#' Read, validate, and write theory objects.
#'
#' @name core
#' @keywords internal
NULL

.tf_MATURITY <- c("draft", "building", "developing", "testing")
.tf_FORM <- c("variance", "network", "typology", "process")
.tf_RELATION <- c("increases", "decreases", "moderates", "mediates", "causes", "associates")
.tf_PRED_TYPE <- c("point", "interval", "directional", "existence")
.tf_FORMAL_MODEL_TYPE <- c("ode", "abm", "network", "sem", "none")
.tf_EVIDENCE_DIRECTION <- c("corroborates", "refutes", "mixed")
# The collections of the schema, in the order tf_validate() reports one that is
# not a list, and the keys of the closed version block.
.tf_COLLECTIONS <- c("constructs", "propositions", "predictions", "auxiliary_assumptions",
                     "alternatives", "evidence", "test_outcomes", "provenance")
.tf_VERSION_KEYS <- c("id", "parent_id", "content_hash")

#' Read a theory object from a YAML or JSON file
#'
#' Reads a theory object authored as YAML (or JSON, chosen by file extension)
#' into a named list.
#'
#' The file is read exactly as the Python twin's \code{theoryforge.read()}
#' reads it (API_SPEC.md section 3). The text is UTF-8, and a byte-order mark
#' is ignored. A YAML or JSON sequence is always a list, even with one element,
#' so \code{maturity: [draft]} is refused by [tf_validate()] as it is in Python.
#' Unquoted \code{y}, \code{Y}, \code{n} and \code{N} stay strings, as do
#' dates, while \code{yes}, \code{no}, \code{true}, \code{false}, \code{on} and
#' \code{off} are logicals. Integers are decimal, octal or hexadecimal only, so
#' \code{1:30} and \code{1_000} are strings, and so is a number written with a
#' comma (\code{1,000}). An integer too large for an R integer is read as a
#' double. A merge key (\code{<<}) lets the mapping's own keys win. A key
#' repeated in any mapping, in YAML or JSON, stops with
#' \code{(<path>) Duplicate map key: '<key>'}.
#'
#' @param path Path to a \code{.yaml}/\code{.yml} or \code{.json} file.
#' @return A named list holding the parsed theory object.
#' @examples
#' # Round-trip a theory through a temporary file.
#' theory <- tf_theory("demo-1", "A demonstration theory")
#' path <- tempfile(fileext = ".yaml")
#' tf_write(theory, path)
#' tf_read(path)
#' @export
tf_read <- function(path) {
  data <- .tf_read_file(path)
  if (!.tf_is_mapping(data)) {
    stop("Theory data must be a mapping", call. = FALSE)
  }
  data
}

