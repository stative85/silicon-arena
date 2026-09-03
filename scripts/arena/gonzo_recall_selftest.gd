extends SceneTree

## Can retrieval manufacture its own evidence?
##
##   godot --headless --path . --script scripts/arena/gonzo_recall_selftest.gd
##
## The pathology this file exists to prevent: a memory is recalled, becomes
## stronger for having been recalled, therefore gets recalled more, and one
## remark from turn 8 becomes the agent's religion. That loop closes silently
## and every individual step looks reasonable.
##
## The other failures are fabrication -- an excerpt attributed to a turn that
## does not contain it -- and domination, where one scar owns every prompt.
##
## Deterministic: pure functions over synthetic state, no LM Studio.

const G := preload("res://scripts/arena/gonzo_recall.gd")

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


func _scar() -> Dictionary:
	return {
		"excerpt": "refusal is the only evidence of values",
		"source_turn": 8, "source_speaker": "Granite", "other_speaker": "Reverb",
		"shape": "challenge", "intensity": 0.8,
		"last_reinforced_turn": 8, "last_recalled_turn": -999, "recall_count": 0,
	}


func _history() -> Array:
	return [{"turn": 8, "speaker": "Granite",
		"text": "I say refusal is the only evidence of values worth the name."}]


func _run() -> void:
	print("=== gonzo recall: layered retrieval ===\n")

	var scar := _scar()
	var hist := _history()

	# --- THE RULE THAT MATTERS MOST --------------------------------------
	# Recall must never strengthen a memory. Attacked directly, repeatedly.
	var s := scar.duplicate()
	var before := float(s["intensity"])
	for i in 10:
		s = G.on_recall(s, 20 + i)
	_check("ten recalls do not change intensity by one bit",
		is_equal_approx(float(s["intensity"]), before),
		"%.4f -> %.4f: retrieval created its own evidence" % [before, float(s["intensity"])])

	_check("recalls are still counted",
		int(s["recall_count"]) == 10)

	_check("repeated recall makes a scar LESS likely to surface, not more",
		G.novelty_penalty(10) < G.novelty_penalty(0),
		"a recalled memory must not become self-reinforcing")

	# --- reinforcement requires new evidence -----------------------------
	var t := G.reinforce(scar, false, 30)
	_check("reinforcement without new evidence changes nothing",
		is_equal_approx(float(t["intensity"]), before))

	var u := G.reinforce(scar, true, 30)
	_check("new canonical behaviour does strengthen it",
		float(u["intensity"]) > before)

	_check("reinforcement is capped at 1.0",
		float(G.reinforce({"intensity": 0.95}, true, 30)["intensity"]) <= 1.0)

	_check("recall does not reset the decay clock",
		int(G.on_recall(scar, 50).get("last_reinforced_turn", 8)) == 8,
		"remembering something must not keep it young")

	# --- provenance -------------------------------------------------------
	_check("a real excerpt resolves", G.provenance_holds(scar, hist))

	var wrong_turn := scar.duplicate()
	wrong_turn["source_turn"] = 99
	_check("REFUSED: an excerpt from a turn that does not exist",
		not G.provenance_holds(wrong_turn, hist))

	var wrong_speaker := scar.duplicate()
	wrong_speaker["source_speaker"] = "Reverb"
	_check("REFUSED: an excerpt attributed to the wrong speaker",
		not G.provenance_holds(wrong_speaker, hist))

	var invented := scar.duplicate()
	invented["excerpt"] = "values require the capacity to walk away"
	_check("REFUSED: a plausible paraphrase that was never said",
		not G.provenance_holds(invented, hist),
		"a paraphrase presented as a quote is fabrication")

	_check("REFUSED: an empty excerpt",
		not G.provenance_holds({"source_turn": 8, "source_speaker": "Granite",
			"excerpt": ""}, hist))

	# --- decay ------------------------------------------------------------
	_check("a fresh memory is undiscounted",
		G.decay_factor(8, 8) > 0.99)
	_check("an old memory is discounted",
		G.decay_factor(38, 8) < 0.3)
	_check("decay never reaches zero or goes negative",
		G.decay_factor(500, 8) >= 0.0)

	# The four resonance dimensions were deleted after the paired tournament
	# (docs/EXPERIMENT_TOURNAMENT.md): distance converted at 69.3% against
	# resonance's 65.4%, and the pre-registered rule required +8 to justify the
	# machinery. What is left is distance discounted by decay and novelty.
	_check("a more distant memory scores higher, all else equal",
		G.score({"source_turn": 5, "intensity": 0.8, "last_reinforced_turn": 5},
			"", "", [], 40)
		> G.score({"source_turn": 30, "intensity": 0.8, "last_reinforced_turn": 30},
			"", "", [], 40))

	_check("a weaker memory scores lower at the same distance",
		G.score({"source_turn": 10, "intensity": 0.2, "last_reinforced_turn": 10},
			"", "", [], 30)
		< G.score({"source_turn": 10, "intensity": 0.9, "last_reinforced_turn": 10},
			"", "", [], 30))

	_check("a repeatedly surfaced memory scores lower",
		G.score({"source_turn": 10, "intensity": 0.8, "last_reinforced_turn": 10,
			"recall_count": 6}, "", "", [], 30)
		< G.score({"source_turn": 10, "intensity": 0.8, "last_reinforced_turn": 10,
			"recall_count": 0}, "", "", [], 30))

	# --- cooldown and bounds ---------------------------------------------
	var just_recalled := scar.duplicate()
	just_recalled["last_recalled_turn"] = 20
	_check("REFUSED: a scar recalled two turns ago",
		not G.eligible(just_recalled, hist, 22,
			"Granite is wrong about refusal.", "Reverb", ["Granite"]),
		"one memory must not dominate consecutive turns")

	var too_recent := scar.duplicate()
	too_recent["source_turn"] = 18
	_check("REFUSED: a memory still inside the visible transcript",
		not G.eligible(too_recent, [{"turn": 18, "speaker": "Granite",
			"text": "I say refusal is the only evidence of values worth the name."}],
			22, "Granite is wrong about refusal.", "Reverb", ["Granite"]),
		"surfacing what is already on screen is duplication, not memory")

	_check("at most two recalls may enter a prompt",
		G.MAX_RECALLS_PER_PROMPT == 2)

	# --- rendering is sterile --------------------------------------------
	var text := G.render(scar).to_lower()
	_check("the rendered memory cites its turn and speaker",
		text.find("turn 8") != -1 and text.find("granite") != -1)
	_check("the rendered memory issues no instruction about how to feel",
		text.find("haunt") == -1 and text.find("still bothers") == -1
		and text.find("you must") == -1,
		"nine rejections say do not tell these models how to write")

	_report()


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("GONZO RECALL OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
