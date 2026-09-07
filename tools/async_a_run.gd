extends SceneTree

## ASYNC-A runner. Deliberately boring.
##
##   godot --headless --path . --script tools/async_a_run.gd -- --dry
##   godot --headless --path . --script tools/async_a_run.gd -- --arm=NATURAL
##
## PRE-RUN   verify frozen config, residents, health, policy hashes
## RUN       StepEngine + AgentState + TimingPolicy + AsyncWorld + Bridge
## POST-RUN  assert immutability, lifecycles, arm teeth, runtime, then seal
##
## MODEL COMPLETION IS NOT WORLD APPLICATION. A bridge completion only fills in
## an envelope. The timing policy decides when that envelope becomes releasable,
## and only StepEngine mutates the world. Nothing else in this file touches
## AsyncWorld.

const W := preload("res://scripts/arena/async_world.gd")
const E := preload("res://scripts/arena/async_envelope.gd")
const S := preload("res://scripts/arena/async_step.gd")
const T := preload("res://scripts/arena/async_timing.gd")
const AG := preload("res://scripts/arena/async_agent.gd")
const C := preload("res://scripts/arena/async_contract.gd")
const G := preload("res://scripts/arena/async_runtime_guard.gd")
const B := preload("res://scripts/arena/inference_bridge.gd")
const M := preload("res://scripts/arena/bridge_model.gd")
const HL := preload("res://scripts/arena/bridge_health.gd")

## Frozen configuration.
const RESOURCES := 16          ## world calibration, first-passing config
const HOLD := 4
const AGENTS := 3              ## preregistered
## Amendment 11: 800 observation ticks for every live arm. The equalized
## lifecycle yields ~0.75 actions/tick, so 800 ticks restores the ~600
## actions/replicate the pre-registration intended for the weakest arm WHILE
## every arm still experiences the same amount of world time. Action counts are
## deliberately NOT equalized between arms: throughput is a downstream
## consequence of the timing treatment and stays an outcome.
const CYCLES := 800
const AGENT_IDS := ["agent_0", "agent_1", "agent_2"]

var _arm := T.NATURAL
var _replicate := 0
var _synthetic := false
var _cycles := CYCLES

var _world: AsyncWorld
var _eng: AsyncStepEngine
var _guard: AsyncRuntimeGuard
var _agents: Array = []
var _bridge: InferenceBridge
var _models: Array[String] = []
var _rng := RandomNumberGenerator.new()

## request_id -> envelope, for in-flight cognition.
var _inflight: Dictionary = {}
var _completed: Array = []
var _run_start_ms := 0

var _model_calls := 0
var _actions_returned := 0
var _shape_failed := 0
var _equalizer_breaches := 0
var _settle_ticks := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--arm="):
			_arm = s.substr(6)
		elif s.begins_with("--replicate="):
			_replicate = int(s.substr(12))
		elif s.begins_with("--cycles="):
			_cycles = int(s.substr(9))
		elif s == "--dry":
			_synthetic = true
	_run.call_deferred()


func replicate_id() -> String:
	return "%s_r%d" % [_arm, _replicate]


# ------------------------------------------------------------------- PRE-RUN

