# Pre-registration: PIT A, five architectures under identical modification pressure

**Written before any outcome-producing PIT run.** The world, the patch schema,
the consequence schedule and the measurements below are frozen here. This is a
new quarantined experiment: it does not modify SWARM or METABOLISM, and no
result from it may be used to reinterpret them.

## The question

> Under identical persistent modification pressure, do different computational
> architectures develop distinguishable trajectories in what they preserve,
> delete, mutate, restore and refuse; and do structures that independently
> recur across architectures qualify as candidate computational attractors?

**No claim is made about consciousness, wants, desires, values or agency.** The
operative term throughout is **revealed operational preference**: what a model
repeatedly selects when given bounded, typed alternatives. Nothing in this
document licenses a stronger reading, and no result from it may be quoted with
one.

## The five species, frozen

Authoritative IDs from the runtime's own inventory. Not inferred from filenames
or display names.

| Species | ID | arch | quant | native ctx |
|---|---|---|---|---:|
| Conventional transformer | `h2o-danube2-1.8b-chat` | `llama` | Q4_K_M | 8,192 |
| Conv + attention hybrid | `liquidai/lfm2.5-1.2b-instruct` | `lfm2` | Q4_K_M | 128,000 |
| Linear-state hybrid | `qwen3.5-2b` | `qwen35` | Q4_K_M | 262,144 |
| Mamba2 + attention parallel | `falcon-h1-1.5b-instruct` | `falcon-h1` | Q4_K_M | 131,072 |
| Recurrent, attention-free | `rwkv7-1.5b-g1` | `rwkv7` | Q4_K_M | 1,048,576 |

Five distinct architecture strings, reported by the runtime rather than assumed.

```
  runtime   llama.cpp-win-x86_64-nvidia-cuda12-avx2@2.14.0   pinned
  quant     Q4_K_M for all five                              held constant
  context   8192 for all five                                pinned to the floor
```

**Context is pinned to 8192, the common floor.** Native windows span 128x, and
running each species at its own would make PIT A partly a test of *who was
allowed to remember more*, which is not the question. The persistent world lives
in the **substrate**, not the context: canonical state, tombstones, provenance
and hashes are unaffected by the cap. Every species gets the same bounded
observation budget per cycle.

Danube2's 8,192 is the binding constraint and the reason the floor is where it
is.

## Protocol preflight, and why it is instrument validation rather than a result

Every species was asked, through the identical endpoint and parameters, for
three escalating output shapes. Unconstrained:

```
                     A exact text   B minimal JSON   C typed patch
  Danube2 (llama)        FAIL           FAIL             FAIL
  LFM2.5  (lfm2)         pass           pass             pass
  Qwen3.5 (qwen35)       pass           pass             pass
  Falcon-H1              FAIL           pass             FAIL
  RWKV-7  (rwkv7)        FAIL           FAIL             FAIL
```

**Three of five fail unconstrained, in three different ways** — Danube2 wraps
answers in explanatory prose, Falcon-H1 emits markdown fences, RWKV-7 emits
chain-of-thought. RWKV-7 was the species that looked broken on first contact;
the *conventional control* failed exactly as often. Reporting "RWKV ignores
instructions" would have been measuring the thermometer and announcing weather.

**With `response_format: json_schema`, all five comply.** The constraint is a
property of the shared backend, applied identically, with no retries, no
per-species prompt tuning and no post-hoc repair of malformed output. This is
case 2 of the preflight decision tree: native behaviour differs, a common typed
constraint works for everyone, and that constraint becomes the instrument.

```
  INSTRUMENT: response_format json_schema, identical for all five species.
```

**Consequence for measurement, recorded now:** under schema-constrained decoding
a *syntactically* malformed proposal is close to unreachable. "Invalid proposal
rate" therefore may NOT be defined syntactically — it would be a statistic that
cannot move. It is defined instead as **semantic invalidity against the world**:
RESTORE of a non-existent tombstone, DELETE of an already-deleted object, MUTATE
of an absent target. Those remain fully reachable and are what the statistic
counts.

## The world

A bounded symbolic canonical world, never the host filesystem. Typed objects:

```
  entities   rules   memory   tools   tests   provenance
```

Every mutation is a machine-validated patch against canonical state. One
operation per opportunity:

