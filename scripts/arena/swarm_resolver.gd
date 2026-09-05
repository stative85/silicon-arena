extends RefCounted
class_name SwarmResolver

## Arbitration for one scarce speaking slot, and the smallest thing in this
## repository on purpose.
##
## Pre-registered in docs/EXPERIMENT_SWARM.md at 85d34f2, before this file
## existed.
##
## THE POINT IS WHAT THIS FILE CANNOT SEE. A centralized scorer over a global
## agent-feature table is not a swarm -- setting its weight to zero starves
## nothing, because the scheduler is still at full strength with different
## arithmetic. Starving the cage means removing semantic knowledge from the
## controller, not lowering a coefficient.
##
## So the entire input is three keys:
##
##     resolve([{agent_id, eligible, bid, requested_class}, ...])
##         -> {ok, agent_id | code}
##
## `requested_class` was added for METABOLISM-A (docs/EXPERIMENT_METABOLISM.md),
## pre-registered before this key existed. It is SMALL, NORMAL or HEAVY and it
## says WHAT is being asked for, never WHY it is wanted -- the same line these
## failure codes already draw between resource state and motive.
##
## A REQUEST IS NOT AUTHORITY. This file validates the class and then ignores it
## completely: it is not read in the argmax, not folded into the tiebreak salt,
## and cannot move a single allocation. An agent asks for HEAVY; a separate
## substrate decision grants, downgrades or denies it on resource facts the
## agent cannot see. If wanting more compute could win an agent the speaking
## slot, `requested_class` would be a second bid channel and every agent would
## learn to shout HEAVY.
##
## An agent decides locally how much it wants the slot. This decides who gets
## it. It cannot know why anyone wants it, and there is no field through which
## it could be told.
##
## A SEMANTIC FIELD IS A HARD FAILURE, NOT AN IGNORED ONE. Silently dropping
## unknown keys would let `direct_address` sit in the payload for months while
## everyone believed the boundary held. Adding one breaks the run loudly, and
## an import lint (tools/lint_locality.py) fails if this file can even reach a
## module that carries history, memory or turn content.
##
## Deterministic: argmax, with agent_id as the tiebreak. Stochastic contention
## is a later condition and would destroy the paired design v0.1 relies on.

## The whole vocabulary. Anything else is malformed.
const ALLOWED_KEYS := ["agent_id", "eligible", "bid", "requested_class"]

## The only legal compute requests. An unrecognised class is MALFORMED_BID and
## is never coerced to a default: a silent downgrade to NORMAL would let a typo
## look like a policy decision for months.
const CLASSES := ["SMALL", "NORMAL", "HEAVY"]

## Failure codes. These describe RESOURCE state, never motive.
const OK := "OK"
const NO_BIDS := "NO_BIDS"
const NO_ELIGIBLE_BIDS := "NO_ELIGIBLE_BIDS"
const MALFORMED_BID := "MALFORMED_BID"


## Returns {"ok": true, "agent_id": String} or {"ok": false, "code": String}.
##
## Staleness is not visible here and is not meant to be: a bid carries no
## timestamp because a timestamp is one more thing the substrate could learn to
## reason about. Whoever collects bids passes only the current opportunity's,
## and reports stale ones itself.
static func resolve(bids: Array) -> Dictionary:
	if bids.is_empty():
		return {"ok": false, "code": NO_BIDS}

	var best_id := ""
	var best_bid := -1.0
	var eligible_seen := false

	# Ties need a rule that cannot depend on array order, which is upstream
	# state this file has no business inheriting. The first version compared
	# agent_id lexicographically, and in this roster that hands every tie to the
	# same competitor forever, on the strength of how its model family is
	# spelled. Ordering by name is ordering by something that means something.
	#
	# So ties break on a hash, salted from the bid multiset itself -- no extra
	# field crosses the boundary to obtain it. The salt sums QUANTIZED bids
	# because integer addition is associative and float addition is not, and an
	# order-dependent salt would reintroduce exactly the bug being removed.
	var salt := 0
	for entry in bids:
		if typeof(entry) == TYPE_DICTIONARY and entry.has("bid"):
			var q = entry["bid"]
			if (typeof(q) == TYPE_FLOAT or typeof(q) == TYPE_INT) and is_finite(float(q)):
				salt += int(round(float(q) * 1000.0))

	for entry in bids:
		if typeof(entry) != TYPE_DICTIONARY:
			return {"ok": false, "code": MALFORMED_BID}

		# The boundary. Not a filter -- a refusal.
		for k in entry.keys():
			if not ALLOWED_KEYS.has(str(k)):
				return {"ok": false, "code": MALFORMED_BID}
		for k in ALLOWED_KEYS:
			if not entry.has(k):
				return {"ok": false, "code": MALFORMED_BID}

		var id := str(entry["agent_id"])
		if id.strip_edges() == "":
			return {"ok": false, "code": MALFORMED_BID}
		if typeof(entry["eligible"]) != TYPE_BOOL:
			return {"ok": false, "code": MALFORMED_BID}
		if typeof(entry["bid"]) != TYPE_FLOAT and typeof(entry["bid"]) != TYPE_INT:
			return {"ok": false, "code": MALFORMED_BID}

		var b := float(entry["bid"])
		if not is_finite(b) or b < 0.0 or b > 1.0:
			return {"ok": false, "code": MALFORMED_BID}

		# Validated and then deliberately unused. Nothing below this line reads
		# it, which is the whole invariant.
		if typeof(entry["requested_class"]) != TYPE_STRING:
			return {"ok": false, "code": MALFORMED_BID}
		if not CLASSES.has(str(entry["requested_class"])):
			return {"ok": false, "code": MALFORMED_BID}

		if not bool(entry["eligible"]):
			continue
		eligible_seen = true

		if b > best_bid or (b == best_bid and _tie_key(id, salt) < _tie_key(best_id, salt)):
			best_bid = b
			best_id = id

	if not eligible_seen:
		return {"ok": false, "code": NO_ELIGIBLE_BIDS}
	return {"ok": true, "agent_id": best_id}


## FNV-1a, written out rather than borrowed, so the tiebreak cannot change
## underneath this file when an engine hash implementation does.
static func _tie_key(id: String, salt: int) -> int:
	var h := 2166136261
	for byte in (id + ":" + str(salt)).to_utf8_buffer():
		h = (h ^ int(byte)) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	return h
