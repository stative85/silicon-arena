# Direction: what Silicon Arena is for, and what it refuses

Written down because the tempting things all photograph well, and a screenshot
is not a result. This document is a commitment about *what gets built next* and
*what does not get built at all*. It is not a roadmap of features; it is a
constraint on them.

## The thesis

> More agents is not more interesting. Five bots arguing in a circle behind a
> good UI is an expensive pile of trash wearing neon.

The version worth building is the one where **the architecture itself produces
behaviour nobody centrally scripted.** Every experiment in
[EXPERIMENT_LEDGER](EXPERIMENT_LEDGER.md) that tried to *instruct* interesting
behaviour was rejected; the two that shipped changed what the arena *does with*
model output. Put the structure in the substrate, not in the prompt.

The end state, if every layer earns the next:

```
  LOCAL AGENTS
      |-- private state
      |-- local communication graph
      |-- local compute demand
      |-- local bidding
      +-- local interpretation
                |
                v
        OPAQUE STIGMERGY
                |
                v
        BLIND SUBSTRATE
        |-- resource arbitration
        |-- VRAM / JIT execution
        |-- provenance
        +-- canonical history
                |
                v
      SHADOW COUNTERFACTUALS
                |
                v
        ROBRUSTION FORGE
                +-- candidate improvements, proposed never promoted
```

That is a local artificial ecology where communication, attention, memory,
compute and survival are all constrained resources, while the central substrate
stays deliberately too stupid to manufacture the behaviour itself.

## Build order, enforced

Each is a separate pre-registration. None starts before the one above returns a
verdict.

### 0. Fault, degradation and reintegration — DONE

[EXPERIMENT_SWARM_F](EXPERIMENT_SWARM_F.md), **PARTIAL**. Allocation holds to a
roster of three with zero fallback wakes in 4,000 allocations; collapses at two;
**reintegration is only guaranteed once an absence reaches 8 turns**, the
starvation-saturation constant.

That last clause is a live constraint on step 2, not a closed result. See
"What SWARM-F hands forward" below.

### 1. Compute metabolism — make intelligence a scarce resource agents request

Extend the local decision from "do I want the slot" to "how much intelligence
does this moment deserve":

```
  {bid: 0.71, requested_class: SMALL | NORMAL | HEAVY, token_budget: 48|96|160}
```

The substrate may know only resource facts — `agent_id`, `eligible`, `bid`,
`requested_class`, `cost`, `availability` — and never why. Heterogeneous models
competing for real VRAM stops being plumbing and becomes the world's
metabolism, which is this project's genuine asymmetry.

Teeth:

```
  >7B                              impossible
  invalid class                    hard reject
  unavailable model                explicit failure, never silent downgrade
  cost budget exceeded             downgrade or deny mechanically
  semantic reason crossing         verify red
  unique model                     never deleted under pressure
```

Measure compute requested, compute granted, latency, fallbacks, VRAM churn,
behaviour under starvation. **Do not measure "smartness" yet.**

### 2. Local communication topology — destroy the all-to-all chat room

Each agent gets an observation neighbourhood: proximity, range, line of sight,
temporary channels. Fixed shapes as the experimental variable — FULL, RING,
LINE, STAR, TWO CLUSTERS, PARTITION then REJOIN, RANDOM LINK FAILURE.

> The arena controls whether a channel physically exists. It never decides what
> information ought to move through it.

The question that becomes askable: can information cross the population without
any agent holding global context?

### 3. Real stigmergy — agents modify the environment

Only after topology works. Not a global semantic spreadsheet; that is Cage 2.
An opaque substrate primitive:

```
  TRACE {trace_id, source_agent, locus_id, canonical_source,
         strength, ttl, payload_ref}
```

The substrate knows only *something exists here*. Agents interpret locally.
Traces attach to real things — doors, corridors, objects, resources, terminals,
canonical events. Agent A marks a corridor, disappears, and Agent D routes
around it 25 turns later having never spoken to A.

Teeth: canonical provenance or destroy; TTL mandatory; emission budget; no
self-reinforcement; **reading a trace cannot increase its strength**; derived
state rebuildable from canon; invalid provenance dropped and never
reconstructed.

### 4. Shadow counterfactual arena

At selected canonical moments, fork: what if another agent had won, escalation
been denied, a trace been invisible? Shadow branches never touch live state.
Store fork turn, real decision, counterfactual decision, short trajectory,
mechanical differences.

