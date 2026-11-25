# The causal reading of API_SPEC.md Part J: entailments, equivalent models and
# rivals. The Python suite's test_entailment.py holds the same cases.

modality <- function() tf_read(tf_example_path("modality-switching.theory.yaml"))

small_theory <- function(props, claims = list(), alternatives = list(), k = 4L) {
  list(
    schema_version = "1.1", id = "t", title = "t", maturity = "developing",
    constructs = lapply(seq_len(k) - 1L, function(i) {
      list(id = paste0("c", i), label = paste0("c", i), definition = "d")
    }),
    propositions = lapply(seq_along(props), function(i) {
      list(id = paste0("p", i - 1L), from = props[[i]][[1]], to = props[[i]][[2]],
           relation = props[[i]][[3]])
    }),
    predictions = lapply(seq_along(claims), function(i) {
      list(id = paste0("q", i - 1L), statement = "s", type = "directional",
           derives_from = list("p0"), claim = claims[[i]])
    }),
    alternatives = alternatives
  )
}

claim <- function(kind, x, y, sign, given = NULL) {
  out <- list(kind = kind, x = x, y = y, sign = sign)
  if (!is.null(given)) out$given <- as.list(given)
  out
}

test_that("the example entails its four claims", {
  e <- tf_entailments(modality())
  expect_equal(e$counts, list(entailed = 4L, contradicted = 0L, undetermined = 0L,
                              not_evaluated = 0L))
  got <- vapply(e$claims, function(c) {
    paste(c$id, c$derived, c$basis, paste(unlist(c$via), collapse = "+"))
  }, "")
  expect_equal(got, c("pred1 positive paths_agree p2", "pred3 positive paths_agree p3",
                      "pred4 zero no_path ", "ph1 positive paths_agree p1+p3"))
})

test_that("the example has two directions no observational study can test", {
  eq <- tf_equivalent_models(modality())
  expect_true(eq$computed)
  expect_equal(vapply(eq$edges, function(e) e$status, ""),
               c("reversible", "reversible", "compelled", "compelled"))
  expect_equal(eq$v_structures[[1]]$collider, "c_conceptual_access")
})

test_that("each rival is told apart by the claims that name it", {
  t <- modality()
  gbi <- tf_discriminate(t, "alt_grounding_by_interaction")
  found <- Filter(function(c) c$discriminates, gbi$claims)
  expect_equal(vapply(found, function(c) c$id, ""), c("pred3", "ph1"))
  expect_false(gbi$markov_equivalent)
  expect_equal(gbi$counts, list(discriminating_claims = 2L, independencies = 4L,
                                decisive_effects = 6L, decisive_associations = 3L))
  si <- tf_discriminate(t, "alt_symbol_interdependency")
  expect_true(is.na(si$markov_equivalent))
  expect_equal(si$independencies[[1]]$statement,
               "c_sensorimotor_experience _||_ c_lexical_familiarity")
})

test_that("signs multiply along a path and unsigned relations leave it open", {
  t <- small_theory(list(c("c0", "c1", "increases"), c("c1", "c2", "decreases"),
                         c("c2", "c3", "causes")),
                    claims = list(claim("effect", "c0", "c2", "negative"),
                                  claim("effect", "c0", "c3", "positive"),
                                  claim("effect", "c3", "c0", "zero"),
                                  claim("effect", "c0", "c3", "nonzero")))
  got <- vapply(tf_entailments(t)$claims, function(c) {
    paste(c$derived, c$verdict, c$basis, c$faithfulness)
  }, "")
  expect_equal(got, c("negative entailed paths_agree FALSE",
                      "undetermined undetermined unsigned FALSE",
                      "zero entailed no_path FALSE",
                      "undetermined entailed unsigned TRUE"))
})

test_that("a common cause signs an association and a collider leaves none", {
  t <- small_theory(list(c("c0", "c1", "increases"), c("c0", "c2", "decreases"),
                         c("c1", "c3", "increases"), c("c2", "c3", "increases")),
                    claims = list(claim("association", "c1", "c2", "negative"),
                                  claim("association", "c1", "c2", "zero", given = "c0"),
                                  claim("association", "c1", "c2", "zero", given = c("c0", "c3"))))
  e <- tf_entailments(t)$claims
  expect_equal(e[[1]]$derived, "negative")
  expect_equal(unlist(e[[1]]$via), c("p0", "p1"))
  expect_equal(e[[2]]$basis, "separated")
  expect_equal(c(e[[3]]$verdict, e[[3]]$faithfulness), c("contradicted", "TRUE"))
})

