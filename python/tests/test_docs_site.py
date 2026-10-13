"""The Python documentation site, checked from its sources.

markdown-exec runs the guides' example blocks when the site is built, but a reader sees
only the blocks that show their source, and those are the ones a reader copies. They must
run on their own after ``pip install theoryforge``, away from a clone. The first test
therefore runs each page's visible blocks from an empty directory and leaves the hidden
ones out, so a name that only a hidden block defines fails here as it would for the
reader. The home page's first look is checked the same way. The diagrams are rendered
when the site is built, so no page holds a pasted figure, and a second test runs every
block in page order, the hidden figure blocks included, with a stand-in for Graphviz. The
methodology page's table of rigour checks quotes the checklist the package ships. The
pages sit in python/docs, beside the package, so the tests skip where they are absent.
"""

import contextlib
import copy
import io
import re
import sys
import types
from pathlib import Path

import pytest

from theoryforge import _resources, examples

DOCS = Path(__file__).resolve().parents[1] / "docs"
PAGES = sorted(DOCS.glob("*.md")) if DOCS.is_dir() else []
# A python block, with the info string that carries markdown-exec's options.
PYTHON_FENCE = re.compile(r"^```python([^\n]*)\n(.*?)^```[ \t]*$", flags=re.S | re.M)
ANY_FENCE = re.compile(r"^```.*?^```[ \t]*$", flags=re.S | re.M)
OPTION = re.compile(r'(\w+)="([^"]*)"')


def _text(path: Path) -> str:
    if not path.exists():
        pytest.skip(f"{path.name} not available")
    return path.read_text(encoding="utf-8")


def _blocks(text: str) -> list[tuple[dict, str]]:
    """Each python block of a page, as its markdown-exec options and its code."""
    return [(dict(OPTION.findall(m.group(1))), m.group(2)) for m in PYTHON_FENCE.finditer(text)]


def _run(code: str, namespace: dict, name: str) -> str:
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        exec(compile(code, name, "exec"), namespace)
    return out.getvalue()


def _table_rows(markdown: str) -> list[list[str]]:
    """The body rows of the Markdown table in a text, split into cells."""
    lines = [line.strip() for line in markdown.splitlines() if line.lstrip().startswith("|")]
    return [[cell.strip() for cell in line.strip("|").split("|")] for line in lines[2:]]


@pytest.mark.parametrize("page", PAGES, ids=[p.name for p in PAGES])
def test_visible_code_runs_as_shown(page, tmp_path, monkeypatch):
    # markdown-exec runs the blocks of one session in one namespace, in page order. A
    # block without a source option is hidden from the reader, so it is left out here,
    # and nothing it defines is there for the blocks the reader copies.
    monkeypatch.chdir(tmp_path)
    sessions: dict[str, dict] = {}
    for i, (options, code) in enumerate(_blocks(_text(page)), start=1):
        if options.get("exec") != "1" or "source" not in options:
            continue
        namespace = sessions.setdefault(options.get("session") or f"block {i}", {"__name__": "__docs__"})
        _run(code, namespace, f"{page.name}, python block {i}")


class _Source:
    """Stands in for graphviz.Source. Its pipe() returns an SVG document headed as the
    one Graphviz writes, XML declaration first, without running dot."""

    def __init__(self, source: str):
        self.source = source

    def pipe(self, format=None, encoding=None):
        assert (format, encoding) == ("svg", "utf-8")
        name = self.source.split("{", 1)[0].split()[-1]
        return (
            '<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n'
            f"<!-- Title: {name} Pages: 1 -->\n"
            f'<svg width="8pt" height="8pt"><g id="graph0" class="graph"><title>{name}</title></g></svg>\n'
        )


