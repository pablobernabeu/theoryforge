"""Access to the example theories and corpora installed with the package.

The R package offers the same files through ``tf_example_path()`` and
``tf_example_names()``.
"""
from __future__ import annotations

from importlib.resources import as_file, files
from pathlib import Path


def example_names() -> list[str]:
    """The names of the example theory and corpus files, sorted.

    Only the ``.yaml`` files the package ships are listed.
    """
    # Only .yaml entries count, matching R's list.files(pattern = "\\.yaml$").
    # Listing the directory wholesale would let anything else that lands beside
    # the examples, such as a __pycache__ directory left by a local build, show
    # up here and not in R.
    entries = (files("theoryforge") / "fixtures").iterdir()
    return sorted(p.name for p in entries if p.name.endswith(".yaml"))


def example_path(name: str) -> Path:
    """Filesystem path of a packaged example, such as ``panic-network.theory.yaml``.

    The path exists for a package installed on disk, as pip installs it.
    Raises ``FileNotFoundError`` naming the available files when ``name`` is not
    one of them.
    """
    # Only a listed name is looked up, so that no other file of the installed
    # package can be reached through this function.
    resource = files("theoryforge") / "fixtures" / str(name)
    if name not in example_names() or not resource.is_file():
        raise FileNotFoundError(f"no packaged example named {name!r}; available: {example_names()}")
    # An installed wheel is a directory on disk, so as_file() yields the file
    # itself and the path stays valid. From a zipped installation it would
    # yield a temporary copy that is deleted when the block exits, so the path
    # is guaranteed only for a package installed on disk.
    with as_file(resource) as path:
        return Path(path)
