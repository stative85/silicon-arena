# Pre-registration: does a lower token ceiling buy throughput without thinning the debate?

**Written and committed before the ladder was run.** Criteria fixed in advance,
as with the compression experiment.

## Why this and not the prompt

Asking these models for fewer words does nothing: four pre-registered
conditions moved mean length by under two words and compliance never exceeded
5% (`EXPERIMENT_COMPRESSION.md`). `max_tokens` is not a request, it is a
ceiling, and it is what actually determined reply length all along.

## Design

| condition | max_tokens |
|---|---:|
| M110 | 110 (current) |
| M85 | 85 |
| M70 | 70 |
| M55 | 55 |

AUTO roster fixed (`stablelm-2-zephyr-1.6b` / `h2o-danube3-4b-chat` /
`gemma-3-1b`), same topic and template, **sentence trimming ON**, 60 speeches
per run, **three independent runs per condition**, VRAM and memory cleared
before each run.

Three runs per condition because the trimmed arena's run-to-run standard
deviation is now known (`EXPERIMENT_TRIMMING.md`): challenge 2.5, addressing
1.6, mean words 0.6. Guards below are set against those.

## Primary measures

* speeches per minute
* mid-thought truncation
* mean words

## Guards, declared in advance

**Interaction** — a lower ceiling must not thin the debate:

| guard | bound |
|---|---|
| challenge rate | not more than 5 points below the M110 mean |
| addresses someone | not more than 4 points below the M110 mean |
| near-duplicate rate | not more than 3 points above the M110 mean |
| turn failure rate | not above 2% |

**Completeness** — a lower ceiling must not reintroduce the defect trimming
just fixed:

| guard | bound |
|---|---|
| mid-thought truncation | at or below 5% |

The completeness guard is the one under real pressure. Trimming repairs a
severed sentence by discarding it, so a ceiling low enough to cut most replies
mid-clause would still report low truncation while quietly throwing away most
of what was generated. **A second completeness check therefore applies: mean
words must not fall below 35**, which is where a reply stops being an argument
and becomes a fragment that happens to end in a full stop.

## Acceptance

A lower ceiling replaces 110 only if **all** of:

1. throughput at least **15%** above M110;
2. the completeness guards pass;
3. every interaction guard passes.

## Tie-break

Among passing conditions, start from the highest and step down only while each
step buys at least **5%** more throughput than the setting above it. This stops
55 being chosen over 70 for a rounding error while producing visibly thinner
prose.

If no condition passes, 110 stands.

## Not part of the decision

Judge scores. Unchanged from the roster evaluation: on entertainment the three
judges correlated −0.066, −0.108 and +0.184 with one another, and noise cannot
adjudicate.

## On the numbers this will report

Effects are reported as change divided by run-to-run standard deviation — a
signal-to-noise ratio, not a significance test. Three runs per condition is
enough to tell a large effect from a small one and not enough for formal
inference; none is claimed.


---

# Result: every lower ceiling thins the debate. 110 stands.

Twelve runs, AUTO roster fixed, trimming on, 60 speeches each, run
consecutively in one session.

| condition | speeches/min | challenge | addresses | mean words | truncated | near-dup |
|---|---:|---:|---:|---:|---:|---:|
| **M110** | 15.27 | **47.2%** | **44.4%** | 60.9 | 2.8% | 6.7% |
| M85 | 17.06 | 20.6% | 30.0% | 45.8 | 3.9% | 5.6% |
| M70 | 18.23 | 22.2% | 35.0% | 38.3 | 3.9% | 2.8% |
| M55 | 20.01 | 17.8% | 31.7% | 30.5 | 23.3% | 10.0% |

Evaluated against the pre-registered rule:

| condition | throughput | challenge guard | addressing guard | completeness | verdict |
|---|---:|---|---|---|---|
| M85 | +11.7% | FAIL (−26.6 pts) | FAIL (−14.4) | ok | **REJECT** |
| M70 | +19.4% | FAIL (−25.0 pts) | FAIL (−9.4) | ok | **REJECT** |
| M55 | +31.0% | FAIL (−29.4 pts) | FAIL (−12.7) | FAIL | **REJECT** |

## What this says

**The token budget is where the argument lives.** Cutting the ceiling from 110
to 70 buys 19% more turns and costs more than half the rate at which agents
disagree with each other: 47.2% to 22.2%. Shorter replies here are not
punchier, they are blander. The models spend their first clause restating the
position and reach the objection later, so a lower ceiling removes the
objection and keeps the restatement.

M55 additionally breaks completeness — 23.3% truncated and a 30.5-word mean —
which is trimming discarding most of what was generated. Exactly the failure
the second completeness clause was written to catch.

## The guards are the finding

Without the interaction guards, **M70 would have shipped**. It gains 19.4%
throughput, holds truncation at 3.9%, has the *lowest* near-duplicate rate of
any condition, and lands at a 38-word mean — precisely the "30-45 word sweet
spot" both the operator and I predicted before running it.

It also halves the rate at which anyone contradicts anyone. A dashboard showing
throughput, truncation and repetition would have called it a clean win.

That is the second time in this sequence that a pre-registered guard rejected a
result that looked good on the headline numbers, and the first time it rejected
one that matched our stated prior.

## A caveat on absolute numbers

M110 here scores 47.2% challenge; three runs of the same configuration measured
earlier in the day scored 38.3%. Within-batch spread is small (sd 2.8) but
between-session drift is larger than that. All twelve runs here were
consecutive, so the comparison between conditions is internally valid, but
absolute values should not be carried across sessions and guards should be set
against a baseline measured in the same batch.

## Where the throughput actually is

At M110 a turn takes 3.9s of which about 2.1s is generation. The remaining
~1.8s is the fixed inter-turn interval and per-turn processing. That is the
lever worth pulling next: it costs nothing in debate quality, whereas every
token removed costs conflict.
