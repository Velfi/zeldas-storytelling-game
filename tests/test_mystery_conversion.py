import json
import subprocess
import tempfile
import tomllib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONVERTER = ROOT / "tools" / "convert_legacy_mystery.py"
REPORTS = sorted((ROOT / "assets" / "stories" / "mysteries").rglob("*.conversion.json"))


class MysteryConversionTests(unittest.TestCase):
    def test_all_campaign_mysteries_convert_deterministically_without_warnings(self):
        self.assertEqual(len(REPORTS), 17)
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            for index, checked_report_path in enumerate(REPORTS):
                checked_report = json.loads(checked_report_path.read_text())
                output = temporary / f"story-{index}.toml"
                report = temporary / f"story-{index}.json"
                subprocess.run(
                    ["python3", str(CONVERTER), checked_report["case_path"], checked_report["graph_path"], checked_report["level_path"], str(output), "--report", str(report)],
                    cwd=ROOT,
                    check=True,
                )
                checked_story = Path(str(checked_report_path).removesuffix(".conversion.json"))
                generated = json.loads(report.read_text())
                # The reference vertical slice is now maintained as authored
                # InteractiveStory source. Keep exercising its legacy converter
                # for warnings, but do not overwrite later hand-authored work.
                if checked_report.get("post_conversion_authored"):
                    self.assertEqual(generated["warnings"], [])
                    continue
                self.assertEqual(output.read_bytes(), checked_story.read_bytes())
                self.assertEqual(generated["sha256"], checked_report["sha256"])
                self.assertEqual(generated["preserved_ids"], checked_report["preserved_ids"])
                self.assertEqual(generated["generated_ids"], checked_report["generated_ids"])
                self.assertEqual(generated["warnings"], [])

    def test_converted_story_retains_domain_only_legacy_semantics(self):
        story = tomllib.loads((ROOT / "assets" / "stories" / "mysteries" / "the_torn_appointment.story.toml").read_text())
        theft_confrontation = next(node for node in story["nodes"] if node["id"] == "approach_elsie_theft_response")
        self.assertEqual(theft_confrontation["speaker"], "detective")
        briefing_instruction = next(node for node in story["nodes"] if node["id"] == "briefing_instruction")
        self.assertIn("An accident ought not require three explanations", briefing_instruction["text"])
        scenes = {scene["id"]: scene for scene in story["scenes"]}
        self.assertNotIn("blood", scenes["scene_inspect_statuette"]["display_name"].lower())
        self.assertNotIn("8:20", scenes["scene_recover_memo_stub"]["display_name"])
        self.assertNotIn("burned note", scenes["scene_search_wastebin"]["display_name"].lower())
        mystery = story["mystery"]
        propositions = {item["id"]: item["text"] for item in story["propositions"]}
        for clue in mystery["clues"]:
            self.assertNotEqual(clue["description"], propositions[clue["proposition"]])
        self.assertTrue(any(character["private_secret"] for character in mystery["characters"]))
        self.assertTrue(any(location["connections"] for location in mystery["locations"]))
        self.assertTrue(any(poi["relevant_state"] for poi in mystery["pois"]))
        self.assertTrue(any(event["effects"] for event in mystery["events"]))
        self.assertIn("canonical_truth", mystery["claims"][0])
        demonstrations = {item["question"]: item["result"] for item in mystery["demonstrations"]}
        self.assertIn("where Edgar was displayed, not where he died", demonstrations["q_garden_murder"])
        self.assertIn("Two empty places cannot witness each other", demonstrations["q_miriam_alibi"])
        self.assertIn("sentence she chose to deny", demonstrations["q_miriam_study_meeting"])
        questions = {item["id"]: item["prompt"] for item in mystery["questions"]}
        self.assertIn("body but so little blood", questions["q_garden_murder"])
        self.assertIn("merely arrange him", questions["q_cane_weapon"])
        self.assertIn("two empty places", questions["q_miriam_alibi"])
        solution = mystery["solution"]
        self.assertTrue(solution["weapon_block"])
        self.assertTrue(solution["murder_events"])
        self.assertTrue(solution["cover_up_events"])
        self.assertTrue(solution["false_alibis"])


if __name__ == "__main__":
    unittest.main()
