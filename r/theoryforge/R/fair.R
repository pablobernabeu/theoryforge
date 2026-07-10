#' Archive-ready export of a theory as a reusable digital object.
#'
#' Renders a deterministic bundle (README, citation metadata, deposition
#' metadata, audit dossier) from the schema-validated theory object. The four
#' rendered files are byte-identical across languages and parity-tested;
#' writing them to disk is the only I/O and happens only when a path is given.
#' See API_SPEC.md Part F.
#' @name fair
#' @keywords internal
NULL

# Minimal JSON string escape (backslash then quote), mirrored in Python.
.tf_js <- function(s) {
  s <- if (is.null(s)) "" else as.character(s)
  gsub('"', '\\\\"', gsub("\\\\", "\\\\\\\\", s))
}

# Normalised DOIs cited by the theory's evidence and alternatives, deduplicated
# and sorted by normalised form (the API_SPEC.md section 18 normalisation).
.tf_cited_dois <- function(theory) {
  seen <- character(0)
  for (coll in c("evidence", "alternatives")) {
    for (e in .tf_list(theory, coll)) {
      doi <- .tf_get(e, "source_doi")
      if (!is.null(doi) && is.character(doi) && nzchar(trimws(doi))) {
        seen <- c(seen, .tf_normalize_doi(doi))
      }
    }
  }
  sort(unique(seen), method = "radix")
}

.tf_fair_readme <- function(theory, rep, version, license) {
  lines <- c(
    sprintf("# %s", .tf_str(theory, "title")),
    "",
    sprintf("- Theory ID: %s", .tf_str(theory, "id")),
    sprintf("- Version: %s", version),
    sprintf("- Maturity: %s", .tf_str(theory, "maturity")),
    sprintf("- Aggregate rigour score: %s/100 (gate: %s)",
            .tf_fmt(rep$aggregate_score), rep$gate),
    sprintf("- Licence: %s", license),
    "",
    "## Constructs",
    ""
  )
  cons <- .tf_list(theory, "constructs")
  if (length(cons) > 0L) {
    for (c in cons) {
      lines <- c(lines, sprintf("- %s: %s", .tf_str(c, "id"), .tf_str(c, "label")))
    }
  } else {
    lines <- c(lines, "_No constructs declared._")
  }
  lines <- c(
    lines,
    "",
    "## Contents",
    "",
    "- `theory.yaml` \u2014 the machine-checkable theory object (theoryforge schema)",
    "- `dossier.md` \u2014 the audit dossier (rigour report, severity, provenance, preregistration)",
    "- `CITATION.cff` \u2014 citation metadata",
    "- `metadata.json` \u2014 deposition metadata for general-purpose archives",
    "",
    "## Reuse",
    "",
    "Validate, score, diagram, simulate or amend this theory with the theoryforge",
    "R or Python package: https://github.com/pablobernabeu/theoryforge"
  )
  paste0(paste(lines, collapse = "\n"), "\n")
}

.tf_fair_cff <- function(theory, version, license, keywords, authors) {
  lines <- c(
    "cff-version: 1.2.0",
    "message: If you use this theory, please cite it.",
    "type: dataset",
    sprintf("title: %s", .tf_str(theory, "title")),
    sprintf("version: %s", version),
    sprintf("license: %s", license),
    "keywords:"
  )
  for (k in keywords) lines <- c(lines, sprintf("  - %s", k))
  if (length(authors) > 0L) {
    lines <- c(lines, "authors:")
    for (a in authors) lines <- c(lines, sprintf("  - name: %s", a))
  } else {
    lines <- c(lines, "authors: []")
  }
  paste0(paste(lines, collapse = "\n"), "\n")
}

