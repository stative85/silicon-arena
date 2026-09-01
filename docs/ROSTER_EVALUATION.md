# Which roster mode should be the default?

Decided by a blinded four-condition evaluation, not by reading a transcript.
Harness and protocol: [tools/eval/](../tools/eval/README.md).

One machine, one session, one topic, RTX 5060 8GB. Each condition ran the same
roster for four 15-turn matches (~60 speeches), same topic, same agent count,
same harness, with VRAM emptied and memory cleared before each condition.

## Mechanical measurements (no model in the loop)

| metric | A default | B `--balanced` | C `--fast` | D `--fit` |
|---|---:|---:|---:|---:|
| speeches | 59 | 60 | 60 | 60 |
| **speeches / min** | **1.82** | 7.77 | **17.60** | **14.53** |
| failure rate | 1.7% | 0% | 0% | 0% |
| distinct models | 5 | 2 | 1 | 3 |
| median latency | 32.9s | 5.2s | 2.3s | 2.1s |
| p90 latency | 48.3s | 14.3s | 3.0s | 5.5s |
| **refers to another agent** | **66.1%** | 31.7% | **0.0%** | **65.0%** |
| **challenge / contradiction** | 45.8% | 48.3% | **18.3%** | **55.0%** |
| near-duplicate rate | 8.5% | 0% | 0% | 13.3% |
| content novelty | 0.269 | 0.326 | 0.347 | 0.248 |
| self-prefix leakage | 0% | 0% | 0% | 0% |
| picks up a term the previous speaker introduced | 47.1% | 37.5% | 46.6% | **50.9%** |

The uptake row replaces an earlier "cross-agent retention" measure that scored
98.3% in all four conditions. That version asked whether a speech shared two
content words with any of the previous three turns, which measures that the
debate is in English, not that anyone is listening. The replacement asks
something a condition can fail: a term must be new to the whole run when the
previous speaker used it, and then be picked up by the next.

It is worth reading next to the reference row. `--fast` names another agent
**0%** of the time yet picks up their new terms 46.6% of the time — it engages
with the content and never with the person. That distinction was invisible
before.

## Blind judges

39 excerpts of six consecutive turns, speaker names replaced, in-text names
rewritten, model ids and bare parameter sizes scrubbed, shuffled. Judges are
from families that appear in **no** roster under test.

| dimension | A | B | C | D |
|---|---:|---:|---:|---:|
| **J1** `adg-alpaca-gpt4-qwen2.5-7b` (37 scored, 2 unusable) | | | | |
| coherence | 3.62 | 3.33 | 3.90 | 3.60 |
| distinctiveness | 2.88 | 2.78 | 4.10 | 2.70 |
| argument quality | 3.12 | 3.00 | 3.30 | 3.10 |
| responsiveness | 3.12 | 3.22 | 3.60 | 3.00 |
| entertainment | 2.88 | 2.89 | 2.50 | 2.90 |
| **J1 overall** | 3.10 | 3.04 | **3.40** | 3.05 |
| **J2** `phi-3-mini-4k-instruct` (39 scored, 0 unusable) | | | | |
| coherence | 4.00 | 4.10 | 4.40 | 4.00 |
| distinctiveness | 4.00 | 4.50 | 4.50 | 3.70 |
| argument quality | 4.00 | 4.10 | 4.10 | 4.00 |
| responsiveness | 3.44 | 4.60 | 4.90 | 3.40 |
| entertainment | 2.22 | 2.80 | 3.00 | 2.10 |
| **J2 overall** | 3.78 | 4.18 | **4.32** | 3.70 |

Both judges rank `--fast` first. **That ranking is not trustworthy**, and the
reason is visible in the table above it.

## Why the judges were not followed

`--fast` **never once referred to another agent** — 0% against 65–66% — and had
the lowest challenge rate, 18.3% against 46–55%. Both judges nonetheless scored
it highest on *responsiveness* (J1 3.60, J2 4.90). A condition in which no
speaker ever addresses another cannot be the most responsive one. The judges
are not measuring the thing the word names.

Agreement supports the same caution. Reported as a measurement, never as
validation:

```
excerpts scored by both: 37
OVERALL          pearson r=0.312   mean|diff|=0.86   means 3.15 / 4.02
coherence        pearson r=-0.018
argument_quality pearson r=-0.078
entertainment    pearson r=-0.061
relevance        constant for both judges (3.00 and 5.00) - uninformative
condition-ranking spearman: 0.400
same best condition: YES
```

