extends SceneTree

## Do the four clocks behave, and is the evidence really immutable?
##
##   godot --headless --path . --script scripts/arena/async_harness_selftest.gd
##
## Offline. No LM inference. Synthetic envelopes only.
##
## The teeth here are the ones that would let a harness bug masquerade as an
## ASYNC-A finding: a barrier hiding inside "equalized", a replay that peeks at
## the live world, or an envelope that quietly re-derives its own provenance.

const W := preload("res://scripts/arena/async_world.gd")
const E := preload("res://scripts/arena/async_envelope.gd")
const T := preload("res://scripts/arena/async_timing.gd")
const AG := preload("res://scripts/arena/async_agent.gd")
const C := preload("res://scripts/arena/async_contract.gd")

var _checks := 0
var _failures: Array[String] = []

## A test function that crashes skips its checks silently, and the suite would
## still report OK. Each section registers itself and must mark completion, so
## an aborted section fails the run instead of vanishing from it.
var _expected_sections := ["envelope", "clocks", "equalizer", "inversion",
	"serial_tooth", "lifecycle", "contract", "within_tick"]
var _completed_sections: Array[String] = []


func _done(section: String) -> void:
	_completed_sections.append(section)


func _init() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("   ok   %s" % name)
	else:
		_failures.append(name)
		print("   FAIL %s  %s" % [name, detail])


func _run() -> void:
	print("=== ASYNC-A harness selftest ===\n")
	_envelope()
	_clocks()
	_equalizer()
	_inversion()
	_serial_tooth()
	_lifecycle()
	_contract()
	_within_tick()
	_report()


func _mk(rid: String, agent: String, world: AsyncWorld,
		target: String) -> AsyncEnvelope:
	var e: AsyncEnvelope = E.make(rid, agent)
	e.seal_observation(world.observe())
	e.set_action(target, "{\"target\":\"%s\"}" % target)
	return e


func _envelope() -> void:
	print(" the envelope is evidence, not a suggestion")
	var w: AsyncWorld = W.make(4, 3)
	var e := _mk("q1", "a", w, "r_00")
	_check("   sealed observation is immutable", e.assert_immutable())
	_check("   provenance captured",
		e.observation_version == 0 and e.visible_target_ids.size() == 4
			and e.chosen_target_generation == 0)

	# The observation must come from the ENVELOPE, never the live world.
	w.apply("b", "r_01", w.observe())
	w.advance()
	var obs := e.observation()
	_check("   observation() reflects what was SEEN, not the world now",
		(obs["valid_targets"] as Array).size() == 4
			and int(obs["tick"]) == 0,
		"the live world has moved on; the fossil must not")

	# SABOTAGE: mutate provenance and prove the check goes red.
	var f := e.fingerprint()
	e.observation_version = 999
	_check("   SABOTAGE APPLIED: provenance mutated",
		e.observation_version != 0)
	_check("   immutability check catches it", not e.assert_immutable(),
		"a mutable envelope would let a replay re-derive its own provenance")
	e.observation_version = 0
	_check("   and passes again once restored",
		e.assert_immutable() and e.fingerprint() == f)

	var e2 := _mk("q2", "a", w, "r_02")
	_check("   different envelopes fingerprint differently",
		e2.fingerprint() != f)
	_done("envelope")


func _clocks() -> void:
	print("\n four clocks, one difference")
	_check("   SERIAL releases in the observed tick",
		T.release_tick(T.SERIAL, 10, 14) == 10,
		"the world waits for cognition")
	_check("   NATURAL releases at real completion",
		T.release_tick(T.NATURAL, 10, 14) == 14)
	_check("   EQUALIZED releases at observed + frozen delay",
		T.release_tick(T.EQUALIZED, 10, 11)
			== 10 + T.EQUALIZED_DELAY_TICKS)
	_check("   EQUALIZED ignores how fast the model was",
		T.release_tick(T.EQUALIZED, 10, 11)
			== T.release_tick(T.EQUALIZED, 10, 12),
		"a fast model must not be released early")

	# The barrier failure mode: equalized must NOT depend on other requests.
	var a := T.release_tick(T.EQUALIZED, 10, 11)
	var b := T.release_tick(T.EQUALIZED, 10, 13)
	_check("   EQUALIZED is not a barrier", a == b,
		"waiting for the slowest would make this batch synchronisation")

	# World time comes from wall time through one frozen mapping, never
	# from frame rate.
	_check("   tick_of maps wall time to world ticks",
		T.tick_of(1000, 1000) == 0 and T.tick_of(1000 + T.TICK_MS, 1000) == 1
			and T.tick_of(1000 + T.TICK_MS * 3 + 10, 1000) == 3)
	_check("   tick_start_ms is its inverse",
		T.tick_start_ms(3, 1000) == 1000 + 3 * T.TICK_MS)
	_check("   the equalizer deadline is explicit in milliseconds",
		T.equalized_deadline_ms(10, 0)
			== 10 * T.TICK_MS + T.EQUALIZED_DELAY_TICKS * T.TICK_MS,
		"3 ticks x 250 ms = 750 ms, stated not implied")
	_done("clocks")


