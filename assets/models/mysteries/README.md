# Mystery prop library

This directory contains generated GLB source assets for every row in
`docs/mysteries/3d-prop-inventory.md`.

- `manifest.json` is the one-to-one inventory mapping.
- Directory names group models by campaign and case.
- Every GLB is right-handed, Y-up, and contains named mesh/node metadata with
  its inventory status and authoring note.
- `tools/generate_mystery_props.py` deterministically rebuilds the library.

The generated meshes are deliberately low-poly production blockouts. They give
levels and MysteryScript authoring stable paths immediately, while retaining a
one-file-per-prop replacement path for higher-fidelity Blender work. Existing
Kenney, foliage, rug, vehicle, and project-specific assets remain the source of
truth for entries marked **Reuse** in the inventory; this library provides a
stable case-local model for every required inventory row, including those
variants and stateful evidence props.
