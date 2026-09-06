extends SceneTree

## Make the bridge characterise ITSELF. Bridge-native timing collection.
##
##   godot --headless --path . --script tools/bridge_collect.gd -- --n 60
##
## Every threshold in the bridge today is global and was derived from the
## external benchmark, not from the bridge's own streaming path. This collects
## the distributions the per-model bands will later be derived FROM, so those
## bands arrive from measurement rather than from imagination in a lab coat.
##
## THE REGIME IS FROZEN FOR THE WHOLE RUN.
##   hot set        lfm2.5 + danube2 + falcon, explicit residency, 8192, Q4_K_M
##   max_active     2
##   no swapping, no policy tuning, no band changes mid-run
##
## THE MATRIX: MODEL x PROMPT_BUCKET x ACTIVE_LOAD. No combined score. A single
## number would average away the exact structure the bands need.
##
## ACTIVE_LOAD IS OBSERVED, NOT ASSUMED. Samples are binned by
## `max_active_during` -- the peak concurrency each request actually
## experienced. `active_at_dispatch` is not enough: the FIRST request of a
## concurrent pair is always dispatched alone and then overlapped for most of
## its life, so binning on dispatch would file genuinely contended calls as
## uncontended and empty one model's contended cell entirely.
##
## HEALTHY BASELINE EXCLUSIONS. A call is excluded from the healthy reference
## if any existing bridge invariant fired. Excluded records are KEPT in the raw
## dataset with a reason -- they are runtime evidence, just not healthy
## reference samples.

const B := preload("res://scripts/arena/inference_bridge.gd")
const R := preload("res://scripts/arena/bridge_receipt.gd")
const M := preload("res://scripts/arena/bridge_model.gd")
const T := preload("res://scripts/arena/bridge_ticket.gd")

## Default grid. `--low` switches to the tiny grid below.
const BUCKETS_DEFAULT := ["SMALL", "MEDIUM", "LARGE"]

## LOW-END GRID. Live arena traffic measured 20-22 tokens, BELOW the smallest
## knot in the frozen expectation (47-60). There the expectation clamps, which
## is conservative against false positives AND against detection: a genuinely
## degraded tiny request can look healthier than it is because the denominator
## is too generous. This grid measures the region the arena actually uses.
##
## The question is whether the low end continues the first knot or whether
## there is a startup floor. If TTFT is essentially flat below ~45 tokens
## because connection and runtime overhead dominate, clamping is already the
## correct policy and no knot need be added.
const BUCKETS_LOW := ["T16", "T24", "T40"]

var BUCKETS: Array = BUCKETS_DEFAULT
const OUT_JSON := "D:/bridge_timing.json"
const OUT_JSON_LOW := "D:/bridge_timing_low.json"
const OUT_MD := "res://docs/results/BRIDGE_TIMING.md"
const OUT_MD_LOW := "res://docs/results/BRIDGE_TIMING_LOW.md"

var _n_per_cell := 60
var _bridge: InferenceBridge
var _models: Array[String] = []
var _pending := 0
var _records: Array = []
var _order := 0
var _uniq := 0
var _low := false


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--n="):
			_n_per_cell = int(s.substr(4))
		if s == "--low":
			BUCKETS = BUCKETS_LOW
			_low = true
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if str(args[i]) == "--n" and i + 1 < args.size():
			_n_per_cell = int(args[i + 1])
	_run.call_deferred()


# ------------------------------------------------------------------ prompts

