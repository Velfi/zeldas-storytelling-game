#!/usr/bin/env python3
"""Generate low-poly, source-controlled GLB placeholders for the mystery inventory.

Each Markdown inventory row becomes one valid glTF 2.0 binary model.  The models
are intentionally modular, Y-up, and named after the authored prop so designers
can replace or refine individual assets without changing the inventory manifest.
"""

from __future__ import annotations

import json
import math
import re
import struct
from collections import Counter
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
INVENTORY = ROOT / "docs/mysteries/3d-prop-inventory.md"
OUT = ROOT / "assets/models/mysteries"
MANIFEST = OUT / "manifest.json"


def slug(value: str) -> str:
    value = value.lower().replace("&", "and")
    value = re.sub(r"[^a-z0-9]+", "-", value).strip("-")
    return value or "prop"


class Mesh:
    def __init__(self) -> None:
        self.positions: list[tuple[float, float, float]] = []
        self.normals: list[tuple[float, float, float]] = []
        self.indices: list[int] = []

    def vertex(self, p: tuple[float, float, float], n: tuple[float, float, float]) -> int:
        self.positions.append(p)
        self.normals.append(n)
        return len(self.positions) - 1

    def quad(self, points: list[tuple[float, float, float]], normal: tuple[float, float, float]) -> None:
        base = [self.vertex(point, normal) for point in points]
        self.indices.extend((base[0], base[1], base[2], base[0], base[2], base[3]))

    def box(self, center: tuple[float, float, float], size: tuple[float, float, float]) -> None:
        cx, cy, cz = center
        sx, sy, sz = (value / 2 for value in size)
        p000 = (cx - sx, cy - sy, cz - sz)
        p001 = (cx - sx, cy - sy, cz + sz)
        p010 = (cx - sx, cy + sy, cz - sz)
        p011 = (cx - sx, cy + sy, cz + sz)
        p100 = (cx + sx, cy - sy, cz - sz)
        p101 = (cx + sx, cy - sy, cz + sz)
        p110 = (cx + sx, cy + sy, cz - sz)
        p111 = (cx + sx, cy + sy, cz + sz)
        self.quad([p000, p100, p110, p010], (0, 0, -1))
        self.quad([p101, p001, p011, p111], (0, 0, 1))
        self.quad([p001, p000, p010, p011], (-1, 0, 0))
        self.quad([p100, p101, p111, p110], (1, 0, 0))
        self.quad([p010, p110, p111, p011], (0, 1, 0))
        self.quad([p001, p101, p100, p000], (0, -1, 0))

    def cylinder(self, center: tuple[float, float, float], radius: float, height: float, sides: int = 12) -> None:
        cx, cy, cz = center
        bottom = cy - height / 2
        top = cy + height / 2
        start = len(self.positions)
        for ring_y, ny in ((bottom, -1.0), (top, 1.0)):
            for i in range(sides):
                a = math.tau * i / sides
                self.vertex((cx + radius * math.cos(a), ring_y, cz + radius * math.sin(a)), (0, ny, 0))
        for i in range(sides):
            a = math.tau * i / sides
            nx, nz = math.cos(a), math.sin(a)
            b0 = self.vertex((cx + radius * nx, bottom, cz + radius * nz), (nx, 0, nz))
            b1 = self.vertex((cx + radius * nx, top, cz + radius * nz), (nx, 0, nz))
            j = (i + 1) % sides
            na = math.tau * j / sides
            nnx, nnz = math.cos(na), math.sin(na)
            mid = math.atan2(nz + nnz, nx + nnx)
            face_normal = (math.cos(mid), 0, math.sin(mid))
            b2 = self.vertex((cx + radius * nnx, top, cz + radius * nnz), face_normal)
            b3 = self.vertex((cx + radius * nnx, bottom, cz + radius * nnz), face_normal)
            self.indices.extend((b0, b1, b2, b0, b2, b3))
        for i in range(1, sides - 1):
            self.indices.extend((start, start + i + 1, start + i))
            self.indices.extend((start + sides, start + sides + i, start + sides + i + 1))

    def rod_x(self, center: tuple[float, float, float], length: float, radius: float) -> None:
        # A box is used to keep the generated mesh dependency-free and readable.
        self.box(center, (length, radius * 2, radius * 2))


