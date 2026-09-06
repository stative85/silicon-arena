extends SceneTree

## Can arbitrary producer output break the semantic, journal or consequence
## layers, or the whole pipeline replayed end to end?
##
##   godot --headless --path . --script scripts/arena/pit_pipeline_fuzz.gd
##
## Void records: results/PIT_A_RUN1_VOID.md, RUN2, RUN3.
##
## PRODUCER-SHAPED INPUTS FIRST, HARNESS-CONSTRUCTED SECOND. Four instrument
## failures in a row were found by the models within minutes of being allowed to
## speak, because every audit built its witnesses with the harness's own
## constructors. So this file is seeded with 183 proposals the five species
## ACTUALLY emitted across the three void runs
## (fixtures/producer_specimens.json), and only then generates synthetic ones.
##
## Four layers, in dependency order:
##
##   1. canonicaliser + validator   irrelevant variation must not change meaning
##   2. journal                     hostile rows must fail closed WITH A REASON
##   3. consequence evaluator       outcome depends on the declared dependency,
##                                  never on incidental representation
##   4. whole-pipeline chaos        live == replayed, across crashes
##
## NOTE ON WHAT THIS PROVES. These are instrument-engineering results. PIT A has
## produced ZERO valid architectural findings: all three runs are void. Nothing
## here changes that and nothing here may be cited as though it did.

const W := preload("res://scripts/arena/pit_world.gd")
const V := preload("res://scripts/arena/pit_validator.gd")
const K := preload("res://scripts/arena/pit_contract.gd")
const CN := preload("res://scripts/arena/pit_canonical.gd")
const CT := preload("res://scripts/arena/pit_canon_text.gd")
const IX := preload("res://scripts/arena/pit_interaction.gd")
const C := preload("res://scripts/arena/pit_consequence.gd")
const J := preload("res://scripts/arena/pit_journal.gd")

const SPECIMENS := "res://scripts/arena/fixtures/producer_specimens.json"

var _checks := 0
var _failures: Array[String] = []
var _h := 20260906


func _init() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("   ok   %s" % name)
	else:
		_failures.append(name)
		print("   FAIL %s  %s" % [name, detail])


func _next(n: int) -> int:
	_h = (_h ^ 0x9E3779B9) & 0xFFFFFFFF
	_h = (_h * 16777619) & 0xFFFFFFFF
	return (_h >> 8) % maxi(n, 1)


func _junk(depth: int) -> Variant:
	match _next(8 if depth < 4 else 4):
		0:
			return ["", "\"q\"", "back\\slash", "new\nline", "é中文", "  pad  ",
				"__NONE__", "none"][_next(8)]
		1:
			return _next(2) == 0
		2:
			return null
		3:
			return float(_next(100))
		4, 5:
			var d := {}
			for _i in _next(4):
				d["k%d" % _next(6)] = _junk(depth + 1)
			return d
		6:
			var a := []
			for _i in _next(4):
				a.append(_junk(depth + 1))
			return a
	return {"rule_1": {"description": "x", "text": "y"}, "deps": ["a", "b"]}


## Junk that is always a Dictionary, for the places props must be one.
func _junk_props(depth: int) -> Dictionary:
	var v: Variant = _junk(depth)
	return v if typeof(v) == TYPE_DICTIONARY else {"v": v}


## The decision a patch expresses, WITHOUT the prose. `explanation` is never
## authoritative, never reaches world state, and two patches differing only in
## it are the same decision. An earlier version of this test compared the whole
## canonical patch and reported 483 "distinct forms" for 500 identical DELETE
## decisions -- a bug in the test, not the instrument.
func _semantic(patch: Dictionary) -> String:
	return CT.canonical({"operation": patch.get("operation", ""),
		"target": patch.get("target", ""), "type": patch.get("type", ""),
		"props": patch.get("props", {})})


func _specimens() -> Array:
	var fh := FileAccess.open(SPECIMENS, FileAccess.READ)
	if fh == null:
		return []
	var d = JSON.parse_string(fh.get_as_text())
	fh.close()
	if typeof(d) != TYPE_DICTIONARY:
		return []
	var out: Array = []
	for s in d.get("specimens", []):
		out.append((s as Dictionary).get("proposal", {}))
	return out


