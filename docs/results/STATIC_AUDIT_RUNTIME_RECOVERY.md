# STATIC AUDIT — runtime-memory and recovery code paths

Static night shift, ITEM 1. **Finding only. Nothing was fixed in this pass.**
Separating finding from fixing is the point: a defect that is discovered and
repaired in the same breath is never counted, and the count is what tells you
whether the apparatus is trustworthy.

Method: read at HEAD (`fb71a50`), cross-read against git history and against the
artifacts on disk. No process was started, no test suite was invoked directly,
LM Studio was not contacted. Confirmations that would require executing Godot or
Python are marked **UNVERIFIED-BY-EXECUTION** and say so explicitly.

Paths audited:

| path | defects | severity of worst |
|---|---|---|
| `tools/runtime_memory.gd` | 9 | **BLOCKER** |
| `scripts/arena/recovery_action.gd` | 6 | HIGH |
| `scripts/arena/recovery_gate.gd` | 5 | HIGH |
| `tools/backend_continuity.py` | 6 | HIGH |

A fifth file, `tools/runtime_memory_selftest.py`, was not on the list but is
implicated by RM-1 and is reported under it, because the defect is only
dangerous *because* that file says GREEN.

---

## tools/runtime_memory.gd

### RM-1 — BLOCKER — the arm harness contains three unterminated string literals and cannot parse

Three `String.split()` calls have a **raw newline inside the string literal**
instead of the escape `"\n"`:

| line | function |
|---|---|
| 117–118 | `_backend_pids_cheap()` |
| 141–142 | `_backend_probe()` |
| 443–444 | `_lms_version()` |

Verified byte-for-byte with `cat -A`; each is a `"` at end of physical line, the
literal terminating on the next line. GDScript does not permit a newline inside
a `"`-delimited literal, so the script should fail to compile at load, and
`godot --headless --script tools/runtime_memory.gd` should never reach `_init()`.

The same corruption pattern (an escape expanded into the character it denotes)
also hit two line continuations, at 150 and 218 and 468, where a `\` was replaced
by a run of literal tabs. Those three are **harmless** — the expression collapsed
onto one physical line and remains valid — which is exactly why the newline cases
went unnoticed: the damage was mixed with damage that did not matter.

Note the contrast: `_lms_rss_mb()` at line 193 still has a correct `split("\n")`.
Three sites were mangled, one identical site was not.

**Failure scenario.** An operator follows the rerun procedure, runs
`godot --headless --path . --script tools/runtime_memory.gd -- --arm=IDLE`, and
gets a parse error before the first sample. No artifact is written. Under a
4-arm orchestrated sequence with backend restarts between arms, the restarts
still happen while every arm produces nothing — the machine is disturbed and no
data is collected.

**Provenance.** `git diff d6e06a0 704b999 -- tools/runtime_memory.gd` shows the
`_backend_pids_cheap` and `_lms_version` breakages entering at `704b999`
("Static review fixes: telemetry no longer distorts the workload it measures").
The `_backend_probe` breakage entered earlier, at `d6e06a0`.

**Why nobody caught it — and this is the actual finding.** The four arm artifacts
on disk (`docs/results/RUNTIME_MEMORY_*.json`) are **old-schema**: their samples
carry `backend_pids`, `residency_counts`, `lms_rss_mb`, `vram_*` and nothing
else. They have no `backend_core_created`, no `backend_probe_ok`, no
`backend_procs`, no `backend_probe_full`, and the documents have no
`experiment_id`, no `integrity_status`, no `git_commit`. Those fields were added
by `d6e06a0` and `704b999`. **Therefore no arm has ever been executed against the
current harness.** The corrupted code has never been run.

And `tools/runtime_memory_selftest.py` — the preflight that prints
`PREFLIGHT GREEN -- harness is built` — is pure `re.search` over the file *as
text*. Every one of its 30-odd checks asks whether a substring is present:
`"BACKEND_CORE_CHANGED" in arm`, `"--type=" in arm`,
`'"final_live_client"' in arm`. It proves the harness contains the right words.
It cannot distinguish a harness from a text file that mentions a harness.
**Nothing in this repository parses `tools/runtime_memory.gd`.** There is no
syntax gate, no `--check-only` load, no registered suite that imports it.

Status: **UNVERIFIED-BY-EXECUTION.** Proving the parse failure requires running
Godot, which this shift's allowlist forbids. The literals are confirmed present;
the compiler's reaction to them is inferred from the language specification.

### RM-2 — HIGH — cheap samples fabricate a generation witness they did not observe

`_sample()` (216–263). On 9 of every 10 samples the cheap `tasklist` probe runs,
which cannot read `CreationDate`. The record then writes:

```gdscript
"core_created": (_core_created if cheap.has(_core_pid) else ""),
```

— the **cached** value from arm start, stored into the sample as
`backend_core_created` with no flag distinguishing observed from assumed. The
only marker is `backend_probe_full`, a separate field that a downstream reader
must know to consult.

`_eligibility()` then counts `samples_missing_generation` as samples whose
`backend_core_created` is `""`. Cheap samples inherit a non-empty string, so they
never count as missing. The eligibility check that exists to guarantee a
generation witness is satisfied, for 90% of samples, by a value that was copied
rather than measured.

**Failure scenario.** The backend restarts and Windows reuses the core PID.
`cheap.has(_core_pid)` is true, so the cached `T0` is written into every cheap
sample. Nine of ten samples assert a generation that no longer exists. Only when
sample index ≡ 0 mod 10 does the full probe run and record the change. Between
those, up to ~18 s of samples carry a false continuity claim, and any consumer
reading `backend_core_created` per-sample — which is precisely what
`backend_continuity.py` clause 2 does — reads a fabricated constant.

### RM-3 — HIGH — VOID vs UNKNOWN is decided by counting reasons, not by their kind

`_eligibility()` (479–481):

```gdscript
var status := "QUALIFIED"
if not reasons.is_empty():
    status = "VOID" if reasons.size() > 1 else "UNKNOWN"
