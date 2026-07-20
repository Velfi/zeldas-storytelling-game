import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CASE_TOOL = ROOT / "tools/interactive_story_package.py"
CAMPAIGN_TOOL = ROOT / "tools/campaign_package.py"

class CampaignPackageTests(unittest.TestCase):
    def run_tool(self, tool, *arguments, expected=0):
        result = subprocess.run([sys.executable, str(tool), *map(str, arguments)], text=True, capture_output=True)
        self.assertEqual(result.returncode, expected, result.stderr + result.stdout)
        return result

    def make_case(self, root: Path, case_id: str):
        assets = root / case_id; assets.mkdir(parents=True)
        (assets / "story.toml").write_text(f'version="InteractiveStory v1"\nid="{case_id}"\ntitle="{case_id}"\ncontent_version="1.0.0"\ndefault_space="{case_id}_level"\n')
        (assets / "level.toml").write_text(f'version="LevelFormat v1"\nid="{case_id}_level"\n')
        config = {"author": "Author", "description": "Case", "content_version": "1.0.0", "story": f"{case_id}/story.toml", "level": f"{case_id}/level.toml", "acknowledge_incomplete_validation": True}
        config_path = root / f"{case_id}.json"; config_path.write_text(json.dumps(config))
        package = root / f"{case_id}.interactive-story"
        self.run_tool(CASE_TOOL, "export", package, "--root", root, "--config", config_path, "--skip-engine-validation")
        return package

    def test_deterministic_export_verify_and_install(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); first = self.make_case(root, "first"); second = self.make_case(root, "second")
            (root / "hero.png").write_bytes(b"portable campaign artwork")
            (root / "campaign.toml").write_text('version="MysteryCampaign v2"\nid="collection"\ntitle="Collection"\ncreator="Author"\ndescription="Campaign"\ncontent_version="1.0.0"\nthumbnail="hero.png"\n[[conditions]]\nkind=0\n[[cases]]\nid="first"\ntitle="First"\nstory_path="first/story.toml"\nlevel_path="first/level.toml"\ncontent_version="1.0.0"\ncondition_root=0\nrequired=true\noptional=false\n[[cases]]\nid="second"\ntitle="Second"\nstory_path="second/story.toml"\nlevel_path="second/level.toml"\ncontent_version="1.0.0"\ncondition_root=0\nrequired=true\noptional=false\n')
            config = root / "campaign.package.json"
            config.write_text(json.dumps({"campaign": "campaign.toml", "author": "Author", "description": "Campaign", "content_version": "1.0.0", "cases": [first.name, second.name]}))
            one, two = root / "one.mysterycampaign", root / "two.mysterycampaign"
            self.run_tool(CAMPAIGN_TOOL, "export", one, "--config", config); self.run_tool(CAMPAIGN_TOOL, "export", two, "--config", config)
            self.assertEqual(one.read_bytes(), two.read_bytes()); self.run_tool(CAMPAIGN_TOOL, "inspect", one)
            library = root / "library"; self.run_tool(CAMPAIGN_TOOL, "import", one, "--library", library)
            self.assertTrue((library / "collection/1.0.0/content/campaign.toml").is_file())
            runtime = library / "collection/1.0.0/runtime"
            self.assertTrue((runtime / "campaign.toml").is_file())
            self.assertTrue((runtime / "cases/first/1.0.0/first/story.toml").is_file())
            self.assertTrue((runtime / "cases/second/1.0.0/second/level.toml").is_file())
            runtime_document = (runtime / "campaign.toml").read_text()
            self.assertIn(str((runtime / "cases/first/1.0.0/first/story.toml").resolve()), runtime_document)
            self.assertIn(str((runtime / "campaign-thumbnail.png").resolve()), runtime_document)
            self.assertEqual((runtime / "campaign-thumbnail.png").read_bytes(), b"portable campaign artwork")

    def test_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            unsafe = Path(directory) / "unsafe.mysterycampaign"
            with zipfile.ZipFile(unsafe, "w") as archive:
                archive.writestr("campaign-manifest.json", "{}"); archive.writestr("../escape", "bad")
            self.run_tool(CAMPAIGN_TOOL, "inspect", unsafe, expected=2)

if __name__ == "__main__": unittest.main()
