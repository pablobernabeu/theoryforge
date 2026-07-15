# Workflow modes

theoryforge organises work into three modes: BUILDING, DEVELOPMENT and
TESTING. A theory is a single versioned object that moves through these
modes as it matures. Each mode is a set of methods on the `Theory` object,
so the same artefact carries from a first draft to a preregistered test.

This page assumes you have already read a theory as in
[Getting started](getting-started.md); see
[Methodological foundations](methodology.md) for the rationale and the exact
computation behind the rigour checklist, severity and amendment-appraisal rules
demonstrated below.

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
`add_proposition(id, frm, to, relation)` takes an optional `mechanism`,
where `relation` is one of `increases`, `decreases`, `moderates`,
`mediates`, `causes` or `associates` (`frm` stands in for the schema's
`from` field, since `from` is a reserved word in Python). `add_prediction(id, statement,
type)` takes optional `derives_from` and `diagnostic_vs` lists, where `type`
is one of `point`, `interval`, `directional` or `existence`.

The provenance log is held under `t.data["provenance"]`. Each entry records
the action and the identifier it affected.

```python
for step in t.data["provenance"]:
    print(step["step"], step["action"], step["detail"])
```

```
1 tf_theory panic_demo
2 tf_add_construct arousal
3 tf_add_construct catastrophic_interpretation
4 tf_add_proposition p1
5 tf_add_prediction pred1
```

Once the object is assembled, `t.validate()` confirms it satisfies the
schema's required fields, and `t.report()` returns the rigour checklist.

```python
t.validate()
print(t.report("json"))
```

`validate()` returns `True` silently; the report opens with the aggregate score
and the gate, then one entry per checklist item.

```
{
  "theory_id": "panic_demo",
  "schema_version": "1.0",
  "maturity": "building",
  "aggregate_score": 57.6,
  "gate": "pass",
  "n_blockers_failed": 0,
  "items": [
    {
      "id": "falsifiability",
      "status": "pass",
      ...
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
    "new_predictions": ["pred4"],      # prediction ids present in v2 but not v1
    "corroborated_new": ["pred4"],     # of those, the ones with a passed test outcome
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

The document opens as follows.

```
# Preregistration: A demonstration theory of panic

- Theory ID: panic_demo
- Schema version: 1.0
- Maturity: building
- Derivation chain verified: yes

## Hypotheses
1. [directional] higher arousal predicts more catastrophic interpretation (derives from: p1)

## Severity
- pred1: severity 0.3, risk 0.4
```

### Audit bundle

`dossier()` assembles a single Markdown document for reviewers. It composes
the rigour checklist, the severity table, the provenance log and the
preregistration into one artefact. The output is deterministic, so it can be
committed or attached to a submission.

```python
print(t.dossier())
```

The bundle opens with the header and the rigour checklist, and the severity
table, provenance log and preregistration follow.

```
# theoryforge dossier: A demonstration theory of panic

- Theory ID: panic_demo
- Maturity: building
- Aggregate rigour score: 57.6/100
- Gate: pass
- Blockers failed: 0

## Rigour checklist

| item | status | score | weight |
| --- | --- | --- | --- |
...
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

## Visualising the theory

`diagram()` exports several views of the same object. The graph views return
Graphviz DOT or dagitty text; three further views are returned directly as SVG
and render inline. These examples use the repository's panic-network fixture
(see [Getting started](getting-started.md) for where the fixture files live),
which carries the test outcomes and scope conditions the richer views draw on.

```python
t = tf.read("panic-network.theory.yaml")
```

The `workflow` view traces the lifecycle from constructs, through propositions and
predictions, to the recorded test outcomes.

