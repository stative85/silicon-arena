"""Subprocess test runner. Executed in a temp dir, never imported by the arena.

Usage:  python _runner.py <solution.py> <tests.py>

Emits ONE line of JSON on stdout:
  {"ok": bool, "error": str|null, "results": [{"name","passed","error"}]}

Why a custom runner instead of pytest: no third-party dependency (pytest is
not installed on this box), and -- more importantly -- structured per-test
results. The critic agent needs real failure objects to attack. Scraping
pytest's console output would throw away exactly the detail that makes the
critique concrete instead of vague.
"""

import ast
import importlib.util
import json
import linecache
import os
import sys
import traceback


def _explain_assertion(exc, tests_path):
    """Recover the OBSERVED value from a bare `assert a == b` failure.

    Plain asserts raise `AssertionError` with no message, so a critic agent
    sees "AssertionError" and the source line but never what the function
    ACTUALLY returned -- which is precisely the information needed to
    diagnose the defect. pytest solves this with AST rewriting; this is the
    cheap version: find the failing frame, parse the line, and re-evaluate
    the left-hand side of the comparison in that frame.

    Re-evaluation can in principle have side effects, so it is best-effort
    and clearly labelled. Returns "" when it cannot help.
    """
    tb = exc.__traceback__
    frame = None
    lineno = 0
    while tb is not None:
        if os.path.abspath(tb.tb_frame.f_code.co_filename) == os.path.abspath(tests_path):
            frame, lineno = tb.tb_frame, tb.tb_lineno
        tb = tb.tb_next
    if frame is None:
        return ""

    src = linecache.getline(tests_path, lineno).strip()
    # Assertions often span lines; walk the module AST for the real node.
    try:
        tree = ast.parse(open(tests_path, "r", encoding="utf-8").read())
    except SyntaxError:
        return ""
    node = None
    for candidate in ast.walk(tree):
        if isinstance(candidate, ast.Assert) and candidate.lineno == lineno:
            node = candidate
            break
    if node is None or not isinstance(node.test, ast.Compare):
        return ""

    parts = []
    try:
        left = eval(compile(ast.Expression(node.test.left), "<assert>", "eval"),
                    frame.f_globals, frame.f_locals)
        parts.append(f"  actual   : {left!r}")
    except BaseException as inner:                       # noqa: BLE001
        parts.append(f"  actual   : <could not re-evaluate: {inner!r}>")
    if node.test.comparators:
        try:
            right = eval(
                compile(ast.Expression(node.test.comparators[0]), "<assert>", "eval"),
                frame.f_globals, frame.f_locals)
            parts.append(f"  expected : {right!r}")
        except BaseException:                            # noqa: BLE001
            pass
    if not parts:
        return ""
    return "\nOBSERVED VALUES for `{}`:\n{}\n".format(src, "\n".join(parts))


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def main() -> int:
    if len(sys.argv) != 3:
        print(json.dumps({"ok": False, "error": "bad args", "results": []}))
        return 2

    solution_path, tests_path = sys.argv[1], sys.argv[2]
    sys.path.insert(0, os.path.dirname(os.path.abspath(solution_path)))

    # Import the candidate. A syntax error or import-time crash here is a
    # total failure -- score 0 -- and the traceback is the critique material.
    try:
        _load(solution_path, "solution")
    except BaseException:
        print(json.dumps({
            "ok": False,
            "error": "solution failed to import:\n" + traceback.format_exc(limit=6),
            "results": [],
        }))
        return 0

    try:
        tests = _load(tests_path, "arena_tests")
    except BaseException:
        print(json.dumps({
            "ok": False,
            "error": "test file failed to import:\n" + traceback.format_exc(limit=6),
            "results": [],
        }))
        return 0

    names = sorted(n for n in dir(tests) if n.startswith("test_")
                   and callable(getattr(tests, n)))
    results = []
    for name in names:
        try:
            getattr(tests, name)()
            results.append({"name": name, "passed": True, "error": None})
        except BaseException as exc:
            # BaseException, not Exception: a candidate that raises
            # SystemExit or KeyboardInterrupt must count as failing, not
            # silently kill the runner and look like zero tests.
            detail = traceback.format_exc(limit=6)
            if isinstance(exc, AssertionError) and not str(exc):
                detail += _explain_assertion(exc, tests_path)
            results.append({"name": name, "passed": False, "error": detail})

    print(json.dumps({"ok": True, "error": None, "results": results}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
