"""Regenerate the requirement inventory from the current spec and owner ledgers.

This updates documentation only. Revision overrides reset changed contracts for
implementation reassessment while preserving their prior recorded statuses.
"""
import json
import re
from pathlib import Path

base = Path(__file__).resolve().parent
spec = base.parent / 'Improvement_Spec_2026-09-04'
validation = json.loads((spec / 'validation.json').read_text())
assert validation['status'] == 'passed', 'Run validate_spec.py and resolve errors first.'
ledgers = {}
for file in sorted(base.glob('*Status.md')):
    for line in file.read_text().splitlines():
        match = re.match(r'\| ((?:[A-Z0-9]+-)+\d+) \| ([^|]+) \| (.*)', line)
        if match:
            ledgers[match[1]] = (match[2].strip(), match[3].replace('|', ';').strip(' ;'), file.name)
revision_path = base / 'AI_Direction_Revision_Status.json'
revision = json.loads(revision_path.read_text()) if revision_path.exists() else {'requirements': []}
overrides = {row['id']: row for row in revision['requirements']}
rows = []
for requirement in validation['requirements']:
    ident = requirement['id']
    status, note, ledger = ledgers.get(ident, ('not closed', 'Implementation/acceptance remains unverified.', ''))
    override = overrides.get(ident)
    if override:
        status, note, ledger = override['status'], override['reason'], 'AI_Direction_Revision_Status.md'
    row = dict(id=ident, title=requirement['title'],
               specification='../Improvement_Spec_2026-09-04/' + requirement['file'] + '#' + ident.lower(),
               status=status, implementation_ledger=ledger, evidence_and_remaining_work=note)
    if override:
        row['previous_specification_status'] = override['priorStatus']
        row['reassessment_version'] = revision['specificationVersion']
    rows.append(row)
expected = validation['requirement_count']
assert len(rows) == expected and len({row['id'] for row in rows}) == expected
assert set(overrides).issubset({row['id'] for row in rows}), 'Revision contains an unknown requirement.'
assert all(row['implementation_ledger'] for row in rows), [row['id'] for row in rows if not row['implementation_ledger']]
result = dict(specificationVersion=validation['specification_version'], requirementCount=expected,
              distributionCertified=False,
              statusMeaning='Implemented means source present for its recorded scope, not all acceptance gates passed. Changed v1.1 contracts require reassessment; this documentation revision implements no app behavior.',
              previousStatusLedger='Previous_Requirement_Traceability_v1_0.json', requirements=rows)
(base / 'Requirement_Traceability.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(f'All {expected} normative requirements are accounted for; {len(overrides)} require v1.1 reassessment.')
