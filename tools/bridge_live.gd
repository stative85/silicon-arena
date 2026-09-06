extends SceneTree

## Drive the bridge against real LM Studio. Requires the hot set resident.
##
##   godot --headless --path . --script tools/bridge_live.gd
##
## This is NOT part of verify.cmd -- it needs a live server. It exists to prove
## the streaming path measures a real first-content TTFT rather than the
## completion latency the v0 non-streaming path was politely reporting.
##
## It makes no model quality claims and does not modify any experiment.

const B := preload("res://scripts/arena/inference_bridge.gd")
const R := preload("res://scripts/arena/bridge_receipt.gd")
const M := preload("res://scripts/arena/bridge_model.gd")
const T := preload("res://scripts/arena/bridge_ticket.gd")

var _done := 0
var _want := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== bridge live check (EXPLICIT_RESIDENCY_MODE) ===\n")
	var br := B.new()
	get_root().add_child(br)
	await process_frame

	var resident := await br.refresh_residency()
	print("resident: %s" % str(resident))
	var usable: Array[String] = []
	for mid in br.policy.hot_set:
		if resident.has(mid):
			usable.append(mid)
			(br.models[mid] as BridgeModel).set_state(M.HOT, "observed", 0)
	if usable.is_empty():
		print("\nNo hot-set model is resident. Load the hot set first:")
		for mid in br.policy.hot_set:
			print("  lms load %s --context-length 8192 --gpu max -y" % mid)
		quit(1)
		return
	print("usable: %s\n" % str(usable))

	br.completed.connect(func(rid, ok, text, rec):
		_done += 1
		print("  %s" % R.line(rec))
		print("     first_event=%dms first_content=%dms  chars=%d  ok=%s"
			% [int(rec.get("first_event_at_ms", 0))
				- int(rec.get("dispatched_at_ms", 0)),
			   int(rec.get("ttft_ms", -1)), text.length(), str(ok)]))

	br.model_state_changed.connect(func(mid, from, to, why):
		print("  STATE %s: %s -> %s (%s)" % [mid, from, to, why]))

	print("[1] one request per usable model, sequential")
	for mid in usable:
		_want += 1
		br.submit("live_agent", mid, _body(), T.CLASS_NORMAL,
			T.LATENCY_INTERACTIVE)
		while _done < _want:
			await process_frame

	print("\n[2] concurrent burst across the hot set")
	var before := _done
	for mid in usable:
		_want += 1
		br.submit("live_agent", mid, _body())
	while _done < _want:
		await process_frame
	print("  %d concurrent requests completed" % (_done - before))

	print("\n[3] TTFT distribution (the point of streaming)")
	var by_model := {}
	for rec in br.receipts:
		var t := int(rec.get("ttft_ms", -1))
		if t < 0:
			continue
		var mid := str(rec["model_id"])
		if not by_model.has(mid):
			by_model[mid] = []
		(by_model[mid] as Array).append(t)
	for mid in by_model:
		var arr: Array = by_model[mid]
		arr.sort()
		print("  %-32s n=%d  ttft %s ms" % [mid, arr.size(), str(arr)])

	print("\nstats: %s" % str(br.stats()))
	var bad := 0
	for rec in br.receipts:
		if str(rec.get("status", "")) != R.STATUS_OK:
			bad += 1
	print("non-OK receipts: %d/%d" % [bad, br.receipts.size()])
	quit(0 if bad == 0 else 1)


func _body() -> Dictionary:
	return {
		"messages": [{"role": "user",
			"content": "Reply with one short sentence about a typed object."}],
		"max_tokens": 48,
		"temperature": 0.0,
	}
