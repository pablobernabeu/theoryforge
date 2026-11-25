#' Read, validate and write theory objects.
#'
#' @name core
#' @noRd
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
                     "alternatives", "evidence", "test_outcomes", "provenance", "phenomena")
.tf_VERSION_KEYS <- c("id", "parent_id", "content_hash")

#' Read a theory object from a YAML or JSON file
#'
#' Reads a theory object authored as YAML (or JSON, chosen by file extension)
#' into a named list.
#'
#' The file is read as the Python package's \code{theoryforge.read()} reads
#' it. The text is UTF-8, and a byte-order mark is ignored. A file that is not
#' valid UTF-8 stops with \code{(<path>) the file is not valid UTF-8}, and one
#' that holds a NUL byte with \code{(<path>) the file holds a NUL byte, which
#' theoryforge cannot read}. A YAML or JSON
#' sequence is always a list, even with one element, so [tf_validate()] refuses
#' \code{maturity: [draft]}.
#' Unquoted \code{y}, \code{Y}, \code{n} and \code{N} stay strings, as do
#' dates, while \code{yes}, \code{no}, \code{true}, \code{false}, \code{on} and
#' \code{off} are logicals. Integers are decimal, octal or hexadecimal only, so
#' \code{1:30} and \code{1_000} are strings, and so is a number written with a
#' comma (\code{1,000}). An integer too large for an R integer is read as a
#' double. A tab is read as YAML allows it: as white space after a value, before
#' a comment and in a flow collection, and as text inside an unquoted value. A
#' merge key (\code{<<}) lets the mapping's own keys win. A key repeated in any
#' mapping, in YAML or JSON, stops with \code{(<path>) Duplicate map key:
#' '<key>'}. A YAML document that holds more than 1000000 values once its
#' aliases (\code{*a}) are expanded stops with \code{(<path>) the document holds
#' more than 1000000 values once its aliases are expanded}, before anything
#' walks it, and a document nested more than 64 levels deep, the document being
#' the first, stops with \code{(<path>) the document is nested more than 64
#' levels deep}. An alias whose anchor is undefined, or that lies inside the
#' node its anchor names, stops with \code{(<path>) the alias '<name>' names no
#' node that ends before it}, and an anchor given to two nodes with
#' \code{(<path>) the anchor '<name>' names two nodes}, where yaml would read a
#' placeholder or the first of the two nodes. A value tagged \code{!expr}, which
#' the yaml package evaluates as R code when the option \code{yaml.eval.expr} is
#' \code{TRUE}, stops with \code{(<path>) a value is tagged !expr, which
#' theoryforge does not read}, whatever the option says, and no code is run. A
#' comment in a JSON file stops with the message of the JSON parser, since JSON
#' has no comments. A string or key that holds U+0000 or a lone surrogate, which
#' R would cut short or misread, stops with \code{(<path>) a string holds
#' U+0000, which theoryforge cannot read}, or the same message naming \code{a
#' lone surrogate}. A file with more than one of these faults is refused for
#' the first in this order. A JSON text is measured for depth before it is
#' parsed, a file that is not valid UTF-8 or holds a NUL byte is refused next,
#' or first in YAML, and a syntax error anywhere in a JSON text comes before a
#' repeated key. In
#' YAML, a syntax error, a repeated key and an alias that names no node come in
#' the order the parser meets them, a repeated key where its mapping ends, and
#' a value tagged \code{!expr} once the whole text has been parsed, after any
#' alias that names no node. The depth and the count of values come next, then
#' U+0000 or a lone surrogate and last an anchor given twice. A document that
#' is not a mapping, such as a sequence or an empty YAML file, stops with
#' \code{Theory data must be a mapping}.
#'
#' @param path Path to a \code{.yaml}, \code{.yml} or \code{.json} file. The
#'   file is read as JSON when its extension is \code{.json}, in any letter
#'   case, and as YAML otherwise. A name that begins with its only dot, such
#'   as \code{.json}, has no extension. A leading \code{~} is expanded as
#'   [path.expand()] expands it: \code{~} alone or before a separator is the
#'   home directory, and \code{~user} is that user's home directory on Unix,
#'   an unknown user being left as written, and is left as written on
#'   Windows. The Python package follows the same rule.
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
#' With \code{full = TRUE}, it also checks that every id is unique within its
#' collection and that every cross-reference points to a declared id. The
#' cross-references are the endpoints of a proposition, the derivations and
#' diagnostics of a prediction and the target of an assumption, an evidence
#' entry or a test outcome. It then checks the rest of the schema. That covers
#' the required fields of assumptions, alternatives, evidence and test
#' outcomes, a logical \code{passed}, the evidence direction and formal-model
#' type enums, the version block and the \code{schema_version} pattern. It also covers numbers within \[0, 1\] where
#' the schema asks for them, a prediction's \code{bounds} and \code{test}
#' block and a test outcome's \code{estimate} and \code{se}. Last, it checks
#' the type of every other field and of every entry of a string array.
#'
#' Besides the ids and references, which the schema cannot express, the full
#' check is stricter than a JSON Schema 2020-12 validator in three ways. A
#' blank required string counts as missing. An entry of a string array must be
#' a nonempty string. A prediction's \code{bounds} must hold a finite bound
#' with \code{lower} not above \code{upper}, a test outcome's \code{estimate}
#' and \code{se} and a \code{test} block's \code{sesoi} must be finite, that
#' block's \code{n_planned} must lie within the range of a double and its
#' \code{power_lo} must not be above \code{power_hi}. The full check is more
#' lenient in three ways. A \code{NULL} optional field other than
#' \code{theory_form} is absent, as is a single \code{NA}, which [tf_write()]
#' writes as null. A single string stands for a one-element array of strings.
#' An empty \code{list()} stands for an empty mapping as well as an empty
#' sequence.
#'
#' Both checks are deterministic, and the Python package's
#' \code{Theory.validate()} reports the same problems in the same order with
#' the same text.
#'
#' @param theory A theory object (named list), such as one from [tf_read()].
#' @param full When \code{TRUE}, also check ids, cross-references and the rest
#'   of the schema.
#' @return \code{TRUE} (invisibly) on success. Otherwise, it stops with
#'   \code{"invalid theory object: "} followed by every problem found, joined
#'   by \code{"; "}. The messages count entries from 0, as the Python package
#'   does, so \code{prediction[0]} is \code{theory$predictions[[1]]}.
#' @examples
#' theory <- tf_read(tf_example_path("panic-network.theory.yaml"))
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
  errors <- .tf_validation_problems(theory, full)
  if (length(errors) > 0L) {
    stop("invalid theory object: ", paste(errors, collapse = "; "), call. = FALSE)
  }
  invisible(TRUE)
}

