extends Node
class_name InferenceBridge

## Scarce machinery, scheduled. Not a game master.
##
##   GODOT AGENTS
##        | submit(request)
##        v
##   INFERENCE BRIDGE
##        |-- queue / aging
##        |-- max_active 2-3
##        |-- hot-set manager
##        |-- residency monitor
##        |-- performance health
##        |-- hysteretic swap policy
##        |-- provenance receipts
##        v
##   LM STUDIO (explicit residency)
##
## WHAT THIS DOES NOT DO. It never decides when an agent needs to think. The
## agent decides that and submits. The bridge decides only WHEN, and with what
## currently available compute, that request is serviced. The moment a
## scheduler starts deciding whose thought matters, the substrate has become an
## author -- so the scheduler cannot even see the request's contents
## (BridgeTicket enforces this structurally).
##
## ASYNCHRONOUS BY CONSTRUCTION. `submit()` returns a request_id immediately.
## The arena keeps simulating. No global `await brain()` freezes the world
## because one model decided today was a good day to become a geological
## formation.
##
## PIT A IS EXEMPT. This is arena infrastructure. It is not applied to any
## finished experiment, and PIT A's runner keeps its own residency.

signal completed(request_id: String, ok: bool, text: String, receipt: Dictionary)
signal model_state_changed(model_id: String, from: String, to: String, reason: String)
signal recovery(model_id: String, action: String, ok: bool)

const P := preload("res://scripts/arena/bridge_policy.gd")
const T := preload("res://scripts/arena/bridge_ticket.gd")
const M := preload("res://scripts/arena/bridge_model.gd")
const R := preload("res://scripts/arena/bridge_receipt.gd")
const ST := preload("res://scripts/arena/bridge_stream.gd")

var policy: BridgePolicy
var models: Dictionary = {}          ## model_id -> BridgeModel
var queue: Array[BridgeTicket] = []
var receipts: Array = []

var _slots: Array = []               ## HTTPRequest nodes, one per burst slot
var _busy: Dictionary = {}           ## slot index -> request_id
var _seq: int = 0
var _started: bool = false
var _last_resident: Array = []
var _inflight: Dictionary = {}   ## request_id -> live receipt

## Injected so the self-test can drive the bridge without LM Studio. Must
## return {ok, text, tokens, ttft_ms} and is the ONLY place payload is read.
var transport: Callable = Callable()


func _ready() -> void:
	if policy == null:
		policy = BridgePolicy.new()
	var errs := policy.validate()
	if not errs.is_empty():
		push_error("bridge policy invalid: " + str(errs))
		return
	for mid in policy.known_models():
		models[mid] = M.make(mid)
	for mid in policy.hot_set:
		(models[mid] as BridgeModel).set_state(
			M.PARKED, "configured hot, not yet loaded", _now())
	_make_slots()
	_started = true


func _now() -> int:
	return Time.get_ticks_msec()


func _make_slots() -> void:
	# Each slot owns its own connection. Cancelling a wedged Danube request
	# must never murder the in-flight LFM and Falcon requests -- that shared
	# cancellation is exactly what this bridge exists to escape.
	for i in policy.max_active_burst:
		_slots.append(null)


func _new_stream() -> BridgeStream:
	var st := ST.new()
	st.connect_timeout_ms = policy.connect_timeout_ms
	st.ttft_timeout_ms = policy.ttft_timeout_ms
	st.idle_timeout_ms = policy.idle_timeout_ms
	st.total_timeout_ms = policy.total_timeout_ms
	return st


# --------------------------------------------------------------- submission

## Returns a request_id immediately. Never blocks the caller.
func submit(agent_id: String, model_id: String, payload: Dictionary,
		compute_class: String = T.CLASS_NORMAL,
		latency_class: String = T.LATENCY_INTERACTIVE) -> String:
	_seq += 1
	var rid := "req_%06d" % _seq
	if not models.has(model_id):
		# Unknown model is a resource fact, not a judgement. Fail immediately
		# and visibly rather than queueing something undeliverable.
		var t0 := T.make(rid, agent_id, model_id, payload, compute_class,
			latency_class)
		var rec := R.seal(R.make(t0), R.STATUS_REJECTED)
		rec["health_verdict"] = "UNKNOWN_MODEL"
		receipts.append(rec)
		completed.emit(rid, false, "", rec)
		return rid
	var t := T.make(rid, agent_id, model_id, payload, compute_class,
		latency_class)
	queue.append(t)
	var bm: BridgeModel = models[model_id]
	if not bm.is_dispatchable():
		bm.note_demand(_now(), policy.promote_demand_window_ms)
	_pump()
	return rid


