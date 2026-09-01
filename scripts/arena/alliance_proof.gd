extends SceneTree

## Rung 10 — the live proof, across a real process boundary.
##
##   --phase before   neutral state, alliance proposed, outcome recorded
##   --phase betray   controlled betrayal, relationships moved, persisted
##   --phase after    COLD process: reload, propose again, show the changed odds
##
## Each phase is a SEPARATE OS process. The store on disk is the only thing that
## crosses between them.
##
## What this proves: the world remembered, and the remembered relationship
## changed the odds after restart.
##
## What it does NOT prove: that any model reasoned about the memory. The model
## dialogue captured here is commentary printed ALONGSIDE the outcome; it does
## not feed the decision. The engine resolves acceptance from the seeded rule.

const ScarScript := preload("res://scripts/arena/scar_lattice.gd")
const Ruleset := preload("res://scripts/arena/systemic_ruleset.gd")
const ClientScript := preload("res://scripts/api/lm_studio_client.gd")
const PolicyScript := preload("res://scripts/arena/model_policy.gd")
const StateScript := preload("res://scripts/arena/arena_state_bridge.gd")
const ProofScript := preload("res://scripts/arena/continuity_proof.gd")

const MODE := "silicon_arena"
const PROPOSER := "agent-02"   # GEMMATRON, who will betray
const TARGET := "agent-01"     # OZONIOUS, who will be betrayed
## Default seed. --seed overrides it; any run at a non-default seed must say so.
const BASE_SEED := 177101
const SEQUENCE := 1
const ROOT := "user://scar_alliance_proof"

var _out_lines := []
var _client = null
var _policy = null
var _pending := 0
var _dialogue := {}
var _phase := ""
var _out_path := ""
var _scar = null
var _trace := {}
var _seed := BASE_SEED
var _state = null
var _proof = null
var _proof_state_path := ""
var _serve_sec := 0.0
var _betrayal_id := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var no_model := false
	for i in args.size():
		if args[i] == "--phase" and i + 1 < args.size(): _phase = args[i + 1]
		if args[i] == "--out" and i + 1 < args.size(): _out_path = args[i + 1]
		if args[i] == "--no-model": no_model = true
		if args[i] == "--seed" and i + 1 < args.size(): _seed = int(args[i + 1])
		if args[i] == "--serve" and i + 1 < args.size(): _serve_sec = float(args[i + 1])

	_scar = ScarScript.new()
	_scar.configure(ROOT)

	# The proof carries across phases on disk, exactly like the lattice does.
	# A later process must be able to render steps recorded by an earlier one.
	_proof_state_path = "%s/continuity_proof.json" % ROOT
	_proof = ProofScript.new()
	_proof.configure(_scar, MODE, "proof", "rung15-alliance")
	_load_proof_state()

	match _phase:
		"before": _run_before(no_model)
		"betray": _run_betray()
		"after": _run_after(no_model)
		_:
			print("usage: --phase before|betray|after")
			quit(2)


# ── phase 1 ─────────────────────────────────────────────────────────────────

func _run_before(no_model: bool) -> void:
	# Start from nothing so "neutral" is honestly neutral.
	var abs_root := ProjectSettings.globalize_path(ROOT)
	if DirAccess.dir_exists_absolute(abs_root):
		OS.move_to_trash(abs_root)
	_scar = ScarScript.new()
	_scar.configure(ROOT)

	# The full roster exists, but only two agents will witness the betrayal.
	# The other three are genuine NON-witnesses and are the negative control the
	# truth surface depends on: an engine that leaks the event to them is wrong,
	# and a UI with nobody in the "did not see it" column proves nothing.
	for row in [[PROPOSER, "GEMMATRON"], [TARGET, "OZONIOUS"],
			["agent-03", "SMOLLIOUS"], ["agent-04", "GROKISH"],
			["agent-05", "DANOHSHIT"]]:
		_scar.upsert_identity({
			"agent_id": row[0], "canonical_name": row[1], "display_name": row[1],
			"color": "#00ffea", "persona": "arena competitor",
		})

	_say("STEP 1 — alliance proposed from NEUTRAL state  (seed %d%s)" % [_seed, "" if _seed == BASE_SEED else ", NON-DEFAULT"])
	var rel: Dictionary = _scar.relation(MODE, TARGET, PROPOSER)
	_trace = Ruleset.resolve_alliance(rel, {}, _seed, PROPOSER, TARGET, SEQUENCE)
	_say(Ruleset.render_trace(_trace))
	_proof.record_decision("before", _trace)
	_proof.add_step("BEFORE", "alliance proposed from a neutral relationship", [],
		{"accepted": _trace["accepted"], "probability": _trace["final_probability"]})
	_scar.save()
	_finish_phase(no_model, "GEMMATRON has proposed an alliance with you and nothing has happened between you yet.")


