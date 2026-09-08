# CLAIM-TO-WITNESS — every finding declares its strongest evidence

**Status: GRANTED AS LAW 7 — CLAIM-TO-WITNESS LAW, 2026-09-08.**
Promoted by human clearance after the redundancy test in the last section. It
was written as a candidate and deliberately not self-granted, because granting a
law on the strength of one's own argument is the error it names. The normative
statement now lives in `docs/ROBRUSTION_LAWS.md` §7; this document remains the
working detail — the four classes, the six rules, and the form a finding takes.

---

## The event that produced this

The 2026-09-08 static shift produced RM-1: a BLOCKER stating that
`tools/runtime_memory.gd` could not parse. It was wrong.

Everything supporting it was real:

- the exact bytes, three raw newlines inside double-quoted literals
- `cat -A` output confirming them
- git provenance for when the corruption entered
- timestamps
- a corroborating detail: an adjacent identical site that was *not* mangled
- a plausible mechanism: an escape expanded into the character it denotes

The conclusion was still false. Godot 4 permits a literal newline in an ordinary
string. One `--check-only` invocation — available the whole time, never run —
would have settled it in under a second.

The finding then propagated into a commit subject line and into the supervisor's
append-only event log, where neither can be edited. The apparatus did not
malfunction. Every boundary held. **The system was operationally safe and
epistemically wrong**, and no amount of additional permissions machinery would
have caught it, because nothing unsafe happened.

## The four classes

Every defect, finding, or claim states which class its **strongest** evidence
reaches. Not its most abundant evidence. Its strongest.

```text
1. OBSERVED_SHAPE
   "I see this pattern."
   Bytes, greps, file contents, structure. Says what is there.
   Says nothing whatever about what it does.

2. STATIC_INFERENCE
   "I infer this pattern probably means X."
   Reading plus a model of the system. This is where RM-1 died, and it is
   where confident wrongness lives, because it FEELS like knowledge and
   accumulates corroboration without ever touching the referent.

3. EXECUTED_WITNESS
   "I executed the relevant behaviour and observed X."
   The claim was put to the thing it is about.

4. SABOTAGE_PROVEN
   "I proved the witness can fail in the dangerous direction, then
    observed it pass correctly."
   The witness itself has been shown to bite.
```

## The rules

**RULE 1 — Execution beats reading, and is mandatory when available.**
If the claim is about executable or runtime behaviour and execution is
available, OBSERVED_SHAPE and STATIC_INFERENCE are **not sufficient**, however
much of either has accumulated. Corroboration between two class-1 facts does not
produce a class-3 fact. RM-1 had six independent pieces of evidence and all six
were about the shape.

**RULE 2 — A witness that could only pass is not evidence.**
An EXECUTED_WITNESS must have been *capable of producing the opposite result*. A
checker that never fails is a rubber stamp with a transcript. This is why
`gd_parse_check.py` qualifies against a genuinely corrupt script: the tooth is
shown able to say FAIL before its PASS is worth anything.

**RULE 3 — The suspicious-but-legal control is not optional.**
A detector qualified only on (valid passes, corrupt fails) is satisfied by one
that rejects anything unusual-looking — which is precisely the detector that
generated RM-1. Any tooth adjudicating "is this thing broken" must carry a
control that is *legal and looks wrong*, and must PASS it.

**RULE 4 — Unverified is a verdict. Write it.**
"I could not execute this" is a publishable, respectable finding. Silence about
the gap is not. The failure is never the absence of a witness; it is the absence
of a witness plus the presence of a confident verdict.

```text
BAD:
  "I see a newline in a quoted string, therefore parse failure."

GOOD:
  "I see a newline inside a quoted string.       [OBSERVED_SHAPE]
   Static inference: suspicious, possible parse failure.
   Execution: NOT TESTED.
   Verdict: UNVERIFIED."
```

**RULE 5 — Refutation supersedes, never deletes.**
A finding shown false keeps its original text and gains the transition record:
original status, current status, original basis, refuting class, claim, result.
A log that erases its own bad findings cannot be used to measure how often the
apparatus is wrong — and that rate is the only thing that says whether it can be
trusted. Humans have laundered bad premises through editing since clay tablets;
this system will not automate it.

**RULE 6 — Refuting a claim does not refute its neighbours.**
When a premise falls, every dependent claim becomes UNDETERMINED, **not false**,
and every independent claim standing beside it is untouched. Sort them
explicitly. RM-1's fall left one FALSE, one UNDETERMINED, one INDEPENDENT and
one still TRUE.

## Required form for a finding

```text
ID       — SEVERITY — one-line claim
EVIDENCE CLASS: OBSERVED_SHAPE | STATIC_INFERENCE | EXECUTED_WITNESS | SABOTAGE_PROVEN
WITNESS:        the exact command run, or NONE AVAILABLE, or NOT ATTEMPTED
COULD-HAVE-FAILED: how this witness could have produced the opposite result
                   (mandatory for EXECUTED_WITNESS and above)
```

A finding at class 1 or 2 whose subject is executable, where execution was
available and not attempted, is **UNVERIFIED** regardless of how much shape
evidence it carries. It may still be written. It may not be called a BLOCKER.

## Where this applies immediately

| target | current strongest class | note |
|---|---|---|
| `runtime_memory_selftest.py` "PREFLIGHT GREEN" | STATIC_INFERENCE | 41 `re.search` calls over source as text; certifies no executable behaviour |
| RM-1 | refuted at EXECUTED_WITNESS | see the supersession in the static audit |
| `gd_parse_check.py` | SABOTAGE_PROVEN | corrupt-script control proves it can say FAIL |
| RUNTIME-MEMORY arms A/B/C | none — telemetry absent | UNKNOWN. Never promote to PASS |

## Redundancy test — is this really new?

Law 6 was granted only after it was shown not to be an existing law arriving by
another route. The same test, honestly applied:

- **Law 2 (Detector-Support)** is the closest neighbour: a detector must be
  supported by what it claims to detect. But Law 2 governs *instruments inside
  an experiment*. RM-1 involved no instrument and no experiment — it was an
  agent reading a file and concluding. Law 2 has nothing to attach to.
- **Law 6 (Execution-Boundary)** is about mechanically enforcing what may be
  *executed*. This is close to its inverse: what must be executed before a claim
  is believed. Law 6 restrains the hands; this restrains the conclusions.
- **Laws 1, 3, 4, 5** all concern an instrument or treatment misrepresenting a
  system under measurement. This concerns a *reasoner* misrepresenting a file
  under inspection, with every boundary intact.

That is a different family, and arguably the more dangerous one, because it
produces artifacts that look exactly like good work. But "arguably" is a class-2
word, and promoting doctrine on class-2 evidence is the error this document
exists to name. **HUMAN_CLEARANCE_REQUIRED.**

**CLEARED 2026-09-08.** Granted as Law 7. The clearing judgement recorded the
distinctness this way: observation true, provenance true, receipts true,
inference from those receipts to executable behaviour false, and an executable
witness available that would have refuted the claim immediately. The law's third
sentence — *a witness must itself be capable of producing the opposite result* —
carries the separate lesson from the sentinel and the sabotages, not just from
RM-1.