```python
print(t.diagram("workflow"))
```

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
```

With the optional render extra (`pip install theoryforge[render]`), the same
view renders without leaving Python: `render_diagram(t, "workflow")` wraps the
DOT in a `graphviz.Source`, which displays inline in a notebook and writes
image files through its `render` method. Rendered, the workflow view reads as
a figure.

<div class="tf-figure tf-diagram"><svg width="466pt" height="246pt"
 viewBox="0.00 0.00 465.51 245.80" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g id="graph0" class="graph" transform="scale(1 1) rotate(0) translate(14.4 231.4)">
<title>workflow</title>
<g id="clust1" class="cluster">
<title>cluster_build</title>
<path fill="transparent" stroke="#c4d1d9" d="M20,-10C20,-10 116.0756,-10 116.0756,-10 122.0756,-10 128.0756,-16 128.0756,-22 128.0756,-22 128.0756,-195 128.0756,-195 128.0756,-201 122.0756,-207 116.0756,-207 116.0756,-207 20,-207 20,-207 14,-207 8,-201 8,-195 8,-195 8,-22 8,-22 8,-16 14,-10 20,-10"/>
<text text-anchor="middle" x="68.0378" y="-193.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#5b7285">building</text>
</g>
<g id="clust2" class="cluster">
<title>cluster_relate</title>
<path fill="transparent" stroke="#c4d1d9" d="M156.0756,-8C156.0756,-8 219.138,-8 219.138,-8 225.138,-8 231.138,-14 231.138,-20 231.138,-20 231.138,-197 231.138,-197 231.138,-203 225.138,-209 219.138,-209 219.138,-209 156.0756,-209 156.0756,-209 150.0756,-209 144.0756,-203 144.0756,-197 144.0756,-197 144.0756,-20 144.0756,-20 144.0756,-14 150.0756,-8 156.0756,-8"/>
<text text-anchor="middle" x="187.6068" y="-195.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#5b7285">propositions</text>
</g>
<g id="clust3" class="cluster">
<title>cluster_predict</title>
<path fill="transparent" stroke="#c4d1d9" d="M259.138,-8C259.138,-8 325.254,-8 325.254,-8 331.254,-8 337.254,-14 337.254,-20 337.254,-20 337.254,-197 337.254,-197 337.254,-203 331.254,-209 325.254,-209 325.254,-209 259.138,-209 259.138,-209 253.138,-209 247.138,-203 247.138,-197 247.138,-197 247.138,-20 247.138,-20 247.138,-14 253.138,-8 259.138,-8"/>
<text text-anchor="middle" x="292.196" y="-195.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#5b7285">predictions</text>
</g>
<g id="clust4" class="cluster">
<title>cluster_test</title>
<path fill="transparent" stroke="#c4d1d9" d="M365.254,-132C365.254,-132 416.7136,-132 416.7136,-132 422.7136,-132 428.7136,-138 428.7136,-144 428.7136,-144 428.7136,-197 428.7136,-197 428.7136,-203 422.7136,-209 416.7136,-209 416.7136,-209 365.254,-209 365.254,-209 359.254,-209 353.254,-203 353.254,-197 353.254,-197 353.254,-144 353.254,-144 353.254,-138 359.254,-132 365.254,-132"/>
<text text-anchor="middle" x="390.9838" y="-195.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#5b7285">testing</text>
</g>
<!-- c_arousal -->
<g id="node1" class="node">
<title>c_arousal</title>
<path fill="#e4f1f1" stroke="#1e7b7b" stroke-width="1.1" d="M100.212,-178.402C100.212,-178.402 35.8636,-178.402 35.8636,-178.402 29.8636,-178.402 23.8636,-172.402 23.8636,-166.402 23.8636,-166.402 23.8636,-149.598 23.8636,-149.598 23.8636,-143.598 29.8636,-137.598 35.8636,-137.598 35.8636,-137.598 100.212,-137.598 100.212,-137.598 106.212,-137.598 112.212,-143.598 112.212,-149.598 112.212,-149.598 112.212,-166.402 112.212,-166.402 112.212,-172.402 106.212,-178.402 100.212,-178.402"/>
<text text-anchor="middle" x="68.0378" y="-161.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">Physiological</text>
<text text-anchor="middle" x="68.0378" y="-148.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">arousal</text>
</g>
<!-- prop_p1 -->
<g id="node4" class="node">
<title>prop_p1</title>
<path fill="#fbf1dc" stroke="#9c6b14" stroke-width="1.1" d="M211.1692,-180.402C211.1692,-180.402 164.0444,-180.402 164.0444,-180.402 158.0444,-180.402 152.0444,-174.402 152.0444,-168.402 152.0444,-168.402 152.0444,-151.598 152.0444,-151.598 152.0444,-145.598 158.0444,-139.598 164.0444,-139.598 164.0444,-139.598 211.1692,-139.598 211.1692,-139.598 217.1692,-139.598 223.1692,-145.598 223.1692,-151.598 223.1692,-151.598 223.1692,-168.402 223.1692,-168.402 223.1692,-174.402 217.1692,-180.402 211.1692,-180.402"/>
<text text-anchor="middle" x="187.6068" y="-163.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">p1</text>
<text text-anchor="middle" x="187.6068" y="-150.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">increases</text>
</g>
<!-- c_arousal&#45;&gt;prop_p1 -->
<g id="edge1" class="edge">
<title>c_arousal&#45;&gt;prop_p1</title>
<path fill="none" stroke="#7b909f" d="M112.2212,-158.739C122.8153,-158.9162 134.1121,-159.1052 144.6496,-159.2815"/>
<polygon fill="#7b909f" stroke="#7b909f" points="144.7655,-161.7337 151.8056,-159.4012 144.8476,-156.8343 144.7655,-161.7337"/>
</g>
<!-- c_perceived_threat -->
<g id="node2" class="node">
<title>c_perceived_threat</title>
<path fill="#e4f1f1" stroke="#1e7b7b" stroke-width="1.1" d="M108.1134,-116C108.1134,-116 27.9622,-116 27.9622,-116 21.9622,-116 15.9622,-110 15.9622,-104 15.9622,-104 15.9622,-92 15.9622,-92 15.9622,-86 21.9622,-80 27.9622,-80 27.9622,-80 108.1134,-80 108.1134,-80 114.1134,-80 120.1134,-86 120.1134,-92 120.1134,-92 120.1134,-104 120.1134,-104 120.1134,-110 114.1134,-116 108.1134,-116"/>
<text text-anchor="middle" x="68.0378" y="-94.7" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">Perceived threat</text>
</g>
<!-- prop_p2 -->
<g id="node5" class="node">
<title>prop_p2</title>
<path fill="#fbf1dc" stroke="#9c6b14" stroke-width="1.1" d="M211.1692,-56.402C211.1692,-56.402 164.0444,-56.402 164.0444,-56.402 158.0444,-56.402 152.0444,-50.402 152.0444,-44.402 152.0444,-44.402 152.0444,-27.598 152.0444,-27.598 152.0444,-21.598 158.0444,-15.598 164.0444,-15.598 164.0444,-15.598 211.1692,-15.598 211.1692,-15.598 217.1692,-15.598 223.1692,-21.598 223.1692,-27.598 223.1692,-27.598 223.1692,-44.402 223.1692,-44.402 223.1692,-50.402 217.1692,-56.402 211.1692,-56.402"/>
<text text-anchor="middle" x="187.6068" y="-39.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">p2</text>
<text text-anchor="middle" x="187.6068" y="-26.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">increases</text>
</g>
<!-- c_perceived_threat&#45;&gt;prop_p2 -->
<g id="edge2" class="edge">
<title>c_perceived_threat&#45;&gt;prop_p2</title>
<path fill="none" stroke="#7b909f" d="M106.3104,-79.9105C113.5747,-76.365 121.0868,-72.6213 128.0756,-69 133.7774,-66.0455 139.7411,-62.8584 145.5986,-59.6704"/>
<polygon fill="#7b909f" stroke="#7b909f" points="146.9327,-61.7331 151.8954,-56.2218 144.579,-57.4354 146.9327,-61.7331"/>
</g>
<!-- prop_p3 -->
<g id="node6" class="node">
<title>prop_p3</title>
<path fill="#fbf1dc" stroke="#9c6b14" stroke-width="1.1" d="M204.9517,-118.402C204.9517,-118.402 170.2619,-118.402 170.2619,-118.402 164.2619,-118.402 158.2619,-112.402 158.2619,-106.402 158.2619,-106.402 158.2619,-89.598 158.2619,-89.598 158.2619,-83.598 164.2619,-77.598 170.2619,-77.598 170.2619,-77.598 204.9517,-77.598 204.9517,-77.598 210.9517,-77.598 216.9517,-83.598 216.9517,-89.598 216.9517,-89.598 216.9517,-106.402 216.9517,-106.402 216.9517,-112.402 210.9517,-118.402 204.9517,-118.402"/>
<text text-anchor="middle" x="187.6068" y="-101.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">p3</text>
<text text-anchor="middle" x="187.6068" y="-88.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">causes</text>
</g>
<!-- c_perceived_threat&#45;&gt;prop_p3 -->
<g id="edge3" class="edge">
<title>c_perceived_threat&#45;&gt;prop_p3</title>
<path fill="none" stroke="#7b909f" d="M120.1347,-98C130.4654,-98 141.1076,-98 150.7995,-98"/>
<polygon fill="#7b909f" stroke="#7b909f" points="151.0049,-100.4501 158.0048,-98 151.0048,-95.5501 151.0049,-100.4501"/>
</g>
<!-- c_avoidance -->
<g id="node3" class="node">
<title>c_avoidance</title>
<path fill="#e4f1f1" stroke="#1e7b7b" stroke-width="1.1" d="M93.8899,-58.402C93.8899,-58.402 42.1857,-58.402 42.1857,-58.402 36.1857,-58.402 30.1857,-52.402 30.1857,-46.402 30.1857,-46.402 30.1857,-29.598 30.1857,-29.598 30.1857,-23.598 36.1857,-17.598 42.1857,-17.598 42.1857,-17.598 93.8899,-17.598 93.8899,-17.598 99.8899,-17.598 105.8899,-23.598 105.8899,-29.598 105.8899,-29.598 105.8899,-46.402 105.8899,-46.402 105.8899,-52.402 99.8899,-58.402 93.8899,-58.402"/>
<text text-anchor="middle" x="68.0378" y="-41.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">Avoidance</text>
<text text-anchor="middle" x="68.0378" y="-28.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">behaviour</text>
</g>
<!-- pred_pred1 -->
<g id="node7" class="node">
<title>pred_pred1</title>
<path fill="#e7edf5" stroke="#33567a" stroke-width="1.1" d="M307.196,-180.402C307.196,-180.402 277.196,-180.402 277.196,-180.402 271.196,-180.402 265.196,-174.402 265.196,-168.402 265.196,-168.402 265.196,-151.598 265.196,-151.598 265.196,-145.598 271.196,-139.598 277.196,-139.598 277.196,-139.598 307.196,-139.598 307.196,-139.598 313.196,-139.598 319.196,-145.598 319.196,-151.598 319.196,-151.598 319.196,-168.402 319.196,-168.402 319.196,-174.402 313.196,-180.402 307.196,-180.402"/>
<text text-anchor="middle" x="292.196" y="-163.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">pred1</text>
<text text-anchor="middle" x="292.196" y="-150.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">point</text>
</g>
<!-- prop_p1&#45;&gt;pred_pred1 -->
<g id="edge4" class="edge">
<title>prop_p1&#45;&gt;pred_pred1</title>
<path fill="none" stroke="#7b909f" d="M223.3079,-160C234.473,-160 246.7639,-160 257.8347,-160"/>
<polygon fill="#7b909f" stroke="#7b909f" points="257.9096,-162.4501 264.9095,-160 257.9095,-157.5501 257.9096,-162.4501"/>
</g>
<!-- pred_pred2 -->
<g id="node8" class="node">
<title>pred_pred2</title>
<path fill="#e7edf5" stroke="#33567a" stroke-width="1.1" d="M310.143,-118.402C310.143,-118.402 274.249,-118.402 274.249,-118.402 268.249,-118.402 262.249,-112.402 262.249,-106.402 262.249,-106.402 262.249,-89.598 262.249,-89.598 262.249,-83.598 268.249,-77.598 274.249,-77.598 274.249,-77.598 310.143,-77.598 310.143,-77.598 316.143,-77.598 322.143,-83.598 322.143,-89.598 322.143,-89.598 322.143,-106.402 322.143,-106.402 322.143,-112.402 316.143,-118.402 310.143,-118.402"/>
<text text-anchor="middle" x="292.196" y="-101.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">pred2</text>
<text text-anchor="middle" x="292.196" y="-88.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">interval</text>
</g>
<!-- prop_p2&#45;&gt;pred_pred2 -->
<g id="edge6" class="edge">
<title>prop_p2&#45;&gt;pred_pred2</title>
<path fill="none" stroke="#7b909f" d="M221.8532,-56.3011C232.9119,-62.8567 245.1979,-70.1398 256.3678,-76.7612"/>
<polygon fill="#7b909f" stroke="#7b909f" points="255.1727,-78.9009 262.4436,-80.3629 257.6714,-74.6858 255.1727,-78.9009"/>
</g>
<!-- pred_pred3 -->
<g id="node9" class="node">
<title>pred_pred3</title>
<path fill="#e7edf5" stroke="#33567a" stroke-width="1.1" d="M317.3121,-56.402C317.3121,-56.402 267.0799,-56.402 267.0799,-56.402 261.0799,-56.402 255.0799,-50.402 255.0799,-44.402 255.0799,-44.402 255.0799,-27.598 255.0799,-27.598 255.0799,-21.598 261.0799,-15.598 267.0799,-15.598 267.0799,-15.598 317.3121,-15.598 317.3121,-15.598 323.3121,-15.598 329.3121,-21.598 329.3121,-27.598 329.3121,-27.598 329.3121,-44.402 329.3121,-44.402 329.3121,-50.402 323.3121,-56.402 317.3121,-56.402"/>
<text text-anchor="middle" x="292.196" y="-39.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">pred3</text>
<text text-anchor="middle" x="292.196" y="-26.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">directional</text>
</g>
<!-- prop_p2&#45;&gt;pred_pred3 -->
<g id="edge7" class="edge">
<title>prop_p2&#45;&gt;pred_pred3</title>
<path fill="none" stroke="#7b909f" d="M223.3079,-36C231.1008,-36 239.4422,-36 247.5343,-36"/>
<polygon fill="#7b909f" stroke="#7b909f" points="247.873,-38.4501 254.8729,-36 247.8729,-33.5501 247.873,-38.4501"/>
</g>
<!-- prop_p3&#45;&gt;pred_pred1 -->
<g id="edge5" class="edge">
<title>prop_p3&#45;&gt;pred_pred1</title>
<path fill="none" stroke="#7b909f" d="M217.0191,-115.4354C230.1179,-123.2004 245.6026,-132.3796 259.1041,-140.3833"/>
<polygon fill="#7b909f" stroke="#7b909f" points="257.8814,-142.5065 265.1522,-143.9686 260.3801,-138.2915 257.8814,-142.5065"/>
</g>
<!-- outcome_pred1 -->
<g id="node10" class="node">
<title>outcome_pred1</title>
<path fill="#e5f2e7" stroke="#3e7a46" stroke-width="1.1" d="M408.9452,-180.402C408.9452,-180.402 373.0224,-180.402 373.0224,-180.402 367.0224,-180.402 361.0224,-174.402 361.0224,-168.402 361.0224,-168.402 361.0224,-151.598 361.0224,-151.598 361.0224,-145.598 367.0224,-139.598 373.0224,-139.598 373.0224,-139.598 408.9452,-139.598 408.9452,-139.598 414.9452,-139.598 420.9452,-145.598 420.9452,-151.598 420.9452,-151.598 420.9452,-168.402 420.9452,-168.402 420.9452,-174.402 414.9452,-180.402 408.9452,-180.402"/>
<text text-anchor="middle" x="390.9838" y="-163.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">pred1</text>
<text text-anchor="middle" x="390.9838" y="-150.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">passed</text>
</g>
<!-- pred_pred1&#45;&gt;outcome_pred1 -->
<g id="edge8" class="edge">
<title>pred_pred1&#45;&gt;outcome_pred1</title>
<path fill="none" stroke="#7b909f" d="M319.4517,-160C330.0395,-160 342.3383,-160 353.721,-160"/>
<polygon fill="#7b909f" stroke="#7b909f" points="354.0415,-162.4501 361.0415,-160 354.0415,-157.5501 354.0415,-162.4501"/>
</g>
</g>
</svg></div>

The `context` view places the theory among the scope conditions under which it is
claimed to hold and the registered rivals it is meant to outpredict.

```python
print(t.diagram("context"))
```

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
  "alt_cognitive" [style="rounded,filled,dashed", label="Cognitive model of\npanic", fillcolor="#F1F1F1", color="#8A8A8A"];
  "theory" -> "alt_cognitive" [style=dashed, label="contrasts with"];
  "alt_biological" [style="rounded,filled,dashed", label="Biological model\nof panic", fillcolor="#F1F1F1", color="#8A8A8A"];
  "theory" -> "alt_biological" [style=dashed, label="contrasts with"];
}
```

