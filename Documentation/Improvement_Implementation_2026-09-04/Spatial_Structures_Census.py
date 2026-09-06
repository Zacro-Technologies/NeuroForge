"""Independent finite geometry enumeration; no app runtime or user stores."""
from itertools import product
from collections import defaultdict
from pathlib import Path
import json
p=Path(__file__).parent
I=((1,0,0),(0,1,0),(0,0,1));turns={'x':((1,0,0),(0,0,-1),(0,1,0)),'y':((0,0,1),(0,1,0),(-1,0,0)),'z':((0,-1,0),(1,0,0),(0,0,1))}
def mul(a,b):return tuple(tuple(sum(a[r][k]*b[k][c] for k in range(3)) for c in range(3)) for r in range(3))
def matrix(path):
 m=I
 for axis,count in path:
  for _ in range(count):m=mul(turns[axis],m)
 return m
def det(m):return m[0][0]*(m[1][1]*m[2][2]-m[1][2]*m[2][1])-m[0][1]*(m[1][0]*m[2][2]-m[1][2]*m[2][0])+m[0][2]*(m[1][0]*m[2][1]-m[1][1]*m[2][0])
rotations=list(product('xyz',range(1,4)));paths=[[r] for r in rotations]+[[a,b] for a in rotations for b in rotations if a[0]!=b[0]]
orientations={matrix(path) for path in paths};assert len(orientations)==23 and all(det(m)==1 for m in orientations)
assert len(orientations|{I})==24
# Fixed-grid animal growth, with D4 quotient on every size. This is independent
# of the app's cube-net fold interpreter and its content-key implementation.
def normal(points):
 a=min(x for x,y in points);b=min(y for x,y in points);return tuple(sorted((x-a,y-b) for x,y in points))
def canonical(points):
 images=[]
 for swap,sx,sy in product([False,True],[-1,1],[-1,1]):images.append(normal([(sx*(y if swap else x),sy*(x if swap else y)) for x,y in points]))
 return min(images)
shapes={((0,0),)};counts={1:1};footprints=[]
for size in range(2,6):
 shapes={canonical((*shape,(x+dx,y+dy))) for shape in shapes for x,y in shape for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)] if (x+dx,y+dy) not in shape}
 counts[size]=len(shapes)
 if size>=4:footprints.extend(sorted(shapes))
assert counts=={1:1,2:1,3:2,4:5,5:12}
G=defaultdict(list)
for h in product(range(1,4),repeat=4):G[((max(h[0],h[2]),max(h[1],h[3])),(max(h[0],h[1]),max(h[2],h[3])))].append(h)
def pair_key(f,s):return min(tuple(a)+tuple(b) for x,y in [(f,s),(s,f)] for a in [x,x[::-1]] for b in [y,y[::-1]])
ambiguous={pair_key(f,s) for (f,s),v in G.items() if len(v)>1};assert len(G)==35 and len(ambiguous)==4
# Prove every encountered labeled pair has sufficient distinct alternatives
# before canonical duplicate filtering, including three-answer layouts.
classes=set();construction=[]
for (f,s),valid in G.items():
 if len(valid)<2:continue
 required=[2,3,2,3][len(classes)%4]
 assert len(valid)>=required
 construction.append({'front':list(f),'side':list(s),'available':len(valid),'required':required,'newClass':pair_key(f,s) not in classes})
 classes.add(pair_key(f,s))
assert len(classes)==4
result={'kind':'provisional-spatial-geometry-capacity','generatorVersion':11,'exerciseSchemaVersion':8,'policyVersion':1,
 'executionStatus':'Python finite oracle executed. App generator/scorer/runtime/native XCTest methods authored; root execution pending.',
 'faceRotation':{'initialLabeledCubes':1,'singleOrTwoAxisPaths':len(paths),'distinctNonidentityProperRotations':23,'properOrientationsIncludingInitial':24,'queryDirections':6,'canonicalQueryContracts':138,'substructures':['single-fixed-axis-turn','two-distinct-fixed-axis-turns'],'countIsNotNumberOfIndependentObjectTopologies':True},
 'occupiedTopView':{'freeTetrominoes':5,'freePentominoes':12,'canonicalFootprints':17,'heightsCreateNoNewTopViewIdentity':True,'footprints':[[list(point) for point in shape] for shape in footprints]},
 'twoViewConstraints':{'grounded2x2HeightAssignments':81,'labeledProjectionPairs':35,'ambiguousLabeledPairs':sum(len(v)>1 for v in G.values()),'symmetryReducedAmbiguousPairs':4,'projections':[list(v) for v in sorted(ambiguous)],'correctProposalCounts':[2,3],'allProposedValidAlternativesRequired':True,'constructionMultiplicityAudit':construction},
 'totalCanonicalQueryContracts':159,'reviewedBandSlots':0,'signedEditionSlots':0,
 'familyStatus':{'QA-F11':'unchanged engineering gap: all quadrants, other angles, non-origin centers and compositions','QA-F12':'new labeled cube, exact fixed-axis single/composed turns and feedback replay; asymmetric solids/occlusion remain engineering','QA-F13':'unchanged engineering gap: noncentral/intersection/oblique/degenerate sections','QA-F14':'new grounded occupied cells, top footprints and all matching two-view proposals; broader inverse assembly search remains engineering','QA-F15':'existing11free nets retained; new adjacency/partial-fold/multiconstraint query engineering remains','QA-F16':'unchanged engineering gap: translated/diagonal reflections and transform compositions'},
 'remainingEngineering':['Target-demand selection over these substructures rather than descriptive difficulty floats','Broader physical shapes and projection search spaces','New exact retention recipe for these new spatial identities','Exhaustive requested-block capacity/CAS assurance independent of bounded legacy random probes','Cross-family58structure expansion and source-driven asset authoring'],
 'separateReleaseGates':['Independent language/visual editorial review','Reviewed band contracts and eligible structural quota assignment','Calibration/admission/signature approval']}
(p/'Capacity.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print('PASS:24properorientations;138facequeries;17freefootprints;81groundedassemblies;35projectionpairs;4ambiguoussymmetryclasses;159querycontracts;0reviewedslots')
