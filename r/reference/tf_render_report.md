# Write a Quarto report for a theory

Writes a standalone Quarto report to `path` (forced to a `.qmd` suffix):
a YAML header (`title`, `format`) followed by the deterministic
`tf_dossier(theory)` body. Returns the written path. When
`render = TRUE`, invokes `quarto render`, which requires a Quarto
installation, and stops if that render fails.

## Usage

``` r
tf_render_report(theory, path, title = NULL, render = FALSE, to = "html")
```

## Arguments

- theory:

  A theory object (named list), e.g. from
  [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md).

- path:

  Destination path; any extension is replaced with `.qmd`.

- title:

  Optional report title; defaults to
  `"theoryforge report: <title-or-id>"`, also when `NULL`, `NA` or
  empty. It is written as a YAML double-quoted scalar with backslashes,
  double quotes and control characters escaped, so a YAML parser reads
  back exactly the string passed. Quarto then reads the title as
  Markdown, so raw TeX such as `\emph{}` is dropped from HTML output and
  `$\alpha$` becomes mathematics.

- render:

  When `TRUE`, run `quarto render` on the written file and stop if it
  exits non-zero.

- to:

  Quarto output format (default `"html"`).

## Value

The path of the written `.qmd` file.

## Examples

``` r
theory <- tf_theory("demo-1", "A demonstration theory") |>
  tf_add_construct("c_arousal", "Arousal", "Bodily activation.")
path <- tempfile(fileext = ".qmd")
tf_render_report(theory, path)
#> [1] "/tmp/Rtmp3QuhJx/file1a1d7f41c4a1.qmd"
```
