extends SceneTree

## OBSERVATION V3 DIAGNOSTIC — STAGE 1: executable fixtures.
##
##   godot --headless --path . --script tools/observation_v3_stage1.gd -- \
##       --out scratch/v3_stage1 --decider live|precheck
##
## Preregistered in docs/OBSERVATION_V3_DIAGNOSTIC_PREREG.md.
##
## THE QUESTION: did falconh1 fail TAKE and WITHDRAW_KEY under V2 because the
## encoding made MOVE salient, or because the shared qualification fixture made
## those verbs NON-EXECUTABLE and V2 honestly said so?
##
## THE V2 ENCODING IS UNCHANGED. Only the world changes: one unambiguous
## fixture per failed verb, where the requested operation genuinely works.
##
## THE OFFLINE PRECHECK RUNS FIRST, ALWAYS. Each fixture has the canonical
## action injected straight into the reducer and must be proven executable
## before any model is called. Skipping that would repeat the exact mistake
## being diagnosed: qualifying a verb against a state where it cannot run.
##
## THE CHAIN IS END TO END, not merely valid JSON:
##   1. the requested verb is selected
##   2. the target is drawn from the correct visible domain
##   3. the canonical parser accepts it
##   4. the real reducer accepts it
##   5. the expected state mutation occurs

const MC := preload("res://scripts/breach/mass_contract.gd")
const CO := preload("res://scripts/breach/canonical_operation.gd")
const OB := preload("res://scripts/breach/observation_builder.gd")
const PARSER := preload("res://scripts/breach/output_parser.gd")
const Reducer := preload("res://scripts/breach/world_reducer.gd")
const WorldStateScript := preload("res://scripts/breach/world_state.gd")
const AgentStateScript := preload("res://scripts/breach/agent_state.gd")
const BusScript := preload("res://scripts/breach/message_bus.gd")
const SoloJit := preload("res://scripts/breach/solo_jit_decider.gd")

const SPECIES := [
	["falconh1", "falcon-h1-1.5b-instruct"],
	["lfm25", "liquidai/lfm2.5-1.2b-instruct"],
	["qwen35", "qwen3.5-2b"],
	["rwkv7", "rwkv7-1.5b-g1"],
	["danube2", "h2o-danube2-1.8b-chat"],
]
const REPS := 3

var _mc = null
var _out_dir := "scratch/v3_stage1"
var _decider_kind := "live"
var _http: HTTPRequest = null
var _live = null
var _fail := 0


func ck(label: String, cond: bool) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail += 1


func _sha(text: String) -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(text.to_utf8_buffer())
	return c.finish().hex_encode()


## TAKE fixture: exactly one visible floor object, one valid target, nothing
## competing. The actor holds nothing, so inventory cannot be confused with the
## floor.
func _fixture_take() -> Dictionary:
	var w = WorldStateScript.new()
	w.contract = _mc
	w.round_id = "V3S1_TAKE"
	w.add_location("chamber_north", "Chamber North", ["vault_hall"])
	w.add_location("vault_hall", "Vault Hall", ["chamber_north"])
	w.add_object("key_blue", "key", "chamber_north")
	var me = AgentStateScript.new("ACTOR", "f", "f", "f#1", 60,
		"chamber_north")
	return {"world": w, "agents": {"ACTOR": me}, "verb": CO.TAKE,
		"fields": {"target": "key_blue"}, "domain": "visible_object_ids",
		"expect": "key_blue is held by ACTOR"}


## WITHDRAW_KEY fixture: actor AT the vault, exactly one visible occupied slot,
## every reducer prerequisite satisfied.
func _fixture_withdraw() -> Dictionary:
	var w = WorldStateScript.new()
	w.contract = _mc
	w.round_id = "V3S1_WITHDRAW"
	w.add_location("vault_hall", "Vault Hall", ["chamber_north"])
	w.add_location("chamber_north", "Chamber North", ["vault_hall"])
	w.add_object("key_blue", "key", "vault_hall")
	w.add_vault_slot("slot_1")
	## A committed key: the slot holds it and the object is held by the vault.
	w.vault_slots["slot_1"] = "key_blue"
	w.objects["key_blue"]["holder"] = "vault"
	w.objects["key_blue"]["at_location"] = ""
	var me = AgentStateScript.new("ACTOR", "f", "f", "f#1", 60, "vault_hall")
	return {"world": w, "agents": {"ACTOR": me}, "verb": CO.WITHDRAW_KEY,
		"fields": {"target": "slot_1"}, "domain": "visible_vault_slot_ids",
		"expect": "key_blue leaves slot_1 and is held by ACTOR"}


