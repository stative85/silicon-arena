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
## Deliberately boring, v0.1, for the same reason swarm_bid.gd is: a clever
## request function would make a positive result impossible to attribute. Its
## only job is to be locally derived and non-degenerate.
##
## Pure and total: no state, no clock, no globals, no randomness.

const B := preload("res://scripts/arena/swarm_bid.gd")

## The three classes, in the substrate's vocabulary.
const SMALL := "SMALL"
const NORMAL := "NORMAL"
const HEAVY := "HEAVY"

## Frozen. `named_recently` triggers HEAVY because SWARM-F established it as a
## real local signal rather than a guess -- direct address carried a stable
## +0.94 extra bidder there (docs/EXPERIMENT_SWARM_F.md). No weight fishing was
## required to find it and none is permitted to tune it.
const NORMAL_AT_SILENCE := B.STARVATION_SATURATION


## Returns SMALL, NORMAL or HEAVY, or "" when the view is malformed.
##
## "" means DO NOT REQUEST, and is the same shape of answer as a NAN bid: a
## malformed view says nothing at all, and defaulting it to NORMAL would be the
## silent-failure pattern this project keeps paying for.
static func request(local_view: Dictionary) -> String:
	for key in B.REQUIRED:
		if not local_view.has(key):
			return ""

	var since = local_view["turns_since_spoke"]
	var named = local_view["named_recently"]
	if typeof(named) != TYPE_BOOL:
		return ""
	if typeof(since) != TYPE_INT and typeof(since) != TYPE_FLOAT:
		return ""
	if not is_finite(float(since)) or float(since) < 0.0:
		return ""

	# Someone addressed me. Whatever is happening, it is happening to me.
	if bool(named):
		return HEAVY

	# I have been quiet long enough that starvation has saturated.
	if float(since) >= NORMAL_AT_SILENCE:
		return NORMAL

	return SMALL