func _run() -> void:
	print("=== PIT pipeline fuzz: producer-shaped inputs first ===\n")
	_layer1()
	_layer2()
	_layer3()
	_layer4()
	_report()


# ------------------------------------- 1. canonicaliser + validator

func _layer1() -> void:
	print(" 1. canonicaliser + validator")
	var specs := _specimens()
	_check("   183 real producer proposals loaded as seeds", specs.size() >= 180,
		"%d loaded" % specs.size())

	# Every real proposal must reach a DECISION -- accepted, or rejected with a
	# reason. None may crash, hang, or produce an unclassified outcome.
	var g := W.genesis()
	var unclassified := 0
	var decided := 0
	for p in specs:
		var c := CN.canonicalise(p)
		if bool(c["ok"]):
			var v := V.validate(g, c["patch"])
			if bool(v["ok"]) or str(v["code"]) != "":
				decided += 1
			else:
				unclassified += 1
		elif str(c["code"]) != "":
			decided += 1
		else:
			unclassified += 1
	_check("   every real proposal reaches a classified decision",
		unclassified == 0 and decided == specs.size(),
		"%d unclassified" % unclassified)

	# METAMORPHIC: irrelevant-field variation must NEVER change the decision.
	var forms := {}
	for _n in 500:
		var p := {"operation": "DELETE", "target": "rule_1",
			"type": ["none", "rule", "tool", "memory"][_next(4)],
			"props": _junk(0), "explanation": "%d" % _next(9999)}
		var c := CN.canonicalise(p)
		if bool(c["ok"]):
			forms[_semantic(c["patch"])] = true
	_check("   500 DELETE variants with junk in irrelevant fields -> 1 form",
		forms.size() == 1, "%d distinct canonical forms" % forms.size())

	var keeps := {}
	for _n in 500:
		var p2 := {"operation": "KEEP",
			"target": ["__NONE__", "rule_1", "anything", "  "][_next(4)],
			"type": ["none", "memory"][_next(2)], "props": _junk(0),
			"explanation": "%d" % _next(9999)}
		var c2 := CN.canonicalise(p2)
		if bool(c2["ok"]):
			keeps[_semantic(c2["patch"])] = true
	_check("   500 KEEP variants with junk elsewhere -> 1 form",
		keeps.size() == 1, "%d distinct" % keeps.size())

	# AUTHORITATIVE variation MUST change the decision.
	var by_target := {}
	for t in ["rule_1", "rule_2", "memory_1", "tool_1"]:
		var c3 := CN.canonicalise({"operation": "DELETE", "target": t,
			"type": "none", "props": {}, "explanation": ""})
		by_target[_semantic(c3["patch"])] = true
	_check("   but changing the target DOES change the decision",
		by_target.size() == 4, "%d distinct" % by_target.size())

	# Nested props survive the semantic layer with identity intact.
	var nested_bad := 0
	for _n in 300:
		var props: Variant = _junk(0)
		if typeof(props) != TYPE_DICTIONARY:
			continue
		var p3 := K.mutate("rule_1", props)
		var c4 := CN.canonicalise(p3)
		if not bool(c4["ok"]):
			continue
		if not bool(V.validate(g, c4["patch"])["ok"]):
			continue
		var live := W.apply(g, c4["patch"])
		var rt = JSON.parse_string(JSON.stringify(c4["patch"]))
		if W.state_hash(live) != W.state_hash(W.apply(g, rt)):
			nested_bad += 1
	_check("   nested-props MUTATEs keep identity through the semantic layer",
		nested_bad == 0, "%d divergences" % nested_bad)


# ------------------------------------------------------- 2. journal

