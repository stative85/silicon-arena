"""Fail if TEMPLATES.md does not document every template the code defines.

TEMPLATES.md is the showcase a visitor reads to decide whether this project is
interesting. It claimed 45 templates and described 43: "Hemp-Graphene
Ascension" and "Functional Stability Tribunal" were shipped in the code and
absent from the document. Nothing could catch that, because the count in the
prose and the templates in the code were maintained by hand, separately.

Also checks that the headline count in the prose matches reality, since a
document that says "45 templates" while listing a different number is the same
defect in a form a reader notices faster.

    python tools/lint_templates.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "scripts", "template_manager.gd")
DOC = os.path.join(ROOT, "TEMPLATES.md")


def main():
    if not os.path.exists(SOURCE) or not os.path.exists(DOC):
        print("  FAIL missing %s or %s" % (SOURCE, DOC))
        print("TEMPLATE LINT FAILED")
        return 1

    src = open(SOURCE, encoding="utf-8", errors="ignore").read()
    doc = open(DOC, encoding="utf-8", errors="ignore").read()

    labels = re.findall(r'"label":\s*"([^"]*)"', src)
    if not labels:
        # A parse that finds nothing must fail loudly rather than pass by
        # comparing an empty list against the document.
        print("  FAIL no templates parsed from %s" % os.path.relpath(SOURCE, ROOT))
        print("TEMPLATE LINT FAILED")
        return 1

    problems = []
    for label in labels:
        if label not in doc:
            problems.append('template "%s" is in the code and not in TEMPLATES.md' % label)

    # The advertised count must match what the code actually defines.
    for claimed in re.findall(r"(\d+) templates", doc):
        if int(claimed) != len(labels):
            problems.append(
                "TEMPLATES.md says %s templates; the code defines %d"
                % (claimed, len(labels))
            )

    for p in problems:
        print("  FAIL %s" % p)
    print("\n%d template(s) defined, %d problem(s)" % (len(labels), len(problems)))
    if problems:
        print("TEMPLATE LINT FAILED")
        return 1
    print("TEMPLATES OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
