#!/usr/bin/env python3
"""Build the reading artifacts and validate this documentation package.

Run from any directory with Python 3. This does not build or modify the app.
The six source Markdown documents remain the editing authority.
"""

from collections import Counter
from pathlib import Path
from urllib.parse import unquote
import json
import re


ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
FILES = [
    "README.md",
    "01_Experience_and_Interaction.md",
    "02_Content_and_Scoring.md",
    "03_Adaptive_Learning_and_Evidence.md",
    "04_Runtime_Data_and_Migration.md",
    "05_QA_and_Delivery.md",
]
PREFIXES = "PRD|UX|INT|A11Y|COPY|CON|SCO|ADP|EVD|SCH|CORE|RUN|DATA|MIG|QA-REQ|DEL"
ID = rf"(?:{PREFIXES})-\d{{3}}"
HEADING = re.compile(rf"^#{{2,4}}\s+({ID})\s+—\s+(.+)$")
BOLD = re.compile(rf"^\*\*({ID})\s+—\s+(.+?)\*\*")
REF = re.compile(rf"\b({ID})\b")
LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
errors = []
requirements = []
texts = {}


def definition(line):
    return HEADING.match(line) or BOLD.match(line)


# Stable explicit anchors also work for requirements defined as bold paragraphs.
for name in FILES:
    path = ROOT / name
    lines = path.read_text().splitlines()
    output = []
    for line in lines:
        found = definition(line)
        if found:
            anchor = f'<a id="{found[1].lower()}"></a>'
            preceding = [value for value in output[-3:] if value.strip()]
            if not preceding or preceding[-1] != anchor:
                output.extend([anchor, ""])
        output.append(line.rstrip())
    updated = "\n".join(output) + "\n"
    if updated != path.read_text():
        path.write_text(updated)
    texts[name] = updated
    for number, line in enumerate(output, 1):
        found = definition(line)
        if found:
            requirements.append({
                "id": found[1], "title": found[2].rstrip("."),
                "file": name, "line": number, "status": "specified",
            })

counts = Counter(row["id"] for row in requirements)
errors.extend(f"Duplicate requirement: {key}" for key, n in counts.items() if n != 1)
known = set(counts)

index = [
    "# NeuroForge requirement index", "",
    "Generated from the six authoritative specification documents by `validate_spec.py`. "
    "All requirements are **specified**; this index does not mark future implementation as verified.", "",
    f"**{len(requirements)} unique normative requirements.** "
    "Test/fixture IDs and audit findings are additional references, not included in this count.", "",
    "[Master specification](README.md) · [Complete reading copy](Complete_Specification.md) "
    "· [Documentation validation](Specification_Validation.md)", "",
]
for name in FILES:
    rows = [row for row in requirements if row["file"] == name]
    index.extend([f"## {texts[name].splitlines()[0].lstrip('# ')}", "",
                  f"{len(rows)} requirements in [{name}]({name}).", "",
                  "| Requirement | Contract | Status |", "|---|---|---|"])
    for row in rows:
        index.append(f'| [{row["id"]}]({name}#{row["id"].lower()}) | {row["title"]} | Specified |')
    index.append("")
(ROOT / "Requirement_Index.md").write_text("\n".join(index) + "\n")

combined = [
    "# NeuroForge — Complete improvement specification", "",
    "**5 September 2026 · Version 1.1 · AI-centered product direction · Specification only**", "",
    "This generated reading copy combines the master and five chapters. "
    "Edit the source chapters, then run `validate_spec.py` to rebuild it. "
    "It specifies future behavior; it does not certify that the app implements it.", "",
    "[Reading guide](README.md) · [Requirement index](Requirement_Index.md)", "",
]
for name in FILES:
    combined.extend(["---", "", f"<!-- Source: {name} -->", "", texts[name].rstrip(), ""])
(ROOT / "Complete_Specification.md").write_text("\n".join(combined) + "\n")

table_problems = []
for name, content in texts.items():
    for ref in set(REF.findall(content)):
        if ref not in known:
            errors.append(f"Undefined requirement {ref} in {name}")
    fence = None
    expected_cells = None
    for number, line in enumerate(content.splitlines(), 1):
        if line.startswith(("```", "~~~")):
            marker = line[:3]
            fence = None if fence == marker else marker
            expected_cells = None
            continue
        if fence:
            continue
        if line.startswith("|"):
            cells = len(re.findall(r"(?<!\\)\|", line)) - 1
            if expected_cells is None:
                expected_cells = cells
            elif cells != expected_cells:
                table_problems.append(f"{name}:{number}: {cells} table cells, expected {expected_cells}")
        else:
            expected_cells = None
    if fence:
        errors.append(f"Unclosed code fence: {name}")
    if re.search(r"\b(?:TODO|TBD|FIXME)\b", content):
        errors.append(f"Unresolved placeholder marker: {name}")
