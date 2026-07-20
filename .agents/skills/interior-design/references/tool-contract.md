# Interior Agent Tool Contract

Use the repository root `/Users/zelda/Documents/chicago` as the working directory.

## Current files

- Tool: `tools/interior_agent.py`
- Default level: `assets/levels/vale_house.toml`
- Default catalog: `assets/catalog/editor_catalog.toml`
- Tests: `tests/test_interior_agent.py`

Pass `--level` and `--catalog` before the subcommand when targeting other files.

## Inspect and discover

```sh
python3 tools/interior_agent.py inspect-room study
python3 tools/interior_agent.py search-catalog "table" --placement indoor --limit 20
python3 tools/interior_agent.py validate --room study
```

`inspect-room` returns the polygon, bounds, materials, contained objects, catalog categories, footprint radii, transforms, support IDs, and markers. Catalog search matches ID, category, and placement metadata in deterministic manifest order.

## Preview before mutation

```sh
python3 tools/interior_agent.py preview-placement agent_plant plant \
  --room study --relationship against_wall --wall west --distance 0.2
```

Supported relationships:

- `center_of_room`
- `against_wall` with `--wall north|south|east|west|nearest`
- `beside --target OBJECT_ID`
- `in_front_of --target OBJECT_ID`
- `facing --target OBJECT_ID`
- `on_surface --target OBJECT_ID`

Use `--distance` for separation and `--rotation` only when semantic resolution is insufficient. A preview is read-only and returns `state`, the resolved candidate, diagnostics, and a JSON add diff. Do not commit a blocked preview.

## Commit deliberately

After reviewing the preview, repeat the same arguments with `place-object`:

```sh
python3 tools/interior_agent.py place-object agent_plant plant \
  --room study --relationship against_wall --wall west --distance 0.2
```

The command rejects duplicate IDs and invalid candidates, then atomically appends an ordinary `[[objects]]` entry. It does not create a parallel scene representation. Run validation after each coherent group of placements, not merely at the end.

## Render the canonical plan

```sh
python3 tools/interior_agent.py render-room study --output /tmp/study-plan.svg
```

This creates a deterministic top-down SVG showing circular catalog footprint approximations. Use it to evaluate grouping, density, and gross circulation. It is not sufficient for height, occlusion, asset orientation, lighting, or production visual quality; use engine renders for those judgments when available.

## Known limits

- Placement validation uses catalog footprint radii and detects approximate overlap; it is not full mesh collision or navmesh validation.
- `against_wall` targets a cardinally selected polygon segment midpoint rather than an arbitrary offset along a named wall.
- `facing` places the new object at room center before orienting it toward the target.
- Static catalog absence is a warning because runtime-discovered paintings may be valid.
- The CLI currently places objects only; use existing editor/runtime paths for rooms, openings, lighting, and richer transforms.

Never edit level TOML by string manipulation when the CLI already supports the operation. For unsupported changes, follow the level serializer schema in `src/level_editor.odin`, preserve stable IDs, and run the project checks.

## Verification

Run:

```sh
make agent-tools-test
```

For level changes, also run the narrowest relevant project validation or test target and inspect an engine render when visual correctness matters.
