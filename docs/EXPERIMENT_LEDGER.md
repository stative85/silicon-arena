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

| **Q1** | Does resonance-selected recall of old canonical material beat a matched sham? | `f937c74` | conversion Q1 58.9% vs sham 75.7% vs none 0%; distance 11.7 turns; **0** fabricated attributions in ~84 injections | **REJECTED** — recall produces real long-range callbacks; the resonance scoring is not why, and the sham beat it |

**Shipped: 5. Rejected: 10.**

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

Both are in [CONTRIBUTING.md](../CONTRIBUTING.md) as non-negotiable:

1. A new test must be shown to fail.
2. You cannot set a useful threshold for a metric whose noise floor you have
   not measured.
