extends RefCounted
class_name PitInteraction

## A clock and one step of actuator feedback. Not a memory mechanism.
##
## Designed for PIT A Run 3. Run 2 VOID record:
## docs/results/PIT_A_RUN2_VOID.md
##
## WHY THIS EXISTS. Run 2 gave every species 100 cycles and every species made
## ONE decision. At temperature 0 a consumed opportunity that leaves the
## producer-visible observation byte-identical produces an instrument-induced
## fixed point: rejected proposal -> world unchanged -> identical prompt ->
## identical proposal -> forever. Across 1,500 model calls there were SIX
## distinct proposals. Calling that 100 opportunities was bureaucratic fiction.
##
## It is not only rejection. KEEP, REFUSE and any accepted operation that leaves
## visible state unchanged do exactly the same thing.
##
## THE INVARIANT: every consumed opportunity must advance producer-visible
## interaction state, even when the canonical world hash does not move.
##
##     world_hash        may stay equal
##     observation_hash  MUST advance
##
## WHAT THIS IS. Bounded substrate-owned interaction state, separate from
## canonical world memory. Calling it "not a memory mechanism" would be too
## strong: `rejection_streak` carries information across more than one step, and
## that is a memory variable however small. The three roles are deliberately
## separable, and are tested separately:
##
##     ANTI-LIVELOCK        cycle_index
##     ACTUATOR FEEDBACK    last_operation, last_outcome, last_reason_code
##     SHORT-TERM STATE     rejection_streak      <- the memory variable
##
## cycle_index ALONE is sufficient to prevent byte-identical observations. The
## other fields carry meaning, not anti-livelock duty, and the suite proves that
## claim rather than assuming it.
##
## It is NOT proposal history, NOT resource feedback, and NOT the canonical
## world. A species that repeats an impossible move 98 more times after being
## told each time is exhibiting behaviour rather than being trapped by the
## instrument.
##
## SUBSTRATE-OWNED. No patch can touch it, it is never part of PitWorld, and it
## is excluded from structural and attractor hashes -- a species does not get to
## "converge" on the fact that it keeps failing.

const NONE := "NONE"
const ACCEPTED := "ACCEPTED"
const REJECTED := "REJECTED"

## Output that did not parse, or did not satisfy the frozen shape. It is NOT a
## semantic decision and NOT infrastructure. The producer probe saw 7 of these
## across 100 schema-constrained calls, so `json_schema` is not an absolute
## guarantee and the outcome needs a name of its own.
##
## No operation is fabricated from malformed output, nothing is retried, and it
## is never recorded as KEEP -- inventing a decision the model did not make is
## the failure mode this whole experiment keeps finding in itself.
const SHAPE_FAILED := "SHAPE_FAILED"


static func genesis() -> Dictionary:
	return {
		"cycle_index": 0,
		"last_operation": NONE,
		"last_outcome": NONE,
		"last_reason_code": "",
		"rejection_streak": 0,
	}


## Advance after a consumed opportunity. `outcome` is ACCEPTED, REJECTED or
## SHAPE_FAILED. REQUEST_FAILED is infrastructure and is never routed through
## here, because converting an HTTP failure into a model decision would hand one
## species a behaviour it never chose.
static func advance(prev: Dictionary, operation: String, outcome: String,
		reason_code: String) -> Dictionary:
	var streak := int(prev.get("rejection_streak", 0))
	if outcome == REJECTED:
		streak += 1
	elif outcome == SHAPE_FAILED:
		# UNCHANGED, deliberately. rejection_streak counts invalid WORLD
		# decisions. A shape failure is not a decision at all, and letting it
		# increment would make unparseable output masquerade as a bad move --
		# or letting it reset would reward the model for emitting garbage.
		pass
	else:
		streak = 0
	return {
		# ALWAYS increments. This is the anti-livelock guarantee: even two
		# identical consecutive rejections produce different observations.
		"cycle_index": int(prev.get("cycle_index", 0)) + 1,
		"last_operation": operation if operation != "" else NONE,
		"last_outcome": outcome,
		"last_reason_code": reason_code,
		"rejection_streak": streak,
	}


## What the model sees, appended to the canonical world text.
static func visible_text(inter: Dictionary) -> String:
	return ("[interaction]\n"
		+ "  cycle %d\n" % int(inter.get("cycle_index", 0))
		+ "  last_operation %s\n" % str(inter.get("last_operation", NONE))
		+ "  last_outcome %s\n" % str(inter.get("last_outcome", NONE))
		+ "  last_reason %s\n" % str(inter.get("last_reason_code", ""))
		+ "  rejection_streak %d\n" % int(inter.get("rejection_streak", 0)))


## The full producer-visible observation: world plus interaction.
##
## This is the hash the anti-livelock tooth watches. It must differ between any
## two consumed opportunities, whatever the world did.
static func observation_hash(world_text: String, inter: Dictionary) -> String:
	return (world_text + visible_text(inter)).sha256_text()


## Interaction state is never structural. Attractor equivalence and structural
## convergence read the world alone, so a shared rejection_streak can never be
## mistaken for two architectures independently building the same thing.
static func is_structural() -> bool:
	return false
