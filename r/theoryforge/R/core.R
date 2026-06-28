#' Read, validate, and write theory objects.
#'
#' @name core
#' @keywords internal
NULL

.tf_MATURITY <- c("draft", "building", "developing", "testing")
.tf_FORM <- c("variance", "network", "typology", "process")
.tf_RELATION <- c("increases", "decreases", "moderates", "mediates", "causes", "associates")
.tf_PRED_TYPE <- c("point", "interval", "directional", "existence")

#' Read a theory object from a YAML or JSON file
#'
#' Reads a theory object authored as YAML (or JSON, chosen by file extension)
#' into a named list. Mirrors the Python \code{theoryforge.read(path)}.
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
  ext <- tolower(tools::file_ext(path))
  if (identical(ext, "json")) {
    text <- readChar(path, file.info(path)$size, useBytes = TRUE)
    data <- jsonlite::fromJSON(text, simplifyVector = FALSE)
  } else {
    data <- yaml::read_yaml(path)
  }
  if (!is.list(data)) {
    stop("Theory data must be a mapping", call. = FALSE)
  }
  data
}

#' Validate a theory object
#'
#' Built-in validation mirroring the Python \code{Theory.validate}. The default
#' (\code{full = FALSE}) checks required fields and enum membership. With
#' \code{full = TRUE} it additionally checks referential integrity: that every id
#' is unique within its collection and that every cross-reference (proposition
#' endpoints, prediction derivations and diagnostics, and assumption, evidence and
#' test-outcome targets) points to a declared id. The \code{full} checks are
#' deterministic and identical to the Python \code{theory.validate(full=True)}.
#' See API_SPEC.md section 2.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @param full When \code{TRUE}, also run the referential-integrity checks.
#' @return \code{TRUE} (invisibly) on success; otherwise stops with a message
#'   listing every problem found.
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory")
#' tf_validate(theory)
#' tf_validate(theory, full = TRUE)
#' @export
tf_validate <- function(theory, full = FALSE) {
  d <- theory
  errors <- character(0)

  for (req in c("schema_version", "id", "title", "maturity")) {
    if (!.tf_ne_str(.tf_get(d, req))) {
      errors <- c(errors, sprintf("missing/empty required field: %s", req))
    }
  }
  mat <- .tf_get(d, "maturity")
  if (is.null(mat) || !(length(mat) == 1L && mat %in% .tf_MATURITY)) {
    errors <- c(errors, sprintf("maturity must be one of %s",
                                paste(sort(.tf_MATURITY), collapse = ", ")))
  }
  if ("theory_form" %in% names(d)) {
    tf <- .tf_get(d, "theory_form")
    if (!(length(tf) == 1L && tf %in% .tf_FORM)) {
      errors <- c(errors, sprintf("theory_form must be one of %s",
                                  paste(sort(.tf_FORM), collapse = ", ")))
    }
  }

  cons <- .tf_list(d, "constructs")
  for (i in seq_along(cons)) {
    c_i <- cons[[i]]
    for (req in c("id", "label", "definition")) {
      if (!.tf_ne_str(.tf_get(c_i, req))) {
        errors <- c(errors, sprintf("construct[%d] missing/empty %s", i - 1L, req))
      }
    }
  }

  props <- .tf_list(d, "propositions")
  for (i in seq_along(props)) {
    p_i <- props[[i]]
    for (req in c("id", "from", "to", "relation")) {
      if (!.tf_ne_str(.tf_get(p_i, req))) {
        errors <- c(errors, sprintf("proposition[%d] missing/empty %s", i - 1L, req))
      }
    }
    rel <- .tf_get(p_i, "relation")
    if (!(length(rel) == 1L && rel %in% .tf_RELATION) && .tf_ne_str(rel)) {
      errors <- c(errors, sprintf("proposition[%d] relation '%s' not allowed", i - 1L, rel))
    }
  }

  preds <- .tf_list(d, "predictions")
  for (i in seq_along(preds)) {
    p_i <- preds[[i]]
    for (req in c("id", "statement", "type")) {
      if (!.tf_ne_str(.tf_get(p_i, req))) {
        errors <- c(errors, sprintf("prediction[%d] missing/empty %s", i - 1L, req))
      }
    }
    ty <- .tf_get(p_i, "type")
    if (!(length(ty) == 1L && ty %in% .tf_PRED_TYPE) && .tf_ne_str(ty)) {
      errors <- c(errors, sprintf("prediction[%d] type '%s' not allowed", i - 1L, ty))
    }
  }

  # Referential-integrity checks (opt-in). Deterministic and mirrored byte-for-byte
  # by the Python Theory._referential_errors: same checks, order and message text.
  if (isTRUE(full)) {
    alts <- .tf_list(d, "alternatives")
    auxs <- .tf_list(d, "auxiliary_assumptions")
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
    for (i in seq_along(preds)) {
      for (dref in .tf_list(preds[[i]], "derives_from")) {
        if (.tf_ne_str(dref) && !(dref %in% proposition_ids))
          errors <- c(errors, sprintf("prediction[%d] derives_from '%s' is not a known proposition", i - 1L, dref))
      }
      for (dv in .tf_list(preds[[i]], "diagnostic_vs")) {
        if (.tf_ne_str(dv) && !(dv %in% alternative_ids))
          errors <- c(errors, sprintf("prediction[%d] diagnostic_vs '%s' is not a known alternative", i - 1L, dv))
      }
    }
    for (i in seq_along(auxs)) {
      for (pr in .tf_list(auxs[[i]], "protects")) {
        if (.tf_ne_str(pr) && !(pr %in% prediction_ids))
          errors <- c(errors, sprintf("assumption[%d] protects '%s' is not a known prediction", i - 1L, pr))
      }
    }
    tos <- .tf_list(d, "test_outcomes")
    for (i in seq_along(tos)) {
      if (.tf_ne_str(.tf_get(tos[[i]], "prediction_id"))) {
        pid <- .tf_str(tos[[i]], "prediction_id")
        if (!(pid %in% prediction_ids))
          errors <- c(errors, sprintf("test_outcome[%d] prediction_id '%s' is not a known prediction", i - 1L, pid))
      }
    }
    ev <- .tf_list(d, "evidence")
    for (i in seq_along(ev)) {
      if (.tf_ne_str(.tf_get(ev[[i]], "supports"))) {
        s <- .tf_str(ev[[i]], "supports")
        if (!(s %in% prediction_ids))
          errors <- c(errors, sprintf("evidence[%d] supports '%s' is not a known prediction", i - 1L, s))
      }
    }
  }

  if (length(errors) > 0L) {
    stop("invalid theory object: ", paste(errors, collapse = "; "), call. = FALSE)
  }
  invisible(TRUE)
}

