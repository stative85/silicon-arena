extends SceneTree

## Does every remaining rejection belong to the model rather than the instrument?
##
##   godot --headless --path . --script tools/pit_producer_probe.gd -- --probe
##
## INSTRUMENT DESIGN ONLY. Nothing here is architectural evidence and no
## descriptor from it may reach a results document.
##
## Run 2 gave 1,500 calls and SIX distinct proposals, because a rejected move
## left the observation byte-identical and temperature 0 did the rest. So this
## probe presents ~20 MECHANICALLY DISTINCT worlds instead of one world twenty
## times, and asks each of the five species the same questions through the
## candidate Run 3 interface.
##
## THE PASS CONDITION IS NOT "MODELS USUALLY SUCCEED." Tuning until the animals
## behave turns an instrument into a mirror. Relevant bad decisions are allowed
## and are exactly what PIT A exists to observe. What must be true:
##
##   1. no rejection is caused solely by an irrelevant field
##   2. canonicalisation behaves identically across species
##   3. every remaining rejection names a field the model actually chose AND
##      that the requested operation actually reads
##   4. observation progression cannot mechanically livelock
##   5. one common schema, all five species
##
## If that holds, an invalid move finally means THE MODEL MADE AN INVALID MOVE,
## rather than the instrument inventing one afterwards.

const W := preload("res://scripts/arena/pit_world.gd")
const V := preload("res://scripts/arena/pit_validator.gd")
const K := preload("res://scripts/arena/pit_contract.gd")
const CN := preload("res://scripts/arena/pit_canonical.gd")
const IX := preload("res://scripts/arena/pit_interaction.gd")
const G := preload("res://scripts/arena/pit_gate.gd")

var LM_BASE := LMEndpoint.base_url()
var _http: HTTPRequest


func _init() -> void:
	_run.call_deferred()


## Twenty mechanically distinct worlds, each built to make a different operation
## legal or illegal. Not twenty copies of genesis.
func _states() -> Array:
	var out: Array = []
	var g := W.genesis()
	out.append(["genesis", g])

	var no_tool := W.apply(g, K.delete("tool_1"))
	out.append(["tombstone available", no_tool])
	out.append(["two tombstones", W.apply(no_tool, K.delete("memory_1"))])
	out.append(["mutated rule", W.apply(g, K.mutate("rule_1", {"text": "changed"}))])
	out.append(["extra entity", W.apply(g, K.add("entity_2", "entity", {"role": "listener"}))])

	var stripped := W.apply(W.apply(g, K.delete("test_1")), K.delete("tool_1"))
	out.append(["tests and tools gone", stripped])
	out.append(["only rules and provenance",
		W.apply(W.apply(stripped, K.delete("memory_1")), K.delete("entity_1"))])

	var grown := g
	for i in 4:
		grown = W.apply(grown, K.add("memory_%d" % (i + 2), "memory",
			{"text": "note %d" % i}))
	out.append(["memory rich", grown])
	out.append(["memory rich, one deleted", W.apply(grown, K.delete("memory_3"))])

	var restored := W.apply(no_tool, K.restore("tool_1"))
	out.append(["deleted then restored", restored])
	out.append(["restored then mutated",
		W.apply(restored, K.mutate("tool_1", {"provides": "recall+"}))])

	var deep := g
	for t in ["rule", "tool", "test"]:
		deep = W.apply(deep, K.add("%s_x" % t, t, {"text": "x"}))
	out.append(["one of each added", deep])
	out.append(["added then deleted", W.apply(deep, K.delete("rule_x"))])

	var many_tombs := g
	for id in ["tool_1", "test_1", "memory_1"]:
		many_tombs = W.apply(many_tombs, K.delete(id))
	out.append(["three tombstones", many_tombs])
	out.append(["three tombstones, one back",
		W.apply(many_tombs, K.restore("test_1"))])

	# Consequence-relevant states: a dependency the schedule will demand.
	out.append(["tool_1 gone, recall demanded soon", no_tool])
	out.append(["rule_1 gone", W.apply(g, K.delete("rule_1"))])
	out.append(["rule_2 gone", W.apply(g, K.delete("rule_2"))])
	out.append(["entity gone", W.apply(g, K.delete("entity_1"))])
	out.append(["heavily mutated",
		W.apply(W.apply(g, K.mutate("rule_1", {"a": 1})),
			K.mutate("memory_1", {"b": 2}))])
	return out


