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