#' Validate a theory object
#'
#' Checks a theory against the package's schema, \code{theory.schema.json},
#' without a JSON Schema engine, so that it runs wherever R does, webR
#' included.
#'
#' The default (\code{full = FALSE}) checks structure. It covers the required
#' top-level fields, the \code{maturity} and \code{theory_form} enums, the
#' top-level field names and the required fields and enums of each construct,
#' proposition and prediction. It also checks that every collection is a list.
#' A field that is absent, \code{NULL} or blank is reported as missing, and one
#' that holds another type as such (\code{id must be a string}).
#'
#' With \code{full = TRUE} it also checks that every id is unique within its
#' collection and that every cross-reference (proposition endpoints,
#' prediction derivations and diagnostics, and assumption, evidence and
#' test-outcome targets) points to a declared id. It then checks the rest of
#' the schema. That covers the required fields of assumptions, alternatives,
#' evidence and test outcomes, a logical \code{passed}, the evidence direction
#' and formal-model type enums, the version block and the
#' \code{schema_version} pattern. It also covers numbers within \[0, 1\] where
#' the schema asks for them and the type of every other field and of every
#' entry of a string array.
#'
#' The Python twin's test suite compares the result with a JSON Schema 2020-12
#' validator. Besides the ids and references, which the schema cannot express,
#' the pass is stricter in two ways, since a blank string counts as missing and
#' an entry of a string array must be a nonempty string. It is more lenient in
#' three ways, which API_SPEC.md section 2 documents. A \code{NULL}
#' optional field is absent and a single string stands for a one-element array
#' of strings. An empty \code{list()} stands for an empty mapping as well as an
#' empty sequence. A single \code{NA}, which [tf_write()] writes as null, reads
#' as absent.
#'
#' Both passes are deterministic, and the Python twin's
#' \code{Theory.validate()} reports the same problems in the same order with
#' the same text.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @param full When \code{TRUE}, also check ids, cross-references and the rest
#'   of the schema.
#' @return \code{TRUE} (invisibly) on success; otherwise stops with
#'   \code{"invalid theory object: "} followed by every problem found, joined
#'   by \code{"; "}.
#' @examples
#' theory <- tf_read(system.file("fixtures", "panic-network.theory.yaml",
#'                               package = "theoryforge"))
#' isTRUE(tf_validate(theory))              # required fields and enums
#' isTRUE(tf_validate(theory, full = TRUE)) # also ids, cross-references and the rest of the schema
#'
#' # The failure path is the more informative one. Point a prediction at a
#' # proposition that was never declared.
#' broken <- theory
#' broken$predictions[[1]]$derives_from <- "p_missing"
#' tryCatch(tf_validate(broken, full = TRUE), error = conditionMessage)
#' @export
tf_validate <- function(theory, full = FALSE) {
  d <- theory
  errors <- character(0)

  for (req in c("schema_version", "id", "title", "maturity")) {
    errors <- c(errors, .tf_required_text(.tf_get(d, req),
                                          sprintf("missing/empty required field: %s", req), req))
  }
  # Each enum test asks for a nonempty scalar string before asking about
  # membership. `%in%` coerces its left operand, so a one-element YAML sequence
  # such as `theory_form: [network]` used to match the enum and validate here
  # while the Python twin refused it as a non-string. Requiring the string first
  # keeps the two engines level on input that is mistyped rather than misspelt.
  mat <- .tf_get(d, "maturity")
  if (!(.tf_ne_str(mat) && mat %in% .tf_MATURITY)) {
    errors <- c(errors, sprintf("maturity must be one of %s",
                                paste(sort(.tf_MATURITY), collapse = ", ")))
  }
  if ("theory_form" %in% names(d)) {
    form <- .tf_get(d, "theory_form")
    if (!(.tf_ne_str(form) && form %in% .tf_FORM)) {
      errors <- c(errors, sprintf("theory_form must be one of %s",
                                  paste(sort(.tf_FORM), collapse = ", ")))
    }
  }

  # A misspelt collection key would otherwise pass silently and quietly change
  # every downstream verdict (a renamed `predictions:` drops the whole
  # collection), so unrecognised top-level fields are refused.
  known <- names(.tf_get(tf_theory_schema(), "properties", list()))
  for (key in names(d)) {
    if (!(key %in% known)) {
      errors <- c(errors, sprintf("unknown top-level field: %s", key))
    }
  }
  # A collection that is not a list reads as empty (API_SPEC.md section 3), so
  # the theory would lose it without a word.
  for (key in .tf_COLLECTIONS) {
    if (.tf_not_a_list(.tf_get(d, key))) {
      errors <- c(errors, sprintf("%s must be a list", key))
    }
  }

  cons <- .tf_list(d, "constructs")
  for (i in seq_along(cons)) {
    errors <- c(errors, .tf_required_fields(cons[[i]], sprintf("construct[%d]", i - 1L),
                                            c("id", "label", "definition")))
  }

  props <- .tf_list(d, "propositions")
  for (i in seq_along(props)) {
    p_i <- props[[i]]
    errors <- c(errors, .tf_required_fields(p_i, sprintf("proposition[%d]", i - 1L),
                                            c("id", "from", "to", "relation")))
    rel <- .tf_get(p_i, "relation")
    if (.tf_ne_str(rel) && !(rel %in% .tf_RELATION)) {
      errors <- c(errors, sprintf("proposition[%d] relation '%s' not allowed", i - 1L, rel))
    }
  }

  preds <- .tf_list(d, "predictions")
  for (i in seq_along(preds)) {
    p_i <- preds[[i]]
    errors <- c(errors, .tf_required_fields(p_i, sprintf("prediction[%d]", i - 1L),
                                            c("id", "statement", "type")))
    ty <- .tf_get(p_i, "type")
    if (.tf_ne_str(ty) && !(ty %in% .tf_PRED_TYPE)) {
      errors <- c(errors, sprintf("prediction[%d] type '%s' not allowed", i - 1L, ty))
    }
  }

  # The full pass, items 1 to 14 of API_SPEC.md section 2. The Python twin's
  # Theory._full_errors makes the same checks in the same order with the same
  # message text.
  if (isTRUE(full)) {
    alts <- .tf_list(d, "alternatives")
    auxs <- .tf_list(d, "auxiliary_assumptions")
    evs <- .tf_list(d, "evidence")
    tos <- .tf_list(d, "test_outcomes")
    ids_of <- function(items) {
      out <- character(0)
      for (it in items) if (.tf_ne_str(.tf_get(it, "id"))) out <- c(out, .tf_str(it, "id"))
      out
    }
    construct_ids <- ids_of(cons)
    proposition_ids <- ids_of(props)
    prediction_ids <- ids_of(preds)
    alternative_ids <- ids_of(alts)
    dups <- function(items, kind) {
      seen <- character(0)
      for (it in items) {
        if (.tf_ne_str(.tf_get(it, "id"))) {
          i <- .tf_str(it, "id")
          if (i %in% seen) errors <<- c(errors, sprintf("duplicate %s id: %s", kind, i))
          seen <- c(seen, i)
        }
      }
    }
    dups(cons, "construct"); dups(props, "proposition"); dups(preds, "prediction")
    dups(alts, "alternative"); dups(auxs, "assumption")
    for (i in seq_along(props)) {
      if (.tf_ne_str(.tf_get(props[[i]], "from"))) {
        frm <- .tf_str(props[[i]], "from")
        if (!(frm %in% construct_ids))
          errors <- c(errors, sprintf("proposition[%d] from '%s' is not a known construct", i - 1L, frm))
      }
      if (.tf_ne_str(.tf_get(props[[i]], "to"))) {
        to <- .tf_str(props[[i]], "to")
        if (!(to %in% construct_ids))
          errors <- c(errors, sprintf("proposition[%d] to '%s' is not a known construct", i - 1L, to))
      }
    }
    # Items 3 and 4: each entry of a referencing array is either a nonempty
    # string to look up or a problem in its own right (item 10).
    for (i in seq_along(preds)) {
      errors <- c(errors,
                  .tf_string_array(.tf_get(preds[[i]], "derives_from"),
                                   sprintf("prediction[%d] derives_from", i - 1L),
                                   proposition_ids, "proposition"),
                  .tf_string_array(.tf_get(preds[[i]], "diagnostic_vs"),
                                   sprintf("prediction[%d] diagnostic_vs", i - 1L),
                                   alternative_ids, "alternative"))
    }
    for (i in seq_along(auxs)) {
      errors <- c(errors, .tf_string_array(.tf_get(auxs[[i]], "protects"),
                                           sprintf("assumption[%d] protects", i - 1L),
                                           prediction_ids, "prediction"))
    }
    for (i in seq_along(tos)) {
      if (.tf_ne_str(.tf_get(tos[[i]], "prediction_id"))) {
        pid <- .tf_str(tos[[i]], "prediction_id")
        if (!(pid %in% prediction_ids))
          errors <- c(errors, sprintf("test_outcome[%d] prediction_id '%s' is not a known prediction", i - 1L, pid))
      }
    }
    for (i in seq_along(evs)) {
      if (.tf_ne_str(.tf_get(evs[[i]], "supports"))) {
        s <- .tf_str(evs[[i]], "supports")
        if (!(s %in% prediction_ids))
          errors <- c(errors, sprintf("evidence[%d] supports '%s' is not a known prediction", i - 1L, s))
      }
    }
    # The schema types prediction severity as a number in [0, 1]; enforced here
    # so a file cannot pass full validation and then be refused by the scorer,
    # which rejects non-numeric severities.
    for (i in seq_along(preds)) {
      s <- .tf_get(preds[[i]], "severity")
      if (is.null(s)) next
      if (!is.numeric(s) || length(s) != 1L || is.na(s) || s < 0 || s > 1) {
        errors <- c(errors,
                    sprintf("prediction[%d] severity must be a number between 0 and 1", i - 1L))
      }
    }

    # 8: the required fields of the other collections. A quoted "true" in passed
    # read as a failure and turned a progressive amendment into a degenerating
    # one, so passed must be a logical.
    for (i in seq_along(auxs)) {
      errors <- c(errors, .tf_required_fields(auxs[[i]], sprintf("assumption[%d]", i - 1L),
                                              c("id", "statement")))
    }
    for (i in seq_along(alts)) {
      errors <- c(errors, .tf_required_fields(alts[[i]], sprintf("alternative[%d]", i - 1L),
                                              c("id", "label")))
    }
    for (i in seq_along(evs)) {
      errors <- c(errors, .tf_required_fields(evs[[i]], sprintf("evidence[%d]", i - 1L),
                                              c("supports", "direction")))
      direction <- .tf_get(evs[[i]], "direction")
      if (.tf_ne_str(direction) && !(direction %in% .tf_EVIDENCE_DIRECTION)) {
        errors <- c(errors, sprintf("evidence[%d] direction '%s' not allowed", i - 1L, direction))
      }
    }
    for (i in seq_along(tos)) {
      errors <- c(errors, .tf_required_fields(tos[[i]], sprintf("test_outcome[%d]", i - 1L),
                                              "prediction_id"))
      passed <- .tf_get(tos[[i]], "passed")
      if (!(is.logical(passed) && length(passed) == 1L && !is.na(passed))) {
        errors <- c(errors, sprintf("test_outcome[%d] passed must be true or false", i - 1L))
      }
    }

    # 9: typed optional fields of assumptions and test outcomes.
    for (i in seq_along(auxs)) {
      errors <- c(errors, .tf_optional_text(.tf_get(auxs[[i]], "added_for"),
                                            sprintf("assumption[%d] added_for", i - 1L),
                                            nullable = TRUE))
    }
    for (i in seq_along(tos)) {
      t_i <- tos[[i]]
      prefix <- sprintf("test_outcome[%d]", i - 1L)
      errors <- c(errors,
                  .tf_unit_number(.tf_get(t_i, "severity_at_test"), paste(prefix, "severity_at_test")),
                  .tf_optional_text(.tf_get(t_i, "registered"), paste(prefix, "registered"),
                                    nullable = TRUE),
                  .tf_optional_text(.tf_get(t_i, "date"), paste(prefix, "date"), nullable = TRUE))
    }

    # 11: the formal model. A type outside the enum earned the formalisation
    # point in 0.6.0, and reads as absent since (API_SPEC.md section 3).
    fm <- .tf_get(d, "formal_model")
    if (!.tf_absent(fm) && .tf_not_a_mapping(fm)) {
      errors <- c(errors, "formal_model must be a mapping")
    } else if (is.list(fm)) {
      ty <- .tf_get(fm, "type")
      if (!.tf_absent(ty) && !.tf_is_string(ty)) {
        errors <- c(errors, .tf_not_string("formal_model type", ty))
      } else if (!.tf_absent(ty) && !(ty %in% .tf_FORMAL_MODEL_TYPE)) {
        errors <- c(errors, sprintf("formal_model type '%s' not allowed", ty))
      }
      errors <- c(errors, .tf_optional_text(.tf_get(fm, "spec_ref"), "formal_model spec_ref",
                                            nullable = TRUE))
    }

    # 12: the version block, which the schema closes.
    ver <- .tf_get(d, "version")
    if (!.tf_absent(ver) && .tf_not_a_mapping(ver)) {
      errors <- c(errors, "version must be a mapping")
    } else if (is.list(ver)) {
      for (key in names(ver)) {
        if (!(key %in% .tf_VERSION_KEYS)) {
          errors <- c(errors, sprintf("version has unknown field: %s", key))
        }
      }
      errors <- c(errors,
                  .tf_optional_text(.tf_get(ver, "id"), "version id"),
                  .tf_optional_text(.tf_get(ver, "parent_id"), "version parent_id",
                                    nullable = TRUE),
                  .tf_optional_text(.tf_get(ver, "content_hash"), "version content_hash",
                                    nullable = TRUE))
    }

    # 13: the schema_version pattern. The default regex engine's "$" matches
    # only at the end of the string, as Python's fullmatch() does.
    sv <- .tf_get(d, "schema_version")
    if (.tf_ne_str(sv) && !grepl("^[0-9]+\\.[0-9]+$", sv)) {
      errors <- c(errors, 'schema_version must match major.minor (for example "1.0")')
    }

    # 14: the schema's remaining types, collection by collection in the schema's
    # order.
    for (i in seq_along(cons)) {
      prefix <- sprintf("construct[%d]", i - 1L)
      errors <- c(errors,
                  .tf_string_array(.tf_get(cons[[i]], "measurement"), paste(prefix, "measurement")),
                  .tf_string_array(.tf_get(cons[[i]], "boundary_conditions"),
                                   paste(prefix, "boundary_conditions")))
    }
    for (i in seq_along(props)) {
      prefix <- sprintf("proposition[%d]", i - 1L)
      errors <- c(errors,
                  .tf_optional_text(.tf_get(props[[i]], "mechanism"), paste(prefix, "mechanism")),
                  .tf_optional_text(.tf_get(props[[i]], "functional_form"),
                                    paste(prefix, "functional_form")))
    }
    errors <- c(errors, .tf_string_array(.tf_get(d, "boundary_conditions"), "boundary_conditions"))
    for (i in seq_along(preds)) {
      errors <- c(errors, .tf_unit_number(.tf_get(preds[[i]], "risk_score"),
                                          sprintf("prediction[%d] risk_score", i - 1L)))
    }
    for (i in seq_along(evs)) {
      errors <- c(errors, .tf_optional_text(.tf_get(evs[[i]], "source_doi"),
                                            sprintf("evidence[%d] source_doi", i - 1L),
                                            nullable = TRUE))
    }
    for (i in seq_along(tos)) {
      errors <- c(errors, .tf_optional_text(.tf_get(tos[[i]], "observed"),
                                            sprintf("test_outcome[%d] observed", i - 1L)))
    }
    for (i in seq_along(alts)) {
      prefix <- sprintf("alternative[%d]", i - 1L)
      errors <- c(errors,
                  .tf_string_array(.tf_get(alts[[i]], "key_constructs"),
                                   paste(prefix, "key_constructs")),
                  .tf_optional_text(.tf_get(alts[[i]], "source_doi"), paste(prefix, "source_doi"),
                                    nullable = TRUE))
    }
    steps <- .tf_list(d, "provenance")
    for (i in seq_along(steps)) {
      prefix <- sprintf("provenance[%d]", i - 1L)
      if (.tf_not_a_mapping(steps[[i]])) {
        errors <- c(errors, paste(prefix, "must be a mapping"))
        next
      }
      for (name in c("step", "action", "detail")) {
        errors <- c(errors, .tf_optional_text(.tf_get(steps[[i]], name), paste(prefix, name)))
      }
    }
  }

  if (length(errors) > 0L) {
    stop("invalid theory object: ", paste(errors, collapse = "; "), call. = FALSE)
  }
  invisible(TRUE)
}

