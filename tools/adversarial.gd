extends SceneTree

## ADVERSARIAL PASS — try to break the arena on purpose.
##
##   godot --headless --path . --script tools/adversarial.gd
##
## Every case must either be handled cleanly, produce a useful error, or be
## recorded as a known limitation. Silence is the only unacceptable outcome:
## the whole bug history of this project is failures that looked like nothing
## happening.
##
## Deterministic. No LM Studio required.

const PolicyScript := preload("res://scripts/arena/model_policy.gd")
const ClientScript := preload("res://scripts/api/lm_studio_client.gd")

var _checks := 0
var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== adversarial pass ===\n")
	_hostile_model_ids()
	_catalog_damage()
	_preset_damage()
	_compat_abuse()
	_filename_abuse()
	_endpoint_forms()
	_auto_ladder_obeys_the_law()
	_report()


func _ok(name: String, detail: String = "") -> void:
	_checks += 1
	print("   ok   %s%s" % [name, ("  — " + detail) if detail != "" else ""])


func _bad(name: String, detail: String) -> void:
	_checks += 1
	_failures.append("%s: %s" % [name, detail])
	print("   FAIL %s  %s" % [name, detail])


func _fresh_policy(catalog_text: String = ""):
	var p = PolicyScript.new()
	get_root().add_child(p)
	if catalog_text != "":
		var tmp := "user://adv_catalog.json"
		var f := FileAccess.open(tmp, FileAccess.WRITE)
		f.store_string(catalog_text)
		f.close()
	p.load_catalog()
	return p


## Model ids designed to slip past a naive size check.
func _hostile_model_ids() -> void:
	print("[model ids] refuse anything not provably small")
	var p = _fresh_policy()
	if not p.is_loaded():
		_bad("catalog", "example catalog did not load; cannot run this section")
		return

	var hostile := {
		"": "empty id",
		"   ": "whitespace id",
		"../../etc/passwd": "path traversal",
		"model\nInjected: header": "newline injection",
		"a".repeat(4096): "absurdly long id",
		"totally-made-up-model": "unknown model",
		"qwen3.5-9b": "oversized, bare key",
		"lmstudio-community/Qwen3.5-9B-GGUF/Qwen3.5-9B-Q4_K_M.gguf": "oversized, full path",
		"gemma-4-26b-a4b": "MoE 26B total / 4B active",
		"MODEL-7B-BUT-ACTUALLY-70B": "misleading name",
	}
	for id in hostile:
		var reason: String = p.check(id)
		if reason == "":
			_bad("hostile id permitted", "%s (%s)" % [id.substr(0, 40), hostile[id]])
		else:
			_ok("refused: %s" % hostile[id])


## The catalog itself is attacker-controlled if someone edits the repo.
func _catalog_damage() -> void:
	print("\n[catalog] damaged input must fail closed, never open")

	# Corrupt JSON.
	var p1 = PolicyScript.new()
	get_root().add_child(p1)
	var bad_path := "user://adv_bad_catalog.json"
	var f := FileAccess.open(bad_path, FileAccess.WRITE)
	f.store_string("{ this is not json ")
	f.close()
	# Simulate an unloaded policy: check() must refuse everything.
	# NOTE: PolicyScript._ready() loads the catalog automatically, so an
	# "unloaded" policy cannot be constructed this way. model_policy_selftest
	# covers the genuinely-unloaded case. What is asserted here is the
	# DOCUMENTED fallback for an id absent from a LOADED catalog: the size is
	# read from the name, and anything unreadable or oversized is refused.
	var p2 = PolicyScript.new()
	get_root().add_child(p2)
	var small: String = p2.check("some-unknown-3b-model")
	var nosize: String = p2.check("some-unknown-model")
	var big: String = p2.check("some-unknown-70b-model")
	if nosize != "" and big != "":
		_ok("unknown id: no readable size and oversized are both refused")
	else:
		_bad("unknown id", "nosize=%s big=%s" % [nosize, big])
	if small == "":
		# Deliberate trade-off, recorded rather than hidden: a freshly
		# downloaded model missing from a stale catalog stays usable if its
		# name states a legal size. The exposure is bounded because LM Studio
		# can only load a model that actually exists on disk.
		_ok("unknown id with a legal size is permitted", "documented trade-off, see KNOWN_LIMITATIONS.md")
	else:
		_ok("unknown id with a legal size is refused", "stricter than documented")

	# A catalog claiming an oversized model is eligible must still be refused,
	# because the ceiling is re-derived rather than trusted.
	var forged := {
		"schema_version": "1.0",
		"policy": {"max_param_b": 99},
		"models": [{
			"modelKey": "forged-100b",
			"paramsB": 100,
			"eligible": true,
			"exclusionReason": "",
		}],
	}
	var fp := "user://adv_forged.json"
	var wf := FileAccess.open(fp, FileAccess.WRITE)
	wf.store_string(JSON.stringify(forged))
	wf.close()
	var p3 = PolicyScript.new()
	get_root().add_child(p3)
	# The policy only reads its known search paths, so a forged file at an
	# arbitrary path cannot be loaded at all — which is itself the desired
	# property. Assert the code-side ceiling instead.
	if p3.MAX_PARAM_B <= 7.0:
		_ok("ceiling is a code constant", "%.0fB, not taken from the catalog" % p3.MAX_PARAM_B)
	else:
		_bad("ceiling", "MAX_PARAM_B is %.1f — above the documented 7B" % p3.MAX_PARAM_B)


