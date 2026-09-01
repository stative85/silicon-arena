#!/usr/bin/env python3
"""Measure what JIT model swapping actually costs on a constrained GPU.

    python tools/bench_swap.py [--models N] [--rounds N] [--out FILE]

Talks to LM Studio directly over HTTP so the numbers describe the runtime, not
Godot. Requires LM Studio running with auto-unload / keep-last-model, which is
the configuration the arena is designed around.

Measures three things per model:
  cold    first request after another model was resident -> weights load
  warm    immediate second request while resident
  switch  cold latency attributable to the swap (cold - warm)

Reports median and p95 where the sample supports it. One machine, one run:
observational, not a universal benchmark.
"""

import argparse
import json
import statistics
import sys
import time
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:1234/v1"
PROMPT = "Reply with exactly: ok"


def _post(model: str, timeout: float) -> tuple[bool, float, str]:
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": PROMPT}],
        "max_tokens": 8,
        "temperature": 0.1,
        "stream": False,
    }).encode()
    req = urllib.request.Request(
        BASE + "/chat/completions", data=body,
        headers={"Content-Type": "application/json"})
    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            payload = json.loads(r.read())
        dt = time.perf_counter() - t0
        txt = payload["choices"][0]["message"].get("content", "") or ""
        return True, dt, txt.strip()[:40]
    except urllib.error.HTTPError as e:
        return False, time.perf_counter() - t0, f"HTTP {e.code}"
    except Exception as e:                      # noqa: BLE001
        return False, time.perf_counter() - t0, type(e).__name__


def catalog_eligible(path: str, ceiling: float) -> list[str]:
    with open(path, encoding="utf-8") as f:
        cat = json.load(f)
    out = []
    for m in cat.get("models", []):
        if not m.get("eligible"):
            continue
        p = m.get("paramsB")
        if p is None or float(p) > ceiling:
            continue
        out.append(m["modelKey"])
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", default="config/model-catalog.example.json")
    ap.add_argument("--models", type=int, default=4)
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--timeout", type=float, default=180.0)
    ap.add_argument("--ceiling", type=float, default=7.0)
    ap.add_argument("--out", default="")
    ap.add_argument("--only", default="",
                    help="comma-separated model ids to test instead of auto-selection")
    args = ap.parse_args()

    try:
        with urllib.request.urlopen(BASE + "/models", timeout=10) as r:
            installed = {m["id"] for m in json.loads(r.read()).get("data", [])}
    except Exception as e:                      # noqa: BLE001
        print(f"LM Studio not reachable at {BASE}: {e}", file=sys.stderr)
        return 2

    eligible = [m for m in catalog_eligible(args.catalog, args.ceiling) if m in installed]
    if len(eligible) < 2:
        print(f"need at least 2 installed eligible models, found {len(eligible)}", file=sys.stderr)
        return 2
    if args.only:
        wanted = [m.strip() for m in args.only.split(",") if m.strip()]
        missing = [m for m in wanted if m not in installed]
        if missing:
            print(f"not installed: {missing}", file=sys.stderr)
            return 2
        models = wanted
    else:
        # Spread across distinct model families rather than four builds of the
        # same one, otherwise the numbers describe one architecture.
        seen, models = set(), []
        for m in eligible:
            fam = m.split("/")[-1].split("-")[0]
            if fam in seen:
                continue
            seen.add(fam)
            models.append(m)
            if len(models) >= args.models:
                break

    print(f"models under test ({len(models)}):")
    for m in models:
        print(f"   {m}")
    print(f"rounds: {args.rounds}   ceiling: {args.ceiling}B\n")

    cold: dict[str, list[float]] = {m: [] for m in models}
    warm: dict[str, list[float]] = {m: [] for m in models}
    fails: dict[str, int] = {m: 0 for m in models}

    for rnd in range(args.rounds):
        for i, m in enumerate(models):
            # Force a swap: the previous model in the rotation is resident.
            ok, dt, note = _post(m, args.timeout)
            if ok:
                cold[m].append(dt)
            else:
                fails[m] += 1
            print(f"  r{rnd+1} cold  {m[:44]:<44} {dt:7.2f}s  {'ok' if ok else note}")

            ok2, dt2, note2 = _post(m, args.timeout)
            if ok2:
                warm[m].append(dt2)
            else:
                fails[m] += 1
            print(f"  r{rnd+1} warm  {m[:44]:<44} {dt2:7.2f}s  {'ok' if ok2 else note2}")

    def stat(v: list[float]) -> str:
        if not v:
            return "     n/a"
        med = statistics.median(v)
        if len(v) >= 5:
            p95 = sorted(v)[int(len(v) * 0.95) - 1]
            return f"{med:6.2f}s (p95 {p95:5.2f}s)"
        return f"{med:6.2f}s"

    lines = []
    lines.append("")
    lines.append(f"{'model':<46} {'cold median':>22} {'warm median':>14} {'swap cost':>11} {'fails':>6}")
    lines.append("-" * 104)
    swap_costs = []
    for m in models:
        c = statistics.median(cold[m]) if cold[m] else float("nan")
        w = statistics.median(warm[m]) if warm[m] else float("nan")
        sc = c - w if cold[m] and warm[m] else float("nan")
        if sc == sc:
            swap_costs.append(sc)
        lines.append(f"{m[:46]:<46} {stat(cold[m]):>22} {stat(warm[m]):>14} "
                     f"{sc:9.2f}s {fails[m]:6d}")
    total_req = sum(len(cold[m]) + len(warm[m]) for m in models) + sum(fails.values())
    total_fail = sum(fails.values())
    lines.append("-" * 104)
    if swap_costs:
        lines.append(f"median swap cost across models: {statistics.median(swap_costs):.2f}s")
        lines.append(f"max swap cost observed:         {max(swap_costs):.2f}s")
    lines.append(f"requests: {total_req}   failures: {total_fail} "
                 f"({100.0*total_fail/max(1,total_req):.1f}%)")
    out = "\n".join(lines)
    print(out)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(out + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
