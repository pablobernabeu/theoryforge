# A corpus whose keywords form a single theme makes tf_litmap() and
# tf_landscape() warn that the theme holds every linked keyword (API_SPEC.md
# section 14). Tests that use one for another purpose evaluate the call through
# one_theme(), which muffles that warning and no other.
one_theme <- function(expr) {
  withCallingHandlers(expr, warning = function(w) {
    if (startsWith(conditionMessage(w), "litmap: one theme holds ")) {
      invokeRestart("muffleWarning")
    }
  })
}
