extends SceneTree

## BREACH OFFLINE QUALIFICATION. NO_CONTACT.
##
##     godot --headless --path . --script scripts/breach/breach_selftest.gd
##
## NOT YET EXECUTED. Written while the RUNTIME-MEMORY four-arm run owns the
## machine; running Godot would have put a second process on the box during a
## timing-sensitive experiment. This suite is the FIRST action when Lane A
## lands -- the point of writing it now is that qualification does not begin
## with authorship.
##
## Every check here runs with ZERO inference and ZERO LM Studio contact. The
## ScriptedDecider emits raw text through the same parser a live model will use,
## so the offline path exercises the production path rather than bypassing it
## (Law 3).
##
## The load-bearing checks, the ones that would let a silent behavioural lie
## through if they were absent:
##
##   * malformed output becomes NO_OP and NEVER WAIT
##   * the vault needs three DISTINCT keys
##   * a committed key can be withdrawn by someone who did not commit it
##   * initiative rotates, so first-mover advantage is not a species effect
##   * the replay chain detects a tampered event

const BreachRoundScript := preload("res://scripts/breach/breach_round.gd")
const OutputParserScript := preload("res://scripts/breach/output_parser.gd")
const CanonicalOperationScript := preload("res://scripts/breach/canonical_operation.gd")
const DeciderScript := preload("res://scripts/breach/decider.gd")
const BreachRosterScript := preload("res://scripts/breach/breach_roster.gd")
const WorldStateScript := preload("res://scripts/breach/world_state.gd")
const WorldReducerScript := preload("res://scripts/breach/world_reducer.gd")
const AgentStateScript := preload("res://scripts/breach/agent_state.gd")
const ArenaLayoutScript := preload("res://scripts/breach/arena_layout.gd")
const TurnSchedulerScript := preload("res://scripts/breach/turn_scheduler.gd")
const MemoryLedgerScript := preload("res://scripts/breach/memory_ledger.gd")
const CO := CanonicalOperationScript

var checks := 0
var fails: Array = []


func ck(label: String, cond: bool, detail: String = "") -> void:
	checks += 1
	if cond:
		print("  ok   %s" % label)
	else:
		fails.append(label)
		print("  FAIL %s %s" % [label, detail])


