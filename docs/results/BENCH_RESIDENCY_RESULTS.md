# EXPLICIT_RESIDENCY_MODE Pool Benchmark — Results

**Regime:** `EXPLICIT_RESIDENCY_MODE`, five models preloaded at 8192 context, no TTL
**Instrument:** `tools/bench_residency.py` (method frozen in `docs/BENCH_RESIDENCY.md`)
**Raw:** `D:/bench_residency.json`
**Card:** RTX 5060, 8,151 MiB. Pool resident footprint 7,674–7,710 MiB.

No model quality claims. No leaderboard. No combined score.

## Headline

The pool is **oversubscribed**, and that single fact explains every anomaly in
this run. Summed standalone footprints come to 10,414 MiB against an 8,151 MiB
card. The runtime absorbs the ~2.3 GiB deficit by putting a model on the CPU or
evicting one, and which model it picks depends on allocation history rather than
on anything about the request.

A CPU-resident model runs at **~2.4–2.6 tok/s** with a multi-second TTFT, versus
~200–330 tok/s and sub-150 ms TTFT on the GPU. That is a 50–100x penalty, and it
is invisible to both the resident-set check and a liveness probe: the model is
loaded, it answers every request, and it returns correct-looking output.

**When all five are genuinely GPU-resident, the pool works well.** 5-way
concurrency completes in 2,754 ms — barely more than the slowest member's solo
time — and 400 sustained requests completed with zero failures.

## The demonstration

Two independent natural experiments, neither designed, both showing the same
causal chain: free a neighbour's VRAM and the spilled model returns to the GPU.

**In the solo phase.** qwen was CPU-resident throughout, except for one case:

```
qwen3.5   A_micro   6,736 ms  (4.5 tok/s)   CPU
          B_turn   38,888 ms  (2.4 tok/s)   CPU
          C_256       221 ms  (182 tok/s)   GPU   <- rwkv7 evicted during this case
          C_1024   22,956 ms  (2.4 tok/s)   CPU   <- rwkv7 reloaded
          C_4096   12,042 ms  (2.6 tok/s)   CPU
          C_7000   18,647 ms  (2.5 tok/s)   CPU
```

The one healthy reading is the one case where the residency assertion caught
rwkv7 missing from the pool. ~1.7 GiB freed, qwen back on the GPU, 100x faster.
rwkv7 reloads, qwen spills again.

**In the concurrency phase.** h2o wedged during `2way/med+slow` and was
unloaded and reloaded by the recovery path:

```
2way/med+slow   qwen 33,630 ms   CPU   (h2o wedges here, gets reloaded)
3way/fast       qwen    705 ms   GPU
5way/all        qwen  1,147 ms   GPU
```

Same chain, different trigger.

### What is claimed, and what is not

Claimed: a model in this pool intermittently executes ~50–100x slower, this
state persists across many consecutive requests, and freeing a co-tenant's VRAM
restores it. That is directly observed, twice.

Not claimed: that the slow path is specifically CPU execution. There is no
layer-placement telemetry here. The evidence is convergent — the oversubscription
arithmetic, a token rate matching CPU inference for a 2B Q4, prefill and decode
degrading by the *same* factor (which rules out a context or KV-cache effect),
and the eviction-recovery coupling — but the mechanism is inferred, not measured.

## Solo baseline

10 measured requests per model per workload, 3 discarded warmups. Median / p95 ms.
Rows marked `[CPU]` were taken while the model was in the degraded state and are
**not** valid latency figures for that model.

```
              A_micro      B_turn       C_256      C_1024     C_4096     C_7000
h2o             193/200     489/501     110/112    267/284    329/345    360/377
lfm2.5           92/111     247/258      96/107    127/154    144/171    252/266
falcon          158/172     517/542     183/197    220/238    166/188    187/206
rwkv7           844/864   1790/1841     940/954    939/983    935/945    939/972
qwen3.5   [CPU] 6736/6769 38888/38996   221/230* 22956/23165 12042/12086 18647/18760
                                        *GPU
```

