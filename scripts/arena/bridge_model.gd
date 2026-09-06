extends RefCounted
class_name BridgeModel

## One model's residency and health state.
##
##   PARKED -> LOADING -> HOT -> DEGRADED / WEDGED / EVICTED -> RECOVERING
##
## WHY HEALTH IS SEPARATE FROM RESIDENCY. The benchmark found three distinct
## failure modes and the residency check caught exactly one of them:
##
##   evicted     dropped from the resident set        residency CATCHES
##   wedged      loaded, stops responding             residency MISSES
##   degraded    loaded, answers, 50-100x slow        residency MISSES,
##                                                    liveness MISSES TOO
##
## The wedge lines in the raw benchmark read literally
## `missing=none wedged=['h2o']` -- five models present and correct, one of
## them a corpse. And qwen ran 50-100x slow through five consecutive cases
## reporting `fail 0`, because a degraded model answers every request
## successfully. Liveness is not health, so this class tracks both.

const PARKED := "PARKED"
const LOADING := "LOADING"
const HOT := "HOT"
const DEGRADED := "DEGRADED"
const WEDGED := "WEDGED"
const EVICTED := "EVICTED"
const RECOVERING := "RECOVERING"

const STATES := [PARKED, LOADING, HOT, DEGRADED, WEDGED, EVICTED, RECOVERING]

## Which states may accept dispatch. DEGRADED deliberately may not: tolerating
## a 40-second "successful" call is the failure the benchmark documented.
const DISPATCHABLE := [HOT]

var model_id: String = ""
var state: String = PARKED
var loaded_at_ms: int = 0
var last_swap_ms: int = 0
var strikes: int = 0
var in_flight: int = 0

## Rolling demand record for hysteresis: submission times of requests that
## wanted this model while it was not resident.
var demand_ms: Array[int] = []

## Provenance of state changes, so a recovery is never silent.
var transitions: Array = []


static func make(mid: String) -> BridgeModel:
	var m := BridgeModel.new()
	m.model_id = mid
	return m


func set_state(next: String, reason: String, now_ms: int) -> void:
	if not STATES.has(next):
		push_error("unknown bridge model state: " + next)
		return
	if next == state:
		return
	transitions.append({"from": state, "to": next, "reason": reason,
		"at_ms": now_ms})
	state = next
	if next == HOT and loaded_at_ms == 0:
		loaded_at_ms = now_ms


func is_dispatchable() -> bool:
	return DISPATCHABLE.has(state)


func note_demand(now_ms: int, window_ms: int) -> void:
	demand_ms.append(now_ms)
	var cutoff := now_ms - window_ms
	while not demand_ms.is_empty() and demand_ms[0] < cutoff:
		demand_ms.remove_at(0)


func demand_in_window(now_ms: int, window_ms: int) -> int:
	var cutoff := now_ms - window_ms
	var n := 0
	for t in demand_ms:
		if t >= cutoff:
			n += 1
	return n


## Classify one completed request. Returns a verdict dictionary; it does not
## mutate state, because the caller owns transitions and their provenance.
##
## HARD signal is TTFT. The supporting decode-rate signal is only consulted
## when enough tokens exist for the rate to be meaningful -- an 8-token reply
## has a denominator too small to trust, and must never on its own declare a
## model dead.
static func classify(ttft_ms: int, decode_tps: float, tokens: int,
		policy: BridgePolicy) -> Dictionary:
	var hard := ttft_ms > policy.hard_degraded_ttft_ms
	var rate_meaningful := tokens >= policy.min_tokens_for_rate
	var supporting := (rate_meaningful
		and decode_tps > 0.0 and decode_tps < policy.supporting_decode_tps)
	return {
		"hard_degraded": hard,
		"supporting": supporting,
		"rate_meaningful": rate_meaningful,
		"verdict": ("HARD_DEGRADED" if hard
			else ("SUSPECT" if supporting else "HEALTHY")),
	}


## Hysteresis. Promotion requires SUSTAINED demand, never a single request:
## a cold load costs 1.77-8.50 s, so thrashing the resident set would spend
## more than any scheduling gain could recover.
func may_promote(queue_depth: int, oldest_wait_ms: int, now_ms: int,
		policy: BridgePolicy) -> bool:
	if now_ms - last_swap_ms < policy.swap_cooldown_ms:
		return false
	if queue_depth >= policy.promote_queue_depth:
		return true
	if oldest_wait_ms >= policy.promote_wait_ms:
		return true
	return demand_in_window(now_ms, policy.promote_demand_window_ms) \
		>= policy.promote_demand_count


## A model that just arrived stays a while, whatever the queue thinks.
func may_demote(now_ms: int, policy: BridgePolicy) -> bool:
	if in_flight > 0:
		return false
	if loaded_at_ms > 0 and now_ms - loaded_at_ms < policy.min_residency_ms:
		return false
	return now_ms - last_swap_ms >= policy.swap_cooldown_ms
