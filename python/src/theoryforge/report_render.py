"""Render a theory's audit dossier as a standalone Quarto report.

Writes a ``.qmd`` (a YAML header plus the deterministic dossier body) and can optionally
invoke Quarto to render it. The report content is the deterministic ``dossier`` output, and
only the rendering step depends on the environment.

A theory file may come from someone else, and Quarto runs the code chunks and
inline code of a document, expands its shortcodes (which can read files and
environment variables) and passes on its raw HTML. The report is therefore
written so that the theory's text reaches Quarto as text alone, and text that
Quarto would decode as a shortcode after reading it is refused (API_SPEC.md
section 23).
"""
from __future__ import annotations

import os
import re
import subprocess

from ._access import text
from ._compat import theory_keyword
from ._io import write_lf as _write_lf
from ._text import quoted
from .dossier import dossier as _dossier
from .prereg import flat

# A Quarto format name, with any extensions added or removed (html, pdf,
# gfm+tex_math_dollars, acm-pdf), or the path of a custom writer
# (writers/plain.lua). Anything else could add keys to the header or options
# to the command line.
_FORMAT = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.+/-]*")

# The ASCII punctuation characters that Markdown and Quarto read as markup:
# all of them but the quotation marks, which open nothing once the others are
# escaped and keep their typographic form, and the backtick, which is written
# as an entity.
_PUNCT = re.compile(r"[!#-&(-/:-@\[-_{-~]")

# The text of an implied conditional independence that keeps its code span:
# letters, digits, underscores, bars, commas, full stops and spaces, so that it
# holds no brace, angle bracket, backtick or hyphen, and not 'r ' first, so
# that knitr reads no inline code in it.
_PLAIN_CODE = re.compile(r"[A-Za-z0-9_|,. ]+")

# Quarto's reader encodes each shortcode it finds in the text as a UUID
# followed by ';<hex>;' and, once Pandoc has read the document and removed its
# escapes, decodes such a run in any text and runs it as a shortcode. Any UUID
# is matched, in case another version of Quarto uses another one.
_ENCODED = re.compile(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12};[0-9A-Fa-f]+;")

# The marker that opens a heading or a list item of the dossier: spaces, then
# one to six number signs, a hyphen or a number with a full stop, then a space.
_MARKER = re.compile(r" *(?:#{1,6}|-|[0-9]+\.) ")

