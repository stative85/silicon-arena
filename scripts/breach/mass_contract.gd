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

## EXPLICIT VERSION SELECTION. There is no "latest".
##
## A runtime that silently loads the newest contract cannot replay an older
## result, and keeping V1 on disk is worthless if nothing can select it. Every
## round NAMES the version it runs under; the file on disk must hash to the
## value recorded in config/contract-registry.json, and a missing, unknown or
## mismatched contract is REFUSED rather than reconciled.
##
## Step 1B was signed against V1. FLOWSCAR4 requires V2, which adds the shell
## and deposit kinds V1 never declared -- under V1 both are
## MASS_KIND_UNDECLARED and ignition refuses, which is the gate working.
const REGISTRY := "res://config/contract-registry.json"

const DEFAULT_VERSION := 2

## AN INSTANCE, NOT A GLOBAL.
##
## This was a static singleton with a module-level cache, and select() mutated
## it. Two rounds on different contracts in one process then shared whichever
## version was selected last: a V1 replay running after a FLOWSCAR4 round would
## silently inherit V2 physics, and the failure would look like a result.
##
## A contract is now an immutable object owned by the round that named it.
## Nothing can reselect it, so nothing can contaminate a neighbour.
var version: int = 0
var sha256: String = ""
var _data: Dictionary = {}


static func _registry() -> Dictionary:
	var fh := FileAccess.open(REGISTRY, FileAccess.READ)
	if fh == null:
		return {}
	var t := fh.get_as_text()
	fh.close()
	var d = JSON.parse_string(t)
	return d if typeof(d) == TYPE_DICTIONARY else {}


static func known_versions() -> Array:
	var reg: Dictionary = _registry().get("mass_contract", {})
	var out: Array = []
	for k in reg.keys():
		out.append(int(str(k)))
	out.sort()
	return out


static func path_for(version: int) -> String:
	var reg: Dictionary = _registry().get("mass_contract", {})
	var e = reg.get(str(version), null)
	if typeof(e) != TYPE_DICTIONARY:
		return ""
	return "res://" + str((e as Dictionary).get("path", ""))


static func expected_sha(version: int) -> String:
	var reg: Dictionary = _registry().get("mass_contract", {})
	var e = reg.get(str(version), null)
	if typeof(e) != TYPE_DICTIONARY:
		return ""
	return str((e as Dictionary).get("sha256", ""))


static func _sha_of(text: String) -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(text.to_utf8_buffer())
	return c.finish().hex_encode()


## THE ONLY WAY TO GET A CONTRACT. Returns
## {"ok": bool, "reason": String, "contract": BreachMassContract or null}.
## Never guesses and never pushes an error: the caller decides what a refusal
## means, and ignition turns it into a refused round.
static func open(version_wanted: int) -> Dictionary:
	var res := {"ok": false, "reason": "", "contract": null}
	var path := path_for(version_wanted)
	if path.is_empty():
		res["reason"] = "UNKNOWN_CONTRACT_VERSION: %d (known: %s)" % [
			version_wanted, str(known_versions())]
		return res
	var fh := FileAccess.open(path, FileAccess.READ)
	if fh == null:
		res["reason"] = "CONTRACT_FILE_MISSING: " + path
		return res
	var text := fh.get_as_text()
	fh.close()
	var sha := _sha_of(text)
	var want := expected_sha(version_wanted)
	if sha != want:
		res["reason"] = "CONTRACT_HASH_MISMATCH v%d: on disk %s, registry %s" 			% [version_wanted, sha.substr(0, 16), want.substr(0, 16)]
		return res
	var d = JSON.parse_string(text)
	if typeof(d) != TYPE_DICTIONARY:
		res["reason"] = "CONTRACT_NOT_AN_OBJECT: " + path
		return res
	var c := new()
	c.version = version_wanted
	c.sha256 = sha
	## DEEP copy. JSON.parse_string already returns a fresh tree, but relying on
	## that makes immutability an accident of the parser rather than a property
	## of this class. Two instances of the same version must not share a nested
	## dictionary that either could mutate.
	c._data = (d as Dictionary).duplicate(true)
	res["ok"] = true
	res["contract"] = c
	return res


# ------------------------------------------------------------- instance API

func capacity() -> int:
	return int(_data.get("capacity_per_agent", 0))


func move_cost_base() -> int:
	return int(_data.get("move_cost_base", 4))


## AN UNDECLARED KIND IS A VIOLATION, NOT A WEIGHT. This returned 0 once. Zero
## is a legitimate mass -- a feather is not a bug -- so a contract gap was
## indistinguishable from a light object and could travel the whole reducer as
## a valid number.
const MASS_KIND_UNDECLARED := -1


## The nested table is never handed out. Callers get scalars or defensive
## copies, so no caller can reach in and change this contract's physics.
func mass_table() -> Dictionary:
	return (_data.get("mass_by_kind", {}) as Dictionary).duplicate(true)


func is_declared(kind: String) -> bool:
	return (_data.get("mass_by_kind", {}) as Dictionary).has(kind)


func mass_of_kind(kind: String) -> int:
	var by: Dictionary = _data.get("mass_by_kind", {})
	if not by.has(kind):
		return MASS_KIND_UNDECLARED
	return int(by[kind])


func kinds() -> Array:
	var out: Array = (_data.get("mass_by_kind", {}) as Dictionary).keys()
	out.sort()
	return out


func raw() -> Dictionary:
	return _data.duplicate(true)


## Host-authored event names, read as DATA. Nothing reads the prose.
func host_authored_events() -> Array:
	var out: Array = (_data.get("host_authored_events", []) as Array).duplicate()
	out.sort()
	return out


## THE GRADIENT. Flat to capacity, then one extra per unit of overload.
func move_cost_for(carried_mass: int) -> int:
	var base := move_cost_base()
	var cap := capacity()
	if carried_mass <= cap:
		return base
	return base + (carried_mass - cap)


## EVERY object, checked before a round may advance. One violation per
## offending object, naming id and kind.
func validate_world(world) -> Array:
	var violations: Array = []
	var ids: Array = world.objects.keys()
	ids.sort()
	for oid in ids:
		var kind := str(world.objects[oid]["kind"])
		if not is_declared(kind):
			violations.append({"violation": "MASS_KIND_UNDECLARED",
				"object": str(oid), "kind": kind})
	return violations