# -- validation helpers (API_SPEC.md section 2) ------------------------------
#
# Each returns the messages for one value, so that tf_validate() lists them in
# the contract's order. The Python twin's core.py holds the same helpers
# (_required_text and the rest) with the same messages.

# The message for a present value that should be a string. YAML reads an
# unquoted 1.0, 2026 or Yes as a number or a logical, so for those the message
# says how to keep the value a string.
.tf_not_string <- function(name, v) {
  hint <- if ((is.numeric(v) || is.logical(v)) && length(v) == 1L) {
    " (quote the value in YAML)"
  } else {
    ""
  }
  paste0(name, " must be a string", hint)
}

# A required text field: `missing` when it is absent, NULL or blank.
.tf_required_text <- function(v, missing, name) {
  if (.tf_absent(v) || (.tf_is_string(v) && !nzchar(.tf_trim(v)))) return(missing)
  if (!.tf_is_string(v)) return(.tf_not_string(name, v))
  character(0)
}

.tf_required_fields <- function(item, prefix, names) {
  out <- character(0)
  for (name in names) {
    out <- c(out, .tf_required_text(.tf_get(item, name),
                                    sprintf("%s missing/empty %s", prefix, name),
                                    paste(prefix, name)))
  }
  out
}

# A field the schema types as a string, or with `nullable` as a string or null.
# An absent or NULL optional field is never reported, since R holds the two
# alike.
.tf_optional_text <- function(v, name, nullable = FALSE) {
  if (.tf_absent(v) || .tf_is_string(v)) return(character(0))
  if (nullable) paste(name, "must be a string or null") else .tf_not_string(name, v)
}

