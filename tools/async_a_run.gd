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

## Experiment tag. ASYNC-A2 writes to its own namespace so it cannot overwrite
## ASYNC-A Run 1's VOID artifacts, which are quarantined evidence. It also
## enters the sterile request_id, so identities from the two experiments can
## never collide.
var _exp := "A2"
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
var _shape_by_agent: Dictionary = {}
var _calls_by_agent: Dictionary = {}
var _equalizer_breaches := 0
var _settle_ticks := 0
var _observation_calls := 0
var _replay: Dictionary = {}
var _all_envelopes: Array = []

## The bridge issues its OWN request ids, so the transport's id and the
## experiment's sterile request_id are different namespaces and must be mapped.
## Keying in-flight cognition by the sterile id alone silently dropped every
## completion.
var _bridge_rid: Dictionary = {}   ## bridge request_id -> AsyncEnvelope


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--arm="):
			_arm = s.substr(6)
		elif s.begins_with("--replicate="):
			_replicate = int(s.substr(12))
		elif s.begins_with("--cycles="):
			_cycles = int(s.substr(9))
		elif s.begins_with("--exp="):
			_exp = s.substr(6)
		elif s == "--dry":
			_synthetic = true
	_run.call_deferred()


func replicate_id() -> String:
	return "%s_%s_r%d" % [_exp, _arm, _replicate]


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
	# _run_start_ms is set when the tick loop actually begins, NOT here: the
	# bridge handshake below makes an HTTP residency call, and anchoring the
	# world clock before it would put every early tick deadline in the past --
	# the wall-clock wait would never wait, and the run would spin through its
	# ticks without ever draining a completion.
	_eng = S.make(_world, _arm, 0)
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

	# A measured experiment must not start with a model the bridge cannot
	# monitor. UNPROFILED is not a failure state -- it means no expectation
	# surface exists -- but running an arm against one would leave that model
	# silently unmonitored for the whole replicate.
	# Host memory headroom. Three co-resident models cost far more SYSTEM RAM
	# than VRAM -- Gate 2 saw 0.7 GB free of 31.7 GB with LM Studio holding
	# ~23.6 GB -- and a mid-replicate OOM kill is not a result. Checked here so
	# the run refuses rather than dying halfway.
	# "free" is physical RAM; "available" is virtual address space and reported
	# 56 GB on a host the OS said had 3.5 GB left. A guard that gives false
	# assurance is worse than no guard.
	var mem := OS.get_memory_info()
	var avail_mb := float(mem.get("free", 0)) / (1024.0 * 1024.0)
	print("  host free      %.0f MB" % avail_mb)
	if avail_mb > 0.0 and avail_mb < 2048.0:
		print("  FAIL host memory headroom below 2 GB; a mid-replicate OOM")
		print("       kill would void the replicate")
		return false

	var unprof := HL.unprofiled(_models)
	if not unprof.is_empty():
		print("  FAIL UNPROFILED models on the roster: %s" % str(unprof))
		print("       qualify them before a measured run")
		return false

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
			_observation_calls += 1
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
			_all_envelopes.append(env)
			if _synthetic:
				_synthetic_complete(env, ag, vt)
			else:
				_model_calls += 1
				_calls_by_agent[ag.agent_id] = int(
					_calls_by_agent.get(ag.agent_id, 0)) + 1
				var brid := _bridge.submit(ag.agent_id, ag.model_id,
					_request_payload(vt))
				_bridge_rid[brid] = env

		# Process completions into ENVELOPES ONLY, never the world.
		#
		# THE TICK-ADVANCE RULE IS PART OF THE TIMING POLICY. SERIAL means the
		# world waits for cognition, so its tick ends when the outstanding
		# cognition has completed. NATURAL and EQUALIZED mean the world
		# continues, so their ticks are wall-clock 250 ms -- blocking until all
		# in-flight requests finished would be a barrier and would make both
		# arms behave synchronously, destroying the asynchrony they measure.
		if not _synthetic:
			var rule := T.tick_advance_rule(_arm)
			if rule == T.TICK_WAIT_FOR_COGNITION:
				while not _inflight.is_empty():
					await process_frame
					_drain_completions()
			else:
				var deadline := T.tick_start_ms(tick + 1, _run_start_ms)
				while Time.get_ticks_msec() < deadline:
					await process_frame
					_drain_completions()
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
	# Live cognition may still be in flight at the horizon. Settle is drainage,
	# so those requests are awaited and applied -- but NO new observation and
	# NO new submission happens, so every counted action still originates
	# inside the acquisition horizon.
	if not _synthetic:
		var wait_until := Time.get_ticks_msec() + 120000
		while not _inflight.is_empty() and Time.get_ticks_msec() < wait_until:
			await process_frame
			_drain_completions()

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
		var env: AsyncEnvelope = _bridge_rid.get(str(d["rid"]), null)
		if env == null:
			continue
		_bridge_rid.erase(str(d["rid"]))
		var ag := _agent_for(env)
		var parsed := C.parse(str(d["text"]))
		if not bool(d["ok"]) or not bool(parsed["ok"]):
			_shape_failed += 1
			_shape_by_agent[env.agent_id] = int(
				_shape_by_agent.get(env.agent_id, 0)) + 1
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
	if _arm == T.ORDER_REPLAY:
		if _model_calls != 0:
			problems.append("replay made %d model calls" % _model_calls)
		if _observation_calls != 0:
			problems.append("replay made %d observation calls"
				% _observation_calls)
		if str(_replay.get("source_envelope_corpus_hash", "")) \
				!= str(_replay.get("replay_input_corpus_hash", "x")):
			problems.append("source corpus hash != replay input hash")
		if int(_replay.get("source_envelopes_mutated", -1)) != 0:
			problems.append("replay mutated the source envelopes")
		if str(_replay.get("source_hash_after", "")) \
				!= str(_replay.get("replay_input_corpus_hash", "x")):
			problems.append("source corpus changed during replay")
		# Positive control: if nothing was reorderable, arm 4 is not evidence
		# about ordering for this replicate.
		# POSITIVE CONTROL. If the transform ran but the replay journal is
		# byte-identical to the source, either there were no reorderable
		# collisions or the transform did not actually apply. Record which --
		# do not quietly report "arm 4 ~ arm 2" as evidence about ordering.
		var rjh := _eng.journal_hash()
		_replay["replay_journal_hash"] = rjh
		_replay["journal_differs_from_source"] = (
			rjh != str(_replay.get("source_journal_hash", "")))
		if not bool(_replay["journal_differs_from_source"]):
			_replay["ordering_exercised"] = "NOT_EXERCISED_NO_EFFECT"
		if int(_replay.get("reorderable_groups", 0)) == 0:
			_replay["ordering_exercised"] = "NOT_EXERCISED"
		else:
			_replay["ordering_exercised"] = "EXERCISED"
	# Preregistered void condition: SHAPE_FAILED above 10% for ANY agent means
	# the contract is not expressible and the descriptors would be measuring
	# contract-satisfaction, as PIT A Run 1 did.
	var shape_rates := {}
	for aid in _calls_by_agent:
		var calls := int(_calls_by_agent[aid])
		var sf := int(_shape_by_agent.get(aid, 0))
		var rate := (float(sf) / float(calls)) if calls > 0 else 0.0
		shape_rates[aid] = rate
		if rate > 0.10:
			problems.append("SHAPE_FAILED %.1f%% for %s (>10%%)"
				% [rate * 100.0, aid])
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
		"experiment": _exp, "replicate_id": replicate_id(), "arm": _arm,
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
		"shape_failed_by_agent": _shape_by_agent,
		"model_calls_by_agent": _calls_by_agent,
		"shape_failed_rates": shape_rates,
		"equalizer_breaches": _equalizer_breaches,
		"runtime": _guard.envelope(),
		"observation_calls": _observation_calls,
		"replay": _replay,
		"void": not problems.is_empty(),
		"void_reasons": problems,
	}
	return manifest



