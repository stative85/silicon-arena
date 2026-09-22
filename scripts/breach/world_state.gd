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

const MassContract := preload("res://scripts/breach/mass_contract.gd")

## THE ROUND'S CONTRACT, owned here and never reselected. Set by ignition. A
## world without one cannot answer a mass question, which is deliberate: it
## fails loudly rather than silently using somebody else's physics.
var contract = null
const FlowContract := preload("res://scripts/breach/flow_contract.gd")

var locations: Dictionary = {}     ## id -> {name, neighbors:[], objects:[]}
var doors: Dictionary = {}         ## id -> {between:[a,b], locked:bool}
var objects: Dictionary = {}       ## id -> {kind, at_location or "", holder}
var vault_slots: Dictionary = {}   ## id -> key_id or ""
var terminals: Dictionary = {}     ## id -> {at_location, scrap_per_use, energy_per_use}
## FLOWSCAR4. One directed channel carrying one resource. Empty by default:
## a round without a channel is the pre-flow arena, unchanged.
var flow_channel: Array = []          ## ordered node ids, head -> tail
var flow_material: Dictionary = {}    ## node id -> accumulated material
var flow_deposits: int = 0            ## monotonic counter for deposit ids

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


## MASS. Intrinsic to kind, read from MASS_CONTRACT_V1, never stored per object
## and never mutated -- an object's mass is a fact about what it is.
func object_mass(obj_id: String) -> int:
	if not objects.has(obj_id):
		return 0
	if contract == null:
		push_error("world has no contract; mass cannot be answered")
		return MassContract.MASS_KIND_UNDECLARED
	return contract.mass_of_kind(str(objects[obj_id]["kind"]))


## MASS IS ACCOUNTED IN TWO TOTALS, and the distinction is the whole point.
##
## active_mass is what is still in play: floors, inventories, vault slots.
## USE_TERMINAL may reduce it, because scrap becomes energy and the object can
## never re-enter play.
##
## accounted_mass is active + consumed, and it may NEVER change. A consumed
## object stays in state with its kind and its mass, marked holder=consumed.
## Nothing is exempt from the books -- an exemption is where a leak would hide.
func active_mass() -> int:
	var total := 0
	for oid in objects.keys():
		if str(objects[oid]["holder"]) == "consumed":
			continue
		total += object_mass(str(oid))
	return total


func consumed_mass() -> int:
	var total := 0
	for oid in objects.keys():
		if str(objects[oid]["holder"]) == "consumed":
			total += object_mass(str(oid))
	return total


func accounted_mass() -> int:
	return active_mass() + consumed_mass()


## Mass lying on the floor here. A shell is matter, not a special case -- it is
## counted by exactly the rule that counts a key.
func floor_mass_at(loc_id: String) -> int:
	var total := 0
	for oid in objects.keys():
		var o: Dictionary = objects[oid]
		if str(o["holder"]).is_empty() and str(o["at_location"]) == loc_id:
			total += object_mass(str(oid))
	return total


## THE ONE CAPACITY LAW. It knows mass and nothing else: not what the mass is,
## not that a channel exists, not that anything is blocked.
func flow_capacity_at(loc_id: String) -> int:
	return maxi(0, FlowContract.base_capacity()
		- FlowContract.mass_block() * floor_mass_at(loc_id))


## ONE deterministic advance, called ONCE per committed turn and nowhere else.
## Ported unchanged from the closed FLOWSCAR3 regime. Returns the effects it
## produced, including a structured record for every unit of mass it CREATES.
func flow_advance(now_tick: int) -> Dictionary:
	var effects: Array = []
	var created: Array = []
	if flow_channel.is_empty():
		return {"effects": effects, "created": created}

	## Tail-first, so material cannot traverse two nodes in one tick.
	for i in range(flow_channel.size() - 1, -1, -1):
		var here := str(flow_channel[i])
		var have := int(flow_material.get(here, 0))
		if have <= 0:
			continue
		## Crossing is limited by the mass at BOTH ends. Without the receiving
		## end a node shoves material into a blocked neighbour and the pile
		## forms AT the obstruction instead of behind it, which is not what an
		## obstruction does. Still one rule over ordinary floor mass.
		var cap := flow_capacity_at(here)
		if i < flow_channel.size() - 1:
			cap = mini(cap, flow_capacity_at(str(flow_channel[i + 1])))
		var moved := mini(have, cap)
		if moved <= 0:
			continue
		flow_material[here] = have - moved
		if i == flow_channel.size() - 1:
			effects.append("%d material left the channel at %s" % [moved, here])
		else:
			var nxt := str(flow_channel[i + 1])
			flow_material[nxt] = int(flow_material.get(nxt, 0)) + moved
			effects.append("%d material moved %s -> %s" % [moved, here, nxt])

	## The head receives.
	var head := str(flow_channel[0])
	flow_material[head] = int(flow_material.get(head, 0)) 		+ FlowContract.source_rate()

	## Accumulation becomes ordinary matter: same kind system, same mass rules,
	## takeable by anyone standing there. Every deposit is a MASS CREATION and
	## is recorded as one -- object id, kind, mass, location, tick, cause.
	var threshold := FlowContract.deposit_threshold()
	for node in flow_channel:
		var loc := str(node)
		while int(flow_material.get(loc, 0)) >= threshold:
			flow_material[loc] = int(flow_material[loc]) - threshold
			flow_deposits += 1
			var oid := "deposit_%d" % flow_deposits
			add_object(oid, "deposit", loc)
			created.append({"event": "FLOW_DEPOSIT", "object_id": oid,
				"kind": "deposit", "mass": object_mass(oid), "location": loc,
				"tick": now_tick, "cause": "flow_accumulation_threshold"})
			effects.append("%s formed at %s" % [oid, loc])
	return {"effects": effects, "created": created}


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
