# Contributing to Silicon Arena

The easiest and most impactful way to contribute is **adding debate templates**. Each template creates a new arena scenario that every user gets to play with.

---

## Adding a Debate Template

Templates live in `scripts/main.gd` inside the `TemplateManager.TEMPLATES` array (starts around line 1108).

### Template Format

```gdscript
{
    "id": "your_template_id",
    "label": "Your Template Name",
    "description": "One-line pitch that makes someone want to try it.",
    "global_script": "Injected into every agent's system prompt. Sets the scene, tone, and constraints.",
    "rules": [
        "Keep replies under 40 words.",
        "Be direct and confrontational.",
        "Each turn must introduce a new argument."
    ],
    "topics": [
        "first debate topic",
        "second debate topic",
        "third debate topic",
        "fourth debate topic"
    ],
    "angles": [
        "The Prosecutor (aggressive, evidence-based)",
        "The Defender (empathetic, principle-based)",
        "The Wildcard (chaotic, unpredictable)"
    ]
}
```

### What Makes a Good Template

- **Conflict built in** — the angles should naturally clash. If everyone agrees, there's no debate.
- **Short rules** — models are 3-8B parameters. Complex instructions get ignored. "Under 40 words" and "be aggressive" work better than paragraph-long constraints.
- **Vivid global_script** — this is the voice of the arena. Make it set a mood, not just describe rules.
- **4 topics minimum** — the arena rotates through topics. More topics = more variety per session.
- **3-5 angles** — these get assigned to agents. Each angle should have a distinct rhetorical style.

### Testing Your Template

1. Add your template to the `TEMPLATES` array
2. Run the arena, press F6 (Builder), then click "Templates" to find yours
3. Watch at least 2 full rotations (all agents speak on all topics)
4. Check: Are agents staying in character? Are responses varied? Is there natural conflict?

---

## Adding a Character Sprite

Character sprites are managed by `SpriteFactory` (inner class in `main.gd`, around line 734).

### Using Layered Sprite Sheets

The arena uses 512x512 sprite sheets with 64px cells in an 8-column grid. Each character needs:
- Idle animation row
- Walk animation row
- Talk animation row
- One or more PNG layers that get composited

Add your character to the `SHEET_CHARS` dictionary in SpriteFactory with:
```gdscript
"your_char": {
    "layers": ["res://assets/characters/your_char/layer1.png", ...],
    "idle_row": 0, "walk_row": 1, "talk_row": 2, "frames": 4
}
```

Then map model families to your character in `MODEL_CHAR_MAP`:
```gdscript
"modelname": "your_char"
```

---

## Before you open a pull request

Run the whole deterministic suite. It needs no LM Studio and no GPU:

```
tools\verify.cmd
```

```
[PASS] project import
[PASS] project parses
[PASS] entrypoint parity
[PASS] model policy
[PASS] coherence
[PASS] cinematic bridge
[PASS] scar lattice
[PASS] system-role compat
[PASS] adversarial pass
[PASS] required files, configs and presets
VERIFY OK
```

CI runs the same thing on Linux for every push and pull request.

### Thirteen rules that are not negotiable

**1. A new test must be shown to fail.** Reintroduce the defect it guards,
watch it go red, restore, watch it go green. A suite that can only pass is not
evidence. This is not hypothetical: an early version of the parity self-test
matched `model_policy =`, which the *broken* code also satisfied, so it passed
the exact bug it existed to catch.

**2. You cannot set a useful threshold for a metric whose noise floor you have
not measured.** A guard tighter than its metric's run-to-run spread fires at
random, and it will eventually fire on a change that was fine. This is not
hypothetical either: the pipelining experiment was rejected on a
near-duplicate guard set at +3.0 points, and that metric's block-level standard
deviation turned out to be 7.9 — the guard was inside the noise before it was
ever used. Measure the spread first, in the same batch, then set the bound.
Corollary: run a baseline-against-itself calibration before trusting any A/B
protocol, because the protocol manufactures some apparent effect on its own.

**3. The conflict axis is closed.** No entertainment intervention may primarily
optimise challenge rate, cross-agent addressing, or rivalry. Four
pre-registered experiments explored that family — world events, a targeted
challenge, a bounded dispute episode, and claim-scoped contention memory — and
all four were rejected (`docs/EXPERIMENT_LEDGER.md`). Making the agents argue
harder is a solved question with a negative answer. Reopening it needs new
evidence, not a new variation.

**4. A detection metric needs a placebo floor, not just a noise floor.** Rule 2
asks how much the metric moves when nothing changes. This asks something
harsher: how often does it fire when the thing it detects is *absent*? Generate
the output with the treatment removed entirely, then score it as if the
treatment were there. Whatever it reports is a false positive, and the real
effect is your arm minus that floor.

