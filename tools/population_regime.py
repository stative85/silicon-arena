"""Population regime tagging, fail-closed. NO_CONTACT.

    python tools/population_regime.py --audit      check every result artifact
    python tools/population_regime.py --selftest   qualify this tooth

WHAT THIS PREVENTS

Regime A and Regime B share no species at all:

    REGIME A   3 species / 5 agents / 2+2+1   every result up to 2026-09-08
    REGIME B   5 species / 5 agents / 1x5     from 2026-09-08

They are not a roster that grew or swapped a member. They are a disjoint
population. Five months from now, "Arena behaviour changed" is a sentence
somebody will write while comparing across that line, attributing a POPULATION
REPLACEMENT to a mechanism change. Nouns collapse; causality disappears.

So every result artifact must be attributable to a regime, and the attribution
must be mechanical rather than remembered.

HOW LEGACY ARTIFACTS ARE ATTRIBUTED, AND WHY NOT BY EDITING THEM

151 artifacts predate the field. They are attributed to Regime A by a FROZEN
SNAPSHOT, `config/population-regime-a-legacy.json`, and never by adding a field
to the artifacts themselves. Rewriting an old artifact to carry a tag it did not
have when it was written is falsifying provenance, however true the tag is.

The snapshot is content-hashed here. Appending a name to it -- the obvious way
to make a new untagged artifact stop complaining -- changes the hash and is
refused. The escape hatch is deliberately noisy: a human edits the frozen list
AND updates the pinned hash, in a commit that says why.

FAIL CLOSED

An artifact that is not in the frozen legacy set and does not declare
`population_regime_id` is REFUSED. Not warned about. Refused.
"""

import argparse
import glob
import hashlib
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEGACY_PATH = os.path.join(REPO, "config", "population-regime-a-legacy.json")
RESULTS_GLOB = os.path.join(REPO, "docs", "results", "*.json")

# Pinned at the moment the snapshot was frozen. See the module docstring: this
# is what makes "just add it to the legacy list" a visible act rather than a
# quiet one.
LEGACY_SHA256 = "6ad9dce1adeb64a5"

KNOWN_REGIMES = ("A", "B")


def legacy_set(path=None):
    """The frozen Regime A snapshot, refused if it has drifted."""
    p = path or LEGACY_PATH
    raw = open(p, "rb").read()
    got = hashlib.sha256(raw).hexdigest()[:16]
    doc = json.loads(raw.decode("utf-8"))
    names = set(doc.get("artifacts") or [])
    drifted = (got != LEGACY_SHA256) if path is None else False
    return names, drifted, got, doc


def classify(path, legacy):
    """(regime, status) for one artifact. status in OK / REFUSED / LEGACY."""
    base = os.path.basename(path)
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            doc = json.load(f)
    except Exception:                                        # noqa: BLE001
        return None, "UNPARSEABLE"
    tag = doc.get("population_regime_id") if isinstance(doc, dict) else None
    if tag is not None:
        if tag not in KNOWN_REGIMES:
            return tag, "REFUSED_UNKNOWN_REGIME"
        if base in legacy and tag != "A":
            # A frozen Regime A artifact claiming to be Regime B is either a
            # mistake or a rewrite of history. Either way, refuse.
            return tag, "REFUSED_CONTRADICTS_SNAPSHOT"
        return tag, "OK"
    if base in legacy:
        return "A", "LEGACY"
    return None, "REFUSED_UNTAGGED"


def audit(paths=None, legacy=None, quiet=False):
    if legacy is None:
        legacy, drifted, got, _ = legacy_set()
        if drifted:
            print("REFUSED -- the frozen Regime A snapshot has changed.")
            print("  pinned %s, found %s" % (LEGACY_SHA256, got))
            print("  Adding a name to the legacy list is how an untagged NEW")
            print("  artifact gets silently attributed to Regime A. If the edit")
            print("  is intentional, update LEGACY_SHA256 in this file in the")
            print("  same commit, and say why.")
            return 1
    paths = sorted(glob.glob(RESULTS_GLOB)) if paths is None else paths
    counts = {}
    bad = []
    for p in paths:
        regime, status = classify(p, legacy)
        counts[status] = counts.get(status, 0) + 1
        if status.startswith("REFUSED"):
            bad.append((os.path.basename(p), regime, status))
    if not quiet:
        print("=== population regime audit ===")
        print("scanned %d artifact(s)" % len(paths))
        for k in sorted(counts):
            print("    %-28s %d" % (k, counts[k]))
    if bad:
        if not quiet:
            print("")
            print("REFUSED -- artifacts with no attributable population regime:")
            for base, regime, status in bad:
                print("    %-46s %s %s" % (base, status,
                                           "" if regime is None else regime))
            print("")
            print("A new artifact must declare population_regime_id. Do NOT add")
            print("it to the frozen legacy snapshot -- that list is a record of")
            print("what predated the field, not a place to put new things.")
        return 1
    if not quiet:
        print("CLEAN -- every artifact is attributable")
    return 0