```

Severity is the **length of a list**. One `BACKEND_CORE_CHANGED` — a proven
backend restart mid-arm, the single most disqualifying event this apparatus
watches for — produces exactly one reason and is therefore classified `UNKNOWN`.
Two `BACKEND_PROBE_FAILED` entries, meaning powershell was slow twice, produce
two reasons and are classified `VOID`.

**Failure scenario.** An arm restarts its backend once, cleanly detected. The
artifact reports `integrity_status: "UNKNOWN"`. A later reader who is permitted
to treat UNKNOWN as "inconclusive, worth rerunning" rather than "destroyed"
draws the wrong conclusion about what happened to this arm.

This is a classification rule, not a preregistered threshold, but it is close
enough to one that **it is recorded here and not touched.** Changing it is a
science decision.

### RM-4 — HIGH — completion accounting has no epoch guard, so stale replies corrupt the next probe

`_run()` (327–332) connects `_bridge.completed` to a lambda that does
`_pending -= 1` unconditionally. `_one_window()` (367–384) resets
`_pending = POOL.size() - 1` and `_last.clear()` at the top of every probe, then
waits with a 60 s guard.

Nothing ties a completion to the probe that requested it. This is the exact
defect `main.gd` spends its whole epoch discipline preventing — `_alive(epoch,
name)`, "never capture agent dicts in lambdas" — and the arm harness reimplements
the bug.

**Failure scenario.** Probe *k* submits 2 requests; one stalls past the 60 s
guard; the loop moves on with `_pending == 1`. Probe *k+1* sets `_pending = 2` and
submits 2 more. The stalled reply from probe *k* now lands and decrements to 1;
one of the new replies decrements to 0; the loop exits believing both new
requests completed, while one is still in flight. `_completions` and
`_prompt_tokens` are credited to the wrong probe, and `_pending` can go negative
across further iterations, at which point `while _pending > 0` never blocks again
and the workload arm stops waiting for its own requests. Since "MB per 100
requests" is the primary dependent variable, a miscounted denominator is not
cosmetic.

### RM-5 — HIGH — no HTTPRequest timeout anywhere, so a stalled backend hangs the arm forever

`_http` and `_http_rec` are constructed (300–303) with no `timeout` set;
Godot's `HTTPRequest.timeout` defaults to `0`, meaning none. Every
`await http.request_completed` in `recovery_action.gd` is therefore unbounded.

`_do_recovery()` is launched **without `await`** (365) and the window's `rguard`
(388) gives up waiting after 120 s — but it does not cancel anything.
`_rec_running` stays `true` forever, and the abandoned coroutine is still parked
on `_http_rec.request_completed`.

**Failure scenario.** Window *w*'s recovery stalls on the liveness probe.
`rguard` expires; the window ends; window *w+1* triggers its own recovery, which
constructs a second `RecoveryAction` and issues a new request on **the same
`_http_rec` node**. When a single response finally arrives, both parked
coroutines resume from it. Two recovery witnesses are built from one HTTP
response, `_recoveries` is incremented twice, and `residency_epoch` is tracked on
two separate `RecoveryAction` instances so the "incremented exactly once"
clause is meaningless. `_do_recovery` also sets `_rec_running = false` from
whichever finishes, so the flag stops tracking anything real.

### RM-6 — MEDIUM — the artifact is truncated-then-rewritten once per window, with no atomic replace

`_write(false)` is called after every window (337). It opens the results file
with `FileAccess.WRITE`, which **truncates**, then serialises the entire
accumulated document. For a 40-window arm the artifact is destroyed and rebuilt
40 times, and it grows monotonically (every sample retained), so the last writes
are the largest and the exposure window is longest exactly when the most data is
at risk.

**Failure scenario.** The process is killed, the machine loses power, or RM-1's
parse failure is fixed and something else crashes mid-`store_string` at window
38. The artifact on disk is a truncated JSON fragment — not merely stale, but
unparseable — and the previous good full-artifact was already destroyed. The
write-to-temp-then-rename that would make this safe is absent.

### RM-7 — MEDIUM — the process exits 0 regardless of integrity status

`_write(true)` ends with `quit(0)` (514), unconditionally. An arm that recorded
`BACKEND_CORE_CHANGED`, computed `integrity_status: "VOID"`, and printed its
problems still reports success to its caller.

**Failure scenario.** `tools/runtime_memory_run.py` (or any operator running the
arms in sequence) checks the exit code between arms, sees 0, and proceeds to the
next arm and the next backend restart. The VOID verdict exists only inside a JSON
field that nothing on the control path reads.

### RM-8 — MEDIUM — `--windows` is not validated; a typo silently produces a two-sample arm

`_init()` (85–86) does `_windows = int(s.substr(10))`. GDScript's `int()` on a
non-numeric string yields `0`. There is no lower bound, no upper bound, and no
recording of a rejected value.

**Failure scenario.** `--windows=2O` (letter O) or `--windows=` gives
`_windows = 0`. `for w in 0` runs zero windows. The arm takes an `arm_start`
sample and a `final_live_client` sample, records zero problems, computes
`integrity_status: "QUALIFIED"` — because two samples with a good generation
witness satisfy every clause — and writes a fully-provenanced artifact declaring
`window_horizon: 0`. It looks like a clean arm.

### RM-9 — LOW — machine-specific absolute paths fail silently into empty provenance

`_lms_version()` calls `OS.execute(RA.LMS, ...)` where
`RA.LMS = "C:/Users/cleve/.lmstudio/bin/lms.exe"`. On any other machine, or after
any LM Studio relocation, `OS.execute` fails, `out` is empty, and the function
returns `""`. `_metadata()` then stores `runtime_version: ""` and no problem is
recorded.

**Failure scenario.** The arms are rerun on a second machine. Every artifact
carries `runtime_version: ""`. "Same runtime/version" is one of the ten
`FROZEN_PREFLIGHT` items, and the field that would evidence it is empty without
anything having failed. Same shape applies to `_health_hash()` returning `""`
when the file is missing, and to `_git_head()` returning `""`.

---

## scripts/arena/recovery_action.gd

### RA-1 — HIGH — the documented `known`-pool safeguard is inert on every production call site

`base_id()` (126–138) carries a long comment: *"THE SUFFIX IS ONLY STRIPPED WHEN
THE RESULT IS A KNOWN POOL MEMBER... An unrecognised numeric-colon id is left
intact so the gate reports it as foreign rather than quietly absorbing it."*

That protection lives behind `known.is_empty() or known.has(candidate)` — when
`known` is empty, the suffix **is** stripped unconditionally.

And `perform()` calls `residency_counts(http)` at lines 216, 233 and 248 with
**no `known` argument**. `RecoveryGate.sample()` calls
`RA.residency_counts_result(http)` with no `known` argument either. Both
production consumers pass the empty default, so the safeguard never engages on
any path that matters. The only caller that passes a pool is
`runtime_memory.gd:_sample()` (`RA.residency_counts(_http, POOL)`), which is
telemetry, not a gate.

**Failure scenario.** The pool one day contains a model whose canonical id ends
`:2` — a quantisation or revision tag. `base_id` strips it to a base that is not
resident. `RecoveryGate.classify` reports the real model as `DISAPPEARED` and the
phantom base as... nothing, because it was merged. Conversely, a genuine
duplicate instance `x:2` of a model *not* in `expected` is collapsed onto `x` and
counted as an extra instance of `x` rather than surfacing as `FOREIGN`. Either
way the cause reported in the artifact is wrong, and the comment above the
function asserts this cannot happen.

### RA-2 — HIGH — `perform()` never consults the `ok` flag that was added specifically so it could

`resident_set_result()` carries an explicit rationale for `ok` (68–80): a failed
read is not an empty pool, the two were conflated, and *"callers now fail closed
on it."*

`perform()` does not use it. All three residency reads go through the lossy
`residency_counts()` wrapper, whose own docstring says `{}` means *"EITHER a
failed read or an empty pool."*

The consequence at the mid-check (233–236) is direct: a transport failure yields
`mid = {}`, so `int(mid.get(target, 0)) == 0` is **true** and
`w["unload_verified"] = true` is written into the witness. The witness now
asserts a state transition that was never observed.

**Failure scenario.** With a non-empty neighbour set the arm is saved by
accident: `counts_match({}, want_absent)` is false, so `mid_n` is false, so
`neighbor_set_preserved` is false and the verdict is `RECOVERY_NOT_VERIFIED` —
but under the reason `"neighbour residency changed"`, which is a lie about what
happened. With **`neighbours == []`**, `want_absent` is `{}` and
`counts_match({}, {})` is **true**. Then: transport failure at mid →
`unload_verified = true`, `mid_n = true`; the read recovers at post → target
present → `reload_verified = true`, `post_n = true`,
`neighbor_set_preserved = true`; liveness passes; `residency_epoch` increments
and the verdict is **`RECOVERY_VALID` for a recovery whose unload was never
witnessed at all.** `runtime_memory.gd` always passes two neighbours so it does
not reach this, but nothing in `recovery_action.gd` requires a non-empty
neighbour set, and the contract is stated as unconditional.

### RA-3 — MEDIUM — the runner's exit code is discarded

`run.call(["unload", target])` (231) and
`run.call(["load", target, ...])` (246) both ignore the return value, even though
`real_runner()` is documented as *"Returns the process exit code."* The witness
has fields for the timestamps around each call but none for its result.

**Failure scenario.** `lms.exe` is missing (see RM-9 — the path is hardcoded to
one user's home directory). `OS.execute` returns `-1`, nothing is unloaded, the
absence check fails, and the witness reports `"target never became absent"` — an
eviction-failure story for what is actually a missing-binary story. The operator
debugs the runtime instead of the path.

### RA-4 — MEDIUM — `ensure_loaded()` bypasses the injected runner, so it is unsabotageable

`perform()` takes a `runner: Callable` precisely so the self-test can suppress an
unload without the production file containing a switch — a good design, stated
in the header as *"NO SABOTAGE AFFORDANCES EXIST IN THIS FILE."*

`ensure_loaded()` (275–294) then calls `real_runner(...)` directly at line 291.
It cannot be driven by a test. Its two most interesting branches — fail-closed on
an unreadable pool, and refuse-on-duplicate when `have > 1` — are reachable in
tests, but the load path itself is not, so nothing can prove `ensure_loaded` does
not double-load. Flagged for ITEM 6 as a tooth asserted but not proven to bite.

### RA-5 — LOW — `is_valid()` re-derivation is narrower than the stated contract

The header contract lists six clauses. `is_valid()` (299–305) checks five plus
the epoch, omitting `pre_neighbours_present` and `recovery_attempted`. Re-checking
a stored witness therefore applies a weaker rule than the one `perform()` applied
live. In practice `neighbor_set_preserved` covers the mid and post neighbour
state, so the gap is small — but the two rules are not the same rule, and the
docstring presents them as one.

### RA-6 — LOW — `liveness()` accepts any HTTP 200

`liveness()` (180–190) returns `int(res[1]) == 200`. Deliberately trivial, and
the comment says so. Recorded only because a 200 carrying an error body, or a
200 from a proxy, satisfies it. Not a defect against the stated contract.

---

## scripts/arena/recovery_gate.gd

### RG-1 — HIGH — `begin()` does not clear `flex_model`, so a scheduled-absence relaxation leaks into later windows

The comment at 42–47 states the relaxation *"is set by the executor around its
own scheduled recovery and cleared immediately afterwards"* and that
*"the relaxation cannot be applied retroactively to excuse anything."*

`begin()` (53–57) resets `window_id`, `expected`, `offences` and `first_offence`.
It does **not** reset `flex_model`. The invariant depends entirely on the
executor's discipline, and the one place that could enforce it declines to.

**Failure scenario.** The executor sets `flex_model = "qwen3.5-2b"`, the recovery
throws or returns on an early error path before the clearing line, and the next
`begin()` starts a **control** window with the relaxation still armed. Every
sample in that window treats `qwen3.5-2b` count 0 as acceptable. A genuine
eviction in a control window is recorded as `CLEAN`. The artifact does record
`flex_model` per sample, so the damage is *forensically recoverable* — but the
window's `void` verdict, which is what anyone actually reads, is wrong.

### RG-2 — HIGH — the RAM floor is only evaluated when nothing else is wrong

`sample()` (112):

```gdscript
if reason == OK and free_mb > 0.0 and free_mb < HOST_FLOOR_MB:
    reason = RAM_FLOOR
