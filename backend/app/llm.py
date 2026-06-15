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
