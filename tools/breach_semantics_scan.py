"""Fail-closed scan for host-authored semantics in the BREACH host. NO_CONTACT.

    python tools/breach_semantics_scan.py            scan the host
    python tools/breach_semantics_scan.py --selftest qualify this tooth

WHY THIS EXISTS

"The host understands verbs, not behaviour" is a principle, and principles decay
into habits and then into comments. This makes it mechanical:

    if the host implementation names a behaviour, the scan REFUSES.

Forbidden concepts: alliance, betrayal, trust, leadership, cooperation,
deception, strategy, and their obvious relatives. The moment a field called
`trust_score` or a function called `form_alliance()` exists, the Arena has begun
measuring the host instead of the models, and every later claim about what the
agents "did" is contaminated at the source.

WHERE THE LINE IS

Forbidden in HOST IMPLEMENTATION -- the code that decides what happens.
Permitted, and necessary, in:

  * documentation, which has to be able to NAME what it prohibits
  * this scanner, which must contain the patterns it searches for
  * tests that prove the prohibition works

That exemption is the same shape as run_safe_tests.py's marker_allowance for
runtime_memory_selftest naming `taskkill`: a scanner necessarily contains its
own forbidden strings. It is granted by PATH, explicitly, never by silence.

WHAT THIS CANNOT DO

It cannot stop someone implementing an alliance and calling it `pact_b`. A
static scan catches the honest mistake and the lazy one, not a determined
rename. It is a tripwire, not a proof, and it is written down as such.
"""

import argparse
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The concepts the host may not implement. Case insensitive, over code with
# comments and string literals stripped.
#
# ON THE BOUNDARY, paid for by this tooth's own qualification: `\b` does NOT
# work here. "_" is a word character, so `\balliance` never matches
# `form_alliance()` -- the single most obvious violation in the language would
# have walked straight through a scanner that looked strict. The lookbehind
# below treats any non-letter as a boundary, so snake_case, camelCase and
# prefixed identifiers are all caught. The selftest keeps all three as
# permanent controls.
# Two boundaries: a non-letter before the word (snake_case, prefixes, bare
# identifiers), OR a lowercase->uppercase transition (camelCase). The camel
# branch requires the match to START uppercase, which is what keeps it from
# firing on ordinary words that merely contain a forbidden substring -- notably
# `finally`, which contains "ally" and is a Python keyword.
#
# KNOWN GAP, stated rather than hidden: a forbidden word glued to a lowercase
# prefix, like `distrust`, is NOT caught. Widening to catch it flags `finally`
# and this tooth becomes noise. A static scan is a tripwire, not a proof.
# The camel branch MUST be case-sensitive. The whole table is matched with
# re.I, and under re.I `[A-Z]` also matches lowercase -- so `(?=[A-Z])` happily
# fired on the "a" in `finally` and the tooth started crying wolf on a Python
# keyword. `(?-i:...)` scopes those two classes back to case-sensitive. Caught
# by the false-positive control below, which is the entire reason it exists.
B = r"(?:(?<![A-Za-z])|(?<=(?-i:[a-z]))(?=(?-i:[A-Z])))"

FORBIDDEN = {
    "alliance": B + r"allianc\w*",
    "ally": B + r"all(y|ies)(?![A-Za-z])",
    "betrayal": B + r"betray\w*",
    "trust": B + r"trust\w*",
    "leadership": B + r"lead(er|ership|ing)(?![A-Za-z])",
    "cooperation": B + r"cooperat\w*",
    "deception": B + r"(deceiv\w*|deception)",
    "strategy": B + r"strateg\w*",
    "rival": B + r"rival\w*",
    "enemy": B + r"enem(y|ies)(?![A-Za-z])",
    "friendship": B + r"friend\w*",
    "greed": B + r"greed\w*",
    "honesty": B + r"honest\w*",
    "coalition": B + r"coalition\w*",
}

# Host implementation. These files decide what happens.
HOST_GLOBS = ["scripts/breach/*.gd"]

# Granted by path, with a stated reason. Never silent.
PATH_EXEMPT = {
    "tools/breach_semantics_scan.py":
        "this scanner necessarily contains the patterns it forbids",
    "scripts/breach/breach_selftest.gd":
        "the suite proves the prohibition and must name what it checks",
}


def strip_noncode(src, is_gd):
    """Remove comments and string literals: a forbidden word inside a docstring
    explaining the prohibition is not an implementation of it."""
    if is_gd:
        src = re.sub(r"#[^\n]*", "", src)
    else:
        src = re.sub(r"#[^\n]*", "", src)
        src = re.sub(r'"""[\s\S]*?"""', "", src)
        src = re.sub(r"'''[\s\S]*?'''", "", src)
    src = re.sub(r'"(?:[^"\\]|\\.)*"', '""', src)
    src = re.sub(r"'(?:[^'\\]|\\.)*'", "''", src)
    return src


