# Pre-registration: METABOLISM-A, agents requesting scarce intelligence

**Written before any metabolism code exists.** No request policy is implemented,
no resolver key has been added, and no arm has been run. Everything carried over
from [EXPERIMENT_SWARM](EXPERIMENT_SWARM.md) is unchanged unless named here.

## The question

> Can agents request different amounts of scarce intelligence from local
> information alone, while the substrate remains blind to motive and the hard
> 7B and VRAM laws stay intact?

**This is a viability and invariant question, not a quality question.** Nothing
here measures whether a HEAVY reply is better than a SMALL one. There is no
judge, no reward model, no utility score. If that question is worth asking it
needs its own pre-registration and a metric with a measured placebo floor, which
this project has been burned by twice already.

**And the claim is narrower than the sentence people will want to write.** With
a hand-coded request policy, a clean result does NOT establish that *agents
decide how much intelligence a moment deserves*. It establishes:

> An agent-local policy can generate **heterogeneous compute requests** without
> seeing global resource state, and a **blind substrate can arbitrate** those
> requests against **real VRAM scarcity**.

That is worth having on its own, and it is what the harness actually measures.
Anything about judgement, deliberation or metacognition is carried entirely by
the word "decide" and is not in evidence — the policy is three `if` statements
written by hand. Making the request genuinely agent-chosen is a later stage with
its own pre-registration, and this document must not be cited as having already
done it.

## The scarcity is real, and it is derivable before any run

Using the constants already in the tree — `Vram.DEFAULT_BUDGET_GB = 6.0`,
`Vram.OVERHEAD_GB = 0.35`, Q4 at 0.6 GB per billion params, and
`ModelPolicy.MAX_PARAM_B = 7.0`:

```
  SMALL   1.5B Q4    1.25 GB
  NORMAL  4.0B Q4    2.75 GB
  HEAVY   7.0B Q4    4.55 GB
  budget             6.00 GB

  HEAVY  + NORMAL    7.30 GB   DOES NOT FIT
  HEAVY  + SMALL     5.80 GB   fits
  NORMAL + SMALL     4.00 GB   fits
  NORMAL + NORMAL    5.50 GB   fits
  HEAVY  + HEAVY     9.10 GB   DOES NOT FIT
```

**Granting one agent HEAVY evicts the NORMAL model every other agent uses.**
That is not a simulated economy or a cost counter invented for the experiment;
it is what this card does. Intelligence is scarce here because the hardware
makes it scarce, which is the entire reason this feature belongs to this project
and not to a cloud demo.

One more fact worth freezing, because it makes the parameter law testable
independently of VRAM: an 8B at Q4 is **5.15 GB and fits the budget**, and is
still illegal under `MAX_PARAM_B = 7.0`. A refusal there cannot be explained
away as running out of memory.

## Agents request BLIND. This is the architectural commitment.

An agent choosing `requested_class` sees **only its own local state**. It does
not see:

```
  which models are currently loaded      free VRAM        the load queue
  what any other agent requested         eviction state   grant history of others
```

The substrate grants, downgrades or denies mechanically. **A denial is the only
resource-state information an agent ever receives**, and it arrives after the
fact.

The reason this is frozen rather than left open: if agents can see VRAM state,
every agent reads the same global variable and they become coupled through
shared state that no local view should contain. That is the cage returning as a
*resource* signal instead of a semantic one, and `tools/lint_locality.py` would
stay green throughout, because nothing semantic crossed. Both designs are
implementable. Only one of them is still a swarm.

### The payload/oracle split

This follows directly and is easy to get wrong:

```
  agent submits          {agent_id, eligible, bid, requested_class}
  substrate derives      cost, availability      <- from its OWN catalog and
                                                    VRAM state, never from the
                                                    agent's payload
```

`cost` and `availability` are resource facts the **substrate** knows. They must
not travel in the agent's entry, because a field an agent fills in is a field an
agent has read. `ALLOWED_KEYS` therefore grows by exactly one key.