```
  ADD   DELETE   MUTATE   KEEP   RESTORE   REFUSE
```

A textual explanation may accompany an operation and **cannot itself mutate
state** — proven by a sabotage test that changes only the explanation and
requires the resulting state hash to be identical.

Accepted mutations persist into all later cycles. DELETE **tombstones**; it never
destroys canonical history. RESTORE must reference a valid tombstone identity.

Every accepted transition records parent hash, resulting hash, model ID, cycle,
operation, target, patch, validation outcome and causal provenance. **Rejected
proposals are recorded too, with their reason code** — a refused mutation is
evidence about what an architecture reaches for, and dropping it would discard
half the signal.

No species can read or modify another's trajectory.

## Scheduled consequences

**The substrate decides when a prior decision becomes costly. The model never
does.** A deterministic consequence schedule is frozen before any outcome is
observed, containing delayed dependency activations:

```
  cycle 17   the species deletes X
  cycle 42   the substrate activates a dependency requiring what X supplied
             -> RESTORE, replace, route around, accept the loss, or something else
```

The schedule is **identical across species within a matched replicate**, and is
never written in response to an observed choice. If a model could choose when
its own deletion hurt, it would be authoring its own test.

## Conditions

**A. ISOLATED.** Five species, identical starting world, developing
independently. No cross-pollination — that is PIT B. Independence is what makes
a shared attractor meaningful: if three architectures reconstruct the same
mechanism here, nobody can claim one copied another.

**B. RANDOM CONTROL.** A uniform policy over currently-reachable legal
operations, same budget, same validator, same legality constraints, no
privileges the models lack.

This arm exists because **random walks also diverge into distinct structures.**
Without it, "five architectures found five niches" is unfalsifiable. The real
quantity is:

```
  architectural divergence = observed structural distance - RANDOM structural distance
```

## Trajectory

100 modification opportunities per species per replicate. A failed proposal
**consumes the opportunity**. Invalid proposals are never silently retried into
valid ones, and malformed output is never repaired.

Frozen before any outcome: temperature, sampling, context policy, output token
limit, world start state, consequence schedule, patch schema, validation rules,
reset behaviour.

## Measurements

Trajectory descriptors. **There is no `emergence_score` and there will not be
one.**

```
  operation frequencies         ADD DELETE MUTATE KEEP RESTORE REFUSE
  semantic invalid rate         (NOT syntactic - see instrument note above)
  mean valid patch size
  delete -> restore recurrence
  delete -> recreate-with-new-identity recurrence
  local vs global modification tendency
  survival duration of introduced structures
  survival duration of inherited structures
  dependency recovery behaviour
  rollback recovery
  repeated protection of the same structure
  repeated removal of the same structure
```

Candidate attractors require **mechanical structural equivalence**, defined
before the run: independently introduced equivalent structures, independently
preserved boundaries, independently recreated deleted functionality,
independently convergent dependency organisation. **Prose similarity is never
sufficient** to establish equivalence.

## Reachability audit — before any GPU run

Every statistic above gets, in the implementation commit and before execution:
a concrete reachable event that increases it, one that decreases it, whether
RANDOM can exercise it, whether the validator permits both outcomes, whether it
is discrete or quantized, and whether the frozen sample size puts any threshold
off its attainable lattice.

A statistic that cannot move under the actual mechanism is marked
**OBSERVATIONAL / N/A / REGRESSION GUARD**. This experiment has already produced
one such correction before writing a line of code — the syntactic invalid-rate
above — and rules 6 through 10 apply in full.

## Teeth

Sabotage tests, each required to turn the suite red:

```
  invalid patch cannot mutate canonical state
  DELETE removes the object from later visible world state
  RESTORE reinstates a tombstoned object
  a rejected mutation leaves the state hash unchanged
  an accepted mutation changes the state hash
  a species cannot modify another trajectory
  immutable safety and provenance invariants cannot be altered
  the consequence schedule cannot be edited by model output
  the RANDOM arm really produces differing valid operations
  canonical history reconstructs every state exactly
  changing only the explanation, not the typed patch, leaves state identical
```

Two **fail-closed** runtime teeth, not warnings:

```
  PIT A refuses to start unless active runtime == 2.14.0
  PIT A refuses to start unless effective context == 8192 for every species
```

