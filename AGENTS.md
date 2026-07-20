# Project Agent Notes

docs/product-design.md
docs/cli.md
docs/dialogue-guidelines.md

## 3D Coordinate Convention

- Use a right-handed, Y-up coordinate system: +X is right, +Y is up, and +Z is forward (`+X × +Y = +Z`).
- Map 2D ground-plane coordinates `(x, y)` to 3D `(x, elevation, y)`; the 2D Y axis therefore corresponds to 3D Z.
- Ground-plane headings are measured from +X toward +Z, so increasing yaw appears clockwise when viewed from +Y.
- Author front faces with winding and normals that agree in this basis. In particular, an upward-facing XZ triangle has clockwise XZ winding when viewed from +Y because `+Z × +X = +Y`.
- Keep transforms, procedural geometry, camera math, imported assets, and winding conversions consistent with this convention.
