extends RefCounted
class_name AsyncRuntimeGuard

## Gate 4: runtime integrity for one measured replicate.
##
## ASYNC-A measures timing under a STABLE three-model explicit-residency
## regime. Runtime degradation, recovery, eviction and residency transitions
## are NOT experimental treatments -- they void the affected replicate. Written
## down so that a future reader confronted with a spectacular result cannot
## decide afterwards that a surprise GPU eviction was "part of the ecology".
##
## AN ISOLATED SUSPECT DOES NOT VOID. The frozen health policy records SUSPECT
## and explicitly does not recover on it; only three consecutive suspect calls
## make DEGRADED actionable, because n=1 produced false positives on held-out
## data. Voiding on any SUSPECT would resurrect n=1 through the experimental
## harness after the health work proved n=1 wrong. Suspects are recorded as
## runtime context; they are not a failed regime.
##
## EVENTS, NOT SNAPSHOTS. Endpoint hashes cannot see a transient:
##
##   start  A B C   hash X
##   mid    C evicted, C reloaded
##   end    A B C   hash X
##
## The endpoints agree while one model spent several world ticks absent, and
## those ticks are in the data. The bridge already emits explicit
## model_state_changed and recovery signals, so those are consumed as
## AUTHORITATIVE rather than inferred later from before/after comparisons.

const HL := preload("res://scripts/arena/bridge_health.gd")
const M := preload("res://scripts/arena/bridge_model.gd")

## Conditions that void. Deliberately excludes SUSPECT.
const VOIDING_VERDICTS := [HL.DEGRADED, HL.CATASTROPHE]
const VOIDING_STATES := [M.DEGRADED, M.WEDGED, M.EVICTED, M.RECOVERING]

var replicate_id: String = ""
var expected_resident: Array = []
var expected_resident_hash: String = ""

var start_resident_set: Array = []
var start_model_states: Dictionary = {}
var end_resident_set: Array = []
var end_model_states: Dictionary = {}

var runtime_events: Array = []
var suspects: Array = []              ## recorded, never voiding
var observed_resident_hashes: Dictionary = {}

var void_reason: String = ""
var world_tick: int = 0               ## set by the runner each tick


static func hash_set(ids: Array) -> String:
	var s: Array = ids.duplicate()
	s.sort()
	return ("|".join(PackedStringArray(s))).sha256_text().substr(0, 16)


static func make(rid: String, expected: Array) -> AsyncRuntimeGuard:
	var g := AsyncRuntimeGuard.new()
	g.replicate_id = rid
	g.expected_resident = expected.duplicate()
	g.expected_resident_hash = hash_set(expected)
	return g


func begin(resident: Array, states: Dictionary) -> void:
	start_resident_set = resident.duplicate()
	start_model_states = states.duplicate()
	observed_resident_hashes[hash_set(resident)] = 1
	if hash_set(resident) != expected_resident_hash:
		_void("start resident set is not the expected regime")


## Consume the bridge's own state-change signal. Authoritative.
func on_model_state_changed(model_id: String, from: String, to: String,
		reason: String) -> void:
	_record("model_state_changed", model_id, from, to, reason)
	if VOIDING_STATES.has(to):
		_void("model %s entered %s during a measured replicate"
			% [model_id, to])


## Consume the bridge's own recovery signal. Any recovery voids.
func on_recovery(model_id: String, action: String, ok: bool) -> void:
	_record("recovery", model_id, "", action, "ok=%s" % str(ok))
	_void("bridge recovery (%s) on %s during a measured replicate"
		% [action, model_id])


## Every receipt is a second, differently-sourced witness to residency.
func on_receipt(rec: Dictionary) -> void:
	var verdict := str(rec.get("health_verdict", ""))
	if verdict == HL.SUSPECT:
		# Recorded as runtime context. NOT a void condition.
		suspects.append({"request_id": str(rec.get("request_id", "")),
			"model_id": str(rec.get("model_id", "")),
			"residual": float(rec.get("health_residual", -1.0)),
			"world_tick": world_tick})
	elif VOIDING_VERDICTS.has(verdict):
		_record("health_verdict", str(rec.get("model_id", "")), "", verdict,
			"residual %.2f" % float(rec.get("health_residual", -1.0)))
		_void("health verdict %s on %s"
			% [verdict, str(rec.get("model_id", ""))])

	var rs: Array = rec.get("resident_set", [])
	if not rs.is_empty():
		var h := hash_set(rs)
		observed_resident_hashes[h] = int(observed_resident_hashes.get(h, 0)) + 1
		if h != expected_resident_hash:
			_record("resident_mismatch", "", expected_resident_hash, h,
				"from receipt " + str(rec.get("request_id", "")))
			_void("a receipt observed a resident set differing from R0")


## Periodic poll. Catches a transition the signals somehow missed.
func on_residency_poll(resident: Array) -> void:
	var h := hash_set(resident)
	observed_resident_hashes[h] = int(observed_resident_hashes.get(h, 0)) + 1
	if h != expected_resident_hash:
		_record("residency_poll_mismatch", "", expected_resident_hash, h, "")
		_void("polled resident set differs from R0")


func finish(resident: Array, states: Dictionary) -> void:
	end_resident_set = resident.duplicate()
	end_model_states = states.duplicate()
	var h := hash_set(resident)
	observed_resident_hashes[h] = int(observed_resident_hashes.get(h, 0)) + 1
	if h != expected_resident_hash:
		_void("end resident set is not the expected regime")


func _record(kind: String, model_id: String, before: String, after: String,
		note: String) -> void:
	runtime_events.append({
		"timestamp_ms": Time.get_ticks_msec(), "world_tick": world_tick,
		"event_type": kind, "model_id": model_id,
		"state_before": before, "state_after": after, "note": note,
	})


func _void(reason: String) -> void:
	if void_reason == "":
		void_reason = reason


func is_void() -> bool:
	return void_reason != ""


## The endpoint-only view, kept ONLY to demonstrate that it is insufficient.
## A transient eviction and restore leaves both endpoints identical.
func endpoints_agree() -> bool:
	return hash_set(start_resident_set) == hash_set(end_resident_set)


func envelope() -> Dictionary:
	return {
		"replicate_id": replicate_id,
		"expected_resident": expected_resident,
		"expected_resident_hash": expected_resident_hash,
		"start_resident_set": start_resident_set,
		"start_resident_hash": hash_set(start_resident_set),
		"start_model_states": start_model_states,
		"runtime_events": runtime_events,
		"suspects": suspects,
		"observed_resident_hashes": observed_resident_hashes.keys(),
		"end_resident_set": end_resident_set,
		"end_resident_hash": hash_set(end_resident_set),
		"end_model_states": end_model_states,
		"void_reason": void_reason,
	}