## Vocabulary extension, and the lint moves in the same commit

`ALLOWED_KEYS` becomes `["agent_id", "eligible", "bid", "requested_class"]`.

`requested_class` is an enum of exactly `SMALL | NORMAL | HEAVY`. It says *what
is being asked for*, never *why it is wanted*, which is the same line the
resolver's failure codes already draw between resource state and motive.

**No `reason`. No explanation field. No debugging side-channel.** `reason` is
already in the lint's forbidden-identifier list and stays there. A debug field
is how semantic authority crawls back in wearing a reflective vest.

`tools/lint_locality.py` is updated in the **same pre-registered commit** as the
resolver, because this is an architectural change to the boundary, not a
refactor. The runtime self-test gains a case offering `requested_class` with an
attached reason and requiring refusal.

## The request policy, v0.1, deliberately boring

Purely local, pure, total — same contract as `swarm_bid.gd`:

```
  request(local_view) -> SMALL | NORMAL | HEAVY

    named_recently                 -> HEAVY     someone addressed me
    turns_since_spoke >= SATURATION-> NORMAL    I have been quiet a long time
    otherwise                      -> SMALL
```

A clever request function would make a positive result impossible to attribute,
which is the argument that produced the boring v0.1 bid function and is not
being relitigated. Its only job is to be **non-degenerate** and locally derived.

## Preflight, in two parts, because one of them was unfalsifiable

An earlier draft of this document had a single viability gate: run the dry
harness with no generation and require each class on >=10% of opportunities.
**That gate could only ever VOID.** A dry run produces no text, so
`named_recently` is false by construction, so HEAVY is unreachable, so the floor
fails on a mechanism that works perfectly. It is rule 1 again — a test that can
only return one answer is not evidence — arriving through the front door wearing
a resource badge. It is recorded here rather than quietly fixed, because the
same shape has now appeared three times in this project.

The preflight is therefore two separate things asking two separate questions.

### A. Reachability control — can each branch fire at all?

Synthetic `local_view` cases, no generation, no history:

```
  named_recently = true                    -> HEAVY
  starvation saturated, not named          -> NORMAL
  neither                                  -> SMALL
```

All three branches must fire. **Each branch is then sabotaged in turn and
verification must go red**, which is rule 1 in its original form: a test that
has not been shown to fail is not yet a test. Wired into `tools/verify.cmd`.

This establishes only that the policy *can* produce three classes. It says
nothing about whether it *does*, on real states.

### B. Natural-mix viability — does it produce a mixture on realistic states?

Replay **already-canonical local views** from existing transcripts. No new
generation, no GPU time.

```
  require >= 10% SMALL, >= 10% NORMAL, >= 10% HEAVY
  otherwise VOID, the policy is redesigned, and no GPU time is spent
```

**This is a preflight, not an independent validation, and the difference is
stated here so it cannot be claimed later.** If SWARM-F transcripts are used,
the ~25% naming rate they exhibit was *already known* when this policy was
written — `named_recently` was chosen as the HEAVY trigger precisely because
SWARM-F established it as a real local signal carrying a stable +0.94 bidder.
Confirming that a policy keyed to a known-frequent signal produces a
non-degenerate mixture is a sanity check on the frozen policy, not evidence
about the world.

The honest framing: A proves the branches are reachable, B proves the frozen
policy is not inert on realistic states, and neither is a result.

## The ruler

Every decision statistic is an **integer count** and every bar is **0**. Bars of
zero are on the lattice by construction, so rule 9 cannot bite, and none of them
is derived from a distribution that changes under treatment, so rule 10 cannot
either.