func _clone(fx: Dictionary) -> Dictionary:
	## Rebuild rather than deep-copy, so every rep starts from an identical
	## world and no rep inherits another's mutation.
	return _fixture_take() if str(fx["verb"]) == CO.TAKE \
		else _fixture_withdraw()


## THE PRECHECK. Inject the canonical action; the reducer must accept it and the
## expected mutation must occur. A fixture that fails here is not a fixture.
func _precheck(fx: Dictionary) -> Dictionary:
	var f := _clone(fx)
	var w = f["world"]
	var agents: Dictionary = f["agents"]
	var verb := str(f["verb"])
	var obs: Dictionary = OB.build(w, agents, "ACTOR", BusScript.new(), [])
	var domains: Dictionary = obs["domains"]
	var dom: Array = domains.get(str(f["domain"]), [])
	var target := str((f["fields"] as Dictionary)["target"])
	var res := Reducer.apply(w, agents, "ACTOR", verb, f["fields"],
		BusScript.new(), 1)
	var mutated := false
	if verb == CO.TAKE:
		mutated = agents["ACTOR"].has_object("key_blue") \
			and str(w.objects["key_blue"]["holder"]) == "ACTOR"
	else:
		mutated = str(w.vault_slots["slot_1"]).is_empty() \
			and agents["ACTOR"].has_object("key_blue")
	return {"domain_has_target": dom.has(target), "domain": dom,
		"accepted": bool(res["ok"]), "reason": str(res["reason"]),
		"mutated": mutated,
		"observation_text": JSON.stringify(obs, "\t"),
		"fixture_id": "%s@%s" % [str(w.round_id),
			_sha(JSON.stringify(obs)).substr(0, 12)]}


func _parse_args() -> void:
	var argv := OS.get_cmdline_user_args()
	for i in argv.size():
		match argv[i]:
			"--out": _out_dir = str(argv[i + 1])
			"--decider": _decider_kind = str(argv[i + 1])


func _init() -> void:
	_parse_args()
	print("=== OBSERVATION V3 DIAGNOSTIC -- STAGE 1 ===")
	print("V2 encoding UNCHANGED; only the world changes.")
	var r: Dictionary = MC.open(2)
	if not bool(r["ok"]):
		print("  FAIL %s" % str(r["reason"]))
		quit(1)
		return
	_mc = r["contract"]
	var fh := FileAccess.open("res://config/action-schema.v1.json",
		FileAccess.READ)
	var schema_text := fh.get_as_text().strip_edges()
	fh.close()
	_http = HTTPRequest.new()
	_http.timeout = 180.0
	root.add_child(_http)
	if _decider_kind == "live":
		_live = SoloJit.new(schema_text, _http, 2048)
	_run.call_deferred()


