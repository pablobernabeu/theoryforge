# Appraise an amendment as progressive, degenerating, or neutral

Compares an amended theory `new` with its `prior` version by content,
not by prediction ids, and returns a Lakatosian verdict with the
evidence behind it.

## Usage

``` r
tf_appraise_amendment(new, prior)
```

## Arguments

- new:

  The amended theory object (named list).

- prior:

  The prior theory object (named list).

## Value

A named list whose first element, `verdict`, is one of `"progressive"`,
`"degenerating"` and `"neutral"`. `new_predictions`, `corroborated_new`,
`ad_hoc_assumptions`, `articulated`, `underived`,
`corroborated_new_registered`, `dropped`, `dropped_corroborated`,
`content_lost` and `new_anomalies` are ascending-sorted character
vectors. `renamed` is a list of `list(prior, new)` pairs sorted by
`new`, and `assumptions` holds one
`list(id, added_for, class, independent)` per new assumption added for
an anomaly, in file order. The four elements of earlier versions come
first, in their old order.

## Details

A new prediction whose statement and type match a prediction the
amendment dropped is that prediction renamed. A new prediction derived
only from propositions the prior already held, and needing no new
assumption, articulates old content. A prediction is corroborated when
at least one test outcome passes it and none fails it. An assumption
added for an anomaly (its `added_for` names the prediction it answers)
is ad hoc unless a prediction it protects that is new in this version,
other than the anomaly, is corroborated.

The verdict is `"progressive"` when a corroborated new prediction is
neither an articulation nor underived, no assumption is ad hoc and no
corroborated prediction is dropped. It is `"degenerating"` when an
assumption is ad hoc and no such prediction exists, and `"neutral"`
otherwise. Lakatos has only the first two. `"neutral"` is theoryforge's
label for an amendment that meets neither rule, and the vectors returned
tell its cases apart. Only `corroborated_new_registered` reads a test
outcome's `registered`, and no date or `version` field is read, so which
version is the prior is the caller's responsibility.

A test outcome whose `passed` is present and not `TRUE` or `FALSE`, in
`new` (checked first) or in `prior`, is refused with the message the
Python twin raises. A quoted `"true"` read as a failure and could turn a
progressive amendment into a degenerating one.

## References

Lakatos, I. (1970). Falsification and the methodology of scientific
research programmes. In *Criticism and the growth of knowledge* (pp.
91-196). Cambridge University Press.
[doi:10.1017/cbo9781139171434.009](https://doi.org/10.1017/cbo9781139171434.009)

Meehl, P. E. (1990a). Appraising and amending theories: The strategy of
Lakatosian defense and two principles that warrant it. *Psychological
Inquiry*, 1(2), 108-141.
[doi:10.1207/s15327965pli0102_1](https://doi.org/10.1207/s15327965pli0102_1)

## Examples

``` r
prior <- tf_theory("demo-1", "A demonstration theory") |>
  tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
  tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
  tf_add_proposition("p1", "c_arousal", "c_threat", "increases") |>
  tf_add_prediction("h1", "Threat rises with arousal.", "directional",
                    derives_from = "p1")
new <- prior |>
  tf_add_construct("c_avoid", "Avoidance", "Withdrawal from feared situations.") |>
  tf_add_proposition("p2", "c_threat", "c_avoid", "increases") |>
  tf_add_prediction("h2", "Avoidance rises 0.3 SD per SD of threat.", "point",
                    derives_from = "p2")
new$test_outcomes <- list(list(prediction_id = "h2", passed = TRUE))
tf_appraise_amendment(new, prior)$verdict
#> [1] "progressive"
```
