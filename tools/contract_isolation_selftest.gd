extends SceneTree

## Can two contract versions coexist in one process without contaminating?
##
##   godot --headless --path . --script tools/contract_isolation_selftest.gd
##
## THE BUG THIS EXISTS TO PREVENT, which was real until it was refactored out.
##
## MassContract was a static singleton with a module-level cache, and select()
## mutated it. Two rounds on different contracts in one process then shared
## whichever version was selected LAST. A Step 1B replay running after a
## FLOWSCAR4 round would silently inherit V2 physics -- where death creates a
## shell of mass 8 -- and the signed result would quietly stop being what the
## gate checked. Nothing would look wrong: same code, same file on disk, same
## green output.
##
## A contract is now an immutable object owned by the round that named it. This
## file proves that ownership holds in every order, offline, with no models.

const MC := preload("res://scripts/breach/mass_contract.gd")
const WorldStateScript := preload("res://scripts/breach/world_state.gd")
const AgentStateScript := preload("res://scripts/breach/agent_state.gd")
const BusScript := preload("res://scripts/breach/message_bus.gd")
const Reducer := preload("res://scripts/breach/world_reducer.gd")
const CO := preload("res://scripts/breach/canonical_operation.gd")

var _fail := 0


func ck(label: String, cond: bool) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail += 1


func _open(v: int):
	var r: Dictionary = MC.open(v)
	if not bool(r["ok"]):
		print("  FAIL cannot open v%d: %s" % [v, str(r["reason"])])
		_fail += 1
		return null
	return r["contract"]


## Semantics that must differ between the two versions. If these ever agree,
## the test below proves nothing and says so rather than passing.
func _assert_versions_differ(v1, v2) -> void:
	ck("V1 does not declare 'shell'", not v1.is_declared("shell"))
	ck("V2 declares 'shell' at mass 8",
		v2.is_declared("shell") and v2.mass_of_kind("shell") == 8)
	ck("V1 does not declare 'deposit'", not v1.is_declared("deposit"))
	ck("V2 declares 'deposit' at mass 1",
		v2.is_declared("deposit") and v2.mass_of_kind("deposit") == 1)
	ck("the two versions are genuinely distinguishable",
		v1.is_declared("shell") != v2.is_declared("shell"))


## One death, under one contract. Returns what the world looks like after.
func _death(contract) -> Dictionary:
	var world = WorldStateScript.new()
	world.contract = contract
	world.round_id = "ISOLATION"
	world.add_location("room_a", "Room A", ["room_b"])
	world.add_location("room_b", "Room B", ["room_a"])
	world.add_object("key_1", "key", "room_a")
	var a = AgentStateScript.new("ALPHA", "fixture", "fixture", "fixture#1",
		100, "room_a")
	var agents := {"ALPHA": a}
	var bus = BusScript.new()
	Reducer.apply(world, agents, "ALPHA", CO.TAKE, {"target": "key_1"}, bus)
	a.energy = 4                                   ## exactly one move left
	var r: Dictionary = Reducer.apply(world, agents, "ALPHA", CO.MOVE,
		{"target": "room_b"}, bus)
	var floor_b: Array = world.objects_at("room_b")
	floor_b.sort()
	return {"dead": not a.alive, "shell": r.has("shell_appeared"),
		"floor": floor_b, "capacity": a.capacity_in(world),
		"version": contract.version}


