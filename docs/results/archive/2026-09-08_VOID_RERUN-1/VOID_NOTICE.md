# VOID_RERUN-1 — 2026-09-08

```text
STATUS:                          VOID
four_arm_evidence_eligible:      false, PERMANENTLY
diagnostic_artifact:             true
```

Voided under finding `RERUN-1` for two independent reasons, either sufficient:

1. **Sameness condition 1 failed.** The three arms recorded three different
   `git_commit` values (`63d52ab`, `c0f3e07`, `d4d1c67`) because commits landed
   in the repository while the arms were collecting. The preregistration
   requires all four identical.
2. **FULL_WINDOW never ran.** The orchestrator's fixed 6-second teardown wait
   refused a backend that was still dying.

**The instrument did not change.** `tools/runtime_memory.gd` is blob
`bcb535bcc525831daa6aa854ed2fda3d0493ffd5` in all three commits. That is why
these arms remain useful as diagnostic reference — and it is NOT why they would
be admissible, because the criterion that failed is the recorded commit, and a
frozen criterion is not reinterpreted after seeing the data.

**Option 2 was explicitly rejected**: keeping these three and rerunning
`FULL_WINDOW` alone would stitch two instrumentation eras together, which is the
exact thing the P6 decision rejected when that cost was also two hours.

## What these arms may be used for

- Diagnostic reference: expected magnitudes, sanity checks on a clean rerun.
- Evidence that the corrected generation witness works end-to-end:

```text
IDLE              core pid 26056  created 2026-09-08T15:17:53.6312630-05:00
CONTROL_WORKLOAD  core pid 30408  created 2026-09-08T15:46:36.0315750-05:00
RECOVERY_ONLY     core pid 26912  created 2026-09-08T16:15:23.9361040-05:00
```

## What they may NOT be used for

- Any cell of a four-arm comparison.
- A control against the clean rerun.
- Any claim requiring the arms to be commensurable.

Not deleted. A voided run that vanishes cannot be audited, and the reason for
its voiding stops being checkable.
