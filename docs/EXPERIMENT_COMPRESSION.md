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
