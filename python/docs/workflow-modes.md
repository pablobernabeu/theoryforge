# Workflow modes

theoryforge organises work into three modes: BUILDING, DEVELOPMENT, and
TESTING. A theory is a single versioned object that moves through these
modes as it matures. Each mode is a set of methods on the `Theory` object,
so the same artefact carries from a first draft to a preregistered test.

Throughout, the package is imported as `tf`.

```python
import theoryforge as tf
```

## BUILDING

BUILDING assembles a theory from scratch. `tf.new_theory()` returns an empty
`Theory`, and the `add_*` methods append constructs, propositions, and
predictions. Each method returns the same object, so calls chain. Every
addition is recorded in a provenance log, which gives a step-by-step account
of how the theory was assembled.

```python
t = (
    tf.new_theory("panic_demo", "A demonstration theory of panic")
      .add_construct(
          "arousal",
          "Physiological arousal",
          "bodily signs of sympathetic activation",
          measurement=["heart_rate", "skin_conductance"],
          boundary_conditions=["adults"],
      )
      .add_construct(
          "catastrophic_interpretation",
          "Catastrophic interpretation",
          "appraisal of bodily sensations as dangerous",
          measurement=["bsiq"],
      )
      .add_proposition(
          "p1",
          "arousal",
          "catastrophic_interpretation",
          "increases",
          mechanism="rising arousal is read as evidence of threat",
      )
      .add_prediction(
          "pred1",
          "higher arousal predicts more catastrophic interpretation",
          "directional",
          derives_from=["p1"],
      )
)
```

The positional arguments follow the schema. `add_construct(id, label,
definition)` takes optional `measurement` and `boundary_conditions` lists.
`add_proposition(id, from, to, relation)` takes an optional `mechanism`,
where `relation` is one of `increases`, `decreases`, `moderates`,
`mediates`, `causes`, or `associates`. `add_prediction(id, statement,
type)` takes optional `derives_from` and `diagnostic_vs` lists, where `type`
is one of `point`, `interval`, `directional`, or `existence`.

The provenance log is held under `t.data["provenance"]`. Each entry records
the action and the identifier it affected.

```python
for step in t.data["provenance"]:
    print(step["step"], step["action"], step["detail"])
```

Once the object is assembled, `t.validate()` confirms it satisfies the
schema's required fields, and `t.report()` returns the rigour checklist.

```python
t.validate()
print(t.report("json"))
```

## DEVELOPMENT

DEVELOPMENT compares two versions of a theory and judges whether an
amendment is an improvement. The appraisal operationalises the Lakatosian
distinction between progressive and degenerating problem shifts. An
amendment is progressive when it yields newly corroborated predictions
without resorting to ad-hoc immunising assumptions.

Call `appraise_amendment` on the newer version, passing the prior version as
the argument.

```python
v1 = tf.read("panic-network.theory.yaml")
v2 = tf.read("panic-network-2026-v2.theory.yaml")

result = v2.appraise_amendment(v1)
print(result["verdict"])
```

The return value is a dictionary with four keys.

```python
{
    "verdict": "progressive",          # 'progressive', 'degenerating', or 'neutral'
    "new_predictions": ["pred5"],      # prediction ids present in v2 but not v1
    "corroborated_new": ["pred5"],     # of those, the ones with a passed test outcome
    "ad_hoc_assumptions": [],          # new assumptions that protect untested predictions
}
```

The verdict depends on the recorded test outcomes and any new auxiliary
assumptions in the newer version. The rule is as follows.

- `progressive`: at least one new prediction is corroborated and no ad-hoc
  assumptions were added.
- `degenerating`: at least one ad-hoc assumption was added and no new
  prediction is corroborated.
- `neutral`: any other combination.

A new prediction counts as corroborated when the newer version carries a
matching entry under `test_outcomes` with `passed` set to `True`. A new
auxiliary assumption counts as ad-hoc when it has an `added_for` reason but
none of the predictions it claims to protect has a passing test outcome.

## TESTING

TESTING prepares a theory for empirical evaluation. It scores how risky each
prediction is, exports a preregistration document, and assembles a
reviewer-facing audit bundle.

### Severity

`severity()` returns one entry per prediction, in file order, giving the
base risk implied by the prediction type and the computed severity after the
rubric's adjustments.

```python
for s in t.severity():
    print(s["prediction_id"], s["risk_score"], s["computed_severity"])
```

Each entry has the shape below.

```python
{
    "prediction_id": "pred1",
    "type": "directional",
    "risk_score": 0.4,            # base risk from the prediction type
    "computed_severity": 0.3,     # after the directional discount and any diagnostic bonus
}
```

Base risk rises with the strength of the claim: `existence` 0.1,
`directional` 0.4, `interval` 0.7, `point` 0.9. Directional predictions
carry a discount for the ambient correlations expected in the field. A
prediction that discriminates the theory from a named alternative, through
its `diagnostic_vs` field, earns a small severity bonus.

### Preregistration

`preregister()` renders a Markdown preregistration document. It lists the
hypotheses with their derivations and a severity line for each prediction.
Called without an argument it returns the text. Passing a path also writes
the file.

```python
text = t.preregister()
print(text)

t.preregister("panic-prereg.md")    # also writes the document to disk
```

### Audit bundle

`dossier()` assembles a single Markdown document for reviewers. It composes
the rigour checklist, the severity table, the provenance log, and the
preregistration into one artefact. The output is deterministic, so it can be
committed or attached to a submission.

```python
print(t.dossier())
```

`compile_sem()` translates the structural content into lavaan model syntax.
Constructs with measurement indicators become a latent measurement model
with `=~`, and directed propositions become structural paths with `~`.

```python
print(t.compile_sem())
```

A representative fragment of the output is shown below.

```
# lavaan model generated by theoryforge for panic_demo
# Measurement model
arousal =~ heart_rate + skin_conductance
catastrophic_interpretation =~ bsiq
# Structural model
catastrophic_interpretation ~ arousal
```

These three modes share one object, so a theory built with the BUILDING
methods can be appraised under DEVELOPMENT and then carried into TESTING
without conversion.
