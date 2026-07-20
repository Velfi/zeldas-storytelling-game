# Author story-state visibility and interactions

## Goal

Move entity visibility, availability, prompts, and interaction outcomes out of source-ID branches and into the regular StoryCore and LevelFormat authoring pipeline.

## Current bypasses

- `entity_visible` special-cases the ledger, memo stub, and shutter thread.
- Context targeting and activation special-case the desk, body, rug, statuette, cloth, burned note, shutter, reflection, and dining room.
- Several discovery gates read `Game` booleans directly instead of authored StoryCore conditions/effects.

## Work

- Define an authored binding from a world entity or LevelFormat interactive to StoryCore conditions and effects.
- Represent initial visibility, reveal conditions, interaction availability, prompt/status text, and completion state in authored data.
- Project authored state into runtime entities without comparing entity IDs.
- Migrate every Vale House entity currently handled by a source-ID branch.
- Remove obsolete per-entity visibility and activation branches.
- Add round-trip serialization and validation for all new fields.

## Acceptance criteria

- Renaming an entity and updating its authored references does not require an Odin change.
- Desk, rug, body, memo, burned-note, cloth, statuette, shutter-thread, reflection, and dining interactions retain their current progression.
- Missing or incompatible conditions/effects fail authoring validation.
- A repository check rejects source-ID comparisons in generic visibility and interaction dispatch.
- `make check`, story validation, and all self-tests pass.

