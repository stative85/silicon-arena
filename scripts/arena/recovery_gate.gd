extends RefCounted
class_name RecoveryGate

## RECOVERY-COUPLING step 3: the contamination gate.
##
## Watches the FULL RESIDENCY COUNT VECTOR, not merely disappearance. LM Studio
## can instantiate the same logical model more than once, so presence is not
## evidence of state:
##
##     qwen3.5-2b = 1, lfm2.5 = 1, falcon = 1, TOTAL = 3
##
## An extra instance, a missing one, a replacement, or an unexpected model each
## voids the window even though "every expected model is present" may still be
## true of the naive set.
##
## FIRST OFFENCE IS PRESERVED. A window does not merely carry `void = true`; it
## carries what killed it, when, and the count vector at that instant. A void
## with no cause is a dead end for whoever reads the artifact later.

const RA := preload("res://scripts/arena/recovery_action.gd")

const OK := "CLEAN"
const DUPLICATE := "UNEXPECTED_DUPLICATE"
const DISAPPEARED := "UNEXPECTED_DISAPPEARANCE"
const REPLACED := "UNEXPECTED_REPLACEMENT"
const UNSCHEDULED := "UNSCHEDULED_RECOVERY"
const FOREIGN := "UNEXPECTED_RESIDENT_MODEL"
const RAM_FLOOR := "RAM_FLOOR_EVENT"
const TRANSPORT := "TRANSPORT_OR_RUNTIME_FAILURE"

const HOST_FLOOR_MB := 2048.0

var expected: Dictionary = {}      ## base model id -> expected instance count
var window_id: int = -1
var offences: Array = []           ## every offence, in order
var first_offence: Dictionary = {} ## the one that killed the window


func begin(window: int, expect_counts: Dictionary) -> void:
	window_id = window
	expected = expect_counts.duplicate()
	offences.clear()
	first_offence = {}


## Classify a count vector against the expectation. Returns a reason constant.
##
## The classification is deliberately specific: "something changed" is not
## actionable, and the three ways a count vector can differ have different
## causes. A duplicate is a non-idempotent load. A disappearance is an eviction
## or a crash. A replacement is both at once and is the most alarming.
static func classify(got: Dictionary, want: Dictionary) -> String:
	var missing: Array = []
	var extra: Array = []
	var foreign: Array = []
	for k in want:
		var g := int(got.get(k, 0))
		var wv := int(want[k])
		if g < wv:
			missing.append(k)
		elif g > wv:
			extra.append(k)
	for k in got:
		if not want.has(k):
			foreign.append(k)
	if not foreign.is_empty():
		return FOREIGN
	if not missing.is_empty() and not extra.is_empty():
		return REPLACED
	if not extra.is_empty():
		return DUPLICATE
	if not missing.is_empty():
		return DISAPPEARED
	return OK


## Sample the runtime. Call at every phase boundary of a window, in BOTH
## treatment and control, so the observation burden matches.
func sample(http: HTTPRequest, phase: String, elapsed_ms: int) -> Dictionary:
	var counts := await RA.residency_counts(http)
	var reason := OK
	if counts.is_empty():
		reason = TRANSPORT          # a failed read is not an empty pool
	else:
		reason = classify(counts, expected)
	var mem := OS.get_memory_info()
	var free_mb := float(mem.get("free", 0)) / (1024.0 * 1024.0)
	if reason == OK and free_mb > 0.0 and free_mb < HOST_FLOOR_MB:
		reason = RAM_FLOOR
	var s := {
		"window_id": window_id, "phase": phase, "elapsed_ms": elapsed_ms,
		"counts": counts, "expected": expected,
		"host_free_mb": int(free_mb), "reason": reason,
		"at_ms": Time.get_ticks_msec(),
	}
	if reason != OK:
		offences.append(s)
		if first_offence.is_empty():
			first_offence = s
	return s


## An unscheduled recovery is a contamination even if residency looks correct
## afterwards -- a fast unload/reload can land entirely between two samples. The
## window executor reports any recovery it did not itself schedule.
func note_unscheduled_recovery(model_id: String, elapsed_ms: int) -> void:
	var s := {
		"window_id": window_id, "phase": "unscheduled", "elapsed_ms": elapsed_ms,
		"model_id": model_id, "reason": UNSCHEDULED,
		"at_ms": Time.get_ticks_msec(),
	}
	offences.append(s)
	if first_offence.is_empty():
		first_offence = s


func note_transport(detail: String, elapsed_ms: int) -> void:
	var s := {
		"window_id": window_id, "phase": "transport", "elapsed_ms": elapsed_ms,
		"detail": detail, "reason": TRANSPORT, "at_ms": Time.get_ticks_msec(),
	}
	offences.append(s)
	if first_offence.is_empty():
		first_offence = s


func is_void() -> bool:
	return not first_offence.is_empty()


func envelope() -> Dictionary:
	return {
		"window_id": window_id, "expected": expected,
		"void": is_void(),
		"void_reason": str(first_offence.get("reason", "")),
		"first_offence": first_offence,
		"offences": offences,
		"offence_count": offences.size(),
	}
