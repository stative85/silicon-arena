"""Model access for the arena spine.

Two implementations behind one tiny interface:

  LMStudioLLM  -- talks to the local LM Studio OpenAI-compatible server.
  ScriptedLLM  -- returns canned replies in order, records every call.

ScriptedLLM is not a toy. It is the only way to test the recursive loop's
control flow (does it stop on success? does it stall out? does it keep the
best candidate when a revision regresses?) without a model in the way. A loop
whose stopping rules are only ever exercised against a live LLM is a loop
whose stopping rules are untested.
"""

from __future__ import annotations

import json
import re
import urllib.error
import urllib.request
from typing import List, Optional, Protocol

DEFAULT_BASE_URL = "http://127.0.0.1:1234/v1"


class LLMError(RuntimeError):
    pass


class LLM(Protocol):
    def complete(self, system: str, user: str) -> str: ...


class LMStudioLLM:
    """Local LM Studio client. stdlib only -- no requests dependency."""

    def __init__(self, model: str, base_url: str = DEFAULT_BASE_URL,
                 temperature: float = 0.4, timeout: float = 180.0,
                 max_tokens: int = 2048) -> None:
        self.model = model
        self.base_url = base_url.rstrip("/")
        self.temperature = temperature
        self.timeout = timeout
        self.max_tokens = max_tokens
        self.calls: List[dict] = []

    def complete(self, system: str, user: str) -> str:
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "temperature": self.temperature,
            "max_tokens": self.max_tokens,
            "stream": False,
        }
        req = urllib.request.Request(
            f"{self.base_url}/chat/completions",
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                body = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            # The server answered -- it just refused. The body says WHY
            # ("Failed to load model", context overflow, ...). Reporting only
            # the status code here sends you hunting for a network problem
            # that does not exist.
            detail = ""
            try:
                detail = json.loads(exc.read().decode("utf-8"))["error"]["message"]
            except Exception:                                    # noqa: BLE001
                pass
            raise LLMError(
                f"LM Studio rejected the request (HTTP {exc.code})"
                + (f": {detail}" if detail else "")
                + f" [model={self.model}]"
            ) from exc
        except urllib.error.URLError as exc:
            raise LLMError(f"LM Studio unreachable at {self.base_url}: {exc}") from exc
        except json.JSONDecodeError as exc:
            raise LLMError(f"LM Studio returned non-JSON: {exc}") from exc

        try:
            message = body["choices"][0]["message"]
        except (KeyError, IndexError) as exc:
            raise LLMError(f"Unexpected response shape: {body}") from exc

        # Reasoning models (Qwen3, DeepSeek R1) may put the answer in
        # reasoning_content when content comes back empty.
        text = message.get("content") or message.get("reasoning_content") or ""
        self.calls.append({"system": system, "user": user, "reply": text})
        return strip_think(text)


class ScriptedLLM:
    """Deterministic test double. Hands back `responses` in order."""

    def __init__(self, responses: List[str]) -> None:
        self._responses = list(responses)
        self.calls: List[dict] = []

    def complete(self, system: str, user: str) -> str:
        if not self._responses:
            raise LLMError(
                "ScriptedLLM exhausted: the loop asked for more completions than "
                "the test scripted. That is a real finding about the loop, not a "
                "test-harness bug -- check the cycle count."
            )
        reply = self._responses.pop(0)
        self.calls.append({"system": system, "user": user, "reply": reply})
        return reply

    @property
    def remaining(self) -> int:
        return len(self._responses)


_THINK_RE = re.compile(r"<think>.*?</think>", re.DOTALL | re.IGNORECASE)
_FENCE_RE = re.compile(r"```(?:python|py)?\s*\n(.*?)```", re.DOTALL)


def strip_think(text: str) -> str:
    return _THINK_RE.sub("", text).strip()


def extract_code(text: str) -> str:
    """Pull the code out of a model reply.

    Prefers the LONGEST fenced block: models often emit a short usage snippet
    alongside the real implementation, and taking the first block silently
    ships the example instead of the solution.
    """
    blocks = _FENCE_RE.findall(text or "")
    if blocks:
        return max(blocks, key=len).strip()
    return (text or "").strip()