# ---------------------------------------------------------------- ARM 4

## The counterfactual replay.
##
## THE SEAM GUARDED HARDEST: arm 4 must NEVER regenerate an observation from
## the replay world. The replay world diverges the moment ordering changes, so
## asking it what the agent "would have seen" answers a different, incoherent
## question -- some half-recomputed alternate history. The source envelope is
## injected as HISTORICAL EVIDENCE instead.
##
## Divergence between the replay world and the source world is EXPECTED. That
## is the experiment, not contamination. Classification still uses the ORIGINAL
## observation provenance: the agent is not retroactively judged by what a
## counterfactual world would have shown it.
func _run_replay(source_path: String) -> bool:
	print("\n[ARM 4] counterfactual replay")
	if not FileAccess.file_exists(source_path):
		print("  FAIL source corpus not found: %s" % source_path)
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		print("  FAIL source corpus unreadable")
		return false
	var src: Array = (parsed as Dictionary)["corpus"]
	var declared_hash := str((parsed as Dictionary).get("corpus_hash", ""))
	print("  source envelopes     %d" % src.size())

	# Rebuild source envelopes as evidence, then clone for execution.
	var sources: Array = []
	for row in src:
		var d: Dictionary = row
		var e: AsyncEnvelope = E.make(str(d["request_id"]), str(d["agent_id"]))
		e.seal_observation({
			"tick": int(d["observed_tick"]),
			"version": int(d["observation_version"]),
			"valid_targets": d["visible_target_ids"],
			"valid_target_generations": d["visible_target_generations"],
			"hash": str(d["observation_hash"]),
		})
		e.set_action(str(d["chosen_target"]), str(d.get("raw_action", "")))
		e.submitted_ms = int(d["submitted_ms"])
		e.completed_ms = int(d["completed_ms"])
		e.completion_tick = int(d["completion_tick"])
		e.release_tick = int(d["release_tick"])
		sources.append(e)

	var src_journal := ""
	for row in src:
		var d2: Dictionary = row
		src_journal += "%s|%s|%s|%d|%d|%s|%s
