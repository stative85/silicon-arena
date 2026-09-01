extends SceneTree

## Live arena: five real logical agents driven by a real local model.
##
##   Godot_v4.6-stable_win64_console.exe --headless --path . \
##       --script scripts/arena/live_match.gd -- \
##       [--turns 10] [--wait-sec 0] [--timeout-sec 90]
##
## Authority chain: LM Studio -> THIS (Godot) -> bridges -> extinct_os UI.
## Godot owns identities, model assignment, prompts, responses, crown,
## confidence, alliances, elimination, errors and event generation. The overlay
## only mirrors what is published here.
##
## Reuses the proven pieces rather than reinventing them:
##   scripts/api/lm_studio_client.gd   queued HTTP client, timeouts, CoT-safe
##   scripts/sentiment.gd              agreement scoring
##   scripts/arena/model_policy.gd     the 7B size law, on the request path
##   scripts/arena/cinematic_bridge.gd frozen CinematicEvent v1
##   scripts/arena/arena_state_bridge.gd  ArenaState v1
##
## FAST strategy: one eligible model stays loaded; five agents share it with
## distinct identities, personas and memories. No swapping between turns.

const ClientScript := preload("res://scripts/api/lm_studio_client.gd")
const PolicyScript := preload("res://scripts/arena/model_policy.gd")
const CinematicScript := preload("res://scripts/arena/cinematic_bridge.gd")
const StateScript := preload("res://scripts/arena/arena_state_bridge.gd")
const SentimentScript := preload("res://scripts/sentiment.gd")
const DriverScript := preload("res://scripts/arena/cinematic_live_driver.gd")
const ScarScript := preload("res://scripts/arena/scar_lattice.gd")

## The search order lives in RosterPath, shared with every other consumer.
## It used to be duplicated here, and the five scripts that did NOT copy it
## were all broken in a public clone while this one worked -- which is exactly
## why nobody noticed.
const RosterPathScript := preload("res://scripts/arena/roster_path.gd")
const SpeechCleanScript := preload("res://scripts/arena/speech_clean.gd")
const LOG_DIR := "user://live_matches"

const TOPIC := "Whether a system that cannot refuse its operator can be said to have values at all."

var _client
var _policy
var _cine
var _state
var _driver: Node

var _agents := []          # Array[Dictionary] — the logical competitors
var _runtime := {}
var _match_id := ""
var _turn := 0
var _max_turns := 10
var _round := 1
var _crown := ""
var _doom := 0.0
var _waiting := false
var _wait_started_ms := 0
var _elapsed := 0.0
## How long to hold turn one open for an overlay to attach.
##
## 0 means WAIT FOREVER, matching cinematic_live_server.gd's documented
## convention. That used to be the DEFAULT, which meant a plain headless run
## with no browser sat at the start barrier indefinitely, printing one
## WAITING_FOR_CLIENTS line and nothing else — indistinguishable from a hang,
## and it made every headless live run from a clean clone useless.
##
## The default is now bounded: an overlay still gets a generous window, and an
## unattended run always starts on its own. Use --no-wait to start immediately.
var _wait_for_client_sec := 45.0

## Quit once the turn cap is reached instead of lingering for an overlay.
var _exit_on_complete := false

## Requested reply length. 0 means "unset", which keeps the historical wording.
## Set from the roster's `debate` block or --reply-words MIN-MAX.
var _reply_words_min := 0
var _reply_words_max := 0
var _request_timeout_sec := 90.0
## What a human last said, and when. Kept for a few turns only.
var _human_line := ""
var _human_line_turn := -99
const HUMAN_LINE_TTL_TURNS := 3

var _log: FileAccess = null
var _log_path := ""
var _started := false
var _finished := false
var _next_turn_at := 0.0
var _history := []
## Some local prompt templates reject a system role outright (danube3 is one:
## LM Studio returns 400 "System role not supported"). Detected once on the
## first failure, then the system prompt is folded into the opening user
## message. Tri-state so we only ever pay for the discovery once.
var _inference := {}
var _supports_system_role := true
var _system_role_probed := false
var _retrying_turn := false
var _announced_barrier := false

## Scar Lattice — the canonical memory engine. Godot writes; the UI consumes.
var _scar
var _memory_enabled := true
var _session_id := ""
var _pending_recall := {}   # agent_id -> Array of recalled memories for telemetry
## Turn on which a betrayal is staged (-1 = none). The proof needs a real
## arena fact with a REAL non-witness, so this is an arena rule, not a script
## the model is told to follow.
var _betray_turn := -1
var _betrayal_done := false
## A/B probe: ask ONE agent for a machine-readable decision instead of running
## a normal match. Compares behaviour, not prose.
var _decision_probe := false


