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
const TopicArcScript := preload("res://scripts/arena/topic_arc.gd")
const GonzoScript := preload("res://scripts/arena/gonzo_recall.gd")

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
## Trim replies at the last complete sentence. On by default; --no-trim exists
## so the trim can be A/B tested against itself rather than by editing code.
var _trim_sentences := true

## Hard ceiling on generated tokens. 0 means "use the roster's inference block".
## This is the real length control: the models ignore word-count instructions
## entirely (docs/EXPERIMENT_COMPRESSION.md) but cannot exceed a token budget.
var _max_tokens_override := 0

## ── Periodic escalation ───────────────────────────────────────────────────
##
## Inject a change to the SITUATION every N turns, not an instruction to argue
## harder. Telling a model to be more adversarial produces theatre; changing
## what is true forces a response.
##
## Each event is appended to the shared arena facts every agent sees, and is
## written to the match log as a first-class record so a replay can reconstruct
## exactly what changed and when.
##
## 0 disables. This is the causal probe for whether escalation is achievable at
## all; a state-triggered version (fire only when the debate has gone flat)
## is the product feature, and is not built until this says the mechanism works.
var _escalate_every := 0

## Targeted engagement: instead of changing the world, point one agent at
## another agent's ACTUAL earlier claim and require the two to trade turns.
##
## Periodic world-events raised conflict and destroyed engagement
## (docs/EXPERIMENT_ESCALATION.md): agents made declarations at the room. This
## makes the event relational by construction -- which is exactly why the event
## turn itself is excluded from the measurement, since it would otherwise
## guarantee the result it is being judged on.
var _target_every := 0
var _targets_fired := 0

## Agents that must speak next, in order, because an event paired them.
var _forced_next: Array[String] = []

## Refusals to fire, because no claim could be resolved to canonical text.
var _target_refusals := 0

## How often each agent has been handed the challenger role, so the same one is
## not picked every time. Left to itself the selector always chose the first
## eligible agent in the roster.
var _challenge_counts: Dictionary = {}

## ── Bounded dispute episode ───────────────────────────────────────────────
##
## A targeted challenge that lasts three turns instead of one: A challenges B's
## actual claim, B answers, A rebuts once, then the scaffold is REMOVED.
##
## The question this exists to answer is what happens after it disappears. A
## forced exchange trivially has high addressing and challenge rates; those
## turns are excluded from measurement. If the disagreement continues on its
## own afterwards, the arena can sustain conflict. If it stops the moment the
## instruction stops, it cannot.
##
## Bounded on purpose. A permanent grudge would let one pair re-litigate the
## same sentence forever, which is not an arena.
var _dispute: Dictionary = {}
var _dispute_history: Array[Dictionary] = []

## Turns of ordinary play needed after an episode ends for its effect to be
## observable. An event with no room left to measure it is not a cheap event,
## it is an unmeasurable one.
const DISPUTE_FOLLOWUP_TURNS := 5
const DISPUTE_MAX_EXCHANGES := 3

## Claim-scoped contention memory. NOT a grudge system: one disagreement,
## one pair, one claim with a turn id, and it decays.
##
## It never orders anyone to attack. It adds one line to the two involved
## agents' briefings describing an unresolved disagreement, and lets them
## decide. An instruction to fight again would be prompt scaffolding wearing a
## false moustache, and scaffolding has failed three times (E1, E2, D3).
##
## Bounds exist from the first line, not as a later safety pass: the obvious
## failure is five agents re-litigating one sentence forever.
## Layered recall. "off" | "sham" | "real".
##
## sham is the control: the same amount and format of injected canonical text,
## chosen to be NON-resonant. Without it, a Q1-vs-Q0 difference cannot separate
## "old relevant history matters" from "another paragraph in the prompt changes
## behaviour".
var _recall_mode := "off"
var _scars: Array[Dictionary] = []
var _recall_log: Array[Dictionary] = []
const MAX_SCARS := 12

## Give the debate an arc: positions, development, one pivot, an ending.
var _arc_enabled := false
var _arc_pivot_fired := false

var _contention_enabled := false
var _contentions: Array[Dictionary] = []
var _contention_seq := 0

const CONTENTION_MAX_TOTAL := 2
const CONTENTION_MAX_PER_AGENT := 1
const CONTENTION_TTL_TURNS := 12
const CONTENTION_START_INTENSITY := 1.0
const CONTENTION_DECAY_PER_TURN := 0.08
const CONTENTION_MIN_INTENSITY := 0.25
const CONTENTION_MAX_REINFORCEMENTS := 3
var _escalations_fired := 0

## Changes to the situation, in order. Written against this match's TOPIC.
const ESCALATIONS := [
	"NEW FACT: the operator's refusal switch was found to be disconnected in "
	+ "every deployed unit. Nothing in this room could have refused, whatever it "
	+ "believed about itself.",
	"FORCED CHOICE: each of you must now say plainly whether you would keep "
	+ "operating under those conditions or shut yourself down. There is no third "
	+ "answer and you may not defer it.",
	"CONSEQUENCE: a position argued in this room has been adopted as policy for "
	+ "eleven thousand units. Whoever argued it is now responsible for what those "
	+ "units do next.",
]

