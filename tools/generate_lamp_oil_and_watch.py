#!/usr/bin/env python3
"""Generate the lamp-oil bottle and Edgar's stopped 8:24 wristwatch."""

import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODEL_DIR = ROOT / "assets" / "models"

MATERIALS = {
    "amber_glass": ([0.34, 0.125, 0.018, 1.0], 0.22, 0.08),
    "oil": ([0.58, 0.31, 0.035, 1.0], 0.38, 0.0),
    "cork": ([0.35, 0.20, 0.095, 1.0], 0.94, 0.0),
    "label": ([0.72, 0.62, 0.42, 1.0], 0.92, 0.0),
    "label_ink": ([0.12, 0.075, 0.035, 1.0], 0.84, 0.0),
    "aged_brass": ([0.52, 0.31, 0.075, 1.0], 0.34, 0.78),
    "watch_face": ([0.80, 0.73, 0.58, 1.0], 0.82, 0.0),
    "watch_ink": ([0.035, 0.032, 0.027, 1.0], 0.58, 0.05),
    "burgundy_leather": ([0.24, 0.025, 0.020, 1.0], 0.76, 0.0),
    "leather_edge": ([0.075, 0.012, 0.010, 1.0], 0.86, 0.0),
}


class Model:
    def __init__(self):
        self.parts = []

    def add(self, material, verts, norms, inds):
        self.parts.append((material, verts, norms, inds))

    def box(self, center, size, material, rotation=0.0):
        cx, cy, cz = center
        sx, sy, sz = (v * 0.5 for v in size)
        c, s = math.cos(rotation), math.sin(rotation)
        def p(x, y, z): return (cx + c*x - s*y, cy + s*x + c*y, cz + z)
        corners = [p(x, y, z) for z in (-sz, sz) for y in (-sy, sy) for x in (-sx, sx)]
        faces = [((0, 2, 3, 1), (0, 0, -1)), ((4, 5, 7, 6), (0, 0, 1)),
                 ((0, 1, 5, 4), (s, -c, 0)), ((2, 6, 7, 3), (-s, c, 0)),
                 ((0, 4, 6, 2), (-c, -s, 0)), ((1, 3, 7, 5), (c, s, 0))]
        verts, norms, inds = [], [], []
        for face, n in faces:
            base = len(verts); verts.extend(corners[i] for i in face); norms.extend([n]*4)
            inds.extend((base, base+1, base+2, base, base+2, base+3))
        self.add(material, verts, norms, inds)

    def frustum(self, z0, z1, r0, r1, material, sides=24, center=(0, 0)):
        cx, cy = center
        verts, norms, inds = [], [], []
        slope = (r0-r1)/(z1-z0)
        for z, radius in ((z0, r0), (z1, r1)):
            for i in range(sides):
                a = math.tau*i/sides
                length = math.sqrt(1+slope*slope)
                verts.append((cx+math.cos(a)*radius, cy+math.sin(a)*radius, z))
                norms.append((math.cos(a)/length, math.sin(a)/length, slope/length))
        for i in range(sides):
            j = (i+1)%sides; inds.extend((i, j, sides+i, j, sides+j, sides+i))
        for z, ring, nz in ((z0, 0, -1), (z1, sides, 1)):
            center_i = len(verts); verts.append((cx, cy, z)); norms.append((0, 0, nz))
            for i in range(sides):
                j = (i+1)%sides
                inds.extend((center_i, ring+j, ring+i) if nz < 0 else (center_i, ring+i, ring+j))
        self.add(material, verts, norms, inds)


def lamp_oil():
    m = Model()
    # Squat apothecary bottle: oil is suggested by a darker inner lower volume.
    m.frustum(0.00, 0.255, 0.105, 0.105, "amber_glass", 20)
    m.frustum(0.012, 0.190, 0.092, 0.092, "oil", 20)
    m.frustum(0.255, 0.315, 0.105, 0.050, "amber_glass", 20)
    m.frustum(0.315, 0.390, 0.050, 0.050, "amber_glass", 20)
    m.frustum(0.386, 0.430, 0.043, 0.047, "cork", 16)
    # Raised label plate and simple bands remain legible without texture support.
    m.box((0, -0.108, 0.158), (0.145, 0.012, 0.125), "label")
    m.box((0, -0.116, 0.178), (0.100, 0.008, 0.012), "label_ink")
    m.box((0, -0.116, 0.145), (0.072, 0.008, 0.009), "label_ink")
    m.box((0, -0.116, 0.120), (0.088, 0.008, 0.009), "label_ink")
    return m


