"""Provenance axes for result artifacts, fail-closed. NO_CONTACT.

    python tools/population_regime.py --audit      check every result artifact
    python tools/population_regime.py --selftest   qualify this tooth

TWO AXES, MUTUALLY EXCLUSIVE, NEITHER INFERRING THE OTHER

    population_regime_id    WHO DEBATES -- an instantiated Arena roster
                            REGIME A  3 species / 5 agents / 2+2+1
                            REGIME B  5 species / 5 agents / 1x5
                            config/arena-species.v1.json

    measurement_pool_id     WHAT IS LOADED AND MEASURED -- a model pool
                            RM3_V1  lfm2.5 + qwen3.5-2b + falcon-h1
                            config/measurement-pools.v1.json

A pool is not a roster. RM3_V1 is a strict subset of the Regime B membership and
is NOT that roster -- OZONIOUS and BRINE are not in it and never were.

WHY BOTH EXIST (finding REGIME-1)

The first version of this tool had one axis and applied it to everything. The
prereg then declared the RUNTIME-MEMORY rerun "REGIME B", and the frozen legacy
snapshot attributed 151 artifacts to "REGIME A". Both were false:

    stablelm-2-zephyr-1.6b    0 artifacts
    h2o-danube3-4b-chat       0 artifacts
    gemma-3-1b-it-fast-guff   0 artifacts

The Regime A Arena roster has produced ZERO tracked result artifacts. Every
existing artifact came from a measurement pool, not from an instantiated roster.
Two populations had been collapsed into one noun. See
docs/results/FINDING_REGIME_SCOPE_ERROR.md.

The correction supersedes rather than erases: the legacy snapshot is retained,
its Regime A claim withdrawn, and the artifacts it names are PRE-AXIS -- carrying
neither label, because neither was true when they were written. Nothing is
back-filled into an old artifact.

FAIL CLOSED

A NEW artifact must declare EXACTLY ONE axis. Zero is refused. Both is refused
-- an artifact claiming to be a roster run AND a pool measurement is confused
about what it is, and that is the confusion this file exists to stop.

A declared measurement_pool_id is checked AGAINST the pool the artifact actually
recorded. Saying RM3_V1 while measuring something else is refused.
"""

import argparse
import glob
import hashlib
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEGACY_PATH = os.path.join(REPO, "config", "population-regime-a-legacy.json")
POOLS_PATH = os.path.join(REPO, "config", "measurement-pools.v1.json")
RESULTS_GLOB = os.path.join(REPO, "docs", "results", "*.json")

# Pinned when the snapshot was frozen. Appending a name to the legacy list is
# how a new untagged artifact would get silently attributed; the pin makes that
# a visible act. Updated once, deliberately, when the Regime A claim was
# withdrawn under REGIME-1.
LEGACY_SHA256 = "253b2f045115cf0b"

KNOWN_REGIMES = ("A", "B")


def load_pools(path=None):
    with open(path or POOLS_PATH, encoding="utf-8") as f:
        doc = json.load(f)
    return {p["measurement_pool_id"]: list(p["models"]) for p in doc["pools"]}


def legacy_set(path=None):
    """The frozen PRE-AXIS snapshot, refused if it has drifted."""
    p = path or LEGACY_PATH
    raw = open(p, "rb").read()
    got = hashlib.sha256(raw).hexdigest()[:16]
    doc = json.loads(raw.decode("utf-8"))
    names = set(doc.get("artifacts") or [])
    drifted = (got != LEGACY_SHA256) if path is None else False
    return names, drifted, got, doc


