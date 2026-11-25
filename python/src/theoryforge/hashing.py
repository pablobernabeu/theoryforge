"""The content hash of a theory (API_SPEC.md section 34).

A theory is written in a canonical form, which R's ``hashing.R`` writes byte
for byte alike, and the SHA-256 digest of that form identifies the content. A
preregistration and a dossier give it, so that a reader can check that the
theory file in hand is the one they describe.
"""
from __future__ import annotations

import hashlib
import math
import numbers

from ._compat import theory_keyword
from ._num import number, plain
from ._resources import string_array_paths


def _decimal_up(s: str) -> str:
    """The decimal one unit in the last place above ``s``, written as ``%e`` writes it.

    ``5.960464477539062e-08`` gives ``5.960464477539063e-08``, and ``9.99e+02``
    gives ``1.00e+03``. ``s`` is positive.
    """
    mantissa, exp = s.split("e")
    digits = [int(c) for c in mantissa.replace(".", "")]
    e = int(exp)
    i = len(digits) - 1
    while i >= 0 and digits[i] == 9:
        digits[i] = 0
        i -= 1
    if i < 0:
        digits = [1] + digits[:-1]
        e += 1
    else:
        digits[i] += 1
    text = "".join(str(d) for d in digits)
    head = text[0] + ("." + text[1:] if len(text) > 1 else "")
    return f"{head}e{'-' if e < 0 else '+'}{abs(e):02d}"


def _number(x) -> str:
    """A number as ECMAScript's Number.prototype.toString writes it.

    The digits are the shortest that read back as the same double, as RFC 8785
    asks. An integer beyond 2^53 is first read as the double nearest it, as R
    holds it.
    """
    if isinstance(x, numbers.Integral) and abs(int(x)) < 2 ** 53:
        return str(int(x))
    # number() reads an integer too large for a double as an infinity, as R
    # holds it, where float() would raise OverflowError.
    y = number(x)
    x = math.nan if y is None else y
    if math.isnan(x):
        return "NaN"
    if math.isinf(x):
        return "Infinity" if x > 0 else "-Infinity"
    if x == 0:
        return "0"
    sign = "-" if x < 0 else ""
    x = abs(x)
    # For each count of digits the nearest decimal is tried and then the one a
    # unit in the last place above it, which only beside a power of two reads
    # back where the nearest does not (API_SPEC.md section 34).
    for p in range(1, 18):
        s = f"{x:.{p - 1}e}"
        if float(s) == x:
            break
        t = _decimal_up(s)
        if float(t) == x:
            s = t
            break
    mantissa, exp = s.split("e")
    digits = mantissa.replace(".", "").rstrip("0") or "0"
    k, n = len(digits), int(exp) + 1
    if k <= n <= 21:
        out = digits + "0" * (n - k)
    elif 0 < n <= 21:
        out = digits[:n] + "." + digits[n:]
    elif -6 < n <= 0:
        out = "0." + "0" * (-n) + digits
    else:
        e = n - 1
        out = digits[0] + ("." + digits[1:] if k > 1 else "") + ("e+" if e >= 0 else "e-") + str(abs(e))
    return sign + out


_ESCAPES = {'"': '\\"', "\\": "\\\\", "\b": "\\b", "\f": "\\f", "\n": "\\n", "\r": "\\r", "\t": "\\t"}


def _string(s: str) -> str:
    """A JSON string: quotation mark, backslash and control characters escaped, the rest as it is."""
    out = []
    for ch in s:
        if ch in _ESCAPES:
            out.append(_ESCAPES[ch])
        elif ord(ch) < 0x20:
            out.append(f"\\u{ord(ch):04x}")
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def _box(x, path: tuple[str, ...]):
    """``x`` with a single value at the end of ``path`` held as a one-element list.

    A value that is neither None nor a list or mapping is boxed. ``"[]"`` visits
    every entry of a list and every value of a mapping, as R's ``.tf_box_path()``
    does, and None is left alone wherever it stands.
    """
    if not path:
        return x if x is None or isinstance(x, (list, dict)) else [x]
    head, rest = path[0], path[1:]
    if head == "[]":
        if isinstance(x, list):
            return [None if item is None else _box(item, rest) for item in x]
        if isinstance(x, dict):
            return {k: None if v is None else _box(v, rest) for k, v in x.items()}
        return x
    if isinstance(x, dict) and x.get(head) is not None:
        return {**x, head: _box(x[head], rest)}
    return x


def box_string_arrays(data):
    """``data`` with a single value in each field the schema types as an array of strings boxed.

    The singleton rule (API_SPEC.md section 4) reads ``derives_from: p1`` as
    ``derives_from: [p1]``, and R's ``tf_write()`` writes it so. The canonical
    form writes the boxed value, so that the two spellings hash alike. ``data``
    itself is not changed.
    """
    for path in string_array_paths():
        data = _box(data, path)
    return data


def _key(k: str) -> bytes:
    """A key's sort order: its UTF-16 code units, as RFC 8785 sorts them."""
    return k.encode("utf-16-be")


def canonical(v) -> str:
    """``v`` as canonical JSON: keys sorted, no whitespace, an empty container written as []."""
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, numbers.Real):
        return _number(v)
    if isinstance(v, str):
        return _string(v)
    if isinstance(v, dict):
        if not v:
            return "[]"
        keys = sorted((str(k) for k in v), key=_key)
        return "{" + ",".join(_string(k) + ":" + canonical(v[k]) for k in keys) + "}"
    if isinstance(v, (list, tuple)):
        return "[" + ",".join(canonical(x) for x in v) + "]"
    raise TypeError(f"content_hash cannot write a value of type {type(v).__name__}")


@theory_keyword
def content_hash(theory) -> str:
    """The SHA-256 digest of the theory's canonical form, as ``sha256:<64 hex digits>``.

    The canonical form is the theory as JSON with every mapping's keys sorted
    by their UTF-16 code units, no whitespace, strings escaped only where JSON
    requires it and numbers written with the fewest digits that read back as the
    same double, as RFC 8785 specifies. Three conventions make it the same in
    R and Python: an empty mapping is written as an empty sequence, since R
    holds the two alike, an infinity or a missing number is written as
    ``Infinity``, ``-Infinity`` or ``NaN``, and a single value in a field that
    the schema types as an array of strings, such as ``measurement`` or
    ``derives_from``, is written as a one-element array, since a reader takes
    ``derives_from: p1`` for ``[p1]``. R's ``tf_write()`` writes such a field
    as an array, so a theory keeps its hash when R writes it. The theory's own
    ``version.content_hash`` is left out, so that a file can record the hash of
    its content.

    Two theory files with the same content therefore have the same hash
    whatever their layout, comments, key order or format, and any change to a
    value changes it. Full validation checks a recorded hash against the
    content.

    Raises:
        TypeError: when the theory holds a value that YAML or JSON cannot
            hold.

    References:
        Rundgren, A., Jordan, B., & Erdtman, S. (2020). JSON Canonicalization
        Scheme (JCS) (RFC 8785). RFC Editor.
        https://doi.org/10.17487/RFC8785
    """
    data = plain(theory.data if hasattr(theory, "data") else theory)
    if isinstance(data, dict) and isinstance(data.get("version"), dict):
        version = {k: v for k, v in data["version"].items() if k != "content_hash"}
        data = {**data, "version": version}
    data = box_string_arrays(data)
    return "sha256:" + hashlib.sha256(canonical(data).encode("utf-8")).hexdigest()
