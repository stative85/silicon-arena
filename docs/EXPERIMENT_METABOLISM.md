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
