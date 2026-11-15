# Tokenise a string into a set of content tokens

Folds the text through the package's fold table (accented Latin letters
to ASCII, Greek and Cyrillic letters to small unaccented ones) and
lowercases ASCII letters, then takes every maximal run of letters, marks
and digits in any script (Unicode general categories L, M and N) as a
token. Tokens shorter than 3 code points and the canonical English
stopwords are dropped, and the unique set is returned. Scripts other
than Latin, Greek and Cyrillic are compared as written, and text written
without spaces, such as Chinese, gives one token per run.

## Usage

``` r
tf_tokens(s)
```

## Arguments

- s:

  A single string (or `NULL`, treated as "").

## Value

A character vector of unique tokens (possibly empty).

## Examples

``` r
tf_tokens("The physiological arousal response to a threat")
#> [1] "physiological" "arousal"       "response"      "threat"       
# Accents and case are folded, so these give the same tokens.
tf_tokens("Na\u00efve \u00c9motion")
#> [1] "naive"   "emotion"
tf_tokens("naive emotion")
#> [1] "naive"   "emotion"
```
