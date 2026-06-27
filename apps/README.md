# theoryforge interactive apps

Two browser apps that put a graphical interface on the twin packages. They run
the **real** package code entirely client-side — the R app via
[webR](https://docs.r-wasm.org/webr/latest/) and the Python app via
[Pyodide](https://pyodide.org/) — so nothing is sent to a server and the results
are identical to running the package locally. Every operation can export its
visualisation (SVG and PNG) and the R/Python code needed to reproduce it.

| App | Engine | Lives at (deployed) |
|---|---|---|
| `r/`  | webR (WebAssembly R)      | `…/theoryforge/apps/r/`  |
| `py/` | Pyodide (WebAssembly Py)  | `…/theoryforge/apps/py/` |

`shared/` holds the language-agnostic UI core, styles and favicon. A small
language runtime (`r-runtime.js`, `py-runtime.js`) boots the engine, vendors the
package source, runs operations and emits the reproducible code snippets.

## Build and run locally

The apps fetch the live package source from a `vendor/` directory that
`build.mjs` assembles (git-ignored; rebuilt in CI on every deploy):

```bash
cd apps
node build.mjs                 # vendor R + Python source, schema and fixtures
python -m http.server 8765     # serve over HTTP (file:// will not work)
# open http://localhost:8765/r/  and  http://localhost:8765/py/
```

## Deploy

The `docs` GitHub Actions workflow runs `node build.mjs` and copies `apps/` into
`site/apps/`, so the apps are published alongside the documentation on GitHub
Pages. The first load of each app downloads its WebAssembly engine (~20 s); after
that it is cached by the browser.
