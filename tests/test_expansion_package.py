from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "expansion_package.py"


class ExpansionPackageTests(unittest.TestCase):
    def fixture(self, root: Path, namespace: str = "art_deco") -> Path:
        (root / "catalog.toml").write_text(
            f'[[objects]]\nid = "{namespace}:fan_table"\nmodel = "fan.glb"\n', encoding="utf-8"
        )
        (root / "fan.glb").write_bytes(b"glTF fixture")
        (root / "expansion.toml").write_text(
            f'format = "ExpansionPack v1"\nid = "art-deco"\nnamespace = "{namespace}"\n'
            'title = "Art Deco"\ncreator = "Test"\ndescription = "Fixture"\nversion = "1.2.3"\n'
            'engine_min = "1.0.0"\nengine_max = "1.9.9"\nredistribution_permitted = true\n'
            'catalogs = ["catalog.toml"]\ncapabilities = ["mystery@1"]\n', encoding="utf-8"
        )
        config = root / "expansion.package.json"
        config.write_text(json.dumps({"manifest": "expansion.toml", "include": ["fan.glb"]}), encoding="utf-8")
        return config

    def run_tool(self, *args: object, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run([sys.executable, str(TOOL), *(str(arg) for arg in args)], text=True, capture_output=True, check=check)

    def test_export_verify_install_enable_disable_and_uninstall(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); config = self.fixture(root); package = root / "art-deco.expansion"; library = root / "library"
            self.run_tool("export", package, "--config", config)
            manifest = json.loads(self.run_tool("inspect", package).stdout)
            self.assertEqual(manifest["format"], "ExpansionPack")
            self.assertEqual(manifest["namespace"], "art_deco")
            self.run_tool("install", package, "--library", library)
            installed = library / "art-deco" / "1.2.3"
            self.assertTrue((installed / "catalog.toml").is_file())
            enabled = json.loads((library / "enabled-expansions.json").read_text())["enabled"]
            self.assertEqual(enabled, ["art-deco@1.2.3"])
            self.run_tool("disable", "art-deco@1.2.3", "--library", library)
            self.run_tool("enable", "art-deco@1.2.3", "--library", library)
            self.run_tool("uninstall", "art-deco@1.2.3", "--library", library)
            self.assertFalse(installed.exists())

    def test_rejects_bad_namespace_and_engine_version(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); config = self.fixture(root, "core"); package = root / "bad.expansion"
            result = self.run_tool("export", package, "--config", config, check=False)
            self.assertNotEqual(result.returncode, 0)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); config = self.fixture(root); package = root / "version.expansion"
            result = self.run_tool("export", package, "--config", config, "--engine-version", "2.0.0", check=False)
            self.assertNotEqual(result.returncode, 0)

    def test_duplicate_namespace_cannot_be_installed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); library = root / "library"
            first = root / "first"; first.mkdir(); first_config = self.fixture(first); first_package = root / "first.expansion"
            self.run_tool("export", first_package, "--config", first_config); self.run_tool("install", first_package, "--library", library)
            second = root / "second"; second.mkdir(); second_config = self.fixture(second)
            text = (second / "expansion.toml").read_text().replace('id = "art-deco"', 'id = "another-pack"')
            (second / "expansion.toml").write_text(text); second_package = root / "second.expansion"
            self.run_tool("export", second_package, "--config", second_config)
            result = self.run_tool("install", second_package, "--library", library, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("namespace is already owned", result.stderr)


if __name__ == "__main__":
    unittest.main()
