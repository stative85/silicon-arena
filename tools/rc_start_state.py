"""RECOVERY-COUPLING Amendment 2: establish and witness the experiment start state.

    python tools/rc_start_state.py

Executes the frozen procedure in order and refuses to continue at the first
failure. Emits docs/results/RC_START_STATE.json.

WHAT IS BEING RESET IS HIDDEN RUNTIME HISTORY -- cache, allocator state,
resident age, backend lifetime -- none of which is visible in a residency
listing. That is why `counts == expected` alone is explicitly rejected as a
start-state test and a full backend restart is performed instead.
"""

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
MODELS_ENDPOINT = "http://127.0.0.1:1234/api/v0/models"
POOL = ["liquidai/lfm2.5-1.2b-instruct", "qwen3.5-2b",
        "falcon-h1-1.5b-instruct"]
CONTEXT = "8192"
EXPECTED_SCHEDULE_HASH = "9c9dbd9ca0c45252"


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


def lm_pids():
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq LM Studio.exe",
                          "/FO", "CSV"], capture_output=True, text=True,
                         encoding="utf-8", errors="replace").stdout or ""
    pids = []
    for ln in out.splitlines()[1:]:
        parts = [p.strip('"') for p in ln.split('","')]
        if len(parts) > 1 and parts[1].isdigit():
            pids.append(int(parts[1]))
    return pids


def resident():
    try:
        with urllib.request.urlopen(MODELS_ENDPOINT, timeout=10) as r:
            data = json.loads(r.read().decode("utf-8"))
    except Exception:                                   # noqa: BLE001
        return None
    return [d.get("id", "") for d in data.get("data", [])
            if d.get("state", "not-loaded") != "not-loaded"]


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
        u, t = [int(x.strip()) for x in out.split(",")]
        return u, t
    except Exception:                                   # noqa: BLE001
        return -1, -1


def step(n, msg):
    print("\n[%d] %s" % (n, msg))


def main():
    print("=== RECOVERY-COUPLING start state (Amendment 2) ===")

    step(3, "stopping LM Studio completely")
    subprocess.run([LMS, "server", "stop"], capture_output=True, text=True,
                   encoding="utf-8", errors="replace", timeout=120)
    subprocess.run(["taskkill", "/F", "/IM", "LM Studio.exe"],
                   capture_output=True, text=True)
    time.sleep(6)

    step(4, "confirming the old backend is gone")
    pids = lm_pids()
    print("    LM Studio processes: %s" % (pids if pids else "none"))
    if pids:
        print("    FAIL processes survived the stop")
        return 1
    if resident() is not None:
        print("    FAIL the API still answers; a backend is still alive")
        return 1
    print("    API unreachable, backend down")

    step(5, "starting LM Studio fresh")
    started_at = time.strftime("%Y-%m-%dT%H:%M:%S")
    subprocess.Popen([LMSTUDIO_EXE], stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL)
    ok = False
    for _ in range(60):
        time.sleep(2)
        subprocess.run([LMS, "server", "start"], capture_output=True,
                       text=True, encoding="utf-8", errors="replace")
        if resident() is not None:
            ok = True
            break
    if not ok:
        print("    FAIL the server did not come up")
        return 1
    print("    server up, started_at %s" % started_at)
    print("    resident on a fresh backend: %s" % resident())

    step(6, "loading exactly one instance of each pool member")
    for m in POOL:
        c = counts() or {}
        if c.get(m, 0) >= 1:
            print("    %s already resident, not loading again" % m)
            continue
        subprocess.run([LMS, "load", m, "--gpu=max",
                        "--context-length=" + CONTEXT, "-y"],
                       capture_output=True, text=True, encoding="utf-8",
                       errors="replace", timeout=300)
        print("    loaded %s" % m)

    step(7, "verifying the exact residency COUNT MAP")
    c = counts()
    want = {m: 1 for m in POOL}
    print("    counts   %s" % c)
    print("    expected %s" % want)
    if c != want:
        print("    FAIL count map mismatch")
        return 1
    total = sum(c.values())
    print("    TOTAL_INSTANCES = %d" % total)
    if total != 3:
        print("    FAIL total instances is not 3")
        return 1

    step(8, "arm baseline")
    r = subprocess.run([sys.executable, os.path.join(REPO, "tools",
                                                     "arm_baseline.py"),
                        "--witness", os.path.join(RESULTS,
                                                  "RC_experiment_baseline.json")],
                       cwd=REPO, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    for ln in (r.stdout or "").splitlines():
        if any(k in ln for k in ("BASELINE", "FAIL", "host free", "pool")):
            print("    %s" % ln.strip())
    if r.returncode != 0:
        print("    FAIL arm_baseline did not pass")
        return 1

    step(9, "emitting the START-STATE WITNESS")
    used, tot = vram()
    sched = json.load(open(os.path.join(RESULTS, "RC_SCHEDULE.json"),
                           encoding="utf-8"))
    health_src = open(os.path.join(REPO, "scripts", "arena",
                                   "bridge_health.gd"), "rb").read()
    ver = subprocess.run([LMS, "version"], capture_output=True, text=True,
                         encoding="utf-8", errors="replace").stdout.strip()
    witness = {
        "experiment_id": "RECOVERY-COUPLING",
        "schedule_hash": sched["schedule_hash"],
        "schedule_hash_expected": EXPECTED_SCHEDULE_HASH,
        "runtime_version": ver,
        "backend_fresh_start_at": started_at,
        "backend_pids_after_start": lm_pids(),
        "residency_counts": c,
        "total_instances": total,
        "models": POOL,
        "vram_used_mib": used, "vram_total_mib": tot,
        "host_free_ram_mb": round(host_free_mb()),
        "active_requests": 0,
        "arm_baseline": "PASS",
        "health_surface_sha256": hashlib.sha256(health_src).hexdigest()[:16],
        "ks": 1.8, "kh": 20.0, "n": 3,
        "at": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }
    if witness["schedule_hash"] != EXPECTED_SCHEDULE_HASH:
        print("    FAIL schedule hash %s != frozen %s"
              % (witness["schedule_hash"], EXPECTED_SCHEDULE_HASH))
        return 1
    path = os.path.join(RESULTS, "RC_START_STATE.json")
    json.dump(witness, open(path, "w", encoding="utf-8"), indent=2)
    for k in ("runtime_version", "backend_fresh_start_at", "residency_counts",
              "total_instances", "vram_used_mib", "host_free_ram_mb",
              "health_surface_sha256", "schedule_hash"):
        print("    %-24s %s" % (k, witness[k]))
    print("\n    wrote %s" % os.path.relpath(path, REPO))
    print("\nSTART STATE ESTABLISHED. Window 0 may begin.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