test_that("a claim that cannot be read is not evaluated", {
  t <- small_theory(list(c("c0", "c1", "increases"), c("c1", "c0", "increases")),
                    claims = list(claim("effect", "c0", "c1", "positive"),
                                  claim("effect", "c0", "c2", "positive"),
                                  claim("effect", "c0", "c0", "positive"),
                                  list()))
  expect_equal(vapply(tf_entailments(t)$claims, function(c) c$basis, ""),
               c("feedback_loop", "not_in_graph", "malformed_claim"))
  expect_equal(tf_entailments(t, cycles = "sigma")$claims[[1]]$verdict, "entailed")
  expect_error(tf_entailments(t, cycles = "loops"), "requires cycles to be 'refuse' or 'sigma'")
})

test_that("a reversed chain is Markov equivalent but differs in its effects", {
  t <- small_theory(list(c("c0", "c1", "increases"), c("c1", "c2", "increases")),
                    alternatives = list(list(id = "a", label = "r", propositions = list(
                      list(id = "r1", from = "c1", to = "c0", relation = "increases"),
                      list(id = "r2", from = "c2", to = "c1", relation = "increases")))))
  d <- tf_discriminate(t, "a")
  expect_true(d$markov_equivalent)
  expect_length(d$independencies, 0L)
  effects <- vapply(d$effects, function(e) paste(e$x, e$y, e$theory, e$rival), "")
  expect_true(all(c("c0 c2 positive zero", "c2 c0 zero positive") %in% effects))
  expect_error(tf_discriminate(t, "b"), "no alternative 'b'")
})

test_that("a rival over other constructs is projected", {
  t <- small_theory(list(c("c0", "c1", "increases"), c("c1", "c2", "increases")))
  rival <- small_theory(list(c("c0", "c3", "increases"), c("c3", "c2", "increases"),
                             c("c1", "c2", "increases")))
  d <- tf_discriminate(t, rival)
  expect_equal(d$independence_basis, "projected")
  expect_equal(unlist(d$only_rival), "c3")
  expect_equal(vapply(d$independencies, function(i) paste(i$statement, i$implied_by), ""),
               c("c0 _||_ c1 rival", "c0 _||_ c2 | c1 theory"))
})

test_that("a contradicted or open claim breaks the derivation chain", {
  props <- list(c("c0", "c1", "increases"), c("c1", "c2", "causes"))
  item <- function(t, id) Filter(function(i) i$id == id, tf_check(t)$items)[[1]]$status
  expect_equal(item(small_theory(props, list(claim("effect", "c0", "c1", "positive"))),
                    "derivation_chain"), "pass")
  expect_equal(item(small_theory(props, list(claim("effect", "c0", "c1", "negative"))),
                    "derivation_chain"), "fail")
  expect_equal(item(small_theory(props, list(claim("effect", "c0", "c2", "positive"))),
                    "derivation_chain"), "fail")
})

test_that("a rival that agrees on the claim does not count as discriminated", {
  rival <- function(rel) {
    list(list(id = "a", label = "r",
              propositions = list(list(id = "r1", from = "c0", to = "c1", relation = rel))))
  }
  item <- function(t) Filter(function(i) i$id == "diagnosticity", tf_check(t)$items)[[1]]$status
  t <- small_theory(list(c("c0", "c1", "increases")), list(claim("effect", "c0", "c1", "positive")),
                    alternatives = rival("increases"))
  t$predictions[[1]]$diagnostic_vs <- list("a")
  expect_equal(item(t), "warn")
  t$alternatives <- rival("decreases")
  expect_equal(item(t), "pass")
})

test_that("the preregistration and the dossier report the causal reading", {
  t <- modality()
  doc <- tf_preregister(t)
  expect_match(doc, "- Derivations check: yes", fixed = TRUE)
  expect_match(doc, paste0("   - Rivals it is declared to discriminate: ",
                           "alt_grounding_by_interaction (its propositions contradict the claim)"),
               fixed = TRUE)
  dossier <- tf_dossier(t)
  expect_match(dossier, "\n## Preregistration\n\n## Preregistration: Modality switching", fixed = TRUE)
  expect_match(dossier, paste0("- p2: c_modality_activation -> c_switch_cost ",
                               "(reversed in some equivalent model)"), fixed = TRUE)
})

test_that("full validation reports each fault of a claim", {
  t <- small_theory(list(c("c0", "c1", "increases")),
                    claims = list(list(kind = "effect", x = "c0", y = "c0", sign = "up",
                                       given = list("c1"), note = 1),
                                  "c0 raises c1"))
  msg <- tryCatch(tf_validate(t, full = TRUE), error = conditionMessage)
  expect_equal(strsplit(sub("^invalid theory object: ", "", msg), "; ")[[1]], c(
    "prediction[0] claim has unknown field: note",
    "prediction[0] claim sign 'up' not allowed",
    "prediction[0] claim x and y must differ",
    "prediction[0] claim given applies only to an association",
    "prediction[1] claim must be a mapping"))
})

