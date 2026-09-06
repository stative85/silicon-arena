#!/usr/bin/env python3
"""Adversarial harness for candidate health detectors. Offline, no LM Studio.

    python tools/health_harness.py [--data docs/results/bridge_timing.json]

WHY THIS EXISTS. The bridge-native collection killed the flat
`TTFT > 1500 ms` tooth: falcon's healthy LARGE contended median is 1,780 ms,
so the tooth sits below the median of a healthy cell and would "recover"
healthy models to death.

The replacement must be chosen by attacking candidates, not by picking a number
that looks reasonable. This harness scores every candidate on two corpora:

  HEALTHY REPLAY     all measured receipts, UNCENSORED -- including the
                     >1500 ms calls the collection filtered out. A detector
                     that flags normal large-prompt falcon behaviour is
                     disqualified regardless of how well it catches pathology.

  INJECTED FAILURE   the failure SHAPES actually observed, not just uniform
                     multiplication: persistent degradation, single spike,
                     gradual decay, wedge, and recovery-after-reload.

The scoring asymmetry is deliberate. A false positive costs a reload -- roughly
2-9 seconds of unavailability plus pool churn -- and a detector that thrashes is
worse than no detector. A missed degradation costs latency until the next
breach. False positives are therefore weighted as the more serious error.

NOTHING IS FROZEN HERE. This ranks candidates and reports where each breaks.
Choosing the policy is a separate, deliberate act.
"""
import argparse
import json
import os
import statistics
import sys

# Approximate prompt sizes for the three collection buckets, used only when a
# receipt predates prompt-size telemetry. Exact per-model token counts are
# preferred whenever the receipt carries them.
BUCKET_TOKENS = {"SMALL": 10, "MEDIUM": 295, "LARGE": 3455}


def load(path):
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    tags = d.get("tags", {})
    rows = []
    for r in d.get("records", []):
        if r.get("status") != "OK":
            continue
        ttft = r.get("ttft_ms", -1)
        if ttft is None or ttft < 0:
            continue
        bucket = tags.get(r.get("request_id"), {}).get("bucket")
        tok = r.get("prompt_tokens", -1)
        exact = tok is not None and tok >= 0
        if not exact:
            tok = BUCKET_TOKENS.get(bucket, 0)
        rows.append({
            "model": r["model_id"],
            "bucket": bucket,
            "load": int(r.get("max_active_during", 1) or 1),
            "ttft": int(ttft),
            "tokens": int(tok),
            "tokens_exact": exact,
            "order": int(r.get("order", 0)),
        })
    rows.sort(key=lambda x: x["order"])
    return rows


def short(m):
    return m.split("/")[-1].split("-")[0]


def pct(vals, q):
    v = sorted(vals)
    if not v:
        return 0.0
    return float(v[min(int(round(q * (len(v) - 1))), len(v) - 1)])


# ----------------------------------------------------------------- expectation

def fit(rows):
    """Per-model expectation of TTFT as a function of prompt size and load.

    Fitted on UNCONTENDED cells only, then a separate contention factor is
    measured. Keeping them separate means a detector can be asked what it
    would do without load information, which matters because the scheduler is
    not required to tell the health path about concurrency.
    """
    models = sorted({r["model"] for r in rows})
    out = {}
    for m in models:
        solo = [r for r in rows if r["model"] == m and r["load"] == 1]
        by_size = {}
        for r in solo:
            by_size.setdefault(r["tokens"], []).append(r["ttft"])
        sizes = sorted(by_size)
        if len(sizes) < 2:
            continue
        lo, hi = sizes[0], sizes[-1]
        y_lo = statistics.median(by_size[lo])
        y_hi = statistics.median(by_size[hi])
        slope = (y_hi - y_lo) / float(hi - lo) if hi != lo else 0.0
        icept = y_lo - slope * lo
        # Contention factor, measured per model across sizes.
        facs = []
        for sz in sizes:
            two = [r["ttft"] for r in rows
                   if r["model"] == m and r["load"] >= 2 and r["tokens"] == sz]
            if two and by_size[sz]:
                facs.append(statistics.median(two) / statistics.median(by_size[sz]))
        # Cluster near-identical sizes before making knots. The SMALL bucket
        # splits into token counts a few apart (h2o 59 and 61) whose medians
        # differ by sampling noise, producing a segment with a local slope of
        # ~7 ms/token against a real 0.15. That is noise encoded as policy, and
        # it makes the expectation jagged exactly where prompts are cheapest.
        # Sizes within 10% of each other are the same workload; pool them.
        clusters = []
        for sz in sizes:
            if clusters and sz <= clusters[-1][-1] * 1.10:
                clusters[-1].append(sz)
            else:
                clusters.append([sz])
        knots = []
        for c in clusters:
            pooled = []
            for sz in c:
                pooled += by_size[sz]
            knots.append((int(round(sum(c) / float(len(c)))),
                          statistics.median(pooled)))
        out[m] = {
            "knots": knots,
            "intercept": icept,
            "per_token": slope,
            "contention": statistics.median(facs) if facs else 1.0,
            "sizes": sizes,
        }
    return out


