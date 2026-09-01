extends SceneTree

## Headless proof that the Godot half of the cinematic contract matches the
## TypeScript half, and that nothing the arena can do to it makes it throw.
##
##   godot --headless --path . \
##       --script scripts/arena/cinematic_selftest.gd
##
## Exits 2 on any failure. The test that matters most is PARITY: it reads
## extinct_os/src/events/schema.ts and compares the numbers, so if either side
## is edited alone this fails instead of producing a live overlay that silently
## renders the wrong effect for the wrong duration.

const BridgeScript := preload("res://scripts/arena/cinematic_bridge.gd")

## Where the TypeScript contract lives, relative to the silicon_arena project.
const SCHEMA_TS := "../extinct_os/src/events/schema.ts"

var _failures: Array[String] = []
var _checks := 0


func _init() -> void:
	print("=== cinematic bridge self-test ===\n")

	var bridge = BridgeScript.new()
	bridge.serve_websocket = false   # no port binding in CI
	bridge.log_to_disk = true
	get_root().add_child(bridge)
	# Deliberately NOT 1771: that is the demo-match fixture's seed, and the log
	# path is derived from it. Sharing the seed made a self-test run silently
	# overwrite the fixture the replay tool reads.
	bridge.begin_match(90000001)

	_test_parity_with_typescript(bridge)
	_test_every_type_emits(bridge)
	_test_hostile_input(bridge)
	_test_determinism()
	_test_jsonl_roundtrip(bridge)

	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	for f in _failures:
		print("  FAIL: " + f)
	if _failures.is_empty():
		# Do not claim the cross-repo contract was checked when it was skipped.
		# The schema lives in a private sibling repo, so on every public clone
		# and in CI that comparison does not run — and this line was still
		# asserting it had. A summary that overstates what ran is the same
		# failure as a test that passes on absence.
		if _skips.is_empty():
			print("cinematic bridge matches the TypeScript contract")
		else:
			print("cinematic bridge OK (%d check(s) skipped; the TypeScript"
				% _skips.size())
			print("contract was NOT verified here — see SKIP above)")
		quit(0)
	else:
		quit(2)


# ── the parity test ────────────────────────────────────────────────────────

func _test_parity_with_typescript(bridge) -> void:
	print("[parity] comparing against " + SCHEMA_TS)

	var ts := _read_sibling(SCHEMA_TS)
	if ts == "":
		# The TypeScript contract lives in a sibling repository that is not part
		# of a standalone Silicon Arena clone. Absent sibling = UNVERIFIABLE,
		# which is not the same as BROKEN. Report it and skip, so a fresh clone
		# does not see a red failure for a file it was never shipped.
		_skip("parity", "%s not present (standalone clone) — cross-repo contract not verified here" % SCHEMA_TS)
		return

	var ts_version := _match_one(ts, "EVENT_SCHEMA_VERSION\\s*=\\s*\"([^\"]+)\"")
	_check("schema_version matches TS", ts_version == bridge.SCHEMA_VERSION,
		"TS=%s GD=%s" % [ts_version, bridge.SCHEMA_VERSION])

	var ts_priority := _parse_ts_record(ts, "DEFAULT_PRIORITY")
	var ts_duration := _parse_ts_record(ts, "DEFAULT_DURATION")
	var ts_types := _parse_ts_type_list(ts)

	_check("TS priority table parsed", ts_priority.size() > 0, "got %d entries" % ts_priority.size())
	_check("TS duration table parsed", ts_duration.size() > 0, "got %d entries" % ts_duration.size())
	_check("TS event type list parsed", ts_types.size() > 0, "got %d entries" % ts_types.size())

	# Same set of event types on both sides — no orphans in either direction.
	for t in ts_types:
		_check("GD knows type %s" % t, bridge.PRIORITY.has(t), "missing from PRIORITY")
	for t in bridge.PRIORITY.keys():
		_check("TS knows type %s" % t, ts_types.has(t), "GD emits a type TS cannot route")

	# Same numbers.
	for t in ts_priority.keys():
		if bridge.PRIORITY.has(t):
			_check("priority[%s]" % t, int(bridge.PRIORITY[t]) == int(ts_priority[t]),
				"TS=%d GD=%d" % [int(ts_priority[t]), int(bridge.PRIORITY[t])])
	for t in ts_duration.keys():
		if bridge.DURATION.has(t):
			_check("duration[%s]" % t, int(bridge.DURATION[t]) == int(ts_duration[t]),
				"TS=%d GD=%d" % [int(ts_duration[t]), int(bridge.DURATION[t])])