Zero request failures in every solo case.

**Healthy spread across species is roughly 5–7x**, taking each model's
GPU-resident readings (lfm2.5 fastest, rwkv7 slowest). The **17x** figure carried
in from the earlier sequential probe is **not reproduced** by this instrument;
the companion pressure test measured 6.5x alone and 14.7x in-pool on its own
workload. These are different measurements on different workloads and are not
merged into a single claim.

**Deep context is cheap.** C_7000 (~28,000 characters) costs h2o 360 ms with a
119 ms TTFT. Context depth is not a significant cost driver in this pool; the
C cases are *faster* than B_turn because they generate 48 tokens rather than 96.
Output length dominates, not prompt length.

## Concurrency

Barrier-synchronised so requests genuinely begin together, 3 trials, B_turn.

```
2way/fast+fast   wall 1,861   lfm2.5   217   rwkv7 1,860
2way/fast+slow   wall   705   lfm2.5   313   h2o     703
2way/slow+slow   wall   832   falcon   686   h2o     823
2way/med+slow    wall 120,032  [FAILED: h2o wedged]
3way/fast        wall 120,024  [FAILED: lfm2.5 wedged]
3way/mixed       wall 1,347   lfm2.5   374   falcon  649   h2o 1,345
3way/slow        wall 1,461   qwen3.5  994   falcon  769   h2o 1,460
5way/all         wall 2,754   h2o 1,799  lfm2.5 567  qwen3.5 1,147  falcon 1,008  rwkv7 2,752
```

**Wall time is governed by the slowest participant, not by the sum.** 5-way
completes in 2,754 ms against rwkv7's 1,790 ms solo — five concurrent requests
for roughly 1.5x the cost of the slowest one alone. The card is not saturated by
five concurrent small models.

The two 120,032 ms walls are the 120 s request ceiling, not measurements. Both
are wedge failures, and the ceiling is what kept them bounded — an earlier
un-ceilinged run hung for over thirty minutes on the same fault.

### slowdown_ratio (concurrent median / solo median)

```
2way/fast+fast     lfm2.5 0.88   rwkv7 1.04
2way/fast+slow     lfm2.5 1.27   h2o   1.44
2way/slow+slow     falcon 1.33   h2o   1.68
3way/mixed         lfm2.5 1.51   falcon 1.26   h2o 2.75
3way/slow          falcon 1.49   h2o   2.99
5way/all           h2o 3.68   lfm2.5 2.29   falcon 1.95   rwkv7 1.54
```

**Every qwen3.5 slowdown_ratio is NOT COMPUTABLE and is excluded above.** Its
solo B_turn denominator (38,888 ms) was captured while it was CPU-resident, so
the raw file reports values of 0.02, 0.03 and 0.86 — which would read as qwen
being *33x faster* under concurrency. That is an artifact of a broken
denominator, not a measurement. The defect propagated silently because the
degraded solo case was not flagged: see the blind spot below.

## Sustained queue

100 requests per level, round-robin across all five. **Zero failures across all
400 requests.**

```
in-flight   wall     req/s   tok/s   gain
1           85.2 s   1.17    86.9    1.00x
2           53.6 s   1.86   138.0    1.59x
3           44.0 s   2.27   168.1    1.93x
5           41.4 s   2.41   178.1    2.06x
```

**Throughput saturates near 2x at three in-flight.** Going from 3 to 5 buys
0.13x for 67% more concurrency. Useful concurrency for this pool is ~3.

Per-model median latency under queue pressure tells the more useful story:

```
in-flight      1      2      3      5     ratio 1->5
lfm2.5       235    254    289    295       1.26x
falcon       410    515    601    618       1.51x
qwen3.5      628    732    804    761       1.21x
h2o        1,158  1,442  1,572  1,790       1.55x
rwkv7      1,817  2,336  3,153  5,828       3.21x
```

