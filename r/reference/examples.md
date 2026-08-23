# Access to the example theories shipped inside the package.

Thin wrappers over
[`system.file()`](https://rdrr.io/r/base/system.file.html), so that the
two twins name the examples the same way: the Python package exposes
`example_path()` and `example_names()` over the same files. The copies
under `inst/fixtures/` are written by `scripts/gen_golden.py` and gated
in CI, so they cannot drift from the originals at the repository root.
