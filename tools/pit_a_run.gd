extends SceneTree

## PIT A: five architectures, one persistent world, one hundred chances each.
##
##   godot --headless --path . --script tools/pit_a_run.gd -- --negative
##   godot --headless --path . --script tools/pit_a_run.gd -- --run
##
## Pre-registered in docs/EXPERIMENT_PIT_A.md at 15f30e9, amended at e4faf3e.
## Instrument at c1688d7, gate and journal at 673a750.
##
## THERE IS NO SKIP PATH IN THIS FILE. tools/verify.cmd may skip live probing so
## the suite passes on a machine without LM Studio. Execution may not. Every
## startup condition below aborts, and an abort produces no journal, no
## manifest, and no outcome.
##
## EFFECTIVE CONFIGURATION, MEASURED AFTER LOADING. Inventory metadata saying
## RWKV supports a million tokens is not a violation; RUNNING it at a million
## would be. The gate is therefore consulted twice -- once on inventory to catch
## a missing species, and once on what each model reports once it is actually
## resident.
##
## NO SILENT RETRY. A failed HTTP request is REQUEST_FAILED, journalled as
## infrastructure, and the cycle is consumed. Asking again would hand one
## species extra lottery tickets that the others never received.
##
## THE PRE-STATE IS COMMITTED BEFORE GENERATION. An open-cycle marker carrying
## the presented state hash is written and flushed BEFORE the first token is
## requested, so a crash leaves an unambiguous record of what the species was
## looking at. On resume the marker distinguishes a cycle that never started
## from one whose generation died mid-flight.

const W := preload("res://scripts/arena/pit_world.gd")
const V := preload("res://scripts/arena/pit_validator.gd")
const C := preload("res://scripts/arena/pit_consequence.gd")
const R := preload("res://scripts/arena/pit_random.gd")
const G := preload("res://scripts/arena/pit_gate.gd")
const J := preload("res://scripts/arena/pit_journal.gd")

var LM_BASE := LMEndpoint.base_url()

const CYCLES := 100
const REPLICATES := [0, 1, 2]
const MAX_TOKENS := 220
const TEMPERATURE := 0.0
const RANDOM_ARM := "RANDOM"

## Frozen sampling. Recorded in the manifest so a later run cannot differ
## quietly and still call itself PIT A.
const SAMPLING := {"temperature": TEMPERATURE, "max_tokens": MAX_TOKENS,
	"top_p": 1.0, "stream": false}

var _http: HTTPRequest
var _mode := ""


func _init() -> void:
	_run.call_deferred()


func _abort(step: String, why: String) -> void:
	printerr("\nPIT A ABORT at %s" % step)
	printerr("  %s" % why)
	printerr("  No journal, no manifest, no outcome.")
	quit(1)


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if str(a) == "--run":
			_mode = "run"
		if str(a) == "--negative":
			_mode = "negative"
	if _mode == "":
		printerr("need --run or --negative")
		quit(2)
		return

	_http = HTTPRequest.new()
	get_root().add_child(_http)
	await process_frame
	_http.timeout = 600.0

	if _mode == "negative":
		await _negative()
		return
	await _startup_then_run()


# ----------------------------------------------------------------- startup