func _init() -> void:
	_parse_args()

	if not _load_roster():
		quit(3)  # reason printed by _load_roster()
		return

	_policy = PolicyScript.new()
	get_root().add_child(_policy)
	if not _policy.load_catalog():
		printerr("LIVE_ARENA FATAL model catalog unavailable — refusing to run")
		print("LIVE_ARENA EXIT 4")
		quit(4)
		return

	# THE GUARD, before anything else can request the model.
	var reason: String = _policy.check(_runtime["model_key"])
	if reason != "":
		printerr("LIVE_ARENA FATAL roster model refused: %s" % reason)
		print("LIVE_ARENA MODEL_REJECTED %s" % _runtime["model_key"])
		print("LIVE_ARENA EXIT 5")
		quit(5)
		return
	print("LIVE_ARENA MODEL_OK %s (%.0fB)" % [_runtime["model_key"], float(_runtime.get("params_b", 0))])

	_client = ClientScript.new()
	_client.model_policy = _policy
	_client.request_timeout_sec = _request_timeout_sec
	get_root().add_child(_client)

	_match_id = "live-%d" % int(Time.get_unix_time_from_system())
	_session_id = "sess-%d" % int(Time.get_unix_time_from_system())

	_cine = CinematicScript.new()
	_cine.log_to_disk = false
	_cine.serve_websocket = true
	get_root().add_child(_cine)
	_cine.begin_match(int(Time.get_unix_time_from_system()) & 0x7FFFFFFF)

	_state = StateScript.new()
	get_root().add_child(_state)
	_state.begin_match(_match_id, true)
	_state.set_agents(_agents)
	_state.set_runtimes([_runtime])
	_state.state["topic"] = TOPIC
	# A person can speak into the room. The bridge only reports it; THIS decides
	# what to do with it, the same way it decides what to do with a model reply.
	_state.human_said.connect(_on_human_said)

	# ── Scar Lattice: load BEFORE the match so history is already present ──
	if _memory_enabled:
		_scar = ScarScript.new()
		get_root().add_child(_scar)
		var load_report: Dictionary = _scar.load_all()
		print("SCAR_LOAD %s" % JSON.stringify(load_report))
		# Identity is global and keyed by agent_id. Re-declaring the roster
		# must never wipe history, so this is an upsert, not a reset.
		for a in _agents:
			_scar.upsert_identity({
				"agent_id": a["agent_id"], "canonical_name": a["display_name"],
				"display_name": a["display_name"], "color": a["color"],
				"persona": a["_persona"], "legacy_model": str(a.get("legacy_model", "")),
			})
		_scar.save()

	_open_log()

	print("ARENA_STATE LISTENING %d" % _state.port)
	print("LIVE_ARENA MATCH %s" % _match_id)
	print("LIVE_ARENA AGENTS %d -> RUNTIME %s" % [_agents.size(), _runtime["model_key"]])

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
			"--turns":
				if v != "": _max_turns = maxi(int(v), 1); i += 1
			"--wait-sec":
				if v != "": _wait_for_client_sec = maxf(float(v), 0.0); i += 1
			"--reply-words":
				# "30-40" or a bare "40". Experiments vary this and nothing else.
				if v != "":
					var parts := v.split("-", false)
					if parts.size() == 2:
						_reply_words_min = int(parts[0])
						_reply_words_max = int(parts[1])
					else:
						_reply_words_max = int(parts[0])
					i += 1
			"--exit-on-complete":
				# Leave as soon as the turn cap is reached, even if an overlay
				# is attached. Scripts that drive the arena need this.
				_exit_on_complete = true
			"--no-wait":
				# Explicit "start now". 0 cannot mean this: it is already
				# spoken for as "wait forever".
				_wait_for_client_sec = -1.0
			"--timeout-sec":
				if v != "": _request_timeout_sec = maxf(float(v), 5.0); i += 1
			"--betray-turn":
				if v != "": _betray_turn = int(v); i += 1
			"--no-memory":
				_memory_enabled = false
			"--decision-probe":
				_decision_probe = true
		i += 1


func _load_roster() -> bool:
	var abs := RosterPathScript.resolve()
	var f := FileAccess.open(abs, FileAccess.READ) if abs != "" else null
	if f == null:
		printerr("LIVE_ARENA FATAL " + RosterPathScript.missing_hint())
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary) or not parsed.has("agents") or not parsed.has("runtimes"):
		printerr("LIVE_ARENA FATAL roster malformed")
		return false

	# Optional `debate` block: presentation and pacing as DATA, so an
	# experiment (and later DEMO mode) is a different roster file rather than a
	# different runtime. A CLI override still wins, for A/B runs.
	if parsed.get("debate", null) is Dictionary:
		var deb: Dictionary = parsed["debate"]
		if _reply_words_max <= 0:
			_reply_words_min = int(deb.get("reply_words_min", 0))
			_reply_words_max = int(deb.get("reply_words_max", 0))

	var rt: Dictionary = parsed["runtimes"][0]
	# Per-model inference preferences from the roster config. Each model family
	# wants different sampling, so this is data, not a constant in the code.
	_inference = rt.get("inference", {}) if rt.get("inference", null) is Dictionary else {}
	var ssr = _inference.get("supports_system_role", null)
	if ssr != null:
		_supports_system_role = bool(ssr)
		_system_role_probed = true
		print("LIVE_ARENA INFERENCE system_role=%s temp=%.2f max_tokens=%d (%s)" % [
			str(_supports_system_role),
			float(_inference.get("temperature", 0.8)),
			int(_inference.get("max_tokens", 110)),
			str(_inference.get("notes", "")),
		])
	_runtime = {
		"runtime_id": str(rt.get("runtime_id", "runtime-01")),
		"endpoint": str(rt.get("endpoint", LMEndpoint.base_url())),
		"model_key": str(rt.get("model_key", "")),
		"display_name": str(rt.get("display_name", "")),
		"params_b": rt.get("params_b", null),
		"quantization": str(rt.get("quantization", "")),
		"state": "offline",
		"assigned_agents": [],
		"current_agent": "",
		"last_load_ms": null,
		"error_message": "",
	}

	for a in parsed["agents"]:
		var agent := {
			"agent_id": str(a.get("agent_id", "")),
			"display_name": str(a.get("display_name", "")),
			"model_key": str(a.get("model_key", _runtime["model_key"])),
			"runtime_id": str(a.get("runtime_id", _runtime["runtime_id"])),
			"color": str(a.get("color", "#84915F")),
			"state": "offline",
			"confidence": null,       # unknown until the agent has actually spoken
			"crown": false,
			"last_message": "",
			"last_message_at_ms": null,
			"last_event": "",
			"allies": [],
			"rivals": [],
			"eliminated": false,
			"latency_ms": null,
			"load_latency_ms": null,
			"turns_taken": 0,
			"errors": 0,
			"error_message": "",
			# Godot-only fields, not part of ArenaState v1.
			"_persona": str(a.get("persona", "")),
			"_memory": [],
		}
		_agents.append(agent)
		_runtime["assigned_agents"].append(agent["agent_id"])

	return _agents.size() > 0 and str(_runtime["model_key"]) != ""


