"""Artifact schema teeth. An artifact must DECLARE what it is, or be refused.

    python tools/artifact_schema.py --selftest
    python tools/artifact_schema.py --check docs/results/RUNTIME_MEMORY_IDLE.json

WHY THIS EXISTS. Static audit ITEM 1 recorded BC-5: `backend_continuity.py`
reads `docs/results/RUNTIME_MEMORY_*.json` with hard indexing -- `d["samples"]`,
`d["problems"]`, `x["backend_pids"]` -- and checks nothing about what the file
claims to be. A file at the expected path that is not what it claims raises
`KeyError`: a stack trace, not a refusal. And the skew is not hypothetical. The
four arm artifacts on disk are an OLDER schema than the current writer emits:
no `experiment_id`, no `run_kind`, no `integrity_status`. A consumer that trusts
the path instead of the content is one filename away from analysing the wrong
experiment and never being told.

THE RULE. Position on disk is not identity. A result may depend on an artifact
only if the artifact says, inside itself, which experiment it belongs to and
which arm it is -- and only if that agrees with the path it was found at.
Absence of a declaration is a REFUSAL, not a default.

WHAT THIS DOES NOT DO. It does not decide whether evidence is admissible; that
is `result_loader.py`, which asks about integrity status and eligibility. This
module asks the strictly earlier question: is this file the thing we think it
is. A document can pass every check here and still be VOID.

NO THRESHOLD IS SET HERE. The `frozen` block does not choose ks/kh/n -- it
refuses an artifact that declares values DIFFERENT from the preregistered
1.8 / 20 / 3. Enforcing a freeze is not the same act as setting one.
"""

import argparse
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(REPO, "docs", "results")

# Preregistered and frozen. Listed here to be ENFORCED, never to be chosen.
FROZEN = {"ks": 1.8, "kh": 20.0, "n": 3}


class SchemaRefused(Exception):
    """Raised instead of KeyError when an artifact is not what it claims."""


# --------------------------------------------------------------- the registry
#
# declares    field -> the literal the artifact must carry. This is the
#             identity claim. Missing field = refused; wrong value = refused.
# required    field -> accepted python type(s).
# nonempty    fields that must not be empty once present.
# rows        (list field, {row field -> type}) applied to every element.
# frozen      True = if the artifact declares any FROZEN key, it must match.
# path        regex over the basename with one group; the group must equal
#             the value of `path_field`. Content and location must agree.

KINDS = {
    "RUNTIME_MEMORY_ARM": {
        "declares": {"experiment_id": "RUNTIME-MEMORY"},
        "required": {"arm": str, "samples": list, "problems": list,
                     "windows": int},
        "nonempty": ["arm", "samples"],
        "rows": ("samples", {"backend_pids": list}),
        "frozen": True,
        "path": (r"^RUNTIME_MEMORY_(.+)\.json$", "arm"),
    },
    "RUNTIME_MEMORY_RESULTS": {
        "declares": {"experiment_id": "RUNTIME-MEMORY"},
        "required": {"arms": dict},
        "nonempty": ["arms"],
        "frozen": True,
    },
    "RM_BACKEND_CONTINUITY": {
        "declares": {"artifact_kind": "RM_BACKEND_CONTINUITY",
                     "experiment_id": "RUNTIME-MEMORY"},
        "required": {"arms": dict, "produced_by": str},
        "nonempty": ["arms"],
    },
    "RC_QWEN_BLOCK_LABEL": {
        "declares": {"block_id": "RC_RUN1_QWEN_BLOCK"},
        "required": {"status": str, "causal_evidence_eligible": bool,
                     "admissibility_criterion": dict},
    },
}

# Any artifact a result depends on must carry at least one of these. A file
# that names no experiment and no block is anonymous, and anonymous evidence is
# refused on sight.
DECLARATION_KEYS = ("experiment_id", "artifact_kind", "block_id")


def _typename(t):
    return "/".join(x.__name__ for x in t) if isinstance(t, tuple) else t.__name__


