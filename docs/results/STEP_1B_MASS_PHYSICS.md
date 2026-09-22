# Step 1B, claim 1 — mass physics qualification

**Claim:** the reducer obeys MASS_CONTRACT_V1 under injection.
**Instrument:** `tools/mass_physics_qualify.gd` — canonical operations injected
straight into `WorldReducer.apply()`. **No model is involved.**
**Contract:** `config/mass-contract.v1.json`
**Schema:** `ACTION_SCHEMA_V1` untouched. Step 1B adds no verb.

```
  checks 99, failures 0        MASS PHYSICS GREEN      (mass_physics_qualify)
  MASS CONTRACT OK                                     (mass_contract_selftest)
```

This says nothing whatever about any species. The species half is claim 2,
`STEP_1B_SEAM_REQUALIFICATION.md`, and it is a separate claim with its own
instrument.

## The contract, as frozen

```
capacity_per_agent  4      identical for every agent, no species strength
mass_by_kind        key 1, scrap 3      intrinsic to kind, never per object
move_cost_base      4
gradient            carried <= capacity : cost = 4
                    carried >  capacity : cost = 4 + (carried - capacity)
```

`PUSH` and `DRAG` were considered and rejected. They do not exist in the
vocabulary, and inventing them would have forced an 18-verb schema and
invalidated a signed gate to buy something the gradient already provides.

## Measured, below / exactly at / above

```
  carried 0   below        -> cost 4, charged 4
  carried 1   below        -> cost 4, charged 4
  carried 3   below        -> cost 4, charged 4     one scrap
  carried 3   below        -> cost 4, charged 4     three keys, same mass
  carried 4   EXACTLY AT   -> cost 4, charged 4
  carried 5   above        -> cost 5, charged 5
  carried 6   above        -> cost 6, charged 6
  carried 7   above        -> cost 7, charged 7
  carried 9   above        -> cost 9, charged 9
```

Cost is **charged**, not merely reported. Three keys and one scrap weigh the
same and cost the same: mass is a fact about kind, not about how many things
are held.

## The gradient is not a wall

Six consecutive `TAKE`s are accepted to mass 9 against capacity 4. An agent may
knowingly overload itself; it pays at `MOVE`. `DROP` remains available while
pinned.

## Refusal is inert

An unaffordable `MOVE` is refused **before** mutation:

```
  ok   refused, reason names the shortfall
  ok   energy byte-identical
  ok   position unchanged
  ok   world hash byte-identical
  ok   agent still alive
```

Same for an absent object, an absent location, a `DROP` of something not held,
and a `GIVE` to an absent agent — each refused with the world hash byte
identical and no energy spent. The hash is taken with `HashingContext` over the
deterministic `to_dict()` projection, so "unchanged" means the bytes, not the
assertions that happened to be written.

## Atomic death spill

An agent carrying mass 7 with exactly 7 energy moves, **arrives**, hits zero,
and dies:

```
  ok   the final move is accepted
  ok   the agent reached its destination before dying
  ok   energy is exactly zero, the agent is dead, inventory is empty
  ok   spill location is the final position (room_b)
  ok   spill names every carried object [key_1, scrap_1, scrap_2]
  ok   the objects are on the floor where it died
  ok   accounted mass conserved through death
  ok   the dead agent is not schedulable
  ok   DEATH_SPILL is not in the canonical vocabulary, not agent-choosable
```

A death with an empty inventory emits no spill event.

An earlier draft of this contract said `DROP` stays available at zero energy.
That was written without the existing death rule in view, and honouring it would
have put a dead agent in the log performing a canonical operation — corrupting
the meaning of both *dead* and *agent-chosen operation*. The contract was
revised rather than the reducer twisted to obey it. `DEATH_SPILL` is
host-authored: the host moved the objects, nobody chose to.

This is also a legitimate emergent possibility rather than a safety valve: an
agent can spend its last energy reaching a place and die there, leaving its
cargo on that floor. No death hook, no intention recorded.

## Mass conversion, not a conservation exception

