"""Text normalisation shared by every consumer (API_SPEC.md sections 3, 6, 18 and 19).

The two languages disagree on what whitespace is and on how to lowercase:
Python's ``str.strip()`` and R's ``trimws()`` trim different characters, and
``str.lower()`` turns the Turkish dotted capital I into two code points where
R's ``tolower()`` gives one. These helpers pin one reading, and R's ``text.R``
mirrors each of them.
"""
from __future__ import annotations

import re
import string

from . import _resources

# Unicode's White_Space property, 25 code points. Python's str.isspace() adds
# U+001C-001F, and R's trimws() trims only space, tab, CR and LF by default.
WS = ("\t\n\x0b\x0c\r \x85\xa0\u1680"
      + "".join(chr(cp) for cp in range(0x2000, 0x200B))
      + "\u2028\u2029\u202f\u205f\u3000")

_ASCII_LOWER = str.maketrans(string.ascii_uppercase, string.ascii_lowercase)


def trim(s: str) -> str:
    """``s`` without leading or trailing characters of the whitespace set."""
    return s.strip(WS)


def ascii_lower(s: str) -> str:
    """``s`` with A-Z lowercased and every other character kept."""
    return s.translate(_ASCII_LOWER)


def fold(s: str) -> str:
    """``s`` folded through ``schema/fold.json``: accents and Greek and Cyrillic case removed."""
    return s.translate(_resources.fold_table())


def normalise_words(s: str) -> str:
    """The fold, then ASCII lowercasing: what tokens and SEM names are built from."""
    return ascii_lower(fold(s))


# A DOI as Crossref matches one, with explicit ASCII classes: R's PCRE and
# Python's re give \d, \S and \v different meanings.
_DOI = re.compile(r"10\.[0-9]{4,9}/[^\x09-\x0d\x20]+")
_PCT = re.compile(r"%[0-9a-f]{2}")
_DOI_PREFIXES = ("https://doi.org/", "http://doi.org/", "https://dx.doi.org/", "http://dx.doi.org/", "doi:")


def _pct(m: re.Match) -> str:
    v = int(m.group(0)[1:], 16)
    return chr(v) if 0x21 <= v <= 0x7E else m.group(0)


def normalise_doi(doi) -> str:
    """The form two DOIs are compared in (API_SPEC.md section 18).

    Trimmed and lowercased (ASCII only, as the DOI Handbook prescribes), with
    every percent escape of a printable ASCII character decoded, then the first
    run that looks like a DOI, less any trailing full stops, commas or
    semicolons. Text with no such run keeps the 0.6.0 rule: one known prefix is
    removed and the rest trimmed again.
    """
    d = ascii_lower(trim(str(doi or "")))
    d = _PCT.sub(_pct, d)
    m = _DOI.search(d)
    if m:
        return m.group(0).rstrip(".,;")
    for prefix in _DOI_PREFIXES:
        if d.startswith(prefix):
            return trim(d[len(prefix):])
    return d
