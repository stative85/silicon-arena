# EXPLICIT_RESIDENCY_MODE Pool Throughput Benchmark

**Status:** method frozen before measurement
**Instrument:** `tools/bench_residency.py`
**Regime label:** `EXPLICIT_RESIDENCY_MODE` (stamped into every output record)

## What this is

Hardware and runtime characterisation of the five-species resident pool, taken
before any inference bridge is written. The bridge's scheduling decisions should
follow from measured service behaviour, not from an assumption about it.

## What this is not

- Not a model-quality evaluation. No output is inspected for correctness.
- Not a leaderboard. There is deliberately **no combined performance score**.
  A single number would average away the exact structure being measured.
- Not a bridge. No bridge code is written until these numbers are frozen.

## Why the regime label is not decoration

The METABOLISM correction established that two different loading regimes exist
on this box and produce opposite-looking results:

| Regime | Acquisition | Observed behaviour |
|---|---|---|
| `JIT_RESIDENCY_MODE` | model loaded on demand by the request | requesting B evicts A; pool of one |
| `EXPLICIT_RESIDENCY_MODE` | all five preloaded, never unloaded | five co-resident at 8192 ctx |

Per Rule 13, *a runtime property must be qualified by the loading and execution
regime under which it was observed.* Numbers from these two regimes are not
comparable and must never be placed in the same table. Every record here carries
the regime string so a future reader cannot mix them by accident.

A JIT-loaded model is identifiable by a TTL in `lms ps`. The pool used here is
loaded explicitly with no TTL.

## Frozen pool

```
h2o-danube2-1.8b-chat            1.11 GB
liquidai/lfm2.5-1.2b-instruct  730.90 MB
qwen3.5-2b                       1.28 GB
falcon-h1-1.5b-instruct        944.79 MB
rwkv7-1.5b-g1                    1.02 GB
```

All at context 8192, `--gpu max`, no TTL.
Resident footprint **7,710 MiB of 8,151 MiB — 441 MiB headroom.**

That headroom is the single most important fact about this benchmark. It is
under half a gigabyte. Concurrency is being measured against a card that has
almost no slack, and the honest possible outcome is *this regime does not
support N-way concurrency*.

## Residency assertion (the central tooth)

The resident set is asserted **before and after every case**. If it changed, the
case is marked `FAILED`, what disappeared is recorded, and the pool is rebuilt
before continuing.

The benchmark never silently continues under a different regime. A case that
evicted a model measured something other than what it claims to measure, and
saying so is the result.

## Measurement design

**Streaming.** `stream=true` on every request so time-to-first-token is measured
at the first content delta rather than inferred from total latency. TTFT and
generation time answer different scheduling questions and are never summed into
one figure.

**Per-request record.** model, ok/failed, TTFT ms, total ms, generated tokens,
decode tokens/sec, plus per-case resident set and VRAM before/after and a GPU
sample (utilisation, memory utilisation, power, temperature).

**A caveat on decode tokens/sec.** It is computed as deltas divided by
(completion - first token). For short fast generations that denominator is a
few milliseconds, so the figure is dominated by timer resolution and by how the
server batches deltas -- `falcon` reports over 1,500 tok/s alone, which is not a
real decode rate. **Total latency and TTFT are the trustworthy numbers here;
tok/s is indicative only** and is never used in a decision or a derived ratio.

**Warmup.** Three requests per model per workload, discarded, never in any
statistic.

**Statistics.** Median and p95, reported separately. No means — the tail is the
part a scheduler has to survive, and a mean hides it.

### Workloads

| Name | Shape | Max tokens |
|---|---|---|
| `A_micro` | 16-32 token arena-style reply | 32 |
| `B_turn` | realistic 64-96 token arena turn over a small world | 96 |
| `C_256` / `C_1024` / `C_4096` / `C_7000` | context pressure at four depths | 48 |

`C_7000` deliberately approaches the 8192 ceiling. Prompt sizes are set by
character budget (~4 chars/token), so the depths are approximate by design and
are reported as nominal depths, not exact token counts.

### Phases

1. **Solo baseline** — one model at a time on an otherwise idle card,
   >= 10 measured requests per model per workload. This is the denominator for
   everything after it.
