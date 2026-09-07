"""RUNTIME-MEMORY orchestrator. REQUIRES EXPLICIT CLEARANCE TO RUN.

    python tools/runtime_memory_run.py --confirm-restarts

Four arms, each from a FRESH BACKEND. Refuses to do anything without
--confirm-restarts, because Amendment 2 authorised ONE specific restart
procedure for RECOVERY-COUPLING, not a standing licence to reboot the substrate.

Per arm, the frozen preflight -- identical for all four, only the workload
differs:

    fresh backend required
    exact pool count map = 1/1/1
    same runtime/version
    same health surface
    same model load order
    same observation cadence
    same resource sampling cadence
    same duration / horizon
    same start-state witness schema
    same termination rules

The backend is restarted ONLY at an arm boundary. Within an arm its process set
is fixed and the arm script verifies that at every sample.

CLIENT DISCONNECT IS A MEASURED TERMINAL PHASE, not cleanup:

    workload complete
    -> final live-client sample   (taken by the arm, inside the client)
    -> close client cleanly
    -> wait a fixed interval
    -> sample LM Studio RSS / host free
    -> backend REMAINS ALIVE

That separates memory tied to an active client/session, memory retained after
client exit, and memory retained until a backend restart -- without hand-waving
about leaks.
"""

import argparse
import ctypes
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(REPO, "docs", "results")
LMS = os.path.expanduser("~/.lmstudio/bin/lms.exe")
LMSTUDIO_EXE = r"C:\Program Files\LM Studio\LM Studio.exe"
GODOT = os.environ.get("GODOT") or os.path.expanduser(
    "~/Downloads/Godot_v4.6-stable_win64.exe/Godot_v4.6-stable_win64_console.exe")
MODELS_ENDPOINT = "http://127.0.0.1:1234/api/v0/models"

# Same model load order in every arm.
POOL = ["liquidai/lfm2.5-1.2b-instruct", "qwen3.5-2b",
        "falcon-h1-1.5b-instruct"]
CONTEXT = "8192"
ARMS = ["IDLE", "CONTROL_WORKLOAD", "RECOVERY_ONLY", "FULL_WINDOW"]
WINDOWS = 40                      # same duration / horizon for every arm
DISCONNECT_SAMPLES = [5, 15, 30, 60]   # seconds after client exit


def host_free_mb():
    class MS(ctypes.Structure):
        _fields_ = [("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong),
                    ("ullTotalPhys", ctypes.c_ulonglong),
                    ("ullAvailPhys", ctypes.c_ulonglong),
                    ("ullTotalPageFile", ctypes.c_ulonglong),
                    ("ullAvailPageFile", ctypes.c_ulonglong),
                    ("ullTotalVirtual", ctypes.c_ulonglong),
                    ("ullAvailVirtual", ctypes.c_ulonglong),
                    ("ullAvailExtendedVirtual", ctypes.c_ulonglong)]
    m = MS()
    m.dwLength = ctypes.sizeof(MS)
    ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m))
    return m.ullAvailPhys / 1048576.0


def lm_procs():
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq LM Studio.exe",
                          "/FO", "CSV", "/NH"], capture_output=True, text=True,
                         encoding="utf-8", errors="replace").stdout or ""
    pids, rss = [], 0.0
    for ln in out.splitlines():
        parts = [p.strip('"') for p in ln.split('","')]
        if len(parts) >= 5 and parts[1].isdigit():
            pids.append(int(parts[1]))
            rss += int(parts[4].replace(",", "").replace(" K", "")
                       .replace("K", "") or 0) / 1024.0
    return sorted(pids), rss


def resident():
    try:
        with urllib.request.urlopen(MODELS_ENDPOINT, timeout=10) as r:
            return [d.get("id", "") for d in
                    json.loads(r.read().decode("utf-8")).get("data", [])
                    if d.get("state", "not-loaded") != "not-loaded"]
    except Exception:                                    # noqa: BLE001
        return None


def counts():
    ids = resident()
    if ids is None:
        return None
    c = {}
    for i in ids:
        base = i
        if ":" in i and i.rsplit(":", 1)[1].isdigit():
            cand = i.rsplit(":", 1)[0]
            if cand in POOL:
                base = cand
        c[base] = c.get(base, 0) + 1
    return c


def vram():
    out = subprocess.run(["nvidia-smi", "--query-gpu=memory.used,memory.total",
                          "--format=csv,noheader,nounits"],
                         capture_output=True, text=True).stdout.strip()
    try:
        return [int(x.strip()) for x in out.split(",")]
    except Exception:                                    # noqa: BLE001
        return [-1, -1]


