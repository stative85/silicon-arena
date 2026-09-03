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
