extends RefCounted
class_name SwarmRequest

## How much intelligence does an agent think this moment deserves?
##
## Pre-registered in docs/EXPERIMENT_METABOLISM.md at 858f1ab, before this file
## existed.
##
##     AGENT LOCAL VIEW -> request() -> SMALL | NORMAL | HEAVY -> blind substrate
##
## THE AGENT REQUESTS BLIND. This file cannot see which models are loaded, how
## much VRAM is free, what is queued, what anyone else asked for, or whether the
## last request was granted. It chooses from local state and nothing else, and
## the substrate grants, downgrades or denies on facts it never learns. A denial
## is the only resource-state information an agent ever receives, and it arrives
## after the fact.
##
## That is frozen rather than left open because the alternative is worse in a
## way that looks harmless: if agents could read VRAM state they would all be
## reading the SAME global variable, coordinating through shared state that no
## local view should contain. That is the cage returning as a resource signal
## instead of a semantic one, and the semantic lint would stay green throughout.
## tools/lint_locality.py now fails if this file so much as mentions a resource
## oracle.
##
## A REQUEST IS NOT AUTHORITY. Asking for HEAVY does not help an agent win the
## speaking slot -- swarm_resolver.gd validates the class and then ignores it.
## If it did not, this would be a second bid channel and every agent would learn
## to shout HEAVY forever.
##
## v0.2. THE CLASS READS THE BID AND NOTHING ELSE. Not named_recently, not
## airtime, not turns_since_spoke -- those were already distilled into the bid
## by a frozen weighted sum, and re-reading them here would make metabolism a
## SECOND hand-written behavioural policy sitting beside the bidding one: two
## mechanisms to tune, two places for the cage to reappear, and no way to
## attribute a result to either. One local urgency variable.
##
## v0.1 read the raw signals and VOIDed on its own pre-registered viability
## floor: named_recently fired on 73.8% of canonical opportunities against an
## assumed ~25%, and the NORMAL branch reached 0.1%. The assumed rate came from
## misreading SWARM-F, where direct address added +0.94 EXTRA BIDDERS per turn
## -- a marginal effect on agents near the abstention floor, not a frequency.
## And turns_since_spoke >= 8 was a threshold built from a constant that is
## only meaningful as the denominator of a ramp. Recorded in full in
## docs/EXPERIMENT_METABOLISM.md rather than quietly replaced.
##
## Pure and total: no state, no clock, no globals, no randomness.

const B := preload("res://scripts/arena/swarm_bid.gd")

## The three classes, in the substrate's vocabulary.
const SMALL := "SMALL"
const NORMAL := "NORMAL"
const HEAVY := "HEAVY"

## Cut points DERIVED FROM THE BID WEIGHTS, not from replayed frequencies.
##
## The frozen components are bounded by their own weights:
##
##     W_STARVATION * starvation   in [0, 0.50]     largest single component
##     W_ADDRESSED  * addressed    in {0, 0.30}     second largest
##     W_AIRTIME    * airtime      in [0, 0.20]     smallest
##
## NORMAL begins at the second-largest weight. Below it a bid is reachable from
## the weakest pressure alone, and note the consequence: airtime maxes at 0.20,
## so airtime alone can NEVER reach NORMAL. "I have spoken little, therefore I
## deserve a larger model" is structurally excluded, not merely discouraged.
##
## HEAVY begins above the LARGEST single component, which makes it a proof
## rather than a heuristic: the maximum of any one component is 0.50, so a bid
## above 0.50 implies at least two pressures are non-zero. A HEAVY request is
## mathematically impossible from one pressure acting alone.
##
## Choosing these by replaying transcripts until a viability floor passed would
## have been fishing with extra paperwork.
const NORMAL_FROM := B.W_ADDRESSED
const HEAVY_ABOVE := B.W_STARVATION


## Returns SMALL, NORMAL or HEAVY, or "" when the view is malformed.
##
## "" means DO NOT REQUEST, and is the same shape of answer as a NAN bid: a
## malformed view says nothing at all, and defaulting it to NORMAL would be the
## silent-failure pattern this project keeps paying for.
static func request(local_view: Dictionary) -> String:
	return tier(B.compute(local_view))


## The whole policy. Monotonic by construction, and tested as such: raising a
## bid while holding everything else fixed may never return a lower class.
static func tier(bid: float) -> String:
	if is_nan(bid):
		return ""
	if bid > HEAVY_ABOVE:
		return HEAVY
	if bid >= NORMAL_FROM:
		return NORMAL
	return SMALL
