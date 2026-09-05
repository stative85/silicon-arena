extends SceneTree

## Can each compute class actually be requested, and do the hard laws bite?
##
##   godot --headless --path . --script scripts/arena/swarm_request_selftest.gd
##
## Pre-registered in docs/EXPERIMENT_METABOLISM.md at 858f1ab.
##
## THIS IS PREFLIGHT A, THE REACHABILITY CONTROL, AND IT IS NOT A RESULT.
## It establishes only that the frozen request policy CAN produce three classes
## on synthetic local views. Whether it DOES, on realistic states, is preflight
## B -- a replay of already-canonical views -- and that is a separate check
## which is itself explicitly not independent validation.
##
## The gate this replaces could only ever VOID. An earlier draft measured class
## frequencies in a dry run with no generation, where `named_recently` is false
## by construction, so HEAVY was unreachable and a >=10%-per-class floor would
## have failed a mechanism that works perfectly. Rule 1 arriving through the
## front door wearing a resource badge, and the third time that shape has
## appeared in this project. Splitting reachability from natural mix is the fix.
##
## Deterministic: pure functions over synthetic views, no LM Studio, no GPU.

const Q := preload("res://scripts/arena/swarm_request.gd")
const B := preload("res://scripts/arena/swarm_bid.gd")
const R := preload("res://scripts/arena/swarm_resolver.gd")
const V := preload("res://scripts/arena/vram.gd")

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


func _view(since: float, named: bool, share: float) -> Dictionary:
	return B.local_view(int(since), named, share)


