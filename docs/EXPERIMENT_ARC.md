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