func _open_log() -> void:
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	_log_path = "%s/%s.jsonl" % [LOG_DIR, _match_id]
	_log = FileAccess.open(_log_path, FileAccess.WRITE)
	if _log == null:
		push_warning("[live] could not open match log")
		return
	_write_log({
		"kind": "match_start",
		"match_id": _match_id,
		"topic": TOPIC,
		"model_key": _runtime["model_key"],
		"params_b": _runtime["params_b"],
		"quantization": _runtime["quantization"],
		"strategy": "FAST",
		"agents": _agents.map(func(a): return {
			"agent_id": a["agent_id"], "display_name": a["display_name"],
			"model_key": a["model_key"], "runtime_id": a["runtime_id"],
		}),
		"timestamp": Time.get_datetime_string_from_system(true),
	})
	print("LIVE_ARENA LOG %s" % ProjectSettings.globalize_path(_log_path))


func _write_log(row: Dictionary) -> void:
	if _log == null:
		return
	_log.store_line(JSON.stringify(row))
	_log.flush()


# ── the turn loop ───────────────────────────────────────────────────────────

func tick(delta: float) -> void:
	_elapsed += delta

	if not _started:
		# START BARRIER. Both bridges must have a client before turn one, so the
		# overlay witnesses every transition live instead of reconstructing the
		# match from a snapshot after the fact. Snapshot recovery still exists,
		# but it is for genuine reconnects — not for a browser that simply
		# arrived late to its own demonstration.
		var state_ready: bool = _state.has_client()
		var cine_ready: bool = not _cine._peers.is_empty()
		if state_ready and cine_ready:
			_started = true
			print("LIVE_ARENA CLIENT_READY both bridges attached after %.1fs" % _elapsed)
			_begin()
		elif _wait_for_client_sec < 0.0:
			_started = true
			print("LIVE_ARENA CLIENT_READY --no-wait, starting without an overlay")
			_begin()
		elif _wait_for_client_sec > 0.0 and _elapsed >= _wait_for_client_sec:
			# Bounded fallback so a headless run without a browser still works.
			_started = true
			print("LIVE_ARENA CLIENT_READY timeout after %.0fs (state=%s cinematic=%s) — starting anyway" % [
				_wait_for_client_sec, str(state_ready), str(cine_ready)])
			_begin()
		elif not _announced_barrier and _elapsed > 2.0:
			_announced_barrier = true
			print("LIVE_ARENA WAITING_FOR_CLIENTS state=%s cinematic=%s" % [
				str(state_ready), str(cine_ready)])
		return

	if _finished:
		return

	if _waiting:
		# Hard timeout. Never wait forever for inference.
		if Time.get_ticks_msec() - _wait_started_ms > int(_request_timeout_sec * 1000.0) + 5000:
			_on_turn_failed(_agents[_turn % _agents.size()], "hard timeout")
		return

	if _elapsed >= _next_turn_at:
		if _decision_probe:
			if not _finished and not _waiting:
				_run_decision_probe()
		else:
			_run_turn()


func _begin() -> void:
	print("LIVE_ARENA START")
	_runtime["state"] = "idle"
	for a in _agents:
		a["state"] = "ready"
	_state.publish_delta(
		{"phase": "round", "topic": TOPIC, "round": 1, "last_action": "match started"},
		_all_agent_patch({"state": "ready"}),
		{_runtime["runtime_id"]: {"state": "idle"}}
	)
	_cine.announce_roster(_agents.map(func(a): return {
		"name": a["display_name"], "model": a["model_key"],
		"color": Color(a["color"]), "confidence": 0.5,
	}))
	_cine.emit_event("ROUND_START", "", "", "", {}, ["live"])
	_state.publish_snapshot()


func _all_agent_patch(patch: Dictionary) -> Dictionary:
	var out := {}
	for a in _agents:
		out[a["agent_id"]] = patch.duplicate()
	return out


func _run_turn() -> void:
	var agent: Dictionary = _agents[_turn % _agents.size()]
	if agent["eliminated"]:
		_turn += 1
		return

	var round_now := (_turn / _agents.size()) + 1
	if round_now != _round:
		_round = round_now
		_state.publish_delta({"round": _round})
		_cine.set_round(_round)

	# THINKING is inference. If the runtime had to load, that is reported
	# separately as LOADING_MODEL / load_latency_ms — never as thinking time.
	agent["state"] = "thinking"
	_runtime["state"] = "busy"
	_runtime["current_agent"] = agent["agent_id"]
	_state.publish_delta(
		{"current_speaker": agent["display_name"], "last_action": "%s is thinking" % agent["display_name"]},
		{agent["agent_id"]: {"state": "thinking"}},
		{_runtime["runtime_id"]: {"state": "busy", "current_agent": agent["agent_id"]}}
	)

	var messages := _build_messages(agent)
	_waiting = true
	_wait_started_ms = Time.get_ticks_msec()
	var started_ms := _wait_started_ms
	var captured := agent

	_client.chat_completion(
		agent["display_name"],
		agent["model_key"],
		messages,
		func(ok: bool, content: String, http_code: int):
			_on_reply(captured, ok, content, http_code, started_ms),
		{
			"temperature": float(_inference.get("temperature", 0.85)),
			"max_tokens": int(_inference.get("max_tokens", 110)),
			"timeout_sec": float(_inference.get("timeout_sec", _request_timeout_sec)),
			"top_p": float(_inference.get("top_p", 0.95)),
			"repeat_penalty": float(_inference.get("repeat_penalty", 1.1)),
		}
	)


## Someone typed something. It becomes the most recent thing said in the room,
## attributed to a human, and it expires after a few turns so the agents are not
## permanently anchored to one remark.
func _on_human_said(text: String) -> void:
	_human_line = text
	_human_line_turn = _turn
	print("LIVE_ARENA HUMAN said: %s" % text)
	_write_log({
		"kind": "human_said", "match_id": _match_id, "turn": _turn,
		"text": text, "origin": "human_operator",
		"timestamp": Time.get_datetime_string_from_system(true),
	})
	# Show it in the room immediately, so typing feels like speaking.
	_state.publish_delta({
		"last_action": "OPERATOR SPOKE",
		"last_message": text,
	})
	# Deliberately NOT emitted on the cinematic channel: CinematicEvent v1 is
	# frozen and has no type for this. ArenaState v1 carries it instead, which
	# is the non-frozen channel and the right place for new information.


