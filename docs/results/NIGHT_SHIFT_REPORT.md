# Night shift report — 2026-09-07

```text
starting commit   6a6b4d5   RUNTIME-MEMORY Amendment 5
ending commit     0322a69   failure-path teeth
commits           9
files changed     25  (+90,835 / -52, dominated by raw arm artifacts)
```

**Objective:** make the next live run boring, mechanically witnessed, and hard
to misinterpret. Not to make Silicon Arena look successful.

---

## Commits

```text
47d2c13  RUNTIME-MEMORY raw artifacts + corrected backend-continuity witness
d6e06a0  Core-generation telemetry in the live harness; corrected continuity tooth
3a74857  Self-describing arm artifacts + fail-closed result loader
981b39d  Treatment-aware detector audit; contact classification for test suites
a8083d0  Preserve the PID-tooth defect history; corollary NOT promoted to Law 6
704b999  Static review fixes: telemetry no longer distorts the workload it measures
62f1881  Static review: a failed read is no longer indistinguishable from an empty pool
3d4263e  docs/NEXT_LIVE_RUN.md: deterministic handover
0322a69  Pin the night-shift fixes with failure-path teeth, proven to bite
```

## Tests

`python tools/run_safe_tests.py` — **9 no-contact suites pass, 0 fail, 2 contact
suites correctly skipped.**

```text
runtime_memory_selftest      41 checks   static scan of the arm harness
backend_continuity           10 checks   synthetic PID-sample sabotage
result_loader                15 checks   eligibility rejection branches
recovery_schedule                        plan verification
qwen_fossil_admissibility                fails closed, as designed
detector_audit_selftest      10 checks   treatment-flex narrowness
failure_path_selftest        19 checks   night-shift fixes pinned
recovery_probe_selftest      20 checks   telemetry record validation
async_b_witness             385 checks   representation layer
```

## Sabotages proven

Every one asserted that the sabotage actually applied before running, and every
one was reverted:

```text
BACKEND_PROBE_FAILED removed          -> preflight RED, correct failure named
BACKEND_CORE_CHANGED removed          -> preflight RED, correct failure named
BACKEND_GENERATION_CHANGED removed    -> preflight RED, correct failure named
backend_core_created_at_start removed -> preflight RED, correct failure named
DISAPPEARED flipped to TRANSPORT      -> failure-path teeth RED, 2 failures
                                         naming the wrong reason code
```

Plus the pre-existing witness sabotages re-verified: actual restart,
disappear/reappear, reused pid with changed generation, dead core, unexplained
churn, churn exceeding recoveries, missing generation field → UNKNOWN not PASS.

## Bugs found and fixed

**1. Telemetry that distorted the workload it measures.** My own core-generation
fix used a producer probe measured at **345 ms median**, blocking, every 2 s —
17.3% of each interval, ~276 s per 40-window arm. Requests per minute is a
primary independent variable, so the fix would have reduced throughput and moved
the measurement. Fixed by split cadence: cheap tasklist probe (~150 ms) every
sample, full generation probe every 10th and at both arm boundaries, per-sample
cost 17.3% → ~9.2%, each sample recording `backend_probe_full`.

**2. At-least vs exactly-one in `ensure_loaded()`.** Returned true for any count
≥ 1, reporting a pool holding two instances as restored. Same defect class as the
duplicate-instance bug that once left 5 instances at 7,656 MiB VRAM, one layer
down. Now true only for exactly 1.

**3. A failed read indistinguishable from an empty pool.** `resident_set()`
returned `[]` for transport failure, non-200, malformed JSON **and** a genuinely
empty pool. Two consequences: a total eviction classified as the milder
`TRANSPORT`, and `ensure_loaded()` issuing a load for a resident model after a
transient read failure — recreating duplicate instances through a failure path.
Fixed with explicit `ok` flags; callers fail closed.

