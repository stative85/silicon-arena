extends RefCounted
class_name Vram

## How much VRAM a model needs, estimated from catalog metadata.
##
## This is an ESTIMATE, not a measurement: the catalog carries parameter counts
## and a quantisation string but no file sizes. It exists because whether two
## models fit together decides whether the arena swaps at all, and swapping is
## the dominant cost in the whole project (docs/BENCHMARK_8GB.md).
##
## It lives here rather than in tools/build_roster.gd because doctor reports
## the same number to the user. A fact written down twice eventually disagrees
## with itself, and this project has shipped that bug five times.
##
## Deliberately GENEROUS. Overcommitting VRAM causes the eviction thrashing
## that --fit exists to avoid, whereas underestimating capacity merely costs
## one architecture. Round up when unsure.

## Usable VRAM to plan against on an 8GB card: context, KV cache and the
## desktop compositor all want some.
const DEFAULT_BUDGET_GB := 6.0

## Returned for a model whose size cannot be determined. Large enough that no
## budget accepts it, so an unknown model is never planned around.
const UNKNOWN := 999.0

## Fixed allowance per loaded model for context and KV cache, in GB.
const OVERHEAD_GB := 0.35


## Bytes per weight implied by a quantisation string, as GB per billion params.
static func bytes_per_weight(quantization: String) -> float:
	var q := quantization.to_upper()
	if q.begins_with("F32"):
		return 4.2
	if q.begins_with("F16") or q.begins_with("BF16"):
		return 2.1
	if q.find("Q8") != -1:
		return 1.1
	if q.find("Q6") != -1:
		return 0.85
	if q.find("Q5") != -1:
		return 0.72
	if q.find("Q3") != -1:
		return 0.48
	if q.find("Q2") != -1:
		return 0.36
	# Q4_K_M and friends, and anything unrecognised. Q4 is by far the most
	# common local quantisation, and it is a safe middle guess for a string
	# this function does not know.
	return 0.6


## Estimated resident size in GB. params_b <= 0 means unknown.
static func estimate_gb(params_b: float, quantization: String) -> float:
	if params_b <= 0.0:
		return UNKNOWN
	return params_b * bytes_per_weight(quantization) + OVERHEAD_GB


## True when a model's size could not be determined.
static func is_unknown(gb: float) -> bool:
	return gb > 900.0


## Total for a set of models that would be resident at the same time.
static func total_gb(sizes: Array) -> float:
	var t := 0.0
	for g in sizes:
		t += float(g)
	return t


## Choose which of `costs` (in rank order, best first) can be resident together.
##
## Returns the indices of the chosen models, preferring MORE distinct models
## and, at a given count, better-ranked ones. Tries `want` models, then
## want-1, and so on down to 2.
##
## The rule for accepting a candidate is a LOOKAHEAD, not a per-model share of
## the budget. Capping each model at budget/k is simpler and quietly refuses
## good rosters: with a 6GB budget and k=3 it rejects anything over 2.0GB, so
## a 2.8 + 1.5 + 1.5 roster that fits comfortably is unreachable and selection
## collapses onto the smallest models installed. Accept a candidate when the
## budget still holds it AND the cheapest models that would fill the remaining
## slots.
##
## Pure arithmetic on a list of sizes, so it is testable without a GPU, a
## catalog or LM Studio.
static func plan_fit(costs: Array, budget_gb: float, want: int) -> Array:
	for k in range(want, 1, -1):
		var chosen: Array = []
		var used := 0.0
		for i in costs.size():
			if chosen.size() >= k:
				break
			var cost := float(costs[i])
			if is_unknown(cost) or cost <= 0.0:
				continue
			var slots_left := k - chosen.size() - 1
			if used + cost + _cheapest_sum(costs, chosen, i, slots_left) <= budget_gb:
				chosen.append(i)
				used += cost
		if chosen.size() == k:
			return chosen
	# Nothing pairs up: the best single model that fits at all.
	for i in costs.size():
		var c := float(costs[i])
		if not is_unknown(c) and c > 0.0 and c <= budget_gb:
			return [i]
	return []


## Combined size of the `count` cheapest models still available. 1e9 when there
## are not enough left to fill the slots at any price, so the caller backs off
## to a smaller k rather than committing to an impossible plan.
static func _cheapest_sum(costs: Array, chosen: Array, candidate: int,
		count: int) -> float:
	if count <= 0:
		return 0.0
	var rest: Array[float] = []
	for i in costs.size():
		if i == candidate or chosen.has(i):
			continue
		var c := float(costs[i])
		if is_unknown(c) or c <= 0.0:
			continue
		rest.append(c)
	rest.sort()
	if rest.size() < count:
		return 1e9
	var total := 0.0
	for i in count:
		total += rest[i]
	return total
