extends RefCounted
class_name SwarmBid

## How much does one agent want the slot, computed from what only it knows?
##
## Pre-registered in docs/EXPERIMENT_SWARM.md at 85d34f2.
##
## This file is allowed to understand meaning. That is the whole architecture:
## interpretation lives out here with the agents, and the substrate that
## arbitrates -- swarm_resolver.gd -- is forbidden from seeing any of it. What
## crosses the boundary is one number.
##
##     AGENT LOCAL VIEW -> compute() -> scalar bid -> blind resolver -> speaker
##
## THE COMPONENTS MUST NEVER CROSS INDIVIDUALLY. Not as fields, not as a
## breakdown, not as `bid_reason` for debugging. A debug field is how semantic
## authority crawls back in wearing a reflective vest, and swarm_resolver.gd
## refuses unknown keys precisely so that it cannot be done quietly.
##
## Pure and total: no state, no clock, no globals, no randomness. Same view,
## same number, forever. The paired frozen-state design depends on it.
##
## Deliberately boring. v0.1 is asking whether local bidding can allocate a slot
## at all, and a clever bid function would make a positive result impossible to
## attribute.

## Turns of silence at which starvation pressure saturates. Roughly two full
## rotations of a five-agent roster.
const STARVATION_SATURATION := 8.0

## Share of recent turns an agent would hold if airtime were even across five.
const FAIR_SHARE := 0.2

## Frozen weights. Changing them is a change to the experiment.
const W_STARVATION := 0.5
const W_ADDRESSED := 0.3
const W_AIRTIME := 0.2

const REQUIRED := ["turns_since_spoke", "named_recently", "airtime_share"]


## Returns a bid in [0, 1], or NAN when the view is malformed.
##
## NAN means DO NOT BID. It is not a zero bid -- a zero bid says "I am here and
## I do not want the slot", which is a real local decision, while a malformed
## view says nothing at all. An agent that gets NAN submits no entry, and the
## resolver reports NO_BIDS or routes around it. Defaulting the missing fields
## instead would be the silent-failure pattern this project keeps paying for.
static func compute(local_view: Dictionary) -> float:
	for key in REQUIRED:
		if not local_view.has(key):
			return NAN

	var since = local_view["turns_since_spoke"]
	var named = local_view["named_recently"]
	var share = local_view["airtime_share"]
	if typeof(since) != TYPE_INT and typeof(since) != TYPE_FLOAT:
		return NAN
	if typeof(named) != TYPE_BOOL:
		return NAN
	if typeof(share) != TYPE_INT and typeof(share) != TYPE_FLOAT:
		return NAN
	if not is_finite(float(since)) or not is_finite(float(share)):
		return NAN
	if float(since) < 0.0 or float(share) < 0.0:
		return NAN

	# Longer silence, more pressure, saturating so one forgotten agent cannot
	# accumulate unbounded claim on the slot.
	var starvation := clampf(float(since) / STARVATION_SATURATION, 0.0, 1.0)

	# Being named is observed by the agent in what it can see. The resolver is
	# never told this happened, only that the number went up.
	var addressed := 1.0 if bool(named) else 0.0

	# Less airtime than an even share, more pressure. This is the agent's own
	# accounting of itself, not a fairness rule imposed by a referee.
	var airtime := clampf(1.0 - (float(share) / FAIR_SHARE), 0.0, 1.0)

	return clampf(
		W_STARVATION * starvation + W_ADDRESSED * addressed + W_AIRTIME * airtime,
		0.0, 1.0)


## The view an agent assembles about ITSELF. Present so the shape is written
## down once; nothing here is ever handed to the resolver.
static func local_view(turns_since_spoke: int, named_recently: bool,
		airtime_share: float) -> Dictionary:
	return {
		"turns_since_spoke": turns_since_spoke,
		"named_recently": named_recently,
		"airtime_share": airtime_share,
	}
