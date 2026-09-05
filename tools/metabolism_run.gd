extends SceneTree

## METABOLISM-A live: what does the hardware actually do?
##
##   godot --headless --path . --script tools/metabolism_run.gd -- --probe
##   godot --headless --path . --script tools/metabolism_run.gd -- --run
##
## Pre-registered in docs/EXPERIMENT_METABOLISM.md at 858f1ab.
##
## THIS IS AN ANATOMY RUN, NOT A HYPOTHESIS TEST, and that was recorded before
## it was written. Seven of the eight pre-registered statistics cannot fail
## live: they are regression guards, proven offline by sabotage where the
## invariants actually live. Only REQUEST_FAILED and statistic 3 in M2 can be
## falsified by a GPU. Everything else here is description, and description is
## what an anatomy is for.
##
## RESIDENCY TRUTH COMES FROM THE RUNTIME, NEVER FROM THE ARBITER. The arbiter
## is fed what LM Studio reports as loaded, not what the arbiter predicted it
## had loaded. Feeding it its own forecast would be comparing arithmetic to
## arithmetic and congratulating both copies.
##
## FOUR RESIDENCY EVENTS, NEVER INFERRED FROM DISAPPEARANCE. A model that is
## gone was unloaded, or was never there, or vanished unexpectedly, and those
## are different facts. They are logged separately.
##
## DENIAL IS NOT FAILURE. A DENIED verdict is the metabolism working. An HTTP
## error or a model that will not load is infrastructure failing. Merging them
## into one "could not think" number would hide the only thing a GPU can
## falsify here.
##
## RESIDENCY NEVER REACHES THE AGENT. The audit layer sees everything below.
## The local view stays the same three fields it has always been, or this first
## live run quietly becomes an adaptive-resource-sensing experiment as well.

const B := preload("res://scripts/arena/swarm_bid.gd")
const Q := preload("res://scripts/arena/swarm_request.gd")
const J := preload("res://scripts/arena/metabolism_join.gd")
const A := preload("res://scripts/arena/compute_arbiter.gd")
const V := preload("res://scripts/arena/vram.gd")

var LM_BASE := LMEndpoint.base_url()
const TRANSCRIPT_DIR := "user://live_matches"
const RESULTS := "user://metabolism_a.json"

## The real bindings on this box, with the quantisation the catalog reports.
## NOT the abstract CLASS_PARAMS the offline teeth use -- those exist to test
## the arbiter's arithmetic, these are what the card will actually load.
const CLASS_MODEL := {
	"SMALL": "gemma-3-1b-it-fast-guff",
	"NORMAL": "h2o-danube3-4b-chat",
	"HEAVY": "adg-alpaca-gpt4-qwen2.5-7b",
}
const CLASS_B := {"SMALL": 1.0, "NORMAL": 4.0, "HEAVY": 7.0}
const CLASS_QUANT := {"SMALL": "Q8_0", "NORMAL": "Q4_K_M", "HEAVY": "Q4_K_M"}

const MATCH_TURNS := 10
const MATCHES := 2
const SEED_TURNS := 8
const AIRTIME_WINDOW := 20
const NAMED_WINDOW := 3
const MAX_TOKENS := 110

const ARMS := ["M0", "M1", "M2", "M3"]

var _http: HTTPRequest
var _mode := ""
var _rows: Array[Dictionary] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if str(a) == "--probe":
			_mode = "probe"
		if str(a) == "--run":
			_mode = "run"
	if _mode == "":
		printerr("need --probe or --run")
		quit(2)
		return

	_http = HTTPRequest.new()
	get_root().add_child(_http)
	await process_frame
	_http.timeout = 600.0

	if _mode == "probe":
		await _probe()
		return
	await _live()


# ------------------------------------------------------------ resource truth

