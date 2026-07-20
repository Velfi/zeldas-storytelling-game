# MurderScript v1 — converter fixture format

This format is not loaded by the shipped runtime. It is documented solely for
the deterministic offline converter and immutable legacy fixtures. New and
converted mysteries are authored as InteractiveStory documents with a
registered MysteryDomain payload.

Legacy fixture files under `tests/fixtures/legacy/cases/` are TOML inputs consumed only by
`tools/convert_legacy_mystery.py`. Their stable IDs connect characters,
locations, points of interest, events, claims, clues, contradictions, and the
old solution contract. The descriptions below exist only to maintain and test
that offline conversion path; they are not runtime authoring guidance.

## Authored case endings

`[[endings]]` lets a case finish for reasons beyond solving the canonical mystery. Each ending has a stable `id`, a unique `trigger`, presentation copy, a semantic `tone` (`success`, `neutral`, `warning`, or `failure`), and a primary action. Supported actions are `campaign`, `restart`, `title`, `quit`, and `reveal`; `reveal` displays the optional `canonical_timeline`. A secondary label/action pair is optional.

The final reconstruction automatically requests one of these triggers: `outcome.airtight`, `outcome.correct_but_unproven`, `outcome.plausible_incomplete`, `outcome.wrong_accusation`, or `outcome.unresolved`. An ending using one of those triggers should set the matching `outcome` value so campaign state records it. Exhausting the investigation clock requests `out_of_time`; it need not record an outcome. Other trigger names are author-defined and may be requested by game-specific systems.

A cinematic dialogue beat with `kind = "end"` may set `ending = "ending_id"`. When reached, its normal unlock effects are applied and the named ending opens immediately. This supports bargains, escapes, refusals, deaths, departures, or any authored terminal story event without pretending that the player submitted a solution. Ending IDs, triggers, tones, actions, and dialogue references are validated when the case loads.

```toml
[[endings]]
id = "suspect_escapes"
trigger = "suspect_escapes"
title = "THE HOUSE IS EMPTY"
subtitle = "The inquiry ends before an accusation"
summary = "By the time the warrant arrives, the suspect is gone."
epilogue = "The evidence remains, but the confrontation is lost."
tone = "failure"
primary_label = "RETRY THE CASE"
primary_action = "restart"
secondary_label = "RETURN TO CAMPAIGN"
secondary_action = "campaign"

[[dialogue_beats]]
id = "escape_end"
scene = "scene_final_warning"
kind = "end"
ending = "suspect_escapes"
```

Evidence presentation is derived from authored semantics: a discovered clue is compatible with an dialogue approach only when it satisfies one of that clue's prerequisites or shares an authored topic. A presentation costs no action, is single-use per approach, adds +10 to both previewed and resolved odds, and counts as a changed circumstance for white-check reopening. Red checks remain expired regardless of later presentation.

To add a case, copy the bundled file, change every ID consistently, preserve the cardinality rules, author affordable clue routes, then point `load_case` in `main.odin` at it. The canonical solution is only read by evaluation and development diagnostics.

Cases may also contribute one optional `[[city_locations]]` entry. A city
location supplies a stable ID, player-facing label, and the authored level
marker used when the player enters from the city. It does not create or alter
geometry; the static city places labels on reserved case sites:

```toml
[[city_locations]]
id = "vale_house"
display_name = "VALE HOUSE"
level_spawn = "spawn_front_gate"
```

Permanent landmarks such as Westhaven Police Station are owned by the city and
must not be repeated in case data. A case may start at a permanent landmark or
at its own opening, but the station is not an implicit universal start. The
reference tutorial starts at the station and routes to its first case label,
Vale House. Permanent landmark and reserved-site transforms, including their
arrival positions and facings, are authored in `assets/city/landmarks.toml`.

City opening behavior is explicit metadata rather than a case-ID convention:

```toml
city_start = "police_station"
city_destination = "vale_house"
tutorial = "basic_controls"
```

`city_start` may reference a permanent landmark or the case label.
`city_destination` references the case label. `tutorial` is optional; the only
v1 value is `basic_controls`. Because campaign cases currently have one
`level_path`, the validator rejects multiple case city labels instead of
silently routing several names to the same level.

## LLM generation template

Generate one mystery as valid MurderScript v1 TOML, outputting TOML only. Include exactly four characters (one victim and three suspects), exactly five connected investigative `[[locations]]`, exactly one culprit, 8–10 discoverable clues, and only the supported actions above. When the case needs a city-map destination, include one `[[city_locations]]` entry containing only a stable ID and display label; do not redefine permanent city landmarks or imply that the label adds geometry. One innocent suspect must support the killer's false alibi because of an unrelated secret; another must conceal a separate wrongdoing. Important conclusions should have two support routes where practical. Include one fair decisive proof based on unique knowledge or opportunity, with no confession required. Do not use twins, supernatural events, secret passages, or evidence invented after the crime. Essential progress cannot depend exclusively on a random check. All IDs and references must resolve, the timeline must be physically possible, the solution must exclude both innocents, and the total winning route must cost at most 12 action points.

An LLM proposes data; the deterministic engine validates and adjudicates it.

## Reconstruction

The `[solution]` contract retains stable support references for physical validation and optional reconstruction diagnostics. Player-facing completion is candidate-relative: after choosing a suspect, the player must apply an established deduction to motive, means, and opportunity. Optional reconstruction details and innocent-suspect explanations enrich the reveal without gating it. A correct culprit missing one or more pillars remains `Correct_But_Unproven` or `Plausible_Incomplete`, and an incorrect culprit can never be airtight.

The player-facing theory flow is authored through `[[questions]]`, `[[demonstrations]]`, and `[[deductions]]`. Questions state genuine unknowns and open from clue, claim, deduction, or earlier-question prerequisites; they are never globally required. A demonstration references one question, selects `physical`, `timeline`, `comparison`, or `confrontation`, and supplies two or three neutral `slot_labels` and broad `slot_types`: `observation`, `testimony`, `statement`, or `deduction`. Accepted combinations are flattened in `accepted_routes`, with matching `route_firsts` and `route_counts`; any complete route may establish the question. A demonstration resolves as `substantiated`, `eliminated`, or `explained` and awards its `result_deductions`. Deductions may declare candidate-relative proof support such as `supports = ["miriam:motive"]`, using the pillars `motive`, `means`, and `opportunity`. The loader rejects dangling references, invalid route shapes or types, self-dependent routes, unprotected or unaffordable proof-pillar routes, dependency cycles, and missing culprit pillars. Legacy cases using one `accepted_pieces` tuple continue to load as a single route. Claim truth flags remain author-only: discovering a claim establishes that it was said, not that it was true.
