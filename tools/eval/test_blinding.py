#!/usr/bin/env python3
"""Prove the blinding actually blinds, on synthetic transcripts.

    python tools/eval/test_blinding.py

If an excerpt still names a model or an agent, the judges are not blind and
every quality number downstream is worthless. This runs the real scrub()
against transcripts built to contain every leak shape seen in real logs.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_blind_set import scrub

CASES = [
    # (text, mapping, model tokens, must_not_contain, must_contain)
    ("Stablelm 2 Zephyr #1: values are not utility.",
     {"Stablelm 2 Zephyr #1": "SPEAKER_A"}, {"stablelm-2-zephyr-1.6b"},
     ["Stablelm", "Zephyr", "#1"], ["SPEAKER_A"]),

    ("I disagree with Gpt 5 Distill #2 about alignment.",
     {"Gpt 5 Distill #2": "SPEAKER_B"}, {"gpt-5-distill-llama3.2-3b"},
     ["Gpt 5 Distill", "Distill"], ["SPEAKER_B"]),

    # bare name without the #n suffix, which models produce constantly
    ("Gemma 3 1B makes a fair point.",
     {"Gemma 3 1B": "SPEAKER_C"}, {"gemma-3-1b-it-fast-guff"},
     ["Gemma"], ["SPEAKER_C"]),

    # raw model id leaking into content
    ("According to mistralai/mistral-7b-instruct-v0.3 this is settled.",
     {}, {"mistralai/mistral-7b-instruct-v0.3", "mistral", "instruct"},
     ["mistral", "mistralai"], ["[model]"]),

    # bare parameter size is a mode tell: 1.6b implies the fitting roster
    ("A 1.6B model cannot reason about this.", {}, set(),
     ["1.6B"], ["[size]"]),

    ("Running a 7 B checkpoint changes nothing.", {}, set(),
     ["7 B"], ["[size]"]),

    # case-insensitivity
    ("stablelm 2 zephyr #1 already said that.",
     {"Stablelm 2 Zephyr #1": "SPEAKER_A"}, {"stablelm-2-zephyr-1.6b"},
     ["stablelm", "zephyr"], ["SPEAKER_A"]),
]

def main():
    bad = 0
    for i, (text, mapping, tokens, must_not, must) in enumerate(CASES, 1):
        out = scrub(text, mapping, tokens)
        low = out.lower()
        problems = [t for t in must_not if t.lower() in low]
        missing = [t for t in must if t not in out]
        if problems or missing:
            bad += 1
            print("   FAIL case %d" % i)
            print("        in : %s" % text)
            print("        out: %s" % out)
            if problems:
                print("        leaked: %s" % problems)
            if missing:
                print("        missing: %s" % missing)
        else:
            print("   ok   case %d  -> %s" % (i, out))
    print("\n--- %d cases, %d failure(s) ---" % (len(CASES), bad))
    if bad:
        print("BLINDING BROKEN")
        return 1
    print("BLINDING OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