func _pre_run() -> bool:
	print("[PRE-RUN]")
	if not T.ARMS.has(_arm):
		print("  unknown arm: %s" % _arm)
		return false
	print("  arm            %s" % _arm)
	print("  replicate      %s" % replicate_id())
	print("  world          %d resources, hold %d" % [RESOURCES, HOLD])
	print("  agents         %d" % AGENTS)
	print("  cycles         %d" % _cycles)
	print("  tick           %d ms" % T.TICK_MS)
	print("  equalizer      %d ticks (%d ms)"
		% [T.EQUALIZED_DELAY_TICKS, T.EQUALIZED_DELAY_TICKS * T.TICK_MS])
	print("  contract hash  %s" % C.schema_hash())
	print("  synthetic      %s" % str(_synthetic))

	_world = W.make(RESOURCES, HOLD)
	_run_start_ms = Time.get_ticks_msec()
	_eng = S.make(_world, _arm, _run_start_ms)
	_rng.seed = 990000 + _replicate

	for i in AGENTS:
		_agents.append(AG.make(AGENT_IDS[i], "synthetic_%d" % i))

	if _synthetic:
		_guard = G.make(replicate_id(), [])
		_guard.expected_resident_hash = G.hash_set([])
		_guard.begin([], {})
		print("  genesis hash   %s" % _world.canonical_hash())
		return true

	_bridge = B.new()
	get_root().add_child(_bridge)
	await process_frame
	var resident := await _bridge.refresh_residency()
	for mid in _bridge.policy.hot_set:
		if resident.has(mid):
			_models.append(mid)
			(_bridge.models[mid] as BridgeModel).set_state(M.HOT, "observed", 0)
	if _models.size() < AGENTS:
		print("  FAIL need %d hot models, found %d" % [AGENTS, _models.size()])
		return false
	for i in AGENTS:
		(_agents[i] as AsyncAgentState).model_id = _models[i]
	print("  resident       %s" % str(_models))

	_guard = G.make(replicate_id(), _models)
	var states := {}
	for mid in _models:
		states[mid] = (_bridge.models[mid] as BridgeModel).state
	_guard.begin(_models, states)
	_bridge.model_state_changed.connect(
		func(mid, f, t, r): _guard.on_model_state_changed(mid, f, t, r))
	_bridge.recovery.connect(
		func(mid, act, ok): _guard.on_recovery(mid, act, ok))
	_bridge.completed.connect(_on_completed)
	if _guard.is_void():
		print("  FAIL runtime guard voided at start: %s" % _guard.void_reason)
		return false
	print("  genesis hash   %s" % _world.canonical_hash())
	return true


# ----------------------------------------------------------------------- RUN

func _run_ticks() -> void:
	print("\n[RUN]")
	for c in _cycles:
		var tick := _world.tick
		_guard.world_tick = tick

		# 1-4. apply due envelopes; 5. close their agents
		var applied := _eng.step_apply(tick)
		for e in applied:
			var env: AsyncEnvelope = e
			for a in _agents:
				var ag: AsyncAgentState = a
				if ag.envelope != null and ag.envelope.request_id == env.request_id:
					ag.close()
					break

		# 6-7. one observation opportunity per free agent, then submit
		for a in _agents:
			var ag: AsyncAgentState = a
			if not ag.may_observe(tick):
				continue
			var obs := _world.observe()
			var vt: Array = obs["valid_targets"]
			if vt.is_empty():
				# Scarcity must not manufacture hallucination: no model call.
				ag.note_no_opportunity(tick)
				_eng.no_opportunity += 1
				continue
			var rid := E.request_id_for(replicate_id(), ag.agent_id,
				ag.cognition_index)
			var env: AsyncEnvelope = E.make(rid, ag.agent_id)
			env.seal_observation(obs)
			env.submitted_ms = Time.get_ticks_msec()
			ag.begin(env, tick)
			_inflight[rid] = env
			if _synthetic:
				_synthetic_complete(env, ag, vt)
			else:
				_model_calls += 1
				_bridge.submit(ag.agent_id, ag.model_id,
					_request_payload(vt))

		# process completions into ENVELOPES ONLY, never the world
		if not _synthetic:
			while _inflight.size() > 0 and _completed.size() < _inflight.size():
				await process_frame
			_drain_completions()

		# Drain anything now due IN THIS TICK. For SERIAL this is what "the
		# world waits for cognition" means: the action was released at the tick
		# it was observed, so it must land before the world moves. For NATURAL
		# it fires only when a model genuinely completed inside the same 250 ms
		# tick, which is correct -- no world time passed, so that is contention
		# and not staleness. For EQUALIZED it is always a no-op, since the
		# release tick is observed_tick + 4.
		#
		# Deliberately uniform: an arm-specific branch here would be a second
		# choreography, which is the thing Gate 2 exists to prevent.
		var late := _eng.step_apply(tick)
		for e in late:
			var env2: AsyncEnvelope = e
			for a in _agents:
				var ag2: AsyncAgentState = a
				if ag2.envelope == null:
					continue
				if ag2.envelope.request_id == env2.request_id:
					ag2.close()
					break

		# 8. advance the world exactly once
		_eng.step_advance()

	# SETTLE. Envelopes released after the final cycle would otherwise never
	# land, leaving lifecycles open and actions unrecorded. Ticking on without
	# submitting new cognition drains them.
	#
	# Uniform across arms deliberately: a "stop submitting N ticks early"
	# window would have to differ per arm (SERIAL 0, NATURAL 1-3, EQUALIZED 4),
	# which is arm-specific choreography.
	# SETTLE IS DRAINAGE, NOT EXPERIMENTAL TIME. No observation and no
	# submission happens below, so every counted action originated inside the
	# acquisition horizon. Otherwise NATURAL and EQUALIZED would gain extra
	# cognition opportunities merely for taking longer to empty the pipe.
	var settle := 0
	while not _eng.pending.is_empty() and settle < 64:
		settle += 1
		var tick2 := _world.tick
		_guard.world_tick = tick2
		for e in _eng.step_apply(tick2):
			var env3: AsyncEnvelope = e
			for a in _agents:
				var ag3: AsyncAgentState = a
				if ag3.envelope == null:
					continue
				if ag3.envelope.request_id == env3.request_id:
					ag3.close()
					break
		_eng.step_advance()
	_settle_ticks = settle
	print("  %d ticks completed, %d settle ticks" % [_cycles, settle])