# ---------------------------------------------------------------- scheduling

func active_count() -> int:
	return _busy.size()


## Burst is allowed only when the queue warrants it and nothing is unhealthy.
## Bursting into a degraded pool is how a co-tenant gets wedged -- both wedges
## observed in the benchmark occurred in concurrent cases containing the
## spilled model.
func max_active() -> int:
	if queue.size() < policy.burst_queue_depth:
		return policy.max_active_normal
	for mid in models:
		var bm: BridgeModel = models[mid]
		if bm.state == M.DEGRADED or bm.state == M.WEDGED \
				or bm.state == M.RECOVERING:
			return policy.max_active_normal
	return policy.max_active_burst


## Choose the next dispatchable ticket. Sees ONLY the scheduling view.
##
## Ordering: interactive before background, then oldest first. Age is a
## resource fact -- a request that has waited longer has consumed more of the
## agent's turn -- not a statement about importance.
func _select() -> int:
	var now := _now()
	var best := -1
	var best_key := []
	for i in queue.size():
		var v := queue[i].scheduling_view()
		var bm: BridgeModel = models.get(v["model_id"])
		if bm == null or not bm.is_dispatchable():
			continue
		var interactive := 0 if v["latency_class"] == T.LATENCY_INTERACTIVE else 1
		var age := now - int(v["submitted_at_ms"])
		var key := [interactive, -age]
		if best == -1 or _key_less(key, best_key):
			best = i
			best_key = key
	return best


