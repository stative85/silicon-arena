extends RefCounted
class_name EventRecord

## ONE OPERATION, WITH ENOUGH PROVENANCE TO REPLAY AND TO FALSIFY.
##
## before_state_hash and after_state_hash are what make a replay CHECKABLE
## rather than plausible. Replaying the log must reproduce the same hashes; if
## it does not, the divergence is detected at the exact event where it started,
## instead of being argued about later from a transcript that looks fine.
##
## PROVENANCE AXIS: an Arena round instantiates a ROSTER, so its artifacts carry
## population_regime_id and never measurement_pool_id. See
## docs/ARENA_IDENTITY_LAYERS.md and tools/population_regime.py. BREACH-0 will
## be the first artifact of regime B that has ever existed.
##
## The display name appears here as `actor` because the event stream is read by
## humans. Identity travels alongside it as model_id / species_id / instance_id
## and is never derived from the name.

var event_id: int = 0
var tick: int = 0
var actor: String = ""                ## display name, e.g. GEMMATRON
var model_id: String = ""             ## identity
var species_id: String = ""           ## identity
var instance_id: String = ""          ## runtime incarnation
var population_regime_id: String = "B"

var operation: String = ""            ## canonical verb, or NO_OP
var fields: Dictionary = {}
var accepted: bool = false            ## did the reducer apply it
var refusal_reason: String = ""       ## mechanical, when not accepted
var effects: Array = []

var raw_output: String = ""           ## model text, VERBATIM, always retained
var parse_failure: String = ""        ## "" when the output parsed
var parse_detail: String = ""

var observation_hash: String = ""
var before_state_hash: String = ""
var after_state_hash: String = ""

var initiative: Dictionary = {}       ## cycle / index / order
var latency_ms: int = -1              ## -1 until a real model produced it
var generation_params: Dictionary = {}


static func sha16(d) -> String:
	var s := JSON.stringify(d)
	return s.sha256_text().substr(0, 16)


func to_dict() -> Dictionary:
	return {
		"event_id": event_id,
		"tick": tick,
		"actor": actor,
		"model_id": model_id,
		"species_id": species_id,
		"instance_id": instance_id,
		"population_regime_id": population_regime_id,
		"operation": operation,
		"fields": fields.duplicate(true),
		"accepted": accepted,
		"refusal_reason": refusal_reason,
		"effects": effects.duplicate(),
		"raw_output": raw_output,
		"parse_failure": parse_failure,
		"parse_detail": parse_detail,
		"observation_hash": observation_hash,
		"before_state_hash": before_state_hash,
		"after_state_hash": after_state_hash,
		"initiative": initiative.duplicate(true),
		"latency_ms": latency_ms,
		"generation_params": generation_params.duplicate(true),
	}


## A single line for the live event stream. Mechanical, positional, no
## adjectives -- the UI renders exactly this and adds nothing.
func stream_line() -> String:
	var t := "%02d:%02d" % [int(tick / 60), tick % 60]
	var target := str(fields.get("target", ""))
	var head := "%s %-10s %s" % [t, actor, operation]
	if not target.is_empty():
		head += " " + target
	if not accepted:
		head += "  [REFUSED: %s]" % refusal_reason
	if operation == "NO_OP":
		head += "  [%s]" % parse_failure
	return head
