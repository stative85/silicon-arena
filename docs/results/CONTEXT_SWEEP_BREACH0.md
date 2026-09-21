# Context sweep for BREACH IGNITION 0 — Section 0, Option A

**Regime:** `EXPLICIT_RESIDENCY_MODE`, five species preloaded, identical context
for all five, no TTL
**Instrument:** `tools/bench_residency.py` with the degraded-mode detector added
(`tools/bench_residency_selftest.py`, 22 offline cases)
**Card:** RTX 5060, 8,151 MiB. Desktop floor at run start: 1,682 MiB.
**Raw:** `scratch/` (gitignored, not repo content)

No model-quality claims. No leaderboard. No combined score. This measures
placement, not intelligence.

## Why the instrument was changed first

`BENCH_RESIDENCY_RESULTS.md` preregistered a performance-bounded health check
as the change to make **before any rerun**, because a model spilled off the GPU
stays `RESIDENT`, answers every request, and passes the liveness probe. That
change had never been made. Running the sweep without it would have reported
Option D (per-agent offload) as Option A (uniform context) — the banned
host-introduced asymmetry, arriving by accident and stamped `regime_held`.

Detector: an absolute floor of 25 tok/s, plus a per-model relative band at 40%
of that model's own median, calibrated at run start. Calibration is itself
checked against the absolute floor, so a pool that is already spilled cannot
write its degraded rate in as normal.

## Result

```
context   pool VRAM    h2o    lfm2.5   qwen3.5   falcon   rwkv7     outcome
 4096      7,571      51.9     54.1      25.8     44.1     5.8     REFUSED
 3072      7,625     219.7    299.8     130.3    175.5     4.3     REFUSED
 2048      7,611     221.0    297.2     127.9    166.5    54.1     MEASURED
```
*(median decode tok/s at calibration, five models resident in every row)*

**2048 is the answer, and it is the only one of the three that is.**

Two facts the table makes visible that the old arithmetic could not:

1. **`rwkv7` is the model that spills.** At 4096 and 3072 it sits at 4–6 tok/s
   while resident — a 10x drop from its own 54.1 tok/s at 2048. Which model the
   runtime picks is an allocation-history artifact, not a property of RWKV.
2. **4096 degrades the whole pool, not just one member.** Every species runs
   3–6x slower at 4096 than at 3072 with the same five resident. Only `rwkv7`
   broke the absolute floor, so the detector reported one failure where four
   more were present. **The absolute floor under-detects; the cross-context
   comparison is what exposed it.** Recorded as the detector's known weakness.

## What still fails at 2048

The full benchmark ran at 2048 and completed with zero request failures, but
two cases did not hold the regime:

```
conc/5way/all           h2o    87.1 tok/s  (floor 91.9)
sustained/inflight_5    rwkv7  16.9 tok/s  (floor 25.0)
```

**This is contention, not spill, and the instrument cannot currently tell them
apart.** The band is calibrated solo; five-way concurrency legitimately costs
about 2.4x (`slowdown_ratio 5way/all`), which lands a healthy model just under a
solo-calibrated floor. A per-inflight-level band is the next instrument change.
Until it exists, a band breach at inflight 5 is not evidence of placement.

This matters less than it looks for BREACH, which is turn-based: the scheduler
issues one request at a time. At inflight 1 the pool is clean. Five-way
concurrency is not on the ignition path, and the arena should not be designed to
need it — throughput gain is 1.93x at inflight 5 versus 1.75x at 3.

## Invalid rows in this run

`C_4096` and `C_7000` prompts exceed a 2048 ceiling. They returned no tokens
(`tps -1`) and are **not measurements**. Deep-context characterisation does not
survive the context reduction; the earlier finding that "deep context is nearly
free" was taken at 8192 and does not transfer.

## What this does and does not settle

**Settled:** five species co-reside at 2048 on this card with all five at GPU
speed, at ~7.6 GiB. Option A has a viable ceiling. Option D is not a choice —
it is what happens silently above 2048.

**Not settled:** whether all five can execute the 16 canonical verbs through
`VERB-FIRST+NAME` at 2048. Step 1a is a separate gate and must drive the real
`scripts/breach/output_parser.gd` headless — a Python reimplementation would
qualify a parser the arena does not use (LAW 3, PRODUCTION-PATH EQUIVALENCE).

**Not authorized:** Section 0 remains a human call. This document is evidence
for it, not a decision.
