extends RefCounted
class_name BridgeHealth

## Size-conditioned health classification. FROZEN POLICY.
##
##   residual = observed_ttft / expected_ttft(model, prompt_tokens, load)
##
##   SUSPECT           residual >= 1.8
##   HARD_CATASTROPHE  residual >= 20.0
##   DEGRADED          3 consecutive SUSPECT completed calls
##   single spike      recorded, NOT recovered
##
## WHAT THIS REPLACES. `TTFT > 1500 ms` was not merely mis-sized, it was
## structurally blind: 8.3% false positives on healthy traffic AND it detected
## no degradation shape except a total wedge. LFM2.5 degraded 4x on a small
## prompt is 308 ms, invisible to it; healthy falcon on a large contended
## prompt is 1,780 ms, flagged by it. Both errors at once.
##
## The bridge now measures something more useful than "slow":
## **unexpectedly slow for this model, this input, under this load,
## repeatedly.**
##
## THE CAUSALITY RULE, and it matters. Exact `prompt_tokens` comes from the
## server's usage frame, which arrives at STREAM COMPLETION. This detector is
## therefore a POST-CALL classifier and nothing else. It must never be
## consulted to decide whether a call should have been abandoned earlier --
## that decision belongs to the transport's own TTFT/connect/idle timeouts,
## which are a separate and deliberately generous safety ceiling. A token count
## from the end of a request cannot be allowed to influence a timeout at its
## beginning.
##
## PROVENANCE OF THE CONSTANTS
##   development corpus   docs/results/bridge_timing_run1.json  (1,080 calls)
##   validation corpus    docs/results/bridge_timing_run2.json  (1,080 calls)
##   exact token source   stream_options.include_usage
##   selection            tools/health_harness.py
##
## Run 2 was used to choose 1.8 over 1.5, so it is a VALIDATION set, not an
## untouched final test set. The honest claim is "zero false positives on the
## corpora used to select and validate it", not "zero generalization error".
## A publication-grade estimate would need a run 3 that never touched the
## choice.
##
## WHY THESE NUMBERS
##   ks = 1.8   A candidate at 1.5 scored zero false positives on BOTH full
##              corpora and then produced 6-7 false positives when the
##              expectation was fitted on data the evaluation half had never
##              seen. 1.8 survived that same held-out test with zero.
##   kh = 20.0  Reserved for unambiguous catastrophe. The pathology actually
##              observed was 50-100x. A lone 5x transient must NOT trigger
##              recovery: a reload costs 2-9 s of unavailability plus pool
##              churn, and a single spike is not a persistent state.
##   n  = 3     The timing collection measured serial correlation directly and
##              found healthy jitter essentially independent (15 of 17 cells
##              showed no clustering beyond chance), while every observed
##              pathology was a persistent state lasting many calls. Three
##              consecutive breaches are unlikely by accident BECAUSE THAT WAS
##              MEASURED. n=2 is ruled out: a healthy run of six consecutive
##              above-p75 calls was observed.

const NORMAL := "NORMAL"
const SUSPECT := "SUSPECT"
const DEGRADED := "DEGRADED"
const CATASTROPHE := "CATASTROPHE"

## Piecewise expectation knots: [prompt_tokens, median_ttft_ms], uncontended.
##
## Sizes within 10% of each other are pooled into one knot. Without that, the
## SMALL bucket splits into token counts a few apart whose medians differ by
## sampling noise -- h2o at 59 tokens and 61 tokens gave 78.5 ms and 92.5 ms,
## a local slope of ~7 ms/token against a real 0.15. That is noise encoded as
## policy, and it makes the expectation jagged exactly where prompts are
## cheapest.
const KNOTS := {
	"falcon-h1-1.5b-instruct": [[58, 202.0], [804, 440.0], [6184, 1295.5]],
	"h2o-danube2-1.8b-chat": [[60, 92.0], [789, 188.0], [5829, 948.0]],
	"liquidai/lfm2.5-1.2b-instruct": [[47, 93.0], [597, 133.0], [4837, 423.0]],
}

## Measured multiplier when another request was in flight. Per model, because
## it varies: 1.16x to 1.48x across the three.
const CONTENTION := {
	"falcon-h1-1.5b-instruct": 1.4809,
	"h2o-danube2-1.8b-chat": 1.3339,
	"liquidai/lfm2.5-1.2b-instruct": 1.1579,
}

