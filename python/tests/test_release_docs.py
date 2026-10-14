"""The PyPI page and the release metadata, checked from the repository.

python/README.md is the long description PyPI shows, so its quick start is the first code
most users run, straight after ``pip install`` and with no clone. The first test runs that
block from a directory outside the repository, as the CI wheel job does with the installed
wheel. PyPI shows the page away from GitHub, so the logo needs an absolute address, and the
changelog must date the release that CITATION.cff cites as CITATION.cff does. Those two
files sit at the root of the repository, outside the Python project, so that test skips
where they are absent. The last test reads pyproject.toml with tomllib, or on Python 3.10
with tomli, which pytest itself requires there.
"""

import re
from pathlib import Path

import pytest
import yaml

PYTHON_DIR = Path(__file__).resolve().parents[1]
REPO = PYTHON_DIR.parent
README = PYTHON_DIR / "README.md"
PYPROJECT = PYTHON_DIR / "pyproject.toml"
CHANGELOG = REPO / "CHANGELOG.md"
CITATION = REPO / "CITATION.cff"
# The logo's address on GitHub, down to the folder this README sits in.
RAW_PYTHON_DIR = "https://raw.githubusercontent.com/pablobernabeu/theoryforge/main/python/"


def _text(path: Path) -> str:
    if not path.exists():
        pytest.skip(f"{path.name} not available")
    return path.read_text(encoding="utf-8")


def test_readme_quick_start_runs_outside_the_repository(tmp_path, monkeypatch):
    # The blocks before the quick start are shell commands, so the first python
    # block is the quick start, the block the CI wheel job runs.
    blocks = re.findall(r"^```python[ \t]*\n(.*?)^```", _text(README), flags=re.S | re.M)
    assert blocks, "the README has no python block"
    monkeypatch.chdir(tmp_path)
    exec(compile(blocks[0], str(README), "exec"), {"__name__": "__readme__"})


def test_readme_logo_has_an_absolute_address():
    # PyPI serves the page from its own host, so a relative src such as
    # docs/assets/logo.png names nothing there and shows as a broken image.
    img = re.search(r'<img\s[^>]*\bsrc="([^"]+)"', _text(README))
    assert img, "the README has no logo"
    src = img.group(1)
    assert src.startswith("https://"), f"PyPI cannot resolve the relative address {src!r}"
    if src.startswith(RAW_PYTHON_DIR):
        assert (PYTHON_DIR / src[len(RAW_PYTHON_DIR):]).is_file(), f"{src} names no file here"


def test_changelog_dates_the_cited_release_as_citation_cff_does():
    cff = yaml.safe_load(_text(CITATION))
    version, released = str(cff["version"]), str(cff["date-released"])
    heading = re.search(rf"^## \[{re.escape(version)}\] - (\S+)[ \t]*$", _text(CHANGELOG), flags=re.M)
    assert heading, f"CHANGELOG.md has no dated heading for {version}"
    assert heading.group(1) == released, (
        f"CHANGELOG.md dates {version} {heading.group(1)}, CITATION.cff {released}"
    )


def _pyproject() -> dict:
    try:
        import tomllib
    except ImportError:  # Python 3.10
        tomllib = pytest.importorskip("tomli")
    return tomllib.loads(_text(PYPROJECT))


def test_pyproject_has_no_obsolete_backend_cap_or_licence_classifier():
    data = _pyproject()
    # hatchling was held below 1.32, which writes Metadata-Version 2.5, while twine could not
    # read that version. twine 7.0.0 passes it, so a cap would only withhold the backend's fixes.
    capped = [
        req for req in data["build-system"]["requires"]
        if re.match(r"\s*hatchling\b", req, flags=re.I) and re.search(r"<|~=|==", req)
    ]
    assert not capped, f"the build backend is capped: {capped}"
    project = data["project"]
    # A string is an SPDX expression (PEP 639), which the wheel's metadata carries as
    # License-Expression. A table would put the whole licence text in License instead.
    assert project["license"] == "MIT"
    assert project.get("license-files") == ["LICENSE"]
    # PEP 639 deprecates licence classifiers and lets a backend refuse one beside an
    # expression, so the licence is declared once.
    licence_classifiers = [c for c in project.get("classifiers", []) if c.startswith("License ::")]
    assert not licence_classifiers, f"licence classifiers beside license: {licence_classifiers}"