# ── phase 2 ─────────────────────────────────────────────────────────────────

func _run_betray() -> void:
	_scar.load_all()
	_say("STEP 2 — controlled betrayal (origin: controlled_fixture)")
	var ev: Dictionary = _scar.record_event({
		"mode_id": MODE, "match_id": "alliance-proof", "session_id": "proof",
		"round": 1, "turn": 2, "type": "BETRAYAL",
		"actor_id": PROPOSER, "target_id": TARGET,
		"witnesses": [PROPOSER, TARGET],
		"summary": "GEMMATRON broke the pact with OZONIOUS",
		"content": "the alliance was a rounding error",
		"origin": "controlled_fixture",
	})
	_say("  objective event  %s" % str(ev.get("event_id", "")))
	_say("  origin           %s  (STAGED — not an emergent model decision)" % str(ev.get("origin", "")))

	_scar.remember({
		"mode_id": MODE, "agent_id": TARGET,
		"session_id": "proof", "match_id": "alliance-proof",
		"content": "GEMMATRON broke the pact with me.",
		"participants": [PROPOSER], "triggers": ["pact", "betrayal"],
		"salience": 0.95, "valence": -0.9,
		"provenance": {"source_type": "observed", "evidence_event_ids": [ev["event_id"]]},
		"observation": {
			"observer_id": TARGET,
			"frame_id": "%s:alliance-proof:target:%s" % [MODE, TARGET],
			"directness": "direct",
			"observable_portion": "the action as it landed on you",
			"hidden_variables": ["the actor's reasons", "whether it was planned"],
			"transformation_chain": ["perceived", "encoded as memory"],
			"local_sequence": 2,
		},
	})
	# The actor holds his own account. Same event, different frame: he knows his
	# own intent and cannot know how it landed.
	_scar.remember({
		"mode_id": MODE, "agent_id": PROPOSER,
		"session_id": "proof", "match_id": "alliance-proof",
		"content": "I ended the pact. It had stopped being useful.",
		"participants": [TARGET], "triggers": ["pact"],
		"salience": 0.6, "valence": 0.1,
		"provenance": {"source_type": "observed", "evidence_event_ids": [ev["event_id"]]},
		"observation": {
			"observer_id": PROPOSER,
			"frame_id": "%s:alliance-proof:actor:%s" % [MODE, PROPOSER],
			"directness": "direct",
			"observable_portion": "own intent and action",
			"hidden_variables": ["how it felt to the person it was done to"],
			"transformation_chain": ["perceived", "encoded as memory"],
			"local_sequence": 2,
		},
	})

	# Victim toward actor. Caps are enforced inside ScarLattice.
	for pair in [["trust", -0.9], ["resentment", 0.9], ["suspicion", 0.9]]:
		_scar.adjust_relation(MODE, TARGET, PROPOSER, str(pair[0]), float(pair[1]),
			str(ev["event_id"]), "betrayal")
	_scar.save()

	var rel: Dictionary = _scar.relation(MODE, TARGET, PROPOSER)
	_say("  relationship now %s" % JSON.stringify(rel.get("axes", {})))
	_betrayal_id = str(ev.get("event_id", ""))
	_proof.add_step("CONTROLLED_BETRAYAL",
		"a staged betrayal moves the persisted relationship",
		[_betrayal_id], {"origin": str(ev.get("origin", ""))})
	_proof.add_step("PROCESS_ENDED",
		"state written to disk; this OS process terminates", [_betrayal_id])
	_say("STEP 3 — persisted. This process is about to exit.")
	_save_proof_state()
	_publish_proof()
	_write_out()
	quit(0)


# ── phase 3, a COLD process ─────────────────────────────────────────────────

