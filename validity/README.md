# Validity of theoryforge: report, protocol and data

This folder holds the validity report on theoryforge, the data it reads and
the protocol of the studies that would test what the report leaves open. The
report rests on an audit of the packages and apps at commit f72ce4c, whose code
is the same as that of b5ebf84, the release candidate before the corrections
made for version 0.8.0. Eight lenses, each an auditor examining the package
from one point of view, examined the code and documentation: the claims
register, causal verification, statistics and simulation, a red team of the
checklist score, philosophy of science, measurement, metascience and related
tools, and communication and apps. An independent second reader rechecked each
lens, and three encoders encoded three verbal theories in a pilot. Every
auditor, second reader and encoder was an AI agent, and so was the drafter of
the report and of the status register. The folder lies outside both packages:
no R build, Python distribution or CI job reads it.

The audit's own files, the scripts, inputs and outputs of each lens, of each
second reader and of the pilot, are kept outside the repository. Every path
into them, here and in the register, is relative to that audit directory.

## The report and the protocol

- `report.qmd`: the validity report. It reads every number from `data/`,
  reruns `demonstrations/run.R` against `r/theoryforge` in the working tree,
  says whether that run equals `data/demonstrations-0.8.0.csv` and prints a
  hash of the package source it read.
- `protocol.qmd`: the protocol of three preregistered studies with human
  participants (encoding reliability, agreement with expert judgement and
  known groups, and a reader study), with sample sizes computed from stated
  inputs.
- `references.bib` and `apa.csl`: the references of both documents, each
  checked against Crossref or PubMed, and the APA style that sets them.

Either document renders from this folder with Quarto and R, given knitr,
rmarkdown, jsonlite and pkgload (and lme4 for the protocol) and the R
package's dependencies:

    LANG=C.utf8 quarto render report.qmd

The rendered HTML is not kept in the repository.

## The register

`data/findings.csv` has one row per finding of each lens and of the pilot,
followed for each lens by the defects its second reader said the lens had
missed.

- `lens`, `group` (formal or conceptual) and `id` (the lens and a number).
- `raised_by`: `lens`, or `second reader` for a missed defect.
- `title` and `component`.
- `severity_lens`: critical, major or minor, as the lens graded it.
- `severity_verified`: the second reader's grade where a check covered the
  finding, the lens's grade where the reader upheld it without grading it, and
  `none` for a finding the reader withdrew. For a missed defect, the grade the
  reader stated, if any. Blank where no check covered the finding, as for every
  finding of the pilot, which had no second reader.
- `upheld`: `true` or `false` where a check covered the finding.
- `fix_before_release`: the lens's flag.
- `recommendation`: the lens's, followed by 'Second reader:' and the reader's
  correction where there is one.
- `evidence_path`: the output or script to rerun, relative to the audit
  directory (several are separated by '; ').
- `check`: the reader's check that covered the finding (C and its number in the
  reader's list), or the reader's missed item (M and its number).
- `extends`: for a missed defect, the lens finding it adds to.

`data/verdicts.csv` has one row per verdict: `lens`, `group`, `id` (the lens,
'v' and a number), `component`, `claim`, `category`, `verdict` (sound, sound
with caveats, questionable, unsupported or wrong), `recommendation` (keep,
qualify, rework, remove or extend), `check` and `upheld` where a check covered
the verdict, and `verdict_verified` and `recommendation_verified` where the
reader changed them. Two verdicts the reader split by part carry both readings.

`data/references.csv` lists every reference a lens or a second reader verified,
once per DOI: `doi`, `citation`, `verified_how` (each account, separated by
' | '), `lenses` (those that cite it) and `second_readers` (those whose
Crossref or PubMed checks name it).

`data/status-0.8.0.csv` has one row per finding and per verdict (`kind` and
`id`). `status_080` says what version 0.8.0 does about it: `fixed` (the
behaviour or rule is corrected), `reported` (the problem is reported beside
the result, without changing the verdict or the gate the finding concerns),
`reworded` (the outputs and documents say what is computed, the behaviour is
unchanged), `unchanged`, `deferred` (unchanged, the remedy being one of the
expansions the maintainer plans for 0.9.0, for which no plan is published),
`withdrawn` or `not applicable` (a verdict of sound whose recommendation is to
keep). A verdict of sound with caveats whose recommendation is to keep is
`reworded` where 0.8.0 states its caveat in more places, and `unchanged`
otherwise. Other verdicts are classed as findings are. `checked` says who
checked the row again after the agent that classified it: `drafter` (the
agents that drafted and revised the report), `reviewer` (a reviewer of the
draft), `both` or `none`. `revised` is `status` where the status differs from
the classifying agent's, `basis` where the status was kept and the basis
qualified after a check, and `none` otherwise. `basis` names the file or the
rerun on 0.8.0 that shows the status and, after 'Remaining:', what is left of a
finding classed as fixed. For a verdict of sound with caveats kept unchanged,
it says whether the documentation already stated the caveat, the caveat
concerns the auditors' own reading of a source or it is not documented.

