extends SceneTree

## Deterministic config + preset validation. No LM Studio required.
##
##   Godot --headless --path . --script tools/verify_configs.gd
##
## Prints "CONFIGS OK" on success. Anything else means a failure, and every
## failure names the file and the reason.
##
## What this catches that a human review does not:
##   - a shipped preset naming a model above the 7B ceiling, which would make a
##     fresh clone watch the policy refuse most of its own default roster
##   - malformed JSON in any config the arena loads at boot
##   - a catalog whose declared policy disagrees with the code's ceiling

const PolicyScript := preload("res://scripts/arena/model_policy.gd")

var _fail: Array[String] = []
var _checks := 0


func _init() -> void:
	print("=== config + preset validation ===")
	_check_required_files()
	_check_json_parses()
	_check_catalog_policy()
	_check_presets_legal()
	_report()


## Files a fresh clone must have for the documented instructions to work.
const REQUIRED := [
	"res://README.md", "res://SETUP.md", "res://LICENSE", "res://project.godot",
	"res://presets.json", "res://config/model-catalog.example.json",
	"res://scripts/main.gd", "res://scripts/arena/model_policy.gd",
]


func _check_required_files() -> void:
	for path in REQUIRED:
		_checks += 1
		if not FileAccess.file_exists(path):
			_bad("required file missing: %s" % path)


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


func _bad(msg: String) -> void:
	_fail.append(msg)
	print("  FAIL  " + msg)


## Every JSON file the project ships must actually parse.
func _check_json_parses() -> void:
	for path in ["res://presets.json", "res://config/model-catalog.example.json"]:
		_checks += 1
		var raw := _read(path)
		if raw == "":
			_bad("%s missing or empty" % path)
			continue
		if JSON.parse_string(raw) == null:
			_bad("%s is not valid JSON" % path)


## The catalog's declared ceiling must match the ceiling the code enforces.
## A catalog that says 13 while the code says 7 is a trap for the next reader.
func _check_catalog_policy() -> void:
	_checks += 1
	var raw := _read("res://config/model-catalog.example.json")
	if raw == "":
		return
	var d = JSON.parse_string(raw)
	if typeof(d) != TYPE_DICTIONARY or not d.has("policy"):
		_bad("example catalog has no policy block")
		return
	var declared = d["policy"].get("max_param_b", null)
	if declared == null:
		_bad("example catalog policy has no max_param_b")
		return
	var policy = PolicyScript.new()
	if float(declared) != float(policy.MAX_PARAM_B):
		_bad("catalog declares max_param_b=%s but ModelPolicy.MAX_PARAM_B=%s"
			% [str(declared), str(policy.MAX_PARAM_B)])


## Every model named by every shipped preset must be permitted by the policy.
## This is the check that would have caught a default roster where four of five
## agents were illegal under the project's own law.
func _check_presets_legal() -> void:
	var raw := _read("res://presets.json")
	if raw == "":
		return
	var presets = JSON.parse_string(raw)
	if typeof(presets) != TYPE_ARRAY:
		_bad("presets.json is not an array")
		return

	var policy = PolicyScript.new()
	get_root().add_child(policy)
	# _ready() is deferred; load explicitly so the catalog is present before the
	# first check. Without this every model reports "no catalog" and the
	# validator measures its own start-up order instead of the presets.
	policy.load_catalog()

	var idx := 0
	for preset in presets:
		if typeof(preset) != TYPE_ARRAY:
			idx += 1
			continue
		for agent in preset:
			if typeof(agent) != TYPE_DICTIONARY:
				continue
			var model := str(agent.get("model", ""))
			var who := str(agent.get("name", "?"))
			_checks += 1
			if model == "":
				_bad("preset %d agent %s has no model" % [idx, who])
				continue
			var reason: String = policy.check(model)
			if reason != "":
				_bad("preset %d agent %s (%s): %s" % [idx, who, model, reason])
		idx += 1


func _report() -> void:
	print("--- %d checks, %d failure(s) ---" % [_checks, _fail.size()])
	if _fail.is_empty():
		print("CONFIGS OK")
		quit(0)
	else:
		quit(1)