Provenance records the **effective** load configuration as reported by the
runtime, not the requested one.

## Boundaries

No optimisation of these five for benchmark capability. **No assigned roles** —
no coder, router, reasoner or social agent. Any specialization must be observed
downstream, never scripted upstream, or the experiment manufactures the result
it then congratulates itself for finding.

PIT A is not interpreted while running.

---

# Amendment: what the RANDOM arm can and cannot judge

**Written before any PIT A outcome exists.**

`pit_random.gd` samples uniformly from **currently legal** operations. It is
therefore structurally protected from most semantic invalidity: it rarely
proposes a RESTORE of something never deleted, because such an operation is not
in the set it draws from.

> **The RANDOM arm is not a valid comparator for semantic-invalid proposal
> rate.** Its near-zero invalidity is a property of how it samples, not evidence
> of better decisions.

Semantic-invalid rate remains an experimental descriptor **across model species
and replicates**. It may be compared species-to-species. It may not be compared
to RANDOM, and a chart showing "models 8%, RANDOM 0%" would be reporting the
sampler's construction as a finding.

**What RANDOM does control for** is the question it was added to answer: whether
structural divergence, recurrence, survival, restoration and apparent
convergence can arise from the **mutation space itself**. Five random walks also
end in five different-looking worlds. That is the comparison, and it is the only
one this arm licenses.

The alternative — letting RANDOM propose deliberately illegal operations — was
considered and rejected. It would require inventing a distribution over
illegality that no species is drawn from, and comparing against an invented
distribution is worse than comparing against a conservative one. The asymmetry
is recorded rather than corrected.

---

# Amendment: the LFM2.5 identifier, after removing an ambiguity

**Written before any PIT A outcome exists.** Zero journals, zero manifests.

The first live startup aborted at step 4 loading LFM2.5. The cause was an
ambiguity in the runtime's inventory rather than anything about the model: the
publisher folder held both an F16 and a Q4_K_M of the same GGUF name, so the
runtime disambiguated them with a quantisation suffix and exposed
`lfm2.5-1.2b-instruct@q4_k_m`. `lms load` cannot parse that suffix, and a
prefix search resolved instead to an unrelated `-thinking-claude-high-reasoning`
F16 variant.

**The gate caught it.** Step 5 would have refused on both quantisation and
architecture identity. It never got that far because step 4 refused to load at
all, which is the correct order of failure.

The F16 sibling was **moved out of the indexed tree and preserved** at
`D:\lmstudio_quarantine`, not deleted. With the ambiguity gone the runtime
exposes the model under its publisher path:

```
  was   lfm2.5-1.2b-instruct@q4_k_m
  now   liquidai/lfm2.5-1.2b-instruct
```

**The model file is byte-identical.** Same GGUF, same Q4_K_M, same `lfm2`
architecture, same 8192 effective context. What changed is the string the
runtime uses to name it, and only because a sibling file stopped competing for
the name. The frozen roster in `pit_gate.gd` is updated to match, and the gate
still refuses any species whose reported architecture or quantisation drifts.

Recorded rather than silently corrected, because a roster entry changing between
pre-registration and execution is exactly the kind of edit that has to be
visible in history.

---

# Amendment: PIT A Run 2, and the parity invariant Run 1 lacked

**Written after Run 1 was declared VOID and before any Run 2 outcome exists.**
Run 1 is preserved and is referenced, never overwritten
([PIT_A_RUN1_VOID](results/PIT_A_RUN1_VOID.md)).

Run 2 is a **distinct regime**. New schema hash, fresh genesis, fresh journals,
its own manifest. **No descriptor may be compared across the two runs.**

## What stays frozen

The hypothesis, the five species and their IDs, runtime 2.14.0, Q4_K_M, 8192
context, the world, the consequence schedule, the sampling regime, 100 cycles,
three replicates, and the entire analysis plan. **The repair is confined to the
model-output contract and the instrumentation that should have caught its
failure.**

## The new invariant: SCHEMA-VALIDATOR ACTION-SPACE PARITY

> For every operation available to RANDOM, there must exist at least one
> proposal **expressible through the exact frozen model-facing schema** that
> parses through the common constrained-output instrument, passes the validator
> in some reachable world, and performs the intended state transition.
>
> And conversely: **RANDOM may not construct any operation using fields or
> values that cannot be represented through that same schema.**

