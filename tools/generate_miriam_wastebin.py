#!/usr/bin/env python3
"""Generate Miriam Vale's metal wastebin and burned-note evidence as a GLB."""

import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "models" / "miriam-metal-wastebin.glb"
PARTS = []

MATERIALS = {
    "galvanized_steel": ([0.34, 0.38, 0.39, 1.0], 0.38, 0.82),
    "dark_steel": ([0.095, 0.115, 0.12, 1.0], 0.48, 0.76),
    "cold_ash": ([0.055, 0.052, 0.048, 1.0], 0.98, 0.0),
    "scorched_paper": ([0.43, 0.30, 0.16, 1.0], 0.93, 0.0),
    "char": ([0.025, 0.018, 0.012, 1.0], 1.0, 0.0),
}


def ring_part(name, radii, heights, segments=20, inward=False):
    """Create connected rings, with radii/heights ordered from bottom to top."""
    verts, norms, inds = [], [], []
    for ring, (radius, height) in enumerate(zip(radii, heights)):
        slope = 0.0
        if ring + 1 < len(radii):
            slope = (radii[ring + 1] - radius) / max(heights[ring + 1] - height, 0.001)
        elif ring:
            slope = (radius - radii[ring - 1]) / max(height - heights[ring - 1], 0.001)
        for i in range(segments):
            angle = 2.0 * math.pi * i / segments
            sign = -1.0 if inward else 1.0
            nx, nz = sign * math.cos(angle), sign * math.sin(angle)
            length = math.sqrt(1.0 + slope * slope)
            verts.append((radius * math.cos(angle), height, radius * math.sin(angle)))
            norms.append((nx / length, -sign * slope / length, nz / length))
    for ring in range(len(radii) - 1):
        for i in range(segments):
            j = (i + 1) % segments
            a, b = ring * segments + i, ring * segments + j
            c, d = a + segments, b + segments
            inds.extend((a, c, b, b, c, d) if inward else (a, b, c, b, d, c))
    PARTS.append((name, verts, norms, inds))


def disc(name, radius, height, segments=20, up=True):
    verts = [(0.0, height, 0.0)]
    norms = [(0.0, 1.0 if up else -1.0, 0.0)]
    for i in range(segments):
        angle = 2.0 * math.pi * i / segments
        verts.append((radius * math.cos(angle), height, radius * math.sin(angle)))
        norms.append(norms[0])
    inds = []
    for i in range(segments):
        j = (i + 1) % segments
        inds.extend((0, i + 1, j + 1) if up else (0, j + 1, i + 1))
    PARTS.append((name, verts, norms, inds))


def paper_fragment(name, center, scale, charred=False):
    """A curled, irregular scrap readable from the game's elevated camera."""
    cx, cy, cz = center
    outline = [(-.50, -.34), (-.12, -.43), (.13, -.31), (.47, -.38),
               (.53, .18), (.26, .43), (-.10, .35), (-.46, .46)]
    verts = [(cx, cy + 0.018, cz)]
    for x, z in outline:
        curl = 0.065 * (x + .12) ** 2 + 0.025 * z
        verts.append((cx + x * scale, cy + curl * scale, cz + z * scale))
    norms = [(0.0, 1.0, 0.0)] * len(verts)
    inds = []
    for i in range(len(outline)):
        inds.extend((0, i + 1, (i + 1) % len(outline) + 1))
    PARTS.append(("char" if charred else name, verts, norms, inds))


def build():
    # Slightly flared 1930s office basket, open at the top. Separate inner and
    # outer shells make the opening convincingly hollow under close inspection.
    ring_part("galvanized_steel", [.255, .325], [.055, .62])
    ring_part("dark_steel", [.232, .294], [.075, .590], inward=True)
    disc("dark_steel", .255, .052)
    # Rolled lip and lower reinforcing bead.
    ring_part("galvanized_steel", [.325, .345, .345, .325], [.600, .610, .635, .645])
    ring_part("dark_steel", [.250, .268, .268, .250], [.045, .052, .073, .080])
    # Cold contents remain below the rim, while the clue's pale torn edge reads
    # clearly against them from the isometric investigation camera.
    disc("cold_ash", .270, .165, 18)
    paper_fragment("scorched_paper", (.035, .186, -.015), .33)
    # A smaller blackened overlap gives one edge a burned-away silhouette.
    paper_fragment("char", (.105, .192, -.055), .15, True)


def write_glb():
    build()
    blob = bytearray()
    views, accessors, primitives = [], [], []
    used = list(dict.fromkeys(part[0] for part in PARTS))

    def put(data, target):
        offset = len(blob)
        blob.extend(data)
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data), "target": target})
        return len(views) - 1

    for material, verts, norms, inds in PARTS:
        pv = put(b"".join(struct.pack("<3f", *p) for p in verts), 34962)
        nv = put(b"".join(struct.pack("<3f", *n) for n in norms), 34962)
        iv = put(b"".join(struct.pack("<H", i) for i in inds), 34963)
        pa = len(accessors)
        accessors.append({"bufferView": pv, "componentType": 5126, "count": len(verts), "type": "VEC3",
                          "min": [min(p[i] for p in verts) for i in range(3)],
                          "max": [max(p[i] for p in verts) for i in range(3)]})
        na = len(accessors)
        accessors.append({"bufferView": nv, "componentType": 5126, "count": len(norms), "type": "VEC3"})
        ia = len(accessors)
        accessors.append({"bufferView": iv, "componentType": 5123, "count": len(inds), "type": "SCALAR"})
        primitives.append({"attributes": {"POSITION": pa, "NORMAL": na}, "indices": ia,
                           "material": used.index(material)})

    materials = []
    for name in used:
        color, roughness, metallic = MATERIALS[name]
        materials.append({"name": name.replace("_", " ").title(), "pbrMetallicRoughness": {
            "baseColorFactor": color, "roughnessFactor": roughness, "metallicFactor": metallic}})
    doc = {"asset": {"version": "2.0", "generator": "Chicago Miriam wastebin generator"},
           "scene": 0, "scenes": [{"nodes": [0]}],
           "nodes": [{"mesh": 0, "name": "Miriam_Metal_Wastebin"}],
           "meshes": [{"name": "Miriam_Metal_Wastebin", "primitives": primitives}],
           "materials": materials, "buffers": [{"byteLength": len(blob)}],
           "bufferViews": views, "accessors": accessors}
    encoded = json.dumps(doc, separators=(",", ":")).encode()
    encoded += b" " * ((4 - len(encoded) % 4) % 4)
    total = 12 + 8 + len(encoded) + 8 + len(blob)
    data = (struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(encoded), b"JSON") + encoded
            + struct.pack("<I4s", len(blob), b"BIN\0") + blob)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(data)
    print(f"wrote {OUT.relative_to(ROOT)} ({len(data)} bytes, {len(PARTS)} primitives)")


if __name__ == "__main__":
    write_glb()