def validate(doc, kind, path=None):
    """Return a list of refusal reasons. Empty means the artifact is what it
    claims to be. Never raises on malformed input -- malformed IS the answer."""
    if kind not in KINDS:
        return ["unknown artifact kind %r; refusing rather than guessing" % kind]
    spec = KINDS[kind]
    bad = []

    if not isinstance(doc, dict):
        return ["artifact root is %s, not an object" % type(doc).__name__]

    # 1. identity claim
    for field, want in spec["declares"].items():
        if field not in doc:
            bad.append("does not declare %s; expected %s=%r" % (field, field, want))
        elif str(doc[field]).strip().upper() != str(want).upper():
            bad.append("declares %s=%r but this consumer requires %r"
                       % (field, doc[field], want))

    # 2. structure the consumers hard-index
    for field, typ in spec.get("required", {}).items():
        if field not in doc:
            bad.append("missing required field %r (%s)" % (field, _typename(typ)))
        elif not isinstance(doc[field], typ) or isinstance(doc[field], bool) != (
                typ is bool):
            bad.append("field %r is %s, expected %s"
                       % (field, type(doc[field]).__name__, _typename(typ)))

    for field in spec.get("nonempty", []):
        if field in doc and not isinstance(doc[field], bool) and not doc[field]:
            bad.append("field %r is present but empty" % field)

    # 3. rows -- one bad row refuses the artifact; a consumer that iterates
    #    samples must not discover row 40 is malformed at row 40.
    if "rows" in spec:
        lf, rowspec = spec["rows"]
        rows = doc.get(lf)
        if isinstance(rows, list):
            for i, row in enumerate(rows):
                if not isinstance(row, dict):
                    bad.append("%s[%d] is %s, not an object"
                               % (lf, i, type(row).__name__))
                    continue
                for rk, rt in rowspec.items():
                    if rk not in row:
                        bad.append("%s[%d] missing %r" % (lf, i, rk))
                    elif not isinstance(row[rk], rt):
                        bad.append("%s[%d].%s is %s, expected %s"
                                   % (lf, i, rk, type(row[rk]).__name__,
                                      _typename(rt)))

    # 4. the freeze is enforced, not chosen
    if spec.get("frozen"):
        for k, want in FROZEN.items():
            if k not in doc:
                continue
            try:
                same = float(doc[k]) == float(want)
            except (TypeError, ValueError):
                same = False           # unreadable is not equal
            if not same:
                bad.append("declares %s=%r but the preregistered value is %r"
                           % (k, doc[k], want))

    # 5. content must agree with location
    if path and "path" in spec:
        rx, field = spec["path"]
        m = re.match(rx, os.path.basename(path))
        if m and field in doc and str(doc[field]).strip() != m.group(1):
            bad.append("found at %s but declares %s=%r; path and content "
                       "disagree" % (os.path.basename(path), field, doc[field]))

    return bad


def declaration_reasons(doc, name="<artifact>"):
    """The weak, kind-agnostic check: does this file say what it is at all?"""
    if not isinstance(doc, dict):
        return ["%s: root is %s, not an object" % (name, type(doc).__name__)]
    if not any(k in doc for k in DECLARATION_KEYS):
        return ["%s: declares no identity (none of %s); anonymous evidence "
                "is refused" % (name, ", ".join(DECLARATION_KEYS))]
    return []


def load_checked(path, kind):
    """Load an artifact or raise SchemaRefused. The only sanctioned way for a
    result-bearing consumer to open one of these files."""
    if not os.path.exists(path):
        raise SchemaRefused("%s: does not exist" % os.path.basename(path))
    try:
        with open(path, encoding="utf-8") as fh:
            doc = json.load(fh)
    except (ValueError, UnicodeDecodeError) as e:
        raise SchemaRefused("%s: not parseable as JSON (%s)"
                            % (os.path.basename(path), e))
    bad = validate(doc, kind, path)
    if bad:
        raise SchemaRefused("%s: %s" % (os.path.basename(path), "; ".join(bad)))
    return doc


