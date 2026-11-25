# theoryforge <span class="mrd-lang">(Python)</span>

Theories in the behavioural sciences often define their constructs too loosely to
measure, state claims that no result could contradict and survive a failed test by adding
an assumption that protects them. theoryforge holds a theory as a structured file of
constructs, propositions, predictions, rival accounts and test outcomes, and computes what
that file commits the theory to. It scores the theory against a checklist of rigour
criteria drawn from the methodology literature, derives the independencies and signed
effects its causal graph implies, grades how risky each prediction is and how severely it
has been tested, and appraises whether an amendment adds content or only shields the theory
from an anomaly.

## A worked result

The package includes a deliberately underspecified theory of motivation. Reading it and
running the rigour checklist gives its score, the range of scores the checklist's other
weightings would give, its gate and the items it does not pass.

```python exec="1" source="block" result="text" session="home"
import theoryforge as tf

weak = tf.read(tf.example_path("weak-theory.theory.yaml"))
report = weak.check()

print(report["aggregate_score"], report["aggregate_range"], report["gate"])
for item in report["items"]:
    if item["status"] != "pass":
        print(f'{item["id"]:<19} {item["status"]:<5} {item["severity_if_fail"]}')
```

The gate is blocked because two items that the checklist treats as blockers failed. The
theory's one prediction, 'Motivated people exist', asserts an existence claim, which no
observation can contradict, and it cites no proposition from which it would follow. To
unblock the gate, the author would state a prediction that rules out some result, such as a
direction or a bounded range of an effect, and derive it from a proposition. The warnings
name the remaining work. Motivation and Drive are defined in nearly the same words and would
have to be merged or defined apart. Neither construct has a measure or a stated scope, and
the one proposition is an association without a mechanism. The
[development roadmap](workflow-modes.md#visualising-the-theory) draws the same list as an
ordered worklist.

The score is a mean of the item scores under conventional weights, and the gate is the
verdict to act on. A passing gate shows that the theory's file states what a test would
need, and it does not show that the theory is true.
[Methodological foundations](methodology.md) gives the rationale and the computation behind
each item.

## From building to testing

A theory's `maturity` field records its stage as `building`, `developing` or `testing`, or
as `draft`, which makes the rigour checklist's gate advisory. At the building stage, the
builder methods assemble the theory and log each step. `read_dagitty()` starts a draft from
a causal diagram drawn in DAGitty. Validation checks the file against the schema and every
cross-reference, and the content hash identifies its content exactly.

At the developing stage, `appraise_amendment()` compares a revision with its prior version
and classifies it as progressive, degenerating or neutral, the first two in Lakatos's sense.

At the testing stage, the causal graph of the propositions is read for the conditional
independencies it implies, the signs of the effects it entails, the directions no
observational study can settle and the results that would tell it from a rival. The package
then grades each prediction before and after the data, writes the theory and hypotheses
sections of a preregistration and assembles an audit dossier for a reviewer.

[Get started](getting-started.md) covers reading, validating and scoring a theory, and
[Workflow modes](workflow-modes.md) follows the three stages with a worked example of each
function. The [literature layer](literature.md) maps a corpus of publications and finds the
themes that the theory and its rivals share words with.

## Install

```bash
pip install theoryforge
```

## A first look

The examples ship with the package, so these lines run straight after installation.

```python
import theoryforge as tf

t = tf.read(tf.example_path("modality-switching.theory.yaml"))
t.validate(full=True)    # the schema, every cross-reference and the recorded hash
t.check()                # the rigour checklist: score, range, gate and items
t.implications()         # the conditional independencies the causal graph implies
t.entailments()          # whether the graph entails each claim the theory states
t.discriminate("alt_grounding_by_interaction")   # where data could tell it from a rival
t.dossier()              # the audit dossier for a reviewer, as Markdown
```

## Browser apps

Two [browser apps](app.md) run the package in a web page, with a theory editor that needs no
YAML. The Python app runs this package through Pyodide, and nothing leaves the browser.

## Two languages, one specification

This is the Python twin of [the R package](https://pablobernabeu.github.io/theoryforge/r/) of
the same name. Both implement one
[specification](https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md), and
their deterministic functions, from validation and the checklist to the causal reading, the
preregistration and the dossier, are checked against shared expected outputs. The helpers
that depend on a network service, a user-supplied embedder or a renderer
(`fetch_corpus()`, `osf_push()`, `embedding_redundancy()` and `render_diagram()`) can give
different results in the two languages. The [API reference](api.md) lists the differences in
naming.

## Author

theoryforge is written and maintained by
[Pablo Bernabeu](https://pablobernabeu.github.io) and released under the MIT licence.
If theoryforge contributes to published work, please [cite it](about.md#citing-theoryforge).
Its citation gives the concept DOI <https://doi.org/10.5281/zenodo.21229964>, which resolves to
the latest release archived on Zenodo.
