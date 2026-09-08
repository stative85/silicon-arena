# Nondeterministic gate: `coherence_selftest`

Found during the night shift of 2026-09-07 while running the classified test
suite. **Not fixed** — the fix touches Arena science tooling and changes a
qualification verdict, which is not a night-shift decision.

## The defect

`coherence_engine.gd:55` calls `_rng.randomize()`, seeding from entropy. Every
phase and frequency in the synthetic populations is then drawn randomly:

```gdscript
_rng.randomize()
...
_phase[n] = _rng.randf_range(0.0, TAU)
_omega[n] = _rng.randf_range(0.8, 1.2)
...
dp += _rng.randfn(0.0, 0.12)
```

`self_test()` evaluates a **fixed criterion against a random draw**:

```text
SEPARATED iff  echo_r - argue_r > 0.2
exit 0 if separated, exit 2 if not
```

## Measured

Four standalone runs plus one inside the classified runner:

```text
echo r     argue r    gap     verdict
0.984      0.052      0.93    SEPARATED
0.962      0.149      0.81    SEPARATED
0.984      0.555      0.43    SEPARATED
0.992      0.664      0.33    SEPARATED
  (one run inside tools/run_safe_tests.py returned FAILED)
```

`argue_r` ranges **0.052 to 0.664** across runs. With `echo_r` near 0.98, the
margin shrinks from 0.93 to 0.33 as the draw varies. The distribution's tail can
cross the 0.2 criterion, and did.

## Why it matters more now than it did before

A stochastic gate was survivable when a human ran the suite and re-ran on a red.
It is not survivable under `tools/night_supervisor.py`, whose integrity gate
halts the loop on any test failure. A test that fails occasionally for no reason
converts directly into **random `INTEGRITY_FAILURE` stops at 3 a.m.**, and the
operator arrives to a halted run with no real defect behind it.

Worse, it trains the reflex this whole project exists to prevent: the first
person to hit a spurious red will be tempted to make the gate looser.

## The fix that must NOT be applied

**Do not widen the 0.2 criterion.** The margin varies because the input varies,
not because the threshold is wrong. Loosening it after seeing a red is metric
fiddling of exactly the kind the frozen-threshold rules forbid.

## The fix that probably should be applied — needs a human decision

Seed `self_test()` deterministically, leaving live `randomize()` behaviour
untouched, so the qualification is reproducible. Better still, run it across N
fixed seeds and report the **worst-case margin**, which is strictly more
informative than one random draw and would make a marginal detector visible
instead of intermittent.

This is deferred because:

- it modifies `coherence_engine.gd`, which is Arena experimental tooling
- it changes a qualification verdict currently phrased as
  `"Safe to wire in"`
- a marginal detector may be a real finding worth surfacing rather than
  smoothing, and that judgement belongs to the operator

## Consequence for unattended running

**This is a blocker for a long unattended supervisor run.** A two-iteration
attended qualification is unaffected in principle but may still stop spuriously;
if it does, the stop is the flaky gate and not the loop.

## Process note

The commit that surfaced this ran its verification *after* committing rather
than before, so a red suite was briefly present in an otherwise unrelated
commit. The tree is green at the time of writing (40 passed, 0 failed, 4
withheld) and the commit's content is unrelated to the failure, but the ordering
was wrong and is recorded rather than quietly corrected.
