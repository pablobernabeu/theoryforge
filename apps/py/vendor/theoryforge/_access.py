"""How every consumer reads a theory's values (API_SPEC.md section 3, "Reading a theory").

``validate()`` reports a malformed theory. Every other function reads it
leniently, and these accessors fix what lenient means, so that the two engines
read the same malformed value the same way. R's ``utils.R`` mirrors each of them
(``.tf_list``, ``.tf_get``, ``.tf_text``, ``.tf_enum``, ``.tf_str_list``).
"""
from __future__ import annotations

from ._text import trim

MATURITY = frozenset({"draft", "building", "developing", "testing"})
FORM = frozenset({"variance", "network", "typology", "process"})
RELATION = frozenset({"increases", "decreases", "moderates", "mediates", "causes", "associates"})
PRED_TYPE = frozenset({"point", "interval", "directional", "existence"})
FORMAL_MODEL_TYPE = frozenset({"ode", "abm", "network", "sem", "none"})
EVIDENCE_DIRECTION = frozenset({"corroborates", "refutes", "mixed"})


def ne_str(v) -> bool:
    """Whether ``v`` is a string with at least one character left after trimming.

    Trimming removes the whitespace set of ``_text.WS`` (Unicode's White_Space),
    so a lone no-break space is empty in both languages.
    """
    return isinstance(v, str) and trim(v) != ""


def items(d, key: str) -> list:
    """The collection under ``key``: the list when it is a sequence, otherwise empty.

    A scalar or a mapping where a collection belongs reads as an empty
    collection, and so does ``d`` itself when it is not a mapping. An entry of
    the list that is not a mapping is kept, and ``field`` reads it as an entry
    with no fields.
    """
    v = d.get(key) if isinstance(d, dict) else None
    return v if isinstance(v, list) else []


def field(item, key: str):
    """The value of ``key`` in ``item``, or None when ``item`` is not a mapping."""
    return item.get(key) if isinstance(item, dict) else None


def text(v) -> str:
    """A value read as text.

    A string is returned as it is, and a nonempty sequence whose first element
    is a string gives that element, as R's reader did for a one-element
    sequence. Anything else reads as the empty string: null, a number and a
    boolean included, because R holds ``1.0`` as the number 1 and ``Yes`` as
    TRUE, and no reading of either can give back what the file says.
    """
    if isinstance(v, str):
        return v
    if isinstance(v, list) and v and isinstance(v[0], str):
        return v[0]
    return ""


def enum(v, allowed) -> str | None:
    """``v`` when it is one of the ``allowed`` strings, otherwise None (absent).

    Used for ``type``, ``relation``, ``maturity`` and ``formal_model.type``
    wherever they are read, so a value outside the enum, a sequence included,
    takes part in no verdict and prints as nothing.
    """
    return v if isinstance(v, str) and v in allowed else None


def str_list(v) -> list[str]:
    """A string array: its nonempty string entries, in order.

    A nonempty scalar string is a one-element array (``derives_from: p1``), a
    reading both languages keep as a convenience for hand-written YAML. R's
    reader once collapsed a one-element sequence to a string, so the two forms
    could not be told apart there, but it now returns every sequence as a list.
    An entry that is not a nonempty string, such as the null in ``[p1, ~]`` or
    the inner list in ``[[adults]]``, is ignored, and any other value reads as
    empty.
    """
    if isinstance(v, list):
        return [x for x in v if ne_str(x)]
    if ne_str(v):
        return [v]
    return []
