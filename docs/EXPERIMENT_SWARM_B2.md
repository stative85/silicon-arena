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

**The 3x multiplier, not N, is the binding constraint.** Under the observed
between-seed sd of 0.74 and the current 3x decision rule, the **estimated
asymptotic floor is about 4.8 turns** — more matches per seed buy progressively
less. That is an empirical property of this null structure, not a mathematical
impossibility result, and it is stated here rather than discovered later. The multiplier is not being changed, because it would be
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

**This is an economic futility criterion, not a prediction about the treatment.**
6.0 is a noisy point estimate from a single 20-match arm. If the powered bar
came back at 6.2, a fresh treatment could still happen to produce 7 or 8 and
clear it — the outcome is not predetermined and no claim is made that it is.

The defensible statement is narrower:

> If the powered bar is >= 6.0 turns, abort the treatment because **the
> redesigned experiment has failed to achieve sensitivity below the best
> existing estimate of the effect that motivated the replication.**

That is a decision about instrument quality, made without pretending to know an
unseen result. Choosing the number after seeing the null would be deciding
whether to spend 24 more GPU-hours based on whether the answer looked reachable,
which is the same act as moving a bar.

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

  estimated asymptotic floor                   ~4.8 turns, under the observed
                                               between-seed variance and the
                                               current 3x decision rule
  cost to move the bar from 9.15 to 5.60       ~28 additional GPU-hours
  cost to move it from 5.60 to 5.21            ~28 more on top of that
```

**This experimental geometry has a bad empirical asymptote.** The `3x`
multiplier against a null containing between-seed variance that does not shrink
with matches-per-seed means more GPU eventually stops buying much information: doubling the matches per seed from
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

---

# Result: the null completed, the bar is 6.00, the gate fires

**400 of 400 null matches finished.** The run continued to completion after the
session driving it disconnected; nothing was resumed and nothing was restarted.
Read from the persisted checkpoint, not from stdout.

```
  10 derangement seeds x 40 matches            400 rows, 40 per seed
  12,000 allocations                           every code OK
  FALLBACK_WAKES 0    NO_BIDS 0                MALFORMED_BID 0
  NO_ELIGIBLE_BIDS 0  SHAM_UNDERANGEABLE 0     REQUEST_FAILED 0

  per-seed median longest silence
    [11.0, 10.0, 10.5, 11.0, 11.0, 10.0, 9.0, 10.0, 11.0, 12.0]

  pairwise |difference|   p90 2.00   max 3.00
  bar = max(3 x 2.00, 3.0)                     = 6.00 turns
```

Recomputed independently from the checkpoint rather than trusting the harness's
own summary line. Same numbers.

## The gate fires

The threshold was fixed before this number existed: `bar >= 6.0` means stop.
The bar is 6.00. **The treatment is not run.**

It lands exactly on the boundary, which is uncomfortable and changes nothing.
`>=` was written before the null returned, and the whole purpose of writing it
then was to remove the judgement call that a boundary invites. Arguing that 6.00
is close enough to below 6.0 is moving a bar with the answer in view, which is
rule 8 in the exact costume rule 8 was written about.

Recorded, per the pre-registration:

> **Locality is unresolved under this mechanism.** The powered instrument failed
> to achieve sensitivity below the best existing estimate of the effect that
> motivated the replication. No claim is made about what a treatment would have
> produced.

The architecture claim is untouched, as stated in advance that it would be. It
now rests on 12,000 further allocations in which the substrate saw only
`{agent_id, eligible, bid}`, no fairness machinery ran, and centralized
fallback authority never woke.

**No SWARM-B3.** The stopping rule was frozen for this outcome.

## Why the bar missed its projection, and it is not variance

The simulation predicted `p90 1.87 -> bar 5.60` at 40 matches per seed. The
realized spread was actually *better* than projected:

```
                              projected (n=5 data)   realized (n=40)
  mean within-seed variance          5.12                 9.45
  variance of medians                2.16                 0.69
  between-seed sd                    0.74                 0.57
```

Between-seed variance — the component that was supposed to never shrink — came
in **lower** than the estimate the power calculation was built on. The null
behaved better than its own forecast and the bar still came in worse.

The reason is that **the bar is quantized, and 5.60 was never a value it could
take.** `longest silence` is an integer count of turns. A median of an even
number of integers is a half-integer. Pairwise differences of half-integers lie
on a 0.5 lattice. So `bar = max(3 x p90, 3.0)` can only ever be:

```
  3.0    4.5    6.0    7.5    9.0
```

There is no 5.60. There is no 5.21. The entire compute-economics table in the
amendment above is a continuous curve drawn through a statistic that can only
land on rungs 1.5 turns apart, and the observed `p90 = 2.00` is one rung. The
adjacent rung is 4.50.

This is a defect in the power analysis, not in the null, and it was mine. The
simulation treated a discrete order statistic as continuous, which is why it
produced a projection between two attainable values and why "40 is the smallest
step that puts the bar below 6.0" was never true. At 40 matches per seed the
outcome was always going to be 4.50 or 6.00, and buying more matches moves a
quantity that can only jump by 1.5 turns at a time.

**Doctrine rule 9.**

> A power calculation must be performed on the distribution the decision
> statistic can actually take. Simulating a continuous approximation of a
> discrete statistic can predict a value the experiment is incapable of
> producing, and will then appear to justify a sample size that buys nothing.

That is the finding with the longest shelf life here, and it generalises past
swarm work to every threshold in this repo built on a median of small integers.

## The compute receipt, corrected

The transferable claim survives and gets sharper. The earlier statement was that
this geometry has a bad asymptote. The stronger and more accurate statement is:

> **This design cannot be tuned by spending money on it.** Its decision
> statistic is quantized at 1.5 turns. Doubling the null from 40 to 80 matches
> per seed — another ~28 GPU-hours — cannot produce any bar between 4.50 and
> 6.00, because no such bar exists. Compute buys a probability of landing on a
> lower rung, not a lower bar.

Total spent reaching this: ~28 GPU-hours of null on top of SWARM-B's ~8. The
~3,600 treatment generations are not spent, which is what the gate was for.

Any future swarm question needs a decision statistic chosen for its noise floor
*and its granularity*, before its treatment values are seen. That option is
still unspent.
