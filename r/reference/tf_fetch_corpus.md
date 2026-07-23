# Build a corpus from the OpenAlex API (network call)

Assistive helper that builds a corpus by querying the OpenAlex works API
(`https://api.openalex.org/works?search=...`). This is a network call:
it depends on a live external service whose results change over time, so
it sits outside the package's deterministic core. Each work is mapped to
`{id, title, year, keywords, references}` (keywords falls back to the
top concepts when no keywords are present).

## Usage

``` r
tf_fetch_corpus(query, per_page = 25, mailto = NULL)
```

## Arguments

- query:

  Free-text search query.

- per_page:

  Number of works to request (default `25`).

- mailto:

  Optional contact email for the OpenAlex "polite pool".

## Value

A corpus object (named list) with `schema_version`, `id`, and `records`.

## Examples

``` r
if (FALSE) { # \dontrun{
corpus <- tf_fetch_corpus("panic disorder interoception", mailto = "me@example.org")
} # }
```
