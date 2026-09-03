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


---

# Result: resonance is not deleted, and it is not vindicated either.

4 runs per arm, 60 speeches, frozen at `2714e4c`.

| arm | injected | callbacks | **conversion** | distance | unsupported |
|---|---:|---:|---:|---:|---:|
| G0 none | 0 | 0 | — | — | 0 |
| **G1 distance** | 40.75 | 27.75 | **68.7%** | 15.8 | **0** |
| **G2 resonance** | 36.75 | 27.25 | **73.1%** | 15.5 | **0** |

Source-distance profiles matched: 15.8 against 15.5. The confound from
EXPERIMENT_RECALL is gone.

| check | value | verdict |
|---|---|---|
| G1 >= G2 on conversion | 68.7% vs 73.1% | **FAIL** |
| unsupported attribution == 0 | 0.00 | OK |
| all other guards | — | OK |

**The resonance machinery is not deleted**, because the rule said delete only
if distance won and it did not.

## But this does not show resonance works

Per-run conversion:

```
G1 distance   58  65  75  78     mean 69.0   sd 8.0
G2 resonance  84  71  77  61     mean 73.2   sd 8.4
```

The difference is **+4.2 points against a run-to-run standard deviation of
8.4 — half a standard deviation**, with the ranges almost entirely overlapping
and each arm winning two of four runs. At four runs per arm the standard error
is about 4.2, so two standard errors is 8.4: the observed gap is inside it.

The honest statement is that **distance alone was not shown to be sufficient**,
not that resonance was shown to help. The evidence is weak in both directions
and the rule happened to be directional.

## A flaw in my own pre-registration

I wrote the decision as `G1 >= G2` with **no noise band**. That let a
half-standard-deviation difference decide whether ~120 lines of scoring
machinery lived or died.

This is the same error as the guards that fired at random earlier: a threshold
set without reference to the spread of the thing it measures
(`CONTRIBUTING.md` rule 2, which I wrote). A better rule would have been "delete
if G1 is within one standard error of G2", which on these numbers would have
deleted it.

I am **not** applying that rule now. Rewriting a decision threshold after seeing
the data is precisely what the pre-registration exists to prevent, and doing it
here — where it would produce the outcome I had already argued for — would be
the worst possible time. The machinery stays until an experiment designed with a
noise band says otherwise.

## What replicated, strongly

Across ~310 injections in this experiment plus ~84 in EXPERIMENT_RECALL:

* **conversion 69–73%** — sparse recall of genuinely old canonical material
  produces non-verbatim callbacks most of the time it is surfaced;
* **mean distance ~15.5 turns**, well outside the visible window;
* **zero fabricated attributions**, in every arm, in every run.

The provenance teeth have now held across roughly 400 injections without a
single unsupported quote.

One incidental result worth noting: distance-based recall **halved repetition**
against no recall at all (4.6% near-duplicate versus 10.0%). Neither arm was
predicted to do that and it is reported without an explanation.