**4. A detector that could flag the phenomenon under study.** A stalled
neighbour probe was filed as `TRANSPORT_OR_RUNTIME_FAILURE`, but the hypothesis
is that recovery disturbs neighbours — so a large enough disturbance stalls a
probe and the instrument calls the effect contamination. Split into
`NEIGHBOUR_COMPLETION_TIMEOUT`. **Nothing relaxed**; both still void.

**5. No distinction between unit tests and runtime-driving tests.** See below.

## Boundary violation — reported, not buried

Under an explicit `treat LM Studio as READ-ONLY / DO-NOT-CONTACT` boundary, I ran
`recovery_tooth_selftest.gd` as a routine regression check after editing
`recovery_gate.gd`. **It is not a unit test.** It performed four real
unload/reload cycles, a temporary neighbour eviction, and liveness inference.

Assessed impact:

```text
pool          intact, exactly 1/1/1, no duplicate instances
core pid      20924, created 6:53:25 PM -- unchanged, backend never restarted
frozen data   RM_BACKEND_CONTINUITY.json and every arm trajectory were
              committed at 47d2c13 BEFORE this and are unmodified
arm D         core identity and generation unchanged; its PASS is still
              independently re-verifiable
```

**What cannot be claimed:** LM Studio's internal memory state is no longer the
post-arm-D state. No future measurement should assume otherwise.

Root cause was not carelessness alone — nothing in the repository distinguished
a pure unit test from one that drives the runtime. Same directory, same naming,
same green output. Corrective action: `tools/run_safe_tests.py` declares contact
per suite, defaults to the no-contact set, and refuses contact suites without
explicit clearance while printing exactly what they would do.

## Deliberately NOT done

- **No trajectory was read or analysed.** Not one arm's RAM curve was examined.
- **No arm re-evaluated** under the new reason codes; they were recorded under
  the old ones and stay that way.
- **UNKNOWN never reinterpreted as PASS** for arms A, B, C.
- **The qwen block untouched**; no causal analysis, quarantine intact.
- **No threshold, floor, `ks`, `kh`, `n` changed.** No post-hoc threshold invented.
- **Corollary 1a NOT promoted to Law 6.** The redundancy test was run and it
  failed to earn a number: Law 1 is the epistemic requirement, the corollary is
  its constructive counterpart. Same law, different delivery.
- **No LM Studio restart, no inference, no experiment run** — beyond the
  violation above.
- **No frozen preregistration history altered.**

## Unresolved blockers

**Arms IDLE, CONTROL_WORKLOAD, RECOVERY_ONLY remain integrity-UNKNOWN.** Their
backends are gone and core generation was never recorded, so the corrected
witness cannot be evaluated and no honest reconstruction exists. This is
Amendment 5's frozen outcome, not a failure to try harder. The cross-arm
comparison cannot be made from the completed run.

**RUNTIME-MEMORY has not identified a mechanism.** The four arms exist; three
cannot carry a result.

## Exact next live action — requires human clearance

Full procedure in `docs/NEXT_LIVE_RUN.md`. Summary:

```text
0. human clearance for FOUR LM Studio restarts
   Amendment 2 authorised ONE specific restart and is not a standing licence
1. tools/run_safe_tests.py            -> 9 passed, 0 failed, 2 skipped
2. tools/runtime_memory_selftest.py   -> PREFLIGHT GREEN, 41 checks
3. tools/backend_continuity.py --selftest -> WITNESS GREEN, 10 checks
4. confirm no scientific runtime state is live
5. tools/runtime_memory_run.py --confirm-restarts \
       --arms IDLE CONTROL_WORKLOAD RECOVERY_ONLY
6. tools/backend_continuity.py --apply -> every rerun arm must be PASS.
   If any is UNKNOWN, STOP: the telemetry fix did not take.
7. tools/result_loader.py --check <artifacts> -> must ADMIT
8. only then read trajectories, in the frozen 7-item order
```

**One decision to make before starting, not after:** whether the existing
`FULL_WINDOW` PASS may be compared against three newly-collected arms, given it
was collected under the old telemetry and a different harness commit. Differing
harness versions is a limitation to state, not a covariate to adjust for.
