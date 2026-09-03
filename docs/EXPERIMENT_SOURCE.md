# Pre-registration: does the CONTENT of a recalled scar change the reply?

**Written and committed before the evaluator was written and before any
generation was run.** The feasibility and floor numbers quoted below come from
existing transcripts and involve no generation, so no outcome data exists at
the time of freezing.

## What MP1 settled, and what it did not

MP1 ([EXPERIMENT_METRIC](EXPERIMENT_METRIC.md)) asked whether `_is_callback`
measures memory engagement. It returned INCONCLUSIVE on that question at +7.6,
and settled a harsher one on the way:

```
  repaired metric, verbatim exclusion removed
    S0 none 78.5%    S1 sham 80.6%    S2 real 80.6%
    real - sham = +0.0      real - none = +2.1
```

A block of unrelated text from a different match does exactly what the recalled
memory does. So the open question is no longer "how big is the callback rate".
It is:

> **Does changing WHICH old canonical memory is injected change the reply in a
> way traceable to that memory's source?**

That is a question about causation and about source specificity. An absolute
conversion rate cannot answer it, and running MP1 longer cannot either.

## The shipping decision this makes

Gonzo recall is shipped and stays shipped through this experiment. What is on
the table is narrower and more honest:

**Has automatic injection of an old scar earned default runtime authority?**

If it loses, canonical storage, scars, provenance, decay, cooldown, the
distance policy and the ROBRUSTION guards all stay. They are infrastructure and
they are correct. What is withdrawn is the automatic act of putting an old scar
into every eligible prompt by default.

## Design: a crossover, not a comparison

Three replies at every eligible opportunity, identical in agent, model, visible
history, topic, generation settings, prompt position, memory formatting, memory
length band and source-age band. Only the injected block differs:

| branch | injected |
|---|---|
| **N** | nothing |
| **S** | the matched sham scar **B** |
| **R** | the real distance-selected scar **A** |

MP1 scored all three arms against the real scar alone. That is right for
measuring instrument bias and wrong for measuring source specificity. Here
**every reply is scored against BOTH sources**, giving six numbers per
opportunity:

```
             scored vs A (real)   scored vs B (sham)
  reply N        U(N,A)               U(N,B)
  reply S        U(S,A)               U(S,B)
  reply R        U(R,A)               U(R,B)
```

`U(R,B)` is a within-response control: the same reply, same length, same
verbosity, scored against a source it never saw. `U(N,A)` and `U(N,B)` are the
placebo floor rule 4 demands, measured in the same batch rather than assumed.

**The primary estimator is a difference of differences:**

```
  source_lift(R) = [ U(R,A) - U(R,B) ] - [ U(N,A) - U(N,B) ]
```

The first bracket asks whether the real arm prefers its own source. The second
subtracts whatever asymmetry exists between the two sources when no memory was
injected at all. Anything that makes scar A easier to hit than scar B —
vocabulary drift, topic overlap, excerpt length — appears in both brackets and
cancels.

The identical quantity is computed for the sham arm against **its** own source:

```
  source_lift(S) = [ U(S,B) - U(S,A) ] - [ U(N,B) - U(N,A) ]
```

S is therefore a second treatment arm, not only a control. Both arms inject an
old canonical excerpt; they differ only in whether it came from this
conversation. That doubles the evidence, gives the result an internal
replication, and separates two questions that MP1 could only ask as one: does
injected content get used at all, and does it matter which content.

## The uptake measure, frozen

For a scar X at an opportunity whose visible window is `recent`:

```
  D(X) = content_words(X.excerpt)
         - content_words(recent)        # absent from the visible context
         - content_words(other scar)    # absent from the competing source
```

`content_words` is `GonzoRecall._content` unchanged — lowercased, punctuation
stripped, longer than 3 characters, stoplist applied. The two sources are made
disjoint by construction, so a term can never be credited to both.

```
  U(reply, X) = 1 if |D(X) INTERSECT content_words(reply)| >= 2, else 0
```

**The threshold is 2, and it was chosen from a measured floor, not by taste.**
See below. A threshold of 3 is reported as a robustness check and cannot change
the verdict.

