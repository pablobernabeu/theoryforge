# Developing and testing a theory

The companion vignette covers building a theory and checking its rigour.
This article continues the workflow into development and testing. It
shows how to grade the riskiness of each prediction’s claim, derive what
the causal graph forbids in data, export a preregistration, appraise an
amendment in Lakatosian terms, compile a measurement model for `lavaan`
and assemble a reviewer-facing audit bundle. The worked example reads
the panic-network fixture shipped with the package, joined in two
sections by the shipped modality-switching fixture, so every chunk runs
with only `theoryforge` loaded.

``` r

theory <- tf_read(
  system.file("fixtures/panic-network.theory.yaml", package = "theoryforge")
)
theory$id
```

    [1] "panic-network-2026"

### The severity rubric

A prediction earns evidential weight in proportion to the risk it takes.
A point prediction stakes more on the data than a directional one, and
that asymmetry should be made explicit before any test is run.
[`tf_severity()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_severity.md)
is a pre-data rubric of claim form. It reports, for each prediction in
file order, the riskiness of its declared type and the resulting
computed severity.

``` r

tf_severity(theory)
```

      prediction_id        type risk_score computed_severity
    1         pred1       point        0.9               1.0
    2         pred2    interval        0.7               0.7
    3         pred3 directional        0.4               0.3

The `risk_score` reflects the prediction type, while `computed_severity`
applies the directional discount and the diagnostic bonus defined in the
specification, both of them the package’s conventions. The rubric reads
only the declared type and the named rivals, never the statement or the
data, so it says nothing about how severely a claim has been tested.
That depends on the design and the data. Reading these values before
data collection guards against the temptation to read a weak,
hard-to-fail prediction as though it were a risky one.

### What the causal graph commits you to

Severity scores the predictions a theory states. A causal theory also
commits itself to claims it never states, because the propositions taken
together are a graph, and the graph implies a set of conditional
independencies.
[`tf_implications()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_implications.md)
derives them. Each directed relation (increases, decreases, causes,
mediates and moderates) is an arrow, and an association is a bidirected
edge, covariance the theory leaves unexplained. Every pair of constructs
with no edge between them yields one claim when some set of other
constructs separates them, usually the parents of both. When every
relation is directed, those claims are the basis set, from which every
other independence the graph implies follows. Each claim is something a
study can be designed to look for and fail to find. An association can
leave a pair that no set separates, and
[`tf_implications()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_implications.md)
lists such a pair under `inseparable`, since the theory then implies no
independence for it.

The panic-network example gets no statements by default. Its third
proposition returns from perceived threat to arousal, closing the
feedback loop the theory is about, and
[`tf_implications()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_implications.md)
refuses a graph with a cycle unless it is told how to read one.

``` r

tf_implications(theory)
```

    Error:
    ! implications requires an acyclic causal graph; cycle found: c_arousal -> c_perceived_threat -> c_arousal; set cycles to 'sigma' to derive sigma-separation statements

