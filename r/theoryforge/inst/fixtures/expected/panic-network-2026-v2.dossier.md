# theoryforge dossier: Network theory of panic disorder

- Theory ID: panic-network-2026-v2
- Content hash: sha256:486b5a95b0fa635a7c4360b412a868f441191199b10ccea30089d9e13da69b10
- Maturity: testing
- Checklist version: 2.1
- Aggregate rigour score: 89.8/100
- Checklist coverage: 0.92
- Gate: pass
- Blockers failed: 0

## Rigour checklist

| item | criterion | status | score | weight |
| --- | --- | --- | --- | --- |
| falsifiability | At least one prediction forbids an observation | pass | 1.0 | 0.15 |
| precision | Predictions are point/interval, not merely directional | pass | 0.75 | 0.1 |
| risk_severity | Mean prediction severity (declared, else the claim-form rubric) at or above threshold | pass | 0.613 | 0.1 |
| parsimony | No auxiliary assumption added in response to an anomaly lacks independent corroboration | n/a | n/a | 0.08 |
| non_redundancy | No pair of construct definitions is a near-duplicate or contained in the other (lexical screen) | pass | 1.0 | 0.1 |
| construct_clarity | Every construct has definition + measurement + boundary conditions | pass | 1.0 | 0.08 |
| scope | Boundary conditions explicitly stated | pass | 1.0 | 0.06 |
| logical_why | Each proposition states a mechanism, not just a correlation | pass | 1.0 | 0.08 |
| causal_testability | At least one proposition states a causal relation | pass | 1.0 | 0.06 |
| diagnosticity | At least one prediction names a registered alternative it discriminates from (declared, or verified where the claim and the rival's propositions are stated) | pass | 0.5 | 0.06 |
| formalisation | A formal model of a recognised type (ode, abm, network, sem) is declared | pass | 1.0 | 0.05 |
| derivation_chain | Every prediction cites declared propositions, and the causal graph entails the claim it states, if any | pass | 1.0 | 0.08 |

## Severity (pre-data rubric of claim form)

- pred1: severity 1.0, risk 0.9, declared 0.7
- pred2: severity 0.7, risk 0.7, declared 0.6
- pred3: severity 0.3, risk 0.4, declared 0.4
- pred4: severity 1.0, risk 0.9, declared 0.75

## Test record

- pred1: passed; observed: Illustrative values, not a reported result: arousal reached the predicted band in 78% of trials.; date: 2026-05-01; registered: osf.io/abcde
- pred4: passed; observed: Illustrative values, not a reported result: avoidance dropped into the predicted band in 71% of cases.; date: 2026-06-10; registered: osf.io/fghij

## Evidence

- supports pred4: corroborates

## Claims and the causal graph

_No prediction or phenomenon states a claim._

## Equivalent models

_Not determined: the causal graph has a feedback loop._

## Rivals

_No alternative states propositions._

## Provenance

1. tf_add_proposition: p4
2. tf_add_prediction: pred4

## Preregistration

## Preregistration: Network theory of panic disorder

- Theory ID: panic-network-2026-v2
- Version: v2 (parent v1)
- Schema version: 1.0
- Content hash: sha256:486b5a95b0fa635a7c4360b412a868f441191199b10ccea30089d9e13da69b10
- Maturity: testing
- Formal model: ode (models/panic_ode.py)
- Derivations check: yes

### Theory

#### Constructs
- c_arousal (Physiological arousal): Bodily activation indexed by heart rate, respiration and electrodermal response. Measures: heart-rate variability; self-reported arousal. Boundary conditions: adults; non-clinical baseline; no beta-blocker medication.
- c_perceived_threat (Perceived threat): The appraised dangerousness of internal sensations and external context. Measures: threat appraisal questionnaire. Boundary conditions: adults; non-clinical baseline; waking hours.
- c_avoidance (Avoidance behaviour): Acts that reduce exposure to feared situations or sensations. Measures: behavioural avoidance task; diary counts. Boundary conditions: adults; waking hours; community sample.

#### Propositions
- p1: c_arousal increases c_perceived_threat. Mechanism: Interoceptive feedback: rising arousal is detected and appraised as danger.
- p2: c_perceived_threat increases c_avoidance. Mechanism: Threat appraisal motivates protective withdrawal.
- p3: c_perceived_threat causes c_arousal. Mechanism: Catastrophic appraisal triggers sympathetic activation, closing a positive loop.
- p4: c_arousal increases c_avoidance. Mechanism: Bodily sensations are themselves feared, so activities that raise arousal are avoided directly, not only through the appraisal of threat.

#### Auxiliary assumptions
- aux1 (core): Self-report indexes the latent appraisal construct.

#### Rival accounts
- alt_cognitive: Cognitive model of panic (doi: 10.1016/0005-7967(86)90011-2)
- alt_biological: Biological model of panic (doi: 10.1176/ajp.146.2.148)

#### Scope
- adults
- non-clinical baseline
- no beta-blocker medication
- waking hours
- community sample

### Hypotheses
1. [point] An interoceptive challenge raises heart rate 20 beats per minute above baseline, within a measurement tolerance of 5, within 90 seconds. (pred1; derives from: p1, p3)
   - Auxiliary assumptions: aux1 (core)
   - Rivals it discriminates: alt_cognitive
   - Test record: already tested: passed (2026-05-01, registered osf.io/abcde)
2. [interval] Avoidance frequency falls within a 20-35% band after exposure therapy. (pred2; derives from: p2)
   - Test record: untested
3. [directional] Higher perceived threat is associated with more avoidance. (pred3; derives from: p2)
   - Test record: untested
4. [point] Blocking interoceptive feedback lowers avoidance-task scores by 30 per cent, within a tolerance of 5 percentage points, within two weeks. (pred4; derives from: p4)
   - Rivals it discriminates: alt_cognitive
   - Test record: already tested: passed (2026-06-10, registered osf.io/fghij)

### Implied conditional independencies (derived from the causal graph, not predictions)
_Not derived: the causal graph has a feedback loop, c_arousal -> c_perceived_threat -> c_arousal. With cycles = 'sigma', the statements are read by sigma-separation and hold if each loop settles to a unique equilibrium._
