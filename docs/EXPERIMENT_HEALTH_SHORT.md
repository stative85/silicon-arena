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

No ecology. No world. No contention. No representation factors. No agents.

```text
model:            qwen3.5-2b first; lfm2.5 and falcon after, unchanged design
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
