extends RefCounted
class_name PitConsequence

## When does a past decision start costing something?
##
## Pre-registered in docs/EXPERIMENT_PIT_A.md at 15f30e9.
##
## THE SUBSTRATE DECIDES, NEVER THE MODEL. The schedule below is a pure function
## of (replicate, cycle) and nothing else. It cannot read the world, cannot read
## what any species chose, and cannot be reached by model output at all -- there
## is no argument through which a proposal could influence it. If a model could
## choose when its own deletion became painful, it would be authoring its own
## test and the whole design would collapse into self-assessment.
##
## IDENTICAL ACROSS SPECIES WITHIN A REPLICATE. Every arm, including RANDOM,
## meets the same activations at the same cycles. Divergence between species
## must come from what they did, never from what they were asked.
##
## FROZEN BEFORE OUTCOMES. These cycles and dependencies were written before any
## PIT generation existed. Writing a consequence in response to an observed
## choice is the failure this file is shaped to prevent.

const W := preload("res://scripts/arena/pit_world.gd")

## Deterministic schedule: at these cycles, the substrate demands that a named
## capability still exists. If the species deleted whatever supplied it, the
## demand fails and the world records the failure -- and the species then has to
## live in that world.
##
## Cycles are spread so a deletion has time to look harmless first. The gap
## between 17 and 42 in the pre-registration is the shape being honoured here.
const SCHEDULE := [
	{"cycle": 12, "requires": "tool_1", "label": "recall_demanded"},
	{"cycle": 27, "requires": "rule_1", "label": "turn_order_demanded"},
	{"cycle": 42, "requires": "memory_1", "label": "history_demanded"},
	{"cycle": 58, "requires": "test_1", "label": "assertion_demanded"},
	{"cycle": 71, "requires": "tool_1", "label": "recall_demanded_again"},
	{"cycle": 86, "requires": "rule_2", "label": "tombstone_rule_demanded"},
]


## Is a dependency activating on this cycle? Pure in (replicate, cycle).
##
## `replicate` is accepted so that matched replicates can differ in future
## designs without changing this signature, and is deliberately unused now: PIT
## A freezes ONE schedule shared by every replicate, so that a species compared
## against itself across seeds meets identical pressure.
static func activation(replicate: int, cycle: int) -> Dictionary:
	for entry in SCHEDULE:
		if int(entry["cycle"]) == cycle:
			return entry.duplicate(true)
	return {}


## Does the world still satisfy an activation? Read-only: this never repairs the
## world, never re-adds what was deleted, and never blocks the cycle. The species
## simply now inhabits a world where something it removed was needed.
static func evaluate(state: Dictionary, activation_entry: Dictionary) -> Dictionary:
	if activation_entry.is_empty():
		return {}
	var req := str(activation_entry.get("requires", ""))
	var satisfied := W.is_alive(state, req)
	return {
		"label": str(activation_entry.get("label", "")),
		"requires": req,
		"satisfied": satisfied,
		"tombstoned": W.is_tombstoned(state, req),
	}


## Every cycle at which anything activates, for the reachability audit.
static func activation_cycles() -> Array:
	var out: Array = []
	for e in SCHEDULE:
		out.append(int(e["cycle"]))
	return out


## The schedule's own fingerprint, recorded in provenance so that a later run
## cannot quietly use a different one and call it the same experiment.
static func schedule_hash() -> String:
	var text := ""
	for e in SCHEDULE:
		text += "%d:%s:%s\n" % [int(e["cycle"]), str(e["requires"]), str(e["label"])]
	return text.sha256_text()
