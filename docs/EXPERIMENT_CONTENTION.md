# Pre-registration: does claim-scoped contention memory produce callbacks without obsession?

**Written and committed before the arms were run.** Final experiment in the
conflict-persistence family.

## Why this is worth one more expensive test

Three cheaper interventions have been rejected, and together they rule out a
family rather than three ideas:

| | intervention | post-effect on addressing |
|---|---|---:|
| E1 | world events | −31.2 |
| E2 | one targeted challenge | +5.6 |
| D3 | three-turn bounded episode | +3.3 |

**Prompt scaffolding does not create durable rivalry.** Tripling the scaffold
slightly reduced the after-effect. What has not been tried is *state that
survives the event*.

## What this is not

Not a grudge system. A contention is scoped to **one claim, one pair, one turn
id**, and it decays. It never instructs anyone to attack. It adds a single
descriptive line to the two involved agents' briefings:

> UNRESOLVED: you and Granite still disagree about "…" from turn 12. It has not
> been settled. **You are not required to raise it.**

An instruction to fight again would be scaffolding wearing a false moustache,
and scaffolding is the thing that failed three times.

## Conditions

| id | behaviour |
|---|---|
| C0 | current AUTO |
| C1 | AUTO + contention memory |

4 runs per arm, 60 speeches, interleaved, everything else frozen.

## Primary measure

**Organic re-engagement of the same pair, 4–10 turns after a contention opens**,
against the same turn positions in C0. Acceptance requires beating C0 by at
least **16 points**.

Secondary, reported: challenge persistence, callbacks to the disputed claim,
term uptake, third-agent entry.

## The anti-obsession rule, which can reject on its own

**If the dominant pair's share of interaction rises more than 15 points above
C0, or any single contention is still influencing prompts past its TTL, C1 is
rejected regardless of how large the persistence gain is.**

Persistence is trivial to manufacture — tell two agents to hate each other
forever and the metric goes up. The outcome worth having is occasional
callbacks and evolving rivalry *without monopolising the conversation*, so the
concentration guard outranks the upside.

| guard | bound |
|---|---|
| top-pair interaction share | not above C0 + 15 points |
| contention surviving past TTL | **0 — automatic failure** |
| contentions active at once | never above 2 |
| contentions per agent | never above 1 |
| reinforcements per contention | never above 3 |
| fabricated citations | 0 |
| near-duplicate rate | not above C0 + 8.1 |
| opener uniqueness | not below C0 − 0.15 |
| repeated-claim rate | not above C0 + 10 |
| truncation | at or below 5% |
| failure rate | not above 2% |

## Bounds, with teeth

```
INVARIANT   a contention names a claim that exists verbatim in canonical
            history, spoken by the agent it is attributed to; the pair are
            distinct and active; intensity decays; TTL is finite; at most one
            per agent and two in total; reinforcement is capped; an expired
            contention influences nothing and never returns
DETECTION   contention_admissible() and a decay sweep every turn
TEETH       inadmissible is refused; expired is DELETED from the array, not
            flagged, because lingering state can still be read by mistake
RECOVERY    the arena continues with no contention at all
PROOF       contention_selftest.gd — 15 checks. Removing the per-agent cap
            turns 1 red; removing expiry turns 3 red.
```

## If this fails

Stop digging. Three rejections plus this would establish that conflict
persistence is not reachable by any cheap mechanism in this arena, and the next
entertainment lever should be something else entirely rather than a fifth
variation on making agents argue.

## Not part of the decision

Judge scores.


---

# Result: the closest yet, still short. C1 rejected. Stop digging.

4 runs per arm, 60 speeches. Window is turns 4–10 after a contention opens,
evaluated at the same turn positions in C0.

| | C0 | C1 | delta |
|---|---:|---:|---:|
| same-pair organic re-engagement | 10.7% | **21.4%** | **+10.7** |

| guard | C0 | C1 | |
|---|---:|---:|---|
| top-pair interaction share | 28.2% | **26.7%** | OK |
| contentions outliving TTL | — | **0** | OK |
| near-duplicate | 9.2% | 9.2% | OK |
| opener uniqueness | 0.69 | 0.75 | OK |
| truncation | 0.8% | 2.1% | OK |
| failure rate | 0.0% | 0.0% | OK |
| fabricated citations | — | **0** | OK |

**Rejected:** +10.7 against a bar of +16.

## What actually happened

Re-engagement **doubled**. This is the largest effect any of the four conflict
interventions produced, and the first with no cost anywhere: the anti-obsession
guard went the *right* way — top-pair share fell from 28.2% to 26.7% — and
opener uniqueness improved. Nothing was traded for it.

It is still below the threshold that was frozen before the run, so it is
rejected. A bar is not moved after seeing the number that missed it.

## The limitation this test had, stated plainly

**Contentions opened 0.75 times per run.** Three across four runs. The organic
detector requires a challenge word *and* another agent named in the same turn,
and that combination is rare. The effect is therefore measured over very few
windows, and the +10.7 is a noisy estimate of something that barely happened.

**And the instrument was coarse.** The published rates reproduce exactly as
3/28 and 6/28, so the measurement has a resolution of about 3.6 points and the
"+10.7" is three additional events. On a 28-slot denominator the written bar of
+16 is not an attainable value at all — the rungs are +14.29 and +17.86, so the
effective bar was **+17.86**. The rejection is unaffected, because +10.7 is
below even the lower rung. The *effect size* should not be quoted as a precise
figure ([AUDIT_RULE9](AUDIT_RULE9.md), rule 9).

That is a fact about this test, not an argument for another round. The
pre-registration said that if this failed, the conclusion is to stop digging,
and a low trigger count is exactly the kind of post-hoc reason one reaches for
to justify one more attempt. Whether a looser trigger deserves a fifth
experiment is a decision for the operator, not a discovery in this data.

## Where the family stands

| | intervention | effect |
|---|---|---:|
| E1 | world events | addressing −31.2 |
| E2 | one targeted challenge | addressing +5.6 |
| D3 | three-turn bounded episode | addressing +3.3 |
| C1 | claim-scoped contention memory | re-engagement +10.7 |

Four interventions, four rejections. Scaffolding does not persist; state
persists better than scaffolding and still not enough. **Conflict persistence
is not cheaply reachable in this arena**, and per the pre-registration the next
entertainment lever should be something other than a fifth way of making agents
argue.

## Status

`--contention` stays off by default. The 15 bounds checks stay in the verify
gate: the arena can hold a memory of who disagreed with whom about what, and it
must never be able to invent the disagreement, keep it forever, or let one pair
own the room.