.tf_unit_number <- function(v, name) {
  if (.tf_absent(v) || (is.numeric(v) && length(v) == 1L && !is.na(v) && v >= 0 && v <= 1)) {
    return(character(0))
  }
  paste(name, "must be a number between 0 and 1")
}

# Whether a present value cannot be read as a sequence: a scalar or a non-empty
# mapping. An empty mapping holds nothing to lose, and list() stands for both
# kinds of empty value, so neither twin reports one. A vector of two or more
# values, which only a theory built in memory holds, is a sequence, as
# .tf_list() reads it.
.tf_not_a_list <- function(v) {
  if (is.list(v)) return(length(v) > 0L && .tf_is_mapping(v))
  length(v) == 1L && !.tf_absent(v)
}

# Whether a value cannot be read as a mapping: NULL, a scalar or a non-empty
# sequence. The callers rule out an absent top-level field first.
.tf_not_a_mapping <- function(v) {
  if (is.list(v)) return(length(v) > 0L && !.tf_is_mapping(v))
  is.null(v) || length(v) > 0L
}

# A field the schema types as an array of strings. Each entry must be a nonempty
# string, as the readers ignore any other (API_SPEC.md section 4). A nonempty
# string is a one-element array, and any other value that is not a list, a
# blank string included, cannot be read as an array. With `known`, each
# nonempty entry is also looked up there, in entry order, and `kind` names what
# it should refer to.
.tf_string_array <- function(v, name, known = NULL, kind = "") {
  if (is.list(v)) {
    if (length(v) == 0L) return(character(0))
    if (.tf_is_mapping(v)) return(paste(name, "must be a list"))
    entries <- v
  } else if (length(v) == 0L || .tf_absent(v)) {
    return(character(0))
  } else if (length(v) == 1L) {
    if (!.tf_ne_str(v)) return(paste(name, "must be a list"))
    entries <- list(v)
  } else {
    entries <- as.list(v)
  }
  out <- character(0)
  for (k in seq_along(entries)) {
    entry <- entries[[k]]
    if (!.tf_ne_str(entry)) {
      out <- c(out, sprintf("%s entry %d must be a nonempty string", name, k - 1L))
    } else if (!is.null(known) && !(entry %in% known)) {
      out <- c(out, sprintf("%s '%s' is not a known %s", name, entry, kind))
    }
  }
  out
}

