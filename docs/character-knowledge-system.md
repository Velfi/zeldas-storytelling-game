# Character Knowledge System

## Purpose

The character knowledge system records which authored propositions each actor is
aware of, what stance the actor takes toward each proposition, and which
communications have occurred. Dialogue remains an authored graph. Knowledge is
state read and changed by dialogue and world interactions; it does not generate
dialogue or choose behavior.

The system must support the following mechanically distinct statements:

- an event is canonically true;
- Miriam believes that the event occurred;
- Miriam tells the detective that the event occurred;
- the detective has heard Miriam's statement;
- Miriam knows that the detective has been told.

These states must not be collapsed into one flag.

## Scope

Version 1 provides:

- globally authored propositions;
- per-actor awareness and belief stance;
- explicit state predicates and effects for Graph Mode;
- a communication ledger;
- deterministic initialization, mutation, save, load, and validation;
- creator-facing state inspection during playtest.

Version 1 does not provide:

- autonomous character decision-making;
- generated dialogue;
- automatic inference from one proposition to another;
- confidence scores, emotions, personality, or relationships;
- automatic rumor propagation;
- natural-language parsing;
- a general-purpose expression or scripting language.

## Terms

### Actor

An actor is an entity that can hold epistemic state. Every case character is an
actor. The detective is also an actor with the reserved ID `detective`.

### Proposition

A proposition is one stable, authored statement about the story world. It is
identified by ID rather than by its display text.

Examples:

```text
prop_edgar_arrived_before_nine
prop_window_broken_from_inside
prop_miriam_moved_letter
```

A proposition is not evidence and is not an utterance. Evidence may support a
proposition. A claim records that an actor uttered a proposition.

### Canonical truth

Canonical truth is the creator-authored status of a proposition in the actual
story world:

```text
true
false
undetermined
```

`undetermined` means the story does not commit to an answer. Canonical truth is
creator-only data and must not be exposed by ordinary player-facing APIs or UI.

### Awareness

An actor is aware of a proposition when it is present in that actor's epistemic
state. An actor cannot hold a belief stance toward an unrecognized proposition.

### Belief stance

An aware actor has exactly one stance:

```text
uncertain
believes
disbelieves
```

The stance describes the actor, not canonical truth. The engine must permit an
actor to believe a false proposition and disbelieve a true one.

### Communication

A communication records that one actor communicated one proposition to another
actor in an authored scene or interaction. Communication does not itself imply
that the recipient believes the proposition.

## Authored data

### Propositions

Propositions belong to case data:

```toml
[[propositions]]
id = "prop_window_broken_from_inside"
text = "The study window was broken from inside."
canonical_truth = "true"

[[propositions]]
id = "prop_edgar_arrived_after_nine"
text = "Edgar arrived after nine o'clock."
canonical_truth = "false"
```

Fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | stable ID | Runtime and cross-document identity |
| `text` | string | Creator-facing and optionally player-facing wording |
| `canonical_truth` | enum | `true`, `false`, or `undetermined` |

Canonical truth is required in Mystery Mode. A future general-story mode may
default it to `undetermined`.

### Initial epistemic state

Initial state is authored separately from character identity:

```toml
[[character_knowledge]]
character = "miriam"
proposition = "prop_window_broken_from_inside"
stance = "believes"

[[character_knowledge]]
character = "elsie"
proposition = "prop_edgar_arrived_after_nine"
stance = "uncertain"
```

Absence means the actor is unaware of the proposition. There is no explicit
`unaware` record.

Each `(character, proposition)` pair may appear at most once in initial data.

### Claims

The existing claim type should gain a proposition reference:

```toml
[[claims]]
id = "claim_miriam_edgar_arrived_late"
speaker = "miriam"
proposition = "prop_edgar_arrived_after_nine"
text = "Edgar did not arrive until after nine."
```

The proposition is the semantic content. `text` is the wording of this specific
utterance. Recording or discovering a claim establishes only that the utterance
was made. It does not establish canonical truth or the speaker's belief.

