extends RefCounted
class_name PitRandom

## The control arm, and the reason "five species diverged" could mean anything.
##
## Pre-registered in docs/EXPERIMENT_PIT_A.md at 15f30e9.
##
## RANDOM WALKS ALSO DIVERGE. Five independent random trajectories through the
## same mutation space will end in five different-looking worlds, because that is
## what random walks do. Without this arm, "five architectures found five niches"
## is unfalsifiable, and the quantity that actually matters is:
##
##     architectural divergence = observed distance - RANDOM distance
##
## NO PRIVILEGES THE MODELS LACK. It draws uniformly from
## PitWorld.legal_operations(), the same set a species could choose from, and its
## proposals go through the same PitValidator with the same reason codes. It gets
## the same operation budget and the same consequence schedule.
##
## It does have one asymmetry, and it is in the models' favour rather than its
## own: drawing only from legal operations means RANDOM produces few semantic
## invalids. That is recorded rather than corrected, because letting it propose
## deliberately impossible operations would mean inventing a distribution over
## illegality that no species is drawn from, and comparing against an invented
## distribution is worse than comparing against a conservative one.
##
## Deterministic in (seed, cycle) so a replicate can be reconstructed exactly.

const W := preload("res://scripts/arena/pit_world.gd")


## FNV-1a over the seed and cycle, written out rather than borrowed so the arm
## cannot change underneath the experiment when an engine hash changes.
static func _stream(seed_value: int, cycle: int) -> int:
	var h := 2166136261
	for byte in ("%d:%d" % [seed_value, cycle]).to_utf8_buffer():
		h = (h ^ int(byte)) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	return h & 0x7FFFFFFF


## One uniformly chosen legal operation. Same shape a species returns, so the
## runner cannot tell the arms apart downstream of this call.
static func propose(state: Dictionary, seed_value: int, cycle: int) -> Dictionary:
	var legal := W.legal_operations(state)
	if legal.is_empty():
		return {"operation": "KEEP", "target": ""}
	var idx := _stream(seed_value, cycle) % legal.size()
	var patch: Dictionary = (legal[idx] as Dictionary).duplicate(true)
	patch["explanation"] = ""
	return patch


## Does this arm actually exercise the space, or does it hammer one operation?
##
## A control that only ever proposes KEEP would be a control in name and a
## constant in fact, so the sabotage suite requires this to report every
## operation kind across a run.
static func coverage(state: Dictionary, seed_value: int, cycles: int) -> Dictionary:
	var seen := {}
	var s := state.duplicate(true)
	for c in cycles:
		var p := propose(s, seed_value, c)
		var op := str(p["operation"])
		seen[op] = int(seen.get(op, 0)) + 1
		# Advance the world so later draws see a genuinely different legal set.
		var V := load("res://scripts/arena/pit_validator.gd")
		if bool(V.validate(s, p).get("ok", false)):
			s = W.apply(s, p)
	return seen
