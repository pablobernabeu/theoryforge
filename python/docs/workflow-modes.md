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
  rankdir=LR;
  node [shape=box];
  subgraph cluster_build {
    label="building";
    "c_arousal" [label="Physiological arousal"];
    "c_perceived_threat" [label="Perceived threat"];
    "c_avoidance" [label="Avoidance behaviour"];
  }
  subgraph cluster_relate {
    label="propositions";
    "prop_p1" [label="increases"];
    "prop_p2" [label="increases"];
    "prop_p3" [label="causes"];
  }
  subgraph cluster_predict {
    label="predictions";
    "pred_pred1" [label="point"];
    "pred_pred2" [label="interval"];
    "pred_pred3" [label="directional"];
  }
  subgraph cluster_test {
    label="testing";
    "outcome_pred1" [label="passed=true"];
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

<div class="tf-figure tf-diagram"><svg width="511pt" height="209pt"
 viewBox="0.00 0.00 511.29 209.00" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g id="graph0" class="graph" transform="scale(1 1) rotate(0) translate(4 205)">
<title>workflow</title>
<polygon fill="#ffffff" stroke="transparent" points="-4,4 -4,-205 507.2882,-205 507.2882,4 -4,4"/>
<g id="clust1" class="cluster">
<title>cluster_build</title>
<polygon fill="none" stroke="#000000" points="8,-8 8,-193 160.1438,-193 160.1438,-8 8,-8"/>
<text text-anchor="middle" x="84.0719" y="-176.4" font-family="Times,serif" font-size="14.00" fill="#000000">building</text>
</g>
<g id="clust2" class="cluster">
<title>cluster_relate</title>
<polygon fill="none" stroke="#000000" points="180.1438,-8 180.1438,-193 264.4426,-193 264.4426,-8 180.1438,-8"/>
<text text-anchor="middle" x="222.2932" y="-176.4" font-family="Times,serif" font-size="14.00" fill="#000000">propositions</text>
</g>
<g id="clust3" class="cluster">
<title>cluster_predict</title>
<polygon fill="none" stroke="#000000" points="284.4426,-8 284.4426,-193 376.3094,-193 376.3094,-8 284.4426,-8"/>
<text text-anchor="middle" x="330.376" y="-176.4" font-family="Times,serif" font-size="14.00" fill="#000000">predictions</text>
</g>
<g id="clust4" class="cluster">
<title>cluster_test</title>
<polygon fill="none" stroke="#000000" points="396.3094,-116 396.3094,-193 495.2882,-193 495.2882,-116 396.3094,-116"/>
<text text-anchor="middle" x="445.7988" y="-176.4" font-family="Times,serif" font-size="14.00" fill="#000000">testing</text>
</g>
<!-- c_arousal -->
<g id="node1" class="node">
<title>c_arousal</title>
<polygon fill="none" stroke="#000000" points="152.2158,-160 15.928,-160 15.928,-124 152.2158,-124 152.2158,-160"/>
<text text-anchor="middle" x="84.0719" y="-137.8" font-family="Times,serif" font-size="14.00" fill="#000000">Physiological arousal</text>
</g>
<!-- prop_p1 -->
<g id="node4" class="node">
<title>prop_p1</title>
<polygon fill="none" stroke="#000000" points="255.5927,-160 187.9937,-160 187.9937,-124 255.5927,-124 255.5927,-160"/>
<text text-anchor="middle" x="221.7932" y="-137.8" font-family="Times,serif" font-size="14.00" fill="#000000">increases</text>
</g>
<!-- c_arousal&#45;&gt;prop_p1 -->
<g id="edge1" class="edge">
<title>c_arousal&#45;&gt;prop_p1</title>
<path fill="none" stroke="#000000" d="M152.5291,-142C161.072,-142 169.6233,-142 177.6569,-142"/>
<polygon fill="#000000" stroke="#000000" points="177.8754,-145.5001 187.8754,-142 177.8753,-138.5001 177.8754,-145.5001"/>
</g>
<!-- c_perceived_threat -->
<g id="node2" class="node">
<title>c_perceived_threat</title>
<polygon fill="none" stroke="#000000" points="137.136,-106 31.0078,-106 31.0078,-70 137.136,-70 137.136,-106"/>
<text text-anchor="middle" x="84.0719" y="-83.8" font-family="Times,serif" font-size="14.00" fill="#000000">Perceived threat</text>
</g>
<!-- prop_p2 -->
<g id="node5" class="node">
<title>prop_p2</title>
<polygon fill="none" stroke="#000000" points="255.5927,-52 187.9937,-52 187.9937,-16 255.5927,-16 255.5927,-52"/>
<text text-anchor="middle" x="221.7932" y="-29.8" font-family="Times,serif" font-size="14.00" fill="#000000">increases</text>
</g>
<!-- c_perceived_threat&#45;&gt;prop_p2 -->
<g id="edge2" class="edge">
<title>c_perceived_threat&#45;&gt;prop_p2</title>
<path fill="none" stroke="#000000" d="M136.6357,-69.8987C144.5483,-67.0137 152.5862,-63.9917 160.1438,-61 166.1327,-58.6293 172.401,-56.0276 178.5506,-53.4044"/>
<polygon fill="#000000" stroke="#000000" points="180.2687,-56.4747 188.0594,-49.2945 177.4914,-50.0492 180.2687,-56.4747"/>
</g>
<!-- prop_p3 -->
<g id="node6" class="node">
<title>prop_p3</title>
<polygon fill="none" stroke="#000000" points="248.7932,-106 194.7932,-106 194.7932,-70 248.7932,-70 248.7932,-106"/>
<text text-anchor="middle" x="221.7932" y="-83.8" font-family="Times,serif" font-size="14.00" fill="#000000">causes</text>
</g>
<!-- c_perceived_threat&#45;&gt;prop_p3 -->
<g id="edge3" class="edge">
<title>c_perceived_threat&#45;&gt;prop_p3</title>
<path fill="none" stroke="#000000" d="M137.3186,-88C153.0331,-88 169.8929,-88 184.3853,-88"/>
<polygon fill="#000000" stroke="#000000" points="184.4695,-91.5001 194.4694,-88 184.4694,-84.5001 184.4695,-91.5001"/>
</g>
<!-- c_avoidance -->
<g id="node3" class="node">
<title>c_avoidance</title>
<polygon fill="none" stroke="#000000" points="152.1934,-52 15.9504,-52 15.9504,-16 152.1934,-16 152.1934,-52"/>
<text text-anchor="middle" x="84.0719" y="-29.8" font-family="Times,serif" font-size="14.00" fill="#000000">Avoidance behaviour</text>
</g>
<!-- pred_pred1 -->
<g id="node7" class="node">
<title>pred_pred1</title>
<polygon fill="none" stroke="#000000" points="357.376,-160 303.376,-160 303.376,-124 357.376,-124 357.376,-160"/>
<text text-anchor="middle" x="330.376" y="-137.8" font-family="Times,serif" font-size="14.00" fill="#000000">point</text>
</g>
<!-- prop_p1&#45;&gt;pred_pred1 -->
<g id="edge4" class="edge">
<title>prop_p1&#45;&gt;pred_pred1</title>
<path fill="none" stroke="#000000" d="M255.5543,-142C267.3993,-142 280.7734,-142 292.9044,-142"/>
<polygon fill="#000000" stroke="#000000" points="293.1752,-145.5001 303.1752,-142 293.1752,-138.5001 293.1752,-145.5001"/>
</g>
<!-- pred_pred2 -->
<g id="node8" class="node">
<title>pred_pred2</title>
<polygon fill="none" stroke="#000000" points="359.6381,-106 301.1139,-106 301.1139,-70 359.6381,-70 359.6381,-106"/>
<text text-anchor="middle" x="330.376" y="-83.8" font-family="Times,serif" font-size="14.00" fill="#000000">interval</text>
</g>
<!-- prop_p2&#45;&gt;pred_pred2 -->
<g id="edge6" class="edge">
<title>prop_p2&#45;&gt;pred_pred2</title>
<path fill="none" stroke="#000000" d="M255.5543,-50.7899C267.0491,-56.5065 279.984,-62.9392 291.8252,-68.8281"/>
<polygon fill="#000000" stroke="#000000" points="290.5265,-72.0911 301.0389,-73.4102 293.6435,-65.8234 290.5265,-72.0911"/>
</g>
<!-- pred_pred3 -->
<g id="node9" class="node">
<title>pred_pred3</title>
<polygon fill="none" stroke="#000000" points="368.2429,-52 292.5091,-52 292.5091,-16 368.2429,-16 368.2429,-52"/>
<text text-anchor="middle" x="330.376" y="-29.8" font-family="Times,serif" font-size="14.00" fill="#000000">directional</text>
</g>
<!-- prop_p2&#45;&gt;pred_pred3 -->
<g id="edge7" class="edge">
<title>prop_p2&#45;&gt;pred_pred3</title>
<path fill="none" stroke="#000000" d="M255.5543,-34C264.058,-34 273.3497,-34 282.4038,-34"/>
<polygon fill="#000000" stroke="#000000" points="282.4705,-37.5001 292.4705,-34 282.4704,-30.5001 282.4705,-37.5001"/>
</g>
<!-- prop_p3&#45;&gt;pred_pred1 -->
<g id="edge5" class="edge">
<title>prop_p3&#45;&gt;pred_pred1</title>
<path fill="none" stroke="#000000" d="M248.9131,-101.4872C262.5166,-108.2524 279.1865,-116.5426 293.895,-123.8574"/>
<polygon fill="#000000" stroke="#000000" points="292.7131,-127.1785 303.2255,-128.4976 295.8301,-120.9108 292.7131,-127.1785"/>
</g>
<!-- outcome_pred1 -->
<g id="node10" class="node">
<title>outcome_pred1</title>
<polygon fill="none" stroke="#000000" points="487.2776,-160 404.32,-160 404.32,-124 487.2776,-124 487.2776,-160"/>
<text text-anchor="middle" x="445.7988" y="-137.8" font-family="Times,serif" font-size="14.00" fill="#000000">passed=true</text>
</g>
<!-- pred_pred1&#45;&gt;outcome_pred1 -->
<g id="edge8" class="edge">
<title>pred_pred1&#45;&gt;outcome_pred1</title>
<path fill="none" stroke="#000000" d="M357.4375,-142C368.2652,-142 381.1206,-142 393.626,-142"/>
<polygon fill="#000000" stroke="#000000" points="393.996,-145.5001 403.9959,-142 393.9959,-138.5001 393.996,-145.5001"/>
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
  rankdir=LR;
  node [shape=box, style=rounded];
  "theory" [shape=ellipse, label="Network theory of panic disorder"];
  "c_arousal" [label="Physiological arousal"];
  "theory" -> "c_arousal";
  "c_perceived_threat" [label="Perceived threat"];
  "theory" -> "c_perceived_threat";
  "c_avoidance" [label="Avoidance behaviour"];
  "theory" -> "c_avoidance";
  "scope1" [shape=note, label="adults"];
  "scope1" -> "theory" [style=dotted, label="holds within"];
  "scope2" [shape=note, label="non-clinical baseline"];
  "scope2" -> "theory" [style=dotted, label="holds within"];
  "scope3" [shape=note, label="no beta-blocker medication"];
  "scope3" -> "theory" [style=dotted, label="holds within"];
  "alt_cognitive" [shape=box, style=dashed, label="Cognitive model of panic"];
  "theory" -> "alt_cognitive" [style=dashed, label="contrasts with"];
  "alt_biological" [shape=box, style=dashed, label="Biological model of panic"];
  "theory" -> "alt_biological" [style=dashed, label="contrasts with"];
}
```

<div class="tf-figure tf-diagram"><svg width="838pt" height="260pt"
 viewBox="0.00 0.00 838.23 260.00" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g id="graph0" class="graph" transform="scale(1 1) rotate(0) translate(4 256)">
<title>context</title>
<polygon fill="#ffffff" stroke="transparent" points="-4,4 -4,-256 834.2273,-256 834.2273,4 -4,4"/>
<!-- theory -->
<g id="node1" class="node">
<title>theory</title>
<ellipse fill="none" stroke="#000000" cx="414.5278" cy="-126" rx="139.9948" ry="18"/>
<text text-anchor="middle" x="414.5278" y="-121.8" font-family="Times,serif" font-size="14.00" fill="#000000">Network theory of panic disorder</text>
</g>
<!-- c_arousal -->
<g id="node2" class="node">
<title>c_arousal</title>
<path fill="none" stroke="#000000" d="M805.469,-252C805.469,-252 693.1812,-252 693.1812,-252 687.1812,-252 681.1812,-246 681.1812,-240 681.1812,-240 681.1812,-228 681.1812,-228 681.1812,-222 687.1812,-216 693.1812,-216 693.1812,-216 805.469,-216 805.469,-216 811.469,-216 817.469,-222 817.469,-228 817.469,-228 817.469,-240 817.469,-240 817.469,-246 811.469,-252 805.469,-252"/>
<text text-anchor="middle" x="749.3251" y="-229.8" font-family="Times,serif" font-size="14.00" fill="#000000">Physiological arousal</text>
</g>
<!-- theory&#45;&gt;c_arousal -->
<g id="edge1" class="edge">
<title>theory&#45;&gt;c_arousal</title>
<path fill="none" stroke="#000000" d="M466.4725,-142.7565C524.9972,-161.6356 620.2302,-192.3562 683.8132,-212.867"/>
<polygon fill="#000000" stroke="#000000" points="682.7541,-216.2029 693.3458,-215.942 684.9032,-209.5409 682.7541,-216.2029"/>
</g>
<!-- c_perceived_threat -->
<g id="node3" class="node">
<title>c_perceived_threat</title>
<path fill="none" stroke="#000000" d="M790.3892,-198C790.3892,-198 708.261,-198 708.261,-198 702.261,-198 696.261,-192 696.261,-186 696.261,-186 696.261,-174 696.261,-174 696.261,-168 702.261,-162 708.261,-162 708.261,-162 790.3892,-162 790.3892,-162 796.3892,-162 802.3892,-168 802.3892,-174 802.3892,-174 802.3892,-186 802.3892,-186 802.3892,-192 796.3892,-198 790.3892,-198"/>
<text text-anchor="middle" x="749.3251" y="-175.8" font-family="Times,serif" font-size="14.00" fill="#000000">Perceived threat</text>
</g>
<!-- theory&#45;&gt;c_perceived_threat -->
<g id="edge2" class="edge">
<title>theory&#45;&gt;c_perceived_threat</title>
<path fill="none" stroke="#000000" d="M502.0545,-140.1173C559.6331,-149.4043 633.6787,-161.3472 685.6758,-169.7339"/>
<polygon fill="#000000" stroke="#000000" points="685.3401,-173.2249 695.7698,-171.362 686.4548,-166.3142 685.3401,-173.2249"/>
</g>
<!-- c_avoidance -->
<g id="node4" class="node">
<title>c_avoidance</title>
<path fill="none" stroke="#000000" d="M805.4466,-144C805.4466,-144 693.2037,-144 693.2037,-144 687.2037,-144 681.2037,-138 681.2037,-132 681.2037,-132 681.2037,-120 681.2037,-120 681.2037,-114 687.2037,-108 693.2037,-108 693.2037,-108 805.4466,-108 805.4466,-108 811.4466,-108 817.4466,-114 817.4466,-120 817.4466,-120 817.4466,-132 817.4466,-132 817.4466,-138 811.4466,-144 805.4466,-144"/>
<text text-anchor="middle" x="749.3251" y="-121.8" font-family="Times,serif" font-size="14.00" fill="#000000">Avoidance behaviour</text>
</g>
<!-- theory&#45;&gt;c_avoidance -->
<g id="edge3" class="edge">
<title>theory&#45;&gt;c_avoidance</title>
<path fill="none" stroke="#000000" d="M554.5721,-126C594.3654,-126 636.2783,-126 670.9856,-126"/>
<polygon fill="#000000" stroke="#000000" points="671.0441,-129.5001 681.0441,-126 671.044,-122.5001 671.0441,-129.5001"/>
</g>
<!-- alt_cognitive -->
<g id="node8" class="node">
<title>alt_cognitive</title>
<polygon fill="none" stroke="#000000" stroke-dasharray="5,2" points="828.5246,-90 670.1256,-90 670.1256,-54 828.5246,-54 828.5246,-90"/>
<text text-anchor="middle" x="749.3251" y="-67.8" font-family="Times,serif" font-size="14.00" fill="#000000">Cognitive model of panic</text>
</g>
<!-- theory&#45;&gt;alt_cognitive -->
<g id="edge7" class="edge">
<title>theory&#45;&gt;alt_cognitive</title>
<path fill="none" stroke="#000000" stroke-dasharray="5,2" d="M502.0545,-111.8827C550.7222,-104.033 611.1543,-94.2858 660.0929,-86.3924"/>
<polygon fill="#000000" stroke="#000000" points="660.7212,-89.8364 670.0363,-84.7886 659.6065,-82.9257 660.7212,-89.8364"/>
<text text-anchor="middle" x="611.3489" y="-103.2" font-family="Times,serif" font-size="14.00" fill="#000000">contrasts with</text>
</g>
<!-- alt_biological -->
<g id="node9" class="node">
<title>alt_biological</title>
<polygon fill="none" stroke="#000000" stroke-dasharray="5,2" points="830.1296,-36 668.5206,-36 668.5206,0 830.1296,0 830.1296,-36"/>
<text text-anchor="middle" x="749.3251" y="-13.8" font-family="Times,serif" font-size="14.00" fill="#000000">Biological model of panic</text>
</g>
<!-- theory&#45;&gt;alt_biological -->
<g id="edge8" class="edge">
<title>theory&#45;&gt;alt_biological</title>
<path fill="none" stroke="#000000" stroke-dasharray="5,2" d="M457.6974,-108.7674C489.205,-96.4706 533.0783,-79.9255 572.2749,-67.2 603.7623,-56.9774 638.8137,-46.9583 669.3661,-38.6573"/>
<polygon fill="#000000" stroke="#000000" points="670.3755,-42.0102 679.1175,-36.0245 668.5508,-35.2522 670.3755,-42.0102"/>
<text text-anchor="middle" x="611.3489" y="-72.2" font-family="Times,serif" font-size="14.00" fill="#000000">contrasts with</text>
</g>
<!-- scope1 -->
<g id="node5" class="node">
<title>scope1</title>
<text text-anchor="middle" x="84.5835" y="-175.8" font-family="Times,serif" font-size="14.00" fill="#000000">adults</text>
</g>
<!-- scope1&#45;&gt;theory -->
<g id="edge4" class="edge">
<title>scope1&#45;&gt;theory</title>
<path fill="none" stroke="#000000" stroke-dasharray="1,5" d="M111.5842,-175.581C156.1054,-168.2944 247.0216,-153.4147 317.6959,-141.8479"/>
<polygon fill="#000000" stroke="#000000" points="318.6651,-145.2359 327.9685,-140.1666 317.5345,-138.3278 318.6651,-145.2359"/>
<text text-anchor="middle" x="221.9738" y="-166.2" font-family="Times,serif" font-size="14.00" fill="#000000">holds within</text>
</g>
<!-- scope2 -->
<g id="node6" class="node">
<title>scope2</title>
<text text-anchor="middle" x="84.5835" y="-121.8" font-family="Times,serif" font-size="14.00" fill="#000000">non&#45;clinical baseline</text>
</g>
<!-- scope2&#45;&gt;theory -->
<g id="edge5" class="edge">
<title>scope2&#45;&gt;theory</title>
<path fill="none" stroke="#000000" stroke-dasharray="1,5" d="M150.9557,-126C183.7435,-126 224.7388,-126 264.5586,-126"/>
<polygon fill="#000000" stroke="#000000" points="264.6512,-129.5001 274.6512,-126 264.6512,-122.5001 264.6512,-129.5001"/>
<text text-anchor="middle" x="221.9738" y="-130.2" font-family="Times,serif" font-size="14.00" fill="#000000">holds within</text>
</g>
<!-- scope3 -->
<g id="node7" class="node">
<title>scope3</title>
<text text-anchor="middle" x="84.5835" y="-67.8" font-family="Times,serif" font-size="14.00" fill="#000000">no beta&#45;blocker medication</text>
</g>
<!-- scope3&#45;&gt;theory -->
<g id="edge6" class="edge">
<title>scope3&#45;&gt;theory</title>
<path fill="none" stroke="#000000" stroke-dasharray="1,5" d="M169.5523,-85.9063C214.9191,-93.3312 270.9362,-102.4992 317.9489,-110.1935"/>
<polygon fill="#000000" stroke="#000000" points="317.4031,-113.6507 327.8371,-111.8119 318.5337,-106.7426 317.4031,-113.6507"/>
<text text-anchor="middle" x="221.9738" y="-103.2" font-family="Times,serif" font-size="14.00" fill="#000000">holds within</text>
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
  rankdir=LR;
  node [shape=box];
  "pred1" [label="point"];
  "pred2" [label="interval"];
  "pred3" [label="directional"];
  "result_pred1" [label="passed=true"];
  "pred1" -> "result_pred1";
}
```

