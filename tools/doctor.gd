extends SceneTree

## SILICON ARENA DOCTOR — tell a stranger exactly what is wrong.
##
##   godot --headless --path . --script tools/doctor.gd
##
## Every check prints OK / WARN / FAIL with a concrete next action. Exits 0 when
## the arena can run, 1 when something would stop it.
##
## This exists because the failure modes are all silent by default: LM Studio
## not started looks identical to a bad roster, an unloaded catalog looks
## identical to a model that will not answer, and a fresh clone with no import
## looks like a broken project.

const PolicyScript := preload("res://scripts/arena/model_policy.gd")

## Single source of truth, overridable via SILICON_ARENA_LM_URL.
var LM_BASE := LMEndpoint.base_url()

var _fail := 0
var _warn := 0
var _models: Array = []


func _init() -> void:
	print("\nSILICON ARENA DOCTOR")
	print("--------------------")
	_check_godot()
	_check_import()
	_check_ffmpeg()
	_check_writable()
	_fetch_models()


func _ok(label: String, detail: String) -> void:
	print("%-18s OK    %s" % [label, detail])


func _warned(label: String, detail: String, fix: String) -> void:
	_warn += 1
	print("%-18s WARN  %s" % [label, detail])
	print("%-18s       fix: %s" % ["", fix])


func _bad(label: String, detail: String, fix: String) -> void:
	_fail += 1
	print("%-18s FAIL  %s" % [label, detail])
	print("%-18s       fix: %s" % ["", fix])


func _check_godot() -> void:
	_ok("Godot", "%s" % Engine.get_version_info().get("string", "?"))


func _check_import() -> void:
	if FileAccess.file_exists("res://.godot/global_script_class_cache.cfg"):
		_ok("Project import", "class registry present")
	else:
		_bad("Project import", "no global class cache — class_name types will not resolve",
			"run: godot --headless --editor --quit --path .")


func _check_ffmpeg() -> void:
	var out: Array = []
	var code := OS.execute("where", ["ffmpeg"], out, true)
	if code == 0 and not out.is_empty() and str(out[0]).strip_edges() != "":
		_ok("FFmpeg", "clip recording available")
	else:
		_warned("FFmpeg", "not on PATH — F10 clip recording will be disabled",
			"install ffmpeg and add it to PATH (everything else still works)")


func _check_writable() -> void:
	var dir := OS.get_user_data_dir()
	var probe := dir.path_join("doctor_write_probe.tmp")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		_bad("User data dir", "cannot write to %s" % dir, "check permissions on that folder")
		return
	f.store_string("ok")
	f.close()
	DirAccess.remove_absolute(probe)
	_ok("User data dir", "writable (%s)" % dir)


func _fetch_models() -> void:
	var http := HTTPRequest.new()
	get_root().add_child(http)
	await process_frame
	http.timeout = 8.0
	http.request_completed.connect(_on_models)
	var err := http.request(LM_BASE + "/models")
	if err != OK:
		_bad("LM Studio", "could not issue request to %s" % LM_BASE,
			"start LM Studio and enable the local server on port 1234")
		_finish()