**rwkv7 absorbs almost all of the queue pressure.** Four species degrade by
1.2–1.6x from serial to 5-way; rwkv7 degrades 3.2x and is the sole reason the
tail widens. This matches the companion pressure test, where rwkv7 was the only
species with a significant co-residency penalty (2.65x, against 1.05–1.17x for
the rest). It is also the one architecturally distinct member — recurrent /
linear-attention, whose runtime state is not a conventional KV cache. Whether
those facts are connected is **not established here.**

## Regime failures

```
cases where the regime did not hold   3
  solo/C_256/qwen3.5                  rwkv7 evicted from the pool
  conc/2way/med+slow                  h2o wedged
  conc/3way/fast                      lfm2.5 wedged
wedge events                          2, both recovered by reload
```

Three of 44 cases. All three are recorded rather than repaired-and-rerun, and
their numbers are excluded from the derived statistics.

## The instrument's own blind spot

The residency assertion is the benchmark's main tooth, and it is **not
sufficient**. Three distinct failure modes appeared, and it detects only one:

```
mode        example                          resident set   liveness probe
evicted     rwkv7 dropped from pool          CAUGHT         caught
wedged      h2o, lfm2.5 stop responding      missed         CAUGHT
degraded    qwen at 2.4 tok/s for 5 cases    missed         missed
```

A wedged model stays `RESIDENT`; the `FAILED` lines read literally
`missing=none wedged=['h2o']`. That gap was found during smoke testing and
closed with a liveness probe before this run.

**The third mode is still open.** A 50–100x-slow model passes both checks: it is
resident, and it answers every request successfully. qwen ran degraded through
five consecutive solo cases and the instrument reported `fail 0` and
`regime_held` for all but one of them. The corrupted `slowdown_ratio` is the
direct consequence — a derived statistic inheriting a defect from an input that
nothing flagged as defective.

Closing it requires a **performance-bounded** health check: a per-model expected
latency band, with a breach treated as a regime failure. That was not added
mid-run, because repairing an instrument while it is measuring is how a
benchmark becomes a story about itself. It is recorded here as the next change
to the instrument, to be made before any rerun.

## What this means for the inference bridge

Measured facts, in priority order:

1. **The pool cannot be trusted to stay as configured.** Across one run, three
   of five models entered a bad state — one evicted, two wedged, one degraded
   for most of the run. The bridge must treat pool composition as observed
   state, never as configuration.
2. **Liveness is not health.** The most damaging mode answers every request. The
   bridge needs latency-band monitoring per model, not an up/down check.
3. **Recovery is cheap and works.** Both wedges recovered on unload/reload
   (`recovered: True`), and reloading a neighbour restored a spilled model
   twice. Reload is a viable remediation.
4. **Five at 8192 is over the line.** 10,414 MiB of demand on an 8,151 MiB card.
   A four-model pool, or a reduced context for some members, would remove the
   entire class of failure documented here. This benchmark does not establish
   which of those is better — it establishes that the current configuration is
   the cause.
5. **Concurrency is worth having, up to about three.** 1.93x at in-flight 3,
   2.06x at 5. Beyond three the gain does not justify the added memory pressure.
6. **Schedule on the slowest participant.** Wall time tracks the slowest member
   of a concurrent set, so mixing rwkv7 into a batch sets that batch's latency.
7. **Output length dominates, not prompt length.** Deep context is nearly free;
   generation length is the real cost driver.

## Corrections made during this work

**I retracted a correct hypothesis.** The first smoke run measured h2o at
17,946 ms / 2.3 tok/s. I read it as VRAM spill, then found an orphaned Python
process from a previous run and retracted the spill hypothesis, attributing the
reading to contention. The orphan was real and did corrupt the first pressure
run — but it was not the cause of the slow reading. The spill hypothesis was
substantially right, and this run demonstrates it twice.

The error was collapsing two separate claims: *"this particular run was
contaminated"* and *"the hypothesis is wrong."* The first was true and the second
did not follow. A contaminated measurement invalidates that measurement, not the
idea it was testing.

The ~200x spread figure from that contaminated run stays retracted; it never
measured what it claimed to.
