#!/usr/bin/env python3
"""Repair opacity metadata in already-exported character GLBs."""

import json
import struct
import sys
from pathlib import Path

JSON_CHUNK = 0x4E4F534A


def repair(path: Path) -> None:
    data = bytearray(path.read_bytes())
    if data[:4] != b"glTF" or struct.unpack_from("<I", data, 4)[0] != 2:
        raise ValueError(f"not a glTF 2 GLB: {path}")
    chunk_length, chunk_type = struct.unpack_from("<II", data, 12)
    if chunk_type != JSON_CHUNK:
        raise ValueError(f"first GLB chunk is not JSON: {path}")
    start, end = 20, 20 + chunk_length
    document = json.loads(data[start:end])
    changed = 0
    for material in document.get("materials", []):
        pbr = material.get("pbrMetallicRoughness", {})
        factor = pbr.get("baseColorFactor")
        if factor is not None and len(factor) == 4 and factor[3] != 1:
            factor[3] = 1
            changed += 1
        material.pop("alphaMode", None)
        material.pop("alphaCutoff", None)
        material.pop("doubleSided", None)
    encoded = json.dumps(document, separators=(",", ":")).encode()
    padded_length = (len(encoded) + 3) & ~3
    data[end:end] = b" " * max(0, padded_length - chunk_length)
    if padded_length < chunk_length:
        del data[start + padded_length : end]
    data[start : start + padded_length] = encoded.ljust(padded_length, b" ")
    struct.pack_into("<I", data, 8, len(data))
    struct.pack_into("<I", data, 12, padded_length)
    path.write_bytes(data)
    print(f"repaired {path}: {changed} transparent base colors")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("usage: fix_character_glb_materials.py model.glb [...]")
    for argument in sys.argv[1:]:
        repair(Path(argument))
