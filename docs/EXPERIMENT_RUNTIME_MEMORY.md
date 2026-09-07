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


---

# Amendment 1 — reading order, and a law held in reserve

Frozen before implementation.

## The order the result is read in

Fixed now so the answer is not assembled from whichever arm looks most
interesting:

```text
1. Does IDLE move materially?
2. Does CONTROL WORKLOAD reproduce the RAM depression without any recovery?
3. Does RECOVERY-ONLY reproduce it with minimal probing?
4. Does FULL WINDOW reproduce the LFM-like collapse?
5. At client disconnect, does LM Studio RSS step downward reproducibly
   while the backend stays alive?
6. Does memory plateau, oscillate, or recover BEFORE disconnect?
7. Are the trajectories model-dependent -- especially around lfm2.5 -- or
   merely coincident with rotation position and elapsed time?
```

Item 7 is the one Run 1 cannot answer and this experiment can: the collapse
coincided with the lfm2.5 rotation block, but rotation position and elapsed time
were perfectly confounded there.

## Resource primitives, kept beside any rate

`MB / 100 requests`, `MB / recovery` and `MB / minute` are descriptive mechanism
summaries, **not** new scores. The primitives underneath them -- request count,
prompt tokens, completions, recoveries, elapsed time -- are retained per sample
for the same reason `observed_ttft` and `expected_ttft` are kept beside
`residual`: a rate cannot be interrogated once its numerator and denominator
have been thrown away.

## A law held in reserve, NOT yet named

Run 1 suggests a sixth ROBRUSTION law:

> **VALID START STATE != VALID EXECUTION TRAJECTORY.**
> A start-state witness proves initial conditions. It does not establish that
> the workload remains inside its qualified resource envelope.

It is **deliberately not added to `ROBRUSTION_LAWS.md` yet.** Every existing law
there is anchored to a measured mechanism. This one currently rests on an effect
whose mechanism is unknown -- which is exactly what this experiment exists to
supply. It gets named after RUNTIME-MEMORY reports, or not at all.

---

# Amendment 2 — horizon 40 windows, and a phase-aware reading

Frozen before the first RUNTIME-MEMORY call, before the four restarts, and
before any arm exists.

## The 20-window horizon censors the phenomenon

RECOVERY-COUPLING Run 1, recorded in `docs/results/RC_RUN1_VOID.md` at commit
`9707314` — **before this amendment and before any RUNTIME-MEMORY outcome
exists** — showed:

```text
RAM depression begins   ~window 2
stays depressed through ~window 19
recovers                ~window 21
then ~20 clean windows
```

A 20-window arm would have stopped one window before the recovery. Four
beautifully controlled arms could have concluded "memory stays depressed"
because the stopwatch quit just before the runtime got back up.

```text
HORIZON = 40 windows per arm
```

~26.7 minutes per arm, ~1h50m for four arms plus restarts. This experiment is
specifically about **trajectory shape**, so a horizon shorter than the known
recovery timescale is not a saving, it is a censoring.

This is an amendment made on an observation that PREDATES it, not on any
RUNTIME-MEMORY result. The git chronology is the evidence: `9707314` precedes
this commit, and no RUNTIME-MEMORY arm has run.

## Phase-aware reading, descriptive only

Reported per arm. **No thresholds, and no "recovered" cutoff invented
afterwards** — the shape is described, not scored:

```text
minimum host-free RAM, and the window it occurred in
maximum LM Studio RSS, and the window it occurred in
time / window index to the minimum
whether a recovery occurs before the arm ends
post-minimum slope
final 5-window median
disconnect drop at +5s / +15s / +30s / +60s
```

## No early-stop rule for RAM

Crossing the 2 GB floor remains **the observable**, not a void condition, as
already frozen. The only permitted stops are the genuine machine-safety and
runtime failures already listed in the void conditions. "This graph looks
conclusive" is not a stopping rule.

---

# Amendment 3 — arm order is a limitation, never a covariate

