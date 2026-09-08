extends SceneTree

## Treatment-aware detector teeth. NO LM STUDIO CONTACT, NO INFERENCE.
##
##   godot --headless --path . --script tools/detector_audit_selftest.gd
##
## Every integrity detector was audited against one question:
##
##     Can the legitimate treatment itself cause the state this detector
##     labels as contamination?
##
## The PID tooth failed that question. These tests pin the two properties that
## keep the surviving detectors honest:
##
##   1. a treatment-caused state that IS the phenomenon under study gets its own
##      reason code, so a void can be attributed to the effect or the apparatus
##      rather than disappearing into one bucket
##   2. the treatment flex is NARROW -- it excuses exactly the scheduled
##      absence of exactly one model, and nothing else
##
## Findings are documented in docs/results/TREATMENT_AWARE_DETECTOR_AUDIT.md.

const G := preload("res://scripts/arena/recovery_gate.gd")

var _n := 0
var _f := 0


func _init() -> void:
	_run.call_deferred()


func _ck(label: String, cond: bool) -> void:
	_n += 1
	if cond:
		print("  ok   %s" % label)
	else:
		_f += 1
		print("  FAIL %s" % label)


func _run() -> void:
	print("=== treatment-aware detector teeth ===\n")

	print("[a treatment-caused stall is separable from a broken transport]")
	var g := G.new()
	g.begin(1, {"a": 1, "b": 1})
	g.note_transport("no completion for b", 500, G.NEIGHBOUR_TIMEOUT)
	_ck("neighbour timeout still VOIDS the window", g.is_void())
	_ck("neighbour timeout carries its OWN reason code",
		str(g.first_offence["reason"]) == G.NEIGHBOUR_TIMEOUT)
	_ck("neighbour timeout is not filed as generic transport",
		str(g.first_offence["reason"]) != G.TRANSPORT)

	var g2 := G.new()
	g2.begin(2, {"a": 1})
	g2.note_transport("socket died", 10)
	_ck("a real transport failure still defaults to TRANSPORT",
		str(g2.first_offence["reason"]) == G.TRANSPORT)

	print("\n[the treatment flex is narrow]")
	_ck("flex tolerates the scheduled absence of its own target",
		G.classify({"b": 1}, {"a": 1, "b": 1}, "a") == G.OK)
	_ck("flex NEVER excuses a duplicate of the flexed model",
		G.classify({"a": 2, "b": 1}, {"a": 1, "b": 1}, "a") == G.DUPLICATE)
	_ck("flex does not excuse a DIFFERENT model disappearing",
		G.classify({"a": 1}, {"a": 1, "b": 1}, "a") == G.DISAPPEARED)
	_ck("flex does not excuse a foreign model appearing",
		G.classify({"a": 1, "b": 1, "z": 1}, {"a": 1, "b": 1}, "a") == G.FOREIGN)
	_ck("with no flex, a scheduled absence would still be flagged",
		G.classify({"b": 1}, {"a": 1, "b": 1}, "") == G.DISAPPEARED)

	print("\n[the relaxation cannot be applied retroactively]")
	var g3 := G.new()
	g3.begin(3, {"a": 1, "b": 1})
	g3.flex_model = ""
	var before := G.classify({"b": 1}, g3.expected, g3.flex_model)
	g3.flex_model = "a"
	var during := G.classify({"b": 1}, g3.expected, g3.flex_model)
	_ck("same state reads differently only while the flex is declared",
		before == G.DISAPPEARED and during == G.OK)

	print("\n[SUMMARY]")
	print("  checks %d, failures %d" % [_n, _f])
	if _f > 0:
		print("\nDETECTOR AUDIT RED")
		quit(1)
		return
	print("\nDETECTOR AUDIT GREEN")
	quit(0)
