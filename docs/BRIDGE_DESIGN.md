# Inference Bridge — Design

**Status:** design frozen before implementation
**Built from:** `docs/results/BENCH_RESIDENCY_RESULTS.md`, `docs/results/bench_pressure.json`, `D:/vram_budget.json`
**Not yet implemented.** No bridge code exists at the time of writing.

## The unlock

> **Five agents do not require five simultaneous GPU executions.**

All five species keep persistent state — memory, bids, scars, topology, world
position — as logical entities. The bridge decides only *when their inference
actually runs*, and how many models are resident to run it. Logical population,
residency, and concurrency are three separate numbers, and the arena has been
conflating them.

```
5 LOGICAL ARENA AIS          persistent state, always "present"
        |
        v
   BRIDGE / SCHEDULER        max_active = 2 normal, 3 burst
        |
        v
      GPU                    ~3 resident in desktop mode
```

## Measured facts this rests on

```
TOTAL VRAM                8,151 MiB
DESKTOP_BASELINE            596 MiB    zero models resident, idle desktop
marginal cost per model     h2o 1,694   lfm2.5 1,055   qwen 1,999
                            falcon 1,577   rwkv7 767
five models                7,092 MiB   -> pool 7,688, free 463
```

**The five-model pool never fit.** 596 + 7,092 = 7,688 MiB against a 7,551 MiB
budget at even a minimal 600 MiB reserve. It appeared to fit only because the
runtime economised, and the economising is the spilling documented in the
results: a model pushed to ~2.4 tok/s, or evicted outright.

Throughput, from 400 sustained requests:

```
in-flight    1       2       3       5
gain       1.00x   1.59x   1.93x   2.06x
```

Nearly all available gain is captured by 2–3 concurrent requests. Going 3 -> 5
buys 0.13x for 67% more concurrency and a large increase in memory pressure.

## Decisions

### 1. Budget with a desktop reserve

```
GPU_BUDGET = TOTAL_VRAM - DESKTOP_RESERVE
DESKTOP_RESERVE = 2,048 MiB      (desktop mode, this machine)
GPU_BUDGET = 6,103 MiB
```

The reserve covers the desktop's **peak**, not its 596 MiB idle floor. Windows
compositing, Firefox, hardware video decode and Godot all draw from the same
card. The Arena does not get to claim the last slice.

`DESKTOP_RESERVE` is a configured number, not a measurement — 596 MiB is the
measured floor and the reserve is a judgement about headroom above it. It should
be raised, not lowered, if the desktop is observed stuttering.

### 2. Residency modes

```
DESKTOP MODE          (current 8 GiB card, shared with the desktop)
  resident   3        hot set, default: lfm2.5 + danube + falcon = 4,922 MiB
  parked     2        qwen, rwkv7 — loaded on demand
  free       3,229 MiB for the desktop

DEDICATED ARENA MODE  (nothing else using the card)
  resident   4        h2o+lfm2.5+falcon+rwkv7 = 5,689 MiB, the only 4-set
                      that fits a 2,048 MiB reserve alongside one other
  concurrent still 2-3

FUTURE 24 GiB CARD
  resident   5        all five comfortably
  concurrent 2-5      re-measure scaling; do not assume it extends
```

The hot three are the three fastest healthy medians (247 / 489 / 517 ms) drawn
from three different model families. It parks the two most troublesome members:
qwen is the most expensive at 1,999 MiB and was the observed spill victim;
rwkv7 degrades 3.21x under queue pressure and set the wall time in every
concurrent set it appeared in.

Note the tension: rwkv7 is the *cheapest* model at 767 MiB, so parking it saves
the least memory. It is parked on **runtime** grounds, not memory grounds.

**PIT A is exempt.** It requires all five species by design and manages its own
residency. The bridge's hot set is a runtime serving policy, not a change to any
experiment.

### 3. Concurrency

```
max_active = 2      normal
max_active = 3      burst, only while headroom is healthy
max_active > 3      never on this card
```

Requests beyond `max_active` queue. Wall time tracks the slowest participant, so
the scheduler must not put a slow model in a batch with latency-sensitive ones
purely because a slot was free.

### 4. DEGRADED detection — the tooth the benchmark lacked

The benchmark's blind spot was that a 50–100x-slow model passes both a residency
check and a liveness probe: it is loaded, and it answers every request. qwen ran
degraded through five consecutive cases reporting `fail 0`.

Measured separation between healthy and degraded is wide enough to threshold on
confidently:

```
                healthy              degraded          margin
decode      59–330 tok/s          2.4–4.5 tok/s        ~13x
TTFT          <= 377 ms         3,599–4,530 ms         ~9.5x
```

```
DEGRADED  if  decode_tok_per_s < 15   or   TTFT_ms > 1500
```

Both thresholds sit roughly 4x clear of either distribution. The decode metric
is unreliable for very fast short generations (it can read >1,000 tok/s when
generation time approaches timer resolution) — but that error is only at the
*high* end, and this test only looks at the low end, where generation is long
and the measurement is sound.

On DEGRADED: **reload or rebalance the model. Do not wait 40 seconds because it
is technically alive.** Both observed wedges recovered on unload/reload, and
freeing a neighbour's VRAM restored a spilled model twice.

Per-model latency bands are preferable to the global thresholds above and should
replace them once enough healthy samples per model exist. The global rule is the
starting point because it is defensible from data already collected.

### 5. Swap policy

Measured cold load times:

```
lfm2.5 1.77 s   danube 2.25 s   falcon 4.13 s   qwen 4.52 s   rwkv7 8.50 s
```

A swap costs between 1.8 and 8.5 seconds. **Park/swap must be hysteretic, never
per-request.** Thrashing the resident set would cost more than any scheduling
gain it could recover. A parked model's request either waits for a scheduled
swap window or is served after a deliberate promotion, and promotion demotes
something else by explicit policy rather than by allocator accident.

## What the bridge must treat as observed state

From three of five models entering a bad state during a single run:

1. **Pool composition is observed, never configuration.** Query it; do not
   assume it.
2. **Liveness is not health.** The most damaging failure answers every request.
3. **Recovery is cheap and works.** Reload is a viable remediation, not a last
   resort.
4. **A degraded model can take its co-tenant down.** Both observed wedges
   occurred in cases containing the spilled model.

## Open, not decided here

- Whether a reduced context for some members beats parking them. Context is
  pinned at 8192 across all five for PIT A comparability; the bridge could serve
  a smaller context, but nothing here measures that trade.
- Whether the 2,048 MiB reserve is right under real desktop load. It is a
  judgement, and the honest test is whether the desktop stutters.
- Whether rwkv7's queue sensitivity and its recurrent architecture are related.
  Observed together; causation not established.
- Scaling on a larger card. Not extrapolated from these measurements.
