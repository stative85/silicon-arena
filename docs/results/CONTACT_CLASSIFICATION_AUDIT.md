# CONTACT CLASSIFICATION AUDIT

**Static shift, ITEM 5.** Every suite registered in `tools/run_safe_tests.py`
justified against what the file actually does. 46 suites audited. No LM Studio
contact, no inference, no arm run.

**Result: no misclassification found in the dangerous direction.** Three
structural findings are recorded (§4). Per the item's rule — *misclassification
found = fix the classification, never the boundary* — nothing was reclassified,
because nothing needed it, and no boundary was touched.

**Method.** The audit deliberately does **not** reuse only the runner's own four
contact markers. A detector audited with its own lens can only confirm itself.
Ten broader probes were run over comment-stripped, docstring-stripped source:

```text
bridge  http  lms  kill  exec  net_any  sleep  write_repo  godot_spawn  env_model
```

Hits are **evidence, not verdicts**. 17 NO_CONTACT suites showed at least one
hit; all 17 are justified below, individually, by reading the hit in context.

---

## 1. Non-NO_CONTACT suites — is the restriction still warranted?

The dangerous direction for these is the *opposite* one: a suite held back that
does not need to be. Held suites cost coverage, so each is re-justified.

| suite | class | evidence | verdict |
|---|---|---|---|
| `recovery_tooth_selftest` | STATE_MUTATING | real unload/reload cycles, liveness inference, temporary model eviction | **CORRECT.** This is the suite that caused the 2026-09-07 boundary violation. Classification stands. |
| `gate4_sabotage` | STATE_MUTATING | `lms`, `exec`, `godot_spawn`, `sleep`, `write_repo` — the densest contact profile of any suite | **CORRECT.** Drives the runtime directly. |
| `bridge_selftest` | CONTACT_REQUIRED | `inference_bridge`, HTTP, model names, 623 lines | **CORRECT.** Found by the original static contact scan. |
| `entrypoint_parity_selftest` | CONTACT_REQUIRED | HTTP + `net_any` + spawns Godot | **CORRECT.** Compares live entrypoints. |

No held suite is over-restricted. Nothing is released.

---

## 2. NO_CONTACT suites with probe hits — 17 justifications

### 2.1 The one that can genuinely reach the process table

**`backend_continuity` — `exec`, `write_repo` — JUSTIFIED BY EXECUTION**

`live_process_roles()` (line 50) shells out to PowerShell and enumerates the
live process table. That is real contact with machine state. It is reachable
from `apply_to_arms()` (line 270) — **not** from `selftest()`, and the suite is
registered with `args: ["--selftest"]`.

That is a structural argument, so it was put to execution rather than trusted:

```text
WITNESS: replace live_process_roles with a tripwire that raises, run selftest()
OBSERVED: selftest rc=0, WITNESS GREEN -- the tripwire never fired
CONTROL:  calling the tripwire directly raises
          "TRIPWIRE: live_process_roles() was called"
EVIDENCE CLASS: EXECUTED_WITNESS
COULD-HAVE-FAILED: yes -- the tripwire is proven able to fire, so its silence
                   during the suite is informative rather than decorative.
```

**Verdict: NO_CONTACT correct for the registered invocation.** See finding F-3:
the classification is a property of `(file, args)`, and the registry records
that pair while the marker scan reads the whole file.

### 2.2 Forbidden tokens that appear because the suite forbids them

A scanner necessarily contains the pattern it scans for. Two suites are in this
class; only one has a recorded allowance.

| suite | hit | context | verdict |
|---|---|---|---|
| `runtime_memory_selftest` | `lms`, `kill` | declares `taskkill` as a FORBIDDEN pattern it scans the arm harness for | **JUSTIFIED**, and already carries an explicit `marker_allowance` in the registry — a documented allowance, never a silent exemption |
| `night_supervisor_selftest` | `net_any`, `godot_spawn` | line 161: `for w in ("lms", "curl", "godot", "PowerShell")` — the assertion that **no allowlist entry can reach the runtime** | **JUSTIFIED.** The tokens appear inside the test that forbids them. Trips my broader probe; does not trip the runner's narrower markers. See F-2. |

### 2.3 Hits that are strings, labels, or explicit disabling

| suite | hit | actual context | verdict |
|---|---|---|---|
| `cinematic_selftest` | `net_any` | `bridge.serve_websocket = false` ×4 — the suite explicitly **turns networking off** | JUSTIFIED — a hit that is evidence of *more* isolation, not less |
| `detector_audit_selftest` | `net_any` | `g2.note_transport("socket died", 10)` — a string label in a synthetic event | JUSTIFIED |
| `model_policy_selftest` | `godot_spawn` | `print("=== model policy (Godot request path) ===")` — a banner | JUSTIFIED |
| `scar_lattice_selftest` | `godot_spawn` | the literal `"godot_event_authority"` in an assertion | JUSTIFIED |
| `offline_selftest` | `http` | `const DEAD_URL := "http://127.0.0.1:9"` — port 9 is discard, deliberately dead | JUSTIFIED, **with a caveat** — see F-1 |

`offline_selftest` is the only NO_CONTACT suite that opens a socket at all. It
addresses a deliberately dead local port to prove offline behaviour, never the
runtime at `:1234`, and it is the legacy aggregate runner. The classification
holds. What it exposes about the runner's marker set is F-1.

### 2.4 `exec` that is git or the compiler, never the runtime

