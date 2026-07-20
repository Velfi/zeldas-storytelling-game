# Interactive Story v1

`InteractiveStory v1` is the general, deterministic narrative substrate for the
Chicago Story Studio. It is the sole shipped narrative source format; the
offline development converter is the only component that reads legacy MurderScript while
the reference mystery is re-authored on the new model.

## Design contract

- Narrative logic reads and writes declared typed state only.
- Effects from one completed narrative action commit atomically or not at all.
- Character awareness, belief, communication, and canonical truth are distinct.
- Authored scenes provide deliberate sequences; storylets provide contextual,
  reorderable content.
- Storylet selection is deterministic and explainable.
- Human UI and agent tooling use the same revision-checked command batches.
- Player packages contain no authoring agent or runtime generative dependency.
- Genre is descriptive metadata, never an exclusive runtime mode.
- Reusable props and other content are independent of the mechanics that ship
  beside them.
- Future capability dependencies must compose; a story may require several
  compatible capabilities without being forced into one genre domain.

## Expansion-ready boundary

The current schema is an intentional clean break from the development-era v1
shape: `domain` and `domain_version` are rejected. `[[capabilities]]` declares a
composable, exact-version set of engine-provided adapters over the always-present
core, while `[[expansions]]` declares exact reusable-content dependencies.

Expansion content belongs in additive, namespaced registries. A prop's source
expansion may supply provenance, tags, defaults, and assets, but it does not
restrict which stories can place or script that prop. Story packages declare
hard requirements separately from optional content and must resolve all hard
references before compilation. Capability adapters may validate their own
records and contribute editor or player surfaces, while shared state,
conditions and effects, scenes, saves, and deterministic transactions remain
core contracts.

Capability implementations are compiled into the trusted engine. Expansion
archives contain data and assets only; they cannot introduce executable code.

## Source and runtime

The source entrypoint is a Git-readable TOML document. The core types are in
`src/story_core.odin`, and parsing is in `src/story_io.odin`. Top-level arrays
are dynamic; cross-document identity uses stable string IDs. `Story_State`
contains only runtime values and history and is initialized from a validated
project.

Every currently declared record family is losslessly parsed and serialized,
including roles, facts, relationships, event witnesses, scene nodes, endings,
and invariants. `compile_story_project` validates the source, assigns compact
runtime IDs in stable-ID order, and takes an owned runtime snapshot. Editor
mutations therefore cannot change a running story without recompilation.

Supported value kinds are Boolean, bounded integer, enumeration, and entity
reference. Conditions form a flat typed tree. Effects are ordered and applied
through `story_apply_transaction`, which uses a working state clone to prevent
partial mutation.

Character knowledge follows `docs/character-knowledge-system.md`: absence means
unaware; an aware actor is uncertain, believes, or disbelieves. Communication
is append-only during forward play and does not imply canonical truth.

## Storylets

A storylet belongs to a group and references an authored scene. The runtime:

1. removes candidates whose conditions, once-only rule, or cooldown fail;
2. prefers higher dramatic priority;
3. prefers higher specificity;
4. prefers the least-seen candidate;
5. uses authored order as the final deterministic tie-break.

Every non-empty group requires a fallback unless it explicitly allows no
content. `storylet_select` returns every candidate and a selection explanation
for editor and MCP diagnostics.

## Authoring commands

`story_command_batch` is the shared mutation boundary. A caller supplies the
revision it inspected, one or more typed commands, and an optional dry-run flag.
The batch is applied to a working document, validated, and committed as one
revision. Stale revisions and invalid batches leave source data unchanged.
Typed record commands cover all stable-ID record families. Capability discovery,
reference search, and dependency inspection are exposed as transport-neutral
queries for UI and MCP adapters.

## Scene runtime

`Story_Runtime` executes the compiled snapshot and owns its `Story_State`.
Scene entry, condition checks, ordered node effects, subscene call/return, and
scene completion all use the same deterministic transaction machinery. The
current executable slice covers the core node traversal contract; save files,
choice presentation models, breakpoints, and target-state exploration remain
future slices.

## Containers

Any entity with a positive `container_capacity` is a container. Storable
entities declare a positive `volume`; the sum of their volumes may not exceed
the container's capacity. Containers may start `locked`, may name an `owner`,
and entities may start inside one with `contained_by`:

```toml
[[entities]]
id = "desk"
kind = "object"
volume = 12
container_capacity = 8
locked = true
owner = "miriam"

[[entities]]
id = "letter"
kind = "object"
volume = 1
contained_by = "desk"
```

Lock state, current ownership, and containment are runtime state. Locked
containers reject storing and removing items. The core API supports querying
used and available volume, storing and removing entities, locking and
unlocking, and changing or clearing ownership. Validation rejects missing
references, over-capacity initial contents, and containment cycles.

## Commands

```sh
make story-core-test
make story-validate STORY=assets/stories/the_lantern_visit.story.toml
make story-export STORY_OUT=build/the-lantern-visit-1.0.0.zip
make story-inspect PACKAGE=build/the-lantern-visit-1.0.0.zip
make story-install PACKAGE=build/the-lantern-visit-1.0.0.zip
```

The proof project is `assets/stories/the_lantern_visit.story.toml`. It uses only
Blank Core records: actors, an object, bounded relationship state, a world-state
enumeration, explicit knowledge transfer, an objective, an event, and
contextual storylets.

## Current boundary

Structural validation, lossless source round trips, deterministic compilation,
atomic runtime state, basic scene execution, storylet selection, typed command
transactions, query discovery, and portable packaging are implemented. The
package manifest records state-space coverage as incomplete. Multi-document
source composition, condition/effect stable IDs, saves, complete node UX,
bounded exploration, counterexample generation, command-bus integration with
Level/Graph/MCP, the multi-view editor UI, and Mystery-pack re-authoring remain
subsequent implementation slices and must not be described as complete or
proven.
