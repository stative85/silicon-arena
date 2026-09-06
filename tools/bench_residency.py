#!/usr/bin/env python3
"""EXPLICIT_RESIDENCY_MODE throughput benchmark for the five-species pool.

    python tools/bench_residency.py --out D:/bench_out.json

WHAT THIS IS. Hardware and runtime characterisation for a future inference
bridge. It does NOT modify PIT A, SWARM or METABOLISM, and it makes no claim
about any model's quality. The question is:

    "What service topology does the resident pool actually provide?"

NOT "which model is smartest".

REGIME. All five models are explicitly preloaded before measurement and never
unloaded between requests. JIT acquisition is never relied on -- under
JIT_RESIDENCY_MODE a request evicts the previously JIT-loaded model, which is a
different regime entirely and its numbers are not comparable
(docs/EXPERIMENT_METABOLISM.md, correction-to-the-correction).

Residency is asserted before AND after every case. If it changes, the case is
marked FAILED, what disappeared is recorded, the pool is rebuilt, and the run
continues -- never silently under a different regime.

STREAMING is used so time-to-first-token is actually measurable rather than
inferred from total latency.
"""
import argparse
import builtins
import functools
import json
import statistics
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

print = functools.partial(builtins.print, flush=True)  # unbuffered progress

BASE = "http://127.0.0.1:1234"
LMS = r"C:\Users\cleve\.lmstudio\bin\lms.exe"
CTX = 8192

MODELS = [
    "h2o-danube2-1.8b-chat",
    "liquidai/lfm2.5-1.2b-instruct",
    "qwen3.5-2b",
    "falcon-h1-1.5b-instruct",
    "rwkv7-1.5b-g1",
]
SHORT = {m: m.split("/")[-1].split("-")[0] for m in MODELS}


# --------------------------------------------------------------- telemetry

def nvidia(fields):
    try:
        out = subprocess.run(
            ["nvidia-smi", "--query-gpu=" + ",".join(fields),
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=15)
        vals = out.stdout.strip().split("\n")[0].split(",")
        return [float(v.strip()) for v in vals]
    except Exception:
        return [None] * len(fields)


def vram_mib():
    return nvidia(["memory.used"])[0]


def gpu_sample():
    u, m, p, t = nvidia(["utilization.gpu", "utilization.memory",
                         "power.draw", "temperature.gpu"])
    return {"gpu_util": u, "mem_util": m, "power_w": p, "temp_c": t}


def resident():
    try:
        with urllib.request.urlopen(BASE + "/api/v0/models", timeout=30) as r:
            d = json.loads(r.read().decode())
        return sorted(m["id"] for m in d.get("data", [])
                      if m.get("state") != "not-loaded")
    except Exception:
        return []


def preload_pool():
    """Explicitly load all five. Never unload between cases."""
    have = set(resident())
    for m in MODELS:
        if m in have:
            continue
        subprocess.run([LMS, "load", m, "--context-length", str(CTX),
                        "--gpu", "max", "-y"],
                       capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=600)
    return resident()


def pool_intact():
    r = set(resident())
    missing = [m for m in MODELS if m not in r]
    return (not missing), missing, sorted(r)


# ----------------------------------------------------------------- request

## Bounded per-request ceiling. The slowest solo request measured is ~5 s, so
## 120 s is far outside the legitimate distribution: anything reaching it is a
## wedge, not slow work. Without this the harness can block indefinitely.
REQUEST_TIMEOUT_S = 120

WEDGE_EVENTS = []


def health_probe(model):
    """Is this model still answering at all? A wedged instance stays RESIDENT,
    so the residency check cannot see it -- this is the separate tooth."""
    r = stream_request(model, "Say OK.", 8, timeout_s=45)
    return r["ok"]


def unwedge(model, where):
    """A wedged model poisons every later measurement of it. Reload it and
    record the event: an aborted or stalled stream permanently wedging an
    instance is a runtime property the bridge has to handle, not noise."""
    ev = {"model": model, "at": where, "time": time.strftime("%H:%M:%S")}
    print("    *** WEDGED: %s at %s -- reloading" % (SHORT.get(model, model), where))
    subprocess.run([LMS, "unload", model], capture_output=True, text=True,
            encoding="utf-8", errors="replace",
                   timeout=300)
    subprocess.run([LMS, "load", model, "--context-length", str(CTX),
                    "--gpu", "max", "-y"],
                   capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=600)
    ev["recovered"] = health_probe(model)
    WEDGE_EVENTS.append(ev)
    return ev["recovered"]


def stream_request(model, prompt, max_tokens, timeout_s=REQUEST_TIMEOUT_S):
    """One streamed completion. Returns a per-request record."""
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens, "temperature": 0.0, "stream": True,
    }).encode()
    req = urllib.request.Request(
        BASE + "/v1/chat/completions", data=body,
        headers={"Content-Type": "application/json"})
    rec = {"model": model, "ok": False, "ttft_ms": None, "total_ms": None,
           "generated_tokens": 0, "error": None}
    submitted = time.perf_counter()
    first = None
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            for raw in resp:
                line = raw.decode("utf-8", "replace").strip()
                if not line.startswith("data:"):
                    continue
                payload = line[5:].strip()
                if payload == "[DONE]":
                    break
                try:
                    chunk = json.loads(payload)
                except Exception:
                    continue
                delta = chunk.get("choices", [{}])[0].get("delta", {})
                if delta.get("content"):
                    if first is None:
                        first = time.perf_counter()
                    rec["generated_tokens"] += 1
        done = time.perf_counter()
        rec["ok"] = True
        rec["total_ms"] = (done - submitted) * 1000.0
        rec["ttft_ms"] = (first - submitted) * 1000.0 if first else None
        gen_s = (done - first) if first else 0.0
        rec["decode_tps"] = (rec["generated_tokens"] / gen_s) if gen_s > 0 else None
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        rec["error"] = str(e)[:120]
        rec["total_ms"] = (time.perf_counter() - submitted) * 1000.0
    return rec


