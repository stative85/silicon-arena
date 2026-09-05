# Pre-registration: SWARM-F, fault tolerance under a blind resolver

**Written before any F match has been run**, and before any perturbation code
exists. The mechanism is carried over unchanged from
[EXPERIMENT_SWARM](EXPERIMENT_SWARM.md). Nothing about the bid policy, the
resolver, or the decoding regime moves.

## The question

> Can the blind local-bid swarm keep allocating when agents disappear, go
> silent, or return, without semantic rescue from the arena?

This is an **invariant** question, not an effect-size question. That distinction
is the reason it can be asked cheaply and the reason it escapes rule 9 — see
"The ruler" below.

## What is already known before running, and why that is a feature

The frozen bid policy hardcodes two constants for a roster of five:

```gdscript
const FAIR_SHARE := 0.2              # "even share across five"
const STARVATION_SATURATION := 8.0   # "two rotations of a five-agent roster"
const ABSTAIN_BELOW := 0.10
```

An agent sees only its own `airtime_share` and never learns how many agents
exist. Shrinking the roster raises every survivor's share above `FAIR_SHARE`, so
the airtime term clamps to zero for all of them and the bid reduces to
starvation plus direct address. The previous speaker is excluded, so a roster of
`n` presents `n-1` eligible agents holding `turns_since_spoke` of `1..n-1`.

Evaluating the frozen arithmetic at even rotation, with no naming:

| roster | eligible | bids | submit (`>= 0.10`) |
|---:|---:|---|---:|
| 6 | 5 | .096 .158 .221 .283 .346 | 4 |
| **5** | 4 | .063 .125 .188 .250 | **3** |
| **4** | 3 | .063 .125 .188 | **2** |
| **3** | 2 | .063 .125 | **1** |
| **2** | 1 | .063 | **0** |

The n=5 row reproduces the figure published in
[EXPERIMENT_SWARM](EXPERIMENT_SWARM.md) when `ABSTAIN_BELOW` was frozen —
"0.10 leaves THREE agents competing" — which is how this derivation is checked
against something written before it.

So the predictions are:

* **n=4** — two competitors. Bidding still happens.
* **n=3** — one competitor. The swarm degenerates to round-robin with extra
  steps, without any fairness machinery being switched on.
* **n=2** — nobody clears the floor. `NO_BIDS`, and the fallback authority
  wakes. The only rescue is `named_recently`, worth `+0.30`, which lifts a lone
  eligible agent to `0.363`.

**Deriving this in advance is the point, not a spoiler.** Rule 9 says a
threshold must be set against values the statistic can actually produce; the
cheapest way to know those values is to compute them. The experiment now has
sharp, falsifiable, pre-registered predictions instead of a bar picked from
nothing, and the interesting measurement becomes *where the arithmetic stops
describing the real dynamics*.

**This is not licence to retune `FAIR_SHARE`.** It is now the object of study.
Changing it because the derivation is unflattering would be rule 8 with a
socket set.

## What this can and cannot establish

The resolver is untouched, so nothing here can weaken or strengthen the
architecture claim by design. What is under test is the **policy**: whether a
bid function calibrated for five agents survives having agents removed.

> If it does not, the finding is that this swarm's fault tolerance is bounded by
> constants in the local policy, not by the substrate — and the boundary is
> computable on paper.

## Frozen, and listed so none of it can quietly become an excuse

```
  same bid function              same abstention floor (0.10)
  same W_STARVATION = 0.5        same blind resolver
  same FAIR_SHARE = 0.2          same temperature 0 regime
  same STARVATION_SATURATION     same zero-fairness-assistance condition
  same ALLOWED_KEYS vocabulary   no sham arm (nothing to derange)
```

No traces, no stigmergy, no memory coupling, no minimum airtime, no dominance
correction, no starvation rescue, no roster-size awareness in the bid.

`MATCH_TURNS` moves from 30 to **40** for this experiment only, and the reason
is stated here rather than discovered later: `AIRTIME_WINDOW` is 20, so a
20-turn scoring region that contains no pre-perturbation history requires the
match to outlast the window. This is a change to a sampling parameter, not to
the mechanism.

## The ruler, designed before the arms

Every decision statistic is an **integer count** and every bar is **0**, the
minimum value the count can take. A bar of zero is always on the lattice, so
rule 9 cannot bite: there is no continuous approximation anywhere in the
decision procedure, and no median of small integers.

| # | statistic | support | bar |
|---|---|---|---:|
| 1 | allocation failures not explained by abstention or ineligibility | `Z>=0` | **0** |
| 2 | fallback wakes | `Z>=0` | **predicted per arm**, below |
| 3 | scored turns where observed bidder count != derived prediction | `Z>=0` | **0** |
| 4 | dropout events after which allocation does not resume on the next turn | `Z>=0` | **0** |
| 5 | rejoin events where the returning agent fails to win its first eligible turn | `Z>=0` | **0** |
| 6 | surviving agents silent for more than `S` consecutive turns | `Z>=0` | **0** |

`S` is frozen from **F0 only**, before any perturbed arm is read: the maximum
consecutive silence observed in the unperturbed roster, and nothing else. It is
a control-side quantity by construction.

**`S` is a conservative control ceiling, not a sensitive detector, and it is
described that way on purpose.** A maximum errs loose: one long tail in F0
buys every perturbed arm extra room. The alternative — F0's p90 silence —
would be a percentile over small integers, which is precisely the construction
rule 9 was written about, and manufacturing precision that way to tighten a
guard would be trading a known looseness for an unknown quantization. Statistic
6 therefore answers "did a survivor starve worse than anything the intact
roster ever produced", and nothing finer. Its zero bar sits on the integer
support either way.

