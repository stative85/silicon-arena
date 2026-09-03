# Pre-registration: is `_is_callback` measuring anything?

**Written and committed before the harness was modified and before any data was
collected.**

## Why this is a shipping question, not a research one

Gonzo recall is **shipped**. It was accepted on evidence produced by
`_is_callback`, and that metric has now scored a no-memory control *higher* than
either memory arm ([EXPERIMENT_EMBEDDING](EXPERIMENT_EMBEDDING.md)):

```
placebo, no memory injected   78.0%
distance recall               70.9%
nomic recall                  75.3%
```

So the decision this answers is blunt: **does Gonzo recall stay shipped?** If
the metric cannot distinguish a reply that saw a memory from one that did not,
the feature was accepted on a number that meant nothing, and it has to be either
re-justified or pulled.

## The hypothesis, stated so it can lose

`_is_callback` disqualifies any reply sharing a six-word run with the excerpt,
to stop verbatim repetition counting as engagement.

> **H:** genuine engagement usually echoes a phrase of the memory, so the
> verbatim guard disqualifies real callbacks while letting topical coincidence
> through. The exclusion is not a refinement of the metric, it is the defect.

If H is true, the memory arms are being *penalised for succeeding*.

## Conditions

Three replies at every eligible opportunity, identical in every respect except
the injected block:

| id | injected |
|---|---|
| **S0** | nothing |
| **S1** | **sham** — a real excerpt from a DIFFERENT transcript, same volume and format, rendered by the same `G.render()` |
| **S2** | the real distance-selected scar |

All three scored against the **same** real scar.

S1 is the control this project already built for Q0/QS/Q1 and the one the
embedding placebo lacked. The bare placebo differed from the arms in two ways —
no memory content *and* a shorter prompt — so it could not separate "the memory
was irrelevant" from "the extra text changed the output". S1 holds prompt volume
and format constant and varies only whether the content is from this
conversation.

## The instrumentation that actually decides it

Scoring is not enough. Each arm records **why** `_is_callback` refused, counted
separately:

```
rejected_provenance     scar did not resolve to its turn
rejected_shared         fewer than 2 shared content words
rejected_novel          fewer than 8 novel words
rejected_verbatim       shared a 6-word run  <-- the suspect
passed
```

H predicts `rejected_verbatim` is **much** higher for S2 than for S0.

That is a direct mechanistic test. The conversion percentages are downstream of
it and, on current evidence, untrustworthy.

## Frozen decision

Bars are set against a measured null: the E0/E1 null control returned a
between-arm gap of **+0.0 points** on 22 same-treatment opportunities, so the
harness contributes no detectable bias and 10 points is far outside it.

**THE METRIC IS BROKEN — redefine it** if:

`rejected_verbatim` for S2 exceeds S0 by **>= 10 percentage points**.

Repair, fixed now so it cannot be tuned to taste: report **two numbers instead
of one** — engagement without the verbatim exclusion, and the verbatim rate
alongside it. Conflating them into a single pass/fail is what produced this.

**THE METRIC IS SOUND** if `rejected_verbatim` differs by **< 5 points** AND
S2 engagement exceeds S1 by **>= 10 points**. Recall keeps its shipped status on
evidence that survives a sham control.

**RECALL LOSES ITS JUSTIFICATION** if the verbatim rates match AND S2 does not
beat S1 by 10 points. Then the sham is as good as the memory, memory content is
not doing the work, and the feature is reopened as a shipping decision.

Between 5 and 10 on the verbatim gap: **INCONCLUSIVE**, metric stays suspect,
and no absolute conversion number may be published until it is settled.

## Target

**>= 120 opportunities**, for the reason two consecutive experiments have now
demonstrated:

```
resonance    +5.0 at 40    +7.4 at 81    -3.9 at 127
embedding   +30.4 at 46                  +4.4 at 182
```

Both reversed. Neither was readable early.

## Anti-Goodhart guards

* The callback definition is **not** edited during the run. If it needs changing
  that is the *result*, applied afterwards, not a mid-flight correction.
