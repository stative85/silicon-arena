extends SceneTree

## HEALTH-REUSE. Does production-like prompt-set reuse explain the anchor
## contradiction between the synthetic harness and ASYNC-B cell A?
##
##   godot --headless --path . --script tools/health_reuse.gd -- \
##       --first=CYCLING --seed=0 --rounds=200 --tag=r0_cu
##
## CYCLING replays cell A's exact visible sequences -- 200 rounds, ~10 distinct
## prompts, every repeat at gap >= 4. UNIQUE matches the per-round list LENGTH
## exactly but uses a distinct subset every round.
##
## WHY THIS REPLACED HEALTH-PREFIX. The prefix hypothesis was checked against the
## fossils and is false: production shared no content prefix either (LCP median
## 25 chars = header only, first item changed every round). Closing the whole
## cache question on that was an over-claim -- ~95% of cell A's prompts were
## exact repeats at gap >= 4, and "a single KV context evicts before the repeat
## returns" was an assumption about LM Studio, not a measurement.
##
## Shadow mode. ks/kh/n untouched. No reloads, so Blocker 2 stays out.

const B := preload("res://scripts/arena/inference_bridge.gd")
const C := preload("res://scripts/arena/async_contract.gd")
const M := preload("res://scripts/arena/bridge_model.gd")
const HL := preload("res://scripts/arena/bridge_health.gd")

const HOST_FLOOR_MB := 2048.0

var _first := "CYCLING"
var _seed := 0
var _rounds := 200
var _tag := "run"

var _bridge: InferenceBridge
var _models: Array[String] = []
var _pending := 0
var _round: Dictionary = {}
var _samples: Array = []
var _problems: Array = []
var _trace: Array = []
var _t0 := 0
var _used_unique := {}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--first="):
			_first = s.substr(8)
		elif s.begins_with("--seed="):
			_seed = int(s.substr(7))
		elif s.begins_with("--rounds="):
			_rounds = int(s.substr(9))
		elif s.begins_with("--tag="):
			_tag = s.substr(6)
	_run.call_deferred()


