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

---

# Amendment: three things fixed before any data exists

**Written and committed before a single allocation has been recorded.** No
outcome exists, so nothing here can be a reaction to one. Bars, conditions,
metrics and N are untouched.

## 1. Tiebreaking by name is semantic, and it favoured one model family

The resolver's first version broke ties lexicographically on `agent_id`. That
looked like the neutral choice and is not one. This corpus's roster is

```
  Gemma 3 1B   H 2o Danube 3 4B #1/#2   Stablelm 2 Zephyr #1/#2
```

so `Gemma` wins **every tie, forever**, on the strength of how its model family
is spelled. Ordering by name is ordering by something that means something, and
with fairness assistance switched off a permanently favoured tie-winner would
inflate measured concentration as an artifact of the resolver rather than a
property of the bids — the metric would be reporting my sort order back to me.

Ties now break on FNV-1a of the agent id, salted from the bid multiset itself,
so no additional field crosses the boundary to obtain it. The salt sums
**quantized** bids because integer addition is associative and float addition is
not, and an order-dependent salt would reintroduce the exact bug being removed.

Guarded by a self-test that sweeps 40 salts and requires both tied agents to win
at least once. Shown to fail: restoring the lexicographic comparison returns
40/0.

## 2. The bid's components never cross individually, including for debugging

`swarm_bid.gd` computes `compute(local_view) -> float` from an agent's own view
and returns one number. The components — starvation, being named, airtime — stay
on the agent side.

**Not even a `bid_reason` field for debugging.** A debug field is how semantic
authority crawls back in wearing a reflective vest, and the resolver refuses
unknown keys specifically so it cannot be added quietly.

