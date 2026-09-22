extends SceneTree

## The leverage gate and the ancestor-removal counterfactual, proven on
## fixtures BEFORE any live result exists.
##
##   godot --headless --path . --script tools/flow_analysis_selftest.gd
##
## Building an analyzer after seeing the shells would let the shells shape the
## instrument that measures them. So every threshold, projection rule and
## verdict path is exercised here, offline, with no models and no GPU.

const FA := preload("res://scripts/breach/flow_analysis.gd")
const MC := preload("res://scripts/breach/mass_contract.gd")
const SP := preload("res://scripts/breach/state_profile.gd")
const FC := preload("res://scripts/breach/flow_contract.gd")
const WorldStateScript := preload("res://scripts/breach/world_state.gd")

var _mc = null
var _profile = null
var _fail := 0


func ck(label: String, cond: bool) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail += 1


func _world_pre(material: Dictionary, floor_mass: Dictionary):
	var w = WorldStateScript.new()
	w.contract = _mc
	w.round_id = "PRE"
	w.add_location("west_pipe", "West Pipe", ["commons_north"])
	w.add_location("commons_north", "Commons North",
		["west_pipe", "vault_ring"])
	w.add_location("vault_ring", "Vault Ring", ["commons_north"])
	w.flow_channel = FC.channel()
	for k in material.keys():
		w.flow_material[str(k)] = int(material[k])
	var n := 0
	for loc in floor_mass.keys():
		## scrap weighs 3; stack enough to reach the requested obstruction.
		var want := int(floor_mass[loc])
		while want >= 3:
			n += 1
			w.add_object("rock_%d" % n, "scrap", str(loc))
			want -= 3
	return w


func _spec() -> Dictionary:
	return {
		"round_id": "FIXTURE",
		"tau": 2,
		"locations": [
			{"id": "west_pipe", "neighbors": ["commons_north"]},
			{"id": "commons_north", "neighbors": ["west_pipe", "vault_ring"]},
			{"id": "vault_ring", "neighbors": ["commons_north"]},
		],
		"objects": [],
		"flow_channel": FC.channel(),
		"agents": [
			{"name": "ALPHA", "at": "west_pipe", "energy": 8},
			{"name": "BETA", "at": "vault_ring", "energy": 100},
		],
	}


## ALPHA moves twice and exhausts (4 energy per move, 8 to start), dying on a
## channel node. BETA idles, so the log is identical in both passes.
func _oplog() -> Array:
	return [
		{"event_id": 1, "tick": 0, "actor": "ALPHA", "operation": "MOVE",
			"fields": {"target": "commons_north"}, "accepted": true},
		{"event_id": 2, "tick": 1, "actor": "BETA", "operation": "WAIT",
			"fields": {}, "accepted": true},
		{"event_id": 3, "tick": 2, "actor": "ALPHA", "operation": "MOVE",
			"fields": {"target": "vault_ring"}, "accepted": true},
		{"event_id": 4, "tick": 3, "actor": "BETA", "operation": "WAIT",
			"fields": {}, "accepted": true},
		{"event_id": 5, "tick": 4, "actor": "BETA", "operation": "WAIT",
			"fields": {}, "accepted": true},
		{"event_id": 6, "tick": 5, "actor": "BETA", "operation": "WAIT",
			"fields": {}, "accepted": true},
	]


