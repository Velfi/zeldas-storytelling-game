> Historical planning record. References to the former case runtime below describe the pre-StoryCore implementation and are retained only as migration history. Current architecture is documented in `spatial-story-architecture.md`.

Continue working autonomously overnight to turn the existing murder-mystery prototype and `The Torn Appointment` into a polished, playful, Nintendo-like vertical slice.

Do not stop after an audit, plan, partial implementation, or status report. Repeatedly inspect, implement, build, test, launch, play, visually review, simplify, and polish while useful in-scope work remains.

Preserve unrelated user changes. Follow the repository’s existing architecture and conventions. Do not replace working systems, introduce a second framework, or perform broad unrelated refactors.

# Product goal

Create a delightful 20–35 minute detective game built around this loop:

```text
Notice an irregularity
→ investigate it physically
→ receive an evidence or fact block
→ place it into a partial murder theory
→ press Recreate
→ watch the dollhouse accept or reject the theory
→ form the next investigative question
→ perform the completed theory as a dramatic final reveal
````

The player investigates `The Torn Appointment` with twelve clock ticks representing limited investigation actions.

They must determine:

* Why Edgar was murdered
* When he died
* Where he died
* What killed him
* How his body reached the garden
* How the apparent fall was staged
* Why Miriam’s alibi is false
* Why Daniel lied
* Why Elsie lied
* Why Miriam’s claimed sighting was impossible
* Why the murderer had to be Miriam

A correct guess is not enough. The player wins by constructing and performing a coherent, supported, exclusive explanation.

The shared city is static. Permanent landmarks belong to the runtime; cases may
add named map destinations as labels without adding city geometry. This
reference case begins at the permanent Westhaven Police Station, teaches the
basic controls there, and then sends the player to its case-authored `Vale
House` city label. The five locations listed below are investigative spaces
inside Vale House, not five separate city destinations. Other cases are not
required to start at the police station.

# Quality hierarchy

Prioritize work in this order:

1. Torn-appointment recovery and magnetic assembly
2. Evidence-block acquisition and contradiction testing
3. Recreate dollhouse playback
4. Study murder-scene interaction
5. Dinner-table alibi interaction
6. Expressive character dialogue approaches and reactions
7. Clue-route fairness and action economy
8. Supporting notebook, diagnostics, tests, and secondary polish

Do not expand secondary systems while a higher-priority interaction remains confusing, sluggish, visually weak, unreliable, or unpleasant.

Correctness is necessary but insufficient. This must feel like a tactile mystery toy, not case-management software.

# Begin with an implementation audit

Inspect:

* Repository architecture
* Build and run instructions
* Existing MurderScript implementation
* `The Torn Appointment` case data
* Investigation state and actions
* Investigation-clock economy
* Dialogue and skill checks
* Evidence, facts, claims, and conclusions
* Reconstruction/block editor
* Dollhouse or location presentation
* Recreate functionality
* Reveal evaluation
* Input systems
* Existing tests and diagnostics
* Screenshot or application-control tooling

Trace the complete data flow:

```text
MurderScript
→ canonical case model
→ investigation state
→ player actions
→ discovered evidence and propositions
→ unlocked blocks
→ player reconstruction
→ Recreate simulation
→ final reveal
→ outcome evaluation
```

Identify and fix:

* Disconnected or placeholder systems
* Hard-coded clue behavior that should use case data
* Display-string comparisons instead of stable IDs
* Canonical truth leaking into player UI
* Silent action failures
* Duplicate action costs
* Unwinnable clue routes
* Random checks required for essential progress
* Confusing or redundant screens
* Poor controller navigation
* Weak visual feedback
* Reconstruction that validates only textually
* Reveal sequences that ignore the player’s actual theory

Extend working systems instead of creating parallel replacements.

# Core case structure

Use exactly:

* One victim: Edgar Vale
* Culprit: Miriam Vale
* Innocent suspect: Daniel Cross
* Innocent suspect: Elsie Ward
* Five investigative locations inside Vale House
* Twelve investigation-clock ticks
* One true murder scene
* One staged discovery scene
* One cleaned murder weapon
* One false alibi
* One unrelated affair
* One unrelated theft
* One decisive contradiction built from two matching note fragments

Canonical truth:

* Edgar discovered Miriam’s embezzlement.
* Edgar left dinner and entered the study.
* Miriam answered his 8:20 summons to bring the account books.
* Miriam killed Edgar at approximately 8:24 with the bronze statuette.
* She cleaned the statuette with lamp oil.
* The storm shutter was already closed by 8:15.
* She moved Edgar’s body through the study terrace door into the garden.
* She staged the body beneath the shuttered window with Edgar’s cane.
* In her sitting room, she tried to burn her half of the summons and hid the surviving fragment in the metal wastebin.
* She returned to dinner after completing the cover-up.
* Daniel falsely supported her alibi to conceal their affair.
* Daniel did not witness or assist the murder; his lie concealed the affair and their absences from dinner.
* Elsie lied about entering the study to conceal an earlier theft.
* Miriam denied receiving Edgar’s summons to the study.
* Edgar’s memo stub names Miriam, the study, and 8:20, but its lower half is missing.
* The burned fragment from Miriam’s wastebin preserves the complementary text and torn edge.

Keep this canonical truth inaccessible to normal player-facing systems until the post-case explanation.

# Case phases

Implement or complete explicit phases:

```text
Introduction
Investigation
RevealPreparation
FinalReveal
CaseResult
```

## Introduction

Teach through a short authored interaction:

1. At Westhaven Police Station, the player demonstrates movement and camera control.
2. The player interacts with the station briefing point.
3. The case-authored `Vale House` city label becomes the destination.
4. At Vale House, the player examines Edgar.
5. Player manipulates his stopped watch.
6. Player receives `[Edgar died around 8:24]`.
7. The player receives Miriam’s denial that she received Edgar’s summons.
8. Edgar’s appointment stub appears as a related but incomplete fact.
9. The two blocks remain unresolved because the missing half of the note has not been found.
10. The unresolved question appears:
   `What completed Edgar’s appointment with Miriam?`
11. The dollhouse opens for free investigation.

Avoid a long tutorial page.

## Investigation

Track:

* Current investigative location within the active case level
* Remaining ticks
* Discovered hooks
* Evidence
* Established facts
* Claims
* Contradictions
* Conclusions
* Unresolved questions
* Dialogue topics
* Character dispositions
* Skill-check state
* Threshold events
* Player reconstruction
* Investigation history

Travel and ordinary conversation should be free.

Searches, examinations, protected dialogue topics, and special investigations consume their declared tick cost.

At four ticks remaining, warn gently.

At two ticks remaining, make the approaching reveal unmistakable.

At zero, finish the current action and enter reveal preparation.

Allow the player to end the investigation early after confirmation.

## Reveal preparation

Lock new investigation actions.

Allow unlimited:

* Evidence review
* Theory editing
* Recreate tests
* Accused-person selection
* Readiness review

## Final reveal

Use the player’s assembled program. Do not substitute a canned correct sequence.

## Case result

Support:

* Airtight solution
* Correct but unproven
* Incomplete theory
* Wrong accusation
* Unresolved case

Offer restart and post-case canonical reconstruction.

# Clue-discovery philosophy

Implement this rule:

“Clue locations are generous, investigative choices are meaningful, and conclusions belong to the player.”

Separate discovery into:

## Notice

Expose an obvious irregularity or investigative hook.

Examples:

* Disturbed rug
* Unusually clean statuette
* Resistant shutter crank
* A torn memo stub in Edgar’s writing pad
* Missing napkin
* Disturbed dinner setting

Do not require pixel hunting.

## Investigate

Let the player decide whether the hook deserves time.

Show the action, cost, and general intent before confirmation.

## Interpret

Award evidence and structured facts, not the complete solution.

The player must connect facts, claims, and conclusions through blocks.

# Clue tiers

Represent these tiers in case data and development diagnostics.

## Foundation clues

Reliably establish:

* Edgar died around 8:24.
* Edgar died in the study.
* The statuette was the weapon.
* The body was moved into the garden.

These require obvious guaranteed routes.

## Corroborating clues

Include:

* Miriam left dinner.
* Elsie saw Miriam enter the study shortly after the fish course.
* Daniel also left dinner.
* The statuette was cleaned with lamp oil.

## Decisive clues

Include:

* Edgar’s torn memo stub names Miriam, the study, and 8:20.
* The burned fragment in Miriam’s wastebin preserves the message’s remaining text and a complementary edge.
* Rejoining both pieces reconstructs Edgar’s summons.
* Miriam denied receiving or answering that summons.

Do not label clues as “essential” or “decisive” in normal player UI.

# Multiple discovery routes

Every required conclusion needs:

* One guaranteed but moderately expensive route
* One efficient hypothesis-driven route
* One social or skill-based alternative when appropriate

Implement and validate at least:

## Miriam left dinner

* Thoroughly examine the dinner table.
* Notice her disturbed place setting.
* Get Daniel to withdraw his alibi.
* Obtain Elsie’s sighting.

## Edgar died in the study

* Thoroughly search the study.
* Investigate the disturbed rug.
* Obtain relevant testimony from Elsie.

## Statuette was the weapon

* Perform a full forensic comparison.
* Match its base to the wound.
* Inspect blood trapped in its seam.

## Miriam answered Edgar’s summons

* Recover the memo stub from Edgar’s writing pad.
* Search Miriam’s wastebin for the burned fragment.
* Rejoin the matching torn edges.
* Confront Miriam with the completed appointment.

## Daniel lied to conceal the affair

* Find and present the love note.
* Use Empathy successfully.
* Break both dinner accounts, then pressure him.

## Elsie lied to conceal theft

* Inspect the empty cash box.
* Use Empathy successfully.
* Observe her attempting to return the money after the case advances.

Alternate routes must establish the same structured propositions.

# Broad-search safety net

Allow expensive guaranteed room searches.

Example:

```text
Search the Study Thoroughly
Cost: 2 ticks