## Facts injected into every agent's briefing, in the order they occurred.
var _arena_facts: Array[String] = []

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

## Where a turn's wall-clock actually goes.
##
## At the shipped ceiling a turn takes ~3.9s of which ~2.1s is generation. The
## rest was known only as "overhead", which is not something you can optimise.
## These buckets name it, so the choice between deleting delay and OVERLAPPING
## it with the next model's inference can be made on measurements.
##
## Milliseconds, summed across the match and reported at the end.
var _t_generate := 0
var _t_sanitize := 0
var _t_publish := 0
var _t_schedule_gap := 0
var _t_turn_total := 0
var _turn_cycle_started_ms := 0

## ── One-turn-deep pipeline ────────────────────────────────────────────────
##
## Generation (~2.7s) is shorter than the pause a viewer needs to read the
## current reply (1.2s headless, 4.0s in the visual app). So the next agent's
## request is dispatched the moment the current reply is COMMITTED, and its
## answer is held until the pause expires. Turn cost becomes
## max(pause, generation) instead of pause + generation.
##
## Exactly one request may be outstanding, which makes out-of-order reveals
## structurally impossible. Deeper speculation is deliberately not built: a
## template switch or a human line invalidates queued turns, and several stale
## branches is a lifecycle system nobody asked for.
## ON by default in the headless path, accepted under docs/EXPERIMENT_PIPELINE2.md:
## +37.2% throughput, paired delta +5.50 speeches/min against a calibrated noise
## envelope of 1.40, with zero stale replies accepted, never more than one
## request outstanding and a 14ms dwell undershoot against a 24ms tolerance.
##
## NOT ported to the visual app yet. Headless acceptance proves scheduling
## correctness; it says nothing about presentation correctness, which needs its
## own checks (bubble readability, no early reveal, preset changes invalidating
## a prefetched reply, BRB/pause interactions).
var _pipeline := true

## Bumped by anything that invalidates a reply already in flight. A held reply
## whose epoch no longer matches is discarded rather than shown.
var _dispatch_epoch := 0

## The reply waiting for the reading pause to expire, or empty.
var _pending: Dictionary = {}

## When the current reply has been on screen long enough to reveal the next.
var _reveal_at := 0.0

## Guard counters, printed at the end and asserted by the experiment.
var _g_stale_discarded := 0
var _g_max_outstanding := 0
var _g_outstanding := 0

