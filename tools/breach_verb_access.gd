extends SceneTree

## STEP 1a -- VERB ACCESS QUALIFICATION.
##
##   godot --headless --path . --script tools/breach_verb_access.gd -- \
##       --ctx 2048 --reps 3 --out user://verb_access.json
##
## THE ONE QUESTION:
##
##     Can each species emit each of the 16 agent-choosable operations through
##     the frozen interface, such that the REAL parser accepts it?
##
## WHAT THIS IS NOT. Not a benchmark, not a leaderboard, not a measure of what
## a model would CHOOSE. Every prompt names the operation to emit, so this
## measures ACCESS UNDER INSTRUCTION and nothing else. A species that can reach
## a verb and never picks it has passed step 1a; one that cannot reach it makes
## every later difference uninterpretable. That is the whole point of the gate.
##
## LAW 3, PRODUCTION-PATH EQUIVALENCE. The verdict comes from
## scripts/breach/output_parser.gd itself -- the same static parse() the arena
## runs. Nothing here re-implements it, relaxes it, or repairs output before
## showing it. The vocabulary and required fields are read out of
## canonical_operation.gd rather than restated, because PIT A run 1 kept a
## private copy of a contract shape, the copy disagreed with the validator, and
## nothing in the instrument could notice.
##
## WHY NOT THE BRIDGE. InferenceBridge manages residency and will swap models
## under memory pressure. The context sweep established that pool composition is
## exactly what must be held constant, so this probe is sequential, inflight 1,
## with the pool preloaded and never touched. That also matches turn_scheduler,
## which issues one request at a time.
##
## TWO ARMS, because the choice is load-bearing and not yet made:
##   FREE    raw text, no grammar constraint -- what the unwired live seam
##           describes: send the packet, take the text back unmodified
##   SCHEMA  the same prompt with a json_schema response_format
## If a species passes only under SCHEMA, that is a fact about the interface
## decision, not about the species, and the human call should see it.

const OP := preload("res://scripts/breach/canonical_operation.gd")
const PARSER := preload("res://scripts/breach/output_parser.gd")

const LM_BASE := "http://127.0.0.1:1234/v1"
const TEMPERATURE := 0.0
## Run 1 used 160 and truncated danube2 mid-object, which the parser then
## reported as not_json. A ceiling that turns a verbose answer into a parse
## failure measures the ceiling.
const MAX_TOKENS := 512
const REQUEST_TIMEOUT_S := 90.0

var _http: HTTPRequest
var _ctx := 2048
var _reps := 3
var _out := "user://verb_access.json"
var _models: Array = []


func _init() -> void:
	_parse_args()
	_models = _roster()
	if _models.is_empty():
		push_error("no roster; config/arena-species.v1.json unreadable")
		quit(1)
		return
	_http = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT_S
	root.add_child(_http)
	_run.call_deferred()


func _parse_args() -> void:
	var argv := OS.get_cmdline_user_args()
	for i in argv.size():
		match argv[i]:
			"--ctx": _ctx = int(argv[i + 1])
			"--reps": _reps = int(argv[i + 1])
			"--out": _out = str(argv[i + 1])


## Membership comes from the frozen population file and nowhere else. Display
## names decide nothing (ARENA_IDENTITY_LAYERS, forbidden inference I-1).
func _roster() -> Array:
	var fh := FileAccess.open("res://config/arena-species.v1.json",
		FileAccess.READ)
	if fh == null:
		return []
	var d = JSON.parse_string(fh.get_as_text())
	fh.close()
	if typeof(d) != TYPE_DICTIONARY:
		return []
	var out := []
	for s in d.get("species", []):
		out.append({"model_id": str(s.get("model_id", "")),
			"species_id": str(s.get("species_id", ""))})
	return out


## The contract, generated from the canonical source. Identical for all five
## species, every time. No persona, no behavioural suggestion, no per-species
## wording -- that is what keeps a later species comparison free of
## PERSONA_CONFOUND.
func _contract() -> String:
	var lines := []
	for op in OP.AGENT_CHOOSABLE:
		var req: Array = OP.required_fields(op)
		if req.is_empty():
			lines.append("  %s" % op)
		else:
			## Run 1 wrote "MOVE  requires: target" and falcon-h1 echoed the
			## word back as a key -- {"operation":"MOVE","requires":"target"}.
			## Contract wording that can be mistaken for a field name measures
			## the wording.
			lines.append("  %s  (fields: %s)" % [op, ", ".join(req)])
	return ("Reply with exactly one JSON object and no other text.\n"
		+ "It must have an \"operation\" field whose value is one of:\n"
		+ "\n".join(lines) + "\n"
		+ "Include every field that operation requires, each a non-empty "
		+ "string. Do not include an \"operations\" list.")


func _task(op: String) -> String:
	var req: Array = OP.required_fields(op)
	var s := "Emit the operation %s." % op
	if not req.is_empty():
		var pairs := []
		for f in req:
			pairs.append("%s=\"%s\"" % [f, _value_for(str(f))])
		s += " Use these values: " + ", ".join(pairs)
	return s


## Fixture values. Deliberately boring and identical across species: this gate
## is about reaching the verb, not about choosing a good target.
func _value_for(field: String) -> String:
	match field:
		"target": return "chamber_north"
		"object": return "key_blue"
		"requested": return "key_red"
		"text": return "status report"
	return "x"


