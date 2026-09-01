extends SceneTree

## Deterministic tests for the system-role compatibility layer.
##
##   godot --headless --path . --script scripts/arena/compat_selftest.gd
##
## No LM Studio required: both functions under test are pure.
##
## WHY THIS EXISTS
##
## Some GGUF chat templates reject a system message outright:
##
##   HTTP 400  Error rendering prompt with jinja template:
##             "Only user and assistant roles are supported!"
##
## Observed on Mistral-7B-Instruct-v0.3. Without handling, the model simply
## never speaks and looks broken. The risk in fixing it is over-reach: a
## blanket "retry any 400" would silently mask real request bugs. So the
## detector must be narrow and the transformation must be lossless.

const ClientScript := preload("res://scripts/api/lm_studio_client.gd")

var _checks := 0
var _failures: Array[String] = []


func _init() -> void:
	print("=== system-role compatibility ===\n")
	_test_detector()
	_test_fold()
	_test_error_summary()
	_report()


func _check(name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("   ok   %s" % name)
	else:
		_failures.append(name)
		print("   FAIL %s  %s" % [name, detail])


func _test_detector() -> void:
	print("[detector] only the specific template failure, nothing else")

	var real := '{"error":"Error rendering prompt with jinja template: \\"Only user and assistant roles are supported!\\"."}'
	_check("real jinja rejection is detected",
		ClientScript.is_system_role_rejection(400, real))

	_check("case does not matter",
		ClientScript.is_system_role_rejection(400, "ONLY USER AND ASSISTANT ROLES ARE SUPPORTED"))

	_check("alternating-roles variant is detected",
		ClientScript.is_system_role_rejection(400, "Conversation roles must alternate user/assistant/..."))

	# The dangerous direction: retrying things we should not.
	_check("unrelated 400 is NOT a system-role rejection",
		not ClientScript.is_system_role_rejection(400, '{"error":"model not found"}'))

	_check("context-overflow 400 is NOT a system-role rejection",
		not ClientScript.is_system_role_rejection(400, "context length exceeded"))

	_check("500 with the same text is NOT retried",
		not ClientScript.is_system_role_rejection(500, "only user and assistant roles are supported"),
		"a 500 is a server fault, not a template contract")

	_check("200 is never a rejection",
		not ClientScript.is_system_role_rejection(200, "only user and assistant roles are supported"))

	_check("empty body is not a rejection",
		not ClientScript.is_system_role_rejection(400, ""))


func _test_fold() -> void:
	print("\n[fold] system instruction survives, order preserved")

	var msgs := [
		{"role": "system", "content": "You are terse."},
		{"role": "user", "content": "Say hello."},
		{"role": "assistant", "content": "hello"},
		{"role": "user", "content": "Again."},
	]
	var out := ClientScript.fold_system_into_user(msgs)

	_check("no system role remains",
		not _has_role(out, "system"))
	_check("message count drops by exactly the system messages",
		out.size() == 3, "got %d" % out.size())
	_check("instruction is preserved verbatim",
		str(out[0]["content"]).find("You are terse.") != -1)
	_check("it lands on the FIRST user message",
		str(out[0]["role"]) == "user")
	_check("original user text is kept",
		str(out[0]["content"]).find("Say hello.") != -1)
	_check("later turns are untouched",
		str(out[1]["content"]) == "hello" and str(out[2]["content"]) == "Again.")
	_check("input array is not mutated",
		msgs.size() == 4 and str(msgs[0]["role"]) == "system")

	# Multiple system messages concatenate rather than losing any.
	var multi := [
		{"role": "system", "content": "A."},
		{"role": "system", "content": "B."},
		{"role": "user", "content": "go"},
	]
	var out2 := ClientScript.fold_system_into_user(multi)
	_check("multiple system messages all survive",
		str(out2[0]["content"]).find("A.") != -1 and str(out2[0]["content"]).find("B.") != -1)

	# System-only conversation: the instruction must not evaporate.
	var only_sys := [{"role": "system", "content": "Rules."}]
	var out3 := ClientScript.fold_system_into_user(only_sys)
	_check("system-only conversation gains a user message",
		out3.size() == 1 and str(out3[0]["role"]) == "user"
		and str(out3[0]["content"]).find("Rules.") != -1)

	# No system message: identity.
	var no_sys := [{"role": "user", "content": "hi"}]
	var out4 := ClientScript.fold_system_into_user(no_sys)
	_check("no system message means no change",
		out4.size() == 1 and str(out4[0]["content"]) == "hi")

	# Internal bookkeeping must never reach the wire.
	var wire := ClientScript._wire_body({"model": "m", "messages": [], "_compat_retry": true})
	_check("_compat_retry is stripped before sending",
		not wire.has("_compat_retry") and wire.has("model"))


## A failure must explain itself in one actionable line. The arena used to say
## "model not available (HTTP 400)" for a request-rejection, sending users to
## download a model that was already installed.
func _test_error_summary() -> void:
	print("
[errors] every failure explains itself, actionably")

	var jinja := "Error rendering prompt with jinja template: \"Only user and assistant roles are supported!\""
	_check("system-role rejection is named as such",
		ClientScript.summarize_error(400, jinja).find("system role") != -1)

	_check("context overflow is named",
		ClientScript.summarize_error(400, "context length exceeded").find("context window") != -1)

	_check("missing model is named",
		ClientScript.summarize_error(404, "model not found").find("not have this model") != -1)

	_check("out of VRAM is named",
		ClientScript.summarize_error(500, "CUDA out of memory").find("VRAM") != -1)

	_check("plain 400 does NOT claim the model is unavailable",
		ClientScript.summarize_error(400, "{}").find("not available") == -1)

	_check("timeout/no-response is named",
		ClientScript.summarize_error(0, "").find("no response") != -1)

	# A model that could not be LOADED is not a model that is broken. LM Studio
	# reports it as a bare HTTP 400, which used to be summarised as "LM Studio
	# rejected the request" -- and the roster builder then recorded a verdict it
	# had not earned and dropped a perfectly good model. The real text seen on
	# an 8GB card with another model resident is below, verbatim.
	var load_err := "{\"error\":{\"message\":\"Failed to load model \\\"elyza-7b\\\". Error: Operation canceled.\"}}"

	_check("a failed load is recognised, not called a bad request",
		ClientScript.is_load_failure(400, load_err))

	_check("the failed-load summary blames VRAM, not the model",
		ClientScript.summarize_error(400, load_err).to_lower().find("could not load") != -1)

	_check("the failed-load summary tells the user how to fix it",
		ClientScript.summarize_error(400, load_err).find("unload") != -1)

	_check("a 500 'error loading model' is also a load failure",
		ClientScript.is_load_failure(500, "Error loading model: out of space"))

	_check("an ordinary 400 is NOT treated as a load failure",
		not ClientScript.is_load_failure(400, "{\"error\":\"bad request\"}"))

	_check("a 200 is never a load failure",
		not ClientScript.is_load_failure(200, "Failed to load model"))

	_check("unknown codes still produce something",
		ClientScript.summarize_error(418, "teapot") != "")

	_check("summary is one line",
		ClientScript.summarize_error(400, jinja).find("
") == -1)


func _has_role(arr: Array, role: String) -> bool:
	for m in arr:
		if typeof(m) == TYPE_DICTIONARY and str(m.get("role", "")) == role:
			return true
	return false


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(2)