## Three realistic sizes. Prompt size is stratified so it cannot quietly
## become the next fake pathology -- a model that looks slow only because its
## bucket was larger has not demonstrated anything about itself.
## EVERY PROMPT IS UNIQUE, and this matters more than it looks. LM Studio
## caches the prompt prefix. Repeating one identical prompt makes the first
## call pay full prefill -- measured at 3,343-5,990 ms on LARGE -- and every
## later call a cache hit at 75-292 ms. An envelope built from cache hits
## would be far too tight, and bands derived from it would flag ordinary arena
## traffic as SUSPECT: the wrong generating distribution, measured precisely.
##
## In the real arena every observation differs because the world changed, so
## every call pays real prefill. The varying prefix here reproduces that.
func _prompt(bucket: String) -> Dictionary:
	_uniq += 1
	var salt := "%d-%d" % [_uniq, Time.get_ticks_msec()]
	var world := "cycle=%s\n" % salt
	match bucket:
		# Tiny grid. The standard instruction wrapper alone is ~20 tokens, so
		# the low end uses a minimal instruction -- otherwise the wrapper, not
		# the world, would set the floor and the grid would measure nothing.
		"T16":
			return _tiny("Act. c=%s" % salt)
		"T24":
			return _tiny("Choose one action now. cycle=%s ok" % salt)
		"T40":
			return _tiny(("Choose one action for this world and say why. "
				+ "cycle=%s rule_1 memory_1 tool_1") % salt)
		"SMALL":
			world += "[objects]\n  \"rule_%d\" type=\"rule\"\n" % _uniq
		"MEDIUM":
			var body := ""
			for i in 20:
				body += ("  \"obj_%d_%d\" type=\"rule\" props={\"text\":"
					+ "\"line %d of %s\"}\n") % [i, _uniq, i, salt]
			world += "[objects]\n" + body
		"LARGE":
			var body2 := ""
			for i in 120:
				body2 += ("  \"obj_%d_%d\" type=\"memory\" props={\"text\":"
					+ "\"the arena records a canonical world of typed "
					+ "objects, entry %d of %s\"}\n") % [i, _uniq, i, salt]
			world += "[objects]\n" + body2
	return {
		"messages": [{"role": "user",
			"content": ("Given this world, choose one action and explain "
				+ "briefly.\n" + world + "\nAnswer in two sentences.")}],
		"max_tokens": 64,
		"temperature": 0.0,
	}


## A minimal request. Same uniqueness discipline as the main grid: the salt
## defeats prefix caching, because a cached prefill is a different generating
## distribution from a novel one.
func _tiny(text: String) -> Dictionary:
	return {
		"messages": [{"role": "user", "content": text}],
		"max_tokens": 24,
		"temperature": 0.0,
	}


# --------------------------------------------------------------------- run

func _run() -> void:
	print("=== bridge-native timing collection ===")
	print("Bridge characterising itself. No model quality claims.\n")

	_bridge = B.new()
	get_root().add_child(_bridge)
	await process_frame

	var resident := await _bridge.refresh_residency()
	for mid in _bridge.policy.hot_set:
		if resident.has(mid):
			_models.append(mid)
			(_bridge.models[mid] as BridgeModel).set_state(M.HOT, "observed", 0)
	if _models.size() < 2:
		print("Need at least 2 hot models resident; found %s" % str(_models))
		print("Load the hot set first, then re-run.")
		quit(1)
		return

	print("regime:")
	print("  hot set      %s" % str(_models))
	print("  max_active   %d" % _bridge.policy.max_active_normal)
	print("  context      %d" % _bridge.policy.context_length)
	print("  n per cell   %d" % _n_per_cell)
	print("  buckets      %s\n" % str(BUCKETS))

	_bridge.completed.connect(_on_done)

	# Warmups, discarded. Never enter any statistic.
	print("warmup...")
	for mid in _models:
		for b in BUCKETS:
			await _one(mid, b, "WARMUP")
	_records.clear()
	_order = 0

	var t0 := Time.get_ticks_msec()

	print("\n[A] UNCONTENDED  one active request")
	for b in BUCKETS:
		for mid in _models:
			for i in _n_per_cell:
				await _one(mid, b, "collect")
			print("   %-9s %-32s done" % [b, mid])

	print("\n[B] TWO-WAY  two active requests, rotating pairs")
	var pairs: Array = []
	for i in _models.size():
		for j in range(i + 1, _models.size()):
			pairs.append([_models[i], _models[j]])
	# Each pair yields one sample per participant. With 3 models and 3 pairs,
	# every model appears in 2 of 3 pairs, so rounds are sized accordingly.
	var rounds := int(ceil(float(_n_per_cell) * float(pairs.size())
		/ float(maxi(pairs.size() - 1, 1)) / 1.0))
	for b in BUCKETS:
		for r in rounds:
			var p: Array = pairs[r % pairs.size()]
			await _two(str(p[0]), str(p[1]), b)
		print("   %-9s %d rounds done" % [b, rounds])

	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	print("\ncollected %d records in %.1f s" % [_records.size(), elapsed])

	_analyse()
	quit(0)


func _on_done(_rid: String, _ok: bool, _text: String, rec: Dictionary) -> void:
	_pending -= 1
	var r := rec.duplicate(true)
	r["order"] = _order
	_order += 1
	_records.append(r)


