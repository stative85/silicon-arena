extends SceneTree

## RUNTIME-MEMORY, one arm. BUILD-ONLY UNTIL EXPLICITLY CLEARED TO RUN.
##
##   godot --headless --path . --script tools/runtime_memory.gd -- \
##       --arm=IDLE|CONTROL_WORKLOAD|RECOVERY_ONLY|FULL_WINDOW --windows=20
##
## ONLY THE WORKLOAD DIFFERS BETWEEN ARMS. Pool, load order, cadences, horizon,
## sampling, witness schema and termination rules are identical by construction
## -- they are constants here, not parameters, so an arm cannot quietly acquire
## its own settings.
##
## THIS FILE CANNOT RESTART THE BACKEND. It contains no unload-all, no server
## start/stop, no process kill, and no LM Studio launch. Backend lifetime is the
## orchestrator's business and changes only at an arm boundary. That is enforced
## two ways: a static check in the self-test, and a live PID witness here -- the
## LM Studio process set is captured at arm start and re-verified at every
## sample, so a restart mid-arm VOIDS the arm instead of silently splicing two
## unrelated trajectories into one.
##
## CLIENT DISCONNECT IS A MEASURED PHASE, NOT CLEANUP. This process cannot
## observe its own absence, so it writes a final live-client sample and exits;
## the orchestrator samples afterwards while the backend stays alive.

const B := preload("res://scripts/arena/inference_bridge.gd")
const C := preload("res://scripts/arena/async_contract.gd")
const M := preload("res://scripts/arena/bridge_model.gd")
const RA := preload("res://scripts/arena/recovery_action.gd")

const POOL := ["liquidai/lfm2.5-1.2b-instruct", "qwen3.5-2b",
	"falcon-h1-1.5b-instruct"]

## Identical across every arm. Constants, not parameters.
const WINDOW_MS := 40000          ## matches the RC window
const SAMPLE_MS := 2000           ## resource sampling cadence
const PROBE_LIST_LEN := 10        ## fixed, so the denominator cannot move
const RECOVERY_AT_MS := 10000     ## within a window, arms C and D

const IDLE := "IDLE"
const CONTROL_WORKLOAD := "CONTROL_WORKLOAD"
const RECOVERY_ONLY := "RECOVERY_ONLY"
const FULL_WINDOW := "FULL_WINDOW"

var _arm := IDLE
var _windows := 40
var _bridge: InferenceBridge
var _http: HTTPRequest
var _http_rec: HTTPRequest
var _pending := 0
var _last: Dictionary = {}
var _samples: Array = []
var _events: Array = []
var _problems: Array = []
var _t0 := 0
var _requests := 0
var _completions := 0
var _prompt_tokens := 0
var _recoveries := 0
var _pids: Array = []
var _rec_running := false


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--arm="):
			_arm = s.substr(6)
		elif s.begins_with("--windows="):
			_windows = int(s.substr(10))
	_run.call_deferred()


## LM Studio process ids. The treatment boundary is "one backend lifetime per
## arm", so this set must not change while an arm is running.
func _backend_pids() -> Array:
	var out: Array = []
	OS.execute("tasklist", PackedStringArray(["/FI", "IMAGENAME eq LM Studio.exe",
		"/FO", "CSV", "/NH"]), out, false, false)
	var pids: Array = []
	if out.is_empty():
		return pids
	for ln in str(out[0]).split("\n"):
		var parts := str(ln).split("\",\"")
		if parts.size() > 1:
			var p := str(parts[1]).replace("\"", "").strip_edges()
			if p.is_valid_int():
				pids.append(int(p))
	pids.sort()
	return pids


