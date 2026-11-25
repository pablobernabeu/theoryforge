"""Build the register of the validity audit from the two workflow results.

Usage, from the repository root:

    python3 validity/scripts/build_register.py FORMAL.json CONCEPTUAL.json --audit AUDIT_DIR

FORMAL.json and CONCEPTUAL.json are the results of the formal and conceptual
groups of the audit at f72ce4c. Each holds result.group, result.lenses (each
lens with its result and the second reader's check) and result.pilot.
AUDIT_DIR is the directory that holds each lens's scripts and outputs; evidence
paths are written relative to it, and the second readers' Crossref records are
read from it. The judgements the register rests on are in mapping.yaml beside
this script. The script writes findings.csv, verdicts.csv and references.csv
to validity/data/ and prints the counts.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
from collections import Counter
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
DATA = HERE.parent / "data"
SKIP_DIRS = {"venv", "Rlib", "__pycache__", "node_modules", "fulltext", "abstracts"}
NO_CORRECTION = {"", "none", "none."}
FILE_TOKEN = re.compile(r"[\w./-]+\.(?:py|R|out|txt|csv|json|sh|md|png)\b")


def load_groups(paths):
    """Each lens as (group, name, result, check); the pilot has no check."""
    lenses = []
    for path in paths:
        with open(path, encoding="utf-8") as fh:
            result = json.load(fh)["result"]
        for lens in result["lenses"]:
            lenses.append((result["group"], lens["lens"], lens["result"], lens["check"]))
        if result.get("pilot"):
            lenses.append((result["group"], "pilot", result["pilot"], None))
    return lenses


def index_files(audit):
    """Every file under the audit directory, keyed by base name."""
    index = {}
    for root, dirs, files in os.walk(audit):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not d.startswith("wt-"))
        for name in sorted(files):
            rel = os.path.relpath(os.path.join(root, name), audit)
            index.setdefault(name, []).append(rel)
    return index


def first_evidence_file(text, lens, audit, index):
    """The first file in the lens's own directory that the evidence text names."""
    # The lenses wrote paths either in full or as $S/audit/..., where S is the
    # directory that holds the audit directory.
    prefixes = re.escape(str(audit).rstrip("/") + "/") + "|" + re.escape("$S/audit/")
    hits = []
    for m in re.finditer(f"(?:{prefixes})" + r"([^\s,;:()'\"]+)", text):
        hits.append((m.start(), m.group(1).rstrip(".")))
    for m in FILE_TOKEN.finditer(text):
        token = m.group(0)
        for rel in index.get(os.path.basename(token), []):
            if rel.split("/")[0] == lens and rel.endswith(token.lstrip("./")):
                hits.append((m.start(), rel))
                break
    for _, rel in sorted(hits):
        if rel.split("/")[0] == lens and (audit / rel).is_file():
            return rel
    return ""


def check_paths(value, audit, where):
    for rel in filter(None, (p.strip() for p in value.split(";"))):
        if not (audit / rel).exists():
            sys.exit(f"{where}: {rel} is not under the audit directory")
    return value


def correction_of(check):
    text = (check.get("correction") or "").strip()
    return "" if text.lower() in NO_CORRECTION else text


def flag(value):
    if value is None or value == "":
        return ""
    return "true" if value else "false"


def coverage(lens, kind, numbered, mapped):
    missing = sorted(set(range(1, numbered + 1)) - set(mapped))
    extra = sorted(set(mapped) - set(range(1, numbered + 1)))
    if missing or extra:
        sys.exit(f"mapping.yaml, {lens} {kind}: missing {missing}, out of range {extra}")


