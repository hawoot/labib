"""The swappable AI brain.

The whole app talks to ONE interface, `LLMProvider.complete(...)`. We ship two
implementations and pick between them with the `LLM_PROVIDER` env var:

  * openai_compatible -> OpenRouter, DeepSeek, OpenAI, Together, Groq, Ollama...
                         (all share the same "/chat/completions" API)
  * anthropic         -> Claude

Swapping providers is purely a `.env` change; no code changes needed.
"""
from __future__ import annotations

from abc import ABC, abstractmethod

from .config import Settings, get_settings


class LLMProvider(ABC):
    @abstractmethod
    def complete(self, messages: list[dict], **kwargs) -> str:
        """Take chat messages [{role, content}, ...], return the reply text."""


class OpenAICompatibleProvider(LLMProvider):
    """Works with any OpenAI-compatible endpoint (most providers)."""

    def __init__(self, s: Settings):
        from openai import OpenAI

        self.client = OpenAI(base_url=s.llm_base_url, api_key=s.llm_api_key or "none")
        self.model = s.llm_model

    def complete(self, messages: list[dict], **kwargs) -> str:
        resp = self.client.chat.completions.create(
            model=self.model, messages=messages, **kwargs
        )
        return resp.choices[0].message.content or ""


class AnthropicProvider(LLMProvider):
    """Claude. Anthropic separates the system prompt from the conversation."""

    def __init__(self, s: Settings):
        from anthropic import Anthropic

        self.client = Anthropic(api_key=s.llm_api_key)
        self.model = s.llm_model

    def complete(self, messages: list[dict], **kwargs) -> str:
        system = "\n".join(m["content"] for m in messages if m["role"] == "system")
        convo = [m for m in messages if m["role"] != "system"]
        resp = self.client.messages.create(
            model=self.model,
            system=system or None,
            messages=convo,
            max_tokens=kwargs.pop("max_tokens", 1024),
            **kwargs,
        )
        return "".join(
            b.text for b in resp.content if getattr(b, "type", None) == "text"
        )


def get_llm(settings: Settings | None = None) -> LLMProvider:
    s = settings or get_settings()
    if s.llm_provider == "anthropic":
        return AnthropicProvider(s)
    return OpenAICompatibleProvider(s)


def _extract_json(text: str) -> str:
    """Pull a JSON object/array out of a model reply (strips ``` fences, prose)."""
    t = text.strip()
    if t.startswith("```"):
        t = t.split("```", 2)[1] if t.count("```") >= 2 else t.strip("`")
        if t.lstrip().startswith("json"):
            t = t.lstrip()[4:]
    start = min(
        (i for i in (t.find("{"), t.find("[")) if i != -1), default=-1
    )
    end = max(t.rfind("}"), t.rfind("]"))
    return t[start : end + 1] if start != -1 and end != -1 else t


def complete_json(
    messages: list[dict], settings: Settings | None = None, max_tokens: int = 4096
):
    """Call the LLM and parse its reply as JSON, with one corrective retry."""
    import json

    llm = get_llm(settings)
    raw = llm.complete(messages, max_tokens=max_tokens)
    try:
        return json.loads(_extract_json(raw))
    except json.JSONDecodeError:
        retry = messages + [
            {"role": "assistant", "content": raw},
            {"role": "user", "content": "That was not valid JSON. Reply with ONLY the JSON, no prose, no code fences."},
        ]
        raw = llm.complete(retry, max_tokens=max_tokens)
        return json.loads(_extract_json(raw))
