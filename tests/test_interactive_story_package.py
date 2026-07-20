from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("interactive_story_package", ROOT / "tools/interactive_story_package.py")
assert SPEC and SPEC.loader
PACKAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGE)


class InteractiveStoryPackageTests(unittest.TestCase):
    def test_export_and_verify_blank_core_story(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "lantern.interactive-story.zip"
            args = argparse.Namespace(
                root=ROOT,
                config=ROOT / "story.package.json",
                validator=ROOT / "build/chicago",
                skip_engine_validation=True,
                output=output,
            )
            PACKAGE.export(args)
            manifest = PACKAGE.verify(output)
            self.assertEqual(manifest["format"], "InteractiveStoryPackage")
            self.assertEqual(manifest["story_id"], "the_lantern_visit")
            self.assertEqual(manifest["capabilities"], [])
            self.assertEqual(manifest["expansions"], [])
            self.assertFalse(manifest["validation"]["coverage_complete"])
            self.assertTrue(manifest["validation"]["incomplete_acknowledged"])
            self.assertIn("assets/stories/the_lantern_visit.story.toml", {item["path"] for item in manifest["files"]})

    def test_export_and_verify_mystery_domain_story(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "torn-appointment.interactive-story.zip"
            args = argparse.Namespace(
                root=ROOT,
                config=ROOT / "assets/stories/mysteries/the_torn_appointment.package.json",
                validator=ROOT / "build/chicago",
                skip_engine_validation=True,
                output=output,
            )
            PACKAGE.export(args)
            manifest = PACKAGE.verify(output)
            self.assertEqual(manifest["story_id"], "the_torn_appointment")
            self.assertEqual(manifest["capabilities"], [{"id": "mystery", "version": "1"}])
            packaged = {item["path"] for item in manifest["files"]}
            self.assertIn("assets/stories/mysteries/the_torn_appointment.story.toml", packaged)
            self.assertIn("assets/levels/vale_house.toml", packaged)

    def test_archive_contents_must_match_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "bad.zip"
            manifest = {
                "format": "InteractiveStoryPackage",
                "format_version": 1,
                "story_id": "bad",
                "title": "Bad",
                "author": "Test",
                "description": "Test",
                "content_version": "1",
                "capabilities": [],
                "expansions": [],
                "resolved_content_identity": "0" * 64,
                "entrypoints": {"story": "story.toml", "level": ""},
                "files": [{"path": "story.toml", "size": 0, "sha256": "0" * 64}],
            }
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr(PACKAGE.MANIFEST, json.dumps(manifest))
                archive.writestr("content/story.toml", b"")
                archive.writestr("content/unlisted.txt", b"surprise")
            with self.assertRaises(PACKAGE.PackageError):
                PACKAGE.verify(path)

    def test_paths_cannot_escape_content_root(self) -> None:
        with self.assertRaises(PACKAGE.PackageError):
            PACKAGE.safe_relative("../escape")
        with self.assertRaises(PACKAGE.PackageError):
            PACKAGE.safe_relative("/absolute")

    def test_embedded_expansion_is_verified_and_installed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root / "catalog.toml").write_text('[[objects]]\nid="fixture:lamp"\nmodel="lamp.glb"\n'); (root / "lamp.glb").write_bytes(b"lamp")
            (root / "expansion.toml").write_text('format="ExpansionPack v1"\nid="fixture-pack"\nnamespace="fixture"\ntitle="Fixture"\ncreator="Test"\ndescription="Fixture"\nversion="1.0.0"\nengine_min="1.0.0"\nengine_max="1.9.9"\nredistribution_permitted=true\ncatalogs=["catalog.toml"]\ncapabilities=[]\n')
            expansion_config = root / "expansion.package.json"; expansion_config.write_text(json.dumps({"manifest": "expansion.toml", "include": ["lamp.glb"]})); expansion_archive = root / "fixture.expansion"
            subprocess.run([sys.executable, str(ROOT / "tools/expansion_package.py"), "export", str(expansion_archive), "--config", str(expansion_config)], check=True, capture_output=True)
            (root / "story.toml").write_text('version="InteractiveStory v1"\nid="embedded-story"\ntitle="Embedded Story"\ncontent_version="1.0.0"\ndefault_space="level"\n[[expansions]]\nid="fixture-pack"\nversion="1.0.0"\noptional=false\ndistribution="embed"\nfallback="none"\n')
            story_config = root / "story.json"; story_config.write_text(json.dumps({"story": "story.toml", "author": "Test", "description": "Fixture", "content_version": "1.0.0", "acknowledge_incomplete_validation": True, "expansion_packages": {"fixture-pack@1.0.0": "fixture.expansion"}})); output = root / "story.interactive-story"
            args = argparse.Namespace(root=root, config=story_config, validator=ROOT / "build/chicago", skip_engine_validation=True, output=output); PACKAGE.export(args); manifest = PACKAGE.verify(output)
            self.assertEqual(manifest["expansions"][0]["distribution"], "embed")
            library = root / "Library" / "Stories"; PACKAGE.install(argparse.Namespace(package=output, library=library, replace=False, engine_version="1.0.0"))
            self.assertTrue((root / "Library" / "Expansions" / "fixture-pack" / "1.0.0" / "catalog.toml").is_file())
            self.assertTrue((library / "embedded-story" / "1.0.0" / "standalone-campaign.toml").is_file())


if __name__ == "__main__":
    unittest.main()
