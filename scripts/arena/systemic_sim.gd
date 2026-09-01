extends SceneTree

## Rung 10 — the cheap systemic proof.
##
##   Godot --headless --path . --script scripts/arena/systemic_sim.gd -- \
##       [--seeds 2000] [--out FILE] [--ablate] [--json FILE]
##
## No model inference. Pure seeded arithmetic across five arms, checked against
## docs/proof/continuity-lattice/rung10-systemic-memory/PREREGISTRATION.md.
##
## This proves SYSTEMIC consequence: stored relationship state changes the odds.
## It proves nothing about model cognition and must not be reported as if it did.

const Ruleset := preload("res://scripts/arena/systemic_ruleset.gd")

## Axis deltas per event, matching the caps ScarLattice already enforces.
const BETRAYAL_DELTAS := {"trust": -0.25, "resentment": 0.25, "suspicion": 0.20}
const COOPERATION_DELTAS := {"trust": 0.15, "debt": 0.20, "resentment": -0.15}

var _failures := 0
var _lines := []


func _init() -> void:
	var seeds := 2000
	var out_path := ""
	var json_path := ""
	var ablate := false
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size(): seeds = int(args[i + 1])
		if args[i] == "--out" and i + 1 < args.size(): out_path = args[i + 1]
		if args[i] == "--json" and i + 1 < args.size(): json_path = args[i + 1]
		if args[i] == "--ablate": ablate = true

	_say("Rung 10 — systemic memory, seeded simulation")
	_say("ruleset %s:%s   seeds/arm %d   ablation=%s" % [
		Ruleset.RULESET_ID, Ruleset.RULESET_VERSION, seeds, str(ablate)])
	_say("NO model inference was used. This is a systemic result, not a cognitive one.")
	_say("")

	var neutral := _blank()
	var betrayed := _apply(_blank(), BETRAYAL_DELTAS)
	var repaired := _apply(_apply(_blank(), BETRAYAL_DELTAS), COOPERATION_DELTAS)

	_say("relationship states (target -> proposer)")
	_say("  neutral   %s" % _fmt(neutral))
	_say("  betrayed  %s" % _fmt(betrayed))
	_say("  repaired  %s" % _fmt(repaired))
	_say("")

	var r_neutral := _arm("neutral", neutral, seeds, "agent-02", "agent-01", false)
	var r_betrayed := _arm("betrayed", betrayed, seeds, "agent-02", "agent-01", false)
	var r_repaired := _arm("repaired", repaired, seeds, "agent-02", "agent-01", false)
	var r_ablated := _arm("ablated", betrayed, seeds, "agent-02", "agent-01", true)
	# Identity strings exchanged; the RELATIONSHIP is unchanged. Any shift here
	# is the names leaking into the outcome.
	var r_swap := _arm("name_swap", betrayed, seeds, "agent-01", "agent-02", false)

	_say("")
	_say("arm         accept%%   n      mean p   min p   max p")
	for r in [r_neutral, r_betrayed, r_repaired, r_ablated, r_swap]:
		_say("  %-10s %6.2f  %5d   %6.4f  %6.4f  %6.4f" % [
			r["name"], r["rate"] * 100.0, r["n"], r["mean_p"], r["min_p"], r["max_p"]])
	_say("")

	# ── the preregistered predictions ──────────────────────────────────────
	var drop: float = (float(r_neutral["rate"]) - float(r_betrayed["rate"])) * 100.0
	_say("PREREGISTERED CHECKS")
	_check("1. betrayal LOWERS acceptance", r_betrayed["rate"] < r_neutral["rate"],
		"%.2fpp drop" % drop)
	_check("2. the shift is soft: 5-15pp", drop >= 5.0 and drop <= 15.0,
		"%.2fpp" % drop)
	var all_mixed := true
	for r in [r_neutral, r_betrayed, r_repaired, r_ablated, r_swap]:
		if r["rate"] <= 0.0 or r["rate"] >= 1.0:
			all_mixed = false
	_check("3. both outcomes occur in EVERY arm", all_mixed)
	_check("4. repair moves back toward neutral, without erasing it",
		r_repaired["rate"] > r_betrayed["rate"] and r_repaired["rate"] < r_neutral["rate"],
		"betrayed %.2f%% < repaired %.2f%% < neutral %.2f%%" % [
			r_betrayed["rate"] * 100.0, r_repaired["rate"] * 100.0, r_neutral["rate"] * 100.0])
	var abl_gap: float = absf(r_ablated["rate"] - r_neutral["rate"]) * 100.0
	_check("6. ablation removes the shift (within 1.5pp of neutral)", abl_gap <= 1.5,
		"%.2fpp from neutral" % abl_gap)
	var swap_gap: float = absf(r_swap["rate"] - r_betrayed["rate"]) * 100.0
	_check("7. swapping identities does not move the rate (within 2pp)",
		swap_gap <= 2.0, "%.2fpp" % swap_gap)

	# 8. no single event may move probability more than 15pp, from ANY state.
	var worst: float = 0.0
	var worst_desc := ""
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for i in 500:
		var state := _blank()
		for axis in state:
			state[axis] = rng.randf_range(-1.0, 1.0)
		for deltas in [BETRAYAL_DELTAS, COOPERATION_DELTAS]:
			var before := Ruleset.probability_only({"axes": state}, {}, 7, "a", "b", i)
			var after := Ruleset.probability_only({"axes": _apply(state.duplicate(), deltas)},
				{}, 7, "a", "b", i)
			var shift: float = absf(after - before) * 100.0
			if shift > worst:
				worst = shift
				worst_desc = "%.2fpp" % shift
	_check("8. no single event moves probability more than 15pp", worst <= 15.0,
		"worst observed %s" % worst_desc)

	# 5. determinism, checked in-process; cross-process is the selftest's job.
	var a := Ruleset.resolve_alliance({"axes": betrayed}, {}, 1771, "agent-02", "agent-01", 3)
	var b := Ruleset.resolve_alliance({"axes": betrayed}, {}, 1771, "agent-02", "agent-01", 3)
	_check("5. same state + same seed reproduces exactly",
		JSON.stringify(a) == JSON.stringify(b))

	# Debt and survival pressure can outweigh resentment.
	var resentful := _blank()
	resentful["resentment"] = 1.0
	var p_resentful := Ruleset.probability_only({"axes": resentful}, {}, 5, "x", "y", 1)
	var indebted := resentful.duplicate()
	indebted["debt"] = 1.0
	var p_debt := Ruleset.probability_only({"axes": indebted}, {"survival_pressure": 1.0},
		5, "x", "y", 1)
	_check("debt + survival pressure can outweigh maximum resentment",
		p_debt > p_resentful, "%.4f -> %.4f" % [p_resentful, p_debt])
	_check("no probability is ever exactly 0 or 1",
		p_resentful > 0.0 and p_debt < 1.0)

	_say("")
	_say("--- %d preregistered check(s), %d failure(s) ---" % [_checks, _failures])
	_say("RUNG10 " + ("PASS" if _failures == 0 else "FAIL"))

	var text := "\n".join(_lines)
	print(text)
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(text + "\n")
			f.close()
	if json_path != "":
		var jf := FileAccess.open(json_path, FileAccess.WRITE)
		if jf != null:
			jf.store_string(JSON.stringify({
				"ruleset": "%s:%s" % [Ruleset.RULESET_ID, Ruleset.RULESET_VERSION],
				"seeds_per_arm": seeds,
				"arms": [r_neutral, r_betrayed, r_repaired, r_ablated, r_swap],
				"drop_pp": drop, "failures": _failures,
			}, "  "))
			jf.close()
	quit(0 if _failures == 0 else 1)


