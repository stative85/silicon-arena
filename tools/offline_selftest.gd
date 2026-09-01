extends SceneTree

## What happens when LM Studio is not there.
##
##   godot --headless --path . --script tools/offline_selftest.gd
##
## Deterministic: it points the client at a closed port, so it needs no server
## and behaves identically on a developer machine and in CI.
##
## WHY
##
## Every other failure in this project turned out to be something that looked
## like nothing happening. "LM Studio was closed" must not join that list: the
## callback has to fire, it has to report failure, and it has to say something
## a human can act on. A silent hang here would strand a turn forever.

const ClientScript := preload("res://scripts/api/lm_studio_client.gd")

## Almost certainly closed. Not 1234, which is LM Studio's real port.
const DEAD_URL := "http://127.0.0.1:9"

var _checks := 0
var _failures: Array[String] = []
var _done := false


func _init() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("   ok   %s" % name)
	else:
		_failures.append(name)
		print("   FAIL %s  %s" % [name, detail])


func _run() -> void:
	print("=== offline behaviour (LM Studio absent) ===\n")

	var client = ClientScript.new()
	client.base_url = DEAD_URL
	client.request_timeout_sec = 5.0
	get_root().add_child(client)
	await process_frame

	var result := {"called": false, "ok": true, "text": "", "code": -1}
	var t0 := Time.get_ticks_msec()

	client.chat_completion("OfflineAgent", "any-3b-model",
		[{"role": "user", "content": "hello"}],
		func(ok: bool, text: String, code: int):
			result["called"] = true
			result["ok"] = ok
			result["text"] = text
			result["code"] = code)

	# Wait generously, but bounded: a hang is the failure we are testing for.
	var waited := 0
	while not result["called"] and waited < 900:
		await process_frame
		waited += 1
	var elapsed := float(Time.get_ticks_msec() - t0) / 1000.0

	_check("the callback fires at all (no silent hang)", result["called"],
		"waited %d frames / %.1fs" % [waited, elapsed])

	if result["called"]:
		_check("it reports failure, not success", result["ok"] == false,
			"ok=%s" % str(result["ok"]))
		_check("a human-readable reason is supplied",
			str(result["text"]).strip_edges() != "",
			"text was empty")
		_check("the reason mentions LM Studio or a connection",
			str(result["text"]).to_lower().find("lm studio") != -1
			or str(result["text"]).to_lower().find("response") != -1
			or str(result["text"]).to_lower().find("connect") != -1,
			"got: %s" % str(result["text"]))
		print("        reason: %s" % str(result["text"]))
		print("        code:   %d" % int(result["code"]))
		print("        took:   %.1fs" % elapsed)
		_check("it gives up within the configured timeout budget",
			elapsed < 60.0, "%.1fs" % elapsed)

	# The queue must not be wedged: a second request still completes.
	var second := {"called": false}
	client.chat_completion("OfflineAgent2", "any-3b-model",
		[{"role": "user", "content": "again"}],
		func(_ok: bool, _t: String, _c: int): second["called"] = true)
	var w2 := 0
	while not second["called"] and w2 < 900:
		await process_frame
		w2 += 1
	_check("a later request is not wedged behind the failed one", second["called"],
		"queue stalled after a failure")

	_report()


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("OFFLINE OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
