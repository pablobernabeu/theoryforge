# Methodological foundations

## Why theoryforge

Psychology and the social sciences accumulate findings far faster than they build theories that explain them. Constructs proliferate and overlap (the jingle-jangle problem), and predictions stay vague and directional where they ought to commit. Auxiliary assumptions accrete to protect a theory from the tests it should face, and a revision is rarely judged by whether it adds testable content or only deflects refutation. These problems have been described as psychology's theory crisis (Eronen & Bringmann, 2021).

theoryforge holds a theory as a structured, versioned object: its constructs, the propositions that relate them, the predictions derived from those propositions, the auxiliary assumptions that protect them, the rival accounts it is tested against and the record of each revision. It scores the theory against a checklist of rigour criteria, reads the causal claims of its propositions, grades the form of each prediction's claim before any data and the severity of a test after it, screens its constructs for redundancy, appraises amendments in Lakatos's sense and maps the theory against a literature corpus.

Each of these analyses applies a fixed rule, set out in the [specification](https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md), so the same theory always gives the same result and a reader can check each value against the rule. None of them fits a model to data or draws a random number. The one analysis that depends on a model is the opt-in embedding screen of construct definitions, whose similarities depend on the embedding model the user supplies. The R and Python packages implement the same specification and are tested against the same expected outputs, apart from the functions that call a network service, an embedding model or a renderer. [Scope and limits](#scope-and-limits), near the end of the page, says what this checking does and does not establish.

## Grounding for each rigour check

Each rigour check addresses a concern raised in the methodology literature. The table gives the criterion each check applies, its weight in the aggregate score and works that discuss the concern, and the name in brackets is the identifier the check carries in the report. When this page is built, the criteria and weights are read from the checklist file that the package ships. The rule that turns the concern into a score, described in the sections below, is the package's own. The report names works for each check in its `citation` field, and the works cited on this page are listed in APA style in the references at the foot of the page.

```python exec="1" session="methodology"
# The criterion and weight columns come from the shipped checklist, so the table
# changes with it. The names and the supporting works are kept here, keyed by
# the identifier of each check, and a check that the checklist gains or drops
# stops the build until this table is brought up to date.
from theoryforge._resources import checklist

CHECKS = {
    "falsifiability": (
        "Falsifiability",
        "[Popper (1959/2005)](https://doi.org/10.4324/9780203994627), "
        "[Bacharach (1989)](https://doi.org/10.5465/amr.1989.4308374)",
    ),
    "precision": (
        "Predictive precision",
        "[Meehl (1967)](https://doi.org/10.1086/288135), "
        "[Meehl (1990a)](https://doi.org/10.1207/s15327965pli0102_1)",
    ),
    "risk_severity": (
        "Prediction severity",
        "[Popper (1959/2005)](https://doi.org/10.4324/9780203994627), "
        "[Meehl (1967)](https://doi.org/10.1086/288135), "
        "[Meehl (1990b)](https://doi.org/10.2466/pr0.1990.66.1.195)",
    ),
    "parsimony": (
        "Parsimony",
        "[Lakatos (1970)](https://doi.org/10.1017/cbo9781139171434.009), "
        "[Meehl (1990a)](https://doi.org/10.1207/s15327965pli0102_1)",
    ),
    "non_redundancy": (
        "Construct non-redundancy",
        "[Le et al. (2010)](https://doi.org/10.1016/j.obhdp.2010.02.003), "
        "[Lawson & Robins (2021)](https://doi.org/10.1177/10888683211047101)",
    ),
    "construct_clarity": (
        "Construct clarity",
        "[Suddaby (2010)](https://doi.org/10.5465/amr.35.3.zok346), "
        "[Cronbach & Meehl (1955)](https://doi.org/10.1037/h0040957), "
        "[Flake & Fried (2020)](https://doi.org/10.1177/2515245920952393)",
    ),
    "scope": (
        "Scope and boundary conditions",
        "[Whetten (1989)](https://doi.org/10.5465/amr.1989.4308371), "
        "[Bacharach (1989)](https://doi.org/10.5465/amr.1989.4308374)",
    ),
    "logical_why": (
        "Mechanism",
        "[Sutton & Staw (1995)](https://doi.org/10.2307/2393788), "
        "[Whetten (1989)](https://doi.org/10.5465/amr.1989.4308371)",
    ),
    "causal_testability": (
        "Causal testability",
        "[Rohrer (2018)](https://doi.org/10.1177/2515245917745629), "
        "[Eronen & Bringmann (2021)](https://doi.org/10.1177/1745691620970586)",
    ),
    "diagnosticity": (
        "Diagnosticity",
        "[Platt (1964)](https://doi.org/10.1126/science.146.3642.347), "
        "[Fiedler (2017)](https://doi.org/10.1177/1745691616654458)",
    ),
    "formalisation": (
        "Formalisation",
        "[Robinaugh et al. (2021)](https://doi.org/10.1177/1745691620974697), "
        "[Guest & Martin (2021)](https://doi.org/10.1177/1745691620970585)",
    ),
    "derivation_chain": (
        "Derivation chain",
        "[Scheel et al. (2021)](https://doi.org/10.1177/1745691620966795), "
        "[Szollosi et al. (2020)](https://doi.org/10.1016/j.tics.2019.11.009)",
    ),
}

spec = checklist()
items = spec["items"]
ids = [item["id"] for item in items]
unnamed = [i for i in ids if i not in CHECKS]
dropped = [i for i in CHECKS if i not in ids]
if unnamed or dropped:
    raise RuntimeError(
        "the table of rigour checks does not match the checklist: "
        f"no name for {unnamed}, no check for {dropped}"
    )
print("| Rigour check | Criterion | Weight | Supporting work |")
print("|---|---|---|---|")
for item in items:
    name, works = CHECKS[item["id"]]
    weight = f"{item['weight']:g}"
    if item["severity_if_fail"] == "blocker":
        weight += ", blocker"
    print(f"| {name} (`{item['id']}`) | {item['criterion']} | {weight} | {works} |")
```

```python exec="1" session="methodology"
# Every value the prose quotes is computed here when the page is built, from the
# checklist file read above and the example theories the package ships, so the
# text cannot drift from the code. The R article computes the same values.
import math

import theoryforge as tf

def g(x):
    return f"{x:g}"

def f1(x):
    return f"{x:.1f}"

def f2(x):
    return f"{x:.2f}"

def f3(x):
    return f"{x:.3f}"

def d(x):
    """A value with at most three decimals and at least one, as 1.0 or 0.25."""
    text = f"{x:.3f}".rstrip("0")
    return text + "0" if text.endswith(".") else text

thr = spec["thresholds"]
# The three items that can have nothing to assess. The others always apply.
min_coverage = math.fsum(item["weight"] for item in spec["items"]
                         if item["id"] not in ("non_redundancy", "derivation_chain", "parsimony"))
panic_report = tf.check(tf.read(tf.example_path("panic-network.theory.yaml")))

weak_pair = tf.redundancy_check(tf.read(tf.example_path("weak-theory.theory.yaml")))[0]

# A one-sided claim with an estimate two standard errors inside its bound.
one_sided = tf.new_theory(id="one-sided", title="A one-sided claim")
one_sided.add_prediction(id="h", statement="The effect is above zero.", type="directional",
                         bounds={"lower": 0})
one_sided.add_test_outcome(prediction_id="h", passed=True, estimate=2.0, se=1.0)
severity_normal = tf.post_data_severity(one_sided)[0]["severity"]

def t_cdf(x, df, n=2000):
    """The t distribution function at x > 0, by Simpson's rule on the density."""
    c = math.gamma((df + 1) / 2) / (math.sqrt(df * math.pi) * math.gamma(df / 2))
    h = x / n
    total = 0.0
    for i in range(n + 1):
        weight = 1 if i in (0, n) else (4 if i % 2 else 2)
        total += weight * c * (1 + (i * h) ** 2 / df) ** (-(df + 1) / 2)
    return 0.5 + total * h / 3

severity_t10 = t_cdf(2.0, 10)

# The last construct of a five-construct chain at the default gain and damping.
chain = tf.new_theory(id="chain", title="A causal chain")
chain_ids = [f"c{i}" for i in range(1, 6)]
for cid in chain_ids:
    chain.add_construct(id=cid, label=cid, definition=f"Construct {cid}")
for i in range(4):
    chain.add_proposition(id=f"p{i + 1}", frm=chain_ids[i], to=chain_ids[i + 1],
                          relation="increases")
chain_run = tf.simulate(chain, steps=100, method="exact")
chain_peak = max(row[4] for row in chain_run["trajectory"])

# The panic network at the default gain and damping, propagated by the exact
# method. The prose says that every state reaches one value, so the build stops
# if the states part at one decimal.
panic_run = tf.simulate(tf.read(tf.example_path("panic-network.theory.yaml")),
                        steps=100, method="exact")
panic_end = max(panic_run["trajectory"][-1])
if f1(min(panic_run["trajectory"][-1])) != f1(panic_end):
    raise RuntimeError("the states of the panic network no longer end at one value")
panic_time = panic_run["steps"] * panic_run["dt"]
```

## How the rigour score is computed

Each item returns a status, `pass`, `warn` or `fail`, and a score between 0 and 1. An item that checks whether something is present scores 1 or 0, and one that measures a share, such as the share of constructs with a definition, a measurement and boundary conditions, scores that share. Some items pass with a score below 1: predictive precision and prediction severity at the thresholds given below, and diagnosticity once a single prediction qualifies. An item with nothing to assess has the status `n/a` and no score. That is the case for construct non-redundancy when the theory has fewer than two constructs, for the derivation chain when it has no predictions and for parsimony when no auxiliary assumption is declared as added for an anomaly.

```python exec="1" session="methodology"
print(f"""This page describes version {spec['schema_version']} of the checklist, the version every report records as `checklist_version`. The checklist file fixes the thresholds. Predictive precision passes when the share of bounded point and interval predictions reaches {g(thr['min_precision_share'])}, and prediction severity when the mean riskiness of the predictions reaches {g(thr['min_severity'])}. The redundancy screen flags a pair of definitions at a Jaccard similarity of {g(thr['redundancy_similarity_max'])} or an overlap coefficient of {g(thr['redundancy_overlap_max'])}, and the optional embedding screen flags a pair at a cosine of {g(thr['embedding_similarity_max'])}.""")
```

```python exec="1" session="methodology"
print(f"""The aggregate score is the weighted mean of the applicable items' scores, multiplied by 100, with the weights of the table above. The report also gives the coverage, the share of the checklist's weight that was applicable. The items other than the three that can have nothing to assess always apply, so the coverage is at least {g(min_coverage)}, and the panic-network example, in which parsimony alone has nothing to assess, has a coverage of {g(panic_report['coverage'])}. Leaving such an item out keeps a theory from scoring for what it lacks, so a theory with no content scores 0. The aggregate is compensatory, in that a high score on one item offsets a low score on another.""")
```

```python exec="1" session="methodology"
print(f"""The weights are a convention, so the report also gives `aggregate_range`, the lowest and highest aggregate under other weightings: equal weights, and each applicable item's weight halved and doubled in turn with the others unchanged. The panic-network example has an aggregate of {f1(panic_report['aggregate_score'])}, with a range of {f1(panic_report['aggregate_range'][0])} to {f1(panic_report['aggregate_range'][1])}. The range shows how far the aggregate depends on the choice of weights.""")
```

The gate is the one-word verdict, and it is not compensatory. The two items marked as blockers in the table, falsifiability and the derivation chain, decide it: the gate is `blocked` when either fails and `pass` otherwise. A theory at the `draft` maturity stage is always `advisory`, so the blockers inform without gating early work. A failed blocker counts in the aggregate like any other item, so a blocked theory can outscore one whose gate passes.

Predictive precision, prediction severity and diagnosticity are shares or means over the predictions, so they describe the profile of a theory's claims and not their total content. Adding a vague prediction to a set of precise ones lowers them, although the theory then forbids at least as much as it did. Comparing the content of two versions of a theory is the work of the amendment appraisal, which reads what an amendment adds and what it gives up.

## What each item checks

### The form of the predictions

Falsifiability passes when at least one prediction is a point, interval or directional claim, and so forbids some observation. Predictive precision is the share of predictions that are point or interval claims whose `bounds` state a finite lower and a finite upper value. A point or interval label without the region it claims does not count, since a label alone states nothing that a test could miss.

Prediction severity averages one value per prediction, its declared `severity` where it has one and otherwise the value of the claim-form rubric described below. With no predictions, it warns with a score of 0. A declared value is taken as given, and the dossier prints it beside the rubric's value. The rubric reads the same type label as predictive precision and the same named rival as diagnosticity, so a prediction without a declared severity is credited for those features twice. The item grades claims before any data. How severely a claim has been tested depends on the design and the data, which `post_data_severity()` reads and no item does.

### Derivation and rivals

The derivation chain is the share of predictions that cite at least one proposition in `derives_from`, cite only declared propositions and state no claim that the causal graph contradicts or leaves undetermined. It passes only at 1 and fails otherwise, and with no predictions it is `n/a`. A prediction without a machine-readable claim is judged on its references alone, so for such a prediction the item shows that its citations resolve and not that it follows from them.

Diagnosticity is the share of predictions that name, in `diagnostic_vs`, a registered alternative they discriminate from, and it passes once one prediction does. Where the prediction states a claim and the alternative states propositions of its own, the declaration is checked, and it is shown false when the claim gets the same verdict under the rival's causal graph as under the theory's. Where either is missing, or the theory's graph cannot evaluate the claim, the declaration counts as given. The rubric's bonus for a named rival rests on the declaration alone.

### Constructs

Construct non-redundancy passes when every construct's definition holds at least one content word and the redundancy screen flags no pair, and it warns with a score of 0 otherwise. A construct without a definition cannot be screened, so deleting the definitions of a redundant pair cannot raise the score. The screen, described below, flags near-duplicate definitions, a definition contained in another, two constructs with one label and a construct with no measure of its own.

Construct clarity is the share of constructs that carry a definition, a measurement and boundary conditions, and passes only at 1. Scope passes when boundary conditions are stated, either for the theory or on every construct.

### Propositions and the formal model

Mechanism is the share of propositions that fill in their `mechanism` field, the reason the relation holds, and passes only at 1. With no propositions, it warns with a score of 0. Causal testability passes when at least one proposition states one of the five directed relations, `increases`, `decreases`, `causes`, `mediates` or `moderates`. It checks only that such a relation is present, and the causal reading described below says what the relations imply and which of their directions data could test. Formalisation passes when the theory declares a formal model of a recognised type, `ode`, `abm`, `network` or `sem`.

### Auxiliary assumptions

Parsimony assesses only the auxiliary assumptions declared as added in response to an anomaly, those whose `added_for` names the prediction they answer. Despite its name, the item tests whether these assumptions are ad hoc and does not count assumptions. Such an assumption is ad hoc when no prediction it protects, other than that anomaly, is corroborated (Lakatos, 1970). The item fails if any of them is ad hoc and passes otherwise, and with no such assumption it is `n/a`. Core assumptions do not count against a theory, since every derivation relies on auxiliaries (Meehl, 1990a) and declaring them makes the protective belt visible.

The checklist has no prior version to compare with, so it cannot tell an assumption made before a test from one made after it. It therefore leaves an assumption without `added_for` unassessed, and every prediction an assessed assumption protects counts as support. The amendment appraisal is the stricter check, since it infers the anomaly that an undeclared addition answers and counts only predictions that are new in the amended version.

## Validation of claims and fields

Full validation, `validate(full=True)`, adds checks to the structural pass, and two of them concern how a theory is written down. The first compares each prediction's type and stated sign with its bounds, a comparison the schema cannot express. A point or interval prediction needs a finite lower and a finite upper bound. A directional prediction with two finite bounds needs one of them at 0, so that the region states a sign, as `[0, 1]` does for a correlation. An existence prediction must leave one side of its region open. A claimed positive sign needs a lower bound of 0 or above, a negative sign an upper bound of 0 or below, a zero sign a region that includes 0 and a nonzero sign a region that excludes it. Without this check, the rubric, the precision item and the causal reading could describe a different claim from the one whose test `post_data_severity()` reads. A recorded pass whose estimate lies outside the bounds is not refused, and the dossier notes it beside the outcome.

The second reports every field of an entry that the schema does not list, as the schema's closed entries require, with the nearest known field when one lies within two edits, so that a misspelt `derives_form` is reported where it would otherwise be ignored. A field whose name begins with `x_` carries extension metadata and is allowed, which is how `read_dagitty()` marks a latent variable.

## The causal graph and its implications

Every function that reads the causal structure builds one graph from the propositions. Each directed relation is an arrow from its `from` construct to its `to` construct, and an association is a bidirected edge, a covariance the theory leaves unexplained, such as a latent common cause of the two would produce. A construct that no proposition relates to another is left out, since silence about a construct is no claim that it is independent of anything.

`implications()` lists the conditional independencies the graph implies by m-separation, the reading of d-separation for graphs with bidirected edges (Richardson, 2003). For each pair of constructs that no edge joins, it tries two conditioning sets in turn, the parents of both and then all their other ancestors, and records the first that separates the pair. In a graph of directed edges alone, the first always succeeds. With bidirected edges, holding a parent fixed can open a path on which that parent is a collider. When neither set separates a pair, no set does, since the two are joined by an inducing path (Richardson & Spirtes, 2002), and the pair is listed under `inseparable`.

In a graph of directed edges alone, the statements form the basis set of Shipley (2000). When the model holds, their tests are independent of each other, so that Shipley's C statistic combines them into one test of the whole model. When the distribution has the property called composition, as a multivariate normal distribution does, the basis set implies every other independence the graph entails. Under composition, a construct that is independent of each of two others, given the same set, is independent of the two together.

With `given="minimal"`, each conditioning set is then pruned: a member is dropped when the set without it still separates the pair. The result is minimal, in that none of its members can be dropped, though other minimal sets may exist and the order of the constructs decides which is returned. A minimal set holds fewer constructs, and so fewer constructs measured with error. Error in a conditioning construct leaves part of the dependence that holding it fixed should remove, so a conditional statement tested on observed scores is rejected too often (Westfall & Yarkoni, 2016). Minimal sets suit tests of single pairs, but they no longer form a basis set: their tests need not be independent of each other, so they are not combined into one test of the model as the basis set's are.

```python exec="1" source="block" result="text" session="methodology"
import theoryforge as tf

M = tf.read(tf.example_path("modality-switching.theory.yaml"))
for given in ("basis", "minimal"):
    print(given)
    for s in tf.implications(M, given=given)["implications"]:
        print("  " + s["statement"])
```

A theory whose directed relations form a feedback loop is refused by default, since a model with feedback is guaranteed to satisfy d-separation only in special cases, linear models among them (Bongers et al., 2021). With `cycles="sigma"`, the graph is read by sigma-separation instead. Each feedback loop is replaced by its acyclification, in which every member of the loop takes the loop's outside causes and the members are joined to each other, and m-separation in the acyclification is sigma-separation in the theory's graph (Bongers et al., 2021). The statements then hold in every model with that graph whose feedback loops each settle to a unique equilibrium. A theory that posits alternative stable states, such as a bistable symptom network, does not meet that condition, and its statements are not guaranteed. DAGitty accepts a cyclic graph and reads it by d-separation without a warning. For the graph x → y ⇄ z ← w, it treats x and w as independent given y and z, a statement that sigma-separation does not support.

## The causal reading of claims

A prediction, or a phenomenon the theory sets out to explain, may state its claim in machine-readable form, as a `claim` with a `kind`, two constructs `x` and `y`, an optional `given` and a `sign`. An `effect` claim concerns the total effect of `x` on `y`, how `y` responds when `x` is set by intervention. An `association` claim concerns the dependence between the two, given the constructs in `given` when there are any. The sign is `positive`, `negative`, `zero` or `nonzero`. `entailments()` reads each claim against the causal graph and says whether the graph entails it, contradicts it or leaves it undetermined.

The derivation follows the path-tracing rules of a linear structural model (Wright, 1934). An effect is the sum, over the directed paths from cause to outcome, of the products of the coefficients along them, and a covariance is the sum over the treks between the two constructs, a trek being a pair of directed paths from a common source. When every term has the same sign, so does the sum, whatever the sizes of the coefficients, and with no term the quantity is zero. The sign of an edge comes from its relation: `increases` is positive and `decreases` negative, while `causes`, `mediates` and `moderates` state no sign. A route through an edge without a sign leaves the sign of the quantity undetermined, and so do routes of opposite signs.

An intervention on `x` replaces the equation of `x` and so cuts every edge into it. On a graph with feedback loops, read by sigma-separation, a walk that returns to `x` round a loop therefore carries nothing to `y`, and the effect takes the sign of the walks that avoid `x`. When `x` lowers `y` and `y` raises `x`, for instance, the effect of `x` on `y` is negative. For an association with no `given`, the derived sign combines the signs of all the treks between the two constructs, and an association edge between their ancestors adds a route of unknown sign, since it stands for a common cause whose effects the theory leaves unsigned. For an association with a `given`, the derived value is zero when the constructs in `given` separate the two in the graph and nonzero otherwise.

A derived zero entails a claimed zero and contradicts any other sign, and any other derived value contradicts a claimed zero. A claimed `nonzero` is entailed by a derivation other than zero, a claimed sign is entailed by the same derived sign and contradicted by the opposite one, and an undetermined derivation leaves a signed claim undetermined. A claim that names a construct outside the graph, or one on a graph with a feedback loop while cycles are refused, is not evaluated. Some verdicts rest on faithfulness, the assumption that contributions do not cancel exactly. A route of no fixed sign, routes of opposite signs and a connecting path make two constructs dependent only when their contributions do not sum to zero, and the record marks such verdicts with `faithfulness`.

For an effect claim on a graph without feedback loops, the record also says whether adjusting for some set of the theory's constructs identifies the effect from observational data, and gives a smallest such set, or the full canonical set when that holds more than 12 constructs, by the criterion of van der Zander et al. (2019). An association between `x` and `y` leaves the effect unidentified. No set is given for a graph with a feedback loop, since the criterion is not established there.

A derived sign holds in a linear structural model with the graph, or at least in one in which each relation acts in the same direction throughout (VanderWeele & Robins, 2010), and in which no common cause of two constructs is left out unless an association stands for it. On a graph with feedback loops, each loop is also assumed to settle to a unique equilibrium, and the signs read off walks round a loop assume that the effects round it die out. The derivation chain of the checklist reads these verdicts, and the preregistration and the dossier write each claim and its verdict in words.

```python exec="1" source="block" result="text" session="methodology"
for c in tf.entailments(M)["claims"]:
    print(c["id"], c["kind"], c["x"], c["y"], c["sign"], "->", c["verdict"], c["basis"])
```

## Equivalent models and rivals

Two causal graphs that imply the same conditional independencies are Markov equivalent, and no observational study can tell them apart (Verma & Pearl, 1990/2022). Two acyclic graphs of directed edges are Markov equivalent exactly when they have the same skeleton, the edges without their directions, and the same unshielded colliders, the triples `a -> c <- b` in which no edge joins `a` and `b`. `equivalent_models()` marks each edge of the theory as compelled, when it points the same way in every equivalent graph, or reversible, when some equivalent graph reverses it. The compelled edges are those of the essential graph (Andersson et al., 1997), found by orienting edges outwards from the unshielded colliders until no rule applies. Testing the direction of a reversible edge needs an intervention, a temporal order or some other assumption. In structural equation modelling, this is the problem of equivalent models (MacCallum et al., 1993). The rule holds for graphs of directed edges alone, so the function reports that it does not apply to a graph with a feedback loop or an association.

```python exec="1" source="block" result="text" session="methodology"
for e in tf.equivalent_models(M)["edges"]:
    print(", ".join(e["propositions"]), e["from"], "->", e["to"], e["status"])
```

A rival account can be stated as propositions of its own over the theory's constructs, in an alternative's `propositions`, or as a separate theory. `discriminate()` reads the two graphs side by side. It lists the conditional independencies that hold in one graph and fail in the other, the effects and marginal associations whose derived signs differ, marked as decisive when both signs are fixed, and the claims that one graph entails and the other contradicts. Each of these is a test that could tell the two accounts apart. When the two graphs hold different constructs and are acyclic, each is first projected onto the constructs they share, with the others treated as latent, which keeps the separations among the shared constructs (Verma & Pearl, 1990/2022). When both graphs are acyclic, hold the same constructs and state no association, the record also says whether they are Markov equivalent, in which case no observational test of independence separates them. The diagnosticity item reads the same comparison for the claims of the predictions.

```python exec="1" source="block" result="text" session="methodology"
for rival in ("alt_grounding_by_interaction", "alt_symbol_interdependency"):
    print(rival, tf.discriminate(M, rival)["counts"])
```

## Riskiness before the data and severity after it

Every prediction declares one of four types, and the rigour checklist and the claim-form rubric read that label. An existence prediction asserts that an effect or relation exists, without a direction. A directional prediction asserts a sign or an order, which covers comparisons, interactions, the invariance of a direction across groups and claims that an effect occurs only when a condition holds. An interval prediction asserts that a quantity lies in a stated range, the range the theory permits. A point prediction asserts one value, with the tolerance that measurement requires, and that width is measurement tolerance rather than latitude the theory allows, which separates it from an interval. The labels are self-declared, and full validation checks them only against the bounds.

`severity()` grades the form of each prediction's claim before any data. Each type has a base value, reported as `risk_score`. A directional prediction is then discounted, following Meehl's (1967, 1990b) argument that a sign alone risks little where almost everything correlates a little, and a prediction that names a registered alternative in `diagnostic_vs` gains a bonus, with the result capped at 1. The table gives the values the rubric computes for each type.

```python exec="1" session="methodology"
rubric = tf.new_theory(id="rubric", title="Claim forms")
rubric.add_alternative(id="rival", label="A rival account")
claim_types = ["existence", "directional", "interval", "point"]
for t in claim_types:
    rubric.add_prediction(id=t, statement="A claim.", type=t)
    rubric.add_prediction(id=f"{t}_rival", statement="A claim.", type=t, diagnostic_vs=["rival"])
graded = {r["prediction_id"]: r for r in tf.severity(rubric)}
print("| Type | Base value (`risk_score`) | Computed severity | With a named rival |")
print("|---|---|---|---|")
for t in claim_types:
    print(f"| {t} | {d(graded[t]['risk_score'])} | {d(graded[t]['computed_severity'])} "
          f"| {d(graded[t + '_rival']['computed_severity'])} |")
```

The order of the four types follows Popper's (1959/2005, sections 31–33) comparison of falsifiability, by which, of two nested claims about one quantity, the one that forbids more is the more falsifiable. The base values, the discount and the bonus are the package's conventions, and neither Popper nor Meehl gives them. The sizes of ambient correlation that Meehl (1990b) mentions, .25 and .30, are a different quantity from the discount. The rubric also applies one scale to predictions about different quantities, where Popper's comparison ranks only nested claims about one. Despite the name `computed_severity`, the rubric reads only the declared type and the named alternatives, so it says nothing about how severely a claim has been tested.

`post_data_severity()` reads what the rubric leaves out. A prediction may state, in `bounds`, the region its claim allows, a `lower` and an `upper` value, either of which may be left open. A test outcome may record the `estimate` the test observed and its standard error `se`. For a claim with one finite bound, such as an effect above a smallest effect of interest, the function gives the severity with which the claim passed, SEV in the sense of Mayo and Spanos (2006, 2011). It is the probability that the test would have produced a result less in accord with the claim had the quantity been at the bound, computed as `Φ((estimate − lower) / se)` for a lower bound and `Φ((upper − estimate) / se)` for an upper one, where Φ is the standard normal distribution function.

Mayo and Spanos give no rule for a claim with two finite bounds. For such a claim, the function returns the smaller of the two one-sided values, which is the package's own extension to the conjunction of the two one-sided claims. It equals 1 minus the p value of the two one-sided z-tests of equivalence (Lakens, 2017), since that p value is the larger of the two one-sided p values. A point claim, whose two bounds coincide, can therefore pass with a severity of at most one half, so it needs a tolerance around its value. The table gives the severity of a claim that a correlation lies between −0.10 and 0.10, tested with an estimate of 0 at three standard errors. The rubric gives the claim the same value whatever the test.

```python exec="1" session="methodology"
bounded = tf.new_theory(id="bounded", title="A bounded claim")
bounded.add_prediction(id="h", statement="The correlation lies between -0.10 and 0.10.",
                       type="interval", bounds={"lower": -0.1, "upper": 0.1})
for se in (0.01, 0.1, 0.2):
    bounded.add_test_outcome(prediction_id="h", passed=True, estimate=0.0, se=se)
print("| Standard error | Severity |")
print("|---|---|")
for row in tf.post_data_severity(bounded):
    print(f"| {f2(row['se'])} | {f3(row['severity'])} |")
```

```python exec="1" session="methodology"
print(f"""The computation treats the standard error as known and the sampling distribution of the estimate as normal. When the standard error is estimated from a small sample, the estimate follows a t distribution, whose tails are heavier, and for an estimate inside the region the normal value is the higher of the two. An estimate two standard errors inside a one-sided bound gets a severity of {f3(severity_normal)}, where a t distribution with 10 degrees of freedom gives {f3(severity_t10)}, so the function overstates the severity in small samples. The rigour checklist does not read the value, and the dossier gives it in the test record. In the modality-switching example, an illustrative outcome tests the interval claim of `pred2`, and the value equals 1 minus the larger of the two one-sided p values.""")
```

```python exec="1" source="block" result="text" session="methodology"
from statistics import NormalDist

row = tf.post_data_severity(M)[0]
phi = NormalDist().cdf
p_lower = 1 - phi((row["estimate"] - row["lower"]) / row["se"])
p_upper = phi((row["estimate"] - row["upper"]) / row["se"])
print(row["prediction_id"], row["severity"], round(1 - max(p_lower, p_upper), 3))
```

A prediction may also record the sampling plan of its test in a `test` block. The block holds the planned sample size and what it counts, alpha and whether the test is one- or two-sided, and the smallest effect of interest and its scale. It also holds the planned power or decision probability, with an interval and the method that gave it, a reference to the design analysis and a justification. A Stage 1 Registered Report asks for such a plan for each hypothesis. The preregistration lists the plans after the hypotheses, and no function scores them or recomputes the stated power. As the precision of a test grows, the probability of a significant difference in the predicted direction approaches one half even when the theory is false (Meehl, 1967), so power must not raise a claim's severity. Power does decide how informative a failed prediction is, since a test unlikely to detect the smallest effect of interest says little when it misses that effect (Lakens, 2022).

## The redundancy screen

The lexical screen, `redundancy_check()`, reduces each construct definition to a set of content words. The text is first folded by a table that the R and Python packages share. Accented Latin letters go to their ASCII base (`é` to `e`, `ß` to `ss`), Greek and Cyrillic letters to unaccented lower case, and ASCII letters are lowercased. The text is then split on anything that is not a letter, mark or digit in any script, and words shorter than three characters or in a short English stop-word list are dropped. Other scripts are compared as written, so case, accents and the Unicode normalisation form count there, and text written without spaces, such as Chinese, forms one token per run.

```python exec="1" session="methodology"
print(f"""For each pair of constructs, the screen gives the Jaccard index of their word sets, the size of the intersection over the size of the union, and the overlap coefficient, the size of the intersection over the size of the smaller set. It flags a pair for review for any of four reasons. A Jaccard index at the threshold marks a near-duplicate, and an overlap coefficient at its threshold marks a definition contained in another, when both definitions hold at least three words. Two constructs with the same label, compared after folding, are a jingle. When every measure of one construct is listed for the other, the two cannot be told apart by data from those measures. Constructs that share a method or an inventory and keep measures of their own, as in a multitrait-multimethod design (Campbell & Fiske, 1959), are not flagged. The two motivation constructs of the weak example are flagged as contained: one definition adds 'towards goals' to the other, so their similarity is {g(weak_pair['similarity'])} and their overlap {g(weak_pair['overlap'])}.""")
```

The screen compares words, so it cannot detect empirical redundancy. Two constructs that correlate almost perfectly once measurement error is corrected for may be defined in different words (Le et al., 2010), and assessing that needs data (Rönkkö & Cho, 2022). Sibling constructs may share vocabulary without being redundant (Lawson & Robins, 2021), and the screen can flag them. `embedding_redundancy()` compares definitions by the cosine of embedding vectors from a function the user supplies. It is the one step of the package that depends on a model, so its values change with the embedding model and its version, and its `threshold` argument is best set for the model in use. No checklist item reads it.

## The amendment appraisal

`appraise_amendment()` compares an amended theory with a prior version by what the two claim, not by the identifiers of their predictions. Lakatos (1970, p. 118) calls a problemshift progressive when the new theory predicts a fact its predecessor did not and some of that excess content is corroborated, and degenerating when it is not. The appraisal turns this into rules. A prediction that changed only its identifier is reported as renamed and is not new. A new prediction derived only from propositions the prior already held, with the same endpoints and relation, articulates old content, and so does a new prediction whose claim the prior's causal graph already entails, however it is derived. A new auxiliary assumption is new content, so a prediction it protects is not an articulation. A new prediction that cites no proposition, or one its version lacks, adds no content. A prediction is corroborated when at least one test outcome passes it and none fails it, so a failed replication leaves it mixed.

An assumption added in response to an anomaly names the prediction it answers in `added_for`. An assumption that leaves `added_for` empty but protects a prediction that failed in the prior is taken to answer that prediction, so leaving the field out does not exempt it. Such an assumption is ad hoc unless a prediction it protects that is new in this version, other than the anomaly, is corroborated, since accommodating the anomaly is no independent support.

A prediction kept from the prior is reported as revised when its statement, type, bounds or claim changed. It is weakened when its type ranks lower, its bounds allow a wider region, or its claim is dropped or gives up a fixed sign for `nonzero`, and nothing in it is stronger. The appraisal also compares the conditional independencies that the two causal graphs imply, read by sigma-separation, and reports those the amendment gives up and those it adds. Lakatos (1970, p. 118) considers series in which 'each theory [has] at least as much content as the unrefuted content of its predecessor'. Content is therefore lost when an untested prediction is dropped or weakened, or when an implication is given up that no failed prediction of the prior contradicts.

The verdict is progressive when a corroborated new prediction adds content, no content is lost, no assumption is ad hoc, no corroborated prediction was dropped and no failed prediction was weakened. It is degenerating when an assumption is ad hoc or a failed prediction was weakened, and no corroborated prediction adds content. Lakatos's scheme is a dichotomy, and 'neutral' is the package's label for an amendment that meets neither rule. The lists returned tell the neutral cases apart, and two flags report whether some new prediction adds content (`theoretically_progressive`) and whether one of these is corroborated (`empirically_progressive`). New failures of retained predictions (`new_anomalies`) are reported without changing the verdict, and so are the corroborations that were preregistered (`corroborated_new_registered`). The appraisal reads no date and no `version` field, so which version is the prior is the caller's responsibility.

## The literature layer

`landscape()` sets the theory against a literature corpus and labels each theme by how many of the theory's accounts match it, counting the focal theory and each registered alternative once. An account matches a theme when a word of its construct labels, or of an alternative's label and key constructs, appears among the theme's keywords, and the result lists the words that matched. Three kinds of word never match. Words carried by more than the share `max_token_share` of the records belong to the whole field. Words of the theory's title name the phenomenon that every account explains, so a construct word that also appears in the title does not match. Words such as 'theory', 'model' and 'account' name a kind of account.

A theme that no account matches is 'under-theorised', one that a single account matches is 'covered', and one that two or more match is 'crowded'. The match is lexical, so it shows a word in common and not that the account explains what the theme's records report. An under-theorised theme may therefore be addressed by an account the theory does not register, or by one that names the same idea in other words. A crowded theme may call for predictions that discriminate between its accounts, and does not show that they compete or that any of them is redundant.

By default, `litmap()` takes the themes to be the connected components of the keyword co-occurrence graph. On a real corpus, one or a few keywords carried by most records join nearly every keyword into one component, and the function warns when one theme holds more than half of ten or more linked keywords. The simple-centres method of co-word analysis (Coulter et al., 1998; Cobo et al., 2011) bounds each theme instead. It weights each pair of keywords by its equivalence index, the square of their co-occurrence count over the product of their frequencies, and grows each theme from its strongest remaining link up to `max_theme_size` keywords. Each theme is then placed in the strategic diagram by its centrality, the strength of its links to other themes, and its density, the strength of the links within it (Callon et al., 1991).

The strategic diagram splits each measure at its median over the themes. A theme is high on a measure when its value lies above the median, or equals it when the median is also the highest value, so that when more than half the themes share the highest value, those themes are high and the rest low. A theme is `motor` when it is high on both, `basic` when high on centrality alone, `niche` when high on density alone and `emerging_or_declining` when low on both. A theme with no links to other themes has a centrality of 0 and is never central. When every theme has the same value of either measure, that measure cannot be split, and no theme is given a quadrant. The quadrants place a theme relative to the other themes of the same corpus, so they change with the corpus and say nothing of a theme's standing in the field at large.

## The simulation

`simulate()` makes each construct a state variable. Each proposition whose relation is `increases`, `decreases`, `causes` or `mediates` contributes a coupling between two states, scaled by the gain `k`, with the sign the relation table gives. `causes` and `mediates` state no sign, so the simulation takes them as positive and lists them under `assumed_positive`, since that choice alone can decide whether a feedback loop grows or settles. `moderates` and `associates` couple nothing, and the `functional_form` field is not read. Every state also decays towards zero at the damping rate. All states start from a common value unless `init` gives the starting values of some constructs, the others starting from zero, so that one construct can be perturbed and the response of the rest traced. From a common value, constructs with the same incoming couplings follow the same trajectory.

```python exec="1" session="methodology"
print(f"""The simulation is a transparent linear system, meant to expose the qualitative dynamics a network of propositions implies and not to fit data. A linear system has one equilibrium, or a continuum of them, and never two separate ones, so it cannot show the bistability that formal models of panic disorder rely on (Robinaugh et al., 2024). A network without directed cycles decays at the damping rate in the long run, though not in its transients. Propagated by the exact method at the default gain and damping, the last construct of a five-construct chain rises to {f2(chain_peak)} times its starting value before it decays. The regime of a theory with feedback loops is set by the gain against the damping. In the panic-network example, propagated in the same way, the loop between arousal and perceived threat grows, and every state reaches {f1(panic_end)} by time {g(panic_time)}.""")
```

Two methods propagate the system. The exact method multiplies the state at every step by the matrix exponential of the system matrix times the step size, computed by scaling and squaring a Taylor polynomial (Moler & Van Loan, 2003), so each row is the solution at its time whatever the step size. The Euler method, the default, takes fixed explicit steps. Its step is stable only when `|1 + dt·λ| < 1` for every eigenvalue `λ` of the coupling matrix minus the damping. In a network without directed cycles, the states therefore diverge with alternating sign once the step size times the damping exceeds 2, although the system they approximate decays, and raising the damping can cause a divergence rather than remove it. Euler steps also turn a sustained oscillation into growth, so a run warns when its trajectory departs from the exact one by more than 5 per cent. Passing `method="exact"` avoids both problems.

## The content hash

`content_hash()` identifies a theory by the SHA-256 digest of its canonical form, written as `sha256:` followed by 64 hexadecimal digits. The canonical form is the JSON Canonicalization Scheme (Rundgren et al., 2020), with three conventions that make it the same in R and Python: an empty mapping is written as an empty sequence, a number that is not finite is written as a word, and a single value in a field that the schema types as an array of strings is written as a one-element array, since `derives_from: p1` reads as `[p1]`. Two files with the same content therefore have the same hash whatever their layout, comments, key order or format, and any change to a value changes it. The key `content_hash` of `version` is left out, so that a file can record the hash of its own content, and full validation checks a recorded hash against the content. The preregistration and the dossier give the hash, so that a reader can check that the theory file in hand is the one they describe. The hash shows that two files hold the same theory and says nothing about when either was written, which a time-stamped registration records.

```python exec="1" source="block" result="text" session="methodology"
import os
import tempfile

path = os.path.join(tempfile.mkdtemp(), "modality-switching.json")
tf.write(M, path)
print(tf.content_hash(M))
print(tf.content_hash(tf.read(path)) == tf.content_hash(M))
```

## Reading DAGitty diagrams

`read_dagitty()` reads model code as DAGitty writes it (Textor et al., 2016) and returns a theory whose constructs are the diagram's variables and whose propositions are its edges. A directed edge becomes a proposition with the relation `causes`, or `increases` or `decreases` when the `relation` argument gives that sign to every edge, and a bidirected edge becomes an association. A variable marked `latent` keeps the mark as `x_latent`, and the `causal_dag` view of `diagram()` writes it back, so a diagram read and written again keeps its variables' marks, its directed edges and its associations. Positions and other attributes are dropped.

The reader refuses what a theory cannot hold. An ancestral graph (`mag` or `pag`) has edge marks with no counterpart among the relations, an undirected edge states no direction, and a selected variable is held fixed by selection, which opens paths that the theory's implications would not show. A diagram states no definitions, so the theory it gives is a draft that does not pass validation until each construct is defined. A latent construct remains a construct whose relations the theory states, and a statement that holds it fixed needs a measure of it before data can test it.

```python exec="1" source="block" result="text" session="methodology"
G = tf.read_dagitty("""
dag {
  stress [latent]
  sleep -> stress -> mood
  exercise -> stress
  sleep <-> mood
}
""", id="sleep-mood", title="Sleep, stress and mood")
for p in G.data["propositions"]:
    print(p["id"], p["from"], p["relation"], p["to"])
for s in tf.implications(G)["implications"]:
    print(s["statement"])
print(tf.diagram(G, "causal_dag"))
```

## Scope and limits

The checklist is a structural and lexical screen. Each item asks whether a required property is present in the theory object, such as a boundary-conditions field or a mechanism string, or what share of a collection has it, and the redundancy screen measures the overlap of words between definitions. No item judges the content of a definition, a mechanism or a boundary condition. A theory can score highly by being completely and precisely specified while resting on a false premise, and poorly for being under-specified while resting on a sound one. The aggregate score indexes how completely a theory is specified against the checklist, and says nothing about whether the theory is true or well reasoned.

The thresholds and weights are the package's defaults, fixed in the checklist file and not derived from an external validation study. Two scores with the same `checklist_version` were computed by the same rule, and a difference between them reflects how the two theories are specified. Much of that specification is self-declared, such as the type of each prediction, its named rivals and the outcomes of its tests, and no study has yet measured how far two coders would agree on it. The package offers no option to substitute other weights or thresholds, apart from the `threshold` of the embedding screen, which no item reads. A field with different norms can recombine the per-item scores the report lists, and the result is then not comparable with the default aggregate.

The gate reflects only the blockers, so a theory can show `gate: pass` while several other items are `warn` or `fail`. The gate reports a minimal precondition for testing, and the items give the rest, so the two are best read together with the aggregate score and its range.

The causal reading takes the propositions as stated. Its verdicts say what the stated graph implies under the assumptions given above, and the implied independencies, signs and equivalences are hypotheses for data to test. The package does not test them. That needs an estimate from data, which `post_data_severity()` can then read, or a test of the implied independencies, which other tools provide (see [Related tools](related-tools.md)).

## References

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Andersson, S. A., Madigan, D., &amp; Perlman, M. D. (1997). A characterization of Markov equivalence classes for acyclic digraphs. <em>The Annals of Statistics</em>, <em>25</em>(2), 505–541. <a href="https://doi.org/10.1214/aos/1031833662">https://doi.org/10.1214/aos/1031833662</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Bacharach, S. B. (1989). Organizational theories: Some criteria for evaluation. <em>The Academy of Management Review</em>, <em>14</em>(4), 496–515. <a href="https://doi.org/10.5465/amr.1989.4308374">https://doi.org/10.5465/amr.1989.4308374</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Bongers, S., Forré, P., Peters, J., &amp; Mooij, J. M. (2021). Foundations of structural causal models with cycles and latent variables. <em>The Annals of Statistics</em>, <em>49</em>(5), 2885–2915. <a href="https://doi.org/10.1214/21-AOS2064">https://doi.org/10.1214/21-AOS2064</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Callon, M., Courtial, J. P., &amp; Laville, F. (1991). Co-word analysis as a tool for describing the network of interactions between basic and technological research: The case of polymer chemistry. <em>Scientometrics</em>, <em>22</em>(1), 155–205. <a href="https://doi.org/10.1007/BF02019280">https://doi.org/10.1007/BF02019280</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Campbell, D. T., &amp; Fiske, D. W. (1959). Convergent and discriminant validation by the multitrait-multimethod matrix. <em>Psychological Bulletin</em>, <em>56</em>(2), 81–105. <a href="https://doi.org/10.1037/h0046016">https://doi.org/10.1037/h0046016</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Cobo, M. J., López-Herrera, A. G., Herrera-Viedma, E., &amp; Herrera, F. (2011). An approach for detecting, quantifying, and visualizing the evolution of a research field: A practical application to the Fuzzy Sets Theory field. <em>Journal of Informetrics</em>, <em>5</em>(1), 146–166. <a href="https://doi.org/10.1016/j.joi.2010.10.002">https://doi.org/10.1016/j.joi.2010.10.002</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Coulter, N., Monarch, I., &amp; Konda, S. (1998). Software engineering as seen through its research literature: A study in co-word analysis. <em>Journal of the American Society for Information Science</em>, <em>49</em>(13), 1206–1223. <a href="https://doi.org/10.1002/(SICI)1097-4571(1998)49:13%3C1206::AID-ASI7%3E3.0.CO;2-F">https://doi.org/10.1002/(SICI)1097-4571(1998)49:13&lt;1206::AID-ASI7&gt;3.0.CO;2-F</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Cronbach, L. J., &amp; Meehl, P. E. (1955). Construct validity in psychological tests. <em>Psychological Bulletin</em>, <em>52</em>(4), 281–302. <a href="https://doi.org/10.1037/h0040957">https://doi.org/10.1037/h0040957</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Eronen, M. I., &amp; Bringmann, L. F. (2021). The theory crisis in psychology: How to move forward. <em>Perspectives on Psychological Science</em>, <em>16</em>(4), 779–788. <a href="https://doi.org/10.1177/1745691620970586">https://doi.org/10.1177/1745691620970586</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Fiedler, K. (2017). What constitutes strong psychological science? The (neglected) role of diagnosticity and a priori theorizing. <em>Perspectives on Psychological Science</em>, <em>12</em>(1), 46–61. <a href="https://doi.org/10.1177/1745691616654458">https://doi.org/10.1177/1745691616654458</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Flake, J. K., &amp; Fried, E. I. (2020). Measurement schmeasurement: Questionable measurement practices and how to avoid them. <em>Advances in Methods and Practices in Psychological Science</em>, <em>3</em>(4), 456–465. <a href="https://doi.org/10.1177/2515245920952393">https://doi.org/10.1177/2515245920952393</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Guest, O., &amp; Martin, A. E. (2021). How computational modeling can force theory building in psychological science. <em>Perspectives on Psychological Science</em>, <em>16</em>(4), 789–802. <a href="https://doi.org/10.1177/1745691620970585">https://doi.org/10.1177/1745691620970585</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Lakatos, I. (1970). Falsification and the methodology of scientific research programmes. In I. Lakatos &amp; A. Musgrave (Eds.), <em>Criticism and the growth of knowledge</em> (pp. 91–196). Cambridge University Press. <a href="https://doi.org/10.1017/cbo9781139171434.009">https://doi.org/10.1017/cbo9781139171434.009</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Lakens, D. (2017). Equivalence tests: A practical primer for <em>t</em> tests, correlations, and meta-analyses. <em>Social Psychological and Personality Science</em>, <em>8</em>(4), 355–362. <a href="https://doi.org/10.1177/1948550617697177">https://doi.org/10.1177/1948550617697177</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Lakens, D. (2022). Sample size justification. <em>Collabra: Psychology</em>, <em>8</em>(1), Article 33267. <a href="https://doi.org/10.1525/collabra.33267">https://doi.org/10.1525/collabra.33267</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Lawson, K. M., &amp; Robins, R. W. (2021). Sibling constructs: What are they, why do they matter, and how should you handle them? <em>Personality and Social Psychology Review</em>, <em>25</em>(4), 344–366. <a href="https://doi.org/10.1177/10888683211047101">https://doi.org/10.1177/10888683211047101</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Le, H., Schmidt, F. L., Harter, J. K., &amp; Lauver, K. J. (2010). The problem of empirical redundancy of constructs in organizational research: An empirical investigation. <em>Organizational Behavior and Human Decision Processes</em>, <em>112</em>(2), 112–125. <a href="https://doi.org/10.1016/j.obhdp.2010.02.003">https://doi.org/10.1016/j.obhdp.2010.02.003</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">MacCallum, R. C., Wegener, D. T., Uchino, B. N., &amp; Fabrigar, L. R. (1993). The problem of equivalent models in applications of covariance structure analysis. <em>Psychological Bulletin</em>, <em>114</em>(1), 185–199. <a href="https://doi.org/10.1037/0033-2909.114.1.185">https://doi.org/10.1037/0033-2909.114.1.185</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Mayo, D. G., &amp; Spanos, A. (2006). Severe testing as a basic concept in a Neyman–Pearson philosophy of induction. <em>The British Journal for the Philosophy of Science</em>, <em>57</em>(2), 323–357. <a href="https://doi.org/10.1093/bjps/axl003">https://doi.org/10.1093/bjps/axl003</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Mayo, D. G., &amp; Spanos, A. (2011). Error statistics. In P. S. Bandyopadhyay &amp; M. R. Forster (Eds.), <em>Philosophy of statistics</em> (pp. 153–198). Elsevier. <a href="https://doi.org/10.1016/B978-0-444-51862-0.50005-8">https://doi.org/10.1016/B978-0-444-51862-0.50005-8</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Meehl, P. E. (1967). Theory-testing in psychology and physics: A methodological paradox. <em>Philosophy of Science</em>, <em>34</em>(2), 103–115. <a href="https://doi.org/10.1086/288135">https://doi.org/10.1086/288135</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Meehl, P. E. (1990a). Appraising and amending theories: The strategy of Lakatosian defense and two principles that warrant it. <em>Psychological Inquiry</em>, <em>1</em>(2), 108–141. <a href="https://doi.org/10.1207/s15327965pli0102_1">https://doi.org/10.1207/s15327965pli0102_1</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Meehl, P. E. (1990b). Why summaries of research on psychological theories are often uninterpretable. <em>Psychological Reports</em>, <em>66</em>(1), 195–244. <a href="https://doi.org/10.2466/pr0.1990.66.1.195">https://doi.org/10.2466/pr0.1990.66.1.195</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Moler, C., &amp; Van Loan, C. (2003). Nineteen dubious ways to compute the exponential of a matrix, twenty-five years later. <em>SIAM Review</em>, <em>45</em>(1), 3–49. <a href="https://doi.org/10.1137/S00361445024180">https://doi.org/10.1137/S00361445024180</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Platt, J. R. (1964). Strong inference. <em>Science</em>, <em>146</em>(3642), 347–353. <a href="https://doi.org/10.1126/science.146.3642.347">https://doi.org/10.1126/science.146.3642.347</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Popper, K. (2005). <em>The logic of scientific discovery</em>. Routledge. <a href="https://doi.org/10.4324/9780203994627">https://doi.org/10.4324/9780203994627</a> (Original work published 1959)</p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Richardson, T. (2003). Markov properties for acyclic directed mixed graphs. <em>Scandinavian Journal of Statistics</em>, <em>30</em>(1), 145–157. <a href="https://doi.org/10.1111/1467-9469.00323">https://doi.org/10.1111/1467-9469.00323</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Richardson, T., &amp; Spirtes, P. (2002). Ancestral graph Markov models. <em>The Annals of Statistics</em>, <em>30</em>(4), 962–1030. <a href="https://doi.org/10.1214/aos/1031689015">https://doi.org/10.1214/aos/1031689015</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Robinaugh, D. J., Haslbeck, J. M. B., Ryan, O., Fried, E. I., &amp; Waldorp, L. J. (2021). Invisible hands and fine calipers: A call to use formal theory as a toolkit for theory construction. <em>Perspectives on Psychological Science</em>, <em>16</em>(4), 725–743. <a href="https://doi.org/10.1177/1745691620974697">https://doi.org/10.1177/1745691620974697</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Robinaugh, D. J., Haslbeck, J. M. B., Waldorp, L. J., Kossakowski, J. J., Fried, E. I., Millner, A. J., McNally, R. J., Ryan, O., de Ron, J., van der Maas, H. L. J., van Nes, E. H., Scheffer, M., Kendler, K. S., &amp; Borsboom, D. (2024). Advancing the network theory of mental disorders: A computational model of panic disorder. <em>Psychological Review</em>, <em>131</em>(6), 1482–1508. <a href="https://doi.org/10.1037/rev0000515">https://doi.org/10.1037/rev0000515</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Rohrer, J. M. (2018). Thinking clearly about correlations and causation: Graphical causal models for observational data. <em>Advances in Methods and Practices in Psychological Science</em>, <em>1</em>(1), 27–42. <a href="https://doi.org/10.1177/2515245917745629">https://doi.org/10.1177/2515245917745629</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Rönkkö, M., &amp; Cho, E. (2022). An updated guideline for assessing discriminant validity. <em>Organizational Research Methods</em>, <em>25</em>(1), 6–14. <a href="https://doi.org/10.1177/1094428120968614">https://doi.org/10.1177/1094428120968614</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Rundgren, A., Jordan, B., &amp; Erdtman, S. (2020). <em>JSON Canonicalization Scheme (JCS)</em> (RFC 8785). RFC Editor. <a href="https://doi.org/10.17487/RFC8785">https://doi.org/10.17487/RFC8785</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Scheel, A. M., Tiokhin, L., Isager, P. M., &amp; Lakens, D. (2021). Why hypothesis testers should spend less time testing hypotheses. <em>Perspectives on Psychological Science</em>, <em>16</em>(4), 744–755. <a href="https://doi.org/10.1177/1745691620966795">https://doi.org/10.1177/1745691620966795</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Shipley, B. (2000). A new inferential test for path models based on directed acyclic graphs. <em>Structural Equation Modeling: A Multidisciplinary Journal</em>, <em>7</em>(2), 206–218. <a href="https://doi.org/10.1207/S15328007SEM0702_4">https://doi.org/10.1207/S15328007SEM0702_4</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Suddaby, R. (2010). Editor's comments: Construct clarity in theories of management and organization. <em>Academy of Management Review</em>, <em>35</em>(3), 346–357. <a href="https://doi.org/10.5465/amr.35.3.zok346">https://doi.org/10.5465/amr.35.3.zok346</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Sutton, R. I., &amp; Staw, B. M. (1995). What theory is not. <em>Administrative Science Quarterly</em>, <em>40</em>(3), 371–384. <a href="https://doi.org/10.2307/2393788">https://doi.org/10.2307/2393788</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Szollosi, A., Kellen, D., Navarro, D. J., Shiffrin, R., van Rooij, I., Van Zandt, T., &amp; Donkin, C. (2020). Is preregistration worthwhile? <em>Trends in Cognitive Sciences</em>, <em>24</em>(2), 94–95. <a href="https://doi.org/10.1016/j.tics.2019.11.009">https://doi.org/10.1016/j.tics.2019.11.009</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Textor, J., van der Zander, B., Gilthorpe, M. S., Liśkiewicz, M., &amp; Ellison, G. T. H. (2016). Robust causal inference using directed acyclic graphs: The R package ‘dagitty’. <em>International Journal of Epidemiology</em>, <em>45</em>(6), 1887–1894. <a href="https://doi.org/10.1093/ije/dyw341">https://doi.org/10.1093/ije/dyw341</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">van der Zander, B., Liśkiewicz, M., &amp; Textor, J. (2019). Separators and adjustment sets in causal graphs: Complete criteria and an algorithmic framework. <em>Artificial Intelligence</em>, <em>270</em>, 1–40. <a href="https://doi.org/10.1016/j.artint.2018.12.006">https://doi.org/10.1016/j.artint.2018.12.006</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">VanderWeele, T. J., &amp; Robins, J. M. (2010). Signed directed acyclic graphs for causal inference. <em>Journal of the Royal Statistical Society Series B: Statistical Methodology</em>, <em>72</em>(1), 111–127. <a href="https://doi.org/10.1111/j.1467-9868.2009.00728.x">https://doi.org/10.1111/j.1467-9868.2009.00728.x</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Verma, T. S., &amp; Pearl, J. (2022). Equivalence and synthesis of causal models. In H. Geffner, R. Dechter, &amp; J. Y. Halpern (Eds.), <em>Probabilistic and causal inference: The works of Judea Pearl</em> (pp. 221–236). Association for Computing Machinery. <a href="https://doi.org/10.1145/3501714.3501732">https://doi.org/10.1145/3501714.3501732</a> (Original work published 1990)</p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Westfall, J., &amp; Yarkoni, T. (2016). Statistically controlling for confounding constructs is harder than you think. <em>PLOS ONE</em>, <em>11</em>(3), Article e0152719. <a href="https://doi.org/10.1371/journal.pone.0152719">https://doi.org/10.1371/journal.pone.0152719</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Whetten, D. A. (1989). What constitutes a theoretical contribution? <em>The Academy of Management Review</em>, <em>14</em>(4), 490–495. <a href="https://doi.org/10.5465/amr.1989.4308371">https://doi.org/10.5465/amr.1989.4308371</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Wright, S. (1934). The method of path coefficients. <em>The Annals of Mathematical Statistics</em>, <em>5</em>(3), 161–215. <a href="https://doi.org/10.1214/aoms/1177732676">https://doi.org/10.1214/aoms/1177732676</a></p>
