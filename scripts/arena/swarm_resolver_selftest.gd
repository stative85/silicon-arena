extends SceneTree

## Can the substrate learn why an agent wants the slot?
##
##   godot --headless --path . --script scripts/arena/swarm_resolver_selftest.gd
##
## Pre-registered in docs/EXPERIMENT_SWARM.md at 85d34f2.
##
## This is the experiment, not a check on it. SWARM-V asks whether locally
## informed agents can allocate a scarce slot without the arena understanding
## their reasons, and that question is meaningless if a semantic field can slip
## into the resolver's input during some later refactor. So the boundary is
## tested the way a guard is tested: every forbidden field is offered to the
## resolver, one at a time, and every one must be refused.
##
## The other half of the boundary is tools/lint_locality.py, which fails if this
## resolver can even reach a module carrying history, memory or turn text.
##
## Deterministic: pure functions over synthetic bids, no LM Studio.

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


func _bid(id: String, eligible: bool, bid: float) -> Dictionary:
	return {"agent_id": id, "eligible": eligible, "bid": bid}


## Never index a resolve() result directly.
##
## A first version wrote `R.resolve(x)["agent_id"]`. Breach-testing the boundary
## made resolve() return a failure dictionary, the missing key raised a script
## error, `_run()` aborted before `_report()` could call quit(), and headless
## Godot hung forever instead of reporting red. A test that hangs when the code
## breaks is worse in CI than one that fails.
func _won(out: Dictionary) -> String:
	return str(out.get("agent_id", "<none>"))


func _code(out: Dictionary) -> String:
	return str(out.get("code", "<no code>"))


func _run() -> void:
	print("=== swarm resolver selftest ===\n")

	# ---- the locality boundary --------------------------------------------
	#
	# Every one of these is a real field somewhere in this codebase, and every
	# one is a plausible thing for a future tiebreak to reach for.
	print(" the boundary: semantic fields are REFUSED, not ignored")
	const FORBIDDEN := ["text", "speaker", "turn", "history", "scar", "trace",
		"direct_address", "addressed", "topic", "relationship", "memory",
		"reason", "target", "intensity", "shape", "excerpt"]
	var refused_all := true
	var leaked := ""
	for field in FORBIDDEN:
		var poisoned := _bid("A", true, 0.9)
		poisoned[field] = "anything at all"
		var out: Dictionary = R.resolve([poisoned])
		if bool(out.get("ok", false)) or str(out.get("code", "")) != R.MALFORMED_BID:
			refused_all = false
			leaked = field
	_check("all %d semantic fields are refused" % FORBIDDEN.size(), refused_all,
		"'%s' passed through; the substrate could be told why" % leaked)

	_check("a missing required key is refused",
		not bool(R.resolve([{"agent_id": "A", "bid": 0.5}]).get("ok", false)),
		"a partial payload must not be quietly completed")

	# ---- resource failures, which describe state and never motive ---------
	print("\n resource failure codes")
	_check("no bids at all", _code(R.resolve([])) == R.NO_BIDS)
	_check("bids arrived but none eligible",
		_code(R.resolve([_bid("A", false, 0.9), _bid("B", false, 0.1)]))
			== R.NO_ELIGIBLE_BIDS)
	_check("a bid above 1.0 is malformed",
		_code(R.resolve([_bid("A", true, 1.5)])) == R.MALFORMED_BID)
	_check("a negative bid is malformed",
		_code(R.resolve([_bid("A", true, -0.1)])) == R.MALFORMED_BID)
	_check("NAN is malformed",
		_code(R.resolve([_bid("A", true, NAN)])) == R.MALFORMED_BID,
		"an unchecked NAN wins every comparison it is in")
	_check("INF is malformed",
		_code(R.resolve([_bid("A", true, INF)])) == R.MALFORMED_BID)
	_check("an empty agent_id is malformed",
		_code(R.resolve([_bid("", true, 0.5)])) == R.MALFORMED_BID)
	_check("a non-dictionary entry is malformed",
		_code(R.resolve(["A"])) == R.MALFORMED_BID)

	# ---- arbitration -------------------------------------------------------
	print("\n arbitration")
	var three := [_bid("A", true, 0.31), _bid("B", true, 0.82), _bid("C", true, 0.44)]
	_check("the highest eligible bid wins",
		_won(R.resolve(three)) == "B")
	_check("an ineligible agent cannot win with the highest bid",
		_won(R.resolve([_bid("A", false, 0.99), _bid("B", true, 0.10)])) == "B",
		"eligibility is a resource fact and it outranks wanting the slot")
	_check("an agent that does not bid is simply routed around",
		_won(R.resolve([_bid("B", true, 0.18), _bid("D", true, 0.44)])) == "D",
		"silence is a legitimate local decision, not an error")

	# Order is upstream state. If it can change the winner, the resolver has
	# inherited information it was never handed.
	var shuffled := [_bid("C", true, 0.44), _bid("B", true, 0.82), _bid("A", true, 0.31)]
	_check("array order cannot change the winner",
		_won(R.resolve(shuffled)) == _won(R.resolve(three)))
	_check("ties break on agent_id, not on position",
		_won(R.resolve([_bid("Z", true, 0.5), _bid("A", true, 0.5)])) == "A")

	# ---- no fairness assistance -------------------------------------------
	#
	# The first swarm condition runs with anti-monopoly machinery OFF, because
	# those guards enforce exactly the property the swarm is supposed to
	# demonstrate. If the referee supplies fairness the measurement says
	# nothing.
	print("\n no fairness assistance in v0.1")
	var monopolist := [_bid("A", true, 0.99), _bid("B", true, 0.01)]
	var won_every_time := true
	for _i in 20:
		if _won(R.resolve(monopolist)) != "A":
			won_every_time = false
	_check("one agent can win twenty times in a row, unimpeded", won_every_time,
		"whatever concentration raw local bidding produces IS the finding")

	_report()


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("SWARM RESOLVER OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