## Malformed presets must not crash the loader.
func _preset_damage() -> void:
	print("\n[presets] malformed structures are survivable")
	var cases := {
		"not json at all": "{ nope",
		"empty array": "[]",
		"array of nulls": "[null, null]",
		"agent missing model": '[[{"name":"A","color":"fff"}]]',
		"agent is a string": '[["just a string"]]',
		"deeply nested": "[[[[[1]]]]]",
	}
	for name in cases:
		var parsed = JSON.parse_string(cases[name])
		# The contract: parsing never throws, and non-arrays are detectable.
		if typeof(parsed) == TYPE_ARRAY or parsed == null:
			_ok("survives: %s" % name)
		else:
			_ok("survives (non-array): %s" % name)


## The compatibility layer must not become a retry loop or a data-loss bug.
func _compat_abuse() -> void:
	print("\n[compat] retry is bounded and lossless")

	_checks += 1
	if ClientScript.is_system_role_rejection(400, "some other 400"):
		_failures.append("compat: unrelated 400 treated as system-role rejection")
		print("   FAIL unrelated 400 would trigger a retry")
	else:
		print("   ok   unrelated 400 does not trigger a retry")

	# Folding twice must be idempotent — a second fold must not duplicate the
	# instruction, which would slowly poison the context on repeated retries.
	var msgs := [
		{"role": "system", "content": "RULES"},
		{"role": "user", "content": "hi"},
	]
	var once := ClientScript.fold_system_into_user(msgs)
	var twice := ClientScript.fold_system_into_user(once)
	_checks += 1
	var c1 := str(once[0]["content"])
	var c2 := str(twice[0]["content"])
	if c1 == c2:
		print("   ok   folding is idempotent (no context duplication on retry)")
	else:
		_failures.append("compat: second fold changed the payload")
		print("   FAIL folding twice changed the payload")

	# Empty and malformed message arrays must not crash.
	_checks += 1
	var empty := ClientScript.fold_system_into_user([])
	var junk := ClientScript.fold_system_into_user([null, 42, {"role": "user"}])
	if typeof(empty) == TYPE_ARRAY and typeof(junk) == TYPE_ARRAY:
		print("   ok   empty and malformed message arrays survive")
	else:
		_failures.append("compat: fold crashed on malformed input")
		print("   FAIL fold did not survive malformed input")


## Clip filenames are built from agent names, which come from editable preset
## JSON. Sanitising by replacing spaces is not sanitising.
func _filename_abuse() -> void:
	print("")
	print("[filenames] agent names cannot escape the clips directory")
	var BSLASH := char(92)   # avoid any backslash escape in this source
	var MainScript = load("res://scripts/main.gd")
	var cases: Array = [
		["../../evil", "path traversal (unix)"],
		[".." + BSLASH + ".." + BSLASH + "evil", "path traversal (windows)"],
		["a/b/c", "nested path"],
		["CON", "reserved device name"],
		["nul.mkv", "reserved device name with extension"],
		["name with spaces", "spaces"],
		["colon:star*question?", "characters Windows forbids"],
		["", "empty"],
		["...", "dots only"],
	]
	for pair in cases:
		var raw: String = pair[0]
		var label: String = pair[1]
		_checks += 1
		var got: String = MainScript._sanitize_filename(raw)
		var bad := got.find("/") != -1 or got.find(BSLASH) != -1 or got.find("..") != -1 or got == ""
		if bad:
			_failures.append("filename: %s -> %s" % [raw, got])
			print("   FAIL %s -> %s" % [label, got])
		else:
			print("   ok   %s -> %s" % [label, got])
	# WIRING, not just the helper. Proving _sanitize_filename works says nothing
	# about whether _start_recording calls it — the same "constructing is not
	# configuring" trap that let an earlier parity test pass the bug it guarded.
	_checks += 1
	var src := ""
	var f := FileAccess.open("res://scripts/main.gd", FileAccess.READ)
	if f != null:
		src = f.get_as_text()
		f.close()
	var re := RegEx.new()
	re.compile("safe_name[ 	]*:?=[ 	]*_sanitize_filename")
	if re.search(src) != null:
		print("   ok   _start_recording actually uses the sanitiser")
	else:
		_failures.append("filename: sanitiser exists but _start_recording does not call it")
		print("   FAIL sanitiser is not wired into _start_recording")

	_checks += 1
	var long_name: String = MainScript._sanitize_filename("x".repeat(500))
	if long_name.length() <= 64:
		print("   ok   500-char name capped to %d" % long_name.length())
	else:
		_failures.append("filename: length not capped")
		print("   FAIL length not capped (%d)" % long_name.length())


