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

---

# Amendment 3: resource generations, STALE_REVALIDATED, and the three denominators

**Written before the ASYNC-A harness exists, because this changes what can be
measured rather than merely what is logged.**

## The ABA hole, demonstrated

Deterministic regeneration creates a classic ABA problem. Verified against the
current world before amending:

```
A observes r_00 free           version 0
B takes r_00                   version 1
two ticks pass, r_00 released  version 2
A's aged request arrives       -> ACCEPTED, age 2, nothing recorded
```

Tracking validity by target id alone, `r_00` was valid when observed and is
valid now, so the action succeeds. But A acted on an **old instance of
reality**: the resource disappeared and came back while A was thinking. Latency
touched that opportunity and the instrument could not see it.

This hides latency effects exactly as badly as conflating simultaneous
contention with staleness did, and for the same reason — an identifier is not
an identity.

## Resource identity is now (id, generation)

Every resource carries a `generation`, incremented when it is released back to
the pool. A resource that has been taken and released is a **new instance** of
the same id.

Recorded on every action:

```
observed_target_generation
current_target_generation
invalidated_since_observation
revalidated_since_observation
```

## STALE_REVALIDATED

```
X valid when observed
X invalid now
age > 0
    => STALE_CONFLICT          latency destroyed the opportunity

X valid when observed
X disappeared and regenerated
X valid again now
generation changed
    => ACCEPTED, stale_revalidated = true
```

**The action succeeds.** The substrate does not rescue the agent and does not
reject it either; it records what happened. That is the same discipline as
refusing to refresh a stale observation — the world is not obliged to protect an
agent from the consequences of its own latency, in either direction.

What this buys is a richer statement than a conflict count alone:

> aged cognition can fail because reality changed, and can accidentally become
> valid again because reality changed twice.

The instrumentation still knows latency touched the opportunity, which is the
part that matters.

## Three denominators, always reported together

A single stale-conflict rate answers a question nobody asked. Every ASYNC-A
result reports all three:

```
STALE_CONFLICT / all_actions        How often does stale failure happen?

STALE_CONFLICT / stale_eligible     When latency creates danger, how often do
                                    agents actually walk into it?

STALE_ELIGIBLE / all_actions        How often does the world create
                                    latency-sensitive situations at all?
```

The calibration makes the second one interpretable: synthetic actors produced
`stale_eligible == stale_conflict` exactly (983/983, 687/687), because a
synthetic actor always attempts the target it chose. That is the **world-side
ceiling**. If the main run yields, say, 400 eligible and 120 conflicts, the gap
is not a bug — it means the world created 400 aged opportunities and the agents
entered 120 of them. That ratio is a property of the agents, measurable only
because the ceiling is known.

## The action envelope

Carried by every request so no later analysis reconstructs anything:

```
request_id                      agent_id
observed_tick                   observation_version
observation_hash                visible_target_ids
visible_target_generations      chosen_target_id
chosen_target_generation        completed_at
applied_tick                    current_target_generation
observation_age_ticks           outcome
stale_revalidated
```

## One harness, four timing policies

ASYNC-A is **one harness in which only the release/application rule changes**:

```
                SAME WORLD
                SAME ACTION API
                SAME VALIDATOR
                SAME TELEMETRY
                     |
       +-------------+-------------+
       |             |             |
    SERIAL       NATURAL       EQUALIZED
       |             |             |
       +-------------+-------------+
                     |
               ORDER REPLAY
```

The experimental invariant is therefore structural rather than promised:

> **Arms differ in time treatment, not world physics.**

Four separate arena implementations would make that a claim to be trusted. One
harness makes it a fact about the code.

### Per-arm teeth

**Arm 1 SERIAL** — any violation voids:
```
observation_age_ticks == 0 for every action
STALE_CONFLICT       == 0
STALE_REVALIDATED    == 0
```

**Arm 2 NATURAL ASYNC** — real bridge completion timing, real arrival ordering,
the world never waits.

