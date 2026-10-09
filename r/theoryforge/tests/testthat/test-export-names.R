# Identifiers in the two exports that other tools read (API_SPEC.md sections 5
# and 19). The causal_dag view is read by dagitty and drawn by the apps with
# Graphviz, and tf_compile_sem()'s syntax is read by lavaan. A construct id is
# free text, so both exports write each id in a form those tools read as
# written, and tf_compile_sem() refuses two names that would merge.
# test_export_names.py asserts the same outputs and messages in Python, and the
# dagitty and lavaan checks are R's alone. Non-ASCII text is written with \u
# escapes, so the file reads the same in every locale.

# A theory from list(id, measurement) and list(id, from, to, relation) entries.
.ids_theory <- function(constructs, propositions = list(), id = "ids") {
  theory <- tf_theory(id, "Identifiers")
  for (con in constructs) {
    theory <- tf_add_construct(theory, con[[1L]], "Label", "A definition.",
                               measurement = con[[2L]])
  }
  for (p in propositions) {
    theory <- tf_add_proposition(theory, p[[1L]], p[[2L]], p[[3L]], p[[4L]])
  }
  theory
}

# -- causal_dag -----------------------------------------------------------------

.dag_ids <- c("self-efficacy", "task persistence", "1arousal", "a.b", "c_\u00e4rger",
              "NA", "if", "edge", "Node", 'say "hi"', "x\\y")

.quoting_theory <- function() {
  .ids_theory(lapply(.dag_ids, function(x) list(x, NULL)), list(
    list("p1", "self-efficacy", "task persistence", "increases"),
    list("p2", "1arousal", "a.b", "causes"),
    list("p3", "c_\u00e4rger", "NA", "decreases"),
    list("p4", "if", "edge", "mediates"),
    list("p5", "Node", 'say "hi"', "moderates"),
    list("p6", "x\\y", "self-efficacy", "causes"),
    list("p7", "self-efficacy", "1arousal", "associates")
  ))
}

test_that("causal_dag quotes ids that dagitty or Graphviz would misread", {
  # dagitty read `self-efficacy -> task-persistence` as four nodes, and Graphviz
  # split `1arousal` and stopped at a hyphen or a dot. An id is bare only when
  # it is a DOT identifier that is not a keyword in any case. Any other id is
  # quoted, with `"` escaped and a backslash kept as it is, since dagitty keeps
  # it literally.
  expect_identical(tf_diagram(.quoting_theory(), "causal_dag"), paste0(
    "dag {\n",
    '  "self-efficacy" -> "task persistence"\n',
    '  "1arousal" -> "a.b"\n',
    '  "c_\u00e4rger" -> NA\n',
    '  if -> "edge"\n',
    '  "Node" -> "say \\"hi\\""\n',
    '  "x\\y" -> "self-efficacy"\n',
    '  "self-efficacy" <-> "1arousal"\n',
    "}\n"))
})

test_that("causal_dag refuses the two ids dagitty reserves", {
  # dagitty refuses a node named `node` or `graph` even when it is quoted. The
  # first such id the view would write is named, in file order.
  theory <- .ids_theory(lapply(c("a", "b", "graph", "node"), function(x) list(x, NULL)), list(
    list("p1", "a", "graph", "causes"),
    list("p2", "node", "b", "causes")))
  expect_error(tf_diagram(theory, "causal_dag"),
               "causal_dag cannot export construct id 'graph': dagitty reserves it",
               fixed = TRUE)
  # Only an id the view writes is refused: this association joins two
  # constructs that no directed relation names, so it is not exported.
  theory <- .ids_theory(lapply(c("a", "b", "node", "k"), function(x) list(x, NULL)), list(
    list("p1", "a", "b", "causes"),
    list("p2", "node", "k", "associates")))
  expect_identical(tf_diagram(theory, "causal_dag"), "dag {\n  a -> b\n}\n")
})

test_that("causal_dag quotes an empty endpoint", {
  # A missing `from` reads as "" (API_SPEC.md section 3), which is no bare
  # identifier, so the line stays one that dagitty can parse.
  theory <- list(id = "t", constructs = list(list(id = "b")),
                 propositions = list(list(id = "p1", to = "b", relation = "causes")))
  expect_identical(tf_diagram(theory, "causal_dag"), 'dag {\n  "" -> b\n}\n')
})

