extends RefCounted
class_name AsyncStepEngine

## THE tick protocol. One implementation, driven by both the calibration and
## the ASYNC-A runner.
##
## GATE 2, in its strongest form. Sharing `AsyncWorld` is necessary but NOT
## sufficient: the calibration already proved that a single `world.advance()`
## in the wrong place manufactures staleness that time could not have caused.
## Two copies of the same call ordering are two dynamical systems waiting to
## drift out of agreement while sharing a class file.
##
## So the question is not "did we write the same sequence twice?" but "are
## there even two sequences to drift?" There are not.
##
## FROZEN PHASE ORDER, per tick T:
##
##   1. collect envelopes releasable at T
##   2. order them according to the timing policy (within-tick ordering)
##   3. apply them to the world
##   4. classify outcomes
##   5. close the corresponding agents
##   6. allow newly free agents to observe
##   7. create and submit envelopes
##   8. advance the world exactly once
##
## Phases 3 and 8 are the pair the calibration failure was about: applying
## BEFORE advancing is what makes a zero-delay action land in the tick it was
## observed. Reversing them re-manufactures the bug.

const W := preload("res://scripts/arena/async_world.gd")
const T := preload("res://scripts/arena/async_timing.gd")

var world: AsyncWorld
var arm: String = ""
var run_start_ms: int = 0

## Envelopes awaiting release: {envelope, release_tick}
var pending: Array = []

## Every applied outcome, in application order. This is the journal.
var journal: Array = []

## Substrate events that are NOT decisions and never enter a denominator.
var no_opportunity: int = 0

## Counters
var contention_opportunity: int = 0
var stale_eligible: int = 0


static func make(w: AsyncWorld, arm_name: String, start_ms: int
		) -> AsyncStepEngine:
	var e := AsyncStepEngine.new()
	e.world = w
	e.arm = arm_name
	e.run_start_ms = start_ms
	return e


## Queue a completed envelope for release at the given tick.
func schedule(env: AsyncEnvelope, release_tick: int) -> void:
	env.release_tick = release_tick
	pending.append(env)


## PHASES 1-4. Returns the envelopes applied this tick, in application order.
##
## `submit_fn` and `observe_fn` are supplied by the caller so the calibration
## can drive synthetic actors and the runner can drive the bridge, WITHOUT
## either owning the phase order.
func step_apply(now_tick: int) -> Array:
	# 1. collect
	var due: Array = []
	var still: Array = []
	for p in pending:
		var env: AsyncEnvelope = p
		if env.release_tick <= now_tick:
			due.append(env)
		else:
			still.append(env)
	pending = still
	if due.is_empty():
		return []

	# 2. order according to the timing policy
	var ordered := T.order_due(arm, due)

	# 3-4. apply and classify
	var applied: Array = []
	for e in ordered:
		var env: AsyncEnvelope = e
		# The evidence must be intact before it is used to judge anything.
		if not env.assert_immutable():
			push_error("envelope mutated before application: " + env.request_id)
		var obs := env.observation()
		# stale_eligible is judged BEFORE applying.
		var r: Dictionary = world.resources.get(env.chosen_target, {})
		if not r.is_empty() and str(r["holder"]) != "" \
				and int(r["invalidated_at_version"]) > int(obs["version"]):
			stale_eligible += 1
		var out := world.apply(env.agent_id, env.chosen_target, obs)
		env.outcome = str(out["outcome"])
		env.stale_revalidated = bool(out.get("stale_revalidated", false))
		env.observation_age_ticks = int(out["observation_age_ticks"])
		env.current_target_generation = int(out.get(
			"current_target_generation", -1))
		env.applied_tick = now_tick
		if not env.assert_immutable():
			push_error("envelope mutated by application: " + env.request_id)
		journal.append(env.to_row())
		applied.append(env)
	return applied


## PHASE 8. Exactly once per tick, after application.
func step_advance() -> Array:
	return world.advance()


## Deterministic identity of everything that happened, in order.
##
## Compared across implementations rather than aggregate rates: two orderings
## can produce the same stale-conflict count while being different histories,
## and an aggregate would not notice.
func journal_hash() -> String:
	var s := ""
	for row in journal:
		var d: Dictionary = row
		s += "%s|%s|%s|%d|%d|%s|%s\n" % [
			str(d["request_id"]), str(d["agent_id"]), str(d["chosen_target"]),
			int(d["applied_tick"]), int(d["observation_age_ticks"]),
			str(d["outcome"]), str(d["stale_revalidated"])]
	return s.sha256_text()


func counts() -> Dictionary:
	var by := {}
	for row in journal:
		var o := str((row as Dictionary)["outcome"])
		by[o] = int(by.get(o, 0)) + 1
	var reval := 0
	for row in journal:
		if bool((row as Dictionary)["stale_revalidated"]):
			reval += 1
	return {
		"actions": journal.size(),
		"by_outcome": by,
		"stale_revalidated": reval,
		"stale_eligible": stale_eligible,
		"contention_opportunity": contention_opportunity,
		"no_opportunity": no_opportunity,
	}
