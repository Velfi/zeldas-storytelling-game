# First-Case Tutorial System

## Goal

`The Torn Appointment` should teach the shared detective language while already
feeling like a case. The tutorial is not a checklist before the game begins. It
is a sequence of small mysteries in which the desired action is also the most
interesting thing in the scene.

The target experience is:

- a new player reaches Vale House in about four minutes;
- the first minute contains movement, camera, and contextual interaction;
- every new verb is introduced immediately before it is useful;
- the player independently completes one genuine observation-to-deduction loop;
- instruction retreats quickly when the player demonstrates fluency;
- no tutorial text reveals hidden truth or names the culprit;
- returning and experienced players can move at full speed without prompts
  becoming gates.

This system belongs to the first case, not to every mystery. Later cases may opt
into individual reminders, but do not replay the police-station sequence.

## Design rules

### Invite, observe, confirm

Each lesson has three beats:

1. **Invite:** composition, motion, sound, or character behavior creates a
   reason to act. A compact input prompt appears only if needed.
2. **Observe:** the runtime watches for the underlying player intent, not one
   exact input. Walking with keyboard, stick, or click-to-move can all prove
   movement fluency where those modes are available.
3. **Confirm:** the world responds first. A short UI acknowledgement follows,
   then disappears permanently for that lesson.

The tutorial never pauses for a text panel before a basic action. Instruction
appears beside the thing it describes and does not cover the play space.

### Teach one new idea at a time

A lesson may combine controls the player has already demonstrated, but exposes
only one new concept. Input glyphs always reflect the last active device and
change live between keyboard/mouse and controller families.

### Gates protect comprehension, not obedience

The only hard gate is receiving the case destination. Everything else is a soft
gate. The tutorial may teach how a control works, but never require a particular
clue, suspect, hypothesis, or deduction. If the player performs the desired
interface action early, the lesson silently completes.

### Teach operations, never conclusions

Tutorial guidance may answer **How do I do the thing I have chosen?** It must
not answer **What should I investigate?**, **Which facts belong together?**, or
**What does the evidence mean?**

The runtime must not use hidden solution data, accepted demonstration inputs, or
authored relevance tags to choose prompts, highlights, filters, ordering, or
hints. A player-facing affordance is valid only if it would behave the same way
in a case with a different culprit and solution.

### The world is the teacher

Prefer these signals, in order:

1. character gaze, pose, and movement;
2. lighting, framing, and a single authored point of contrast;
3. diegetic sound;
4. contextual action label;
5. a short coach line;
6. an explicit help card after repeated difficulty.

Do not use glowing trails, omniscient objective arrows, or flashing every
interactive object. Case Sense remains a player-invoked investigative aid, not
the default visual language.

Its compact HUD status makes room completeness legible: **MORE TO LEARN HERE**
or **NOTHING TO SEE HERE**. Activating it expands only that room-level
message. It never names a source, action, destination, relationship, or
conclusion. “Exhausted” means nothing is available with the player's current
knowledge; a later discovery may reopen the room.

## The teaching arc

| Beat | Player desire | New concept | Success signal | Recovery |
|---|---|---|---|---|
| 1. Locker room threshold | Find where to report | Move | Leave the marked threshold | After 4 s, show Move glyphs; after 12 s, pulse the doorway light |
| 2. Front-desk turn | Locate the desk sergeant | Camera/look | Bring the sergeant into the central view | After 5 s, show Look glyph; camera never snaps automatically |
| 3. Briefing | Receive the assignment | Contextual interaction | Activate the sergeant/front desk | Sergeant calls once; prompt expands after 8 s |
| 4. Motor pool | Get to the scene | Enter/exit vehicle and map landmark | Enter the nearby police car or choose assisted travel | Walking to Vale House remains valid; assisted travel appears after 20 s |
| 5. Vale House gate | Understand the immediate situation | Click-to-move or direct movement | Approach the constable/victim marker | Constable waves and repeats a spatial, not mechanical, direction |
| 6. First chosen inspection | Inspect anything that catches the player's attention | Revealed PoI and examination controls | Complete any examination | If the player attempts an interaction incorrectly, explain the control only |
| 7. First chosen conversation | Question a household member | Conversation and claims | Record any claim | Explain free versus costly actions when the choice first matters |
| 8. Notebook echo | See what the game retained | Notebook navigation | Open any newly recorded entry | A small “Recorded in Notebook” toast is selectable; no entry is privileged |
| 9. Independent investigation | Pursue a lead | No new tutorial concept | Discover freely | No spatial, relevance, or solution nudges |
| 10. First board visit | Express the player's own idea | Evidence placement and free testing | Attempt any authored question | Explain slot types and test feedback, never recommend evidence |
| 11. Release | Continue the investigation | Independent reasoning | Close the board | Interface reminders remain available on request |