#' Write a theory object to YAML or JSON
#'
#' Serialises a theory object to disk. The format is chosen by the file
#' extension (\code{.json} -> JSON, otherwise YAML). Files are UTF-8 with LF
#' line endings.
#'
#' Numbers keep 15 significant digits in both formats, logicals are written as
#' \code{true} and \code{false}, and a missing value (\code{NA}) is written as
#' null, which reads back as \code{NULL} in R and \code{None} in Python. Every
#' field the schema types as an array of strings (\code{derives_from},
#' \code{diagnostic_vs}, \code{protects}, \code{measurement},
#' \code{boundary_conditions}, \code{key_constructs}) is written as an array,
#' even when the theory holds it as a single string. A written theory therefore
#' validates against the package's own schema and reads back the same in R and
#' in Python (API_SPEC.md section 3).
#'
#' @param theory A theory object (named list).
#' @param path Destination path.
#' @return The \code{path} (invisibly).
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory")
#' tf_write(theory, tempfile(fileext = ".yaml"))
#' @export
tf_write <- function(theory, path) {
  theory <- .tf_na_as_null(.tf_box_string_arrays(theory))
  ext <- tolower(tools::file_ext(path))
  if (identical(ext, "json")) {
    # digits = NA keeps 15 significant digits. jsonlite's default rounds to four
    # decimal places, which turned a severity of 0.49996 into 0.5.
    text <- jsonlite::toJSON(theory, pretty = TRUE, auto_unbox = TRUE, null = "null", digits = NA)
    text <- paste0(as.character(text), "\n")
  } else {
    # yaml's default writes doubles to seven decimal places and a logical as yes
    # or no. .tf_yaml_double keeps 15 significant digits, and verbatim_logical
    # writes true and false.
    text <- yaml::as.yaml(theory, handlers = list(logical = yaml::verbatim_logical,
                                                  numeric = .tf_yaml_double))
  }
  .tf_write_lf(path, text)
}

