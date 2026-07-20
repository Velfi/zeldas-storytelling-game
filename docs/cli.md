# Command-line reference

This page documents the game executable's developer and automation flags. Run
commands from the repository root after `make build`.

## Launch modes

```sh
build/chicago                 # normal game launch
build/chicago --city-preview  # start in the city exterior
build/chicago --world-preview # start in the case world
```

Use `--aa=off`, `--aa=2x`, `--aa=4x`, or `--aa=fxaa` for a one-run
anti-aliasing override. The in-game Options selection remains the persistent
setting.

## Screenshot captures

Every `--capture-*` command renders a deterministic Vulkan frame and exits.
Captures default to `/private/tmp/chicago-vulkan-<name>.png`; override the path
with `--capture-output=<path>`. Capture windows are non-focusable, so automated
runs do not take keyboard focus from the application currently in use.

### General UI and game states

- Startup: `--capture-title`, `--capture-theme-knoll`,
  `--capture-theme-knoll-details`, `--capture-introduction`, `--capture-options`
- World: `--capture-city`, `--capture-driving`, `--capture-world`,
  `--capture-case-sense`, `--capture-study`, `--capture-dinner`,
  `--capture-shutter`, `--capture-shutter-motion`
- Investigation UI: `--capture-notebook`, `--capture-objectives`,
  `--capture-board`, `--capture-board-complete`, `--capture-recreate`,
  `--capture-recreate-motion`, `--capture-cover-up-recreate`,
  `--capture-alibi-recreate`, `--capture-proof-recreate`,
  `--capture-reveal-prep`, `--capture-reveal`, `--capture-final-demo`,
  `--capture-result`, `--capture-result-airtight`, `--capture-diagnostics`
- Checks: `--capture-check`, `--capture-check-success`,
  `--capture-check-overtime`, `--capture-disposition-tooltip`,
  `--capture-disposition-tooltip-neutral`

### Dialogue

- States: `--capture-dialogue`, `--capture-dialogue-history`,
  `--capture-dialogue-history-oldest`, `--capture-dialogue-long-response`,
  `--capture-dialogue-notebook`, `--capture-dialogue-object`,
  `--capture-dialogue-object-acquired`, `--capture-dialogue-object-locked`,
  `--capture-dialogue-object-description`
- Evidence: `--capture-dialogue-evidence`,
  `--capture-dialogue-evidence-presented`,
  `--capture-dialogue-evidence-presented-history`,
  `--capture-dialogue-evidence-only`
- Checks: `--capture-dialogue-check`, `--capture-dialogue-check-success`,
  `--capture-dialogue-check-failure`,
  `--capture-dialogue-check-return-success`,
  `--capture-dialogue-check-return-failure`
- Input presentation: `--capture-dialogue-keyboard-shortcuts`,
  `--capture-dialogue-mouse-hover`, `--capture-dialogue-gamepad-focus`,
  `--capture-dialogue-playstation-focus`

### Context prompts

`--capture-context-idle`, `--capture-context-person`,
`--capture-context-evidence`, `--capture-context-door`,
`--capture-context-locked`, `--capture-context-multiple`,
`--capture-context-xbox`, `--capture-context-playstation`,
`--capture-context-switch`, `--capture-context-orbit`,
`--capture-context-landmark`, and `--capture-context-vehicle`.

### Build Mode

- Catalog and placement: `--capture-build`, `--capture-build-catalog`,
  `--capture-build-placement`, `--capture-build-selection`,
  `--capture-build-object-selected`, `--capture-build-drag`
- Materials and terrain: `--capture-build-materials`,
  `--capture-build-wall-paint`, `--capture-build-eyedropper`,
  `--capture-build-terrain`, `--capture-build-foundation`,
  `--capture-build-foundation-polygon`, `--capture-build-foundation-shell`,
  `--capture-build-path`, `--capture-build-water`
- Architecture: `--capture-build-opening`,
  `--capture-build-window-selected`, `--capture-build-window-drag`,
  `--capture-build-room-draw`, `--capture-build-room-rectangle`,
  `--capture-build-room-split`, `--capture-build-room-merge`,
  `--capture-build-roof`, `--capture-build-mansard`,
  `--capture-roof-overhead`, `--capture-build-stairs`
- Diagnostics: `--capture-build-markers`, `--capture-build-diagnostics`,
  `--capture-build-playtest`, `--capture-build-room-measures`,
  `--capture-build-navmesh`, `--capture-build-lighting`,
  `--capture-build-stories`

### Graph Mode

- General states: `--capture-graph`, `--capture-graph-script`,
  `--capture-graph-localization`, `--capture-graph-diagnostics`,
  `--capture-graph-inspector-edit`, `--capture-graph-quick-add`,
  `--capture-graph-edge-drag`, `--capture-graph-edge-selection`,
  `--capture-graph-paste`, `--capture-graph-debugger`,
  `--capture-graph-choice`, `--capture-graph-conditions`,
  `--capture-graph-effects`, `--capture-graph-help`
- Routing fixtures: `--capture-graph-routing-board`,
  `--capture-graph-routing-crossings`,
  `--capture-graph-routing-direct-hover`,
  `--capture-graph-routing-obstacle-hover`,
  `--capture-graph-routing-back-hover`,
  `--capture-graph-routing-crossing-hover`,
  `--capture-graph-routing-parallel-hover`,
  `--capture-graph-routing-zoomed-hover`
- Navigation fixtures: `--capture-graph-minimap-stress`

### Campaign and story authoring

- Campaign tabs: `--capture-campaign-authoring-overview`,
  `--capture-campaign-authoring-cases`, `--capture-campaign-authoring-variables`,
  `--capture-campaign-authoring-conditions`, `--capture-campaign-authoring-effects`,
  `--capture-campaign-authoring-simulation`, and
  `--capture-campaign-authoring-diagnostics`.
- Story tabs: `--capture-story-authoring-project`,
  `--capture-story-authoring-story-data`, `--capture-story-authoring-mystery`,
  `--capture-story-authoring-diagnostics`, `--capture-story-authoring-assets`,
  `--capture-story-authoring-packages`, and `--capture-story-authoring-library`.

## Graph semantic round-trip

Verify that Graph Mode can import and rebuild a story without changing its
compiled semantic identity:

```sh
build/chicago --graph-roundtrip-story assets/stories/mysteries/the_torn_appointment.story.toml
```

## Capture camera and visibility

House and editor captures accept an exact right-handed, Y-up camera pose. Pass
the eye and target as comma-separated `x,y,z` values:

```sh
build/chicago --capture-world \
  --camera-position=36,10,14 \
  --camera-look-at=30,0,14 \
  --hide-roofs \
  --capture-output=/private/tmp/miriam-room.png
```

The camera flags override only the view. The selected capture still determines
scene state, UI, wall cutaways, weather, and other staging.

- `--hide-roofs` suppresses roof geometry without changing level data.
- `--walls=up` forces full-height walls.
- `--walls=cutaway` forces lowered walls and hidden roofs.
- `--walls=auto` uses the automatic camera-relative cutaway.
- `--cutaway=<0..1>` sets an exact partial transition.
- `--walls=down` aliases `cutaway`; `--walls=full` aliases `up`.

Do not combine `--walls` with `--cutaway`.

## Capture helpers

```sh
make theme-knoll-screenshot
make catalog-thumbnails
```

The first command stitches both theme-knoll pages into
`build/theme-knoll-full.png`. The second rebuilds all deterministic catalog
cards; pass selected IDs directly to `tools/bake_catalog_thumbnails.sh` to
refresh individual assets.
