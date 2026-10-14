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
   - Test record: already tested: passed
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