* The sham excerpt is drawn from a different transcript by index, never chosen
  for being dissimilar — choosing it would be selecting the control to lose.
* `rejected_*` counters are recorded for all three arms including S0, so the
  suspect number has its own baseline.

## Not part of the decision

Judge scores. Throughput. Anything about embeddings — that question is closed.

---

# Result: INCONCLUSIVE at 144 opportunities

```
                S0 none  S1 sham  S2 real
  passed          77.1%    77.8%    71.5%
  verbatim         1.4%     2.8%     9.0%
  shared          21.5%    19.4%    18.8%
  novel            0.0%     0.0%     0.7%
  provenance       0.0%     0.0%     0.0%

  ENGAGEMENT (metric as shipped)
    S2 real 71.5%   S1 sham 77.8%   S2-S1 = -6.3 points
    S0 none 77.1%

  THE SUSPECT CLAUSE
    verbatim rejection: S0 1.4%   S2 9.0%   gap +7.6 points

  REPAIRED METRIC (verbatim exclusion removed)
    S0 none 78.5%   S1 sham 80.6%   S2 real 80.6%
    S2-S1 = +0.0 points   S2-S0 = +2.1 points
```

**INCONCLUSIVE.** The verbatim gap is +7.6, inside the pre-registered 5-to-10
band. The metric stays suspect and **no absolute conversion number may be
published until this is settled.**

## The hypothesis was closer than an early read suggested

At 48 opportunities the verbatim gap was +2.1 and this was written up as the
hypothesis failing. At 144 it is +7.6, and real memory is disqualified by the
verbatim clause **6.4 times as often** as a reply that saw no memory at all.

Directionally the mechanism is real. It did not clear the bar, so it is not
established, and the bar does not move. But the interim call of "falsified" was
itself an early read of exactly the kind this project keeps getting punished
for, made in the same document that warns against them.

Third consecutive experiment where the early number and the final number tell
different stories:

```
resonance    +5.0 at 40    +7.4 at 81    -3.9 at 127
embedding   +30.4 at 46                  +4.4 at 182
metric       +2.1 at 48                  +7.6 at 144
```

The S0 pass rate itself moved from 31.3% to 77.1% between those two reads. One
transcript is not a sample.

## What is not inconclusive

The sham comparison is separate from the verbatim question, and it is clean:

| | shipped metric | repaired metric |
|---|---:|---:|
| S2 real vs S1 sham | **-6.3** | **+0.0** |
| S2 real vs S0 none | -5.6 | +2.1 |

**Real memory does not outperform a sham on either version of the metric.**
Remove the verbatim exclusion and they are identical to the decimal: 80.6%
against 80.6%. A block of unrelated text from a different match does exactly
what the recalled memory does.

This is not the frozen decision — the frozen rule routes +7.6 to inconclusive
and that stands — but it is evidence, it was pre-registered as a reported
quantity, and it points one way. **There is currently no measurement showing
that memory *content* drives callbacks.** The prior 65-76% conversion figures
are consistent with a sham scoring the same.

## Consequence for a shipped feature

Gonzo recall stays shipped. An inconclusive result does not unship anything,
and unshipping on it would be the mirror image of shipping on a bad number.

What changes is what may be claimed. Recall may not be described as producing
callbacks, or as having a conversion rate, in the README, the docs, or a launch
post. Those claims rest on a metric a sham satisfies equally well.

## Why this does not get "one more run"

The obvious move is to run past 144 until +7.6 crosses 10. That is the precise
sin this project exists to avoid: extending a sample to chase a threshold is
how the resonance result would have shipped at 81 pairs.

Settling it needs a **new pre-registration with a target fixed in advance**,
powered for the effect actually observed rather than the one hoped for, and it
is a separate decision from this one.

## Also recorded

The first attempt at this run was killed at ~20 opportunities and persisted
nothing, because saving happened once per transcript. Fixed to save every 10
(`38bd475`) before the clean restart. No data was carried across.
