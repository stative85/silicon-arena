# Health Detector — Adversarial Harness Results

Candidate health rules attacked offline against measured traffic and injected
failure shapes. **No policy is frozen by this document.** It reports which
candidates survive and which break, so that choosing one is a separate,
deliberate act.

**Instrument:** `tools/health_harness.py`
**Corpora:** `bridge_timing_run1.json` (1,080 calls, prompt size approximated
from bucket) and `bridge_timing_run2.json` (1,080 calls, exact per-model
`prompt_tokens` from `stream_options.include_usage`).

## Why the flat tooth had to go, restated precisely

`TTFT > 1500 ms` is not merely mis-sized. It is **structurally blind**.

```
DETECTOR                  FP/1080   persist x4   persist x2   spike   gradual   wedge
D1 flat global 1500ms      90 (8.3%)     -            -          -        -      0.0
D2 flat per-model           0 (0.0%)     -            -          -        -      0.0
```

The flat tooth fires on 8.3% of healthy traffic **and detects none of the
degradation shapes** except a total wedge. LFM2.5 degraded 4x on a small prompt
is 308 ms — invisible. Healthy falcon on a large contended prompt is 1,780 ms —
flagged. It gets both errors at once.

Making the threshold per-model removes the false positives and keeps the
blindness: 0 FP, still detects nothing but the wedge. **No absolute threshold
can work**, because the quantity that varies most is input size.

## Exact tokens matter more than expected

Run 2 records the model's own tokenizer count. The same LARGE prompt is:

```
lfm2.5  4,837 tokens     h2o  5,829     falcon  6,546
```

A 35% spread on identical text. Run 1's bucket approximation (3,455 for all
three) was off by 40-90%, and the fitted per-token costs changed accordingly
(falcon 0.333 -> 0.178 ms/tok). Character counts are not interchangeable across
tokenizers, and a size-conditioned detector must use the model's own count.

## The expectation model

```
expected_ttft(model, tokens, load)
    = piecewise_linear(tokens through measured size knots)
      x contention_factor   if load >= 2

health_ratio = observed_ttft / expected_ttft
```

**Piecewise, not a straight line.** A two-point fit through the endpoints
carries falcon's mid-range superlinearity into the residuals: healthy falcon
MEDIUM sat at residual median 1.30 with a max of 4.18. That is fit error
masquerading as unhealthiness, and it would spend the detector's whole error
budget on a deficiency of the model rather than on real pathology. Interpolating
through all three measured sizes puts every cell median at ~1.00.

Fitted on run 2 (exact tokens):

```
          intercept   per token    contention
falcon      192 ms    0.17847 ms      1.48x
h2o          70 ms    0.15069 ms      1.33x
lfm2.5       90 ms    0.06889 ms      1.16x
```

Healthy residual dispersion overall: median 0.99, p99 1.60, max 4.37.

## The held-out test changed the answer

The candidate chosen on run 1 was `ks=1.5, kh=20, n=3`. It scored 0 false
positives on run 1 and 0 on run 2. It **failed** when the expectation was
fitted on data the evaluation half had never seen:

```
                                  run1    run2    HELD-OUT (fit on 1st half,
                                                   evaluated on 2nd)
ks=1.5  kh=20  n=3  PW              0       0        7   (1.30%)
ks=1.8  kh=20  n=3  PW              0       0        0
ks=1.8  kh=20  n=4  PW              0       0        0
D1 flat global 1500 ms             88      90       90  (16.7%)
```

`ks=1.5` was overfit to run 1's expectation. It also began firing on single
spikes in held-out mode. Choosing and validating on the same corpus would have
shipped it.

## Surviving candidate

```
ks = 1.8    suspect when observed / expected > 1.8
kh = 20.0   immediate action on unambiguous catastrophe
n  = 3      consecutive suspect calls before DEGRADED
expectation piecewise, per-model, contention-adjusted
```

Behaviour against injected failure shapes (calls after onset; held-out mode):

```
persistent x4     2.0
persistent x2     3.7
single spike      does not fire      <- correct
gradual decay     4.3
wedge             0.0 (immediate)
recovery x4       2.0
```

**Not firing on a single spike is a pass, not a miss.** A lone transient is not
a persistent state, and a reload costs 2-9 s of unavailability plus pool churn.
`kh = 20` reserves immediate action for the unambiguous: the pathology actually
observed was 50-100x, so 20x is well clear of both healthy jitter and the
2-5x degradations the streak is there to catch.

`n = 4` also survives with zero false positives but detects strictly slower
(3.0 / 4.7 / 5.3 against 2.0 / 3.7 / 4.3) for no reduction in false positives,
so `n = 3` is preferred on this evidence.

## Why a streak works here

The timing collection measured serial correlation directly: **15 of 17 cells
showed no clustering of slow calls beyond chance**. Healthy jitter is
essentially independent, so three consecutive breaches are unlikely by accident
— while every pathology observed in the external benchmark was a persistent
state lasting many calls. The streak is not a smoothing hack; it exploits a
measured difference between how healthy noise and real degradation behave.

A caution against `n = 2`: a healthy run of six consecutive above-p75 calls was
observed. Above-p75 is a looser definition of "slow" than a 1.8x residual, but
it is enough to show that short streaks occur naturally.

## Scoring asymmetry, stated

A false positive costs a reload — seconds of unavailability plus pool churn — 
and a detector that thrashes is worse than no detector. A missed degradation
costs latency until the next breach. False positives are therefore treated as
the more serious error, and any candidate with non-zero healthy false positives
is disqualified before detection latency is even considered.

## Limits

- Two collections, one machine, one runtime, one quantisation, one context
  length, `max_active = 2`.
- Three prompt sizes, not a continuum. The piecewise model interpolates between
  them and clamps outside them; behaviour far outside the measured range is
  not characterised.
- The contention factor is a single per-model median across sizes. Some cells
  show it is size-dependent (falcon MEDIUM load=2 residual median 0.73,
  lfm2.5 LARGE load=2 at 1.39), so the factor is an approximation.
- Injected failures are synthetic multiplications of real healthy calls. They
  reproduce the observed *shapes*, not the underlying mechanism.
- Nothing here has run against a genuinely degraded model in production.

## Not done

Freezing this into `BridgePolicy` and wiring it into the bridge's health path
is the next step and is deliberately not taken here.
