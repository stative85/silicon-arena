# Pre-registration: hide generation inside the reading pause

**Written and committed before the change was built.**

## Why not simply shorten the pause

The turn clock decomposes as: generate 2717ms, scheduled gap 1143ms, sanitise
2ms, publish 0ms. There is no processing fat. The only non-generation cost is a
deliberate pause, and in the visual app that pause is the four seconds a viewer
spends reading the speech bubble (`TURN_INTERVAL_SEC = 5.0`,
`BUBBLE_DURATION = 4.0`). Deleting it buys throughput by taking reading time
away from the only path a human watches.

Generation (~2.7s) is shorter than the dwell (4.0s). So it can be **overlapped**
rather than removed: start the next agent's request while the current reply is
still on screen, and reveal it when the dwell expires.

## The change

One turn deep. Exactly one speculative request may be outstanding.

Deeper speculation is rejected on purpose: a template switch, a human line, a
beef event or any state mutation invalidates queued turns, and five stale
branches is a lifecycle system nobody asked for. This project already has epoch
machinery for precisely this (`advance_epoch`, and the live path's stale-reply
guard) and the pipeline must use it rather than inventing a second one.

## Conditions

| id | behaviour |
|---|---|
| P0 | current sequencing (reply, wait, dispatch) |
| P1 | one-deep pipeline (dispatch next during dwell, reveal on dwell expiry) |

**Interleaved blocks, not consecutive sessions.** `P0-P1-P1-P0-P0-P1-P1-P0`,
20 speeches per block, state reset between blocks, all inside one session.
Absolute behaviour drifts between sessions by more than the within-batch spread
(`EXPERIMENT_MAXTOKENS.md`), so sequential arms let drift impersonate an
effect. Blocks are balanced so drift falls on both arms equally.

## Primary measure

* speeches per minute

## Correctness guards, declared in advance

A pipeline is a concurrency change, so these matter more than the debate
metrics this time. Any failure rejects P1:

| guard | bound |
|---|---|
| stale replies accepted | **0** — a reply from a superseded epoch must never be shown |
| out-of-order speeches | **0** — the transcript order must match the reveal order |
| minimum readable dwell | no bubble visible for less than `BUBBLE_DURATION` |
| skipped cinematic events | 0 relative to P0 |
| outstanding requests | never more than 1 |
| turn failure rate | not above 2% |

## Interaction guards

The next agent now composes its prompt before the current reply is revealed,
but it must still compose it **from** that reply — the canonical turn is
committed to history the moment it lands, ahead of the dwell. If the pipeline
were to dispatch before committing, agents would answer a turn they never saw:

| guard | bound |
|---|---|
| challenge rate | not more than 5 points below the P0 mean in the same batch |
| addresses someone | not more than 4 points below the P0 mean in the same batch |
| near-duplicate rate | not more than 3 points above the P0 mean in the same batch |

**A dedicated check, not just a metric:** every speech in P1 must be composable
from the history that existed when it was dispatched. A speech referencing a
turn that had not yet been committed is a stale-callback bug, and the count
must be 0.

## Acceptance

P1 replaces P0 only if throughput improves by at least **15%** and every
correctness and interaction guard passes. Otherwise P0 stands.

## Not part of the decision

Judge scores, for the reasons given in the roster evaluation.

## Reporting

Effects as change over within-batch run-to-run standard deviation — a
signal-to-noise ratio, not a significance test.
