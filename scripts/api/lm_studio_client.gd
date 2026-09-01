extends Node
class_name LMStudioClient

var base_url: String = "http://127.0.0.1:1234/v1"
var request_timeout_sec: float = 20.0
const REQUEST_DEADLINE_BUFFER_SEC := 8.0
const LM_TIMEOUT_HTTP_CODE := 408
## Synthetic code for "the size law refused this model". Distinct from a
## network or model error so the UI can show MODEL_REJECTED, not MODEL_ERROR.
const MODEL_REJECTED_HTTP_CODE := 452

var _queue: Array = []
var _busy: bool = false
var _busy_since_msec: int = 0  # track how long we've been busy
var _active_timeout_sec: float = 20.0

func _ready() -> void:
	print("LM Studio client initialized: " + base_url)

func _process(_delta: float) -> void:
	# Safety net: if _busy has been true for way too long, force-reset
	if _busy and _busy_since_msec > 0:
		var stuck_sec := float(Time.get_ticks_msec() - _busy_since_msec) / 1000.0
		if stuck_sec > _active_timeout_sec + REQUEST_DEADLINE_BUFFER_SEC + 5.0:
			print("[LMClient] STUCK for %.0fs — force-resetting queue" % stuck_sec)
			_busy = false
			_busy_since_msec = 0
			_active_timeout_sec = request_timeout_sec
			# Drain any remaining tasks with failure callbacks
			while not _queue.is_empty():
				var stale = _queue.pop_front()
				if stale.has("callback") and stale.callback.is_valid():
					if stale.type == "chat":
						stale.callback.call(false, "", LM_TIMEOUT_HTTP_CODE)
					else:
						stale.callback.call(false, [])

func fetch_models(callback: Callable) -> void:
	_enqueue({
		"type": "models",
		"callback": callback,
	})

## Optional ModelPolicy. When set, NO request leaves this client for a model
## the policy refuses. Injected by Main so the client stays testable standalone.
var model_policy = null

func chat_completion(
	agent_name: String,
	model_id: String,
	messages: Array,
	callback: Callable,
	options: Dictionary = {}
) -> void:
	# THE GUARD. LM Studio just-in-time loads whatever model id it is given, so
	# refusing here is the difference between "we do not select 12B models" and
	# "a 12B model cannot be loaded by this program".
	if model_policy != null:
		var reason: String = model_policy.check(model_id)
		if reason != "":
			push_warning("[LMClient] BLOCKED %s: %s" % [agent_name, reason])
			_safe_call_chat(callback, false, "", MODEL_REJECTED_HTTP_CODE)
			return

	var body := {
		"model": model_id,
		"messages": messages,
		"temperature": options.get("temperature", 0.5),
		"max_tokens": options.get("max_tokens", 96),
		"stream": false,
		# Explicitly disable tool use — some models (Reverb, SmolLM3) try to
		# call tools instead of generating text, returning empty content with
		# tool_calls array. Setting tool_choice to "none" prevents this.
		"tool_choice": "none",
	}
	# Optional per-model sampling. Only sent when the roster supplied a value,
	# so a model with no recorded preference keeps LM Studio's own default.
	if options.has("top_p"):
		body["top_p"] = float(options["top_p"])
	if options.has("repeat_penalty"):
		body["repeat_penalty"] = float(options["repeat_penalty"])
	# Verified on this machine: LM Studio honours seeds. Same seed reproduces
	# byte-identical output at temperature 1.3; different seeds diverge; no
	# seed is non-deterministic. That makes a paired A/B a MATCHED comparison
	# rather than two independent samples.
	if options.has("seed"):
		body["seed"] = int(options["seed"])
	# Stop sequences — prevent models from writing other agents' turns
	var stop_seqs = options.get("stop", [])
	if not stop_seqs.is_empty():
		body["stop"] = stop_seqs
	_enqueue({
		"type": "chat",
		"agent_name": agent_name,
		"body": body,
		"callback": callback,
		"timeout_sec": maxf(float(options.get("timeout_sec", request_timeout_sec)), 1.0),
	})