The refusal names the cycle it found, so nobody has to hunt for it, and
the option that reads it. A cyclic graph does imply conditional
independencies, and dagitty accepts the `causal_dag` export of one.
dagitty reads it by d-separation, though, which a model with feedback is
guaranteed to satisfy only in special cases, a linear model among them.
The criterion that holds whenever each feedback loop has a unique
equilibrium is sigma-separation ([Bongers et al.,
2021](https://doi.org/10.1214/21-AOS2064)), and `cycles = "sigma"`
applies it.

``` r

implied <- tf_implications(theory, cycles = "sigma")
lapply(implied$feedback, unlist)
```

    [[1]]
    [1] "c_arousal"          "c_perceived_threat"

``` r

implied$implications[[1]]$statement
```

    [1] "c_arousal _||_ c_avoidance | c_perceived_threat"

The loop between arousal and perceived threat is the one feedback loop.
Holding perceived threat fixed cuts the only way out of the loop towards
avoidance. The theory therefore implies that arousal and avoidance are
independent given perceived threat, a claim it never states and a study
could refute. The claim rests on an assumption the graph cannot check,
that for given inputs the loop settles into a single equilibrium. A
network theory that posits alternative stable states, such as a calm
state and a panic state that each sustain themselves, violates it. The
statement is then not guaranteed.
[`tf_simulate()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_simulate.md)
runs the loop over time.

The package ships a second example whose causal graph is acyclic, a
theory of modality switching in grounded conceptual processing.
Sensorimotor experience with a concept drives activation of the
modality-specific perceptual system. That activation both raises the
cost of switching modality between consecutive trials and eases
conceptual access, which lexical familiarity with the word form eases as
well.

``` r

switching <- tf_read(
  system.file("fixtures/modality-switching.theory.yaml", package = "theoryforge")
)

implied <- tf_implications(switching)
implied$n_edges
```

    [1] 4

``` r

implied$n_implications
```

    [1] 6

``` r

writeLines(vapply(implied$implications, function(i) i$statement, character(1)))
```

    c_sensorimotor_experience _||_ c_switch_cost | c_modality_activation
    c_sensorimotor_experience _||_ c_conceptual_access | c_modality_activation, c_lexical_familiarity
    c_sensorimotor_experience _||_ c_lexical_familiarity
    c_modality_activation _||_ c_lexical_familiarity | c_sensorimotor_experience
    c_switch_cost _||_ c_conceptual_access | c_modality_activation, c_lexical_familiarity
    c_switch_cost _||_ c_lexical_familiarity | c_modality_activation

Five constructs and four causal propositions leave six non-adjacent
pairs, and so six claims, each written in the notation dagitty prints.
Two of them are worth dwelling on. Switch cost and ease of conceptual
access are the two children of a fork at modality activation, so the
theory says the correlation between them is entirely due to that shared
cause and vanishes once it is held fixed. Sensorimotor experience and
lexical familiarity meet only at the collider at conceptual access, and
the theory says they are unrelated to each other with nothing held
fixed, which is what an account deriving perceptual knowledge from
distributional word statistics would deny. Neither claim appears among
the theory’s own predictions, and either could sink it. A version of the
theory that granted sensorimotor experience and lexical familiarity some
covariance would state it with `associates`, and the claim that the two
are unrelated would then be withdrawn.

The claims concern constructs, and a study observes them through
fallible measures. Error in a conditioning construct leaves part of the
dependence that holding it fixed should remove. A conditional claim
tested on observed scores is therefore rejected too often, and more
often the larger the sample ([Westfall & Yarkoni,
2016](https://doi.org/10.1371/journal.pone.0152719)). Take a chain whose
two paths have standardised coefficients of .5, with the middle
construct measured at a reliability of .8. A partial-correlation test at
the 5 per cent level then rejects the true claim in about 14, 29 and 51
per cent of studies of 200, 500 and 1,000 observations. Five of the six
claims above are conditional. They are better tested in a
latent-variable model, such as one built on the measurement model that
[`tf_compile_sem()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_compile_sem.md)
writes ([Thoemmes et al., 2018](https://doi.org/10.1037/met0000147)).

### Preregistration

[`tf_preregister()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_preregister.md)
renders a preregistration document as a single markdown string. It
records the predictions, each with its claim type and derivation, plus
the severity values, in a fixed order, so the output is stable across
runs and suitable for deposit. Because the string is markdown, it
renders below as the document a registry would receive.

``` r

prereg <- tf_preregister(theory)
cat(prereg)
```

## Preregistration: Network theory of panic disorder

- Theory ID: panic-network-2026
- Schema version: 1.0
- Maturity: developing
- Derivation chain verified: yes

### Hypotheses

1.  \[point\] An interoceptive challenge raises heart rate 20 beats per
    minute above baseline, within a measurement tolerance of 5, within
    90 seconds. (derives from: p1, p3)
2.  \[interval\] Avoidance frequency falls within a 20-35% band after
    exposure therapy. (derives from: p2)
3.  \[directional\] Higher perceived threat is associated with more
    avoidance. (derives from: p2)

### Severity (pre-data rubric of claim form)

- pred1: severity 1.0, risk 0.9
- pred2: severity 0.7, risk 0.7
- pred3: severity 0.3, risk 0.4

Passing a `path` writes the same markdown to disk with LF line endings,
which is convenient when the document is committed to a repository or
uploaded to a registry.

``` r

prereg_path <- tempfile(fileext = ".md")
invisible(tf_preregister(theory, path = prereg_path))
file.exists(prereg_path)
```

    [1] TRUE

### Appraising an amendment

Theories change. The question is whether a change is progressive, in
that it predicts and then corroborates something new, or degenerating,
in that it only adds assumptions to absorb anomalies.
[`tf_appraise_amendment()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_appraise_amendment.md)
compares an amended theory against its prior version and returns a
verdict in those terms.

Here the prior is the panic-network fixture and the amended version is
its 2026 revision. The revision adds a proposition, a direct path from
arousal to avoidance, and derives from it a new prediction that a
registered test later corroborates. It introduces no ad hoc assumption.

``` r

v2 <- tf_read(
  system.file(
    "fixtures/panic-network-2026-v2.theory.yaml",
    package = "theoryforge"
  )
)

appraisal <- tf_appraise_amendment(v2, theory)
appraisal$verdict
```

    [1] "progressive"

``` r

appraisal$new_predictions
```

    [1] "pred4"

``` r

appraisal$corroborated_new
```

    [1] "pred4"

``` r

appraisal$articulated
```

    character(0)

``` r

appraisal$ad_hoc_assumptions
```

    character(0)

A `progressive` verdict reflects new content that survived a test. The
appraisal compares what the two versions claim. A prediction that only
changed its identifier is reported under `renamed`, and one derived only
from propositions the prior already held is reported under `articulated`
and does not make the amendment progressive. Had the amendment instead
added assumptions tied to specific anomalies without generating
corroborated predictions, the verdict would record that as degenerating.

### Compiling a measurement model

When constructs carry measurement indicators,
[`tf_compile_sem()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_compile_sem.md)
compiles the theory into `lavaan` model syntax written for
[`lavaan::sem()`](https://rdrr.io/pkg/lavaan/man/sem.html). Constructs
with indicators become latent variables with `=~`, and propositions
become structural paths with `~` and covariances with `~~`. The
modality-switching theory shows the rest of what the syntax carries.

``` r

cat(tf_compile_sem(switching))
```

    # lavaan model generated by theoryforge for modality-switching-2026
    # Written for lavaan::sem(); indicator names are the sanitised measurement entries and must match columns of the data.
    # Measurement model
    c_sensorimotor_experience =~ modality_specific_perceptual_strength_ratings + sensory_experience_ratings + self_reported_frequency_of_first_hand_encounters
    c_modality_activation =~ bold_response_in_modality_specific_sensory_cortex + interference_from_a_concurrent_load_in_the_same_modality
    c_switch_cost =~ switch_minus_repeat_response_time_difference + switch_minus_repeat_error_rate_difference
    c_conceptual_access =~ semantic_categorisation_latency + lexical_decision_latency + accuracy_on_either_task
    c_lexical_familiarity =~ subjective_familiarity_ratings + corpus_frequency_of_the_word_form + age_of_acquisition
    # Structural model
    c_modality_activation ~ c_sensorimotor_experience
    c_switch_cost ~ c_modality_activation
    c_conceptual_access ~ c_modality_activation
    c_conceptual_access ~ c_lexical_familiarity
    # Covariances the theory fixes at zero (lavaan::sem() frees them by default; delete this block to restore its defaults)
    c_sensorimotor_experience ~~ 0*c_lexical_familiarity
    c_switch_cost ~~ 0*c_conceptual_access

The last block fixes two covariances at zero, those behind the two
claims singled out above. Sensorimotor experience and lexical
familiarity are both exogenous, and switch cost and conceptual access
are both terminal.
[`lavaan::sem()`](https://rdrr.io/pkg/lavaan/man/sem.html) frees the
covariance of each such pair by default, so a fit with its defaults
could not refute either claim. With the block, the structural model
tests all six. Deleting the block restores lavaan’s defaults.

The syntax is a starting point for a fit. The indicator names are the
sanitised measurement entries and must match columns of the data, so
entries written as column names give syntax that fits as it stands.
[`lavaan::sem()`](https://rdrr.io/pkg/lavaan/man/sem.html) treats a
construct with a single indicator as measured without error, which a
comment notes, and a manipulation or a categorical predictor with more
than two levels has to be re-specified by hand. A feedback loop makes
the model non-recursive, and such a model may not be identified
([Bollen, 1989](https://doi.org/10.1002/9781118619179)). The syntax
flags each loop in a comment. The panic network’s loop between arousal
and perceived threat leaves its model unidentified as it stands, and the
model needs an instrument or a further restriction before it can be
fitted.

The function returns a plain string and does not require `lavaan` to be
installed.

### The reviewer audit bundle

[`tf_dossier()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_dossier.md)
assembles a single markdown document for a reviewer or editor. It
collects the header, the rigour-checklist table, the severity list, the
provenance trail and the preregistration into one bundle, so a reader
can follow the theory from its claims through to its planned tests in
one place. The opening of the bundle, through the rigour-checklist
table, renders below.

``` r

dossier <- tf_dossier(theory)
cat(strsplit(dossier, "\n## Severity", fixed = TRUE)[[1]][1])
```

## theoryforge dossier: Network theory of panic disorder

- Theory ID: panic-network-2026
- Maturity: developing
- Checklist version: 2.0
- Aggregate rigour score: 87.3/100
- Checklist coverage: 0.92
- Gate: pass
- Blockers failed: 0

### Rigour checklist

| item               | status | score | weight |
|--------------------|--------|-------|--------|
| falsifiability     | pass   | 1.0   | 0.15   |
| precision          | pass   | 0.667 | 0.1    |
| risk_severity      | pass   | 0.567 | 0.1    |
| parsimony          | n/a    | n/a   | 0.08   |
| non_redundancy     | pass   | 1.0   | 0.1    |
| construct_clarity  | pass   | 1.0   | 0.08   |
| scope              | pass   | 1.0   | 0.06   |
| logical_why        | pass   | 1.0   | 0.08   |
| causal_testability | pass   | 1.0   | 0.06   |
| diagnosticity      | pass   | 0.333 | 0.06   |
| formalisation      | pass   | 1.0   | 0.05   |
| derivation_chain   | pass   | 1.0   | 0.08   |

The severity list, the provenance trail and the preregistration follow
in the full document, which is deterministic, so the same theory always
produces the same dossier.

### Rendering and depositing

[`tf_render_report()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_render_report.md)
writes the dossier as a Quarto source document, ready to render to HTML
or PDF. With `render = FALSE`, which is the default, it writes the
`.qmd` without calling Quarto, so the step runs anywhere. It returns the
path of the file it wrote.

``` r

report_path <- tf_render_report(theory, tempfile(fileext = ".qmd"))
basename(report_path)
```

    [1] "file1ea027a02cbd.qmd"

[`tf_osf_push()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_osf_push.md)
deposits the audit dossier on an Open Science Framework node, as
`<id>.dossier.md`. It defaults to `dry_run = TRUE`, which assembles the
request and returns it without sending anything, so the planned deposit
can be inspected offline and without a token. What goes up is the
dossier, since that is the machine-checkable bundle a reviewer needs.
The report written just above stays on your own machine.

``` r

str(tf_osf_push(theory, node = "ab12c"))
```

    List of 3
     $ dry_run: logi TRUE
     $ request:List of 4
      ..$ method       : chr "PUT"
      ..$ url          : chr "https://files.osf.io/v1/resources/ab12c/providers/osfstorage/?kind=file&name=panic-network-2026.dossier.md"
      ..$ filename     : chr "panic-network-2026.dossier.md"
      ..$ content_bytes: int 1867
     $ note   : chr "set dry_run=FALSE with a valid token and node to perform the upload"

The returned request records the method, the destination URL, the
filename the deposit would create and the size of the dossier in bytes,
so the step can be checked before anything leaves the machine. A live
deposit needs `dry_run = FALSE` together with a token and the node id,
and that is the only path that touches the network.

``` r

tf_osf_push(
  theory,
  node = "ab12c",
  token = Sys.getenv("OSF_PAT"),
  dry_run = FALSE
)
```

OSF refuses to create a file whose name already exists in the project,
so depositing the same theory a second time stops with HTTP 409. Either
pass a filename that names the version, or add `overwrite = TRUE`, which
lists the project folder first and sends the dossier to the existing
file as a new OSF version. Any other refusal also stops with its HTTP
status, so a returned value always describes an upload that OSF
accepted.

### Visualising the theory

[`tf_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_diagram.md)
exports several views of the same object. The `workflow` view traces the
lifecycle from constructs, through propositions and predictions, to the
recorded test outcomes, so the path from a claim to its planned test is
visible in one figure.

``` r

cat(tf_diagram(theory, "workflow"))
```

    digraph workflow {
      graph [rankdir=LR, bgcolor="transparent", fontname="Helvetica", fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];
      node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", color="#33567A", fillcolor="#F2F6F9", fontcolor="#12283A", penwidth=1.1, margin="0.16,0.1"];
      edge [fontname="Helvetica", fontsize=10, color="#7B909F", fontcolor="#0F6E6E", arrowsize=0.7];
      subgraph cluster_build {
        label="building";
        style="rounded";
        color="#C4D1D9";
        fontcolor="#5B7285";
        "c_arousal" [label="Physiological\narousal", fillcolor="#E4F1F1", color="#1E7B7B"];
        "c_perceived_threat" [label="Perceived threat", fillcolor="#E4F1F1", color="#1E7B7B"];
        "c_avoidance" [label="Avoidance\nbehaviour", fillcolor="#E4F1F1", color="#1E7B7B"];
      }
      subgraph cluster_relate {
        label="propositions";
        style="rounded";
        color="#C4D1D9";
        fontcolor="#5B7285";
        "prop_p1" [label="p1\nincreases", fillcolor="#FBF1DC", color="#9C6B14"];
        "prop_p2" [label="p2\nincreases", fillcolor="#FBF1DC", color="#9C6B14"];
        "prop_p3" [label="p3\ncauses", fillcolor="#FBF1DC", color="#9C6B14"];
      }
      subgraph cluster_predict {
        label="predictions";
        style="rounded";
        color="#C4D1D9";
        fontcolor="#5B7285";
        "pred_pred1" [label="pred1\npoint", fillcolor="#E7EDF5", color="#33567A"];
        "pred_pred2" [label="pred2\ninterval", fillcolor="#E7EDF5", color="#33567A"];
        "pred_pred3" [label="pred3\ndirectional", fillcolor="#E7EDF5", color="#33567A"];
      }
      subgraph cluster_test {
        label="testing";
        style="rounded";
        color="#C4D1D9";
        fontcolor="#5B7285";
        "outcome_pred1" [label="pred1\npassed", fillcolor="#E5F2E7", color="#3E7A46"];
      }
      "c_arousal" -> "prop_p1";
      "c_perceived_threat" -> "prop_p2";
      "c_perceived_threat" -> "prop_p3";
      "prop_p1" -> "pred_pred1";
      "prop_p3" -> "pred_pred1";
      "prop_p2" -> "pred_pred2";
      "prop_p2" -> "pred_pred3";
      "pred_pred1" -> "outcome_pred1";
    }

Rendered with
[`tf_render_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_render_diagram.md),
which passes the DOT to the DiagrammeR engine, the same view reads as a
figure.

``` r

cat(
  '<div class="tf-figure tf-diagram">',
  tf_render_diagram(theory, "workflow", as = "svg"),
  '</div>',
  sep = ""
)
```

![](data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iNDY2cHQiIGhlaWdodD0iMjQ2cHQiIHZpZXdib3g9IjAuMDAgMC4wMCA0NjUuNTEgMjQ1LjgwIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHhtbG5zOnhsaW5rPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5L3hsaW5rIj48ZyBpZD0iZ3JhcGgwIiBjbGFzcz0iZ3JhcGgiIHRyYW5zZm9ybT0ic2NhbGUoMSAxKSByb3RhdGUoMCkgdHJhbnNsYXRlKDE0LjQgMjMxLjQpIj48dGl0bGU+CndvcmtmbG93CjwvdGl0bGU+CjxnIGlkPSJjbHVzdDEiIGNsYXNzPSJjbHVzdGVyIj48dGl0bGU+CmNsdXN0ZXJfYnVpbGQKPC90aXRsZT4KPHBhdGggZmlsbD0idHJhbnNwYXJlbnQiIHN0cm9rZT0iI2M0ZDFkOSIgZD0iTTIwLC0xMEMyMCwtMTAgMTE2LjA3NTYsLTEwIDExNi4wNzU2LC0xMCAxMjIuMDc1NiwtMTAgMTI4LjA3NTYsLTE2IDEyOC4wNzU2LC0yMiAxMjguMDc1NiwtMjIgMTI4LjA3NTYsLTE5NSAxMjguMDc1NiwtMTk1IDEyOC4wNzU2LC0yMDEgMTIyLjA3NTYsLTIwNyAxMTYuMDc1NiwtMjA3IDExNi4wNzU2LC0yMDcgMjAsLTIwNyAyMCwtMjA3IDE0LC0yMDcgOCwtMjAxIDgsLTE5NSA4LC0xOTUgOCwtMjIgOCwtMjIgOCwtMTYgMTQsLTEwIDIwLC0xMCIgLz48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI2OC4wMzc4IiB5PSItMTkzLjEiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzViNzI4NSI+YnVpbGRpbmc8L3RleHQ+PC9nPjxnIGlkPSJjbHVzdDIiIGNsYXNzPSJjbHVzdGVyIj48dGl0bGU+CmNsdXN0ZXJfcmVsYXRlCjwvdGl0bGU+CjxwYXRoIGZpbGw9InRyYW5zcGFyZW50IiBzdHJva2U9IiNjNGQxZDkiIGQ9Ik0xNTYuMDc1NiwtOEMxNTYuMDc1NiwtOCAyMTkuMTM4LC04IDIxOS4xMzgsLTggMjI1LjEzOCwtOCAyMzEuMTM4LC0xNCAyMzEuMTM4LC0yMCAyMzEuMTM4LC0yMCAyMzEuMTM4LC0xOTcgMjMxLjEzOCwtMTk3IDIzMS4xMzgsLTIwMyAyMjUuMTM4LC0yMDkgMjE5LjEzOCwtMjA5IDIxOS4xMzgsLTIwOSAxNTYuMDc1NiwtMjA5IDE1Ni4wNzU2LC0yMDkgMTUwLjA3NTYsLTIwOSAxNDQuMDc1NiwtMjAzIDE0NC4wNzU2LC0xOTcgMTQ0LjA3NTYsLTE5NyAxNDQuMDc1NiwtMjAgMTQ0LjA3NTYsLTIwIDE0NC4wNzU2LC0xNCAxNTAuMDc1NiwtOCAxNTYuMDc1NiwtOCIgLz48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIxODcuNjA2OCIgeT0iLTE5NS4xIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiM1YjcyODUiPnByb3Bvc2l0aW9uczwvdGV4dD48L2c+PGcgaWQ9ImNsdXN0MyIgY2xhc3M9ImNsdXN0ZXIiPjx0aXRsZT4KY2x1c3Rlcl9wcmVkaWN0CjwvdGl0bGU+CjxwYXRoIGZpbGw9InRyYW5zcGFyZW50IiBzdHJva2U9IiNjNGQxZDkiIGQ9Ik0yNTkuMTM4LC04QzI1OS4xMzgsLTggMzI1LjI1NCwtOCAzMjUuMjU0LC04IDMzMS4yNTQsLTggMzM3LjI1NCwtMTQgMzM3LjI1NCwtMjAgMzM3LjI1NCwtMjAgMzM3LjI1NCwtMTk3IDMzNy4yNTQsLTE5NyAzMzcuMjU0LC0yMDMgMzMxLjI1NCwtMjA5IDMyNS4yNTQsLTIwOSAzMjUuMjU0LC0yMDkgMjU5LjEzOCwtMjA5IDI1OS4xMzgsLTIwOSAyNTMuMTM4LC0yMDkgMjQ3LjEzOCwtMjAzIDI0Ny4xMzgsLTE5NyAyNDcuMTM4LC0xOTcgMjQ3LjEzOCwtMjAgMjQ3LjEzOCwtMjAgMjQ3LjEzOCwtMTQgMjUzLjEzOCwtOCAyNTkuMTM4LC04IiAvPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjI5Mi4xOTYiIHk9Ii0xOTUuMSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjNWI3Mjg1Ij5wcmVkaWN0aW9uczwvdGV4dD48L2c+PGcgaWQ9ImNsdXN0NCIgY2xhc3M9ImNsdXN0ZXIiPjx0aXRsZT4KY2x1c3Rlcl90ZXN0CjwvdGl0bGU+CjxwYXRoIGZpbGw9InRyYW5zcGFyZW50IiBzdHJva2U9IiNjNGQxZDkiIGQ9Ik0zNjUuMjU0LC0xMzJDMzY1LjI1NCwtMTMyIDQxNi43MTM2LC0xMzIgNDE2LjcxMzYsLTEzMiA0MjIuNzEzNiwtMTMyIDQyOC43MTM2LC0xMzggNDI4LjcxMzYsLTE0NCA0MjguNzEzNiwtMTQ0IDQyOC43MTM2LC0xOTcgNDI4LjcxMzYsLTE5NyA0MjguNzEzNiwtMjAzIDQyMi43MTM2LC0yMDkgNDE2LjcxMzYsLTIwOSA0MTYuNzEzNiwtMjA5IDM2NS4yNTQsLTIwOSAzNjUuMjU0LC0yMDkgMzU5LjI1NCwtMjA5IDM1My4yNTQsLTIwMyAzNTMuMjU0LC0xOTcgMzUzLjI1NCwtMTk3IDM1My4yNTQsLTE0NCAzNTMuMjU0LC0xNDQgMzUzLjI1NCwtMTM4IDM1OS4yNTQsLTEzMiAzNjUuMjU0LC0xMzIiIC8+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMzkwLjk4MzgiIHk9Ii0xOTUuMSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjNWI3Mjg1Ij50ZXN0aW5nPC90ZXh0PjwvZz48IS0tIGNfYXJvdXNhbCAtLT48ZyBpZD0ibm9kZTEiIGNsYXNzPSJub2RlIj48dGl0bGU+CmNfYXJvdXNhbAo8L3RpdGxlPgo8cGF0aCBmaWxsPSIjZTRmMWYxIiBzdHJva2U9IiMxZTdiN2IiIHN0cm9rZS13aWR0aD0iMS4xIiBkPSJNMTAwLjIxMiwtMTc4LjQwMkMxMDAuMjEyLC0xNzguNDAyIDM1Ljg2MzYsLTE3OC40MDIgMzUuODYzNiwtMTc4LjQwMiAyOS44NjM2LC0xNzguNDAyIDIzLjg2MzYsLTE3Mi40MDIgMjMuODYzNiwtMTY2LjQwMiAyMy44NjM2LC0xNjYuNDAyIDIzLjg2MzYsLTE0OS41OTggMjMuODYzNiwtMTQ5LjU5OCAyMy44NjM2LC0xNDMuNTk4IDI5Ljg2MzYsLTEzNy41OTggMzUuODYzNiwtMTM3LjU5OCAzNS44NjM2LC0xMzcuNTk4IDEwMC4yMTIsLTEzNy41OTggMTAwLjIxMiwtMTM3LjU5OCAxMDYuMjEyLC0xMzcuNTk4IDExMi4yMTIsLTE0My41OTggMTEyLjIxMiwtMTQ5LjU5OCAxMTIuMjEyLC0xNDkuNTk4IDExMi4yMTIsLTE2Ni40MDIgMTEyLjIxMiwtMTY2LjQwMiAxMTIuMjEyLC0xNzIuNDAyIDEwNi4yMTIsLTE3OC40MDIgMTAwLjIxMiwtMTc4LjQwMiIgLz48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI2OC4wMzc4IiB5PSItMTYxLjMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+UGh5c2lvbG9naWNhbDwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI2OC4wMzc4IiB5PSItMTQ4LjEiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+YXJvdXNhbDwvdGV4dD48L2c+PCEtLSBwcm9wX3AxIC0tPjxnIGlkPSJub2RlNCIgY2xhc3M9Im5vZGUiPjx0aXRsZT4KcHJvcF9wMQo8L3RpdGxlPgo8cGF0aCBmaWxsPSIjZmJmMWRjIiBzdHJva2U9IiM5YzZiMTQiIHN0cm9rZS13aWR0aD0iMS4xIiBkPSJNMjExLjE2OTIsLTE4MC40MDJDMjExLjE2OTIsLTE4MC40MDIgMTY0LjA0NDQsLTE4MC40MDIgMTY0LjA0NDQsLTE4MC40MDIgMTU4LjA0NDQsLTE4MC40MDIgMTUyLjA0NDQsLTE3NC40MDIgMTUyLjA0NDQsLTE2OC40MDIgMTUyLjA0NDQsLTE2OC40MDIgMTUyLjA0NDQsLTE1MS41OTggMTUyLjA0NDQsLTE1MS41OTggMTUyLjA0NDQsLTE0NS41OTggMTU4LjA0NDQsLTEzOS41OTggMTY0LjA0NDQsLTEzOS41OTggMTY0LjA0NDQsLTEzOS41OTggMjExLjE2OTIsLTEzOS41OTggMjExLjE2OTIsLTEzOS41OTggMjE3LjE2OTIsLTEzOS41OTggMjIzLjE2OTIsLTE0NS41OTggMjIzLjE2OTIsLTE1MS41OTggMjIzLjE2OTIsLTE1MS41OTggMjIzLjE2OTIsLTE2OC40MDIgMjIzLjE2OTIsLTE2OC40MDIgMjIzLjE2OTIsLTE3NC40MDIgMjE3LjE2OTIsLTE4MC40MDIgMjExLjE2OTIsLTE4MC40MDIiIC8+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMTg3LjYwNjgiIHk9Ii0xNjMuMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5wMTwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIxODcuNjA2OCIgeT0iLTE1MC4xIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPmluY3JlYXNlczwvdGV4dD48L2c+PCEtLSBjX2Fyb3VzYWwmIzQ1OyZndDtwcm9wX3AxIC0tPjxnIGlkPSJlZGdlMSIgY2xhc3M9ImVkZ2UiPjx0aXRsZT4KY19hcm91c2FsLSZndDtwcm9wX3AxCjwvdGl0bGU+CjxwYXRoIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzdiOTA5ZiIgZD0iTTExMi4yMjEyLC0xNTguNzM5QzEyMi44MTUzLC0xNTguOTE2MiAxMzQuMTEyMSwtMTU5LjEwNTIgMTQ0LjY0OTYsLTE1OS4yODE1IiAvPjxwb2x5Z29uIGZpbGw9IiM3YjkwOWYiIHN0cm9rZT0iIzdiOTA5ZiIgcG9pbnRzPSIxNDQuNzY1NSwtMTYxLjczMzcgMTUxLjgwNTYsLTE1OS40MDEyIDE0NC44NDc2LC0xNTYuODM0MyAxNDQuNzY1NSwtMTYxLjczMzciPjwvcG9seWdvbj48L2c+PCEtLSBjX3BlcmNlaXZlZF90aHJlYXQgLS0+PGcgaWQ9Im5vZGUyIiBjbGFzcz0ibm9kZSI+PHRpdGxlPgpjX3BlcmNlaXZlZF90aHJlYXQKPC90aXRsZT4KPHBhdGggZmlsbD0iI2U0ZjFmMSIgc3Ryb2tlPSIjMWU3YjdiIiBzdHJva2Utd2lkdGg9IjEuMSIgZD0iTTEwOC4xMTM0LC0xMTZDMTA4LjExMzQsLTExNiAyNy45NjIyLC0xMTYgMjcuOTYyMiwtMTE2IDIxLjk2MjIsLTExNiAxNS45NjIyLC0xMTAgMTUuOTYyMiwtMTA0IDE1Ljk2MjIsLTEwNCAxNS45NjIyLC05MiAxNS45NjIyLC05MiAxNS45NjIyLC04NiAyMS45NjIyLC04MCAyNy45NjIyLC04MCAyNy45NjIyLC04MCAxMDguMTEzNCwtODAgMTA4LjExMzQsLTgwIDExNC4xMTM0LC04MCAxMjAuMTEzNCwtODYgMTIwLjExMzQsLTkyIDEyMC4xMTM0LC05MiAxMjAuMTEzNCwtMTA0IDEyMC4xMTM0LC0xMDQgMTIwLjExMzQsLTExMCAxMTQuMTEzNCwtMTE2IDEwOC4xMTM0LC0xMTYiIC8+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iNjguMDM3OCIgeT0iLTk0LjciIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+UGVyY2VpdmVkCnRocmVhdDwvdGV4dD48L2c+PCEtLSBwcm9wX3AyIC0tPjxnIGlkPSJub2RlNSIgY2xhc3M9Im5vZGUiPjx0aXRsZT4KcHJvcF9wMgo8L3RpdGxlPgo8cGF0aCBmaWxsPSIjZmJmMWRjIiBzdHJva2U9IiM5YzZiMTQiIHN0cm9rZS13aWR0aD0iMS4xIiBkPSJNMjExLjE2OTIsLTU2LjQwMkMyMTEuMTY5MiwtNTYuNDAyIDE2NC4wNDQ0LC01Ni40MDIgMTY0LjA0NDQsLTU2LjQwMiAxNTguMDQ0NCwtNTYuNDAyIDE1Mi4wNDQ0LC01MC40MDIgMTUyLjA0NDQsLTQ0LjQwMiAxNTIuMDQ0NCwtNDQuNDAyIDE1Mi4wNDQ0LC0yNy41OTggMTUyLjA0NDQsLTI3LjU5OCAxNTIuMDQ0NCwtMjEuNTk4IDE1OC4wNDQ0LC0xNS41OTggMTY0LjA0NDQsLTE1LjU5OCAxNjQuMDQ0NCwtMTUuNTk4IDIxMS4xNjkyLC0xNS41OTggMjExLjE2OTIsLTE1LjU5OCAyMTcuMTY5MiwtMTUuNTk4IDIyMy4xNjkyLC0yMS41OTggMjIzLjE2OTIsLTI3LjU5OCAyMjMuMTY5MiwtMjcuNTk4IDIyMy4xNjkyLC00NC40MDIgMjIzLjE2OTIsLTQ0LjQwMiAyMjMuMTY5MiwtNTAuNDAyIDIxNy4xNjkyLC01Ni40MDIgMjExLjE2OTIsLTU2LjQwMiIgLz48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIxODcuNjA2OCIgeT0iLTM5LjMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+cDI8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMTg3LjYwNjgiIHk9Ii0yNi4xIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPmluY3JlYXNlczwvdGV4dD48L2c+PCEtLSBjX3BlcmNlaXZlZF90aHJlYXQmIzQ1OyZndDtwcm9wX3AyIC0tPjxnIGlkPSJlZGdlMiIgY2xhc3M9ImVkZ2UiPjx0aXRsZT4KY19wZXJjZWl2ZWRfdGhyZWF0LSZndDtwcm9wX3AyCjwvdGl0bGU+CjxwYXRoIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzdiOTA5ZiIgZD0iTTEwNi4zMTA0LC03OS45MTA1QzExMy41NzQ3LC03Ni4zNjUgMTIxLjA4NjgsLTcyLjYyMTMgMTI4LjA3NTYsLTY5IDEzMy43Nzc0LC02Ni4wNDU1IDEzOS43NDExLC02Mi44NTg0IDE0NS41OTg2LC01OS42NzA0IiAvPjxwb2x5Z29uIGZpbGw9IiM3YjkwOWYiIHN0cm9rZT0iIzdiOTA5ZiIgcG9pbnRzPSIxNDYuOTMyNywtNjEuNzMzMSAxNTEuODk1NCwtNTYuMjIxOCAxNDQuNTc5LC01Ny40MzU0IDE0Ni45MzI3LC02MS43MzMxIj48L3BvbHlnb24+PC9nPjwhLS0gcHJvcF9wMyAtLT48ZyBpZD0ibm9kZTYiIGNsYXNzPSJub2RlIj48dGl0bGU+CnByb3BfcDMKPC90aXRsZT4KPHBhdGggZmlsbD0iI2ZiZjFkYyIgc3Ryb2tlPSIjOWM2YjE0IiBzdHJva2Utd2lkdGg9IjEuMSIgZD0iTTIwNC45NTE3LC0xMTguNDAyQzIwNC45NTE3LC0xMTguNDAyIDE3MC4yNjE5LC0xMTguNDAyIDE3MC4yNjE5LC0xMTguNDAyIDE2NC4yNjE5LC0xMTguNDAyIDE1OC4yNjE5LC0xMTIuNDAyIDE1OC4yNjE5LC0xMDYuNDAyIDE1OC4yNjE5LC0xMDYuNDAyIDE1OC4yNjE5LC04OS41OTggMTU4LjI2MTksLTg5LjU5OCAxNTguMjYxOSwtODMuNTk4IDE2NC4yNjE5LC03Ny41OTggMTcwLjI2MTksLTc3LjU5OCAxNzAuMjYxOSwtNzcuNTk4IDIwNC45NTE3LC03Ny41OTggMjA0Ljk1MTcsLTc3LjU5OCAyMTAuOTUxNywtNzcuNTk4IDIxNi45NTE3LC04My41OTggMjE2Ljk1MTcsLTg5LjU5OCAyMTYuOTUxNywtODkuNTk4IDIxNi45NTE3LC0xMDYuNDAyIDIxNi45NTE3LC0xMDYuNDAyIDIxNi45NTE3LC0xMTIuNDAyIDIxMC45NTE3LC0xMTguNDAyIDIwNC45NTE3LC0xMTguNDAyIiAvPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjE4Ny42MDY4IiB5PSItMTAxLjMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+cDM8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMTg3LjYwNjgiIHk9Ii04OC4xIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPmNhdXNlczwvdGV4dD48L2c+PCEtLSBjX3BlcmNlaXZlZF90aHJlYXQmIzQ1OyZndDtwcm9wX3AzIC0tPjxnIGlkPSJlZGdlMyIgY2xhc3M9ImVkZ2UiPjx0aXRsZT4KY19wZXJjZWl2ZWRfdGhyZWF0LSZndDtwcm9wX3AzCjwvdGl0bGU+CjxwYXRoIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzdiOTA5ZiIgZD0iTTEyMC4xMzQ3LC05OEMxMzAuNDY1NCwtOTggMTQxLjEwNzYsLTk4IDE1MC43OTk1LC05OCIgLz48cG9seWdvbiBmaWxsPSIjN2I5MDlmIiBzdHJva2U9IiM3YjkwOWYiIHBvaW50cz0iMTUxLjAwNDksLTEwMC40NTAxIDE1OC4wMDQ4LC05OCAxNTEuMDA0OCwtOTUuNTUwMSAxNTEuMDA0OSwtMTAwLjQ1MDEiPjwvcG9seWdvbj48L2c+PCEtLSBjX2F2b2lkYW5jZSAtLT48ZyBpZD0ibm9kZTMiIGNsYXNzPSJub2RlIj48dGl0bGU+CmNfYXZvaWRhbmNlCjwvdGl0bGU+CjxwYXRoIGZpbGw9IiNlNGYxZjEiIHN0cm9rZT0iIzFlN2I3YiIgc3Ryb2tlLXdpZHRoPSIxLjEiIGQ9Ik05My44ODk5LC01OC40MDJDOTMuODg5OSwtNTguNDAyIDQyLjE4NTcsLTU4LjQwMiA0Mi4xODU3LC01OC40MDIgMzYuMTg1NywtNTguNDAyIDMwLjE4NTcsLTUyLjQwMiAzMC4xODU3LC00Ni40MDIgMzAuMTg1NywtNDYuNDAyIDMwLjE4NTcsLTI5LjU5OCAzMC4xODU3LC0yOS41OTggMzAuMTg1NywtMjMuNTk4IDM2LjE4NTcsLTE3LjU5OCA0Mi4xODU3LC0xNy41OTggNDIuMTg1NywtMTcuNTk4IDkzLjg4OTksLTE3LjU5OCA5My44ODk5LC0xNy41OTggOTkuODg5OSwtMTcuNTk4IDEwNS44ODk5LC0yMy41OTggMTA1Ljg4OTksLTI5LjU5OCAxMDUuODg5OSwtMjkuNTk4IDEwNS44ODk5LC00Ni40MDIgMTA1Ljg4OTksLTQ2LjQwMiAxMDUuODg5OSwtNTIuNDAyIDk5Ljg4OTksLTU4LjQwMiA5My44ODk5LC01OC40MDIiIC8+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iNjguMDM3OCIgeT0iLTQxLjMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+QXZvaWRhbmNlPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjY4LjAzNzgiIHk9Ii0yOC4xIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPmJlaGF2aW91cjwvdGV4dD48L2c+PCEtLSBwcmVkX3ByZWQxIC0tPjxnIGlkPSJub2RlNyIgY2xhc3M9Im5vZGUiPjx0aXRsZT4KcHJlZF9wcmVkMQo8L3RpdGxlPgo8cGF0aCBmaWxsPSIjZTdlZGY1IiBzdHJva2U9IiMzMzU2N2EiIHN0cm9rZS13aWR0aD0iMS4xIiBkPSJNMzA3LjE5NiwtMTgwLjQwMkMzMDcuMTk2LC0xODAuNDAyIDI3Ny4xOTYsLTE4MC40MDIgMjc3LjE5NiwtMTgwLjQwMiAyNzEuMTk2LC0xODAuNDAyIDI2NS4xOTYsLTE3NC40MDIgMjY1LjE5NiwtMTY4LjQwMiAyNjUuMTk2LC0xNjguNDAyIDI2NS4xOTYsLTE1MS41OTggMjY1LjE5NiwtMTUxLjU5OCAyNjUuMTk2LC0xNDUuNTk4IDI3MS4xOTYsLTEzOS41OTggMjc3LjE5NiwtMTM5LjU5OCAyNzcuMTk2LC0xMzkuNTk4IDMwNy4xOTYsLTEzOS41OTggMzA3LjE5NiwtMTM5LjU5OCAzMTMuMTk2LC0xMzkuNTk4IDMxOS4xOTYsLTE0NS41OTggMzE5LjE5NiwtMTUxLjU5OCAzMTkuMTk2LC0xNTEuNTk4IDMxOS4xOTYsLTE2OC40MDIgMzE5LjE5NiwtMTY4LjQwMiAzMTkuMTk2LC0xNzQuNDAyIDMxMy4xOTYsLTE4MC40MDIgMzA3LjE5NiwtMTgwLjQwMiIgLz48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIyOTIuMTk2IiB5PSItMTYzLjMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+cHJlZDE8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMjkyLjE5NiIgeT0iLTE1MC4xIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPnBvaW50PC90ZXh0PjwvZz48IS0tIHByb3BfcDEmIzQ1OyZndDtwcmVkX3ByZWQxIC0tPjxnIGlkPSJlZGdlNCIgY2xhc3M9ImVkZ2UiPjx0aXRsZT4KcHJvcF9wMS0mZ3Q7cHJlZF9wcmVkMQo8L3RpdGxlPgo8cGF0aCBmaWxsPSJub25lIiBzdHJva2U9IiM3YjkwOWYiIGQ9Ik0yMjMuMzA3OSwtMTYwQzIzNC40NzMsLTE2MCAyNDYuNzYzOSwtMTYwIDI1Ny44MzQ3LC0xNjAiIC8+PHBvbHlnb24gZmlsbD0iIzdiOTA5ZiIgc3Ryb2tlPSIjN2I5MDlmIiBwb2ludHM9IjI1Ny45MDk2LC0xNjIuNDUwMSAyNjQuOTA5NSwtMTYwIDI1Ny45MDk1LC0xNTcuNTUwMSAyNTcuOTA5NiwtMTYyLjQ1MDEiPjwvcG9seWdvbj48L2c+PCEtLSBwcmVkX3ByZWQyIC0tPjxnIGlkPSJub2RlOCIgY2xhc3M9Im5vZGUiPjx0aXRsZT4KcHJlZF9wcmVkMgo8L3RpdGxlPgo8cGF0aCBmaWxsPSIjZTdlZGY1IiBzdHJva2U9IiMzMzU2N2EiIHN0cm9rZS13aWR0aD0iMS4xIiBkPSJNMzEwLjE0MywtMTE4LjQwMkMzMTAuMTQzLC0xMTguNDAyIDI3NC4yNDksLTExOC40MDIgMjc0LjI0OSwtMTE4LjQwMiAyNjguMjQ5LC0xMTguNDAyIDI2Mi4yNDksLTExMi40MDIgMjYyLjI0OSwtMTA2LjQwMiAyNjIuMjQ5LC0xMDYuNDAyIDI2Mi4yNDksLTg5LjU5OCAyNjIuMjQ5LC04OS41OTggMjYyLjI0OSwtODMuNTk4IDI2OC4yNDksLTc3LjU5OCAyNzQuMjQ5LC03Ny41OTggMjc0LjI0OSwtNzcuNTk4IDMxMC4xNDMsLTc3LjU5OCAzMTAuMTQzLC03Ny41OTggMzE2LjE0MywtNzcuNTk4IDMyMi4xNDMsLTgzLjU5OCAzMjIuMTQzLC04OS41OTggMzIyLjE0MywtODkuNTk4IDMyMi4xNDMsLTEwNi40MDIgMzIyLjE0MywtMTA2LjQwMiAzMjIuMTQzLC0xMTIuNDAyIDMxNi4xNDMsLTExOC40MDIgMzEwLjE0MywtMTE4LjQwMiIgLz48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIyOTIuMTk2IiB5PSItMTAxLjMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+cHJlZDI8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMjkyLjE5NiIgeT0iLTg4LjEiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+aW50ZXJ2YWw8L3RleHQ+PC9nPjwhLS0gcHJvcF9wMiYjNDU7Jmd0O3ByZWRfcHJlZDIgLS0+PGcgaWQ9ImVkZ2U2IiBjbGFzcz0iZWRnZSI+PHRpdGxlPgpwcm9wX3AyLSZndDtwcmVkX3ByZWQyCjwvdGl0bGU+CjxwYXRoIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzdiOTA5ZiIgZD0iTTIyMS44NTMyLC01Ni4zMDExQzIzMi45MTE5LC02Mi44NTY3IDI0NS4xOTc5LC03MC4xMzk4IDI1Ni4zNjc4LC03Ni43NjEyIiAvPjxwb2x5Z29uIGZpbGw9IiM3YjkwOWYiIHN0cm9rZT0iIzdiOTA5ZiIgcG9pbnRzPSIyNTUuMTcyNywtNzguOTAwOSAyNjIuNDQzNiwtODAuMzYyOSAyNTcuNjcxNCwtNzQuNjg1OCAyNTUuMTcyNywtNzguOTAwOSI+PC9wb2x5Z29uPjwvZz48IS0tIHByZWRfcHJlZDMgLS0+PGcgaWQ9Im5vZGU5IiBjbGFzcz0ibm9kZSI+PHRpdGxlPgpwcmVkX3ByZWQzCjwvdGl0bGU+CjxwYXRoIGZpbGw9IiNlN2VkZjUiIHN0cm9rZT0iIzMzNTY3YSIgc3Ryb2tlLXdpZHRoPSIxLjEiIGQ9Ik0zMTcuMzEyMSwtNTYuNDAyQzMxNy4zMTIxLC01Ni40MDIgMjY3LjA3OTksLTU2LjQwMiAyNjcuMDc5OSwtNTYuNDAyIDI2MS4wNzk5LC01Ni40MDIgMjU1LjA3OTksLTUwLjQwMiAyNTUuMDc5OSwtNDQuNDAyIDI1NS4wNzk5LC00NC40MDIgMjU1LjA3OTksLTI3LjU5OCAyNTUuMDc5OSwtMjcuNTk4IDI1NS4wNzk5LC0yMS41OTggMjYxLjA3OTksLTE1LjU5OCAyNjcuMDc5OSwtMTUuNTk4IDI2Ny4wNzk5LC0xNS41OTggMzE3LjMxMjEsLTE1LjU5OCAzMTcuMzEyMSwtMTUuNTk4IDMyMy4zMTIxLC0xNS41OTggMzI5LjMxMjEsLTIxLjU5OCAzMjkuMzEyMSwtMjcuNTk4IDMyOS4zMTIxLC0yNy41OTggMzI5LjMxMjEsLTQ0LjQwMiAzMjkuMzEyMSwtNDQuNDAyIDMyOS4zMTIxLC01MC40MDIgMzIzLjMxMjEsLTU2LjQwMiAzMTcuMzEyMSwtNTYuNDAyIiAvPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjI5Mi4xOTYiIHk9Ii0zOS4zIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPnByZWQzPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjI5Mi4xOTYiIHk9Ii0yNi4xIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPmRpcmVjdGlvbmFsPC90ZXh0PjwvZz48IS0tIHByb3BfcDImIzQ1OyZndDtwcmVkX3ByZWQzIC0tPjxnIGlkPSJlZGdlNyIgY2xhc3M9ImVkZ2UiPjx0aXRsZT4KcHJvcF9wMi0mZ3Q7cHJlZF9wcmVkMwo8L3RpdGxlPgo8cGF0aCBmaWxsPSJub25lIiBzdHJva2U9IiM3YjkwOWYiIGQ9Ik0yMjMuMzA3OSwtMzZDMjMxLjEwMDgsLTM2IDIzOS40NDIyLC0zNiAyNDcuNTM0MywtMzYiIC8+PHBvbHlnb24gZmlsbD0iIzdiOTA5ZiIgc3Ryb2tlPSIjN2I5MDlmIiBwb2ludHM9IjI0Ny44NzMsLTM4LjQ1MDEgMjU0Ljg3MjksLTM2IDI0Ny44NzI5LC0zMy41NTAxIDI0Ny44NzMsLTM4LjQ1MDEiPjwvcG9seWdvbj48L2c+PCEtLSBwcm9wX3AzJiM0NTsmZ3Q7cHJlZF9wcmVkMSAtLT48ZyBpZD0iZWRnZTUiIGNsYXNzPSJlZGdlIj48dGl0bGU+CnByb3BfcDMtJmd0O3ByZWRfcHJlZDEKPC90aXRsZT4KPHBhdGggZmlsbD0ibm9uZSIgc3Ryb2tlPSIjN2I5MDlmIiBkPSJNMjE3LjAxOTEsLTExNS40MzU0QzIzMC4xMTc5LC0xMjMuMjAwNCAyNDUuNjAyNiwtMTMyLjM3OTYgMjU5LjEwNDEsLTE0MC4zODMzIiAvPjxwb2x5Z29uIGZpbGw9IiM3YjkwOWYiIHN0cm9rZT0iIzdiOTA5ZiIgcG9pbnRzPSIyNTcuODgxNCwtMTQyLjUwNjUgMjY1LjE1MjIsLTE0My45Njg2IDI2MC4zODAxLC0xMzguMjkxNSAyNTcuODgxNCwtMTQyLjUwNjUiPjwvcG9seWdvbj48L2c+PCEtLSBvdXRjb21lX3ByZWQxIC0tPjxnIGlkPSJub2RlMTAiIGNsYXNzPSJub2RlIj48dGl0bGU+Cm91dGNvbWVfcHJlZDEKPC90aXRsZT4KPHBhdGggZmlsbD0iI2U1ZjJlNyIgc3Ryb2tlPSIjM2U3YTQ2IiBzdHJva2Utd2lkdGg9IjEuMSIgZD0iTTQwOC45NDUyLC0xODAuNDAyQzQwOC45NDUyLC0xODAuNDAyIDM3My4wMjI0LC0xODAuNDAyIDM3My4wMjI0LC0xODAuNDAyIDM2Ny4wMjI0LC0xODAuNDAyIDM2MS4wMjI0LC0xNzQuNDAyIDM2MS4wMjI0LC0xNjguNDAyIDM2MS4wMjI0LC0xNjguNDAyIDM2MS4wMjI0LC0xNTEuNTk4IDM2MS4wMjI0LC0xNTEuNTk4IDM2MS4wMjI0LC0xNDUuNTk4IDM2Ny4wMjI0LC0xMzkuNTk4IDM3My4wMjI0LC0xMzkuNTk4IDM3My4wMjI0LC0xMzkuNTk4IDQwOC45NDUyLC0xMzkuNTk4IDQwOC45NDUyLC0xMzkuNTk4IDQxNC45NDUyLC0xMzkuNTk4IDQyMC45NDUyLC0xNDUuNTk4IDQyMC45NDUyLC0xNTEuNTk4IDQyMC45NDUyLC0xNTEuNTk4IDQyMC45NDUyLC0xNjguNDAyIDQyMC45NDUyLC0xNjguNDAyIDQyMC45NDUyLC0xNzQuNDAyIDQxNC45NDUyLC0xODAuNDAyIDQwOC45NDUyLC0xODAuNDAyIiAvPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjM5MC45ODM4IiB5PSItMTYzLjMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+cHJlZDE8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMzkwLjk4MzgiIHk9Ii0xNTAuMSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5wYXNzZWQ8L3RleHQ+PC9nPjwhLS0gcHJlZF9wcmVkMSYjNDU7Jmd0O291dGNvbWVfcHJlZDEgLS0+PGcgaWQ9ImVkZ2U4IiBjbGFzcz0iZWRnZSI+PHRpdGxlPgpwcmVkX3ByZWQxLSZndDtvdXRjb21lX3ByZWQxCjwvdGl0bGU+CjxwYXRoIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzdiOTA5ZiIgZD0iTTMxOS40NTE3LC0xNjBDMzMwLjAzOTUsLTE2MCAzNDIuMzM4MywtMTYwIDM1My43MjEsLTE2MCIgLz48cG9seWdvbiBmaWxsPSIjN2I5MDlmIiBzdHJva2U9IiM3YjkwOWYiIHBvaW50cz0iMzU0LjA0MTUsLTE2Mi40NTAxIDM2MS4wNDE1LC0xNjAgMzU0LjA0MTUsLTE1Ny41NTAxIDM1NC4wNDE1LC0xNjIuNDUwMSI+PC9wb2x5Z29uPjwvZz48L2c+PC9zdmc+)

The `context` view places the theory among the scope conditions under
which it is claimed to hold and the registered rivals it is meant to
outpredict.

``` r

cat(tf_diagram(theory, "context"))
```

    digraph context {
      graph [rankdir=LR, bgcolor="transparent", fontname="Helvetica", fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];
      node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", color="#33567A", fillcolor="#F2F6F9", fontcolor="#12283A", penwidth=1.1, margin="0.16,0.1"];
      edge [fontname="Helvetica", fontsize=10, color="#7B909F", fontcolor="#0F6E6E", arrowsize=0.7];
      "theory" [shape=ellipse, label="Network theory of\npanic disorder", fillcolor="#12283A", color="#12283A", fontcolor="#FFFFFF"];
      "c_arousal" [label="Physiological\narousal", fillcolor="#E4F1F1", color="#1E7B7B"];
      "theory" -> "c_arousal";
      "c_perceived_threat" [label="Perceived threat", fillcolor="#E4F1F1", color="#1E7B7B"];
      "theory" -> "c_perceived_threat";
      "c_avoidance" [label="Avoidance\nbehaviour", fillcolor="#E4F1F1", color="#1E7B7B"];
      "theory" -> "c_avoidance";
      "scope1" [shape=note, style="filled", label="adults", fillcolor="#FBF7EA", color="#B49B55"];
      "scope1" -> "theory" [style=dotted, label="holds within"];
      "scope2" [shape=note, style="filled", label="non-clinical\nbaseline", fillcolor="#FBF7EA", color="#B49B55"];
      "scope2" -> "theory" [style=dotted, label="holds within"];
      "scope3" [shape=note, style="filled", label="no beta-blocker\nmedication", fillcolor="#FBF7EA", color="#B49B55"];
      "scope3" -> "theory" [style=dotted, label="holds within"];
      "scope4" [shape=note, style="filled", label="waking hours", fillcolor="#FBF7EA", color="#B49B55"];
      "scope4" -> "theory" [style=dotted, label="holds within"];
      "scope5" [shape=note, style="filled", label="community sample", fillcolor="#FBF7EA", color="#B49B55"];
      "scope5" -> "theory" [style=dotted, label="holds within"];
      "alt_cognitive" [style="rounded,filled,dashed", label="Cognitive model of\npanic", fillcolor="#F1F1F1", color="#8A8A8A"];
      "theory" -> "alt_cognitive" [style=dashed, label="contrasts with"];
      "alt_biological" [style="rounded,filled,dashed", label="Biological model\nof panic", fillcolor="#F1F1F1", color="#8A8A8A"];
      "theory" -> "alt_biological" [style=dashed, label="contrasts with"];
    }

``` r

cat(
  '<div class="tf-figure tf-diagram">',
  tf_render_diagram(theory, "context", as = "svg"),
  '</div>',
  sep = ""
)
```

![](data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iNTkzcHQiIGhlaWdodD0iMzEzcHQiIHZpZXdib3g9IjAuMDAgMC4wMCA1OTIuNzEgMzEzLjIwIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHhtbG5zOnhsaW5rPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5L3hsaW5rIj48ZyBpZD0iZ3JhcGgwIiBjbGFzcz0iZ3JhcGgiIHRyYW5zZm9ybT0ic2NhbGUoMSAxKSByb3RhdGUoMCkgdHJhbnNsYXRlKDE0LjQgMjk4LjgpIj48dGl0bGU+CmNvbnRleHQKPC90aXRsZT4KPCEtLSB0aGVvcnkgLS0+PGcgaWQ9Im5vZGUxIiBjbGFzcz0ibm9kZSI+PHRpdGxlPgp0aGVvcnkKPC90aXRsZT4KPGVsbGlwc2UgZmlsbD0iIzEyMjgzYSIgc3Ryb2tlPSIjMTIyODNhIiBzdHJva2Utd2lkdGg9IjEuMSIgY3g9IjI3Ny44MDg0IiBjeT0iLTE0NC4yIiByeD0iNzcuODE3NSIgcnk9IjI4LjYzNDQiPjwvZWxsaXBzZT48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIyNzcuODA4NCIgeT0iLTE0Ny41IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiNmZmZmZmYiPk5ldHdvcmsKdGhlb3J5IG9mPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjI3Ny44MDg0IiB5PSItMTM0LjMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iI2ZmZmZmZiI+cGFuaWMKZGlzb3JkZXI8L3RleHQ+PC9nPjwhLS0gY19hcm91c2FsIC0tPjxnIGlkPSJub2RlMiIgY2xhc3M9Im5vZGUiPjx0aXRsZT4KY19hcm91c2FsCjwvdGl0bGU+CjxwYXRoIGZpbGw9IiNlNGYxZjEiIHN0cm9rZT0iIzFlN2I3YiIgc3Ryb2tlLXdpZHRoPSIxLjEiIGQ9Ik01MzguNTQ2NCwtMjg0LjYwMkM1MzguNTQ2NCwtMjg0LjYwMiA0NzQuMTk4LC0yODQuNjAyIDQ3NC4xOTgsLTI4NC42MDIgNDY4LjE5OCwtMjg0LjYwMiA0NjIuMTk4LC0yNzguNjAyIDQ2Mi4xOTgsLTI3Mi42MDIgNDYyLjE5OCwtMjcyLjYwMiA0NjIuMTk4LC0yNTUuNzk4IDQ2Mi4xOTgsLTI1NS43OTggNDYyLjE5OCwtMjQ5Ljc5OCA0NjguMTk4LC0yNDMuNzk4IDQ3NC4xOTgsLTI0My43OTggNDc0LjE5OCwtMjQzLjc5OCA1MzguNTQ2NCwtMjQzLjc5OCA1MzguNTQ2NCwtMjQzLjc5OCA1NDQuNTQ2NCwtMjQzLjc5OCA1NTAuNTQ2NCwtMjQ5Ljc5OCA1NTAuNTQ2NCwtMjU1Ljc5OCA1NTAuNTQ2NCwtMjU1Ljc5OCA1NTAuNTQ2NCwtMjcyLjYwMiA1NTAuNTQ2NCwtMjcyLjYwMiA1NTAuNTQ2NCwtMjc4LjYwMiA1NDQuNTQ2NCwtMjg0LjYwMiA1MzguNTQ2NCwtMjg0LjYwMiIgLz48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI1MDYuMzcyMiIgeT0iLTI2Ny41IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPlBoeXNpb2xvZ2ljYWw8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iNTA2LjM3MjIiIHk9Ii0yNTQuMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5hcm91c2FsPC90ZXh0PjwvZz48IS0tIHRoZW9yeSYjNDU7Jmd0O2NfYXJvdXNhbCAtLT48ZyBpZD0iZWRnZTEiIGNsYXNzPSJlZGdlIj48dGl0bGU+CnRoZW9yeS0mZ3Q7Y19hcm91c2FsCjwvdGl0bGU+CjxwYXRoIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzdiOTA5ZiIgZD0iTTMyMi4xODcyLC0xNjcuOTQzOUMzMzcuODIzOCwtMTc2LjI3OTQgMzU1LjUzNDMsLTE4NS42ODU5IDM3MS43MTcsLTE5NC4yIDQwMS4yNzM3LC0yMDkuNzUwNSA0MzQuNTc0MSwtMjI3LjA2MzQgNDYwLjY2NDQsLTI0MC41ODA4IiAvPjxwb2x5Z29uIGZpbGw9IiM3YjkwOWYiIHN0cm9rZT0iIzdiOTA5ZiIgcG9pbnRzPSI0NTkuNzkzLC0yNDIuODg4NSA0NjcuMTM1NSwtMjQzLjkzMjMgNDYyLjA0NjUsLTIzOC41Mzc1IDQ1OS43OTMsLTI0Mi44ODg1Ij48L3BvbHlnb24+PC9nPjwhLS0gY19wZXJjZWl2ZWRfdGhyZWF0IC0tPjxnIGlkPSJub2RlMyIgY2xhc3M9Im5vZGUiPjx0aXRsZT4KY19wZXJjZWl2ZWRfdGhyZWF0CjwvdGl0bGU+CjxwYXRoIGZpbGw9IiNlNGYxZjEiIHN0cm9rZT0iIzFlN2I3YiIgc3Ryb2tlLXdpZHRoPSIxLjEiIGQ9Ik01NDYuNDQ3OCwtMjIyLjJDNTQ2LjQ0NzgsLTIyMi4yIDQ2Ni4yOTY2LC0yMjIuMiA0NjYuMjk2NiwtMjIyLjIgNDYwLjI5NjYsLTIyMi4yIDQ1NC4yOTY2LC0yMTYuMiA0NTQuMjk2NiwtMjEwLjIgNDU0LjI5NjYsLTIxMC4yIDQ1NC4yOTY2LC0xOTguMiA0NTQuMjk2NiwtMTk4LjIgNDU0LjI5NjYsLTE5Mi4yIDQ2MC4yOTY2LC0xODYuMiA0NjYuMjk2NiwtMTg2LjIgNDY2LjI5NjYsLTE4Ni4yIDU0Ni40NDc4LC0xODYuMiA1NDYuNDQ3OCwtMTg2LjIgNTUyLjQ0NzgsLTE4Ni4yIDU1OC40NDc4LC0xOTIuMiA1NTguNDQ3OCwtMTk4LjIgNTU4LjQ0NzgsLTE5OC4yIDU1OC40NDc4LC0yMTAuMiA1NTguNDQ3OCwtMjEwLjIgNTU4LjQ0NzgsLTIxNi4yIDU1Mi40NDc4LC0yMjIuMiA1NDYuNDQ3OCwtMjIyLjIiIC8+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iNTA2LjM3MjIiIHk9Ii0yMDAuOSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5QZXJjZWl2ZWQKdGhyZWF0PC90ZXh0PjwvZz48IS0tIHRoZW9yeSYjNDU7Jmd0O2NfcGVyY2VpdmVkX3RocmVhdCAtLT48ZyBpZD0iZWRnZTIiIGNsYXNzPSJlZGdlIj48dGl0bGU+CnRoZW9yeS0mZ3Q7Y19wZXJjZWl2ZWRfdGhyZWF0CjwvdGl0bGU+CjxwYXRoIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzdiOTA5ZiIgZD0iTTM0MS4xNzI2LC0xNjAuODMzN0MzNzQuMzUxMiwtMTY5LjU0MzMgNDE0LjcyNzIsLTE4MC4xNDI0IDQ0Ny4yNTczLC0xODguNjgxOCIgLz48cG9seWdvbiBmaWxsPSIjN2I5MDlmIiBzdHJva2U9IiM3YjkwOWYiIHBvaW50cz0iNDQ2LjY4MTcsLTE5MS4wNjM3IDQ1NC4wNzQ0LC0xOTAuNDcxNCA0NDcuOTI1OSwtMTg2LjMyNDMgNDQ2LjY4MTcsLTE5MS4wNjM3Ij48L3BvbHlnb24+PC9nPjwhLS0gY19hdm9pZGFuY2UgLS0+PGcgaWQ9Im5vZGU0IiBjbGFzcz0ibm9kZSI+PHRpdGxlPgpjX2F2b2lkYW5jZQo8L3RpdGxlPgo8cGF0aCBmaWxsPSIjZTRmMWYxIiBzdHJva2U9IiMxZTdiN2IiIHN0cm9rZS13aWR0aD0iMS4xIiBkPSJNNTMyLjIyNDMsLTE2NC42MDJDNTMyLjIyNDMsLTE2NC42MDIgNDgwLjUyMDEsLTE2NC42MDIgNDgwLjUyMDEsLTE2NC42MDIgNDc0LjUyMDEsLTE2NC42MDIgNDY4LjUyMDEsLTE1OC42MDIgNDY4LjUyMDEsLTE1Mi42MDIgNDY4LjUyMDEsLTE1Mi42MDIgNDY4LjUyMDEsLTEzNS43OTggNDY4LjUyMDEsLTEzNS43OTggNDY4LjUyMDEsLTEyOS43OTggNDc0LjUyMDEsLTEyMy43OTggNDgwLjUyMDEsLTEyMy43OTggNDgwLjUyMDEsLTEyMy43OTggNTMyLjIyNDMsLTEyMy43OTggNTMyLjIyNDMsLTEyMy43OTggNTM4LjIyNDMsLTEyMy43OTggNTQ0LjIyNDMsLTEyOS43OTggNTQ0LjIyNDMsLTEzNS43OTggNTQ0LjIyNDMsLTEzNS43OTggNTQ0LjIyNDMsLTE1Mi42MDIgNTQ0LjIyNDMsLTE1Mi42MDIgNTQ0LjIyNDMsLTE1OC42MDIgNTM4LjIyNDMsLTE2NC42MDIgNTMyLjIyNDMsLTE2NC42MDIiIC8+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iNTA2LjM3MjIiIHk9Ii0xNDcuNSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5Bdm9pZGFuY2U8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iNTA2LjM3MjIiIHk9Ii0xMzQuMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5iZWhhdmlvdXI8L3RleHQ+PC9nPjwhLS0gdGhlb3J5JiM0NTsmZ3Q7Y19hdm9pZGFuY2UgLS0+PGcgaWQ9ImVkZ2UzIiBjbGFzcz0iZWRnZSI+PHRpdGxlPgp0aGVvcnktJmd0O2NfYXZvaWRhbmNlCjwvdGl0bGU+CjxwYXRoIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzdiOTA5ZiIgZD0iTTM1NS44Mjc4LC0xNDQuMkMzOTEuMDI2OCwtMTQ0LjIgNDMxLjM0NTksLTE0NC4yIDQ2MS4zOTQyLC0xNDQuMiIgLz48cG9seWdvbiBmaWxsPSIjN2I5MDlmIiBzdHJva2U9IiM3YjkwOWYiIHBvaW50cz0iNDYxLjQxNTEsLTE0Ni42NTAxIDQ2OC40MTUxLC0xNDQuMiA0NjEuNDE1MSwtMTQxLjc1MDEgNDYxLjQxNTEsLTE0Ni42NTAxIj48L3BvbHlnb24+PC9nPjwhLS0gYWx0X2NvZ25pdGl2ZSAtLT48ZyBpZD0ibm9kZTEwIiBjbGFzcz0ibm9kZSI+PHRpdGxlPgphbHRfY29nbml0aXZlCjwvdGl0bGU+CjxwYXRoIGZpbGw9IiNmMWYxZjEiIHN0cm9rZT0iIzhhOGE4YSIgc3Ryb2tlLXdpZHRoPSIxLjEiIHN0cm9rZS1kYXNoYXJyYXk9IjUsMiIgZD0iTTU1MS45NDQ1LC0xMDIuNjAyQzU1MS45NDQ1LC0xMDIuNjAyIDQ2MC43OTk5LC0xMDIuNjAyIDQ2MC43OTk5LC0xMDIuNjAyIDQ1NC43OTk5LC0xMDIuNjAyIDQ0OC43OTk5LC05Ni42MDIgNDQ4Ljc5OTksLTkwLjYwMiA0NDguNzk5OSwtOTAuNjAyIDQ0OC43OTk5LC03My43OTggNDQ4Ljc5OTksLTczLjc5OCA0NDguNzk5OSwtNjcuNzk4IDQ1NC43OTk5LC02MS43OTggNDYwLjc5OTksLTYxLjc5OCA0NjAuNzk5OSwtNjEuNzk4IDU1MS45NDQ1LC02MS43OTggNTUxLjk0NDUsLTYxLjc5OCA1NTcuOTQ0NSwtNjEuNzk4IDU2My45NDQ1LC02Ny43OTggNTYzLjk0NDUsLTczLjc5OCA1NjMuOTQ0NSwtNzMuNzk4IDU2My45NDQ1LC05MC42MDIgNTYzLjk0NDUsLTkwLjYwMiA1NjMuOTQ0NSwtOTYuNjAyIDU1Ny45NDQ1LC0xMDIuNjAyIDU1MS45NDQ1LC0xMDIuNjAyIiAvPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjUwNi4zNzIyIiB5PSItODUuNSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5Db2duaXRpdmUKbW9kZWwgb2Y8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iNTA2LjM3MjIiIHk9Ii03Mi4zIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPnBhbmljPC90ZXh0PjwvZz48IS0tIHRoZW9yeSYjNDU7Jmd0O2FsdF9jb2duaXRpdmUgLS0+PGcgaWQ9ImVkZ2U5IiBjbGFzcz0iZWRnZSI+PHRpdGxlPgp0aGVvcnktJmd0O2FsdF9jb2duaXRpdmUKPC90aXRsZT4KPHBhdGggZmlsbD0ibm9uZSIgc3Ryb2tlPSIjN2I5MDlmIiBzdHJva2UtZGFzaGFycmF5PSI1LDIiIGQ9Ik0zNDAuNTY2OCwtMTI3LjE3NjJDMzcxLjg5NzEsLTExOC42Nzc2IDQwOS43NjE2LC0xMDguNDA2NSA0NDEuMzkyMiwtOTkuODI2NCIgLz48cG9seWdvbiBmaWxsPSIjN2I5MDlmIiBzdHJva2U9IiM3YjkwOWYiIHBvaW50cz0iNDQyLjM0MiwtMTAyLjEwNzQgNDQ4LjQ1NjQsLTk3LjkxMDIgNDQxLjA1OTEsLTk3LjM3ODMgNDQyLjM0MiwtMTAyLjEwNzQiPjwvcG9seWdvbj48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI0MDIuMjc2NSIgeT0iLTExOS4yIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTAuMDAiIGZpbGw9IiMwZjZlNmUiPmNvbnRyYXN0cwp3aXRoPC90ZXh0PjwvZz48IS0tIGFsdF9iaW9sb2dpY2FsIC0tPjxnIGlkPSJub2RlMTEiIGNsYXNzPSJub2RlIj48dGl0bGU+CmFsdF9iaW9sb2dpY2FsCjwvdGl0bGU+CjxwYXRoIGZpbGw9IiNmMWYxZjEiIHN0cm9rZT0iIzhhOGE4YSIgc3Ryb2tlLXdpZHRoPSIxLjEiIHN0cm9rZS1kYXNoYXJyYXk9IjUsMiIgZD0iTTU0Ni40MzU3LC00MC42MDJDNTQ2LjQzNTcsLTQwLjYwMiA0NjYuMzA4NywtNDAuNjAyIDQ2Ni4zMDg3LC00MC42MDIgNDYwLjMwODcsLTQwLjYwMiA0NTQuMzA4NywtMzQuNjAyIDQ1NC4zMDg3LC0yOC42MDIgNDU0LjMwODcsLTI4LjYwMiA0NTQuMzA4NywtMTEuNzk4IDQ1NC4zMDg3LC0xMS43OTggNDU0LjMwODcsLTUuNzk4IDQ2MC4zMDg3LC4yMDIgNDY2LjMwODcsLjIwMiA0NjYuMzA4NywuMjAyIDU0Ni40MzU3LC4yMDIgNTQ2LjQzNTcsLjIwMiA1NTIuNDM1NywuMjAyIDU1OC40MzU3LC01Ljc5OCA1NTguNDM1NywtMTEuNzk4IDU1OC40MzU3LC0xMS43OTggNTU4LjQzNTcsLTI4LjYwMiA1NTguNDM1NywtMjguNjAyIDU1OC40MzU3LC0zNC42MDIgNTUyLjQzNTcsLTQwLjYwMiA1NDYuNDM1NywtNDAuNjAyIiAvPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjUwNi4zNzIyIiB5PSItMjMuNSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5CaW9sb2dpY2FsCm1vZGVsPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjUwNi4zNzIyIiB5PSItMTAuMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5vZgpwYW5pYzwvdGV4dD48L2c+PCEtLSB0aGVvcnkmIzQ1OyZndDthbHRfYmlvbG9naWNhbCAtLT48ZyBpZD0iZWRnZTEwIiBjbGFzcz0iZWRnZSI+PHRpdGxlPgp0aGVvcnktJmd0O2FsdF9iaW9sb2dpY2FsCjwvdGl0bGU+CjxwYXRoIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzdiOTA5ZiIgc3Ryb2tlLWRhc2hhcnJheT0iNSwyIiBkPSJNMzE1LjYwOTYsLTExOS4xMDdDMzMyLjUxNDIsLTEwOC4yMzc1IDM1Mi44NDc2LC05NS42Mzk1IDM3MS43MTcsLTg1LjIgMzk4LjUxMDUsLTcwLjM3NjUgNDI5LjIwMTgsLTU1LjQxMzEgNDU0LjUxMDEsLTQzLjU4NjEiIC8+PHBvbHlnb24gZmlsbD0iIzdiOTA5ZiIgc3Ryb2tlPSIjN2I5MDlmIiBwb2ludHM9IjQ1NS44NDU4LC00NS42NjY5IDQ2MS4xNTkzLC00MC40OTI5IDQ1My43NzksLTQxLjIyNDEgNDU1Ljg0NTgsLTQ1LjY2NjkiPjwvcG9seWdvbj48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI0MDIuMjc2NSIgeT0iLTg4LjIiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMC4wMCIgZmlsbD0iIzBmNmU2ZSI+Y29udHJhc3RzCndpdGg8L3RleHQ+PC9nPjwhLS0gc2NvcGUxIC0tPjxnIGlkPSJub2RlNSIgY2xhc3M9Im5vZGUiPjx0aXRsZT4Kc2NvcGUxCjwvdGl0bGU+Cjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjU3LjgzNTMiIHk9Ii0yNjIuOSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5hZHVsdHM8L3RleHQ+PC9nPjwhLS0gc2NvcGUxJiM0NTsmZ3Q7dGhlb3J5IC0tPjxnIGlkPSJlZGdlNCIgY2xhc3M9ImVkZ2UiPjx0aXRsZT4Kc2NvcGUxLSZndDt0aGVvcnkKPC90aXRsZT4KPHBhdGggZmlsbD0ibm9uZSIgc3Ryb2tlPSIjN2I5MDlmIiBzdHJva2UtZGFzaGFycmF5PSIxLDUiIGQ9Ik04NC45NjM0LC0yNTIuNzQyNEM5NC42NzI3LC0yNDcuODg3NiAxMDUuNjgyNiwtMjQyLjMzODUgMTE1LjY3MDcsLTIzNy4yIDE0Ni4xNTg5LC0yMjEuNTE1MSAxNTQuMDY5NCwtMjE4LjEwMjcgMTgzLjg5OTcsLTIwMS4yIDE5OS44NjY3LC0xOTIuMTUyNiAyMTcuMDk4NiwtMTgxLjg1MzMgMjMyLjM4ODMsLTE3Mi41MjE1IiAvPjxwb2x5Z29uIGZpbGw9IiM3YjkwOWYiIHN0cm9rZT0iIzdiOTA5ZiIgcG9pbnRzPSIyMzMuNjc2LC0xNzQuNjA1OSAyMzguMzY3LC0xNjguODYxNiAyMzEuMTE3NywtMTcwLjQyNjcgMjMzLjY3NiwtMTc0LjYwNTkiPjwvcG9seWdvbj48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIxNTcuNzg1MiIgeT0iLTIzMS4yIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTAuMDAiIGZpbGw9IiMwZjZlNmUiPmhvbGRzCndpdGhpbjwvdGV4dD48L2c+PCEtLSBzY29wZTIgLS0+PGcgaWQ9Im5vZGU2IiBjbGFzcz0ibm9kZSI+PHRpdGxlPgpzY29wZTIKPC90aXRsZT4KPHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iNTcuODM1MyIgeT0iLTIwOS41IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPm5vbi1jbGluaWNhbDwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI1Ny44MzUzIiB5PSItMTk2LjMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+YmFzZWxpbmU8L3RleHQ+PC9nPjwhLS0gc2NvcGUyJiM0NTsmZ3Q7dGhlb3J5IC0tPjxnIGlkPSJlZGdlNSIgY2xhc3M9ImVkZ2UiPjx0aXRsZT4Kc2NvcGUyLSZndDt0aGVvcnkKPC90aXRsZT4KPHBhdGggZmlsbD0ibm9uZSIgc3Ryb2tlPSIjN2I5MDlmIiBzdHJva2UtZGFzaGFycmF5PSIxLDUiIGQ9Ik05Ny40MTYyLC0xOTUuMDQ0QzEyOC4zOTEsLTE4Ni4zMTM3IDE3Mi4yMTgzLC0xNzMuOTYwOCAyMDguOTE2NiwtMTYzLjYxNzMiIC8+PHBvbHlnb24gZmlsbD0iIzdiOTA5ZiIgc3Ryb2tlPSIjN2I5MDlmIiBwb2ludHM9IjIwOS42MDg1LC0xNjUuOTY3OSAyMTUuNjgxMywtMTYxLjcxMDcgMjA4LjI3OTIsLTE2MS4yNTE2IDIwOS42MDg1LC0xNjUuOTY3OSI+PC9wb2x5Z29uPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjE1Ny43ODUyIiB5PSItMTg3LjIiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMC4wMCIgZmlsbD0iIzBmNmU2ZSI+aG9sZHMKd2l0aGluPC90ZXh0PjwvZz48IS0tIHNjb3BlMyAtLT48ZyBpZD0ibm9kZTciIGNsYXNzPSJub2RlIj48dGl0bGU+CnNjb3BlMwo8L3RpdGxlPgo8dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI1Ny44MzUzIiB5PSItMTQ3LjUiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+bm8KYmV0YS1ibG9ja2VyPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjU3LjgzNTMiIHk9Ii0xMzQuMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5tZWRpY2F0aW9uPC90ZXh0PjwvZz48IS0tIHNjb3BlMyYjNDU7Jmd0O3RoZW9yeSAtLT48ZyBpZD0iZWRnZTYiIGNsYXNzPSJlZGdlIj48dGl0bGU+CnNjb3BlMy0mZ3Q7dGhlb3J5CjwvdGl0bGU+CjxwYXRoIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzdiOTA5ZiIgc3Ryb2tlLWRhc2hhcnJheT0iMSw1IiBkPSJNMTA3Ljc1MDYsLTE0NC4yQzEzMi43NTgxLC0xNDQuMiAxNjMuNzQyMSwtMTQ0LjIgMTkyLjM4NDIsLTE0NC4yIiAvPjxwb2x5Z29uIGZpbGw9IiM3YjkwOWYiIHN0cm9rZT0iIzdiOTA5ZiIgcG9pbnRzPSIxOTIuNjEwNiwtMTQ2LjY1MDEgMTk5LjYxMDUsLTE0NC4yIDE5Mi42MTA1LC0xNDEuNzUwMSAxOTIuNjEwNiwtMTQ2LjY1MDEiPjwvcG9seWdvbj48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIxNTcuNzg1MiIgeT0iLTE0Ny4yIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTAuMDAiIGZpbGw9IiMwZjZlNmUiPmhvbGRzCndpdGhpbjwvdGV4dD48L2c+PCEtLSBzY29wZTQgLS0+PGcgaWQ9Im5vZGU4IiBjbGFzcz0ibm9kZSI+PHRpdGxlPgpzY29wZTQKPC90aXRsZT4KPHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iNTcuODM1MyIgeT0iLTgwLjkiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+d2FraW5nCmhvdXJzPC90ZXh0PjwvZz48IS0tIHNjb3BlNCYjNDU7Jmd0O3RoZW9yeSAtLT48ZyBpZD0iZWRnZTciIGNsYXNzPSJlZGdlIj48dGl0bGU+CnNjb3BlNC0mZ3Q7dGhlb3J5CjwvdGl0bGU+CjxwYXRoIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzdiOTA5ZiIgc3Ryb2tlLWRhc2hhcnJheT0iMSw1IiBkPSJNMTAyLjM1MDIsLTk2LjM0MTlDMTMyLjcxNTMsLTEwNC42MjQzIDE3My41NDgzLC0xMTUuNzYxOSAyMDguMTgyMiwtMTI1LjIwODciIC8+PHBvbHlnb24gZmlsbD0iIzdiOTA5ZiIgc3Ryb2tlPSIjN2I5MDlmIiBwb2ludHM9IjIwNy42MjMzLC0xMjcuNTk1NyAyMTUuMDIxMywtMTI3LjA3NDIgMjA4LjkxMjgsLTEyMi44Njg0IDIwNy42MjMzLC0xMjcuNTk1NyI+PC9wb2x5Z29uPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjE1Ny43ODUyIiB5PSItMTIwLjIiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMC4wMCIgZmlsbD0iIzBmNmU2ZSI+aG9sZHMKd2l0aGluPC90ZXh0PjwvZz48IS0tIHNjb3BlNSAtLT48ZyBpZD0ibm9kZTkiIGNsYXNzPSJub2RlIj48dGl0bGU+CnNjb3BlNQo8L3RpdGxlPgo8dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI1Ny44MzUzIiB5PSItMjIuOSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5jb21tdW5pdHkKc2FtcGxlPC90ZXh0PjwvZz48IS0tIHNjb3BlNSYjNDU7Jmd0O3RoZW9yeSAtLT48ZyBpZD0iZWRnZTgiIGNsYXNzPSJlZGdlIj48dGl0bGU+CnNjb3BlNS0mZ3Q7dGhlb3J5CjwvdGl0bGU+CjxwYXRoIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzdiOTA5ZiIgc3Ryb2tlLWRhc2hhcnJheT0iMSw1IiBkPSJNOTYuNTg4NSwtNDQuMjYzNUMxMjEuNzM2LC01Ni4yMjg1IDE1NS4wNzAzLC03Mi41NDc4IDE4My44OTk3LC04OC4yIDE5OS42NjQ0LC05Ni43NTkgMjE2LjU4NjgsLTEwNi42Mjk5IDIzMS42NjM5LC0xMTUuNjc3OCIgLz48cG9seWdvbiBmaWxsPSIjN2I5MDlmIiBzdHJva2U9IiM3YjkwOWYiIHBvaW50cz0iMjMwLjc0MzgsLTExNy45ODM5IDIzOC4wMDM4LC0xMTkuNDk4OSAyMzMuMjczMiwtMTEzLjc4NzEgMjMwLjc0MzgsLTExNy45ODM5Ij48L3BvbHlnb24+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMTU3Ljc4NTIiIHk9Ii05MS4yIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTAuMDAiIGZpbGw9IiMwZjZlNmUiPmhvbGRzCndpdGhpbjwvdGV4dD48L2c+PC9nPjwvc3ZnPg==)

The `pipeline` view links each prediction to its recorded test outcome,
so predictions still awaiting a test are visible as loose ends.

``` r

cat(tf_diagram(theory, "pipeline"))
```

    digraph pipeline {
      graph [rankdir=LR, bgcolor="transparent", fontname="Helvetica", fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];
      node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", color="#33567A", fillcolor="#F2F6F9", fontcolor="#12283A", penwidth=1.1, margin="0.16,0.1"];
      edge [fontname="Helvetica", fontsize=10, color="#7B909F", fontcolor="#0F6E6E", arrowsize=0.7];
      "pred1" [label="pred1\npoint", fillcolor="#E7EDF5", color="#33567A"];
      "pred2" [label="pred2\ninterval", fillcolor="#E7EDF5", color="#33567A"];
      "pred3" [label="pred3\ndirectional", fillcolor="#E7EDF5", color="#33567A"];
      "result_pred1" [label="passed", fillcolor="#E5F2E7", color="#3E7A46"];
      "pred1" -> "result_pred1";
    }

``` r

cat(
  '<div class="tf-figure tf-diagram">',
  tf_render_diagram(theory, "pipeline", as = "svg"),
  '</div>',
  sep = ""
)
```

![](data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTk0cHQiIGhlaWdodD0iMTkzcHQiIHZpZXdib3g9IjAuMDAgMC4wMCAxOTQuMzggMTkzLjIwIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHhtbG5zOnhsaW5rPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5L3hsaW5rIj48ZyBpZD0iZ3JhcGgwIiBjbGFzcz0iZ3JhcGgiIHRyYW5zZm9ybT0ic2NhbGUoMSAxKSByb3RhdGUoMCkgdHJhbnNsYXRlKDE0LjQgMTc4LjgpIj48dGl0bGU+CnBpcGVsaW5lCjwvdGl0bGU+CjwhLS0gcHJlZDEgLS0+PGcgaWQ9Im5vZGUxIiBjbGFzcz0ibm9kZSI+PHRpdGxlPgpwcmVkMQo8L3RpdGxlPgo8cGF0aCBmaWxsPSIjZTdlZGY1IiBzdHJva2U9IiMzMzU2N2EiIHN0cm9rZS13aWR0aD0iMS4xIiBkPSJNNTIuMDU4LC00MC42MDJDNTIuMDU4LC00MC42MDIgMjIuMDU4LC00MC42MDIgMjIuMDU4LC00MC42MDIgMTYuMDU4LC00MC42MDIgMTAuMDU4LC0zNC42MDIgMTAuMDU4LC0yOC42MDIgMTAuMDU4LC0yOC42MDIgMTAuMDU4LC0xMS43OTggMTAuMDU4LC0xMS43OTggMTAuMDU4LC01Ljc5OCAxNi4wNTgsLjIwMiAyMi4wNTgsLjIwMiAyMi4wNTgsLjIwMiA1Mi4wNTgsLjIwMiA1Mi4wNTgsLjIwMiA1OC4wNTgsLjIwMiA2NC4wNTgsLTUuNzk4IDY0LjA1OCwtMTEuNzk4IDY0LjA1OCwtMTEuNzk4IDY0LjA1OCwtMjguNjAyIDY0LjA1OCwtMjguNjAyIDY0LjA1OCwtMzQuNjAyIDU4LjA1OCwtNDAuNjAyIDUyLjA1OCwtNDAuNjAyIiAvPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjM3LjA1OCIgeT0iLTIzLjUiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+cHJlZDE8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMzcuMDU4IiB5PSItMTAuMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5wb2ludDwvdGV4dD48L2c+PCEtLSByZXN1bHRfcHJlZDEgLS0+PGcgaWQ9Im5vZGU0IiBjbGFzcz0ibm9kZSI+PHRpdGxlPgpyZXN1bHRfcHJlZDEKPC90aXRsZT4KPHBhdGggZmlsbD0iI2U1ZjJlNyIgc3Ryb2tlPSIjM2U3YTQ2IiBzdHJva2Utd2lkdGg9IjEuMSIgZD0iTTE1My44MDcyLC0zOC4yQzE1My44MDcyLC0zOC4yIDExNy44ODQ0LC0zOC4yIDExNy44ODQ0LC0zOC4yIDExMS44ODQ0LC0zOC4yIDEwNS44ODQ0LC0zMi4yIDEwNS44ODQ0LC0yNi4yIDEwNS44ODQ0LC0yNi4yIDEwNS44ODQ0LC0xNC4yIDEwNS44ODQ0LC0xNC4yIDEwNS44ODQ0LC04LjIgMTExLjg4NDQsLTIuMiAxMTcuODg0NCwtMi4yIDExNy44ODQ0LC0yLjIgMTUzLjgwNzIsLTIuMiAxNTMuODA3MiwtMi4yIDE1OS44MDcyLC0yLjIgMTY1LjgwNzIsLTguMiAxNjUuODA3MiwtMTQuMiAxNjUuODA3MiwtMTQuMiAxNjUuODA3MiwtMjYuMiAxNjUuODA3MiwtMjYuMiAxNjUuODA3MiwtMzIuMiAxNTkuODA3MiwtMzguMiAxNTMuODA3MiwtMzguMiIgLz48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIxMzUuODQ1OCIgeT0iLTE2LjkiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+cGFzc2VkPC90ZXh0PjwvZz48IS0tIHByZWQxJiM0NTsmZ3Q7cmVzdWx0X3ByZWQxIC0tPjxnIGlkPSJlZGdlMSIgY2xhc3M9ImVkZ2UiPjx0aXRsZT4KcHJlZDEtJmd0O3Jlc3VsdF9wcmVkMQo8L3RpdGxlPgo8cGF0aCBmaWxsPSJub25lIiBzdHJva2U9IiM3YjkwOWYiIGQ9Ik02NC4zMTM3LC0yMC4yQzc0LjkwMTUsLTIwLjIgODcuMjAwMywtMjAuMiA5OC41ODMsLTIwLjIiIC8+PHBvbHlnb24gZmlsbD0iIzdiOTA5ZiIgc3Ryb2tlPSIjN2I5MDlmIiBwb2ludHM9Ijk4LjkwMzUsLTIyLjY1MDEgMTA1LjkwMzUsLTIwLjIgOTguOTAzNSwtMTcuNzUwMSA5OC45MDM1LC0yMi42NTAxIj48L3BvbHlnb24+PC9nPjwhLS0gcHJlZDIgLS0+PGcgaWQ9Im5vZGUyIiBjbGFzcz0ibm9kZSI+PHRpdGxlPgpwcmVkMgo8L3RpdGxlPgo8cGF0aCBmaWxsPSIjZTdlZGY1IiBzdHJva2U9IiMzMzU2N2EiIHN0cm9rZS13aWR0aD0iMS4xIiBkPSJNNTUuMDA1LC0xMDIuNjAyQzU1LjAwNSwtMTAyLjYwMiAxOS4xMTEsLTEwMi42MDIgMTkuMTExLC0xMDIuNjAyIDEzLjExMSwtMTAyLjYwMiA3LjExMSwtOTYuNjAyIDcuMTExLC05MC42MDIgNy4xMTEsLTkwLjYwMiA3LjExMSwtNzMuNzk4IDcuMTExLC03My43OTggNy4xMTEsLTY3Ljc5OCAxMy4xMTEsLTYxLjc5OCAxOS4xMTEsLTYxLjc5OCAxOS4xMTEsLTYxLjc5OCA1NS4wMDUsLTYxLjc5OCA1NS4wMDUsLTYxLjc5OCA2MS4wMDUsLTYxLjc5OCA2Ny4wMDUsLTY3Ljc5OCA2Ny4wMDUsLTczLjc5OCA2Ny4wMDUsLTczLjc5OCA2Ny4wMDUsLTkwLjYwMiA2Ny4wMDUsLTkwLjYwMiA2Ny4wMDUsLTk2LjYwMiA2MS4wMDUsLTEwMi42MDIgNTUuMDA1LC0xMDIuNjAyIiAvPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjM3LjA1OCIgeT0iLTg1LjUiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+cHJlZDI8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMzcuMDU4IiB5PSItNzIuMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5pbnRlcnZhbDwvdGV4dD48L2c+PCEtLSBwcmVkMyAtLT48ZyBpZD0ibm9kZTMiIGNsYXNzPSJub2RlIj48dGl0bGU+CnByZWQzCjwvdGl0bGU+CjxwYXRoIGZpbGw9IiNlN2VkZjUiIHN0cm9rZT0iIzMzNTY3YSIgc3Ryb2tlLXdpZHRoPSIxLjEiIGQ9Ik02Mi4xNzQxLC0xNjQuNjAyQzYyLjE3NDEsLTE2NC42MDIgMTEuOTQxOSwtMTY0LjYwMiAxMS45NDE5LC0xNjQuNjAyIDUuOTQxOSwtMTY0LjYwMiAtLjA1ODEsLTE1OC42MDIgLS4wNTgxLC0xNTIuNjAyIC0uMDU4MSwtMTUyLjYwMiAtLjA1ODEsLTEzNS43OTggLS4wNTgxLC0xMzUuNzk4IC0uMDU4MSwtMTI5Ljc5OCA1Ljk0MTksLTEyMy43OTggMTEuOTQxOSwtMTIzLjc5OCAxMS45NDE5LC0xMjMuNzk4IDYyLjE3NDEsLTEyMy43OTggNjIuMTc0MSwtMTIzLjc5OCA2OC4xNzQxLC0xMjMuNzk4IDc0LjE3NDEsLTEyOS43OTggNzQuMTc0MSwtMTM1Ljc5OCA3NC4xNzQxLC0xMzUuNzk4IDc0LjE3NDEsLTE1Mi42MDIgNzQuMTc0MSwtMTUyLjYwMiA3NC4xNzQxLC0xNTguNjAyIDY4LjE3NDEsLTE2NC42MDIgNjIuMTc0MSwtMTY0LjYwMiIgLz48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIzNy4wNTgiIHk9Ii0xNDcuNSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5wcmVkMzwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIzNy4wNTgiIHk9Ii0xMzQuMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5kaXJlY3Rpb25hbDwvdGV4dD48L2c+PC9nPjwvc3ZnPg==)

The `provenance` view draws the build log as a digraph, so the record of
how the theory reached its current state travels with the object itself.

``` r

cat(tf_diagram(theory, "provenance"))
```

    digraph provenance {
      graph [rankdir=TB, bgcolor="transparent", fontname="Helvetica", fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];
      node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", color="#33567A", fillcolor="#F2F6F9", fontcolor="#12283A", penwidth=1.1, margin="0.16,0.1"];
      edge [fontname="Helvetica", fontsize=10, color="#7B909F", fontcolor="#0F6E6E", arrowsize=0.7];
      "n1" [label="tf_add_construct\nRegistered three\nconstructs."];
      "n2" [label="tf_add_proposition\nLinked constructs into a\nfeedback network."];
      "n3" [label="tf_add_prediction\nDerived three predictions\nfrom the propositions."];
      "n1" -> "n2";
      "n2" -> "n3";
    }

``` r

cat(
  '<div class="tf-figure tf-diagram">',
  tf_render_diagram(theory, "provenance", as = "svg"),
  '</div>',
  sep = ""
)
```

![](data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTc1cHQiIGhlaWdodD0iMjU0cHQiIHZpZXdib3g9IjAuMDAgMC4wMCAxNzUuMDQgMjUzLjYwIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHhtbG5zOnhsaW5rPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5L3hsaW5rIj48ZyBpZD0iZ3JhcGgwIiBjbGFzcz0iZ3JhcGgiIHRyYW5zZm9ybT0ic2NhbGUoMSAxKSByb3RhdGUoMCkgdHJhbnNsYXRlKDE0LjQgMjM5LjIpIj48dGl0bGU+CnByb3ZlbmFuY2UKPC90aXRsZT4KPCEtLSBuMSAtLT48ZyBpZD0ibm9kZTEiIGNsYXNzPSJub2RlIj48dGl0bGU+Cm4xCjwvdGl0bGU+CjxwYXRoIGZpbGw9IiNmMmY2ZjkiIHN0cm9rZT0iIzMzNTY3YSIgc3Ryb2tlLXdpZHRoPSIxLjEiIGQ9Ik0xMTMuOTI5NiwtMjI0LjYwMTVDMTEzLjkyOTYsLTIyNC42MDE1IDMyLjMxMTIsLTIyNC42MDE1IDMyLjMxMTIsLTIyNC42MDE1IDI2LjMxMTIsLTIyNC42MDE1IDIwLjMxMTIsLTIxOC42MDE1IDIwLjMxMTIsLTIxMi42MDE1IDIwLjMxMTIsLTIxMi42MDE1IDIwLjMxMTIsLTE4My4zOTg1IDIwLjMxMTIsLTE4My4zOTg1IDIwLjMxMTIsLTE3Ny4zOTg1IDI2LjMxMTIsLTE3MS4zOTg1IDMyLjMxMTIsLTE3MS4zOTg1IDMyLjMxMTIsLTE3MS4zOTg1IDExMy45Mjk2LC0xNzEuMzk4NSAxMTMuOTI5NiwtMTcxLjM5ODUgMTE5LjkyOTYsLTE3MS4zOTg1IDEyNS45Mjk2LC0xNzcuMzk4NSAxMjUuOTI5NiwtMTgzLjM5ODUgMTI1LjkyOTYsLTE4My4zOTg1IDEyNS45Mjk2LC0yMTIuNjAxNSAxMjUuOTI5NiwtMjEyLjYwMTUgMTI1LjkyOTYsLTIxOC42MDE1IDExOS45Mjk2LC0yMjQuNjAxNSAxMTMuOTI5NiwtMjI0LjYwMTUiIC8+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iNzMuMTIwNCIgeT0iLTIwNy45IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPnRmX2FkZF9jb25zdHJ1Y3Q8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iNzMuMTIwNCIgeT0iLTE5NC43IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPlJlZ2lzdGVyZWQKdGhyZWU8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iNzMuMTIwNCIgeT0iLTE4MS41IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPmNvbnN0cnVjdHMuPC90ZXh0PjwvZz48IS0tIG4yIC0tPjxnIGlkPSJub2RlMiIgY2xhc3M9Im5vZGUiPjx0aXRsZT4KbjIKPC90aXRsZT4KPHBhdGggZmlsbD0iI2YyZjZmOSIgc3Ryb2tlPSIjMzM1NjdhIiBzdHJva2Utd2lkdGg9IjEuMSIgZD0iTTEzMC42NTUzLC0xMzkuMDAxNUMxMzAuNjU1MywtMTM5LjAwMTUgMTUuNTg1NSwtMTM5LjAwMTUgMTUuNTg1NSwtMTM5LjAwMTUgOS41ODU1LC0xMzkuMDAxNSAzLjU4NTUsLTEzMy4wMDE1IDMuNTg1NSwtMTI3LjAwMTUgMy41ODU1LC0xMjcuMDAxNSAzLjU4NTUsLTk3Ljc5ODUgMy41ODU1LC05Ny43OTg1IDMuNTg1NSwtOTEuNzk4NSA5LjU4NTUsLTg1Ljc5ODUgMTUuNTg1NSwtODUuNzk4NSAxNS41ODU1LC04NS43OTg1IDEzMC42NTUzLC04NS43OTg1IDEzMC42NTUzLC04NS43OTg1IDEzNi42NTUzLC04NS43OTg1IDE0Mi42NTUzLC05MS43OTg1IDE0Mi42NTUzLC05Ny43OTg1IDE0Mi42NTUzLC05Ny43OTg1IDE0Mi42NTUzLC0xMjcuMDAxNSAxNDIuNjU1MywtMTI3LjAwMTUgMTQyLjY1NTMsLTEzMy4wMDE1IDEzNi42NTUzLC0xMzkuMDAxNSAxMzAuNjU1MywtMTM5LjAwMTUiIC8+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iNzMuMTIwNCIgeT0iLTEyMi4zIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPnRmX2FkZF9wcm9wb3NpdGlvbjwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI3My4xMjA0IiB5PSItMTA5LjEiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+TGlua2VkCmNvbnN0cnVjdHMgaW50byBhPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjczLjEyMDQiIHk9Ii05NS45IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPmZlZWRiYWNrCm5ldHdvcmsuPC90ZXh0PjwvZz48IS0tIG4xJiM0NTsmZ3Q7bjIgLS0+PGcgaWQ9ImVkZ2UxIiBjbGFzcz0iZWRnZSI+PHRpdGxlPgpuMS0mZ3Q7bjIKPC90aXRsZT4KPHBhdGggZmlsbD0ibm9uZSIgc3Ryb2tlPSIjN2I5MDlmIiBkPSJNNzMuMTIwNCwtMTcxLjM4NDlDNzMuMTIwNCwtMTYzLjQ4OTQgNzMuMTIwNCwtMTU0LjczMjIgNzMuMTIwNCwtMTQ2LjQzNDIiIC8+PHBvbHlnb24gZmlsbD0iIzdiOTA5ZiIgc3Ryb2tlPSIjN2I5MDlmIiBwb2ludHM9Ijc1LjU3MDUsLTE0Ni4yOTM1IDczLjEyMDQsLTEzOS4yOTM1IDcwLjY3MDUsLTE0Ni4yOTM1IDc1LjU3MDUsLTE0Ni4yOTM1Ij48L3BvbHlnb24+PC9nPjwhLS0gbjMgLS0+PGcgaWQ9Im5vZGUzIiBjbGFzcz0ibm9kZSI+PHRpdGxlPgpuMwo8L3RpdGxlPgo8cGF0aCBmaWxsPSIjZjJmNmY5IiBzdHJva2U9IiMzMzU2N2EiIHN0cm9rZS13aWR0aD0iMS4xIiBkPSJNMTM0LjM2MTQsLTUzLjQwMTVDMTM0LjM2MTQsLTUzLjQwMTUgMTEuODc5NCwtNTMuNDAxNSAxMS44Nzk0LC01My40MDE1IDUuODc5NCwtNTMuNDAxNSAtLjEyMDYsLTQ3LjQwMTUgLS4xMjA2LC00MS40MDE1IC0uMTIwNiwtNDEuNDAxNSAtLjEyMDYsLTEyLjE5ODUgLS4xMjA2LC0xMi4xOTg1IC0uMTIwNiwtNi4xOTg1IDUuODc5NCwtLjE5ODUgMTEuODc5NCwtLjE5ODUgMTEuODc5NCwtLjE5ODUgMTM0LjM2MTQsLS4xOTg1IDEzNC4zNjE0LC0uMTk4NSAxNDAuMzYxNCwtLjE5ODUgMTQ2LjM2MTQsLTYuMTk4NSAxNDYuMzYxNCwtMTIuMTk4NSAxNDYuMzYxNCwtMTIuMTk4NSAxNDYuMzYxNCwtNDEuNDAxNSAxNDYuMzYxNCwtNDEuNDAxNSAxNDYuMzYxNCwtNDcuNDAxNSAxNDAuMzYxNCwtNTMuNDAxNSAxMzQuMzYxNCwtNTMuNDAxNSIgLz48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI3My4xMjA0IiB5PSItMzYuNyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj50Zl9hZGRfcHJlZGljdGlvbjwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI3My4xMjA0IiB5PSItMjMuNSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5EZXJpdmVkCnRocmVlIHByZWRpY3Rpb25zPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjczLjEyMDQiIHk9Ii0xMC4zIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPmZyb20KdGhlIHByb3Bvc2l0aW9ucy48L3RleHQ+PC9nPjwhLS0gbjImIzQ1OyZndDtuMyAtLT48ZyBpZD0iZWRnZTIiIGNsYXNzPSJlZGdlIj48dGl0bGU+Cm4yLSZndDtuMwo8L3RpdGxlPgo8cGF0aCBmaWxsPSJub25lIiBzdHJva2U9IiM3YjkwOWYiIGQ9Ik03My4xMjA0LC04NS43ODQ5QzczLjEyMDQsLTc3Ljg4OTQgNzMuMTIwNCwtNjkuMTMyMiA3My4xMjA0LC02MC44MzQyIiAvPjxwb2x5Z29uIGZpbGw9IiM3YjkwOWYiIHN0cm9rZT0iIzdiOTA5ZiIgcG9pbnRzPSI3NS41NzA1LC02MC42OTM1IDczLjEyMDQsLTUzLjY5MzUgNzAuNjcwNSwtNjAuNjkzNSA3NS41NzA1LC02MC42OTM1Ij48L3BvbHlnb24+PC9nPjwvZz48L3N2Zz4=)

The `venn` view takes each construct’s boundary conditions as a set and
returns an SVG showing where those scopes coincide and where they part
company, with each region labelled by the number of conditions in it. It
renders inline because the output is a self-contained image.

``` r

cat('<div class="tf-figure">', tf_diagram(theory, "venn"), '</div>', sep = "")
```

![](data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIzODAiIGhlaWdodD0iMzAwIiB2aWV3Ym94PSIwIDAgMzgwIDMwMCIgZm9udC1mYW1pbHk9InNhbnMtc2VyaWYiIGZvbnQtc2l6ZT0iMTMiPjx0ZXh0IHg9IjE5MCIgeT0iMjQiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtc2l6ZT0iMTUiPkNvbnN0cnVjdCBzY29wZQpvdmVybGFwPC90ZXh0PjxjaXJjbGUgY3g9IjE1MCIgY3k9IjEzNSIgcj0iNzgiIGZpbGw9IiM0ZTc5YTciIGZpbGwtb3BhY2l0eT0iMC4zNSIgc3Ryb2tlPSIjMWU3YjdiIj48L2NpcmNsZT48Y2lyY2xlIGN4PSIyMzAiIGN5PSIxMzUiIHI9Ijc4IiBmaWxsPSIjNGU3OWE3IiBmaWxsLW9wYWNpdHk9IjAuMzUiIHN0cm9rZT0iIzFlN2I3YiI+PC9jaXJjbGU+PGNpcmNsZSBjeD0iMTkwIiBjeT0iMTk1IiByPSI3OCIgZmlsbD0iIzRlNzlhNyIgZmlsbC1vcGFjaXR5PSIwLjM1IiBzdHJva2U9IiMxZTdiN2IiPjwvY2lyY2xlPjx0ZXh0IHg9IjExMCIgeT0iNDUiIHRleHQtYW5jaG9yPSJtaWRkbGUiPlBoeXNpb2xvZ2ljYWwgYXJvdXNhbDwvdGV4dD48dGV4dCB4PSIyNzAiIHk9IjQ1IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIj5QZXJjZWl2ZWQgdGhyZWF0PC90ZXh0Pjx0ZXh0IHg9IjE5MCIgeT0iMjkwIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIj5Bdm9pZGFuY2UgYmVoYXZpb3VyPC90ZXh0Pjx0ZXh0IHg9IjEyMCIgeT0iMTE1IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXdlaWdodD0iYm9sZCI+MTwvdGV4dD48dGV4dCB4PSIyNjAiIHk9IjExNSIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC13ZWlnaHQ9ImJvbGQiPjA8L3RleHQ+PHRleHQgeD0iMTkwIiB5PSIyMzAiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtd2VpZ2h0PSJib2xkIj4xPC90ZXh0Pjx0ZXh0IHg9IjE5MCIgeT0iMTA1IiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXdlaWdodD0iYm9sZCI+MTwvdGV4dD48dGV4dCB4PSIxNDUiIHk9IjE4MCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC13ZWlnaHQ9ImJvbGQiPjA8L3RleHQ+PHRleHQgeD0iMjM1IiB5PSIxODAiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtd2VpZ2h0PSJib2xkIj4xPC90ZXh0Pjx0ZXh0IHg9IjE5MCIgeT0iMTYwIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXdlaWdodD0iYm9sZCI+MTwvdGV4dD48L3N2Zz4=)

Two further views summarise the scoring. The `rigour` view draws the
checklist as a status grid, colouring each item by its result and
reporting the aggregate score and the gate.

``` r

cat('<div class="tf-figure">', tf_diagram(theory, "rigour"), '</div>', sep = "")
```

![](data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSI0NjAiIGhlaWdodD0iMzYwIiB2aWV3Ym94PSIwIDAgNDYwIDM2MCIgZm9udC1mYW1pbHk9InNhbnMtc2VyaWYiIGZvbnQtc2l6ZT0iMTMiPjx0ZXh0IHg9IjIwIiB5PSIyOCIgZm9udC1zaXplPSIxNSI+Umlnb3VyIGNoZWNrbGlzdDwvdGV4dD48dGV4dCB4PSIyMCIgeT0iNDYiPmFnZ3JlZ2F0ZSBzY29yZSA4Ny4zLCBnYXRlIHBhc3M8L3RleHQ+PHJlY3QgeD0iMjAiIHk9IjYwIiB3aWR0aD0iMTYiIGhlaWdodD0iMTYiIHJ4PSIzIiBmaWxsPSIjNGNhZjUwIiAvPjx0ZXh0IHg9IjQ0IiB5PSI3MiI+ZmFsc2lmaWFiaWxpdHk8L3RleHQ+PHRleHQgeD0iMzIwIiB5PSI3MiI+cGFzczwvdGV4dD48cmVjdCB4PSIyMCIgeT0iODQiIHdpZHRoPSIxNiIgaGVpZ2h0PSIxNiIgcng9IjMiIGZpbGw9IiM0Y2FmNTAiIC8+PHRleHQgeD0iNDQiIHk9Ijk2Ij5wcmVjaXNpb248L3RleHQ+PHRleHQgeD0iMzIwIiB5PSI5NiI+cGFzczwvdGV4dD48cmVjdCB4PSIyMCIgeT0iMTA4IiB3aWR0aD0iMTYiIGhlaWdodD0iMTYiIHJ4PSIzIiBmaWxsPSIjNGNhZjUwIiAvPjx0ZXh0IHg9IjQ0IiB5PSIxMjAiPnJpc2tfc2V2ZXJpdHk8L3RleHQ+PHRleHQgeD0iMzIwIiB5PSIxMjAiPnBhc3M8L3RleHQ+PHJlY3QgeD0iMjAiIHk9IjEzMiIgd2lkdGg9IjE2IiBoZWlnaHQ9IjE2IiByeD0iMyIgZmlsbD0iIzllOWU5ZSIgLz48dGV4dCB4PSI0NCIgeT0iMTQ0Ij5wYXJzaW1vbnk8L3RleHQ+PHRleHQgeD0iMzIwIiB5PSIxNDQiPm4vYTwvdGV4dD48cmVjdCB4PSIyMCIgeT0iMTU2IiB3aWR0aD0iMTYiIGhlaWdodD0iMTYiIHJ4PSIzIiBmaWxsPSIjNGNhZjUwIiAvPjx0ZXh0IHg9IjQ0IiB5PSIxNjgiPm5vbl9yZWR1bmRhbmN5PC90ZXh0Pjx0ZXh0IHg9IjMyMCIgeT0iMTY4Ij5wYXNzPC90ZXh0PjxyZWN0IHg9IjIwIiB5PSIxODAiIHdpZHRoPSIxNiIgaGVpZ2h0PSIxNiIgcng9IjMiIGZpbGw9IiM0Y2FmNTAiIC8+PHRleHQgeD0iNDQiIHk9IjE5MiI+Y29uc3RydWN0X2NsYXJpdHk8L3RleHQ+PHRleHQgeD0iMzIwIiB5PSIxOTIiPnBhc3M8L3RleHQ+PHJlY3QgeD0iMjAiIHk9IjIwNCIgd2lkdGg9IjE2IiBoZWlnaHQ9IjE2IiByeD0iMyIgZmlsbD0iIzRjYWY1MCIgLz48dGV4dCB4PSI0NCIgeT0iMjE2Ij5zY29wZTwvdGV4dD48dGV4dCB4PSIzMjAiIHk9IjIxNiI+cGFzczwvdGV4dD48cmVjdCB4PSIyMCIgeT0iMjI4IiB3aWR0aD0iMTYiIGhlaWdodD0iMTYiIHJ4PSIzIiBmaWxsPSIjNGNhZjUwIiAvPjx0ZXh0IHg9IjQ0IiB5PSIyNDAiPmxvZ2ljYWxfd2h5PC90ZXh0Pjx0ZXh0IHg9IjMyMCIgeT0iMjQwIj5wYXNzPC90ZXh0PjxyZWN0IHg9IjIwIiB5PSIyNTIiIHdpZHRoPSIxNiIgaGVpZ2h0PSIxNiIgcng9IjMiIGZpbGw9IiM0Y2FmNTAiIC8+PHRleHQgeD0iNDQiIHk9IjI2NCI+Y2F1c2FsX3Rlc3RhYmlsaXR5PC90ZXh0Pjx0ZXh0IHg9IjMyMCIgeT0iMjY0Ij5wYXNzPC90ZXh0PjxyZWN0IHg9IjIwIiB5PSIyNzYiIHdpZHRoPSIxNiIgaGVpZ2h0PSIxNiIgcng9IjMiIGZpbGw9IiM0Y2FmNTAiIC8+PHRleHQgeD0iNDQiIHk9IjI4OCI+ZGlhZ25vc3RpY2l0eTwvdGV4dD48dGV4dCB4PSIzMjAiIHk9IjI4OCI+cGFzczwvdGV4dD48cmVjdCB4PSIyMCIgeT0iMzAwIiB3aWR0aD0iMTYiIGhlaWdodD0iMTYiIHJ4PSIzIiBmaWxsPSIjNGNhZjUwIiAvPjx0ZXh0IHg9IjQ0IiB5PSIzMTIiPmZvcm1hbGlzYXRpb248L3RleHQ+PHRleHQgeD0iMzIwIiB5PSIzMTIiPnBhc3M8L3RleHQ+PHJlY3QgeD0iMjAiIHk9IjMyNCIgd2lkdGg9IjE2IiBoZWlnaHQ9IjE2IiByeD0iMyIgZmlsbD0iIzRjYWY1MCIgLz48dGV4dCB4PSI0NCIgeT0iMzM2Ij5kZXJpdmF0aW9uX2NoYWluPC90ZXh0Pjx0ZXh0IHg9IjMyMCIgeT0iMzM2Ij5wYXNzPC90ZXh0Pjwvc3ZnPg==)

The `severity` view draws one bar per prediction, scaled by its computed
severity, so the riskier claims stand out.

``` r

cat(
  '<div class="tf-figure">',
  tf_diagram(theory, "severity"),
  '</div>',
  sep = ""
)
```

![](data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIzMjAiIGhlaWdodD0iMTMyIiB2aWV3Ym94PSIwIDAgMzIwIDEzMiIgZm9udC1mYW1pbHk9InNhbnMtc2VyaWYiIGZvbnQtc2l6ZT0iMTMiPjx0ZXh0IHg9IjIwIiB5PSIyNiIgZm9udC1zaXplPSIxNSI+UHJlLWRhdGEgcmlza2luZXNzPC90ZXh0Pjx0ZXh0IHg9IjIwIiB5PSI1MiI+cHJlZDE8L3RleHQ+PHJlY3QgeD0iNzAiIHk9IjQwIiB3aWR0aD0iMjAwIiBoZWlnaHQ9IjE2IiByeD0iMiIgZmlsbD0iIzRlNzlhNyIgLz48dGV4dCB4PSIyNzUiIHk9IjUyIj4xLjAwMDwvdGV4dD48dGV4dCB4PSIyMCIgeT0iODAiPnByZWQyPC90ZXh0PjxyZWN0IHg9IjcwIiB5PSI2OCIgd2lkdGg9IjE0MCIgaGVpZ2h0PSIxNiIgcng9IjIiIGZpbGw9IiM0ZTc5YTciIC8+PHRleHQgeD0iMjE1IiB5PSI4MCI+MC43MDA8L3RleHQ+PHRleHQgeD0iMjAiIHk9IjEwOCI+cHJlZDM8L3RleHQ+PHJlY3QgeD0iNzAiIHk9Ijk2IiB3aWR0aD0iNjAiIGhlaWdodD0iMTYiIHJ4PSIyIiBmaWxsPSIjNGU3OWE3IiAvPjx0ZXh0IHg9IjEzNSIgeT0iMTA4Ij4wLjMwMDwvdGV4dD48L3N2Zz4=)

The `development_roadmap` view turns the same checklist into a worklist
by keeping only the items that still fail or warn, and it orders that
worklist the way the work should be done. Whatever gates the theory
comes first, heaviest check first, and the advisory items follow. Each
step carries its number, the criterion it is measured against and
whether missing it blocks the gate or is merely advisory, so the figure
amounts to a plan of work. The hub names the theory and its current
standing. The panic network passes every check, so its roadmap reduces
to that hub and an `all checks pass` node, and the deliberately weak
theory shipped alongside it shows the worklist in full.

``` r

weak <- tf_read(
  system.file("fixtures/weak-theory.theory.yaml", package = "theoryforge")
)
cat(tf_diagram(theory, "development_roadmap"))
```

    digraph development_roadmap {
      graph [rankdir=TB, bgcolor="transparent", fontname="Helvetica", fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];
      node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", color="#33567A", fillcolor="#F2F6F9", fontcolor="#12283A", penwidth=1.1, margin="0.16,0.1"];
      edge [fontname="Helvetica", fontsize=10, color="#7B909F", fontcolor="#0F6E6E", arrowsize=0.7];
      "roadmap" [shape=ellipse, label="Network theory of\npanic disorder\nscore 87.3, gate pass", fillcolor="#12283A", color="#12283A", fontcolor="#FFFFFF"];
      "all_checks_pass" [label="all checks pass", fillcolor="#E5F2E7", color="#3E7A46"];
      "roadmap" -> "all_checks_pass";
    }

``` r

cat(tf_diagram(weak, "development_roadmap"))
```

    digraph development_roadmap {
      graph [rankdir=TB, bgcolor="transparent", fontname="Helvetica", fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];
      node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", color="#33567A", fillcolor="#F2F6F9", fontcolor="#12283A", penwidth=1.1, margin="0.16,0.1"];
      edge [fontname="Helvetica", fontsize=10, color="#7B909F", fontcolor="#0F6E6E", arrowsize=0.7];
      "roadmap" [shape=ellipse, label="An underspecified\nmotivation theory\nscore 2.2, gate blocked", fillcolor="#12283A", color="#12283A", fontcolor="#FFFFFF"];
      "falsifiability" [label="1. falsifiability\nAt least one\nprediction forbids an\nobservation\nblocks the gate", fillcolor="#F9E5E4", color="#B2453C"];
      "derivation_chain" [label="2. derivation_chain\nEvery prediction cites\nat least one\nproposition, and every\ncited id is a declared\nproposition (reference\ncheck only)\nblocks the gate", fillcolor="#F9E5E4", color="#B2453C"];
      "precision" [label="3. precision\nPredictions are\npoint/interval, not\nmerely directional\nadvisory", fillcolor="#FBF1DC", color="#9C6B14"];
      "risk_severity" [label="4. risk_severity\nMean prediction\nseverity (declared,\nelse the claim-form\nrubric) at or above\nthreshold\nadvisory", fillcolor="#FBF1DC", color="#9C6B14"];
      "non_redundancy" [label="5. non_redundancy\nNo pair of construct\ndefinitions is a\nnear-duplicate or\ncontained in the other\n(lexical screen)\nadvisory", fillcolor="#FBF1DC", color="#9C6B14"];
      "construct_clarity" [label="6. construct_clarity\nEvery construct has\ndefinition +\nmeasurement + boundary\nconditions\nadvisory", fillcolor="#FBF1DC", color="#9C6B14"];
      "logical_why" [label="7. logical_why\nEach proposition\nstates a mechanism,\nnot just a correlation\nadvisory", fillcolor="#FBF1DC", color="#9C6B14"];
      "scope" [label="8. scope\nBoundary conditions\nexplicitly stated\nadvisory", fillcolor="#FBF1DC", color="#9C6B14"];
      "causal_testability" [label="9. causal_testability\nAt least one\nproposition states a\ncausal relation\nadvisory", fillcolor="#FBF1DC", color="#9C6B14"];
      "diagnosticity" [label="10. diagnosticity\nAt least one\nprediction names a\nregistered alternative\nit is declared to\ndiscriminate from\n(declared, not\nverified)\nadvisory", fillcolor="#FBF1DC", color="#9C6B14"];
      "formalisation" [label="11. formalisation\nA formal model of a\nrecognised type (ode,\nabm, network, sem) is\ndeclared\nadvisory", fillcolor="#FBF1DC", color="#9C6B14"];
      "roadmap" -> "falsifiability";
      "falsifiability" -> "derivation_chain";
      "derivation_chain" -> "precision";
      { rank=same; "precision" -> "risk_severity" -> "non_redundancy" [style=invis]; }
      "precision" -> "construct_clarity" [style=invis];
      { rank=same; "construct_clarity" -> "logical_why" -> "scope" [style=invis]; }
      "construct_clarity" -> "causal_testability" [style=invis];
      { rank=same; "causal_testability" -> "diagnosticity" -> "formalisation" [style=invis]; }
    }

``` r

cat(
  '<div class="tf-figure tf-diagram">',
  tf_render_diagram(weak, "development_roadmap", as = "svg"),
  '</div>',
  sep = ""
)
```

![](data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iNDkzcHQiIGhlaWdodD0iNzk3cHQiIHZpZXdib3g9IjAuMDAgMC4wMCA0OTMuMDAgNzk2LjYwIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHhtbG5zOnhsaW5rPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5L3hsaW5rIj48ZyBpZD0iZ3JhcGgwIiBjbGFzcz0iZ3JhcGgiIHRyYW5zZm9ybT0ic2NhbGUoMSAxKSByb3RhdGUoMCkgdHJhbnNsYXRlKDE0LjQgNzgyLjIwMTgpIj48dGl0bGU+CmRldmVsb3BtZW50X3JvYWRtYXAKPC90aXRsZT4KPCEtLSByb2FkbWFwIC0tPjxnIGlkPSJub2RlMSIgY2xhc3M9Im5vZGUiPjx0aXRsZT4Kcm9hZG1hcAo8L3RpdGxlPgo8ZWxsaXBzZSBmaWxsPSIjMTIyODNhIiBzdHJva2U9IiMxMjI4M2EiIHN0cm9rZS13aWR0aD0iMS4xIiBjeD0iOTcuMzc0MyIgY3k9Ii03MjkuOTAwOSIgcng9Ijk3LjI0ODgiIHJ5PSIzNy44MDIxIj48L2VsbGlwc2U+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iOTcuMzc0MyIgeT0iLTczOS44MDA5IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiNmZmZmZmYiPkFuCnVuZGVyc3BlY2lmaWVkPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9Ijk3LjM3NDMiIHk9Ii03MjYuNjAwOSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjZmZmZmZmIj5tb3RpdmF0aW9uCnRoZW9yeTwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI5Ny4zNzQzIiB5PSItNzEzLjQwMDkiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iI2ZmZmZmZiI+c2NvcmUKMi4yLCBnYXRlIGJsb2NrZWQ8L3RleHQ+PC9nPjwhLS0gZmFsc2lmaWFiaWxpdHkgLS0+PGcgaWQ9Im5vZGUyIiBjbGFzcz0ibm9kZSI+PHRpdGxlPgpmYWxzaWZpYWJpbGl0eQo8L3RpdGxlPgo8cGF0aCBmaWxsPSIjZjllNWU0IiBzdHJva2U9IiNiMjQ1M2MiIHN0cm9rZS13aWR0aD0iMS4xIiBkPSJNMTQ2Ljg5NzQsLTY2MEMxNDYuODk3NCwtNjYwIDQ3Ljg1MTIsLTY2MCA0Ny44NTEyLC02NjAgNDEuODUxMiwtNjYwIDM1Ljg1MTIsLTY1NCAzNS44NTEyLC02NDggMzUuODUxMiwtNjQ4IDM1Ljg1MTIsLTU5MiAzNS44NTEyLC01OTIgMzUuODUxMiwtNTg2IDQxLjg1MTIsLTU4MCA0Ny44NTEyLC01ODAgNDcuODUxMiwtNTgwIDE0Ni44OTc0LC01ODAgMTQ2Ljg5NzQsLTU4MCAxNTIuODk3NCwtNTgwIDE1OC44OTc0LC01ODYgMTU4Ljg5NzQsLTU5MiAxNTguODk3NCwtNTkyIDE1OC44OTc0LC02NDggMTU4Ljg5NzQsLTY0OCAxNTguODk3NCwtNjU0IDE1Mi44OTc0LC02NjAgMTQ2Ljg5NzQsLTY2MCIgLz48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI5Ny4zNzQzIiB5PSItNjQzLjEiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+MS4KZmFsc2lmaWFiaWxpdHk8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iOTcuMzc0MyIgeT0iLTYyOS45IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPkF0CmxlYXN0IG9uZTwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI5Ny4zNzQzIiB5PSItNjE2LjciIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+cHJlZGljdGlvbgpmb3JiaWRzIGFuPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9Ijk3LjM3NDMiIHk9Ii02MDMuNSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5vYnNlcnZhdGlvbjwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI5Ny4zNzQzIiB5PSItNTkwLjMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+YmxvY2tzCnRoZSBnYXRlPC90ZXh0PjwvZz48IS0tIHJvYWRtYXAmIzQ1OyZndDtmYWxzaWZpYWJpbGl0eSAtLT48ZyBpZD0iZWRnZTEiIGNsYXNzPSJlZGdlIj48dGl0bGU+CnJvYWRtYXAtJmd0O2ZhbHNpZmlhYmlsaXR5CjwvdGl0bGU+CjxwYXRoIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzdiOTA5ZiIgZD0iTTk3LjM3NDMsLTY5MS43NzEzQzk3LjM3NDMsLTY4My45ODcgOTcuMzc0MywtNjc1LjcwNDIgOTcuMzc0MywtNjY3LjYzNTYiIC8+PHBvbHlnb24gZmlsbD0iIzdiOTA5ZiIgc3Ryb2tlPSIjN2I5MDlmIiBwb2ludHM9Ijk5LjgyNDQsLTY2Ny4zMDYzIDk3LjM3NDMsLTY2MC4zMDYzIDk0LjkyNDQsLTY2Ny4zMDYzIDk5LjgyNDQsLTY2Ny4zMDYzIj48L3BvbHlnb24+PC9nPjwhLS0gZGVyaXZhdGlvbl9jaGFpbiAtLT48ZyBpZD0ibm9kZTMiIGNsYXNzPSJub2RlIj48dGl0bGU+CmRlcml2YXRpb25fY2hhaW4KPC90aXRsZT4KPHBhdGggZmlsbD0iI2Y5ZTVlNCIgc3Ryb2tlPSIjYjI0NTNjIiBzdHJva2Utd2lkdGg9IjEuMSIgZD0iTTE1MS41NzE2LC01NDcuODAwN0MxNTEuNTcxNiwtNTQ3LjgwMDcgNDMuMTc3MSwtNTQ3LjgwMDcgNDMuMTc3MSwtNTQ3LjgwMDcgMzcuMTc3MSwtNTQ3LjgwMDcgMzEuMTc3MSwtNTQxLjgwMDcgMzEuMTc3MSwtNTM1LjgwMDcgMzEuMTc3MSwtNTM1LjgwMDcgMzEuMTc3MSwtNDQwLjU5OTMgMzEuMTc3MSwtNDQwLjU5OTMgMzEuMTc3MSwtNDM0LjU5OTMgMzcuMTc3MSwtNDI4LjU5OTMgNDMuMTc3MSwtNDI4LjU5OTMgNDMuMTc3MSwtNDI4LjU5OTMgMTUxLjU3MTYsLTQyOC41OTkzIDE1MS41NzE2LC00MjguNTk5MyAxNTcuNTcxNiwtNDI4LjU5OTMgMTYzLjU3MTYsLTQzNC41OTkzIDE2My41NzE2LC00NDAuNTk5MyAxNjMuNTcxNiwtNDQwLjU5OTMgMTYzLjU3MTYsLTUzNS44MDA3IDE2My41NzE2LC01MzUuODAwNyAxNjMuNTcxNiwtNTQxLjgwMDcgMTU3LjU3MTYsLTU0Ny44MDA3IDE1MS41NzE2LC01NDcuODAwNyIgLz48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI5Ny4zNzQzIiB5PSItNTMxLjEiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+Mi4KZGVyaXZhdGlvbl9jaGFpbjwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI5Ny4zNzQzIiB5PSItNTE3LjkiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+RXZlcnkKcHJlZGljdGlvbiBjaXRlczwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI5Ny4zNzQzIiB5PSItNTA0LjciIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+YXQKbGVhc3Qgb25lPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9Ijk3LjM3NDMiIHk9Ii00OTEuNSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5wcm9wb3NpdGlvbiwKYW5kIGV2ZXJ5PC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9Ijk3LjM3NDMiIHk9Ii00NzguMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5jaXRlZAppZCBpcyBhIGRlY2xhcmVkPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9Ijk3LjM3NDMiIHk9Ii00NjUuMSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5wcm9wb3NpdGlvbgoocmVmZXJlbmNlPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9Ijk3LjM3NDMiIHk9Ii00NTEuOSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5jaGVjawpvbmx5KTwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI5Ny4zNzQzIiB5PSItNDM4LjciIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+YmxvY2tzCnRoZSBnYXRlPC90ZXh0PjwvZz48IS0tIGZhbHNpZmlhYmlsaXR5JiM0NTsmZ3Q7ZGVyaXZhdGlvbl9jaGFpbiAtLT48ZyBpZD0iZWRnZTIiIGNsYXNzPSJlZGdlIj48dGl0bGU+CmZhbHNpZmlhYmlsaXR5LSZndDtkZXJpdmF0aW9uX2NoYWluCjwvdGl0bGU+CjxwYXRoIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzdiOTA5ZiIgZD0iTTk3LjM3NDMsLTU3OS43Mzk1Qzk3LjM3NDMsLTU3MS45MzI2IDk3LjM3NDMsLTU2My41NTcgOTcuMzc0MywtNTU1LjE1ODQiIC8+PHBvbHlnb24gZmlsbD0iIzdiOTA5ZiIgc3Ryb2tlPSIjN2I5MDlmIiBwb2ludHM9Ijk5LjgyNDQsLTU1NS4xMTAyIDk3LjM3NDMsLTU0OC4xMTAyIDk0LjkyNDQsLTU1NS4xMTAzIDk5LjgyNDQsLTU1NS4xMTAyIj48L3BvbHlnb24+PC9nPjwhLS0gcHJlY2lzaW9uIC0tPjxnIGlkPSJub2RlNCIgY2xhc3M9Im5vZGUiPjx0aXRsZT4KcHJlY2lzaW9uCjwvdGl0bGU+CjxwYXRoIGZpbGw9IiNmYmYxZGMiIHN0cm9rZT0iIzljNmIxNCIgc3Ryb2tlLXdpZHRoPSIxLjEiIGQ9Ik0xNDAuNTQxOSwtMzgzLjJDMTQwLjU0MTksLTM4My4yIDU0LjIwNjgsLTM4My4yIDU0LjIwNjgsLTM4My4yIDQ4LjIwNjgsLTM4My4yIDQyLjIwNjgsLTM3Ny4yIDQyLjIwNjgsLTM3MS4yIDQyLjIwNjgsLTM3MS4yIDQyLjIwNjgsLTMxNS4yIDQyLjIwNjgsLTMxNS4yIDQyLjIwNjgsLTMwOS4yIDQ4LjIwNjgsLTMwMy4yIDU0LjIwNjgsLTMwMy4yIDU0LjIwNjgsLTMwMy4yIDE0MC41NDE5LC0zMDMuMiAxNDAuNTQxOSwtMzAzLjIgMTQ2LjU0MTksLTMwMy4yIDE1Mi41NDE5LC0zMDkuMiAxNTIuNTQxOSwtMzE1LjIgMTUyLjU0MTksLTMxNS4yIDE1Mi41NDE5LC0zNzEuMiAxNTIuNTQxOSwtMzcxLjIgMTUyLjU0MTksLTM3Ny4yIDE0Ni41NDE5LC0zODMuMiAxNDAuNTQxOSwtMzgzLjIiIC8+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iOTcuMzc0MyIgeT0iLTM2Ni4zIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPjMuCnByZWNpc2lvbjwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI5Ny4zNzQzIiB5PSItMzUzLjEiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+UHJlZGljdGlvbnMKYXJlPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9Ijk3LjM3NDMiIHk9Ii0zMzkuOSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5wb2ludC9pbnRlcnZhbCwKbm90PC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9Ijk3LjM3NDMiIHk9Ii0zMjYuNyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5tZXJlbHkKZGlyZWN0aW9uYWw8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iOTcuMzc0MyIgeT0iLTMxMy41IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPmFkdmlzb3J5PC90ZXh0PjwvZz48IS0tIGRlcml2YXRpb25fY2hhaW4mIzQ1OyZndDtwcmVjaXNpb24gLS0+PGcgaWQ9ImVkZ2UzIiBjbGFzcz0iZWRnZSI+PHRpdGxlPgpkZXJpdmF0aW9uX2NoYWluLSZndDtwcmVjaXNpb24KPC90aXRsZT4KPHBhdGggZmlsbD0ibm9uZSIgc3Ryb2tlPSIjN2I5MDlmIiBkPSJNOTcuMzc0MywtNDI4LjM4NThDOTcuMzc0MywtNDE1Ljg1MjggOTcuMzc0MywtNDAyLjc5NzcgOTcuMzc0MywtMzkwLjc4MjIiIC8+PHBvbHlnb24gZmlsbD0iIzdiOTA5ZiIgc3Ryb2tlPSIjN2I5MDlmIiBwb2ludHM9Ijk5LjgyNDQsLTM5MC40NDkxIDk3LjM3NDMsLTM4My40NDkxIDk0LjkyNDQsLTM5MC40NDkyIDk5LjgyNDQsLTM5MC40NDkxIj48L3BvbHlnb24+PC9nPjwhLS0gcmlza19zZXZlcml0eSAtLT48ZyBpZD0ibm9kZTUiIGNsYXNzPSJub2RlIj48dGl0bGU+CnJpc2tfc2V2ZXJpdHkKPC90aXRsZT4KPHBhdGggZmlsbD0iI2ZiZjFkYyIgc3Ryb2tlPSIjOWM2YjE0IiBzdHJva2Utd2lkdGg9IjEuMSIgZD0iTTI3OS43NjE3LC0zOTYuNjAwOEMyNzkuNzYxNywtMzk2LjYwMDggMTg2Ljk4NywtMzk2LjYwMDggMTg2Ljk4NywtMzk2LjYwMDggMTgwLjk4NywtMzk2LjYwMDggMTc0Ljk4NywtMzkwLjYwMDggMTc0Ljk4NywtMzg0LjYwMDggMTc0Ljk4NywtMzg0LjYwMDggMTc0Ljk4NywtMzAxLjc5OTIgMTc0Ljk4NywtMzAxLjc5OTIgMTc0Ljk4NywtMjk1Ljc5OTIgMTgwLjk4NywtMjg5Ljc5OTIgMTg2Ljk4NywtMjg5Ljc5OTIgMTg2Ljk4NywtMjg5Ljc5OTIgMjc5Ljc2MTcsLTI4OS43OTkyIDI3OS43NjE3LC0yODkuNzk5MiAyODUuNzYxNywtMjg5Ljc5OTIgMjkxLjc2MTcsLTI5NS43OTkyIDI5MS43NjE3LC0zMDEuNzk5MiAyOTEuNzYxNywtMzAxLjc5OTIgMjkxLjc2MTcsLTM4NC42MDA4IDI5MS43NjE3LC0zODQuNjAwOCAyOTEuNzYxNywtMzkwLjYwMDggMjg1Ljc2MTcsLTM5Ni42MDA4IDI3OS43NjE3LC0zOTYuNjAwOCIgLz48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIyMzMuMzc0MyIgeT0iLTM3OS41IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPjQuCnJpc2tfc2V2ZXJpdHk8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMjMzLjM3NDMiIHk9Ii0zNjYuMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5NZWFuCnByZWRpY3Rpb248L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMjMzLjM3NDMiIHk9Ii0zNTMuMSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5zZXZlcml0eQooZGVjbGFyZWQsPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjIzMy4zNzQzIiB5PSItMzM5LjkiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+ZWxzZQp0aGUgY2xhaW0tZm9ybTwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIyMzMuMzc0MyIgeT0iLTMyNi43IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPnJ1YnJpYykKYXQgb3IgYWJvdmU8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMjMzLjM3NDMiIHk9Ii0zMTMuNSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj50aHJlc2hvbGQ8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMjMzLjM3NDMiIHk9Ii0zMDAuMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5hZHZpc29yeTwvdGV4dD48L2c+PCEtLSBwcmVjaXNpb24mIzQ1OyZndDtyaXNrX3NldmVyaXR5IC0tPjwhLS0gY29uc3RydWN0X2NsYXJpdHkgLS0+PGcgaWQ9Im5vZGU3IiBjbGFzcz0ibm9kZSI+PHRpdGxlPgpjb25zdHJ1Y3RfY2xhcml0eQo8L3RpdGxlPgo8cGF0aCBmaWxsPSIjZmJmMWRjIiBzdHJva2U9IiM5YzZiMTQiIHN0cm9rZS13aWR0aD0iMS4xIiBkPSJNMTU5Ljk5NDgsLTI1OC4xMDAyQzE1OS45OTQ4LC0yNTguMTAwMiAzNC43NTM5LC0yNTguMTAwMiAzNC43NTM5LC0yNTguMTAwMiAyOC43NTM5LC0yNTguMTAwMiAyMi43NTM5LC0yNTIuMTAwMiAyMi43NTM5LC0yNDYuMTAwMiAyMi43NTM5LC0yNDYuMTAwMiAyMi43NTM5LC0xNzYuNjk5OCAyMi43NTM5LC0xNzYuNjk5OCAyMi43NTM5LC0xNzAuNjk5OCAyOC43NTM5LC0xNjQuNjk5OCAzNC43NTM5LC0xNjQuNjk5OCAzNC43NTM5LC0xNjQuNjk5OCAxNTkuOTk0OCwtMTY0LjY5OTggMTU5Ljk5NDgsLTE2NC42OTk4IDE2NS45OTQ4LC0xNjQuNjk5OCAxNzEuOTk0OCwtMTcwLjY5OTggMTcxLjk5NDgsLTE3Ni42OTk4IDE3MS45OTQ4LC0xNzYuNjk5OCAxNzEuOTk0OCwtMjQ2LjEwMDIgMTcxLjk5NDgsLTI0Ni4xMDAyIDE3MS45OTQ4LC0yNTIuMTAwMiAxNjUuOTk0OCwtMjU4LjEwMDIgMTU5Ljk5NDgsLTI1OC4xMDAyIiAvPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9Ijk3LjM3NDMiIHk9Ii0yNDEuMSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj42Lgpjb25zdHJ1Y3RfY2xhcml0eTwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI5Ny4zNzQzIiB5PSItMjI3LjkiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+RXZlcnkKY29uc3RydWN0IGhhczwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI5Ny4zNzQzIiB5PSItMjE0LjciIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+ZGVmaW5pdGlvbgorPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9Ijk3LjM3NDMiIHk9Ii0yMDEuNSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5tZWFzdXJlbWVudAorIGJvdW5kYXJ5PC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9Ijk3LjM3NDMiIHk9Ii0xODguMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5jb25kaXRpb25zPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9Ijk3LjM3NDMiIHk9Ii0xNzUuMSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5hZHZpc29yeTwvdGV4dD48L2c+PCEtLSBwcmVjaXNpb24mIzQ1OyZndDtjb25zdHJ1Y3RfY2xhcml0eSAtLT48IS0tIG5vbl9yZWR1bmRhbmN5IC0tPjxnIGlkPSJub2RlNiIgY2xhc3M9Im5vZGUiPjx0aXRsZT4Kbm9uX3JlZHVuZGFuY3kKPC90aXRsZT4KPHBhdGggZmlsbD0iI2ZiZjFkYyIgc3Ryb2tlPSIjOWM2YjE0IiBzdHJva2Utd2lkdGg9IjEuMSIgZD0iTTQzMS4xMzg0LC0zOTYuNjAwOEM0MzEuMTM4NCwtMzk2LjYwMDggMzI1LjYxMDIsLTM5Ni42MDA4IDMyNS42MTAyLC0zOTYuNjAwOCAzMTkuNjEwMiwtMzk2LjYwMDggMzEzLjYxMDIsLTM5MC42MDA4IDMxMy42MTAyLC0zODQuNjAwOCAzMTMuNjEwMiwtMzg0LjYwMDggMzEzLjYxMDIsLTMwMS43OTkyIDMxMy42MTAyLC0zMDEuNzk5MiAzMTMuNjEwMiwtMjk1Ljc5OTIgMzE5LjYxMDIsLTI4OS43OTkyIDMyNS42MTAyLC0yODkuNzk5MiAzMjUuNjEwMiwtMjg5Ljc5OTIgNDMxLjEzODQsLTI4OS43OTkyIDQzMS4xMzg0LC0yODkuNzk5MiA0MzcuMTM4NCwtMjg5Ljc5OTIgNDQzLjEzODQsLTI5NS43OTkyIDQ0My4xMzg0LC0zMDEuNzk5MiA0NDMuMTM4NCwtMzAxLjc5OTIgNDQzLjEzODQsLTM4NC42MDA4IDQ0My4xMzg0LC0zODQuNjAwOCA0NDMuMTM4NCwtMzkwLjYwMDggNDM3LjEzODQsLTM5Ni42MDA4IDQzMS4xMzg0LC0zOTYuNjAwOCIgLz48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIzNzguMzc0MyIgeT0iLTM3OS41IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPjUuCm5vbl9yZWR1bmRhbmN5PC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjM3OC4zNzQzIiB5PSItMzY2LjMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+Tm8KcGFpciBvZiBjb25zdHJ1Y3Q8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMzc4LjM3NDMiIHk9Ii0zNTMuMSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5kZWZpbml0aW9ucwppcyBhPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjM3OC4zNzQzIiB5PSItMzM5LjkiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+bmVhci1kdXBsaWNhdGUKb3I8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMzc4LjM3NDMiIHk9Ii0zMjYuNyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5jb250YWluZWQKaW4gdGhlIG90aGVyPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjM3OC4zNzQzIiB5PSItMzEzLjUiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+KGxleGljYWwKc2NyZWVuKTwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIzNzguMzc0MyIgeT0iLTMwMC4zIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPmFkdmlzb3J5PC90ZXh0PjwvZz48IS0tIHJpc2tfc2V2ZXJpdHkmIzQ1OyZndDtub25fcmVkdW5kYW5jeSAtLT48IS0tIGxvZ2ljYWxfd2h5IC0tPjxnIGlkPSJub2RlOCIgY2xhc3M9Im5vZGUiPjx0aXRsZT4KbG9naWNhbF93aHkKPC90aXRsZT4KPHBhdGggZmlsbD0iI2ZiZjFkYyIgc3Ryb2tlPSIjOWM2YjE0IiBzdHJva2Utd2lkdGg9IjEuMSIgZD0iTTMwNi43Mjc5LC0yNTEuNEMzMDYuNzI3OSwtMjUxLjQgMjA2LjAyMDcsLTI1MS40IDIwNi4wMjA3LC0yNTEuNCAyMDAuMDIwNywtMjUxLjQgMTk0LjAyMDcsLTI0NS40IDE5NC4wMjA3LC0yMzkuNCAxOTQuMDIwNywtMjM5LjQgMTk0LjAyMDcsLTE4My40IDE5NC4wMjA3LC0xODMuNCAxOTQuMDIwNywtMTc3LjQgMjAwLjAyMDcsLTE3MS40IDIwNi4wMjA3LC0xNzEuNCAyMDYuMDIwNywtMTcxLjQgMzA2LjcyNzksLTE3MS40IDMwNi43Mjc5LC0xNzEuNCAzMTIuNzI3OSwtMTcxLjQgMzE4LjcyNzksLTE3Ny40IDMxOC43Mjc5LC0xODMuNCAzMTguNzI3OSwtMTgzLjQgMzE4LjcyNzksLTIzOS40IDMxOC43Mjc5LC0yMzkuNCAzMTguNzI3OSwtMjQ1LjQgMzEyLjcyNzksLTI1MS40IDMwNi43Mjc5LC0yNTEuNCIgLz48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIyNTYuMzc0MyIgeT0iLTIzNC41IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPjcuCmxvZ2ljYWxfd2h5PC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjI1Ni4zNzQzIiB5PSItMjIxLjMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+RWFjaApwcm9wb3NpdGlvbjwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIyNTYuMzc0MyIgeT0iLTIwOC4xIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPnN0YXRlcwphIG1lY2hhbmlzbSw8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMjU2LjM3NDMiIHk9Ii0xOTQuOSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5ub3QKanVzdCBhIGNvcnJlbGF0aW9uPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjI1Ni4zNzQzIiB5PSItMTgxLjciIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+YWR2aXNvcnk8L3RleHQ+PC9nPjwhLS0gY29uc3RydWN0X2NsYXJpdHkmIzQ1OyZndDtsb2dpY2FsX3doeSAtLT48IS0tIGNhdXNhbF90ZXN0YWJpbGl0eSAtLT48ZyBpZD0ibm9kZTEwIiBjbGFzcz0ibm9kZSI+PHRpdGxlPgpjYXVzYWxfdGVzdGFiaWxpdHkKPC90aXRsZT4KPHBhdGggZmlsbD0iI2ZiZjFkYyIgc3Ryb2tlPSIjOWM2YjE0IiBzdHJva2Utd2lkdGg9IjEuMSIgZD0iTTE0NS4zNDE2LC0xMDYuNEMxNDUuMzQxNiwtMTA2LjQgNDkuNDA3LC0xMDYuNCA0OS40MDcsLTEwNi40IDQzLjQwNywtMTA2LjQgMzcuNDA3LC0xMDAuNCAzNy40MDcsLTk0LjQgMzcuNDA3LC05NC40IDM3LjQwNywtMzguNCAzNy40MDcsLTM4LjQgMzcuNDA3LC0zMi40IDQzLjQwNywtMjYuNCA0OS40MDcsLTI2LjQgNDkuNDA3LC0yNi40IDE0NS4zNDE2LC0yNi40IDE0NS4zNDE2LC0yNi40IDE1MS4zNDE2LC0yNi40IDE1Ny4zNDE2LC0zMi40IDE1Ny4zNDE2LC0zOC40IDE1Ny4zNDE2LC0zOC40IDE1Ny4zNDE2LC05NC40IDE1Ny4zNDE2LC05NC40IDE1Ny4zNDE2LC0xMDAuNCAxNTEuMzQxNiwtMTA2LjQgMTQ1LjM0MTYsLTEwNi40IiAvPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9Ijk3LjM3NDMiIHk9Ii04OS41IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPjkuCmNhdXNhbF90ZXN0YWJpbGl0eTwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI5Ny4zNzQzIiB5PSItNzYuMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5BdApsZWFzdCBvbmU8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iOTcuMzc0MyIgeT0iLTYzLjEiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+cHJvcG9zaXRpb24Kc3RhdGVzIGE8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iOTcuMzc0MyIgeT0iLTQ5LjkiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+Y2F1c2FsCnJlbGF0aW9uPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9Ijk3LjM3NDMiIHk9Ii0zNi43IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPmFkdmlzb3J5PC90ZXh0PjwvZz48IS0tIGNvbnN0cnVjdF9jbGFyaXR5JiM0NTsmZ3Q7Y2F1c2FsX3Rlc3RhYmlsaXR5IC0tPjwhLS0gc2NvcGUgLS0+PGcgaWQ9Im5vZGU5IiBjbGFzcz0ibm9kZSI+PHRpdGxlPgpzY29wZQo8L3RpdGxlPgo8cGF0aCBmaWxsPSIjZmJmMWRjIiBzdHJva2U9IiM5YzZiMTQiIHN0cm9rZS13aWR0aD0iMS4xIiBkPSJNNDUyLjAxNzIsLTI0NC43MDAzQzQ1Mi4wMTcyLC0yNDQuNzAwMyAzNTIuNzMxNCwtMjQ0LjcwMDMgMzUyLjczMTQsLTI0NC43MDAzIDM0Ni43MzE0LC0yNDQuNzAwMyAzNDAuNzMxNCwtMjM4LjcwMDMgMzQwLjczMTQsLTIzMi43MDAzIDM0MC43MzE0LC0yMzIuNzAwMyAzNDAuNzMxNCwtMTkwLjA5OTcgMzQwLjczMTQsLTE5MC4wOTk3IDM0MC43MzE0LC0xODQuMDk5NyAzNDYuNzMxNCwtMTc4LjA5OTcgMzUyLjczMTQsLTE3OC4wOTk3IDM1Mi43MzE0LC0xNzguMDk5NyA0NTIuMDE3MiwtMTc4LjA5OTcgNDUyLjAxNzIsLTE3OC4wOTk3IDQ1OC4wMTcyLC0xNzguMDk5NyA0NjQuMDE3MiwtMTg0LjA5OTcgNDY0LjAxNzIsLTE5MC4wOTk3IDQ2NC4wMTcyLC0xOTAuMDk5NyA0NjQuMDE3MiwtMjMyLjcwMDMgNDY0LjAxNzIsLTIzMi43MDAzIDQ2NC4wMTcyLC0yMzguNzAwMyA0NTguMDE3MiwtMjQ0LjcwMDMgNDUyLjAxNzIsLTI0NC43MDAzIiAvPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjQwMi4zNzQzIiB5PSItMjI3LjkiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+OC4Kc2NvcGU8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iNDAyLjM3NDMiIHk9Ii0yMTQuNyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5Cb3VuZGFyeQpjb25kaXRpb25zPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjQwMi4zNzQzIiB5PSItMjAxLjUiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+ZXhwbGljaXRseQpzdGF0ZWQ8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iNDAyLjM3NDMiIHk9Ii0xODguMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5hZHZpc29yeTwvdGV4dD48L2c+PCEtLSBsb2dpY2FsX3doeSYjNDU7Jmd0O3Njb3BlIC0tPjwhLS0gZGlhZ25vc3RpY2l0eSAtLT48ZyBpZD0ibm9kZTExIiBjbGFzcz0ibm9kZSI+PHRpdGxlPgpkaWFnbm9zdGljaXR5CjwvdGl0bGU+CjxwYXRoIGZpbGw9IiNmYmYxZGMiIHN0cm9rZT0iIzljNmIxNCIgc3Ryb2tlLXdpZHRoPSIxLjEiIGQ9Ik0yOTMuNTU5NywtMTMyLjcwMDJDMjkzLjU1OTcsLTEzMi43MDAyIDE5MS4xODg5LC0xMzIuNzAwMiAxOTEuMTg4OSwtMTMyLjcwMDIgMTg1LjE4ODksLTEzMi43MDAyIDE3OS4xODg5LC0xMjYuNzAwMiAxNzkuMTg4OSwtMTIwLjcwMDIgMTc5LjE4ODksLTEyMC43MDAyIDE3OS4xODg5LC0xMi4wOTk4IDE3OS4xODg5LC0xMi4wOTk4IDE3OS4xODg5LC02LjA5OTggMTg1LjE4ODksLS4wOTk4IDE5MS4xODg5LC0uMDk5OCAxOTEuMTg4OSwtLjA5OTggMjkzLjU1OTcsLS4wOTk4IDI5My41NTk3LC0uMDk5OCAyOTkuNTU5NywtLjA5OTggMzA1LjU1OTcsLTYuMDk5OCAzMDUuNTU5NywtMTIuMDk5OCAzMDUuNTU5NywtMTIuMDk5OCAzMDUuNTU5NywtMTIwLjcwMDIgMzA1LjU1OTcsLTEyMC43MDAyIDMwNS41NTk3LC0xMjYuNzAwMiAyOTkuNTU5NywtMTMyLjcwMDIgMjkzLjU1OTcsLTEzMi43MDAyIiAvPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjI0Mi4zNzQzIiB5PSItMTE1LjkiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+MTAuCmRpYWdub3N0aWNpdHk8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMjQyLjM3NDMiIHk9Ii0xMDIuNyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5BdApsZWFzdCBvbmU8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMjQyLjM3NDMiIHk9Ii04OS41IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPnByZWRpY3Rpb24KbmFtZXMgYTwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIyNDIuMzc0MyIgeT0iLTc2LjMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+cmVnaXN0ZXJlZAphbHRlcm5hdGl2ZTwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIyNDIuMzc0MyIgeT0iLTYzLjEiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+aXQKaXMgZGVjbGFyZWQgdG88L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMjQyLjM3NDMiIHk9Ii00OS45IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPmRpc2NyaW1pbmF0ZQpmcm9tPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjI0Mi4zNzQzIiB5PSItMzYuNyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj4oZGVjbGFyZWQsCm5vdDwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIyNDIuMzc0MyIgeT0iLTIzLjUiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+dmVyaWZpZWQpPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjI0Mi4zNzQzIiB5PSItMTAuMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5hZHZpc29yeTwvdGV4dD48L2c+PCEtLSBjYXVzYWxfdGVzdGFiaWxpdHkmIzQ1OyZndDtkaWFnbm9zdGljaXR5IC0tPjwhLS0gZm9ybWFsaXNhdGlvbiAtLT48ZyBpZD0ibm9kZTEyIiBjbGFzcz0ibm9kZSI+PHRpdGxlPgpmb3JtYWxpc2F0aW9uCjwvdGl0bGU+CjxwYXRoIGZpbGw9IiNmYmYxZGMiIHN0cm9rZT0iIzljNmIxNCIgc3Ryb2tlLXdpZHRoPSIxLjEiIGQ9Ik00NDYuOTM1MywtMTEzLjEwMDJDNDQ2LjkzNTMsLTExMy4xMDAyIDMzOS44MTM0LC0xMTMuMTAwMiAzMzkuODEzNCwtMTEzLjEwMDIgMzMzLjgxMzQsLTExMy4xMDAyIDMyNy44MTM0LC0xMDcuMTAwMiAzMjcuODEzNCwtMTAxLjEwMDIgMzI3LjgxMzQsLTEwMS4xMDAyIDMyNy44MTM0LC0zMS42OTk4IDMyNy44MTM0LC0zMS42OTk4IDMyNy44MTM0LC0yNS42OTk4IDMzMy44MTM0LC0xOS42OTk4IDMzOS44MTM0LC0xOS42OTk4IDMzOS44MTM0LC0xOS42OTk4IDQ0Ni45MzUzLC0xOS42OTk4IDQ0Ni45MzUzLC0xOS42OTk4IDQ1Mi45MzUzLC0xOS42OTk4IDQ1OC45MzUzLC0yNS42OTk4IDQ1OC45MzUzLC0zMS42OTk4IDQ1OC45MzUzLC0zMS42OTk4IDQ1OC45MzUzLC0xMDEuMTAwMiA0NTguOTM1MywtMTAxLjEwMDIgNDU4LjkzNTMsLTEwNy4xMDAyIDQ1Mi45MzUzLC0xMTMuMTAwMiA0NDYuOTM1MywtMTEzLjEwMDIiIC8+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMzkzLjM3NDMiIHk9Ii05Ni4xIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPjExLgpmb3JtYWxpc2F0aW9uPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjM5My4zNzQzIiB5PSItODIuOSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5BCmZvcm1hbCBtb2RlbCBvZiBhPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjM5My4zNzQzIiB5PSItNjkuNyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5yZWNvZ25pc2VkCnR5cGUgKG9kZSw8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMzkzLjM3NDMiIHk9Ii01Ni41IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPmFibSwKbmV0d29yaywgc2VtKSBpczwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIzOTMuMzc0MyIgeT0iLTQzLjMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+ZGVjbGFyZWQ8L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMzkzLjM3NDMiIHk9Ii0zMC4xIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPmFkdmlzb3J5PC90ZXh0PjwvZz48IS0tIGRpYWdub3N0aWNpdHkmIzQ1OyZndDtmb3JtYWxpc2F0aW9uIC0tPjwvZz48L3N2Zz4=)

All of these views are deterministic. The DOT strings render with any
Graphviz engine, and the SVG views open in any browser. Together with
the `nomological_net` and `causal_dag` views introduced in the Get
started vignette, they complete the set of diagram types that
[`tf_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_diagram.md)
exports, each documented in
[`?tf_diagram`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_diagram.md).
