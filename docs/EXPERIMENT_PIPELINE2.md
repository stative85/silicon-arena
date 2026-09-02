# Null calibration, and a re-pre-registration of the pipeline

## What the protocol invents when nothing changes

Two arms, identical configuration, labels assigned artificially, interleaved
`N0a-N0b-N0b-N0a-N0b-N0a-N0a-N0b`, 20 speeches per block, 4 paired blocks each.
Any difference reported here is manufactured by the protocol.

Paired block deltas (B − A):

| metric | pair 1 | pair 2 | pair 3 | pair 4 | mean | sd |
|---|---:|---:|---:|---:|---:|---:|
| speeches/min | −0.3 | +0.4 | +0.2 | −1.2 | −0.20 | 0.60 |
| challenge | +25.0 | −40.0 | +20.0 | +5.0 | +2.50 | 25.62 |
| addresses | −10.0 | −5.0 | −10.0 | +25.0 | 0.00 | 14.58 |
| near-duplicate | +5.0 | +5.0 | +5.0 | 0.0 | +3.75 | 2.17 |
| mean words | +2.1 | −0.5 | −12.5 | +12.1 | +0.30 | 8.74 |

**Noise envelope** (|mean| + 2sd) — nothing below this is resolvable:

| metric | envelope |
|---|---:|
| speeches/min | **1.40** (≈9% of a 15/min baseline) |
| challenge | **53.7 points** |
| addresses | 29.2 points |
| near-duplicate | 8.1 points |
| mean words | 17.8 |

## This indicts the previous guards in both directions

The rejected pipeline run used a challenge guard of −5 points and a
near-duplicate guard of +3 points. The resolvable floors are 53.7 and 8.1. Both
were far inside the noise: one rejected the run at random, and the other could
never have caught real harm either.

An earlier null run with the same protocol reported a challenge envelope of
42.2 rather than 53.7. The envelope estimate is itself noisy at four pairs.
That is reported rather than averaged away, because it bounds how much
confidence any of these thresholds deserve.

## Honest consequence: the interaction metrics are low-power here

At 20-speech blocks, challenge rate cannot detect anything smaller than a
50-point swing. No realistic intervention produces that. The same holds, less
extremely, for addressing.

So the pipeline decision **cannot** rest on interaction metrics, and pretending
otherwise by setting a plausible-looking threshold would be theatre. It rests
on the correctness guards, which are exact counts rather than rates and have no
noise floor at all, and on throughput, whose envelope (1.40) is comfortably
below the observed effect (+4.9).

## P2 pre-registration

Identical to the pipeline change already implemented, `--pipeline`, evaluated
again with thresholds derived from the calibration above.

**Design.** Interleaved `P0-P1-P1-P0-P0-P1-P1-P0`, 20 speeches per block, 4
paired blocks per arm, one session, memory and VRAM reset between blocks.
Analysis by paired block deltas.

**Primary.** Throughput gain ≥ **20%**, and the paired mean delta must exceed
the calibrated envelope of 1.40 speeches/min.

**Hard correctness guards** — exact counts, no noise floor:

| guard | bound |
|---|---|
| stale replies accepted | 0 |
| outstanding requests | ≤ 1 |
| out-of-order reveals | 0 |
| failure-rate increase | ≤ 2 points |

**Dwell guard.** Actual spacing may undershoot the requested pause by at most
`max(one rendered frame, 2% of the pause)` — 24ms at a 1200ms pause. The
previous exact-millisecond threshold rejected an 8ms undershoot on a
frame-quantised quantity.

**Interaction guards**, set at the measured envelope and labelled for what they
are — weak:

| metric | bound |
|---|---|
| challenge | paired mean delta not worse than −53.7 |
| addresses | not worse than −29.2 |
| near-duplicate | not worse than +8.1 |

These will almost certainly pass. That is the point: they are recorded so a
catastrophic regression would still be caught, and they are explicitly **not**
evidence that the pipeline preserves debate quality. Establishing that needs
larger blocks than this experiment runs.

**Acceptance.** Throughput ≥20% and above envelope, every hard correctness
guard passes, dwell guard passes, no interaction metric outside its envelope.


---

# Result: P1 accepted. The pipeline is the default in the headless path.

Interleaved `P0-P1-P1-P0-P0-P1-P1-P0`, 20 speeches per block, 4 paired blocks
per arm, one session.

Paired block deltas (P1 − P0):

