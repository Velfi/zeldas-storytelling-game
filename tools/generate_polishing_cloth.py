#!/usr/bin/env python3
"""Generate Miriam's stained polishing cloth as a self-contained low-poly GLB."""

import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "models" / "polishing-cloth.glb"

MATERIALS = {
    "linen": ([0.72, 0.67, 0.54, 1.0], 0.98, 0.0),
    "linen_edge": ([0.43, 0.39, 0.31, 1.0], 1.0, 0.0),
    "bronze_polish": ([0.28, 0.13, 0.045, 1.0], 0.84, 0.18),
    "diluted_blood": ([0.28, 0.035, 0.028, 1.0], 0.92, 0.0),
    "damp_patch": ([0.40, 0.38, 0.31, 1.0], 0.76, 0.0),
}


def normal(a, b, c):
    u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
    v = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
    n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
    length = math.sqrt(sum(x * x for x in n)) or 1.0
    return tuple(x / length for x in n)


class Model:
    def __init__(self):
        self.parts = []

    def triangles(self, material, vertices, indices):
        # Split vertices per triangle for stable flat normals in the game's loader.
        out_v, out_n, out_i = [], [], []
        for i in range(0, len(indices), 3):
            tri = [vertices[indices[i + j]] for j in range(3)]
            n = normal(*tri)
            base = len(out_v)
            out_v.extend(tri)
            out_n.extend([n, n, n])
            out_i.extend((base, base + 1, base + 2))
        self.parts.append((material, out_v, out_n, out_i))

    def patch(self, center, radii, material, angle=0.0, height=0.004, segments=18):
        cx, cy = center
        c, s = math.cos(angle), math.sin(angle)
        verts = [(cx, cy, height)]
        for i in range(segments):
            a = math.tau * i / segments
            x, y = math.cos(a) * radii[0], math.sin(a) * radii[1]
            # Deliberately uneven perimeter reads as soaked cloth rather than a decal disc.
            wobble = 1.0 + 0.10 * math.sin(i * 2.7 + radii[0] * 31)
            verts.append((cx + (c * x - s * y) * wobble, cy + (s * x + c * y) * wobble, height))
        inds = []
        for i in range(segments):
            inds.extend((0, 1 + i, 1 + (i + 1) % segments))
        self.triangles(material, verts, inds)


def cloth_height(x, y):
    # Several broad folds plus small damp wrinkles; edges remain close to the table.
    fold = 0.045 * math.exp(-((x + 0.08) ** 2 / 0.035 + (y - 0.02) ** 2 / 0.18))
    ridge = 0.028 * math.exp(-((x - 0.18) ** 2 / 0.022 + (y + 0.10) ** 2 / 0.10))
    wrinkle = 0.008 * math.sin(x * 21 + y * 7) * math.cos(y * 16 - x * 4)
    return 0.018 + fold + ridge + wrinkle