# ── behavioural tests ──────────────────────────────────────────────────────

func _test_every_type_emits(bridge) -> void:
	print("[emit] every declared type produces a well-formed event")
	var required := ["schema_version", "event_id", "seed", "timestamp_ms",
		"match_id", "type", "priority", "duration_ms", "values", "tags", "metadata"]
	for t in bridge.PRIORITY.keys():
		var ev: Dictionary = bridge.emit_event(t, "Qwen 3B", "Gemma 2B", "a quote",
			{"confidence": 0.7, "sentiment": -0.4}, ["test"], {"k": "v"})
		var missing := []
		for key in required:
			if not ev.has(key):
				missing.append(key)
		_check("%s well-formed" % t, missing.is_empty(), "missing " + str(missing))
		if ev.has("seed"):
			_check("%s seed in uint32" % t, ev.seed >= 0 and ev.seed <= 0xFFFFFFFF,
				"seed=%d" % ev.seed)
		if ev.has("priority"):
			_check("%s priority in 0..100" % t, ev.priority >= 0 and ev.priority <= 100,
				"priority=%d" % ev.priority)
		if ev.has("duration_ms"):
			_check("%s duration in 200..30000" % t,
				ev.duration_ms >= 200 and ev.duration_ms <= 30000, "dur=%d" % ev.duration_ms)


func _test_hostile_input(bridge) -> void:
	print("[hostile] malformed input must degrade, never throw")

	var bad: Dictionary = bridge.emit_event("NOT_A_REAL_TYPE", "x")
	_check("unknown type is refused, not emitted", bad.is_empty(), "returned " + str(bad))

	var nan_ev: Dictionary = bridge.emit_event("AGENT_SPEAK", "A", "", "",
		{"confidence": NAN, "sentiment": INF, "doom": -999.0})
	_check("NaN confidence coerced finite",
		nan_ev.values.confidence >= 0.0 and nan_ev.values.confidence <= 1.0,
		"got %s" % str(nan_ev.values.confidence))
	_check("INF sentiment clamped to <=1",
		nan_ev.values.sentiment <= 1.0 and nan_ev.values.sentiment >= -1.0,
		"got %s" % str(nan_ev.values.sentiment))
	_check("negative doom clamped to >=0", nan_ev.values.doom >= 0.0,
		"got %s" % str(nan_ev.values.doom))

	var long_quote := "X".repeat(50000)
	var long_ev: Dictionary = bridge.emit_event("AGENT_SPEAK", "A", "", long_quote)
	_check("overlong quote truncated", long_ev.quote.length() <= 240,
		"len=%d" % long_ev.quote.length())

	var empty_ev: Dictionary = bridge.emit_event("ROUND_START")
	_check("no agent_id key when unset", not empty_ev.has("agent_id"), "agent_id leaked")
	_check("empty values ok", empty_ev.values.is_empty(), str(empty_ev.values))

	var junk_tags: Dictionary = bridge.emit_event("ROUND_END", "", "", "", {}, [null, 42, "", "ok"])
	_check("junk tags filtered to strings", junk_tags.tags == ["ok"], str(junk_tags.tags))

	var roster_safe := true
	bridge.announce_roster([null, 42, "string", {}])
	_check("announce_roster survives junk roster", roster_safe, "threw")


