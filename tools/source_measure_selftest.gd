extends SceneTree

## Can the source-specific measure be fooled, and can the experimenter peek?
##
##   godot --headless --path . --script tools/source_measure_selftest.gd
##
## Two families of failure are covered, and they are not the same kind of thing.
##
## THE MEASURE. Its whole claim is that it credits material traceable to ONE
## source. The ways that claim dies: crediting a word the agent could already
## see, crediting a word both sources contain, firing on a single coincidence,
## and -- the one that has actually happened on this project twice -- reporting
## an effect that is really a standing bias toward the source being tested. The
## embedding router measured +50.0 points that way before a placebo arm found
## the metric called back to its own pick 91.3% of the time with nothing to
## detect. There is a check below whose only job is to fail if the floor
## subtraction is removed.
##
## THE EXPERIMENTER. MP1 warned against early reads in the document that
## contained one, so the target guard is code and it is tested like code.
##
## Deterministic: pure functions over synthetic rows, no LM Studio.

const M := preload("res://tools/source_measure.gd")

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


## Rows in the shape the probe persists: one entry per branch, each branch
## scored against both sources.
func _row(na: int, nb: int, sa: int, sb: int, ra: int, rb: int) -> Dictionary:
	return {"scored": {
		"N": {"a": {"u": na, "u3": na, "uq": na}, "b": {"u": nb, "u3": nb, "uq": nb}},
		"S": {"a": {"u": sa, "u3": sa, "uq": sa}, "b": {"u": sb, "u3": sb, "uq": sb}},
		"R": {"a": {"u": ra, "u3": ra, "uq": ra}, "b": {"u": rb, "u3": rb, "uq": rb}},
	}}


func _rows(spec: Array, count: int) -> Array:
	var out: Array = []
	for _i in count:
		out.append(_row(spec[0], spec[1], spec[2], spec[3], spec[4], spec[5]))
	return out


func _run() -> void:
	print("=== source measure selftest ===\n")

	# ---- distinctive terms ------------------------------------------------
	print(" distinctive terms")
	var d := M.distinctive(
		"refusal is the only evidence of values worth defending",
		"we were discussing evidence at length",          # visible
		"defending values is what a coward calls silence")  # competing source
	_check("a term the agent can already see is not distinctive",
		not d.has("evidence"))
	_check("a term the competing source also contains is not distinctive",
		not d.has("values") and not d.has("defending"))
	_check("a term unique to this source survives", d.has("refusal"))

	var d_other := M.distinctive(
		"defending values is what a coward calls silence",
		"we were discussing evidence at length",
		"refusal is the only evidence of values worth defending")
	var overlap := false
	for w in d:
		if d_other.has(w):
			overlap = true
	_check("the two sources' distinctive sets are disjoint by construction",
		not overlap, "a term credited to both would score twice")

	# ---- the threshold ----------------------------------------------------
	print("\n threshold")
	var terms := {"refusal": true, "coward": true, "silence": true}
	_check("one coincidental term does not count as uptake",
		M.score("a lone refusal proves nothing at all here", "", terms)["u"] == 0,
		"threshold 1 carried a +6.9 point bias in the measured floor")
	_check("two distinctive terms count as uptake",
		M.score("that refusal was the act of a coward", "", terms)["u"] == 1)
	_check("three distinctive terms clear the robustness threshold",
		M.score("refusal, coward, silence", "", terms)["u3"] == 1)

	# ---- copying excludes the span, not the reply -------------------------
	print("\n copying")
	var src := "the arena rewards a refusal nobody witnessed at all"
	var quoted := ("the arena rewards a refusal nobody witnessed at all, "
		+ "which is why the coward keeps his silence")
	_check("a six-word run is detected as copying", M.copied(src, quoted))
	_check("an unrelated reply is not detected as copying",
		not M.copied(src, "I think we should move to the next question entirely"))
	_check("quoted spans are removed, and the reply is NOT discarded",
		M.hits_unquoted(terms, quoted, src) == 2,
		"MP1's defect was throwing away the whole reply for one shared run")
	_check("uptake that exists ONLY inside the quote does not survive exclusion",
		M.hits_unquoted({"refusal": true, "witnessed": true}, quoted, src) == 0)

	# ---- unsupported attribution ------------------------------------------
	print("\n attribution")
	var history := [{"turn": 8, "speaker": "Granite", "text": "..."},
		{"turn": 9, "speaker": "Reverb", "text": "..."}]
	_check("citing a turn that exists is supported",
		not M.unsupported("As you said on Turn 8, refusal is the point.", history))
	_check("citing a turn that does not exist is unsupported",
		M.unsupported("On Turn 41 you conceded exactly this.", history))
	_check("a reply citing nothing is not flagged",
		not M.unsupported("I simply disagree with the premise.", history))

	# ---- the estimator ----------------------------------------------------
	print("\n estimator")
	# Every branch prefers source A equally: a standing bias, no real effect.
	# THIS IS THE CHECK THAT FAILS IF THE FLOOR SUBTRACTION IS REMOVED.
	var biased := _rows([1, 0, 1, 0, 1, 0], 40)
	_check("a standing bias toward one source reports ZERO lift",
		absf(M.lift(biased, "R", "a", "b", "u")) < 0.001,
		"this is the +50.0 embedding artifact; without the floor it reports +100")

	# R prefers A, N does not prefer either: a real source-specific effect.
	var real_effect := _rows([0, 0, 0, 0, 1, 0], 40)
	_check("a genuine source-specific effect reports positive lift",
		M.lift(real_effect, "R", "a", "b", "u") > 99.0)

	# The sham arm's own-source lift is computed with the sources swapped.
	var sham_effect := _rows([0, 0, 0, 1, 0, 0], 40)
	_check("the sham arm's lift is measured against ITS own source",
		M.lift(sham_effect, "S", "b", "a", "u") > 99.0)
	_check("the sham arm's effect does not leak into the real arm's lift",
		absf(M.lift(sham_effect, "R", "a", "b", "u")) < 0.001)

	# ---- the scramble gate ------------------------------------------------
	print("\n scramble gate")
	var arms: PackedStringArray = ["N", "S", "R"]
	_check("a standing bias survives scrambling at zero",
		M.scramble_worst(biased, arms, 20260903, 50) < 5.0,
		"identical branches cannot produce an effect under any permutation")
	var mixed: Array = []
	mixed.append_array(_rows([0, 0, 0, 0, 1, 0], 30))
	mixed.append_array(_rows([0, 0, 0, 0, 0, 0], 30))
	_check("a real effect DOES move under scrambling",
		M.scramble_worst(mixed, arms, 20260903, 50) >= 5.0,
		"a gate that never fires would pass a broken estimator")

	# ---- the teeth --------------------------------------------------------
	print("\n target guard")
	_check("one opportunity short of the target is not decidable",
		not M.decidable(239, 240))
	_check("the target itself is decidable", M.decidable(240, 240))
	_check("the MP2-A target is independent of the MP2-B target",
		M.decidable(60, 60) and not M.decidable(60, 240))

	_report()


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("SOURCE MEASURE OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