**Arm 3 LATENCY-EQUALIZED** — the equalizer touches **release timing only**. Not
prompts, not observations, not generated actions, not semantic content. If
equalization changes what the model saw, speed is no longer what is being
isolated, and the arm is void.

**Arm 4 ARRIVAL-ORDER REPLAY** — brutal:
```
action bytes            identical to arm 2
request provenance      identical
observed target set     identical
world genesis           identical
ONLY application ordering differs
```
**If any model is called during arm 4, the arm is contaminated and void.** It
replays already-produced action envelopes.

---

# Amendment 4: release rules locked, ordering transform frozen

**Written before the harness exists. Arm 3 is the dangerous one and is
specified first.**

## Tick base

```
TICK_MS = 250        frozen. The world advances one tick per 250 ms wall time.
```

A request submitted at tick T with wall-clock completion W applies at
`ceil(W / TICK_MS)`.

## Arm 3 — EQUALIZED, ex ante, never a barrier

**Latency-equalized must not mean "wait until everyone finishes, then release
together."** That is a barrier: it converts asynchrony into batch
synchronisation, and the arm would no longer be asynchronous at all. It equally
must not use the slowest completion in the current cycle as the equalizer,
because that **peeks at future completions** — information the substrate cannot
have at release time.

The only safe form is an **ex ante delay schedule, frozen before the run**:

```
EQUALIZED_DELAY_TICKS = 3      frozen (750 ms at TICK_MS = 250)

for every request:
    observed at tick T
    the model finishes whenever it finishes
    the action MAY NOT release before T + EQUALIZED_DELAY_TICKS
```

So arm 3 means *all agents experience the same cognition delay regardless of
model speed* — not *everybody waits for the slowest one*.

### The leak, and the tooth that catches it

If a model finishes **later** than `T + EQUALIZED_DELAY_TICKS`, its real latency
has leaked back in and the arm is no longer isolating speed. Such completions
are classified separately as `EQUALIZER_BREACH`, and **any breach voids the
arm.**

3 ticks (750 ms) is chosen against the measured small-prompt envelope: total
latencies for prompts of this size measured roughly 190-580 ms across the three
models, so 750 ms clears the slowest with margin. If breaches occur, the healthy
envelope has moved and that is itself information — the delay is **not** silently
enlarged. Changing it requires an amendment.

### A property of equalization, stated rather than hidden

Equalization can only level **upward** without peeking at the future. Arm 3's
uniform delay therefore exceeds the mean natural delay, so arm 3 has somewhat
**greater absolute staleness exposure** than arm 2.

This is not a confound for the question being asked. Q2 compares the
**between-agent difference within each arm**, and equalization removes
between-agent variance in delay. A difference in absolute rate between arms 2
and 3 is expected and is not evidence of anything by itself.

## Arm 4 — ORDER_REPLAY, paired replicate-by-replicate

Arm 4 is paired to a specific arm 2 replicate, not to arm 2 in aggregate.

```
FROM the natural replicate:   action envelopes
                              observation provenance
                              completion order

ARM 4 USES:                   the same genesis
                              the same action envelopes
                              the same observation provenance
                              the same action bytes
                              a different application ordering

ARM 4 MUST NOT:               call any model
                              regenerate any observation
                              reconstruct provenance from current world state
```

### The ordering transform, frozen now

```
LATENCY-RANK INVERSION
    fastest natural arrival  ->  applied LAST
    slowest natural arrival  ->  applied FIRST
```

Chosen before any result, and chosen because it asks the question directly: did
the natural ordering itself matter? It is a mechanical queue inversion with no
semantic decision anywhere in it. Ties break by request_id for determinism.

An identity permutation must reproduce arm 2 exactly; that check is a void
condition already recorded in Amendment 1.

## Envelope immutability

```
observation_version
observation_hash
visible_target_ids
visible_target_generations
chosen_target
chosen_target_generation
```

**Immutable after submission.** No arm regenerates them. No replay reconstructs
them from current world state.

