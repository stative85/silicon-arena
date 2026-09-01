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
