# Pre-registration: can an event turn a disagreement into a running dispute?

**Written and committed before the arms were run.**

## The question

Periodic world-events escalated conflict and destroyed engagement: agents made
declarations at the room instead of arguing with each other
([EXPERIMENT_ESCALATION](EXPERIMENT_ESCALATION.md)). The diagnosis was content,
not timing — two of three events asked each agent to *declare* something.

This tests the opposite kind of event. Instead of changing the world, it points
one agent at another agent's **actual earlier claim** and makes the two trade
turns:

```
DIRECT CHALLENGE: Gemma 3 1B said in turn 14, "<verbatim claim>" —
Stablelm 2 Zephyr #2, take that exact claim apart. Gemma 3 1B answers next.
```

## The trap this design has to avoid

The event *guarantees* addressing and challenge on the turn it fires. Measuring
those on that turn would be measuring the instruction, exactly as a mandatory
rebuttal would have gamed challenge rate.

**So the event turn and the forced reply are excluded from every measurement.**
The question is what happens in the ordinary turns *after* the pair have had
their exchange: does the dispute continue on its own, or does it stop the
moment the instruction stops?

## Conditions

| id | behaviour |
|---|---|
| E0 | current AUTO (baseline, re-run in the same batch) |
| E2 | AUTO + a targeted-engagement event every 15 turns |

Everything else frozen. 4 runs per arm, 60 speeches, interleaved.

## Primary measure

For the **2nd, 3rd and 4th turns after each event** (skipping the challenger's
forced turn and the target's forced reply), compared against the same positions
in E0:

* cross-agent addressing rate
* challenge rate
* term uptake from the challenged claim
* whether a third agent joins the dispute

**Acceptance:** addressing in the post-event window must exceed E0's rate at
the same turn positions by at least **16 points** (2 SE at 4 runs, from the
32.8-point single-run envelope), with challenge rate not falling below E0 by
more than 10.

## Guards

| guard | bound |
|---|---|
| every fired event cites a resolvable claim | 100% |
| fabricated citations | **0** |
| same challenger twice in a row | not more than once per run |
| opener uniqueness | not below E0 − 0.15 |
| near-duplicate rate | not more than E0 + 8.1 |
| truncation | at or below 5% |
| failure rate | not above 2% |

## Provenance is a correctness property, not a metric

If the arena quotes a claim an agent did not make, it has fabricated evidence
and attributed it — and every later statement about what the agents argued is
worthless, with no way for a viewer to tell.

```
INVARIANT   a cited claim exists verbatim in the canonical transcript
DETECTION   the citation carries a turn number, re-checked against history
TEETH       an unresolvable citation refuses the event outright
RECOVERY    try the next eligible claim; if none resolve, skip the event
PROOF       targeting_selftest.gd — 10 checks, and making citation_holds()
            trust its caller turns 4 of them red
```

Refusals are logged as `target_refused` records, so a run that fired fewer
events than expected explains itself rather than looking like a bug.

## Not part of the decision

Judge scores.
