extends Node
class_name CinematicBridge

## Emits CinematicEvent v1.0 from the arena to the Ghostloop overlay.
##
## The contract lives in extinct_os/src/events/schema.ts. This file is the
## Godot half. Field names, priority bands and durations are mirrored here
## deliberately rather than derived, because the two processes ship separately
## and a silent drift must show up as a self-test failure, not as a dead
## overlay during a stream.
##
## Two sinks, both optional and independently failable:
##   - JSONL on disk  -> user://cinematic/<match_id>.jsonl  (replayable fixture)
##   - WebSocket      -> ws://127.0.0.1:8971                (live overlay)
##
## Hard rule: nothing in here may raise, block, or slow a turn. The arena is
## the product; this is a spectator feed. Every sink failure degrades to a
## disabled sink and a printed reason.

const SCHEMA_VERSION := "1.0"
const DEFAULT_PORT := 8971
const MAX_CLIENTS := 4
const LOG_DIR := "user://cinematic"

## Mirrors DEFAULT_PRIORITY in schema.ts. Higher interrupts lower.
const PRIORITY := {
	"MODEL_LOADED": 15,
	"ROUND_START": 20,
	"ROUND_END": 20,
	"DOOM_STAGE": 25,
	"AGENT_SPEAK": 35,
	"AGENT_ARRIVE": 40,
	"CONFIDENCE_SPIKE": 50,
	"SENTIMENT_HOSTILE": 55,
	"ALLIANCE_FORMED": 55,
	"ALLIANCE_BROKEN": 60,
	"BETRAYAL": 65,
	"MODEL_ERROR": 65,
	"HEALTH_CRITICAL": 70,
	"DESPERATION": 75,
	"CROWN_TRANSFER": 80,
	"FINAL_TWO": 85,
	"AGENT_ELIMINATED": 90,
	"MATCH_END": 100,
}

## Mirrors DEFAULT_DURATION in schema.ts, in milliseconds.
const DURATION := {
	"MODEL_LOADED": 2600,
	"ROUND_START": 1800,
	"ROUND_END": 1800,
	"DOOM_STAGE": 2600,
	"AGENT_SPEAK": 2200,
	"AGENT_ARRIVE": 2400,
	"CONFIDENCE_SPIKE": 1600,
	"SENTIMENT_HOSTILE": 2000,
	"ALLIANCE_FORMED": 2000,
	"ALLIANCE_BROKEN": 2200,
	"BETRAYAL": 3000,
	"MODEL_ERROR": 1800,
	"HEALTH_CRITICAL": 1800,
	"DESPERATION": 2600,
	"CROWN_TRANSFER": 3000,
	"FINAL_TWO": 3200,
	"AGENT_ELIMINATED": 2800,
	"MATCH_END": 5000,
}

var enabled := true
var log_to_disk := true
var serve_websocket := true
var port := DEFAULT_PORT

var _match_id := ""
var _match_seed := 0
var _counter := 0
var _round := 1
var _mode := "NORMAL"

var _log: FileAccess = null
var _log_path := ""
var _server: TCPServer = null
var _peers: Array[WebSocketPeer] = []
var _pending: Array[WebSocketPeer] = []

var _emitted := 0
var _dropped := 0
var _last_error := ""

## Test seam. Below zero the real engine clock is used, which is what the arena
## always wants. Fixture generators set it so a synthetic match has realistic
## pacing instead of stamping every event with the same tick.
var clock_override_ms := -1


func _ready() -> void:
	set_process(serve_websocket)


## Begin a match. Safe to call repeatedly; each call rotates the log file.
func begin_match(seed_value: int = 0) -> void:
	if not enabled:
		return
	_match_seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())
	_match_id = "match-%d" % _match_seed
	_counter = 0
	_round = 1
	_mode = "NORMAL"
	_open_log()
	if serve_websocket:
		_open_server()


func set_round(r: int) -> void:
	_round = maxi(1, r)


func set_mode(m: String) -> void:
	_mode = m if m in ["NORMAL", "BEEF", "AGAPE"] else "NORMAL"


## The single emit path. `values` and `metadata` are optional.
func emit_event(
	type_name: String,
	agent_id: String = "",
	target_agent_id: String = "",
	quote: String = "",
	values: Dictionary = {},
	tags: Array = [],
	metadata: Dictionary = {}
) -> Dictionary:
	if not enabled:
		return {}
	if not PRIORITY.has(type_name):
		push_warning("[cinematic] unknown event type '%s' — not emitted" % type_name)
		_dropped += 1
		return {}

	_counter += 1
	# Deterministic per-event seed: same match seed + same ordinal => same
	# visuals on replay. Mixed so consecutive events don't render as near-twins.
	var ev_seed := (_match_seed ^ (_counter * 0x9E3779B1)) & 0xFFFFFFFF

	var event := {
		"schema_version": SCHEMA_VERSION,
		"event_id": "%s-%04d" % [_match_id, _counter],
		"seed": ev_seed,
		"timestamp_ms": Time.get_ticks_msec() if clock_override_ms < 0 else clock_override_ms,
		"match_id": _match_id,
		"type": type_name,
		"priority": int(PRIORITY[type_name]),
		"duration_ms": int(DURATION[type_name]),
		"round": _round,
		"mode": _mode,
		"values": _clean_values(values),
		"tags": _clean_tags(tags),
		"metadata": metadata if metadata is Dictionary else {},
	}
	if agent_id != "":
		event["agent_id"] = agent_id
	if target_agent_id != "":
		event["target_agent_id"] = target_agent_id
	if quote != "":
		# The overlay only ever shows the head of a quote; sending a 2KB reply
		# over the wire every turn is waste.
		event["quote"] = quote.strip_edges().substr(0, 240)

	_sink(event)
	_emitted += 1
	return event