# --------------------------------------------------------------- workloads

def workload_a():
    return ("Reply with one JSON object: {\"operation\":\"KEEP\"}", 32)


def workload_b():
    world = ("[objects]\n" + "\n".join(
        '  "obj_%d" type="rule" props={"text":"line %d"}' % (i, i)
        for i in range(8)))
    return ("Given this world, choose one action and explain briefly.\n"
            + world + "\nAnswer in two sentences.", 96)


def workload_c(target_tokens):
    # The filler must be longer than the deepest request, or a deep case
    # silently truncates and measures a shallower depth than it reports.
    # At ~4 chars/token, 7000 tokens needs 28,000 chars; 2000 repeats is ample.
    filler = ("The arena records a canonical world of typed objects. " * 2000)
    approx_chars = target_tokens * 4
    assert len(filler) >= approx_chars, "filler too short for depth"
    return ("Summarise the state below in one sentence.\n"
            + filler[:approx_chars], 48)


# ----------------------------------------------------------- measurements

def pct(vals, q):
    vals = sorted(v for v in vals if v is not None)
    if not vals:
        return None
    k = min(int(round((q / 100.0) * (len(vals) - 1))), len(vals) - 1)
    return vals[k]


def summarise(records):
    ok = [r for r in records if r["ok"]]
    tot = [r["total_ms"] for r in ok]
    ttft = [r["ttft_ms"] for r in ok if r["ttft_ms"] is not None]
    tps = [r["decode_tps"] for r in ok if r.get("decode_tps")]
    return {
        "n": len(records), "ok": len(ok), "failed": len(records) - len(ok),
        "total_ms_median": statistics.median(tot) if tot else None,
        "total_ms_p95": pct(tot, 95),
        "ttft_ms_median": statistics.median(ttft) if ttft else None,
        "ttft_ms_p95": pct(ttft, 95),
        "decode_tps_median": statistics.median(tps) if tps else None,
        "tokens": sum(r["generated_tokens"] for r in ok),
    }


def _walk_records(out):
    """Every per-request record, whatever shape the phase returned.
    solo -> [rec]; concurrency -> [{records:[rec]}]; sustained -> {records:[rec]}
    """
    if isinstance(out, dict):
        return [r for r in out.get("records", []) if r]
    recs = []
    for item in out or []:
        if isinstance(item, dict) and "records" in item:
            recs.extend(r for r in item["records"] if r)
        elif isinstance(item, dict):
            recs.append(item)
    return recs


def guarded(name, fn, results):
    """Run a case with residency asserted before and after."""
    ok_before, missing_before, before = pool_intact()
    v0 = vram_mib()
    if not ok_before:
        print("    REBUILDING POOL before %s (missing %s)" % (name, missing_before))
        preload_pool()
        ok_before, missing_before, before = pool_intact()
    out = fn()

    # A wedged model stays RESIDENT, so the residency check below cannot see
    # it. Any model that timed out in this case is probed and, if dead,
    # reloaded -- otherwise every later measurement of it is of a corpse.
    timed_out = set()
    for rec in _walk_records(out):
        if not rec.get("ok") and "timed out" in str(rec.get("error", "")):
            timed_out.add(rec["model"])
    wedged = []
    for m in sorted(timed_out):
        if not health_probe(m):
            unwedge(m, name)
            wedged.append(m)

    ok_after, missing_after, after = pool_intact()
    v1 = vram_mib()
    case = {"case": name, "resident_before": before, "resident_after": after,
            "vram_before_mib": v0, "vram_after_mib": v1,
            "gpu": gpu_sample(), "regime_held": ok_before and ok_after
            and not wedged,
            "missing_after": missing_after, "wedged": wedged, "data": out}
    if not case["regime_held"]:
        case["FAILED"] = ("model wedged during the case" if wedged
                          else "residency changed during the case")
        print("    *** FAILED: %s (missing=%s wedged=%s)"
              % (case["FAILED"], missing_after or "none",
                 [SHORT.get(m, m) for m in wedged] or "none"))
        preload_pool()
    results.append(case)
    return case


