extends RefCounted
class_name ComputeArbiter

## Can the world afford the intelligence this agent asked for?
##
## Pre-registered in docs/EXPERIMENT_METABOLISM.md at 858f1ab, amended at
## 0b29e08, both before this file existed.
##
##     requested_class -> arbitrate(resource state) -> GRANTED | DOWNGRADED | DENIED
##
## THE SUBSTRATE HALF OF THE BOUNDARY. This file is allowed to know everything
## about resources -- the parameter ceiling, the catalog, what is resident, the
## budget -- and nothing whatsoever about motive. It never sees the bid, the
## agent's local view, who was named, or what anyone said. It is handed a class
## and a resource state and it does arithmetic.
##
## The agent half is scripts/arena/swarm_request.gd, which sees only its own
## local view and never learns any of this. A denial is the only resource-state
## information that ever travels back, and it arrives after the fact.
##
## DELIBERATELY DUMB, AND IT DOES NOT EVICT. Fitting a grant into free headroom
## or stepping it down is the whole policy. A clever packer that unloaded other
## agents' models to make room would be making a scheduling decision about who
## gets to think, which is exactly the authority this architecture removes from
## the centre. See "statistic 5 is vacuous here" below -- that omission has a
## cost and it is recorded rather than hidden.
##
## PURE. Same inputs, same decision, forever. Reproducible from resource state
## alone, which is one of the pre-registered teeth.

const V := preload("res://scripts/arena/vram.gd")

const SMALL := "SMALL"
const NORMAL := "NORMAL"
const HEAVY := "HEAVY"

## The frozen class-to-hardware mapping. Q4 because that is what this catalog
## actually holds, and the sizes these produce are what make the experiment
## worth running: HEAVY + NORMAL is 7.30 GB against a 6.00 GB budget and simply
## cannot coexist.
const CLASS_PARAMS := {SMALL: 1.5, NORMAL: 4.0, HEAVY: 7.0}
const CLASS_QUANT := "Q4_K_M"

## Downgrade path, strongest first. One step at a time, never a leap to SMALL.
const LADDER := [HEAVY, NORMAL, SMALL]

## Outcomes. Exactly three, and they partition the space -- an outcome that is
## none of them is a silent failure, which is statistic 7.
const GRANTED := "GRANTED"
const DOWNGRADED := "DOWNGRADED"
const DENIED := "DENIED"

## Reasons, describing RESOURCE state and never motive, the same line the
## resolver's failure codes draw.
const OK := "OK"
const INVALID_CLASS := "INVALID_CLASS"
const OVER_PARAM_CEILING := "OVER_PARAM_CEILING"
const MODEL_UNAVAILABLE := "MODEL_UNAVAILABLE"
const NO_CAPACITY := "NO_CAPACITY"


## Resident size in GB for a class.
## `params` is injectable so the ceiling and budget-boundary branches can be
## exercised at all. With the frozen catalog no class exceeds MAX_PARAM_B and no
## resident set lands exactly on the budget, so both branches are unreachable and
## a sabotage of either goes undetected -- which is how they were found.
static func class_gb(cls: String, params: Dictionary = CLASS_PARAMS) -> float:
	if not params.has(cls):
		return V.UNKNOWN
	return V.estimate_gb(float(params[cls]), CLASS_QUANT)


## What the currently loaded set costs. A class already resident is free to use
## again, which is why granting the same class twice does not double-count it.
static func occupancy_gb(resident: Array, params: Dictionary = CLASS_PARAMS) -> float:
	var seen := {}
	var total := 0.0
	for r in resident:
		var cls := str(r)
		if seen.has(cls) or not params.has(cls):
			continue
		seen[cls] = true
		total += class_gb(cls, params)
	return total


## Returns {outcome, granted_class, code, gb, headroom_gb}.
##
## `resident` is the set of classes currently loaded. `available` is the set the
## catalog can actually serve. Both are resource facts; neither has ever been
## seen by the agent that submitted the request.
static func arbitrate(requested_class: String, resident: Array,
		available: Array = LADDER,
		params: Dictionary = CLASS_PARAMS,
		budget: float = V.DEFAULT_BUDGET_GB) -> Dictionary:
	if not params.has(requested_class):
		return _deny(INVALID_CLASS)

	# THE PARAMETER LAW IS CHECKED FIRST, BEFORE ANY MEMORY ARITHMETIC, so that
	# a refusal on the ceiling can never be mistaken for running out of room.
	# An 8B at Q4 is 5.15 GB and fits a 6.00 GB budget; it is still illegal.
	if float(params[requested_class]) > ModelPolicy.MAX_PARAM_B:
		return _deny(OVER_PARAM_CEILING)

	var occupied := occupancy_gb(resident, params)
	var start := LADDER.find(requested_class)
	if start == -1:
		return _deny(INVALID_CLASS)

	for step in range(start, LADDER.size()):
		var cls := str(LADDER[step])
		var downgraded := step > start

		# Never substituted silently: an unavailable class steps DOWN the ladder
		# and the outcome says so, or it is denied. It is never served as though
		# it were what was asked for.
		if not available.has(cls):
			continue

		# A class already resident costs nothing further to use.
		var extra := 0.0 if resident.has(cls) else class_gb(cls, params)
		if occupied + extra <= budget:
			return {
				"outcome": DOWNGRADED if downgraded else GRANTED,
				"granted_class": cls,
				"code": MODEL_UNAVAILABLE if (downgraded and not available.has(
					str(LADDER[start]))) else OK,
				"gb": extra,
				"headroom_gb": budget - (occupied + extra),
			}

	# Nothing on the ladder fits, or nothing below the request is available.
	if not available.has(str(LADDER[start])):
		return _deny(MODEL_UNAVAILABLE)
	return _deny(NO_CAPACITY)


static func _deny(code: String) -> Dictionary:
	return {"outcome": DENIED, "granted_class": "", "code": code,
		"gb": 0.0, "headroom_gb": 0.0}


## Is this a well-formed outcome at all? Statistic 7 counts anything that is
## none of the three, because an unclassified decision is a silent failure and
## this project has paid for that pattern five times.
static func is_classified(out: Dictionary) -> bool:
	var o := str(out.get("outcome", ""))
	return o == GRANTED or o == DOWNGRADED or o == DENIED
