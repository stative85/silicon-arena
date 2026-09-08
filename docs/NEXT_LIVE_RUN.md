# NEXT LIVE RUN

Written during the night shift of 2026-09-07. **Brought current 2026-09-08**
after the static shift (run `20260908_081127`) and the post-run review. No live
action was taken and none is authorised by this document. It exists so the next
operator does not have to reconstruct the state from commit messages.

**Read `docs/CLAIM_TO_WITNESS.md` first.** This shift produced a false BLOCKER
with complete and accurate supporting evidence. Every claim below therefore
carries its evidence class, and "well documented" is not one of them.

**RUNTIME-MEMORY has NOT identified a mechanism.** Nothing below should be read
as a finding about why the runtime accumulates memory.

---

## ESTABLISHED — measured facts

**RECOVERY-COUPLING Run 1** (`RC_RUN1_VOID.md`) — VOID / TERMINATED on repeated
`RAM_FLOOR_EVENT`. 41 of 60 windows persisted before termination: 23 CLEAN, 18
VOID, the voids concentrated in the lfm2.5 rotation block and released at the
rotation boundary. Both conditions hit equally, 9 TREATMENT and 9 CONTROL.
The causal question is **unanswered**.

**The qwen3.5 block** — 20 windows, 10 T / 10 C, zero voids, complete and clean.
**QUARANTINED.** `causal_evidence_eligible` is permanently false. A weaker
`diagnostic_sensitivity_eligible` status is earnable only under the nine-point
criterion frozen at `b49a58e`, whose ninth condition is enforced by git
chronology.

**RUNTIME-MEMORY** — all four arms completed 40 windows each. Start-state
witnesses were comparable on every pre-existing boundary: floor cleared, counts
1/1/1, health surface `14536bd0e92f16ba`, runtime `lms CLI commit df81c60`,
start RSS 5,471–5,514 MB, start free 15,526–16,652 MB.

**Backend continuity, corrected witness** (`RM_BACKEND_CONTINUITY.json`):

```text
FULL_WINDOW       PASS      core 20924 identified, generation verified
RECOVERY_ONLY     UNKNOWN   backend gone, generation unrecoverable
CONTROL_WORKLOAD  UNKNOWN   same
IDLE              UNKNOWN   same
```

**The arm harness parses** (2026-09-08, EXECUTED_WITNESS) —
`python tools/gd_parse_check.py tools/runtime_memory.gd` -> `1 parsed, 0
failed`. This supersedes the static audit's RM-1 BLOCKER, which claimed the
opposite from shape evidence alone. See INVALIDATED.

**The four existing arm artifacts are REFUSED by the loader** (2026-09-08,
EXECUTED_WITNESS) — `result_loader --check` refuses all four as anonymous
pre-schema documents: *"declares no identity ... anonymous evidence is
refused"*. Previously an unchecked observation; now confirmed, and it is the
acceptance test for any rerun (the new artifacts must FLIP to ADMITTED).

**The corrected continuity witness cannot silently pass an undecidable arm**
(2026-09-08, SABOTAGE_PROVEN) — mutating `core_generation_unchanged` from
UNKNOWN to PASS visibly changes the verdict, and the same mutation does **not**
rescue an arm whose generation genuinely changed. The clause is uninformative
when it says UNKNOWN, not wrong.

**Post-disconnect behaviour, from the orchestrator log** — recorded, not
interpreted:

```text
arm                start rss    +5s      +60s     host free +60s
IDLE                   5,471    5,597    5,597           15,649
CONTROL_WORKLOAD       5,500   16,597   16,664            4,744
RECOVERY_ONLY          5,491    5,410    5,414           15,690
FULL_WINDOW            5,514   16,105   16,097            5,444
```

---

## UNRESOLVED — open questions

1. **Does recovery destabilise co-resident neighbours?** RECOVERY-COUPLING's
   causal question. Twelve observational instances exist across ASYNC-A2 and
   ASYNC-B with a consistent signature, but recovery has never been the
   independent variable in a completed run.
2. **What does the runtime accumulate, under which operation, and does it
   plateau?** RUNTIME-MEMORY's question. Three of four arms are
   integrity-UNKNOWN, so the cross-arm comparison cannot be made.
3. **Is memory retention session-bound, backend-bound, or lifetime-bound?** The
   disconnect phase was measured but not analysed, and the arms that would
   anchor it are UNKNOWN.
4. **Is any of it model-dependent?** RC Run 1 could not separate this: the
   lfm2.5 rotation block and elapsed time were perfectly confounded.