func _same_pids(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if int(a[i]) != int(b[i]):
			return false
	return true


func _lms_rss_mb() -> float:
	var out: Array = []
	OS.execute("tasklist", PackedStringArray(["/FI", "IMAGENAME eq LM Studio.exe",
		"/FO", "CSV", "/NH"]), out, false, false)
	var total := 0.0
	if out.is_empty():
		return -1.0
	for ln in str(out[0]).split("\n"):
		var parts := str(ln).split("\",\"")
		if parts.size() >= 5:
			var mem := str(parts[4]).replace("\"", "").replace(",", "")
			mem = mem.replace(" K", "").replace("K", "").strip_edges()
			if mem.is_valid_int():
				total += float(int(mem)) / 1024.0
	return total


func _vram() -> Array:
	var out: Array = []
	OS.execute("nvidia-smi", PackedStringArray([
		"--query-gpu=memory.used,memory.total",
		"--format=csv,noheader,nounits"]), out, false, false)
	if out.is_empty():
		return [-1, -1]
	var parts := str(out[0]).strip_edges().split(",")
	if parts.size() < 2:
		return [-1, -1]
	return [int(str(parts[0]).strip_edges()), int(str(parts[1]).strip_edges())]


func _sample(phase: String) -> void:
	var pids := _backend_pids()
	if not _pids.is_empty() and not _same_pids(pids, _pids):
		_problems.append("BACKEND_RESTARTED_MID_ARM: %s -> %s"
			% [str(_pids), str(pids)])
	var mem := OS.get_memory_info()
	var v := _vram()
	var counts := await RA.residency_counts(_http, POOL)
	_samples.append({
		"arm": _arm, "phase": phase,
		"elapsed_ms": Time.get_ticks_msec() - _t0,
		"lms_rss_mb": _lms_rss_mb(),
		"host_free_mb": int(float(mem.get("free", 0)) / 1048576.0),
		"vram_used_mib": v[0], "vram_total_mib": v[1],
		"requests": _requests, "completions": _completions,
		"prompt_tokens": _prompt_tokens, "recoveries": _recoveries,
		"residency_counts": counts,
		"backend_pids": pids,
	})


func _visible(window: int, probe: int) -> Array:
	var ids: Array = []
	for k in 16:
		ids.append("r_%02d" % k)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(("RM|%d|%d" % [window, probe]).sha256_text()
		.substr(0, 15).hex_to_int())
	for k in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var t = ids[k]
		ids[k] = ids[j]
		ids[j] = t
	return ids.slice(0, PROBE_LIST_LEN)


func _payload(vis: Array) -> Dictionary:
	return {
		"messages": [{"role": "user", "content": C.prompt(vis)}],
		"max_tokens": 24, "temperature": 0.0,
		"response_format": {"type": "json_schema", "json_schema": {
			"name": "async_action", "strict": true, "schema": C.schema()}},
	}


func _run() -> void:
	_t0 = Time.get_ticks_msec()
	print("=== RUNTIME-MEMORY arm %s ===" % _arm)
	if not [IDLE, CONTROL_WORKLOAD, RECOVERY_ONLY, FULL_WINDOW].has(_arm):
		print("FAIL unknown arm")
		quit(1)
		return
	print("windows %d, window %d ms, sample every %d ms"
		% [_windows, WINDOW_MS, SAMPLE_MS])

	_http = HTTPRequest.new()
	get_root().add_child(_http)
	_http_rec = HTTPRequest.new()
	get_root().add_child(_http_rec)
	_bridge = B.new()
	get_root().add_child(_bridge)
	await process_frame

	_pids = _backend_pids()
	print("backend pids at arm start: %s" % str(_pids))
	if _pids.is_empty():
		print("FAIL no backend process found")
		quit(1)
		return

	await _bridge.refresh_residency()
	for mid in POOL:
		if _bridge.models.has(mid):
			(_bridge.models[mid] as BridgeModel).set_state(M.HOT, "observed", 0)
	_bridge.health.shadow = true
	_bridge.completed.connect(func(_rid, ok, _text, rec):
		_last[str(rec.get("model_id", ""))] = {"ok": ok, "rec": rec}
		if ok:
			_completions += 1
			_prompt_tokens += maxi(int(rec.get("prompt_tokens", 0)), 0)
		_pending -= 1)

	await _sample("arm_start")
	for w in _windows:
		await _one_window(w)
		_write(false)
	await _sample("final_live_client")
	print("  final live-client sample taken; the orchestrator measures the")
	print("  disconnect phase, since this process cannot observe its own exit")
	_write(true)


func _one_window(w: int) -> void:
	var start := Time.get_ticks_msec()
	var next_sample := start
	var probe := 0
	var did_recovery := false
	while Time.get_ticks_msec() - start < WINDOW_MS:
		var into := Time.get_ticks_msec() - start
		if Time.get_ticks_msec() >= next_sample:
			await _sample("window_%d" % w)
			next_sample = Time.get_ticks_msec() + SAMPLE_MS

		# The one thing that differs between arms.
		if (_arm == RECOVERY_ONLY or _arm == FULL_WINDOW) \
				and not did_recovery and into >= RECOVERY_AT_MS:
			did_recovery = true
			var target := str(POOL[w % POOL.size()])
			var neigh: Array = []
			for m in POOL:
				if m != target:
					neigh.append(m)
			_rec_running = true
			_do_recovery(target, neigh)

		if _arm == CONTROL_WORKLOAD or _arm == FULL_WINDOW:
			var vis := _visible(w, probe)
			_last.clear()
			_pending = POOL.size() - 1
			var n := 0
			for m in POOL:
				if _arm == FULL_WINDOW and did_recovery \
						and str(m) == str(POOL[w % POOL.size()]):
					continue
				if n >= POOL.size() - 1:
					break
				_requests += 1
				n += 1
				_bridge.submit("rm", str(m), _payload(vis))
			var guard := Time.get_ticks_msec() + 60000
			while _pending > 0 and Time.get_ticks_msec() < guard:
				await process_frame
			probe += 1
		else:
			await process_frame

	var rguard := Time.get_ticks_msec() + 120000
	while _rec_running and Time.get_ticks_msec() < rguard:
		await process_frame
	await _sample("window_%d_end" % w)


func _do_recovery(target: String, neighbours: Array) -> void:
	var ra := RA.new()
	var wit: Dictionary = await ra.perform(_http_rec, target, neighbours)
	_recoveries += 1
	_events.append({"kind": "recovery", "target": target,
		"verdict": str(wit["verdict"]),
		"elapsed_ms": Time.get_ticks_msec() - _t0})
	if str(wit["verdict"]) != RA.VALID:
		_problems.append("recovery not verified: " + str(wit.get("reason", "")))
	_rec_running = false


func _write(final: bool) -> void:
	var f := FileAccess.open("res://docs/results/RUNTIME_MEMORY_%s.json" % _arm,
		FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"arm": _arm, "windows": _windows, "window_ms": WINDOW_MS,
			"sample_ms": SAMPLE_MS, "probe_list_len": PROBE_LIST_LEN,
			"pool": POOL, "backend_pids_at_start": _pids,
			"samples": _samples, "events": _events, "problems": _problems,
		}, "  "))
		f.close()
	if final:
		print("\n[ARM %s] samples %d, requests %d, completions %d, recoveries %d"
			% [_arm, _samples.size(), _requests, _completions, _recoveries])
		for p in _problems:
			print("  PROBLEM: %s" % str(p))
		print("  wrote docs/results/RUNTIME_MEMORY_%s.json" % _arm)
		quit(0)