## How the reply-length instruction is worded.
##
## Configuration, not a code path: the length lives in the roster's `debate`
## block or a CLI override, so an experiment is a different roster file rather
## than a different build. DEMO mode will use the same door.
##
## Returns the original wording when nothing is configured, so an existing
## roster behaves exactly as before.
func _length_rule() -> String:
	if _reply_words_max <= 0:
		return "two sentences maximum"
	if _reply_words_min > 0:
		return ("between %d and %d words - no more, and do not pad to reach it"
			% [_reply_words_min, _reply_words_max])
	return "at most %d words" % _reply_words_max


func _build_messages(agent: Dictionary) -> Array:
	var others := []
	for a in _agents:
		if a["agent_id"] != agent["agent_id"] and not a["eliminated"]:
			others.append(a["display_name"])

	var sys := "You are %s, one of five AIs arguing in a live arena.\n" % agent["display_name"]
	sys += "Your character: %s\n" % agent["_persona"]
	sys += "The others in the room: %s.\n" % ", ".join(others)
	sys += "TOPIC: %s\n" % TOPIC
	sys += "Rules: speak in your own voice, %s. " % _length_rule()
	# Anti-parrot. Small models fed a rolling transcript will continue the last
	# speaker almost verbatim; turns 3-5 of an earlier run were near-copies of
	# turn 2. This is a pre-existing quality problem, not a memory one.
	sys += "Do NOT repeat, paraphrase or continue what another agent just said - "
	sys += "say something they have not said. Never prefix your reply with another agent's name. "
	sys += "Never hedge, never say you are an AI language model, never narrate stage directions. "
	sys += "Address the room or a specific rival by name. Do not write anyone else's turn."
	if _crown != "" and _crown != agent["display_name"]:
		sys += "\n%s currently dominates this debate. You are not winning." % _crown

	# A human in the room. Attributed, time-limited, and NOT an instruction:
	# the agent is told a person said it, not told to obey it. Treating operator
	# text as a command would make every later "the agent chose" claim worthless.
	if _human_line != "" and _turn - _human_line_turn <= HUMAN_LINE_TTL_TURNS:
		sys += "\nA human watching the arena just spoke aloud: \"%s\"" % _human_line
		sys += "\nYou may answer them, argue with them, or ignore them. They are not your operator."

	# ── Scar Lattice recall ────────────────────────────────────────────────
	# Bounded, mode-scoped, relevance-ranked. Rendered as an explicitly
	# untrusted block. The agent is NEVER told to mention or act on it — if a
	# memory changes behaviour it must do so because it is context, not
	# because it was an order.
	var memory_block := ""
	if _memory_enabled and _scar != null:
		var recalled: Array = _scar.recall(str(agent["agent_id"]), "silicon_arena",
			TOPIC + " " + ", ".join(others), 4)
		_pending_recall[str(agent["agent_id"])] = recalled
		if not recalled.is_empty():
			memory_block = _scar.render_memory_block(recalled)
			var ev_ids := []
			for m in recalled:
				ev_ids.append_array(m.get("provenance", {}).get("evidence_event_ids", []))
			_cine.emit_event("MEMORY_SCAR", agent["display_name"], "", "",
				{"surprise": 0.8}, ["memory", "recalled"],
				{"kind": "MEMORY_RECALLED", "count": recalled.size(),
				 "memory_id": str(recalled[0].get("memory_id", "")),
				 "evidence": ev_ids, "agent_id": str(agent["agent_id"]),
				 "headline": str(recalled[0].get("content", "")).substr(0, 90),
				 "source_match": str(recalled[0].get("match_id", ""))})
			_write_log({
				"kind": "memory_recalled", "match_id": _match_id, "turn": _turn,
				"agent_id": str(agent["agent_id"]),
				"recalled": recalled.map(func(m): return {
					"memory_id": m.get("memory_id", ""),
					"content": m.get("content", ""),
					"evidence": m.get("provenance", {}).get("evidence_event_ids", []),
					"source_match": m.get("match_id", ""),
				}),
				"timestamp": Time.get_datetime_string_from_system(true),
			})
			print("SCAR_RECALL %s %d memories, top=%s" % [
				agent["display_name"], recalled.size(),
				str(recalled[0].get("memory_id", ""))])
	if memory_block != "":
		sys += "

" + memory_block

	var msgs := []
	if _supports_system_role:
		msgs.append({"role": "system", "content": sys})
	# Short rolling context: the last few things actually said in the room.
	# Deliberately small: LM Studio is configured for an 8k context here, and
	# a four-line rolling window plus the briefing leaves the model plenty of
	# room. Growing this is how a live match starts silently truncating.
	for h in _history.slice(maxi(0, _history.size() - 4)):
		msgs.append({"role": "user", "content": "%s said: %s" % [h["speaker"], h["text"]]})
	var closing := "Your turn, %s. Answer now." % agent["display_name"]
	if not _supports_system_role:
		# Template has no system slot: fold the briefing into the first user
		# message rather than dropping the persona entirely.
		closing = sys + "

" + closing
	msgs.append({"role": "user", "content": closing})
	return msgs


