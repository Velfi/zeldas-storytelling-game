#!/usr/bin/env python3
"""Create original textured rug/mat GLBs for the Chicago editor."""
import json, math, struct
from pathlib import Path
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]; OUT=ROOT/"assets/rugs"; TEX=OUT/"textures"; S=512

def img(c): return Image.new("RGBA",(S,S),c)
def woven(im, step=6):
 d=ImageDraw.Draw(im,"RGBA")
 for n in range(0,S,step): d.line((0,n,S,n+2),fill=(25,18,12,45)); d.line((n,0,n+2,S),fill=(255,245,220,25))
def frame(d, cols):
 for i,c in enumerate(cols): d.rectangle((10+i*14,10+i*14,S-11-i*14,S-11-i*14),outline=c,width=7)
def coir():
 im=img((158,94,44,255)); woven(im,7); frame(ImageDraw.Draw(im),[(66,38,21,255),(218,151,77,255)]); return im
def persian():
 im=img((105,22,27,255)); d=ImageDraw.Draw(im); frame(d,[(225,184,99,255),(25,53,64,255),(205,134,61,255)])
 for y in range(80,440,64):
  for x in range(70,450,64): d.polygon((x,y-19,x+17,y,x,y+19,x-17,y),fill=(211,150,65,255)); d.ellipse((x-6,y-6,x+6,y+6),fill=(28,65,70,255))
 woven(im,5); return im
def braided():
 im=img((188,140,82,255)); d=ImageDraw.Draw(im)
 for r in range(250,5,-8): d.ellipse((256-r,256-r,256+r,256+r),outline=((115+r)%170+50,105,55,255),width=5)
 return im
