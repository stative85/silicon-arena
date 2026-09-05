extends RefCounted
class_name MetabolismJoin

## The seam between wanting to speak and being able to afford to think.
##
## Pre-registered in docs/EXPERIMENT_METABOLISM.md at 858f1ab.
##
##     local_view -> compute_bid -> requested_class
##                       |
##                 blind resolver picks the speaker
##                       |
##                 compute arbiter
##                       |
##          GRANTED / DOWNGRADED / DENIED -> granted_class -> executor
##
## THE ORDER IS THE INVARIANT. The speaker is chosen before a single byte of
## resource state is consulted, and nothing after that line can revisit it. If
## arbitration could reach back and change who won, compute allocation would
## quietly become a second scheduler -- a semantic one, since the class came
## from the agent's own local pressure. That is the exact failure the blind
## resolver exists to prevent, arriving through the back door.
##
## EXECUTION OBEYS granted_class, NEVER requested_class. An agent asks; the
## world answers; the world's answer is what runs. `execute_class` is derived
## here once, from the arbiter's decision alone, so no caller has to remember
## which of the two fields is authoritative.
##
## NO RESOURCE FEEDBACK IN METABOLISM-A. The outcome is returned for the audit
## layer and is NOT folded into the next local view, the next bid, or the next
## prompt. Teaching an organism that hunger exists is a different experiment
## from proving it has a circulatory system, and running both at once would
## leave neither attributable. tools/lint_locality.py already fails if
## `granted`, `denied` or `downgrade` appear in agent-side code at all.
##
## Pure and total: same inputs, same decision, forever.

const R := preload("res://scripts/arena/swarm_resolver.gd")
const A := preload("res://scripts/arena/compute_arbiter.gd")
const V := preload("res://scripts/arena/vram.gd")

## Nothing executes.
const NOTHING := ""


## Returns the whole per-turn decision, in order, with the speaker fixed before
## resources are consulted.
static func allocate(entries: Array, resident: Array,
		available: Array = A.LADDER,
		params: Dictionary = A.CLASS_PARAMS,
		budget: float = -1.0) -> Dictionary:
	# ---- 1. WHO SPEAKS. Resource state has not been read at this point and
	#         cannot be, because nothing below has run yet.
	var picked: Dictionary = R.resolve(entries)
	if not bool(picked.get("ok", false)):
		return {
			"ok": false,
			"speaker": NOTHING,
			"resolver_code": str(picked.get("code", "?")),
			"requested_class": NOTHING,
			"outcome": NOTHING,
			"granted_class": NOTHING,
			"execute_class": NOTHING,
			"arbiter_code": NOTHING,
		}
	var speaker := str(picked["agent_id"])

	# ---- 2. WHAT DID THE WINNER ASK FOR. A lookup, not a decision.
	var asked := NOTHING
	for e in entries:
		if typeof(e) == TYPE_DICTIONARY and str(e.get("agent_id", "")) == speaker:
			asked = str(e.get("requested_class", ""))
			break

	# ---- 3. WHAT CAN THE WORLD AFFORD. First contact with resource state.
	var verdict: Dictionary = A.arbitrate(asked, resident, available, params,
		budget if budget >= 0.0 else V.DEFAULT_BUDGET_GB)

	# ---- 4. WHAT ACTUALLY RUNS. The arbiter's answer, never the request.
	var runs := NOTHING
	if str(verdict["outcome"]) != A.DENIED:
		runs = str(verdict["granted_class"])

	# `speaker` is carried through untouched from step 1. There is deliberately
	# no branch here that could rewrite it.
	return {
		"ok": true,
		"speaker": speaker,
		"resolver_code": R.OK,
		"requested_class": asked,
		"outcome": str(verdict["outcome"]),
		"granted_class": str(verdict["granted_class"]),
		"execute_class": runs,
		"arbiter_code": str(verdict["code"]),
	}


## Does this turn run a model at all?
static func executes(decision: Dictionary) -> bool:
	return str(decision.get("execute_class", NOTHING)) != NOTHING
