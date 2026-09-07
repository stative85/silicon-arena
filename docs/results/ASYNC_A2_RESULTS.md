# ASYNC-A2 — Run 1 results

Run executed in the frozen order at prereg `0241dd0`, roster lfm2.5 + qwen3.5 +
falcon, world 16 resources / hold 4, 3 agents, 800 observation ticks, 250 ms
tick, 1000 ms equalizer (4 ticks), contract hash `f5a2aaf89dfa6ffa`, genesis
hash `c16b1d7ae8e2fd50` identical across all four arms.

Nothing was tuned, retried, or repaired during the run.

## Classification

```text
ASYNC-A2 RUN 1

PRIMARY ASYNC-A TEST:
NO RESULT / INCONCLUSIVE

SERIAL:
VOID - runtime health event

EQUALIZED:
VOID - preregistered equalizer breaches

NATURAL:
mechanically completed, but RUNTIME INTEGRITY INCOMPLETE
not confirmatory evidence

ORDER_REPLAY:
mechanically completed,
inherits NATURAL's runtime-integrity uncertainty
exploratory counterfactual only
```

**Why NATURAL is not called valid.** Part of the preregistered
runtime-integrity instrument was never exercised (see the Gate 4 defect below).
A missing check cannot become evidence because independent evidence makes us
feel confident nothing happened. `lms ps` showing the pool resident afterwards
is reassurance, not time travel: a transient eviction and restore that the live
runner never recorded cannot be retroactively observed. NATURAL and
ORDER_REPLAY therefore completed **mechanically**, and neither is confirmatory.

A2 is preserved exactly as it happened. The repairs below are ASYNC-A3, not a
re-run of A2.

## Arm outcomes

| arm | verdict | actions | ACCEPTED | STALE_CONFLICT | SEM_INVALID | CONT_LOST |
|---|---|---|---|---|---|---|
| SERIAL | **VOID** (runtime) | 2400 | 2000 | 0 | 0 | 400 |
| NATURAL | completed, integrity incomplete | 1080 | 881 | 194 | 4 | 1 |
| EQUALIZED | **VOID** (2 equalizer breaches) | 600 | 402 | 198 | 0 | 0 |
| ORDER_REPLAY | completed, exploratory only | 1080 | 881 | 193 | 5 | 1 |

Shape failures: **0** in every arm, all three agents. The roster qualification
gate did what it was for — the interface pathology that voided ASYNC-A Run 1
did not recur.

## The preregistered comparison is not available

ASYNC-A2's primary contrast is SERIAL vs NATURAL vs EQUALIZED. Two of those
three live arms are void. **The main comparison cannot be made from this run**,
and no partial version of it is reported: comparing NATURAL against a void
SERIAL would be exactly the rescue the protocol forbids.

What remains is one mechanically completed live arm whose runtime integrity
was not fully instrumented, and one counterfactual built from it that inherits
that uncertainty.

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
the lowest breach (1012 ms) -- a separate population of two, not a tail. Both
members are the tick-0 burst, and the reason turns out not to be latency.

**THE BREACHES ARE AN INSTRUMENT ARTIFACT.** Found after the run, by tracing
why `end_resident_set` was empty and then checking the other clock assumptions.

`_run_start_ms` was declared, documented at its own declaration as "set when the
tick loop actually begins", and **never assigned**. It stayed 0 for the whole
run, which anchors world time to *engine start*. Measured directly from the A2
corpora, `submitted_ms - tick*250`:

```
                tick 0        after tick 400
NATURAL         417-418 ms    6 ms
EQUALIZED       407-418 ms    7 ms
```

Godot boot plus the bridge residency handshake takes ~410 ms, so tick 0's
deadline had already passed before the first observation existed; the clock then
silently resynchronised once real time caught up with it.

Against the submission instant rather than the unanchored clock:

```
agent    submitted   completed   from submission   from the unanchored clock
agent_0    407 ms      605 ms        198 ms              605 ms
agent_1    408 ms     1012 ms        604 ms             1012 ms   BREACH
agent_2    418 ms     1068 ms        650 ms             1068 ms   BREACH
```

Both breaches completed **604 ms and 650 ms after they were submitted**,
comfortably inside the 1000 ms equalizer. They breached only because the
deadline was measured from a moment 410 ms before the run began.

The cold-start queueing is nevertheless real and visible in the same numbers:
198 ms for the first agent against 604 and 650 ms for the two that waited behind
`max_active = 2`. It just was not, on its own, enough to breach.

**The Gate 1 calibration could not have caught either problem.**
`tools/async_equalizer_check.gd` fires a warmup burst and discards it before
collecting, so it excluded the cold-start regime by construction -- and being
bridge-only, it never exercised the world clock at all.

Two defects, then, and the reportable consequence is the same:
**the 1000 ms constant is not disproven; the procedure that qualified it is.**
Nothing was changed during the run. The gate fired, and a fired gate wins.

## ORDER_REPLAY vs NATURAL — exploratory counterfactual

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

Supported, and the claim is kept deliberately tiny:

> In this one NATURAL trajectory, under this fairly resource-rich world, the
> frozen ordering inversion changed history but barely affected mechanically
> successful allocation.

Not "ordering does not matter". Sixteen resources against three agents gives
ordering plenty of chances to be irrelevant.

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
instrument partway through.

**The guard is NOT retrofitted to rescue these arms.** Wiring it now and then
declaring NATURAL valid would be exactly backwards: the check would run against
a replicate whose transient residency events, if any, were never recorded. The
integration lands in ASYNC-A3 and applies only to runs made after it.

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

## Status: NO CONFIRMATORY RESULT

- SERIAL r0 — **VOID** (runtime health). Artifacts preserved.
- NATURAL r0 — completed, runtime integrity incomplete. Not confirmatory.
- EQUALIZED r0 — **VOID** (equalizer breach). Artifacts preserved.
- ORDER_REPLAY r0 — completed, exploratory counterfactual only.
- Primary three-arm comparison — **no result**.

A2 is closed. It is not re-run; the repairs become ASYNC-A3.

### Four findings this run earned

1. **Gate 4 integration defect** — residency guard never wired to the live
   runner. Repair in A3.
2. **Equalizer qualification defect** — the gate warmed up and so excluded the
   cold-start regime that later voided the arm. The 1000 ms constant is **not
   disproven**; the procedure that qualified it is. Repair in A3.
3. **Recovery-neighbour coupling** — a new measured bridge failure mode, which
   legitimately opens the closed-infrastructure wall for investigation. See
   `docs/results/RECOVERY_COUPLING.md`.
4. **Unanchored world clock** — `_run_start_ms` never assigned, anchoring world
   time to engine start and manufacturing the EQUALIZED void. Repair in A3.

All four are repaired or tracked in `docs/EXPERIMENT_ASYNC_A3.md`. None of them
makes A2 confirmatory.

Nothing was deleted. Nothing was retuned. No prompt rescue, no per-species
patching, no metric surgery.