5. **Has the corrected runtime-memory harness ever executed end-to-end?**
   **UNDETERMINED.** This rested entirely on RM-1, which is refuted, so it now
   has no support in either direction. The file parses; that is a different
   claim. Not answerable without a live run.
6. **Is the coherence detector non-marginal?** The operational gate is
   deterministic (20 fixed seeds, worst margin 0.468 against a criterion of
   0.2). That makes the *doorman* reproducible. It says nothing about the
   *detector*, and the previously observed failing region remains an OPEN
   SCIENTIFIC QUESTION. COHERENCE-MARGIN needs its own preregistration. Do not
   widen 0.2, do not change the seeds, do not claim the marginal region is gone.
7. **What is the current LM Studio runtime state?** Contaminated by the
   2026-09-07 `recovery_tooth_selftest` violation and not checkable without
   contact. Must be established and recorded before any rerun.

---

## INVALIDATED — broken instruments and void runs

- **RM-1, "the arm harness cannot parse"** — a BLOCKER raised by the static
  audit on 2026-09-08 and **REFUTED by execution the same day**. Not an
  instrument defect and not a void run: a *false finding*, carried by exact
  bytes, `cat -A` output, git provenance, timestamps and a plausible mechanism.
  Godot 4 permits a literal newline in an ordinary string. The false claim is
  now permanent in commit subject `07a3cb6` and in the supervisor's append-only
  event log, neither of which can be edited. Full supersession in
  `STATIC_AUDIT_RUNTIME_RECOVERY.md`; the methodology it produced is
  `CLAIM_TO_WITNESS.md`.
- **The ITEM 4 draft from iteration 4** — `orphaned_RERUN_ABC_PROCEDURE.md`,
  quarantined as Q-1. No bound receipt, and contaminated by RM-1 in four places
  including its first precondition. Rewritten from accepted evidence rather
  than edited; see `docs/RERUN_FOUR_ARM_PROCEDURE.md`.
- **The supervisor's "receipt is not from this turn" wording** — reported for an
  invocation that produced no receipt at all. The refusal was correct; the
  explanation was not. Fixed by invocation-outcome classification: a missing
  receipt and a mis-bound one are now different events.
- **`BACKEND_RESTARTED_MID_ARM`** — compared the complete LM Studio PID set for
  equality; scheduled recovery replaces model workers by design. 676 and 582
  false offences. Replaced. Full record in `INSTRUMENT_DEFECT_PID_TOOTH.md`.
- **RECOVERY-COUPLING Run 1** — VOID / TERMINATED.
- **RECOVERY-COUPLING qualification pass 1** — all three TREATMENT windows void
  from a shared `HTTPRequest` between the gate and the concurrent recovery.
  Preserved as evidence: treatment and control were about to separate perfectly
  from a plumbing bug.
- **20-window RUNTIME-MEMORY horizon** — would have censored the known
  recovery-at-window-21 timescale. Amended to 40 before the run.
- **`resident_set()` ambiguity** — a failed read was indistinguishable from an
  empty pool, which let `ensure_loaded()` create duplicate instances through a
  failure path. Fixed this shift.
- **Telemetry-induced throughput distortion** — the producer probe cost a
  measured 345 ms per sample, 17.3% of every interval. Fixed by split cadence
  this shift, before any arm ran with it.

---

## NEXT PERMITTED LIVE ACTION

**Requires explicit human clearance. Do not begin from this document alone.**

Rerun the three integrity-UNKNOWN RUNTIME-MEMORY arms — `IDLE`,
`CONTROL_WORKLOAD`, `RECOVERY_ONLY` — with the corrected telemetry now in the
harness. `FULL_WINDOW` already holds a PASS and does not need rerunning.

**The procedure is `docs/RERUN_FOUR_ARM_PROCEDURE.md`.** It replaces the eight-line
sketch that used to sit here. Do not follow the sketch from memory or from an
older checkout: it carried five defects, recorded in §4 of that document, of
which two were dangerous.

```text
S-1  it expected "8 passed, 0 failed, 2 skipped" from run_safe_tests.py.
     The suite now reports 42 passed, 0 failed, 4 withheld. An operator
     following it exactly either halts on a precondition that can never be
     met again, or learns to disregard expected output. The second is worse,
     and it is the one that actually happens.

S-2  it gated readiness on runtime_memory_selftest.py "PREFLIGHT GREEN,
     41 checks". Those are 41 regex matches over source as TEXT. They
     certify nothing executable. Use tools/gd_parse_check.py for that, and
     keep the regex preflight for what it does catch.
```

