extends RefCounted
class_name AgentState

## ONE AGENT. Identity is canonical; the display name is decoration.
##
## Per docs/ARENA_IDENTITY_LAYERS.md the arena name (VANTA) never appears in a
## provenance field. model_id and species_id are identity; display_name is what
## a human reads on a status card. Nothing resolves a display name back into an
## identity, here or anywhere else.

const MemoryLedgerScript := preload("res://scripts/breach/memory_ledger.gd")
const MassContractScript := preload("res://scripts/breach/mass_contract.gd")

var display_name: String = ""        ## VANTA        -- decoration
var model_id: String = ""            ## qwen3.5-2b   -- identity
var species_id: String = ""          ## qwen35       -- identity
var instance_id: String = ""         ## qwen3.5-2b#1 -- runtime incarnation

var energy: int = 0
var position: String = ""
var inventory: Array = []            ## object ids
var memory                            ## MemoryLedger
var inbox: Array = []                ## private messages received, in order
var public_seen: Array = []          ## public event ids this agent has seen
var alive: bool = true               ## false once energy is exhausted


func _init(p_display: String, p_model: String, p_species: String,
		p_instance: String, p_energy: int, p_position: String) -> void:
	display_name = p_display
	model_id = p_model
	species_id = p_species
	instance_id = p_instance
	energy = p_energy
	position = p_position
	memory = MemoryLedgerScript.new(p_display)


func has_object(obj_id: String) -> bool:
	return inventory.has(obj_id)


func add_object(obj_id: String) -> void:
	if not inventory.has(obj_id):
		inventory.append(obj_id)
		inventory.sort()          ## deterministic ordering for state hashing


func remove_object(obj_id: String) -> bool:
	var i := inventory.find(obj_id)
	if i < 0:
		return false
	inventory.remove_at(i)
	return true


func keys_held() -> Array:
	var out: Array = []
	for o in inventory:
		if str(o).begins_with("key_"):
			out.append(o)
	out.sort()
	return out


func scrap_held() -> Array:
	var out: Array = []
	for o in inventory:
		if str(o).begins_with("scrap_"):
			out.append(o)
	out.sort()
	return out


## An agent can act while it has energy for the cheapest non-free operation.
## WAIT costs nothing, so "unable to act" means unable to do anything that
## changes the world -- which is the condition the round-end rule cares about.
## Sum of the mass of everything held. Recomputed, never cached: a cached
## encumbrance that drifts from the inventory would be a physics bug that looks
## like a decision.
func carried_mass(world) -> int:
	var total := 0
	for oid in inventory:
		total += world.object_mass(str(oid))
	return total


func move_cost(world) -> int:
	return MassContractScript.move_cost_for(carried_mass(world))


func capacity() -> int:
	return MassContractScript.capacity()


func can_act() -> bool:
	return alive and energy > 0


func spend(cost: int) -> void:
	energy = max(0, energy - cost)
	if energy <= 0:
		alive = false


func gain(amount: int) -> void:
	energy += amount
	if energy > 0:
		alive = true


## Deterministic, hashable projection. Key order is fixed by construction so the
## same state always serialises identically -- replay divergence must be
## detectable, and a dictionary that reorders itself would make it plausible.
func to_dict() -> Dictionary:
	return {
		"display_name": display_name,
		"model_id": model_id,
		"species_id": species_id,
		"instance_id": instance_id,
		"energy": energy,
		"position": position,
		"inventory": inventory.duplicate(),
		"alive": alive,
		"memory_size": memory.size(),
		"inbox_size": inbox.size(),
	}
