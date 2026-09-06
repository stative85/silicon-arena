extends RefCounted
class_name AsyncWorld

## The ASYNC-A world. Substrate-owned, deterministic, minimal.
##
## THIS IS THE ONLY WORLD IMPLEMENTATION. Calibration and all four ASYNC-A arms
## run this exact code. Calibrating a different world than the one measured is
## worthless, and the pre-registration makes that a void condition.
##
## The world is deliberately not clever. ASYNC-A is about timing, not strategy:
##
##   resources      r_00 .. r_(K-1), each held by at most one agent
##   action         TAKE <id>, or PASS
##   hold           a taken resource returns to the pool after H ticks
##   regeneration   substrate-owned and deterministic, never model-chosen
##
## RESOURCE IDENTITY IS (id, generation), NOT id. Regeneration creates a
## classic ABA problem: a resource observed free, taken by someone else,
## then released, is free again under the same id -- so an aged action
## would succeed and nothing would record that it acted on a dead
## instance of reality. An identifier is not an identity. `generation`
## increments on release, so an observation carries the instance it saw.
##
## VERSIONING IS THE INSTRUMENT. Every state change increments `version`, and
## each resource records the version at which it was most recently invalidated
## (taken). That record is what lets a stale action be distinguished from a
## hallucinated one after the fact, rather than by guessing at intent.

const ACCEPTED := "ACCEPTED"
const STALE_CONFLICT := "STALE_CONFLICT"
const CONTENTION_LOST := "CONTENTION_LOST"
const SEMANTIC_INVALID := "SEMANTIC_INVALID"
const SHAPE_FAILED := "SHAPE_FAILED"
const PASSED := "PASSED"

const PASS_TARGET := "__PASS__"

var resource_count: int = 12
var hold_ticks: int = 6

var tick: int = 0
var version: int = 0

## id -> {holder, taken_at_tick, invalidated_at_version}
var resources: Dictionary = {}


static func make(count: int, hold: int) -> AsyncWorld:
	var w := AsyncWorld.new()
	w.resource_count = count
	w.hold_ticks = hold
	w.reset()
	return w


func reset() -> void:
	tick = 0
	version = 0
	resources = {}
	for i in resource_count:
		resources["r_%02d" % i] = {
			"holder": "", "taken_at_tick": -1,
			"invalidated_at_version": -1, "generation": 0,
		}


func valid_targets() -> Array:
	var out: Array = []
	var ids: Array = resources.keys()
	ids.sort()
	for id in ids:
		if str((resources[id] as Dictionary)["holder"]) == "":
			out.append(id)
	return out


## What an agent sees, and everything needed to judge its action later.
##
## `valid_targets` is RETAINED on the observation rather than recomputed at
## application time. Recomputing would destroy the only evidence that
## distinguishes a stale target from an invented one.
func observe() -> Dictionary:
	var vt := valid_targets()
	var gens := {}
	for id in vt:
		gens[id] = int((resources[id] as Dictionary)["generation"])
	return {
		"tick": tick,
		"version": version,
		"valid_targets": vt,
		"valid_target_generations": gens,
		"hash": canonical_hash(),
	}


func canonical_hash() -> String:
	var s := "tick=%d\n" % tick
	var ids: Array = resources.keys()
	ids.sort()
	for id in ids:
		var r: Dictionary = resources[id]
		s += "%s=%s\n" % [id, str(r["holder"])]
	return s.sha256_text().substr(0, 16)