def build_cloth():
    m = Model()
    cols, rows = 10, 9
    width, depth = 0.72, 0.58
    verts = []
    for row in range(rows):
        v = row / (rows - 1)
        y = (v - 0.5) * depth
        for col in range(cols):
            u = col / (cols - 1)
            x = (u - 0.5) * width
            # Frayed, asymmetric outline.
            if col in (0, cols - 1):
                x += 0.014 * math.sin(row * 2.3 + col)
            if row in (0, rows - 1):
                y += 0.012 * math.sin(col * 2.1 + row)
            verts.append((x, y, cloth_height(x, y)))
    inds = []
    for row in range(rows - 1):
        for col in range(cols - 1):
            a = row * cols + col
            b, c, d = a + 1, a + cols, a + cols + 1
            if (row + col) % 2:
                inds.extend((a, b, c, b, d, c))
            else:
                inds.extend((a, b, d, a, d, c))
    m.triangles("linen", verts, inds)

    # Dark side strips give the cloth a little thickness under grazing light.
    edge_verts, edge_inds = [], []
    perimeter = ([row * cols for row in range(rows)]
                 + [(rows - 1) * cols + col for col in range(1, cols)]
                 + [row * cols + cols - 1 for row in range(rows - 2, -1, -1)]
                 + [col for col in range(cols - 2, 0, -1)])
    for i, index in enumerate(perimeter):
        nxt = perimeter[(i + 1) % len(perimeter)]
        a, b = verts[index], verts[nxt]
        base = len(edge_verts)
        edge_verts.extend((a, b, (b[0], b[1], max(0.002, b[2] - 0.012)), (a[0], a[1], max(0.002, a[2] - 0.012))))
        edge_inds.extend((base, base + 1, base + 2, base, base + 2, base + 3))
    m.triangles("linen_edge", edge_verts, edge_inds)

    # Layered stains: a broad damp area, embedded bronze polish, and a smaller
    # rusty-red dilution where the weapon was wiped.
    m.patch((-0.04, -0.015), (0.25, 0.18), "damp_patch", -0.18, cloth_height(-0.04, -0.015) + 0.004, 22)
    m.patch((-0.16, 0.055), (0.15, 0.085), "bronze_polish", 0.38, cloth_height(-0.16, 0.055) + 0.009, 18)
    m.patch((0.13, -0.07), (0.12, 0.060), "diluted_blood", -0.48, cloth_height(0.13, -0.07) + 0.009, 18)
    m.patch((0.235, -0.14), (0.045, 0.025), "diluted_blood", 0.20, cloth_height(0.235, -0.14) + 0.009, 14)
    return m


def write_glb(model):
    blob = bytearray()
    views, accessors, primitives = [], [], []
    used = list(dict.fromkeys(part[0] for part in model.parts))
    materials = []
    for key in used:
        color, roughness, metallic = MATERIALS[key]
        materials.append({"name": key, "pbrMetallicRoughness": {
            "baseColorFactor": color, "roughnessFactor": roughness, "metallicFactor": metallic}})

    def put(data, target):
        offset = len(blob)
        blob.extend(data)
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data), "target": target})
        return len(views) - 1

    for material, verts, norms, inds in model.parts:
        # Z-up authoring coordinates to Y-up glTF/runtime coordinates.
        verts = [(x, z, -y) for x, y, z in verts]
        norms = [(x, z, -y) for x, y, z in norms]
        pv = put(b"".join(struct.pack("<3f", *p) for p in verts), 34962)
        nv = put(b"".join(struct.pack("<3f", *n) for n in norms), 34962)
        iv = put(b"".join(struct.pack("<H", i) for i in inds), 34963)
        mn = [min(p[i] for p in verts) for i in range(3)]
        mx = [max(p[i] for p in verts) for i in range(3)]
        pa = len(accessors)
        accessors.append({"bufferView": pv, "componentType": 5126, "count": len(verts), "type": "VEC3", "min": mn, "max": mx})
        na = len(accessors)
        accessors.append({"bufferView": nv, "componentType": 5126, "count": len(norms), "type": "VEC3"})
        ia = len(accessors)
        accessors.append({"bufferView": iv, "componentType": 5123, "count": len(inds), "type": "SCALAR"})
        primitives.append({"attributes": {"POSITION": pa, "NORMAL": na}, "indices": ia, "material": used.index(material)})

    doc = {"asset": {"version": "2.0", "generator": "Chicago polishing cloth generator"},
           "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": "Polishing_Cloth"}],
           "meshes": [{"name": "Polishing_Cloth", "primitives": primitives}], "materials": materials,
           "buffers": [{"byteLength": len(blob)}], "bufferViews": views, "accessors": accessors}
    encoded = json.dumps(doc, separators=(",", ":")).encode()
    encoded += b" " * ((4 - len(encoded) % 4) % 4)
    total = 12 + 8 + len(encoded) + 8 + len(blob)
    data = (struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(encoded), b"JSON") + encoded
            + struct.pack("<I4s", len(blob), b"BIN\0") + blob)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(data)
    print(f"wrote {OUT.relative_to(ROOT)} ({len(data)} bytes, {len(model.parts)} parts)")


if __name__ == "__main__":
    write_glb(build_cloth())
