# Does sentence trimming cost anything? And how noisy is this arena?

Follow-up to the compression experiment, run because two things needed
settling before any further intervention:

1. Trimming looked like it had cut challenge rate from 61.7% to ~36%. If real,
   the fix for truncation was buying complete sentences with lost conflict.
2. An unexplained jump in "addresses someone", 35% to 62%, appeared in the
   compression conditions. It was reported as unexplained and not cited.

Both needed replication rather than a story.

## Design

Six runs, AUTO roster held constant (stablelm-2-zephyr-1.6b /
h2o-danube3-4b-chat / gemma-3-1b), 60 speeches each, VRAM and memory cleared
before every run. Three with trimming, three without. `--no-trim` exists so the
arm is a flag rather than an edit.

## Results

| run | challenge | addresses | mean words | truncated | <=40 words |
|---|---:|---:|---:|---:|---:|
| **trimmed** | | | | | |
| R0_replicate | 35.0% | 38.3% | 59.1 | 3.3% | 21.7% |
| V1_var | 41.7% | 35.0% | 60.0 | 3.3% | 21.7% |
| V2_var | 38.3% | 38.3% | 60.5 | 1.7% | 21.7% |
| **mean** | **38.3%** | **37.2%** | **59.9** | **2.8%** | **21.7%** |
| **untrimmed** | | | | | |
| L0_baseline | 61.7% | 35.0% | 75.2 | 58.3% | 10.0% |
| U1_untrimmed | 30.0% | 55.0% | 73.3 | 63.3% | 6.7% |
| U2_untrimmed | 53.3% | 60.0% | 69.8 | 46.7% | 10.0% |
| **mean** | **48.3%** | **50.0%** | **72.8** | **56.1%** | **8.9%** |

Effect of trimming, in units of the larger arm's standard deviation:

| measure | change | significance |
|---|---:|---|
| truncated mid-thought | −53.3 pts | **7.6 sd** |
| replies <= 40 words | +12.8 pts | **8.1 sd** |
| mean words | −12.9 | **5.7 sd** |
| challenge rate | −10.0 pts | 0.7 sd — not measurable |
| addresses someone | −12.8 pts | 1.2 sd — not measurable |

## Both questions answered

**Trimming costs nothing measurable.** The apparent collapse in challenge rate
was an artefact of comparing against `L0_baseline`, which happens to be the
high outlier of the untrimmed arm. Across three untrimmed runs the challenge
rate is 61.7%, 30.0% and 53.3%. A 10-point difference between arms is 0.7 sd
and cannot be distinguished from that.

**The addressing jump does not survive replication.** Untrimmed addressing
varies 35.0% to 60.0% run to run. The 62% seen in the compression conditions —
which were all untrimmed, having been run before the trim landed — sits inside
that spread. There is no effect to explain, and the earlier "asking for brevity
increased addressing" reading is withdrawn.

## The finding that matters most for future work

**Trimming makes the arena roughly five times less noisy.**

| measure | untrimmed sd | trimmed sd |
|---|---:|---:|
| challenge rate | 13.4 | **2.5** |
| addresses someone | 10.8 | **1.6** |
| mean words | 2.3 | 0.6 |

At the untrimmed noise level, an intervention would need to move challenge rate
by roughly 27 points before it could be told from chance at 60 speeches. At the
trimmed level, 5 points is detectable. Every experiment from here is far
cheaper because the instrument stopped shaking.

The likely mechanism is that a severed sentence is a coin flip for the next
speaker: sometimes it reads as a provocation to attack, sometimes as noise to
ignore. Complete sentences give the next agent a stable thing to respond to.
That is an explanation, not a measurement, and is not relied on.

## Correction

An earlier note said trimming "could be my win deleting actual challenges" and
that challenge rate had fallen from 61.7% to 35-37%. That comparison used one
untrimmed run against three trimmed ones. With the untrimmed arm replicated,
the difference is 0.7 sd. The concern was unfounded and the trim stands.
