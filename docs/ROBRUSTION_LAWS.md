# ROBRUSTION laws

Methodology laws **earned by a measured failure**, not proposed as good practice.
Each records the event that produced it, so none can later soften into an
aphorism that sounds wise and constrains nothing.

---

## 1. TREATMENT-TO-OBSERVABILITY LAW

```text
A treatment is not causally interpretable until the experiment establishes
whether it changes the probability that its own data are observed, retained,
judged healthy, or allowed to complete.
```

**Earned by ASYNC-B Run 1.** The representation treatment reduced contention,
which raised the accept rate, which shortened the visible list, which lowered
`expected_ttft`, which inflated the health residual, which voided cells —
selectively.

```text
cell   void rate   mean visible-list length
A      0/8         9.96
C      3/8         9.64
B      4/8         8.39
D      5/8         8.15
```

Void rate monotone in list length. The treatment changed the probability that
its own data survived, and the surviving cells in B and D were exactly those
where the pathology did not fire — a biased subsample by construction.

## 2. DETECTOR-SUPPORT LAW

```text
Any variable used in a validity detector's denominator must be qualified over
the range induced by the treatment.

Outside that qualified support, the instrument must not silently extrapolate
and report ordinary health.
```

**Earned by HEALTH-SHORT.** `expected_ttft` extrapolated a downward slope below
its measured support for lfm2.5 and qwen3.5, whose TTFT is dominated by a fixed
cost in that regime:

```text
len 16 -> len 4     ttft change   expected change
lfm2.5                  +1%            -15%
qwen3.5                 -5%            -21%
falcon                 -22%            -19%
```

falcon, whose TTFT genuinely scales with prompt length, is the control that made
the defect readable rather than ambiguous.

This is the runtime-region analogue of `UNPROFILED`, which already exists for
unknown models. **Architecture only — not implemented**, because the support
boundary is not yet known, and implementing it early would replace one arbitrary
detector with another.

## 3. PRODUCTION-PATH EQUIVALENCE LAW

```text
A detector calibration harness must reproduce every runtime dimension known to
materially affect the detector, not merely the variables appearing in its
mathematical formula.
```

**Earned by HEALTH-DUTY.** The formula knows `model`, `prompt_tokens`, `load`.
Matching all three exactly — same pool, same `max_active_during = 2`, same
nominal prompt size — still failed to reproduce production:

```text
ASYNC-B cell A      ~1,600 qwen calls    0 DEGRADED
health harness      same nominal size    13% - 69% SUSPECT
```

The runtime cares about dimensions the formula never mentions.

## 4. DECISION-BOUNDARY AMPLIFICATION LAW

```text
When substantial probability mass lies near a decision threshold, the
thresholded verdict rate must not be used as a measure of effect magnitude.

Report the underlying continuous decision statistic.
```

**Earned by HEALTH-REUSE.** About 60% of qwen's residual mass sits within 0.10
of `ks = 1.8`:

```text
median residual   1.73 -> 1.86
SUSPECT rate       19% -> 75%
```

The rate measures threshold crossings, and measures them correctly. It is simply
a wildly nonlinear proxy for the quantity of interest.

**In force now:** SUSPECT rate is not an endpoint for qwen anywhere downstream.
See RECOVERY-COUPLING Amendment 1, which bars it as treatment evidence while
leaving the `kh = 20` primary untouched — a threshold an order of magnitude
above the dense region is not subject to this law.

---

## What these four have in common

Every one describes the instrument being changed by the thing it was measuring,
or the instrument's stated variables failing to capture what it actually
responds to. That is the specific hazard of running experiments on a substrate
you also built.

The general form:

```text
the specimen can move the microscope's calibration knob
```

The counter-discipline is not more careful reading of results. It is designing
each experiment so the knob-turning is detectable — controls that should not
move, and manipulation checks that must fire.

**On endpoint choice, one correction worth stating explicitly.** The rule is NOT
"choose endpoints away from where the instrument is most sensitive." That
degenerates into designing the experiment around the detector, which is the same
disease wearing a lab coat. The rule is:

```text
Prefer the continuous decision statistic for effect magnitude.

Use thresholded verdicts only when the threshold itself is the object of
interest, and qualify the distribution around that threshold.
```

Humans are astonishingly talented at fixing one metric by inventing another one
to worship.
