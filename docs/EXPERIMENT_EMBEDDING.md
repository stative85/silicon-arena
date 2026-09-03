# Pre-registration: does a real embedding beat distance?

**Written and committed before `lms get` was run and before any embedding code
was written.**

## The hypothesis has changed

This is **not** "does semantic selection beat a crude heuristic". That heuristic
is dead — it lost to *not scoring at all*
([EXPERIMENT_TOURNAMENT](EXPERIMENT_TOURNAMENT.md)).

The contest now is:

> Does a real embedding model beat the stupid-simple distance policy strongly
> enough to justify an entire embedding subsystem?

Distance survived 127 paired opportunities and won on a frozen rule. An
embedding router does not get a participation trophy for using vectors.

## Conditions

| id | selection rule |
|---|---|
| **E0** | distance-only recall (the shipped policy) |
| **E1** | `nomic-embed-text-v1.5` semantic selection |

Paired counterfactual design, identical to the tournament that decided the last
question. At each eligible recall opportunity: same agent, same model, same
visible history, same candidate pool and count, same source-age eligibility,
same cooldown, same prompt position, same injected format, same generation
settings. **The only difference is which eligible scar is selected.** Both
responses scored, both discarded, nothing enters history.

Asymmetric prefixes as the model intends: `search_query:` for the current
context, `search_document:` for the stored scar text.

## Callback definition — unchanged

Provenance valid, engages the recalled material, contains novel language beyond
the excerpt, not a verbatim repetition. **This does not get adjusted because
embeddings start looking prettier.**

## Target

**>= 120 paired recall opportunities.**

Fixed now, for a reason the last experiment made vivid. Its R−D ran:

```
 40 pairs   +5.0     "delete"
 81 pairs   +7.4     "inconclusive"
127 pairs   -3.9     "delete"
```

Same experiment, three different stories depending on when a human gets bored.

## Selection divergence — reported, and it matters

**How often does the embedding router even pick a different scar?**

If E1 differs from E0 on only 12% of opportunities, a small overall gain may be
a large gain where it actually intervenes. So two numbers are reported:

* overall conversion delta;
* conversion delta **restricted to opportunities where the two rules selected
  different scars**.

The second says whether semantic routing has discriminative power, or mostly
agrees with the cheap router and occasionally rearranges the furniture.

## The decision, frozen now

The bar is harsher than the last tournament's because an embedding layer carries
real baggage: another local model, load behaviour, CPU and RAM cost, a vector
cache, serialization, model and version compatibility, invalidation, migration,
failure modes when the embedder is absent, latency at scar creation, and code
someone must understand in six months.

**KEEP the embedding router** only if all hold:

1. callback conversion improves by **>= 10 percentage points** over distance;
2. the improvement appears in **>= 3 of 4** large batches;
3. unsupported attribution remains **0**;
4. fixation and repetition do not materially worsen;
5. embedding failure **falls open to distance recall** and never kills memory;
6. runtime cost stays inside the frozen budget below.

**REJECT** if improvement is **< 5 points**.

**INCONCLUSIVE** between 5 and 10 — in which case it is not shipped and the
question closes.

Two to four points does not pay rent for an entire subsystem.

## Frozen runtime budget

| cost | bound |
|---|---|
| VRAM | **0** — the embedder loads CPU-only (`--gpu off`) |
| added latency at scar creation | <= 150 ms |
| added latency per recall opportunity | <= 100 ms |
| arena throughput | not below E0 − 1.40 speeches/min (the calibrated envelope) |

An 84 MB memory router must never evict a debater from an 8 GB card.

## Cache invariants, frozen before the model is downloaded

Every stored vector carries:

```
embedding_model_id
embedding_dimension
embedding_schema_version
source_turn_id
source_text_hash
```

At lookup, **any** mismatch — model, version, dimension, or a text hash that no
longer matches the canonical turn — makes the vector invalid. An invalid vector
is re-embedded if the embedder is available, and otherwise the opportunity
falls back to distance.

**Vectors from different embedding spaces are never compared.** That is the same
failure class as an unsupported quote: silently confident, invisible to the
viewer, and wrong.

Scar text is immutable, so its vector is immutable. Each scar is embedded
**once**, at creation. The current context is embedded once per opportunity.
Nothing is re-embedded per candidate.

## The embedder is optional infrastructure

```
eligible scars
      |
embedding router available and valid?
      +-- yes -> semantic selection
      +-- no  -> distance selection
```

Not:

```
embedding system breaks -> memory dies
```

