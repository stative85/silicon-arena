extends SceneTree

## HEALTH-SHORT. Blocker 1: is the frozen expectation surface valid at the short
## prompts ASYNC-B drove the world into?
##
##   godot --headless --path . --script tools/health_short.gd [-- --rounds=120]
##
## NO ECOLOGY. No world, no agents, no representation, no outcomes. Only the
## bridge, the frozen surface, and a swept prompt length.
##
## NOTHING IS FITTED HERE. No knot is added, moved, or re-measured; ks/kh/n are
## untouched. The question is whether the DENOMINATOR is valid below the regime
## it was fitted in. A residual can be wrong because its numerator moved or
## because its denominator did, and ASYNC-B cannot tell which.
##
## AMENDMENT 1 -- the pool and the load regime are held constant. All three
## models are probed SIMULTANEOUSLY every round, reproducing ASYNC-B's SERIAL
## tick (3 submitted, max_active 2). Probing qwen solo would question a surface
## under conditions it was never fitted or exercised in; co-resident composition
## has already been measured to move contention factors ~20%.
##
## AMENDMENT 2 -- shadow mode. Classification runs exactly as live; only the
## recovery ACTION is suppressed, because a reload IS the Blocker-2 event and
## would both confound this measurement and contaminate every later bucket.
##
## AMENDMENT 3 -- chronology is preserved. Calls are analysed in issue order and
## nothing is shuffled before streak analysis. Residual lag-1 autocorrelation is
## recorded as evidence, with no threshold attached to it.

const B := preload("res://scripts/arena/inference_bridge.gd")
const C := preload("res://scripts/arena/async_contract.gd")
const M := preload("res://scripts/arena/bridge_model.gd")
const R := preload("res://scripts/arena/bridge_receipt.gd")
const HL := preload("res://scripts/arena/bridge_health.gd")

## Brackets ASYNC-B's measured means (A 9.96, C 9.64, B 8.39, D 8.15) and
## extends past both ends. Declared before any output.
const LENGTHS := [16, 14, 12, 10, 8, 6, 4]
const HOST_FLOOR_MB := 2048.0

var _rounds := 120
var _bridge: InferenceBridge
var _models: Array[String] = []
var _pending := 0
var _round: Dictionary = {}
var _samples: Array = []
var _uniq := 0
var _problems: Array = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--rounds="):
			_rounds = int(s.substr(9))
	_run.call_deferred()


## A unique visible list of exactly `n` ids. Uniqueness matters: a repeated
## prompt would be a prefix-cache hit and would make later calls in a bucket
## artificially fast, hiding the very effect under investigation.
func _visible(n: int) -> Array:
	_uniq += 1
	var ids: Array = []
	for i in 16:
		ids.append("r_%02d" % i)
	# Deterministic rotation + shuffle keyed on the round, so every round in a
	# bucket presents a different subset in a different order.
	var rng := RandomNumberGenerator.new()
	rng.seed = _uniq * 7919 + n
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = ids[i]
		ids[i] = ids[j]
		ids[j] = t
	return ids.slice(0, n)


func _payload(visible: Array) -> Dictionary:
	return {
		"messages": [{"role": "user", "content": C.prompt(visible)}],
		"max_tokens": 24, "temperature": 0.0,
		"response_format": {"type": "json_schema", "json_schema": {
			"name": "async_action", "strict": true, "schema": C.schema()}},
	}


func _run() -> void:
	print("=== HEALTH-SHORT (Blocker 1) ===")
	print("No world. No agents. No fitting. Shadow mode.\n")
	print("lengths   %s" % str(LENGTHS))
	print("rounds    %d per length, all three models each round\n" % _rounds)

	_bridge = B.new()
	get_root().add_child(_bridge)
	await process_frame
	var resident := await _bridge.refresh_residency()
	for mid in _bridge.policy.hot_set:
		if resident.has(mid):
			_models.append(mid)
			(_bridge.models[mid] as BridgeModel).set_state(M.HOT, "observed", 0)
	if _models.size() < 3:
		print("FAIL need the frozen three-model pool, found %s" % str(_models))
		quit(1)
		return
	print("resident  %s" % str(_models))

	# AMENDMENT 2: classification live, recovery suppressed.
	_bridge.health.shadow = true
	print("shadow    %s (recovery suppressed, classification unchanged)"
		% str(_bridge.health.shadow))
	print("ks/kh/n   %.1f / %.1f / %d\n"
		% [_bridge.health.ks, _bridge.health.kh, _bridge.health.streak_n])

	var mem := OS.get_memory_info()
	var free_mb := float(mem.get("free", 0)) / (1024.0 * 1024.0)
	print("host free %.0f MB" % free_mb)
	if free_mb > 0.0 and free_mb < HOST_FLOOR_MB:
		print("FAIL host memory below the frozen floor")
		quit(1)
		return

	_bridge.completed.connect(func(_rid, ok, _text, rec):
		_round[str(rec.get("model_id", ""))] = {"ok": ok, "rec": rec}
		_pending -= 1)

	# Warmup, discarded and recorded as discarded.
	for i in 3:
		await _one_round(16)
	_samples.clear()
	print("3 warmup rounds discarded\n")

	var seen_prompts := {}
	for n in LENGTHS:
		print("  length %2d ..." % n)
		for r in _rounds:
			var vis := await _one_round(n)
			var key := str(vis)
			if seen_prompts.has(key):
				_problems.append("duplicate prompt at length %d" % n)
			seen_prompts[key] = true

	_report()


