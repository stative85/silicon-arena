# ASYNC-B Run 1 — VOID, NO RESULT

Run executed at prereg `e53e684`, instrument `f531701`, runner `6eb4098`.
Frozen Latin schedule, 8 representation seeds x 4 cells, SERIAL only, 200 ticks
per cell, `arm_baseline` before every cell.

```text
ASYNC-B RUN 1:
VOID / NO RESULT

REPRESENTATION INSTRUMENT:
PASSED

PRIMARY 2x2:
NOT ESTIMABLE

BLOCKING INFRASTRUCTURE QUESTIONS:
1. short-prompt health-surface validity
2. recovery-neighbour coupling

32 cells run
12 VOID (38%)
0 seeds with a complete usable 2x2
```

**No representation tooth fired.** Zero map-hash changes, zero bijection
failures, zero separation failures, zero canonical-set-invariant violations,
zero `NOT EXERCISED`. The representation layer did its job; the run died for an
unrelated reason.

## Void map

```text
seed  A B C D
  0   . V . V
  1   . V . V
  2   . V . V
  3   . . V .
  4   . . . V
  5   . . V V
  6   . V . .
  7   . . V .

void by cell   A 0/8   B 4/8   C 3/8   D 5/8
```

Every void reason is identical:

```text
runtime: model qwen3.5-2b entered DEGRADED during a measured replicate
```

That is a pre-registered void condition firing exactly as written. Nothing was
tuned, exempted, or re-run.

## The voids are condition-correlated, and that is the problem

Cell A never voided. Void rate rises monotonically as the visible list shortens:

```text
cell   void      mean visible-list len   accept rate (all cells)
A      0/8       9.96                    0.679
C      3/8       9.64                    0.714
B      4/8       8.39                    0.855
D      5/8       8.15                    0.881
```

The chain appears to run **through the treatment itself**:

```text
private frames
    -> agents collide less
    -> accept rate rises
    -> more resources held simultaneously
    -> visible list shortens
    -> fewer prompt tokens
    -> lower expected_ttft
    -> unchanged observed TTFT yields a larger residual
    -> 3 consecutive SUSPECT
    -> DEGRADED
```

If that reading is right, the manipulation worked and the *byproduct of it
working* destroyed the measurement.

**This is stated as the shape of the mechanism, not as a result.** The accept
rates above include voided cells. Restricting to non-void cells does not fix it
— it makes it worse, because the surviving cells in B and D are exactly the ones
where the pathology did not fire:

```text
accept rate, non-void cells only
A 0.679 (n=8)   B 0.834 (n=4)   C 0.708 (n=5)   D 0.857 (n=3)
```

That is a biased subsample by construction. **No effect estimate is computed
from this run**, and the 2x2 contrasts in `tools/async_b_analyse.py --pass 2`
are not run against it.

## What was harvested: the coupling reproduces 10 times

Every void carried the same signature, and it is the ASYNC-A3 SERIAL failure
recurring with far more instances:

```text
cell/seed   first DEGRADED                     then                          gap
B seed0     qwen3.5  3 consecutive suspect  -> falcon 31.0x catastrophe   +7,440 ms
D seed0     qwen3.5  3 consecutive suspect  -> falcon 34.4x catastrophe   +8,270 ms
B seed1     qwen3.5  3 consecutive suspect  -> falcon 37.3x catastrophe   +8,808 ms
D seed1     qwen3.5  3 consecutive suspect  -> falcon 31.1x catastrophe   +7,331 ms
B seed2     qwen3.5  3 consecutive suspect  -> falcon 30.4x catastrophe   +7,310 ms
C seed3     qwen3.5  3 consecutive suspect  -> falcon 33.5x catastrophe   +8,192 ms
D seed4     qwen3.5  3 consecutive suspect  -> falcon 36.7x catastrophe   +8,862 ms
D seed5     qwen3.5  3 consecutive suspect  -> falcon 34.9x catastrophe   +8,240 ms
B seed6     qwen3.5  3 consecutive suspect  -> falcon 31.5x catastrophe   +7,422 ms
C seed7     qwen3.5  3 consecutive suspect  -> falcon 34.2x catastrophe   +8,370 ms

D seed2     qwen3.5  3 consecutive suspect  -> qwen3.5 3 consecutive       +13,611 ms
```

Ten of eleven sequences are the identical ordering, with residuals in a
**30.4x-37.3x** band and gaps in a **7,310-8,862 ms** band. The gap is
consistent with the duration of qwen's reload.

A3 produced this once, at 60.7x, and the honest reading then was that
adjacency is not a mechanism. Eleven instances with a fixed ordering, a narrow
residual band and a narrow latency band is a different evidentiary situation.
It is still not a controlled test — recovery was never the independent variable
here — but it is now a strong regularity rather than an anecdote. Recorded in
`docs/results/RECOVERY_COUPLING.md`.

## What is NOT being done

- **No threshold change.** `ks = 1.8`, `kh = 20`, `n = 3` stay exactly as
  frozen. The detector fired on 30-37x residuals; that is it working.
- **No low-end knot extension** to make short prompts cheaper to satisfy.
- **No short-prompt exemption**, no per-cell re-run, no dropping qwen.
- **No effect estimate** from the surviving cells.

Each of those would be the move the closed-infrastructure wall exists to
prevent, and each would be made *after* seeing which cells died.

## TWO blockers, not one

An earlier version of this record named recovery coupling as *the* blocker. That
was wrong, and the correction matters because it changes what has to be fixed
first.

**The health verdict precedes every reload.** In 12 of 12 cells that produced
runtime events, the first event is `qwen3.5-2b -> DEGRADED`. Recovery is
downstream. Repairing the coupling tomorrow would not have saved one cell,
because qwen would still trip the detector in the short-list regime and void
B/C/D selectively.

```text
BLOCKER 1
Is Qwen genuinely degrading in the short-list regime,
or is the frozen expected-TTFT surface miscalibrated there?
    -> docs/EXPERIMENT_HEALTH_SHORT.md

BLOCKER 2
When Qwen recovery/reload occurs,
does that operation itself destabilize Falcon?
    -> docs/EXPERIMENT_RECOVERY_COUPLING.md
```

They are separate questions requiring separate controlled instruments, and
neither can be answered by reinterpreting this run's artifacts.

## The uncomfortable possibility

ASYNC-B may have found the regime where **the treatment changes the detector's
denominator without changing the underlying runtime enough to justify it**.

If HEALTH-SHORT confirms that, the run did not merely fail. It found an
interaction between **ecology state and observability infrastructure**: the
experimental manipulation altered the world in a way that moved the measuring
instrument's expectations, and the instrument then removed exactly the cells
where the manipulation worked best.

That is a real result about instrumentation, and it is only visible because
every other part of the pipeline was made hard to lie with first.

## What ASYNC-B2 will and will not change

Not designed yet, and deliberately not started. When it exists it stays
**scientifically identical** to `e53e684`: same question, same 2x2, same 8
seeds, same Latin schedule, same world, same maps, same metrics.

Only infrastructure qualification changes. No scarcity tweak, no new roster, no
dropping qwen because it was inconvenient, and no making A/B/C/D easier on the
detector.
