extends SceneTree

## Does the substrate arbiter obey the hardware, and can it report its own no?
##
##   godot --headless --path . --script scripts/arena/compute_arbiter_selftest.gd
##
## Pre-registered in docs/EXPERIMENT_METABOLISM.md at 858f1ab.
##
## OFFLINE. No LM Studio, no GPU, no generation. Every decision below is a pure
## function of a class and a resource state, which is itself one of the frozen
## teeth: grant, downgrade and deny must be reproducible from resource state
## alone or the metabolism is not measurable.
##
## SABOTAGE INSTRUCTIONS, so this is a test shown to fail rather than one that
## has only ever passed. In compute_arbiter.gd:
##
##   ceiling     move the MAX_PARAM_B check below the capacity arithmetic
##   capacity    change `<=` to `<` in the budget comparison
##   ladder      let the loop leap from HEAVY straight to SMALL
##   silence     return GRANTED instead of DOWNGRADED when step > start
##   residency   drop the `resident.has(cls)` free-reuse case
##
## Each must turn its own check red. Verified by hand before committing.

const A := preload("res://scripts/arena/compute_arbiter.gd")
const V := preload("res://scripts/arena/vram.gd")
const R := preload("res://scripts/arena/swarm_resolver.gd")

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


func _out(cls: String, resident: Array, available: Array = A.LADDER) -> Dictionary:
	return A.arbitrate(cls, resident, available)