Horizons stay at 1–3 turns. Anything longer reinvents exponential tree search
on a consumer GPU.

### 5. The ROBRUSTION forge — recursive improvement that cannot self-promote

Generate candidate local policies; **never promote one because a metric moved**.

```
  CURRENT POLICY -> candidate mutations -> LOCALITY GATE -> FAULT SUITE
  -> CONTROL VALIDATION -> HELD-OUT SCENARIOS -> PARETO COMPARISON
  -> promotion candidate
```

No `emergence_score`. A Pareto frontier instead: fallback wakes down, starvation
down, compute cost down, latency down, VRAM churn down, fault recovery up,
allocation diversity up, rejoin reliability up. A candidate survives only by
improving something real without violating a frozen guard elsewhere.

Every candidate must pass INVARIANT → DETECTION → TEETH → RECOVERY → PROOF, plus
the doctrine earned since: a control must prove it can fail (rule 6), provenance
firewall (rule 7), adversarial validation when a result gets cleaner (rule 8),
decision-statistic support checked (rule 9), generating assumptions matched
(rule 10).

**The system proposes. It does not promote.**

## Cross-cutting: opaque decision receipts

Belongs to whichever layer needs it first. The resolver stays blind; an agent
may store a private receipt *after* a decision — `receipt_id -> local inputs +
local decision` — readable by the audit layer, never by the allocation path.
Post-hoc causal archaeology without returning semantic authority to the cage.

Invariant, and it needs a test that goes red when breached: **a receipt is
written after the allocation it describes, and nothing in the allocation path
can read one.**

## What SWARM-F hands forward, and it is not optional

**The 8-turn reintegration boundary is a constraint on the topology work.**
Step 2's core perturbation is partition-then-rejoin. SWARM-F established that a
returning agent is only guaranteed its first eligible turn once its absence
saturates starvation at 8 turns. Any partition shorter than that will reproduce
the same rejoin failures — and if topology does not account for it, they will be
misread as a *topology* effect when they are a known property of the bid policy.

Either partitions are held at 8+ turns, or the rejoin statistic is scored
against the SWARM-F boundary rather than against zero.

## The locality question compute metabolism must answer first

`cost` and `availability` are resource facts and the resolver may see them.
**But what does the agent see when it forms `requested_class`?**

If the agent knows what is currently loaded in VRAM, then every agent is reading
the same global variable, and they are coupled through shared state that no
local view should contain. That is the cage returning as a resource signal
rather than a semantic one, and the locality lint would not catch it because
nothing semantic crossed.

The swarm-like answer is that an agent requests **blind** — it asks for what the
moment deserves by its own lights, and the substrate grants, downgrades or
denies on facts the agent never sees. Denial is information, and it is the only
information about global resource state an agent should get.

This must be settled in the pre-registration, before any code, because both
designs are implementable and only one of them is still a swarm.

## Rule 10 is already loaded and aimed at step 1

Any threshold derived while all agents request `NORMAL` cannot judge a run where
agents escalate — escalation changes the distribution of latency, VRAM churn and
fallbacks. Derive baselines under the no-escalation regime by all means, then
use them as **baselines to measure against, not bars to fail against**
([AUDIT_RULE9](AUDIT_RULE9.md), and rule 10 in
[CONTRIBUTING](../CONTRIBUTING.md)).

SWARM-F paid for that lesson once already, at statistic 3.

## The refusal list

Cheap, demos beautifully, and every one quietly puts God back inside `main.gd`:

* more prewritten personalities
* global mood meters
* central relationship scores
* an "AI director" deciding drama
* automatic coalitions
* thirty memory dimensions
* a giant global vector called `emergence_score`
* fifty agents because fifty is bigger than five

The common defect: each replaces emergence with a central authority that
*computes* emergence, and then the interesting behaviour is the authority's, not
the swarm's. A metric named after the thing you are trying to produce is a
confession.

Adding any of these is not a feature decision. It is a change to what the
project claims to be, and it belongs in a pre-registration that says which prior
result it invalidates.

## Deferred, not refused

**Emergent specialization with zero assigned roles.** Identical permissions, long
horizons, specialization classified afterwards, and it only counts if it survives
resets or perturbations without a role prompt. It was in an earlier draft of this
order and has been dropped out of the top five deliberately: it is a *read* on a
system that has enough structure to specialise, and the arena does not have that
structure until compute, topology and stigmergy exist. Building it sooner would
measure prompt residue and call it a niche.
