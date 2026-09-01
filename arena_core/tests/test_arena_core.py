"""Tests for the arena spine. stdlib unittest -- no pytest dependency.

Run:  python -m unittest discover -s arena_core/tests -t . -v

The load-bearing test in this file is test_ugly_working_beats_polished_broken.
If that ever fails, the verifier has become an opinion and the whole loop is
theatre. The control-flow tests matter almost as much: they are the only place
the stopping rules get exercised, because a live model is too non-deterministic
to prove "stops after two stalls" against.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))

from arena_core.cycle import run_mission
from arena_core.llm import LLMError, ScriptedLLM, extract_code
from arena_core.mission import Mission
from arena_core.verifier import CodeVerifier

TESTS = '''
from solution import add

def test_add_positive():
    assert add(2, 3) == 5

def test_add_negative():
    assert add(-1, -1) == -2

def test_add_zero():
    assert add(0, 7) == 7

def test_add_mixed():
    assert add(-4, 9) == 5
'''

WORKING_UGLY = "def add(a,b):\n  return a+b\n"

POLISHED_BROKEN = '''
"""Arithmetic utilities.

This module provides a carefully designed, fully documented addition
routine with comprehensive type annotations and a clean public API.
"""

from typing import Union

Number = Union[int, float]


def add(a: Number, b: Number) -> Number:
    """Return the sum of two numbers.

    Args:
        a: The first addend.
        b: The second addend.

    Returns:
        The arithmetic sum of `a` and `b`.
    """
    return a - b        # subtly, catastrophically wrong
'''


def fence(code: str) -> str:
    return f"Here you go:\n\n```python\n{code}\n```\n"


def mission(max_cycles: int = 4) -> Mission:
    return Mission(
        id="add", objective="Implement add(a, b).",
        contract="def add(a, b) -> number", tests_source=TESTS,
        max_cycles=max_cycles, timeout=20.0,
    )


class TestVerifierIsGroundTruth(unittest.TestCase):

    def test_ugly_working_beats_polished_broken(self):
        """THE load-bearing test. Execution decides, not presentation."""
        v = CodeVerifier(TESTS)
        ugly = v.verify(WORKING_UGLY)
        polished = v.verify(POLISHED_BROKEN)

        self.assertEqual(ugly.score, 1.0, "working code must score perfect")
        self.assertLess(polished.score, ugly.score,
                        "a polished but broken answer must LOSE to an ugly "
                        "working one -- otherwise this is AI voting")
        self.assertEqual(polished.passed, 0)
        self.assertTrue(polished.failures, "failures must be reported")

    def test_syntax_error_scores_zero_and_reports_why(self):
        v = CodeVerifier(TESTS)
        r = v.verify("def add(a, b)\n    return a + b\n")   # missing colon
        self.assertEqual(r.score, 0.0)
        self.assertIsNotNone(r.fatal)
        self.assertIn("import", r.fatal.lower())

    def test_partial_credit_is_proportional(self):
        v = CodeVerifier(TESTS)
        # Correct except for negatives -> exactly one of four tests fails.
        r = v.verify("def add(a, b):\n    return abs(a) + abs(b)\n")
        self.assertEqual(r.total, 4)
        self.assertEqual(r.passed, 2)
        self.assertAlmostEqual(r.score, 0.5)

    def test_infinite_loop_scores_zero_instead_of_hanging(self):
        v = CodeVerifier(TESTS, timeout=5.0)
        r = v.verify("def add(a, b):\n    while True:\n        pass\n")
        self.assertEqual(r.score, 0.0)
        self.assertIn("timeout", (r.fatal or "").lower())

    def test_self_check_rejects_a_broken_test_file(self):
        """A dead instrument must fail loudly, not score everything 0."""
        v = CodeVerifier("this is not valid python at all !!!\n")
        with self.assertRaises(ValueError):
            v.self_check()

    def test_self_check_rejects_test_file_with_no_tests(self):
        v = CodeVerifier("x = 1\n")
        with self.assertRaises(ValueError):
            v.self_check()

    def test_critique_material_contains_real_traceback(self):
        v = CodeVerifier(TESTS)
        material = v.verify(POLISHED_BROKEN).critique_material()
        self.assertIn("test_add_positive", material)
        self.assertIn("AssertionError", material)


class TestLoopControlFlow(unittest.TestCase):

    def test_stops_immediately_when_draft_is_already_correct(self):
        llm = ScriptedLLM([fence(WORKING_UGLY)])
        report = run_mission(mission(), llm)
        self.assertEqual(report.final.score, 1.0)
        self.assertEqual(len(report.cycles), 0, "must not burn cycles on a win")
        self.assertIn("first draft", report.stop_reason)

    def test_repairs_a_broken_draft_end_to_end(self):
        llm = ScriptedLLM([
            fence(POLISHED_BROKEN),          # draft: 0/4
            "- add() subtracts instead of adding",   # critique
            fence(WORKING_UGLY),             # repair: 4/4
        ])
        report = run_mission(mission(), llm)
        self.assertEqual(report.initial.score, 0.0)
        self.assertEqual(report.final.score, 1.0)
        self.assertTrue(report.improved)
        self.assertEqual(len(report.cycles), 1)
        self.assertTrue(report.cycles[0].accepted)
        self.assertAlmostEqual(report.cycles[0].delta, 1.0)

    def test_stops_after_two_cycles_without_improvement(self):
        broken = fence("def add(a, b):\n    return a - b\n")
        llm = ScriptedLLM([
            broken,                 # draft 0/4
            "critique 1", broken,   # cycle 1: still 0/4  -> stall 1
            "critique 2", broken,   # cycle 2: still 0/4  -> stall 2 -> stop
            "critique 3", broken,   # must never be reached
        ])
        report = run_mission(mission(max_cycles=4), llm)
        self.assertEqual(len(report.cycles), 2)
        self.assertIn("stalled", report.stop_reason)
        self.assertEqual(llm.remaining, 2, "loop kept going after the stall")

    def test_regression_is_rejected_and_best_carries_forward(self):
        half = "def add(a, b):\n    return abs(a) + abs(b)\n"   # 2/4
        worse = "def add(a, b):\n    return 0\n"                # 1/4
        good = WORKING_UGLY                                     # 4/4
        llm = ScriptedLLM([
            fence(half),                # draft 2/4
            "critique", fence(worse),   # cycle 1 regresses -> rejected
            "critique", fence(good),    # cycle 2 fixes it from the KEPT draft
        ])
        report = run_mission(mission(), llm)
        self.assertEqual(report.initial.passed, 2)
        self.assertFalse(report.cycles[0].accepted, "regression must be rejected")
        self.assertEqual(report.final.score, 1.0)
        self.assertEqual(report.artifact.strip(), good.strip())

    def test_budget_is_respected(self):
        broken = fence("def add(a, b):\n    return a - b\n")
        # Alternate tiny improvements so stalls never hit 2, forcing the run
        # to end on budget rather than on stall.
        llm = ScriptedLLM([
            fence("def add(a, b):\n    return 0\n"),        # 1/4
            "c", fence("def add(a, b):\n    return abs(a)+abs(b)\n"),  # 2/4
            "c", fence("def add(a, b):\n    return a if b==0 else abs(a)+abs(b)\n"),
            "c", broken,
            "c", broken,
        ])
        report = run_mission(mission(max_cycles=2), llm)
        self.assertLessEqual(len(report.cycles), 2)
        self.assertNotEqual(report.final.score, 1.0)
        self.assertTrue("budget" in report.stop_reason
                        or "stalled" in report.stop_reason)

    def test_every_cycle_reports_an_exact_delta(self):
        llm = ScriptedLLM([
            fence(POLISHED_BROKEN), "critique", fence(WORKING_UGLY),
        ])
        report = run_mission(mission(), llm)
        for record in report.cycles:
            self.assertRegex(record.line(),
                             r"cycle \d+: \d+/\d+ -> \d+/\d+ \([+=-][\d.]+\)")


class TestCodeExtraction(unittest.TestCase):

    def test_prefers_longest_block_not_first(self):
        reply = ("Example usage:\n```python\nadd(1, 2)\n```\n"
                 "Implementation:\n```python\ndef add(a, b):\n    return a + b\n```")
        self.assertIn("def add", extract_code(reply))

    def test_falls_back_to_bare_text(self):
        self.assertEqual(extract_code("def add(a, b): return a + b"),
                         "def add(a, b): return a + b")

    def test_scripted_llm_exhaustion_is_loud(self):
        llm = ScriptedLLM([])
        with self.assertRaises(LLMError):
            llm.complete("s", "u")


if __name__ == "__main__":
    unittest.main(verbosity=2)
