extends SceneTree

## Does ACTION_SCHEMA_V1 still agree with the canonical vocabulary?
##
##   godot --headless --path . --script tools/action_schema_selftest.gd
##
## config/action-schema.v1.json is the FROZEN live decision seam: the exact
## grammar the arena constrains generation with, hashed into every artifact.
## Being frozen is what makes it evidence -- and it is also how it silently
## stops matching canonical_operation.gd the first time a verb or a required
## field changes there.
##
## PIT A run 1 kept a private copy of a contract shape, the copy disagreed with
## the validator, and nothing in the instrument could notice. This is that
## check, made mechanical. A drift here is a BLOCKER, not a warning: a schema
## that permits a verb the reducer does not implement, or omits a field the
## parser demands, produces agents that cannot act and a log that cannot say
## why.

const OP := preload("res://scripts/breach/canonical_operation.gd")

const SCHEMA_PATH := "res://config/action-schema.v1.json"

var _fail := 0


func ck(label: String, cond: bool) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail += 1


func _init() -> void:
	print("=== ACTION_SCHEMA_V1 vs canonical_operation.gd ===")
	var fh := FileAccess.open(SCHEMA_PATH, FileAccess.READ)
	if fh == null:
		print("  FAIL cannot open %s" % SCHEMA_PATH)
		quit(1)
		return
	var text := fh.get_as_text()
	fh.close()

	var parsed = JSON.parse_string(text)
	ck("the schema file is valid JSON", typeof(parsed) == TYPE_DICTIONARY)
	if typeof(parsed) != TYPE_DICTIONARY:
		print("ACTION SCHEMA DRIFT: the seam is not a JSON object.")
		print("Do not run the arena against a seam that does not parse.")
		quit(1)
		return
	var doc: Dictionary = parsed

	var branches: Array = doc.get("anyOf", [])
	ck("it is a union", not branches.is_empty())

	## Every branch names exactly one operation, via const.
	var named := {}
	var shaped := true
	for b in branches:
		if typeof(b) != TYPE_DICTIONARY:
			shaped = false
			continue
		var props: Dictionary = b.get("properties", {})
		var opdef: Dictionary = props.get("operation", {})
		if not opdef.has("const"):
			shaped = false
			continue
		named[str(opdef["const"])] = b
	ck("every branch pins one operation with const", shaped)

	## MEMBERSHIP. The union must be the agent-choosable set exactly -- no verb
	## missing, and nothing extra.
	var choosable := {}
	for op in OP.AGENT_CHOOSABLE:
		choosable[str(op)] = true
	var missing := []
	for op in choosable.keys():
		if not named.has(op):
			missing.append(op)
	var extra := []
	for op in named.keys():
		if not choosable.has(op):
			extra.append(op)
	ck("no agent-choosable operation is missing (%s)"
		% ("none" if missing.is_empty() else ", ".join(missing)),
		missing.is_empty())
	ck("no operation outside the vocabulary (%s)"
		% ("none" if extra.is_empty() else ", ".join(extra)),
		extra.is_empty())

	## NO_OP is host-authored. A schema that lets an agent select it would let a
	## model declare its own turn void, which the parser refuses on purpose.
	ck("NO_OP is not selectable by an agent", not named.has(OP.NO_OP))

	## FIELDS. Each branch requires exactly its operation's required fields,
	## plus the discriminator, and permits nothing else.
	var field_ok := true
	var detail := ""
	for op in OP.AGENT_CHOOSABLE:
		var sop := str(op)
		if not named.has(sop):
			continue
		var b: Dictionary = named[sop]
		var want := ["operation"]
		for f in OP.required_fields(op):
			want.append(str(f))
		want.sort()
		var got: Array = (b.get("required", []) as Array).duplicate()
		got.sort()
		if want != got:
			field_ok = false
			detail += " %s(want %s got %s)" % [sop, want, got]
		var props: Dictionary = b.get("properties", {})
		var pkeys: Array = props.keys()
		pkeys.sort()
		if pkeys != want:
			field_ok = false
			detail += " %s(properties %s)" % [sop, pkeys]
		if bool(b.get("additionalProperties", true)):
			field_ok = false
			detail += " %s(additionalProperties not false)" % sop
	ck("every branch requires exactly its fields, and no others%s" % detail,
		field_ok)

	print("")
	if _fail == 0:
		print("ACTION SCHEMA OK -- the frozen seam matches the vocabulary")
		quit(0)
	else:
		print("ACTION SCHEMA DRIFT: %d check(s) failed." % _fail)
		print("The schema is frozen and the vocabulary moved, or the reverse.")
		print("Do not run the arena against a seam that does not match.")
		quit(1)
