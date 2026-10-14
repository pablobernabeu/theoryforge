"""Text normalisation shared by every consumer (API_SPEC.md sections 3, 6, 10, 14, 18 and 19).

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
_WS_RUN = re.compile("[" + re.escape(WS) + "]+")


def trim(s: str) -> str:
    """``s`` without leading or trailing characters of the whitespace set."""
    return s.strip(WS)


def squish(s: str) -> str:
    """``s`` trimmed, with each run of whitespace-set characters inside it made one space."""
    return trim(_WS_RUN.sub(" ", s))


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


def _prepared(s: str) -> str:
    """``s`` trimmed, lowercased (ASCII only) and percent-decoded, in that order."""
    return _PCT.sub(_pct, ascii_lower(trim(s)))


def find_doi(s: str) -> str | None:
    """The DOI in ``s`` in the form ``normalise_doi`` gives it, or None when there is none.

    ``s`` is trimmed and lowercased (ASCII only, as the DOI Handbook
    prescribes), with every percent escape of a printable ASCII character
    decoded. The result is the first run that looks like a DOI, less any
    trailing full stops, commas or semicolons. litmap keys a reference by it
    (API_SPEC.md section 14), and since the prefix rule of ``normalise_doi`` is
    left out, text without such a run gives None.
    """
    m = _DOI.search(_prepared(s))
    return m.group(0).rstrip(".,;") if m else None


def normalise_doi(doi) -> str:
    """The form two DOIs are compared in (API_SPEC.md section 18).

    The DOI that ``find_doi`` finds in the text. Text with no such run keeps the
    0.6.0 rule: trimmed, lowercased and percent-decoded, it loses a known
    prefix, if it has one, and is trimmed again.
    """
    text = str(doi or "")
    found = find_doi(text)
    if found is not None:
        return found
    d = _prepared(text)
    for prefix in _DOI_PREFIXES:
        if d.startswith(prefix):
            return trim(d[len(prefix):])
    return d