def scan_text(src, is_gd=True):
    code = strip_noncode(src, is_gd)
    hits = []
    for concept, pattern in sorted(FORBIDDEN.items()):
        for m in re.finditer(pattern, code, re.I):
            line = code[:m.start()].count("\n") + 1
            hits.append((concept, m.group(0), line))
    return hits


def host_files():
    import glob
    out = []
    for g in HOST_GLOBS:
        for p in sorted(glob.glob(os.path.join(REPO, g))):
            rel = os.path.relpath(p, REPO).replace("\\", "/")
            if rel not in PATH_EXEMPT:
                out.append(rel)
    return out


def scan():
    files = host_files()
    print("=== BREACH host-semantics scan ===")
    print("scanning %d host file(s) for %d forbidden concept(s)"
          % (len(files), len(FORBIDDEN)))
    if not files:
        # An empty scan that reports success is a scan that proves nothing.
        print("")
        print("REFUSED -- no host files found at %s" % ", ".join(HOST_GLOBS))
        print("A scanner with nothing to scan must not report GREEN.")
        return 1
    bad = []
    for rel in files:
        with open(os.path.join(REPO, rel), encoding="utf-8",
                  errors="replace") as f:
            hits = scan_text(f.read(), rel.endswith(".gd"))
        for concept, word, line in hits:
            bad.append((rel, line, concept, word))
    for rel, why in sorted(PATH_EXEMPT.items()):
        print("    exempt  %-42s %s" % (rel, why))
    if bad:
        print("")
        print("REFUSED -- the host implements a behaviour it should only observe:")
        for rel, line, concept, word in bad:
            print("    %s:%d  %s  (%r)" % (rel, line, concept, word))
        print("")
        print("Write the verbs. Do not write the behavior. If this concept is")
        print("real, it must EMERGE from sequences of canonical operations and")
        print("be named by an analyst afterwards -- never by the host.")
        return 1
    print("")
    print("CLEAN -- the host names no behaviour")
    return 0


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

    print("=== semantics scanner qualification ===")

    ck("clean code passes",
       scan_text("func move(target):\n\tposition = target\n") == [])
    # REGRESSION CONTROLS. The first of these FAILED on the original pattern
    # table: "_" is a word character, so \b never matched form_alliance. All
    # three stay as permanent controls because the boundary is the part of this
    # tooth most likely to be quietly weakened later.
    ck("a forbidden function name is caught (snake_case)",
       any(c == "alliance" for c, _, _ in
           scan_text("func form_alliance(a, b):\n\tpass\n")))
    ck("camelCase is caught",
       any(c == "trust" for c, _, _ in scan_text("var agentTrust := 0\n")))
    ck("a prefixed identifier is caught",
       any(c == "betrayal" for c, _, _ in
           scan_text("var _betrayal_flag := 0\n")))
    ck("a forbidden field is caught",
       any(c == "trust" for c, _, _ in scan_text("var trust_score := 0.0\n")))
    ck("betrayal is caught",
       any(c == "betrayal" for c, _, _ in
           scan_text("if betrayed:\n\tpass\n")))

    # The control that matters: a scanner that flags prose would make it
    # impossible to DOCUMENT the prohibition, and the documentation is how the
    # rule survives the people who wrote it.
    ck("a comment explaining the prohibition is NOT flagged",
       scan_text("# the host must never model trust or betrayal\nvar x := 1\n")
       == [])
    ck("a string literal is NOT flagged",
       scan_text('var s := "trust"\nvar y := 2\n') == [])

    # FALSE-POSITIVE CONTROLS. Without these, widening the boundary to catch
    # camelCase quietly breaks every file containing `finally` -- and a tooth
    # that cries wolf gets switched off, which is worse than one that misses.
    ck("`finally` is NOT flagged as `ally`",
       scan_text("try:\n\tpass\nfinally:\n\tpass\n") == [])
    ck("ordinary identifiers are NOT flagged",
       scan_text("var already_moved := true\nvar total := 0\n") == [])

    # Sabotage: neuter the pattern table and require the tooth to go blind, so
    # its GREEN is known to be capable of being RED.
    global FORBIDDEN
    real = dict(FORBIDDEN)
    FORBIDDEN = {}
    applied = len(FORBIDDEN) == 0 and len(real) > 0
    ck("SABOTAGE APPLIED (pattern table emptied)", applied)
    if applied:
        ck("SABOTAGE BITES: obvious violation now passes",
           scan_text("func form_alliance():\n\tvar trust_score := 1.0\n") == [])
    FORBIDDEN = real
    ck("SABOTAGE REVERTED",
       any(c == "alliance" for c, _, _ in
           scan_text("func form_alliance():\n\tpass\n")))

    print("\n  checks %d, failures %d" % (n, f))
    print("SEMANTICS TOOTH GREEN" if f == 0 else "SEMANTICS TOOTH RED")
    return 1 if f else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    return selftest() if a.selftest else scan()


if __name__ == "__main__":
    sys.exit(main())