func _one(mid: String, bucket: String, tag: String) -> void:
	_pending += 1
	var rid := _bridge.submit("collector", mid, _prompt(bucket))
	_tag(rid, bucket, tag)
	while _pending > 0:
		await process_frame


func _two(a: String, b: String, bucket: String) -> void:
	_pending += 2
	var r1 := _bridge.submit("collector", a, _prompt(bucket))
	var r2 := _bridge.submit("collector", b, _prompt(bucket))
	_tag(r1, bucket, "collect")
	_tag(r2, bucket, "collect")
	while _pending > 0:
		await process_frame


var _tags := {}


func _tag(rid: String, bucket: String, tag: String) -> void:
	_tags[rid] = {"bucket": bucket, "tag": tag}


# ---------------------------------------------------------------- statistics

func _pct(sorted_vals: Array, q: float) -> float:
	if sorted_vals.is_empty():
		return -1.0
	var idx := int(round(q * float(sorted_vals.size() - 1)))
	return float(sorted_vals[clampi(idx, 0, sorted_vals.size() - 1)])


func _median(sorted_vals: Array) -> float:
	return _pct(sorted_vals, 0.5)


## Why a call is not a healthy reference sample. Kept in the raw dataset.
func _exclusion(rec: Dictionary) -> String:
	var st := str(rec.get("status", ""))
	if st != R.STATUS_OK:
		return "status:" + st
	if str(rec.get("failure_kind", "")) != "":
		return "failure_kind:" + str(rec.get("failure_kind"))
	if int(rec.get("ttft_ms", -1)) < 0:
		return "no_ttft"
	if int(rec.get("ttft_ms", 0)) > _bridge.policy.hard_degraded_ttft_ms:
		return "hard_degraded_ttft"
	var after := str(rec.get("model_state_after", ""))
	if after != M.HOT and after != "":
		return "model_state:" + after
	return ""


