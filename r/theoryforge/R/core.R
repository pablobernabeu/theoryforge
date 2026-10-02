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
#' Built-in validation. The default
#' (\code{full = FALSE}) checks required fields and enum membership. With
#' \code{full = TRUE} it additionally checks referential integrity: that every id
#' is unique within its collection and that every cross-reference (proposition
#' endpoints, prediction derivations and diagnostics, and assumption, evidence and
#' test-outcome targets) points to a declared id, and that every prediction
#' \code{severity} is a number within \[0, 1\]. The \code{full} checks are
#' deterministic.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @param full When \code{TRUE}, also run the referential-integrity checks.
#' @return \code{TRUE} (invisibly) on success; otherwise stops with a message
#'   listing every problem found.
#' @examples
#' theory <- tf_read(system.file("fixtures", "panic-network.theory.yaml",
#'                               package = "theoryforge"))
#' isTRUE(tf_validate(theory))              # required fields and enums
#' isTRUE(tf_validate(theory, full = TRUE)) # also ids and cross-references
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
    if (!.tf_ne_str(.tf_get(d, req))) {
      errors <- c(errors, sprintf("missing/empty required field: %s", req))
    }
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
    if (.tf_ne_str(rel) && !(rel %in% .tf_RELATION)) {
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
    if (.tf_ne_str(ty) && !(ty %in% .tf_PRED_TYPE)) {
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
  }

  if (length(errors) > 0L) {
    stop("invalid theory object: ", paste(errors, collapse = "; "), call. = FALSE)
  }
  invisible(TRUE)
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