The hoped-for first complete learning loop may be:

```text
Miriam denies that Edgar summoned her
→ the notebook records her statement
→ the player recovers Edgar's torn 8:20 memo stub
→ the burned fragment supplies the complementary text and torn edge
→ the board rejoins the note and tests it against her statement
→ the player earns a real deduction
```

But the tutorial neither presents nor names that route. A player may instead
begin with the watch, cane, desk, cloth, another statement, or another question.
All are legitimate. There is no disposable “practice evidence,” and completing
a tutorial lesson is never contingent on finding solution-critical evidence.

## Opening direction

The police station begins with the detective just inside a locker-room door.
The front desk is not initially on camera. A warm desk lamp, radio chatter, and
the sergeant's body orientation pull the player around the corner. Once the
player looks toward the desk, the sergeant looks up and says:

> Lieutenant. When you're ready.

The contextual label reads **Receive briefing**, not **Press E to interact**.
The current input glyph sits beside the verb. On activation:

> Vale House. Edgar Vale, found in the moon garden. The family is holding in
> the dining room. Take a car, or I can send you straight there.

The map acquires **Vale House** during the line. Control is never removed for a
separate tutorial card.

At the motor pool, the nearest police car unlocks and flashes its lights once.
The prompt says **Drive to Vale House**. Players who do not want the driving
lesson can choose **Ride with patrol** from the same interaction after a short
delay. This is framed as an in-world choice, not “skip tutorial.”

## Vale House onboarding

Arrival is quiet and authored for contrast with the city. A constable beside
the garden gate says:

> Lieutenant. Scene's being held. The household is inside when you're ready.

This establishes the available spaces without interpreting evidence or ranking
leads. Nearby PoIs remain naturally visible and none receives tutorial-only
salience.

Completing any first examination produces a restrained confirmation:

- the close inspection establishes whatever observation that object authors;
- a brief evidence sound plays;
- a corner toast says **Observation recorded · Open Notebook**.

The toast can be activated directly. If ignored, it shrinks to a notebook pip.
It never blocks movement.

Conversations retain their normal authored topic hierarchy. The tutorial does
not enlarge, reorder, or highlight a topic because it leads toward an accepted
deduction. It only explains the common visual distinction between a free topic
and an action that spends investigation time.

When the player encounters the crank, its ordinary contextual label remains
**Operate storm shutter**. The movement and sound of the slats make the result
legible without a tutorial caption. The game does not instruct the player to
return to a particular window or announce that a related question is ready.

On the first board visit, a neutral coach mark labels the available evidence,
slot types, and free **Test** action. The evidence remains complete and in its
normal order. It is never filtered by accepted answers. On a failed test, items stay where the
player put them and feedback describes only formal incompatibility—such as
**This slot accepts statements**—or the general distinction between
unsupported and contradicted. It does not say which statement, observation, or
question the player should choose.

## Adaptive assistance

Each lesson has four assistance levels:

| Level | Behavior |
|---|---|
| 0 — Invisible | The player acts before instruction; record mastery and show only world response |
| 1 — Prompt | Show the localized verb and current-device glyph near its target |
| 2 — Nudge | Add one authored character line or environmental pulse after inactivity |
| 3 — Help | Offer a concise explanation of the current control or screen |

Escalation is based on meaningful inactivity, not wall-clock time alone. Time in
menus, accessibility settings, dialogue reading, or active exploration does not
count as being stuck. Repeated invalid inputs and returning to the same unresolved
location do count.

Assistance de-escalates immediately after success. Once the player demonstrates
a verb twice without help, future reminders for that verb begin at level 0.
Help never names a lead, marks an investigative destination, filters evidence,
solves placement, or selects an answer.

### Optional help language

Hints describe an action at levels 1–2 and a goal at level 3:

- **Look toward the front desk**
- **Speak with the desk sergeant**
- **Open the board to arrange evidence around a question**

Avoid judgmental copy such as “Wrong,” “You forgot,” or “Obviously.” Failed
reasoning should distinguish incompatible evidence from insufficient evidence.

## Returning players and skip behavior

The campaign profile stores tutorial mastery by capability, not by button:

```text
move, look, contextual_interaction, travel, inspect, converse,
notebook, case_sense, board_place, board_test
```

On a replay, the station briefing is immediately available. A player can walk
straight to it, enter a car, or choose the patrol ride. Completed capability
lessons do not display proactive prompts, but contextual labels remain.

