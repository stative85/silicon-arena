# FINDING — the four-arm rerun is incomplete, and sameness condition 1 failed

```text
ID:              RERUN-1
SEVERITY:        BLOCKER for the four-arm comparison
EVIDENCE CLASS:  EXECUTED_WITNESS
STATUS:          RAISED, NOT RESOLVED. Two of the three remedies require
                 amending a frozen preregistration or accepting a violated
                 criterion, and neither is mine to choose.
RAISED:          2026-09-08, immediately after the orchestrator exited 1.
```

## What happened

```text
ORCHESTRATOR EXIT=1

IDLE               collected  15:45:25   git_commit 63d52ab
CONTROL_WORKLOAD   collected  16:14:13   git_commit c0f3e07
RECOVERY_ONLY      collected  16:42:55   git_commit d4d1c67
FULL_WINDOW        NEVER RAN  --         "FAIL backend did not restart cleanly"
```

Two independent failures. Either alone blocks the comparison.

---

## FAILURE 1 — sameness condition 1 failed, and I caused it

The preregistration freezes eight sameness conditions. The first:

> | 1 | same harness commit | `git rev-parse HEAD` recorded in every arm
> artifact; all four identical |

**They are not identical.** Three arms, three different commits.

**Cause: I committed to the repository while the arms were collecting.** The
harness records `git rev-parse --short HEAD` at arm start, so every commit I
made during Lane B moved the value the next arm would record. The BREACH design
doc landed at 15:31, the implementation at 15:54, the vault fix at 16:18 — each
between two arms.

Lane A was supposed to own the machine. It did: no process was started, no
inference sent, no Godot launched. **What I did not consider is that a commit is
also an intervention**, because the instrument reads the repository's HEAD as
part of its own provenance.

### What did NOT change: the instrument

```text
git rev-parse <commit>:tools/runtime_memory.gd

  63d52ab   bcb535bcc525831daa6aa854ed2fda3d0493ffd5
  c0f3e07   bcb535bcc525831daa6aa854ed2fda3d0493ffd5
  d4d1c67   bcb535bcc525831daa6aa854ed2fda3d0493ffd5
```

The arm harness is **byte-identical** across all three arms. `git diff` between
those commits touches `tools/runtime_memory.gd` not at all. What changed was
2,908 lines of BREACH code on a path the measurement never reads.

**COULD-HAVE-FAILED:** yes. Had any commit touched the harness, the blob hashes
would differ and this section would read the opposite way.

### Why that does not resolve it

The argument "the intent is satisfied even though the letter is not" is exactly
the move a preregistration exists to prevent, and it is being made *after* the
data exists by the party who caused the violation. The prereg is explicit:

> Nothing in this document may be revised after the first sample of the first
> arm is collected; a change after that point is a post-hoc criterion change and
> voids the run.

So condition 1 **failed as written**, and the criterion may not be amended now to
make it pass. Stop condition 3 — *"any sameness condition 1–8 fails for any
arm"* — has fired.

### A defect in the criterion, for the NEXT preregistration only

Binding sameness to **repo HEAD** rather than to **the instrument's content
hash** means any unrelated commit invalidates a run. A four-hour experiment is
one documentation typo away from being void, which will train operators to
freeze the whole repository — or, worse, to shrug at the condition.

`git rev-parse HEAD:tools/runtime_memory.gd` binds what actually matters. This
is recorded for the next prereg and is **not applied to this one**.

---

## FAILURE 2 — FULL_WINDOW never ran

```text
FAIL backend did not restart cleanly
```

`restart_backend()` stops the server, issues `taskkill /F`, then waits a **fixed
6 seconds** and refuses if any LM Studio process still exists:

```python
subprocess.run(["taskkill", "/F", "/IM", "LM Studio.exe"], ...)
time.sleep(6)
if lm_procs()[0] or resident() is not None:
    return None          # -> "backend did not restart cleanly"
```

Six seconds was enough three times and not the fourth. The process count is
**0 now**, so the backend did die — just later than the fixed wait allowed. A
teardown race, not a corrupted backend.

The refusal is *correct behaviour*: it fails closed rather than starting an arm
against a half-dead backend. The defect is the fixed sleep, which should be a
wait-until-dead loop with a deadline.

---

## What is intact

- The three collected arms each obtained the **producer-derived generation
  witness** — the thing that made every previous attempt fail:

```text
IDLE              core pid 26056  created 2026-09-08T15:17:53.6312630-05:00
CONTROL_WORKLOAD  core pid 30408  created 2026-09-08T15:46:36.0315750-05:00
RECOVERY_ONLY     core pid 26912  created 2026-09-08T16:15:23.9361040-05:00
```

- All three carry `measurement_pool_id: RM3_V1`.
- All three ran on a fresh backend with the 1/1/1 residency count map.
- No `RAM_FLOOR_EVENT`. No unaccounted restart.
- The pre-rerun artifacts remain archived and byte-verified.

The instrument amendment worked. The experiment around it did not complete.

---

## Options, none taken

1. **Rerun all four with a frozen tree.** No commits between launch and
   completion. Clean under the prereg exactly as written. Costs ~2 hours and
   requires the teardown fix first.
2. **Accept the three arms and rerun FULL_WINDOW alone.** Fastest, and the
   instrument is provably identical — but condition 1 stays failed as written,
   and the fourth arm would additionally run after a teardown fix the other
   three did not have. That is two asymmetries, not one.
3. **Declare the run void and re-preregister** with sameness bound to the
   harness blob hash rather than repo HEAD.

Option 2 is the tempting one and it is the one that stitches eras together —
the exact thing the P6 decision rejected two hours ago when the cost was also
about two hours.

**Both failures need a human decision. The teardown fix is mechanical and I can
make it; whether this run is salvageable is not.**