The author may deliberately create a lie by giving the speaker a `disbelieves`
stance toward the proposition they assert. The engine does not infer dishonesty
from this discrepancy; Mystery validation or authored deductions may inspect it.

## Runtime state

Runtime state contains:

```text
epistemic_entries[]
    actor_id
    proposition_id
    stance

communications[]
    sequence
    sender_id
    recipient_id
    proposition_id
    scene_id
    beat_id
```

An epistemic entry's existence represents awareness. Its stance is one of the
three belief stances.

`sequence` is a monotonically increasing runtime integer. It preserves the order
of communications without requiring story-world clock time.

The communication ledger is append-only during forward play. Rollback or
restoring a playtest snapshot restores the ledger with the rest of game state.
Repeated communications remain separate records because their scene and order
may matter.

## Predicates

Graph conditions use typed predicates. Every predicate returns a Boolean and has
no side effects.

```text
aware(actor, proposition)
unaware(actor, proposition)
believes(actor, proposition)
disbelieves(actor, proposition)
uncertain(actor, proposition)
communicated(sender, recipient, proposition)
communicated_in_scene(sender, recipient, proposition, scene)
```

Belief predicates return `false` when the actor is unaware. They never create an
entry.

Canonical truth is intentionally absent from ordinary Graph Mode predicates.
Creator-only validators and diagnostics may query it. This prevents a runtime
branch from accidentally revealing solution data through a player-facing path.

Conditions combine using the existing fixed groups:

```text
all of
any of
none of
```

Arbitrary expressions are not supported.

## Effects

Graph beats and world interactions may apply these typed effects:

```text
make_aware(actor, proposition)
set_belief(actor, proposition, stance)
communicate(sender, recipient, proposition, recipient_stance)
```

### `make_aware`

If no entry exists, create one with stance `uncertain`. If an entry already
exists, do nothing. The operation is idempotent.

### `set_belief`

Create the entry if necessary and set its stance to the supplied value. Repeating
the same operation has no additional effect. If several effects set the same
entry during one beat, effects execute in authored order and the final effect
wins.

### `communicate`

Append a communication record, make the recipient aware, and optionally set the
recipient's stance.

`recipient_stance` is one of:

```text
unchanged
uncertain
believes
disbelieves
```

`unchanged` means an existing stance is preserved; a previously unaware
recipient becomes `uncertain`.

Communication does not alter the sender's state. If the story requires the
sender to become aware that they communicated something, that awareness must
already exist or be authored as a separate effect.

There is no `forget` effect in version 1. Removing knowledge creates difficult
questions for dialogue history, claims, and validation and has no demonstrated
case requirement yet.

## Execution semantics

Effects execute only when their containing beat completes successfully.

- A Line applies effects after its text is acknowledged.
- A Choice applies effects from the selected branch only.
- A Check applies effects from the resolved branch only.
- A Stage applies effects when staging completes.
- An Interaction applies success or cancel effects from the completed result.
- An End applies effects before the scene closes.

If a beat is entered but not completed, it applies no effects. Saving and loading
must therefore restore either side of the completion boundary deterministically.

All effects in a completed beat are applied in document order as one story-state
transaction. Player-facing notifications are emitted after the transaction, so
UI cannot observe a partially applied beat.

## Example

Initial state:

```text
Miriam believes prop_window_broken_from_inside
Elsie is unaware of prop_window_broken_from_inside
Detective is unaware of prop_window_broken_from_inside
```

Miriam tells the detective:

```text
Line: "That window was broken from inside."
On complete:
    communicate(
        miriam,
        detective,
        prop_window_broken_from_inside,
        uncertain
    )
    unlock_claim(claim_miriam_window_broken_inside)
```

The detective later tells Elsie:

```text
Available when:
    aware(detective, prop_window_broken_from_inside)
    not communicated(detective, elsie, prop_window_broken_from_inside)

Choice: "Tell Elsie what Miriam said."
On complete:
    communicate(
        detective,
        elsie,
        prop_window_broken_from_inside,
        uncertain
    )
```

