# Product Design

## Product vision

This project is one tool and one game for creating, sharing, and playing spatial
interactive stories. Murder mysteries are the first complete authored
experience and quality bar, not a permanent genre boundary.

> Make a place. Put a story inside it. Let someone else live through it.

A creator builds a location, places props, authors characters and events, and
selects the mechanics the story needs. The tool validates that the result is
coherent and gives the creator a fast way to playtest it. A finished story can
then be packaged and shared with another player. Mystery-specific stories may
stage a crime and conceal a solution, but the same game must also support
stories with different structures and combinations of mechanics.

Creation, sharing, and play are three views of the same story rather than
separate products. One versioned story project drives the editor, validator,
portable package, and game runtime.

## Expansions and composability

Chicago is a single extensible game, not a collection of genre-specific
executables. An expansion may contribute reusable content such as props,
materials, characters, animation, audio, environments, and authoring presets.
It may eventually contribute mechanics as well. No new mechanics module is
introduced merely to label a genre; a module exists only when an implemented,
versioned capability requires one.

Content is not owned by a genre. A laboratory console from a science-fiction
expansion may be placed in a murder mystery, an antique lantern may appear on a
space station, and either prop may participate in any interaction supported by
the story. Catalog filtering may use themes and tags for discovery, but those
tags never prohibit cross-genre use.

Mechanics are composable capabilities rather than mutually exclusive modes. A
story may combine investigation, branching dialogue, driving, survival,
relationships, supernatural state, or future mechanics whenever their declared
versions are compatible. The package and editor must not require a story to
choose one exclusive genre or one exclusive mechanics domain.

This establishes the following compatibility contract before the first
expansion ships:

- expansion-owned assets and capabilities use stable, namespaced IDs;
- installation adds to shared registries and never silently replaces base or
  third-party content;
- a story records exact required expansion and capability versions, while
  optional dependencies degrade only in explicitly authored ways;
- saves retain resolved content identities so another expansion cannot change
  an existing playthrough through ID collision or load order;
- packaging may reference installed reusable content or embed content when its
  license and distribution model permit it;
- validators report missing, incompatible, and ambiguous dependencies before
  play or export;
- stories using several compatible capabilities receive the union of their
  authoring and player-facing surfaces.

The current implementation continues to ship only the core story runtime and
the existing mystery capability. Preparing registries, manifests, and UI for
composition does not authorize placeholder genre modules.

## Product principles

### Mysteries are places, not questionnaires

The player solves a mystery by moving through an authored space, noticing its
physical details, speaking with characters, testing claims, and reconstructing
events. The location is part of the reasoning. Sightlines, travel time, object
placement, access, and changes to the environment can all become evidence.

### The player constructs the explanation

Finding every highlighted clue is not the goal. Players form questions, combine
evidence, test deductions, and ultimately present a supported account of who
committed the crime, how, where, when, and why. A correct guess is not enough.

### Authors define truth; the engine checks consistency

The creator authors the canonical events and the information available to each
character. InteractiveStory with its registered MysteryDomain and the spatial editor turn that truth into a playable
case. Deterministic validation catches broken references, impossible timelines,
unreachable evidence, unsupported conclusions, and essential progress that
depends on chance.

### Authoring and playtesting form one loop

Creators should be able to move quickly between building, writing, validating,
and playing:

```text
Build the place
-> author the crime and its witnesses
-> place evidence and interactions
-> validate fairness and consistency
-> play as a detective
-> revise
```

Preview uses the real game runtime. The editor should not maintain a parallel
approximation of how a mystery will behave.

### The game never spoils the mystery accidentally

A playable package contains everything required to adjudicate the mystery, and
its contents may reveal the solution to someone who deliberately inspects them.
Ordinary player-facing tools never reveal canonical truth, hidden claim flags,
accepted deduction pieces, or undiscovered content. Revealing the solution or
entering a creator-facing mode requires an explicit choice; the product does not
claim to protect the mystery from deliberate source inspection.

## The three experiences

### Create

Creation combines several focused workspaces over one case:

- **Build Mode** authors terrain, buildings, rooms, objects, lighting,
  characters, interactions, and staging markers.
- **Graph Mode** authors dialogue, choices, checks, cinematics, and the flow of
  playable scenes.
- **Mystery authoring** defines the victim, suspects, motives, canonical event
  sequence, claims, clues, deductions, solution requirements, and investigation
  economy.
- **Validation** checks both data integrity and mystery-specific qualities such
  as affordability, physical possibility, evidence routes, and exclusion of
  innocent suspects.
- **Playtest** launches the current draft in the normal player presentation,
  with separate creator diagnostics available when requested.

The tool should make the correct relationships easy to author without turning
MysteryDomain into a generic programming language. Stable IDs, typed references,
searchable pickers, and direct links between workspaces keep the case legible.

### Share

