# ASYNC-A2 — Run 1 results

Run executed in the frozen order at prereg `0241dd0`, roster lfm2.5 + qwen3.5 +
falcon, world 16 resources / hold 4, 3 agents, 800 observation ticks, 250 ms
tick, 1000 ms equalizer (4 ticks), contract hash `f5a2aaf89dfa6ffa`, genesis
hash `c16b1d7ae8e2fd50` identical across all four arms.

Nothing was tuned, retried, or repaired during the run. Two arms voided. They
are recorded as void.

## Arm outcomes

| arm | verdict | actions | ACCEPTED | STALE_CONFLICT | SEM_INVALID | CONT_LOST |
|---|---|---|---|---|---|---|
| SERIAL | **VOID** (runtime) | 2400 | 2000 | 0 | 0 | 400 |
| NATURAL | valid, teeth OK | 1080 | 881 | 194 | 4 | 1 |
| EQUALIZED | **VOID** (2 equalizer breaches) | 600 | 402 | 198 | 0 | 0 |
| ORDER_REPLAY | valid, teeth OK | 1080 | 881 | 193 | 5 | 1 |

Shape failures: **0** in every arm, all three agents. The roster qualification
gate did what it was for — the interface pathology that voided ASYNC-A Run 1
did not recur.

## The preregistered comparison is not available

ASYNC-A2's primary contrast is SERIAL vs NATURAL vs EQUALIZED. Two of those
three live arms are void. **The main comparison cannot be made from this run**,
and no partial version of it is reported: comparing NATURAL against a void
SERIAL would be exactly the rescue the protocol forbids.

What survives is one valid live arm and one valid counterfactual built from it.

## SERIAL — void by Gate 4 at tick 508

```
t=334.6s  qwen3.5-2b   HOT -> DEGRADED       health: 3 consecutive suspect calls
t=334.6s  qwen3.5-2b   -> RECOVERING          reload, ok=false
t=349.2s  qwen3.5-2b   residual 1.84, recovery succeeded -> HOT
t=349.3s  falcon-h1    HOT -> DEGRADED        residual 60.7x >= catastrophe 20.0x
t=349.3s  falcon-h1    -> RECOVERING          reload, ok=false
t=361.8s  falcon-h1    CATASTROPHE 60.67, recovery succeeded -> HOT
```

The arm ran its full 800 ticks; the void is a health verdict, not a crash. Host
free was 4,676 MB against the 2,048 MB floor, so this is **not** an OOM.

qwen's three suspect calls sit just over the `ks = 1.8` line (the recorded
residual is 1.84). falcon's 60.7× is unambiguous and is the pathology class
`kh = 20` was reserved for.

The temporal adjacency between qwen's reload and falcon's 60.7× residual is
**recorded, not explained**. Distinguishing "a reload disrupted a co-resident
model" from "both models degraded for a shared external reason" needs evidence
this run does not contain. Proximity is not a mechanism.

The detector is not being reconsidered. It fired on a 60× residual; that is the
detector working.

## EQUALIZED — void by 2 breaches, both at tick 0

Both breaching envelopes are the **first cognition of the run**:

| agent | observed_tick | submitted_ms | completed_ms | obs→completion | outcome |
|---|---|---|---|---|---|
| agent_2 | 0 | 418 | 1068 | 1068 ms | ACCEPTED |
| agent_1 | 0 | 408 | 1012 | 1012 ms | STALE_CONFLICT |
| agent_0 | 0 | 407 | 605 | 605 ms | ACCEPTED |

The rest of the arm is nowhere near the deadline:

```
observation -> completion, 600 envelopes
  median 449 ms    p95 652 ms    max 1068 ms
  top six: 666, 668, 672, 679, 1012, 1068
```

There is a 333 ms gap between the highest steady-state completion (679 ms) and
the lowest breach (1012 ms). This is not a distribution tail. It is a separate
population of two, and both members are cold-start.

**Why the Gate 1 calibration did not predict this.** `tools/async_equalizer_check.gd`
runs a warmup burst and discards it (`_burst.clear()` after the warmup loop)
before collecting its 200 bursts. The live runner has no warmup — tick 0 is
measured. The calibration therefore excluded, by construction, the exact
condition that produced both breaches: three agents submitting simultaneously
into a cold `max_active = 2` bridge, where the third waits for a slot.

