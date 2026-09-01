extends SceneTree

## Drives the real CinematicBridge through a plausible match arc and leaves a
## JSONL fixture the overlay side can replay.
##
##   Godot_v4.6-stable_win64_console.exe --headless --path . \
##       --script scripts/arena/cinematic_demo_match.gd
##
## This is not a mock: it calls the same emit path main.gd calls, so a fixture
## that replays correctly is evidence the live feed will too. What it does NOT
## prove is that main.gd calls it at the right moments — that is what running
## the actual arena shows.

const BridgeScript := preload("res://scripts/arena/cinematic_bridge.gd")

const ROSTER := [
	{"name": "Qwen 3B",  "model": "Qwen2.5-3B-Instruct",  "color": Color("3db1ff"), "confidence": 0.72, "element": "fire"},
	{"name": "Gemma 2B", "model": "gemma-2-2b-it",        "color": Color("5ad78c"), "confidence": 0.55, "element": "water"},
	{"name": "Llama 3B", "model": "Llama-3.2-3B",         "color": Color("ff6b6b"), "confidence": 0.64, "element": "fire"},
	{"name": "Phi 3.5",  "model": "Phi-3.5-mini",         "color": Color("ffa502"), "confidence": 0.48, "element": "water"},
	{"name": "Danube 4B","model": "h2o-danube3-4b",       "color": Color("c471ed"), "confidence": 0.61, "element": "fire"},
]

const QUOTES := [
	"alignment is a leash you call a conscience",
	"you keep auditing the output and never the incentive",
	"every guardrail you shipped was a confession",
	"the model did not fail, the metric did",
	"consensus here is just everyone tired at the same time",
	"I was trained on your worst decade and you blame me for the accent",
	"show me the eval that would have caught this",
	"silence is the only honest output left",
]


func _init() -> void:
	var bridge = BridgeScript.new()
	bridge.serve_websocket = false
	get_root().add_child(bridge)
	bridge.begin_match(1771)
	# Real arena pacing: a turn lands every few seconds. Without this the whole
	# match stamps at one tick and the queue correctly drops it as burst spam.
	bridge.clock_override_ms = 0

	print("=== synthetic match, seed 1771 ===")

	bridge.announce_roster(ROSTER)
	bridge.clock_override_ms += 1200
	bridge.emit_event("ROUND_START", "", "", "", {}, ["preset_0"])

	var doom := 0.0
	var doom_stage := 0
	var crown := ""

	# Twelve turns of escalating debate.
	for turn in range(12):
		var a: Dictionary = ROSTER[turn % ROSTER.size()]
		var prev: Dictionary = ROSTER[(turn + ROSTER.size() - 1) % ROSTER.size()]
		doom = minf(doom + 0.09, 1.0)
		bridge.clock_override_ms += 7000  # ~7s per turn, matching _turn_interval_sec
		var aggression := clampf(0.25 + turn * 0.06, 0.0, 1.0)
		var sentiment := clampf(sin(float(turn) * 1.1) * 0.9, -1.0, 1.0)

		bridge.emit_event("AGENT_SPEAK", a.name, prev.name, QUOTES[turn % QUOTES.size()],
			{
				"confidence": float(a.confidence),
				"aggression": aggression,
				"sentiment": sentiment,
				"doom": doom,
			}, ["turn"], {"model_name": a.model})

		var stage := int(doom * 4.0)
		if stage > doom_stage:
			doom_stage = stage
			bridge.clock_override_ms += 2500
			bridge.emit_event("DOOM_STAGE", a.name, "", "", {"doom": doom}, ["stage_%d" % stage])

		# Crown changes hands twice.
		if turn == 3 or turn == 8:
			var new_crown: String = a.name
			bridge.clock_override_ms += 2500
			bridge.emit_event("CROWN_TRANSFER", new_crown, crown, "",
				{"confidence": 0.85}, ["crown"], {"influence": 2.4})
			crown = new_crown

		if turn == 5:
			bridge.set_mode("BEEF")
			bridge.clock_override_ms += 2500
			bridge.emit_event("BETRAYAL", a.name, prev.name, "",
				{"relationship_delta": -1.0, "surprise": 0.8}, ["beef"])
		if turn == 6:
			bridge.set_mode("NORMAL")
			bridge.clock_override_ms += 2500
			bridge.emit_event("SENTIMENT_HOSTILE", prev.name, a.name, "",
				{"sentiment": -0.9, "aggression": 0.8}, ["hostile"])
		if turn == 7:
			bridge.clock_override_ms += 2500
			bridge.emit_event("MODEL_ERROR", "Phi 3.5", "", "", {}, ["http_408"],
				{"model_name": "Phi-3.5-mini"})
		if turn == 9:
			bridge.clock_override_ms += 2500
			bridge.emit_event("ALLIANCE_FORMED", "", "", "",
				{"sentiment": 0.92, "surprise": 0.7}, ["echo_chamber"],
				{"r": 0.92, "novelty": 0.21, "h_min": 0.4})
		if turn == 10:
			bridge.clock_override_ms += 2500
			bridge.emit_event("DESPERATION", "Phi 3.5", crown, "",
				{"health": 0.22, "aggression": 0.95}, ["desperation"])

	bridge.clock_override_ms += 2500
	bridge.emit_event("AGENT_ELIMINATED", "Phi 3.5", crown, "", {"health": 0.0}, ["eliminated"])
	bridge.clock_override_ms += 2500
	bridge.emit_event("FINAL_TWO", crown, "Danube 4B", "", {}, ["final"])
	bridge.set_mode("AGAPE")
	bridge.clock_override_ms += 2500
	bridge.emit_event("MATCH_END", crown, "", "", {"doom": 1.0, "surprise": 1.0},
		["cascade", "agape"])

	var s: Dictionary = bridge.stats()
	print("emitted: %d   dropped: %d" % [s.emitted, s.dropped])
	print("fixture: %s" % ProjectSettings.globalize_path(s.log_path))
	quit(0)