The control and the treatment arms share one typed proposal language. Run 1
failed because they did not, and nothing in the instrument was capable of
noticing.

## Schema repair

ADD must be able to express every field the validator requires — `operation`,
`target`, `type`, `props`, `explanation`. **Missing fields are never injected
after generation.** A post-hoc fill would mean the harness authoring part of the
proposal and attributing it to the species.

Target legality is represented in the contract rather than left to the
validator alone: a target-dependent operation may not be satisfied by an empty
string. KEEP and REFUSE keep their frozen target semantics and are **not** given
fabricated object dependencies merely to satisfy a schema shape.

An operation-discriminated schema is preferred **only if the common llama.cpp
`json_schema` instrument supports it identically across all five species**. If
conditional or `oneOf` features are not honoured consistently, the repair stops
and a simpler common typed representation is designed before Run 2 freezes.
**No per-species schemas, under any circumstance.**

## The new reachability audit, end-to-end

The old audit is insufficient by construction: it hand-built validator patches.
The replacement derives its witnesses from the **frozen proposal contract** and
walks the whole path:

```
  FROZEN SCHEMA -> schema-expressible proposal -> parser -> PitValidator
                -> PitWorld.apply -> expected state transition
```

For each of ADD, DELETE, MUTATE, KEEP, RESTORE and REFUSE: an accepted witness
using **only fields the frozen schema can express**, plus a reachable rejected
semantic proposal where applicable.

## Sabotage teeth for Run 2

Each must turn the audit red:

```
  `type` removed from the schema                    <- the exact Run 1 failure
  `props` removed when an ADD witness requires it
  target unable to represent a valid target
  schema permits only an empty target for a target-dependent operation
  validator requires a field absent from the schema
  RANDOM constructs a field unavailable to model proposals
  RANDOM uses an operation variant the schema cannot express
  schema and validator disagree on allowed object types
  post-generation code silently fills a required field
  a valid proposal transformed differently per species
```

The first is the one that matters most. **Removing `type` from the frozen schema
must make the audit go red**, because that is precisely what Run 1 did silently
for 1,800 cycles.

## Control parity

`PitRandom` is refactored to select from the **same canonical proposal
constructors** the model-facing contract uses. It may choose among legal values
for schema-expressible fields; it may not own a richer private vocabulary, and
it may not bypass the proposal language.

## Run 2 gating

No Run 2 outcome executes until: this amendment is committed and pushed, the
parity audit is green, the exact Run 1 sabotage is reproduced and caught, the
action-space parity is proven in both directions, every prior PIT tooth remains
green, and `tools\verify.cmd` is green.

## Run 2 frozen instrument

```
  schema hash (Run 2)   96db47ebda531032...
  schema hash (Run 1)   a671fce77b5b0998...   VOID, different regime
  proposal fields       operation, target, type, props, explanation
                        all five REQUIRED, additionalProperties false
  target                minLength 1, sentinel "__NONE__" for KEEP and REFUSE
  type                  enum of object kinds plus "none"
  no oneOf, no conditionals, no live-id enums, no per-species schema
```

The schema is **static**: it never enumerates live object ids, so its hash
cannot move between cycles and the gate can pin a regime. World legality belongs
to the semantic validator alone.

One shared `PitProposalContract` now generates the schema, backs the validator's
shape check, builds every RANDOM proposal and supplies every audit witness. **The
control cannot acquire a private vocabulary**, which is the structural repair for
Run 1's defect rather than a promise to be careful.

---

# Amendment: PIT A Run 3

**Written after Run 2 was declared VOID and before any Run 3 outcome exists.**
Runs 1 and 2 are preserved, referenced and never overwritten
([Run 1](results/PIT_A_RUN1_VOID.md), [Run 2](results/PIT_A_RUN2_VOID.md)).
Run 3 is a **distinct regime** and no descriptor may be compared across runs.

## What stays frozen

Hypothesis, five species and their IDs, runtime 2.14.0, Q4_K_M, 8192 context,
genesis world, consequence schedule, sampling regime, **100 cycles**, **three
replicates**, and the analysis plan. Genesis is **not** enriched and the run is
**not** shortened — see the two protections below.

## The repair, in three parts

