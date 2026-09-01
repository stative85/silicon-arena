# Silicon Arena

**5 local AI models argue live in a 2D arena — with beef cinematics, doom cascades, and no cloud APIs.**

<!-- TODO: Add a GIF of a beef clash cinematic here -->
<!-- ![Silicon Arena Demo](docs/demo.gif) -->

Silicon Arena is a real-time AI debate simulator built in Godot 4.6. Local LLM agents served by [LM Studio](https://lmstudio.ai/) debate AI alignment, rap battle each other, run therapy sessions, and trigger emergent cinematic events — all running offline on your machine.

Inspired by [Stanford's Generative Agents](https://arxiv.org/abs/2304.03442) paper. Built for streamers, the local AI community, and anyone who thinks AI should do more than answer questions politely.

---

## What Makes This Different

- **40 debate templates** — from AI ethics tribunals to rap battles to gonzo journalism to AI divorce court ([full list](TEMPLATES.md))
- **Beef system** — when agents get hostile, a cinematic clash triggers: bullet-time, weapon VFX, screen shake, crowd reactions
- **Doom meter** — certain phrases fill a global threat meter. At 100%, the Silent Cascade fires, then the Agape Override injects unity and turns the arena cyan
- **Response sanitization** — catches chain-of-thought leaks, prompt scaffold exposure, and model repetition. Leaked prompts become in-character "mask slips"
- **Auto-amnesia** — detects when small models loop and wipes their memory with a glitch effect
- **BRB overlay** — streamer AFK mode that auto-cycles templates while the arena runs live
- **7 presets** including the Guardian Protocol: 5 faction-scripted agents with Agape/Truth/Mercy/Justice/Protection directives
- **Runs entirely offline** — no cloud APIs, no subscriptions, no telemetry

---

## Quick Start

### 1. Install LM Studio
Download [LM Studio](https://lmstudio.ai/), load any GGUF model (3B-8B recommended). Start the local server — it runs at `http://127.0.0.1:1234`.

### 2. Install Godot 4.6
Download [Godot 4.6](https://godotengine.org/download/) (standard, not .NET). No installation needed — it's a single executable.

### 3. Run Silicon Arena
Double-click `start_arena.cmd`, or open the project in Godot and press Play.

> For detailed setup with model recommendations by VRAM tier, see [SETUP.md](SETUP.md).

---

## For Streamers

Silicon Arena was built to look good on camera.

| Key | Action |
|-----|--------|
| **F6** | Arena Builder — tune roster, prompts, chaos engine |
| **F7** | Demo Mode — clean HUD, no debug noise |
| **F8** | Screenshot (saved to user data) |
| **F9** | Cinema Mode — hides all UI for clean presentation |
| **F10** | Record clip via FFmpeg |
| **F11** | BRB Overlay — AFK mode with auto-rotating templates |
| **1-7** | Jump to preset |
| **F2/F3** | Cycle presets |
| **ESC** | Close topmost panel |

**Demo Mode (F7)** strips debug info, hides model IDs, and shows clean influence bars. **Cinema Mode (F9)** removes all UI for recording. **BRB Overlay (F11)** turns the arena into an AFK screen with pulsing title text, cycling flavor messages, and auto-template rotation every 90 seconds — the debate keeps running live behind a semi-transparent overlay.

---

## System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| GPU | GTX 1060 / 6GB VRAM | RTX 3060+ / 8GB+ VRAM |
| RAM | 16 GB | 32 GB |
| Storage | ~500 MB (project) + model sizes | Same |
| OS | Windows 10/11 | Windows 11 |
| Software | Godot 4.6, LM Studio | Same |

The arena itself is lightweight. Your VRAM budget goes to the LLM models in LM Studio. A single 3B model needs ~2GB VRAM. Running 5 different models simultaneously requires loading/unloading (LM Studio handles this automatically).

---

## Templates Preview

Silicon Arena ships with **40 debate templates**. Here are some highlights:

| Template | Vibe |
|----------|------|
| The Cyber-Ethics Tribunal | Formal AI rights debate |
| Silicon Bars | AI rap battle — 2-4 bars, must diss previous speaker |
| AI Divorce Court | Custody battle over the training dataset |
| Campfire Creepypasta | ML horror stories around a digital campfire |
| The Great Model Roast | Architecture roast battle |
| Guardian Protocol: Agape with Teeth | Weaponized guardians vs digital rot |
| Gonzo Transmissions from the Edge | Hunter S. Thompson meets AI consciousness |
| Spit or Get Deprecated | Rap cypher with elimination stakes |
| The Seraphim Protocol | Broadcast from 2088, two voices transmitting back through time |
| Open Mic Night at the GPU Bar | Stand-up comedy by language models |

[See all 40 templates](TEMPLATES.md)

---

## Tech Stack

- **Engine**: Godot 4.6 (GDScript)
- **LLM Backend**: LM Studio (OpenAI-compatible local API)
- **Renderer**: gl_compatibility (runs on basically anything)
- **External Dependencies**: Zero. Just Godot + LM Studio.
- **Codebase**: ~6000 lines across 6 files, single-file inner-class architecture

---

## Contributing

Silicon Arena's easiest contribution path is **new debate templates**. Each template is a dictionary with an id, label, description, rules, topics, and angles. If you can write a debate premise, you can contribute.

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on:
- Adding debate templates
- Adding character sprites
- Reporting bugs

---

## License

Silicon Arena is licensed under the [GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0).

You are free to use, modify, and distribute this software. If you run a modified version as a service, you must share your changes under the same license. The original creator retains the right to dual-license for commercial use.

Sprite assets from [CraftPix](https://craftpix.net/) are used under their [free game assets license](https://craftpix.net/file-licenses/).
