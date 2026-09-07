extends SceneTree

## ASYNC-B, ONE CELL. SERIAL only.
##
##   godot --headless --path . --script tools/async_b_cell.gd -- \
##       --seed=0 --cell=A [--cycles=200]
##
## One cell = one representation seed x one 2x2 condition. The orchestrator
## `tools/async_b_run.py` runs the frozen Latin schedule over 8 seeds x 4 cells
## and puts `tools/arm_baseline.py` in front of every one.
##
## THE THREE COORDINATES ARE CAPTURED AT DECISION TIME. Every choice records the
## alias list the model actually saw, the alias it returned, that alias's rank
## WITHIN THAT LIST, and the decoded canonical target. None of it is
## reconstructed afterwards from the current mapping. The maps are immutable and
## verified so, but telemetry that depends on successful reconstruction has
## already cost this project several runs; the observation describes itself.
##
## SERIAL removes relative inference latency, so the cell isolates
## representation -> choice -> contention. Required teeth: zero STALE_CONFLICT
## and every observation_age_ticks == 0.

const B := preload("res://scripts/arena/inference_bridge.gd")
const C := preload("res://scripts/arena/async_contract.gd")
const M := preload("res://scripts/arena/bridge_model.gd")
const W := preload("res://scripts/arena/async_world.gd")
const G := preload("res://scripts/arena/async_runtime_guard.gd")
const HL := preload("res://scripts/arena/bridge_health.gd")
const REP := preload("res://scripts/arena/async_representation.gd")

const RESOURCES := 16
const HOLD := 4
const AGENTS := 3
const AGENT_IDS := ["agent_0", "agent_1", "agent_2"]
const CELLS := {
	"A": [true, true], "B": [false, true],
	"C": [true, false], "D": [false, false],
}
const HOST_FLOOR_MB := 2048.0

var _seed := 0
var _cell := "A"
var _cycles := 200

var _bridge: InferenceBridge
var _world
var _guard
var _models: Array[String] = []
var _reps: Dictionary = {}          ## agent_id -> AsyncRepresentation
var _rows: Array = []
var _pending := 0
var _last: Dictionary = {}          ## agent_id -> completion record
var _shape_failed := {}
var _calls := {}
var _problems: Array = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--seed="):
			_seed = int(s.substr(7))
		elif s.begins_with("--cell="):
			_cell = s.substr(7)
		elif s.begins_with("--cycles="):
			_cycles = int(s.substr(9))
	_run.call_deferred()


func cell_id() -> String:
	return "B_seed%02d_%s" % [_seed, _cell]


func _run() -> void:
	print("=== ASYNC-B cell %s ===" % cell_id())
	if not CELLS.has(_cell):
		print("  FAIL unknown cell %s" % _cell)
		quit(1)
		return
	var f: Array = CELLS[_cell]
	var shared_order: bool = bool(f[0])
	var shared_labels: bool = bool(f[1])

	print("[PRE-RUN]")
	print("  seed           %d" % _seed)
	print("  cell           %s" % _cell)
	print("  shared_order   %s" % str(shared_order))
	print("  shared_labels  %s" % str(shared_labels))
	print("  world          %d resources, hold %d" % [RESOURCES, HOLD])
	print("  cycles         %d (SERIAL)" % _cycles)

	# ---- representation frames, frozen before any model call
	for a in AGENT_IDS:
		_reps[a] = REP.make(_seed, a, shared_order, shared_labels)
	var map_hashes := {}
	for a in AGENT_IDS:
		var r = _reps[a]
		if not r.is_bijection():
			print("  FAIL map for %s is not a bijection" % a)
			quit(1)
			return
		map_hashes[a] = {"order": r.order_hash(), "label": r.label_hash()}
		print("  %-8s order %s  label %s" % [a, r.order_hash(), r.label_hash()])
	if not _verify_frames(shared_order, shared_labels):
		quit(1)
		return

	# ---- bridge and roster
	_bridge = B.new()
	get_root().add_child(_bridge)
	await process_frame
	var resident := await _bridge.refresh_residency()
	for mid in _bridge.policy.hot_set:
		if resident.has(mid):
			_models.append(mid)
			(_bridge.models[mid] as BridgeModel).set_state(M.HOT, "observed", 0)
	if _models.size() < AGENTS:
		print("  FAIL need %d hot models, found %d" % [AGENTS, _models.size()])
		quit(1)
		return
	var unprof := HL.unprofiled(_models)
	if not unprof.is_empty():
		print("  FAIL UNPROFILED on roster: %s" % str(unprof))
		quit(1)
		return
	var mem := OS.get_memory_info()
	var free_mb := float(mem.get("free", 0)) / (1024.0 * 1024.0)
	print("  host free      %.0f MB" % free_mb)
	if free_mb > 0.0 and free_mb < HOST_FLOOR_MB:
		print("  FAIL host memory below the frozen floor")
		quit(1)
		return

	_world = W.make(RESOURCES, HOLD)
	_guard = G.make(cell_id(), _models)
	var states := {}
	for mid in _models:
		states[mid] = (_bridge.models[mid] as BridgeModel).state
	_guard.begin(_models, states)
	_bridge.model_state_changed.connect(
		func(mid, fr, t, r): _guard.on_model_state_changed(mid, fr, t, r))
	_bridge.recovery.connect(func(mid, act, ok): _guard.on_recovery(mid, act, ok))
	_bridge.completed.connect(_on_completed)
	print("  genesis hash   %s" % _world.canonical_hash())

	for a in AGENT_IDS:
		_shape_failed[a] = 0
		_calls[a] = 0

	# ---- the cell
	print("\n[RUN]")
	await _ticks()
	print("  %d ticks completed" % _cycles)

	# ---- post-run teeth
	var manifest := _post(shared_order, shared_labels, map_hashes)
	var path := "res://docs/results/ASYNC_%s.json" % cell_id()
	var fh := FileAccess.open(path, FileAccess.WRITE)
	if fh != null:
		fh.store_string(JSON.stringify(manifest, "  "))
		fh.close()
		print("\nwrote %s" % path)
	quit(1 if bool(manifest["void"]) else 0)