An opportunity where `D(A)` or `D(B)` is empty is **discarded before
generation**, so the filter can never be outcome-dependent. Measured discard
rate on 543 real opportunities: **0.7%**.

### Verbatim copying is reported, never used to disqualify

MP1's central suspicion was that the six-word verbatim exclusion disqualifies
genuine engagement. That defect is not inherited. Copying is handled by
**excluding the copied span, not the reply**:

* **primary** — `U` as defined above, quoted material included.
* **secondary** — `U_unquoted`, counting only distinctive terms that fall
  outside any 6-word run shared with the injected block.

Both are always reported. Two numbers, never one — that was MP1's
pre-registered repair and it carries forward here.

## The measured floor that set the threshold

Rule 4 asks how often a detection metric fires when the thing it detects is
absent. This was measured **offline, before freezing**, on 540 opportunities
using canonical arena turns — real replies, generated in ordinary matches with
no memory injected, then scored as if a scar had been injected:

```
  threshold      vs real source   vs sham source   asymmetry
  >= 1 terms         31.9%            25.0%          +6.9
  >= 2 terms          9.1%             7.4%          +1.7
  >= 3 terms          3.0%             1.7%          +1.3
```

**At the obvious threshold the measure carries a +6.9-point bias toward the
real source with nothing injected.** A reply that never saw scar A takes up
scar A almost a third of the time, and does so 6.9 points more often than it
takes up an unrelated scar, purely because A comes from the same conversation
and shares its vocabulary drift.

That is the same class of artifact that inverted the embedding result from
+30.4 to -10.9, and it is the same magnitude as MP1's inconclusive +7.6. A
naive `P(uptake | real) - P(uptake | sham)` at threshold 1 would have
manufactured most of a result out of nothing.

Threshold 2 cuts the floor to 9.1% and the bias to +1.7. The crossover then
cancels that residual empirically instead of assuming it is gone.

This floor is a prior, not a substitute for the live N branch: the offline
replies were produced with the full arena prompt and the harness uses a reduced
one. N is still generated and still measured.

## Matching the sham

The sham is drawn round-robin **by index** from scars in other transcripts,
never chosen for being dissimilar, then constrained to:

* excerpt length within **40 characters** of the real scar;
* attributed speaker present in the **current match's cast**;
* excerpt not appearing anywhere in the current transcript.

The speaker constraint is new and it closes a leak MP1 had. Every transcript in
this corpus shares the same five-agent roster, measured at **70 of 70** usable
transcripts, so a sham can always name a speaker the agent recognises. Without
it, R and S differ not only in relevance but in whether the cited speaker
exists at all, which is a cue the model can read off the prompt without reading
the memory. Availability of a fully matched sham was measured at **100%** of
opportunities, so this costs no sample.

## Generation settings, and why there are no seeds

Fixed seeds would make the counterfactual cleaner. **They are not available.**
Measured on this LM Studio build with `h2o-danube3-4b-chat`: two identical
requests at `temperature 0.8` carrying the same `seed` returned different text.
`temperature 0` is fully deterministic, byte for byte.

So the design splits:

* **Primary run — temperature 0.8, the shipped setting.** External validity:
  this is what the runtime actually does. Sampling variance is absorbed by N
  and by the within-response controls the crossover provides.
* **Deterministic replication — temperature 0, on a pre-specified subset: the
  first 80 opportunities by index.** There the branches differ by the memory
  block and by nothing else at all, including decoding. It is reported and it
  cannot change the verdict.

Everything else matches MP1 exactly so the two remain comparable: model
`h2o-danube3-4b-chat`, `max_tokens` 110, the same prompt construction, the same
three-turn `recent` window.

---

# MP2-A — is the measure capable of detecting uptake at all?

A null from a blind instrument is worthless, and this project has already
shipped one metric that measured nothing. Before MP2-B runs, the measure must
be shown capable of firing when uptake is genuinely present. Rule 1 — a test
must be shown to fail — applied to a metric instead of a guard.

**Branch P**: the real scar injected, plus an explicit instruction to build on
it. This is a *calibration ceiling*, not a candidate intervention. It does not
reopen prompt instructions as a shipping lever; the ledger's answer on that
stands and this arm will never ship.

