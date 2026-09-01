#!/usr/bin/env python3
"""Validate GitHub Actions workflow YAML before it reaches CI.

    python tools/lint_workflows.py

Exists because a `run:` line containing "RESULT: SEPARATED" was pushed to main
and broke the workflow: an unquoted YAML scalar cannot contain ": ". CI itself
cannot catch that, because a workflow that does not parse never runs.
"""
import pathlib
import sys

try:
    import yaml
except ImportError:
    print("pyyaml not installed; skipping (pip install pyyaml to enable)")
    sys.exit(0)

ROOT = pathlib.Path(__file__).resolve().parents[1]
WF = ROOT / ".github" / "workflows"
bad = 0
files = sorted(WF.glob("*.yml")) + sorted(WF.glob("*.yaml"))
if not files:
    print("no workflow files found")
    sys.exit(0)

for f in files:
    try:
        doc = yaml.safe_load(f.read_text(encoding="utf-8"))
    except Exception as e:                       # noqa: BLE001
        print(f"FAIL {f.relative_to(ROOT)}: {e}")
        bad += 1
        continue
    if not isinstance(doc, dict) or "jobs" not in doc:
        print(f"FAIL {f.relative_to(ROOT)}: no jobs block")
        bad += 1
        continue
    steps = sum(len(j.get("steps", [])) for j in doc["jobs"].values())
    print(f"ok   {f.relative_to(ROOT)}  ({len(doc['jobs'])} job(s), {steps} steps)")

print(f"\n{len(files)} workflow(s), {bad} invalid")
sys.exit(1 if bad else 0)
