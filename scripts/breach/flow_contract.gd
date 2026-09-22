extends RefCounted
class_name BreachFlowContract

## FLOW_SCAR_CONTRACT_V1 -- the FLOWSCAR4 regime, read from config, never inlined.
##
## EVERY CONSTANT HERE WAS LIFTED, NOT CHOSEN. They come unchanged from the
## closed FLOWSCAR3 regime in the breach-work tree. FLOW_SOURCE_RATE in
## particular was derived there from a null-stability requirement that existed
## independently of any result, and it does not move if a FLOWSCAR4 run
## disappoints.
##
##     A parameter changed to rescue a hypothesis is not a parameter,
##     it is a conclusion wearing a number.
##
## FLOWSCAR3 IS NOT INHERITED. Its vocabulary has 33 constants including PUSH
## and DRAG, a different observation surface, batteries, capacitors and residue
## traces. This repo's signed ACTION_SCHEMA_V1 has sixteen verbs and no PUSH.
## No FLOWSCAR4 result may be compared with or described as reproducing it.

const PATH := "res://config/flow-scar-contract.v1.json"

static var _cache: Dictionary = {}


static func _load() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var fh := FileAccess.open(PATH, FileAccess.READ)
	if fh == null:
		push_error("FLOW_SCAR_CONTRACT_V1 missing: " + PATH)
		return {}
	var text := fh.get_as_text()
	fh.close()
	var d = JSON.parse_string(text)
	if typeof(d) != TYPE_DICTIONARY:
		push_error("FLOW_SCAR_CONTRACT_V1 is not a JSON object")
		return {}
	_cache = d
	return _cache


static func _const(name: String, fallback: int) -> int:
	var c: Dictionary = _load().get("frozen_constants", {})
	return int(c.get(name, fallback))


static func source_rate() -> int:
	return _const("FLOW_SOURCE_RATE", 2)


static func base_capacity() -> int:
	return _const("FLOW_BASE_CAPACITY", 4)


static func mass_block() -> int:
	return _const("FLOW_MASS_BLOCK", 1)


static func deposit_threshold() -> int:
	return _const("FLOW_DEPOSIT_THRESHOLD", 6)


static func shell_mass() -> int:
	return _const("SHELL_MASS", 8)


static func channel() -> Array:
	var ch: Dictionary = _load().get("channel", {})
	return (ch.get("topology", []) as Array).duplicate()


static func null_ticks() -> int:
	var n: Dictionary = _load().get("null_stability_bar", {})
	return int(n.get("ticks", 200))


static func rounds() -> int:
	return int((_load().get("run_budget", {}) as Dictionary).get("rounds", 0))


static func ticks_per_round() -> int:
	return int((_load().get("run_budget", {}) as Dictionary)
		.get("ticks_per_round", 0))


## Host-authored event names, as DATA. The gate asserts these against the
## canonical vocabulary directly; nothing reads the prose.
static func host_events() -> Array:
	var h: Dictionary = _load().get("host_events", {})
	var out: Array = []
	for k in h.keys():
		if typeof(h[k]) == TYPE_DICTIONARY:
			out.append(str(k))
	out.sort()
	return out


## Which host events CREATE mass. The ledger check uses this to know which
## transitions are permitted to move accounted_mass at all.
static func mass_creating_events() -> Array:
	var h: Dictionary = _load().get("host_events", {})
	var out: Array = []
	for k in h.keys():
		if typeof(h[k]) != TYPE_DICTIONARY:
			continue
		if bool((h[k] as Dictionary).get("creates_mass", false)):
			out.append(str(k))
	out.sort()
	return out


static func salvage_is_out() -> bool:
	var sv: Dictionary = _load().get("salvage", {})
	return str(sv.get("status", "")).begins_with("OUT")
