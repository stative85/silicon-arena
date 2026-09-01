"""The spine: propose -> attack -> repair -> verify, repeat while it helps.

    Draft -> Critique -> Revision -> Verification
               ^_____________________|

Rules that make this an optimizer rather than a conversation:

1. Only the verifier decides. Agents never vote on quality.
2. The critic attacks REAL failure output, not the draft's vibe.
3. The best-scoring candidate carries forward, so a bad revision cannot
   drag the run downhill.
4. Stop on success, on budget, or after two cycles with no improvement.
5. Every cycle records its exact delta. If a run cannot show where it
   improved, it did not improve.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Callable, List, Optional

from .llm import LLM, extract_code
from .mission import Mission
from .verifier import CodeVerifier, VerificationResult

StopReason = str

PROPOSER_SYSTEM = (
    "You are a senior Python engineer. Write a complete, working module that "
    "satisfies the contract exactly. Output ONE fenced python code block and "
    "nothing else. No explanation, no usage examples, no tests."
)

CRITIC_SYSTEM = (
    "You are a ruthless code reviewer. You are shown a candidate module and the "
    "ACTUAL output of running its test suite. Identify the specific defects that "
    "caused those failures. Be concrete: name the function, the wrong behaviour, "
    "and the fix. Maximum 6 bullet points. Never praise. Never restate the code. "
    "If the tests reveal a missing edge case, say which input triggers it."
)

REPAIRER_SYSTEM = (
    "You are a senior Python engineer repairing your own module. You are given "
    "the current code, the real test failures, and a reviewer's defect list. "
    "Rewrite the COMPLETE module so those failures pass, without breaking what "
    "already works. Output ONE fenced python code block and nothing else."
)


@dataclass
class CycleRecord:
    index: int
    score_before: float
    score_after: float
    passed_before: int
    passed_after: int
    total: int
    critique: str
    accepted: bool
    seconds: float

    @property
    def delta(self) -> float:
        return self.score_after - self.score_before

    def line(self) -> str:
        arrow = "+" if self.delta > 0 else ("=" if self.delta == 0 else "-")
        flag = "kept" if self.accepted else "rejected"
        return (f"cycle {self.index}: {self.passed_before}/{self.total} -> "
                f"{self.passed_after}/{self.total} "
                f"({arrow}{abs(self.delta):.3f}) [{flag}] {self.seconds:.1f}s")


@dataclass
class MissionReport:
    mission_id: str
    artifact: str
    initial: VerificationResult
    final: VerificationResult
    cycles: List[CycleRecord] = field(default_factory=list)
    stop_reason: StopReason = ""
    seconds: float = 0.0

    @property
    def improved(self) -> bool:
        return self.final.score > self.initial.score

    def summary(self) -> str:
        lines = [
            f"mission     : {self.mission_id}",
            f"draft       : {self.initial.summary()}  (score {self.initial.score:.3f})",
            f"final       : {self.final.summary()}  (score {self.final.score:.3f})",
            f"improvement : {self.final.score - self.initial.score:+.3f}",
            f"cycles      : {len(self.cycles)}",
            f"stopped     : {self.stop_reason}",
            f"elapsed     : {self.seconds:.1f}s",
        ]
        if self.cycles:
            lines.append("")
            lines.extend("  " + c.line() for c in self.cycles)
        return "\n".join(lines)


def run_mission(mission: Mission, llm: LLM,
                verifier: Optional[CodeVerifier] = None,
                on_event: Optional[Callable[[str], None]] = None,
                stall_limit: int = 2) -> MissionReport:
    emit = on_event or (lambda _msg: None)
    started = time.time()

    if verifier is None:
        verifier = CodeVerifier(mission.tests_source, timeout=mission.timeout)

    # Preflight: prove the instrument works before spending tokens on it.
    verifier.self_check()

    emit(f"[propose] {mission.id}")
    draft = extract_code(llm.complete(PROPOSER_SYSTEM, _propose_prompt(mission)))
    result = verifier.verify(draft)
    initial = result
    emit(f"[verify ] draft {result.summary()} (score {result.score:.3f})")

    best_code, best_result = draft, result
    records: List[CycleRecord] = []
    stalls = 0
    stop_reason = "budget exhausted"

    if best_result.perfect:
        stop_reason = "verified on first draft"
        return _finish(mission, best_code, initial, best_result, records,
                       stop_reason, started)

    for index in range(1, mission.max_cycles + 1):
        cycle_started = time.time()
        score_before = best_result.score
        passed_before = best_result.passed

        emit(f"[attack ] cycle {index}")
        critique = llm.complete(
            CRITIC_SYSTEM, _critic_prompt(mission, best_code, best_result)
        ).strip()

        emit(f"[repair ] cycle {index}")
        revision = extract_code(llm.complete(
            REPAIRER_SYSTEM, _repair_prompt(mission, best_code, best_result, critique)
        ))
        candidate = verifier.verify(revision)

        accepted = candidate.score > best_result.score
        if accepted:
            best_code, best_result = revision, candidate
            stalls = 0
        else:
            # Keep the better candidate. A revision that regresses is
            # discarded, not carried, so the run cannot walk downhill.
            stalls += 1

        record = CycleRecord(
            index=index,
            score_before=score_before,
            score_after=candidate.score,
            passed_before=passed_before,
            passed_after=candidate.passed,
            total=candidate.total or best_result.total,
            critique=critique,
            accepted=accepted,
            seconds=time.time() - cycle_started,
        )
        records.append(record)
        emit("[result ] " + record.line())

        if best_result.perfect:
            stop_reason = f"verified after {index} cycle(s)"
            break
        if stalls >= stall_limit:
            stop_reason = f"stalled - {stall_limit} cycles with no improvement"
            break
    else:
        stop_reason = f"budget exhausted after {mission.max_cycles} cycle(s)"

    return _finish(mission, best_code, initial, best_result, records,
                   stop_reason, started)


def _finish(mission, code, initial, final, records, stop_reason, started):
    return MissionReport(
        mission_id=mission.id,
        artifact=code,
        initial=initial,
        final=final,
        cycles=records,
        stop_reason=stop_reason,
        seconds=time.time() - started,
    )


# --- prompts ---------------------------------------------------------------

def _propose_prompt(mission: Mission) -> str:
    return (
        f"OBJECTIVE\n{mission.objective}\n\n"
        f"CONTRACT (your module must expose exactly this)\n{mission.contract}\n\n"
        "Write the module now."
    )


def _critic_prompt(mission: Mission, code: str, result: VerificationResult) -> str:
    return (
        f"OBJECTIVE\n{mission.objective}\n\n"
        f"CONTRACT\n{mission.contract}\n\n"
        f"CANDIDATE MODULE\n```python\n{code}\n```\n\n"
        f"ACTUAL TEST RESULTS — {result.summary()} passing\n"
        f"{result.critique_material()}\n\n"
        "List the specific defects causing these failures."
    )


def _repair_prompt(mission: Mission, code: str, result: VerificationResult,
                   critique: str) -> str:
    return (
        f"OBJECTIVE\n{mission.objective}\n\n"
        f"CONTRACT\n{mission.contract}\n\n"
        f"CURRENT MODULE\n```python\n{code}\n```\n\n"
        f"ACTUAL TEST FAILURES\n{result.critique_material()}\n\n"
        f"REVIEWER'S DEFECT LIST\n{critique}\n\n"
        "Output the complete repaired module."
    )
