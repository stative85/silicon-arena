# Inference Bridge — Design

**Status:** v1 implemented — streaming, real TTFT, per-slot connections
**Built from:** `docs/results/BENCH_RESIDENCY_RESULTS.md`, `docs/results/bench_pressure.json`, `docs/results/vram_budget.json`
**Code:** `scripts/arena/bridge_policy.gd`, `bridge_ticket.gd`, `bridge_model.gd`, `bridge_receipt.gd`, `sse_parser.gd`, `bridge_stream.gd`, `inference_bridge.gd`
**Tests:** `bridge_selftest.gd` (76 checks) + `sse_parser_selftest.gd` (29 checks), offline, both in `verify.cmd`
**Live check:** `tools/bridge_live.gd` (needs LM Studio; not in verify)

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
HARD_DEGRADED      TTFT_ms > 1500                      authoritative
SUPPORTING_SIGNAL  decode_tok_per_s < 15               corroborating only,
                   AND generated_tokens >= 16          never condemns alone
```

**Why decode is demoted to a supporting signal.** `BENCH_RESIDENCY_RESULTS.md`
records that decode tok/s is unreliable when generation time approaches timer
resolution -- falcon read over 1,500 tok/s on short outputs -- and states
plainly that total latency and TTFT are the trustworthy quantities. Promoting
decode to a co-equal tooth would contradict the document it was derived from.
An 8-token completion has a denominator too small to trust, and must never on
its own declare a model dead. The `min_tokens_for_rate` gate exists for exactly
that case and is tested.

Both thresholds sit roughly 4x clear of either distribution.

On DEGRADED: **reload or rebalance the model. Do not wait 40 seconds because it
is technically alive.** Both observed wedges recovered on unload/reload, and
freeing a neighbour's VRAM restored a spilled model twice.

A single breach is not a diagnosis; `degraded_strikes = 2` consecutive breaches
are. Per-model latency bands are preferable to these global thresholds and
should replace them once enough healthy samples per model exist. The global rule
is the starting point because it is defensible from data already collected.

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

## v1 — streaming

v0's `ttft_ms` was politely lying: the non-streaming transport recorded the
completion instant, so TTFT and total latency were the same number. Since TTFT
is the authoritative health signal, every health decision rested on an
approximation. v1 removes it.

### Per-slot connections

Each active slot owns a private `HTTPClient` (`bridge_stream.gd`). The v0
pattern — one shared `HTTPRequest` with `cancel_request()` — cannot survive
concurrency: cancelling a wedged danube request would also kill the in-flight
lfm2.5 and falcon requests. Independent cancellation is the point.

### The SSE parser

`sse_parser.gd` buffers **bytes, never text**, because a multi-byte UTF-8
character can be split across TCP packets and decoding a partial chunk would
corrupt it before parsing began. A complete event is decoded exactly once,
whole. Tested by replaying a stream split at every one of 168 byte offsets, and
again one byte at a time, requiring identical output each way — plus the same
sweep over a multi-byte payload.

**The first SSE event is not the first token.** A server may open with a
role-only delta carrying no content. Timestamping that as TTFT would understate
prefill by however long generation actually takes to begin, so `first_event`
and `first_content` are recorded separately and only `first_content` feeds the
health classifier.

A malformed frame is flagged and the stream continues; one bad event must not
kill a live generation.

### Four timeout classes

```
CONNECT_TIMEOUT       no connection or response headers   -> WEDGE
TTFT_TIMEOUT          connected, generation never began   -> WEDGE
STREAM_IDLE_TIMEOUT   generation began, then froze        -> STALL
TOTAL_TIMEOUT         absolute ceiling                    -> STALL
```

One giant timeout would collapse three different pathologies into one useless
label. These map onto failures already observed: a wedge that never responds, a
spilled model responding 100x slowly, and a generation that starts then stops.
Recovery keys off the mechanical class, not a guess.

A stream closing without `[DONE]` is `TRUNCATED`, not OK — a half generation
must never be recorded as a healthy call.

### Receipts

Now carry `connected_at_ms`, `first_event_at_ms`, `first_content_at_ms`,
`connect_ms`, `ttft_ms`, `generation_after_first_ms`, `total_ms`, `queue_ms`,
`stream_event_count`, `content_event_count`, `failure_kind`.

`decode_estimate` is named an estimate deliberately: the streaming API reports
no token count, so content events stand in for tokens. Calling it `decode_tps`
would imply a precision that is not there — and it remains a supporting signal
only, gated on `min_tokens_for_rate`.

### Measured live

Against the resident hot set, three sequential then three concurrent requests:

```
lfm2.5   ttft 213 ms   gen  96 ms   total 309 ms
danube2  ttft 199 ms   gen 104 ms   total 303 ms
falcon   ttft 269 ms   gen 172 ms   total 441 ms
```

TTFT is now a distinct measurement rather than a copy of total. The concurrency
cap was observed working: with `max_active = 2`, the third concurrent request
queued for 186 ms.

**Not verified live:** LM Studio emitted no role-only opening frame in these
runs, so `first_event != first_content` was exercised only in unit tests.

### Deliberately not done yet

**Per-model latency bands.** The thresholds stay global until the bridge has
collected real TTFT distributions through its own streaming path across a few
hundred healthy calls. Deriving bands now would mean thresholds arriving from
imagination wearing a lab coat — the receipts exist precisely so the bands can
come from measurement instead.
