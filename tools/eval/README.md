# Roster mode evaluation

A blinded A/B/C/D comparison of the four roster modes, built because the
question "should `--fit` be the default?" must not be answered by looking at a
transcript and forming an impression.

```
python tools/eval/run_conditions.py --turns 60      # run all four conditions
python tools/eval/metrics.py                        # mechanical metrics
python tools/eval/build_blind_set.py                # blinded excerpts
python tools/eval/test_blinding.py                  # prove the blinding blinds
python tools/eval/judge.py --model <id> --tag J1    # judge 1
python tools/eval/judge.py --model <id> --tag J2    # judge 2, different family
python tools/eval/compare.py                        # both judges + agreement
```

## Conditions

| id | mode | intent |
|---|---|---|
| A | default | five distinct models, one cold load per turn |
| B | `--balanced` | five agents over two models, grouped |
| C | `--fast` | five agents on one model |
| D | `--fit` | most distinct models that fit VRAM together |

Held constant: the topic (`live_match.gd`'s `TOPIC`), five agents, the turn cap,
the harness, the machine, the server. Varied: the roster mode only.

## Controls that turned out to be load-bearing

**Memory is cleared between conditions.** `user://scar_lattice` is deleted, so
no condition inherits another's memory.

**VRAM is emptied between conditions.** LM Studio keeps models resident on a
TTL, and a resident model reduces what is left for the next one. On an 8GB card
a resident 2.5GB model is enough to stop a 7B loading; the request comes back
as HTTP 400 and is indistinguishable from the model being broken.

**One run at a time.** `run_conditions.py` takes a lock. Two runs share one
LM Studio server and one roster file, so they silently attribute one run's
match to another run's roster.

## Two invalidated attempts, kept on the record

The first run produced 40%+ "failure rates" in three of four conditions and
rosters containing an encyclopedia continuation model and a phone-order agent.
None of that was real. It was three defects in the probe, since fixed:

1. A model that could not be **loaded** was recorded as a model that could not
   **speak**, so good models were dropped and whatever small thing loaded next
   got in.
2. The probe did not fold a rejected system role into the user turn the way the
   live client does, so it rejected models the arena runs fine.
3. Base/continuation checkpoints passed, because they emit non-empty text —
   they just continue the transcript instead of answering it.

The second attempt was invalidated by detached runs surviving a kill and
writing condition files underneath a fresh run. Hence the lock.

Both are recorded because "the harness was wrong twice" is the kind of thing
that quietly disappears from a methods section, and the numbers from those runs
should never be cited.

## What is measured

`metrics.py` computes, without any model in the loop: speeches per minute,
failure rate, near-duplicate rate, content novelty, references to other agents,
challenge/contradiction rate, cross-agent context retention, self-prefix
leakage, mean words, median and p90 latency, distinct models, and the resident
VRAM estimate.

`judge.py` scores blinded excerpts for coherence, relevance, distinctiveness,
argument quality, responsiveness and entertainment.

## On the judges

Two judges from different model families score the same blinded excerpts, and
`compare.py` reports them **separately**, with agreement as its own
measurement. Agreement is not treated as ground truth: two models agreeing can
mean the excerpts really differ, or that both share a bias, and nothing here
can distinguish those. A judge that cannot return usable JSON twice is recorded
as a refusal rather than defaulted to a score.

Excerpts are consecutive runs of turns, not isolated lines, because
responsiveness cannot be judged without the previous speaker. Speaker names
become `SPEAKER_A..E`, names inside the text are rewritten to match, and model
ids and bare parameter sizes are scrubbed — `test_blinding.py` asserts all of
that against the leak shapes seen in real logs.
