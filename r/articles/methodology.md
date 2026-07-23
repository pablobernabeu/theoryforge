# Methodological foundations

## Why theoryforge

Psychology and the social sciences accumulate findings far faster than
they build theories that explain them. Constructs proliferate and blur
into one another (the jingle-jangle problem), predictions stay vague and
directional rather than committal, auxiliary assumptions accrete to
protect a theory rather than to expose it, and a revision is rarely
judged by whether it adds testable content or merely shields the theory
from refutation. Eronen and Bringmann (2021) call this the theory
crisis.

theoryforge treats a theory as a structured, versioned object and makes
the specification of these properties checkable rather than left to
prose. It scores the theory against twelve structural criteria drawn
from the methodology literature, screens its constructs for redundancy,
grades how severely each prediction is tested, distinguishes progressive
from degenerating amendments in Lakatos’s sense, and renders the
structure so it can be read and tested. Every value it reports is
produced by a fixed, documented rule, with no model and no randomness,
and the R and Python implementations return identical verdicts and
byte-identical diagram intermediate representations, so a verdict is
reproducible and can be audited against the specification. See [Scope
and limits](#scope-and-limits) below for what this checking does and
does not establish.

Each item in the rigour checklist follows from a result in the
methodology literature, and the package records the supporting work next
to the check (the `citation` field of the report). The supporting works
are listed in APA style below.

## Grounding for each rigour check

| Rigour check | Criterion | Supporting work |
|----|----|----|
| Falsifiability (`falsifiability`) | At least one prediction forbids an observation | Popper (1959), [Bacharach (1989)](https://doi.org/10.5465/amr.1989.4308374) |
| Predictive precision (`precision`) | Predictions are point/interval, not merely directional | [Meehl (1967)](https://doi.org/10.1086/288135), [Meehl (1990a)](https://doi.org/10.1207/s15327965pli0102_1) |
| Test severity (`risk_severity`) | Mean prediction severity above a threshold | [Mayo (2018)](https://doi.org/10.1017/9781107286184), [Meehl (1990b)](https://doi.org/10.2466/pr0.1990.66.1.195) |
| Parsimony (`parsimony`) | Few auxiliary assumptions; none added purely defensively | [Forster & Sober (1994)](https://doi.org/10.1093/bjps/45.1.1), [Lakatos (1970)](https://doi.org/10.1017/cbo9781139171434.009) |
| Construct non-redundancy (`non_redundancy`) | No construct pair exceeds a calibrated similarity screen (jingle-jangle) | Kelley (1927), [Le et al. (2010)](https://doi.org/10.1016/j.obhdp.2010.02.003), [Lawson & Robins (2021)](https://doi.org/10.1177/10888683211047101) |
| Construct clarity (`construct_clarity`) | Every construct has definition + measurement + boundary conditions | [Suddaby (2010)](https://doi.org/10.5465/amr.35.3.zok346), [Cronbach & Meehl (1955)](https://doi.org/10.1037/h0040957), [Flake & Fried (2020)](https://doi.org/10.1177/2515245920952393) |
| Scope and boundary conditions (`scope`) | Boundary conditions explicitly stated | [Whetten (1989)](https://doi.org/10.5465/amr.1989.4308371), [Bacharach (1989)](https://doi.org/10.5465/amr.1989.4308374) |
| Mechanism (`logical_why`) | Each proposition states a mechanism, not just a correlation | [Sutton & Staw (1995)](https://doi.org/10.2307/2393788), [Whetten (1989)](https://doi.org/10.5465/amr.1989.4308371) |
| Causal testability (`causal_testability`) | Causal relations export to a DAG with derivable implications | [Textor et al. (2016)](https://doi.org/10.1093/ije/dyw341), [Eronen & Bringmann (2021)](https://doi.org/10.1177/1745691620970586) |
| Diagnosticity (`diagnosticity`) | At least one prediction discriminates from a registered alternative | [Platt (1964)](https://doi.org/10.1126/science.146.3642.347), [Fiedler (2017)](https://doi.org/10.1177/1745691616654458) |
| Formalisation (`formalisation`) | A formal-model stub exists | [Robinaugh et al. (2021)](https://doi.org/10.1177/1745691620974697), [Guest & Martin (2021)](https://doi.org/10.1177/1745691620970585) |
| Derivation chain (`derivation_chain`) | Each prediction is graph-reachable from propositions (reachability only) | [Scheel et al. (2021)](https://doi.org/10.1177/1745691620966795), [Szollosi et al. (2020)](https://doi.org/10.1016/j.tics.2019.11.009) |

## How the rigour score is computed

Each of the twelve items returns a status (`pass`, `warn` or `fail`) and
a score between 0 and 1. Present-or-absent items score 1 or 0; items
that measure a proportion (for example, the share of constructs that
carry a definition, a measurement and boundary conditions) score that
proportion. Two items read a calibrated threshold from the checklist
file: predictive precision passes when at least half of the predictions
are point or interval, and test severity passes when the mean of the
declared per-prediction `severity` values reaches 0.5.

The headline number, the aggregate score, is the weighted sum of the
twelve item scores scaled to a 0 to 100 range. The weights are fixed in
the checklist file and sum to one, so a theory that passes every item
scores 100. Falsifiability carries the most weight (0.15) and
formalisation the least (0.05).

The gate is the one-word verdict. Two items are blockers: falsifiability
and the derivation chain. If either blocker fails, the gate is
`blocked`. A theory at the `draft` maturity stage is always `advisory`,
so the blockers inform without gating early work. Otherwise the gate is
`pass`.

Each item is scored as follows.

- **Falsifiability** passes if at least one prediction is point,
  interval or directional, that is, a claim that forbids some
  observation.
- **Predictive precision** is the share of predictions that are point or
  interval, and passes at 0.5 or above.
- **Test severity** averages the declared `severity` field of each
  prediction (warning with a score of 0 when no prediction declares
  one), and passes at 0.5 or above. It is distinct from the computed
  severity of the
  [`tf_severity()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_severity.md)
  rubric, which offers a principled way of choosing the declared values.
- **Parsimony** falls as the ratio of auxiliary assumptions to
  propositions rises, and fails outright if any assumption is ad hoc
  (added for a prediction that no passing test supports).
- **Construct non-redundancy** scores one minus the largest lexical
  similarity between any pair of construct definitions, and warns once
  that similarity reaches 0.85.
- **Construct clarity** is the share of constructs that carry a
  definition, a measurement and boundary conditions, and passes only at
  1.
- **Scope** passes when boundary conditions are stated, either for the
  theory or on every construct.
- **Mechanism** is the share of propositions that state a mechanism
  rather than a bare correlation, and passes only at 1.
- **Causal testability** passes if at least one proposition is a causal
  relation (causes, increases or decreases) that exports to a directed
  acyclic graph.
- **Diagnosticity** is the share of predictions that name a registered
  alternative they would discriminate against, and passes once at least
  one does.
- **Formalisation** passes if the theory carries a formal-model stub.
- **Derivation chain** is the share of predictions that derive from
  declared propositions, and passes only at 1; otherwise it fails.

## Scope and limits

The checklist is a structural and lexical screen, not a substantive
review. Each item asks whether a required property is present in the
theory object, such as a boundary-conditions field or a mechanism
string, or what share of a collection exhibits it; the non-redundancy
screen additionally measures the lexical overlap between construct
definitions. No item reads or judges the content of a definition, a
mechanism or a boundary condition: a theory can score highly by being
completely and precisely specified while resting on a false premise, and
can score poorly for being under-specified while resting on a sound one.
The aggregate score indexes how completely a theory is specified against
the checklist, not whether it is true or well-reasoned.

The weights that combine the twelve items into the aggregate score, and
the three numeric thresholds (the redundancy ceiling, the minimum
precision share, the minimum mean severity), are the package’s own
calibrated defaults, fixed in the checklist file for reproducibility.
They are not derived from an external validation study, and a field with
different norms can override them in its own copy of the file. The gate
reflects only two of the twelve items, falsifiability and the derivation
chain: a theory can show `gate: pass` while several other items are
`warn` or `fail`, so the gate is a minimal precondition for testing
rather than an overall verdict. Read the item table alongside the
aggregate score, not the score alone.

## How the other outputs are computed

**Severity.** Each prediction earns a base risk from its form: existence
0.1, directional 0.4, interval 0.7 and point 0.9. The reported risk
score is this base. The computed severity then adjusts it. A merely
directional prediction is discounted by 25 per cent, following Meehl’s
argument that a bare sign is cheap because almost everything in
psychology correlates a little. A prediction that names a registered
alternative in its `diagnostic_vs` field, and so would discriminate
between theories, earns a bonus of 0.1. The computed severity is the
discounted base plus the bonus, capped at 1.

**Construct redundancy.** Each construct definition is reduced to a set
of content tokens: the text is lowercased and split on anything that is
not a letter or digit, and tokens shorter than three characters or in a
small stop-word list are dropped. The similarity of two constructs is
the Jaccard index of their token sets, the size of the intersection
divided by the size of the union. The screen reports every construct
pair with its similarity and flags any pair at or above 0.85 for review.
This is a deliberately simple lexical screen, calibrated rather than a
hard truth; an optional embedding-based screen is available for a
semantic comparison.

**Amendment appraisal.** Comparing an amended theory with a prior
version, a prediction is new if its identifier did not appear in the
prior, and corroborated if a passing test outcome references it. An
assumption is ad hoc if it was added for a prediction (its `added_for`
field is set) and no passing test supports the prediction it protects.
The verdict follows Lakatos: progressive if the amendment adds at least
one corroborated new prediction and no ad-hoc assumptions, degenerating
if it adds at least one ad-hoc assumption and no corroborated new
prediction, and neutral otherwise.

**Theory landscape.** Against a literature corpus, each theme is
labelled by how many of the theory’s accounts address it, counting the
focal theory and its registered alternatives. A theme that no account
touches is under-theorised, one that a single account touches is
covered, and one that two or more touch is crowded, which flags a
redundancy risk.

**Simulation.** Each construct becomes a state variable, and each
directed proposition contributes a signed coupling between two states,
positive for increases, causes and mediates and negative for decreases,
scaled by the coupling gain. Every state also decays towards zero at the
damping rate. The network is integrated with fixed-step (Euler) updates
from a common initial value, and the trajectory is the sequence of state
vectors. It is a deliberately transparent linear system, meant to expose
the qualitative dynamics a network of propositions implies rather than
to fit data.

## References

Bacharach, S. B. (1989). Organizational theories: Some criteria for
evaluation. *The Academy of Management Review*, *14*(4), 496–515.
<https://doi.org/10.5465/amr.1989.4308374>

Cronbach, L. J., & Meehl, P. E. (1955). Construct validity in
psychological tests. *Psychological Bulletin*, *52*(4), 281–302.
<https://doi.org/10.1037/h0040957>

Eronen, M. I., & Bringmann, L. F. (2021). The theory crisis in
psychology: How to move forward. *Perspectives on Psychological
Science*, *16*(4), 779–788. <https://doi.org/10.1177/1745691620970586>

Fiedler, K. (2017). What constitutes strong psychological science? The
(neglected) role of diagnosticity and a priori theorizing. *Perspectives
on Psychological Science*, *12*(1), 46–61.
<https://doi.org/10.1177/1745691616654458>

Flake, J. K., & Fried, E. I. (2020). Measurement schmeasurement:
Questionable measurement practices and how to avoid them. *Advances in
Methods and Practices in Psychological Science*, *3*(4), 456–465.
<https://doi.org/10.1177/2515245920952393>

Forster, M., & Sober, E. (1994). How to tell when simpler, more unified,
or less ad hoc theories will provide more accurate predictions. *The
British Journal for the Philosophy of Science*, *45*(1), 1–35.
<https://doi.org/10.1093/bjps/45.1.1>

Guest, O., & Martin, A. E. (2021). How computational modeling can force
theory building in psychological science. *Perspectives on Psychological
Science*, *16*(4), 789–802. <https://doi.org/10.1177/1745691620970585>

Kelley, T. L. (1927). *Interpretation of educational measurements*.
World Book Company.

Lakatos, I. (1970). Falsification and the methodology of scientific
research programmes. In I. Lakatos & A. Musgrave (Eds.), *Criticism and
the growth of knowledge* (pp. 91–196). Cambridge University Press.
<https://doi.org/10.1017/cbo9781139171434.009>

Lawson, K. M., & Robins, R. W. (2021). Sibling constructs: What are
they, why do they matter, and how should you handle them? *Personality
and Social Psychology Review*, *25*(4), 344–366.
<https://doi.org/10.1177/10888683211047101>

Le, H., Schmidt, F. L., Harter, J. K., & Lauver, K. J. (2010). The
problem of empirical redundancy of constructs in organizational
research: An empirical investigation. *Organizational Behavior and Human
Decision Processes*, *112*(2), 112–125.
<https://doi.org/10.1016/j.obhdp.2010.02.003>

Mayo, D. G. (2018). *Statistical inference as severe testing: How to get
beyond the statistics wars*. Cambridge University Press.
<https://doi.org/10.1017/9781107286184>

Meehl, P. E. (1967). Theory-testing in psychology and physics: A
methodological paradox. *Philosophy of Science*, *34*(2), 103–115.
<https://doi.org/10.1086/288135>

Meehl, P. E. (1990a). Appraising and amending theories: The strategy of
Lakatosian defense and two principles that warrant it. *Psychological
Inquiry*, *1*(2), 108–141. <https://doi.org/10.1207/s15327965pli0102_1>

Meehl, P. E. (1990b). Why summaries of research on psychological
theories are often uninterpretable. *Psychological Reports*, *66*(1),
195–244. <https://doi.org/10.2466/pr0.1990.66.1.195>

Platt, J. R. (1964). Strong inference. *Science*, *146*(3642), 347–353.
<https://doi.org/10.1126/science.146.3642.347>

Popper, K. R. (1959). *The logic of scientific discovery*. Hutchinson.

Robinaugh, D. J., Haslbeck, J. M. B., Ryan, O., Fried, E. I., & Waldorp,
L. J. (2021). Invisible hands and fine calipers: A call to use formal
theory as a toolkit for theory construction. *Perspectives on
Psychological Science*, *16*(4), 725–743.
<https://doi.org/10.1177/1745691620974697>

Scheel, A. M., Tiokhin, L., Isager, P. M., & Lakens, D. (2021). Why
hypothesis testers should spend less time testing hypotheses.
*Perspectives on Psychological Science*, *16*(4), 744–755.
<https://doi.org/10.1177/1745691620966795>

Suddaby, R. (2010). Editor’s comments: Construct clarity in theories of
management and organization. *Academy of Management Review*, *35*(3),
346–357. <https://doi.org/10.5465/amr.35.3.zok346>

Sutton, R. I., & Staw, B. M. (1995). What theory is not. *Administrative
Science Quarterly*, *40*(3), 371–384. <https://doi.org/10.2307/2393788>

Szollosi, A., Kellen, D., Navarro, D. J., Shiffrin, R., van Rooij, I.,
Van Zandt, T., & Donkin, C. (2020). Is preregistration worthwhile?
*Trends in Cognitive Sciences*, *24*(2), 94–95.
<https://doi.org/10.1016/j.tics.2019.11.009>

Textor, J., van der Zander, B., Gilthorpe, M. S., Liśkiewicz, M., &
Ellison, G. T. H. (2016). Robust causal inference using directed acyclic
graphs: The R package ‘dagitty’. *International Journal of
Epidemiology*, *45*(6), 1887–1894. <https://doi.org/10.1093/ije/dyw341>

Whetten, D. A. (1989). What constitutes a theoretical contribution? *The
Academy of Management Review*, *14*(4), 490–495.
<https://doi.org/10.5465/amr.1989.4308371>
