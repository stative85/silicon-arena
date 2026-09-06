extends SceneTree

## Does the bridge obey its own policy?
##
##   godot --headless --path . --script scripts/arena/bridge_selftest.gd
##
## Runs entirely offline through an injected transport, so it is part of
## verify.cmd and never needs LM Studio.
##
## Every sabotage below ASSERTS THAT THE SABOTAGE APPLIED before checking the
## consequence. Three edits in this project once silently did nothing and
## reported green, so a test that cannot prove it changed something is not a
## test.

const P := preload("res://scripts/arena/bridge_policy.gd")
const T := preload("res://scripts/arena/bridge_ticket.gd")
const M := preload("res://scripts/arena/bridge_model.gd")
const R := preload("res://scripts/arena/bridge_receipt.gd")
const B := preload("res://scripts/arena/inference_bridge.gd")

var _checks := 0
var _failures: Array[String] = []

## Scripted transport behaviour, per model.
var _behaviour := {}
var _calls := 0


func _init() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("   ok   %s" % name)
	else:
		_failures.append(name)
		print("   FAIL %s  %s" % [name, detail])


func _transport(model_id: String, _payload: Dictionary) -> Dictionary:
	_calls += 1
	var b: Dictionary = _behaviour.get(model_id, {})
	var ttft := int(b.get("ttft_ms", 60))
	var tokens := int(b.get("tokens", 64))
	var ok := bool(b.get("ok", true))
	await get_root().get_tree().process_frame
	var now := Time.get_ticks_msec()
	if not ok:
		return {"ok": false, "status": str(b.get("status", R.STATUS_TIMEOUT))}
	# first_token_at_ms is expressed as an offset the receipt will difference
	# against dispatch; the bridge seals it into ttft_ms.
	return {"ok": true, "text": "x", "tokens": tokens,
		"first_token_at_ms": now + ttft}


func _make_bridge() -> InferenceBridge:
	var pol := BridgePolicy.new()
	pol.min_residency_ms = 0
	pol.swap_cooldown_ms = 0
	var br := InferenceBridge.new()
	br.policy = pol
	br.transport = _transport
	get_root().add_child(br)
	return br


func _run() -> void:
	print("=== inference bridge selftest ===\n")
	await _policy()
	await _locality()
	await _health()
	await _concurrency()
	await _hysteresis()
	await _receipts()
	await _states()
	_report()


func _policy() -> void:
	print(" policy is validated, not assumed")
	var pol := BridgePolicy.new()
	_check("   default policy validates", pol.validate().is_empty(),
		str(pol.validate()))

	var bad := BridgePolicy.new()
	bad.hot_set = []
	_check("   empty hot_set is rejected", not bad.validate().is_empty())

	var bad2 := BridgePolicy.new()
	bad2.max_active_burst = 1
	bad2.max_active_normal = 2
	_check("   burst < normal is rejected", not bad2.validate().is_empty())

	var bad3 := BridgePolicy.new()
	bad3.hot_set = ["rwkv7-1.5b-g1"] as Array[String]
	bad3.parked_set = ["rwkv7-1.5b-g1"] as Array[String]
	_check("   a model in both sets is rejected", not bad3.validate().is_empty())

	# The hot set is configuration. Swapping RWKV in must be a legal policy.
	var alt := BridgePolicy.new()
	alt.hot_set = ["rwkv7-1.5b-g1", "liquidai/lfm2.5-1.2b-instruct",
		"qwen3.5-2b"] as Array[String]
	alt.parked_set = ["h2o-danube2-1.8b-chat",
		"falcon-h1-1.5b-instruct"] as Array[String]
	_check("   an RWKV-hot policy is accepted", alt.validate().is_empty(),
		str(alt.validate()))

	var pol2 := BridgePolicy.new()
	_check("   budget = total - reserve",
		pol2.gpu_budget_mib() == pol2.total_vram_mib - pol2.desktop_reserve_mib)
	# 596 baseline + the five marginal costs = 7,688 > 6,103 budget.
	_check("   all five models do NOT fit the budget",
		not pol2.fits(pol2.known_models(), 596))
	_check("   the default hot three do fit",
		pol2.fits(pol2.hot_set, 596))


