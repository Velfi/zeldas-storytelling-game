# Graph Mode

Graph Mode is the visual editor for InteractiveStory scenes and nodes. It is a
top-level sibling of Build Mode: Build Mode authors spatial assets and markers;
Graph Mode authors narrative flow and presentation that reference those assets.

## Source ownership

There is no separate dialogue or graph runtime document. The active
InteractiveStory TOML owns `[[scenes]]` and `[[nodes]]`, including stable choice
IDs, result edges, conditions, effects, and presentation fields. Saving or
autosaving Graph Mode writes an InteractiveStory document. Node positions,
selection, pan, and zoom are editor-only state and do not affect compiled
content identity.

Graph Mode imports its working presentation from `Story_Project`, validates it
as StoryCore content, compiles a temporary `Compiled_Story` for playtest, and
executes the selected scene through `Story_Runtime`. Stopping playtest destroys
that temporary snapshot and restores the editor state.

## Connection routing variation board

Run the editor with `--capture-graph-routing-board` to open an ephemeral Graph
Mode fixture for connection-wire QA. The board covers a clear forward edge, an
obstructed forward edge, a backward edge using an outside lane, and a bundled
three-way fan-out. Use `--capture-graph-routing-crossings` for its second scene,
which stresses crossing and tightly parallel wires. It has no source project and disables autosave, so it cannot
overwrite authored story data. Capture output defaults to
`/private/tmp/chicago-vulkan-graph-routing-board.png`.

The focused variants `--capture-graph-routing-direct-hover`,
`--capture-graph-routing-obstacle-hover`, and
`--capture-graph-routing-back-hover`, plus
`--capture-graph-routing-crossing-hover` and
`--capture-graph-routing-parallel-hover`, highlight one route and its in-line
flow marker for deterministic visual regression captures.
`--capture-graph-routing-zoomed-hover` shows the crossing fixture at 55% zoom
to check overview-scale wire hierarchy.

## Node language

The editor exposes StoryCore node kinds used by Chicago:

| Node | Purpose | Inputs or outgoing edges |
| --- | --- | --- |
| Line | Speaker and dialogue text | Advance / Next |
| Choice | Stable player choices | One stable ID and target per choice |
| Check | Host-supplied or condition result | Success, Failure, Cancel |
| Stage | Camera, actor mark, animation, duration, UI transition | Advance / Next |
| Interaction | Focused spatial interaction | Success, Failure, Cancel |
| Wait Event | Await a stable external event ID | Signal / Next |
| Subscene | Enter a nested scene | Return edge |
| End | Complete or return from a scene | None |

Mystery-specific clue and interaction annotations are stored in the registered
MysteryDomain payload and keyed by the core node ID. They are not StoryCore
node kinds.

## Editing and validation

- Nodes and choices retain stable IDs when moved or reordered.
- Connections use explicit result edges and never array positions.
- Camera and actor-mark pickers resolve qualified LevelFormat targets.
- Play is blocked by missing IDs, invalid edges, invalid condition/effect
  references, recursive subscenes, or unresolved spatial bindings.
- Save validates the complete StoryCore project and MysteryDomain payload.
- Autosave may preserve an invalid draft in an InteractiveStory autosave file;
  package export requires complete validation.

## Build Mode relationship

Build Mode owns geometry, navigation, objects, interactions, lights, spawns,
and transitions. Graph Mode references those records through qualified spatial
bindings and presentation marker IDs. City and level spaces remain distinct;
cross-space travel is resolved by the shared spatial service.
