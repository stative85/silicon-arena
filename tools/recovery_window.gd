extends SceneTree

## RECOVERY-COUPLING window executor.
##
##   godot --headless --path . --script tools/recovery_window.gd -- \
##       --run-kind=QUALIFICATION --windows=0,1,20,21,40,41 [--inject=21]
##
## TREATMENT and CONTROL differ in ONE physical operation and nothing else:
##
##   TREATMENT                      CONTROL
##     read residency                 read residency
##     unload designated target       (matched read-only residency read)
##     read residency                 read residency
##     reload target                  (matched read-only residency read)
##     read residency                 read residency
##     target liveness call           target liveness call
##     neighbour probes               neighbour probes
##
## Same nominal target, same liveness prompt, same neighbour prompts, same probe
## ordering, same logging, same gate sampling. NO FAKE SLEEPS are inserted to
## imitate how long unload/reload took -- that command latency IS the treatment,
## and padding the control to match would control the causal mechanism out of
## the causal experiment.
##
## CONTAMINATION INJECTION IS FORBIDDEN IN AN EXPERIMENT RUN. `--inject` exists
## to prove the executor HONOURS a gate verdict rather than logging it and
## marching onward, and it is refused outright when run_kind is EXPERIMENT.

const B := preload("res://scripts/arena/inference_bridge.gd")
const C := preload("res://scripts/arena/async_contract.gd")
const M := preload("res://scripts/arena/bridge_model.gd")
const RA := preload("res://scripts/arena/recovery_action.gd")
const RG := preload("res://scripts/arena/recovery_gate.gd")
const RP := preload("res://scripts/arena/recovery_probe.gd")

const SCHEDULE := "res://docs/results/RC_SCHEDULE.json"
const QUALIFICATION := "QUALIFICATION"
const EXPERIMENT := "EXPERIMENT"

var _run_kind := QUALIFICATION
var _want: Array = []
var _inject := -1
var _tag := "qual"

var _bridge: InferenceBridge
var _sched: Dictionary = {}
var _pool: Array = []
var _expected_counts: Dictionary = {}
## SEPARATE HTTP NODES. A single HTTPRequest cannot service two overlapping
## requests, and the concurrent-recovery fix made the gate's residency sampling
## overlap the recovery's own residency reads. Qualification caught this: all
## three TREATMENT windows voided on "HTTPRequest is processing a request".
## The gate and the recovery therefore own separate transports.
var _http: HTTPRequest          ## gate sampling only
var _http_rec: HTTPRequest      ## recovery action and liveness only
var _pending := 0
var _last: Dictionary = {}
var _records: Array = []
var _windows_out: Array = []
var _recovery_epoch := 0
var _rec_running := false
var _rec_witness: Dictionary = {}
var _rec_done_ms := -1


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--run-kind="):
			_run_kind = s.substr(11)
		elif s.begins_with("--windows="):
			for p in s.substr(10).split(","):
				_want.append(int(p))
		elif s.begins_with("--inject="):
			_inject = int(s.substr(9))
		elif s.begins_with("--tag="):
			_tag = s.substr(6)
	_run.call_deferred()


