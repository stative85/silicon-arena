# Bridge Health Policy — FROZEN

**Status:** frozen and implemented, running in **shadow mode**
**Code:** `scripts/arena/bridge_health.gd`
**Tests:** `scripts/arena/bridge_selftest.gd` — 110 checks including five
sabotage teeth and a 1,080-vector agreement test against the offline harness

## The policy

```
EXPECTED_TTFT = piecewise_expectation(model_id, prompt_tokens, load_condition)
residual      = observed_ttft / EXPECTED_TTFT

SUSPECT            residual >= 1.8
HARD_CATASTROPHE   residual >= 20.0
DEGRADED           3 consecutive SUSPECT completed calls
SINGLE SPIKE       recorded, NOT recovered
WEDGE              transport connect/TTFT/idle timeout path, separate
```

The bridge now measures something more useful than "slow":

> **unexpectedly slow for this model, this input, under this load, repeatedly.**

## What it replaces, and why

`TTFT > 1500 ms` was not mis-sized. It was **structurally blind** — it managed
to flag healthy falcon while missing degraded LFM2.5:

```
DETECTOR                  FP/1080     persist x4   persist x2   spike   gradual   wedge
flat global 1500 ms       90 (8.3%)       -            -          -        -      0.0
flat per-model             0 (0.0%)       -            -          -        -      0.0
FROZEN 1.8 / 20 / 3        0 (0.0%)      2.0          3.7         -       4.3     0.0
```

LFM2.5 degraded 4x on a small prompt is 308 ms — invisible to any absolute
threshold. Healthy falcon on a large contended prompt is 1,780 ms — flagged by
one. No absolute threshold can work, because the quantity that varies most is
input size.

## Frozen constants

```
ks = 1.8      kh = 20.0      n = 3

model                            knots [prompt_tokens, median_ttft_ms]         contention
falcon-h1-1.5b-instruct          [58, 202.0] [804, 440.0] [6184, 1295.5]         1.4809
h2o-danube2-1.8b-chat            [60,  92.0] [789, 188.0] [5829,  948.0]         1.3339
liquidai/lfm2.5-1.2b-instruct    [47,  93.0] [597, 133.0] [4837,  423.0]         1.1579
```

Sizes within 10% of each other are pooled into one knot. Without that, the
SMALL bucket splits into token counts a few apart whose medians differ by
sampling noise — h2o at 59 and 61 tokens gave 78.5 ms and 92.5 ms, a local
slope of ~7 ms/token against a real 0.15. That is noise encoded as policy.

## Why these numbers

**`ks = 1.8`.** A candidate at 1.5 scored zero false positives on *both* full
corpora, then produced 6-7 false positives once the expectation was fitted on
data the evaluation half had never seen — and began firing on single spikes.
1.8 survived the same held-out test with zero.

**`kh = 20.0`.** Reserved for unambiguous catastrophe. The pathology actually
observed was 50-100x. A lone 5x transient must **not** trigger recovery: a
reload costs 2-9 s of unavailability plus pool churn, and a single spike is not
a persistent state.

**`n = 3`.** The timing collection measured serial correlation directly and
found healthy jitter essentially independent — 15 of 17 cells showed no
clustering beyond chance — while every observed pathology was a persistent
state lasting many calls. Three consecutive breaches are unlikely by accident
*because that was measured*, not assumed. `n = 2` is ruled out: a healthy run of
six consecutive above-p75 calls was observed. `n = 4` also survives with zero
false positives but detects strictly slower for no benefit.

## The causality rule

Exact `prompt_tokens` arrives in the server's **usage frame at stream
completion**. This detector is therefore a **post-call classifier and nothing
else.**

It must never be consulted to decide whether a call should have been abandoned
earlier. That decision belongs to the transport's own connect / TTFT / idle
timeouts, which are a separate and deliberately generous safety ceiling. A
token count from the end of a request cannot be allowed to influence a timeout
at its beginning.

Enforced in code: `classify()` refuses to judge when `prompt_tokens < 0`
(returning NORMAL with a reason) rather than falling back to a character
estimate, and refuses when `ttft_ms < 0`, deferring explicitly to the transport.
Both are tested.

## Provenance

```
development corpus    docs/results/bridge_timing_run1.json   1,080 calls
validation corpus     docs/results/bridge_timing_run2.json   1,080 calls
exact token source    stream_options.include_usage
selection instrument  tools/health_harness.py
policy                ks = 1.8, kh = 20.0, n = 3
expectation           piecewise / per-model / contention-conditioned
```

**A statistical caveat, stated plainly.** Run 2 was used to choose 1.8 over 1.5,
so it is a **validation set, not an untouched final test set**. The honest claim
is *"zero false positives on the corpora used to select and validate it"*, not
*"zero generalization error"*. A publication-grade estimate would need a run 3
that never touched the choice. This is adequate for shipping an engineering
health policy and is not adequate for a generalization claim.

## The tokenizer finding

The same LARGE text is **4,837 tokens for lfm2.5, 5,829 for danube2, and 6,546
for falcon** — a 35% spread. One shared "prompt size" estimate was never going
to be trustworthy, and character counts are not interchangeable across
tokenizers. This is why `classify()` refuses rather than estimating when the
exact count is missing.

## Sabotage teeth

Five, each asserting the sabotage applied before checking its consequence:

```
1  ks -> 1.5                  flags a 1.6x call that 1.8 calls normal
2  n -> 1                     wrongly recovers on a single transient spike
3  remove size conditioning   healthy LARGE condemned, degraded SMALL missed
4  remove load conditioning   inflates residuals of healthy contended traffic
5  bucket-estimated tokens    shifts the expectation materially vs exact
```

Plus a **1,080-vector agreement test**: the GDScript implementation must produce
the same expectation and the same verdict as the Python harness that chose the
policy, on every vector. Otherwise the evidence belongs to a different rule than
the one actually running.

## Shadow mode

`BridgeHealth.shadow` defaults to **true**. Classifications are computed and
recorded; `actionable` is forced false, so no recovery can fire. Verified live:
six real calls classified NORMAL with residuals 0.41-1.22 and zero events.

Enabling recovery is a one-line change (`health.shadow = false`) and should
follow a period of shadow operation confirming the classifications match
expectations on real arena traffic.

## Limits

- Two collections, one machine, one runtime, one quantisation, context 8192,
  `max_active = 2`. Three-way concurrency is not characterised.
- Three prompt sizes, not a continuum. The expectation interpolates between
  knots and **clamps outside them**. Below the smallest knot the expectation is
  generous — live arena prompts of 20-22 tokens sit under the 47-60 token floor
  and score residuals of 0.4-0.7 — which errs toward not firing.
- The contention factor is one per-model median across sizes; some cells show
  it is size-dependent.
- Injected failures are synthetic multiplications of real healthy calls. They
  reproduce the observed *shapes*, not the underlying mechanism.
- The policy has never run against a genuinely degraded model in production.
  That is what shadow mode is for.
