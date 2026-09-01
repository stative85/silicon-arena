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
