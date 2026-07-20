# Zelda's Storytelling Game

Zelda's Storytelling Game is a tool and a game for creating, sharing, and
playing spatial interactive stories. You make a place, put a story inside it,
and let someone else live through it.

Murder mysteries are the first complete experience. As a detective, you can
explore Vale City and its authored locations, talk to characters, inspect
objects and spaces, collect evidence, test claims, reconstruct events, and
build a supported explanation of what happened. The setting matters: routes,
sightlines, access, timing, and changes to the environment can all become part
of the mystery.

As a creator, you can:

- Shape terrain and build rooms and exteriors.
- Furnish spaces, place characters, props, evidence, and lighting.
- Author dialogue, choices, checks, events, and character knowledge.
- Define a mystery's suspects, motives, clues, chronology, and solution.
- Validate that a story is coherent, fair, and completable.
- Playtest the story in the same experience players receive.
- Export and share a portable story package that can be played offline.

Stories are not limited to one genre. The long-term goal is a shared,
extensible system in which creators can combine compatible settings, content,
and mechanics to make many kinds of spatial interactive stories.

The included reference mystery, **The Torn Appointment**, follows an
investigation that begins at Westhaven Police Station and leads to Vale House,
where the player must examine the scene, question three suspects, and prove a
complete theory of the crime.

## Clone and dependencies

This repository uses [Git LFS](https://git-lfs.com/) for binary art and audio
assets and includes Clipper2 as a Git submodule. Install Git LFS, then clone
with submodules enabled:

```sh
git lfs install
git clone --recurse-submodules <repository-url>
```

For an existing clone, initialize both with:

```sh
git lfs pull
git submodule update --init --recursive
```

## Releases

Tags matching `v*` build macOS arm64 and Windows x86-64 archives and publish
them to a GitHub Release. Start a release from a clean, up-to-date `main`:

```sh
tools/release.sh 1.0.0
```

The workflows expect the reusable engine in `Velfi/zelda-engine`. Override
that with the `ZELDA_ENGINE_REPOSITORY` and `ZELDA_ENGINE_REF` repository
variables. If the engine repository is private, add a `ZELDA_ENGINE_TOKEN`
secret with read access.
