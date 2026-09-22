extends SceneTree

## The schema that leaves the process must be the schema on disk, byte for byte.
##
##   godot --headless --path . --script tools/live_seam_regression.gd
##
## THE BUG THIS EXISTS TO PREVENT, which already happened once:
##
## The backend compiles a JSON schema into a GBNF grammar in which the ORDER of
## `properties` is the required emission order. Godot's
## JSON.parse_string -> Dictionary -> JSON.stringify round trip reorders object
## keys ALPHABETICALLY. GIVE therefore left as object,operation,target, the
## grammar demanded "object" first, and a model correctly beginning with
## "operation" could only be inside a single-field branch. GIVE and OFFER became
## unreachable and MOVE fell out instead -- for all five species at once, which
## is what finally identified it as the harness rather than the models.
##
## Nothing in the request looked wrong. The schema was valid, the hash of the
## FILE was unchanged, every field was present. Only the byte order differed,
## and only the grammar could see it.
##
## So the assertion is not "the file is unchanged". It is: THE BYTES ON THE WIRE
## HASH TO THE FILE. Offline. No LM Studio, no inference, no network.

const OP := preload("res://scripts/breach/canonical_operation.gd")

const SCHEMA_PATH := "res://config/action-schema.v1.json"
const PLACEHOLDER := "__LIVE_SCHEMA_BYTES__"

var _fail := 0


func ck(label: String, cond: bool) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail += 1


func _sha(text: String) -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(text.to_utf8_buffer())
	return c.finish().hex_encode()


## The exact construction the live seam must use: schema held as TEXT, spliced
## into the serialised body. If this ever becomes parse/stringify, the checks
## below fail.
func _build_payload(schema_text: String) -> String:
	var body := {"model": "fixture", "messages": [{"role": "user",
		"content": "fixture"}], "max_tokens": 512, "temperature": 0.0,
		"stream": false,
		"response_format": {"type": "json_schema", "json_schema": {
			"name": "ACTION_SCHEMA_V1", "strict": true,
			"schema": PLACEHOLDER}}}
	return JSON.stringify(body).replace("\"" + PLACEHOLDER + "\"", schema_text)


func _extract_schema(payload: String) -> String:
	var key := "\"schema\":"
	var at := payload.find(key)
	if at < 0:
		return ""
	var start := at + key.length()
	while start < payload.length() and payload[start] == " ":
		start += 1
	if start >= payload.length() or payload[start] != "{":
		return ""
	## Brace matching, string-aware: the schema contains braces inside strings.
	var depth := 0
	var i := start
	var in_str := false
	var esc := false
	while i < payload.length():
		var ch := payload[i]
		if in_str:
			if esc:
				esc = false
			elif ch == "\\":
				esc = true
			elif ch == "\"":
				in_str = false
		else:
			if ch == "\"":
				in_str = true
			elif ch == "{":
				depth += 1
			elif ch == "}":
				depth -= 1
				if depth == 0:
					return payload.substr(start, i - start + 1)
		i += 1
	return ""


func _init() -> void:
	print("=== LIVE SEAM REGRESSION -- outbound bytes vs frozen file ===")
	var fh := FileAccess.open(SCHEMA_PATH, FileAccess.READ)
	if fh == null:
		print("  FAIL cannot open %s" % SCHEMA_PATH)
		quit(1)
		return
	var file_text := fh.get_as_text()
	fh.close()
	## TWO HASHES, and conflating them is its own trap. The file as stored ends
	## with a trailing newline; the bytes on the wire do not. The provenance
	## that matters is the WIRE hash -- that is the grammar the model saw.
	print("  file sha256 (as stored) %s" % _sha(file_text))
	print("  wire sha256 (as sent)   %s" % _sha(file_text.strip_edges()))

	var payload := _build_payload(file_text)
	var sent := _extract_schema(payload)
	ck("a schema object is present in the outbound body", not sent.is_empty())
	if sent.is_empty():
		quit(1)
		return

	## THE ASSERTION. Trailing whitespace in the file is not sent, so the
	## comparison is against the stripped file text -- the bytes, in order.
	var want := file_text.strip_edges()
	ck("outbound schema bytes are identical to the file", sent == want)
	ck("outbound schema hash equals the frozen wire hash",
		_sha(sent) == _sha(want))
	ck("the placeholder was substituted, not left in place",
		not payload.contains(PLACEHOLDER))
	ck("the body is still valid JSON after splicing",
		JSON.parse_string(payload) != null)

	## THE SABOTAGE. A round trip through Godot's JSON must be DETECTED, not
	## tolerated. This is the exact corruption that shipped once.
	var round_tripped := JSON.stringify(JSON.parse_string(file_text))
	var differs := round_tripped != want
	ck("a parse/stringify round trip changes the bytes (so it is detectable)",
		differs)
	ck("SABOTAGE BITES: round-tripped schema fails the hash assertion",
		_sha(round_tripped) != _sha(want))

	## And name the damage, so a future reader sees why order matters.
	var rt = JSON.parse_string(round_tripped)
	var first_prop := ""
	if typeof(rt) == TYPE_DICTIONARY:
		for b in (rt as Dictionary).get("anyOf", []):
			var props: Dictionary = (b as Dictionary).get("properties", {})
			if props.has("object"):
				var keys: Array = props.keys()
				first_prop = str(keys[0]) if not keys.is_empty() else ""
				break
	ck("round trip puts a field before the discriminator (got '%s')"
		% first_prop, first_prop != "" and first_prop != "operation")

	## The seam must still describe the vocabulary it claims to.
	var parsed = JSON.parse_string(file_text)
	var branches: Array = []
	if typeof(parsed) == TYPE_DICTIONARY:
		branches = (parsed as Dictionary).get("anyOf", [])
	ck("branch count equals the agent-choosable vocabulary (%d)"
		% OP.AGENT_CHOOSABLE.size(),
		branches.size() == OP.AGENT_CHOOSABLE.size())

	print("")
	if _fail == 0:
		print("LIVE SEAM OK -- what leaves the process is what is on disk")
		quit(0)
	else:
		print("LIVE SEAM REGRESSION FAILED: %d check(s)." % _fail)
		print("Do not ignite: the grammar the models see is not the frozen one.")
		quit(1)
