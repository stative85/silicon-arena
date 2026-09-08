"""Arena display names. PRESENTATION ONLY, one-way, fail-closed. NO_CONTACT.

    python tools/arena_names.py              show the roster
    python tools/arena_names.py --audit      scan artifacts for contamination
    python tools/arena_names.py --selftest   qualify this tooth

WHY THIS FILE IS SHAPED LIKE THIS

`qwen3.5-2b` is a correct identity and an unreadable one. Once model names reach
logs, replays, screenshots and arena lore, an operator reads them constantly and
a serial number costs attention every time. So the arena gets a roster:

    VANTA  KESTREL  GEMMATRON  OZONIOUS  BRINE

The names are deliberately SEMANTICALLY NEUTRAL. No Scout, Builder, Strategist,
Judge. A role-flavoured name assigns specialisation before any agent has earned
it, and would then be quoted back as evidence for the specialisation it caused.
These names mean nothing on purpose.

THE INVARIANT, AND WHY IT IS ONE-WAY

    display_name is a LABEL. model_id and species_id are IDENTITY.

The map runs in exactly one direction: `display_for(model_id)`. There is
deliberately NO supported path from a display name back into provenance. A
pretty name that could be resolved into an identity is a pretty name that can
contaminate one -- rename a model, or reuse a name across checkpoints, and every
artifact that resolved through it silently re-points. So provenance never reads
this file, and `--audit` proves no artifact on disk carries a display name in an
identity field.

FAIL CLOSED

An unknown model_id gets NO NAME. It does not get a guess, a title-cased
derivation, or a nearest match. `tools/build_roster.gd` already demonstrates the
alternative: mechanically title-casing an id produced "H 2o Danube 3 4B #1",
which is both ugly and, more importantly, an invented string presented with the
same confidence as a real one.

CARDINALITY IS STATE (Law 5)

LM Studio can hold `qwen3.5-2b` and `qwen3.5-2b:2` at the same time. They are
one species and two instances. Display distinguishes them (`GEMMATRON:2`);
species does not. Residency is a COUNT MAP, never set membership, and nothing
here may be used to collapse two instances into one because they render alike.
"""

import argparse
import glob
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAMES_PATH = os.path.join(REPO, "config", "arena-names.v1.json")

# Fields that carry IDENTITY. A display name appearing in any of them is
# contamination, not decoration.
PROVENANCE_FIELDS = (
    "model_id", "model_key", "modelKey", "species_id", "model",
    "base_model", "checkpoint", "runtime_model",
)

# An instance suffix: "qwen3.5-2b:2" is instance 2 of the same species.
INSTANCE_RE = re.compile(r"^(?P<base>.+?):(?P<n>\d+)$")


def load(path=None):
    with open(path or NAMES_PATH, encoding="utf-8") as f:
        doc = json.load(f)
    if int(doc.get("schema_version", 0)) != 1:
        raise ValueError("arena-names: unsupported schema_version %r"
                         % doc.get("schema_version"))
    rows = doc.get("names") or []
    seen_ids, seen_names = set(), set()
    for r in rows:
        for k in ("display_name", "model_id", "species_id"):
            if not str(r.get(k, "")).strip():
                raise ValueError("arena-names: row missing %s: %r" % (k, r))
        if r["model_id"] in seen_ids:
            raise ValueError("arena-names: duplicate model_id %r" % r["model_id"])
        if r["display_name"] in seen_names:
            # Two models sharing a display name is the ambiguity this whole
            # file exists to prevent. Refuse the roster rather than render it.
            raise ValueError("arena-names: duplicate display_name %r"
                             % r["display_name"])
        seen_ids.add(r["model_id"])
        seen_names.add(r["display_name"])
    return rows


def split_instance(model_ref):
    """('qwen3.5-2b:2') -> ('qwen3.5-2b', 2). No suffix -> (ref, 1)."""
    m = INSTANCE_RE.match(str(model_ref))
    if not m:
        return str(model_ref), 1
    return m.group("base"), int(m.group("n"))