## What the RUNTIME says is loaded. Returns class names, not model ids, because
## that is the vocabulary the arbiter speaks.
func _resident() -> Array:
	var out: Array = []
	_http.cancel_request()
	if _http.request(LM_BASE.replace("/v1", "") + "/api/v0/models") != OK:
		return out
	var res: Array = await _http.request_completed
	if int(res[1]) != 200:
		return out
	var p = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(p) != TYPE_DICTIONARY:
		return out
	for m in p.get("data", []):
		if str(m.get("state", "not-loaded")) == "not-loaded":
			continue
		for cls in CLASS_MODEL:
			if str(m.get("id", "")) == str(CLASS_MODEL[cls]):
				if not out.has(cls):
					out.append(cls)
	return out


## Real VRAM in use, in GB, straight from the driver.
func _vram_used_gb() -> float:
	var out: Array = []
	var rc := OS.execute("nvidia-smi",
		["--query-gpu=memory.used", "--format=csv,noheader,nounits"], out, true)
	if rc != 0 or out.is_empty():
		return -1.0
	return float(str(out[0]).strip_edges().split("\n")[0]) / 1024.0


func _predicted_gb(cls: String) -> float:
	if not CLASS_B.has(cls):
		return 0.0
	return V.estimate_gb(float(CLASS_B[cls]), str(CLASS_QUANT[cls]))


## Classify what happened to residency, rather than inferring it from absence.
func _residency_events(before: Array, after: Array, wanted: String) -> Dictionary:
	var ev := {"loaded_by_us": [], "already_resident": [], "unloaded": [],
		"missing_unexpectedly": []}
	for cls in after:
		if not before.has(cls):
			ev["loaded_by_us"].append(cls)
	for cls in before:
		if not after.has(cls):
			ev["unloaded"].append(cls)
	if wanted != "":
		if before.has(wanted):
			ev["already_resident"].append(wanted)
		elif not after.has(wanted):
			# We asked for it, it generated, and the runtime still does not
			# report it. That is not an eviction and must not be logged as one.
			ev["missing_unexpectedly"].append(wanted)
	return ev


# ------------------------------------------------------------------- probe

func _probe() -> void:
	print("=== METABOLISM-A probe: bindings, residency truth, calibration ===\n")
	var base := await _vram_used_gb()
	print("  driver VRAM in use at rest: %.2f GB" % base)
	print("  budget the arbiter plans against: %.2f GB\n" % V.DEFAULT_BUDGET_GB)

	print("  class bindings and PREDICTED residency:")
	for cls in A.LADDER:
		print("    %-7s %-46s %-8s %.2f GB"
			% [cls, str(CLASS_MODEL[cls]), str(CLASS_QUANT[cls]),
				_predicted_gb(str(cls))])
	var hs := _predicted_gb("HEAVY") + _predicted_gb("SMALL")
	var hn := _predicted_gb("HEAVY") + _predicted_gb("NORMAL")
	print("\n    HEAVY + SMALL  %.2f GB   %s" % [hs,
		"fits" if hs <= V.DEFAULT_BUDGET_GB else "DOES NOT FIT"])
	print("    HEAVY + NORMAL %.2f GB   %s" % [hn,
		"fits" if hn <= V.DEFAULT_BUDGET_GB else "DOES NOT FIT"])
	if absf(hs - V.DEFAULT_BUDGET_GB) < 0.01:
		print("\n    NOTE: HEAVY + SMALL lands EXACTLY on the budget with the real")
		print("    bindings. The <= boundary, which was unreachable with the")
		print("    abstract catalog, is live on this box.")

	print("\n  runtime residency right now: %s" % str(await _resident()))

	# Measured ABOVE THE RESTING BASELINE, not as a delta from the previous
	# model. A delta is unreadable here, because this runtime unloads the
	# previous model before loading the next -- so the difference is (new load
	# minus old unload) and comes out NEGATIVE for anything smaller than its
	# predecessor. The first probe reported NORMAL at -1.98 GB for exactly that
	# reason, which is not shrinkage, it is an eviction hiding inside a
	# subtraction.
	print("\n  calibration, one model at a time. PREDICTED vs ACTUAL RESIDENT:")
	for cls in A.LADDER:
		var t0 := Time.get_ticks_msec()
		var reply := await _ask(str(CLASS_MODEL[cls]), "Say the word ready.")
		var ms := Time.get_ticks_msec() - t0
		var after := await _vram_used_gb()
		var res := await _resident()
		if reply == "":
			print("    %-7s REQUEST FAILED (infrastructure, not a denial)" % cls)
			continue
		var actual := after - base
		print("    %-7s predicted %.2f  actual %.2f  error %+.2f  %6d ms  resident %s"
			% [cls, _predicted_gb(str(cls)), actual,
				actual - _predicted_gb(str(cls)), ms, str(res)])
		if res.size() > 1:
			print("      NOTE: more than one class resident at once.")
	print("\n  this is a calibration table, not a pass/fail bar.")
	quit(0)


