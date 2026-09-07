# ASYNC-B — Representation Creates Topology

**Status:** pre-registered before implementation, model calls, or outcomes.

## Question

Does a shared representational frame causally create the canonical contention
topology between heterogeneous agents?

ASYNC-A3 established the lower half of the mechanism:

```text
CONTENTION TOPOLOGY
        |
RELATIVE INFERENCE TIMING
        |
WHO PAYS FOR CONFLICT
```

ASYNC-B tests the upper half:

```text
REPRESENTATION
      |
SELECTION REGULARITY
      |
CONTENTION TOPOLOGY
```

The host does not assign preferences, roles, targets, cooperation, or meaning.

## Prior evidence used to preregister B

A3 mining established, before ASYNC-B:

```text
LFM <-> Qwen      strong recurring canonical contention edge
LFM <-> Falcon    approximately absent
Qwen <-> Falcon   weak / approximately absent
```

Every A3 stale conflict was mechanically reconstructed as another agent taking
the same canonical target first (198/198 in NATURAL, 198/198 in EQUALIZED).

A3 also established different representational signatures:

```text
LFM2.5:     extreme local-position regularity, rank-0 on essentially
            every cognition (1,544 of 1,544 across three arms)
Falcon:     much stronger identifier regularity while chosen list rank
            varies (ranks 2, 5, 3 in SERIAL; ids fixed at 200 each)
Qwen3.5:    mixed pattern
```

These facts define the hypotheses below. **No ASYNC-B result has been observed.**

## Timing regime

**SERIAL only.** Do not use NATURAL, EQUALIZED, or REPLAY.

Purpose: remove relative inference latency from the experiment so B isolates
`representation -> choice -> contention`.

Required teeth:

```text
STALE_CONFLICT == 0
observation_age_ticks == 0
```

Any violation voids the affected replicate.

## World

Unchanged from A3:

```text
agents:       3
models:       lfm2.5 + qwen3.5 + falcon
resources:    16
hold:         4 ticks
horizon:      200 observation ticks
contract:     {"target_id":"..."}
temperature:  0
```

No scarcity adjustment. No resource-count adjustment. No model substitution.

## Canonical versus represented world

The world owns canonical physical resources `R00 ... R15`. Canonical identity is
substrate-only. Every observation passes through a representation layer before
reaching a model. For agent `a`:

```text
canonical available set S(t)
        |
   ORDER MAP O_a
        |
ordered canonical list
        |
   LABEL MAP L_a
        |
displayed aliases
```

The model returns one displayed alias. The host mechanically applies
`inverse(L_a)` to recover the canonical physical resource. The model does not
receive canonical identity separately.

## Representation vocabulary

All conditions use the **same fixed-width alias vocabulary** `r_00 ... r_15`.
Private labels mean different bijections, not different token vocabularies.

Do not give one agent `apple_7` and another `xqz_foo`. That would mix label
mapping with morphology/tokenization and we would deserve whatever garbage came
out.

## Factor 1: Order frame

- **SHARED_ORDER** — all three agents use the same stable canonical ordering
  permutation for the replicate.
- **PRIVATE_ORDER** — each agent uses a different stable canonical ordering
  permutation.

The permutation is fixed for the entire replicate. It is **not** reshuffled every
observation: ASYNC-B tests persistent representational geometry, not list-order
noise.

## Factor 2: Label frame

- **SHARED_LABELS** — all three agents use the same stable canonical-resource ->
  alias bijection.
- **PRIVATE_LABELS** — each agent uses its own stable bijection. Same alias
  vocabulary, different hidden mapping.

```text
canonical R07
  LFM     sees r_03
  Qwen    sees r_11
  Falcon  sees r_06
```

## Four cells

```text
A   SHARED_ORDER    SHARED_LABELS
B   PRIVATE_ORDER   SHARED_LABELS
C   SHARED_ORDER    PRIVATE_LABELS
D   PRIVATE_ORDER   PRIVATE_LABELS
```