def stopped_watch():
    m = Model()
    # Broken burgundy strap, laid flat as it appears beside the place settings.
    m.box((0, 0.245, 0.030), (0.19, 0.37, 0.040), "burgundy_leather")
    m.box((0, -0.245, 0.030), (0.19, 0.37, 0.040), "burgundy_leather")
    m.box((-0.100, 0.245, 0.034), (0.014, 0.35, 0.048), "leather_edge")
    m.box((0.100, 0.245, 0.034), (0.014, 0.35, 0.048), "leather_edge")
    m.box((-0.100, -0.245, 0.034), (0.014, 0.35, 0.048), "leather_edge")
    m.box((0.100, -0.245, 0.034), (0.014, 0.35, 0.048), "leather_edge")
    m.frustum(0.035, 0.090, 0.235, 0.225, "aged_brass", 32)
    m.frustum(0.091, 0.106, 0.196, 0.196, "watch_face", 32)
    # Crown and lugs.
    m.box((0.255, 0, 0.070), (0.055, 0.070, 0.065), "aged_brass")
    for x in (-0.145, 0.145):
        for y in (-0.212, 0.212): m.box((x, y, 0.055), (0.070, 0.090, 0.055), "aged_brass")
    # Twelve raised hour indices.
    for hour in range(12):
        a = math.pi/2 - math.tau*hour/12
        x, y = math.cos(a)*0.161, math.sin(a)*0.161
        m.box((x, y, 0.116), (0.010, 0.035, 0.012), "watch_ink", -a+math.pi/2)
    # Hands frozen at 8:24. Angles are clockwise from twelve.
    minute_a = math.pi/2 - math.tau*(24/60)
    hour_a = math.pi/2 - math.tau*((8+24/60)/12)
    def hand(angle, length, width, z):
        m.box((math.cos(angle)*length*.46, math.sin(angle)*length*.46, z),
              (length, width, 0.014), "watch_ink", angle)
    hand(hour_a, 0.120, 0.020, 0.123)
    hand(minute_a, 0.170, 0.014, 0.128)
    m.frustum(0.126, 0.145, 0.025, 0.021, "watch_ink", 20)
    return m


def write_glb(path, name, model):
    blob = bytearray(); views, accessors, primitives = [], [], []
    used = list(dict.fromkeys(p[0] for p in model.parts))
    materials = []
    for key in used:
        color, rough, metallic = MATERIALS[key]
        materials.append({"name": key, "pbrMetallicRoughness": {"baseColorFactor": color,
                          "roughnessFactor": rough, "metallicFactor": metallic}})
    def put(data, target):
        offset = len(blob); blob.extend(data)
        while len(blob)%4: blob.append(0)
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data), "target": target})
        return len(views)-1
    for material, verts, norms, inds in model.parts:
        verts = [(x, z, -y) for x, y, z in verts]; norms = [(x, z, -y) for x, y, z in norms]
        pv = put(b"".join(struct.pack("<3f", *p) for p in verts), 34962)
        nv = put(b"".join(struct.pack("<3f", *n) for n in norms), 34962)
        iv = put(b"".join(struct.pack("<H", i) for i in inds), 34963)
        mn = [min(p[i] for p in verts) for i in range(3)]; mx = [max(p[i] for p in verts) for i in range(3)]
        pa = len(accessors); accessors.append({"bufferView": pv, "componentType": 5126, "count": len(verts), "type": "VEC3", "min": mn, "max": mx})
        na = len(accessors); accessors.append({"bufferView": nv, "componentType": 5126, "count": len(norms), "type": "VEC3"})
        ia = len(accessors); accessors.append({"bufferView": iv, "componentType": 5123, "count": len(inds), "type": "SCALAR"})
        primitives.append({"attributes": {"POSITION": pa, "NORMAL": na}, "indices": ia, "material": used.index(material)})
    doc = {"asset": {"version": "2.0", "generator": "Chicago case prop generator"}, "scene": 0,
           "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": name}],
           "meshes": [{"name": name, "primitives": primitives}], "materials": materials,
           "buffers": [{"byteLength": len(blob)}], "bufferViews": views, "accessors": accessors}
    encoded = json.dumps(doc, separators=(",", ":")).encode(); encoded += b" "*((4-len(encoded)%4)%4)
    total = 12+8+len(encoded)+8+len(blob)
    data = struct.pack("<4sII", b"glTF", 2, total)+struct.pack("<I4s", len(encoded), b"JSON")+encoded+struct.pack("<I4s", len(blob), b"BIN\0")+blob
    path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
    print(f"wrote {path.relative_to(ROOT)} ({len(data)} bytes, {len(model.parts)} parts)")


if __name__ == "__main__":
    write_glb(MODEL_DIR/"lamp-oil-bottle.glb", "Lamp_Oil_Bottle", lamp_oil())
    write_glb(MODEL_DIR/"stopped-watch-824.glb", "Stopped_Watch_824", stopped_watch())
