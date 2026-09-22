extends SceneTree

## The transactional mass ledger, the async-death guard, and replay idempotence.
##
##   godot --headless --path . --script tools/flow_ledger_selftest.gd
##
## THE INVARIANT, over a whole committed turn -- action, death and its shell,
## and the same-tick flow advance:
##
##     delta accounted_mass == sum of mass named by creation events
##
## Nothing unnamed may move it. The check runs BEFORE the after-state hash, so
## a violating tick can never be hashed, recorded, or followed by another.
##
## Offline. No models, no GPU, no network.

const MC := preload("res://scripts/breach/mass_contract.gd")
const SP := preload("res://scripts/breach/state_profile.gd")
const FC := preload("res://scripts/breach/flow_contract.gd")
const WorldStateScript := preload("res://scripts/breach/world_state.gd")
const AgentStateScript := preload("res://scripts/breach/agent_state.gd")
const BusScript := preload("res://scripts/breach/message_bus.gd")
const Reducer := preload("res://scripts/breach/world_reducer.gd")
const CO := preload("res://scripts/breach/canonical_operation.gd")

var _mc = null
var _fail := 0


func ck(label: String, cond: bool) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail += 1


func _world():
	var w = WorldStateScript.new()
	w.contract = _mc
	w.round_id = "LEDGER"
	## Adjacency is directional in the layout, so neighbours are declared both
	## ways -- an agent that cannot walk the channel cannot die on it.
	w.add_location("west_pipe", "West Pipe", ["commons_north"])
	w.add_location("commons_north", "Commons North",
		["west_pipe", "vault_ring"])
	w.add_location("vault_ring", "Vault Ring", ["commons_north"])
	w.flow_channel = ["west_pipe", "commons_north", "vault_ring"]
	return w


## One committed turn, ledger enforced exactly as breach_round enforces it.
func _turn(world, agents: Dictionary, actor: String, op: String,
		fields: Dictionary, event_id: int) -> Dictionary:
	var before: int = world.accounted_mass()
	var created: Array = []
	var out: Dictionary = Reducer.apply(world, agents, actor, op, fields,
		BusScript.new(), event_id)
	if out.has("shell_appeared"):
		created.append(out["shell_appeared"])
	var fx: Dictionary = world.flow_advance(world.tick)
	for rec in (fx["created"] as Array):
		var r: Dictionary = rec
		r["causing_event_id"] = event_id
		created.append(r)
	var after: int = world.accounted_mass()
	var declared := 0
	var seen := {}
	var dupes: Array = []
	for rec in created:
		var r2: Dictionary = rec
		var oid := str(r2.get("object_id", ""))
		if seen.has(oid):
			dupes.append(oid)
		seen[oid] = true
		declared += int(r2.get("mass", 0))
	world.tick += 1
	return {"ok": dupes.is_empty() and (after - before) == declared,
		"delta": after - before, "declared": declared, "created": created,
		"dupes": dupes, "accepted": bool(out["ok"])}


