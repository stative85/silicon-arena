extends RefCounted
class_name BreachMassContract

## MASS_CONTRACT_V1 -- the frozen mass physics, read from config, never inlined.
##
## Mass is INTRINSIC TO OBJECT KIND. Every key weighs the same as every other
## key, always, and no object's mass ever changes. Capacity is IDENTICAL FOR
## EVERY AGENT: there is no species-specific strength, because a host-authored
## strength difference would confound every later species comparison -- it is
## the first entry on the Arena's permanent murder list.
##
## WHY A FILE AND NOT CONSTANTS. The same reason ACTION_SCHEMA_V1 is a file:
## the numbers are evidence. They are hashed into artifacts, and a run that
## used different physics must be impossible to confuse with one that did not.
## tools/mass_contract_selftest.gd is the drift check.
##
## ENCUMBRANCE IS A GRADIENT, NOT A WALL. TAKE never refuses for weight. An
## agent may knowingly overload itself; it pays at MOVE, one extra energy per
## unit over capacity. That is what makes a body that is too heavy to move
## possible, which is the raw material FLOW SCAR needs.

const PATH := "res://config/mass-contract.v1.json"

static var _cache: Dictionary = {}


static func _load() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var fh := FileAccess.open(PATH, FileAccess.READ)
	if fh == null:
		push_error("MASS_CONTRACT_V1 missing: " + PATH)
		return {}
	var text := fh.get_as_text()
	fh.close()
	var d = JSON.parse_string(text)
	if typeof(d) != TYPE_DICTIONARY:
		push_error("MASS_CONTRACT_V1 is not a JSON object")
		return {}
	_cache = d
	return _cache


static func capacity() -> int:
	return int(_load().get("capacity_per_agent", 0))


static func move_cost_base() -> int:
	return int(_load().get("move_cost_base", 4))


## An unknown kind weighs nothing rather than guessing. A kind that reaches the
## world without a declared mass is a contract gap, and the selftest is what
## catches it -- silently inventing a weight here would hide exactly that.
static func mass_of_kind(kind: String) -> int:
	var by: Dictionary = _load().get("mass_by_kind", {})
	return int(by.get(kind, 0))


static func kinds() -> Array:
	var by: Dictionary = _load().get("mass_by_kind", {})
	var out: Array = by.keys()
	out.sort()
	return out


## THE GRADIENT. At or under capacity a move costs the base. Over capacity it
## costs one more per unit of overload, without bound, so an agent can always
## become pinned but never becomes unable to shed.
static func move_cost_for(carried_mass: int) -> int:
	var base := move_cost_base()
	var cap := capacity()
	if carried_mass <= cap:
		return base
	return base + (carried_mass - cap)