**Gate, on 60 opportunities:**

```
  U(P,A) - U(N,A) >= +25 points   ->  the measure can see uptake. Proceed.
  < +25 points                    ->  the measure is BLIND. STOP.
                                      MP2-B is not run. Redesign the measure.
```

Running MP2-B without this gate would repeat the exact error being corrected:
interpreting a null produced by an instrument nobody validated.

# MP2-B — does real recall create source-specific influence?

**N = 240 opportunities**, fixed now.

Chosen by simulating the difference-in-differences estimator against the
measured floor above. With no true effect, the probability of the estimate
reaching +10 was ~0% at every N tested; N=240 discriminates as well as N=400,
and past 240 the fixed practical bar rather than the sample is the binding
constraint. The simulation is approximate and its one load-bearing conclusion
is that **the +10 bar cannot be cleared by noise.**

## Frozen decision

Evaluated on `source_lift(R)`, with `source_lift(S)` as the replication.

**1. CONTENT CAUSAL, SELECTION MATTERS** —
`source_lift(R) >= +10` AND `source_lift(R) - source_lift(S) >= +10`.
Recall is justified as designed. The selected memory does something a matched
sham does not.

**2. CONTENT CAUSAL, SELECTION IRRELEVANT** —
both arms `>= +10` and within 10 points of each other.
Injected content *is* used source-specifically — the model reads the block and
takes specific material from it — but the distance policy's pick is not
special. Injection keeps its authority; **the selection policy loses its
justification** and reopens as a separate shipping decision.

**3. NO SOURCE-SPECIFIC CONTENT EFFECT** —
`source_lift(R) < +5`.
Injecting an old scar does not causally shape the reply. **Automatic injection
loses default runtime authority** and reopens as a shipping decision. Storage,
scars, provenance, decay, cooldown and the guards all stay.

**4. INCONCLUSIVE** — `source_lift(R)` between +5 and +10.
The bar does not move and the sample is not extended. Settling it needs another
pre-registration.

### Conditions attached to outcomes 1 and 2

A verdict of justified additionally requires all of:

* **unsupported attribution = 0**, on every arm, as in every prior recall
  experiment;
* **`U_unquoted` retains at least half the primary lift.** If the effect
  survives only when quoted spans are counted, it is copying rather than use,
  and copying is not what this feature exists to produce;
* **no fixation harm** — R-arm verbatim copying may not exceed S-arm copying by
  more than 15 points.

Any of these failing routes the result to INCONCLUSIVE regardless of the
primary number.

## Anti-Goodhart teeth

Three consecutive experiments told different stories early and late:

```
  resonance    +5.0 at 40    +7.4 at 81    -3.9 at 127
  embedding   +30.4 at 46                  +4.4 at 182
  metric       +2.1 at 48                  +7.6 at 144
```

Warning against early reads did not prevent one; MP1's own document contains an
interim "falsified" call it later had to retract. So the guard is mechanical
this time rather than editorial:

* **The harness refuses to print arm rates before N is reached.** Below the
  target it prints the row count and exits. There is no flag to override it.
  This is INVARIANT to DETECTION to TEETH to RECOVERY to PROOF applied to the
  experimenter, and it is covered by a self-test that fails if interim output
  is emitted.
* **Label-scramble gate.** Before the verdict is read, the same analysis runs
  on shuffled branch labels. It must return `|source_lift| < 5`. If a scramble
  produces a result, the estimator is broken and the run is void.
* The uptake definition, the threshold, the discard rule and the sham matching
  rules are frozen at this commit and are not edited during the run. If any
  needs changing, that is the result, applied afterwards.
* The deterministic replication and the threshold-3 robustness check are
  reported and cannot change the verdict.

## Not part of the decision

Judge scores. Throughput. Latency. Embeddings — that question is closed.
Whether the reply is any *good*. This measures traceability to a source and
nothing about quality.

---

# Result: MP2-A gate FIRED at 60 opportunities — the control arm was invalid

