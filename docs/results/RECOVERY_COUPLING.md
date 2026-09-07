# Recovery-neighbour coupling — reopened bridge investigation

**Status: OPEN QUESTION, no answer claimed.**

## Why the wall opens here and not elsewhere

`docs/HEALTH_POLICY.md` closes the health thresholds to retuning and lists the
only conditions that reopen bridge infrastructure. One of them is **a new
measured failure mode**. ASYNC-A2 produced one.

This is not a request to retune `ks = 1.8`, `kh = 20`, `n = 3`. **The detector
did its job.** It fired on a 60.7× residual, which is exactly what `kh = 20` was
reserved for. Nothing in this document proposes changing a threshold.

## What was measured

ASYNC-A2, SERIAL arm, at world tick 508 (`ASYNC_A2_SERIAL_r0.json`):

```
t=334.596s  qwen3.5-2b   HOT -> DEGRADED       3 consecutive suspect calls
t=334.596s  qwen3.5-2b   -> RECOVERING          reload, ok=false
t=349.157s  qwen3.5-2b   residual 1.84, recovery succeeded -> HOT
t=349.293s  falcon-h1    HOT -> DEGRADED        residual 60.7x >= catastrophe 20x
t=349.293s  falcon-h1    -> RECOVERING          reload, ok=false
t=361.774s  falcon-h1    CATASTROPHE 60.67, recovery succeeded -> HOT
```

falcon's catastrophe verdict lands **136 ms** after qwen's recovery completes.
falcon had been healthy for the preceding 508 ticks.

Host free memory was 4,676 MB against a 2,048 MB floor, so this is not an OOM.
GPU was 5,335 MiB of 8,151 MiB with all three models resident.

## What is NOT established

**Causation.** One occurrence, one replicate, no control. Two readings fit the
same evidence and this run cannot separate them:

1. Recovering qwen transiently destabilised a healthy neighbour — reload
   allocation, VRAM churn, or server-side contention during load.
2. Both models degraded from a shared external cause, and qwen simply crossed
   its threshold first because `ks` is a ratio against a smaller expectation.

Temporal adjacency is not a mechanism. 136 ms is suggestive and nothing more.

## The question worth answering

> Does recovering one explicitly resident model transiently destabilise healthy
> co-resident neighbours?

This is bridge and runtime mechanics. It is **not** ASYNC emergence, it does not
belong inside an ASYNC experiment, and it must not be investigated by
reinterpreting ASYNC-A2's envelopes.

## Proposed instrument, to be pre-registered before it runs

Deliberately outside any world:

```
MODEL A recovery
        |
        v
co-resident B/C latency measured through each phase:
    baseline        steady state, all HOT, no recovery
    unload          A's weights being released
    reload          A's weights being loaded
    allocation      A allocating context
    completion      immediately after A returns to HOT
    settled         N seconds after
```

Shape of the measurement, mirroring the health-collection discipline that
already exists in `tools/bridge_collect.gd`:

- B and C generate continuously at a fixed prompt size and load level; A is
  recovered on a schedule, not on a health verdict, so recovery is the
  independent variable rather than a consequence of degradation.
- Residual is computed against the **existing frozen expectation surface** in
  `bridge_health.gd`. No refitting. The question is how far neighbours deviate
  from their own measured normal, and refitting during the investigation would
  absorb the effect being measured.
- Repeat across which model plays A, since contention factors already differ
  measurably by model (falcon 1.239, lfm2.5 1.087, qwen3.5 1.286).
- A no-recovery control arm of equal duration, to establish the base rate of
  spontaneous 20×+ residuals. Without it, a coupling effect cannot be
  distinguished from the tail of ordinary jitter.

## If a coupling effect is confirmed

Then the design question is a **scheduler** question, not a threshold question:
whether recovery should quiesce the pool, drain in-flight work on neighbours,
or serialise against other models' requests. Those are changes to
`InferenceBridge` behaviour, and they get their own pre-registration.

If no coupling effect is found, the A2 event is recorded as a coincidence of two
independent degradations and the wall closes again.

## Related recorded facts, not yet connected

- Intermittent ~12-second stalls, recorded during health collection as outside
  the healthy expectation surface and never explained.
- LARGE/load2 residual drift of 1.43/1.28, recorded and not corrected.

Both are candidates for the same underlying cause as this event, and none of the
three has evidence linking it to the others. Listed so a future investigation
does not have to rediscover them.
