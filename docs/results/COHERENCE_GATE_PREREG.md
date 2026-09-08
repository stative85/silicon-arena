# Preregistration: making the coherence gate a doorman, not an experiment

**Written and committed BEFORE the seeded suite was implemented or run.** The
commit preceding this file's own commit is the last one that could have seen a
result. That ordering is the point: everything below is a criterion, not a
description of an outcome.

Context: `docs/results/FLAKY_GATE_COHERENCE.md` recorded that
`coherence_selftest` calls `_rng.randomize()` and then evaluates a fixed
criterion against a random draw, with observed `argue_r` from 0.052 to 0.664
against a fixed 0.2 bar. It went unfixed deliberately, because the fix touches
scientific qualification logic and changing a gate's acceptance rule after
seeing it go red is exactly the reflex this project exists to prevent.

## The decision

Two coherent options existed:

```text
A. deterministic qualification -> freeze an explicit seed / fixed corpus
B. stochastic qualification    -> preregister repeated trials + acceptance rule
```

**A is taken.** A gate protecting the supervisor must answer the same question
the same way on the same code. Randomness belongs in the experiments the gate
guards, not in the gate. A doorman who admits people at random is not a
doorman.

## What changes, exactly

1. `CoherenceEngine.self_test(seed)` seeds `_rng` explicitly at entry, before
   either `_drive()` call, so a seed fully determines the run.
2. A suite runs the self-test across **N = 20 fixed seeds**.
3. **Live behaviour is untouched.** `_init()` keeps `_rng.randomize()`. Only
   the qualification path becomes deterministic.

## What does NOT change

- **The 0.2 separation criterion stays at 0.2.** It is not widened, softened,
  made relative, or converted to a percentile. The margin varied because the
  input varied, not because the threshold was wrong.
- The synthetic echo/argue matrices, the 12-turn drive, and the `r`/`H_min`
  math are untouched.

## The seeds, fixed now

**Seeds 1 through 20 inclusive.** Chosen mechanically as the first twenty
positive integers, specified here before any of them has been run, precisely so
that no seed can be swapped for a friendlier one afterwards. If a seed is ever
changed, added, or dropped, that is an amendment and must be recorded as one
with its own commit and reason.

## The acceptance rule, fixed now

```text
margin(s)  = echo_r(s) - argue_r(s)
GATE PASSES iff  min over all 20 seeds of margin(s) > 0.2
```

The gate reports the **worst case**, not the mean and not a single draw. This
is strictly more informative than the old single random draw: a detector that
is marginal becomes visibly and repeatably marginal instead of intermittently
red at 3 a.m.

## The pre-committed decision tree

```text
min margin > 0.2   -> GREEN. The detector separates on every fixed seed.
                      coherence_selftest is deterministic and may stay in the
                      supervisor's integrity set.

min margin <= 0.2  -> RED, and it STAYS RED.
                      This is a REAL FINDING, not a tuning opportunity: the
                      detector genuinely fails to separate on some inputs.
                      Then, in this order and no other:
                        - the threshold is NOT moved
                        - the failing seeds are NOT dropped
                        - N is NOT reduced
                        - the gate is REMOVED from the supervisor's integrity
                          set and recorded as an open scientific question
                        - the detector is not wired into the arena
```

The temptation this preregistration exists to block is specific and nameable:
discovering that the worst of twenty seeds lands at, say, 0.18, and deciding
that 0.15 was always the sensible bar. It was not. 0.2 was written down first.

## Scope

`coherence_selftest` is NO_CONTACT: pure synthetic math under `godot
--headless`. Nothing here reads, writes, or contacts LM Studio, and nothing
here touches PIT A, SWARM/METABOLISM, the quarantined qwen block, `ks=1.8`,
`kh=20`, `n=3`, or the 2048 MB floor.