var ks: float = 1.8
var kh: float = 20.0
var streak_n: int = 3

## SHADOW MODE. Classifications are computed and recorded; recovery actions are
## suppressed. The policy runs against live traffic and is compared with the
## offline harness before it is allowed to unload anything.
var shadow: bool = true

var _streak: Dictionary = {}
var events: Array = []


## Expected TTFT for this model at this input size and load. Piecewise-linear
## between measured knots, clamped outside them -- behaviour far outside the
## measured range is not characterised and this does not pretend otherwise.
static func expected_ttft(model_id: String, prompt_tokens: int,
		load: int) -> float:
	var knots: Array = KNOTS.get(model_id, [])
	if knots.size() < 2:
		return -1.0
	var e := 0.0
	var first: Array = knots[0]
	var last: Array = knots[knots.size() - 1]
	if prompt_tokens <= int(first[0]):
		e = float(first[1])
	elif prompt_tokens >= int(last[0]):
		e = float(last[1])
	else:
		for i in knots.size() - 1:
			var a: Array = knots[i]
			var b: Array = knots[i + 1]
			if prompt_tokens >= int(a[0]) and prompt_tokens <= int(b[0]):
				var span := float(int(b[0]) - int(a[0]))
				var t := 0.0 if span == 0.0 else \
					float(prompt_tokens - int(a[0])) / span
				e = float(a[1]) + t * (float(b[1]) - float(a[1]))
				break
	if load >= 2:
		e *= float(CONTENTION.get(model_id, 1.0))
	return maxf(e, 1.0)


## Classify ONE COMPLETED call. Requires values that exist only at completion.
##
## Returns {verdict, residual, expected_ms, streak, actionable}. `actionable`
## is false in shadow mode even when the verdict is DEGRADED, so a caller can
## never accidentally act on a suppressed classification.
func classify(model_id: String, prompt_tokens: int, load: int,
		ttft_ms: int) -> Dictionary:
	var out := {"verdict": NORMAL, "residual": -1.0, "expected_ms": -1.0,
		"streak": 0, "actionable": false, "reason": ""}
	# No exact token count means no size-conditioned judgement. Guessing from
	# characters would reintroduce the tokenizer error the collection measured:
	# the same text is 4,837 tokens for lfm2.5 and 6,546 for falcon.
	if prompt_tokens < 0:
		out["reason"] = "no exact prompt_tokens; not classifiable"
		return out
	if ttft_ms < 0:
		out["reason"] = "no first-content TTFT; transport path owns this"
		return out
	var e := expected_ttft(model_id, prompt_tokens, load)
	if e <= 0.0:
		out["reason"] = "no expectation for model " + model_id
		return out
	var residual := float(ttft_ms) / e
	out["expected_ms"] = e
	out["residual"] = residual

	if residual >= kh:
		_streak[model_id] = 0
		out["verdict"] = CATASTROPHE
		out["actionable"] = not shadow
		out["reason"] = "residual %.1fx >= catastrophe %.1fx" % [residual, kh]
		_record(model_id, out)
		return out

	if residual >= ks:
		var n := int(_streak.get(model_id, 0)) + 1
		_streak[model_id] = n
		out["streak"] = n
		if n >= streak_n:
			_streak[model_id] = 0
			out["verdict"] = DEGRADED
			out["actionable"] = not shadow
			out["reason"] = "%d consecutive suspect calls" % n
		else:
			out["verdict"] = SUSPECT
			# A single spike is RECORDED and not recovered. Reloading on a lone
			# transient costs more than the transient did.
			out["reason"] = "residual %.2fx, streak %d of %d" % [
				residual, n, streak_n]
		_record(model_id, out)
		return out

	_streak[model_id] = 0
	return out


func _record(model_id: String, out: Dictionary) -> void:
	events.append({"model_id": model_id, "verdict": out["verdict"],
		"residual": out["residual"], "expected_ms": out["expected_ms"],
		"streak": out["streak"], "shadow": shadow,
		"at_ms": Time.get_ticks_msec()})


func reset() -> void:
	_streak.clear()
	events.clear()


func streak_for(model_id: String) -> int:
	return int(_streak.get(model_id, 0))


func summary() -> Dictionary:
	var by := {}
	for e in events:
		var v := str(e["verdict"])
		by[v] = int(by.get(v, 0)) + 1
	return {"shadow": shadow, "events": events.size(), "by_verdict": by}