errors.extend(table_problems)

family_ids = re.findall(r'^\s*activity\("([^"]+)"',
                        (REPO / "Sources/TrainingEngine/NFDefaultContentCatalog.swift").read_text(), re.M)
matrix_ids = re.findall(r"^\| QA-F\d{2} — `([^`]+)`", texts[FILES[2]], re.M)
if len(family_ids) != 58 or matrix_ids != family_ids:
    errors.append(f"Family matrix mismatch: catalog={len(family_ids)}, matrix={len(matrix_ids)}")

simulation_ids = re.findall(r"^\| ((?:ADP|EVD|SCH)-F\d{2}) —", texts[FILES[3]], re.M)
journey_ids = re.findall(r"^\| (T-[CRAG]\d{2}) \|", texts[FILES[5]], re.M)
for label, values, expected in [("simulation", simulation_ids, 60), ("acceptance", journey_ids, 80)]:
    if len(values) != expected or len(set(values)) != expected:
        errors.append(f"Unexpected {label} fixture count: {len(values)}/{len(set(values))}, expected {expected}")

missing_audit = [f"QA-{n:02d}" for n in range(1, 18)
                 if not re.search(rf"^\| QA-{n:02d}\b", texts["README.md"], re.M)]
errors.extend(f"Unmapped audit finding {value}" for value in missing_audit)

source_word_count = sum(len(value.split()) for value in texts.values())
report = {
    "scope": "Documentation validation only; no application acceptance tests run by this script.",
    "specification_version": "1.1",
    "revision_date": "2026-09-05",
    "source_word_count": source_word_count,
    "requirement_count": len(requirements),
    "requirements_by_source": dict(Counter(row["file"] for row in requirements)),
    "catalog_families_mapped": len(matrix_ids),
    "adaptive_simulation_fixtures": len(simulation_ids),
    "cross_chapter_acceptance_cases": len(journey_ids),
    "audit_findings_mapped": 17 - len(missing_audit),
    "requirements": requirements,
}
validation = [
    "# Specification documentation validation", "",
    "This validates the specification's structure and references. "
    "It does **not** establish that the proposed app behavior is implemented or tested.", "",
    "| Check | Result |", "|---|---|",
    f"| Authoritative source documents | {len(FILES)} |",
    f"| Source word count (whitespace-delimited, including tables/anchors) | {source_word_count:,} |",
    f"| Unique normative requirements | {len(requirements)} |",
    f"| Current catalog families mapped in exact source order | {len(matrix_ids)}/58 |",
    f"| Adaptive/evidence/scheduling simulation fixtures | {len(simulation_ids)} |",
    f"| Cross-chapter content/runtime/adaptive/AI acceptance cases | {len(journey_ids)} |",
    f"| Audited priority findings traced to requirements/tests | {17-len(missing_audit)}/17 |",
    "",
    "The content chapter additionally defines per-family validation, scoring suites and bank suites. "
    "This revision aligns AI tutoring and rubric grading, local/cloud availability, retained grade replay, "
    "source learning and operational recovery. These document checks do not substitute for human "
    "grading adjudication, usability research or actual model evaluations.", "",
    "Reproduce with `python3 Documentation/Improvement_Spec_2026-09-04/validate_spec.py` "
    "from the repository root. Generated artifacts are the requirement index, complete reading copy, "
    "this summary and `validation.json`.", "",
]
(ROOT / "Specification_Validation.md").write_text("\n".join(validation) + "\n")

# Validate local targets and explicit requirement anchors, including generated outputs.
for path in ROOT.glob("*.md"):
    for raw_target in LINK.findall(path.read_text()):
        target = raw_target.strip("<>")
        if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target):
            continue
        target_path, _, fragment = unquote(target).partition("#")
        resolved = (path.parent / target_path).resolve() if target_path else path
        if not resolved.exists():
            errors.append(f"Broken local link in {path.name}: {target}")
        elif fragment and re.fullmatch(ID.lower(), fragment):
            if f'<a id="{fragment}"></a>' not in resolved.read_text():
                errors.append(f"Missing anchor in {path.name}: {target}")

report["errors"] = sorted(set(errors))
report["status"] = "passed" if not errors else "failed"
(ROOT / "validation.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
with (ROOT / "Specification_Validation.md").open("a") as output:
    output.write(f'\n**Structural validation: {report["status"].upper()}.**\n')
    for error in report["errors"]:
        output.write(f"\n- {error}\n")
print(json.dumps({key: value for key, value in report.items() if key != "requirements"}, indent=2))
raise SystemExit(0 if not errors else 1)