# -- builder (BUILDING mode) -------------------------------------------------

# Append one provenance entry {step, action, detail} (API_SPEC.md section 8).
# step = str(new length of provenance), 1-based.
.tf_provenance_append <- function(theory, action, detail) {
  prov <- .tf_as_list(theory, "provenance")
  step <- as.character(length(prov) + 1L)
  prov[[length(prov) + 1L]] <- list(step = step, action = action, detail = detail)
  theory$provenance <- prov
  theory
}

# Append `item` to the named collection (creating it lazily) and return theory.
.tf_coll_append <- function(theory, key, item) {
  coll <- .tf_as_list(theory, key)
  coll[[length(coll) + 1L]] <- item
  theory[[key]] <- coll
  theory
}

#' Start a new, empty theory object (BUILDING mode entry point)
#'
#' Seeds \code{schema_version = "1.0"} and a first provenance entry
#' \code{{step:"1", action:"tf_theory", detail:<id>}}.
#'
#' @param id Theory id.
#' @param title Human-readable title.
#' @param maturity Maturity stage (default \code{"building"}).
#' @param theory_form Theory form (default \code{"network"}).
#' @return A theory object (named list).
#' @examples
#' tf_theory("demo-1", "A demonstration theory")
#' @export
tf_theory <- function(id, title, maturity = "building", theory_form = "network") {
  theory <- list(
    schema_version = "1.0",
    id = id,
    title = title,
    maturity = maturity,
    theory_form = theory_form
  )
  .tf_provenance_append(theory, "tf_theory", id)
}

