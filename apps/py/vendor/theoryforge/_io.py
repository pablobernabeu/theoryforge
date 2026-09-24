"""The single writer every file-emitting function in the package goes through.

``Path.write_text`` opens in text mode with ``newline=None``, so on Windows each
``\\n`` is translated to ``\\r\\n``. API_SPEC.md section 3 pins every generated
artefact to LF, and the R twin normalises explicitly, so a text-mode write here
would make the two engines emit different bytes for the same theory. Writing
encoded bytes bypasses the platform's newline translation entirely.
"""
from __future__ import annotations

from pathlib import Path


def write_lf(path, text: str) -> None:
    """Write ``text`` to ``path`` as UTF-8 with LF line endings only."""
    Path(path).write_bytes(text.replace("\r\n", "\n").encode("utf-8"))
