# Security policy

## Reporting a vulnerability

If you find a security problem in theoryforge, please report it privately by
email to pcbernabeu@gmail.com rather than opening a public issue. A short
description of the problem and, where possible, a way to reproduce it is enough
to get started. You can expect an acknowledgement within a few days, and we will
keep you informed as the issue is investigated and resolved.

## A note on credentials

theoryforge never stores your credentials, and no step that uses one runs
automatically. A live deposit to OSF needs an OSF personal access token, which
is passed explicitly to `tf_osf_push()` (R) or `osf_push()` (Python) and is
never read from disk or the environment. A fetch from OpenAlex with
`tf_fetch_corpus()` (R) or `fetch_corpus()` (Python) can send an OpenAlex API
key, which is passed as `api_key` or read by default from the
`OPENALEX_API_KEY` environment variable. Each is sent only in an
`Authorization: Bearer` header that no redirect carries to another server, and
neither is written anywhere. Keep tokens and keys in your own environment and
never paste one into an issue, a pull request or a discussion.
