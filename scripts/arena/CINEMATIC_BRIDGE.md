# Cinematic Bridge — Silicon Arena ⇄ Ghostloop

Wires the Godot arena to the `extinct_os` cinematic engines so a live debate
drives real trailer-grade visuals instead of the two projects being unrelated.

## The contract

One event type, versioned, defined **twice on purpose**:

| Side | File |
|---|---|
| TypeScript (authority) | `extinct_os/src/events/schema.ts` |
| Godot (mirror) | `silicon_arena/scripts/arena/cinematic_bridge.gd` |

The tables (`DEFAULT_PRIORITY`, `DEFAULT_DURATION`, `EVENT_TYPES`) are mirrored
rather than derived, because the two processes ship separately. **Drift is
caught by the self-test, which parses the actual `.ts` file and compares.**

## Data flow

```
main.gd hook  ->  CinematicBridge.emit_event()
                     |
                     +--> user://cinematic/<match_id>.jsonl   (replayable fixture)
                     +--> ws://127.0.0.1:8971                 (live overlay)
                                    |
                     ArenaLiveFeed.ingestLine()  (src/bridge/liveFeed.ts)
                                    |
                     validateEvent -> CinematicEventQueue
                                    |
                     EVENT_ENGINE[type] -> engine.create() -> frames
```

## Hooks in main.gd

| Arena moment | Event | Site |
|---|---|---|
| Reply lands | `AGENT_SPEAK` | `_on_reply` |
| Request failed / timed out | `MODEL_ERROR` | `_on_reply` failure branch |
| Doom crosses a quarter | `DOOM_STAGE` | `_on_reply` doom block |
| Influence lead changes | `CROWN_TRANSFER` | `_update_crown_status` |
| Agent falls far behind | `DESPERATION` | `_update_desperation_status` |
| Beef cinematic fires | `BETRAYAL` | `_trigger_beef_cinematic` |
| Echo chamber detected | `ALLIANCE_FORMED` | `_on_echo_chamber_detected` |
| Doom meter full | `MATCH_END` | `_trigger_silent_cascade` |
| Preset/roster load | `MODEL_LOADED` ×N + `ROUND_START` | `_load_preset` |

`DOOM_STAGE` fires only on a quarter-crossing (`_cine_doom_stage`). The meter
moves on nearly every reply; an event per tick would own the overlay and say
nothing.

## Hard rules

- **The feed is a spectator, never a participant.** Nothing in
  `cinematic_bridge.gd` may raise, block, or slow a turn. Every sink fails
  independently: no overlay running is the normal case, not an error.
- **Both sinks degrade alone.** Port busy → disk log continues. Disk unwritable
  → WebSocket continues.
- **The disk log is flushed per event**, so a crashed arena still leaves a
  replayable record up to the crash.
- **Seeds are deterministic**: `match_seed ^ (ordinal * 0x9E3779B1)`. The same
  match replays to the same frames on any machine.
- **Titles are titles.** `MAX_TITLE_CHARS = 20` in `schema.ts`. These engines
  render headlines, not subtitles — a 42-character quote renders as an
  unreadable smear (found by looking at a storyboard, not by any passing test).

## Commands

```bash
# the whole gate, from extinct_os/
npm run gate        # tsc + verify + engine smoke + regression lock
npm run livetest    # requires cinematic_live_server.gd running

# contract + robustness self-test (161 checks; exits 2 on drift)
Godot_v4.6-stable_win64_console.exe --headless --path . \
    --script scripts/arena/cinematic_selftest.gd

# regenerate the synthetic match fixture
Godot_v4.6-stable_win64_console.exe --headless --path . \
    --script scripts/arena/cinematic_demo_match.gd

# replay any match log into a storyboard PNG  (from extinct_os/)
npx tsx tools/replayEvents.ts "<path to match-*.jsonl>" --out _replay_match
# -> tools/out/_replay_match.png
```

**Re-run the self-test after touching either side of the contract.** It has
been checked for falsification: injecting a 100 ms drift into one duration
makes it fail with `duration[BETRAYAL] TS=3000 GD=3100`.

## Test seam

`CinematicBridge.clock_override_ms` (default `-1` = use the real engine clock).
Fixture generators set it so a synthetic match has realistic pacing; without it
every event stamps at the same tick and the queue correctly drops the burst as
spam.

## Schema versioning

`EVENT_SCHEMA_VERSION` is MAJOR.MINOR and the split is enforced, not decorative
(`checkCompatibility` in `schema.ts`):

- **MINOR** bump = additive only. New optional field, new event type, new tag.
  An older reader still works; it ignores what it does not know. Accepted with
  a `degraded` warning.
- **MAJOR** bump = breaking. A field removed, renamed, retyped, or a
  priority/duration band redefined. **Refused outright** — `validateEvent`
  returns `ok:false` and the payload is never rendered. Silently showing the
  wrong effect for the wrong duration is worse than a visible refusal.

The Godot mirror is `SCHEMA_VERSION` in `cinematic_bridge.gd`; the self-test
fails if the two drift.

## The freeze — `cinematic-pipeline-v1.0.0`

Three layers, each protecting something different:

1. **Locked fixture + regression suite** — behaviour and routing.
   `extinct_os/fixtures/cinematic-v1/` is immutable input; `expected.json` is
   the lock. 270 checks over event order, engine routing, headlines, queue
   admission, per-shot ink ranges, title-band legibility, and perceptual
   hashes. **Exact PNG bytes are deliberately not locked** — fonts and
   rasterization differ across machines, and a suite that cries wolf gets
   ignored. Tolerances: ink +/-3% absolute, dHash +/-8 bits of 64.
2. **Schema version + compatibility enforcement** — see above.
3. **Annotated git tag** — exact recovery point. Repo root is `Downloads/CLI`
   with an allow-list `.gitignore` (that directory is a scratch folder holding
   ~136 unrelated items, including third-party installers).

Falsification-checked, both layers:
- Injecting a 100 ms duration drift fails the Godot self-test:
  `duration[BETRAYAL] TS=3000 GD=3100`, exit 2.
- Rerouting `BETRAYAL: shatter -> gaussian` fails the regression lock on
  routing *and* perceptual hash (distance 18 > 8), exit 1.

Re-locking is a deliberate act, never a fix for a red test:
`npm run lock:update` — after looking at the storyboard.

## Status

Done: schema parity and version enforcement, both sinks, all nine hooks, live
feed client with backoff and match-change reset, `ArenaLiveFeed` mounted in
`App.tsx` (ARENA FEED panel, shared queue injection), replay tool, storyboard,
self-test, fixture generator, live socket test, locked regression suite.

Live transport is proven over a real socket by `npm run livetest` against
`cinematic_live_server.gd`: 14/14 events, in order, 0 malformed.

**Unconfirmed by eye:** nobody has watched the React overlay react in a browser.
Run `extinct_os/live_arena_demo.cmd`, open localhost:3000, click CONNECT ARENA.
The Godot side holds 6 s for a client before starting the match.