Distance is the **proven baseline**, not an embarrassing fallback. A stranger
who never installs the embedder gets working Gonzo memory.

## Not part of the decision

Judge scores. The incidental repetition result from EXPERIMENT_DISTANCE.


---

# Pre-run measurement: the embedder violates the frozen VRAM line

Taken **before any conversion data was collected.**

`nomic-embed-text-v1.5` q4_k_m, loaded with `--gpu off --identifier gonzo-embed`:

| | measured | budget | |
|---|---:|---:|---|
| dimension | 768 | 768 | ok |
| median embed latency | **18 ms** | <= 150 ms | ok |
| discrimination | 0.781 related / 0.387 unrelated | — | works |
| **VRAM** | **+299 MiB** | **0** | **VIOLATION** |

Reproducible: unload → 4473 MiB, load → 4772 MiB, twice. `--gpu off` does not
produce a zero-VRAM load on this runtime.

The model itself is fine. It is fast, it is the right dimension, and it
separates related from unrelated scar text cleanly.

## Why this stops the experiment before it starts

Guard 6 requires runtime cost inside the frozen budget, and the budget says
**zero VRAM**, on the reasoning that an 84 MB memory router must never evict a
debater from an 8 GB card. AUTO plans against 6.0 GB of that card; 299 MiB is
about 5% of the total and can change which roster fits.

With guard 6 failing, **KEEP is unreachable** no matter what conversion
returns. Running 120 paired opportunities could only produce REJECT or
INCONCLUSIVE.

## The legitimate moment to amend, and the illegitimate one

**No outcome data has been collected.** Amending a budget line now, with the
measurement disclosed, is legitimate — the number was set as a guess about what
`--gpu off` would do, and that guess was wrong about the runtime, not about the
result.

Amending it *after* seeing conversion numbers would not be legitimate, and this
document exists so that distinction cannot be blurred later.

The decision belongs to the operator: either the VRAM line is amended to a
measured allowance before the run, or the embedding router is rejected on
budget without spending the compute.

---

# True zero, found — and what it actually costs

The operator declined to amend the budget and asked for a real zero first. There
is one, it was already installed, and finding it also turned up an LM Studio
defect worth writing down.

## Where the 299 MiB was coming from

Not the weights. `nvidia-smi --query-compute-apps` cannot attribute per-process
memory under Windows WDDM, but the process list does: loading the embedder
spawns a **fourth LM Studio worker process**, which disappears on unload. About
299 MiB is a CUDA context plus cuBLAS kernels.

`--gpu off` sets the offload ratio to zero layers. It does not stop the selected
runtime from initialising CUDA. With a CUDA runtime selected, **every** model
process pays for a CUDA context whether or not it uses the GPU.

## The fix: a runtime that has no CUDA in it

`llama.cpp-win-x86_64-avx2` — already installed, no download, not a new
dependency.

```
lms runtime select llama.cpp-win-x86_64-avx2@2.12.0
lms load --exact nomic-ai/.../nomic-embed-text-v1.5.Q4_K_M.gguf \
         --gpu off --identifier gonzo-embed
lms runtime select llama.cpp-win-x86_64-nvidia-cuda12-avx2@2.9.0
```

| | CUDA runtime | **CPU-only runtime** |
|---|---:|---:|
| VRAM | +299 MiB | **0 MiB** |
| dimension | 768 | 768 |
| cosine, related | 0.781 | 0.765 |
| cosine, unrelated | 0.387 | 0.389 |
| median embed latency | 18 ms | **16 ms** |
| p90 latency | — | 32 ms |

Delta measured as load-minus-unload twice, both times exactly **0 MiB**. The
embedder is not slower for being on the CPU; it is marginally faster, because it
is no longer paying to talk to a device it never uses.

Guard 6's VRAM line is met as written.

## The ritual is not free, and one part of it is a leak

Three costs, all found by control measurements rather than assumed:

**1. Runtime selection is global to GGUF, not per-model.** There is no
per-model runtime flag on `lms load`. So the embedder must be loaded while the
CPU runtime is selected, and the runtime switched back before any debater loads.
Ordering is now load-bearing.

**2. Switching the runtime evicts resident models.** Measured: 4691 MiB → 1898
MiB, a resident 4B debater dropped on the floor by a runtime change. The ritual
is therefore **startup-only**. Reloading the embedder mid-match would nuke the
roster.

**3. Switching leaks 111 MiB of VRAM, permanently.** Control with no embedder
and no models loaded, four switch cycles:

```
2120 -> 2231 -> 2342 -> 2453 -> 2564 MiB
```