Blocking list at HEAD, from `RERUN_FOUR_ARM_PROCEDURE.md` §1:

```text
P1  harness persists per-sample core generation      MET
P2  old arm artifacts REFUSED (the acceptance test)  MET
P3  NO_CONTACT suite green, 42/0/4                   MET
P4  LM Studio in a known state                       UNMET -- contaminated
P5  STATE_MUTATING clearance + attended human        UNMET by construction
P6  comparability of the FULL_WINDOW PASS            UNMET -- human decision,
                                                     must be recorded BEFORE
                                                     any data exists
```

P4, P5 and P6 are the whole gate, and none of them can be cleared by an agent.

### What must NOT happen

No threshold change. No floor change. No post-hoc definition of "materially
shifted" beyond the pre-existing boundaries (Amendment 4). No adjustment for arm
order — with three arms and no replication of position, arm order is **not
estimable** (Amendment 3). No analysis of the quarantined qwen block. No
reinterpretation of UNKNOWN as PASS. No hand-editing an artifact to get it
admitted by the loader.

---

## Supervisor

Some of the documentation state above was produced by an unattended night shift
driven by `tools/night_supervisor.py`, a loop that lives outside the model and
re-invokes it until a machine-readable stop condition is reached.
**Read `docs/night/README.md` before running or trusting one.** It is the
reference for the stop conditions, the receipt binding, and the caps.

Three things a future operator needs to know before touching it:

1. **It cannot grant runtime clearance.** The night shift runs under LM Studio
   READ-ONLY / DO-NOT-CONTACT, enforced by an execution allowlist rather than by
   the prompt: seven `git` verbs plus the exact string
   `Bash(python tools/run_safe_tests.py)`. Everything in "NEXT PERMITTED LIVE
   ACTION" above is therefore out of reach for it by construction. That section
   still requires a human.
2. **Every stop fails closed.** Only a verified `CONTINUE` — bound to this
   run's nonce, the objective hash, and the commits the supervisor itself
   observed — keeps the loop alive. A missing, stale or unparseable receipt is
   `BLOCKED`, never progress.

   Since 2026-09-08 the supervisor also says **which** of those it got. Run
   `20260908_081127` stopped reporting that "the receipt is not from this turn"
   when in fact no receipt had been written at all — the model had hit a
   provider session limit and the previous iteration's file was still on disk.
   The decision was right, the story was wrong. Invocation outcomes are now
   classified from evidence gathered around the call:

   ```text
   INVOCATION_FAILED       the child never started
   NO_STATUS_PRODUCED      ran, wrote nothing, nothing on disk
   STALE_STATUS_PRESENT    ran, wrote nothing, prior receipt still present
   UNBOUND_STATUS_WRITTEN  wrote a NEW receipt that does not bind
   BOUND_STATUS_VALID      the only one that continues
   ```

   `external_cause=PROVIDER_QUOTA` may be attached from provider-authored text
   when no bound receipt exists. It is advisory: it never selects an outcome and
   never rescues a refusal.
3. **Its own output is gitignored.** `docs/night/status.json`,
   `supervisor.log` and `runs/` are operational output. Archiving a run into git
   is a deliberate act.

```
python tools/night_supervisor.py --dry-run    # plan only, no agent invoked
python tools/night_supervisor.py --status     # read the current receipt
```

Documentation written under a supervised shift is documentation, not evidence.
Nothing in this file was measured by the supervisor, and no shift may promote a
`UNKNOWN` arm, retouch a threshold, or reinterpret the quarantined block.

---

## Blocked, and why

The night shift could not resolve the integrity adjudication for arms A, B and
C. Their backends are gone and core generation was never recorded, so the
corrected witness returns UNKNOWN and no honest reconstruction exists. That is
the frozen outcome from Amendment 5, not a failure to try harder.

Also blocked, and left blocked deliberately:

- **COHERENCE-MARGIN.** The operational gate is deterministic; the scientific
  question of whether the detector is marginal is untouched and needs its own
  preregistration.
- **Promotion of CLAIM-TO-WITNESS to Law 7.** The redundancy test is written
  out in `docs/CLAIM_TO_WITNESS.md`, but granting a law on the strength of my
  own argument is the error that document exists to name.
- **F-1 and F-2 from the contact classification audit.** The runner's `http`
  marker is pinned to one port. Widening it refuses *more* — the safe direction
  — but it is still a boundary change, and boundary changes are not made
  unattended.

All three are HUMAN_CLEARANCE_REQUIRED. None is a failure to try harder either.
