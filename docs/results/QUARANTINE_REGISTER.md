# QUARANTINE REGISTER

Artifacts that exist, are not deleted, and are **not evidence**. Nothing here
may be cited, promoted, or edited into acceptance. The register is tracked; some
of the artifacts it names are not, which is exactly why the register exists.

Deletion is never the remedy. A quarantined artifact that vanishes cannot be
audited, and the reason it was quarantined stops being checkable.

---

## Q-1 — `orphaned_RERUN_ABC_PROCEDURE.md` — ITEM 4 draft, 2026-09-08

```text
STATUS:          ORPHANED_PARTIAL
CLASSIFICATION:  not evidence / not accepted output / drafting material only
LOCATION:        docs/night/runs/20260908_081127/orphaned_RERUN_ABC_PROCEDURE.md
                 (inside a gitignored run directory; never tracked)
SIZE:            20,544 bytes
PRODUCED BY:     static shift run 20260908_081127, iteration 4
```

**How it came to exist.** Iteration 4 began ITEM 4 at 08:35:11 and wrote this
file. The invocation then hit a provider session limit before the agent could
commit it or write a status receipt. The supervisor found the tree dirty with an
untracked file, stopped on `dirty_tree_post`, and the draft was set aside under
an `orphaned_` prefix. It was never committed, never reviewed, never accepted.

**Why it stays quarantined — two independent reasons.**

1. **It is procedurally unaccepted.** It has no bound receipt. Iteration 4
   produced no status.json, so nothing attests to what this file claims to be.
   An artifact whose producing turn never reported cannot be admitted on the
   strength of looking finished.

2. **It is contaminated at the root.** It inherits RM-1 — now **REFUTED** — in
   four places, including as the *first* entry in its blocking list:

   | line | inherited claim |
   |---|---|
   | 44 | records RM-1 as the parse defect, citing the static audit |
   | 55 | precondition 1: "RM-1 is fixed — the three literals restored to `\n`" |
   | 59 | requires a parse gate so the harness cannot ship "a file that does not compile" |
   | 300 | STOP condition: "RM-1 unfixed, or fixed with no parse gate" |

   Its headline — *"this procedure CANNOT BE RUN TODAY"*, five unmet
   preconditions — is built on a false premise. The harness parses. The
   conclusion may well survive on other grounds, but it would be surviving for
   reasons the document does not give.

**The rule this exists to enforce.** The tempting move is to open the file, edit
out the four RM-1 references, and commit what remains — it would look correct
and it would read well. That is laundering a bad premise through editing, and it
destroys the only record of how far the false finding actually propagated.
ITEM 4 is therefore **rewritten from accepted evidence**, not repaired. See
`docs/CLAIM_TO_WITNESS.md` RULE 5.

**Permitted use.** Consult as drafting material — its section structure and its
list of *candidate* preconditions are a reasonable starting shape, and its
observation that `docs/NEXT_LIVE_RUN.md` names witnesses that cannot be produced
is worth re-deriving independently. Every claim taken from it must be
re-established against HEAD before it appears in an accepted document.

**Forbidden.** Committing it, in whole or in part, in edited or unedited form.
Citing it as a finding. Treating its precondition list as the blocking list.

---

## Q-2 — the clean qwen3.5 20-window block

Recorded in full in the RUNTIME-MEMORY and RECOVERY-COUPLING documents; named
here so the register is a complete index of what is quarantined, **not** to
restate or reinterpret its terms.

```text
causal_evidence_eligible:         false, FOREVER
diagnostic_sensitivity_eligible:  false, earnable only through the pre-frozen
                                  9-condition rule
```

Its terms are frozen elsewhere and are not modified, summarised, or softened by
this register. Do not analyse it casually.
