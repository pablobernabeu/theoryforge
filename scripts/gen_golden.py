#!/usr/bin/env python
"""Generate golden outputs from the Python reference implementation.

Writes every parity artefact named in API_SPEC.md sections 13, 17, 21 and 22
into ``fixtures/expected/``. Listing the artefact types here as well would only
give them a second place to drift from; the spec is the list.

Also mirrors the fixture inputs and the golden tree into the copies each package
ships, so that every duplicate in the repository has exactly one writer. CI runs
this script and fails on any resulting change.
"""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python" / "src"))

import theoryforge as tf  # noqa: E402

FIXTURES = ROOT / "fixtures"
EXPECTED = FIXTURES / "expected"
# The R package ships its own copy of the golden tree, and the two harnesses
# read different ones: testthat prefers the installed copy, scripts/parity_check
# reads the root copy. A desync would silently split the two gates onto
# different reference data, so this script owns both.
R_EXPECTED = ROOT / "r" / "theoryforge" / "inst" / "fixtures" / "expected"
# Both packages ship the example theories so that a reader who installed only
# the package still has something to run: R reaches them with system.file(),
# Python with theoryforge.example_path(). Neither copy is edited by hand.
EXAMPLE_INPUTS = ("panic-network.theory.yaml", "panic-network-2026-v2.theory.yaml",
                  "modality-switching.theory.yaml", "weak-theory.theory.yaml",
                  "panic-corpus.yaml")
R_INPUTS = ROOT / "r" / "theoryforge" / "inst" / "fixtures"
PY_INPUTS = ROOT / "python" / "src" / "theoryforge" / "fixtures"
DIAGRAMS = {
    "nomological_net": "dot",
    "provenance": "dot",
    "causal_dag": "dag",
    "development_roadmap": "dot",
    "pipeline": "dot",
    "context": "dot",
    "workflow": "dot",
    "venn": "svg",
    "rigour": "svg",
    "severity": "svg",
}