# ------------------------------------------------------------------ phases

def solo(results, reps):
    print("\n[SOLO BASELINE] %d measured requests per model per workload" % reps)
    loads = [("A_micro", workload_a()), ("B_turn", workload_b()),
             ("C_256", workload_c(256)), ("C_1024", workload_c(1024)),
             ("C_4096", workload_c(4096)), ("C_7000", workload_c(7000))]
    for wname, (prompt, mx) in loads:
        for m in MODELS:
            def run(m=m, prompt=prompt, mx=mx):
                for _ in range(3):                     # warmup, discarded
                    stream_request(m, prompt, mx)
                return [stream_request(m, prompt, mx) for _ in range(reps)]
            c = guarded("solo/%s/%s" % (wname, SHORT[m]), run, results)
            s = summarise(c["data"])
            c["summary"] = s
            print("   %-10s %-9s med %7.0f ms  p95 %7.0f  TTFT med %6.0f  "
                  "tps %5.1f  fail %d"
                  % (wname, SHORT[m], s["total_ms_median"] or -1,
                     s["total_ms_p95"] or -1, s["ttft_ms_median"] or -1,
                     s["decode_tps_median"] or -1, s["failed"]))


def barrier_run(models, prompt, mx, trials):
    """All requests genuinely begin together."""
    out = []
    for _ in range(trials):
        barrier = threading.Barrier(len(models))
        recs = [None] * len(models)

        def worker(i, m):
            barrier.wait()
            recs[i] = stream_request(m, prompt, mx)

        threads = [threading.Thread(target=worker, args=(i, m))
                   for i, m in enumerate(models)]
        t0 = time.perf_counter()
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        wall = (time.perf_counter() - t0) * 1000.0
        out.append({"wall_ms": wall, "records": recs})
    return out


def concurrency(results, trials):
    print("\n[CONCURRENCY] barrier-synchronised, %d trials each" % trials)
    prompt, mx = workload_b()
    D, L, Q, F, R = MODELS[0], MODELS[1], MODELS[2], MODELS[3], MODELS[4]
    combos = [
        ("2way/fast+fast", [L, R]), ("2way/fast+slow", [L, D]),
        ("2way/slow+slow", [F, D]), ("2way/med+slow", [Q, D]),
        ("3way/fast", [L, R, Q]), ("3way/mixed", [L, F, D]),
        ("3way/slow", [Q, F, D]), ("5way/all", MODELS),
    ]
    for name, ms in combos:
        c = guarded("conc/%s" % name,
                    lambda ms=ms: barrier_run(ms, prompt, mx, trials), results)
        per = {}
        walls = []
        for trial in c["data"]:
            walls.append(trial["wall_ms"])
            for rec in trial["records"]:
                if rec and rec["ok"]:
                    per.setdefault(rec["model"], []).append(rec["total_ms"])
        c["summary"] = {"wall_ms_median": statistics.median(walls),
                        "per_model_median": {SHORT[k]: statistics.median(v)
                                             for k, v in per.items()}}
        print("   %-16s wall med %7.0f ms   %s"
              % (name, c["summary"]["wall_ms_median"],
                 {k: int(v) for k, v in c["summary"]["per_model_median"].items()}))


