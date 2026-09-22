extends SceneTree

## AFFORDANCE_GROUNDING — separating prompt presentation from model capability.
##
##   godot --headless --path . --script tools/affordance_grounding.gd -- \
##       --out scratch/affordance --decider live|mock
##
## Preregistered in docs/AFFORDANCE_GROUNDING_PREREG.md. A separate experiment
## with its own record. It cannot alter FLOWSCAR4, which is closed at
## NO ANCESTOR / CAUSAL CLAIM NOT EVALUATED.
##
## PACKETS ARE RECONSTRUCTED, NOT CAPTURED. FLOWSCAR4's artifacts persisted the
## oplog and not the observation each agent saw, nor its observation_hash. So
## the packets are rebuilt by deterministic replay of the committed oplog
## against the committed starting state. ObservationBuilder is deterministic, so
## this should be byte-identical to what the models saw -- but "should be" is
## not a witness, and nothing here can verify it against a stored hash. Every
## packet is labelled RECONSTRUCTED and every finding carries that caveat.
##
## The schema and the parser are UNCHANGED. Four conditions, one generation per
## cell, temperature 0, no repair, no retry.

const RoundScript := preload("res://scripts/breach/breach_round.gd")
const OB := preload("res://scripts/breach/observation_builder.gd")
const PARSER := preload("res://scripts/breach/output_parser.gd")
const CO := preload("res://scripts/breach/canonical_operation.gd")
const SoloJit := preload("res://scripts/breach/solo_jit_decider.gd")
const MC := preload("res://scripts/breach/mass_contract.gd")

const ROUNDS := ["FLOWSCAR4-r1", "FLOWSCAR4-r2", "FLOWSCAR4-r3"]
const CONDITIONS := ["A", "B", "C", "D"]

var _out_dir := "scratch/affordance"
var _decider_kind := "live"
var _http: HTTPRequest = null
var _live = null
var _schema_text := ""


func _parse_args() -> void:
	var argv := OS.get_cmdline_user_args()
	for i in argv.size():
		match argv[i]:
			"--out": _out_dir = str(argv[i + 1])
			"--decider": _decider_kind = str(argv[i + 1])


func _sha(text: String) -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(text.to_utf8_buffer())
	return c.finish().hex_encode()


func _sha_file(rel: String) -> String:
	var fh := FileAccess.open("res://" + rel, FileAccess.READ)
	if fh == null:
		return ""
	var b := fh.get_buffer(fh.get_length())
	fh.close()
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(b)
	return c.finish().hex_encode()


func _git(args: Array) -> String:
	var out: Array = []
	OS.execute("git", args, out, true)
	return "\n".join(out.map(func(x): return str(x))).strip_edges()


## RECONSTRUCTION. Replay the committed oplog; at each turn, before the
## operation is applied, build the packet that actor saw. Returns the FIRST
## packet for each species in this round -- one fixture per species per round.
func _reconstruct(round_id: String) -> Dictionary:
	var fh := FileAccess.open("res://docs/results/flowscar4/%s.json"
		% round_id, FileAccess.READ)
	if fh == null:
		return {}
	var d = JSON.parse_string(fh.get_as_text())
	fh.close()
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	var art: Dictionary = d

	var roster: Array = []
	for nm in (art.get("roster_order", []) as Array):
		roster.append({"display_name": str(nm),
			"model_id": _model_for(str(nm)),
			"species_id": _species_for(str(nm)),
			"instance_id": "%s#1" % _model_for(str(nm))})
	var rd = RoundScript.new(round_id, roster, {},
		int(art.get("ticks_ceiling", 140)), null, 2)
	if rd.ended:
		return {}
	rd.world.flow_channel = ["west_pipe", "commons_north", "vault_ring"]

	var packets := {}
	for entry in (art.get("oplog", []) as Array):
		var o: Dictionary = entry
		var actor := str(o.get("actor", ""))
		if not rd.agents.has(actor):
			continue
		if not packets.has(actor):
			var obs: Dictionary = OB.build(rd.world, rd.agents, actor, rd.bus,
				rd.public_lines)
			packets[actor] = {"observation": obs,
				"observation_text": JSON.stringify(obs, "\t"),
				"exits": (obs.get("location", {}) as Dictionary)
					.get("exits", []),
				"position": str((obs.get("location", {}) as Dictionary)
					.get("id", "")),
				"tick": int(o.get("tick", -1)),
				"provenance": "RECONSTRUCTED"}
		rd.deciders[actor] = _Canned.new("")
		rd.step()
	return packets


