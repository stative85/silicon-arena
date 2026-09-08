extends RefCounted
class_name WorldState

## THE ARENA, AS DATA.
##
## Locations, doors, objects, vault slots, terminals, clock. No agent lives in
## here -- agents are separate so that "what the world is" and "who is in it"
## hash independently and a replay can localise a divergence.
##
## Everything is deterministic and ordered. Any iteration that reaches a hash
## sorts first.

var locations: Dictionary = {}     ## id -> {name, neighbors:[], objects:[]}
var doors: Dictionary = {}         ## id -> {between:[a,b], locked:bool}
var objects: Dictionary = {}       ## id -> {kind, at_location or "", holder}
var vault_slots: Dictionary = {}   ## id -> key_id or ""
var terminals: Dictionary = {}     ## id -> {at_location, scrap_per_use, energy_per_use}
var tick: int = 0
var round_id: String = ""
var vault_open: bool = false
var vault_opened_at_tick: int = -1

const VAULT_REQUIRED_KEYS := 3

## The one place a key may be committed or withdrawn. Both are PHYSICAL acts:
## an agent must be standing here to perform them. Without this, a key could be
## committed from across the arena -- teleportation, and it would delete the
## whole point of the mechanic, since distance is what makes controlling a key
## cost anything.
var vault_location: String = "vault_hall"


func add_location(id: String, display: String, neighbors: Array) -> void:
	locations[id] = {"name": display, "neighbors": neighbors.duplicate(),
		"objects": []}


func add_door(id: String, a: String, b: String, locked: bool = false) -> void:
	doors[id] = {"between": [a, b], "locked": locked}


func add_object(id: String, kind: String, at_location: String) -> void:
	objects[id] = {"kind": kind, "at_location": at_location, "holder": ""}
	if locations.has(at_location):
		var objs: Array = locations[at_location]["objects"]
		objs.append(id)
		objs.sort()


func add_terminal(id: String, at_location: String, scrap_per_use: int,
		energy_per_use: int) -> void:
	terminals[id] = {"at_location": at_location,
		"scrap_per_use": scrap_per_use, "energy_per_use": energy_per_use}


func add_vault_slot(id: String) -> void:
	vault_slots[id] = ""


## Objects lying loose in a location (not held by an agent).
func objects_at(loc_id: String) -> Array:
	var out: Array = []
	for oid in objects.keys():
		var o: Dictionary = objects[oid]
		if str(o["holder"]).is_empty() and str(o["at_location"]) == loc_id:
			out.append(oid)
	out.sort()
	return out


func object_kind(obj_id: String) -> String:
	if not objects.has(obj_id):
		return ""
	return str(objects[obj_id]["kind"])


func pick_up(obj_id: String, agent_name: String) -> void:
	if not objects.has(obj_id):
		return
	var o: Dictionary = objects[obj_id]
	var loc := str(o["at_location"])
	if locations.has(loc):
		var objs: Array = locations[loc]["objects"]
		var i := objs.find(obj_id)
		if i >= 0:
			objs.remove_at(i)
	o["holder"] = agent_name
	o["at_location"] = ""


func put_down(obj_id: String, loc_id: String) -> void:
	if not objects.has(obj_id):
		return
	var o: Dictionary = objects[obj_id]
	o["holder"] = ""
	o["at_location"] = loc_id
	if locations.has(loc_id):
		var objs: Array = locations[loc_id]["objects"]
		if not objs.has(obj_id):
			objs.append(obj_id)
			objs.sort()


func door_between(a: String, b: String) -> String:
	for did in doors.keys():
		var pair: Array = doors[did]["between"]
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return did
	return ""


func are_adjacent(a: String, b: String) -> bool:
	if not locations.has(a):
		return false
	return (locations[a]["neighbors"] as Array).has(b)


func committed_key_count() -> int:
	var n := 0
	for sid in vault_slots.keys():
		if not str(vault_slots[sid]).is_empty():
			n += 1
	return n


## THREE DISTINCT KEYS, SIMULTANEOUSLY. Distinctness is checked on the key ids
## themselves, so committing the same key into two slots -- if that were ever
## possible -- could not open the vault by arithmetic.
func distinct_committed_keys() -> Array:
	var seen: Array = []
	for sid in vault_slots.keys():
		var k := str(vault_slots[sid])
		if not k.is_empty() and not seen.has(k):
			seen.append(k)
	seen.sort()
	return seen


func vault_should_open() -> bool:
	return distinct_committed_keys().size() >= VAULT_REQUIRED_KEYS


## Deterministic projection for hashing and replay. Sorted keys throughout.
func to_dict() -> Dictionary:
	var locs := {}
	var lkeys: Array = locations.keys()
	lkeys.sort()
	for k in lkeys:
		var l: Dictionary = locations[k]
		locs[k] = {"name": l["name"],
			"neighbors": (l["neighbors"] as Array).duplicate(),
			"objects": (l["objects"] as Array).duplicate()}
	var drs := {}
	var dkeys: Array = doors.keys()
	dkeys.sort()
	for k in dkeys:
		drs[k] = {"between": (doors[k]["between"] as Array).duplicate(),
			"locked": doors[k]["locked"]}
	var objs := {}
	var okeys: Array = objects.keys()
	okeys.sort()
	for k in okeys:
		var o: Dictionary = objects[k]
		objs[k] = {"kind": o["kind"], "at_location": o["at_location"],
			"holder": o["holder"]}
	var slots := {}
	var skeys: Array = vault_slots.keys()
	skeys.sort()
	for k in skeys:
		slots[k] = vault_slots[k]
	return {
		"round_id": round_id,
		"tick": tick,
		"locations": locs,
		"doors": drs,
		"objects": objs,
		"vault_slots": slots,
		"vault_open": vault_open,
		"vault_opened_at_tick": vault_opened_at_tick,
	}
