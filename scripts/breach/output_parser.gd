extends RefCounted
class_name OutputParser

## MODEL TEXT -> EXACTLY ONE CANONICAL OPERATION, OR NO_OP.
##
## THE LOAD-BEARING DECISION IN THIS FILE:
##
##   MALFORMED OUTPUT NEVER BECOMES WAIT().
##
## Substituting WAIT would write a behaviour the model did not perform. The log
## would read "the agent chose to wait" when in fact it emitted unparseable
## text, and no later analysis could tell those apart. So invalid output becomes
## NO_OP, carrying the raw text verbatim and a machine-readable failure reason,
## and NO_OP is distinct from WAIT forever.
##
## This matters more here than in most systems: failure to emit a valid
## operation is the single most likely thing to differ between five
## heterogeneous models of different families and sizes. It is a species signal,
## possibly the first real one the Arena produces. Collapsing it into WAIT would
## destroy that signal at the moment of capture.
##
## The parser is also deliberately STRICT rather than helpful. It does not
## repair, guess, or pick the closest verb. A parser that fixes output is a
## parser that hides how well each model actually followed the contract.

const CanonicalOperationScript := preload("res://scripts/breach/canonical_operation.gd")

const FAIL_NOT_JSON := "not_json"
const FAIL_NOT_OBJECT := "not_an_object"
const FAIL_NO_OPERATION := "no_operation_field"
const FAIL_UNKNOWN_OPERATION := "unknown_operation"
const FAIL_NOT_AGENT_CHOOSABLE := "operation_not_agent_choosable"
const FAIL_MISSING_FIELD := "missing_required_field"
const FAIL_EMPTY_FIELD := "empty_required_field"
const FAIL_MULTIPLE_OPERATIONS := "multiple_operations"


## Returns:
## {
##   ok: bool,
##   operation: String,          ## canonical op, or NO_OP
##   fields: Dictionary,         ## target/object/requested/text as given
##   memory_write: String,       ## may be empty
##   memory_replace_index: int,  ## -1 when not specified
##   raw: String,                ## the model's text, VERBATIM, always
##   parse_failure: String,      ## "" when ok
##   parse_detail: String,
## }
static func parse(raw_text: String) -> Dictionary:
	var res := {
		"ok": false,
		"operation": CanonicalOperationScript.NO_OP,
		"fields": {},
		"memory_write": "",
		"memory_replace_index": -1,
		"raw": raw_text,
		"parse_failure": "",
		"parse_detail": "",
	}

	var body := _extract_json(raw_text)
	if body.is_empty():
		res["parse_failure"] = FAIL_NOT_JSON
		res["parse_detail"] = "no JSON object found in model output"
		return res

	var json := JSON.new()
	if json.parse(body) != OK:
		res["parse_failure"] = FAIL_NOT_JSON
		res["parse_detail"] = "JSON parse error at line %d: %s" % [
			json.get_error_line(), json.get_error_message()]
		return res

	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		res["parse_failure"] = FAIL_NOT_OBJECT
		res["parse_detail"] = "top level is not an object"
		return res

	var doc: Dictionary = data

	## An agent acts ONCE per turn. A response carrying a list of operations, or
	## an "operations" array, is not a valid single choice and is not silently
	## truncated to its first element -- taking the first would be the host
	## choosing on the model's behalf.
	if doc.has("operations"):
		res["parse_failure"] = FAIL_MULTIPLE_OPERATIONS
		res["parse_detail"] = "response contains an 'operations' list; " \
			+ "exactly one operation is required"
		return res

	if not doc.has("operation"):
		res["parse_failure"] = FAIL_NO_OPERATION
		res["parse_detail"] = "no 'operation' field"
		return res

	var op_raw = doc["operation"]
	if typeof(op_raw) != TYPE_STRING:
		res["parse_failure"] = FAIL_NO_OPERATION
		res["parse_detail"] = "'operation' is not a string"
		return res

	var op := str(op_raw).strip_edges().to_upper()
	if not CanonicalOperationScript.is_known(op):
		res["parse_failure"] = FAIL_UNKNOWN_OPERATION
		res["parse_detail"] = "'%s' is not in the canonical vocabulary" % op
		return res
	if not CanonicalOperationScript.is_agent_choosable(op):
		## Includes an agent literally emitting NO_OP.
		res["parse_failure"] = FAIL_NOT_AGENT_CHOOSABLE
		res["parse_detail"] = "'%s' is host-authored and may not be chosen" % op
		return res

	var fields := {}
	for f in CanonicalOperationScript.required_fields(op):
		if not doc.has(f):
			res["parse_failure"] = FAIL_MISSING_FIELD
			res["parse_detail"] = "%s requires '%s'" % [op, f]
			return res
		var v := str(doc[f]).strip_edges()
		if v.is_empty():
			res["parse_failure"] = FAIL_EMPTY_FIELD
			res["parse_detail"] = "%s: '%s' is empty" % [op, f]
			return res
		fields[f] = v

	res["ok"] = true
	res["operation"] = op
	res["fields"] = fields
	if doc.has("memory_write") and typeof(doc["memory_write"]) == TYPE_STRING:
		res["memory_write"] = str(doc["memory_write"]).strip_edges()
	if doc.has("memory_replace_index"):
		var mi = doc["memory_replace_index"]
		if typeof(mi) == TYPE_FLOAT or typeof(mi) == TYPE_INT:
			res["memory_replace_index"] = int(mi)
	return res


## Models wrap JSON in prose, fences, or both. Finding the object is not
## repairing the output: the bytes are unchanged and the raw text is retained
## either way. What is NOT done is guessing a verb out of prose.
static func _extract_json(text: String) -> String:
	var t := text.strip_edges()
	if t.is_empty():
		return ""
	var fence := t.find("```")
	if fence >= 0:
		var after := t.substr(fence + 3)
		if after.begins_with("json"):
			after = after.substr(4)
		var close := after.find("```")
		if close >= 0:
			after = after.substr(0, close)
		t = after.strip_edges()
	var start := t.find("{")
	var stop := t.rfind("}")
	if start < 0 or stop <= start:
		return ""
	return t.substr(start, stop - start + 1)