test_that("dagitty reads the causal_dag export as written", {
  skip_if_not_installed("dagitty")
  # Read bare, the hyphenated chain gave dagitty five nodes and eight implied
  # independencies. Quoted, it implies the one tf_implications() derives.
  theory <- .ids_theory(
    list(list("self-efficacy", NULL), list("task-persistence", NULL), list("outcome", NULL)),
    list(list("p1", "self-efficacy", "task-persistence", "increases"),
         list("p2", "task-persistence", "outcome", "increases")))
  g <- dagitty::dagitty(tf_diagram(theory, "causal_dag"))
  expect_setequal(names(g), c("self-efficacy", "task-persistence", "outcome"))
  expect_length(dagitty::impliedConditionalIndependencies(g), 1L)
  expect_equal(tf_implications(theory)$n_implications, 1)
  # Every id of the quoting test comes back as written, the quote and the
  # backslash included.
  g <- dagitty::dagitty(tf_diagram(.quoting_theory(), "causal_dag"))
  expect_setequal(names(g), .dag_ids)
})

# -- tf_compile_sem -------------------------------------------------------------

.renaming_theory <- function() {
  .ids_theory(list(
    list("self-efficacy", c("7-point Likert rating", "Self report")),
    list("task persistence", "Time on task"),
    list("1arousal", NULL),
    list("NA", "In"),
    list("if", NULL),
    list("c_\u00e4rger", NULL),
    list(".1a", NULL),
    list(".hidden", NULL),
    list("a.b", NULL),
    list("node", NULL)
  ), list(
    list("p1", "self-efficacy", "task persistence", "increases"),
    list("p2", "1arousal", "NA", "causes"),
    list("p3", "if", "c_\u00e4rger", "decreases"),
    list("p4", ".hidden", "a.b", "associates"),
    list("p5", "NA", "task persistence", "moderates"),
    list("p6", ".1a", "if", "associates"),
    list("p7", "node", "a.b", "causes")
  ))
}

test_that("tf_compile_sem renames ids and indicators that lavaan cannot read as written", {
  # lavaan refuses or misreads `c-arousal`, `1arousal`, R's reserved words and
  # an indicator such as `7_point_likert_rating`. A construct id is renamed with
  # a comment that records the renaming, an unsafe indicator name gains `i_`,
  # and safe names are written as they are, `node` among them, since only
  # dagitty reserves it. The comments and the zero block use the new names.
  expect_identical(tf_compile_sem(.renaming_theory()), paste0(
    "# lavaan model generated by theoryforge for ids\n",
    "# Written for lavaan::sem(); indicator names are the sanitised measurement entries ",
    "and must match columns of the data.\n",
    "# renamed for lavaan: 'self-efficacy' -> self_efficacy\n",
    "# renamed for lavaan: 'task persistence' -> task_persistence\n",
    "# renamed for lavaan: '1arousal' -> c_1arousal\n",
    "# renamed for lavaan: 'NA' -> c_NA\n",
    "# renamed for lavaan: 'if' -> c_if\n",
    "# renamed for lavaan: 'c_\u00e4rger' -> c_arger\n",
    "# renamed for lavaan: '.1a' -> c_.1a\n",
    "# Measurement model\n",
    "self_efficacy =~ i_7_point_likert_rating + self_report\n",
    "task_persistence =~ time_on_task\n",
    "c_NA =~ i_in\n",
    "# Single-indicator constructs (lavaan fixes the indicator's residual variance at zero, ",
    "so each is treated as measured without error): task_persistence, c_NA\n",
    "# Structural model\n",
    "task_persistence ~ self_efficacy\n",
    "c_NA ~ c_1arousal\n",
    "c_arger ~ c_if\n",
    ".hidden ~~ a.b\n",
    "task_persistence ~ c_NA\n",
    "# moderation: c_NA moderates the paths into task_persistence; add the product term ",
    "by hand (task_persistence ~ <x>:c_NA for an observed predictor <x>; lavaan::sam() or ",
    "the modsem package for latent variables)\n",
    "c_.1a ~~ c_if\n",
    "a.b ~ node\n",
    "# Covariances the theory fixes at zero (lavaan::sem() frees them by default; ",
    "delete this block to restore its defaults)\n",
    "self_efficacy ~~ 0*c_1arousal\n",
    "self_efficacy ~~ 0*c_if\n",
    "self_efficacy ~~ 0*node\n",
    "task_persistence ~~ 0*c_arger\n",
    "task_persistence ~~ 0*a.b\n",
    "c_1arousal ~~ 0*c_if\n",
    "c_1arousal ~~ 0*node\n",
    "c_if ~~ 0*node\n",
    "c_arger ~~ 0*a.b\n"))
})

