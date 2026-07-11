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
the rigour checklist, the severity table, the provenance log and the
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

<div class="tf-figure"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 380 132" font-family="sans-serif" font-size="13">
  <text x="20" y="26" font-size="15">Prediction severity</text>
  <text x="20" y="52">pred1</text>
  <rect x="130" y="40" width="200" height="16" rx="2" fill="#4e79a7"/>
  <text x="335" y="52">1.000</text>
  <text x="20" y="80">pred2</text>
  <rect x="130" y="68" width="140" height="16" rx="2" fill="#4e79a7"/>
  <text x="275" y="80">0.700</text>
  <text x="20" y="108">pred3</text>
  <rect x="130" y="96" width="60" height="16" rx="2" fill="#4e79a7"/>
  <text x="195" y="108">0.300</text>
</svg></div>

Three further graph views are not shown here: `provenance` (the build log as a
digraph), `development_roadmap` (the checklist items still failing or warning),
and `pipeline` (each prediction linked to its test outcome). See the
[API reference](api.md#theoryforge.diagram.diagram) for the complete list of
diagram types.

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
