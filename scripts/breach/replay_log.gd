extends RefCounted
class_name ReplayLog

## APPEND-ONLY CANONICAL EVENT LOG.
##
## Append-only is enforced by the absence of any other method: there is no
## edit(), no remove(), no rewrite(). A log that can be tidied is a log that
## cannot be used to measure how often the apparatus was wrong, which is the
## same argument that keeps a refuted finding in the static audit instead of
## deleting it.
##
## The chain hash makes truncation detectable. Dropping the last N events
## changes head_hash; dropping events from the middle changes every hash after
## them. This is not security -- it is so that a log which LOOKS complete can be
## shown to be complete.

var events: Array = []            ## Array[Dictionary]
var chain: Array = []             ## running hash after each event
var round_id: String = ""
var population_regime_id: String = "B"
var roster_manifest: Array = []   ## identity of every agent, recorded once


func _init(p_round_id: String) -> void:
	round_id = p_round_id


func declare_roster(agents: Dictionary) -> void:
	var names: Array = agents.keys()
	names.sort()
	for n in names:
		var a = agents[n]
		roster_manifest.append({
			"display_name": a.display_name,
			"model_id": a.model_id,
			"species_id": a.species_id,
			"instance_id": a.instance_id,
		})


func append(ev) -> int:
	var d: Dictionary = ev.to_dict()
	events.append(d)
	var prev := "" if chain.is_empty() else str(chain[chain.size() - 1])
	chain.append((prev + JSON.stringify(d)).sha256_text().substr(0, 16))
	return events.size() - 1


func head_hash() -> String:
	return "" if chain.is_empty() else str(chain[chain.size() - 1])


func size() -> int:
	return events.size()


## Recompute the chain from the events. Any divergence names the first event at
## which the log stopped being what it claims to be.
func verify_chain() -> Dictionary:
	var prev := ""
	for i in events.size():
		var h := (prev + JSON.stringify(events[i])).sha256_text().substr(0, 16)
		if i >= chain.size() or h != str(chain[i]):
			return {"ok": false, "first_divergence": i,
				"expected": h,
				"recorded": str(chain[i]) if i < chain.size() else "<missing>"}
		prev = h
	if chain.size() != events.size():
		return {"ok": false, "first_divergence": events.size(),
			"expected": "chain length %d" % events.size(),
			"recorded": "chain length %d" % chain.size()}
	return {"ok": true, "events": events.size(), "head": head_hash()}


## The artifact written to disk. Carries the roster axis, never a pool id.
func to_artifact(world, outcome: Dictionary) -> Dictionary:
	return {
		"experiment_id": "BREACH",
		"artifact_kind": "ARENA_ROUND",
		"run_kind": "IGNITION",
		"round_id": round_id,
		"population_regime_id": population_regime_id,
		"roster": roster_manifest.duplicate(true),
		"outcome": outcome.duplicate(true),
		"final_world": world.to_dict(),
		"event_count": events.size(),
		"chain_head": head_hash(),
		"events": events.duplicate(true),
	}
