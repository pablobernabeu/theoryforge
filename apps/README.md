# theoryforge interactive apps

Two browser apps put a graphical interface on the twin packages. They run the
package code entirely client-side: the R app via
[webR](https://docs.r-wasm.org/webr/latest/) and the Python app via
[Pyodide](https://pyodide.org/). Nothing is sent to a server, and the results are
identical to running the package locally. A researcher can build or edit a theory in
forms without writing YAML, run the package's operations on it and export each
result: figures as SVG and PNG, text and JSON results as files and the R or Python
code that reproduces the result with the installed package.

| App | Engine | Deployed at |
|---|---|---|
| `r/`  | webR (WebAssembly R)      | `…/theoryforge/apps/r/`  |
| `py/` | Pyodide (WebAssembly Py)  | `…/theoryforge/apps/py/` |

`shared/` holds the language-agnostic part of the apps. `app-core.js` holds the
operations, the interface and the shaping of each result, `editor.js` the theory
editor, `markdown.js` the renderer of the preregistration and
the dossier and `share.js` the link that carries a session. `app.css` styles both
apps. A small language runtime (`r-runtime.js`, `py-runtime.js`) starts the engine,
loads the package source into it, runs operations and writes the reproducible code.

## The editor

The editor shows the theory as forms, one card for each construct, proposition,
phenomenon, prediction, auxiliary assumption, alternative, evidence entry and test
outcome, beside a source pane that holds the same theory as YAML or JSON. Either can
be edited. The app hands each version to the engine, which reads it with the
package's reader, validates it in full and scores it with the rigour checklist, so
the problems shown beside the fields and the score and gate above them are the
package's own. A change in the forms rewrites the source with the package's writer,
which keeps no comments, and a change in the source rebuilds the forms. New theory
starts from an empty template, and any example or upload can be edited. Save writes
the theory as YAML with `tf_write()` or `Theory.write()`, so the file reads back as
the same theory in either package.

Import DAGitty hands model code from dagitty.net or from `dagitty::dagitty()` to the
package's own reader, `read_dagitty()` in Python and `tf_read_dagitty()` in R, and the
theory it makes replaces the one in the editor. The reader takes `dag { ... }` with
`->`, `<-` and `<->`, chains such as `a -> b -> c`, groups such as `{a b}` and quoted
names, and ignores attributes in square brackets. Each variable becomes a construct
and each edge a proposition: `->` as `causes`, or as `increases` or `decreases` when
that sign is chosen, and `<->` as `associates`. The dialog shows the R or Python code
that makes the same theory. A package version without the reader leaves the button
disabled.

## Operations

The operations are grouped by what they are for. Assess holds the rigour checklist,
full validation, the severity rubric, post-data severity and the redundancy screen.
Derive holds the implied independencies, what the causal graph entails, equivalent
models and the lavaan syntax. Compare sets the theory against a rival (an alternative
that states propositions, or an uploaded theory) and appraises an amendment against a
prior version. Document draws the diagrams and writes the preregistration and the
dossier, shown as HTML with the Markdown a click away. Simulate propagates the
construct network as a linear system, from one value for every construct or from an
impulse in one of them. Literature maps the bundled demonstration corpus, a frozen
OpenAlex corpus of 150 works on panic disorder or an uploaded corpus, with the theme
method, min_df and max_df of `litmap()`. The theory landscape takes the method too,
and builds its themes with `litmap()`'s other settings at their defaults, since
`landscape()` takes no min_df or max_df.

The apps make no network request for data. The literature operations read the files
listed above, so every result rests on files the user can see and save, and nothing
about a theory reaches another service. OpenAlex and Crossref would answer a browser
directly, so `fetch_corpus()` could run here in principle. To map a fresh corpus, run
it in the package and upload the file it writes. The embedding-based redundancy screen
needs an embedding model, and the OSF deposit needs a personal access token, which a
web page should not hold, so both stay in the installed package.

## Links

Copy link writes the theory and the chosen operation into the URL fragment, the part
after `#`, which browsers do not send to the server. The state is JSON, compressed
with the browser's `CompressionStream('deflate-raw')` and encoded as base64url. An
example travels as its path and any other theory as its text. Links are kept below
16,000 characters so that mail clients and chat programs pass them on whole, and a
theory too large for that is better sent as a file. An uploaded prior, rival or
corpus is not carried.

## Runtimes

The R app loads webR 0.6.1 (R 4.6.0) and the Python app loads Pyodide 314.0.8
(Python 3.14.2, with PyYAML 6.0.3), the releases npm tags as latest. Before the moves
from webR 0.6.0 and Pyodide 0.27.7, each app was booted in headless Chromium on the
new release, and every operation ran on every example there
(`tests/browser.e2e.mjs`). The CI apps job runs the Python glue under Python 3.14
with PyYAML 6.0.3 to match. Both releases are pinned in the runtimes, and the two
engines are updated deliberately, since a new engine can change the version of the
language the package runs under. The R app installs jsonlite and yaml from
repo.r-wasm.org when it loads. These two are not pinned: each session gets the builds
the repository serves that day, and the browser console records their versions. The
Graphviz renderer, `@hpcc-js/wasm-graphviz` 1.22.2, is pinned in `shared/app-core.js`.

## Build and run locally

The apps fetch the live package source from a `vendor/` directory that `build.mjs`
assembles. The directory is git-ignored and is rebuilt in CI on every deploy.

```bash
cd apps
node build.mjs                 # vendor R + Python source, schema and fixtures
python -m http.server 8765     # serve over HTTP (file:// will not work)
# open http://localhost:8765/r/  and  http://localhost:8765/py/
```

Each load runs the package's full validation, and the theory card says whether the
theory is valid or how many problems it has. A file that cannot be read leaves the
previous theory loaded. The apps keep the session and the theme in the browser's
storage when it is available and run without it when the browser blocks it.

The amendment appraisal defaults to the version the loaded theory declares as its
parent and otherwise waits for a prior to be chosen or uploaded. The runtimes read
each example's version record when the app starts.

`build.mjs` marks in each manifest the files that the corresponding package includes.
The reproducible code reads those through `example_path()` and asks for any other
file to be saved beside the script first.

## Test

`apps/tests/` holds tests for the UI core, the editor's helpers and its DAGitty
reader, the Markdown renderer, the link, the colour contrast of both themes, the two
runtimes and their reproducible code, `build.mjs` and the site's landing and 404
pages. They run under Node's built-in test runner with a small stand-in for the
browser DOM (`tests/dom.mjs`), so they need no browser and no dependency.
`tests/code.test.mjs` also runs every Python snippet the app writes under the Python
on the path with PyYAML and checks that it prints its result. It skips when there is
no such Python.

```bash
node --test apps/tests/*.test.mjs   # from the repository root
```

`tests/browser.e2e.mjs` drives both apps in Chromium with Playwright. It boots the
two engines and runs every operation on every example and on a theory it builds in
the editor. It checks how a source the package cannot read is reported, the layout at
390 and 768 px wide and the contrast of coloured text in both themes. Last, it
compares the displayed text of the two apps wherever the packages promise the same
output. It needs Playwright with its Chromium and network access to the engines'
hosts, so `node --test` leaves it out:

```bash
node apps/build.mjs
node apps/tests/browser.e2e.mjs            # --apps r or py, --shots DIR for screenshots
```

The glue code each runtime runs in its engine is tested in the package suites
(`python/tests/test_app_glue.py`, `r/theoryforge/tests/testthat/test-app-glue.R`).

Two scripts run that glue on exactly the files the browser receives, once
`node apps/build.mjs` has written them:

```bash
python scripts/app_smoke.py   # from the repository root
Rscript scripts/app_smoke.R
```

Each script copies the files its manifest lists into a temporary directory and runs
the glue there. The Python glue runs under CPython with PyYAML alone, and the R glue
in a fresh R whose library holds jsonlite and yaml alone. An installed theoryforge
therefore cannot supply a file the app does not fetch. Each script runs every
operation listed in `scripts/app_smoke_cases.json` and the editor's call on every
example, after uploading a prior, a rival and a corpus. It then checks that an invalid
theory is reported as invalid. The CI apps job runs both scripts, and the CI browser
job runs the browser test.

## Deploy

The `docs` GitHub Actions workflow runs `node build.mjs` and the unit tests, copies
`r/`, `py/` and `shared/` into `site/apps/` and runs the two smoke scripts on that
copy. It then
deploys the site to GitHub Pages, where the apps are published alongside the
documentation. The first load of each app downloads its WebAssembly engine, which
takes about 20 s, and the browser then caches the engine.
