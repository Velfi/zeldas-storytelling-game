#!/usr/bin/env python3
"""Generate Edgar Vale's open private ledger as a self-contained low-poly GLB."""

import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "models" / "private-ledger.glb"

MATERIALS = {
    "leather": ([0.035, 0.145, 0.095, 1.0], 0.72, 0.0),
    "leather_dark": ([0.018, 0.065, 0.042, 1.0], 0.78, 0.0),
    "paper": ([0.78, 0.69, 0.50, 1.0], 0.92, 0.0),
    "paper_edge": ([0.48, 0.39, 0.25, 1.0], 0.96, 0.0),
    "ink": ([0.055, 0.045, 0.035, 1.0], 0.86, 0.0),
    "red_pencil": ([0.48, 0.028, 0.022, 1.0], 0.58, 0.0),
    "graphite": ([0.035, 0.032, 0.030, 1.0], 0.52, 0.15),
    "gold": ([0.66, 0.40, 0.075, 1.0], 0.34, 0.68),
}


class Model:
    def __init__(self):
        self.parts = []

    def box(self, center, size, material, rotation=0.0):
        """Add a box in Z-up authoring coordinates; rotation is around Z."""
        cx, cy, cz = center
        sx, sy, sz = (v * 0.5 for v in size)
        c, s = math.cos(rotation), math.sin(rotation)

        def point(x, y, z):
            return (cx + c * x - s * y, cy + s * x + c * y, cz + z)

        corners = [point(x, y, z) for z in (-sz, sz) for y in (-sy, sy) for x in (-sx, sx)]
        faces = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4),
                 (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
        verts, norms, inds = [], [], []
        for face in faces:
            a, b, d = (corners[face[i]] for i in (0, 1, 3))
            u = tuple(b[i] - a[i] for i in range(3))
            v = tuple(d[i] - a[i] for i in range(3))
            n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
            length = math.sqrt(sum(q * q for q in n))
            n = tuple(q / length for q in n)
            base = len(verts)
            verts.extend(corners[i] for i in face)
            norms.extend([n] * 4)
            inds.extend((base, base + 1, base + 2, base, base + 2, base + 3))
        self.parts.append((material, verts, norms, inds))


def build_ledger():
    m = Model()
    # Open boards and thick, uneven page blocks. The shallow opposing yaw makes
    # the central gutter readable from the game's aerial camera.
    m.box((-0.265, 0, 0.018), (0.54, 0.72, 0.036), "leather", -0.025)
    m.box((0.265, 0, 0.018), (0.54, 0.72, 0.036), "leather", 0.025)
    m.box((0, 0, 0.035), (0.055, 0.735, 0.070), "leather_dark")
    m.box((-0.255, 0.005, 0.075), (0.485, 0.665, 0.078), "paper_edge", -0.025)
    m.box((0.255, 0.005, 0.075), (0.485, 0.665, 0.078), "paper_edge", 0.025)
    m.box((-0.247, -0.002, 0.119), (0.468, 0.646, 0.012), "paper", -0.025)
    m.box((0.247, -0.002, 0.119), (0.468, 0.646, 0.012), "paper", 0.025)

    # Printed account rows, column rules, and several incriminating red marks.
    for side in (-1, 1):
        cx = side * 0.247
        angle = side * 0.025
        for row in range(8):
            y = -0.245 + row * 0.064
            m.box((cx, y, 0.128), (0.365, 0.007, 0.006), "ink", angle)
        for column in (-0.105, 0.105):
            m.box((cx + column, 0.006, 0.128), (0.006, 0.515, 0.006), "ink", angle)
    for x, y, width in ((0.255, -0.117, 0.29), (0.255, 0.075, 0.22), (-0.255, 0.203, 0.30)):
        m.box((x, y, 0.134), (width, 0.014, 0.007), "red_pencil", 0.025 if x > 0 else -0.025)

    # Gold corner tooling keeps the object identifiable when viewed at world scale.
    for x in (-0.49, 0.49):
        for y in (-0.335, 0.335):
            m.box((x, y, 0.040), (0.055, 0.055, 0.012), "gold")

    # Edgar's red pencil rests diagonally across the marked receiving column.
    pencil_angle = -0.30
    m.box((0.13, 0.035, 0.166), (0.69, 0.026, 0.026), "red_pencil", pencil_angle)
    c, s = math.cos(pencil_angle), math.sin(pencil_angle)
    m.box((0.13 + c * 0.354, 0.035 + s * 0.354, 0.166), (0.045, 0.030, 0.030), "graphite", pencil_angle)
    m.box((0.13 - c * 0.354, 0.035 - s * 0.354, 0.166), (0.040, 0.030, 0.030), "gold", pencil_angle)
    return m


def write_glb(model):
    blob = bytearray()
    views, accessors, primitives = [], [], []
    used = list(dict.fromkeys(part[0] for part in model.parts))
    materials = []
    for key in used:
        color, roughness, metallic = MATERIALS[key]
        materials.append({"name": key, "pbrMetallicRoughness": {
            "baseColorFactor": color, "metallicFactor": metallic, "roughnessFactor": roughness}})

    def put(data, target):
        offset = len(blob)
        blob.extend(data)
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data), "target": target})
        return len(views) - 1

    for material, verts, norms, inds in model.parts:
        # Convert Z-up authoring coordinates to the runtime's Y-up convention.
        verts = [(x, z, -y) for x, y, z in verts]
        norms = [(x, z, -y) for x, y, z in norms]
        pv = put(b"".join(struct.pack("<3f", *p) for p in verts), 34962)
        nv = put(b"".join(struct.pack("<3f", *n) for n in norms), 34962)
        iv = put(b"".join(struct.pack("<H", i) for i in inds), 34963)
        minimum = [min(p[i] for p in verts) for i in range(3)]
        maximum = [max(p[i] for p in verts) for i in range(3)]
        pa = len(accessors)
        accessors.append({"bufferView": pv, "componentType": 5126, "count": len(verts), "type": "VEC3", "min": minimum, "max": maximum})
        na = len(accessors)
        accessors.append({"bufferView": nv, "componentType": 5126, "count": len(norms), "type": "VEC3"})
        ia = len(accessors)
        accessors.append({"bufferView": iv, "componentType": 5123, "count": len(inds), "type": "SCALAR"})
        primitives.append({"attributes": {"POSITION": pa, "NORMAL": na}, "indices": ia, "material": used.index(material)})

    doc = {"asset": {"version": "2.0", "generator": "Chicago private ledger generator"},
           "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": "Private_Ledger"}],
           "meshes": [{"name": "Private_Ledger", "primitives": primitives}], "materials": materials,
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
    write_glb(build_ledger())