func _init() -> void:
	print("=== FLOWSCAR4 TRANSACTIONAL LEDGER ===")
	var r: Dictionary = MC.open(2)
	if not bool(r["ok"]):
		print("  FAIL %s" % str(r["reason"]))
		quit(1)
		return
	_mc = r["contract"]

	print("")
	print("  -- 1. quiet ticks move nothing --")
	var w = _world()
	var a = AgentStateScript.new("ALPHA", "f", "f", "f#1", 200, "west_pipe")
	var agents := {"ALPHA": a}
	for i in 3:
		var t: Dictionary = _turn(w, agents, "ALPHA", CO.WAIT, {}, i + 1)
		ck("tick %d: delta %d == declared %d"
			% [i, int(t["delta"]), int(t["declared"])], bool(t["ok"]))

	print("")
	print("  -- 2. a deposit is declared, and sums --")
	## AN UNOBSTRUCTED CHANNEL NEVER DEPOSITS -- that is exactly what null
	## stability proves, and the first draft of this test wrongly expected one.
	## So an obstruction is placed first: mass 8 at the receiving node drops its
	## capacity to 0, nothing crosses, and the head accumulates 2 per tick until
	## it passes the threshold of 6.
	w.add_object("blocker", "shell", "commons_north")
	ck("the obstruction drops the receiving node to zero capacity",
		w.flow_capacity_at("commons_north") == 0)
	## Run until the head crosses the threshold. source 2, threshold 6.
	var made := false
	for i in 12:
		var t: Dictionary = _turn(w, agents, "ALPHA", CO.WAIT, {}, 100 + i)
		if not bool(t["ok"]):
			ck("a deposit tick balances", false)
			made = true
			break
		if not (t["created"] as Array).is_empty():
			var c: Dictionary = (t["created"] as Array)[0]
			ck("deposit declared %s mass %d, delta %d"
				% [str(c["object_id"]), int(c["mass"]), int(t["delta"])],
				int(t["delta"]) == int(c["mass"]))
			ck("  it names its cause and its causing event",
				str(c["cause"]) == "flow_accumulation_threshold"
					and int(c["causing_event_id"]) == 100 + i)
			ck("  and its kind and location",
				str(c["kind"]) == "deposit" and not str(c["location"]).is_empty())
			made = true
			break
	ck("a deposit formed within the window", made)

	print("")
	print("  -- 3. a shell is declared, separately from the spill --")
	var w2 = _world()
	w2.add_object("key_1", "key", "west_pipe")
	var b = AgentStateScript.new("BETA", "f", "f", "f#2", 100, "west_pipe")
	var ag2 := {"BETA": b}
	Reducer.apply(w2, ag2, "BETA", CO.TAKE, {"target": "key_1"},
		BusScript.new(), 1)
	b.energy = 4
	var died: Dictionary = _turn(w2, ag2, "BETA", CO.MOVE,
		{"target": "commons_north"}, 42)
	ck("the agent died", not b.alive)
	ck("the ledger balances on the death tick (delta %d, declared %d)"
		% [int(died["delta"]), int(died["declared"])], bool(died["ok"]))
	var shell_rec := {}
	for rec in (died["created"] as Array):
		if str((rec as Dictionary).get("event", "")) == "SHELL_APPEARED":
			shell_rec = rec
	ck("a SHELL_APPEARED record exists", not shell_rec.is_empty())
	if not shell_rec.is_empty():
		ck("  it declares mass 8", int(shell_rec["mass"]) == 8)
		ck("  it carries causing_event_id 42, never -1",
			int(shell_rec["causing_event_id"]) == 42)
		ck("  it names object, kind, location, tick and cause",
			str(shell_rec["object_id"]) == "shell_beta"
				and str(shell_rec["kind"]) == "shell"
				and str(shell_rec["location"]) == "commons_north"
				and shell_rec.has("tick")
				and str(shell_rec["cause"]) == "energy_exhausted")
	ck("the spilled key created NO mass (it was already in the books)",
		int(died["delta"]) == 8)

	print("")
	print("  -- 4. the ledger BITES on unnamed creation --")
	var w3 = _world()
	var c3 = AgentStateScript.new("GAMMA", "f", "f", "f#3", 100, "west_pipe")
	var ag3 := {"GAMMA": c3}
	var before3: int = w3.accounted_mass()
	## SABOTAGE: matter appears with no creation record behind it.
	w3.add_object("smuggled_1", "scrap", "vault_ring")
	var after3: int = w3.accounted_mass()
	var declared3 := 0
	ck("unnamed matter moves accounted_mass (%d -> %d)"
		% [before3, after3], after3 != before3)
	ck("SABOTAGE BITES: delta %d != declared %d"
		% [after3 - before3, declared3], (after3 - before3) != declared3)

	print("")
	print("  -- 5. a duplicated object id is a violation, not a second unit --")
	var dup := [
		{"event": "FLOW_DEPOSIT", "object_id": "deposit_1", "mass": 1},
		{"event": "FLOW_DEPOSIT", "object_id": "deposit_1", "mass": 1},
	]
	var seen := {}
	var dupes: Array = []
	for rec in dup:
		var oid := str((rec as Dictionary)["object_id"])
		if seen.has(oid):
			dupes.append(oid)
		seen[oid] = true
	ck("a repeated id is detected (%s)" % str(dupes), not dupes.is_empty())

	print("")
	print("  -- 6. replay creates exactly one shell, deterministically --")
	var runs := []
	for i in 2:
		var wr = _world()
		wr.add_object("key_1", "key", "west_pipe")
		var ar = AgentStateScript.new("DELTA", "f", "f", "f#4", 100,
			"west_pipe")
		var agr := {"DELTA": ar}
		Reducer.apply(wr, agr, "DELTA", CO.TAKE, {"target": "key_1"},
			BusScript.new(), 1)
		ar.energy = 4
		_turn(wr, agr, "DELTA", CO.MOVE, {"target": "commons_north"}, 7)
		## A second turn must NOT mint a second shell, and a dead agent is
		## refused anyway -- both guards, not one.
		var second: Dictionary = _turn(wr, agr, "DELTA", CO.WAIT, {}, 8)
		var shells: Array = []
		for oid in wr.objects.keys():
			if str(wr.objects[oid]["kind"]) == "shell":
				shells.append(str(oid))
		shells.sort()
		runs.append({"shells": shells, "second_created":
			(second["created"] as Array).size()})
	ck("exactly one shell exists (%s)" % str(runs[0]["shells"]),
		(runs[0]["shells"] as Array).size() == 1)
	ck("a later turn mints no second shell",
		int(runs[0]["second_created"]) == 0)
	ck("two identical replays agree exactly",
		runs[0]["shells"] == runs[1]["shells"])

	print("")
	print("  -- 7. the sole death path is the actor's own spend --")
	_sole_death_path()

	print("")
	if _fail == 0:
		print("FLOW LEDGER OK -- the books balance and the guards bite")
		quit(0)
	else:
		print("FLOW LEDGER FAILED: %d check(s)." % _fail)
		print("Do not run FLOWSCAR4: mass can move without being named.")
		quit(1)