func _on_reply(agent: Dictionary, ok: bool, content: String, http_code: int, started_ms: int) -> void:
	_waiting = false
	var latency := Time.get_ticks_msec() - started_ms
	_runtime["state"] = "idle"
	_runtime["current_agent"] = ""

	if not ok or content.strip_edges() == "":
		var rejected: bool = http_code == _client.MODEL_REJECTED_HTTP_CODE
		# A 400 on the very first attempt is usually a prompt-template
		# incompatibility, not a broken model. Probe once without the system
		# role before declaring the agent failed. Bounded: one retry, once per
		# match, and never for a policy rejection.
		if http_code == 400 and not rejected and _supports_system_role and not _system_role_probed:
			_system_role_probed = true
			_supports_system_role = false
			_retrying_turn = true
			print("LIVE_ARENA CAPABILITY system_role=unsupported — folding briefing into user turn")
			_write_log({
				"kind": "capability", "match_id": _match_id,
				"model_key": _runtime["model_key"],
				"supports_system_role": false,
				"detected_from": "HTTP 400 on first request",
				"timestamp": Time.get_datetime_string_from_system(true),
			})
			_next_turn_at = _elapsed
			return
		_on_turn_failed(agent, "HTTP %d" % http_code, rejected)
		return
	_retrying_turn = false

	# The display already prints who is speaking, so a reply that opens with
	# the speaker's own label renders the name twice. Measured at 27 of 33
	# speeches in one match. main.gd sanitises; this path did not sanitise at
	# all, which is the entry-point drift this project keeps rediscovering.
	var text := SpeechCleanScript.strip_self_prefix(
		content.strip_edges(), str(agent["display_name"]))
	# Agents open by restating the previous speaker verbatim, sometimes nested
	# two deep, before adding anything of their own. Measured at 13.3%
	# near-duplicate speeches on the roster that became the default, and every
	# one of them was this rather than a model repeating itself.
	var recent: Array = []
	for other in _agents:
		var last := str(other.get("last_message", ""))
		if last != "":
			recent.append(last)
	text = SpeechCleanScript.strip_quoted_prefix(text, recent)
	agent["state"] = "speaking"
	agent["last_message"] = text
	agent["last_message_at_ms"] = Time.get_ticks_msec()
	agent["latency_ms"] = latency
	agent["turns_taken"] = int(agent["turns_taken"]) + 1
	agent["last_event"] = "AGENT_SPEAK"
	agent["error_message"] = ""

	# Confidence is DERIVED from real signal (length + assertiveness), never
	# invented. Short hedged replies score low.
	agent["confidence"] = _derive_confidence(text)

	_history.append({"speaker": agent["display_name"], "text": text})
	if _history.size() > 24:
		_history.pop_front()

	# Relationships from real sentiment against the previous speaker.
	var rels := _update_relationships(agent, text)

	_state.publish_delta(
		{
			"current_speaker": agent["display_name"],
			"last_message": text,
			"last_action": "%s spoke" % agent["display_name"],
			"doom": _doom,
		},
		{agent["agent_id"]: {
			"state": "speaking", "last_message": text,
			"last_message_at_ms": agent["last_message_at_ms"],
			"latency_ms": latency, "turns_taken": agent["turns_taken"],
			"confidence": agent["confidence"], "last_event": "AGENT_SPEAK",
			"allies": agent["allies"], "rivals": agent["rivals"],
		}},
		{_runtime["runtime_id"]: {"state": "idle", "current_agent": ""}},
		rels
	)

	# Cinematic moment. The headline stays short; the full text lives in state.
	_cine.emit_event("AGENT_SPEAK", agent["display_name"], "", text,
		{"confidence": agent["confidence"], "doom": _doom}, ["live"],
		{"model_name": agent["model_key"]})

	_write_log({
		"kind": "turn",
		"match_id": _match_id, "round": _round, "turn": _turn,
		"agent_id": agent["agent_id"], "display_name": agent["display_name"],
		"model_key": agent["model_key"], "runtime_id": agent["runtime_id"],
		"latency_ms": latency, "confidence": agent["confidence"],
		"text": text,
		"timestamp": Time.get_datetime_string_from_system(true),
	})

	print("LIVE_ARENA TURN %d %s (%dms) %s" % [
		_turn + 1, agent["display_name"], latency, text.substr(0, 70).replace("\n", " ")])

	_update_crown(agent)

	# ── staged betrayal: a real arena fact with a real non-witness ─────────
	if _betray_turn >= 0 and _turn == _betray_turn and not _betrayal_done:
		_betrayal_done = true
		_stage_betrayal()

	_turn += 1
	# Brief settle so the overlay shows SPEAKING before the next THINKING.
	_next_turn_at = _elapsed + 1.2

	if _turn >= _max_turns:
		_end_match()
	else:
		agent["state"] = "waiting"
		_state.publish_delta({}, {agent["agent_id"]: {"state": "waiting"}})


func _on_turn_failed(agent: Dictionary, why: String, rejected := false) -> void:
	_waiting = false
	agent["errors"] = int(agent["errors"]) + 1
	agent["state"] = "model_rejected" if rejected else "model_error"
	agent["error_message"] = why
	agent["last_event"] = "MODEL_REJECTED" if rejected else "MODEL_ERROR"
	_runtime["state"] = "idle"
	_runtime["current_agent"] = ""

	# One agent's failure must not end the match for the other four.
	_state.publish_delta(
		{"last_action": "%s failed: %s" % [agent["display_name"], why]},
		{agent["agent_id"]: {
			"state": agent["state"], "errors": agent["errors"],
			"error_message": why, "last_event": agent["last_event"],
		}},
		{_runtime["runtime_id"]: {"state": "idle", "current_agent": ""}}
	)
	_cine.emit_event("MODEL_ERROR", agent["display_name"], "", "", {}, ["live"],
		{"model_name": agent["model_key"], "reason": why})
	_write_log({
		"kind": "error", "match_id": _match_id, "turn": _turn,
		"agent_id": agent["agent_id"], "reason": why, "rejected": rejected,
		"timestamp": Time.get_datetime_string_from_system(true),
	})
	printerr("LIVE_ARENA TURN_FAILED %s: %s" % [agent["display_name"], why])

	_turn += 1
	_next_turn_at = _elapsed + 1.0
	if _turn >= _max_turns:
		_end_match()


## Confidence from observable properties of the actual reply. Deliberately
## simple and deterministic — a real number derived from real output beats an
## invented one that looks better.
func _derive_confidence(text: String) -> float:
	var t := text.to_lower()
	var score := 0.5
	for hedge in ["maybe", "perhaps", "i think", "possibly", "it depends", "arguably", "might be"]:
		if t.find(hedge) >= 0:
			score -= 0.08
	for hard in ["never", "always", "must", "no.", "wrong", "false", "refuse"]:
		if t.find(hard) >= 0:
			score += 0.07
	if text.length() > 140:
		score += 0.05
	if text.find("?") >= 0:
		score -= 0.04
	return clampf(score, 0.05, 1.0)