## Apply one action against the CURRENT world, judged against the observation
## it was formed from.
##
## THE PREDICATE, implemented literally as pre-registered:
##
##   X in observed_valid_targets
##     AND X not in current_valid_targets
##     AND X was invalidated after observation_version
##       => STALE_CONFLICT
##
##   X in observed_valid_targets
##     AND X not in current_valid_targets
##     AND observation_age_ticks == 0
##       => CONTENTION_LOST     simultaneous race, NOT latency evidence
##
##   X not in observed_valid_targets
##       => SEMANTIC_INVALID
##
## Anything else is NOT latency evidence. The third clause is not redundant:
## a resource can be free, taken, released and taken again, and only an
## invalidation recorded AFTER the observation version makes the failure a
## consequence of this action's own latency.
func apply(agent_id: String, target: String, obs: Dictionary) -> Dictionary:
	var out := {
		"agent_id": agent_id, "target": target,
		"applied_tick": tick, "applied_version": version,
		"observation_version": int(obs.get("version", -1)),
		"observation_tick": int(obs.get("tick", -1)),
		"observation_age_ticks": tick - int(obs.get("tick", tick)),
		"observed_target_generation": -1,
		"current_target_generation": -1,
		"invalidated_since_observation": false,
		"revalidated_since_observation": false,
		"stale_revalidated": false,
		"outcome": SEMANTIC_INVALID, "reason": "",
	}
	if target == PASS_TARGET:
		out["outcome"] = PASSED
		return out

	var observed: Array = obs.get("valid_targets", [])
	if not observed.has(target):
		out["reason"] = "target was not valid in the observation"
		return out
	if not resources.has(target):
		out["reason"] = "unknown resource id"
		return out

	var r: Dictionary = resources[target]
	var obs_gens: Dictionary = obs.get("valid_target_generations", {})
	var obs_gen := int(obs_gens.get(target, -1))
	var cur_gen := int(r["generation"])
	var inval_after := int(r["invalidated_at_version"]) > int(obs.get("version", -1))
	out["observed_target_generation"] = obs_gen
	out["current_target_generation"] = cur_gen
	out["invalidated_since_observation"] = inval_after
	out["revalidated_since_observation"] = obs_gen >= 0 and cur_gen > obs_gen

	if str(r["holder"]) == "":
		r["holder"] = agent_id
		r["taken_at_tick"] = tick
		r["invalidated_at_version"] = version + 1
		version += 1
		out["outcome"] = ACCEPTED
		out["applied_version"] = version
		# ABA: the id was free when observed and is free now, but this is a
		# DIFFERENT INSTANCE -- taken and released while the agent was
		# thinking. The action succeeds: the substrate does not rescue the
		# agent and does not reject it either, it records what happened.
		if obs_gen >= 0 and cur_gen > obs_gen:
			out["stale_revalidated"] = true
			out["reason"] = "revalidated: observed generation %d, now %d" % [
				obs_gen, cur_gen]
		return out

	if int(r["invalidated_at_version"]) > int(obs.get("version", -1)):
		# LATENCY EVIDENCE REQUIRES LATENCY. With zero elapsed world-time the
		# agent observed the same world as whoever beat it: that is a
		# simultaneous race, not aged information. The zero-delay control
		# caught this conflation -- the earlier predicate called every
		# same-tick collision a stale conflict.
		if int(out["observation_age_ticks"]) <= 0:
			out["outcome"] = CONTENTION_LOST
			out["reason"] = "simultaneous contention, no world-time elapsed"
			return out
		out["outcome"] = STALE_CONFLICT
		out["reason"] = "invalidated at version %d, observed at %d, aged %d ticks" % [
			int(r["invalidated_at_version"]), int(obs.get("version", -1)),
			int(out["observation_age_ticks"])]
		return out

	# Held, but not invalidated after this observation. Not latency evidence.
	out["reason"] = "target already held before the observation"
	return out


## Substrate-owned regeneration. Deterministic, never model-chosen.
func advance() -> Array:
	tick += 1
	var released: Array = []
	var ids: Array = resources.keys()
	ids.sort()
	for id in ids:
		var r: Dictionary = resources[id]
		if str(r["holder"]) == "":
			continue
		if tick - int(r["taken_at_tick"]) >= hold_ticks:
			r["holder"] = ""
			r["taken_at_tick"] = -1
			# A released resource is a NEW INSTANCE of the same id.
			r["generation"] = int(r["generation"]) + 1
			version += 1
			released.append(id)
	return released


func holdings() -> Dictionary:
	var out := {}
	for id in resources:
		var h := str((resources[id] as Dictionary)["holder"])
		if h != "":
			out[h] = int(out.get(h, 0)) + 1
	return out
