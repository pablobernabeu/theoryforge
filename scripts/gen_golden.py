#!/usr/bin/env python
"""Generate golden outputs from the Python reference implementation.

Writes every parity artefact named in API_SPEC.md sections 13, 17, 21 and 22
into ``fixtures/expected/``. Listing the artefact types here as well would only
give them a second place to drift from; the spec is the list.

Also mirrors the fixture inputs, the golden tree and the two schema files
(``schema/theory.schema.json`` and ``schema/rigor_checklist.yaml``) into the
copies each package ships, so that every duplicate in the repository has exactly
one writer. CI runs this script and fails on any resulting change.

Finally, it records the outcome of every edge-case theory and corpus in
``fixtures/edge/`` (deliberately malformed or awkward inputs) as
``fixtures/edge/expected/<name>.outcome.json``. Neither directory is mirrored
into a package. ``scripts/parity_check.py`` compares the R twin's outcomes with
these records.
"""
from __future__ import annotations

import json
import re
import shutil
import sys
from collections.abc import Callable
from pathlib import Path
from typing import Any

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
# Each package reads its own copy of the schema and checklist, because neither
# the CRAN tarball nor the sdist can reach the repository root. The webR app
# vendors the R package's copy (apps/build.mjs).
SCHEMA = ROOT / "schema"
SCHEMA_FILES = ("theory.schema.json", "rigor_checklist.yaml", "fold.json")
SCHEMA_COPIES = (ROOT / "r" / "theoryforge" / "inst" / "schema",
                 ROOT / "python" / "src" / "theoryforge" / "schema")
EDGE = FIXTURES / "edge"
EDGE_EXPECTED = EDGE / "expected"
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


def emit_theory(t: tf.Theory, out_dir: Path) -> list[str]:
    """Write the per-theory artefact set of ``t`` into ``out_dir``.

    Returns the file names written. ``scripts/parity_check.py`` calls this for
    the app examples, which have no goldens, and compares the result with the
    files ``parity_emit.R theories`` writes for the same inputs.
    """
    tid = t.id
    written = []
    # write raw bytes with LF endings (no platform newline translation) so
    # the diagram goldens are byte-identical targets on every OS.
    (out_dir / f"{tid}.report.json").write_bytes((t.report("json") + "\n").encode("utf-8"))
    written.append(f"{tid}.report.json")
    for dtype, ext in DIAGRAMS.items():
        (out_dir / f"{tid}.{dtype}.{ext}").write_bytes(t.diagram(dtype).encode("utf-8"))
        written.append(f"{tid}.{dtype}.{ext}")
    (out_dir / f"{tid}.severity.json").write_bytes(
        (json.dumps(t.severity(), indent=2) + "\n").encode("utf-8"))
    written.append(f"{tid}.severity.json")
    (out_dir / f"{tid}.prereg.md").write_bytes(t.preregister().encode("utf-8"))
    written.append(f"{tid}.prereg.md")
    (out_dir / f"{tid}.sem.lavaan").write_bytes(t.compile_sem().encode("utf-8"))
    written.append(f"{tid}.sem.lavaan")
    (out_dir / f"{tid}.dossier.md").write_bytes(t.dossier().encode("utf-8"))
    written.append(f"{tid}.dossier.md")
    (out_dir / f"{tid}.simulate.json").write_bytes(
        (json.dumps(t.simulate(), indent=2) + "\n").encode("utf-8"))
    written.append(f"{tid}.simulate.json")
    return written


# A reader may prefix its message with the offending path in parentheses. The
# path differs between machines, and the twins spell it differently (R joins
# with "/"), so it is dropped before the message is recorded. The match ends at
# the first ") " and not at the first ")", so that a path such as
# "C:/Program Files (x86)/..." is dropped whole.
_PATH_PREFIX = re.compile(r"^\(.*?\) ")


def error_text(err: BaseException) -> str:
    """The message of ``err`` as an edge outcome records it."""
    return _PATH_PREFIX.sub("", str(err), count=1)


def _attempt(call: Callable[[], Any]) -> Any:
    try:
        return call()
    # Every refusal is part of the record, whatever its class: the R twin has
    # only a message to compare, so the message is what is kept.
    except Exception as err:
        return {"error": error_text(err)}


def _check_summary(rep: dict) -> dict:
    return {
        "aggregate_score": rep["aggregate_score"],
        "gate": rep["gate"],
        "n_blockers_failed": rep["n_blockers_failed"],
        "items": [{"id": it["id"], "status": it["status"], "score": it["score"]}
                  for it in rep["items"]],
    }


def edge_outcome(path: Path) -> dict:
    """What each public call makes of the theory file at ``path``.

    The keys follow the order of the calls. A call that raises is recorded as
    ``{"error": <message>}``. When the file cannot be read, the record holds
    ``read`` alone. ``scripts/parity_emit.R edge`` builds the same record in R.
    """
    try:
        t = tf.read(path)
    except Exception as err:
        return {"read": {"error": error_text(err)}}
    return {
        "read": "ok",
        "validate": _attempt(t.validate),
        "validate_full": _attempt(lambda: t.validate(full=True)),
        "check": _attempt(lambda: _check_summary(t.check())),
        "severity": _attempt(t.severity),
        "implications": _attempt(t.implications),
        "compile_sem": _attempt(t.compile_sem),
        "simulate": _attempt(lambda: t.simulate(steps=3)),
        "preregister": _attempt(t.preregister),
    }


