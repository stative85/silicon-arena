extends SceneTree

## Gate 2: does the step engine reproduce the calibration's exact dynamics?
##
##   godot --headless --path . --script scripts/arena/async_step_selftest.gd
##
## The calibration proved that phase order is dangerous: one `world.advance()`
## in the wrong place manufactured staleness that time could not have caused.
## Sharing `AsyncWorld` does not make two drivers the same dynamical system.
##
## This runs the SAME synthetic actors, seeds and delay schedule that produced
## the frozen calibration numbers, through `AsyncStepEngine`, and requires an
## EXACT journal match -- not merely the same aggregate rate. Two different
## histories can produce identical stale-conflict counts, and an aggregate
## would not notice.
##
## Offline. No LM inference.

const W := preload("res://scripts/arena/async_world.gd")
const E := preload("res://scripts/arena/async_envelope.gd")
const S := preload("res://scripts/arena/async_step.gd")
const T := preload("res://scripts/arena/async_timing.gd")

## The calibration's frozen configuration and seeds.
const RESOURCES := 16
const HOLD := 4
const AGENTS := 3
const CYCLES := 200
const SEED_BASE := 770011

var _checks := 0
var _failures: Array[String] = []
var _sections := ["reproduction", "phase_order", "no_opportunity"]
var _done_sections: Array[String] = []
var _seq := 0


func _init() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("   ok   %s" % name)
	else:
		_failures.append(name)
		print("   FAIL %s  %s" % [name, detail])


func _done(s: String) -> void:
	_done_sections.append(s)


func _run() -> void:
	print("=== ASYNC-A step engine (Gate 2) ===\n")
	_reproduction()
	_phase_order()
	_no_opportunity()
	_report()


## The standalone calibration loop, reproduced here verbatim in structure.
## This is what the engine must match.
func _reference(delay_max: int, seed_v: int) -> Dictionary:
	var world: AsyncWorld = W.make(RESOURCES, HOLD)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var pending: Array = []
	var rows: Array = []
	var stale_eligible := 0
	for _c in CYCLES:
		for a in AGENTS:
			var obs := world.observe()
			var vt: Array = obs["valid_targets"]
			if vt.is_empty():
				continue
			var target := str(vt[rng.randi_range(0, vt.size() - 1)])
			var delay := 0 if delay_max <= 0 else rng.randi_range(1, delay_max)
			pending.append({"agent": "syn_%d" % a, "target": target,
				"obs": obs, "apply_tick": world.tick + delay,
				"rid": "c%03d_a%d" % [_c, a]})
		var still: Array = []
		for p in pending:
			var d: Dictionary = p
			if int(d["apply_tick"]) > world.tick:
				still.append(d)
				continue
			var tgt := str(d["target"])
			var obs2: Dictionary = d["obs"]
			var r: Dictionary = world.resources.get(tgt, {})
			if not r.is_empty() and str(r["holder"]) != "" \
					and int(r["invalidated_at_version"]) > int(obs2["version"]):
				stale_eligible += 1
			var out := world.apply(str(d["agent"]), tgt, obs2)
			rows.append("%s|%s|%s|%d|%d|%s|%s" % [
				str(d["rid"]), str(d["agent"]), tgt, world.tick,
				int(out["observation_age_ticks"]), str(out["outcome"]),
				str(bool(out.get("stale_revalidated", false)))])
		pending = still
		world.advance()
	var s := ""
	for row in rows:
		s += str(row) + "\n"
	return {"hash": s.sha256_text(), "rows": rows.size(),
		"stale_eligible": stale_eligible}