func _on_models(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_bad("LM Studio", "no response from %s (result=%d code=%d)" % [LM_BASE, result, code],
			"start LM Studio, then Developer > Start Server (port 1234)")
		_check_catalog_only()
		_finish()
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("data"):
		_bad("LM Studio", "reachable but /v1/models returned an unexpected body",
			"check the LM Studio version supports the OpenAI-compatible API")
		_finish()
		return

	_ok("LM Studio", "%s" % LM_BASE)
	for m in parsed["data"]:
		_models.append(str(m.get("id", "")))
	if _models.is_empty():
		_bad("Installed models", "LM Studio reports zero models",
			"download at least one model at or under 7B in LM Studio")
	else:
		_ok("Installed models", "%d" % _models.size())

	_check_policy_and_roster()
	_finish()


func _check_catalog_only() -> void:
	var policy = PolicyScript.new()
	get_root().add_child(policy)
	policy.load_catalog()
	if policy.is_loaded():
		_ok("Model catalog", "%d models, ceiling %.0fB" % [policy.eligible_count(), policy.MAX_PARAM_B])
	else:
		_bad("Model catalog", "not loaded — every request will be refused (fail-closed)",
			"ensure config/model-catalog.example.json exists, or generate config/model-catalog.v1.json")


func _check_policy_and_roster() -> void:
	var policy = PolicyScript.new()
	get_root().add_child(policy)
	policy.load_catalog()

	if not policy.is_loaded():
		_bad("Model catalog", "not loaded — every request will be refused (fail-closed)",
			"ensure config/model-catalog.example.json exists")
		return
	_ok("Model catalog", "%d eligible, ceiling %.0fB" % [policy.eligible_count(), policy.MAX_PARAM_B])

	# How many INSTALLED models are actually legal to run here?
	var legal: Array = []
	for id in _models:
		if policy.check(id) == "":
			legal.append(id)
	if legal.is_empty():
		_bad("Eligible <=%.0fB" % policy.MAX_PARAM_B, "0 of %d installed models are permitted" % _models.size(),
			"install a model at or under %.0fB, or regenerate the catalog from `lms ls --json`" % policy.MAX_PARAM_B)
	elif legal.size() < 5:
		_warned("Eligible <=%.0fB" % policy.MAX_PARAM_B, "%d of %d installed models permitted" % [legal.size(), _models.size()],
			"the arena wants 5 agents; it will reuse models or run shorter rosters")
	else:
		_ok("Eligible <=%.0fB" % policy.MAX_PARAM_B, "%d of %d installed models permitted" % [legal.size(), _models.size()])

	# Does the default roster actually resolve on THIS machine?
	# Check the preset the arena will ACTUALLY load. user:// wins when present,
	# which is exactly what build_roster.gd writes. Reading res:// here reported
	# "Roster 1/5" immediately after a good roster had been generated — a
	# diagnostic that lies is worse than no diagnostic.
	var raw := ""
	var source := "res://presets.json"
	if FileAccess.file_exists("user://presets.json"):
		source = "user://presets.json"
	var f := FileAccess.open(source, FileAccess.READ)
	if f != null:
		raw = f.get_as_text()
		f.close()
	var presets = JSON.parse_string(raw)
	if typeof(presets) != TYPE_ARRAY or presets.is_empty():
		_bad("Roster", "presets.json missing or unreadable", "restore presets.json from the repository")
		return

	var total := 0
	var good := 0
	var problems: Array[String] = []
	for agent in presets[0]:
		if typeof(agent) != TYPE_DICTIONARY:
			continue
		total += 1
		var model := str(agent.get("model", ""))
		var reason: String = policy.check(model)
		var installed := _models.has(model) or _models.has(policy.resolve_key(model))
		if reason != "":
			problems.append("%s: %s" % [str(agent.get("name", "?")), reason])
		elif not installed:
			problems.append("%s: %s is legal but NOT installed" % [str(agent.get("name", "?")), model])
		else:
			good += 1
	if good == total and total > 0:
		_ok("Roster", "%d/%d valid (%s)" % [good, total, source])
	else:
		_warned("Roster", "%d/%d usable in preset 0 of %s" % [good, total, source],
			"run: godot --headless --path . --script tools/build_roster.gd")
		for p in problems:
			print("%-18s       - %s" % ["", p])


func _finish() -> void:
	print("--------------------")
	if _fail > 0:
		print("NOT READY — %d blocking problem(s), %d warning(s)\n" % [_fail, _warn])
		quit(1)
	elif _warn > 0:
		print("READY (with %d warning(s))\n" % _warn)
		quit(0)
	else:
		print("READY\n")
		quit(0)