# The problems tf_validate() reports, one message each, in its order.
# tf_validate() joins them with "; ". A message may quote a value of the
# theory, which can hold "; " itself, so the apps read this vector rather than
# split the joined text. Python's Theory._problems() returns the same messages.
.tf_validation_problems <- function(theory, full = FALSE) {
  d <- theory
  # The messages are gathered as a list and joined once at the end, since c()
  # would copy every earlier message at each check.
  found <- list()
  add <- function(...) {
    x <- c(...)
    if (length(x)) found[[length(found) + 1L]] <<- x
  }

  for (req in c("schema_version", "id", "title", "maturity")) {
    add(.tf_required_text(.tf_get(d, req),
                          sprintf("missing/empty required field: %s", req), req))
  }
  # Each enum test asks for a nonempty scalar string before asking about
  # membership. `%in%` coerces its left operand, so a one-element YAML sequence
  # such as `theory_form: [network]` would otherwise match the enum, where the
  # Python twin refuses it as a non-string. Requiring the string first keeps
  # the two engines level on input that is mistyped rather than misspelt.
  mat <- .tf_get(d, "maturity")
  if (!(.tf_ne_str(mat) && mat %in% .tf_MATURITY)) {
    add(sprintf("maturity must be one of %s",
                paste(sort(.tf_MATURITY), collapse = ", ")))
  }
  if ("theory_form" %in% names(d)) {
    form <- .tf_get(d, "theory_form")
    if (!(.tf_ne_str(form) && form %in% .tf_FORM)) {
      add(sprintf("theory_form must be one of %s",
                  paste(sort(.tf_FORM), collapse = ", ")))
    }
  }

  # A misspelt collection key would otherwise pass silently and quietly change
  # every downstream verdict (a renamed `predictions:` drops the whole
  # collection), so unrecognised top-level fields are refused.
  known <- names(.tf_get(tf_theory_schema(), "properties", list()))
  for (key in names(d)) {
    if (!(key %in% known)) {
      add(sprintf("unknown top-level field: %s", key))
    }
  }
  # A collection that is not a list reads as empty (API_SPEC.md section 3), so
  # the theory would lose it without a word.
  for (key in .tf_COLLECTIONS) {
    if (.tf_not_a_list(.tf_get(d, key))) {
      add(sprintf("%s must be a list", key))
    }
  }

  cons <- .tf_list(d, "constructs")
  for (i in seq_along(cons)) {
    add(.tf_required_fields(cons[[i]], sprintf("construct[%d]", i - 1L),
                            c("id", "label", "definition")))
  }

  props <- .tf_list(d, "propositions")
  for (i in seq_along(props)) {
    p_i <- props[[i]]
    add(.tf_required_fields(p_i, sprintf("proposition[%d]", i - 1L),
                            c("id", "from", "to", "relation")))
    rel <- .tf_get(p_i, "relation")
    if (.tf_ne_str(rel) && !(rel %in% .tf_RELATION)) {
      add(sprintf("proposition[%d] relation '%s' not allowed", i - 1L, rel))
    }
  }

  preds <- .tf_list(d, "predictions")
  for (i in seq_along(preds)) {
    p_i <- preds[[i]]
    add(.tf_required_fields(p_i, sprintf("prediction[%d]", i - 1L),
                            c("id", "statement", "type")))
    ty <- .tf_get(p_i, "type")
    if (.tf_ne_str(ty) && !(ty %in% .tf_PRED_TYPE)) {
      add(sprintf("prediction[%d] type '%s' not allowed", i - 1L, ty))
    }
  }

  # The full pass, items 1 to 16 of API_SPEC.md section 2. The Python twin's
  # Theory._full_errors makes the same checks in the same order with the same
  # message text.
  if (isTRUE(full)) {
    alts <- .tf_list(d, "alternatives")
    auxs <- .tf_list(d, "auxiliary_assumptions")
    evs <- .tf_list(d, "evidence")
    tos <- .tf_list(d, "test_outcomes")
    ids_of <- function(items) {
      ids <- vapply(items, function(it) {
        if (.tf_ne_str(.tf_get(it, "id"))) .tf_str(it, "id") else NA_character_
      }, character(1))
      ids[!is.na(ids)]
    }
    construct_list <- ids_of(cons)
    proposition_list <- ids_of(props)
    prediction_list <- ids_of(preds)
    alternative_list <- ids_of(alts)
    # Each set of ids is asked about once for every reference to it
    # (.tf_string_set()).
    construct_ids <- .tf_string_set(construct_list)
    proposition_ids <- .tf_string_set(proposition_list)
    prediction_ids <- .tf_string_set(prediction_list)
    alternative_ids <- .tf_string_set(alternative_list)
    # Each repeat of an id, in order.
    dups <- function(ids, kind) {
      for (i in ids[duplicated(ids)]) add(sprintf("duplicate %s id: %s", kind, i))
    }
    dups(construct_list, "construct"); dups(proposition_list, "proposition")
    dups(prediction_list, "prediction"); dups(alternative_list, "alternative")
    dups(ids_of(auxs), "assumption")
    for (i in seq_along(props)) {
      if (.tf_ne_str(.tf_get(props[[i]], "from"))) {
        frm <- .tf_str(props[[i]], "from")
        if (!.tf_in_set(frm, construct_ids))
          add(sprintf("proposition[%d] from '%s' is not a known construct", i - 1L, frm))
      }
      if (.tf_ne_str(.tf_get(props[[i]], "to"))) {
        to <- .tf_str(props[[i]], "to")
        if (!.tf_in_set(to, construct_ids))
          add(sprintf("proposition[%d] to '%s' is not a known construct", i - 1L, to))
      }
    }
    # Items 3 and 4: each entry of a referencing array is either a nonempty
    # string to look up or a problem in its own right (item 10).
    for (i in seq_along(preds)) {
      add(.tf_string_array(.tf_get(preds[[i]], "derives_from"),
                           sprintf("prediction[%d] derives_from", i - 1L),
                           proposition_ids, "proposition"),
          .tf_string_array(.tf_get(preds[[i]], "diagnostic_vs"),
                           sprintf("prediction[%d] diagnostic_vs", i - 1L),
                           alternative_ids, "alternative"))
    }
    for (i in seq_along(auxs)) {
      add(.tf_string_array(.tf_get(auxs[[i]], "protects"),
                           sprintf("assumption[%d] protects", i - 1L),
                           prediction_ids, "prediction"))
    }
    for (i in seq_along(tos)) {
      if (.tf_ne_str(.tf_get(tos[[i]], "prediction_id"))) {
        pid <- .tf_str(tos[[i]], "prediction_id")
        if (!.tf_in_set(pid, prediction_ids))
          add(sprintf("test_outcome[%d] prediction_id '%s' is not a known prediction", i - 1L, pid))
      }
    }
    for (i in seq_along(evs)) {
      if (.tf_ne_str(.tf_get(evs[[i]], "supports"))) {
        s <- .tf_str(evs[[i]], "supports")
        if (!.tf_in_set(s, prediction_ids))
          add(sprintf("evidence[%d] supports '%s' is not a known prediction", i - 1L, s))
      }
    }
    # The schema types prediction severity as a number in [0, 1]; enforced here
    # so a file cannot pass full validation and then be refused by the scorer,
    # which rejects non-numeric severities.
    for (i in seq_along(preds)) {
      s <- .tf_get(preds[[i]], "severity")
      if (.tf_absent(s)) next
      if (!.tf_is_unit_number(s)) {
        add(sprintf("prediction[%d] severity must be a number between 0 and 1", i - 1L))
      }
    }

    # 8: the required fields of the other collections. passed is required and
    # must be true or false, as the schema has it. A quoted "true" is not a
    # pass, and tf_check() and tf_appraise_amendment() refuse a passed that is
    # present and not a logical (.tf_refuse_non_boolean_outcomes() in rigor.R).
    for (i in seq_along(auxs)) {
      add(.tf_required_fields(auxs[[i]], sprintf("assumption[%d]", i - 1L),
                              c("id", "statement")))
    }
    for (i in seq_along(alts)) {
      add(.tf_required_fields(alts[[i]], sprintf("alternative[%d]", i - 1L),
                              c("id", "label")))
    }
    for (i in seq_along(evs)) {
      add(.tf_required_fields(evs[[i]], sprintf("evidence[%d]", i - 1L),
                              c("supports", "direction")))
      direction <- .tf_get(evs[[i]], "direction")
      if (.tf_ne_str(direction) && !(direction %in% .tf_EVIDENCE_DIRECTION)) {
        add(sprintf("evidence[%d] direction '%s' not allowed", i - 1L, direction))
      }
    }
    for (i in seq_along(tos)) {
      add(.tf_required_fields(tos[[i]], sprintf("test_outcome[%d]", i - 1L),
                              "prediction_id"))
      passed <- .tf_get(tos[[i]], "passed")
      if (!(is.logical(passed) && length(passed) == 1L && !is.na(passed))) {
        add(sprintf("test_outcome[%d] passed must be true or false", i - 1L))
      }
    }

    # 9: typed optional fields of assumptions and test outcomes.
    for (i in seq_along(auxs)) {
      add(.tf_optional_text(.tf_get(auxs[[i]], "added_for"),
                            sprintf("assumption[%d] added_for", i - 1L),
                            nullable = TRUE))
    }
    for (i in seq_along(tos)) {
      t_i <- tos[[i]]
      prefix <- sprintf("test_outcome[%d]", i - 1L)
      add(.tf_unit_number(.tf_get(t_i, "severity_at_test"), paste(prefix, "severity_at_test")),
          .tf_optional_text(.tf_get(t_i, "registered"), paste(prefix, "registered"),
                            nullable = TRUE),
          .tf_optional_text(.tf_get(t_i, "date"), paste(prefix, "date"), nullable = TRUE))
    }

    # 11: the formal model. A type outside the enum reads as absent wherever
    # the theory is read (API_SPEC.md section 3), so it earns no formalisation
    # point.
    fm <- .tf_get(d, "formal_model")
    if (!.tf_absent(fm) && .tf_not_a_mapping(fm)) {
      add("formal_model must be a mapping")
    } else if (is.list(fm)) {
      ty <- .tf_get(fm, "type")
      if (!.tf_absent(ty) && !.tf_is_string(ty)) {
        add(.tf_not_string("formal_model type", ty))
      } else if (!.tf_absent(ty) && !(ty %in% .tf_FORMAL_MODEL_TYPE)) {
        add(sprintf("formal_model type '%s' not allowed", ty))
      }
      add(.tf_optional_text(.tf_get(fm, "spec_ref"), "formal_model spec_ref",
                            nullable = TRUE))
    }

    # 12: the version block, which the schema closes.
    ver <- .tf_get(d, "version")
    if (!.tf_absent(ver) && .tf_not_a_mapping(ver)) {
      add("version must be a mapping")
    } else if (is.list(ver)) {
      for (key in names(ver)) {
        if (!(key %in% .tf_VERSION_KEYS)) {
          add(sprintf("version has unknown field: %s", key))
        }
      }
      add(.tf_optional_text(.tf_get(ver, "id"), "version id"),
          .tf_optional_text(.tf_get(ver, "parent_id"), "version parent_id",
                            nullable = TRUE),
          .tf_optional_text(.tf_get(ver, "content_hash"), "version content_hash",
                            nullable = TRUE))
      recorded <- .tf_get(ver, "content_hash")
      if (.tf_ne_str(recorded) && !identical(recorded, tf_content_hash(d))) {
        add("version content_hash does not match the theory's content")
      }
    }

    # 13: the schema_version pattern. The default regex engine's "$" matches
    # only at the end of the string, as Python's fullmatch() does.
    sv <- .tf_get(d, "schema_version")
    if (.tf_ne_str(sv) && !grepl("^[0-9]+\\.[0-9]+$", sv)) {
      add('schema_version must match major.minor (for example "1.0")')
    }

    # 14: the schema's remaining types, collection by collection in the schema's
    # order.
    for (i in seq_along(cons)) {
      prefix <- sprintf("construct[%d]", i - 1L)
      add(.tf_string_array(.tf_get(cons[[i]], "measurement"), paste(prefix, "measurement")),
          .tf_string_array(.tf_get(cons[[i]], "boundary_conditions"),
                           paste(prefix, "boundary_conditions")))
    }
    for (i in seq_along(props)) {
      prefix <- sprintf("proposition[%d]", i - 1L)
      add(.tf_optional_text(.tf_get(props[[i]], "mechanism"), paste(prefix, "mechanism")),
          .tf_optional_text(.tf_get(props[[i]], "functional_form"),
                            paste(prefix, "functional_form")))
    }
    add(.tf_string_array(.tf_get(d, "boundary_conditions"), "boundary_conditions"))
    for (i in seq_along(preds)) {
      add(.tf_unit_number(.tf_get(preds[[i]], "risk_score"),
                          sprintf("prediction[%d] risk_score", i - 1L)),
          .tf_bounds(.tf_get(preds[[i]], "bounds"), sprintf("prediction[%d] bounds", i - 1L)),
          .tf_test_plan(.tf_get(preds[[i]], "test"), sprintf("prediction[%d] test", i - 1L)))
    }
    for (i in seq_along(evs)) {
      add(.tf_optional_text(.tf_get(evs[[i]], "source_doi"),
                            sprintf("evidence[%d] source_doi", i - 1L),
                            nullable = TRUE))
    }
    for (i in seq_along(tos)) {
      prefix <- sprintf("test_outcome[%d]", i - 1L)
      add(.tf_optional_text(.tf_get(tos[[i]], "observed"), paste(prefix, "observed")),
          .tf_estimate_and_se(tos[[i]], prefix))
    }
    for (i in seq_along(alts)) {
      prefix <- sprintf("alternative[%d]", i - 1L)
      add(.tf_string_array(.tf_get(alts[[i]], "key_constructs"),
                           paste(prefix, "key_constructs")),
          .tf_optional_text(.tf_get(alts[[i]], "source_doi"), paste(prefix, "source_doi"),
                            nullable = TRUE))
    }
    steps <- .tf_list(d, "provenance")
    for (i in seq_along(steps)) {
      prefix <- sprintf("provenance[%d]", i - 1L)
      if (.tf_not_a_mapping(steps[[i]])) {
        add(paste(prefix, "must be a mapping"))
        next
      }
      for (name in c("step", "action", "detail")) {
        add(.tf_optional_text(.tf_get(steps[[i]], name), paste(prefix, name)))
      }
    }

    # 15: the claims of predictions and phenomena, and the propositions of
    # rival accounts, which tf_entailments() and tf_discriminate() read.
    phens <- .tf_list(d, "phenomena")
    dups(ids_of(phens), "phenomenon")
    for (i in seq_along(phens)) {
      prefix <- sprintf("phenomenon[%d]", i - 1L)
      add(.tf_required_fields(phens[[i]], prefix, c("id", "statement")),
  .tf_optional_text(.tf_get(phens[[i]], "source_doi"), paste(prefix, "source_doi"),
                    nullable = TRUE))
    }
    for (i in seq_along(preds)) {
      add(.tf_claim(.tf_get(preds[[i]], "claim"),
                    sprintf("prediction[%d] claim", i - 1L), construct_ids))
    }
    for (i in seq_along(phens)) {
      add(.tf_claim(.tf_get(phens[[i]], "claim"),
                    sprintf("phenomenon[%d] claim", i - 1L), construct_ids))
    }
    for (i in seq_along(alts)) {
      rival <- .tf_get(alts[[i]], "propositions")
      if (.tf_not_a_list(rival)) {
        add(sprintf("alternative[%d] propositions must be a list", i - 1L))
        next
      }
      if (!is.list(rival)) next
      pids <- vapply(rival, function(p) {
        pid <- .tf_get(p, "id")
        if (.tf_ne_str(pid)) pid else NA_character_
      }, character(1))
      repeated <- !is.na(pids)
      repeated[repeated] <- duplicated(pids[repeated])
      for (j in seq_along(rival)) {
        p <- rival[[j]]
        name <- sprintf("alternative[%d] proposition[%d]", i - 1L, j - 1L)
        add(.tf_required_fields(p, name, c("id", "from", "to", "relation")))
        rel <- .tf_get(p, "relation")
        if (.tf_ne_str(rel) && !(rel %in% .tf_RELATION)) {
          add(sprintf("%s relation '%s' not allowed", name, rel))
        }
        if (repeated[[j]]) {
          add(sprintf("alternative[%d] duplicate proposition id: %s", i - 1L, pids[[j]]))
        }
        for (end in c("from", "to")) {
          val <- .tf_get(p, end)
          if (.tf_ne_str(val) && !.tf_in_set(val, construct_ids)) {
            add(sprintf("%s %s '%s' is not a known construct", name, end, val))
          }
        }
        add(.tf_optional_text(.tf_get(p, "mechanism"), paste(name, "mechanism")))
      }
    }

    # 16: a claim's form and sign against its bounds, where both are
    # themselves valid. A type or a sign the bounds contradict makes the
    # riskiness rubric, the precision item and the causal reading describe a
    # different claim from the one tf_post_data_severity() tests. An existence
    # claim allows every value but 0, which no bounds can state, and a
    # one-sided region would make tf_post_data_severity() test a directional
    # claim.
    for (i in seq_along(preds)) {
      region <- .tf_bounds_region(.tf_get(preds[[i]], "bounds"))
      if (is.null(region)) next
      lo <- region$lower
      up <- region$upper
      both <- !is.null(lo) && !is.null(up)
      ty <- .tf_get(preds[[i]], "type")
      ty <- if (.tf_is_string(ty)) ty else ""
      if (ty %in% c("point", "interval") && !both) {
        article <- if (identical(ty, "interval")) "an" else "a"
        add(sprintf(paste0("prediction[%d] is %s %s claim, so its bounds need a ",
                           "finite lower and a finite upper"), i - 1L, article, ty))
      } else if (identical(ty, "directional") && both && lo != 0 && up != 0) {
        add(sprintf(paste0("prediction[%d] is a directional claim, so its bounds ",
                           "must leave one side open or end at 0"), i - 1L))
      } else if (identical(ty, "existence")) {
        add(sprintf(paste0("prediction[%d] is an existence claim, so it takes no ",
                           "bounds: the region it allows, every value but 0, is ",
                           "not one interval"), i - 1L))
      }
      claim <- .tf_get(preds[[i]], "claim")
      sign <- if (.tf_is_mapping(claim)) .tf_get(claim, "sign") else NULL
      sign <- if (.tf_is_string(sign)) sign else ""
      if (sign == "positive" && !(!is.null(lo) && lo >= 0)) {
        add(sprintf(paste0("prediction[%d] claims a positive sign, so its lower ",
                           "bound must be 0 or above"), i - 1L))
      } else if (sign == "negative" && !(!is.null(up) && up <= 0)) {
        add(sprintf(paste0("prediction[%d] claims a negative sign, so its upper ",
                           "bound must be 0 or below"), i - 1L))
      } else if (sign == "zero" && !((is.null(lo) || lo <= 0) && (is.null(up) || up >= 0))) {
        add(sprintf("prediction[%d] claims a zero sign, so its bounds must include 0",
                    i - 1L))
      } else if (sign == "nonzero" && !((!is.null(lo) && lo > 0) || (!is.null(up) && up < 0))) {
        add(sprintf(paste0("prediction[%d] claims a nonzero sign, so its bounds ",
                           "must exclude 0"), i - 1L))
      }
    }

    # 17: the fields of each entry, which the schema closes as it closes the
    # top level, since a misspelt severty or derives_form would drop what it
    # holds without a word. Collections come in the schema's order.
    props <- tf_theory_schema()$properties
    keys <- function(node) names(node$properties)
    entries <- c(constructs = "construct", propositions = "proposition",
                 phenomena = "phenomenon", predictions = "prediction",
                 auxiliary_assumptions = "assumption", evidence = "evidence",
                 test_outcomes = "test_outcome", alternatives = "alternative")
    for (key in names(entries)) {
      item <- props[[key]]$items
      coll <- .tf_list(d, key)
      for (i in seq_along(coll)) {
        add(.tf_unknown_fields(coll[[i]], sprintf("%s[%d]", entries[[key]], i - 1L),
                               keys(item)))
        rival <- if (key == "alternatives") .tf_get(coll[[i]], "propositions")
        if (is.list(rival) && !.tf_is_mapping(rival)) {
          for (j in seq_along(rival)) {
            add(.tf_unknown_fields(
rival[[j]], sprintf("alternative[%d] proposition[%d]", i - 1L, j - 1L),
keys(item$properties$propositions$items)))
          }
        }
      }
    }
    add(.tf_unknown_fields(.tf_get(d, "formal_model"), "formal_model",
                           keys(props$formal_model)))
    steps <- .tf_list(d, "provenance")
    for (i in seq_along(steps)) {
      add(.tf_unknown_fields(steps[[i]], sprintf("provenance[%d]", i - 1L),
                             keys(props$provenance$items)))
    }
  }
  as.character(unlist(found))
}

