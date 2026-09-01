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

Replicated on a later build, 260-second window:

| roster | agents spoke |
|---|---:|
| 5 distinct models | 6 |
| 1 shared model (`--fast`) | 49 |

Same ratio from an independent run after roughly twenty commits of changes, so
the effect is the swapping itself rather than a quirk of one build.

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

## BALANCED mode: the middle of the dial

The diverse roster and `--fast` are the two ends of one trade, and nothing sat
between them. `--balanced` puts N agents on M distinct models and orders the
roster so agents sharing a model are adjacent, which makes a round cost one
cold load per *model* instead of one per *agent*.

All three measured on the same build, same 260-second window, same headless
harness, no overlay attached, back to back:

| roster | distinct models | cold loads/round | agents spoke | failures |
|---|---:|---:|---:|---:|
| diverse (default) | 5 | 5 | 8 | 0 |
| `--balanced` | 2 | 2 | **33** | 0 |
| `--fast` | 1 | 1 | 64 | 0 |

**Balanced is 4.1x the diverse roster and keeps roughly half of `--fast`'s
throughput while still being a genuinely heterogeneous debate.** Two
architectures argue instead of one wearing five hats.

```
godot --headless --path . --script tools/build_roster.gd -- --balanced
godot --headless --path . --script tools/build_roster.gd -- --balanced=3
```

Why ordering matters at all: turns are taken strictly round-robin, so a cold
load is paid on every adjacent model *change*, counted circularly. Interleaved,
five agents on two models cost four loads per round; grouped, they cost two.
Same agents, same models, half the waiting. `scripts/arena/turn_order.gd` holds
the cost model and `turn_order_selftest.gd` pins the arithmetic.

Limits: one machine, one session, one topic, and throughput depends on which
models the builder happens to pick — the balanced run drew two 7Bs while the
diverse run included a 1.6B and a 4B that load faster. Treat the ratio as the
result, not the absolute counts.

## Models that fit together do not swap at all

The premise underneath everything above -- one model resident, so every model
change costs a cold load -- is only true when the models do not fit together.

Alternating requests between two models, steady state, same card:

| pair | estimated resident | per-turn cost |
|---|---:|---:|
| mistral-7b + elyza-7b | ~9 GB | 3.1s / 5.3s |
| llama-3.2-3b + stablelm-1.6b | ~3 GB | 0.03-0.06s |

The second pair matches the same-model baseline exactly (0.05s back to back).
Nothing is being evicted: both are resident, and alternating is free. The first
pair evicts each other every turn and pays a page-cache reload.

So the "variety costs throughput" trade is not a law, it is what happens when
the roster overcommits VRAM. `--fit` selects the most distinct models that fit
a budget together:

```
godot --headless --path . --script tools/build_roster.gd -- --fit
godot --headless --path . --script tools/build_roster.gd -- --fit=4.5
```

All four modes, same build, same 260-second window, same headless harness:

| roster | distinct models | resident | agents spoke | failures |
|---|---:|---|---:|---:|
| diverse (default) | 5 | no, thrashes | 8 | 0 |
| `--balanced` | 2 | no, ~9 GB | 33 | 0 |
| `--fast` | 1 | yes | 64 | 0 |
| **`--fit`** | **3** | **yes, ~5.1 GB** | **90** | **0** |

`--fit` beat single-model `--fast` while running three architectures, with
turns spread perfectly evenly (18 each) and no failures.

Read that honestly: a fitting roster wins on two counts at once, and only one
of them is residency. Its models are also *smaller* — 1.6B, 3B and 1B — so each
reply is quicker to generate as well as free of loading. The claim this run
supports is "no swapping **and** cheaper inference", not "residency alone is
worth 26 speeches". What it does establish is that the trade-off the rest of
this document describes is escapable rather than fundamental.

The budget defaults to 6.0 GB of an 8 GB card, leaving room for context, KV
cache and the desktop. Sizes are ESTIMATED from catalog parameter counts and
quantisation, because the catalog carries no file sizes; the estimate is
deliberately generous, since overcommitting is the failure this mode exists to
avoid.

### The probe has to look like a real request

`--fit` first shipped with 36 failed turns out of 88. One selected model,
`agentica-org_deepscaler-1.5b-preview`, returned HTTP 200 with empty content on
every turn — the reasoning-only class the candidate probe exists to catch.

The probe passed it because the probe was not representative. It asked
"Say the word: ready" with `max_tokens` 16, which a reasoning model answers
directly. Given the arena's actual shape — a system role, a debate prompt and
`max_tokens` 110 — the same model spends the entire budget thinking:

```
old probe     -> content="Sure! How would you like to go?"   reasoning=0 chars
arena-shaped  -> content=""                                  reasoning=559 chars
```

The probe now sends an arena-shaped request. It rejects that model, and also
rejects `h2o-danube3-4b-chat`, which earlier diverse rosters had been shipping.
A rejection now backfills from the ranked list instead of shrinking the roster,
so one mute model no longer costs an entire architecture.

## Sustained operation

A 400-second unattended run, three logical agents sharing one resident model:

```
78 speeches / 400s   ≈ 5.1s per speech
```

No crashes, no context overflow, no degradation over the run. Context cannot
grow without bound by construction: each agent keeps a rolling window of 12
messages (`MEMORY_WINDOW`) and the shared display log is capped at 12 entries.

That matters for the streamer case, where the arena is expected to run for
hours unattended behind a BRB overlay.
