# Author bespoke world presentation modes

## Goal

Make the shutter mechanism, body tableau, blood, and drag trace regular authored presentations instead of renderer branches selected by entity identity.

## Current bypasses

- The shutter is assembled procedurally in `vulkan_scene.odin` after locating a specially named entity.
- The corpse, blood decal, and drag trace use dedicated renderer code and marker-name fallbacks.
- Presentation offsets, dimensions, colors, mesh choices, and layering remain compiled in.

## Work

- Add catalog-supported presentation components for articulated mechanisms, posed characters, decals, and multi-part props.
- Author component transforms, tint, render layer, pose/animation, and state-driven variants.
- Bind shutter travel to an authored interaction output rather than a source-specific renderer path.
- Create catalog entries and LevelFormat records for the shutter assembly, body tableau, blood, and drag trace.
- Remove marker-name fallbacks and source/tag-selected bespoke rendering blocks.
- Ensure editor previews show the same authored presentation used during play.

## Acceptance criteria

- Moving or rotating any migrated presentation in LevelFormat moves the complete rendered assembly.
- The shutter still animates, indicates travel, and operates from the authored wall position.
- The body, blood, and drag trace retain their intended alignment and layering.
- No renderer branch names a Vale House entity or marker.
- Targeted open/closed shutter and crime-scene screenshots pass visual review.
- `make check` and all self-tests pass.

