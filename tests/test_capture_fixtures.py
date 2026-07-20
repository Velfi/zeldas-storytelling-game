import importlib.util
from pathlib import Path
import unittest


SCRIPT = Path(__file__).parents[1] / "tools" / "check_capture_fixtures.py"
SPEC = importlib.util.spec_from_file_location("capture_fixture_check", SCRIPT)
CHECK = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(CHECK)


class CaptureFixtureStaticCheckTests(unittest.TestCase):
    def test_repository_capture_setup_is_stable(self):
        source = (Path(__file__).parents[1] / "src" / "main.odin").read_text()
        self.assertEqual(CHECK.violations(source), [])

    def test_rejects_numeric_and_coordinate_bypasses(self):
        examples = {
            "if capture_mode {g.dialogue_entity=2}": "numeric dialogue entity",
            "if capture_mode {target:=context_entity_target(&g,3)}": "numeric context target",
            "if capture_mode {g.interactives[0].locked=true}": "numeric interactive access",
            "if capture_mode {WORLD_ENTITIES[i].x=4}": "capture world-entity mutation",
            "if capture_mode {g.player_x=12.5}": "hardcoded capture transform",
        }
        for source, expected in examples.items():
            with self.subTest(source=source):
                self.assertIn(expected, CHECK.violations(source))


if __name__ == "__main__":
    unittest.main()