func _equalizer() -> void:
	print("\n the equalizer leak tooth")
	var deadline := T.equalized_deadline_ms(10, 0)
	_check("   a completion inside the frozen delay is no breach",
		not T.is_equalizer_breach(T.EQUALIZED, 10, deadline - 1, 0))
	_check("   SABOTAGE APPLIED: a completion past the deadline",
		deadline + 1 > deadline)
	_check("   a late completion IS a breach",
		T.is_equalizer_breach(T.EQUALIZED, 10, deadline + 1, 0),
		"real latency leaking back in means the arm stops isolating speed")
	_check("   breaches are meaningless outside EQUALIZED",
		not T.is_equalizer_breach(T.NATURAL, 10, deadline + 9999, 0)
			and not T.is_equalizer_breach(T.SERIAL, 10, deadline + 9999, 0))
	_done("equalizer")


func _inversion() -> void:
	print("\n latency-rank inversion, frozen before any result")
	var w: AsyncWorld = W.make(8, 3)
	var fast := _mk("f", "fast", w, "r_00")
	fast.submitted_ms = 0
	fast.completed_ms = 100
	var mid := _mk("m", "mid", w, "r_01")
	mid.submitted_ms = 0
	mid.completed_ms = 300
	var slow := _mk("s", "slow", w, "r_02")
	slow.submitted_ms = 0
	slow.completed_ms = 900

	var natural := [fast, mid, slow]
	var inverted := T.invert_by_latency(natural)
	_check("   slowest natural arrival is applied FIRST",
		(inverted[0] as AsyncEnvelope).request_id == "s")
	_check("   fastest natural arrival is applied LAST",
		(inverted[2] as AsyncEnvelope).request_id == "f")
	_check("   the set is preserved, only the order changes",
		inverted.size() == natural.size())
	var ids := {}
	for e in inverted:
		ids[(e as AsyncEnvelope).request_id] = true
	_check("   every envelope survives the transform", ids.size() == 3)
	_check("   envelopes are unmodified by reordering",
		fast.assert_immutable() and slow.assert_immutable(),
		"a reorder must not touch the evidence")

	# Ties break deterministically.
	var t1 := _mk("bbb", "x", w, "r_03")
	t1.submitted_ms = 0
	t1.completed_ms = 200
	var t2 := _mk("aaa", "y", w, "r_04")
	t2.submitted_ms = 0
	t2.completed_ms = 200
	var tied := T.invert_by_latency([t1, t2])
	_check("   ties break by request_id, deterministically",
		(tied[0] as AsyncEnvelope).request_id == "aaa")

	var ident := T.identity_order(natural)
	_check("   the identity permutation preserves order exactly",
		(ident[0] as AsyncEnvelope).request_id == "f"
			and (ident[2] as AsyncEnvelope).request_id == "s",
		"the void check depends on this reproducing arm 2")
	_done("inversion")


## Arm 1's teeth, checked against the real world implementation.
func _serial_tooth() -> void:
	print("\n arm 1 SERIAL: staleness must be structurally impossible")
	var w: AsyncWorld = W.make(6, 3)
	var stale := 0
	var reval := 0
	var ages: Array = []
	for c in 40:
		var envs: Array = []
		for a in 3:
			var free: Array = w.valid_targets()
			# Every resource may be held; an agent with nothing to take passes.
			var tgt := (W.PASS_TARGET if free.is_empty()
				else str(free[a % free.size()]))
			envs.append(_mk("c%d_a%d" % [c, a], "syn_%d" % a, w, tgt))
		# SERIAL: released in the observed tick, applied immediately.
		for e in envs:
			var env: AsyncEnvelope = e
			var out := w.apply(env.agent_id, env.chosen_target,
				env.observation())
			ages.append(int(out["observation_age_ticks"]))
			if str(out["outcome"]) == W.STALE_CONFLICT:
				stale += 1
			if bool(out.get("stale_revalidated", false)):
				reval += 1
		w.advance()
	var max_age := 0
	for a in ages:
		max_age = maxi(max_age, int(a))
	_check("   every action has observation_age_ticks == 0", max_age == 0,
		"max age %d" % max_age)
	_check("   STALE_CONFLICT == 0", stale == 0, str(stale))
	_check("   STALE_REVALIDATED == 0", reval == 0, str(reval))
	_check("   and the run actually did something",
		ages.size() >= 100, str(ages.size()))
	_done("serial_tooth")



