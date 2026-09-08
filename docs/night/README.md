# The Night Supervisor

`tools/night_supervisor.py` is the loop that lives **outside** the model.

A coding agent is turn-bounded. Inside a turn it can behave like an autonomous
worker; when the turn ends, control returns to the human. "Keep going until the
queue is empty" is an instruction, not a mechanism. A background monitor does
not fix this either — a monitor is a diligent security camera with no legs. It
observes; it cannot decide, and it cannot re-invoke.

So continuation lives in a process the model does not control, and **stopping
requires a machine-readable reason**. That is ROBRUSTION Law 6 aimed at the
agent loop itself: *a boundary — or an obligation — that exists only as prose is
weaker than one enforced by the execution path.*

```
python tools/night_supervisor.py --dry-run                       # plan only, no agent
python tools/night_supervisor.py --objective docs/night/objective.json
python tools/night_supervisor.py --status                        # read current state
```

---

## The shape of one iteration

```
pre-flight   tree clean?  no-contact suite green?      -> else INTEGRITY_FAILURE, stop
issue        fresh nonce + snapshot of HEAD
invoke       claude -p <prompt>  (allowlisted tools only)
read receipt docs/night/status.json, bound to this invocation
post-flight  suite green again?  tree clean again?     -> else INTEGRITY_FAILURE, stop
progress     did HEAD move?                            -> else count an idle iteration
decide       CONTINUE -> loop;  anything else -> stop
```

The supervisor never repairs the repository to keep going, and never raises a
budget to keep going.

## Stop conditions

All fail closed. Only an explicit, verified `CONTINUE` keeps the loop alive.

| State | Meaning |
|---|---|
| `DONE` | Queue exhausted; the agent declared completion. |
| `BLOCKED` | The agent cannot proceed and said why. |
| `HUMAN_CLEARANCE_REQUIRED` | The next action needs runtime contact or a judgement that is not the agent's. |
| `INTEGRITY_FAILURE` | The repo or the tests are not in a verified state. Raised by the supervisor, not the agent. |
| *(missing / stale / unparseable / unrecognised status)* | Treated as `BLOCKED`. Never as `CONTINUE`. |

An unrecognised `state` string is refused rather than interpreted charitably.
No status file at all means "the agent wrote no receipt", which is a stop —
absence is never read as progress.

## Receipt binding

Each iteration the agent must write `docs/night/status.json`. The supervisor
does not trust it because it is recent; a fresh timestamp is not identity. The
receipt must describe **this invocation** and **the repository the supervisor
actually observed**, or it is refused (`read_status`, `tools/night_supervisor.py`).

| Field | Bound against | Why |
|---|---|---|
| `iteration_id` | a per-iteration `secrets.token_hex(8)` **nonce** | Without it, an older process could write the file late and still look current. |
| `iteration` | the loop counter | Catches a receipt from a different turn of the same run. |
| `objective_hash` | `sha256(objective)[:16]` | Proves the agent worked against the objective the supervisor loaded, not a stale or edited one. |
| `starting_commit` | `HEAD` observed *before* invocation | Anchors the claim to a known starting repo state. |
| `ending_commit` | `HEAD` observed *after* invocation | The agent cannot claim a commit the supervisor did not see. |
| `advanced_item` | required whenever `state` is `CONTINUE` | Progress is audit evidence, never a truth oracle: the agent must **name** the queue item it advanced. The supervisor records the claim and does not score it. |

Every one of these is a hard mismatch check. A `CONTINUE` that refers to some
other commit or some other objective is refused rather than believed.

## Anti-runaway caps

| Cap | Flag | Default |
|---|---|---|
| Iteration cap | `--max-iterations` | 12 |
| Wall-clock budget | `--max-minutes` | 240 |
| Spinning — consecutive iterations with no new commit | `--max-idle-iterations` | 2 |
| Per-invocation agent timeout | `--agent-timeout` | 1800 s |
| Unexpected dirty tree, before or after an iteration | — | always stops |
| No-contact suite red, before or after an iteration | — | always stops |

The budgets are read once, at start. Nothing in the loop extends them.

## The contact boundary

The night shift runs under **LM Studio READ-ONLY / DO-NOT-CONTACT**: no
restart, no unload/load, no inference, no experiment runs. The supervisor cannot
grant runtime clearance; only a human can.

Two mechanisms hold that, neither of them prose:

1. **Tests only via `tools/run_safe_tests.py`, with no arguments.** Its
   classification audit is itself fail-closed, so an *unclassified* test stops
   the loop just as a failing one does. The supervisor runs it before and after
   every iteration.
2. **The sub-agent's permissions are part of the boundary.** The agent is
   invoked with `--permission-mode acceptEdits` plus an explicit
   `AGENT_ALLOWED_TOOLS` allowlist: seven read/write `git` verbs and the exact
   string `Bash(python tools/run_safe_tests.py)`. That exactness is deliberate —
   the wildcard form `Bash(python tools/run_safe_tests.py:*)` would let the
   agent append a clearance flag and run the state-mutating suites the
   classified runner exists to withhold. `AGENT_DENIED_TOOLS` additionally names
   `lms`, `curl`, `godot`, `taskkill`, PowerShell, web access and `Agent`
   spawning; that list is redundant against the allowlist by design, so a future
   edit that widens the allowlist still cannot reach the runtime.

`--permission-mode bypassPermissions` is the obvious repair when an iteration
stalls on permissions, and it is **refused**. Under it, DO-NOT-CONTACT is prose
again, and an unattended agent at 3 a.m. could run `lms unload` or POST to the
backend with nothing in the way but a sentence in a prompt. The night shift
already produced one boundary violation that way. Anything the allowlist does
not name falls through to a permission prompt, and a prompt in a
non-interactive session is a refusal — fail-closed by construction.

## Where the audit trail is written

**The supervisor owns the audit trail.** Every prompt, every raw agent output,
every status receipt and every decision is written by the supervisor itself.
Depending on the agent to document the agent would be Law 6 wearing novelty
glasses.

```
docs/night/
├── objective.json                     the durable objective (queue, boundaries, stop_when)
├── objective_qualification.json       the tiny two-item objective used to qualify the loop
├── status.json                        the CURRENT iteration's receipt (overwritten each turn)
├── supervisor.log                     human-readable timeline across runs
└── runs/<YYYYmmdd_HHMMSS>/
    ├── objective_snapshot.json        what was actually loaded, hashed into objective_hash
    ├── supervisor_events.jsonl        one JSON record per supervisor decision
    ├── iteration_NNN_prompt.txt       the exact prompt sent
    ├── iteration_NNN_output.txt       the agent's raw output (last 4000 chars)
    └── iteration_NNN_status.json      the receipt as written, archived before the next turn
```

`status.json`, `supervisor.log` and `runs/` are **gitignored**
(`docs/night/.gitignore`). They are operational output of a run, not repository
content. Without that rule the supervisor creates its own audit trail and then
its own pre-flight dirty check refuses to start — which is exactly what happened
on the first qualification attempt. Archiving a run into git is a deliberate
act, not a side effect of running one.
