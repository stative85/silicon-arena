# Result loader: fail-closed coverage

Static night shift, ITEM 3. Offline. No runtime contacted, no artifact
rewritten, no threshold set or relaxed.

## The rule applied

A refusal branch with no test is not coverage. Every branch below is paired
with a sabotage that mutates a known-good document, **proves the mutation
actually applied**, and then proves the loader refuses it.

Every change here moves in one direction only: the loader refuses **more**
than it did. Nothing that was previously refused is now admitted. This file
decides admissibility of evidence; it decides nothing about what evidence
means. ks=1.8, kh=20, n=3, the 2048 MB floor and the coherence gate's 0.2 and
seeds are untouched.

`tools/result_loader.py`: 17 checks -> **35 checks**.
`tools/artifact_schema.py`: 29 checks -> **33 checks**.

## Holes closed

Each of these documents was **ADMITTED** by the previous loader.

| # | Hole | What used to happen | Now |
|---|---|---|---|
| RL-1 | unrecognised `integrity_status` | only `UNKNOWN`/`VOID`/`QUARANTINED` were named. `integrity_status: "FAILED"` with `integrity_qualified: true` fell through every branch and was **admitted** | refused unless the status is in `RECOGNISED_STATUS`; unrecognised is not PASS |
| RL-2 | `run_kind` absent | only `QUALIFICATION` was refused. An artifact that declared no run kind at all was admitted | refused; an artifact must declare it is an evidence run |
| RL-3 | `run_kind` some other non-evidence value | `SMOKE`, `PILOT`, `DRYRUN` were admitted, because the code only knew the one name it had been told | refused unless in `EVIDENCE_RUN_KINDS` |
| RL-4 | causal request against a doc with no causal field | already refused by `is not True`, but **untested** — a branch nobody had ever proven bites | refused, with the reason naming `absent`, and tested |
| RL-5 | non-object root reaching `assess()` | `doc.get` raised `AttributeError` — a stack trace, not a refusal. Reachable by any caller that does not go through `load_for_comparison` | refused. Tested for list, str, int and None roots |
| RL-6 | truthy-not-True `integrity_qualified` | already refused, untested | tested for the string `"true"` and the integer `1` |
| RL-7 | empty batch | `load_for_comparison([])` returned `{}` and the CLI printed `ADMITTED 0 artifact(s)` with return code 0 — a comparison over nothing reading as a pass | refused |
| RL-8 | duplicate artifact in a batch | two paths sharing a basename collapsed into one entry in `docs`. The caller believed it compared N arms and compared N-1 | refused as an ambiguous batch. The paired test proves the same artifact **is** still admitted when requested once, so the refusal is about duplication and not about a bad fixture |
| RL-9 | batch spanning two experiments | arms declaring different `experiment_id` were compared against each other without comment | refused. The paired test proves two arms of the **same** experiment are still admitted |

## A defect found in the sabotage machinery itself

RL-6 did not pass first time, and the reason is worth keeping.

The sabotage helper proves a mutation applied by comparing the document before
and after. It used `==`. In Python `1 == True`, so replacing the boolean `True`
with the integer `1` — a real corruption of an artifact, and exactly the
serialisation accident the `is not True` check exists to catch — compared
**equal**, and the helper reported `SABOTAGE DID NOT APPLY`.

This is a false negative in a tooth, which is the worst kind: it can only ever
make a test refuse to witness something. `artifact_schema.doc_fingerprint()`
now serialises with types visible, and both sabotage helpers use it. Four
checks in `artifact_schema --selftest` prove the trap exists under `==` and
that the fingerprint sees through it — the helper's own tooth now has a tooth.

The same weak `==` was present in `artifact_schema`'s sabotage helper and is
fixed there too. No sabotage there was passing falsely (none mutate a bool to
an int), but the hole was the same hole.

## A reporting defect fixed in the runner

`tools/run_safe_tests.py` printed the last three matching lines of a suite's
output. For a **green** suite that is the summary. For a **red** one it showed
the summary and hid which check failed, so the only way to find out was to run
the suite directly — which is precisely what the contact classification
forbids. On failure the runner now surfaces the `FAIL` lines themselves.

This was found the honest way: a suite went red and the harness would not say
why.

## Not done

- The four `RUNTIME_MEMORY_*.json` arms on disk remain refused, for the same
  reason as before (no declared identity). Nothing here rescues them.
- `RECOGNISED_STATUS` lists `QUALIFIED` as the only non-refusing status. That
  is a description of the statuses this loader has branches for, not a claim
  that any artifact currently holds it. None does.
