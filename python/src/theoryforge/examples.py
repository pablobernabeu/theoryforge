"""Access to the example theories shipped inside the package.

The R twin reaches the same files through ``system.file("fixtures", ...)``, so a
reader who installed only one half still has something to run. The files are
copies of ``fixtures/*.yaml`` at the repository root, written by
``scripts/gen_golden.py`` and gated in CI, so they cannot drift.
"""
from __future__ import annotations

from importlib.resources import as_file, files
from pathlib import Path


def example_names() -> list[str]:
    """The names of the example theory and corpus files, sorted."""
    return sorted(p.name for p in (files("theoryforge") / "fixtures").iterdir())


def example_path(name: str) -> Path:
    """Filesystem path of a packaged example, e.g. ``panic-network.theory.yaml``.

    Raises ``FileNotFoundError`` naming the available files when ``name`` is not
    one of them.
    """
    resource = files("theoryforge") / "fixtures" / name
    if not resource.is_file():
        raise FileNotFoundError(f"no packaged example named {name!r}; available: {example_names()}")
    # A wheel is a directory on disk once installed, so this resolves to a real
    # path; as_file() keeps the call correct for a zipped install too.
    with as_file(resource) as path:
        return Path(path)