# -- validation helpers (API_SPEC.md section 2) ------------------------------
#
# Each returns the messages for one value, so that tf_validate() lists them in
# the contract's order. The Python twin's core.py holds the same helpers
# (_required_text and the rest) with the same messages.

# A set of strings that the validator asks about once for every reference to
# it, such as the construct ids. A small set is kept as it is and searched with
# %in%. %in% hashes the whole set at each question, though, so a larger set is
# an environment whose variable names spell the strings' UTF-8 bytes, which
# answers at once. A string is a member when match() would find it, so a
# string whose UTF-8 bytes do not say how match() compares it is kept aside and
# searched with %in%: one marked as bytes, which match() compares only with
# other bytes, one in the native encoding that is not ASCII outside a UTF-8
# locale, whose bytes enc2utf8() would rewrite, and one too long for a
# variable name.
.tf_SET_SMALL <- 200L

.tf_string_set <- function(x) {
  if (length(x) <= .tf_SET_SMALL) return(list(env = NULL, aside = x))
  key <- .tf_set_key(x)
  env <- new.env(hash = TRUE, parent = emptyenv(), size = length(x))
  for (k in key[!is.na(key)]) assign(k, TRUE, envir = env)
  list(env = env, aside = x[is.na(key)])
}

.tf_set_key <- function(x) {
  x <- as.character(x)
  enc <- Encoding(x)
  utf8_locale <- isTRUE(l10n_info()[["UTF-8"]])
  vapply(seq_along(x), function(i) {
    bytes <- charToRaw(x[[i]])
    if (enc[[i]] == "bytes" || (enc[[i]] == "unknown" && !utf8_locale && any(bytes > as.raw(0x7F)))) {
      return(NA_character_)
    }
    bytes <- charToRaw(enc2utf8(x[[i]]))
    if (length(bytes) > 4000L) return(NA_character_)
    paste(c("k", as.character(bytes)), collapse = "")
  }, character(1))
}