def main() -> int:
    EXPECTED.mkdir(parents=True, exist_ok=True)
    written = []
    for fx in sorted(FIXTURES.glob("*.theory.yaml")):
        t = tf.read(fx)
        t.validate()
        tid = t.id
        # write raw bytes with LF endings (no platform newline translation) so
        # the diagram goldens are byte-identical targets on every OS.
        (EXPECTED / f"{tid}.report.json").write_bytes((t.report("json") + "\n").encode("utf-8"))
        written.append(f"{tid}.report.json")
        for dtype, ext in DIAGRAMS.items():
            (EXPECTED / f"{tid}.{dtype}.{ext}").write_bytes(t.diagram(dtype).encode("utf-8"))
            written.append(f"{tid}.{dtype}.{ext}")
        (EXPECTED / f"{tid}.severity.json").write_bytes(
            (json.dumps(t.severity(), indent=2) + "\n").encode("utf-8"))
        written.append(f"{tid}.severity.json")
        (EXPECTED / f"{tid}.prereg.md").write_bytes(t.preregister().encode("utf-8"))
        written.append(f"{tid}.prereg.md")
        (EXPECTED / f"{tid}.sem.lavaan").write_bytes(t.compile_sem().encode("utf-8"))
        written.append(f"{tid}.sem.lavaan")
        (EXPECTED / f"{tid}.dossier.md").write_bytes(t.dossier().encode("utf-8"))
        written.append(f"{tid}.dossier.md")
        (EXPECTED / f"{tid}.simulate.json").write_bytes(
            (json.dumps(t.simulate(), indent=2) + "\n").encode("utf-8"))
        written.append(f"{tid}.simulate.json")

    # amendment appraisal for the v2-vs-v1 pair (Lakatosian progressive/degenerating)
    v1 = tf.read(FIXTURES / "panic-network.theory.yaml")
    v2 = tf.read(FIXTURES / "panic-network-2026-v2.theory.yaml")
    (EXPECTED / "panic-network-2026-v2.appraisal.json").write_bytes(
        (json.dumps(v2.appraise_amendment(v1), indent=2) + "\n").encode("utf-8")
    )
    written.append("panic-network-2026-v2.appraisal.json")

    # new_evidence_dois (P2): candidate DOIs against the panic-network theory's
    # existing evidence and alternatives (two already cited, two new, one duplicate)
    new_evidence_candidates = [
        "10.1016/j.brat.2015.10.002",
        "https://doi.org/10.1016/0005-7967(86)90011-2",
        "10.1176/AJP.146.2.148",
        "10.1037/0033-2909.99.1.20",
        "10.1037/0033-2909.99.1.20",
        "10.1016/j.cpr.2011.09.005",
    ]
    new_dois = v1.new_evidence_dois(new_evidence_candidates)
    (EXPECTED / "panic-network-2026.new_evidence_dois.json").write_bytes(
        (json.dumps(new_dois, indent=2) + "\n").encode("utf-8")
    )
    written.append("panic-network-2026.new_evidence_dois.json")

    # bibliometric layer (P2): litmap + landscape + lit diagrams
    corpus = tf.read_corpus(FIXTURES / "panic-corpus.yaml")
    cid = corpus["id"]
    lm = tf.litmap(corpus)
    (EXPECTED / f"{cid}.litmap.json").write_bytes((json.dumps(lm, indent=2) + "\n").encode("utf-8"))
    (EXPECTED / f"{cid}.keyword_cooccurrence.dot").write_bytes(
        tf.lit_diagram(lm, "keyword_cooccurrence").encode("utf-8"))
    (EXPECTED / f"{cid}.co_citation.dot").write_bytes(tf.lit_diagram(lm, "co_citation").encode("utf-8"))
    ls = tf.read(FIXTURES / "panic-network.theory.yaml").landscape(corpus)
    (EXPECTED / f"{cid}.landscape.json").write_bytes((json.dumps(ls, indent=2) + "\n").encode("utf-8"))
    (EXPECTED / f"{cid}.theme_landscape.dot").write_bytes(
        tf.lit_diagram(ls, "theme_landscape").encode("utf-8"))
    written += [f"{cid}.litmap.json", f"{cid}.keyword_cooccurrence.dot", f"{cid}.co_citation.dot",
                f"{cid}.landscape.json", f"{cid}.theme_landscape.dot"]

    # A golden left behind by a deleted fixture would otherwise linger as a
    # tracked file that nobody regenerates and no gate notices, so anything not
    # written on this run is pruned.
    expected_now = set(written)
    for stale in sorted(EXPECTED.iterdir()):
        if stale.name not in expected_now:
            stale.unlink()
            print(f"pruned stale golden: {stale.name}")

    # Mirror the golden tree into the R package's copy. Only `expected/` is
    # touched; the fixture inputs beside it are handled below. The directory
    # itself is kept and its contents replaced, because a sync client can hold a
    # handle on it and make removing the directory unreliable.
    R_EXPECTED.mkdir(parents=True, exist_ok=True)
    for old in sorted(R_EXPECTED.iterdir()):
        if old.is_file():
            old.unlink()
    shutil.copytree(EXPECTED, R_EXPECTED, dirs_exist_ok=True)

    # Mirror the example theories into each package's shipped copy.
    for dest in (R_INPUTS, PY_INPUTS):
        dest.mkdir(parents=True, exist_ok=True)
        for name in EXAMPLE_INPUTS:
            shutil.copyfile(FIXTURES / name, dest / name)

    print(f"wrote {len(written)} golden files to {EXPECTED}")
    print(f"mirrored the golden tree to {R_EXPECTED}")
    print(f"mirrored {len(EXAMPLE_INPUTS)} example theories to {R_INPUTS} and {PY_INPUTS}")
    for w in written:
        print("  " + w)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