def build_mesh(name: str) -> tuple[Mesh, str, tuple[float, float, float, float]]:
    key = name.lower()
    mesh = Mesh()
    color = (0.31, 0.35, 0.40, 1.0)
    kind = "utility"

    if any(word in key for word in ("blood", "residue", "ash", "dust", "trace", "footprint", "drag", "chalk", "fiber")):
        mesh.box((0, 0.012, 0), (1.0, 0.024, 0.65))
        color, kind = (0.38, 0.06, 0.05, 1.0), "evidence_decal"
    elif any(word in key for word in ("bottle", "vial", "decanter", "jar", "carafe", "glass", "wine")):
        mesh.cylinder((0, 0.42, 0), 0.23, 0.72)
        mesh.cylinder((0, 0.88, 0), 0.075, 0.32)
        mesh.cylinder((0, 1.06, 0), 0.10, 0.06)
        color, kind = (0.24, 0.43, 0.30, 1.0), "vessel"
    elif any(word in key for word in ("clock", "timer", "gauge", "metronome")):
        mesh.box((0, 0.10, 0), (0.62, 0.20, 0.28))
        mesh.cylinder((0, 0.53, 0), 0.34, 0.14)
        mesh.rod_x((0.08, 0.59, 0.09), 0.34, 0.018)
        color, kind = (0.62, 0.48, 0.19, 1.0), "timepiece"
    elif any(word in key for word in ("cart", "trolley", "cradle", "chair", "bench", "rack", "shelf", "cabinet", "case", "trunk", "crate", "box", "bin", "caddy")):
        mesh.box((0, 0.44, 0), (1.35, 0.65, 0.82))
        mesh.box((0, 0.90, -0.31), (1.35, 0.50, 0.10))
        for x in (-0.48, 0.48):
            for z in (-0.28, 0.28):
                mesh.cylinder((x, 0.14, z), 0.13, 0.10)
        color, kind = (0.36, 0.20, 0.10, 1.0), "storage_or_cart"
    elif any(word in key for word in ("door", "gate", "hatch", "barrier", "panel", "transom", "latch", "catch", "bolt", "lock")):
        mesh.box((0, 1.0, 0), (1.15, 2.0, 0.10))
        mesh.box((0.36, 1.0, 0.10), (0.10, 0.10, 0.12))
        color, kind = (0.24, 0.16, 0.10, 1.0), "fixture"
    elif any(word in key for word in ("table", "desk", "workstation", "board", "podium", "counter", "stand", "plinth")):
        mesh.box((0, 0.80, 0), (1.45, 0.10, 0.85))
        for x in (-0.58, 0.58):
            for z in (-0.30, 0.30):
                mesh.box((x, 0.38, z), (0.09, 0.76, 0.09))
        color, kind = (0.28, 0.18, 0.11, 1.0), "furniture"
    elif any(word in key for word in ("key", "token", "ticket", "tag", "wristband", "card", "folder", "letter", "paper", "score", "map", "log", "ledger", "chart", "photograph", "permit", "program", "file")):
        mesh.box((0, 0.025, 0), (0.76, 0.05, 1.0))
        mesh.box((0, 0.055, 0), (0.65, 0.02, 0.88))
        color, kind = (0.72, 0.64, 0.47, 1.0), "document"
    elif any(word in key for word in ("line", "rope", "hose", "cord", "cable", "wire")):
        for i in range(8):
            mesh.box((-0.63 + i * 0.18, 0.08, 0.08 * math.sin(i)), (0.22, 0.075, 0.075))
        color, kind = (0.18, 0.16, 0.12, 1.0), "line"
    elif any(word in key for word in ("lamp", "light", "projector", "camera", "speaker", "recorder", "console", "screen", "detector", "terminal", "control")):
        mesh.box((0, 0.38, 0), (0.72, 0.50, 0.45))
        mesh.cylinder((0, 0.84, 0), 0.18, 0.36)
        mesh.box((0, 1.10, 0), (0.44, 0.10, 0.30))
        color, kind = (0.15, 0.18, 0.20, 1.0), "equipment"
    elif any(word in key for word in ("knife", "divider", "brace", "guide", "weight", "shoe", "cradle", "sample", "tool", "wrench", "trowel", "fork", "shears", "splicer")):
        mesh.rod_x((0, 0.10, 0), 1.10, 0.075)
        mesh.box((-0.42, 0.10, 0), (0.18, 0.18, 0.18))
        color, kind = (0.40, 0.42, 0.45, 1.0), "tool"
    elif any(word in key for word in ("violin", "bass", "instrument", "mute", "bow")):
        mesh.cylinder((0, 0.38, 0), 0.26, 0.60)
        mesh.box((0, 0.89, 0), (0.10, 0.50, 0.10))
        color, kind = (0.38, 0.16, 0.06, 1.0), "instrument"
    elif any(word in key for word in ("plant", "orchid", "flower", "soil", "compost", "garden")):
        mesh.cylinder((0, 0.16, 0), 0.28, 0.30)
        mesh.cylinder((0, 0.73, 0), 0.05, 0.90)
        for x, z in ((0.18, 0), (-0.18, 0), (0, 0.18), (0, -0.18)):
            mesh.box((x, 0.70, z), (0.30, 0.08, 0.16))
        color, kind = (0.15, 0.39, 0.18, 1.0), "garden"
    else:
        mesh.box((0, 0.40, 0), (0.80, 0.80, 0.80))
        mesh.cylinder((0, 0.88, 0), 0.20, 0.18)
        color, kind = (0.30, 0.32, 0.36, 1.0), "general"
    return mesh, kind, color


