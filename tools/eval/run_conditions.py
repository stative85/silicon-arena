#!/usr/bin/env python3
"""Run the four roster modes under identical conditions and record transcripts.

    python tools/eval/run_conditions.py [--turns 70]

Held constant across conditions:
  * the debate topic (live_match.gd's TOPIC const)
  * the agent count (5)
  * the harness, the machine, the LM Studio server
  * the turn cap
  * memory state, which is CLEARED before each condition so no run inherits
    another's scar lattice

Varied: only the roster mode, which is the independent variable.

Outputs one JSON per condition into tools/eval/runs/.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "tools", "eval", "runs")
USERDATA = os.path.expandvars(
    r"%APPDATA%\Godot\app_userdata\Silicon Arena")

CONDITIONS = [
    ("A_diverse",  []),
    ("B_balanced", ["--balanced"]),
    ("C_fast",     ["--fast"]),
    ("D_fit",      ["--fit"]),
]

FAIL = re.compile(r"^LIVE_ARENA TURN_FAILED (.*?): (.*)$")


def newest_match_log():
    d = os.path.join(USERDATA, "live_matches")
    if not os.path.isdir(d):
        return None
    files = [os.path.join(d, f) for f in os.listdir(d) if f.endswith(".jsonl")]
    return max(files, key=os.path.getmtime) if files else None


def read_turns(path):
    """Read speeches from the match log rather than from stdout.

    The JSONL carries display_name, model_key, latency_ms and the full text as
    structured fields, so this cannot be broken by a print-format change or by
    a reply that happens to contain a newline.
    """
    out = []
    if not path or not os.path.exists(path):
        return out
    for line in open(path, encoding="utf-8", errors="ignore"):
        try:
            d = json.loads(line)
        except Exception:
            continue
        if d.get("kind") == "turn":
            out.append({"n": int(d.get("turn", 0)),
                        "speaker": str(d.get("display_name", "")).strip(),
                        "model": str(d.get("model_key", "")),
                        "latency_ms": int(d.get("latency_ms") or 0),
                        "text": str(d.get("text", ""))})
    return out


def godot():
    for c in [os.environ.get("GODOT", ""),
              r"C:\Users\cleve\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64.exe"]:
        if c and os.path.exists(c):
            return c
    sys.exit("godot not found; set GODOT")


def free_vram():
    """Unload every resident model so each condition starts from the same state.

    LM Studio keeps models resident on a TTL, and a resident model reduces the
    VRAM available to the next one. On an 8GB card a resident 2.5GB model is
    enough to stop a 7B loading, which arrives as HTTP 400 and looks exactly
    like the model being broken. The first attempt at this evaluation was
    invalidated by it: three of four conditions ran with 40%+ "failures" that
    were really load failures inherited from the previous condition.
    """
    exe = os.path.join(os.path.expanduser("~"), ".lmstudio", "bin", "lms.exe")
    if not os.path.exists(exe):
        return False
    try:
        subprocess.run([exe, "unload", "--all"], capture_output=True, timeout=120)
        time.sleep(3)
        return True
    except Exception:
        return False


def clear_memory():
    """Each condition starts from the same blank memory state."""
    for name in ("scar_lattice", "live_matches"):
        p = os.path.join(USERDATA, name)
        if os.path.isdir(p):
            shutil.rmtree(p, ignore_errors=True)


def run(cmd, timeout):
    t0 = time.time()
    try:
        p = subprocess.run(cmd, capture_output=True, text=True,
                           encoding="utf-8", errors="ignore", timeout=timeout)
        return p.stdout + p.stderr, time.time() - t0, False
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or "") + (e.stderr or "")
        if isinstance(out, bytes):
            out = out.decode("utf-8", "ignore")
        return out, time.time() - t0, True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--turns", type=int, default=70)
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    g = godot()

    for name, flags in CONDITIONS:
        if a.only and a.only not in name:
            continue
        print("\n" + "=" * 66)
        print("CONDITION %s   flags=%s" % (name, flags or ["(default)"]))
        print("=" * 66)

        print("  freeing VRAM: %s" % ("ok" if free_vram() else "lms CLI unavailable"))
        build, bt, _ = run([g, "--headless", "--path", ROOT, "--script",
                            "tools/build_roster.gd", "--"] + flags, 1800)
        roster_path = os.path.join(ROOT, "config", "arena-roster.v1.json")
        if not os.path.exists(roster_path):
            print("  roster not written; skipping")
            continue
        roster = json.load(open(roster_path, encoding="utf-8"))
        models = [ag["model_key"] for ag in roster["agents"]]
        print("  roster built in %.0fs: %d agents, %d distinct model(s)"
              % (bt, len(models), len(set(models))))

        clear_memory()
        free_vram()

        log, rt, timed_out = run(
            [g, "--headless", "--path", ROOT, "--script",
             "scripts/arena/live_match.gd", "--",
             "--turns", str(a.turns), "--no-wait", "--exit-on-complete",
             "--timeout-sec", "120"],
            7200)

        speeches = read_turns(newest_match_log())
        failures = []
        for line in log.splitlines():
            f = FAIL.match(line)
            if f:
                failures.append({"speaker": f.group(1).strip(), "why": f.group(2)})

        rec = {
            "condition": name,
            "flags": flags,
            "roster": roster,
            "models": models,
            "distinct_models": len(set(models)),
            "wall_sec": rt,
            "build_sec": bt,
            "timed_out": timed_out,
            "speeches": speeches,
            "failures": failures,
        }
        with open(os.path.join(OUT, name + ".json"), "w", encoding="utf-8") as fh:
            json.dump(rec, fh, indent=1)
        print("  %d speeches, %d failures, %.0fs wall%s"
              % (len(speeches), len(failures), rt,
                 "  (TIMED OUT)" if timed_out else ""))


if __name__ == "__main__":
    main()
