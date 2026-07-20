# Yard Textures

Stylized, top-down terrain textures generated for the yard system.

- `yard-grass.png` — mown lawn grass
- `yard-gravel.png` — fine warm-gray gravel
- `yard-dirt.png` — compacted garden-path dirt
- `yard-flagstone.png` — irregular garden paving stones

All source images are square PNGs intended for repeating terrain materials. Validate the exact wrap behavior in-engine before shipping; generative seamlessness may still benefit from a conventional offset-and-heal pass.

Runtime mapping:

- Terrain chunks use `yard-grass.png`.
- Paths containing `gravel` use `yard-gravel.png`.
- Paths containing `dirt` use `yard-dirt.png`.
- Other footpaths, including Vale House's front walk, use `yard-flagstone.png`.
- The open Moon Garden Patio floor also uses `yard-flagstone.png`.