func _run() -> void:
	print("=== swarm request selftest (preflight A: reachability) ===\n")

	# ---------------------------------------------------------- reachability
	#
	# Every tier must fire. SABOTAGE INSTRUCTIONS, so this is a test that has
	# been shown to fail rather than one that has only ever passed. In
	# swarm_request.gd's tier():
	#
	#   HEAVY   change `bid > HEAVY_ABOVE` to `bid > 2.0`, unreachable
	#   NORMAL  change `bid >= NORMAL_FROM` to `bid >= 2.0`
	#   SMALL   make the final `return SMALL` return NORMAL
	#   MONO    swap the HEAVY and SMALL returns, or flip `>` to `<`
	#
	# Each edit must turn its own check red. Verified by hand before this file
	# was committed; re-verify after any change to the policy or the weights.
	print(" reachability: every tier fires from a real local view")
	# Named AND saturated: two stacked pressures, 0.30 + 0.50 = 0.80.
	var heavy := Q.request(_view(B.STARVATION_SATURATION, true, 0.2))
	_check("stacked pressures -> HEAVY", heavy == Q.HEAVY, "got %s" % heavy)

	# Saturated starvation alone: exactly 0.50, the largest single component.
	var normal := Q.request(_view(B.STARVATION_SATURATION, false, 0.2))
	_check("one strong pressure alone -> NORMAL", normal == Q.NORMAL,
		"got %s" % normal)

	# One turn silent, unnamed, fair airtime: 0.0625.
	var small := Q.request(_view(1, false, 0.2))
	_check("background willingness -> SMALL", small == Q.SMALL, "got %s" % small)

	_check("the three tiers are distinct",
		heavy != normal and normal != small and heavy != small,
		"a policy that returns one class cannot demonstrate heterogeneity")

	print("\n cut points are the bid weights themselves")
	_check("NORMAL begins at W_ADDRESSED", Q.NORMAL_FROM == B.W_ADDRESSED,
		"%.4f vs %.4f" % [Q.NORMAL_FROM, B.W_ADDRESSED])
	_check("HEAVY begins above W_STARVATION", Q.HEAVY_ABOVE == B.W_STARVATION,
		"%.4f vs %.4f" % [Q.HEAVY_ABOVE, B.W_STARVATION])

	# The structural consequence, and the reason airtime was rejected as a
	# trigger: the smallest component cannot reach the NORMAL cut on its own.
	_check("airtime alone can NEVER reach NORMAL",
		B.W_AIRTIME < Q.NORMAL_FROM,
		"%.2f vs %.2f" % [B.W_AIRTIME, Q.NORMAL_FROM])
	_check("HEAVY is unreachable from any single component",
		maxf(maxf(B.W_STARVATION, B.W_ADDRESSED), B.W_AIRTIME) <= Q.HEAVY_ABOVE,
		"a single pressure could reach HEAVY, so stacking is not forced")

	# ------------------------------------------------------- monotonicity
	#
	# Statistic 8: raising a bid while holding everything else fixed may never
	# request a LOWER class. An agent that wants the slot more must never be
	# assigned less compute -- that is not a metabolism, it is a bug with a
	# story attached.
	#
	# SABOTAGE: in swarm_request.gd swap the HEAVY and SMALL returns, or change
	# `bid > HEAVY_ABOVE` to `bid < HEAVY_ABOVE`. Either must turn this red.
	print("\n monotonicity: more want, never less compute")
	var rank := {Q.SMALL: 0, Q.NORMAL: 1, Q.HEAVY: 2, "": -1}
	var last := -1
	var violations := 0
	var worst := ""
	for i in 1001:
		var b := float(i) / 1000.0
		var r := int(rank[Q.tier(b)])
		if r < last:
			violations += 1
			if worst == "":
				worst = "bid %.3f dropped to %s" % [b, Q.tier(b)]
		last = r
	_check("1001 bids from 0.000 to 1.000 never step down",
		violations == 0, "%d violation(s); %s" % [violations, worst])

	_check("the sweep actually reached all three tiers",
		Q.tier(0.05) == Q.SMALL and Q.tier(0.40) == Q.NORMAL
			and Q.tier(0.90) == Q.HEAVY,
		"a monotone constant function would pass the check above")

	print("\n tier boundaries are closed on the documented side")
	_check("exactly W_ADDRESSED is NORMAL", Q.tier(B.W_ADDRESSED) == Q.NORMAL)
	_check("just below W_ADDRESSED is SMALL",
		Q.tier(B.W_ADDRESSED - 0.001) == Q.SMALL)
	_check("exactly W_STARVATION is NORMAL", Q.tier(B.W_STARVATION) == Q.NORMAL)
	_check("just above W_STARVATION is HEAVY",
		Q.tier(B.W_STARVATION + 0.001) == Q.HEAVY)
	_check("a NAN bid requests nothing", Q.tier(NAN) == "")

	# ------------------------------------------------------- malformed views
	print("\n a malformed view requests nothing, and is never defaulted")
	_check("missing key -> no request", Q.request({"named_recently": true}) == "")
	_check("wrong type -> no request",
		Q.request({"turns_since_spoke": 1, "named_recently": "yes",
			"airtime_share": 0.2}) == "")
	_check("negative silence -> no request",
		Q.request(_view(-1, false, 0.2)) == "")

	# -------------------------------------------- a request is not authority
	#
	# The invariant that keeps metabolism from becoming a second bid channel.
	print("\n a request is not authority: class cannot move an allocation")
	var lo_heavy := {"agent_id": "A", "eligible": true, "bid": 0.20,
		"requested_class": "HEAVY"}
	var hi_small := {"agent_id": "B", "eligible": true, "bid": 0.80,
		"requested_class": "SMALL"}
	_check("the higher bid wins even when the loser asked for HEAVY",
		str(R.resolve([lo_heavy, hi_small]).get("agent_id", "")) == "B")

	var winner_by_class := {}
	for c in R.CLASSES:
		var out: Dictionary = R.resolve([
			{"agent_id": "A", "eligible": true, "bid": 0.60, "requested_class": c},
			{"agent_id": "B", "eligible": true, "bid": 0.40, "requested_class": "NORMAL"},
		])
		winner_by_class[c] = str(out.get("agent_id", "<none>"))
	_check("changing only the class never changes the winner",
		winner_by_class["SMALL"] == winner_by_class["NORMAL"]
			and winner_by_class["NORMAL"] == winner_by_class["HEAVY"],
		str(winner_by_class))

	# ------------------------------------------------------ vocabulary teeth
	print("\n an unrecognised class is refused, never coerced to a default")
	_check("class ENORMOUS -> MALFORMED_BID",
		str(R.resolve([{"agent_id": "A", "eligible": true, "bid": 0.5,
			"requested_class": "ENORMOUS"}]).get("code", "")) == R.MALFORMED_BID)
	_check("empty class -> MALFORMED_BID",
		str(R.resolve([{"agent_id": "A", "eligible": true, "bid": 0.5,
			"requested_class": ""}]).get("code", "")) == R.MALFORMED_BID)
	_check("lowercase class -> MALFORMED_BID",
		str(R.resolve([{"agent_id": "A", "eligible": true, "bid": 0.5,
			"requested_class": "heavy"}]).get("code", "")) == R.MALFORMED_BID)
	_check("non-string class -> MALFORMED_BID",
		str(R.resolve([{"agent_id": "A", "eligible": true, "bid": 0.5,
			"requested_class": 2}]).get("code", "")) == R.MALFORMED_BID)
	_check("a missing class is still MALFORMED_BID",
		str(R.resolve([{"agent_id": "A", "eligible": true,
			"bid": 0.5}]).get("code", "")) == R.MALFORMED_BID)
	_check("a reason field is still refused alongside a legal class",
		str(R.resolve([{"agent_id": "A", "eligible": true, "bid": 0.5,
			"requested_class": "HEAVY", "reason": "this matters"}])
			.get("code", "")) == R.MALFORMED_BID)

	# --------------------------------------- the two hard laws are separable
	#
	# The parameter ceiling and the memory budget must be independently alive.
	# An 8B at Q4 FITS the budget and is still illegal, so a refusal there
	# cannot be explained away as running out of memory -- and that is the only
	# way to know MAX_PARAM_B is doing work of its own.
	print("\n the 7B law and the VRAM law are independently alive")
	var small_gb := V.estimate_gb(1.5, "Q4_K_M")
	var normal_gb := V.estimate_gb(4.0, "Q4_K_M")
	var heavy_gb := V.estimate_gb(7.0, "Q4_K_M")
	var illegal_gb := V.estimate_gb(8.0, "Q4_K_M")
	print("    SMALL %.2f  NORMAL %.2f  HEAVY %.2f  8B %.2f  budget %.2f"
		% [small_gb, normal_gb, heavy_gb, illegal_gb, V.DEFAULT_BUDGET_GB])

	_check("an 8B at Q4 FITS the budget on its own",
		illegal_gb <= V.DEFAULT_BUDGET_GB,
		"%.2f vs %.2f" % [illegal_gb, V.DEFAULT_BUDGET_GB])
	_check("and 8B is still over the parameter ceiling",
		8.0 > ModelPolicy.MAX_PARAM_B,
		"ceiling is %.1fB" % ModelPolicy.MAX_PARAM_B)
	_check("a 7B is legal by the parameter ceiling",
		7.0 <= ModelPolicy.MAX_PARAM_B)

	# And the scarcity that makes the whole experiment worth running.
	_check("HEAVY + NORMAL do NOT fit together",
		heavy_gb + normal_gb > V.DEFAULT_BUDGET_GB,
		"%.2f fits %.2f" % [heavy_gb + normal_gb, V.DEFAULT_BUDGET_GB])
	_check("HEAVY + SMALL do fit together",
		heavy_gb + small_gb <= V.DEFAULT_BUDGET_GB,
		"%.2f vs %.2f" % [heavy_gb + small_gb, V.DEFAULT_BUDGET_GB])
	_check("two HEAVY never fit",
		heavy_gb * 2.0 > V.DEFAULT_BUDGET_GB)

	_report()


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("SWARM REQUEST OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