func _init() -> void:
	print("=== CONTRACT ISOLATION -- two versions, one process ===")

	print("")
	print("  -- 1. construct V1 then V2 --")
	var a1 = _open(1)
	var a2 = _open(2)
	if a1 == null or a2 == null:
		quit(1)
		return
	_assert_versions_differ(a1, a2)

	print("")
	print("  -- 2. construct V2 then V1, order reversed --")
	var b2 = _open(2)
	var b1 = _open(1)
	if b1 == null or b2 == null:
		quit(1)
		return
	_assert_versions_differ(b1, b2)
	ck("V1 opened AFTER V2 still refuses 'shell'", not b1.is_declared("shell"))
	ck("V2 opened BEFORE V1 still declares 'shell'", b2.is_declared("shell"))
	ck("the same version yields the same hash in either order",
		a1.sha256 == b1.sha256 and a2.sha256 == b2.sha256)

	print("")
	print("  -- 3. interleaved rounds: V1, V2, V1 again --")
	## The third call is the one that matters. Under the old singleton it would
	## have inherited V2's physics from the call before it.
	var first_v1 := _death(a1)
	var only_v2 := _death(a2)
	var again_v1 := _death(b1)

	ck("V1 death creates NO shell", not bool(first_v1["shell"]))
	ck("V2 death DOES create a shell", bool(only_v2["shell"]))
	ck("V1 death AFTER a V2 death still creates no shell",
		not bool(again_v1["shell"]))
	ck("the two V1 rounds are identical (%s == %s)"
		% [str(first_v1["floor"]), str(again_v1["floor"])],
		first_v1["floor"] == again_v1["floor"])
	ck("the V2 round left a shell on the floor (%s)" % str(only_v2["floor"]),
		(only_v2["floor"] as Array).has("shell_alpha"))
	ck("neither V1 round left a shell anywhere",
		not (first_v1["floor"] as Array).has("shell_alpha")
			and not (again_v1["floor"] as Array).has("shell_alpha"))
	ck("each round reported its own version (%d, %d, %d)"
		% [int(first_v1["version"]), int(only_v2["version"]),
			int(again_v1["version"])],
		int(first_v1["version"]) == 1 and int(only_v2["version"]) == 2
			and int(again_v1["version"]) == 1)

	print("")
	print("  -- 4. refusals never mutate a live contract --")
	var before: bool = a2.is_declared("shell")
	var bad: Dictionary = MC.open(99)
	ck("an unknown version is refused", not bool(bad["ok"]))
	ck("  and names itself (%s)" % str(bad["reason"]).substr(0, 28),
		str(bad["reason"]).begins_with("UNKNOWN_CONTRACT_VERSION"))
	ck("a refusal returns no contract", bad["contract"] == null)
	ck("an existing contract is untouched by someone else's refusal",
		a2.is_declared("shell") == before)

	print("")
	print("  -- 5. immutability is deep, not shallow --")
	var c2a = _open(2)
	var c2b = _open(2)
	ck("two instances of the same version are distinct objects", c2a != c2b)
	var t = c2a.mass_table()
	t["shell"] = 999
	t["smuggled"] = 1
	ck("mutating a handed-out table does not change the contract",
		c2a.mass_of_kind("shell") == 8 and not c2a.is_declared("smuggled"))
	ck("and does not reach the other instance of the same version",
		c2b.mass_of_kind("shell") == 8 and not c2b.is_declared("smuggled"))
	var r1: Dictionary = c2a.raw()
	(r1["mass_by_kind"] as Dictionary)["shell"] = 777
	ck("mutating raw() does not change the contract either",
		c2a.mass_of_kind("shell") == 8)
	var ev: Array = c2a.host_authored_events()
	ev.append("FORGED_EVENT")
	ck("mutating the event list does not change the contract",
		not c2a.host_authored_events().has("FORGED_EVENT"))

	print("")
	print("  -- 6. the contract never enters state or artifacts --")
	var w = WorldStateScript.new()
	w.contract = c2a
	w.round_id = "HASH_CHECK"
	w.add_location("room_a", "Room A", [])
	w.add_object("key_1", "key", "room_a")
	var blob := JSON.stringify(w.to_dict())
	ck("to_dict carries no contract key", not w.to_dict().has("contract"))
	ck("no object identity leaks into the serialised state",
		not blob.contains("BreachMassContract") and not blob.contains("RefCounted"))
	ck("no contract hash is baked into state either (it is provenance)",
		not blob.contains(str(c2a.sha256).substr(0, 16)))
	## Replay reopens by version and refuses on a hash difference; the state
	## itself stays physics, not bookkeeping.
	ck("version and sha are available as provenance when asked",
		c2a.version == 2 and c2a.sha256.length() == 64)

	print("")
	if _fail == 0:
		print("CONTRACT ISOLATION OK -- versions do not contaminate")
		quit(0)
	else:
		print("CONTRACT ISOLATION FAILED: %d check(s)." % _fail)
		print("A round can inherit another round's physics. Do not run")
		print("FLOWSCAR4 and do not trust any replay until this passes.")
		quit(1)