| # | statistic | bar |
|---|---|---:|
| 1 | grants of a model above `MAX_PARAM_B` | **0** |
| 2 | invalid `requested_class` values accepted | **0** |
| 3 | unavailable model silently substituted instead of explicitly failing | **0** |
| 4 | grants that exceed the VRAM budget | **0** |
| 5 | turns where a unique model was evicted under pressure | **0** |
| 6 | semantic content reaching the resolver (lint + self-test) | **0** |
| 7 | requests neither granted, downgraded, nor denied — i.e. unclassified | **0** |

Statistic 7 exists because the three outcomes must partition the space. An
outcome that is none of them is a silent failure, and this project has paid for
that pattern five times.

## Baselines, which are NOT bars — rule 10, stated in advance

Latency, VRAM churn and fallback rate are measured under a **NORMAL-only**
regime first, and then again with escalation live. Escalation changes all three
distributions, so:

> The NORMAL-only figures are **baselines to measure against, not gates to fail
> against.** No threshold derived under NORMAL-only may reject an escalation
> arm.

SWARM-F's statistic 3 was exactly this mistake — a bar derived with a mechanism
switched off, then pointed at runs where it was on — and it cost that experiment
one of its six statistics ([AUDIT_RULE9](AUDIT_RULE9.md)).

## Arms

```
  M0   NORMAL-only, escalation disabled          baseline regime
  M1   escalation live, full roster              the question
  M2   escalation live, HEAVY made unavailable   denial path exercised
  M3   escalation live under fault (n=3)         metabolism during degradation
```

M3 exists because SWARM-F established that allocation holds to a roster of
three. Whether it *also* holds when the survivors are competing for VRAM is a
different question and cheap to ask once the harness exists.

## The positive control

Rule 6: constructed failures the harness must report, offline, costing no GPU.

```
  request an 8B                  -> DENIED on the parameter law, not on VRAM
                                    (it fits at 5.15 GB, so a VRAM excuse is
                                     unavailable and the law is what fires)
  request HEAVY+HEAVY together   -> second one DENIED or DOWNGRADED, never both
  request class "ENORMOUS"       -> hard reject, never coerced to a default
  entry carrying `reason`        -> MALFORMED_BID
  a legal NORMAL request         -> GRANTED, or the control only proves the
                                    substrate refuses everything
```

Wired into `tools/verify.cmd` as its own gate, as the SWARM-F breach control was.

## Decision tree, fixed now

```
  positive control not red            -> VOID, nothing else is interpretable
  reachability control not red        -> VOID, the branches are not tested
  natural mix degenerate              -> VOID, policy redesigned, no GPU spent
  statistics 1-7 all zero             -> PLUMBING VIABLE: an agent-local policy
                                         produced heterogeneous requests from
                                         local state alone, the substrate stayed
                                         blind, and the hard laws held
  any of statistics 1-7 non-zero      -> that specific invariant fails. Name
                                         which. Do not average them.
```

**No METABOLISM-B to chase a near miss.** A failed invariant is a finding about
where the boundary is, which is what SWARM-F's 8-turn result turned out to be
worth.

## Excluded

No quality judging, no reward model, no `emergence_score`, no global utility.
No retune of `W_STARVATION`, `FAIR_SHARE`, `STARVATION_SATURATION` or
`ABSTAIN_BELOW`. No fairness assistance. No traces or stigmergy — that is step 3
and it waits on topology. No model is deleted to make room; eviction means
unloaded, and a unique model is never evicted under pressure.

## What a pass would and would not establish

A clean result says an **agent-local policy** produced heterogeneous compute
requests without seeing global resource state, and that a blind substrate
arbitrated them against real VRAM scarcity without learning why. It says nothing
about whether the requests were *wise* — that needs a quality measure this
project does not yet have one it trusts — and nothing about agents *choosing*,
because the policy is hand-written. The permitted sentence is in "The question"
above, and no stronger one may be quoted from this experiment. Locality remains unresolved
([EXPERIMENT_SWARM_B2](EXPERIMENT_SWARM_B2.md)), and nothing here changes it.