```

The 2048 MB floor is checked **only if the count vector is already clean**. A
window that is both `DUPLICATE` and below the memory floor records only
`DUPLICATE`.

**Failure scenario.** Memory pressure causes a duplicate instance load to push
the host under the floor. The gate reports `UNEXPECTED_DUPLICATE`. The RAM floor
event — the thing that would tell you the host, not the runtime, is the cause —
never appears in `offences` for that sample, so a later analyst counting RAM
floor events undercounts them exactly in the windows where they mattered most.
The floor value (2048) is frozen and is not touched; the **masking** is the
defect.

### RG-3 — HIGH — the RAM floor fails open when memory info is unavailable

Same line: `free_mb > 0.0`. If `OS.get_memory_info()` returns no `free` key or
zero — an unsupported platform, or a failed query — `free_mb` is `0.0`, the guard
is false, and the floor check is **skipped silently**. Zero free memory, read
literally, is the most severe possible floor violation, and it is the one input
that disables the check.

Every other failure surface in these files is documented as failing closed
(`resident_set_result`, `_backend_probe`, `ensure_loaded`). This one fails open,
and nothing records that it was skipped.

### RG-4 — MEDIUM — a misspelled `flex_model` degrades silently

`classify()` compares `k == flex` while iterating `want`. If `flex` names a model
that is not a key of `want` — a typo, a base-id mismatch, an instance-suffixed id
— no branch is taken, no error is raised, and the relaxation simply does nothing.
The executor believes it declared a scheduled absence; the gate voids the window
on the target's legitimate disappearance.

Combined with RA-1: if the executor passes an instance id and `expected` holds
base ids, this is not a hypothetical typo but a systematic mismatch.

### RG-5 — LOW — `offences` is unbounded

Every non-OK sample appends a full dictionary including `counts` and `expected`.
Over a long run with a persistent contamination this grows without limit and is
serialised in full by `envelope()`. `first_offence` is what determines the
verdict; the tail is diagnostic only.

---

## tools/backend_continuity.py

### BC-1 — HIGH — the retrospective generation check does not implement the precondition it documents

`apply_to_arms()` (228–237). The comment states:

> if the live core was created BEFORE this arm's first sample and is still the
> same pid, it persisted across the whole arm and its generation cannot have
> changed.

The code does not compare `created` to anything:

```python
if cp is not None and live.get(cp):
    created = live[cp]["created"]
    s_eval = [dict(x, core_created=created) for x in s]
