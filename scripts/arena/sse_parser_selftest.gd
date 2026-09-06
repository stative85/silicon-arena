extends SceneTree

## Can chunk boundaries break the SSE parser?
##
##   godot --headless --path . --script scripts/arena/sse_parser_selftest.gd
##
## This is boring plumbing, which is exactly why it gets its own test. A JSON
## object bisected between network packets, left unhandled, does not look like
## a parser bug later -- it looks like "Qwen is uniquely broken."
##
## The central case is the byte-boundary sweep: the same stream is replayed
## split at EVERY possible byte position, and every split must produce
## identical output. If any offset differs, some boundary is being handled as
## a message boundary.

const S := preload("res://scripts/arena/sse_parser.gd")

var _checks := 0
var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("   ok   %s" % name)
	else:
		_failures.append(name)
		print("   FAIL %s  %s" % [name, detail])


func _b(s: String) -> PackedByteArray:
	return s.to_utf8_buffer()


func _content_of(events: Array) -> String:
	var out := ""
	for e in events:
		out += str((e as Dictionary).get("content", ""))
	return out


func _run() -> void:
	print("=== SSE parser selftest ===\n")
	_basic()
	_boundaries()
	_utf8()
	_pathological()
	_content_vs_event()
	_sabotage()
	_report()


func _basic() -> void:
	print(" whole events")
	var p := S.new()
	var ev := p.feed(_b("data: {\"choices\":[{\"delta\":{\"content\":\"He\"}}]}\n\n"))
	_check("   one event per chunk", ev.size() == 1 and _content_of(ev) == "He",
		str(ev))

	var p2 := S.new()
	var two := p2.feed(_b(
		"data: {\"choices\":[{\"delta\":{\"content\":\"a\"}}]}\n\n"
		+ "data: {\"choices\":[{\"delta\":{\"content\":\"b\"}}]}\n\n"))
	_check("   two events in one chunk",
		two.size() == 2 and _content_of(two) == "ab", str(two))

	var p3 := S.new()
	var d := p3.feed(_b("data: [DONE]\n\n"))
	_check("   [DONE] is recognised",
		d.size() == 1 and bool(d[0]["done"]) and p3.saw_done)

	var p4 := S.new()
	p4.feed(_b("data: {\"choices\":[{\"delta\":{\"content\":\"x\"}}]}\n\n"))
	_check("   nothing pending after a complete event", not p4.has_pending())

	var p5 := S.new()
	var none := p5.feed(_b("data: {\"choices\":[{\"delta\":{\"content\":\"x\"}}]}"))
	_check("   an event without its blank line is withheld",
		none.is_empty() and p5.has_pending(),
		"emitting early is how a half-JSON gets parsed")

	# CRLF is legal and must not be mistaken for content.
	var p6 := S.new()
	var crlf := p6.feed(_b(
		"data: {\"choices\":[{\"delta\":{\"content\":\"c\"}}]}\r\n\r\n"))
	_check("   CRLF event separator", crlf.size() == 1
		and _content_of(crlf) == "c", str(crlf))


func _boundaries() -> void:
	print("\n the byte-boundary sweep")
	var stream := ("data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}\n\n"
		+ "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n"
		+ "data: {\"choices\":[{\"delta\":{\"content\":\" world\"}}]}\n\n"
		+ "data: [DONE]\n\n")
	var bytes := _b(stream)

	var whole := S.new()
	var expect_events: Array = whole.feed(bytes)
	var expect_text := _content_of(expect_events)
	_check("   baseline parses whole", expect_text == "Hello world"
		and expect_events.size() == 4, expect_text)

	var bad := []
	for cut in range(1, bytes.size()):
		var p := S.new()
		var got: Array = []
		got.append_array(p.feed(bytes.slice(0, cut)))
		got.append_array(p.feed(bytes.slice(cut)))
		if _content_of(got) != expect_text or got.size() != expect_events.size():
			bad.append(cut)
	_check("   split at every one of %d byte offsets is identical"
			% (bytes.size() - 1), bad.is_empty(),
		"differing offsets: %s" % str(bad.slice(0, 8)))

	# Byte-at-a-time is the most adversarial arrival pattern there is.
	var drip := S.new()
	var dripped: Array = []
	for i in bytes.size():
		dripped.append_array(drip.feed(bytes.slice(i, i + 1)))
	_check("   one byte per chunk still yields the same content",
		_content_of(dripped) == expect_text
			and dripped.size() == expect_events.size(),
		_content_of(dripped))

	# [DONE] split across chunks specifically.
	var tail := _b("data: [DO")
	var rest := _b("NE]\n\n")
	var p2 := S.new()
	var a := p2.feed(tail)
	var b := p2.feed(rest)
	_check("   [DONE] split across chunks",
		a.is_empty() and b.size() == 1 and bool(b[0]["done"]))


