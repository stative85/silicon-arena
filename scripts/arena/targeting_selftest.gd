extends SceneTree

## Can the arena be made to put words in an agent's mouth?
##
##   godot --headless --path . --script scripts/arena/targeting_selftest.gd
##
## A targeted-engagement event quotes one agent back at another:
##
##   "Granite said in turn 12, "values require refusal" — Reverb, take that
##    exact claim apart."
##
## If the quoted claim is not in the transcript, the arena has fabricated
## evidence and attributed it to an agent. Every later "the agents argued about
## X" claim is then worthless, and a viewer cannot tell.
##
## Deterministic: pure functions over a synthetic history, no LM Studio.

const LM := preload("res://scripts/arena/live_match.gd")

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
	print("=== targeted engagement: claim provenance ===\n")

	var history := [
		{"speaker": "Granite", "turn": 3,
		 "text": "A system that cannot refuse has no values at all. It merely has settings."},
		{"speaker": "Reverb", "turn": 4,
		 "text": "That conflates capability with commitment in a way I cannot accept."},
	]
	var claim := LM.extract_claim(str(history[0]["text"]))

	_check("a claim is extracted from a real turn", claim != "", "got %s" % claim)
	_check("the claim is the first sentence, not the whole turn",
		claim.find("merely has settings") == -1, "got: %s" % claim)

	# --- the citation must hold ------------------------------------------
	_check("a true citation is accepted",
		LM.citation_holds(history, 3, "Granite", claim))

	# --- and every way of being wrong must be refused ---------------------
	_check("REFUSED: a turn number that is not in the transcript",
		not LM.citation_holds(history, 99, "Granite", claim),
		"the arena would cite a turn that never happened")

	_check("REFUSED: the claim attributed to the wrong agent",
		not LM.citation_holds(history, 3, "Reverb", claim),
		"the arena would put Granite's words in Reverb's mouth")

	_check("REFUSED: a plausible paraphrase that was never said",
		not LM.citation_holds(history, 3, "Granite",
			"A system without refusal cannot hold values."),
		"a paraphrase presented as a quote is fabricated evidence")

	_check("REFUSED: an empty claim",
		not LM.citation_holds(history, 3, "Granite", ""))

	_check("REFUSED: any citation against an empty transcript",
		not LM.citation_holds([], 3, "Granite", claim))

	# A turn too short to be a position must not become one.
	_check("a one-word turn yields no claim",
		LM.extract_claim("Agreed.") == "")

	_check("a turn below the word floor yields no claim",
		LM.extract_claim("I disagree with that.") == "",
		"too short to be worth challenging")

	_report()


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("TARGETING OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