.tf_in_set <- function(x, set) {
  if (is.null(set$env)) return(x %in% set$aside)
  key <- .tf_set_key(x)
  if (is.na(key)) x %in% set$aside else exists(key, envir = set$env, inherits = FALSE)
}

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

# Whether `v` is a single number within [0, 1]. A logical is not a number.
.tf_is_unit_number <- function(v) {
  is.numeric(v) && length(v) == 1L && !is.na(v) && v >= 0 && v <= 1
}

.tf_unit_number <- function(v, name) {
  if (.tf_absent(v) || .tf_is_unit_number(v)) return(character(0))
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

# A prediction's bounds: a mapping of lower and upper, each a number or null. An
# infinite bound is open, as a null one is, so at least one bound must be
# finite, and a lower bound above the upper one states no region. These are the
# conditions tf_post_data_severity() refuses, so a theory that passes full
# validation is never refused there. The block is closed, since a misspelt
# `uper` would leave the upper bound open and make a two-sided claim one-sided.
.tf_bounds <- function(v, name) {
  if (.tf_absent(v)) return(character(0))
  shape <- paste(name, "must be a mapping with numeric or null lower and upper")
  if (.tf_not_a_mapping(v)) return(shape)
  out <- character(0)
  for (key in names(v)) {
    if (!(key %in% c("lower", "upper"))) {
      out <- c(out, sprintf("%s has unknown field: %s", name, key))
    }
  }
  raw <- list(.tf_get(v, "lower"), .tf_get(v, "upper"))
  nums <- lapply(raw, .tf_number)
  for (k in 1:2) {
    if (!.tf_absent(raw[[k]]) && is.null(nums[[k]])) return(c(out, shape))
  }
  if (!any(vapply(nums, function(x) !is.null(x) && is.finite(x), logical(1)))) {
    out <- c(out, paste(name, "needs at least one finite bound"))
  }
  if (!is.null(nums[[1]]) && !is.null(nums[[2]]) && nums[[1]] > nums[[2]]) {
    out <- c(out, paste(name, "lower exceeds upper"))
  }
  out
}

# `<name> has unknown field: <key>` for each key of `entry` the schema does not
# list. A key that begins with x_ carries extension metadata and is allowed. The
# message names the closest known field, within two edits by utils::adist(),
# the first in schema order on a tie, as the Python twin's _unknown_fields().
.tf_unknown_fields <- function(entry, name, known) {
  if (!.tf_is_mapping(entry)) return(character(0))
  out <- character(0)
  for (key in names(entry)) {
    if (key %in% known || startsWith(key, "x_")) next
    msg <- sprintf("%s has unknown field: %s", name, key)
    if (length(known)) {
      dist <- as.vector(utils::adist(key, known))
      if (min(dist) <= 2) msg <- sprintf("%s (did you mean %s?)", msg, known[[which.min(dist)]])
    }
    out <- c(out, msg)
  }
  out
}

# The finite ends of a valid bounds mapping, as list(lower, upper) with NULL
# for an open side, or NULL when the bounds are invalid or absent.
.tf_bounds_region <- function(v) {
  if (.tf_absent(v) || length(.tf_bounds(v, "bounds")) > 0L) return(NULL)
  end <- function(key) {
    x <- .tf_number(.tf_get(v, key))
    if (!is.null(x) && is.finite(x)) x else NULL
  }
  list(lower = end("lower"), upper = end("upper"))
}

.tf_TEST_KEYS <- c("n_planned", "unit", "alpha", "sided", "sesoi", "sesoi_scale", "power",
                   "decision_probability", "power_lo", "power_hi", "method", "design_ref",
                   "justification")
.tf_SIDED <- c("two", "one")

# Whether `v` is a finite whole number of at least 1, as n_planned must be. A
# double such as 48 counts, as JSON Schema's integer type allows, and an integer
# too large for a double, which the reader holds as Inf, does not.
.tf_whole_count <- function(v) {
  x <- .tf_number(v)
  !is.null(x) && is.finite(x) && x == floor(x) && x >= 1
}

# A prediction's test block, the sampling plan tf_preregister() lists. The block
# is closed, as bounds is, since a misspelt key would drop a value from the plan
# without a word. power_lo and power_hi come as a pair, because the
# preregistration writes the interval only whole.
.tf_test_plan <- function(v, name) {
  if (.tf_absent(v)) return(character(0))
  if (.tf_not_a_mapping(v)) return(paste(name, "must be a mapping"))
  out <- character(0)
  for (key in names(v)) {
    if (!(key %in% .tf_TEST_KEYS)) {
      out <- c(out, sprintf("%s has unknown field: %s", name, key))
    }
  }
  n <- .tf_get(v, "n_planned")
  if (!.tf_absent(n) && !.tf_whole_count(n)) {
    out <- c(out, paste(name, "n_planned must be a whole number of at least 1"))
  }
  out <- c(out, .tf_optional_text(.tf_get(v, "unit"), paste(name, "unit")))
  a <- .tf_get(v, "alpha")
  x <- .tf_number(a)
  if (!.tf_absent(a) && !(!is.null(x) && x > 0 && x < 1)) {
    out <- c(out, paste(name, "alpha must be a number between 0 and 1"))
  }
  sided <- .tf_get(v, "sided")
  if (!.tf_absent(sided) && is.null(.tf_enum(sided, .tf_SIDED))) {
    out <- c(out, sprintf("%s sided must be one of: %s", name, paste(.tf_SIDED, collapse = ", ")))
  }
  s <- .tf_get(v, "sesoi")
  x <- .tf_number(s)
  if (!.tf_absent(s) && (is.null(x) || !is.finite(x))) {
    out <- c(out, paste(name, "sesoi must be a finite number"))
  }
  out <- c(out, .tf_optional_text(.tf_get(v, "sesoi_scale"), paste(name, "sesoi_scale")))
  for (key in c("power", "decision_probability", "power_lo", "power_hi")) {
    out <- c(out, .tf_unit_number(.tf_get(v, key), paste(name, key)))
  }
  lo <- .tf_get(v, "power_lo")
  hi <- .tf_get(v, "power_hi")
  if (.tf_absent(lo) != .tf_absent(hi)) {
    out <- c(out, paste(name, "power_lo and power_hi must be given together"))
  } else if (.tf_is_unit_number(lo) && .tf_is_unit_number(hi) && lo > hi) {
    out <- c(out, paste(name, "power_lo exceeds power_hi"))
  }
  for (key in c("method", "design_ref", "justification")) {
    out <- c(out, .tf_optional_text(.tf_get(v, key), paste(name, key)))
  }
  out
}

# A test outcome's estimate and se, which tf_post_data_severity() reads
# together.
.tf_estimate_and_se <- function(t, prefix) {
  est <- .tf_get(t, "estimate")
  se <- .tf_get(t, "se")
  out <- character(0)
  x <- .tf_number(est)
  if (!.tf_absent(est) && (is.null(x) || !is.finite(x))) {
    out <- c(out, paste(prefix, "estimate must be a finite number"))
  }
  x <- .tf_number(se)
  if (!.tf_absent(se) && (is.null(x) || !is.finite(x) || x <= 0)) {
    out <- c(out, paste(prefix, "se must be a finite number greater than 0"))
  }
  if (.tf_absent(est) != .tf_absent(se)) {
    out <- c(out, paste(prefix, "estimate and se must be given together"))
  }
  out
}

# The problems of a prediction's or a phenomenon's claim (API_SPEC.md section 2,
# item 15). An absent claim, or an empty one, is no claim.
.tf_claim <- function(v, name, construct_ids) {
  if (.tf_absent(v)) return(character(0))
  if (.tf_not_a_mapping(v)) return(paste(name, "must be a mapping"))
  if (!is.list(v) || length(v) == 0L) return(character(0))
  out <- character(0)
  for (key in names(v)) {
    if (!(key %in% c("kind", "x", "y", "given", "sign"))) {
      out <- c(out, sprintf("%s has unknown field: %s", name, key))
    }
  }
  out <- c(out, .tf_required_fields(v, name, c("kind", "x", "y", "sign")))
  kind <- .tf_get(v, "kind")
  sign <- .tf_get(v, "sign")
  if (.tf_ne_str(kind) && !(kind %in% .tf_CLAIM_KINDS)) {
    out <- c(out, sprintf("%s kind '%s' not allowed", name, kind))
  }
  if (.tf_ne_str(sign) && !(sign %in% .tf_CLAIM_SIGNS)) {
    out <- c(out, sprintf("%s sign '%s' not allowed", name, sign))
  }
  x <- .tf_get(v, "x")
  y <- .tf_get(v, "y")
  for (end in c("x", "y")) {
    val <- .tf_get(v, end)
    if (.tf_ne_str(val) && !.tf_in_set(val, construct_ids)) {
      out <- c(out, sprintf("%s %s '%s' is not a known construct", name, end, val))
    }
  }
  if (.tf_ne_str(x) && identical(x, y)) out <- c(out, paste(name, "x and y must differ"))
  out <- c(out, .tf_string_array(.tf_get(v, "given"), paste(name, "given"), construct_ids, "construct"))
  given <- .tf_str_list(.tf_get(v, "given"))
  if (length(given) > 0L) {
    if ((.tf_ne_str(x) && x %in% given) || (.tf_ne_str(y) && y %in% given)) {
      out <- c(out, paste(name, "given must not include x or y"))
    }
    if (identical(kind, "effect")) {
      out <- c(out, paste(name, "given applies only to an association"))
    } else if (identical(sign, "positive") || identical(sign, "negative")) {
      out <- c(out, paste(name, "sign must be zero or nonzero when given is not empty"))
    }
  }
  out
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
    } else if (!is.null(known) && !.tf_in_set(entry, known)) {
      out <- c(out, sprintf("%s '%s' is not a known %s", name, entry, kind))
    }
  }
  out
}

