# ASYNC-A Run 1 — VOID

**All three live arms are VOID on preregistered conditions.** No ASYNC-A
question is answered by this run. Written before any interpretation, and no
data from it is used to argue anything about timing.

Frozen configuration: 16 resources, hold 4, 3 agents, 800 observation ticks,
tick 250 ms, equalizer 4 ticks (1000 ms), contract schema
`f5a2aaf89dfa6ffa`. Run in the frozen order.

## Result

```
ARM            actions  ACCEPT  STALE  CONT_LOST  SEM_INV  PASSED   status
SERIAL            2400    1801      0        399        0     200   VOID
NATURAL           1101     894    117          0        2      88   VOID
EQUALIZED          600     402     99          0        0      99   VOID
ORDER_REPLAY      1101     894    117          0        2      88   (see below)
```

## Why it is void

**Preregistered condition: `SHAPE_FAILED` above 10% for any agent.** From
Amendment 1 — *"the contract is not expressible and the descriptors would
measure contract-satisfaction, as in PIT A Run 1."*

```
agent          model      SERIAL   NATURAL   EQUALIZED
agent_0        lfm2.5       0.0%      0.0%        0.0%
agent_1        danube2     25.0%     31.7%       49.5%
agent_2        falcon       0.0%      0.0%        0.0%
```

`agent_1` (h2o-danube2-1.8b-chat) failed to emit `{"target_id": "..."}` on a
quarter to a half of its calls, across 2,400, 1,101 and 600 model calls
respectively. That is a firm estimate, not small-sample noise.

The other two models failed **zero times out of thousands of calls**. The
contract is expressible; one model cannot express it.

**Second condition, EQUALIZED only:** one `EQUALIZER_BREACH` — a completion
later than the 1000 ms deadline, meaning real latency re-entered the arm built
to remove it. Amendment 4 makes any breach void the arm.

## What is NOT concluded

- **No claim about timing.** Q1, Q2 and Q3 are unanswered. A 25-50% shape
  failure rate concentrated in one agent contaminates every per-agent measure,
  which is exactly what the condition was written to prevent.
- **No claim that danube2 is a worse model.** It failed *this* contract under
  *these* conditions. Nothing here measures capability.
- **The rising shape rate across arms (25.0% -> 31.7% -> 49.5%) is NOT
  interpreted.** It is recorded because it is a striking pattern and the raw
  data is preserved, but the arms differ in prompt cadence, in-flight
  concurrency and the number of calls per agent, and a void run is not evidence
  for anything.

## Arm 4

`ORDER_REPLAY` passed its own teeth and is reported for instrument
completeness only:

```
model_calls                 0
observation_calls           0
source                      NATURAL_r0
corpus hash stable          true (before == during == after)
envelopes reordered         482
pairwise inversions         241
ordering_exercised          EXERCISED
journal differs from source true
```

The counterfactual machinery works: zero model calls, the source fossil
unmutated, the transform genuinely applied, and the replay journal differs from
the source journal despite identical aggregate counts.

**But its source replicate is VOID, so arm 4 is void by inheritance.** A
counterfactual replay of contaminated cognition is contaminated cognition in a
different order.

## What the instrument did right

Every arm's own structural teeth passed:

```
SERIAL      STALE_CONFLICT 0, STALE_REVALIDATED 0, all observation ages 0
NATURAL     117 stale conflicts against SERIAL's 0 -- the arm contrast is real
EQUALIZED   the single breach was detected rather than absorbed
ORDER_REPLAY corpus hash identical before, during and after
```

`SEMANTIC_INVALID 2` in NATURAL is worth recording: a genuinely hallucinated
target reached the classifier and was scored. That confirms Amendment 10's
refusal to enumerate visible ids in the schema kept the outcome observable —
had the enum been added, that control variable would have been silently
deleted.

## Preserved

```
docs/results/ASYNC_A_SERIAL_r0.json
docs/results/ASYNC_A_NATURAL_r0.json
docs/results/ASYNC_A_EQUALIZED_r0.json
docs/results/ASYNC_A_ORDER_REPLAY_r0.json
docs/results/ASYNC_A_NATURAL_r0_corpus.json
```

Manifests carry per-agent shape rates, runtime envelopes, resident-set
witnesses, journal and world hashes, corpus hashes and replay exposure counts.
Nothing is deleted.

## Not done

No amendment. No threshold change. No model substitution. No prompt rescue.
No re-run.

The void is the result of this run. What to do about a model that cannot
satisfy a one-field contract is a separate decision, and it is the user's.