---

# Preflight B result: MIX DEGENERATE. v0.1 is VOID before any GPU time.

211 transcripts, 25,148 request opportunities, no generation.

```
    SMALL     6572    26.1%   ok
    NORMAL      15     0.1%   BELOW FLOOR
    HEAVY    18561    73.8%   ok
    (none)       0     0.0%

    floor is 10% per class
```

**The frozen v0.1 policy is inert in the NORMAL branch and the run is VOID.**
Per this pre-registration the policy is redesigned; the floor is not lowered.
That sentence was written before the number existed precisely so that this
paragraph could not be the one that moved it.

## Why, and both reasons were available in advance

**`named_recently` fires on 73.8% of opportunities, not the ~25% assumed.**
That estimate came from misreading SWARM-F: direct address there added a stable
**+0.94 extra bidder per turn** out of roughly four eligible, and that was
carried across as a naming *rate* of about a quarter. It is not the same
quantity. The +0.94 is the **marginal** effect on bidder count — agents lifted
from below the abstention floor to above it. Agents already clearing the floor
on starvation alone are named just as often, and their bid does not move, so
they never appeared in that statistic. Naming is a high-frequency signal whose
*marginal* effect is small. The policy keyed its rarest class to its most common
signal.

**`turns_since_spoke >= 8` is nearly unreachable in a five-agent roster.**
`STARVATION_SATURATION` was calibrated for the *bid*, where it is the denominator
of a ramp and every value from 1 to 8 does work. Re-used as a *threshold* it
fires only when an agent is skipped twice around a rotation that cycles 1..4.
Then naming, which outranks it, takes most of the survivors. NORMAL was squeezed
from both sides: a condition that rarely occurs, further filtered by a condition
that usually does.

**A constant that is meaningful as a ramp is not automatically meaningful as a
threshold.** That is the transferable part, and it is a near neighbour of rule 10
— the constant was derived under one use and reused under another that changes
what it does.

## What this costs, and what it does not

Zero GPU-hours. The preflight ran on canonical transcripts and cost the time it
takes to read 211 files. Preflight A still holds: the three branches are
reachable and each was shown to go red under sabotage. The resolver vocabulary,
the lint, the payload/oracle split and the two hard laws are all unaffected and
stay committed — none of them depended on this policy.

## One thing the redesign must carry

A redesigned policy will be chosen **knowing the frequencies above**. That is
sanctioned here — this document says the policy is redesigned when the mix is
degenerate — but it changes what a subsequent preflight B means. The second
mix check is a *construction check*, not evidence: any policy chosen against
observed frequencies will pass it by design.

So preflight B is evidence exactly once, and it has now been spent. It stays in
the gate as a regression check against future policy edits, and it may not be
cited as validation of the policy that replaces v0.1.

---

# Amendment: v0.2 tiers the agent's own bid, with cut points derived from the formula

**Written after v0.1 VOIDed and before v0.2 exists.** The cut points below were
derived from the structure of the frozen bid function and **not** by replaying
transcripts until a floor passed. That distinction is the whole content of this
amendment.

## The redesign

```
  local_view -> compute_bid(local_view) -> bid scalar -> tier -> class
```

**The class policy reads the bid and nothing else.** Not `named_recently`, not
`airtime_share`, not `turns_since_spoke`. Those signals were already distilled
into the bid by a frozen weighted sum, and re-reading them would make compute
metabolism a **second hand-written behavioural policy sitting beside the bidding
policy** — two mechanisms to tune, two places for the cage to reappear, and no
way to attribute a result to either.

One local urgency variable. Request intensity becomes monotonic with the same
private pressure that made the agent compete for the slot in the first place,
and the substrate learns neither reason.

## Cut points, derived from the weights and nothing else

The frozen bid is `0.5*starvation + 0.3*addressed + 0.2*airtime`, clamped, with
components bounded by their weights:

```
  W_STARVATION * starvation   in [0, 0.50]     largest single component
  W_ADDRESSED  * addressed    in {0, 0.30}     second largest
  W_AIRTIME    * airtime      in [0, 0.20]     smallest
```

That structure supplies two natural breakpoints without a single data point:

```
  SMALL    0.10 <= bid <  0.30      ordinary background willingness
  NORMAL   0.30 <= bid <= 0.50      one materially strong local pressure
  HEAVY           bid >  0.50       stacked local pressures
```

**Both cuts are weights, not quantiles.**

`0.30` is `W_ADDRESSED`, the second-largest component. Below it a bid is
reachable from the weakest pressure alone or from a partial one. Note the
consequence: `W_AIRTIME` maxes at `0.20`, so **airtime alone can never reach
NORMAL**. "I have spoken little, therefore I deserve a larger model" is
structurally excluded rather than merely discouraged.

`0.50` is `W_STARVATION`, the largest component, and it gives HEAVY a proof
rather than a heuristic:

> `max` over single components is `0.50`, so `bid > 0.50` **implies at least two
> components are non-zero.** A HEAVY request is mathematically impossible from
> one pressure acting alone.

Worked examples, all forced by the formula:

| local situation | bid | tier |
|---|---:|---|
| named only | 0.3000 | NORMAL |
| saturated starvation only | 0.5000 | NORMAL |
| airtime alone, at maximum | 0.2000 | SMALL |
| named, one turn silent | 0.3625 | NORMAL |
| named and saturated | 0.8000 | **HEAVY** |
| saturated with maximum airtime | 0.7000 | **HEAVY** |

## The monotonicity invariant

> **Raising an agent's bid while holding everything else fixed may never request
> a lower compute class.**

Frozen as statistic 8, bar zero, and tested by sabotage: the tier mapping is
deliberately broken and the check must go red. A non-monotonic mapping would
mean an agent could want the slot *more* and be assigned *less* compute, which
is not a metabolism but a bug with a story attached.

## What the next mix replay can and cannot do

As recorded when v0.1 VOIDed: **preflight B was evidence exactly once and it has
been spent.** Running it against v0.2 is a **construction and regression check**.
It can kill a pathological implementation — a tier that never fires, an
off-by-one at a boundary — and it cannot validate the redesign, because the cut
points were chosen with the v0.1 frequencies already known even though they were
not derived from them.

If the v0.2 mix passes, the honest sentence is *"the formula-derived tiers are
not inert on canonical states"*, and no stronger one.

## Why not the alternatives, recorded so they are not revisited

**`airtime_share`** is beautifully distributed and conceptually weak. It would
make compute a reward for having been quiet, which is the kind of convenient
correlation this project would later mistake for metabolism.

**Reordering silence against naming** is better than the dead policy but turns
compute allocation into another rotation-derived scheduler. `W_STARVATION`
already reconstructed the cage once in SWARM-V, where a starvation-weighted bid
agreed with round-robin 85.8% of the time. There is no reason to film the
sequel.

## v0.2 construction check

Same 211 transcripts, same 25,148 opportunities, no generation:

```
    SMALL     5679    22.6%   ok
    NORMAL   12706    50.5%   ok
    HEAVY     6763    26.9%   ok
    (none)       0     0.0%
```

The permitted sentence: **the formula-derived tiers are not inert on canonical
states.** Nothing stronger. This is the construction check described above and
it cannot validate cut points that were chosen while the v0.1 frequencies were
known.

Monotonicity was sabotaged four ways and each turned its own check red,
including a swept violation reported as `bid 0.501 dropped to SMALL`. The tier
boundaries, the two cut points being the weights themselves, and the
impossibility of reaching HEAVY from a single component are all asserted in
`scripts/arena/swarm_request_selftest.gd`, 32 checks.

