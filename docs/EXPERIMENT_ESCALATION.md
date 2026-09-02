# Pre-registration: can the debate be made to escalate at all?

**Written and committed before the arms were run.**

## The question

Debates currently continue rather than develop. This tests one causal
mechanism, not an "entertainment engine": does changing the SITUATION every N
turns produce a measurable upward slope in adversarial structure?

The intervention changes what is true, never how to behave. Telling a model to
argue harder produces theatre; telling it the operator's refusal switch was
disconnected forces a response. Three events fire at turns 5, 10 and 15: a new
fact that contradicts a shared assumption, a forced incompatible choice, and a
consequence attached to a position already argued.

Each is appended to the shared briefing as a fact, not an order, and written to
the match log as its own `escalation` record so a replay can reconstruct
exactly what changed and when.

## Conditions

| id | behaviour |
|---|---|
| E0 | current AUTO |
| E1 | AUTO + a state event every 5 turns |

Everything else frozen: `max_tokens=110`, sentence trim on, headless pipeline
on, same roster, same topic, same personas, same scheduler.

**4 independent runs per arm, 60 speeches each, interleaved E0-E1-E1-E0-E0-E1-E1-E0.**

## Primary measure: within-run slope, not rate

Raw challenge rate has a ~54-point noise floor at 20-speech blocks, which
cannot answer anything. The primary is the **late-third minus early-third**
difference within each run.

Measured across six identical-config runs, the slope's own noise is:

| signal | slope mean | sd | 2sd |
|---|---:|---:|---:|
| challenge | +11.4 | 10.2 | 20.3 |
| addresses | +16.6 | 16.4 | 32.8 |
| commit | −12.8 | 24.3 | 48.6 |
| opener uniqueness | +0.03 | 0.08 | 0.15 |

Two things follow, and both are recorded before the run rather than discovered
after it:

1. **Debates already escalate.** Challenge slope averages +11.4 with no
   intervention. E1 must beat E0's slope, not merely have a positive one.
2. **`commit` is unusable** at a 48.6-point floor and is reported as
   description only. Within-run slope turned out to be only slightly quieter
   than raw rates, so the hoped-for cancellation of run-level variation is weak.

With 4 runs per arm the standard error of a mean slope falls to about sd/2, so
the detectable difference on challenge slope is roughly **10 points**.

## Acceptance

E1 ships only if **all** hold:

1. **challenge slope** exceeds E0's mean by at least **10 points**;
2. **addresses slope** not worse than E0's mean by more than 16 (half its 2sd);
3. no guard below fails.

## Guards

| guard | bound |
|---|---|
| turn failure rate | not above 2% |
| truncation | at or below 5% |
| near-duplicate rate | not more than E0 + 8.1 (calibrated envelope) |
| opener uniqueness | not below E0 − 0.15 (calibrated envelope) |
| formulaic openers | not more than E0 + 15 points |
| dead air (waits over 10s) | not above E0 |
| escalation records in the log | exactly 3 per E1 run, at turns 5/10/15 |

The formulaic-opener guard is the one aimed at this specific intervention. A
forced choice invites every agent to open "I choose to shut down because…", and
a wall of identical openings is exactly the failure the guards exist to catch.

## Not part of the decision

Judge entertainment scores. Reported, weighted at nothing, for the reasons in
the roster evaluation.

## If it works

The product feature is **not** periodic. It is state-triggered: fire an event
only when the arena has been structurally flat for N turns. Periodic is the
causal probe — it establishes whether the mechanism moves anything at all
before anything more complicated is built.
