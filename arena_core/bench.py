"""The baseline question, answered with numbers.

    Does the arena beat asking one model once?

Runs N single-shot attempts (propose only -- exactly what you get from one
prompt) and N full arena runs (propose -> attack -> repair -> verify) against
the SAME mission and the SAME model, then compares verified scores.

    python -m arena_core.bench --mission arena_core/missions/word_wrap.json \
        --model <id> --trials 5

This exists because "it feels smarter" is not a result. If the arena does not
beat single-shot on this table, the arena is not worth its tokens and the
honest move is to say so.
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from arena_core.cycle import PROPOSER_SYSTEM, _propose_prompt, run_mission
from arena_core.llm import DEFAULT_BASE_URL, LLMError, LMStudioLLM, extract_code
from arena_core.mission import Mission
from arena_core.verifier import CodeVerifier


def single_shot(mission: Mission, llm: LMStudioLLM, verifier: CodeVerifier):
    """One prompt, one answer, verified. The thing we must beat."""
    code = extract_code(llm.complete(PROPOSER_SYSTEM, _propose_prompt(mission)))
    return verifier.verify(code)


def describe(name: str, scores, tokens_note: str = "") -> str:
    if not scores:
        return f"  {name:<14} (no data)"
    mean = statistics.mean(scores)
    best = max(scores)
    solved = sum(1 for s in scores if s >= 1.0)
    return (f"  {name:<14} mean {mean:.3f}   best {best:.3f}   "
            f"solved {solved}/{len(scores)}{tokens_note}")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mission", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--trials", type=int, default=5)
    ap.add_argument("--cycles", type=int, default=4)
    ap.add_argument("--temperature", type=float, default=0.4)
    ap.add_argument("--base-url", default=DEFAULT_BASE_URL)
    ap.add_argument("--out", default=None)
    args = ap.parse_args(argv)

    mission = Mission.load(args.mission)
    mission.max_cycles = args.cycles
    verifier = CodeVerifier(mission.tests_source, timeout=mission.timeout)
    verifier.self_check()

    llm = LMStudioLLM(model=args.model, base_url=args.base_url,
                      temperature=args.temperature)

    single_scores, arena_scores, arena_drafts = [], [], []
    single_time = arena_time = 0.0

    print(f"mission {mission.id} | model {args.model} | {args.trials} trials each\n")

    print("SINGLE-SHOT (one prompt, one answer)")
    for i in range(args.trials):
        t0 = time.time()
        try:
            r = single_shot(mission, llm, verifier)
        except LLMError as exc:
            print(f"  trial {i+1}: MODEL ERROR {exc}")
            continue
        single_time += time.time() - t0
        single_scores.append(r.score)
        print(f"  trial {i+1}: {r.summary()}  score {r.score:.3f}")

    print("\nARENA (propose -> attack -> repair -> verify)")
    for i in range(args.trials):
        t0 = time.time()
        try:
            rep = run_mission(mission, llm, verifier=verifier)
        except LLMError as exc:
            print(f"  trial {i+1}: MODEL ERROR {exc}")
            continue
        arena_time += time.time() - t0
        arena_scores.append(rep.final.score)
        arena_drafts.append(rep.initial.score)
        print(f"  trial {i+1}: {rep.initial.summary()} -> {rep.final.summary()}  "
              f"score {rep.final.score:.3f} ({rep.final.score - rep.initial.score:+.3f}, "
              f"{len(rep.cycles)} cycles, {rep.stop_reason})")

    print("\n" + "=" * 62)
    print("RESULT")
    print("=" * 62)
    print(describe("single-shot", single_scores, f"   {single_time:.0f}s total"))
    print(describe("arena", arena_scores, f"   {arena_time:.0f}s total"))

    verdict = "INCONCLUSIVE"
    if single_scores and arena_scores:
        mean_delta = statistics.mean(arena_scores) - statistics.mean(single_scores)
        per_single = single_time / len(single_scores)
        per_arena = arena_time / len(arena_scores)
        ratio = per_arena / max(per_single, 1e-9)

        print(f"\n  mean delta     = {mean_delta:+.3f} "
              f"(arena mean minus single-shot mean)")
        print(f"  cost           = one arena run buys ~{ratio:.0f} single-shot draws")

        # THE HONEST COMPARISON. Comparing arena-mean to single-mean flatters
        # the arena: nobody with a verifier takes ONE sample, they take the
        # best of N. Since we already verify every candidate, best-of-N is
        # free to compute and is the real baseline. An arena run that costs
        # 10x a sample must beat the best of ~10 samples, not the average of
        # one.
        best_single = max(single_scores)
        best_arena = max(arena_scores)
        print(f"\n  best-of-{len(single_scores)} single = {best_single:.3f}")
        print(f"  best-of-{len(arena_scores)} arena  = {best_arena:.3f}")

        if best_arena > best_single + 0.02:
            verdict = "ARENA WINS (beats best-of-N sampling)"
        elif best_arena < best_single - 0.02:
            verdict = (f"ARENA LOSES - best-of-N sampling scores "
                       f"{best_single:.3f} at ~1/{ratio:.0f} the cost")
        else:
            verdict = "NO MEASURABLE DIFFERENCE vs best-of-N sampling"

        if mean_delta > 0.05 and best_arena <= best_single:
            print("\n  NOTE: the arena raises the FLOOR (better mean) but not the")
            print("  CEILING. It makes bad draws less bad; it does not produce")
            print("  answers that sampling could not have found more cheaply.")

        # Isolates the repair loop from luck in the draft pool: the arena's
        # own drafts are single-shot samples too.
        if arena_drafts:
            lift = statistics.mean(arena_scores) - statistics.mean(arena_drafts)
            print(f"\n  repair-loop lift over its own drafts = {lift:+.3f}")
    print(f"\n  VERDICT: {verdict}")

    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump({
                "mission": mission.id, "model": args.model,
                "trials": args.trials, "verdict": verdict,
                "single_shot_scores": single_scores,
                "arena_scores": arena_scores,
                "arena_draft_scores": arena_drafts,
                "single_seconds": single_time, "arena_seconds": arena_time,
            }, fh, indent=2)
        print(f"  written -> {args.out}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