" % [
			str(d2["request_id"]), str(d2["agent_id"]),
			str(d2["chosen_target"]), int(d2["applied_tick"]),
			int(d2["observation_age_ticks"]), str(d2["outcome"]),
			str(d2["stale_revalidated"])]
	_replay["source_journal_hash"] = src_journal.sha256_text()

	var input_hash := _corpus_hash(sources)
	_replay["source_envelope_corpus_hash"] = declared_hash
	_replay["replay_input_corpus_hash"] = input_hash
	print("  source corpus hash   %s" % declared_hash)
	print("  replay input hash    %s" % input_hash)

	# Group by release tick; invert latency rank WITHIN each group. Only the
	# ordering changes -- the tick structure is identical to the source.
	var groups: Dictionary = {}
	for e in sources:
		var env: AsyncEnvelope = e
		var t := env.release_tick
		if not groups.has(t):
			groups[t] = []
		(groups[t] as Array).append(env)

	var reorderable := 0
	var reordered := 0
	var inversions := 0
	var ticks: Array = groups.keys()
	ticks.sort()
	for t in ticks:
		var g: Array = groups[t]
		if g.size() < 2:
			continue
		reorderable += 1
		# The baseline is the SOURCE application order -- NATURAL's within-tick
		# rule -- not the order envelopes happen to sit in memory. Comparing
		# against memory order measured nothing and reported zero reordering
		# across 533 groups.
		var g0 := T.order_due(T.NATURAL, g)
		var inv := T.invert_by_latency(g)
		for i in g0.size():
			if (g0[i] as AsyncEnvelope).request_id != (inv[i] as AsyncEnvelope).request_id:
				reordered += 1
		for i in g0.size():
			for j in range(i + 1, g0.size()):
				var a_id := (g0[i] as AsyncEnvelope).request_id
				var b_id := (g0[j] as AsyncEnvelope).request_id
				var ia := _index_of(inv, a_id)
				var ib := _index_of(inv, b_id)
				if ia > ib:
					inversions += 1
		groups[t] = inv

	_replay["reorderable_groups"] = reorderable
	_replay["envelopes_reordered"] = reordered
	_replay["pairwise_order_inversions"] = inversions
	_replay["fraction_of_applications_reordered"] = (
		float(reordered) / float(maxi(sources.size(), 1)))
	print("  reorderable groups   %d" % reorderable)
	print("  envelopes reordered  %d" % reordered)
	print("  pairwise inversions  %d" % inversions)

	# Schedule clones in the inverted order. ORDER_REPLAY's within-tick rule is
	# "use the order given", so scheduling order IS application order.
	for t in ticks:
		for e in (groups[t] as Array):
			var clone: AsyncEnvelope = (e as AsyncEnvelope).clone_for_replay()
			_all_envelopes.append(clone)
			_eng.schedule(clone, t)

	# Run the world forward. NO observations, NO model calls.
	var max_tick := 0
	for t in ticks:
		max_tick = maxi(max_tick, int(t))
	for _i in max_tick + 1:
		_eng.step_apply(_world.tick)
		_eng.step_advance()
	var settle := 0
	while not _eng.pending.is_empty() and settle < 64:
		settle += 1
		_eng.step_apply(_world.tick)
		_eng.step_advance()
	_settle_ticks = settle

	# The fossil must be untouched by the replay.
	var mutated := 0
	for e in sources:
		if not (e as AsyncEnvelope).assert_immutable():
			mutated += 1
	_replay["source_envelopes_mutated"] = mutated
	_replay["source_hash_after"] = _corpus_hash(sources)
	print("  source hash after    %s" % str(_replay["source_hash_after"]))
	return true


