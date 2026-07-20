---
name: interior-design
description: Furnish, rearrange, restyle, or evaluate the contents of a specific 3D room or building interior in the Chicago mystery-game project. Use only when the user explicitly requests interior decoration, furniture or prop placement, room furnishing, spatial layout of interior objects, interior lighting composition, occupant-driven room dressing, or environmental storytelling inside an authored LevelFormat space.
---

# Interior Design

Create interiors as evidence of activities, occupants, history, and recent events. Preserve playability and mystery logic before improving appearance.

## Start by reading context

1. Read `/Users/zelda/Documents/chicago/AGENTS.md` and every instruction it links.
2. Read `docs/product-design.md` when narrative or mystery behavior matters.
3. Inspect the target room and its nearby rooms, doors, windows, markers, objects, and materials.
4. Read [references/tool-contract.md](references/tool-contract.md) before invoking `tools/interior_agent.py` or modifying level data.
5. Read [references/design-principles.md](references/design-principles.md) before generating or substantially revising a layout.

## Establish the brief

Infer only low-risk details. Ask for direction when style, period, occupant, or narrative purpose would materially change the result and cannot be discovered from project data.

Record or state:

- room functions and activities;
- occupants, means, habits, taste, and maintenance level;
- period, style, palette, mood, and desired first impression;
- entrances, focal points, activity zones, and primary routes;
- interaction envelopes, sightlines, clues, staging markers, and immutable story facts;
- intentional irregularities and what caused them.

Treat gameplay and canonical mystery requirements as hard constraints. Treat aesthetic preferences as soft constraints.

## Work in passes

1. **Inspect:** Understand the shell, existing contents, catalog, and narrative bindings.
2. **Protect:** Identify door access, circulation, markers, interactions, and mystery-critical sightlines.
3. **Zone:** Assign areas for movement, conversation, work, storage, display, and transitions.
4. **Anchor:** Place the few large objects that define function and focal hierarchy.
5. **Support:** Add secondary furniture with explicit relationships to anchors.
6. **Light:** Provide ambient, task, and accent intent without changing narrative visibility accidentally.
7. **Dress:** Add occupant-specific props, storage logic, wear, omissions, and event traces.
8. **Validate:** Check geometry, support relationships, reachability, circulation, and story constraints.
9. **Render and critique:** Review the canonical plan and, when available, doorway, player-height, interaction, and critical-sightline views.
10. **Revise:** Fix one diagnosed issue at a time and revalidate.

Do not start with decoration. Do not use random jitter as a substitute for human specificity.

## Place semantically

Prefer relationships such as `against_wall`, `beside`, `in_front_of`, `facing`, and `on_surface` over hand-authored coordinates. Preview every placement before committing it. Use stable, descriptive IDs. Group objects by shared activity or focal relationship rather than distributing them evenly.

Agents author intent and relationships; the engine owns coordinate conversion, placement resolution, persistence, and runtime truth.

## Respect project geometry

Use the project convention exactly:

- right-handed, Y-up 3D coordinates;
- map ground `(x, y)` to 3D `(x, elevation, y)`;
- ground headings run from +X toward +Z and appear clockwise from +Y;
- keep transforms, front directions, normals, winding, and imported assets consistent.

Never guess an asset's front direction or support surface when metadata or a rendered view can establish it.

## Preserve human plausibility

Build three legible layers:

1. **Baseline:** The normal functional room.
2. **Occupant:** Personal taste, routines, resources, storage, and wear.
3. **Event:** Recent changes caused by the crime, concealment, interruption, or investigation.

Create controlled asymmetry through causality: reach, use frequency, incomplete sets, repairs, temporary objects, or displaced items. Keep intentional anomalies visually readable without making every object conspicuous.

## Validate and report

Require all of the following before calling a change complete:

- level and placement validation passes without errors;
- object centers, footprints, and support relationships are valid;
- primary routes, openings, interaction points, and clues remain usable;
- focal hierarchy and activity groupings read clearly in rendered views;
- style choices fit the brief or have an authored narrative reason not to;
- the final level remains ordinary LevelFormat data used by editor and runtime.

Report the design intent, material changes, validation performed, and any remaining warnings or visual checks. Never describe a plan render as a production 3D render.