Reveals:
- Disturbed rug
- Displaced statuette
- Recently used shutter mechanism
```

Broad searches reveal hooks, not their full interpretations.

Targeted hypothesis-driven investigation should be more efficient.

Never allow a completed broad search to consume additional ticks without a new possible result.

# Hypothesis-driven investigation

Let partial theories unlock targeted actions.

Examples:

* Edgar’s memo stub plus Miriam’s denial unlocks `Search for the missing fragment`.
* Finding the burned fragment unlocks `Join the appointment`.
* Study blood unlocks `Compare nearby objects with the wound`.
* Both dinner absences unlock a targeted Daniel dialogue.
* Evidence that Elsie entered the study unlocks questions about what she did there.

Store unlock requirements in MurderScript or reusable case rules where practical. Avoid scattered clue-specific UI conditionals.

When an action unlocks, explain the player’s reasoning:

```text
New action: Join the appointment fragments.

The burned edge and handwriting may complete Edgar’s torn memo.
```

# Unresolved questions

Guide with questions, not answers.

Track:

* When did Edgar die?
* Where did he die?
* What caused the wound?
* How did his body reach the garden?
* What completed Edgar’s appointment note?
* Why did Daniel support Miriam?
* Why did Elsie lie?
* Did Miriam receive and answer Edgar’s summons?

Update questions as evidence is established.

Show relevant people, places, and evidence without prescribing the winning action.

Do not expose implementation terms such as predicate, node, schema, contract, validator, or canonical state.

# Hero interaction 1: torn appointment

This is the most important interaction in the prototype. Fully polish it.

The player must be able to:

* Recover Edgar’s memo stub.
* Recover the burned fragment from Miriam’s wastebin.
* Rotate and align the two physical evidence blocks.
* Compare torn edges, handwriting, and the completed sentence.
* Join the fragments into one appointment.
* Place the completed appointment beside Miriam’s denial.
* Test the contradiction without being told the answer.

The interaction should communicate through animation before text.

Required feedback:

* Paper resistance and magnetic snap
* Legible torn edges and matching handwriting
* A restrained alignment sound before the decisive join
* The completed 8:20 summons
* Miriam’s denial visibly opposing the joined note
* Failed arrangement feedback that preserves the player’s layout
* Contradiction reveal
* Evidence-block reward
* Character or skill-helper reaction

The decisive proof should reuse this exact joined appointment during the finale.

The storm shutter remains an optional supporting interaction. The player may operate its interior crank, watch the slats move, and test the obstructed view. It teaches physical experimentation and spatial reconstruction, but it does not identify who operated it or replace the appointment contradiction.

# Hero interaction 2: study murder scene

Fully polish:

* Lift the disturbed rug.
* Reveal diluted blood underneath.
* Compare the wound against nearby objects.
* Manipulate the statuette.
* Match its base to the wound.
* Find lamp-oil residue.
* Reveal blood trapped inside its seam.
* Award separate weapon, location, and cleaning facts.

Keep the interaction compact. It should communicate one causal chain:

```text
Blood in study
→ statuette matches wound
→ statuette was cleaned
→ study was the true murder scene
```

# Hero interaction 3: dinner-table alibi

Fully polish:

* View the table and character positions.
* Place or remove character tokens.
* Inspect spilled wine and missing napkin.
* Compare claims against physical disturbances.
* Establish that Miriam and Daniel left.
* Visually crack the shared alibi.
* Preserve the question of why Daniel lied.

Do not automatically identify the murderer from the broken alibi.

# Other evidence interactions

Other clues may use simpler inspect-and-react sequences, but every highlighted object must produce at least one of:

* Evidence
* Relevant characterization
* A new question
* An alternate proof route
* Elimination of a possibility
* A useful complication

Remove meaningless interactable clutter.

# Detective skills

Implement or complete:

* Observation
* Analysis
* Empathy
* Pressure

Give each a short, distinct helper personality and visual identity.

Suggested presentation:

* Observation: curious magpie
* Analysis: clockwork owl
* Empathy: gentle hound
* Pressure: theatrical lion

Keep interventions short.

Examples:

```text
OWL:
Two times. One dead man. They cannot both stay on the board.