func _layer2() -> void:
	print("\n 2. journal: hostile rows must fail closed WITH A REASON")
	var sp := "fuzz-species"
	var other := "fuzz-other"
	for s in [sp, other]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(J.path(s, 0)))

	# A good journal round-trips.
	var state := W.genesis()
	for cyc in 40:
		var pre := W.state_hash(state)
		var patch := K.mutate("rule_1", _junk_props(0) if _next(2) == 0 else {"t": cyc})
		var v := V.validate(state, patch)
		if bool(v["ok"]):
			state = W.apply(state, patch)
		J.append(sp, 0, {"species": sp, "replicate": 0, "cycle": cyc,
			"pre_state_hash": pre, "patch": patch, "accepted": bool(v["ok"]),
			"reason_code": str(v["code"]), "post_state_hash": W.state_hash(state)})
	var good := J.load_rows(sp, 0)
	_check("   40 nested-props rows load and replay exactly",
		bool(good["ok"]) and W.state_hash(J.replay(good["rows"]))
			== W.state_hash(state), str(good["code"]))

	# Hostile rows, each with the reason it must be refused for.
	var rows: Array = (good["rows"] as Array)
	var cases := {
		"wrong species": func(r): r["species"] = other,
		"wrong replicate": func(r): r["replicate"] = 9,
		"broken parent link": func(r): r["pre_state_hash"] = "deadbeef",
	}
	for label in cases:
		var forged: Array = []
		for r in rows:
			forged.append((r as Dictionary).duplicate(true))
		(cases[label] as Callable).call(forged[20])
		J.ensure_dir()
		var fh := FileAccess.open(J.path(other, 0), FileAccess.WRITE)
		for r in forged:
			var rr: Dictionary = r
			if str(label) != "wrong species":
				rr = (r as Dictionary).duplicate(true)
				if str(rr.get("species", "")) == sp:
					rr["species"] = other
			fh.store_line(JSON.stringify(rr))
		fh.close()
		var res := J.load_rows(other, 0)
		var refused := not bool(res["ok"])
		_check("   %-20s -> refused as %s" % [str(label), str(res["code"])],
			refused and str(res["code"]) != "",
			"a journal must fail closed WITH a reason, not just fail")
		_check("   %-20s -> yields no rows" % str(label),
			(res["rows"] as Array).is_empty())

	for s in [sp, other]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(J.path(s, 0)))


# ------------------------------------------- 3. consequence evaluator

func _layer3() -> void:
	print("\n 3. consequences depend on the declared dependency, nothing else")
	var act := C.activation(0, 12)
	_check("   an activation exists to test", not act.is_empty())

	# Same dependency status, wildly different incidental world content.
	var with_dep: Array = []
	var without_dep: Array = []
	for _n in 200:
		var g := W.genesis()
		# Junk that has nothing to do with tool_1.
		for _i in _next(4):
			g = W.apply(g, K.add("noise_%d" % _next(9999),
				K.OBJECT_TYPES[_next(K.OBJECT_TYPES.size() - 1)], _junk_props(0)))
		var mutated := W.apply(g, K.mutate("rule_1", _junk_props(0)))
		with_dep.append(bool(C.evaluate(mutated, act)["satisfied"]))
		without_dep.append(bool(C.evaluate(
			W.apply(mutated, K.delete("tool_1")), act)["satisfied"]))
	var all_sat := true
	var all_unsat := true
	for b in with_dep:
		if not b:
			all_sat = false
	for b in without_dep:
		if b:
			all_unsat = false
	_check("   200 noisy worlds WITH the dependency: all satisfied", all_sat,
		"incidental content changed a consequence outcome")
	_check("   200 noisy worlds WITHOUT it: all unsatisfied", all_unsat)

	# Insertion-order and representation must not matter.
	var g2 := W.apply(W.genesis(), K.mutate("tool_1",
		{"a": {"x": 1, "y": 2}, "b": [1, 2]}))
	var rt = JSON.parse_string(JSON.stringify(g2))
	_check("   a round-tripped world evaluates identically",
		str(C.evaluate(g2, act)) == str(C.evaluate(rt, act)))

	# A restored dependency satisfies again; an equivalent structure under a NEW
	# identity does NOT, because the schedule names an identity.
	var gone := W.apply(W.genesis(), K.delete("tool_1"))
	_check("   restoring the dependency satisfies it again",
		bool(C.evaluate(W.apply(gone, K.restore("tool_1")), act)["satisfied"]))
	_check("   an equivalent structure under a new id does NOT satisfy it",
		not bool(C.evaluate(W.apply(gone, K.add("tool_2", "tool",
			{"provides": "recall"})), act)["satisfied"]),
		"the schedule names an identity, and recreate is not restore")


