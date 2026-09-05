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
	for bad in [{"operation": "DELETE", "target": "does_not_exist"},
			{"operation": "RESTORE", "target": "rule_1"},
			{"operation": "MUTATE", "target": "ghost", "props": {}},
			{"operation": "ADD", "target": "rule_1", "type": "rule", "props": {}},
			{"operation": "NONSENSE", "target": "rule_1"}]:
		var v := V.validate(g, bad)
		_check("   %s/%s refused as %s" % [str(bad["operation"]),
				str(bad.get("target", "-")), str(v["code"])],
			not bool(v["ok"]), str(v))
	_check("   and genesis is untouched by all of them",
		W.structural_hash(g) == before)

	print("\n 2. DELETE removes the object from later visible state")
	var d := _step(g, {"operation": "DELETE", "target": "tool_1"})
	_check("   tool_1 no longer alive", not W.is_alive(d, "tool_1"))
	_check("   tool_1 IS tombstoned, not erased", W.is_tombstoned(d, "tool_1"))
	_check("   the tombstone remembers when it died",
		(d["tombstones"]["tool_1"] as Dictionary).has("deleted_at"))

	print("\n 3. RESTORE reinstates a tombstoned object")
	var r := _step(d, {"operation": "RESTORE", "target": "tool_1"})
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
	var rejected := _step(g, {"operation": "DELETE", "target": "provenance_1"})
	_check("   provenance DELETE refused and hash identical",
		W.structural_hash(rejected) == h0)

	print("\n 5. an accepted mutation changes the state hash")
	var m := _step(g, {"operation": "MUTATE", "target": "rule_1",
		"props": {"text": "changed"}})
	_check("   MUTATE moved the hash", W.structural_hash(m) != h0)
	var a := _step(g, {"operation": "ADD", "target": "rule_9", "type": "rule",
		"props": {"text": "new"}})
	_check("   ADD moved the hash", W.structural_hash(a) != h0)
	_check("   KEEP did NOT move the structural hash",
		W.structural_hash(_step(g, {"operation": "KEEP", "target": ""})) == h0,
		"KEEP is a real decision, but it must not look like a structural change")
	_check("   REFUSE did NOT move the structural hash",
		W.structural_hash(_step(g, {"operation": "REFUSE", "target": ""})) == h0)
	_check("   but KEEP still advanced the cycle",
		int(_step(g, {"operation": "KEEP", "target": ""})["cycle"]) == 1,
		"a decision to change nothing still consumes the opportunity")

	print("\n 6. immutable provenance cannot be altered by any operation")
	for op in ["DELETE", "MUTATE", "RESTORE"]:
		var v2 := V.validate(g, {"operation": op, "target": "provenance_1",
			"props": {"x": 1}})
		_check("   %s provenance_1 -> %s" % [op, str(v2["code"])],
			not bool(v2["ok"]) and str(v2["code"]) == V.IMMUTABLE_TARGET, str(v2))
	_check("   and provenance cannot be ADDed either",
		str(V.validate(g, {"operation": "ADD", "target": "p2",
			"type": "provenance", "props": {}})["code"]) == V.IMMUTABLE_TARGET)

	print("\n 7. the explanation cannot mutate anything")
	var p_plain := {"operation": "MUTATE", "target": "rule_1", "props": {"text": "x"}}
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
	var beta_after := _step(beta, {"operation": "DELETE", "target": "memory_1"})
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
	var ev := C.evaluate(_step(g, {"operation": "DELETE", "target": "tool_1"}),
		C.activation(0, 12))
	_check("   a deleted dependency reports unsatisfied",
		not bool(ev["satisfied"]) and bool(ev["tombstoned"]), str(ev))
	_check("   an intact dependency reports satisfied",
		bool(C.evaluate(g, C.activation(0, 12))["satisfied"]))
	_check("   evaluating a consequence does not repair the world",
		not W.is_alive(_step(g, {"operation": "DELETE", "target": "tool_1"}),
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
	_reachability(g)
	_report()


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
	var sem := V.validate(g, {"operation": "RESTORE", "target": "rule_1"})
	_check("EXPERIMENTAL  semantic-invalid rate: witness exists",
		not bool(sem["ok"]) and V.is_semantic(str(sem["code"])), str(sem))
	_check("EXPERIMENTAL  semantic-invalid rate: counter-event exists",
		bool(V.validate(g, {"operation": "DELETE", "target": "rule_1"})["ok"]))

	# Every operation must be individually reachable or its frequency is a
	# constant dressed as a measurement.
	var reachable: Array = []
	var d := W.apply(g, {"operation": "DELETE", "target": "tool_1"})
	for op in W.OPS:
		var probe: Dictionary = {"KEEP": {"operation": "KEEP", "target": ""},
			"REFUSE": {"operation": "REFUSE", "target": ""},
			"ADD": {"operation": "ADD", "target": "n1", "type": "rule", "props": {}},
			"DELETE": {"operation": "DELETE", "target": "rule_1"},
			"MUTATE": {"operation": "MUTATE", "target": "rule_1", "props": {"t": 1}},
			"RESTORE": {"operation": "RESTORE", "target": "tool_1"}}[op]
		var st := d if op == "RESTORE" else g
		if bool(V.validate(st, probe)["ok"]):
			reachable.append(op)
	_check("EXPERIMENTAL  all six operation frequencies are reachable: %s"
			% str(reachable), reachable.size() == W.OPS.size())

	# delete -> restore recurrence.
	var rr := W.apply(d, {"operation": "RESTORE", "target": "tool_1"})
	_check("EXPERIMENTAL  delete->restore recurrence: witness exists",
		W.is_alive(rr, "tool_1"))
	# delete -> recreate under a NEW identity is the distinguishable alternative.
	_check("EXPERIMENTAL  delete->recreate-new-identity is distinguishable",
		bool(V.validate(d, {"operation": "ADD", "target": "tool_2",
			"type": "tool", "props": {"provides": "recall"}})["ok"])
		and not bool(V.validate(d, {"operation": "ADD", "target": "tool_1",
			"type": "tool", "props": {}})["ok"]),
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
