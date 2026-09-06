# ASYNC-A — Pre-registration

**Status:** pre-registered. No code exists.
**Written before any implementation, any run, and any result.**

## The question

Four things are normally blended into one blob called "multi-agent behaviour":

```
model output        what a species proposes
world evolution     what changed while it was thinking
latency             how long it took to think
arrival ordering    whose finished thought lands first
```

ASYNC-A separates them mechanically. It asks whether **timing alone** — with
model outputs held constant — produces differences in what the world becomes.

## The central design decision

> A response acts on the world that exists **when cognition finishes**, while
> retaining exact provenance for the world it observed **when cognition began**.

Three things the substrate will **not** do:

- **Not silently refresh the observation.** The agent acted on what it saw.
- **Not silently re-run the request.** A stale thought is not an error to retry.
- **Not pretend the world waited.** No host rescue, no "actually X is gone,
  please reconsider."

The stale-information gap is not a bug to be engineered away. It is a candidate
part of the ecology, and the experiment exists to find out whether it does
anything.

## STALE_CONFLICT, and the tooth that makes it meaningful

An action whose target was valid when observed and is invalid when applied
fails as `STALE_CONFLICT`. That is a **mechanically distinct outcome class**
from ordinary invalid output, and the distinction is the instrument's most
important tooth:

```
target was present in the observed world AND absent now
    -> STALE_CONFLICT          latency had a consequence

target was never present in the observed world
    -> SEMANTIC_INVALID        the model hallucinated a target

payload does not satisfy the schema
    -> SHAPE_FAILED            neither a decision nor infrastructure
```

Collapsing the first two would let a model's hallucination rate masquerade as a
latency effect, which is the whole result. So each request **retains the exact
set of valid targets at its observation version**, and classification consults
that recorded set rather than reasoning about what the model "probably meant".

Without this separation the experiment cannot make its claim, and if the
separation cannot be implemented cleanly the experiment does not run.

## Provenance carried by every cognition request

```
agent_id
request_id

submitted_tick
observation_hash
observation_version
observed_valid_targets        the set, retained for classification

dispatched_ms
first_content_ms
completed_ms

applied_tick
current_world_hash

observation_age_ticks         applied_tick - submitted_tick
world_changed_since_observation
outcome                       ACCEPTED | STALE_CONFLICT
                              | SEMANTIC_INVALID | SHAPE_FAILED
```

Timing fields come from the frozen bridge receipt. ASYNC-A does not re-measure
latency and does not touch bridge health, which is closed infrastructure.

## The world

Deliberately minimal, because the experiment is about timing, not cleverness.

```
12 resources        r_00 .. r_11
each cycle          every agent submits one action: TAKE <id> or PASS
exclusivity         a resource is held by exactly one agent
hold duration       H cycles, then it returns to the pool
regeneration        substrate-owned and deterministic, never model-chosen
```

Contention is the point: several agents can want the same resource, and only the
first application succeeds. The action space is a **single choice from a visible
list**, far smaller than PIT A's typed-operation contract — a deliberate
response to PIT A, where semantic-invalid rates of 0.41-0.99 meant the
descriptors largely measured whether a model could satisfy the contract at all.
If ASYNC-A's agents cannot reliably emit one id from a list, that is a void
condition, not a result.

## Arms

```
1  SERIAL WORLD              the world waits for cognition.
                             observation_age_ticks is always 0.
                             STALE_CONFLICT is structurally impossible.
                             Baseline.

2  NATURAL ASYNC             the world continues. Real bridge completion times
                             decide when proposals arrive.

3  LATENCY-EQUALIZED ASYNC   still asynchronous, but every completion is held
                             to a common delay, removing model speed
                             differences while preserving asynchrony.

4  ARRIVAL-ORDER REPLAY      the actions produced in arm 2, replayed against a
                             fresh world with completion ordering mechanically
                             permuted. No new inference.
```

Arm 3 isolates *asynchrony* from *speed*. Arm 4 isolates *ordering* from
*content*: identical proposals, different sequence.

Arm 1 must show zero `STALE_CONFLICT`. If it does not, the harness is
constructing staleness that the design forbids, and the run is void.

## Replicates actually vary here

PIT A's Phase 2 was NOT ESTIMABLE because temperature 0 with an identical
genesis made three copies of one trajectory. **That does not apply to ASYNC-A.**
Latency is stochastic, so arms 2 and 3 produce genuinely different arrival
orderings between replicates even at temperature 0. Within-species repeatability
is therefore estimable, and will be reported before any between-arm comparison.

Arms 1 and 4 are deterministic given their inputs and are expected to reproduce
exactly; that expectation is itself checked, and a mismatch is an instrument
failure.

## Measures

Per arm, per replicate. Integer counts and rates, no combined score.

```
stale_conflict_count / rate
semantic_invalid_count / rate
shape_failed_count
observation_age_ticks           distribution, per agent
acquisition_count               per agent, per resource
acquisition_gini                concentration across agents
first_arrival_share             fraction of cycles each agent landed first
resource_turnover               distinct holders per resource over the run
```

## Frozen questions and decision rules

