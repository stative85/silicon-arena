# RERUN A/B/C — rerunning RUNTIME-MEMORY arms IDLE, CONTROL_WORKLOAD, RECOVERY_ONLY

**Static shift, ITEM 4. WRITTEN, NOT EXECUTED.** Every step below that touches
LM Studio, Godot, or the process table is outside the static shift's execution
allowlist by construction. Nothing in this document authorises a human to skip a
clearance, and reading it is not clearance.

**Provenance.** Rewritten from accepted evidence at HEAD. It does **not** derive
from `orphaned_RERUN_ABC_PROCEDURE.md`, which is quarantined as Q-1 in
`docs/results/QUARANTINE_REGISTER.md` for inheriting the refuted RM-1 as its
first precondition. That draft was not edited into this one; every precondition
here was re-established directly, and where I could execute a check I did.

Supersedes the sketch under "NEXT PERMITTED LIVE ACTION" in
`docs/NEXT_LIVE_RUN.md`, which has drifted — see §4.

Every precondition below carries its evidence class per `docs/CLAIM_TO_WITNESS.md`.

---

## 0. What this rerun is for, and what it cannot deliver

The four-arm RUNTIME-MEMORY experiment currently stands at:

| arm | backend-continuity verdict |
|---|---|
| `FULL_WINDOW` | **PASS** |
| `IDLE` | **UNKNOWN** |
| `CONTROL_WORKLOAD` | **UNKNOWN** |
| `RECOVERY_ONLY` | **UNKNOWN** |

The three UNKNOWNs are not failures and **must never be promoted to PASS**. They
are the verdict of a corrected witness that was frozen *before* trajectories were
read, applied to arms whose per-sample core-generation telemetry was never
persisted, against backends that no longer exist. The missing history cannot be
reconstructed; it can only be recollected.

**This rerun can deliver:** three arms whose continuity verdict is decidable.

**This rerun cannot deliver:** anything about the original arms. The old arms
stay UNKNOWN forever. A rerun is new data, not a retroactive repair.

---

## 1. Preconditions — the blocking list

Each is stated with what actually witnesses it. **P1–P3 are met at HEAD.**
P4–P6 are unmet or undecidable without a human.

### P1 — the harness persists per-sample core generation — **MET**

```text
EVIDENCE CLASS:  OBSERVED_SHAPE (code) + EXECUTED_WITNESS (it parses)
WITNESS:         grep -n "generation\|creation" tools/runtime_memory.gd
                 python tools/gd_parse_check.py tools/runtime_memory.gd
```

`_backend_probe()` asks the producer for pid, parent, creation time and command
line, assigns roles from structure, and stores `core_created` per sample
(`d6e06a0`). The harness refuses to start without a generation witness at arm
start, and counts `samples_missing_generation`. `backend_continuity.evaluate()`
returns `core_generation_unchanged = UNKNOWN` when `core_created` is absent —
the exact clause that made A/B/C undecidable — and it cannot silently pass.

> **A NOTE ON HOW THIS PRECONDITION WAS CHECKED.** My first grep for this
> telemetry used the field names I expected (`core_generation`, `start_time`)
> and returned nothing. On that evidence the precondition looked UNMET and this
> section was nearly written as a blocker. The field is `core_created`. A grep
> that returns nothing is evidence about the pattern, never about the code.
> This is RM-1's failure mode arriving at ITEM 4 through a different door, in
> the document written to correct RM-1.

### P2 — the arm artifacts are currently REFUSED, and that must FLIP — **MET (as a starting state)**

```text
EVIDENCE CLASS:  EXECUTED_WITNESS
WITNESS:         python tools/result_loader.py --check RUNTIME_MEMORY_IDLE.json
OBSERVED:        REFUSED
                 "declares no identity (none of experiment_id, artifact_kind,
                  block_id); anonymous evidence is refused"
                 "no eligibility fields; artifact cannot prove its status"
COULD-HAVE-FAILED: the loader admits self-describing artifacts; refusal here is
                   about these files, not a loader that refuses everything.
```