_YAML_DQ_ESCAPES = {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\t": "\\t"}


def _yaml_dq(s: str) -> str:
    """Escape ``s`` for the inside of a YAML double-quoted scalar.

    The rule the R twin's .tf_yaml_dq() applies character for character
    (API_SPEC.md section 23): backslash and double quote are escaped, newline and
    tab become \\n and \\t, every other C0 control, DEL and the C1 controls
    become \\xNN, and the noncharacters U+FFFE and U+FFFF become \\uFFFE and
    \\uFFFF, since YAML forbids all of these raw in a stream. Unescaped, "A\\B"
    would be a parse error and "\\emph" an escape sequence.
    """
    out = []
    for ch in s:
        code = ord(ch)
        if ch in _YAML_DQ_ESCAPES:
            out.append(_YAML_DQ_ESCAPES[ch])
        elif code < 0x20 or 0x7F <= code <= 0x9F:
            out.append(f"\\x{code:02X}")
        elif code in (0xFFFE, 0xFFFF):
            out.append(f"\\u{code:04X}")
        else:
            out.append(ch)
    return "".join(out)


def _md_text(s: str) -> str:
    """``s`` written so that Quarto reads each of its characters as text.

    Every ASCII punctuation character but the quotation marks gains a
    backslash, which Pandoc's Markdown reads as the character itself, so that
    no emphasis, link, span, attribute, raw HTML, mathematics or shortcode can
    open. A backtick becomes the entity ``&#96;``, since knitr finds inline
    code by its backticks whatever precedes them.
    """
    return _PUNCT.sub(lambda m: "\\" + m.group(), s).replace("`", "&#96;")


def _shortcodes(s: str) -> str:
    """``s`` with each Quarto shortcode delimiter in its escaped form.

    Quarto finds the shortcodes of the title once it has read the title as
    Markdown, so a backslash before the brace does not stop them there, and
    ``{{{<`` and ``>}}}`` are its own escapes.
    """
    return s.replace("{{<", "{{{<").replace(">}}", ">}}}")


def _qmd_body(md: str) -> str:
    """The dossier ``md`` as the report's body, its text escaped by ``_md_text``.

    A blank line and a row of the checklist table, which holds the checklist's
    own text alone, are kept as they are. Every other line keeps the marker of
    its heading or list item. A line without a marker that is set in italics
    keeps its two underscores. A list item that is a code span alone (an
    implied conditional independence) keeps it when its text is plain
    (``_PLAIN_CODE``), and otherwise loses its backticks, since the escaped
    text needs no code span to keep its underscores. The rest of the line is
    escaped.
    """
    out = []
    for line in md.split("\n"):
        if line == "" or line.startswith("|"):
            out.append(line)
            continue
        m = _MARKER.match(line)
        marker = m.group() if m else ""
        rest = line[len(marker):]
        if (marker.strip() == "-" and len(rest) > 1 and rest[0] == rest[-1] == "`"
                and "`" not in rest[1:-1]):
            inner = rest[1:-1]
            plain = _PLAIN_CODE.fullmatch(inner) and not inner.startswith("r ")
            rest = rest if plain else _md_text(inner)
        elif not marker and len(rest) > 1 and rest[0] == rest[-1] == "_":
            rest = "_" + _md_text(rest[1:-1]) + "_"
        else:
            rest = _md_text(rest)
        out.append(marker + rest)
    return "\n".join(out)


def _qmd_path(path: str) -> str:
    """``path`` with its file name ending in ``.qmd``, by the rule ``render_report()`` states.

    Written out in full, rather than with ``Path.with_suffix``, so that R's twin
    can follow the same rule character for character.
    """
    cut = max(path.rfind("/"), path.rfind("\\")) + 1
    folder, name = path[:cut], path[cut:]
    if name.lower().endswith(".qmd"):
        return path
    dot = name.rfind(".")
    if dot > 0:
        name = name[:dot]
    return folder + name + ".qmd"


@theory_keyword
def render_report(theory, path, title: str | None = None, render: bool = False, to: str = "html") -> str:
    """Write a Quarto report for the theory, and render it with Quarto when ``render=True``.

    The report is a YAML header followed by the ``dossier()`` body. The header gives
    ``title`` and ``format``, ``engine: markdown``, so that Quarto runs no code, and
    ``from: markdown-raw_html-raw_attribute-raw_tex``, so that it passes on no raw
    HTML, raw attribute or raw TeX. In the body, every ASCII punctuation character
    of the dossier's text but the quotation marks gains a backslash and a backtick
    becomes ``&#96;``, so that Quarto reads the theory's text as text: no code chunk,
    inline code, shortcode, link, span or tag can open from it. Typed ``--`` and
    ``...`` therefore show as typed, and a heading's anchor follows its typed text.
    The marker of each heading and list item, the underscores of a line in italics
    and the checklist table are kept. An implied conditional independence keeps its
    code span when it holds only letters, digits, ``_``, ``|``, ``,``, ``.`` and
    spaces and does not begin with ``r`` and a space, and is written without it
    otherwise.

    Quarto encodes a shortcode as a UUID followed by ``;<hex>;`` and decodes such a
    run in any text once the document is parsed, escapes removed. Text that
    holds one, a UUID followed by a semicolon, hexadecimal digits and a semicolon,
    is therefore refused: the dossier, the default title before it is escaped and a
    title passed by the caller with its backslashes removed.

    A file name that does not end in ``.qmd`` (in any letter case) loses everything from its
    last dot, unless the name begins with that dot, and gains ``.qmd``. So ``report.md`` is
    written as ``report.qmd``, ``report`` and ``.hidden`` gain the suffix and ``a.tar.gz``
    becomes ``a.tar.qmd``. A leading ``~`` stands for the home directory, as in R.
    ``to`` is the Quarto output format, ``"html"`` by default, written into the header and
    passed to ``quarto render --to``. It must be a format name or the path of a custom
    writer: a letter or digit followed by letters, digits, ``_``, ``.``, ``+``, ``/`` and
    ``-``, as in ``pdf``, ``gfm+tex_math_dollars`` or ``writers/plain.lua``.

    ``title`` defaults to ``"theoryforge report: <title-or-id>"``, also when empty, with the
    theory's title or id written on one line and escaped as the body is, and with
    Quarto's shortcode delimiters in their escaped forms ``{{{<`` and ``>}}}``. The
    title is written as a YAML double-quoted scalar with backslashes, double quotes and
    control characters escaped, so a YAML parser reads back exactly the string passed.
    Quarto then reads the title as Markdown, so in a title passed by the caller raw TeX
    such as ``\\emph{}`` is dropped from HTML output and ``$\\alpha$`` becomes
    mathematics.

    When ``to`` is not a format name or a writer, when ``check()`` refuses the theory or
    when the text holds an encoded shortcode, ``ValueError`` is raised before anything is
    written. With ``render=True``, the ``quarto`` command must be on the PATH, and it is
    given the absolute path of the report, so that a path beginning with ``-`` is not
    read as an option. A failed render raises ``subprocess.CalledProcessError`` and a
    missing Quarto ``FileNotFoundError``, after the ``.qmd`` has been written.

    Returns the path of the written ``.qmd``.
    """
    if not (isinstance(to, str) and _FORMAT.fullmatch(to)):
        raise ValueError("render_report requires `to` to be a Quarto format or writer of "
                         "letters, digits, '_', '.', '+', '/' and '-' that starts with a letter "
                         f"or digit, not {quoted(to)}")
    data = theory.data if hasattr(theory, "data") else theory
    # Fall back to the id when the title is empty as well as absent (matches R's nzchar fallback).
    label = flat(text(data.get("title")) or text(data.get("id")))
    # The title as Quarto reads it, escapes removed, which the refusal below scans.
    shown = title.replace("\\", "") if title else f"theoryforge report: {label}"
    title = title or f"theoryforge report: {_md_text(_shortcodes(label))}"
    path = _qmd_path(os.fspath(path))
    md = _dossier(data)
    for scanned in (shown, md):
        found = _ENCODED.search(scanned)
        if found:
            raise ValueError("render_report refuses text that Quarto reads as an encoded "
                             f"shortcode: '{found.group()}'")
    header = (f'---\ntitle: "{_yaml_dq(title)}"\nformat: {to}\nengine: markdown\n'
              "from: markdown-raw_html-raw_attribute-raw_tex\n---\n\n")
    _write_lf(path, header + _qmd_body(md))
    if render:
        target = os.path.abspath(os.path.expanduser(path))
        subprocess.run(["quarto", "render", target, "--to", to], check=True)  # pragma: no cover
    return str(path)
