# ASYNC-A3 — Run 1 results

Run executed in the frozen order at prereg `a598daa`, with
`tools/arm_baseline.py` at every arm boundary. Roster lfm2.5 + qwen3.5 +
falcon, world 16 resources / hold 4, 3 agents, 800 observation ticks, 250 ms
tick, 1000 ms equalizer (4 ticks), contract hash `f5a2aaf89dfa6ffa`. 914 s.

Nothing was tuned, retried, or repaired during the run.

## Classification

```text
ASYNC-A3 RUN 1

ALL FOUR ARMS COMPLETED. NO VOIDS.

SERIAL        valid, teeth OK
NATURAL       valid, teeth OK
EQUALIZED     valid, teeth OK
ORDER_REPLAY  valid, teeth OK

PRIMARY ASYNC-A TEST: ANSWERED, with one large stated confound
```

Every pre-registered void condition held clear:

| void condition | result |
|---|---|
| arm 1 produces any STALE_CONFLICT | 0 of 2400 |
| SHAPE_FAILED > 10% for any agent | 0 in every arm |
| SEMANTIC_INVALID not separable | separable, 0-4 per arm |
| any health DEGRADED / CATASTROPHE | 0 runtime events, all arms |
| arm 4 identity reproduction | holds |
| equalizer breach | 0 |

Gate 4 was live this time: `end_resident_set` is populated in all four arms,
`observed_resident_hashes` is the single value `daadde8d4dd9cb37` throughout,
and every arm boundary froze a witness with that same hash.

## Arm outcomes

| arm | actions | ACCEPTED | STALE | SEM_INV | CONT_LOST | actions/tick |
|---|---|---|---|---|---|---|
| SERIAL | 2400 | 2000 | 0 | 0 | 400 | 3.00 |
| NATURAL | 1082 | 881 | 198 | 2 | 1 | 1.35 |
| EQUALIZED | 600 | 402 | 198 | 0 | 0 | 0.75 |
| ORDER_REPLAY | 1082 | 881 | 195 | 4 | 2 | — |

---

## Q1 — Does latency have a mechanical consequence at all?

**ANSWERED: yes.**

```
SERIAL     0 / 2400  =  0.00%   (structurally zero)
NATURAL  198 / 1082  = 18.30%
```

Arm 1 is structurally zero and produced exactly zero, so the tooth holds and the
non-zero arm 2 rate answers the question directly. Observation age confirms the
mechanism rather than merely accompanying it:

```
observation_age_ticks, median / p95 / max
              SERIAL      NATURAL     EQUALIZED
lfm2.5        0 / 0 / 0   0 / 1 / 2   4 / 4 / 4
qwen3.5       0 / 0 / 0   2 / 3 / 3   4 / 4 / 4
falcon        0 / 0 / 0   2 / 2 / 3   4 / 4 / 4
```

EQUALIZED is exactly 4 for every agent on every cognition — the equalizer does
precisely what it claims, with no leakage.

---

## Q2 — Do speed differences produce persistent acquisition differences?

**Partly, and the parts separate cleanly.** Three speed-derived differences
vanish under equalization. One difference survives it and is **not** speed.

### What vanished (therefore: caused by speed)

**Cognition opportunities.** In NATURAL the fast model simply thinks more often.

```
                NATURAL          EQUALIZED
lfm2.5          544 actions      200
qwen3.5         268              200
falcon          270              200
```

**First-arrival share.** Who lands first in a contested tick.

```
                NATURAL          EQUALIZED
lfm2.5          55.4%            26.5%
falcon          21.6%            35.5%
qwen3.5         23.0%            38.0%
```

**Who pays for asynchrony.** This is the sharpest result in the run. Under
natural timing, staleness falls almost entirely on the slow model; under
equalization it splits between the two agents that actually contend.

```
STALE_CONFLICT by agent
                NATURAL          EQUALIZED
lfm2.5            5              104
qwen3.5         187               94
falcon            6                0
                ---              ---
                198              198
```

qwen3.5 absorbs **94% of all staleness** in NATURAL (187 of 198) and **47%**
under equalization. The total is identical in both arms; only its distribution
moves. Per the pre-committed reading: *a difference that vanishes in arm 3 is
explained by speed.* This one does, and the mechanism is visible — the slow
model's observations are 2 ticks old when they land, the fast model's are 0.

### What survived (therefore: not speed)

Acquisition counts do **not** equalize:

```
acquisitions        NATURAL              EQUALIZED
lfm2.5              538 / 544 = 98.9%     96 / 200 = 48.0%
qwen3.5              81 / 268 = 30.2%    106 / 200 = 53.0%
falcon              262 / 270 = 97.0%    200 / 200 = 100.0%
spread              457                  104
gini                0.3458               0.1725
```

Under equalization all three agents have identical opportunity (200) and
identical release timing (age exactly 4), so the residual difference **cannot**
be latency. Its cause is in the next section, and it is not a property this
experiment set out to measure.

---

## THE CONFOUND — target preference, and it is large

The three models have near-deterministic and **largely disjoint** target
preferences. From SERIAL, where nothing contends for cognition time:

```
lfm2.5    r_00 200, r_01 200, r_02 200, r_03 200     (exactly 200 each)
falcon    r_05 200, r_07 200, r_09 200, r_12 200     (exactly 200 each)
qwen3.5   r_00 200, r_06 200, r_08 200, r_02 199
```

That is a deterministic cycle, not a rich choice. And the preferred sets barely
overlap: lfm2.5 lives on `r_00..r_03`, falcon on `r_05..r_12`.

The consequence is that **the entire staleness signal is one pair of models
colliding.** In EQUALIZED:

```
lfm2.5   r_00 (100), r_01 (100)              104 stale
qwen3.5  r_00  (99), r_01  (99)               94 stale
falcon   r_07 (100), r_08  (98)                0 stale
```

falcon contends with nobody, so it accepts 200 of 200. lfm2.5 and qwen3.5 fight
head-on over `r_00` and `r_01` and split the difference. falcon's 100% is not
skill, speed, or scheduling — it is an empty lane.

**What this costs the result.** Q1's answer stands: staleness is real and
mechanically caused by observation age. Q2's speed findings stand: they are
within-agent comparisons across arms, so disjoint preferences do not create
them. But **the magnitude of every rate here is a function of which resources
these three models happen to name.** A roster whose preferences overlapped
completely would show far more staleness; one that partitioned perfectly would
show almost none. 18.30% is a fact about this roster in this world, not a
property of asynchronous world time.

This is reported, not repaired. Diversifying targets, randomising the visible
list, or selecting models by preference spread would each be a new experiment
with its own pre-registration — and doing any of them now, after seeing the
numbers, is exactly the move the protocol forbids.

---

## Q3 — Does arrival order alone change outcomes?

Counterfactual replay over NATURAL's corpus, latency-rank inversion within
simultaneity groups. Source corpus unmutated (`source_envelopes_mutated: 0`),
zero model calls.

```
reorderable groups     296
envelopes reordered    370
pairwise inversions    185
journal_differs        true

                  NATURAL   ORDER_REPLAY
ACCEPTED              881            881
STALE_CONFLICT        198            195
SEMANTIC_INVALID        2              4
CONTENTION_LOST         1              2
final_world_hash  6551ed240a32a7a4 == 6551ed240a32a7a4
```

185 pairwise inversions moved **5 actions of 1082**, none of them into or out of
ACCEPTED, and the final holder map is bit-identical.

The claim stays small, and it now has an independent replication: A2's
ORDER_REPLAY produced the same shape (186 inversions, 1 action moved, identical
final hash) on a different NATURAL trajectory.

> In these two NATURAL trajectories, under this resource-rich world, the frozen
> ordering inversion changed history but did not change mechanically successful
> allocation.

Not "ordering does not matter". The confound above explains why it would be hard
for ordering to matter here: two of three agents are not competing for the same
resources at all, and reordering non-competing actions cannot change their
outcome. 16 resources against 3 agents with largely disjoint tastes gives
ordering very little to bite on.

---

## What is deliberately NOT claimed

- **No model quality claim.** falcon's 100% acceptance measures an uncontested
  lane, not capability.
- **n = 1 per arm.** No variance estimate, no significance testing. The
  qwen3.5 staleness shift (94% → 47%) is large and mechanically explained, but
  it is one replicate.
- **No emergence claim.** The agents are deterministic cyclers under this
  contract. Nothing here is adaptation.
- **A2 is not revalidated.** A3 answering the question does not make A2's arms
  confirmatory; they ran under a defective instrument.

## Status

```
Q1  answered: latency has a mechanical consequence          18.30% vs 0
Q2  speed explains opportunity, arrival order, and WHO PAYS
    speed does NOT explain residual acquisition difference
Q3  ordering alone moved 5 of 1082 actions, world identical
CONFOUND  target preference is near-deterministic and largely
          disjoint; it sets the magnitude of every rate reported
```

The instrument worked. Four arms, no voids, every tooth intact.