## THE ASYNC-DEATH GUARD, checked structurally rather than by hoping. The inline
## shell transition is equivalent to FLOWSCAR3's post-action sweep ONLY while no
## non-acting agent can lose energy. If a metabolism or any asynchronous drain
## is introduced, this must fail and stay failing until sweep semantics return.
func _sole_death_path() -> void:
	var sources: Array = ["res://scripts/breach/world_reducer.gd",
		"res://scripts/breach/breach_round.gd",
		"res://scripts/breach/agent_state.gd"]
	var spend_sites: Array = []
	var alive_writes: Array = []
	for path in sources:
		var fh := FileAccess.open(str(path), FileAccess.READ)
		if fh == null:
			continue
		var text := fh.get_as_text()
		fh.close()
		var lines: Array = text.split("\n")
		for i in lines.size():
			var line := str(lines[i]).strip_edges()
			if line.begins_with("#"):
				continue
			if line.contains(".spend(") or line.contains("spend(cost)"):
				spend_sites.append("%s:%d" % [str(path).get_file(), i + 1])
			if line.contains("alive = false") or line.contains("alive=false"):
				alive_writes.append("%s:%d" % [str(path).get_file(), i + 1])
	ck("energy is spent from exactly one site (%s)" % str(spend_sites),
		spend_sites.size() == 1)
	ck("  and that site is inside the reducer",
		spend_sites.size() == 1 and str(spend_sites[0]).begins_with(
			"world_reducer.gd"))
	ck("alive is cleared from exactly one site (%s)" % str(alive_writes),
		alive_writes.size() == 1)
	ck("  and that site is agent_state.spend",
		alive_writes.size() == 1 and str(alive_writes[0]).begins_with(
			"agent_state.gd"))

	## And behaviourally: a bystander never dies while another agent acts.
	var w = _world()
	var actor = AgentStateScript.new("ACTOR", "f", "f", "f#1", 8, "west_pipe")
	var idle = AgentStateScript.new("IDLE", "f", "f", "f#2", 1, "vault_ring")
	var agents := {"ACTOR": actor, "IDLE": idle}
	for i in 3:
		_turn(w, agents, "ACTOR", CO.WAIT, {}, 200 + i)
	ck("a bystander at 1 energy is still alive after the actor's turns",
		idle.alive and idle.energy == 1)
