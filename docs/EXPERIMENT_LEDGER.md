# Experiment ledger

One source of truth for what was tested, what was decided, and where the
pre-registration lives. Casual counts drift — this exists because a summary
claimed "five of seven" when the real figure was five of eight.

Every row must name a shipping decision. An experiment that changes nothing in
the runtime does not belong here and should not have been run.

| id | question | pre-registered | result | decision |
|---|---|---|---|---|
| **R1** | Which roster mode should be the default? | `e9af6f8` | AUTO 14.07 spm vs default 1.82, judged quality indistinguishable; 3 blind judges disagreed with each other (r=0.01–0.32) | **SHIPPED** — AUTO is the default ([ROSTER_EVALUATION](ROSTER_EVALUATION.md)) |
| **R2** | Does AUTO plan against the real card? | — | a 24GB card was planning against 6GB | **SHIPPED** — `nvidia-smi`, 75% of VRAM (`7e4ffaa`) |
| **C1** | Do shorter replies follow from asking for them? | `eaf167d` | asked 15–25 words, got a median of 81; compliance 5% at baseline and 5% at target | **REJECTED** (`f185dc9`) |
| **T1** | Should replies be trimmed at the last complete sentence? | — | truncation 58.3% → 3.3%; A/B over 6 runs found no measurable cost and 5x less noise | **SHIPPED** (`bb90ae3`, `245625f`) |
| **M1** | Does a lower token ceiling buy throughput? | `76173ef` | M70 gains 19% and halves the contradiction rate; M55 breaks completeness | **REJECTED** — 110 stands (`36dc0d9`) |
| **P1** | Does a one-deep pipeline help, headless? | `002d20f` | +32.2% throughput, all correctness guards held, two guards mis-specified | **REJECTED** by its own rule |
| **P2** | Same question, thresholds calibrated first | `75a88f1` | +37.2%, paired delta +5.50 against a 1.40 envelope, 0 stale, dwell within tolerance | **SHIPPED** — headless default |
| **P3** | Does the pipeline help the visual app? | `75a88f1` | 29 turns/200s before and after — exactly zero; the free-running timer already overlapped | **REJECTED and reverted** (`af6afa8`) |
| **E1** | Does periodic state escalation help? | `da635ff` | challenge slope +10.0 as intended, addressing slope −31.2, opener uniqueness −0.18 | **REJECTED** — escalates but stops agents engaging each other (`dc99aac`) |

| **E2** | Can a targeted event turn a disagreement into a running dispute? | `7d4f669` | addressing +5.6 (bar was +16), challenge +8.3, no harm to any guard, 0 fabricated citations | **REJECTED** — right direction, too small |

| **D3** | Does a bounded 3-turn dispute outlive its scaffold? | `4178a06` | addressing +3.3 (bar +16), no guard harmed, 0 fabricated citations, top-pair share flat | **REJECTED** — scaffolded conflict does not self-sustain |

| **C1** | Does claim-scoped decaying contention memory create callbacks without obsession? | `a4dcacb` | re-engagement 10.7% → 21.4% (+10.7, bar +16); top-pair share *fell*; 0 outlived TTL | **IMPLEMENTATION REJECTED; hypothesis unresolved** — a later audit ([AUDIT_EXTRACTOR](AUDIT_EXTRACTOR.md)) found the treatment fired 0.75×/run because a broken claim extractor failed on 59.6% of turns. The bar was missed and stands; the mechanism barely ran, so this is **not** evidence that contention memory fails. Does **not** reopen the conflict axis. |

| **PR1** | Does uneven presentation rhythm work without costing throughput? | `5f9c54d` | 25 distinct dwells vs 1, applied mean exactly 1.000, 30 turns vs 29 baseline | **SHIPPED** — watchability itself needs a human |
| **T1** | Does a four-phase topic arc give the debate trajectory? | `ca67213` | pivot shifted vocabulary +0.013 (bar 0.10); CLOSE resolution fell 26.9% → 17.8%; opener uniqueness 0.80 → 0.64 | **REJECTED** — cosmetic, and instructing a conclusion made conclusions worse |