test_that("the builders record claims, phenomena, rivals, evidence and outcomes", {
  t <- tf_theory("b", "Built") |>
    tf_add_construct("c0", "A", "a.") |>
    tf_add_construct("c1", "B", "b.") |>
    tf_add_proposition("p1", "c0", "c1", "increases", functional_form = "monotonic") |>
    tf_add_prediction("h1", "A raises B.", "directional", derives_from = c(first = "p1"),
                      diagnostic_vs = "r", bounds = list(lower = 0, upper = NULL),
                      claim = list(kind = "effect", x = "c0", y = "c1", sign = "positive")) |>
    tf_add_alternative("r", "Reverse", source_doi = "10.1/x", propositions = list(
      list(id = "r1", from = "c1", to = "c0", relation = "increases"))) |>
    tf_add_phenomenon("ph", "A and B covary.",
                      claim = list(kind = "association", x = "c0", y = "c1", sign = "positive")) |>
    tf_add_evidence("h1", "corroborates", source_doi = "10.1/y") |>
    tf_add_test_outcome("h1", TRUE, estimate = 0.3, se = 0.1, registered = "osf.io/x")
  expect_true(tf_validate(t, full = TRUE))
  expect_null(names(t$predictions[[1]]$derives_from))
  expect_equal(t$schema_version, "1.1")
  expect_equal(vapply(tail(t$provenance, 3L), function(p) p$action, ""),
               c("tf_add_phenomenon", "tf_add_evidence", "tf_add_test_outcome"))
  expect_equal(tf_discriminate(t, "r")$counts$discriminating_claims, 1L)
  expect_error(tf_add_construct(list(constructs = list(a = 1)), "c", "C", "c."),
               "cannot add to 'constructs': the theory holds a mapping there, not a list",
               fixed = TRUE)
})

test_that("an effect claim names a smallest adjustment set", {
  confounded <- small_theory(list(c("c0", "c1", "increases"), c("c0", "c2", "increases"),
                                  c("c1", "c2", "increases"), c("c3", "c1", "increases")),
                             claims = list(claim("effect", "c1", "c2", "positive"),
                                           claim("association", "c1", "c2", "positive")))
  e <- tf_entailments(confounded)$claims
  expect_true(e[[1]]$identified)
  expect_equal(unlist(e[[1]]$adjustment), "c0")
  expect_true(is.na(e[[2]]$identified))
  bow <- small_theory(list(c("c0", "c1", "increases"), c("c0", "c1", "associates")),
                      claims = list(claim("effect", "c0", "c1", "positive")))
  expect_false(tf_entailments(bow)$claims[[1]]$identified)
  expect_match(tf_preregister(confounded), "   - Adjustment for an observational test: c0\n",
               fixed = TRUE)
})

test_that("each adjustment set is one dagitty accepts, of the smallest size", {
  # Some constructs are marked latent, which dagitty reads from the same mark
  # and neither adjusts for.
  skip_if_not_installed("dagitty")
  set.seed(5)
  for (rep in 1:150) {
    k <- sample(2:6, 1)
    nodes <- paste0("c", seq_len(k) - 1L)
    order <- sample(nodes)
    props <- list()
    lines <- character(0)
    for (i in seq_len(k - 1L)) {
      for (j in (i + 1L):k) {
        a <- order[[i]]
        b <- order[[j]]
        u <- stats::runif(1)
        if (u < 0.45) {
          props[[length(props) + 1L]] <- c(a, b, "increases")
          lines <- c(lines, paste(a, "->", b))
        } else if (u < 0.55) {
          props[[length(props) + 1L]] <- c(a, b, "associates")
          lines <- c(lines, paste(a, "<->", b))
        }
      }
    }
    if (length(props) == 0L) next
    xy <- sample(nodes, 2)
    t <- small_theory(props, claims = list(claim("effect", xy[[1]], xy[[2]], "positive")), k = k)
    latent <- setdiff(nodes[stats::runif(k) < 0.2], xy)
    for (i in seq_along(t$constructs)) {
      if (t$constructs[[i]]$id %in% latent) t$constructs[[i]]$x_latent <- TRUE
    }
    rec <- tf_entailments(t)$claims[[1]]
    if (rec$verdict == "not_evaluated") next
    marks <- if (length(latent)) paste(latent, "[latent]") else character(0)
    g <- dagitty::dagitty(paste0("dag { ", paste(c(nodes, marks, lines), collapse = "; "), " }"))
    sets <- dagitty::adjustmentSets(g, exposure = xy[[1]], outcome = xy[[2]], type = "minimal")
    if (!rec$identified) {
      expect_length(sets, 0L)
    } else {
      z <- unlist(rec$adjustment)
      if (is.null(z)) z <- character(0)
      expect_false(any(z %in% latent))
      expect_true(dagitty::isAdjustmentSet(g, z, exposure = xy[[1]], outcome = xy[[2]]))
      expect_equal(length(z), min(lengths(sets)))
    }
  }
})

