# VOID_RERUN-2 — 2026-09-08

```text
STATUS:                      VOID
four_arm_evidence_eligible:  false, PERMANENTLY
diagnostic_artifact:         true
```

Killed by the operating system for low memory, ~6% into arm 2 of 4.

```text
IDLE               complete   720 samples
CONTROL_WORKLOAD   PARTIAL     51 samples of ~800
RECOVERY_ONLY      never ran
FULL_WINDOW        never ran
```

**What worked:** the freeze held. Both arms recorded `git_commit a5cb652` — the
Lane A / Lane B worktree split did exactly what it was built for, and sameness
condition 1 would have passed. The teardown fix also held: 2.2 s and 3.4 s, both
polled to an observed count of 0.

**What killed it:** see `FINDING_RAM_FLOOR_DETECTOR_ABSENT.md` (RAMFLOOR-1).
`CONTROL_WORKLOAD` drives this 32 GB host to 396 MB free and spends 18% of the
arm below the declared 2048 MB floor. The preregistered stop condition for that
is `RAM_FLOOR_EVENT`, and **no such detector exists in the harness**. The OS
enforced the floor because nothing else was going to.

The partial `CONTROL_WORKLOAD` artifact is an incremental flush, not a completed
arm. It is kept as diagnostic material and is not admissible for anything.
