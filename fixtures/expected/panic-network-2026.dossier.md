# theoryforge dossier: Network theory of panic disorder

- Theory ID: panic-network-2026
- Content hash: sha256:4687e71fc5b8e34114d1266d204d8911b6641d152d94b0fa8bcff62cf0755e42
- Maturity: developing
- Checklist version: 3.1
- Aggregate rigour score: 85.9/100 (82.1 to 87.9 under other weightings)
- Checklist coverage: 0.92
- Gate: pass
- Blockers failed: 0

## Rigour checklist

| item | criterion | status | score | weight |
| --- | --- | --- | --- | --- |
| falsifiability | At least one prediction is typed point, interval or directional; the label is the author's | pass | 1.0 | 0.15 |
| precision | Share of predictions typed point or interval with a finite lower and upper bound, at or above threshold; the width of the region is not read | pass | 0.75 | 0.1 |
| risk_severity | Mean prediction riskiness (declared severity, else the claim-form rubric) at or above threshold | pass | 0.6 | 0.1 |
| parsimony | No auxiliary assumption added for an anomaly (named in added_for) lacks independent corroboration | n/a | n/a | 0.08 |
| non_redundancy | Every construct is defined, and no two have near-duplicate or contained definitions or one label, and no construct's measures are all listed for another (lexical screen) | pass | 1.0 | 0.1 |
| construct_clarity | Every construct has definition + measurement + boundary conditions | pass | 1.0 | 0.08 |
| scope | Boundary conditions explicitly stated | pass | 1.0 | 0.06 |
| logical_why | Every proposition's mechanism field is filled in; its text is not judged | pass | 1.0 | 0.08 |
| causal_testability | At least one proposition states a causal relation | pass | 1.0 | 0.06 |
| diagnosticity | At least one prediction names a registered alternative it discriminates from (declared, and not shown false where the claim and the rival's propositions are stated) | pass | 0.25 | 0.06 |
| formalisation | A formal model of a recognised type (ode, abm, network, sem) is declared | pass | 1.0 | 0.05 |
| derivation_chain | Every prediction cites declared propositions, the causal graph entails any claim it states and contradicts no phenomenon's claim (a claim left unread because of a feedback loop warns) | warn | 0.75 | 0.08 |

## Severity (pre-data rubric of claim form)

- pred1: severity 1.0, risk 0.9, declared 0.7
- pred2: severity 0.7, risk 0.7, declared 0.6
- pred3: severity 0.3, risk 0.4, declared 0.4
- pred_indep: severity 0.7, risk 0.7

## Test record

- pred1: passed; observed: Illustrative values, not a reported result: arousal reached the predicted band in 78% of trials.; date: 2026-05-01; registered: osf.io/abcde
- pred_indep: failed; observed: Illustrative values, not a reported result: the partial correlation of arousal and avoidance given perceived threat was 0.24.; date: 2026-05-20

## Evidence

- supports pred1: corroborates; doi: 10.1176/ajp.155.5.610

## Claims and the causal graph

- pred_indep (prediction): c_arousal and c_avoidance are independent given c_perceived_threat; not evaluated, since the causal graph has a feedback loop

## Equivalent models

_Not determined: the causal graph has a feedback loop._

## Rivals

_No alternative states propositions._

## Provenance

1. tf_add_construct: Registered three constructs.
2. tf_add_proposition: Linked constructs into a feedback network.
3. tf_add_prediction: Derived three predictions from the propositions.
4. tf_add_prediction: Stated the independence of arousal and avoidance given perceived threat that the causal graph implies.

## Preregistration

## Preregistration: Network theory of panic disorder

- Theory ID: panic-network-2026
- Version: v1
- Schema version: 1.1
- Content hash: sha256:4687e71fc5b8e34114d1266d204d8911b6641d152d94b0fa8bcff62cf0755e42
- Maturity: developing
- Formal model: ode (models/panic_ode.py)
- Derivations check: not checked (feedback loop)

### Theory

#### Constructs
- c_arousal (Physiological arousal): Bodily activation indexed by heart rate, respiration and electrodermal response. Measures: heart-rate variability; self-reported arousal. Boundary conditions: adults; non-clinical baseline; no beta-blocker medication.
- c_perceived_threat (Perceived threat): The appraised dangerousness of internal sensations and external context. Measures: threat appraisal questionnaire. Boundary conditions: adults; non-clinical baseline; waking hours.
- c_avoidance (Avoidance behaviour): Acts that reduce exposure to feared situations or sensations. Measures: behavioural avoidance task; diary counts. Boundary conditions: adults; waking hours; community sample.

#### Propositions
- p1: c_arousal increases c_perceived_threat. Mechanism: Interoceptive feedback: rising arousal is detected and appraised as danger.
- p2: c_perceived_threat increases c_avoidance. Mechanism: Threat appraisal motivates protective withdrawal.
- p3: c_perceived_threat causes c_arousal. Mechanism: Catastrophic appraisal triggers sympathetic activation, closing a positive loop.

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
   - Region the claim allows: [15, 25]
   - Auxiliary assumptions: aux1 (core)
   - Rivals it is declared to discriminate: alt_cognitive
   - Test record: already tested: passed (2026-05-01, registered osf.io/abcde)
2. [interval] Avoidance frequency falls within a 20-35% band after exposure therapy. (pred2; derives from: p2)
   - Region the claim allows: [20, 35]
   - Test record: untested
3. [directional] Higher perceived threat is associated with more avoidance. (pred3; derives from: p2)
   - Test record: untested
4. [interval] Holding perceived threat constant, physiological arousal and avoidance correlate no more strongly than 0.10 in absolute value. (pred_indep; derives from: p1, p2, p3)
   - Region the claim allows: [-0.1, 0.1]
   - Claim: c_arousal and c_avoidance are independent given c_perceived_threat; not evaluated, since the causal graph has a feedback loop
   - Test record: already tested: failed (2026-05-20)

### Implied conditional independencies (derived from the causal graph, not predictions)
_Not derived: the causal graph has a feedback loop, c_arousal -> c_perceived_threat -> c_arousal. With cycles = 'sigma', the statements are read by sigma-separation and hold if each loop settles to a unique equilibrium._
