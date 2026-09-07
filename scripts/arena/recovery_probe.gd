extends RefCounted
class_name RecoveryProbe

## RECOVERY-COUPLING step 4: the neighbour-probe telemetry record.
##
## BORING, IMMUTABLE, MECHANICAL EVIDENCE. No interpretation, no recovery
## decision, no adaptive behaviour, no clever summary during collection.
##
## THE PRIMITIVES ARE STORED, NOT JUST THE DERIVED STATISTIC. `residual` is kept
## alongside BOTH its numerator and its denominator, because HEALTH-REUSE showed
## a thresholded verdict can swing wildly while the continuous statistic barely
## moves -- and because if a neighbour jumps 1.2 -> 35, the analysis must be able
## to ask whether observed TTFT exploded or the expectation surface collapsed. A
## naked ratio throws away the crime scene.
##
## AMENDMENT 1 IS ENFORCED IN THE DATA, not left to the report writer. `suspect`
## and `degraded` are recorded but carry `audit_only = true`, and the validator
## rejects any record that omits that marking.
##
## TREATMENT AND CONTROL ARE DISTINGUISHED BY VERIFIED FACT. A TREATMENT record
## must carry a real recovery epoch transition; a CONTROL record must not claim
## one. That makes it impossible for the analysis layer to confuse the NOMINAL
## target with a recovery that actually happened.

const TREATMENT := "TREATMENT"
const CONTROL := "CONTROL"

## Frozen primary threshold. Not adjusted, not read from config, not tunable.
const KH := 20.0


## Build one immutable probe record.
static func make(window: Dictionary, neighbour: String, probe_index: int,
		phase: String, rec: Dictionary, gate_sample: Dictionary,
		ms_since_window: int, ms_since_recovery: int) -> Dictionary:
	var observed := int(rec.get("ttft_ms", -1))
	var expected := float(rec.get("health_expected_ms", -1.0))
	var residual := -1.0
	if observed >= 0 and expected > 0.0:
		residual = float(observed) / expected
	return {
		# identity
		"window_id": int(window.get("window_id", -1)),
		"schedule_hash": str(window.get("schedule_hash", "")),
		"condition": str(window.get("condition", "")),
		"nominal_recovered_model": str(window.get("recovered_model", "")),
		"actual_recovery_epoch": int(window.get("actual_recovery_epoch", -1)),
		"recovery_verified": bool(window.get("recovery_verified", false)),
		"neighbor_model": neighbour,

		# position in the window
		"probe_index": probe_index,
		"probe_phase": phase,
		"ms_since_window_start": ms_since_window,
		"ms_since_recovery_completion": ms_since_recovery,

		# request shape
		"prompt_tokens": int(rec.get("prompt_tokens", -1)),
		"load_condition": int(rec.get("max_active_during", -1)),
		"max_active": int(rec.get("max_active_during", -1)),

		# raw clocks
		"submitted_ms": int(rec.get("submitted_at_ms", -1)),
		"first_token_ms": int(rec.get("first_token_at_ms", -1)),
		"completed_ms": int(rec.get("finished_at_ms", -1)),

		# THE PRIMITIVES, kept beside the derived statistic
		"observed_ttft_ms": observed,
		"expected_ttft_ms": expected,
		"residual": residual,

		# frozen primary endpoint witness
		"residual_ge_kh20": residual >= KH,

		# runtime state at the instant of the probe
		"residency_counts": gate_sample.get("counts", {}),
		"host_free_ram_mb": int(gate_sample.get("host_free_mb", -1)),
		"gate_state": str(gate_sample.get("reason", "")),

		# transport
		"transport_ok": str(rec.get("status", "")) == "OK",
		"completion_ok": observed >= 0,

		# AUDIT ONLY -- barred as treatment evidence by Amendment 1
		"suspect": str(rec.get("health_verdict", "")) == "SUSPECT",
		"degraded": str(rec.get("health_verdict", "")) == "DEGRADED",
		"audit_only": true,
	}


## Mechanical validation. Returns a list of problems; empty means well formed.
##
## A recorder that has never caught a malformed record is an optimistic diary,
## so every one of these is exercised by the step-4 tooth.
static func validate(r: Dictionary, expect_window: Dictionary,
		expect_neighbours: Array) -> Array:
	var bad: Array = []

	if not r.has("expected_ttft_ms"):
		bad.append("missing expected_ttft_ms")
	elif float(r["expected_ttft_ms"]) <= 0.0 and bool(r.get("completion_ok", false)):
		bad.append("expected_ttft_ms is zero or negative on a completed probe")

	# residual must equal its own numerator over its own denominator
	if bool(r.get("completion_ok", false)):
		var o := float(r.get("observed_ttft_ms", -1))
		var e := float(r.get("expected_ttft_ms", -1))
		var got := float(r.get("residual", -1.0))
		if e > 0.0 and absf(got - (o / e)) > 0.0005:
			bad.append("residual %.4f inconsistent with %.1f / %.1f"
				% [got, o, e])
		if bool(r.get("residual_ge_kh20", false)) != (got >= KH):
			bad.append("residual_ge_kh20 disagrees with residual")

	if not expect_neighbours.has(str(r.get("neighbor_model", ""))):
		bad.append("wrong neighbour identity: " + str(r.get("neighbor_model", "")))
	if str(r.get("neighbor_model", "")) == str(r.get("nominal_recovered_model", "")):
		bad.append("neighbour is the recovered model")

	if int(r.get("window_id", -1)) != int(expect_window.get("window_id", -2)):
		bad.append("wrong window_id")
	if str(r.get("schedule_hash", "")) != str(expect_window.get("schedule_hash", "")):
		bad.append("wrong schedule_hash")

	var gate_counts: Dictionary = r.get("residency_counts", {})
	var expect_counts: Dictionary = expect_window.get("expected_counts", {})
	if not expect_counts.is_empty():
		if gate_counts.is_empty():
			bad.append("residency counts absent from the record")
		elif not _counts_equal(gate_counts, expect_counts) \
				and str(r.get("gate_state", "")) == "CLEAN":
			bad.append("residency counts mismatch a CLEAN gate state")

	# the treatment boundary, enforced in the data
	var cond := str(r.get("condition", ""))
	if cond == TREATMENT:
		if not bool(r.get("recovery_verified", false)):
			bad.append("TREATMENT record with no verified recovery")
		if int(r.get("actual_recovery_epoch", -1)) < 0:
			bad.append("TREATMENT record with no recovery epoch")
	elif cond == CONTROL:
		if bool(r.get("recovery_verified", false)):
			bad.append("CONTROL record claiming a verified recovery")
		if int(r.get("actual_recovery_epoch", -1)) >= 0:
			bad.append("CONTROL record claiming a recovery epoch transition")
	else:
		bad.append("unknown condition: " + cond)

	if not bool(r.get("audit_only", false)):
		bad.append("suspect/degraded not marked audit_only (Amendment 1)")

	return bad


static func _counts_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in b:
		if int(a.get(k, 0)) != int(b[k]):
			return false
	return true