```
                    vs A (real)   vs B (sham)
  reply N (none)         1.7%          5.0%
  reply P (instructed)   8.3%          3.3%
  reply R (real scar)   11.7%          1.7%

  U(P,A) - U(N,A) = +6.7 points      gate was +25.0
```

**MEASURE IS BLIND, per the frozen rule. MP2-B is not run.**

The pre-registered consequence stands and is not being negotiated. What
follows is the diagnosis the rule demands before a redesign, not an appeal.

## The instructed arm never engaged the memory at all

```
                copies a 6-word run    mean distinctive hits vs A
  N none                     0.0%                    0.22
  P instructed               0.0%                    0.50
  R real scar                1.7%                    0.52
```

Told in plain words to "build on that prior moment explicitly", the model
reproduced a six-word run from it **zero times in 60 opportunities**, and its
distinctive-term uptake was indistinguishable from the arm that was told
nothing at all — 0.50 against 0.52. The instruction did nothing.

So the gate cannot mean what it was written to mean. It was meant to separate
"the measure cannot see uptake" from "there is no uptake to see". It instead
demonstrated a third thing: **the ceiling arm never produced the uptake it was
supposed to guarantee.** A ceiling that does not rise is not a ceiling.

## This was foreseeable, and the ledger says so

The pattern across nine rejections is stated in EXPERIMENT_LEDGER: everything
that tried to change what the models were ASKED to produce failed, and only
changes to what the arena DOES with output survived. C1 asked for 15-25 words
and got a median of 81 at 5% compliance.

The calibration ceiling was built out of the one material this project has
already proven does not work on these models. That is a design error, it was
avoidable by reading a document that was read, and the run cost is the answer.

## What the run does establish

Not a verdict — 60 opportunities, and three experiments in a row reversed
between an early read and their pre-registered target. But two things are worth
recording because they bear on the redesign:

* **The measure is not obviously blind.** Both memory arms roughly double the
  no-memory arm's mean uptake against the real source, 0.50 and 0.52 against
  0.22, while the sham-source column stays flat across every arm, 0.22 to 0.27.
  Something moves when a memory is present, and the floor behaves as designed.
* **The floor behaves as designed.** N scores 1.7% against the real source and
  5.0% against the sham. A raw real-versus-sham comparison would have read that
  asymmetry as a result; the crossover subtracts it.

**The MP2-B estimator is computable from these 60 rows and is deliberately not
computed here.** Reading it would be the fourth early read in four experiments,
and this document already contains a warning that failed to prevent the third.
The rows are on disk. They are not evidence until MP2-B runs to its target.

---

# Amendment: MP2-A2, a ceiling that does not require compliance

**Written and committed before MP2-A2 was run.** The MP2-B bars, targets,
uptake definition, threshold, discard rule and sham matching are untouched. The
only thing replaced is the invalid ceiling arm.

**Branch P2**: the model is asked to **restate the scar's excerpt in its own
words**, and that paraphrase is scored as the reply.

A paraphrase of the source is source-specific use by construction — it is
derived from that excerpt and from nothing else — and producing one is a
transformation task rather than a behavioural instruction. Every intervention
this project has seen fail asked the model to *behave* differently: be shorter,
argue harder, take a position, follow a phase. Rewriting supplied text is the
kind of thing a 4B model does do, and if it does not, that failure is visible
directly as an empty or unchanged output rather than being silently confounded
with the thing under test.

**Gate, unchanged at 60 opportunities:**

```
  U(P2,A) - U(N,A) >= +25 points  ->  the measure can see source-specific use.
                                      MP2-B proceeds under its frozen bars.
  < +25 points                    ->  the measure is BLIND for real. MP2-B is
                                      not run, and the uptake definition itself
                                      is what needs replacing.
```

**A guard on the ceiling itself, so this cannot fail silently twice.** The
paraphrase must actually be a paraphrase: it is discarded, and the opportunity
with it, if it reproduces a 6-word run from the excerpt (that is copying, not
paraphrase) or if it is shorter than half the excerpt's word count. The discard
rate is reported. **If more than 25% of paraphrases are discarded, the ceiling
is again not a ceiling and the gate is void rather than failed** — a distinction
MP2-A had no way to draw about itself.

