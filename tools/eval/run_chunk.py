#!/usr/bin/env python3
"""Run one match chunk for a condition and append it to that condition's record.

    python tools/eval/run_chunk.py --cond A_diverse --build     # roster once
    python tools/eval/run_chunk.py --cond A_diverse --turns 15  # a chunk

Why chunks: a diverse-roster condition needs about half an hour of real
inference, and this environment stops long-running background work. Each
condition is therefore run as several shorter matches with the SAME roster,
and their turns are concatenated.

The chunking is applied identically to every condition, so it cannot favour
one. It does mean each condition contains several debate openings rather than
one long debate, which is recorded in the report rather than hidden.

VRAM is emptied and memory cleared once per condition, at --build time, not
between chunks: between chunks the resident set is whatever the mode actually
produces, which is the steady state being measured.
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
USERDATA = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata",
                        "Silicon Arena")
FAIL = re.compile(r"^LIVE_ARENA TURN_FAILED (.*?): (.*)$")

CONDITIONS = {
    "A_diverse": [],
    "B_balanced": ["--balanced"],
    "C_fast": ["--fast"],
    "D_fit": ["--fit"],
}


def godot():
    c = os.environ.get("GODOT") or (
        r"C:\Users\cleve\Downloads\Godot_v4.6-stable_win64.exe"
        r"\Godot_v4.6-stable_win64.exe")
    if not os.path.exists(c):
        sys.exit("godot not found; set GODOT")
    return c


def lms_unload():
    exe = os.path.join(os.path.expanduser("~"), ".lmstudio", "bin", "lms.exe")
    if not os.path.exists(exe):
        return False
    try:
        subprocess.run([exe, "unload", "--all"], capture_output=True, timeout=120)
        time.sleep(3)
        return True
    except Exception:
        return False


def newest_log():
    d = os.path.join(USERDATA, "live_matches")
    if not os.path.isdir(d):
        return None
    fs = [os.path.join(d, f) for f in os.listdir(d) if f.endswith(".jsonl")]
    return max(fs, key=os.path.getmtime) if fs else None


def read_turns(path):
    out, stamps = [], []
    if not path or not os.path.exists(path):
        return out, 0.0
    for line in open(path, encoding="utf-8", errors="ignore"):
        try:
            d = json.loads(line)
        except Exception:
            continue
        if d.get("kind") != "turn":
            continue
        out.append({"n": int(d.get("turn", 0)),
                    "speaker": str(d.get("display_name", "")).strip(),
                    "model": str(d.get("model_key", "")),
                    "latency_ms": int(d.get("latency_ms") or 0),
                    "text": str(d.get("text", ""))})
        if d.get("timestamp"):
            stamps.append(d["timestamp"])
    wall = 0.0
    if len(stamps) >= 2:
        import datetime
        wall = (datetime.datetime.fromisoformat(stamps[-1])
                - datetime.datetime.fromisoformat(stamps[0])).total_seconds()
    if out:
        wall += out[0]["latency_ms"] / 1000.0
    return out, wall


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cond", required=True, choices=sorted(CONDITIONS))
    ap.add_argument("--turns", type=int, default=15)
    ap.add_argument("--build", action="store_true")
    ap.add_argument("--label", default="",
                    help="write results under this name instead of --cond, so "
                         "several conditions can share one roster")
    ap.add_argument("--reply-words", dest="reply_words", default="",
                    help="MIN-MAX passed to live_match; the only variable in "
                         "the compression experiment")
    ap.add_argument("--max-tokens", dest="max_tokens", default="",
                    help="token ceiling passed to live_match")
    ap.add_argument("--pipeline", action="store_true",
                    help="one-turn-deep pipeline arm (now the default)")
    ap.add_argument("--no-pipeline", dest="no_pipeline", action="store_true",
                    help="baseline arm: sequential dispatch")
    ap.add_argument("--contention", action="store_true",
                    help="enable claim-scoped contention memory")
    ap.add_argument("--target-every", dest="target", default="",
                    help="targeted engagement event every N turns")
    ap.add_argument("--escalate-every", dest="escalate", default="",
                    help="inject a state event every N turns")
    ap.add_argument("--no-trim", dest="no_trim", action="store_true",
                    help="disable sentence trimming for an A/B arm")
    ap.add_argument("--reset", action="store_true",
                    help="clear memory and VRAM without rebuilding the roster")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    g = godot()
    flags = CONDITIONS[a.cond]
    name = a.label or a.cond
    path = os.path.join(OUT, name + ".json")

    if a.reset:
        # Same clean slate as --build, but keeps the roster on disk so several
        # conditions are measured against an identical set of models.
        print("freeing VRAM: %s" % ("ok" if lms_unload() else "lms unavailable"))
        p = os.path.join(USERDATA, "scar_lattice")
        if os.path.isdir(p):
            shutil.rmtree(p, ignore_errors=True)
        roster = json.load(open(os.path.join(ROOT, "config",
                                             "arena-roster.v1.json"), encoding="utf-8"))
        models = [ag["model_key"] for ag in roster["agents"]]
        rec = {"condition": name, "flags": flags, "roster": roster,
               "models": [], "distinct_models": len(set(models)),
               "roster_models": sorted(set(models)),
               "reply_words": a.reply_words or "(baseline)",
               "wall_sec": 0.0, "build_sec": 0.0, "chunks": 0,
               "timed_out": False, "speeches": [], "failures": []}
        json.dump(rec, open(path, "w", encoding="utf-8"), indent=1)
        print("reset %s against the existing roster (%d distinct models), reply_words=%s"
              % (name, len(set(models)), rec["reply_words"]))
        return

    if a.build:
        print("freeing VRAM: %s" % ("ok" if lms_unload() else "lms unavailable"))
        # NB: not `name` -- that is the condition label and shadowing it here
        # made --build report "built live_matches".
        for sub in ("scar_lattice", "live_matches"):
            p = os.path.join(USERDATA, sub)
            if os.path.isdir(p):
                shutil.rmtree(p, ignore_errors=True)
        t0 = time.time()
        subprocess.run([g, "--headless", "--path", ROOT, "--script",
                        "tools/build_roster.gd", "--"] + flags,
                       capture_output=True, text=True, encoding="utf-8",
                       errors="ignore", timeout=3600)
        roster = json.load(open(os.path.join(ROOT, "config",
                                             "arena-roster.v1.json"), encoding="utf-8"))
        models = [ag["model_key"] for ag in roster["agents"]]
        rec = {"condition": name, "flags": flags, "roster": roster,
               "models": [], "distinct_models": len(set(models)),
               "roster_models": sorted(set(models)),
               "wall_sec": 0.0, "build_sec": time.time() - t0,
               "chunks": 0, "timed_out": False, "speeches": [], "failures": []}
        json.dump(rec, open(path, "w", encoding="utf-8"), indent=1)
        print("built %s: %d agents, %d distinct model(s) in %.0fs"
              % (name, len(models), len(set(models)), rec["build_sec"]))
        print("  " + ", ".join(sorted(set(models))))
        return

    rec = json.load(open(path, encoding="utf-8"))
    before = newest_log()
    extra = ["--reply-words", a.reply_words] if a.reply_words else []
    if a.no_trim:
        extra.append("--no-trim")
    if a.max_tokens:
        extra += ["--max-tokens", a.max_tokens]
    if a.pipeline:
        extra.append("--pipeline")
    if a.no_pipeline:
        extra.append("--no-pipeline")
    if a.escalate:
        extra += ["--escalate-every", a.escalate]
    if a.target:
        extra += ["--target-every", a.target]
    if a.contention:
        extra.append("--contention")
    p = subprocess.run([g, "--headless", "--path", ROOT, "--script",
                        "scripts/arena/live_match.gd", "--",
                        "--turns", str(a.turns), "--no-wait",
                        "--exit-on-complete", "--timeout-sec", "120"] + extra,
                       capture_output=True, text=True, encoding="utf-8",
                       errors="ignore", timeout=3000)
    log = (p.stdout or "") + (p.stderr or "")
    cur = newest_log()
    if cur == before:
        print("no new match log; chunk produced nothing")
        return
    sp, wall = read_turns(cur)
    fails = [{"speaker": m.group(1).strip(), "why": m.group(2)}
             for m in (FAIL.match(l) for l in log.splitlines()) if m]

    for line in log.splitlines():
        if (line.startswith("LIVE_ARENA PIPELINE") or line.startswith("LIVE_ARENA DWELL")
                or line.startswith("LIVE_ARENA ESCALATION")
                or line.startswith("LIVE_ARENA TARGET")
                or line.startswith("LIVE_ARENA CONTENTION")):
            rec.setdefault("guards", []).append(line.strip())
    base = len(rec["speeches"])
    for s in sp:
        s["n"] += base
        s["chunk"] = rec["chunks"] + 1
    rec["speeches"].extend(sp)
    rec["failures"].extend(fails)
    rec["models"].extend(s["model"] for s in sp)
    rec["wall_sec"] += wall
    # Per-block wall time, because a block's throughput cannot be recovered by
    # dividing the total evenly: the first block after a VRAM reset pays cold
    # model loads and the rest do not.
    rec.setdefault("chunk_walls", []).append(wall)
    rec["chunks"] += 1
    json.dump(rec, open(path, "w", encoding="utf-8"), indent=1)
    print("%s chunk %d: +%d speeches (%d total), +%d failures, %.0fs (%.0fs total)"
          % (name, rec["chunks"], len(sp), len(rec["speeches"]),
             len(fails), wall, rec["wall_sec"]))


if __name__ == "__main__":
    main()
