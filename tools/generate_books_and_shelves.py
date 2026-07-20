#!/usr/bin/env python3
"""Generate a small, dependency-free set of low-poly book and bookshelf GLBs."""

import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/library"

MATERIALS = {
    "walnut": ([0.22, 0.095, 0.035, 1], 0.72),
    "wood_edge": ([0.10, 0.035, 0.015, 1], 0.78),
    "paper": ([0.78, 0.70, 0.53, 1], 0.9),
    "red": ([0.43, 0.045, 0.035, 1], 0.72),
    "green": ([0.07, 0.25, 0.15, 1], 0.75),
    "blue": ([0.045, 0.12, 0.31, 1], 0.7),
    "ochre": ([0.55, 0.28, 0.045, 1], 0.76),
    "black": ([0.035, 0.028, 0.025, 1], 0.82),
    "gold": ([0.72, 0.48, 0.12, 1], 0.38),
}


class Model:
    def __init__(self):
        self.parts = []

    def box(self, center, size, material, rotation=0.0):
        cx, cy, cz = center
        sx, sy, sz = (v * 0.5 for v in size)
        c, s = math.cos(rotation), math.sin(rotation)

        def point(x, y, z):
            return (cx + c*x - s*y, cy + s*x + c*y, cz + z)

        corners = [point(x, y, z) for z in (-sz, sz) for y in (-sy, sy) for x in (-sx, sx)]
        faces = [
            (0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4),
            (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5),
        ]
        verts, norms, inds = [], [], []
        for face in faces:
            a, b, d = (corners[face[i]] for i in (0, 1, 3))
            u = tuple(b[i] - a[i] for i in range(3)); v = tuple(d[i] - a[i] for i in range(3))
            n = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
            length = math.sqrt(sum(q*q for q in n)); n = tuple(q/length for q in n)
            base = len(verts); verts.extend(corners[i] for i in face); norms.extend([n] * 4)
            inds.extend((base, base+1, base+2, base, base+2, base+3))
        self.parts.append((material, verts, norms, inds))

    def book(self, center, width, depth, height, cover, rotation=0.0, bands=True):
        x, y, z = center
        # Proper layered construction: an inset page block, thin cover boards,
        # and an opaque spine. Components meet without coplanar overlap, so the
        # pages cannot bleed through the cover in the production renderer.
        page_depth = depth-.040
        page_height = height-.026
        board_width = .014
        self.box((x, y+.010, z), (width-board_width*2, page_depth, page_height), "paper", rotation)
        # Upright books have their cover boards on the left and right faces.
        # (Top/bottom boards made the fore-edge look as if the cover were inside-out.)
        c, s = math.cos(rotation), math.sin(rotation)
        for dx in (-width/2+board_width/2, width/2-board_width/2):
            ox, oy = (dx, 0)
            self.box((x+c*ox-s*oy, y+s*ox+c*oy, z), (board_width, depth, height), cover, rotation)
        spine_depth = .026
        ox, oy = (0, -depth/2+spine_depth/2)
        self.box((x+c*ox-s*oy, y+s*ox+c*oy, z), (width, spine_depth, height), cover, rotation)
        if bands:
            for dz in (-height*.28, height*.28):
                ox, oy = (0, -depth/2-.002)
                self.box((x+c*ox-s*oy, y+s*ox+c*oy, z+dz), (width+.006, .012, .018), "gold", rotation)