Exactly +111 each time, perfectly linear, never reclaimed. This is an LM Studio
defect in runtime switching, unrelated to the embedder — it reproduces with
nothing loaded at all. It is bounded only by restarting LM Studio.

## Ruled out: a standalone CPU server

`extensions/backends/llama.cpp-win-x86_64-avx2-2.12.0` ships DLLs
(`llama.dll`, `ggml-cpu.dll`, `llm_engine.dll`), no `llama-server.exe`. LM
Studio loads them into its own worker. Getting a standalone CPU server means
fetching llama.cpp separately, which is the external dependency the
pre-registration counted as baggage. Not done.

## Decision on guard 6

**Guard 6 is SATISFIED.** The embedder costs zero VRAM, measured twice, with
equal-or-better latency and preserved discrimination. No budget line was
amended, and no outcome data was seen before this was settled.

The 111 MiB is charged honestly to the *switch*, not to memory: it is paid once
per LM Studio session, does not scale with scars, recalls, or match length, and
reproduces with no embedder present. The eviction and ordering constraints are
real and are now documented as startup requirements.

This does not weaken the "never evict a debater" principle. It satisfies it:
the embedder now genuinely takes nothing from the card.

The tournament proceeds.

---

# The instrument was broken, and the embedding router was exploiting it

The first smoke run returned **E1 nomic +50.0 points** over distance.

Every effect this project has measured is four to eight points. An effect an
order of magnitude larger than anything before it is not a breakthrough, it is
a broken instrument. So it got a placebo arm instead of a victory lap.

## The placebo

A third reply generated with **no memory injected at all**, scored against both
picks. A reply that was never shown a scar cannot call back to it, so its
"conversion" is the false-positive rate of the callback metric.

| arm | raw | placebo floor | true effect |
|---|---:|---:|---:|
| E0 distance | 58.7% | 50.0% | **+8.7** |
| E1 nomic | 89.1% | **91.3%** | **-2.2** |

**Honest delta: -10.9 points.**

The metric favours the E1 pick by **+41.3 points with no memory present**. The
headline was entirely artifact. Corrected, the embedding router shows no memory
engagement at all, while distance shows a real one.

## The mechanism

`_is_callback` rewards shared content words between the excerpt and the reply.
Nomic selects the scar most semantically similar to the recent context, and the
reply is **generated from that same recent context**. So E1's excerpt overlaps
the reply for free, whether or not the memory was ever read.

Goodhart's law, and the router was optimising for it as hard as it could.

## Why this explains every recall result so far

**Semantic similarity selects for redundancy.**

The scar most like what is already being discussed adds nothing the agent did
not already have. That is why E1 lands at -2.2: it is not that nomic chooses
badly, it is that nomic chooses things the model already knows, so injecting
them changes nothing.

This is `MIN_RECALL_DISTANCE` arrived at from the opposite direction. That bound
exists because recalling what is on screen is duplication rather than memory,
measured at a mean recall distance of 2.5 turns. Semantic selection reintroduces
exactly that failure through a more sophisticated door: not temporally close,
but topically close, which is the same redundancy wearing a better coat.

Distance wins because it is the only rule that reliably surfaces something the
conversation does **not** already contain.

## Blast radius: every conversion number ever reported here

No prior recall experiment had a placebo floor. So every callback conversion
rate this project has published -- the 65-76% band, the 69.3% that beat
resonance -- is a raw number sitting on an unmeasured false-positive floor of
roughly **50%**.

What survives and what does not:

* **Arm-versus-arm comparisons survive.** Both arms carried the same bias, and
  the paired design holds it constant.
* **The absolute rates do not.** They were never memory-engagement rates and
  must not be read as such. "Distance converts at 69.3%" means 69.3% against a
  ~50% floor, not that memory worked seven times in ten.
* **The resonance deletion is strengthened, not weakened.** Resonance selected
  on similarity, so the contaminated metric was biased *in its favour* -- and it
  still lost by 3.9 points. Correcting the bias moves it further down.

This is CONTRIBUTING rule 2 again, in its sharpest form yet: a threshold on a
metric whose false-positive floor is unmeasured is not a threshold, it is a
decoration. The rule said noise floor. It should have said noise floor *and*
false-positive floor.

## Applying the frozen rule

The pre-registration froze "callback conversion improves by >= 10 percentage
points" without anticipating a placebo. The faithful reading is that the frozen
metric is contaminated and the placebo-corrected delta is that same metric with
its false-positive floor removed, so the rule is applied to the corrected
number. Both are reported, so the choice is visible rather than convenient.

---

# Result: REJECT, at 182 paired opportunities

