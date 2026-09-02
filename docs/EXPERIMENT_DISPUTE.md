# Pre-registration: does a disagreement continue after the scaffold is removed?

**Written and committed before the arms were run.**

## The question

Two interventions have now been rejected, and together they narrow the
mechanism:

* **E1**, world-events, escalated conflict and *destroyed* engagement:
  addressing slope −31.2. Agents declared at the room.
* **E2**, a single targeted challenge, fixed that harm (+5.6 addressing) but
  the effect was too small and too short. The pair exchanged their forced turns
  and the debate reverted within three.

E2 said the mechanism works *while it runs*. This tests whether it can outlive
itself: a **bounded three-turn episode** — A challenges B's actual claim, B
answers, A rebuts once — and then the scaffold is **removed from the prompt
entirely**, not merely stopped.

**The primary question is what happens in the ordinary turns afterwards.** The
forced exchange will obviously have high addressing and challenge rates; those
turns are excluded, as in E2.

## Conditions

| id | behaviour |
|---|---|
| D0 | current AUTO |
| D3 | AUTO + a bounded dispute episode every 15 turns |

4 runs per arm, 60 speeches, interleaved, everything else frozen.

## Primary measure

The **5 ordinary turns after each episode expires**, against the same turn
positions in D0:

* same-pair re-engagement without prompting
* challenge rate
* term uptake from the disputed claim
* whether a third agent joins

**Acceptance:** post-episode addressing must beat D0 at the same positions by
at least **16 points** (2 SE at 4 runs), with challenge not below D0 by more
than 10.

## Guards

| guard | bound |
|---|---|
| fabricated citations | **0** |
| episodes exceeding their exchange limit | **0** |
| events fired without follow-up room | **0** |
| **top-pair share of interactions** | not above D0 + 15 points |
| opener uniqueness | not below D0 − 0.15 |
| near-duplicate rate | not more than D0 + 8.1 |
| truncation | at or below 5% |
| failure rate | not above 2% |

**Top-pair share** is the new one and it exists because success has an obvious
failure mode: if one dispute causes two agents to consume most of the
subsequent interaction, the arena has not become more watchable, it has become
two agents having an argument while three others hold their coats.

## Why the event cannot fire near the end

An episode at turn 60 of a 60-turn match has nowhere to be observed. That is
not a cheap event, it is an unmeasurable one, and E2's guard failure was
exactly this mistake made in a threshold instead of in the arena:

```
current_turn + max_exchanges + followup_window <= match_end
```

Now enforced in `dispute_eligible()` and refused with a logged reason.

## Invariants, with teeth

```
INVARIANT   the cited claim exists verbatim in canonical history;
            challenger != target; both active; exchanges finite;
            one dispute at a time; enough turns left to observe it;
            an expired dispute contributes nothing to any prompt
DETECTION   dispute_eligible() and citation_holds()
TEETH       an ineligible dispute is refused and logged, never injected
RECOVERY    try the next eligible claim, else continue unchanged
PROOF       dispute_selftest.gd — 13 checks; removing the horizon check turns
            2 red, allowing self-challenge turns 1 red
```

## Not part of the decision

Judge scores.


---

# Result: scaffolded conflict does not outlive its scaffold. D3 rejected.

4 runs per arm, 60 speeches. Episodes at turns 15/30/45, expiring at 18/33/48.
Forced exchanges excluded; window is the 5 ordinary turns after expiry.

| post-episode window | D0 | D3 | delta |
|---|---:|---:|---:|
| cross-agent addressing | 38.3% | 41.7% | **+3.3** |
| challenge rate | 41.7% | 43.3% | +1.7 |

| guard | D0 | D3 | |
|---|---:|---:|---|
| top-pair share | 23.2% | 25.2% | OK |
| near-duplicate | 7.5% | 7.9% | OK |
| opener uniqueness | 0.79 | 0.72 | OK |
| truncation | 4.2% | 3.8% | OK |
| failure rate | 0.0% | 0.0% | OK |
| fabricated citations | — | **0** | OK |
| episodes over their exchange limit | — | **0** | OK |
| events fired without follow-up room | — | **0** | OK |

**Rejected.** +3.3 against a bar of +16.

## The three experiments together

| | intervention | post-effect on addressing |
|---|---|---:|
| E1 | world events every 15 turns | **−31.2** |
| E2 | one targeted challenge | +5.6 |
| D3 | three-turn bounded episode | **+3.3** |

Tripling the scaffold did not increase persistence. It slightly reduced it.

That is the finding worth keeping: **forced conflict does not become
self-sustaining in this arena.** The debate returns to its baseline shape as
soon as the instruction stops, and a longer instruction does not change the
shape of what follows it. E2 and D3 differ by 2.3 points, which is nothing.

The couples-therapy failure mode did not occur either — top-pair share moved
23.2% to 25.2%. Nothing was harmed. Nothing persisted.

## What this rules out

Prompt scaffolding as a route to durable rivalry. Three shapes have now been
tried — change the world, point one agent at another, force a bounded exchange
— and the post-scaffold effect is at best a third of the threshold.

## What remains, and what it would cost

Persistence would have to live in **agent state that keeps shaping prompts**
after the event: a standing grudge that decays over many turns rather than a
fact appended to a briefing. The scar lattice already stores per-agent memory
with provenance, so the machinery exists.

That is deliberately **not** built here. Three rejections establish that the
cheap version does not work, which is the precondition for considering the
expensive one — not a mandate for it. A grudge that survives is also the
mechanism most likely to produce five agents re-litigating one sentence
forever, and it should be entered into with a pre-registration and a decay
bound, not enthusiasm.

## Status

`--target-every` stays off by default. The dispute machinery and its 13
invariant checks stay in the verify gate: the arena can quote agents back at
each other, and it must never be able to invent the quote or start an episode
it cannot observe.
