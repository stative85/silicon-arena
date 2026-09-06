extends SceneTree

## Does the ASYNC-A world classify outcomes correctly?
##
##   godot --headless --path . --script scripts/arena/async_world_selftest.gd
##
## The STALE_CONFLICT / CONTENTION_LOST / SEMANTIC_INVALID boundary is the
## instrument's load-bearing tooth. If a hallucinated target can be scored as a
## latency effect, or a simultaneous race as aged information, ASYNC-A's entire
## claim collapses -- so each branch is exercised directly.
##
## Offline. No LM inference, no bridge.

const W := preload("res://scripts/arena/async_world.gd")

var _checks := 0
var _failures: Array[String] = []


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
	print("=== ASYNC-A world selftest ===\n")
	_basic()
	_predicate()
	_aba()
	_regeneration()
	_determinism()
	_report()


func _basic() -> void:
	print(" world mechanics")
	var w: AsyncWorld = W.make(4, 3)
	_check("   starts with all resources free", w.valid_targets().size() == 4)
	var obs := w.observe()
	var r := w.apply("a", "r_00", obs)
	_check("   a free target is ACCEPTED", str(r["outcome"]) == W.ACCEPTED)
	_check("   and is no longer valid", w.valid_targets().size() == 3)
	_check("   holder recorded", w.holdings().get("a", 0) == 1)
	_check("   version advanced", w.version > int(obs["version"]))
	var p := w.apply("a", W.PASS_TARGET, w.observe())
	_check("   PASS is its own outcome", str(p["outcome"]) == W.PASSED)


func _predicate() -> void:
	print("\n the classification boundary")

	# SEMANTIC_INVALID: target was never valid in the observation.
	var w: AsyncWorld = W.make(4, 99)
	w.apply("a", "r_00", w.observe())          # a takes r_00
	var stale_obs := w.observe()                # r_00 already absent here
	var bad := w.apply("b", "r_00", stale_obs)
	_check("   target absent from the observation -> SEMANTIC_INVALID",
		str(bad["outcome"]) == W.SEMANTIC_INVALID,
		"a hallucinated target must never score as a latency effect")

	# CONTENTION_LOST: both observed the same world, no time elapsed.
	var w2: AsyncWorld = W.make(4, 99)
	var shared := w2.observe()
	var first := w2.apply("a", "r_01", shared)
	var second := w2.apply("b", "r_01", shared)
	_check("   first of a simultaneous race is ACCEPTED",
		str(first["outcome"]) == W.ACCEPTED)
	_check("   second is CONTENTION_LOST, not STALE_CONFLICT",
		str(second["outcome"]) == W.CONTENTION_LOST,
		"no world-time elapsed, so nothing went stale")
	_check("   and its observation age is zero",
		int(second["observation_age_ticks"]) == 0)

	# STALE_CONFLICT: observed, then time passed, then invalidated.
	var w3: AsyncWorld = W.make(4, 99)
	var old_obs := w3.observe()
	w3.advance()
	w3.advance()
	w3.apply("a", "r_02", w3.observe())        # someone else takes it later
	var late := w3.apply("b", "r_02", old_obs)
	_check("   observed, aged, then invalidated -> STALE_CONFLICT",
		str(late["outcome"]) == W.STALE_CONFLICT,
		str(late["reason"]))
	_check("   and its observation age is positive",
		int(late["observation_age_ticks"]) > 0)

	# The age gate is load-bearing: same setup, zero age, different verdict.
	var w4: AsyncWorld = W.make(4, 99)
	var o4 := w4.observe()
	w4.apply("a", "r_03", o4)
	var same_tick := w4.apply("b", "r_03", o4)
	_check("   SABOTAGE APPLIED: identical setup with zero elapsed ticks",
		int(same_tick["observation_age_ticks"]) == 0)
	_check("   zero age flips STALE_CONFLICT to CONTENTION_LOST",
		str(same_tick["outcome"]) == W.CONTENTION_LOST,
		"latency evidence must require latency")

	# Held before the observation is not latency evidence either.
	var w5: AsyncWorld = W.make(4, 99)
	w5.apply("a", "r_00", w5.observe())
	w5.advance()
	var after := w5.observe()
	var never := w5.apply("b", "r_00", after)
	_check("   held before the observation -> SEMANTIC_INVALID",
		str(never["outcome"]) == W.SEMANTIC_INVALID)


## The ABA problem: an id is not an identity.
func _aba() -> void:
	print("\n resource identity is (id, generation)")
	var w: AsyncWorld = W.make(4, 2)
	var obs := w.observe()                     # A observes r_00, generation 0
	_check("   observation carries target generations",
		obs.has("valid_target_generations")
			and int((obs["valid_target_generations"] as Dictionary)["r_00"]) == 0)

	w.apply("B", "r_00", w.observe())          # B takes it
	w.advance()
	w.advance()                                # hold expires, r_00 returns
	_check("   SABOTAGE APPLIED: the id is free again",
		w.valid_targets().has("r_00"))
	_check("   but it is a new instance",
		int((w.resources["r_00"] as Dictionary)["generation"]) == 1)

	var late := w.apply("A", "r_00", obs)      # A's aged request lands
	_check("   an aged action on a regenerated id still SUCCEEDS",
		str(late["outcome"]) == W.ACCEPTED,
		"the substrate does not rescue and does not reject")
	_check("   and is flagged stale_revalidated",
		bool(late["stale_revalidated"]),
		"without this the ABA case is invisible: latency touched it")
	_check("   generations recorded on the action",
		int(late["observed_target_generation"]) == 0
			and int(late["current_target_generation"]) == 1)
	_check("   revalidated_since_observation is set",
		bool(late["revalidated_since_observation"]))

	# A same-generation success must NOT be flagged.
	var w2: AsyncWorld = W.make(4, 99)
	var o2 := w2.observe()
	var plain := w2.apply("A", "r_01", o2)
	_check("   an ordinary success is NOT flagged revalidated",
		str(plain["outcome"]) == W.ACCEPTED
			and not bool(plain["stale_revalidated"]),
		"flagging every success would make the signal meaningless")


func _regeneration() -> void:
	print("\n substrate-owned regeneration")
	var w: AsyncWorld = W.make(3, 2)
	w.apply("a", "r_00", w.observe())
	_check("   held after take", w.valid_targets().size() == 2)
	w.advance()
	_check("   still held before the hold expires",
		w.valid_targets().size() == 2)
	var rel := w.advance()
	_check("   released exactly at the hold boundary",
		rel.has("r_00") and w.valid_targets().size() == 3,
		str(rel))
	_check("   release advances the version", w.version >= 2)


func _determinism() -> void:
	print("\n determinism")
	var a: AsyncWorld = W.make(6, 3)
	var b: AsyncWorld = W.make(6, 3)
	_check("   identical worlds hash identically",
		a.canonical_hash() == b.canonical_hash())
	a.apply("x", "r_01", a.observe())
	b.apply("x", "r_01", b.observe())
	_check("   identical actions keep them identical",
		a.canonical_hash() == b.canonical_hash())
	var c: AsyncWorld = W.make(6, 3)
	c.apply("y", "r_01", c.observe())
	_check("   a different holder changes the hash",
		c.canonical_hash() != a.canonical_hash(),
		"the holder must be part of world identity")


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("ASYNC WORLD OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
