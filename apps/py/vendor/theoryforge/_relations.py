"""What each proposition relation asserts (API_SPEC.md section 28, "Relation semantics").

The table is defined once here and read wherever a relation's meaning matters.
R's ``relations.R`` holds the same table (``.tf_RELATIONS``, ``.tf_DIRECTED``,
``.tf_BIDIRECTED``).
"""
from __future__ import annotations

# relation -> (kind, sign). A directed relation states an effect of `from` on
# `to`. A bidirected one states covariance that the theory leaves unexplained, as
# a latent common cause of the two would. The sign is +1 or -1 where the relation
# fixes one and None where it does not. Mediation over a path is written as a
# chain of propositions, so `mediates` is one directed edge, from -> to.
# `moderates` points from the moderator to the outcome, whose effect it modifies
# (VanderWeele & Robins, 2007). A proposition's `functional_form` is descriptive
# and no function reads it.
RELATIONS: dict[str, tuple[str, int | None]] = {
    "increases": ("directed", 1),
    "decreases": ("directed", -1),
    "causes": ("directed", None),
    "mediates": ("directed", None),
    "moderates": ("directed", None),
    "associates": ("bidirected", None),
}

# The relations that state an effect of one construct on another: the edges
# from -> to of the graph that implications() and the causal_dag view read, and
# what the checklist's causal_testability item counts.
DIRECTED = frozenset(r for r, (kind, _) in RELATIONS.items() if kind == "directed")

# The relations that state unexplained covariance: the bidirected edges of that
# graph, and the edges the nomological_net view draws without arrowheads.
BIDIRECTED = frozenset(r for r, (kind, _) in RELATIONS.items() if kind == "bidirected")
