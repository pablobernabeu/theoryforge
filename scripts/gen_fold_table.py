#!/usr/bin/env python
"""Write ``schema/fold.json``, the table both twins fold text with.

Tokens (API_SPEC.md section 6) and SEM variable names (section 19) are compared
after this fold, so the table has to be identical in R and Python and must not
depend on either runtime's Unicode tables. It is generated here once, from
Python's ``unicodedata``, and committed. ``scripts/gen_golden.py`` mirrors it
into both packages, and ``tests/test_text_normalisation.py`` fails when the
committed file differs from what this script writes.

The table maps single characters to their folded text:

* Latin letters go to ASCII with their case kept. A precomposed letter whose
  canonical decomposition is a base letter followed by combining marks in
  U+0300-036F goes to the fold of its base (``É`` to ``E``, ``Ǣ`` to ``AE``).
  The Latin-1 Supplement and Latin Extended-A letters that have no such
  decomposition are spelt out in ``LATIN_EXTRA`` (``ß`` to ``ss``, ``ø`` to
  ``o``, ``ł`` to ``l`` and so on), following the usual ASCII transliteration.
* Greek and Cyrillic letters go to their small base letter: a capital to its
  small letter where the case mapping is one code point to one, final sigma to
  sigma, and a precomposed letter as above to the small form of its base
  (``Ά`` and ``ά`` to ``α``, ``Й`` and ``й`` to ``и``).

The combining marks U+0300-036F are deleted, so a text in NFD folds as its NFC
form does. No output contains a character the table folds, which lets R apply
the one-character entries with ``chartr`` and the longer ones with ``gsub``, one
after the other, and still agree with Python's single ``str.translate``.
"""
from __future__ import annotations

import json
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "schema" / "fold.json"

MARKS = (0x0300, 0x036F)

# Blocks whose precomposed letters are folded through their decomposition. The
# Latin Extended-B, Latin Extended Additional and Greek Extended blocks hold the
# precomposed letters of Vietnamese, pinyin and polytonic Greek, among others,
# which an NFD text spells with marks from U+0300-036F.
LATIN_BLOCKS = ((0x00C0, 0x024F), (0x1E00, 0x1EFF))
GREEK_BLOCKS = ((0x0370, 0x03FF), (0x1F00, 0x1FFF))
CYRILLIC_BLOCKS = ((0x0400, 0x04FF),)
# Case is folded in the Greek and Coptic and the Cyrillic blocks only.
CASE_BLOCKS = ((0x0370, 0x03FF), (0x0400, 0x04FF))

# Latin letters without a canonical decomposition.
LATIN_EXTRA = {
    "\u00c6": "AE", "\u00e6": "ae",   # Æ æ
    "\u00d0": "D", "\u00f0": "d",     # Ð ð
    "\u00d8": "O", "\u00f8": "o",     # Ø ø
    "\u00de": "TH", "\u00fe": "th",   # Þ þ
    "\u00df": "ss",                   # ß
    "\u0110": "D", "\u0111": "d",     # Đ đ
    "\u0126": "H", "\u0127": "h",     # Ħ ħ
    "\u0131": "i",                    # ı
    "\u0132": "IJ", "\u0133": "ij",   # Ĳ ĳ
    "\u0138": "q",                    # ĸ
    "\u013f": "L", "\u0140": "l",     # Ŀ ŀ
    "\u0141": "L", "\u0142": "l",     # Ł ł
    "\u0149": "n",                    # ŉ
    "\u014a": "N", "\u014b": "n",     # Ŋ ŋ
    "\u0152": "OE", "\u0153": "oe",   # Œ œ
    "\u0166": "T", "\u0167": "t",     # Ŧ ŧ
    "\u017f": "s",                    # ſ
    "\u1e9e": "SS",                   # ẞ
}


def _in(cp: int, blocks) -> bool:
    return any(lo <= cp <= hi for lo, hi in blocks)


def _is_mark(ch: str) -> bool:
    return MARKS[0] <= ord(ch) <= MARKS[1]


def _base(ch: str) -> str | None:
    """The base letter of ``ch`` when its NFD is that letter plus marks, else None."""
    nfd = unicodedata.normalize("NFD", ch)
    if nfd == ch or not all(_is_mark(c) for c in nfd[1:]):
        return None
    return nfd[0]


def _small(ch: str) -> str:
    low = ch.lower()
    return low if len(low) == 1 else ch


def build() -> dict:
    """The fold table as the JSON object written to ``schema/fold.json``."""
    table: dict[str, str] = dict(LATIN_EXTRA)
    for cp in range(0x00C0, 0x2000):
        ch = chr(cp)
        if ch in table or not unicodedata.category(ch).startswith("L"):
            continue
        base = _base(ch)
        if _in(cp, LATIN_BLOCKS):
            if base is not None:
                table[ch] = LATIN_EXTRA.get(base, base)
        elif _in(cp, GREEK_BLOCKS) or _in(cp, CYRILLIC_BLOCKS):
            if base is not None:
                table[ch] = _small(base)
            elif ch == "\u03c2":                       # final sigma
                table[ch] = "\u03c3"
            elif _in(cp, CASE_BLOCKS) and _small(ch) != ch:
                table[ch] = _small(ch)
    # An entry that maps a character to itself folds nothing.
    table = {k: v for k, v in table.items() if v != k}
    for k, v in table.items():
        if any(c in table or _is_mark(c) for c in v):
            raise SystemExit(f"U+{ord(k):04X} folds to {v!r}, which would be folded again")
    entries = dict(sorted(table.items(), key=lambda kv: ord(kv[0])))
    return {
        "description": (
            "Characters folded before text is tokenised or turned into a SEM variable name "
            "(API_SPEC.md sections 6 and 19, rules in section 3). Each key folds to its value, "
            "and the combining marks in delete_ranges are removed. Written by "
            "scripts/gen_fold_table.py. Do not edit it by hand."
        ),
        "delete_ranges": [[f"{MARKS[0]:04X}", f"{MARKS[1]:04X}"]],
        "map": entries,
    }


def main() -> int:
    table = build()
    text = json.dumps(table, ensure_ascii=False, indent=1) + "\n"
    OUT.write_bytes(text.encode("utf-8"))
    print(f"wrote {len(table['map'])} entries to {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
