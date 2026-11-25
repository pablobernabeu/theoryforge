# Validity of theoryforge: register, demonstrations and pilot data

This folder holds the data behind the validity report on theoryforge. The
report rests on an audit of the packages and apps at commit f72ce4c, whose code
is the same as that of the 0.8.0 release candidate (b5ebf84). Eight lenses
examined the code and documentation: the claims register, causal verification,
statistics and simulation, a red team of the checklist score, metascience and
related tools, communication and apps, philosophy of science and measurement.
An independent second reader rechecked each lens, and three encoders encoded
three verbal theories in a pilot. The folder lies outside both packages:
neither the R build, the Python distributions nor any CI job reads it.

The audit's own files, the scripts, inputs and outputs of each lens, of each
second reader and of the pilot, are kept outside the repository. Every path
into them, here and in the register, is relative to that audit directory.

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

`scripts/build_register.py` writes the three files from the two results of
the audit (the formal and the conceptual group, each a JSON file holding the
lenses' results and the second readers' checks). The judgements it needs, which
check covers which finding or verdict, which missed items state a defect and
where the evidence lies when the text does not name it, are in
`scripts/mapping.yaml`, each made by reading the lens and the reader side by
side. To rebuild, with PyYAML installed:

    python3 validity/scripts/build_register.py FORMAL.json CONCEPTUAL.json --audit AUDIT_DIR

## The demonstrations

`demonstrations/` holds the theory files behind the audit's main
demonstrations. The first line of each says where it came from.

- `adversarial/`: files that score highly although they are empty, circular,
  vague, placeholder text or refuted. They are the red team's three files, the
  measurement lens's hollow theory, the one-letter 'x' theory and the
  blue-socks theory, as written and with every test failed.
- `strong/`: four theories encoded from their sources (light deflection,
  prospect theory, Hick's law, Michaelis-Menten kinetics), each as first
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
the same run on the code at f72ce4c (run on b5ebf84, which has the same code),
kept so that the report can compare the two.

## The pilot's tables

`data/pilot/` holds the tables of the pilot's analysis that the report draws
on, copied from `pilot/analysis/tables/`, where `RERUN.txt` says how they were
made.

- `summary.json`: checklist scores by theory and encoder, their spread, the
  intraclass correlation between theories, item status agreement and the count
  of differences between R and Python.
- `checklist_by_encoder.csv`: score, range, coverage, gate and every item's
  status and score for the nine files; `checklist_item_spread.csv` the three
  encoders' values of each item and the points they move.
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
  sampled linear models, and the pairs left open that every stable draw fixed.
- `implications_independent_check.csv`: the implied independencies against a
  separation reader that does not import theoryforge.
- `parity_r_python.csv`: differences between the R and Python results.
- `severity.csv` and `structure.csv`: the claim-form rubric's values and the
  counts of each kind of element per file.
