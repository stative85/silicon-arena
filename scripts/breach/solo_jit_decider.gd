extends RefCounted
class_name BreachSoloJitDecider

## THE LIVE SEAM, under SOLO_JIT_RESIDENCY.
##
## Before every inference request, ONLY the acting species may be resident. The
## previous species is unloaded before the next is loaded, the resident set is
## ASSERTED before the request, and a mismatch aborts the round.
##
## This is not a cache policy. "One or two resident at a time" would leave the
## number resident at any moment depending on timing and on what ran before --
## a free variable inside the experiment. Exactly one is a regime.
##
## WHAT IS CLAIMED about this differing from the co-resident pool:
##   * FLOWSCAR4 measures no latency and no throughput quantity
##   * requests are stateless -- no KV cache or conversation carries between
##     turns
##   * temperature is 0
##   * prompt bytes and schema bytes are identical regardless of residency
##   * no host rule reads load state, swap time or token rate
##
## WHAT IS NOT CLAIMED: that residency cannot affect a decision. That is not
## established. Any residual effect of load order or reload on a model's output
## is a DECLARED LIMITATION of this regime, recorded rather than argued away.
##
## The schema is sent as VERBATIM BYTES. Parsing it into a Dictionary and
## re-serialising reorders keys alphabetically, which reorders the grammar's
## required emission order and makes GIVE and OFFER unreachable
## (docs/results/LIVE_SEAM_QUALIFICATION.md). Never do it.

const LMS := "C:\\Users\\cleve\\.lmstudio\\bin\\lms.exe"
const LM_BASE := "http://127.0.0.1:1234/v1"
const PLACEHOLDER := "__LIVE_SCHEMA_BYTES__"
const OP := preload("res://scripts/breach/canonical_operation.gd")


## The contract text, generated from canonical_operation.gd rather than
## restated. Identical for all five species: no persona, no behavioural
## suggestion, no per-species wording.
static func contract_text() -> String:
	var lines: Array = []
	for op in OP.AGENT_CHOOSABLE:
		var req: Array = OP.required_fields(op)
		if req.is_empty():
			lines.append("  %s" % op)
		else:
			lines.append("  %s  (fields: %s)" % [op, ", ".join(req)])
	return ("Reply with exactly one JSON object and no other text.
"
		+ "It must have an \"operation\" field whose value is one of:
"
		+ "
".join(lines) + "
"
		+ "Include every field that operation requires, each a non-empty "
		+ "string. Do not include an \"operations\" list.")

var context_length: int = 2048
var temperature: float = 0.0
var max_tokens: int = 512
var schema_text: String = ""
var last_resident: Array = []
var violations: Array = []
var _http: HTTPRequest = null
var _loaded: String = ""


func _init(p_schema_text: String, p_http: HTTPRequest,
		p_context: int = 2048) -> void:
	schema_text = p_schema_text
	_http = p_http
	context_length = p_context


static func _run(args: Array) -> String:
	var out: Array = []
	OS.execute(LMS, args, out, true)
	return "\n".join(out.map(func(x): return str(x)))


## Every model the runtime currently holds. The assertion below compares this
## against the single species that is supposed to be loaded.
static func resident() -> Array:
	var text := _run(["ps"])
	var found: Array = []
	for line in text.split("\n"):
		var l := str(line).strip_edges()
		if l.is_empty() or l.begins_with("IDENTIFIER"):
			continue
		var first := l.split(" ", false)
		if first.size() > 0:
			found.append(str(first[0]))
	found.sort()
	return found


static func unload_all() -> void:
	_run(["unload", "--all"])


## SOLO: unload whatever is there, load exactly one, and prove it.
func ensure_only(model_id: String) -> Dictionary:
	if _loaded == model_id:
		var still := resident()
		if still.size() == 1 and still[0] == model_id:
			last_resident = still
			return {"ok": true}
	unload_all()
	_run(["load", model_id, "--context-length", str(context_length),
		"--gpu", "max", "-y"])
	var now := resident()
	last_resident = now
	_loaded = model_id
	if now.size() != 1 or now[0] != model_id:
		var v := {"violation": "RESIDENCY_VIOLATION", "expected": model_id,
			"resident": now}
		violations.append(v)
		return {"ok": false, "reason":
			"RESIDENCY_VIOLATION: expected only %s, resident %s"
			% [model_id, str(now)]}
	return {"ok": true}


## One generation. No repair, no retry, no second ask. Whatever comes back is
## handed to OutputParser verbatim, including when it is garbage.
func decide(observation_text: String, contract_text: String,
		model_id: String) -> Dictionary:
	var gate: Dictionary = ensure_only(model_id)
	if not bool(gate["ok"]):
		return {"raw": "", "latency_ms": -1, "residency_ok": false,
			"reason": str(gate["reason"])}
	var body := {"model": model_id,
		"messages": [{"role": "user",
			"content": contract_text + "\n\nOBSERVATION:\n" + observation_text}],
		"max_tokens": max_tokens, "temperature": temperature, "stream": false,
		"response_format": {"type": "json_schema", "json_schema": {
			"name": "ACTION_SCHEMA_V1", "strict": true,
			"schema": PLACEHOLDER}}}
	var payload := JSON.stringify(body).replace(
		"\"" + PLACEHOLDER + "\"", schema_text)
	_http.cancel_request()
	var t0 := Time.get_ticks_msec()
	if _http.request(LM_BASE + "/chat/completions",
			["Content-Type: application/json"], HTTPClient.METHOD_POST,
			payload) != OK:
		return {"raw": "", "latency_ms": -1, "residency_ok": true,
			"reason": "transport"}
	var res: Array = await _http.request_completed
	var ms := Time.get_ticks_msec() - t0
	if int(res[1]) != 200:
		return {"raw": "", "latency_ms": ms, "residency_ok": true,
			"reason": "http_%d" % int(res[1])}
	var parsed = JSON.parse_string(
		(res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("choices"):
		return {"raw": "", "latency_ms": ms, "residency_ok": true,
			"reason": "malformed_response"}
	var usage: Dictionary = parsed.get("usage", {})
	return {"raw": str(parsed["choices"][0]["message"].get("content", "")),
		"latency_ms": ms, "residency_ok": true, "reason": "",
		"prompt_tokens": int(usage.get("prompt_tokens", 0)),
		"resident": last_resident.duplicate()}
