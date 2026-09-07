extends SceneTree

## Gate 1: is the frozen equalizer delay feasible under REAL queue pressure?
##
##   godot --headless --path . --script tools/async_equalizer_check.gd
##
## BRIDGE ONLY. No world, no resource outcomes, no arms, no arm comparisons.
## Just the bridge under the submission pattern ASYNC-A will actually create.
##
## WHY THIS EXISTS. The 750 ms equalizer was justified against measured SOLO
## small-prompt latencies of roughly 190-580 ms. That is the wrong load regime.
## The bridge runs max_active = 2 and ASYNC-A agents observe together, so they
## submit together:
##
##     3 submitted  ->  2 active  ->  1 queued
##
## A queued request may be perfectly healthy and still complete more than 750 ms
## after its observation because it waited for a slot. That would raise
## EQUALIZER_BREACH and void arm 3 while every subsystem behaves correctly --
## not because equalization failed, and not because a model was slow, but
## because a scheduler queue exists.
##
## FIRST-PASS DISCIPLINE, as with the world calibration: accept the first
## candidate delay that survives, stop, and freeze it. Do NOT search for the
## prettiest number. If 750 ms survives, it is kept unchanged.

const B := preload("res://scripts/arena/inference_bridge.gd")
const C := preload("res://scripts/arena/async_contract.gd")
const M := preload("res://scripts/arena/bridge_model.gd")
const R := preload("res://scripts/arena/bridge_receipt.gd")
const HL := preload("res://scripts/arena/bridge_health.gd")

## Declared before any output.
const CANDIDATES := [750, 1000, 1250, 1500, 2000]
const BURSTS := 60
const AGENTS := 3          ## preregistered; see Amendment 6

var _bridge: InferenceBridge
var _models: Array[String] = []
var _pending := 0
var _burst: Array = []
var _uniq := 0


func _init() -> void:
	_run.call_deferred()


## An ASYNC-A shaped request: a short list of ids, one field back. Unique every
## time, so prefix caching cannot make a queued request look fast.
func _payload() -> Dictionary:
	_uniq += 1
	var ids: Array = []
	for i in 16:
		ids.append("r_%02d_%d" % [i, _uniq])
	return {
		"messages": [{"role": "user", "content": C.prompt(ids)}],
		"max_tokens": 24,
		"temperature": 0.0,
		"response_format": {"type": "json_schema", "json_schema": {
			"name": "async_action", "strict": true, "schema": C.schema()}},
	}


