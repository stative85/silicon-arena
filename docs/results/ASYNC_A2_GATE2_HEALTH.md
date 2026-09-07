# Gate 2 — New-Pool Health Qualification

Roster: lfm2.5 + qwen3.5 + falcon-h1. Two collections, 1,440 calls each,
4 prompt sizes (ASYNC / SMALL / MEDIUM / LARGE) x 2 load conditions x 60
samples, unique prompts, explicit residency, `max_active = 2`, health in
**shadow** throughout.

## Collection A — fit

```
records 1440   transport failures 0   pathological stalls 0
```

Stalls were identified relative to each cell's own distribution (>5x cell
median), **not** by any frozen threshold: a policy constant cannot help select
the surface it will later be applied to. None occurred.

### The surfaces changed because the neighbour changed

```
contention factor    beside danube2    beside qwen3.5
lfm2.5                    1.1579           1.0874
falcon                    1.4809           1.2390
qwen3.5                        --           1.2864
```

Falcon's contention fell ~20% purely from a change of co-resident. Profiling
qwen alone and carrying the old lfm2.5/falcon numbers forward would have left
both with inflated expectations — and an inflated denominator makes the
detector **less** sensitive, the same failure the low-end validation caught
previously.

The new surfaces also gain an **ASYNC-sized knot** (~142-194 tokens) the old
ones lacked entirely. ASYNC-A2 runs in exactly that regime.

```
falcon    [[58,183.0], [194,264.5], [804,403.5], [6184,1312.5]]   1.2390
lfm2.5    [[47, 73.0], [142, 93.5], [597,123.0], [4837, 418.0]]   1.0874
qwen3.5   [[58,128.5], [187,190.0], [766,249.5], [5706, 889.0]]   1.2864
```

## Collection B — held-out validation

`ks = 1.8`, `kh = 20`, `n = 3` were selected on the **old** pool's corpora and
given no vote in the Collection A fit. Collection B touched neither. This is a
genuine external test rather than another selection round.

```
DEGRADED / CATASTROPHE (false positives)   0 of 1440
SUSPECT (recorded, not actioned)          23
residual   median 1.01   p95 1.50   p99 2.02   max 2.53
worst call 2.53x  (lfm2.5, MEDIUM, uncontended, 311 ms vs 123 ms expected)
```

**Zero false recoveries.** Twenty-three calls exceeded `ks`, none reached three
consecutive — the streak requirement doing exactly what it was measured to do.

**The frozen thresholds survive the new pool unchanged.**

### Known drift, recorded not patched

```
lfm2.5   LARGE  load2   residual median 1.43
qwen3.5  LARGE  load2   residual median 1.28
```

2 of 24 cells sit outside 0.80-1.25, both contended LARGE prompts. The single
per-model contention factor underestimates contention at the largest size —
the size-dependent contention limitation already recorded for the old pool,
now quantified for this one.

It is **not** corrected. Making contention size-conditioned would change the
expectation surface and require re-validating the whole detector for a gain in
the direction that fires *more*, and neither drifting cell produced a false
positive. Recorded as a known approximation.

## Operational risk noted

During Collection B the host reached **0.7 GB free of 31.7 GB**, with LM Studio
holding ~23.6 GB across three model processes, and the collection process was
killed by the OS during teardown — after its data was written and verified
intact (1,440 records, all OK).

Three co-resident models cost far more system RAM than VRAM. An ASYNC-A2 run
should confirm host memory headroom before starting; a mid-replicate OOM kill
would void the replicate.

## Verdict

```
Gate 1 contract     PASS   0/200 shape failures for all three
Gate 2 health       PASS   0 false positives on held-out, thresholds unchanged
Gate 3 equalizer    PASS   1000 ms, 0 breaches at run-equivalent exposure
```

All three models are now profiled, so the `UNPROFILED` PRE-RUN refusal no
longer fires. ASYNC-A2 is unblocked pending its pre-registration.
