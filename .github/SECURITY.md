# Security policy

## Reporting a vulnerability

If you find a security problem in theoryforge, please report it privately by
email to pcbernabeu@gmail.com rather than opening a public issue. A short
description of the problem and, where possible, a way to reproduce it is enough
to get started. You can expect an acknowledgement within a few days, and we will
keep you informed as the issue is investigated and resolved.

## A note on credentials

theoryforge never stores your credentials. Depositing to OSF is the only step
that needs one: the OSF personal access token is passed explicitly to
`tf_osf_push()` (R) or `osf_push()` (Python) for a live upload, is never read
from disk or written anywhere, and the deposit is never performed automatically.
Keep the token in your own environment and never paste it into an issue, a pull
request or a discussion.