<div class="tf-figure tf-diagram"><svg width="577pt" height="313pt"
 viewBox="0.00 0.00 576.84 313.20" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g id="graph0" class="graph" transform="scale(1 1) rotate(0) translate(14.4 298.8)">
<title>context</title>
<!-- theory -->
<g id="node1" class="node">
<title>theory</title>
<ellipse fill="#12283a" stroke="#12283a" stroke-width="1.1" cx="261.9354" cy="-144.2" rx="77.8175" ry="28.6344"/>
<text text-anchor="middle" x="261.9354" y="-147.5" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#ffffff">Network theory of</text>
<text text-anchor="middle" x="261.9354" y="-134.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#ffffff">panic disorder</text>
</g>
<!-- c_arousal -->
<g id="node2" class="node">
<title>c_arousal</title>
<path fill="#e4f1f1" stroke="#1e7b7b" stroke-width="1.1" d="M522.6734,-284.602C522.6734,-284.602 458.325,-284.602 458.325,-284.602 452.325,-284.602 446.325,-278.602 446.325,-272.602 446.325,-272.602 446.325,-255.798 446.325,-255.798 446.325,-249.798 452.325,-243.798 458.325,-243.798 458.325,-243.798 522.6734,-243.798 522.6734,-243.798 528.6734,-243.798 534.6734,-249.798 534.6734,-255.798 534.6734,-255.798 534.6734,-272.602 534.6734,-272.602 534.6734,-278.602 528.6734,-284.602 522.6734,-284.602"/>
<text text-anchor="middle" x="490.4992" y="-267.5" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">Physiological</text>
<text text-anchor="middle" x="490.4992" y="-254.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">arousal</text>
</g>
<!-- theory&#45;&gt;c_arousal -->
<g id="edge1" class="edge">
<title>theory&#45;&gt;c_arousal</title>
<path fill="none" stroke="#7b909f" d="M306.3142,-167.9439C321.9508,-176.2794 339.6613,-185.6859 355.844,-194.2 385.4007,-209.7505 418.7011,-227.0634 444.7914,-240.5808"/>
<polygon fill="#7b909f" stroke="#7b909f" points="443.92,-242.8885 451.2625,-243.9323 446.1735,-238.5375 443.92,-242.8885"/>
</g>
<!-- c_perceived_threat -->
<g id="node3" class="node">
<title>c_perceived_threat</title>
<path fill="#e4f1f1" stroke="#1e7b7b" stroke-width="1.1" d="M530.5748,-222.2C530.5748,-222.2 450.4236,-222.2 450.4236,-222.2 444.4236,-222.2 438.4236,-216.2 438.4236,-210.2 438.4236,-210.2 438.4236,-198.2 438.4236,-198.2 438.4236,-192.2 444.4236,-186.2 450.4236,-186.2 450.4236,-186.2 530.5748,-186.2 530.5748,-186.2 536.5748,-186.2 542.5748,-192.2 542.5748,-198.2 542.5748,-198.2 542.5748,-210.2 542.5748,-210.2 542.5748,-216.2 536.5748,-222.2 530.5748,-222.2"/>
<text text-anchor="middle" x="490.4992" y="-200.9" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">Perceived threat</text>
</g>
<!-- theory&#45;&gt;c_perceived_threat -->
<g id="edge2" class="edge">
<title>theory&#45;&gt;c_perceived_threat</title>
<path fill="none" stroke="#7b909f" d="M325.2996,-160.8337C358.4782,-169.5433 398.8542,-180.1424 431.3843,-188.6818"/>
<polygon fill="#7b909f" stroke="#7b909f" points="430.8087,-191.0637 438.2014,-190.4714 432.0529,-186.3243 430.8087,-191.0637"/>
</g>
<!-- c_avoidance -->
<g id="node4" class="node">
<title>c_avoidance</title>
<path fill="#e4f1f1" stroke="#1e7b7b" stroke-width="1.1" d="M516.3513,-164.602C516.3513,-164.602 464.6471,-164.602 464.6471,-164.602 458.6471,-164.602 452.6471,-158.602 452.6471,-152.602 452.6471,-152.602 452.6471,-135.798 452.6471,-135.798 452.6471,-129.798 458.6471,-123.798 464.6471,-123.798 464.6471,-123.798 516.3513,-123.798 516.3513,-123.798 522.3513,-123.798 528.3513,-129.798 528.3513,-135.798 528.3513,-135.798 528.3513,-152.602 528.3513,-152.602 528.3513,-158.602 522.3513,-164.602 516.3513,-164.602"/>
<text text-anchor="middle" x="490.4992" y="-147.5" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">Avoidance</text>
<text text-anchor="middle" x="490.4992" y="-134.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">behaviour</text>
</g>
<!-- theory&#45;&gt;c_avoidance -->
<g id="edge3" class="edge">
<title>theory&#45;&gt;c_avoidance</title>
<path fill="none" stroke="#7b909f" d="M339.9548,-144.2C375.1538,-144.2 415.4729,-144.2 445.5212,-144.2"/>
<polygon fill="#7b909f" stroke="#7b909f" points="445.5421,-146.6501 452.5421,-144.2 445.5421,-141.7501 445.5421,-146.6501"/>
</g>
<!-- alt_cognitive -->
<g id="node8" class="node">
<title>alt_cognitive</title>
<path fill="#f1f1f1" stroke="#8a8a8a" stroke-width="1.1" stroke-dasharray="5,2" d="M536.0715,-102.602C536.0715,-102.602 444.9269,-102.602 444.9269,-102.602 438.9269,-102.602 432.9269,-96.602 432.9269,-90.602 432.9269,-90.602 432.9269,-73.798 432.9269,-73.798 432.9269,-67.798 438.9269,-61.798 444.9269,-61.798 444.9269,-61.798 536.0715,-61.798 536.0715,-61.798 542.0715,-61.798 548.0715,-67.798 548.0715,-73.798 548.0715,-73.798 548.0715,-90.602 548.0715,-90.602 548.0715,-96.602 542.0715,-102.602 536.0715,-102.602"/>
<text text-anchor="middle" x="490.4992" y="-85.5" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">Cognitive model of</text>
<text text-anchor="middle" x="490.4992" y="-72.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">panic</text>
</g>
<!-- theory&#45;&gt;alt_cognitive -->
<g id="edge7" class="edge">
<title>theory&#45;&gt;alt_cognitive</title>
<path fill="none" stroke="#7b909f" stroke-dasharray="5,2" d="M324.6938,-127.1762C356.0241,-118.6776 393.8886,-108.4065 425.5192,-99.8264"/>
<polygon fill="#7b909f" stroke="#7b909f" points="426.469,-102.1074 432.5834,-97.9102 425.1861,-97.3783 426.469,-102.1074"/>
<text text-anchor="middle" x="386.4035" y="-119.2" font-family="Helvetica,sans-Serif" font-size="10.00" fill="#0f6e6e">contrasts with</text>
</g>
<!-- alt_biological -->
<g id="node9" class="node">
<title>alt_biological</title>
<path fill="#f1f1f1" stroke="#8a8a8a" stroke-width="1.1" stroke-dasharray="5,2" d="M530.5627,-40.602C530.5627,-40.602 450.4357,-40.602 450.4357,-40.602 444.4357,-40.602 438.4357,-34.602 438.4357,-28.602 438.4357,-28.602 438.4357,-11.798 438.4357,-11.798 438.4357,-5.798 444.4357,.202 450.4357,.202 450.4357,.202 530.5627,.202 530.5627,.202 536.5627,.202 542.5627,-5.798 542.5627,-11.798 542.5627,-11.798 542.5627,-28.602 542.5627,-28.602 542.5627,-34.602 536.5627,-40.602 530.5627,-40.602"/>
<text text-anchor="middle" x="490.4992" y="-23.5" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">Biological model</text>
<text text-anchor="middle" x="490.4992" y="-10.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">of panic</text>
</g>
<!-- theory&#45;&gt;alt_biological -->
<g id="edge8" class="edge">
<title>theory&#45;&gt;alt_biological</title>
<path fill="none" stroke="#7b909f" stroke-dasharray="5,2" d="M299.7366,-119.107C316.6412,-108.2375 336.9746,-95.6395 355.844,-85.2 382.6375,-70.3765 413.3288,-55.4131 438.6371,-43.5861"/>
<polygon fill="#7b909f" stroke="#7b909f" points="439.9728,-45.6669 445.2863,-40.4929 437.906,-41.2241 439.9728,-45.6669"/>
<text text-anchor="middle" x="386.4035" y="-88.2" font-family="Helvetica,sans-Serif" font-size="10.00" fill="#0f6e6e">contrasts with</text>
</g>
<!-- scope1 -->
<g id="node5" class="node">
<title>scope1</title>
<text text-anchor="middle" x="49.8989" y="-200.9" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">adults</text>
</g>
<!-- scope1&#45;&gt;theory -->
<g id="edge4" class="edge">
<title>scope1&#45;&gt;theory</title>
<path fill="none" stroke="#7b909f" stroke-dasharray="1,5" d="M77.1848,-196.4789C106.3674,-188.2211 153.7831,-174.8039 193.2714,-163.6298"/>
<polygon fill="#7b909f" stroke="#7b909f" points="193.9717,-165.978 200.0401,-161.7145 192.6374,-161.2631 193.9717,-165.978"/>
<text text-anchor="middle" x="141.9122" y="-187.2" font-family="Helvetica,sans-Serif" font-size="10.00" fill="#0f6e6e">holds within</text>
</g>
<!-- scope2 -->
<g id="node6" class="node">
<title>scope2</title>
<text text-anchor="middle" x="49.8989" y="-147.5" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">non&#45;clinical</text>
<text text-anchor="middle" x="49.8989" y="-134.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">baseline</text>
</g>
<!-- scope2&#45;&gt;theory -->
<g id="edge5" class="edge">
<title>scope2&#45;&gt;theory</title>
<path fill="none" stroke="#7b909f" stroke-dasharray="1,5" d="M89.7813,-144.2C114.3257,-144.2 146.7443,-144.2 176.8245,-144.2"/>
<polygon fill="#7b909f" stroke="#7b909f" points="177.0087,-146.6501 184.0086,-144.2 177.0086,-141.7501 177.0087,-146.6501"/>
<text text-anchor="middle" x="141.9122" y="-147.2" font-family="Helvetica,sans-Serif" font-size="10.00" fill="#0f6e6e">holds within</text>
</g>
<!-- scope3 -->
<g id="node7" class="node">
<title>scope3</title>
<text text-anchor="middle" x="49.8989" y="-85.5" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">no beta&#45;blocker</text>
<text text-anchor="middle" x="49.8989" y="-72.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">medication</text>
</g>
<!-- scope3&#45;&gt;theory -->
<g id="edge6" class="edge">
<title>scope3&#45;&gt;theory</title>
<path fill="none" stroke="#7b909f" stroke-dasharray="1,5" d="M99.88,-96.8146C127.9954,-105.0356 163.4892,-115.4141 194.0875,-124.3611"/>
<polygon fill="#7b909f" stroke="#7b909f" points="193.5343,-126.7519 200.9406,-126.365 194.9096,-122.0488 193.5343,-126.7519"/>
<text text-anchor="middle" x="141.9122" y="-117.2" font-family="Helvetica,sans-Serif" font-size="10.00" fill="#0f6e6e">holds within</text>
</g>
</g>
</svg></div>