All four existing `RUNTIME_MEMORY_*.json` are pre-schema and anonymous. This
confirms by execution the previously-unchecked observation that they "appear
old-schema". **This refusal is the acceptance test.** After a correct rerun the
three new artifacts must be **ADMITTED** by the same command, unchanged. If they
are still refused, the rerun did not produce schema-compliant artifacts and its
data is not admissible — STOP, do not hand-edit the artifacts.

### P3 — the NO_CONTACT suite is green — **MET**

```text
EVIDENCE CLASS:  EXECUTED_WITNESS
WITNESS:         python tools/run_safe_tests.py
OBSERVED:        === 42 passed, 0 failed, 4 withheld ===
```

The 4 withheld are the 2 STATE_MUTATING and 2 CONTACT_REQUIRED suites. They stay
withheld until step 5 below, under clearance.

### P4 — LM Studio is in a known state — **UNMET, and cannot be self-cleared**

```text
EVIDENCE CLASS:  STATIC_INFERENCE — deliberately not executed
```

`recovery_tooth_selftest.gd` was run against the live backend on 2026-09-07 in
violation of a READ-ONLY boundary. It performs real unload/reload cycles and
temporary model eviction. Committed artifacts predating it are unaffected;
**current LM Studio internal runtime state was contaminated for future
measurement.**

I cannot verify the current state without contacting the runtime, which is
forbidden. The operator must establish a known starting state before arm 1, and
must record what that state was. Do not assume the contamination has aged out.

Residency validation here uses a **count map, not set membership** — LM Studio
can hold `qwen3.5-2b` and `qwen3.5-2b:2` simultaneously, and presence is not
enough when multiplicity exists (Law 5, Cardinality Is State).

### P5 — clearance for STATE_MUTATING execution — **UNMET by construction**

Three arms means three backend restarts, plus scheduled recoveries within
`RECOVERY_ONLY` and any arm that carries them. Under `run_safe_tests.py`
classification, STATE_MUTATING requires **clearance plus an attended human**.

Amendment 2 authorised *one specific restart* for RECOVERY-COUPLING. It is not a
standing licence and does not extend here.

### P6 — the comparability decision — **UNMET, science decision, HUMAN ONLY**

Decide **before** starting, and record the decision before any data exists:

> May the existing `FULL_WINDOW` PASS be compared against three arms collected
> under a different harness commit and corrected telemetry?

Options are (a) accept the asymmetry and state it as a limitation, or (b) rerun
all four for symmetric provenance. Arms differing in harness version is **a
limitation to state, not a covariate to adjust for** (Amendment 3).

Deciding this after seeing the new arms is a post-hoc criterion change and is
forbidden. If the answer is not obvious, that is a reason to preregister it, not
a reason to defer it until the data can influence it.

---

## 2. The procedure

Nothing here may run until P4, P5 and P6 are resolved by a human.

```text
STEP 0  RECORD INTENT
        Write the P6 decision and the expected arm order to
        docs/results/ BEFORE touching anything. Arm order is a limitation,
        never a covariate (Amendment 3); with three arms and no replication
        of position it is NOT estimable.

STEP 1  PRE-FLIGHT, offline
        python tools/run_safe_tests.py
        EXPECT: 42 passed, 0 failed, 4 withheld
        If the count differs from 42, do not shrug -- suites have been added
        since; confirm 0 failed and 4 withheld and update this line.

STEP 2  PRE-FLIGHT, the parse tooth
        python tools/gd_parse_check.py tools/runtime_memory.gd
        EXPECT: ok / 1 parsed, 0 failed
        This replaces reliance on runtime_memory_selftest.py's "PREFLIGHT
        GREEN", which is 41 regex checks over source as TEXT and certifies
        nothing executable (see CLAIM_TO_WITNESS). Run the regex preflight
        too -- it catches things the compiler will not -- but never treat it
        as evidence the harness runs.

STEP 3  PRE-FLIGHT, the witness
        python tools/backend_continuity.py --selftest
        EXPECT: WITNESS GREEN
        This is the witness frozen BEFORE trajectories were read. It is not
        to be modified during or after the run, for any reason, including
        it returning an inconvenient verdict.

STEP 4  ESTABLISH AND RECORD BACKEND STATE  [P4]
        Record the model residency COUNT MAP, not a set. Record core pid and
        core creation time before arm 1.

STEP 5  RUN  [REQUIRES CLEARANCE + ATTENDED HUMAN]
        python tools/runtime_memory_run.py --confirm-restarts \
            --arms IDLE CONTROL_WORKLOAD RECOVERY_ONLY

STEP 6  CONTINUITY VERDICT, before any trajectory is read
        python tools/backend_continuity.py --apply
        EXPECT: PASS for each rerun arm.
        UNKNOWN on any arm = the telemetry fix did not take. STOP.
        UNKNOWN IS NOT A SOFT PASS. It is not "probably fine". The arm is
        undecidable and stays undecidable.

STEP 7  ADMISSIBILITY
        python tools/result_loader.py --check <the three new artifacts>
        EXPECT: ADMITTED, where the old artifacts are REFUSED (P2).
        Still refused = not admissible. Do not hand-edit an artifact to get
        it admitted; that defeats the entire schema tooth.

STEP 8  ONLY NOW read trajectories, in the frozen 7-item order
        (EXPERIMENT_RUNTIME_MEMORY.md, Amendment 1)
```

