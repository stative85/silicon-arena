extends RefCounted
class_name BreachRoster

## THE CANONICAL ROSTER, READ FROM CONFIG -- NEVER HARDCODED TWICE.
##
## Membership lives in config/arena-species.v1.json and names live in
## config/arena-names.v1.json. This reads both and joins them in the ONE
## permitted direction: identity -> decoration. A missing display name yields
## the raw model_id, ugly and true; it never removes an agent from the roster.
##
## Per docs/ARENA_IDENTITY_LAYERS.md:
##     I-1  decoration cannot change population
##     I-6  an unnamed member renders as its raw id, never a derived one
##
## instance_id encodes the runtime incarnation. Ignition 0 is one instance per
## species, so every instance is "#1" -- but the field exists from the first
## round so that BREACH-4 and BREACH-5 (duplicate populations) do not require a
## schema change to an artifact format that by then has real data in it.

const SPECIES_PATH := "res://config/arena-species.v1.json"
const NAMES_PATH := "res://config/arena-names.v1.json"


static func _read_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(txt) != OK:
		return null
	return j.data


## Returns Array[{display_name, model_id, species_id, instance_id}] in the order
## declared by the species config, or [] on failure. Fails CLOSED: a roster that
## cannot be read is empty, never partially invented.
static func load_roster() -> Array:
	var species = _read_json(SPECIES_PATH)
	if typeof(species) != TYPE_DICTIONARY:
		push_error("BreachRoster: cannot read %s" % SPECIES_PATH)
		return []
	var per := int((species as Dictionary).get("instances_per_species", 0))
	if per != 1:
		push_error("BreachRoster: instances_per_species=%d; Ignition 0 is one instance per species" % per)
		return []

	var name_by_model := {}
	var names = _read_json(NAMES_PATH)
	if typeof(names) == TYPE_DICTIONARY:
		for row in (names as Dictionary).get("names", []):
			var r: Dictionary = row
			name_by_model[str(r["model_id"])] = str(r["display_name"])

	var out: Array = []
	for row in (species as Dictionary).get("species", []):
		var s: Dictionary = row
		var mid := str(s["model_id"])
		out.append({
			"display_name": str(name_by_model.get(mid, mid)),
			"model_id": mid,
			"species_id": str(s["species_id"]),
			"instance_id": mid + "#1",
		})
	return out


## The five distinct species, one instance each, as a sanity assertion the
## caller can make before spending an hour of GPU time.
static func is_ignition_0_shape(roster: Array) -> bool:
	if roster.size() != 5:
		return false
	var species: Array = []
	var models: Array = []
	for r in roster:
		var d: Dictionary = r
		if species.has(d["species_id"]) or models.has(d["model_id"]):
			return false
		species.append(d["species_id"])
		models.append(d["model_id"])
	return true
