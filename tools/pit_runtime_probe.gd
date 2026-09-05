extends SceneTree

## Does the fail-closed gate bite a REAL runtime, not a synthetic dictionary?
##
##   godot --headless --path . --script tools/pit_runtime_probe.gd -- --probe
##   godot --headless --path . --script tools/pit_runtime_probe.gd -- --sabotage
##
## Pre-registered in docs/EXPERIMENT_PIT_A.md at 15f30e9, amended at e4faf3e.
##
## NO GENERATION. This reads the runtime's inventory and its own report of what
## it loaded. Nothing is asked of a model, and no PIT outcome is produced.
##
## THE GAP THIS CLOSES. pit_gate.gd was proven against hand-built dictionaries.
## That establishes the logic and nothing about whether the fields it checks can
## actually be populated from this machine, or whether a real drift produces a
## real refusal. A gate that has only ever refused inputs written by its own
## author is a gate with an untested mouth.
##
## OBSERVED, NEVER REQUESTED. Every field below comes from what the runtime
## REPORTS, not from what was asked for. Those agree right up until they do not,
## and the entire point of a fail-closed gate is to catch the moment they stop.

const G := preload("res://scripts/arena/pit_gate.gd")

var LM_BASE := LMEndpoint.base_url()
var _http: HTTPRequest
var _mode := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if str(a) == "--probe":
			_mode = "probe"
		if str(a) == "--sabotage":
			_mode = "sabotage"
	if _mode == "":
		printerr("need --probe or --sabotage")
		quit(2)
		return

	_http = HTTPRequest.new()
	get_root().add_child(_http)
	await process_frame
	_http.timeout = 120.0

	var observed := await _observe()
	if observed.is_empty():
		printerr("could not read the runtime inventory; is LM Studio up?")
		quit(2)
		return

	if _mode == "probe":
		_report_probe(observed)
	else:
		_report_sabotage(observed)


## Build the gate's input from the runtime's own report.
func _observe() -> Dictionary:
	var models := {}
	_http.cancel_request()
	if _http.request(LM_BASE.replace("/v1", "") + "/api/v0/models") != OK:
		return {}
	var res: Array = await _http.request_completed
	if int(res[1]) != 200:
		return {}
	var p = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(p) != TYPE_DICTIONARY:
		return {}
	for m in p.get("data", []):
		var id := str(m.get("id", ""))
		if not G.SPECIES.has(id):
			continue
		models[id] = {
			"arch": str(m.get("arch", "")),
			"quant": str(m.get("quantization", "")),
			# Effective context is what the runtime reports for a LOADED model.
			# For an unloaded one this is the model's maximum, which is exactly
			# the drift the gate exists to refuse -- so it is passed through
			# unmodified rather than clamped to what we wanted it to be.
			"context": int(m.get("loaded_context_length",
				m.get("max_context_length", -1))),
			"state": str(m.get("state", "")),
			"type": str(m.get("type", "")),
		}
	return {
		"runtime": _runtime_id(),
		"response_format": G.RESPONSE_FORMAT,
		"schema_hash": G.schema_hash(),
		"constraint_mode": G.CONSTRAINT_MODE,
		"models": models,
	}


## The active runtime, read from the CLI rather than assumed.
func _runtime_id() -> String:
	var out: Array = []
	var lms := OS.get_environment("USERPROFILE") + "/.lmstudio/bin/lms.exe"
	if OS.execute(lms, ["runtime", "ls"], out, true) != 0 or out.is_empty():
		return "<unreadable>"
	# The selected row carries a check mark, but that glyph does not survive the
	# console codepage intact through OS.execute -- the first version matched on
	# it literally and reported "<none selected>" for a runtime that WAS
	# selected. Detect the marker by position instead: strip the engine name,
	# and if anything non-blank sits between it and the format column, this is
	# the selected row, whatever byte the check mark arrived as.
	for raw_line in str(out[0]).split("\n"):
		var line := raw_line.strip_edges()
		if not line.begins_with("llama.cpp"):
			continue
		var engine := line.split(" ")[0].strip_edges()
		var rest := line.substr(engine.length())
		var fmt := rest.find("GGUF")
		if fmt == -1:
			continue
		if rest.substr(0, fmt).strip_edges() != "":
			return engine
	return "<none selected>"


