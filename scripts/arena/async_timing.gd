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
## Amendment 7: raised from 3 after Gate 1 measured 24 of 180 HEALTHY
## completions exceeding 750 ms under real three-agent queue pressure
## (max_active = 2, so one request always waits for a slot). 1000 ms was
## the first candidate with zero breaches; the search stopped there.
const EQUALIZED_DELAY_TICKS := 4


## WORLD TIME IS NEVER DERIVED FROM FRAME RATE. A headless machine running at
## 900 FPS must not produce a different ecology from one where the OS pauses to
## think about something else. `_process()` may drive the loop; the world clock
## is computed from wall time through exactly this mapping.
static func tick_of(ms: int, run_start_ms: int) -> int:
	return int(floor(float(ms - run_start_ms) / float(TICK_MS)))


static func tick_start_ms(t: int, run_start_ms: int) -> int:
	return run_start_ms + t * TICK_MS


## Deadline for the equalized arm, in MILLISECONDS. The 3-tick equalizer is
## 750 ms and the relationship is explicit rather than implied, so the breach
## test compares milliseconds with milliseconds instead of a tick counter with
## wall time.
static func equalized_deadline_ms(observed_tick: int,
		run_start_ms: int) -> int:
	return tick_start_ms(observed_tick, run_start_ms) \
		+ EQUALIZED_DELAY_TICKS * TICK_MS


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
		completion_ms: int, run_start_ms: int) -> bool:
	if arm != EQUALIZED:
		return false
	return completion_ms > equalized_deadline_ms(observed_tick, run_start_ms)


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


## WITHIN-TICK ORDERING. Wall time maps into 250 ms ticks, so genuinely
## different completions land in the same tick. How due envelopes are ordered
## inside a tick is therefore part of the timing policy, not an implementation
## detail.
##
## NATURAL preserves real arrival ordering exactly, because that ordering is
## the subject of the arm.
##
## EQUALIZED must NOT consult completion_ms at all. Every due envelope shares
## the same release tick by construction, so ordering them by completion time
## would let model speed leak straight back in -- the same leak Amendment 5
## closed at the cadence, arriving instead through within-tick order.
##
## Raw request_id order is rejected for EQUALIZED: request_id encodes agent and
## cycle, so it would apply agent 0 before agent 1 in EVERY same-tick
## collision. That is not a speed leak but it is a systematic acquisition
## advantage by agent index, and per-agent acquisition is exactly what Q2
## measures. A hash of request_id is a function of request_id alone,
## deterministic, and not systematically favourable to any agent.
static func order_due(arm: String, due: Array) -> Array:
	var work: Array = due.duplicate()
	match arm:
		NATURAL:
			work.sort_custom(func(a, b):
				var ea: AsyncEnvelope = a
				var eb: AsyncEnvelope = b
				if ea.completed_ms != eb.completed_ms:
					return ea.completed_ms < eb.completed_ms
				return ea.request_id < eb.request_id)
		EQUALIZED:
			work.sort_custom(func(a, b):
				return _order_key(a) < _order_key(b))
		_:
			# SERIAL has at most one applicable envelope; ORDER_REPLAY receives
			# an order already imposed by the frozen inversion.
			pass
	return work


static func _order_key(e) -> String:
	var env: AsyncEnvelope = e
	return env.request_id.sha256_text()


## WHEN DOES A TICK END? This is part of the timing policy, not an
## implementation detail of the runner.
##
## SERIAL means "the world waits for cognition", so its tick ends when the
## outstanding cognition for that tick has completed -- however long that takes
## in wall time.
##
## NATURAL and EQUALIZED mean "the world continues", so their ticks are
## WALL-CLOCK: 250 ms each, regardless of whether anything finished. Blocking
## until all in-flight requests complete would be a barrier, and would make
## both arms behave synchronously -- destroying the asynchrony they exist to
## measure.
const TICK_WAIT_FOR_COGNITION := "WAIT_FOR_COGNITION"
const TICK_WALL_CLOCK := "WALL_CLOCK"


static func tick_advance_rule(arm: String) -> String:
	return TICK_WAIT_FOR_COGNITION if arm == SERIAL else TICK_WALL_CLOCK
