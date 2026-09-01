extends SceneTree

## Proves the size law is enforced on the Godot request path.
##
##   Godot_v4.6-stable_win64_console.exe --headless --path . \
##       --script scripts/arena/model_policy_selftest.gd
##
## The TypeScript suite proves the policy maths. This proves the thing that
## actually matters at runtime: that LMStudioClient will not emit an HTTP
## request for an ineligible model, and that a missing catalog fails CLOSED.

const PolicyScript := preload("res://scripts/arena/model_policy.gd")
const ClientScript := preload("res://scripts/api/lm_studio_client.gd")

var _checks := 0
var _failures: Array[String] = []


func _init() -> void:
	print("=== model policy (Godot request path) ===\n")

	var policy = PolicyScript.new()
	get_root().add_child(policy)
	policy.load_catalog()

	_check("catalog loaded", policy.is_loaded(), "eligible: %d" % policy.eligible_count())
	if not policy.is_loaded():
		print("\nCatalog missing. Run: npx tsx tools/buildModelCatalog.ts")
		_finish()
		return

	_test_ceiling(policy)
	_test_request_path(policy)
	_test_fails_closed()

	_finish()


func _test_ceiling(policy) -> void:
	print("\n[ceiling] the catalog's own entries obey the law")

	var over := []
	var eligible := 0
	for key in policy._by_key:
		var m: Dictionary = policy._by_key[key]
		if bool(m.get("eligible", false)):
			eligible += 1
			var p = m.get("paramsB", null)
			if p == null or float(p) > policy.MAX_PARAM_B:
				over.append(key)
	_check("no eligible model exceeds %.0fB" % policy.MAX_PARAM_B, over.is_empty(), str(over))
	_check("at least one eligible model exists", eligible > 0, "%d eligible" % eligible)

	# Pick real oversized entries out of the actual inventory and confirm refusal.
	var refused_big := 0
	var checked_big := 0
	for key in policy._by_key:
		var m: Dictionary = policy._by_key[key]
		var p = m.get("paramsB", null)
		if p != null and float(p) > policy.MAX_PARAM_B:
			checked_big += 1
			if policy.check(key) != "":
				refused_big += 1
	_check("every oversized model in the real inventory is refused",
		checked_big > 0 and refused_big == checked_big,
		"%d/%d refused" % [refused_big, checked_big])

	# Ambiguous entries too.
	var refused_amb := 0
	var checked_amb := 0
	for key in policy._by_key:
		var m: Dictionary = policy._by_key[key]
		if m.get("paramsB", null) == null:
			checked_amb += 1
			if policy.check(key) != "":
				refused_amb += 1
	_check("every unidentifiable model is refused",
		checked_amb == 0 or refused_amb == checked_amb,
		"%d/%d refused" % [refused_amb, checked_amb])

	_check("an invented model id is refused", policy.check("definitely-not-a-real-model") != "")
	_check("an empty model id is refused", policy.check("") != "")


func _test_request_path(policy) -> void:
	print("\n[request path] the client must not emit HTTP for a refused model")

	var client = ClientScript.new()
	get_root().add_child(client)
	client.model_policy = policy

	# Find a genuinely oversized model from the real inventory.
	var big := ""
	for key in policy._by_key:
		var p = policy._by_key[key].get("paramsB", null)
		if p != null and float(p) > policy.MAX_PARAM_B:
			big = key
			break
	_check("found an oversized model to test with", big != "", big)
	if big == "":
		return

	var got := {"called": false, "ok": true, "code": 0}
	var cb := func(ok: bool, text: String, code: int):
		got["called"] = true
		got["ok"] = ok
		got["code"] = code

	client.chat_completion("TestAgent", big, [{"role": "user", "content": "hi"}], cb)

	_check("callback fired synchronously (no request queued)", bool(got["called"]),
		"called=%s" % str(got["called"]))
	_check("reported failure, not success", not bool(got["ok"]))
	_check("used MODEL_REJECTED code, not a network error",
		int(got["code"]) == client.MODEL_REJECTED_HTTP_CODE,
		"code=%d expected=%d" % [int(got["code"]), client.MODEL_REJECTED_HTTP_CODE])
	_check("nothing was enqueued", client._queue.is_empty(), "queue=%d" % client._queue.size())

	# And an eligible model must NOT be blocked by the guard.
	var small := ""
	for key in policy._by_key:
		var m: Dictionary = policy._by_key[key]
		if bool(m.get("eligible", false)):
			small = key
			break
	_check("an eligible model passes the guard", small != "" and policy.check(small) == "",
		"%s -> %s" % [small, policy.check(small)])


func _test_fails_closed() -> void:
	print("\n[fail closed] no catalog means no requests, not free rein")
	var orphan = PolicyScript.new()
	# Deliberately never added to the tree and never loaded.
	_check("unloaded policy refuses an eligible-looking id",
		orphan.check("h2o-danube3-4b-chat") != "",
		orphan.check("h2o-danube3-4b-chat"))
	_check("unloaded policy refuses everything",
		orphan.check("anything-at-all") != "")


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("   ok   " + label + ("  (" + detail + ")" if detail != "" else ""))
	else:
		print("   FAIL " + label + ("  (" + detail + ")" if detail != "" else ""))
		_failures.append(label)


func _finish() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	for f in _failures:
		print("  FAIL: " + f)
	if _failures.is_empty():
		print("SIZE LAW ENFORCED ON THE REQUEST PATH")
		quit(0)
	else:
		quit(2)
