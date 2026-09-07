extends SceneTree

## The runner-level deterministic witness.
##
##   godot --headless --path . --script scripts/arena/async_runner_witness_selftest.gd
##
## An INDEPENDENT inline orchestration drives the same AsyncWorld,
## AsyncStepEngine, AsyncAgentState and TimingPolicy with the same deterministic
## synthetic choices, and must reproduce the final runner's frozen dry-run
## witnesses exactly.
##
## WHY NOT THE GATE 2 FIXTURE. Gate 2 reproduces the calibration, whose
## synthetic actors submitted every cycle with no lifecycle gate. The runner
## enforces one outstanding cognition per agent. Requiring the runner to match
## Gate 2 would prove the lifecycle gate was ABSENT, which is backwards. The
## reference here therefore includes the lifecycle, and the question it answers
## is narrower and correct: did wrapping orchestration around the shared step
## engine introduce a second choreography?
##
## Three witnesses: journal_hash is authoritative; final_world_hash and outcome
## counts exist so a failure can be diagnosed by seeing WHAT differs rather than
## by staring at two SHA strings.
##
## Offline. No LM inference.

const W := preload("res://scripts/arena/async_world.gd")
const E := preload("res://scripts/arena/async_envelope.gd")
const S := preload("res://scripts/arena/async_step.gd")
const T := preload("res://scripts/arena/async_timing.gd")
const AG := preload("res://scripts/arena/async_agent.gd")

const FIXTURE := "res://scripts/arena/fixtures/async_runner_witness.json"
const RESOURCES := 16
const HOLD := 4
const AGENTS := 3
const HORIZON := 800
const AGENT_IDS := ["agent_0", "agent_1", "agent_2"]

var _checks := 0
var _failures: Array[String] = []
var _sections := ["witness", "sabotage"]
var _done: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("   ok   %s" % name)
	else:
		_failures.append(name)
		print("   FAIL %s  %s" % [name, detail])


## An independent inline orchestration. Deliberately written as its own loop
## rather than calling the runner, so that a divergence in the runner's
## choreography shows up as a hash mismatch.
##
## `swap_phases` reverses apply and advance, reproducing the calibration bug on
## purpose so the witness can be shown to go red.
func _inline(arm: String, replicate: int, swap_phases: bool) -> Dictionary:
	var world: AsyncWorld = W.make(RESOURCES, HOLD)
	var eng: AsyncStepEngine = S.make(world, arm, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 990000 + replicate
	var agents: Array = []
	for i in AGENTS:
		agents.append(AG.make(AGENT_IDS[i], "synthetic_%d" % i))
	var rid_prefix := "%s_r%d" % [arm, replicate]

	for _c in HORIZON:
		var tick := world.tick
		if swap_phases:
			eng.step_advance()
		for e in eng.step_apply(tick):
			_close_for(agents, e)
		for a in agents:
			var ag: AsyncAgentState = a
			if not ag.may_observe(tick):
				continue
			var obs := world.observe()
			var vt: Array = obs["valid_targets"]
			if vt.is_empty():
				ag.note_no_opportunity(tick)
				eng.no_opportunity += 1
				continue
			var rid := E.request_id_for(rid_prefix, ag.agent_id,
				ag.cognition_index)
			var env: AsyncEnvelope = E.make(rid, ag.agent_id)
			env.seal_observation(obs)
			env.submitted_ms = 0
			ag.begin(env, tick)
			var target := str(vt[rng.randi_range(0, vt.size() - 1)])
			env.set_action(target, "{\"target_id\":\"%s\"}" % target)
			var idx := AGENT_IDS.find(ag.agent_id)
			var lat := 1 + idx
			env.completed_ms = env.submitted_ms + lat * T.TICK_MS
			env.completion_tick = env.observed_tick + lat
			var rel := T.release_tick(arm, env.observed_tick,
				env.completion_tick)
			ag.complete(rel)
			eng.schedule(env, rel)
		for e in eng.step_apply(tick):
			_close_for(agents, e)
		if not swap_phases:
			eng.step_advance()

	var settle := 0
	while not eng.pending.is_empty() and settle < 64:
		settle += 1
		for e in eng.step_apply(world.tick):
			_close_for(agents, e)
		eng.step_advance()

	return {"journal_hash": eng.journal_hash(),
		"final_world_hash": world.canonical_hash(),
		"counts": eng.counts(), "settle_ticks": settle}


func _close_for(agents: Array, e) -> void:
	var env: AsyncEnvelope = e
	for a in agents:
		var ag: AsyncAgentState = a
		if ag.envelope == null:
			continue
		if ag.envelope.request_id == env.request_id:
			ag.close()
			return


func _run() -> void:
	print("=== ASYNC-A runner witness ===\n")
	if not FileAccess.file_exists(FIXTURE):
		_check("fixture present", false, FIXTURE)
		_report()
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	if typeof(parsed) != TYPE_DICTIONARY:
		_check("fixture parses", false)
		_report()
		return
	var arms: Dictionary = (parsed as Dictionary)["arms"]

	print(" an independent orchestration reproduces the runner exactly")
	for arm in ["SERIAL", "NATURAL", "EQUALIZED"]:
		var want: Dictionary = arms[arm]
		var got := _inline(arm, 0, false)
		_check("   %-9s actions match" % arm,
			int((got["counts"] as Dictionary)["actions"]) == int(want["actions"]),
			"%d vs %d" % [int((got["counts"] as Dictionary)["actions"]),
				int(want["actions"])])
		_check("   %-9s final_world_hash matches" % arm,
			str(got["final_world_hash"]) == str(want["final_world_hash"]),
			"%s vs %s" % [str(got["final_world_hash"]),
				str(want["final_world_hash"])])
		_check("   %-9s JOURNAL HASH matches" % arm,
			str(got["journal_hash"]) == str(want["journal_hash"]),
			"the runner has its own choreography")
		_check("   %-9s settle ticks match" % arm,
			int(got["settle_ticks"]) == int(want["settle_ticks"]))
	_done.append("witness")

	print("\n sabotage: the witness must be able to go red")
	var swapped := _inline("NATURAL", 0, true)
	var baseline: Dictionary = arms["NATURAL"]
	_check("   SABOTAGE APPLIED: advance moved before apply",
		str(swapped["journal_hash"]) != "")
	_check("   a reversed phase order breaks the journal hash",
		str(swapped["journal_hash"]) != str(baseline["journal_hash"]),
		"if this matched, the witness would be a ceremonial hash shrine")
	_check("   and the final world differs too",
		str(swapped["final_world_hash"]) != str(baseline["final_world_hash"]))
	_done.append("sabotage")
	_report()


func _report() -> void:
	for sec in _sections:
		if not _done.has(sec):
			_failures.append("section did not complete: " + sec)
			print("   FAIL section aborted: %s" % sec)
	print("\n--- %d checks, %d failure(s), %d/%d sections ---"
		% [_checks, _failures.size(), _done.size(), _sections.size()])
	if _failures.is_empty():
		print("ASYNC RUNNER WITNESS OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