#' Write a theory object to YAML or JSON
#'
#' Serialises a theory object to disk. The file extension sets the format:
#' JSON for \code{.json} and YAML otherwise. Files are UTF-8 with LF line
#' endings.
#'
#' Each number is written with the fewest significant digits, up to 17, that
#' read back as the same double in both formats, so the file holds the theory's
#' numbers exactly. A date or a date-time is written as text, such as
#' \code{"2026-11-23"}. Logicals are written as
#' \code{true} and \code{false}, and a missing value (\code{NA}) is written as
#' null, which reads back as \code{NULL} in R and \code{None} in Python. Every
#' field the schema types as an array of strings (\code{derives_from},
#' \code{diagnostic_vs}, \code{protects}, \code{measurement},
#' \code{boundary_conditions}, \code{key_constructs}) is written as an array,
#' even when the theory holds it as a single string. A theory that validates
#' against the package's own schema therefore still validates once written, and
#' it reads back the same in R and in Python. A single string held in such a
#' field reads back as a one-element array, which [tf_content_hash()] reads as
#' it reads the string, so a hash recorded in \code{version$content_hash} still
#' matches the theory.
#'
#' @param theory A theory object (named list).
#' @param path Destination path.
#' @return The \code{path} (invisibly).
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory")
#' tf_write(theory, tempfile(fileext = ".yaml"))
#' @export
tf_write <- function(theory, path) {
  # NA becomes null before the boxing, so that a missing value is written as
  # null and not as a one-element array holding null.
  theory <- .tf_box_string_arrays(.tf_na_as_null(.tf_dates_as_text(theory)))
  if (.tf_is_json(path)) {
    # Each finite double is written as text with the fewest digits that read
    # back as the same double. jsonlite's default rounds to four decimal places,
    # which would write a severity of 0.49996 as 0.5, and digits = NA keeps 15
    # significant digits.
    text <- jsonlite::toJSON(.tf_json_doubles(theory), pretty = TRUE, auto_unbox = TRUE,
                             null = "null", digits = NA, json_verbatim = TRUE)
    text <- paste0(as.character(text), "\n")
  } else {
    # yaml's default writes doubles to seven decimal places and a logical as yes
    # or no. .tf_yaml_double writes the fewest digits that read back as the same
    # double, and verbatim_logical writes true and false.
    text <- yaml::as.yaml(theory, handlers = list(logical = yaml::verbatim_logical,
                                                  numeric = .tf_yaml_double))
  }
  .tf_write_lf(path, text)
}

