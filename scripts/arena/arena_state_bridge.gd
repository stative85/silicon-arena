extends Node
class_name ArenaStateBridge

## Publishes ArenaState v1 — persistent match state.
##
## SEPARATE SOCKET, SEPARATE CONTRACT from CinematicBridge on purpose. The
## cinematic channel may coalesce, interrupt and drop; a missed effect costs
## one animation. This channel may never drop: a missed delta means the roster
## shows the wrong crown holder for the rest of the match.
##
## Protocol:
##   - a full snapshot on every client connect, and on demand
##   - sequenced deltas for ordinary updates
##   - the client re-requests a snapshot on any gap; we never let it guess
##
## Read-only for STATE. Inbound text is drained and ignored except two verbs:
##   RESNAP     ask for a fresh snapshot
##   SAY <text> a person said something out loud in the room
##
## Neither writes arena state. SAY is emitted as a signal and the arena decides
## what to do with it, exactly as it decides what to do with a model reply. The
## overlay still cannot command the arena.

const SCHEMA_VERSION := "1.0"
const DEFAULT_PORT := 8972
const MAX_CLIENTS := 4
const RESNAP_REQUEST := "RESNAP"
## A human speaking into the room. Prefix only; the arena decides what, if
## anything, to do with it.
const SAY_PREFIX := "SAY "
const MAX_SAY_CHARS := 240

signal client_connected()
## Emitted when a person types something. The listener owns the consequences:
## this bridge never changes arena state on the overlay's say-so.
signal human_said(text: String)

var enabled := true
var port := DEFAULT_PORT

var _server: TCPServer = null
var _peers: Array[WebSocketPeer] = []
var _pending: Array[WebSocketPeer] = []

var _sequence := 0
var _match_id := ""
var _live := false
var _last_error := ""
var _snapshots_sent := 0
var _deltas_sent := 0

## The authoritative state. Godot owns this; the overlay only mirrors it.
var state := {}


func _ready() -> void:
	set_process(enabled)


func begin_match(match_id: String, live: bool) -> void:
	_match_id = match_id
	_live = live
	_sequence = 0
	state = {
		"topic": "",
		"round": 1,
		"phase": "starting",
		"doom": 0.0,
		"current_speaker": "",
		"crown_holder": "",
		"agents": [],
		"runtimes": [],
		"relationships": [],
		"last_action": "",
		"last_message": "",
		"error_state": "",
	}
	if _server == null:
		_open_server()


func _open_server() -> void:
	_server = TCPServer.new()
	var err := _server.listen(port, "127.0.0.1")
	if err != OK:
		_last_error = "port %d unavailable: %s" % [port, error_string(err)]
		push_warning("[arena-state] " + _last_error)
		_server = null
		set_process(false)
		return
	print("ARENA_STATE LISTENING %d" % port)


func set_agents(agents: Array) -> void:
	state["agents"] = agents


func set_runtimes(runtimes: Array) -> void:
	state["runtimes"] = runtimes


## Merge a partial change into the authoritative state and publish a delta.
## `agent_patches` is { agent_id: {field: value} }.
func publish_delta(
	changes: Dictionary = {},
	agent_patches: Dictionary = {},
	runtime_patches: Dictionary = {},
	relationships = null
) -> void:
	if not enabled:
		return

	for k in changes:
		state[k] = changes[k]

	for aid in agent_patches:
		for a in state["agents"]:
			if a is Dictionary and str(a.get("agent_id", "")) == str(aid):
				for f in agent_patches[aid]:
					a[f] = agent_patches[aid][f]
				break

	for rid in runtime_patches:
		for r in state["runtimes"]:
			if r is Dictionary and str(r.get("runtime_id", "")) == str(rid):
				for f in runtime_patches[rid]:
					r[f] = runtime_patches[rid][f]
				break

	if relationships != null:
		state["relationships"] = relationships

	_sequence += 1
	var msg := {
		"schema_version": SCHEMA_VERSION,
		"message_type": "delta",
		"match_id": _match_id,
		"sequence": _sequence,
		"timestamp_ms": Time.get_ticks_msec(),
		"changes": changes,
		"agents": agent_patches,
		"runtimes": runtime_patches,
		"relationships": relationships,
	}
	_broadcast(JSON.stringify(msg))
	_deltas_sent += 1