func _utf8() -> void:
	print("\n multi-byte characters split mid-character")
	var payload := "data: {\"choices\":[{\"delta\":{\"content\":\"中文é\"}}]}\n\n"
	var bytes := _b(payload)
	var whole := S.new()
	var want := _content_of(whole.feed(bytes))
	_check("   baseline decodes multibyte", want == "中文é", want)

	var bad := []
	for cut in range(1, bytes.size()):
		var p := S.new()
		var got: Array = []
		got.append_array(p.feed(bytes.slice(0, cut)))
		got.append_array(p.feed(bytes.slice(cut)))
		if _content_of(got) != want:
			bad.append(cut)
	_check("   split at every byte, including mid-character, is identical",
		bad.is_empty(),
		"buffering text instead of bytes corrupts these: %s"
			% str(bad.slice(0, 8)))


func _pathological() -> void:
	print("\n frames that are not content")
	var p := S.new()
	var role := p.feed(_b(
		"data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}\n\n"))
	_check("   role-only delta yields empty content",
		role.size() == 1 and str(role[0]["content"]) == "",
		"this frame must never be mistaken for the first token")

	var p2 := S.new()
	var empty := p2.feed(_b("data: {\"choices\":[{\"delta\":{\"content\":\"\"}}]}\n\n"))
	_check("   empty content string is an event with no content",
		empty.size() == 1 and str(empty[0]["content"]) == "")

	var p3 := S.new()
	var blank := p3.feed(_b("data: {\"choices\":[{\"delta\":{}}]}\n\n"))
	_check("   blank delta is handled", blank.size() == 1
		and str(blank[0]["content"]) == "")

	var p4 := S.new()
	var mal := p4.feed(_b("data: {not json at all\n\n"))
	_check("   malformed JSON is flagged, not fatal",
		mal.size() == 1 and bool(mal[0]["malformed"]) and p4.malformed_seen == 1)

	var p5 := S.new()
	var after := p5.feed(_b("data: {broken\n\n"
		+ "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\n"))
	_check("   a bad frame does not kill the stream",
		_content_of(after) == "ok",
		"one malformed event must not end a live generation")

	var p6 := S.new()
	var cmt := p6.feed(_b(": keepalive\n\n"))
	_check("   a comment frame carries no content",
		cmt.size() == 1 and str(cmt[0]["content"]) == ""
			and bool(cmt[0]["comment"]))

	var p7 := S.new()
	var unknown := p7.feed(_b("data: {\"unexpected\":true}\n\n"))
	_check("   an unfamiliar shape yields empty content, not an error",
		unknown.size() == 1 and str(unknown[0]["content"]) == "")

	# Connection closes before [DONE]: the tail must be recoverable.
	var p8 := S.new()
	p8.feed(_b("data: {\"choices\":[{\"delta\":{\"content\":\"tail\"}}]}"))
	_check("   truncated stream leaves bytes pending", p8.has_pending())
	var flushed := p8.flush()
	_check("   flush recovers the trailing event",
		flushed.size() == 1 and _content_of(flushed) == "tail")
	_check("   and no [DONE] was seen", not p8.saw_done,
		"the caller must be able to tell a truncated stream from a clean one")

	var p9 := S.new()
	_check("   flush on an empty buffer yields nothing", p9.flush().is_empty())


func _content_vs_event() -> void:
	print("\n first event is NOT first content")
	var p := S.new()
	var evs := p.feed(_b(
		"data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}\n\n"
		+ ": keepalive\n\n"
		+ "data: {\"choices\":[{\"delta\":{\"content\":\"\"}}]}\n\n"
		+ "data: {\"choices\":[{\"delta\":{\"content\":\"first\"}}]}\n\n"))
	var first_event := -1
	var first_content := -1
	for i in evs.size():
		if first_event < 0:
			first_event = i
		if first_content < 0 and str(evs[i]["content"]) != "":
			first_content = i
	_check("   four events arrive", evs.size() == 4, str(evs.size()))
	_check("   first event is index 0", first_event == 0)
	_check("   first CONTENT is index 3", first_content == 3,
		"TTFT measured from the first event would understate prefill")


func _sabotage() -> void:
	print("\n sabotage: prove the tests can go red")
	# If the parser emitted on every chunk instead of on event boundaries, a
	# bisected JSON object would surface. Simulate that failure directly.
	var half := "data: {\"choices\":[{\"delta\":{\"con"
	var naive = JSON.parse_string(half.substr(5))
	_check("   SABOTAGE APPLIED: a bisected frame is not valid JSON",
		naive == null,
		"if this parsed, the sabotage is not exercising anything")

	var p := S.new()
	var got := p.feed(_b(half))
	_check("   the parser withholds it instead of parsing it",
		got.is_empty() and p.malformed_seen == 0,
		"emitting per-chunk would have produced a malformed event here")

	# And prove the boundary logic is load-bearing: a stream with no blank
	# line must produce nothing at all, however long it gets.
	var p2 := S.new()
	var long_no_break := "data: " + "x".repeat(5000)
	_check("   5000 bytes without a separator yields no events",
		p2.feed(_b(long_no_break)).is_empty() and p2.pending_bytes() > 5000)


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("SSE PARSER OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