Elsie's later graph may branch on her state:

```text
If believes(elsie, prop_window_broken_from_inside):
    "Then the intruder story makes no sense."

If uncertain(elsie, prop_window_broken_from_inside):
    "Miriam told you that? I would not trust her account."

If unaware(elsie, prop_window_broken_from_inside):
    ordinary conversation path
```

Every line and transition remains authored.

## Graph Mode presentation

The node inspector adds typed entries to the existing sections:

```text
AVAILABLE WHEN
  Elsie / stance / believes / Window broken from inside

ON COMPLETE
  Communicate / Detective -> Elsie / Window broken from inside
  Recipient stance / uncertain
```

Pickers select actor and proposition IDs from case data. They do not accept raw
IDs when a referenced object is available.

During playtest, the state drawer shows an actor selector and a proposition
table:

| Proposition | Awareness | Stance | Last source |
| --- | --- | --- | --- |
| Window broken from inside | Aware | Uncertain | Detective, beat 14 |

Creator overrides may change awareness or stance in the playtest snapshot. They
must not mutate the case document or player save.

## Validation

Validation errors:

- duplicate proposition IDs;
- invalid canonical truth or stance value;
- unknown actor or proposition in initial state, predicates, or effects;
- duplicate initial `(actor, proposition)` entries;
- claim with an unknown proposition;
- `communicate` with an unknown sender or recipient;
- a creator-only canonical-truth predicate in a playable graph;
- a required knowledge state with no possible initial state or producing effect;
- a knowledge dependency cycle with no initially reachable entry point.

Validation warnings:

- proposition never read by a predicate, claim, deduction, or diagnostic;
- epistemic state written but never read;
- communication recorded but never read;
- actor claims a proposition while initially unaware of it;
- several effects set different stances for the same actor and proposition in
  one beat, even though their document order makes the result deterministic;
- mandatory scene requires a stance that is reachable only through an optional
  branch;
- a character's stance changes without an authored communication, observation,
  or interaction providing a visible reason.

The reachability validator operates conservatively. It proves that at least one
graph path can produce a required state; it does not attempt exhaustive theorem
proving over arbitrary combinations because the condition language is finite and
typed but may still have combinatorial branches.

## Persistence and packaging

Proposition definitions and initial character knowledge are immutable package
content. Epistemic entries, the communication ledger, and its next sequence
number are player progress and belong in the save file.

Save data references actors and propositions by stable ID. Loading fails with a
compatibility diagnostic if an installed content version no longer contains a
referenced ID. Content upgrades must provide an explicit migration when IDs are
renamed or removed.

The player-facing package contains canonical truth because it is required for
adjudication, but ordinary runtime APIs and screens keep it behind the same
creator-only boundary as solution data.

## Relationship to existing systems

Version 1 does not replace clues, claims, topics, or deductions.

- A clue may support one or more propositions.
- A claim references the proposition it asserts.
- A topic continues to control conversational organization and availability.
- A deduction may establish a proposition for the detective through an explicit
  `set_belief` or `make_aware` effect.
- Existing `requires_clues`, `requires_claims`, and `requires_topics` remain valid
  while typed epistemic predicates are introduced.

This permits incremental adoption. The Torn Appointment can add propositions
only where character-specific memory produces an observable difference; it does
not require translating every existing clue or dialogue gate immediately.

## Implementation boundary

The smallest implementation slice is:

1. Load and validate propositions and initial character knowledge.
2. Store per-actor epistemic entries in game state.
3. Implement `aware`, the three stance predicates, `make_aware`, and
   `set_belief`.
4. Expose those operations in Graph Mode and its playtest state drawer.
5. Add `communicate` and the communication ledger only when one authored scene
   transfers information between actors.
6. Add one Torn Appointment scene in which information given to a character
   changes a later authored response.

The feature is successful when the later response depends on shared character
state rather than on a bespoke flag, the validator can explain how that state is
reached, and save/load reproduces it exactly.