| **Q1** | Does resonance-selected recall of old canonical material beat a matched sham? | `f937c74` | conversion Q1 58.9% vs sham 75.7% vs none 0%; distance 11.7 turns; **0** fabricated attributions in ~84 injections | **REJECTED** — the sham beat it, and the resonance scoring is not why. **Interpretation corrected (MP1):** this row originally read "recall produces real long-range callbacks". That claim is not supported — a sham outscored the real memory here (75.7% vs 58.9%) and again in MP1, and the metric behind all three numbers is suspect. The "none 0%" arm is 0 by construction, not evidence. |

| **G1/G2** | Does distance alone match resonance when exposure is matched? | `2714e4c` | conversion 68.7% vs 73.1% — a 0.5 sd gap | **SUPERSEDED by T1** — the arena design manufactured its own variance; the paired tournament answered it properly |

| **T1** | Does resonance earn ~120 lines, given identical moment and pool? | `2955612` | 127 paired counterfactual trials: distance 69.3% vs resonance 65.4%, R−D = −3.9; 0 unsupported attribution | **RESONANCE DELETED** — R−D swung +5.0 → +7.4 → −3.9 as the sample grew; only the pre-fixed target made the answer defensible |

| **E0/E1** | Does nomic-embed-text-v1.5 beat the distance policy enough to justify an embedding subsystem? | `68b5b19` | 182 paired opportunities: E0 70.9% vs E1 75.3%, +4.4 (bar +10); E1 won 1 of 4 batches and declined monotonically; 0 unsupported attribution; latency 137 ms vs a 100 ms bound | **REJECTED** — and a placebo arm showed both arms score *below* a no-memory control, so `_is_callback` does not measure engagement ([EXPERIMENT_EMBEDDING](EXPERIMENT_EMBEDDING.md)) |

| **MP1** | Is `_is_callback` measuring memory engagement at all? | `bbf4a4f` | 144 opportunities, S0 none / S1 sham / S2 real: verbatim-rejection gap +7.6 (bands were <5 sound, >=10 broken); real vs sham **-6.3** shipped and **+0.0** with the verbatim clause removed | **INCONCLUSIVE** — metric stays suspect; no absolute conversion number may be published ([EXPERIMENT_METRIC](EXPERIMENT_METRIC.md)) |

| **MP2-A** | Can a source-specific measure detect uptake at all? | `1d3e62d` | instructed ceiling arm returned +6.7 against a +25 gate; it copied the memory 0 times in 60 opportunities and matched the uninstructed arm at 0.50 vs 0.52 | **GATE FIRED, CONTROL INVALID** — the ceiling never rose, so the gate could not mean what it was written to mean. Produced rule 6 ([EXPERIMENT_SOURCE](EXPERIMENT_SOURCE.md)) |

| **MP2-A2** | Same question, ceiling that needs no compliance | `cfd8cc4` | paraphrase ceiling +53.3 against +25; 10.4% paraphrases discarded against a 25% void line; sham column flat at 1.7% across every branch | **PASSED** — the measure discriminates *which* source, which `_is_callback` never could |

| **MP2-B** | Does real recall create source-specific influence? | `1d3e62d` | reached 240; scramble gate returned 11.3 against a bound of 5.0 | **VOID** — the gate compared a max of 200 draws to a bound set without measuring the null's spread (sd 3.95, expected max 11.2). Rule 2, broken by the guard enforcing it |

| **MP2-B2** | Same question, corrected gate, fresh transcripts | `a12f3f3` | 240 opportunities: lift(R) +17.9, lift(S) +21.3, both past +10 and 3.4 apart; estimator bias -0.14, observed 17.9 vs label-noise p95 8.3; **1 unsupported attribution in 720 replies, and it came from the sham arm** | **INCONCLUSIVE** — the primary numbers reached outcome 2 and the zero-attribution condition failed on the control arm. Bar not rescoped |

| **SWARM-V** | Can locally-informed agents allocate the speaking slot with the arena blind to why? | `85d34f2` | 400 opportunities, no generation: 100% valid allocation with no fairness machinery; agreement with round-robin 85.8% against a 35.0% random placebo; concentration 30.4% vs placebo 30.4%; longest unproposed run 44 vs placebo 14 | **VIABLE AND UNCONVINCING** — the bar is met, and 14 points of divergence is all local bidding bought. The starvation-weighted bid encodes the cage it replaces ([EXPERIMENT_SWARM](EXPERIMENT_SWARM.md)) |

**Shipped: 5. Rejected: 12. Inconclusive: 3. Void: 1. Viable-but-unconvincing: 1. Undecided: 0.**

## Open, and blocking further recall work