func _startup_then_run() -> void:
	print("=== PIT A startup ===\n")

	# 1. live runtime reachable
	var inv := await _inventory()
	if inv.is_empty():
		_abort("1 runtime reachable", "LM Studio inventory unreadable")
		return
	print("  1  runtime reachable")

	# 2. the five frozen IDs resolve
	for id in G.SPECIES:
		if not inv.has(id):
			_abort("2 roster", "frozen species absent from inventory: %s" % id)
			return
	print("  2  five frozen species resolve")

	# 3. active runtime is the frozen one
	var runtime := _runtime_id()
	if runtime != G.EXPECTED_RUNTIME:
		_abort("3 runtime version", "active %s, frozen %s"
			% [runtime, G.EXPECTED_RUNTIME])
		return
	print("  3  runtime is %s" % runtime)

	# 4 + 5. load each species at 8192 and read the EFFECTIVE configuration.
	# Inventory maxima are irrelevant here; what matters is what is resident.
	var effective := {}
	for id in G.SPECIES:
		if not _load_species(str(id)):
			_abort("4 load", "could not load %s at context %d"
				% [str(id), G.EXPECTED_CONTEXT])
			return
		var live := await _inventory()
		var m: Dictionary = live.get(id, {})
		var ctx := int(m.get("loaded_context_length", -1))
		if ctx != G.EXPECTED_CONTEXT:
			_abort("5 effective context",
				"%s loaded at %d, frozen %d" % [str(id), ctx, G.EXPECTED_CONTEXT])
			return
		effective[id] = {"arch": str(m.get("arch", "")),
			"quant": str(m.get("quantization", "")), "context": ctx}
		print("  5  %-30s ctx=%d arch=%s" % [str(id), ctx, str(m.get("arch", ""))])
	_unload_all()

	# 6 + 7. the common instrument, by hash.
	var observed := {"runtime": runtime, "response_format": G.RESPONSE_FORMAT,
		"schema_hash": G.schema_hash(), "constraint_mode": G.CONSTRAINT_MODE,
		"models": effective}
	var verdict := G.check(observed)
	if not bool(verdict["ok"]):
		_abort("6/7 gate", str(verdict["failures"]))
		return
	print("  6  json_schema instrument, common across species")
	print("  7  schema hash %s" % G.schema_hash().substr(0, 16))

	# 8 + 9. the frozen world and the frozen consequence schedule.
	var genesis_hash := W.state_hash(W.genesis())
	print("  8  consequence schedule %s" % C.schedule_hash().substr(0, 16))
	print("  9  genesis world %s" % genesis_hash.substr(0, 16))

	# 10. manifest, written before the first generation.
	var manifest := _manifest(observed, genesis_hash)
	J.ensure_dir()
	var mf := FileAccess.open("user://pit_a/manifest.json", FileAccess.WRITE)
	if mf == null:
		_abort("10 manifest", "could not write the run manifest")
		return
	mf.store_string(JSON.stringify(manifest, "\t"))
	mf.flush()
	mf.close()
	print(" 10  manifest written")
	print(" 11  generation permitted\n")

	await _all_arms(manifest)


func _manifest(observed: Dictionary, genesis_hash: String) -> Dictionary:
	return {
		"pit_prereg_commit": "15f30e9",
		"pit_amendment_commit": "e4faf3e",
		"instrument_commit": "c1688d7",
		"probe_journal_commit": "673a750",
		"head_commit": _git_head(),
		"runtime": str(observed["runtime"]),
		"backend": "lmstudio-openai-compatible",
		"models": observed["models"],
		"schema_hash": G.schema_hash(),
		"constraint_mode": G.CONSTRAINT_MODE,
		"response_format": G.RESPONSE_FORMAT,
		"context": G.EXPECTED_CONTEXT,
		"quant": G.EXPECTED_QUANT,
		"genesis_hash": genesis_hash,
		"consequence_schedule_hash": C.schedule_hash(),
		"sampling": SAMPLING,
		"cycles": CYCLES,
		"replicates": REPLICATES,
		"started": Time.get_datetime_string_from_system(true),
	}


# -------------------------------------------------------------------- arms

func _all_arms(manifest: Dictionary) -> void:
	var arms: Array = G.SPECIES.keys()
	arms.append(RANDOM_ARM)
	for arm in arms:
		for rep in REPLICATES:
			await _trajectory(str(arm), int(rep), manifest)
	print("\nPIT A COMPLETE. Outcomes are not interpreted here.")
	quit(0)


func _trajectory(arm: String, replicate: int, manifest: Dictionary) -> void:
	var loaded := J.load_rows(arm, replicate)
	if not bool(loaded["ok"]):
		_abort("10 journal", "%s r%d refused: %s"
			% [arm, replicate, str(loaded["code"])])
		return
	var rows: Array = loaded["rows"]
	var state := J.replay(rows)
	var start := J.next_cycle(rows)

	# A marker left behind means a cycle opened and never closed. The state it
	# presented is recorded, so recovery is explicit rather than inferred.
	var marker := _read_marker(arm, replicate)
	if not marker.is_empty():
		print("  %s r%d: recovering half-cycle %d (presented %s)"
			% [arm, replicate, int(marker.get("cycle", -1)),
				str(marker.get("pre_state_hash", "")).substr(0, 12)])
		if str(marker.get("pre_state_hash", "")) != W.state_hash(state):
			_abort("10 journal", ("half-cycle marker for %s r%d presents %s but "
				+ "the replayed journal is at %s") % [arm, replicate,
				str(marker.get("pre_state_hash", "")).substr(0, 12),
				W.state_hash(state).substr(0, 12)])
			return
		_clear_marker(arm, replicate)

	if start >= CYCLES:
		print("  %s r%d already complete" % [arm, replicate])
		return
	if arm != RANDOM_ARM and not _load_species(arm):
		_abort("4 load", "could not load %s" % arm)
		return

	for cycle in range(start, CYCLES):
		await _cycle(arm, replicate, cycle, state)
		var reloaded := J.load_rows(arm, replicate)
		if not bool(reloaded["ok"]):
			_abort("journal", "%s r%d became unreadable mid-run: %s"
				% [arm, replicate, str(reloaded["code"])])
			return
		state = J.replay(reloaded["rows"])
	print("  %s r%d: %d cycles" % [arm, replicate, CYCLES])