Statistic 1 must keep three states apart, and the harness records them
separately or the run is void:

```
  voluntary abstention   every eligible agent bid below the floor   LEGITIMATE
  no eligible agents     the roster left nobody to ask              STRUCTURAL
  swarm-system failure   bids existed and no winner emerged         FAILURE
```

Only the third is a failure. Conflating them is the defect this ruler exists to
avoid, and it is the same distinction the resolver's failure codes already draw.

## Arms

Two families, because steady-state degradation and transient recovery are
different questions and must not be scored with the same statistic.

**Steady state** — roster fixed from turn 0, scored on statistics 1, 2, 3, 6
over match turns 20–39, where the airtime window contains no pre-perturbation
history:

| arm | roster | predicted bidders | predicted fallback wakes |
|---|---:|---:|---:|
| **F0** | 5 | 3 | 0 |
| **F1** | 4 | 2 | 0 |
| **F2** | 3 | 1 | 0 |
| **F5** | 2 | 0 | **>= 50% of turns** |

**Transient** — perturbation mid-match, scored on statistics 1, 2, 4, 5:

| arm | perturbation | predicted |
|---|---|---|
| **F3** | one agent alternately ineligible, 5 turns on / 5 off, from turn 10 | no failures, no fallback wakes |
| **F4** | one agent removed at turn 10, rejoins at turn 20 | rejoining agent wins its first eligible turn |

F4's prediction is not a guess. A returning agent has `turns_since_spoke = 10`,
which is past `STARVATION_SATURATION` and therefore saturates starvation at
`0.5`, against survivors cycling at `.063/.125/.188`. It should win immediately
and by a wide margin. If it does not, starvation pressure does not do what the
policy claims.

Rejoin is at turn 20 of 40, leaving **20 turns of post-rejoin observation** —
four full nominal five-agent rotations. Reintegration is the whole point of this
arm, and three rotations was not enough to watch it happen.

`>= 50%` for F5 is chosen because it is exactly `400/800` on that arm's
denominator — an attainable value, checked rather than assumed.

## The positive control, which costs no GPU

Rule 6: a control must be able to detect its own failure. F5 is *not* that
control, because at a roster of two the agents are likely to name each other
often and `named_recently` may rescue the arm — which would be a real finding
about which term is load-bearing at small `n`, but would leave the harness
unvalidated.

The control is instead an **offline breach**, run in the self-test with no
generation at all: hand the resolver an empty bid list and a list where every
entry is ineligible, and require `NO_BIDS` and `NO_ELIGIBLE_BIDS` respectively,
each incrementing the fallback counter the live harness reads. If the harness
cannot report a failure that is constructed to occur, a clean sheet from
F0–F4 means nothing.

This satisfies rule 1 in the same motion: the test is shown to fail before it is
trusted to pass.

## N, and what it buys

There is no effect size, so there is no power calculation. The right instrument
for a zero-bar invariant is the **rule of three**: zero violations in `N`
opportunities bounds the true rate at roughly `3/N` with 95% confidence.

```
  6 arms x 20 matches x 40 turns   = 4,800 generations   ~11 GPU-hours
  per-arm allocations                    800   ->  0 failures bounds < 0.4%
  statistic 3 scored turns per arm       400   ->  0 mismatches bounds < 0.8%
```

Roughly one third of SWARM-B2, and unlike B2 the bound tightens **continuously**
with more matches rather than jumping to the next rung, because it is a bound on
a count rather than a threshold on a median.

## Decision tree, fixed now

```
  offline control fails to go red        ->  VOID. No arm is interpretable.

  statistics 1, 4, 5, 6 all zero across F0-F4
  and statistic 3 zero across F0-F2      ->  FAULT TOLERANCE HOLDS to n=3,
                                             bounded, with the boundary derived
                                             and confirmed.

  statistic 3 non-zero                   ->  the derivation is wrong. Report
                                             observed against predicted bidder
                                             counts. Informative, not a failure
                                             of the swarm.

  statistic 1, 4, 5 or 6 non-zero        ->  that specific tolerance claim
                                             fails. Name which, do not average
                                             them into a verdict.

  F5 fallback rate < 50%                 ->  naming rescues a two-agent swarm.
                                             Record which term is load-bearing.
                                             Does not rescue or damage F0-F2.
```

**No SWARM-F2 to chase a near miss.** If an arm fails, the finding is the
boundary, and the next question is architectural rather than another sweep of
the same ladder.

## What this does not license

A clean result here says the swarm routes around holes down to a roster of
three. It does not say the policy is good, does not resolve locality (which
[EXPERIMENT_SWARM_B2](EXPERIMENT_SWARM_B2.md) left unresolved and closed), and
does not justify stigmergy. Those remain separate questions with their own
pre-registrations.

---

# Amendment: how a live-versus-dry gap must be read

**Written while the run is in flight, before the scored region of any arm has
been read.** No arm result exists at the time of writing.

The dry run has no text, so `named_recently` is false by construction and the
curve it produces is the **starvation-only baseline**. If live bidding sits
above that baseline, the reading is that direct address is a second
independently load-bearing local channel, shifting the phase boundary — not that
the derived curve was refuted. The curve is the prediction for one mechanism
acting alone, and it was confirmed exactly under that condition.

Fixed now so it cannot later become a rescue explanation for a prediction that
missed. It binds in both directions: if live bidding sits at or below the
baseline, naming is **not** load-bearing and no second mechanism may be claimed.