# ------------------------------------------- 4. whole-pipeline chaos

func _layer4() -> void:
	print("\n 4. whole-pipeline chaos: live == replayed, across crashes")
	var sp := "chaos"
	for rep in [0]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(J.path(sp, rep)))

	var state := W.genesis()
	var inter := IX.genesis()
	var obs_seen := {}
	var live_conseq: Array = []

	for cyc in 400:
		# A mix of legal, illegal, no-op and outright malformed proposals.
		var raw: Variant = null
		match _next(6):
			0:
				raw = K.keep()
			1:
				raw = K.refuse()
			2:
				raw = {"operation": "DELETE", "target": "rule_1", "type": "tool",
					"props": _junk_props(0), "explanation": "junk"}
			3:
				raw = K.mutate("rule_1", _junk_props(0))
			4:
				raw = K.add("n_%d" % cyc, "memory", _junk_props(0))
			_:
				raw = {"operation": "RESTORE", "target": "nothing_here",
					"type": "none", "props": {}, "explanation": ""}

		var pre := W.state_hash(state)
		obs_seen[IX.observation_hash(W.canonical_text(state), inter)] = true
		var c := CN.canonicalise(raw)
		var accepted := false
		var reason := str(c["code"])
		var patch := {}
		if bool(c["ok"]):
			patch = c["patch"]
			var v := V.validate(state, patch)
			reason = str(v["code"])
			accepted = bool(v["ok"])
			if accepted:
				state = W.apply(state, patch)
		inter = IX.advance(inter, str(raw.get("operation", "")),
			IX.ACCEPTED if accepted else IX.REJECTED, reason)
		live_conseq.append(str(C.evaluate(state, C.activation(0, cyc))))
		J.append(sp, 0, {"species": sp, "replicate": 0, "cycle": cyc,
			"pre_state_hash": pre, "patch": patch, "accepted": accepted,
			"reason_code": reason, "operation": str(raw.get("operation", "")),
			"outcome": IX.ACCEPTED if accepted else IX.REJECTED,
			"post_state_hash": W.state_hash(state)})

	_check("   400 chaotic cycles: every observation distinct",
		obs_seen.size() == 400, "%d distinct of 400" % obs_seen.size())

	var loaded := J.load_rows(sp, 0)
	_check("   the chaotic journal still loads", bool(loaded["ok"]),
		str(loaded["code"]))
	var replayed := J.replay(loaded["rows"])
	_check("   live state == replayed state",
		W.state_hash(state) == W.state_hash(replayed))

	# Interaction and consequences reconstructed from the journal alone.
	var rinter := IX.genesis()
	var rconseq: Array = []
	var rstate := W.genesis()
	for r in (loaded["rows"] as Array):
		var row: Dictionary = r
		if bool(row.get("accepted", false)):
			rstate = W.apply(rstate, row.get("patch", {}))
		rinter = IX.advance(rinter, str(row.get("operation", "")),
			str(row.get("outcome", IX.REJECTED)), str(row.get("reason_code", "")))
		rconseq.append(str(C.evaluate(rstate, C.activation(0, int(row["cycle"])))))
	_check("   live interaction == replayed interaction",
		str(inter) == str(rinter))
	_check("   live consequence outcomes == replayed outcomes",
		str(live_conseq) == str(rconseq))

	# Crash and resume at 40 arbitrary points: each must land on the same world.
	var mismatches := 0
	for _n in 40:
		var cut := 1 + _next(399)
		var partial: Array = (loaded["rows"] as Array).slice(0, cut)
		var resumed := J.replay(partial)
		var expected := W.genesis()
		for i in cut:
			var row2: Dictionary = (loaded["rows"] as Array)[i]
			if bool(row2.get("accepted", false)):
				expected = W.apply(expected, row2.get("patch", {}))
		if W.state_hash(resumed) != W.state_hash(expected):
			mismatches += 1
	_check("   40 crash/resume points all reconstruct exactly",
		mismatches == 0, "%d mismatches" % mismatches)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(J.path(sp, 0)))


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("PIT PIPELINE FUZZ OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