def display_for(model_ref, rows=None):
    """Label for a model reference, or None. NEVER invents one.

    Returning None is the correct, useful answer for an unnamed model: the
    caller renders the raw id, which is ugly and true, instead of a plausible
    string that is pretty and made up.
    """
    rows = load() if rows is None else rows
    base, inst = split_instance(model_ref)
    for r in rows:
        if r["model_id"] == base:
            return r["display_name"] if inst == 1 else "%s:%d" % (
                r["display_name"], inst)
    return None


def species_for(model_ref, rows=None):
    """species_id for a model reference, or None. Instance-independent."""
    rows = load() if rows is None else rows
    base, _ = split_instance(model_ref)
    for r in rows:
        if r["model_id"] == base:
            return r["species_id"]
    return None


def label(model_ref, rows=None):
    """What a log line should print: the name if known, else the raw id."""
    return display_for(model_ref, rows) or str(model_ref)


# --- contamination audit ---------------------------------------------------

def audit_paths(paths, rows=None):
    """Find display names sitting in identity fields. Returns list of hits.

    This is the tooth that keeps the mapping one-way in practice rather than
    in prose. It reads artifacts as DATA and reports; it never edits them.
    """
    rows = load() if rows is None else rows
    names = {r["display_name"] for r in rows}
    hits = []

    def walk(node, path, src):
        if isinstance(node, dict):
            for k, v in node.items():
                if k in PROVENANCE_FIELDS and isinstance(v, str):
                    base, _ = split_instance(v)
                    if base in names:
                        hits.append((src, "%s.%s" % (path, k) if path else k, v))
                walk(v, "%s.%s" % (path, k) if path else k, src)
        elif isinstance(node, list):
            for i, v in enumerate(node):
                walk(v, "%s[%d]" % (path, i), src)

    for p in paths:
        try:
            with open(p, encoding="utf-8", errors="replace") as f:
                doc = json.load(f)
        except Exception:                                    # noqa: BLE001
            continue          # unparseable artifacts are not this tooth's job
        walk(doc, "", os.path.relpath(p, REPO).replace("\\", "/"))
    return hits


def audit(rows=None):
    paths = sorted(glob.glob(os.path.join(REPO, "docs", "results", "*.json"))
                   + glob.glob(os.path.join(REPO, "config", "*.json")))
    hits = audit_paths(paths, rows)
    print("=== display-name contamination audit ===")
    print("scanned %d artifact(s) for %d display name(s) in %d identity field(s)"
          % (len(paths), len(load() if rows is None else rows),
             len(PROVENANCE_FIELDS)))
    if hits:
        print("")
        print("CONTAMINATED -- a display name is being used as an identity:")
        for src, where, val in hits:
            print("    %-52s %s = %r" % (src, where, val))
        print("")
        print("A label was written where provenance belongs. Fix the PRODUCER;")
        print("do not add the display name to the identity vocabulary.")
        return 1
    print("CLEAN -- no display name appears in any identity field")
    return 0


# --- selftest --------------------------------------------------------------

_n = _f = 0


def ck(label_, cond, detail=""):
    global _n, _f
    _n += 1
    if cond:
        print("  ok   %s" % label_)
    else:
        _f += 1
        print("  FAIL %s %s" % (label_, detail))


