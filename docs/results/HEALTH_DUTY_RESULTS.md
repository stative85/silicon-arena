# HEALTH-DUTY — results: fourth branch, FIT NOTHING

Run at prereg `fa560fb` + Amendment 1 `0efe4fd`. 3 prompt regimes x 2 session
structures, 120 rounds each, all three models probed simultaneously, shadow
mode, `ks=1.8 / kh=20 / n=3` untouched. 1,080 rounds, 3,240 calls.

## The pre-registered fourth reading fired

```text
Neither arm reproduces ASYNC-B cell A's near-zero SUSPECT rate at length 10
  -> some other production-state variable is missing; FIT NOTHING
```

```text
qwen3.5 at length 10, three independent measurements
  long_desc    residual 1.77   SUSPECT 48%   DEGRADED 15
  long_asc     residual 1.67   SUSPECT 13%   DEGRADED  1
  cell_10      residual 1.82   SUSPECT 69%   DEGRADED 22

ASYNC-B cell A, mean length 9.96, ~1,600 qwen calls
                                  SUSPECT  unknown   DEGRADED  0
```

`CELL_LIKE` did not lower the SUSPECT rate. It produced the **highest** rate of
the three. The client-session hypothesis is not supported, and the anchor
contradiction is unexplained.

**No surface may be fitted.** That was written into the prereg before any call
precisely so it could not be skipped now.

## What IS confirmed, for the third independent time

The low-end slope. It appears in every arm, at every execution position:

```text
qwen3.5   residual len16 -> len4
  long_desc   1.55 -> 1.88   (+0.33)
  long_asc    1.69 -> 1.95   (+0.26)
  cell        1.78 -> 1.96   (+0.18)

lfm2.5    residual len16 -> len4
  long_desc   1.48 -> 1.77   (+0.29)
  long_asc    1.51 -> 1.76   (+0.25)
  cell        1.49 -> 1.87   (+0.38)
```

falcon, the control, over all 1,080 of its calls:

```text
residual range 1.11 - 1.35        SUSPECT total: 0
```

Zero SUSPECT verdicts in the entire experiment, across every length, every
session structure and every execution position. Whatever moves qwen and lfm2.5
is model-specific and is not the harness.

## MY DESIGN ERROR: the arms are confounded with wall clock

The orchestrator ran `long_desc, long_asc, cell_16, cell_10, cell_04` in that
order — both LONG arms first, then all three CELL arms. So session structure is
collinear with position in the experiment.

**This is the same class of mistake as HEALTH-SHORT's descending sweep, which I
had flagged one experiment earlier.** Recorded, not excused. The level
comparison between arms is therefore **not attributable**, and no level claim is
made from it.

The interleaved schedule that would have avoided it is obvious in hindsight and
is the first thing a follow-up must fix.

## A drift signal, IMPLICATED not established

At **fixed length 16**, across increasing wall-clock position:

```text
qwen3.5 len 16      residual   SUSPECT
  long_desc  t+0.0     1.55        2%
  long_asc   t+4.2     1.69        5%
  cell_16    t+5.7     1.78       45%

falcon  len 16
  long_desc  t+0.0     1.12        0%
  long_asc   t+4.2     1.22        0%
  cell_16    t+5.7     1.23        0%
```

Length is held constant here, so this is not the slope effect. Over roughly six
minutes of continuous operation qwen's SUSPECT rate at an unchanged prompt size
went from 2% to 45%, while falcon barely moved and never once fired.

**This is implicated, NOT established.** The three len-16 observations sit in
three different arms — `long_desc`, `long_asc`, `cell_16` — so arm and wall
clock advance together even with length pinned. Holding one variable constant
did not clean the comparison; it only removed the variable that was already
understood. The correct claim is:

> model/runtime history is **implicated**

and not:

> model/runtime history **caused** it

`CELL_LIKE` resets the client and cannot touch LM Studio process lifetime, cache
state, resident duration or GPU scheduling, so the null client-session result is
consistent with the cause living in that half. Consistent is not demonstrated.

So the null client-session result and this drift are consistent: the experiment
manipulated the wrong half of the bundle. That is a useful negative, and it was
only interpretable because the two histories were separated in advance.

## Leading candidate for the anchor contradiction — UNTESTED

Both health harnesses generate a **fresh random subset every round**, a decision
made deliberately to prevent prefix-cache hits from making calls artificially
fast.

Production does the opposite. In ASYNC-B the visible list is the world's
available set, which changes by only one or two resources per tick, so
consecutive prompts share long prefixes.

If prefill dominates TTFT for qwen and lfm2.5 but not falcon, then:

```text
production   slowly-evolving list -> long shared prefixes -> cache hits -> low TTFT
harness      fresh random subset  -> no shared prefix     -> full prefill -> high TTFT
```

That would make the anti-cache decision the thing that made the harness
systematically **slower than production**, and would explain cell A directly.

### TESTED AND FALSE — killed before HEALTH-PREFIX was built

The hypothesis was checkable after all, from the Cell-A fossils, without a
single model call. It is **wrong**:

```text
Cell-A consecutive prompts, 8 non-void seeds, 200 rounds each
  longest common prefix, median          25 characters
  the string "Available resources:
  r_" is exactly  25 characters
  consecutive rounds sharing the same first item      0.0%
```

An LCP of 25 is the fixed header plus the start of the first id, so **production
shared no content prefix at all.** The first item changed on literally every
round. Both harnesses and production had the same near-zero prefix continuity,
so the anti-cache decision removed nothing production was receiving.

A second cache route also fails. Cell A's 200 rounds contain only **~10 distinct
prompts** (94.9% duplicates), which looks like a large exact-match cache
opportunity — but the duplicates are never consecutive:

```text
consecutive-identical rounds                    0.0%
gap to the previous identical prompt   median 4, minimum 4
```

Every repeat is at least four rounds away, and three other prompts are issued to
that model in between. A single KV context per model is evicted long before the
repeat arrives.

**HEALTH-PREFIX is therefore not built.** Its manipulation check would have
failed as NOT EXERCISED: P and X have the same prefix continuity because P has
none. That is 9,600 calls not spent.

### An unexpected fact about the world, not the detector

`gap = 4` with a minimum of 4 is not coincidence: `hold_ticks = 4`. ASYNC-B cell
A was running a **near-periodic world** — roughly ten distinct availability
configurations cycling on the hold period, across all 200 ticks. That is a
property of the world's parameters, recorded here because it was discovered
while chasing something else and belongs with the ASYNC results rather than in
anyone's memory.

## Status

```text
SLOPE ERROR        CONFIRMED x3, robust across arms and positions
LEVEL OFFSET       STILL UNRESOLVED; this run's arms are confounded with
                   wall clock by my own scheduling error
CLIENT SESSION     not supported as the explanation
RUNTIME HISTORY    implicated, not established; never manipulated, and the
                   fixed-length comparison is still entangled with arm order
ANCHOR FACT        still unexplained
REPAIR             forbidden by the frozen fourth reading
```

Nothing was fitted. No knot, threshold, or contention factor was touched. No
`OUT_OF_PROFILE` implementation. No RECOVERY-COUPLING. No ASYNC-B2.
