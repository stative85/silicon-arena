# HEALTH-SHORT — is the frozen expectation surface valid at short prompts?

**Status:** pre-registered before implementation, model calls, or outcomes.

**Blocker 1 of 2** for ASYNC-B. Strictly upstream of the recovery-coupling
question: in 12 of 12 ASYNC-B cells that produced runtime events, the FIRST
event was `qwen3.5-2b -> DEGRADED`. Every reload followed a health verdict.
Fixing the coupling would not have saved a single cell.

## Question

> Does the frozen expected-TTFT surface produce systematic residual inflation as
> the prompt shrinks through the exact regime ASYNC-B enters — or is qwen3.5
> genuinely degrading there?

Two outcomes, mechanically distinguishable:

```text
MODEL/SURFACE MISMATCH
  residual median drifts upward monotonically as list length falls
  while observed TTFT stays flat
  => the denominator is wrong, not the model

REAL RUNTIME PHENOMENON
  observed TTFT itself rises or destabilises at the short end
  => the model really is slower there
```

## Why this is not a threshold question

`ks = 1.8`, `kh = 20`, `n = 3` are **not** under review and are not touched by
this experiment. The question is whether `expected_ttft(model, prompt_tokens,
load)` — the denominator — is valid below the regime it was fitted in. A ratio
can be wrong because its numerator moved or because its denominator did, and
ASYNC-B cannot tell which.

**NOTHING IS FITTED IN THIS EXPERIMENT.** No knot is added, moved, or
re-measured. HEALTH-SHORT only asks whether a mismatch exists. If it does, the
repair is a separate pre-registration with its own first-passing rule.

## Design

No ecology. No world. No representation factors. No agents.

**Contention IS retained** — see Amendment 1. The pool and the load regime are
part of what is being questioned and are held constant, not removed.

```text
models:           all three probed simultaneously each round (Amendment 1)
runtime:          same explicit residency pool, all three resident
path:             same SERIAL bridge path
max_tokens:       24            (unchanged)
temperature:      0             (unchanged)
response schema:  the same one-field async_action schema
prompts:          the same "Available resources:" format
```

Prompt length is swept over the empirical ASYNC-B list-length regimes:

```text
visible resources:  16  14  12  10  8  6  4
```

ASYNC-B's measured means were A 9.96, C 9.64, B 8.39, D 8.15, so the sweep
brackets the whole observed range and extends past both ends.

Every prompt is **unique** — prefix caching would otherwise make later calls in
a length bucket artificially fast and hide the effect.

## Measured, per call

```text
prompt_tokens        exact, from the usage frame
observed_ttft
expected_ttft        from the FROZEN surface, unmodified
residual
verdict              NORMAL / SUSPECT / DEGRADED / CATASTROPHE
streak state
```

Reported per length bucket: n, median and p95 of observed TTFT, median and p95
of residual, SUSPECT rate, and the count of 3-in-a-row SUSPECT streaks.

## Sequential, not independent

Calls are issued **sequentially within a bucket**, in a single run, and the
`n = 3` streak state is carried exactly as the live detector carries it.

This is deliberate. An independent-call residual distribution cannot answer the
question, because the failure being investigated is a STREAK. Autocorrelation is
the mechanism, so the measurement has to preserve call order. A bucket whose
residuals are individually acceptable can still produce streaks if they are
correlated.

Minimum 120 sequential calls per length bucket per model.

## Pre-registered readings

- **Residual median rises monotonically as list length falls, while observed
  TTFT median stays flat** → the frozen surface is miscalibrated below its
  measured support. ASYNC-B's voids are an artefact of the denominator.
- **Observed TTFT itself rises or destabilises at short lengths** → a real
  runtime phenomenon. The surface is fine and qwen genuinely degrades there.
- **Neither** → the ASYNC-B voids are not explained by prompt length, and the
  monotone void/length correlation needs another explanation.
- **Streak counts far exceed what the per-call SUSPECT rate would predict under
  independence** → autocorrelation is the operative mechanism regardless of
  which of the above holds.

## Void conditions

```text
any model not resident at start or end        -> VOID
runtime DEGRADED/CATASTROPHE on a NON-swept model -> VOID (contaminated pool)
host memory below the frozen 2 GB floor       -> VOID
prompt_tokens unavailable for any call        -> that call excluded, reported
prefix-cache hit suspected (duplicate prompt) -> VOID
```

A DEGRADED verdict on the **swept** model is not a void — it is the observable.

## Explicitly out of scope

No threshold change. No knot refitting. No roster change. No world. No
representation. No ASYNC-B re-run. HEALTH-SHORT answers one question and stops.


---

# Amendment 1 — pool composition and load regime are held constant

Frozen before implementation and before any model call.

## The mistake this prevents

The original design said "use only Qwen initially". That is wrong, and the
project has already paid for this lesson twice.

`bridge_health.gd` records that co-resident composition measurably moves the
contention factor:

```text
contention     beside danube2   beside qwen3.5
lfm2.5             1.1579           1.0874
falcon             1.4809           1.2390
```

Carrying old values across a roster change would have inflated falcon's
expectation by ~20% and made the detector measurably LESS sensitive. The
expectation surface being questioned here was fitted with **LFM2.5 + Qwen3.5 +
Falcon co-resident**, and ASYNC-B exercised it in exactly that pool under
simultaneous three-way submission. Testing Qwen solo would question a surface
under conditions it was never fitted or exercised in, and any result would be
uninterpretable.

## What is held constant

```text
resident pool     LFM2.5 + Qwen3.5 + Falcon, explicit residency
bridge            the same InferenceBridge path
load regime       all three models submitted SIMULTANEOUSLY each round,
                  reproducing ASYNC-B's SERIAL tick (3 submitted, max_active 2)
schema            the same one-field async_action schema
max_tokens        24
temperature       0
health constants  ks = 1.8, kh = 20, n = 3
```

All three models are probed every round and all three are reported. Qwen3.5 is
the primary, because it is the model that voided ASYNC-B, but LFM2.5 and Falcon
come free and their surfaces face the same short-prompt regime.

## Amendment 2 — recovery is suppressed, classification is not

`BridgeHealth.shadow = true` for the duration of HEALTH-SHORT.

Verdicts, residuals, expectations and streak state are computed and recorded
exactly as in live operation. Only the recovery ACTION is suppressed.

**Reason.** A DEGRADED verdict in live mode triggers a reload, and a reload is
precisely the Blocker-2 event. Allowing it here would inject the coupling
confound into the measurement of Blocker 1, and would additionally contaminate
every subsequent length bucket in the sweep with a mid-run pool disturbance.

Shadow mode is not a threshold change and not a repair. `bridge_health.gd`
documents it as the correct mode "when introducing a new model, a new context
length, or a machine whose knots have not been measured: classification
continues, recovery does not". A prompt-length regime below the measured support
is the same kind of situation.

The consequence is stated plainly: HEALTH-SHORT measures whether the detector
WOULD fire and how often, not what happens after it fires. What happens after it
fires is RECOVERY-COUPLING.

## Amendment 3 — chronology preserved, autocorrelation recorded

Calls are issued sequentially within a bucket and analysed in issue order.
**Nothing is shuffled before streak analysis.** A histogram cannot tell whether
three bad calls arrived consecutively.

Additionally recorded, per model per length bucket:

```text
residual lag-1 autocorrelation
```

This is **not** a pass/fail rule and no threshold is attached to it. It is
preserved because if individual residuals look innocuous while streak frequency
explodes, autocorrelation is the obvious mechanical explanation, and the
evidence should exist before anyone moves on.
