# PREREGISTRATION — RUNTIME-MEMORY four-arm rerun

**FROZEN 2026-09-08, BEFORE ANY NEW ARM EXISTS.** Human decision, recorded in
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

## Population regime

This run is **REGIME B** (5 species, 1 instance each). Every artifact it
produces must carry `population_regime_id: "B"`. The original RUNTIME-MEMORY
arms were collected under **REGIME A** (3 species, 2+2+1). See
`POPULATION_REGIMES.md`; the two are never pooled.