## Registers the roster so the overlay can colour agents correctly.
## Mirrors AgentVisualIdentity in extinct_os/src/types/index.ts.
func announce_roster(agents: Array) -> void:
	if not enabled:
		return
	for a in agents:
		if not (a is Dictionary):
			continue
		var col: Color = a.get("color", Color.WHITE)
		emit_event(
			"MODEL_LOADED",
			str(a.get("name", "")),
			"",
			"",
			{"confidence": float(a.get("confidence", 0.5))},
			["roster"],
			{
				"model_name": str(a.get("model", "")),
				"primary_color": "#" + col.to_html(false),
				"secondary_color": "#" + col.darkened(0.4).to_html(false),
				"element": str(a.get("element", "fire")),
			}
		)


func stats() -> Dictionary:
	return {
		"emitted": _emitted,
		"dropped": _dropped,
		"peers": _peers.size(),
		"log_path": _log_path,
		"last_error": _last_error,
	}


func status_line() -> String:
	return "CINE %d ev  %d peer%s" % [_emitted, _peers.size(), "" if _peers.size() == 1 else "s"]


# ── sinks ──────────────────────────────────────────────────────────────────

func _sink(event: Dictionary) -> void:
	var line := JSON.stringify(event)
	if _log != null:
		_log.store_line(line)
		# Flushed per event on purpose: a crashed arena must still leave a
		# replayable log of everything up to the crash.
		_log.flush()
	if _peers.is_empty():
		return
	for p in _peers:
		if p.get_ready_state() == WebSocketPeer.STATE_OPEN:
			p.send_text(line)


func _open_log() -> void:
	if not log_to_disk:
		return
	if _log != null:
		_log.close()
		_log = null
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))
	if not DirAccess.dir_exists_absolute(LOG_DIR):
		DirAccess.make_dir_recursive_absolute(LOG_DIR)
	_log_path = "%s/%s.jsonl" % [LOG_DIR, _match_id]
	_log = FileAccess.open(_log_path, FileAccess.WRITE)
	if _log == null:
		_last_error = "log open failed: %s" % error_string(FileAccess.get_open_error())
		log_to_disk = false
		push_warning("[cinematic] " + _last_error)


func _open_server() -> void:
	if _server != null:
		return
	_server = TCPServer.new()
	var err := _server.listen(port, "127.0.0.1")
	if err != OK:
		_last_error = "port %d unavailable: %s" % [port, error_string(err)]
		push_warning("[cinematic] " + _last_error + " — live overlay disabled, disk log unaffected")
		_server = null
		serve_websocket = false
		set_process(false)


func _process(_delta: float) -> void:
	if _server == null:
		return

	while _server.is_connection_available():
		if _peers.size() + _pending.size() >= MAX_CLIENTS:
			_server.take_connection()  # refuse politely by dropping
			break
		var conn := _server.take_connection()
		if conn == null:
			break
		var peer := WebSocketPeer.new()
		if peer.accept_stream(conn) == OK:
			_pending.append(peer)

	# Handshake in progress
	for i in range(_pending.size() - 1, -1, -1):
		var p: WebSocketPeer = _pending[i]
		p.poll()
		match p.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				_pending.remove_at(i)
				_peers.append(p)
			WebSocketPeer.STATE_CLOSED:
				_pending.remove_at(i)

	# Live peers
	for i in range(_peers.size() - 1, -1, -1):
		var p: WebSocketPeer = _peers[i]
		p.poll()
		if p.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_peers.remove_at(i)
			continue
		# Drain inbound; the overlay is not allowed to command the arena, so
		# anything it sends is read and discarded to keep the buffer clear.
		while p.get_available_packet_count() > 0:
			p.get_packet()


func _exit_tree() -> void:
	for p in _peers:
		p.close()
	_peers.clear()
	_pending.clear()
	if _server != null:
		_server.stop()
		_server = null
	if _log != null:
		_log.close()
		_log = null


# ── coercion ───────────────────────────────────────────────────────────────

## clamp01 / clampSigned parity with schema.ts. Keys absent from `values` stay
## absent, matching the TS side's `undefined`.
func _clean_values(v: Dictionary) -> Dictionary:
	var out := {}
	for key in ["health", "confidence", "aggression", "doom", "surprise"]:
		if v.has(key):
			out[key] = clampf(_finite(v[key]), 0.0, 1.0)
	for key in ["sentiment", "relationship_delta"]:
		if v.has(key):
			out[key] = clampf(_finite(v[key]), -1.0, 1.0)
	return out


func _clean_tags(tags: Array) -> Array:
	var out := []
	for t in tags:
		if t is String and t != "":
			out.append(t)
	return out


func _finite(x) -> float:
	var f := float(x) if (x is float or x is int) else 0.0
	return 0.0 if (is_nan(f) or is_inf(f)) else f
