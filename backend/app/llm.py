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
        """Take chat messages [{role, content}, ...], return the reply text.

        A message's `content` is normally a string, but may be a list of parts
        to send an image alongside text:
            {"type": "text", "text": "..."}
            {"type": "image", "data": "<base64>", "media_type": "image/jpeg"}
        Each provider translates those parts into its own wire format, so
        callers stay provider-agnostic.
        """


def _to_openai_content(content):
    """Normalize our content parts to OpenAI's multimodal format."""
    if isinstance(content, str):
        return content
    out = []
    for p in content:
        if p.get("type") == "image":
            mt = p.get("media_type", "image/jpeg")
            out.append({
                "type": "image_url",
                "image_url": {"url": f"data:{mt};base64,{p['data']}"},
            })
        else:
            out.append({"type": "text", "text": p.get("text", "")})
    return out


def _to_anthropic_content(content):
    """Normalize our content parts to Anthropic's block format."""
    if isinstance(content, str):
        return content
    out = []
    for p in content:
        if p.get("type") == "image":
            out.append({
                "type": "image",
                "source": {
                    "type": "base64",
                    "media_type": p.get("media_type", "image/jpeg"),
                    "data": p["data"],
                },
            })
        else:
            out.append({"type": "text", "text": p.get("text", "")})
    return out


class OpenAICompatibleProvider(LLMProvider):
    """Works with any OpenAI-compatible endpoint (most providers)."""

    def __init__(self, s: Settings):
        from openai import OpenAI

        self.client = OpenAI(base_url=s.llm_base_url, api_key=s.llm_api_key or "none")
        self.model = s.llm_model

    def complete(self, messages: list[dict], **kwargs) -> str:
        msgs = [{**m, "content": _to_openai_content(m["content"])} for m in messages]
        resp = self.client.chat.completions.create(
            model=self.model, messages=msgs, **kwargs
        )
        return resp.choices[0].message.content or ""


class AnthropicProvider(LLMProvider):
    """Claude. Anthropic separates the system prompt from the conversation."""

    def __init__(self, s: Settings):
        from anthropic import Anthropic

        self.client = Anthropic(api_key=s.llm_api_key)
        self.model = s.llm_model

    def complete(self, messages: list[dict], **kwargs) -> str:
        system = "\n".join(
            m["content"]
            for m in messages
            if m["role"] == "system" and isinstance(m["content"], str)
        )
        convo = [
            {**m, "content": _to_anthropic_content(m["content"])}
            for m in messages
            if m["role"] != "system"
        ]
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
    messages: list[dict], settings: Settings | None = None, max_tokens: int = 8000
):
    """Call the LLM and parse its reply as JSON, robust to reasoning models.

    - asks for JSON mode (response_format) where the provider supports it;
    - retries a couple of times if the reply is empty or unparseable;
    - raises a descriptive error (not a cryptic JSONDecodeError) on final failure.
    """
    import json

    llm = get_llm(settings)
    state = {"force_json": True}

    def _call(msgs: list[dict]) -> str:
        try:
            kw = {"max_tokens": max_tokens}
            if state["force_json"]:
                kw["response_format"] = {"type": "json_object"}
            return llm.complete(msgs, **kw)
        except Exception:
            # Provider likely rejects response_format -> drop it and retry once.
            if state["force_json"]:
                state["force_json"] = False
                return llm.complete(msgs, max_tokens=max_tokens)
            raise

    raw = _call(messages)
    for attempt in range(3):
        text = _extract_json(raw)
        if text.strip():
            try:
                return json.loads(text)
            except json.JSONDecodeError:
                pass
        if attempt == 2:
            break
        raw = _call(
            messages
            + [
                {"role": "assistant", "content": raw or ""},
                {
                    "role": "user",
                    "content": "Your previous reply was empty or not valid JSON. "
                    "Reply with ONLY the JSON, no prose, no code fences.",
                },
            ]
        )
    raise ValueError(
        f"LLM did not return parseable JSON. Last reply (truncated): {(raw or '')[:300]!r}"
    )
