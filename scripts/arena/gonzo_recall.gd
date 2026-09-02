extends RefCounted
class_name GonzoRecall

## Sparse, decaying, resonance-based retrieval over canonical history.
##
## THE THESIS. Not "give agents more context". Whether distant history can bend
## present behaviour WITHOUT instructing the model what to do with it.
##
## That distinction is load-bearing. Nine pre-registered interventions have been
## rejected and the pattern is consistent: everything that tried to change what
## the models were ASKED to produce failed, and the two things that shipped
## changed what the arena DOES with output. So the injected text here is
## deliberately sterile - an excerpt and its provenance, nothing about how the
## memory should feel.
##
## THREE LAYERS ONLY.
##   L0 CANON   immutable turns: speaker, turn id, exact text
##   L1 SCARS   sparse pointers to canonical moments that earned persistence
##   L3 ECHOES  a scar becomes eligible when the present resonates with it
##
## No motifs, no hypotheses, no theatrical framing. Those are derived content,
## and derived content is where fabricated attribution enters; they must earn
## existence on evidence.

const MAX_RECALLS_PER_PROMPT := 2
const RECALL_COOLDOWN_TURNS := 4
const DECAY_HALF_LIFE_TURNS := 15.0
const MIN_ELIGIBLE_SCORE := 0.20

## Interpersonal and contradiction outweigh raw word overlap on purpose: the
## interesting recall is one where the ARGUMENT rhymes, not the nouns.
const W_SEMANTIC := 0.30
const W_INTERPERSONAL := 0.25
const W_CONTRADICTION := 0.25
const W_STRUCTURAL := 0.20

const CHALLENGE_WORDS := ["disagree", "wrong", "however", "actually", "refute",
	"reject", "mistaken", "incorrect", "flawed", "misses", "overlooks"]
const CONCEDE_WORDS := ["agree", "concede", "fair point", "granted", "i accept"]

const STOP := ["the", "a", "an", "and", "or", "but", "if", "then", "that",
	"this", "is", "are", "was", "were", "be", "to", "of", "in", "on", "at",
	"by", "for", "with", "as", "from", "it", "its", "you", "they", "we", "not",
	"have", "has", "had", "will", "would", "can", "could", "should", "there",
	"their", "them", "what", "which", "when", "where", "why", "how", "all",
	"any", "some", "only", "very", "just", "also", "into", "about", "over"]


static func _content(text: String) -> Dictionary:
	var out := {}
	for w in text.to_lower().split(" ", false):
		var clean := ""
		for i in w.length():
			var c := w[i]
			if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
				clean += c
		if clean.length() > 3 and not STOP.has(clean):
			out[clean] = true
	return out


static func _has_any(text: String, words: Array) -> bool:
	var low := text.to_lower()
	for w in words:
		if low.find(w) != -1:
			return true
	return false


## Coarse shape of a turn. Structural resonance is shape-matching: a
## contradiction rhymes with a contradiction even when the subject differs.
static func shape_of(text: String) -> String:
	if _has_any(text, CONCEDE_WORDS):
		return "concede"
	if _has_any(text, CHALLENGE_WORDS):
		return "challenge"
	return "assert"


## Four independent readings of "does this old moment rhyme with now?".
##
## Kept separate from intensity and age, which are facts about the MEMORY
## rather than about the match. Folding them together would make a bad recall
## impossible to diagnose: you could not tell a strong old memory from a
## genuinely similar moment.
static func resonance(scar: Dictionary, now_text: String, now_speaker: String,
		named_now: Array) -> Dictionary:
	var scar_words := _content(str(scar.get("excerpt", "")))
	var now_words := _content(now_text)
	var inter := 0
	for w in scar_words:
		if now_words.has(w):
			inter += 1
	var union := scar_words.size() + now_words.size() - inter
	var semantic := (float(inter) / float(union)) if union > 0 else 0.0

	var a := str(scar.get("source_speaker", ""))
	var b := str(scar.get("other_speaker", ""))
	var interpersonal := 0.0
	if now_speaker == a or now_speaker == b:
		interpersonal += 0.5
	if named_now.has(a) or named_now.has(b):
		interpersonal += 0.5

	var now_shape := shape_of(now_text)
	var contradiction := 1.0 if (now_shape == "challenge"
		and str(scar.get("shape", "")) == "challenge") else 0.0
	var structural := 1.0 if now_shape == str(scar.get("shape", "")) else 0.0

	return {"semantic": semantic, "interpersonal": interpersonal,
		"contradiction": contradiction, "structural": structural}