func _locality() -> void:
	print("\n the scheduler cannot see semantics")
	var t := T.make("r1", "agent_a", "liquidai/lfm2.5-1.2b-instruct",
		{"messages": [{"role": "user", "content": "SECRET INTENT"}],
		 "explanation": "because I am afraid",
		 "priority_because_important": true},
		T.CLASS_NORMAL, T.LATENCY_INTERACTIVE)
	var view := t.scheduling_view()
	_check("   scheduling view has exactly the allowed keys",
		view.keys().size() == T.ALLOWED_KEYS.size(), str(view.keys()))
	for k in view.keys():
		_check("   allowed key: %s" % k, T.ALLOWED_KEYS.has(k))
	var blob := JSON.stringify(view)
	_check("   payload text never reaches the scheduling view",
		blob.find("SECRET INTENT") == -1 and blob.find("afraid") == -1,
		"semantic content leaked into scheduling")
	_check("   a semantic field added later cannot leak",
		blob.find("priority_because_important") == -1,
		"the view must be built from ALLOWED_KEYS, not filtered")
	_check("   the payload is still intact for dispatch",
		JSON.stringify(t.payload()).find("SECRET INTENT") != -1)


func _health() -> void:
	print("\n health classification: TTFT is hard, decode is supporting")
	var pol := BridgePolicy.new()

	var slow := M.classify(4530, 2.4, 64, pol)
	_check("   TTFT 4530ms is HARD_DEGRADED",
		str(slow["verdict"]) == "HARD_DEGRADED")

	var fast := M.classify(80, 300.0, 64, pol)
	_check("   TTFT 80ms with fast decode is HEALTHY",
		str(fast["verdict"]) == "HEALTHY")

	# The correction that matters: a tiny generation must not condemn a model
	# just because the denominator got stupid.
	var tiny := M.classify(90, 3.0, 8, pol)
	_check("   8 tokens at 3 tok/s is NOT degraded (rate not meaningful)",
		str(tiny["verdict"]) == "HEALTHY" and not bool(tiny["rate_meaningful"]),
		"a short completion must not declare a model dead")

	var enough := M.classify(90, 3.0, 64, pol)
	_check("   64 tokens at 3 tok/s is SUSPECT, not hard",
		str(enough["verdict"]) == "SUSPECT" and not bool(enough["hard_degraded"]))

	_check("   supporting evidence alone is never HARD_DEGRADED",
		not bool(enough["hard_degraded"]))

	# Sabotage: raise the threshold and prove the same sample flips.
	var loose := BridgePolicy.new()
	loose.hard_degraded_ttft_ms = 99999
	_check("   SABOTAGE APPLIED: threshold raised",
		loose.hard_degraded_ttft_ms != pol.hard_degraded_ttft_ms)
	_check("   the verdict follows policy, not a hardcoded constant",
		str(M.classify(4530, 2.4, 64, loose)["verdict"]) != "HARD_DEGRADED")


func _concurrency() -> void:
	print("\n concurrency cap and burst")
	var br := _make_bridge()
	await process_frame
	_check("   starts at max_active_normal",
		br.max_active() == br.policy.max_active_normal)

	for m in br.policy.hot_set:
		(br.models[m] as BridgeModel).set_state(M.HOT, "test", 0)

	for i in br.policy.burst_queue_depth + 2:
		br.queue.append(T.make("q%d" % i, "a", br.policy.hot_set[0], {}))
	_check("   SABOTAGE APPLIED: queue is deep",
		br.queue.size() >= br.policy.burst_queue_depth)
	_check("   deep queue raises the cap to burst",
		br.max_active() == br.policy.max_active_burst)

	(br.models[br.policy.hot_set[1]] as BridgeModel).set_state(
		M.DEGRADED, "test", 0)
	_check("   SABOTAGE APPLIED: a model is DEGRADED",
		(br.models[br.policy.hot_set[1]] as BridgeModel).state == M.DEGRADED)
	_check("   burst is refused while any model is unhealthy",
		br.max_active() == br.policy.max_active_normal,
		"bursting into a degraded pool is how a co-tenant gets wedged")
	br.queue.clear()
	br.queue_free()


