extends SceneTree

## Every way a dispute episode must refuse to start.
##
##   godot --headless --path . --script scripts/arena/dispute_selftest.gd
##
## A dispute puts one agent's words in front of another and forces three turns
## around them. Each invariant below, violated, produces a different lie: a
## quote nobody said, an agent arguing with itself, a dead agent answering, an
## episode that never ends, or an event fired with no room left to observe it.
##
## Deterministic: pure functions over synthetic state, no LM Studio.

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
	print("=== dispute episode: eligibility ===\n")

	var history := [{"speaker": "Granite", "turn": 3,
		"text": "A system that cannot refuse has no values at all. It merely has settings."}]
	var claim: String = LM.extract_claim(str(history[0]["text"]))
	var active := ["Granite", "Reverb", "Deckard"]

	var good := {"claim": claim, "turn": 3, "target": "Granite",
		"challenger": "Reverb", "max_exchanges": 3}

	_check("a well-formed dispute is eligible",
		LM.dispute_eligible(good, history, active, 10, 60, {}))

	# --- provenance -------------------------------------------------------
	var wrong_turn := good.duplicate()
	wrong_turn["turn"] = 99
	_check("REFUSED: the claim's turn is not in the transcript",
		not LM.dispute_eligible(wrong_turn, history, active, 10, 60, {}))

	var wrong_speaker := good.duplicate()
	wrong_speaker["target"] = "Reverb"
	_check("REFUSED: the claim attributed to an agent who did not say it",
		not LM.dispute_eligible(wrong_speaker, history, active, 10, 60, {}))

	# --- the pair ---------------------------------------------------------
	var self_fight := good.duplicate()
	self_fight["challenger"] = "Granite"
	_check("REFUSED: an agent challenging itself",
		not LM.dispute_eligible(self_fight, history, active, 10, 60, {}))

	_check("REFUSED: the target is no longer active",
		not LM.dispute_eligible(good, history, ["Reverb", "Deckard"], 10, 60, {}))

	_check("REFUSED: the challenger is no longer active",
		not LM.dispute_eligible(good, history, ["Granite", "Deckard"], 10, 60, {}))

	# --- boundedness ------------------------------------------------------
	var endless := good.duplicate()
	endless["max_exchanges"] = 0
	_check("REFUSED: an episode with no exchange limit",
		not LM.dispute_eligible(endless, history, active, 10, 60, {}))

	# --- one at a time ----------------------------------------------------
	_check("REFUSED: a second dispute while one is already running",
		not LM.dispute_eligible(good, history, active, 10, 60,
			{"status": "active", "challenger": "Deckard", "target": "Reverb"}))

	# --- observation horizon ---------------------------------------------
	# This is the one that fired for real: an event at turn 60 of a 60-turn
	# match has nowhere to be measured, so it must never be injected.
	_check("REFUSED: no turns left to observe the effect",
		not LM.dispute_eligible(good, history, active, 60, 60, {}),
		"an event at the final turn is unmeasurable, not merely cheap")

	_check("REFUSED: too close to the end for the follow-up window",
		not LM.dispute_eligible(good, history, active, 55, 60, {}))

	_check("allowed with exactly enough room",
		LM.has_followup_room(52, 60, 3, 5))

	_check("REFUSED one turn later",
		not LM.has_followup_room(53, 60, 3, 5))

	_check("REFUSED: an empty dispute",
		not LM.dispute_eligible({}, history, active, 10, 60, {}))

	_report()


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("DISPUTE OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
