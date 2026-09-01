# What JIT model swapping actually costs on 8GB

Measured, not estimated. **One machine, one session — observational, not a
universal benchmark.** Reproduce with:

```
python tools/bench_swap.py --rounds 3 --only "model-a,model-b,..."
```

## Machine

| | |
|---|---|
| GPU | NVIDIA GeForce RTX 5060, 8151 MiB, driver 580.88 |
| CPU | Intel Core Ultra 5 225F |
| RAM | 31.7 GB |
| OS | Windows 11 Home |
| Godot | 4.6.stable.official.89cea1439 |
| LM Studio | local server on 127.0.0.1:1234, auto-unload + keep-last-model |

LM Studio is configured to keep only the most recent model resident. Every turn
that changes model is therefore a **cold load**: weights off disk into VRAM
before a single token can be produced.

## Heterogeneous roster, 3 rounds, 30 requests

| model | cold median | warm median | swap cost | failures |
|---|---:|---:|---:|---:|
| ozone-ai_reverb-7b | 37.71s | 0.10s | **37.61s** | 0 |
| ibm/granite-4-h-tiny (7B MoE) | 31.32s | 0.25s | 31.07s | 0 |
| qwen3-deckard-…-6b-iii-150-i1 | 26.37s | 0.16s | 26.21s | 0 |
| llama-3.2-3b-instruct | 18.75s | 0.08s | 18.67s | 0 |
| mistralai/mistral-7b-instruct-v0.3 | 30.55s | 0.06s | 30.49s | 0 |

```
median swap cost across models: 30.49s
max swap cost observed:         37.61s
requests: 30   failures: 0 (0.0%)
```

**Warm inference is effectively free** — 60–260ms. Essentially the entire cost
of a heterogeneous roster is the swap, and it scales with weight size: the 3B
loads in ~19s, the 7Bs in 26–38s.

## Disk cache matters enormously

A separate run over four 4B models showed the first-ever load paying full disk
cost and every later load hitting the OS page cache:

```
round 1 (cold OS cache):  19.25s  18.59s  19.72s  18.58s
round 2 (warm OS cache):   2.77s   2.30s   2.24s   2.32s
round 3 (warm OS cache):   2.28s   2.26s   2.27s   2.25s
```

Same weights, **~8x faster** once Windows is caching the file. With 31.7 GB of
RAM several 4B models fit in cache simultaneously; 7B models at 30s+ suggest
they are being re-read rather than cached. Timeouts must therefore be sized for
the **uncached** case, because that is what a viewer sees on a fresh boot.

## What this proves about the timeout constants

These numbers are why the previous defaults failed, and they were the evidence
used to choose the new ones — not a guess, and not one lucky run.

| constant | old | would fail on | now |
|---|---:|---|---:|
| `request_timeout_sec` (LM client) | 20s | 4 of 5 models | **120s** |
| `TURN_STALL_TIMEOUT_SEC` (watchdog) | 30s | 3 of 5 models | **150s** |

At 20s only `llama-3.2-3b-instruct` (18.75s) fits, and only barely. That is
exactly the observed symptom: models appeared dead when they were merely
loading, and the arena reported `result=13` (Godot `RESULT_TIMEOUT`) or skipped
the turn as unresponsive.

The new values carry **3.2x headroom** over the worst observed swap (37.61s).
That margin is deliberate: the sample is 30 requests on one machine with a warm
disk cache for part of it, and a slower disk or a larger model would move the
tail. Do not lower these based on a faster run.

## Practical consequences for a roster

- **Fewer distinct models = far more turns per minute.** Five models means a
  swap every turn; two models alternating still swaps every turn. Any roster
  where consecutive turns share a model gets warm-path latency for free.
- **Mixing a 3B with 7Bs** makes the 3B's turns visibly snappier. That is a
  pacing tool, not a defect.
- **0% failure rate across 30 requests** once timeouts are correct. The
  reliability problem was never the swapping; it was measuring it wrong.

## Method and limits

- `tools/bench_swap.py` talks to LM Studio over HTTP directly, so the numbers
  describe the runtime rather than Godot.
- `cold` = first request after a different model was resident. `warm` = an
  immediate second request. `swap cost` = cold − warm.
- 3 rounds per model. Medians reported; p95 only where n ≥ 5, which this sample
  does not reach per-model. Treat the maximum as the planning number.
- Not measured: concurrent requests, long-context loads, quantisations other
  than those installed here, or any GPU other than this one.

## FAST mode: what sharing one model actually buys

Same machine, same 280-second window, same five logical agents.

| roster | turns started | agents spoke | cold-load heartbeats |
|---|---:|---:|---:|
| 5 distinct models | 10 | **7** | 21 |
| 1 shared model (`--fast`) | 49 | **49** | 3 |

**7x more speeches, and a 100% completion rate against 70%.** The three
heartbeats in FAST mode are the single initial load; after that the model stays
resident and every turn runs on the warm path.

```
godot --headless --path . --script tools/build_roster.gd -- --fast
```

The trade is real and it is not free: FAST gives up the heterogeneity that is
the whole point of the project. Five agents share one set of weights and differ
only by persona and memory, so "three architectures arguing" becomes "one
architecture wearing five hats".

Use the diverse roster to demonstrate what the project *is*. Use `--fast` when
you want conversation throughput — long unattended streams, testing template
behaviour, or filling a BRB overlay — where waiting 40 seconds per line is the
dominant cost.
