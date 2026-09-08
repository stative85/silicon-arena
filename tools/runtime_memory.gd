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
var _core_pid := -1
var _core_created := ""
var _rec_running := false


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--arm="):
			_arm = s.substr(6)
		elif s.begins_with("--windows="):
			_windows = int(s.substr(10))
	_run.call_deferred()


## PRODUCER-DERIVED BACKEND TELEMETRY.
##
## The previous implementation recorded a bare PID list and compared the
## complete set for equality, so it fired on the model-worker churn that a
## scheduled recovery necessarily causes -- 676 and 582 false offences in
## RUNTIME-MEMORY arms C and D. The invariant it was meant to protect is
## backend/core LIFETIME CONTINUITY, not worker PID identity.
##
## Roles come from what the producer exposes, never from a count learned in a
## previous run:
##
##   core          no --type= flag AND parent is not another LM Studio process
##   model_worker  --type=utility --utility-sub-type=node.mojom.NodeService
##   support       any other --type=
##
## FAILS CLOSED. If the producer field cannot be obtained the sample records
## backend_probe_ok = false and the arm records a problem, rather than
## defaulting to an empty set that would read as "backend gone".
func _backend_probe() -> Dictionary:
	var out: Array = []
	var ps := ("Get-CimInstance Win32_Process -Filter \"Name='LM Studio.exe'\" "
		+ "| ForEach-Object { \"$($_.ProcessId)|$($_.ParentProcessId)|"
		+ "$($_.CreationDate)|$($_.CommandLine)\" }")
	var rc := OS.execute("powershell", PackedStringArray(
		["-NoProfile", "-Command", ps]), out, false, false)
	var res := {"ok": false, "procs": [], "core_pid": -1, "core_created": "",
		"worker_pids": [], "support_pids": [], "pids": []}
	if rc != 0 or out.is_empty():
		return res
	var rows: Array = []
	var by_pid := {}
	for ln in str(out[0]).split("
"):
		var parts := str(ln).split("|", true, 3)
		if parts.size() < 4:
			continue
		var pid_s := str(parts[0]).strip_edges()
		if not pid_s.is_valid_int():
			continue
		var row := {"pid": int(pid_s),
			"parent": int(str(parts[1]).strip_edges()) 				if str(parts[1]).strip_edges().is_valid_int() else -1,
			"created": str(parts[2]).strip_edges(),
			"cmd": str(parts[3])}
		rows.append(row)
		by_pid[row["pid"]] = row
	if rows.is_empty():
		return res
	for r in rows:
		var row: Dictionary = r
		var cmd := str(row["cmd"])
		var pids_all: Array = []
		if not cmd.contains("--type=") and not by_pid.has(int(row["parent"])):
			row["role"] = "core"
		elif cmd.contains("node.mojom.NodeService"):
			row["role"] = "model_worker"
		else:
			row["role"] = "support"
		res["pids"].append(int(row["pid"]))
		if str(row["role"]) == "core":
			res["core_pid"] = int(row["pid"])
			res["core_created"] = str(row["created"])
		elif str(row["role"]) == "model_worker":
			res["worker_pids"].append(int(row["pid"]))
		else:
			res["support_pids"].append(int(row["pid"]))
		res["procs"].append({"pid": int(row["pid"]), "parent": int(row["parent"]),
			"created": str(row["created"]), "role": str(row["role"])})
	(res["pids"] as Array).sort()
	(res["worker_pids"] as Array).sort()
	(res["support_pids"] as Array).sort()
	# A probe that found processes but no identifiable core is NOT ok: the
	# generation witness would be silently absent.
	res["ok"] = int(res["core_pid"]) > 0 and str(res["core_created"]) != ""
	return res


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
	var probe := _backend_probe()
	if not bool(probe["ok"]):
		_problems.append("BACKEND_PROBE_FAILED at %s: producer field "
			% phase + "unavailable; failing closed rather than recording an "
			+ "empty process set")
	else:
		# THE CORRECTED INVARIANT. Worker churn is expected -- a scheduled
		# recovery replaces model workers by design. What must not change is the
		# core identity or its generation.
		if _core_pid > 0 and int(probe["core_pid"]) != _core_pid:
			_problems.append("BACKEND_CORE_CHANGED at %s: core pid %d -> %d"
				% [phase, _core_pid, int(probe["core_pid"])])
		if _core_created != "" and str(probe["core_created"]) != _core_created:
			_problems.append("BACKEND_GENERATION_CHANGED at %s: %s -> %s"
				% [phase, _core_created, str(probe["core_created"])])
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
		# producer-derived backend telemetry, persisted per sample
		"backend_probe_ok": bool(probe["ok"]),
		"backend_pids": probe["pids"],
		"backend_core_pid": int(probe["core_pid"]),
		"backend_core_created": str(probe["core_created"]),
		"backend_worker_pids": probe["worker_pids"],
		"backend_support_pids": probe["support_pids"],
		"backend_procs": probe["procs"],
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

	var p0 := _backend_probe()
	if not bool(p0["ok"]):
		print("FAIL backend probe did not yield a core identity + generation.")
		print("     Failing closed: an arm cannot be integrity-qualified")
		print("     without a producer-derived generation witness.")
		quit(1)
		return
	_pids = p0["pids"]
	_core_pid = int(p0["core_pid"])
	_core_created = str(p0["core_created"])
	print("backend core pid %d created %s; %d workers, %d support"
		% [_core_pid, _core_created, (p0["worker_pids"] as Array).size(),
		   (p0["support_pids"] as Array).size()])

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
			"backend_core_pid_at_start": _core_pid,
			"backend_core_created_at_start": _core_created,
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