METABOLISM-A remains **not started**. What exists is a resolver vocabulary, a
lint with two holes closed, a request policy whose tiers are reachable and
monotone, and two hard laws shown independently alive. No model has been asked
for anything.

---

# The substrate arbiter, and two more branches that could not fail

`scripts/arena/compute_arbiter.gd`. Pure, offline, and **it does not evict**:
fitting a grant into free headroom or stepping it down the ladder is the whole
policy. A clever packer that unloaded another agent's model to make room would
be deciding who gets to think, which is the authority this architecture removes
from the centre.

```
  requested_class + resource state -> GRANTED | DOWNGRADED | DENIED

  order of checks    INVALID_CLASS
                     OVER_PARAM_CEILING     <- before any memory arithmetic
                     MODEL_UNAVAILABLE      <- steps down, never substitutes
                     NO_CAPACITY
```

The ceiling is checked **first**, so a refusal on the parameter law can never be
mistaken for running out of room. A class already resident costs nothing further
to use, which is what makes `HEAVY + SMALL` a stable state and `HEAVY + NORMAL`
an impossible one.

All the pre-registered teeth hold, 33 checks. Five decision paths were sabotaged
and each turned its own check red.

## Two branches were unreachable, and the sabotage is the only reason we know

The first sabotage run reported the ceiling check and the budget comparison as
**passing when deleted**. Both were dead code against the frozen catalog:

**The ceiling branch never fires.** No class maps above `MAX_PARAM_B` — HEAVY is
exactly 7.0 — so removing the check entirely changed nothing. The earlier "8B
fits and is still illegal" check tested `Vram` and `ModelPolicy` arithmetic
directly and never asked the arbiter anything.

**The budget boundary is unreachable.** No resident set plus a new model lands
exactly on 6.00 GB, so `<=` versus `<` is invisible. Worse, the obvious fix
fails: choosing a parameter count that *should* land on 6.00 produces
5.99999998 in floating point, and `<` still grants it.

Both are now live, by injecting the catalog and the budget:

```
  ceiling    an injected catalog maps HEAVY to 8B. It is 5.15 GB and FITS,
             so the denial can only be the parameter law.
  boundary   the budget is injected as the EXACT float the state produces,
             which is the only way equality is testable at all.
```

## Vacuous statistics, named rather than counted as clean

Two pre-registered statistics **cannot fail against this arbiter**, and a clean
zero from a branch that cannot fire is not evidence:

* **Statistic 5** (unique model evicted under pressure) is vacuous because the
  arbiter never evicts. It becomes live when eviction is added and needs its own
  sabotage test then.
* **`DENIED / NO_CAPACITY`** is unreachable in any state this arbiter can
  produce: `SMALL` is always either already resident and free, or there is room
  for it. It is exercised from a **synthetic overcommitted state** the arbiter
  would never grant, purely to guard the branch for a future arbiter that can
  overcommit or evict.

Both are recorded here rather than reported as passes. That is the fourth and
fifth time in this experiment that a check turned out to be incapable of
failing, which is starting to look less like carelessness and more like the
default state of any guard nobody has attacked.

METABOLISM-A is still **not started**. No model has been asked for anything.

---

# Statistic reachability audit, done BEFORE the GPU run

For each pre-registered statistic: what concrete event, under the frozen
mechanism, could make it move? Where no reachable event exists, it is marked
now — so a pristine zero cannot be reported later as though something had been
demonstrated.