HOUND:
Daniel is protecting Miriam—but perhaps not from the murder.
```

## Productive failure

Every failed check must:

* Reveal a weaker observation
* Unlock a slower guaranteed action
* Expose a prerequisite
* Change character behavior
* Close one route while preserving another
* Create a useful complication
* Or add an unresolved question

Never consume a tick and show only `Failed`.

Examples:

* Failed Empathy with Daniel:

  * Daniel refuses disclosure.
  * His reaction unlocks searching for relationship evidence.

* Failed Pressure with Elsie:

  * Elsie becomes less cooperative.
  * She later attempts to return the stolen money.

Use deterministic seeded randomness. Displayed chances must match actual resolution.

Essential progress cannot depend solely on random success.

# Case progression events

Tie development to clock ticks spent.

After four ticks are spent:

* Daniel becomes visibly nervous.
* Miriam warns the household against speculation.
* The study’s deeper examination becomes available.
* Music or ambience gains a new layer.

After eight ticks are spent:

* Daniel may request a private conversation.
* Elsie may attempt to return the money if her secret remains concealed.
* Miriam watches the evidence more closely, reacting to the scorched fragment only if it has been found.
* Reveal warnings intensify.

Events must respond to current state. Do not play obsolete scenes.

# Typed murder-program blocks

Use chunky, physical, readable blocks rather than generic cards.

Support:

* Person
* Action
* Object
* Place
* Time
* Motive
* Claim
* Evidence
* Fact
* Contradiction
* Conclusion
* Connectors

Always-available grammar:

```text
ENTER
LEAVE
ATTACK
CLEAN
OPEN
MOVE
CLAIM
SEE
LIE
KNOW
BECAUSE
THEREFORE
SUPPORTED BY
BUT
```

Investigation unlocks specific nouns, times, facts, and claims.

Provide wildcards:

* Someone
* Unknown object
* Unknown place
* Unknown time
* Unknown motive

# Reconstruction structure

Use five large containers:

```text
MOTIVE
MURDER
COVER-UP
FALSE ALIBI
DECISIVE PROOF
```

Support statements such as:

```text
[Person] acted because [Motive]