## THE BASEMENT WINDOW. A fixed release tick equalizes when actions LAND. It
## does not equalize how often an agent gets to THINK.
func _lifecycle() -> void:
	print("\n one outstanding cognition per agent")
	var w: AsyncWorld = W.make(8, 4)
	var a: AsyncAgentState = AG.make("fast", "m_fast")
	_check("   a fresh agent may observe", a.may_observe())
	a.begin(_mk("x1", "fast", w, "r_00"))
	_check("   an agent with cognition outstanding may NOT observe",
		not a.may_observe() and a.state == AG.PENDING)
	a.complete(5)
	_check("   COMPLETING does not free the agent",
		not a.may_observe() and a.state == AG.AWAITING_RELEASE,
		"freeing on completion is exactly the leak")
	_check("   not releasable before the release tick",
		not a.ready_to_release(4))
	_check("   releasable at the release tick", a.ready_to_release(5))
	a.close()
	_check("   only closing the envelope frees the agent",
		a.may_observe() and a.closes == 1)

	# The leak, simulated: two agents of different speed under EQUALIZED.
	var correct := _cadence(false)
	_check("   gated on RELEASE: fast and slow agents observe equally often",
		int(correct["fast"]) == int(correct["slow"]),
		"fast %d vs slow %d" % [int(correct["fast"]), int(correct["slow"])])

	var leaked := _cadence(true)
	_check("   SABOTAGE APPLIED: gate moved to completion",
		int(leaked["fast"]) != int(correct["fast"])
			or int(leaked["fast"]) != int(leaked["slow"]))
	_check("   gated on COMPLETION: the fast agent thinks more often",
		int(leaked["fast"]) > int(leaked["slow"]),
		"fast %d vs slow %d -- model speed re-enters through cadence"
			% [int(leaked["fast"]), int(leaked["slow"])])
	_done("lifecycle")


## Count observations for a fast and a slow agent under the EQUALIZED clock,
## over a fixed wall-clock horizon.
##
## Cadence is modelled in MILLISECONDS. Modelling it in ticks deadlocks: a fast
## agent completing inside its own tick maps back to the same tick and never
## advances -- which this test did on its first run.
func _cadence(gate_on_completion: bool) -> Dictionary:
	var run_start := 0
	var horizon_ms := 20000
	var counts := {"fast": 0, "slow": 0}
	for name in ["fast", "slow"]:
		var lat := 100 if name == "fast" else 700
		var now_ms := 0
		var n := 0
		while now_ms < horizon_ms:
			n += 1
			var observed_tick := T.tick_of(now_ms, run_start)
			var done_ms := now_ms + lat
			if gate_on_completion:
				# LEAK: free to observe again the moment cognition finished.
				now_ms = done_ms
			else:
				# CORRECT: free only when the envelope closes, which under
				# EQUALIZED is the fixed release deadline.
				now_ms = maxi(
					T.equalized_deadline_ms(observed_tick, run_start), done_ms)
		counts[name] = n
	return counts


func _contract() -> void:
	print("\n the action contract")
	var sch := C.schema()
	_check("   exactly one field is required",
		(sch["required"] as Array).size() == 1
			and (sch["required"] as Array)[0] == C.FIELD)
	_check("   additional properties are forbidden",
		not bool(sch["additionalProperties"]))
	var props: Dictionary = sch["properties"]
	var tgt: Dictionary = props[C.FIELD]
	_check("   target_id is a free string, NOT an enum",
		str(tgt["type"]) == "string" and not tgt.has("enum"),
		"an enum of visible ids would delete SEMANTIC_INVALID as an outcome")

	var ok := C.parse("{\"target_id\":\"r_07\"}")
	_check("   a well-formed reply parses",
		bool(ok["ok"]) and str(ok["target_id"]) == "r_07")
	_check("   invalid JSON is a shape failure",
		not bool(C.parse("{not json")["ok"]))
	_check("   a missing field is a shape failure",
		not bool(C.parse("{}")["ok"]))
	_check("   extra properties are a shape failure",
		not bool(C.parse("{\"target_id\":\"r_00\",\"why\":\"x\"}")["ok"]),
		"no explanation, no reason, no confidence")
	_check("   a non-string target is a shape failure",
		not bool(C.parse("{\"target_id\":7}")["ok"]))
	_check("   an empty target is a shape failure",
		not bool(C.parse("{\"target_id\":\"\"}")["ok"]))

	# A hallucinated id must remain EXPRESSIBLE, so it can be classified.
	var ghost := C.parse("{\"target_id\":\"r_99_nonexistent\"}")
	_check("   a hallucinated id parses cleanly and stays observable",
		bool(ghost["ok"]) and str(ghost["target_id"]) == "r_99_nonexistent",
		"it must reach the classifier to be scored SEMANTIC_INVALID")

	var w: AsyncWorld = W.make(4, 9)
	var out := w.apply("a", "r_99_nonexistent", w.observe())
	_check("   and the world scores it SEMANTIC_INVALID",
		str(out["outcome"]) == W.SEMANTIC_INVALID)

	_check("   the prompt lists the visible ids",
		C.prompt(["r_00", "r_01"]).find("r_01") != -1)
	_check("   the schema hash is stable",
		C.schema_hash() == C.schema_hash() and C.schema_hash() != "")
	_done("contract")



