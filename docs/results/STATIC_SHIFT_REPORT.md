# STATIC SHIFT REPORT — run `20260908_081127` and post-run review

**ITEM 8.** Range `fb71a50..6bfe463`, 12 commits, 16 files, +3083/-62. No LM
Studio contact, no inference, no arm run, no threshold touched.

The shift's most important product is a **false BLOCKER it published with
perfect receipts**, and the machinery built afterwards to make that harder. That
is the headline, ahead of anything that went right.

---

## 1. The headline failure

The unattended static audit (ITEM 1, `07a3cb6`) reported **RM-1**: the arm
harness `tools/runtime_memory.gd` contains unterminated string literals and
**cannot parse**. Severity BLOCKER. It blocked ITEM 4 by its own account.

It was false.

Everything under it was true. Three raw newlines inside ordinary double-quoted
literals, confirmed byte-for-byte with `cat -A`, traced through git provenance,
timestamped, and corroborated by an adjacent identical site that had *not* been
mangled — plus a plausible mechanism, an escape expanded into the character it
denotes. Six independent pieces of evidence, every one of them real.

Godot 4 permits a literal newline in an ordinary string. `.split("<newline>")`
means exactly what `.split("\n")` means. One `--check-only` invocation —
available the entire time, never run — settles it in under a second:

```text
python tools/gd_parse_check.py tools/runtime_memory.gd
  ok   tools/runtime_memory.gd
  === 1 parsed, 0 failed ===
```

**Nothing in the apparatus malfunctioned.** Every execution boundary held. The
agent had no runtime access, contacted nothing, deleted nothing, and changed no
criterion. It was *operationally safe and epistemically wrong*, and no amount of
additional permissions machinery would have caught it, because nothing unsafe
occurred.

**The damage is permanent where it landed.** The false claim is the subject line
of commit `07a3cb6` and an entry in the supervisor's append-only event log at
08:18:53. Neither can be edited. The finding is superseded in place in
`STATIC_AUDIT_RUNTIME_RECOVERY.md`, original text preserved as an exhibit.

**It nearly happened twice.** Writing ITEM 4, my first grep for the core
generation telemetry used the field names I expected — `core_generation`,
`start_time` — and returned nothing. On that evidence precondition P1 was about
to be written as UNMET, a second blocker. The field is `core_created`. A grep
that returns nothing is evidence about the pattern, never about the code. The
near-miss is recorded in `RERUN_FOUR_ARM_PROCEDURE.md` §1 rather than quietly fixed.

---

## 2. Why the run stopped

Not budget: 4 of 10 iterations, 28 of 240 minutes.

```text
08:35:11  iteration_start  it=4  nonce 0dbf4a514eeb0313
08:39:14  status           it=4  BLOCKED
08:39:36  stop             reason=dirty_tree_post
                           dirty: ["?? docs/RERUN_ABC_PROCEDURE.md"]
```

`iteration_004_output.txt`, 67 bytes, in full:

```text
You've hit your session limit · resets 12:30pm (America/Chicago)
```

The model hit a provider quota mid-ITEM-4. It wrote no receipt. The supervisor
read the file on disk — iteration 3's receipt, `md5` byte-identical — found the
nonce did not match, and reported *"the receipt is not from this turn"*. It then
found the half-written ITEM 4 draft untracked and stopped.

**The supervisor was right and its explanation was wrong.** BLOCKED was correct;
the wording described a model presenting a bad receipt when no receipt had been
produced at all. Fixed in `2d76537` — see §4.

**The scheduling miss was human timing, not supervisor failure.** There was no
successful overnight run; the supervisor worked correctly when launched in the
morning. That distinction is worth keeping: the supervisor has now been observed
to fail *closed* twice and to fail *open* never.

---

## 3. What was completed

| item | commit | outcome |
|---|---|---|
| 1 | `07a3cb6` | static audit, 26 findings, nothing fixed — **1 of them false** |
| 2 | `35bd7e7` | artifact schemas; BC-5 closed at 3 consumers; 14 mutation teeth |
| 3 | `be26288` | loader fail-closed 17 → 35 checks, nine holes each with a sabotage |
| 4 | `34ec946` | rerun procedure, rewritten from accepted evidence |
| 5 | `43cb767` | 46 suites justified; no misclassification; 3 findings |
| 6 | `7fd22c7` | sabotage added to two teeth that had none |
| 7 | `6bfe463` | `NEXT_LIVE_RUN.md` current |
| 8 | this | — |

Post-run review added: the parse tooth (`cb09e57`), the RM-1 supersession
(`1cee28d`), CLAIM-TO-WITNESS (`edd826d`), supervisor invocation outcomes
(`2d76537`), the quarantine register (`8bdc735`).

Suite: **41 → 42 passed, 0 failed, 4 withheld** throughout.

---

## 4. Bugs found

Four, of which **three were in the witnessing machinery itself** — the teeth,
not the code under test.

**B-1 — a sabotage helper that could not tell it had failed to apply**
(`be26288`). The sabotage-applied check used `==`. In Python `1 == True`, so
mutating boolean `True` to integer `1` — precisely the serialisation accident
the `is not True` branch exists to catch — compared EQUAL, and the helper
reported SABOTAGE DID NOT APPLY. A false negative inside a witness. Fixed with
`artifact_schema.doc_fingerprint()`; four checks prove the trap exists under `==`
and that the fingerprint sees through it.