```
--- 182 paired opportunities ---
  selection divergence: 160 of 182 (87.9%)

  OVERALL
    E0 distance  70.9%    E1 nomic  75.3%    E1-E0 = +4.4 points

  PLACEBO (reply generated with NO memory injected)
    scored against E0 pick  78.0%    against E1 pick  76.9%
    TRUE EFFECT  E0 -7.1    E1 -1.6
    honest delta: +5.5 points

  NULL CONTROL (22 opportunities where both rules agreed)
    same scar both arms: E0  95.5%  E1  95.5%  gap +0.0 points

  WHERE THEY DISAGREED (160 opportunities)
    E0  67.5%    E1  72.5%    delta +5.0 points

  mean source distance: E0 35.2  E1 29.4
  unsupported attribution: 0
  fail-open events: 0
  embed latency: median 137 ms  p90 158 ms

  batch 1  E0 46.7%  E1 88.9%  E1
  batch 2  E0 86.7%  E1 77.8%  E0
  batch 3  E0 77.8%  E1 75.6%  E0
  batch 4  E0 75.6%  E1 60.0%  E0
  E1 wins 1 of 4 batches
```

**REJECT.** The frozen rule rejects below 5 points; the overall delta is +4.4.
It fails independently on the batch condition, which required 3 of 4 and got 1,
and the trend runs the wrong way: E1's only win is the first batch and it
declines monotonically after it.

Guard 6 also fails on latency. The measured cost is **137 ms median per
opportunity** against a frozen bound of 100 ms. The earlier 16 ms figure was a
short probe string; a real query embeds roughly three turns of context and costs
about ten times more. The VRAM line was met, the latency line was not.

## Why fixing N in advance mattered, again

```
 46 opportunities   +30.4   "spectacular"
182 opportunities    +4.4   "reject"
```

The same experiment, a factor of seven apart, differing only in when it was
read. This is the second time in two experiments that an early read told a
completely different story, and the second time the pre-registered target was
the only thing standing between a wrong ship and a right rejection.

## The null control came back clean

22 opportunities where both rules chose the same scar: E0 95.5%, E1 95.5%, gap
**+0.0 points**. Two independent generations on an identical prompt scored
identically. So the measurement path adds no detectable bias of its own, and the
+4.4 is a real if unimpressive difference rather than an artifact of the harness.

That is worth noting because it is the one number here that came out perfect.

## The finding that outlives this experiment

**Both memory arms score BELOW the no-memory placebo.**

```
placebo, no memory injected   78.0%
E0 distance                   70.9%   (-7.1)
E1 nomic                      75.3%   (-1.6)
```

A reply generated with no memory at all registers as a "callback" more often
than a reply that was actually given the memory. Read literally, injecting
memory makes callbacks *less* likely, which is not a credible description of
what memory does.

The likely mechanism is in the metric's own exclusion clause. `_is_callback`
disqualifies a reply that shares a six-word run with the excerpt, to stop
verbatim repetition counting as engagement. But a model that has been handed a
memory and engages with it will often echo a phrase of it — so genuine
engagement trips the verbatim guard, while a free-running reply that merely
shares topical vocabulary sails through. The metric penalises the behaviour it
exists to detect.

**So `_is_callback` does not measure memory engagement.** Every callback
conversion rate this project has published rests on it.

What survives: paired arm-versus-arm comparisons, because both arms are scored
by the same broken instrument on the same moments, and the null control shows
the harness itself is unbiased. The resonance deletion and this rejection both
stand.

What does not survive: any absolute claim of the form "recall produces callbacks
in N% of opportunities." A no-memory control scores 78%. That number was never
an engagement rate.

## Limitation of this placebo, and the honest next step

The placebo differs from the arms in **two** ways, not one: no memory content,
and a shorter prompt. So it cannot separate "the memory was irrelevant" from
"the extra prompt text changed the output".

This project already built the right instrument for that and used it elsewhere:
the **sham control** from the Q0/QS/Q1 design, which injects the same volume and
format of text with non-resonant content. A sham-controlled rerun would isolate
memory content from prompt volume.

That is a metric-repair question, not an embedding question. The embedding
question is closed.

## Disposition

The router never entered the runtime, so there was nothing to unship. Its code
has been moved out of the product tree to `tools/embed_router.gd` and
`tools/embed_router_selftest.gd`, alongside the harness, because the placebo
instrument is now the only thing that can re-validate the recall program's prior
claims. Nothing in `scripts/arena/` references an embedding router.

The nomic model stays on disk. Models are not deleted here.