## Are slow calls clustered into persistent regimes, or isolated spikes?
##
## The observed longest run of consecutive slow calls is compared against the
## same values shuffled many times. If reality routinely beats chance, the
## slowness is a state the model enters and stays in -- which argues for
## "N consecutive suspect calls -> recovery" rather than reloading on one
## unusual call and thrashing the pool.
func _runs(values: Array) -> Dictionary:
	var n := values.size()
	if n < 8:
		return {"n": n, "insufficient": true}
	var srt := values.duplicate()
	srt.sort()
	var thresh := _pct(srt, 0.75)
	var flags: Array = []
	for v in values:
		flags.append(1 if float(v) > thresh else 0)
	var observed := _longest_run(flags)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260906
	var trials := 200
	var ge := 0
	var total := 0.0
	for t in trials:
		var sh := flags.duplicate()
		# Fisher-Yates
		for i in range(sh.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = sh[i]
			sh[i] = sh[j]
			sh[j] = tmp
		var lr := _longest_run(sh)
		total += float(lr)
		if lr >= observed:
			ge += 1
	return {
		"n": n,
		"slow_threshold_ms": thresh,
		"longest_slow_run": observed,
		"shuffled_mean_longest_run": total / float(trials),
		"p_shuffled_ge_observed": float(ge) / float(trials),
		"lag1_autocorr": _lag1(values),
	}


func _longest_run(flags: Array) -> int:
	var best := 0
	var cur := 0
	for f in flags:
		if int(f) == 1:
			cur += 1
			best = maxi(best, cur)
		else:
			cur = 0
	return best


func _lag1(values: Array) -> float:
	var n := values.size()
	if n < 3:
		return 0.0
	var mean := 0.0
	for v in values:
		mean += float(v)
	mean /= float(n)
	var num := 0.0
	var den := 0.0
	for i in n:
		var d := float(values[i]) - mean
		den += d * d
		if i > 0:
			num += (float(values[i - 1]) - mean) * d
	return 0.0 if den == 0.0 else num / den


func _cell_stats(recs: Array, field: String) -> Dictionary:
	var vals: Array = []
	for r in recs:
		var v := int(r.get(field, -1))
		if v >= 0:
			vals.append(v)
	vals.sort()
	if vals.is_empty():
		return {"n": 0}
	return {
		"n": vals.size(),
		"min": vals[0],
		"median": _median(vals),
		"p90": _pct(vals, 0.90),
		"p95": _pct(vals, 0.95),
		"p99": _pct(vals, 0.99),
		"max": vals[vals.size() - 1],
		"iqr": _pct(vals, 0.75) - _pct(vals, 0.25),
	}


# ------------------------------------------------------------------ analysis

func _analyse() -> void:
	var healthy: Array = []
	var excluded: Array = []
	for r in _records:
		var why := _exclusion(r)
		r["exclusion_reason"] = why
		if why == "":
			healthy.append(r)
		else:
			excluded.append(r)

	print("\nhealthy reference samples: %d   excluded: %d"
		% [healthy.size(), excluded.size()])
	if not excluded.is_empty():
		var by := {}
		for r in excluded:
			var k := str(r["exclusion_reason"])
			by[k] = int(by.get(k, 0)) + 1
		print("exclusions: %s" % str(by))

	var lines: Array[String] = []
	var w := func(s: String) -> void: lines.append(s)

	w.call("# Bridge-Native Timing — Healthy Envelope")
	w.call("")
	w.call("**Regime:** bridge v1, `EXPLICIT_RESIDENCY_MODE`, context 8192, "
		+ "Q4_K_M, `max_active = 2`.")
	w.call("Hot set frozen for the whole run; no swapping, no policy tuning, "
		+ "no band changes mid-run.")
	w.call("")
	w.call("**Instrument:** `tools/bridge_collect.gd`. Timings come from the "
		+ "bridge's own streaming path, so `ttft_ms` is real "
		+ "first-content latency.")
	w.call("")
	w.call("No combined score. A single number would average away the "
		+ "structure the bands need.")
	w.call("")
	w.call("> **Read `CENSORED` cells carefully.** The healthy-baseline filter "
		+ "excludes TTFT > 1500 ms, which is the current global "
		+ "`HARD_DEGRADED` tooth. In cells where healthy large-prompt prefill "
		+ "approaches that value, the filter removes the upper tail of the "
		+ "very distribution the bands are meant to be derived from. Those "
		+ "cells' `p95`/`p99` are **lower bounds, not estimates**.")
	w.call("")
	w.call("```")
	w.call("healthy reference samples  %d" % healthy.size())
	w.call("excluded from baseline     %d" % excluded.size())
	w.call("```")
	w.call("")

	# The matrix.
	var fields := ["queue_ms", "connect_ms", "ttft_ms",
		"generation_after_first_ms", "total_ms"]
	for field in fields:
		w.call("## %s" % field)
		w.call("")
		w.call("```")
		w.call("%-9s %-8s %-5s %5s %7s %7s %7s %7s %7s %7s"
			% ["MODEL", "BUCKET", "load", "n", "median", "p90", "p95", "p99",
			   "min", "max"])
		for mid in _models:
			for b in BUCKETS:
				for load in [1, 2]:
					var cell: Array = []
					for r in healthy:
						if str(r["model_id"]) != mid:
							continue
						if str(_tags.get(r["request_id"], {}).get("bucket", "")) != b:
							continue
						if int(r.get("max_active_during", 0)) != load:
							continue
						cell.append(r)
					var st := _cell_stats(cell, field)
					if int(st.get("n", 0)) == 0:
						continue
					# Excluding TTFT > 1500 ms right-censors this cell's upper
					# tail. Where that happened often, the envelope is not a
					# clean distribution and must not be read as one.
					var exc := _excluded_in_cell(excluded, mid, b, load)
					var mark := ""
					if exc > 0:
						var rate := float(exc) / float(int(st["n"]) + exc)
						mark = " CENSORED %d (%.0f%%)" % [exc, rate * 100.0]
					w.call("%-9s %-8s %-5d %5d %7.0f %7.0f %7.0f %7.0f %7.0f %7.0f%s"
						% [_short(mid), b, load, int(st["n"]),
						   float(st["median"]), float(st["p90"]),
						   float(st["p95"]), float(st["p99"]),
						   float(st["min"]), float(st["max"]), mark])
		w.call("```")
		w.call("")

	# Serial correlation, on TTFT only -- the health signal.
	w.call("## Serial correlation of TTFT")
	w.call("")
	w.call("Are slow calls isolated spikes, or persistent regimes? The observed "
		+ "longest run of consecutive slow calls (above the cell's own p75) is "
		+ "compared with 200 shuffles of the same values.")
	w.call("")
	w.call("`p` is the fraction of shuffles matching or beating the observed "
		+ "run. A low `p` means the slowness clusters more than chance allows.")
	w.call("")
	w.call("```")
	w.call("%-9s %-8s %-5s %5s %9s %8s %9s %7s"
		% ["MODEL", "BUCKET", "load", "n", "slow>ms", "run", "shuffled", "p"])
	var clustered := 0
	var tested := 0
	for mid in _models:
		for b in BUCKETS:
			for load in [1, 2]:
				var vals: Array = []
				for r in healthy:
					if str(r["model_id"]) != mid:
						continue
					if str(_tags.get(r["request_id"], {}).get("bucket", "")) != b:
						continue
					if int(r.get("max_active_during", 0)) != load:
						continue
					vals.append(int(r.get("ttft_ms", 0)))
				var rr := _runs(vals)
				if bool(rr.get("insufficient", false)) or int(rr.get("n", 0)) == 0:
					continue
				tested += 1
				if float(rr["p_shuffled_ge_observed"]) < 0.05:
					clustered += 1
				w.call("%-9s %-8s %-5d %5d %9.0f %8d %9.2f %7.3f"
					% [_short(mid), b, load, int(rr["n"]),
					   float(rr["slow_threshold_ms"]),
					   int(rr["longest_slow_run"]),
					   float(rr["shuffled_mean_longest_run"]),
					   float(rr["p_shuffled_ge_observed"])])
	w.call("```")
	w.call("")
	w.call("**%d of %d cells show clustering beyond chance (p < 0.05).**"
		% [clustered, tested])
	w.call("")

	w.call("## Exclusions")
	w.call("")
	w.call("Excluded records are kept in the raw dataset with a reason. They "
		+ "are runtime evidence, not healthy reference samples.")
	w.call("")
	w.call("```")
	if excluded.is_empty():
		w.call("none")
	else:
		w.call("%-9s %-8s %-5s %-26s %s"
			% ["MODEL", "BUCKET", "load", "reason", "ttft_ms"])
		for r in excluded:
			w.call("%-9s %-8s %-5d %-26s %d"
				% [_short(str(r["model_id"])),
				   str(_tags.get(r["request_id"], {}).get("bucket", "?")),
				   int(r.get("max_active_during", 0)),
				   str(r["exclusion_reason"]), int(r.get("ttft_ms", -1))])
	w.call("```")
	w.call("")
	w.call("## Bands are NOT derived here")
	w.call("")
	w.call("This document freezes distributions only. The per-model `SUSPECT` "
		+ "band is chosen after inspecting these numbers, not before — and the "
		+ "global `HARD_DEGRADED` tooth (TTFT > 1500 ms) stays as it is, "
		+ "because the external benchmark showed a wide gap between healthy "
		+ "hundreds-of-milliseconds behaviour and pathological multi-second "
		+ "TTFT.")

	var text := "\n".join(lines) + "\n"
	var f := FileAccess.open(OUT_MD_LOW if _low else OUT_MD, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	var raw := {"regime": {"bridge": "v1", "max_active":
		_bridge.policy.max_active_normal, "context":
		_bridge.policy.context_length, "hot_set": _models,
		"n_per_cell": _n_per_cell},
		"records": _records, "tags": _tags}
	var jf := FileAccess.open(OUT_JSON_LOW if _low else OUT_JSON, FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(raw))
		jf.close()
	print("\nwrote %s" % (OUT_MD_LOW if _low else OUT_MD))
	print("wrote %s" % (OUT_JSON_LOW if _low else OUT_JSON))
	print("\n%s" % text)


## How many calls in this exact cell were excluded. A censored cell's p95/p99
## are lower bounds, not estimates: the samples that would have set them were
## removed by the very threshold the bands are meant to replace.
func _excluded_in_cell(excluded: Array, mid: String, bucket: String,
		load: int) -> int:
	var n := 0
	for r in excluded:
		if str(r["model_id"]) != mid:
			continue
		if str(_tags.get(r["request_id"], {}).get("bucket", "")) != bucket:
			continue
		if int(r.get("max_active_during", 0)) != load:
			continue
		n += 1
	return n


func _short(mid: String) -> String:
	return mid.get_slice("/", mid.get_slice_count("/") - 1).get_slice("-", 0)
