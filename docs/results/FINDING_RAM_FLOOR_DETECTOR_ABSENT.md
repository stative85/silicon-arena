# FINDING — the RAM floor stop condition has no detector behind it

```text
ID:              RAMFLOOR-1
SEVERITY:        BLOCKER for any further RUNTIME-MEMORY arm on this machine
EVIDENCE CLASS:  EXECUTED_WITNESS
STATUS:          RAISED, NOT FIXED. The remedy is an instrument change under a
                 frozen preregistration, and a safety decision about a machine
                 that the experiment can exhaust.
RAISED:          2026-09-08, after RERUN-2 was killed by the operating system.
```

## What happened

RERUN-2 was terminated by the OS for low memory, ~6% into arm 2 of 4:

```text
IDLE               complete    720 samples
CONTROL_WORKLOAD   KILLED       51 samples of ~800
RECOVERY_ONLY      never ran
FULL_WINDOW        never ran
```

## Why — and it is not a fluke

From RERUN-1's **completed** `CONTROL_WORKLOAD` arm, 647 samples:

```text
LM Studio RSS, max      14,420 MB
host free RAM, min         396 MB
samples below the 2048 MB floor    117 of 647
first breach at sample 49         1,985 MB
machine total              32,470 MB
```

`CONTROL_WORKLOAD` drives a 32 GB host down to **396 MB free**, and stays under
the declared floor for **18% of the arm**. RERUN-2 did not die of bad luck or of
anything running beside it. This arm consumes essentially all host memory, and
on the second attempt the OS reaped the orchestrator before the arm could finish.

## The actual defect

The preregistration freezes a stop condition:

> 4. `RAM_FLOOR_EVENT` fires, as it did in RECOVERY-COUPLING Run 1

and the clearance receipt freezes `ram_floor_mb: 2048`.

**No such detector exists in `tools/runtime_memory.gd`.**

```text
$ grep -n "RAM_FLOOR\|2048\|free_mb" tools/runtime_memory.gd
258:  "host_free_mb": int(float(mem.get("free", 0)) / 1048576.0),
```

One line. It **records** host free memory. Nothing compares it to anything,
nothing raises an event, nothing stops an arm. The arm artifacts confirm it:

```text
events   : []
problems : []
```

117 samples below the floor produced zero events, because there is nothing to
produce them.

`RAM_FLOOR_EVENT` is real — it exists in the RECOVERY-COUPLING harness, where it
fired repeatedly and voided Run 1. It was carried into the RUNTIME-MEMORY
preregistration as a stop condition **by name**, against a harness that never
implemented it.

**COULD-HAVE-FAILED:** yes. Had the guard existed, the grep would show a
threshold comparison and the arm would carry floor events.

## What this means

1. **Stop condition 4 has never been able to fire in this experiment.** A
   preregistered safety boundary with no mechanism is a sentence, not a
   boundary. Law 2, Detector-Support: a detector must be supported by the thing
   it claims to detect, and this one has no detector at all.
2. **RERUN-1's `CONTROL_WORKLOAD` should have stopped and did not.** Under the
   prereg as written, an arm that spent 117 samples below the floor was already
   a stop. It ran to completion because nothing was watching. That is an
   additional, independent reason RERUN-1 is void — one I did not know when I
   voided it for the sameness violation.
3. **The OS did what the missing guard should have done.** RERUN-2's kill is the
   floor enforcing itself through the only mechanism present.
4. **It retroactively illuminates RECOVERY-COUPLING Run 1.** That run was voided
   by repeated `RAM_FLOOR_EVENT`s. Same phenomenon, same machine, a harness that
   could see it. The pattern is not specific to that experiment; this workload
   exhausts host RAM.

## My contribution, stated plainly

I was doing Lane B work in a git worktree during the CONTROL_WORKLOAD arm —
python scans, commits, and an 8,438-file checkout. **That is not the cause: the
arm reaches 396 MB free on its own, in a run where I was doing nothing.** But it
cannot have helped, and I should not have been running anything on that box
during the memory-heaviest arm.

This is the second boundary I have read too narrowly. RERUN-1: I honoured "do
not touch the machine" but not "do not move HEAD". RERUN-2: I honoured "no
runtime processes" as "no Godot, no LM Studio" while running a large checkout
during the arm that consumes all available RAM. Both times the constraint was
about *the experiment's environment*, and both times I took the narrowest
reading available.

## Options, none taken

1. **Implement the guard.** Add a real floor check to the harness: sample
   `host_free_mb`, raise `RAM_FLOOR_EVENT` below 2048, terminate the arm. This
   is an instrument change under a frozen prereg — the same category as the
   `_backend_probe` amendment, which was permitted only because no sample
   existed. No sample exists now either.
2. **Reduce the workload** so the arm does not exhaust the host. That changes
   what is measured and is a design change, not an amendment.
3. **Accept the exposure** and run with nothing else on the machine, knowing the
   OS may reap the run again and that stop condition 4 remains decorative.
4. **Re-preregister** with a floor that the harness actually implements, and a
   declared expectation that this arm approaches host exhaustion.

Option 3 is the one that looks like momentum and is the one that leaves a
preregistered safety boundary unenforced.

**A machine that the experiment can drive to 396 MB free is a safety question,
not a scheduling inconvenience. Not mine to decide.**