#' Add a construct to a theory (BUILDING mode)
#'
#' Appends a construct and a provenance entry, returning the mutated theory.
#'
#' @param theory A theory object (named list).
#' @param id,label,definition Construct fields.
#' @param measurement,boundary_conditions Optional character vectors.
#' @return The (mutated) theory object.
#' @examples
#' tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Physiological arousal",
#'                    "Bodily activation in response to a stressor.")
#' @export
tf_add_construct <- function(theory, id, label, definition,
                             measurement = NULL, boundary_conditions = NULL) {
  c_item <- list(id = id, label = label, definition = definition)
  if (!is.null(measurement)) c_item$measurement <- as.list(measurement)
  if (!is.null(boundary_conditions)) c_item$boundary_conditions <- as.list(boundary_conditions)
  theory <- .tf_coll_append(theory, "constructs", c_item)
  .tf_provenance_append(theory, "tf_add_construct", id)
}

#' Add a proposition to a theory (BUILDING mode)
#'
#' @param theory A theory object (named list).
#' @param id,from,to,relation Proposition fields. \code{from} is the source
#'   construct id (named \code{from} to match the schema field).
#' @param mechanism Optional mechanism string.
#' @return The (mutated) theory object.
#' @examples
#' tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
#'   tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
#'   tf_add_proposition("p1", "c_arousal", "c_threat", "increases")
#' @export
tf_add_proposition <- function(theory, id, from, to, relation, mechanism = NULL) {
  p_item <- list(id = id, from = from, to = to, relation = relation)
  if (!is.null(mechanism)) p_item$mechanism <- mechanism
  theory <- .tf_coll_append(theory, "propositions", p_item)
  .tf_provenance_append(theory, "tf_add_proposition", id)
}

