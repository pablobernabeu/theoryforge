# Deposit a theory's audit dossier to OSF storage

Builds (and optionally sends) a request to upload `tf_dossier(theory)`
to OSF storage. With `dry_run = TRUE` (the default) the planned request
is returned and nothing is sent. A live upload (`dry_run = FALSE`)
requires both `token` and `node` (the OSF project id) and performs an
authenticated `PUT`. The live path is network- and credential-dependent.

## Usage

``` r
tf_osf_push(
  theory,
  token = NULL,
  node = NULL,
  filename = NULL,
  dry_run = TRUE,
  base_url = .tf_OSF_BASE
)
```

## Arguments

- theory:

  A theory object (named list), e.g. from
  [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md).

- token:

  OSF personal access token (required when `dry_run = FALSE`).

- node:

  OSF project (node) id; used to build the upload URL and required when
  `dry_run = FALSE`.

- filename:

  Destination filename; defaults to `<id>.dossier.md`.

- dry_run:

  When `TRUE` (default), return the planned request without sending it.

- base_url:

  OSF storage base URL; override to target a non-default host.

## Value

When `dry_run = TRUE`, a list
`list(dry_run = TRUE, request = list(method, url, filename, content_bytes), note)`.
When `dry_run = FALSE`, a list describing the completed upload.

## Examples

``` r
theory <- tf_theory("demo-1", "A demonstration theory")
tf_osf_push(theory)
#> $dry_run
#> [1] TRUE
#> 
#> $request
#> $request$method
#> [1] "PUT"
#> 
#> $request$url
#> NULL
#> 
#> $request$filename
#> [1] "demo-1.dossier.md"
#> 
#> $request$content_bytes
#> [1] 1015
#> 
#> 
#> $note
#> [1] "set dry_run=FALSE with a valid token and node to perform the upload"
#> 
tf_osf_push(theory, node = "abc12")$request$url
#> [1] "https://files.osf.io/v1/resources/abc12/providers/osfstorage/?kind=file&name=demo-1.dossier.md"
```
