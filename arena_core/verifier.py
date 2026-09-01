"""Ground truth for code missions.

The whole point: score comes from EXECUTION, never from a model's opinion.
A polished, well-documented, beautifully-argued answer that fails the tests
scores below an ugly one-liner that passes them. That property is enforced by
a test in tests/test_arena_core.py and is the reason this file exists.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from typing import List, Optional

_RUNNER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_runner.py")


@dataclass
class Failure:
    name: str
    error: str

    def brief(self, max_chars: int = 600) -> str:
        err = self.error.strip()
        if len(err) > max_chars:
            err = err[:max_chars] + "\n    ... (truncated)"
        return f"{self.name}:\n{err}"


@dataclass
class VerificationResult:
    score: float                       # 0.0 - 1.0, fraction of tests passing
    passed: int
    total: int
    failures: List[Failure] = field(default_factory=list)
    fatal: Optional[str] = None        # import/syntax error, or harness failure

    @property
    def perfect(self) -> bool:
        return self.total > 0 and self.passed == self.total

    def summary(self) -> str:
        if self.fatal:
            first = self.fatal.strip().splitlines()
            tail = first[-1] if first else "unknown error"
            return f"0/{self.total or '?'} — {tail}"
        return f"{self.passed}/{self.total}"

    def critique_material(self, max_failures: int = 4) -> str:
        """Exactly what the critic agent gets to attack. Real output only."""
        if self.fatal:
            return "The candidate did not even run:\n\n" + self.fatal.strip()
        if not self.failures:
            return "All tests passed."
        chunks = [f.brief() for f in self.failures[:max_failures]]
        extra = len(self.failures) - max_failures
        if extra > 0:
            chunks.append(f"... and {extra} more failing test(s).")
        return "\n\n".join(chunks)


class CodeVerifier:
    """Runs candidate code against a fixed test file in an isolated temp dir."""

    def __init__(self, tests_source: str, timeout: float = 30.0,
                 python: Optional[str] = None) -> None:
        self.tests_source = tests_source
        self.timeout = timeout
        self.python = python or sys.executable

    def verify(self, code: str) -> VerificationResult:
        expected_total = self.expected_test_count()
        with tempfile.TemporaryDirectory(prefix="arena_verify_") as tmp:
            solution_path = os.path.join(tmp, "solution.py")
            tests_path = os.path.join(tmp, "arena_tests.py")
            with open(solution_path, "w", encoding="utf-8") as fh:
                fh.write(code or "")
            with open(tests_path, "w", encoding="utf-8") as fh:
                fh.write(self.tests_source)

            try:
                proc = subprocess.run(
                    [self.python, _RUNNER, solution_path, tests_path],
                    capture_output=True, text=True, timeout=self.timeout,
                    cwd=tmp,
                )
            except subprocess.TimeoutExpired:
                # An infinite loop is a real defect and must score 0, not hang
                # the arena or crash it into an unscored state.
                return VerificationResult(
                    score=0.0, passed=0, total=expected_total,
                    fatal=f"Execution exceeded the {self.timeout:.0f}s timeout — "
                          "likely an infinite loop or a blocking call.",
                )

            stdout = (proc.stdout or "").strip()
            if not stdout:
                return VerificationResult(
                    score=0.0, passed=0, total=expected_total,
                    fatal="Test runner produced no output.\n"
                          + (proc.stderr or "")[-800:],
                )
            try:
                payload = json.loads(stdout.splitlines()[-1])
            except json.JSONDecodeError:
                return VerificationResult(
                    score=0.0, passed=0, total=expected_total,
                    fatal="Test runner output was not JSON:\n" + stdout[-800:],
                )

        if not payload.get("ok"):
            return VerificationResult(
                score=0.0, passed=0, total=expected_total,
                fatal=payload.get("error") or "unknown runner failure",
            )

        results = payload.get("results", [])
        failures = [Failure(r["name"], r.get("error") or "")
                    for r in results if not r.get("passed")]
        passed = sum(1 for r in results if r.get("passed"))
        total = len(results)
        if total == 0:
            return VerificationResult(
                score=0.0, passed=0, total=0,
                fatal="No test functions were collected — the mission's test "
                      "file defines no test_* functions.",
            )
        return VerificationResult(
            score=passed / total, passed=passed, total=total, failures=failures,
        )

    def expected_test_count(self) -> int:
        """Best-effort count for reporting when the candidate won't even import."""
        return sum(1 for line in self.tests_source.splitlines()
                   if line.startswith("def test_"))

    # A stand-in solution that satisfies ANY import the test file asks for, so
    # `from solution import whatever` succeeds during preflight. Every call
    # then fails loudly, so a correct test file scores this 0/N -- which is
    # the point: it proves the tests RUN and that they can fail.
    _PROBE = (
        "def __getattr__(name):\n"
        "    def _stub(*args, **kwargs):\n"
        "        raise AssertionError('arena preflight stub')\n"
        "    return _stub\n"
    )

    def self_check(self) -> None:
        """Preflight: prove the mission's own tests are runnable and can fail
        before we spend model tokens on it.

        A mission whose test file is broken would score every candidate 0, and
        the loop would grind through its whole budget 'improving' against a
        dead instrument. Fail loudly here instead.
        """
        if self.expected_test_count() == 0:
            raise ValueError("mission test file defines no test_* functions")

        probe = self.verify(self._PROBE)
        if probe.fatal:
            raise ValueError(
                "mission test file is not runnable - every candidate would "
                f"score 0 regardless of quality:\n{probe.fatal}"
            )
        if probe.total == 0:
            raise ValueError("mission test file collected no test functions")
        if probe.passed == probe.total:
            raise ValueError(
                "mission test file passes even against a stub that implements "
                "nothing - these tests assert nothing and would rate every "
                "candidate perfect."
            )
