import importlib.util
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("interior_agent", ROOT / "tools/interior_agent.py")
AGENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AGENT)


class InteriorAgentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.level = AGENT.load_toml(ROOT / "assets/levels/vale_house.toml")
        cls.catalog = AGENT.load_toml(ROOT / "assets/catalog/editor_catalog.toml")

    def test_inspect_room_only_returns_contained_objects(self):
        room = AGENT.inspect_room(self.level, self.catalog, "study")
        self.assertEqual(room["id"], "study")
        self.assertTrue(all(AGENT.point_in_polygon(tuple(item["position"]), room["points"]) for item in room["objects"]))

    def test_search_catalog_is_semantic_and_deterministic(self):
        results = AGENT.search_catalog(self.catalog, "table", None, "indoor", 5)
        self.assertTrue(results)
        self.assertTrue(all("table" in (item["id"] + " " + item["category"]) for item in results))
        self.assertIn("dimensions", results[0])
        self.assertIn("affordances", results[0])

    def test_relationship_preview_does_not_mutate(self):
        count = len(self.level.get("objects", []))
        AGENT.resolve_placement(self.level, self.catalog, "study", "core:plant", "against_wall", None, .2, "west", None)
        self.assertEqual(len(self.level.get("objects", [])), count)

    def test_on_surface_uses_authored_surface(self):
        bedroom = AGENT.inspect_room(self.level, self.catalog, "master_bedroom")
        support = next(item for item in bedroom["objects"] if AGENT.catalog_objects(self.catalog).get(item["catalog_id"], {}).get("surface_height", 0) > 0)
        placement = AGENT.resolve_placement(self.level, self.catalog, "master_bedroom", "core:table_lamp_square", "on_surface", support["id"], .2, "nearest", None)
        self.assertEqual(placement["support_id"], support["id"])
        self.assertGreater(placement["elevation"], 0)

    def test_beside_distance_is_clearance_not_center_offset(self):
        target = AGENT.object_for(self.level, "furnish_dining_room_1_dining_table")
        placement = AGENT.resolve_placement(self.level, self.catalog, "dining_room", "core:chair_rounded", "beside", target["id"], .25, "nearest", None)
        assets = AGENT.catalog_objects(self.catalog)
        expected = assets[target["catalog_id"]]["footprint_radius"] + assets["core:chair_rounded"]["footprint_radius"] + .25
        self.assertAlmostEqual(__import__("math").dist(placement["position"], AGENT.position(target)), expected, places=2)

    def test_vale_furnishing_ids_match_catalog_assets(self):
        for item in self.level.get("objects", []):
            if not item["id"].startswith("furnish_"):
                continue
            asset_id = item["catalog_id"].removeprefix("core:")
            self.assertTrue(item["id"].endswith(f"_{asset_id}"), (item["id"], item["catalog_id"]))

    def test_engine_commit_preserves_permissions_and_valid_toml(self):
        engine = ROOT / "build/chicago"
        if not engine.exists():
            self.skipTest("engine has not been built")
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "level.toml"
            target.write_text((ROOT / "assets/levels/vale_house.toml").read_text())
            target.chmod(0o644)
            placement = AGENT.resolve_placement(self.level, self.catalog, "study", "core:plant", "center_of_room", None, .2, "nearest", None)
            candidate = dict(placement, id="agent_commit_test")
            result = AGENT.engine_transaction(engine, target, ROOT / "assets/catalog/editor_catalog.toml", "commit", candidate)
            self.assertIn(result["state"], ("valid", "warning"))
            loaded = AGENT.load_toml(target)
            self.assertEqual(loaded["objects"][-1]["id"], "agent_commit_test")
            self.assertEqual(target.stat().st_mode & 0o777, 0o644)

    def test_canonical_render_is_deterministic_svg(self):
        with tempfile.TemporaryDirectory() as folder:
            first = Path(folder) / "first.svg"; second = Path(folder) / "second.svg"
            AGENT.render_plan_svg(self.level, self.catalog, "study", first)
            AGENT.render_plan_svg(self.level, self.catalog, "study", second)
            self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_engine_preview_is_authoritative_when_built(self):
        engine = ROOT / "build/chicago"
        if not engine.exists():
            self.skipTest("engine has not been built")
        placement = AGENT.resolve_placement(self.level, self.catalog, "study", "core:plant", "against_wall", None, .2, "west", None)
        result = AGENT.engine_transaction(engine, ROOT / "assets/levels/vale_house.toml", ROOT / "assets/catalog/editor_catalog.toml", "preview", dict(placement, id="agent_engine_preview"))
        self.assertTrue(result["engine_validated"])
        self.assertIn(result["state"], ("valid", "warning"))

    def test_engine_level_validation_is_authoritative_when_built(self):
        engine = ROOT / "build/chicago"
        if not engine.exists():
            self.skipTest("engine has not been built")
        result = AGENT.engine_validate(engine, ROOT / "assets/levels/vale_house.toml")
        self.assertTrue(result["valid"])
        self.assertTrue(result["engine_validated"])


if __name__ == "__main__":
    unittest.main()