# ------------------------------------------------------------------ self-test

def _good_arm():
    return {
        "experiment_id": "RUNTIME-MEMORY", "arm": "IDLE", "run_kind": "EXPERIMENT",
        "windows": 40, "problems": [],
        "ks": 1.8, "kh": 20.0, "n": 3,
        "samples": [{"backend_pids": [1, 2, 3], "phase": "arm_start"},
                    {"backend_pids": [1, 2, 4], "phase": "final_live_client"}],
    }


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

    def sabotage(label, mutate, expect, kind="RUNTIME_MEMORY_ARM", path=None):
        """Apply a mutation, PROVE it applied, then prove the schema refuses.

        A sabotage that silently failed to apply is a green test that proves
        nothing. The applied-check is not ceremony: it is the difference
        between 'the tooth bit' and 'nothing happened and we called it a pass'.
        """
        nonlocal n, f
        base = _good_arm()
        d = mutate(_good_arm())
        n += 1
        if d == base:
            f += 1
            print("  FAIL %s -- SABOTAGE DID NOT APPLY (document unchanged)"
                  % label)
            return
        r = validate(d, kind, path)
        hit = [x for x in r if expect in x]
        if hit:
            print("  ok   %s -> %s" % (label, hit[0]))
        else:
            f += 1
            print("  FAIL %s -- not refused for %r; got %s" % (label, expect, r))

    print("=== artifact schema: identity is claimed, not assumed ===\n")

    # positive control. If this ever fails, every refusal below is vacuous.
    r = validate(_good_arm(), "RUNTIME_MEMORY_ARM",
                 "docs/results/RUNTIME_MEMORY_IDLE.json")
    ck("ADMITS a well-formed, self-declaring arm artifact", r == [], str(r))

    print("\n-- identity")
    sabotage("REFUSES an artifact that declares no experiment",
             lambda d: (d.pop("experiment_id"), d)[1], "does not declare")
    sabotage("REFUSES an artifact from a DIFFERENT experiment",
             lambda d: dict(d, experiment_id="RECOVERY-COUPLING"),
             "this consumer requires")
    sabotage("REFUSES a mislabelled arm at a correct-looking path",
             lambda d: dict(d, arm="CONTROL_WORKLOAD"),
             "path and content disagree",
             path="docs/results/RUNTIME_MEMORY_IDLE.json")
    ck("...and does NOT refuse that same doc when no path is asserted",
       validate(dict(_good_arm(), arm="CONTROL_WORKLOAD"),
                "RUNTIME_MEMORY_ARM") == [])

    print("\n-- structure the consumers hard-index (BC-5)")
    sabotage("REFUSES a missing samples list",
             lambda d: (d.pop("samples"), d)[1], "missing required field")
    sabotage("REFUSES samples that are not a list",
             lambda d: dict(d, samples={"0": {}}), "expected list")
    sabotage("REFUSES an empty samples list",
             lambda d: dict(d, samples=[]), "present but empty")
    sabotage("REFUSES a missing problems list",
             lambda d: (d.pop("problems"), d)[1], "missing required field")
    sabotage("REFUSES a sample row that is not an object",
             lambda d: dict(d, samples=d["samples"] + ["oops"]),
             "not an object")
    sabotage("REFUSES a sample row missing backend_pids",
             lambda d: dict(d, samples=d["samples"] + [{"phase": "x"}]),
             "missing 'backend_pids'")
    sabotage("REFUSES backend_pids of the wrong type",
             lambda d: dict(d, samples=[dict(d["samples"][0],
                                             backend_pids="1,2,3")]),
             "expected list")
    sabotage("REFUSES windows declared as a string",
             lambda d: dict(d, windows="40"), "expected int")

    print("\n-- the freeze is enforced, not chosen")
    sabotage("REFUSES an artifact declaring ks != 1.8",
             lambda d: dict(d, ks=2.5), "preregistered value")
    sabotage("REFUSES an artifact declaring kh != 20",
             lambda d: dict(d, kh=15.0), "preregistered value")
    sabotage("REFUSES an artifact declaring n != 3",
             lambda d: dict(d, n=5), "preregistered value")

    print("\n-- root and kind")
    ck("REFUSES a JSON array as an artifact root",
       any("not an object" in x
           for x in validate([1, 2, 3], "RUNTIME_MEMORY_ARM")))
    ck("REFUSES a JSON string as an artifact root",
       any("not an object" in x
           for x in validate("qualified", "RUNTIME_MEMORY_ARM")))
    ck("REFUSES an unknown kind rather than guessing",
       any("unknown artifact kind" in x
           for x in validate(_good_arm(), "SOMETHING_INVENTED")))

    print("\n-- kind-agnostic declaration check (used by result_loader)")
    ck("REFUSES an anonymous document",
       declaration_reasons({"integrity_qualified": True}) != [])
    ck("ADMITS a document that names its experiment",
       declaration_reasons({"experiment_id": "RUNTIME-MEMORY"}) == [])
    ck("ADMITS a document that names its block",
       declaration_reasons({"block_id": "RC_RUN1_QWEN_BLOCK"}) == [])

    print("\n-- load_checked refuses files, not just dicts")
    try:
        load_checked(os.path.join(RESULTS, "__no_such_artifact__.json"),
                     "RUNTIME_MEMORY_ARM")
        ck("REFUSES a missing file", False)
    except SchemaRefused as e:
        ck("REFUSES a missing file", "does not exist" in str(e))
    try:
        load_checked(os.path.join(REPO, "tools", "artifact_schema.py"),
                     "RUNTIME_MEMORY_ARM")
        ck("REFUSES a file that is not JSON", False)
    except SchemaRefused as e:
        ck("REFUSES a file that is not JSON", "not parseable as JSON" in str(e))

    print("\n-- the artifacts actually on disk")
    # This is not a hypothetical. The four arm artifacts predate the current
    # writer, so they carry no experiment_id. They MUST be refused, and the
    # refusal is the evidence for RM-1's conclusion that no arm has ever run
    # against the corrected harness. Nothing here rewrites them.
    for arm in ["IDLE", "CONTROL_WORKLOAD", "RECOVERY_ONLY", "FULL_WINDOW"]:
        p = os.path.join(RESULTS, "RUNTIME_MEMORY_%s.json" % arm)
        if not os.path.exists(p):
            continue
        try:
            load_checked(p, "RUNTIME_MEMORY_ARM")
            ck("REFUSES old-schema %s (undeclared)" % arm, False,
               "it was ADMITTED -- schema skew has closed; re-read this test")
        except SchemaRefused as e:
            ck("REFUSES old-schema %s (undeclared)" % arm,
               "does not declare experiment_id" in str(e), str(e)[:120])

    qb = os.path.join(RESULTS, "RC_RUN1_QWEN_BLOCK.json")
    if os.path.exists(qb):
        try:
            load_checked(qb, "RC_QWEN_BLOCK_LABEL")
            ck("ADMITS the qwen block label as a self-declaring label", True)
        except SchemaRefused as e:
            ck("ADMITS the qwen block label as a self-declaring label", False,
               str(e)[:160])

    print("\nchecks %d, failures %d" % (n, f))
    print("SCHEMA GREEN" if f == 0 else "SCHEMA RED")
    return 0 if f == 0 else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--check", nargs="*", default=[])
    ap.add_argument("--kind", default="RUNTIME_MEMORY_ARM")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if a.check:
        rc = 0
        for p in a.check:
            full = p if os.path.isabs(p) else os.path.join(REPO, p)
            try:
                load_checked(full, a.kind)
                print("OK       %s" % os.path.basename(full))
            except SchemaRefused as e:
                rc = 1
                print("REFUSED  %s" % e)
        return rc
    ap.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
