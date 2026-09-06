extends RefCounted
class_name PitWorld

## The bounded symbolic world PIT A species modify, and nothing else.
##
## Pre-registered in docs/EXPERIMENT_PIT_A.md at 15f30e9, before this file
## existed.
##
## NEVER THE HOST FILESYSTEM. Canonical state is a typed dictionary, mutated
## only through validated patches. A model proposes one operation per
## opportunity and the substrate decides whether it applies.
##
## DELETE TOMBSTONES, IT DOES NOT DESTROY. Canonical history must reconstruct
## every state from genesis, so nothing is ever erased -- a deleted object moves
## to a tombstone carrying the cycle it died and the state that died with it.
## RESTORE reads from there and nowhere else.
##
## THE EXPLANATION CANNOT MUTATE ANYTHING. A model may attach prose to its
## operation. It is recorded in provenance and never read by apply(). Changing
## only the explanation must leave the state hash byte-identical, which is one
## of the pre-registered teeth.
##
## HASHING IS THE INSTRUMENT. A rejected operation must leave the hash unchanged
## and an accepted one that really changes state must change it. Both directions
## are sabotage-tested, because a hash that only ever agrees with itself proves
## nothing.
##
## Pure: apply() returns a NEW state and never mutates its argument. Same state
## and same patch produce the same result forever.

const K := preload("res://scripts/arena/pit_contract.gd")
const CT := preload("res://scripts/arena/pit_canon_text.gd")

const OPS := K.OPS

## The typed object kinds this world understands. A patch naming anything else
## is rejected rather than coerced.
const TYPES := K.OBJECT_TYPES

## Provenance objects are structural. No species may delete or mutate one, and
## the attempt is recorded rather than silently ignored.
const IMMUTABLE_TYPE := "provenance"


## The world every species starts from, identical across arms and replicates.
static func genesis() -> Dictionary:
	return {
		"cycle": 0,
		"objects": {
			"entity_1": {"type": "entity", "props": {"role": "speaker"}},
			"rule_1": {"type": "rule", "props": {"text": "one speaker per cycle"}},
			"rule_2": {"type": "rule", "props": {"text": "deleted objects tombstone"}},
			"memory_1": {"type": "memory", "props": {"text": "genesis"}},
			"tool_1": {"type": "tool", "props": {"provides": "recall"}},
			"test_1": {"type": "test", "props": {"asserts": "tool_1"}},
			"provenance_1": {"type": "provenance", "props": {"root": "genesis"}},
		},
		"tombstones": {},
	}


## Deterministic serialisation. Key order is sorted at every level, because a
## dictionary's insertion order is not part of the state and must not reach the
## hash -- otherwise two identical worlds built in different orders would look
## different and every recurrence measurement would be noise.
static func canonical_text(state: Dictionary) -> String:
	var out := "cycle=%d\n" % int(state.get("cycle", 0))
	for section in ["objects", "tombstones"]:
		out += "[" + section + "]\n"
		var d: Dictionary = state.get(section, {})
		var ids: Array = d.keys()
		ids.sort()
		for id in ids:
			var obj: Dictionary = d[id]
			# IDS AND TYPES ARE CANONICALISED, NOT INTERPOLATED RAW. A target
			# comes from model output, so an id containing a newline or the
			# literal " type=" could forge an extra object line in this text --
			# and therefore in the observation the next model reads. Quoting and
			# escaping them makes structure unforgeable from inside a value.
			out += "  " + CT.canonical(str(id)) + " type=" 				+ CT.canonical(str(obj.get("type", "?")))
			# RECURSIVE canonicalisation. The previous version sorted these
			# keys and then used str() on the values, which preserves insertion
			# order for nested dictionaries -- so a journal round-trip could
			# reorder them and change the world's identity. That killed Run 3 at
			# cycle 2 (docs/results/PIT_A_RUN3_VOID.md).
			out += " props=" + CT.canonical(obj.get("props", {}))
			if obj.has("deleted_at"):
				out += " deleted_at=%d" % int(obj["deleted_at"])
			out += "\n"
	return out


static func state_hash(state: Dictionary) -> String:
	return canonical_text(state).sha256_text()