func build_snapshot() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"message_type": "snapshot",
		"match_id": _match_id,
		"sequence": _sequence,
		"timestamp_ms": Time.get_ticks_msec(),
		"topic": state.get("topic", ""),
		"round": state.get("round", 1),
		"phase": state.get("phase", "idle"),
		"doom": state.get("doom", 0.0),
		"current_speaker": state.get("current_speaker", ""),
		"crown_holder": state.get("crown_holder", ""),
		"live": _live,
		"agents": state.get("agents", []),
		"runtimes": state.get("runtimes", []),
		"relationships": state.get("relationships", []),
		"last_action": state.get("last_action", ""),
		"last_message": state.get("last_message", ""),
		"error_state": state.get("error_state", ""),
		# Rung 15, ADDITIVE. Older consumers ignore an unknown field, so this
		# needs no version bump. The FULL proof travels on every snapshot: a
		# client that connects late, or reconnects after a gap, must be able to
		# reconstruct the entire timeline without relying on its own memory.
		"continuity_proof": state.get("continuity_proof", null),
	}


## Publish a full snapshot to everyone. Used on connect, on request, and after
## anything that makes incremental reasoning unsafe.
func publish_snapshot() -> void:
	if not enabled:
		return
	_broadcast(JSON.stringify(build_snapshot()))
	_snapshots_sent += 1


func _send_snapshot_to(peer: WebSocketPeer) -> void:
	if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		peer.send_text(JSON.stringify(build_snapshot()))
		_snapshots_sent += 1


func _broadcast(line: String) -> void:
	for p in _peers:
		if p.get_ready_state() == WebSocketPeer.STATE_OPEN:
			p.send_text(line)


func stats() -> Dictionary:
	return {
		"sequence": _sequence,
		"peers": _peers.size(),
		"snapshots": _snapshots_sent,
		"deltas": _deltas_sent,
		"last_error": _last_error,
	}


func has_client() -> bool:
	return not _peers.is_empty()


func _process(_delta: float) -> void:
	if _server == null:
		return

	while _server.is_connection_available():
		var conn := _server.take_connection()
		if conn == null:
			break
		if _peers.size() + _pending.size() >= MAX_CLIENTS:
			break
		var peer := WebSocketPeer.new()
		if peer.accept_stream(conn) == OK:
			_pending.append(peer)

	for i in range(_pending.size() - 1, -1, -1):
		var p: WebSocketPeer = _pending[i]
		p.poll()
		match p.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				_pending.remove_at(i)
				_peers.append(p)
				# Every new client starts from a full snapshot, never mid-stream.
				_send_snapshot_to(p)
				client_connected.emit()
				print("ARENA_STATE CLIENT_CONNECTED")
			WebSocketPeer.STATE_CLOSED:
				_pending.remove_at(i)

	for i in range(_peers.size() - 1, -1, -1):
		var p: WebSocketPeer = _peers[i]
		p.poll()
		if p.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_peers.remove_at(i)
			continue
		while p.get_available_packet_count() > 0:
			var text := p.get_packet().get_string_from_utf8().strip_edges()
			# The ONLY inbound verb. Anything else is discarded: this channel is
			# read-only and the overlay is not allowed to drive the arena.
			if text == RESNAP_REQUEST:
				_send_snapshot_to(p)
			elif text.begins_with(SAY_PREFIX):
				# A person talking is INPUT, not authority. It is flattened to a
				# single line and capped, so it cannot smuggle structure into a
				# prompt, and it is emitted as a signal — the arena decides
				# whether and how to use it. The overlay still cannot command
				# anything, which is the property that matters.
				var said := text.substr(SAY_PREFIX.length())
				said = said.replace("
", " ").replace("", " ").replace("	", " ")
				said = said.strip_edges()
				if said.length() > MAX_SAY_CHARS:
					said = said.substr(0, MAX_SAY_CHARS)
				if said != "":
					human_said.emit(said)


func _exit_tree() -> void:
	for p in _peers:
		p.close()
	_peers.clear()
	_pending.clear()
	if _server != null:
		_server.stop()
		_server = null


## Rung 15: publish the canonical proof payload.
##
## Godot owns this. The UI formats it and may never recompute a decision from
## it. Every call republishes a full snapshot as well, so the proof state is
## recoverable by anyone who joins afterwards.
func publish_continuity_proof(payload: Dictionary) -> void:
	if not enabled:
		return
	state["continuity_proof"] = payload
	publish_delta({"continuity_proof": payload})
	publish_snapshot()