# -- builder (BUILDING mode) -------------------------------------------------

# Append one provenance entry {step, action, detail} (API_SPEC.md section 8).
# step = str(new length of provenance), 1-based.
.tf_provenance_append <- function(theory, action, detail) {
  prov <- .tf_coll(theory, "provenance")
  step <- as.character(length(prov) + 1L)
  prov[[length(prov) + 1L]] <- list(step = step, action = action, detail = detail)
  theory$provenance <- prov
  theory
}

# The list a builder appends to under `key`. A missing or NULL key gives an
# empty list, and a vector of two or more values, which only a theory built in
# memory holds, the list of its elements. Any other value that is not a list is
# refused with the message the Python builders give (API_SPEC.md section 8).
.tf_coll <- function(theory, key) {
  v <- theory[[key]]
  if (is.null(v)) return(list())
  if (is.list(v)) {
    if (length(v) > 0L && .tf_is_mapping(v)) .tf_refuse_coll(key, "a mapping")
    return(v)
  }
  if (length(v) >= 2L) return(as.list(v))
  what <- if (is.character(v)) "a string" else if (is.logical(v)) "a boolean" else
    if (is.numeric(v)) "a number" else "a value that is not a list"
  .tf_refuse_coll(key, what)
}

.tf_refuse_coll <- function(key, what) {
  stop(sprintf("cannot add to '%s': the theory holds %s there, not a list", key, what),
       call. = FALSE)
}