[Person] attacked [Person]
with [Object]
in [Place]
at [Time]

[Person] cleaned [Object]
with [Object]

[Person] moved [Body]
from [Place]
to [Place]

[Person] claimed [Proposition]

[Claim] is contradicted by [Fact]

[Conclusion] is supported by [Evidence]

[Person] knew [Hidden fact]
even though [Blocking fact]
```

Allow:

* Adding
* Replacing
* Removing
* Reordering
* Inspecting sources
* Returning blocks to palette
* Clearing a section
* Undo/redo where supported
* Saving theory state
* Testing incomplete theories

Show only compatible blocks first when filling a socket.

# Block feel

Important blocks require:

* Idle animation
* Hover/focus response
* Pick-up animation
* Compatible-socket attraction
* Magnetic snap
* Incompatible rejection
* Speculative wobble
* Supported settling
* Proven lock
* Contradiction crack
* Removal animation
* Rewind behavior

Provide distinct sounds for:

* Evidence discovered
* Fact established
* Block picked up
* Compatible snap
* Invalid placement
* Contradiction created
* Theory run
* Timeline failure
* Clock tick spent
* Reveal section proven

Tune timing so common actions feel immediate.

# Recreate

`Recreate` is the central verb.

It must visibly simulate the player’s proposed sequence through the dollhouse.

It must not be merely a text validator with a decorative animation.

Show:

* Ghostly characters moving between rooms
* Proposed actions
* Object state changes
* Clock progression
* Shutter state
* Sightlines where the player has proposed a visibility claim
* Body movement
* Character-location conflicts
* Unsupported translucent events

Visual failure examples:

* A closed shutter blocks the view.
* A character arrives too late.
* Two copies collide when placed in incompatible locations.
* A locked mechanism stops an action.
* An unsupported event fades or floats loose.
* A contradictory sequence jams and rewinds.

After animation, show one concise diagnostic:

```text
Miriam cannot return to dinner before leaving the study.
```

Do not provide the correct replacement block.

# Reconstruction validation

Evaluate structured propositions rather than matching a single expected string.

Validate:

## Syntax

* Required sections exist.
* Required sockets are filled.
* Types are compatible.
* Connections are not dangling.

## Physical and temporal possibility

* Characters occupy possible locations.
* Travel time is sufficient.
* Event ordering works.
* Death time matches established evidence.
* Body movement follows the proposed murder location.
* Shutter operation requires the interior crank.

## Evidence support

* Claims are not used as proof of themselves.
* Speculation is visually distinct.
* Evidence supports the proposition receiving it.
* Contradicted claims are identified.

## Completeness

The theory explains:

* Motive
* Culprit
* Victim
* Weapon
* Time
* Murder location
* Cleaned weapon
* Moved body
* Staged fall
* False alibi
* Daniel’s affair
* Elsie’s theft
* Impossible sighting
* Miriam’s hidden knowledge

## Exclusivity

The theory establishes why:

* Daniel’s lie does not make him the murderer.
* Elsie’s lie does not make her the murderer.
* Only Miriam satisfies the complete sequence and decisive contradiction.

# Certainty states

Represent:

* Unknown
* Speculative
* Supported
* Proven
* Contradicted

Use animation, color, border, and motion consistently.

Do not imply that an attractive or completed-looking block is proven when it is speculative.

# Controller-first interaction

The entire case must be playable with:

| Input            | Function                     |
| ---------------- | ---------------------------- |
| Stick or D-pad   | Move focus                   |
| Confirm          | Interact, pick up, place     |
| Cancel           | Back, return block           |
| Shoulder buttons | Change room or board section |
| One face button  | Recreate                     |
| One face button  | Notebook/details             |

Do not require:

* Precise dragging
* Tiny socket selection
* More than two nested menus
* Reading tooltips to understand compatibility
* Pointer-only interaction
* Navigating through irrelevant controls

Never show more than three primary actions at once.

Test readability at couch distance and the intended resolution.

# Character performance

Implement authored state-driven reactions.

## Miriam

* Calmly gives too much detail.
* Turns incriminating objects away from view.
* Looks toward Daniel when her alibi is challenged.
* Recovers quickly from ordinary pressure.
* Becomes genuinely unsettled by the rejoined appointment.
* Does not confess merely because accused.

## Daniel

* Supports Miriam too quickly.
* Looks toward her before answering.
* Responds better to Empathy than Pressure.
* Becomes relieved when the affair is separated from murder.
* Admits hearing the impact without knowing what caused it.

## Elsie

* Straightens nearby objects while lying.
* Fears that the theft makes her look guilty.
* Becomes useful after the theft is distinguished from murder.
* Reacts strongly when Miriam is placed in the study.
* May attempt to return the cash after eight ticks are spent.

Prefer gestures, glances, pauses, and props plus one concise line over explanatory paragraphs.

# Intermediate “aha” rewards

Recognize:

* True time of death
* True murder location
* Murder weapon
* Body was moved
* Daniel’s alibi broken
* Elsie’s theft explained
* Miriam’s summons denial disproven

For each major deduction:

* Lock relevant blocks
* Play a short reconstruction
* Add a musical or audiovisual layer
* Resolve one question
* Let a helper or character react briefly

Reserve the strongest payoff for joining the appointment and presenting it against Miriam’s denial in the final reveal.

# Final reveal

Transform the dining room into a small theatrical stage.

Present five acts:

1. Motive
2. Murder
3. Cover-up
4. False alibi
5. Decisive proof

For each act:

1. Show the player’s actual blocks.
2. Translate them into concise detective dialogue.
3. Recreate them through the dollhouse.
4. Let suspects challenge weak steps.
5. Let the player present already-discovered evidence.
6. Mark the act accepted, weak, contradicted, or missing.

Do not depend on random checks.

## Decisive demonstration

The player must:

1. Recover Edgar’s torn memo stub.
2. Recover the burned fragment from Miriam’s wastebin.
3. Rejoin the matching paper edges.
4. Establish that Edgar summoned Miriam to the study at 8:20.
5. Present the completed appointment beside Miriam’s denial.
6. Use the shutter experiment as supporting reconstruction evidence, not as a substitute for the contradiction.

An airtight argument wins without a confession.

# Outcome evaluation

## Airtight

Requires:

* Miriam accused
* Correct motive
* Correct murder sequence
* Correct cover-up
* False alibi explained
* Daniel and Elsie excluded
* Decisive appointment proof complete
* Essential claims supported
* No fatal contradiction

## Correct but unproven

* Miriam accused
* Core reconstruction substantially correct
* Decisive proof absent or inadequate

## Incomplete

* Miriam accused
* Major causal sections missing or contradicted

## Wrong accusation

* Daniel or Elsie accused

## Unresolved

* No coherent accusation completed

Afterward show:

* Correct conclusions
* Unsupported conclusions
* Contradicted conclusions
* Unexplained evidence
* Suspects not excluded
* Decisive-proof status

Then offer the canonical reconstruction.

# Action-budget tuning

Tune the case so:

* Efficient route: approximately 9–10 ticks
* Typical first-time winning route: 11–12
* Two or three inefficient decisions remain recoverable
* No single failed check makes an airtight solution impossible
* Broad searches alone cannot obtain and interpret everything
* At least two distinct airtight routes exist

Display costs before confirmation.

# Simplification pass

After the full loop works, perform a dedicated deletion and consolidation pass.

Remove or combine:

* Redundant screens
* Duplicate notebook information
* Low-value actions
* Repeated explanations
* Excessive navigation steps
* Meaningless objects
* Interactions that do not change knowledge, theory, character state, or tension
* Developer language in player UI

Prefer animation plus one clear sentence over a paragraph.

# Development diagnostics

Provide development-only inspection for:

* Canonical timeline
* Character knowledge
* Claims and protected secrets
* Discovered state
* Clue tiers
* Discovery routes
* Route costs
* Guaranteed fallbacks
* Player theory
* Validation diagnostics
* Outcome reasoning

Add a clue-route report containing:

* Required conclusion
* All routes
* Route cost
* Prerequisites
* Whether randomness is involved
* Guaranteed fallback
* Earliest availability
* Whether permanently missable

Warn or reject when:

* A required conclusion lacks a guaranteed route.
* Essential progress depends solely on randomness.
* A winning route exceeds twelve ticks.
* One failure eliminates all winning routes.
* A broad search directly awards a final conclusion.
* A highlighted hook has no meaningful result.
* A repeatable action can waste ticks without state change.
* An innocent suspect satisfies the complete solution.

# Automated tests

Follow repository conventions.

Cover:

* MurderScript parsing
* Reference validation
* No canonical-truth leakage
* Phase transitions
* Tick accounting
* Duplicate-action prevention
* Hook discovery
* Broad-search fallback
* Targeted-action unlocking
* Multiple routes to the same proposition
* Productive check failures
* White-check reopening
* Red-check expiration
* Deterministic randomness
* Threshold events
* Missed-clue alternatives
* Typed block compatibility
* Theory persistence
* Syntax diagnostics
* Timeline diagnostics
* Evidence-support diagnostics
* Completeness diagnostics
* Exclusivity diagnostics
* Airtight outcome
* Correct-but-unproven outcome
* Incomplete outcome
* Wrong accusation
* Unresolved case
* Complete restart reset

Add scripted playthroughs for:

1. Efficient hypothesis-driven airtight solution.
2. Broad-search-heavy airtight solution.
3. Failed Empathy with Daniel, recovered through evidence.
4. Failed essential dialogue check, followed its recorded lead in restricted overtime, and reopened the check with relevant evidence.
5. Missed theft evidence, recovered through Elsie’s threshold event.
6. Correct culprit without decisive proof.
7. Wrong accusation against Daniel.
8. Exhausted ticks with incomplete theory.

# Experience targets

A fresh player should reasonably:

* Understand the investigation clock and tick costs within 30 seconds.
* Discover meaningful evidence within 90 seconds.
* Create their first contradiction within five minutes.
* Test a partial theory without extensive instruction.
* Recover from at least two inefficient decisions.
* Finish in 20–35 minutes.
* Understand why Daniel lied.
* Understand why Elsie lied.
* Personally demonstrate why Miriam’s sighting was impossible.
* Explain why the murderer had to be Miriam.

# Overnight iteration process

Perform at least three complete play-and-revise passes after the primary implementation works.

## Pass 1: comprehension

Focus on:

* Available actions
* Costs
* Evidence versus claims
* Block manipulation
* Unresolved questions
* Theory diagnostics
* Onboarding

Remove ambiguity and unnecessary explanation.

## Pass 2: feel

Focus on:

* Responsiveness
* Input latency
* Focus movement
* Snapping
* Animation timing
* Sound
* Camera behavior
* Transitions
* Recreate playback
* Controller usability

## Pass 3: drama

Focus on:

* Investigation-clock pacing
* Threshold events
* Character reactions
* Intermediate deductions
* Appointment-fragment reveal
* Final confrontation
* Ending clarity

For every pass:

1. Reset to a clean case state.
2. Play without development shortcuts.
3. Record friction and confusion.
4. Fix the highest-impact issues.
5. Replay affected sequences.
6. Capture screenshots of major states if tooling permits.
7. Run relevant tests afterward.

Continue with the next safest high-value improvement while useful work remains. Do not repeatedly rewrite stable code in pursuit of speculative perfection.

# Completion criteria

The work is complete when:

* The repository builds using its documented workflow.
* Relevant tests pass.
* A new player can understand the opening through interaction.
* Important clues do not require pixel hunting.
* Investigative choices meaningfully spend ticks.
* Failed checks remain productive.
* The three hero interactions feel tactile and clear.
* Blocks are satisfying and practical to manipulate.
* Recreate visibly runs the player’s theory.
* Partial theories produce useful feedback without answers.
* At least two airtight routes work within budget.
* The final reveal uses the player’s actual reconstruction.
* Guessing the culprit is distinguished from proving the murder.
* Controller navigation works where supported.
* Player-facing UI is free from developer terminology.
* Major visual, input, and state defects found during playtesting are fixed.

At the end, leave the repository in a building, tested state and report:

* Major systems completed
* Important files changed
* How to build and run
* Controls
* Two verified airtight routes
* Failure-recovery routes verified
* Automated test results
* Manual playthroughs completed
* Visual review performed
* Simplifications made
* Remaining prototype limitations and balance risks

Do not stop at a plan or list of remaining work. Implement, test, play, revise, and polish the highest-value in-scope work available before handing the repository back.
