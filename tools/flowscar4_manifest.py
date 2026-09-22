#!/usr/bin/env python3
"""Seal the FLOWSCAR4 run manifest, or refuse.

    python tools/flowscar4_manifest.py --out scratch/flowscar4_manifest.json

WHY A MANIFEST AND NOT A FILE IN THE REPO. A regime stamp that records the
current commit cannot live in a committed file: writing the hash in changes the
tree, which changes the commit, and the stamp is wrong the instant it is made.

So the order is:

    1. commit the complete apparatus and preregistration
    2. confirm the worktree is clean
    3. at launch, generate an immutable manifest recording `git rev-parse HEAD`
    4. hash the manifest
    5. every round artifact carries the manifest hash
    6. no code or config changes during execution
    7. commit result artifacts only after all three rounds finish

THIS TOOL REFUSES if the worktree is dirty or any registered hash differs from
the file on disk. A dirty tree means the manifest would describe an apparatus
that does not exist in any commit, and no later reader could reconstruct it.

SEEDS. FLOWSCAR3 recorded a roster order but no seeds, so the order is reused
and the seeds are DERIVED deterministically from the apparatus commit and the
round index, then published here before any round runs. They are never chosen,
and never replaced after seeing a result.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Roster order reused from the closed FLOWSCAR3 regime (alphabetical by display
# name). Reused rather than re-derived so turn order is not a new free variable.
ROSTER_ORDER = ["BRINE", "GEMMATRON", "KESTREL", "OZONIOUS", "VANTA"]

# Every file whose bytes can change what the models see or what the physics does.
BOUND_FILES = [
    "config/action-schema.v1.json",
    "config/mass-contract.v1.json",
    "config/mass-contract.v2.json",
    "config/flow-scar-contract.v1.json",
    "config/contract-registry.json",
    "config/state-profiles.v1.json",
    "config/arena-species.v1.json",
    "config/arena-names.v1.json",
    "scripts/breach/world_reducer.gd",
    "scripts/breach/world_state.gd",
    "scripts/breach/observation_builder.gd",
    "scripts/breach/output_parser.gd",
    "scripts/breach/canonical_operation.gd",
    "scripts/breach/mass_contract.gd",
    "scripts/breach/flow_contract.gd",
    "scripts/breach/state_profile.gd",
    "scripts/breach/breach_round.gd",
    "scripts/breach/decider.gd",
    "scripts/breach/turn_scheduler.gd",
    "scripts/breach/arena_layout.gd",
]


def sha256_file(rel):
    with open(os.path.join(REPO, rel), "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def git(*args):
    return subprocess.run(["git"] + list(args), cwd=REPO, capture_output=True,
                          text=True, encoding="utf-8",
                          errors="replace").stdout.strip()


def refuse(reason):
    print("MANIFEST REFUSED: %s" % reason)
    print("Nothing was sealed and no round may start.")
    return 2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="scratch/flowscar4_manifest.json")
    ap.add_argument("--allow-dirty", action="store_true",
                    help="refused anyway; present only so the refusal is "
                         "explicit rather than a missing flag")
    a = ap.parse_args()

    print("=== FLOWSCAR4 RUN MANIFEST ===")

    # 2. the worktree must be clean.
    dirty = git("status", "--porcelain")
    if dirty:
        for line in dirty.splitlines()[:12]:
            print("   dirty: %s" % line)
        return refuse("worktree is not clean")
    if a.allow_dirty:
        return refuse("--allow-dirty is not honoured; commit first")

    # 3. the apparatus commit, read at launch and never written into the tree.
    commit = git("rev-parse", "HEAD")
    if len(commit) != 40:
        return refuse("could not read HEAD")
    print("  apparatus commit %s" % commit)

    # Every bound file must exist and hash to something.
    files = {}
    for rel in BOUND_FILES:
        p = os.path.join(REPO, rel)
        if not os.path.isfile(p):
            return refuse("bound file missing: %s" % rel)
        files[rel] = sha256_file(rel)

    # The registry must agree with the files it registers, or the run would be
    # stamped against contracts the runtime would refuse to load.
    reg = json.load(open(os.path.join(REPO, "config/contract-registry.json"),
                        encoding="utf-8"))
    for section in ("mass_contract", "flow_contract", "state_profiles"):
        for ver, entry in reg.get(section, {}).items():
            rel = entry["path"]
            actual = sha256_file(rel)
            if actual != entry["sha256"]:
                return refuse("registry hash differs for %s: registry %s, "
                              "disk %s" % (rel, entry["sha256"][:16],
                                           actual[:16]))
    print("  registry agrees with every registered file")

    flow = json.load(open(os.path.join(REPO,
                     "config/flow-scar-contract.v1.json"), encoding="utf-8"))
    profiles = json.load(open(os.path.join(REPO,
                         "config/state-profiles.v1.json"), encoding="utf-8"))
    species = json.load(open(os.path.join(REPO, "config/arena-species.v1.json"),
                        encoding="utf-8"))

    budget = flow["run_budget"]
    rounds = int(budget["rounds"])
    ticks = int(budget["ticks_per_round"])

    # SEEDS, derived and published before execution. Deterministic in the
    # apparatus commit and the round index; never chosen, never replaced.
    seeds = {}
    for r in range(1, rounds + 1):
        material = "FLOWSCAR4|%s|round:%d" % (commit, r)
        # Masked to 63 bits. GDScript's int is SIGNED 64-bit, and an unsigned
        # 64-bit seed overflowed it to -9223372036854775808 for two of three
        # rounds in the dry run -- two different rounds silently sharing one
        # seed. Caught by the mock pass, before any inference was paid for.
        raw = int(hashlib.sha256(material.encode()).hexdigest()[:16], 16)
        seeds["FLOWSCAR4-r%d" % r] = {
            "derivation":
                "sha256(\"%s\")[:16] & 0x7FFFFFFFFFFFFFFF" % material,
            "seed": raw & 0x7FFFFFFFFFFFFFFF,
        }

    manifest = {
        "regime": "FLOWSCAR4",
        "sealed_before_execution": True,
        "apparatus_commit": commit,
        "git_describe": git("describe", "--always", "--dirty"),
        "bound_files": files,
        "contract_binding": {
            "mass_contract_version": 2,
            "flow_contract_version": 1,
            "state_profile": "FLOWSCAR4_STATE_V1",
        },
        "state_profile_spec":
            profiles["profiles"]["FLOWSCAR4_STATE_V1"],
        "projection_definitions":
            profiles["counterfactual_projections"],
        "frozen_constants": flow["frozen_constants"],
        "tick_ordering": flow["tick_ordering"],
        "salvage": flow["salvage"],
        "lifecycle": flow["lifecycle"],
        "death_path": flow["death_path"],
        "mass_source_ledger": flow["mass_source_ledger"],
        "host_events": flow["host_events"],
        "interruption_policy": flow["interruption_policy"],
        "residency": flow["residency"],
        "run_budget": {"rounds": rounds, "ticks_per_round": ticks,
                       "stop_condition": budget["stop_condition"]},
        "roster_order": ROSTER_ORDER,
        "species": species["species"],
        "generation": {
            "context_length": 2048,
            "temperature": 0.0,
            "max_tokens": 512,
            "generations_per_cell": 1,
            "repair": False,
            "retry": False,
            "decoding": "constrained by ACTION_SCHEMA_V1, sent as verbatim bytes",
        },
        "seeds": seeds,
        "denominator_required": flow["denominator_required"],
        "claim_ladder_target": flow["claim_ladder"]["target"],
        "not_compatible_with": "FLOWSCAR3 (different vocabulary, observation "
                               "surface, mass law and schema identity)",
    }

    body = json.dumps(manifest, indent=1, sort_keys=True)
    digest = hashlib.sha256(body.encode("utf-8")).hexdigest()
    manifest_out = dict(manifest)
    manifest_out["manifest_sha256"] = digest

    out = os.path.join(REPO, a.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest_out, f, indent=1, sort_keys=True)
        f.write("\n")

    print("  bound files: %d" % len(files))
    print("  budget: %d rounds x %d ticks, hard stop" % (rounds, ticks))
    print("  roster order: %s" % ", ".join(ROSTER_ORDER))
    for k in sorted(seeds):
        print("  seed %-14s %d" % (k, seeds[k]["seed"]))
    print("")
    print("  MANIFEST SHA256 %s" % digest)
    print("  wrote %s" % out)
    print("")
    print("MANIFEST SEALED -- every round artifact must carry this hash.")
    print("No code or config may change until all %d rounds finish." % rounds)
    return 0


if __name__ == "__main__":
    sys.exit(main())
