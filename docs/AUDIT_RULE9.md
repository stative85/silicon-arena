# Blast-radius audit: quantized decision statistics (rule 9)

SWARM-B2 discovered that its bar could only take the values
`{3.0, 4.5, 6.0, 7.5, 9.0}` and that the 5.60 its power analysis projected was
never attainable ([EXPERIMENT_SWARM_B2](EXPERIMENT_SWARM_B2.md)). That is a
property of the *measuring equipment*, not of swarm work, so this audit asks the
same question of every threshold already in the ledger.

**Nothing was rerun.** This is a static audit of decision statistics, their
denominators, and the thresholds set against them. Where a denominator is not
recoverable from tracked code it is marked INFERRED and must be confirmed before
anything is acted on.

## Method

For each row: identify the decision statistic, its denominator, the lattice its
values are confined to, and whether the pre-registered threshold is a point on
that lattice. A threshold between two rungs is not wrong — it silently becomes
the next rung up.

```
  lattice   = 100 / N  points, for a rate over N opportunities
  effective = the smallest attainable value that satisfies the written bar
```

## Classification

| id | statistic | N | lattice | bar | attainable? | class |
|---|---|---:|---:|---:|---|---|
| **R1** | speeches/min | — | continuous | none (judged) | n/a | SAFE |
| **R2** | VRAM detected | — | exact | none | n/a | SAFE |
| **C1** *(replies)* | median reply words | 60 | 1 word | asked 15–25, got 81 | yes | SAFE |
| **T1** *(trimming)* | truncation rate | 60 | 1.67 | none pre-set | n/a | SAFE |
| **M1** | guard rates | 60 | 1.67 | `<= 5%`, `not above 2%` | 5% yes; **2% no** | QUANTIZED BUT DECISION UNAFFECTED |
| **P1** | throughput + exact counts | — | mixed | mis-specified guards | n/a | SAFE — rejected by its own rule |
| **P2** | speeches/min, exact counts | — | continuous | 1.40 envelope | yes | SAFE — doc already states counts are exact |
| **P3** | turns per 200s | — | 1 turn | none | n/a | SAFE — effect was exactly zero |
| **E1** | addressing slope | — | continuous | none (harm) | n/a | SAFE |
| **E2** | addressing rate | INFERRED | ~0.83 | +16 | **no** → +16.67 | QUANTIZED BUT DECISION UNAFFECTED |
| **D3** | addressing rate | 120 | 0.83 | +16 | **no** → +16.67 | QUANTIZED BUT DECISION UNAFFECTED |
| **C1** *(contention)* | same-pair re-engagement | **28** INFERRED | **3.57** | +16 | **no** → **+17.86** | **CLAIM NEEDS QUALIFICATION** |
| **PR1** | distinct dwells, turn count | — | exact | exact counts | yes | SAFE |
| **T1** *(arc)* | vocab shift; CLOSE rate | ~45 INFERRED | ~2.2 | 0.10; 40% | 40% plausibly yes | QUANTIZED BUT DECISION UNAFFECTED |
| **Q1** | callback conversion | ~84 | ~1.2 | none pre-set | n/a | superseded by MP1; already retracted |
| **G1/G2** | callback conversion | — | — | none | n/a | SUPERSEDED |
| **T1** *(tournament)* | R−D conversion | 127 | 0.79 | +8 | **no** → +8.66 | QUANTIZED BUT DECISION UNAFFECTED |
| **E0/E1** | conversion; batches won | 182; 4 | 0.55; 1 | +10; 3 of 4 | **no** → +10.44; batches yes | QUANTIZED BUT DECISION UNAFFECTED |
| **MP1** | verbatim-rejection gap | 144 | 0.69 | bands `<5`, `>=10` | **neither edge** | QUANTIZED BUT DECISION UNAFFECTED |
| **MP2-A** | binary uptake rate | 60 | 1.67 | +25 | **yes** (15/60) | SAFE |
| **MP2-A2** | binary uptake rate | 60 | 1.67 | +25 | **yes** | SAFE |
| **MP2-B** | scramble max | 200 draws | — | 5.0 | n/a | already VOID (rule 2) |
| **MP2-B2** | source lift | 240 | 0.42 | +10, within 10 | **yes** (24/240) | SAFE |
| **SWARM-V** | valid allocation rate | 400 | 0.25 | 95.0% | **yes** (380/400) | SAFE |
| **SWARM-B** | median longest silence | 10x5 null | **3.00** | 9.0 | yes, but only 3/6/9/12 | QUANTIZED BUT DECISION UNAFFECTED |
| **SWARM-B2** | median longest silence | 10x40 null | **1.50** | 6.0 gate | yes | **RESULT RECHECKED** — see below |

