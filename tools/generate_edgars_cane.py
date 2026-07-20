#!/usr/bin/env python3
"""Generate Edgar Vale's game-ready walking cane as a self-contained GLB."""

import json
import math
import struct
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "models" / "edgars-cane.glb"


def tube_along_path(points, radius, sides=16):
    points = np.asarray(points, dtype=np.float32)
    verts, normals = [], []
    for i, p in enumerate(points):
        tangent = points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]
        tangent /= np.linalg.norm(tangent)
        # The cane path lies in XY, so Z is a stable first frame axis.
        axis_a = np.array([0.0, 0.0, 1.0], dtype=np.float32)
        axis_b = np.cross(tangent, axis_a)
        axis_b /= np.linalg.norm(axis_b)
        for j in range(sides):
            a = 2 * math.pi * j / sides
            n = math.cos(a) * axis_a + math.sin(a) * axis_b
            verts.append(p + radius * n)
            normals.append(n)
    indices = []
    for i in range(len(points) - 1):
        for j in range(sides):
            a, b = i * sides + j, i * sides + (j + 1) % sides
            c, d = (i + 1) * sides + j, (i + 1) * sides + (j + 1) % sides
            # Counter-clockwise from outside; the renderer culls back faces.
            indices.extend((a, b, c, b, d, c))
    return np.asarray(verts, np.float32), np.asarray(normals, np.float32), np.asarray(indices, np.uint32)


def cylinder(y0, y1, radius, sides=20):
    pts = [(0.0, y0, 0.0), (0.0, y1, 0.0)]
    v, n, idx = tube_along_path(pts, radius, sides)
    # Add simple end caps.
    verts, normals, indices = v.tolist(), n.tolist(), idx.tolist()
    for y, ny, ring in ((y0, -1.0, 0), (y1, 1.0, sides)):
        center = len(verts)
        verts.append([0.0, y, 0.0]); normals.append([0.0, ny, 0.0])
        for j in range(sides):
            a, b = ring + j, ring + (j + 1) % sides
            indices.extend((center, b, a) if ny < 0 else (center, a, b))
    return np.asarray(verts, np.float32), np.asarray(normals, np.float32), np.asarray(indices, np.uint32)


def ring(y0, y1, outer, sides=20):
    return cylinder(y0, y1, outer, sides)


def combine(parts):
    vs, ns, ids, offset = [], [], [], 0
    for v, n, idx in parts:
        vs.append(v); ns.append(n); ids.append(idx + offset); offset += len(v)
    return np.concatenate(vs), np.concatenate(ns), np.concatenate(ids)


wood = combine([cylinder(0.065, 0.79, 0.018, 20)])

# A substantial brass crook, sized for a stern 1930s shipping magnate.
angles = np.linspace(math.pi, 0.0, 29)
crook_path = [(0.105 + 0.105 * math.cos(a), 0.79 + 0.105 * math.sin(a), 0.0) for a in angles]
brass = combine([
    tube_along_path(crook_path, 0.025, 20),
    ring(0.755, 0.805, 0.0265, 20),
    ring(0.018, 0.075, 0.0235, 20),
])


def aligned(blob, alignment=4):
    return blob + b"\0" * ((-len(blob)) % alignment)


buffer = bytearray()
views, accessors, primitives = [], [], []


def add_array(arr, target, component_type, accessor_type, include_bounds=False):
    raw = aligned(arr.tobytes())
    offset = len(buffer); buffer.extend(raw)
    view = len(views)
    views.append({"buffer": 0, "byteOffset": offset, "byteLength": arr.nbytes, "target": target})
    acc = {"bufferView": view, "componentType": component_type, "count": len(arr), "type": accessor_type}
    if include_bounds:
        acc["min"] = arr.min(axis=0).astype(float).tolist()
        acc["max"] = arr.max(axis=0).astype(float).tolist()
    accessors.append(acc)
    return len(accessors) - 1


for material, (verts, norms, indices) in enumerate((wood, brass)):
    pos = add_array(verts, 34962, 5126, "VEC3", True)
    nor = add_array(norms, 34962, 5126, "VEC3")
    ind = add_array(indices, 34963, 5125, "SCALAR")
    primitives.append({"attributes": {"POSITION": pos, "NORMAL": nor}, "indices": ind, "material": material})

doc = {
    "asset": {"version": "2.0", "generator": "Codex procedural cane generator"},
    "scene": 0,
    "scenes": [{"nodes": [0]}],
    "nodes": [{"name": "Edgars_Cane", "mesh": 0}],
    "meshes": [{"name": "Edgars_Cane", "primitives": primitives}],
    "materials": [
        {"name": "Dark_Walnut", "pbrMetallicRoughness": {"baseColorFactor": [0.105, 0.035, 0.012, 1.0], "metallicFactor": 0.0, "roughnessFactor": 0.38}},
        {"name": "Aged_Brass", "pbrMetallicRoughness": {"baseColorFactor": [0.50, 0.27, 0.055, 1.0], "metallicFactor": 0.88, "roughnessFactor": 0.27}},
    ],
    "buffers": [{"byteLength": len(buffer)}],
    "bufferViews": views,
    "accessors": accessors,
}

json_blob = aligned(json.dumps(doc, separators=(",", ":")).encode("utf-8"), 4).replace(b"\0", b" ")
bin_blob = aligned(bytes(buffer), 4)
total = 12 + 8 + len(json_blob) + 8 + len(bin_blob)
glb = struct.pack("<4sII", b"glTF", 2, total)
glb += struct.pack("<I4s", len(json_blob), b"JSON") + json_blob
glb += struct.pack("<I4s", len(bin_blob), b"BIN\0") + bin_blob
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(glb)
print(f"wrote {OUT} ({len(glb)} bytes, {sum(len(x[0]) for x in (wood, brass))} vertices)")
