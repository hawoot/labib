"""Swappable file storage (mirrors the LLM provider pattern).

Uploaded documents (PDFs, etc.) never go in the database — only a pointer
(`storage_key`) does. In dev we store on local disk; later this same interface
gets an S3/R2 implementation with no caller changes.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from functools import lru_cache
from pathlib import Path

from .config import get_settings


class StorageBackend(ABC):
    @abstractmethod
    def save(self, key: str, data: bytes) -> None: ...

    @abstractmethod
    def load(self, key: str) -> bytes: ...

    @abstractmethod
    def delete(self, key: str) -> None: ...


class LocalStorage(StorageBackend):
    def __init__(self, base_dir: str):
        self.base = Path(base_dir)

    def _path(self, key: str) -> Path:
        return self.base / key

    def save(self, key: str, data: bytes) -> None:
        p = self._path(key)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)

    def load(self, key: str) -> bytes:
        return self._path(key).read_bytes()

    def delete(self, key: str) -> None:
        self._path(key).unlink(missing_ok=True)


@lru_cache
def get_storage() -> StorageBackend:
    return LocalStorage(get_settings().storage_dir)
