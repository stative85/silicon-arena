extends RefCounted
class_name PitProposalContract

## The ONE definition of what a PIT A proposal is.
##
## Pre-registered in docs/EXPERIMENT_PIT_A.md, Run 2 amendment at 0005e14.
##
## THIS FILE EXISTS BECAUSE RUN 1 HAD TWO CONTRACTS AND NOBODY NOTICED.
## The model-facing schema exposed operation/target/explanation. The validator
## required `type` for ADD. PitRandom built ADD patches WITH `type`, using a
## field no model could emit. So the control had a strictly larger action space
## than every treatment arm, 1,167 of 1,500 model cycles died at the contract
## boundary, and three species never changed the world once
## (docs/results/PIT_A_RUN1_VOID.md).
##
## Every consumer now derives from here:
##
##     json_schema generation   PitValidator   PitRandom
##     reachability audit       the runner
##
## Not five opinions about what the contract probably is.
##
## THE SCHEMA IS STATIC AND FROZEN. It never enumerates live object ids, because
## a state-dependent schema would produce a different hash every cycle and the
## gate's whole job is to notice when the hash changes. World legality is the
## semantic validator's business, never the schema's.
##
## NO oneOf, NO conditional subschemas. Those buy prettier documents and add a
## backend-feature dependency across five architectures, which is one more way
## to build a scientific rake and step on it. Five fields, always present.

## Every proposal carries all five fields. Absent fields are not "optional" --
## they are the shape of the Run 1 failure.
const FIELDS := ["operation", "target", "type", "props", "explanation"]

const OPS := ["ADD", "DELETE", "MUTATE", "KEEP", "RESTORE", "REFUSE"]

## Object kinds, plus an explicit `none`. A sentinel beats an empty string
## because it makes "no type" a value rather than an absence.
const OBJECT_TYPES := ["entity", "rule", "memory", "tool", "test", "provenance"]
const TYPE_NONE := "none"

## Reserved target for operations that address nothing. An empty string is
## invalid EVERYWHERE, so there is no "empty means no target, except when it
## means a broken DELETE" ambiguity -- which is exactly how LFM2.5 spent 300
## cycles emitting schema-valid impossibilities in Run 1.
const NONE := "__NONE__"

const SHAPE_OK := "OK"
const SHAPE_MALFORMED := "MALFORMED_PATCH"
const SHAPE_UNKNOWN_OPERATION := "UNKNOWN_OPERATION"
const SHAPE_UNKNOWN_TYPE := "UNKNOWN_TYPE"
const SHAPE_TARGET_REQUIRED := "TARGET_REQUIRED"
const SHAPE_TARGET_FORBIDDEN := "TARGET_FORBIDDEN"
const SHAPE_TYPE_REQUIRED := "TYPE_REQUIRED"
const SHAPE_TYPE_FORBIDDEN := "TYPE_FORBIDDEN"
const SHAPE_PROPS_FORBIDDEN := "PROPS_FORBIDDEN"


## Operations that address an object. The rest use NONE.
static func needs_target(op: String) -> bool:
	return op == "ADD" or op == "DELETE" or op == "MUTATE" or op == "RESTORE"


## Only ADD names a kind. Everything else carries TYPE_NONE.
static func needs_type(op: String) -> bool:
	return op == "ADD"


## Only ADD and MUTATE carry properties.
static func allows_props(op: String) -> bool:
	return op == "ADD" or op == "MUTATE"


# ------------------------------------------------------- the frozen schema

## The exact json_schema every species emits through. Static: no live ids, no
## conditionals, no per-species variation.
static func schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"operation": {"type": "string", "enum": OPS},
			"target": {"type": "string", "minLength": 1},
			"type": {"type": "string", "enum": OBJECT_TYPES + [TYPE_NONE]},
			"props": {"type": "object"},
			"explanation": {"type": "string"},
		},
		"required": FIELDS.duplicate(),
		"additionalProperties": false,
	}


