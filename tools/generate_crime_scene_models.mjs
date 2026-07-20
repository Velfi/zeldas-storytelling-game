import fs from "node:fs";

const outDir = new URL("../assets/models/crime-scene/", import.meta.url);
fs.mkdirSync(outDir, { recursive: true });

function meshBuilder() {
  const positions = [], indices = [];
  const addTri = (a, b, c) => indices.push(a, b, c);
  function box(center, size, material, rotation = 0) {
    const first = positions.length / 3, [cx, cy, cz] = center, [sx, sy, sz] = size;
    const c = Math.cos(rotation), s = Math.sin(rotation), verts = [];
    for (const [x, y, z] of [[-1,-1,-1],[1,-1,-1],[1,1,-1],[-1,1,-1],[-1,-1,1],[1,-1,1],[1,1,1],[-1,1,1]]) {
      const px=x*sx/2, pz=z*sz/2; verts.push([cx+px*c-pz*s,cy+y*sy/2,cz+px*s+pz*c]);
    }
    for (const v of verts) positions.push(...v);
    const faces=[[0,2,1,0,3,2],[4,5,6,4,6,7],[0,1,5,0,5,4],[3,7,6,3,6,2],[1,2,6,1,6,5],[0,4,7,0,7,3]];
    const start=indices.length; for(const f of faces) for(let i=0;i<f.length;i+=3)addTri(first+f[i],first+f[i+1],first+f[i+2]);
    return { start, count: indices.length-start, material };
  }
  function ellipsoid(center, radius, material, rings=6, segments=10) {
    const first=positions.length/3, [cx,cy,cz]=center, [rx,ry,rz]=radius;
    for(let r=0;r<=rings;r++){const v=r/rings,phi=Math.PI*v;for(let q=0;q<segments;q++){const t=Math.PI*2*q/segments;positions.push(cx+rx*Math.sin(phi)*Math.cos(t),cy+ry*Math.cos(phi),cz+rz*Math.sin(phi)*Math.sin(t));}}
    const start=indices.length;for(let r=0;r<rings;r++)for(let q=0;q<segments;q++){const n=(q+1)%segments,a=first+r*segments+q,b=first+r*segments+n,c=first+(r+1)*segments+q,d=first+(r+1)*segments+n;addTri(a,c,b);addTri(b,c,d)}
    return {start,count:indices.length-start,material};
  }
  function limb(a,b,radius,material,sides=8){
    const first=positions.length/3, dx=b[0]-a[0],dy=b[1]-a[1],dz=b[2]-a[2],len=Math.hypot(dx,dy,dz), ux=dx/len,uy=dy/len,uz=dz/len;
    let px=-uz,py=0,pz=ux,pl=Math.hypot(px,py,pz);if(pl<.01){px=1;py=0;pz=0;pl=1} px/=pl;py/=pl;pz/=pl;
    const qx=uy*pz-uz*py,qy=uz*px-ux*pz,qz=ux*py-uy*px;
    for(const end of [a,b])for(let i=0;i<sides;i++){const t=Math.PI*2*i/sides,co=Math.cos(t)*radius,si=Math.sin(t)*radius;positions.push(end[0]+px*co+qx*si,end[1]+py*co+qy*si,end[2]+pz*co+qz*si)}
    const start=indices.length;for(let i=0;i<sides;i++){const n=(i+1)%sides;addTri(first+i,first+sides+i,first+n);addTri(first+n,first+sides+i,first+sides+n)}
    return {start,count:indices.length-start,material};
  }
  return {positions,indices,box,ellipsoid,limb};
}