func _run() -> void:
	print("=== RECOVERY-COUPLING window executor ===")
	print("run_kind %s   windows %s" % [_run_kind, str(_want)])

	if _inject >= 0 and _run_kind == EXPERIMENT:
		print("FAIL contamination injection requested in an EXPERIMENT run.")
		print("     --inject exists only to prove the executor honours a gate")
		print("     verdict during QUALIFICATION. Refusing to start.")
		quit(1)
		return
	if _inject >= 0:
		print("inject  synthetic contamination into window %d" % _inject)

	var f := FileAccess.open(SCHEDULE, FileAccess.READ)
	if f == null:
		print("FAIL no schedule; run tools/recovery_schedule.py first")
		quit(1)
		return
	_sched = JSON.parse_string(f.get_as_text())
	f.close()
	_pool = _sched["models"]
	_expected_counts = RA.expect_one_each(_pool)
	print("schedule hash %s, pool %s\n" % [str(_sched["schedule_hash"]),
		str(_pool)])

	_http = HTTPRequest.new()
	get_root().add_child(_http)
	_http_rec = HTTPRequest.new()
	get_root().add_child(_http_rec)
	_bridge = B.new()
	get_root().add_child(_bridge)
	await process_frame
	await _bridge.refresh_residency()
	for mid in _pool:
		if _bridge.models.has(mid):
			(_bridge.models[mid] as BridgeModel).set_state(M.HOT, "observed", 0)
	# Shadow mode is how "no verdict-triggered recovery" is enforced
	# STRUCTURALLY rather than merely detected: the health system cannot fire a
	# reload at all, so the schedule is the only source of recovery.
	_bridge.health.shadow = true
	print("health shadow %s (verdict-triggered recovery is impossible)\n"
		% str(_bridge.health.shadow))

	_bridge.completed.connect(func(_rid, ok, _text, rec):
		_last[str(rec.get("model_id", ""))] = {"ok": ok, "rec": rec}
		_pending -= 1)

	for wid in _want:
		var w: Dictionary = _sched["windows"][wid]
		await _one_window(w)
		# INCREMENTAL WRITE. A 60-window run that only persists at the
		# end loses every completed window to a crash in a later one.
		_write(false)

	_write(true)