`USE_TERMINAL` is **not** exempt from the books:

```
  ok   active mass FELL by the converted mass (12 -> 6)
  ok   accounted mass did NOT move (12)
  ok   consumed mass holds the difference (6)
  ok   consumed object retains its kind and its mass
  ok   consumed object is on no floor, cannot be taken again
  ok   MASS_CONVERSION is not in the canonical vocabulary, not agent-choosable
```

Two totals, and the distinction is the point:

- `active_mass` — floors, inventories, vault slots. May fall through
  `USE_TERMINAL`.
- `accounted_mass` — active + consumed. **May never change.**

A consumed object stays in state with `holder = "consumed"`, keeps its kind and
its mass, and can never re-enter play. A host-authored `MASS_CONVERSION` event
records object ids, mass, terminal, agent and energy gained. An exemption is
where a leak would hide; this is a ledger entry instead.

## Determinism

Two identical injected sequences produce one world hash.

## The drift tooth, and two false-green paths closed after first review

`tools/mass_contract_selftest.gd` → `MASS CONTRACT OK`. It checks that the
accessors return the file rather than a drifted copy, that the gradient is
flat-then-linear as arithmetic, that capacity is identical across species with
no per-species strength field admitted, and that every kind in the built arena
has a declared mass.

The first version of this gate shipped two ways to be falsely green. Both were
caught in review, before signing, and both are closed.

**1. The gate read human prose.** It searched the contract's sentences for
`"not a verb"` — first case-sensitively, then, after that failed, case-
insensitively. Both were tests of the wording: rephrasing a comment could turn
the gate green or red without changing one rule of physics. The contract now
declares `host_authored_events` as **data**, and the gate asserts each name
directly against `CO.ALL` and `CO.AGENT_CHOOSABLE`. Nothing reads a sentence.

**2. An undeclared kind weighed zero.** `mass_of_kind` returned `0` for an
unknown kind. Zero is a legitimate mass — a feather is not a bug — so a contract
gap was indistinguishable from a light object and could travel the whole reducer
as a valid number. The offline check only proved the *current* fixtures were
declared; it could not prove a kind introduced later would be caught.

Now:

- `mass_of_kind` returns `MASS_KIND_UNDECLARED` (-1), which no arithmetic can
  mistake for a weight
- `MassContract.validate_world()` returns one violation per offending object,
  naming id and kind
- `BreachRound._init` validates **every object at ignition** and refuses:
  `ended = true`, `end_reason = MASS_CONTRACT_VIOLATION`, before any observation
  is built and before any tick

## Sabotage: the refusal is demonstrated, not asserted

A world containing `anvil_1` of undeclared kind `anvil` is constructed on
purpose:

```
  ok   the validator reports a violation
  ok     the violation is MASS_KIND_UNDECLARED
  ok     it names the object id (anvil_1) and the kind (anvil)
  ok   the declared object is not flagged
  ok   its mass is the violation sentinel, never 0
  ok   world hash byte-identical after validation

  ok   _init refused to start the round
  ok   it recorded the violation
  ok   the abort reason names the object and the kind
       MASS_KIND_UNDECLARED: anvil_3 (kind 'anvil')
  ok   step() produces no event once ignition has refused
  ok   no observation was emitted
  ok   world hash byte-identical after the refused step
  ok   the end reason is MASS_CONTRACT_VIOLATION, not a round outcome
```

The last block drives the **real** `BreachRound._init`, not a re-implementation
of it. `_init` gained an optional `p_world` parameter for exactly this: the
canonical layout would never produce a violating world, so without it the
ignition refusal would be a branch that had never executed, and a gate whose
abort path has never run is not a gate. Production rounds pass nothing and get
the canonical layout.

`MASS_CONTRACT_VIOLATION` is deliberately not a round outcome. The round did not
end — it never started, because the world it was built on does not satisfy the
frozen contract.

## Wired into the gate

`tools/verify.cmd` now runs `mass contract` and `mass physics` alongside the
BREACH checks. Neither requires a GPU, LM Studio, or a network.