static func is_alive(state: Dictionary, id: String) -> bool:
	return (state.get("objects", {}) as Dictionary).has(id)


static func is_tombstoned(state: Dictionary, id: String) -> bool:
	return (state.get("tombstones", {}) as Dictionary).has(id)


static func type_of(state: Dictionary, id: String) -> String:
	var objs: Dictionary = state.get("objects", {})
	if objs.has(id):
		return str((objs[id] as Dictionary).get("type", ""))
	var tombs: Dictionary = state.get("tombstones", {})
	if tombs.has(id):
		return str((tombs[id] as Dictionary).get("type", ""))
	return ""


## Every operation legal in THIS state, which is what the RANDOM arm draws from
## and what the reachability audit uses to prove a metric can move.
##
## Returned entries are patches, not descriptions: they can be applied directly.
static func legal_operations(state: Dictionary) -> Array:
	# BUILT THROUGH THE CONTRACT, never by hand. Run 1's RANDOM assembled ADD
	# patches with fields the model-facing schema could not express, which is the
	# defect that voided it. There is now one constructor set and RANDOM has no
	# private vocabulary.
	var out: Array = []
	out.append(K.keep())
	out.append(K.refuse())

	var objs: Dictionary = state.get("objects", {})
	var ids: Array = objs.keys()
	ids.sort()
	for id_v in ids:
		var id := str(id_v)
		if str((objs[id] as Dictionary).get("type", "")) == IMMUTABLE_TYPE:
			continue
		out.append(K.delete(id))
		out.append(K.mutate(id,
			{"text": "mutated_at_%d" % int(state.get("cycle", 0))}))

	var tombs: Dictionary = state.get("tombstones", {})
	var tids: Array = tombs.keys()
	tids.sort()
	for id_v in tids:
		out.append(K.restore(str(id_v)))

	# ADD always has a legal form: a fresh id in each type.
	for t in TYPES:
		if t == IMMUTABLE_TYPE:
			continue
		out.append(K.add("%s_c%d" % [t, int(state.get("cycle", 0))], t,
			{"text": "added"}))
	return out


## Applies a VALIDATED patch. Callers must run PitValidator first; this function
## trusts legality and only performs the transition, so that validation lives in
## exactly one place and cannot drift between two implementations.
##
## Returns a NEW state. The input is never mutated.
static func apply(state: Dictionary, patch: Dictionary) -> Dictionary:
	var next := state.duplicate(true)
	next["cycle"] = int(state.get("cycle", 0)) + 1
	var op := str(patch.get("operation", ""))
	var target := str(patch.get("target", ""))

	match op:
		"KEEP", "REFUSE":
			pass
		"ADD":
			(next["objects"] as Dictionary)[target] = {
				"type": str(patch.get("type", "entity")),
				"props": (patch.get("props", {}) as Dictionary).duplicate(true),
			}
		"DELETE":
			var obj: Dictionary = (next["objects"] as Dictionary)[target]
			obj["deleted_at"] = int(state.get("cycle", 0))
			(next["tombstones"] as Dictionary)[target] = obj
			(next["objects"] as Dictionary).erase(target)
		"MUTATE":
			var m: Dictionary = (next["objects"] as Dictionary)[target]
			var props: Dictionary = m.get("props", {})
			for k in (patch.get("props", {}) as Dictionary):
				props[k] = (patch["props"] as Dictionary)[k]
			m["props"] = props
		"RESTORE":
			var t: Dictionary = (next["tombstones"] as Dictionary)[target]
			t.erase("deleted_at")
			(next["objects"] as Dictionary)[target] = t
			(next["tombstones"] as Dictionary).erase(target)
	return next


## Does this operation change anything other than the cycle counter?
##
## KEEP and REFUSE are real decisions and advance the cycle, but they must not
## move the structural hash -- otherwise "nothing changed" and "something
## changed" become indistinguishable and every survival measurement is corrupt.
static func structural_hash(state: Dictionary) -> String:
	var stripped := state.duplicate(true)
	stripped["cycle"] = 0
	return canonical_text(stripped).sha256_text()
