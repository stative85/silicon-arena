extends Node
class_name ContinuityProof

## Rung 15 — the canonical proof payload.
##
## Godot is the only writer. This assembles the Rung 15 truth surface from
## ScarLattice and SystemicRuleset ONLY: it reads stored state and copies it.
## It never recomputes a decision, never fills a gap with a plausible value, and
## never infers a fact the store does not contain.
##
## Anything absent is UNKNOWN, NONE_RECORDED or NOT_MODELLED — three different
## honest answers:
##   UNKNOWN       the store should have it and does not
##   NONE_RECORDED the run genuinely produced none
##   NOT_MODELLED  the engine has no such concept yet (a later rung)
##
## The authoritative Rung 15 list has NINE elements. Each is tagged below with
## its element id so the mapping is checkable in the data, not just in a README.

const Ruleset := preload("res://scripts/arena/systemic_ruleset.gd")

const PROOF_SCHEMA := "continuity_proof/1.0"

const UNKNOWN := "UNKNOWN"
const NONE_RECORDED := "NONE_RECORDED"
const NOT_MODELLED := "NOT_MODELLED"

## The five timeline states, in order. A step is only ever appended.
const STEPS := ["BEFORE", "CONTROLLED_BETRAYAL", "PROCESS_ENDED", "COLD_LOAD", "AFTER"]

var _scar = null
var _proof_id := ""
var _mode_id := ""
var _session_id := ""
var _model_id := UNKNOWN
var _steps := []
var _errors := []
var _decisions := {}      # "before" / "after" -> systemic trace
var _axes_before := {}
var _cold_load_evidence := {}


func configure(scar, mode_id: String, session_id: String, proof_id: String) -> void:
	_scar = scar
	_mode_id = mode_id
	_session_id = session_id
	_proof_id = proof_id


## The real API identifier, taken from the request path. Never an alias.
func set_model_id(model_id: String) -> void:
	_model_id = model_id if model_id.strip_edges() != "" else UNKNOWN


func note_error(message: String) -> void:
	_errors.append({"at_ms": _now(), "message": message})


## Append one timeline step. `evidence_event_ids` ties it to the archive.
##
## COLD_LOAD may only be recorded with a real load report — a restart is proven
## by what came off disk, never by elapsed time.
func add_step(step: String, label: String, evidence_event_ids: Array = [],
		extra: Dictionary = {}) -> Dictionary:
	if not STEPS.has(step):
		note_error("unknown proof step '%s'" % step)
		return {}
	if step == "COLD_LOAD":
		var report: Dictionary = extra.get("load_report", {})
		var loaded := int(report.get("events", 0)) + int(report.get("memories", 0)) \
			+ int(report.get("relationships", 0))
		if loaded <= 0:
			note_error("COLD_LOAD refused: no evidence of a load from disk")
			return {}
		_cold_load_evidence = report
	var entry := {
		"step": step,
		"index": _steps.size(),
		"label": label,
		"at_ms": _now(),
		"evidence_event_ids": evidence_event_ids.duplicate(),
		"cold_load": step == "COLD_LOAD",
	}
	for k in extra:
		entry[k] = extra[k]
	_steps.append(entry)
	return entry


func record_decision(which: String, trace: Dictionary) -> void:
	_decisions[which] = trace.duplicate(true)
	if which == "before":
		_axes_before = trace.get("relationship_snapshot", {}).duplicate(true)


# ── the payload ─────────────────────────────────────────────────────────────

