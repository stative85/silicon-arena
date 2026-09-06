#!/usr/bin/env python3
"""Is the five-model pool's latency spread architecture, or VRAM pressure?

    python tools/bench_pressure.py

WHY THIS EXISTS. The pool occupies 7,710 of 8,151 MiB -- 441 MiB of headroom.
The observed solo spread across the five species is ~17x. Two very different
explanations fit that number equally well:

  (a) ARCHITECTURAL. The species genuinely differ in cost per token, and the
      spread would look the same on an empty card.
  (b) PRESSURE. Co-residency at 8192 context degrades some members -- KV cache
      placement, offload, or allocator thrash -- and the spread is partly an
      artifact of running five models on a card that fits four comfortably.

These have opposite consequences for an inference bridge. Under (a) the slow
species are simply expensive and scheduling must route around them. Under (b)
the pool size is itself the problem and a smaller resident set would be faster
for everyone.

THE MEASUREMENT. Each model is timed twice on the identical workload:

    ALONE_IN_POOL   that model is the only one loaded
    FULL_POOL       all five loaded, this one exercised

Both are EXPLICIT_RESIDENCY_MODE -- no JIT anywhere -- so the only variable is
how many other models are resident. The ratio is the pressure penalty.

This does not modify PIT A, SWARM or METABOLISM, and makes no quality claims.
"""
import builtins
import functools
import json
import statistics
import subprocess
import sys
import time
import urllib.error
import urllib.request

print = functools.partial(builtins.print, flush=True)

BASE = "http://127.0.0.1:1234"
LMS = r"C:\Users\cleve\.lmstudio\bin\lms.exe"
CTX = 8192
REPS = 5
WARMUP = 2

MODELS = [
    "h2o-danube2-1.8b-chat",
    "liquidai/lfm2.5-1.2b-instruct",
    "qwen3.5-2b",
    "falcon-h1-1.5b-instruct",
    "rwkv7-1.5b-g1",
]
SHORT = {m: m.split("/")[-1].split("-")[0] for m in MODELS}

PROMPT = "Given a world of typed objects, choose one action. Answer briefly."
MAX_TOKENS = 64


def sh(args, timeout=600):
    return subprocess.run(args, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=timeout)


def vram():
    try:
        o = sh(["nvidia-smi", "--query-gpu=memory.used",
                "--format=csv,noheader,nounits"], timeout=15)
        return float(o.stdout.strip().split("\n")[0])
    except Exception:
        return None


def resident():
    try:
        with urllib.request.urlopen(BASE + "/api/v0/models", timeout=30) as r:
            d = json.loads(r.read().decode())
        return sorted(m["id"] for m in d.get("data", [])
                      if m.get("state") != "not-loaded")
    except Exception:
        return []


def load(m):
    sh([LMS, "load", m, "--context-length", str(CTX), "--gpu", "max", "-y"])


def unload_all():
    sh([LMS, "unload", "--all"], timeout=300)


def timed(model, timeout_s=180):
    body = json.dumps({
        "model": model, "messages": [{"role": "user", "content": PROMPT}],
        "max_tokens": MAX_TOKENS, "temperature": 0.0, "stream": True,
    }).encode()
    req = urllib.request.Request(BASE + "/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json"})
    t0 = time.perf_counter()
    first = None
    n = 0
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            for raw in resp:
                line = raw.decode("utf-8", "replace").strip()
                if not line.startswith("data:"):
                    continue
                p = line[5:].strip()
                if p == "[DONE]":
                    break
                delta = json.loads(p).get("choices", [{}])[0].get("delta", {})
                if delta.get("content"):
                    if first is None:
                        first = time.perf_counter()
                    n += 1
        end = time.perf_counter()
        gen = (end - first) if first else 0.0
        return {"ok": True, "total_ms": (end - t0) * 1000.0,
                "ttft_ms": (first - t0) * 1000.0 if first else None,
                "tokens": n, "tps": (n / gen) if gen > 0 else None}
    except Exception as e:
        return {"ok": False, "error": str(e)[:100],
                "total_ms": (time.perf_counter() - t0) * 1000.0, "tokens": n}


def measure(model):
    for _ in range(WARMUP):
        timed(model)
    recs = [timed(model) for _ in range(REPS)]
    ok = [r for r in recs if r["ok"]]
    if not ok:
        return {"ok": 0, "failed": len(recs)}
    return {
        "ok": len(ok), "failed": len(recs) - len(ok),
        "total_ms_median": statistics.median(r["total_ms"] for r in ok),
        "ttft_ms_median": statistics.median(
            r["ttft_ms"] for r in ok if r["ttft_ms"] is not None),
        "tps_median": statistics.median(
            r["tps"] for r in ok if r["tps"]),
        "tokens_median": statistics.median(r["tokens"] for r in ok),
    }


def main():
    print("=== pool pressure: ALONE_IN_POOL vs FULL_POOL ===")
    print("Both EXPLICIT_RESIDENCY_MODE. Only the resident-set size varies.\n")
    out = {"regime": "EXPLICIT_RESIDENCY_MODE", "context": CTX,
           "prompt_max_tokens": MAX_TOKENS, "alone": {}, "full": {}}

    print("[ALONE_IN_POOL] one model resident at a time")
    for m in MODELS:
        unload_all()
        load(m)
        r = resident()
        if r != [m]:
            print("   %-9s SKIPPED, resident set is %s" % (SHORT[m], r))
            continue
        v = vram()
        s = measure(m)
        s["vram_mib"] = v
        out["alone"][SHORT[m]] = s
        print("   %-9s med %7.0f ms  ttft %6.0f  %6.2f tok/s  vram %5.0f MiB"
              % (SHORT[m], s.get("total_ms_median", -1),
                 s.get("ttft_ms_median", -1), s.get("tps_median", -1), v or -1))

    print("\n[FULL_POOL] all five resident")
    unload_all()
    for m in MODELS:
        load(m)
    r = resident()
    if len(r) != len(MODELS):
        print("   POOL INCOMPLETE: %s -- aborting rather than mislabelling" % r)
        return 1
    v = vram()
    print("   resident: %d/5   vram %.0f MiB" % (len(r), v or -1))
    for m in MODELS:
        s = measure(m)
        s["vram_mib"] = v
        out["full"][SHORT[m]] = s
        print("   %-9s med %7.0f ms  ttft %6.0f  %6.2f tok/s"
              % (SHORT[m], s.get("total_ms_median", -1),
                 s.get("ttft_ms_median", -1), s.get("tps_median", -1)))

    print("\n[PRESSURE PENALTY] full_pool_median / alone_median")
    out["penalty"] = {}
    for m in MODELS:
        k = SHORT[m]
        a = out["alone"].get(k, {}).get("total_ms_median")
        f = out["full"].get(k, {}).get("total_ms_median")
        if a and f:
            out["penalty"][k] = round(f / a, 2)
            print("   %-9s %5.2fx" % (k, f / a))

    for label, key in (("ALONE_IN_POOL", "alone"), ("FULL_POOL", "full")):
        meds = [v["total_ms_median"] for v in out[key].values()
                if v.get("total_ms_median")]
        if len(meds) > 1:
            spread = max(meds) / min(meds)
            out.setdefault("spread", {})[key] = round(spread, 1)
            print("   spread %-14s %5.1fx" % (label, spread))

    with open("D:/bench_pressure.json", "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=1)
    print("\nwrote D:/bench_pressure.json")
    print("\nNOTE: this leaves the full pool loaded.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