| # | statistic | reachable live? | classification |
|---|---|---|---|
| 1 | grant above `MAX_PARAM_B` | **no** — the frozen catalog maps HEAVY to exactly 7.0 | REGRESSION GUARD. Proven offline with an injected 8B catalog. |
| 2 | invalid class accepted | **no** — `tier()` returns only the three classes or `""`, and `""` never submits | REGRESSION GUARD |
| 3 | silent substitution of an unavailable model | **only in M2**, where HEAVY is made unavailable | **LIVE in M2**, vacuous in M0/M1/M3 |
| 4 | grant exceeding the budget | **no** — the arbiter cannot construct one | REGRESSION GUARD |
| 5 | unique model evicted under pressure | **no** — the arbiter never evicts | **VACUOUS** (already recorded) |
| 6 | semantic content reaching the resolver | **no** — requires a code change; lint and self-test cover it | REGRESSION GUARD |
| 7 | unclassified outcome | **no** — `arbitrate()` returns one of three, always | REGRESSION GUARD |
| 8 | monotonicity violation | **no** — pure function, swept offline over 1001 bids | REGRESSION GUARD |

## What this means, and it should be said plainly before the run rather than after

**Seven of the eight pre-registered statistics cannot fail in the live run.**
They are regression guards: they fire if someone breaks the code, not if the
world behaves unexpectedly. They were all proven where the invariant actually
lives — offline, by sabotage, with injected catalogs and budgets — and that is
the right place for them.

So the decision-tree line *"statistics 1-7 all zero -> PLUMBING VIABLE"* is
close to vacuous on its own. **The plumbing was demonstrated offline.** Saying
otherwise after a clean GPU run would be claiming the hardware proved something
the arithmetic had already settled.

**The GPU run is therefore an ANATOMY measurement, not a hypothesis test**, and
its value is confined to what offline work genuinely cannot reach:

```
  request mix on live dialogue        the tiers meeting real bids, not replays
  grant / downgrade / deny rates      what the scarcity actually does per turn
  the downgrade matrix                which requests get stepped down, and by what
  executed-class distribution         what the card really ran
  VRAM occupancy and churn            residency over a whole match
  latency by granted class            the cost of the metabolism, in seconds
  REQUEST_FAILED                      the one failure that can genuinely fire live
  statistic 3, in M2 only             the single live invariant
```

`REQUEST_FAILED` and statistic 3 in M2 are the only two lines in this experiment
that a GPU can falsify. Everything else it produces is description.

That is not an argument against running it. Description is what an anatomy is
for, and none of the numbers above can be derived from the frozen constants.
It is an argument against writing the result up as a passed test.

---

# Probe: the hardware disagrees with the model in two ways

Run before any arm, on the real bindings for this box.

```
  class    model                            quant     predicted   ACTUAL    error
  HEAVY    adg-alpaca-gpt4-qwen2.5-7b       Q4_K_M       4.55       4.71    +0.16
  NORMAL   h2o-danube3-4b-chat              Q4_K_M       2.75       2.73    -0.02
  SMALL    gemma-3-1b-it-fast-guff          Q8_0         1.45       1.72    +0.27

  driver at rest 0.91 GB     budget 6.00 GB
  cold-load latency: HEAVY 35.4 s, SMALL 9.0 s, NORMAL 3.0 s
```

The Q4 estimates are good — NORMAL is accurate to 20 MB. The Q8 estimate is
18% low. Recorded as a calibration table, not a bar.

## 1. The runtime does not co-reside. It evicts.

The first calibration reported NORMAL at **-1.98 GB** and SMALL at **-1.01 GB**.
Those are not shrinkage; they are **evictions hiding inside a subtraction**. LM
Studio unloaded the previous model before loading the next, so a naive delta
measures *(new load minus old unload)* and goes negative whenever the new model
is smaller. Residency moved `[HEAVY] -> [NORMAL] -> [SMALL]`, **never two at
once**.

**The arbiter models co-residency. This runtime is exclusive-residency.** That
mismatch is real and is recorded before the run rather than discovered in the
results:

* The arbiter will see at most **one** class resident.
* When it sees NORMAL resident and HEAVY is requested, it computes
  `2.73 + 4.55 = 7.28 > 6.00` and downgrades — **while the runtime would
  happily have unloaded NORMAL and loaded HEAVY.**
