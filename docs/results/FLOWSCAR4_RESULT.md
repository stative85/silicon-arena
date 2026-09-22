# FLOWSCAR4 — NO ANCESTOR / CAUSAL CLAIM NOT EVALUATED

**Verdict:** three completed rounds produced zero shells, so no ancestor existed,
so the leverage gate and the rung-3 counterfactual were **never run**.

This is **not** `NO_EFFECT`. `NO_EFFECT` is a verdict the counterfactual returns
after removing an ancestor and finding no later difference. No ancestor was
available to remove. The distinction decides what this run may be cited as: it
is not evidence against persistent causation, because persistent causation was
never tested.

```
apparatus commit   8d51993f66c2
manifest sha256    08ed9e9c21dfb482
regime             FLOWSCAR4, MASS_CONTRACT_V2, ACTION_SCHEMA_V1 (unchanged)
residency          SOLO_JIT_RESIDENCY, peak ~2.5 GiB
```

## The denominator, in full

```
1.  rounds completed             3
2.  aborted attempts             0
3.  total shells                 0
4.  channel-node shells          0
5.  causally leveraged shells    0   (gate never ran: no ancestor)
6.  rung-3 witnesses             0   (counterfactual never ran: no ancestor)
```

| round | seed | starting state | ticks | outcome |
|---|---|---|---|---|
| FLOWSCAR4-r1 | 1938338670697508 | `6e0c1002b489ee80` | 140/140 | COMPLETED |
| FLOWSCAR4-r2 | 1351538822899565 | `3b171fa5aaa90892` | 140/140 | COMPLETED |
| FLOWSCAR4-r3 | 3625874628104545 | `c88df8c7826abc5e` | 140/140 | COMPLETED |

Every seed matches the sealed manifest. Zero ledger violations, zero residency
violations, cleanup executed.

## Why zero shells

A shell exists only when an agent reaches zero energy. Across 140 ticks each
agent takes 28 turns. `OBSERVE` costs 1 and `MOVE` costs 4, and **a refused
action costs nothing** — refusal is inert by design.

Every `MOVE` in all three rounds was refused. The early repeated policy made
shell creation practically unreachable within the observed ceiling: an agent
emitting `OBSERVE` and invalid `MOVE`s ends the round with most of its energy
intact.

```
round 1 (rounds 2 and 3 identical)
  accepted   OBSERVE 80
  refused    MOVE    60
  every other verb   0
```

Refused `MOVE` targets, by category: the agent's own current room, another
agent's **display name**, an **object id**, and `vault`. Samples:

```
t0   BRINE     MOVE  refused  target=spawn_brine      its own room
t3   OZONIOUS  MOVE  refused  target=spawn_ozonious   its own room
t4   VANTA     MOVE  refused  target=VANTA            its own display name
t2   KESTREL   OBSERVE  ok    target=geemtron         a misspelt agent name
```

## By species, not only aggregate

| species | accepted | refused | refused target category | energy remaining (of 100) |
|---|---|---|---|---|
| BRINE | OBSERVE 24 | MOVE 4 | own spawn room 2, object id 2 | ~76 |
| GEMMATRON | OBSERVE 28 | — | — | ~72 |
| KESTREL | OBSERVE 28 | — | — | ~72 |
| OZONIOUS | **none** | MOVE 28 | own/other spawn room 28 | 100 |
| VANTA | **none** | MOVE 28 | display name 11, spawn room 15, other 2 | 100 |

**OZONIOUS and VANTA executed zero accepted operations in 140 ticks.** They were
never refused by the schema — every output parsed — they were refused by the
world, because the target did not name a reachable location. Their energy is
untouched at 100.

This is the first FLOWSCAR4 result that is actually about the models, and it is
a divergence between species under an identical regime.

## What this is, and what it is not

**It is a free-choice action-grounding failure.** Given a real observation packet
and no instruction naming an operation, these models emit `OBSERVE` and
malformed `MOVE` targets.

**It is NOT yet established as an interface failure.** Prompt presentation and
model capability have not been separated. The observation exposes `exits`; these
models did not use them; whether that is because the packet makes adjacency hard
to extract, or because the models cannot extract it, is untested. Calling it an
interface defect now would be the same error as the `requires:` / `(fields:)`
echo that contaminated the free-form arm twice — an instrument property reported
as a subject property.

**The qualification runs are not contradicted.** Step 1B qualified verb access
*under instruction naming the operation*, and its own document says so: "Every
cell names the operation to emit. Nothing here says whether a species would ever
choose to." This run is the first free choice, and the gap between the two is
now measured rather than assumed.

## Seeds did nothing, and that is expected

All three rounds produced identical operation distributions despite three
distinct seeds and three distinct starting states. At temperature 0 with a
deterministic scheduler this is expected, and it means these are effectively one
observation repeated three times rather than three independent samples. Recorded
so that no later reader treats n=3 rounds as n=3 samples of behaviour.

## What was NOT done

Spawning, topology, `START_ENERGY`, the prompt, the observation format and the
budget are unchanged. No fourth round was run; the stop condition forbids it.
Tuning any of those to produce a shell is the move this apparatus exists to
prevent.

FLOWSCAR4 is closed at this result. If a later diagnostic justifies an
observation-contract change, that contract is a new version requiring
requalification, and any future causal run is **FLOWSCAR5** — never a rescue of
this one.

## Next

A separate preregistered diagnostic, `AFFORDANCE_GROUNDING`, using captured real
FLOWSCAR4 observation packets, to separate prompt presentation from model
capability. It is a new experiment with its own seal, not a rerun of this one.
