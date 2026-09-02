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
