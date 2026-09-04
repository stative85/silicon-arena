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

---

# Amendment: protocol integrity, what the null actually is, and the budget

**Before the harness runs anything.** No match, no floor, no treatment.

## 1. End-to-end determinism is checked before the null is interpreted

Temperature 0 was measured deterministic during MP2, but SWARM-B adds bid
generation, derangement, arbitration, state advancement and history updates on
top of it. Determinism of the decoder is not determinism of the harness.

So, before any null is read: **run one identical `(arm, match_seed, sham_seed)`
twice and require byte-identical mechanical output** — the same speaker
sequence, the same bids and abstentions, the same failure codes, the same
transcript checksum.

This is **not a decision gate and has no bar**. It is a protocol integrity
check. If it fails, the run stops and nothing downstream is interpreted,
because a null measured on a non-reproducible harness is measuring the harness.

## 2. What the sham null is, named precisely

It is **not sampling noise.** Temperature 0 removed decoding randomness
entirely, so nothing here fluctuates the way a sampled experiment does.

> The sham null is **trajectory variance caused solely by destroying the mapping
> between local state and agent identity in different valid ways.**

Ten derangements are ten equally legitimate ways to break locality, and they
produce different histories, which produce different local views, which produce
different bids. That divergence is the null. Writing "null spread" without this
sentence invites a later reader to assume sampling noise and reason about it
wrongly, which is how the +7.6 verbatim gap nearly became an effect size.

## 3. The frozen N does not fit the machine, and the fix errs strict

The original N — 20 match-triples at roughly 60 turns — is about 3,600
generations. The null on top of it, at 10 seeds by 20 matches, is 12,000 more.
At the throughput measured during MP2 that is over a day of continuous
generation for one experiment, and it would run once with no room to repeat it.

Revised, before any data:

```
  match length        30 turns    (a five-agent roster rotates in five)
  sham null           10 derangement seeds x 5 matches   = 1,500 generations
  treatment           20 match-triples x 3 arms          = 1,800 generations
                                                    total ~3,300, ~8 hours
```

**The null is deliberately the under-powered half, and that direction is
safe.** Fewer matches per sham seed makes each seed's median longest-silence
noisier, which *widens* the pairwise-difference distribution, which *raises*
`p90(null)`, which makes the bar **harder** to clear. An under-powered null
costs the treatment the benefit of the doubt rather than granting it.

Recorded because the reverse would not be acceptable, and because "we shortened
it for time" is exactly the kind of quiet change that later looks like tuning if
it is not written down before the numbers exist.

---

# Correction: temperature 0 does NOT close the confound

**Found by the protocol integrity check, before any null was measured and before
any treatment ran.** The check failed on its first execution and again after two
repairs, which is the entire reason it exists.

## What was claimed, and why it was wrong

The pre-registration said greedy decoding removes the stochastic stream, so an
arm can only differ by producing different prompts. That rested on an MP2
measurement: two identical requests at temperature 0 returned identical text.

Two calls on a short prompt was not enough evidence for a 3,300-generation
experiment.

## What is actually true, measured

```
  ten consecutive identical requests, warm      1 unique hash out of 10
  novel prompt, after 20 intervening requests   identical, 4 of 4
  first inference after a cold model load       DIFFERS from every warm one
  same prompt, same preceding request type,
    sampled four times across a longer session  f0dbb4c3, f0dbb4c3,
                                                a3f046b3, a3f046b3
```

That last line is the finding. The output changed **partway through the
sequence**, not according to what preceded it — two stable values, each
repeated, with a boundary between them. It is not prompt-cache reuse: a
prefix-sharing predecessor and an unrelated one produced the same answer as each
other, both before and after the change.

> **Temperature 0 on this stack is deterministic in bursts and drifts across
> longer request sequences.** Greedy decoding removes sampling. It does not make
> a 30-turn match reproducible.

Two other defects were found on the way and are fixed: the first inference after
a cold load is never reproducible (every recorded turn now runs behind a
discarded warm-up generation), and a timed-out request left its one-shot handler
connected so it could fire during the next call and deliver the previous body —
that one was mine, and removing it made speaker sequences identical across all
three arms.

## What this does to the design

**Byte-identical transcripts are not achievable here, at any temperature.** The
integrity check cannot require them and will not be relaxed into pretending
otherwise. It now requires what the experiment actually depends on:

```
  REQUIRED across 3 repeats per arm    identical speaker sequence
                                       identical failure codes and counts
  MEASURED AND REPORTED                text divergence rate
                                       bid-flip rate under that drift
```

`bid-flip rate` is new and it is the number that matters: how often the text
drift changes which agent the resolver selects. Drift that never flips a bid is
noise in the prose; drift that flips bids is noise in the treatment.

## The confound is not closed, and the null is why it survives anyway

The honest statement is that drift is an uncontrolled source of variation and
SWARM-B cannot claim a clean causal attribution on the strength of temperature 0.

What rescues the comparison is the control, not the decoder. **The sham-vs-sham
null is measured by re-running the same machinery under the same drift**, so
drift-induced trajectory variance is *inside* `p90(null)` rather than confounding
the treatment against it. The bar is three times that floor, which now includes
the drift it was previously assumed to have eliminated.

So the design survives — for a different reason than the one written down, and
the original reason was wrong. A larger null is the price, and an
under-powered null already errs strict, so both errors point the same safe way.

If the bid-flip rate turns out to be substantial, that reasoning fails too, and
SWARM-B needs a different instrument rather than a wider bar. That is measured
next, before the null.

## What 0/60 bid flips does and does not establish

Recorded before the null returned, so it cannot be shaped by the result.

The integrity check found zero bid flips in 60 comparisons per arm, 180 in
total, across cage, swarm and sham. Text drifted in all three; no selection
changed.

**What it supports:** over a 30-turn horizon on one match seed, decoder drift did
not alter which agent the resolver selected — in the sham arm *and in the real
swarm arm*. The second half matters. If only the sham had been checked, the null
would measure drift under deranged dynamics while the treatment ran under
different ones, and any interaction between locality and drift would be
invisible to the comparison. Repeating the actual SWARM arm is what makes the
null's coverage of drift defensible rather than assumed.

**What it does not support:** any claim that decoder drift *cannot* affect
locality. It is 180 comparisons on a single match seed over 30 turns. The true
bid-flip rate could be small and nonzero, and a longer horizon or a different
seed could expose an interaction this check has no power to see.

The correct sentence is the narrow one:

> Over the tested horizon, drift-locality interaction was not detectable, and
> the sham null therefore absorbs drift for comparisons of this length.

Not:

> Decoder drift cannot affect locality.

If SWARM-B's treatment produces a difference near its bar, this caveat is the
first thing that should be attacked, because a small undetected flip rate is
exactly the size of error that would matter there.

---

# Result: the sham null is non-degenerate, and the bar it produces is brutal

```
  10 derangement seeds x 5 matches, 30 turns each, temperature 0

  per-seed median longest silence
    [13, 10, 11, 10, 12, 10, 11, 10, 8, 13]

  pairwise |difference|:  p90 3.00   max 5.00

  bar = max(3 x p90, 3) = 9.00 turns
```

**THE CONTROL IS ALIVE.** Ten different ways of destroying the local-state to
identity mapping produce ten different trajectories, spanning medians of 8 to
13. The derangement is perturbing what it was built to perturb, so the VOID
condition does not fire and the treatment has something to be measured against.

That was a real risk. Every mechanism here is deterministic, and a zero-spread
null would have killed SWARM-B at the control stage before a single treatment
match ran.

## What this bar means, said before the treatment runs

The frozen procedure produced **9.00 turns**, and it is not moving. But its
scale should be recorded honestly while it still costs nothing to admit:

```
  observed sham medians span     8 to 13 turns
  the bar demands a difference   >= 9 turns
```

**The bar is roughly twice the entire observed spread of the null.** In a
30-turn match with five agents, a median longest-silence difference of 9 turns
is close to the largest effect the statistic can express.

So SWARM-B, as frozen, can only detect a very large dynamical difference.
Therefore:

> **A "no dynamical difference" verdict from this experiment is weak evidence of
> absence.** A moderate real effect — three or four turns, which would be
> genuinely interesting — produces exactly the same verdict as no effect at all.

This is the pre-registered consequence of an under-powered null, and it was
flagged in advance as erring strict. It errs strict. That is the cost being paid
rather than a surprise, and the bar stays where the procedure put it.

What would fix it is not a smaller multiplier chosen now that the floor is
known. It is more matches per sham seed, which tightens the null honestly, and
that is a differently-powered experiment with its own pre-registration.

## The treatment now runs against a bar it will probably not clear

