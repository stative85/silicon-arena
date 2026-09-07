extends RefCounted
class_name AsyncEnvelope

## One cognition request, from observation to application. IMMUTABLE EVIDENCE.
##
## The envelope is a fossil, not a suggestion. After `seal_observation()` the
## provenance fields cannot change, and `assert_immutable()` proves it rather
## than trusting the harness.
##
## WHY THAT IS LOAD-BEARING. Arm 4 replays produced actions against a world
## whose state differs from the one that produced them. If any arm could
## regenerate an observation, or reconstruct provenance from the *current*
## world, the replay would quietly re-derive a provenance that agrees with
## whatever it happens to be looking at -- and the arm would become
## unfalsifiable. The same applies to arm 3: an equalizer that touched the
## observation would no longer be isolating speed.
##
## So: no arm regenerates these. No replay reconstructs them.

var request_id: String = ""
var agent_id: String = ""

## --- observation provenance, immutable after sealing --------------------
var observed_tick: int = -1
var observation_version: int = -1
var observation_hash: String = ""
var visible_target_ids: Array = []
var visible_target_generations: Dictionary = {}

## --- the produced action, immutable after sealing -----------------------
var chosen_target: String = ""
var chosen_target_generation: int = -1
var raw_action: String = ""

## --- timing, filled by the timing policy --------------------------------
var submitted_ms: int = 0
var completed_ms: int = 0
var completion_tick: int = -1
var release_tick: int = -1
var applied_tick: int = -1

## --- outcome ------------------------------------------------------------
var outcome: String = ""
var stale_revalidated: bool = false
var observation_age_ticks: int = -1
var current_target_generation: int = -1
var equalizer_breach: bool = false

var _sealed: bool = false
var _fingerprint: String = ""


## CAUSALLY STERILE REQUEST IDENTITY.
##
## EQUALIZED breaks within-tick ties on sha256(request_id), which is only
## speed-blind if request identity is. A timestamp, a global submission
## counter, a UUID or a bridge slot index would let model latency influence
## the ordering of the arm built to remove model latency -- a leak one hash
## function away from invisible.
##
## Derived from experimental identity ONLY: which replicate, which agent, and
## the agent's own count of cognitions. All three are facts about the
## experiment rather than about the machine.
static func request_id_for(replicate_id: String, agent_id: String,
		cognition_index: int) -> String:
	return ("%s|%s|%d" % [replicate_id, agent_id, cognition_index]
		).sha256_text().substr(0, 24)


static func make(rid: String, agent: String) -> AsyncEnvelope:
	var e := AsyncEnvelope.new()
	e.request_id = rid
	e.agent_id = agent
	return e


## Record what the agent saw. Callable once.
func seal_observation(obs: Dictionary) -> void:
	if _sealed:
		push_error("envelope observation already sealed: " + request_id)
		return
	observed_tick = int(obs.get("tick", -1))
	observation_version = int(obs.get("version", -1))
	observation_hash = str(obs.get("hash", ""))
	visible_target_ids = (obs.get("valid_targets", []) as Array).duplicate()
	visible_target_generations = (
		obs.get("valid_target_generations", {}) as Dictionary).duplicate()
	_sealed = true
	_fingerprint = _compute_fingerprint()


## Record the produced action, and the generation of the chosen target AS SEEN.
func set_action(target: String, raw: String) -> void:
	chosen_target = target
	raw_action = raw
	chosen_target_generation = int(
		visible_target_generations.get(target, -1))
	_fingerprint = _compute_fingerprint()


func _compute_fingerprint() -> String:
	var ids: Array = visible_target_ids.duplicate()
	ids.sort()
	var gens := ""
	for id in ids:
		gens += "%s:%d," % [str(id), int(visible_target_generations.get(id, -1))]
	return ("%s|%s|%d|%d|%s|%s|%s|%d|%s" % [
		request_id, agent_id, observed_tick, observation_version,
		observation_hash, gens, chosen_target, chosen_target_generation,
		raw_action]).sha256_text().substr(0, 24)


func fingerprint() -> String:
	return _fingerprint


## Prove nothing mutated the evidence. Called before and after every
## application, and after any replay reconstruction.
func assert_immutable() -> bool:
	return _fingerprint != "" and _fingerprint == _compute_fingerprint()


## The observation, rebuilt from the ENVELOPE, never from the live world.
func observation() -> Dictionary:
	return {
		"tick": observed_tick,
		"version": observation_version,
		"valid_targets": visible_target_ids,
		"valid_target_generations": visible_target_generations,
		"hash": observation_hash,
	}


func to_row() -> Dictionary:
	return {
		"request_id": request_id, "agent_id": agent_id,
		"observed_tick": observed_tick,
		"observation_version": observation_version,
		"observation_hash": observation_hash,
		"visible_target_ids": visible_target_ids,
		"chosen_target": chosen_target,
		"chosen_target_generation": chosen_target_generation,
		"current_target_generation": current_target_generation,
		"submitted_ms": submitted_ms, "completed_ms": completed_ms,
		"completion_tick": completion_tick, "release_tick": release_tick,
		"applied_tick": applied_tick,
		"observation_age_ticks": observation_age_ticks,
		"outcome": outcome, "stale_revalidated": stale_revalidated,
		"equalizer_breach": equalizer_breach,
		"fingerprint": _fingerprint,
	}
