"""CLI entry point: one objective in, one verified artifact out.

    python -m arena_core.run_mission --mission arena_core/missions/word_wrap.json \
        --model google/gemma-4-26b-a4b

Writes to arena_core/runs/<mission>_<timestamp>/:
    solution.py   the artifact -- copyable, runnable, verified
    report.md     what happened, cycle by cycle, with exact deltas
    run.json      machine-readable record for the future optimizer (#4)

Exit codes: 0 verified, 1 improved but not verified, 2 failed/error.
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import os
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from arena_core.cycle import MissionReport, run_mission
from arena_core.llm import DEFAULT_BASE_URL, LLMError, LMStudioLLM
from arena_core.mission import Mission
from arena_core.verifier import CodeVerifier

RUNS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "runs")


def list_models(base_url: str) -> list:
    try:
        with urllib.request.urlopen(f"{base_url.rstrip('/')}/models", timeout=10) as r:
            return [m["id"] for m in json.loads(r.read().decode("utf-8"))["data"]]
    except Exception as exc:                      # noqa: BLE001 - reported, not raised
        print(f"could not reach LM Studio at {base_url}: {exc}", file=sys.stderr)
        return []


def write_outputs(report: MissionReport, mission: Mission, out_dir: str,
                  model: str) -> None:
    os.makedirs(out_dir, exist_ok=True)

    artifact_path = os.path.join(out_dir, mission.artifact_name)
    with open(artifact_path, "w", encoding="utf-8") as fh:
        fh.write(report.artifact.rstrip() + "\n")

    verdict = ("VERIFIED" if report.final.perfect
               else ("PARTIAL" if report.final.score > 0 else "FAILED"))
    lines = [
        f"# {mission.id} - {verdict}",
        "",
        f"**Objective:** {mission.objective}",
        "",
        f"**Model:** `{model}`",
        "",
        "## Result",
        "",
        "```",
        report.summary(),
        "```",
        "",
        "## Cycles",
        "",
    ]
    if not report.cycles:
        lines.append("_No repair cycles were needed._")
    for c in report.cycles:
        lines += [
            f"### Cycle {c.index} - {'kept' if c.accepted else 'rejected'} "
            f"({c.passed_before}/{c.total} -> {c.passed_after}/{c.total}, "
            f"{c.delta:+.3f})",
            "",
            "Critique the repairer acted on:",
            "",
            "```",
            c.critique.strip()[:2000] or "(empty)",
            "```",
            "",
        ]
    if report.final.failures:
        lines += ["## Remaining failures", ""]
        lines += ["```", report.final.critique_material(), "```", ""]

    with open(os.path.join(out_dir, "report.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))

    record = {
        "mission": mission.id,
        "model": model,
        "verdict": verdict,
        "initial_score": report.initial.score,
        "final_score": report.final.score,
        "improvement": report.final.score - report.initial.score,
        "cycles": [dataclasses.asdict(c) for c in report.cycles],
        "stop_reason": report.stop_reason,
        "seconds": report.seconds,
        "timestamp": time.time(),
    }
    with open(os.path.join(out_dir, "run.json"), "w", encoding="utf-8") as fh:
        json.dump(record, fh, indent=2)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Run one arena mission to a verified artifact.")
    ap.add_argument("--mission", help="path to mission .json")
    ap.add_argument("--model", help="LM Studio model id")
    ap.add_argument("--base-url", default=DEFAULT_BASE_URL)
    ap.add_argument("--out", help="output directory (default: arena_core/runs/...)")
    ap.add_argument("--cycles", type=int, help="override max repair cycles")
    ap.add_argument("--temperature", type=float, default=0.3)
    ap.add_argument("--list-models", action="store_true")
    args = ap.parse_args(argv)

    if args.list_models:
        for m in list_models(args.base_url):
            print(m)
        return 0

    if not args.mission or not args.model:
        ap.error("--mission and --model are required (try --list-models)")

    mission = Mission.load(args.mission)
    if args.cycles is not None:
        mission.max_cycles = args.cycles

    verifier = CodeVerifier(mission.tests_source, timeout=mission.timeout)
    try:
        # Preflight before any tokens are spent. A broken test file must fail
        # here, not after four cycles of grinding against a dead instrument.
        verifier.self_check()
    except ValueError as exc:
        print(f"MISSION REJECTED: {exc}", file=sys.stderr)
        return 2

    llm = LMStudioLLM(model=args.model, base_url=args.base_url,
                      temperature=args.temperature)

    def emit(msg: str) -> None:
        print(msg, flush=True)

    try:
        report = run_mission(mission, llm, verifier=verifier, on_event=emit)
    except LLMError as exc:
        print(f"MODEL ERROR: {exc}", file=sys.stderr)
        return 2

    out_dir = args.out or os.path.join(
        RUNS_DIR, f"{mission.id}_{time.strftime('%Y%m%d_%H%M%S')}")
    write_outputs(report, mission, out_dir, args.model)

    print()
    print(report.summary())
    print()
    print(f"artifact -> {os.path.join(out_dir, mission.artifact_name)}")
    print(f"report   -> {os.path.join(out_dir, 'report.md')}")

    if report.final.perfect:
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