Recorded so the eventual write-up cannot be read as a surprise, and so that a
null result is not mistaken for a demonstration that locality does nothing.

---

# Result: INCONCLUSIVE at 20 triples, and the anatomy says more than the verdict

```
  arm      n   med silence   med gini   fallback wakes   NO_BIDS   NO_ELIG
  cage    20           4.0      0.000                0         0         0
  swarm   20           6.0      0.067                0         0         0
  sham    20          12.0      0.360                0         0         0

  PRIMARY  | median(SWARM) - median(SHAM) | = 6.0 turns     bar 9.0
```

**INCONCLUSIVE.** 6.0 falls between the 3.0 lower band and the 9.0 bar. The
frozen rule routes it there, the sample is not extended, and the bar does not
move.

**The caveat committed before this ran is now load-bearing**, and it said this
would happen:

> A moderate real effect — three or four turns, which would be genuinely
> interesting — produces exactly the same verdict as no effect at all.

The observed effect is six turns. It produced the predicted verdict. That was
written down before the number existed precisely so it could not be
re-described afterwards.

## Cage dependence is zero

```
  fallback wakes         0
  NO_BIDS                0
  NO_ELIGIBLE_BIDS       0
  SHAM_UNDERANGEABLE     0
  request failures       0
```

Across **60 matches and 1,800 allocations**, the fallback authority never woke.
Local bidding carried the scarce slot from the first turn to the last, with no
fairness machinery, no dominance correction and no starvation rescue. Every
`NO_BIDS` state that abstention made reachable stayed unreached in practice.

This is the number the whole starvation programme was defined around, and it is
zero. It is also the one quantity here that is not affected by the
under-powered null, because it is a count of events rather than a comparison
against a floor.

## What destroying locality actually does

The verdict is inconclusive; the mechanism is not subtle.

```
  share of turns actually spoken

  cage     every agent 20.0%                     gini 0.000
  swarm    17.7% - 23.7%                         gini 0.067
  sham     0.7% - 36.3%                          gini 0.360
```

Under the sham, `H 2o Danube 3 4B #2` submitted **596 bids — more than any
other agent — and spoke 0.7% of the time.** `Gemma 3 1B` took 36.3%. Destroying
the mapping between local state and identity does not merely randomise the
schedule; it removes the self-correcting loop, because a bid that no longer
belongs to the agent whose silence produced it cannot answer that silence.

The swarm keeps a Gini of 0.067 against the sham's 0.360, and does it with no
referee.

## The honest reading, and its limit

Stated as events rather than as an interpretation, because the interpretation is
the part that would be doing the arguing:

> **Destroying the mapping between local state and agent identity produced a
> large allocation pathology, while intact locality completed all 1,800
> allocations without centralized fallback. The pre-registered primary test
> remained inconclusive because its 9-turn bar exceeded the observed 6-turn
> difference.**

An earlier draft of this section said "locality is doing real work". That is
supported mechanically and it is not what the frozen test measured, and the
distance between those two things is exactly where a result gets quietly
upgraded. The sentence above says what happened and what did not clear, and
nothing else.

The architecture claim that *is* clean, because it is a property of the code
rather than of the outcome:

> **The substrate stayed semantically blind for all 1,800 allocations.** The
> resolver received `{agent_id, eligible, bid}` and nothing else, fairness
> assistance was off, and the fallback never woke. Whatever the schedule was
> worth, it was produced without the arena being told why anyone wanted the
> slot. The primary statistic missed its bar and the answer is inconclusive.

Two further observations, recorded as pointers rather than evidence:

* every swarm match had a longest silence between 4 and 8, and the null's ten
  sham medians ranged 8 to 13 — the treatment sits below the entire observed
  sham distribution. That is not the frozen comparison and it is not being
  substituted for it.
* the sham may be a *stronger* destruction of locality than "no locality" would
  be in nature, since it actively misassigns every turn rather than merely
  failing to correlate. A weaker control would be a different experiment.

## What is earned and what is not

**Earned:** local bidding allocates a scarce slot unassisted across 1,800
consecutive allocations with zero fallback wakes, and the locality mapping is
what prevents monopoly.

**Not earned:** any claim that locality produces *different dynamics* at the
pre-registered threshold. It did not clear the bar.

The next experiment is not a smaller multiplier. It is more matches per sham
seed, which tightens the null honestly and would give a six-turn effect a fair
chance of being detected — with its own pre-registration, written before the
floor is known.