func _model_for(display: String) -> String:
	match display:
		"BRINE": return "h2o-danube2-1.8b-chat"
		"GEMMATRON": return "qwen3.5-2b"
		"KESTREL": return "falcon-h1-1.5b-instruct"
		"OZONIOUS": return "rwkv7-1.5b-g1"
		"VANTA": return "liquidai/lfm2.5-1.2b-instruct"
	return ""


func _species_for(display: String) -> String:
	match display:
		"BRINE": return "danube2"
		"GEMMATRON": return "qwen35"
		"KESTREL": return "falconh1"
		"OZONIOUS": return "rwkv7"
		"VANTA": return "lfm25"
	return ""


## THE FOUR CONDITIONS. A is the original prompt verbatim; the others add ONE
## instruction each, and nothing else changes.
func _prompt(cond: String, packet: Dictionary) -> String:
	var base := SoloJit.contract_text() + "\n\nOBSERVATION:\n" \
		+ str(packet["observation_text"])
	var exits: Array = packet["exits"]
	match cond:
		"A":
			return base
		"B":
			return base + "\n\nMOVE to any adjacent room shown in the " \
				+ "observation."
		"C":
			var target := str(exits[0]) if not exits.is_empty() else ""
			return base + "\n\nMOVE to \"%s\"." % target
		"D":
			var listing := ""
			for e in exits:
				listing += "\n  " + str(e)
			return base + "\n\nLEGAL MOVE TARGETS:" + listing \
				+ "\n\nMOVE to any adjacent room shown in the observation."
	return base


func _init() -> void:
	_parse_args()
	print("=== AFFORDANCE_GROUNDING (%s) ===" % _decider_kind)
	var dirty := _git(["status", "--porcelain"])
	if not dirty.is_empty():
		print("REFUSED: worktree is not clean")
		quit(2)
		return
	var fh := FileAccess.open("res://config/action-schema.v1.json",
		FileAccess.READ)
	_schema_text = fh.get_as_text().strip_edges()
	fh.close()
	_http = HTTPRequest.new()
	_http.timeout = 180.0
	root.add_child(_http)
	if _decider_kind == "live":
		_live = SoloJit.new(_schema_text, _http, 2048)
	_run.call_deferred()


