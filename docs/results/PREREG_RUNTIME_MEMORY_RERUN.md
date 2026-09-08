# PREREGISTRATION — RUNTIME-MEMORY four-arm rerun

**FROZEN 2026-09-08, BEFORE ANY NEW ARM EXISTS. Corrected once, also before any
arm existed, under finding REGIME-1 — see the provenance-axis section.** Human decision, recorded in
advance precisely so the data cannot influence it. Nothing in this document may
be revised after the first sample of the first arm is collected; a change after
that point is a post-hoc criterion change and voids the run.

**This is a preregistration, not a clearance.** P4 and P5 remain HOLD. Freezing
what the run *would be* is deliberately separate from authorising it to happen.

---

## P6 DECISION — rerun all four arms

```text
RERUN:
  IDLE
  CONTROL_WORKLOAD
  RECOVERY_ONLY
  FULL_WINDOW

All four under:
  - same harness commit
  - same corrected telemetry
  - same start-state witness schema
  - same horizon
  - same sampling cadence
  - same backend-continuity witness
  - same runtime version
  - same load order
```

**The rejected option, named so it stays rejected:** comparing the existing
`FULL_WINDOW` PASS against three newly collected arms. It would have saved
roughly two hours and produced a four-cell comparison stitched together from two
experimental eras — one cell collected under a different harness commit, without
the corrected per-sample core-generation telemetry, and adjudicated by a witness
that did not yet exist in its corrected form.

The asymmetry is not a nuisance parameter. It sits on exactly the axis the
experiment measures. Two hours is the cheaper problem.

## Status of the existing FULL_WINDOW result

```text
historical_valid                  = true
new_cross_arm_evidence_eligible   = false
diagnostic_reference              = true
```

**No deletion. No downgrade. No retraction.** The old `FULL_WINDOW` PASS remains
a correct result about what it measured, under the instrumentation of its time.
It is simply not reused as the fourth cell of a new experiment whose
instrumentation boundary moved.

Permitted: as a diagnostic reference — an expectation for magnitude, a sanity
check that the reruns are not wildly different, a source of hypotheses.

Forbidden: as one of the four cells in the new cross-arm comparison; as a
control against the new arms; as evidence in any claim that requires the four
arms to be commensurable.

This is the same shape as the qwen3.5 block's quarantine and the Regime A rule:
a real, valid, correctly-collected dataset that is not *interchangeable* with
data collected under different instrumentation.

## Sameness conditions — how each is witnessed

An arm that cannot demonstrate all eight is not part of the comparison.

| # | condition | witness |
|---|---|---|
| 1 | same harness commit | `git rev-parse HEAD` recorded in every arm artifact; all four identical |
| 2 | same corrected telemetry | `core_created` present on every sample; `samples_missing_generation == 0` |
| 3 | same start-state witness schema | identical schema keys across all four start-state records |
| 4 | same horizon | 40 windows per arm (Amendment: 20 was amended to 40 *before* the original run, because 20 would have censored the recovery-at-window-21 timescale) |
| 5 | same sampling cadence | identical `sample_ms` and `window_ms` in all four artifacts |
| 6 | same backend-continuity witness | one frozen `backend_continuity.py`, unmodified across the whole run |
| 7 | same runtime version | LM Studio + `lms` CLI commit recorded per arm; all four identical |
| 8 | same load order | recorded per arm; see the arm-order limitation below |

**Arm order.** With four arms and no replication of position, arm order is **not
estimable**. It is recorded as a limitation, never adjusted for (Amendment 3).
Fix one order, record it, and state it in the write-up.

## Analysis order — frozen

```text
1. backend-continuity verdict for all four arms
2. admissibility: result_loader must ADMIT all four
3. ONLY THEN read trajectories, in the frozen 7-item order
   (EXPERIMENT_RUNTIME_MEMORY.md Amendment 1)
```

Integrity first, trajectories last. A run that reads a trajectory before step 1
completes has forfeited the frozen-witness property, and no discipline applied
afterwards restores it.

## Stop conditions — frozen

Any of these stops the run and produces a finding rather than a result:

1. Any arm returns `UNKNOWN` from the continuity witness. **UNKNOWN is not a
   soft PASS.**
2. `result_loader` refuses any new artifact. Do not hand-edit an artifact to get
   it admitted.
3. Any sameness condition 1–8 fails for any arm.
4. `RAM_FLOOR_EVENT` fires, as it did in RECOVERY-COUPLING Run 1 — that run is
   VOID/TERMINATED and its causal question is still **UNANSWERED**.
5. The backend restarts at a moment no scheduled recovery accounts for.
6. Any impulse to adjust a threshold, floor, seed set, or acceptance criterion.
   Frozen: RAM floor 2048 MB, `ks=1.8`, `kh=20`, `n=3`.

## What this run cannot deliver

The original IDLE, CONTROL_WORKLOAD and RECOVERY_ONLY arms remain **UNKNOWN
forever**. Their backends are gone and their generation was never recorded. This
rerun produces new data; it does not retroactively repair old data, and no
result here may be described as having "resolved" those arms.

## Provenance axis — CORRECTED 2026-09-08 under REGIME-1, before any data

**This run is NOT Regime B.** The original text of this section claimed it was
and required `population_regime_id: "B"` on every artifact. That was false and
would have written false provenance. Corrected before the first runtime contact;
the withdrawn claim is preserved in
`docs/results/FINDING_REGIME_SCOPE_ERROR.md`.

RUNTIME-MEMORY **measures a model pool**; it does not instantiate an Arena
roster. It therefore carries the pool axis and never the roster axis:

```text
measurement_pool_id: "RM3_V1"
pool_identity:       ["liquidai/lfm2.5-1.2b-instruct",
                      "qwen3.5-2b",
                      "falcon-h1-1.5b-instruct"]
population_regime_id: ABSENT -- this run instantiates no Arena roster
```

`RM3_V1` is declared in `config/measurement-pools.v1.json` and is a **strict
subset** of the Regime B membership, not that roster: `OZONIOUS` (rwkv7) and
`BRINE` (danube2) are not in it and never were.

**`tools/runtime_memory.gd` POOL is NOT changed.** Making the original claim
true by enlarging the pool to five models would be a *design change to the
experiment*, not a relabelling, and is not authorised. The pool stays as it has
always been; only its name is now declared.

`tools/population_regime.py` verifies the declared pool against the pool each
artifact actually recorded. Declaring `RM3_V1` while measuring anything else is
refused.

The original arms are **PRE-AXIS**: they predate both axes and carry neither.
They are not back-filled — adding a label an artifact did not have when written
falsifies provenance however true the label is.
