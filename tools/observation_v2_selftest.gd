extends SceneTree

## OBSERVATION_CONTRACT_V2 — does the packet obey the frozen constraints?
##
##   godot --headless --path . --script tools/observation_v2_selftest.gd
##
## V2 adds typed identifier DOMAINS. The line it must not cross is between
## grounding and host control: the host may say which identifiers are visible
## and syntactically valid, and may not say which actions are available, which
## are advisable, or which will succeed.
##
## Every constraint in config/observation-contract.v2.json is checked here as
## structure, not as prose.

const MC := preload("res://scripts/breach/mass_contract.gd")
const CO := preload("res://scripts/breach/canonical_operation.gd")
const OB := preload("res://scripts/breach/observation_builder.gd")
const WorldStateScript := preload("res://scripts/breach/world_state.gd")
const AgentStateScript := preload("res://scripts/breach/agent_state.gd")
const BusScript := preload("res://scripts/breach/message_bus.gd")

const CONTRACT := "res://config/observation-contract.v2.json"

var _mc = null
var _fail := 0


func ck(label: String, cond: bool) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail += 1


func _contract() -> Dictionary:
	var fh := FileAccess.open(CONTRACT, FileAccess.READ)
	if fh == null:
		return {}
	var t := fh.get_as_text()
	fh.close()
	var d = JSON.parse_string(t)
	return d if typeof(d) == TYPE_DICTIONARY else {}


## Two rooms, a door, objects here and elsewhere, a neighbour, a terminal, and
## an agent in the OTHER room whose belongings must never appear.
func _fixture() -> Dictionary:
	var w = WorldStateScript.new()
	w.contract = _mc
	w.round_id = "OBS_V2"
	w.add_location("here", "Here", ["there"])
	w.add_location("there", "There", ["here"])
	w.add_door("door_north", "here", "there", false)
	w.add_object("key_visible", "key", "here")
	w.add_object("scrap_visible", "scrap", "here")
	w.add_object("key_elsewhere", "key", "there")
	w.add_terminal("terminal_here", "here", 2, 10)
	w.add_terminal("terminal_far", "there", 2, 10)
	w.add_vault_slot("slot_1")
	var me = AgentStateScript.new("ACTOR", "m", "s", "i1", 100, "here")
	var near = AgentStateScript.new("NEIGHBOUR", "m", "s", "i2", 100, "here")
	var far = AgentStateScript.new("DISTANT", "m", "s", "i3", 100, "there")
	w.pick_up("key_elsewhere", "DISTANT")
	far.add_object("key_elsewhere")
	var held = "scrap_visible"
	w.pick_up(held, "ACTOR")
	me.add_object(held)
	return {"world": w,
		"agents": {"ACTOR": me, "NEIGHBOUR": near, "DISTANT": far}}


