# Author character reactions and officer dialogue

## Goal

Move character-specific presentation changes and officer conversations into StoryCore-authored character and dialogue data.

## Current bypasses

- Character mesh, idle clip, phase, and reaction facing are selected by character IDs.
- Miriam, Daniel, and Elsie have compiled story-state pose changes.
- Officer opening/report lines and lead-officer UI choices are selected in source-ID switches.

## Work

- Extend authored character presentation with catalog appearance, default animation, phase, tint, and facing.
- Support condition-driven presentation overrides for reaction poses and animations.
- Express officer conversations, reports, and reconstruction choices as StoryCore scenes/nodes.
- Replace the special officer UI path with the regular dialogue runtime where possible.
- Migrate all current character and officer content.
- Remove character-ID and officer-ID presentation/dialogue switches.

## Acceptance criteria

- Character appearance and default pose can be changed without recompiling.
- Existing reaction beats still occur at the same story milestones.
- All three officers retain their current reports and the lead officer retains the reconstruction flow.
- Renaming a character through authored references requires no Odin edits.
- Generic character rendering and dialogue contain no Vale House character IDs.
- Dialogue, screenshot, and self-tests pass.

