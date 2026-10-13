# Preregistration: Network theory of panic disorder

- Theory ID: panic-network-2026
- Version: v1
- Schema version: 1.0
- Maturity: developing
- Derivation references resolve: yes

## Hypotheses
1. [point] An interoceptive challenge raises heart rate 20 beats per minute above baseline, within a measurement tolerance of 5, within 90 seconds. (derives from: p1, p3)
   - Auxiliary assumptions: aux1 (core)
   - Rivals it discriminates: alt_cognitive
   - Test record: already tested: passed (2026-05-01, registered osf.io/abcde)
2. [interval] Avoidance frequency falls within a 20-35% band after exposure therapy. (derives from: p2)
   - Test record: untested
3. [directional] Higher perceived threat is associated with more avoidance. (derives from: p2)
   - Test record: untested

## Implied conditional independencies (derived from the causal graph, not predictions)
_Not derived: implications requires an acyclic causal graph; cycle found: c_arousal -> c_perceived_threat -> c_arousal; set cycles to 'sigma' to derive sigma-separation statements._

## Severity (pre-data rubric of claim form)
- pred1: severity 1.0, risk 0.9
- pred2: severity 0.7, risk 0.7
- pred3: severity 0.3, risk 0.4