| metric | pair 1 | pair 2 | pair 3 | pair 4 | mean | sd |
|---|---:|---:|---:|---:|---:|---:|
| **speeches/min** | +5.0 | +5.5 | +5.2 | +6.2 | **+5.50** | 0.45 |
| challenge | +15.0 | 0.0 | +10.0 | 0.0 | +6.25 | 6.50 |
| addresses | −25.0 | 0.0 | +5.0 | 0.0 | −5.00 | 11.73 |
| near-duplicate | 0.0 | +10.0 | −15.0 | −10.0 | −3.75 | 9.60 |
| mean words | −4.0 | +1.1 | −1.9 | −5.5 | −2.58 | 2.45 |

Arm throughput: 14.79 → 20.28 speeches/min, **+37.2%**.

| check (frozen before the run) | value | verdict |
|---|---|---|
| throughput >= +20% | +37.2% | OK |
| paired spm delta above envelope 1.40 | +5.50 | OK |
| stale replies accepted == 0 | 0 | OK |
| outstanding requests <= 1 | 1 | OK |
| out-of-order reveals == 0 | 0 by construction | OK |
| failure-rate increase <= 2 pts | 0.0 → 0.0 | OK |
| dwell undershoot <= 24ms | 14ms | OK |
| challenge delta >= −53.7 | +6.2 | OK |
| addresses delta >= −29.2 | −5.0 | OK |
| near-duplicate delta <= +8.1 | −3.8 | OK |

**Accepted.** The throughput effect is the only one that clears its noise
envelope, and it clears it by 12 standard deviations: the paired deltas are
+5.0, +5.5, +5.2, +6.2, which is about as consistent as this arena produces.

## What is deliberately not claimed

The interaction guards all passed, and that is close to meaningless — they were
set at a noise floor wide enough to pass almost anything. Challenge rate came
out **+6.2** and addressing **−5.0**, both well inside a protocol that produces
±25 point swings with nothing changed. This experiment does not show that the
pipeline preserves debate quality. It shows that it did not cause a
catastrophe, and that the correctness properties hold exactly.

## Scope

On by default in the headless path only. `--no-pipeline` restores sequential
dispatch.

**Not ported to the visual app.** Headless acceptance proves scheduling
correctness. Presentation correctness is a separate question and needs its own
verification: that a bubble stays readable for its full dwell, that a prefetched
reply cannot appear early, that cinematic and event processing use the committed
previous turn, that a preset or template change invalidates a reply in flight,
and that pause/BRB interactions never reveal prefetched text. The model may
think one turn ahead; the viewer must never be able to tell.


---

# Visual port: attempted, measured, reverted

The headless win did not transfer, and the port was removed rather than kept
"for later".

## Measurement

Same 200-second window, visual app (`main.gd`) headless:

| build | turns | per turn | speeches/min |
|---|---:|---:|---:|
| before the port | 29 | 6.90s | 8.7 |
| with the one-deep pipeline | 29 | 6.90s | 8.7 |

Identical. Instrumenting the turn tick showed why:

```
[TICK] t=5687  pending=true  waiting=true
[TICK] t=10828 pending=true  waiting=true
[TICK] t=16002 pending=true  waiting=true
[TICK] t=41414 pending=false waiting=true
```

Ticks fire every ~5.0s and a reply is already in hand at almost all of them.

## Why the headless gain does not exist here

The two entry points schedule differently, and only one had the defect the
pipeline fixes.

`live_match.gd` scheduled the next turn **relative to the previous reply**
(`_next_turn_at = _elapsed + 1.2`), so the pause and the generation were
strictly sequential and added up.

`main.gd` uses a **free-running repeating timer**. The reply lands somewhere
inside the 5-second interval and the next dispatch happens on the next tick
regardless, so generation was already overlapping the pause. Prefetching moves
*when the text is displayed*, not *how often turns happen*.

The visual app was pipelined by accident of its timer design.

## Decision

Reverted. It added a hold-and-reveal path, an epoch re-check and three counters
to the largest and most load-bearing file in the project, in exchange for a
measured zero. Keeping it behind a flag would have been the same complexity
with an added branch.

The rate in the visual app is set by `TURN_INTERVAL_SEC = 5.0`, which is the
reading pause. Changing it is a product decision about how long a viewer needs
to read a bubble, not a scheduling one, and it is not made here.

The headless pipeline stays: that path had the sequential defect and the +37.2%
is real.
