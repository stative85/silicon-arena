# Pre-registration: does shortening replies make the arena more watchable?

**Written and committed before the experiment was run or the mechanism built.**
The point of that ordering is that twelve metrics and a free choice afterwards
is p-hacking with extra steps.

## Hypothesis

The arena's entertainment problem is length, not passivity. AUTO already leads
every roster condition on conflict (63.3% challenges) while producing 76-word
paragraphs: only 6.7% of replies are 40 words or fewer and 15% run to 90 or
more. A viewer waits through a paragraph before anyone is contradicted.

Compressing replies should raise turns per minute and put more exchanges on
screen per unit of attention, without reducing how often agents take each other
on.

## Design

Four conditions. **AUTO roster held constant** — same models, same personas,
same topic, same harness, same turn count. The only variable is the requested
reply length.

| id | target |
|---|---|
| L0 | baseline, current prompt (~76 words observed) |
| L1 | 45-55 words |
| L2 | 30-40 words |
| L3 | 15-25 words |

60 speeches per condition, run as four 15-turn chunks, VRAM emptied and memory
cleared before each condition — the same protocol as the roster evaluation.

## Primary outcome, declared in advance

A condition **passes** only if BOTH hold:

1. **Compliance**: at least 60% of replies fall inside the requested band.
   A condition that ignores the instruction tests nothing.
2. **Throughput**: speeches per minute at least **15% above L0**.

## Guard rails, declared in advance

A condition **fails** if any of these worsen past its bound, no matter how good
the primary numbers look:

| guard | bound |
|---|---|
| near-duplicate rate | not more than baseline + 2 points |
| opener uniqueness | not below baseline − 0.05 |
| formulaic openers | not more than baseline + 5 points |
| challenge rate | not below baseline − 5 points |
| turn failure rate | not above 2% |
| truncation rate | not above 10% |

`truncation rate` is the share of replies ending without terminal punctuation
(`.`, `!`, `?`, `"`), which is how a too-small token budget shows up: the model
is cut off mid-thought. Squeezing the word count until sentences break is not a
win, and without this guard it would look like one.

## Tie-break, declared in advance

If several conditions pass, take the highest speeches per minute. If none pass,
keep L0 and report that compression did not work.

## What is explicitly NOT part of the decision

Judge entertainment scores. They are reported for completeness and carry no
weight in accepting or rejecting a condition, because on the roster evaluation
the three judges correlated −0.066, −0.108 and +0.184 with each other on
exactly this dimension. That is noise, and noise cannot adjudicate.

Term uptake, topic drift and concession rate are reported as description. They
have no pre-declared direction: a shorter reply plausibly moves them either way
and picking a direction now would be inventing a prediction to be right about.


---

# Result: compression by instruction does not work. L0 stands.

Run as pre-registered: AUTO roster held constant (3 architectures,
stablelm-2-zephyr-1.6b / h2o-danube3-4b-chat / gemma-3-1b), 60 speeches per
condition, four 15-turn chunks, VRAM and memory cleared before each.

| metric | L0 baseline | L1 45-55 | L2 30-40 | L3 15-25 |
|---|---:|---:|---:|---:|
| mean words | 75.2 | 77.3 | 76.6 | 75.3 |
| median words | 84 | — | — | 81 |
| **compliance** | — | ~0% | 1.7% | **5%** |
| replies <= 40 words | 10.0% | 0.0% | 1.7% | 5.0% |
| speeches / min | 14.4 | 14.1 | 14.0 | 14.2 |
| truncated mid-thought | 58.3% | 71.7% | 78.3% | 71.7% |
| challenges | 61.7% | 51.7% | 63.3% | 46.7% |
| addresses someone | 35.0% | 61.7% | 63.3% | 61.7% |
| opener uniqueness [guard] | 0.85 | 0.65 | 0.85 | 0.70 |

**No condition passes.** Compliance never approached the declared 60% floor —
asking for 15-25 words produced a median of 81 — and throughput never moved.
Two conditions also breached the truncation guard and one breached the opener
guard. Per the pre-registration, L0 stands and the intervention is rejected.

## Why it failed, which is the useful part

Mean reply length is 75-77 words in **every** condition including the ones that
asked for a quarter of that. `max_tokens` is 110, which is roughly 80 words.
The replies are not the length the model chose; they are the length the budget
allowed, and 58-78% of them end mid-sentence because the budget cut them off.

These small models do not obey word-count instructions at all. Compliance was
5% at 15-25 words and 5% at baseline, which is to say the instruction changed
nothing measurable.

Adding the instruction made truncation **worse** (58.3% to 71.7-78.3%). The
most plausible reading is that a model told to be brief front-loads more
content per sentence and therefore has more left unsaid when the budget runs
out, but this run cannot separate that from noise and the claim is not made.

## What this rules out and what it points at

Ruled out: prompt-level length control on this class of model.

Pointed at: the real lever is `max_tokens`, which is a hard constraint rather
than a request, plus trimming replies at the last complete sentence so a cut
budget stops being visible. Those are different interventions and get their own
pre-registration rather than being folded into this one after the fact.

## A note on the guards

They worked. L1 dropped opener uniqueness to 0.65 and L2/L3 pushed truncation
past 70%, so even if compliance had been reached, two conditions would have
been rejected on the guards. That is the anti-Goodhart machinery doing its job
on the first experiment it was applied to.