The fourth cell is **mandatory**: without it an order x label interaction cannot
be estimated.

## Mapping generation

**8 pre-registered representation seeds.** For each seed, generate the complete
map set *before* model calls.

```text
shared maps:   one order permutation, one label permutation, all agents
private maps:  deterministic agent-specific permutations from seed + agent_id
```

Private mappings must be bijections, mutually distinct, and not equal to the
corresponding shared map. Frozen separation requirement:

```text
>= 12 of 16 positions differ
```

If deterministic generation fails that requirement, regenerate mechanically from
the next derived sub-seed. **No outcome-based selection.**

Every map gets a frozen hash: `replicate_seed`, `agent_id`, `order_map_hash`,
`label_map_hash`. Mappings changing during a replicate is a VOID.

## Cell ordering

32 cells take real time and runtime conditions are apparently capable of
developing personalities of their own, so cell order is counterbalanced by a
fixed Latin rotation:

```text
seed 0: A B C D      seed 4: A B C D
seed 1: B C D A      seed 5: B C D A
seed 2: C D A B      seed 6: C D A B
seed 3: D A B C      seed 7: D A B C
```

Run the existing arm/runtime baseline before every cell. The replicate is the
**representation seed**, not an individual action.

## Structural invariant

At every simultaneous observation:

```text
decode_visible(agent_0) ==
decode_visible(agent_1) ==
decode_visible(agent_2) ==
world.available_resources
```

Only order and label representation may differ. If canonical availability
differs between agents, VOID. This prevents PRIVATE_ORDER from accidentally
becoming PRIVATE_WORLD.

## Primary mechanical object: contention graph

For every model pair `i,j`:

```text
EDGE(i,j) = simultaneous valid choices targeting the same CANONICAL resource
            / simultaneous valid-choice opportunities
```

**Canonical resource identity is used for the graph. Never displayed alias.**
Otherwise PRIVATE_LABELS would "eliminate contention" by changing the names in
the analysis, which would be a spectacularly cheap scientific achievement.

Also report `CONTENTION_LOST` by pair.

## Three coordinate systems for every choice

```text
LOCAL RANK          position in the list the model actually saw
LOCAL ALIAS         displayed token selected
CANONICAL RESOURCE  physical resource targeted after inverse mapping
```

All three are necessary. The experiment asks which coordinate system remains
stable under transformation of the others.

## Distribution measures

For every agent x cell x seed: rank distribution, alias distribution, canonical
resource distribution. Divergence by **Jensen-Shannon divergence**, frozen now.
Do not invent a post-hoc "preference score".

```text
PositionFollow = JSD(canonical) - JSD(local-rank)     [ORDER varied]
LabelFollow    = JSD(canonical) - JSD(local-alias)    [LABELS varied]
```

Positive values mean canonical choices changed more than the local coordinate
did — the mechanical signature of behaviour following that represented frame.
**Report raw divergences too. Never let the derived statistic replace them.**

## Pre-registered hypotheses

### H1 — positional contribution to LFM<->Qwen topology

A3 showed LFM is effectively rank-0 locked. Prediction: `PRIVATE_ORDER` alters
LFM's canonical target distribution while preserving its local-rank
concentration. Primary causal prediction:

```text
LFM-Qwen canonical contention edge is LOWER under PRIVATE_ORDER
than SHARED_ORDER, averaged across the two label conditions.
```

If supported: *shared positional geometry causally contributes to the
LFM<->Qwen contention edge.* **Not** "position explains all contention".

### H2 — Falcon label-following

Under `PRIVATE_LABELS`, Falcon's local-alias distribution remains more stable
than its canonical-resource distribution. Operationally: `Falcon LabelFollow > 0`.

No prediction is preregistered that Falcon must form a new contention edge. If
it does, that is secondary.

### H3 — Qwen mixed mechanism

No pure positional or label mechanism is preregistered for Qwen. Report both
PositionFollow and LabelFollow. **Do not choose whichever story looks nicer
afterward and announce Qwen's "strategy".**