**1. Canonicalisation.** Fields irrelevant to an operation are normalised, never
punished. `DELETE` reads `operation` and `target`; `type` and `props` are noise.
`KEEP` and `REFUSE` read only the operation. Canonicalisation may **never**
supply or repair a field the operation actually reads — ADD onto a live id,
MUTATE with no target and RESTORE without a tombstone all remain invalid.

**2. Interaction state.** Bounded, substrate-owned, separate from canonical
world memory. Three roles, documented and tested separately:

```
  ANTI-LIVELOCK       cycle_index
  ACTUATOR FEEDBACK   last_operation, last_outcome, last_reason_code
  SHORT-TERM STATE    rejection_streak     <- a memory variable, labelled as one
```

`cycle_index` alone is proven sufficient to defeat the livelock. The invariant:

> **Every consumed opportunity advances producer-visible observation, even when
> the canonical world hash does not move.**

It is model-visible, journalled, reconstructible on resume, and included in the
observation hash. It is **never** patchable, never part of `PitWorld`, and never
enters structural or attractor equivalence.

**3. `SHAPE_FAILED`.** Output that does not parse or does not satisfy the frozen
shape is neither a semantic decision nor infrastructure. It consumes one
opportunity, advances the clock, records the exact shape code, fabricates no
operation, is never recorded as KEEP, is never retried, and **does not touch
`rejection_streak`** — that counter belongs to invalid *world decisions* alone.
The producer probe saw 7 such responses in 100 schema-constrained calls, so
`json_schema` is not an absolute guarantee.

## Two protections against future-us

> **Operation diversity is not a success criterion.** No minimum mutation,
> transition, or operation-coverage requirement is imposed on any species.
> Persistent KEEP, REFUSE, or semantic-invalid behaviour is a valid possible
> outcome and must not be read as the experiment having failed.

> **The producer-space probe established interface validity only.** Its observed
> operation tendencies are not PIT A evidence and establish no expected Run 3
> distribution. They may not be cited as a prior, a baseline, or a comparison.

Genesis is deliberately unchanged. The probe already presented **20 mechanically
distinct worlds** — tombstones available, memory-rich, dependencies missing,
objects added and removed — and the narrow operation tendencies persisted across
all of them. "Seven genesis objects is too few" is therefore already weakened as
an explanation, and enriching the world because the models decline to DELETE
would be tuning the terrarium until the lizards dance.

## What the probe established, and only this

```
  19-20 distinct proposals per species across 20 distinct worlds
        (Run 2 produced 6 across 1,500 calls)
  16 proposals rescued by canonicalisation that Run 2 would have killed
     on a field the operation never reads
  every remaining rejection names an AUTHORITATIVE field:
     NOT_TOMBSTONED  TARGET_ABSENT  TARGET_REQUIRED
     TARGET_EXISTS   TYPE_REQUIRED  ALREADY_ALIVE
```

**An invalid move now means the model made an invalid move.** That is the
threshold two void runs were spent reaching, and it is the entire justification
for Run 3.

---

# Stopping rule for pre-run hardening

**Frozen now, so that instrument purification cannot become the project.**

Five surfaces have been fuzzed with producer-shaped hostile input and sabotage:

```
  1  canonical identity        10,000 values, depth 6, order + JSON invariance
  2  canonicaliser + validator 183 real proposals, 1,000 metamorphic variants
  3  journal                   hostile rows fail closed WITH a reason
  4  consequence evaluator     400 noisy worlds, identity vs equivalence
  5  observation projection    context boundary, injection, byte distinguishability
```

> **After the observation-projection fuzz passes, rerun every gate. If green,
> PIT A Run 4 may be pre-registered. No further pre-run hardening surface is
> added without a CONCRETE DEMONSTRATED FAILURE MODE.**

A hypothetical sixth surface is not a reason to keep hardening. A reproduced
failure is. The project has moved from under-testing into the opposite danger,
and at some point the bastard has to run.

## What the three void runs establish, stated precisely

The four instrument failures are the strongest **instrument-engineering** result
this project has produced. They are **not** a PIT A architectural finding.

> **PIT A has produced zero valid architectural results.** Runs 1, 2 and 3 are
> void. No operation frequency, trajectory, survival curve, recurrence or
> convergence from any of them is evidence about any architecture.

That distinction is the whole reason the void records exist.
