from pathlib import Path
import re,json,hashlib
p=Path(__file__).parent;a=p/'attachments'
net=(a/'0AFEE0D5-6289-4E6F-8BB8-D3D1EC2584FF.txt').read_text()
cells={label:(int(x),int(y)) for label,x,y in re.findall(r'([A-F]): \((-?\d+), (-?\d+)\)',net)}
neg=lambda a:tuple(-x for x in a)
frames={'A':((1,0,0),(0,1,0),(0,0,1))};queue=['A']
for label in queue:
 r,u,n=frames[label];x,y=cells[label]
 for other,(xx,yy) in cells.items():
  delta=(xx-x,yy-y)
  if delta==(1,0):next_frame=(neg(n),u,r)
  elif delta==(-1,0):next_frame=(n,u,neg(r))
  elif delta==(0,1):next_frame=(r,neg(n),u)
  elif delta==(0,-1):next_frame=(r,n,neg(u))
  else:continue
  if other in frames:assert frames[other]==next_frame
  else:frames[other]=next_frame;queue.append(other)
assert len(frames)==6 and len({n for r,u,n in frames.values()})==6
text=json.loads((p/'Cube_Worked_AX_Snapshot_Strings.json').read_text())[0]['strings'][0]
rendered={name:((int(nx),int(ny),int(nz)),(int(ux),int(uy),int(uz))) for name,nx,ny,nz,ux,uy,uz in re.findall(r'([A-F]) normal (-?\d+),(-?\d+),(-?\d+), arrow (-?\d+),(-?\d+),(-?\d+)',text)}
expected={name:(n,u) for name,(r,u,n) in frames.items()}
assert expected==rendered
assert sum(x*y for x,y in zip(expected['C'][0],expected['A'][0]))==0 # adjacent, not opposite
assert expected['C'][1]==(0,0,-1)
coordinate=(a/'060BF42A-8C80-493E-883C-66F51AE7E947.txt').read_text()
assert 'Q = (-2, -3)' in coordinate and '90° counterclockwise about (0, 0)' in coordinate
q=(-2,-3);original=(q[1],-q[0]);assert original==(-3,2)
result={'cube_public_cells':cells,'cube_independently_folded_normals_and_printed_arrows':expected,
 'cube_complete_AX_text_matches_independent_fold':True,
 'cube_proposal':{'C_and_A_opposite':False,'C_arrow_negative_z':True,'both_rules':False},
 'coordinate_public_Q':q,'coordinate_original_P':original,'coordinate_forward_rotation_returns_Q':(-original[1],original[0])==q,
 'limits':'Pure check of exported public givens and exported AX text only; visual visibility evaluated separately. No app/scorer functions or private keys were read.'}
(p/'Public_Givens_Check.json').write_text(json.dumps(result,indent=2)+'\n')
print('PASS: all six net normals/arrows match exported text; proposed opposite relation is false; coordinate inverse is (-3, 2).')
