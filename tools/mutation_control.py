#!/usr/bin/env python3
"""Mutation controls for the Scar Lattice.

A guard that has never been watched break is not evidence. This installs one
deliberate defect at a time, runs the suite, and records whether the suite
noticed. Baseline-FAIL plus candidate-PASS is the only shape that proves a
check can falsify its author.

Safety: the pristine source is copied and VERIFIED clean before any mutation is
written, and residue is asserted zero after every restore. An earlier version of
this workflow left a mutant in the working tree because a shell `||` fallback
never ran and the restore silently copied nothing.

    python tools/mutation_control.py [--out FILE]
"""
import argparse
import pathlib
import os
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "scripts" / "arena" / "scar_lattice.gd"
def _find_godot() -> pathlib.Path:
    """Locate Godot without hardcoding one developer's Downloads folder."""
    env = os.environ.get("GODOT_BIN")
    if env and pathlib.Path(env).exists():
        return pathlib.Path(env)
    for name in ("godot", "godot.exe", "Godot_v4.6-stable_win64_console.exe",
                 "Godot_v4.6-stable_win64.exe"):
        found = shutil.which(name)
        if found:
            return pathlib.Path(found)
    raise SystemExit(
        "Godot not found. Set GODOT_BIN to your Godot 4.6 executable, "
        "or put godot on PATH."
    )


GODOT = _find_godot()
MARK = "MUTANT"

# name, phase, old, new, what the mutation asserts is not being checked
MUTATIONS = [
    (
        "rung2: validate_claim accepts everything",
        "unit",
        'func validate_claim(memory: Dictionary, sources: Array = []) -> String:\n'
        '\tvar kind := str(memory.get("claim_kind", ""))',
        'func validate_claim(memory: Dictionary, sources: Array = []) -> String:\n'
        '\treturn ""   # MUTANT\n'
        '\tvar kind := str(memory.get("claim_kind", ""))',
        "claim grammar is enforced at all",
    ),
    (
        "rung2: corroboration rewrites claim_kind (laundering)",
        "unit",
        '\tclaim["support_history"] = history\n\tclaim["support_status"] = status',
        '\tclaim["support_history"] = history\n\tclaim["support_status"] = status\n'
        '\tif status == "CORROBORATED":\n'
        '\t\tclaim["claim_kind"] = "DIRECT_OBSERVATION"   # MUTANT\n'
        '\t\tclaim["acquisition_mode"] = "OBSERVED"   # MUTANT',
        "a corroborated rumour stays a rumour",
    ),
    (
        "rung4: a later position overwrites earlier ones",
        "verify",
        '\t\t\t\t\t_contradictions[pcid]["positions"].append(pos)',
        '\t\t\t\t\t_contradictions[pcid]["positions"] = [pos]   # MUTANT',
        "conflicting positions survive restart unmerged",
    ),
    (
        "rung4: system audit masquerades as the agent's own words",
        "verify",
        '\t\t"position_origin": "system_derived_audit",\n\t\t"queried": false,',
        '\t\t"position_origin": "agent_stated",   # MUTANT\n\t\t"queried": true,',
        "absence of memory is not fabricated into a statement",
    ),
    (
        "rung4: resolution deletes the positions it contradicts",
        "verify",
        '\tcon["resolutions"].append(res)\n\tcon["resolution_state"] = state',
        '\tcon["resolutions"].append(res)\n\tcon["resolution_state"] = state\n'
        '\tvar keep := []   # MUTANT\n'
        '\tfor pos in con["positions"]:\n'
        '\t\tif not contradicted.has(str(pos.get("position_id", ""))):\n'
        '\t\t\tkeep.append(pos)\n'
        '\tcon["positions"] = keep',
        "resolution never deletes a position",
    ),
]


def _invoke(phase: str) -> str:
    out = subprocess.run(
        [str(GODOT), "--headless", "--path", str(ROOT), "--script",
         "scripts/arena/scar_lattice_selftest.gd", "--", "--phase", phase],
        capture_output=True, text=True, timeout=600,
    )
    return out.stdout or ""


def run(phase: str) -> str:
    """Run one phase, from a known state.

    The verify phase reads a store that the write phase creates, and it also
    APPENDS to that store (it records a resolution event). Running verify twice
    against the same store therefore fails for reasons that have nothing to do
    with the mutation under test — the first harness did exactly that and
    produced six phantom failures in every arm, including the unmutated one.
    Verify is always preceded by a fresh write.
    """
    if phase == "verify":
        _invoke("write")
    text = _invoke(phase)
    lines = [l for l in text.splitlines()
             if l.strip().startswith("FAIL") or "checks," in l]
    return "\n".join(lines) if lines else "(no result line)"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    if not GODOT.exists():
        print("godot not found: %s" % GODOT, file=sys.stderr)
        return 2

    pristine = SRC.read_text(encoding="utf-8")
    if MARK in pristine:
        print("ABORT: working tree already contains a mutant", file=sys.stderr)
        return 2
    backup = SRC.with_suffix(".gd.pristine")
    backup.write_text(pristine, encoding="utf-8", newline="\n")
    assert MARK not in backup.read_text(encoding="utf-8"), "backup is not clean"

    report = ["Scar Lattice mutation controls",
              "Each mutation installs one defect. A control PASSES when the suite FAILS.",
              ""]
    ok = True
    try:
        for name, phase, old, new, asserts in MUTATIONS:
            if old not in pristine:
                report.append("SKIPPED  %s\n  anchor not found - the control is STALE" % name)
                ok = False
                continue
            SRC.write_text(pristine.replace(old, new, 1), encoding="utf-8", newline="\n")
            baseline = run(phase)
            SRC.write_text(pristine, encoding="utf-8", newline="\n")
            assert MARK not in SRC.read_text(encoding="utf-8"), "restore failed"

            noticed = "FAIL" in baseline
            ok = ok and noticed
            report.append("%s  %s" % ("CONTROL OK " if noticed else "CONTROL DEAD", name))
            report.append("  proves: %s" % asserts)
            report.append("  phase : %s" % phase)
            for line in baseline.splitlines():
                report.append("    %s" % line.strip())
            report.append("")
    finally:
        SRC.write_text(pristine, encoding="utf-8", newline="\n")
        residue = MARK in SRC.read_text(encoding="utf-8")
        report.append("mutant residue in working tree: %s" % ("YES - MANUAL FIX NEEDED" if residue else "none"))
        backup.unlink(missing_ok=True)
        if residue:
            ok = False

    for phase in ("unit", "verify"):
        report.append("")
        report.append("CANDIDATE (%s, unmutated): %s" % (phase, run(phase)))

    text = "\n".join(report)
    print(text)
    if args.out:
        out_path = pathlib.Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(text, encoding="utf-8", newline="\n")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