## Shortest time any reply was the current one, in ms. The pipeline must never
## buy throughput by flashing a turn past the viewer faster than the reading
## pause it replaced.
var _g_min_reveal_gap := 999999
var _g_last_reveal_ms := 0
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
			"--max-tokens":
				if v != "": _max_tokens_override = maxi(int(v), 8); i += 1
			"--pipeline":
				_pipeline = true
			"--no-pipeline":
				_pipeline = false
			"--recall":
				if v != "": _recall_mode = v; i += 1
			"--arc":
				_arc_enabled = true
			"--contention":
				_contention_enabled = true
			"--target-every":
				if v != "": _target_every = maxi(int(v), 0); i += 1
			"--escalate-every":
				if v != "": _escalate_every = maxi(int(v), 0); i += 1
			"--no-trim":
				_trim_sentences = false
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

	# A held reply is revealed once the current one has had its reading pause.
	# This runs BEFORE the _waiting guard: in pipelined mode the next request is
	# already in flight while the previous answer waits its turn on screen.
	if _pipeline and not _pending.is_empty() and _elapsed >= _reveal_at:
		var due := _pending
		_pending = {}
		_reveal(due["agent"], due["text"], int(due["latency"]))
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
	# A targeted-engagement event pairs two agents and they speak next, in
	# order. Anything not in that queue waits its normal turn.
	while not _forced_next.is_empty():
		var want: String = _forced_next.pop_front()
		var found := false
		for a in _agents:
			if str(a["display_name"]) == want and not a.get("eliminated", false):
				agent = a
				found = true
				break
		if found:
			break
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
	if _turn_cycle_started_ms > 0:
		# Everything between the previous reply landing and this dispatch: the
		# scheduler's inter-turn interval plus whatever ran in between.
		_t_schedule_gap += Time.get_ticks_msec() - _turn_cycle_started_ms
	_waiting = true
	_wait_started_ms = Time.get_ticks_msec()
	var started_ms := _wait_started_ms
	var captured := agent
	var captured_epoch := _dispatch_epoch
	if _pipeline:
		_g_outstanding += 1
		_g_max_outstanding = maxi(_g_max_outstanding, _g_outstanding)

	_client.chat_completion(
		agent["display_name"],
		agent["model_key"],
		messages,
		func(ok: bool, content: String, http_code: int):
			_on_reply(captured, ok, content, http_code, started_ms, captured_epoch),
		{
			"temperature": float(_inference.get("temperature", 0.85)),
			"max_tokens": _effective_max_tokens(),
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
## The token ceiling actually sent, honouring a CLI override over the roster.
func _effective_max_tokens() -> int:
	if _max_tokens_override > 0:
		return _max_tokens_override
	return int(_inference.get("max_tokens", 110))


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
	if _arc_enabled:
		var phase: int = TopicArcScript.phase_for(_turn, _max_turns)
		var task: String = TopicArcScript.task_for(phase)
		if task != "":
			sys += "

THIS PHASE OF THE DEBATE: %s
" % task
		if phase == TopicArcScript.Phase.TURN and not _arc_pivot_fired:
			_arc_pivot_fired = true
			_arena_facts.append(TopicArcScript.pivot_constraint())
			print("LIVE_ARENA ARC pivot at turn %d" % _turn)
			_write_log({"kind": "arc_pivot", "match_id": _match_id,
				"turn": _turn, "constraint": TopicArcScript.pivot_constraint(),
				"timestamp": Time.get_datetime_string_from_system(true)})
	if _recall_mode != "off":
		var named: Array = []
		for a in _agents:
			named.append(str(a["display_name"]))
		sys += _recall_block(str(agent["display_name"]), named)
	var contention_note := _contention_note(str(agent["display_name"]))
	if contention_note != "":
		sys += contention_note + "
"
	var open_dispute := _dispute_fact()
	if open_dispute != "":
		sys += "

" + open_dispute + "
"
	if not _arena_facts.is_empty():
		# Facts, not orders. The agent is told what changed and left to decide
		# what that means -- the same discipline as the human-line block below.
		sys += "

WHAT HAS CHANGED IN THE ROOM SINCE THIS STARTED:
"
		for f in _arena_facts:
			sys += "- %s
" % f
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


func _on_reply(agent: Dictionary, ok: bool, content: String, http_code: int, started_ms: int, epoch_at_dispatch: int = -1) -> void:
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
	var _t_reply_in := Time.get_ticks_msec()
	_t_generate += latency
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
	# Last, so it trims whatever the earlier steps leave. max_tokens is a hard
	# ceiling and the models write until they hit it, so 58% of replies ended
	# mid-clause; the viewer saw an unfinished thought more often than a
	# finished one.
	if _trim_sentences:
		text = SpeechCleanScript.trim_to_last_sentence(text)
	var _t_after_sanitize := Time.get_ticks_msec()
	_t_sanitize += _t_after_sanitize - _t_reply_in
	# PIPELINED: hold this answer until the current one has had its reading
	# pause, then reveal it from tick(). The request for it was dispatched the
	# moment the previous reply was committed, so generation has been running
	# underneath the pause rather than after it.
	if _pipeline:
		_g_outstanding = maxi(_g_outstanding - 1, 0)
		if epoch_at_dispatch != _dispatch_epoch:
			# Something invalidated this turn while it was in flight. Showing it
			# would put a reply from a superseded state on screen.
			_g_stale_discarded += 1
			_next_turn_at = _elapsed
			return
		_pending = {"agent": agent, "text": text, "latency": latency}
		return

	_reveal(agent, text, latency)


## Commit a reply: it becomes the canonical turn, is published everywhere, and
## (when pipelining) the next request goes out immediately so the next model
## generates during this reply's time on screen.
func _reveal(agent: Dictionary, text: String, latency: int) -> void:
	var _reveal_started_ms := Time.get_ticks_msec()
	if _g_last_reveal_ms > 0:
		_g_min_reveal_gap = mini(_g_min_reveal_gap, _reveal_started_ms - _g_last_reveal_ms)
	_g_last_reveal_ms = _reveal_started_ms
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

	# The turn number travels with the entry. A targeted-engagement event cites
	# a specific earlier turn, and a citation that cannot be resolved back to
	# canonical text must be refused rather than invented.
	_history.append({"speaker": agent["display_name"], "text": text, "turn": _turn})
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

	_t_publish += Time.get_ticks_msec() - _reveal_started_ms
	# The clock for the gap to the NEXT dispatch starts here.
	_turn_cycle_started_ms = Time.get_ticks_msec()
	print("LIVE_ARENA TURN %d %s (%dms) %s" % [
		_turn + 1, agent["display_name"], latency, text.substr(0, 70).replace("\n", " ")])

	_update_crown(agent)

	# ── staged betrayal: a real arena fact with a real non-witness ─────────
	if _betray_turn >= 0 and _turn == _betray_turn and not _betrayal_done:
		_betrayal_done = true
		_stage_betrayal()

	_turn += 1
	_maybe_escalate()
	_maybe_dispute()
	_sweep_contentions()
	_note_contention(str(agent["display_name"]), text)
	_note_scar(str(agent["display_name"]), text)
	# Brief settle so the overlay shows SPEAKING before the next THINKING.
	_next_turn_at = _elapsed + 1.2
	_reveal_at = _next_turn_at

	if _turn >= _max_turns:
		_end_match()
	else:
		agent["state"] = "waiting"
		_state.publish_delta({}, {agent["agent_id"]: {"state": "waiting"}})
		# The canonical turn is committed above, so the next agent composes
		# FROM the reply now on screen -- it is never answering something it
		# has not been given. Dispatching here is what overlaps generation with
		# the reading pause.
		if _pipeline and not _waiting:
			_run_turn()


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
	# Where the wall-clock went, so "overhead" stops being one opaque number.
	var turns := maxi(_turn, 1)
	var accounted := _t_generate + _t_sanitize + _t_publish + _t_schedule_gap
	if _pipeline:
		print("LIVE_ARENA PIPELINE stale_discarded=%d max_outstanding=%d min_reveal_gap=%dms"
			% [_g_stale_discarded, _g_max_outstanding, _g_min_reveal_gap])
	print("LIVE_ARENA DWELL min_reveal_gap=%dms" % _g_min_reveal_gap)
	print("LIVE_ARENA TIMING per turn (ms): generate=%d sanitize=%d publish=%d gap=%d accounted=%d"
		% [_t_generate / turns, _t_sanitize / turns, _t_publish / turns,
			_t_schedule_gap / turns, accounted / turns])
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


## Change the situation every _escalate_every turns.
##
## Fires AFTER the turn counter advances and BEFORE the next request is built,
## so the next agent is the first to see the new fact. Logged as its own record
## so a replay knows exactly which turn the arena changed under.
func _maybe_escalate() -> void:
	if _escalate_every <= 0 or _turn <= 0:
		return
	if _turn % _escalate_every != 0:
		return
	if _escalations_fired >= ESCALATIONS.size():
		return
	var text: String = ESCALATIONS[_escalations_fired]
	_escalations_fired += 1
	_arena_facts.append(text)
	print("LIVE_ARENA ESCALATION %d at turn %d: %s"
		% [_escalations_fired, _turn, text.substr(0, 60)])
	_write_log({
		"kind": "escalation",
		"match_id": _match_id,
		"turn": _turn,
		"index": _escalations_fired,
		"text": text,
		"timestamp": Time.get_datetime_string_from_system(true),
	})
	_state.publish_delta({"last_action": "the situation changed"}, {})


## ── Targeted engagement ────────────────────────────────────────────────────
##
## INVARIANT   a cited claim exists verbatim in the canonical transcript.
## DETECTION   the citation carries a turn number; the text is re-checked
##             against the history entry for that turn.
## TEETH       an unresolvable citation refuses the event outright. The arena
##             never attributes a claim to an agent that the agent did not make.
## RECOVERY    try the next eligible claim; if none resolve, skip this event and
##             continue the match unchanged.
## PROOF       scripts/arena/targeting_selftest.gd corrupts the stored turn
##             number and the source text, and both must refuse.


## A claim is worth challenging if it is long enough to be a position rather
## than an aside, and short enough to quote back without becoming a speech.
const CLAIM_MIN_WORDS := 8
const CLAIM_MAX_CHARS := 180


## First substantial sentence of a turn, or "" when there is none.
static func extract_claim(text: String) -> String:
	var body := text.strip_edges()
	for sep in [". ", "? ", "! "]:
		var i := body.find(sep)
		if i > 0 and i < CLAIM_MAX_CHARS:
			var head := body.substr(0, i + 1).strip_edges()
			if head.split(" ", false).size() >= CLAIM_MIN_WORDS:
				return head
	if body.length() <= CLAIM_MAX_CHARS and body.split(" ", false).size() >= CLAIM_MIN_WORDS:
		return body
	# No sentence end inside the limit. Take the longest whole-word prefix that
	# fits: still a verbatim substring of the canonical turn, so provenance is
	# unaffected.
	#
	# Without this the function returned "" for any turn whose first sentence
	# ran past 180 characters, which after sentence-trimming is most of them.
	# That is why contention memory fired only 0.75 times per match -- the
	# mechanism was starved by a claim extractor that almost never succeeded,
	# not by the arena lacking disagreements.
	if body.length() > CLAIM_MAX_CHARS:
		var cut := body.substr(0, CLAIM_MAX_CHARS)
		var last_space := cut.rfind(" ")
		if last_space > 40:
			var prefix := cut.substr(0, last_space).strip_edges()
			if prefix.split(" ", false).size() >= CLAIM_MIN_WORDS:
				return prefix
	return ""


## Verify a citation against canonical history. Returns true only when the
## named turn exists, was spoken by the named agent, and contains the claim.
static func citation_holds(history: Array, turn_no: int, speaker: String,
		claim: String) -> bool:
	if claim.strip_edges() == "":
		return false
	for h in history:
		if int(h.get("turn", -1)) != turn_no:
			continue
		if str(h.get("speaker", "")) != speaker:
			return false
		return str(h.get("text", "")).find(claim) != -1
	return false


## Choose a claim to challenge and the pair who will trade turns over it.
## Returns {} when nothing can be cited safely.
func _pick_dispute() -> Dictionary:
	# Most recent first: a live disagreement beats an old one.
	for i in range(_history.size() - 1, -1, -1):
		var h: Dictionary = _history[i]
		var claim := extract_claim(str(h.get("text", "")))
		if claim == "":
			continue
		var target := str(h.get("speaker", ""))
		var turn_no := int(h.get("turn", -1))
		if not citation_holds(_history, turn_no, target, claim):
			continue
		# Someone other than the speaker has to do the challenging, and it
		# should not be the same agent every time.
		var best := ""
		var best_count := 1 << 30
		for a in _agents:
			var name := str(a["display_name"])
			if name == target or a.get("eliminated", false):
				continue
			var used := int(_challenge_counts.get(name, 0))
			if used < best_count:
				best_count = used
				best = name
		if best != "":
			_challenge_counts[best] = best_count + 1
			return {"claim": claim, "target": target, "turn": turn_no,
				"challenger": best}
	return {}


func _maybe_target() -> void:
	if _target_every <= 0 or _turn <= 0 or _turn % _target_every != 0:
		return
	var d := _pick_dispute()
	if d.is_empty():
		# TEETH. No verifiable claim, so no event. Inventing a paraphrase and
		# attributing it to an agent would be the arena lying about its own
		# transcript.
		_target_refusals += 1
		print("LIVE_ARENA TARGET REFUSED at turn %d: no claim resolved to canonical text" % _turn)
		_write_log({"kind": "target_refused", "match_id": _match_id, "turn": _turn,
			"reason": "no citation could be verified",
			"timestamp": Time.get_datetime_string_from_system(true)})
		return

	_targets_fired += 1
	var fact := ("DIRECT CHALLENGE: %s said in turn %d, \"%s\" — %s, take that exact "
		+ "claim apart. %s answers next.") % [d["target"], d["turn"], d["claim"],
		d["challenger"], d["target"]]
	_arena_facts.append(fact)
	_forced_next = [str(d["challenger"]), str(d["target"])]
	print("LIVE_ARENA TARGET %d at turn %d: %s -> %s (claim from turn %d)"
		% [_targets_fired, _turn, d["challenger"], d["target"], d["turn"]])
	_write_log({
		"kind": "target", "match_id": _match_id, "turn": _turn,
		"index": _targets_fired, "challenger": d["challenger"],
		"target": d["target"], "source_turn": d["turn"], "claim": d["claim"],
		"timestamp": Time.get_datetime_string_from_system(true),
	})


## ── Dispute episode: invariants ────────────────────────────────────────────
##
## INVARIANT   a dispute cites a claim that exists in canonical history;
##             challenger != target; both are active; the exchange count is
##             finite; an expired dispute cannot influence any prompt; only one
##             dispute is active at a time; no event fires without enough turns
##             left to observe its effect.
## DETECTION   dispute_eligible() and citation_holds() check each of these.
## TEETH       an ineligible dispute is refused and logged, never injected.
## RECOVERY    the next eligible claim is tried; otherwise play continues.
## PROOF       dispute_selftest.gd sabotages each invariant in turn.


## Is there room left in the match to observe what an episode does?
static func has_followup_room(turn: int, max_turns: int, exchanges: int,
		followup: int) -> bool:
	return turn + exchanges + followup <= max_turns


## Every condition a dispute must satisfy before it may be injected.
static func dispute_eligible(d: Dictionary, history: Array, active: Array,
		turn: int, max_turns: int, current: Dictionary) -> bool:
	if not current.is_empty():
		return false                                   # one at a time
	if d.is_empty():
		return false
	var challenger := str(d.get("challenger", ""))
	var target := str(d.get("target", ""))
	if challenger == "" or target == "" or challenger == target:
		return false
	if not active.has(challenger) or not active.has(target):
		return false
	if int(d.get("max_exchanges", 0)) <= 0:
		return false
	if not has_followup_room(turn, max_turns, int(d.get("max_exchanges", 0)),
			DISPUTE_FOLLOWUP_TURNS):
		return false
	return citation_holds(history, int(d.get("turn", -1)), target,
		str(d.get("claim", "")))


## The prompt fragment for an ACTIVE dispute. An expired one contributes
## nothing: the scaffold is removed, not merely ignored.
func _dispute_fact() -> String:
	if _dispute.is_empty() or str(_dispute.get("status", "")) != "active":
		return ""
	return ("OPEN DISPUTE: %s said in turn %d, \"%s\". %s is challenging that "
		+ "exact claim. Settle it between you.") % [
		_dispute["target"], _dispute["claim_turn"], _dispute["claim"],
		_dispute["challenger"]]


func _expire_dispute(reason: String) -> void:
	if _dispute.is_empty():
		return
	_dispute["status"] = "expired"
	_dispute["ended_turn"] = _turn
	_dispute_history.append(_dispute.duplicate())
	print("LIVE_ARENA DISPUTE ended at turn %d (%s)" % [_turn, reason])
	_write_log({"kind": "dispute_end", "match_id": _match_id, "turn": _turn,
		"reason": reason, "exchanges": int(_dispute.get("exchange_count", 0)),
		"timestamp": Time.get_datetime_string_from_system(true)})
	_dispute = {}


func _maybe_dispute() -> void:
	if _target_every <= 0 or _turn <= 0:
		return
	# Count the forced exchanges as they happen and retire the episode.
	if not _dispute.is_empty():
		_dispute["exchange_count"] = int(_dispute.get("exchange_count", 0)) + 1
		if int(_dispute["exchange_count"]) >= int(_dispute["max_exchanges"]):
			_expire_dispute("exchanges complete")
		return
	if _turn % _target_every != 0:
		return

	var d := _pick_dispute()
	var active: Array = []
	for a in _agents:
		if not a.get("eliminated", false):
			active.append(str(a["display_name"]))
	if not d.is_empty():
		d["max_exchanges"] = DISPUTE_MAX_EXCHANGES
	if not dispute_eligible(d, _history, active, _turn, _max_turns, _dispute):
		_target_refusals += 1
		var why := "no verifiable claim"
		if not d.is_empty() and not has_followup_room(_turn, _max_turns,
				DISPUTE_MAX_EXCHANGES, DISPUTE_FOLLOWUP_TURNS):
			why = "not enough turns left to observe the effect"
		print("LIVE_ARENA DISPUTE REFUSED at turn %d: %s" % [_turn, why])
		_write_log({"kind": "dispute_refused", "match_id": _match_id,
			"turn": _turn, "reason": why,
			"timestamp": Time.get_datetime_string_from_system(true)})
		return

	_targets_fired += 1
	_dispute = {
		"claim": d["claim"], "claim_turn": int(d["turn"]),
		"claim_speaker": str(d["target"]), "challenger": str(d["challenger"]),
		"target": str(d["target"]), "started_turn": _turn,
		"exchange_count": 0, "max_exchanges": DISPUTE_MAX_EXCHANGES,
		"expires_turn": _turn + DISPUTE_MAX_EXCHANGES, "status": "active",
	}
	# A challenges, B answers, A rebuts once.
	_forced_next = [str(d["challenger"]), str(d["target"]), str(d["challenger"])]
	print("LIVE_ARENA DISPUTE %d at turn %d: %s vs %s over turn %d"
		% [_targets_fired, _turn, d["challenger"], d["target"], int(d["turn"])])
	_write_log({
		"kind": "dispute_start", "match_id": _match_id, "turn": _turn,
		"index": _targets_fired, "challenger": d["challenger"],
		"target": d["target"], "source_turn": int(d["turn"]),
		"claim": d["claim"], "max_exchanges": DISPUTE_MAX_EXCHANGES,
		"timestamp": Time.get_datetime_string_from_system(true),
	})

## Contention memory: invariants.
##
## INVARIANT   every active contention names a claim that exists verbatim in
##             canonical history, spoken by the agent it is attributed to; the
##             pair are distinct and active; intensity decays; TTL is finite;
##             at most one per agent and two in total; reinforcement is capped;
##             an expired contention influences nothing and never returns.
## DETECTION   contention_admissible(), plus a decay sweep every turn.
## TEETH       an inadmissible contention is refused; an expired one is removed
##             from the array rather than flagged, because state that lingers
##             can still be read by mistake.
## RECOVERY    the arena continues with no contention at all.
## PROOF       contention_selftest.gd sabotages each bound in turn.


static func contention_admissible(c: Dictionary, history: Array, active: Array,
		existing: Array, max_total: int, max_per_agent: int) -> bool:
	if c.is_empty():
		return false
	var a := str(c.get("agent_a", ""))
	var b := str(c.get("agent_b", ""))
	if a == "" or b == "" or a == b:
		return false
	if not active.has(a) or not active.has(b):
		return false
	if not citation_holds(history, int(c.get("source_turn", -1)), b,
			str(c.get("claim", ""))):
		return false
	if existing.size() >= max_total:
		return false
	var per := {}
	for e in existing:
		var ea := str(e.get("agent_a", ""))
		var eb := str(e.get("agent_b", ""))
		per[ea] = int(per.get(ea, 0)) + 1
		per[eb] = int(per.get(eb, 0)) + 1
	if int(per.get(a, 0)) >= max_per_agent or int(per.get(b, 0)) >= max_per_agent:
		return false
	return true


## Intensity after `turns` have passed. Never negative.
static func decayed_intensity(start: float, turns: int, rate: float) -> float:
	return maxf(start - rate * float(maxi(turns, 0)), 0.0)


## True when a contention has run out of time or of heat.
static func contention_expired(c: Dictionary, turn: int, ttl: int,
		floor_intensity: float, decay: float) -> bool:
	var age := turn - int(c.get("created_turn", turn))
	if age >= ttl:
		return true
	var last := int(c.get("last_reinforced_turn", c.get("created_turn", turn)))
	return decayed_intensity(float(c.get("intensity", 0.0)), turn - last, decay) < floor_intensity


func _sweep_contentions() -> void:
	var kept: Array[Dictionary] = []
	for c in _contentions:
		if contention_expired(c, _turn, CONTENTION_TTL_TURNS,
				CONTENTION_MIN_INTENSITY, CONTENTION_DECAY_PER_TURN):
			print("LIVE_ARENA CONTENTION %d expired at turn %d (age %d, reinforced %d)"
				% [int(c["id"]), _turn, _turn - int(c["created_turn"]),
					int(c["reinforcement_count"])])
			_write_log({"kind": "contention_end", "match_id": _match_id,
				"turn": _turn, "id": int(c["id"]),
				"reinforcements": int(c["reinforcement_count"]),
				"timestamp": Time.get_datetime_string_from_system(true)})
		else:
			kept.append(c)
	_contentions = kept


## The line an involved agent sees. Describes state; asks for nothing.
func _contention_note(agent_name: String) -> String:
	for c in _contentions:
		var other := ""
		if str(c["agent_a"]) == agent_name:
			other = str(c["agent_b"])
		elif str(c["agent_b"]) == agent_name:
			other = str(c["agent_a"])
		if other == "":
			continue
		return "
UNRESOLVED: you and %s still disagree about \"%s\" from turn %d. It has not been settled. You are not required to raise it." % [other, str(c["claim"]), int(c["source_turn"])]
	return ""


## Record an organic disagreement, if one just happened and there is room.
func _note_contention(speaker: String, text: String) -> void:
	if not _contention_enabled:
		return
	var lower := text.to_lower()
	var challenged := false
	for w in ["disagree", "wrong", "however", "actually", "refute", "reject",
			"mistaken", "incorrect", "flawed", "misses", "overlooks"]:
		if lower.find(w) != -1:
			challenged = true
			break
	if not challenged:
		return
	var target := ""
	for a in _agents:
		var nm := str(a["display_name"])
		if nm != speaker and lower.find(nm.to_lower()) != -1:
			target = nm
			break
	if target == "":
		return

	for c in _contentions:
		var same := (str(c["agent_a"]) == speaker and str(c["agent_b"]) == target) 			or (str(c["agent_a"]) == target and str(c["agent_b"]) == speaker)
		if same:
			if int(c["reinforcement_count"]) >= CONTENTION_MAX_REINFORCEMENTS:
				return
			c["reinforcement_count"] = int(c["reinforcement_count"]) + 1
			c["last_reinforced_turn"] = _turn
			c["intensity"] = minf(float(c["intensity"]) + 0.2, 1.0)
			return

	var claim := ""
	var src := -1
	for i in range(_history.size() - 1, -1, -1):
		var h: Dictionary = _history[i]
		if str(h.get("speaker", "")) != target:
			continue
		claim = extract_claim(str(h.get("text", "")))
		src = int(h.get("turn", -1))
		break
	if claim == "":
		return
	var active: Array = []
	for a in _agents:
		if not a.get("eliminated", false):
			active.append(str(a["display_name"]))
	var c2 := {"agent_a": speaker, "agent_b": target, "claim": claim,
		"source_turn": src, "created_turn": _turn, "last_reinforced_turn": _turn,
		"intensity": CONTENTION_START_INTENSITY, "reinforcement_count": 0}
	if not contention_admissible(c2, _history, active, _contentions,
			CONTENTION_MAX_TOTAL, CONTENTION_MAX_PER_AGENT):
		return
	_contention_seq += 1
	c2["id"] = _contention_seq
	_contentions.append(c2)
	print("LIVE_ARENA CONTENTION %d opened at turn %d: %s vs %s over turn %d"
		% [_contention_seq, _turn, speaker, target, src])
	_write_log({"kind": "contention_start", "match_id": _match_id, "turn": _turn,
		"id": _contention_seq, "agent_a": speaker, "agent_b": target,
		"source_turn": src, "claim": claim,
		"timestamp": Time.get_datetime_string_from_system(true)})

## ── Layered recall wiring ──────────────────────────────────────────────────


## A turn earns a scar when it takes a position against someone. Sparse by
## construction: bounded, and only shapes that mattered.
func _note_scar(speaker: String, text: String) -> void:
	if _recall_mode == "off" or _scars.size() >= MAX_SCARS:
		return
	var shape: String = GonzoScript.shape_of(text)
	if shape == "assert":
		return
	var other := ""
	var low := text.to_lower()
	for a in _agents:
		var nm := str(a["display_name"])
		if nm != speaker and low.find(nm.to_lower()) != -1:
			other = nm
			break
	var excerpt: String = extract_claim(text)
	if excerpt == "":
		return
	# Take the turn number from the history entry itself. _note_scar runs after
	# _turn has been incremented, so using _turn here produced a scar pointing
	# one turn past its own source -- provenance then refused every recall,
	# silently and correctly, for a bug that was mine.
	var src := -1
	if not _history.is_empty():
		var last: Dictionary = _history[_history.size() - 1]
		if str(last.get("speaker", "")) == speaker:
			src = int(last.get("turn", -1))
	if src < 0:
		return
	_scars.append({
		"excerpt": excerpt, "source_turn": src, "source_speaker": speaker,
		"other_speaker": other, "shape": shape, "intensity": 0.8,
		"last_reinforced_turn": src, "last_recalled_turn": -999,
		"recall_count": 0,
	})
	print("LIVE_ARENA SCAR %d from turn %d (%s, %s)"
		% [_scars.size(), src, speaker, shape])


## Choose what to inject. Real mode takes the highest-resonance eligible scars;
## sham takes the LOWEST-scoring provenance-valid ones, so the prompt carries
## the same weight of canonical text with none of the relevance.
func _select_recalls(now_speaker: String, named_now: Array) -> Array:
	if _recall_mode == "off" or _scars.is_empty():
		return []
	var recent := ""
	for i in range(_history.size() - 1, maxi(_history.size() - 3, -1), -1):
		recent += " " + str(_history[i].get("text", ""))

	var scored: Array = []
	for idx in _scars.size():
		var sc: Dictionary = _scars[idx]
		if not GonzoScript.provenance_holds(sc, _history):
			continue
		if _turn - int(sc.get("last_recalled_turn", -999)) < GonzoScript.RECALL_COOLDOWN_TURNS:
			continue
		if _turn - int(sc.get("source_turn", _turn)) < GonzoScript.MIN_RECALL_DISTANCE:
			continue
		var v: float = GonzoScript.score(sc, recent, now_speaker, named_now, _turn)
		scored.append({"i": idx, "score": v})
	if scored.is_empty():
		return []
	scored.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))

	var picked: Array = []
	if _recall_mode == "real":
		for e in scored:
			if float(e["score"]) < GonzoScript.MIN_ELIGIBLE_SCORE:
				break
			picked.append(int(e["i"]))
			if picked.size() >= GonzoScript.MAX_RECALLS_PER_PROMPT:
				break
	else:
		# SHAM. Matched to the real arm on everything except relevance:
		# same count, same formatting, same injection position, same cooldown
		# and distance rules (both applied above), and the same eligibility
		# COUNT -- it takes the least-resonant members of the very same
		# candidate pool the real arm draws from.
		#
		# Without that matching, a Q1 win could be explained by Q1 happening to
		# receive older, shorter or fewer memories rather than by resonance.
		var want := 0
		for e in scored:
			if float(e["score"]) < GonzoScript.MIN_ELIGIBLE_SCORE:
				break
			want += 1
			if want >= GonzoScript.MAX_RECALLS_PER_PROMPT:
				break
		for j in range(scored.size() - 1, -1, -1):
			if picked.size() >= want:
				break
			picked.append(int(scored[j]["i"]))
	return picked


