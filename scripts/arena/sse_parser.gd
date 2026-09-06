extends RefCounted
class_name SSEParser

## Incremental Server-Sent Events parser. Chunk boundaries are hostile.
##
## THE ASSUMPTION THAT BREAKS EVERYTHING. A TCP read is not a message. One
## call to `read_response_body_chunk()` may hand you half an event, four
## events, or a JSON object bisected mid-token -- and, worst of all, a
## multi-byte UTF-8 character split across two packets.
##
## So this buffers BYTES, never text. Decoding a partial chunk to String would
## corrupt any split multi-byte character before parsing ever begins, and the
## corruption would surface later as one model mysteriously emitting garbage.
## Bytes accumulate; a complete event is decoded exactly once, whole.
##
## THE OTHER TRAP: the first SSE event is not the first token. A server may
## open with a role-only delta:
##
##   data: {"choices":[{"delta":{"role":"assistant"}}]}
##
## Treating that as time-to-first-token would understate TTFT by however long
## the real prefill takes, and TTFT is the bridge's authoritative health
## signal. So each event reports whether it carried non-empty CONTENT, and the
## caller timestamps `first_event` and `first_content` separately.
##
## This parser never raises. A malformed event is reported as malformed and the
## stream continues -- one bad frame must not kill a live generation.

## Accumulated bytes not yet forming a complete event.
var _buf: PackedByteArray = PackedByteArray()

## Totals across the life of the stream.
var events_seen: int = 0
var malformed_seen: int = 0
var saw_done: bool = false

const LF := 0x0A
const CR := 0x0D


## Feed raw bytes. Returns the events that completed with this chunk, in
## order. An incomplete trailing event stays buffered for the next call.
func feed(chunk: PackedByteArray) -> Array:
	if not chunk.is_empty():
		_buf.append_array(chunk)
	var out: Array = []
	while true:
		var cut := _find_event_end()
		if cut.is_empty():
			break
		var body := _buf.slice(0, int(cut[0]))
		_buf = _buf.slice(int(cut[1]))
		var ev := _parse_event(body)
		if not ev.is_empty():
			out.append(ev)
	return out


## Anything still buffered when the connection closes. A well-behaved stream
## ends with [DONE] and an empty buffer; a truncated one does not, and the
## caller needs to know rather than silently losing the tail.
func flush() -> Array:
	if _buf.is_empty():
		return []
	var body := _buf
	_buf = PackedByteArray()
	var ev := _parse_event(body)
	return [] if ev.is_empty() else [ev]


func has_pending() -> bool:
	return not _buf.is_empty()


func pending_bytes() -> int:
	return _buf.size()


## Locate the blank line ending the first event. Handles LF LF and CRLF CRLF,
## because a server is free to use either and mixing them is legal.
## Returns [body_end_index, next_start_index] or [] if incomplete.
func _find_event_end() -> Array:
	var n := _buf.size()
	var i := 0
	while i < n:
		if _buf[i] == LF:
			# "\n\n"
			if i + 1 < n and _buf[i + 1] == LF:
				return [i, i + 2]
			# "\n\r\n"
			if i + 2 < n and _buf[i + 1] == CR and _buf[i + 2] == LF:
				return [i, i + 3]
		i += 1
	return []


## Decode one complete event. Only called on whole events, so a split
## multi-byte character cannot reach here.
func _parse_event(body: PackedByteArray) -> Dictionary:
	var text := body.get_string_from_utf8()
	if text.strip_edges() == "":
		return {}
	events_seen += 1
	var ev := {"data": "", "done": false, "json": null, "content": "",
		"malformed": false, "comment": false}
	var payloads: Array[String] = []
	for raw_line in text.split("\n"):
		var line := str(raw_line)
		if line.ends_with("\r"):
			line = line.substr(0, line.length() - 1)
		if line == "":
			continue
		if line.begins_with(":"):
			ev["comment"] = true
			continue
		if not line.begins_with("data:"):
			continue  # event:/id:/retry: are not used here
		var payload := line.substr(5)
		if payload.begins_with(" "):
			payload = payload.substr(1)
		payloads.append(payload)
	if payloads.is_empty():
		# A comment-only or field-only frame is a real event with no data.
		return ev
	# Multiple data: lines in one event concatenate with newlines, per spec.
	ev["data"] = "\n".join(payloads)
	if str(ev["data"]) == "[DONE]":
		ev["done"] = true
		saw_done = true
		return ev
	# JSON.parse_string() pushes an engine error on bad input. A malformed
	# frame is EXPECTED here -- servers emit keepalives and truncated writes --
	# and a stream of engine errors during normal operation would drown the
	# real ones. An instance parse returns a code instead of shouting.
	var j := JSON.new()
	if j.parse(str(ev["data"])) != OK:
		ev["malformed"] = true
		malformed_seen += 1
		return ev
	var parsed = j.data
	ev["json"] = parsed
	ev["content"] = extract_content(parsed)
	return ev


## Pull the output delta out of an OpenAI-style chunk. Returns "" when the
## event carries no content -- a role-only opener, a finish_reason frame, or
## anything unexpected. Never raises on an unfamiliar shape.
static func extract_content(parsed) -> String:
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var choices = (parsed as Dictionary).get("choices", null)
	if typeof(choices) != TYPE_ARRAY or (choices as Array).is_empty():
		return ""
	var first = (choices as Array)[0]
	if typeof(first) != TYPE_DICTIONARY:
		return ""
	var delta = (first as Dictionary).get("delta", null)
	if typeof(delta) == TYPE_DICTIONARY:
		var c = (delta as Dictionary).get("content", null)
		if typeof(c) == TYPE_STRING:
			return str(c)
		return ""
	# Some servers emit a non-streaming-shaped final frame.
	var msg = (first as Dictionary).get("message", null)
	if typeof(msg) == TYPE_DICTIONARY:
		var mc = (msg as Dictionary).get("content", null)
		if typeof(mc) == TYPE_STRING:
			return str(mc)
	return ""
