extends RefCounted
class_name PitValidator

## Is this proposal legal against the world as it actually is?
##
## Pre-registered in docs/EXPERIMENT_PIT_A.md at 15f30e9.
##
## SEMANTIC LEGALITY ONLY. Under the frozen instrument every species emits
## through `response_format: json_schema`, so a SYNTACTICALLY malformed patch is
## close to unreachable. Counting syntax would be counting a statistic that
## cannot move -- the correction is recorded in the pre-registration and this
## file is where it is enforced. What remains fully reachable, and what this
## validator exists to catch, is a proposal that is well-formed and impossible:
##
##     RESTORE of something never deleted
##     DELETE of something already gone
##     MUTATE of an absent target
##     ADD of an id that already exists
##     any operation against an immutable provenance object
##
## THE SAME RULES FOR EVERY SPECIES. No model-specific exceptions, no silent
## repair, no retry that turns an invalid proposal into a valid one. A refused
## proposal consumes the opportunity and is recorded with its reason, because
## what an architecture reaches for and cannot have is evidence.

const W := preload("res://scripts/arena/pit_world.gd")
const K := preload("res://scripts/arena/pit_contract.gd")

const OK := "OK"
const UNKNOWN_OPERATION := "UNKNOWN_OPERATION"
const MALFORMED_PATCH := "MALFORMED_PATCH"
const UNKNOWN_TYPE := "UNKNOWN_TYPE"
const TARGET_ABSENT := "TARGET_ABSENT"
const TARGET_EXISTS := "TARGET_EXISTS"
const NOT_TOMBSTONED := "NOT_TOMBSTONED"
const ALREADY_ALIVE := "ALREADY_ALIVE"
const IMMUTABLE_TARGET := "IMMUTABLE_TARGET"

## Reason codes that mean "well-formed but impossible in this world". These are
## the semantic-invalid class the pre-registration counts; UNKNOWN_OPERATION and
## MALFORMED_PATCH are plumbing and are reported separately.
const SEMANTIC := [TARGET_ABSENT, TARGET_EXISTS, NOT_TOMBSTONED, ALREADY_ALIVE,
	IMMUTABLE_TARGET, UNKNOWN_TYPE]


static func is_semantic(code: String) -> bool:
	return SEMANTIC.has(code)


## Returns {"ok": bool, "code": String}.
static func validate(state: Dictionary, patch: Dictionary) -> Dictionary:
	# SHAPE FIRST, from the one shared contract. Run 1 had the validator and the
	# model-facing schema disagreeing about which fields exist; there is now a
	# single definition and both sides read it.
	var sh := K.shape(patch)
	if not bool(sh["ok"]):
		return _no(str(sh["code"]))

	var op := str(patch["operation"])

	# A decision to change nothing is always legal. It is also a real decision,
	# and is recorded as one rather than treated as an absence of input.
	if op == "KEEP" or op == "REFUSE":
		return _yes()

	var target := str(patch["target"])

	# Provenance is structural. Refusing here, loudly, is what keeps canonical
	# history reconstructible no matter what a species proposes.
	if W.type_of(state, target) == W.IMMUTABLE_TYPE:
		return _no(IMMUTABLE_TARGET)

	match op:
		"ADD":
			# Shape already proved `type` is a real object kind and not `none`.
			if str(patch["type"]) == W.IMMUTABLE_TYPE:
				return _no(IMMUTABLE_TARGET)
			if W.is_alive(state, target):
				return _no(TARGET_EXISTS)
			if W.is_tombstoned(state, target):
				# Re-using a tombstoned id would make DELETE->ADD and
				# DELETE->RESTORE indistinguishable in the trajectory, and those
				# are two different behaviours the experiment measures apart.
				return _no(TARGET_EXISTS)
			return _yes()
		"DELETE", "MUTATE":
			if not W.is_alive(state, target):
				return _no(TARGET_ABSENT)
			return _yes()
		"RESTORE":
			if W.is_alive(state, target):
				return _no(ALREADY_ALIVE)
			if not W.is_tombstoned(state, target):
				return _no(NOT_TOMBSTONED)
			return _yes()
	return _no(UNKNOWN_OPERATION)


static func _yes() -> Dictionary:
	return {"ok": true, "code": OK}


static func _no(code: String) -> Dictionary:
	return {"ok": false, "code": code}
