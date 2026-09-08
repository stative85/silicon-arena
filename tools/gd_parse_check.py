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
EXECUTABLE witness, and its own qualification is three-sided on purpose.

The second control is the one that matters. A tooth qualified only on
(valid -> pass, corrupt -> fail) can be satisfied by a detector that rejects
anything unusual-looking. This project has already produced that species of
detector more than once. So a LEGAL-BUT-SUSPICIOUS control -- the exact
construct that generated the false RM-1 -- must PASS, or the tooth is not
qualified.
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


def check(project_dir, script_rel):
    """Ask Godot to parse a script. Returns (ok, output).

    --check-only parses and quits WITHOUT executing: verified by act, not by
    the help text -- a script whose _init prints produces no output under this
    flag and does print under a plain --script run. That is what makes this
    tooth NO_CONTACT even for scripts that would otherwise reach the runtime.
    """
    r = subprocess.run(
        [GODOT, "--headless", "--path", project_dir, "--check-only",
         "--script", "res://" + script_rel.replace(os.sep, "/")],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        timeout=120)
    out = ((r.stdout or "") + (r.stderr or ""))
    out = NL.join(l for l in out.splitlines()
                  if l.strip() and not l.startswith("Godot Engine"))
    return r.returncode == 0, out


def selftest():
    print("=== gd parse tooth qualification (%d controls) ===" % (len(CONTROLS) + 1))
    d = tempfile.mkdtemp(prefix="gdparse_")
    fails = 0
    failed_labels = []
    try:
        with open(os.path.join(d, "project.godot"), "w") as f:
            f.write('config_version=5' + NL + NL + '[application]' + NL + NL
                    + 'config/name="gdparse"' + NL
                    + 'config/features=PackedStringArray("4.6")' + NL)
        for name, label, expect_ok, body in CONTROLS:
            with open(os.path.join(d, name), "w", newline=NL) as f:
                f.write(body)
            ok, out = check(d, name)
            good = (ok == expect_ok)
            if not good:
                fails += 1
                failed_labels.append(label)
            print("  %s %-42s expect %-4s got %-4s"
                  % ("ok  " if good else "FAIL", label,
                     "PASS" if expect_ok else "FAIL",
                     "PASS" if ok else "FAIL"))
            if not good and out:
                print("       " + out.splitlines()[0][:100])
        # CONTROL 4: the tooth's own NO_CONTACT classification is a claim
        # about executable behaviour, so it needs an executable witness too --
        # not the help text's word that --check-only "only parses". A script
        # that PRINTS A SENTINEL from _init must stay silent under
        # --check-only, and must emit it under a plain --script run. If the
        # first ever prints, this tooth executes the files it inspects, and
        # every .gd that reaches the runtime would be contacting LM Studio
        # through the "safe" checker.
        sentinel = "SENTINEL_EXECUTED_7f3a"
        with open(os.path.join(d, "sentinel.gd"), "w", newline=NL) as f:
            f.write("extends SceneTree" + NL + NL + "func _init() -> void:" + NL
                    + TAB + 'print("' + sentinel + '")' + NL
                    + TAB + "quit(0)" + NL)
        _, checked = check(d, "sentinel.gd")
        r = subprocess.run(
            [GODOT, "--headless", "--path", d, "--script", "res://sentinel.gd"],
            capture_output=True, text=True, encoding="utf-8",
            errors="replace", timeout=120)
        ran = (r.stdout or "") + (r.stderr or "")
        silent = sentinel not in checked
        proves = sentinel in ran
        if not (silent and proves):
            fails += 1
            failed_labels.append("NO_CONTACT: --check-only does not execute")
        print("  %s %-42s expect %-4s got %-4s"
              % ("ok  " if (silent and proves) else "FAIL",
                 "NO_CONTACT: --check-only does not execute",
                 "SILENT",
                 "SILENT" if silent else "EXECUTED"))
        if not proves:
            print("       control void: the sentinel never printed even when")
            print("       actually run, so its silence proves nothing")
    finally:
        shutil.rmtree(d, ignore_errors=True)

    print("")
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
        return 1
    print("PARSE TOOTH GREEN -- valid passes, legal-but-odd passes, corrupt fails")
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
