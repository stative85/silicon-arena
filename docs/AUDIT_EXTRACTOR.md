# Blast-radius audit: `extract_claim()` and `shape_of()`

Two bugs were found while wiring layered recall. Both sat underneath earlier
experiments, so the question is not "are they fixed" but **which published
results were measuring something other than what they claimed**.

## The bugs

**`extract_claim()` returned empty for most turns.** It looked for a sentence
end within the first 180 characters and otherwise gave up. After sentence
trimming, most replies open with a longer sentence than that.

Measured over **720 recorded turns** from the experiment archive: the old
implementation returned empty on **429 of them — 59.6%**.

**`shape_of()` classified every disagreement as a concession**, because
`"disagree"` contains `"agree"` and concessions were tested first.

## Callers

| function | callers | used by |
|---|---|---|
| `shape_of()` | `gonzo_recall.resonance()`, `live_match._note_scar()` | QLP only — both new |
| `extract_claim()` | `_pick_dispute()` | E2, D3 |
| | `_note_contention()` | C1 |
| | `_note_scar()` | QLP — new |

`agent_mind._extract_claim()` is a **different private function** with its own
implementation and is unaffected. The analysis tools in `tools/eval/` use their
own regexes and never called either function.

## Classification

### `shape_of()` — unaffected

Both callers are part of GONZO QLP, written after every completed experiment.
No prior result depended on it. The bug never reached a published number.

### E2 and D3 — numerically affected, decision unchanged

`_pick_dispute()` walks backwards through history until a claim extracts, so a
failure moved to an older turn rather than cancelling the event. Both
experiments fired at their intended rates (3–4 events per run, verified in the
logs at the time).

What was distorted is **which** claim got cited: only turns whose first
sentence fit in 180 characters were ever eligible, roughly 40% of them. The
events happened as designed and their measured effects (+5.6 and +3.3
addressing, against a +16 bar) are not close enough to the threshold for a
selection bias in claim choice to plausibly reverse them.

**Both rejections stand.**

### C1 — treatment under-activated, hypothesis unresolved

`_note_contention()` extracts a claim from the target's **most recent turn
only**, with no fallback to an older one. A failure meant no contention was
created at all.

That is the direct cause of the 0.75 contentions per run reported at the time.
The mechanism was starved by a broken extractor, not by an arena short of
disagreements.

**The C1 implementation still failed its pre-registered bar** — re-engagement
+10.7 against +16, and a bar is not moved after the fact. But the result cannot
be cited as evidence that contention memory does not work, because the
treatment barely ran. The correct statement is:

> C1 as implemented failed its pre-registered bar. A later audit found the
> treatment was under-activated by a broken claim extractor, so the broader
> contention-memory hypothesis remains **unresolved**.

**This does not reopen the conflict family.** That axis stays closed by the
standing rule; it simply must not be described as having established more than
it did.

## What changed

`extract_claim()` now falls back to the longest whole-word prefix within the
limit — still a verbatim substring of the canonical turn, so provenance is
unaffected. `shape_of()` tests challenges before concessions.
