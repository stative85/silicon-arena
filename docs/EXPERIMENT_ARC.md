# Pre-registration: does a debate with an arc go somewhere?

**Written and committed before the arms were run.**

## The question

Four experiments closed the conflict axis: making agents argue harder does not
help. The remaining complaint is different — nothing accumulates. Sixty turns
of equal weight, no beginning, no pivot, no ending.

T1 gives the debate a structure:

```
OPEN      state your position and the one reason you hold it
DEVELOP   (no task — react normally)
TURN      one new constraint enters; say whether it changes your position
CLOSE     name the position you now hold and what would change your mind
```

Each phase changes **what the debate has to accomplish**, never how emotional
anyone is told to sound. "Argue harder with nicer branding" is the failure this
is written to avoid, and the selftest asserts no task instructs a mood.

**Exactly one pivot.** Several twists would make attribution impossible.

## Conditions

| id | behaviour |
|---|---|
| T0 | current AUTO |
| T1 | AUTO + four-phase arc |

4 runs per arm, 60 speeches, interleaved. Roster, tokens, trim, pipeline,
presentation director all fixed.

## Primary measure: does the pivot change what is discussed?

Content-word overlap between the 8 turns before the pivot and the 8 after,
compared at the same positions in T0. A larger vocabulary shift in T1 means the
constraint redirected the discussion.

**Words appearing in the injected constraint are excluded from the
comparison.** Otherwise agents echoing "memory" and "refusal" back would count
as redirection when it is only repetition of the prompt. The measure is whether
the debate moved, not whether the models can copy.

**Acceptance requires both:**

1. post-pivot vocabulary shift exceeds T0 at the same positions by at least
   **0.10** (Jaccard distance, excluding injected words);
2. **CLOSE resolution rate at least 40%** — closing turns that name a position
   or what would change it, rather than "in conclusion, this is a complex
   issue".

If the pivot changes nothing downstream, the arc is cosmetic and is rejected
regardless of how tidy the phases look.

## Guards

| guard | bound |
|---|---|
| pivots fired per run | **exactly 1** |
| speeches per minute | not below T0 − 1.40 (calibrated envelope) |
| near-duplicate rate | not more than T0 + 8.1 |
| opener uniqueness | not below T0 − 0.15 |
| truncation | at or below 5% |
| failure rate | not above 2% |

## Invariants

```
INVARIANT   every turn belongs to exactly one phase; exactly one pivot fires;
            no phase task instructs a mood; the pivot is a constraint rather
            than an order; a generic summary is not counted as resolution
DETECTION   phase_for() is total; is_resolved() rejects hedging vocabulary
TEETH       a hedge inside a commitment still fails resolution
PROOF       topic_arc_selftest.gd — 24 checks
```

## Not part of the decision

Judge scores.


---

# Result: the arc is cosmetic, and the ending got worse. T1 rejected.

4 runs per arm, 60 speeches, pivot at turn 33.

| | T0 | T1 | delta |
|---|---:|---:|---:|
| post-pivot vocabulary shift | 0.759 | 0.772 | **+0.013** |
| CLOSE resolution rate | **26.9%** | **17.8%** | **−9.1** |
| opener uniqueness | 0.80 | **0.64** | −0.16 |
| speeches/min | 17.67 | 16.57 | −1.10 |

| pre-registered check | value | verdict |
|---|---|---|
| post-pivot shift beats T0 by >= 0.10 | +0.013 | **FAIL** |
| CLOSE resolution >= 40% | 17.8% | **FAIL** |
| opener uniqueness >= T0 − 0.15 | 0.64 vs 0.80 | **FAIL** |
| exactly 1 pivot per run | 1.0 | OK |
| all other guards | — | OK |

**Rejected on three counts.**

## The pivot changed nothing

A vocabulary shift of +0.013 against a bar of 0.10 means the constraint did not
redirect the discussion. Both arms shift about 0.76 across the same window,
which is what a debate does anyway as it wanders. The pivot was injected,
acknowledged in the moment, and had no downstream effect — the definition of
cosmetic.

## Instructing a conclusion made conclusions worse

This is the interesting result. **T0 resolved 26.9% of its closing turns with no
instruction at all. T1, explicitly told to name a position and what would change
its mind, resolved 17.8%.**

Asking for resolution reduced resolution by a third. The most likely reading is
that the added task competes for a fixed token budget with the content that
would have constituted an actual position — the models spend words
acknowledging the instruction. This run cannot separate that from other
explanations and the claim is not made, but the direction is clear and it
matches the compression result: these models do not gain from being told how to
write, only from being given room.

## And the phases made everyone sound alike

Opener uniqueness fell 0.80 to 0.64. Handing every agent the same phase task
makes them open the same way — the formulaic collapse that the guard exists to
catch, showing up for the third time.

## What this rules out

Structural framing imposed by prompt. That is the same family as the four
conflict interventions: instructions about how to conduct the debate, whoever
they are addressed to, do not survive contact with these models.

Five pre-registered attempts have now failed in the same shape. The two changes
that shipped — sentence trimming and the presentation director — both worked by
changing what the arena DOES with output rather than what it asks models to
produce.

## Status

`--arc` stays off by default. The 24 invariant checks stay in the gate.
