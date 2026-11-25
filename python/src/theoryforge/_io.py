"""The single writer every file-emitting function in the package goes through.

``Path.write_text`` opens in text mode with ``newline=None``, so on Windows each
``\\n`` is translated to ``\\r\\n``. API_SPEC.md section 3 pins every generated
artefact to LF, and the R twin normalises explicitly, so a text-mode write here
would make the two engines emit different bytes for the same theory. Writing
encoded bytes bypasses the platform's newline translation entirely.
"""
from __future__ import annotations

import os
from pathlib import Path


def expand_home(path) -> str:
    """``path`` with a leading ``~`` expanded as R's ``path.expand()`` expands it.

    A ``~`` alone, or followed by a separator (``/``, or ``\\`` on Windows),
    stands for the home directory on every platform. A ``~user`` names that
    user's home directory on POSIX systems, where an unknown user is left as
    written, as R leaves it, and ``Path.expanduser`` would raise. R on Windows
    never expands ``~user``, so it is left as written there.
    """
    p = os.fspath(path)
    if not p.startswith("~"):
        return p
    if os.name != "nt" or len(p) == 1 or p[1] in "/\\":
        return os.path.expanduser(p)
    return p


def write_lf(path, text: str) -> None:
    """Write ``text`` to ``path`` as UTF-8 with LF line endings only.

    A leading ``~`` in ``path`` is expanded as R expands it (``expand_home``).
    """
    Path(expand_home(path)).write_bytes(text.replace("\r\n", "\n").encode("utf-8"))
