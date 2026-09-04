# Pre-registration: SWARM-B2, power repair, no new cleverness

**Written before any B2 match has been run.** Everything about the mechanism is
carried over unchanged from [EXPERIMENT_SWARM_B](EXPERIMENT_SWARM_B.md). The
only thing that changes is how many matches are run.

## Why B2 exists

SWARM-B returned INCONCLUSIVE: a 6.0-turn difference against a 9.0-turn bar. The
mechanism was not ambiguous — the sham collapsed to a Gini of 0.360 with one
agent submitting the most bids of anyone and speaking 0.7% of the time — but the
pre-registered primary did not clear, and it does not become a result because
the anatomy is suggestive.

The bar was large because the null was under-powered, which was flagged in
advance as erring strict. B2 pays that debt.

## Frozen, unchanged, and listed so none of it can quietly become an excuse

```
  same bid function              same abstention floor (0.10)
  same W_STARVATION = 0.5        same blind resolver
  same deranged sham             same temperature 0 regime
  same 30-turn matches           same zero-fairness-assistance condition
  same primary statistic         same 3x multiplier
  same 10 derangement seeds      same decision tree
```

**The primary stays `longest actual silence`.** Gini separated far more
cleanly in SWARM-B — 0.067 against 0.360 — and it is *not* being promoted.
Changing the ruler after seeing which ruler likes the result is rule 8 with a
lab coat on. Choosing a statistic by its control-side noise before seeing
treatment would have been legitimate; that option was destroyed by the order the
work was done in, and this is recorded as a cost rather than argued away.

## The power calculation, done on control data only

Using the null's own variance and no treatment values.

```
  mean within-seed variance         5.12   (sd 2.26)
  observed variance of medians      2.16
  expected from sampling alone      1.61
  REAL between-seed variance        0.55   (sd 0.74)   <- never shrinks
  share of spread that is noise      74%
```

Simulating the bar against matches-per-seed:

```
  matches/seed   p90(null)     bar    null generations
        5          3.05       9.15           1,500     <- SWARM-B
       10          2.42       7.26           3,000
       20          2.08       6.23           6,000
       40          1.87       5.60          12,000     <- B2
       80          1.74       5.21          24,000
  asymptotic       1.61       4.83               inf
```

**20 matches per seed is not enough.** It yields a bar of 6.23 against the 6.0
effect already observed — fourteen hours of generation to reproduce the same
verdict. 40 is the smallest step that puts the bar (5.60) below it.

A bootstrap was tried first and is recorded as **invalid**: resampling within
each seed's five observed matches makes the median converge to those five
values' own median, so at large n it reproduces the original spread by
construction and cannot show improvement. The parametric simulation above uses
the decomposition instead.

**The 3x multiplier, not N, is the binding constraint.** With a real
between-seed sd of 0.74 the bar can never fall below about 4.8 turns at any
budget. That is a property of the design and it is stated here rather than
discovered later. The multiplier is not being changed, because it would be
changed with the effect size already known.

## N and cost

```
  null        10 seeds x 40 matches x 30 turns   = 12,000 generations
  treatment    3 arms  x 40 matches x 30 turns   =  3,600 generations
                                            total ~15,600, roughly 36 hours
```

The treatment arm moves from 20 to 40 matches for the same reason as the null:
its own median carries sampling noise, and powering one side only would leave
the comparison limited by the other.

## The stopping rule, fixed now

**If an adequately powered B2 is still inconclusive, this line of questioning
stops.**

No B3, B4 or B5 interrogating the same bid policy until it confesses. The result
is recorded as *locality unresolved under this mechanism*, the architecture
claim stands on its own evidence, and the next question is architectural rather
than another swing at the same one.

Written now because after a second inconclusive result the temptation to run
"just one more, slightly bigger" is exactly what a pre-registration is for.

## What is already earned and cannot be improved or erased by B2

> The substrate remained semantically blind and completed 1,800 allocations
> without centralized fallback.

That is a property of the code, not of the outcome. It was true when SWARM-B
returned inconclusive and it will be true whatever B2 returns.

## If B2 clears

Then, and only then, stigmergy becomes justified — one decaying
provenance-backed trace, tested for whether indirect local coupling adds
anything beyond direct local bidding. Not before. Building a trace layer on an
unresolved locality effect would mean never knowing which of the two was
carrying the result.

---

# Amendment: a pre-treatment abort gate, and the compute receipt

**Written while the null is still running and before any of it has been read.**
This adds a way to STOP. It adds no way to pass.

## The gate, with its threshold fixed before the number exists

When the null completes, the bar is computed and **compared against the effect
already observed in SWARM-B, 6.0 turns**, before any treatment match runs:

```
  bar <  6.0    the treatment can discriminate an effect the size of the one
                already measured. Pay the remaining ~3,600 generations once and
                close the book.

  bar >= 6.0    STOP. Do not run the treatment.
                Record: locality unresolved under this mechanism, instrument
                economics poor, architecture claim unaffected.
```

The threshold is 6.0 because that is the best available estimate of the effect,
and a bar at or above it means the experiment is futile in advance rather than
uncertain. Choosing this number after seeing the null would be choosing whether
to spend 24 more GPU-hours based on whether the answer looked reachable, which
is the same act as moving a bar.

The simulation expected 5.60 at 40 matches per seed. If the real null is worse
than simulated, that is exactly the case this gate exists for.

## The compute receipt, recorded as a result in its own right

Because "just increase N" reads as cheap advice six months from now, and it is
not:

```
  SWARM-B         1,500 null + 1,800 treatment generations      ~8 GPU-hours
                  bar 9.15, underpowered, INCONCLUSIVE at a 6.0 effect

  SWARM-B2       12,000 null + 3,600 treatment generations     ~36 GPU-hours
                  expected bar 5.60
                  one frozen bid policy, terminal replication

  detectability floor of this design           ~4.8 turns, at ANY budget
  cost to move the bar from 9.15 to 5.60       ~28 additional GPU-hours
  cost to move it from 5.60 to 5.21            ~28 more on top of that
```

**This experimental geometry has a bad asymptote.** The `3x` multiplier
multiplied against a null containing irreducible between-seed variance means
more GPU eventually stops buying information: doubling the matches per seed from
40 to 80 moves the bar by 0.39 turns for another day of generation.

That is the transferable finding, and it may outlast the B2 answer entirely:

> **This design is too expensive for iterative architectural work.** It is
> affordable once, as a terminal test of one frozen mechanism. It is not
> affordable as the standard ruler for a series of swarm questions, and any
> future swarm experiment should be designed against a statistic with a better
> noise floor rather than pointed at this one with more compute.

Choosing that better statistic must happen **before** its treatment values are
seen. That option was available for B2 and was destroyed by doing the work in
the wrong order; it is still available for whatever comes next, and this
paragraph exists so it is not squandered twice.
