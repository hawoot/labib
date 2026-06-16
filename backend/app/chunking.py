"""Split extracted text into ordered chunks.

Simple, dependency-free: pack paragraphs into ~chunk_chars-sized pieces on
paragraph boundaries. Good enough for the crunch; smarter splitting can slot in
later behind the same function signature.
"""
from __future__ import annotations


def chunk_text(text: str, chunk_chars: int = 1500) -> list[str]:
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    chunks: list[str] = []
    buf = ""
    for p in paragraphs:
        if buf and len(buf) + len(p) + 2 > chunk_chars:
            chunks.append(buf)
            buf = p
        else:
            buf = f"{buf}\n\n{p}" if buf else p
    if buf:
        chunks.append(buf)
    return chunks
