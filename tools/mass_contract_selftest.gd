extends SceneTree

## Does MASS_CONTRACT_V1 still describe the world the reducer runs?
##
##   godot --headless --path . --script tools/mass_contract_selftest.gd
##
## Two jobs, both offline:
##
## 1. DRIFT. The contract is frozen and hashed into artifacts, which is also how
##    it silently stops matching the world. Every object kind that reaches the
##    arena must have a declared mass; no kind may be invented at runtime; the
##    numbers the reducer uses must be the numbers in the file.
##
## 2. INFORMATION SURFACE. Mass added fields to the observation packet. The
##    contract requires four of them to be visible, and requires that another
##    agent's carried mass is visible ONLY when that agent is genuinely
##    observable. A mass field that leaks across rooms would hand every agent a
##    free sensor the physics never gave it, and every later behavioural result
##    would be about that sensor.

const MC := preload("res://scripts/breach/mass_contract.gd")
const WorldStateScript := preload("res://scripts/breach/world_state.gd")
const AgentStateScript := preload("res://scripts/breach/agent_state.gd")
const BusScript := preload("res://scripts/breach/message_bus.gd")
const OB := preload("res://scripts/breach/observation_builder.gd")
const Layout := preload("res://scripts/breach/arena_layout.gd")

const CONTRACT_PATH := "res://config/mass-contract.v1.json"

var _fail := 0


func ck(label: String, cond: bool) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail += 1


func _contract() -> Dictionary:
	var fh := FileAccess.open(CONTRACT_PATH, FileAccess.READ)
	if fh == null:
		return {}
	var t := fh.get_as_text()
	fh.close()
	var d = JSON.parse_string(t)
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _init() -> void:
	print("=== MASS_CONTRACT_V1 vs the world the reducer runs ===")
	var c := _contract()
	if c.is_empty():
		print("MASS CONTRACT DRIFT: the contract is missing or unparseable.")
		print("Do not run the arena against physics that cannot be read.")
		quit(1)
		return

	## The accessors must return the file, not a copy of it that drifted.
	ck("capacity matches the file (%d)" % MC.capacity(),
		MC.capacity() == int(c.get("capacity_per_agent", -1)))
	ck("base move cost matches the file (%d)" % MC.move_cost_base(),
		MC.move_cost_base() == int(c.get("move_cost_base", -1)))
	var by: Dictionary = c.get("mass_by_kind", {})
	var kinds_ok := true
	for k in by.keys():
		if MC.mass_of_kind(str(k)) != int(by[k]):
			kinds_ok = false
	ck("every declared kind's mass matches the file %s" % str(MC.kinds()),
		kinds_ok)

	## THE GRADIENT, checked as arithmetic rather than as prose.
	var cap := MC.capacity()
	var base := MC.move_cost_base()
	var grad_ok := MC.move_cost_for(0) == base \
		and MC.move_cost_for(cap) == base \
		and MC.move_cost_for(cap + 1) == base + 1 \
		and MC.move_cost_for(cap + 7) == base + 7
	ck("cost is flat to capacity then rises one per unit over", grad_ok)

	## EVERY KIND IN THE ACTUAL ARENA IS DECLARED. A kind with no declared mass
	## would weigh nothing, which is a contract gap wearing the costume of a
	## light object.
	var world = WorldStateScript.new()
	Layout.build(world, "DRIFT_CHECK")
	var undeclared: Array = []
	for oid in world.objects.keys():
		var kind := str(world.objects[oid]["kind"])
		if not by.has(kind):
			if not undeclared.has(kind):
				undeclared.append(kind)
	ck("every kind in the built arena has a declared mass (%s)"
		% ("none missing" if undeclared.is_empty() else str(undeclared)),
		undeclared.is_empty())

	## CAPACITY IS NOT PER-SPECIES. The first entry on the murder list.
	var a1 = AgentStateScript.new("A", "m1", "s1", "i1", 50, "x")
	var a2 = AgentStateScript.new("B", "m2", "s2", "i2", 50, "x")
	ck("capacity is identical for two different species",
		a1.capacity() == a2.capacity())
	ck("the contract declares no per-species strength",
		not c.has("capacity_by_species") and not c.has("strength_by_species"))

	## HOST-AUTHORED EVENTS ARE NOT VERBS.
	## Case-insensitive: the contract writes "NOT a verb" for emphasis in one
	## rule and "not a verb" in the other, and a tooth that depends on which is
	## a tooth that bites the prose instead of the physics.
	var ds := str(c.get("death_spill_rule", "")).to_lower()
	var mcv := str(c.get("mass_conversion_event", "")).to_lower()
	ck("the contract states DEATH_SPILL is host-authored and not a verb",
		ds.contains("not a verb") and ds.contains("action_schema_v1"))
	ck("the contract states MASS_CONVERSION is host-authored and not a verb",
		mcv.contains("not a verb") and mcv.contains("action_schema_v1"))

	_observation_surface()

	print("")
	if _fail == 0:
		print("MASS CONTRACT OK -- the frozen physics matches the world")
		quit(0)
	else:
		print("MASS CONTRACT DRIFT: %d check(s) failed." % _fail)
		print("The contract is frozen and the world moved, or the reverse.")
		quit(1)