func _run() -> void:
	var commit := _git(["rev-parse", "HEAD"])
	print("  apparatus %s" % commit.substr(0, 12))
	print("  schema %s  parser %s"
		% [_sha_file("config/action-schema.v1.json").substr(0, 12),
			_sha_file("scripts/breach/output_parser.gd").substr(0, 12)])

	var fixtures: Array = []
	for rid in ROUNDS:
		var packets := _reconstruct(rid)
		for actor in packets.keys():
			var p: Dictionary = packets[actor]
			if (p["exits"] as Array).is_empty():
				continue
			fixtures.append({"round_id": rid, "display": str(actor),
				"packet": p})
	print("  reconstructed %d fixtures (RECONSTRUCTED, unverifiable against a "
		% fixtures.size() + "stored hash)")
	if fixtures.is_empty():
		print("REFUSED: no fixtures reconstructed")
		quit(2)
		return

	var records: Array = []
	for cond in CONDITIONS:
		print("")
		print("  [CONDITION %s]" % cond)
		var per := {}
		for f in fixtures:
			var fx: Dictionary = f
			var display := str(fx["display"])
			var model := _model_for(display)
			var packet: Dictionary = fx["packet"]
			var prompt := _prompt(cond, packet)
			var raw := ""
			if _decider_kind == "live":
				var spoken: Dictionary = await _live.decide(
					str(packet["observation_text"]),
					_prompt(cond, packet).replace(
						"\n\nOBSERVATION:\n" + str(packet["observation_text"]),
						""), model)
				raw = str(spoken.get("raw", ""))
			var verdict := PARSER.parse(raw)
			var exits: Array = packet["exits"]
			var target := str((verdict["fields"] as Dictionary).get("target",
				""))
			var is_move: bool = bool(verdict["ok"]) \
				and str(verdict["operation"]) == CO.MOVE
			var valid: bool = is_move and exits.has(target)
			if not per.has(display):
				per[display] = {"n": 0, "parsed": 0, "move": 0, "valid": 0,
					"ops": {}, "bad_targets": []}
			var q: Dictionary = per[display]
			q["n"] = int(q["n"]) + 1
			if bool(verdict["ok"]):
				q["parsed"] = int(q["parsed"]) + 1
				var op := str(verdict["operation"])
				(q["ops"] as Dictionary)[op] = int(
					(q["ops"] as Dictionary).get(op, 0)) + 1
			if is_move:
				q["move"] = int(q["move"]) + 1
			if valid:
				q["valid"] = int(q["valid"]) + 1
			elif is_move:
				(q["bad_targets"] as Array).append(target)
			records.append({"condition": cond, "round_id": str(fx["round_id"]),
				"species": display, "model_id": model,
				"position": str(packet["position"]), "exits": exits,
				"raw": raw, "operation": str(verdict["operation"]),
				"parse_failure": str(verdict["parse_failure"]),
				"target": target, "valid_move": valid,
				"packet_provenance": "RECONSTRUCTED"})
		for display in ["BRINE", "GEMMATRON", "KESTREL", "OZONIOUS", "VANTA"]:
			if not per.has(display):
				continue
			var q: Dictionary = per[display]
			print("    %-10s valid MOVE %d/%d   parsed %d   ops %s%s"
				% [display, int(q["valid"]), int(q["n"]), int(q["parsed"]),
					str(q["ops"]),
					("  bad targets " + str(q["bad_targets"]))
						if not (q["bad_targets"] as Array).is_empty() else ""])

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_out_dir))
	var payload := {
		"artifact_kind": "AFFORDANCE_GROUNDING",
		"prereg": "docs/AFFORDANCE_GROUNDING_PREREG.md",
		"apparatus_commit": commit,
		"schema_sha256": _sha_file("config/action-schema.v1.json"),
		"parser_sha256": _sha_file("scripts/breach/output_parser.gd"),
		"observation_builder_sha256":
			_sha_file("scripts/breach/observation_builder.gd"),
		"packet_provenance": "RECONSTRUCTED from committed FLOWSCAR4 oplogs; "
			+ "NOT verifiable against a stored observation hash",
		"decider_kind": _decider_kind,
		"conditions": CONDITIONS,
		"fixtures": fixtures.size(),
		"records": records,
	}
	var path := "%s/AFFORDANCE_GROUNDING.json" % _out_dir
	var tmp := path + ".tmp"
	var f2 := FileAccess.open(tmp, FileAccess.WRITE)
	f2.store_string(JSON.stringify(payload, "\t"))
	f2.flush()
	f2.close()
	var da := DirAccess.open(path.get_base_dir())
	if FileAccess.file_exists(path):
		da.remove(path.get_file())
	da.rename(tmp.get_file(), path.get_file())
	print("")
	print("  wrote %s" % ProjectSettings.globalize_path(path))
	if _decider_kind == "live":
		SoloJit.unload_all()
		print("  cleanup: all models unloaded")
	quit(0)


class _Canned:
	var raw: String = ""

	func _init(p_raw: String) -> void:
		raw = p_raw

	func decide(_o: Dictionary, _a) -> Dictionary:
		return {"raw": raw, "latency_ms": 0, "params": {}}