test_that("lavaan parses the renamed syntax as written", {
  skip_if_not_installed("lavaan")
  pt <- NULL
  expect_no_warning(pt <- lavaan::lavaanify(tf_compile_sem(.renaming_theory())))
  expect_identical(lavaan::lavNames(pt, "lv"), c("self_efficacy", "task_persistence", "c_NA"))
  expect_identical(lavaan::lavNames(pt, "ov.ind"),
                   c("i_7_point_likert_rating", "self_report", "time_on_task", "i_in"))
})

.efa_theory <- function() {
  .ids_theory(list(list("efa", c("q1", "q2")), list("traits", c("Openness", "EFA"))),
              list(list("p1", "efa", "traits", "causes")))
}

test_that("tf_compile_sem renames lavaan's own keyword efa", {
  # lavaan's parser takes `efa` as the start of an exploratory factor block
  # wherever it stands, so it refused `traits =~ openness + efa`. The name is
  # renamed in both positions, although make.names() accepts it.
  expect_identical(tf_compile_sem(.efa_theory()), paste0(
    "# lavaan model generated by theoryforge for ids\n",
    "# Written for lavaan::sem(); indicator names are the sanitised measurement entries ",
    "and must match columns of the data.\n",
    "# renamed for lavaan: 'efa' -> c_efa\n",
    "# Measurement model\n",
    "c_efa =~ q1 + q2\n",
    "traits =~ openness + i_efa\n",
    "# Structural model\n",
    "traits ~ c_efa\n"))
  skip_if_not_installed("lavaan")
  pt <- NULL
  expect_no_warning(pt <- lavaan::lavaanify(tf_compile_sem(.efa_theory())))
  expect_identical(lavaan::lavNames(pt, "ov.ind"), c("q1", "q2", "openness", "i_efa"))
})

.comment_theory <- function() {
  .ids_theory(list(list("outcome", NULL), list("mood\U0001f600\U0001f600", NULL),
                   list("x\nf ~~ 0*g", NULL)),
              list(list("p1", "mood\U0001f600\U0001f600", "outcome", "causes"),
                   list("p2", "x\nf ~~ 0*g", "outcome", "causes")),
              id = "t\r1")
}

test_that("tf_compile_sem keeps each comment on one line", {
  # A line feed in an id carried the rest of its renaming comment into the
  # model, where lavaan read `f ~~ 0*g' -> x_f_0_g` as a covariance. On
  # Windows, two characters outside the Basic Multilingual Plane in a comment
  # made lavaan read `outcome ~ mood` as `utcome ~ mood`. A comment writes
  # control characters and such characters as <U+XXXX>, in the header's
  # theory id as well.
  expect_identical(tf_compile_sem(.comment_theory()), paste0(
    "# lavaan model generated by theoryforge for t<U+000D>1\n",
    "# Written for lavaan::sem(); indicator names are the sanitised measurement entries ",
    "and must match columns of the data.\n",
    "# renamed for lavaan: 'mood<U+1F600><U+1F600>' -> mood\n",
    "# renamed for lavaan: 'x<U+000A>f ~~ 0*g' -> x_f_0_g\n",
    "# Measurement model\n",
    "# Structural model\n",
    "outcome ~ mood\n",
    "outcome ~ x_f_0_g\n",
    "# Covariances the theory fixes at zero (lavaan::sem() frees them by default; ",
    "delete this block to restore its defaults)\n",
    "mood ~~ 0*x_f_0_g\n"))
  skip_if_not_installed("lavaan")
  pt <- NULL
  expect_no_warning(pt <- lavaan::lavaanify(tf_compile_sem(.comment_theory())))
  user <- pt[pt$user == 1L, ]
  expect_identical(paste(user$lhs, user$op, user$rhs),
                   c("outcome ~ mood", "outcome ~ x_f_0_g", "mood ~~ x_f_0_g"))
})

test_that("a name is safe exactly when it is ASCII, make.names() leaves it unchanged and it is not efa", {
  # lavaan checks names with make.names(), so on ASCII text the rule must agree
  # with it, less lavaan's keyword efa. Every string of up to three characters
  # over this alphabet is tried, with R's reserved words, the dot names
  # make.names() accepts and efa.
  alphabet <- c("a", "Z", "0", "9", ".", "_", "-", " ", "!")
  s <- alphabet
  for (k in 2:3) s <- c(s, as.vector(outer(s[nchar(s) == k - 1L], alphabet, paste0)))
  s <- c(s, "if", "else", "repeat", "while", "function", "for", "in", "next", "break",
         "TRUE", "FALSE", "NULL", "Inf", "NaN", "NA", "NA_integer_", "NA_real_",
         "NA_character_", "NA_complex_", "...", "..1", "T", "iff", "Na", "efa", "EFA",
         "efa.1")
  safe <- vapply(s, .tf_lavaan_safe, logical(1), USE.NAMES = FALSE)
  expect_identical(safe, make.names(s) == s & s != "efa")
})