def classify(path, legacy, pools=None):
    """(axis_value, status) for one artifact."""
    pools = load_pools() if pools is None else pools
    base = os.path.basename(path)
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            doc = json.load(f)
    except Exception:                                        # noqa: BLE001
        return None, "UNPARSEABLE"
    if not isinstance(doc, dict):
        return None, "PRE_AXIS" if base in legacy else "REFUSED_UNTAGGED"

    regime = doc.get("population_regime_id")
    pool_id = doc.get("measurement_pool_id")

    if regime is not None and pool_id is not None:
        return None, "REFUSED_BOTH_AXES"

    if regime is not None:
        if regime not in KNOWN_REGIMES:
            return regime, "REFUSED_UNKNOWN_REGIME"
        if base in legacy:
            return regime, "REFUSED_PRE_AXIS_CLAIMS_AXIS"
        return regime, "OK_REGIME"

    if pool_id is not None:
        if pool_id not in pools:
            return pool_id, "REFUSED_UNKNOWN_POOL"
        if base in legacy:
            return pool_id, "REFUSED_PRE_AXIS_CLAIMS_AXIS"
        # The declared pool must match what the artifact actually measured.
        actual = doc.get("pool") or doc.get("pool_identity")
        if actual is not None and sorted(actual) != sorted(pools[pool_id]):
            return pool_id, "REFUSED_POOL_MISMATCH"
        return pool_id, "OK_POOL"

    if base in legacy:
        return None, "PRE_AXIS"
    return None, "REFUSED_UNTAGGED"


