# About

## Citing theoryforge

If you use the Python package in your work, please cite it:

````python exec="1"
# The reference, the BibTeX entry and the download link are all written from
# one string at build time. The version is the installed distribution's
# (theoryforge.__version__), or pyproject.toml's when the package runs from an
# uninstalled source tree, and the year is that of the release date recorded in
# the repository's CITATION.cff, so neither is written by hand here. The
# download link is a self-contained data URI carrying exactly the string the
# fenced block shows, so no file has to be shipped beside the site. The
# extra.version chip in mkdocs.yml cannot run code and is updated on release.
import re
from pathlib import Path
from urllib.parse import quote

import theoryforge

# src/theoryforge/__init__.py, three levels below the repository root.
root = Path(theoryforge.__file__).resolve().parents[3]
version = theoryforge.__version__
if version == "0+unknown":
    pyproject = (root / "python" / "pyproject.toml").read_text(encoding="utf-8")
    version = re.search(r'^version\s*=\s*"([^"]+)"', pyproject, re.M).group(1)
cff = (root / "CITATION.cff").read_text(encoding="utf-8")
year = re.search(r'^date-released:\s*"?(\d{4})-', cff, re.M).group(1)
doi = re.search(r'^doi:\s*"?([^"\s]+)', cff, re.M).group(1)

bibtex = "\n".join(
    [
        "@Manual{theoryforge,",
        "  title  = {theoryforge: Systematic theory development},",
        "  author = {Pablo Bernabeu},",
        f"  year   = {{{year}}},",
        f"  note   = {{Python package version {version}}},",
        f"  doi    = {{{doi}}},",
        "  url    = {https://pypi.org/project/theoryforge/},",
        "}",
    ]
)

print(
    '<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">'
    f"Bernabeu, P. ({year}). <em>theoryforge: Systematic theory development</em> "
    f"(Python package version {version}). "
    f'<a href="https://doi.org/{doi}">https://doi.org/{doi}</a></p>'
)
print()

# A real fenced block rather than raw HTML, so Material still highlights the
# entry and still offers its copy button.
print("```bibtex")
print(bibtex)
print("```")
print()

uri = "data:application/x-bibtex;charset=utf-8," + quote(bibtex, safe="")
print(
    f'You can <a href="{uri}" download="theoryforge.bib">download the BibTeX '
    "entry</a>. The package installs with `pip install theoryforge`."
)
````

## The developer

theoryforge is developed and maintained by
[Pablo Bernabeu](https://pablobernabeu.github.io), a researcher in the
Department of Education at the University of Oxford. His work spans cognitive psychology and
neuroscience, linguistics, education and digital technologies, and research methods and open
science. He has hands-on experience in behavioural and EEG experiments, corpus analysis,
computational modelling and statistics. He develops open, reproducible research software in R
and Python, and is a Fellow of the Software Sustainability Institute. His
[ORCID record](https://orcid.org/0000-0003-1083-2460) lists his other work.

This Python package has a twin written in R, documented on the
[theoryforge (R) site](https://pablobernabeu.github.io/theoryforge/r/). Both implement one
[specification](https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md) and are
tested against the same expected outputs, apart from the functions that call a network service,
an embedding model or a renderer.

## Licence

theoryforge is released under the MIT licence, which allows use, modification and
redistribution provided that the copyright and licence notices are kept. The full text is on
this site's [licence page](licence.md).

## Versions and archiving

Releases are tagged on [GitHub](https://github.com/pablobernabeu/theoryforge/releases) and
archived on Zenodo, which gives each release a DOI of its own. The concept DOI given in the
citation above resolves to the latest archived release, and the version in the citation
identifies the release used. The [changelog](changelog.md)
records what changed in each release.

## Contributing and support

Bugs and feature requests can be reported on the
[GitHub issues page](https://github.com/pablobernabeu/theoryforge/issues), and the
[contributing guide](https://github.com/pablobernabeu/theoryforge/blob/main/.github/CONTRIBUTING.md)
explains how to set up a development environment and propose a change. The OSF deposit
adapter takes a personal access token, so never paste that token, or any other secret, into an
issue. Replace it with a placeholder.