func _run() -> void:
	print("=== ASYNC-A equalizer feasibility (Gate 1) ===")
	print("BRIDGE ONLY. No world, no arms, no outcomes.\n")

	_bridge = B.new()
	get_root().add_child(_bridge)
	await process_frame

	var resident := await _bridge.refresh_residency()
	for mid in _bridge.policy.hot_set:
		if resident.has(mid):
			_models.append(mid)
			(_bridge.models[mid] as BridgeModel).set_state(M.HOT, "observed", 0)
	if _models.size() < AGENTS:
		print("Need %d hot models resident, found %d: %s"
			% [AGENTS, _models.size(), str(_models)])
		quit(1)
		return

	print("agents        %d (one per hot-set model)" % AGENTS)
	print("max_active    %d" % _bridge.policy.max_active_normal)
	print("bursts        %d, all agents submitting at the same instant" % BURSTS)
	print("candidates    %s ms\n" % str(CANDIDATES))

	_bridge.completed.connect(func(_rid, _ok, _txt, rec):
		_pending -= 1
		_burst.append(rec))

	# Warmup, discarded.
	for mid in _models:
		await _one(mid)
	_burst.clear()

	print("collecting %d simultaneous bursts..." % BURSTS)
	var samples: Array = []
	var health_events := 0
	var transport_failures := 0
	for b in BURSTS:
		_burst.clear()
		var t0 := Time.get_ticks_msec()
		_pending = AGENTS
		for i in AGENTS:
			_bridge.submit("eq_%d" % i, _models[i], _payload())
		while _pending > 0:
			await process_frame
		for rec in _burst:
			var elapsed := int(rec.get("finished_at_ms", 0)) - t0
			samples.append({"model": str(rec["model_id"]),
				"elapsed_ms": elapsed,
				"queue_ms": int(rec.get("queue_ms", 0)),
				"status": str(rec.get("status", ""))})
			if str(rec.get("status", "")) != R.STATUS_OK:
				transport_failures += 1
			var v := str(rec.get("health_verdict", ""))
			if v == HL.DEGRADED or v == HL.CATASTROPHE:
				health_events += 1

	print("  samples %d, transport failures %d, health interventions %d\n"
		% [samples.size(), transport_failures, health_events])

	# Observation-to-completion, which is what the equalizer must cover.
	var all_ms: Array = []
	var by_model := {}
	for s in samples:
		var d: Dictionary = s
		all_ms.append(int(d["elapsed_ms"]))
		var k := str(d["model"])
		if not by_model.has(k):
			by_model[k] = []
		(by_model[k] as Array).append(int(d["elapsed_ms"]))
	all_ms.sort()
	print("observation-to-completion under queue pressure:")
	print("  %-32s %5s %7s %7s %7s" % ["MODEL", "n", "median", "p95", "max"])
	for k in by_model:
		var v: Array = by_model[k]
		v.sort()
		print("  %-32s %5d %7d %7d %7d"
			% [k, v.size(), int(v[v.size() / 2]),
			   int(v[mini(int(v.size() * 0.95), v.size() - 1)]),
			   int(v[v.size() - 1])])
	print("  %-32s %5d %7d %7d %7d\n"
		% ["ALL", all_ms.size(), int(all_ms[all_ms.size() / 2]),
		   int(all_ms[mini(int(all_ms.size() * 0.95), all_ms.size() - 1)]),
		   int(all_ms[all_ms.size() - 1])])

	print("first candidate delay with zero breaches wins; no further search\n")
	print("  %-8s %10s %s" % ["delay_ms", "breaches", ""])
	var chosen := -1
	for cand in CANDIDATES:
		var breaches := 0
		for ms in all_ms:
			if int(ms) > int(cand):
				breaches += 1
		var mark := ""
		if breaches == 0 and transport_failures == 0 and health_events == 0:
			mark = "<- PASS, taken"
		elif breaches > 0:
			mark = "%d healthy completions exceed it" % breaches
		else:
			mark = "blocked by transport/health events"
		print("  %-8d %10d %s" % [int(cand), breaches, mark])
		if mark.begins_with("<-"):
			chosen = int(cand)
			break

	print("")
	if chosen < 0:
		print("NO CANDIDATE PASSED. Arm 3 is not feasible at this queue")
		print("pressure with the declared candidates. Reported as such; the")
		print("candidate list is not extended to manufacture feasibility.")
		quit(1)
		return
	print("FROZEN EQUALIZER DELAY: %d ms" % chosen)
	if chosen == 750:
		print("  unchanged -- 750 ms survives real three-agent queue pressure")
	else:
		print("  CHANGED from 750 ms. Amendment 4's constant must be updated")
		print("  and EQUALIZED_DELAY_TICKS recomputed: %d ms / 250 ms = %d ticks"
			% [chosen, chosen / 250])

	var out := {"candidates": CANDIDATES, "bursts": BURSTS, "agents": AGENTS,
		"max_active": _bridge.policy.max_active_normal,
		"samples": samples.size(), "transport_failures": transport_failures,
		"health_interventions": health_events,
		"median_ms": int(all_ms[all_ms.size() / 2]),
		"max_ms": int(all_ms[all_ms.size() - 1]),
		"chosen_delay_ms": chosen}
	var f := FileAccess.open("res://docs/results/ASYNC_A_EQUALIZER.json",
		FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "  "))
		f.close()
		print("\nwrote docs/results/ASYNC_A_EQUALIZER.json")
	quit(0)


func _one(mid: String) -> void:
	_pending = 1
	_bridge.submit("warm", mid, _payload())
	while _pending > 0:
		await process_frame
