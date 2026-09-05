extends SceneTree

## Does the seam hold, where the pieces individually already have teeth?
##
##   godot --headless --path . --script scripts/arena/metabolism_join_selftest.gd
##
## Pre-registered in docs/EXPERIMENT_METABOLISM.md at 858f1ab.
##
## OFFLINE, with a FAKE EXECUTOR. No LM Studio, no GPU, no generation. The
## executor here records which class it was asked to run and nothing else, which
## is the only thing the seam invariants are about.
##
## SABOTAGE INSTRUCTIONS. In metabolism_join.gd:
##
##   obedience   set `runs = asked` instead of the granted class
##   ordering    move the resolve() call below the arbitrate() call and let the
##               verdict pick the speaker
##   denial      let a DENIED verdict still return a granted class to execute
##
## Each must turn its own check red. Verified by hand before committing.

const J := preload("res://scripts/arena/metabolism_join.gd")
const A := preload("res://scripts/arena/compute_arbiter.gd")
const B := preload("res://scripts/arena/swarm_bid.gd")
const Q := preload("res://scripts/arena/swarm_request.gd")
const V := preload("res://scripts/arena/vram.gd")

var _checks := 0
var _failures: Array[String] = []

## The fake executor. Records what it was told to run; runs nothing.
var _executed: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("   ok   %s" % name)
	else:
		_failures.append(name)
		print("   FAIL %s  %s" % [name, detail])


func _entry(id: String, bid: float, cls: String) -> Dictionary:
	return {"agent_id": id, "eligible": true, "bid": bid, "requested_class": cls}


## Executes exactly what the join says to execute, which is the whole point.
func _execute(decision: Dictionary) -> String:
	if not J.executes(decision):
		return ""
	var cls := str(decision["execute_class"])
	_executed.append(cls)
	return cls