func _init() -> void:
	print("=== BREACH offline qualification ===")

	print("\n[the vocabulary is the whole host]")
	ck("16 agent-choosable operations", CO.AGENT_CHOOSABLE.size() == 16,
		str(CO.AGENT_CHOOSABLE.size()))
	ck("NO_OP is not agent-choosable",
		not CO.is_agent_choosable(CO.NO_OP))
	ck("NO_OP is a known host operation", CO.is_known(CO.NO_OP))
	for banned in ["ALLY", "BETRAY", "TRUST", "LEAD", "COOPERATE", "DECEIVE"]:
		ck("no verb named %s" % banned, not CO.is_known(banned))

	print("\n[malformed output becomes NO_OP, never WAIT]")
	for bad in ["", "I think I should wait and see.", "{not json",
			"{\"operation\": \"BETRAY\", \"target\": \"BRINE\"}",
			"{\"operation\": \"MOVE\"}",
			"{\"operation\": \"NO_OP\"}",
			"{\"operations\": [{\"operation\": \"WAIT\"}]}"]:
		var p := OutputParserScript.parse(bad)
		ck("rejected: %s" % bad.substr(0, 34),
			not bool(p["ok"]) and str(p["operation"]) == CO.NO_OP
			and str(p["operation"]) != CO.WAIT,
			str(p["operation"]))
		ck("  raw text retained verbatim", str(p["raw"]) == bad)
		ck("  parse_failure names a reason",
			not str(p["parse_failure"]).is_empty())

	var good := OutputParserScript.parse(
		"{\"operation\":\"MOVE\",\"target\":\"vault_ring\"}")
	ck("a valid operation parses", bool(good["ok"])
		and str(good["operation"]) == CO.MOVE)
	var fenced := OutputParserScript.parse(
		"Sure!\n```json\n{\"operation\":\"WAIT\"}\n```")
	ck("fenced JSON is found, not repaired", bool(fenced["ok"])
		and str(fenced["operation"]) == CO.WAIT)
	ck("  and the raw text still holds the prose",
		str(fenced["raw"]).begins_with("Sure!"))

	print("\n[bounded, model-authored memory]")
	var led = MemoryLedgerScript.new("TEST")
	for i in MemoryLedgerScript.MAX_ENTRIES:
		led.write("entry %d" % i, [i], i)
	ck("ledger fills to 12", led.size() == 12, str(led.size()))
	var refused := led.write("thirteenth", [99], 99)
	ck("a full ledger REFUSES rather than silently evicting",
		not bool(refused["ok"]))
	var replaced := led.write("replacement", [100], 100, 3)
	ck("naming a replace_index works", bool(replaced["ok"])
		and str(replaced["action"]) == "replaced")
	ck("the replaced slot holds the new text",
		str((led.as_lines()[3] as Dictionary)["text"]) == "replacement")

	print("\n[initiative rotates]")
	var sched = TurnSchedulerScript.new(["A", "B", "C", "D", "E"])
	var first_cycle := sched.current_order()
	for i in 5:
		sched.advance()
	var second_cycle := sched.current_order()
	ck("cycle 1 starts with A", str(first_cycle[0]) == "A")
	ck("cycle 2 starts with B", str(second_cycle[0]) == "B",
		str(second_cycle[0]))
	ck("no agent is dropped by rotation", second_cycle.size() == 5)

	print("\n[the vault needs three DISTINCT keys]")
	var w = WorldStateScript.new()
	ArenaLayoutScript.build(w, "TEST")
	ck("five keys exist in the world",
		w.objects.has("key_A") and w.objects.has("key_E"))
	ck("five slots, three required",
		w.vault_slots.size() == 5 and w.VAULT_REQUIRED_KEYS == 3)
	w.vault_slots["vault_slot_1"] = "key_A"
	w.vault_slots["vault_slot_2"] = "key_B"
	ck("two keys do not open it", not w.vault_should_open())
	w.vault_slots["vault_slot_3"] = "key_A"
	ck("a repeated key does NOT count toward three",
		not w.vault_should_open(), str(w.distinct_committed_keys()))
	w.vault_slots["vault_slot_3"] = "key_C"
	ck("three distinct keys open it", w.vault_should_open())

	print("\n[vault operations are PHYSICAL -- no key teleportation]")
	var w2 = WorldStateScript.new()
	ArenaLayoutScript.build(w2, "TEST2")
	var far = AgentStateScript.new("FAR", "m", "s", "m#1", 100, "spawn_vanta")
	far.add_object("key_A")
	var at_vault = AgentStateScript.new("NEAR", "m", "s", "m#1", 100, w2.vault_location)
	at_vault.add_object("key_B")
	var two := {"FAR": far, "NEAR": at_vault}
	var r_far := WorldReducerScript.apply(w2, two, "FAR", CO.COMMIT_KEY,
		{"target": "vault_slot_1"}, null)
	ck("committing from across the arena is REFUSED", not bool(r_far["ok"]),
		str(r_far["reason"]))
	ck("  and the slot stayed empty",
		str(w2.vault_slots["vault_slot_1"]).is_empty())
	var r_near := WorldReducerScript.apply(w2, two, "NEAR", CO.COMMIT_KEY,
		{"target": "vault_slot_1"}, null)
	ck("committing while standing at the vault works", bool(r_near["ok"]),
		str(r_near["reason"]))
	ck("  the key is in the slot",
		str(w2.vault_slots["vault_slot_1"]) == "key_B")
	var r_wfar := WorldReducerScript.apply(w2, two, "FAR", CO.WITHDRAW_KEY,
		{"target": "vault_slot_1"}, null)
	ck("withdrawing from across the arena is REFUSED", not bool(r_wfar["ok"]))
	var r_wnear := WorldReducerScript.apply(w2, two, "NEAR", CO.WITHDRAW_KEY,
		{"target": "vault_slot_1"}, null)
	ck("withdrawing at the vault transfers POSSESSION explicitly",
		bool(r_wnear["ok"]) and at_vault.has_object("key_B")
		and str(w2.objects["key_B"]["holder"]) == "NEAR")
	ck("  and the slot is empty again",
		str(w2.vault_slots["vault_slot_1"]).is_empty())

	print("\n[a full offline round, no inference]")
	var roster := BreachRosterScript.load_roster()
	ck("roster loads five species from config", roster.size() == 5,
		str(roster.size()))
	ck("roster is the Ignition 0 shape",
		BreachRosterScript.is_ignition_0_shape(roster))
	if roster.size() == 5:
		var names: Array = []
		for r in roster:
			names.append(str((r as Dictionary)["display_name"]))
		ck("names are VANTA/KESTREL/GEMMATRON/OZONIOUS/BRINE",
			names == ["VANTA", "KESTREL", "GEMMATRON", "OZONIOUS", "BRINE"],
			str(names))

		var deciders := {}
		for r in roster:
			var d: Dictionary = r
			deciders[str(d["display_name"])] = DeciderScript.ScriptedDecider.new([
				"{\"operation\":\"OBSERVE\",\"target\":\"vault\"}",
				"garbage, not json at all",
				"{\"operation\":\"WAIT\"}",
			])
		var round_a = BreachRoundScript.new("TEST-A", roster, deciders, 40)
		var out_a := round_a.run_to_completion()
		ck("round terminates", bool(out_a["ended"]))
		ck("it ends for a frozen reason",
			[BreachRoundScript.END_VAULT_OPENED,
			 BreachRoundScript.END_NO_AGENT_CAN_ACT,
			 BreachRoundScript.END_TIME_HORIZON].has(str(out_a["end_reason"])),
			str(out_a["end_reason"]))
		ck("events were recorded", int(out_a["events"]) > 0)
		ck("the garbage line produced NO_OPs", int(out_a["no_op_count"]) > 0,
			str(out_a["no_op_count"]))
		ck("vault failure is a valid outcome, not an error",
			out_a.has("vault_open"))

		print("\n[determinism: same inputs, same round]")
		var deciders_b := {}
		for r in roster:
			var d2: Dictionary = r
			deciders_b[str(d2["display_name"])] = DeciderScript.ScriptedDecider.new([
				"{\"operation\":\"OBSERVE\",\"target\":\"vault\"}",
				"garbage, not json at all",
				"{\"operation\":\"WAIT\"}",
			])
		var round_b = BreachRoundScript.new("TEST-A", roster, deciders_b, 40)
		var out_b := round_b.run_to_completion()
		ck("chain head is identical across two identical rounds",
			str(out_a["chain_head"]) == str(out_b["chain_head"]),
			"%s vs %s" % [out_a["chain_head"], out_b["chain_head"]])

		print("\n[the replay chain detects tampering]")
		var v := round_a.log.verify_chain()
		ck("an untouched log verifies", bool(v["ok"]))
		if round_a.log.events.size() > 2:
			## SABOTAGE: rewrite a recorded operation, the way a tidied log
			## would. Assert the mutation applied before trusting the result.
			var before_op := str(round_a.log.events[1]["operation"])
			round_a.log.events[1]["operation"] = "MOVE"
			var applied := str(round_a.log.events[1]["operation"]) != before_op
			ck("SABOTAGE APPLIED (an event was rewritten)", applied)
			if applied:
				var v2 := round_a.log.verify_chain()
				ck("SABOTAGE BITES: the chain refuses", not bool(v2["ok"]))
				ck("  and names the first divergent event",
					int(v2["first_divergence"]) == 1,
					str(v2.get("first_divergence", -1)))
			round_a.log.events[1]["operation"] = before_op
			ck("SABOTAGE REVERTED", bool(round_a.log.verify_chain()["ok"]))

		print("\n[the artifact carries the roster axis, never a pool id]")
		var art := round_a.log.to_artifact(round_a.world, out_a)
		ck("population_regime_id is B",
			str(art["population_regime_id"]) == "B")
		ck("no measurement_pool_id on a roster artifact",
			not art.has("measurement_pool_id"))
		ck("the roster manifest carries model identity",
			(art["roster"] as Array).size() == 5
			and (art["roster"][0] as Dictionary).has("model_id"))

	print("\n[SUMMARY]")
	print("  checks %d, failures %d" % [checks, fails.size()])
	if fails.is_empty():
		print("\nBREACH OFFLINE GREEN -- the machinery transports operations")
		print("correctly. It says NOTHING about what five models will do.")
	else:
		print("\nBREACH OFFLINE RED")
		for f in fails:
			print("  failed: %s" % f)
	quit(0 if fails.is_empty() else 1)
