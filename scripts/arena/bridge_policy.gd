extends RefCounted
class_name BridgePolicy

## Every tunable the bridge obeys, in one place, as DATA.
##
## WHY THIS IS A SEPARATE FILE. The hot set is a policy decision, not a fact
## about the world. Today's default is performance-driven -- the three fastest
## healthy medians measured in docs/results/BENCH_RESIDENCY_RESULTS.md. A later
## experiment may deliberately want RWKV7 hot for architectural diversity, and
## the cost of that is already measured. Hardcoding three model ids into the
## scheduler would turn a measured trade into folklore.
##
## NOTHING HERE IS SEMANTIC. These are resource facts and timing thresholds.
## No entry describes what an agent means, wants, or deserves.

## ---------------------------------------------------------------- residency

## The models the bridge keeps resident by default. Configuration, never
## hardcoded into scheduling logic.
##
## Default rationale, from measured B_turn medians on an idle card:
##   lfm2.5 247 ms, danube2 489 ms, falcon 517 ms  -- three fastest, three
##   different model families. Parks qwen3.5 (most expensive at 1,999 MiB and
##   the observed spill victim) and rwkv7 (3.21x queue degradation, set the
##   wall time in every concurrent set it joined).
##
## Note rwkv7 is the CHEAPEST model at 767 MiB. It is parked on runtime
## grounds, not memory grounds. Swapping it back in is a supported policy.
var hot_set: Array[String] = [
	"liquidai/lfm2.5-1.2b-instruct",
	"h2o-danube2-1.8b-chat",
	"falcon-h1-1.5b-instruct",
]

## Known to the pool but not resident by default.
var parked_set: Array[String] = [
	"qwen3.5-2b",
	"rwkv7-1.5b-g1",
]

var context_length: int = 8192

## ------------------------------------------------------------- concurrency

## Measured throughput gain: 1.59x at 2 in-flight, 1.93x at 3, 2.06x at 5.
## Nearly all of it is captured by 2-3. Beyond 3 the gain does not justify the
## memory pressure on an 8 GiB card shared with a desktop.
var max_active_normal: int = 2
var max_active_burst: int = 3

## Burst is permitted only when the queue actually warrants it AND nothing is
## unhealthy. Bursting into a degraded pool is how a co-tenant gets wedged.
var burst_queue_depth: int = 4

## ------------------------------------------------------------------- health

## HARD signal. Measured separation is wide: healthy TTFT <= 377 ms, degraded
## TTFT 3,599-4,530 ms. 1,500 ms sits ~4x clear of both.
var hard_degraded_ttft_ms: int = 1500

## SUPPORTING signal only, and only when enough tokens were generated for the
## rate to mean anything. Decode tok/s is unreliable when generation time
## approaches timer resolution -- falcon read >1,500 tok/s on short outputs.
## Total latency and TTFT are the trustworthy quantities; this corroborates.
var supporting_decode_tps: float = 15.0
var min_tokens_for_rate: int = 16

## A single slow reply is not a diagnosis. Consecutive breaches are.
var degraded_strikes: int = 2

## FOUR TIMEOUT CLASSES. One giant timeout erases the distinction between
## failures that need different responses, so each phase gets its own clock:
##
##   connect  no connection or response headers -> the server is not there
##   ttft     connected, generation never begins -> wedged model
##   idle     generation began, then froze mid-stream -> stalled generation
##   total    absolute ceiling
##
## These map onto pathologies already observed in the benchmark: a wedge that
## never responds, a spilled model responding 100x slowly, and a generation
## that starts then stops. Recovery keys off the mechanical class.
var connect_timeout_ms: int = 10000
var ttft_timeout_ms: int = 30000
var idle_timeout_ms: int = 20000
var total_timeout_ms: int = 120000

## Retained name for the absolute ceiling used when sizing slot budgets.
var wedge_timeout_ms: int = 120000

## ------------------------------------------------------- swap  hysteresis

## Cold loads measured 1.77 s (lfm2.5) to 8.50 s (rwkv7). A swap is expensive,
## so promotion must require SUSTAINED demand. One queued request is never
## enough -- that would be JIT loading with extra paperwork.
var promote_queue_depth: int = 3
var promote_wait_ms: int = 10000
var promote_demand_count: int = 5
var promote_demand_window_ms: int = 60000

## Once loaded, a model stays for at least this long regardless of demand.
var min_residency_ms: int = 60000

## And the bridge will not swap again until this has elapsed.
var swap_cooldown_ms: int = 30000

## --------------------------------------------------------------- resources

## GPU_BUDGET = total - reserve. The reserve covers the desktop's PEAK, not its
## 596 MiB measured idle floor: Windows compositing, a browser with hardware
## video decode, and Godot all draw from the same card. Raise it, never lower
## it, if the desktop stutters.
var total_vram_mib: int = 8151
var desktop_reserve_mib: int = 2048

## Measured marginal cost of each model when loaded into the pool.
var model_cost_mib: Dictionary = {
	"h2o-danube2-1.8b-chat": 1694,
	"liquidai/lfm2.5-1.2b-instruct": 1055,
	"qwen3.5-2b": 1999,
	"falcon-h1-1.5b-instruct": 1577,
	"rwkv7-1.5b-g1": 767,
}

var endpoint: String = "http://127.0.0.1:1234/v1"
var models_endpoint: String = "http://127.0.0.1:1234/api/v0/models"


func gpu_budget_mib() -> int:
	return total_vram_mib - desktop_reserve_mib


## Does this resident set fit the budget? Baseline is the desktop's own use,
## which the caller measures rather than assumes.
func fits(models: Array, baseline_mib: int) -> bool:
	var cost := baseline_mib
	for m in models:
		cost += int(model_cost_mib.get(m, 0))
	return cost <= gpu_budget_mib()


func known_models() -> Array[String]:
	var out: Array[String] = []
	out.append_array(hot_set)
	for m in parked_set:
		if not out.has(m):
			out.append(m)
	return out


## A policy is only usable if it is internally consistent. Checked at startup
## so a bad configuration fails loudly instead of scheduling strangely.
func validate() -> Array[String]:
	var errs: Array[String] = []
	if hot_set.is_empty():
		errs.append("hot_set is empty")
	if max_active_normal < 1:
		errs.append("max_active_normal must be >= 1")
	if max_active_burst < max_active_normal:
		errs.append("max_active_burst < max_active_normal")
	if desktop_reserve_mib >= total_vram_mib:
		errs.append("desktop_reserve_mib >= total_vram_mib")
	for m in hot_set:
		if parked_set.has(m):
			errs.append("model in both hot_set and parked_set: " + str(m))
		if not model_cost_mib.has(m):
			errs.append("no measured cost for hot model: " + str(m))
	if min_residency_ms < 0 or swap_cooldown_ms < 0:
		errs.append("hysteresis timings must be >= 0")
	return errs