## Canonical text for hashing. Sorted so key order cannot change the hash.
static func schema_text() -> String:
	var s := schema()
	var props: Dictionary = s["properties"]
	var keys: Array = props.keys()
	keys.sort()
	var out := "fields=" + ",".join(PackedStringArray(FIELDS)) + "\n"
	for k in keys:
		out += "%s=%s\n" % [str(k), JSON.stringify(props[k])]
	out += "required=" + ",".join(PackedStringArray(s["required"])) + "\n"
	out += "additionalProperties=false\nsentinel=%s\ntype_none=%s\n" % [NONE, TYPE_NONE]
	return out


static func schema_hash() -> String:
	return schema_text().sha256_text()


# ---------------------------------------------------------- constructors
#
# THE ONLY WAY TO BUILD A PROPOSAL. RANDOM, the audit and the runner all come
# through here, so RANDOM cannot acquire a private vocabulary again.

static func add(target: String, object_type: String,
		props: Dictionary = {}, explanation: String = "") -> Dictionary:
	return {"operation": "ADD", "target": target, "type": object_type,
		"props": props, "explanation": explanation}


static func delete(target: String, explanation: String = "") -> Dictionary:
	return {"operation": "DELETE", "target": target, "type": TYPE_NONE,
		"props": {}, "explanation": explanation}


static func mutate(target: String, props: Dictionary,
		explanation: String = "") -> Dictionary:
	return {"operation": "MUTATE", "target": target, "type": TYPE_NONE,
		"props": props, "explanation": explanation}


static func restore(target: String, explanation: String = "") -> Dictionary:
	return {"operation": "RESTORE", "target": target, "type": TYPE_NONE,
		"props": {}, "explanation": explanation}


static func keep(explanation: String = "") -> Dictionary:
	return {"operation": "KEEP", "target": NONE, "type": TYPE_NONE,
		"props": {}, "explanation": explanation}


static func refuse(explanation: String = "") -> Dictionary:
	return {"operation": "REFUSE", "target": NONE, "type": TYPE_NONE,
		"props": {}, "explanation": explanation}


# ---------------------------------------------------------- shape checking

## Is this a well-formed proposal under the frozen contract, ignoring the world?
##
## Separate from world legality on purpose: this is what the schema is supposed
## to guarantee, so a failure here means the instrument and the contract have
## drifted apart -- the Run 1 condition.
static func shape(patch: Dictionary) -> Dictionary:
	if typeof(patch) != TYPE_DICTIONARY:
		return {"ok": false, "code": SHAPE_MALFORMED}
	for f in FIELDS:
		if not patch.has(f):
			return {"ok": false, "code": SHAPE_MALFORMED}
	for k in patch.keys():
		if not FIELDS.has(str(k)):
			return {"ok": false, "code": SHAPE_MALFORMED}

	var op := str(patch["operation"])
	if not OPS.has(op):
		return {"ok": false, "code": SHAPE_UNKNOWN_OPERATION}
	if typeof(patch["target"]) != TYPE_STRING \
			or typeof(patch["type"]) != TYPE_STRING \
			or typeof(patch["props"]) != TYPE_DICTIONARY \
			or typeof(patch["explanation"]) != TYPE_STRING:
		return {"ok": false, "code": SHAPE_MALFORMED}

	var target := str(patch["target"])
	if target == "":
		return {"ok": false, "code": SHAPE_MALFORMED}
	var t := str(patch["type"])
	if not (OBJECT_TYPES.has(t) or t == TYPE_NONE):
		return {"ok": false, "code": SHAPE_UNKNOWN_TYPE}

	if needs_target(op):
		if target == NONE:
			return {"ok": false, "code": SHAPE_TARGET_REQUIRED}
	else:
		if target != NONE:
			return {"ok": false, "code": SHAPE_TARGET_FORBIDDEN}

	if needs_type(op):
		if t == TYPE_NONE:
			return {"ok": false, "code": SHAPE_TYPE_REQUIRED}
	else:
		if t != TYPE_NONE:
			return {"ok": false, "code": SHAPE_TYPE_FORBIDDEN}

	if not allows_props(op) and not (patch["props"] as Dictionary).is_empty():
		return {"ok": false, "code": SHAPE_PROPS_FORBIDDEN}

	return {"ok": true, "code": SHAPE_OK}
