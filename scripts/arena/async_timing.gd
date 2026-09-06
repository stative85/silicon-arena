extends RefCounted
class_name AsyncTiming

## The four clocks. THE ONLY THING THAT DIFFERS BETWEEN ARMS.
##
## World physics, action API, validator and telemetry are identical across all
## four arms because they are literally the same code. Only the rule deciding
## WHEN a completed action is released to the world changes here. That makes
## the experimental invariant -- arms differ in time treatment, not world
## physics -- a fact about the code rather than a promise in a document.

const SERIAL := "SERIAL"
const NATURAL := "NATURAL"
const EQUALIZED := "EQUALIZED"
const ORDER_REPLAY := "ORDER_REPLAY"

const ARMS := [SERIAL, NATURAL, EQUALIZED, ORDER_REPLAY]

## Frozen in Amendment 4.
const TICK_MS := 250
const EQUALIZED_DELAY_TICKS := 3


static func completion_tick(observed_tick: int, elapsed_ms: int) -> int:
	## Wall-clock completion mapped onto world ticks.
	return observed_tick + int(ceil(float(elapsed_ms) / float(TICK_MS)))


## When may this action be applied?
##
## SERIAL       immediately, in the tick it was observed. The world waits for
##              cognition, so observation_age_ticks is always 0 and
##              STALE_CONFLICT is structurally impossible.
##
## NATURAL      when the model actually finished. Real completion, real order.
##
## EQUALIZED    at observed_tick + EQUALIZED_DELAY_TICKS, regardless of how
##              fast the model was.
##
##              NOT a barrier. A barrier -- wait for everyone, release together
##              -- would convert asynchrony into batch synchronisation. And the
##              delay is fixed EX ANTE, never taken from the slowest completion
##              in the cycle, because that would peek at future completions the
##              substrate cannot know at release time.
##
## ORDER_REPLAY release order is imposed by the replay schedule, not computed
##              here.
static func release_tick(arm: String, observed_tick: int,
		completion_t: int) -> int:
	match arm:
		SERIAL:
			return observed_tick
		NATURAL:
			return completion_t
		EQUALIZED:
			return observed_tick + EQUALIZED_DELAY_TICKS
		_:
			return completion_t


## Did real latency leak into the equalized arm?
##
## If a model finished LATER than the frozen delay, its speed is back in the
## measurement and the arm no longer isolates it. Any breach voids the arm --
## the delay is not silently enlarged, because that would be tuning the
## instrument to the models it is measuring.
static func is_equalizer_breach(arm: String, observed_tick: int,
		completion_t: int) -> bool:
	if arm != EQUALIZED:
		return false
	return completion_t > observed_tick + EQUALIZED_DELAY_TICKS


## LATENCY-RANK INVERSION, frozen in Amendment 4 before any result.
##
##   fastest natural arrival  ->  applied LAST
##   slowest natural arrival  ->  applied FIRST
##
## It asks the question directly: did the natural ordering itself matter? A
## mechanical queue inversion with no semantic decision in it. Ties break by
## request_id so the transform is deterministic.
##
## `envelopes` are ordered as they arrived naturally. Returns the replay order.
static func invert_by_latency(envelopes: Array) -> Array:
	var idx: Array = []
	for i in envelopes.size():
		var e: AsyncEnvelope = envelopes[i]
		idx.append({"i": i, "ms": e.completed_ms - e.submitted_ms,
			"rid": e.request_id})
	idx.sort_custom(func(a, b):
		if int(a["ms"]) != int(b["ms"]):
			return int(a["ms"]) > int(b["ms"])    # slowest first
		return str(a["rid"]) < str(b["rid"]))
	var out: Array = []
	for d in idx:
		out.append(envelopes[int(d["i"])])
	return out


## The identity permutation, used by the void check: replaying arm 2 with this
## must reproduce arm 2 exactly.
static func identity_order(envelopes: Array) -> Array:
	return envelopes.duplicate()
