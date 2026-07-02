# Open Science Framework deposit adapter (assistive, parity-exempt).

Builds the request to upload a theory's audit dossier to OSF. Defaults
to `dry_run = TRUE`, which constructs the request without sending it. A
live push requires the user's OSF token and network access and is never
performed automatically. See API_SPEC.md section 24.