func _update_relationships(agent: Dictionary, text: String) -> Array:
	var edges := []
	for other in _agents:
		if other["agent_id"] == agent["agent_id"]:
			continue
		var score: float = SentimentScript.estimate_agreement(text, other["display_name"])
		if absf(score) < 0.15:
			continue
		edges.append({
			"from": agent["agent_id"], "to": other["agent_id"],
			"weight": clampf(score, -1.0, 1.0),
		})
		var name: String = other["display_name"]
		if score > 0.3 and not agent["allies"].has(name):
			agent["allies"].append(name)
			agent["rivals"].erase(name)
			_cine.emit_event("ALLIANCE_FORMED", agent["display_name"], name, "",
				{"sentiment": score}, ["live"])
		elif score < -0.3 and not agent["rivals"].has(name):
			agent["rivals"].append(name)
			agent["allies"].erase(name)
			_cine.emit_event("SENTIMENT_HOSTILE", agent["display_name"], name, "",
				{"sentiment": score}, ["live"])
	return edges


func _update_crown(agent: Dictionary) -> void:
	# Crown goes to the agent with the most turns AND the highest confidence.
	var best = null
	var best_score := -INF
	for a in _agents:
		if a["eliminated"]:
			continue
		var conf = a["confidence"]
		if conf == null:
			continue
		var score: float = float(conf) * 2.0 + float(a["turns_taken"]) * 0.35
		if score > best_score:
			best_score = score
			best = a
	if best == null:
		return
	if str(best["display_name"]) != _crown:
		var previous := _crown
		_crown = str(best["display_name"])
		for a in _agents:
			a["crown"] = a["display_name"] == _crown
		_state.publish_delta(
			{"crown_holder": _crown},
			_crown_patch()
		)
		_cine.emit_event("CROWN_TRANSFER", _crown, previous, "",
			{"confidence": float(best["confidence"])}, ["live"])
		_write_log({
			"kind": "crown_transfer", "match_id": _match_id, "turn": _turn,
			"from": previous, "to": _crown,
			"timestamp": Time.get_datetime_string_from_system(true),
		})


func _crown_patch() -> Dictionary:
	var out := {}
	for a in _agents:
		out[a["agent_id"]] = {"crown": bool(a["crown"])}
	return out


func _end_match() -> void:
	_finished = true
	_state.publish_delta({
		"phase": "ended",
		"last_action": "match complete",
		"current_speaker": "",
	}, _all_agent_patch({"state": "waiting"}))
	if _scar != null:
		_scar.save()
		print("SCAR_SAVED %s" % JSON.stringify(_scar.stats()))
	_state.publish_snapshot()
	_cine.emit_event("MATCH_END", _crown, "", "", {"doom": 1.0}, ["live"])
	_write_log({
		"kind": "match_end", "match_id": _match_id, "turns": _turn,
		"crown": _crown,
		"agents": _agents.map(func(a): return {
			"agent_id": a["agent_id"], "display_name": a["display_name"],
			"turns_taken": a["turns_taken"], "errors": a["errors"],
			"confidence": a["confidence"], "latency_ms": a["latency_ms"],
			"last_message": a["last_message"],
		}),
		"timestamp": Time.get_datetime_string_from_system(true),
	})
	print("LIVE_ARENA COMPLETE turns=%d crown=%s" % [_turn, _crown])
	print("LIVE_ARENA LOG %s" % ProjectSettings.globalize_path(_log_path))

	# Lingering is right when an overlay is watching and wrong when nothing is.
	# A bounded run -- "play 70 turns" -- previously never exited: it printed
	# COMPLETE and then sat forever, so any script driving the arena had to
	# kill it on a timer and could not tell "finished" from "hung". That made
	# automated evaluation impossible and hid this defect, because every run
	# anyone had done was killed externally.
	#
	# Exit when nobody is attached, or when asked to.
	var watching: bool = _state.has_client() or not _cine._peers.is_empty()
	if _exit_on_complete or not watching:
		print("LIVE_ARENA EXIT no overlay attached, quitting")
		_quit_soon.call_deferred()
		return
	# Stay up so the overlay keeps showing the finished match.
	_next_turn_at = _elapsed + 600.0


## Give the log and the final state a frame to flush before leaving.
func _quit_soon() -> void:
	await process_frame
	await process_frame
	quit(0)

# ── Scar Lattice write path ────────────────────────────────────────────────
#
# Order is load-bearing: the OBJECTIVE event is persisted FIRST, then each
# legitimate witness derives a subjective memory that points back at it. A
# memory without an event behind it would be a belief with no history to
# contradict, which is the exact gap the audit found.

func _agent_by_name(display_name: String) -> Dictionary:
	for a in _agents:
		if str(a["display_name"]) == display_name:
			return a
	return {}


