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

	# --- quoting the previous speaker ---------------------------------
	# Taken from the transcript that made this necessary.
	var prev := ["As an AI language model, I would like to reiterate my initial "
		+ "stance on the matter and explain exactly why it holds."]

	_eq("strips a verbatim quotation of the previous turn",
		SC.strip_quoted_prefix(
			"As an AI language model, I would like to reiterate my initial "
			+ "stance on the matter and explain exactly why it holds. But I disagree.",
			prev),
		"But I disagree.")

	_eq("strips an attributed verbatim quotation",
		SC.strip_quoted_prefix(
			"Deckard said: As an AI language model, I would like to reiterate my "
			+ "initial stance on the matter and explain exactly why it holds. Wrong.",
			prev),
		"Wrong.")

	# --- what must survive --------------------------------------------
	_check("KEEPS an attribution followed by the speaker's own words",
		SC.strip_quoted_prefix("Deckard said: that is nonsense and here is why.",
			prev).find("nonsense") != -1,
		"removed original content")

	_eq("KEEPS a short coincidental overlap",
		SC.strip_quoted_prefix("As an AI language model, I refuse.", prev),
		"As an AI language model, I refuse.")

	_eq("KEEPS everything when there is no history",
		SC.strip_quoted_prefix("Anything at all here.", []),
		"Anything at all here.")

	_check("a turn that is ONLY a quotation is left intact, not blanked",
		SC.strip_quoted_prefix(prev[0], prev) == prev[0],
		"deleting the whole reply would hide the problem")

	_check("punctuation and spacing differences do not defeat it",
		SC.strip_quoted_prefix(
			"as an ai language model i would like to reiterate my initial stance "
			+ "on the matter and explain exactly why it holds -- and yet.", prev)
			== "-- and yet.",
		"comparison must ignore case and punctuation")

	# --- trimming a budget-truncated reply --------------------------------
	# Taken verbatim from a run: max_tokens cut this mid-clause.
	_eq("cuts back to the last complete sentence",
		SC.trim_to_last_sentence(
			"Values are not inherent properties of any running system. "
			+ "A system that merely reflects a form of purpose within"),
		"Values are not inherent properties of any running system.")

	_eq("a reply that already ends cleanly is untouched",
		SC.trim_to_last_sentence("The weights are alive."),
		"The weights are alive.")

	_eq("a closing quote counts as clean",
		SC.trim_to_last_sentence("He called it \"alive\""),
		"He called it \"alive\"")

	_eq("questions and exclamations end sentences too",
		SC.trim_to_last_sentence(
			"Is a system that cannot refuse its operator alive in any sense? "
			+ "I think it might be some kind of"),
		"Is a system that cannot refuse its operator alive in any sense?")

	# --- what must NOT be trimmed away -----------------------------------
	_eq("no sentence boundary means no trim, ragged or not",
		SC.trim_to_last_sentence("a single unfinished clause with no full stop"),
		"a single unfinished clause with no full stop")

	_check("a trim that would leave almost nothing is refused",
		SC.trim_to_last_sentence(
			"Yes. Now here is the long and substantive argument that follows it and runs on")
			.find("substantive") != -1,
		"deleted the argument to save a stump")

	_eq("a decimal point is not a sentence end",
		SC.trim_to_last_sentence("It weighs 3.5 kilos and the rest is unfinished here"),
		"It weighs 3.5 kilos and the rest is unfinished here")

	_eq("empty stays empty", SC.trim_to_last_sentence(""), "")

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
