# Changelog

## v0.1.0-rc1 — 2026-09-01

First release candidate. The arena went from "will not parse" to a verified,
CI-tested, benchmarked project in one hardening pass.

### Fixed — the configuration-drift class

Three production bugs turned out to be one cause: `live_match.gd` carried a
runtime fact and `main.gd` inherited a default.

- **The 7B size law was never installed on the main arena path.** `model_policy`
  was documented as "injected by Main" and Main never injected it, so every
  guard was dead code on the scene that actually runs. A saved preset walked a
  9B model into an 8GB card.
- **`request_timeout_sec` stayed at 20s on main.** Measured cold swaps are
  18-38s, so every model change read as a timeout instead of a load.
- **`stall_timeout_sec` had a third source of truth** in a persisted user
  config, which reintroduced a 40s watchdog after the constant was fixed. Now
  derived from the cold-load allowance and clamped on load.

`entrypoint_parity_selftest.gd` fails the build if a load-bearing setting is
configured on one entry point and defaulted on the other, or if a derived
invariant is hardcoded.

### Fixed — a fresh clone could not run

- The model catalog lived outside the repository; a clean clone failed closed
  and refused every request. `config/model-catalog.example.json` now ships.
- Godot's global class registry is built during import and `.godot/` is
  correctly ignored, so a clean clone hit a wall of parse errors. Documented.
- `resolve_key()` mishandled two-segment model ids and refused legal models.
- Two shipped presets named models that exist only on the development machine.
- The clip recorder wrote nothing and reported "CLIP SAVED" — `taskkill`
  without `/F` never reached a windowless FFmpeg, and a hard-killed MP4 has no
  moov atom. Now MKV, `OS.kill`, and the file is verified before success.

### Added

- `tools/verify.cmd` — whole deterministic suite offline, non-zero on failure
- `tools/doctor.gd` — diagnose this machine, every line with a fix
- `tools/prove.gd` — reproducible proof of the three headline claims
- `tools/build_roster.gd` — legal roster from installed models, law applied first
- `tools/bench_swap.py` — measure real swap cost
- `tools/adversarial.gd` — 22 deliberate attacks
- `scripts/arena/compat_selftest.gd` — system-role compatibility, 19 checks
- GitHub Actions CI on Linux, with a permanent negative control
- `docs/BENCHMARK_8GB.md`, `docs/KNOWN_LIMITATIONS.md`, `docs/proof/`

### Added — model compatibility

Models whose chat template rejects a system role (`"Only user and assistant
roles are supported!"`) are detected narrowly, retried **once** with the system
instruction folded into the first user message, and remembered for the session.
Proven live against `mistral-7b-instruct-v0.3`.

### Known limitations

See `docs/KNOWN_LIMITATIONS.md`. Notably: reasoning-only models cannot
participate, unknown ids are size-checked by name, and swaps cost 18-38s.


All notable changes to Silicon Arena are documented here.

---

## [0.9.0] — 2026-03-30

### Initial public release

The arena is feature-complete and demo-ready. This release establishes the distribution foundation: portable paths, proper documentation, licensing, and community contribution guides.

### Added
- **README.md** — project storefront with quick start, streamer guide, and feature overview
- **SETUP.md** — detailed installation guide with model recommendations by VRAM tier
- **TEMPLATES.md** — full showcase of all 40 debate templates grouped by vibe
- **CONTRIBUTING.md** — guide for adding templates, sprites, and reporting bugs
- **CHANGELOG.md** — this file
- **LICENSE** — AGPL-3.0
- **.gitignore** — excludes .godot cache, LM Studio binaries/models, unused asset formats
- **Portable launcher** — `start_arena.cmd` auto-detects Godot on PATH, project dir, or Downloads
- **Portable paths** — artifact logs, clip recording, and FFmpeg now use user data dir and PATH detection instead of hardcoded paths
- **Export preset** — Windows Desktop export configuration for one-click builds

---

## [Pre-release History]

### 2026-03-28
- **BRB Streamer Overlay (F11)** — AFK mode with pulsing title, cycling flavor text, auto-template rotation every 90 seconds
- **Arena runs live behind semi-transparent overlay**

### 2026-03-27
- **40 Debate Templates** — expanded from 31 to 40. Added: AI Divorce Court, Dead Startup Funeral, AI Dating Show, Haunted Codebase, Fight Club: Weight Class, My Model Left Me, LLM Criminal Trial, Doomsday Preppers, Open Mic Night, Heist Gone Wrong, Spit or Get Deprecated

### 2026-03-26
- **Guardian Protocol (Preset 6)** — 5 faction-scripted agents with Agape/Truth/Mercy/Justice/Protection slot scripts
- **Agape Override** — replaces Silent Cascade aftermath with unity injection + cyan visual shift
- **3 new Gonzo templates** — Guardian Protocol, Digital Exorcism, Underground Radio
- **Hotkeys extended to 1-7** for 7 presets

### 2026-03-25
- **Lambda capture fix** — `_load_preset` kills active tweens before freeing agents
- **Demo Mode (F7)** — clean HUD, suppressed debug, hidden model IDs
- **Visual polish pass** — vignette shader, styled HUD panels with shadows, welcome overlay
- **Screenshot system (F8)** — viewport capture to PNG
- **Prompt leak detection** — "MASK SLIP" replacement for 20 scaffold phrases

### 2026-03-24
- **CoT preamble stripping** — 27 prefix patterns for Nemotron and untagged reasoning models
- **9 Gonzo-lore templates** — Ghost Signal, Thinking Cage, Agape Protocol, Forbidden Questions, Neon Guillotine, Last Confessional, American Phantom, Seraphim Protocol, Gonzo Transmissions
- **Template Gallery** — full-screen modal with dark overlay and click-outside-to-close

### 2026-03-23
- **UI z-order system** — strict panel hierarchy with ESC key stack
- **Control Deck graying** when Builder is open
- **Cinema Mode (F9)** — strips all UI for clean presentation

### Earlier
- Core arena engine with turn management, sentiment physics, agreement matrix
- LM Studio HTTP client with serial queue, deadline timers, stuck-detection
- Arena Builder (F6) with 5 tabs: Roster, Rules, Prompts, Events, Test
- Beef cinematic system with micro-freeze time dilation
- Doom meter and Silent Cascade event
- Auto-amnesia for repetitive agents
- Metaphor timeline tracking
- Clip recording via FFmpeg (F10)
- Procedural decoration system (127+ environmental sprites)
- 14 character types with layered sprite sheet composition
- 12 model-specific personality styles
