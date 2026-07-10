#!/usr/bin/env python
"""Generate golden outputs from the Python reference implementation.

Writes, for every fixture in ``fixtures/*.theory.yaml``:
  fixtures/expected/<id>.report.json
  fixtures/expected/<id>.nomological_net.dot
  fixtures/expected/<id>.provenance.dot
  fixtures/expected/<id>.causal_dag.dag

These are the parity targets the R package is checked against.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python" / "src"))

import theoryforge as tf  # noqa: E402

FIXTURES = ROOT / "fixtures"
EXPECTED = FIXTURES / "expected"
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
        (EXPECTED / f"{tid}.severity.json").write_bytes((json.dumps(t.severity(), indent=2) + "\n").encode("utf-8"))
        written.append(f"{tid}.severity.json")
        (EXPECTED / f"{tid}.prereg.md").write_bytes(t.preregister().encode("utf-8"))
        written.append(f"{tid}.prereg.md")
        (EXPECTED / f"{tid}.sem.lavaan").write_bytes(t.compile_sem().encode("utf-8"))
        written.append(f"{tid}.sem.lavaan")
        (EXPECTED / f"{tid}.dossier.md").write_bytes(t.dossier().encode("utf-8"))
        written.append(f"{tid}.dossier.md")
        (EXPECTED / f"{tid}.simulate.json").write_bytes((json.dumps(t.simulate(), indent=2) + "\n").encode("utf-8"))
        written.append(f"{tid}.simulate.json")
        (EXPECTED / f"{tid}.implications.json").write_bytes(
            (json.dumps(t.implications(), indent=2) + "\n").encode("utf-8")
        )
        written.append(f"{tid}.implications.json")

    # amendment appraisal for the v2-vs-v1 pair (Lakatosian progressive/degenerating)
    v1 = tf.read(FIXTURES / "panic-network.theory.yaml")
    v2 = tf.read(FIXTURES / "panic-network-2026-v2.theory.yaml")
    (EXPECTED / "panic-network-2026-v2.appraisal.json").write_bytes(
        (json.dumps(v2.appraise_amendment(v1), indent=2) + "\n").encode("utf-8")
    )
    written.append("panic-network-2026-v2.appraisal.json")

    # structured version diff for the same amended pair (P5)
    (EXPECTED / "panic-network-2026-v2.diff.json").write_bytes(
        (json.dumps(v2.diff(v1), indent=2) + "\n").encode("utf-8")
    )
    written.append("panic-network-2026-v2.diff.json")

    # archive bundle (P5): deterministic contents with a fixed author list
    fair = v1.fair_export(authors=["Doe, Jane"])
    (EXPECTED / "panic-network-2026.fair.json").write_bytes(
        (json.dumps(fair, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    )
    written.append("panic-network-2026.fair.json")

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
    (EXPECTED / f"{cid}.keyword_cooccurrence.dot").write_bytes(tf.lit_diagram(lm, "keyword_cooccurrence").encode("utf-8"))
    (EXPECTED / f"{cid}.co_citation.dot").write_bytes(tf.lit_diagram(lm, "co_citation").encode("utf-8"))
    ls = tf.read(FIXTURES / "panic-network.theory.yaml").landscape(corpus)
    (EXPECTED / f"{cid}.landscape.json").write_bytes((json.dumps(ls, indent=2) + "\n").encode("utf-8"))
    (EXPECTED / f"{cid}.theme_landscape.dot").write_bytes(tf.lit_diagram(ls, "theme_landscape").encode("utf-8"))
    written += [f"{cid}.litmap.json", f"{cid}.keyword_cooccurrence.dot", f"{cid}.co_citation.dot",
                f"{cid}.landscape.json", f"{cid}.theme_landscape.dot"]

    print(f"wrote {len(written)} golden files to {EXPECTED}:")
    for w in written:
        print("  " + w)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
