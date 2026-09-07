extends SceneTree

## HEALTH-DUTY. Which session-level feature explains the contradiction between
## the synthetic health harness and the production experimental path?
##
##   godot --headless --path . --script tools/health_duty.gd -- \
##       --arm=LONG --order=16,10,4 --rounds=120 --tag=long_asc
##       --arm=CELL --regime=10 --rounds=120 --tag=cell_10
##
## NO FITTING. Shadow mode. ks/kh/n untouched. Same resident pool.
##
## THE ANCHOR FACT. ASYNC-B cell A ran ~1,600 qwen calls at a mean visible list
## of 9.96 with ZERO voids. HEALTH-SHORT at length 10 measured qwen at
## p(SUSPECT) = 0.708, where three-in-a-row is effectively certain. Both at
## max_active_during = 2. Something session-level differs.
##
## CELL_LIKE IS A CLIENT SESSION, NOT A FRESH RUNTIME. A new Godot process
## resets the client; it does NOT reset LM Studio's process lifetime, caches,
## resident duration or GPU scheduling state. No reload is performed to
## manufacture freshness -- that would inject Blocker 2 into a Blocker 1
## diagnostic.
##
## Prompt material is keyed on (length, round_index) ONLY, so the two arms see
## byte-identical prompt sequences and any difference is session, not content.

const B := preload("res://scripts/arena/inference_bridge.gd")
const C := preload("res://scripts/arena/async_contract.gd")
const M := preload("res://scripts/arena/bridge_model.gd")
const HL := preload("res://scripts/arena/bridge_health.gd")

const HOST_FLOOR_MB := 2048.0

var _arm := "LONG"
var _order: Array = [16, 10, 4]
var _rounds := 120
var _tag := "run"

var _bridge: InferenceBridge
var _models: Array[String] = []
var _pending := 0
var _round: Dictionary = {}
var _samples: Array = []
var _problems: Array = []
var _t0 := 0
var _seen := {}
var _last_req_ms := {}
var _calls_in_process := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--arm="):
			_arm = s.substr(6)
		elif s.begins_with("--order="):
			_order = []
			for p in s.substr(8).split(","):
				_order.append(int(p))
		elif s.begins_with("--regime="):
			_order = [int(s.substr(9))]
		elif s.begins_with("--rounds="):
			_rounds = int(s.substr(9))
		elif s.begins_with("--tag="):
			_tag = s.substr(6)
	_run.call_deferred()


## MATCHED MATERIAL. Keyed on (length, round_index) alone -- not on arm, tag,
## process, or wall clock -- so both arms present byte-identical prompts.
func _visible(n: int, round_index: int) -> Array:
	var ids: Array = []
	for i in 16:
		ids.append("r_%02d" % i)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(("HD|len=%d|round=%d" % [n, round_index])
		.sha256_text().substr(0, 15).hex_to_int())
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = ids[i]
		ids[i] = ids[j]
		ids[j] = t
	return ids.slice(0, n)


func _payload(visible: Array) -> Dictionary:
	return {
		"messages": [{"role": "user", "content": C.prompt(visible)}],
		"max_tokens": 24, "temperature": 0.0,
		"response_format": {"type": "json_schema", "json_schema": {
			"name": "async_action", "strict": true, "schema": C.schema()}},
	}


func _run() -> void:
	_t0 = Time.get_ticks_msec()
	print("=== HEALTH-DUTY  arm=%s  tag=%s ===" % [_arm, _tag])
	print("order %s, %d rounds each, shadow, no fitting\n" % [str(_order), _rounds])

	_bridge = B.new()
	get_root().add_child(_bridge)
	await process_frame
	var resident := await _bridge.refresh_residency()
	for mid in _bridge.policy.hot_set:
		if resident.has(mid):
			_models.append(mid)
			(_bridge.models[mid] as BridgeModel).set_state(M.HOT, "observed", 0)
	if _models.size() < 3:
		print("FAIL need the frozen three-model pool, found %s" % str(_models))
		quit(1)
		return
	_bridge.health.shadow = true
	print("resident %s" % str(_models))
	print("shadow   %s   ks/kh/n %.1f/%.1f/%d\n"
		% [str(_bridge.health.shadow), _bridge.health.ks,
		   _bridge.health.kh, _bridge.health.streak_n])

	var mem := OS.get_memory_info()
	var free_mb := float(mem.get("free", 0)) / (1024.0 * 1024.0)
	print("host free %.0f MB" % free_mb)
	if free_mb > 0.0 and free_mb < HOST_FLOOR_MB:
		print("FAIL host memory below the frozen floor")
		quit(1)
		return

	_bridge.completed.connect(func(_rid, ok, _text, rec):
		_round[str(rec.get("model_id", ""))] = {"ok": ok, "rec": rec}
		_pending -= 1)

	## NO WARMUP in the CELL arm -- first-call-in-process is part of what is
	## being measured. The LONG arm gets none either, so the arms stay matched.
	for n in _order:
		print("  regime %2d ..." % n)
		for r in _rounds:
			await _one_round(n, r)

	_report()