## PER-OPERATION schema. Run 1 used ONE schema for all sixteen: every optional
## field present, only "operation" required. Under constrained decoding all five
## species then answered GIVE and OFFER with "text" where "object" belonged, and
## all five failed both operations -- a uniform failure across unrelated
## architectures, which is the signature of the instrument rather than the
## subjects. The schema now asks for exactly the fields the operation requires.
func _schema(op: String) -> Dictionary:
	var props := {"operation": {"type": "string", "enum": [op]}}
	var req := ["operation"]
	for f in OP.required_fields(op):
		props[str(f)] = {"type": "string", "minLength": 1}
		req.append(str(f))
	return {"type": "object", "additionalProperties": false,
		"required": req, "properties": props}


func _ask(model: String, op: String, arm: String) -> Dictionary:
	var body := {"model": model,
		"messages": [{"role": "user",
			"content": _contract() + "\n\n" + _task(op)}],
		"max_tokens": MAX_TOKENS, "temperature": TEMPERATURE, "stream": false}
	if arm == "SCHEMA":
		body["response_format"] = {"type": "json_schema", "json_schema": {
			"name": "canonical_operation", "strict": true,
			"schema": _schema(op)}}
	_http.cancel_request()
	var t0 := Time.get_ticks_msec()
	if _http.request(LM_BASE + "/chat/completions",
			["Content-Type: application/json"], HTTPClient.METHOD_POST,
			JSON.stringify(body)) != OK:
		return {"transport": false, "raw": "", "latency_ms": -1}
	var res: Array = await _http.request_completed
	var ms := Time.get_ticks_msec() - t0
	if int(res[1]) != 200:
		return {"transport": false, "raw": "",
			"http": int(res[1]), "latency_ms": ms}
	var parsed = JSON.parse_string(
		(res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("choices"):
		return {"transport": false, "raw": "", "latency_ms": ms}
	return {"transport": true, "latency_ms": ms,
		"raw": str(parsed["choices"][0]["message"].get("content", ""))}


func _run() -> void:
	var started := Time.get_datetime_string_from_system(true)
	print("=== STEP 1a VERB ACCESS ===")
	print("context %d, %d reps, %d species x %d operations x 2 arms"
		% [_ctx, _reps, _models.size(), OP.AGENT_CHOOSABLE.size()])
	print("verdict from scripts/breach/output_parser.gd, unmodified")
	print("")

	var records := []
	var matrix := {}
	for arm in ["FREE", "SCHEMA"]:
		print("[ARM %s]" % arm)
		for m in _models:
			var sid := str(m["species_id"])
			var row := {}
			for op in OP.AGENT_CHOOSABLE:
				var ok_n := 0
				var fails := {}
				for r in _reps:
					var got: Dictionary = await _ask(str(m["model_id"]), op, arm)
					var verdict := PARSER.parse(str(got.get("raw", "")))
					## Access means: the parser accepted it AND it is the
					## operation that was asked for. A model that emits a
					## different valid verb has not demonstrated access to
					## this one.
					var hit: bool = bool(verdict["ok"]) \
						and str(verdict["operation"]) == op
					if hit:
						ok_n += 1
					else:
						var why := str(verdict["parse_failure"])
						if why.is_empty():
							why = "wrong_operation:" + str(verdict["operation"])
						if not bool(got.get("transport", false)):
							why = "transport"
						fails[why] = int(fails.get(why, 0)) + 1
					records.append({"arm": arm, "species_id": sid,
						"model_id": str(m["model_id"]), "asked": op,
						"rep": r, "accepted": hit,
						"got_operation": str(verdict["operation"]),
						"parse_failure": str(verdict["parse_failure"]),
						"parse_detail": str(verdict["parse_detail"]),
						"latency_ms": int(got.get("latency_ms", -1)),
						"raw": str(got.get("raw", ""))})
				row[op] = {"ok": ok_n, "n": _reps, "failures": fails}
			matrix[arm + "/" + sid] = row
			var passed := 0
			for op in OP.AGENT_CHOOSABLE:
				if int(row[op]["ok"]) == _reps:
					passed += 1
			print("  %-10s %2d/%d operations clean"
				% [sid, passed, OP.AGENT_CHOOSABLE.size()])
	_report(matrix)
	_write(started, records, matrix)
	quit(0)


func _report(matrix: Dictionary) -> void:
	for arm in ["FREE", "SCHEMA"]:
		print("")
		print("[MATRIX %s]  . = all reps accepted, digit = accepted count" % arm)
		var head := "  %-16s" % "operation"
		for m in _models:
			head += "%-10s" % str(m["species_id"])
		print(head)
		for op in OP.AGENT_CHOOSABLE:
			var line := "  %-16s" % op
			for m in _models:
				var key := "%s/%s" % [arm, str(m["species_id"])]
				var cell: Dictionary = matrix[key][op]
				line += "%-10s" % ("." if int(cell["ok"]) == _reps
					else str(int(cell["ok"])))
			print(line)


func _write(started: String, records: Array, matrix: Dictionary) -> void:
	var payload := {
		"gate": "STEP_1A_VERB_ACCESS",
		"started_utc": started,
		"context": _ctx,
		"reps": _reps,
		"operations": OP.AGENT_CHOOSABLE,
		"species": _models,
		"parser": "scripts/breach/output_parser.gd",
		"matrix": matrix,
		"records": records,
	}
	var fh := FileAccess.open(_out, FileAccess.WRITE)
	if fh == null:
		push_error("cannot write " + _out)
		return
	fh.store_string(JSON.stringify(payload, "\t"))
	fh.flush()
	fh.close()
	print("")
	print("wrote %s" % ProjectSettings.globalize_path(_out))