def sustained(results, total, levels):
    print("\n[SUSTAINED QUEUE] %d requests per in-flight level" % total)
    prompt, mx = workload_b()
    order = [MODELS[i % len(MODELS)] for i in range(total)]
    for inflight in levels:
        def run(inflight=inflight):
            recs = []
            lock = threading.Lock()
            idx = [0]
            sem = threading.Semaphore(inflight)
            threads = []

            def worker():
                while True:
                    with lock:
                        if idx[0] >= total:
                            return
                        i = idx[0]
                        idx[0] += 1
                    with sem:
                        r = stream_request(order[i], prompt, mx)
                    with lock:
                        recs.append(r)

            t0 = time.perf_counter()
            for _ in range(inflight):
                t = threading.Thread(target=worker)
                t.start()
                threads.append(t)
            for t in threads:
                t.join()
            return {"wall_s": time.perf_counter() - t0, "records": recs}

        c = guarded("sustained/inflight_%d" % inflight, run, results)
        d = c["data"]
        ok = [r for r in d["records"] if r["ok"]]
        per = {}
        for r in ok:
            per.setdefault(r["model"], []).append(r["total_ms"])
        c["summary"] = {
            "wall_s": d["wall_s"],
            "req_per_s": len(ok) / d["wall_s"] if d["wall_s"] else None,
            "tokens_per_s": sum(r["generated_tokens"] for r in ok) / d["wall_s"],
            "failed": len(d["records"]) - len(ok),
            "per_model_median_ms": {SHORT[k]: statistics.median(v)
                                    for k, v in per.items()},
            "per_model_p95_ms": {SHORT[k]: pct(v, 95) for k, v in per.items()},
        }
        s = c["summary"]
        print("   inflight=%d  wall %6.1f s  %5.2f req/s  %6.1f tok/s  fail %d"
              % (inflight, s["wall_s"], s["req_per_s"] or -1,
                 s["tokens_per_s"], s["failed"]))
        print("      median per model: %s"
              % {k: int(v) for k, v in s["per_model_median_ms"].items()})


def derive(results):
    """slowdown_ratio and throughput_gain, per model and per level.

    Ratios of measured medians. Never a blended score -- the whole point is the
    structure that a single number would average away.
    """
    print("\n[DERIVED]")
    solo_med = {}
    for c in results:
        if c["case"].startswith("solo/B_turn/") and c.get("summary"):
            solo_med[c["case"].split("/")[-1]] = c["summary"]["total_ms_median"]

    out = {"solo_B_turn_median_ms": solo_med, "slowdown_ratio": {},
           "throughput_gain": {}}

    print("  slowdown_ratio = concurrent_median / solo_median  (B_turn)")
    for c in results:
        if not c["case"].startswith("conc/") or not c.get("summary"):
            continue
        row = {}
        for short, med in c["summary"]["per_model_median"].items():
            base = solo_med.get(short)
            if base:
                row[short] = round(med / base, 2)
        out["slowdown_ratio"][c["case"]] = row
        flag = "" if c.get("regime_held") else "   [REGIME FAILED]"
        print("   %-18s %s%s" % (c["case"].split("/", 1)[1], row, flag))

    print("  throughput_gain = req_per_s(N) / req_per_s(1)")
    base_rps = None
    for c in results:
        if c["case"] == "sustained/inflight_1" and c.get("summary"):
            base_rps = c["summary"]["req_per_s"]
    for c in results:
        if not c["case"].startswith("sustained/") or not c.get("summary"):
            continue
        rps = c["summary"]["req_per_s"]
        gain = round(rps / base_rps, 2) if base_rps and rps else None
        out["throughput_gain"][c["case"]] = gain
        print("   %-22s %5.2f req/s   gain %sx" % (c["case"], rps or -1, gain))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="D:/bench_residency.json")
    ap.add_argument("--reps", type=int, default=10)
    ap.add_argument("--trials", type=int, default=3)
    ap.add_argument("--sustained", type=int, default=100)
    a = ap.parse_args()

    print("=== EXPLICIT_RESIDENCY_MODE throughput benchmark ===")
    print("Hardware/runtime characterisation. No model-quality claims.\n")
    print("preloading the five-model pool explicitly...")
    pool = preload_pool()
    ok, missing, res = pool_intact()
    print("  resident: %d/%d  %s" % (len(res), len(MODELS),
                                     "OK" if ok else "MISSING %s" % missing))
    print("  VRAM: %.0f MiB" % (vram_mib() or -1))
    if not ok:
        print("\nCANNOT ESTABLISH THE POOL. Aborting rather than measuring a "
              "different regime.")
        return 1

    results = []
    solo(results, a.reps)
    concurrency(results, a.trials)
    sustained(results, a.sustained, [1, 2, 3, 5])

    derived = derive(results)

    with open(a.out, "w", encoding="utf-8") as f:
        json.dump({"regime": "EXPLICIT_RESIDENCY_MODE", "models": MODELS,
                   "context": CTX, "cases": results, "derived": derived,
                   "wedge_events": WEDGE_EVENTS}, f,
                  indent=1)
    print("\nwrote %s" % a.out)
    failed = [c["case"] for c in results if not c.get("regime_held")]
    print("cases where the regime did not hold: %s" % (failed or "none"))
    print("wedge events: %d %s" % (len(WEDGE_EVENTS),
          [(SHORT.get(e["model"], e["model"]), e["at"], e["recovered"])
           for e in WEDGE_EVENTS]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