## Within-tick ordering. Wall time maps into 250 ms ticks, so genuinely
## different completions land in the same tick, and how they are ordered there
## is part of the timing policy.
func _within_tick() -> void:
	print("\n within-tick ordering")
	var w: AsyncWorld = W.make(8, 4)

	var a := _mk("c01_a0", "fast", w, "r_00")
	a.submitted_ms = 0
	a.completed_ms = 611
	var b := _mk("c01_a1", "mid", w, "r_01")
	b.submitted_ms = 0
	b.completed_ms = 734
	var c := _mk("c01_a2", "slow", w, "r_02")
	c.submitted_ms = 0
	c.completed_ms = 690

	var due := [a, b, c]

	# NATURAL preserves the real arrival ordering.
	var nat := T.order_due(T.NATURAL, due)
	_check("   NATURAL orders by exact completion_ms",
		(nat[0] as AsyncEnvelope).request_id == "c01_a0"
			and (nat[1] as AsyncEnvelope).request_id == "c01_a2"
			and (nat[2] as AsyncEnvelope).request_id == "c01_a1",
		"611, 690, 734 -- all in the same tick")

	# SABOTAGE: swap completion times, order MUST follow.
	var sa := _mk("c01_a0", "fast", w, "r_00")
	sa.completed_ms = 734
	var sb := _mk("c01_a1", "mid", w, "r_01")
	sb.completed_ms = 611
	_check("   SABOTAGE APPLIED: completion times swapped",
		sa.completed_ms > sb.completed_ms)
	var nat2 := T.order_due(T.NATURAL, [sa, sb])
	_check("   NATURAL order swaps with them",
		(nat2[0] as AsyncEnvelope).request_id == "c01_a1",
		"if it did not, the runner discards the arrival information the arm "
		+ "exists to study")

	# EQUALIZED must be blind to completion_ms.
	var eq_before := T.order_due(T.EQUALIZED, due)
	var ids_before: Array = []
	for e in eq_before:
		ids_before.append((e as AsyncEnvelope).request_id)

	# SABOTAGE: permute every completion time. Order MUST NOT move.
	a.completed_ms = 999
	b.completed_ms = 100
	c.completed_ms = 500
	_check("   SABOTAGE APPLIED: completion times permuted",
		a.completed_ms == 999 and b.completed_ms == 100)
	var eq_after := T.order_due(T.EQUALIZED, due)
	var ids_after: Array = []
	for e in eq_after:
		ids_after.append((e as AsyncEnvelope).request_id)
	_check("   EQUALIZED order is unchanged by completion times",
		str(ids_before) == str(ids_after),
		"speed leaking into arm 3 through within-tick order: %s vs %s"
			% [str(ids_before), str(ids_after)])

	# And it must not simply be agent-index order, which would hand agent 0
	# every same-tick collision. Checked across many cycles below rather than
	# by one comparison -- a single ordering could match agent order by chance.
	var seen := {}
	for cyc in 40:
		var e0 := _mk("c%02d_a0" % cyc, "a0", w, "r_00")
		var e1 := _mk("c%02d_a1" % cyc, "a1", w, "r_01")
		var e2 := _mk("c%02d_a2" % cyc, "a2", w, "r_02")
		var o := T.order_due(T.EQUALIZED, [e0, e1, e2])
		var first := str((o[0] as AsyncEnvelope).request_id).right(2)
		seen[first] = int(seen.get(first, 0)) + 1
	_check("   no single agent takes first position every tick",
		seen.size() > 1,
		"a fixed agent order is a systematic acquisition advantage: %s"
			% str(seen))

	# Determinism.
	_check("   EQUALIZED ordering is deterministic",
		str(ids_after) == str(T.order_due(T.EQUALIZED, due).map(
			func(e): return (e as AsyncEnvelope).request_id)))
	_done("within_tick")


func _report() -> void:
	# A section that crashed contributes no failures -- its checks simply never
	# ran. Without this the suite reports green on an aborted test, which it
	# did once already.
	for sec in _expected_sections:
		if not _completed_sections.has(sec):
			_failures.append("section did not complete: " + sec)
			print("   FAIL section aborted before finishing: %s" % sec)
	print("\n--- %d checks, %d failure(s), %d/%d sections completed ---"
		% [_checks, _failures.size(), _completed_sections.size(),
		   _expected_sections.size()])
	if _failures.is_empty():
		print("ASYNC HARNESS OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
