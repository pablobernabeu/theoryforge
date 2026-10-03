# What each proposition relation asserts (API_SPEC.md section 28, "Relation
# semantics"). The table is defined once here and read wherever a relation's
# meaning matters. The Python twin's _relations.py holds the same table.
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

# The relations that state an effect of one construct on another, which the
# checklist's causal_testability item counts.
.tf_DIRECTED <- names(Filter(function(r) identical(r$kind, "directed"), .tf_RELATIONS))

# The causal_dag view and tf_implications() read only these three relations
# (API_SPEC.md sections 5 and 27).
.tf_CAUSAL <- c("causes", "increases", "decreases")
