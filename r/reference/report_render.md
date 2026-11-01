# Render a theory's audit dossier as a standalone Quarto report.

Writes a `.qmd` (a YAML header plus the deterministic dossier body) and
can optionally invoke Quarto to render it. The report content is the
deterministic `tf_dossier` output, and only the rendering step is
environment-dependent.
