"""Executable-witness parse check for GDScript. NO_CONTACT.

    python tools/gd_parse_check.py --selftest      qualify the tooth itself
    python tools/gd_parse_check.py                 check the repo's .gd files

Why this exists: `tools/runtime_memory_selftest.py` is 41 `re.search` calls over
a source file as TEXT, and prints "PREFLIGHT GREEN -- harness is built". Nothing
in this repository ever asked a compiler whether that file was a program. A
static audit then reported it as unparseable (RM-1) on shape evidence -- a raw
newline inside a quoted string, confirmed byte-for-byte -- and the claim was
FALSE: Godot 4 permits literal newlines in ordinary strings, and the construct
executes correctly.

So this tooth exists to settle a claim about EXECUTABLE behaviour with an
EXECUTABLE witness, and its own qualification is four-sided on purpose.

The second control is the one that matters. A tooth qualified only on
(valid -> pass, corrupt -> fail) can be satisfied by a detector that rejects
anything unusual-looking. This project has already produced that species of
detector more than once. So a LEGAL-BUT-SUSPICIOUS control -- the exact
construct that generated the false RM-1 -- must PASS, or the tooth is not
qualified.

The fourth control is the NO_CONTACT classification proving itself rather than
citing Godot's help text, and the sabotage section at the end proves the whole
qualification can go RED. A qualification that cannot fail is a transcript, not
a witness.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT") or os.path.expanduser(
    "~/Downloads/Godot_v4.6-stable_win64.exe/Godot_v4.6-stable_win64_console.exe")

NL = chr(10)
TAB = chr(9)

SENTINEL = "SENTINEL_EXECUTED_7f3a"

# The three controls. `expect_ok` is the qualification, fixed here.
CONTROLS = [
    ("valid.gd", "VALID NORMAL SCRIPT", True,
     "extends SceneTree" + NL + NL + "func _init() -> void:" + NL
     + TAB + 'print("hello")' + NL + TAB + "quit(0)" + NL),

    # The RM-1 construct: a raw newline inside an ordinary double-quoted
    # string. Looks like heredoc corruption. Is valid GDScript, and means
    # exactly what "\n" would have meant. MUST PASS.
    ("legal_suspicious.gd", "LEGAL BUT SUSPICIOUS (raw newline in string)", True,
     "extends SceneTree" + NL + NL + "func _init() -> void:" + NL
     + TAB + 'for ln in str("a").split("' + NL + '"):' + NL
     + TAB + TAB + "print(ln)" + NL + TAB + "quit(0)" + NL),

    ("corrupt.gd", "ACTUALLY INVALID SCRIPT", False,
     "extends SceneTree" + NL + NL + "func _init( -> void" + NL
     + TAB + "@@@ not gdscript" + NL),
]


def _godot(args, project_dir):
    r = subprocess.run([GODOT, "--headless", "--path", project_dir] + args,
                       capture_output=True, text=True, encoding="utf-8",
                       errors="replace", timeout=120)
    out = ((r.stdout or "") + (r.stderr or ""))
    out = NL.join(l for l in out.splitlines()
                  if l.strip() and not l.startswith("Godot Engine"))
    return r.returncode == 0, out


def check(project_dir, script_rel):
    """Ask Godot to parse a script. Returns (ok, output).

    --check-only parses and quits WITHOUT executing: verified by act, not by
    the help text -- a script whose _init prints produces no output under this
    flag and does print under a plain --script run. That is what makes this
    tooth NO_CONTACT even for scripts that would otherwise reach the runtime.
    """
    return _godot(["--check-only", "--script",
                   "res://" + script_rel.replace(os.sep, "/")], project_dir)


def _write_project(d):
    with open(os.path.join(d, "project.godot"), "w") as f:
        f.write('config_version=5' + NL + NL + '[application]' + NL + NL
                + 'config/name="gdparse"' + NL
                + 'config/features=PackedStringArray("4.6")' + NL)


def run_controls(d, checker, verbose=True):
    """Run all four controls with `checker` as the parse function.

    Parameterised on the checker so the sabotage section can run the SAME
    qualification against a deliberately broken one. A qualification that only
    ever sees the good checker cannot tell you it would notice a bad one.
    """
    fails, labels = 0, []
    for name, label, expect_ok, body in CONTROLS:
        with open(os.path.join(d, name), "w", newline=NL) as f:
            f.write(body)
        ok, out = checker(d, name)
        good = (ok == expect_ok)
        if not good:
            fails += 1
            labels.append(label)
        if verbose:
            print("  %s %-42s expect %-4s got %-4s"
                  % ("ok  " if good else "FAIL", label,
                     "PASS" if expect_ok else "FAIL",
                     "PASS" if ok else "FAIL"))
            if not good and out:
                print("       " + out.splitlines()[0][:100])

    # CONTROL 4: the tooth's own NO_CONTACT classification is a claim about
    # executable behaviour, so it needs an executable witness too -- not the
    # help text's word that --check-only "only parses". A script that PRINTS A
    # SENTINEL from _init must stay silent under the checker, and must emit it
    # under a plain --script run. If the first ever prints, this tooth executes
    # the files it inspects, and every .gd that reaches the runtime would be
    # contacting LM Studio through the "safe" checker.
    with open(os.path.join(d, "sentinel.gd"), "w", newline=NL) as f:
        f.write("extends SceneTree" + NL + NL + "func _init() -> void:" + NL
                + TAB + 'print("' + SENTINEL + '")' + NL
                + TAB + "quit(0)" + NL)
    _, checked = checker(d, "sentinel.gd")
    _, ran = _godot(["--script", "res://sentinel.gd"], d)
    silent = SENTINEL not in checked
    proves = SENTINEL in ran
    if not (silent and proves):
        fails += 1
        labels.append("NO_CONTACT: --check-only does not execute")
    if verbose:
        print("  %s %-42s expect %-4s got %-4s"
              % ("ok  " if (silent and proves) else "FAIL",
                 "NO_CONTACT: --check-only does not execute",
                 "SILENT", "SILENT" if silent else "EXECUTED"))
        if not proves:
            print("       control void: the sentinel never printed even when")
            print("       actually run, so its silence proves nothing")
    return fails, labels


# --- sabotages -------------------------------------------------------------
#
# Each returns a checker broken in ONE specific dangerous direction. The
# qualification must go RED for every one of them. A tooth that stays green
# while its checker is broken is decoration with a transcript.

def _sabotage_no_check_only(d, script_rel):
    """Drop --check-only: the checker now EXECUTES what it inspects.

    This is the dangerous direction for a tool classified NO_CONTACT. If the
    qualification does not notice, a checker that runs every .gd it scans could
    reach the runtime while reporting itself safe.
    """
    return _godot(["--script", "res://" + script_rel.replace(os.sep, "/")], d)


def _sabotage_always_ok(d, script_rel):
    """Always report success -- the rubber stamp."""
    return True, ""


SABOTAGES = [
    ("remove --check-only (checker executes the script)",
     _sabotage_no_check_only, "NO_CONTACT"),
    ("force the checker to always report OK",
     _sabotage_always_ok, "ACTUALLY INVALID"),
]


def sabotage_suite():
    """Prove the qualification can go RED. Returns the number of FAILED
    sabotages -- that is, sabotages the qualification did not notice."""
    print("")
    print("=== sabotage: can this qualification fail? ===")
    bad = 0
    for label, checker, expect_fragment in SABOTAGES:
        # A sabotage must assert it actually applied before it is trusted to
        # prove anything. An unapplied sabotage that "passes" is the strongest
        # false negative available -- this repo has already paid for one, in
        # artifact_schema, where 1 == True made a mutation look unapplied.
        applied = checker is not check
        if not applied:
            print("  FAIL %-52s SABOTAGE DID NOT APPLY" % label)
            bad += 1
            continue
        d = tempfile.mkdtemp(prefix="gdsab_")
        try:
            _write_project(d)
            fails, labels = run_controls(d, checker, verbose=False)
        finally:
            shutil.rmtree(d, ignore_errors=True)
        bit = fails > 0 and any(expect_fragment in l for l in labels)
        print("  %s %-52s %s"
              % ("ok  " if bit else "FAIL", label,
                 "RED (%d control%s)" % (fails, "" if fails == 1 else "s")
                 if bit else "STAYED GREEN -- tooth is blind"))
        if not bit:
            bad += 1
        elif labels:
            print("       broke: %s" % "; ".join(labels))
    return bad


def selftest():
    print("=== gd parse tooth qualification (%d controls) ===" % (len(CONTROLS) + 1))
    d = tempfile.mkdtemp(prefix="gdparse_")
    try:
        _write_project(d)
        fails, failed_labels = run_controls(d, check)
    finally:
        shutil.rmtree(d, ignore_errors=True)

    sab_bad = sabotage_suite()

    print("")
    if fails or sab_bad:
        if fails:
            print("PARSE TOOTH RED -- %d of %d controls wrong"
                  % (fails, len(CONTROLS) + 1))
            for label in failed_labels:
                print("  failed: %s" % label)
            if any("SUSPICIOUS" in l for l in failed_labels):
                print("A tooth that fails the LEGAL-BUT-SUSPICIOUS control is not")
                print("strict, it is broken: it rejects code for looking unusual.")
            if any("NO_CONTACT" in l for l in failed_labels):
                print("The NO_CONTACT control failing means this checker EXECUTES")
                print("the scripts it inspects. It must not run unattended, and it")
                print("must not be classified NO_CONTACT, until that is fixed.")
        if sab_bad:
            print("PARSE TOOTH RED -- %d sabotage(s) did not bite. The" % sab_bad)
            print("qualification cannot detect a broken checker, so its GREEN")
            print("means nothing.")
        return 1
    print("PARSE TOOTH GREEN -- valid passes, legal-but-odd passes, corrupt")
    print("fails, --check-only proven non-executing, both sabotages bite")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("paths", nargs="*")
    a = ap.parse_args()
    if a.selftest:
        return selftest()

    targets = a.paths or sorted(
        os.path.relpath(os.path.join(r, f), REPO)
        for r, _, fs in os.walk(REPO) for f in fs
        if f.endswith(".gd") and ".godot" not in r)
    bad = 0
    for t in targets:
        ok, out = check(REPO, t)
        if ok:
            print("  ok   %s" % t)
        else:
            bad += 1
            print("  FAIL %s" % t)
            for line in out.splitlines()[:4]:
                print("       " + line[:120])
    print("")
    print("=== %d parsed, %d failed ===" % (len(targets) - bad, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
