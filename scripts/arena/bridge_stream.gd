extends RefCounted
class_name BridgeStream

## One slot's private streaming connection. Owns its socket, start to finish.
##
## WHY PER-SLOT. The old pattern shared a single HTTPRequest and called
## `cancel_request()` before each use. With three concurrent slots that is
## fatal: cancelling a wedged Danube request would also murder the in-flight
## LFM2.5 and Falcon requests. Independent cancellation is the whole point, so
## each slot gets its own HTTPClient and closing one touches nothing else.
##
## WHY HTTPClient RATHER THAN HTTPRequest. HTTPRequest delivers one completed
## body. Real time-to-first-token needs the body as it arrives, which means
## polling and `read_response_body_chunk()`.
##
## FOUR TIMEOUT CLASSES, because one giant timeout erases the distinction
## between failures that need different responses:
##
##   CONNECT_TIMEOUT      no connection or no response headers
##   TTFT_TIMEOUT         connected, but generation never begins
##   STREAM_IDLE_TIMEOUT  generation began, then the stream froze mid-way
##   TOTAL_TIMEOUT        absolute ceiling
##
## Those map onto pathologies already observed: a wedged model that never
## responds, a spilled model that responds 100x slowly, and a generation that
## starts and stalls. Recovery policy keys off the mechanical category rather
## than a guess about what happened.
##
## THE SEMANTIC FIREWALL. This class necessarily sees the prompt -- it has to
## send it. That does not give the SCHEDULER access. The bridge passes a
## payload here and a BridgeTicket.scheduling_view() to scheduling, and the two
## paths never meet.

const SSE := preload("res://scripts/arena/sse_parser.gd")

const IDLE := "IDLE"
const RESOLVING := "RESOLVING"
const CONNECTING := "CONNECTING"
const SENDING := "SENDING"
const STREAMING := "STREAMING"
const FINISHED := "FINISHED"

const OK_STATUS := "OK"
const CONNECT_TIMEOUT := "CONNECT_TIMEOUT"
const TTFT_TIMEOUT := "TTFT_TIMEOUT"
const STREAM_IDLE_TIMEOUT := "STREAM_IDLE_TIMEOUT"
const TOTAL_TIMEOUT := "TOTAL_TIMEOUT"
const HTTP_ERROR := "HTTP_ERROR"
const TRUNCATED := "TRUNCATED"
const CANCELLED := "CANCELLED"

var state: String = IDLE
var status: String = ""

## Timestamps, all ms. Zero means "did not happen".
var started_at_ms: int = 0
var connected_at_ms: int = 0
var first_event_at_ms: int = 0
var first_content_at_ms: int = 0
var completed_at_ms: int = 0
var last_data_at_ms: int = 0

var text: String = ""
var event_count: int = 0
var content_events: int = 0
var http_code: int = 0

## Timeout budget, ms. Supplied by policy.
var connect_timeout_ms: int = 10000
var ttft_timeout_ms: int = 30000
var idle_timeout_ms: int = 20000
var total_timeout_ms: int = 120000

var _client: HTTPClient
var _parser: SSEParser
var _host: String = ""
var _port: int = 80
var _use_ssl: bool = false
var _path: String = "/"
var _body: String = ""
var _requested: bool = false


## Split an endpoint like "http://127.0.0.1:1234/v1" into its parts.
static func split_url(url: String) -> Dictionary:
	var rest := url
	var ssl := false
	if rest.begins_with("https://"):
		ssl = true
		rest = rest.substr(8)
	elif rest.begins_with("http://"):
		rest = rest.substr(7)
	var slash := rest.find("/")
	var path := "/"
	if slash >= 0:
		path = rest.substr(slash)
		rest = rest.substr(0, slash)
	var port := 443 if ssl else 80
	var colon := rest.rfind(":")
	if colon >= 0:
		port = int(rest.substr(colon + 1))
		rest = rest.substr(0, colon)
	return {"host": rest, "port": port, "ssl": ssl, "path": path}


func begin(endpoint: String, route: String, body: Dictionary,
		now_ms: int) -> void:
	var u := split_url(endpoint)
	_host = str(u["host"])
	_port = int(u["port"])
	_use_ssl = bool(u["ssl"])
	_path = str(u["path"]) + route
	_body = JSON.stringify(body)
	_client = HTTPClient.new()
	_parser = SSE.new()
	started_at_ms = now_ms
	last_data_at_ms = now_ms
	_requested = false
	status = ""
	state = RESOLVING
	if _client.connect_to_host(_host, _port,
			TLSOptions.client() if _use_ssl else null) != OK:
		_finish(HTTP_ERROR, now_ms)
		return
	state = CONNECTING


## Drive the connection. Returns true once the stream has finished for any
## reason. Called every frame by the bridge; never blocks.
func poll(now_ms: int) -> bool:
	if state == FINISHED:
		return true
	if _check_timeouts(now_ms):
		return true
	_client.poll()
	match _client.get_status():
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING:
			return false
		HTTPClient.STATUS_CONNECTED:
			if not _requested:
				_send(now_ms)
			return false
		HTTPClient.STATUS_REQUESTING:
			return false
		HTTPClient.STATUS_BODY:
			_read_body(now_ms)
			return state == FINISHED
		HTTPClient.STATUS_DISCONNECTED:
			# Clean close. Anything still buffered is a truncated event.
			return _on_close(now_ms)
		_:
			_finish(HTTP_ERROR, now_ms)
			return true