func _observation_surface() -> void:
	print("")
	print("  -- the observation surface mass added --")
	var world = WorldStateScript.new()
	world.add_location("room_a", "Room A", ["room_b"])
	world.add_location("room_b", "Room B", ["room_a"])
	world.add_object("scrap_1", "scrap", "room_a")
	world.add_object("key_1", "key", "room_a")
	var here = AgentStateScript.new("HERE", "m", "s", "i1", 50, "room_a")
	var also = AgentStateScript.new("ALSO", "m", "s", "i2", 50, "room_a")
	var away = AgentStateScript.new("AWAY", "m", "s", "i3", 50, "room_b")
	var agents := {"HERE": here, "ALSO": also, "AWAY": away}

	## Give the distant agent something heavy. If its burden appears in HERE's
	## packet, mass has become a free long-range sensor.
	world.pick_up("scrap_1", "AWAY")
	away.add_object("scrap_1")

	var bus = BusScript.new()
	var obs: Dictionary = OB.build(world, agents, "HERE", bus, [])
	var me: Dictionary = obs["self"]

	ck("self exposes carry_capacity", me.has("carry_capacity"))
	ck("self exposes carried_mass", me.has("carried_mass"))
	ck("self exposes move_cost", me.has("move_cost"))

	var visible: Array = obs.get("visible_world", [])
	var saw_loose_mass := false
	var saw_away := false
	var saw_also := false
	for v in visible:
		var e: Dictionary = v
		if str(e.get("entity", "")) == "key_1":
			saw_loose_mass = e.has("mass")
		if str(e.get("entity", "")) == "AWAY":
			saw_away = true
		if str(e.get("entity", "")) == "ALSO":
			saw_also = true
	ck("a loose object here exposes its mass", saw_loose_mass)
	ck("a co-located agent is visible", saw_also)

	## THE LEAK CHECK, stated as bytes rather than as structure: the distant
	## agent's name and its cargo must not appear anywhere in the packet.
	var blob := JSON.stringify(obs)
	ck("an agent in another room is not in the packet", not saw_away)
	ck("its name does not appear anywhere in the packet",
		not blob.contains("AWAY"))
	ck("its carried object does not appear anywhere in the packet",
		not blob.contains("scrap_1"))

	## And the co-located one's burden IS visible -- the field exists, it is
	## just bounded by observability.
	world.pick_up("key_1", "ALSO")
	also.add_object("key_1")
	var obs2: Dictionary = OB.build(world, agents, "HERE", bus, [])
	var shown := -1
	for v in obs2.get("visible_world", []):
		var e: Dictionary = v
		if str(e.get("entity", "")) == "ALSO":
			shown = int(e.get("visible_carried_mass", -1))
	ck("a co-located agent's carried mass IS exposed (%d)" % shown, shown == 1)