static func weighted_resonance(r: Dictionary) -> float:
	return (W_SEMANTIC * float(r.get("semantic", 0.0))
		+ W_INTERPERSONAL * float(r.get("interpersonal", 0.0))
		+ W_CONTRADICTION * float(r.get("contradiction", 0.0))
		+ W_STRUCTURAL * float(r.get("structural", 0.0)))


## Age discount. Halves every DECAY_HALF_LIFE_TURNS since last REINFORCEMENT --
## deliberately not since last recall, so remembering something cannot keep it
## young.
static func decay_factor(turn: int, last_reinforced_turn: int) -> float:
	var age := float(maxi(turn - last_reinforced_turn, 0))
	return pow(0.5, age / DECAY_HALF_LIFE_TURNS)


## Repeatedly surfacing the same scar is penalised, so one moment cannot own
## the match.
static func novelty_penalty(recall_count: int) -> float:
	return 1.0 / (1.0 + 0.5 * float(maxi(recall_count, 0)))


static func score(scar: Dictionary, now_text: String, now_speaker: String,
		named_now: Array, turn: int) -> float:
	var r := resonance(scar, now_text, now_speaker, named_now)
	return (weighted_resonance(r)
		* float(scar.get("intensity", 0.0))
		* decay_factor(turn, int(scar.get("last_reinforced_turn", turn)))
		* novelty_penalty(int(scar.get("recall_count", 0))))


## A scar whose excerpt cannot be found in the canonical turn it names is
## destroyed, never guessed at.
static func provenance_holds(scar: Dictionary, history: Array) -> bool:
	var excerpt := str(scar.get("excerpt", ""))
	if excerpt.strip_edges() == "":
		return false
	for h in history:
		if int(h.get("turn", -1)) != int(scar.get("source_turn", -2)):
			continue
		if str(h.get("speaker", "")) != str(scar.get("source_speaker", "")):
			return false
		return str(h.get("text", "")).find(excerpt) != -1
	return false


static func eligible(scar: Dictionary, history: Array, turn: int,
		now_text: String, now_speaker: String, named_now: Array) -> bool:
	if not provenance_holds(scar, history):
		return false
	if turn - int(scar.get("last_recalled_turn", -999)) < RECALL_COOLDOWN_TURNS:
		return false
	return score(scar, now_text, now_speaker, named_now, turn) >= MIN_ELIGIBLE_SCORE


## Mark a scar as surfaced.
##
## THE RULE THAT MATTERS MOST: recall does not strengthen a memory. Without it,
## retrieval manufactures its own evidence -- recalled, therefore stronger,
## therefore recalled more -- and one remark from turn 8 becomes the agent's
## religion. Intensity is returned untouched.
static func on_recall(scar: Dictionary, turn: int) -> Dictionary:
	var out := scar.duplicate()
	out["last_recalled_turn"] = turn
	out["recall_count"] = int(scar.get("recall_count", 0)) + 1
	out["intensity"] = scar.get("intensity", 0.0)
	return out


## Only NEW canonical behaviour strengthens a scar. A caller passing false gets
## its scar back unchanged.
static func reinforce(scar: Dictionary, has_new_evidence: bool,
		turn: int) -> Dictionary:
	if not has_new_evidence:
		return scar.duplicate()
	var out := scar.duplicate()
	out["intensity"] = minf(float(scar.get("intensity", 0.0)) + 0.25, 1.0)
	out["last_reinforced_turn"] = turn
	return out


## The injected text. An excerpt and where it came from; nothing about how the
## memory should feel or what to do with it.
static func render(scar: Dictionary) -> String:
	return ("Relevant prior moment:\n\nTurn %d - %s:\n\"%s\"\n\nThis may be "
		+ "relevant to the current discussion. Use it only if it genuinely "
		+ "helps your response.") % [
		int(scar.get("source_turn", -1)), str(scar.get("source_speaker", "")),
		str(scar.get("excerpt", ""))]
