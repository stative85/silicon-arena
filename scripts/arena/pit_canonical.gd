extends RefCounted
class_name PitCanonical

## Which fields actually mean something for each operation?
##
## Pre-registered for PIT A Run 3. Run 2 VOID record:
## docs/results/PIT_A_RUN2_VOID.md
##
## WHY THIS EXISTS. Run 2 gave every species a flat schema with five always-
## present fields, and then had the validator enforce RELATIONSHIPS between them
## that a flat JSON Schema cannot state: KEEP must carry `__NONE__`, DELETE must
## carry `none` and empty props, ADD must not carry `none`. Five architectures
## were silently required to coordinate fields nothing told them were coupled,
## and each failed differently, 300 times each, while RANDOM went 300/300.
##
## Several of those failures were SOUND DECISIONS killed by an irrelevant field:
##
##     falcon-h1   MUTATE rule_1, type="rule"     a real mutation
##     lfm2.5      KEEP, target="object id"       a real KEEP
##
## THE RULE: fields irrelevant to an action must not be able to invalidate that
## action.
##
## THIS IS NOT A REPAIR SHOP. Canonicalisation normalises fields the operation
## does not read. It never supplies a field the operation DOES read, never
## changes the operation, and never chooses a target. A decision that is wrong in
## a field the operation actually uses stays wrong:
##
##     qwen3.5   MUTATE with target="__NONE__"    still TARGET_REQUIRED
##     rwkv7     ADD onto an existing id          still TARGET_EXISTS
##
## Mommy does not do the homework.

const K := preload("res://scripts/arena/pit_contract.gd")

## Which fields each operation READS. Everything else is noise and is normalised
## away rather than punished.
const AUTHORITATIVE := {
	"ADD": ["operation", "target", "type", "props"],
	"DELETE": ["operation", "target"],
	"MUTATE": ["operation", "target", "props"],
	"RESTORE": ["operation", "target"],
	"KEEP": ["operation"],
	"REFUSE": ["operation"],
}

## `explanation` is never authoritative for any operation. Prose does not act,
## which is a pre-registered invariant with its own sabotage test.
const NEVER_AUTHORITATIVE := ["explanation"]


static func reads(op: String, field: String) -> bool:
	if not AUTHORITATIVE.has(op):
		return false
	return (AUTHORITATIVE[op] as Array).has(field)


## Normalise a schema-valid proposal into its canonical form.
##
## Returns {"ok": bool, "code": String, "patch": Dictionary, "normalised": Array}
## where `normalised` names every field that was ignored and reset, so the
## journal records what the model said AND what the substrate read.
static func canonicalise(raw: Dictionary) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY or not raw.has("operation"):
		return _bad(K.SHAPE_MALFORMED)
	var op := str(raw.get("operation", ""))
	if not K.OPS.has(op):
		return _bad(K.SHAPE_UNKNOWN_OPERATION)

	var out := {"operation": op, "explanation": str(raw.get("explanation", ""))}
	var touched: Array = []

	# target: kept when the operation reads it, otherwise forced to the sentinel.
	if reads(op, "target"):
		var t := str(raw.get("target", ""))
		if t.strip_edges() == "":
			# The operation READS this field and it is unusable. Not noise.
			return _bad(K.SHAPE_TARGET_REQUIRED)
		out["target"] = t
	else:
		if str(raw.get("target", K.NONE)) != K.NONE:
			touched.append("target")
		out["target"] = K.NONE

	# type: only ADD reads it.
	if reads(op, "type"):
		var ty := str(raw.get("type", ""))
		if ty == "" or ty == K.TYPE_NONE:
			return _bad(K.SHAPE_TYPE_REQUIRED)
		if not K.OBJECT_TYPES.has(ty):
			return _bad(K.SHAPE_UNKNOWN_TYPE)
		out["type"] = ty
	else:
		if str(raw.get("type", K.TYPE_NONE)) != K.TYPE_NONE:
			touched.append("type")
		out["type"] = K.TYPE_NONE

	# props: only ADD and MUTATE read them.
	if reads(op, "props"):
		var p = raw.get("props", {})
		out["props"] = p.duplicate(true) if typeof(p) == TYPE_DICTIONARY else {}
		if typeof(p) != TYPE_DICTIONARY:
			touched.append("props")
	else:
		var q = raw.get("props", {})
		if typeof(q) != TYPE_DICTIONARY or not (q as Dictionary).is_empty():
			touched.append("props")
		out["props"] = {}

	return {"ok": true, "code": K.SHAPE_OK, "patch": out, "normalised": touched}


static func _bad(code: String) -> Dictionary:
	return {"ok": false, "code": code, "patch": {}, "normalised": []}


## The canonicalisation contract's own fingerprint, recorded in provenance
## alongside the schema hash. A changed canonicalisation is a changed regime.
static func canonical_hash() -> String:
	var text := ""
	var ops: Array = AUTHORITATIVE.keys()
	ops.sort()
	for op in ops:
		text += "%s=%s\n" % [str(op), ",".join(PackedStringArray(AUTHORITATIVE[op]))]
	text += "never=" + ",".join(PackedStringArray(NEVER_AUTHORITATIVE)) + "\n"
	return text.sha256_text()