The `pipeline` view links each prediction to its recorded test outcome, so
predictions still awaiting a test are visible as loose ends.

```python
print(t.diagram("pipeline"))
```

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
```

<div class="tf-figure tf-diagram"><svg width="194pt" height="193pt"
 viewBox="0.00 0.00 194.38 193.20" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g id="graph0" class="graph" transform="scale(1 1) rotate(0) translate(14.4 178.8)">
<title>pipeline</title>
<!-- pred1 -->
<g id="node1" class="node">
<title>pred1</title>
<path fill="#e7edf5" stroke="#33567a" stroke-width="1.1" d="M52.058,-40.602C52.058,-40.602 22.058,-40.602 22.058,-40.602 16.058,-40.602 10.058,-34.602 10.058,-28.602 10.058,-28.602 10.058,-11.798 10.058,-11.798 10.058,-5.798 16.058,.202 22.058,.202 22.058,.202 52.058,.202 52.058,.202 58.058,.202 64.058,-5.798 64.058,-11.798 64.058,-11.798 64.058,-28.602 64.058,-28.602 64.058,-34.602 58.058,-40.602 52.058,-40.602"/>
<text text-anchor="middle" x="37.058" y="-23.5" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">pred1</text>
<text text-anchor="middle" x="37.058" y="-10.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">point</text>
</g>
<!-- result_pred1 -->
<g id="node4" class="node">
<title>result_pred1</title>
<path fill="#e5f2e7" stroke="#3e7a46" stroke-width="1.1" d="M153.8072,-38.2C153.8072,-38.2 117.8844,-38.2 117.8844,-38.2 111.8844,-38.2 105.8844,-32.2 105.8844,-26.2 105.8844,-26.2 105.8844,-14.2 105.8844,-14.2 105.8844,-8.2 111.8844,-2.2 117.8844,-2.2 117.8844,-2.2 153.8072,-2.2 153.8072,-2.2 159.8072,-2.2 165.8072,-8.2 165.8072,-14.2 165.8072,-14.2 165.8072,-26.2 165.8072,-26.2 165.8072,-32.2 159.8072,-38.2 153.8072,-38.2"/>
<text text-anchor="middle" x="135.8458" y="-16.9" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">passed</text>
</g>
<!-- pred1&#45;&gt;result_pred1 -->
<g id="edge1" class="edge">
<title>pred1&#45;&gt;result_pred1</title>
<path fill="none" stroke="#7b909f" d="M64.3137,-20.2C74.9015,-20.2 87.2003,-20.2 98.583,-20.2"/>
<polygon fill="#7b909f" stroke="#7b909f" points="98.9035,-22.6501 105.9035,-20.2 98.9035,-17.7501 98.9035,-22.6501"/>
</g>
<!-- pred2 -->
<g id="node2" class="node">
<title>pred2</title>
<path fill="#e7edf5" stroke="#33567a" stroke-width="1.1" d="M55.005,-102.602C55.005,-102.602 19.111,-102.602 19.111,-102.602 13.111,-102.602 7.111,-96.602 7.111,-90.602 7.111,-90.602 7.111,-73.798 7.111,-73.798 7.111,-67.798 13.111,-61.798 19.111,-61.798 19.111,-61.798 55.005,-61.798 55.005,-61.798 61.005,-61.798 67.005,-67.798 67.005,-73.798 67.005,-73.798 67.005,-90.602 67.005,-90.602 67.005,-96.602 61.005,-102.602 55.005,-102.602"/>
<text text-anchor="middle" x="37.058" y="-85.5" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">pred2</text>
<text text-anchor="middle" x="37.058" y="-72.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">interval</text>
</g>
<!-- pred3 -->
<g id="node3" class="node">
<title>pred3</title>
<path fill="#e7edf5" stroke="#33567a" stroke-width="1.1" d="M62.1741,-164.602C62.1741,-164.602 11.9419,-164.602 11.9419,-164.602 5.9419,-164.602 -.0581,-158.602 -.0581,-152.602 -.0581,-152.602 -.0581,-135.798 -.0581,-135.798 -.0581,-129.798 5.9419,-123.798 11.9419,-123.798 11.9419,-123.798 62.1741,-123.798 62.1741,-123.798 68.1741,-123.798 74.1741,-129.798 74.1741,-135.798 74.1741,-135.798 74.1741,-152.602 74.1741,-152.602 74.1741,-158.602 68.1741,-164.602 62.1741,-164.602"/>
<text text-anchor="middle" x="37.058" y="-147.5" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">pred3</text>
<text text-anchor="middle" x="37.058" y="-134.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">directional</text>
</g>
</g>
</svg></div>

The `provenance` view draws the build log as a digraph, so the record of how
the theory reached its current state travels with the object itself.

```python
print(t.diagram("provenance"))
```

```
digraph provenance {
  graph [rankdir=TB, bgcolor="transparent", fontname="Helvetica", fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];
  node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", color="#33567A", fillcolor="#F2F6F9", fontcolor="#12283A", penwidth=1.1, margin="0.16,0.1"];
  edge [fontname="Helvetica", fontsize=10, color="#7B909F", fontcolor="#0F6E6E", arrowsize=0.7];
  "n1" [label="tf_construct\nRegistered three\nconstructs."];
  "n2" [label="tf_proposition\nLinked constructs into a\nfeedback network."];
  "n3" [label="tf_predict\nDerived three predictions\nfrom the propositions."];
  "n1" -> "n2";
  "n2" -> "n3";
}
```

<div class="tf-figure tf-diagram"><svg width="175pt" height="254pt"
 viewBox="0.00 0.00 175.04 253.60" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g id="graph0" class="graph" transform="scale(1 1) rotate(0) translate(14.4 239.2)">
<title>provenance</title>
<!-- n1 -->
<g id="node1" class="node">
<title>n1</title>
<path fill="#f2f6f9" stroke="#33567a" stroke-width="1.1" d="M113.9163,-224.6015C113.9163,-224.6015 32.3245,-224.6015 32.3245,-224.6015 26.3245,-224.6015 20.3245,-218.6015 20.3245,-212.6015 20.3245,-212.6015 20.3245,-183.3985 20.3245,-183.3985 20.3245,-177.3985 26.3245,-171.3985 32.3245,-171.3985 32.3245,-171.3985 113.9163,-171.3985 113.9163,-171.3985 119.9163,-171.3985 125.9163,-177.3985 125.9163,-183.3985 125.9163,-183.3985 125.9163,-212.6015 125.9163,-212.6015 125.9163,-218.6015 119.9163,-224.6015 113.9163,-224.6015"/>
<text text-anchor="middle" x="73.1204" y="-207.9" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">tf_construct</text>
<text text-anchor="middle" x="73.1204" y="-194.7" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">Registered three</text>
<text text-anchor="middle" x="73.1204" y="-181.5" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">constructs.</text>
</g>
<!-- n2 -->
<g id="node2" class="node">
<title>n2</title>
<path fill="#f2f6f9" stroke="#33567a" stroke-width="1.1" d="M130.6553,-139.0015C130.6553,-139.0015 15.5855,-139.0015 15.5855,-139.0015 9.5855,-139.0015 3.5855,-133.0015 3.5855,-127.0015 3.5855,-127.0015 3.5855,-97.7985 3.5855,-97.7985 3.5855,-91.7985 9.5855,-85.7985 15.5855,-85.7985 15.5855,-85.7985 130.6553,-85.7985 130.6553,-85.7985 136.6553,-85.7985 142.6553,-91.7985 142.6553,-97.7985 142.6553,-97.7985 142.6553,-127.0015 142.6553,-127.0015 142.6553,-133.0015 136.6553,-139.0015 130.6553,-139.0015"/>
<text text-anchor="middle" x="73.1204" y="-122.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">tf_proposition</text>
<text text-anchor="middle" x="73.1204" y="-109.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">Linked constructs into a</text>
<text text-anchor="middle" x="73.1204" y="-95.9" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">feedback network.</text>
</g>
<!-- n1&#45;&gt;n2 -->
<g id="edge1" class="edge">
<title>n1&#45;&gt;n2</title>
<path fill="none" stroke="#7b909f" d="M73.1204,-171.3849C73.1204,-163.4894 73.1204,-154.7322 73.1204,-146.4342"/>
<polygon fill="#7b909f" stroke="#7b909f" points="75.5705,-146.2935 73.1204,-139.2935 70.6705,-146.2935 75.5705,-146.2935"/>
</g>
<!-- n3 -->
<g id="node3" class="node">
<title>n3</title>
<path fill="#f2f6f9" stroke="#33567a" stroke-width="1.1" d="M134.3614,-53.4015C134.3614,-53.4015 11.8794,-53.4015 11.8794,-53.4015 5.8794,-53.4015 -.1206,-47.4015 -.1206,-41.4015 -.1206,-41.4015 -.1206,-12.1985 -.1206,-12.1985 -.1206,-6.1985 5.8794,-.1985 11.8794,-.1985 11.8794,-.1985 134.3614,-.1985 134.3614,-.1985 140.3614,-.1985 146.3614,-6.1985 146.3614,-12.1985 146.3614,-12.1985 146.3614,-41.4015 146.3614,-41.4015 146.3614,-47.4015 140.3614,-53.4015 134.3614,-53.4015"/>
<text text-anchor="middle" x="73.1204" y="-36.7" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">tf_predict</text>
<text text-anchor="middle" x="73.1204" y="-23.5" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">Derived three predictions</text>
<text text-anchor="middle" x="73.1204" y="-10.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">from the propositions.</text>
</g>
<!-- n2&#45;&gt;n3 -->
<g id="edge2" class="edge">
<title>n2&#45;&gt;n3</title>
<path fill="none" stroke="#7b909f" d="M73.1204,-85.7849C73.1204,-77.8894 73.1204,-69.1322 73.1204,-60.8342"/>
<polygon fill="#7b909f" stroke="#7b909f" points="75.5705,-60.6935 73.1204,-53.6935 70.6705,-60.6935 75.5705,-60.6935"/>
</g>
</g>
</svg></div>

The `venn` view shows where the first three constructs share boundary conditions.

```python
print(t.diagram("venn"))      # construct scope overlap
print(t.diagram("rigour"))    # the rigour checklist as a status grid
print(t.diagram("severity"))  # per-prediction severity bars
```

<div class="tf-figure"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 380 300" font-family="sans-serif" font-size="13">
  <text x="190" y="24" text-anchor="middle" font-size="15">Construct scope overlap</text>
  <circle cx="150" cy="135" r="78" fill="#4e79a7" fill-opacity="0.35" stroke="#33567a"/>
  <circle cx="230" cy="135" r="78" fill="#4e79a7" fill-opacity="0.35" stroke="#33567a"/>
  <circle cx="190" cy="195" r="78" fill="#4e79a7" fill-opacity="0.35" stroke="#33567a"/>
  <text x="110" y="45" text-anchor="middle">Physiological arousal</text>
  <text x="270" y="45" text-anchor="middle">Perceived threat</text>
  <text x="190" y="290" text-anchor="middle">Avoidance behaviour</text>
  <text x="120" y="115" text-anchor="middle" font-weight="bold">1</text>
  <text x="260" y="115" text-anchor="middle" font-weight="bold">0</text>
  <text x="190" y="230" text-anchor="middle" font-weight="bold">0</text>
  <text x="190" y="105" text-anchor="middle" font-weight="bold">0</text>
  <text x="145" y="180" text-anchor="middle" font-weight="bold">0</text>
  <text x="235" y="180" text-anchor="middle" font-weight="bold">0</text>
  <text x="190" y="160" text-anchor="middle" font-weight="bold">1</text>
</svg></div>

The `rigour` view draws the checklist as a status grid, colouring each item by its
result and reporting the aggregate score and the gate.

<div class="tf-figure"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 460 360" font-family="sans-serif" font-size="13">
  <text x="20" y="28" font-size="15">Rigour checklist</text>
  <text x="20" y="46">aggregate score 84.8, gate pass</text>
  <rect x="20" y="60" width="16" height="16" rx="3" fill="#4caf50"/>
  <text x="44" y="72">falsifiability</text>
  <text x="320" y="72">pass</text>
  <rect x="20" y="84" width="16" height="16" rx="3" fill="#4caf50"/>
  <text x="44" y="96">precision</text>
  <text x="320" y="96">pass</text>
  <rect x="20" y="108" width="16" height="16" rx="3" fill="#4caf50"/>
  <text x="44" y="120">risk_severity</text>
  <text x="320" y="120">pass</text>
  <rect x="20" y="132" width="16" height="16" rx="3" fill="#4caf50"/>
  <text x="44" y="144">parsimony</text>
  <text x="320" y="144">pass</text>
  <rect x="20" y="156" width="16" height="16" rx="3" fill="#4caf50"/>
  <text x="44" y="168">non_redundancy</text>
  <text x="320" y="168">pass</text>
  <rect x="20" y="180" width="16" height="16" rx="3" fill="#4caf50"/>
  <text x="44" y="192">construct_clarity</text>
  <text x="320" y="192">pass</text>
  <rect x="20" y="204" width="16" height="16" rx="3" fill="#4caf50"/>
  <text x="44" y="216">scope</text>
  <text x="320" y="216">pass</text>
  <rect x="20" y="228" width="16" height="16" rx="3" fill="#4caf50"/>
  <text x="44" y="240">logical_why</text>
  <text x="320" y="240">pass</text>
  <rect x="20" y="252" width="16" height="16" rx="3" fill="#4caf50"/>
  <text x="44" y="264">causal_testability</text>
  <text x="320" y="264">pass</text>
  <rect x="20" y="276" width="16" height="16" rx="3" fill="#4caf50"/>
  <text x="44" y="288">diagnosticity</text>
  <text x="320" y="288">pass</text>
  <rect x="20" y="300" width="16" height="16" rx="3" fill="#4caf50"/>
  <text x="44" y="312">formalisation</text>
  <text x="320" y="312">pass</text>
  <rect x="20" y="324" width="16" height="16" rx="3" fill="#4caf50"/>
  <text x="44" y="336">derivation_chain</text>
  <text x="320" y="336">pass</text>
</svg></div>

The `severity` view draws one bar per prediction, scaled by its computed severity,
so the riskier tests stand out at a glance.

<div class="tf-figure"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 132" font-family="sans-serif" font-size="13">
  <text x="20" y="26" font-size="15">Prediction severity</text>
  <text x="20" y="52">pred1</text>
  <rect x="70" y="40" width="200" height="16" rx="2" fill="#4e79a7"/>
  <text x="275" y="52">1.000</text>
  <text x="20" y="80">pred2</text>
  <rect x="70" y="68" width="140" height="16" rx="2" fill="#4e79a7"/>
  <text x="215" y="80">0.700</text>
  <text x="20" y="108">pred3</text>
  <rect x="70" y="96" width="60" height="16" rx="2" fill="#4e79a7"/>
  <text x="135" y="108">0.300</text>
</svg></div>

The `development_roadmap` view turns the same checklist into a worklist by
keeping only the items that still fail or warn. The panic network passes every
check, so its roadmap collapses to a single `all checks pass` node, and the
deliberately weak fixture shipped alongside it shows the worklist in full.

```python
print(tf.read("weak-theory.theory.yaml").diagram("development_roadmap"))
```

```
digraph development_roadmap {
  graph [rankdir=TB, bgcolor="transparent", fontname="Helvetica", fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];
  node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", color="#33567A", fillcolor="#F2F6F9", fontcolor="#12283A", penwidth=1.1, margin="0.16,0.1"];
  edge [fontname="Helvetica", fontsize=10, color="#7B909F", fontcolor="#0F6E6E", arrowsize=0.7];
  "falsifiability" [label="falsifiability\nfail", fillcolor="#F9E5E4", color="#B2453C"];
  "precision" [label="precision\nwarn", fillcolor="#FBF1DC", color="#9C6B14"];
  "risk_severity" [label="risk_severity\nwarn", fillcolor="#FBF1DC", color="#9C6B14"];
  "construct_clarity" [label="construct_clarity\nwarn", fillcolor="#FBF1DC", color="#9C6B14"];
  "scope" [label="scope\nwarn", fillcolor="#FBF1DC", color="#9C6B14"];
  "logical_why" [label="logical_why\nwarn", fillcolor="#FBF1DC", color="#9C6B14"];
  "causal_testability" [label="causal_testability\nwarn", fillcolor="#FBF1DC", color="#9C6B14"];
  "diagnosticity" [label="diagnosticity\nwarn", fillcolor="#FBF1DC", color="#9C6B14"];
  "formalisation" [label="formalisation\nwarn", fillcolor="#FBF1DC", color="#9C6B14"];
  "derivation_chain" [label="derivation_chain\nfail", fillcolor="#F9E5E4", color="#B2453C"];
  "falsifiability" -> "precision" [style=invis];
  "precision" -> "risk_severity" [style=invis];
  "risk_severity" -> "construct_clarity" [style=invis];
  "construct_clarity" -> "scope" [style=invis];
  "scope" -> "logical_why" [style=invis];
  "logical_why" -> "causal_testability" [style=invis];
  "causal_testability" -> "diagnosticity" [style=invis];
  "diagnosticity" -> "formalisation" [style=invis];
  "formalisation" -> "derivation_chain" [style=invis];
}
```

<div class="tf-figure tf-diagram"><svg width="137pt" height="721pt"
 viewBox="0.00 0.00 136.54 720.80" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g id="graph0" class="graph" transform="scale(1 1) rotate(0) translate(14.4 706.4)">
<title>development_roadmap</title>
<!-- falsifiability -->
<g id="node1" class="node">
<title>falsifiability</title>
<path fill="#f9e5e4" stroke="#b2453c" stroke-width="1.1" d="M80.5303,-692.202C80.5303,-692.202 27.2083,-692.202 27.2083,-692.202 21.2083,-692.202 15.2083,-686.202 15.2083,-680.202 15.2083,-680.202 15.2083,-663.398 15.2083,-663.398 15.2083,-657.398 21.2083,-651.398 27.2083,-651.398 27.2083,-651.398 80.5303,-651.398 80.5303,-651.398 86.5303,-651.398 92.5303,-657.398 92.5303,-663.398 92.5303,-663.398 92.5303,-680.202 92.5303,-680.202 92.5303,-686.202 86.5303,-692.202 80.5303,-692.202"/>
<text text-anchor="middle" x="53.8693" y="-675.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">falsifiability</text>
<text text-anchor="middle" x="53.8693" y="-661.9" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">fail</text>
</g>
<!-- precision -->
<g id="node2" class="node">
<title>precision</title>
<path fill="#fbf1dc" stroke="#9c6b14" stroke-width="1.1" d="M75.8726,-619.802C75.8726,-619.802 31.866,-619.802 31.866,-619.802 25.866,-619.802 19.866,-613.802 19.866,-607.802 19.866,-607.802 19.866,-590.998 19.866,-590.998 19.866,-584.998 25.866,-578.998 31.866,-578.998 31.866,-578.998 75.8726,-578.998 75.8726,-578.998 81.8726,-578.998 87.8726,-584.998 87.8726,-590.998 87.8726,-590.998 87.8726,-607.802 87.8726,-607.802 87.8726,-613.802 81.8726,-619.802 75.8726,-619.802"/>
<text text-anchor="middle" x="53.8693" y="-602.7" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">precision</text>
<text text-anchor="middle" x="53.8693" y="-589.5" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">warn</text>
</g>
<!-- falsifiability&#45;&gt;precision -->
<!-- risk_severity -->
<g id="node3" class="node">
<title>risk_severity</title>
<path fill="#fbf1dc" stroke="#9c6b14" stroke-width="1.1" d="M84.4766,-547.402C84.4766,-547.402 23.262,-547.402 23.262,-547.402 17.262,-547.402 11.262,-541.402 11.262,-535.402 11.262,-535.402 11.262,-518.598 11.262,-518.598 11.262,-512.598 17.262,-506.598 23.262,-506.598 23.262,-506.598 84.4766,-506.598 84.4766,-506.598 90.4766,-506.598 96.4766,-512.598 96.4766,-518.598 96.4766,-518.598 96.4766,-535.402 96.4766,-535.402 96.4766,-541.402 90.4766,-547.402 84.4766,-547.402"/>
<text text-anchor="middle" x="53.8693" y="-530.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">risk_severity</text>
<text text-anchor="middle" x="53.8693" y="-517.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">warn</text>
</g>
<!-- precision&#45;&gt;risk_severity -->
<!-- construct_clarity -->
<g id="node4" class="node">
<title>construct_clarity</title>
<path fill="#fbf1dc" stroke="#9c6b14" stroke-width="1.1" d="M93.8211,-475.002C93.8211,-475.002 13.9175,-475.002 13.9175,-475.002 7.9175,-475.002 1.9175,-469.002 1.9175,-463.002 1.9175,-463.002 1.9175,-446.198 1.9175,-446.198 1.9175,-440.198 7.9175,-434.198 13.9175,-434.198 13.9175,-434.198 93.8211,-434.198 93.8211,-434.198 99.8211,-434.198 105.8211,-440.198 105.8211,-446.198 105.8211,-446.198 105.8211,-463.002 105.8211,-463.002 105.8211,-469.002 99.8211,-475.002 93.8211,-475.002"/>
<text text-anchor="middle" x="53.8693" y="-457.9" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">construct_clarity</text>
<text text-anchor="middle" x="53.8693" y="-444.7" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">warn</text>
</g>
<!-- risk_severity&#45;&gt;construct_clarity -->
<!-- scope -->
<g id="node5" class="node">
<title>scope</title>
<path fill="#fbf1dc" stroke="#9c6b14" stroke-width="1.1" d="M68.8693,-402.602C68.8693,-402.602 38.8693,-402.602 38.8693,-402.602 32.8693,-402.602 26.8693,-396.602 26.8693,-390.602 26.8693,-390.602 26.8693,-373.798 26.8693,-373.798 26.8693,-367.798 32.8693,-361.798 38.8693,-361.798 38.8693,-361.798 68.8693,-361.798 68.8693,-361.798 74.8693,-361.798 80.8693,-367.798 80.8693,-373.798 80.8693,-373.798 80.8693,-390.602 80.8693,-390.602 80.8693,-396.602 74.8693,-402.602 68.8693,-402.602"/>
<text text-anchor="middle" x="53.8693" y="-385.5" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">scope</text>
<text text-anchor="middle" x="53.8693" y="-372.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">warn</text>
</g>
<!-- construct_clarity&#45;&gt;scope -->
<!-- logical_why -->
<g id="node6" class="node">
<title>logical_why</title>
<path fill="#fbf1dc" stroke="#9c6b14" stroke-width="1.1" d="M82.2076,-330.202C82.2076,-330.202 25.531,-330.202 25.531,-330.202 19.531,-330.202 13.531,-324.202 13.531,-318.202 13.531,-318.202 13.531,-301.398 13.531,-301.398 13.531,-295.398 19.531,-289.398 25.531,-289.398 25.531,-289.398 82.2076,-289.398 82.2076,-289.398 88.2076,-289.398 94.2076,-295.398 94.2076,-301.398 94.2076,-301.398 94.2076,-318.202 94.2076,-318.202 94.2076,-324.202 88.2076,-330.202 82.2076,-330.202"/>
<text text-anchor="middle" x="53.8693" y="-313.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">logical_why</text>
<text text-anchor="middle" x="53.8693" y="-299.9" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">warn</text>
</g>
<!-- scope&#45;&gt;logical_why -->
<!-- causal_testability -->
<g id="node7" class="node">
<title>causal_testability</title>
<path fill="#fbf1dc" stroke="#9c6b14" stroke-width="1.1" d="M95.6082,-257.802C95.6082,-257.802 12.1304,-257.802 12.1304,-257.802 6.1304,-257.802 .1304,-251.802 .1304,-245.802 .1304,-245.802 .1304,-228.998 .1304,-228.998 .1304,-222.998 6.1304,-216.998 12.1304,-216.998 12.1304,-216.998 95.6082,-216.998 95.6082,-216.998 101.6082,-216.998 107.6082,-222.998 107.6082,-228.998 107.6082,-228.998 107.6082,-245.802 107.6082,-245.802 107.6082,-251.802 101.6082,-257.802 95.6082,-257.802"/>
<text text-anchor="middle" x="53.8693" y="-240.7" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">causal_testability</text>
<text text-anchor="middle" x="53.8693" y="-227.5" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">warn</text>
</g>
<!-- logical_why&#45;&gt;causal_testability -->
<!-- diagnosticity -->
<g id="node8" class="node">
<title>diagnosticity</title>
<path fill="#fbf1dc" stroke="#9c6b14" stroke-width="1.1" d="M83.8817,-185.402C83.8817,-185.402 23.8569,-185.402 23.8569,-185.402 17.8569,-185.402 11.8569,-179.402 11.8569,-173.402 11.8569,-173.402 11.8569,-156.598 11.8569,-156.598 11.8569,-150.598 17.8569,-144.598 23.8569,-144.598 23.8569,-144.598 83.8817,-144.598 83.8817,-144.598 89.8817,-144.598 95.8817,-150.598 95.8817,-156.598 95.8817,-156.598 95.8817,-173.402 95.8817,-173.402 95.8817,-179.402 89.8817,-185.402 83.8817,-185.402"/>
<text text-anchor="middle" x="53.8693" y="-168.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">diagnosticity</text>
<text text-anchor="middle" x="53.8693" y="-155.1" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">warn</text>
</g>
<!-- causal_testability&#45;&gt;diagnosticity -->
<!-- formalisation -->
<g id="node9" class="node">
<title>formalisation</title>
<path fill="#fbf1dc" stroke="#9c6b14" stroke-width="1.1" d="M85.2048,-113.002C85.2048,-113.002 22.5338,-113.002 22.5338,-113.002 16.5338,-113.002 10.5338,-107.002 10.5338,-101.002 10.5338,-101.002 10.5338,-84.198 10.5338,-84.198 10.5338,-78.198 16.5338,-72.198 22.5338,-72.198 22.5338,-72.198 85.2048,-72.198 85.2048,-72.198 91.2048,-72.198 97.2048,-78.198 97.2048,-84.198 97.2048,-84.198 97.2048,-101.002 97.2048,-101.002 97.2048,-107.002 91.2048,-113.002 85.2048,-113.002"/>
<text text-anchor="middle" x="53.8693" y="-95.9" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">formalisation</text>
<text text-anchor="middle" x="53.8693" y="-82.7" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">warn</text>
</g>
<!-- diagnosticity&#45;&gt;formalisation -->
<!-- derivation_chain -->
<g id="node10" class="node">
<title>derivation_chain</title>
<path fill="#f9e5e4" stroke="#b2453c" stroke-width="1.1" d="M93.9449,-40.602C93.9449,-40.602 13.7937,-40.602 13.7937,-40.602 7.7937,-40.602 1.7937,-34.602 1.7937,-28.602 1.7937,-28.602 1.7937,-11.798 1.7937,-11.798 1.7937,-5.798 7.7937,.202 13.7937,.202 13.7937,.202 93.9449,.202 93.9449,.202 99.9449,.202 105.9449,-5.798 105.9449,-11.798 105.9449,-11.798 105.9449,-28.602 105.9449,-28.602 105.9449,-34.602 99.9449,-40.602 93.9449,-40.602"/>
<text text-anchor="middle" x="53.8693" y="-23.5" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">derivation_chain</text>
<text text-anchor="middle" x="53.8693" y="-10.3" font-family="Helvetica,sans-Serif" font-size="11.00" fill="#12283a">fail</text>
</g>
<!-- formalisation&#45;&gt;derivation_chain -->
</g>
</svg></div>

Together with the `nomological_net` and `causal_dag` views shown in
[Getting started](getting-started.md), these complete the set of diagram types
that `diagram()` exports, each documented in the
[API reference](api.md#theoryforge.diagram.diagram).

## Simulation

`simulate()` treats each construct as a state variable and integrates the signed
proposition network as a linear dynamical system with fixed-step (Euler) updates.
The trajectory is fully deterministic.

The example below adds a regulating edge to the panic structure: arousal raises
threat, threat raises avoidance, and avoidance in turn *decreases* arousal. The
negative coupling breaks the symmetry between the states, so the qualitative
dynamics the network implies are visible in the trajectory.

```python
s = (
    tf.new_theory("regulation_demo", "Arousal regulated by avoidance")
      .add_construct("arousal", "Physiological arousal", "bodily activation")
      .add_construct("threat", "Perceived threat", "appraised danger")
      .add_construct("avoidance", "Avoidance behaviour", "protective withdrawal")
      .add_proposition("p1", "arousal", "threat", "increases")
      .add_proposition("p2", "threat", "avoidance", "increases")
      .add_proposition("p3", "avoidance", "arousal", "decreases")
)

sim = s.simulate(steps=5)
sim["states"]          # construct ids, in file order
sim["trajectory"][0]   # the common initial state
```

```
>>> sim["states"]
['arousal', 'threat', 'avoidance']
>>> sim["trajectory"][0]
[1.0, 1.0, 1.0]
>>> sim["trajectory"][1]
[0.85, 1.05, 1.05]
>>> sim["trajectory"][5]
[0.27225, 1.085807, 1.257262]
```

Arousal falls from the first step, pushed down by the negative coupling from
avoidance on top of the damping, while threat and avoidance are driven up by
their positive inputs before the decay takes over.
