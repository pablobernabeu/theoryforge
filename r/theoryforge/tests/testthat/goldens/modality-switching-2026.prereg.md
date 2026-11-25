# Preregistration: Modality switching in grounded conceptual processing

- Theory ID: modality-switching-2026
- Version: v1
- Schema version: 1.1
- Content hash: sha256:c8109f9b8b7ca5df9c28ea0b42d799a4e9e608cad9cb0641e6030f9cd7bbb630
- Maturity: developing
- Formal model: sem (models/modality_switching.lavaan)
- Derivations check: yes

## Theory

### Constructs
- c_sensorimotor_experience (Sensorimotor experience with a concept): The accumulated perceptual and motor engagement a person has had with the referent of a concept, across the modalities in which that referent is met. Measures: modality-specific perceptual strength ratings; sensory experience ratings; self-reported frequency of first-hand encounters. Boundary conditions: adult native speakers; concrete nouns and their properties; no sensory impairment in the modalities tested.
- c_modality_activation (Modality-specific perceptual activation): Recruitment of the perceptual system belonging to one modality while a word or property that draws on that modality is understood. Measures: BOLD response in modality-specific sensory cortex; interference from a concurrent load in the same modality. Boundary conditions: adult native speakers; no sensory impairment in the modalities tested; visual word presentation.
- c_switch_cost (Cost of switching modality between consecutive trials): The extra time taken to verify a property when the trial before it addressed a property of a different perceptual modality. Measures: switch-minus-repeat response-time difference; switch-minus-repeat error-rate difference. Boundary conditions: adult native speakers; consecutive trials within one block; no interpolated task between trials.
- c_conceptual_access (Ease of conceptual access): The speed and reliability with which the meaning of a word becomes available to the task at hand. Measures: semantic categorisation latency; lexical decision latency; accuracy on either task. Boundary conditions: adult native speakers; visual word presentation; single words without sentence context.
- c_lexical_familiarity (Lexical familiarity with the word form): How well established the written or spoken form of a word is for a reader, apart from anything the word refers to. Measures: subjective familiarity ratings; corpus frequency of the word form; age of acquisition. Boundary conditions: adult native speakers; single words without sentence context; concrete nouns and their properties.

### Propositions
- p1: c_sensorimotor_experience increases c_modality_activation. Mechanism: Understanding a word re-enacts the perceptual states laid down when its referent was met, so a modality that carries much of that experience is the one recruited most strongly.
- p2: c_modality_activation increases c_switch_cost. Mechanism: Attention has to be moved from one perceptual system to another between trials, and the more firmly the system engaged on the preceding trial was committed, the longer that move takes.
- p3: c_modality_activation increases c_conceptual_access. Mechanism: The perceptual detail the recruited system returns is part of the conceptual content itself, so recruiting it supplies the very information the task is asking for.
- p4: c_lexical_familiarity increases c_conceptual_access. Mechanism: A well-established form is recognised quickly and with little competition from its neighbours, which leaves the conceptual system a cleaner signal to work from.

### Phenomena to explain
- ph1: Words whose referents are experienced more strongly through the senses are recognised and named faster, beyond what concreteness and imageability predict. (doi: 10.1016/j.cognition.2012.07.010)
  - Claim: c_sensorimotor_experience and c_conceptual_access are positively associated; entailed by the causal graph through p1, p3

### Auxiliary assumptions
- aux1 (core): Response latency in these tasks indexes ease of conceptual access rather than ease of selecting a response.
- aux2 (core): Perceptual strength ratings collected from a norming sample stand in for the sensorimotor experience of the participants tested.

### Rival accounts
- alt_grounding_by_interaction: Grounding by interaction (doi: 10.1016/j.jphysparis.2008.03.004)
- alt_symbol_interdependency: Symbol interdependency (doi: 10.1111/j.1756-8765.2010.01106.x)

### Scope
- adult native speakers
- concrete nouns and their properties
- no sensory impairment in the modalities tested
- visual word presentation
- consecutive trials within one block
- no interpolated task between trials
- single words without sentence context

## Hypotheses
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
   - Rivals it is declared to discriminate: alt_grounding_by_interaction (its propositions contradict the claim)
   - Test record: untested
4. [interval] Across a corpus of concrete nouns matched for length, modality-specific perceptual strength and lexical familiarity correlate no more strongly than 0.10 in absolute value. (pred4; derives from: p1, p4)
   - Region the claim allows: [-0.1, 0.1]
   - Claim: c_sensorimotor_experience and c_lexical_familiarity are independent; entailed by the causal graph
   - Auxiliary assumptions: aux2 (core)
   - Rivals it is declared to discriminate: alt_symbol_interdependency (its propositions contradict the claim)
   - Test record: untested

## Sampling plan (author-recorded; not scored)
- pred1: no sampling plan stated
- pred2: n = 48 participants; alpha 0.05, two-sided; smallest effect of interest 20 ms; power 0.9 (simulation). Illustrative values.
- pred3: no sampling plan stated
- pred4: no sampling plan stated

## Implied conditional independencies (derived from the causal graph, not predictions)
- `c_sensorimotor_experience _||_ c_switch_cost | c_modality_activation`
- `c_sensorimotor_experience _||_ c_conceptual_access | c_modality_activation, c_lexical_familiarity`
- `c_sensorimotor_experience _||_ c_lexical_familiarity`
- `c_modality_activation _||_ c_lexical_familiarity | c_sensorimotor_experience`
- `c_switch_cost _||_ c_conceptual_access | c_modality_activation, c_lexical_familiarity`
- `c_switch_cost _||_ c_lexical_familiarity | c_modality_activation`

## Severity (pre-data rubric of claim form)
- pred1: severity 0.3, risk 0.4
- pred2: severity 0.7, risk 0.7
- pred3: severity 1.0, risk 0.9
- pred4: severity 0.8, risk 0.7