def build_findings_and_verdicts(lenses, mapping, audit, index):
    findings, verdicts = [], []
    for group, lens, result, check in lenses:
        spec = mapping.get(lens, {})
        nf, nv = len(result["findings"]), len(result["verdicts"])
        f_check, v_check = {}, {}
        if check is not None:
            coverage(lens, "checks", len(check["checks"]), spec.get("checks", {}))
            coverage(lens, "missed", len(check["missed"]), spec.get("missed", {}))
            for c, target in spec["checks"].items():
                target = target or {}
                f, v = target.get("finding"), target.get("verdict")
                if f is not None:
                    if not 1 <= f <= nf or f in f_check:
                        sys.exit(f"mapping.yaml, {lens} check {c}: finding {f} out of range or mapped twice")
                    f_check[f] = c
                if v is not None:
                    if not 1 <= v <= nv or v in v_check:
                        sys.exit(f"mapping.yaml, {lens} check {c}: verdict {v} out of range or mapped twice")
                    v_check[v] = (c, target)
        evidence = spec.get("evidence", {})
        for i, f in enumerate(result["findings"], 1):
            row = {
                "lens": lens, "group": group, "id": f"{lens}-{i}", "raised_by": "lens",
                "title": f["title"], "component": f["component"],
                "severity_lens": f["severity"], "severity_verified": "", "upheld": "",
                "fix_before_release": flag(f["fix_before_release"]),
                "recommendation": f["recommendation"],
                "evidence_path": "", "check": "", "extends": "",
            }
            if i in evidence:
                row["evidence_path"] = check_paths(evidence[i], audit, f"{lens} finding {i}")
            else:
                row["evidence_path"] = first_evidence_file(f["evidence"], lens, audit, index)
            if i in f_check:
                c = check["checks"][f_check[i] - 1]
                after = (c.get("severity_after") or "").strip()
                if after and after != "none":
                    row["severity_verified"] = after
                else:
                    row["severity_verified"] = "none" if c["upheld"] is False else f["severity"]
                row["upheld"] = flag(c["upheld"])
                row["check"] = f"C{f_check[i]}"
                corr = correction_of(c)
                if corr:
                    row["recommendation"] = f"{f['recommendation']} Second reader: {corr}"
            findings.append(row)
        if check is not None:
            n = nf
            for m, item in sorted(spec.get("missed", {}).items()):
                if not item.get("defect"):
                    continue
                n += 1
                ext = item.get("extends")
                findings.append({
                    "lens": lens, "group": group, "id": f"{lens}-{n}", "raised_by": "second reader",
                    "title": item["title"], "component": item["component"],
                    "severity_lens": "", "severity_verified": item.get("severity", ""),
                    "upheld": "", "fix_before_release": "",
                    "recommendation": item.get("recommendation", ""),
                    "evidence_path": check_paths(item.get("evidence", ""), audit, f"{lens} missed {m}"),
                    "check": f"M{m}", "extends": f"{lens}-{ext}" if ext else "",
                })
        for i, v in enumerate(result["verdicts"], 1):
            row = {
                "lens": lens, "group": group, "id": f"{lens}-v{i}",
                "component": v["component"], "claim": v["claim"], "category": v["category"],
                "verdict": v["verdict"], "recommendation": v["recommendation"],
                "check": "", "upheld": "", "verdict_verified": "", "recommendation_verified": "",
            }
            if i in v_check:
                c, target = v_check[i]
                row["check"] = f"C{c}"
                row["upheld"] = flag(check["checks"][c - 1]["upheld"])
                row["verdict_verified"] = target.get("verdict_verified", "")
                row["recommendation_verified"] = target.get("recommendation_verified", "")
            verdicts.append(row)
    return findings, verdicts


def initials(given):
    parts = []
    for word in given.replace(".", ". ").split():
        sub = [s for s in word.strip(".").split("-") if s]
        if sub:
            parts.append("-".join(s[0] + "." for s in sub))
    return " ".join(parts)


def crossref_citation(m):
    names = []
    for a in m.get("author", []):
        if "family" in a:
            names.append(f"{a['family']}, {initials(a.get('given', ''))}".rstrip(", "))
        elif "name" in a:
            names.append(a["name"])
    authors = names[0] if len(names) == 1 else ""
    if len(names) > 1:
        authors = ", ".join(names[:-1]) + " & " + names[-1]
    year = ""
    for key in ("published-print", "issued", "published-online"):
        parts = (m.get(key) or {}).get("date-parts") or [[None]]
        if parts[0] and parts[0][0]:
            year = str(parts[0][0])
            break
    title = (m.get("title") or [""])[0].rstrip(".")
    container = (m.get("container-title") or [""])[0]
    tail = container
    if m.get("volume"):
        tail += f", {m['volume']}"
        if m.get("issue"):
            tail += f"({m['issue']})"
    if m.get("page"):
        tail += f", {m['page']}"
    elif m.get("article-number"):
        tail += f", {m['article-number']}"
    text = f"{authors} ({year}). {title}."
    return f"{text} {tail}." if tail else text


