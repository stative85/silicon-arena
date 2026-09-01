# Changelog

## Unreleased (since v0.1.0-rc2)

### Security

- **Clip filenames could escape the clips directory.** Names are built from
  agent names, which come from editable preset JSON; only spaces were
  sanitised, so `../../evil` wrote outside `CLIP_DIR`. Now an allowlist
  (`A-Za-z0-9_-`), capped at 64 characters, with a source-level assertion that
  `_start_recording` actually calls the sanitiser.

### Added

- **`--balanced` roster mode.** The default roster (five models, five cold
  loads per round) and `--fast` (one model, one load) were the two ends of one
  dial with nothing between them. `--balanced` puts five agents on N models and
  orders the roster so agents sharing a model are adjacent, which costs one
  load per *model* rather than one per *agent*. Measured on an RTX 5060 8GB,
  same build and same 260s window, zero failures in all three: **8 speeches
  diverse, 33 balanced, 64 fast**. Balanced is 4.1x the default roster and
  still has two architectures arguing.
- **`scripts/arena/turn_order.gd`** holds the cost model — a round costs one
  cold load per adjacent model *change*, counted circularly — with 19 checks
  pinning the arithmetic and optimality.
- **`tools/lint_private_paths.py`**, which fails the build if a script depends
  on the private `../extinct_os/` checkout with no public path.
- **`--no-wait`** for `live_match.gd`.

### Fixed

- **HTTP 400 was reported as "model not available"**, sending users to download
  a model that was already installed. The client now summarises the real cause
  and the arena prints it with a remedy.
- **The F6 model picker listed models the policy refuses** — 8B through 32B —
  while failure messages told users to pick from it. The ceiling is now applied
  before the list is built.
- **`live_match.gd` told users to run `npx tsx tools/buildModelCatalog.ts`**,
  which does not exist in this repository.
- **Five scripts were dead on arrival in a public clone.** `alliance_proof`,
  `scar_ab_probe`, `scar_ladder`, `scar_table` and `match_scene` hardcoded
  `../extinct_os/config/arena-roster.v1.json` — a *private* sibling checkout —
  as their only roster path. `live_match.gd` had its own two-entry search list
  and worked, which is precisely why the breakage stayed invisible: the one
  path anyone ran was fine. All six now share `RosterPath`, and a lint keeps
  the class from returning.
- **Nothing in the repository could produce `config/arena-roster.v1.json`.**
  The advice was to copy `user://presets.json` there, which cannot work — the
  two files have different schemas. `build_roster.gd` now writes both from one
  selection, so they cannot drift apart either.
- **Headless live runs hung forever waiting for a browser overlay.**
  `_wait_for_client_sec` defaulted to `0.0` and the start-barrier fallback was
  guarded by `> 0.0`, so the default meant "wait forever": 275 seconds produced
  0 speeches and 0 errors, indistinguishable from a hang. The default is now a
  bounded 45s.
- **The LM Studio URL was hardcoded in five places**, so `SILICON_ARENA_LM_URL`
  was honoured by some paths and ignored by others.
- **README, CLAUDE.md and CONTRIBUTING.md shipped `toolserify.cmd`** — a
  vertical tab had replaced a backslash in `tools\verify.cmd` during a scripted
  edit. The command rendered almost correctly and did not exist.
- **SETUP.md contradicted the code**: it said HTTP 400 meant "model not found"
  and recommended 12B models that the ceiling refuses.
- 68 orphan `.import` files and 38 vendor-bundle extras (Unity packages,
  Spriter sources, a CraftPix marketing coupon) removed from tracking.

### Added

- `SILICON_ARENA_LM_URL` / `LM_STUDIO_URL` override, resolved once in
  `scripts/api/lm_endpoint.gd` and honoured by every tool and the launcher.
  Accepts bare `host:port`, with or without scheme or `/v1`.
- `--fast` roster mode: one resident model across five logical agents. Measured
  over the same 280s window, **49 speeches instead of 7**, 100% completion
  instead of 70%. Trades heterogeneity for throughput; documented as such.
- `[LOADING]` heartbeat every 10s during a cold model load, so an 18-38s swap
  is visibly progressing rather than looking like a hang.
- `tools/offline_selftest.gd` — proves the arena degrades cleanly with no LM
  Studio (callback fires, honest reason, queue not wedged).
- `tools/lint_docs.py` and `tools/lint_workflows.py`, both in CI and
  `verify.cmd`.
- CI now covers `doctor`, `build_roster` and `prove` in the no-LM-Studio state
  a first-time user is actually in.

### Testing

- `verify.cmd` demands a **positive success token** from each suite. The old
  harness passed on the absence of the word "failure", so a test printing
  nothing would have reported green.
- Parity self-test gained `SINGLE_SOURCE`: facts that must be written down
  exactly once. It caught `live_match.gd` still hardcoding the endpoint after
  the refactor fixed the other four call sites.
- Suite counts: parity 12, adversarial 41, compat 27, offline 6, configs 46.


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