<div class="tf-figure tf-diagram"><svg width="203pt" height="152pt"
 viewBox="0.00 0.00 202.85 152.00" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g id="graph0" class="graph" transform="scale(1 1) rotate(0) translate(4 148)">
<title>pipeline</title>
<polygon fill="#ffffff" stroke="transparent" points="-4,4 -4,-148 198.8456,-148 198.8456,4 -4,4"/>
<!-- pred1 -->
<g id="node1" class="node">
<title>pred1</title>
<polygon fill="none" stroke="#000000" points="64.9334,-36 10.9334,-36 10.9334,0 64.9334,0 64.9334,-36"/>
<text text-anchor="middle" x="37.9334" y="-13.8" font-family="Times,serif" font-size="14.00" fill="#000000">point</text>
</g>
<!-- result_pred1 -->
<g id="node4" class="node">
<title>result_pred1</title>
<polygon fill="none" stroke="#000000" points="194.835,-36 111.8774,-36 111.8774,0 194.835,0 194.835,-36"/>
<text text-anchor="middle" x="153.3562" y="-13.8" font-family="Times,serif" font-size="14.00" fill="#000000">passed=true</text>
</g>
<!-- pred1&#45;&gt;result_pred1 -->
<g id="edge1" class="edge">
<title>pred1&#45;&gt;result_pred1</title>
<path fill="none" stroke="#000000" d="M64.9949,-18C75.8226,-18 88.678,-18 101.1834,-18"/>
<polygon fill="#000000" stroke="#000000" points="101.5534,-21.5001 111.5533,-18 101.5533,-14.5001 101.5534,-21.5001"/>
</g>
<!-- pred2 -->
<g id="node2" class="node">
<title>pred2</title>
<polygon fill="none" stroke="#000000" points="67.1955,-90 8.6713,-90 8.6713,-54 67.1955,-54 67.1955,-90"/>
<text text-anchor="middle" x="37.9334" y="-67.8" font-family="Times,serif" font-size="14.00" fill="#000000">interval</text>
</g>
<!-- pred3 -->
<g id="node3" class="node">
<title>pred3</title>
<polygon fill="none" stroke="#000000" points="75.8003,-144 .0665,-144 .0665,-108 75.8003,-108 75.8003,-144"/>
<text text-anchor="middle" x="37.9334" y="-121.8" font-family="Times,serif" font-size="14.00" fill="#000000">directional</text>
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
  rankdir=TB;
  node [shape=box];
  "n1" [label="tf_construct: Registered three constructs."];
  "n2" [label="tf_proposition: Linked constructs into a feedback network."];
  "n3" [label="tf_predict: Derived three predictions from the propositions."];
  "n1" -> "n2";
  "n2" -> "n3";
}
```

<div class="tf-figure tf-diagram"><svg width="356pt" height="188pt"
 viewBox="0.00 0.00 355.62 188.00" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g id="graph0" class="graph" transform="scale(1 1) rotate(0) translate(4 184)">
<title>provenance</title>
<polygon fill="#ffffff" stroke="transparent" points="-4,4 -4,-184 351.625,-184 351.625,4 -4,4"/>
<!-- n1 -->
<g id="node1" class="node">
<title>n1</title>
<polygon fill="none" stroke="#000000" points="296.6776,-180 50.9474,-180 50.9474,-144 296.6776,-144 296.6776,-180"/>
<text text-anchor="middle" x="173.8125" y="-157.8" font-family="Times,serif" font-size="14.00" fill="#000000">tf_construct: Registered three constructs.</text>
</g>
<!-- n2 -->
<g id="node2" class="node">
<title>n2</title>
<polygon fill="none" stroke="#000000" points="345.8368,-108 1.7882,-108 1.7882,-72 345.8368,-72 345.8368,-108"/>
<text text-anchor="middle" x="173.8125" y="-85.8" font-family="Times,serif" font-size="14.00" fill="#000000">tf_proposition: Linked constructs into a feedback network.</text>
</g>
<!-- n1&#45;&gt;n2 -->
<g id="edge1" class="edge">
<title>n1&#45;&gt;n2</title>
<path fill="none" stroke="#000000" d="M173.8125,-143.8314C173.8125,-136.131 173.8125,-126.9743 173.8125,-118.4166"/>
<polygon fill="#000000" stroke="#000000" points="177.3126,-118.4132 173.8125,-108.4133 170.3126,-118.4133 177.3126,-118.4132"/>
</g>
<!-- n3 -->
<g id="node3" class="node">
<title>n3</title>
<polygon fill="none" stroke="#000000" points="347.4377,-36 .1873,-36 .1873,0 347.4377,0 347.4377,-36"/>
<text text-anchor="middle" x="173.8125" y="-13.8" font-family="Times,serif" font-size="14.00" fill="#000000">tf_predict: Derived three predictions from the propositions.</text>
</g>
<!-- n2&#45;&gt;n3 -->
<g id="edge2" class="edge">
<title>n2&#45;&gt;n3</title>
<path fill="none" stroke="#000000" d="M173.8125,-71.8314C173.8125,-64.131 173.8125,-54.9743 173.8125,-46.4166"/>
<polygon fill="#000000" stroke="#000000" points="177.3126,-46.4132 173.8125,-36.4133 170.3126,-46.4133 177.3126,-46.4132"/>
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
  rankdir=TB;
  node [shape=box];
  "falsifiability" [label="falsifiability (fail)"];
  "precision" [label="precision (warn)"];
  "risk_severity" [label="risk_severity (warn)"];
  "construct_clarity" [label="construct_clarity (warn)"];
  "scope" [label="scope (warn)"];
  "logical_why" [label="logical_why (warn)"];
  "causal_testability" [label="causal_testability (warn)"];
  "diagnosticity" [label="diagnosticity (warn)"];
  "formalisation" [label="formalisation (warn)"];
  "derivation_chain" [label="derivation_chain (fail)"];
}
```