| suite | hit | context | verdict |
|---|---|---|---|
| `qwen_fossil_admissibility` | `exec` | `subprocess.run(["git", "log"...])`, `["git", "show"...]` — reads repo history | JUSTIFIED |
| `gd_parse_check` | `exec`, `godot_spawn` | spawns Godot `--check-only`; the fourth control runs one generated throwaway script in a temp dir | JUSTIFIED, and the caveat is written into the registry note rather than omitted. Its own fourth control proves `--check-only` does not execute what it inspects. No repo `.gd` is ever executed. |

### 2.5 `env_model` — model names in fixtures and prose

Nine suites hit only `env_model` (`qwen|llama|mistral|gemma`): `artifact_schema`,
`failure_path_selftest`, `pit_a_selftest`, `recovery_probe_selftest`,
`result_loader`, `speech_clean_selftest`, `recovery_schedule` (+`write_repo`),
plus `cinematic_selftest` and `qwen_fossil_admissibility` covered above.

A model **name** is a string in a fixture or a document identifier. It is not a
model **load**. This probe was included precisely because it produces false
positives — a probe that only ever fires on real contact cannot tell you whether
your reading of "contact" is too narrow. **All JUSTIFIED.**

`recovery_schedule`'s `write_repo` hit is plan verification writing under
`docs/results/`; `night_supervisor_selftest` and `backend_continuity` write only
to `tempfile.mkdtemp()`.

---

## 3. NO_CONTACT suites with zero probe hits — 25

Clean on all ten probes. Pure-logic suites over synthetic data:

```text
async_b_witness            async_harness_selftest     async_runner_witness_selftest
async_runtime_selftest     async_step_selftest        async_world_selftest
coherence_selftest         compat_selftest            compute_arbiter_selftest
contention_selftest        dispute_selftest           embed_router_selftest
gonzo_recall_selftest      metabolism_join_selftest   pit_fuzz_selftest
presentation_selftest      source_measure_selftest    sse_parser_selftest
swarm_bid_selftest         swarm_request_selftest     swarm_resolver_selftest
targeting_selftest         topic_arc_selftest         turn_order_selftest
vram_selftest
```

**Absence of a marker is evidence, not proof** — the runner says so itself. A
suite could reach the runtime through an indirection none of the ten probes
name. These 25 are *unremarkable*, which is a weaker statement than *proven
isolated*, and this audit does not upgrade them.

`vram_selftest` was read specifically for that reason, since VRAM reporting is a
plausible route to the runtime. It operates on synthetic figures.

---

## 4. Findings

### F-1 — the runner's `http` marker is pinned to one port

```text
EVIDENCE CLASS:  OBSERVED_SHAPE + EXECUTED_WITNESS (the broader probe found
                 a socket the runner's marker does not match)
SEVERITY:        MEDIUM -- a gap in the dangerous direction
STATUS:          RECORDED, NOT FIXED
```

The runner's marker is:

```python
"http": r"HTTPRequest|127[.]0[.]0[.]1:1234|http://localhost:1234"
```

A NO_CONTACT suite addressing the runtime on any other port, host, or via an
`HTTPClient`/`StreamPeerTCP` path would not be flagged. `offline_selftest`
demonstrates the gap benignly: it holds a live URL constant the runner's scan
does not see. Nothing malicious was found — but the scan's silence over the
other 45 suites is weaker evidence than it appears.

**Recommendation (not applied):** widen to `HTTPClient`, `StreamPeerTCP`, and
`127.0.0.1|localhost` on any port. Widening a detector refuses *more*, which is
the safe direction. It is still a change to a boundary tooth mid-queue, and this
item's rule is to fix classifications, never boundaries. **Left to the human.**

### F-2 — `marker_allowance` is applied inconsistently

```text
EVIDENCE CLASS:  OBSERVED_SHAPE
SEVERITY:        LOW
STATUS:          RECORDED, NOT FIXED
```

`runtime_memory_selftest` carries an explicit documented allowance for naming
`taskkill`. `night_supervisor_selftest` names `lms`, `curl`, `godot` and
`PowerShell` in the assertion that forbids them, and needs no allowance **only
because the runner's markers are narrow enough to miss them**. If F-1 is applied,
this suite will start tripping the audit and will need an allowance of its own.
The two findings are coupled; fix them together or not at all.

### F-3 — classification is a property of `(file, args)`, not of a file

```text
EVIDENCE CLASS:  EXECUTED_WITNESS (the backend_continuity tripwire)
SEVERITY:        MEDIUM -- structural
STATUS:          RECORDED, NOT FIXED
```

`backend_continuity.py` is NO_CONTACT as `--selftest` and reads the live process
table as `--apply`. The registry records the invocation; the marker scan reads
the whole file. Both are correct in their own terms, and the *reason* the
classification is safe — that the contacting path is unreachable from the
registered arguments — is currently a fact about the code, not a fact the
registry states or the audit enforces.

Nothing exploits this today. It is written down because the next person to add
`--apply` to a registry entry, or to make a contacting path reachable from
`selftest()`, will not be warned by any tooth.

**Recommendation (not applied):** record per-entry *why the registered
invocation cannot reach the contacting path*, and prefer a tripwire witness like
§2.1 over a reading of the call graph.

---

## 5. What this audit did not do

- It did not execute CONTACT_REQUIRED or STATE_MUTATING suites.
- It did not contact LM Studio, load or unload a model, or run inference.
- It did not reclassify any suite, because no misclassification was found.
- It did not change `CONTACT_MARKERS`, `DISCOVERY_EXEMPT`, or any boundary.
- It did not prove the 25 clean suites isolated — only unremarkable under ten
  probes.

Suite state at the time of audit: **42 passed, 0 failed, 4 withheld.**