## Deterministic synthetic cognition: a legal choice and a fixed per-agent
## latency. No bridge, no model, no wall-clock dependence.
func _synthetic_complete(env: AsyncEnvelope, ag: AsyncAgentState,
		vt: Array) -> void:
	var target := str(vt[_rng.randi_range(0, vt.size() - 1)])
	env.set_action(target, "{\"target_id\":\"%s\"}" % target)
	var idx := AGENT_IDS.find(ag.agent_id)
	var latency_ticks := 1 + idx        # 1, 2, 3 ticks
	env.completed_ms = env.submitted_ms + latency_ticks * T.TICK_MS
	_actions_returned += 1
	_finish(env, ag, env.observed_tick + latency_ticks)


func _request_payload(vt: Array) -> Dictionary:
	return {
		"messages": [{"role": "user", "content": C.prompt(vt)}],
		"max_tokens": 24, "temperature": 0.0,
		"response_format": {"type": "json_schema", "json_schema": {
			"name": "async_action", "strict": true, "schema": C.schema()}},
	}


func _on_completed(rid: String, ok: bool, text: String,
		receipt: Dictionary) -> void:
	_completed.append({"rid": rid, "ok": ok, "text": text, "rec": receipt})


func _drain_completions() -> void:
	for c in _completed:
		var d: Dictionary = c
		_guard.on_receipt(d["rec"])
		var env: AsyncEnvelope = _inflight.get(str(d["rid"]), null)
		if env == null:
			continue
		var ag := _agent_for(env)
		var parsed := C.parse(str(d["text"]))
		if not bool(d["ok"]) or not bool(parsed["ok"]):
			_shape_failed += 1
			env.set_action(W.PASS_TARGET, str(d["text"]))
		else:
			_actions_returned += 1
			env.set_action(str(parsed["target_id"]), str(d["text"]))
		var rec: Dictionary = d["rec"]
		env.completed_ms = int(rec.get("finished_at_ms",
			Time.get_ticks_msec()))
		var comp_tick := T.tick_of(env.completed_ms, _run_start_ms)
		if T.is_equalizer_breach(_arm, env.observed_tick, env.completed_ms,
				_run_start_ms):
			env.equalizer_breach = true
			_equalizer_breaches += 1
		_finish(env, ag, comp_tick)
	_completed.clear()


func _finish(env: AsyncEnvelope, ag: AsyncAgentState, comp_tick: int) -> void:
	env.completion_tick = comp_tick
	var rel := T.release_tick(_arm, env.observed_tick, comp_tick)
	ag.complete(rel)
	_eng.schedule(env, rel)
	_inflight.erase(env.request_id)


func _agent_for(env: AsyncEnvelope) -> AsyncAgentState:
	for a in _agents:
		var ag: AsyncAgentState = a
		if ag.envelope != null and ag.envelope.request_id == env.request_id:
			return ag
	return null


# ------------------------------------------------------------------ POST-RUN