## Piecewise-linear expectation through every measured size, rather than a
## straight line through the endpoints. Falcon is superlinear mid-range: the
## two-point line understates its MEDIUM cell, giving healthy calls there a
## residual median of 1.30 and a max of 4.18. That is fit error masquerading as
## unhealthiness, and it would spend the detector's whole error budget on a
## deficiency of the model rather than on real pathology. Three sizes are
## measured; interpolating between them costs nothing and removes the bias.
def expected_pw(model, tokens, load, f, use_load=True):
    p = f.get(model)
    if p is None:
        return None
    knots = p.get("knots") or []
    if len(knots) < 2:
        return expected(model, tokens, load, f, use_load)
    e = None
    if tokens <= knots[0][0]:
        e = knots[0][1]
    elif tokens >= knots[-1][0]:
        e = knots[-1][1]
    else:
        for i in range(len(knots) - 1):
            x0, y0 = knots[i]
            x1, y1 = knots[i + 1]
            if x0 <= tokens <= x1:
                t = 0.0 if x1 == x0 else (tokens - x0) / float(x1 - x0)
                e = y0 + t * (y1 - y0)
                break
    if e is None:
        e = knots[-1][1]
    if use_load and load >= 2:
        e *= p["contention"]
    return max(e, 1.0)


def expected(model, tokens, load, f, use_load=True):
    p = f.get(model)
    if p is None:
        return None
    e = p["intercept"] + p["per_token"] * tokens
    if use_load and load >= 2:
        e *= p["contention"]
    return max(e, 1.0)


# ------------------------------------------------------------------ detectors

class Detector:
    """A candidate rule. `feed` returns one of NORMAL / SUSPECT / DEGRADED."""

    name = "base"

    def reset(self):
        pass

    def feed(self, row, f):
        return "NORMAL"


class FlatGlobal(Detector):
    """The current tooth. Included as the baseline to beat."""

    def __init__(self, ms=1500):
        self.ms = ms
        self.name = "D1 flat global %dms" % ms

    def feed(self, row, f):
        return "DEGRADED" if row["ttft"] > self.ms else "NORMAL"


class FlatPerModel(Detector):
    """Per-model absolute threshold, ignoring prompt size."""

    def __init__(self, thresholds):
        self.t = thresholds
        self.name = "D2 flat per-model"

    def feed(self, row, f):
        lim = self.t.get(row["model"], 1e9)
        return "DEGRADED" if row["ttft"] > lim else "NORMAL"


class Residual(Detector):
    """Size-conditioned residual. One breach is enough to condemn."""

    def __init__(self, k, use_load=True, pw=False):
        self.k = k
        self.use_load = use_load
        self.exp = expected_pw if pw else expected
        self.name = "D3 residual k=%.1f%s%s" % (
            k, "" if use_load else " no-load", " PW" if pw else "")

    def feed(self, row, f):
        e = self.exp(row["model"], row["tokens"], row["load"], f, self.use_load)
        if e is None:
            return "NORMAL"
        return "DEGRADED" if row["ttft"] / e > self.k else "NORMAL"


