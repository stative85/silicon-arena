# Pre-registration: does locality matter once its choices compound?

**Written before any SWARM-B code exists and before any match has been run.**

## What SWARM-V could not answer

SWARM-V ([EXPERIMENT_SWARM](EXPERIMENT_SWARM.md)) replayed cage-generated
history and asked both schedulers to propose. Nothing advanced from either
proposal, which preserved pairing and capped the scope hard:

```
  VIABLE        100% valid allocation, unassisted
  agreement     85.8% with round-robin, against a 35.0% random floor
  concentration 30.4% swarm, 30.4% random -- zero lift over placebo
  drought       44 swarm, 14 random, 4 cage
```

It could not separate *"the local policy is a soft round-robin"* from *"on
cage-generated states any sensible local policy resembles round-robin"*. Both
predict 85.8%.

> **Once swarm choices generate the states that produce the next bids, does
> locality create dynamics different from both the cage and a
> locality-destroyed placebo?**

## Three arms

```
  CAGE          round-robin over the roster
  SWARM         real local bids
  SHAM-SWARM    the same bids, with the agent-to-bid mapping destroyed
```

**SHAM-SWARM is the point of this design.** Random bids were the right placebo
for SWARM-V and are too weak here: they change the bid distribution, the
abstention rate and the number of competitors all at once, so a difference could
come from any of them. The sham instead:

```
  every agent computes its real local bid
  among the ELIGIBLE agents, the (submits, bid) tuples are permuted
  the blind resolver proceeds unchanged
```

Preserved exactly: bid distribution, abstention count, number of competitors,
resolver behaviour. Destroyed: *this bid came from this agent's local state.*

Permuted among eligible agents only, so the eligible-bidder count matches the
real arm exactly rather than approximately. The permutation is a deterministic
function of `(match_seed, turn_index)` and never of the arm's own trajectory.

## The randomness problem, and why the obvious fix is unavailable

Once trajectories diverge, a scheduler can manufacture a fake treatment effect
purely by changing **which model receives which random draws**. If one arm makes
an agent speak earlier and that consumes the next draw from a global stream,
every later generation differs for reasons unrelated to scheduling.

The correct fix is per-agent deterministic streams keyed by
`hash(match_seed, agent_id, agent_local_speech_index)` rather than a global
generation counter, so an agent's third reply draws the same stream whether it
happens on turn 8 or turn 23.

**That fix cannot be implemented on this stack.** Measured during MP2, on this
LM Studio build with `h2o-danube3-4b-chat`: two identical requests at
`temperature 0.8` carrying the same `seed` return different text. The server
does not honour seeds, so there is no stream to key.

**Resolution: SWARM-B runs at temperature 0.** Greedy decoding is deterministic
byte-for-byte, measured, which removes the stochastic stream entirely rather
than trying to partition it. A reply becomes a pure function of its prompt, so
the only way an arm can differ is by producing different prompts — which is
exactly the treatment.

The cost is declared. MP2 showed temperature 0 changes reply *character*:
copying nearly doubles and source uptake becomes transcription rather than use.
SWARM-B's primary measurements are mechanical — who speaks, who bids, how long
anyone waits — and none of them depend on reply quality. **No dialogue-quality
claim may be made from a temperature-0 run.**

A temperature-0.8 arm is run afterwards as a **reported-only robustness check**,
carrying an explicit note that the RNG confound above is live in it and that it
cannot support a causal claim.

## Pairing dies here, and what replaces it

Every trusted result on this project came from paired counterfactuals at frozen
moments. After the first divergent allocation there is no shared moment left, so
pairing is gone and cannot be faked.

What replaces it is **distributions over N independent matches**, with
SHAM-SWARM rather than the cage as the comparison. The cage is context; the sham
is the control, because it differs from the swarm in exactly one property.

## Measurements, mechanical and separated by kind

**Primary, per match:**

```
  longest actual silence      max consecutive turns an agent does not speak
  speaker share Gini          concentration of who actually spoke
  bid participation rate      submissions / opportunities
  voluntary abstention rate   below-floor, a local decision
```

**Two failure kinds that must never be summed**, because they are different
pathologies:

```
  LOCAL-POLICY BEHAVIOUR      an agent declines to bid for k turns
                              -> reported. Not a failure. It is the policy.

  SWARM-SYSTEM FAILURE        no eligible bid exists and the match cannot
                              advance -> the fallback wakes. THIS is the cage
                              dependence number.
```

An agent choosing silence for thirty turns is behaviour. Nobody bidding at all
is the system failing. SWARM-V could not tell these apart because neither ever
occurred.

**Substrate failures** — unavailable model, load/swap failure, stall watchdog,
request failure — are measurable here for the first time, since allocations
actually execute. Round-robin's rate is the null and is measured first.

**Secondary, reported, cannot change the verdict:** anything about what was
said.

## Bars, with the floor measured before they are fixed

Rule 2 forbids a threshold on a statistic whose spread has not been measured,
and this project has now been bitten by that twice, once by a guard written to
enforce it. So the **procedure** is frozen here and the number is derived from a
measurement taken before any treatment outcome is read:

1. Run **SHAM vs SHAM** across N matches with different permutation seeds.
   The spread of `longest actual silence` across those runs is the noise floor.
2. The bar is **3x that measured floor**, and the multiplier is what is frozen
   now.