func _index_of(arr: Array, rid: String) -> int:
	for i in arr.size():
		if (arr[i] as AsyncEnvelope).request_id == rid:
			return i
	return -1


## Hash of a corpus as ROWS, so the value written with the corpus and the
## value recomputed from rebuilt envelopes are the same quantity.
func _rows_hash(rows: Array) -> String:
	var fps: Array = []
	for row in rows:
		fps.append(str((row as Dictionary)["fingerprint"]))
	fps.sort()
	return ("|".join(PackedStringArray(fps))).sha256_text()


func _corpus_hash(envs: Array) -> String:
	var parts: Array = []
	for e in envs:
		parts.append((e as AsyncEnvelope).fingerprint())
	parts.sort()
	return ("|".join(PackedStringArray(parts))).sha256_text()


func _run() -> void:
	print("=== ASYNC-A runner ===\n")
	if not await _pre_run():
		quit(1)
		return
	if _arm == T.ORDER_REPLAY:
		var src := "res://docs/results/ASYNC_%s_NATURAL_r%d%s_corpus.json" % [
			_exp, _replicate, "_dry" if _synthetic else ""]
		_replay["source_arm"] = T.NATURAL
		_replay["source_replicate"] = "%s_NATURAL_r%d" % [_exp, _replicate]
		_replay["ordering_transform"] = "LATENCY_RANK_INVERSION"
		if not _run_replay(src):
			quit(1)  # reason printed by _run_replay
			return
	else:
		await _run_ticks()
	var manifest := _post_run()
	var path := "res://docs/results/ASYNC_%s.json" % [
		replicate_id() + ("_dry" if _synthetic else "")]
	# The envelope corpus is arm 4's input, so it is written for every LIVE
	# arm rather than reconstructed later.
	if _arm != T.ORDER_REPLAY:
		# Written in JOURNAL order, which IS the source application order.
		var corpus: Array = _eng.journal.duplicate()
		var cf := FileAccess.open("res://docs/results/ASYNC_%s_corpus.json"
			% [replicate_id() + ("_dry" if _synthetic else "")],
			FileAccess.WRITE)
		if cf != null:
			cf.store_string(JSON.stringify({"corpus": corpus,
				"corpus_hash": _rows_hash(corpus)}, "  "))
			cf.close()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(manifest, "  "))
		f.close()
		print("\nwrote %s" % path)
	quit(1 if bool(manifest["void"]) else 0)