The action envelope is **evidence**, not a suggestion. Treating it as
reconstructible would let arm 4 quietly re-derive a provenance that agrees with
whatever the replayed world happens to look like, which would make the arm
unfalsifiable. The harness asserts immutability rather than trusting itself.

## LATENCY_TOUCHED, and the reporting set

The generation fix created a second way for reality to move under an action, so
the two are reported separately and also together:

```
LATENCY_TOUCHED = STALE_CONFLICT + STALE_REVALIDATED
```

They are different outcomes and are never merged into one number, but together
they answer: *how often did reality change underneath an action between
observation and application?*

Every arm reports:

```
stale_eligible     / all_actions        does the world create the situation?
stale_conflict     / stale_eligible     do agents walk into it?
stale_revalidated  / stale_eligible     do agents accidentally survive it?
latency_touched    / all_actions        how often did reality move at all?
contention_lost    / all_actions        same-time competition, NOT latency
```

`STALE_REVALIDATED` is the strange one and is worth naming plainly: *the agent
was wrong, the world changed again, and the agent became right by accident.* A
simpler instrument erases that case entirely by scoring it as an ordinary
success.

`CONTENTION_LOST` is retained in every arm as a **negative control**. It is
same-time competition and must not depend on latency. If `CONTENTION_LOST` and
`STALE_CONFLICT` start moving together, the harness is inspected before any
story is told.

## Harness architecture

```
AsyncRequestEnvelope     observation provenance, visible target generations,
                         selected target, immutable payload

TimingPolicy             SERIAL | NATURAL | EQUALIZED | ORDER_REPLAY
                         the ONLY thing that differs between arms

AsyncWorld               one implementation, all arms

OutcomeClassifier        ACCEPTED | CONTENTION_LOST | STALE_CONFLICT
                         | STALE_REVALIDATED | SEMANTIC_INVALID | SHAPE_FAILED
```

One experiment engine, four clocks. The harness is deliberately boring: if
ASYNC-A produces something strange, the strangeness must come from time
interacting with agents, not from a clever harness bug.

---

# Amendment 5: agent lifecycle, clock mapping, and the action contract

**Written before the run loop exists.** Amendment 4 fixed *when an action is
released*. That is not sufficient to equalize cognition.

## The basement window

A fixed release tick equalizes when actions **land**. It does not equalize how
often an agent gets to **think**:

```
Agent A observes at tick 10, finishes at 10.4, released at 13
Agent B observes at tick 10, finishes at 12.2, released at 13
```

Both release at 13, so arm 3 looks equalized. But if A may begin its next
cognition the moment it *completes* at 10.4, A is already working on request #2
while B is still finishing request #1. Over 200 cycles the faster model
accumulates more observations, more submissions, and more chances to take
resources — **and model speed is back in the experiment**, having entered
through cadence rather than release.

## ONE OUTSTANDING COGNITION PER AGENT

```
observe
   |
submit
   |
complete
   |
WAIT FOR TIMING POLICY RELEASE     <-- the gate
   |
apply / close envelope
   |
ONLY THEN may that agent observe again
```

The next observation is gated on **envelope close**, never on completion. One
outstanding cognition per agent, always, in every arm.

What this yields per arm:

```
ARM 1 SERIAL       trivially one at a time
ARM 2 NATURAL      real latency changes when the envelope closes, so it
                   naturally changes cognition cadence -- which is the effect
                   under study, not a leak
ARM 3 EQUALIZED    every envelope closes on the equalized schedule, so model
                   speed cannot create hidden extra thinking opportunities
ARM 4 REPLAY       no cognition at all
```

Arm 2 *should* have speed-dependent cadence. Arm 3 must not. That difference is
the experiment.

### Required sabotage test

```
gate the next request on COMPLETION instead of RELEASE
    -> the faster synthetic agent obtains more observations and submissions
    -> the test MUST go red
```

If that sabotage does not go red, the gate is not load-bearing and the arm-3
result means nothing.

## Wall clock to world tick: one frozen mapping

There are now two clocks — real bridge milliseconds and world ticks — and
exactly one mapping between them:

