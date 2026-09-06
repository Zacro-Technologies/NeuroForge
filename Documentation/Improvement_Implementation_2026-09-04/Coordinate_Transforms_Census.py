"""Independent homogeneous-matrix finite oracle; no app/user data."""
from pathlib import Path
from itertools import product
from math import gcd
from functools import reduce
from collections import Counter
import json
p=Path(__file__).parent
I=((1,0,0),(0,1,0),(0,0,1))
def mul(a,b):return tuple(tuple(sum(a[r][k]*b[k][c] for k in range(3)) for c in range(3)) for r in range(3))
def apply(m,p):return tuple(sum(m[r][k]*(*p,1)[k] for k in range(3)) for r in range(2))
def trans(x,y):return ((1,0,x),(0,1,y),(0,0,1))
def op(kind,*args):return (kind,args)
def matrix(o):
 kind,a=o
 if kind=='t':return trans(*a)
 if kind=='r':
  x,y,q=a;quarter=((0,-1,0),(1,0,0),(0,0,1));m=I
  for _ in range(q%4):m=mul(quarter,m)
  return mul(trans(x,y),mul(m,trans(-x,-y)))
 line,k=a
 n={'v':(1,0),'h':(0,1),'d':(1,-1),'n':(1,1)}[line];den=sum(v*v for v in n)
 return ((1-2*n[0]*n[0]//den,-2*n[0]*n[1]//den,2*k*n[0]//den),(-2*n[1]*n[0]//den,1-2*n[1]*n[1]//den,2*k*n[1]//den),(0,0,1))
def anchor(o):
 kind,a=o
 if kind=='r':return a[:2]
 if kind=='f':return (a[1],0) if a[0]=='v' else (0,a[1]) if a[0]=='h' else (0,0)
 return(0,0)
points=[(-3,-2),(-3,2),(3,-2),(3,2),(0,-3),(0,3),(-3,0),(3,0),(0,0),(2,2),(-2,-2),(2,-2),(-2,2),(1,-1)]
recipes=[]
for q in [-3,-2,-1,1,2,3]:recipes += [('rotateOrigin',[op('r',0,0,q)]),('rotateOffset',[op('r',1,-1,q)])]
recipes += [('translateThenRotate',[op('t',2,1),op('r',1,-1,1)]),('rotateThenTranslate',[op('r',1,-1,1),op('t',2,1)]),('reflectAxis',[op('f','v',0)]),('reflectAxis',[op('f','h',0)]),('reflectOffset',[op('f','v',1)]),('reflectOffset',[op('f','h',-1)]),('reflectDiagonal',[op('f','d',0)]),('reflectDiagonal',[op('f','n',0)]),('reflectTwice',[op('f','v',1),op('f','h',-1)]),('reflectTwice',[op('f','v',0),op('f','d',0)]),('rotateThenReflect',[op('r',1,-1,1),op('f','d',0)]),('reflectThenRotate',[op('f','d',0),op('r',1,-1,1)])]
sym=[]
for swap,x,y in product([False,True],[-1,1],[-1,1]):sym.append(((0,x,0),(y,0,0),(0,0,1)) if swap else ((x,0,0),(0,y,0),(0,0,1)))
def semantic(kind,ops,point):
 if len(ops)==1 and apply(matrix(ops[0]),point)==point:return kind+'.fixed-point'
 x,y=anchor(ops[0]);relative=(point[0]-x,point[1]-y);moves=[mul(trans(-x,-y),mul(matrix(o),trans(x,y))) for o in ops];versions=[]
 for s in sym:
  inv=tuple(tuple(s[c][r] for c in range(3)) for r in range(3));q=apply(s,relative);changed=[mul(s,mul(m,inv)) for m in moves]
  divisor=max(1,reduce(gcd,[abs(v) for v in (*q,*[v for m in changed for v in (m[0][2],m[1][2])])],0))
  flat=[q[0]//divisor,q[1]//divisor]+[v for m in changed for v in (m[0][0],m[0][1],m[1][0],m[1][1],m[0][2]//divisor,m[1][2]//divisor)]
  versions.append(','.join(map(str,flat)))
 return kind+'.'+min(versions)
keys=set();answers=[];kinds=Counter();fixed=0
for kind,ops in recipes:
 for point in points:
  state=point
  for o in ops:
   m=matrix(o);det=m[0][0]*m[1][1]-m[0][1]*m[1][0];assert abs(det)==1
   result=apply(m,state)
   assert all(-12<=v<=12 for v in result)
   for q in product(range(-3,4),repeat=2):
    r=apply(m,q);neighbor=(q[0]+1,q[1]-2);rn=apply(m,neighbor)
    assert sum((q[i]-neighbor[i])**2 for i in range(2))==sum((r[i]-rn[i])**2 for i in range(2))
    if o[0]=='f':assert apply(m,r)==q
   state=result
  keys.add(semantic(kind,ops,point));kinds[kind]+=1;answers.append(state);fixed+=state==point
assert len(answers)==336
out={'kind':'coordinate-transform-provisional-finite-census','policyVersion':1,'generatorVersion':12,'exerciseSchemaVersion':9,
 'executed':'Independent Python homogeneous matrix/distance/involution oracle. App/runtime tests authored, root execution pending.',
 'authoredOperationRecipes':len(recipes),'sourceCoverageCases':len(points),'exactParameterizedContracts':len(answers),
 'semanticQueryClassesAfterD4TranslationScaleAndFixedPointCanonicalization':len(keys),'substructureKinds':dict(kinds),
 'allQuadrants':True,'axisOriginSymmetryAndNamedCenterCases':True,'finalFixedPointCases':fixed,'answerBounds':[-12,12],
 'response':'Two typed exact numeric coordinates; half credit each; full correctness requires both.',
 'countsDoNotGrantIndependentTopologiesOrReviewedBands':True,'reviewedBandSlots':0,'signedEditionSlots':0,
 'remainingEngineering':['Unknown-transform inference from sufficient point correspondences','Scored orientation/fixed-point classification rather than post-response explanation','Broader authored transform families and demand-tier selection','Exact retention recipes for new identities','Requested-block feasibility independent of bounded legacy random probes','QA-F13 solid-plane intersections and QA-F15 varied folding queries'],
 'separateReleaseGates':['Independent editorial/visual/language review','Band admission and balanced quota assignment','Calibration and signature approval']}
(p/'Capacity.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');print(json.dumps(out,indent=2))