test_that("tf_compile_sem refuses two indicators of one construct with one name", {
  # lavaan merged the two into one indicator without a word.
  theory <- .ids_theory(list(list("c_avoidance",
                                  c("Self-reported avoidance", "self reported avoidance"))))
  expect_error(tf_compile_sem(theory), paste0(
    "compile_sem found a name collision: construct 'c_avoidance' has two indicators ",
    "that both become self_reported_avoidance"), fixed = TRUE)
})

test_that("tf_compile_sem refuses a construct named like an indicator", {
  # `anxiety =~ anxiety` drew a warning from lavaan and then an unidentified
  # fit, and a construct named like another's indicator made a second-order
  # factor. The message is the same whichever comes first in the file.
  expect_error(tf_compile_sem(.ids_theory(list(list("anxiety", "Anxiety")))), paste0(
    "compile_sem found a name collision: construct 'anxiety' and an indicator of ",
    "construct 'anxiety' both become anxiety"), fixed = TRUE)
  msg <- paste0("compile_sem found a name collision: construct 'threat' and an ",
                "indicator of construct 'appraisal' both become threat")
  expect_error(tf_compile_sem(.ids_theory(list(list("threat", c("q1", "q2")),
                                               list("appraisal", c("Threat", "q3"))))),
               msg, fixed = TRUE)
  expect_error(tf_compile_sem(.ids_theory(list(list("appraisal", c("Threat", "q3")),
                                               list("threat", c("q1", "q2"))))),
               msg, fixed = TRUE)
})

test_that("tf_compile_sem refuses two constructs with one name", {
  theory <- .ids_theory(list(list("self-efficacy", "q1"), list("self_efficacy", "q2")))
  expect_error(tf_compile_sem(theory), paste0(
    "compile_sem found a name collision: constructs 'self-efficacy' and ",
    "'self_efficacy' both become self_efficacy"), fixed = TRUE)
})

test_that("tf_compile_sem reports the first collision in file order", {
  theory <- .ids_theory(list(list("a", c("X", "x")), list("b-c", "q1"), list("b_c", "q2")))
  expect_error(tf_compile_sem(theory), paste0(
    "compile_sem found a name collision: construct 'a' has two indicators that ",
    "both become x"), fixed = TRUE)
})

test_that("tf_compile_sem names an undeclared endpoint by the same rule", {
  # tf_validate() reports an endpoint that names no construct. tf_compile_sem()
  # still writes it, renamed and recorded like a construct, and refuses it when
  # it would merge with a declared name, where lavaan used to stop at `x-1`.
  sem <- tf_compile_sem(.ids_theory(list(list("y", NULL)),
                                    list(list("p1", "my-x", "y", "causes"))))
  expect_true(grepl("# renamed for lavaan: 'my-x' -> my_x\n# Measurement model\n", sem,
                    fixed = TRUE))
  expect_true(endsWith(sem, "# Structural model\ny ~ my_x\n"))
  theory <- .ids_theory(list(list("x_1", NULL), list("y", NULL)),
                        list(list("p1", "x-1", "y", "causes")))
  expect_error(tf_compile_sem(theory), paste0(
    "compile_sem found a name collision: constructs 'x_1' and 'x-1' both become x_1"),
    fixed = TRUE)
})

test_that("tf_compile_sem allows an indicator shared by two constructs", {
  # A cross-loading is one observed variable measuring two constructs.
  sem <- tf_compile_sem(.ids_theory(list(list("a", c("x", "y")), list("b", c("y", "z")))))
  expect_true(grepl("# Measurement model\na =~ x + y\nb =~ y + z\n", sem, fixed = TRUE))
})

test_that("tf_compile_sem keeps an empty id empty", {
  # A construct without an id reads as "" (API_SPEC.md section 3) in both
  # twins, and the empty name is neither renamed nor recorded.
  # Nor is it listed among the single-indicator constructs.
  theory <- list(id = "t", constructs = list(list(measurement = list("m1"))))
  expect_identical(tf_compile_sem(theory), paste0(
    "# lavaan model generated by theoryforge for t\n",
    "# Written for lavaan::sem(); indicator names are the sanitised measurement entries ",
    "and must match columns of the data.\n",
    "# Measurement model\n =~ m1\n# Structural model\n"))
})
