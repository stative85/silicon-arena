"""Fail-closed result loader. Refuses ineligible evidence mechanically.

    python tools/result_loader.py --selftest
    python tools/result_loader.py --check RUNTIME_MEMORY_IDLE.json ...

Cross-arm comparison is REFUSED unless every requested artifact is
`integrity_qualified == true`. Rejection is the default; admission must be
earned by the artifact carrying its own proof.

REJECTED, always:
    integrity_status  UNKNOWN        -- never silently upgraded to PASS
    integrity_status  VOID
    status            QUARANTINED
    integrity_status  unrecognised   -- a status this loader does not know is
                                        not a pass; see RECOGNISED_STATUS
    run_kind          QUALIFICATION  -- qualification is not evidence
    run_kind          absent / other -- only a declared evidence run counts;
                                        see EVIDENCE_RUN_KINDS
    evidence_eligible false
    causal_evidence_eligible false   -- when causal analysis is requested
    causal_evidence_eligible absent  -- likewise; silence is not consent
    missing eligibility fields       -- an artifact that cannot prove its own
                                        status is not admitted on the benefit
                                        of the doubt
    non-object root                  -- refused, not crashed on
    no declared identity             -- a file that names no experiment and no
                                        block is anonymous; position on disk
                                        is not identity (see artifact_schema)
    unparseable JSON                 -- refused, not crashed on

REFUSED AT THE BATCH LEVEL (a comparison is a claim about a set, not about
each file separately):
    empty batch                      -- "compared zero arms" must not read as
                                        an admission
    duplicate artifact names         -- two paths with one basename silently
                                        collapse into one doc; the caller then
                                        believes it compared N arms and it
                                        compared N-1
    more than one declared experiment -- arms from different experiments are
                                        not each other's controls

This exists because eligibility that lives only in prose gets overridden by
whoever is reading at 2 a.m. with a deadline. Here it is a return code.

DIRECTION OF TRAVEL. Every branch here only ever REFUSES more. No threshold,
seed set, gate verdict or acceptance criterion is set or relaxed by this file;
it decides admissibility of evidence, not what the evidence means.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from artifact_schema import declaration_reasons, doc_fingerprint  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(REPO, "docs", "results")


class Rejected(Exception):
    pass


# The only integrity_status strings this loader understands. Anything else is
# refused rather than interpreted: a status nobody wrote a branch for is not a
# pass, and guessing at "COMPLETE" or "OK" is exactly how UNKNOWN gets upgraded.
RECOGNISED_STATUS = ("QUALIFIED", "UNKNOWN", "VOID", "QUARANTINED")

# A run must declare that it was an evidence-producing run. QUALIFICATION was
# already named; it is not the only non-evidence run kind, and the old code
# admitted every one it had not been told about (SMOKE, PILOT, DRYRUN, ...).
EVIDENCE_RUN_KINDS = ("EXPERIMENT",)


def assess(doc, name="<artifact>", causal=False):
    """Return a list of rejection reasons. Empty means admissible.

    Never raises on a malformed document -- malformed IS the answer."""
    bad = []

    # A non-object cannot carry eligibility. Previously this reached doc.get()
    # and died with AttributeError: a stack trace, not a refusal.
    if not isinstance(doc, dict):
        return ["%s: root is %s, not an object" % (name, type(doc).__name__)]

    # An artifact that cannot describe its own eligibility is not admitted.
    if "integrity_qualified" not in doc and "causal_evidence_eligible" not in doc:
        bad.append("no eligibility fields; artifact cannot prove its status")
        return bad

    status = str(doc.get("integrity_status", "")).upper()
    if status in ("UNKNOWN", ""):
        bad.append("integrity_status=%s (UNKNOWN is never upgraded to PASS)"
                   % (status or "absent"))
    elif status == "VOID":
        bad.append("integrity_status=VOID")
    elif status == "QUARANTINED":
        bad.append("integrity_status=QUARANTINED")
    elif status not in RECOGNISED_STATUS:
        # An unrecognised status used to fall straight through every branch.
        # "FAILED" with integrity_qualified=true was ADMITTED.
        bad.append("integrity_status=%s is not a recognised status (%s); "
                   "unrecognised is not PASS"
                   % (status, ", ".join(RECOGNISED_STATUS)))

    if str(doc.get("status", "")).upper() == "QUARANTINED":
        bad.append("status=QUARANTINED")

    if doc.get("integrity_qualified") is not True and status not in ("VOID",
                                                                     "QUARANTINED"):
        # `is not True` on purpose: the string "true" and the integer 1 are
        # not a qualification, they are a serialisation accident.
        bad.append("integrity_qualified is not true")

    run_kind = str(doc.get("run_kind", "")).upper()
    if run_kind == "QUALIFICATION":
        bad.append("run_kind=QUALIFICATION (qualification is not evidence)")
    elif run_kind == "":
        bad.append("run_kind absent; an artifact must declare that it is an "
                   "evidence run (%s)" % ", ".join(EVIDENCE_RUN_KINDS))
    elif run_kind not in EVIDENCE_RUN_KINDS:
        bad.append("run_kind=%s is not an evidence run kind (%s)"
                   % (run_kind, ", ".join(EVIDENCE_RUN_KINDS)))

    if doc.get("evidence_eligible") is False:
        bad.append("evidence_eligible=false")

    if causal and doc.get("causal_evidence_eligible") is not True:
        # Absent counts. An artifact that never considered causal use has not
        # cleared it, and a missing field is not a quiet yes.
        bad.append("causal analysis requested but causal_evidence_eligible "
                   "is %s, not true"
                   % ("absent" if "causal_evidence_eligible" not in doc
                      else repr(doc.get("causal_evidence_eligible"))))

    return bad


def load_for_comparison(paths, causal=False):
    """Load artifacts for cross-arm comparison, or raise Rejected."""
    docs, problems = {}, {}

    # A comparison over nothing is not a comparison. Returning {} let the CLI
    # print "ADMITTED 0 artifact(s)" with return code 0, which reads as a pass.
    if not paths:
        raise Rejected({"<batch>": ["no artifacts requested; a cross-arm "
                                    "comparison over an empty set is refused"]})

    for p in paths:
        full = p if os.path.isabs(p) else os.path.join(RESULTS, p)
        name = os.path.basename(full)
        # Two paths sharing a basename would collapse into one entry in `docs`
        # and the caller would count arms it never loaded.
        if name in docs or name in problems:
            problems[name] = ["requested more than once (or two paths share "
                              "this basename); refusing an ambiguous batch"]
            docs.pop(name, None)
            continue
        if not os.path.exists(full):
            problems[name] = ["artifact does not exist"]
            continue
        try:
            with open(full, encoding="utf-8") as fh:
                d = json.load(fh)
        except (ValueError, UnicodeDecodeError) as e:
            problems[name] = ["not parseable as JSON (%s)" % e]
            continue
        # IDENTITY BEFORE ELIGIBILITY. Asking whether an artifact is qualified
        # is meaningless until it has said which experiment it belongs to.
        # An anonymous document is refused here rather than assessed on the
        # strength of fields that anyone could have typed into any file.
        bad = declaration_reasons(d, name) + assess(d, name, causal)
        if bad:
            problems[name] = bad
        else:
            docs[name] = d
    # BATCH-LEVEL. Each artifact can be individually admissible and the SET
    # still be an illegitimate comparison. Arms from two different experiments
    # are not each other's controls.
    experiments = sorted({str(d["experiment_id"]).strip()
                          for d in docs.values() if "experiment_id" in d})
    if len(experiments) > 1:
        problems["<batch>"] = ["artifacts declare %d different experiments "
                               "(%s); they are not comparable arms"
                               % (len(experiments), ", ".join(experiments))]

    if problems:
        raise Rejected(problems)
    return docs


# --------------------------------------------------------------- self-test

def selftest():
    n = f = 0

    def ck(label, cond, detail=""):
        nonlocal n, f
        n += 1
        if cond:
            print("  ok   %s" % label)
        else:
            f += 1
            print("  FAIL %s %s" % (label, detail))

    good = {"integrity_status": "QUALIFIED", "integrity_qualified": True,
            "causal_evidence_eligible": True, "run_kind": "EXPERIMENT",
            "experiment_id": "RUNTIME-MEMORY"}

    def rejects(label, mutate, expect, causal=False):
        """Mutate `good`, PROVE the mutation applied, then prove it is refused.

        The applied-check is the same rule as artifact_schema's sabotage
        helper: a mutation that silently no-ops produces a green test that
        witnesses nothing."""
        nonlocal n, f
        d = mutate(dict(good))
        n += 1
        # doc_fingerprint, not ==: `1 == True` would report a real corruption
        # as "never applied". See artifact_schema.doc_fingerprint.
        if doc_fingerprint(d) == doc_fingerprint(good):
            f += 1
            print("  FAIL %s -- SABOTAGE DID NOT APPLY (document unchanged)"
                  % label)
            return
        r = assess(d, causal=causal)
        hit = [x for x in r if expect in x]
        if hit:
            print("  ok   %s -> %s" % (label, hit[0]))
        else:
            f += 1
            print("  FAIL %s -- not refused for %r; got %s" % (label, expect, r))

    print("=== result loader rejection branches ===\n")
    ck("admits a fully qualified artifact", assess(dict(good)) == [],
       str(assess(dict(good))))
    ck("admits it for causal analysis too",
       assess(dict(good), causal=True) == [])

    d = dict(good); d["integrity_status"] = "UNKNOWN"; d["integrity_qualified"] = False
    r = assess(d)
    ck("REJECTS UNKNOWN", any("UNKNOWN" in x for x in r), str(r))

    d = dict(good); d["integrity_status"] = "VOID"; d["integrity_qualified"] = False
    ck("REJECTS VOID", any("VOID" in x for x in assess(d)))

    d = dict(good); d["integrity_status"] = "QUARANTINED"; d["integrity_qualified"] = False
    ck("REJECTS QUARANTINED via integrity_status",
       any("QUARANTINED" in x for x in assess(d)))

    d = dict(good); d["status"] = "QUARANTINED"
    ck("REJECTS QUARANTINED via status field",
       any("status=QUARANTINED" in x for x in assess(d)))

    d = dict(good); d["run_kind"] = "QUALIFICATION"
    ck("REJECTS qualification data",
       any("QUALIFICATION" in x for x in assess(d)))

    d = dict(good); d["evidence_eligible"] = False
    ck("REJECTS evidence_eligible=false",
       any("evidence_eligible=false" in x for x in assess(d)))

    d = dict(good); d["causal_evidence_eligible"] = False
    ck("REJECTS causal request when causal_evidence_eligible=false",
       any("causal" in x for x in assess(d, causal=True)))
    ck("...but permits the same artifact for NON-causal inspection",
       assess(d, causal=False) == [], str(assess(d, causal=False)))

    ck("REJECTS an artifact with no eligibility fields at all",
       assess({"arm": "IDLE"}) == ["no eligibility fields; artifact cannot "
                                   "prove its status"])

    d = dict(good); d.pop("integrity_qualified")
    ck("REJECTS integrity_qualified absent",
       any("integrity_qualified is not true" in x for x in assess(d)))

    # ------------------------------------------------------- ITEM 3 branches
    # Each of these was a hole: a document shaped like this was ADMITTED by the
    # previous loader. A refusal branch with no test is not coverage, so every
    # one below is paired with the sabotage that proves it bites.

    print("\n-- unrecognised status is not a pass")
    rejects("REJECTS an unrecognised integrity_status (FAILED)",
            lambda d: dict(d, integrity_status="FAILED"),
            "not a recognised status")
    rejects("REJECTS a plausible-sounding invented status (COMPLETE)",
            lambda d: dict(d, integrity_status="COMPLETE"),
            "not a recognised status")
    ck("...and the refusal survives integrity_qualified=true, which is the "
       "combination that used to slip through",
       assess(dict(good, integrity_status="FAILED")) != [])

    print("\n-- run_kind must be declared, not merely not-QUALIFICATION")
    rejects("REJECTS an artifact with no run_kind at all",
            lambda d: {k: v for k, v in d.items() if k != "run_kind"},
            "run_kind absent")
    rejects("REJECTS a non-evidence run kind (SMOKE)",
            lambda d: dict(d, run_kind="SMOKE"), "not an evidence run kind")
    rejects("REJECTS a non-evidence run kind (PILOT)",
            lambda d: dict(d, run_kind="PILOT"), "not an evidence run kind")

    print("\n-- truthy is not True")
    rejects("REJECTS integrity_qualified as the STRING 'true'",
            lambda d: dict(d, integrity_qualified="true"),
            "integrity_qualified is not true")
    rejects("REJECTS integrity_qualified as the integer 1",
            lambda d: dict(d, integrity_qualified=1),
            "integrity_qualified is not true")

    print("\n-- causal silence is not causal consent")
    rejects("REJECTS a causal request against a doc with NO causal field",
            lambda d: {k: v for k, v in d.items()
                       if k != "causal_evidence_eligible"},
            "causal_evidence_eligible is absent", causal=True)

    print("\n-- a non-object never reaches doc.get()")
    for root in ([1, 2, 3], "QUALIFIED", 7, None):
        ck("REFUSES a %s root without raising" % type(root).__name__,
           any("not an object" in x for x in assess(root)))

    print("\n-- batch-level refusals")
    try:
        load_for_comparison([])
        ck("REFUSES an empty batch", False, "it returned {} and rc 0")
    except Rejected as e:
        ck("REFUSES an empty batch",
           any("empty set" in x for v in e.args[0].values() for x in v),
           str(e.args[0]))

    import tempfile

    def _tmp(doc):
        fh = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False,
                                         encoding="utf-8")
        json.dump(doc, fh)
        fh.close()
        return fh.name

    tmpfiles = []
    try:
        a = _tmp(dict(good, arm="IDLE"))
        tmpfiles.append(a)
        try:
            load_for_comparison([a, a])
            ck("REFUSES the same artifact requested twice", False,
               "it counted one file as two arms")
        except Rejected as e:
            ck("REFUSES the same artifact requested twice",
               any("more than once" in x
                   for v in e.args[0].values() for x in v), str(e.args[0]))

        # ...and prove the single-file case is still ADMITTED, so the duplicate
        # refusal is about duplication and not about the fixture being bad.
        ck("...while admitting that same artifact once",
           list(load_for_comparison([a])) == [os.path.basename(a)])

        b = _tmp(dict(good, arm="CONTROL", experiment_id="RECOVERY-COUPLING"))
        tmpfiles.append(b)
        try:
            load_for_comparison([a, b])
            ck("REFUSES a batch spanning two experiments", False,
               "it compared arms from different experiments")
        except Rejected as e:
            ck("REFUSES a batch spanning two experiments",
               any("different experiments" in x
                   for v in e.args[0].values() for x in v), str(e.args[0]))

        c = _tmp(dict(good, arm="CONTROL"))
        tmpfiles.append(c)
        ck("...but ADMITS two arms of the SAME experiment",
           len(load_for_comparison([a, c])) == 2)
    finally:
        for p in tmpfiles:
            try:
                os.unlink(p)
            except OSError:
                pass

    # end-to-end refusal, mixed batch
    try:
        load_for_comparison(["__does_not_exist__.json"])
        ck("raises Rejected on a missing artifact", False)
    except Rejected as e:
        ck("raises Rejected on a missing artifact",
           "does not exist" in str(e.args[0]))

    # the real completed arms must currently be refused
    real = ["RUNTIME_MEMORY_IDLE.json", "RUNTIME_MEMORY_CONTROL_WORKLOAD.json",
            "RUNTIME_MEMORY_RECOVERY_ONLY.json", "RUNTIME_MEMORY_FULL_WINDOW.json"]
    present = [r for r in real if os.path.exists(os.path.join(RESULTS, r))]
    if present:
        try:
            load_for_comparison(present)
            ck("REFUSES the completed RUNTIME-MEMORY arms (no eligibility yet)",
               False, "loader admitted them")
        except Rejected as e:
            ck("REFUSES the completed RUNTIME-MEMORY arms (no eligibility yet)",
               len(e.args[0]) == len(present),
               "%d of %d refused" % (len(e.args[0]), len(present)))

    # IDENTITY BRANCHES. Added with the artifact-schema hardening; each is
    # here because a refusal branch with no test is not coverage.
    try:
        load_for_comparison([os.path.join(REPO, "tools", "result_loader.py")])
        ck("REFUSES a file that is not JSON at all", False, "it was admitted")
    except Rejected as e:
        ck("REFUSES a file that is not JSON at all",
           any("not parseable" in x
               for v in e.args[0].values() for x in v), str(e.args[0]))

    if present:
        try:
            load_for_comparison(present)
            ck("refusal of the arms cites their missing identity", False)
        except Rejected as e:
            ck("refusal of the arms cites their missing identity",
               all(any("declares no identity" in x for x in v)
                   for v in e.args[0].values()), str(e.args[0]))

    # the quarantined qwen block must be refused for causal use
    qb = os.path.join(RESULTS, "RC_RUN1_QWEN_BLOCK.json")
    if os.path.exists(qb):
        d = json.load(open(qb, encoding="utf-8"))
        r = assess(d, causal=True)
        ck("REFUSES the quarantined qwen block for causal analysis", bool(r),
           str(r))

    print("\nchecks %d, failures %d" % (n, f))
    print("LOADER GREEN" if f == 0 else "LOADER RED")
    return 0 if f == 0 else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--check", nargs="*", default=[])
    ap.add_argument("--causal", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if a.check:
        try:
            docs = load_for_comparison(a.check, a.causal)
            print("ADMITTED %d artifact(s)" % len(docs))
            return 0
        except Rejected as e:
            print("REFUSED -- cross-arm comparison not permitted")
            for name, reasons in e.args[0].items():
                print("  %s" % name)
                for r in reasons:
                    print("      %s" % r)
            return 1
    ap.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