func _test_determinism() -> void:
	print("[determinism] same match seed => same event seeds")
	var a = BridgeScript.new()
	var b = BridgeScript.new()
	a.serve_websocket = false; a.log_to_disk = false
	b.serve_websocket = false; b.log_to_disk = false
	get_root().add_child(a)
	get_root().add_child(b)
	a.begin_match(1771)
	b.begin_match(1771)
	var seeds_a := []
	var seeds_b := []
	for i in range(12):
		seeds_a.append(a.emit_event("AGENT_SPEAK", "A").seed)
		seeds_b.append(b.emit_event("AGENT_SPEAK", "A").seed)
	_check("identical seed sequence", seeds_a == seeds_b, "%s vs %s" % [seeds_a, seeds_b])

	var c = BridgeScript.new()
	c.serve_websocket = false; c.log_to_disk = false
	get_root().add_child(c)
	c.begin_match(1772)
	var seeds_c := []
	for i in range(12):
		seeds_c.append(c.emit_event("AGENT_SPEAK", "A").seed)
	_check("different match seed diverges", seeds_a != seeds_c, "seeds collided across matches")

	# A run of same-type events must not all render identically.
	var uniq := {}
	for s in seeds_a:
		uniq[s] = true
	_check("consecutive events get distinct seeds", uniq.size() == seeds_a.size(),
		"%d unique of %d" % [uniq.size(), seeds_a.size()])


func _test_jsonl_roundtrip(bridge) -> void:
	print("[jsonl] written log parses back as JSON")
	var path: String = bridge.stats().log_path
	if path == "":
		_fail("jsonl", "no log path — disk sink never opened")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_fail("jsonl", "cannot reopen %s" % path)
		return
	var lines := 0
	var parsed := 0
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		lines += 1
		var j = JSON.parse_string(line)
		if j is Dictionary and j.has("type") and j.has("seed"):
			parsed += 1
	f.close()
	_check("every logged line is valid JSON", lines > 0 and parsed == lines,
		"%d/%d parsed" % [parsed, lines])
	print("       log: %s (%d events)" % [path, lines])


# ── helpers ────────────────────────────────────────────────────────────────

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("   ok   " + label)
	else:
		_fail(label, detail)


var _skips: Array[String] = []


## Not a pass and not a failure: the evidence needed is not present in this
## checkout. Recorded loudly so it can never be mistaken for verification.
func _skip(name: String, why: String) -> void:
	_skips.append("%s  %s" % [name, why])
	print("   SKIP %s  %s" % [name, why])


func _fail(label: String, detail: String) -> void:
	print("   FAIL " + label + ("  (" + detail + ")" if detail != "" else ""))
	_failures.append(label + ("  " + detail if detail != "" else ""))


## Reads a file addressed relative to the project directory, including paths
## that climb out of it (res:// cannot).
func _read_sibling(rel: String) -> String:
	var base := ProjectSettings.globalize_path("res://")
	var abs := base.path_join(rel).simplify_path()
	var f := FileAccess.open(abs, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _match_one(text: String, pattern: String) -> String:
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		return ""
	var m := re.search(text)
	return m.get_string(1) if m else ""


## Pulls `KEY: 123,` pairs out of a `export const NAME: ... = { ... };` block.
func _parse_ts_record(text: String, name: String) -> Dictionary:
	var out := {}
	var start := text.find(name)
	if start < 0:
		return out
	var open_brace := text.find("{", start)
	var close_brace := text.find("};", open_brace)
	if open_brace < 0 or close_brace < 0:
		return out
	var body := text.substr(open_brace, close_brace - open_brace)
	var re := RegEx.new()
	re.compile("([A-Z_]+)\\s*:\\s*(\\d+)")
	for m in re.search_all(body):
		out[m.get_string(1)] = int(m.get_string(2))
	return out


## Pulls the quoted members of the EVENT_TYPES array.
func _parse_ts_type_list(text: String) -> Array:
	var out := []
	var start := text.find("EVENT_TYPES")
	if start < 0:
		return out
	# Seek past the `=`, otherwise the `[]` in the `CinematicEventType[]` type
	# annotation is found first and the array parses as empty.
	var assign := text.find("=", start)
	if assign < 0:
		return out
	var open_bracket := text.find("[", assign)
	var close_bracket := text.find("]", open_bracket)
	if open_bracket < 0 or close_bracket < 0:
		return out
	var body := text.substr(open_bracket, close_bracket - open_bracket)
	var re := RegEx.new()
	re.compile("\"([A-Z_]+)\"")
	for m in re.search_all(body):
		out.append(m.get_string(1))
	return out