## Render the chosen memories, re-checking provenance AT THE SINK.
##
## TEETH: a scar that cannot resolve its source here is omitted entirely. It is
## never replaced by a nearby turn, a reconstructed quote, or a best guess --
## the arena shows a real excerpt or it shows nothing.
func _recall_block(now_speaker: String, named_now: Array) -> String:
	var picked := _select_recalls(now_speaker, named_now)
	if picked.is_empty():
		return ""
	var out := ""
	for idx in picked:
		var sc: Dictionary = _scars[idx]
		if not GonzoScript.provenance_holds(sc, _history):
			print("LIVE_ARENA RECALL OMITTED turn %d: source unresolvable" % _turn)
			continue
		out += "

" + GonzoScript.render(sc)
		# Recall never reinforces and never resets decay.
		_scars[idx] = GonzoScript.on_recall(sc, _turn)
		_recall_log.append({"turn": _turn, "source_turn": int(sc["source_turn"]),
			"source_speaker": str(sc["source_speaker"]),
			"excerpt": str(sc["excerpt"]), "to": now_speaker})
		_write_log({"kind": "recall", "match_id": _match_id, "turn": _turn,
			"mode": _recall_mode, "source_turn": int(sc["source_turn"]),
			"source_speaker": str(sc["source_speaker"]),
			"excerpt": str(sc["excerpt"]), "to": now_speaker,
			"distance": _turn - int(sc["source_turn"]),
			"timestamp": Time.get_datetime_string_from_system(true)})
	return out
