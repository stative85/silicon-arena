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

var _checks := 0
var _failures: Array[String] = []

## A test function that crashes skips its checks silently, and the suite would
## still report OK. Each section registers itself and must mark completion, so
## an aborted section fails the run instead of vanishing from it.
var _expected_sections := ["envelope", "clocks", "equalizer", "inversion",
	"serial_tooth"]
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

	_check("   completion tick rounds up from wall time",
		T.completion_tick(0, T.TICK_MS + 1) == 2
			and T.completion_tick(0, T.TICK_MS) == 1)
	_check("   an instant completion still lands in the next tick",
		T.completion_tick(5, 1) == 6)
	_done("clocks")


func _equalizer() -> void:
	print("\n the equalizer leak tooth")
	var within := T.EQUALIZED_DELAY_TICKS
	_check("   a completion inside the frozen delay is no breach",
		not T.is_equalizer_breach(T.EQUALIZED, 10, 10 + within))
	_check("   SABOTAGE APPLIED: a completion past the frozen delay",
		10 + within + 1 > 10 + T.EQUALIZED_DELAY_TICKS)
	_check("   a late completion IS a breach",
		T.is_equalizer_breach(T.EQUALIZED, 10, 10 + within + 1),
		"real latency leaking back in means the arm stops isolating speed")
	_check("   breaches are meaningless outside EQUALIZED",
		not T.is_equalizer_breach(T.NATURAL, 10, 99)
			and not T.is_equalizer_breach(T.SERIAL, 10, 99))
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