# Append `item` to the collection under `key` and log the step. Both lists are
# checked before anything is stored, so a refused call adds nothing.
.tf_add <- function(theory, key, item, action, detail) {
  coll <- .tf_coll(theory, key)
  .tf_coll(theory, "provenance")
  coll[[length(coll) + 1L]] <- item
  theory[[key]] <- coll
  .tf_provenance_append(theory, action, detail)
}

# A builder's string-array argument as the list the schema stores: its values,
# in order and without names, so that a named vector gives its values and a
# factor its labels, as the Python builders store a mapping's values.
.tf_str_vec <- function(x) {
  if (is.factor(x)) x <- as.character(x)
  unname(as.list(x))
}

#' Start a new, empty theory object
#'
#' Seeds \code{schema_version = "1.1"} and a first provenance entry
#' \code{{step:"1", action:"tf_theory", detail:<id>}}.
#'
#' The builders do not check field values. [tf_validate()] reports a value
#' outside its enum, except that it checks the formal-model type, an evidence
#' entry's \code{direction} and a \code{test} block's \code{sided} only with
#' \code{full = TRUE}.
#'
#' @param id Theory id.
#' @param title Human-readable title.
#' @param maturity Maturity stage, one of \code{"draft"}, \code{"building"}
#'   (the default), \code{"developing"} or \code{"testing"}. At \code{"draft"},
#'   the gate of [tf_check()] is advisory.
#' @param theory_form Theory form, one of \code{"variance"}, \code{"network"}
#'   (the default), \code{"typology"} or \code{"process"}. No score depends on
#'   it.
#' @return A theory object (named list).
#' @examples
#' tf_theory("demo-1", "A demonstration theory")
#' @export
tf_theory <- function(id, title, maturity = "building", theory_form = "network") {
  theory <- list(
    schema_version = "1.1",
    id = id,
    title = title,
    maturity = maturity,
    theory_form = theory_form
  )
  .tf_provenance_append(theory, "tf_theory", id)
}

#' Add a construct to a theory
#'
#' Appends a construct and a provenance entry. R does not change the theory in
#' place, so assign the result.
#'
#' @param theory A theory object (named list).
#' @param id,label,definition Construct fields.
#' @param measurement,boundary_conditions Optional character vectors, stored
#'   without names.
#' @return The theory with the construct added.
#' @examples
#' tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Physiological arousal",
#'                    "Bodily activation in response to a stressor.")
#' @export
tf_add_construct <- function(theory, id, label, definition,
                             measurement = NULL, boundary_conditions = NULL) {
  c_item <- list(id = id, label = label, definition = definition)
  if (!is.null(measurement)) c_item$measurement <- .tf_str_vec(measurement)
  if (!is.null(boundary_conditions)) c_item$boundary_conditions <- .tf_str_vec(boundary_conditions)
  .tf_add(theory, "constructs", c_item, "tf_add_construct", id)
}

#' Add a proposition to a theory
#'
#' Appends a proposition and a provenance entry. R does not change the theory
#' in place, so assign the result.
#'
#' @param theory A theory object (named list).
#' @param id,from,to,relation Proposition fields. \code{relation} is one of
#'   \code{"increases"}, \code{"decreases"}, \code{"causes"},
#'   \code{"mediates"}, \code{"moderates"} or \code{"associates"}.
#' @param mechanism Optional statement of why the relation holds.
#' @param functional_form Optional description of the relation's shape.
#' @return The theory with the proposition added.
#' @examples
#' tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_proposition("p1", "c_arousal", "c_threat", "increases",
#'                      mechanism = "Bodily cues are read as danger.")
#' @export
tf_add_proposition <- function(theory, id, from, to, relation, mechanism = NULL,
                               functional_form = NULL) {
  p_item <- list(id = id, from = from, to = to, relation = relation)
  if (!is.null(mechanism)) p_item$mechanism <- mechanism
  if (!is.null(functional_form)) p_item$functional_form <- functional_form
  .tf_add(theory, "propositions", p_item, "tf_add_proposition", id)
}

#' Add a prediction to a theory
#'
#' Appends a prediction and a provenance entry. R does not change the theory in
#' place, so assign the result.
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
#'   requires. The tolerance comes from measurement, and the theory itself
#'   permits only the one value.
#' @param derives_from,diagnostic_vs Optional character vectors, stored without
#'   names.
#' @param severity Optional declared pre-data severity from 0 to 1. The
#'   checklist's risk_severity item reads it, and reads the claim-form rubric's
#'   value ([tf_severity()]) for a prediction that declares none.
#' @param test Optional sampling plan for testing the prediction, a named list
#'   of any of \code{n_planned}, \code{unit}, \code{alpha}, \code{sided}
#'   (\code{"two"} or \code{"one"}), \code{sesoi} and \code{sesoi_scale} (the
#'   smallest effect of interest and its scale), \code{power} or
#'   \code{decision_probability} with an optional \code{power_lo} and
#'   \code{power_hi}, \code{method}, \code{design_ref} and
#'   \code{justification}. [tf_preregister()] lists it after the hypotheses,
#'   and nothing scores it.
#' @param bounds Optional region of the quantity the claim allows, a named list
#'   of \code{lower} and \code{upper}, either of which may be \code{NULL} for
#'   an open side. [tf_post_data_severity()] reads it with each test outcome.
#' @param claim Optional machine-readable claim, a named list of \code{kind}
#'   (\code{"effect"} or \code{"association"}), the construct ids \code{x} and
#'   \code{y}, an optional \code{given} and \code{sign} (\code{"positive"},
#'   \code{"negative"}, \code{"zero"} or \code{"nonzero"}), which
#'   [tf_entailments()] reads against the causal graph.
#' @return The theory with the prediction added.
#' @examples
#' tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_prediction("h1", "Arousal raises perceived threat.", "directional",
#'                     claim = list(kind = "effect", x = "c_arousal", y = "c_threat",
#'                                  sign = "positive"))
#'
#' # A prediction with the sampling plan of its test.
#' tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_prediction("h1", "The switch cost lies between 20 and 60 ms.", "interval",
#'                     bounds = list(lower = 20, upper = 60),
#'                     test = list(n_planned = 48, unit = "participants", alpha = 0.05,
#'                                 sided = "two", power = 0.9))
#' @export
tf_add_prediction <- function(theory, id, statement, type,
                              derives_from = NULL, diagnostic_vs = NULL,
                              severity = NULL, test = NULL, bounds = NULL, claim = NULL) {
  p_item <- list(id = id, statement = statement, type = type)
  if (!is.null(derives_from)) p_item$derives_from <- .tf_str_vec(derives_from)
  if (!is.null(diagnostic_vs)) p_item$diagnostic_vs <- .tf_str_vec(diagnostic_vs)
  if (!is.null(severity)) p_item$severity <- severity
  # A named numeric vector becomes the mapping it names. A vector that mixes
  # numbers and text has already turned its numbers into text, which
  # tf_validate(full = TRUE) then reports.
  if (!is.null(test)) p_item$test <- if (is.list(test)) test else as.list(test)
  if (!is.null(bounds)) p_item$bounds <- if (is.list(bounds)) bounds else as.list(bounds)
  if (!is.null(claim)) {
    claim <- if (is.list(claim)) claim else as.list(claim)
    if (!is.null(claim$given)) claim$given <- .tf_str_vec(claim$given)
    p_item$claim <- claim
  }
  .tf_add(theory, "predictions", p_item, "tf_add_prediction", id)
}

