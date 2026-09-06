"""Regenerate the256-requirement inventory from the specification and owner ledgers."""
import json, re
from pathlib import Path
base=Path(__file__).resolve().parent
spec=base.parent/'Improvement_Spec_2026-09-04'
ledgers={}
for file in base.glob('*Status.md'):
    for line in file.read_text().splitlines():
        m=re.match(r'\| ((?:[A-Z0-9]+-)+\d+) \| ([^|]+) \| (.*)',line)
        if m: ledgers[m[1]]=(m[2].strip(),m[3].replace('|',';').strip(' ;'),file.name)
rows=[]
for name in ['README.md','01_Experience_and_Interaction.md','02_Content_and_Scoring.md','03_Adaptive_Learning_and_Evidence.md','04_Runtime_Data_and_Migration.md','05_QA_and_Delivery.md']:
    for m in re.finditer(r'(?:\*\*|### )((?:[A-Z0-9]+-)+\d+) — ([^\n]+)',(spec/name).read_text()):
        ident=m[1]
        status,note,ledger=ledgers.get(ident,('not closed','Implementation/acceptance remains unverified.',''))
        rows.append(dict(id=ident,title=m[2].split('.**')[0].replace('**',''),specification='../Improvement_Spec_2026-09-04/'+name+'#'+ident.lower(),status=status,implementation_ledger=ledger,evidence_and_remaining_work=note))
assert len(rows)==256 and len({r['id'] for r in rows})==256
assert all(r['implementation_ledger'] for r in rows),[r['id'] for r in rows if not r['implementation_ledger']]
(base/'Requirement_Traceability.json').write_text(json.dumps(dict(specificationVersion='1.0',requirementCount=256,distributionCertified=False,statusMeaning='Implemented means source present, not all acceptance gates passed. Executed validation is recorded separately.',requirements=rows),ensure_ascii=False,indent=2)+'\n')
print('All256 normative requirements are accounted for.')