2. **Concurrency** — 2-way, 3-way and 5-way, each behind a real
   `threading.Barrier` so the requests genuinely begin together rather than
   merely overlapping. Pairs are chosen by measured speed class
   (fast+fast, fast+slow, slow+slow, med+slow) because the interesting question
   is whether a slow model blocks a fast one.
3. **Sustained queue** — >= 100 requests round-robined across the five at
   max-in-flight 1, 2, 3 and 5.

### Derived quantities

```
slowdown_ratio  = concurrent_median_ms / solo_median_ms      (per model)
throughput_gain = inflight_N_req_per_s / inflight_1_req_per_s
```

Both are reported per model and per level. They are ratios of measured medians,
never of a blended score.

## Known solo latencies going in

From the correction-to-the-correction, all five resident, sequential, idle card:

```
lfm2.5    249 ms      rwkv7   493 ms     qwen3.5  1,901 ms
falcon  3,522 ms      danube2 4,228 ms
```

A **17x** spread between fastest and slowest. That spread, not any average, is
the fact a bridge has to be designed around.

## Instrument defects found during smoke testing

Both were found by a `reps=1` smoke run before any measurement was taken, and
both are recorded because a benchmark that hides its own repairs is a story
about itself.

### 1. A resident model can wedge, and residency cannot see it

During the first smoke run `lfm2.5` -- the *fastest* model in the pool --
entered `GENERATING` and stayed there for over thirty minutes at 2% GPU
utilisation. It was not slow; it was wedged. Every subsequent request to it
timed out, at every context depth, streaming and non-streaming alike. The other
four models answered normally throughout, so the server itself was healthy.

`lms unload` followed by `lms load` cleared it completely.

The important part is the detection gap. **A wedged model is still `RESIDENT`.**
The residency assertion -- the benchmark's main tooth -- looks at the loaded
set and sees five models, exactly as expected, and reports the regime intact
while one member of the pool is a corpse. Residency and liveness are different
properties, and only one of them was being checked.

Three changes followed:

- `REQUEST_TIMEOUT_S = 120`, a bounded ceiling. The slowest legitimate solo
  request measured is ~5 s, so nothing inside the real distribution can reach
  120 s. Previously the harness could block indefinitely, and did.
- A `health_probe` after any case containing a timeout: a separate liveness
  check that does not trust the resident set.
- `unwedge` -- reload the model, re-probe, record the event, and mark the case
  `FAILED`. Wedge events are written to the output as `wedge_events`.

This is not merely a harness bug. **An intermittently wedging model instance is
a runtime property of this pool, and the inference bridge will have to handle
it.** It is the first hard requirement this benchmark has produced: the bridge
needs liveness checking and instance recovery, not just a model registry. The
trigger was not identified and is not claimed to be understood -- it did not
reproduce across depth sweeps or repeated streams. It is recorded as observed
and defended against, not as diagnosed.

### 2. A killed benchmark kept running and corrupted the next one

Stopping the smoke run killed its shell but **not its Python child**. The
orphan kept issuing requests and calling `lms load` for another twenty minutes,
against a pool the next experiment believed it controlled.

The visible symptom was absurd: after `lms unload --all` followed by loading
exactly one model, the resident set came back as *two* models. The second was
being loaded by a process that was supposed to be dead.

Every `ALONE_IN_POOL` case in the first pressure run was skipped as a result,
and the run aborted at `POOL INCOMPLETE`. That is the correct outcome and worth
stating plainly: **the guards refused to mislabel a two-model set as
`ALONE_IN_POOL`.** Without the exact-resident-set assertion, the run would have
produced a full table of confident "alone" numbers measured with a second model
resident, and nothing in the output would have shown it.

Operationally: verify no `python.exe` running a benchmark survives before
starting another, and treat an unexpected member of the resident set as a live
process, not a glitch.

### 3. `lms unload --all` exits non-zero on success

It returns exit code 1 while correctly unloading everything. Return code is
therefore not usable as the success signal; the resident set is queried
afterwards instead. Nothing in the harness branches on that exit code.

### 4. `lms` output is not decodable by the system locale

`subprocess.run(..., text=True)` decodes with the Windows locale codec (cp1252),
and `lms` emits bytes that codec has no mapping for -- its spinner frames.
Every call raised `UnicodeDecodeError`, so `unload_all()` and `load()` *never
actually ran*, silently, while looking like ordinary calls in the source.