def selftest():
    global _f
    print("=== arena names: label != identity ===")
    rows = load()

    ck("roster loads with 5 names", len(rows) == 5, str(len(rows)))
    expect = ["VANTA", "KESTREL", "GEMMATRON", "OZONIOUS", "BRINE"]
    ck("roster is VANTA/KESTREL/GEMMATRON/OZONIOUS/BRINE",
       [r["display_name"] for r in rows] == expect,
       str([r["display_name"] for r in rows]))

    print("\n[the map runs one way]")
    ck("display_for(qwen3.5-2b) is GEMMATRON",
       display_for("qwen3.5-2b", rows) == "GEMMATRON")
    ck("species_for(qwen3.5-2b) is qwen35",
       species_for("qwen3.5-2b", rows) == "qwen35")
    ck("there is no reverse resolver in this module",
       not any(n.startswith(("model_for", "id_for", "resolve_display"))
               for n in globals()))

    print("\n[fail closed: an unknown model gets NO name]")
    for unknown in ("gpt-2-xl", "qwen3-8b", "", "GEMMATRON"):
        ck("display_for(%r) is None" % unknown,
           display_for(unknown, rows) is None, str(display_for(unknown, rows)))
    ck("label() falls back to the raw id, ugly and true",
       label("gpt-2-xl", rows) == "gpt-2-xl")
    # A display name must not resolve as if it were an id -- that is the
    # round-trip this design forbids, checked rather than asserted.
    ck("a display name is not itself a resolvable id",
       species_for("GEMMATRON", rows) is None)

    print("\n[cardinality is state: an instance is not a species]")
    ck("qwen3.5-2b:2 displays as GEMMATRON:2",
       display_for("qwen3.5-2b:2", rows) == "GEMMATRON:2")
    ck("qwen3.5-2b:2 is the SAME species",
       species_for("qwen3.5-2b:2", rows) == "qwen35")
    ck("the two instances do NOT render identically",
       display_for("qwen3.5-2b", rows) != display_for("qwen3.5-2b:2", rows))
    ck("split_instance keeps the base id intact",
       split_instance("qwen3.5-2b:2") == ("qwen3.5-2b", 2))
    ck("a bare id is instance 1", split_instance("rwkv7-1.5b-g1")[1] == 1)

    print("\n[the roster refuses ambiguity]")
    import copy
    dup = copy.deepcopy(rows)
    dup[1]["display_name"] = "GEMMATRON"          # two models, one name
    tmp = os.path.join(REPO, "docs", "night", "_names_dup.json")
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"schema_version": 1, "names": dup}, f)
        try:
            load(tmp)
            ck("duplicate display_name is refused", False, "it was accepted")
        except ValueError as e:
            ck("duplicate display_name is refused", "duplicate" in str(e))
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)

    print("\n[contamination audit, on the real artifacts]")
    rc = audit(rows)
    ck("no artifact on disk uses a display name as identity", rc == 0)

    print("\n[sabotage: would the audit notice?]")
    # SABOTAGE -- write a document that puts a display name exactly where
    # provenance belongs, and require the auditor to catch it. An auditor that
    # has only ever seen clean data has proven nothing.
    tmp = os.path.join(REPO, "docs", "night", "_names_sabotage.json")
    payload = {"experiment_id": "FAKE",
               "arms": [{"model_id": "GEMMATRON", "samples": 1}]}
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(payload, f)
        applied = os.path.exists(tmp)
        ck("SABOTAGE APPLIED (contaminated artifact written)", applied)
        if applied:
            hits = audit_paths([tmp], rows)
            ck("SABOTAGE BITES: the audit finds the planted name",
               len(hits) == 1 and hits[0][2] == "GEMMATRON", str(hits))
            ck("...and names the exact field",
               bool(hits) and hits[0][1].endswith("model_id"), str(hits))
        # instance-suffixed contamination must also be caught
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"model_key": "GEMMATRON:2"}, f)
        ck("SABOTAGE BITES on an instance-suffixed name",
           len(audit_paths([tmp], rows)) == 1)
        # a legitimate id in the same field must NOT be flagged
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"model_id": "qwen3.5-2b"}, f)
        ck("the audit does NOT flag a legitimate model_id",
           audit_paths([tmp], rows) == [])
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
        ck("SABOTAGE REVERTED (temp artifact removed)",
           not os.path.exists(tmp))

    print("\nchecks %d, failures %d" % (_n, _f))
    print("ARENA NAMES GREEN" if _f == 0 else "ARENA NAMES RED")
    return 1 if _f else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--audit", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if a.audit:
        return audit()
    rows = load()
    print("=== ARENA ROSTER ===")
    print("%-12s %-32s %s" % ("DISPLAY", "MODEL_ID", "SPECIES_ID"))
    for r in rows:
        print("%-12s %-32s %s"
              % (r["display_name"], r["model_id"], r["species_id"]))
    print("")
    print("display_name is a label. model_id and species_id are identity.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
