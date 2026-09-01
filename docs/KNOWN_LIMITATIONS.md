# Known limitations

Found by deliberately attacking the project (`tools/adversarial.gd`) and by
running it as a stranger. Recorded rather than hidden: a limitation you know
about is a design decision, one you don't is a bug waiting to be discovered by
someone else.

## Size law

**An unknown model whose name states a legal size is permitted.**

If a model id is absent from the loaded catalog, the policy reads the parameter
count out of the id string. `some-unknown-3b-model` is permitted;
`some-unknown-model` (no readable size) and `some-unknown-70b-model` are both
refused.

*Why it is this way:* a model you downloaded five minutes ago is not in a
catalog generated last week. Refusing every unknown id would mean regenerating
the catalog after every download.

*Why the exposure is bounded:* LM Studio can only load a model that exists on
disk, and a deliberately mislabelled name is refused anyway — the parser takes
the **largest** size token it finds, so `MODEL-7B-BUT-ACTUALLY-70B` reads as
70B and is refused.

*If you want strictness:* generate `config/model-catalog.v1.json` from
`lms ls --json`. A model present in the catalog is checked against real
metadata, and the catalog's `eligible` flag is re-derived rather than trusted.

**With no catalog at all, everything is refused.** That is deliberate and is
covered by `model_policy_selftest.gd`. Fresh-clone usability is solved by
shipping `config/model-catalog.example.json`, not by loosening the rule.

## Models that cannot participate

**Reasoning-only models.** Some models return HTTP 200 with `content: ""` and
put the entire answer in `reasoning_content`. The arena deliberately refuses to
read `reasoning_content` (no chain-of-thought leaking into a live debate), so
these models never speak. They are reported explicitly:

```
[LMClient] X is a REASONING-ONLY responder: content empty,
           reasoning_content N chars. Not usable in a roster.
```

Observed on `deepseek-r1-distill-qwen-7b`. Pick a non-thinking model.

**Base / non-instruct checkpoints.** A continued-pretraining checkpoint has no
chat template and will not hold a turn. `tools/build_roster.gd` scores these
down, but if you select one by hand it will simply not answer.

**Tool-calling models.** Some models emit `tool_calls` instead of text even with
`tool_choice: "none"`. The client extracts text from the call arguments as a
fallback, which is a salvage, not a fix.

## Model swapping

Measured cold swaps are **18–38s** on this machine (`docs/BENCHMARK_8GB.md`).
That is inherent to loading weights from disk into a small VRAM budget, not a
defect. Consequences:

- A five-model roster swaps on every turn. Fewer distinct models is
  dramatically faster.
- The first load of a session is the slowest; the OS page cache makes later
  loads of the same weights ~8x quicker.
- Timeouts are sized for the **uncached** case on purpose. Do not lower them
  because one warm run looked fast.

## Cross-repo contracts

`cinematic_selftest.gd` and `scar_lattice_selftest.gd` compare Godot constants
against TypeScript files in a sibling repository that is not part of a
standalone clone. In this repo those checks **SKIP** with an explicit message.
Unverifiable is not the same as broken, but it does mean the contract is not
proven here.

## Platform

Windows-first. `tools/verify.cmd`, `tools/doctor.cmd` and `start_arena.cmd` are
batch files. The Godot self-tests and `tools/verify_configs.gd` are plain
GDScript and run on Linux — CI proves that on every push. FFmpeg clip recording
uses `gdigrab`, which is Windows-only.

## Recording

Clips are written as `.mkv`, not `.mp4`. MP4 only becomes playable when FFmpeg
writes its moov atom on a clean exit, and the recorder is stopped by killing the
process; a hard-killed MP4 leaves nothing usable. MKV finalises as it goes. The
recorder verifies the file exists and is non-empty before reporting success.
