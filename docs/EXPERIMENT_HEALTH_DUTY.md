# HEALTH-DUTY — is the absolute residual level a harness artefact?

**Status:** pre-registered before implementation, model calls, or outcomes.

Sole question:

> Is the absolute residual level shift caused by sustained operation, and does
> it interact with the already-confirmed short-prompt slope defect?

No fitting. Still shadow. Same entire resident pool. No surface change.

## What HEALTH-SHORT settled and what it did not

```text
1. LOW-END SLOPE ERROR        CONFIRMED   (lfm2.5, qwen3.5; falcon is the control)
2. ABSOLUTE LEVEL OFFSET      UNRESOLVED
3. STREAK / AUTOCORRELATION   NOT THE CAUSE
```

## The anchor fact this experiment must explain

ASYNC-B cell A had a mean visible list of **9.96** and **never voided** across
8 cells x 200 ticks — roughly 1,600 qwen calls with zero DEGRADED.

HEALTH-SHORT at length 10 measured qwen at **p(SUSPECT) = 0.708**.

At that rate, three consecutive SUSPECT is effectively certain, so cell A should
have voided repeatedly and did not. **Something material differs between the two
harnesses at the same nominal prompt size and the same `max_active_during = 2`.**
Identifying it is the point of HEALTH-DUTY.

## CORRECTION: the second factor is SESSION, not cadence

The originally proposed factor was `SATURATED` vs `B-LIKE` inter-request
cadence. Derived mechanically from the frozen runner rather than assumed, that
factor is **empty**:

- `tools/async_b_cell.gd` has no wall-clock pacing. Each tick observes, submits
  three requests, awaits all completions, applies, advances. The world work
  between rounds is microseconds of GDScript against ~350 ms of inference.
- Measured from the ASYNC-B artifacts: median **149.2 s per cell** including
  ~15 s of baseline and engine boot, over 200 ticks — about **671 ms per tick**,
  which is what three calls at `max_active = 2` cost back to back.

ASYNC-B was therefore already saturated at the round level. A `SATURATED` vs
`B-LIKE` pacing contrast would compare saturated against saturated and answer
nothing.

What actually differs between HEALTH-SHORT and an ASYNC-B cell is **session
structure**:

```text
HEALTH-SHORT    840 rounds, ONE process, no teardown, no baseline between
ASYNC-B cell    200 rounds, FRESH process, arm_baseline before each
```

So factor 2 is redefined, mechanically, as:

```text
LONG_CONTINUOUS   all prompt regimes in one long process, HEALTH-SHORT style
B_LIKE            one prompt regime per FRESH process, 200 rounds,
                  arm_baseline before it, exactly as a B cell runs
```

`B_LIKE` is defined by reproducing the runner's actual session semantics. No
delay is invented, tuned, or chosen to make any model look healthy.

## SECOND CORRECTION: HEALTH-SHORT confounded length with elapsed time

HEALTH-SHORT swept 16, 14, 12, 10, 8, 6, 4 in descending order, so "shorter
prompt" and "later in the run" were the same variable. That is a design defect
and it is recorded rather than excused.

Evidence it did **not** drive the result, gathered after the fact:

- Within-bucket drift (first 30 vs last 30 rounds of each 120) is small and
  non-systematic, deltas from -0.17 to +0.17 with no consistent sign.
- falcon shows no across-bucket drift (1.22 at length 16, 1.17 at length 4)
  while sharing the identical timeline.

That makes a pure time explanation unlikely but does not eliminate it.
HEALTH-DUTY therefore **counterbalances prompt-regime order**: the
`LONG_CONTINUOUS` arm runs once ascending and once descending, and the `B_LIKE`
arm gets a fresh process per regime so ordering cannot accumulate at all.

## Design

```text
PROMPT REGIME     16   10   4          (10 sits where ASYNC-B actually lived)
        x
SESSION REGIME    LONG_CONTINUOUS   B_LIKE

pool              LFM2.5 + Qwen3.5 + Falcon, explicit residency, unchanged
health            shadow, ks=1.8 / kh=20 / n=3 untouched
schema            unchanged one-field async_action
max_tokens 24, temperature 0
all three models probed SIMULTANEOUSLY each round (HEALTH-SHORT Amendment 1)
rounds            120 per regime per arm
order             LONG_CONTINUOUS run twice: 16,10,4 and 4,10,16
```

**Matched prompt material.** The visible list for round *i* at length *L* is
generated from the same frozen key in both arms, so the two session regimes see
byte-identical prompt sequences. Any difference is session, not content.

## Pre-registered readings

```text
B_LIKE lowers the whole residual curve but the short-prompt slope remains
  -> sustained operation caused the level offset;
     the low-end surface slope is still genuinely wrong

B_LIKE leaves the elevated level intact and the slope remains
  -> both level and low-end slope require repair

B_LIKE removes the slope too
  -> the prompt-size error is actually a session x prompt-size interaction

Neither arm reproduces ASYNC-B cell A's near-zero SUSPECT rate at length 10
  -> some other production-state variable is missing; FIT NOTHING
```

The fourth reading is a real possibility and is written down first so it cannot
be quietly skipped later. If `B_LIKE` at length 10 still shows a high SUSPECT
rate, the anchor fact remains unexplained and no repair may be designed.

## Analysis

Reported per model x prompt regime x session regime: n, median and p95 observed
TTFT, median expected, median and p95 residual, SUSPECT rate, DEGRADED count.

```text
LEVEL EFFECT       residual(B_LIKE) - residual(LONG_CONTINUOUS)  at each length
SLOPE EFFECT       residual(len 4) - residual(len 16)            within each arm
INTERACTION        slope(LONG_CONTINUOUS) - slope(B_LIKE)
```

Falcon is carried through everything as the control. A manipulation that moves
falcon is moving the harness, not the calibration.

## Void conditions

```text
pool not exactly the frozen three at start or end   -> VOID
host memory below the frozen 2 GB floor             -> VOID
any recovery fires (shadow should prevent it)       -> VOID
duplicate prompt within an arm                      -> VOID
prompt material not matched between arms            -> VOID
```

## Explicitly out of scope

No fitting. No knot added, moved, or re-measured. No threshold change. No
contention-factor change. No `OUT_OF_PROFILE` implementation. No repair. No
RECOVERY-COUPLING. No ASYNC-B2.

HEALTH-DUTY discriminates mechanisms. It does not fix anything.