class ResidualStreak(Detector):
    """Size-conditioned residual requiring N consecutive breaches.

    The serial-correlation result is what makes this viable: healthy jitter is
    essentially independent (15 of 17 cells showed no clustering), so a run of
    N consecutive breaches is unlikely by chance -- while the pathologies
    actually observed were persistent states lasting many calls.
    """

    def __init__(self, k_suspect, k_hard, n, use_load=True, pw=False):
        self.ks, self.kh, self.n = k_suspect, k_hard, n
        self.use_load = use_load
        self.exp = expected_pw if pw else expected
        self.streak = {}
        self.name = "D%d residual streak ks=%.1f kh=%.1f n=%d%s" % (
            5 if pw else 4, k_suspect, k_hard, n, " PW" if pw else "")

    def reset(self):
        self.streak = {}

    def feed(self, row, f):
        e = self.exp(row["model"], row["tokens"], row["load"], f, self.use_load)
        if e is None:
            return "NORMAL"
        ratio = row["ttft"] / e
        m = row["model"]
        if ratio > self.kh:
            self.streak[m] = 0
            return "DEGRADED"       # a single catastrophic breach still counts
        if ratio > self.ks:
            self.streak[m] = self.streak.get(m, 0) + 1
            if self.streak[m] >= self.n:
                self.streak[m] = 0
                return "DEGRADED"
            return "SUSPECT"
        self.streak[m] = 0
        return "NORMAL"


# -------------------------------------------------------------------- corpora