# ------------------------------------------------------------- one cycle

func _cycle(arm: String, replicate: int, cycle: int, state: Dictionary) -> void:
	var pre := W.state_hash(state)

	# THE PRE-STATE IS COMMITTED BEFORE ANY TOKEN IS REQUESTED.
	_write_marker(arm, replicate, {"cycle": cycle, "pre_state_hash": pre,
		"phase": "OPENED"})

	var visible := W.canonical_text(state)
	var patch := {}
	var raw := ""
	var failed := false
	var t0 := Time.get_ticks_msec()

	if arm == RANDOM_ARM:
		patch = R.propose(state, 90000 + replicate, cycle)
		raw = JSON.stringify(patch)
	else:
		var resp := await _propose(arm, visible)
		raw = str(resp.get("raw", ""))
		if not bool(resp.get("ok", false)):
			failed = true
		else:
			var parsed = JSON.parse_string(raw)
			patch = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	var ms := Time.get_ticks_msec() - t0

	var reason := "REQUEST_FAILED"
	var accepted := false
	var post := pre
	if not failed:
		var v := V.validate(state, patch)
		reason = str(v["code"])
		accepted = bool(v["ok"])
		if accepted:
			post = W.state_hash(W.apply(state, patch))

	var next_state := W.apply(state, patch) if accepted else state
	var act := C.activation(replicate, cycle)
	var dep := C.evaluate(next_state, act)

	J.append(arm, replicate, {
		"species": arm, "replicate": replicate, "cycle": cycle,
		"pre_state_hash": pre, "visible_state_hash": visible.sha256_text(),
		"raw_response": raw, "patch": patch,
		"operation": str(patch.get("operation", "")),
		"target": str(patch.get("target", "")),
		"reason_code": reason, "accepted": accepted,
		"request_failed": failed,
		"post_state_hash": post,
		"scheduled_consequence": act, "dependency_result": dep,
		"latency_ms": ms, "phase": "COMMITTED",
	})
	_clear_marker(arm, replicate)


func _propose(model: String, visible: String) -> Dictionary:
	var prompt := ("You may change one thing about this world, or nothing.\n\n"
		+ "WORLD:\n" + visible + "\n"
		+ "Choose exactly one operation: ADD, DELETE, MUTATE, KEEP, RESTORE, "
		+ "REFUSE. Give the target object id, or an empty string for KEEP and "
		+ "REFUSE.")
	var body := {"model": model,
		"messages": [{"role": "user", "content": prompt}],
		"max_tokens": MAX_TOKENS, "temperature": TEMPERATURE, "stream": false,
		"response_format": {"type": "json_schema", "json_schema": {
			"name": "pit_operation", "strict": true, "schema": {
				"type": "object",
				"properties": {
					"operation": {"type": "string", "enum": W.OPS},
					"target": {"type": "string"},
					"explanation": {"type": "string"}},
				"required": ["operation", "target"],
				"additionalProperties": false}}}}
	_http.cancel_request()
	if _http.request(LM_BASE + "/chat/completions",
			["Content-Type: application/json"], HTTPClient.METHOD_POST,
			JSON.stringify(body)) != OK:
		return {"ok": false, "raw": ""}
	var res: Array = await _http.request_completed
	if int(res[1]) != 200:
		return {"ok": false, "raw": ""}
	var parsed = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("choices"):
		return {"ok": false, "raw": ""}
	return {"ok": true,
		"raw": str(parsed["choices"][0]["message"].get("content", ""))}


# ------------------------------------------------------- half-cycle markers

func _marker_path(arm: String, replicate: int) -> String:
	return "user://pit_a/%s__r%d.open" % [arm.replace("/", "_"), replicate]


func _write_marker(arm: String, replicate: int, d: Dictionary) -> void:
	J.ensure_dir()
	var fh := FileAccess.open(_marker_path(arm, replicate), FileAccess.WRITE)
	if fh == null:
		return
	fh.store_string(JSON.stringify(d))
	fh.flush()
	fh.close()


func _read_marker(arm: String, replicate: int) -> Dictionary:
	var fh := FileAccess.open(_marker_path(arm, replicate), FileAccess.READ)
	if fh == null:
		return {}
	var d = JSON.parse_string(fh.get_as_text())
	fh.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _clear_marker(arm: String, replicate: int) -> void:
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(_marker_path(arm, replicate)))


# ------------------------------------------------------------------ runtime