The bid is pure and total. Pure because the paired frozen-state design compares
two schedulers at one moment and a bid that drifts between calls destroys the
pairing. Total because a malformed view returns NAN — meaning *do not bid* —
rather than a plausible default, since a defaulted bid is a silent failure
wearing the shape of a decision. A zero bid is a real local statement ("I am
here and I do not want the slot"); a malformed view says nothing at all, and the
two must not be confused.

A self-test asserts that a fully starved agent and a freshly-addressed one both
arrive at exactly 0.50 for unrelated reasons. **The substrate cannot recover
which.** That is the architecture written as an assertion rather than a comment.

## 3. What a high agreement rate with round-robin would mean

Fixed now, because after the number exists it would be arguable either way.

Agreement between the cage's pick and the swarm's pick is already a reported
quantity. Its interpretation:

> **A swarm that agrees with round-robin 95% of the time has not bought
> autonomy, even if every viability bar passes.** It would be a more expensive
> way to compute a modulo.

This does **not** become a bar, and divergence is not a target. A bar on
disagreement would reward gratuitous difference, and a scheduler optimised to
differ from round-robin is no more sovereign than one optimised to match it —
both are defined by the cage. It is recorded as an interpretive commitment: high
agreement means the experiment succeeded mechanically and bought little, and
that reading is fixed in advance rather than negotiated afterwards.

---

# Amendment: the viability bar could not fail, and now can

**Written before any allocation has been recorded.** Found while building the
walk harness, not while looking at results — there are none.

## The defect

As originally frozen, SWARM-V's bar was "a runnable, eligible speaker in >= 95%
of allocation opportunities". Both failure families were **identically zero by
construction**:

* **Common substrate failures.** The walk only *proposes* a speaker against real
  history. Nothing is executed, no model is loaded, no request is issued — so
  unavailable model, load/swap failure, stall watchdog and request failure
  cannot occur in either condition. Round-robin's null on this family would have
  returned 0, and so would the swarm's. **This family is not measurable in a
  proposal-only design and is deferred to SWARM-B**, where allocations run.
* **Swarm autonomy failures.** `compute()` returned a number in [0,1] for every
  well-formed view, so every agent always submitted, so `NO_BIDS` could never
  fire and someone was always eligible. The swarm would have produced a valid
  winner 100% of the time.

400 opportunities would have been spent confirming that a modulo cannot fail.
**A test that can only pass is not evidence** — rule 1, violated by the bar
rather than by a test, which is a way it had not failed here before.

## The repair: abstention

An agent whose bid falls below a floor **submits nothing**. That is a real local
decision and a more swarm-like one than compulsory participation: an agent that
does not want the slot says so by silence, and the substrate has to survive an
arena where everyone is satisfied.

`ABSTAIN_BELOW = 0.10`, frozen from arithmetic before any run. In a five-agent
rotation at fair airtime the bids are

```
  turns silent   0      1      2      3      4
  bid            0.000  0.062  0.125  0.188  0.250
```

so a floor of 0.10 leaves **three of five agents competing**. Failure is
reachable without being the default. At 0.20 only one agent ever bids, which is
round-robin with extra steps; at 0.05 only the agent who just spoke abstains and
`NO_BIDS` stays unreachable.

Both endpoints are asserted in the self-test so the threshold cannot drift into
either degenerate regime unnoticed.

## What SWARM-V now concludes

The bar is unchanged at **>= 95% valid allocations, N = 400**, and it can now
fail: a corpus where agents are frequently satisfied at the same moment
produces `NO_BIDS`, and no referee rescues it because fairness assistance is
off.

The two failure families remain unsummed. Family 1 is now explicitly **out of
scope for SWARM-V** rather than measured-and-zero, which is the honest
description of a quantity the design cannot observe.

---

# Result: SWARM-V is VIABLE at 400, and bought almost nothing

```
  VIABILITY (the only bar)
    valid allocation rate      100.0%      bar 95.0%

  SWARM AUTONOMY FAILURES
    NO_BIDS              0.0%
    NO_ELIGIBLE_BIDS     0.0%
    MALFORMED_BID        0.0%

  BEHAVIOURAL DIVERGENCE FROM ROUND-ROBIN (not quality)
    swarm agrees with cage      85.8%
    RANDOM agrees with cage     35.0%     <- placebo floor

  COUNTERFACTUAL SELECTION CONCENTRATION (top share of 20)
    cage 20.0%    swarm 30.4%    random 30.4%   <- placebo floor

  COUNTERFACTUAL PROPOSAL DROUGHT (longest unproposed run)
    cage 4        swarm 44       random 14

  PER-AGENT ANATOMY
    agent                     seen  bids  abst  wins  mean bid
    Stablelm 2 Zephyr #1       400   350    50   111     0.410
    Stablelm 2 Zephyr #2       400   357    43    72     0.418
    H 2o Danube 3 4B #1        400   400     0    99     0.425
    H 2o Danube 3 4B #2        400   400     0    80     0.425
    Gemma 3 1B                 400   300   100    38     0.304
```

The walk is deterministic: two independent runs produced byte-identical
results, so nothing below is protocol noise.

**VIABLE.** Local bidding allocated the slot unassisted in 100% of 400
opportunities, with no fairness machinery of any kind. The bar is met and the
frozen rule says nothing else can change that.

Everything else here is reported, and every one of the reported numbers is bad.

## The swarm is mostly a soft round-robin

85.8% agreement with the cage, against a placebo floor of 35.0%. The
pre-registered interpretation, fixed before the number existed, says exactly
what to do with that:

> a swarm agreeing with round-robin 95% of the time has not bought autonomy,
> even if every viability bar passes

85.8% is not 95%, so this is not the degenerate case. It is close to it. Local
bidding purchased **14.2 points of divergence** over the scheduler it replaces.

The mechanism is not mysterious and is my fault. `W_STARVATION = 0.5` makes
`turns_since_spoke` the dominant term, and in a transcript generated by a
rotating scheduler the agent with the longest silence is *by construction* the
agent round-robin is about to pick. **The bid function encodes the cage.** It
was chosen to be boring and it turned out to be boring in the specific way that
reproduces what it was meant to be an alternative to.

## Concentration shows zero lift over the placebo

```
  swarm 30.4%     random 30.4%
```

Identical. Whatever makes the swarm's proposals more concentrated than
round-robin's 20.0%, it is **not local information** — bids carrying no
information at all concentrate exactly as much. This is rule 4 doing its job: a
number that looked like a finding about local policy is a property of any
non-uniform selection over five agents, and without the placebo arm it would
have been written up as a swarm characteristic.

## The drought is worse than noise

```
  cage 4     swarm 44     random 14
```

One agent goes 44 opportunities without being proposed, three times worse than
random selection manages. The anatomy names it: `Gemma 3 1B` abstains 100 times
of 400, carries the lowest mean bid at 0.304, and wins 38 against 72-111 for
everyone else.

That is a real pathology and it is the one the experiment was built to expose.
Fairness assistance is off precisely so this is visible rather than corrected
into invisibility by a referee. **Raw local bidding, with no anti-monopoly
machinery, starves a participant worse than chance does.**

## The confound that limits all of this

The replayed history was produced by the cage. A starvation-weighted bid will
track round-robin on round-robin-generated states almost by definition, so
SWARM-V **cannot distinguish**:

* the local policy is a soft round-robin, from
* on cage-generated states, any sensible local policy resembles round-robin.

Both predict 85.8%. Separating them requires states the swarm itself produced,
which is SWARM-B, and the pre-registration already forbids pooling that data
with this.

## Standing consequence

v0.1 is **viable and unconvincing**. It allocates, it does not fabricate, it
survives an unassisted arena — and it buys 14 points of divergence while
concentrating no better than noise and starving one agent worse than noise.

Nothing is deleted. The resolver, the locality invariant, the import lint, the
abstention rule and the failure taxonomy are all infrastructure and all stay.
What has not been earned is any claim that local bidding is *better*, and none
is made.

The next question is not "tune the weights until divergence rises". A bid
function tuned to disagree with round-robin is as cage-defined as one that
agrees, which the amendment above already settled. The next question is whether
divergence changes anything once it can compound — and that is SWARM-B.