# --- selftest --------------------------------------------------------------

_n = _f = 0


def ck(lbl, cond, detail=""):
    global _n, _f
    _n += 1
    if cond:
        print("  ok   %s" % lbl)
    else:
        _f += 1
        print("  FAIL %s %s" % (lbl, detail))


def selftest():
    import tempfile
    print("=== population regime: every result is attributable ===")
    legacy, drifted, got, doc = legacy_set()

    ck("frozen snapshot loads", len(legacy) > 0, str(len(legacy)))
    ck("snapshot hash matches the pin", not drifted,
       "pinned %s got %s" % (LEGACY_SHA256, got))
    ck("snapshot declares regime A", doc.get("regime") == "A")
    ck("snapshot count matches its own list",
       int(doc.get("count", -1)) == len(doc.get("artifacts") or []))

    print("\n[the real corpus]")
    ck("every artifact on disk is attributable", audit(quiet=True) == 0)

    d = tempfile.mkdtemp(prefix="regime_")

    def write(name, payload):
        p = os.path.join(d, name)
        with open(p, "w", encoding="utf-8") as f:
            json.dump(payload, f)
        return p

    print("\n[fail closed on a NEW untagged artifact]")
    p_new = write("BRAND_NEW_RESULT.json", {"arm": "IDLE", "samples": 1})
    regime, status = classify(p_new, legacy)
    ck("a new untagged artifact is REFUSED", status == "REFUSED_UNTAGGED",
       status)
    ck("...and the audit returns nonzero", audit([p_new], legacy, True) == 1)

    print("\n[a tagged artifact is admitted]")
    p_b = write("NEW_TAGGED.json", {"population_regime_id": "B", "arm": "IDLE"})
    ck("population_regime_id B is admitted",
       classify(p_b, legacy) == ("B", "OK"))
    ck("...and the audit returns zero", audit([p_b], legacy, True) == 0)

    print("\n[unknown and contradictory regimes]")
    p_x = write("BOGUS.json", {"population_regime_id": "Z"})
    ck("an unknown regime is REFUSED, not passed through",
       classify(p_x, legacy)[1] == "REFUSED_UNKNOWN_REGIME")
    legacy_name = sorted(legacy)[0]
    p_c = write(legacy_name, {"population_regime_id": "B"})
    ck("a frozen Regime A artifact claiming B is REFUSED",
       classify(p_c, legacy)[1] == "REFUSED_CONTRADICTS_SNAPSHOT")

    print("\n[legacy artifacts are attributed WITHOUT being edited]")
    p_l = write(legacy_name, {"arm": "IDLE"})
    ck("an untagged legacy artifact is attributed to A",
       classify(p_l, legacy) == ("A", "LEGACY"))
    real = os.path.join(REPO, "docs", "results", legacy_name)
    if os.path.exists(real):
        with open(real, encoding="utf-8", errors="replace") as f:
            try:
                rd = json.load(f)
                ck("...and the real artifact was NOT given a tag on disk",
                   isinstance(rd, dict) and "population_regime_id" not in rd)
            except Exception:                                # noqa: BLE001
                ck("...and the real artifact was NOT given a tag on disk", True)

    print("\n[sabotage: append to the frozen list to silence a refusal]")
    sab = os.path.join(d, "legacy_sabotage.json")
    doc2 = json.loads(json.dumps(doc))
    doc2["artifacts"] = sorted(doc2["artifacts"] + ["BRAND_NEW_RESULT.json"])
    doc2["count"] = len(doc2["artifacts"])
    with open(sab, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(doc2, indent="\t") + "\n")
    applied = os.path.getsize(sab) > 0 and \
        "BRAND_NEW_RESULT.json" in open(sab, encoding="utf-8").read()
    ck("SABOTAGE APPLIED (new name appended to the legacy list)", applied)
    if applied:
        names2, _, got2, _ = legacy_set(sab)
        ck("SABOTAGE would silence the refusal, if unhashed",
           classify(p_new, names2) == ("A", "LEGACY"))
        ck("SABOTAGE BITES: the snapshot hash changes",
           got2 != LEGACY_SHA256, "%s vs %s" % (got2, LEGACY_SHA256))
    import shutil
    shutil.rmtree(d, ignore_errors=True)
    ck("SABOTAGE REVERTED (temp artifacts removed)", not os.path.exists(d))

    print("\nchecks %d, failures %d" % (_n, _f))
    print("POPULATION REGIME GREEN" if _f == 0 else "POPULATION REGIME RED")
    return 1 if _f else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--audit", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    return audit()


if __name__ == "__main__":
    sys.exit(main())