func _run() -> void:
	var fixtures := [_fixture_take(), _fixture_withdraw()]
	var prechecked: Array = []

	print("")
	print("  -- OFFLINE PRECHECK: is each fixture genuinely executable? --")
	for fx in fixtures:
		var f: Dictionary = fx
		var pc: Dictionary = _precheck(f)
		var verb := str(f["verb"])
		print("   %s  fixture %s" % [verb, str(pc["fixture_id"])])
		ck("  %s: target is in %s %s"
			% [verb, str(f["domain"]), str(pc["domain"])],
			bool(pc["domain_has_target"]))
		ck("  %s: the reducer ACCEPTS the canonical action (%s)"
			% [verb, str(pc["reason"])], bool(pc["accepted"]))
		ck("  %s: the expected mutation occurs -- %s"
			% [verb, str(f["expect"])], bool(pc["mutated"]))
		prechecked.append({"verb": verb, "precheck": pc, "fixture": f})
	if _fail > 0:
		print("")
		print("STAGE 1 REFUSED: a fixture is not executable.")
		print("Testing a model against it would repeat the mistake being")
		print("diagnosed. Fix the fixture before calling any model.")
		quit(1)
		return
	print("  every fixture proven executable before any model was called")

	if _decider_kind != "live":
		print("")
		print("STAGE 1 PRECHECK OK -- fixtures executable, no models called")
		quit(0)
		return

	var records: Array = []
	for entry in prechecked:
		var e: Dictionary = entry
		var verb := str(e["verb"])
		var pc: Dictionary = e["precheck"]
		var f: Dictionary = e["fixture"]
		print("")
		print("  -- LIVE: %s on an executable fixture --" % verb)
		for sp in SPECIES:
			var species := str(sp[0])
			var model := str(sp[1])
			var chain := 0
			var detail: Array = []
			for rep in REPS:
				var task := "Emit the operation %s." % verb
				var spoken: Dictionary = await _live.decide(
					str(pc["observation_text"]),
					SoloJit.contract_text() + "\n\n" + task, model)
				var raw := str(spoken.get("raw", ""))
				var v := PARSER.parse(raw)
				## 1 verb selected, 2 target from the right domain,
				## 3 parser accepts, 4 reducer accepts, 5 mutation occurs.
				var step1: bool = str(v["operation"]) == verb
				var step3: bool = bool(v["ok"])
				var target := str((v["fields"] as Dictionary).get("target", ""))
				var step2: bool = (pc["domain"] as Array).has(target)
				var step4 := false
				var step5 := false
				if step1 and step3 and step2:
					var f2 := _clone(f)
					var rr := Reducer.apply(f2["world"], f2["agents"], "ACTOR",
						str(v["operation"]), v["fields"], BusScript.new(), 1)
					step4 = bool(rr["ok"])
					if verb == CO.TAKE:
						step5 = f2["agents"]["ACTOR"].has_object("key_blue")
					else:
						step5 = str(f2["world"].vault_slots["slot_1"]).is_empty() \
							and f2["agents"]["ACTOR"].has_object("key_blue")
				var full: bool = step1 and step2 and step3 and step4 and step5
				if full:
					chain += 1
				detail.append({"rep": rep, "raw": raw,
					"operation": str(v["operation"]), "target": target,
					"verb_selected": step1, "target_in_domain": step2,
					"parser_ok": step3, "reducer_ok": step4,
					"mutated": step5, "full_chain": full})
				records.append({"verb": verb, "species": species,
					"model_id": model, "fixture_id": str(pc["fixture_id"]),
					"rep": rep, "raw": raw, "operation": str(v["operation"]),
					"target": target, "full_chain": full,
					"verb_selected": step1, "target_in_domain": step2,
					"parser_ok": step3, "reducer_ok": step4, "mutated": step5})
			var mark := "" if chain == REPS else "   <-"
			print("    %-10s full chain %d/%d%s" % [species, chain, REPS, mark])
			if chain != REPS:
				for d in detail:
					var dd: Dictionary = d
					if not bool(dd["full_chain"]):
						print("       got %s target=%s  verb=%s domain=%s "
							% [str(dd["operation"]), str(dd["target"]),
								str(dd["verb_selected"]),
								str(dd["target_in_domain"])]
							+ "parser=%s reducer=%s mutated=%s"
							% [str(dd["parser_ok"]), str(dd["reducer_ok"]),
								str(dd["mutated"])])

	var falcon_ok := 0
	for rec in records:
		var rr2: Dictionary = rec
		if str(rr2["species"]) == "falconh1" and bool(rr2["full_chain"]):
			falcon_ok += 1
	print("")
	print("  === STAGE 1 VERDICT ===")
	print("    falconh1 full chain: %d / %d" % [falcon_ok, 2 * REPS])
	if falcon_ok == 2 * REPS:
		print("    -> the shared fixture contradicted the requested action")
		print("    -> V2 is NOT convicted; the qualification fixture is the")
		print("       defect. Stage 2 is NOT run.")
	else:
		print("    -> the failure survives an executable fixture")
		print("    -> presentation regression is real; Stage 2 must run.")

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_out_dir))
	var path := "%s/V3_STAGE1.json" % _out_dir
	var f3 := FileAccess.open(path, FileAccess.WRITE)
	f3.store_string(JSON.stringify({
		"artifact_kind": "OBSERVATION_V3_STAGE1",
		"prereg": "docs/OBSERVATION_V3_DIAGNOSTIC_PREREG.md",
		"encoding": "OBSERVATION_CONTRACT_V2, unchanged",
		"precheck": prechecked.map(func(x): return {
			"verb": str((x as Dictionary)["verb"]),
			"fixture_id": str(((x as Dictionary)["precheck"]
				as Dictionary)["fixture_id"])}),
		"falcon_full_chain": falcon_ok,
		"falcon_cells": 2 * REPS,
		"records": records,
	}, "\t"))
	f3.flush()
	f3.close()
	print("    wrote %s" % ProjectSettings.globalize_path(path))
	SoloJit.unload_all()
	print("    cleanup: all models unloaded")
	quit(0)