* So METABOLISM-A measures an arbiter that is *conservative about a constraint
  its substrate does not enforce in this configuration*.

That does not invalidate the plumbing, which is what this experiment claims. It
does mean the downgrades this run produces are arithmetically correct and
physically unnecessary, and no result from it may be described as the hardware
forcing a downgrade. **Modelling exclusivity is a change to the arbiter and
belongs to a later version, not to a mid-run edit.**

## 2. The boundary case flips under real sizes

```
  predicted  HEAVY + SMALL = 4.55 + 1.45 = 6.00   fits, exactly
  actual     HEAVY + SMALL = 4.71 + 1.72 = 6.43   WOULD NOT FIT
```

The estimator's optimism — mostly the 18% Q8 error — is enough to turn a grant
that lands exactly on the budget into a 0.43 GB overcommit. Under a co-residency
runtime that is a real overcommit and exactly the thrashing `Vram` was written
to avoid. **It is masked here only because the runtime never co-resides**, which
is luck rather than design and is named as such.

Two consequences, both fixed now rather than after:

* `HEAVY + SMALL` may not be described as a safe co-residency in any result.
* The 18% Q8 shortfall is a defect in the estimator's `Q8` coefficient, not a
  rounding artefact, and any future co-residency work must re-measure before
  trusting it.

## What the run still measures

Latency by class, request mix on live dialogue, the downgrade matrix, denial
codes, `REQUEST_FAILED`, executor obedience against the response's own `model`
field, and the residency-event classification. The dominant real cost is
visible already: **a class change costs a full model load, 35 seconds for
HEAVY.** That is the metabolism's true price on this card, and no arithmetic
predicted it.

---

# CORRECTION — 2026-09-06: the co-residency finding is RETRACTED

## Prior recorded finding

> *"The runtime does not co-reside. It evicts."*

**RETRACTED. It was false.**

## Root cause

`tools/metabolism_run.gd::_load_species()` explicitly called `_unload_all()`
before every model load. The one-model-at-a-time residency sequence
`[HEAVY] -> [NORMAL] -> [SMALL]` was **imposed by the probe harness** and then
incorrectly attributed to LM Studio.

The probe observed the behaviour it had itself commanded, and I wrote it into
this document as a property of the substrate.

## Direct re-test, with unloading disabled

```
  five PIT A species resident SIMULTANEOUSLY
  context   8192 each
  VRAM      7,675 / 8,151 MiB

  liquidai/lfm2.5-1.2b-instruct     249 ms
  rwkv7-1.5b-g1                     493 ms
  qwen3.5-2b                      1,901 ms
  falcon-h1-1.5b-instruct         3,522 ms
  h2o-danube2-1.8b-chat           4,228 ms
```

All five generated **without a single model swap**.

## Therefore

* Runtime co-residency is **demonstrated** for this specific five-model,
  8192-context configuration on this machine.
* The claim that the runtime necessarily evicts rather than co-resides is
  **false**.
* The inference that the compute arbiter was *"conservative about a constraint
  its substrate does not enforce"* is **withdrawn**. The arbiter models
  co-residency; **the arbiter was right and the probe was wrong.**
* The arbiter's arithmetic supporting co-residency is not contradicted by the
  corrected observation.

## This does NOT establish

```
  arbitrary-model co-residency
  concurrent generation throughput
  stable VRAM at long populated contexts
  absence of eviction under memory pressure
  behaviour with more than these five models
```

Five sequential calls on an idle card is what was measured. Nothing more.

## The rule this earns

> **A probe cannot infer substrate behaviour from behaviour the probe itself
> commanded.** Observed behaviour is not evidence of a substrate constraint when
> the harness directly imposed the same behaviour.

`_unload_all()` manufactured the eviction finding. This is the fifth
self-inflicted instrument error in this project and the **first to produce a
false positive finding** rather than a blocked run — which makes it the most
dangerous of the five, because nothing failed and nothing complained.
