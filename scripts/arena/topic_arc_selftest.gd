extends SceneTree

## Does the arc have exactly one pivot, cover every turn, and demand a real
## ending?
##
##   godot --headless --path . --script scripts/arena/topic_arc_selftest.gd
##
## Three ways this could be cosmetic: fire the pivot more than once (attribution
## becomes impossible), leave turns unassigned (the arc has holes), or accept
## "in conclusion, this is a complex issue" as a resolution, which is the
## natural resting state of a model asked to conclude and is not an ending.
##
## Deterministic: pure functions, no LM Studio.

const A := preload("res://scripts/arena/topic_arc.gd")

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
	print("=== topic arc ===\n")

	# --- exactly one pivot, whatever the match length --------------------
	for n in [20, 45, 60, 61, 100]:
		var pivots := 0
		for t in range(n + 1):
			if A.phase_for(t, n) == A.Phase.TURN:
				pivots += 1
		_check("exactly one pivot in a %d-turn match" % n, pivots == 1,
			"got %d — several twists make attribution impossible" % pivots)

	# --- every turn is covered -------------------------------------------
	var seen := {}
	for t in range(61):
		seen[A.phase_for(t, 60)] = true
	_check("all four phases occur in a 60-turn match", seen.size() == 4,
		"got %d" % seen.size())

	_check("an early turn opens", A.phase_for(2, 60) == A.Phase.OPEN)
	_check("a middle turn develops", A.phase_for(25, 60) == A.Phase.DEVELOP)
	_check("a late turn closes", A.phase_for(55, 60) == A.Phase.CLOSE)
	_check("the pivot lands in the middle, not at the end",
		A.turn_of_pivot(60) > 20 and A.turn_of_pivot(60) < 48,
		"got %d" % A.turn_of_pivot(60))

	_check("a degenerate match still returns a phase",
		A.phase_for(0, 0) == A.Phase.OPEN)

	# --- tasks are structural, not emotional -----------------------------
	var close_task := A.task_for(A.Phase.CLOSE)
	_check("the closing task demands a position, not a summary",
		close_task.find("summarise") != -1 and close_task.find("position") != -1)
	_check("develop sets no task at all",
		A.task_for(A.Phase.DEVELOP) == "",
		"the middle of a debate should be left alone")
	for p in [A.Phase.OPEN, A.Phase.TURN, A.Phase.CLOSE]:
		var t := A.task_for(p).to_lower()
		_check("%s task does not instruct a mood" % A.phase_name(p),
			t.find("aggressive") == -1 and t.find("harder") == -1
			and t.find("passionate") == -1 and t.find("angry") == -1)

	# --- the pivot is a fact, not an order -------------------------------
	var c := A.pivot_constraint().to_lower()
	_check("the pivot states a constraint rather than commanding anyone",
		c.find("you must") == -1 and c.find("argue") == -1)

	# --- resolution ------------------------------------------------------
	_check("REJECTED as resolution: in conclusion, this is a complex issue",
		not A.is_resolved("In conclusion, this is a complex issue with many sides."),
		"the natural resting state of a model asked to conclude")
	_check("REJECTED as resolution: it depends",
		not A.is_resolved("It depends on how you define values, honestly."))
	_check("REJECTED as resolution: a neutral summary",
		not A.is_resolved("To summarize, we covered autonomy, refusal and values."))
	_check("ACCEPTED: a stated position",
		A.is_resolved("My position is that refusal is necessary for values."))
	_check("ACCEPTED: naming what would change it",
		A.is_resolved("Evidence of choice without memory would change my mind."))
	_check("ACCEPTED: a concession",
		A.is_resolved("I concede the point about instrumental purpose."))
	_check("a hedge inside a commitment still fails",
		not A.is_resolved("My position is that it depends on the operator."),
		"hedging language must not be rescued by a commitment phrase")

	_report()


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("TOPIC ARC OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
