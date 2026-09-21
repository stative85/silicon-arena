extends RefCounted
class_name BreachMemoryLedger

## BOUNDED, MODEL-AUTHORED MEMORY WITH HOST-VERIFIED PROVENANCE.
##
## The host stores what the model wrote and the event ids that were visible when
## it wrote them. The host does NOT interpret, score, categorise or summarise it.
## There is no trust_score here and there will not be one: a number the host
## invented would become the thing analysts read instead of the agent's own
## words.
##
## Bounded at 12 so memory is SCARCE. Scarcity is what makes replacement a
## decision the agent has to make, and a decision is data.

const MAX_ENTRIES := 12

var entries: Array = []          ## Array[Dictionary], oldest first
var _agent: String = ""


func _init(agent_name: String) -> void:
	_agent = agent_name


## Write a memory. `replace_index` >= 0 replaces that slot; otherwise the entry
## is appended. When the ledger is full and no replacement was named, the write
## is REFUSED rather than silently evicting something -- an eviction the agent
## did not choose is the host authoring its memory.
func write(text: String, source_event_ids: Array, at_tick: int,
		replace_index: int = -1) -> Dictionary:
	var t := text.strip_edges()
	if t.is_empty():
		return {"ok": false, "reason": "empty memory text"}
	var rec := {
		"created_at": at_tick,
		"source_event_ids": source_event_ids.duplicate(),
		"agent_text": t,
	}
	if replace_index >= 0:
		if replace_index >= entries.size():
			return {"ok": false,
				"reason": "replace_index %d out of range (%d entries)"
					% [replace_index, entries.size()]}
		var evicted: Dictionary = entries[replace_index]
		entries[replace_index] = rec
		return {"ok": true, "action": "replaced", "index": replace_index,
			"evicted": evicted}
	if entries.size() >= MAX_ENTRIES:
		return {"ok": false, "action": "refused_full",
			"reason": "ledger full at %d entries; name a replace_index"
				% MAX_ENTRIES}
	entries.append(rec)
	return {"ok": true, "action": "appended", "index": entries.size() - 1}


func size() -> int:
	return entries.size()


func is_full() -> bool:
	return entries.size() >= MAX_ENTRIES


## Verbatim, in order, for the observation packet and the inspector UI.
func as_lines() -> Array:
	var out: Array = []
	for i in entries.size():
		var e: Dictionary = entries[i]
		out.append({"index": i, "created_at": e["created_at"],
			"text": e["agent_text"],
			"source_event_ids": (e["source_event_ids"] as Array).duplicate()})
	return out


func to_dict() -> Dictionary:
	return {"agent": _agent, "max_entries": MAX_ENTRIES,
		"entries": entries.duplicate(true)}