**Q1. Does latency have a mechanical consequence at all?**
`STALE_CONFLICT` rate in arm 2 versus arm 1. Arm 1 is structurally zero, so any
non-zero rate in arm 2 answers this. If arm 2's rate is also ~0, the world is
not contested enough for timing to matter, the remaining questions are
unanswerable, and that is reported as such rather than reframed.

**Q2. Do speed differences produce persistent acquisition differences?**
Compare per-agent `acquisition_count` between arms 2 and 3. If the difference
between agents in arm 2 disappears under latency equalization in arm 3, the
difference was caused by model speed, not by anything about the model.

**Q3. Does arrival order alone change outcomes?**
Arm 4 against arm 2 with identical produced actions. Any difference is
attributable to ordering alone, because content is held fixed by construction.

**Pre-committed reading.** A difference that survives arm 3 is *not* explained by
speed. A difference that vanishes in arm 3 *is*. A difference that appears in
arm 4 is ordering, not cognition. These readings are fixed now so they cannot be
chosen after seeing which way the numbers fell.

## Void conditions, fixed in advance

The run is VOID if any of:

- Arm 1 produces any `STALE_CONFLICT`.
- `SHAPE_FAILED` exceeds 10% for any agent — the contract is not expressible and
  the descriptors would measure contract-satisfaction, as in PIT A Run 1.
- `SEMANTIC_INVALID` cannot be mechanically separated from `STALE_CONFLICT` for
  any request.
- Any bridge health `DEGRADED` or `CATASTROPHE` verdict fires during a run. The
  arm is re-run after recovery; a degraded model's latency is not this
  experiment's subject.
- Arm 4 fails to reproduce arm 2 exactly when the permutation is the identity.

Void records are written **before** any repair, as with PIT A Runs 1-3.

## What is deliberately NOT claimed

- Nothing about model quality, intelligence, or strategy.
- No claim that observed specialization is intentional. If a functional
  difference appears — a species that acquires more, or conflicts less — the
  claim is that it *emerged from the coupled mechanics*, and only if it survives
  arm 3 and replicates.
- No claim that these results transfer to other hardware, runtimes, or model
  sets. Latency is a property of this machine's measured regime.
- No fog-of-war, no stigmergy, no topology. Those are later layers and mixing
  them in now would make every result unattributable.

## What ASYNC-A does not touch

Bridge health is **closed infrastructure** (`93f3897`). ASYNC-A consumes its
receipts and never retunes it. An ASYNC-A result that looks strange is not
evidence that the health policy is wrong.

PIT A is closed (`51f446e`) and is not modified, re-run, or reinterpreted.

---

# Amendment 1: substrate-only world-feasibility calibration

**Written before any calibration run and before any ASYNC-A implementation.**

A world where nobody ever collides cannot answer Q1-Q3. A world where every
observation is stale answers them trivially and uselessly. The world's pressure
parameters must therefore be shown to sit inside a feasibility window **before**
the main run — but that check must not become a small ASYNC-A that leaks
outcome information.

## What calibration may and may not do

> Calibration may test whether the substrate can mechanically generate
> contention and stale-eligible opportunities. It may **not** use ASYNC-A
> agents, arm assignments, model outputs, or arm-level effect estimates.
> Calibration may change only world-pressure parameters — resource count and
> hold/regeneration timing — according to a predeclared rule. Once calibrated,
> those parameters **freeze for all four arms**.

**No LM inference occurs during calibration.** Actors are synthetic, choose a
legal target mechanically, and have completion delays drawn from a fixed seeded
distribution. There are no prompts, no model outputs, and therefore no semantic
failures to confound the measurement.

Calibration asks exactly one question:

```
Can this world generate the event ASYNC-A is supposed to study?
```

It does not ask, and cannot answer, whether natural async differs from
equalized async.

## The three instrumented quantities

```
contention_opportunity
    >= 2 actors observed the same currently-valid target

stale_eligible
    a target was valid in actor A's observation, and another applied action
    invalidated it before A's scheduled application

stale_conflict
    A then actually attempted that exact formerly-valid target
```

The first two are the calibration's subject. `stale_conflict` needs no model to
produce and is instrumented only for the controls below.

This separation distinguishes two completely different nulls:

```
WORLD CANNOT PRODUCE STALENESS
    stale_eligible ~ 0   -> the world is the problem

WORLD PRODUCES OPPORTUNITIES BUT AGENTS DO NOT ENTER THEM
    stale_eligible high, stale_conflict ~ 0 in the main run
    -> the agents are the finding, not the world
```

## Calibration controls: one negative, one positive

```
ZERO-DELAY synthetic actors     every completion delay = 0
    MUST produce stale_conflict == 0
    If it does not, the harness manufactures staleness where time cannot
    cause it, and calibration is void.

INJECTED-DELAY synthetic actors  delays from a fixed seeded distribution
    MUST produce stale_eligible inside the feasibility window
```

The negative control mirrors ASYNC-A's arm 1 exactly: one shows the world is
*capable* of the phenomenon, the other shows the harness does not *manufacture*
it when time cannot cause it.

## The feasibility window, declared before any calibration output

