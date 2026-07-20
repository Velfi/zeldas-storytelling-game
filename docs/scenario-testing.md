# Scenario Testing

Chicago scenarios are deterministic, headless playthroughs over the real
dialogue runtime. They address narrative branches by stable scene and beat IDs
rather than screen coordinates.

Run every enabled scenario in a file:

```sh
build/chicago --scenario-test assets/scenarios/the_torn_appointment.toml
```

Run one named scenario:

```sh
build/chicago --scenario-test assets/scenarios/the_torn_appointment.toml desk_key_recovery
```

The root document declares its case, graph, and level. Each `[[scenarios]]`
table contains ordered `[[scenarios.steps]]` tables.

Supported actions:

- `start` starts a scene by ID.
- `advance` completes a line or stage beat.
- `choose` selects an exact authored choice label.
- `check` resolves the current check with `outcome = "success"` or
  `outcome = "failure"`. The runner finds a deterministic RNG seed and then
  uses the normal check-resolution path, including AP and clue effects.
- `know` establishes a clue, claim, or topic before continuing.
- `investigate` resolves an available clue through the normal successful check
  path, including its action-point cost and unlock effects.
- `demonstrate` completes the first authored evidence route for a question.
- `accuse` selects a character by stable ID.
- `support` assigns a known deduction to the named `motive`, `means`, or
  `opportunity` pillar.
- `reveal` evaluates the reconstruction and enters its authored ending.
- `timeout` enters the terminal out-of-time route.
- `expect` asserts the current beat, scene, AP, active state, or whether a clue,
  claim, topic, ending, or outcome is known.

Example:

```toml
[[scenarios]]
id = "question_route"

[[scenarios.steps]]
action = "know"
state = "clue"
value = "clue_ledger"

[[scenarios.steps]]
action = "start"
value = "scene_question_route"

[[scenarios.steps]]
action = "choose"
value = "Then account for the ledger."

[[scenarios.steps]]
action = "check"
outcome = "failure"

[[scenarios.steps]]
action = "expect"
state = "topic"
value = "failure_followup"
```

`make scenario-test` runs the checked-in Torn Appointment scenarios.