#' Add an alternative theory
#'
#' Appends a registered alternative account and a provenance entry. R does not
#' change the theory in place, so assign the result.
#'
#' @param theory A theory object (named list).
#' @param id,label Alternative fields.
#' @param key_constructs Optional character vector of the rival's key
#'   constructs, which [tf_landscape()] matches against the literature.
#' @param source_doi Optional DOI of the work that states the rival.
#' @param propositions Optional list of the rival's own propositions over the
#'   theory's constructs, each a named list with \code{id}, \code{from},
#'   \code{to} and \code{relation}, which [tf_discriminate()] sets against the
#'   theory's.
#' @return The theory with the alternative added.
#' @examples
#' tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_alternative("alt1", "Cognitive appraisal account",
#'                      key_constructs = "appraisal",
#'                      propositions = list(list(id = "r1", from = "c_threat",
#'                                               to = "c_arousal", relation = "increases")))
#' @export
tf_add_alternative <- function(theory, id, label, key_constructs = NULL, source_doi = NULL,
                               propositions = NULL) {
  a_item <- list(id = id, label = label)
  if (!is.null(key_constructs)) a_item$key_constructs <- .tf_str_vec(key_constructs)
  if (!is.null(source_doi)) a_item$source_doi <- source_doi
  if (!is.null(propositions)) a_item$propositions <- unname(as.list(propositions))
  .tf_add(theory, "alternatives", a_item, "tf_add_alternative", id)
}

#' Add a phenomenon the theory sets out to explain
#'
#' Appends a phenomenon, a robust empirical regularity, and a provenance entry.
#' R does not change the theory in place, so assign the result.
#'
#' @param theory A theory object (named list).
#' @param id The phenomenon's identifier.
#' @param statement The regularity in words.
#' @param claim Optional machine-readable claim, as for [tf_add_prediction()],
#'   which [tf_entailments()] reads against the causal graph.
#' @param source_doi Optional DOI of the work that establishes it.
#' @return The theory with the phenomenon added.
#' @examples
#' tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_phenomenon("ph1", "Arousal and avoidance covary.",
#'                     claim = list(kind = "association", x = "c_arousal",
#'                                  y = "c_avoidance", sign = "positive"))
#' @export
tf_add_phenomenon <- function(theory, id, statement, claim = NULL, source_doi = NULL) {
  ph <- list(id = id, statement = statement)
  if (!is.null(claim)) {
    claim <- if (is.list(claim)) claim else as.list(claim)
    if (!is.null(claim$given)) claim$given <- .tf_str_vec(claim$given)
    ph$claim <- claim
  }
  if (!is.null(source_doi)) ph$source_doi <- source_doi
  .tf_add(theory, "phenomena", ph, "tf_add_phenomenon", id)
}

#' Add an auxiliary assumption
#'
#' Appends an auxiliary assumption and a provenance entry. R does not change
#' the theory in place, so assign the result.
#'
#' @param theory A theory object (named list).
#' @param id,statement Assumption fields.
#' @param added_for Optional id of the prediction whose anomaly the assumption
#'   was added to answer. Leave it \code{NULL} for a core assumption.
#'   [tf_appraise_amendment()] counts an assumption added for an anomaly as ad
#'   hoc unless a corroborated prediction it protects, new in the amended
#'   version and other than the one named in \code{added_for}, exists.
#' @param protects Optional character vector of the ids of the predictions the
#'   assumption shields from refutation.
#' @return The theory with the assumption added.
#' @examples
#' tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_assumption("a1", "Measurement error is negligible.")
#' @export
tf_add_assumption <- function(theory, id, statement, added_for = NULL, protects = NULL) {
  a_item <- list(id = id, statement = statement, added_for = added_for)
  if (!is.null(protects)) a_item$protects <- .tf_str_vec(protects)
  .tf_add(theory, "auxiliary_assumptions", a_item, "tf_add_assumption", id)
}

#' Record published evidence on a prediction
#'
#' Appends an evidence entry and a provenance entry. R does not change the
#' theory in place, so assign the result.
#'
#' @param theory A theory object (named list).
#' @param supports The id of the prediction the evidence bears on.
#' @param direction One of \code{"corroborates"}, \code{"refutes"} or
#'   \code{"mixed"}.
#' @param source_doi Optional DOI of the work, stored as null when not given.
#' @return The theory with the evidence added.
#' @examples
#' tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_evidence("h1", "corroborates", source_doi = "10.1037/0033-295X.94.2.115")
#' @export
tf_add_evidence <- function(theory, supports, direction, source_doi = NULL) {
  e <- list(supports = supports, source_doi = source_doi, direction = direction)
  .tf_add(theory, "evidence", e, "tf_add_evidence", supports)
}

#' Record the outcome of a test of a prediction
#'
#' Appends a test outcome and a provenance entry. R does not change the theory
#' in place, so assign the result.
#'
#' @param theory A theory object (named list).
#' @param prediction_id The id of the prediction tested.
#' @param passed \code{TRUE} or \code{FALSE}.
#' @param observed Optional description of the result.
#' @param estimate,se Optional estimate and standard error, given together,
#'   which [tf_post_data_severity()] reads with the prediction's bounds.
#' @param registered Optional reference to the preregistration of the test.
#' @param date Optional date of the test.
#' @return The theory with the outcome added.
#' @examples
#' tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_test_outcome("h1", TRUE, observed = "switch cost 41 ms (SE 6)",
#'                       estimate = 41, se = 6)
#' @export
tf_add_test_outcome <- function(theory, prediction_id, passed, observed = NULL, estimate = NULL,
                                se = NULL, registered = NULL, date = NULL) {
  t_item <- list(prediction_id = prediction_id, passed = passed)
  if (!is.null(observed)) t_item$observed <- observed
  if (!is.null(estimate)) t_item$estimate <- estimate
  if (!is.null(se)) t_item$se <- se
  if (!is.null(registered)) t_item$registered <- registered
  if (!is.null(date)) t_item$date <- date
  .tf_add(theory, "test_outcomes", t_item, "tf_add_test_outcome", prediction_id)
}

#' Set the formal model
#'
#' Declares the theory's formal model and adds a provenance entry. A formal
#' model declared earlier is replaced. R does not change the theory in place,
#' so assign the result.
#'
#' @param theory A theory object (named list).
#' @param type Formal-model type, one of \code{"ode"}, \code{"abm"},
#'   \code{"network"}, \code{"sem"} or \code{"none"}. Any but \code{"none"}
#'   passes the checklist's formalisation item.
#' @param spec_ref Optional reference to the model specification.
#' @return The theory with the formal model set.
#' @examples
#' tf_theory("demo-1", "A demonstration theory") |>
#'   tf_set_formal_model("ode", spec_ref = "models/panic.ode")
#' @export
tf_set_formal_model <- function(theory, type, spec_ref = NULL) {
  .tf_coll(theory, "provenance")
  theory$formal_model <- list(type = type, spec_ref = spec_ref)
  .tf_provenance_append(theory, "tf_set_formal_model", type)
}