def align(data: bytes, fill: bytes = b"\x00") -> bytes:
    """Pad a GLB chunk to four bytes; JSON padding must be whitespace."""
    return data + fill * ((4 - len(data) % 4) % 4)


def write_glb(path: Path, name: str, notes: str, status: str) -> None:
    mesh, kind, color = build_mesh(name)
    positions = np.asarray(mesh.positions, dtype="<f4")
    normals = np.asarray(mesh.normals, dtype="<f4")
    indices = np.asarray(mesh.indices, dtype="<u4")
    pos_bytes = positions.tobytes()
    normal_bytes = normals.tobytes()
    index_bytes = indices.tobytes()
    blob = align(pos_bytes) + align(normal_bytes) + align(index_bytes)
    pos_offset = 0
    normal_offset = len(align(pos_bytes))
    index_offset = normal_offset + len(align(normal_bytes))
    lo = positions.min(axis=0).tolist()
    hi = positions.max(axis=0).tolist()
    doc = {
        "asset": {"version": "2.0", "generator": "generate_mystery_props.py"},
        "scene": 0,
        "scenes": [{"name": "Mystery prop scene", "nodes": [0]}],
        "nodes": [{"name": slug(name), "mesh": 0, "extras": {"inventory_name": name, "inventory_status": status, "notes": notes}}],
        "meshes": [{"name": slug(name), "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1}, "indices": 2, "material": 0, "mode": 4}]}],
        "materials": [{"name": f"{kind}_material", "pbrMetallicRoughness": {"baseColorFactor": color, "metallicFactor": 0.12 if kind in {"tool", "timepiece"} else 0.0, "roughnessFactor": 0.62}}],
        "buffers": [{"byteLength": len(blob)}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": pos_offset, "byteLength": len(pos_bytes), "target": 34962},
            {"buffer": 0, "byteOffset": normal_offset, "byteLength": len(normal_bytes), "target": 34962},
            {"buffer": 0, "byteOffset": index_offset, "byteLength": len(index_bytes), "target": 34963},
        ],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(positions), "type": "VEC3", "min": lo, "max": hi},
            {"bufferView": 1, "componentType": 5126, "count": len(normals), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5125, "count": len(indices), "type": "SCALAR", "min": [int(indices.min())], "max": [int(indices.max())]},
        ],
    }
    json_chunk = align(json.dumps(doc, separators=(",", ":")).encode("utf-8"), b" ")
    bin_chunk = align(blob)
    total = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
    payload = b"".join((struct.pack("<4sII", b"glTF", 2, total), struct.pack("<I4s", len(json_chunk), b"JSON"), json_chunk, struct.pack("<I4s", len(bin_chunk), b"BIN\x00"), bin_chunk))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def inventory_rows() -> list[dict[str, str]]:
    campaign = "shared"
    section = "shared"
    rows: list[dict[str, str]] = []
    for raw in INVENTORY.read_text().splitlines():
        if raw.startswith("## "):
            campaign = slug(raw[3:])
            section = campaign
        elif raw.startswith("### "):
            section = slug(raw[4:])
        elif raw.startswith("| ") and not raw.startswith("| ---"):
            cells = [cell.strip() for cell in raw.strip().strip("|").split("|")]
            if len(cells) != 3 or cells[0] in {"Prop", "Prop family"}:
                continue
            rows.append({"campaign": campaign, "section": section, "name": cells[0], "status": cells[1], "notes": cells[2]})
    return rows


def main() -> None:
    rows = inventory_rows()
    if not rows:
        raise SystemExit("No inventory rows found")
    OUT.mkdir(parents=True, exist_ok=True)
    name_counts: Counter[tuple[str, str, str]] = Counter()
    manifest: list[dict[str, str]] = []
    for row in rows:
        key = (row["campaign"], row["section"], slug(row["name"]))
        name_counts[key] += 1
        suffix = "" if name_counts[key] == 1 else f"-{name_counts[key]}"
        relative = Path(row["campaign"]) / row["section"] / f"{key[2]}{suffix}.glb"
        write_glb(OUT / relative, row["name"], row["notes"], row["status"])
        manifest.append({**row, "path": str(relative)})
    MANIFEST.write_text(json.dumps({"version": 1, "source": str(INVENTORY.relative_to(ROOT)), "models": manifest}, indent=2) + "\n")
    print(f"Generated {len(manifest)} GLB props in {OUT}")


if __name__ == "__main__":
    main()
