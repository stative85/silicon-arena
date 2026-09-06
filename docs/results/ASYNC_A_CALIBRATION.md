# ASYNC-A World-Feasibility Calibration — Result

**Substrate only. No LM inference, no ASYNC-A agents, no arms, no
arm-level effect estimates.**

Instrument: `tools/async_calibrate.gd`
World: `scripts/arena/async_world.gd` — the same code all four ASYNC-A arms run
Raw: `docs/results/ASYNC_A_CALIBRATION.json`

## Frozen configuration

```
resources    16
hold_ticks    4
chosen step   1 of the frozen sequence
evaluated     2 configurations, stopped at the first pass
```

These parameters now freeze for all four ASYNC-A arms.

## Controls

```
NEGATIVE  zero-delay synthetic actors
          stale_conflict = 0 across 27 runs (9 configurations x 3 replicates)

POSITIVE  injected-delay synthetic actors
          step 2  (12 res, hold 6)   stale_eligible_rate 0.5467   above ceiling
          step 1  (16 res, hold 4)   stale_eligible_rate 0.3817   PASS, taken
```

The sweep started at step 2, found it above the 0.40 ceiling, moved one step
toward looser pressure, and stopped at the first configuration inside the
window. No further search was performed.

## The negative control failed twice first, and both failures were real

This is the part worth keeping.

**Failure 1 — a conflated predicate.** The zero-delay control produced 57-336
`STALE_CONFLICT` events per configuration. With no delay, several actors observe
the *same* world version, several may want the same target, and the losers'
targets were "invalidated after their observation version" — so the original
predicate called them stale. But no world-time had elapsed. That is
**simultaneous contention**, not aged information, and calling it staleness
would have inflated ASYNC-A's headline measure with an effect that has nothing
to do with latency.

Fixed by Amendment 2: a fourth outcome class, `CONTENTION_LOST`, and an
`observation_age_ticks > 0` requirement on `STALE_CONFLICT`. Latency evidence
requires latency.

**Failure 2 — a harness ordering bug.** The control still failed. The
calibration loop called `world.advance()` *before* applying same-tick actions,
so a zero-delay action observed at tick T landed at T+1 and reported an age of
one tick. The harness was manufacturing the very elapsed time the control
forbids. Fixed by applying before advancing.

Two distinct defects, both invisible in the positive results, both caught by a
control whose only job is to fire when time cannot cause the phenomenon. Neither
was found by looking at the numbers the experiment cares about.

## Reading the result honestly

**0.3817 sits close to the 0.40 ceiling.** The first-passing rule took it, and
that rule is not being revisited — searching further for a "nicer" rate is
exactly the shaping the rule exists to prevent. But the frozen world is a
contested one, near the upper edge of the declared window, and that context
belongs with any ASYNC-A result rather than being discovered later.

**`stale_eligible` equals `stale_conflict` exactly in both rows** (983/983 and
687/687). That is expected here and not a bug: synthetic actors always attempt
the target they chose, so every stale-eligible action becomes a stale conflict.
Real agents need not, and the gap between the two in the main run is itself
informative — it separates *the world produced an opportunity* from *the agent
walked into it*.

## What this does and does not establish

**Establishes:** the world can mechanically generate stale-eligible
opportunities at a usable rate, and the harness does not manufacture them when
time cannot cause them.

**Does not establish, and cannot:** anything about whether natural async
differs from equalized async, whether arrival order matters, or how any model
behaves. No arm was run. No model was called.
