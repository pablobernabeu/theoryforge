# theoryforge dossier: Modality switching in grounded conceptual processing

- Theory ID: modality-switching-2026
- Maturity: developing
- Checklist version: 2.0
- Aggregate rigour score: 89.8/100
- Checklist coverage: 0.92
- Gate: pass
- Blockers failed: 0

## Rigour checklist

| item | status | score | weight |
| --- | --- | --- | --- |
| falsifiability | pass | 1.0 | 0.15 |
| precision | pass | 0.75 | 0.1 |
| risk_severity | pass | 0.613 | 0.1 |
| parsimony | n/a | n/a | 0.08 |
| non_redundancy | pass | 1.0 | 0.1 |
| construct_clarity | pass | 1.0 | 0.08 |
| scope | pass | 1.0 | 0.06 |
| logical_why | pass | 1.0 | 0.08 |
| causal_testability | pass | 1.0 | 0.06 |
| diagnosticity | pass | 0.5 | 0.06 |
| formalisation | pass | 1.0 | 0.05 |
| derivation_chain | pass | 1.0 | 0.08 |

## Severity (pre-data rubric of claim form)

- pred1: severity 0.3, risk 0.4, declared 0.45
- pred2: severity 0.7, risk 0.7, declared 0.6
- pred3: severity 1.0, risk 0.9, declared 0.75
- pred4: severity 0.8, risk 0.7, declared 0.65

## Test record

_No test outcomes recorded._

## Evidence

- supports pred1: corroborates; doi: 10.1111/1467-9280.t01-1-01429

## Provenance

1. tf_add_construct: Registered five constructs from the perceptual-symbols account of conceptual processing (Barsalou, 1999, doi:10.1017/S0140525X99002149).
2. tf_add_proposition: Linked the constructs into an acyclic graph: a fork at modality activation and a collider at conceptual access.
3. tf_add_prediction: Derived four predictions, two of them diagnostic against a registered alternative.

## Preregistration

# Preregistration: Modality switching in grounded conceptual processing

- Theory ID: modality-switching-2026
- Version: v1
- Schema version: 1.0
- Maturity: developing
- Derivation references resolve: yes

## Hypotheses
1. [directional] In property verification with word frequency, word length and property typicality matched across conditions, responses are slower when the property belongs to a different modality from the preceding trial than when it belongs to the same one. (derives from: p1, p2)
   - Auxiliary assumptions: aux1 (core)
   - Test record: untested
2. [interval] In that design the switch cost lies between 20 and 60 ms, averaged over items and participants. (derives from: p1, p2)
   - Auxiliary assumptions: aux1 (core)
   - Test record: untested
3. [point] Concurrent dynamic visual noise removes the advantage of visual properties over auditory properties in semantic categorisation, leaving a difference of zero under load in the same participants who show the advantage without it. (derives from: p3)
   - Auxiliary assumptions: aux1 (core)
   - Rivals it discriminates: alt_grounding_by_interaction
   - Test record: untested
4. [interval] Across a corpus of concrete nouns matched for length, modality-specific perceptual strength and lexical familiarity correlate no more strongly than 0.10 in absolute value. (derives from: p1, p4)
   - Auxiliary assumptions: aux2 (core)
   - Rivals it discriminates: alt_symbol_interdependency
   - Test record: untested

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
