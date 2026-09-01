extends Node
class_name SystemicRuleset

## systemic_relationship_ruleset: v1
##
## Rung 10 — soft systemic memory. The world remembers even when the model
## misses the inference.
##
## An agent may PROPOSE an alliance; the engine resolves whether the other agent
## accepts. The target's persistent directional relationship toward the proposer
## softly shifts that probability. It never decides it.
##
## This is a SYSTEMIC channel, not a cognitive one. It proves that history
## changed the odds. It proves nothing about whether any model reasoned about
## the history — that is the cognitive channel, measured separately, and the
## Danube 4B configuration showed no useful social-inference signal across the
## conditions tested. Do not report a systemic result as a cognitive one.
##
## Every term is exposed in the returned trace. Nothing is hidden in prose.

const RULESET_ID := "systemic_relationship_ruleset"
const RULESET_VERSION := "v1"

## Neutral starting point: alliances are slightly more likely than not, so that
## both outcomes occur in every arm and no arm is degenerate.
const BASE_PROBABILITY := 0.55

## Weights per axis. Positive axes raise acceptance, negative axes lower it.
##
## familiarity and predictability are logged with ZERO weight. They have no
## agreed directional meaning yet — knowing someone well is a reason to trust
## them or to avoid them, and guessing which would be inventing a finding.
const WEIGHTS := {
	"trust": 0.20,
	"respect": 0.10,
	"debt": 0.15,
	"threat": -0.15,
	"resentment": -0.20,
	"suspicion": -0.10,
	"familiarity": 0.0,
	"predictability": 0.0,
}

## Hard floor and ceiling. Never 0, never 1: a betrayed agent may still accept,
## and a trusted one may still refuse. There is no enemy flag in this engine.
const P_MIN := 0.05
const P_MAX := 0.95

## Bounded seeded uncertainty, applied symmetrically.
const NOISE_RANGE := 0.05

## No single objective event may move acceptance probability by more than this.
## Checked directly by the test suite against the axis caps in ScarLattice.
const MAX_EVENT_SHIFT := 0.15


static func axis_weight(axis: String) -> float:
	return float(WEIGHTS.get(axis, 0.0))


## Deterministic per-decision seed. Same state and same seed reproduce exactly.
static func decision_seed(base_seed: int, proposer_id: String, target_id: String,
		sequence: int) -> int:
	var s := "%d|%s|%s|%d" % [base_seed, proposer_id, target_id, sequence]
	return int(hash(s)) & 0x7FFFFFFF


