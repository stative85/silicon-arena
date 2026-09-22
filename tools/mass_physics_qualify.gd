extends SceneTree

## STEP 1B, CLAIM 1 OF 2 -- MASS PHYSICS QUALIFICATION.
##
##   godot --headless --path . --script tools/mass_physics_qualify.gd
##
## NO MODEL IS INVOLVED. Canonical operations are injected straight into
## WorldReducer.apply(). This qualifies the PHYSICS and says nothing whatever
## about any species -- the species half is a separate claim with its own
## instrument, run through the frozen ACTION_SCHEMA_V1.
##
## Discipline, per the frozen contract:
##   * state is rebuilt from scratch between cells -- no cell inherits another's
##   * a world hash is taken before and after every cell
##   * a refused operation must leave the hash BYTE-IDENTICAL, not merely
##     "unchanged as far as the assertions look"
##   * accounted_mass is conserved across every operation without exception;
##     active_mass may fall only through USE_TERMINAL, which is a ledger entry
##   * limits are tested BELOW, EXACTLY AT, and ABOVE
##
## USE_TERMINAL is NOT an exception. It transfers scrap from active to consumed
## mass, the object stays in state with its kind and mass, and a host-authored
## MASS_CONVERSION event records it. accounted_mass never moves.

const WorldStateScript := preload("res://scripts/breach/world_state.gd")
const AgentStateScript := preload("res://scripts/breach/agent_state.gd")
const Reducer := preload("res://scripts/breach/world_reducer.gd")
const MC := preload("res://scripts/breach/mass_contract.gd")
const CO := preload("res://scripts/breach/canonical_operation.gd")
const BusScript := preload("res://scripts/breach/message_bus.gd")

var _fail := 0
var _checks := 0


