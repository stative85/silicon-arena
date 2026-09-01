extends SceneTree

## Does roster ordering actually reduce cold model loads?
##
##   godot --headless --path . --script scripts/arena/turn_order_selftest.gd
##
## Deterministic: pure functions over literal rosters, no LM Studio, no GPU.
##
## The property under test is not "the code runs". It is the arithmetic claim
## the feature is sold on: grouping a roster of N agents over M models yields
## exactly M cold loads per round, which is the optimum. Every check below
## asserts a NUMBER, because "it reordered something" is not evidence.

const TO := preload("res://scripts/arena/turn_order.gd")

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


func _r(models: Array) -> Array:
	var out: Array = []
	for i in models.size():
		out.append({"name": "Agent%d" % i, "model": models[i]})
	return out


func _models_of(roster: Array) -> Array:
	var out: Array = []
	for a in roster:
		out.append(a["model"])
	return out


func _run() -> void:
	print("=== turn order / swap cost ===\n")

	# --- the cost model itself -------------------------------------------
	# 4, not 5: walked in a cycle the trailing A wraps onto the leading A and
	# that one handover is free. This test was written expecting 5 and the
	# implementation was right — the wrap is easy to forget, so it is pinned.
	_check("interleaved A B A B A costs 4 swaps per round (the wrap is free)",
		TO.swaps_per_round(_r(["A", "B", "A", "B", "A"])) == 4,
		"got %d" % TO.swaps_per_round(_r(["A", "B", "A", "B", "A"])))

	_check("grouped A A A B B costs 2 swaps per round",
		TO.swaps_per_round(_r(["A", "A", "A", "B", "B"])) == 2,
		"got %d" % TO.swaps_per_round(_r(["A", "A", "A", "B", "B"])))

	# The wrap is real: the last agent hands over to the first next round.
	_check("the wrap-around swap is counted (A A B B is 2, not 1)",
		TO.swaps_per_round(_r(["A", "A", "B", "B"])) == 2,
		"got %d" % TO.swaps_per_round(_r(["A", "A", "B", "B"])))

	_check("one shared model still pays the initial load (1, not 0)",
		TO.swaps_per_round(_r(["A", "A", "A", "A", "A"])) == 1,
		"got %d" % TO.swaps_per_round(_r(["A", "A", "A", "A", "A"])))

	_check("five distinct models cost five swaps",
		TO.swaps_per_round(_r(["A", "B", "C", "D", "E"])) == 5,
		"got %d" % TO.swaps_per_round(_r(["A", "B", "C", "D", "E"])))

	_check("an empty roster costs nothing",
		TO.swaps_per_round([]) == 0, "got %d" % TO.swaps_per_round([]))

	# --- grouping reaches the optimum ------------------------------------
	var worst := _r(["A", "B", "A", "B", "A"])
	var fixed := TO.group_by_model(worst)
	_check("grouping cuts this roster from 4 swaps to 2",
		TO.swaps_per_round(fixed) == 2,
		"got %d from %s" % [TO.swaps_per_round(fixed), str(_models_of(fixed))])

	_check("grouping loses no agents",
		fixed.size() == worst.size(),
		"%d in, %d out" % [worst.size(), fixed.size()])

	# Optimality, not just improvement: M models must cost exactly M.
	for case in [["A", "B", "A", "B", "A"], ["A", "B", "C", "A", "B"],
			["X", "Y", "X"], ["A", "A", "B", "C", "B"], ["Q"]]:
		var g := TO.group_by_model(_r(case))
		var m: int = TO.distinct_models(_r(case))
		_check("%s groups to exactly %d swap(s) (its optimum)" % [str(case), m],
			TO.swaps_per_round(g) == m,
			"got %d" % TO.swaps_per_round(g))

	# --- grouping must not damage what is already good -------------------
	var distinct := _r(["A", "B", "C", "D", "E"])
	_check("a fully distinct roster is left in its original order",
		_models_of(TO.group_by_model(distinct)) == ["A", "B", "C", "D", "E"],
		"got %s" % str(_models_of(TO.group_by_model(distinct))))

	_check("an already-grouped roster is unchanged",
		_models_of(TO.group_by_model(_r(["A", "A", "B", "B"]))) == ["A", "A", "B", "B"],
		"reordered a roster that was already optimal")

	# --- stability, because the result is written to a preset file -------
	var s1 := TO.group_by_model(_r(["B", "A", "B", "A"]))
	var s2 := TO.group_by_model(_r(["B", "A", "B", "A"]))
	_check("grouping is deterministic across calls",
		_models_of(s1) == _models_of(s2), "two calls disagreed")

	_check("first-seen model order is preserved (B before A)",
		_models_of(s1) == ["B", "B", "A", "A"],
		"got %s" % str(_models_of(s1)))

	var named := [{"name": "First", "model": "A"}, {"name": "Second", "model": "B"},
		{"name": "Third", "model": "A"}]
	var gn := TO.group_by_model(named)
	_check("agents keep their relative order within a model group",
		gn[0]["name"] == "First" and gn[1]["name"] == "Third",
		"got %s, %s" % [gn[0]["name"], gn[1]["name"]])

	# --- degenerate input must not crash a match at turn one -------------
	var junk := [{"name": "NoModel"}, {"name": "Ok", "model": "A"}]
	var gj := TO.group_by_model(junk)
	_check("an agent with no model field is tolerated, not dropped",
		gj.size() == 2, "got %d" % gj.size())

	_report()


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("TURN ORDER OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