**No row changes its decision. One claim needs qualification. One power
calculation was already corrected.**

## The one that needs qualification: C1, contention memory

`10.7%` and `21.4%` reproduce exactly as **3/28 and 6/28**. The metric has no
implementation anywhere in the tracked tree — it exists only in prose in
[EXPERIMENT_CONTENTION](EXPERIMENT_CONTENTION.md) — so the denominator is
inferred from the published percentages and must be confirmed before this is
cited. On that denominator:

```
  lattice                    3.57 points
  written bar                +16
  attainable values near it  +14.29 (4/28)   +17.86 (5/28)
  effective bar              +17.86
  observed effect            +10.71  =  3 events becoming 6 events
```

The rejection stands and is not close: `+10.7` is below the next rung down. What
does not survive is the *precision*. "+10.7 against a bar of +16" reads as a
measurement that missed by 5.3 points; it is three additional events on a
28-slot denominator, with a resolution of about 3.6 points. One event either way
moves it by a third of the gap to the bar.

[AUDIT_EXTRACTOR](AUDIT_EXTRACTOR.md) already recorded that this treatment was
under-activated by a broken claim extractor and that the hypothesis is therefore
unresolved. This adds a second, independent reason to quote no precise effect
size from C1: **the instrument had roughly 3.6-point resolution.** Both reasons
point the same way, and neither reopens the conflict axis.

## The pattern, which is the actual finding

**Round-number thresholds are almost never on the lattice.** `+16` on a
120-denominator, `+10` on 182, `+8` on 127, band edges `5` and `10` on 144 —
none of these are attainable values. Every one silently became the next rung up.

In every case except C1 the margin was so large that the shift is irrelevant,
which is why this has cost nothing so far. It cost something exactly once: when
a threshold was set *close to* the observed effect, which is precisely when a
threshold matters most. SWARM-B2 set its gate at 6.0 against an effect of 6.0
and the lattice put the bar on 6.00 rather than the projected 5.60.

> **A quantization defect is invisible while your margins are wide and decisive
> the moment they are narrow.** It is therefore worst in exactly the experiments
> that were designed most carefully.

## Between-seed variance: no other exposure

The audit also looked for power calculations that ignore between-seed variance.
**SWARM-B2 is the only experiment in the ledger with seed structure at all** —
every other design is a single pooled sample or a paired crossover, so there is
no second variance component to omit. MP2-B's N-selection simulated a pooled
binary rate on a lattice where its bar was attainable, and is sound.

That is a narrow escape rather than a virtue: the exposure did not exist because
the designs were simpler, not because anything checked.

## Design guidance recovered, for the next ruler

1. **Compute the attainable set before freezing a threshold.** Run the whole
   decision procedure over plausible draws and read off which values come out.
   If the bar is not in that set, either move it to a rung deliberately, or say
   in the pre-registration which rung it will effectively become.

2. **Parity is a free design lever when the statistic is a median.** A median
   over an *odd* number of integers is an integer; over an *even* number it is a
   half-integer. SWARM-B's 5-matches-per-seed null put its bar on a 3.0 lattice;
   B2's 40 put it on 1.5, and that halving was an accident of choosing an even
   number, not a decision.

3. **Denominator before threshold.** A `+16` bar is meaningless against 28
   slots. Ask what the smallest detectable difference is — one event — and
   whether the bar is a sane multiple of it.

4. **Keep the metric implementation in the tree.** C1's primary cannot be
   confirmed from code because the code is not tracked, which is why its
   denominator is INFERRED in the table above.