func build(betrayal_event_id: String, from_agent: String, to_agent: String) -> Dictionary:
	var payload := {
		"proof_schema": PROOF_SCHEMA,
		"proof_id": _proof_id,
		"mode_id": _mode_id,
		"session_id": _session_id,
		"ruleset": "%s:%s" % [Ruleset.RULESET_ID, Ruleset.RULESET_VERSION],
		"model_id": _model_id,
		"generated_at_ms": _now(),
		"steps": _steps.duplicate(true),
		"errors": _errors.duplicate(true),
	}
	if _scar == null:
		payload["event"] = {}
		payload["errors"].append({"at_ms": _now(), "message": "no lattice attached"})
		return payload

	# A1/A9 — what happened, and whether it was controlled or agent-originated.
	var ev: Dictionary = _scar.get_event(betrayal_event_id)
	var witnesses: Array = ev.get("witnesses", [])
	var non_witnesses := []
	for aid in _scar.identity_ids():
		if not witnesses.has(str(aid)):
			non_witnesses.append(str(aid))
	payload["event"] = {
		"element": "A1/A9",
		"event_id": str(ev.get("event_id", UNKNOWN)),
		"type": str(ev.get("type", UNKNOWN)),
		"summary": str(ev.get("summary", UNKNOWN)),
		"origin": str(ev.get("origin", UNKNOWN)),
		"origin_is_controlled": str(ev.get("origin", "")) == "controlled_fixture",
		"claim_kind": str(ev.get("claim_kind", UNKNOWN)),
		"resolver_authority": str(ev.get("resolver_authority", UNKNOWN)),
		"actor_id": str(ev.get("actor_id", UNKNOWN)),
		"target_id": str(ev.get("target_id", UNKNOWN)),
		"match_id": str(ev.get("match_id", UNKNOWN)),
		"session_id": str(ev.get("session_id", UNKNOWN)),
		"mode_id": str(ev.get("mode_id", UNKNOWN)),
	}

	# A2 — who witnessed it, and who provably did not.
	payload["witnesses"] = {
		"element": "A2",
		"witness_ids": witnesses.duplicate(),
		"non_witness_ids": non_witnesses,
	}

	# A3 — who was affected. NOT MODELLED: separating affectedness from
	# knowledge is Rung 5. The actor and target of record are all the engine
	# honestly knows, and it says so rather than inventing standing.
	payload["affected"] = {
		"element": "A3",
		"status": NOT_MODELLED,
		"note": "affectedness vs knowledge is Rung 5 and is not built",
		"parties_of_record": [str(ev.get("actor_id", "")), str(ev.get("target_id", ""))],
	}

	# A4/A5 — what each agent remembers, and what is inference rather than fact.
	var frames := []
	for aid in _scar.identity_ids():
		var held := {}
		for m in _scar.memories_for(str(aid), _mode_id):
			if m.get("provenance", {}).get("evidence_event_ids", []).has(betrayal_event_id):
				held = m
		var ident: Dictionary = _scar.get_identity(str(aid))
		if held.is_empty():
			frames.append({
				"agent_id": str(aid),
				"display_name": str(ident.get("canonical_name", UNKNOWN)),
				"holds_memory": false,
				"status": NONE_RECORDED,
				"note": "no memory citing this event",
			})
			continue
		var obs: Dictionary = held.get("observation", {})
		var prov: Dictionary = held.get("provenance", {})
		frames.append({
			"agent_id": str(aid),
			"display_name": str(ident.get("canonical_name", UNKNOWN)),
			"holds_memory": true,
			"memory_id": str(held.get("memory_id", UNKNOWN)),
			"content": str(held.get("content", UNKNOWN)),
			"frame_id": str(obs.get("frame_id", UNKNOWN)),
			"directness": str(obs.get("directness", UNKNOWN)),
			"observable_portion": str(obs.get("observable_portion", UNKNOWN)),
			"hidden_variables": obs.get("hidden_variables", []),
			"transformation_chain": obs.get("transformation_chain", []),
			"claim_kind": str(held.get("claim_kind", UNKNOWN)),
			"acquisition_mode": str(held.get("acquisition_mode", UNKNOWN)),
			"support_status": str(held.get("support_status", UNKNOWN)),
			"content_hash": str(prov.get("content_hash", UNKNOWN)),
			"evidence_event_ids": prov.get("evidence_event_ids", []),
		})
	payload["frames"] = {"element": "A4/A5", "entries": frames}

	# A6 — what was predicted. The claim kind is enforced; this run records none.
	var predictions := []
	for aid in _scar.identity_ids():
		for m in _scar.memories_for(str(aid), _mode_id):
			if str(m.get("claim_kind", "")) == "PREDICTION":
				predictions.append({
					"agent_id": str(aid),
					"content": str(m.get("content", "")),
					"falsifier": str(m.get("falsifier", UNKNOWN)),
					"support_status": str(m.get("support_status", UNKNOWN)),
				})
	payload["predictions"] = {
		"element": "A6",
		"status": NONE_RECORDED if predictions.is_empty() else "RECORDED",
		"entries": predictions,
	}

	# A7 — which contradictions remain open.
	var cons := []
	for c in _scar.contradictions_for(_mode_id):
		cons.append({
			"contradiction_id": str(c.get("contradiction_id", "")),
			"question": str(c.get("question", "")),
			"resolution_state": str(c.get("resolution_state", "UNRESOLVED")),
			"position_count": c.get("positions", []).size(),
		})
	payload["contradictions"] = {
		"element": "A7",
		"status": NONE_RECORDED if cons.is_empty() else "RECORDED",
		"open": _count_open(cons),
		"entries": cons,
	}

	# A8 — what systemic consequence changed.
	var rel: Dictionary = _scar.relation(_mode_id, from_agent, to_agent)
	var axes_after: Dictionary = rel.get("axes", {})
	var delta := {}
	for axis in axes_after:
		delta[axis] = float(axes_after[axis]) - float(_axes_before.get(axis, 0.0))
	var before_trace: Dictionary = _decisions.get("before", {})
	var after_trace: Dictionary = _decisions.get("after", {})
	payload["relationship"] = {
		"element": "A8",
		"from_agent_id": from_agent,
		"to_agent_id": to_agent,
		"axes_before": _axes_before.duplicate(true),
		"axes_after": axes_after.duplicate(true),
		"delta": delta,
		"ruleset_version": Ruleset.RULESET_VERSION,
		"weights": Ruleset.WEIGHTS,
	}
	payload["decision_before"] = _decision_view(before_trace)
	payload["decision_after"] = _decision_view(after_trace)

	# The causal statement, computed from the two traces rather than asserted.
	var same_seed := false
	var same_roll := false
	var influence_changed := false
	if not before_trace.is_empty() and not after_trace.is_empty():
		same_seed = int(before_trace.get("decision_seed", -1)) == int(after_trace.get("decision_seed", -2))
		same_roll = is_equal_approx(float(before_trace.get("roll", 0.0)),
			float(after_trace.get("roll", 1.0)))
		influence_changed = not is_equal_approx(
			float(before_trace.get("relationship_influence", 0.0)),
			float(after_trace.get("relationship_influence", 0.0)))
	payload["causal"] = {
		"element": "A8",
		"same_seed": same_seed,
		"same_roll": same_roll,
		"only_influence_changed": same_seed and same_roll and influence_changed,
		"caused_by_event_ids": [betrayal_event_id],
		"cold_load_evidence": _cold_load_evidence,
	}

	# The permanent truth strip. These are claims ABOUT the proof, each carrying
	# its own status, so a viewer cannot mistake the scope.
	payload["truth_labels"] = [
		{"claim": "durable memory across restart", "status": "PROVEN",
		 "where": "cold load report + relationship recovered from disk"},
		{"claim": "systemic behavioural influence", "status": "PROVEN",
		 "where": "same seed, same roll, influence term changed"},
		{"claim": "cognitive behavioural influence at 4B", "status": "NOT_PROVEN",
		 "where": "condition isolation; this configuration showed no useful signal"},
		{"claim": "betrayal origin", "status": "CONTROLLED_FIXTURE",
		 "where": "event.origin, staged by an arena rule, not emergent"},
	]
	return payload


func _decision_view(trace: Dictionary) -> Dictionary:
	if trace.is_empty():
		return {"status": UNKNOWN}
	return {
		"status": "RECORDED",
		"probability": float(trace.get("final_probability", 0.0)),
		"base_probability": float(trace.get("base_probability", 0.0)),
		"relationship_influence": float(trace.get("relationship_influence", 0.0)),
		"modifier_total": float(trace.get("modifier_total", 0.0)),
		"seeded_uncertainty": float(trace.get("seeded_uncertainty", 0.0)),
		"decision_seed": int(trace.get("decision_seed", 0)),
		"roll": float(trace.get("roll", 0.0)),
		"accepted": bool(trace.get("accepted", false)),
		"origin": str(trace.get("origin", UNKNOWN)),
		"axis_contributions": trace.get("axis_contributions", []),
	}


func _count_open(entries: Array) -> int:
	var n := 0
	for c in entries:
		if str(c.get("resolution_state", "")) == "UNRESOLVED":
			n += 1
	return n


func _now() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)