def kilim():
 im=img((218,185,120,255)); d=ImageDraw.Draw(im); cs=[(30,67,72,255),(178,58,35,255),(224,148,47,255),(75,45,57,255)]
 for y in range(-20,550,92):
  for x in range(-20,550,92):
   c=cs[((x+20)//92+(y+20)//92)%4]; d.polygon((x,y-39,x+39,y,x,y+39,x-39,y),fill=c); d.polygon((x,y-15,x+15,y,x,y+15,x-15,y),fill=(235,207,149,255))
 frame(d,[cs[0],cs[1]]); woven(im,4); return im
def shag():
 im=img((201,190,166,255)); d=ImageDraw.Draw(im,"RGBA")
 for i in range(8500):
  x=(i*73)%S; y=(i*151+i//17)%S; q=158+(i*29)%70; d.line((x,y,x+i%5-2,y+4),fill=(q,q-7,q-19,110))
 return im
def rubber():
 im=img((37,42,43,255)); d=ImageDraw.Draw(im)
 for y in range(-30,550,38):
  for x in range(-30,550,38): d.rounded_rectangle((x+(19 if y//38%2 else 0),y,x+20+(19 if y//38%2 else 0),y+8),4,fill=(79,85,83,255))
 frame(d,[(17,19,19,255)]); return im
def bamboo():
 im=img((194,137,66,255)); d=ImageDraw.Draw(im)
 for x in range(0,S,28):
  d.rectangle((x,0,x+22,S),fill=(193+(x//28)%3*9,134+(x//28)%2*12,62,255)); d.line((x+23,0,x+23,S),fill=(72,49,27,255),width=4)
  for y in range(60+x%51,S,128): d.line((x,y,x+22,y),fill=(111,74,31,255),width=3)
 for y in (90,420): d.line((0,y,S,y),fill=(47,42,29,255),width=7)
 return im
def patchwork():
 im=img((160,120,83,255)); d=ImageDraw.Draw(im); cs=[(145,49,41,255),(33,91,101,255),(184,138,61,255),(109,76,92,255),(198,173,128,255)]
 for y in range(0,S,128):
  for x in range(0,S,128): d.rectangle((x+3,y+3,x+125,y+125),fill=cs[(x//128+3*y//128)%5],outline=(55,40,30,255),width=4)
 woven(im); return im

ASSETS=[("coir_doormat","rounded",1.4,.82,.055,coir),("persian_runner","rounded",2.5,.78,.035,persian),("braided_round_rug","round",1.55,1.55,.035,braided),("geometric_kilim","rect",1.8,1.15,.028,kilim),("cream_shag_rug","round",1.72,1.35,.065,shag),("rubber_utility_mat","rounded",1.35,.9,.045,rubber),("bamboo_slat_mat","rect",1.5,.95,.04,bamboo),("patchwork_rug","rounded",1.65,1.1,.04,patchwork)]

def ring(kind,w,d):
 if kind=="rect": return [(-w/2,-d/2),(w/2,-d/2),(w/2,d/2),(-w/2,d/2)]
 n=48 if kind in ("round","scallop") else 32; out=[]
 for i in range(n):
  a=2*math.pi*i/n
  if kind=="round": x,z=math.cos(a)*w/2,math.sin(a)*d/2
  elif kind=="scallop": q=1+.075*math.cos(6*a); x,z=math.cos(a)*w/2*q,math.sin(a)*d/2*q
  else:
   p=4.5; x=w/2*math.copysign(abs(math.cos(a))**(2/p),math.cos(a)); z=d/2*math.copysign(abs(math.sin(a))**(2/p),math.sin(a))
  out.append((x,z))
 return out
def f32(a): return struct.pack("<"+"f"*len(a),*a)
def u32(a): return struct.pack("<"+"I"*len(a),*a)
def glb(name,kind,w,d,h,png):
 r=ring(kind,w,d); n=len(r); ps=[(0,h,0)]+[(x,h,z) for x,z in r]; ns=[(0,1,0)]*(n+1); uv=[(.5,.5)]+[(x/w+.5,z/d+.5) for x,z in r]; ix=[]
 # Reverse the X/Z contour order so right-handed winding produces +Y tops.
 for i in range(n): ix += [0,1+(i+1)%n,1+i]
 for i,(x,z) in enumerate(r):
  x2,z2=r[(i+1)%n]; nx,nz=z2-z,-(x2-x); q=math.hypot(nx,nz); nx,nz=nx/q,nz/q; b=len(ps)
  ps += [(x,0,z),(x2,0,z2),(x2,h,z2),(x,h,z)]; ns += [(nx,0,nz)]*4; uv += [(i/n,1),((i+1)/n,1),((i+1)/n,0),(i/n,0)]; ix += [b,b+2,b+1,b,b+3,b+2]
 chunks=[f32([v for p in ps for v in p]),f32([v for p in ns for v in p]),f32([v for p in uv for v in p]),u32(ix),png.read_bytes()]; blob=bytearray(); views=[]
 for c in chunks:
  while len(blob)%4: blob.append(0)
  views.append({"buffer":0,"byteOffset":len(blob),"byteLength":len(c)}); blob.extend(c)
 mn=[min(p[i] for p in ps) for i in range(3)]; mx=[max(p[i] for p in ps) for i in range(3)]
 doc={"asset":{"version":"2.0","generator":"Chicago rug generator"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":name,"mesh":0}],"meshes":[{"name":name,"primitives":[{"attributes":{"POSITION":0,"NORMAL":1,"TEXCOORD_0":2},"indices":3,"material":0}]}],"materials":[{"name":name+"_material","pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicFactor":0,"roughnessFactor":.9}}],"textures":[{"sampler":0,"source":0}],"samplers":[{"magFilter":9729,"minFilter":9729,"wrapS":10497,"wrapT":10497}],"images":[{"mimeType":"image/png","bufferView":4}],"buffers":[{"byteLength":len(blob)}],"bufferViews":views,"accessors":[{"bufferView":0,"componentType":5126,"count":len(ps),"type":"VEC3","min":mn,"max":mx},{"bufferView":1,"componentType":5126,"count":len(ns),"type":"VEC3"},{"bufferView":2,"componentType":5126,"count":len(uv),"type":"VEC2"},{"bufferView":3,"componentType":5125,"count":len(ix),"type":"SCALAR"}]}
 js=json.dumps(doc,separators=(",",":")).encode(); js+=b" "*((4-len(js)%4)%4)
 while len(blob)%4: blob.append(0)
 data=struct.pack("<4sII",b"glTF",2,28+len(js)+len(blob))+struct.pack("<I4s",len(js),b"JSON")+js+struct.pack("<I4s",len(blob),b"BIN\0")+blob; (OUT/(name+".glb")).write_bytes(data)
def main():
 TEX.mkdir(parents=True,exist_ok=True)
 for name,kind,w,d,h,make in ASSETS:
  p=TEX/(name+"_basecolor.png"); make().save(p,optimize=True); glb(name,kind,w,d,h,p); print(name)
if __name__=="__main__": main()
