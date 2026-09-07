extends SceneTree

## ASYNC-A2 roster qualification. GATE 1 of 3: THE CONTRACT.
##
##   godot --headless --path . --script tools/async_roster_qualify.gd
##
## Same one-field contract, same response_format, same temperature, unique
## realistic observations. NO world. NO timing comparisons. NO outcomes.
##
## This asks exactly one thing:
##
##     Can this model emit {"target_id": "..."} reliably enough to be measured?
##
## Criterion, taken from the ASYNC-A void condition rather than invented here:
##
##     SHAPE_FAILED <= 10% per candidate
##
## A candidate that fails is not "worse". It is incompatible with THIS
## interface under THESE conditions, which is the only claim being made.

const C := preload("res://scripts/arena/async_contract.gd")
const B := preload("res://scripts/arena/inference_bridge.gd")
const M := preload("res://scripts/arena/bridge_model.gd")
const R := preload("res://scripts/arena/bridge_receipt.gd")

const CALLS := 200
const CRITERION := 0.10

var _bridge: InferenceBridge
var _pending := 0
var _results: Array = []
var _uniq := 0


func _init() -> void:
	_run.call_deferred()


## A realistic observation: 16 ids, unique every call so prefix caching cannot
## make the task easier than it is in the arena.
func _payload() -> Dictionary:
	_uniq += 1
	var ids: Array = []
	for i in 16:
		ids.append("r_%02d" % ((i + _uniq) % 16))
	return {
		"messages": [{"role": "user", "content": C.prompt(ids)}],
		"max_tokens": 24, "temperature": 0.0,
		"response_format": {"type": "json_schema", "json_schema": {
			"name": "async_action", "strict": true, "schema": C.schema()}},
	}


func _run() -> void:
	print("=== ASYNC-A2 roster qualification: THE CONTRACT ===")
	print("No world. No timing comparisons. No outcomes.\n")
	print("criterion   SHAPE_FAILED <= %.0f%% per candidate" % (CRITERION * 100))
	print("calls       %d per candidate\n" % CALLS)

	_bridge = B.new()
	get_root().add_child(_bridge)
	await process_frame
	var resident := await _bridge.refresh_residency()
	print("resident: %s\n" % str(resident))

	_bridge.completed.connect(func(_rid, ok, text, rec):
		_pending -= 1
		_results.append({"ok": ok, "text": text,
			"status": str(rec.get("status", ""))}))

	var report: Array = []
	for mid in resident:
		if not _bridge.models.has(mid):
			continue
		(_bridge.models[mid] as BridgeModel).set_state(M.HOT, "qualify", 0)
		_results.clear()
		print("  %-32s" % mid)
		for i in CALLS:
			_pending = 1
			_bridge.submit("qualify", mid, _payload())
			while _pending > 0:
				await process_frame
		var shape := 0
		var transport := 0
		var samples: Array = []
		for r in _results:
			var d: Dictionary = r
			if not bool(d["ok"]):
				transport += 1
				continue
			var parsed := C.parse(str(d["text"]))
			if not bool(parsed["ok"]):
				shape += 1
				if samples.size() < 3:
					samples.append(str(d["text"]).substr(0, 90))
		var n := _results.size()
		var rate := float(shape) / float(maxi(n - transport, 1))
		var pass_ok := rate <= CRITERION and transport == 0
		print("     calls %d  transport_fail %d  shape_fail %d  rate %.3f  %s"
			% [n, transport, shape, rate, "PASS" if pass_ok else "FAIL"])
		for smp in samples:
			print("       %s" % smp)
		report.append({"model": mid, "calls": n, "transport_failures": transport,
			"shape_failures": shape, "shape_rate": rate, "pass": pass_ok,
			"samples": samples})

	print("\n[VERDICT]")
	var qualified: Array = []
	for r in report:
		var d: Dictionary = r
		print("  %-32s %s (%.1f%%)"
			% [str(d["model"]), "QUALIFIED" if bool(d["pass"]) else "REJECTED",
			   float(d["shape_rate"]) * 100.0])
		if bool(d["pass"]):
			qualified.append(str(d["model"]))

	var f := FileAccess.open("res://docs/results/ASYNC_A2_ROSTER.json",
		FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"criterion": CRITERION, "calls": CALLS,
			"contract_schema_hash": C.schema_hash(),
			"candidates": report, "qualified": qualified}, "  "))
		f.close()
		print("\nwrote docs/results/ASYNC_A2_ROSTER.json")
	quit(0)