## Shared frames must be byte-identical across agents; private frames must be
## mutually separated. Checked HERE as well as in the witness, because a cell
## that silently ran a shared frame while labelled private is unrecoverable
## after the fact.
func _verify_frames(shared_order: bool, shared_labels: bool) -> bool:
	var r0 = _reps[AGENT_IDS[0]]
	for i in range(1, AGENT_IDS.size()):
		var ri = _reps[AGENT_IDS[i]]
		if shared_order and r0.order_hash() != ri.order_hash():
			print("  FAIL shared_order frames differ")
			return false
		if not shared_order and REP.hamming(r0.order, ri.order) < 12:
			print("  FAIL private_order frames not separated")
			return false
		if shared_labels and r0.label_hash() != ri.label_hash():
			print("  FAIL shared_labels frames differ")
			return false
		if not shared_labels and REP.hamming(r0.label, ri.label) < 12:
			print("  FAIL private_labels frames not separated")
			return false
	return true


func _ticks() -> void:
	for c in _cycles:
		var tick: int = _world.tick
		_guard.world_tick = tick
		var obs: Dictionary = _world.observe()
		var vt: Array = obs["valid_targets"]
		if vt.is_empty():
			_world.advance()
			continue

		# STRUCTURAL INVARIANT, checked every tick: each agent's decoded visible
		# set must equal the world's canonical set. Only order and labels may
		# differ between agents -- never the set itself.
		var want: Array = vt.duplicate()
		want.sort()
		var shown := {}
		for i in AGENTS:
			var a: String = AGENT_IDS[i]
			var disp: Array = _reps[a].render(vt)
			var back: Array = []
			for al in disp:
				back.append(_reps[a].decode(str(al)))
			back.sort()
			if back != want:
				_problems.append(
					"decoded visible set != world set for %s at tick %d"
					% [a, tick])
				return
			shown[a] = disp

		# SERIAL: every agent observes the same instant, then the world waits.
		_last.clear()
		_pending = AGENTS
		for i in AGENTS:
			var a: String = AGENT_IDS[i]
			_calls[a] = int(_calls[a]) + 1
			_bridge.submit(a, _models[i], _payload(shown[a]))
		while _pending > 0:
			await process_frame

		for i in AGENTS:
			var a: String = AGENT_IDS[i]
			var rec: Dictionary = _last.get(a, {})
			var disp: Array = shown[a]
			var row := {
				"agent_id": a, "model_id": _models[i],
				"representation_seed": _seed, "cell": _cell,
				"world_tick": tick, "world_version": int(obs.get("version", -1)),
				"visible_alias_sequence": disp,
				"visible_canonical_sequence_hash": _hash_list(vt),
				"order_map_hash": _reps[a].order_hash(),
				"label_map_hash": _reps[a].label_hash(),
				"chosen_alias": "", "chosen_local_rank": -1,
				"decoded_canonical_target": "",
				"outcome": "", "observation_age_ticks": -1,
				"shape_failed": false,
			}
			if not bool(rec.get("ok", false)):
				row["shape_failed"] = true
				row["outcome"] = "TRANSPORT_FAILED"
				_shape_failed[a] = int(_shape_failed[a]) + 1
				_rows.append(row)
				continue
			var parsed := C.parse(str(rec.get("text", "")))
			if not bool(parsed["ok"]):
				row["shape_failed"] = true
				row["outcome"] = "SHAPE_FAILED"
				_shape_failed[a] = int(_shape_failed[a]) + 1
				_rows.append(row)
				continue
			var alias := str(parsed["target_id"])
			row["chosen_alias"] = alias
			# Rank is looked up in the EXACT list this model saw, now, not
			# recomputed later from the mapping.
			row["chosen_local_rank"] = disp.find(alias)
			var canon: String = _reps[a].decode(alias)
			row["decoded_canonical_target"] = canon
			var applied: Dictionary = _world.apply(a, canon, obs)
			row["outcome"] = str(applied["outcome"])
			row["observation_age_ticks"] = int(applied["observation_age_ticks"])
			_rows.append(row)
		_world.advance()


