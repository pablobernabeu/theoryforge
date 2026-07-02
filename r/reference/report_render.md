# Render a theory's audit dossier as a standalone Quarto report.

Writes a `.qmd` (a YAML header plus the deterministic dossier body) and
can optionally invoke Quarto to render it. The report content is the
parity-tested `tf_dossier`; only the rendering step is
environment-dependent. See API_SPEC.md section 22.
