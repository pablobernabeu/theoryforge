# Deterministic dynamical-system runner derived from a theory network.

Each construct is a state variable; each directed proposition
contributes a signed linear coupling term. The system is propagated
either with fixed-step (Euler) updates or exactly, with the matrix
exponential of the coupling matrix, so the trajectory is fully
deterministic.
