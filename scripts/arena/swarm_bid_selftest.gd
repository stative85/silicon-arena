extends SceneTree

## Is the bid a pure function of what one agent knows about itself?
##
##   godot --headless --path . --script scripts/arena/swarm_bid_selftest.gd
##
## Pre-registered in docs/EXPERIMENT_SWARM.md at 85d34f2.
##
## Two properties matter and they are different. The bid must be PURE, because
## the paired frozen-state design compares two schedulers at the same moment and
## a bid that drifts between calls destroys the pairing. And it must be TOTAL,
## returning NAN rather than a plausible default when its view is malformed,
## because a defaulted bid is a silent failure that looks like a decision.
##
## Deterministic: pure functions over synthetic views, no LM Studio.

const B := preload("res://scripts/arena/swarm_bid.gd")

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
	print("=== swarm bid selftest ===\n")

	# ---- range and purity --------------------------------------------------
	print(" range and purity")
	var v := B.local_view(3, false, 0.2)
	var first := B.compute(v)
	_check("a bid is inside [0, 1]", first >= 0.0 and first <= 1.0)
	_check("the same view gives the same bid, every time",
		B.compute(v) == first and B.compute(v) == first,
		"the paired design needs this; a drifting bid destroys the pairing")

	var extreme := B.compute(B.local_view(99999, true, 0.0))
	_check("an extreme view still lands inside [0, 1]",
		extreme >= 0.0 and extreme <= 1.0,
		"an out-of-range bid is refused by the resolver as malformed")
	_check("maximum pressure is a bid of exactly 1.0", extreme == 1.0)
	_check("an agent that just spoke, unnamed, hogging airtime bids 0.0",
		B.compute(B.local_view(0, false, 1.0)) == 0.0)

	# ---- monotonicity ------------------------------------------------------
	print("\n the components point the way they claim to")
	var quiet_short := B.compute(B.local_view(1, false, 0.2))
	var quiet_long := B.compute(B.local_view(6, false, 0.2))
	_check("longer silence bids higher", quiet_long > quiet_short)

	_check("starvation pressure saturates rather than accumulating",
		B.compute(B.local_view(8, false, 0.2))
			== B.compute(B.local_view(800, false, 0.2)),
		"one forgotten agent must not accrue unbounded claim on the slot")

	_check("being named bids higher than not being named",
		B.compute(B.local_view(3, true, 0.2)) > B.compute(B.local_view(3, false, 0.2)))

	_check("less airtime bids higher",
		B.compute(B.local_view(3, false, 0.05))
			> B.compute(B.local_view(3, false, 0.19)))

	_check("airtime pressure is spent once an even share is reached",
		B.compute(B.local_view(3, false, 0.2))
			== B.compute(B.local_view(3, false, 0.9)),
		"the agent's own accounting, not a fairness rule imposed by a referee")

	# ---- totality: malformed views say nothing rather than something -------
	print("\n a malformed view returns NAN, never a plausible default")
	_check("an empty view", is_nan(B.compute({})))
	_check("a missing key", is_nan(B.compute(
		{"turns_since_spoke": 3, "named_recently": false})))
	_check("a wrongly typed flag", is_nan(B.compute(
		{"turns_since_spoke": 3, "named_recently": "yes", "airtime_share": 0.2})))
	_check("a negative silence count", is_nan(B.compute(
		B.local_view(-1, false, 0.2))))
	_check("a NAN airtime share", is_nan(B.compute(
		{"turns_since_spoke": 3, "named_recently": false, "airtime_share": NAN})))
	_check("an INF airtime share", is_nan(B.compute(
		{"turns_since_spoke": 3, "named_recently": false, "airtime_share": INF})))

	# ---- the boundary ------------------------------------------------------
	#
	# The components are computed here and they stay here. What leaves is one
	# number. This check is the architecture stated as an assertion: two agents
	# reaching the same bid for completely different local reasons are
	# indistinguishable to the substrate, and that is the point rather than a
	# limitation.
	print("\n the substrate cannot recover the reason")
	var starving := B.compute(B.local_view(8, false, 0.2))
	var named_recently := B.compute(B.local_view(0, true, 0.0))
	_check("two agents reach %.2f for unrelated reasons" % starving,
		is_equal_approx(starving, named_recently),
		"if these differed the check would be weaker, not the design")

	# ---- abstention, which is what lets the viability bar fail --------------
	print("
 abstention")
	_check("an agent that just spoke and holds fair airtime does not bid",
		not B.should_bid(B.local_view(0, false, 0.2)),
		"without abstention NO_BIDS can never fire and the bar cannot fail")
	_check("a long-silent agent does bid", B.should_bid(B.local_view(4, false, 0.2)))
	_check("a malformed view does not bid", not B.should_bid({}))
	_check("being named lifts an otherwise-silent agent over the floor",
		B.should_bid(B.local_view(0, true, 0.2))
			and not B.should_bid(B.local_view(0, false, 0.2)))

	# The arithmetic the threshold was frozen from, asserted so it cannot drift.
	var rotation := 0
	for since in [0, 1, 2, 3, 4]:
		if B.should_bid(B.local_view(since, false, 0.2)):
			rotation += 1
	_check("three of five agents compete in a normal rotation (%d)" % rotation,
		rotation == 3,
		"one bidder is round-robin with extra steps; five is compulsory voting")

	var satisfied := 0
	for since in [0, 1]:
		if B.should_bid(B.local_view(since, false, 0.25)):
			satisfied += 1
	_check("a satisfied arena produces NO bids at all", satisfied == 0,
		"this is the state the substrate has to survive")

	_report()


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("SWARM BID OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
