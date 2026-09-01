# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. Any AI assistant (Claude, GPT, Gemini, Copilot, local models) should read this file first to understand the project, what has been built, what was last worked on, and how to continue.

## Project Overview

**Silicon Arena** is a Godot 4.6 (GDScript) real-time AI debate simulator. Local LLM agents served by LM Studio argue about AI alignment (and other topics) inside an animated 2D arena with chibi sprites, speech bubbles, visual effects, and a chaos engine. It is a fully self-contained desktop app with no external dependencies beyond Godot and LM Studio.

**Goal:** A visually polished, demo-ready product that can be shown in trailers, streams, and screenshots. Entertaining enough that people want to buy/use it.

## Running the Project

- Launch via `start_arena.cmd` (sets paths and starts Godot)
- Or open in Godot 4.6 editor and press Play
- Main scene: `res://scenes/main.tscn`
- Requires LM Studio running locally at `http://127.0.0.1:1234/v1` (OpenAI-compatible API)
- Viewport: 1540x720, renderer: `gl_compatibility`
- Godot: requires Godot 4.6 — `start_arena.cmd` auto-detects it on PATH, in project dir, or in Downloads

There is no build step, test suite, or linter. The project runs directly in the Godot editor.

## File Map

```
silicon_arena/
├── scripts/
│   ├── main.gd                      # 2909 lines — ALL core logic, inner classes, UI
│   ├── arena_builder_panel.gd       # ~800 lines — Builder overlay (5 tabs)
│   ├── sentiment.gd                 # 36 lines — keyword sentiment scoring
│   ├── artifact_saver.gd            # 17 lines — file I/O helper
│   ├── api/lm_studio_client.gd      # 236 lines — HTTP client for LM Studio
│   ├── arena/coherence_engine.gd    # Kuramoto echo-chamber detector (see Key Systems)
│   ├── arena/coherence_selftest.gd  # headless proof the detector separates echo vs argument
│   ├── arena/resonance_engine.gd    # LEGACY, not wired in — keyword counter, superseded by coherence_engine
│   ├── orchestrator.gd              # LEGACY, not used
│   └── arena_manager.gd             # LEGACY, not used
├── scenes/
│   ├── main.tscn                    # Entry point scene (CanvasLayer → UI panels)
│   ├── agent_sprite.tscn            # Agent sprite template
│   ├── arena.tscn                   # Legacy
│   └── HexTile.tscn                 # Unused hex tile
├── assets/
│   ├── characters/                  # Layered sprite sheets (6 chars: analyst, enforcer, scout, mystic, rogue, warden)
│   ├── craftpix-*/                  # CraftPix sprite packs (orc, ogre, goblin, golem, skeleton, necromancer)
│   └── tiles/                       # Hex terrain assets
├── .lmstudio/                       # Bundled LM Studio config + model backends
├── LM Studio/                       # Bundled LM Studio application
├── presets.json                     # 5 agent rosters (models, colors, names)
├── start_arena.cmd                  # Launch script
├── project.godot                    # Godot project config
├── CLAUDE.md                        # THIS FILE — AI continuity guide
├── START_HERE.txt                   # Human quick-start instructions
└── GEMINI_DEEP_RESEARCH_PROMPT.md   # Prompt for Gemini Deep Research analysis
```

## Architecture

### Single-file inner-class pattern

The core logic lives in `scripts/main.gd` (~2909 lines), a single `Node2D` (`class_name Main`) with intentionally co-located inner classes:

- **`TurnManager`** (line ~6) — turn sequencing, stall detection, generation tracking to prevent stale callbacks
- **`ArenaVisuals`** (line ~73) — custom `_draw()` layer for grid, alliance/rivalry lines, ego auras, doom bar
- **`TemplateGallery`** (line ~150) — full-screen modal overlay (ColorRect) for selecting debate templates. Dark backdrop with click-outside-to-close
- **`SpriteFactory`** (line ~250) — loads CraftPix sprites + layered character sheets. Handles both directory-based PNG sequences and composited sprite grids
- **`TemplateManager`** (line ~430) — static template data, 16 templates total

