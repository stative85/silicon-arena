# RUNTIME-MEMORY — what does the runtime accumulate, and does it plateau?

**Status:** pre-registered before implementation, model calls, or outcomes.

Blocker for RECOVERY-COUPLING Run 2. Motivated by Run 1
(`docs/results/RC_RUN1_VOID.md`), which began at 17,308 MB host free and drove
itself below the 2,048 MB floor within two windows.

## Question

Not "does RAM rise" -- Run 1 already answered that. It is:

> **What operation predicts the growth rate, and does memory plateau or remain
> unbounded over the intended experimental horizon?**

## Four regimes, each from a FRESH BACKEND START

```text
A. IDLE               pool loaded, no calls at all
B. CONTROL WORKLOAD   residency reads + liveness + neighbour probes,
                      no unload/reload
C. RECOVERY-ONLY      scheduled unload/reload + matched observations,
                      minimal neighbour probe workload
D. FULL WINDOW        the exact RECOVERY-COUPLING treatment workload
```

**A fresh backend per arm is mandatory.** Without it A contaminates B
contaminates C, and this becomes HEALTH-DUTY in a false moustache. Each arm gets
the Amendment 2 start procedure and its own start-state witness.

## Measured mechanically over request count and elapsed time

```text
LM Studio RSS (all processes, summed)
host free physical RAM
VRAM used / free
request count
prompt tokens (cumulative)
completion count
recovery count
residency count vector
elapsed time
```

Sampled at a fixed cadence and at every operation boundary, in every arm.

## Reported

```text
MB per 100 requests
MB per recovery
MB per minute
slope over time, and whether the slope decays
plateau            yes / no, and at what level
idle release       does RSS fall during arm A after a workload?
unload release     does RSS fall when a model is unloaded?
client-disconnect release   does RSS fall when the client process exits?
backend restart release     the known baseline
```

`client-disconnect release` is on the list because Run 1's termination showed
LM Studio RSS falling 21,884 -> 11,596 MB the moment the Godot client died. That
observation is **untested** and is the single most useful thing to confirm or
kill first: if accumulation is per-connection, the fix is architectural rather
than a matter of endurance.

## Horizon

Each arm runs at least as long as one full RECOVERY-COUPLING rotation position
(20 windows, ~15 minutes) so a plateau claim covers the intended experimental
horizon rather than a convenient window.

## Void conditions

```text
pool not exactly 1/1/1 at arm start        -> VOID that arm
arm started without a fresh backend        -> VOID that arm
any unscheduled recovery during an arm     -> VOID that arm
sampling gap exceeding 2x the cadence      -> recorded, reported
```

The 2 GB floor is **not** a void condition here. Crossing it is an observable in
this experiment, not a disqualification -- that inversion is deliberate and is
the reason this is a separate pre-registration rather than a patch.

## Pre-registered readings

```text
growth tracks request count, plateaus
  -> a sustainable execution regime exists; qualify it and rerun RECOVERY-COUPLING

growth tracks recovery count, plateaus
  -> recovery is the accumulating operation; rotation length must be bounded

growth unbounded in any arm over the horizon
  -> no sustainable regime at this window count; RECOVERY-COUPLING must be
     redesigned, not retried

arm A (idle) also grows
  -> accumulation is not workload-driven and the client is not the cause

release on client disconnect confirmed
  -> accumulation is per-connection; the experimental architecture is the lever
```

## Explicitly out of scope

No threshold changes. No RECOVERY-COUPLING rerun. No health-surface work. No
lowering of any floor anywhere. This experiment characterises and stops.
