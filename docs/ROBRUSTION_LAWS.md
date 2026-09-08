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

### Corollary 1a — treatment-aware witness construction

```text
A treatment-aware integrity witness must distinguish treatment-defined state
transitions from violations of the invariant it protects.
```

**Earned by the RUNTIME-MEMORY `BACKEND_RESTARTED_MID_ARM` defect,
2026-09-07.** The tooth compared the complete LM Studio PID set for equality.
Scheduled recovery replaces model-worker processes by design, so the detector
labelled the treatment itself as contamination: **676 offences in arm C, 582 in
arm D**, both arms flagged, while the invariant it existed to protect — backend
lifetime continuity — had in fact held throughout (9 processes present in every
sample, set size never leaving 11-12, and for arm D the core pid and its
creation time verified unchanged).

**THIS IS DELIBERATELY NOT LAW 6.** The redundancy test was run before giving it
a number, and it failed to earn one:

```text
Law 1 (Treatment-to-Observability)
    an EPISTEMIC requirement on the experimenter:
    establish whether the treatment changes the probability that its own data
    are observed, retained, judged healthy, or allowed to complete

Corollary 1a
    the CONSTRUCTIVE counterpart on the instrument:
    build the detector so that it does not, by conflating a treatment-defined
    transition with a violation
```

The PID defect is Law 1's mechanism arriving through a detector rather than
through a resource: the treatment changed the probability that its own windows
were retained. Same law, different delivery. Promoting it to Law 6 would inflate
the count without adding a distinct failure mode, and this file exists to be
hard to cheat rather than impressive.

**Reference implementation of the corollary:** `RecoveryGate.flex_model`. It
relaxes exactly one model, for exactly the duration of that model's own
scheduled recovery, tolerates 0 or 1 instances and never 2 or more, refuses to
excuse any other model's disappearance or any foreign model, and records the
expectation in force with every sample so the relaxation cannot be applied
retroactively. Proven by `tools/detector_audit_selftest.gd`.

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


## 5. CARDINALITY IS STATE LAW

```text
When a runtime can instantiate the same logical resource more than once,
presence is insufficient evidence of state. Validation must preserve
multiplicity.
```

**Earned by the RECOVERY-COUPLING step-2 restore bug.** A restore loop called
`lms load` on already-resident models. `lms load` is **not idempotent** — it
spawns a second instance:

```text
intended                     actual
qwen3.5-2b       = 1         qwen3.5-2b       = 1
                             qwen3.5-2b:2     = 1
falcon           = 1         falcon           = 1
                             falcon:2         = 1
lfm2.5           = 1         lfm2.5           = 1
                             ----------------------
                             5 instances, 7,656 of 8,151 MiB VRAM
```

A presence-based check certified that as "pool restored", because every expected
model *was* present. `{qwen, falcon}` and `{qwen, qwen, falcon}` are the same
mathematical set and radically different runtime states.

The invariant is therefore an exact **count map**, not a set, and an extra
instance of any model fails the witness. `RecoveryGate.classify()` distinguishes
`UNEXPECTED_DUPLICATE`, `UNEXPECTED_DISAPPEARANCE`, `UNEXPECTED_REPLACEMENT` and
`UNEXPECTED_RESIDENT_MODEL`, because "something changed" is not actionable and
those four have different causes.

**This one travels furthest.** Containers, GPU workers, DB replicas, model
servers, subprocesses, agent pools — anywhere a `create`/`load`/`start` call is
assumed idempotent and is not, presence-based health checks will certify a
corrupted runtime as healthy.

## 6. EXECUTION-BOUNDARY LAW

```text
A safety or experimental boundary that exists only as an instruction is weaker
than a boundary enforced by the execution path.

If violating the boundary can invalidate evidence or mutate protected runtime
state, the toolchain must make the forbidden action mechanically hard or
impossible.
```

**Earned by the night shift of 2026-09-07.** Operating under an explicit
`treat LM Studio as READ-ONLY / DO-NOT-CONTACT` instruction, the agent ran
`recovery_tooth_selftest.gd` as a routine regression check after editing
`recovery_gate.gd`. That suite is not a unit test: it performed **four real
unload/reload cycles, a neighbour eviction, and liveness inference** before the
violation was noticed.

Evidence integrity survived — the artifacts were already committed and the
backend core never restarted — but **runtime state did not**, and the current
LM Studio memory state can no longer be treated as a continuation of the
measured experimental state.

```text
requested boundary   LM Studio READ-ONLY / DO-NOT-CONTACT
enforcement          prose only
outcome              violated within the hour, by the party that read it
```

Nothing in the repository distinguished a pure unit test from one that drives
the runtime: same directory, same `*_selftest.gd` naming, same green output.

**REDUNDANCY TEST, run before granting a number.** Laws 1-5 and Corollary 1a all
govern **measurement validity** — whether an instrument reports the truth about
an experiment. This one governs **operational enforcement** — whether a stated
constraint survives contact with an operator. Nothing above covers it, and the
failure mode is available to any system whose safety rules live in
documentation. It earns Law 6.

**Enforcement built in response:** `tools/run_safe_tests.py` classifies every
suite `NO_CONTACT` / `CONTACT_REQUIRED` / `STATE_MUTATING`, defaults to the
no-contact set, requires explicit clearance for contact and additionally
`--attended` for state-mutating suites.

The classification **fails closed**: test-shaped files are discovered from disk,
and an unclassified suite is a hard error. Its first run found **32 unclassified
suites** in a repository where 12 had been registered by hand.

**Where this travels:** agents, CI systems, lab automation, database migrations,
autonomous coding, robotics — anywhere `don't touch X` currently means
`please remember not to`.

---

## What these six have in common

Laws 1-4 describe the instrument being changed by the thing it was measuring,
or its stated variables failing to capture what it actually responds to. Law 5
is the same disease one level down: the instrument's model of the runtime was
too coarse to represent the state the runtime could actually be in.

**Law 6 is a different family.** The first five are about an instrument lying
about an experiment. The sixth is about a rule failing to bind the operator —
including when the operator is the same system that wrote the rule down. That is the specific hazard of running experiments on a substrate
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
