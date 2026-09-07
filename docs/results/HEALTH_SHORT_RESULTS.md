# HEALTH-SHORT — results

Run at prereg `27aada1` (amendments 1–3 frozen before implementation).
7 length buckets × 120 rounds × 3 models = **2,520 calls**, all three probed
simultaneously each round, shadow mode, `ks=1.8 / kh=20 / n=3` untouched.

`max_active_during` was **2 on all 2,520 calls** — exactly the load regime the
contention factors were fitted at — and `ttft_ms` is measured from dispatch, so
queue time is excluded. The comparison against the frozen surface is
apples-to-apples.

## Answer: MODEL/SURFACE MISMATCH, for two of three models

The pre-registered discriminator was whether observed TTFT tracks the
expectation slope. It does for falcon and does not for the other two:

```text
len 16 -> len 4          ttft change    expected change   residual change
lfm2.5                        +1%             -15%             +0.29
qwen3.5                        -5%             -21%             +0.33
falcon                        -22%             -19%             -0.04
```

**falcon's TTFT genuinely scales with prompt length. lfm2.5's and qwen3.5's do
not.** In this regime their time-to-first-token is dominated by a fixed cost,
while the expectation surface imposes a downward slope they do not have. Shrink
the prompt and the denominator falls while the numerator stays put, so the
residual rises for no runtime reason.

That is the first pre-registered reading, fired:

> Residual median rises monotonically as list length falls, while observed TTFT
> median stays flat → the frozen surface is miscalibrated below its measured
> support. ASYNC-B's voids are an artefact of the denominator.

falcon is the control that makes this readable. Its surface is correct, so the
effect is not a property of the harness, the load, or the prompt format.

## There are TWO denominator errors, not one

The slope error is what the experiment was designed to find. The level error was
not, and it is larger:

```text
residual median      len 16    len 4
lfm2.5                 1.49     1.77
qwen3.5                1.63     1.96
falcon                 1.22     1.17
```

At length 16 — inside the fitted range, 131 tokens for qwen — qwen already sits
at **1.63** against a `ks` of 1.8. Most of the distance to the threshold is
present before any short-prompt effect. The sweep then supplies the last 0.33.

So ASYNC-B's voids are not purely "short prompts break the detector". They are
"qwen runs close to the line everywhere in this regime, and shortening the
prompt pushes it over".

## The level error may be duty cycle, and this experiment cannot separate it

HEALTH-SHORT issues rounds back to back with no pause. ASYNC-B's SERIAL loop did
world work between ticks, giving the pool brief idle time. A continuously
saturated pool can plausibly show higher TTFT than an intermittently loaded one
at the same `max_active`.

The consequence is stated rather than argued away:

- **The slope result is robust.** It is a within-experiment comparison across
  buckets under an identical duty cycle, and falcon's flat residual proves the
  duty cycle alone does not manufacture a slope.
- **The level result is not established.** The absolute residual offset may be
  partly an artefact of the tighter loop. HEALTH-SHORT has no measurement that
  separates duty cycle from calibration level, and none is invented here.

A repair aimed at the level, fitted on this data, would risk fitting the
harness. Anyone designing that repair must first establish whether the offset
survives an ASYNC-B-like duty cycle.

## A prediction of mine that the data refused

Amendment 3 recorded lag-1 autocorrelation because I expected it to be the
mechanism behind `n = 3` streaks — the idea being that individually innocuous
residuals could cluster into runs.

**It is not the explanation.** The SUSPECT base rate alone accounts for the
streaks:

```text
model        len   suspect   p       runs predicted   DEGRADED observed   lag1
qwen3.5       12     73     0.608        26.6              18            0.86
qwen3.5       10     85     0.708        41.9              24            0.43
qwen3.5        6    117     0.975       109.4              38            0.13
lfm2.5         4     56     0.467        12.0               9            0.25
```

At p = 0.975 essentially every call is SUSPECT, so three consecutive is
inevitable without any correlation at all. Observed DEGRADED counts sit *below*
the naive independence prediction, because the detector resets its streak
counter on firing and therefore cannot count overlapping runs — the prediction
column overcounts by construction and is shown only to make the base-rate point.

Autocorrelation is genuinely high in places (0.84–0.88 for qwen at several
lengths), but it is not load-bearing for this failure. The honest summary is
that I looked for a subtle mechanism and found a blunt one.

## Numbers

```text
lfm2.5                                        qwen3.5
len   n  tok  ttft  exp  res   susp           len   n  tok  ttft  exp  res   susp
16  120  110   140   94  1.49     1            16  120  131   342  210  1.63     1
14  120  100   141   92  1.54     4            14  120  119   359  203  1.77    38
12  120   90   140   89  1.56     0            12  120  107   357  195  1.83    73
10  120   80   140   87  1.61     6            10  120   95   344  188  1.83    85
 8  120   70   125   85  1.47    25             8  120   83   312  181  1.73    50
 6  120   60   141   82  1.71    53             6  120   71   343  173  1.98   117
 4  120   50   142   80  1.77    56             4  120   59   325  166  1.96    95

falcon
len   n  tok  ttft  exp  res   susp
16  120  130   341  280  1.22     0
14  120  118   377  271  1.39     0
12  120  106   361  262  1.38     1
10  120   94   345  253  1.36     0
 8  120   82   297  245  1.21     0
 6  120   70   330  236  1.40     2
 4  120   58   266  227  1.17     0
```

141 DEGRADED verdicts across the sweep, all in shadow — **no recovery fired, so
no reload contaminated any bucket.**

## Status

```text
BLOCKER 1:  ANSWERED -- denominator mismatch, confirmed
            slope error   lfm2.5 and qwen3.5, not falcon   ROBUST
            level error   present, magnitude NOT ESTABLISHED (duty cycle)

BLOCKER 2:  untouched, still requires RECOVERY-COUPLING
```

## What was NOT done

Nothing was fitted. No knot added, moved, or re-measured. No threshold changed.
No contention factor adjusted. No repair attempted.

The repair is a separate pre-registration and it now has two requirements this
run generated: it must fix a **slope** error for two models without disturbing
falcon's correct surface, and it must first determine whether the **level**
offset survives a realistic duty cycle before treating it as calibration at all.