# -------------------------------------------------------------------- live

func _live() -> void:
	_load()
	var files := _transcripts()
	if files.is_empty():
		printerr("no transcripts for match seeds")
		quit(2)
		return
	print("=== METABOLISM-A: %d arms x %d matches x %d turns ===\n"
		% [ARMS.size(), MATCHES, MATCH_TURNS])
	for arm in ARMS:
		for m in MATCHES:
			if _recorded(str(arm), m):
				continue
			await _play(str(files[m]), str(arm), m)
			_save()
	_report()


func _play(path: String, arm: String, match_index: int) -> void:
	var turns := _load_turns(path)
	if turns.size() < SEED_TURNS + 2:
		return
	var roster := _roster(turns)
	var history: Array = turns.slice(0, SEED_TURNS)

	# M2 is the HARDWARE POSITIVE CONTROL. It forces NORMAL resident before the
	# match so that a HEAVY request MUST meet real scarcity. If M2 never
	# produces a downgrade, the residency manipulation did not happen and the
	# live experiment is broken -- that is the one thing this arm is for.
	if arm == "M2":
		var warm := await _ask(str(CLASS_MODEL["NORMAL"]), "Say the word ready.")
		if warm == "":
			printerr("  M2 could not preload NORMAL; the control is void")

	for t in MATCH_TURNS:
		var prev := str(history[history.size() - 1]["speaker"])
		var entries: Array = []
		for agent_v in roster:
			var agent := str(agent_v)
			if agent == prev:
				continue
			var view := _local_view(agent, history)
			if not B.should_bid(view):
				continue
			var cls := Q.request(view)
			if cls == "":
				continue
			# M0 is the NORMAL-only baseline regime: the request policy runs,
			# and every request is pinned to NORMAL so the arm measures the
			# world without escalation.
			if arm == "M0":
				cls = "NORMAL"
			entries.append({"agent_id": agent, "eligible": true,
				"bid": B.compute(view), "requested_class": cls})

		var resident_before := await _resident()
		var vram_before := await _vram_used_gb()
		var d: Dictionary = J.allocate(entries, resident_before, A.LADDER,
			CLASS_B, V.DEFAULT_BUDGET_GB)

		var row := {"arm": arm, "match": match_index, "turn": t,
			"agent": str(d["speaker"]), "bid": 0.0,
			"requested_class": str(d["requested_class"]),
			"outcome": str(d["outcome"]), "granted_class": str(d["granted_class"]),
			"execute_class": str(d["execute_class"]),
			"arbiter_code": str(d["arbiter_code"]),
			"resolver_code": str(d["resolver_code"]),
			"resident_before": resident_before, "resident_after": [],
			"predicted_gb": 0.0, "vram_before_gb": vram_before,
			"vram_after_gb": vram_before, "latency_ms": 0,
			"request_failed": false, "executed_model": "",
			"model_matched": false, "events": {}}
		for e in entries:
			if str(e["agent_id"]) == str(d["speaker"]):
				row["bid"] = float(e["bid"])

		if not J.executes(d):
			# DENIED, or no speaker at all. Nothing runs, and this is the
			# metabolism working, not a failure.
			row["resident_after"] = resident_before
			_rows.append(row)
			continue

		var cls_run := str(d["execute_class"])
		var model_id := str(CLASS_MODEL[cls_run])
		row["predicted_gb"] = _predicted_gb(cls_run)
		var t0 := Time.get_ticks_msec()
		var reply := await _ask_full(model_id, _prompt(str(d["speaker"]), history))
		row["latency_ms"] = Time.get_ticks_msec() - t0
		row["resident_after"] = await _resident()
		row["vram_after_gb"] = await _vram_used_gb()
		row["events"] = _residency_events(resident_before,
			row["resident_after"], cls_run)

		if str(reply.get("text", "")) == "":
			# INFRASTRUCTURE, kept strictly separate from DENIED.
			row["request_failed"] = true
			_rows.append(row)
			continue

		# Proof the backend obeyed the grant, from the response itself.
		row["executed_model"] = str(reply.get("model", ""))
		row["model_matched"] = row["executed_model"] == model_id
		history.append({"turn": SEED_TURNS + t, "speaker": str(d["speaker"]),
			"text": str(reply["text"])})
		_rows.append(row)

	print("  %s match %d/%d done" % [arm, match_index + 1, MATCHES])