func _report_probe(observed: Dictionary) -> void:
	print("=== PIT A live runtime probe (no generation) ===\n")
	print("  runtime         %s" % str(observed["runtime"]))
	print("  response_format %s" % str(observed["response_format"]))
	print("  schema_hash     %s" % str(observed["schema_hash"]).substr(0, 16))
	print("  constraint_mode %s\n" % str(observed["constraint_mode"]))
	var models: Dictionary = observed["models"]
	print("  %-30s %-11s %-8s %-9s %s" % ["ID", "ARCH", "QUANT", "CTX", "STATE"])
	print("  " + "-".repeat(72))
	for id in G.SPECIES:
		if not models.has(id):
			print("  %-30s *** ABSENT FROM RUNTIME ***" % id)
			continue
		var m: Dictionary = models[id]
		print("  %-30s %-11s %-8s %-9s %s" % [id, str(m["arch"]), str(m["quant"]),
			str(m["context"]), str(m["state"])])

	var verdict: Dictionary = G.check(observed)
	print("\n  GATE: %s" % ("PASS" if bool(verdict["ok"]) else "REFUSE"))
	for f in verdict["failures"]:
		print("    - %s" % str(f))
	print("\n  A refusal here is CORRECT unless every species is loaded at 8192.")
	print("  Context is reported as the model maximum until it is loaded, and")
	print("  the gate is supposed to refuse that rather than assume our intent.")
	quit(0)


## Live sabotage: bend one real observed field at a time and require a refusal.
func _report_sabotage(observed: Dictionary) -> void:
	print("=== PIT A gate sabotage against a REAL observed config ===\n")
	var bad := 0
	var models: Dictionary = observed["models"]
	if models.size() < G.SPECIES.size():
		printerr("  only %d of %d species visible; run --probe first"
			% [models.size(), G.SPECIES.size()])
		quit(2)
		return

	# A baseline the gate accepts, built from the REAL arch/quant the runtime
	# reported, with only context normalised to the frozen 8192.
	var base := observed.duplicate(true)
	for id in (base["models"] as Dictionary):
		((base["models"] as Dictionary)[id] as Dictionary)["context"] = G.EXPECTED_CONTEXT
	base["runtime"] = G.EXPECTED_RUNTIME
	var ok0: Dictionary = G.check(base)
	print("  real arch/quant + frozen runtime and context -> %s"
		% ("PASS" if bool(ok0["ok"]) else "REFUSE " + str(ok0["failures"])))
	if not bool(ok0["ok"]):
		bad += 1

	var first := str(G.SPECIES.keys()[0])
	var cases: Array = [
		["wrong runtime selected", func(d): d["runtime"] = "llama.cpp-win-x86_64-nvidia-cuda12-avx2@2.9.0"],
		["context reported as 16384", func(d): ((d["models"] as Dictionary)[first] as Dictionary)["context"] = 16384],
		["a species removed", func(d): (d["models"] as Dictionary).erase(first)],
		["schema hash mutated", func(d): d["schema_hash"] = "deadbeef"],
		["one model claims Q8_0", func(d): ((d["models"] as Dictionary)[first] as Dictionary)["quant"] = "Q8_0"],
		["constraint made per-species", func(d): d["constraint_mode"] = "per_species"],
	]
	for c in cases:
		var bent := base.duplicate(true)
		(c[1] as Callable).call(bent)
		var v: Dictionary = G.check(bent)
		var refused := not bool(v["ok"])
		print("  %-28s -> %s" % [str(c[0]), "REFUSED" if refused else "PASSED (!!)"])
		if not refused:
			printerr("    FAIL: the gate accepted a drifted configuration")
			bad += 1

	print("")
	if bad > 0:
		printerr("PIT GATE LIVE SABOTAGE FAILED")
		quit(1)
		return
	print("PIT GATE LIVE OK")
	quit(0)
