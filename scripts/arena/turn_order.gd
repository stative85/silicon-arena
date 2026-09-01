extends RefCounted
class_name TurnOrder

## Roster ordering, and the cost model that justifies it.
##
## THE COST. TurnManager walks the agent array strictly round-robin
## (get_next_agent_index: `turn_index % agents.size()`). LM Studio keeps one
## model resident, so a turn pays a cold load whenever the next agent's model
## differs from the current one. Therefore, for a roster walked in a cycle:
##
##     cold loads per round == number of adjacent model CHANGES, counted
##                             circularly (last agent wraps to first)
##
## That is not the number of distinct models in general — it is the number of
## changes, which is why ORDER is a free variable worth optimising. Measured on
## an RTX 5060 8GB a cold swap is 18-38s and warm inference is 0.06-0.26s
## (docs/BENCHMARK_8GB.md), so a round costs approximately:
##
##     changes * ~30s   +   (agents - changes) * ~0.2s
##
## Swaps dominate by two orders of magnitude. Removing one swap from a round is
## worth more than every other per-turn optimisation in the project combined.
##
## THE FIX. If two agents share a model, putting them next to each other costs
## nothing and removes a swap. Grouping is therefore a pure win: it changes no
## agent, no persona, no model, and no policy decision — only the sequence.
##
## For a roster of N agents over M distinct models, grouping achieves the
## optimum of exactly M changes (each model is entered once per round). An
## interleaved order can be as bad as N.
##
##     A B A B A     -> 5 changes  (5 cold loads per round)
##     A A A B B     -> 2 changes  (2 cold loads per round)
##
## A roster of five DISTINCT models cannot be improved: M == N == 5, and
## grouping correctly leaves it alone. That case is exactly why --balanced
## exists (see tools/build_roster.gd) — the only way to cut swaps further is to
## use fewer distinct models, which is a product decision, not an ordering one.


## Number of cold model loads one full round costs, counting the wrap from the
## last agent back to the first. A single-model roster is 1 (the initial load),
## never 0 — the first round always pays for getting the model resident.
static func swaps_per_round(roster: Array) -> int:
	if roster.is_empty():
		return 0
	if roster.size() == 1:
		return 1
	var changes := 0
	for i in roster.size():
		var here := _model_of(roster[i])
		var next := _model_of(roster[(i + 1) % roster.size()])
		if here != next:
			changes += 1
	# An all-identical roster produces 0 changes but still pays one load.
	return maxi(changes, 1)


## Reorder so agents sharing a model are adjacent, achieving the minimum
## possible swaps for that multiset of models.
##
## STABLE: models appear in the order they first occur in the input, and agents
## within a model keep their relative order. A stable result matters because
## the roster is user-visible and written to a preset file — a build that
## shuffled agents differently every run would look broken and would make
## rosters impossible to diff.
static func group_by_model(roster: Array) -> Array:
	var order: Array[String] = []
	var buckets := {}
	for a in roster:
		var m := _model_of(a)
		if not buckets.has(m):
			buckets[m] = []
			order.append(m)
		buckets[m].append(a)
	var out: Array = []
	for m in order:
		for a in buckets[m]:
			out.append(a)
	return out


## Distinct models in a roster. This is the LOWER BOUND on swaps per round, and
## the only way to reduce it is to change the roster's composition.
static func distinct_models(roster: Array) -> int:
	var seen := {}
	for a in roster:
		seen[_model_of(a)] = true
	return seen.size()


## True when grouping would actually change anything, so callers can stay quiet
## when there is nothing to report.
static func is_grouped(roster: Array) -> bool:
	return swaps_per_round(roster) <= maxi(distinct_models(roster), 1)


## Accepts the dictionary shape the roster builder and presets use. Anything
## without a model is treated as its own unnamed group rather than crashing a
## match at turn one.
static func _model_of(agent) -> String:
	if typeof(agent) == TYPE_DICTIONARY:
		return str(agent.get("model", ""))
	if typeof(agent) == TYPE_OBJECT and agent.get("model") != null:
		return str(agent.get("model"))
	return ""