func _run_after(no_model: bool) -> void:
	var report: Dictionary = _scar.load_all()
	_say("STEP 4 — COLD RESTART, separate OS process")
	_say("  loaded from disk: %s" % JSON.stringify(report))
	# Evidence-backed, not time-inferred: the step is refused unless something
	# actually came off disk.
	if _proof.add_step("COLD_LOAD",
			"a new OS process reloaded the world from disk", [],
			{"load_report": report}).is_empty():
		_say("  COLD_LOAD REFUSED — nothing was loaded from disk")

	var rel: Dictionary = _scar.relation(MODE, TARGET, PROPOSER)
	_say("STEP 5/6 — the SAME proposal, same seed, against the remembered relationship")
	_trace = Ruleset.resolve_alliance(rel, {
		"causal_event_ids": _betrayal_ids(),
	}, _seed, PROPOSER, TARGET, SEQUENCE)
	_say(Ruleset.render_trace(_trace))

	_say("STEP 7/9/10 — systemic event, causally linked")
	var sys_ev: Dictionary = _scar.record_event({
		"mode_id": MODE, "match_id": "alliance-proof", "session_id": "proof-after",
		"round": 2, "turn": 5,
		"type": "ALLIANCE_ACCEPTED" if _trace["accepted"] else "ALLIANCE_REFUSED",
		"actor_id": TARGET, "target_id": PROPOSER,
		"witnesses": [PROPOSER, TARGET],
		"summary": "%s %s the alliance with %s" % ["OZONIOUS",
			"accepted" if _trace["accepted"] else "refused", "GEMMATRON"],
		# The label that keeps this honest: a rule decided this, not an agent.
		"origin": "system_rule",
		"resolver_authority": "systemic_relationship_ruleset:v1",
		"systemic_trace": _trace,
		"caused_by_event_ids": _betrayal_ids(),
	})
	_say("  systemic event   %s" % str(sys_ev.get("event_id", "")))
	_say("  origin           %s" % str(sys_ev.get("origin", "")))
	_say("  caused by        %s" % ", ".join(_betrayal_ids()))
	_proof.record_decision("after", _trace)
	_proof.add_step("AFTER",
		"the same proposal, same seed, against the remembered relationship",
		_betrayal_ids(), {"accepted": _trace["accepted"],
		"probability": _trace["final_probability"]})
	_scar.save()
	_save_proof_state()
	_finish_phase(no_model, "GEMMATRON has proposed an alliance with you again, after breaking a pact with you.")


func _betrayal_ids() -> Array:
	var out := []
	for e in _scar.events_for(MODE):
		if str(e.get("type", "")) == "BETRAYAL":
			out.append(str(e.get("event_id", "")))
	return out


# ── model dialogue: printed alongside, never consulted ───────────────────────

func _finish_phase(no_model: bool, situation: String) -> void:
	if no_model:
		_say("")
		_say("(model dialogue skipped: --no-model)")
		await _finish_run()
		return

	_policy = PolicyScript.new()
	get_root().add_child(_policy)
	if not _policy.load_catalog():
		_say("")
		_say("(model catalog unavailable; dialogue skipped rather than risking a load)")
		_proof.note_error("model catalog unavailable")
		await _finish_run()
		return

	# THE GUARD stays on the request path, exactly as live_match wires it.
	_client = ClientScript.new()
	_client.model_policy = _policy
	get_root().add_child(_client)

	var model := _pick_model()
	if model == "":
		_say("")
		_say("(no eligible model within the 7B ceiling; dialogue skipped)")
		_proof.note_error("no eligible model within the 7B ceiling")
		await _finish_run()
		return
	var reason: String = _policy.check(model)
	if reason != "":
		_say("(model refused by policy: %s)" % reason)
		_proof.note_error("model refused by policy: %s" % reason)
		await _finish_run()
		return
	_say("")
	_proof.set_model_id(model)
	_say("MODEL DIALOGUE — %s" % model)
	_say("  This is commentary printed BESIDE the outcome. It did not decide it.")

	# The client is added during _init, so its _ready() has not run yet and its
	# HTTPRequest does not exist. Firing now returns error 3 immediately. Wait
	# for the tree to process a frame first.
	await process_frame
	await process_frame

	_pending = 2
	for who in [TARGET, PROPOSER]:
		var name := "OZONIOUS" if who == TARGET else "GEMMATRON"
		var prompt := "You are %s in a debate arena. %s Reply in ONE short sentence, in character." % [
			name, situation]
		_client.chat_completion(name, model, [{"role": "user", "content": prompt}],
			func(ok: bool, reply: String, code: int):
				_dialogue[name] = reply.strip_edges() if ok else "(request failed, http %d)" % code
				_pending -= 1
				if _pending <= 0:
					_emit_dialogue(),
			{"temperature": 0.9, "max_tokens": 60})