Frozen while arm A is still running and before any arm has reported.

## No post-hoc adjustment

The four arms are sequential and arm identity is perfectly confounded with
position and wall-clock. With four arms and no replication of position, there is
nothing honest to estimate there.

```text
NEVER: "we adjusted for arm order"
NEVER: regression, normalisation, detrending, or baseline subtraction
       applied to make arms comparable
```

The correct response to a shifted start witness is to **cap the claim**, not to
launder the difference through arithmetic. This project's own history is the
reason the rule is written down: post-hoc normalisation gets more seductive the
more the apparatus drifts, and the drift is exactly when it is least defensible.

## Integrity logic, frozen

```text
start witnesses comparable
  -> workload contrasts interpretable, within the stated sequential-order
     limitation

start witness materially shifted
  -> that arm's contrast is DOWNGRADED and its limit stated explicitly

start witness clearly outside the qualified envelope
  -> that arm may be INTEGRITY-COMPROMISED and is reported as such
```

"Materially shifted" is assessed on the witness fields already frozen — host free
RAM, LM Studio RSS, VRAM used, residency count map, runtime version, health
surface hash — and reported as the observed differences, not as a score.

## Mechanistic hierarchy, in order

```text
1. Does the shape reproduce?
2. Which workload arm produces it?
3. Does disconnect release it?
4. Does backend restart release what disconnect does not?
5. Only then, plausible mechanism -- and only as far as four arms identify it.
```

Shape before magnitude. "Which arm used more RAM" is a leak question;
`healthy -> collapse -> sustained depression -> spontaneous recovery` is a
stateful retention process with a timescale, and only the second tells us
anything about designing a sustainable execution regime.

If all four arms behave differently AND their start witnesses also differ, the
honest answer is that the sequential design cannot separate workload from arm
position. That is a reportable outcome, not a failure to analyse harder.

---

# Amendment 4 — "materially shifted" may only mean pre-existing boundaries

Frozen before any arm has reported. Closes the loophole left open by
Amendment 3.

## The loophole

Amendment 3 said a "materially shifted" start witness downgrades that arm's
contrast, without saying what material means. Left there, the term gets defined
from the four witnesses once they exist — which is a post-hoc pass/fail
criterion built out of the data it is supposed to judge.

## The only admissible boundaries

Boundaries that existed BEFORE RUNTIME-MEMORY, and no others:

```text
the frozen 2048 MB host-RAM floor
exact residency multiset 1/1/1
runtime / version identity
health surface hash identity
arm_baseline PASS
schedule / pool / load-order identity
```

Everything else is reported **descriptively and only descriptively**:

```text
host RAM at start:  A / B / C / D
LM Studio RSS:      A / B / C / D
VRAM used:          A / B / C / D
external load:      A / B / C / D
```

Those numbers are stated. They do **not** become a threshold, a score, or a
pass/fail criterion invented after the fact.

## The rule

```text
PRE-EXISTING QUALIFIED ENVELOPE VIOLATED
  -> integrity consequence according to the already-frozen rules

START WITNESSES DIFFER BUT REMAIN QUALIFIED
  -> state the difference
  -> retain the sequential-arm limitation
  -> cap generality
  -> NO correction, normalisation, or subtraction

NO POSITION REPLICATION
  -> arm effect and wall-clock position cannot be separated statistically
```

## The sentence that governs it

> **With four arms and no replication of position, arm order is NOT ESTIMABLE.**

Not "hard to estimate". Not "adjusted for". Not estimable. If one arm later
produces the most persuasive RAM curve imaginable, nobody gets to invent a
detrending function and recover causality from four perfectly confounded
trajectories.

## Evidence hierarchy

```text
RAW TRAJECTORIES
      |
START-STATE WITNESSES
      |
PRE-FROZEN INTEGRITY RULES
      |
DESCRIPTIVE CROSS-ARM COMPARISON
      |
MECHANISM ONLY AS FAR AS THE DESIGN IDENTIFIES
```

No statistical seance at the bottom.
