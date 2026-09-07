# ASYNC-A2 Roster and Gate Results

Successor to ASYNC-A Run 1 (VOID, `241d86c`). Roster: lfm2.5 + qwen3.5 +
falcon-h1. danube2 retired.

## Gate 1 — the contract

200 calls per candidate, same one-field contract, same `response_format`, same
temperature, unique observations. No world, no timing comparisons, no outcomes.
Criterion `SHAPE_FAILED <= 10%`.

```
liquidai/lfm2.5-1.2b-instruct   QUALIFIED   0.0%   0/200
falcon-h1-1.5b-instruct         QUALIFIED   0.0%   0/200
qwen3.5-2b                      QUALIFIED   0.0%   0/200
```

Zero transport failures. The contract was never the problem: danube2 was
uniquely incompatible with it.

## Gate 3 — the equalizer, at run-equivalent exposure

**The gate itself was underpowered and has been corrected.** It previously used
60 bursts (180 completions) and passed 1000 ms — yet ASYNC-A Run 1's EQUALIZED
arm generated ~600 completions and hit a breach at that same deadline. 180
samples do not reach the tail an 800-tick replicate reaches.

Now 200 bursts = 600 completions, approximately one EQUALIZED replicate's
exposure, with **all candidates tested against one completion corpus** — a
fresh run per candidate would let candidate testing change the runtime
conditions it is measuring.

```
MODEL                              n   median    p95    max
liquidai/lfm2.5-1.2b-instruct    200      243    266    307
qwen3.5-2b                       200      568    706    784
falcon-h1-1.5b-instruct          200      766    799    958
ALL                              600      568    790    958

delay_ms   breaches
   750        146
  1000          0   <- PASS, taken
```

`EQUALIZED_DELAY_TICKS` stays **4**. Because the horizon was derived from the
4-tick cadence, the 800-tick horizon also stands unchanged.

### A stall regime that did not recur

An immediately preceding 180-completion run of this same gate, on this same
pool, produced two completions at **12,299 ms and 12,665 ms** — roughly 15-20x
their model's median, while every other sample was normal.

They did not recur across the subsequent 600 completions. Both observations are
real:

- 1000 ms is feasible across run-equivalent exposure.
- The pool can still produce multi-second stalls that a single gate run may
  miss entirely.

The delay is **not** raised to cover the stall regime. A stall of that size is
a health event, not a queueing cost, and inflating the equalizer to absorb
pathology would hide exactly what the health detector exists to catch. If such
a stall occurs during ASYNC-A2, the arm voids — as designed.

Health interventions during the passing run: 0. Note that qwen3.5 was
`UNPROFILED` throughout, so it could not have been flagged (see below).

## Infrastructure hole closed: UNPROFILED

A model absent from `BridgeHealth.KNOTS` previously produced `expected_ttft = -1`
and classified as **NORMAL** — silently unmonitored while looking healthy. That
is worse than shadow mode, which suppresses action but still classifies.

Such a model now classifies as `UNPROFILED`. It never triggers recovery — there
is nothing to recover from — but a measured experiment refuses to start:

```
FAIL UNPROFILED models on the roster: ["qwen3.5-2b"]
     qualify them before a measured run
```

General fix, not a qwen special case.

## Still outstanding before ASYNC-A2

**Gate 2 — new-pool health qualification.** The expectation surface must be
re-characterised for the whole pool, not just qwen. The bridge's expectation is
conditioned on model *and load*, and the existing lfm2.5 and falcon knots were
measured beside danube2. Reusing them beside qwen would assume co-resident
composition cannot affect latency — an assumption this project's residency work
has already destroyed.

```
collection A   fit new expectation surfaces
collection B   held-out validation
```

`ks = 1.8`, `kh = 20`, `n = 3` stay **frozen** and get no vote in the fit. Since
they were selected on the old corpora, collection B is a genuine external test
rather than another selection corpus.

**ASYNC-A2 pre-registration**, including the explicit boundary:

> Data from ASYNC-A Run 1 are not used to estimate timing effects, select
> hypotheses, or choose expected effect directions. They are used only to
> diagnose the preregistered void and to repair roster and runtime
> qualification for the successor experiment.
