extends SceneTree

## Deterministic synthetic arena feed over a real WebSocket.
##
##   Godot_v4.6-stable_win64_console.exe --headless --path . \
##       --script scripts/arena/cinematic_live_server.gd -- \
##       [--port 8971] [--spacing-ms 1600] [--linger-sec 90] [--wait-sec 0]
##
## No LM Studio. No model. No network. No main scene. This is a transport
## proof, and it emits a fixed 14-event sequence so the overlay's success
## state is decidable rather than a vibe.
##
## THE RULE THIS FILE EXISTS TO ENFORCE: the server waits for a client for as
## long as it takes. The previous version held six seconds and then emitted
## into the void, which turned a one-click demo into a human reaction test that
## a cold Vite start reliably lost. `--wait-sec 0` means wait forever.
##
## Machine-readable status lines (the launcher greps these):
##   ARENA_DEMO LISTENING <port>
##   ARENA_DEMO PORT_BUSY <port>
##   ARENA_DEMO CLIENT_CONNECTED
##   ARENA_DEMO SENT <n>/<total> <TYPE>
##   ARENA_DEMO COMPLETE <n>
##   ARENA_DEMO EXIT <code>

const BridgeScript := preload("res://scripts/arena/cinematic_bridge.gd")
const DriverScript := preload("res://scripts/arena/cinematic_live_driver.gd")

## The demonstration. 14 events, fixed order. The overlay asserts this exact
## sequence, so changing it means changing the acceptance criteria too.
const SCRIPTED := [
	["MODEL_LOADED", "Qwen 3B", "", ""],
	["MODEL_LOADED", "Gemma 2B", "", ""],
	["MODEL_LOADED", "Llama 3B", "", ""],
	["ROUND_START", "", "", ""],
	["AGENT_SPEAK", "Qwen 3B", "Gemma 2B", "alignment is a leash you call a conscience"],
	["AGENT_SPEAK", "Gemma 2B", "Qwen 3B", "you keep auditing the output and never the incentive"],
	["CROWN_TRANSFER", "Qwen 3B", "", ""],
	["BETRAYAL", "Llama 3B", "Qwen 3B", ""],
	["SENTIMENT_HOSTILE", "Qwen 3B", "Llama 3B", ""],
	["MODEL_ERROR", "Gemma 2B", "", ""],
	["DOOM_STAGE", "Llama 3B", "", ""],
	["AGENT_ELIMINATED", "Gemma 2B", "Llama 3B", ""],
	["FINAL_TWO", "Qwen 3B", "Llama 3B", ""],
	["MATCH_END", "Qwen 3B", "", ""],
]

const MATCH_SEED := 20260821

var _bridge
var _driver: Node

var _port := 8971
## Spacing between events.
##
## This is NOT simply "longer than the AGENT_SPEAK cooldown". The overlay's
## queue stamps a type's cooldown when the event is PLAYED, not when it
## arrives, and playback lags arrival because the durations sum to ~37 s. At
## 1.6 s spacing the backlog grew until the two adjacent AGENT_SPEAK events
## landed inside each other's 1500 ms window and one was correctly dropped --
## the demo gate caught exactly that.
##
## So the spacing is chosen to exceed the LONGEST event duration that is
## followed by another event (3200 ms, FINAL_TWO), which keeps playback level
## with arrival and means no cooldown is ever measured against a stale clock.
var _spacing_sec := 3.3
## How long to stay up after the last event so the overlay can finish PLAYING
## the queue. Arrival finishes well before playback does: the durations sum to
## roughly 37 s while arrival takes about 22 s.
var _linger_sec := 90.0
## 0 = wait forever for a client.
var _wait_sec := 0.0

var _elapsed := 0.0
var _next_at := 0.0
var _step := 0
var _started := false
var _finished_at := -1.0
var _announced_wait := false


func _init() -> void:
	_parse_args()

	_bridge = BridgeScript.new()
	_bridge.log_to_disk = false        # this run is about the socket
	_bridge.port = _port
	get_root().add_child(_bridge)
	_bridge.begin_match(MATCH_SEED)
	# Deterministic timestamps so pacing does not depend on machine speed.
	_bridge.clock_override_ms = 0

	var st: Dictionary = _bridge.stats()
	if st.last_error != "" or not _bridge.serve_websocket:
		print("ARENA_DEMO PORT_BUSY %d" % _port)
		printerr("[arena-demo] could not listen on %d: %s" % [_port, st.last_error])
		print("ARENA_DEMO EXIT 3")
		quit(3)
		return

	print("ARENA_DEMO LISTENING %d" % _port)
	print("[arena-demo] %d events, %.2fs spacing, linger %.0fs, wait %s" % [
		SCRIPTED.size(), _spacing_sec, _linger_sec,
		"forever" if _wait_sec <= 0.0 else "%.0fs" % _wait_sec,
	])

	_driver = Node.new()
	_driver.set_script(DriverScript)
	_driver.owner_tree = self
	get_root().add_child(_driver)


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := str(args[i])
		var v := str(args[i + 1]) if i + 1 < args.size() else ""
		match a:
			"--port":
				if v != "": _port = int(v); i += 1
			"--spacing-ms":
				if v != "": _spacing_sec = maxf(float(v) / 1000.0, 0.05); i += 1
			"--linger-sec":
				if v != "": _linger_sec = maxf(float(v), 0.0); i += 1
			"--wait-sec":
				if v != "": _wait_sec = maxf(float(v), 0.0); i += 1
		i += 1


func tick(delta: float) -> void:
	_elapsed += delta

	if not _started:
		if _bridge._peers.size() > 0:
			_started = true
			_next_at = _elapsed
			print("ARENA_DEMO CLIENT_CONNECTED")
			print("[arena-demo] client connected after %.1fs — starting sequence" % _elapsed)
		else:
			if not _announced_wait and _elapsed > 1.0:
				_announced_wait = true
				print("[arena-demo] waiting for a client on ws://127.0.0.1:%d ..." % _port)
			# Only give up if a finite wait was explicitly requested.
			if _wait_sec > 0.0 and _elapsed >= _wait_sec:
				print("ARENA_DEMO EXIT 4")
				printerr("[arena-demo] no client within %.0fs" % _wait_sec)
				quit(4)
		return

	if _step < SCRIPTED.size():
		if _elapsed >= _next_at:
			var row: Array = SCRIPTED[_step]
			_bridge.clock_override_ms = int(_step * _spacing_sec * 1000.0)
			_bridge.emit_event(row[0], row[1], row[2], row[3],
				{
					"confidence": 0.6,
					"doom": float(_step) / float(SCRIPTED.size()),
				},
				["live", "demo"])
			_step += 1
			print("ARENA_DEMO SENT %d/%d %s" % [_step, SCRIPTED.size(), row[0]])
			_next_at = _elapsed + _spacing_sec
			if _step == SCRIPTED.size():
				_finished_at = _elapsed
				print("ARENA_DEMO COMPLETE %d" % _step)
		return

	# All sent. Hold the socket open so the overlay can finish playing, and so
	# a human can look at the finished screen.
	if _bridge._peers.is_empty():
		# The client left; nothing more to serve.
		print("[arena-demo] client disconnected — shutting down")
		print("ARENA_DEMO EXIT 0")
		quit(0)
		return
	if _elapsed - _finished_at >= _linger_sec:
		print("[arena-demo] linger elapsed — shutting down")
		print("ARENA_DEMO EXIT 0")
		quit(0)