func _prompt(speaker: String, history: Array) -> String:
	var recent := ""
	for k in range(maxi(history.size() - 3, 0), history.size()):
		recent += "\n" + str(history[k]["speaker"]) + ": " + str(history[k]["text"])
	return ("You are %s in a live debate arena. Reply in two sentences, in "
		+ "character.\n\nRecent turns:%s\n\nRespond as %s.") \
		% [speaker, recent.strip_edges(), speaker]


# ---------------------------------------------------------------- reporting

func _report() -> void:
	print("\n--- METABOLISM-A anatomy ---\n")
	for arm in ARMS:
		var req := {}
		var out := {}
		var exec_counts := {}
		var lat := {}
		var turns := 0
		var failed := 0
		var mismatched := 0
		var denials := {}
		for r in _rows:
			if str(r["arm"]) != arm:
				continue
			turns += 1
			var rc := str(r["requested_class"])
			req[rc] = int(req.get(rc, 0)) + 1
			var oc := str(r["outcome"])
			out[oc] = int(out.get(oc, 0)) + 1
			if bool(r["request_failed"]):
				failed += 1
			if str(r["execute_class"]) != "":
				var ec := str(r["execute_class"])
				exec_counts[ec] = int(exec_counts.get(ec, 0)) + 1
				if not lat.has(ec):
					lat[ec] = []
				lat[ec].append(int(r["latency_ms"]))
				if not bool(r["model_matched"]) and not bool(r["request_failed"]):
					mismatched += 1
			if oc == A.DENIED:
				var code := str(r["arbiter_code"])
				denials[code] = int(denials.get(code, 0)) + 1
		if turns == 0:
			continue
		print("  %s  %d turns" % [arm, turns])
		print("      requested        %s" % str(req))
		print("      outcomes         %s" % str(out))
		print("      executed         %s" % str(exec_counts))
		print("      denial codes     %s" % str(denials))
		print("      REQUEST_FAILED   %d   (infrastructure, not denial)" % failed)
		print("      model mismatches %d   (executor disobeyed the grant)" % mismatched)
		for cls in lat:
			var arr: Array = lat[cls]
			var total := 0
			for x in arr:
				total += int(x)
			print("      latency %-7s %6d ms mean over %d" % [cls,
				int(float(total) / float(arr.size())), arr.size()])

	print("\n  calibration: predicted vs observed VRAM delta on a load")
	for r in _rows:
		var ev: Dictionary = r.get("events", {})
		if typeof(ev) == TYPE_DICTIONARY and (ev.get("loaded_by_us", []) as Array).size() > 0:
			print("    %-7s predicted %.2f  observed %.2f  (%s)"
				% [str(r["execute_class"]), float(r["predicted_gb"]),
					float(r["vram_after_gb"]) - float(r["vram_before_gb"]),
					str(ev["loaded_by_us"])])

	var m2_downgrades := 0
	for r in _rows:
		if str(r["arm"]) == "M2" and str(r["outcome"]) == A.DOWNGRADED:
			m2_downgrades += 1
	print("\n  HARDWARE POSITIVE CONTROL")
	if m2_downgrades > 0:
		print("    M2 produced %d real downgrade(s). Scarcity was reachable."
			% m2_downgrades)
	else:
		printerr("    M2 PRODUCED NO DOWNGRADE. Either the residency manipulation")
		printerr("    did not happen or the live path is broken. The anatomy from")
		printerr("    the other arms is not interpretable.")
	print("\n  Read against docs/EXPERIMENT_METABOLISM.md. This is anatomy, not a test.")
	quit(0)