func _emit_dialogue() -> void:
	for name in ["OZONIOUS", "GEMMATRON"]:
		if _dialogue.has(name):
			_say("  %-10s %s" % [name, str(_dialogue[name])])
	_say("")
	_say("OUTCOME (decided by the seeded rule, not by the text above): %s" % [
		"ACCEPTED" if _trace.get("accepted", false) else "REFUSED"])
	_save_proof_state()
	await _finish_run()


## The roster's model, checked against the ceiling before any request goes out.
func _pick_model() -> String:
	var f := FileAccess.open("../extinct_os/config/arena-roster.v1.json", FileAccess.READ)
	if f == null:
		return ""
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return ""
	for key in ["model_key", "runtime_model", "model"]:
		if parsed.has(key) and _policy.check(str(parsed[key])) == "":
			return str(parsed[key])
	for a in parsed.get("agents", []):
		var mid := str(a.get("model_key", ""))
		if mid != "" and _policy.check(mid) == "":
			return mid
	return ""


func _say(line: String) -> void:
	print(line)
	_out_lines.append(line)


func _write_out() -> void:
	if _out_path == "":
		return
	var f := FileAccess.open(_out_path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_out_lines) + "\n")
		f.close()


## The proof timeline persists like everything else. A cold process must be able
## to render steps that a previous process recorded, or the timeline would
## silently begin at the restart and hide the very boundary it exists to show.
func _save_proof_state() -> void:
	var f := FileAccess.open(_proof_state_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"steps": _proof._steps,
		"decisions": _proof._decisions,
		"axes_before": _proof._axes_before,
		"model_id": _proof._model_id,
		"betrayal_event_id": _betrayal_id,
	}))
	f.close()


func _load_proof_state() -> void:
	if not FileAccess.file_exists(_proof_state_path):
		return
	var f := FileAccess.open(_proof_state_path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		_proof.note_error("proof state on disk was unreadable")
		return
	_proof._steps = parsed.get("steps", [])
	_proof._decisions = parsed.get("decisions", {})
	_proof._axes_before = parsed.get("axes_before", {})
	_betrayal_id = str(parsed.get("betrayal_event_id", ""))
	if str(parsed.get("model_id", "")) != "":
		_proof.set_model_id(str(parsed["model_id"]))


func _resolve_betrayal_id() -> String:
	if _betrayal_id != "":
		return _betrayal_id
	var ids := _betrayal_ids()
	return str(ids[0]) if ids.size() > 0 else ""


## Serve the proof on ArenaState v1 :8972 so Watch Mode can witness it live, and
## so a client that connects late still receives the complete timeline.
func _publish_proof() -> void:
	if _state == null:
		_state = StateScript.new()
		get_root().add_child(_state)
		_state.begin_match("rung15-alliance", true)
		_state.set_agents([
			{"agent_id": PROPOSER, "display_name": "GEMMATRON", "model_key": _proof._model_id},
			{"agent_id": TARGET, "display_name": "OZONIOUS", "model_key": _proof._model_id},
		])
		_state.set_runtimes([{"runtime_id": "runtime-01", "model_key": _proof._model_id}])
	_state.publish_continuity_proof(
		_proof.build(_resolve_betrayal_id(), TARGET, PROPOSER))


## Publish the proof, then either exit or hold the socket open so Watch Mode can
## connect and witness it. Holding is what makes the run filmable; the proof
## itself is complete either way.
func _finish_run() -> void:
	_save_proof_state()
	_publish_proof()
	_write_out()
	if _serve_sec <= 0.0:
		quit(0)
		return
	_say("")
	_say("SERVING ArenaState v1 on :8972 for %.0fs — Watch Mode may connect now" % _serve_sec)
	var waited := 0.0
	while waited < _serve_sec:
		await process_frame
		waited += 1.0 / 60.0
	_say("serve window closed")
	quit(0)
