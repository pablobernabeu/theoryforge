# What each proposition relation asserts (API_SPEC.md section 28, "Relation
# semantics"). The table is defined once here and read wherever a relation's
# meaning matters. The Python twin's _relations.py holds the same table
# (RELATIONS, DIRECTED, BIDIRECTED).
#
# A directed relation states an effect of `from` on `to`. A bidirected one
# states covariance that the theory leaves unexplained, as a latent common cause
# of the two would. The sign is 1L or -1L where the relation fixes one and NA
# where it does not. Mediation over a path is written as a chain of
# propositions, so `mediates` is one directed edge, from -> to. `moderates`
# points from the moderator to the outcome, whose effect it modifies
# (VanderWeele & Robins, 2007). A proposition's `functional_form` is
# descriptive and no function reads it.
.tf_RELATIONS <- list(
  increases  = list(kind = "directed", sign = 1L),
  decreases  = list(kind = "directed", sign = -1L),
  causes     = list(kind = "directed", sign = NA_integer_),
  mediates   = list(kind = "directed", sign = NA_integer_),
  moderates  = list(kind = "directed", sign = NA_integer_),
  associates = list(kind = "bidirected", sign = NA_integer_)
)

# The relations that state an effect of one construct on another: the edges
# from -> to of the graph that tf_implications() and the causal_dag view read,
# and what the checklist's causal_testability item counts.
.tf_DIRECTED <- names(Filter(function(r) identical(r$kind, "directed"), .tf_RELATIONS))

# The relations that state unexplained covariance: the bidirected edges of that
# graph, and the edges the nomological_net view draws without arrowheads.
.tf_BIDIRECTED <- names(Filter(function(r) identical(r$kind, "bidirected"), .tf_RELATIONS))
