extends SceneTree

## Can presentation stall the arena, skip a turn, or quietly slow it down?
##
##   godot --headless --path . --script scripts/arena/presentation_selftest.gd
##
## The third failure is the dangerous one: every individual dwell looks
## reasonable while the average drifts upward and the whole arena gets slower,
## with nothing on screen to show for it. Throughput here was earned by
## measurement and presentation does not get to spend it.
##
## Deterministic: pure functions, no LM Studio.

const P := preload("res://scripts/arena/presentation.gd")

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


## Mean multiplier actually applied over a sequence of beats.
func _applied_mean(seq: Array) -> float:
	var total := 0.0
	for i in seq.size():
		total += P.normalized(P.multiplier(seq[i]), total, i)
	return total / float(maxi(seq.size(), 1))


func _run() -> void:
	print("=== presentation director ===\n")

	_check("a short reply is handed off quickly",
		P.classify("Agreed entirely.", 3, false, false, false) == P.Beat.QUICK)
	_check("a long reply is held for reading",
		P.classify("x", 90, false, false, false) == P.Beat.HOLD)
	_check("contradicting a named rival is a punch",
		P.classify("Granite is wrong.", 40, true, true, false) == P.Beat.PUNCH)
	_check("naming a rival without contradiction is a connection",
		P.classify("Granite raises a point worth taking seriously.", 40,
			true, false, false) == P.Beat.CONNECT)
	_check("an ordinary turn is ordinary",
		P.classify("The question is what values are for.", 40, false, false,
			false) == P.Beat.ORDINARY)
	_check("changing position outranks everything else",
		P.classify("I was wrong about that, and here is why.", 90, true, true,
			false) == P.Beat.REVERSAL)
	_check("a repeated point is demoted, not rewarded",
		P.classify("Granite is wrong.", 90, true, true, true) == P.Beat.QUICK)

	for beat in [P.Beat.ORDINARY, P.Beat.PUNCH, P.Beat.CONNECT, P.Beat.QUICK,
			P.Beat.HOLD, P.Beat.REVERSAL]:
		var m := P.multiplier(beat)
		_check("%s multiplier is within bounds" % P.beat_name(beat),
			m >= P.MIN_MULTIPLIER and m <= P.MAX_MULTIPLIER, "got %.2f" % m)

	_check("an unknown beat falls back to ordinary, never to zero",
		P.multiplier(999) == P.MULTIPLIER[P.Beat.ORDINARY])
	_check("no multiplier can make a turn vanish", P.MIN_MULTIPLIER > 0.0)

	# --- the quiet failure, tested against distributions that MOVE ---------
	# Two 200s runs of the same build produced very different beat mixes, so a
	# fixed set of weights cannot preserve the mean. These sequences are the
	# adversarial cases.
	var run1: Array = []
	for i in 9: run1.append(P.Beat.CONNECT)
	for i in 6: run1.append(P.Beat.HOLD)
	for i in 6: run1.append(P.Beat.ORDINARY)
	for i in 3: run1.append(P.Beat.QUICK)
	for i in 2: run1.append(P.Beat.PUNCH)

	var run2: Array = []
	for i in 2: run2.append(P.Beat.CONNECT)
	for i in 12: run2.append(P.Beat.HOLD)
	for i in 7: run2.append(P.Beat.ORDINARY)
	for i in 3: run2.append(P.Beat.QUICK)
	for i in 3: run2.append(P.Beat.REVERSAL)

	var all_hold: Array = []
	for i in 30: all_hold.append(P.Beat.HOLD)
	var all_quick: Array = []
	for i in 30: all_quick.append(P.Beat.QUICK)

	for pair in [["measured run 1", run1], ["measured run 2", run2],
			["every turn HOLD", all_hold], ["every turn QUICK", all_quick]]:
		var mean := _applied_mean(pair[1])
		_check("applied mean stays near 1.0 — %s" % pair[0],
			absf(mean - 1.0) <= 0.10, "mean %.3f" % mean)

	# Variety must survive the correction, or this is just a constant dwell.
	var seen := {}
	var total := 0.0
	for i in run1.size():
		var v := P.normalized(P.multiplier(run1[i]), total, i)
		total += v
		seen[snappedf(v, 0.01)] = true
	_check("rhythm is still uneven after normalisation",
		seen.size() >= 4, "only %d distinct dwells" % seen.size())

	_report()


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("PRESENTATION OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