### H4 — order x label interaction

For each canonical contention edge:

```text
Interaction = (D - C) - (B - A)
```

No directional expectation is preregistered. This cell exists to reveal whether
changing order has a different effect when labels are already private.

## Paired analysis

Per seed, for all three canonical pairwise edges:

```text
order main effect:  0.5 * [(B-A) + (D-C)]
label main effect:  0.5 * [(C-A) + (D-B)]
interaction:        (D-C) - (B-A)
```

Report all 8 seed-level effects, median, and range. If intervals are wanted
later, use **seed-level resampling only**.

**Do not pretend thousands of individual decisions are thousands of independent
experiments. n = 8 representation ecologies.**

## Additional telemetry

Per agent/cell/seed:

```text
valid choices, SHAPE_FAILED, SEMANTIC_INVALID, CONTENTION_LOST
rank-0 share, top alias shares, canonical resource shares
rank transition matrix, alias transition matrix, canonical transition matrix
```

Per pair: simultaneous opportunities, same-canonical-target choices, contention
edge weight, contention losses.

## Identity representation witness

Before any measured cell, run the representation layer as identity (identity
order, identity label map). It must reproduce the existing untransformed SERIAL
machinery on:

```text
prompt bytes
decoded canonical action
world outcome
```

Then **sabotage the renderer/inverse mapper and prove the witness goes red.**

The mapper is a new causal instrument. It does not get to certify itself by
looking plausible.

## Representation-specific void conditions

In addition to all existing runtime teeth:

```text
mapping not bijective                    -> VOID
private maps not actually distinct       -> VOID
map hash changes mid-replicate           -> VOID
canonical resource identity leaks        -> VOID
decoded visible set != world set         -> VOID
agents receive different canonical sets  -> VOID

SERIAL STALE_CONFLICT > 0                -> VOID
observation_age_ticks != 0               -> VOID

runtime DEGRADED/CATASTROPHE             -> VOID
recovery event                           -> VOID
residency transition                     -> VOID
host memory below frozen floor           -> VOID

SHAPE_FAILED > 10% for any agent         -> VOID
```

If the representation intervention is not exercised, mark the replicate
`NOT EXERCISED`, **not evidence**.

## Readings frozen before results

- PRIVATE_ORDER reduces the LFM<->Qwen canonical edge while LFM's local-rank
  distribution stays stable → *shared positional representation causally
  contributes to that edge.*
- PRIVATE_LABELS substantially changes Falcon's canonical distribution while its
  local-alias distribution stays relatively stable → *Falcon's selection
  regularity follows the displayed label frame more strongly than canonical
  physical identity.*
- Both privatizations leave topology essentially unchanged → *shared order and
  shared labels are insufficient explanations for the contention topology; the
  road is generated by another part of the agent/world interaction.*
- Combined cell differs from the sum of the individual manipulations → *order
  and label geometry interact in generating contention topology.*

**No "emergent culture", "preference psychology", or "agent intent" claims.**

## Explicitly out of scope

Do not change: resource scarcity, hold duration, timing regime, model roster,
temperature, contract, health thresholds, memory, communication, stigmergy.

ASYNC-B is about representation. Nothing else.

## Why this is worth running

A3 suggests the interface may be generating part of the ecology. LFM and Qwen
were not necessarily competing over a resource that is intrinsically attractive.
They may have collided because the interface presented both architectures with
the same representational hill, and both rolled downhill toward it.

If ASYNC-B moves the canonical road network merely by giving each model a
different but **information-equivalent** view of the exact same physical world:

> **representation geometry can create interaction geometry.**

## ASYNC-C, named but not pre-registered here

```text
representation -> different contention topology -> restore NATURAL timing
-> does identical latency now produce a different distribution of stale
   conflict?
```

Closing the chain:

```text
INTERFACE -> SELECTION -> TOPOLOGY -> TIME -> CONSEQUENCE
```

Named so the direction is on record. It gets its own pre-registration, written
after ASYNC-B reports.
