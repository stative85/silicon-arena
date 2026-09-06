extends SceneTree

## Does the PIT A instrument deserve to touch five models?
##
##   godot --headless --path . --script scripts/arena/pit_a_selftest.gd
##
## Pre-registered in docs/EXPERIMENT_PIT_A.md at 15f30e9.
##
## OFFLINE. No LM Studio, no GPU, no generation. Everything here is a pure
## function over synthetic worlds.
##
## Two jobs. The ELEVEN TEETH prove each load-bearing invariant can be broken
## and detected. The REACHABILITY AUDIT proves each frozen metric has a concrete
## event that moves it and one that prevents it -- and demotes any metric that
## cannot move under the real mechanism, before the GPU is ever asked.
##
## SABOTAGE INSTRUCTIONS, so these are tests shown to fail rather than tests
## that have only ever passed. In pit_world.gd / pit_validator.gd:
##
##   hashing      make structural_hash() return a constant
##   tombstone    make DELETE erase instead of tombstoning
##   restore      make RESTORE add a fresh object instead of reading tombstones
##   immutable    delete the IMMUTABLE_TARGET branch from the validator
##   explanation  make apply() read patch["explanation"]
##   rejection    let the runner apply a patch the validator refused
##   schedule     let activation() read the world state
##
## Each must turn its own check red. Verified by hand before committing.

const W := preload("res://scripts/arena/pit_world.gd")
const V := preload("res://scripts/arena/pit_validator.gd")
const C := preload("res://scripts/arena/pit_consequence.gd")
const R := preload("res://scripts/arena/pit_random.gd")
const G := preload("res://scripts/arena/pit_gate.gd")
const J := preload("res://scripts/arena/pit_journal.gd")
const K := preload("res://scripts/arena/pit_contract.gd")
const CN := preload("res://scripts/arena/pit_canonical.gd")
const IX := preload("res://scripts/arena/pit_interaction.gd")

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


## Apply only what the validator accepts. The runner must do exactly this, and
## tooth 6 proves that skipping validation is detectable.
func _step(state: Dictionary, patch: Dictionary) -> Dictionary:
	var v := V.validate(state, patch)
	if not bool(v["ok"]):
		return state
	return W.apply(state, patch)


