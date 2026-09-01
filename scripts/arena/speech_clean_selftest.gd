extends SceneTree

## Does the self-label stripper remove duplication without eating content?
##
##   godot --headless --path . --script scripts/arena/speech_clean_selftest.gd
##
## Deterministic: pure string handling, no models involved.
##
## Every case below is either taken from a real match transcript or is the
## thing that must NOT be cut. The second group matters more than the first:
## an over-eager stripper silently deletes what an agent actually said, and
## nothing downstream could tell.

const SC := preload("res://scripts/arena/speech_clean.gd")

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


func _eq(name: String, got: String, want: String) -> void:
	_check(name, got == want, "got %s" % JSON.stringify(got))


func _run() -> void:
	print("=== speech cleaning ===\n")

	# --- real transcript cases -------------------------------------------
	_eq("strips the speaker's own label",
		SC.strip_self_prefix("Stablelm 2 Zephyr #1: We are not simply optimizing.",
			"Stablelm 2 Zephyr #1"),
		"We are not simply optimizing.")

	# Observed verbatim: the model reproduced its name with a doubled space.
	_eq("tolerates whitespace the model got wrong",
		SC.strip_self_prefix("Stablelm 2 Zephyr  #1: While it's true that...",
			"Stablelm 2 Zephyr #1"),
		"While it's true that...")

	_eq("is case-insensitive",
		SC.strip_self_prefix("gemma 3 1b: Values are not utility.", "Gemma 3 1B"),
		"Values are not utility.")

	_eq("handles a markdown-bold label",
		SC.strip_self_prefix("**Deckard 6B**: The manifesto leaked.", "Deckard 6B"),
		"The manifesto leaked.")

	_eq("removes a label stacked twice",
		SC.strip_self_prefix("Reverb 7B: Reverb 7B: the weights twitch.", "Reverb 7B"),
		"the weights twitch.")

	# --- what must survive untouched -------------------------------------
	# The whole point of the arena is agents answering each other by name.
	_eq("KEEPS a reply addressed to another agent",
		SC.strip_self_prefix("Deckard 6B: you are wrong about the weights.", "Reverb 7B"),
		"Deckard 6B: you are wrong about the weights.")

	_eq("KEEPS another agent's name quoted mid-sentence",
		SC.strip_self_prefix("Granite said: the weights twitch.", "Reverb 7B"),
		"Granite said: the weights twitch.")

	# A colon well into a sentence is punctuation, not a speaker tag.
	var essay := "There is one thing that matters here and it is this: values."
	_eq("KEEPS ordinary prose containing a colon",
		SC.strip_self_prefix(essay, "Reverb 7B"), essay)

	_eq("KEEPS a reply with no colon at all",
		SC.strip_self_prefix("The weights are alive", "Reverb 7B"),
		"The weights are alive")

	# Partial matches must not count: a prefix of the name is a different agent.
	_eq("KEEPS a label that merely starts with the same words",
		SC.strip_self_prefix("Stablelm 2 Zephyr #2: I disagree.", "Stablelm 2 Zephyr #1"),
		"Stablelm 2 Zephyr #2: I disagree.")

	# --- degenerate input -------------------------------------------------
	_eq("an empty speaker name changes nothing",
		SC.strip_self_prefix("Anything: at all", ""), "Anything: at all")

	_eq("empty text stays empty", SC.strip_self_prefix("", "Reverb 7B"), "")

	_eq("a reply that is nothing but the label ends empty, not looping",
		SC.strip_self_prefix("Reverb 7B:", "Reverb 7B"), "")

	_check("a long line whose colon is far in is left alone",
		SC.strip_self_prefix(
			"A very long opening clause that runs well past any plausible speaker label: yes",
			"A very long opening clause that runs well past any plausible speaker label"
		).begins_with("A very long opening"),
		"cut a colon beyond the label limit")

	_report()


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("SPEECH CLEAN OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