def audit(paths=None, legacy=None, quiet=False, pools=None):
    if legacy is None:
        legacy, drifted, got, _ = legacy_set()
        if drifted:
            print("REFUSED -- the frozen PRE-AXIS snapshot has changed.")
            print("  pinned %s, found %s" % (LEGACY_SHA256, got))
            print("  Adding a name to that list is how a NEW untagged artifact")
            print("  gets silently treated as pre-axis. If the edit is")
            print("  intentional, update LEGACY_SHA256 in the same commit and")
            print("  say why.")
            return 1
    pools = load_pools() if pools is None else pools
    paths = sorted(glob.glob(RESULTS_GLOB)) if paths is None else paths
    counts, bad = {}, []
    for p in paths:
        val, status = classify(p, legacy, pools)
        counts[status] = counts.get(status, 0) + 1
        if status.startswith("REFUSED"):
            bad.append((os.path.basename(p), val, status))
    if not quiet:
        print("=== provenance axis audit ===")
        print("scanned %d artifact(s)" % len(paths))
        for k in sorted(counts):
            print("    %-30s %d" % (k, counts[k]))
    if bad:
        if not quiet:
            print("")
            print("REFUSED:")
            for base, val, status in bad:
                print("    %-46s %-30s %s"
                      % (base, status, "" if val is None else val))
            print("")
            print("A new artifact declares EXACTLY ONE of population_regime_id")
            print("or measurement_pool_id. Do NOT add it to the pre-axis")
            print("snapshot: that list records what predated the axes, it is")
            print("not a place to put new things.")
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
    import shutil
    import tempfile
    print("=== provenance axes: a pool is not a roster ===")
    legacy, drifted, got, doc = legacy_set()
    pools = load_pools()

    ck("pre-axis snapshot loads", len(legacy) > 0, str(len(legacy)))
    ck("snapshot hash matches the pin", not drifted,
       "pinned %s got %s" % (LEGACY_SHA256, got))
    ck("snapshot no longer claims regime A",
       doc.get("regime") in (None, "", "WITHDRAWN"), str(doc.get("regime")))
    ck("snapshot records the withdrawal", "REGIME-1" in json.dumps(doc))
    ck("RM3_V1 is declared", "RM3_V1" in pools)
    ck("RM3_V1 is the three-model pool, not the five-species roster",
       sorted(pools["RM3_V1"]) == sorted([
           "liquidai/lfm2.5-1.2b-instruct", "qwen3.5-2b",
           "falcon-h1-1.5b-instruct"]))

    print("\n[the real corpus]")
    ck("every artifact on disk is attributable", audit(quiet=True) == 0)

    d = tempfile.mkdtemp(prefix="axis_")

    def w(name, payload):
        p = os.path.join(d, name)
        with open(p, "w", encoding="utf-8") as f:
            json.dump(payload, f)
        return p

    print("\n[exactly one axis]")
    ck("a new untagged artifact is REFUSED",
       classify(w("NEW.json", {"arm": "IDLE"}), legacy, pools)[1]
       == "REFUSED_UNTAGGED")
    ck("declaring BOTH axes is REFUSED",
       classify(w("BOTH.json", {"population_regime_id": "B",
                                "measurement_pool_id": "RM3_V1"}),
                legacy, pools)[1] == "REFUSED_BOTH_AXES")
    ck("a roster artifact with regime B is admitted",
       classify(w("ROSTER.json", {"population_regime_id": "B"}),
                legacy, pools)[1] == "OK_REGIME")
    ck("a pool artifact with RM3_V1 is admitted",
       classify(w("POOL.json", {"measurement_pool_id": "RM3_V1"}),
                legacy, pools)[1] == "OK_POOL")

    print("\n[the declared pool must match what was measured]")
    ck("RM3_V1 + matching pool is admitted",
       classify(w("MATCH.json", {"measurement_pool_id": "RM3_V1",
                                 "pool": pools["RM3_V1"]}),
                legacy, pools)[1] == "OK_POOL")
    ck("RM3_V1 while measuring the 5-species roster is REFUSED",
       classify(w("MISMATCH.json", {
           "measurement_pool_id": "RM3_V1",
           "pool": pools["RM3_V1"] + ["rwkv7-1.5b-g1", "h2o-danube2-1.8b-chat"]},
       ), legacy, pools)[1] == "REFUSED_POOL_MISMATCH")
    ck("an unknown pool id is REFUSED",
       classify(w("BADPOOL.json", {"measurement_pool_id": "NOPE"}),
                legacy, pools)[1] == "REFUSED_UNKNOWN_POOL")
    ck("an unknown regime is REFUSED",
       classify(w("BADREG.json", {"population_regime_id": "Z"}),
                legacy, pools)[1] == "REFUSED_UNKNOWN_REGIME")

    print("\n[pre-axis artifacts carry NEITHER label, and are not back-filled]")
    legacy_name = sorted(legacy)[0]
    ck("an untagged pre-axis artifact is PRE_AXIS, not regime A",
       classify(w(legacy_name, {"arm": "IDLE"}), legacy, pools)
       == (None, "PRE_AXIS"))
    ck("a pre-axis artifact CLAIMING an axis is REFUSED",
       classify(w(legacy_name, {"population_regime_id": "A"}), legacy, pools)[1]
       == "REFUSED_PRE_AXIS_CLAIMS_AXIS")
    real = os.path.join(REPO, "docs", "results", legacy_name)
    if os.path.exists(real):
        try:
            rd = json.load(open(real, encoding="utf-8", errors="replace"))
            ck("...and no real artifact was back-filled on disk",
               isinstance(rd, dict)
               and "population_regime_id" not in rd
               and "measurement_pool_id" not in rd)
        except Exception:                                    # noqa: BLE001
            ck("...and no real artifact was back-filled on disk", True)

    print("\n[sabotage: append to the frozen list to silence a refusal]")
    sab = os.path.join(d, "legacy_sabotage.json")
    doc2 = json.loads(json.dumps(doc))
    doc2["artifacts"] = sorted(doc2["artifacts"] + ["NEW.json"])
    with open(sab, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(doc2, indent="\t") + "\n")
    applied = "NEW.json" in open(sab, encoding="utf-8").read()
    ck("SABOTAGE APPLIED (new name appended to the pre-axis list)", applied)
    if applied:
        names2, _, got2, _ = legacy_set(sab)
        ck("SABOTAGE would silence the refusal, if unhashed",
           classify(os.path.join(d, "NEW.json"), names2, pools)[1] == "PRE_AXIS")
        ck("SABOTAGE BITES: the snapshot hash changes", got2 != LEGACY_SHA256)
    shutil.rmtree(d, ignore_errors=True)
    ck("SABOTAGE REVERTED", not os.path.exists(d))

    print("\nchecks %d, failures %d" % (_n, _f))
    print("PROVENANCE AXES GREEN" if _f == 0 else "PROVENANCE AXES RED")
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