`_is_callback` is not a valid measure of memory engagement. A reply generated
with **no memory injected** scores 78.0% on it, above both memory arms. The
suspected cause is its own verbatim-repetition exclusion: a model that genuinely
engages a memory tends to echo a phrase of it and gets disqualified, while a
free-running reply sharing topical vocabulary passes.

Paired arm-versus-arm results survive this — both arms are scored by the same
instrument at the same moments, and the E0/E1 null control measured a bias of
exactly +0.0 points. Absolute conversion rates do not survive it and should not
be quoted as engagement rates.

The sham-controlled rerun was pre-registered (`bbf4a4f`) and run (MP1). It came
back **inconclusive on the metric question** — the verbatim-rejection gap landed
at +7.6, inside the 5-to-10 band — but it settled a different one:

**Real memory does not outperform a sham.** -6.3 points on the shipped metric,
and +0.0 with the verbatim exclusion removed (80.6% against 80.6%). A block of
unrelated text from another match does what the recalled memory does.

So the standing constraint is unchanged and now better evidenced: **no absolute
callback conversion number may be published**, and recall may not be described
as producing callbacks. Recall stays shipped — an inconclusive result unships
nothing — but its justification is not established.

Settling the verbatim question requires a NEW pre-registration with a target
fixed in advance and powered for the observed effect. Running past 144 until
+7.6 crosses 10 is the exact sin that would have shipped resonance at 81 pairs.

**MP2 is that pre-registration** ([EXPERIMENT_SOURCE](EXPERIMENT_SOURCE.md)),
and it asks a different question rather than powering up the same one: does the
*content* of the recalled scar change the reply in a way traceable to its
source? Absolute conversion is abandoned as a quantity. The measure is a paired
crossover scoring every reply against both the real and the sham source, so the
placebo floor is subtracted rather than assumed.

### The pattern across everything rejected

Nine rejections, and the successful changes have a shape the failures do not.
**Sentence trimming and the presentation director both changed what the arena
DOES with model output. Every rejected intervention tried to change what the
models were ASKED to produce** — argue harder, be shorter, take a position,
follow a phase. Instructions do not survive contact with these models; handling
their output does.

### What the three conflict experiments establish together

| | intervention | post-effect on addressing |
|---|---|---:|
| E1 | world events | −31.2 |
| E2 | one targeted challenge | +5.6 |
| D3 | three-turn bounded episode | +3.3 |
| C1 | claim-scoped contention memory | re-engagement +10.7 (treatment under-activated — see audit) |

Prompt scaffolding does not produce durable rivalry on these models, and state
that survives the event does better but still not enough. Four interventions,
four rejections. E1, E2 and D3 tested the hypothesis fairly; C1 did not, because
its treatment was starved by a broken extractor. **Scaffolding does not create
durable rivalry** is established. **Memory does not** is not. Per the
C1 pre-registration, the next entertainment lever should be something other than
a fifth way of making agents argue.

## Supporting work that is not an experiment

These produced no shipping decision on their own and are listed so they are not
miscounted as results.

| what | why it exists |
|---|---|
| null calibration (`75a88f1`) | measures what the A/B protocol invents with nothing changed: challenge envelope 53.7 points at 20-speech blocks |
| slope noise floor | six identical-config runs; challenge slope 2sd = 20.3, `commit` unusable at 48.6 |
| `tools/eval/` harness | conditions runner, metrics, blind set, judges, paired analysis |

## Rules these produced

These are in [CONTRIBUTING.md](../CONTRIBUTING.md) as non-negotiable, where
they are numbered alongside two rules that came from production bugs rather
than from experiments. This said "Both" above a list of three, in the document
that exists because casual counts drift:

1. A new test must be shown to fail.
2. You cannot set a useful threshold for a metric whose noise floor you have
   not measured.
3. A detection metric needs a placebo floor, not just a noise floor. Ask how
   often it fires when the thing it detects is absent. The embedding router
   measured +50.0 points until a no-memory placebo "called back" to its own
   pick 91.3% of the time.
4. A positive control must be able to detect its own failure. MP2-A's ceiling
   arm instructed the model to build on a recalled memory; it copied nothing
   from that memory in 60 opportunities and scored what the uninstructed arm
   scored. The gate read "measure is blind" and could not tell that apart from
   "the ceiling never rose". Do not build a control out of a mechanism this
   ledger already rejected.
