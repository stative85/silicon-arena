"""A mission is one real objective plus its source of truth."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from typing import Optional


@dataclass
class Mission:
    id: str
    objective: str                 # what the user actually wants, in prose
    contract: str                  # the API the solution must expose
    tests_source: str              # ground truth -- executed, not judged
    max_cycles: int = 4
    timeout: float = 30.0
    artifact_name: str = "solution.py"

    @staticmethod
    def load(path: str) -> "Mission":
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)

        tests = data.get("tests_source")
        if not tests:
            tests_file = data.get("tests_file")
            if not tests_file:
                raise ValueError(
                    f"{path}: mission needs 'tests_source' or 'tests_file' — "
                    "a mission without a source of truth cannot be verified, "
                    "and an unverified loop is just a chatbot with extra steps."
                )
            tests_path = os.path.join(os.path.dirname(os.path.abspath(path)), tests_file)
            with open(tests_path, "r", encoding="utf-8") as fh:
                tests = fh.read()

        for required in ("id", "objective", "contract"):
            if not data.get(required):
                raise ValueError(f"{path}: mission is missing '{required}'")

        return Mission(
            id=data["id"],
            objective=data["objective"],
            contract=data["contract"],
            tests_source=tests,
            max_cycles=int(data.get("max_cycles", 4)),
            timeout=float(data.get("timeout", 30.0)),
            artifact_name=data.get("artifact_name", "solution.py"),
        )