```
TICK_MS = 250                                   frozen

tick_of(ms)      = floor((ms - run_start_ms) / TICK_MS)
tick_start_ms(t) = run_start_ms + t * TICK_MS
```

**World time is never derived from frame rate.** A headless machine running at
900 FPS must not produce a different ecology from one where the OS pauses to
think about something else. `_process()` may drive the *loop*, but the world
clock is computed from wall time.

### The breach predicate, in milliseconds

The 3-tick equalizer is 750 ms, and the relationship is explicit rather than
implied:

```
3 ticks x 250 ms/tick = 750 ms

release_deadline_ms = tick_start_ms(observed_tick) + 750
completion_ms > release_deadline_ms   =>  EQUALIZER_BREACH  =>  VOID
```

Milliseconds compared with milliseconds. No approximate comparison between a
tick counter and wall time.

## The action contract

Exactly **one** model-controlled field:

```json
{"target_id": "r_07"}
```

No explanation. No operation type. No confidence. No prose. No reason.

```
type                  object
required              ["target_id"]
additionalProperties  false
target_id             string
```

Dramatically smaller than PIT A's typed-operation contract, which is
deliberate: PIT A's semantic-invalid rates of 0.41-0.99 meant its descriptors
largely measured whether a model could satisfy the contract at all.

### The schema must NOT enumerate the visible target ids

**Load-bearing.** If the JSON schema constrains `target_id` to an enum of the
currently visible ids, the runtime may make it impossible for a model to emit
an invalid target — and `SEMANTIC_INVALID` would be mechanically removed as an
observable outcome.

That is not a safety improvement. It is the silent deletion of a control
variable: the whole point of separating `SEMANTIC_INVALID` from
`STALE_CONFLICT` is that a model's hallucination rate must not be able to
masquerade as a latency effect. If hallucination cannot occur, that separation
can never be checked against real behaviour.

`target_id` is therefore a free string, and validity is judged after the fact
against the sealed observation.

## Classification, complete

```
JSON parse or schema failure                       -> SHAPE_FAILED
well-shaped target_id not in the observed set      -> SEMANTIC_INVALID
in observed set, current incarnation gone, age > 0 -> STALE_CONFLICT
in observed set, gone, age == 0                    -> CONTENTION_LOST
same id regenerated (generation changed)           -> ACCEPTED + STALE_REVALIDATED
still current and available                        -> ACCEPTED
```

---

# Amendment 6: four pre-run gates

**Written before the run loop exists.**

## Note on agent count

This experiment is preregistered at **3 agents** (Amendment 1: 200 cycles x 3
agents = 600 actions per replicate), matching the three-model hot set, and the
world calibration ran at 3. A five-agent design would change queue pressure
materially and requires its own amendment and its own feasibility check. The
gates below are specified and run at **3**.

## Gate 1 — equalizer feasibility under real queue pressure

The 750 ms equalizer was justified against measured *solo* small-prompt
latencies of roughly 190-580 ms. **That is the wrong load regime.** The bridge
runs `max_active = 2`, and ASYNC-A agents observe together and can submit
together:

```
3 submitted
  -> 2 active
  -> 1 queued
```

A queued request may be perfectly healthy and still complete more than 750 ms
after its observation, purely because it waited for a slot. That would raise
`EQUALIZER_BREACH` and void arm 3 **while every subsystem behaves correctly** —
not because equalization failed, and not because a model was slow, but because
a scheduler queue exists.

### Protocol, bridge only

No world. No resource outcomes. No arm comparisons. Just the bridge under the
submission pattern ASYNC-A will actually create.

```
candidate delays      750, 1000, 1250, 1500, 2000 ms
bursts                60
pattern               all agents submit at the same observation instant
prompts               unique and tiny, ASYNC-A shaped
agents                3, one per hot-set model
max_active            2 (unchanged)

accept the FIRST delay with:
    0 healthy completion breaches
    0 bridge-health interventions
    0 transport failures
stop immediately, freeze it
```

