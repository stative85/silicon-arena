# RECOVERY-COUPLING — recovery as the independent variable

**Status:** pre-registered before implementation, model calls, or outcomes.

**Blocker 2 of 2** for ASYNC-B. Findings that motivated it, and their limits,
are in `docs/results/RECOVERY_COUPLING.md`.

## Why this experiment exists

Twelve observed instances across ASYNC-A2 and ASYNC-B Run 1, ten of them with
an identical ordering:

```text
qwen3.5-2b  3 consecutive suspect -> DEGRADED -> reload
falcon-h1   residual 30.4x .. 37.3x  >= catastrophe 20x
gap         7,310 .. 8,862 ms
```

**Recovery has never once been the independent variable.** In every instance it
was triggered BY a health verdict, so these remain observationally entangled:

```text
latent runtime degradation -> health verdict -> recovery -> neighbour spike
```

versus

```text
recovery -> neighbour spike
```

Repetition raises the prior. It does not substitute for manipulating the
variable. **This experiment schedules recovery explicitly and never lets the
health system trigger the treatment.** That single change is the entire point.

## Hypotheses

```text
H0: scheduled recovery does not materially alter co-resident neighbour latency
    beyond spontaneous-control behaviour

H1: scheduled recovery produces a reproducible neighbour-latency excursion
```

No cognition. No semantic interpretation. No ecology outcomes. No representation
manipulation. No world.

## Design

```text
POOL       LFM + Qwen + Falcon, all resident, explicit residency mode

CONTROL    no recovery event, probes run for the same clock duration
TREATMENT  scheduled recovery/reload of one model at a preregistered time

ROTATION   recover Qwen   -> probe LFM   + Falcon
           recover Falcon -> probe LFM   + Qwen
           recover LFM    -> probe Qwen  + Falcon
```

Rotation is mandatory. It is what distinguishes:

```text
Qwen-specific        Falcon-specific        pair-specific
                 or  generic residency/reload coupling
```

During the recovery window the two untouched neighbours are probed continuously
with **fixed-size prompts** — fixed so that the denominator cannot move, which
is exactly the ambiguity HEALTH-SHORT exists to resolve for the other blocker.

## Recorded, continuously

```text
neighbour TTFT
neighbour residual        against the FROZEN surface, unmodified
transport status
resident_set hash
GPU memory, host memory
reload start
reload end
first post-reload completion
```

Timestamps are recorded for reload start/end so the neighbour excursion can be
located relative to the reload rather than relative to a verdict.

## Primary comparison

Not "did health fire?" — health firing is a downstream consequence with its own
thresholds. The comparison is distributional:

```text
neighbour residual distribution during a scheduled recovery window
vs
neighbour residual distribution in the same clock window of a no-recovery control
```

Primary mechanical outcome, chosen because it is already frozen and has already
appeared repeatedly:

```text
count of neighbour residual >= 20x
```

`20x` is `kh`, frozen in `bridge_health.gd` and not adjusted for this
experiment. No threshold tuning of any kind.

Secondary: median and p95 neighbour residual, and the latency from reload start
to the first neighbour excursion — the observational data puts that at
7.3-8.9 s and a controlled run either reproduces it or does not.

## Replication

Minimum 10 scheduled-recovery windows and 10 control windows per rotation
position, alternating treatment and control so slow host drift cannot align with
condition.

`n` is the number of recovery WINDOWS, not the number of probe calls. Thousands
of probes inside one reload are one observation of one reload.

## Void conditions

```text
health system triggers a recovery not on the schedule   -> VOID
  (the treatment must be the schedule, never a verdict)
a probed neighbour is itself recovered during a window  -> VOID
pool not exactly the frozen three at window start/end   -> VOID
host memory below the frozen 2 GB floor                 -> VOID
reload fails to complete within the window              -> recorded, window
                                                           excluded, reported
```

## Pre-registered readings

- **Neighbour `>= 20x` count materially higher in treatment than control, across
  rotation positions** → recovery destabilises co-resident neighbours. This is
  a scheduler question, not a threshold question, and the repair gets its own
  pre-registration.
- **Effect present only when Qwen is the recovered model** → Qwen-specific
  reload behaviour.
- **Effect present only on Falcon as neighbour** → Falcon-specific sensitivity.
- **No difference from control** → the twelve observed instances were common
  cause, the wall closes again, and the ASYNC-B voids are attributable entirely
  to Blocker 1.

## Explicitly out of scope

No threshold change. No scheduler change during the experiment. No roster
change. No ASYNC-B re-run. No reinterpretation of ASYNC-A2 or ASYNC-B envelopes
as evidence for either hypothesis — those are observational and stay that way.


---

# Amendment 1 - endpoint discipline after HEALTH-REUSE

Frozen before the first recovery call.

> HEALTH-REUSE established that Qwen residual mass is concentrated near the
> SUSPECT boundary `ks=1.8`, making SUSPECT/DEGRADED rates highly sensitive to
> small level shifts. Therefore SUSPECT rate, DEGRADED count, and
> consecutive-SUSPECT streaks SHALL NOT be used as evidence for treatment effect
> in RECOVERY-COUPLING.
>
> The frozen causal treatment, sample size, recovery schedule, probe timing,
> controls, `ks`, `kh`, and `n` remain unchanged.
>
> The original primary endpoint remains the count/proportion of recovery windows
> containing a neighbor residual `>= kh=20`, compared with matched no-recovery
> windows.
>
> Every neighbor probe SHALL additionally retain the continuous residual and its
> mechanical components: observed TTFT, expected TTFT, prompt tokens, load
> condition, recovered model, neighbor model, probe index, and elapsed time from
> recovery.
>
> Continuous residual distributions SHALL be reported by directed recovery pair
> and control using median, p95, p99, maximum, and the complete observed range.
> SUSPECT/DEGRADED classifications may appear only as audit telemetry.
>
> Verdict-triggered recovery during a measurement window remains VOID exactly as
> frozen.

## Why the primary endpoint is NOT laundered

`kh = 20` sits an order of magnitude above the marginal decision boundary that
HEALTH-REUSE exposed, and the observed neighbour excursions were 30x-60x. The
amplification problem applies to thresholds sitting inside a dense region of the
distribution; it does not apply here. The frozen primary therefore stands
unchanged rather than being rewritten after seeing another experiment's result.

## The causal matrix

```text
RECOVER QWEN   -> LFM residuals, FALCON residuals
RECOVER FALCON -> LFM residuals, QWEN residuals
RECOVER LFM    -> QWEN residuals, FALCON residuals
```

against identical no-recovery windows.

## Frozen interpretation

```text
scheduled qwen recovery repeatedly produces falcon residuals ~30-60
while matched controls stay near baseline
  -> Blocker 2 is causal

recovery shifts falcon 1.2 -> 1.5 but never approaches 20
  -> the spectacular A2/B observation does NOT reproduce causally

every recovery direction raises both neighbours
  -> general reload/residency disturbance, not qwen-specific coupling

only qwen recovery -> falcon catastrophe survives
  -> a directional runtime interaction, and the more interesting result

controls also produce giant excursions
  -> STOP. Recovery is not identified.
```