## A caveat on the paraphrase ceiling, recorded before its result

Written before MP2-A2 returned, so it cannot be a reaction to the number.

A paraphrase deliberately replaces the source's words. The uptake measure counts
shared content terms, so a *good* paraphrase — one that restates the excerpt in
genuinely different vocabulary — will score low on a measure that is working
exactly as specified. This makes the ceiling **conservative and asymmetric**:

* **Clearing +25 is strong evidence.** The measure detects source-derived
  material even when the wording was deliberately changed.
* **Failing it is weaker evidence than it looks.** It would establish that the
  measure cannot see *semantic* reuse, which is a real and disqualifying
  limitation given that MP2-B is meant to ask about material "used in a
  semantically appropriate way" — but it would not show the measure fails at
  what it literally counts, which is lexical traceability.

The frozen consequence is unchanged either way: below +25, MP2-B does not run
and the uptake definition is what gets replaced. This note fixes in advance what
that failure would and would not mean, so the reading cannot drift afterwards.

An arena reply that genuinely draws on a memory has no incentive to avoid its
vocabulary, and would plausibly score higher than a restatement that is trying
to avoid it. That intuition is not evidence and does not soften the bar.

---

# Result: MP2-A2 ceiling CLEARED at 60 opportunities — the measure is not blind

```
                     vs A (real)   vs B (sham)
  reply N (none)          1.7%          1.7%
  reply P2 (paraphrase)  55.0%          1.7%
  reply R (real scar)    20.0%          1.7%

  U(P2,A) - U(N,A) = +53.3 points      gate was +25.0
  paraphrases rejected: 7 of 67 offered = 10.4%   (void above 25%)
```

**MEASURE CAN SEE SOURCE-SPECIFIC USE. MP2-B proceeds under its frozen bars.**

The ceiling rose, and it rose past twice its bar. When the reply genuinely
derives from the excerpt, the measure fires 55% of the time. When it derives
from nothing, 1.7%.

## The sham column is the part worth staring at

```
  vs B (sham):   N 1.7%   P2 1.7%   R 1.7%
```

Identical to the decimal across all three branches, including the branch whose
entire content is a restatement of source A. The measure does not merely detect
"this reply overlaps some old text" — it discriminates *which* old text, which
is the one thing MP1's metric could not do and the whole reason MP2 exists.

That is also the false-positive floor behaving exactly as rule 4 demands, and it
is far tighter than the offline estimate of 7.4% predicted. The offline floor
was measured against full arena replies; these are shorter, which plausibly
explains the gap.

## The caveat written before this ran held up, and cut the right way

The note above predicted the paraphrase ceiling would be conservative, because a
paraphrase replaces the source's words on purpose. It cleared +25 anyway, by a
factor of two. Under the pre-registered reading that makes this **strong**
evidence rather than weak: the measure detects source-derived material even when
the wording was deliberately changed to avoid it.

## What this does NOT establish

R sits at 20.0% against A. **That is not a result and it is not the MP2-B
estimator.** It is 60 opportunities on a gate run whose purpose was to validate
the instrument, the arms here are N/P2/R rather than N/S/R, and there is no sham
*branch* in this run at all — only a sham *source* to score against. Reading a
verdict off it would be the fourth early read in four experiments.

MP2-B runs to 240 with the S branch present, and its bars are untouched.

---

# Result: MP2-B is VOID at 240 — the scramble gate was mis-specified

The run completed its target. The label-scramble gate then voided it:

```
  worst |source lift| over 200 permutations: 11.3   (bound was 5.0)
  RUN IS VOID - a scramble produced a result; the estimator is broken
```

**The run is void and its numbers are not a verdict.** That consequence is
frozen and it is not being negotiated. What follows is the diagnosis.

## The gate could not have passed, on any dataset

The permutation null was measured after the fact, over 2000 shuffles of the
branch labels on the 240 recorded rows:

```
  permutation null of source_lift(R)
    mean       -0.05        <- unbiased, as designed
    sd          3.95
  |lift| under the null
    p50         2.9
    p90         6.3
    p95         7.9
    p99        10.0
    max of 2000 14.2
  expected max of 200 draws (p99.5)  11.2
  THE FROZEN BOUND WAS 5.0
```

