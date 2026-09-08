# Treatment-aware detector audit

Night-shift audit of every integrity rule in the recovery / runtime-memory
harness. One question asked of each:

> **Can the legitimate treatment itself cause the state this detector labels as
> contamination?**

The PID tooth failed exactly that question — scheduled recovery replaces model
workers by design, and the detector called it a backend restart. This audit
looks for siblings of that defect.

No rule is changed merely because it fired historically. A rule changes only
where its protected invariant and its treatment interaction can both be stated
mechanically.

---

## Detector table

| detector | invariant protected | treatment can cause it? | flex | verdict |
|---|---|---|---|---|
| `UNEXPECTED_DUPLICATE` | exactly one instance per model | no — recovery unloads then loads | `flex_model` allows 0 or 1, **never 2+** | SOUND |
| `UNEXPECTED_DISAPPEARANCE` | pool membership | **yes**, for the recovery target | `flex_model`, one model, only during its own scheduled recovery, cleared immediately after | SOUND, flex is narrow |
| `UNEXPECTED_REPLACEMENT` | both of the above at once | no | inherits `flex_model` | SOUND |
| `UNSCHEDULED_RECOVERY` | only the schedule initiates recovery | no — executor-reported, it knows what it scheduled | none needed | SOUND |
| `UNEXPECTED_RESIDENT_MODEL` | no foreign model in the pool | no | none | SOUND |
| `RAM_FLOOR_EVENT` | host inside its qualified envelope | **yes** — demonstrated in RC Run 1 | none, deliberately | SOUND but see note 1 |
| `TRANSPORT_OR_RUNTIME_FAILURE` | the runtime answered | **yes, in two ways** | none | **DEFECT, see notes 2 and 3** |
| `BACKEND_CORE_CHANGED` | backend lifetime continuity | no — worker churn no longer counted | roles from producer structure | SOUND (replaces the defective tooth) |
| `BACKEND_GENERATION_CHANGED` | core generation identity | no | none | SOUND |
| `BACKEND_PROBE_FAILED` | the generation witness exists | no | fails closed | SOUND |

---

## Note 1 — `RAM_FLOOR_EVENT` has deliberately opposite roles

The same detector is a **void condition** in RECOVERY-COUPLING and **the
observable** in RUNTIME-MEMORY. That is not an inconsistency: RC needs a valid
resource envelope to make a causal claim, while RUNTIME-MEMORY exists precisely
to characterise leaving it.

It is treatment-causable — RC Run 1 proved the workload drives the host below
the floor — which is the Treatment-to-Observability hazard arriving through a
resource channel. It is left unflexed on purpose. The correct response is the
one already taken: void the affected scope and characterise the cause in a
separate experiment, never lower the floor.

## Note 2 — DEFECT: a neighbour timeout is indistinguishable from a broken transport

`recovery_window.gd` records `note_transport("no completion for <model>")` when a
probe does not complete inside the 60 s guard.

**The treatment can cause exactly that.** The hypothesis under test is that
recovering one model disturbs its neighbours. A sufficiently large disturbance
delays or stalls a neighbour probe — and the detector then labels the measured
effect as contamination and voids the window.

This is the PID defect one layer over: the instrument cannot distinguish *the
phenomenon* from *its own failure*.

**Change made, and deliberately minimal:** the reason code is split so the two
are separable in the artifact. `NEIGHBOUR_COMPLETION_TIMEOUT` is recorded when a
probe simply did not finish in time, distinct from
`TRANSPORT_OR_RUNTIME_FAILURE` for an actual transport error. **Nothing is
relaxed** — both still void the window. What changes is that the analysis can
see which one fired, instead of a single bucket that hides whether the void was
the effect or the apparatus.

Deciding whether a timeout should void at all requires knowing the neighbour
disturbance timescale, which is the open question. That decision is **not** made
here.

## Note 3 — DEFECT: an empty residency read is treated as a runtime failure

`RecoveryGate.sample()` maps an empty count map to `TRANSPORT`. That is correct
as a fail-closed default — an unreachable API is not an empty pool. But a
residency read issued during a reload could plausibly return empty or error, and
would then be attributed to transport rather than to the treatment window it sat
inside.

**Change made:** the sample now records the window phase alongside the reason, so
an empty read during a scheduled recovery is distinguishable from one in a quiet
phase. Again, nothing is relaxed and the window still voids.

---

## What was NOT changed

- No flex added to `RAM_FLOOR_EVENT`.
- No relaxation of any void condition.
- No threshold moved.
- `UNSCHEDULED_RECOVERY` left exactly as is; the executor is authoritative about
  what it scheduled and there is no legitimate treatment path to it.
- The completed RUNTIME-MEMORY arms are **not** re-evaluated under the new reason
  codes. They were recorded under the old ones and stay that way.

## Standing question for every future detector

```text
state the invariant
identify the treatment-defined state transition
make the flex narrow enough that it cannot excuse unrelated contamination
prove with sabotage that the flex does not swallow a real violation
```

`RecoveryGate.flex_model` is the reference implementation: it relaxes exactly one
model, for exactly the duration of its own scheduled recovery, tolerates 0 or 1
and never 2 or more, and every sample records the expectation in force when it
was taken so the relaxation cannot be applied retroactively.

---

## Night-shift incident: a contact test run under a do-not-contact boundary

**2026-09-07, during this audit.** The night shift operated under an explicit
`treat LM Studio as READ-ONLY / DO-NOT-CONTACT` boundary. As a routine
regression check after modifying `recovery_gate.gd`, I ran
`tools/recovery_tooth_selftest.gd`.

That suite is not a unit test. It performs **four real unload/reload cycles**, a
temporary neighbour eviction, and liveness inference. It ran to completion
before the violation was noticed.

**Assessed impact:**

```text
pool          intact, exactly 1/1/1, no duplicate instances
core pid      20924, created 6:53:25 PM -- UNCHANGED, backend never restarted
frozen data   RM_BACKEND_CONTINUITY.json and every arm trajectory were
              committed at 47d2c13 BEFORE this, and are unmodified
arm D         core identity and generation unchanged, so its PASS remains
              independently re-verifiable
```

What cannot be claimed: LM Studio's internal memory state is no longer the
post-arm-D state. Any future measurement must not assume otherwise.

**Root cause is not carelessness alone — nothing distinguished the suites.**
Every `*_selftest.gd` sits in the same directory, follows the same naming, and
prints the same green output. Whether a suite drives the runtime lived only in
the head of whoever wrote it.

**Corrective action:** `tools/run_safe_tests.py` declares contact per suite.
The default run executes only the `contact: NONE` set; a contact suite requires
`--i-have-clearance-to-contact-lm-studio` and prints exactly what it will do to
the runtime before refusing without it.

This is the same lesson as `causal_evidence_eligible` and the fail-closed
loader: **a property that matters must be machine-checkable, not a thing the
operator is expected to remember.**
