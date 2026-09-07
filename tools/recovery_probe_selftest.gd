extends SceneTree

## RECOVERY-COUPLING step 4 tooth: sabotage the TELEMETRY.
##
##   godot --headless --path . --script tools/recovery_probe_selftest.gd
##
## NO MODEL CALLS. A recorder that has never caught a malformed causal record is
## just another optimistic diary, so every validation branch is exercised here
## with a deliberately broken record that MUST be rejected.

const P := preload("res://scripts/arena/recovery_probe.gd")

const NEIGHBOURS := ["liquidai/lfm2.5-1.2b-instruct", "falcon-h1-1.5b-instruct"]
const COUNTS := {"liquidai/lfm2.5-1.2b-instruct": 1, "qwen3.5-2b": 1,
	"falcon-h1-1.5b-instruct": 1}

var _n := 0
var _f := 0


func _init() -> void:
	_run.call_deferred()


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  ok   %s" % label)
	else:
		_f += 1
		print("  FAIL %s %s" % [label, detail])


func _window(cond: String) -> Dictionary:
	return {
		"window_id": 7, "schedule_hash": "9c9dbd9ca0c45252",
		"condition": cond, "recovered_model": "qwen3.5-2b",
		"actual_recovery_epoch": 3 if cond == P.TREATMENT else -1,
		"recovery_verified": cond == P.TREATMENT,
		"expected_counts": COUNTS,
	}


func _rec(ttft: int, expected: float) -> Dictionary:
	return {
		"ttft_ms": ttft, "health_expected_ms": expected,
		"prompt_tokens": 95, "max_active_during": 2,
		"submitted_at_ms": 1000, "first_token_at_ms": 1000 + ttft,
		"finished_at_ms": 1400, "status": "OK", "health_verdict": "NORMAL",
	}


func _gate(reason: String = "CLEAN", counts: Dictionary = COUNTS) -> Dictionary:
	return {"counts": counts, "host_free_mb": 12000, "reason": reason}


func _run() -> void:
	print("=== RECOVERY probe telemetry tooth ===")
	print("No model calls. Every sabotage must be REJECTED.\n")

	# ---- the well-formed baseline must pass
	var w := _window(P.TREATMENT)
	var good := P.make(w, NEIGHBOURS[0], 0, "post", _rec(300, 250.0),
		_gate(), 12000, 400)
	_ok("well-formed TREATMENT record accepted",
		P.validate(good, w, NEIGHBOURS).is_empty(),
		str(P.validate(good, w, NEIGHBOURS)))

	var wc := _window(P.CONTROL)
	var goodc := P.make(wc, NEIGHBOURS[1], 0, "post", _rec(300, 250.0),
		_gate(), 12000, -1)
	_ok("well-formed CONTROL record accepted",
		P.validate(goodc, wc, NEIGHBOURS).is_empty(),
		str(P.validate(goodc, wc, NEIGHBOURS)))

	# ---- primitives preserved, not just the ratio
	_ok("numerator stored", int(good["observed_ttft_ms"]) == 300)
	_ok("denominator stored", absf(float(good["expected_ttft_ms"]) - 250.0) < 0.001)
	_ok("residual derived correctly",
		absf(float(good["residual"]) - 1.2) < 0.0005)
	_ok("kh20 witness false at 1.2x", not bool(good["residual_ge_kh20"]))
	var big := P.make(w, NEIGHBOURS[0], 1, "post", _rec(8750, 250.0),
		_gate(), 12000, 400)
	_ok("kh20 witness true at 35x", bool(big["residual_ge_kh20"]))
	_ok("suspect/degraded marked audit_only", bool(good["audit_only"]))

	print("\n[SABOTAGE -- each must be rejected]")

	var s1 := good.duplicate(true)
	s1.erase("expected_ttft_ms")
	_ok("S1 missing expected_ttft", _rejected(s1, w, "missing expected_ttft_ms"))

	var s2 := good.duplicate(true)
	s2["expected_ttft_ms"] = 0.0
	_ok("S2 zero expected_ttft", _rejected(s2, w, "zero or negative"))

	var s3 := good.duplicate(true)
	s3["residual"] = 99.0
	_ok("S3 residual inconsistent with numerator/denominator",
		_rejected(s3, w, "inconsistent"))

	var s3b := good.duplicate(true)
	s3b["residual_ge_kh20"] = true
	_ok("S3b kh20 witness disagrees with residual",
		_rejected(s3b, w, "disagrees"))

	var s4 := good.duplicate(true)
	s4["neighbor_model"] = "h2o-danube2-1.8b-chat"
	_ok("S4 wrong neighbour identity", _rejected(s4, w, "wrong neighbour"))

	var s4b := good.duplicate(true)
	s4b["neighbor_model"] = "qwen3.5-2b"
	_ok("S4b neighbour IS the recovered model",
		_rejected(s4b, w, "is the recovered model"))

	var s5 := good.duplicate(true)
	s5["window_id"] = 99
	_ok("S5 wrong window_id", _rejected(s5, w, "wrong window_id"))

	var s5b := good.duplicate(true)
	s5b["schedule_hash"] = "deadbeefdeadbeef"
	_ok("S5b wrong schedule_hash", _rejected(s5b, w, "wrong schedule_hash"))

	var s6 := good.duplicate(true)
	s6["residency_counts"] = {"qwen3.5-2b": 2, "liquidai/lfm2.5-1.2b-instruct": 1,
		"falcon-h1-1.5b-instruct": 1}
	_ok("S6 residency counts mismatch a CLEAN gate",
		_rejected(s6, w, "counts mismatch"))

	var s7 := good.duplicate(true)
	s7["recovery_verified"] = false
	s7["actual_recovery_epoch"] = -1
	_ok("S7 TREATMENT with no verified recovery",
		_rejected(s7, w, "no verified recovery"))

	var s8 := goodc.duplicate(true)
	s8["actual_recovery_epoch"] = 4
	s8["recovery_verified"] = true
	_ok("S8 CONTROL claiming a recovery epoch transition",
		_rejected(s8, wc, "CONTROL record claiming"))

	var s9 := good.duplicate(true)
	s9["audit_only"] = false
	_ok("S9 audit_only stripped (Amendment 1)",
		_rejected(s9, w, "audit_only"))

	print("\n[SUMMARY]")
	print("  checks %d, failures %d" % [_n, _f])
	if _f > 0:
		print("\nTELEMETRY TOOTH RED")
		quit(1)
		return
	print("\nTELEMETRY TOOTH GREEN")
	quit(0)


func _rejected(r: Dictionary, w: Dictionary, needle: String) -> bool:
	var bad := P.validate(r, w, NEIGHBOURS)
	for b in bad:
		if str(b).findn(needle) >= 0:
			return true
	if bad.is_empty():
		print("       (accepted a record that should have been rejected)")
	else:
		print("       (rejected, but for the wrong reason: %s)" % str(bad))
	return false