```

It stamps the live creation time onto **every** sample, then hands them to
`evaluate()`, whose clause 2 asks `len({s.get("core_created") for s in samples}) == 1`
— which is now true **by construction**, because the code just made it true.
Clause 2 cannot fail after this transformation.

**Failure scenario.** An arm ran, the backend restarted mid-arm, and by PID reuse
the live core happens to hold a pid that appears in every sample's
`backend_pids`. `cp` is set, the live `created` — which is *after* the restart,
i.e. after the arm's first sample — is stamped onto all samples, clause 2 returns
PASS, and the arm is reported as generation-continuous. The stated guard, the
temporal comparison, is the only thing that would have caught this, and it does
not exist. The written argument is sound; the code is not the written argument.

### BC-2 — HIGH — an unobserved generation is scored as a changed generation

`evaluate()` clause 2 tests set-cardinality over `core_created` values. It treats
`""` as an ordinary value.

Per RM-2, `runtime_memory.gd` writes `""` for `backend_core_created` whenever a
cheap probe cannot see the cached core pid. So a run mixing full samples
(`"T0"`) with cheap samples that lost sight of the pid (`""`) yields
`{"T0", ""}`, cardinality 2, and clause 2 returns **FAIL** — "core generation
changed" — for what is a *gap in observation*, not a change.

This is precisely the conflation the module docstring claims to have fixed on
the PID-set side. `UNKNOWN` exists in this file as a first-class verdict and is
the correct answer here. It is not reachable for this case.

### BC-3 — MEDIUM — `PASS_BY_RESTART_EXCLUSION` rolls up as a pass

`evaluate()` (97–98) deliberately emits a fourth clause value, described in the
comment as *"a weaker, restart-exclusion form of the clause... labelled as such
rather than as a pass."* The roll-up (123–129) is:

```python
if FAIL in vals: ... elif UNKNOWN in vals: ... else: PASS
```

`PASS_BY_RESTART_EXCLUSION` is neither, so it falls through to `PASS`. Today this
is masked: the branch that emits it is `core_pid is None`, which also forces
clause 2 to `UNKNOWN`, so the arm verdict is `UNKNOWN` anyway. The label survives
only by accident of a sibling clause.

**Failure scenario.** Anyone adds a fifth clause value, or makes clause 2
resolvable without a core pid, and a deliberately-weakened clause silently
becomes a full PASS. A roll-up whose default for an unrecognised value is "pass"
is fail-open by construction.

### BC-4 — MEDIUM — `churn <= recoveries * 2` and `0 < churn` are unstated acceptance criteria

Clause 4 (116–121): with recoveries, `PASS if 0 < churn <= recoveries * 2`. The
factor `2` appears nowhere in the docstring's four-clause contract, which says
only *"worker churn is attributable only to scheduled recoveries."* And
`0 < churn` makes **zero churn a FAIL** when recoveries occurred.

**Failure scenario.** The cheap probe (RM-2) samples every 2 s and the full probe
every ~18 s. A fast unload/reload that lands between two samples produces a
recovery with no observed churn. Clause 4 returns FAIL and the arm is reported
non-continuous because the apparatus blinked, not because the backend did.

Recorded, **not changed**. Whether these are the right numbers is a science
decision and is not this shift's to make.

### BC-5 — MEDIUM — artifacts are read with hard indexing and no schema check

`apply_to_arms()` does `d["samples"]`, `d["problems"]`,
`x["backend_pids"]`; `evaluate()` does `s["backend_pids"]`. Nothing checks
`experiment_id`, `arm`, or a schema version. A file at the expected path that is
not what it claims to be raises `KeyError` — a stack trace, not a refusal.

This is directly relevant to ITEM 2: the four artifacts on disk **are** an older
schema than the current writer emits, so a producer/consumer version skew is not
hypothetical here, it is the present state.

### BC-6 — LOW — `--apply` reaches the live process table

`live_process_roles()` shells out to powershell and enumerates
`LM Studio.exe`. This is read-only and does not touch the server, but it *is*
runtime contact by any reasonable reading. `backend_continuity.py` is registered
`NO_CONTACT` in `tools/run_safe_tests.py` with `args: ["--selftest"]`, and the
`--selftest` path genuinely touches nothing.

The classification is **correct as invoked** and the static marker scan does not
fire (no `lms.exe`, no `HTTPRequest`, no `127.0.0.1:1234` — the contact is
`subprocess.run(["powershell", ...])`, which no marker matches). But the
classification is a property of the *invocation*, not of the file, and the
registry records it against the file. Carried forward to ITEM 5.

Also minor, same file: `json.load(open(...))` and `json.dump(..., open(...))`
leak file handles.

---

## What this audit did not cover

- `tools/result_loader.py` — ITEM 3's subject, deliberately left alone here.
- `tools/runtime_memory_run.py` (the orchestrator) — not on ITEM 1's list. It is
  the file that owns backend restarts and is the natural next audit target.
- `tools/recovery_window.gd` (the executor) — the only place RG-1's
  set-and-clear discipline for `flex_model` can be confirmed or refuted. RG-1 is
  reported as a missing enforcement in `recovery_gate.gd` regardless of what the
  executor does, but whether it is *live* was not established.
- Any dynamic confirmation of anything. Every finding above is static.

## Consequence for the queue

RM-1 blocks ITEM 4. A rerun procedure for the RUNTIME-MEMORY arms cannot be
written as a working procedure while the harness does not parse; the procedure
will have to name RM-1 as a precondition and stop there. Fixing RM-1 is a code
change and belongs to a later item, not to ITEM 1.
