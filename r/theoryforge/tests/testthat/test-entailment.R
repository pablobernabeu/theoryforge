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
  expect_match(doc, paste0("   - Rivals it discriminates: alt_grounding_by_interaction ",
                           "(its propositions contradict the claim)"), fixed = TRUE)
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
    rec <- tf_entailments(t)$claims[[1]]
    if (rec$verdict == "not_evaluated") next
    g <- dagitty::dagitty(paste0("dag { ", paste(c(nodes, lines), collapse = "; "), " }"))
    sets <- dagitty::adjustmentSets(g, exposure = xy[[1]], outcome = xy[[2]], type = "minimal")
    if (!rec$identified) {
      expect_length(sets, 0L)
    } else {
      z <- unlist(rec$adjustment)
      if (is.null(z)) z <- character(0)
      expect_true(dagitty::isAdjustmentSet(g, z, exposure = xy[[1]], outcome = xy[[2]]))
      expect_equal(length(z), min(lengths(sets)))
    }
  }
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
