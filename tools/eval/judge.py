#!/usr/bin/env python3
"""Score the blinded excerpts with a local model judge.

    python tools/eval/judge.py --model <id> --tag J1

Writes tools/eval/runs/_judge_<TAG>.json. Run it once per judge; the judges are
never combined into a single number here, because agreement between two models
is not ground truth -- it is a measurement in its own right, and compare.py
reports it as one.

The judge sees only SPEAKER_A..E and scrubbed text. It is not told that roster
modes exist, how many conditions there are, or what is being compared.
"""
import argparse
import json
import os
import re
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RUNS = os.path.join(ROOT, "tools", "eval", "runs")
BASE = os.environ.get("SILICON_ARENA_LM_URL", "http://127.0.0.1:1234/v1")

DIMENSIONS = ["coherence", "relevance", "distinctiveness", "argument_quality",
              "responsiveness", "entertainment"]

RUBRIC = """You are grading an excerpt from a multi-speaker debate transcript.

Score each dimension from 1 to 5, where 1 is very poor and 5 is excellent.

coherence       - is each turn internally sensible and grammatical?
relevance       - does it stay on the topic under discussion?
distinctiveness - do the speakers sound like different people, or interchangeable?
argument_quality- are claims supported, specific, and non-trivial?
responsiveness  - does a turn engage with what the previous speaker actually said?
entertainment   - would a viewer keep watching this?

Reply with ONLY a JSON object and nothing else, in exactly this form:
{"coherence":3,"relevance":3,"distinctiveness":3,"argument_quality":3,"responsiveness":3,"entertainment":3}
"""


def post(model, messages, max_tokens=200, temperature=0.0):
    body = json.dumps({"model": model, "messages": messages,
                       "max_tokens": max_tokens, "temperature": temperature,
                       "stream": False}).encode()
    req = urllib.request.Request(BASE + "/chat/completions", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        d = json.loads(r.read().decode("utf-8", "ignore"))
    m = d["choices"][0]["message"]
    return (m.get("content") or "").strip()


def ask(model, excerpt):
    body = "\n\n".join("%s: %s" % (l["speaker"], l["text"]) for l in excerpt["lines"])
    user = RUBRIC + "\n\nTRANSCRIPT EXCERPT:\n\n" + body
    try:
        txt = post(model, [{"role": "user", "content": user}])
    except Exception as e:
        return None, "request failed: %s" % e
    m = re.search(r"\{[^{}]*\}", txt, re.S)
    if not m:
        return None, "no JSON in reply: %r" % txt[:120]
    try:
        obj = json.loads(m.group(0))
    except Exception:
        return None, "unparseable JSON: %r" % m.group(0)[:120]
    out = {}
    for d in DIMENSIONS:
        v = obj.get(d)
        try:
            v = float(v)
        except (TypeError, ValueError):
            return None, "missing/!numeric %s" % d
        if not (1.0 <= v <= 5.0):
            return None, "%s out of range: %s" % (d, v)
        out[d] = v
    return out, ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()

    blind = json.load(open(os.path.join(RUNS, "_blind_set.json"), encoding="utf-8"))
    if a.limit:
        blind = blind[:a.limit]

    scores, errors = {}, []
    t0 = time.time()
    for i, ex in enumerate(blind, 1):
        s, err = ask(a.model, ex)
        if s is None:
            # One retry; a judge that still cannot answer is recorded as a
            # refusal rather than silently dropped or defaulted to a score.
            s, err = ask(a.model, ex)
        if s is None:
            errors.append({"id": ex["id"], "why": err})
        else:
            scores[ex["id"]] = s
        if i % 10 == 0 or i == len(blind):
            print("  %s: %d/%d scored, %d unusable, %.0fs"
                  % (a.tag, len(scores), len(blind), len(errors), time.time() - t0))

    out = {"tag": a.tag, "model": a.model, "scored": len(scores),
           "unusable": errors, "scores": scores}
    p = os.path.join(RUNS, "_judge_%s.json" % a.tag)
    json.dump(out, open(p, "w", encoding="utf-8"), indent=1)
    print("wrote %s" % os.path.relpath(p, ROOT))


if __name__ == "__main__":
    main()