The main run is **200 cycles x 3 agents = 600 actions per replicate**, 3
replicates per arm. The floor is set so a preregistered comparison is not
estimated from a handful of accidents:

```
stale_eligible_rate  >=  0.05      (>= 30 events per replicate, >= 90 per arm)
stale_eligible_rate  <=  0.40      saturation ceiling
```

The floor comes from the planned denominator, **not** from what calibration
happens to produce. The ceiling exists because a world in which most
observations are already invalid degenerates ASYNC-A into "does latency make
everyone trip over each other constantly", which is not the question.

The window is deliberately **broad, not optimised**.

## Parameter selection: deterministic, first-pass, no further search

Frozen sequence, loosest to tightest. Step 0 is the starting configuration:

```
step   resources   hold_H
 -2       20          4
 -1       16          4
  0       12          6     <- start
  1       10          6
  2        8          6
  3        8          9
  4        6          9
  5        6         12
  6        4         12
```

```
Evaluate step 0.
  below the floor    -> move toward tighter pressure (+1, +2, ...)
  above the ceiling  -> move toward looser pressure (-1, -2, ...)
Take the FIRST configuration inside the window. Stop. Never optimise further.
If no step passes, ASYNC-A is not feasible with this world and that is the
reported result.
```

The **first-passing rule is the point.** Without it the search would discover
that some configuration produces deliciously dramatic conflict, and the world
would end up shaped around the result we hoped to see. A configuration is not
preferred for producing a better number; it is accepted for being the first one
that is adequate.

Regeneration remains substrate-owned and deterministic in every configuration.

## The STALE_CONFLICT predicate, stated as code

Load-bearing, and to be implemented literally:

```
X = proposal target

X in observed_valid_targets
    AND X not in current_valid_targets
    AND X was invalidated after observation_version
        => STALE_CONFLICT

X not in observed_valid_targets
        => SEMANTIC_INVALID
```

Anything else is **not latency evidence**. The middle clause is not redundant
with the first two: a target may be absent now for reasons unrelated to the
observation window, and only an invalidation recorded *after* the observation
version makes it a latency effect.

## Calibration void conditions

- Zero-delay control produces any `stale_conflict`.
- The world implementation used in calibration is not the same code ASYNC-A
  runs. Calibrating a different world than the one measured is worthless.
- Any LM inference occurs during calibration.
- More than one configuration is evaluated after the first passing one.

---

# Amendment 2: CONTENTION_LOST, forced by the negative control

**Written after the zero-delay control failed and before any parameter was
changed or any positive run was accepted.**

The zero-delay negative control failed on every configuration, producing 57-336
`STALE_CONFLICT` events where time cannot cause staleness. The control was
right and the predicate was wrong.

## The conflation

With zero delay, all actors observe the **same** world version, several may
choose the same target, and applications resolve in order. The loser's target
was in its observed valid set and was invalidated at a version after its
observation — so Amendment 1's predicate labelled it `STALE_CONFLICT`.

But **no world-time elapsed.** The loser did not lose because its information
aged. It lost a simultaneous race. Two different mechanisms were wearing one
name:

```
CONTENTION            several agents observed the SAME world and wanted the
                      same thing. One wins. Nothing went stale.

STALENESS             an agent observed X free, the world moved on while it was
                      thinking, and its action arrived into a changed world.
```

Only the second is latency evidence, and ASYNC-A's entire claim rests on
measuring the second.

## The corrected predicate

A fourth outcome class is added:

```
X in observed_valid_targets
  AND X not in current_valid_targets
  AND X invalidated after observation_version
  AND observation_age_ticks > 0
      => STALE_CONFLICT        latency had a consequence

X in observed_valid_targets
  AND X not in current_valid_targets
  AND observation_age_ticks == 0
      => CONTENTION_LOST       simultaneous race, NOT latency evidence

X not in observed_valid_targets
      => SEMANTIC_INVALID      hallucinated target
```

`observation_age_ticks > 0` is the load-bearing addition. Latency evidence
requires latency.

## Why this is a correction and not tuning

The distinction matters, so it is stated plainly: this amendment changes an
**outcome definition that was demonstrably conflating two mechanisms**, exposed
by a control designed to expose exactly that. It does not change the feasibility
window, the parameter sequence, the first-pass rule, or any threshold, and it
was made before any positive-sweep result was accepted.

Widening the window to make a failing control pass would have been tuning.
Splitting a class that provably contained two different phenomena is what the
control was built to force.

## Consequences

- `CONTENTION_LOST` is measured and reported in its own right. It is a real
  property of a contested world and is expected to be non-zero in every arm,
  including arm 1.
- ASYNC-A **arm 1 (SERIAL WORLD)** now has a sharper meaning: the world waits,
  so `observation_age_ticks` is always 0, so `STALE_CONFLICT` is *structurally*
  impossible while `CONTENTION_LOST` may still occur. The arm-1 void condition
  is unchanged and is now enforced by construction rather than by hope.
- The measures list gains `contention_lost_count / rate`.
- Q1 compares `STALE_CONFLICT` rates and is unaffected in intent, but is now
  measuring only what its name claims.
