# theoryforge dossier: Modality switching in grounded conceptual processing

- Theory ID: modality-switching-2026
- Content hash: sha256:c8109f9b8b7ca5df9c28ea0b42d799a4e9e608cad9cb0641e6030f9cd7bbb630
- Maturity: developing
- Checklist version: 3.0
- Aggregate rigour score: 87.1/100 (83.5 to 89.2 under other weightings)
- Checklist coverage: 0.92
- Gate: pass
- Blockers failed: 0

## Rigour checklist

| item | criterion | status | score | weight |
| --- | --- | --- | --- | --- |
| falsifiability | At least one prediction forbids an observation | pass | 1.0 | 0.15 |
| precision | Predictions are point or interval claims whose bounds state the region, not merely directional | pass | 0.5 | 0.1 |
| risk_severity | Mean prediction riskiness (declared severity, else the claim-form rubric) at or above threshold | pass | 0.613 | 0.1 |
| parsimony | No auxiliary assumption that answers an anomaly (named in added_for, or a protected prediction a test failed) lacks independent corroboration | n/a | n/a | 0.08 |
| non_redundancy | Every construct is defined, and no two have near-duplicate or contained definitions, one label or a shared measure (lexical screen) | pass | 1.0 | 0.1 |
| construct_clarity | Every construct has definition + measurement + boundary conditions | pass | 1.0 | 0.08 |
| scope | Boundary conditions explicitly stated | pass | 1.0 | 0.06 |
| logical_why | Each proposition states a mechanism, not just a correlation | pass | 1.0 | 0.08 |
| causal_testability | At least one proposition states a causal relation | pass | 1.0 | 0.06 |
| diagnosticity | At least one prediction names a registered alternative it discriminates from (declared, or verified where the claim and the rival's propositions are stated) | pass | 0.5 | 0.06 |
| formalisation | A formal model of a recognised type (ode, abm, network, sem) is declared | pass | 1.0 | 0.05 |
| derivation_chain | Every prediction cites declared propositions, and the causal graph entails the claim it states, if any | pass | 1.0 | 0.08 |

## Severity (pre-data rubric of claim form)

- pred1: severity 0.3, risk 0.4, declared 0.45
- pred2: severity 0.7, risk 0.7, declared 0.6
- pred3: severity 1.0, risk 0.9, declared 0.75
- pred4: severity 0.8, risk 0.7, declared 0.65

## Test record

- pred2: passed; observed: Illustrative values, not a reported result: switch cost 41 ms (SE 6 ms).; post-data severity 0.999 for [20, 60]

## Evidence

- supports pred1: corroborates; doi: 10.1111/1467-9280.t01-1-01429

## Claims and the causal graph

- pred1 (prediction): the effect of c_modality_activation on c_switch_cost is positive; entailed by the causal graph through p2
- pred3 (prediction): the effect of c_modality_activation on c_conceptual_access is positive; entailed by the causal graph through p3
- pred4 (prediction): c_sensorimotor_experience and c_lexical_familiarity are independent; entailed by the causal graph
- ph1 (phenomenon): c_sensorimotor_experience and c_conceptual_access are positively associated; entailed by the causal graph through p1, p3

## Equivalent models

- p1: c_sensorimotor_experience -> c_modality_activation (reversed in some equivalent model)
- p2: c_modality_activation -> c_switch_cost (reversed in some equivalent model)
- p3: c_modality_activation -> c_conceptual_access (fixed in every equivalent model)
- p4: c_lexical_familiarity -> c_conceptual_access (fixed in every equivalent model)

## Rivals

- alt_grounding_by_interaction: claims it discriminates: pred3, ph1; independencies one implies and the other does not: 4; decisive differences in sign: 6 effects, 3 associations
- alt_symbol_interdependency: claims it discriminates: pred4; independencies one implies and the other does not: 1; decisive differences in sign: 0 effects, 0 associations

## Provenance

1. tf_add_construct: Registered five constructs from the perceptual-symbols account of conceptual processing (Barsalou, 1999, doi:10.1017/S0140525X99002149).
2. tf_add_proposition: Linked the constructs into an acyclic graph: a fork at modality activation and a collider at conceptual access.
3. tf_add_prediction: Derived four predictions, two of them diagnostic against a registered alternative.

## Preregistration

## Preregistration: Modality switching in grounded conceptual processing

- Theory ID: modality-switching-2026
- Version: v1
- Schema version: 1.1
- Content hash: sha256:c8109f9b8b7ca5df9c28ea0b42d799a4e9e608cad9cb0641e6030f9cd7bbb630
- Maturity: developing
- Formal model: sem (models/modality_switching.lavaan)
- Derivations check: yes

### Theory

#### Constructs
- c_sensorimotor_experience (Sensorimotor experience with a concept): The accumulated perceptual and motor engagement a person has had with the referent of a concept, across the modalities in which that referent is met. Measures: modality-specific perceptual strength ratings; sensory experience ratings; self-reported frequency of first-hand encounters. Boundary conditions: adult native speakers; concrete nouns and their properties; no sensory impairment in the modalities tested.
- c_modality_activation (Modality-specific perceptual activation): Recruitment of the perceptual system belonging to one modality while a word or property that draws on that modality is understood. Measures: BOLD response in modality-specific sensory cortex; interference from a concurrent load in the same modality. Boundary conditions: adult native speakers; no sensory impairment in the modalities tested; visual word presentation.
- c_switch_cost (Cost of switching modality between consecutive trials): The extra time taken to verify a property when the trial before it addressed a property of a different perceptual modality. Measures: switch-minus-repeat response-time difference; switch-minus-repeat error-rate difference. Boundary conditions: adult native speakers; consecutive trials within one block; no interpolated task between trials.
- c_conceptual_access (Ease of conceptual access): The speed and reliability with which the meaning of a word becomes available to the task at hand. Measures: semantic categorisation latency; lexical decision latency; accuracy on either task. Boundary conditions: adult native speakers; visual word presentation; single words without sentence context.
- c_lexical_familiarity (Lexical familiarity with the word form): How well established the written or spoken form of a word is for a reader, apart from anything the word refers to. Measures: subjective familiarity ratings; corpus frequency of the word form; age of acquisition. Boundary conditions: adult native speakers; single words without sentence context; concrete nouns and their properties.

#### Propositions
- p1: c_sensorimotor_experience increases c_modality_activation. Mechanism: Understanding a word re-enacts the perceptual states laid down when its referent was met, so a modality that carries much of that experience is the one recruited most strongly.
- p2: c_modality_activation increases c_switch_cost. Mechanism: Attention has to be moved from one perceptual system to another between trials, and the more firmly the system engaged on the preceding trial was committed, the longer that move takes.
- p3: c_modality_activation increases c_conceptual_access. Mechanism: The perceptual detail the recruited system returns is part of the conceptual content itself, so recruiting it supplies the very information the task is asking for.
- p4: c_lexical_familiarity increases c_conceptual_access. Mechanism: A well-established form is recognised quickly and with little competition from its neighbours, which leaves the conceptual system a cleaner signal to work from.

#### Phenomena to explain
- ph1: Words whose referents are experienced more strongly through the senses are recognised and named faster, beyond what concreteness and imageability predict. (doi: 10.1016/j.cognition.2012.07.010)
  - Claim: c_sensorimotor_experience and c_conceptual_access are positively associated; entailed by the causal graph through p1, p3

#### Auxiliary assumptions
- aux1 (core): Response latency in these tasks indexes ease of conceptual access rather than ease of selecting a response.
- aux2 (core): Perceptual strength ratings collected from a norming sample stand in for the sensorimotor experience of the participants tested.

#### Rival accounts
- alt_grounding_by_interaction: Grounding by interaction (doi: 10.1016/j.jphysparis.2008.03.004)
- alt_symbol_interdependency: Symbol interdependency (doi: 10.1111/j.1756-8765.2010.01106.x)

#### Scope
- adult native speakers
- concrete nouns and their properties
- no sensory impairment in the modalities tested
- visual word presentation
- consecutive trials within one block
- no interpolated task between trials
- single words without sentence context

### Hypotheses
1. [directional] In property verification with word frequency, word length and property typicality matched across conditions, responses are slower when the property belongs to a different modality from the preceding trial than when it belongs to the same one. (pred1; derives from: p1, p2)
   - Claim: the effect of c_modality_activation on c_switch_cost is positive; entailed by the causal graph through p2
   - Adjustment for an observational test: none needed
   - Auxiliary assumptions: aux1 (core)
   - Test record: untested
2. [interval] In that design the switch cost lies between 20 and 60 ms, averaged over items and participants. (pred2; derives from: p1, p2)
   - Region the claim allows: [20, 60]
   - Auxiliary assumptions: aux1 (core)
   - Test record: already tested: passed
3. [point] Concurrent dynamic visual noise removes the advantage of visual properties over auditory properties in semantic categorisation, leaving a difference of zero under load in the same participants who show the advantage without it. (pred3; derives from: p3)
   - Claim: the effect of c_modality_activation on c_conceptual_access is positive; entailed by the causal graph through p3
   - Adjustment for an observational test: none needed
   - Auxiliary assumptions: aux1 (core)
   - Rivals it discriminates: alt_grounding_by_interaction (its propositions contradict the claim)
   - Test record: untested
4. [interval] Across a corpus of concrete nouns matched for length, modality-specific perceptual strength and lexical familiarity correlate no more strongly than 0.10 in absolute value. (pred4; derives from: p1, p4)
   - Region the claim allows: [-0.1, 0.1]
   - Claim: c_sensorimotor_experience and c_lexical_familiarity are independent; entailed by the causal graph
   - Auxiliary assumptions: aux2 (core)
   - Rivals it discriminates: alt_symbol_interdependency (its propositions contradict the claim)
   - Test record: untested

### Sampling plan (author-recorded; not scored)
- pred1: no sampling plan stated
- pred2: n = 48 participants; alpha 0.05, two-sided; smallest effect of interest 20 ms; power 0.9 (simulation). Illustrative values.
- pred3: no sampling plan stated
- pred4: no sampling plan stated

### Implied conditional independencies (derived from the causal graph, not predictions)
- `c_sensorimotor_experience _||_ c_switch_cost | c_modality_activation`
- `c_sensorimotor_experience _||_ c_conceptual_access | c_modality_activation, c_lexical_familiarity`
- `c_sensorimotor_experience _||_ c_lexical_familiarity`
- `c_modality_activation _||_ c_lexical_familiarity | c_sensorimotor_experience`
- `c_switch_cost _||_ c_conceptual_access | c_modality_activation, c_lexical_familiarity`
- `c_switch_cost _||_ c_lexical_familiarity | c_modality_activation`
