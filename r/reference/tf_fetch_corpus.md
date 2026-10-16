# Build a corpus from the OpenAlex API (network call)

Assistive helper that builds a corpus by querying the OpenAlex works API
(`https://api.openalex.org/works?search=...`). This is a network call:
it depends on a live external service whose results change over time, so
it sits outside the package's deterministic core. Each work is mapped to
`{id, doi, title, year, keywords, references}`, with the DOI as OpenAlex
gives it (keywords falls back to the top concepts when no keywords are
present).

## Usage

``` r
tf_fetch_corpus(
  query,
  per_page = 25,
  mailto = NULL,
  api_key = Sys.getenv("OPENALEX_API_KEY", ""),
  max_records = NULL
)
```

## Arguments

- query:

  Free-text search query.

- per_page:

  Number of works to request in each page (default `25`). It may be 1 to
  200, but OpenAlex supports pages of up to 100 and has deprecated
  larger ones.

- mailto:

  Optional contact email. It is still sent, but OpenAlex now ignores it,
  since API keys replaced the polite pool it once selected.

- api_key:

  An OpenAlex API key, by default the `OPENALEX_API_KEY` environment
  variable. It is sent only in an `Authorization: Bearer` header, never
  in the URL, the corpus or an error message. `""` or `NULL` sends no
  key.

- max_records:

  Number of works to collect, paging as needed. `NULL` (the default)
  means `per_page`, which is one request.

## Value

A corpus object (named list) with `schema_version`, `id`, `source` and
`records`.

## Details

OpenAlex returns the works that match a search in pages of `per_page`,
ranked by relevance, and a search usually matches far more works than
one page holds. A `max_records` above `per_page` pages on through
OpenAlex's cursor until that many works are collected or the results run
out. Each page is one request and costs USD 0.001. OpenAlex allows USD
0.10 a day without a key, about 100 pages, and USD 1 with a free key.
When OpenAlex refuses a request, as it does with HTTP 429 once the
budget is spent, the function stops with the status and OpenAlex's own
message, and the request is not retried.

The corpus records where, when and how it was fetched in `source`. It
gives the service, endpoint and query and the UTC time of retrieval
(`retrieved`), then the number of works that matched (`total_count`),
the number kept (`n_records`), the page size and the order (`sort`). The
date matters because the keywords change. Since late September 2026,
OpenAlex has written each work's keywords with a language model that
reads its title, abstract and venue. It merges and splits that
vocabulary over time. Works without keywords fall back to their
concepts, a deprecated vocabulary with capitalised names that do not
match the lower-case keywords in
[`tf_litmap()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_litmap.md).
Save a fetched corpus and work from the saved file.

## Examples

``` r
if (FALSE) { # \dontrun{
# With OPENALEX_API_KEY set, for example in .Renviron, the key is sent in a
# request header.
corpus <- tf_fetch_corpus("panic disorder interoception",
                          per_page = 100, max_records = 400)
corpus$source
# null = "null" writes a missing DOI or count as null, where jsonlite would
# write an empty object.
path <- tempfile(fileext = ".json")
jsonlite::write_json(corpus, path, auto_unbox = TRUE, null = "null")
corpus <- tf_read_corpus(path)
} # }
```
