# theoryforge 0.4.0

* The DOT diagram views are redesigned for content and legibility. Every view
  opens with a shared Meridian style prelude (Helvetica type, role-coloured
  rounded nodes); labels wrap so nodes stay narrow; workflow and pipeline nodes
  carry the id with the relation or type rather than a bare word; the
  development roadmap stacks its items in a single column; and the theme
  landscape colours themes by status. Every view fits a documentation column.
  The intermediate representation stays byte-identical to the Python twin's.

# theoryforge 0.3.0

* New `tf_render_diagram()` renders the digraph views without leaving R: a
  DiagrammeR widget for the viewer and R Markdown, or a standalone SVG string
  with `as = "svg"`. It accepts a theory or a raw DOT string, so
  `tf_lit_diagram()` output renders the same way; the three SVG chart views
  pass through unchanged, and `causal_dag` is refused with a pointer to
  dagitty. The rendering packages (`DiagrammeR`, `DiagrammeRsvg`, `htmltools`)
  are in Suggests, so the deterministic core stays dependency-free, and
  rendering sits outside the cross-language parity contract. The articles now
  show each digraph rendered beneath its intermediate representation.

# theoryforge 0.2.0

* The severity chart is re-laid out: bars start just past the longest row label
  and each value trails its own bar. The diagram intermediate representation for
  `tf_diagram(type = "severity")` changes accordingly; it stays byte-identical to
  the Python twin's.
* Documentation: the articles now show the `provenance`, `development_roadmap`,
  `pipeline` and `co_citation` views, the embedding-redundancy screen,
  `tf_validate(full = TRUE)` and the remaining build verbs, and a new section
  covers rendering and depositing.

# theoryforge 0.1.0

First public release. The package provides a reproducible workflow for building,
developing and testing scientific theories, with behaviour pinned by a shared
specification
([`API_SPEC.md`](https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md)) so the R
and Python twins return identical verdicts and byte-identical diagram intermediate
representations.

* Core: theory-object input, output and structural validation; a 12-item
  rigour checklist with a weighted aggregate score and a blocker gate; diagram
  intermediate representations (nomological net, provenance, causal DAG); and a
  deterministic lexical construct-redundancy screen. Where the schema expects an
  array of strings, a nonempty scalar string is read as a singleton list
  (API_SPEC.md section 4), so natural YAML such as `derives_from: p1` yields the
  same rigour verdict and gate as the Python twin; an empty or whitespace-only
  scalar counts as absent.
* Workflow modes: a builder API with auto-logged provenance (BUILDING); an
  operationalised severity rubric and preregistration export (TESTING); and a
  Lakatosian progressive-versus-degenerating amendment appraisal (DEVELOPMENT).
* Literature layer: a deterministic bibliometric mapping (`tf_litmap`,
  `tf_landscape`, `tf_lit_diagram`), a parity-exempt OpenAlex corpus adapter, and
  a deterministic, dependency-free check for DOIs not yet cited by a theory
  (`tf_new_evidence_dois`), for use with a search from any source, including the
  companion `scopusflow` package. `tf_lit_diagram()` lists the valid types in its
  unknown-type error, matching `tf_diagram()`.
* Testing and review: lavaan model-syntax compilation (`tf_compile_sem`) and a
  reviewer-facing audit dossier (`tf_dossier`).
* Simulation, reporting and deposit: a deterministic dynamical-system runner
  (`tf_simulate`), a Quarto report wrapper (`tf_render_report`), an opt-in
  embedding redundancy screen (`tf_embedding_redundancy`), and an OSF deposit
  adapter (`tf_osf_push`, dry-run by default). `tf_osf_push()` percent-encodes
  the filename component of the upload URL, keeping the dry-run request
  identical to the Python twin's.
* Cross-language determinism: the literature layer and the amendment appraisal
  sort with radix (codepoint) ordering regardless of locale, matching the Python
  twin for mixed-case keywords and ids.
* Metadata: `citation("theoryforge")` and the About article read the package
  version from the package metadata.