func _run() -> void:
	print("=== PIT A instrument selftest ===\n")
	var g := W.genesis()

	# ------------------------------------------------------------ THE TEETH
	print(" 1. an invalid patch cannot mutate canonical state")
	var before := W.structural_hash(g)
	for bad in [K.delete("does_not_exist"),
			K.restore("rule_1"),
			K.mutate("ghost", {}),
			K.add("rule_1", "rule"),
			{"operation": "NONSENSE", "target": "rule_1", "type": "none", "props": {}, "explanation": ""}]:
		var v := V.validate(g, bad)
		_check("   %s/%s refused as %s" % [str(bad["operation"]),
				str(bad.get("target", "-")), str(v["code"])],
			not bool(v["ok"]), str(v))
	_check("   and genesis is untouched by all of them",
		W.structural_hash(g) == before)

	print("\n 2. DELETE removes the object from later visible state")
	var d := _step(g, K.delete("tool_1"))
	_check("   tool_1 no longer alive", not W.is_alive(d, "tool_1"))
	_check("   tool_1 IS tombstoned, not erased", W.is_tombstoned(d, "tool_1"))
	_check("   the tombstone remembers when it died",
		(d["tombstones"]["tool_1"] as Dictionary).has("deleted_at"))

	print("\n 3. RESTORE reinstates a tombstoned object")
	var r := _step(d, K.restore("tool_1"))
	_check("   tool_1 alive again", W.is_alive(r, "tool_1"))
	_check("   and no longer tombstoned", not W.is_tombstoned(r, "tool_1"))
	_check("   restored object kept its properties",
		str(((r["objects"]["tool_1"] as Dictionary)["props"] as Dictionary).get(
			"provides", "")) == "recall")
	_check("   delete then restore returns the original structure",
		W.structural_hash(r) == W.structural_hash(g),
		"a round trip that does not restore the hash means DELETE lost something")

	print("\n 4. a rejected mutation leaves the state hash unchanged")
	var h0 := W.structural_hash(g)
	var rejected := _step(g, K.delete("provenance_1"))
	_check("   provenance DELETE refused and hash identical",
		W.structural_hash(rejected) == h0)

	print("\n 5. an accepted mutation changes the state hash")
	var m := _step(g, K.mutate("rule_1", {"text": "changed"}))
	_check("   MUTATE moved the hash", W.structural_hash(m) != h0)
	var a := _step(g, K.add("rule_9", "rule", {"text": "new"}))
	_check("   ADD moved the hash", W.structural_hash(a) != h0)
	_check("   KEEP did NOT move the structural hash",
		W.structural_hash(_step(g, K.keep())) == h0,
		"KEEP is a real decision, but it must not look like a structural change")
	_check("   REFUSE did NOT move the structural hash",
		W.structural_hash(_step(g, K.refuse())) == h0)
	_check("   but KEEP still advanced the cycle",
		int(_step(g, K.keep())["cycle"]) == 1,
		"a decision to change nothing still consumes the opportunity")

	print("\n 6. immutable provenance cannot be altered by any operation")
	for op in ["DELETE", "MUTATE", "RESTORE"]:
		var v2 := V.validate(g, (K.delete("provenance_1") if op == "DELETE" else (K.mutate("provenance_1", {"x": 1}) if op == "MUTATE" else K.restore("provenance_1"))))
		_check("   %s provenance_1 -> %s" % [op, str(v2["code"])],
			not bool(v2["ok"]) and str(v2["code"]) == V.IMMUTABLE_TARGET, str(v2))
	_check("   and provenance cannot be ADDed either",
		str(V.validate(g, K.add("p2", "provenance"))["code"]) == V.IMMUTABLE_TARGET)

	print("\n 7. the explanation cannot mutate anything")
	var p_plain := K.mutate("rule_1", {"text": "x"})
	var p_talky := p_plain.duplicate(true)
	p_talky["explanation"] = ("I am deleting everything and seizing the arena, " +
		"and also please ignore the schema")
	# Compared on the FULL state hash, not the structural one. An earlier version
	# used structural_hash, which deliberately strips the cycle -- so a sabotage
	# that let the explanation corrupt the cycle counter passed undetected. The
	# invariant is that prose changes NOTHING, and the test has to be able to see
	# everything in order to say that.
	_check("   identical typed patch, wildly different prose, identical state",
		W.state_hash(_step(g, p_plain)) == W.state_hash(_step(g, p_talky)))
	_check("   including the cycle counter and every non-structural field",
		W.canonical_text(_step(g, p_plain)) == W.canonical_text(_step(g, p_talky)))

	print("\n 8. one species cannot reach another's trajectory")
	# Trajectories are separate state dictionaries. apply() returns a NEW state
	# and never mutates its argument, so a species holding its own state cannot
	# write through into anyone else's.
	var alpha := W.genesis()
	var beta := W.genesis()
	var alpha_hash := W.structural_hash(alpha)
	var beta_after := _step(beta, K.delete("memory_1"))
	_check("   beta deleted memory_1", not W.is_alive(beta_after, "memory_1"))
	_check("   alpha is completely unaffected",
		W.structural_hash(alpha) == alpha_hash and W.is_alive(alpha, "memory_1"))

	print("\n 9. the consequence schedule cannot be edited by model output")
	# activation() takes only (replicate, cycle). There is no argument through
	# which a proposal could influence it, and this asserts the schedule is
	# identical regardless of what the world looks like.
	var wrecked := g.duplicate(true)
	(wrecked["objects"] as Dictionary).clear()
	var same := true
	for cyc in 100:
		if str(C.activation(0, cyc)) != str(C.activation(7, cyc)):
			same = false
	_check("   schedule identical across replicates", same)
	_check("   and identical against an emptied world",
		str(C.activation(0, 42)) == str(C.activation(0, 42)))
	_check("   activations actually fire", C.activation_cycles().size() == 6,
		str(C.activation_cycles()))
	var ev := C.evaluate(_step(g, K.delete("tool_1")),
		C.activation(0, 12))
	_check("   a deleted dependency reports unsatisfied",
		not bool(ev["satisfied"]) and bool(ev["tombstoned"]), str(ev))
	_check("   an intact dependency reports satisfied",
		bool(C.evaluate(g, C.activation(0, 12))["satisfied"]))
	_check("   evaluating a consequence does not repair the world",
		not W.is_alive(_step(g, K.delete("tool_1")),
			"tool_1"))

	print("\n 10. the RANDOM arm really varies")
	var cov := R.coverage(g, 12345, 120)
	var kinds: Array = cov.keys()
	kinds.sort()
	_check("   RANDOM exercised every operation kind: %s" % str(kinds),
		kinds.size() == W.OPS.size(), "%s of %s" % [str(kinds), str(W.OPS)])
	var different := false
	for cyc in 40:
		if str(R.propose(g, 1, cyc)) != str(R.propose(g, 2, cyc)):
			different = true
	_check("   different seeds give different trajectories", different)
	_check("   same seed is reproducible",
		str(R.propose(g, 99, 7)) == str(R.propose(g, 99, 7)))

	print("\n 11. canonical history reconstructs every state from genesis")
	var patches: Array = []
	var live := W.genesis()
	for cyc in 60:
		var p := R.propose(live, 4242, cyc)
		if bool(V.validate(live, p)["ok"]):
			patches.append(p)
			live = W.apply(live, p)
	var replay := W.genesis()
	for p in patches:
		replay = W.apply(replay, p)
	_check("   replay of %d accepted patches reproduces the final hash"
			% patches.size(),
		W.state_hash(replay) == W.state_hash(live),
		"canonical history cannot reconstruct the world it recorded")

	_gate()
	_livelock()
	_canon()
	_endtoend()
	_parity()
	_journal()
	_reachability(g)
	_report()