Sharing begins as a local, account-free workflow. A creator exports a mystery as
a portable package. Another person imports or opens that package and plays it.
The package is the durable product boundary, even when both people use the same
computer.

The first sharing experience should support:

- export from a valid mystery draft;
- a package manifest with a stable mystery ID, title, author, description,
  format version, and content version;
- all required case data, level data, graphs, assets, and generated metadata;
- a player-safe launch path that does not expose the solution through the UI;
- import with validation, compatibility diagnostics, and clear conflict
  handling;
- multiple installed versions or an explicit upgrade decision, without silently
  overwriting a creator's source project;
- a self-contained thumbnail and summary suitable for a future library.

Initially, packages can be exchanged through the filesystem, removable media,
or any existing file-sharing service. No account, server, or network connection
is required to create, export, import, or play a mystery.

The package format should nevertheless be ready for a future community library.
Publishing can later upload the same artifact and manifest rather than introduce
a second case format. Discovery, ratings, moderation, creator identity, remote
updates, and dependency delivery are future services layered over local
packages—not requirements of the core creation or play experience.

### Play

Players browse installed mysteries, choose one, and enter its authored world as
the detective. The core play loop is:

```text
Notice an irregularity
-> investigate it physically or socially
-> gain evidence or establish a fact
-> use it to test a question
-> watch the mystery accept or reject the reasoning
-> form the next question
-> present the completed explanation
```

Each mystery may vary in setting, cast, structure, and tone, but the shared
player language should remain dependable: exploration, conversations, evidence,
notebook, questions, demonstrations, deductions, reconstruction, and reveal.
The engine adjudicates the authored solution without leaking it and reports why
an incomplete theory is unsupported.

## The mystery artifact

A mystery has three representations with explicit boundaries:

1. **Source project**: editable documents, working assets, layout metadata,
   autosaves, and creator-only diagnostics.
2. **Playable package**: a validated, versioned, portable artifact containing
   runtime data and assets.
3. **Installed mystery**: an imported package registered in the local library
   alongside player progress and settings.

Player progress is never stored inside the package. Importing, replaying, or
upgrading a mystery must not mutate the creator's source project. A package's
manifest and content identity should be sufficient for a future online service
to distribute, cache, verify, and update the same artifact.

## Current product proof

`The Torn Appointment` is the reference mystery and vertical slice. It proves the
complete play experience and exercises the authoring systems against a real
case. It is not the product's only intended story.

Westhaven Police Station is a permanent landmark in the shared world, but it is
not a mandatory opening for every mystery. `The Torn Appointment` uses it as its
tutorial start: the player learns movement, camera control, and contextual
interaction there, receives the dispatch briefing, and then travels to Vale
House as a distinct second location where the manor mystery begins. Other cases
start at their own authored opening location.

The city itself is static. It owns a set of permanent landmarks, including the
police station, civic center, old market, union depot, steelworks, and lake
marina. A case does not add city geometry: it contributes `[[city_locations]]`
labels which are placed on reserved sites in the existing city. These labels are
map destinations, distinct from the five investigative `[[locations]]` inside a
InteractiveStory mystery. Vale House is therefore authored level data, not a permanent city
landmark.

Each city landmark or reserved case site owns its city-side arrival position and
facing in `assets/city/landmarks.toml`. Each case city location names an authored
level marker for the corresponding level-side arrival; runtime entry has no
coordinate or facing fallback.

The current campaign format binds one `level_path` to each case, so it supports
one case-authored city label. Supporting several labels in one case requires a
future explicit label-to-level binding; the runtime must not make several labels
open the same level implicitly.

Documentation uses three specific terms:

- **Permanent landmark:** a runtime-owned destination in the static city.
- **Case city location:** a case-authored ID and label placed on a reserved city site.
- **Investigative location:** a connected room or reasoning space inside the case level.

The current implementation emphasis remains justified: tactile investigation,
player-authored deduction, reconstruction, and a dramatic reveal must feel good
before a large sharing surface is useful. Local packaging is the next product
boundary; hosted publishing and discovery can follow after creators can build,
validate, export, import, and replay complete mysteries reliably.

## Near-term product sequence

1. Keep `The Torn Appointment` as the end-to-end quality bar for play.
2. Complete the connected Build, Graph, mystery-authoring, validation, and
   playtest workflow.
3. Version the shared InteractiveStoryPackage manifest and validation contract.
4. Add local export, import, installed-mystery browsing, and compatibility
   diagnostics.
5. Prove the tools by creating and exchanging a second mystery.
6. Add hosted publishing and community discovery using the same package format
   when local creation and sharing are dependable.

## Success criteria

The product succeeds when a creator can make a mystery without editing engine
code, give it to another person as a file, and watch that person reach a fair,
engine-verified solution through investigation and reasoning.

The longer-term product succeeds when that same mystery can be published to a
community library without conversion, while local creation, ownership, and play
continue to work independently of the service.
