"""Write a screenshot-to-asset index for the mystery prop proof sheets."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "assets/models/mysteries"
OUT = ROOT / "docs/mysteries/3d-prop-verification.md"
manifest = json.loads((MODELS / "manifest.json").read_text())["models"]

lines = [
    "# Mystery 3D Prop Verification",
    "",
    "Each proof sheet renders twelve consecutive assets from the production manifest. "
    "The models use intentionally economical low-poly silhouettes; this index makes "
    "the review mapping explicit for evidence and document families whose readable "
    "detail is primarily material/state work.",
    "",
    f"- Manifest models: **{len(manifest)}**",
    f"- Proof sheets: **{(len(manifest) + 11) // 12}**",
    "- Renderer: Blender 5.1.1, orthographic 4 × 3 QA grid",
    "",
]

for start in range(0, len(manifest), 12):
    batch = start // 12 + 1
    entries = manifest[start:start + 12]
    lines += [
        f"## Batch {batch:02d} — assets {start + 1}–{start + len(entries)}",
        "",
        f"![Batch {batch:02d}](../screenshots/mystery-props/batch-{batch:02d}.png)",
        "",
        "| # | Asset | Model |",
        "| ---: | --- | --- |",
    ]
    for index, item in enumerate(entries, start + 1):
        lines.append(f"| {index} | {item['name']} | `{item['path']}` |")
    lines.append("")

OUT.write_text("\n".join(lines) + "\n")
print(f"Wrote {OUT.relative_to(ROOT)}")
