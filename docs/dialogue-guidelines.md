# Dialogue Guidelines

Use these guidelines when authoring or reviewing spoken dialogue, dialogue
prompts, scene narration, and `mystery.dialogue` summaries.

## Let the player interpret

Present what a character says and what the player can observe. Do not use the
neutral narrative voice to certify a character's feelings, motives, honesty, or
dramatic function.

Avoid narration such as:

- “Her careful denial leaves no room for accident.”
- “He tries to turn the accusation into reasonable doubt.”
- “She resents the assumption hidden in the question.”
- “His answer reveals how fear organized the house.”
- “For the first time, precision traps her.”

Instead, show behavior:

- The character waits before answering.
- A hand stops, withdraws, tightens, or returns to a familiar task.
- The character repeats only part of the question.
- An object is straightened, folded, avoided, or left out of place.
- A glance moves toward a door, clock, witness, or piece of evidence.
- The answer changes the subject or substitutes a different word.

The observable detail should create room for several immediate interpretations.
The player decides whether it signals fear, calculation, grief, anger, habit, or
something else.

## Separate observation from conclusion

Neutral narration may report:

- visible movement, posture, expression, and timing;
- audible changes in pace, volume, or wording;
- the physical state of the room and its objects;
- words spoken in the player's presence.

Neutral narration should not declare that a character:

- lies, evades, manipulates, confesses, or tells the truth;
- feels guilty, afraid, ashamed, jealous, or relieved;
- protects another person or conceals a particular motive;
- becomes suspicious or proves another character innocent;
- gives the player an alibi, contradiction, or solution.

### Mark the presentation role

The conversation log distinguishes authored lines by role:

- character or detective speakers are **spoken dialogue**;
- `speaker = "narrator"` is an observable **action / observation**;
- a detective line with `ui = "thought"` is an internal **detective thought**;
- check nodes are presented as **skill checks**, separately from story lines.

Do not combine an action and a quotation in one story node when the distinction
matters to the player. Use consecutive narrator and character line nodes so the
log can label and color them independently. `mystery.dialogue.response` and
scene summaries are metadata records only: the player-facing log must never
render them in place of the beats the player actually experienced.

A character may make those judgments about another character. Such statements
remain that speaker's point of view, not confirmation from the game.

An earned deduction result may state the conclusion established by the evidence.
Before the player completes that deduction, prompts and dialogue should present
the facts without pre-solving their meaning.

## Use natural speech

People normally use contractions. Prefer forms such as “I'm,” “you're,”
“we've,” “I'd,” “didn't,” “can't,” and “won't” in ordinary conversation.

Keep an expanded form when it has a clear purpose:

- emphasis: “I did not open that door.”
- contrast: “She was there; I was not.”
- legalistic or rehearsed wording;
- ceremonial speech or a character-specific verbal habit;
- an exact statement that will later be tested as evidence.

Expanded forms should be conspicuous because the surrounding speech sounds
natural. If every character avoids contractions, deliberate precision no longer
stands out.

## Give each character a physical and verbal vocabulary

Character voice is more than word choice. Give recurring behavior meaning
without explaining that meaning.

- Let a controlling character align objects, restate questions, and choose exact
  nouns and times.
- Let a guarded professional smooth clothing, qualify claims, and invoke rules or
  distinctions.
- Let a working character continue a task, count concrete things, and organize
  memories around duties.

Do not attach an interpretive label after the behavior. “She aligns the knife
with the plate” is stronger than “She aligns the knife to regain control.”

Avoid giving every character the same polished aphorisms, sentence length,
metaphors, or level of self-knowledge. Under pressure, characters may repeat
themselves, answer incompletely, choose an imprecise word, or stop speaking.

## Keep the detective from doing the player's work

The detective may notice a concrete discrepancy, press a witness, or offer an
accusation. Prefer questions when the player has not yet established the answer.

Prefer:

> “Why didn't you tell me?”

Over:

> “You kept silent because seeing her meant admitting why you were there.”

Prefer:

> “And everyone reset their clocks?”

Over:

> “A punishment that looked like punctuality.”

During a confrontation or an earned deduction, the detective may assemble facts
the player has already demonstrated. Do not repeat that conclusion earlier in a
prompt, summary, or transition.

## Write summaries as records, not criticism

`mystery.dialogue.response` should summarize the exchange using observable
actions, quoted language, and facts added to the record. It should not explain
the scene's subtext to the player or to future agents.

Prefer:

> Miriam waits until the room is still, restates the question as whether Edgar
> sent for her tonight, and answers, “He did not.”

Over:

> Miriam carefully narrows the question, revealing a rehearsed denial designed
> to avoid the truth.

When a summary must remain concise, preserve the character's exact consequential
wording and the most legible physical beat. Omit commentary about what the beat
means.

## Pace complex sequences one beat at a time

Never preload a multi-character exchange into the visible transcript. Author a
complex sequence as a chain of short cinematic nodes and wait for player input
after each node.

- Put one spoken line or one compact physical action in each node.
- Reveal that node, retain earlier nodes in the conversation log, and show
  `Continue` before advancing.
- Split a long action into separate nodes when the order of movements matters.
- Stop using `Continue` when the player reaches a genuine response, check, or
  interaction; those controls become the pacing action instead.
- Do not auto-advance dialogue merely because its animation or voice playback
  has finished.

This keeps causality legible, lets portraits follow the current speaker, and
allows the player to set the reading pace.

## Review checklist

Before considering dialogue complete, check that:

- ordinary speech uses natural contractions;
- every expanded form earns its emphasis or evidentiary purpose;
- narration contains only observable details;
- summaries do not certify emotion, motive, honesty, guilt, or suspicion;
- prompts do not reveal conclusions the player has not earned;
- the detective asks rather than answers when interpretation remains open;
- character judgments remain attributable to the speaker;
- physical beats vary and belong to the character using them;
- complex exchanges reveal one action or spoken beat per confirmation;
- important evidentiary wording is identical everywhere it is quoted;
- deduction results interpret only facts the player has successfully combined;
- removing an explanatory clause makes the scene more intriguing, not less
  comprehensible.
