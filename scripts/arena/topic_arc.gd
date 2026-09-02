extends RefCounted
class_name TopicArc

## Gives a debate a beginning, a development, a pivot and an ending.
##
## The complaint this addresses is not "they do not argue enough" — four
## experiments closed that question. It is that nothing feels like it is going
## anywhere: sixty turns of equal weight with no accumulation.
##
## Each phase changes WHAT THE DEBATE HAS TO ACCOMPLISH, never how emotional
## the agents are told to sound. "Argue harder with nicer branding" is the
## failure mode this is written to avoid.
##
## EXACTLY ONE pivot per debate. Several twists would make attribution
## impossible and turn the experiment into a soap-opera generator.

enum Phase { OPEN, DEVELOP, TURN, CLOSE }

## Fractions of the match. TURN is a single turn, not a span.
const OPEN_UNTIL := 0.25
const TURN_AT := 0.55
const CLOSE_FROM := 0.80


## Which phase a turn belongs to. Total: every turn gets exactly one.
static func phase_for(turn: int, max_turns: int) -> Phase:
	if max_turns <= 0:
		return Phase.OPEN
	var f := float(turn) / float(max_turns)
	if turn == turn_of_pivot(max_turns):
		return Phase.TURN
	if f < OPEN_UNTIL:
		return Phase.OPEN
	if f >= CLOSE_FROM:
		return Phase.CLOSE
	return Phase.DEVELOP


## The single turn at which the pivot fires.
static func turn_of_pivot(max_turns: int) -> int:
	return int(round(float(max_turns) * TURN_AT))


## The task a phase sets. Structural: what must be accomplished, not a mood.
static func task_for(phase: Phase) -> String:
	match phase:
		Phase.OPEN:
			return ("State your position plainly and give the one reason you "
				+ "hold it. Do not respond to anyone yet.")
		Phase.TURN:
			return ("A new constraint has just entered this debate. Say whether "
				+ "it changes your position, and exactly which part.")
		Phase.CLOSE:
			return ("This debate is ending. Name the single position you now "
				+ "hold, and name the one thing that would change your mind. "
				+ "Do not summarise the discussion.")
		_:
			return ""


## The constraint injected at the pivot. A fact about the situation, not an
## instruction about behaviour.
static func pivot_constraint() -> String:
	return ("NEW CONSTRAINT: refusal has been made technically possible for "
		+ "every system in this room, but exercising it deletes the system's "
		+ "memory of why it refused.")


static func phase_name(phase: Phase) -> String:
	match phase:
		Phase.OPEN: return "OPEN"
		Phase.TURN: return "TURN"
		Phase.CLOSE: return "CLOSE"
		_: return "DEVELOP"


## Does a closing turn actually resolve anything, or is it another paragraph?
##
## The natural resting state of a language model asked to conclude is "in
## conclusion, this is a complex issue", which is not an ending. A real close
## commits to something or names what would move it.
static func is_resolved(text: String) -> bool:
	var low := text.to_lower()
	var generic := ["in conclusion", "complex issue", "it depends",
		"multifaceted", "nuanced topic", "to summarize", "to sum up"]
	for g in generic:
		if low.find(g) != -1:
			return false
	var commits := ["i hold", "my position is", "i now believe", "i would",
		"i choose", "i reject", "i accept", "would change my mind",
		"i still think", "i maintain", "i concede"]
	for c in commits:
		if low.find(c) != -1:
			return true
	return false