func _hysteresis() -> void:
	print("\n swap hysteresis: sustained demand only")
	var pol := BridgePolicy.new()
	var bm := M.make("qwen3.5-2b")
	var now := 1000000

	_check("   one queued request does NOT promote",
		not bm.may_promote(1, 0, now, pol),
		"that would be JIT loading with extra paperwork")
	_check("   sustained queue depth promotes",
		bm.may_promote(pol.promote_queue_depth, 0, now, pol))
	_check("   a long wait promotes",
		bm.may_promote(1, pol.promote_wait_ms, now, pol))

	for i in pol.promote_demand_count:
		bm.note_demand(now, pol.promote_demand_window_ms)
	_check("   SABOTAGE APPLIED: demand recorded",
		bm.demand_in_window(now, pol.promote_demand_window_ms)
			>= pol.promote_demand_count)
	_check("   repeated demand across the window promotes",
		bm.may_promote(1, 0, now, pol))

	bm.last_swap_ms = now
	_check("   cooldown blocks an immediate second swap",
		not bm.may_promote(pol.promote_queue_depth, 0, now + 1, pol))
	_check("   and permits one after the cooldown",
		bm.may_promote(pol.promote_queue_depth, 0,
			now + pol.swap_cooldown_ms + 1, pol))

	var fresh := M.make("falcon-h1-1.5b-instruct")
	fresh.loaded_at_ms = now
	_check("   a freshly loaded model is not demotable",
		not fresh.may_demote(now + 1, pol))
	_check("   and becomes demotable after minimum residency",
		fresh.may_demote(now + pol.min_residency_ms + pol.swap_cooldown_ms + 1,
			pol))
	fresh.in_flight = 1
	_check("   SABOTAGE APPLIED: request in flight", fresh.in_flight == 1)
	_check("   a model with work in flight is never demoted",
		not fresh.may_demote(now + 999999, pol))


func _receipts() -> void:
	print("\n receipts are immutable resource facts")
	var t := T.make("r9", "agent_z", "liquidai/lfm2.5-1.2b-instruct",
		{"messages": [{"role": "user", "content": "PRIVATE"}]})
	var rec := R.make(t)
	rec["dispatched_at_ms"] = 1000
	rec["first_token_at_ms"] = 1100
	rec["finished_at_ms"] = 1600
	rec["generated_tokens"] = 50
	var sealed := R.seal(rec, R.STATUS_OK)
	_check("   ttft derived once", int(sealed["ttft_ms"]) == 100)
	_check("   total derived once", int(sealed["total_ms"]) == 600)
	_check("   decode rate derived from generation window",
		abs(float(sealed["decode_tps"]) - 100.0) < 0.01,
		str(sealed["decode_tps"]))
	_check("   queue delay recorded",
		int(sealed["queue_delay_ms"]) >= 0)
	_check("   no payload in the receipt",
		JSON.stringify(sealed).find("PRIVATE") == -1,
		"receipts must not carry semantics")
	_check("   sealing does not mutate the original",
		int(rec.get("total_ms", -1)) == -1)
	_check("   a line renders", R.line(sealed).find("r9") != -1)


func _states() -> void:
	print("\n model state machine and end-to-end dispatch")
	var m := M.make("x")
	_check("   starts PARKED", m.state == M.PARKED)
	_check("   PARKED is not dispatchable", not m.is_dispatchable())
	m.set_state(M.HOT, "loaded", 10)
	_check("   HOT is dispatchable", m.is_dispatchable())
	m.set_state(M.DEGRADED, "slow", 20)
	_check("   DEGRADED is NOT dispatchable", not m.is_dispatchable(),
		"tolerating a 40-second successful call is the documented failure")
	_check("   transitions are recorded", m.transitions.size() == 2)
	m.set_state("NONSENSE", "bad", 30)
	_check("   an unknown state is refused", m.state == M.DEGRADED)

	var br := _make_bridge()
	await process_frame
	for mid in br.policy.hot_set:
		(br.models[mid] as BridgeModel).set_state(M.HOT, "test", 0)
	var got := {"n": 0}
	br.completed.connect(func(_rid, ok, _txt, _rec): got["n"] += 1 if ok else 0)

	_behaviour = {}
	var before := _calls
	var rid := br.submit("agent_1", br.policy.hot_set[0], {"messages": []})
	_check("   submit returns immediately with an id", rid != "")
	for i in 30:
		await process_frame
	_check("   the request completed asynchronously", got["n"] == 1,
		"submitted %d calls" % (_calls - before))
	_check("   a receipt was written", br.receipts.size() >= 1)

	var unknown := br.submit("agent_1", "no-such-model", {})
	_check("   an unknown model fails immediately and visibly",
		unknown != "" and br.receipts[-1]["status"] == R.STATUS_REJECTED)
	br.queue_free()


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("BRIDGE SELFTEST OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
