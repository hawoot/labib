"""Turn a Document into plain text (pluggable per Document.kind/mime).

Phase 0 handles: pasted text, .txt/.md files, and PDF (via PyMuPDF).
Adding a new format later = add a branch here; the rest of the crunch is identical.
"""
from __future__ import annotations

from . import models
from .storage import get_storage


class ParseError(Exception):
    pass


def parse_document(doc: "models.Document") -> str:
    """Return the full extracted text for a document."""
    # Inline content (pasted text or a URL's fetched text) lives in source_ref.
    if doc.kind == "text":
        return doc.source_ref or ""

    if doc.kind == "file":
        data = get_storage().load(doc.storage_key)
        mime = (doc.mime or "").lower()
        name = (doc.title or "").lower()
        if mime == "application/pdf" or name.endswith(".pdf"):
            return _parse_pdf(data)
        # default: treat as UTF-8 text (.txt, .md, etc.)
        try:
            return data.decode("utf-8", errors="replace")
        except Exception as e:  # pragma: no cover
            raise ParseError(f"Could not decode {doc.title}: {e}")

    raise ParseError(f"Unsupported document kind: {doc.kind}")


def _parse_pdf(data: bytes) -> str:
    try:
        import fitz  # PyMuPDF
    except ImportError as e:  # pragma: no cover
        raise ParseError("PyMuPDF not installed") from e
    parts: list[str] = []
    with fitz.open(stream=data, filetype="pdf") as pdf:
        for page in pdf:
            parts.append(page.get_text())
    return "\n".join(parts)
