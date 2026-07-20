# InteractiveStoryPackage

Chicago distributes both general stories and mysteries through one package
format. `story.package.json` identifies the InteractiveStory source, its exact
capability and expansion requirements, the separately authored LevelFormat asset, the
compiled content identity, and validation completeness.

The exporter validates and compiles the source before writing the archive. The
inspector and installer verify the manifest and integrity table, and package
launch loads the same compiled runtime used by normal play and editor playtest.
Player progress is stored outside the package.

Mystery packages do not have a separate schema or command family. Mystery-only
records are serialized as the registered `mystery@1` capability payload inside the
InteractiveStory document. Player-safe manifest metadata never contains the
culprit, canonical truth, accepted deduction routes, or hidden solution
requirements.

Expansion dependencies use `reference` or `embed`. References require the exact
installed and enabled version. Embedded archives are accepted only when their
verified manifest permits redistribution. The resolved dependency identity is
part of the package and runtime content identities.

Campaign bundles pin every case by content ID and exact version. A case is
embedded by default and its verified package must exist at export time. A bundle
may instead declare a case external only when the author explicitly enables
external dependencies; players must then install that exact case version before
the campaign is compatible or installable. External case packages are never
silently copied into the campaign archive.