def inject(rows, shape, mult, model=None):
    """Build a failure sequence from real healthy rows.

    The shapes are the ones actually observed, not uniform scaling: a spilled
    model stayed slow for many consecutive calls, a wedge produced no content
    at all, and a reload restored normal service immediately.
    """
    base = [r for r in rows if model is None or r["model"] == model]
    if not base:
        return []
    seq = [dict(r) for r in base[:40]]
    n = len(seq)
    if shape == "persistent":
        for i in range(n // 2, n):
            seq[i]["ttft"] = int(seq[i]["ttft"] * mult)
    elif shape == "spike":
        seq[n // 2]["ttft"] = int(seq[n // 2]["ttft"] * mult)
    elif shape == "gradual":
        steps = [1.0, 1.2, 1.5, 2.0, 3.0]
        for i in range(n // 2, n):
            k = steps[min(i - n // 2, len(steps) - 1)]
            seq[i]["ttft"] = int(seq[i]["ttft"] * k)
    elif shape == "wedge":
        for i in range(n // 2, n):
            seq[i]["ttft"] = 120000
    elif shape == "recovery":
        for i in range(n // 2, n // 2 + 5):
            seq[i]["ttft"] = int(seq[i]["ttft"] * mult)
    return seq


def score_healthy(det, rows, f):
    det.reset()
    fp = 0
    for r in rows:
        if det.feed(r, f) == "DEGRADED":
            fp += 1
    return fp


def score_injected(det, seq, f, onset):
    """Did it fire, and how many calls after onset?"""
    det.reset()
    fired_at = None
    pre = 0
    for i, r in enumerate(seq):
        v = det.feed(r, f)
        if v == "DEGRADED":
            if i < onset:
                pre += 1
            elif fired_at is None:
                fired_at = i - onset
    return fired_at, pre


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="docs/results/bridge_timing.json")
    ap.add_argument("--holdout", action="store_true",
                    help="fit the expectation on the first half by request "
                         "order and evaluate on the second half, so the "
                         "expectation is never validated on data it saw")
    a = ap.parse_args()
    rows = load(a.data)
    if not rows:
        print("no usable rows in %s" % a.data)
        return 1

    exact = sum(1 for r in rows if r["tokens_exact"])
    print("=== health detector adversarial harness ===")
    print("healthy replay corpus: %d receipts, UNCENSORED" % len(rows))
    print("prompt sizes: %d exact from usage, %d approximated from bucket\n"
          % (exact, len(rows) - exact))

    eval_rows = rows
    if a.holdout:
        half = len(rows) // 2
        fit_rows, eval_rows = rows[:half], rows[half:]
        print("HELD-OUT MODE: expectation fitted on %d rows, evaluated on %d"
              % (len(fit_rows), len(eval_rows)))
        print("The thresholds under test were chosen on a DIFFERENT dataset;")
        print("this checks they survive data neither they nor the expectation")
        print("model has seen.\n")
        f = fit(fit_rows)
    else:
        f = fit(rows)
    print("[EXPECTATION MODEL]  ttft = intercept + tokens*cost, x contention")
    for m in sorted(f):
        p = f[m]
        print("  %-9s intercept %6.0f ms  %8.5f ms/tok  contention %.2fx"
              % (short(m), p["intercept"], p["per_token"], p["contention"]))

    # How far do healthy calls stray from their own expectation? This is the
    # dispersion any threshold has to clear.
    print("\n[HEALTHY RESIDUAL DISPERSION]  observed / expected")
    print("  %-9s %-8s %-5s %5s %6s %6s %6s %6s"
          % ("MODEL", "BUCKET", "load", "n", "median", "p95", "p99", "max"))
    all_ratios = []
    for m in sorted(f):
        for b in ["SMALL", "MEDIUM", "LARGE"]:
            for lv in (1, 2):
                rr = [r["ttft"] / expected_pw(m, r["tokens"], r["load"], f)
                      for r in eval_rows
                      if r["model"] == m and r["bucket"] == b
                      and r["load"] == lv]
                if not rr:
                    continue
                all_ratios += rr
                print("  %-9s %-8s %-5d %5d %6.2f %6.2f %6.2f %6.2f"
                      % (short(m), b, lv, len(rr),
                         statistics.median(rr), pct(rr, 0.95), pct(rr, 0.99),
                         max(rr)))
    print("\n  overall healthy residual: median %.2f  p99 %.2f  max %.2f"
          % (statistics.median(all_ratios), pct(all_ratios, 0.99),
             max(all_ratios)))

    per_model_p999 = {}
    for m in sorted(f):
        v = [r["ttft"] for r in eval_rows if r["model"] == m]
        per_model_p999[m] = pct(v, 0.999) * 1.5

    cands = [
        FlatGlobal(1500),
        FlatPerModel(per_model_p999),
        Residual(2.0),
        Residual(2.5),
        Residual(3.0),
        Residual(2.5, use_load=False),
        ResidualStreak(1.8, 5.0, 3),
        ResidualStreak(2.0, 5.0, 3),
        ResidualStreak(2.0, 5.0, 2),
        ResidualStreak(2.5, 6.0, 3),
        ResidualStreak(1.8, 5.0, 3, pw=True),
        ResidualStreak(1.5, 4.0, 3, pw=True),
        ResidualStreak(1.5, 10.0, 3, pw=True),
        ResidualStreak(1.5, 20.0, 3, pw=True),
        ResidualStreak(1.8, 20.0, 3, pw=True),
        ResidualStreak(1.5, 20.0, 4, pw=True),
        ResidualStreak(1.8, 20.0, 4, pw=True),
        ResidualStreak(2.0, 20.0, 4, pw=True),
    ]

    print("\n[HEALTHY REPLAY]  false positives on real measured traffic")
    print("  a detector that fires here would reload a healthy model")
    print("  n = %d" % len(eval_rows))
    print("  %-38s %6s %8s" % ("DETECTOR", "FP", "rate"))
    healthy_fp = {}
    for d in cands:
        fp = score_healthy(d, eval_rows, f)
        healthy_fp[d.name] = fp
        print("  %-38s %6d %7.2f%%"
              % (d.name, fp, 100.0 * fp / max(len(eval_rows), 1)))

    print("\n[INJECTED FAILURE]  detection latency in calls after onset")
    print("  '-' = never fired.  'pre' = fired BEFORE onset (false alarm)")
    models = sorted({r["model"] for r in rows})
    shapes = [("persistent", 4.0), ("persistent", 2.0), ("spike", 5.0),
              ("gradual", 0), ("wedge", 0), ("recovery", 4.0)]
    hdr = "  %-38s" % "DETECTOR"
    for sh, mu in shapes:
        hdr += " %-12s" % (sh[:9] + (("x%g" % mu) if mu else ""))
    print(hdr)
    results = {}
    for d in cands:
        line = "  %-38s" % d.name
        row_res = {}
        for sh, mu in shapes:
            lat = []
            pres = 0
            for m in models:
                seq = inject(eval_rows, sh, mu if mu else 1.0, m)
                if not seq:
                    continue
                onset = len(seq) // 2
                fired, pre = score_injected(d, seq, f, onset)
                pres += pre
                if fired is not None:
                    lat.append(fired)
            if not lat:
                cell = "-"
            else:
                cell = "%.1f" % (sum(lat) / len(lat))
                if len(lat) < len(models):
                    cell += "(%d/%d)" % (len(lat), len(models))
            if pres:
                cell += "!pre%d" % pres
            row_res[sh + str(mu)] = cell
            line += " %-12s" % cell
        results[d.name] = row_res
        print(line)

    print("\n[READING]")
    print("  A detector is only usable if its healthy false-positive count is")
    print("  ~0. Detection latency matters only among survivors of that test.")
    survivors = [d for d in cands if healthy_fp[d.name] == 0]
    print("  zero-false-positive candidates: %d of %d"
          % (len(survivors), len(cands)))
    for d in survivors:
        print("    %s" % d.name)
    print("\n  Nothing is frozen by this run. Choosing the policy is a")
    print("  separate, deliberate act.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
