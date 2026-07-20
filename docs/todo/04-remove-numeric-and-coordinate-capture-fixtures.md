# Remove numeric and coordinate capture fixtures

## Goal

Make capture and visual-test setup resolve authored IDs and camera/staging markers rather than entity array indices or world coordinates.

## Current bypasses

- Some capture modes still assign numeric `dialogue_entity` values.
- Many captures directly assign player, camera, character, and prop coordinates.
- Context captures assume stable ordering of runtime entities and interactives.

## Work

- Add or reuse LevelFormat staging and camera markers for every capture fixture.
- Resolve dialogue entities, context targets, clues, and interactives by stable authored ID.
- Introduce a small capture-fixture resolver that validates required markers and references.
- Migrate every capture mode in `main.odin`.
- Remove direct mutation of `WORLD_ENTITIES` during captures.
- Add a static check for numeric entity/interactive assignments in capture code.

## Acceptance criteria

- Reordering StoryCore entities, POIs, clues, or LevelFormat interactives does not change capture subjects.
- Moving a capture marker updates its capture without an Odin edit.
- No capture mode assigns a numeric entity/interactive index or hardcoded world transform.
- Every capture fails clearly when its authored fixture is missing.
- Representative dialogue, shutter, officer, context, and character captures render successfully.

