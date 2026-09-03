# Pre-registration: does resonance earn its ~120 lines?

**Written and committed before the harness was built or run.** Final decision on
the resonance scorer.

## Why the arena design cannot answer this

G1/G2 gave 68.7% against 73.1% — half a standard deviation, inside the noise
([EXPERIMENT_DISTANCE](EXPERIMENT_DISTANCE.md)). Averaging harder will not fix
it, because the design manufactures the variance it is fighting: once the two
arms select different memories the debates diverge, and after that the candidate
pools, injection counts and topics are no longer comparable.

## Paired counterfactual trials

At every eligible recall opportunity in a **recorded** transcript, freeze the
canonical state and generate two disposable branches:

| held identical | varied |
|---|---|
| agent, model, topic | **only the selected scar** |
| visible history | |
| candidate pool and shortlist | |
| source-age constraints | |
| prompt formatting and generation settings | |

**Branch D** gets the distance-selected scar. **Branch R** gets the
resonance-selected scar. Both responses are scored with the frozen callback
definition, recorded, and **thrown away** — neither enters history, so nothing
diverges and every opportunity yields exactly one D and one R observation on
identical context.

Opportunities where both rules select the *same* scar are skipped: they carry no
contrast.

Target: **100+ paired opportunities.**

The harness runs in GDScript and calls `GonzoRecall` directly, so eligibility,
shortlisting and scoring are the runtime's own code rather than a
reimplementation that could quietly disagree with it.

## Callback definition — unchanged

Provenance valid, engages with the excerpt, contains novel language beyond it,
not a verbatim repetition. Identical to EXPERIMENT_RECALL and
EXPERIMENT_DISTANCE.

## The decision, frozen now

The question is not "is there a difference" but **"does resonance earn ~120
lines of machinery"**. These margins are a minimum practical payoff, not
significance thresholds.

**KEEP resonance** only if all hold:
* R − D conversion **>= 8 percentage points**;
* the improvement appears in a clear majority of paired batches;
* unsupported attribution remains **0**;
* repetition and fixation do not materially worsen.

**DELETE resonance** if:
* |R − D| **<= 5 percentage points** across the completed experiment;
* and no secondary guard gives resonance a clear product advantage.

**INCONCLUSIVE** between 5 and 8 points — in which case it stays, and this
question is closed without another experiment.

## What is already decided, whatever this returns

The memory core has earned its place independently. Across ~400 injections:
long-range canonical material resurfaces, models integrate it non-verbatim at
69–76%, source distance sits well outside the working window, recall does not
reinforce itself, recall does not reset its own decay, corrupted provenance
fails closed, and **unsupported attribution has never once been non-zero**.

What is undecided is only whether

```
old truth + provenance + decay + scarcity + cooldown + distance
```

needs

```
+ four-dimensional resonance ranking
```

## Not part of the decision

The incidental near-duplicate result (4.6% for distance against 10% for
resonance) is unplanned and stays out of this decision. Judge scores likewise.


---

# Result: resonance deleted.

**127 paired opportunities**, past the pre-registered 100+ target. 12 skipped
because both rules chose the same scar.

| policy | callback conversion | mean source distance |
|---|---:|---:|
| **distance** | **69.3%** | 35.7 |
| resonance | 65.4% | 28.7 |

**R − D = −3.9 points.** Unsupported attribution: **0**. R won 1 of 4 batches.

|R − D| <= 5 and no secondary guard favoured resonance, so the frozen rule
returns **DELETE**.

## The trajectory is the lesson

```
 40 pairs   R - D = +5.0
 81 pairs   R - D = +7.4
127 pairs   R - D = -3.9
```

At 40 the rule would have said delete, at 81 inconclusive, at 127 delete again
— and the sign flipped along the way. Any of those could have been reported as
the answer. The only reason this landed anywhere defensible is that the sample
target was fixed in advance; stopping when the number looked interesting would
have produced a different architecture on identical evidence.

## What was deleted

`resonance()`, `weighted_resonance()`, the four dimensions, their weights, and
the scoring path. Roughly 120 lines.

## What remains

```
old truth + provenance + decay + scarcity + cooldown + distance
```

A memory returns because it survived decay, fell out of the working context,
and is still eligible. Whether it matters is the model's problem, not the
scorer's — which is both simpler and closer to the layered-persistence idea
than a similarity engine was.

## Unchanged by this

The memory core stands on ~530 injections across three experiments: 65–76%
non-verbatim callback conversion, source distance well outside the working
window, and **not one unsupported attribution, ever**.