func _post_run() -> Dictionary:
	print("\n[POST-RUN]")
	var problems: Array = []

	# Every opened lifecycle must be closed, and every envelope must still be
	# the evidence it was when sealed.
	var dangling := 0
	for a in _agents:
		var ag: AsyncAgentState = a
		if ag.state != AG.IDLE:
			dangling += 1
	if dangling > 0:
		problems.append("%d agent lifecycle(s) left open" % dangling)
	if not _eng.pending.is_empty():
		problems.append("%d envelope(s) never released" % _eng.pending.size())
	if not _inflight.is_empty():
		problems.append("%d cognition(s) never completed" % _inflight.size())

	# arm teeth
	var counts := _eng.counts()
	var by: Dictionary = counts["by_outcome"]
	if _arm == T.SERIAL:
		if int(by.get(W.STALE_CONFLICT, 0)) != 0:
			problems.append("SERIAL produced STALE_CONFLICT")
		var reval := int(counts["stale_revalidated"])
		if reval != 0:
			problems.append("SERIAL produced STALE_REVALIDATED")
		for row in _eng.journal:
			if int((row as Dictionary)["observation_age_ticks"]) != 0:
				problems.append("SERIAL produced a non-zero observation age")
				break
	if _arm == T.EQUALIZED and _equalizer_breaches > 0:
		problems.append("%d equalizer breaches" % _equalizer_breaches)
	if _guard.is_void():
		problems.append("runtime: " + _guard.void_reason)

	var jh := _eng.journal_hash()
	var wh := _world.canonical_hash()
	print("  actions              %d" % int(counts["actions"]))
	print("  outcomes             %s" % str(by))
	print("  stale_revalidated    %d" % int(counts["stale_revalidated"]))
	print("  stale_eligible       %d" % int(counts["stale_eligible"]))
	print("  no_opportunity       %d" % int(counts["no_opportunity"]))
	print("  model_calls          %d" % _model_calls)
	print("  actions_returned     %d" % _actions_returned)
	print("  shape_failed         %d" % _shape_failed)
	var opps := 0
	for a in _agents:
		opps += (a as AsyncAgentState).observations
	var thr := {
		"actions_per_tick": float(counts["actions"]) / float(maxi(_cycles, 1)),
		"actions_per_agent": float(counts["actions"]) / float(AGENTS),
		"observation_opportunities": opps,
		"opportunities_per_tick": float(opps) / float(maxi(_cycles, 1)),
		"no_opportunity_rate": (float(counts["no_opportunity"]) / float(opps)
			if opps > 0 else 0.0),
	}
	print("  actions/tick         %.3f" % float(thr["actions_per_tick"]))
	print("  actions/agent        %.1f" % float(thr["actions_per_agent"]))
	print("  opportunities/tick   %.3f" % float(thr["opportunities_per_tick"]))
	print("  no_opportunity_rate  %.4f" % float(thr["no_opportunity_rate"]))
	print("  journal_hash         %s" % jh)
	print("  final_world_hash     %s" % wh)
	if problems.is_empty():
		print("  arm teeth            OK")
	else:
		for p in problems:
			print("  VOID: %s" % str(p))

	var manifest := {
		"replicate_id": replicate_id(), "arm": _arm,
		"arm_type": ("COUNTERFACTUAL_REPLAY" if _arm == T.ORDER_REPLAY
			else "LIVE"),
		"synthetic": _synthetic,
		"resources": RESOURCES, "hold_ticks": HOLD, "agents": AGENTS,
		"observation_horizon_ticks": _cycles,
		"settle_ticks": _settle_ticks,
		"final_world_tick": _world.tick,
		"tick_ms": T.TICK_MS,
		"equalized_delay_ticks": T.EQUALIZED_DELAY_TICKS,
		"contract_schema_hash": C.schema_hash(),
		"journal_hash": jh, "final_world_hash": wh,
		"counts": counts, "throughput": thr, "model_calls": _model_calls,
		"actions_returned": _actions_returned,
		"shape_failed": _shape_failed,
		"equalizer_breaches": _equalizer_breaches,
		"runtime": _guard.envelope(),
		"void": not problems.is_empty(),
		"void_reasons": problems,
	}
	return manifest


func _run() -> void:
	print("=== ASYNC-A runner ===\n")
	if not await _pre_run():
		quit(1)
		return
	await _run_ticks()
	var manifest := _post_run()
	var path := "res://docs/results/ASYNC_A_%s%s.json" % [
		replicate_id(), "_dry" if _synthetic else ""]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(manifest, "  "))
		f.close()
		print("\nwrote %s" % path)
	quit(1 if bool(manifest["void"]) else 0)
