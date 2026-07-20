# Enforce no hardcoded author-facing entities

## Goal

Add automated badness checks that prevent author-facing entity identity, transforms, presentation, behavior, and copy from returning to compiled source.

## Dependencies

Complete the other hardcoding-migration todos first so enforcement can be strict without allowlisting existing debt.

## Work

- Add a repository check, invoked by `make check`, that detects:
  - entity or marker IDs in generic renderer dispatch;
  - numeric assignments to entity, clue, POI, or interactive indices;
  - compiled world transforms in capture fixtures;
  - static `World_Entity` content tables;
  - synthetic interactives created outside LevelFormat projection;
  - author-facing dialogue/description copy in generic world and UI dispatch.
- Prefer structural checks over fragile broad text matching where practical.
- Add runtime validation requiring complete spatial, presentation, and interaction bindings for relevant StoryCore roles.
- Add negative tests proving each forbidden pattern is rejected.
- Document the boundary between legitimate engine constants and author-facing data.

## Acceptance criteria

- Each previously identified hardcoding pattern has a failing regression fixture.
- The check reports the file, line, forbidden category, and recommended authoring destination.
- No production exception list contains Vale House entity IDs.
- `make check` runs the enforcement automatically and passes on the migrated project.
- The authoring-boundary documentation clearly permits engine geometry/math while forbidding content identity and placement.
