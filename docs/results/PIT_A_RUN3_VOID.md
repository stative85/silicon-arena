# PIT A, Run 3: VOID

**No architectural interpretation may be drawn from this run.** No analysis phase
was performed and none may be. Everything recorded here is **instrument
diagnostic material**.

## What happened

The run aborted at **Falcon-H1 r0, cycle 2**, with `BROKEN_HASH_CHAIN`. The
fail-closed journal check did exactly what it was built to do and stopped the
run rather than continuing on a world it could not reconstruct.

```
  journal row0 post      75b983940083986e974f7ba5
  apply(genesis, patch)  215190d51521867868710276   <- replay disagrees with live
```

## Root cause

`PitWorld.canonical_text()` sorted keys **one level deep only**. Nested values
were stringified with `str()`, which preserves **insertion order**. A JSON
round-trip through the journal can reorder them, so the same world produced two
different canonical texts and two different hashes.

Falcon-H1 proposed a `MUTATE` whose props contained a nested object:

```json
{"rule_1": {"description": "Allows multiple speakers per cycle.",
            "text": "mutated_rule_1"}}
```

Live apply hashed one key ordering. Replay-from-journal hashed another. **Canonical
identity was not representation-invariant.**

## Why the reconstruction tooth passed anyway

Tooth 11 — *"canonical history reconstructs every state from genesis"* — replays
60 `PitRandom` patches. `PitRandom` builds props as `{"text": "added"}`:
**always flat, always one level deep.** The witness came from a space the
producer does not inhabit.

This is the **fourth** occurrence of one failure class:

```
  Run 1   constructor-shaped patches         schema could not express `type`
  Run 2   constructor-shaped field coupling  cross-field rules unstatable in schema
  Run 3   constructor-shaped flat props      nested values broke hash stability
```

Each time, a component was validated against inputs written by its own author,
and each time the producers found the gap within minutes of being allowed to
speak. **The instrument keeps being correct about worlds the harness can
construct and wrong about worlds the models create.**

## Damage assessment — and why "chain intact" is not "sound"

```
  danube2   r0/r1/r2   100 rows   chain OK   0 accepted patches with nested props
  lfm2.5    r0/r1/r2   100 rows   chain OK   0
  qwen3.5   r0/r1/r2   100 rows   chain OK   1 each
  falcon    r0           2 rows   BREAK      1
  rwkv7, RANDOM         never ran
```

Nine hundred cycles are chain-intact. **They are still not evidence.** qwen3.5's
three replicates each contain an accepted nested-props patch; they chain only
because the divergence landed where the next comparison did not expose it, not
because their identity is stable. A check that can pass for the wrong reason has
not passed.

## What Run 3 does establish

1. The fail-closed journal check works on live data: it detected an
   unreconstructible world at the second cycle and stopped, writing nothing
   further.
2. The interaction-state repair held — the Run 2 fixed point did not recur in
   any completed arm.
3. **A producer-shaped regression specimen**, preserved permanently: Falcon-H1's
   nested `MUTATE`, the exact structure that broke canonical identity.

**It provides no valid evidence for the PIT A architectural hypothesis.**

## The law this earns

> **CANONICAL IDENTITY MUST BE REPRESENTATION-INVARIANT.** For every
> JSON-representable canonical state: dictionary insertion order must not affect
> canonical text or hash; JSON serialise-then-parse must not affect it; journal
> append-then-read must not affect it; and live apply and replay apply must
> produce identical canonical identity.

`str(Dictionary)` — or any insertion-order-dependent representation — may never
appear inside identity computation.

## Disposition

Artifacts preserved at `D:\PIT_A_RUN3_RAW_20260906_082909` with checksums, joining
the Run 1 and Run 2 sets. Nothing is deleted.

**Run 4 is not pre-registered.** The methodology changes first: before another
generation is spent, the persistence boundary must survive thousands of
machine-generated adversarial worlds without changing identity. The five species
have earned the role of adversarial fuzzers before they resume being
experimental subjects.
