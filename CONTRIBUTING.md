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