test_that("a construct marked latent is never adjusted for", {
  # dagitty finds no adjustment set for the first graph and {w} for the
  # second. The Python suite asserts the same records.
  read <- function(text) {
    t <- tf_add_prediction(tf_read_dagitty(text), "h1", "x raises y.", "directional",
                           claim = list(kind = "effect", x = "x", y = "y", sign = "positive"))
    list(t, tf_entailments(t)$claims[[1]])
  }
  first <- read("dag { u [latent]; u -> x; u -> y; x -> y }")
  expect_identical(first[[2]][c("identified", "adjustment")], list(identified = FALSE, adjustment = NA))
  expect_match(tf_preregister(first[[1]]), "   - Adjustment for an observational test: none suffices\n")
  second <- read("dag { u [latent]; u -> w -> x; u -> y; x -> y }")
  expect_identical(unlist(second[[2]]$adjustment), "w")
})

test_that("a canonical set of more than 12 constructs is pruned to a minimal one", {
  # The Python suite asserts the same records.
  many <- function(edges) {
    names <- c(paste0("a", 1:13), "c", "x", "y")
    t <- tf_theory("m", "M")
    for (n in names) t <- tf_add_construct(t, n, n, "A construct.")
    for (i in seq_along(edges)) {
      t <- tf_add_proposition(t, paste0("p", i), edges[[i]][[1]], edges[[i]][[2]], "increases")
    }
    tf_add_prediction(t, "h1", "x raises y.", "directional", derives_from = "p1",
                      claim = list(kind = "effect", x = "x", y = "y", sign = "positive"))
  }
  direct <- many(c(lapply(1:13, function(i) c(paste0("a", i), "x")), list(c("x", "y"))))
  rec <- tf_entailments(direct)$claims[[1]]
  expect_true(rec$identified)
  expect_length(rec$adjustment, 0L)
  expect_match(tf_preregister(direct), "   - Adjustment for an observational test: none needed\n")
  confounded <- many(c(lapply(1:13, function(i) c(paste0("a", i), "c")),
                       list(c("c", "x"), c("c", "y"), c("x", "y"))))
  expect_identical(unlist(tf_entailments(confounded)$claims[[1]]$adjustment), "c")
})

test_that("a pruned adjustment set is one dagitty accepts and none of its members can go", {
  # Fifteen constructs upstream of x and y give a canonical set of more than 12
  # members, which is pruned in one pass.
  skip_if_not_installed("dagitty")
  set.seed(12)
  pruned <- 0L
  for (rep in 1:20) {
    up <- paste0("c", 0:14)
    nodes <- c(up, "x", "y")
    props <- list(c("x", "y", "increases"))
    for (i in seq_along(up)) {
      for (j in seq_along(up)) {
        u <- stats::runif(1)
        if (i < j && u < 0.15) props[[length(props) + 1L]] <- c(up[[i]], up[[j]], "increases")
        if (i < j && u > 0.97) props[[length(props) + 1L]] <- c(up[[i]], up[[j]], "associates")
      }
      for (end in c("x", "y")) {
        if (stats::runif(1) < 0.5) props[[length(props) + 1L]] <- c(up[[i]], end, "increases")
      }
    }
    t <- small_theory(props, claims = list(claim("effect", "x", "y", "positive")), k = 0L)
    t$constructs <- lapply(nodes, function(n) list(id = n, label = n, definition = "d"))
    rec <- tf_entailments(t)$claims[[1]]
    if (!isTRUE(rec$identified)) next
    pruned <- pruned + 1L
    lines <- vapply(props, function(p) paste(p[[1]], if (p[[3]] == "associates") "<->" else "->", p[[2]]), "")
    g <- dagitty::dagitty(paste0("dag { ", paste(c(nodes, lines), collapse = "; "), " }"))
    z <- as.character(unlist(rec$adjustment))
    expect_true(dagitty::isAdjustmentSet(g, z, exposure = "x", outcome = "y"))
    for (v in z) expect_false(dagitty::isAdjustmentSet(g, setdiff(z, v), exposure = "x", outcome = "y"))
  }
  expect_gt(pruned, 10L)
})