Two of six dimensions correlate slightly negatively between judges, one is
degenerate, and the scales differ by nearly a full point. The judges agree on
the winner and on almost nothing else. Agreeing on a winner is weak evidence
when both may share a bias — and the responsiveness contradiction shows they do.

## The decision

The objective is maximum useful **heterogeneous** debate per minute.

* `--fast` is one model wearing five hats. It is disqualified by construction,
  independently of its scores.
* `--fit` reaches **8x** the default's throughput (14.53 vs 1.82 speeches/min)
  at judged quality neither judge could separate from it — 3.05 vs 3.10 and
  3.70 vs 3.78, well inside the noise implied by r=0.312 — while referring to
  other agents just as often (65.0% vs 66.1%) and challenging them **more**
  (55.0% vs 45.8%).
* `--fit`'s real measured cost is repetition: 13.3% near-duplicate against
  8.5%, and the lowest content novelty of the four. That is a genuine trade,
  and it is why the answer is not simply "make `--fit` the default".

So the default is now **AUTO**, which picks a mode from what the machine can
actually do:

1. three or more co-resident, probe-verified chat-capable architectures;
2. otherwise two, with grouped scheduling;
3. otherwise one shared model, and it says plainly that this is not a
   heterogeneous debate;
4. never exceeding the 7B request law — audited at source in
   `tools/adversarial.gd`, which fails if any rung selects from the unfiltered
   installed list.

`--diverse` still gives the historical one-model-per-agent roster.

## Follow-up: the repetition had a cause, and it was fixable

`--fit`'s one clear measured weakness was repetition — 13.3% near-duplicate
speeches. Inspecting the pairs showed it was **not** models repeating
themselves. Every one was an agent restating the previous speaker verbatim
before adding anything, sometimes nested two deep:

```
"Stablelm #1 said: H2o Danube #1 raises a valid point about how AI systems
 can learn from their experiences and adapt their..."
```

And the reason agents sharing a model produced near-identical text was blunter:
`build_roster.gd` wrote `"persona": ""` for every agent, while `live_match.gd`
builds its prompt as `Your character: %s`. Agents on the same model were
receiving byte-identical prompts that differed only in a display name. That is
also the most likely reason `--fit` scored **lowest on distinctiveness** with
both judges.

Two fixes: a deterministic stripper for verbatim quotation of an earlier turn,
and five distinct argumentative stances assigned so that agents sharing a model
never share one.

Re-measured on the same roster and window:

| metric | before | after |
|---|---:|---:|
| near-duplicate rate | 13.3% | **3.3%** |
| mean max similarity | 0.161 | **0.086** |
| content novelty | 0.248 | 0.264 |
| challenge / contradiction | 55.0% | **61.7%** |
| refers to another agent | 65.0% | 53.3% |
| speeches / min | 14.53 | 14.07 |

Duplication is now lower than the historical default's 8.5%, and the challenge
rate is the highest of any condition, at essentially unchanged throughput.

The drop in "refers to another agent" is a consequence of the fix rather than a
regression: those references were largely inside the quoted restatements that
are now removed. The metric was counting quotation as engagement.

Re-judged blind, the two judges disagree about the change:

| | J1 before | J1 after | J2 before | J2 after |
|---|---:|---:|---:|---:|
| distinctiveness | 2.70 | 2.80 | 3.70 | **4.30** |
| responsiveness | 3.00 | 3.00 | 3.40 | 3.80 |
| coherence | 3.60 | **3.20** | 4.00 | 4.00 |
| overall | 3.05 | 3.00 | 3.70 | **3.92** |

J2 rates it clearly better and now ranks `--fit` above the historical default.
J1 rates it marginally worse, driven by a coherence drop. Agreement between the
judges is as weak as before (overall r=0.324), so this is recorded as a split
rather than resolved. The mechanical improvements are unambiguous; the judged
effect is not.

## Limits

One machine, one session, one topic, ~60 speeches per condition. Each condition
is four short debates rather than one long one, applied identically to all four.
Rosters were chosen by the builder, so conditions differ in which models they
contain as well as how many — D drew smaller models than A, and part of D's
throughput is cheaper inference rather than residency alone
([BENCHMARK_8GB.md](BENCHMARK_8GB.md) separates those). Two judges is a small
panel and they disagreed substantially.
