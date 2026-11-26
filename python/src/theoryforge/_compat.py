"""The keyword ``T``, which named the theory argument up to version 0.7.0."""
from __future__ import annotations

import functools
import warnings


def theory_keyword(fn):
    """Let ``fn(T=...)`` stand for ``fn(theory=...)``, with a warning.

    The theory argument is named ``theory``, as in R. A call that names it
    ``T`` still works until the next minor release.
    """
    @functools.wraps(fn)
    def wrapper(*args, **kwargs):
        if "T" in kwargs:
            if args or "theory" in kwargs:
                raise TypeError(f"{fn.__name__}() got multiple values for argument 'theory'")
            warnings.warn(f"{fn.__name__}(T=...) is deprecated; name the argument theory, "
                          "or pass the theory by position", FutureWarning, stacklevel=2)
            kwargs["theory"] = kwargs.pop("T")
        return fn(*args, **kwargs)
    return wrapper