.tf_fair_metadata <- function(theory, version, license, keywords, authors) {
  title <- .tf_js(.tf_str(theory, "title"))
  desc <- .tf_js(sprintf(
    "%s \u2014 a machine-checkable scientific theory object (id: %s, maturity: %s).",
    .tf_str(theory, "title"), .tf_str(theory, "id"), .tf_str(theory, "maturity")))
  kw <- paste(vapply(keywords, function(k) sprintf('"%s"', .tf_js(k)), character(1)),
              collapse = ", ")
  lines <- c(
    "{",
    sprintf('  "title": "%s",', title),
    '  "upload_type": "dataset",',
    sprintf('  "description": "%s",', desc),
    sprintf('  "version": "%s",', .tf_js(version)),
    sprintf('  "license": "%s",', .tf_js(license)),
    sprintf('  "keywords": [%s],', kw)
  )
  if (length(authors) > 0L) {
    lines <- c(lines, '  "creators": [')
    for (i in seq_along(authors)) {
      comma <- if (i < length(authors)) "," else ""
      lines <- c(lines, sprintf('    {"name": "%s"}%s', .tf_js(authors[[i]]), comma))
    }
    lines <- c(lines, "  ],")
  } else {
    lines <- c(lines, '  "creators": [],')
  }
  dois <- .tf_cited_dois(theory)
  if (length(dois) > 0L) {
    lines <- c(lines, '  "related_identifiers": [')
    for (i in seq_along(dois)) {
      comma <- if (i < length(dois)) "," else ""
      lines <- c(lines, sprintf('    {"relation": "cites", "identifier": "%s"}%s',
                                .tf_js(dois[[i]]), comma))
    }
    lines <- c(lines, "  ]")
  } else {
    lines <- c(lines, '  "related_identifiers": []')
  }
  lines <- c(lines, "}")
  paste0(paste(lines, collapse = "\n"), "\n")
}

#' Export a theory as an archive-ready, citable bundle
#'
#' Renders the four files a general-purpose archive (for example Zenodo or OSF)
#' needs to make a theory findable, citable and reusable: a \code{README.md}
#' summarising the theory and its rigour standing, \code{CITATION.cff} citation
#' metadata, \code{metadata.json} deposition metadata (including
#' \code{related_identifiers} for every DOI the theory's evidence and
#' alternatives cite), and the audit \code{dossier.md}. The rendered contents
#' are deterministic and byte-identical to the Python
#' \code{theory.fair_export()}; when \code{path} is given the files are also
#' written there, together with \code{theory.yaml} (a language-native
#' serialisation of the theory, excluded from cross-language parity). See
#' API_SPEC.md Part F.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @param path Optional directory to write the bundle to (created if needed).
#' @param authors Optional character vector of "Family, Given" (or entity) name
#'   strings for the citation and deposition metadata.
#' @param license Licence identifier recorded in the bundle (default
#'   \code{"CC-BY-4.0"}).
#' @param keywords Optional character vector of keywords; defaults to
#'   \code{c("scientific-theory", "theoryforge", <theory id>)}.
#' @return A named list mapping \code{README.md}, \code{CITATION.cff},
#'   \code{metadata.json} and \code{dossier.md} to their rendered contents.
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.")
#' bundle <- tf_fair_export(theory, authors = "Doe, Jane")
#' cat(bundle[["CITATION.cff"]])
#' @export
tf_fair_export <- function(theory, path = NULL, authors = NULL,
                           license = "CC-BY-4.0", keywords = NULL) {
  authors <- if (is.null(authors)) character(0) else as.character(authors)
  kws <- if (is.null(keywords)) {
    c("scientific-theory", "theoryforge", .tf_str(theory, "id"))
  } else {
    as.character(keywords)
  }
  v <- .tf_get(theory, "version")
  version <- if (is.list(v)) .tf_str(v, "id") else ""
  version <- if (nzchar(trimws(version))) version else "unversioned"
  rep <- tf_check(theory)

  files <- list(
    "README.md" = .tf_fair_readme(theory, rep, version, license),
    "CITATION.cff" = .tf_fair_cff(theory, version, license, kws, authors),
    "metadata.json" = .tf_fair_metadata(theory, version, license, kws, authors),
    "dossier.md" = tf_dossier(theory)
  )

  if (!is.null(path)) {
    if (!dir.exists(path)) dir.create(path, recursive = TRUE)
    for (name in names(files)) {
      con <- file(file.path(path, name), open = "wb")
      writeBin(charToRaw(enc2utf8(files[[name]])), con)
      close(con)
    }
    tf_write(theory, file.path(path, "theory.yaml"))
  }
  files
}
