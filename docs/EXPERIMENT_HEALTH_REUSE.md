# HEALTH-REUSE — does prompt-set reuse explain the anchor contradiction?

**Status:** pre-registered before implementation, model calls, or outcomes.

Replaces HEALTH-PREFIX, whose premise was tested against the Cell-A fossils and
found **false** (`0f25d04`): production had no content-prefix continuity either
(LCP median 25 chars = header only; first item changed on 100% of rounds), so a
production-trace vs prefix-broken contrast would have been NOT EXERCISED.

## What survived that check, and why this experiment exists

Cell A's 200 rounds contain only **~10 distinct prompts** (94.9% duplicates),
every repeat at **gap >= 4**. I previously dismissed this as irrelevant on the
grounds that a single KV context is evicted before the repeat returns.

**That was an assumption about LM Studio's internals, not a measurement.** If
the runtime retains more than one cached sequence, production received a large
reuse benefit on ~95% of its calls that both health harnesses removed by
construction.

## Question

> Does production-like prompt-set reuse explain why ASYNC-B cell A stayed
> healthy while the synthetic harness drove qwen3.5 to 13-69% SUSPECT at the
> same nominal prompt size?

## Design

```text
CYCLING   replay cell A's exact visible sequences, in order:
          200 rounds, ~10 distinct prompts, repeats at gap >= 4
UNIQUE    same per-round list LENGTH, same alias vocabulary,
          a distinct subset every round: 200 distinct prompts

pool      LFM2.5 + Qwen3.5 + Falcon, explicit residency, unchanged
health    shadow; ks=1.8 / kh=20 / n=3 untouched
schema    unchanged one-field async_action; max_tokens 24; temperature 0
probing   all three models SIMULTANEOUSLY each round
rounds    200 -- the full cell-A session length, not a partial match
```

Counterbalanced: two processes run CYCLING then UNIQUE, two run UNIQUE then
CYCLING. Fresh client and `arm_baseline` before each. **No model reload** --
that would inject Blocker 2.

## Teeth

```text
prompt_tokens must match per round between conditions   else VOID that pair
distinct-prompt count must differ (~10 vs 200)          else NOT EXERCISED
CYCLING must reproduce cell A's gap structure (min 4)   else NOT EXERCISED
pool not exactly the frozen three at start/end          -> VOID
host memory below the frozen 2 GB floor                 -> VOID
any recovery fires                                      -> VOID
```

## Measured

TTFT, expected_ttft, residual, verdict, SUSPECT rate, max consecutive SUSPECT,
DEGRADED count. Descriptively and with no thresholds attached: host free RAM by
round, round_index, process_elapsed_ms, whether the round's prompt is a repeat
and its gap to the previous identical prompt.

## Pre-registered readings

```text
CYCLING reproduces cell-A-like low qwen SUSPECT while UNIQUE stays elevated
  -> prompt-set reuse explains a major part of the anchor contradiction

both elevated
  -> reuse is not the missing variable; runtime history remains unresolved
     and NO repair may be designed

both healthy
  -> the earlier harnesses contained a further unidentified difference

falcon moves strongly between conditions
  -> the intervention changed general runtime behaviour and the
     model-specific reading is weakened
```

## Out of scope

No fitting. No knot, threshold or contention-factor change. No OUT_OF_PROFILE.
No repair inside the diagnostic. No RECOVERY-COUPLING. No B2.
