# Direction: what Silicon Arena is for, and what it refuses

Written down because the tempting things all photograph well, and a screenshot
is not a result. This document is a commitment about *what gets built next* and
*what does not get built at all*. It is not a roadmap of features; it is a
constraint on them.

## The thesis

> More agents is not more interesting. Five bots arguing in a circle behind a
> good UI is an expensive pile of trash wearing neon.

The version of this project worth building is the one where **the architecture
itself produces behaviour nobody centrally scripted.** Every experiment in
[EXPERIMENT_LEDGER](EXPERIMENT_LEDGER.md) that tried to *instruct* interesting
behaviour was rejected; the two that shipped changed what the arena *does with*
model output. That is the same finding at a larger scale: put the structure in
the substrate, not in the prompt.

The combination that is actually distinctive:

```
  local agents  +  private state  +  local perception  +  scarce compute
  +  agent-requested model escalation  +  spatial traces
  +  blind arbitration  +  provenance-backed audit
```

That is not five LLMs in a chat room. That is a small artificial society running
on one consumer GPU.

## Build order

Each of these is a separate pre-registration. None of them starts before the one
above it has returned a verdict.

**1. Fault, degradation and reintegration.** — *in progress,
[EXPERIMENT_SWARM_F](EXPERIMENT_SWARM_F.md)*
An agent disappears, goes intermittently silent, or returns after 20 turns with
only its preserved local state. The swarm routes around the hole and the arena
never says "replace Gemma with Qwen". Makes "starve the cage" a resilience
measurement rather than a philosophy.

**2. Agent-controlled compute metabolism.** — *the one to circle hardest*
Agents decide locally not only whether they want the slot but **how much
intelligence the moment deserves**: a normal turn, a longer token budget, or
escalation to a larger model. The substrate sees `cost`, `availability`,
`requested_class` and the hard VRAM law. It never learns why.

This turns JIT model loading from backend plumbing into the world's ecology, and
it is the project's real asymmetry: most multi-agent demos do not have
heterogeneous local models genuinely competing for scarce VRAM. The hardware
limit stops being an apology and becomes the metabolism.

**Doctrinally this fits, and the fit must be checked rather than assumed.** The
resolver's failure codes already "describe RESOURCE state, never motive", and
`cost` / `availability` / `requested_class` are resource facts of exactly that
kind — they say what is being asked for, not why it is wanted. But
`ALLOWED_KEYS` is a closed vocabulary of three and `tools/lint_locality.py`
enforces it. Extending it is **a change to the experiment**, made in a
pre-registration, in the open, with the lint updated in the same commit. It is
not a refactor, and `requested_class` must never carry a reason field.

**3. Dynamic communication topology.**
Stop letting everybody hear everybody. Local neighbourhoods — line of sight,
proximity, range, intermittent links. Two agents become informationally isolated
while three others form a temporary cluster, and the arena never creates
"teams". Topology becomes the experimental variable: full graph, local graph,
sparse graph, intermittent links. Coordination surviving information loss is
watchable in a way a metric is not.

**4. Real spatial stigmergy.**
Not a global memory field hidden in code. Agents leave small decaying traces
attached to **places, objects, doors, resources, canonical events**, perceived
only within a local observation radius. One agent marks a dangerous corridor;
another routes around it later having received no message. Every trace keeps
canonical provenance, decays, and can never reconstruct missing content.

Deferred until locality or topology gives it a foundation — building a trace
layer on an unresolved locality effect would mean never knowing which of the two
carried the result ([EXPERIMENT_SWARM_B2](EXPERIMENT_SWARM_B2.md)).

**5. Emergent specialization with zero assigned roles.**
No "you are the critic" prompts — that is costume emergence and this ledger has
nine rejections saying instructions do not survive contact with these models.
Identical permissions, long horizons, and specialization classified
**afterwards**. One explores, one responds, one hoards compute, one revives old
scars. The claim only counts if the specialization persists across resets or
perturbations without a role prompt.

**6. Counterfactual shadow swarm.**
Keep the losing bids. When compute is cheap, let a small model or heuristic
simulate what would have happened had another bidder won. Do not feed it back
into the live match. Store it as a shadow branch, and the arena accumulates a
counterfactual tree: actual trajectory against plausible alternatives. Later
this is experimental leverage; eventually it is a replay UI showing where the
swarm forked.

## Opaque decision receipts — a cross-cutting mechanism

Not a numbered step, because it belongs to whichever experiment needs it first.

The resolver stays blind. An agent may store a **private receipt** after a
decision has been made: `receipt_id -> local inputs + local decision`. The
resolver cannot read it. The experiment and audit layer can inspect it later.

That buys post-hoc causal archaeology without handing semantic authority back to
the cage. If one agent dominates for 40 turns, its receipts explain why *after
the fact*, and the scheduler was never allowed to use a word of it. The
invariant to enforce: **a receipt is written after the allocation it describes,
and nothing in the allocation path can read one.** Both halves need a test that
goes red when breached, the same way the locality boundary has one.

## The refusal list

These are cheap, they demo beautifully, and every one of them quietly puts God
back inside `main.gd`. They are refused now, in advance, so that a future
screenshot cannot argue for them:

* more prewritten personalities
* global mood meters
* central relationship scores
* an "AI director" deciding drama
* automatic coalitions
* thirty memory dimensions
* a giant global vector called `emergence_score`

The common defect is that each replaces emergence with a central authority that
*computes* emergence, and then the interesting behaviour is the authority's,
not the swarm's. A metric named after the thing you are trying to produce is a
confession.

Adding any of these is not a feature decision. It is a change to what the
project claims to be, and it belongs in a pre-registration that says which prior
result it invalidates.
