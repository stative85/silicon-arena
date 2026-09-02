extends RefCounted
class_name Presentation

## How long a turn stays on screen, and why.
##
## The arena's rhythm is uniform: every turn gets the same dwell regardless of
## what was said. Sixty equally weighted turns read as a municipal hearing even
## when the content is good.
##
## This classifies a turn from metadata the runtime ALREADY produces — length,
## whether it contradicts, whether it names someone, whether it repeats — and
## returns a presentation treatment. It never changes what was said, never
## reorders anything, and never invents drama the transcript does not contain.
##
## MEAN-PRESERVING BY CONSTRUCTION. The weights below sum so that a
## representative mix of turns averages 1.0x. Variety must not become a
## slowdown: the arena's throughput was earned by measurement (AUTO, the
## headless pipeline) and presentation may not quietly spend it.
##
## INVARIANT   every turn gets exactly one treatment; every multiplier is
##             finite and within [MIN, MAX]; an unclassifiable turn gets
##             ORDINARY rather than nothing; the mean multiplier over a
##             representative mix stays near 1.0.
## DETECTION   classify() is total — there is no input it cannot answer for.
## TEETH       out-of-range or unknown treatments fall back to ORDINARY.
## RECOVERY    ordinary presentation is always a valid answer.
## PROOF       presentation_selftest.gd, including a mix-mean check.

enum Beat { ORDINARY, PUNCH, CONNECT, QUICK, HOLD, REVERSAL }

## Dwell multipliers. Bounded so no turn can vanish or stall the arena.
const MIN_MULTIPLIER := 0.35
const MAX_MULTIPLIER := 1.6

## Weights calibrated against the distribution that ACTUALLY occurs, measured
## over a 200-second run: CONNECT 9, HOLD 6, ORDINARY 6, QUICK 3, PUNCH 2,
## REVERSAL 0 out of 26 turns.
##
## The first set was balanced against a guessed mix and applied a mean of
## 1.046 in practice -- a 4.6% slowdown the selftest could not see, because it
## was checking an assumption rather than the arena. Naming another agent turns
## out to be the COMMON case here, not a special one, so CONNECT is
## dwell-neutral and kept only as a distinct beat for camera work; the variety
## has to come from the genuinely unusual turns.
const MULTIPLIER := {
	Beat.ORDINARY: 1.0,
	Beat.CONNECT: 1.0,    # common: dwell-neutral, still labelled
	Beat.PUNCH: 1.2,      # a sharp contradiction earns a moment
	Beat.QUICK: 0.35,     # a short reply should not sit there
	Beat.HOLD: 1.25,      # a long reply needs reading time
	Beat.REVERSAL: 1.4,   # changing position is the rarest thing here
}

const SHORT_WORDS := 25
const LONG_WORDS := 75

## Words that mark an agent abandoning a position rather than defending one.
const REVERSAL_MARKERS := ["i was wrong", "i concede", "you are right",
	"you're right", "i withdraw", "i change my", "i accept that", "fair point"]


## Classify a turn. Total: every input yields exactly one beat.
##
## Order matters and encodes priority. A reversal is the rarest and most
## interesting event in this arena and outranks everything; repetition is
## demoted regardless of what else it looks like, because a repeated point
## should not be rewarded with extra time on screen.
static func classify(text: String, words: int, names_other: bool,
		contradicts: bool, is_near_duplicate: bool) -> Beat:
	var low := text.to_lower()
	for m in REVERSAL_MARKERS:
		if low.find(m) != -1:
			return Beat.REVERSAL
	if is_near_duplicate:
		return Beat.QUICK
	if words <= SHORT_WORDS:
		return Beat.QUICK
	if contradicts and names_other:
		return Beat.PUNCH
	if words >= LONG_WORDS:
		return Beat.HOLD
	if names_other:
		return Beat.CONNECT
	return Beat.ORDINARY


## Dwell multiplier for a beat, clamped. An unknown beat is ORDINARY: a
## classifier that cannot answer must not be able to stall or skip a turn.
static func multiplier(beat: int) -> float:
	if not MULTIPLIER.has(beat):
		return MULTIPLIER[Beat.ORDINARY]
	return clampf(float(MULTIPLIER[beat]), MIN_MULTIPLIER, MAX_MULTIPLIER)


## Human-readable name, for logs and the selftest.
static func beat_name(beat: int) -> String:
	match beat:
		Beat.PUNCH: return "PUNCH"
		Beat.CONNECT: return "CONNECT"
		Beat.QUICK: return "QUICK"
		Beat.HOLD: return "HOLD"
		Beat.REVERSAL: return "REVERSAL"
		_: return "ORDINARY"


## ── Keeping the applied mean near 1.0 whatever the arena does ──────────────
##
## Fixed weights cannot preserve the mean, because the beat distribution is not
## fixed. Measured over two 200-second runs of the same build:
##
##   run 1   CONNECT 9  HOLD  6  ORDINARY 6  QUICK 3  PUNCH 2  REVERSAL 0
##   run 2   CONNECT 2  HOLD 12  ORDINARY 7  QUICK 3  PUNCH 0  REVERSAL 3
##
## Weights calibrated to the first applied a mean of 1.083 under the second.
## Calibrating to a measured distribution is no better than calibrating to a
## guessed one when the distribution itself moves.
##
## So the multiplier is corrected against the running mean instead: half the
## turn's own character, half a pull back toward the cumulative target. Over a
## sequence the applied mean converges toward 1.0 for ANY distribution, and for
## a degenerate one (every turn the same beat) it lands as close as the clamp
## allows -- there is nothing to be shorter than.
const TARGET_MEAN := 1.0


## Applied multiplier for turn number `count` (0-based), given the sum of all
## multipliers applied so far. Total: any input returns a bounded value.
static func normalized(raw: float, applied_sum: float, count: int) -> float:
	if count <= 0:
		return clampf(raw, MIN_MULTIPLIER, MAX_MULTIPLIER)
	var target_total := TARGET_MEAN * float(count + 1)
	var pull := target_total - applied_sum
	return clampf(0.5 * raw + 0.5 * pull, MIN_MULTIPLIER, MAX_MULTIPLIER)
