# Pre-registration: does sparse resonant recall bend behaviour, or is it just more prompt?

**Written and committed before the arms were run.**

## The question

Not "does more context help". Whether **distant history** changes present
behaviour *because of the history itself*.

## Three arms, because two would confound

| id | behaviour |
|---|---|
| Q0 | no recall |
| QS | **sham**: the same amount and format of injected canonical text, chosen to be the LEAST resonant available |
| Q1 | real resonance-selected recall |

**The sham is matched to the real arm on everything except relevance:** same
number of injected memories, same formatting, same injection position, same
cooldown and minimum-distance rules, and the same *count* of eligible
candidates — it takes the least-resonant members of the very same pool the real
arm draws from. Otherwise a Q1 win could be explained by Q1 happening to
receive older, shorter or fewer memories.

Q1 differs from Q0 in two ways at once — it receives an older *relevant*
memory, and it receives extra prompt text at all. QS isolates the second, so a
Q1 win means old relevant history mattered rather than that another paragraph
changed the model's behaviour.

4 runs per arm, 60 speeches, interleaved. Everything else frozen.

## Callback success is deliberately hard to fake

Q1 literally injects an old excerpt, so a model parroting it back must **not**
count. A callback counts only when **all** hold:

1. the source turn is provenance-valid;
2. the response engages with the excerpt's content;
3. the response contains **novel language beyond the injected excerpt**;
4. it is not merely repeating speaker + quote.

Without clause 3 the arena could score 100% by becoming a photocopier.

## Primary

Provenance-valid, **non-verbatim** callback rate in Q1, against QS at the same
turn positions. Acceptance requires beating **QS** — not merely Q0.

## Conversion, not just count

Raw callback count can rise simply because Q1 recalls more often. The measure
that answers "is the memory useful when surfaced" is:

```
successful non-verbatim callbacks
---------------------------------
eligible recalls actually injected
```

Reported for both Q1 and QS. A high count with low conversion means the arena
is surfacing memories that do nothing.

## Secondary, reported

Source-turn distance, recall frequency, third-agent entry.

## Guards

| guard | bound |
|---|---|
| unsupported attribution | **0** |
| recall cooldown violations | **0** |
| recalls per prompt | never above 2 |
| same scar recalled per match | small fixed cap |
| topic fixation | share of turns revolving on one recalled scar, not above Q0 + 15 |
| near-duplicate rate | not above Q0 + 8.1 |
| opener uniqueness | not below Q0 − 0.15 |
| throughput | not below Q0 − 1.40 |
| truncation, failures | at or below 5% / 2% |

## Teeth, at the sink

```
INVARIANT   a recalled excerpt exists verbatim in the canonical turn it names
DETECTION   provenance re-checked AT INJECTION, not only at selection
TEETH       an unresolvable scar is OMITTED ENTIRELY -- never replaced by a
            nearby turn, a reconstructed quote, or a best guess
RECOVERY    the prompt goes out with fewer memories, or none
PROOF       gonzo_recall_selftest.gd, 25 checks; three sabotages each turn it red
```

## Two bugs this wiring already found

**Provenance refused everything, correctly, for a bug of mine.** `_note_scar`
runs after the turn counter increments, so every scar pointed one turn past its
own source. Nothing was ever recalled and nothing was ever fabricated — the
guard did exactly its job on an error I had introduced.

**Recall was duplicating the visible transcript.** Before a minimum-distance
bound, mean recall distance was 2.5 turns: the agent was being shown things it
could already see. `MIN_RECALL_DISTANCE` now requires a memory to be older than
the visible window. Measured after: 6 recalls in 40 turns, distance 10–18,
mean 12.5.

A third, older bug surfaced too: `extract_claim` returned empty whenever a
turn's first sentence ran past 180 characters, which after sentence-trimming is
most of them. That is why contention memory fired only 0.75 times per match —
starved by a claim extractor that almost never succeeded, not by an arena
short of disagreements.

## Not part of the decision

Judge scores.