**PRIMARY:** `| median longest-silence(SWARM) - median longest-silence(SHAM) |`

```
  >= 3x floor    LOCALITY PRODUCES DIFFERENT DYNAMICS
  <  1x floor    LOCALITY PRODUCES NO DYNAMICAL DIFFERENCE
                 v0.1 local bidding is decoration; the resolver and the
                 invariant stay, the bid policy loses its justification
  between        INCONCLUSIVE, and the sample is not extended
```

**Direction is not part of the bar.** If the swarm starves agents worse than the
sham, locality still mattered. Whether it mattered *usefully* is a later and
separate question, and collapsing the two is how a mechanically real effect gets
killed by a quality metric nobody validated.

## N

**20 match-triples**, fixed now. Each triple is one match seed run under all
three arms, roughly 60 turns each, so about 3,600 generations. At the rate
measured during MP2 that is several hours and it runs once.

## Anti-Goodhart

* The bid function is **frozen as it stands, including `W_STARVATION = 0.5`**.
  SWARM-V showed that weight reconstructs round-robin, and the temptation is to
  retune it. A bid tuned to disagree with the cage is as cage-defined as one
  tuned to agree — same reference, opposite sign. Retuning is a different
  experiment with its own pre-registration.
* The harness **refuses to print rates before N**, no override flag.
* The sham permutation seed is fixed in advance and never chosen for its result.
* Temperature-0.8 results are reported and can never change a verdict.
* SWARM-V's data may not be pooled with this. Different design, different scope.

## What losing means

If locality produces no dynamical difference, the bid policy loses its
justification and nothing else does. The resolver, the locality invariant, the
import lint, abstention and the failure taxonomy are infrastructure, and they
stay exactly as canonical storage and provenance stayed when recall's authority
went unresolved twice.

The cage does not break. It stays available as the fallback, and the number that
decides whether it is still needed is how often it has to wake.

---

# Amendment: the derangement, the zero-floor hole, and the temp-0 scope

**Written before the sham floor was measured and before any match has been run.**
No outcome of any kind exists. This is instrument repair.

## 1. The sham must be a derangement, not a permutation

A permutation can have fixed points. With five agents, a meaningful share of
opportunities would hand at least one agent **its own** tuple back, preserving
exactly the locality the control exists to destroy. The placebo would be
contaminated with treatment, in proportion to how often that happens, and
nothing in the output would say so.

Whenever two or more eligible agents are present, the sham applies a
**derangement**: no eligible agent may receive its own `(submits, bid)` tuple.
With exactly one eligible agent no derangement exists, and that opportunity is
recorded as `SHAM_UNDERANGEABLE` and excluded from the sham arm rather than
silently passed through unshuffled.

## 2. `3x floor` collapses when the floor is zero

The frozen text said the bar is three times the measured sham-vs-sham floor.
That has a hole with a familiar shape:

```
  measured floor = 0   ->   bar = 3 x 0 = 0   ->   any difference clears it
```

Every mechanism in SWARM-B is deterministic — greedy decoding, argmax
arbitration, seeded derangements — so an exact-zero null is **more** plausible
here than in a sampled experiment, not less. A bar that cannot fail is not
evidence, and this project has already voided one run over a threshold set
against a null it had not characterised.

**The floor is a distribution, and the bar has an absolute minimum:**

1. Run sham against sham across **at least 10 frozen permutation seeds**.
2. Take every pairwise `|difference|` in median longest-silence between those
   runs. That set is the null.
3. `bar = max(3 x p90(null), 3 turns)`

The 3-turn minimum is a practical margin, not a statistical one: a five-agent
roster rotates in five turns, so a difference under three turns is less than one
rotation and is not a dynamical difference worth shipping a subsystem for. It is
fixed now, before the null exists, precisely so it cannot be chosen once the
null is known.

## 3. A degenerate sham null VOIDS the run

If sham-vs-sham produces **zero spread** across ten different derangement seeds,
the control is not perturbing the system at all. That is not a tight floor, it
is a broken placebo — the permutation would be failing to change anything it was
built to change, and comparing the treatment against it would be meaningless.

```
  p90(null) == 0 and max(null) == 0   ->   RUN IS VOID, the sham is not a control
```

Rule 6: a positive control must be able to detect its own failure. This is the
same requirement applied to a negative one, and MP2-A is why it is here — that
gate could not tell "the measure is blind" from "the ceiling never rose", and it
cost a full run to find out.

## 4. What temperature 0 does and does not buy

Greedy decoding removes the stochastic stream, so no arm can differ because the
scheduler reallocated random draws. That confound is closed.

It does not make this a measurement of the deployed arena, and the reason is
sharper than "different regime": **reply content feeds the bid path.**
`named_recently` is computed by reading what other agents said. If greedy
decoding changes how often agents address each other by name — and MP2 showed
greedy decoding changes reply character substantially — then bids and
abstentions change with it.

That is legitimate treatment propagation, and it propagates *through the
temperature-0 system*. So the result reads:

> **SWARM-B is a causal test of scheduling dynamics under deterministic
> decoding.** It is not a direct measurement of the live 0.8 arena, and this
> qualification travels with every number it produces, mechanical ones included.

The 0.8 arm can show whether the qualitative dynamics survive in the deployed
regime. It cannot carry the causal attribution, because the confound this
amendment closes is live in it.