func _run() -> void:
	print("=== compute arbiter selftest ===\n")

	print(" the sizes this whole experiment rests on")
	var s := A.class_gb(A.SMALL)
	var n := A.class_gb(A.NORMAL)
	var h := A.class_gb(A.HEAVY)
	print("    SMALL %.2f  NORMAL %.2f  HEAVY %.2f   budget %.2f"
		% [s, n, h, V.DEFAULT_BUDGET_GB])
	_check("HEAVY + NORMAL cannot coexist", h + n > V.DEFAULT_BUDGET_GB,
		"%.2f fits %.2f" % [h + n, V.DEFAULT_BUDGET_GB])
	_check("HEAVY + SMALL can", h + s <= V.DEFAULT_BUDGET_GB,
		"%.2f vs %.2f" % [h + s, V.DEFAULT_BUDGET_GB])
	_check("NORMAL + NORMAL can", n + n <= V.DEFAULT_BUDGET_GB,
		"%.2f vs %.2f" % [n + n, V.DEFAULT_BUDGET_GB])

	print("\n an empty card grants anything legal")
	for cls in A.LADDER:
		var o := _out(str(cls), [])
		_check("%s on an empty card is GRANTED" % cls,
			str(o["outcome"]) == A.GRANTED and str(o["granted_class"]) == str(cls),
			str(o))

	print("\n the parameter law bites independently of memory")
	# An 8B fits the budget and is still illegal. Proven here by asking the
	# arbiter for a class the catalog maps above the ceiling.
	var illegal_gb := V.estimate_gb(8.0, A.CLASS_QUANT)
	_check("an 8B at Q4 would FIT the budget", illegal_gb <= V.DEFAULT_BUDGET_GB,
		"%.2f vs %.2f" % [illegal_gb, V.DEFAULT_BUDGET_GB])
	_check("HEAVY at 7B is legal under the ceiling",
		float(A.CLASS_PARAMS[A.HEAVY]) <= ModelPolicy.MAX_PARAM_B)
	_check("a legal 7B HEAVY is granted on an empty card",
		str(_out(A.HEAVY, [])["outcome"]) == A.GRANTED)

	# THE ARBITER'S OWN CEILING BRANCH, exercised with an injected catalog that
	# maps HEAVY to 8B. With the frozen catalog nothing exceeds MAX_PARAM_B, so
	# this branch is unreachable and deleting it goes UNDETECTED -- which is how
	# this gap was found. The 8B fits memory at 5.15 GB, so a denial here can
	# only be the parameter law.
	var over := A.arbitrate(A.HEAVY, [], A.LADDER,
		{A.SMALL: 1.5, A.NORMAL: 4.0, A.HEAVY: 8.0})
	_check("an 8B HEAVY is DENIED by the arbiter on the ceiling",
		str(over["outcome"]) == A.DENIED
			and str(over["code"]) == A.OVER_PARAM_CEILING, str(over))
	_check("and it is denied on the LAW, not on capacity",
		str(over["code"]) != A.NO_CAPACITY,
		"the ceiling must be checked before any memory arithmetic")

	# THE BUDGET BOUNDARY, likewise unreachable with the frozen sizes: no
	# resident set plus a new model lands exactly on 6.00 GB, so `<=` versus `<`
	# is invisible and a sabotage of it survives undetected.
	#
	# The budget is injected as the EXACT float the state produces, because
	# chasing exact equality by choosing parameter counts does not work: the
	# nearest catalog lands on 5.99999998 and `<` still grants it. Computing the
	# total first and passing it as the budget makes the equality exact by
	# construction, which is the only way this boundary is testable at all.
	var edge_gb := A.occupancy_gb([A.NORMAL]) + A.class_gb(A.SMALL)
	var edge := A.arbitrate(A.SMALL, [A.NORMAL], A.LADDER, A.CLASS_PARAMS, edge_gb)
	_check("a grant landing EXACTLY on the budget is allowed",
		str(edge["outcome"]) == A.GRANTED and float(edge["headroom_gb"]) == 0.0,
		"the comparison must be <=, and got %s" % str(edge))
	var over_edge := A.arbitrate(A.SMALL, [A.NORMAL], A.LADDER, A.CLASS_PARAMS,
		edge_gb - 0.01)
	_check("one hundredth of a gigabyte short, and it is not granted",
		str(over_edge["outcome"]) != A.GRANTED, str(over_edge))

	print("\n scarcity forces a downgrade, and says so")
	# NORMAL resident, HEAVY requested: 2.75 + 4.55 = 7.30 > 6.00. The ladder
	# steps down to NORMAL, which is already resident and therefore free.
	var squeezed := _out(A.HEAVY, [A.NORMAL])
	_check("HEAVY requested while NORMAL is resident -> DOWNGRADED",
		str(squeezed["outcome"]) == A.DOWNGRADED, str(squeezed))
	_check("and the downgrade names what was actually served",
		str(squeezed["granted_class"]) != A.HEAVY
			and str(squeezed["granted_class"]) != "", str(squeezed))
	_check("a downgrade is never reported as GRANTED",
		str(squeezed["outcome"]) != A.GRANTED,
		"silent substitution is the failure this partition exists to prevent")

	# HEAVY resident, NORMAL requested: 4.55 + 2.75 = 7.30. Steps to SMALL,
	# 4.55 + 1.25 = 5.80, which fits.
	var other_way := _out(A.NORMAL, [A.HEAVY])
	_check("NORMAL requested while HEAVY is resident -> DOWNGRADED to SMALL",
		str(other_way["outcome"]) == A.DOWNGRADED
			and str(other_way["granted_class"]) == A.SMALL, str(other_way))

	print("\n a resident class is free to reuse")
	var reuse := _out(A.HEAVY, [A.HEAVY])
	_check("HEAVY requested while HEAVY is resident -> GRANTED at zero cost",
		str(reuse["outcome"]) == A.GRANTED and float(reuse["gb"]) == 0.0,
		str(reuse))

	print("\n an unavailable class steps down, never substitutes silently")
	var no_heavy := _out(A.HEAVY, [], [A.NORMAL, A.SMALL])
	_check("HEAVY unavailable -> DOWNGRADED, not GRANTED",
		str(no_heavy["outcome"]) == A.DOWNGRADED, str(no_heavy))
	_check("and the code says the model was unavailable",
		str(no_heavy["code"]) == A.MODEL_UNAVAILABLE, str(no_heavy))
	var nothing := _out(A.HEAVY, [], [])
	_check("nothing available at all -> DENIED",
		str(nothing["outcome"]) == A.DENIED
			and str(nothing["code"]) == A.MODEL_UNAVAILABLE, str(nothing))

	print("\n a full card steps down rather than overcommitting")
	# HEAVY + SMALL resident is 5.80 of 6.00. NORMAL cannot be added, and the
	# ladder lands on SMALL -- which is already resident and therefore free.
	var full := _out(A.NORMAL, [A.HEAVY, A.SMALL])
	_check("HEAVY + SMALL resident, NORMAL asked -> DOWNGRADED to a free SMALL",
		str(full["outcome"]) == A.DOWNGRADED
			and str(full["granted_class"]) == A.SMALL
			and float(full["gb"]) == 0.0, str(full))
	_check("no grant ever exceeds the budget",
		float(full["headroom_gb"]) >= 0.0, str(full))

	# NO_CAPACITY IS UNREACHABLE UNDER THIS LADDER, and saying so is the point.
	# In every state the arbiter can actually produce, SMALL is either already
	# resident (free) or there is room for it, so the deny-for-space branch
	# never fires. It is exercised here from a SYNTHETIC overcommitted state
	# that this arbiter would never grant, purely so the branch is guarded
	# against a future arbiter that can overcommit or evict. A clean zero from
	# an unreachable branch is not evidence -- rule 1, again.
	var synthetic := _out(A.NORMAL, [A.HEAVY, A.NORMAL])
	_check("[guard, synthetic state] a genuinely full card DENIES",
		str(synthetic["outcome"]) == A.DENIED
			and str(synthetic["code"]) == A.NO_CAPACITY, str(synthetic))
	_check("and that state is one this arbiter can never produce",
		A.occupancy_gb([A.HEAVY, A.NORMAL]) > V.DEFAULT_BUDGET_GB,
		"%.2f vs %.2f" % [A.occupancy_gb([A.HEAVY, A.NORMAL]),
			V.DEFAULT_BUDGET_GB])

	print("\n unknown classes are refused, never coerced")
	for bad in ["ENORMOUS", "", "heavy", "NORMAL "]:
		var o := _out(bad, [])
		_check("class %s -> DENIED / INVALID_CLASS" % [bad if bad != "" else "<empty>"],
			str(o["outcome"]) == A.DENIED and str(o["code"]) == A.INVALID_CLASS,
			str(o))

	print("\n every decision is classified, and reproducible from state alone")
	var unclassified := 0
	var irreproducible := 0
	var states := [[], [A.SMALL], [A.NORMAL], [A.HEAVY], [A.NORMAL, A.SMALL],
		[A.HEAVY, A.SMALL], [A.SMALL, A.SMALL]]
	for cls in ["SMALL", "NORMAL", "HEAVY", "ENORMOUS"]:
		for st in states:
			var first := A.arbitrate(str(cls), st)
			if not A.is_classified(first):
				unclassified += 1
			for _i in 8:
				if str(A.arbitrate(str(cls), st)) != str(first):
					irreproducible += 1
	_check("no unclassified outcome in %d decisions" % (4 * states.size()),
		unclassified == 0, "%d unclassified" % unclassified)
	_check("identical resource state gives an identical decision, 8x over",
		irreproducible == 0, "%d divergences" % irreproducible)

	print("\n the arbiter never sees, and never affects, the speaking slot")
	# The other half of "a request is not authority", from the substrate side.
	var by_class := {}
	for cls in R.CLASSES:
		var res: Dictionary = R.resolve([
			{"agent_id": "A", "eligible": true, "bid": 0.60, "requested_class": cls},
			{"agent_id": "B", "eligible": true, "bid": 0.40,
				"requested_class": "NORMAL"},
		])
		by_class[cls] = str(res.get("agent_id", "<none>"))
	_check("changing only requested_class cannot alter speaker selection",
		by_class["SMALL"] == by_class["NORMAL"]
			and by_class["NORMAL"] == by_class["HEAVY"], str(by_class))

	print("\n statistic 5 is VACUOUS for this arbiter, and that is recorded")
	# The arbiter does not evict, so "a unique model was evicted under pressure"
	# cannot fail here. A statistic that cannot fail is not evidence (rule 1),
	# so it is reported as vacuous rather than as a clean zero. When eviction is
	# added it becomes live and needs its own sabotage test.
	_check("no decision path unloads anything",
		not A.arbitrate(A.HEAVY, [A.NORMAL]).has("evicted"),
		"if eviction is added, statistic 5 stops being vacuous")

	_report()


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("COMPUTE ARBITER OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