# --------------------------------------------------------------- generation

func _ask(model: String, text: String) -> String:
	var r := await _ask_full(model, text)
	return str(r.get("text", ""))


func _ask_full(model: String, prompt: String) -> Dictionary:
	var payload := {"model": model,
		"messages": [{"role": "user", "content": prompt}],
		"max_tokens": MAX_TOKENS, "temperature": 0.0, "stream": false}
	_http.cancel_request()
	if _http.request(LM_BASE + "/chat/completions",
			["Content-Type: application/json"], HTTPClient.METHOD_POST,
			JSON.stringify(payload)) != OK:
		return {}
	var res: Array = await _http.request_completed
	if int(res[1]) != 200:
		return {}
	var parsed = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("choices"):
		return {}
	return {"text": str(parsed["choices"][0]["message"].get("content", "")).strip_edges(),
		"model": str(parsed.get("model", ""))}


# ------------------------------------------------------------------ material

func _local_view(agent: String, history: Array) -> Dictionary:
	var since := 0
	var found := false
	for k in range(history.size() - 1, -1, -1):
		if str(history[k]["speaker"]) == agent:
			since = (history.size() - 1) - k
			found = true
			break
	if not found:
		since = history.size()
	var start := maxi(history.size() - AIRTIME_WINDOW, 0)
	var mine := 0
	var total := 0
	for k in range(start, history.size()):
		total += 1
		if str(history[k]["speaker"]) == agent:
			mine += 1
	var share := 0.0 if total == 0 else float(mine) / float(total)
	var handle := str(agent.split(" ", false)[0]).to_lower()
	var named := false
	for k in range(maxi(history.size() - NAMED_WINDOW, 0), history.size()):
		if str(history[k]["speaker"]) == agent:
			continue
		if str(history[k]["text"]).to_lower().find(handle) != -1:
			named = true
			break
	return B.local_view(since, named, share)


func _transcripts() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(TRANSCRIPT_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".jsonl"):
			out.append(TRANSCRIPT_DIR.path_join(f))
		f = d.get_next()
	out.sort()
	out.reverse()
	return out


func _load_turns(path: String) -> Array:
	var out: Array = []
	var fh := FileAccess.open(path, FileAccess.READ)
	if fh == null:
		return out
	while not fh.eof_reached():
		var line := fh.get_line()
		if line.strip_edges() == "":
			continue
		var d = JSON.parse_string(line)
		if typeof(d) != TYPE_DICTIONARY or d.get("kind", "") != "turn":
			continue
		out.append({"turn": int(d.get("turn", 0)),
			"speaker": str(d.get("display_name", "")),
			"text": str(d.get("text", ""))})
	fh.close()
	return out


func _roster(turns: Array) -> Array:
	var seen := {}
	var out: Array = []
	for t in turns:
		var s := str(t["speaker"])
		if not seen.has(s):
			seen[s] = true
			out.append(s)
	return out


func _recorded(arm: String, match_index: int) -> bool:
	for r in _rows:
		if str(r["arm"]) == arm and int(r["match"]) == match_index:
			return true
	return false


func _load() -> void:
	var fh := FileAccess.open(RESULTS, FileAccess.READ)
	if fh == null:
		return
	var p = JSON.parse_string(fh.get_as_text())
	fh.close()
	if typeof(p) == TYPE_DICTIONARY:
		for row in p.get("rows", []):
			_rows.append(row)


func _save() -> void:
	var fh := FileAccess.open(RESULTS, FileAccess.WRITE)
	if fh == null:
		return
	fh.store_string(JSON.stringify({"rows": _rows}, "\t"))
	fh.close()