def corpus_edge_outcome(path: Path) -> dict:
    """What ``read_corpus`` and ``litmap`` make of the corpus file at ``path``.

    Recorded as ``edge_outcome`` records a theory: a call that raises is
    ``{"error": <message>}``, and a failed read leaves ``read`` alone.
    ``scripts/parity_emit.R edge`` builds the same record in R.
    """
    try:
        corpus = tf.read_corpus(path)
    except Exception as err:
        return {"read": {"error": error_text(err)}}
    return {"read": "ok", "litmap": _attempt(lambda: tf.litmap(corpus))}


def _edge_files(edge_dir: Path, kind: str) -> dict[str, Path]:
    found: dict[str, Path] = {}
    for path in sorted(edge_dir.glob(f"*.{kind}.*")):
        # Case-sensitive, as the pattern parity_emit.R lists the same directory
        # with, so that both twins see the same set of cases.
        if path.suffix not in (".yaml", ".json"):
            continue
        name = path.name[: -len(f".{kind}" + path.suffix)]
        if name in found:
            raise SystemExit(f"two edge cases share the name {name}: {found[name].name}, {path.name}")
        found[name] = path
    return found


def edge_inputs(edge_dir: Path = EDGE) -> dict[str, Path]:
    """The edge-case theory files keyed by name (the file name less its suffix)."""
    return _edge_files(edge_dir, "theory")


def edge_corpus_inputs(edge_dir: Path = EDGE) -> dict[str, Path]:
    """The edge-case corpus files (``<name>.corpus.yaml|json``) keyed by name."""
    return _edge_files(edge_dir, "corpus")


def write_edge_outcomes() -> list[str]:
    """Write one outcome record per edge case and prune records left by deleted cases."""
    EDGE_EXPECTED.mkdir(parents=True, exist_ok=True)
    theories, corpora = edge_inputs(), edge_corpus_inputs()
    # Both kinds write <name>.outcome.json, so a name may be used once.
    shared = sorted(set(theories) & set(corpora))
    if shared:
        raise SystemExit(f"a theory and a corpus edge case share the name {shared[0]}")
    records = {name: edge_outcome(path) for name, path in theories.items()}
    records.update({name: corpus_edge_outcome(path) for name, path in corpora.items()})
    written = []
    for name in sorted(records):
        record = json.dumps(records[name], indent=2) + "\n"
        (EDGE_EXPECTED / f"{name}.outcome.json").write_bytes(record.encode("utf-8"))
        written.append(f"{name}.outcome.json")
    for stale in sorted(EDGE_EXPECTED.iterdir()):
        if stale.name not in written:
            stale.unlink()
            print(f"pruned stale edge outcome: {stale.name}")
    return written


def mirror_schema(src: Path, dests) -> None:
    """Copy the schema and checklist from ``src`` into each directory in ``dests``."""
    for dest in dests:
        dest.mkdir(parents=True, exist_ok=True)
        for name in SCHEMA_FILES:
            shutil.copyfile(src / name, dest / name)


def main() -> int:
    # Mirror the schema, checklist and fold table into each package's shipped
    # copy first: the package reads its own copy, so the goldens below must be
    # computed from the files this run ships, not from the previous run's.
    mirror_schema(SCHEMA, SCHEMA_COPIES)

    EXPECTED.mkdir(parents=True, exist_ok=True)
    written = []
    for fx in sorted(FIXTURES.glob("*.theory.yaml")):
        t = tf.read(fx)
        t.validate()
        written += emit_theory(t, EXPECTED)

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
        # Spellings of the cited DOIs that the normaliser of API_SPEC.md
        # section 18 recognises, so the output is the same as without them.
        "doi: 10.1016/j.brat.2015.10.002",
        "DOI 10.1016/j.brat.2015.10.002",
        "doi.org/10.1016/j.brat.2015.10.002",
        "dx.doi.org/10.1016/j.brat.2015.10.002",
        "https://www.doi.org/10.1016/j.brat.2015.10.002",
        "info:doi/10.1016/j.brat.2015.10.002",
        "urn:doi:10.1016/j.brat.2015.10.002",
        "https://doi.org/10.1016/0005-7967%2886%2990011-2",
        "10.1016/j.brat.2015.10.002.",
        "10.1016/J.BRAT.2015.10.002\u00a0",
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

    edge_written = write_edge_outcomes()

    print(f"wrote {len(written)} golden files to {EXPECTED}")
    print(f"mirrored the golden tree to {R_EXPECTED}")
    print(f"mirrored {len(EXAMPLE_INPUTS)} example theories to {R_INPUTS} and {PY_INPUTS}")
    print(f"mirrored {len(SCHEMA_FILES)} schema files to "
          + " and ".join(str(d) for d in SCHEMA_COPIES))
    print(f"wrote {len(edge_written)} edge-case outcome records to {EDGE_EXPECTED}")
    for w in written + edge_written:
        print("  " + w)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
