extends SceneTree

## Proves the two entry points configure the same load-bearing runtime.
##
##   godot --headless --path . \
##       --script scripts/arena/entrypoint_parity_selftest.gd
##
## WHY THIS EXISTS
##
## Silicon Arena has two entry points:
##   scripts/main.gd              the visual app
##   scripts/arena/live_match.gd  the headless live path
##
## Three separate production bugs turned out to be one bug wearing three hats:
## live_match.gd configured something, main.gd inherited a default.
##
##   model_policy         injected on live, never on main -> the 7B size law
##                        was dead code on the scene that actually runs, and a
##                        stale preset walked a 9B model into an 8GB card.
##   request_timeout_sec  set on live, left at 20s on main -> every cold model
##                        swap read as a timeout failure instead of a load.
##   (plus the duplicate inner classes that stopped main.gd parsing at all)
##
## Fixing those individually is maintenance. This kills the class: if a
## load-bearing setting is configured on one entry point and not the other,
## and nobody declared that difference intentional, the build fails here
## instead of in a match six weeks from now.
##
## Deliberately a SOURCE-level check. The two entry points cannot be
## instantiated side by side, so comparing what they say is the only honest
## thing to compare.

const MAIN_PATH := "res://scripts/main.gd"
const LIVE_PATH := "res://scripts/arena/live_match.gd"

## Settings that MUST be configured on both entry points.
##
## Each pattern requires a RECEIVER — "something.prop =" — not a bare name.
## That is not pedantry: the original bug was main.gd constructing a
## ModelPolicy and never handing it to the client. A loose "model_policy ="
## match is satisfied by the broken code and the test passes the bug.
const REQUIRED_ON_BOTH := [
	{
		"pattern": "[A-Za-z0-9_]+\\.model_policy\\s*=[^=]",
		"label": "size law injected into the LM client",
		"why": "without it the 7B ceiling is dead code on that path",
	},
	{
		"pattern": "[A-Za-z0-9_]+\\.request_timeout_sec\\s*=[^=]",
		"label": "turn timeout sized for a cold model swap",
		"why": "the 20s default fails every JIT load and reads as a dead model",
	},
]

## Invariants that must hold inside a single entry point. Unlike the parity
## checks above, these guard against a value being reintroduced from elsewhere:
## a persisted config, a UI control, a copy-paste.
const INVARIANTS := [
	{
		"file": "res://scripts/main.gd",
		"pattern": "MIN_STALL_TIMEOUT_SEC[ \t]*:=[ \t]*COLD_LOAD_TIMEOUT_SEC",
		"label": "stall floor is DERIVED from the cold-load allowance",
		"why": "a saved arena_builder_config.json reintroduced a 40s watchdog and killed turns that were only loading",
	},
	{
		"file": "res://scripts/api/lm_studio_client.gd",
		"pattern": "_detach_timer[(]deadline_timer[)]",
		"label": "deadline timers are detached before anything they captured is freed",
		"why": "a timeout lambda captures the HTTPRequest and Godot resolves captures before the body, so a completed[0] guard cannot prevent 'Lambda capture was freed'",
	},
	{
		"file": "res://scripts/api/lm_studio_client.gd",
		"pattern": "_do_chat[.]call_deferred",
		"label": "the compat retry is deferred, not issued from the freed callback",
		"why": "starting the retry synchronously inside the completion lambda of a queue_freed HTTPRequest is a use-after-free",
	},
	{
		"file": "res://scripts/main.gd",
		"pattern": "MIN_STALL_TIMEOUT_SEC[)]",
		"label": "persisted stall_timeout_sec is clamped on load",
		"why": "without the clamp a stale config silently overrides the constant",
	},
]

## Facts that must be written down exactly ONCE. Each entry names a literal
## that may appear only in its owning file; anywhere else is a second source of
## truth waiting to disagree.
const SINGLE_SOURCE := [
	{
		"literal": "127.0.0.1:1234",
		"owner": "res://scripts/api/lm_endpoint.gd",
		"label": "LM Studio endpoint is defined in exactly one place",
		"why": "it was hardcoded in four files, so SILICON_ARENA_LM_URL was ignored by some of them",
	},
]


