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

### Six rules that are not negotiable

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
