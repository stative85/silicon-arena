# Bridge Timing — Findings

**These findings describe COLLECTION 1** (`bridge_timing_run1.json`), taken
before prompt-size telemetry existed, so its prompt sizes are approximated from
bucket. Collection 2 added exact per-model `prompt_tokens` and its numbers
differ — see `HEALTH_DETECTOR_HARNESS.md`. The conclusions below about the
1500 ms tooth hold in both runs (88 and 90 false positives respectively).

Interpretation of the timing collection. That file is machine-generated data;
this one is the reading of it, kept separate so regenerating the data cannot
silently rewrite the conclusions.

**Collection:** 1,080 calls in 990 s, bridge v1 streaming path,
`EXPLICIT_RESIDENCY_MODE`, hot set lfm2.5 + danube2 + falcon, context 8192,
Q4_K_M, `max_active = 2`. Regime frozen throughout: no swapping, no policy
tuning, no band changes mid-run. 60 samples per model × bucket × load cell.

## The headline: the global TTFT tooth is wrong for realistic prompts

`HARD_DEGRADED = TTFT > 1500 ms` was derived from the external benchmark, whose
prompts were small. Against realistic arena-sized observations it fires on
**healthy** behaviour:

```
falcon  LARGE  load=2    58 of 60 healthy calls exceeded 1500 ms   (97%)
h2o     LARGE  load=2    30 of 60 healthy calls exceeded 1500 ms   (50%)
falcon  LARGE  load=1    p99 1476 ms, max 1481 ms — at the ceiling
```

Uncensored, falcon's LARGE contended median is **1,780 ms**. The current tooth
sits *below the median* of that cell. In normal arena operation it would
declare a healthy model degraded and trigger continuous reload thrashing —
precisely the failure mode the hysteresis was built to avoid, arriving through
the health path instead.

This also right-censors the measurement: because the healthy-baseline filter
uses the same 1500 ms threshold, the cells that most need characterising had
their upper tails removed. Those cells are marked `CENSORED` in the data file
and their p95/p99 are lower bounds, not estimates.

## 1. What is normal TTFT for each model?

Uncontended medians:

```
              SMALL    MEDIUM    LARGE
lfm2.5          77       106       419
danube2         90       152       946
falcon         187       367     1,335
```

Healthy dispersion is tight. p99/median across all uncontended cells is
1.09-1.73, the single widest being falcon MEDIUM (one 1,177 ms outlier against
a 367 ms median).

## 2. How much does prompt size move normal?

**It dominates everything else.** SMALL → LARGE multiplies TTFT by 5.4x
(lfm2.5), 10.5x (danube2), 7.1x (falcon).

TTFT is well described by a two-parameter linear model:

```
TTFT ≈ intercept + prompt_tokens × per_token_cost

lfm2.5     76 ms + 0.0990 ms/tok    10,103 tok/s prefill
danube2    87 ms + 0.2480 ms/tok     4,032 tok/s
falcon    184 ms + 0.3328 ms/tok     3,005 tok/s
```

Fitted on SMALL and LARGE only, then checked against the held-out MEDIUM cell:

```
            observed   predicted   ratio
lfm2.5           106         105    1.00
danube2          152         160    0.95
falcon           366         282    1.30
```

Two of three predict the held-out point within 5%. Falcon is superlinear in the
middle of the range and the linear model understates it there — worth noting
rather than smoothing over, since a band built on this model would be loosest
exactly where falcon is slowest.

TTFT is therefore mostly a **prefill measurement**, and prefill scales with
prompt size. A flat threshold across prompt sizes is measuring the wrong thing.

## 3. How much does two-way concurrency move normal?

```
             SMALL   MEDIUM   LARGE
lfm2.5       1.29x    1.60x   1.45x
danube2      1.12x    1.47x   1.48x
falcon       1.47x    1.33x   1.33x
```

Between 1.12x and 1.60x — real, consistent, and **far smaller than the effect
of prompt size**. Concurrency is a modest multiplier; prompt size is an order
of magnitude.

Queue delay was ~0 ms in every cell, as expected: `max_active = 2` and the
driver submitted at most two at a time, so nothing waited. Queue delay under
genuine oversubscription is not characterised here.

## 4. Isolated spikes, or persistent regimes?

**15 of 17 cells show no clustering beyond chance.** Comparing the observed
longest run of consecutive above-p75 calls against 200 shuffles of the same
values, only two cells came in under p < 0.05 (danube2 MEDIUM load=1 at p=0.000,
danube2 LARGE load=1 at p=0.005).

So within the *healthy* envelope, slow calls are essentially independent —
ordinary jitter, not a state the model enters and stays in.

This does **not** contradict the external benchmark's persistent regimes. Those
were pathological states (qwen at 2.4 tok/s across five consecutive cases), and
pathological calls are excluded from this dataset by construction. The correct
reading is narrower and more useful:

> Healthy jitter does not cluster. Pathology did. That difference is what makes
> "N consecutive suspect calls" a usable discriminator.

One caution against setting N too low: a healthy run of 6 consecutive above-p75
calls did occur (danube2 LARGE load=1). Above-p75 is a deliberately loose
definition of "slow"; a SUSPECT band set at the p99 of a size-conditioned
expectation would make consecutive breaches far rarer. But N = 2 would clearly
false-positive on this evidence.

## What this implies for the bands — proposal, not yet implemented

The measured structure says a flat TTFT threshold cannot work, because the
dominant term is prompt size. The natural replacement:

```
expected_ttft(model, tokens, load)
    = (intercept[model] + tokens × per_token_cost[model])
      × (contention_factor if load >= 2 else 1.0)

SUSPECT         actual > expected × k_suspect
HARD_DEGRADED   actual > expected × k_hard
```

with `k_suspect` chosen above the observed healthy dispersion (p99/median tops
out at 1.73, so something near 2.5x is clear of it) and `k_hard` well above
that. Recovery should require consecutive breaches rather than one.

**This requires a receipt field that does not exist yet:** prompt size. The
bridge currently records no measure of how much input a call carried, so a
size-conditioned expectation cannot be evaluated at runtime. That is the first
change, and it is a measurement addition, not a policy change.

**Deliberately not decided here:** the exact multipliers, the contention factor,
and the consecutive-breach count. Those want a negative test — synthetic
degraded calls injected against these bands to confirm they fire, and healthy
replay to confirm they do not. Choosing them now, from three fitted lines and
one collection run, would be the same mistake at a higher resolution.

## Regime limits

- One machine, one runtime, one quantisation, one context length.
- `max_active = 2` only. Three-way concurrency is not characterised.
- Prompt sizes are three fixed shapes, not a continuum.
- The LARGE contended cells are right-censored by the very threshold under
  review, so their upper tails are unmeasured.
- Every prompt was unique to defeat prefix caching. Real arena traffic may
  share prefixes across cycles, in which case cached prefill would be faster
  than anything measured here.