The Options menu includes **Guidance: Full / Adaptive / Minimal**:

- **Full** begins lessons at level 1 and escalates sooner;
- **Adaptive** uses demonstrated mastery and is the default;
- **Minimal** shows only contextual labels and explicit Help requests.

This setting affects teaching presentation, never case difficulty, action cost,
evidence availability, or the solution contract.

## Presentation specification

- Only one teaching prompt may be primary at a time.
- Primary prompts occupy a stable lower-center safe area; contextual labels stay
  attached to their target.
- Prompts use a verb first and one line maximum: **Open Notebook**, not a control
  manual sentence.
- Input glyphs come from the existing prompt system and hot-swap without replaying
  animations or sounds.
- A new prompt fades in after 250 ms of device stability to avoid flicker.
- Completion uses a soft chime and 180–250 ms accent, never a victory fanfare.
- Tutorial motion, color, and sound each have redundant non-sensory equivalents.
- All coach lines and labels use the normal localization path.
- Pausing freezes timers. Subtitles remain on for tutorial-critical spoken lines
  even if general subtitles are disabled, with a setting to suppress speech and
  retain equivalent text.

## Runtime model

Replace the case-specific integer `tutorial_step` with data-driven lessons and a
small capability ledger. The case opts into an authored tutorial sequence; the
shared runtime owns evaluation and presentation.

```text
Tutorial_Lesson
  id
  capability
  prerequisites[]
  completion_event
  target_id?             // control, current interaction, or UI surface
  prompt
  nudge?
  help?
  prompt_delay
  nudge_delay
  help_delay
  blocking               // exceptional; briefing only
  complete_if_already_true
```

Completion events should be semantic:

```text
player_moved(distance)
camera_framed(target, duration)
interaction_completed(target)
knowledge_discovered(id)
screen_opened(kind)
demonstration_resolved(id)
```

They must not be raw key presses. This supports rebinding, mouse, controller,
touch-like click movement, accessibility assists, and future input devices.

Tutorial state lives in player progress, outside the playable package:

```text
Tutorial_Progress
  completed_lessons: set<string>
  capability_mastery: map<capability, 0..2>
  guidance_mode
  requested_help_count
```

Case source contains presentation and sequencing but cannot mutate global
mastery directly. The runtime promotes mastery only after observed success.

## Instrumentation and quality bar

Record anonymous local playtest events with timestamps and no hidden solution
data:

- lesson invited, assistance level shown, completed, bypassed, or abandoned;
- active device family and device switches;
- time spent meaningfully stuck;
- invalid activations near the intended target;
- first notebook open, first board open, first failed test, first resolved test;
- whether the station-to-house trip was driven, walked, or assisted;
- guidance mode and explicit Help requests.

The tutorial is ready when observed first-time players meet all of these:

- 90% reach the briefing without verbal help in 90 seconds;
- 90% reach Vale House within five minutes;
- 85% inspect evidence and open the notebook without external help;
- 80% resolve the first board question with at most one failed test;
- no player believes Case Sense automatically identifies relevant truth;
- no player believes every visible clue must be collected;
- experienced players can reach unrestricted investigation in under two minutes;
- keyboard/mouse, Xbox, PlayStation, and Switch-style controllers all complete
  the sequence with no device-specific text leakage.

## Implementation slices

### Slice 1 — Better station tutorial

Introduce semantic lessons, active-device prompts, adaptive delay, early-action
completion, briefing unlock, and the patrol-ride option. Preserve current city
geometry and travel behavior.

### Slice 2 — Investigation onboarding

Author the neutral arrival, first-discovery notebook toast, and first-use
explanations that accept any examined object or recorded claim. Add capability
persistence and Guidance settings.

### Slice 3 — First deduction

Teach evidence navigation, typed slots, placement, and free testing on the
first question the player chooses. Add answer-independent syntax feedback, then
release the player into the full case.

### Slice 4 — Polish and validation

Add accessibility equivalents, local instrumentation, deterministic tutorial
self-tests, capture scenarios for each assistance level and input family, and
observed playtest passes against the quality bar.

## Non-goals

- teaching every advanced dialogue check before it matters;
- forcing the player to drive;
- explaining the whole action economy at arrival;
- making Case Sense mandatory;
- creating fake evidence or a separate tutorial mystery;
- using tutorial completion as evidence that the player solved the case;
- allowing authored hints to inspect or expose hidden truth flags.
- highlighting, sorting, or filtering knowledge using accepted answer data;
- telling the player which lead, room, person, or question to pursue next.
