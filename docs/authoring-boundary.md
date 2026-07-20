# Authoring boundary

Compiled Odin owns reusable engine policy: geometry algorithms, coordinate-system
conversion, camera math, collision tolerances, UI layout, animation mechanics,
rendering constants, and format/runtime limits. Numeric values that describe those
systems are legitimate engine constants.

Compiled source must not own story content. Entity and marker identity, world or
capture placement, appearance selection, interaction behavior, player-facing names,
descriptions, dialogue, and localized copy belong in StoryCore, LevelFormat, authored
scenes, or localization data. Runtime code resolves those records by stable ID; it
must not depend on entity, clue, POI, or interactive array order.

LevelFormat projection is the only place runtime world entities and interactives are
materialized. Generic renderers select presentations from authored metadata or typed
capabilities, never by comparing a story entity ID. Capture composition uses authored
staging and camera markers and fails validation when a required binding is absent.

Run `make check` to enforce this boundary. Diagnostics identify the source location,
category, and recommended authoring destination.
