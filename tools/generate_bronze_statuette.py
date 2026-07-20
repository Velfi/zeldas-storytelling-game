#!/usr/bin/env python3
"""Generate the low-poly Art Deco bronze statuette used by the Vale House case."""
import json, math, struct
from pathlib import Path

verts=[]; norms=[]; inds=[]

def add_uv_ellipsoid(center, scale, rings=10, seg=16):
    base=len(verts)
    for r in range(rings+1):
        p=math.pi*r/rings; sp,cp=math.sin(p),math.cos(p)
        for s in range(seg):
            t=2*math.pi*s/seg; ct,st=math.cos(t),math.sin(t)
            nx,ny,nz=sp*ct,sp*st,cp
            x=center[0]+scale[0]*nx; y=center[1]+scale[1]*ny; z=center[2]+scale[2]*nz
            # inverse-transpose normal for nonuniform scale
            q=(nx/scale[0],ny/scale[1],nz/scale[2]); l=math.sqrt(sum(v*v for v in q))
            verts.append((x,y,z)); norms.append(tuple(v/l for v in q))
    for r in range(rings):
        for s in range(seg):
            a=base+r*seg+s; b=base+r*seg+(s+1)%seg; c=base+(r+1)*seg+s; d=base+(r+1)*seg+(s+1)%seg
            inds.extend((a,c,b,b,c,d))

def add_tapered(a,b,ra,rb,seg=12,cap_start=True,cap_end=True):
    # ring axis with a stable orthonormal frame
    ax=tuple(b[i]-a[i] for i in range(3)); L=math.sqrt(sum(v*v for v in ax)); w=tuple(v/L for v in ax)
    ref=(0,0,1) if abs(w[2])<.9 else (0,1,0)
    u=(w[1]*ref[2]-w[2]*ref[1],w[2]*ref[0]-w[0]*ref[2],w[0]*ref[1]-w[1]*ref[0]); ul=math.sqrt(sum(v*v for v in u)); u=tuple(v/ul for v in u)
    v=(w[1]*u[2]-w[2]*u[1],w[2]*u[0]-w[0]*u[2],w[0]*u[1]-w[1]*u[0]); base=len(verts)
    for p,r in ((a,ra),(b,rb)):
        for i in range(seg):
            t=2*math.pi*i/seg; n=tuple(math.cos(t)*u[j]+math.sin(t)*v[j] for j in range(3))
            verts.append(tuple(p[j]+r*n[j] for j in range(3))); norms.append(n)
    for i in range(seg):
        # Counter-clockwise when viewed from outside. The old order pointed the
        # geometric faces inward even though the authored normals pointed out.
        j=(i+1)%seg; inds.extend((base+i,base+j,base+seg+i,base+j,base+seg+j,base+seg+i))
    # Close both ends. The start cap on the lowest plinth is the visible,
    # examinable underside when the statuette is turned over.
    if cap_start:
        center=len(verts); verts.append(a); norms.append(tuple(-n for n in w))
        for i in range(seg):
            j=(i+1)%seg; inds.extend((center,base+j,base+i))
    if cap_end:
        center=len(verts); verts.append(b); norms.append(w)
        for i in range(seg):
            j=(i+1)%seg; inds.extend((center,base+seg+i,base+seg+j))

def add_cylinder(z0,z1,r,seg=12): add_tapered((0,0,z0),(0,0,z1),r,r,seg)

def add_arc_band(z0,z1,r,start_angle,end_angle,seg=10):
    """Add a slightly raised, localized strip for a separate decal material."""
    base=len(verts)
    for z,nz in ((z0,-1),(z1,1)):
        for i in range(seg+1):
            t=start_angle+(end_angle-start_angle)*i/seg
            verts.append((math.cos(t)*r,math.sin(t)*r,z))
            norms.append((math.cos(t),math.sin(t),0))
    for i in range(seg):
        a=base+i; b=a+1; c=base+seg+1+i; d=c+1
        inds.extend((a,b,c,b,d,c))

# broad murder-weapon base, stepped plinth, and fan ornament
add_cylinder(0,.18,.66,8); add_cylinder(.18,.31,.54,8); add_cylinder(.31,.39,.43,12)
for i in range(-4,5):
    x=i*.095; h=.62+.07*(4-abs(i)); add_tapered((x,.13,.38),(x,.13,h),.055,.035,6)

