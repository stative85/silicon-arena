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
const CO := preload("res://scripts/breach/canonical_operation.gd")
const WorldStateScript := preload("res://scripts/breach/world_state.gd")
const AgentStateScript := preload("res://scripts/breach/agent_state.gd")
const BusScript := preload("res://scripts/breach/message_bus.gd")
const OB := preload("res://scripts/breach/observation_builder.gd")
const RoundScript := preload("res://scripts/breach/breach_round.gd")
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
	## NO PROSE MATCHING. An earlier version of this file searched the contract's
	## sentences for "not a verb", first case-sensitively and then case-
	## insensitively. Both were tests of the wording: rephrasing a comment could
	## turn the gate green or red without changing one rule of physics.
	##
	## The host-authored event names are now DATA in the contract, and they are
	## asserted directly against the canonical vocabulary.
	var host_events: Array = MC.host_authored_events()
	ck("the contract declares its host-authored events as data %s"
		% str(host_events), not host_events.is_empty())
	for ev in host_events:
		var name := str(ev)
		ck("%s is absent from CO.ALL" % name, not CO.ALL.has(name))
		ck("%s is absent from CO.AGENT_CHOOSABLE" % name,
			not CO.AGENT_CHOOSABLE.has(name))
	## And the events the reducer actually emits are exactly those, no others.
	for name in ["DEATH_SPILL", "MASS_CONVERSION"]:
		ck("%s is declared in host_authored_events" % name,
			host_events.has(name))

	## UNDECLARED KIND IS A VIOLATION, NOT A WEIGHT.
	ck("an undeclared kind returns MASS_KIND_UNDECLARED, not 0",
		MC.mass_of_kind("no_such_kind") == MC.MASS_KIND_UNDECLARED)
	ck("MASS_KIND_UNDECLARED is not a plausible mass",
		MC.MASS_KIND_UNDECLARED < 0)
	ck("is_declared refuses an unknown kind", not MC.is_declared("no_such_kind"))
	ck("is_declared accepts a known kind", MC.is_declared("key"))
	ck("the contract names the policy",
		str(c.get("undeclared_kind_policy", "")) == "MASS_KIND_UNDECLARED")

	_observation_surface()
	_undeclared_kind_sabotage()

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


## SABOTAGE: a world containing an object whose kind has no declared mass.
##
## The offline drift check above proves the CURRENT fixtures are declared. It
## cannot prove that an undeclared kind introduced later would be caught, and
## "would silently weigh zero" was exactly the hole. So a violating world is
## constructed on purpose and the refusal is demonstrated rather than asserted.
func _undeclared_kind_sabotage() -> void:
	print("")
	print("  -- sabotage: an object whose kind has no declared mass --")
	var world = WorldStateScript.new()
	world.add_location("room_a", "Room A", [])
	world.add_object("key_1", "key", "room_a")
	world.add_object("anvil_1", "anvil", "room_a")      ## undeclared kind

	var before := JSON.stringify(world.to_dict())

	var violations: Array = MC.validate_world(world)
	ck("the validator reports a violation", violations.size() == 1)
	if violations.size() == 1:
		var v: Dictionary = violations[0]
		ck("  the violation is MASS_KIND_UNDECLARED",
			str(v["violation"]) == "MASS_KIND_UNDECLARED")
		ck("  it names the object id (%s)" % str(v["object"]),
			str(v["object"]) == "anvil_1")
		ck("  it names the kind (%s)" % str(v["kind"]),
			str(v["kind"]) == "anvil")
	ck("the declared object is not flagged",
		not JSON.stringify(violations).contains("key_1"))
	ck("its mass is the violation sentinel, never 0",
		world.object_mass("anvil_1") == MC.MASS_KIND_UNDECLARED)
	ck("world hash byte-identical after validation",
		JSON.stringify(world.to_dict()) == before)

	## AND THE ROUND MUST REFUSE TO START. A validator nobody calls is not a
	## gate, so this drives the real ignition path.
	var rd = RoundScript.new("SABOTAGE_ROUND", [{
		"display_name": "ALPHA", "model_id": "fixture",
		"species_id": "fixture", "instance_id": "fixture#1"}], {}, 10)
	## The real layout is declared, so the round above starts clean. Inject the
	## violation into its built world and re-validate through the same call the
	## ignition path uses.
	rd.world.add_object("anvil_2", "anvil", rd.world.locations.keys()[0])
	var post: Array = MC.validate_world(rd.world)
	ck("a violation injected into a real built world is caught",
		post.size() == 1 and str(post[0]["kind"]) == "anvil")

	## THE REAL IGNITION PATH, not a simulation of it. A violating world is
	## handed to the round constructor, which must refuse before a tick.
	var sabotaged = WorldStateScript.new()
	sabotaged.add_location("room_a", "Room A", [])
	sabotaged.add_object("key_1", "key", "room_a")
	sabotaged.add_object("anvil_3", "anvil", "room_a")
	var bad = RoundScript.new("SABOTAGE_ROUND_2", [{
		"display_name": "ALPHA", "model_id": "fixture",
		"species_id": "fixture", "instance_id": "fixture#1"}], {}, 10,
		sabotaged)
	ck("_init refused to start the round", bad.ended)
	ck("it recorded the violation", bad.mass_violations.size() == 1)
	ck("the abort reason names the object and the kind (%s)"
		% bad.abort_reason,
		bad.abort_reason.contains("anvil_3") and bad.abort_reason.contains("anvil"))
	var world_before := JSON.stringify(bad.world.to_dict())
	var ev: Dictionary = bad.step()
	ck("step() produces no event once ignition has refused", ev.is_empty())
	ck("no observation was emitted", not ev.has("observation"))
	ck("world hash byte-identical after the refused step",
		JSON.stringify(bad.world.to_dict()) == world_before)
	ck("the end reason is MASS_CONTRACT_VIOLATION, not a round outcome",
		bad.end_reason == RoundScript.END_MASS_CONTRACT_VIOLATION)
