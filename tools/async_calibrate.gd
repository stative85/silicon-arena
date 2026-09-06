extends SceneTree

## ASYNC-A world-feasibility calibration. SUBSTRATE ONLY. No LM inference.
##
##   godot --headless --path . --script tools/async_calibrate.gd
##
## Asks exactly one question:
##
##     Can this world generate the event ASYNC-A is supposed to study?
##
## It does NOT ask, and cannot answer, whether natural async differs from
## equalized async. There are no ASYNC-A agents, no arm assignments, no model
## outputs, and no arm-level effect estimates here. Actors are synthetic and
## choose a legal target mechanically from a seeded distribution.
##
## SYNTHETIC ACTOR CHOICE RULE, declared: uniformly at random among currently
## valid targets, from a fixed seed. Neutral by construction -- an actor that
## always picked the lowest free id would manufacture maximal contention, and
## one that avoided collisions would manufacture none. Either would be tuning
## the answer through the actor rather than the world.
##
## TWO CONTROLS
##   ZERO-DELAY      every completion delay 0. MUST yield stale_conflict == 0.
##                   Mirrors ASYNC-A arm 1: proves the harness does not
##                   manufacture staleness when time cannot cause it.
##   INJECTED-DELAY  delays from a fixed seeded distribution. MUST yield
##                   stale_eligible inside the feasibility window.
##
## FIRST-PASSING CONFIGURATION WINS. The sweep stops at the first parameter set
## inside the window and never optimises further. Without that rule the search
## would find whichever configuration produced the most dramatic conflict, and
## the world would end up shaped around the result we hoped to see.

const W := preload("res://scripts/arena/async_world.gd")

## Feasibility window, declared in the pre-registration BEFORE any calibration
## output. Derived from the planned main-run denominator (200 cycles x 3 agents
## = 600 actions per replicate), not from what calibration happens to produce.
const FLOOR := 0.05      ## >= 30 stale-eligible events per replicate
const CEILING := 0.40    ## above this the world is saturated and useless

## Frozen sweep, loosest to tightest. Index 2 is the starting configuration.
const SEQUENCE := [
	[20, 4], [16, 4], [12, 6], [10, 6], [8, 6], [8, 9], [6, 9], [6, 12],
	[4, 12],
]
const START_INDEX := 2

const AGENTS := 3
const CYCLES := 200
const REPLICATES := 3
const SEED_BASE := 770011


func _init() -> void:
	_run.call_deferred()


## One synthetic run. Returns the three instrumented quantities.
##
## `delay_max` of 0 is the negative control: every action applies in the tick
## it was formed, so no observation can go stale.
func _simulate(res_count: int, hold: int, delay_max: int,
		seed_v: int) -> Dictionary:
	var world: AsyncWorld = W.make(res_count, hold)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v

	var pending: Array = []          ## {agent, target, obs, apply_tick}
	var contention := 0
	var contention_lost := 0
	var stale_eligible := 0
	var stale_conflict := 0
	var accepted := 0
	var actions := 0
	var invalidated_after: Dictionary = {}   ## target -> version invalidated

	for _c in CYCLES:
		# Every actor observes the CURRENT world and forms an action.
		var wanted: Dictionary = {}
		for a in AGENTS:
			var agent := "syn_%d" % a
			var obs := world.observe()
			var vt: Array = obs["valid_targets"]
			if vt.is_empty():
				continue
			var target := str(vt[rng.randi_range(0, vt.size() - 1)])
			wanted[target] = int(wanted.get(target, 0)) + 1
			var delay := 0 if delay_max <= 0 else rng.randi_range(1, delay_max)
			pending.append({"agent": agent, "target": target, "obs": obs,
				"apply_tick": world.tick + delay})
			actions += 1
		# contention_opportunity: two or more actors observed the same
		# currently-valid target in the same tick.
		for t in wanted:
			if int(wanted[t]) >= 2:
				contention += 1

		# APPLY BEFORE ADVANCING. Ordering is load-bearing: advancing first
		# moves the world between observation and application, so a zero-delay
		# action observed at tick T lands at T+1 and reports an age of 1 tick.
		# That is elapsed time the harness invented, and the negative control
		# caught it.
		var still: Array = []
		for p in pending:
			var d: Dictionary = p
			if int(d["apply_tick"]) > world.tick:
				still.append(d)
				continue
			# stale_eligible is judged BEFORE applying: was this target
			# invalidated after the observation that produced the action?
			var tgt := str(d["target"])
			var obs: Dictionary = d["obs"]
			var r: Dictionary = world.resources.get(tgt, {})
			if not r.is_empty() and str(r["holder"]) != "" \
					and int(r["invalidated_at_version"]) > int(obs["version"]):
				stale_eligible += 1
			var out := world.apply(str(d["agent"]), tgt, obs)
			match str(out["outcome"]):
				W.ACCEPTED:
					accepted += 1
				W.STALE_CONFLICT:
					stale_conflict += 1
				W.CONTENTION_LOST:
					contention_lost += 1
		pending = still

		world.advance()

	return {
		"actions": actions,
		"contention_opportunity": contention,
		"stale_eligible": stale_eligible,
		"stale_conflict": stale_conflict,
		"contention_lost": contention_lost,
		"accepted": accepted,
		"stale_eligible_rate": (float(stale_eligible) / float(actions)
			if actions > 0 else 0.0),
	}