@pytest.mark.parametrize("page", PAGES, ids=[p.name for p in PAGES])
def test_every_block_runs_in_page_order(page, tmp_path, monkeypatch):
    # The hidden blocks draw the figures from the names that the visible blocks define,
    # and only the site build, run on the main branch, draws them with Graphviz. Here
    # every block runs in page order, as markdown-exec runs them, and render_diagram()
    # builds the DOT of each view as usual but hands it to the stand-in above. A figure
    # block that names a missing object or an unknown view, or prints the XML declaration
    # into the page, fails here on every pull request.
    fake = types.ModuleType("graphviz")
    fake.Source = _Source
    monkeypatch.setitem(sys.modules, "graphviz", fake)
    monkeypatch.chdir(tmp_path)
    sessions: dict[str, dict] = {}
    for i, (options, code) in enumerate(_blocks(_text(page)), start=1):
        if options.get("exec") != "1":
            continue
        namespace = sessions.setdefault(options.get("session") or f"block {i}", {"__name__": "__docs__"})
        out = _run(code, namespace, f"{page.name}, python block {i}")
        if "render_diagram(" in code:
            assert options.get("html") == "1", f"python block {i} prints a figure as text"
            assert out.startswith('<div class="tf-figure tf-diagram"><svg '), out[:80]
            assert out.rstrip().endswith("</svg>\n</div>"), out[-80:]


def test_home_page_first_look_runs_outside_the_repository(tmp_path, monkeypatch):
    # The first look is shown, not run, when the site is built, so it is run here from a
    # directory that holds no example files.
    shown = [code for options, code in _blocks(_text(DOCS / "index.md")) if "exec" not in options]
    assert shown, "the home page has no python block"
    monkeypatch.chdir(tmp_path)
    _run(shown[0], {"__name__": "__docs__"}, "index.md")


@pytest.mark.parametrize("page", PAGES, ids=[p.name for p in PAGES])
def test_no_page_reads_a_fixtures_directory(page):
    # The guides read the examples through a `fixtures` path that a hidden block found by
    # walking up from the build directory. The reader saw only the reads.
    text = _text(page)
    assert "fixtures /" not in text
    assert "_find_fixtures" not in text


@pytest.mark.parametrize("page", PAGES, ids=[p.name for p in PAGES])
def test_figures_are_rendered_when_the_site_is_built(page):
    # A pasted figure keeps the picture of the day it was pasted, and two of the eight had
    # drifted from the DOT printed above them. Blocks that run at build time draw them
    # now, so outside the code blocks no SVG is left.
    assert "<svg" not in ANY_FENCE.sub("", _text(page))


def _criteria_block() -> tuple[str, str]:
    text = _text(DOCS / "methodology.md")
    found = [code for options, code in _blocks(text) if options.get("exec") == "1" and "checklist()" in code]
    assert len(found) == 1, "one block on the methodology page builds the table of checks from checklist()"
    return text, found[0]


def test_methodology_table_quotes_the_checklist():
    text, code = _criteria_block()
    rows = _table_rows(_run(code, {"__name__": "__docs__"}, "methodology.md"))
    items = _resources.checklist()["items"]
    assert [row[1] for row in rows] == [item["criterion"] for item in items]
    named = [re.search(r"\(`(\w+)`\)", row[0]) for row in rows]
    assert [m.group(1) if m else None for m in named] == [item["id"] for item in items]
    # No copy of a criterion is left in a table written into the page itself.
    written = [line for line in ANY_FENCE.sub("", text).splitlines() if line.lstrip().startswith("|")]
    assert [line for line in written for item in items if item["criterion"] in line] == []


def test_methodology_table_stops_at_a_check_it_cannot_name(monkeypatch):
    # A check the checklist gains has no name or supporting work on the page yet, so the
    # block refuses it, and the strict build fails until the page is brought up to date.
    _, code = _criteria_block()
    spec = copy.deepcopy(_resources.checklist())
    spec["items"].append({"id": "new_check", "criterion": "A criterion the page does not know",
                          "weight": 0.0, "severity_if_fail": "warning", "citation": ""})
    monkeypatch.setattr(_resources, "checklist", lambda: spec)
    with pytest.raises(RuntimeError, match="new_check"):
        _run(code, {"__name__": "__docs__"}, "methodology.md")


def test_example_functions_name_their_r_counterparts():
    # The docstring and the Get started page named only system.file(), although the R
    # twin has offered tf_example_path() and tf_example_names() since 0.6.0.
    for text in (examples.__doc__ or "", _text(DOCS / "getting-started.md")):
        assert "tf_example_path()" in text
        assert "tf_example_names()" in text
