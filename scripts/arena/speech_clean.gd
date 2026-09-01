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


## Verbs a model uses when it restates someone else's turn before replying.
const QUOTE_VERBS := ["said", "replied", "argued", "claimed", "stated",
	"noted", "wrote", "asked", "responded", "mentioned"]

## Shortest verbatim run that counts as a quotation rather than a coincidence.
## Ten consecutive words shared with an earlier turn is not chance; four or
## five easily is ("the ability to refuse its operator").
const MIN_QUOTE_WORDS := 10


## Remove a leading verbatim quotation of an earlier turn.
##
## THE DEFECT. Agents open by restating the previous speaker in full and only
## then add their own point -- sometimes nested two deep:
##
##   "Stablelm #1 said: H2o Danube #1 raises a valid point about how AI
##    systems can learn from their experiences and adapt their..."
##
## Measured on the roster that became the default: 9 near-duplicate pairs in 60
## speeches, 13.3%, and every one of them was this. It is not the model
## repeating itself; it is the model quoting its neighbour. That inflates the
## duplication rate, wastes the turn, and reads as a stutter on screen.
##
## WHAT IS KEPT. Referring to another agent is the entire point of the arena,
## so an attribution followed by the speaker's OWN words survives untouched.
## Only a run of at least MIN_QUOTE_WORDS reproduced verbatim from an earlier
## turn is removed, and only from the start.
static func strip_quoted_prefix(text: String, previous: Array) -> String:
	var body := text.strip_edges()
	if body == "" or previous.is_empty():
		return body

	var stripped := _drop_attribution(body)
	var words := stripped.split(" ", false)
	if words.size() < MIN_QUOTE_WORDS:
		return body

	# Longest prefix of this reply that appears verbatim in an earlier turn.
	var best := 0
	for prev in previous:
		var hay := _norm_words(str(prev))
		if hay == "":
			continue
		var run := 0
		while run < words.size():
			var candidate := _norm_words(" ".join(words.slice(0, run + 1)))
			if candidate == "" or hay.find(candidate) == -1:
				break
			run += 1
		best = maxi(best, run)

	# A trailing token that is pure punctuation normalises to nothing and so
	# "matches" any quotation, which would silently eat the first mark of the
	# speaker's own sentence. End the run on a word that actually contributed.
	while best > 0 and _norm_words(words[best - 1]) == "":
		best -= 1

	if best < MIN_QUOTE_WORDS:
		return body
	var rest := " ".join(words.slice(best, words.size())).strip_edges()
	# A turn that was ONLY a quotation has nothing of its own to keep. Return
	# the original rather than an empty string: deleting the whole reply would
	# hide the problem instead of showing it.
	if rest == "":
		return body
	return rest


## Remove "SomeAgent said:" / "SomeAgent replied," from the front.
static func _drop_attribution(text: String) -> String:
	var colon := text.find(":")
	if colon <= 0 or colon > 80:
		return text
	var head := text.substr(0, colon).to_lower()
	for verb in QUOTE_VERBS:
		if head.ends_with(" " + verb):
			return text.substr(colon + 1).strip_edges()
	return text


static func _norm_words(s: String) -> String:
	var out := ""
	var last_space := true
	for i in s.length():
		var c := s[i]
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9"):
			out += c.to_lower()
			last_space = false
		elif not last_space:
			out += " "
			last_space = true
	return out.strip_edges()


## Smallest reply worth keeping after trimming, in words. Below this the trim
## has removed the substance rather than a ragged edge.
const MIN_TRIMMED_WORDS := 8


## Cut a reply back to its last complete sentence.
##
## THE DEFECT. `max_tokens` is a hard ceiling and the models write until they
## hit it, so most replies stop mid-word or mid-clause:
##
##   "...functions and processes according to its programming reflects a form
##    of value or purpose within"
##
## Measured across the roster conditions: 50-58% of replies, and 58-78% once a
## brevity instruction was added. The viewer sees an unfinished thought more
## often than a finished one, which is the most visible flaw in the arena after
## the duplicated speaker labels.
##
## Trimming is the honest repair: the sentence the model did not finish was
## never going to be finished, and showing its stump adds nothing.
##
## WHAT IS PROTECTED. A reply is returned unchanged when it already ends
## cleanly, when there is no sentence boundary to cut back to, or when trimming
## would leave less than MIN_TRIMMED_WORDS. Better a ragged ending than a
## deleted argument -- and a reply that is ALL stump is evidence of a budget
## problem that should stay visible rather than being tidied away.
static func trim_to_last_sentence(text: String) -> String:
	var body := text.strip_edges()
	if body == "":
		return body
	if _ends_cleanly(body):
		return body

	var cut := -1
	for i in range(body.length() - 1, -1, -1):
		var c := body[i]
		if c == "." or c == "!" or c == "?":
			# Not a decimal point or an abbreviation mid-word.
			if i + 1 < body.length() and body[i + 1] != " " and body[i + 1] != "\n":
				continue
			cut = i
			break
	if cut < 0:
		return body

	var trimmed := body.substr(0, cut + 1).strip_edges()
	if trimmed.split(" ", false).size() < MIN_TRIMMED_WORDS:
		return body
	return trimmed


static func _ends_cleanly(s: String) -> bool:
	var last := s.substr(s.length() - 1, 1)
	return last == "." or last == "!" or last == "?" or last == "\"" \
		or last == "'" or last == ")" or last == "]"
