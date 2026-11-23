#' theoryforge: systematic theory development
#'
#' @description
#' Psychological theories are mostly stated in words, and a verbal theory often
#' leaves unclear what it asserts. Its constructs are loosely defined, its
#' predictions seldom say which result would count against them, and a failed
#' test can be absorbed by an assumption added after the fact (Meehl, 1990;
#' Scheel et al., 2021). theoryforge holds a theory as a YAML or JSON file with
#' a fixed schema: its constructs and their measures, the propositions that
#' relate them, the predictions derived from those propositions, its auxiliary
#' assumptions, its rival accounts and its record of tests. From that file, the
#' package computes what can be checked mechanically. These are checks of what
#' the file states, and none of them shows that a theory is true.
#'
#' The sections below follow a theory from building to testing and to the
#' literature. [Get started](https://pablobernabeu.github.io/theoryforge/r/articles/theoryforge.html)
#' works through them on an example, and the
#' [methodology article](https://pablobernabeu.github.io/theoryforge/r/articles/methodology.html)
#' gives the reasoning and sources behind every check.
#'
#' @section Building a theory:
#' [tf_theory()] starts a theory, and the builders [tf_add_construct()],
#' [tf_add_proposition()], [tf_add_prediction()], [tf_add_phenomenon()],
#' [tf_add_assumption()], [tf_add_alternative()], [tf_add_evidence()] and
#' [tf_add_test_outcome()] add to it, each recording its step in the theory's
#' provenance. [tf_set_formal_model()] records a formal model. Each builder
#' returns a modified copy. [tf_read()] and [tf_write()] read and write YAML or
#' JSON, and [tf_read_dagitty()] makes a theory of a causal diagram drawn in
#' DAGitty, whose constructs then need definitions. [tf_content_hash()] gives
#' the SHA-256 digest of the theory's content, which identifies the file that a
#' preregistration or a dossier describes. [tf_example_names()] and
#' [tf_example_path()] list and locate the bundled examples.
#'
#' @section Checking a theory:
#' [tf_validate()] checks the fields the schema requires and their allowed
#' values, and with `full = TRUE` also every type, reference, claim and unknown
#' field. [tf_check()] scores the theory against a 12-item rigour checklist,
#' with a weighted aggregate, its range under other weightings and a gate that
#' blocks when an item marked as a blocker fails, and [tf_report()] writes the
#' result as JSON or HTML. [tf_redundancy_check()] flags a pair of constructs
#' when their definitions are near duplicates, when one definition is contained
#' in the other, when the two carry the same label or when every measure of one
#' is listed for the other. [tf_embedding_redundancy()] compares definitions
#' with an embedding model that you supply. The checklist reads what the file
#' states. It cannot judge whether a definition is apt or a mechanism plausible.
#'
#' @section Deriving and comparing:
#' [tf_implications()] reads the propositions as a causal graph, with directed
#' relations as arrows and associations as unexplained covariance, and lists
#' the conditional independencies the graph implies. A graph with a feedback
#' loop is read by sigma-separation when `cycles = "sigma"`. [tf_entailments()]
#' reads each claim of a prediction or phenomenon against the graph and says
#' whether the graph entails it, contradicts it or leaves it open.
#' [tf_equivalent_models()] lists the causal directions that no observational
#' study can test. [tf_discriminate()] sets the theory against a rival and
#' lists the claims, independencies and signs that would tell the two apart.
#' [tf_appraise_amendment()] calls an amendment progressive, degenerating or
#' neutral, and [tf_simulate()] runs the construct network as a linear
#' dynamical system. The causal reading assumes that the propositions state
#' every direct relation among the constructs, with an association for each
#' common cause they leave unnamed.
#'
#' @section Testing:
#' [tf_severity()] grades each prediction by the form of its claim before data.
#' [tf_compile_sem()] writes lavaan model syntax with labelled paths, the signs
#' the theory states and a definition of each effect a claim concerns.
#' [tf_preregister()] writes the theory and hypotheses sections of a
#' preregistration, and the study design, analysis plan and inference criteria
#' remain the author's. Once a test outcome records an estimate and its standard
#' error, [tf_post_data_severity()] computes how severely a bounded prediction
#' passed.
#'
#' @section Diagrams and reports:
#' [tf_diagram()] writes ten views of a theory as Graphviz DOT, DAGitty code or
#' SVG, and [tf_render_diagram()] draws its DOT and SVG views. [tf_dossier()]
#' gathers the results in one Markdown document for reviewers,
#' [tf_render_report()] wraps it in a Quarto report and [tf_osf_push()] deposits
#' it in an OSF project.
#'
#' @section The literature layer:
#' [tf_read_corpus()] reads a corpus of bibliographic records, and
#' [tf_fetch_corpus()] assembles one from OpenAlex, the only step of the
#' literature layer that needs a network connection. [tf_litmap()] maps its
#' keyword co-occurrence, themes and co-citation. [tf_landscape()] marks each
#' theme under-theorised, covered or crowded by how many of the theory and its
#' rivals share a word with it. A shared word does not show that an account
#' explains what the theme's records report. [tf_lit_diagram()] draws these
#' maps, and [tf_new_evidence_dois()] lists the candidate DOIs that the theory
#' does not yet cite.
#'
#' @section The Python package:
#' A [Python package](https://pablobernabeu.github.io/theoryforge/python/) of
#' the same name offers each function without the prefix `tf_`, except that
#' [tf_theory()] is `new_theory()`. Both follow one specification
#' ([API_SPEC.md](https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md)),
#' and continuous integration checks that they give the same results for the
#' same file. [tf_fetch_corpus()], [tf_osf_push()], [tf_embedding_redundancy()]
#' and [tf_render_diagram()] depend on a service, an embedding model or a
#' renderer outside the package, so their results can differ between the two.
#'
#' @references
#' Meehl, P. E. (1990). Appraising and amending theories: The strategy of
#' Lakatosian defense and two principles that warrant it. *Psychological
#' Inquiry*, *1*(2), 108--141. \doi{10.1207/s15327965pli0102_1}
#'
#' Scheel, A. M., Tiokhin, L., Isager, P. M., & Lakens, D. (2021). Why
#' hypothesis testers should spend less time testing hypotheses. *Perspectives
#' on Psychological Science*, *16*(4), 744--755. \doi{10.1177/1745691620966795}
#'
#' @author Pablo Bernabeu, author and maintainer
#'   (\email{pcbernabeu@gmail.com},
#'   \href{https://orcid.org/0000-0003-1083-2460}{ORCID}).
#' @keywords internal
"_PACKAGE"