**The ordering of steps 6, 7 and 8 is the scientific content of this procedure.**
Continuity and admissibility are adjudicated before anyone sees a trajectory. Any
run that reads trajectories first has forfeited the frozen-witness property, and
no discipline applied afterwards restores it.

---

## 3. STOP conditions

Stop, write a finding, and do not improvise:

1. Any P1–P6 unmet or unresolved at start.
2. Step 6 returns UNKNOWN for any arm.
3. Step 7 refuses any new artifact.
4. `RAM_FLOOR_EVENT` fires, as it did in RECOVERY-COUPLING Run 1 — that run is
   VOID/TERMINATED and its causal question remains **UNANSWERED**. Do not infer
   recovery coupling from it and do not attempt to rescue it.
5. The backend restarts at a moment no scheduled recovery accounts for.
6. Any impulse to adjust a threshold, floor, seed set, or acceptance criterion.
   Frozen: RAM floor 2048 MB, `ks=1.8`, `kh=20`, `n=3`, coherence criterion 0.2,
   coherence seeds 1..20. **If a criterion looks wrong: WRITE A FINDING. DO NOT
   FIX IT.**

A stopped run that produced nothing is a good outcome. A completed run whose
witnesses were bent to let it finish is worse than no run.

---

## 4. Defects in the superseded sketch

Recorded rather than silently corrected, because the sketch was followed once:

| # | defect |
|---|---|
| S-1 | Step 1 expects `8 passed, 0 failed, 2 skipped`. The suite now reports **42 passed, 0 failed, 4 withheld**. An operator following it exactly either halts on a precondition that can never be met again, or learns to disregard the expected output — the more dangerous outcome. |
| S-2 | Step 2 treats `runtime_memory_selftest.py` "PREFLIGHT GREEN, 41 checks" as a readiness gate. It is 41 regex matches over source text and certifies no executable behaviour. Step 2 above adds the compiler. |
| S-3 | Step 0 says "human clearance for FOUR LM Studio restarts (one per arm)" while the arm list has three entries. Three arms, three restarts, unless P6 resolves to rerunning all four. |
| S-4 | Step 4, "confirm no scientific runtime state is live", names no command and no artifact. Replaced by P4/STEP 4, which requires a recorded count map. |
| S-5 | The sketch names no witness for the P4 contamination from the 2026-09-07 boundary violation. |

S-1 and S-2 are the reason this document exists as more than a command list: a
precondition whose expected output can no longer occur trains the operator to
ignore preconditions.

---

## 5. What this document does not authorise

Executing any of it. Contacting LM Studio. Loading or unloading a model. Running
inference. Rerunning `FULL_WINDOW` without a P6 decision. Analysing the
quarantined qwen3.5 block. Promoting any UNKNOWN. Rescuing VOID data. Touching
PIT A or SWARM/METABOLISM. Modifying anything outside `silicon-arena-public`.