def restart_backend():
    """Called ONLY at an arm boundary. Never inside an arm."""
    subprocess.run([LMS, "server", "stop"], capture_output=True, text=True,
                   encoding="utf-8", errors="replace", timeout=120)
    subprocess.run(["taskkill", "/F", "/IM", "LM Studio.exe"],
                   capture_output=True, text=True)
    time.sleep(6)
    if lm_procs()[0] or resident() is not None:
        return None
    started = time.strftime("%Y-%m-%dT%H:%M:%S")
    subprocess.Popen([LMSTUDIO_EXE], stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL)
    for _ in range(60):
        time.sleep(2)
        subprocess.run([LMS, "server", "start"], capture_output=True,
                       text=True, encoding="utf-8", errors="replace")
        if resident() is not None:
            return started
    return None


def witness(arm, started_at):
    """Same start-state witness schema for every arm."""
    pids, rss = lm_procs()
    used, tot = vram()
    health = open(os.path.join(REPO, "scripts", "arena", "bridge_health.gd"),
                  "rb").read()
    ver = subprocess.run([LMS, "version"], capture_output=True, text=True,
                         encoding="utf-8", errors="replace").stdout
    commit = ""
    for ln in ver.splitlines():
        if "CLI commit" in ln:
            commit = ln.split(":")[-1].strip()
    return {
        "experiment_id": "RUNTIME-MEMORY", "arm": arm,
        "backend_fresh_start_at": started_at,
        "backend_pids": pids, "lms_rss_mb": round(rss),
        "residency_counts": counts(), "model_load_order": POOL,
        "vram_used_mib": used, "vram_total_mib": tot,
        "host_free_ram_mb": round(host_free_mb()),
        "runtime_version": "lms CLI commit " + commit,
        "health_surface_sha256": hashlib.sha256(health).hexdigest()[:16],
        "windows": WINDOWS,
        "at": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--confirm-restarts", action="store_true")
    ap.add_argument("--arms", nargs="*", default=ARMS)
    args = ap.parse_args()

    if not args.confirm_restarts:
        print("RUNTIME-MEMORY requires four full LM Studio restarts, one per arm.")
        print("Amendment 2 authorised ONE specific restart procedure for")
        print("RECOVERY-COUPLING; it is not a standing licence.")
        print("\nRefusing to run. Re-invoke with --confirm-restarts when cleared.")
        return 1

    out = {"experiment": "RUNTIME-MEMORY", "arms": {}, "windows": WINDOWS}
    for arm in args.arms:
        print("\n########## ARM %s ##########" % arm)
        started = restart_backend()          # arm boundary, and only here
        if not started:
            print("  FAIL backend did not restart cleanly")
            return 1
        for m in POOL:                        # same model load order
            if (counts() or {}).get(m, 0) < 1:
                subprocess.run([LMS, "load", m, "--gpu=max",
                                "--context-length=" + CONTEXT, "-y"],
                               capture_output=True, text=True,
                               encoding="utf-8", errors="replace", timeout=300)
        c = counts()
        if c != {m: 1 for m in POOL}:
            print("  FAIL exact pool count map = 1/1/1 not established: %s" % c)
            return 1
        w = witness(arm, started)
        print("  witness: pids=%s rss=%d MB host_free=%d MB vram=%d MiB"
              % (w["backend_pids"], w["lms_rss_mb"], w["host_free_ram_mb"],
                 w["vram_used_mib"]))

        log = os.path.join(RESULTS, "runtime_memory_%s.log" % arm)
        with open(log, "w", encoding="utf-8") as fh:
            subprocess.run([GODOT, "--headless", "--path", REPO, "--script",
                            "tools/runtime_memory.gd", "--",
                            "--arm=%s" % arm, "--windows=%d" % WINDOWS],
                           cwd=REPO, stdout=fh, stderr=subprocess.STDOUT,
                           text=True, encoding="utf-8", errors="replace")

        # CLIENT DISCONNECT, measured. The client has exited by now.
        post = []
        t0 = time.time()
        for s in DISCONNECT_SAMPLES:
            while time.time() - t0 < s:
                time.sleep(0.5)
            pids, rss = lm_procs()
            used, _ = vram()
            post.append({"seconds_after_client_exit": s, "lms_rss_mb": round(rss),
                         "host_free_ram_mb": round(host_free_mb()),
                         "vram_used_mib": used, "backend_pids": pids,
                         "backend_alive_after_disconnect": bool(pids)})
            print("    post_disconnect +%2ds  rss=%5d MB  host_free=%5d MB"
                  % (s, post[-1]["lms_rss_mb"], post[-1]["host_free_ram_mb"]))

        out["arms"][arm] = {"start_witness": w, "post_disconnect": post}
        json.dump(out, open(os.path.join(RESULTS, "RUNTIME_MEMORY_RUN.json"),
                            "w", encoding="utf-8"), indent=2)

    print("\nall arms complete; per-arm traces in RUNTIME_MEMORY_<ARM>.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