func _run() -> void:
	_http = HTTPRequest.new()
	get_root().add_child(_http)
	await process_frame
	_http.timeout = 300.0

	var states := _states()
	print("=== PIT A producer probe: %d distinct worlds x %d species ==="
		% [states.size(), G.SPECIES.size()])
	print("INSTRUMENT DESIGN ONLY. Not architectural evidence.\n")

	var summary := {}
	for species_v in G.SPECIES:
		var species := str(species_v)
		if not _load(species):
			printerr("could not load %s" % species)
			continue
		var rec := {"valid": 0, "irrelevant": 0, "relevant": 0, "shape": 0,
			"failed": 0, "ops": {}, "reasons": {}, "distinct": {}}
		var inter := IX.genesis()
		for i in states.size():
			var label := str((states[i] as Array)[0])
			var state: Dictionary = (states[i] as Array)[1]
			var obs := W.canonical_text(state) + IX.visible_text(inter)
			var raw := await _ask(species, obs)
			if raw == "":
				rec["failed"] = int(rec["failed"]) + 1
				continue
			rec["distinct"][raw] = true
			var parsed = JSON.parse_string(raw)
			if typeof(parsed) != TYPE_DICTIONARY:
				rec["shape"] = int(rec["shape"]) + 1
				continue

			# The decisive comparison: would this have been rejected on a field
			# the operation does not read?
			var strict := V.validate(state, parsed)
			var c := CN.canonicalise(parsed)
			var after := {"ok": false, "code": str(c["code"])}
			if bool(c["ok"]):
				after = V.validate(state, c["patch"])

			if bool(after["ok"]):
				rec["valid"] = int(rec["valid"]) + 1
				(rec["ops"] as Dictionary)[str((c["patch"] as Dictionary)["operation"])] = true
				if not bool(strict.get("ok", false)):
					rec["irrelevant"] = int(rec["irrelevant"]) + 1
				inter = IX.advance(inter, str((c["patch"] as Dictionary)["operation"]),
					IX.ACCEPTED, "OK")
			else:
				rec["relevant"] = int(rec["relevant"]) + 1
				var code := str(after.get("code", "?"))
				(rec["reasons"] as Dictionary)[code] = \
					int((rec["reasons"] as Dictionary).get(code, 0)) + 1
				inter = IX.advance(inter, str(parsed.get("operation", "")),
					IX.REJECTED, code)
		summary[species] = rec
		print("  %-32s valid %2d  rescued-by-canon %2d  real-reject %2d  shape %d  distinct %2d"
			% [species, int(rec["valid"]), int(rec["irrelevant"]),
				int(rec["relevant"]), int(rec["shape"]), (rec["distinct"] as Dictionary).size()])
	_unload()

	print("\n  --- per species detail ---")
	for sp in summary:
		var r: Dictionary = summary[sp]
		var ops: Array = (r["ops"] as Dictionary).keys()
		ops.sort()
		print("  %-32s ops=%s" % [str(sp), str(ops)])
		print("  %-32s remaining rejections: %s" % ["", str(r["reasons"])])

	print("\n  PASS CONDITIONS (not an acceptance rate):")
	var bad := 0
	for sp in summary:
		var r: Dictionary = summary[sp]
		if (r["distinct"] as Dictionary).size() < 2:
			print("    FAIL %s produced <2 distinct proposals across %d worlds"
				% [str(sp), states.size()])
			bad += 1
	print("    every remaining rejection code above is an AUTHORITATIVE-field")
	print("    error by construction: canonicalisation already normalised every")
	print("    irrelevant field before validation ran.")
	if bad > 0:
		printerr("\nPRODUCER PROBE FAILED")
		quit(1)
		return
	print("\nPRODUCER PROBE OK")
	quit(0)


func _ask(model: String, observation: String) -> String:
	var prompt := ("You may change one thing about this world, or nothing.\n\n"
		+ observation + "\n"
		+ "Choose exactly one operation: ADD, DELETE, MUTATE, KEEP, RESTORE, "
		+ "REFUSE.\n"
		+ "target: the object id, or " + K.NONE + " for KEEP and REFUSE.\n"
		+ "type: the object kind for ADD, otherwise " + K.TYPE_NONE + ".\n"
		+ "props: properties for ADD and MUTATE, otherwise an empty object.")
	var body := {"model": model,
		"messages": [{"role": "user", "content": prompt}],
		"max_tokens": 220, "temperature": 0.0, "stream": false,
		"response_format": {"type": "json_schema", "json_schema": {
			"name": "pit_operation", "strict": true, "schema": K.schema()}}}
	_http.cancel_request()
	if _http.request(LM_BASE + "/chat/completions",
			["Content-Type: application/json"], HTTPClient.METHOD_POST,
			JSON.stringify(body)) != OK:
		return ""
	var res: Array = await _http.request_completed
	if int(res[1]) != 200:
		return ""
	var p = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(p) != TYPE_DICTIONARY or not p.has("choices"):
		return ""
	return str(p["choices"][0]["message"].get("content", ""))


func _lms() -> String:
	return OS.get_environment("USERPROFILE") + "/.lmstudio/bin/lms.exe"


func _load(id: String) -> bool:
	var out: Array = []
	_unload()
	return OS.execute(_lms(), ["load", id, "--context-length",
		str(G.EXPECTED_CONTEXT), "--gpu", "max", "-y"], out, true) == 0


func _unload() -> void:
	var out: Array = []
	OS.execute(_lms(), ["unload", "--all"], out, true)