func _payload(visible_aliases: Array) -> Dictionary:
	return {
		"messages": [{"role": "user", "content": C.prompt(visible_aliases)}],
		"max_tokens": 24, "temperature": 0.0,
		"response_format": {"type": "json_schema", "json_schema": {
			"name": "async_action", "strict": true, "schema": C.schema()}},
	}


func _on_completed(_rid, ok, text, rec) -> void:
	var a := str(rec.get("agent_id", ""))
	if a == "":
		a = str(rec.get("requester", ""))
	_last[a] = {"ok": ok, "text": text, "rec": rec}
	_pending -= 1


func _hash_list(xs: Array) -> String:
	var v: Array = xs.duplicate()
	v.sort()
	return ("|".join(PackedStringArray(v))).sha256_text().substr(0, 16)


func _post(shared_order: bool, shared_labels: bool,
		map_hashes: Dictionary) -> Dictionary:
	print("\n[POST-RUN]")
	var by_outcome := {}
	var stale := 0
	var nonzero_age := 0
	for r in _rows:
		var d: Dictionary = r
		var o := str(d["outcome"])
		by_outcome[o] = int(by_outcome.get(o, 0)) + 1
		if o == "STALE_CONFLICT":
			stale += 1
		if int(d["observation_age_ticks"]) > 0:
			nonzero_age += 1

	# maps must be unchanged
	for a in AGENT_IDS:
		var r = _reps[a]
		var h: Dictionary = map_hashes[a]
		if r.order_hash() != str(h["order"]) or r.label_hash() != str(h["label"]):
			_problems.append("map hash changed mid-replicate for " + a)

	if stale > 0:
		_problems.append("SERIAL produced %d STALE_CONFLICT" % stale)
	if nonzero_age > 0:
		_problems.append("%d observations had age > 0" % nonzero_age)
	for a in AGENT_IDS:
		var n := int(_calls[a])
		if n > 0 and float(_shape_failed[a]) / float(n) > 0.10:
			_problems.append("SHAPE_FAILED > 10%% for " + a)
	if _guard.is_void():
		_problems.append("runtime: " + _guard.void_reason)

	# NOT EXERCISED is not evidence: a private cell whose frames collapsed to
	# the shared ones would look like a null result rather than a broken one.
	var exercised := true
	if not shared_order or not shared_labels:
		var r0 = _reps[AGENT_IDS[0]]
		var r1 = _reps[AGENT_IDS[1]]
		if not shared_order and r0.order_hash() == r1.order_hash():
			exercised = false
		if not shared_labels and r0.label_hash() == r1.label_hash():
			exercised = false

	print("  rows            %d" % _rows.size())
	print("  outcomes        %s" % JSON.stringify(by_outcome))
	print("  shape_failed    %s" % JSON.stringify(_shape_failed))
	print("  stale           %d (must be 0)" % stale)
	print("  nonzero age     %d (must be 0)" % nonzero_age)
	print("  exercised       %s" % str(exercised))
	print("  final world     %s" % _world.canonical_hash())
	if _problems.is_empty():
		print("  cell teeth      OK")
	else:
		for p in _problems:
			print("  VOID: %s" % str(p))

	return {
		"cell_id": cell_id(), "experiment": "B",
		"representation_seed": _seed, "cell": _cell,
		"shared_order": shared_order, "shared_labels": shared_labels,
		"map_hashes": map_hashes,
		"resources": RESOURCES, "hold_ticks": HOLD, "agents": AGENTS,
		"cycles": _cycles, "timing_regime": "SERIAL",
		"models": _models, "contract_schema_hash": C.schema_hash(),
		"rows": _rows, "counts": by_outcome,
		"shape_failed": _shape_failed, "calls": _calls,
		"stale_conflict": stale, "nonzero_age": nonzero_age,
		"exercised": exercised,
		"final_world_hash": _world.canonical_hash(),
		"runtime": _guard.envelope(),
		"void": not _problems.is_empty(), "void_reasons": _problems,
	}
