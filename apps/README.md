# theoryforge interactive apps

Two browser apps that put a graphical interface on the twin packages. They run the
real package code entirely client-side: the R app via
[webR](https://docs.r-wasm.org/webr/latest/) and the Python app via
[Pyodide](https://pyodide.org/). Nothing is sent to a server, and the results are
identical to running the package locally. Every operation can export its
visualisation (SVG and PNG) and the R or Python code needed to reproduce it.

| App | Engine | Lives at (deployed) |
|---|---|---|
| `r/`  | webR (WebAssembly R)      | `…/theoryforge/apps/r/`  |
| `py/` | Pyodide (WebAssembly Py)  | `…/theoryforge/apps/py/` |

`shared/` holds the language-agnostic UI core, styles and favicon. A small
language runtime (`r-runtime.js`, `py-runtime.js`) boots the engine, vendors the
package source, runs operations and emits the reproducible code snippets.

## Runtimes

The R app loads webR 0.6.0 (R 4.6.0) and the Python app loads Pyodide 0.27.7
(Python 3.12.7, with PyYAML 6.0.2). Both releases are pinned in the runtimes, and the
two engines are updated together and deliberately, since a new engine can change the
version of the language the package runs under. The R app installs jsonlite and yaml
from repo.r-wasm.org when it loads. These two are not pinned: each session gets the
builds the repository serves that day, and the browser console records their
versions. The Graphviz renderer, `@hpcc-js/wasm-graphviz` 1.22.2, is pinned in
`shared/app-core.js`.

## Build and run locally

The apps fetch the live package source from a `vendor/` directory that
`build.mjs` assembles (git-ignored; rebuilt in CI on every deploy):

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
each example's version record when the app starts. `build.mjs` marks in each manifest
the files that package ships. The reproducible code reads those through
`example_path()` and asks for any other file to be saved beside the script first.

## Test

`apps/tests/` holds tests for the UI core, the two runtimes, `build.mjs` and the site's
landing and 404 pages. They run under Node's own test runner with a small stand-in for
the browser DOM (`tests/dom.mjs`), so they need no browser and no dependency:

```bash
node --test apps/tests/*.test.mjs   # from the repository root
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
therefore cannot stand in for a file the app does not fetch. Each script runs every
operation on every example, with the operations listed in
`scripts/app_smoke_cases.json`, and checks that an invalid theory is reported as
invalid. The CI apps job runs both scripts.

## Deploy

The `docs` GitHub Actions workflow runs `node build.mjs`, copies `apps/` into
`site/apps/` and runs the two smoke scripts on that copy. It then deploys the site,
so the apps are published alongside the documentation on GitHub Pages. The first load
of each app downloads its WebAssembly engine (~20 s). After that it is cached by the
browser.
