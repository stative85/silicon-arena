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
