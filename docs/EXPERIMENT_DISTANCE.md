# Pre-registration: does distance alone beat resonance when exposure is matched?

**Written and committed before the arms were run.** Decides whether the
resonance machinery is deleted.

## Why

Q1 established that sparse provenance-valid recall of old canonical material
produces non-verbatim callbacks, and that resonance scoring is not why: the
sham converted at 75.7% against resonance's 58.9%
([EXPERIMENT_RECALL](EXPERIMENT_RECALL.md)). But that comparison had two
confounds — the sham injected more and reached further back.

This removes both by construction.

## Conditions

| id | selection rule |
|---|---|
| G0 | no recall |
| **G1 distance** | of the shared shortlist, take the **furthest** |
| **G2 resonance** | of the shared shortlist, take the **most resonant** |

**Both arms draw from one shortlist**: the `CANDIDATE_SHORTLIST` (4) most
distant eligible scars, where eligible means provenance-valid, past cooldown,
and older than the visible window. Injection count per turn is the same rule
for both — `min(2, shortlist size)`. Formatting, prompt position, cooldown,
decay and the minimum-distance bound are identical.

**Only the choice rule differs.**

Smoke-tested before freezing: mean source distance 14.9 (G1) against 15.3 (G2)
— the confound that mattered is gone.

**What still cannot be matched:** total injections across a run. Once the arms
choose differently the debates diverge, different scars are created, and
eligibility drifts. The per-turn rule is identical and the primary measure is a
**rate**, so this is controlled; it is stated rather than hidden.

4 runs per arm, 60 speeches, interleaved. Frozen once started.

## Primary

Provenance-valid **non-verbatim callback conversion** — successful callbacks
over eligible recalls actually injected. Definition unchanged from
EXPERIMENT_RECALL: provenance valid, engages with the excerpt, contains novel
language beyond it, not a verbatim repetition.

## The decision, declared in advance

**If G1 >= G2 on conversion and every guard passes, the resonance machinery is
DELETED** — not disabled, not left behind a flag.

Deleted: `resonance()`, `weighted_resonance()`, the four dimensions, the
weights, and the scoring path.

Kept: canonical source, scar eligibility, minimum distance, decay, cooldown,
provenance, the tiny recall budget, and anti-self-reinforcement.

If G2 > G1, resonance has finally earned its place and stays.

## Guards

Unchanged from EXPERIMENT_RECALL: unsupported attribution 0, fixation not above
G0 + 15, near-duplicate not above G0 + 8.1, opener uniqueness not below
G0 − 0.15, throughput not below G0 − 1.40, failures at or below 2%.

## What this would make QLP

If distance wins, the mechanism stops being "retrieve what looks most relevant"
and becomes something plainer and stranger: **an old scar comes back because it
has survived long enough to matter**, and the agent decides whether it does.

Old truth, decay, provenance, scarcity. No relevance engine.

## Not part of the decision

Judge scores. A stochastic variant — a weighted draw among survivors rather
than deterministic top-1 — is explicitly **not** in this experiment and is not
built.
