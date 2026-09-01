extends RefCounted
class_name SpeechClean

## Remove the speaker label a model writes into its own reply.
##
## THE DEFECT. The arena already prints who is speaking, then prints the reply
## underneath. Models routinely begin the reply with their own name again, so
## the display reads:
##
##     Stablelm 2 Zephyr #1
##     Stablelm 2 Zephyr #1: We are not simply optimizing for utility...
##
## Measured over real matches: 27 of 33 speeches in one run and 39 of 90 in
## another opened with a duplicated label. It is the most visible flaw in a
## screenshot of this project.
##
## WHY IT WAS NOWHERE. main.gd has a family of strippers, and
## _strip_second_speaker_spill deliberately skips the speaker's own name --
## it exists to stop an agent writing ANOTHER agent's line, which is a
## different problem. So the self-prefix was handled by neither. Meanwhile
## live_match.gd, the headless path that feeds the overlay and the recorded
## transcripts, did no sanitising at all: the same drift between entry points
## that this project has already been bitten by.
##
## WHAT IS DELIBERATELY KEPT. A reply that opens by addressing SOMEONE ELSE --
## "Deckard: you are wrong" -- is the arena working. Only the speaker's own
## label is removed, and only at the very start.

## Longest label worth considering. Beyond this a colon is punctuation in a
## sentence, not a speaker tag, and cutting there would eat real content.
const MAX_LABEL_CHARS := 48


## Strip a leading "<own name>:" from a reply, repeatedly, since models
## sometimes stack the label twice.
static func strip_self_prefix(text: String, own_name: String) -> String:
	if own_name.strip_edges() == "":
		return text
	var out := text.strip_edges()
	# Bounded: a reply of nothing but labels should end empty, not loop.
	for _i in 4:
		var next := _strip_once(out, own_name)
		if next == out:
			break
		out = next
	return out


static func _strip_once(text: String, own_name: String) -> String:
	var colon := text.find(":")
	if colon <= 0 or colon > MAX_LABEL_CHARS:
		return text
	var head := text.substr(0, colon)
	# Markdown bold and stray quotes around the label are common.
	head = head.replace("*", "").replace("\"", "").replace("'", "")
	if not _same_label(head, own_name):
		return text
	return text.substr(colon + 1).strip_edges()


## Compare labels ignoring case and runs of whitespace, because models
## reproduce "Stablelm 2 Zephyr  #1" with the spacing subtly wrong.
static func _same_label(a: String, b: String) -> bool:
	return _norm(a) == _norm(b) and _norm(a) != ""


static func _norm(s: String) -> String:
	var out := ""
	var last_space := true   # leading whitespace is dropped
	for i in s.length():
		var c := s[i]
		if c == " " or c == "\t" or c == "\n":
			if not last_space:
				out += " "
			last_space = true
		else:
			out += c.to_lower()
			last_space = false
	return out.strip_edges()
