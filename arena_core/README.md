# arena_core — the spine

Mission in, verified artifact out. Headless Python, stdlib only, no pytest.

```
Draft ──▶ Critique ──▶ Revision ──▶ Verification
            ▲                            │
            └────────────────────────────┘
```

## Run it

```bash
# what will actually load on this box (8GB card — check before picking!)
python -m arena_core.run_mission --list-models

python -m arena_core.run_mission \
  --mission arena_core/missions/word_wrap.json \
  --model qwen3-4b-instruct-2507-gemini-3-pro-preview-distill

# the baseline question, with numbers
python -m arena_core.bench \
  --mission arena_core/missions/word_wrap.json \
  --model qwen3-4b-instruct-2507-gemini-3-pro-preview-distill --trials 5

# tests (16, all stdlib)
python -m unittest discover -s arena_core/tests -t .
```

Outputs land in `arena_core/runs/<mission>_<timestamp>/`: `solution.py` (the
artifact), `report.md`, `run.json`.

## Known-good models on this machine

8GB VRAM with dynamic loading. **Verify a model loads before benchmarking it.**

| model | status |
|---|---|
| `qwen3-4b-instruct-2507-gemini-3-pro-preview-distill` | works, follows format |
| `adg-alpaca-gpt4-qwen2.5-7b` | loads, poor instruction-following |
| `google/gemma-4-26b-a4b` | **will not load** — too big |
| `google/gemma-4-e4b` | **will not load** |
| `lmstudio-community/meta-llama-3.1-8b-instruct` | **will not load** |

## Rules the loop actually enforces

1. **Only the verifier decides.** Agents never vote on quality.
2. **The critic attacks real output** — actual tracebacks plus re-evaluated
   observed values, never the draft's vibe.
3. **Best carries forward.** A regressing revision is discarded, so a run
   cannot walk downhill.
4. **Stop** on success, on budget, or after 2 cycles with no improvement.
5. **Every cycle prints its exact delta.** No delta, no improvement claim.

## Preflight

`CodeVerifier.self_check()` runs before any tokens are spent. It rejects a
mission whose tests don't parse, collect nothing, or **pass against a stub that
implements nothing** — tests that assert nothing would rate every candidate
perfect. A dead instrument fails loudly instead of silently scoring everything 0.

## Current honest standing

Benchmarked on `word_wrap` (12 tests), qwen3-4b, 5 trials each:

| | mean | best-of-5 | cost |
|---|---|---|---|
| single-shot | 0.417 | **0.750** | 1x |
| arena | **0.500** | 0.583 | 10.3x |

**The arena raises the floor and lowers the ceiling.** Its mean beats
single-shot's mean (+0.083), and the repair loop genuinely lifts its own drafts
(+0.117) — but one arena run costs ~10 samples, and the best of 5 cheap samples
(0.750) beat the best arena run (0.583).

**Under matched budget, best-of-N sampling currently wins.** The loop's
mechanics are correct and tested; its *yield* is not yet worth its tokens on
this task with this model. Do not claim otherwise until this table flips.

The first version of `bench.py` printed "ARENA WINS" by comparing means. That
was the wrong baseline and it flattered the thing I had just built — the
verdict now compares against best-of-N at matched cost.

### Why it stalls (next thing to fix)

Every arena trial ended in `stalled - 2 cycles with no improvement`, none
reached 12/12. The critic diagnoses correctly once it can see observed values,
but the repairer rewrites the whole module each cycle and reintroduces defects
it had already fixed. Likely fixes, in order:

1. **Regression-guard the repair** — feed the repairer the list of tests that
   currently PASS and forbid breaking them.
2. **Patch, don't rewrite** — target the failing function, not the file.
3. **Multiple repair candidates per cycle**, keep the best verified one. This
   is where the arena's parallelism should finally pay for itself, and it is
   the most likely route to beating best-of-N.