# skirt, torso, neck, head and stylized waved hair
add_tapered((0,0,.38),(0,0,1.15),.35,.18,16)
add_uv_ellipsoid((0,0,1.30),(.22,.14,.29),10,16)
add_tapered((0,0,1.52),(0,0,1.61),.085,.075,12)
add_uv_ellipsoid((0,-.01,1.77),(.14,.12,.18),10,16)
add_uv_ellipsoid((0,.035,1.82),(.155,.13,.145),7,16)

# open arms in the same welcoming pose as the concept art
for side in (-1,1):
    add_tapered((side*.16,0,1.43),(side*.38,-.01,1.12),.075,.055,10)
    add_tapered((side*.38,-.01,1.12),(side*.58,-.03,.94),.055,.035,10)
    add_uv_ellipsoid((side*.62,-.03,.91),(.09,.045,.035),5,10)

# shoulder caps and central Art Deco chest accent
add_uv_ellipsoid((-.15,0,1.43),(.10,.12,.10),6,10); add_uv_ellipsoid((.15,0,1.43),(.10,.12,.10),6,10)
add_tapered((0,-.145,1.49),(0,-.175,1.12),.06,.018,6)

# A missed smear of dried blood caught in one section of the lower base seam.
# Its indices become a second glTF primitive below so it can have an independent
# non-metallic material without requiring decal support in the renderer.
blood_index_start=len(inds)
add_arc_band(.298,.322,.548,-math.pi*.82,-math.pi*.18,12)

# The modeling helpers use Z-up. glTF is Y-up, so rotate -90 degrees around X
# before serialization. This also keeps the statuette upright in the engine.
verts=[(x,z,-y) for x,y,z in verts]
norms=[(x,z,-y) for x,y,z in norms]
pos=b''.join(struct.pack('<3f',*p) for p in verts); nor=b''.join(struct.pack('<3f',*n) for n in norms)
bronze_idx=b''.join(struct.pack('<I',i) for i in inds[:blood_index_start]); blood_idx=b''.join(struct.pack('<I',i) for i in inds[blood_index_start:])
blob=bytearray()
def put(data):
    off=len(blob); blob.extend(data)
    while len(blob)%4: blob.append(0)
    return off,len(data)
po,pl=put(pos); no,nl=put(nor); bio,bil=put(bronze_idx); dio,dil=put(blood_idx)
mn=[min(p[i] for p in verts) for i in range(3)]; mx=[max(p[i] for p in verts) for i in range(3)]
g={"asset":{"version":"2.0","generator":"Chicago statuette generator"},"scene":0,"scenes":[{"nodes":[0]}],
"nodes":[{"mesh":0,"name":"Bronze_Statuette"}],"meshes":[{"name":"Art_Deco_Bronze_Statuette","primitives":[{"attributes":{"POSITION":0,"NORMAL":1},"indices":2,"material":0},{"attributes":{"POSITION":0,"NORMAL":1},"indices":3,"material":1}]}],
"materials":[{"name":"Aged Bronze","pbrMetallicRoughness":{"baseColorFactor":[.31,.14,.055,1],"metallicFactor":.92,"roughnessFactor":.32}},{"name":"Dried Blood In Base Seam","pbrMetallicRoughness":{"baseColorFactor":[.24,.012,.008,1],"metallicFactor":.05,"roughnessFactor":.78}}],
"buffers":[{"byteLength":len(blob)}],"bufferViews":[{"buffer":0,"byteOffset":po,"byteLength":pl,"target":34962},{"buffer":0,"byteOffset":no,"byteLength":nl,"target":34962},{"buffer":0,"byteOffset":bio,"byteLength":bil,"target":34963},{"buffer":0,"byteOffset":dio,"byteLength":dil,"target":34963}],
"accessors":[{"bufferView":0,"componentType":5126,"count":len(verts),"type":"VEC3","min":mn,"max":mx},{"bufferView":1,"componentType":5126,"count":len(norms),"type":"VEC3"},{"bufferView":2,"componentType":5125,"count":blood_index_start,"type":"SCALAR"},{"bufferView":3,"componentType":5125,"count":len(inds)-blood_index_start,"type":"SCALAR"}]}
j=json.dumps(g,separators=(',',':')).encode(); j+=b' ' *((4-len(j)%4)%4)
total=12+8+len(j)+8+len(blob)
out=struct.pack('<4sII',b'glTF',2,total)+struct.pack('<I4s',len(j),b'JSON')+j+struct.pack('<I4s',len(blob),b'BIN\0')+blob
path=Path(__file__).resolve().parents[1]/'assets/models/bronze-statuette.glb'; path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(out)
print(f'{path} ({len(verts)} vertices, {len(inds)//3} triangles, {len(out)} bytes)')
