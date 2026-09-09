# RUNTIME-MEMORY — CLOSED

**Closed 2026-09-08 by human decision. No RERUN-3.** No further memory
experiment unless THE BREACH itself exposes a blocker.

---

## The operational result

```text
RM3_V1 sustained CONTROL_WORKLOAD at the current configuration is
UNSUPPORTED on this machine due to host-memory exhaustion.
```

**Evidence:**

```text
host free RAM, minimum            396 MB
samples below the 2048 MB floor   117 of 647   (18% of the arm)
LM Studio RSS, maximum         14,420 MB
machine total                  32,470 MB
OS subsequently terminated RERUN-2 for low memory
```

That is the whole claim. It is an **operational** conclusion about a
configuration on a machine, and it is what the Arena actually needed to know.

## What this explicitly does NOT claim

- **Nothing about recovery causality.** RECOVERY-COUPLING's question is
  untouched and its Run 1 remains VOID.
- **Nothing about the mechanism of memory growth.** We do not know what
  accumulates, or why.
- **Nothing implicating reload.** Model reload is not established as the cause
  of anything here.
- **Nothing about other workloads.** This is CONTROL_WORKLOAD under RM3_V1 at
  this configuration. It does not predict that every Arena workload reproduces
  it, and BREACH under sequential residency is a different regime entirely.
- **Nothing from the void arms.** No four-arm comparison exists. None of the
  collected arms is a cell of one.

## Why it closed here

Three consecutive attempts, three distinct failures, each of which produced a
real defect and none of which produced a four-arm comparison:

| run | outcome | defect found |
|---|---|---|
| first attempt | zero arms | `_backend_probe` never worked on the production path — the generation witness had never been obtainable |
| RERUN-1 | 3 arms, incomplete | sameness condition 1 violated (commits moved HEAD mid-run); teardown refused on a fixed 6 s sleep |
| RERUN-2 | 1.06 arms, OS-killed | **RAMFLOOR-1**: the preregistered floor had no detector behind it |

The third failure is the one that ended it. A machine that the experiment drives
to 396 MB free is not a scheduling inconvenience, and continuing would have meant
either burning hours to measure a regime already shown unsupported, or running
with a safety boundary that existed only as a sentence.

## What the infrastructure proved, and keeps

Not wasted. Each of these was verified by execution and survives the closure:

- **The generation witness works.** Three arms recorded producer-derived core
  identity and creation time, where every prior attempt got none.
- **The freeze holds.** Lane A / Lane B worktree separation kept `git_commit`
  identical across RERUN-2's arms. Sameness condition 1 would have passed.
- **Teardown polls.** 2.2 s and 3.4 s, both to an observed count of 0, replacing
  a fixed 6-second guess that had already cost one arm.
- **The floor now exists.** `RAM_FLOOR_MB = 2048`, compared per sample, emits
  `RAM_FLOOR_EVENT` into both `events` and `problems`, terminates the arm, and
  writes the partial artifact. Value unchanged; enforcement new. The metadata
  now carries `ram_floor_mb`, `ram_floor_fired` and `terminated_by_floor` so no
  consumer infers any of it from prose.

## Consequence for THE BREACH

Simultaneous five-model residency is **abandoned as the default for IGNITION 0**.
The Arena is turn-based, so sequential residency fits the mechanics rather than
apologising for them: one model active for its turn, identical load/use/unload
policy for all five species, a hard 2048 MB host floor, clean stop and preserved
event log if it is crossed. No asymmetric CPU offload, no mixed quantization —
both would make an agent slower or dumber because of how it was loaded, which
would confound the first species comparison.

Uniform context 4096 under sequential residency; uniform 2048 if a model cannot
run safely at 4096.

**The useful thing RUNTIME-MEMORY produced is not a mechanism. It is: stop
trying to keep the whole zoo resident.**

## Artifacts

All preserved, none salvaged into a four-arm comparison:

```text
docs/results/archive/2026-09-08_pre_rerun/        pre-rerun originals
docs/results/archive/2026-09-08_VOID_RERUN-1/     3 arms, VOID
docs/results/archive/2026-09-08_VOID_RERUN-2/     1 complete + 1 partial, VOID
```

Findings: `FINDING_REGIME_SCOPE_ERROR.md`, `FINDING_RERUN_SAMENESS_VIOLATION.md`,
`FINDING_RAM_FLOOR_DETECTOR_ABSENT.md`.