function writeGlb(name, builder, primitives, materials) {
  const pos=Buffer.from(new Float32Array(builder.positions).buffer), idx=Buffer.from(new Uint32Array(builder.indices).buffer);
  const bin=Buffer.concat([pos,Buffer.alloc((4-pos.length%4)%4),idx]); const idxOffset=(pos.length+3)&~3;
  const mins=[Infinity,Infinity,Infinity],maxs=[-Infinity,-Infinity,-Infinity];for(let i=0;i<builder.positions.length;i+=3)for(let k=0;k<3;k++){mins[k]=Math.min(mins[k],builder.positions[i+k]);maxs[k]=Math.max(maxs[k],builder.positions[i+k]);}
  const accessors=[{bufferView:0,componentType:5126,count:builder.positions.length/3,type:"VEC3",min:mins,max:maxs}];
  const views=[{buffer:0,byteOffset:0,byteLength:pos.length,target:34962},{buffer:0,byteOffset:idxOffset,byteLength:idx.length,target:34963}];
  const gltf={asset:{version:"2.0",generator:"Chicago crime-scene model generator"},scene:0,scenes:[{nodes:[0]}],nodes:[{mesh:0}],meshes:[{primitives:[]}],buffers:[{byteLength:bin.length}],bufferViews:views,accessors,materials:materials.map(([name,color])=>({name,pbrMetallicRoughness:{baseColorFactor:color,metallicFactor:0,roughnessFactor:.88}}))};
  for(const p of primitives){const ai=accessors.length;accessors.push({bufferView:1,byteOffset:p.start*4,componentType:5125,count:p.count,type:"SCALAR"});gltf.meshes[0].primitives.push({attributes:{POSITION:0},indices:ai,material:p.material,mode:4});}
  let json=Buffer.from(JSON.stringify(gltf));json=Buffer.concat([json,Buffer.alloc((4-json.length%4)%4,0x20)]);const header=Buffer.alloc(12);header.writeUInt32LE(0x46546c67,0);header.writeUInt32LE(2,4);header.writeUInt32LE(12+8+json.length+8+bin.length,8);const jh=Buffer.alloc(8);jh.writeUInt32LE(json.length,0);jh.writeUInt32LE(0x4e4f534a,4);const bh=Buffer.alloc(8);bh.writeUInt32LE(bin.length,0);bh.writeUInt32LE(0x004e4942,4);fs.writeFileSync(new URL(name,outDir),Buffer.concat([header,jh,json,bh,bin]));
}

const body=meshBuilder(), bp=[];
bp.push(body.box([0,.29,0],[.62,.34,1.00],0,-.10));
bp.push(body.box([0,.24,.70],[.55,.30,.50],1,.05));
bp.push(body.ellipsoid([-.05,.30,-.72],[.25,.27,.27],2));
bp.push(body.ellipsoid([-.12,.35,-.92],[.08,.06,.09],3,4,8));
bp.push(body.limb([-.25,.27,.26],[-.52,.18,.78],.12,0));bp.push(body.limb([.24,.27,.25],[.58,.13,.53],.12,0));
bp.push(body.ellipsoid([-.56,.17,.86],[.14,.08,.12],2,4,8));bp.push(body.ellipsoid([.63,.12,.58],[.14,.08,.12],2,4,8));
bp.push(body.limb([-.18,.22,.84],[-.25,.17,1.55],.15,1));bp.push(body.limb([.18,.22,.84],[.38,.13,1.48],.15,1));
bp.push(body.box([-.27,.13,1.68],[.28,.18,.38],4,-.06));bp.push(body.box([.42,.10,1.61],[.28,.18,.38],4,.12));
writeGlb("edgar-body.glb",body,bp,[["charcoal suit",[.075,.085,.09,1]],["trousers",[.055,.06,.065,1]],["skin",[.66,.48,.38,1]],["hair",[.10,.065,.045,1]],["shoes",[.035,.025,.02,1]]]);

const stain=meshBuilder();const points=[[-.82,-.05],[-.62,-.42],[-.18,-.54],[.22,-.45],[.62,-.24],[.78,.06],[.48,.37],[.08,.47],[-.34,.39],[-.70,.22]];stain.positions.push(0,.012,0);for(const [x,z] of points)stain.positions.push(x,.012,z);for(let i=0;i<points.length;i++){const n=(i+1)%points.length;stain.indices.push(0,i+1,n+1)};writeGlb("bloodstain.glb",stain,[{start:0,count:stain.indices.length,material:0}],[["dried blood",[.72,.025,.03,1]]]);