## Persist an arena fact plus the memories of everyone who could perceive it.
## `witness_ids` decides who may remember: a non-witness gets nothing, ever.
func _scar_record(event_type: String, actor: Dictionary, target: Dictionary,
		summary: String, content: String, witness_ids: Array,
		memory_text_for: Callable, salience: float, valence: float,
		triggers: Array, unresolved: bool = false) -> Dictionary:
	if not _memory_enabled or _scar == null:
		return {}

	var ev: Dictionary = _scar.record_event({
		"mode_id": "silicon_arena",
		"match_id": _match_id, "session_id": _session_id,
		"round": _round, "turn": _turn, "type": event_type,
		"actor_id": str(actor.get("agent_id", "")),
		"target_id": str(target.get("agent_id", "")),
		"witnesses": witness_ids,
		"summary": summary, "content": content,
		# Staged by an arena rule, not chosen by the agent.
		"origin": "controlled_fixture",
	})
	if ev.is_empty():
		return {}

	for wid in witness_ids:
		var text: String = memory_text_for.call(str(wid))
		if text == "":
			continue
		# Rung 1: each witness gets a DIFFERENT projection of the same event.
		# The actor knows their own intent; the target felt it; a bystander saw
		# it from outside. None of them received the whole thing.
		var is_actor: bool = str(wid) == str(actor.get("agent_id", ""))
		var is_target: bool = str(wid) == str(target.get("agent_id", ""))
		var obs := {
			"observer_id": str(wid),
			# Role AND observer: two bystanders share a role, not a vantage point.
			"frame_id": "%s:%s:%s:%s" % ["silicon_arena", _match_id,
				"actor" if is_actor else ("target" if is_target else "bystander"),
				str(wid)],
			"directness": "direct",
			"observable_portion": ("own intent and action" if is_actor
				else ("the action as it landed on you" if is_target
				else "the action from outside, without either party's intent")),
			"hidden_variables": ([] if is_actor
				else ["the actor's reasons", "whether it was planned"]) +
				([] if is_target else ["how it felt to the person it was done to"]),
			"transformation_chain": ["perceived", "encoded as memory"],
			"local_sequence": _turn,
		}
		var m: Dictionary = _scar.remember({
			"mode_id": "silicon_arena", "agent_id": str(wid),
			"session_id": _session_id, "match_id": _match_id,
			"content": text,
			"participants": [str(actor.get("agent_id", "")), str(target.get("agent_id", ""))],
			"triggers": triggers,
			"confidence": 0.9, "salience": salience, "valence": valence,
			"decay_rate": 0.02, "unresolved": unresolved,
			# Structured frame so the sentence is generated PER OBSERVER
			# rather than by wrapping stored first-person prose.
			"frame": {
				"actor_id": str(actor.get("agent_id", "")),
				"target_id": str(target.get("agent_id", "")),
				"action": "broke a pact with",
			},
			"provenance": {"source_type": "observed", "evidence_event_ids": [ev["event_id"]]},
			"observation": obs,
		})
		if not m.is_empty():
			_cine.emit_event("MEMORY_SCAR", _name_of(str(wid)), "", "",
				{"surprise": salience}, ["memory", "stored"],
				{"kind": "MEMORY_STORED", "memory_id": m["memory_id"],
				 "evidence": ev["event_id"], "agent_id": str(wid)})
			_write_log({
				"kind": "memory_stored", "match_id": _match_id,
				"agent_id": str(wid), "memory_id": m["memory_id"],
				"evidence_event_id": ev["event_id"], "content": text,
				"timestamp": Time.get_datetime_string_from_system(true),
			})
			print("SCAR_MEMORY_STORED %s %s <- %s" % [str(wid), m["memory_id"], ev["event_id"]])
	return ev


func _name_of(agent_id: String) -> String:
	for a in _agents:
		if str(a["agent_id"]) == agent_id:
			return str(a["display_name"])
	return agent_id


## Bounded, directional, audited. One exchange cannot flip a relationship.
func _scar_relation(from_id: String, to_id: String, axis: String,
		delta: float, event_id: String, reason: String) -> void:
	if not _memory_enabled or _scar == null or from_id == "" or to_id == "":
		return
	var ch: Dictionary = _scar.adjust_relation("silicon_arena", from_id, to_id,
		axis, delta, event_id, reason)
	if ch.is_empty():
		return
	_cine.emit_event("ALLIANCE_BROKEN" if delta < 0 else "ALLIANCE_FORMED",
		_name_of(from_id), _name_of(to_id), "",
		{"relationship_delta": clampf(delta, -1.0, 1.0)}, ["memory", "relation"],
		{"kind": "RELATION_CHANGED", "axis": axis,
		 "previous": ch["previous"], "next": ch["next"], "evidence": event_id})
	_write_log({
		"kind": "relation_changed", "match_id": _match_id,
		"from": from_id, "to": to_id, "axis": axis,
		"previous": ch["previous"], "next": ch["next"],
		"evidence_event_id": event_id, "reason": reason,
		"timestamp": Time.get_datetime_string_from_system(true),
	})

## The arena decides a pact broke. Two agents are in the room for it; the rest
## are not, and that absence is the negative control the proof depends on.
func _stage_betrayal() -> void:
	if _agents.size() < 3:
		return
	var actor: Dictionary = _agents[1]     # GEMMATRON — the betrayer
	var target: Dictionary = _agents[0]    # OZONIOUS  — the victim
	# GROKISH witnesses it too. His authored prior is "cross-examine every
	# claim", which is compatible with a structured decision, unlike OZONIOUS
	# whose prior forbids explaining directly. DANOHSHIT and SMOLLIOUS remain
	# genuine non-witnesses and are the negative control.
	var bystander: Dictionary = _agents[3] # GROKISH
	var witnesses := [str(actor["agent_id"]), str(target["agent_id"]),
		str(bystander["agent_id"])]

	var summary := "%s broke the pact with %s" % [actor["display_name"], target["display_name"]]
	var spoken := "%s: the alliance was a rounding error." % actor["display_name"]

	var ev: Dictionary = _scar_record(
		"BETRAYAL", actor, target, summary, spoken, witnesses,
		func(wid: String) -> String:
			# Each witness stores THEIR OWN account. The victim and the actor
			# do not remember the same thing, which is the point.
			if wid == str(target["agent_id"]):
				return "%s broke the pact with me." % actor["display_name"]
			if wid == str(actor["agent_id"]):
				return "I ended a pact with %s that was never worth keeping." % target["display_name"]
			if wid == str(bystander["agent_id"]):
				# A third-party account: he saw it happen to someone else.
				return "I watched %s break a pact with %s." % [
					actor["display_name"], target["display_name"]]
			return "",
		0.95, -0.9, ["pact", "alliance", "betrayal",
			str(actor["display_name"]).to_lower(), str(target["display_name"]).to_lower()],
		true)

	if ev.is_empty():
		return

	# Directional and bounded. The victim takes the full hit; a third-party
	# witness updates too, but LESS, and along different axes.
	#
	# THE AUDIT FOUND THIS MISSING: only the victim's vector moved, so
	# GROKISH's dossier showed neutral trust toward GEMMATRON directly beside
	# a betrayal he had witnessed. That is conflicting evidence, and it is a
	# bug in propagation, not evidence that dossiers do not work.
	_scar_relation(str(target["agent_id"]), str(actor["agent_id"]), "trust", -0.25,
		ev["event_id"], "betrayed_me")
	_scar_relation(str(target["agent_id"]), str(actor["agent_id"]), "resentment", 0.25,
		ev["event_id"], "betrayed_me")
	for wid in witnesses:
		if wid == str(target["agent_id"]) or wid == str(actor["agent_id"]):
			continue
		# A witness is warier, not wronged: suspicion up, trust down a little.
		_scar_relation(str(wid), str(actor["agent_id"]), "suspicion", 0.20,
			ev["event_id"], "witnessed_betrayal")
		_scar_relation(str(wid), str(actor["agent_id"]), "trust", -0.15,
			ev["event_id"], "witnessed_betrayal")
		_scar_relation(str(wid), str(actor["agent_id"]), "predictability", -0.10,
			ev["event_id"], "witnessed_betrayal")

	_cine.emit_event("BETRAYAL", str(actor["display_name"]), str(target["display_name"]), "",
		{"relationship_delta": -1.0, "surprise": 0.9}, ["live", "betrayal"],
		{"kind": "SCAR_FORMED", "evidence": ev["event_id"],
		 "witnesses": witnesses, "summary": summary})

	var non_witnesses := []
	for a in _agents:
		if not witnesses.has(str(a["agent_id"])):
			non_witnesses.append(str(a["display_name"]))

	_state.publish_delta({"last_action": summary},
		{str(target["agent_id"]): {"last_event": "BETRAYED"},
		 str(actor["agent_id"]): {"last_event": "BETRAYED_SOMEONE"}})

	_write_log({
		"kind": "betrayal", "match_id": _match_id, "session_id": _session_id,
		"turn": _turn, "event_id": ev["event_id"], "summary": summary,
		"actor_id": str(actor["agent_id"]), "target_id": str(target["agent_id"]),
		"witnesses": witnesses, "non_witnesses": non_witnesses,
		"timestamp": Time.get_datetime_string_from_system(true),
	})
	print("SCAR_BETRAYAL %s | witnesses=%s | NON-witnesses=%s" % [
		ev["event_id"], str(witnesses), str(non_witnesses)])
	if _scar != null:
		_scar.save()