## Resolve one alliance proposal.
##
## `relation` is the target's directional relationship TOWARD the proposer —
## the axis dictionary as stored by ScarLattice. `context` may carry
## survival_pressure (0..1) and any explicitly named modifiers.
##
## Returns the full trace. The caller renders it; it does not recompute it.
static func resolve_alliance(relation: Dictionary, context: Dictionary,
		base_seed: int, proposer_id: String, target_id: String,
		sequence: int) -> Dictionary:
	var axes: Dictionary = relation.get("axes", relation)

	# An ablation may zero the weights while leaving the relationship state
	# intact. That is the control that proves the WEIGHTS are the mechanism —
	# substituting a neutral state instead would just re-run the neutral arm and
	# call the tautology a result.
	var active_weights: Dictionary = context.get("weights_override", WEIGHTS)

	var contributions := []
	var influence := 0.0
	for axis in WEIGHTS:
		var value := float(axes.get(axis, 0.0))
		var weight := float(active_weights.get(axis, 0.0))
		var contribution := value * weight
		influence += contribution
		contributions.append({
			"axis": axis,
			"value": value,
			"weight": weight,
			"contribution": contribution,
			"counted": weight != 0.0,
		})

	# Contextual modifiers, each named. Survival pressure and debt can outweigh
	# resentment — a cornered agent takes the hand it hates.
	var modifiers := []
	var modifier_total := 0.0
	var survival := clampf(float(context.get("survival_pressure", 0.0)), 0.0, 1.0)
	if survival > 0.0:
		var m := survival * 0.15
		modifier_total += m
		modifiers.append({
			"name": "survival_pressure", "input": survival, "effect": m,
			"why": "a cornered agent accepts help it would otherwise refuse",
		})
	for extra in context.get("modifiers", []):
		if typeof(extra) != TYPE_DICTIONARY:
			continue
		var e := float(extra.get("effect", 0.0))
		modifier_total += e
		modifiers.append(extra)

	var seed_value := decision_seed(base_seed, proposer_id, target_id, sequence)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := rng.randf_range(-NOISE_RANGE, NOISE_RANGE)

	var raw := BASE_PROBABILITY + influence + modifier_total + noise
	var final_p := clampf(raw, P_MIN, P_MAX)
	var roll := rng.randf()
	var accepted := roll < final_p

	return {
		"ruleset_id": RULESET_ID,
		"ruleset_version": RULESET_VERSION,
		"proposer_id": proposer_id,
		"target_id": target_id,
		"sequence": sequence,
		"base_probability": BASE_PROBABILITY,
		"axis_contributions": contributions,
		"relationship_influence": influence,
		"modifiers": modifiers,
		"modifier_total": modifier_total,
		"noise_range": NOISE_RANGE,
		"seeded_uncertainty": noise,
		"decision_seed": seed_value,
		"raw_probability": raw,
		"clamp": [P_MIN, P_MAX],
		"final_probability": final_p,
		"roll": roll,
		"accepted": accepted,
		"causal_event_ids": context.get("causal_event_ids", []),
		"relationship_snapshot": axes.duplicate(true),
		"weights_ablated": context.has("weights_override"),
		"origin": "system_rule",
	}


## Probability alone, without consuming a roll. Used to show the before/after
## of a betrayal without pretending a decision was made.
static func probability_only(relation: Dictionary, context: Dictionary,
		base_seed: int, proposer_id: String, target_id: String,
		sequence: int) -> float:
	return float(resolve_alliance(relation, context, base_seed, proposer_id,
		target_id, sequence)["final_probability"])


## Human-readable trace. Every number that produced the outcome, in order.
static func render_trace(trace: Dictionary) -> String:
	var lines := []
	lines.append("%s:%s  %s -> %s  (seq %d)" % [
		trace["ruleset_id"], trace["ruleset_version"],
		trace["proposer_id"], trace["target_id"], trace["sequence"]])
	lines.append("  base probability            %+.4f" % trace["base_probability"])
	for c in trace["axis_contributions"]:
		if not c["counted"]:
			lines.append("    %-14s value %+.3f  weight  0.000  (logged, zero weight)" % [
				c["axis"], c["value"]])
			continue
		lines.append("    %-14s value %+.3f  weight %+.3f  ->  %+.4f" % [
			c["axis"], c["value"], c["weight"], c["contribution"]])
	lines.append("  relationship influence      %+.4f" % trace["relationship_influence"])
	for m in trace["modifiers"]:
		lines.append("    modifier %-18s %+.4f  (%s)" % [
			str(m.get("name", "?")), float(m.get("effect", 0.0)), str(m.get("why", ""))])
	lines.append("  modifier total              %+.4f" % trace["modifier_total"])
	lines.append("  seeded uncertainty          %+.4f  (range +/-%.3f, seed %d)" % [
		trace["seeded_uncertainty"], trace["noise_range"], trace["decision_seed"]])
	lines.append("  raw                         %+.4f" % trace["raw_probability"])
	lines.append("  clamped to [%.2f, %.2f]      %+.4f" % [
		trace["clamp"][0], trace["clamp"][1], trace["final_probability"]])
	lines.append("  roll                         %.4f" % trace["roll"])
	lines.append("  OUTCOME                     %s" % ("ACCEPTED" if trace["accepted"] else "REFUSED"))
	if not trace["causal_event_ids"].is_empty():
		lines.append("  caused by                   %s" % ", ".join(trace["causal_event_ids"]))
	return "\n".join(lines)