That is a defect in the **gate**, not evidence that 1000 ms is the wrong
constant. It is recorded here and **not acted on**. Changing the equalizer
constant, adding a warmup to the live arm, or excluding tick 0 from the breach
check are all amendments, and the standing rule is that a fired gate wins. This
is the second consecutive experiment in which EQUALIZED voided on breaches
(ASYNC-A Run 1: 1 breach at the same deadline), which makes it a decision worth
making deliberately rather than reflexively.

## ORDER_REPLAY vs NATURAL — the one contrast that survives

Counterfactual replay over NATURAL's envelope corpus, latency-rank inversion
within simultaneity groups. The source corpus was not mutated:

```
source corpus hash   27fc8899...4491d
replay input hash    27fc8899...4491d   (identical)
source hash after    27fc8899...4491d   (identical)
source_envelopes_mutated  0
model_calls               0     -- no inference; pure replay
```

Ordering was genuinely exercised:

```
reorderable groups     297
envelopes reordered    372
pairwise inversions    186
ordering_exercised     EXERCISED
journal_differs_from_source  true
```

Result:

```
                  NATURAL   ORDER_REPLAY
ACCEPTED              881            881
STALE_CONFLICT        194            193
SEMANTIC_INVALID        4              5
CONTENTION_LOST         1              1
journal_hash    bf3ce897...    e98c0810...   (differ)
final_world_hash  2367440b976d93c7 == 2367440b976d93c7
```

Inverting the latency rank of 372 envelopes across 297 simultaneity groups
produced **a different history and an identical final world state**, with
exactly one action changing class — from STALE_CONFLICT to SEMANTIC_INVALID,
both non-accepting, which is why the accepted set of 881 is unchanged and the
final holder map is bit-identical.

That mechanism matters: the identical hash is not a coincidence to marvel at,
it follows directly from the fact that the single reclassification moved an
action between two outcomes that both decline to grant a resource.

### What this does and does not support

Supported, for this world and this replicate: **within-tick ordering of
near-simultaneous actions is very nearly outcome-neutral here.** 186 pairwise
inversions moved one action out of 1080.

Not supported:

- **n = 1.** One replicate, no variance estimate. A single reclassification
  cannot be distinguished from noise without replication.
- `canonical_hash` covers `tick` plus each resource's **holder only** — not
  generations. Identical final hashes do not by themselves prove identical
  generation state. The equal ACCEPTED counts make divergent generations
  unlikely, but the hash does not witness it, and the claim is limited
  accordingly.
- This says nothing about worlds with tighter contention. With 16 resources,
  3 agents and a 4-tick hold, most simultaneity groups do not contend for the
  same resource. A scarcer world could behave entirely differently.

## Instrument defect found mid-run, not fixed

`AsyncRuntimeGuard.finish()` and `on_residency_poll()` are **never called by
`tools/async_a_run.gd`**. The only callers in the tree are in
`scripts/arena/async_runtime_selftest.gd`. Consequently `end_resident_set` is
empty and `end_resident_hash` is the sha of nothing in every arm.

In the live path Gate 4's residency arm is therefore **begin-only**: the pool is
witnessed once at R0 and never again. A transient eviction and restore would go
unwitnessed — which is weaker than the endpoint-only witnessing the design doc
explicitly calls insufficient. The self-test passes because it drives the guard
directly; the component is correct and the integration was never wired to it.

Scope of the damage, kept honest:

- It is a **missing check, not a wrong one**. Nothing that fired was spurious;
  the model-state arm of Gate 4 worked and voided SERIAL correctly.
- Independent evidence says the pool did hold: `lms ps` immediately after SERIAL
  showed all three models resident at 5,335 MiB against 5,339 MiB at launch.
  That is reassurance about this run, not a substitute for the check.

Not fixed mid-run — wiring the guard between arms would have changed the
instrument partway through. Whether the two valid arms stand under a retrofitted
guard is a protocol decision, not a code fix.

## Between-arm condition change, recorded

Host free memory at each arm's PRE-RUN:

```
SERIAL        4,676 MB
NATURAL      15,410 MB
EQUALIZED    11,096 MB
ORDER_REPLAY 11,467 MB
```

The jump after SERIAL is almost certainly a consequence of its two recovery
reloads. Arms were therefore not run under identical host conditions. Recorded;
not adjusted for, not corrected.

## Status

- SERIAL r0 — **VOID** (runtime health). Artifacts preserved.
- NATURAL r0 — valid.
- EQUALIZED r0 — **VOID** (equalizer breach). Artifacts preserved.
- ORDER_REPLAY r0 — valid.
- Primary three-arm comparison — **not available from this run**.

Nothing was deleted. Nothing was retuned. No prompt rescue, no per-species
patching, no metric surgery.