func _key_less(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


func _free_slot() -> int:
	for i in _slots.size():
		if not _busy.values().has(i):
			return i
	return -1


func _pump() -> void:
	if not _started:
		return
	while active_count() < max_active():
		var idx := _select()
		if idx < 0:
			break
		var slot := _free_slot()
		if slot < 0:
			break
		var ticket: BridgeTicket = queue[idx]
		queue.remove_at(idx)
		_dispatch(ticket, slot)
	_consider_swap()


# ----------------------------------------------------------------- dispatch

func _dispatch(ticket: BridgeTicket, slot: int) -> void:
	var bm: BridgeModel = models[ticket.model_id]
	var rec := R.make(ticket)
	rec["dispatched_at_ms"] = _now()
	rec["model_state_before"] = bm.state
	rec["resident_set"] = _last_resident.duplicate()
	# How many requests were already in flight when this one was dispatched.
	# Recorded rather than assumed: a driver believing it created a two-way
	# load, and a bridge that actually dispatched serially, would otherwise
	# produce a "contended" distribution containing uncontended samples.
	rec["active_at_dispatch"] = _busy.size() + 1
	_busy[ticket.request_id] = slot
	# active_at_dispatch alone understates contention: the FIRST request of a
	# concurrent pair is always dispatched alone, then overlapped for most of
	# its life. max_active_during records the peak concurrency each in-flight
	# request actually experienced, which is what a contention distribution
	# needs.
	_inflight[ticket.request_id] = rec
	var peak := _busy.size()
	for r in _inflight.values():
		r["max_active_during"] = maxi(int(r.get("max_active_during", 0)), peak)
	bm.in_flight += 1
	_run(ticket, slot, rec)


func _run(ticket: BridgeTicket, slot: int, rec: Dictionary) -> void:
	var bm: BridgeModel = models[ticket.model_id]
	var timings: Dictionary = {}
	var ok := false
	var text := ""
	var tokens := 0
	var status := R.STATUS_HTTP_ERROR
	var kind := ""

	if transport.is_valid():
		# Injected transport, used by the offline self-test. It reports the
		# same shape the stream does so both paths seal identically.
		var res: Dictionary = await transport.call(ticket.model_id,
			ticket.payload())
		ok = bool(res.get("ok", false))
		text = str(res.get("text", ""))
		tokens = int(res.get("tokens", 0))
		status = R.STATUS_OK if ok else str(res.get("status", status))
		timings = {
			"ttft_ms": int(res.get("ttft_ms", -1)),
			"connect_ms": int(res.get("connect_ms", -1)),
			"generation_after_first_ms": int(res.get("gen_ms", -1)),
			"total_ms": int(res.get("total_ms", -1)),
			"stream_event_count": int(res.get("events", 0)),
			"content_event_count": int(res.get("content_events", 0)),
			"failure_kind": str(res.get("failure_kind", "")),
		}
	else:
		var st := await _stream_call(ticket, slot)
		ok = st.ok()
		text = st.text
		# Tokens are not reported by the streaming API, so content events are
		# used as the token proxy and NAMED as an estimate rather than passed
		# off as a count.
		tokens = st.content_events
		status = R.STATUS_OK if ok else st.status
		timings = st.timings()
		kind = st.failure_kind()

	rec["finished_at_ms"] = _now()
	rec["generated_tokens"] = tokens
	for k in timings:
		rec[k] = timings[k]
	var sealed := R.seal_stream(rec, status)

	bm.in_flight = maxi(bm.in_flight - 1, 0)
	_busy.erase(ticket.request_id)
	_inflight.erase(ticket.request_id)

	# Health is judged from measured first-CONTENT TTFT, never from whether the
	# call returned. A degraded model returns successfully every time.
	var verdict := M.classify(int(sealed["ttft_ms"]),
		float(sealed["decode_estimate"]), int(sealed["generated_tokens"]),
		policy)
	sealed["health_verdict"] = str(verdict["verdict"])

	if kind == "WEDGE" or status == ST.CONNECT_TIMEOUT 			or status == ST.TTFT_TIMEOUT:
		# Connected but never generated, or never connected at all.
		_transition(bm, M.WEDGED, "timeout class: " + status)
	elif kind == "STALL":
		# Generation began then froze. Distinct pathology, distinct label.
		_transition(bm, M.DEGRADED, "timeout class: " + status)
	elif bool(verdict["hard_degraded"]):
		bm.strikes += 1
		if bm.strikes >= policy.degraded_strikes:
			_transition(bm, M.DEGRADED, "TTFT breach x%d" % bm.strikes)
	elif bool(verdict["supporting"]):
		pass  # Supporting evidence alone never condemns a model.
	else:
		bm.strikes = 0

	sealed["model_state_after"] = bm.state
	receipts.append(sealed)
	completed.emit(ticket.request_id, ok, text, sealed)

	if bm.state == M.WEDGED or bm.state == M.DEGRADED:
		await _recover(bm)
	_pump()


## Stream on this slot's own connection, polled to completion. Returns the
## stream object so the caller can read real timings rather than an estimate.
func _stream_call(ticket: BridgeTicket, slot: int) -> BridgeStream:
	var st := _new_stream()
	_slots[slot] = st
	var body := ticket.payload()
	body["model"] = ticket.model_id
	body["stream"] = true
	st.begin(policy.endpoint, "/chat/completions", body, _now())
	while true:
		if st.poll(_now()):
			break
		await get_tree().process_frame
	_slots[slot] = null
	return st


func _transition(bm: BridgeModel, next: String, reason: String) -> void:
	var from := bm.state
	bm.set_state(next, reason, _now())
	if from != bm.state:
		model_state_changed.emit(bm.model_id, from, bm.state, reason)


# ----------------------------------------------------------------- recovery

## Explicit, never silent. A wedge is unload/reload. A degraded model is
## reloaded rather than tolerated -- waiting 40 seconds for a technically
## successful call is the documented failure this exists to prevent.
func _recover(bm: BridgeModel) -> void:
	if bm.in_flight > 0:
		return
	var action := "reload"
	_transition(bm, M.RECOVERING, "recovery: " + action)
	recovery.emit(bm.model_id, action, false)
	var ok := await _reload(bm.model_id)
	bm.strikes = 0
	bm.last_swap_ms = _now()
	bm.loaded_at_ms = _now() if ok else 0
	_transition(bm, M.HOT if ok else M.PARKED,
		"recovery %s" % ("succeeded" if ok else "failed"))
	recovery.emit(bm.model_id, action, ok)


## Overridden by the self-test. Real implementation shells out to `lms`.
func _reload(model_id: String) -> bool:
	var out: Array = []
	OS.execute("lms", ["unload", model_id], out, true)
	out = []
	var code := OS.execute("lms", ["load", model_id,
		"--context-length", str(policy.context_length),
		"--gpu", "max", "-y"], out, true)
	# lms unload --all is known to exit 1 on success, so the exit code is not
	# trusted as the signal; residency is queried instead.
	await get_tree().process_frame
	return code == 0 or (await refresh_residency()).has(model_id)


# ---------------------------------------------------------------- residency

## Query, never assume. Pool composition is observed state.
func refresh_residency() -> Array:
	var http := HTTPRequest.new()
	add_child(http)
	var got: Array = []
	if http.request(policy.models_endpoint) == OK:
		var res: Array = await http.request_completed
		if int(res[1]) == 200:
			var parsed = JSON.parse_string(
				(res[3] as PackedByteArray).get_string_from_utf8())
			if typeof(parsed) == TYPE_DICTIONARY:
				for entry in parsed.get("data", []):
					if str((entry as Dictionary).get("state", "")) != "not-loaded":
						got.append(str((entry as Dictionary).get("id", "")))
	http.queue_free()
	_last_resident = got
	# A hot model missing from the resident set was evicted, which residency
	# CAN see -- unlike a wedge or a degradation.
	for mid in policy.hot_set:
		var bm: BridgeModel = models.get(mid)
		if bm == null:
			continue
		if not got.has(mid) and bm.state == M.HOT:
			_transition(bm, M.EVICTED, "missing from resident set")
	return got


# --------------------------------------------------------------------- swap

## Hysteretic. Promotion needs sustained demand; a freshly loaded model stays
## put; and no model swaps twice inside the cooldown. Without all three this
## becomes JIT loading with extra paperwork.
func _consider_swap() -> void:
	var now := _now()
	var want := ""
	for mid in policy.parked_set:
		var bm: BridgeModel = models.get(mid)
		if bm == null or bm.is_dispatchable():
			continue
		var depth := 0
		var oldest := 0
		for t in queue:
			if t.model_id == mid:
				depth += 1
				oldest = maxi(oldest, t.age_ms(now))
		if bm.may_promote(depth, oldest, now, policy):
			want = mid
			break
	if want == "":
		return
	var victim := _demotable(now)
	if victim == "":
		return
	swap(victim, want)


func _demotable(now_ms: int) -> String:
	var best := ""
	var best_idle := -1
	for mid in policy.hot_set:
		var bm: BridgeModel = models.get(mid)
		if bm == null or not bm.may_demote(now_ms, policy):
			continue
		var pending := 0
		for t in queue:
			if t.model_id == mid:
				pending += 1
		if pending > 0:
			continue
		var idle := now_ms - bm.loaded_at_ms
		if idle > best_idle:
			best_idle = idle
			best = mid
	return best


## Promotion demotes something by explicit policy, never by allocator accident.
## That accident is precisely how qwen ended up executing on the CPU.
func swap(out_id: String, in_id: String) -> void:
	var now := _now()
	var a: BridgeModel = models.get(out_id)
	var b: BridgeModel = models.get(in_id)
	if a == null or b == null:
		return
	policy.hot_set.erase(out_id)
	if not policy.parked_set.has(out_id):
		policy.parked_set.append(out_id)
	policy.parked_set.erase(in_id)
	if not policy.hot_set.has(in_id):
		policy.hot_set.append(in_id)
	a.last_swap_ms = now
	b.last_swap_ms = now
	a.loaded_at_ms = 0
	_transition(a, M.PARKED, "demoted for " + in_id)
	_transition(b, M.LOADING, "promoted over " + out_id)


# ------------------------------------------------------------------ reports

func stats() -> Dictionary:
	var by_state := {}
	for mid in models:
		var s: String = (models[mid] as BridgeModel).state
		by_state[s] = int(by_state.get(s, 0)) + 1
	return {
		"queued": queue.size(),
		"active": active_count(),
		"max_active": max_active(),
		"receipts": receipts.size(),
		"hot_set": policy.hot_set.duplicate(),
		"by_state": by_state,
	}