func _one_window(w: Dictionary) -> void:
	var wid := int(w["window_id"])
	var cond := str(w["condition"])
	var target := str(w["recovered_model"])
	var neighbours: Array = w["neighbours"]
	print("\n--- window %d  %s  recover=%s ---"
		% [wid, cond, RA.base_id(target, _pool)])

	var gate := RG.new()
	gate.begin(wid, _expected_counts)
	var t0 := Time.get_ticks_msec()
	var probe_i := 0
	var recovery_done_ms := -1
	var witness: Dictionary = {}
	var recovery_verified := false
	var epoch := -1

	# PHASE 1 -- pre
	var s: Dictionary = await gate.sample(_http, "pre", 0)
	print("  pre        counts=%s gate=%s" % [str(s["counts"]), str(s["reason"])])
	probe_i = await _probe_until(w, gate, neighbours, t0,
		int(w["pre_ms"]), probe_i, recovery_done_ms, recovery_verified, epoch)

	# PHASE 2 -- the one differing operation.
	#
	# The recovery is launched WITHOUT await so neighbour probing continues
	# THROUGH the unload/reload. The observed coupling appeared 7-9 s after the
	# verdict, i.e. around the reload, so a design that pauses probing during
	# the recovery would miss the entire interval of interest.
	if cond == RP.TREATMENT:
		_rec_running = true
		_rec_witness = {}
		_rec_done_ms = -1
		# The target's absence here is SCHEDULED, so it is declared to the gate
		# rather than voiding the window. Cleared the moment recovery ends.
		gate.flex_model = RA.base_id(target, _pool)
		_do_recovery(target, neighbours, t0)
	else:
		# MATCHED OBSERVATION BURDEN: the same three residency reads and the
		# same liveness call the treatment path performs. No unload, no reload,
		# and deliberately no sleep to imitate their duration.
		await gate.sample(_http, "control_read_1", Time.get_ticks_msec() - t0)
		await gate.sample(_http, "control_read_2", Time.get_ticks_msec() - t0)
		await gate.sample(_http, "control_read_3", Time.get_ticks_msec() - t0)
		var live: bool = await RA.liveness(_http_rec, target)
		_rec_done_ms = Time.get_ticks_msec() - t0
		recovery_done_ms = _rec_done_ms
		print("  control    matched reads + liveness=%s at +%d ms"
			% [str(live), recovery_done_ms])

	if wid == _inject:
		print("  INJECT     synthetic unscheduled recovery (qualification only)")
		gate.note_unscheduled_recovery("synthetic", Time.get_ticks_msec() - t0)

	# PHASE 3 -- post
	probe_i = await _probe_until(w, gate, neighbours, t0,
		int(w["pre_ms"]) + int(w["post_ms"]), probe_i, recovery_done_ms,
		recovery_verified, epoch)
	# Wait out any still-running recovery, then clear the declared absence.
	var rguard := Time.get_ticks_msec() + 120000
	while _rec_running and Time.get_ticks_msec() < rguard:
		await process_frame
	gate.flex_model = ""
	if cond == RP.TREATMENT:
		witness = _rec_witness
		recovery_verified = str(witness.get("verdict", "")) == RA.VALID
		epoch = int(witness.get("new_epoch", -1)) if recovery_verified else -1
		recovery_done_ms = _rec_done_ms
		print("  recovery   verdict=%s epoch %d->%d done at +%d ms"
			% [str(witness.get("verdict", "?")), int(witness.get("old_epoch", -1)),
			   int(witness.get("new_epoch", -1)), recovery_done_ms])
		if not recovery_verified:
			gate.note_transport("recovery not verified: "
				+ str(witness.get("reason", "")), recovery_done_ms)

	var send: Dictionary = await gate.sample(_http, "post", Time.get_ticks_msec() - t0)
	print("  post       counts=%s gate=%s" % [str(send["counts"]),
		str(send["reason"])])

	# restore exact counts before leaving the window
	for m in _pool:
		await RA.ensure_loaded(_http_rec, str(m))
	var final: Dictionary = await RA.residency_counts(_http_rec, _pool)
	var restored := RA.counts_match(final, _expected_counts)
	if not restored:
		gate.note_transport("pool not restored: " + str(final),
			Time.get_ticks_msec() - t0)

	# STAMP AND VALIDATE AT WINDOW END. A probe taken mid-reload cannot know the
	# recovery outcome yet, so records are finalised once, here, against the
	# window's settled result. A TREATMENT window that produced no verified
	# recovery therefore fails validation on every one of its records, which is
	# exactly the intended behaviour.
	var wctx := {
		"window_id": wid, "schedule_hash": str(_sched["schedule_hash"]),
		"condition": cond, "recovered_model": target,
		"actual_recovery_epoch": epoch, "recovery_verified": recovery_verified,
		"expected_counts": _expected_counts,
	}
	var invalid := 0
	for r in _records:
		var rr: Dictionary = r
		if int(rr.get("window_id", -1)) != wid:
			continue
		rr["actual_recovery_epoch"] = epoch
		rr["recovery_verified"] = recovery_verified
		if recovery_done_ms >= 0:
			rr["ms_since_recovery_completion"] = 				int(rr["ms_since_window_start"]) - recovery_done_ms
		var bad := RP.validate(rr, wctx, neighbours)
		if not bad.is_empty():
			rr["validation_problems"] = bad
			invalid += 1
	if invalid > 0:
		gate.note_transport("%d invalid probe records" % invalid,
			Time.get_ticks_msec() - t0)
	var in_window := 0
	for r2 in _records:
		if int((r2 as Dictionary).get("window_id", -1)) == wid:
			in_window += 1
	print("  probes     %d records this window, %d invalid"
		% [in_window, invalid])

	var env := gate.envelope()
	# THE EXECUTOR HONOURS THE VERDICT. A void window's records are retained as
	# evidence of the void and marked, never silently kept as clean data.
	print("  gate       void=%s reason=%s offences=%d"
		% [str(env["void"]), str(env["void_reason"]), int(env["offence_count"])])
	_windows_out.append({
		"window_id": wid, "condition": cond, "recovered_model": target,
		"neighbours": neighbours, "run_kind": _run_kind,
		"evidence_eligible": _run_kind == EXPERIMENT and not bool(env["void"]),
		"recovery_verified": recovery_verified,
		"recovery_epoch": epoch, "recovery_witness": witness,
		"recovery_done_ms": recovery_done_ms,
		"gate": env, "restored": restored,
		"probes": probe_i,
	})


