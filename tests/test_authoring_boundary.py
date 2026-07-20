import importlib.util
from pathlib import Path
import unittest


SCRIPT = Path(__file__).parents[1] / "tools" / "check_authoring_boundary.py"
SPEC = importlib.util.spec_from_file_location("authoring_boundary", SCRIPT)
CHECK = importlib.util.module_from_spec(SPEC); assert SPEC.loader; SPEC.loader.exec_module(CHECK)


class AuthoringBoundaryTests(unittest.TestCase):
    def assert_category(self, source, category, path="src/ui_screens.odin"):
        found = CHECK.findings_for_text(path, source)
        self.assertIn(category, [item.category for item in found])
        self.assertTrue(all(item.line == 1 and item.destination for item in found))

    def test_negative_fixtures_cover_every_boundary(self):
        self.assert_category("g.pending_clue=2", "numeric runtime identity")
        self.assert_category("if capture_mode {g.player_x=4}", "compiled capture transform", "src/main.odin")
        self.assert_category("items: [4]World_Entity{}", "static World_Entity content")
        self.assert_category("item:=Runtime_Interactive{id=\"door\"}", "synthetic interactive", "src/world.odin")
        self.assert_category("if entity.source_id==\"suspect\" {}", "renderer entity-ID dispatch")
        self.assert_category("World_Entity{name=\"Suspect\"}", "author-facing compiled copy")

    def test_level_projection_is_legitimate(self):
        source = "for marker in level_document.markers {item:=Runtime_Interactive{id=marker.id}}"
        self.assertEqual(CHECK.findings_for_text("src/world.odin", source), [])


if __name__ == "__main__": unittest.main()
