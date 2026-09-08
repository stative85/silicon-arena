# NEXT LIVE RUN

Written during the night shift of 2026-09-07. No live action was taken and none
is authorised by this document. It exists so the next operator does not have to
reconstruct the state from commit messages.

**RUNTIME-MEMORY has NOT identified a mechanism.** Nothing below should be read
as a finding about why the runtime accumulates memory.

---

## ESTABLISHED — measured facts

**RECOVERY-COUPLING Run 1** (`RC_RUN1_VOID.md`) — VOID / TERMINATED on repeated
`RAM_FLOOR_EVENT`. 41 of 60 windows persisted before termination: 23 CLEAN, 18
VOID, the voids concentrated in the lfm2.5 rotation block and released at the
rotation boundary. Both conditions hit equally, 9 TREATMENT and 9 CONTROL.
The causal question is **unanswered**.

**The qwen3.5 block** — 20 windows, 10 T / 10 C, zero voids, complete and clean.
**QUARANTINED.** `causal_evidence_eligible` is permanently false. A weaker
`diagnostic_sensitivity_eligible` status is earnable only under the nine-point
criterion frozen at `b49a58e`, whose ninth condition is enforced by git
chronology.

**RUNTIME-MEMORY** — all four arms completed 40 windows each. Start-state
witnesses were comparable on every pre-existing boundary: floor cleared, counts
1/1/1, health surface `14536bd0e92f16ba`, runtime `lms CLI commit df81c60`,
start RSS 5,471–5,514 MB, start free 15,526–16,652 MB.

**Backend continuity, corrected witness** (`RM_BACKEND_CONTINUITY.json`):

```text
FULL_WINDOW       PASS      core 20924 identified, generation verified
RECOVERY_ONLY     UNKNOWN   backend gone, generation unrecoverable
CONTROL_WORKLOAD  UNKNOWN   same
IDLE              UNKNOWN   same
```

**Post-disconnect behaviour, from the orchestrator log** — recorded, not
interpreted:

```text
arm                start rss    +5s      +60s     host free +60s
IDLE                   5,471    5,597    5,597           15,649
CONTROL_WORKLOAD       5,500   16,597   16,664            4,744
RECOVERY_ONLY          5,491    5,410    5,414           15,690
FULL_WINDOW            5,514   16,105   16,097            5,444
```

---

## UNRESOLVED — open questions

1. **Does recovery destabilise co-resident neighbours?** RECOVERY-COUPLING's
   causal question. Twelve observational instances exist across ASYNC-A2 and
   ASYNC-B with a consistent signature, but recovery has never been the
   independent variable in a completed run.
2. **What does the runtime accumulate, under which operation, and does it
   plateau?** RUNTIME-MEMORY's question. Three of four arms are
   integrity-UNKNOWN, so the cross-arm comparison cannot be made.
3. **Is memory retention session-bound, backend-bound, or lifetime-bound?** The
   disconnect phase was measured but not analysed, and the arms that would
   anchor it are UNKNOWN.
4. **Is any of it model-dependent?** RC Run 1 could not separate this: the
   lfm2.5 rotation block and elapsed time were perfectly confounded.

---

## INVALIDATED — broken instruments and void runs

- **`BACKEND_RESTARTED_MID_ARM`** — compared the complete LM Studio PID set for
  equality; scheduled recovery replaces model workers by design. 676 and 582
  false offences. Replaced. Full record in `INSTRUMENT_DEFECT_PID_TOOTH.md`.
- **RECOVERY-COUPLING Run 1** — VOID / TERMINATED.
- **RECOVERY-COUPLING qualification pass 1** — all three TREATMENT windows void
  from a shared `HTTPRequest` between the gate and the concurrent recovery.
  Preserved as evidence: treatment and control were about to separate perfectly
  from a plumbing bug.
- **20-window RUNTIME-MEMORY horizon** — would have censored the known
  recovery-at-window-21 timescale. Amended to 40 before the run.
- **`resident_set()` ambiguity** — a failed read was indistinguishable from an
  empty pool, which let `ensure_loaded()` create duplicate instances through a
  failure path. Fixed this shift.
- **Telemetry-induced throughput distortion** — the producer probe cost a
  measured 345 ms per sample, 17.3% of every interval. Fixed by split cadence
  this shift, before any arm ran with it.

---

## NEXT PERMITTED LIVE ACTION

**Requires explicit human clearance. Do not begin from this document alone.**

Rerun the three integrity-UNKNOWN RUNTIME-MEMORY arms — `IDLE`,
`CONTROL_WORKLOAD`, `RECOVERY_ONLY` — with the corrected telemetry now in the
harness. `FULL_WINDOW` already holds a PASS and does **not** need rerunning,
though rerunning it would make all four arms symmetric in provenance.

Decide before starting, not after: whether the existing `FULL_WINDOW` PASS may
be compared against three newly-collected arms, given that it was collected
under the old telemetry and a different harness commit. Arms differing in
harness version is a limitation to state, not a covariate to adjust for
(Amendment 3).

### Procedure

```text
0. human clearance for FOUR LM Studio restarts (one per arm)
   -- Amendment 2 authorised one specific restart for RECOVERY-COUPLING and is
      NOT a standing licence

1. python tools/run_safe_tests.py
   must report: 8 passed, 0 failed, 2 skipped

2. python tools/runtime_memory_selftest.py
   must report: PREFLIGHT GREEN, 41 checks, 0 failures

3. python tools/backend_continuity.py --selftest
   must report: WITNESS GREEN, 10 checks

4. confirm no scientific runtime state is live on the machine

5. python tools/runtime_memory_run.py --confirm-restarts \
       --arms IDLE CONTROL_WORKLOAD RECOVERY_ONLY

6. python tools/backend_continuity.py --apply
   every rerun arm must report PASS, not UNKNOWN
   if any arm reports UNKNOWN, STOP -- the telemetry fix did not take

7. python tools/result_loader.py --check <the arm artifacts>
   must ADMIT them; it currently refuses the old ones

8. only then read trajectories, in the frozen 7-item order
   (EXPERIMENT_RUNTIME_MEMORY.md Amendment 1)
```

### What must NOT happen

No threshold change. No floor change. No post-hoc definition of "materially
shifted" beyond the pre-existing boundaries (Amendment 4). No adjustment for arm
order — with four arms and no replication of position, arm order is **not
estimable** (Amendment 3). No analysis of the quarantined qwen block. No
reinterpretation of UNKNOWN as PASS.

---

## Blocked, and why

The night shift could not resolve the integrity adjudication for arms A, B and
C. Their backends are gone and core generation was never recorded, so the
corrected witness returns UNKNOWN and no honest reconstruction exists. That is
the frozen outcome from Amendment 5, not a failure to try harder.
