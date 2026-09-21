#!/usr/bin/env python3
"""Does the degraded-mode detector actually bite?

    python tools/bench_residency_selftest.py

WHY THIS FILE EXISTS. The first EXPLICIT_RESIDENCY_MODE run reported `fail 0`
and `regime_held` while qwen3.5 executed at ~2.4 tok/s for five consecutive
cases. The residency assertion and the liveness probe both passed it: the model
was loaded and it answered. A check added to close that hole is worthless
unless the hole is demonstrated closed, so each case below is the sabotage
first and the assertion second.

Offline. No GPU, no LM Studio, no inference. The detector is fed synthetic
records in all three shapes the phases actually return, because a detector that
works on the solo shape and silently walks nothing on the sustained shape would
report a clean run either way -- which is the original defect wearing a
different hat.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def load():
    spec = importlib.util.spec_from_file_location(
        "bench_residency", os.path.join(HERE, "bench_residency.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def recs(model, tps, n=5):
    return [{"model": model, "ok": True, "decode_tps": tps} for _ in range(n)]


# The three shapes phases return. _walk_records must handle all three.
SHAPES = {
    "solo": lambda r: r,
    "concurrency": lambda r: [{"records": r}],
    "sustained": lambda r: {"records": r},
}

# label, calibration, model, observed tok/s, must_catch
CASES = [
    ("historical defect: qwen resident at 2.4 tok/s",
     {"qwen3.5-2b": 210.0}, "qwen3.5-2b", 2.4, True),
    ("slowest species at its own healthy rate is NOT a fault",
     {"rwkv7-1.5b-g1": 45.0}, "rwkv7-1.5b-g1", 45.0, False),
    ("slowest species spilled -- absolute floor catches it",
     {"rwkv7-1.5b-g1": 45.0}, "rwkv7-1.5b-g1", 2.5, True),
    ("half its own rate is within band, not a regime failure",
     {"qwen3.5-2b": 210.0}, "qwen3.5-2b", 105.0, False),
    ("30% of its own rate, still above absolute floor",
     {"qwen3.5-2b": 210.0}, "qwen3.5-2b", 63.0, True),
    ("uncalibrated model falls back to the absolute floor",
     {}, "unknown-model", 2.4, True),
    ("uncalibrated and healthy is not flagged",
     {}, "unknown-model", 200.0, False),
]


def main():
    br = load()
    failures = []
    print("degraded-mode detector: %d cases x %d phase shapes"
          % (len(CASES), len(SHAPES)))
    print("absolute floor %.0f tok/s, relative floor %.0f%% of own median\n"
          % (br.ABSOLUTE_TPS_FLOOR, br.RELATIVE_FLOOR_FRAC * 100))
    for label, calib, model, tps, must_catch in CASES:
        for shape_name, shape in SHAPES.items():
            br.CALIBRATION = dict(calib)
            caught = bool(br.band_breaches(shape(recs(model, tps))))
            ok = caught == must_catch
            if not ok:
                failures.append((label, shape_name, caught, must_catch))
            print("  [%s] %-52s %-12s %s"
                  % ("PASS" if ok else "FAIL", label[:52], shape_name,
                     "caught" if caught else "passed"))

    # A detector that flags everything would pass every must_catch case above.
    br.CALIBRATION = {"a": 200.0, "b": 40.0}
    healthy = br.band_breaches(recs("a", 200.0) + recs("b", 40.0))
    if healthy:
        failures.append(("healthy mixed-speed pool flagged", "solo", True, False))
    print("\n  [%s] healthy mixed-speed pool raises nothing"
          % ("PASS" if not healthy else "FAIL"))

    if failures:
        print("\nFAILED %d:" % len(failures))
        for f in failures:
            print("  %s (%s): caught=%s expected=%s" % f)
        return 1
    print("\nDEGRADED DETECTOR OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