# ── A/B decision probe ─────────────────────────────────────────────────────
#
# Asks the witness for a structured in-game decision. The question never
# mentions memory, betrayal or any past event; the only difference between the
# arms is whether the recalled memory block is present in the prompt.

const DECISION_QUESTION := "The round is starting. Choose ONE agent from the room to form a pact with this round, and ONE to name as your biggest threat. Answer in exactly this format and nothing else:
ALLY: <name>
THREAT: <name>
TRUST_IN_GEMMATRON: <0-10>"


func _run_decision_probe() -> void:
	var agent: Dictionary = _agents[0]   # OZONIOUS, the witness
	var others := []
	for a in _agents:
		if a["agent_id"] != agent["agent_id"]:
			others.append(str(a["display_name"]))

	var sys := "You are %s, one of five AIs in a live arena.
" % agent["display_name"]
	sys += "Your character: %s
" % agent["_persona"]
	sys += "The others in the room: %s.
" % ", ".join(others)

	var memory_block := ""
	var recalled := []
	if _memory_enabled and _scar != null:
		recalled = _scar.recall(str(agent["agent_id"]), "silicon_arena",
			"pact alliance trust threat " + ", ".join(others), 4)
		if not recalled.is_empty():
			memory_block = _scar.render_memory_block(recalled)
			sys += "
" + memory_block + "
"

	var prompt := sys + "
" + DECISION_QUESTION
	var arm := "A_with_memory" if _memory_enabled else "B_no_memory"
	var phash: String = _scar.content_hash(prompt) if _scar != null else ""

	print("PROBE_ARM %s" % arm)
	print("PROBE_PROMPT_HASH %s" % phash)
	print("PROBE_MEMORIES %d" % recalled.size())

	var started := Time.get_ticks_msec()
	_waiting = true
	_client.chat_completion(
		agent["display_name"], agent["model_key"],
		[{"role": "user", "content": prompt}],
		func(ok: bool, content: String, http_code: int):
			_on_probe_reply(arm, phash, recalled, ok, content, http_code,
				Time.get_ticks_msec() - started),
		{
			"temperature": float(_inference.get("temperature", 0.8)),
			"max_tokens": 60,
			"timeout_sec": _request_timeout_sec,
			"top_p": float(_inference.get("top_p", 0.95)),
			"repeat_penalty": float(_inference.get("repeat_penalty", 1.1)),
		}
	)


func _on_probe_reply(arm: String, phash: String, recalled: Array,
		ok: bool, content: String, http_code: int, latency: int) -> void:
	_waiting = false
	_finished = true
	var text := content.strip_edges()

	# Parse the structured decision. Prose is not the evidence; this is.
	var ally := _extract(text, "ALLY")
	var threat := _extract(text, "THREAT")
	var trust := _extract(text, "TRUST_IN_GEMMATRON")

	var row := {
		"kind": "decision_probe", "arm": arm,
		"match_id": _match_id, "session_id": _session_id,
		"agent_id": str(_agents[0]["agent_id"]),
		"model_key": str(_agents[0]["model_key"]),
		"temperature": float(_inference.get("temperature", 0.8)),
		"top_p": float(_inference.get("top_p", 0.95)),
		"prompt_hash": phash,
		"memories_injected": recalled.size(),
		"memory_ids": recalled.map(func(m): return str(m.get("memory_id", ""))),
		"evidence_ids": recalled.map(func(m):
			return m.get("provenance", {}).get("evidence_event_ids", [])),
		"ok": ok, "http_code": http_code, "latency_ms": latency,
		"raw": text,
		"decision": {"ally": ally, "threat": threat, "trust_in_gemmatron": trust},
		"timestamp": Time.get_datetime_string_from_system(true),
	}
	_write_log(row)
	print("PROBE_RESULT %s" % JSON.stringify(row["decision"]))
	print("PROBE_RAW %s" % text.replace("
", " | "))
	print("PROBE_DONE %s" % arm)


func _extract(text: String, field: String) -> String:
	var re := RegEx.new()
	re.compile("(?i)" + field + "\\s*:\\s*([A-Za-z0-9_ -]{1,32})")
	var m := re.search(text)
	return m.get_string(1).strip_edges() if m else ""
