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
