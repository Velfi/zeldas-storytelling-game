# Remove the legacy sample-house seed

Status: Complete (2026-07-20)

## Goal

Delete the compiled sample-house architecture so LevelFormat is the only source of rooms, walls, openings, surfaces, and furniture.

## Current bypasses

- `HOUSE_WALL_SPLINES` contains a compiled floor plan.
- `house_plan_initialize` seeds surfaces and architectural openings with fixed coordinates.
- Collision retains a fallback to the compiled wall splines.
- Some tests depend on the production fallback instead of constructing an authored fixture.

## Work

- Initialize the runtime house plan as an empty projection target.
- Remove compiled wall splines, openings, surface classification, and collision fallbacks.
- Make all runtime entry points require a successfully loaded and validated LevelFormat document.
- Move any useful sample geometry into a LevelFormat test fixture under `tests` or `assets/test`.
- Update geometry/editor tests to load or construct that fixture explicitly.
- Verify error handling for missing, empty, and invalid level documents.

## Acceptance criteria

- Searching production source finds no compiled Vale House floor-plan coordinates.
- Runtime architecture cannot appear unless it exists in the loaded LevelFormat document.
- Missing level content produces a clear validation failure rather than fallback geometry.
- Editor, navigation, collision, cutaway, roof, and opening tests use authored fixtures.
- `make check` and all self-tests pass.
