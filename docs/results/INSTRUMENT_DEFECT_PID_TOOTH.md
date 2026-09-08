# Instrument defect: the `BACKEND_RESTARTED_MID_ARM` tooth

Preserved deliberately. This is not an embarrassing footnote to be tidied away —
it is a worked example of a detector that measured a proxy instead of its
invariant, and of the chronology discipline that kept the correction honest.

## The original tooth

```gdscript
var pids := _backend_pids()          # complete LM Studio PID set
if not _pids.is_empty() and not _same_pids(pids, _pids):
    _problems.append("BACKEND_RESTARTED_MID_ARM: %s -> %s" % [...])
```

**What it measured:** exact equality of the complete set of `LM Studio.exe`
process ids, sampled every 2 seconds and compared against the set captured at
arm start.

**Invariant it was written to protect:** one backend lifetime per arm. The
treatment boundary in RUNTIME-MEMORY is a fresh backend per arm, so a restart
*inside* an arm would splice two unrelated trajectories into one and make a
plateau claim meaningless.

## Why the treatment legitimately violated the proxy

LM Studio runs a process tree, not a single process:

```text
core          "LM Studio.exe"                     no --type=, parent is not
                                                  another LM Studio process
support       --type=renderer / gpu-process / crashpad-handler / utility
model_worker  --type=utility --utility-sub-type=node.mojom.NodeService
```

**A scheduled recovery unloads and reloads a model, and LM Studio replaces that
model's worker process.** The PID set therefore changes on every single
recovery — by design, as the direct mechanical consequence of the treatment.

The detector could not tell that from a backend restart, because both look
identical through the only lens it had: set inequality.

## Historical offences

```text
arm                offences   recoveries   verdict under the old tooth
RECOVERY_ONLY           676           40   flagged
FULL_WINDOW             582           40   flagged
IDLE                      0            0   clean
CONTROL_WORKLOAD          0            0   clean
```

Exactly the two arms that perform recoveries. Exactly the two arms the tooth
most needed to protect.

## Evidence the protected invariant actually held

Recomputed from the same samples, independent of any trajectory:

```text
arm                set_size   stable_core   churned   recoveries
IDLE                   [12]        12            0         0
CONTROL_WORKLOAD       [12]        12            0         0
RECOVERY_ONLY      [11,12]          9           43        40
FULL_WINDOW            [12]          9           43        40
```

Nine processes present in **every** sample of both flagged arms, and the set
size never approaching zero. A genuine restart takes the set to zero and the
stable core to zero. For `FULL_WINDOW` the core process was still alive
afterwards and was verified directly: pid 20924, created 6:53:25 PM, unchanged.

## The corrected witness

```text
BACKEND CONTINUITY PASS iff
    core identity persists for the entire arm
AND core start-time / generation identity does not change
AND no interval shows the backend unavailable
AND worker churn is attributable only to scheduled recoveries
```

Roles come from **producer structure** — command line, parent relationship,
creation time — never from a count observed in the completed run. `"nine stable
PIDs"` was explicitly rejected as a rule and the preflight asserts that no such
count is hardcoded.

`tools/backend_continuity.py`, 10 sabotage checks, 0 failures. It rejects an
actual restart, a disappear/reappear, a reused pid with a changed generation, a
dead core, unexplained churn with no recoveries, and churn exceeding what the
recoveries can explain. It accepts scheduled worker replacement with a constant
core generation. A missing generation field returns **UNKNOWN, never a silent
pass.**

## Chronology — the part that makes the correction trustworthy

```text
47d2c13   raw arm artifacts + corrected witness committed
6a6b4d5   Amendment 5 frozen: adjudication rule, trajectories UNREAD
```

Amendment 5 — which defined the corrected witness, forbade reinterpreting
UNKNOWN as PASS, and pre-committed the possible outcomes including
`integrity_qualified = UNKNOWN` — was frozen **before any RAM trajectory was
examined**. The correction was therefore not shaped by which arms it would
rescue.

Result under the corrected witness:

```text
FULL_WINDOW       PASS      core identified, generation verified
RECOVERY_ONLY     UNKNOWN   backend gone, generation unrecoverable
CONTROL_WORKLOAD  UNKNOWN   same
IDLE              UNKNOWN   same
```

**The corrected witness is stricter and downgraded two arms the broken tooth had
passed.** That was not treated as a reason to soften it.

## The structural lesson

The gap is not incidental. The design restarts the backend at every arm
boundary, so **only the final arm can ever have a live core to interrogate
retrospectively.** Any future run must record the core generation per sample —
now implemented, and the arm refuses to start without it.

## Related

- `docs/ROBRUSTION_LAWS.md` Corollary 1a
- `docs/results/TREATMENT_AWARE_DETECTOR_AUDIT.md`
- `docs/EXPERIMENT_RUNTIME_MEMORY.md` Amendment 5
