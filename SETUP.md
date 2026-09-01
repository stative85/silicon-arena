# Silicon Arena — Setup Guide

## System Requirements

- **OS**: Windows 10 or 11
- **GPU**: NVIDIA GTX 1060+ (for LM Studio inference). The arena itself runs on integrated graphics.
- **VRAM**: 6GB minimum, 8GB+ recommended
- **RAM**: 16GB minimum, 32GB recommended
- **Disk**: ~500MB for the project + model sizes (2-8GB per model)
- **Software**: Godot 4.6, LM Studio

---

## Step 1: Install LM Studio

1. Download LM Studio from [lmstudio.ai](https://lmstudio.ai/)
2. Install and launch it
3. Go to the **Local Server** tab (left sidebar, server icon)
4. Click **Start Server** — it should show `http://127.0.0.1:1234`

### Recommended Starter Models by VRAM

| VRAM | Model | Why |
|------|-------|-----|
| **6 GB** | SmolLM3-3B (Q4_K_M) | Smallest viable model, fast inference |
| **8 GB** | Qwen3-8B (Q4_K_M) | Best all-rounder at this tier |
| **8 GB** | Gemma-3-4B (Q4_K_M) | Great balance of quality and speed |
| **10 GB** | Gemma-3-12B (Q4_K_M) | Noticeably better output quality |
| **12 GB+** | Qwen3.5-9B + DeepSeek-R1-8B | Run two models for variety |

**How to load a model**: In LM Studio, go to the **Discover** tab, search for the model name, download it, then load it in the Local Server tab.

**Important**: Silicon Arena sends requests to whatever models are loaded. You don't need to load all 5 preset models — the arena will use what's available and mark unavailable models as "broken" (they'll show a red indicator and be skipped).

---

## Step 2: Install Godot 4.6

1. Download Godot 4.6 from [godotengine.org/download](https://godotengine.org/download/)
2. Get the **Standard** version (not .NET)
3. Extract the zip — Godot is a single portable executable, no installer needed
4. Place it somewhere convenient (your Downloads folder works fine)

---

## Step 3: Import the project once

A fresh clone has no `.godot/` cache, so Godot has not yet registered the
`class_name` types. Without this you get a wall of
`Identifier "TemplateManager" not declared` parse errors.

```
godot --headless --editor --quit --path .
```

Or just open it in the editor and let it finish importing. Once only.

## Step 4: Build a roster from YOUR installed models

The shipped presets name portable public models so the repository is not tied
to one machine — which means they are probably **not** what you have
downloaded. Point the arena at your own models:

```
godot --headless --path . --script tools/build_roster.gd
```

The 7B ceiling is applied *before* selection, so an oversized model cannot
enter the roster. Models are ranked by chat-capability and spread across
families, and then each candidate is **probed** with one tiny request — only
models that actually return text are accepted:

```
probing candidates (one cold load each, this is the slow part)...
   speaks   mistralai/mistral-7b-instruct-v0.3
   rejected qwen3-4b-instruct-...-distill — reasoning-only (empty content)
   speaks   l3.2-rogue-creative-instruct-uncensored-abliterated-7b
```

That step is slow — one cold model load per candidate — but it runs once, and
it is the difference between a roster that looks right and one that works. Add
`-- --no-probe` to skip it.

**If turns feel slow**, every turn is changing model and paying an 18-38s cold
load. Build a single-model roster instead:

```
godot --headless --path . --script tools/build_roster.gd -- --fast
```

Measured on an RTX 5060 8GB over the same 280s window: 49 speeches instead of
7. You trade architectural variety for throughput — see
`docs/BENCHMARK_8GB.md`.

## Step 5: Check the machine before launching

```
tools\doctor.cmd
```

```
SILICON ARENA DOCTOR
--------------------
Godot              OK    4.6-stable (official)
Project import     OK    class registry present
LM Studio          OK    http://127.0.0.1:1234/v1
Installed models   OK    98
Model catalog      OK    57 eligible, ceiling 7B
Eligible <=7B      OK    60 of 98 installed models permitted
Roster             OK    5/5 valid (user://presets.json)
READY
```

Every non-OK line names a concrete fix. `NOT READY` means something would stop
the arena; a `WARN` will still run.

## Step 6: Run Silicon Arena

### Option A: Double-click the launcher
Run `start_arena.cmd` in the Silicon Arena folder. It auto-detects Godot on your PATH, in the project directory, or in your Downloads folder.

### Option B: Open in Godot editor
1. Open Godot 4.6
2. Click **Import** → navigate to the `silicon_arena` folder → select `project.godot`
3. Click **Import & Edit**
4. Press **F5** (or the Play button) to run

---

## Step 7: First Launch

1. If LM Studio is running with a loaded model, agents will start debating immediately
2. Use **1-7** number keys to switch between presets (different model rosters)
3. Press **F6** to open the Arena Builder and customize everything
4. Press **F7** for Demo Mode (clean presentation view)

---

## Troubleshooting

### "LM Studio API not reachable"
- Make sure LM Studio is running
- Make sure the local server is started (check the Server tab)
- Confirm the server URL is `http://127.0.0.1:1234` (default)
- **Running LM Studio somewhere else?** Set `SILICON_ARENA_LM_URL` and every
  tool follows it:

```
set SILICON_ARENA_LM_URL=192.168.1.50:1234
tools\doctor.cmd
```

  A bare `host:port`, a full URL, and a URL with or without `/v1` all work.

### Agents show as "broken" (red indicator, skipped)
- The console now names the actual reason. Read it before changing anything:

```
[DISABLED] Mistral 7B — chat template rejects a system role (compat retry also failed)
[SKIP] Deckard 6B — prompt exceeded the model's context window (fail 1/2)
```

- **HTTP 400 does NOT mean "model not found."** It means LM Studio rejected the
  request — a chat template that refuses a system role, a malformed payload, or
  a context overflow. The reason is printed; act on that, not on a guess.
- A 400-disabled agent stays out for the session. Change its model with
  F6 → Roster, or rebuild the whole roster:
  `godot --headless --path . --script tools/build_roster.gd`
- Repeated *no-response* failures are different: those cool down and rejoin
  automatically.
- Some models cannot participate at all — see `docs/KNOWN_LIMITATIONS.md`
  (reasoning-only models, base checkpoints).

### Long pauses between turns

**This is almost always a cold model load, not a hang.** With LM Studio set to
auto-unload, every turn that changes model reloads weights from disk. Measured
on an RTX 5060 8GB: **18-38 seconds per swap**, against 0.06-0.26s once a model
is resident (`docs/BENCHMARK_8GB.md`).

The arena says so while it waits:

```
[LOADING] Mistral 7B Instruct — 20s (cold model swaps take 18-38s on 8GB)
```

To go faster, use fewer distinct models — a roster where consecutive turns
share a model gets warm-path latency. A 3B mixed in among 7Bs will visibly
snap.

Note: models above the 7B ceiling are **refused**, not slow. Picking a 12B will
not "produce better output but take longer" — it will not run at all. The F6
picker hides them and says how many it hid.

### "REC FAILED: NO FFMPEG"
- Clip recording (F10) requires FFmpeg on your system PATH
- Download from [ffmpeg.org](https://ffmpeg.org/download.html)
- Or place `ffmpeg.exe` in a `tools/` folder inside the project directory

### Models produce gibberish or repeat themselves
- This is normal for very small models (2-3B). The auto-amnesia system will detect loops and wipe the agent's memory.
- Try a larger model or adjust temperature in the Arena Builder
- Ensure max_tokens is at least 64 (Builder → Config tab)

### White flash on startup
- This is the Godot boot splash. It's brief and normal.

---

## Optional: FFmpeg for Clip Recording

Silicon Arena can record gameplay clips via FFmpeg (F10 hotkey). This is optional.

1. Download FFmpeg from [ffmpeg.org](https://ffmpeg.org/download.html)
2. Add the `bin/` folder to your system PATH
3. Restart Silicon Arena — it will auto-detect FFmpeg on startup

Clips are saved to your Godot user data directory under `artifact_forge/clips/`.

---

## Optional: Custom Presets

Edit `presets.json` in the project root to create your own agent rosters. Each preset is an array of up to 5 agents:

```json
{
  "name": "My Agent",
  "color": "#ff6b6b",
  "model": "lmstudio-community/Qwen3-8B-GGUF/Qwen3-8B-Q4_K_M.gguf",
  "script": "Optional per-agent system prompt injection"
}
```

The `model` field must match the model ID shown in LM Studio's model list.