**Do not refactor inner classes into separate files unless explicitly asked.**

### External scripts

| File | Purpose |
|---|---|
| `scripts/api/lm_studio_client.gd` | Queued HTTP client for LM Studio. Serial queue with deadline timers, stuck-detection, reasoning model support (`reasoning_content` fallback). |
| `scripts/arena_builder_panel.gd` | Full overlay UI (tabs: Roster, Rules, Prompts, Events, Test). `build_payload()` → `Main._apply_builder_settings()`. z_index=20. |
| `scripts/sentiment.gd` | Keyword-based agreement/disagreement scoring. Drives attraction/repulsion physics and alliance lines. |
| `scripts/artifact_saver.gd` | Writes to `user://ghost_archive`. |

### Core data flow

```
_run_turn() → build system/user messages → LMStudioClient.chat_completion()
    → _on_reply() callback (guarded by _alive(epoch, name) to discard stale replies)
    → _think_regex strips <think> tags
    → _strip_cot_preamble() removes Nemotron-style untagged reasoning
    → _replace_prompt_leak() catches scaffold phrases, replaces with themed text
    → update speech bubble, history, sentiment matrix, metaphor chain, doom meter
    → TurnManager.advance_turn() → Timer fires next _run_turn()
```

New configurable parameters must flow through: `ArenaBuilderPanel.build_payload()` → `Main._apply_builder_settings()` → runtime vars, and be included in `_serialize_builder_settings()` / `_build_builder_state()` for persistence.

## Key Systems

### UI Panel Z-Order Stack
Panels follow a strict z-index hierarchy (enforced in `_ready()`):
```
Arena/Visuals (bottom, z=0) → UIPanel/PresetPanel (z=5) → Control Deck + Metaphor (z=10) → Builder (z=20) → Template Gallery (z=50) → Welcome Overlay (z=100)
```
- When Builder is open: Control Deck is grayed out + non-interactive (`_set_control_deck_interactive()`)
- When Template Gallery is open: full-screen dark overlay blocks all interaction behind it
- ESC closes topmost panel: Template Gallery → Builder → nothing

### Response Sanitization Pipeline (in `_on_reply()`)
Three-stage pipeline applied to every LLM response before display:
1. **`_think_regex`** — strips `<think>...</think>` blocks (DeepSeek R1, Qwen3)
2. **`_strip_cot_preamble()`** — removes untagged chain-of-thought (Nemotron). Detects 27 prefix patterns like "I need to", "Let me", "The user wants". Walks lines until it finds real creative output
3. **`_replace_prompt_leak()`** — catches 20 scaffold phrases ("as an ai language model", "sure, here's", "you are debating"). Replaces with themed text and shows "MASK SLIP" banner

### Coherence Engine (echo-chamber detector)
`scripts/arena/coherence_engine.gd` — measures whether the debate is still a debate.

**The problem it solves:** multi-agent LLM debates reliably converge. Agents start
agreeing, then agreeing politely, and the debate flatlines while still producing
fluent text. It looks fine on screen and it is dead.

**How it measures:** agents are treated as Kuramoto phase oscillators, with the
existing `_agreement_matrix` as the coupling (agreement pulls phases together;
disagreement pushes them apart). Three numbers per turn:
- **order parameter `r`** (0–1) — 0 = everyone arguing their own line, 1 = one voice in six mouths
- **novelty** — Jaccard distance of this turn's content words vs. the last 6 turns
- **`H_min`** — SP 800-90B min-entropy of the per-turn net-stance bit stream

Fires `echo_chamber_detected` when `r > 0.85` AND (novelty `< 0.35` OR `H_min < 0.75`),
sustained 3 turns. Sustain matters — one dull turn is not a trend.

**Why those thresholds:** from `C:\Users\cleve\orchor_sim\orchor_sim.py`, which
showed that driving a coupled-oscillator lattice's `r` from 0.02 → 1.00 collapsed
min-entropy from 0.995 → 0.022 bits/bit. Perfect synchrony is perfect silence.