The gate compared a **maximum over 200 draws** against a bound meant for a
typical value. The expected maximum is 11.2 and the run produced 11.3. It fired
on its own expected value. There is no dataset on which that gate passes.

**This is rule 2, broken by the guard written to enforce discipline.** "You
cannot set a useful threshold for a metric whose noise floor you have not
measured." The scramble bound of 5.0 was set without measuring the scramble
distribution's spread. The same document that quotes that rule at the reader
violated it two sections later.

## Why the self-test did not catch it

Both scramble checks used degenerate data:

* 40 identical rows, where every permutation returns exactly 0;
* a planted effect strong enough that any permutation moves it past 5.

Neither exercised a **realistic noisy null**, which is the only condition under
which the bound was ever going to be evaluated. The test proved the gate fires
on extremes and stays silent on constants. It never asked what the gate does on
data that looks like data.

## A second hypothesis, measured and rejected

The suspicion was that the sham source is structurally easier to detect: it
comes from another transcript, so few of its words are stripped as
already-visible, while the real scar shares vocabulary with its own conversation
and loses those terms to the subtraction. If so, `lift(R)` and `lift(S)` would
not be comparable, which matters because the decision tree compares them.

Measured on 425 real opportunities through the production code path:

```
  |D(real)|  mean 8.49  median 9
  |D(sham)|  mean 8.48  median 8
  sham set larger in 13.6% of opportunities
```

**No asymmetry.** The ±40-character excerpt matching already equalises the
sets. The hypothesis was wrong and no fix is warranted. Recorded because a
suspicion that was checked and dropped is worth as much as one that was checked
and confirmed.

So there is exactly one defect: the gate.

---

# Amendment: MP2-B2, a scramble gate that is a test rather than a bound

**Written and committed before MP2-B2 was run.** `TARGET_B` stays 240. The
uptake definition, threshold, discard rule, sham matching, decision tree and
every margin in it are untouched. Only the scramble gate changes, and the run
happens on data this analysis has never seen.

## The gate becomes a permutation test

The old gate asked "is the null small?", which confuses sample noise with a
broken estimator. Noise is not brokenness. Two questions replace it, and each
tests the thing it names:

**1. IS THE ESTIMATOR BIASED?** The permutation null's *mean* must be near zero.
A crossover that cancels correctly has no preferred direction when the labels
are meaningless.

```
  |mean(null)| >= 1.0 point   ->  RUN IS VOID, the estimator is biased
```

That is the check the old gate was reaching for. On the void run this value was
**-0.05**, so the estimator itself was never the problem.

**2. IS THE OBSERVED LIFT DISTINGUISHABLE FROM LABEL NOISE?** The observed
`|source_lift(R)|` must exceed the 95th percentile of its own permutation null,
over 2000 shuffles.

```
  |observed| <= p95(null)   ->  INCONCLUSIVE, regardless of the margin
```

This is self-calibrating: it needs no bound guessed in advance, it scales with
N and with the base rates actually observed, and it cannot be set wrong the way
5.0 was. A lift that clears +10 but sits inside its own label-noise band is not
a result, and under this rule it cannot become one.

Both are computed before the decision tree is consulted. Clearing them is
necessary, never sufficient — the frozen margins still decide.

## The re-run uses transcripts this analysis has not seen

The void run's rows have been read. Applying a rule written afterwards to data
already seen is the exact contamination this project exists to avoid, however
principled the correction. So MP2-B2 draws from a **fresh slice**: targets and
sham donors both shifted to transcripts not used in the void run. 217 are
available and 20 were consumed.

The void run's data stays on disk, unmodified, and is not reanalysed under the
new gate.

## What is honestly compromised, and stated in advance

The void run's numbers are in this document's history and in my context. A
second run's result will inevitably be read against them. That cannot be undone
by procedure, so it is recorded instead: **MP2-B2 is not a blind replication,
and if its numbers land close to the void run's, that agreement is weaker
evidence than it will look.** The margins do not move to accommodate that.
