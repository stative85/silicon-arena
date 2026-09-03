# Pre-registration: can locally-informed agents allocate the speaking slot?

**Written before any swarm code exists.** No bid function, no resolver, no
implementation of any kind is in the tree at this commit.

## The question, narrowed until it can lose

Not "does a swarm make better debates". Not "is emergence real". This:

> **Can agents that each see only their own local state allocate one scarce
> execution slot, without the arena understanding why any of them wants it?**

Viability first. Behaviour later. Quality last. Those are three different
experiments and merging them is how a mechanically successful scheduler gets
killed by a noisy engagement metric before anyone understands what it does.

## What is NOT in v0.1

Named explicitly, because every one of these is a live temptation:

* **No stigmergic traces.** Local bidding must prove it can allocate at all
  before agents start coupling to each other. If traces ship in the same
  version and the thing works, nobody can say whether locality or stigmergy
  earned it.
* **No conflict pressure of any kind.** The conflict axis is closed
  ([CONTRIBUTING](../CONTRIBUTING.md) rule 3, four rejections). "Unresolved
  claim pressure" and "coalition pressure" are that axis wearing different
  words and they do not enter through a side door.
* **No memory coupling.** Gonzo recall's authority question came back
  INCONCLUSIVE twice ([EXPERIMENT_SOURCE](EXPERIMENT_SOURCE.md)). Wiring scars
  into bids would make the swarm's result depend on a mechanism whose own
  effect is unresolved.
* **No fairness assistance in the first condition.** See below — this is the
  one most likely to be added "just to be safe" and it would invalidate the
  entire measurement.
* **No dialogue-quality metric.** Not judged, not scored, not reported.

## The distinction this experiment exists to test

A centralized scorer over a global agent-feature table is **not** a swarm:

```
  LOAD BALANCER                        SWARM
  arena holds every agent's state      agent holds its own state
  arena computes the reasons           agent computes its own bid
  arena selects                        arena compares scalars and arbitrates
  cage_weight = 0 changes nothing      the arena cannot reconstruct why
```

Setting a weight to zero on a central scorer starves nothing — the centralized
scheduler is still at full strength, with different arithmetic. **Starving the
cage means removing semantic knowledge from the centralized controller**, not
lowering a coefficient. The arena's *view* shrinks.

## Information locality is a code invariant, not an intention

The resolver's entire input is:

```
  resolve([{agent_id, eligible, bid}, ...]) -> agent_id
```

Enforced twice, and both are part of `verify.cmd`:

1. **A self-test** that fails if any semantic field appears in the resolver's
   input — `reason`, `target`, `trace`, `speaker`, `text`, `turn`, `scar`,
   anything but the three keys above. Shown to fail by adding one back, per
   rule 1.
2. **An import lint** that fails if the resolver's source file imports
   `live_match`, `gonzo_recall`, transcript loading, or any module carrying
   history, scars, turn text or addressing state.

Without both, the first person needing a tiebreak reaches for `direct_address`
and the central brain is back within a month. The invariant is the experiment;
if it can be quietly violated there is nothing to measure.

## What the arena is still allowed to know

Scarce hardware is physically centralized whether the design likes it or not.

```
  ALLOWED                          FORBIDDEN
  which agents exist               "Gemma was insulted"
  whether a model is runnable      "Qwen has the strongest counterargument"
  the 7B policy                    "Agent C needs more attention"
  one execution slot at a time     "this disagreement deserves escalation"
  which bids arrived
  canonical turn ordering
  invalid or stale bid rejection
```

The line is resources and validity on one side, meaning on the other.

---

# SWARM-V: frozen-state paired allocation

## Design

Stochastic selection makes trajectories diverge after one turn, and every
result this project trusts came from paired counterfactuals at frozen moments —
127 pairs, 182 opportunities, 144, 240. Pairing is not a nicety here, it is the
reason anything is believed.

So v0.1 uses **deterministic argmax**, and the state never advances:

```
  for each turn i of a real transcript:
      history  = the real turns 0..i-1        (identical for both conditions)
      S0 CAGE  proposes a speaker by round-robin
      S1 SWARM proposes a speaker by local bids
      record both proposals. Advance to the real turn i+1, not to either
      proposal.
```

Both schedulers walk the same real trajectory and propose at every step. The
proposals form a sequence, so concentration and starvation are measurable
across a match, while the context distribution stays fixed and identical.

