# RECOVERY-COUPLING qualification — results

```text
run_kind          QUALIFICATION
evidence_eligible false
not evidence, not part of causal n, not interpretable for treatment effect
```

Two live passes of the same 6 windows — one per (rotation position x condition)
— at schedule hash `9c9dbd9ca0c45252`. Purpose is end-to-end executor proof, not
statistics.

## What the qualification proved

**The executor honours the gate verdict.** Window 1 was deliberately
contaminated with a synthetic unscheduled recovery. In pass 1 it voided with
`reason = UNSCHEDULED_RECOVERY`, and its subsequent `post` sample returning
CLEAN did **not** erase the void. In pass 2, where a RAM offence happened to
occur first, the injected offence is still preserved in the offence list:

```text
window 1 offence kinds: {RAM_FLOOR_EVENT: 75, UNSCHEDULED_RECOVERY: 1}
```

First-offence-wins ordering held, and nothing was lost.

**The recovery primitive works across windows.** Three verified recoveries per
pass, epochs advancing `0 -> 1 -> 2 -> 3`, monotone, exactly once each, never on
a control. Every control reported `recovery_verified = false` and no epoch.

**The pool was restored every window**, exact count map, in both passes.

**Health shadow was on throughout**, so verdict-triggered recovery was
structurally impossible rather than merely detected.

## Defect 1, found and fixed: shared HTTP transport

Pass 1 voided **all three TREATMENT windows** with
`TRANSPORT_OR_RUNTIME_FAILURE`:

```text
ERROR: HTTPRequest is processing a request.
  resident_set -> residency_counts -> gate.sample -> _probe_until
```

The gate's residency sampling and the concurrently-running recovery's own
residency reads shared one `HTTPRequest` node. Sequential code never contended
for it — **the concurrency fix that made probes run through the reload is what
created the collision.**

Had this gone straight to 60 windows, every treatment window would have voided
and every control would have passed: a clean, reproducible, entirely false
result reading "recovery causes runtime failures".

Fixed by giving the gate and the recovery separate transports. Pass 2: **0
invalid records in all six windows**, and window 40 (a real TREATMENT with a
verified recovery) came back fully clean.

## Defect 2, NOT fixed: the RAM floor fires on runtime history

Pass 2 host free RAM, per window:

```text
win  cond        min_MB   max_MB  offences  first_offence
0    TREATMENT     1159    10304        11  RAM_FLOOR_EVENT
1    CONTROL        734     1102        76  RAM_FLOOR_EVENT
20   TREATMENT      681     9173        22  RAM_FLOOR_EVENT
21   CONTROL       8870     9104         0  -
40   TREATMENT     8152    16113         0  -
41   CONTROL      10813    13942         0  -
```

The reading is verified, not an instrument artifact: Godot's
`OS.get_memory_info()["free"]` was checked against Windows `GlobalMemoryStatusEx`
at the same instant — 11,026 MB vs 11,061 MB `AvailPhys`. The guard reads
physical available memory correctly.

**The pattern is not "recovery crushes RAM".** Window 40 performed a genuine
verified recovery and never dropped below 8,152 MB. The collapse is concentrated
in the first two windows of the pass — which began immediately after pass 1
finished, inheriting its runtime state.

That is accumulated **runtime history**, the same variable HEALTH-DUTY and
HEALTH-REUSE implicated and neither could isolate. It is exactly the reason the
qualification must not roll straight into the causal run.

**No threshold was changed.** Lowering the 2 GB floor after seeing which windows
died is precisely the move the protocol forbids.

## Consequence for the causal run

Starting 60 windows from this runtime state would void a large, non-random share
of them — and the voids would correlate with position in the run rather than
with condition. That is the Treatment-to-Observability hazard arriving by a
different road.

The frozen prereg specifies pool exactness, the memory floor, and no
verdict-triggered recovery. It says **nothing** about how the experiment-start
state is established. That gap is closed by Amendment 2 before any causal call,
not improvised at run time.