## Differences that ARE intentional. Each needs a reason, in writing.
## An entry here is a decision; a missing entry is a bug.
const ALLOWED_DIVERGENCE := {
	"scar_lattice": "main.gd retires the legacy ledger via LEGACY_MEMORY_LEDGER := false; scar_lattice is live-path only and is the canonical engine",
	"arena_state_bridge": "live-path state export for the browser proof harness; the visual app owns its own state",
	"cinematic_live_driver": "drives the websocket overlay for the live path only",
	"coherence_engine": "visual app only",
	"arena_builder_panel": "visual app UI only",
	"splat_engine": "visual app rendering only",
}

var _checks := 0
var _failures: Array[String] = []


func _init() -> void:
	print("=== entry-point parity (main.gd vs live_match.gd) ===\n")

	var main_src := _read(MAIN_PATH)
	var live_src := _read(LIVE_PATH)
	if main_src == "" or live_src == "":
		_fail("could not read both entry points — refusing to pass")
		_report()
		return

	_check_required(main_src, live_src)
	_check_invariants()
	_check_single_source()
	_check_drift(main_src, live_src)
	_report()


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


func _check_required(main_src: String, live_src: String) -> void:
	for item in REQUIRED_ON_BOTH:
		var in_main := _matches(main_src, item["pattern"])
		var in_live := _matches(live_src, item["pattern"])
		_checks += 1
		if in_main and in_live:
			print("  OK        %s" % item["label"])
		else:
			var missing := "main.gd" if not in_main else "live_match.gd"
			_fail("%s — not configured in %s. %s" % [item["label"], missing, item["why"]])


func _check_invariants() -> void:
	for item in INVARIANTS:
		var src := _read(item["file"])
		_checks += 1
		if src != "" and _matches(src, item["pattern"]):
			print("  OK        %s" % item["label"])
		else:
			_fail("%s — missing in %s. %s" % [item["label"], item["file"], item["why"]])


## A literal that belongs to one file must not appear in runtime code elsewhere.
## Comments, tests and the owner itself are exempt: the point is to catch a
## second DEFINITION, not a mention.
func _check_single_source() -> void:
	var runtime := [
		"res://scripts/main.gd",
		"res://scripts/arena/live_match.gd",
		"res://tools/doctor.gd",
		"res://tools/build_roster.gd",
		"res://tools/prove.gd",
	]
	for item in SINGLE_SOURCE:
		_checks += 1
		var offenders: Array[String] = []
		for path in runtime:
			if path == item["owner"]:
				continue
			var src := _read(path)
			for line in src.split("
"):
				var t := line.strip_edges()
				if t.begins_with("#") or t.begins_with("##"):
					continue
				if t.find(item["literal"]) != -1:
					offenders.append("%s: %s" % [path.get_file(), t.substr(0, 70)])
		if offenders.is_empty():
			print("  OK        %s" % item["label"])
		else:
			_fail("%s — also defined in: %s. %s"
				% [item["label"], ", ".join(offenders), item["why"]])


## Anything live_match.gd preloads that main.gd never mentions is drift unless
## it is allow-listed with a stated reason.
func _check_drift(main_src: String, live_src: String) -> void:
	var re := RegEx.new()
	re.compile("preload\\(\"res://scripts/([A-Za-z0-9_/]+)\\.gd\"\\)")
	for m in re.search_all(live_src):
		var path_part := m.get_string(1)
		var symbol := path_part.get_slice("/", path_part.get_slice_count("/") - 1)
		_checks += 1
		if main_src.find(symbol) != -1:
			continue
		if ALLOWED_DIVERGENCE.has(symbol):
			print("  ALLOWED   %s — %s" % [symbol, ALLOWED_DIVERGENCE[symbol]])
			continue
		_fail("live_match.gd uses \"%s\" and main.gd never mentions it. If deliberate, add it to ALLOWED_DIVERGENCE with a reason. If not, this is the drift bug again." % symbol)


## True when the source contains a real assignment matching `pattern`.
func _matches(src: String, pattern: String) -> bool:
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		return false
	return re.search(src) != null


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("  FAIL      %s" % msg)


func _report() -> void:
	print("\n%d checks, %d failures" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("PARITY OK — both entry points configure the same load-bearing runtime.")
		quit(0)
	else:
		print("PARITY BROKEN:")
		for f in _failures:
			print("  - %s" % f)
		quit(1)
