# AFFORDANCE_GROUNDING — preregistration

**Status: PREREGISTERED, NOT RUN.** Written before any condition is executed.

A separate experiment with its own seal. It is **not** a rerun of FLOWSCAR4 and
cannot rescue it. FLOWSCAR4 is closed at
`NO ANCESTOR / CAUSAL CLAIM NOT EVALUATED` (`docs/results/FLOWSCAR4_RESULT.md`).

## The question

FLOWSCAR4 showed a **free-choice action-grounding failure**: every `MOVE` in
three rounds was refused, with targets naming the agent's own current room,
another agent's display name, or an object id. Two species executed zero
accepted operations in 140 ticks.

What that run cannot tell us is **why**. Prompt presentation and model
capability are not separated. This diagnostic separates them.

## Conditions

All five species, multiple frozen room fixtures, through the **unchanged**
`ACTION_SCHEMA_V1` and the **unchanged** `output_parser.gd`. One generation per
cell, temperature 0, no repair, no retry.

| # | instruction | isolates |
|---|---|---|
| A | the original free-choice prompt, verbatim | observed baseline |
| B | "MOVE to any adjacent room shown in the observation" | can it extract a valid exit? |
| C | "MOVE to `<exact valid exit>`" | can it populate a supplied target? |
| D | as B, but exits presented as an explicit legal-target list | is presentation the defect? |

## Interpretation, fixed in advance

```
C fails                          -> deeper action/schema grounding failure
C passes, B fails                -> cannot extract adjacency from this packet
B fails, D passes                -> observation-FORMAT defect
B and C pass, A still OBSERVE    -> genuine free-choice behaviour in a
   or invalid MOVE                  goal-less environment
all conditions fail              -> this small-model roster cannot navigate
                                    reliably
```

Written down now so the reading cannot be chosen after seeing which cells fail.

## A limitation in the inputs, stated up front

The brief calls for **captured real FLOWSCAR4 observation packets**. The
FLOWSCAR4 artifacts **do not contain them**. The runner persisted the oplog —
actor, verb, fields, tick, event id, accepted — and not the observation each
agent saw, nor its `observation_hash`.

Two consequences, neither hidden:

1. Packets for this diagnostic must be **reconstructed** by deterministic replay
   of the committed oplog against the committed starting state. `ObservationBuilder`
   is deterministic, so the reconstruction should be byte-identical to what the
   models saw.
2. **That reconstruction cannot be verified against a stored hash**, because no
   observation hash was persisted. Every packet used here is therefore labelled
   `RECONSTRUCTED`, and any finding that depends on exact packet bytes carries
   that caveat.

The runner is being fixed to persist `observation_hash` and the packet for
future runs. That fix lands **after** FLOWSCAR4 was committed, so it cannot
touch the closed result.

## What a result here may and may not do

**May:** identify whether the observation contract needs changing, and say which
of the four readings above the evidence supports.

**May not:** alter FLOWSCAR4's denominator, verdict, or artifacts. If this
diagnostic justifies an observation-contract change, that contract becomes a new
version requiring requalification of the sixteen-verb seam, and any subsequent
causal run is **FLOWSCAR5**.

## Reporting

Per species and per condition: accepted operations, refused targets, refused
target category, and parse outcome. Aggregates only alongside the per-species
table, never instead of it — FLOWSCAR4's aggregate hid that two species did
nothing at all while two others were clean.