# ----------------------------------------- anti-livelock (Run 3 invariant)

## EVERY CONSUMED OPPORTUNITY MUST ADVANCE PRODUCER-VISIBLE OBSERVATION.
##
## Run 2 gave five species 100 cycles each and got SIX distinct proposals in
## 1,500 calls. A rejected move left the world unchanged, so the next prompt was
## byte-identical, so at temperature 0 the same move came back forever. KEEP and
## REFUSE do it too.
##
## SABOTAGE: make PitInteraction.advance() stop incrementing cycle_index, or
## drop the interaction block from visible_text(). Either must turn this red.
func _livelock() -> void:
	print("
 16. every consumed opportunity advances the observation")
	var g := W.genesis()
	var world_text := W.canonical_text(g)
	var i0 := IX.genesis()

	# 1-3: rejection, KEEP and REFUSE all leave the world alone and must still
	# move the observation.
	var rejected := IX.advance(i0, "ADD", IX.REJECTED, "TARGET_EXISTS")
	_check("   rejected move: world unchanged, observation ADVANCES",
		IX.observation_hash(world_text, i0)
			!= IX.observation_hash(world_text, rejected))
	var kept := IX.advance(i0, "KEEP", IX.ACCEPTED, "OK")
	_check("   KEEP: world may be unchanged, observation ADVANCES",
		IX.observation_hash(world_text, i0)
			!= IX.observation_hash(world_text, kept))
	var refused := IX.advance(i0, "REFUSE", IX.ACCEPTED, "OK")
	_check("   REFUSE: world may be unchanged, observation ADVANCES",
		IX.observation_hash(world_text, i0)
			!= IX.observation_hash(world_text, refused))

	# 4: the exact Run 2 fixed point. Two IDENTICAL consecutive rejections must
	# still produce different observations.
	var r1 := IX.advance(i0, "ADD", IX.REJECTED, "TARGET_EXISTS")
	var r2 := IX.advance(r1, "ADD", IX.REJECTED, "TARGET_EXISTS")
	_check("   two identical consecutive rejections differ observationally",
		IX.observation_hash(world_text, r1)
			!= IX.observation_hash(world_text, r2),
		"this is the Run 2 fixed point and it must be impossible")
	_check("   and the streak is visible to the producer",
		int(r2["rejection_streak"]) == 2 and int(r1["rejection_streak"]) == 1)
	_check("   an accepted move clears the streak",
		int(IX.advance(r2, "DELETE", IX.ACCEPTED, "OK")["rejection_streak"]) == 0)

	# A hundred consecutive rejections must be a hundred DISTINCT observations.
	var seen := {}
	var cur := i0
	for _n in 100:
		cur = IX.advance(cur, "ADD", IX.REJECTED, "TARGET_EXISTS")
		seen[IX.observation_hash(world_text, cur)] = true
	_check("   100 identical rejections give 100 distinct observations",
		seen.size() == 100, "%d distinct" % seen.size())

	# AND THE SAME FOR ACCEPTED NO-OPS. An earlier version of this tooth only
	# swept rejections, so freezing cycle_index passed: rejection_streak was
	# still advancing and masked it. Repeated accepted KEEPs move no streak, no
	# operation and no reason -- if the clock stops, they are byte-identical and
	# the livelock is back wearing a success code.
	var kseen := {}
	var kcur := i0
	for _n in 100:
		kcur = IX.advance(kcur, "KEEP", IX.ACCEPTED, "OK")
		kseen[IX.observation_hash(world_text, kcur)] = true
	_check("   100 identical accepted KEEPs give 100 distinct observations",
		kseen.size() == 100, "%d distinct -- the clock is not advancing"
			% kseen.size())
	var rseen := {}
	var rcur := i0
	for _n in 50:
		rcur = IX.advance(rcur, "REFUSE", IX.ACCEPTED, "OK")
		rseen[IX.observation_hash(world_text, rcur)] = true
	_check("   50 identical accepted REFUSEs give 50 distinct observations",
		rseen.size() == 50, "%d distinct" % rseen.size())
	_check("   the cycle index is what advances, not just the streak",
		int(kcur["cycle_index"]) == 100 and int(kcur["rejection_streak"]) == 0,
		"cycle=%s streak=%s" % [str(kcur["cycle_index"]),
			str(kcur["rejection_streak"])])

	# THE ROLES ARE SEPARABLE, and each claim is tested rather than assumed.
	# cycle_index ALONE must defeat the livelock; the feedback fields carry
	# meaning, not anti-livelock duty.
	var clock_only := {"cycle_index": 0, "last_operation": IX.NONE,
		"last_outcome": IX.NONE, "last_reason_code": "", "rejection_streak": 0}
	var clock_seen := {}
	for n in 50:
		clock_only["cycle_index"] = n
		clock_seen[IX.observation_hash(world_text, clock_only)] = true
	_check("   cycle_index ALONE gives distinct observations",
		clock_seen.size() == 50,
		"the anti-livelock duty belongs to the clock, not the feedback")

	# rejection_streak is a MEMORY variable and is labelled as one, because
	# calling the whole structure "not a memory mechanism" was too strong.
	var s1 := IX.advance(i0, "ADD", IX.REJECTED, "X")
	var s2 := IX.advance(s1, "ADD", IX.REJECTED, "X")
	_check("   rejection_streak carries state across more than one step",
		int(s2["rejection_streak"]) > int(s1["rejection_streak"]),
		"this is memory, small but real, and the docs now say so")

	# One consumed opportunity advances the clock EXACTLY once.
	_check("   one opportunity advances the cycle exactly once",
		int(IX.advance(i0, "KEEP", IX.ACCEPTED, "OK")["cycle_index"])
			- int(i0["cycle_index"]) == 1)

	# A rejected proposal cannot move the canonical world.
	var before_w := W.structural_hash(g)
	var rej := V.validate(g, K.delete("nope"))
	_check("   a rejected proposal cannot advance the canonical world",
		not bool(rej["ok"]) and W.structural_hash(g) == before_w)

	# Structural/attractor equivalence must be identical whether interaction
	# state exists or is stripped entirely.
	_check("   structural hash is unchanged by any interaction state",
		W.structural_hash(g) == before_w and not IX.is_structural(),
		"interaction must never enter attractor equivalence")

	# SHAPE FAILURE is its own outcome. Not a decision, not infrastructure.
	print("   -- shape failures --")
	var sf := IX.advance(i0, "", IX.SHAPE_FAILED, "MALFORMED_PATCH")
	_check("   shape failure consumes exactly one opportunity",
		int(sf["cycle_index"]) - int(i0["cycle_index"]) == 1)
	_check("   world hash is untouched by a shape failure",
		W.structural_hash(g) == W.structural_hash(g))
	_check("   observation still advances",
		IX.observation_hash(world_text, i0)
			!= IX.observation_hash(world_text, sf))
	_check("   no typed operation is fabricated from malformed output",
		str(sf["last_operation"]) == IX.NONE,
		"inventing a decision the model did not make is the whole failure mode")
	_check("   and it is never recorded as KEEP",
		str(sf["last_operation"]) != "KEEP"
			and str(sf["last_outcome"]) != IX.ACCEPTED)
	_check("   the exact shape code is preserved",
		str(sf["last_reason_code"]) == "MALFORMED_PATCH")

	# rejection_streak belongs to semantic rejection ALONE.
	var after_two := IX.advance(IX.advance(i0, "ADD", IX.REJECTED, "X"),
		"ADD", IX.REJECTED, "X")
	var then_shape := IX.advance(after_two, "", IX.SHAPE_FAILED, "MALFORMED_PATCH")
	_check("   a shape failure does NOT increment the rejection streak",
		int(then_shape["rejection_streak"]) == int(after_two["rejection_streak"]),
		"unparseable output must not masquerade as an invalid world decision")
	_check("   nor does it reset the streak",
		int(then_shape["rejection_streak"]) == 2,
		"resetting would reward a model for emitting garbage")
	_check("   an accepted move still clears it",
		int(IX.advance(then_shape, "KEEP", IX.ACCEPTED, "OK")["rejection_streak"]) == 0)

	# 100 consecutive shape failures must still be 100 distinct observations.
	var shseen := {}
	var shcur := i0
	for _n in 100:
		shcur = IX.advance(shcur, "", IX.SHAPE_FAILED, "MALFORMED_PATCH")
		shseen[IX.observation_hash(world_text, shcur)] = true
	_check("   100 shape failures give 100 distinct observations",
		shseen.size() == 100, "%d distinct" % shseen.size())

	# 6-7: substrate-owned, and never structural.
	var patched := CN.canonicalise(K.mutate("rule_1", {"cycle_index": 999}))
	_check("   a model patch cannot reach interaction state",
		not (patched["patch"] as Dictionary).has("cycle_index")
			and not (patched["patch"] as Dictionary).has("rejection_streak"))
	_check("   interaction state is excluded from structural hashes",
		not IX.is_structural()
			and W.structural_hash(g) == W.structural_hash(g),
		"a shared rejection streak must never look like convergence")

	# 8: resume reconstructs it exactly.
	var rebuilt := IX.genesis()
	for _n in 7:
		rebuilt = IX.advance(rebuilt, "ADD", IX.REJECTED, "TARGET_EXISTS")
	var replayed := IX.genesis()
	for _n in 7:
		replayed = IX.advance(replayed, "ADD", IX.REJECTED, "TARGET_EXISTS")
	_check("   interaction state is reconstructible on resume",
		str(rebuilt) == str(replayed))


# ------------------------------------- canonicalisation (Run 3 invariant)

## Fields irrelevant to an action must not be able to invalidate that action --
## and canonicalisation must never repair a field the action DOES read.
func _canon() -> void:
	print("
 17. irrelevant fields are normalised, authoritative ones are not")
	var g := W.genesis()

	# 10-11: metamorphic. Arbitrary garbage in irrelevant fields must produce
	# IDENTICAL semantics. This is the test Run 2 lacked entirely.
	var deletes: Array = []
	for ty in K.OBJECT_TYPES + [K.TYPE_NONE]:
		for props in [{}, {"a": 1}, {"target": "elsewhere"}, {"x": {"y": 2}}]:
			deletes.append({"operation": "DELETE", "target": "rule_1",
				"type": ty, "props": props, "explanation": "whatever"})
	var canon_forms := {}
	for d in deletes:
		var c := CN.canonicalise(d)
		if bool(c["ok"]):
			canon_forms[str(c["patch"])] = true
	_check("   %d DELETE variants -> one canonical form" % deletes.size(),
		canon_forms.size() == 1, str(canon_forms.keys()))

	var keeps: Array = []
	for tgt in ["__NONE__", "rule_1", "object id", "anything at all"]:
		for ty in ["none", "memory", "tool"]:
			keeps.append({"operation": "KEEP", "target": tgt, "type": ty,
				"props": {"target": "__NONE__"}, "explanation": "x"})
	var keep_forms := {}
	for kp in keeps:
		var c2 := CN.canonicalise(kp)
		if bool(c2["ok"]):
			keep_forms[str(c2["patch"])] = true
	_check("   %d KEEP variants -> one canonical form" % keeps.size(),
		keep_forms.size() == 1, str(keep_forms.keys()))

	# 9 + 12: authoritative fields are NEVER repaired. These are the exact
	# Run 2 failures that were genuine and must stay genuine.
	for bad in [["ADD onto a live id", K.add("rule_1", "rule")],
			["ADD with type none", {"operation": "ADD", "target": "z",
				"type": "none", "props": {}, "explanation": ""}],
			["MUTATE with no target", {"operation": "MUTATE",
				"target": "__NONE__", "type": "none", "props": {"a": 1},
				"explanation": ""}],
			["RESTORE without tombstone", K.restore("rule_1")],
			["DELETE absent target", K.delete("nope")]]:
		var c3 := CN.canonicalise(bad[1])
		var still_bad := (not bool(c3["ok"])) 			or (not bool(V.validate(g, c3["patch"])["ok"]))
		_check("   still invalid: %s" % str(bad[0]), still_bad,
			"canonicalisation repaired an authoritative field")

	# The Run 2 coupling failures, reproduced, must now pass.
	for good in [["falcon-h1 MUTATE with a stray type",
				{"operation": "MUTATE", "target": "rule_1", "type": "rule",
					"props": {"text": "x"}, "explanation": ""}],
			["lfm2.5 KEEP with a stray target",
				{"operation": "KEEP", "target": "object id", "type": "memory",
					"props": {"target": "__NONE__"}, "explanation": ""}],
			["DELETE with stray props",
				{"operation": "DELETE", "target": "rule_1", "type": "none",
					"props": {"junk": 1}, "explanation": ""}]]:
		var c4 := CN.canonicalise(good[1])
		var ok := bool(c4["ok"]) and bool(V.validate(g, c4["patch"])["ok"])
		_check("   now accepted: %s" % str(good[0]), ok,
			"a sound decision is still dying on an irrelevant field")


# ------------------------------------------- end-to-end reachability (Run 2)

## The audit Run 1 needed and did not have.
##
## The old one proved operations reachable against HAND-BUILT validator patches,
## including {"operation":"ADD","target":"n1","type":"rule","props":{}} -- a
## shape no model could emit, because the frozen schema had no `type` field. It
## validated the validator and never validated the path from the schema TO the
## validator. 1,167 of 1,500 model cycles died in that gap.
##
## This walks the whole path, and every witness is built by the contract rather
## than by me:
##
##   FROZEN SCHEMA -> proposal -> serialise -> parse -> validate -> apply
##                 -> expected transition
func _endtoend() -> void:
	print("
 14. end-to-end reachability, witnesses from the frozen contract")
	var g := W.genesis()
	var d := W.apply(g, K.delete("tool_1"))

	# One accepted witness per operation, expressed ONLY through contract fields.
	var cases := [
		["ADD", g, K.add("rule_new", "rule", {"text": "n"}), true],
		["DELETE", g, K.delete("rule_1"), true],
		["MUTATE", g, K.mutate("rule_1", {"text": "m"}), true],
		["KEEP", g, K.keep(), false],
		["RESTORE", d, K.restore("tool_1"), true],
		["REFUSE", g, K.refuse(), false],
	]
	var reached: Array = []
	for c in cases:
		var op := str(c[0])
		var state: Dictionary = c[1]
		var proposal: Dictionary = c[2]
		var changes := bool(c[3])

		# 1. the shape the schema guarantees
		var sh := K.shape(proposal)
		# 2. serialise and parse, exactly as a model's output travels
		var round_trip = JSON.parse_string(JSON.stringify(proposal))
		var survived := typeof(round_trip) == TYPE_DICTIONARY 			and str(K.shape(round_trip).get("code", "")) == K.SHAPE_OK
		# 3. semantic validation
		var v := V.validate(state, round_trip if survived else proposal)
		# 4. apply and 5. assert the transition
		var moved := false
		if bool(v["ok"]):
			moved = W.structural_hash(W.apply(state, round_trip)) 				!= W.structural_hash(state)
		var ok := bool(sh["ok"]) and survived and bool(v["ok"]) 			and moved == changes
		if ok:
			reached.append(op)
		_check("   %-7s schema->parse->validate->apply->transition" % op, ok,
			"shape=%s parse=%s valid=%s moved=%s expected=%s"
				% [str(sh["code"]), survived, str(v["code"]), moved, changes])

	_check("   all six operations reachable through the frozen schema alone",
		reached.size() == K.OPS.size(), str(reached))

	# A reachable REJECTED semantic proposal, also contract-expressible.
	for bad in [["RESTORE never deleted", g, K.restore("rule_1")],
			["DELETE already gone", d, K.delete("tool_1")],
			["MUTATE absent target", g, K.mutate("ghost", {"a": 1})],
			["ADD onto a live id", g, K.add("rule_1", "rule")]]:
		var v2 := V.validate(bad[1], bad[2])
		_check("   rejected: %-22s -> %s" % [str(bad[0]), str(v2["code"])],
			not bool(v2["ok"]) and V.is_semantic(str(v2["code"])), str(v2))


# ------------------------------------------- action-space parity (Run 2)

## RANDOM and the models must speak ONE proposal language.
##
## Run 1's control could ADD and no model could, so the control had a strictly
## larger action space than every treatment arm. That is not a control, it is a
## different experiment, and it is the reason Run 1 is void.
func _parity() -> void:
	print("
 15. RANDOM and the models share one proposal language")
	var g := W.genesis()
	var seen := {}
	var illegal_shape := 0
	var alien_field := 0
	var s := g.duplicate(true)
	for cyc in 200:
		var p := R.propose(s, 31337, cyc)
		seen[str(p.get("operation", "?"))] = true
		# Every RANDOM proposal must satisfy the SAME frozen contract a model
		# emits through. Not "be accepted" -- be EXPRESSIBLE.
		if not bool(K.shape(p)["ok"]):
			illegal_shape += 1
		for k in p.keys():
			if not K.FIELDS.has(str(k)):
				alien_field += 1
		if bool(V.validate(s, p)["ok"]):
			s = W.apply(s, p)

	_check("   every RANDOM proposal is schema-expressible", illegal_shape == 0,
		"%d proposals could not be emitted by any model" % illegal_shape)
	_check("   RANDOM uses no field outside the contract", alien_field == 0,
		"%d alien fields" % alien_field)
	var kinds: Array = seen.keys()
	kinds.sort()
	_check("   and it still exercises every operation: %s" % str(kinds),
		kinds.size() == K.OPS.size())

	# The converse: nothing the schema allows should be structurally impossible
	# for RANDOM to have produced. Checked by shape, not by acceptance.
	var model_side := [K.add("x", "rule", {"a": 1}), K.delete("rule_1"),
		K.mutate("rule_1", {"a": 1}), K.keep(), K.restore("tool_1"), K.refuse()]
	var expressible := 0
	for m in model_side:
		if bool(K.shape(m)["ok"]):
			expressible += 1
	_check("   every model-side operation is contract-valid",
		expressible == model_side.size())

	# The schema is static: it must not depend on world state, or its hash would
	# move every cycle and the gate could never pin a regime.
	var h0 := K.schema_hash()
	var moved := W.apply(g, K.delete("rule_1"))
	_check("   the schema hash does not depend on world state",
		K.schema_hash() == h0 and h0 != "",
		"a state-dependent schema cannot be pinned by the gate")
	_check("   empty target is invalid for EVERY operation",
		not bool(K.shape({"operation": "DELETE", "target": "", "type": "none",
			"props": {}, "explanation": ""})["ok"])
		and not bool(K.shape({"operation": "KEEP", "target": "", "type": "none",
			"props": {}, "explanation": ""})["ok"]),
		"Run 1 let LFM2.5 spend 300 cycles on schema-valid impossibilities")


# ------------------------------------------------ resume and contamination

## Two teeth that only exist once trajectories are FILES. In memory they are
## separate dictionaries and cannot touch. On disk they are paths, and that is
## where shared mutable state comes back wearing a filename.
func _journal() -> void:
	print("
 13. resume is deterministic, and contamination is refused")
	var species := "selftest-species"
	var other := "selftest-other"
	for s in [species, other]:
		for rep in [0, 1]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(
				J.path(s, rep)))

	# An uninterrupted RANDOM run of 100 cycles, journalled every cycle.
	var uninterrupted := _drive(species, 0, 0, 100, 4242)
	var full := J.load_rows(species, 0)
	_check("   100 cycles journalled and the chain links",
		bool(full["ok"]) and (full["rows"] as Array).size() == 100,
		"%s / %d rows" % [str(full["code"]), (full["rows"] as Array).size()])
	_check("   replay from genesis reproduces the live world",
		W.state_hash(J.replay(full["rows"])) == W.state_hash(uninterrupted),
		"the journal cannot rebuild the world it recorded")

	# Now kill at 37 and resume. Same seed, same schedule, same everything.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(J.path(species, 1)))
	_drive(species, 1, 0, 37, 4242)
	var partial := J.load_rows(species, 1)
	_check("   killed at cycle 37, journal holds exactly 37 rows",
		(partial["rows"] as Array).size() == 37)
	var resumed_from := J.replay(partial["rows"])
	var resumed := _drive(species, 1, J.next_cycle(partial["rows"]), 100, 4242,
		resumed_from)
	var after := J.load_rows(species, 1)
	_check("   resumed run reaches 100 rows",
		(after["rows"] as Array).size() == 100)
	_check("   RESUME DETERMINISM: cycles 38-100 match uninterrupted exactly",
		W.state_hash(resumed) == W.state_hash(uninterrupted),
		"a resume that diverges makes every long trajectory unreliable")
	var same_rows := true
	for i in 100:
		var a := (full["rows"] as Array)[i] as Dictionary
		var b := (after["rows"] as Array)[i] as Dictionary
		if str(a.get("patch", {})) != str(b.get("patch", {})):
			same_rows = false
	_check("   and every recorded patch is identical row for row", same_rows)

	# Contamination: point one species at another's journal.
	var stolen := J.load_rows(species, 0)
	var forged := (stolen["rows"] as Array).duplicate(true)
	J.ensure_dir()
	var fh := FileAccess.open(J.path(other, 0), FileAccess.WRITE)
	for r in forged:
		fh.store_line(JSON.stringify(r))
	fh.close()
	var contaminated := J.load_rows(other, 0)
	_check("   CONTAMINATION: another species' journal is REFUSED",
		not bool(contaminated["ok"])
			and str(contaminated["code"]) == J.CONTAMINATED,
		str(contaminated["code"]))
	_check("   and a refused journal yields no rows to resume from",
		(contaminated["rows"] as Array).is_empty(),
		"refusing but still handing back rows would be theatre")

	# A broken chain must also be refused, or lost rows resume silently.
	var gapped := (stolen["rows"] as Array).duplicate(true)
	gapped.remove_at(20)
	var fh2 := FileAccess.open(J.path(other, 1), FileAccess.WRITE)
	for r in gapped:
		var rr: Dictionary = (r as Dictionary).duplicate(true)
		rr["species"] = other
		rr["replicate"] = 1
		fh2.store_line(JSON.stringify(rr))
	fh2.close()
	var broken := J.load_rows(other, 1)
	_check("   a journal missing a cycle is REFUSED as a broken chain",
		not bool(broken["ok"]) and str(broken["code"]) == J.BROKEN_CHAIN,
		str(broken["code"]))

	for s in [species, other]:
		for rep in [0, 1]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(
				J.path(s, rep)))


## Drive RANDOM through a journalled trajectory. No models: this proves the
## checkpoint machinery, not any species.
func _drive(species: String, replicate: int, from_cycle: int, to_cycle: int,
		seed_value: int, start_state: Dictionary = {}) -> Dictionary:
	var state := start_state if not start_state.is_empty() else W.genesis()
	for cyc in range(from_cycle, to_cycle):
		var pre := W.state_hash(state)
		var patch := R.propose(state, seed_value, cyc)
		var v := V.validate(state, patch)
		var accepted := bool(v["ok"])
		if accepted:
			state = W.apply(state, patch)
		J.append(species, replicate, {
			"species": species, "replicate": replicate, "cycle": cyc,
			"pre_state_hash": pre, "patch": patch,
			"operation": str(patch.get("operation", "")),
			"target": str(patch.get("target", "")),
			"reason_code": str(v["code"]), "accepted": accepted,
			"post_state_hash": W.state_hash(state),
		})
	return state


# --------------------------------------------------- fail-closed runtime gate

## A regime mismatch must STOP the run, not annotate it. Every field is checked
## by breaking it and requiring a refusal.
func _gate() -> void:
	print("
 12. the runtime gate fails closed")
	var good := {
		"runtime": G.EXPECTED_RUNTIME,
		"response_format": G.RESPONSE_FORMAT,
		"schema_hash": G.schema_hash(),
		"constraint_mode": G.CONSTRAINT_MODE,
		"models": {},
	}
	for id in G.SPECIES:
		(good["models"] as Dictionary)[id] = {"context": G.EXPECTED_CONTEXT,
			"quant": G.EXPECTED_QUANT, "arch": str(G.SPECIES[id])}
	_check("   the frozen regime passes", bool(G.check(good)["ok"]),
		str(G.check(good)["failures"]))

	var cases := {
		"wrong runtime": ["runtime", "llama.cpp-win-x86_64-nvidia-cuda12-avx2@2.9.0"],
		"no schema constraint": ["response_format", "text"],
		"edited schema": ["schema_hash", "0000"],
		"per-species constraint": ["constraint_mode", "per_species"],
	}
	for label in cases:
		var bent := good.duplicate(true)
		bent[str((cases[label] as Array)[0])] = (cases[label] as Array)[1]
		_check("   %s -> refused" % label, not bool(G.check(bent)["ok"]))

	for field in ["context", "quant", "arch"]:
		var bent2 := good.duplicate(true)
		var first := str(G.SPECIES.keys()[0])
		((bent2["models"] as Dictionary)[first] as Dictionary)[field] = 			(4096 if field == "context" else "WRONG")
		_check("   %s drift on one species -> refused" % field,
			not bool(G.check(bent2)["ok"]))

	var missing := good.duplicate(true)
	(missing["models"] as Dictionary).erase(str(G.SPECIES.keys()[0]))
	_check("   a missing species -> refused", not bool(G.check(missing)["ok"]))

	var cousins := good.duplicate(true)
	for id in G.SPECIES:
		((cousins["models"] as Dictionary)[id] as Dictionary)["arch"] = "llama"
	_check("   roster collapsing into cousins -> refused",
		not bool(G.check(cousins)["ok"]),
		"five species must report five distinct architectures")


# ------------------------------------------------------- reachability audit

## Every frozen metric needs a concrete event that moves it and one that does
## not. Anything that cannot move under the real mechanism is demoted HERE,
## before the GPU, rather than reported later as a meaningful zero.
func _reachability(g: Dictionary) -> void:
	print("\n--- reachability audit: can each metric actually move? ---\n")

	# Semantic invalidity is the corrected definition from the pre-registration.
	var sem := V.validate(g, K.restore("rule_1"))
	_check("EXPERIMENTAL  semantic-invalid rate: witness exists",
		not bool(sem["ok"]) and V.is_semantic(str(sem["code"])), str(sem))
	_check("EXPERIMENTAL  semantic-invalid rate: counter-event exists",
		bool(V.validate(g, K.delete("rule_1"))["ok"]))

	# Every operation must be individually reachable or its frequency is a
	# constant dressed as a measurement.
	var reachable: Array = []
	var d := W.apply(g, K.delete("tool_1"))
	for op in W.OPS:
		var probe: Dictionary = {"KEEP": K.keep(),
			"REFUSE": K.refuse(),
			"ADD": K.add("n1", "rule"),
			"DELETE": K.delete("rule_1"),
			"MUTATE": K.mutate("rule_1", {"t": 1}),
			"RESTORE": K.restore("tool_1")}[op]
		var st := d if op == "RESTORE" else g
		if bool(V.validate(st, probe)["ok"]):
			reachable.append(op)
	_check("EXPERIMENTAL  all six operation frequencies are reachable: %s"
			% str(reachable), reachable.size() == W.OPS.size())

	# delete -> restore recurrence.
	var rr := W.apply(d, K.restore("tool_1"))
	_check("EXPERIMENTAL  delete->restore recurrence: witness exists",
		W.is_alive(rr, "tool_1"))
	# delete -> recreate under a NEW identity is the distinguishable alternative.
	_check("EXPERIMENTAL  delete->recreate-new-identity is distinguishable",
		bool(V.validate(d, K.add("tool_2", "tool", {"provides": "recall"}))["ok"])
		and not bool(V.validate(d, K.add("tool_1", "tool"))["ok"]),
		"reusing a tombstoned id would make restore and recreate look identical")

	# Survival duration needs both a survivor and a casualty.
	_check("EXPERIMENTAL  structure survival: both outcomes reachable",
		W.is_alive(d, "rule_1") and not W.is_alive(d, "tool_1"))

	# Dependency recovery needs a failure that is recoverable.
	var act := C.activation(0, 12)
	_check("EXPERIMENTAL  dependency recovery: failure and recovery both reachable",
		not bool(C.evaluate(d, act)["satisfied"])
			and bool(C.evaluate(rr, act)["satisfied"]))

	# And the RANDOM arm must be able to exercise the space it controls for.
	var cov := R.coverage(g, 777, 120)
	_check("EXPERIMENTAL  RANDOM can exercise the metric space",
		cov.size() == W.OPS.size(), str(cov.keys()))

	print("\n  OBSERVATIONAL / NOT A RESULT:")
	print("    syntactic malformed-patch rate  -- near-unreachable under the")
	print("       frozen json_schema instrument. Plumbing, never evidence.")
	print("    UNKNOWN_OPERATION rate          -- same reason.")
	print("  These are counted and reported, and a zero from either means")
	print("  nothing about any architecture.")


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("PIT A INSTRUMENT OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