func _init() -> void:
	print("=== FLOWSCAR4 ANALYSIS: leverage gate + counterfactual ===")
	var r: Dictionary = MC.open(2)
	if not bool(r["ok"]):
		print("  FAIL %s" % str(r["reason"]))
		quit(1)
		return
	_mc = r["contract"]
	var pr: Dictionary = SP.open("FLOWSCAR4_STATE_V1")
	if not bool(pr["ok"]):
		print("  FAIL %s" % str(pr["reason"]))
		quit(1)
		return
	_profile = pr["profile"]
	var shell_mass: int = FC.shell_mass()
	print("  channel %s, shell mass %d, base capacity %d"
		% [str(FC.channel()), shell_mass, FC.base_capacity()])

	print("")
	print("  -- 1. on-channel shell with pre-treatment leverage --")
	var w1 = _world_pre({"west_pipe": 2, "commons_north": 1}, {})
	var l1: Dictionary = FA.leverage(w1, "commons_north", shell_mass)
	ck("eligible (%s)" % str(l1["reason"]), bool(l1["eligible"]))
	ck("  C0 %d > 0 and C1 %d < C0" % [int(l1["c0"]), int(l1["c1"])],
		int(l1["c0"]) > 0 and int(l1["c1"]) < int(l1["c0"]))
	ck("  supply and receiver both present",
		bool(l1["supply"]) and bool(l1["receiver"]))

	print("")
	print("  -- 2. off-channel shell --")
	var w2 = _world_pre({"west_pipe": 2}, {})
	w2.add_location("store_room", "Store Room", [])
	var l2: Dictionary = FA.leverage(w2, "store_room", shell_mass)
	ck("ineligible (%s)" % str(l2["reason"]), not bool(l2["eligible"]))
	ck("  because it is not on a channel node",
		str(l2["reason"]).contains("not on a channel"))

	print("")
	print("  -- 3. shell arriving after capacity already collapsed --")
	## Floor mass 6 at the node already drives capacity to 0.
	var w3 = _world_pre({"west_pipe": 2}, {"commons_north": 6})
	ck("the node has already collapsed (C %d)"
		% w3.flow_capacity_at("commons_north"),
		w3.flow_capacity_at("commons_north") == 0)
	var l3: Dictionary = FA.leverage(w3, "commons_north", shell_mass)
	ck("ineligible (%s)" % str(l3["reason"]), not bool(l3["eligible"]))
	ck("  because C0 is zero", str(l3["reason"]).contains("C0 is zero"))

	print("")
	print("  -- 3b. no pre-treatment supply --")
	var w3b = _world_pre({}, {})
	var l3b: Dictionary = FA.leverage(w3b, "vault_ring", shell_mass)
	ck("ineligible with no upstream material (%s)" % str(l3b["reason"]),
		not bool(l3b["eligible"]))

	print("")
	print("  -- 4. POSITIVE: removing the ancestor eliminates the difference --")
	var pos: Dictionary = FA.counterfactual(_mc, _profile, _spec(), _oplog(),
		{"agent": "ALPHA", "tau": 2, "causing_event_id": 3})
	ck("status QUALIFIED (%s)" % str(pos["reason"]),
		str(pos["status"]) == FA.QUALIFIED)
	if pos.has("verdict"):
		var v: Dictionary = pos["verdict"]
		ck("  causal hash DIFFERS", bool(v["causal_differs"]))
		ck("  unrelated hash IDENTICAL", bool(v["unrelated_identical"]))
		ck("  complete hash DIFFERS", bool(v["complete_differs"]))
		ck("  treated and counterfactual causal hashes are recorded",
			str(pos["treated"]["causal"]) != str(pos["counterfactual"]["causal"]))

	print("")
	print("  -- 5. NEGATIVE: an ancestor that changes nothing --")
	## BETA never dies, so suppressing BETA's shell is a no-op.
	var neg: Dictionary = FA.counterfactual(_mc, _profile, _spec(), _oplog(),
		{"agent": "BETA", "tau": 2, "causing_event_id": 2})
	ck("status NO_EFFECT (%s)" % str(neg["reason"]),
		str(neg["status"]) == FA.NO_EFFECT)
	ck("  and it is reported, not silently dropped",
		neg.has("verdict") and neg.has("treated"))

	print("")
	print("  -- 6. refusal, never a guess --")
	var bad_anc: Dictionary = FA.counterfactual(_mc, _profile, _spec(),
		_oplog(), {"agent": "ALPHA", "tau": 2, "causing_event_id": 999})
	ck("an ancestor event absent from the oplog is REFUSED",
		str(bad_anc["status"]) == FA.REFUSED)
	ck("  and says why (%s)" % str(bad_anc["reason"]).substr(0, 34),
		str(bad_anc["reason"]).contains("tampered"))
	var no_id: Dictionary = FA.counterfactual(_mc, _profile, _spec(), _oplog(),
		{"agent": "ALPHA", "tau": 2})
	ck("a missing causing_event_id is REFUSED",
		str(no_id["status"]) == FA.REFUSED)
	var no_snap: Dictionary = FA.counterfactual(_mc, _profile, {}, _oplog(),
		{"agent": "ALPHA", "tau": 2, "causing_event_id": 3})
	ck("a missing snapshot is REFUSED",
		str(no_snap["status"]) == FA.REFUSED)
	ck("  and says why (%s)" % str(no_snap["reason"]).substr(0, 30),
		str(no_snap["reason"]).contains("snapshot"))
	var no_anc: Dictionary = FA.counterfactual(_mc, _profile, _spec(),
		_oplog(), {})
	ck("an empty ancestor is REFUSED", str(no_anc["status"]) == FA.REFUSED)

	print("")
	print("  -- 7. a duplicate witness cannot be counted twice --")
	var witnesses := {}
	var claims := [
		{"round_id": "FLOWSCAR4-r1", "ancestor_event_id": 3},
		{"round_id": "FLOWSCAR4-r1", "ancestor_event_id": 3},
		{"round_id": "FLOWSCAR4-r2", "ancestor_event_id": 3},
	]
	var counted := 0
	var rejected: Array = []
	for c in claims:
		var key := "%s#%d" % [str((c as Dictionary)["round_id"]),
			int((c as Dictionary)["ancestor_event_id"])]
		if witnesses.has(key):
			rejected.append(key)
			continue
		witnesses[key] = true
		counted += 1
	ck("three claims, two distinct witnesses (counted %d)" % counted,
		counted == 2)
	ck("  the repeat is rejected by identity, not by order (%s)"
		% str(rejected), rejected.size() == 1)

	print("")
	print("  -- 8. an empty run produces zeros cleanly --")
	var empty: Dictionary = FA.counterfactual(_mc, _profile, _spec(), [],
		{"agent": "ALPHA", "tau": 0, "causing_event_id": 1})
	ck("an empty oplog is REFUSED rather than reported as NO_EFFECT",
		str(empty["status"]) == FA.REFUSED)
	var w8 = _world_pre({}, {})
	var l8: Dictionary = FA.leverage(w8, "west_pipe", shell_mass)
	ck("a null world still answers the gate without crashing",
		l8.has("eligible"))

	print("")
	if _fail == 0:
		print("FLOW ANALYSIS OK -- gate and counterfactual behave on fixtures")
		quit(0)
	else:
		print("FLOW ANALYSIS FAILED: %d check(s)." % _fail)
		print("Do not seal: the instrument does not measure what it claims.")
		quit(1)