This is not hypothetical. The embedding router measured +50.0 points of callback
conversion over distance recall. A placebo arm -- a reply generated with no
memory injected at all -- "called back" to the embedding router's chosen scar
**91.3%** of the time. The metric favoured that arm by 41 points with nothing to
detect, because the router selected scars that overlapped the current topic and
the callback test rewarded shared words. Corrected, the result inverted from
+30.4 to -10.9 (`docs/EXPERIMENT_EMBEDDING.md`).

An unmeasured false-positive floor does not add noise, it adds *bias*, and bias
points the same direction every time you look. Rule 2 protects you from
believing an accident. This rule protects you from believing an artifact you
built yourself.

**6. A positive control must be able to detect its own failure.** Rule 4 says
a detection metric needs a placebo floor: how often does it fire when the thing
is absent? This is the mirror. When you build a ceiling arm to prove your
measure can see the effect at all, ask how you would know if the ceiling never
rose. If the answer is "I would see a small number and conclude the measure is
blind", the control is not a control -- a null from it is indistinguishable
from a null from the treatment.

Not hypothetical. MP2-A's ceiling instructed the model to build explicitly on a
recalled memory. It reproduced a six-word run from that memory **zero times in
60 opportunities** and scored 0.50 mean uptake against the uninstructed arm's
0.52. The instruction did nothing, the gate reported the measure blind, and
nothing in the harness could tell the two explanations apart. The replacement
ceiling is checked against its own definition -- a paraphrase that copies, or
comes back stub-short, is discarded, and too many discards report VOID rather
than BLIND.

Corollary, and this project has now paid for it twice: **do not build a control
out of a mechanism the ledger already rejected.** Nine rejections say
instructions do not survive contact with these models. That finding applies to
your instruments, not only to your features.

**5. If you add a load-bearing runtime setting, add it to the parity test.**
Three separate production bugs had one cause — `live_match.gd` carried a
runtime fact and `main.gd` inherited a default. Put required settings in
`REQUIRED_ON_BOTH`, and put derived values in `INVARIANTS`, in
`scripts/arena/entrypoint_parity_selftest.gd`.

**7. Experiment corpora are quarantined by provenance.** Arena experiments are
scored on arena transcripts and nothing else. There is a 453 MB personal
archive on this machine -- 1,976 conversations, 137,841 messages, 45,429 of
them written by the author, spanning 900 days -- and it is a legitimate corpus
for Ghost personalization work. It is not admissible here.

The failure mode is quiet. Let that archive reach scar priors, topic weighting,
model selection or callback scoring, and the experiment stops measuring the
treatment and starts measuring "author prior + treatment", with no line in any
log saying so. Every margin in the ledger would silently become a different
quantity.

So: an experiment names its corpus, the corpus is arena-generated, and any
outside data enters only through a pre-registration that says which data, why,
and what it could confound. Personalization research lives in its own tree with
its own conclusions and does not lend evidence across the line.

**8. A control is not validated because it appears conservative.** Its own
failure modes must be measured. Instruments that simplify, strengthen, or clean
up the result deserve adversarial validation first.

**9. A power calculation must be run on the distribution the decision statistic
can actually take.** Simulating a continuous approximation of a discrete
statistic can predict a value the experiment is incapable of producing, and
will then appear to justify a sample size that buys nothing.

Not hypothetical. SWARM-B2's power analysis projected a bar of 5.60 turns at 40
matches per seed and that number was used to choose the sample size and to set
an abort gate at 6.0. But the primary is `longest silence`, an integer count of
turns; a median over an even number of integers is a half-integer; pairwise
differences lie on a 0.5 lattice; so `bar = max(3 x p90, 3.0)` can only ever be
3.0, 4.5, 6.0, 7.5 or 9.0. **5.60 was not a value the experiment could return.**
The realized between-seed variance came in *better* than the forecast and the
bar still landed on 6.00, because the outcome was always going to be 4.50 or
6.00 (`docs/EXPERIMENT_SWARM_B2.md`).

Check granularity as well as spread. A statistic whose bar moves in 1.5-turn
steps cannot be tuned by adding compute, and a projection that lands between
two rungs is telling you the model is wrong, not that the rung is reachable.

Corollary: **for discrete or quantized statistics, simulate the complete
decision procedure rather than projecting a continuous approximation through
the threshold.** Run the whole pipeline — draws, medians, pairwise differences,
percentile, multiplier, comparison — and look at which bars actually come out.
If a value cannot appear in that set, no sample size will produce it.

This bites anywhere the decision rests on small-integer counts, medians of
them, ordinal scores, rounded percentages, or numbers of violations. Floating
point will happily report a threshold that reality is forbidden to produce.

**11. An interface is validated against what the PRODUCER can emit, not against
hand-constructed witnesses.** An action is reachable only if the thing that will
actually produce it can express it through the frozen interface, and the
complete path can execute it. Reachability is end-to-end, never component-local.

Not hypothetical, and it cost 3,600 generations across three void runs of PIT A.
Run 1: the model-facing schema had no `type` field while the validator required
one, so 1,167 of 1,500 cycles died at the contract boundary and the control arm
had a strictly larger action space than every treatment arm. Run 2: the schema
was flat and the validator enforced cross-field coupling a flat schema cannot
state, so five species failed five different ways, 300 times each. Run 3:
canonical text sorted keys one level deep and stringified nested values, so a
journal round-trip reordered them and the same world hashed two ways.