def reader_records(audit):
    """Crossref records the second readers saved, and the text of their reference checks."""
    records, texts = {}, {}
    for chk in sorted(p for p in audit.iterdir() if p.is_dir() and p.name.endswith("-check")):
        lens = chk.name[: -len("-check")]
        chunks = []
        for root, dirs, files in os.walk(chk):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
            for name in sorted(files):
                path = Path(root) / name
                rel = str(path.relative_to(audit))
                low = rel.lower()
                if not any(k in low for k in ("crossref", "pubmed", "/refs/")):
                    continue
                chunks.append(low)
                try:
                    text = path.read_text(encoding="utf-8", errors="ignore")
                except OSError:
                    continue
                # A Crossref or PubMed record lists the works it cites, so only
                # its own DOI counts. Other files are the readers' own checks.
                if name.endswith(".json"):
                    try:
                        obj = json.loads(text)
                    except ValueError:
                        continue
                    msg = obj.get("message", obj) if isinstance(obj, dict) else None
                    if isinstance(msg, dict) and msg.get("DOI"):
                        records.setdefault(msg["DOI"].lower(), (lens, rel, msg))
                        chunks.append(msg["DOI"].lower())
                elif not name.endswith(".xml"):
                    chunks.append(text.lower())
        texts[lens] = "\n".join(chunks)
    return records, texts


def build_references(lenses, mapping, audit):
    refs = {}
    for _, lens, result, _ in lenses:
        for r in result["references"]:
            key = r["doi"].strip().lower()
            entry = refs.setdefault(key, {"doi": r["doi"].strip(), "citation": r["citation"],
                                          "how": [], "lenses": [], "readers": []})
            if lens not in entry["lenses"]:
                entry["lenses"].append(lens)
                entry["how"].append(f"{lens}: {r['verified_how']}")
    records, texts = reader_records(audit)
    for key, (lens, rel, msg) in records.items():
        if key not in refs:
            refs[key] = {"doi": msg["DOI"], "citation": crossref_citation(msg),
                         "how": [f"{lens} second reader: Crossref record retrieved ({rel})."],
                         "lenses": [], "readers": [lens]}
    for extra in mapping.get("extra_references", []):
        key = extra["doi"].lower()
        if key in refs:
            sys.exit(f"mapping.yaml: extra reference {extra['doi']} is already in the register")
        refs[key] = {"doi": extra["doi"], "citation": extra["citation"],
                     "how": [f"{extra['second_reader']} second reader: {extra['verified_how']}"],
                     "lenses": [], "readers": [extra["second_reader"]]}
    for key, entry in refs.items():
        variants = (key, key.replace("/", "_"))
        for lens, text in texts.items():
            if lens not in entry["readers"] and any(v in text for v in variants):
                entry["readers"].append(lens)
    rows = []
    for entry in sorted(refs.values(), key=lambda e: e["citation"].lower()):
        rows.append({"doi": entry["doi"], "citation": entry["citation"],
                     "verified_how": " | ".join(entry["how"]),
                     "lenses": "; ".join(entry["lenses"]),
                     "second_readers": "; ".join(sorted(entry["readers"]))})
    return rows


def relative_paths(rows, audit):
    """Write paths into the audit directory relative to it, as evidence_path is."""
    prefixes = (str(audit).rstrip("/") + "/", "$S/audit/")
    for row in rows:
        for key, value in row.items():
            for prefix in prefixes:
                value = value.replace(prefix, "")
            row[key] = value
    return rows


def write_csv(path, rows):
    with open(path, "w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("formal", help="result of the formal group (JSON)")
    parser.add_argument("conceptual", help="result of the conceptual group (JSON)")
    parser.add_argument("--audit", required=True, help="directory of the lenses' scripts and outputs")
    parser.add_argument("--mapping", default=str(HERE / "mapping.yaml"))
    parser.add_argument("--out", default=str(DATA))
    args = parser.parse_args()
    audit = Path(args.audit).resolve()
    with open(args.mapping, encoding="utf-8") as fh:
        mapping = yaml.safe_load(fh)
    lenses = load_groups([args.formal, args.conceptual])
    findings, verdicts = build_findings_and_verdicts(lenses, mapping, audit, index_files(audit))
    references = build_references(lenses, mapping, audit)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    write_csv(out / "findings.csv", relative_paths(findings, audit))
    write_csv(out / "verdicts.csv", relative_paths(verdicts, audit))
    write_csv(out / "references.csv", relative_paths(references, audit))

    print(f"findings: {len(findings)} ({Counter(r['raised_by'] for r in findings)})")
    print(f"verdicts: {len(verdicts)}; references: {len(references)}")
    for lens in dict.fromkeys(r["lens"] for r in findings):
        rows = [r for r in findings if r["lens"] == lens]
        lens_sev = Counter(r["severity_lens"] for r in rows if r["raised_by"] == "lens")
        ver_sev = Counter(r["severity_verified"] or "-" for r in rows)
        print(f"  {lens}: lens {dict(lens_sev)}; verified {dict(ver_sev)}")


if __name__ == "__main__":
    main()
