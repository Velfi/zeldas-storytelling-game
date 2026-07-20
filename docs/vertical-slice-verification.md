# The Torn Appointment — Vertical Slice Verification

This document records implementation and verification evidence for the playable spatial StoryCore vertical slice.

## Build and run

```sh
make run
make test
```

`make test` builds the Odin/Vulkan runtime and runs the named deterministic self-test suites. The current broad result is `359/359 StoryCore, house tool, level editor, city, vehicle, and GLB checks passed`.

## Controls

`The Torn Appointment` starts at the permanent Westhaven Police Station. Its
short tutorial records movement and camera input, then uses contextual
interaction to issue the Vale House briefing. Vale House is supplied by the
story's MysteryDomain city-label metadata and occupies a reserved site in the static
city; it is not hard-coded as a permanent landmark. Other cases bypass this
tutorial unless they explicitly author their own opening flow.

- Mouse: click floor space to move; click people and revealed points of interest to approach and interact. Entering a searchable room reveals its PoIs.
- Keyboard: WASD moves, Q shows the room hint for five seconds, B opens the dollhouse, N opens the notebook, E interacts, and Escape returns.
- Controller: left stick moves and navigates, right stick turns, South accepts/interacts, East returns, West runs Recreate, North opens the notebook, L3 shows the room hint for five seconds, R3 toggles first-person mode, and LB/RB select the previous or next workbench event.
- Driving: accelerate/brake/steer with movement controls, Space applies the handbrake, and E/South exits.

Every investigation action that spends time states its cost as `[-N TICK(S)]` before commitment. Non-spending controls do not call attention to their lack of cost.

## Major systems completed

- Static-city landmark registry plus validated case-authored map labels; the reference route is Police Station → Vale House.
- Interactive five-beat opening that teaches fact, claim, contradiction, and unresolved question through play.
- Twelve-tick investigation budget with four- and two-tick warnings and authored threshold reactions.
- Productive white-check failure that records a named lead and requires relevant evidence to reopen the approach. A last-tick essential failure enters restricted overtime: only that lead and the free retry remain available.
- Three tactile hero interactions: torn-appointment recovery and joining, study murder scene, and dinner-table alibi.
- Data-driven claims, dialogue approaches, evidence presentation, dispositions, topics, clue routes, and solution validation.
- Answer-independent room guidance that reports only whether a currently available lead remains in the present room.
- Five-tab notebook with claims, facts, chronology, people, and unresolved questions.
- Authored question map with substantiation states, reversible evidence arrangements, multi-deduction outcomes, explicit accusation, and physical, timeline, comparison, and confrontation demonstrations.
- Recreate playback of the exact event rail with clock progression, miniature travel, persistent weapon/body/shutter state, unsupported ghosts, and first-failure diagnostics.
- Five-act final reveal using the player's derived reconstruction, followed by five distinct outcomes and an optional canonical timeline.
- Original Kenney UI Audio OGG assets decoded directly through vendored `stb_vorbis`.
- Real GPU text atlases for ASCII, Latin, punctuation, arrows, and symbols.

## Airtight routes verified

The deterministic suite executes two differently ordered routes through the same public discovery/check resolution used by play:

1. Hypothesis-driven route: inspect Edgar for the desk key → unlock the study desk → ledger → Daniel → appointment stub → cane → clock → statuette → drag trace → Elsie → burned fragment. It reaches Airtight with at least two ticks remaining.
2. Broad-search route: clock → appointment stub → cane → gain Elsie's desk help → unlock the study desk → ledger → drag trace → statuette → Daniel → enter the service closet → cloth → Elsie → burned fragment. It reaches Airtight with at least one tick remaining.

Both routes establish the required motive, murder, cover-up, false-alibi, decisive-proof, and innocent-exclusion propositions rather than bypassing them with hidden outcome flags.

## Failure and outcome routes verified

- Failed essential check → named lead recorded; the fact remains undiscovered and the white check closes until the lead is pursued. At zero ticks, restricted overtime preserves only the lead and free retry.
- Failed Daniel Empathy → no automatic confession or fact award.
- Failed essential dialogue check → follow its recorded lead, then retry with relevant evidence.
- Missed theft evidence → Elsie's late threshold return.
- Correct culprit without decisive proof → Correct, But Unproven.
- Daniel accusation → Wrong Accusation.
- Exhausted ticks with an incomplete theory → Reveal Preparation without additional spending.
- Empty reconstruction → Case Unresolved.

The physical simulator additionally verifies backward chronology, impossible same-minute travel, missing event subjects, cleaning before attack, exterior crank operation, unsupported ghost events, and the decisive contradiction between Miriam's denial and the rejoined appointment.

## Play-and-revise passes

### Comprehension

Captured and reviewed the opening, Case Sense, a paid check, shutter interaction, study scene, and dinner-table interaction at the intended 1200×720 logical resolution. Revisions made during this pass:

- Standardized all paid controls on tick terminology.
- Removed explanations that called attention to non-spending actions.
- Confirmed important clues are presented as large manipulable targets rather than pixel hunts.

### Feel

Captured and reviewed dialogue, the complete workbench, mid-sequence Recreate, and failed-event Recreate. Revisions made during this pass:

- Added drag/drop event reordering and room placement with drop-zone highlighting.
- Added Undo/Redo and evidence-source inspection.
- Replaced obsolete shoulder behavior with LB/RB event selection.
- Made playback controls reflect whether the sequence is still running or has reached its failed event.

### Drama

Captured and reviewed Reveal Preparation, the shutter demonstration, and the Airtight result. Revisions made during this pass:

- Added persistent character blocking for authored glances and late-case reactions.
- Added explicit Recreate-tested state to reveal readiness.
- Preserved the player's five derived conclusions through the reveal and outcome.

Vulkan-native captures are written to `/private/tmp/chicago-vulkan-*.png`; the available capture flags are documented in the project README.

## Important implementation files

- `src/main.odin`: game state, interactions, workbench, UI, audio, self-tests, and flow.
- `src/domain.odin`: case validation, reconstruction simulation, diagnostics, and outcomes.
- `src/world.odin`: navigation, entities, dialogue approaches, searches, and character animation state.
- `src/vulkan_scene.odin`: 3D world and character rendering.
- `src/vulkan_backend.odin`: Vulkan UI, text atlases, and capture path.
- `assets/stories/mysteries/the_torn_appointment.story.toml`: unified core narrative and MysteryDomain content.
- `src/city.odin`: permanent city landmarks, reserved case-label sites, and tutorial travel routing.
- `assets/kenney_ui-audio/`: original CC0 OGG sound pack.

## Remaining prototype risks

- The 20–35 minute first-player target is supported by the twelve-tick route budget but still needs timing data from external first-time players.
- Character reactions use the available shared rig animations, blocking, props, and authored stage directions; bespoke facial animation is outside this slice's asset set.
- State persists while moving among investigation, notebook, and workbench screens, but there is no cross-process save file.