test_that("the content hash is SHA-256 of the canonical form", {
  # The standard test vectors of FIPS 180-4, one of them longer than a block.
  sha <- function(s) theoryforge:::.tf_sha256(charToRaw(s))
  expect_equal(sha("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  expect_equal(sha(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  expect_equal(sha("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
               "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
  canon <- theoryforge:::.tf_canonical
  expect_equal(canon(list(b = 1, a = list(1e21, 1e-7, 0.1, -0, 100L, TRUE, NULL))),
               '{"a":[1e+21,1e-7,0.1,0,100,true,null],"b":1}')
  expect_equal(canon(list(x = "q\"\\\né", y = list(), z = setNames(list(), character(0)))),
               '{"x":"q\\"\\\\\\né","y":[],"z":[]}')
  t <- modality()
  h <- tf_content_hash(t)
  expect_match(h, "^sha256:[0-9a-f]{64}$")
  t$version$content_hash <- h
  expect_identical(tf_content_hash(t), h)
  t$constructs <- rev(t$constructs)
  expect_false(identical(tf_content_hash(t), h))
})

test_that("the SHA-256 written in R agrees with the one R provides", {
  # From R 4.5, .tf_sha256() hands the bytes to tools::sha256sum(), so the
  # version in R alone, which earlier versions use, is checked here: against
  # the FIPS 180-4 vectors, against .tf_sha256() at the lengths where the
  # padding takes a second block, and on the canonical form of each example.
  sha_r <- theoryforge:::.tf_sha256_r
  expect_equal(sha_r(charToRaw("abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  expect_equal(sha_r(raw(0)), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  expect_equal(sha_r(charToRaw("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")),
               "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
  for (n in c(55L, 56L, 63L, 64L, 119L, 120L, 1000L)) {
    bytes <- as.raw((seq_len(n) * 37L) %% 256L)
    expect_identical(sha_r(bytes), theoryforge:::.tf_sha256(bytes))
  }
  for (f in c("panic-network.theory.yaml", "panic-network-2026-v2.theory.yaml",
              "modality-switching.theory.yaml", "weak-theory.theory.yaml")) {
    t <- tf_read(tf_fixture_path(f))
    data <- t
    if (is.list(data$version)) data$version$content_hash <- NULL
    data <- theoryforge:::.tf_box_string_arrays(theoryforge:::.tf_na_as_null(data))
    bytes <- charToRaw(enc2utf8(theoryforge:::.tf_canonical(data)))
    expect_identical(paste0("sha256:", sha_r(bytes)), tf_content_hash(t))
  }
})

singletons <- 'schema_version: "1.1"
id: singletons
title: A theory with single values in string arrays
maturity: building
boundary_conditions: adults
constructs:
  - id: c1
    label: Arousal
    definition: Bodily activation.
    measurement: self-report scale
  - id: c2
    label: Threat
    definition: Appraised danger.
propositions:
  - {id: p1, from: c1, to: c2, relation: increases}
predictions:
  - id: h1
    statement: Threat rises with arousal.
    type: directional
    derives_from: p1
'

test_that("the content hash reads a single string as a one-element array", {
  # API_SPEC section 34: a single value in a field the schema types as an array
  # of strings is written as a one-element array, as the singleton rule reads
  # it, so the theory keeps its hash when tf_write() writes the field as an
  # array. The Python suite asserts the same digest.
  scalar <- tempfile(fileext = ".yaml")
  writeLines(singletons, scalar)
  boxed <- tempfile(fileext = ".yaml")
  text <- sub("adults", "[adults]", singletons, fixed = TRUE)
  text <- sub("self-report scale", "[self-report scale]", text, fixed = TRUE)
  writeLines(sub("derives_from: p1", "derives_from: [p1]", text, fixed = TRUE), boxed)
  h <- "sha256:5974774a777a33875a5d94eeebaf466fcd7c41071991d65591d44116699ea71d"
  expect_identical(tf_content_hash(tf_read(scalar)), h)
  expect_identical(tf_content_hash(tf_read(boxed)), h)
  # A theory built in memory holds a one-element character vector there.
  t <- tf_read(boxed)
  t$constructs[[1]]$measurement <- "self-report scale"
  t$predictions[[1]]$derives_from <- "p1"
  expect_identical(tf_content_hash(t), h)
  # NA is null and is not boxed, so it hashes as NULL does.
  t$constructs[[1]]$measurement <- NA
  na <- tf_content_hash(t)
  t$constructs[[1]]["measurement"] <- list(NULL)
  expect_identical(tf_content_hash(t), na)
  # A version key that only partly matches "version" is not the version.
  t$version_note <- list(content_hash = "x")
  t2 <- t
  t2$version_note$content_hash <- "y"
  expect_false(identical(tf_content_hash(t), tf_content_hash(t2)))
})

test_that("the canonical form keeps the shortest digits that read back as the number", {
  # R's parser reads -527.867953 one unit in the last place away, so testing
  # the digits with as.numeric() wrote -527.8679530000001, and it took too few
  # digits for the second number and too many for the third. The numbers are
  # read here as a theory file's would be. The Python suite asserts the same
  # text.
  text <- c("-527.867953", "1.7839211372708861e-265", "-3.06405467662112e+212",
            "3.343559332129407e-41")
  x <- jsonlite::parse_json(paste0("[", paste(text, collapse = ","), "]"),
                            simplifyVector = TRUE)
  expect_identical(theoryforge:::.tf_canonical(as.list(x)),
                   paste0("[", paste(text, collapse = ","), "]"))
  # Beside a power of two the nearest 16-digit decimal of 2^-24 does not read
  # back, while the one above it does, and ECMAScript takes it.
  expect_identical(theoryforge:::.tf_canonical(list(2^-24, 2^-44, 2^89)),
                   "[5.960464477539063e-8,5.684341886080802e-14,6.189700196426902e+26]")
})

test_that("an effect under sigma counts no walk back through the intervened construct", {
  # r lowers f and f raises r. Intervening on r replaces r's own equation, so
  # the loop back through r carries nothing, and the effect is the direct,
  # negative one. The Python suite asserts the same record.
  t <- tf_theory("rf", "RF") |>
    tf_add_construct("r", "R", "a.") |>
    tf_add_construct("f", "F", "b.") |>
    tf_add_proposition("p1", "r", "f", "decreases") |>
    tf_add_proposition("p2", "f", "r", "increases") |>
    tf_add_prediction("h1", "R lowers F.", "directional", derives_from = "p1",
                      claim = list(kind = "effect", x = "r", y = "f", sign = "negative"))
  rec <- tf_entailments(t, cycles = "sigma")$claims[[1]]
  expect_identical(list(rec$derived, rec$verdict, unlist(rec$via)),
                   list("negative", "entailed", "p1"))
})

test_that("the causal_dag export keeps an association between constructs no arrow names", {
  t <- tf_theory("a", "A")
  for (cid in c("x", "y", "z", "w")) t <- tf_add_construct(t, cid, toupper(cid), "A construct.")
  t <- t |>
    tf_add_proposition("p1", "x", "y", "causes") |>
    tf_add_proposition("p2", "z", "w", "associates")
  expect_identical(tf_diagram(t, "causal_dag"), "dag {\n  x -> y\n  z <-> w\n}\n")
  expect_identical(unlist(tf_implications(t)$constructs), c("x", "y", "z", "w"))
})

test_that("an association of a construct with itself adds nothing, though no other proposition names it", {
  # c2 is related to no other construct, so it is no vertex. Looking it up
  # anyway failed before the association was skipped. The Python suite asserts
  # the same records.
  t <- small_theory(list(c("c0", "c1", "increases"), c("c2", "c2", "associates")),
                    claims = list(claim("effect", "c0", "c1", "negative")), k = 3L)
  t$predictions[[1]]$diagnostic_vs <- list("r")
  t$alternatives <- list(list(id = "r", label = "r", propositions = list(
    list(id = "r1", from = "c0", to = "c1", relation = "increases"),
    list(id = "r2", from = "c2", to = "c2", relation = "associates"))))
  imp <- tf_implications(t)
  expect_identical(list(unlist(imp$constructs), imp$n_bidirected, imp$n_implications),
                   list(c("c0", "c1"), 0L, 0L))
  expect_identical(tf_entailments(t)$claims[[1]]$verdict, "contradicted")
  expect_true(tf_equivalent_models(t)$computed)
  expect_true(tf_discriminate(t, "r")$markov_equivalent)
  status <- function(t, id) Filter(function(i) i$id == id, tf_check(t)$items)[[1]][c("status", "score")]
  expect_identical(status(t, "derivation_chain"), list(status = "fail", score = 0))
  expect_identical(status(t, "diagnosticity"), list(status = "warn", score = 0))
  expect_match(tf_preregister(t), "contradicted by the causal graph", fixed = TRUE)
  expect_match(tf_dossier(t), "- r: claims it discriminates: none", fixed = TRUE)
  expect_true(tf_appraise_amendment(t, t)$implications_compared)
  # The same association stated by the rival alone.
  t$propositions[[2]] <- NULL
  expect_identical(status(t, "diagnosticity"), list(status = "warn", score = 0))
})

test_that("a refusal of the causal graph has its own class, and nothing else is read as one", {
  # The functions that report a refusal in place of a result catch this class
  # alone, as the Python twin catches ValueError alone.
  expect_error(tf_entailments(small_theory(list()), cycles = "loops"), class = "tf_refusal")
  expect_error(tf_implications(small_theory(list(c("c0", "c9", "causes")))),
               "proposition 'p0' refers to unknown construct 'c9'", class = "tf_refusal")
  expect_error(tf_implications(small_theory(list(c("c0", "c1", "causes"), c("c1", "c0", "causes")))),
               "implications requires an acyclic causal graph", class = "tf_refusal")
  expect_error(tf_discriminate(small_theory(list()), "r"), class = "tf_refusal")
  # .tf_prepare_graph() runs inside the catch of each such function, so an
  # error it raises that is not a refusal must reach the caller.
  t <- small_theory(list(c("c0", "c1", "increases")), claims = list(claim("effect", "c0", "c1", "positive")))
  local_mocked_bindings(.tf_prepare_graph = function(...) stop("an internal fault"))
  expect_error(tf_check(t), "an internal fault")
  expect_error(tf_preregister(t), "an internal fault")
  expect_error(tf_dossier(t), "an internal fault")
  expect_error(tf_appraise_amendment(t, t), "an internal fault")
})

test_that("a marginal association takes the signs of the simple treks alone", {
  # c0 -> c1 -> c2 is also the trek c1 <- c0 -> c1 -> c2, whose two paths share
  # c0 -> c1. Its term holds that coefficient squared, so it adds no sign, and
  # the association of c1 and c2 is positive whatever c0 does to c1 (Wright,
  # 1934). The Python suite asserts the same records.
  read <- function(props, cl) {
    rec <- tf_entailments(small_theory(props, claims = list(cl)))$claims[[1]]
    paste(rec$derived, rec$verdict, rec$basis)
  }
  pos <- claim("association", "c1", "c2", "positive")
  expect_identical(read(list(c("c0", "c1", "causes"), c("c1", "c2", "increases")), pos),
                   "positive entailed paths_agree")
  expect_identical(read(list(c("c0", "c1", "causes"), c("c1", "c2", "increases")),
                        claim("association", "c2", "c1", "positive")),
                   "positive entailed paths_agree")
  expect_identical(read(list(c("c0", "c1", "increases"), c("c0", "c3", "increases"),
                             c("c3", "c1", "decreases"), c("c1", "c2", "increases")), pos),
                   "positive entailed paths_agree")
  expect_identical(read(list(c("c0", "c1", "causes"), c("c1", "c2", "increases"),
                             c("c1", "c3", "associates")), pos),
                   "positive entailed paths_agree")
  # Here c1 <- c0 -> c2 is a simple trek of no fixed sign.
  expect_identical(read(list(c("c0", "c1", "causes"), c("c0", "c2", "increases"),
                             c("c1", "c2", "increases")), pos),
                   "undetermined undetermined unsigned")
  t <- small_theory(list(c("c0", "c1", "causes"), c("c1", "c2", "increases")), claims = list(pos),
                    alternatives = list(list(id = "r", label = "r", propositions = list(
                      list(id = "r1", from = "c1", to = "c2", relation = "increases"),
                      list(id = "r2", from = "c0", to = "c2", relation = "causes")))))
  item <- Filter(function(i) i$id == "derivation_chain", tf_check(t)$items)[[1]]
  expect_identical(item$status, "pass")
  expect_false(any(vapply(tf_discriminate(t, "r")$associations,
                          function(a) a$a == "c1" && a$b == "c2", logical(1))))
})

test_that("a feedback loop that is one simple cycle leaves the signs of the paths through it", {
  # The loop of c1 and c2 has a negative gain g, and the effects through it are
  # those of the paths times 1 / (1 - g) > 0. So are those through the negative
  # self loop of c4. When c2 and c3 also raise each other, the walks from c0 to
  # c2 take both signs, and the reading stays conservative. The Python suite
  # asserts the same records.
  t <- small_theory(list(c("c0", "c1", "increases"), c("c1", "c2", "increases"),
                         c("c2", "c1", "decreases"), c("c3", "c4", "increases"),
                         c("c4", "c4", "decreases")),
                    claims = list(claim("effect", "c0", "c2", "positive"),
                                  claim("effect", "c0", "c1", "positive"),
                                  claim("association", "c0", "c2", "positive"),
                                  claim("association", "c1", "c2", "positive"),
                                  claim("effect", "c3", "c4", "positive"),
                                  claim("effect", "c2", "c1", "negative")), k = 5L)
  got <- vapply(tf_entailments(t, cycles = "sigma")$claims, function(c) paste(c$derived, c$basis), "")
  expect_identical(got, c("positive paths_agree", "positive paths_agree", "positive paths_agree",
                          "undetermined opposite_signs", "positive paths_agree",
                          "negative paths_agree"))
  shared <- small_theory(list(c("c0", "c1", "increases"), c("c1", "c2", "increases"),
                              c("c2", "c1", "decreases"), c("c2", "c3", "increases"),
                              c("c3", "c2", "increases")),
                         claims = list(claim("effect", "c0", "c2", "positive")))
  expect_identical(tf_entailments(shared, cycles = "sigma")$claims[[1]]$basis, "opposite_signs")
})

# -- large theories -------------------------------------------------------------

# A sparse DAG over the constructs c0001 to c<k>, as the Python suite builds it.
# Construct j has the parent j %/% 2, which increases it when j is even and
# decreases it otherwise, and also j - 2 when j is a multiple of 3 above 3. With
# `associate_every`, every such multiple j is associated with j - 8. Effect
# claim i is that c<3i> lowers c<6i + 1>, whose one parent it is, and
# association claim i concerns c<5i> and c<5i + 2>.
large_theory <- function(k, associate_every = 0L, effects = 0L, associations = 0L) {
  ids <- sprintf("c%04d", seq_len(k))
  props <- list()
  add <- function(a, b, relation) {
    props[[length(props) + 1L]] <<- list(id = paste0("p", length(props) + 1L), from = ids[[a]],
                                         to = ids[[b]], relation = relation)
  }
  for (j in seq_len(k)[-1L]) {
    relation <- if (j %% 2L == 0L) "increases" else "decreases"
    add(j %/% 2L, j, relation)
    if (j %% 3L == 0L && j > 3L) add(j - 2L, j, relation)
  }
  if (associate_every > 0L) {
    for (j in seq(associate_every, k, by = associate_every)) add(j, j - 8L, "associates")
  }
  claims <- c(lapply(seq_len(effects), function(i) claim("effect", ids[[3L * i]], ids[[6L * i + 1L]], "negative")),
              lapply(seq_len(associations), function(i) {
                claim("association", ids[[5L * i]], ids[[5L * i + 2L]], "positive")
              }))
  rival <- lapply(props[seq_along(props) %% 10L != 0L], function(p) {
    p$id <- paste0("r", p$id)
    p
  })
  t <- small_theory(list(), claims = claims, k = 0L,
                    alternatives = list(list(id = "rival", label = "Rival", key_constructs = list("x"),
                                             propositions = rival)))
  t$constructs <- lapply(ids, function(c) list(id = c, label = c, definition = "d"))
  t$propositions <- props
  t
}

test_that("the causal reading finds the reachability of each graph once", {
  # Finding the reachability of the whole graph again for each claim, or
  # searching each pair of a DAG, made the causal reading of a large theory take
  # minutes. The calls are counted, so the test does not depend on the speed of
  # the machine. The Python suite counts the same calls.
  k <- 120L
  t <- large_theory(k, effects = 15L, associations = 10L)
  sizes <- integer(0)
  searches <- 0L
  reach <- theoryforge:::.tf_reach
  m_separated <- theoryforge:::.tf_m_separated
  local_mocked_bindings(
    .tf_reach = function(directed, k) {
      sizes <<- c(sizes, k)
      reach(directed, k)
    },
    .tf_m_separated = function(...) {
      searches <<- searches + 1L
      m_separated(...)
    }
  )
  e <- tf_entailments(t)
  expect_identical(e$counts$not_evaluated, 0L)
  expect_identical(sum(sizes == k), 1L)
  sizes <- integer(0)
  # R reads the ancestors of the two views compared from their reachability
  # too, so a large graph is closed at most four times here.
  d <- tf_discriminate(t, "rival")
  expect_true(d$evaluated && length(d$effects) > 0L)
  expect_lte(sum(sizes > 100L), 4L)
  searches <- 0L
  res <- tf_implications(t)
  expect_identical(searches, 0L)
  m <- length(t$propositions)
  expect_identical(res$n_implications, (k * (k - 1L)) %/% 2L - m)
})

test_that("a theory of several hundred constructs is read in full", {
  # Before the search kept to the ancestors and the claims to the reachability
  # found once, each of these calls took minutes. The Python suite asserts the
  # same records.
  skip_on_cran()
  t <- large_theory(300L, associate_every = 9L)
  res <- tf_implications(t)
  joined <- unique(vapply(t$propositions, function(p) paste(sort(c(p$from, p$to)), collapse = "~"), ""))
  expect_identical(res$n_bidirected, 33L)
  expect_identical(res$n_implications + length(res$inseparable), (300L * 299L) %/% 2L - length(joined))
  big <- large_theory(1000L, effects = 30L, associations = 20L)
  claims <- tf_entailments(big)$claims
  effects <- Filter(function(c) c$kind == "effect", claims)
  expect_length(effects, 30L)
  to <- vapply(big$propositions, function(p) p$to, "")
  for (c in effects) {
    edge <- big$propositions[[match(c$y, to)]]$id
    expect_identical(list(c$derived, c$verdict, c$via), list("negative", "entailed", list(edge)))
    expect_identical(list(c$identified, c$adjustment), list(TRUE, list()))
  }
  expect_false(any(vapply(claims, function(c) c$verdict == "not_evaluated", logical(1))))
  eq <- tf_equivalent_models(big)
  # Every multiple j of 3 from 6 on is the collider of c<j %/% 2> and c<j - 2>.
  expect_length(eq$v_structures, 1000L %/% 3L - 1L)
  expect_identical(eq$n_compelled + eq$n_reversible, length(big$propositions))
  status <- vapply(eq$edges, function(e) e$status, "")
  compelled <- vapply(eq$edges, function(e) paste(e$from, e$to), "")[status == "compelled"]
  for (v in eq$v_structures) {
    expect_true(all(c(paste(v$a, v$collider), paste(v$b, v$collider)) %in% compelled))
  }
})