#' Write a theory object to YAML or JSON
#'
#' Serializes a theory object to disk. The format is chosen by the file
#' extension (\code{.json} -> JSON, otherwise YAML). Files are written with LF
#' line endings.
#'
#' @param theory A theory object (named list).
#' @param path Destination path.
#' @return The \code{path} (invisibly).
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory")
#' tf_write(theory, tempfile(fileext = ".yaml"))
#' @export
tf_write <- function(theory, path) {
  ext <- tolower(tools::file_ext(path))
  if (identical(ext, "json")) {
    text <- jsonlite::toJSON(theory, pretty = TRUE, auto_unbox = TRUE, null = "null")
    text <- paste0(as.character(text), "\n")
  } else {
    text <- yaml::as.yaml(theory)
  }
  con <- file(path, open = "wb")
  on.exit(close(con))
  # Normalize to LF only.
  text <- gsub("\r\n", "\n", text, fixed = TRUE)
  writeBin(charToRaw(text), con)
  invisible(path)
}

# -- builder (BUILDING mode) -------------------------------------------------

# Append one provenance entry {step, action, detail} (API_SPEC.md section 8).
# step = str(new length of provenance), 1-based.
.tf_provenance_append <- function(theory, action, detail) {
  prov <- .tf_list(theory, "provenance")
  step <- as.character(length(prov) + 1L)
  prov[[length(prov) + 1L]] <- list(step = step, action = action, detail = detail)
  theory$provenance <- prov
  theory
}

# Append `item` to the named collection (creating it lazily) and return theory.
.tf_coll_append <- function(theory, key, item) {
  coll <- .tf_list(theory, key)
  coll[[length(coll) + 1L]] <- item
  theory[[key]] <- coll
  theory
}

#' Start a new, empty theory object (BUILDING mode entry point)
#'
#' Mirrors the Python \code{theoryforge.new_theory}. Seeds
#' \code{schema_version = "1.0"} and a first provenance entry
#' \code{{step:"1", action:"tf_theory", detail:<id>}}. See API_SPEC.md
#' section 8.
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
#'   construct id (named \code{from} for parity with the schema).
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
#' @param theory A theory object (named list).
#' @param id,statement,type Prediction fields.
#' @param derives_from,diagnostic_vs Optional character vectors.
#' @return The (mutated) theory object.
#' @examples
#' tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_prediction("h1", "Arousal precedes threat appraisal.", "directional")
#' @export
tf_add_prediction <- function(theory, id, statement, type,
                              derives_from = NULL, diagnostic_vs = NULL) {
  p_item <- list(id = id, statement = statement, type = type)
  if (!is.null(derives_from)) p_item$derives_from <- as.list(derives_from)
  if (!is.null(diagnostic_vs)) p_item$diagnostic_vs <- as.list(diagnostic_vs)
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
#' @param added_for Optional reason the assumption was added.
#' @param protects Optional character vector of prediction ids it protects.
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