func _send(now_ms: int) -> void:
	_requested = true
	connected_at_ms = now_ms
	state = SENDING
	var headers := [
		"Content-Type: application/json",
		"Accept: text/event-stream",
		"Connection: keep-alive",
	]
	if _client.request(HTTPClient.METHOD_POST, _path, headers, _body) != OK:
		_finish(HTTP_ERROR, now_ms)


func _read_body(now_ms: int) -> void:
	if http_code == 0:
		http_code = _client.get_response_code()
		if http_code != 200:
			_finish(HTTP_ERROR, now_ms)
			return
		state = STREAMING
	var chunk := _client.read_response_body_chunk()
	if chunk.is_empty():
		return
	last_data_at_ms = now_ms
	for ev in _parser.feed(chunk):
		_consume(ev, now_ms)
		if state == FINISHED:
			return


## One parsed SSE event. The distinction that matters: the first EVENT is not
## the first CONTENT, and only the latter is time-to-first-token.
func _consume(ev: Dictionary, now_ms: int) -> void:
	event_count += 1
	if first_event_at_ms == 0:
		first_event_at_ms = now_ms
	if bool(ev.get("done", false)):
		_finish(OK_STATUS, now_ms)
		return
	var c := str(ev.get("content", ""))
	if c == "":
		return
	if first_content_at_ms == 0:
		first_content_at_ms = now_ms
	content_events += 1
	text += c


func _on_close(now_ms: int) -> bool:
	if state == FINISHED:
		return true
	for ev in _parser.flush():
		_consume(ev, now_ms)
		if state == FINISHED:
			return true
	# A stream that ends without [DONE] is truncated, not successful. Saying
	# otherwise would let a half-generation be recorded as a healthy call.
	_finish(OK_STATUS if _parser.saw_done else TRUNCATED, now_ms)
	return true


## Which clock ran out. Order matters: the earliest applicable phase wins, so
## the reported class describes where the failure actually occurred.
func _check_timeouts(now_ms: int) -> bool:
	var elapsed := now_ms - started_at_ms
	if elapsed >= total_timeout_ms:
		_finish(TOTAL_TIMEOUT, now_ms)
		return true
	if connected_at_ms == 0:
		if elapsed >= connect_timeout_ms:
			_finish(CONNECT_TIMEOUT, now_ms)
			return true
		return false
	if first_content_at_ms == 0:
		if now_ms - connected_at_ms >= ttft_timeout_ms:
			_finish(TTFT_TIMEOUT, now_ms)
			return true
		return false
	if now_ms - last_data_at_ms >= idle_timeout_ms:
		_finish(STREAM_IDLE_TIMEOUT, now_ms)
		return true
	return false


func cancel(now_ms: int) -> void:
	if state != FINISHED:
		_finish(CANCELLED, now_ms)


func _finish(st: String, now_ms: int) -> void:
	status = st
	completed_at_ms = now_ms
	state = FINISHED
	if _client != null:
		_client.close()


func ok() -> bool:
	return status == OK_STATUS


## Which timeouts are wedge-like (nothing came back) versus degradation-like
## (output began). The recovery path keys off this rather than prose.
func failure_kind() -> String:
	match status:
		CONNECT_TIMEOUT, TTFT_TIMEOUT:
			return "WEDGE"
		STREAM_IDLE_TIMEOUT, TOTAL_TIMEOUT, TRUNCATED:
			return "STALL"
		HTTP_ERROR:
			return "ERROR"
		CANCELLED:
			return "CANCELLED"
		_:
			return ""


## Stream timings for the receipt. Derived once, here.
func timings() -> Dictionary:
	# started_at_ms is always set in begin(), so its presence is not in
	# question -- guarding on it being non-zero would treat a legitimate
	# zero timestamp as "never happened" and silently report -1.
	var ttft := -1
	if first_content_at_ms > 0:
		ttft = first_content_at_ms - started_at_ms
	var gen := -1
	if completed_at_ms > 0 and first_content_at_ms > 0:
		gen = completed_at_ms - first_content_at_ms
	var conn := -1
	if connected_at_ms > 0:
		conn = connected_at_ms - started_at_ms
	return {
		"connected_at_ms": connected_at_ms,
		"first_event_at_ms": first_event_at_ms,
		"first_content_at_ms": first_content_at_ms,
		"completed_at_ms": completed_at_ms,
		"connect_ms": conn,
		"ttft_ms": ttft,
		"generation_after_first_ms": gen,
		"total_ms": (completed_at_ms - started_at_ms
			if completed_at_ms > 0 else -1),
		"stream_event_count": event_count,
		"content_event_count": content_events,
		"status": status,
		"failure_kind": failure_kind(),
	}


func dispatch_base() -> int:
	return started_at_ms
