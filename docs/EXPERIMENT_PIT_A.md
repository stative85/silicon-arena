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
| Conv + attention hybrid | `lfm2.5-1.2b-instruct@q4_k_m` | `lfm2` | Q4_K_M | 128,000 |
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