**This is not the counterfactual trajectory the swarm would have produced.** It
measures allocation behaviour under a fixed context distribution, which is
exactly what viability means and deliberately not what emergence means.
Trajectory divergence belongs to SWARM-B and its data may never be pooled with
this.

## The bid, kept boring on purpose

Each agent computes, from its own view only:

```
  bid = f(turns since I last spoke,
          whether I was named in what I can observe,
          how much airtime I have had)
```

Same function for every agent in v0.1 — what is local is the **information**,
not the policy. Per-agent policies are a later question and adding them now
would confound "locality helps" with "heterogeneity helps".

An agent may return no bid. That is a legitimate local decision and the
substrate must survive it.

## Metrics, in two families that are never summed

Rule 4 and the asymmetric-floor problem: round-robin **cannot** produce
`NO_BIDS` — it is a modulo. Comparing a combined failure rate would guarantee
the swarm loses before it starts, the same structural bias that let a placebo
"call back" 91.3% of the time.

**Family 1 — COMMON SUBSTRATE FAILURES / 100 turns.** Both conditions can
incur these:

```
  unavailable model      load or swap failure     stall watchdog
  invalid execution      turn-order violation     request failure
```

**Round-robin's own rate on these is measured FIRST, as the null**, before any
swarm bar exists. Rule 2.

**Family 2 — SWARM AUTONOMY FAILURES / 100 allocation opportunities.** Only the
swarm can incur these, and they are not "worse than cage" — they answer a
question the cage cannot be asked:

```
  NO_BIDS            NO_ELIGIBLE_BIDS      malformed bid
  stale bid          all bids expired
```

**Reported, never summed into a score:** allocation concentration (top-agent
share over a 20-proposal window), longest gap any agent goes unproposed,
agreement rate with the cage's proposal.

## Fairness assistance is OFF, and that is the point

The first swarm condition runs with **no** anti-monopoly machinery:

```
  OFF: max consecutive wins        minimum airtime guarantee
       dominance correction        bid cooldown for fairness
       forced starvation rescue
```

Those guards enforce precisely the fairness the swarm is supposed to
demonstrate. With them live, the referee supplies the property and the
measurement says nothing. Whatever concentration raw local bidding produces is
the finding, however ugly.

A separate later condition, **SWARM+TEETH**, turns them on and asks a different
product question: if raw bidding develops monopoly pathologies, can minimal
substrate safety bound them without becoming semantic government again. It is
not part of this pre-registration and its result may not be pooled with this
one.

## Conditions: five, fixed, no ratchet

```
  1.00 cage / 0.00 swarm      0.50 / 0.50      0.00 / 1.00
  0.75 / 0.25                 0.25 / 0.75
```

**Fixed N at every step. No "looks healthy, advance."** An adaptive ratchet
that advances whenever guards stay green will advance on noise: this project
measured its own guard floors and they are large — challenge slope 2sd = 20.3,
`commit` unusable at 48.6. A ratchet driven by those steps on a quiet run and
never steps back.

## Target and bars

**N = 400 allocation opportunities per condition**, fixed now. Ten transcripts
at roughly 45 usable turns each, matching the corpus rates measured for MP2.

One hard bar, because this is a viability study and viability is binary:

```
  VIABLE       swarm produces a runnable, eligible speaker in >= 95% of
               allocation opportunities, with fairness assistance OFF,
               at 0.00 cage / 1.00 swarm.
  NOT VIABLE   < 95%. Local bidding cannot carry the slot unassisted, and
               v0.1 is rejected rather than patched with referee help.
```

Everything else — concentration, longest gap, agreement with cage, the common
substrate rates — is **reported and cannot change the verdict.** A viability
experiment that also judges fairness is two experiments, and the second one
would eat the first.

## Anti-Goodhart

* The bid function, the resolver interface, the failure taxonomy and N are
  frozen at this commit. If any needs changing, that is the result.
* **The harness refuses to print rates before N**, as in the source probe, with
  no override flag. Four experiments on this project told different stories
  early and late.
* The label-scramble discipline from MP2 carries over in its corrected form:
  bias in the null is brokenness, spread is not, and any bound is set from a
  measured null rather than chosen.
* Round-robin's common-failure null is measured **before** any swarm run.

## What losing means

Not deletion. If v0.1 is not viable, local bidding has not earned the slot and
round-robin keeps it — while bids, the resolver, the locality invariant and the
failure taxonomy stay in the tree as infrastructure, exactly as canonical
storage and provenance stayed when recall's authority went unresolved.

The cage does not break. It becomes dormant infrastructure, or it does not, and
this is the measurement that decides which.