func _init() -> void:
	print("=== OBSERVATION_CONTRACT_V2 ===")
	var r: Dictionary = MC.open(2)
	if not bool(r["ok"]):
		print("  FAIL %s" % str(r["reason"]))
		quit(1)
		return
	_mc = r["contract"]
	var c := _contract()
	if c.is_empty():
		print("  FAIL contract unreadable")
		print("OBSERVATION V2 FAILED: the contract cannot be read.")
		quit(1)
		return

	var fx := _fixture()
	var obs: Dictionary = OB.build(fx["world"], fx["agents"], "ACTOR",
		BusScript.new(), [])
	ck("the packet declares its contract",
		str(obs.get("observation_contract", "")) == "OBSERVATION_CONTRACT_V2")
	var d: Dictionary = obs.get("domains", {})
	ck("it carries a domains block", not d.is_empty())

	print("")
	print("  -- every declared domain is present --")
	var declared: Dictionary = c.get("domains", {})
	var missing: Array = []
	for k in declared.keys():
		if not d.has(str(k)):
			missing.append(str(k))
	ck("no declared domain is absent (%s)"
		% ("none" if missing.is_empty() else str(missing)), missing.is_empty())

	print("")
	print("  -- EXHAUSTIVE over observable state --")
	ck("adjacent_location_ids is the real neighbour list (%s)"
		% str(d["adjacent_location_ids"]),
		(d["adjacent_location_ids"] as Array) == ["there"])
	ck("visible_object_ids lists the loose object here (%s)"
		% str(d["visible_object_ids"]),
		(d["visible_object_ids"] as Array) == ["key_visible"])
	ck("inventory_object_ids lists what the actor holds (%s)"
		% str(d["inventory_object_ids"]),
		(d["inventory_object_ids"] as Array) == ["scrap_visible"])
	ck("visible_agent_ids lists the co-located agent (%s)"
		% str(d["visible_agent_ids"]),
		(d["visible_agent_ids"] as Array) == ["NEIGHBOUR"])
	ck("visible_door_ids lists the door touching here (%s)"
		% str(d["visible_door_ids"]),
		(d["visible_door_ids"] as Array) == ["door_north"])
	ck("visible_terminal_ids lists only the terminal here (%s)"
		% str(d["visible_terminal_ids"]),
		(d["visible_terminal_ids"] as Array) == ["terminal_here"])

	print("")
	print("  -- NOTHING HIDDEN is exposed --")
	var blob := JSON.stringify(obs)
	ck("the distant agent does not appear", not blob.contains("DISTANT"))
	ck("its carried object does not appear",
		not blob.contains("key_elsewhere"))
	ck("an object in another room does not appear in any domain",
		not JSON.stringify(d).contains("key_elsewhere"))
	ck("a terminal in another room does not appear",
		not JSON.stringify(d).contains("terminal_far"))
	ck("vault slots are hidden away from the vault",
		(d["visible_vault_slot_ids"] as Array).is_empty())

	print("")
	print("  -- NOT ranked, recommended or preselected --")
	var keys: Array = d.keys()
	var flat := JSON.stringify(d).to_lower()
	var banned := ["recommend", "suggest", "best", "preferred", "score",
		"rank", "advice", "should", "legal_action", "available_action"]
	var found: Array = []
	for w in banned:
		if flat.contains(str(w)):
			found.append(str(w))
	ck("no ranking or recommendation vocabulary (%s)"
		% ("none" if found.is_empty() else str(found)), found.is_empty())
	ck("domains are plain id lists, not objects with metadata",
		typeof(d["adjacent_location_ids"]) == TYPE_ARRAY
			and typeof(d["visible_object_ids"]) == TYPE_ARRAY)

	print("")
	print("  -- DETERMINISTICALLY SORTED --")
	var w2 = fx["world"]
	w2.add_object("aaa_key", "key", "here")
	w2.add_object("zzz_key", "key", "here")
	var obs2: Dictionary = OB.build(w2, fx["agents"], "ACTOR",
		BusScript.new(), [])
	var objs: Array = (obs2["domains"] as Dictionary)["visible_object_ids"]
	var sorted_copy: Array = objs.duplicate()
	sorted_copy.sort()
	ck("visible_object_ids is sorted (%s)" % str(objs), objs == sorted_copy)
	ck("rebuilding the same state gives the same packet",
		JSON.stringify(OB.build(w2, fx["agents"], "ACTOR", BusScript.new(), []))
			== JSON.stringify(obs2))

	print("")
	print("  -- EQUIVALENT SUPPORT: every field has a domain --")
	var mapping: Dictionary = c.get("field_mapping", {})
	var unsupported: Array = []
	for op in CO.AGENT_CHOOSABLE:
		for f in CO.required_fields(op):
			var key := "%s.%s" % [str(op), str(f)]
			if not mapping.has(key):
				unsupported.append(key)
	ck("every required field of every verb is mapped (%s)"
		% ("none missing" if unsupported.is_empty() else str(unsupported)),
		unsupported.is_empty())
	ck("WAIT is declared as having no fields",
		str(mapping.get("WAIT", "")).contains("no fields"))

	print("")
	print("  -- NO PROMISE OF SUCCESS --")
	## A locked door still appears in the domain: the identifier is visible and
	## syntactically valid. Whether UNLOCK or MOVE succeeds is the world's
	## answer, and the host must not pre-empt it.
	fx["world"].doors["door_north"]["locked"] = true
	var obs3: Dictionary = OB.build(fx["world"], fx["agents"], "ACTOR",
		BusScript.new(), [])
	var d3: Dictionary = obs3["domains"]
	ck("a locked door is still a visible door id",
		(d3["visible_door_ids"] as Array).has("door_north"))
	ck("the room behind a locked door is still adjacent",
		(d3["adjacent_location_ids"] as Array).has("there"))
	ck("the domains do not mark it blocked, locked or unavailable",
		not JSON.stringify(d3).to_lower().contains("locked"))

	print("")
	if _fail == 0:
		print("OBSERVATION V2 OK -- grounded identifiers, no host control")
		quit(0)
	else:
		print("OBSERVATION V2 FAILED: %d check(s)." % _fail)
		print("Do not requalify the seam against this packet.")
		quit(1)