<div class="tf-figure tf-diagram"><svg width="1446pt" height="44pt"
 viewBox="0.00 0.00 1445.73 44.00" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g id="graph0" class="graph" transform="scale(1 1) rotate(0) translate(4 40)">
<title>development_roadmap</title>
<polygon fill="#ffffff" stroke="transparent" points="-4,4 -4,-40 1441.7329,-40 1441.7329,4 -4,4"/>
<!-- falsifiability -->
<g id="node1" class="node">
<title>falsifiability</title>
<polygon fill="none" stroke="#000000" points="115.8602,-36 .0466,-36 .0466,0 115.8602,0 115.8602,-36"/>
<text text-anchor="middle" x="57.9534" y="-13.8" font-family="Times,serif" font-size="14.00" fill="#000000">falsifiability (fail)</text>
</g>
<!-- precision -->
<g id="node2" class="node">
<title>precision</title>
<polygon fill="none" stroke="#000000" points="242.0721,-36 133.8347,-36 133.8347,0 242.0721,0 242.0721,-36"/>
<text text-anchor="middle" x="187.9534" y="-13.8" font-family="Times,serif" font-size="14.00" fill="#000000">precision (warn)</text>
</g>
<!-- risk_severity -->
<g id="node3" class="node">
<title>risk_severity</title>
<polygon fill="none" stroke="#000000" points="389.5679,-36 260.3389,-36 260.3389,0 389.5679,0 389.5679,-36"/>
<text text-anchor="middle" x="324.9534" y="-13.8" font-family="Times,serif" font-size="14.00" fill="#000000">risk_severity (warn)</text>
</g>
<!-- construct_clarity -->
<g id="node4" class="node">
<title>construct_clarity</title>
<polygon fill="none" stroke="#000000" points="558.3336,-36 407.5732,-36 407.5732,0 558.3336,0 558.3336,-36"/>
<text text-anchor="middle" x="482.9534" y="-13.8" font-family="Times,serif" font-size="14.00" fill="#000000">construct_clarity (warn)</text>
</g>
<!-- scope -->
<g id="node5" class="node">
<title>scope</title>
<polygon fill="none" stroke="#000000" points="665.1308,-36 576.776,-36 576.776,0 665.1308,0 665.1308,-36"/>
<text text-anchor="middle" x="620.9534" y="-13.8" font-family="Times,serif" font-size="14.00" fill="#000000">scope (warn)</text>
</g>
<!-- logical_why -->
<g id="node6" class="node">
<title>logical_why</title>
<polygon fill="none" stroke="#000000" points="808.964,-36 682.9428,-36 682.9428,0 808.964,0 808.964,-36"/>
<text text-anchor="middle" x="745.9534" y="-13.8" font-family="Times,serif" font-size="14.00" fill="#000000">logical_why (warn)</text>
</g>
<!-- causal_testability -->
<g id="node7" class="node">
<title>causal_testability</title>
<polygon fill="none" stroke="#000000" points="980.9528,-36 826.954,-36 826.954,0 980.9528,0 980.9528,-36"/>
<text text-anchor="middle" x="903.9534" y="-13.8" font-family="Times,serif" font-size="14.00" fill="#000000">causal_testability (warn)</text>
</g>
<!-- diagnosticity -->
<g id="node8" class="node">
<title>diagnosticity</title>
<polygon fill="none" stroke="#000000" points="1128.5833,-36 999.3235,-36 999.3235,0 1128.5833,0 1128.5833,-36"/>
<text text-anchor="middle" x="1063.9534" y="-13.8" font-family="Times,serif" font-size="14.00" fill="#000000">diagnosticity (warn)</text>
</g>
<!-- formalisation -->
<g id="node9" class="node">
<title>formalisation</title>
<polygon fill="none" stroke="#000000" points="1277.9052,-36 1146.0016,-36 1146.0016,0 1277.9052,0 1277.9052,-36"/>
<text text-anchor="middle" x="1211.9534" y="-13.8" font-family="Times,serif" font-size="14.00" fill="#000000">formalisation (warn)</text>
</g>
<!-- derivation_chain -->
<g id="node10" class="node">
<title>derivation_chain</title>
<polygon fill="none" stroke="#000000" points="1437.5131,-36 1296.3937,-36 1296.3937,0 1437.5131,0 1437.5131,-36"/>
<text text-anchor="middle" x="1366.9534" y="-13.8" font-family="Times,serif" font-size="14.00" fill="#000000">derivation_chain (fail)</text>
</g>
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
