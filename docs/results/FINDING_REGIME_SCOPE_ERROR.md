# FINDING — the population-regime rule was applied to the wrong population

```text
ID:              REGIME-1
SEVERITY:        BLOCKER for the four-arm rerun
EVIDENCE CLASS:  EXECUTED_WITNESS
STATUS:          RAISED, NOT FIXED. Two frozen documents are affected, one of
                 them human-cleared, so the correction is not mine to make.
RAISED:          2026-09-08, BEFORE the first runtime contact of the rerun.
                 No model was loaded. No arm was started. Nothing is
                 contaminated.
```

## The claim that is false

`PREREG_RUNTIME_MEMORY_RERUN.md` states:

> This run is **REGIME B** (5 species, 1 instance each). Every artifact it
> produces must carry `population_regime_id: "B"`.

It is not Regime B. Tagging the artifacts `"B"` would write **false
provenance** — the exact failure the regime machinery was built to prevent.

## The witness

```text
$ grep -n "^const POOL" tools/runtime_memory.gd
30: const POOL := ["liquidai/lfm2.5-1.2b-instruct", "qwen3.5-2b",
                   "falcon-h1-1.5b-instruct"]

$ python -c "...arena-species.v1.json..."
REGIME B: ['liquidai/lfm2.5-1.2b-instruct', 'falcon-h1-1.5b-instruct',
           'qwen3.5-2b', 'rwkv7-1.5b-g1', 'h2o-danube2-1.8b-chat']
```

The RUNTIME-MEMORY harness measures a **3-model pool**. Regime B is a
**5-species Arena roster**. The pool is a strict subset — `OZONIOUS` (rwkv7) and
`BRINE` (danube2) are not in it, and never were.

The existing arm artifacts agree, and always did:

```text
$ RUNTIME_MEMORY_IDLE.json        pool -> [lfm2.5, qwen3.5-2b, falcon-h1]
$ RUNTIME_MEMORY_FULL_WINDOW.json pool -> [lfm2.5, qwen3.5-2b, falcon-h1]
```

**COULD-HAVE-FAILED:** yes. Had `POOL` matched the five canonical species, the
prereg's claim would have been correct and this finding would not exist.

## The second, larger error

`POPULATION_REGIMES.md` assigns **every result up to 2026-09-08** to Regime A,
and `config/population-regime-a-legacy.json` freezes that attribution over 151
artifacts. Executed check:

```text
stablelm-2-zephyr-1.6b       0 artifact(s)
h2o-danube3-4b-chat          0 artifact(s)
gemma-3-1b-it-fast-guff      0 artifact(s)
```

**The Regime A Arena roster produced zero tracked result artifacts.** The 151
artifacts in the frozen snapshot were not collected under Regime A. Attributing
them to it is wrong — and it is wrong in a frozen, content-hashed file that was
built specifically to make attribution mechanical and trustworthy.

## Root cause

Two different populations were collapsed into one noun:

```text
ARENA AGENT ROSTER          who debates in the Arena
                            Regime A: stablelm / danube3 / gemma  (2+2+1)
                            Regime B: the five canonical species  (1x5)
                            -> produced ZERO tracked result artifacts so far

RUNTIME-MEMORY MODEL POOL   which models are loaded and measured
                            lfm2.5 / qwen3.5-2b / falcon-h1
                            -> produced the RUNTIME-MEMORY arms
```

These have different memberships, different purposes, and different lifetimes.
`population_regime_id` is meaningful for the first. It was applied to the second
by assumption, never checked, and then frozen.

This is `ARENA_IDENTITY_LAYERS.md`'s own error, committed one commit after the
doctrine was written: **a population inferred rather than declared.** The layer
rules were correct; the scope they were applied at was not.

## What is NOT wrong

- The regime machinery itself. `population_regime.py` works, fails closed, and
  its sabotages bite. It is enforcing a correct rule over a wrong assignment.
- The three-layer boundary doctrine.
- The P6 decision to rerun all four arms. Nothing about that depends on regime
  labelling.
- The P4 seven-witness requirement, or the P5 scope limits.
- The existing arm artifacts. They recorded `pool_identity` honestly the whole
  time — the harness was never confused, only the new documentation was.

## Options, none taken

1. **Scope the regime field to Arena-roster results only**, and let
   RUNTIME-MEMORY continue identifying its population by the `pool_identity` it
   already records. Smallest change; leaves 151 artifacts correctly unlabelled
   rather than wrongly labelled.
2. **Introduce a second axis** (e.g. `measurement_pool_id`) for experiments that
   measure a model pool rather than run an agent roster.
3. **Change `POOL` to the five canonical species**, making the prereg's claim
   true. This is a *design change to the experiment*, not a relabelling, and it
   is not authorised by the current clearance.

Option 3 changes what is measured. Options 1 and 2 change only what it is
called. That distinction should decide it, not convenience.

## Why the run is stopped

The clearance authorises a run under a frozen prereg. That prereg contains a
false statement about the run's population and requires a tag that would be
false. Proceeding would produce four artifacts carrying incorrect provenance,
which no later correction fully removes — and the whole point of freezing the
prereg before data was that its contents could be trusted.

Cheapest possible moment to catch it: no runtime contact has occurred.
