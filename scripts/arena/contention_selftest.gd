extends SceneTree

## Every bound a contention must respect.
##
##   godot --headless --path . --script scripts/arena/contention_selftest.gd
##
## A contention is memory of a disagreement that keeps shaping prompts. The
## upside is occasional callbacks; the failure is five agents re-litigating one
## sentence forever. Each bound below, removed, produces a different pathology:
## a quote nobody said, an agent feuding with itself, a feud with a departed
## agent, an unbounded pile of feuds, one agent in every feud at once, or a
## disagreement that never cools.
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
	print("=== contention memory: bounds ===\n")

	var history := [{"speaker": "Granite", "turn": 3,
		"text": "A system that cannot refuse has no values at all. It merely has settings."}]
	var claim: String = LM.extract_claim(str(history[0]["text"]))
	var active := ["Granite", "Reverb", "Deckard", "Opus"]
	var good := {"agent_a": "Reverb", "agent_b": "Granite", "claim": claim,
		"source_turn": 3}

	_check("a well-formed contention is admissible",
		LM.contention_admissible(good, history, active, [], 2, 1))

	# --- provenance -------------------------------------------------------
	var bad_turn := good.duplicate()
	bad_turn["source_turn"] = 99
	_check("REFUSED: a claim from a turn that does not exist",
		not LM.contention_admissible(bad_turn, history, active, [], 2, 1))

	var bad_speaker := good.duplicate()
	bad_speaker["agent_b"] = "Deckard"
	_check("REFUSED: the claim attributed to the wrong agent",
		not LM.contention_admissible(bad_speaker, history, active, [], 2, 1))

	# --- the pair ---------------------------------------------------------
	var selffeud := good.duplicate()
	selffeud["agent_a"] = "Granite"
	_check("REFUSED: an agent in contention with itself",
		not LM.contention_admissible(selffeud, history, active, [], 2, 1))

	_check("REFUSED: the other agent is gone",
		not LM.contention_admissible(good, history, ["Reverb", "Deckard"], [], 2, 1))

	# --- population bounds ------------------------------------------------
	var two_others := [
		{"agent_a": "Deckard", "agent_b": "Opus"},
		{"agent_a": "Opus", "agent_b": "Deckard"},
	]
	_check("REFUSED: more than the total cap",
		not LM.contention_admissible(good, history, active, two_others, 2, 1))

	var reverb_busy := [{"agent_a": "Reverb", "agent_b": "Deckard"}]
	_check("REFUSED: an agent already in a contention",
		not LM.contention_admissible(good, history, active, reverb_busy, 2, 1),
		"one agent must not be in every feud at once")

	_check("allowed alongside an unrelated pair",
		LM.contention_admissible(good, history, active,
			[{"agent_a": "Deckard", "agent_b": "Opus"}], 2, 1))

	# --- decay and expiry -------------------------------------------------
	_check("intensity decays with time",
		LM.decayed_intensity(1.0, 5, 0.08) < 1.0)

	_check("intensity never goes negative",
		LM.decayed_intensity(1.0, 100, 0.08) == 0.0)

	var fresh := {"created_turn": 10, "last_reinforced_turn": 10, "intensity": 1.0}
	_check("a fresh contention is not expired",
		not LM.contention_expired(fresh, 11, 12, 0.25, 0.08))

	_check("EXPIRES once the TTL is reached",
		LM.contention_expired(fresh, 22, 12, 0.25, 0.08),
		"a contention must not outlive its time limit")

	_check("EXPIRES once intensity decays below the floor",
		LM.contention_expired(fresh, 21, 100, 0.25, 0.08),
		"a cold disagreement must stop shaping prompts")

	var reinforced := {"created_turn": 10, "last_reinforced_turn": 19, "intensity": 1.0}
	_check("reinforcement postpones the cooling, not the TTL",
		not LM.contention_expired(reinforced, 20, 12, 0.25, 0.08)
		and LM.contention_expired(reinforced, 25, 12, 0.25, 0.08))

	_check("REFUSED: an empty contention",
		not LM.contention_admissible({}, history, active, [], 2, 1))

	_report()


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("CONTENTION OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
