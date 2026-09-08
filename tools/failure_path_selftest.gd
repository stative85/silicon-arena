extends SceneTree

## Failure-path teeth. NO LM STUDIO CONTACT, NO INFERENCE, NO MODEL CALLS.
##
##   godot --headless --path . --script tools/failure_path_selftest.gd
##
## Pins the night-shift static-review fixes so they cannot silently regress.
## Each was a demonstrable defect, not a style preference:
##
##   1. resident_set() returned [] for a transport failure AND for a genuinely
##      empty pool, so a total eviction read as TRANSPORT and ensure_loaded()
##      could create a duplicate instance through a failure path
##   2. ensure_loaded() returned true for ANY count >= 1, reporting a pool
##      holding two instances as restored
##
## These tests drive the pure classification and contract surfaces only. They
## never construct an HTTPRequest and never reach the network.

const RA := preload("res://scripts/arena/recovery_action.gd")
const G := preload("res://scripts/arena/recovery_gate.gd")

var _n := 0
var _f := 0


func _init() -> void:
	_run.call_deferred()


func _ck(label: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  ok   %s" % label)
	else:
		_f += 1
		print("  FAIL %s %s" % [label, detail])


func _run() -> void:
	print("=== failure-path teeth ===\n")

	print("[an empty pool is a DISAPPEARANCE, not a transport failure]")
	# The gate now branches on the probe's ok flag, so a readable-but-empty pool
	# must classify as the catastrophic state it actually is.
	_ck("empty counts vs a populated expectation -> DISAPPEARED",
		G.classify({}, {"a": 1, "b": 1}) == G.DISAPPEARED,
		G.classify({}, {"a": 1, "b": 1}))
	_ck("empty counts with a flexed model still -> DISAPPEARED",
		G.classify({}, {"a": 1, "b": 1}, "a") == G.DISAPPEARED)
	_ck("TRANSPORT is a distinct reason from DISAPPEARED",
		G.TRANSPORT != G.DISAPPEARED)

	print("\n[cardinality contract]")
	_ck("exactly one each is the expectation",
		RA.expect_one_each(["a", "b"]) == {"a": 1, "b": 1})
	_ck("two instances fail the count map",
		not RA.counts_match({"a": 2, "b": 1}, {"a": 1, "b": 1}))
	_ck("a missing model fails the count map",
		not RA.counts_match({"a": 1}, {"a": 1, "b": 1}))
	_ck("a foreign model fails the count map",
		not RA.counts_match({"a": 1, "b": 1, "z": 1}, {"a": 1, "b": 1}))

	print("\n[producer id contract cannot be murdered by a naming convention]")
	var known := ["qwen3.5-2b", "liquidai/lfm2.5-1.2b-instruct"]
	_ck("known duplicate suffix collapses",
		RA.base_id("qwen3.5-2b:2", known) == "qwen3.5-2b")
	_ck("UNKNOWN numeric-colon id is NOT collapsed",
		RA.base_id("someone-else:2", known) == "someone-else:2")
	_ck("a legitimate id ending in :2 survives when known",
		RA.base_id("cool:2", ["cool:2"]) == "cool:2")
	_ck("non-numeric colon untouched",
		RA.base_id("weird:model", known) == "weird:model")

	print("\n[the witness contract is evaluable from a stored artifact]")
	var w := {"pre_target_present": true, "unload_verified": true,
		"reload_verified": true, "neighbor_set_preserved": true,
		"post_liveness_verified": true, "old_epoch": 3, "new_epoch": 4}
	_ck("a complete witness validates", RA.is_valid(w))
	for key in ["pre_target_present", "unload_verified", "reload_verified",
			"neighbor_set_preserved", "post_liveness_verified"]:
		var broken := w.duplicate()
		broken[key] = false
		_ck("witness rejects when %s is false" % key, not RA.is_valid(broken))
	var no_epoch := w.duplicate()
	no_epoch["new_epoch"] = 3
	_ck("witness rejects when the epoch did not advance",
		not RA.is_valid(no_epoch))
	var double := w.duplicate()
	double["new_epoch"] = 5
	_ck("witness rejects when the epoch advanced twice",
		not RA.is_valid(double))

	print("\n[SUMMARY]")
	print("  checks %d, failures %d" % [_n, _f])
	if _f > 0:
		print("\nFAILURE-PATH TEETH RED")
		quit(1)
		return
	print("\nFAILURE-PATH TEETH GREEN")
	quit(0)