func _evaluate(res_count: int, hold: int) -> Dictionary:
	var rates: Array = []
	var totals := {"stale_eligible": 0, "stale_conflict": 0,
		"contention_lost": 0, "contention_opportunity": 0, "actions": 0}
	for rep in REPLICATES:
		var r := _simulate(res_count, hold, 3, SEED_BASE + rep)
		rates.append(float(r["stale_eligible_rate"]))
		for k in totals:
			totals[k] = int(totals[k]) + int(r[k])
	rates.sort()
	var median := float(rates[rates.size() / 2])
	return {"median_rate": median, "rates": rates, "totals": totals,
		"in_window": median >= FLOOR and median <= CEILING,
		"below": median < FLOOR, "above": median > CEILING}


func _run() -> void:
	print("=== ASYNC-A world-feasibility calibration ===")
	print("SUBSTRATE ONLY. No LM inference. No arms. No agents.\n")
	print("window: %.2f <= stale_eligible_rate <= %.2f" % [FLOOR, CEILING])
	print("planned main run: %d cycles x %d agents = %d actions/replicate\n"
		% [CYCLES, AGENTS, CYCLES * AGENTS])

	# ---- negative control -------------------------------------------------
	print("[NEGATIVE CONTROL] zero-delay synthetic actors")
	print("  mirrors ASYNC-A arm 1: time cannot cause staleness")
	var bad := 0
	var neg_total := 0
	for rep in REPLICATES:
		for cfg in SEQUENCE:
			var z := _simulate(int(cfg[0]), int(cfg[1]), 0, SEED_BASE + rep)
			neg_total += int(z["stale_conflict"])
			if int(z["stale_conflict"]) != 0:
				bad += 1
				print("   FAIL res=%d hold=%d -> stale_conflict=%d"
					% [int(cfg[0]), int(cfg[1]), int(z["stale_conflict"])])
	if bad > 0:
		print("\nCALIBRATION VOID: the harness manufactures staleness where")
		print("time cannot cause it. %d configurations produced conflicts." % bad)
		quit(1)
		return
	print("   ok   stale_conflict == 0 across all %d configurations x %d reps\n"
		% [SEQUENCE.size(), REPLICATES])

	# ---- positive sweep ---------------------------------------------------
	print("[POSITIVE] injected-delay synthetic actors, frozen sweep")
	print("  first configuration inside the window wins; no further search\n")
	print("  %-5s %-10s %-6s %8s %8s %10s %s"
		% ["step", "resources", "hold", "stale_el", "conflict", "rate", ""])

	var start := _evaluate(int(SEQUENCE[START_INDEX][0]),
		int(SEQUENCE[START_INDEX][1]))
	var direction := 0
	if bool(start["below"]):
		direction = 1
	elif bool(start["above"]):
		direction = -1

	var chosen := -1
	var results: Array = []
	var idx := START_INDEX
	while idx >= 0 and idx < SEQUENCE.size():
		var cfg: Array = SEQUENCE[idx]
		var ev := _evaluate(int(cfg[0]), int(cfg[1]))
		var t: Dictionary = ev["totals"]
		var mark := ""
		if bool(ev["in_window"]):
			mark = "<- PASS, taken"
		elif bool(ev["below"]):
			mark = "below floor"
		else:
			mark = "above ceiling"
		print("  %-5d %-10d %-6d %8d %8d %10.4f %s"
			% [idx, int(cfg[0]), int(cfg[1]), int(t["stale_eligible"]),
			   int(t["stale_conflict"]), float(ev["median_rate"]), mark])
		results.append({"step": idx, "resources": int(cfg[0]),
			"hold": int(cfg[1]), "median_rate": float(ev["median_rate"]),
			"in_window": bool(ev["in_window"]), "totals": t})
		if bool(ev["in_window"]):
			chosen = idx
			break
		if direction == 0:
			direction = 1 if bool(ev["below"]) else -1
		idx += direction

	print("")
	if chosen < 0:
		print("NO CONFIGURATION PASSED. ASYNC-A is not feasible with this")
		print("world under the declared window. That is the reported result;")
		print("the window is not widened to manufacture feasibility.")
		quit(1)
		return

	var cfg: Array = SEQUENCE[chosen]
	print("FROZEN WORLD CONFIGURATION")
	print("  step        %d" % chosen)
	print("  resources   %d" % int(cfg[0]))
	print("  hold_ticks  %d" % int(cfg[1]))
	print("  evaluated   %d configuration(s), stopped at the first pass"
		% results.size())
	print("\nThese parameters now freeze for all four ASYNC-A arms.")

	var out := {"window": {"floor": FLOOR, "ceiling": CEILING},
		"sequence": SEQUENCE, "start_index": START_INDEX,
		"evaluated": results, "chosen_step": chosen,
		"resources": int(cfg[0]), "hold_ticks": int(cfg[1]),
		"agents": AGENTS, "cycles": CYCLES, "replicates": REPLICATES,
		"negative_control_stale_conflicts": neg_total,
		"negative_control_runs": SEQUENCE.size() * REPLICATES}
	var f := FileAccess.open("res://docs/results/ASYNC_A_CALIBRATION.json",
		FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "  "))
		f.close()
		print("\nwrote docs/results/ASYNC_A_CALIBRATION.json")
	quit(0)