## Runs the verified recovery alongside the probe loop. Never awaited by the
## caller, so probing continues through the unload and the reload.
func _do_recovery(target: String, neighbours: Array, t0: int) -> void:
	var ra := RA.new()
	ra.residency_epoch = _recovery_epoch
	_rec_witness = await ra.perform(_http_rec, target, neighbours)
	_recovery_epoch = ra.residency_epoch
	_rec_done_ms = Time.get_ticks_msec() - t0
	_rec_running = false


## Probe both neighbours simultaneously until `until_ms` into the window.
func _probe_until(w: Dictionary, gate, neighbours: Array, t0: int,
		until_ms: int, probe_i: int, rec_done_ms: int,
		recovery_verified: bool, epoch: int) -> int:
	var i := probe_i
	while Time.get_ticks_msec() - t0 < until_ms:
		var elapsed := Time.get_ticks_msec() - t0
		var vis := _visible(int(w["window_id"]), i)
		_last.clear()
		_pending = neighbours.size()
		for n in neighbours:
			_bridge.submit("rc", str(n), _payload(vis))
		var guard := Time.get_ticks_msec() + 60000
		while _pending > 0 and Time.get_ticks_msec() < guard:
			await process_frame
		var gs: Dictionary = await gate.sample(_http, "probe", elapsed)
		for n in neighbours:
			var e: Dictionary = _last.get(str(n), {})
			if e.is_empty():
				gate.note_transport("no completion for " + str(n), elapsed)
				continue
			var wctx := {
				"window_id": int(w["window_id"]),
				"schedule_hash": str(_sched["schedule_hash"]),
				"condition": str(w["condition"]),
				"recovered_model": str(w["recovered_model"]),
				"actual_recovery_epoch": epoch,
				"recovery_verified": recovery_verified,
				"expected_counts": _expected_counts,
			}
			var ms_since_rec := -1
			if rec_done_ms >= 0:
				ms_since_rec = elapsed - rec_done_ms
			var r := RP.make(wctx, str(n), i, "probe", e["rec"], gs,
				elapsed, ms_since_rec)
			r["run_kind"] = _run_kind
			r["evidence_eligible"] = _run_kind == EXPERIMENT
			_records.append(r)
		i += 1
	return i


func _visible(window_id: int, probe_index: int) -> Array:
	var ids: Array = []
	for k in 16:
		ids.append("r_%02d" % k)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(("RC|%d|%d" % [window_id, probe_index])
		.sha256_text().substr(0, 15).hex_to_int())
	for k in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var t = ids[k]
		ids[k] = ids[j]
		ids[j] = t
	return ids.slice(0, int(_sched["probe_list_len"]))


func _payload(visible: Array) -> Dictionary:
	return {
		"messages": [{"role": "user", "content": C.prompt(visible)}],
		"max_tokens": 24, "temperature": 0.0,
		"response_format": {"type": "json_schema", "json_schema": {
			"name": "async_action", "strict": true, "schema": C.schema()}},
	}


func _write(final: bool) -> void:
	var voided := 0
	for w in _windows_out:
		if bool((w as Dictionary)["gate"]["void"]):
			voided += 1
	if final:
		print("\n[SUMMARY] %s" % _run_kind)
		print("  windows %d, void %d, probe records %d"
			% [_windows_out.size(), voided, _records.size()])
	var path := "res://docs/results/RC_%s_%s.json" % [_run_kind, _tag]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"run_kind": _run_kind,
			"evidence_eligible": _run_kind == EXPERIMENT,
			"schedule_hash": str(_sched["schedule_hash"]),
			"pool": _pool, "expected_counts": _expected_counts,
			"injected_window": _inject,
			"windows": _windows_out, "records": _records,
		}, "  "))
		f.close()
		if final:
			print("  wrote %s" % path)
	if final:
		quit(0)
