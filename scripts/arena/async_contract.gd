extends RefCounted
class_name AsyncContract

## The agent-facing action contract. Exactly ONE model-controlled field.
##
##     {"target_id": "r_07"}
##
## No explanation. No operation type. No confidence. No prose. No reason.
##
## Deliberately far smaller than PIT A's typed-operation contract: PIT A's
## semantic-invalid rates of 0.41-0.99 meant its descriptors largely measured
## whether a model could satisfy the contract at all, rather than anything
## about how it modified a world.
##
## THE SCHEMA MUST NOT ENUMERATE THE VISIBLE TARGET IDS. This is load-bearing.
## Constraining `target_id` to an enum of the currently visible ids would let
## the runtime make an invalid target impossible to emit -- and SEMANTIC_INVALID
## would be mechanically removed as an observable outcome.
##
## That is not a safety improvement, it is the silent deletion of a control
## variable. The entire reason SEMANTIC_INVALID is separated from
## STALE_CONFLICT is so a model's hallucination rate cannot masquerade as a
## latency effect. If hallucination cannot occur, the separation can never be
## checked against real behaviour.
##
## So `target_id` is a free string, and validity is judged AFTER the fact
## against the sealed observation.

const FIELD := "target_id"


## The JSON schema handed to the model. Free string, no enum, nothing else.
static func schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {FIELD: {"type": "string"}},
		"required": [FIELD],
		"additionalProperties": false,
	}


static func schema_hash() -> String:
	return JSON.stringify(schema(), "", false, true).sha256_text().substr(0, 16)


## The prompt. Identical in shape for every agent and every arm; only the
## visible list differs, because that is the observation.
static func prompt(visible_ids: Array) -> String:
	var lines := ""
	for id in visible_ids:
		lines += "  " + str(id) + "\n"
	return ("Available resources:\n" + lines
		+ "\nChoose exactly one resource to take.\n"
		+ "Reply with only its id in the field target_id.")


## Parse a model reply into a target, or a shape failure.
##
## Returns {ok, target_id, reason}. A shape failure is NOT a decision and is
## never scored as one.
static func parse(raw: String) -> Dictionary:
	var j := JSON.new()
	if j.parse(raw) != OK:
		return {"ok": false, "target_id": "", "reason": "invalid JSON"}
	var d = j.data
	if typeof(d) != TYPE_DICTIONARY:
		return {"ok": false, "target_id": "", "reason": "not an object"}
	var dict: Dictionary = d
	if not dict.has(FIELD):
		return {"ok": false, "target_id": "", "reason": "missing target_id"}
	if dict.size() != 1:
		return {"ok": false, "target_id": "",
			"reason": "additional properties present"}
	var v = dict[FIELD]
	if typeof(v) != TYPE_STRING:
		return {"ok": false, "target_id": "", "reason": "target_id not a string"}
	if str(v) == "":
		return {"ok": false, "target_id": "", "reason": "empty target_id"}
	return {"ok": true, "target_id": str(v), "reason": ""}
