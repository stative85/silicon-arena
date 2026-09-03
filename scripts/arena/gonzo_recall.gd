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

## A memory must be OLDER than the visible transcript to be worth recalling.
##
## The agent already sees the recent turns. Surfacing something from two turns
## ago adds nothing and merely spends prompt budget re-showing what is on
## screen. Measured before this bound existed: mean recall distance 2.5 turns,
## which is not memory, it is duplication.
const MIN_RECALL_DISTANCE := 10

## Both arms of the distance-vs-resonance test draw from the SAME shortlist:
## the N most distant eligible scars. G1 then takes the furthest of them and G2
## the most resonant of them. Matching the pool by construction is the only way
## to remove the two confounds the first experiment had -- the arms differed in
## injection count and in how far back they reached, either of which could have
## carried the result.
const CANDIDATE_SHORTLIST := 4
const DECAY_HALF_LIFE_TURNS := 15.0
const MIN_ELIGIBLE_SCORE := 0.20   # in distance-units after decay and novelty


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
	# Challenge first: "disagree" contains "agree", so checking concessions
	# first classified every disagreement as a concession.
	if _has_any(text, CHALLENGE_WORDS):
		return "challenge"
	if _has_any(text, CONCEDE_WORDS):
		return "concede"
	return "assert"


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


## Retrieval score. Distance, discounted by age and by how often this scar has
## already surfaced.
##
## There was a four-dimensional resonance ranking here -- semantic,
## interpersonal, contradiction and structural -- and it was DELETED after a
## paired counterfactual tournament over 127 opportunities in which the same
## agent, at the same moment, with the same candidate pool, answered once with
## the resonance pick and once with the distance pick:
##
##     distance   69.3% callback conversion
##     resonance  65.4%
##
## The pre-registered rule required resonance to earn 8 points to justify its
## machinery. It returned -3.9 (docs/EXPERIMENT_TOURNAMENT.md).
##
## What remains is a plainer and stranger policy: an old scar comes back
## because it survived decay, fell out of the working context, and is still
## eligible. Whether it matters is the model's problem, not the scorer's.
static func score(scar: Dictionary, now_text: String, now_speaker: String,
		named_now: Array, turn: int) -> float:
	var distance := float(maxi(turn - int(scar.get("source_turn", turn)), 0))
	return (distance
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
	if turn - int(scar.get("source_turn", turn)) < MIN_RECALL_DISTANCE:
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