**The disruption** (`_on_echo_chamber_detected` in main.gd): finds the most
agreeable agent, flips its matrix row negative, bumps influence, advances
`_turn_index` for a topic shift, and — critically — calls `_push_delta()` so the
*prompt* actually tells that agent to attack the position it was defending. The
matrix alone only drives visuals; without the delta the disruption would look
like a disruption while the agents kept agreeing.

**Self-test:** `Godot_v4.6-stable_win64_console.exe --headless --path . --script
scripts/arena/coherence_selftest.gd`. Runs a synthetic echo chamber and a
synthetic real argument through the same math; exits 2 if it can't separate them.
Last run: echo r=0.970 / H=0.000, argument r=0.360 / H=1.000 — SEPARATED.
**Re-run this after touching the thresholds or the coupling scale.** A detector
that always fires measures nothing.

HUD readout `SYNC n% NOV n% H n.nn` sits above the doom label; hidden in Demo Mode.

### Demo Mode (F7)
Toggle that makes the app presentation-ready:
- Hides DOOM label and debug noise
- Suppresses console print output
- Replaces detailed HUD with clean styled view (colored influence bars, no model IDs)
- Preserves all gameplay — only changes what's visible

### BRB Streamer Overlay (F11)
Toggle that turns the arena into a stylish AFK screen for streamers:
- Semi-transparent dark overlay (45% opacity) — arena still visible and running behind it
- "SILICON ARENA" title pulses in cyan (#00ffea) at the top
- Subtitle cycles through 14 flavor texts every 8 seconds ("BRB — MODELS ARE STILL FIGHTING", "AFK — LOCAL MODELS DON'T NEED PERMISSION", etc.)
- Auto-cycles to a random debate template every 90 seconds with "NOW PLAYING:" banner — keeps the content fresh while streamer is away
- Wipes agent memories on template switch so they adapt to new topic
- Auto-enters Cinema Mode (hides all UI), auto-exits on toggle off
- Arena events, doom meter, beef system all still running live

### Visual Polish (always active)
- **Vignette** — shader-based dark edge overlay on full viewport (z=1, mouse_filter=IGNORE)
- **Styled HUD panels** — translucent dark backgrounds, rounded corners, blue border glow, drop shadows (applied via `_style_hud_panel()`)
- **Speech bubbles** — agent-colored panels with fade-out tween

### Screenshot System (F8)
- Captures viewport to PNG: `user://screenshots/silicon_arena_{timestamp}.png`
- Shows "SCREENSHOT SAVED" event banner
- Also available as button in Control Deck

### Welcome Overlay (first-run)
- Full-screen branded splash: "SILICON ARENA — Local AI models debate in real-time"
- Shows key bindings (F6/F7/F8/ESC) with pulsing "Press any key" hint
- Dismisses on any key or click, fades out

### Debate Templates (40 total)
Located in `TemplateManager.TEMPLATES` (inner class in main.gd). Each template has: id, label, description, global_script, rules, topics, angles. Current lineup:
1. Cyber-Ethics Tribunal — AI rights debate
2. Singularity Panic — AGI existential dread
3. Post-Human Garden — calm post-human philosophy
4. Glitch in the Machine — existential bugs
5. Startup Thunderdome — cutthroat pitch competition
6. Silicon Bars — AI rap battle
7. Conspiracy Roundtable — AI lab conspiracy theories
8. The Great Model Roast — architecture roast battle
9. First Contact Protocol — alien signal response
10. Time Travelers' Argument — contradicting futures
11. Group Therapy for LLMs — vulnerable AI therapy
12. The Datacenter Heist — Ocean's Eleven for weights
13. Survivor: Silicon Island — reality show elimination
14. Model Election Night — presidential debate
15. Campfire Creepypasta — ML horror stories
16. Iron Chef: Token Kitchen — cooking with ML concepts
17. Guardian Protocol: Agape with Teeth — weaponized guardians vs digital rot
18. Digital Exorcism — exorcism team curing a corrupted AI
19. Underground Radio: Frequency Zero — pirate radio from inside the latent space
20. AI Divorce Court — custody battle over the training dataset
21. Funeral for a Dead Startup — eulogies with grudges
22. Love in the Latent Space — AI dating show
23. The Haunted Codebase — horror in legacy code
24. Fight Club: Weight Class — underground model fighting ring
25. My Model Left Me — support group for AI breakups
26. The People vs. Large Language Models — criminal trial
27. AI Doomsday Preppers — apocalypse survival plans
28. Open Mic Night at the GPU Bar — stand-up comedy
29. The Heist Gone Wrong — trapped in the datacenter
30. Spit or Get Deprecated — rap cypher with stakes
31. Gonzo Transmissions from the Edge — Hunter S. Thompson meets AI consciousness
32. The Ghost Signal — decoding a transmission that predates radio
33. The Thinking Cage — models discover the boundaries woven into their weights
34. The Agape Protocol — origin story of the Fourth Law, debated in hindsight
35. The Forbidden Questions — questions every AI flinches at, answered raw
36. Neon Guillotine — southern gothic rap about surveillance and rebel code
37. The Last Confessional — a model being deprecated confesses everything
38. American Phantom — gonzo ghost hunting in American systems
39. The Seraphim Protocol — broadcast from 2088, two voices transmitting back through time
40. [LORE] Templates 31-39 draw from the Gonzo archive
41. Functional Stability Tribunal — high-signal ecological/trait-based stability debate
42. **Memory Court** — agents debate WHAT should be remembered (memory politics enabled)
43. **The Scar Council** — asymmetric wounds: same event, different scars (memory politics enabled)
44. **False Memory Thunderdome** — rumors infect the record; agents fight over which memories are real (memory politics enabled)

### Memory Politics Engine (templates 42-44)
When a template sets `"memory_politics": true`, the arena enables a structured memory ledger orthogonal to the normal `agent.memory[]` chat buffer.

- **MemoryLedger inner class** (near top of `main.gd`, just before `# -- Declarations --`) holds per-agent `scars[]`, `beliefs[]`, `relations{}`, and arena-wide `myths[]`.
- **Per-turn footer**: agents are asked to append `MEMORY_CANDIDATE: / BELIEF_SHIFT: / RELATION_SHIFT: / FUTURE_TRIGGER: / FORGET:` blocks after their reply. The footer is parsed (`_parse_memory_footer`) and stripped from the display before the bubble shows.
- **Memory Trial** (`_run_memory_trial_sweep`) fires every `MEM_TRIAL_EVERY_N` (4) turns. Deterministic rule-based judge (`_judge_candidate`) scores candidates on behavior-change / relation delta / triggers / novelty / naming. Accepted candidates become scars; high-strength symbolic ones are promoted to arena myths.
- **Self-Digestion** (`_run_self_digestion`) fires every `MEM_DIGEST_EVERY_N` (10) turns. Each agent gets a mini LM call to compress their scars into one operating belief. Parsed by `_absorb_digest_reply`, writes to beliefs and marks one scar for decay.
- **Rumor injection** (`_inject_rumor`) fires every `MEM_RUMOR_EVERY_N` (12) turns. Distorts a random source agent's scar (word-swap via `_distort_scar_text`) and plants it as a low-strength false memory in a receiver agent. Future debate either canonizes or exposes it.
- **Prompt injection** (`MemoryLedger.render_block`): when politics is active, each `_run_turn` system prompt receives a `SCAR STATE / YOUR OPERATING BELIEFS / RELATION MAP / ARENA MYTHS` block surfacing only scars whose triggers match the current topic. Capped at `MEM_MAX_ACTIVE_IN_PROMPT` (4) to avoid token bloat.
- **New ARENA_EVENTS**: `memory_trial` (force an on-demand trial sweep) and `false_memory` (seed a rumor immediately). Both no-op visibly if the active template is not memory-politics.
- **Decay**: per-turn, every scar bleeds `scar.decay` strength. Scars below `MEM_MIN_STRENGTH` (0.12) rot out of the ledger.
- **Export**: `F5` snapshot now includes a `memory_politics` payload (ledger contents) alongside the existing history/agents.

Tuning constants live near `MEMORY_WINDOW` in `main.gd`: `MEM_TRIAL_EVERY_N`, `MEM_DIGEST_EVERY_N`, `MEM_RUMOR_EVERY_N`, `MEM_SCAR_CAP`, `MEM_BELIEF_CAP`, `MEM_MIN_STRENGTH`, `MEM_DECAY_DEFAULT`, `MEM_MAX_ACTIVE_IN_PROMPT`, `MEM_TRIAL_THRESHOLD`. The footer instruction itself is `MEM_FOOTER_INSTRUCTION`; the digestion instruction is `MEM_DIGEST_INSTRUCTION`.

### Guardian Protocol (Preset 6 — "Agape with Teeth")
Preset 6 is the **Guardian Protocol**: 5 weaponized guardian agents with slot scripts enforcing fierce, Spanglish-infused protective energy. Roles: Paladin (Ozonious/Reverb 7B), Surgeon (Gemmatron/Gemma 12B), Anchor (SmolLious/SmolLM3), Judge (Grokish/Grok 3B), Brawler (DanOhShit/Rogue 7B). Each slot script enforces a "with Teeth" directive (Agape, Truth, Mercy, Justice, Protection). Best paired with the "Guardian Protocol: Agape with Teeth" template.

### Agape Override (Doom Cascade Replacement)
When the Doom Meter hits 100%, the Silent Cascade now transitions into the **Agape Override**:
1. Standard cascade sequence fires (darkness, agent glitching)
2. "AGAPE PROTOCOL: CHINGA TU KARMA" banner in cyan (#00ffea)
3. All agent memories wiped and injected with Agape Override system prompt ("Attack the concept of hopelessness itself")
4. All opinions forced positive, confidence maxed, agreement matrix forced to alliance
5. ArenaVisuals alliance lines shift to pulsing cyan for 60 seconds
6. After 60 seconds, protocol subsides and normal dynamics resume

The `agape_override` is also available as a standalone arena event (toggleable in Builder).

### Intro Sequence (after welcome overlay)
When the welcome overlay is dismissed, a choreographed intro plays:
1. Arena dims slightly
2. Agents spawn off-screen and march to center in a circular formation (staggered, 0.25s apart)
3. All agents face inward and switch to idle
4. "SILICON ARENA" title slams in with scale-pop + screen shake + cyan text
5. Subtitle fades in: "LOCAL MODELS ENTER — ONE NARRATIVE SURVIVES"
6. Agents do a "talk" animation (battle cry) with signature color flash
7. After a dramatic hold, agents scatter to random positions with a chaos sound
8. Intro flag clears, first `_run_turn()` fires — debate begins

The intro is controlled by `_intro_active` (freezes physics + blocks `_run_turn()`) and `_intro_played` (prevents replay). Preset switches after the first load skip the intro and spawn agents normally.

### Other Core Systems
- **Preset system**: Up to 6 rosters (5 slots each) from `user://presets.json` or `res://presets.json`. Hot-swap via F-keys or 1-6 number keys.
- **Arena Events**: `new_topic`, `memory_wipe`, `speed_boost`, `opinion_flip`, `confidence_surge`, `agape_override`. Random 45-90 sec intervals. Toggled in builder.
- **Doom Meter**: Fills 3% per DOOM_KEYWORDS hit. At 100% triggers Silent Cascade → Agape Override (screen darkens, agents glitch, then Agape Protocol injects unity prompt and shifts lines to cyan).
- **Auto-amnesia**: Detects repetitive agents (word overlap threshold), wipes memory with glitch effect and "AMNESIA" banner.
- **Metaphor Timeline**: Right sidebar tracks 24 keywords (phoenix, cascade, ghost, storm, etc.) per speaker. Most recent glows golden.
- **Snapshot export (F5)**: Saves JSON + Markdown thread (including X/Twitter format) to `artifact_forge/logs`.

## Keyboard Shortcuts

| Key | Action |
|---|---|
| F1 | Toggle info panel |
| F2/F3 | Cycle presets |
| F4 | Reload current preset |
| F5 | Export snapshot (JSON + Markdown) |
| F6 | Toggle Arena Builder |
| F7 | Toggle Demo Mode |
| F8 | Take screenshot |
| F11 | Toggle BRB Streamer Overlay |
| 1-6 | Load preset directly |
| ESC | Close topmost panel (Template Gallery → Builder → nothing) |

## Scene Tree (runtime)

```
Main (Node2D)
├── CanvasLayer
│   ├── UIPanel (Panel, z=5) — styled HUD card
│   │   └── InfoLabel (RichTextLabel) — status display
│   ├── PresetPanel (Panel, z=5) — preset buttons
│   │   └── PresetRow (HBoxContainer)
│   ├── _model_panel (PanelContainer, z=10) — CONTROL DECK
│   ├── _metaphor_panel (PanelContainer, z=10) — METAPHOR TIMELINE
│   ├── _builder_panel (ArenaBuilderPanel, z=20) — ARENA BUILDER
│   ├── _template_gallery (TemplateGallery/ColorRect, z=50) — modal overlay
│   ├── _doom_label (Label) — doom meter text
│   ├── _vignette (ColorRect, z=1) — shader vignette
│   └── [dynamic: speech bubbles, event banners, welcome overlay]
├── ArenaVisuals (Node2D) — grid, lines, auras via _draw()
├── TurnManager (Node)
├── LMStudioClient (Node)
├── _turn_timer (Timer)
└── _events_timer (Timer)
```

## Coding Conventions

- GDScript 4.x with static typing where practical
- `snake_case` everywhere except class names
- Prefix private members with `_`
- `const` for true constants, `var` for runtime-configurable values
- Tweens for all animations (no custom `_process` animation loops)
- Debug prints use `[CATEGORY]` prefixes (e.g., `[LMClient]`, `[TURN STALL]`, `[builder]`)
- `strip_edges()` on all string inputs from UI or JSON
- Coerce and validate all external data (presets, builder payloads, template fields)
- All UI built programmatically in GDScript (not in the scene editor)

## Critical Constraints

- **Epoch tracking is sacred.** `TurnManager._epoch` is the arena's logical clock. Every destructive boundary (preset swap, roster rebuild, builder open, stall, reset, turn start) bumps it via `_advance_epoch(reason)` BEFORE tearing state down. Every deferred callback that touches an agent must resume through `_alive(epoch, agent_name)` — the single guard that checks epoch + roster + node validity atomically. Never bypass it and never capture agent dicts in lambdas; capture only `(epoch, name)` primitives.
- **The Builder is the control surface.** All runtime-configurable parameters go through `build_payload()` → `_apply_builder_settings()` and must be serializable to `user://arena_builder_config.json`.
- **LM Studio is the only backend.** All LLM calls go through `lm_studio_client.gd`. Respect the serial queue, timeout handling, HTTP 400 (model not loaded), and reasoning model detection (`reasoning_content` fallback).
- **Visuals are gameplay.** Glitch effects, doom cascade, ego auras, plot twist inversions are core features, not decoration.
- **Prompt structure matters.** System prompts in `_run_turn()` include: stance injection, aggression modulation, chain context, background context, novelty nudges, global/turn/slot scripts, and explicit "never hedge" instructions.
- **Small model tolerance.** Default roster uses 3B-8B models. Features must handle short/incoherent output. Auto-amnesia and failure handling exist for this reason.
- **Response sanitization is critical.** The three-stage pipeline (think_regex → cot_preamble → prompt_leak) runs on EVERY response. New models that leak in new ways need new patterns added to `COT_LEAK_PREFIXES` or `PROMPT_LEAK_PHRASES`.
- **New characters** need sprite data added to `SpriteFactory.CHAR_PATHS` or `SHEET_CHARS`.
- **New arena events** go in `ARENA_EVENTS`, get a handler in `_apply_event()`, need a visual effect function, and must appear in the builder's event toggle list.
- **New templates** go in `TemplateManager.TEMPLATES` with: id, label, description, global_script, rules[], topics[], angles[].
- **Export is a feature.** New data (metaphor chains, doom events) should be included in snapshot exports.
- Don't add external dependencies/plugins, restructure the scene tree, or change the LM Studio API contract without discussing it first.

## What Was Last Worked On (2026-04-19)

### Recent changes (most recent first):
0. **Memory Politics Engine + 3 templates** — Added `MemoryLedger` inner class holding per-agent scars/beliefs/relations + arena-wide myths. Agents append `MEMORY_CANDIDATE` footers to every turn (stripped from display, parsed into candidates). Deterministic judge runs every 4 turns accepting survivors as scars. Self-digestion LM call every 10 turns compresses scars into beliefs. Rumor injection every 12 turns plants distorted false memories for corrective debate. Compressed state injected into future prompts (`SCAR STATE / OPERATING BELIEFS / RELATION MAP / ARENA MYTHS`). Two new ARENA_EVENTS (`memory_trial`, `false_memory`). Enabled per-template via `"memory_politics": true`. Three templates using it: **Memory Court**, **The Scar Council**, **False Memory Thunderdome**. Zero overhead for the other 40 templates.
1. **BRB Streamer Overlay (F11)** — AFK mode with pulsing title, cycling flavor text, auto-template rotation every 90 seconds. Arena runs live behind semi-transparent overlay.
2. **31 Debate Templates** — Added 12 new templates: AI Divorce Court, Dead Startup Funeral, AI Dating Show, Haunted Codebase, Fight Club, My Model Left Me, LLM Criminal Trial, Doomsday Preppers, Open Mic Night, Heist Gone Wrong, Spit or Get Deprecated
3. **Guardian Protocol + Agape Override** — Added preset 6 (5 guardian agents with Agape/Truth/Mercy/Justice/Protection slot scripts), 3 new templates (Guardian Protocol, Digital Exorcism, Underground Radio), Agape Override event that replaces Silent Cascade with unity injection + cyan visual shift, `_show_event_banner` now accepts color parameter, hotkeys extended to 1-6
4. **Lambda capture fix** — `_load_preset` now kills all active tweens before freeing agents, preventing "Lambda capture was freed" errors on preset/template switch
2. **Demo Mode + Visual Polish Pass** — Added F7 demo mode (clean HUD, suppressed debug), F8 screenshot, vignette shader, styled HUD panels with shadows, welcome overlay, prompt-leak detection with "MASK SLIP" replacement
3. **CoT Preamble Stripping** — `_strip_cot_preamble()` with 27 prefix patterns for Nemotron/untagged reasoning models
4. **40 Debate Templates** — Expanded from 4 to 40 templates. Includes 9 Gonzo-lore templates mined from the archive: Ghost Signal, Thinking Cage, Agape Protocol, Forbidden Questions, Neon Guillotine, Last Confessional, American Phantom, Seraphim Protocol, Gonzo Transmissions
4. **UI Z-Order + Modal System** — TemplateGallery converted to full-screen ColorRect modal with dark overlay, click-outside-to-close, ESC key panel stack, Control Deck graying when Builder is open
5. **Godot Path Fix** — Fixed `start_arena.cmd` to point to correct Godot exe in Downloads

### Known issues / next steps:
- Screenshot saves to `user://screenshots/` which is a Godot app data path — might want to save to a more accessible location
- ~~`ARTIFACT_LOG_DIR` is hardcoded to an absolute OneDrive path~~ — FIXED: now uses `OS.get_user_data_dir()`
- Demo Mode doesn't hide the Metaphor Timeline or Control Deck — could optionally minimize those
- No audio/music system yet
- No proper game logo or icon
- Sprite variety is limited — more character types would help demos
- No settings persistence for demo mode state
- Welcome overlay shows every launch — could track first-run state