func _one_round(n: int, round_index: int) -> void:
	var vis := _visible(n, round_index)
	var key := "%d|%s" % [n, str(vis)]
	if _seen.has(key):
		_problems.append("duplicate prompt at length %d round %d" % [n, round_index])
	_seen[key] = true

	_round.clear()
	_pending = _models.size()
	var burst := 0
	var gaps := {}
	var now := Time.get_ticks_msec()
	for mid in _models:
		gaps[mid] = -1 if not _last_req_ms.has(mid) \
			else now - int(_last_req_ms[mid])
		_last_req_ms[mid] = now
		_bridge.submit("duty", mid, _payload(vis))
		burst += 1
	while _pending > 0:
		await process_frame

	var pos := 0
	for mid in _models:
		pos += 1
		var e: Dictionary = _round.get(mid, {})
		if e.is_empty():
			continue
		var rec: Dictionary = e["rec"]
		_calls_in_process += 1
		_samples.append({
			"arm": _arm, "tag": _tag,
			"length": n, "round_index": round_index, "model": mid,
			"ok": bool(e["ok"]), "status": str(rec.get("status", "")),
			"prompt_tokens": int(rec.get("prompt_tokens", -1)),
			"ttft_ms": int(rec.get("ttft_ms", -1)),
			"expected_ms": float(rec.get("health_expected_ms", -1.0)),
			"residual": float(rec.get("health_residual", -1.0)),
			"verdict": str(rec.get("health_verdict", "")),
			"max_active_during": int(rec.get("max_active_during", -1)),
			# Session structure is a bundle; these record its parts. Telemetry
			# only -- no thresholds are attached to any of them.
			"process_elapsed_ms": Time.get_ticks_msec() - _t0,
			"burst_position": pos,
			"first_call_in_process": _calls_in_process <= _models.size(),
			"ms_since_prev_request_for_model": int(gaps.get(mid, -1)),
		})


func _median(v: Array) -> float:
	if v.is_empty():
		return -1.0
	var s: Array = v.duplicate()
	s.sort()
	return float(s[s.size() / 2])


func _pct(v: Array, p: float) -> float:
	if v.is_empty():
		return -1.0
	var s: Array = v.duplicate()
	s.sort()
	return float(s[mini(int(s.size() * p), s.size() - 1)])


func _report() -> void:
	print("\n[RESULTS] arm=%s tag=%s\n" % [_arm, _tag])
	var out: Array = []
	for mid in _models:
		print("%s" % mid)
		print("  %-4s %5s %7s %9s %8s %8s %8s %6s %6s"
			% ["len", "n", "tokens", "ttft_med", "exp_med", "res_med",
			   "res_p95", "susp", "degr"])
		for n in _order:
			var rows: Array = []
			for s in _samples:
				var d: Dictionary = s
				if int(d["length"]) == n and str(d["model"]) == mid \
						and bool(d["ok"]) and int(d["ttft_ms"]) >= 0:
					rows.append(d)
			if rows.is_empty():
				continue
			var tt: Array = []
			var rs: Array = []
			var ex: Array = []
			var tok: Array = []
			var susp := 0
			var degr := 0
			for d in rows:
				tt.append(int(d["ttft_ms"]))
				ex.append(float(d["expected_ms"]))
				tok.append(int(d["prompt_tokens"]))
				rs.append(float(d["residual"]))
				var v := str(d["verdict"])
				if v == HL.SUSPECT or v == HL.DEGRADED:
					susp += 1
				if v == HL.DEGRADED:
					degr += 1
			var row := {
				"arm": _arm, "tag": _tag, "model": mid, "length": n,
				"n": rows.size(), "tokens_med": _median(tok),
				"ttft_med": _median(tt), "ttft_p95": _pct(tt, 0.95),
				"expected_med": _median(ex),
				"residual_med": _median(rs), "residual_p95": _pct(rs, 0.95),
				"suspect": susp, "suspect_rate": float(susp) / float(rows.size()),
				"degraded": degr,
			}
			out.append(row)
			print("  %-4d %5d %7d %9.0f %8.0f %8.2f %8.2f %6d %6d"
				% [n, rows.size(), int(row["tokens_med"]), row["ttft_med"],
				   row["expected_med"], row["residual_med"],
				   row["residual_p95"], susp, degr])
		print("")

	if not _problems.is_empty():
		for p in _problems:
			print("PROBLEM: %s" % str(p))

	var f := FileAccess.open("res://docs/results/HEALTH_DUTY_%s.json" % _tag,
		FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"arm": _arm, "tag": _tag, "order": _order, "rounds": _rounds,
			"models": _models, "shadow": true,
			"ks": _bridge.health.ks, "kh": _bridge.health.kh,
			"streak_n": _bridge.health.streak_n,
			"summary": out, "samples": _samples, "problems": _problems,
		}, "  "))
		f.close()
		print("wrote docs/results/HEALTH_DUTY_%s.json" % _tag)
	quit(0)
