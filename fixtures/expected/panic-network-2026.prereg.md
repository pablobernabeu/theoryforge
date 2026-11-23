# Preregistration: Network theory of panic disorder

- Theory ID: panic-network-2026
- Version: v1
- Schema version: 1.0
- Content hash: sha256:cc1ff8ce967c887aa1f28bd0333d0d7a1e4cae960d626c0b831448fc7ea9d35f
- Maturity: developing
- Formal model: ode (models/panic_ode.py)
- Derivations check: yes

## Theory

### Constructs
- c_arousal (Physiological arousal): Bodily activation indexed by heart rate, respiration and electrodermal response. Measures: heart-rate variability; self-reported arousal. Boundary conditions: adults; non-clinical baseline; no beta-blocker medication.
- c_perceived_threat (Perceived threat): The appraised dangerousness of internal sensations and external context. Measures: threat appraisal questionnaire. Boundary conditions: adults; non-clinical baseline; waking hours.
- c_avoidance (Avoidance behaviour): Acts that reduce exposure to feared situations or sensations. Measures: behavioural avoidance task; diary counts. Boundary conditions: adults; waking hours; community sample.

### Propositions
- p1: c_arousal increases c_perceived_threat. Mechanism: Interoceptive feedback: rising arousal is detected and appraised as danger.
- p2: c_perceived_threat increases c_avoidance. Mechanism: Threat appraisal motivates protective withdrawal.
- p3: c_perceived_threat causes c_arousal. Mechanism: Catastrophic appraisal triggers sympathetic activation, closing a positive loop.

### Auxiliary assumptions
- aux1 (core): Self-report indexes the latent appraisal construct.

### Rival accounts
- alt_cognitive: Cognitive model of panic (doi: 10.1016/0005-7967(86)90011-2)
- alt_biological: Biological model of panic (doi: 10.1176/ajp.146.2.148)

### Scope
- adults
- non-clinical baseline
- no beta-blocker medication
- waking hours
- community sample

## Hypotheses
1. [point] An interoceptive challenge raises heart rate 20 beats per minute above baseline, within a measurement tolerance of 5, within 90 seconds. (pred1; derives from: p1, p3)
   - Auxiliary assumptions: aux1 (core)
   - Rivals it discriminates: alt_cognitive
   - Test record: already tested: passed (2026-05-01, registered osf.io/abcde)
2. [interval] Avoidance frequency falls within a 20-35% band after exposure therapy. (pred2; derives from: p2)
   - Test record: untested
3. [directional] Higher perceived threat is associated with more avoidance. (pred3; derives from: p2)
   - Test record: untested

## Implied conditional independencies (derived from the causal graph, not predictions)
_Not derived: the causal graph has a feedback loop, c_arousal -> c_perceived_threat -> c_arousal. With cycles = 'sigma', the statements are read by sigma-separation and hold if each loop settles to a unique equilibrium._

## Severity (pre-data rubric of claim form)
- pred1: severity 1.0, risk 0.9
- pred2: severity 0.7, risk 0.7
- pred3: severity 0.3, risk 0.4