func _run() -> void:
	print("=== metabolism join selftest (fake executor) ===\n")

	# ------------------------------------------------------ the matrix
	print(" the fake-executor matrix")
	var cases := [
		["SMALL",  [],                       A.GRANTED,    "SMALL"],
		["NORMAL", [],                       A.GRANTED,    "NORMAL"],
		["HEAVY",  [],                       A.GRANTED,    "HEAVY"],
		["HEAVY",  [A.NORMAL],               A.DOWNGRADED, "NORMAL"],
		["NORMAL", [A.HEAVY, A.SMALL],       A.DOWNGRADED, "SMALL"],
	]
	for c in cases:
		var req := str(c[0])
		var resident: Array = c[1]
		var want_outcome := str(c[2])
		var want_exec := str(c[3])
		var d := J.allocate([_entry("A", 0.9, req)], resident)
		var ran := _execute(d)
		_check("%-6s with %-18s -> %-11s exec %s"
				% [req, str(resident), want_outcome, want_exec],
			str(d["outcome"]) == want_outcome and ran == want_exec,
			"got outcome %s exec %s" % [str(d["outcome"]), ran])

	# An over-ceiling class, with room to spare. 8B is 5.15 GB against 6.00.
	var over_params := {A.SMALL: 1.5, A.NORMAL: 4.0, A.HEAVY: 8.0}
	var denied := J.allocate([_entry("A", 0.9, A.HEAVY)], [], A.LADDER, over_params)
	var ran_denied := _execute(denied)
	_check("8B with plenty of room -> DENIED, executes nothing",
		str(denied["outcome"]) == A.DENIED
			and str(denied["arbiter_code"]) == A.OVER_PARAM_CEILING
			and ran_denied == "", str(denied))

	# An invalid class never reaches the resolver: it is MALFORMED_BID there.
	var invalid := J.allocate([_entry("A", 0.9, "ENORMOUS")], [])
	var ran_invalid := _execute(invalid)
	_check("an invalid class is refused and executes nothing",
		not bool(invalid["ok"]) and ran_invalid == "", str(invalid))

	# WHERE THE DENIAL INVARIANT ACTUALLY LIVES. Sabotaging the join's
	# `outcome != DENIED` guard changes nothing, because _deny() already returns
	# an empty granted_class -- so the join's guard is belt-and-braces and the
	# load-bearing fact is in the arbiter. Tested there, or a clean pass above
	# would be passing for a reason nobody checked.
	#
	# SABOTAGE: make compute_arbiter._deny() return a granted_class. This must
	# go red, and the join must then execute on a denied turn.
	var denials := [
		A.arbitrate("ENORMOUS", []),
		A.arbitrate(A.HEAVY, [], A.LADDER, over_params),
		A.arbitrate(A.HEAVY, [], []),
		A.arbitrate(A.NORMAL, [A.HEAVY, A.NORMAL]),
	]
	var carried := 0
	for d in denials:
		if str(d["outcome"]) == A.DENIED and str(d["granted_class"]) != "":
			carried += 1
	_check("no DENIED verdict ever carries a class to run", carried == 0,
		"%d denial(s) named a class the executor could have used" % carried)

	# ------------------------------------------- 1. obedience to granted_class
	print("\n 1. execution obeys granted_class, never requested_class")
	var squeezed := J.allocate([_entry("A", 0.9, A.HEAVY)], [A.NORMAL])
	_check("HEAVY asked, NORMAL granted",
		str(squeezed["requested_class"]) == A.HEAVY
			and str(squeezed["granted_class"]) == A.NORMAL, str(squeezed))
	_check("and execute_class follows the GRANT, not the request",
		str(squeezed["execute_class"]) == str(squeezed["granted_class"])
			and str(squeezed["execute_class"]) != str(squeezed["requested_class"]),
		str(squeezed))

	var obeys := true
	for req in A.LADDER:
		for resident in [[], [A.SMALL], [A.NORMAL], [A.HEAVY], [A.HEAVY, A.SMALL]]:
			var d := J.allocate([_entry("A", 0.9, str(req))], resident)
			if J.executes(d) and str(d["execute_class"]) != str(d["granted_class"]):
				obeys = false
	_check("across 15 request/resource combinations, execution never diverges",
		obeys, "at least one turn ran a class the arbiter did not grant")

	# ------------------------------------------ 2. resources cannot re-pick
	print("\n 2. the resource outcome cannot alter the speaker")
	# Same bids, same classes, wildly different resource states. The winner is
	# decided before any of it is read and must not move.
	var entries := [_entry("A", 0.80, A.HEAVY), _entry("B", 0.40, A.HEAVY)]
	var speakers := {}
	var outcomes := {}
	for resident in [[], [A.SMALL], [A.NORMAL], [A.HEAVY], [A.HEAVY, A.SMALL]]:
		var d := J.allocate(entries, resident)
		speakers[str(resident)] = str(d["speaker"])
		outcomes[str(resident)] = str(d["outcome"])
	var one_speaker := true
	for k in speakers:
		if str(speakers[k]) != "A":
			one_speaker = false
	_check("the same bids elect the same speaker under every resource state",
		one_speaker, str(speakers))
	_check("while the resource outcome genuinely varied",
		outcomes.values().has(A.GRANTED) and outcomes.values().has(A.DOWNGRADED),
		"if every state gave the same outcome the check above proves nothing: %s"
			% str(outcomes))

	# A denial must not hand the slot to somebody else either.
	var denied_speaker := J.allocate(entries, [], A.LADDER, over_params)
	_check("even a DENIED turn keeps the elected speaker",
		str(denied_speaker["speaker"]) == "A"
			and str(denied_speaker["outcome"]) == A.DENIED,
		str(denied_speaker))

	# --------------------------------------- 3. no resource feedback in A
	print("\n 3. no resource state leaks back into the local view")
	# The local view is exactly the three fields the bid requires. If a grant
	# outcome could enter it, METABOLISM-A would also be a learning-from-
	# resource-feedback experiment and neither mechanism would be attributable.
	var view := B.local_view(3, false, 0.2)
	_check("a local view has exactly the three required keys",
		view.size() == B.REQUIRED.size(), str(view.keys()))
	var leaked := false
	for k in view.keys():
		if not B.REQUIRED.has(str(k)):
			leaked = true
	_check("and no fourth field of any kind", not leaked, str(view.keys()))

	# The decision dictionary is for the audit layer. Nothing in it is a key
	# the bid or the request policy would read.
	var audit := J.allocate([_entry("A", 0.9, A.HEAVY)], [A.NORMAL])
	var feedback := false
	for k in audit.keys():
		if B.REQUIRED.has(str(k)):
			feedback = true
	_check("no audit field shares a name with a local-view field", not feedback,
		str(audit.keys()))
	_check("the request policy still reads only the bid",
		Q.request(view) == Q.tier(B.compute(view)),
		"the class must be a pure function of the bid scalar")

	# --------------------------------------------------- the fake executor
	print("\n the fake executor ran only what it was granted")
	var illegal_runs := 0
	for e in _executed:
		if not A.LADDER.has(str(e)):
			illegal_runs += 1
	_check("every recorded execution names a real class", illegal_runs == 0,
		str(_executed))
	# Five matrix cases execute; the over-ceiling case and the invalid-class case
	# ran the fake executor too and must have contributed nothing. Asserted as a
	# delta rather than a magic total, so adding a matrix row does not silently
	# turn this check into a lie.
	_check("the two denial cases contributed no executions",
		_executed.size() == cases.size(),
		"%d executions from %d executing cases: %s"
			% [_executed.size(), cases.size(), str(_executed)])

	_report()


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("METABOLISM JOIN OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