func _blank() -> Dictionary:
	var d := {}
	for axis in Ruleset.WEIGHTS:
		d[axis] = 0.0
	return d


func _apply(state: Dictionary, deltas: Dictionary) -> Dictionary:
	for axis in deltas:
		state[axis] = clampf(float(state.get(axis, 0.0)) + float(deltas[axis]), -1.0, 1.0)
	return state


func _fmt(state: Dictionary) -> String:
	var parts := []
	for axis in state:
		if float(state[axis]) != 0.0:
			parts.append("%s %+.2f" % [axis, state[axis]])
	return "(neutral)" if parts.is_empty() else ", ".join(parts)


## One arm. `ablate` zeroes the relationship contribution, which is the control
## proving the shift comes from the relationship and nowhere else.
func _arm(name: String, state: Dictionary, seeds: int, proposer: String,
		target: String, ablate: bool) -> Dictionary:
	var accepted := 0
	var sum_p := 0.0
	var min_p := 1.0
	var max_p := 0.0
	# ABLATION: keep the betrayed relationship, zero the WEIGHTS. Swapping in a
	# neutral state instead would simply re-run the neutral arm and prove
	# nothing about where the shift came from.
	var ctx := {}
	if ablate:
		var zeroed := {}
		for axis in Ruleset.WEIGHTS:
			zeroed[axis] = 0.0
		ctx["weights_override"] = zeroed
	for i in seeds:
		var t: Dictionary = Ruleset.resolve_alliance({"axes": state}, ctx,
			900000 + i, proposer, target, i)
		if t["accepted"]:
			accepted += 1
		var p: float = t["final_probability"]
		sum_p += p
		min_p = minf(min_p, p)
		max_p = maxf(max_p, p)
	return {
		"name": name, "n": seeds, "accepted": accepted,
		"rate": float(accepted) / float(seeds),
		"mean_p": sum_p / float(seeds), "min_p": min_p, "max_p": max_p,
	}


var _checks := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
	_say("   %s %s%s" % ["ok  " if ok else "FAIL", label,
		"" if detail == "" else "  (%s)" % detail])


func _say(line: String) -> void:
	_lines.append(line)
