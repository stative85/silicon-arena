# ASYNC-A Equalizer Feasibility — Gate 1 Result

**Bridge only. No world, no resource outcomes, no arms, no arm comparisons.**

Instrument: `tools/async_equalizer_check.gd`
Raw: `docs/results/ASYNC_A_EQUALIZER.json`

## Result

```
FROZEN EQUALIZER DELAY   1000 ms  (EQUALIZED_DELAY_TICKS = 4)
superseding              750 ms   (Amendment 4)
```

## Why 750 ms failed

The old constant was justified against measured **solo** small-prompt latencies
of roughly 190-580 ms. That is the wrong load regime. The bridge runs
`max_active = 2`, and ASYNC-A's three agents observe together and submit
together, so one request always waits for a slot.

Observation-to-completion under that real pattern — 60 simultaneous bursts,
unique ASYNC-A-shaped prompts:

```
                          n   median    p95    max
lfm2.5                   60      255    292    312
danube2                  60      353    419    430
falcon                   60      656    837    852
ALL                     180      353    801    852
```

falcon's p95 rises from roughly 580 ms solo to **837 ms** under queue pressure.
Perfectly healthy, and past the old deadline.

```
delay_ms   healthy completions exceeding it
   750     24  (13% of actions)
  1000      0  <- PASS, taken, search stopped
```

Zero transport failures. Zero bridge-health interventions.

**Arm 3 would have voided repeatedly** — not because equalization failed, not
because a model was slow, but because a scheduler queue exists. And it would
have failed *after* outcomes were collected, which is the expensive way to find
out.

## First-pass discipline

1000 ms is the first candidate with zero breaches. The search stopped there and
no prettier value was sought — the same rule that governed the world
calibration, and for the same reason: a delay chosen for producing nicer numbers
would be shaping the experiment around a hoped-for result.

## Consequence, stated

Equalization can only level **upward** without peeking at future completions, so
arm 3's uniform 1000 ms delay now exceeds arm 2's mean natural delay by more
than the original 750 ms would have.

Q2 compares **between-agent differences within each arm**, so this is not a
confound for the question being asked. But arm 3's absolute staleness rate is
expected to exceed arm 2's, and that difference is **not evidence of anything
by itself**.

## What this does and does not establish

**Establishes:** a 1000 ms equalizer is achievable by all three hot-set models
under the exact submission pattern ASYNC-A creates, with no transport failures
and no health interventions.

**Does not establish:** anything about arms, staleness, ordering, or agent
behaviour. No world was instantiated. No outcome was classified.

## Note on agent count

Run at **3 agents**, the preregistered count (Amendment 1: 200 cycles x 3
agents). A five-agent design would put three requests in the queue rather than
one, changing this result materially, and would require its own amendment and
its own re-run of this gate.