def write_glb(name, model):
    blob = bytearray(); views = []; accessors = []; primitives = []
    used = list(dict.fromkeys(part[0] for part in model.parts))
    materials = []
    for key in used:
        color, rough = MATERIALS[key]
        materials.append({"name": key, "pbrMetallicRoughness": {"baseColorFactor": color,
            "metallicFactor": .65 if key == "gold" else 0, "roughnessFactor": rough}})

    def put(data, target):
        offset = len(blob); blob.extend(data)
        while len(blob) % 4: blob.append(0)
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data), "target": target})
        return len(views)-1

    for material, verts, norms, inds in model.parts:
        # The modeling helpers use conventional Z-up coordinates; glTF and this
        # project's loader expect Y-up. The sign keeps the transform right-handed.
        verts = [(x, z, -y) for x, y, z in verts]
        norms = [(x, z, -y) for x, y, z in norms]
        pv = put(b"".join(struct.pack("<3f", *p) for p in verts), 34962)
        nv = put(b"".join(struct.pack("<3f", *n) for n in norms), 34962)
        iv = put(b"".join(struct.pack("<H", i) for i in inds), 34963)
        mn = [min(p[i] for p in verts) for i in range(3)]; mx = [max(p[i] for p in verts) for i in range(3)]
        pa = len(accessors); accessors.append({"bufferView": pv, "componentType": 5126, "count": len(verts), "type": "VEC3", "min": mn, "max": mx})
        na = len(accessors); accessors.append({"bufferView": nv, "componentType": 5126, "count": len(norms), "type": "VEC3"})
        ia = len(accessors); accessors.append({"bufferView": iv, "componentType": 5123, "count": len(inds), "type": "SCALAR"})
        primitives.append({"attributes": {"POSITION": pa, "NORMAL": na}, "indices": ia, "material": used.index(material)})

    doc = {"asset": {"version": "2.0", "generator": "Chicago library asset generator"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": name}],
        "meshes": [{"name": name, "primitives": primitives}], "materials": materials,
        "buffers": [{"byteLength": len(blob)}], "bufferViews": views, "accessors": accessors}
    encoded = json.dumps(doc, separators=(",", ":")).encode(); encoded += b" " * ((4-len(encoded)%4)%4)
    total = 12+8+len(encoded)+8+len(blob)
    data = struct.pack("<4sII", b"glTF", 2, total)+struct.pack("<I4s", len(encoded), b"JSON")+encoded+struct.pack("<I4s", len(blob), b"BIN\0")+blob
    OUT.mkdir(parents=True, exist_ok=True); path = OUT / f"{name}.glb"; path.write_bytes(data)
    print(f"{path.relative_to(ROOT)}: {len(model.parts)} parts, {len(data)} bytes")


def shelf(full=False, wide=False):
    m = Model(); w = 2.15 if wide else 1.25; h = 2.2; d = .38; t = .09
    m.box((0, d*.16, h/2), (w, .055, h), "wood_edge") # back panel
    m.box((-w/2+t/2, 0, h/2), (t, d, h), "walnut"); m.box((w/2-t/2, 0, h/2), (t, d, h), "walnut")
    levels = [t/2, .56, 1.08, 1.60, h-t/2]
    for z in levels: m.box((0, 0, z), (w, d, t), "walnut")
    m.box((0, -.02, .045), (w+.14, d+.08, .09), "wood_edge")
    m.box((0, -.02, h-.045), (w+.12, d+.06, .09), "wood_edge")
    if full:
        colors = ["red", "green", "blue", "ochre", "black"]
        for row in range(4):
            x = -w/2+t+.08; base = levels[row]+t/2
            i = 0
            while x < w/2-t-.08:
                bw = [.105, .13, .085, .115][(i+row)%4]; bh = [.34, .39, .31, .37, .42][(i+2*row)%5]
                if x+bw > w/2-t: break
                angle = .045 * ((i % 3)-1)
                m.book((x+bw/2, -d*.22, base+bh/2), bw, .24, bh, colors[(i+row)%len(colors)], angle, i%2==0)
                x += bw+.018; i += 1
    return m


def main():
    single = Model(); single.book((0, 0, .17), .24, .38, .34, "green"); write_glb("book_single", single)
    stack = Model()
    stack.book((0, 0, .055), .32, .43, .11, "red", .04)
    stack.book((.015, 0, .145), .29, .40, .075, "blue", -.055)
    stack.book((-.01, 0, .235), .34, .42, .105, "ochre", .025)
    write_glb("books_stack", stack)
    row = Model(); x = -.42
    for i, (w, h, color) in enumerate(zip([.11,.13,.09,.12,.10,.14], [.38,.44,.34,.41,.36,.46], ["red","green","blue","ochre","black","red"])):
        row.book((x+w/2, 0, h/2), w, .30, h, color, .025*((i%3)-1), i%2==0); x += w+.015
    write_glb("books_row", row)
    write_glb("bookshelf_empty", shelf(False)); write_glb("bookshelf_full", shelf(True)); write_glb("bookshelf_wide_full", shelf(True, True))


if __name__ == "__main__":
    main()