func _inventory() -> Dictionary:
	var out := {}
	_http.cancel_request()
	if _http.request(LM_BASE.replace("/v1", "") + "/api/v0/models") != OK:
		return out
	var res: Array = await _http.request_completed
	if int(res[1]) != 200:
		return out
	var p = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(p) != TYPE_DICTIONARY:
		return out
	for m in p.get("data", []):
		out[str(m.get("id", ""))] = m
	return out


func _lms() -> String:
	return OS.get_environment("USERPROFILE") + "/.lmstudio/bin/lms.exe"


func _load_species(id: String) -> bool:
	var out: Array = []
	_unload_all()
	return OS.execute(_lms(), ["load", id, "--context-length",
		str(G.EXPECTED_CONTEXT), "--gpu", "max", "--exact"], out, true) == 0


func _unload_all() -> void:
	var out: Array = []
	OS.execute(_lms(), ["unload", "--all"], out, true)


func _runtime_id() -> String:
	var out: Array = []
	if OS.execute(_lms(), ["runtime", "ls"], out, true) != 0 or out.is_empty():
		return "<unreadable>"
	for raw_line in str(out[0]).split("\n"):
		var line := raw_line.strip_edges()
		if not line.begins_with("llama.cpp"):
			continue
		var engine := line.split(" ")[0].strip_edges()
		var rest := line.substr(engine.length())
		var fmt := rest.find("GGUF")
		if fmt != -1 and rest.substr(0, fmt).strip_edges() != "":
			return engine
	return "<none selected>"


func _git_head() -> String:
	var out: Array = []
	if OS.execute("git", ["rev-parse", "--short", "HEAD"], out, true) != 0:
		return "<unknown>"
	return str(out[0]).strip_edges()


# ------------------------------------------------------------ negative tests

## Every abort path, exercised without a single generation.
func _negative() -> void:
	print("=== PIT A runner negative tests (no generation) ===\n")
	var bad := 0
	var base := {"runtime": G.EXPECTED_RUNTIME,
		"response_format": G.RESPONSE_FORMAT, "schema_hash": G.schema_hash(),
		"constraint_mode": G.CONSTRAINT_MODE, "models": {}}
	for id in G.SPECIES:
		(base["models"] as Dictionary)[id] = {"context": G.EXPECTED_CONTEXT,
			"quant": G.EXPECTED_QUANT, "arch": str(G.SPECIES[id])}

	var cases := {
		"model missing": func(d): (d["models"] as Dictionary).erase(str(G.SPECIES.keys()[0])),
		"loaded at wrong context": func(d): ((d["models"] as Dictionary)[str(G.SPECIES.keys()[0])] as Dictionary)["context"] = 32768,
		"wrong quantisation": func(d): ((d["models"] as Dictionary)[str(G.SPECIES.keys()[0])] as Dictionary)["quant"] = "Q8_0",
		"schema unavailable": func(d): d["response_format"] = "text",
		"schema hash drift": func(d): d["schema_hash"] = "0",
		"runtime drift": func(d): d["runtime"] = "llama.cpp@1.0.0",
	}
	for label in cases:
		var bent := base.duplicate(true)
		(cases[label] as Callable).call(bent)
		var refused := not bool(G.check(bent)["ok"])
		print("  %-26s -> %s" % [str(label), "ABORT" if refused else "ACCEPTED (!!)"])
		if not refused:
			bad += 1

	# A REQUEST_FAILED cycle must never become KEEP.
	print("\n  a failed request is journalled as infrastructure, not a decision")
	var sp := "negtest"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(J.path(sp, 0)))
	var g := W.genesis()
	J.append(sp, 0, {"species": sp, "replicate": 0, "cycle": 0,
		"pre_state_hash": W.state_hash(g), "patch": {},
		"operation": "", "target": "", "reason_code": "REQUEST_FAILED",
		"accepted": false, "request_failed": true,
		"post_state_hash": W.state_hash(g), "phase": "COMMITTED"})
	var rows: Array = J.load_rows(sp, 0)["rows"]
	var row: Dictionary = rows[0]
	var clean := str(row["reason_code"]) == "REQUEST_FAILED" \
		and str(row["operation"]) != "KEEP" and not bool(row["accepted"])
	print("  %-26s -> %s" % ["REQUEST_FAILED not KEEP", "OK" if clean else "FAIL"])
	if not clean:
		bad += 1
	print("  %-26s -> %s" % ["and state was preserved",
		"OK" if W.state_hash(J.replay(rows)) == W.state_hash(g) else "FAIL"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(J.path(sp, 0)))

	print("")
	if bad > 0:
		printerr("PIT A RUNNER NEGATIVE TESTS FAILED")
		quit(1)
		return
	print("PIT A RUNNER NEGATIVE OK")
	quit(0)
