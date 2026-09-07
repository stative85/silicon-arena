# ASYNC-A2 — Pre-registration

**Status:** pre-registered. No ASYNC-A2 run has occurred.
**Predecessor:** ASYNC-A Run 1, VOID (`241d86c`) — producer-interface
incompatibility, danube2 `SHAPE_FAILED` 25.0 / 31.7 / 49.5% across arms.

## The boundary on Run 1 data

> Data from ASYNC-A Run 1 are **not** used to estimate timing effects, select
> hypotheses, or choose expected effect directions. They are used **only** to
> diagnose the preregistered void and to repair roster and runtime
> qualification for this successor experiment.

Concretely: Run 1 told us danube2 cannot express the contract, and that the
equalizer gate was underpowered at 180 completions. Both are instrument facts.
Nothing from Run 1's stale-conflict counts, acquisition distributions or arm
contrasts informs any expectation here.

## What is unchanged from ASYNC-A

Everything except the roster.

```
scientific questions   Q1, Q2, Q3 unchanged (Amendments 1-11 apply in full)
world                  16 resources, hold 4, substrate-owned regeneration
agents                 3
contract               {"target_id": "..."}, free string, no enum
horizon                800 observation ticks, all live arms
tick                   250 ms
equalizer              1000 ms = 4 ticks
arms                   SERIAL, NATURAL, EQUALIZED, ORDER_REPLAY
ordering transform     LATENCY_RANK_INVERSION
health policy          ks = 1.8, kh = 20.0, n = 3
all machinery          world, step engine, envelopes, agent lifecycle,
                       timing policy, runtime guard, void conditions
```

The world calibration is **not** re-run: it calibrated 3 synthetic actors
against 16 resources and hold 4, and never depended on danube-specific
behaviour.

## What changed, and why

**Roster.** danube2 retired from the arena roster; qwen3.5-2b admitted.

```
hot set    liquidai/lfm2.5-1.2b-instruct
           qwen3.5-2b
           falcon-h1-1.5b-instruct
parked     h2o-danube2-1.8b-chat, rwkv7-1.5b-g1
```

**Health expectation surfaces re-fitted for the whole pool** — not just for
qwen. Expectation is conditioned on model *and load*, and the incumbent knots
were measured beside danube2. Falcon's contention fell 1.4809 → 1.2390 purely
from the neighbour change, so carrying the old values forward would have left
two of three models with inflated, less sensitive expectations.

**Thresholds unchanged and externally validated.** `ks/kh/n` were selected on
the old pool's corpora, given no vote in the new fit, and tested on a held-out
collection: **0 false positives in 1,440 calls.**

**The equalizer gate was corrected, the constant was not.** The gate ran at 180
completions and passed 1000 ms, while Run 1's EQUALIZED arm generated ~600 and
breached. The gate is now run-equivalent (600 completions, one shared corpus
for all candidates). 1000 ms still passes with zero breaches, so
`EQUALIZED_DELAY_TICKS` stays 4 — and because the 800-tick horizon was derived
from that cadence, it stands too.

## Qualification, complete before this document

```
Gate 1 contract     0/200 shape failures for each of the three models
Gate 2 health       0 false positives on held-out Collection B
Gate 3 equalizer    1000 ms, 0 breaches at run-equivalent exposure
```

`UNPROFILED` now blocks a measured run from starting against a model the bridge
cannot monitor. All three are profiled.

## Void conditions

All of ASYNC-A's, unchanged: arm 1 producing any `STALE_CONFLICT`;
`SHAPE_FAILED` above 10% for any agent; failure to separate `SEMANTIC_INVALID`
from `STALE_CONFLICT`; any bridge `DEGRADED`/`CATASTROPHE`, recovery, or
residency change during a measured replicate; any `EQUALIZER_BREACH` in arm 3;
arm 4 failing to reproduce its source under the identity permutation, or making
any model call.

**Added:** a replicate killed by host memory pressure is VOID. During Gate 2
the host reached 0.7 GB free of 31.7 GB with LM Studio holding ~23.6 GB across
three model processes, and a collection was OS-killed during teardown. Three
co-resident models cost far more system RAM than VRAM. Host headroom is checked
in PRE-RUN; a mid-replicate OOM is not a result.

## Pre-committed readings

Unchanged from ASYNC-A:

- A difference that survives arm 3 is **not** explained by speed.
- A difference that vanishes in arm 3 **is**.
- A difference appearing in arm 4 is ordering, not cognition.
- If arm 3 shows `STALE_CONFLICT` down and `STALE_REVALIDATED` sharply up, the
  first hypothesis is that the equalizer landed near the world's regeneration
  horizon (`EQUALIZED_DELAY_TICKS == HOLD == 4`), **not** that equalization
  improved anything.
- Arm 4 with no reorderable groups, or a replay journal identical to its
  source, is `NOT_EXERCISED` and is not evidence about ordering.

## What is still not claimed

No claim about model quality. No claim that any observed specialization is
intentional. No transfer to other hardware, runtimes or model sets. No
fog-of-war, stigmergy or topology — those remain later layers, and mixing them
in would make every result unattributable.

## Run order

```
SERIAL -> NATURAL -> EQUALIZED -> ORDER_REPLAY (paired to NATURAL)
```

Frozen. Any void is a void.
