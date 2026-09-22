extends SceneTree

## Do the hash profiles see what they must, and only what they must?
##
##   godot --headless --path . --script tools/state_profile_selftest.gd
##
## THE DEFECT: flow_channel, flow_material and flow_deposits sat outside
## to_dict(), so two worlds differing only in accumulated material hashed
## identically. FLOWSCAR4's counterfactual exists to see exactly that
## difference.
##
## THE WRONG FIX, refused: widening the existing payload. Step 1B's artifacts
## were hashed under the old shape; changing it would silently change what a
## signed result meant. So the payload is chosen by a NAMED profile, and this
## file is the golden proof that the old shape still produces the old bytes.

const SP := preload("res://scripts/breach/state_profile.gd")
const MC := preload("res://scripts/breach/mass_contract.gd")
const WorldStateScript := preload("res://scripts/breach/world_state.gd")

var _fail := 0


func ck(label: String, cond: bool) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail += 1


func _contract(v: int):
	var r: Dictionary = MC.open(v)
	if not bool(r["ok"]):
		print("  FAIL contract v%d: %s" % [v, str(r["reason"])])
		_fail += 1
		return null
	return r["contract"]


func _open(n: String):
	var r: Dictionary = SP.open(n)
	if not bool(r["ok"]):
		print("  FAIL profile %s: %s" % [n, str(r["reason"])])
		_fail += 1
		return null
	return r["profile"]


## A FIXED world. Deliberately boring and deliberately identical every time:
## a golden hash is only golden if its input cannot drift.
func _fixture(contract, with_flow: bool):
	var w = WorldStateScript.new()
	w.contract = contract
	w.round_id = "PROFILE_FIXTURE"
	w.add_location("west_pipe", "West Pipe", [])
	w.add_location("commons_north", "Commons North", ["west_pipe"])
	w.add_location("vault_ring", "Vault Ring", ["commons_north"])
	w.add_location("store_room", "Store Room", ["commons_north"])
	w.add_object("key_1", "key", "west_pipe")
	w.add_object("scrap_1", "scrap", "store_room")
	w.add_vault_slot("slot_1")
	if with_flow:
		w.flow_channel = ["west_pipe", "commons_north", "vault_ring"]
	return w


