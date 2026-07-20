# Spatial story architecture

InteractiveStory is Chicago's only shipped narrative runtime and package format.
StoryCore owns typed narrative state, scenes, stable conditions and effects,
execution, domain registration, compilation, and deterministic content identity.

MysteryDomain is a registered adapter. It owns clues, contradictions,
deductions, demonstrations, solution/fairness validation, hidden creator data,
and stable-ID investigation state. Player queries expose only acquired or
otherwise player-safe information.

Every story declares spatial capabilities. The Chicago host registers the city
and each LevelFormat document as separate qualified spaces. Conditions query the
shared spatial registry; commands are staged against provider snapshots and are
committed atomically with narrative state. Cross-space travel uses authored
transitions and within-space route costs.

Campaign manifests reference `story_path` and `level_path`. Packaging,
validation, playtest, scenarios, and normal launch all compile the same story
document. Legacy case and graph documents are accepted only by the offline
development converter and are never loaded by the shipped runtime.