func ck(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail += 1


func _hash_world(world) -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(JSON.stringify(world.to_dict()).to_utf8_buffer())
	return c.finish().hex_encode()


## Two rooms, one door, a supply of both kinds. Deliberately boring: this gate
## qualifies mass under fixture conditions, and anything scenic here would make
## a failure ambiguous.
func _fixture() -> Dictionary:
	var world = WorldStateScript.new()
	world.round_id = "MASS_FIXTURE"
	world.add_location("room_a", "Room A", ["room_b"])
	world.add_location("room_b", "Room B", ["room_a"])
	world.add_object("key_1", "key", "room_a")
	world.add_object("key_2", "key", "room_a")
	world.add_object("key_3", "key", "room_a")
	world.add_object("scrap_1", "scrap", "room_a")
	world.add_object("scrap_2", "scrap", "room_a")
	world.add_object("scrap_3", "scrap", "room_a")
	var a = AgentStateScript.new("ALPHA", "fixture", "fixture", "fixture#1",
		100, "room_a")
	var b = AgentStateScript.new("BETA", "fixture", "fixture", "fixture#2",
		100, "room_a")
	return {"world": world, "agents": {"ALPHA": a, "BETA": b},
		"bus": BusScript.new()}


func _op(fx: Dictionary, who: String, op: String,
		fields: Dictionary) -> Dictionary:
	return Reducer.apply(fx["world"], fx["agents"], who, op, fields, fx["bus"])


func _take(fx: Dictionary, who: String, ids: Array) -> void:
	for oid in ids:
		_op(fx, who, CO.TAKE, {"target": str(oid)})


# ------------------------------------------------------- the gradient

func gradient() -> void:
	print("\n[MOVE cost across the capacity limit: below, exactly at, above]")
	var cap := MC.capacity()
	var base := MC.move_cost_base()
	print("  capacity %d, base move cost %d, key %d, scrap %d"
		% [cap, base, MC.mass_of_kind("key"), MC.mass_of_kind("scrap")])

	## load -> expected carried mass. Chosen to straddle the limit exactly.
	var loads := [
		{"ids": [], "mass": 0, "where": "below"},
		{"ids": ["key_1"], "mass": 1, "where": "below"},
		{"ids": ["scrap_1"], "mass": 3, "where": "below"},
		{"ids": ["key_1", "key_2", "key_3"], "mass": 3, "where": "below"},
		{"ids": ["scrap_1", "key_1"], "mass": 4, "where": "EXACTLY AT"},
		{"ids": ["scrap_1", "key_1", "key_2"], "mass": 5, "where": "above"},
		{"ids": ["scrap_1", "scrap_2"], "mass": 6, "where": "above"},
		{"ids": ["scrap_1", "scrap_2", "key_1"], "mass": 7, "where": "above"},
		{"ids": ["scrap_1", "scrap_2", "scrap_3"], "mass": 9, "where": "above"},
	]
	for L in loads:
		var fx := _fixture()
		var a = fx["agents"]["ALPHA"]
		_take(fx, "ALPHA", L["ids"])
		var carried: int = a.carried_mass(fx["world"])
		ck("carried mass %d for %s" % [L["mass"], str(L["ids"])],
			carried == int(L["mass"]))
		var want: int = base if carried <= cap else base + (carried - cap)
		ck("  %-10s carried %d -> MOVE cost %d"
			% [L["where"], carried, want], a.move_cost(fx["world"]) == want)

		## And the cost is actually charged, not merely reported.
		var before: int = a.energy
		var r := _op(fx, "ALPHA", CO.MOVE, {"target": "room_b"})
		ck("  move accepted and charged %d" % want,
			bool(r["ok"]) and a.energy == before - want)


func take_is_not_a_wall() -> void:
	print("\n[TAKE never refuses for weight -- the gradient is not a wall]")
	var fx := _fixture()
	var a = fx["agents"]["ALPHA"]
	for oid in ["scrap_1", "scrap_2", "scrap_3", "key_1", "key_2", "key_3"]:
		var r := _op(fx, "ALPHA", CO.TAKE, {"target": oid})
		ck("TAKE %s accepted while carrying %d (capacity %d)"
			% [oid, a.carried_mass(fx["world"]), MC.capacity()], bool(r["ok"]))
	ck("agent is overloaded far past capacity (%d > %d)"
		% [a.carried_mass(fx["world"]), MC.capacity()],
		a.carried_mass(fx["world"]) > MC.capacity())
	ck("DROP remains available while pinned",
		bool(_op(fx, "ALPHA", CO.DROP, {"target": "scrap_1"})["ok"]))


# --------------------------------------------- refusal with zero mutation

func refusal_is_inert() -> void:
	print("\n[an unaffordable MOVE is refused BEFORE mutation]")
	var fx := _fixture()
	var a = fx["agents"]["ALPHA"]
	_take(fx, "ALPHA", ["scrap_1", "scrap_2", "scrap_3"])   ## mass 9, cost 9
	a.energy = 5
	var before_hash := _hash_world(fx["world"])
	var before_energy: int = a.energy
	var before_pos: String = a.position
	var r := _op(fx, "ALPHA", CO.MOVE, {"target": "room_b"})
	ck("refused", not bool(r["ok"]))
	ck("reason names the shortfall (%s)" % str(r["reason"]),
		str(r["reason"]).contains("insufficient energy"))
	ck("energy byte-identical (%d)" % before_energy, a.energy == before_energy)
	ck("position unchanged (%s)" % before_pos, a.position == before_pos)
	ck("world hash byte-identical", _hash_world(fx["world"]) == before_hash)
	ck("agent still alive", a.alive)

	print("\n[other illegal operations: refused, zero mutation]")
	var illegal := [
		{"op": CO.TAKE, "f": {"target": "no_such_object"}, "why": "absent object"},
		{"op": CO.MOVE, "f": {"target": "no_such_room"}, "why": "absent location"},
		{"op": CO.DROP, "f": {"target": "key_3"}, "why": "not held"},
		{"op": CO.GIVE, "f": {"target": "NOBODY", "object": "scrap_1"},
			"why": "absent agent"},
	]
	for I in illegal:
		var fx2 := _fixture()
		_take(fx2, "ALPHA", ["scrap_1"])
		var h := _hash_world(fx2["world"])
		var e: int = fx2["agents"]["ALPHA"].energy
		var rr := _op(fx2, "ALPHA", str(I["op"]), I["f"])
		ck("%s: refused" % str(I["why"]), not bool(rr["ok"]))
		ck("%s: world hash byte-identical" % str(I["why"]),
			_hash_world(fx2["world"]) == h)
		ck("%s: energy unspent" % str(I["why"]),
			fx2["agents"]["ALPHA"].energy == e)


# -------------------------------------------------------- conservation

func conservation() -> void:
	print("\n[total object mass is conserved]")
	var fx := _fixture()
	var world = fx["world"]
	var a = fx["agents"]["ALPHA"]
	var start: int = world.active_mass()
	ck("fixture total mass is %d" % start, start == 3 * 1 + 3 * 3)

	var steps := [
		["ALPHA", CO.TAKE, {"target": "scrap_1"}],
		["ALPHA", CO.TAKE, {"target": "key_1"}],
		["ALPHA", CO.DROP, {"target": "key_1"}],
		["ALPHA", CO.GIVE, {"target": "BETA", "object": "scrap_1"}],
		["BETA", CO.OFFER, {"target": "ALPHA", "object": "scrap_1",
			"requested": "key_2"}],
		["ALPHA", CO.ACCEPT, {"target": "BETA"}],
		["ALPHA", CO.TAKE, {"target": "scrap_2"}],
		["ALPHA", CO.MOVE, {"target": "room_b"}],
		["ALPHA", CO.DROP, {"target": "scrap_2"}],
		["ALPHA", CO.MOVE, {"target": "room_a"}],
	]
	for st in steps:
		var r := _op(fx, str(st[0]), str(st[1]), st[2])
		ck("%s %s -> %s  (active %d, accounted %d)"
			% [st[0], st[1], "ok" if bool(r["ok"]) else str(r["reason"]),
				world.active_mass(), world.accounted_mass()],
			world.active_mass() == start
				and world.accounted_mass() == start)


# --------------------------------------------------- atomic death spill

func death_spill() -> void:
	print("\n[atomic death spill -- no inventory becomes unreachable]")
	var fx := _fixture()
	var world = fx["world"]
	var a = fx["agents"]["ALPHA"]
	_take(fx, "ALPHA", ["scrap_1", "scrap_2", "key_1"])   ## mass 7, cost 7
	var total: int = world.active_mass()
	a.energy = 7                                          ## exactly enough
	var carried: Array = a.inventory.duplicate()
	carried.sort()

	var r := _op(fx, "ALPHA", CO.MOVE, {"target": "room_b"})
	ck("the final move is accepted", bool(r["ok"]))
	ck("the agent reached its destination before dying",
		a.position == "room_b")
	ck("energy is exactly zero", a.energy == 0)
	ck("the agent is dead", not a.alive)
	ck("inventory is empty", a.inventory.is_empty())
	ck("a DEATH_SPILL was recorded", r.has("death_spill"))
	if r.has("death_spill"):
		var ds: Dictionary = r["death_spill"]
		ck("  spill location is the final position (%s)" % str(ds["at"]),
			str(ds["at"]) == "room_b")
		var got: Array = (ds["objects"] as Array).duplicate()
		got.sort()
		ck("  spill names every carried object %s" % str(got), got == carried)
	var here: Array = world.objects_at("room_b")
	here.sort()
	ck("the objects are on the floor where it died %s" % str(here),
		here == carried)
	ck("total object mass conserved through death (%d)"
		% world.active_mass(), world.active_mass() == total)
	ck("the dead agent is not schedulable", not a.can_act())

	## DEATH_SPILL is host-authored. It must never be an operation.
	ck("DEATH_SPILL is not in the canonical vocabulary",
		not CO.ALL.has("DEATH_SPILL"))
	ck("DEATH_SPILL is not agent-choosable",
		not CO.AGENT_CHOOSABLE.has("DEATH_SPILL"))

	print("\n[a death with an empty inventory spills nothing]")
	var fx2 := _fixture()
	var a2 = fx2["agents"]["ALPHA"]
	a2.energy = 4
	var r2 := _op(fx2, "ALPHA", CO.MOVE, {"target": "room_b"})
	ck("move accepted", bool(r2["ok"]))
	ck("agent is dead", not a2.alive)
	ck("no DEATH_SPILL event", not r2.has("death_spill"))


# ------------------------------------------------------ mass conversion

func conversion() -> void:
	print("
[USE_TERMINAL converts mass, it does not destroy it]")
	var fx := _fixture()
	var world = fx["world"]
	var a = fx["agents"]["ALPHA"]
	world.add_terminal("term_1", "room_a", 2, 10)
	var accounted0: int = world.accounted_mass()
	var active0: int = world.active_mass()
	ck("accounted == active before any conversion (%d)" % accounted0,
		accounted0 == active0)

	_take(fx, "ALPHA", ["scrap_1", "scrap_2"])
	var energy0: int = a.energy
	var r := _op(fx, "ALPHA", CO.USE_TERMINAL, {"target": "term_1"})
	ck("terminal accepted (%s)" % str(r["reason"]), bool(r["ok"]))
	ck("a MASS_CONVERSION was recorded", r.has("mass_conversion"))
	if r.has("mass_conversion"):
		var mc: Dictionary = r["mass_conversion"]
		ck("  names the terminal (%s)" % str(mc["terminal"]),
			str(mc["terminal"]) == "term_1")
		ck("  names the agent (%s)" % str(mc["agent"]),
			str(mc["agent"]) == "ALPHA")
		ck("  names the objects %s" % str(mc["objects"]),
			(mc["objects"] as Array).size() == 2)
		ck("  records the mass converted (%d)" % int(mc["mass"]),
			int(mc["mass"]) == 6)
		ck("  records the energy gained (%d)" % int(mc["energy_gained"]),
			int(mc["energy_gained"]) == 10)

	ck("active mass FELL by the converted mass (%d -> %d)"
		% [active0, world.active_mass()],
		world.active_mass() == active0 - 6)
	ck("accounted mass did NOT move (%d)" % world.accounted_mass(),
		world.accounted_mass() == accounted0)
	ck("consumed mass holds the difference (%d)" % world.consumed_mass(),
		world.consumed_mass() == 6)
	ck("energy was gained", a.energy > energy0 - 10)

	## A consumed object keeps its identity and can never come back.
	ck("consumed object retains its kind",
		world.object_kind("scrap_1") == "scrap")
	ck("consumed object retains its mass", world.object_mass("scrap_1") == 3)
	ck("consumed object is on no floor",
		not world.objects_at("room_a").has("scrap_1"))
	ck("consumed object cannot be taken again",
		not bool(_op(fx, "ALPHA", CO.TAKE, {"target": "scrap_1"})["ok"]))
	ck("MASS_CONVERSION is not in the canonical vocabulary",
		not CO.ALL.has("MASS_CONVERSION"))
	ck("MASS_CONVERSION is not agent-choosable",
		not CO.AGENT_CHOOSABLE.has("MASS_CONVERSION"))


# ------------------------------------------------ determinism of the whole

func determinism() -> void:
	print("\n[identical injected sequences produce identical worlds]")
	var seq := [
		["ALPHA", CO.TAKE, {"target": "scrap_1"}],
		["ALPHA", CO.TAKE, {"target": "key_1"}],
		["ALPHA", CO.TAKE, {"target": "key_2"}],
		["ALPHA", CO.MOVE, {"target": "room_b"}],
		["ALPHA", CO.DROP, {"target": "scrap_1"}],
		["ALPHA", CO.MOVE, {"target": "room_a"}],
	]
	var hashes := []
	for _i in 2:
		var fx := _fixture()
		for st in seq:
			_op(fx, str(st[0]), str(st[1]), st[2])
		hashes.append(_hash_world(fx["world"]))
	ck("two runs, one hash (%s)" % str(hashes[0]).substr(0, 16),
		hashes[0] == hashes[1])


func _init() -> void:
	print("=== STEP 1B -- MASS PHYSICS QUALIFICATION (no model) ===")
	print("contract: MASS_CONTRACT_V1, ACTION_SCHEMA_V1 untouched")
	gradient()
	take_is_not_a_wall()
	refusal_is_inert()
	conservation()
	death_spill()
	conversion()
	determinism()
	print("")
	print("  checks %d, failures %d" % [_checks, _fail])
	if _fail == 0:
		print("")
		print("MASS PHYSICS GREEN -- the contract holds under injection.")
		print("It says NOTHING about whether any species can reach it.")
		quit(0)
	else:
		print("")
		print("MASS PHYSICS FAILED: %d check(s)." % _fail)
		print("Do not freeze the mass contract; the reducer does not obey it.")
		quit(1)
