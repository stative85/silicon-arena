# BOUNDARY WORK ITEM — F-1, F-2, F-3, F-4 as ONE atomic change

**Status: APPROVED AS A CONCEPT, 2026-09-08. NOT IMPLEMENTED.**
**Blocked on: F-3's exact tracked text being read before implementation** — see
§3, which quotes it rather than paraphrasing it.

Approved as a single atomic boundary change, explicitly **not** four
opportunistic patches. The four findings share the marker machinery in
`tools/run_safe_tests.py`; landing them separately leaves the classified runner
in one of two broken intermediate states:

```text
broader scanner, old allowances   ->  BYPASS FACTORY
                                      (wide detector, unscoped exemptions that
                                       silently swallow the new hits)

broader scanner, no allowances    ->  FALSE-POSITIVE FACTORY
                                      (every benign string trips it; operators
                                       learn to ignore the audit, which is the
                                       S-1 failure mode again)
```

Either state trains the operator to disregard the boundary. That is worse than
the gap the change is meant to close.

---

## 1. Implementation standard — all five, or it does not land

```text
broad contact detector
        +
precisely scoped allowances
        +
existing benign controls
        +
new-contact sabotage
        +
allowance-drift sabotage
        =
ONE CHANGE
```

**Existing benign controls** are the load-bearing half. The current audit's
value is that it does not fire on `bridge.serve_websocket = false`, on
`"socket died"` as a label, on `"godot_event_authority"` in an assertion, or on
a model name in a fixture. A broader detector that flags those has not become
stricter, it has become useless. Every justification in
`CONTACT_CLASSIFICATION_AUDIT.md` §2.3–§2.5 is a regression test for the new
scanner.

**New-contact sabotage:** add real runtime contact to a NO_CONTACT suite on a
port and transport the *old* marker set could not see, and require the audit to
refuse. Without this the widened detector is unproven in the exact direction it
was widened.

**Allowance-drift sabotage:** add a *second*, genuinely contacting occurrence to
a file that already holds an allowed benign one, and require the audit to refuse
while the original stays allowed. This is F-4's whole content and it cannot be
demonstrated by inspection.

Both sabotages must assert they applied before their result is trusted (Law 7,
third sentence).

---

## 2. F-1 and F-2, quoted from the tracked audit

**F-1 — the runner's `http` marker is pinned to one port.** The marker is:

```python
"http": r"HTTPRequest|127[.]0[.]0[.]1:1234|http://localhost:1234"
```

> A NO_CONTACT suite addressing the runtime on any other port, host, or via an
> `HTTPClient`/`StreamPeerTCP` path would not be flagged. `offline_selftest`
> demonstrates the gap benignly: it holds a live URL constant the runner's scan
> does not see.

Recommendation recorded there, **not applied**: widen to `HTTPClient`,
`StreamPeerTCP`, and `127.0.0.1|localhost` on any port.

**F-2 — `marker_allowance` is applied inconsistently.**

> `night_supervisor_selftest` names `lms`, `curl`, `godot` and `PowerShell` in
> the assertion that forbids them, and needs no allowance **only because the
> runner's markers are narrow enough to miss them**. If F-1 is applied, this
> suite will start tripping the audit and will need an allowance of its own. The
> two findings are coupled; fix them together or not at all.

This coupling is the mechanical reason the bundle is atomic rather than a
preference: **widening the detector breaks the supervisor's own test suite** on
the same commit, and that suite is what the night loop's integrity gate runs.

---

## 3. F-3, quoted verbatim — the gate on implementation

Surfaced here in full because it was not to be reconstructed from memory. Law 7
applied to the people applying Law 7.

> ### F-3 — classification is a property of `(file, args)`, not of a file
>
> ```text
> EVIDENCE CLASS:  EXECUTED_WITNESS (the backend_continuity tripwire)
> SEVERITY:        MEDIUM -- structural
> STATUS:          RECORDED, NOT FIXED
> ```
>
> `backend_continuity.py` is NO_CONTACT as `--selftest` and reads the live
> process table as `--apply`. The registry records the invocation; the marker
> scan reads the whole file. Both are correct in their own terms, and the
> *reason* the classification is safe — that the contacting path is unreachable
> from the registered arguments — is currently a fact about the code, not a fact
> the registry states or the audit enforces.
>
> Nothing exploits this today. It is written down because the next person to add
> `--apply` to a registry entry, or to make a contacting path reachable from
> `selftest()`, will not be warned by any tooth.
>
> **Recommendation (not applied):** record per-entry *why the registered
> invocation cannot reach the contacting path*, and prefer a tripwire witness
> like §2.1 over a reading of the call graph.

**What F-3 adds to the bundle.** F-1 and F-4 are about the *scanner*; F-3 is
about the *registry*. A file-level scan cannot express "safe under these args,
contacting under those", so widening the scanner without F-3 makes
`backend_continuity` and any future dual-mode tool permanently
allowance-dependent — and F-4 has just established that allowances are the thing
being tightened. The three interlock: **scope the scanner, scope the allowance,
and record why the registered invocation is safe.**

F-3's recommendation also names the standard the other three should meet: prefer
a **tripwire witness** over a reading of the call graph. The tripwire in §2.1 of
the audit is the model — it fired when called directly and stayed silent through
the suite, so its silence carried information.

---

## 4. Explicitly out of scope

- Reclassifying any suite. The audit found no misclassification; this work item
  changes detection machinery, not classifications.
- Releasing any held suite. The 4 withheld stay withheld.
- Any change to a scientific threshold, seed set, floor, or acceptance
  criterion. This is a boundary change and touches none of them.
- Landing any part of it during a supervised night shift. The classified runner
  is the shift's own integrity gate; rebuilding it while a queue depends on it
  changes what the gate refuses mid-flight.

## 5. Acceptance

```text
1. every §2.3-§2.5 benign control still passes unflagged
2. new-contact sabotage REFUSES, on a port/transport the old markers missed
3. allowance-drift sabotage REFUSES the new occurrence, allows the old one
4. both sabotages assert they applied, and are reverted
5. night_supervisor_selftest passes under the widened detector, with its
   allowance scoped to the exact known occurrence
6. run_safe_tests.py green: 0 failed, 4 withheld
```

Anything less than all six is an intermediate state, and §0 says why
intermediate states are the thing being avoided.