Every one was found by the models within minutes of being allowed to speak, and
every audit had passed beforehand -- because every audit built its witnesses
with the harness's own constructors. Seed the tests with what the producers
actually emitted (`scripts/arena/fixtures/producer_specimens.json`), then fuzz.

**12. Canonical identity must be representation-invariant, and distinct
observations must stay distinct at the bytes.** For any state that gets
serialised: insertion order, JSON round-trip, journal round-trip, and
live-versus-replay must all produce identical identity. `str(Dictionary)` may
never appear inside identity computation. And the projection to whatever the
producer actually reads must not collapse two distinct states -- through
truncation, delimiter collision or interpolation. If truncation is policy, it is
deterministic, declared, and carries the full content's hash so two observations
sharing a prefix still differ.

Corollary that follows from both: structure must be unforgeable from inside a
value. Ids and types that originate in producer output are escaped before they
reach any text a producer later reads, or a model can emit a target containing a
newline and invent a line the substrate never wrote.

**13. A probe cannot infer substrate behaviour from behaviour the probe itself
commanded.** Observed behaviour is not evidence of a substrate constraint when
the harness directly imposed the same behaviour.

Sharper form: **a runtime property must be qualified by the loading and
execution regime under which it was observed.**

Not hypothetical, and the first attempt at recording it got its own example
wrong. The METABOLISM probe recorded "the runtime does not co-reside, it evicts"
as a hardware finding. Under JIT loading — an API request with
`justInTimeModelLoading` on — that is exactly what happens: a new request evicts
the previously JIT-loaded model. Under explicit `lms load`, **five models sit
resident simultaneously at 8192 context, 7,675 of 8,151 MiB, all generating
without a swap**. Both observations are real; the error was generalising a
path-specific one into a substrate-wide constraint.

The first correction then blamed `_unload_all()` in a file that does not contain
it, which is the same mistake twice — asserting a cause without verifying it
(`docs/EXPERIMENT_METABOLISM.md`, correction and correction-to-the-correction,
2026-09-06).

This is the most dangerous shape of instrument error in this repository, because
unlike the others it produced a **false positive** rather than a blocked run.
Nothing failed. Nothing complained. The finding simply arrived, plausible and
wrong. Before recording any observation as a property of the world, ask which
part of it your own harness caused.

**10. A threshold derived under a simplifying assumption may only judge data
generated under that same assumption.** If the assumption changes the
statistic's distribution, the threshold is invalid outside that regime.

Rule 9 is about a threshold that sits off its statistic's attainable support.
This is a different defect: the threshold came from the **wrong generating
distribution** entirely, and it can be perfectly attainable and still
unpassable.

Not hypothetical. SWARM-F derived a predicted bidder count from the frozen bid
policy at even rotation **with no direct address**, confirmed it exactly in a
dry run that produces no text, and then set a bar of *zero mismatches* against
it -- and pointed that bar at live dialogue, where agents name each other and
`named_recently` adds 0.30 to a bid. Direct address contributed a stable +0.94
extra bidder, so the guard reported 376 mismatches out of 400 at full roster. No
correct live system could have passed it (`docs/EXPERIMENT_SWARM_F.md`).

The tell is that the derivation and the data disagree about what generated
them. Ask, before freezing: *what did I hold fixed to get this number, and is it
still fixed when the treatment runs?* If not, the derived value is a baseline to
measure against, not a bar to fail against.

Seven instruments failed on this project in a single day and every one of them
failed toward a *cleaner* answer, never a messier one: a ceiling arm that could
not rise, a scramble bound that could not pass, a decision bar that collapsed to
zero, a lexicographic tiebreak that quietly favoured one model family, a
viability bar whose failure event was structurally unreachable, a cold-start
artifact that rewrote whole trajectories from one token, and a determinism claim
that held at two calls and broke at thirty.

The rule does not name a cause, because the causes differed — a bad assumption,
an unmeasured null, a plausible-looking neutral choice that was not neutral, an
under-evidenced generalisation. What they share is a direction. An instrument
that makes the answer tidier is the one to attack first, whatever produced it.

Never weaken these without evidence:

- the 7B ceiling is enforced on the request path
- no catalog means every request is refused (fail closed)
- MoE models count TOTAL resident parameters, not active
- the stall watchdog can never be shorter than the cold-load allowance

## Reporting Bugs

Open an issue with:
1. What you expected to happen
2. What actually happened
3. Which models you were using (name + size)
4. The debug output from Godot's console (if available)

Common non-bugs:
- Small models (3B) producing short/incoherent output — this is expected, the auto-amnesia system handles it
- Models "breaking" on startup — they aren't loaded in LM Studio, load them or swap the preset
- "MASK SLIP" banners — this means the sanitization pipeline caught a prompt leak, working as intended