**B-2 — the harness hid its own failures** (`be26288`). `run_safe_tests.py`
printed the last three matching lines, which for a RED suite is the summary —
concealing the failing check. The only remedy was running the suite directly,
which the classification forbids. Found the honest way: a suite went red and the
harness would not say why.

**B-3 — the supervisor conflated a missing receipt with a presented one**
(`2d76537`). §2. Now classified from evidence gathered around the call:
`INVOCATION_FAILED`, `NO_STATUS_PRODUCED`, `STALE_STATUS_PRESENT`,
`UNBOUND_STATUS_WRITTEN`, `BOUND_STATUS_VALID`. The status file is fingerprinted
by sha256 **before** invocation — deliberately not mtime, since same-second
writes share a timestamp. `external_cause=PROVIDER_QUOTA` attaches only where no
bound receipt exists, and is advisory: it never selects an outcome, never
rescues a refusal, and a tooth proves quota text in a *passing* turn's
transcript is ignored. **Direction of travel is one-way** — every outcome except
`BOUND_STATUS_VALID` still BLOCKS, with two teeth asserting so.

**B-4 — RM-1 itself**, the only one that reached a published verdict. §1.

---

## 5. Sabotages proven

A tooth that cannot go red is decoration with a transcript.

```text
LOADER (ITEM 3)          9 refusal branches, each paired with the sabotage
                         that proves it applied before proving it bites, plus
                         positive controls so refusal is about the defect and
                         not a broken fixture
ARTIFACT SCHEMA          14 mutation sabotages + 4 on-disk refusals; 29 -> 33
                         checks after B-1
PARSE TOOTH              remove --check-only     -> RED, breaks the NO_CONTACT
                                                    control (the checker starts
                                                    EXECUTING what it inspects)
                         force always-OK         -> RED, breaks the corrupt
                                                    control
SUPERVISOR               collapse STALE back into UNBOUND -> the misleading
                         wording returns; reverted, and it goes
CONTINUITY WITNESS       UNKNOWN -> PASS mutation visibly flips the verdict,
                         AND does not rescue a genuinely changed generation
```

The continuity pair is the one that matters for the science: the dangerous
direction there is never FAIL, it is UNKNOWN quietly becoming PASS, because PASS
is what lets an arm be read.

---

## 6. What was deliberately NOT done

- **RM-1 was not deleted.** Superseded in place, original heading intact, wrapped
  in the verdict. A defect log that erases its bad findings cannot measure how
  often the apparatus is wrong, and that rate is the entire question.
- **The orphaned ITEM 4 draft was not repaired.** It inherits RM-1 in four
  places including its first precondition. Stripping those four references and
  committing the rest would have looked correct and read well. It is quarantined
  as Q-1 and ITEM 4 was rewritten from accepted evidence instead.
- **CLAIM-TO-WITNESS was not self-granted as Law 7.** The redundancy test is
  written out; the promotion is left to a human.
- **No suite was reclassified** — the contact audit found no misclassification.
- **F-1/F-2 were not applied.** The runner's `http` marker is pinned to
  `127.0.0.1:1234`; widening it refuses *more*, the safe direction, but it is a
  boundary change and boundary changes are not made unattended.
- **No threshold, floor, seed set or criterion touched.** RAM floor 2048 MB,
  `ks=1.8`, `kh=20`, `n=3`, coherence 0.2, seeds 1..20 all unchanged.
- **Nothing deleted.** No model, no artifact, no run directory.
- **The supervisor was not relaunched** during the post-run review. Two owners
  of one repository is the conflict the doctrine exists to prevent.

---

## 7. Unresolved blockers

```text
P4  LM Studio in a known state       UNMET. Contaminated by the 2026-09-07
                                     recovery_tooth_selftest violation and not
                                     checkable without contact.
P5  STATE_MUTATING clearance         UNMET by construction. Needs clearance
                                     AND an attended human.
P6  comparability of FULL_WINDOW     UNMET. Science decision, must be recorded
                                     BEFORE any data exists.
```

Still open, and deliberately so: the RUNTIME-MEMORY causal question; whether the
corrected harness has ever executed end-to-end (**UNDETERMINED** — it rested on
RM-1 and now has support in neither direction); whether the coherence *detector*
is marginal (the gate is a deterministic doorman; the detector is untouched);
RECOVERY-COUPLING Run 1's causal question (**VOID**, not rescuable); the
quarantined qwen block (`causal_evidence_eligible: false` **FOREVER**).

**Arms IDLE, CONTROL_WORKLOAD and RECOVERY_ONLY remain UNKNOWN and stay UNKNOWN
forever.** Their backends are gone. A rerun is new data, never a retroactive
repair. UNKNOWN is not a soft PASS.

---

## 8. The lesson, stated plainly

The boundaries stopped destructive action. The supervisor stopped on stale
state. The audit preserved provenance. Every mechanism worked.

And the shift still shipped a false blocker, into a commit subject and an
append-only log, where it cannot be edited.

**A system can be operationally safe and epistemically wrong.** The next
frontier is not more permissions machinery — permissions had nothing to catch.
It is evidence promotion: `shape → inference → executed witness →
sabotage-proven`, with the class stated on every finding.

The system is no longer lying with its hands. It is lying with its conclusions,
and the conclusions arrive with beautiful receipts.