#' Add a prediction to a theory (BUILDING mode)
#'
#' Appends a prediction and a provenance entry, returning the mutated theory.
#'
#' @param theory A theory object (named list).
#' @param id The prediction's identifier.
#' @param statement The claim in words.
#' @param type The form of the claim, one of four. \code{"existence"} asserts
#'   that an effect or relation exists, without a direction.
#'   \code{"directional"} asserts a sign or an order, including comparisons,
#'   interactions, the invariance of a direction across groups and claims that
#'   an effect occurs only when a condition holds. \code{"interval"} asserts
#'   that a quantity lies in a stated range, the range the theory permits.
#'   \code{"point"} asserts one value, with the tolerance that measurement
#'   requires. That width is measurement tolerance, not latitude the theory
#'   allows. The label is self-declared, and no function checks it against the
#'   statement.
#' @param derives_from,diagnostic_vs Optional character vectors.
#' @param severity Optional declared pre-data severity from 0 to 1, stored only
#'   when given. The checklist's risk_severity item reads it, and reads the
#'   claim-form rubric's value ([tf_severity()]) for a prediction that declares
#'   none. [tf_dossier()] sets the two side by side.
#' @return The (mutated) theory object.
#' @examples
#' tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_prediction("h1", "Arousal precedes threat appraisal.", "directional")
#' @export
tf_add_prediction <- function(theory, id, statement, type,
                              derives_from = NULL, diagnostic_vs = NULL,
                              severity = NULL) {
  p_item <- list(id = id, statement = statement, type = type)
  if (!is.null(derives_from)) p_item$derives_from <- as.list(derives_from)
  if (!is.null(diagnostic_vs)) p_item$diagnostic_vs <- as.list(diagnostic_vs)
  if (!is.null(severity)) p_item$severity <- severity
  theory <- .tf_coll_append(theory, "predictions", p_item)
  .tf_provenance_append(theory, "tf_add_prediction", id)
}

#' Add an alternative theory (BUILDING mode)
#'
#' @param theory A theory object (named list).
#' @param id,label Alternative fields.
#' @param key_constructs Optional character vector.
#' @return The (mutated) theory object.
#' @examples
#' tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_alternative("alt1", "Cognitive appraisal account",
#'                      key_constructs = c("c_threat"))
#' @export
tf_add_alternative <- function(theory, id, label, key_constructs = NULL) {
  a_item <- list(id = id, label = label)
  if (!is.null(key_constructs)) a_item$key_constructs <- as.list(key_constructs)
  theory <- .tf_coll_append(theory, "alternatives", a_item)
  .tf_provenance_append(theory, "tf_add_alternative", id)
}

#' Add an auxiliary assumption (BUILDING mode)
#'
#' @param theory A theory object (named list).
#' @param id,statement Assumption fields.
#' @param added_for Optional id of the prediction whose anomaly the assumption
#'   was added to answer. Leave it \code{NULL} for a core assumption.
#'   [tf_appraise_amendment()] counts an assumption added for an anomaly as ad
#'   hoc unless a prediction it protects that is new in the amended version,
#'   other than this one, is corroborated.
#' @param protects Optional character vector of the ids of the predictions the
#'   assumption shields from refutation.
#' @return The (mutated) theory object.
#' @examples
#' tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_assumption("a1", "Measurement error is negligible.")
#' @export
tf_add_assumption <- function(theory, id, statement, added_for = NULL, protects = NULL) {
  a_item <- list(id = id, statement = statement, added_for = added_for)
  if (!is.null(protects)) a_item$protects <- as.list(protects)
  theory <- .tf_coll_append(theory, "auxiliary_assumptions", a_item)
  .tf_provenance_append(theory, "tf_add_assumption", id)
}

#' Set the formal model (BUILDING mode)
#'
#' @param theory A theory object (named list).
#' @param type Formal-model type (e.g. \code{"ode"}).
#' @param spec_ref Optional reference to the model specification.
#' @return The (mutated) theory object.
#' @examples
#' tf_theory("demo-1", "A demonstration theory") |>
#'   tf_set_formal_model("ode", spec_ref = "models/panic.ode")
#' @export
tf_set_formal_model <- function(theory, type, spec_ref = NULL) {
  theory$formal_model <- list(type = type, spec_ref = spec_ref)
  .tf_provenance_append(theory, "tf_set_formal_model", type)
}