## The same run, driven entirely by AsyncStepEngine.
func _via_engine(delay_max: int, seed_v: int) -> Dictionary:
	var world: AsyncWorld = W.make(RESOURCES, HOLD)
	var eng: AsyncStepEngine = S.make(world, T.NATURAL, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	_seq = 0
	for _c in CYCLES:
		# phases 6-7: observe and submit
		for a in AGENTS:
			var obs := world.observe()
			var vt: Array = obs["valid_targets"]
			if vt.is_empty():
				eng.no_opportunity += 1
				continue
			var target := str(vt[rng.randi_range(0, vt.size() - 1)])
			var delay := 0 if delay_max <= 0 else rng.randi_range(1, delay_max)
			var env: AsyncEnvelope = E.make("c%03d_a%d" % [_c, a],
				"syn_%d" % a)
			env.seal_observation(obs)
			env.set_action(target, "")
			# Deterministic completion order matching submission order, so the
			# reference and the engine see the same within-tick sequence.
			# The standalone calibration had NO explicit within-tick ordering
			# rule -- it inherited `pending` insertion order. Amendment 8 froze
			# NATURAL's rule as completion-time order afterwards. The synthetic
			# schedule therefore encodes submission order explicitly, so both
			# drivers see the SAME schedule rather than one inheriting an
			# implicit rule the other does not have.
			env.submitted_ms = 0
			env.completed_ms = _seq
			_seq += 1
			eng.schedule(env, world.tick + delay)
		# phases 1-4: apply
		eng.step_apply(world.tick)
		# phase 8: advance exactly once
		eng.step_advance()
	return {"hash": eng.journal_hash(), "rows": eng.journal.size(),
		"stale_eligible": eng.stale_eligible}


func _reproduction() -> void:
	print(" the engine reproduces calibration dynamics EXACTLY")
	for rep in 3:
		var seed_v := SEED_BASE + rep
		var ref := _reference(3, seed_v)
		var eng := _via_engine(3, seed_v)
		_check("   seed %d: identical action count" % seed_v,
			int(ref["rows"]) == int(eng["rows"]),
			"%d vs %d" % [int(ref["rows"]), int(eng["rows"])])
		_check("   seed %d: identical stale_eligible" % seed_v,
			int(ref["stale_eligible"]) == int(eng["stale_eligible"]),
			"%d vs %d" % [int(ref["stale_eligible"]),
				int(eng["stale_eligible"])])
		_check("   seed %d: identical JOURNAL HASH" % seed_v,
			str(ref["hash"]) == str(eng["hash"]),
			"aggregate agreement is not enough; the histories must match")
	_done("reproduction")


## Phase order is the thing that broke calibration. Prove it is load-bearing.
func _phase_order() -> void:
	print("\n phase order: apply BEFORE advance")
	var world: AsyncWorld = W.make(8, 4)
	var eng: AsyncStepEngine = S.make(world, T.NATURAL, 0)
	var env: AsyncEnvelope = E.make("z0", "a")
	env.seal_observation(world.observe())
	env.set_action("r_00", "")
	env.completed_ms = 0
	eng.schedule(env, world.tick)          # zero delay
	eng.step_apply(world.tick)
	_check("   a zero-delay action lands in the tick it observed",
		env.observation_age_ticks == 0,
		"age %d -- advancing first would invent elapsed time"
			% env.observation_age_ticks)
	_check("   and is not a stale conflict",
		env.outcome != W.STALE_CONFLICT)

	# SABOTAGE: advance first, then apply. The bug returns.
	var w2: AsyncWorld = W.make(8, 4)
	var e2: AsyncStepEngine = S.make(w2, T.NATURAL, 0)
	var v2: AsyncEnvelope = E.make("z1", "a")
	v2.seal_observation(w2.observe())
	v2.set_action("r_00", "")
	v2.completed_ms = 0
	e2.schedule(v2, w2.tick)
	e2.step_advance()                      # WRONG ORDER, deliberately
	_check("   SABOTAGE APPLIED: world advanced before application",
		w2.tick == 1)
	e2.step_apply(w2.tick)
	_check("   reversing the phases invents an aged observation",
		v2.observation_age_ticks == 1,
		"this is exactly the calibration bug, reproduced on purpose")
	_done("phase_order")


## Gate 3: scarcity must not manufacture hallucination.
func _no_opportunity() -> void:
	print("\n zero visible targets records NO_OPPORTUNITY")
	var world: AsyncWorld = W.make(2, 999)   # never regenerates
	var eng: AsyncStepEngine = S.make(world, T.NATURAL, 0)
	world.apply("x", "r_00", world.observe())
	world.apply("y", "r_01", world.observe())
	_check("   SABOTAGE APPLIED: no targets remain",
		world.valid_targets().is_empty())
	# The caller records the substrate event and makes NO model call.
	if world.valid_targets().is_empty():
		eng.no_opportunity += 1
	_check("   NO_OPPORTUNITY recorded", eng.no_opportunity == 1)
	_check("   it is not an action", int(eng.counts()["actions"]) == 0,
		"forcing a choice when nothing is available would let scarcity "
		+ "mechanically generate a hallucination rate")
	var by: Dictionary = eng.counts()["by_outcome"]
	_check("   and enters no outcome denominator", by.is_empty(), str(by))
	_done("no_opportunity")


func _report() -> void:
	for sec in _sections:
		if not _done_sections.has(sec):
			_failures.append("section did not complete: " + sec)
			print("   FAIL section aborted: %s" % sec)
	print("\n--- %d checks, %d failure(s), %d/%d sections ---"
		% [_checks, _failures.size(), _done_sections.size(), _sections.size()])
	if _failures.is_empty():
		print("ASYNC STEP OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