`data/verification.csv` has one row per independent check of the deductive
and numerical core by the causal-verification and statistics-and-simulation
lenses and their second readers: `component`, `quantity` (which names the
unit of the cases), `comparator`, `kind`, `cases`, `agreements` and
`discrepancies` (blank where the check measures a rate or the size of an
approximation), `note` and `evidence_path`. `kind` is `package` where an output
of the package is compared with independent software, the auditors' own
implementation of a definition or an analytic or published value, `parity`
where the R twin is compared with the Python twin, and `other` where the check
concerns a sentence of the documentation, a design argument, a reference
implementation or the package against itself.

`scripts/build_register.py` writes `findings.csv`, `verdicts.csv` and
`references.csv` from the two results of the audit (the formal and the
conceptual group, each a JSON file holding the lenses' results and the second
readers' checks). The judgements it needs, which check covers which finding or
verdict, which missed items state a defect and where the evidence lies when the
text does not name it, are in `scripts/mapping.yaml`, each made by reading the
lens and the reader side by side. To rebuild, with PyYAML installed:

    python3 validity/scripts/build_register.py FORMAL.json CONCEPTUAL.json \
      --audit AUDIT_DIR

## The demonstrations

`demonstrations/` holds the theory files behind the audit's main
demonstrations. The first line of each says where it came from.

- `adversarial/`: files that score highly although they are empty, circular,
  vague, placeholder text or refuted. They are the red team's three files, the
  measurement lens's hollow theory, the one-letter 'x' theory and the
  blue-socks theory, as written and with every test failed.
- `strong/`: four theories encoded from their sources (light deflection,
  prospect theory, Hick's law, Michaelis–Menten kinetics), each as first
  encoded and as re-encoded with every field the sources allow filled in.
- `amendments/`: a sign reversal and a weakened sign, both against one prior,
  and an amendment whose only addition is an assumption listing an old
  prediction in 'protects', with its prior.
- `loops/`: a contradicted claim without a feedback loop, with a loop through
  the claim, with a loop unrelated to it and with an unrelated edge, and the
  same for a bundled example given a wrong sign.
- `phenomena/`: the same contradicted claim added to a bundled example as a
  prediction and as a phenomenon.
- `pilot/`: the nine pilot encodings (three encoders, three theories) and the
  three source summaries they were encoded from.

`demonstrations/run.R` loads the R package from `r/theoryforge` in this
repository and writes one row per file, or per prior and amendment pair: the
set, the file and its prior, the checklist version, whether the file passes
full validation, the checklist score and its range, the gate, the status of
derivation_chain and, for an amendment, the appraisal's verdict, content_lost
and the keys that later versions of the appraisal add. To rerun it against the
code in the working tree:

    LANG=C.utf8 Rscript validity/demonstrations/run.R

which writes `data/demonstrations.csv`. `data/demonstrations-f72ce4c.csv` is
the same run on the code at f72ce4c (run on b5ebf84, which has the same code)
and `data/demonstrations-0.8.0.csv` the run on version 0.8.0, kept so that the
report can compare them.

## The pilot's tables

`data/pilot/` holds the tables of the pilot's analysis that the report draws
on, copied from `pilot/analysis/tables/`, where `RERUN.txt` says how they were
made.

- `summary.json`: checklist scores by theory and encoder, their spread, the
  intraclass correlation between theories, item status agreement and the count
  of differences between R and Python.
- `checklist_by_encoder.csv`: score, range, coverage, gate and every item's
  status and score for the nine files.
- `checklist_item_spread.csv`: the three encoders' values of each item and the
  points they move.
- `construct_agreement.csv`, `edge_agreement.csv` and `claim_agreement.csv`:
  agreement between encoders on constructs, edges and stated claims.
- `units_agreement.csv`: how many statements of each source became the same
  kind of element in all three files, with Fleiss' kappa and the attributed
  cause of each disagreement.
- `implications_agreement.csv` and `independence_model_common.csv`: agreement
  on implied independencies, literally and over the constructs all three
  encoders share.
- `derived_sign_agreement.csv`, `entailments_by_claim.csv` and
  `entailments_shared_claims.csv`: derived signs and claim verdicts, and how
  far they agree across encoders.
- `equivalent_models.csv`: compelled and reversible edges per file.
- `preregistration.csv`: the 'Derivations check' line, hypotheses, claim
  verdicts and implied independencies of each preregistration.
- `perturbations.csv`: one-change-at-a-time edits of an encoding and what each
  changed.
- `linear_check.csv` and `linear_check_pairs.csv`: derived signs against
  sampled linear models, and the pairs left open that every sampled stable
  draw fixed.
- `implications_independent_check.csv`: the implied independencies against a
  separation reader that does not import theoryforge.
- `parity_r_python.csv`: differences between the R and Python results.
- `severity.csv` and `structure.csv`: the claim-form rubric's values and the
  counts of each kind of element per file.