func _load_trace() -> bool:
	var path := "res://docs/results/CELLA_TRACE_seed%02d.json" % _seed
	if not FileAccess.file_exists(path):
		print("FAIL missing fossil %s" % path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_ARRAY:
		print("FAIL fossil is not an array")
		return false
	_trace = parsed
	return _trace.size() >= _rounds


## UNIQUE: same length as the trace round, but a subset never used before in
## this process. Deterministic first, uniqueness enforced by re-rolling.
func _unique_list(n: int, round_index: int) -> Array:
	for attempt in 64:
		var ids: Array = []
		for i in 16:
			ids.append("r_%02d" % i)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(("HR|u|%d|%d|%d" % [_seed, round_index, attempt])
			.sha256_text().substr(0, 15).hex_to_int())
		for i in range(ids.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = ids[i]
			ids[i] = ids[j]
			ids[j] = t
		var pick: Array = ids.slice(0, n)
		var key := str(pick)
		if not _used_unique.has(key):
			_used_unique[key] = true
			return pick
	_problems.append("could not find an unused subset at round %d" % round_index)
	return []


func _payload(visible: Array) -> Dictionary:
	return {
		"messages": [{"role": "user", "content": C.prompt(visible)}],
		"max_tokens": 24, "temperature": 0.0,
		"response_format": {"type": "json_schema", "json_schema": {
			"name": "async_action", "strict": true, "schema": C.schema()}},
	}


func _run() -> void:
	_t0 = Time.get_ticks_msec()
	print("=== HEALTH-REUSE  seed=%d  first=%s  tag=%s ===" % [_seed, _first, _tag])
	if not _load_trace():
		quit(1)
		return
	var distinct := {}
	for i in _rounds:
		distinct[str(_trace[i])] = true
	print("fossil: %d rounds, %d distinct prompts" % [_rounds, distinct.size()])

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
	print("shadow true  ks/kh/n %.1f/%.1f/%d"
		% [_bridge.health.ks, _bridge.health.kh, _bridge.health.streak_n])

	var mem := OS.get_memory_info()
	var free_mb := float(mem.get("free", 0)) / (1024.0 * 1024.0)
	print("host free %.0f MB\n" % free_mb)
	if free_mb > 0.0 and free_mb < HOST_FLOOR_MB:
		print("FAIL host memory below the frozen floor")
		quit(1)
		return

	_bridge.completed.connect(func(_rid, ok, _text, rec):
		_round[str(rec.get("model_id", ""))] = {"ok": ok, "rec": rec}
		_pending -= 1)

	var order: Array = ["CYCLING", "UNIQUE"]
	if _first != "CYCLING":
		order = ["UNIQUE", "CYCLING"]
	for cond in order:
		print("  %s ..." % str(cond))
		var last_seen := {}
		for r in _rounds:
			var vis: Array = []
			if str(cond) == "CYCLING":
				vis = _trace[r]
			else:
				vis = _unique_list((_trace[r] as Array).size(), r)
			if vis.is_empty():
				continue
			var key := str(vis)
			var gap := -1
			if last_seen.has(key):
				gap = r - int(last_seen[key])
			last_seen[key] = r
			await _one_round(str(cond), vis, r, gap)

	_report()


func _one_round(cond: String, vis: Array, round_index: int, gap: int) -> void:
	_round.clear()
	_pending = _models.size()
	for mid in _models:
		_bridge.submit("reuse", mid, _payload(vis))
	while _pending > 0:
		await process_frame
	var mem := OS.get_memory_info()
	for mid in _models:
		var e: Dictionary = _round.get(mid, {})
		if e.is_empty():
			continue
		var rec: Dictionary = e["rec"]
		_samples.append({
			"condition": cond, "seed": _seed, "tag": _tag,
			"round_index": round_index, "model": mid,
			"list_len": vis.size(), "prompt_key": str(vis),
			"repeat_gap": gap,
			"ok": bool(e["ok"]),
			"prompt_tokens": int(rec.get("prompt_tokens", -1)),
			"ttft_ms": int(rec.get("ttft_ms", -1)),
			"expected_ms": float(rec.get("health_expected_ms", -1.0)),
			"residual": float(rec.get("health_residual", -1.0)),
			"verdict": str(rec.get("health_verdict", "")),
			"max_active_during": int(rec.get("max_active_during", -1)),
			"process_elapsed_ms": Time.get_ticks_msec() - _t0,
			"host_free_mb": int(float(mem.get("free", 0)) / (1024.0 * 1024.0)),
		})


func _median(v: Array) -> float:
	if v.is_empty():
		return -1.0
	var s: Array = v.duplicate()
	s.sort()
	return float(s[s.size() / 2])


func _report() -> void:
	print("\n[RESULTS] seed=%d first=%s\n" % [_seed, _first])
	var out: Array = []
	for mid in _models:
		print("%s" % mid)
		print("  %-9s %5s %7s %9s %8s %8s %7s %6s %9s"
			% ["cond", "n", "tokens", "ttft_med", "exp_med", "res_med",
			   "susp%", "degr", "maxstreak"])
		for cond in ["CYCLING", "UNIQUE"]:
			var rows: Array = []
			for s in _samples:
				var d: Dictionary = s
				if str(d["condition"]) == cond and str(d["model"]) == mid \
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
			var cur := 0
			var mx := 0
			for d in rows:
				tt.append(int(d["ttft_ms"]))
				ex.append(float(d["expected_ms"]))
				tok.append(int(d["prompt_tokens"]))
				rs.append(float(d["residual"]))
				var v := str(d["verdict"])
				if v == HL.SUSPECT or v == HL.DEGRADED:
					susp += 1
					cur += 1
					mx = maxi(mx, cur)
				else:
					cur = 0
				if v == HL.DEGRADED:
					degr += 1
			var row := {
				"condition": cond, "model": mid, "seed": _seed, "tag": _tag,
				"n": rows.size(), "tokens_med": _median(tok),
				"ttft_med": _median(tt), "expected_med": _median(ex),
				"residual_med": _median(rs),
				"suspect": susp, "suspect_rate": float(susp) / float(rows.size()),
				"degraded": degr, "max_streak": mx,
			}
			out.append(row)
			print("  %-9s %5d %7d %9.0f %8.0f %8.2f %6.1f%% %6d %9d"
				% [cond, rows.size(), int(row["tokens_med"]), row["ttft_med"],
				   row["expected_med"], row["residual_med"],
				   100.0 * float(row["suspect_rate"]), degr, mx])
		print("")

	# MANIPULATION CHECK. A null is meaningless unless the intervention happened.
	var dc := {}
	var dcu := {}
	for s in _samples:
		var d: Dictionary = s
		if str(d["condition"]) == "CYCLING":
			dc[str(d["prompt_key"])] = true
		else:
			dcu[str(d["prompt_key"])] = true
	print("[MANIPULATION CHECK]")
	print("  distinct prompts  CYCLING %d   UNIQUE %d" % [dc.size(), dcu.size()])
	var exercised: bool = dc.size() < 30 and dcu.size() > 150
	print("  exercised         %s" % str(exercised))
	if not exercised:
		_problems.append("NOT EXERCISED: distinct-prompt counts did not separate")

	# Token-match tooth, per model per round.
	var tok_by := {}
	for s in _samples:
		var d: Dictionary = s
		var k := "%s|%d" % [str(d["model"]), int(d["round_index"])]
		if not tok_by.has(k):
			tok_by[k] = {}
		(tok_by[k] as Dictionary)[str(d["condition"])] = int(d["prompt_tokens"])
	var mismatch := 0
	for k in tok_by:
		var pair: Dictionary = tok_by[k]
		if pair.has("CYCLING") and pair.has("UNIQUE") \
				and int(pair["CYCLING"]) != int(pair["UNIQUE"]):
			mismatch += 1
	print("  prompt_token mismatches across conditions: %d" % mismatch)
	if mismatch > 0:
		_problems.append("%d rounds had mismatched prompt_tokens" % mismatch)

	for p in _problems:
		print("PROBLEM: %s" % str(p))

	var f := FileAccess.open("res://docs/results/HEALTH_REUSE_%s.json" % _tag,
		FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"seed": _seed, "first": _first, "tag": _tag, "rounds": _rounds,
			"models": _models, "shadow": true,
			"distinct_cycling": dc.size(), "distinct_unique": dcu.size(),
			"exercised": exercised, "token_mismatches": mismatch,
			"summary": out, "samples": _samples, "problems": _problems,
		}, "  "))
		f.close()
		print("\nwrote docs/results/HEALTH_REUSE_%s.json" % _tag)
	quit(0)