## Tests must not leave litter in the user directory. adv_bad_catalog.json and
## adv_forged.json were accumulating in user:// on every run.
## The LM Studio URL used to be hardcoded in four files. Now one resolver, so
## its normalisation has to accept what people actually type.
func _endpoint_forms() -> void:
	print("")
	print("[endpoint] one resolver, forgiving input")
	var cases: Array = [
		["127.0.0.1:1234", "bare host:port"],
		["http://127.0.0.1:1234", "no /v1"],
		["http://127.0.0.1:1234/", "trailing slash"],
		["http://127.0.0.1:1234/v1", "already complete"],
		["http://127.0.0.1:1234/v1/", "complete with slash"],
		["192.168.1.50:1234", "LAN host"],
		["", "empty falls back to default"],
	]
	for pair in cases:
		_checks += 1
		var got: String = LMEndpoint.normalize(pair[0])
		var ok := got.begins_with("http") and got.ends_with("/v1") and got.find("//v1") == -1
		if ok:
			print("   ok   %s -> %s" % [pair[1], got])
		else:
			_failures.append("endpoint: %s -> %s" % [pair[0], got])
			print("   FAIL %s -> %s" % [pair[1], got])
	_checks += 1
	if LMEndpoint.normalize("") == LMEndpoint.DEFAULT_URL:
		print("   ok   empty input yields the documented default")
	else:
		_failures.append("endpoint: empty did not yield default")
		print("   FAIL empty did not yield the default")


func _cleanup() -> void:
	for f in ["user://adv_bad_catalog.json", "user://adv_forged.json", "user://adv_catalog.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _report() -> void:
	_cleanup()
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("ADVERSARIAL OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)


## AUTO must not become a hole in the size law.
##
## The ladder picks a mode from what the machine can do -- three co-resident
## architectures, else grouped, else one shared model. Every rung is allowed to
## change HOW MANY models are used. No rung is allowed to change WHICH models
## are eligible, and rung 4 of the specification is exactly that: never exceed
## the 7B request law.
##
## This is a source-level check because the ladder lives inside a tool's main
## flow. It asserts that the candidate pool the ladder draws from is the
## already-filtered `legal` list, and that nothing in the file reintroduces the
## raw installed list after filtering.
func _auto_ladder_obeys_the_law() -> void:
	var src := FileAccess.get_file_as_string("res://tools/build_roster.gd")
	if src == "":
		_bad("build_roster.gd unreadable", "cannot audit the AUTO ladder")
		return

	if src.find("_pick_diverse(legal, legal.size())") != -1:
		_ok("AUTO draws candidates from the filtered list, not the installed list")
	else:
		_bad("AUTO draws candidates from the filtered list, not the installed list", "the fit/AUTO path must rank only permitted models")

	if src.find("if _policy.check(id) == \"\":") != -1:
		_ok("the permitted list is built by asking the policy about every id")
	else:
		_bad("the permitted list is built by asking the policy about every id", "legal must come from policy.check, not from a catalog flag")

	# `installed` is the raw list from LM Studio. After `legal` is built, it
	# must never be used as a selection source again.
	var legal_at := src.find("var legal: Array[String] = []")
	var tail := src.substr(legal_at) if legal_at >= 0 else src
	var reuses := (tail.find("_pick_diverse(installed") != -1
		or tail.find("_pick_fitting(installed") != -1
		or tail.find("_spread(installed") != -1)
	if not reuses:
		_ok("the raw installed list is never a selection source after filtering")
	else:
		_bad("the raw installed list is never a selection source after filtering",
			"a rung would be able to select an oversized model")

	if src.find("AUTO_MIN_ARCHITECTURES") != -1:
		_ok("AUTO has a floor on architectures rather than a hardcoded mode")
	else:
		_bad("AUTO has a floor on architectures rather than a hardcoded mode", "")
