# About

## Citing theoryforge

If you use the Python package in your work, please cite it:

````python exec="1"
# The reference, the BibTeX entry and the download link are all written from
# one string at build time, so the version can no longer drift between them. It
# comes from theoryforge.__version__, which reads the installed distribution's
# metadata, the same source the rest of the site trusts. The version was
# previously typed out three times on this page, and a hand-maintained copy of
# the entry shipped beside the site as theoryforge.bib. The download link is now
# a self-contained data URI carrying exactly the string the fenced block shows,
# so the two cannot disagree and no file has to be shipped alongside the site.
#
# Two further copies of the version are out of reach here, because neither file
# can execute code, and both still have to be bumped by hand on release: the
# extra.version chip in mkdocs.yml, and the version field of CITATION.cff.
from urllib.parse import quote

import theoryforge

version = theoryforge.__version__
doi = "10.5281/zenodo.21229964"

bibtex = "\n".join(
    [
        "@Manual{theoryforge,",
        "  title  = {theoryforge: Systematic theory development},",
        "  author = {Pablo Bernabeu},",
        "  year   = {2026},",
        f"  note   = {{Python package version {version}}},",
        f"  doi    = {{{doi}}},",
        f"  url    = {{https://doi.org/{doi}}},",
        "}",
    ]
)

print(
    '<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">'
    "Bernabeu, P. (2026). <em>theoryforge: Systematic theory development</em> "
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
science, with hands-on experience in behavioural and EEG experiments, corpus analysis,
computational modelling and statistics. He develops open, reproducible research software in R
and Python, and is a Fellow of the Software Sustainability Institute. His
[ORCID record](https://orcid.org/0000-0003-1083-2460) lists his other work.

This Python package has a feature-parity twin written in R. Its documentation lives at the
[theoryforge (R) site](https://pablobernabeu.github.io/theoryforge/r/), keeping a theory
development workflow legible across both languages.

## Licence

theoryforge is released under the MIT licence, a permissive licence that allows use,
modification and redistribution provided the copyright and licence notices are kept. The full
text is reproduced on this site's [licence page](licence.md).

## Versioning and archival

Releases are tagged on [GitHub](https://github.com/pablobernabeu/theoryforge/releases) and
archived on [Zenodo](https://doi.org/10.5281/zenodo.21229964). The concept DOI,
10.5281/zenodo.21229964, always resolves to the latest version, so a citation stays current
without naming a version. The [changelog](changelog.md) records what changed in each release.

## Contributing and support

Bugs and feature requests are best reported on the
[GitHub issues page](https://github.com/pablobernabeu/theoryforge/issues), and the
[contributing guide](https://github.com/pablobernabeu/theoryforge/blob/main/.github/CONTRIBUTING.md)
explains how to set up a development environment and propose a change. Because the OSF deposit
adapter takes a personal access token, never paste that token, or any other secret, into an
issue. Replace it with a placeholder.