func _init() -> void:
	print("=== STATE HASH PROFILES ===")
	var v1 = _contract(1)
	var v2 = _contract(2)
	var breach = _open("BREACH_STATE_V1")
	var flow = _open("FLOWSCAR4_STATE_V1")
	if v1 == null or v2 == null or breach == null or flow == null:
		quit(1)
		return
	print("  known profiles: %s" % str(SP.known()))

	print("")
	print("  -- 1. the historical payload is reproduced byte for byte --")
	var w1 = _fixture(v1, false)
	var direct := JSON.stringify(w1.to_dict())
	var viaprofile := JSON.stringify(breach.payload(w1))
	ck("BREACH_STATE_V1 payload IS to_dict(), exactly", direct == viaprofile)
	ck("it carries no flow fields", not breach.includes_flow()
		and not breach.payload(w1).has("flow_material"))
	## The golden bytes themselves. If this ever changes, a signed Step 1B
	## artifact stopped being reproducible and the failure must be loud.
	var golden: String = breach.state_hash(w1)
	print("       golden BREACH_STATE_V1 hash: %s" % golden)
	ck("hashing the same fixture twice is stable",
		golden == breach.state_hash(_fixture(v1, false)))
	## Adding flow to a world must NOT move the historical hash.
	var w1f = _fixture(v1, true)
	w1f.flow_material["west_pipe"] = 5
	ck("flow state does NOT move the BREACH_STATE_V1 hash",
		breach.state_hash(w1f) == golden)

	print("")
	print("  -- 2. flow material changes the FLOWSCAR4 hash --")
	var a = _fixture(v2, true)
	var b = _fixture(v2, true)
	ck("identical worlds hash identically",
		flow.state_hash(a) == flow.state_hash(b))
	b.flow_material["commons_north"] = 1
	ck("one unit of material at one node changes the hash",
		flow.state_hash(a) != flow.state_hash(b))
	var c = _fixture(v2, true)
	c.flow_material["commons_north"] = 0
	ck("an explicit zero is still state, distinct from absent",
		flow.state_hash(c) != flow.state_hash(a))

	print("")
	print("  -- 3. channel ORDER changes the hash --")
	var d = _fixture(v2, true)
	d.flow_channel = ["vault_ring", "commons_north", "west_pipe"]
	ck("a reversed channel is a different world",
		flow.state_hash(d) != flow.state_hash(a))

	print("")
	print("  -- 4. deposit / ratchet state changes the hash --")
	var e = _fixture(v2, true)
	e.flow_deposits = 1
	ck("the ratchet counter is hashed", flow.state_hash(e) != flow.state_hash(a))
	var f = _fixture(v2, true)
	f.add_object("deposit_1", "deposit", "commons_north")
	ck("a deposit object is hashed", flow.state_hash(f) != flow.state_hash(a))
	var g = _fixture(v2, true)
	g.add_object("shell_vanta", "shell", "commons_north")
	ck("a shell object is hashed", flow.state_hash(g) != flow.state_hash(a))

	print("")
	print("  -- 5. profiles coexist interleaved without contamination --")
	var seq := [breach, flow, breach, flow]
	var hashes := []
	for p in seq:
		var w = _fixture(v2, true)
		w.flow_material["west_pipe"] = 3
		hashes.append(p.state_hash(w))
	ck("the two BREACH hashes agree with each other", hashes[0] == hashes[2])
	ck("the two FLOWSCAR4 hashes agree with each other", hashes[1] == hashes[3])
	ck("BREACH and FLOWSCAR4 disagree, as they must", hashes[0] != hashes[1])
	ck("a BREACH hash taken AFTER a FLOWSCAR4 hash is unchanged",
		hashes[2] == breach.state_hash(_fixture(v1, false)))
	var bad: Dictionary = SP.open("FLOWSCAR9_STATE_V1")
	ck("an unknown profile is refused", not bool(bad["ok"]))
	ck("  and names itself (%s)" % str(bad["reason"]).substr(0, 22),
		str(bad["reason"]).begins_with("UNKNOWN_STATE_PROFILE"))
	ck("a refusal returns no profile", bad["profile"] == null)

	_projections(v2, flow)

	print("")
	if _fail == 0:
		print("STATE PROFILES OK -- the hash sees what the regime declared")
		quit(0)
	else:
		print("STATE PROFILES FAILED: %d check(s)." % _fail)
		print("Do not run FLOWSCAR4: the counterfactual cannot see the state")
		print("it exists to measure, or a historical hash has moved.")
		quit(1)