This is the same class as the `C_7000` defect below and the vertical-tab
incident before it: an operation that appears to have happened, did not, and
said nothing. Fixed with `encoding="utf-8", errors="replace"` at all five call
sites across both tools.

### 5. The deepest context case was not measuring its stated depth

`workload_c` built its filler from 400 repeats -- 21,600 characters. At roughly
4 characters per token, the `C_7000` case needs about 28,000. Python slices past
the end silently, so `C_7000` was submitting ~5,400 tokens while labelling
itself 7000: a case that reported the depth it intended rather than the depth it
achieved.

Fixed to 2,000 repeats with an explicit `assert len(filler) >= approx_chars`, so
a future depth increase fails loudly instead of quietly measuring something
shallower. Depths remain nominal (character-budgeted, ~4 chars/token) and are
reported as such.

## A precondition the smoke run forced, and a wrong hypothesis

The smoke run's first two solo cases came back like this:

```
A_micro   danube   17,946 ms   TTFT 4,505 ms   2.3 tok/s
A_micro   lfm2.5        86 ms  TTFT    80 ms
```

A 1.8B Q4 model does not decode at two tokens per second on an RTX 5060. I read
that as VRAM pressure -- layers or KV cache spilling off a card with only
441 MiB of headroom -- and wrote up a ~200x pool spread on that basis.

**That was wrong, and the mechanism was mundane.** The 17,946 ms was measured
while an orphaned Python process from the *previous* smoke run was still issuing
requests against the same pool (defect 2 above). It was contention from a
process I believed I had killed. Not spill, not architecture. The ~200x figure
is retracted; it never measured what it claimed to.

The question it raised was still worth answering, so it was answered properly.

### The measurement

`tools/bench_pressure.py` times each model on an identical workload under two
conditions -- `ALONE_IN_POOL` (sole occupant) and `FULL_POOL` (all five) -- both
`EXPLICIT_RESIDENCY_MODE`, so the only variable is how many other models are
resident. Run on a verified-clean machine with no surviving processes.

```
                ALONE_IN_POOL              FULL_POOL        penalty
                med      ttft   vram       med      ttft
danube          290 ms    54    2272 MiB   326 ms    52     1.13x
lfm2.5           78 ms    55    1634 MiB    91 ms    64     1.17x
qwen3.5         362 ms    96    2578 MiB   380 ms   121     1.05x
falcon          110 ms   105    2156 MiB   129 ms   123     1.17x
rwkv7           509 ms   165    1774 MiB  1348 ms   277     2.65x

spread          6.5x                       14.7x
pool VRAM       10,414 MiB if summed       7,674 MiB actual
```

### What this says

**Co-residency is mostly cheap, but not uniformly.** Four of the five species
pay between 5% and 17% for sharing the card -- small enough that the pool is a
sound regime to benchmark inside.

**rwkv7 is the exception, at 2.65x.** It is also the one architecturally
distinct member of the roster: a recurrent/linear-attention model whose runtime
state is not a conventional KV cache. It is the only species whose cost changes
materially with the resident set, and it absorbs most of the spread inflation --
from 6.5x alone to 14.7x in the pool. Nearly all of that widening is one model.
Whether the cause is recurrent-state placement or something else is **not
determined here**, and is not claimed.

**The pool is oversubscribed and something is being given up.** Summed
standalone footprints come to 10,414 MiB against an 8,151 MiB card, yet all five
co-reside at 7,674 MiB. Roughly 2.7 GiB is being economised somewhere. What gets
economised, and whether rwkv7's penalty is the visible price of it, is a
hypothesis this benchmark does not test.

### Consequence for the main benchmark

It runs as specified above, unchanged. Two labelling requirements follow:

- Every result is stamped with the resident-set size it was taken under.
  `FULL_POOL` and `ALONE_IN_POOL` numbers are not comparable for rwkv7.
- The **17x** spread carried in from the earlier sequential probe is not
  reproduced here. This instrument measures 6.5x alone and 14.7x in the pool, on
  its own workload. These are different measurements, not a correction of that
  one, and are not merged with it.

## Stopping rule

If concurrency causes eviction or OOM, that regime is recorded as **unsupported
at this VRAM headroom** and the run continues to the next case. Nothing is tuned
mid-benchmark to make a case pass. Fixing the instrument while it is measuring
is how a benchmark becomes a story about itself.