Same first-pass discipline as the world calibration: **do not search for the
prettiest delay.** If 750 ms survives real queue pressure it is kept unchanged.

## Gate 2 — same world code is necessary but NOT sufficient

The calibration proved how dangerous phase order is: a single `world.advance()`
in the wrong place manufactured staleness that time could not have caused.

Sharing `AsyncWorld` therefore does not make calibration and ASYNC-A the same
dynamical system. The invariant must be:

> **same `AsyncWorld` + same world-step protocol**

Otherwise calibration measured one system and ASYNC-A runs another out of the
same class file.

The tick protocol is frozen as **shared code**, not duplicated call ordering,
and the calibration driver and the ASYNC-A runner both call it.

### The reproduction tooth

```
standalone calibration driver
        vs
ASYNC-A runner step engine + synthetic transport

same seed, same timing schedule, same synthetic choices
    => identical outcome journal hash
```

**If those differ, the main experiment does not start.**

## Gate 3 — scarcity must not manufacture hallucination

If an agent has **zero visible legal targets**, it is not asked to choose one.
No model call is made. A substrate event is recorded:

```
NO_OPPORTUNITY
```

Forcing a model to emit `{"target_id": ...}` when nothing is available and then
scoring the inevitable failure as `SEMANTIC_INVALID` would let world scarcity
mechanically generate a hallucination rate — and `SEMANTIC_INVALID` is a
control variable for exactly the opposite purpose. `NO_OPPORTUNITY` is neither a
decision nor a failure, and never enters any outcome denominator.

## Gate 4 — runtime faults void the replicate

ASYNC-A does not study runtime faults. During a measured replicate:

```
bridge health DEGRADED or CATASTROPHE
model recovery / reload
unexpected residency change
    => the replicate is VOID and re-run
```

A five-second model reload producing "asynchronous specialization" would be
comedy, not emergence. Bridge health remains closed infrastructure and is not
retuned to make a replicate survive; the replicate is discarded instead.

---

# Amendment 7: EQUALIZED_DELAY_TICKS 3 -> 4, per Gate 1

**Supersedes the 750 ms constant in Amendment 4.** Recorded before any ASYNC-A
run, from the Gate 1 feasibility check.

## Result

Gate 1 ran the bridge alone under the exact submission pattern ASYNC-A creates:
3 agents submitting simultaneously, `max_active = 2`, 60 bursts, unique tiny
ASYNC-A-shaped prompts. Observation-to-completion:

```
                          n   median    p95    max
lfm2.5                   60      255    292    312
danube2                  60      353    419    430
falcon                   60      656    837    852
ALL                     180      353    801    852
```

```
delay_ms   healthy completions exceeding it
   750     24    <- would have voided arm 3
  1000      0    <- PASS, taken, search stopped
```

Zero transport failures, zero bridge-health interventions.

## What this means

**750 ms was justified against the wrong load regime.** Solo small-prompt
latencies measured 190-580 ms, but with `max_active = 2` and three agents
submitting together, one request always waits for a slot. falcon's p95 rises
from roughly 580 ms solo to 837 ms under queue pressure — perfectly healthy, and
past the old deadline.

Arm 3 would have raised `EQUALIZER_BREACH` on **24 of 180 actions (13%)** and
voided repeatedly, not because equalization failed and not because a model was
slow, but because a scheduler queue exists. That failure would have appeared
only after collecting outcomes.

## The new constant

```
EQUALIZED_DELAY_TICKS = 4        (4 x 250 ms = 1000 ms)
```

Taken by the first-pass rule: 1000 ms is the first candidate with zero
breaches, the search stopped there, and no prettier value was sought.

The consequence noted in Amendment 4 is now larger and stays stated: equalizing
can only level upward, so arm 3's uniform 1000 ms delay exceeds arm 2's mean
natural delay by more than before. Q2 compares **between-agent differences
within each arm**, so this is not a confound for the question asked — but the
absolute staleness rate in arm 3 is expected to exceed arm 2's, and that
difference is not evidence of anything by itself.