func _one_round(n: int) -> Array:
	var vis := _visible(n)
	_round.clear()
	_pending = _models.size()
	for mid in _models:
		_bridge.submit("probe", mid, _payload(vis))
	while _pending > 0:
		await process_frame
	for mid in _models:
		var e: Dictionary = _round.get(mid, {})
		if e.is_empty():
			continue
		var rec: Dictionary = e["rec"]
		_samples.append({
			"length": n, "model": mid,
			"ok": bool(e["ok"]),
			"status": str(rec.get("status", "")),
			"prompt_tokens": int(rec.get("prompt_tokens", -1)),
			"ttft_ms": int(rec.get("ttft_ms", -1)),
			"expected_ms": float(rec.get("health_expected_ms", -1.0)),
			"residual": float(rec.get("health_residual", -1.0)),
			"verdict": str(rec.get("health_verdict", "")),
			"streak": int(rec.get("health_streak", 0)),
			"max_active_during": int(rec.get("max_active_during", -1)),
		})
	return vis


func _median(v: Array) -> float:
	if v.is_empty():
		return -1.0
	var s: Array = v.duplicate()
	s.sort()
	return float(s[s.size() / 2])


func _pct(v: Array, p: float) -> float:
	if v.is_empty():
		return -1.0
	var s: Array = v.duplicate()
	s.sort()
	return float(s[mini(int(s.size() * p), s.size() - 1)])


## Lag-1 autocorrelation of the residual series, IN ISSUE ORDER. Evidence only;
## no threshold is attached to it.
func _lag1(v: Array) -> float:
	if v.size() < 3:
		return 0.0
	var mean := 0.0
	for x in v:
		mean += float(x)
	mean /= float(v.size())
	var num := 0.0
	var den := 0.0
	for i in v.size():
		var d := float(v[i]) - mean
		den += d * d
		if i > 0:
			num += d * (float(v[i - 1]) - mean)
	return 0.0 if den == 0.0 else num / den


func _report() -> void:
	print("\n[RESULTS]  chronology preserved; nothing shuffled\n")
	var out: Array = []
	for mid in _models:
		print("%s" % mid)
		print("  %-4s %5s %7s %9s %9s %8s %8s %8s %7s %6s %6s"
			% ["len", "n", "tokens", "ttft_med", "ttft_p95", "exp_med",
			   "res_med", "res_p95", "res_max", "susp", "lag1"])
		for n in LENGTHS:
			var rows: Array = []
			for s in _samples:
				var d: Dictionary = s
				if int(d["length"]) == n and str(d["model"]) == mid \
						and bool(d["ok"]) and int(d["ttft_ms"]) >= 0:
					rows.append(d)
			if rows.is_empty():
				continue
			var tt: Array = []
			var rs: Array = []
			var ex: Array = []
			var tok: Array = []
			var susp := 0
			var maxstreak := 0
			var cur := 0
			for d in rows:
				tt.append(int(d["ttft_ms"]))
				ex.append(float(d["expected_ms"]))
				tok.append(int(d["prompt_tokens"]))
				rs.append(float(d["residual"]))
				var v := str(d["verdict"])
				if v == HL.SUSPECT or v == HL.DEGRADED:
					susp += 1
					cur += 1
					maxstreak = maxi(maxstreak, cur)
				else:
					cur = 0
			var row := {
				"model": mid, "length": n, "n": rows.size(),
				"tokens_med": _median(tok),
				"ttft_med": _median(tt), "ttft_p95": _pct(tt, 0.95),
				"expected_med": _median(ex),
				"residual_med": _median(rs), "residual_p95": _pct(rs, 0.95),
				"residual_max": _pct(rs, 1.0),
				"suspect": susp, "max_streak": maxstreak,
				"lag1_autocorr": _lag1(rs),
			}
			out.append(row)
			print("  %-4d %5d %7d %9.0f %9.0f %8.0f %8.2f %8.2f %7.2f %6d %6.2f"
				% [n, rows.size(), int(row["tokens_med"]),
				   row["ttft_med"], row["ttft_p95"], row["expected_med"],
				   row["residual_med"], row["residual_p95"],
				   row["residual_max"], susp, row["lag1_autocorr"]])
		print("")

	var degraded := 0
	for s in _samples:
		if str((s as Dictionary)["verdict"]) == HL.DEGRADED:
			degraded += 1
	print("DEGRADED verdicts (shadow, no recovery fired): %d" % degraded)
	if not _problems.is_empty():
		for p in _problems:
			print("PROBLEM: %s" % str(p))

	var f := FileAccess.open("res://docs/results/HEALTH_SHORT.json",
		FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"lengths": LENGTHS, "rounds": _rounds, "models": _models,
			"shadow": true, "ks": _bridge.health.ks, "kh": _bridge.health.kh,
			"streak_n": _bridge.health.streak_n,
			"summary": out, "samples": _samples,
			"problems": _problems, "degraded_verdicts": degraded,
		}, "  "))
		f.close()
		print("\nwrote docs/results/HEALTH_SHORT.json")
	quit(0)