func _enqueue(task: Dictionary) -> void:
	_queue.append(task)
	if not _busy:
		_process_queue()

func _process_queue() -> void:
	if _queue.is_empty():
		_busy = false
		_busy_since_msec = 0
		_active_timeout_sec = request_timeout_sec
		return
	_busy = true
	_busy_since_msec = Time.get_ticks_msec()
	var task = _queue.pop_front()
	match task.type:
		"models":
			_active_timeout_sec = request_timeout_sec
			_do_fetch_models(task.callback)
		"chat":
			_active_timeout_sec = maxf(float(task.get("timeout_sec", request_timeout_sec)), 1.0)
			_do_chat(task.agent_name, task.body, task.callback, _active_timeout_sec)

func _flatten_message_text(value) -> String:
	match typeof(value):
		TYPE_STRING:
			return value
		TYPE_ARRAY:
			var parts: Array[String] = []
			for item in value:
				if typeof(item) == TYPE_STRING:
					parts.append(item)
				elif typeof(item) == TYPE_DICTIONARY:
					var chunk_text = str(item.get("text", item.get("content", "")))
					if not chunk_text.is_empty():
						parts.append(chunk_text)
			return "".join(parts)
		_:
			return ""

const _MIN_CONTENT_CHARS := 4

# KILL-SWITCH: Never use reasoning_content. We only want the final answer.
func _extract_message_text(message: Dictionary, agent_name: String = "") -> String:
	var content_text := _flatten_message_text(message.get("content", "")).strip_edges()
	# Ignore reasoning_content entirely to prevent thinking leakage in the Arena
	return content_text

func _safe_call_chat(callback: Callable, success: bool, text: String, http_code: int) -> void:
	if callback.is_valid():
		callback.call(success, text, http_code)
	else:
		print("[LMClient] WARNING: chat callback was invalid — response lost")

func _safe_call_models(callback: Callable, success: bool, models: Array) -> void:
	if callback.is_valid():
		callback.call(success, models)
	else:
		print("[LMClient] WARNING: models callback was invalid — response lost")

func _finish_models(http: HTTPRequest, deadline_timer: Timer, callback: Callable, success: bool, models: Array) -> void:
	if is_instance_valid(deadline_timer):
		deadline_timer.stop()
		deadline_timer.queue_free()
	if is_instance_valid(http):
		http.queue_free()
	_process_queue()
	_safe_call_models(callback, success, models)

func _finish_chat(http: HTTPRequest, deadline_timer: Timer, callback: Callable, success: bool, text: String, http_code: int = 0) -> void:
	if is_instance_valid(deadline_timer):
		deadline_timer.stop()
		deadline_timer.queue_free()
	if is_instance_valid(http):
		http.queue_free()
	_process_queue()
	_safe_call_chat(callback, success, text, http_code)

func _do_fetch_models(callback: Callable) -> void:
	var http = HTTPRequest.new()
	add_child(http)
	http.timeout = request_timeout_sec
	http.accept_gzip = false  # Godot's gzip decompressor can fail on some LM Studio responses (result=13)
	var completed := [false]  # array so lambda captures by reference
	var deadline_timer := Timer.new()
	deadline_timer.one_shot = true
	deadline_timer.wait_time = request_timeout_sec + REQUEST_DEADLINE_BUFFER_SEC
	add_child(deadline_timer)
	deadline_timer.timeout.connect(func():
		if completed[0]:
			return
		completed[0] = true
		print("[LMClient] fetch_models timed out")
		if is_instance_valid(http):
			http.cancel_request()
		_finish_models(http, deadline_timer, callback, false, [])
	)
	deadline_timer.start()
	http.request_completed.connect(func(result, response_code, _headers, body):
		if completed[0]:
			return
		completed[0] = true
		var success = false
		var models = []
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json = JSON.parse_string(body.get_string_from_utf8())
			if json and json.has("data"):
				for m in json.data:
					models.append(m.id)
				success = true
		else:
			print("[LMClient] fetch_models failed: result=%d code=%d" % [result, response_code])
		_finish_models(http, deadline_timer, callback, success, models)
	)
	var err = http.request(base_url + "/models")
	if err != OK:
		if completed[0]:
			return
		completed[0] = true
		print("[LMClient] fetch_models request error: %d" % err)
		_finish_models(http, deadline_timer, callback, false, [])

