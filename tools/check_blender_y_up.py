"""Static guardrails for the project's Blender Y-up authoring helpers."""

from __future__ import annotations

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = (ROOT / "tools/blender_generate_mystery_props.py").read_text()
HERO_BUILDER = (ROOT / "tools/blender_build_p0_mystery_heroes.py").read_text()
PROOFER = (ROOT / "tools/blender_render_mystery_prop_batches.py").read_text()


def require(source: str, expected: str, label: str) -> None:
    if expected not in source:
        raise AssertionError(f"{label}: missing `{expected}`")


def main() -> int:
    # These are intentionally source-level checks: changes to the helpers must
    # preserve the basis rather than silently reverting to Blender's Z-up
    # primitive defaults.
    require(GENERATOR, "from mathutils import Euler", "generator")
    require(GENERATOR, "base = Euler((math.pi / 2, 0, 0))", "Y-up primitives")
    require(GENERATOR, "adjustment.to_matrix() @ base.to_matrix()", "Y-up primitives")
    require(GENERATOR, 'cyl("splicer reel", (x, 0.40, 0)', "upright splicer reel clearance")
    require(GENERATOR, 'cyl("editing reel", (x, 0.85, 0)', "upright editing reel clearance")
    require(GENERATOR, 'cyl("recorder reel", (x, 0.59, -0.10)', "upright recorder reel clearance")
    require(GENERATOR, '"recorder", "recording player"', "recording player routing")
    require(GENERATOR, '"plant/fern frond"', "unique fern specimen")
    require(GENERATOR, '"plant/snake blade"', "unique snake-plant specimen")
    require(GENERATOR, '"pot/planter"', "separate planter component")
    require(HERO_BUILDER, '"pot/orchid pot"', "separate orchid pot component")
    require(HERO_BUILDER, '"plant/orchid stem"', "separate orchid foliage component")
    require(HERO_BUILDER, "from mathutils import Euler, Vector", "hero builder")
    require(HERO_BUILDER, "adjustment.to_matrix() @ base.to_matrix()", "hero Y-up primitives")
    require(HERO_BUILDER, 'PETAL(), (1.0, 0.65, 0.18)', "orchid bloom Z thickness")
    require(HERO_BUILDER, "petal.rotation_euler[2] = angle", "orchid bloom Y-up rotation")
    require(PROOFER, "group.location += Vector((x, 0.20, z))", "proof grid")
    require(PROOFER, "rotation=(math.pi / 2, 0, 0)", "proof ground plane")
    require(PROOFER, "location=(0, 16.0, -16.5)", "proof camera")
    require(GENERATOR, "export_yup=False", "generator avoids double axis conversion")
    require(HERO_BUILDER, "export_yup=False", "hero builder avoids double axis conversion")
    print("Blender Y-up guardrails: OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(f"Blender Y-up guardrails: FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