## THE TWO PROJECTIONS. A single complete hash cannot prove "unrelated state
## remains invariant", because the treatment is expected to change part of it.
func _projections(v2, flow) -> void:
	print("")
	print("  -- 6. causal and unrelated projections --")
	var before = _fixture(v2, true)
	var after = _fixture(v2, true)
	## Membership frozen at tau, from the PRE-treatment world.
	var m: Dictionary = SP.membership(before, [])

	## THE TREATMENT: a shell lands on a channel node, and material piles behind
	## it. Nothing away from the channel is touched.
	after.add_object("shell_vanta", "shell", "commons_north")
	after.flow_material["west_pipe"] = 4

	var v: Dictionary = flow.verdict(before, after, m)
	ck("causal hash DIFFERS", bool(v["causal_differs"]))
	ck("unrelated hash is IDENTICAL", bool(v["unrelated_identical"]))
	ck("complete hash DIFFERS", bool(v["complete_differs"]))

	## CONTAMINATION must be detectable: change something off-channel and the
	## unrelated half has to notice.
	var dirty = _fixture(v2, true)
	dirty.add_object("shell_vanta", "shell", "commons_north")
	dirty.objects["scrap_1"]["at_location"] = "vault_ring"
	var v2d: Dictionary = flow.verdict(before, dirty, m)
	ck("moving an off-channel object breaks the unrelated hash",
		not bool(v2d["unrelated_identical"]))

	## NO_EFFECT must be reportable rather than indistinguishable from success.
	var same = _fixture(v2, true)
	var v3: Dictionary = flow.verdict(before, same, m)
	ck("an unchanged world reports no causal difference",
		not bool(v3["causal_differs"]) and not bool(v3["complete_differs"]))
	ck("  with its unrelated half still identical",
		bool(v3["unrelated_identical"]))

	## A channel node's contents must not appear in BOTH halves, or the
	## unrelated hash would move with the scar and never be identical.
	var un: Dictionary = flow.unrelated_projection(after, m)
	ck("the unrelated half excludes shells", not (un["objects"] as Dictionary)
		.has("shell_vanta"))
	var ca: Dictionary = flow.causal_projection(after, m)
	ck("the causal half includes the shell",
		(ca["objects"] as Dictionary).has("shell_vanta"))
	ck("the unrelated half keeps the off-channel object",
		(un["objects"] as Dictionary).has("scrap_1"))
	ck("the causal half excludes the off-channel object",
		not (ca["objects"] as Dictionary).has("scrap_1"))

	print("")
	print("  -- 7. membership is frozen at tau, not read off the outcome --")
	## 7a. INSERTION ORDER must not change a hash.
	var o1 = _fixture(v2, true)
	var o2 = WorldStateScript.new()
	o2.contract = v2
	o2.round_id = "PROFILE_FIXTURE"
	## Same world, built in a different order.
	o2.add_location("vault_ring", "Vault Ring", ["commons_north"])
	o2.add_location("store_room", "Store Room", ["commons_north"])
	o2.add_location("west_pipe", "West Pipe", [])
	o2.add_location("commons_north", "Commons North", ["west_pipe"])
	o2.add_object("scrap_1", "scrap", "store_room")
	o2.add_object("key_1", "key", "west_pipe")
	o2.add_vault_slot("slot_1")
	o2.flow_channel = ["west_pipe", "commons_north", "vault_ring"]
	ck("logically identical worlds hash identically despite build order",
		flow.state_hash(o1) == flow.state_hash(o2))

	## 7b. A shell moved OFF the channel stays causal.
	var s_before = _fixture(v2, true)
	s_before.add_object("shell_vanta", "shell", "commons_north")
	var ms: Dictionary = SP.membership(s_before, [])
	var s_after = _fixture(v2, true)
	s_after.add_object("shell_vanta", "shell", "store_room")
	var uo: Dictionary = flow.unrelated_projection(s_after, ms)
	var co: Dictionary = flow.causal_projection(s_after, ms)
	ck("a shell dragged off-channel is STILL causal",
		(co["objects"] as Dictionary).has("shell_vanta"))
	ck("  and never appears in the unrelated half",
		not (uo["objects"] as Dictionary).has("shell_vanta"))

	## 7c. A pre-existing unrelated object moved ONTO the channel stays
	## unrelated -- unless ancestry declares it a descendant.
	var p_after = _fixture(v2, true)
	p_after.objects["scrap_1"]["at_location"] = "commons_north"
	var pu: Dictionary = flow.unrelated_projection(p_after, m)
	var pc: Dictionary = flow.causal_projection(p_after, m)
	ck("an unrelated object moved onto the channel is NOT reclassified",
		(pu["objects"] as Dictionary).has("scrap_1")
			and not (pc["objects"] as Dictionary).has("scrap_1"))
	var md: Dictionary = SP.membership(before, ["scrap_1"])
	var dc: Dictionary = flow.causal_projection(p_after, md)
	var du: Dictionary = flow.unrelated_projection(p_after, md)
	ck("  but ancestry CAN mark it a descendant, and then it is causal",
		(dc["objects"] as Dictionary).has("scrap_1")
			and not (du["objects"] as Dictionary).has("scrap_1"))

	## 7d. Membership cannot be derived from the treated outcome: the same
	## final world under two different taus classifies differently.
	var tau_late = _fixture(v2, true)
	tau_late.objects["scrap_1"]["at_location"] = "commons_north"
	var m_late: Dictionary = SP.membership(tau_late, [])
	var c_late: Dictionary = flow.causal_projection(p_after, m_late)
	ck("the SAME final world classifies differently under a different tau",
		(c_late["objects"] as Dictionary).has("scrap_1")
			and not (pc["objects"] as Dictionary).has("scrap_1"))

	## 7e. Every dynamic object lands in exactly one projection.
	for w in [before, after, s_after, p_after]:
		var audit: Dictionary = flow.partition_audit(w, m)
		ck("partition is complete and disjoint (%d of %d, missing %s, both %s)"
			% [int(audit["counted"]), int(audit["total"]),
				str(audit["missing"]), str(audit["in_both"])],
			bool(audit["ok"]))