func _do_chat(agent_name: String, body: Dictionary, callback: Callable, timeout_sec: float = -1.0) -> void:
	var effective_timeout_sec := maxf(timeout_sec, 1.0) if timeout_sec > 0.0 else request_timeout_sec
	var http = HTTPRequest.new()
	add_child(http)
	http.timeout = effective_timeout_sec
	http.accept_gzip = false  # Godot's gzip decompressor can fail on some LM Studio responses (result=13)
	var completed := [false]  # array so lambda captures by reference
	var deadline_timer := Timer.new()
	deadline_timer.one_shot = true
	deadline_timer.wait_time = effective_timeout_sec + REQUEST_DEADLINE_BUFFER_SEC
	add_child(deadline_timer)
	deadline_timer.timeout.connect(func():
		if completed[0]:
			return
		completed[0] = true
		print("[LMClient] %s timed out (%.0fs)" % [agent_name, effective_timeout_sec + REQUEST_DEADLINE_BUFFER_SEC])
		if is_instance_valid(http):
			http.cancel_request()
		_finish_chat(http, deadline_timer, callback, false, "", LM_TIMEOUT_HTTP_CODE)
	)
	deadline_timer.start()
	http.request_completed.connect(func(result, response_code, _headers, response_body):
		if completed[0]:
			return
		completed[0] = true
		var success = false
		var text = ""
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var raw = response_body.get_string_from_utf8()
			var json = JSON.parse_string(raw)
			if json and json.has("choices") and json.choices.size() > 0:
				var msg = json.choices[0].message
				text = _extract_message_text(msg, agent_name)
				if not text.is_empty():
					success = true
				elif msg.has("tool_calls") and msg.tool_calls.size() > 0:
					# Model tried tool calling instead of generating text.
					# Extract any text from tool call arguments as fallback.
					print("[LMClient] %s used tool_calls instead of text — tool_choice:none may not be supported by this model" % agent_name)
					var tc = msg.tool_calls[0]
					if tc.has("function") and tc.function.has("arguments"):
						var args_text = str(tc.function.arguments).strip_edges()
						if args_text.length() > 5:
							text = args_text
							success = true
				elif str(msg.get("reasoning_content", "")).strip_edges() != "":
					# Reasoning model: it answered, but put everything in
					# reasoning_content and left content empty. The kill-switch
					# above refuses reasoning_content on purpose (no thinking
					# leakage in the arena), so this model cannot be used here.
					# Name the cause instead of reporting a generic empty reply.
					print("[LMClient] %s is a REASONING-ONLY responder: content empty, reasoning_content %d chars. Not usable in a roster — pick a non-thinking model." % [agent_name, str(msg.get("reasoning_content", "")).length()])
				else:
					print("[LMClient] %s got 200 but empty assistant text: %s" % [agent_name, raw.substr(0, 300)])
			else:
				print("[LMClient] %s got 200 but bad body: %s" % [agent_name, raw.substr(0, 300)])
		else:
			var error_body = response_body.get_string_from_utf8().substr(0, 500)
			print("[LMClient] %s failed: result=%d code=%d body=%s" % [agent_name, result, response_code, error_body])
		_finish_chat(http, deadline_timer, callback, success, text, response_code)
	)
	var headers_array = ["Content-Type: application/json"]
	var err = http.request(
		base_url + "/chat/completions",
		headers_array,
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)
	if err != OK:
		if completed[0]:
			return
		completed[0] = true
		print("[LMClient] %s request error: %d" % [agent_name, err])
		_finish_chat(http, deadline_timer, callback, false, "", 0)
