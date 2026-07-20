#!/usr/bin/env python3
"""Generate the Vale House study rug in laid-out and folded states."""
import json, math, struct
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT=Path(__file__).resolve().parents[1]; OUT=ROOT/"assets/rugs"; TEX=OUT/"textures"; S=512

def make_texture(folded=False):
    im=Image.new("RGBA",(S,S),(91,25,29,255)); d=ImageDraw.Draw(im,"RGBA")
    # Worn navy and ochre guard borders.
    for inset,color,width in [(10,(202,158,80,255),8),(25,(27,45,54,255),15),(47,(186,126,61,255),6),(61,(52,25,30,255),5)]:
        d.rectangle((inset,inset,S-1-inset,S-1-inset),outline=color,width=width)
    # Repeating period-appropriate medallions.
    for row,y in enumerate(range(96,438,64)):
        for col,x in enumerate(range(82,442,72)):
            ochre=(190,133,63,235); blue=(30,62,68,235)
            d.polygon((x,y-21,x+18,y,x,y+21,x-18,y),fill=ochre)
            d.ellipse((x-7,y-7,x+7,y+7),fill=blue)
            if (row+col)%2: d.line((x-15,y,x+15,y),fill=(226,190,116,150),width=2)
    # Directional textile weave and age wear.
    for y in range(0,S,5): d.line((0,y,S,y+1),fill=(20,13,12,38),width=1)
    for x in range(0,S,7): d.line((x,0,x+1,S),fill=(245,220,172,20),width=1)
    for i in range(180):
        x=(i*83)%S; y=(i*157+i//5)%S; length=5+(i*13)%31
        d.line((x,y,min(S-1,x+length),y),fill=(218,190,141,20+(i%4)*10),width=1)
    # A restrained dark tide mark near one end; evidence, not gore.
    stain=Image.new("RGBA",im.size,(0,0,0,0)); sd=ImageDraw.Draw(stain,"RGBA")
    sd.ellipse((326,344,474,473),fill=(48,17,19,68)); sd.ellipse((355,372,452,460),fill=(35,12,15,45))
    stain=stain.filter(ImageFilter.GaussianBlur(18)); im=Image.alpha_composite(im,stain)
    if folded:
        # Fold-state source is slightly darker from compressed pile.
        shade=Image.new("RGBA",im.size,(35,25,20,18)); im=Image.alpha_composite(im,shade)
    return im

def rounded_ring(w,d,n=32):
    out=[]; p=4.5
    for i in range(n):
        a=2*math.pi*i/n; ca,sa=math.cos(a),math.sin(a)
        out.append((w/2*math.copysign(abs(ca)**(2/p),ca),d/2*math.copysign(abs(sa)**(2/p),sa)))
    return out

def add_slab(ps,ns,uv,ix,w,d,h,y=0,xoff=0,zoff=0):
    r=rounded_ring(w,d); n=len(r); base=len(ps)
    ps.append((xoff,y+h,zoff)); ns.append((0,1,0)); uv.append((.5,.5))
    for x,z in r: ps.append((x+xoff,y+h,z+zoff)); ns.append((0,1,0)); uv.append((x/w+.5,z/d+.5))
    # In the runtime's right-handed X/Y/Z basis, +X crossed with +Z points
    # toward -Y. Reverse the X/Z contour order so the top faces and +Y normals
    # agree.
    for i in range(n): ix += [base,base+1+(i+1)%n,base+1+i]
    for i,(x,z) in enumerate(r):
        x2,z2=r[(i+1)%n]; nx,nz=z2-z,-(x2-x); q=math.hypot(nx,nz); nx,nz=nx/q,nz/q; b=len(ps)
        ps += [(x+xoff,y,z+zoff),(x2+xoff,y,z2+zoff),(x2+xoff,y+h,z2+zoff),(x+xoff,y+h,z+zoff)]
        ns += [(nx,0,nz)]*4; uv += [(i/n,1),((i+1)/n,1),((i+1)/n,0),(i/n,0)]; ix += [b,b+2,b+1,b,b+3,b+2]

def write_glb(name,slabs,png):
    ps=[]; ns=[]; uv=[]; ix=[]
    for slab in slabs: add_slab(ps,ns,uv,ix,*slab)
    def f32(a): return struct.pack("<"+"f"*len(a),*a)
    def u32(a): return struct.pack("<"+"I"*len(a),*a)
    chunks=[f32([v for p in ps for v in p]),f32([v for p in ns for v in p]),f32([v for p in uv for v in p]),u32(ix),png.read_bytes()]
    blob=bytearray(); views=[]
    for c in chunks:
        while len(blob)%4: blob.append(0)
        views.append({"buffer":0,"byteOffset":len(blob),"byteLength":len(c)}); blob.extend(c)
    mn=[min(p[i] for p in ps) for i in range(3)]; mx=[max(p[i] for p in ps) for i in range(3)]
    doc={"asset":{"version":"2.0","generator":"Vale House study rug generator"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":name,"mesh":0}],"meshes":[{"name":name,"primitives":[{"attributes":{"POSITION":0,"NORMAL":1,"TEXCOORD_0":2},"indices":3,"material":0}]}],"materials":[{"name":"worn_wool","pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicFactor":0,"roughnessFactor":.96}}],"textures":[{"sampler":0,"source":0}],"samplers":[{"magFilter":9729,"minFilter":9729,"wrapS":10497,"wrapT":10497}],"images":[{"mimeType":"image/png","bufferView":4}],"buffers":[{"byteLength":len(blob)}],"bufferViews":views,"accessors":[{"bufferView":0,"componentType":5126,"count":len(ps),"type":"VEC3","min":mn,"max":mx},{"bufferView":1,"componentType":5126,"count":len(ns),"type":"VEC3"},{"bufferView":2,"componentType":5126,"count":len(uv),"type":"VEC2"},{"bufferView":3,"componentType":5125,"count":len(ix),"type":"SCALAR"}]}
    js=json.dumps(doc,separators=(",",":")).encode(); js+=b" "*((4-len(js)%4)%4)
    while len(blob)%4: blob.append(0)
    total=28+len(js)+len(blob); data=struct.pack("<4sII",b"glTF",2,total)+struct.pack("<I4s",len(js),b"JSON")+js+struct.pack("<I4s",len(blob),b"BIN\0")+blob
    (OUT/(name+".glb")).write_bytes(data)

def main():
    TEX.mkdir(parents=True,exist_ok=True)
    laid=TEX/"study_rug_unfolded_basecolor.png"; make_texture().save(laid,optimize=True)
    folded=TEX/"study_rug_folded_basecolor.png"; make_texture(True).save(folded,optimize=True)
    write_glb("study_rug_unfolded",[(2.45,1.42,.045,0,0,0)],laid)
    # Unequal stepped panels make the folded state legible even when previews normalize scale.
    write_glb("study_rug_folded",[(.88,.72,.05,0,-.06,0),(.66,.72,.05,.052,.08,.012),(.44,.72,.05,.104,-.15,.026)],folded)
    print("generated study_rug_unfolded and study_rug_folded")
if __name__=="__main__": main()
