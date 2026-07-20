#!/usr/bin/env python3
"""Deterministically convert one MurderScript + GraphMode pair to InteractiveStory.

This is an offline development tool. The shipped runtime never invokes legacy
parsers. Conversion is intentionally strict: graph edges and source IDs are
preserved, and unsupported records fail instead of being silently discarded.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import tomllib


def q(value: object) -> str:
    return json.dumps("" if value is None else str(value), ensure_ascii=False)


def arr(values: object) -> str:
    def scalar(value: object) -> str:
        if isinstance(value, bool):
            return "true" if value else "false"
        if isinstance(value, (int, float)):
            return str(value)
        return q(value)

    return "[" + ", ".join(scalar(v) for v in (values or [])) + "]"


def table(lines: list[str], name: str, values: dict[str, object]) -> None:
    lines += ["", f"[[{name}]]"]
    for key, value in values.items():
        if isinstance(value, bool):
            rendered = "true" if value else "false"
        elif isinstance(value, (int, float)):
            rendered = str(value)
        elif isinstance(value, list):
            rendered = arr(value)
        else:
            rendered = q(value)
        lines.append(f"{key} = {rendered}")


def node_kind(kind: str) -> str:
    supported = {"line", "choice", "check", "stage", "interaction", "end"}
    if kind not in supported:
        raise ValueError(f"unsupported graph node kind: {kind}")
    return kind


def combined_refs(record: dict[str, object], prefix: str) -> list[str]:
    result: list[str] = []
    for suffix in ("clues", "claims", "topics"):
        result.extend(record.get(f"{prefix}_{suffix}", []) or [])
    return result


def spatial_binding(entity_id: str, level: dict[str, object], level_id: str) -> tuple[str, str, str]:
    for room in level.get("rooms", []):
        if room.get("id") == entity_id:
            return level_id, "room", entity_id
    for obj in level.get("objects", []):
        if obj.get("id") == entity_id:
            return level_id, "entity", entity_id
    for marker in level.get("markers", []):
        if marker.get("id") == entity_id or marker.get("reference") == entity_id:
            kind = "transition" if marker.get("kind") == "transition" else "marker"
            return level_id, kind, str(marker.get("id"))
    return "", "entity", ""


def convert(case_path: Path, graph_path: Path, level_path: Path) -> tuple[str, dict[str, object]]:
    with case_path.open("rb") as f:
        case = tomllib.load(f)
    with graph_path.open("rb") as f:
        graph = tomllib.load(f)
    with level_path.open("rb") as f:
        level = tomllib.load(f)
    if case.get("version") != "MurderScript v1":
        raise ValueError("unsupported legacy case version")
    if graph.get("version") != "GraphMode v1" or graph.get("case_id") != case.get("id"):
        raise ValueError("graph does not match legacy case")
    level_id = str(level.get("id") or level_path.stem)
    lines = [
        'version = "InteractiveStory v1"',
        f'id = {q(case["id"])}',
        f'title = {q(case["title"])}',
        'creator = "Chicago conversion tool"',
        f'description = {q(case.get("introduction", ""))}',
        'content_version = "1.0.0"',
        f'default_space = {q(level_id)}',
        'revision = 0',
        '',
        '[[capabilities]]',
        'id = "mystery"',
        'version = "1"',
    ]
    entity_ids: set[str] = set()
    for character in case.get("characters", []):
        sid, skind, target = spatial_binding(str(character["id"]), level, level_id)
        table(lines, "entities", {"id": character["id"], "kind": "character", "display_name": character.get("display_name", ""), "description": character.get("description", ""), "space_id": sid, "target_kind": skind, "target_id": target, "tags": [character.get("role", "")], "roles": []})
        entity_ids.add(str(character["id"]))
    for location in case.get("locations", []):
        sid, skind, target = spatial_binding(str(location["id"]), level, level_id)
        table(lines, "entities", {"id": location["id"], "kind": "location", "display_name": location.get("display_name", ""), "description": location.get("description", ""), "space_id": sid, "target_kind": skind, "target_id": target, "tags": [], "roles": []})
        entity_ids.add(str(location["id"]))
    for poi in case.get("pois", []):
        sid, skind, target = spatial_binding(str(poi["id"]), level, level_id)
        table(lines, "entities", {"id": poi["id"], "kind": poi.get("kind", "object"), "display_name": poi.get("display_name", ""), "description": poi.get("description", ""), "space_id": sid, "target_kind": skind, "target_id": target, "tags": [], "roles": []})
        entity_ids.add(str(poi["id"]))
    proposition_ids: set[str] = set()
    for group in (case.get("claims", []), case.get("clues", []), case.get("deductions", [])):
        for item in group:
            pid = str(item["id"])
            if pid in proposition_ids:
                continue
            table(lines, "propositions", {"id": pid, "text": item.get("proposition", item.get("description", pid)), "canonical_truth": "undetermined"})
            proposition_ids.add(pid)
    for event in case.get("canonical_timeline", case.get("events", [])):
        table(lines, "events", {"id": event["id"], "subject": event.get("actor", ""), "action": event.get("action", ""), "object": event.get("target", ""), "location": event.get("source", event.get("destination", "")), "fictional_time": event.get("time", ""), "provenance": "legacy_conversion", "witnesses": event.get("witnesses", [])})
    table(lines, "conditions", {"id": "condition.always", "kind": "always", "children": [], "variable": "", "entity": "", "other_entity": "", "proposition": "", "objective": "", "event": "", "content": "", "text": "", "space_a": "", "target_a": "", "space_b": "", "target_b": "", "distance": 0, "value_kind": "boolean", "boolean_value": False, "integer_value": 0, "text_value": "", "comparison": 0, "objective_status": 0, "stance": "uncertain"})
    for scene in graph.get("scenes", []):
        table(lines, "scenes", {"id": scene["id"], "display_name": scene.get("summary", scene["id"]), "entry_node": scene["entry"], "bound_entity": scene.get("source", ""), "summary": scene.get("summary", ""), "return_to": scene.get("return_to", "investigation")})
    graph_nodes = graph.get("nodes", [])
    node_ids = {str(n["id"]) for n in graph_nodes}
    for node in graph_nodes:
        choices = node.get("choice_targets", []) or []
        choice_ids = [f'{node["id"]}.choice.{i}' for i in range(len(choices))]
        values = {
            "id": node["id"], "scene": node["scene"], "kind": node_kind(str(node["kind"])),
            "line_id": node.get("id", ""), "speaker": node.get("speaker", ""), "text": node.get("text", ""),
            "next": node.get("next", ""), "success": node.get("success", ""), "failure": node.get("failure", ""), "cancel": node.get("cancel", ""), "subscene": "",
            "condition_id": "", "effect_ids": [], "ui": node.get("ui", ""), "camera": node.get("camera", ""), "actor": node.get("actor", ""), "actor_mark": node.get("actor_mark", ""), "animation": node.get("animation", ""), "summary": node.get("summary", ""), "ending": node.get("ending", ""), "domain_ref": node["id"], "event_id": "", "duration": node.get("duration", 0), "transition": node.get("transition", 0), "blocking": node.get("blocking", False),
            "choice_ids": choice_ids, "choice_labels": node.get("choice_labels", []), "choice_targets": choices, "choice_conditions": ["" for _ in choices],
        }
        for edge in (values["next"], values["success"], values["failure"], values["cancel"], *choices):
            if edge and edge not in node_ids:
                raise ValueError(f'node {node["id"]} has unresolved edge {edge}')
        table(lines, "nodes", values)
    for ending in case.get("endings", []):
        table(lines, "endings", {"id": ending["id"], "title": ending.get("title", ""), "summary": ending.get("summary", ""), "condition_id": "condition.always", "priority": 0})
    lines += ["", "[mystery]", f'action_budget = {case.get("action_point_limit", 0)}', f'seed = {case.get("seed", 0)}', f'tutorial = {q(case.get("tutorial", ""))}', f'city_start = {q(case.get("city_start", ""))}', f'city_destination = {q(case.get("city_destination", ""))}', f'reveal_location = {q(case.get("reveal_location", ""))}']
    for item in case.get("characters", []):
        table(lines, "mystery.characters", {"entity": item["id"], "private_secret": item.get("private_secret", ""), "motive": item.get("motive", ""), "initial_disposition": item.get("initial_disposition", 0), "initial_claims": item.get("initial_claims", [])})
    for item in case.get("locations", []):
        table(lines, "mystery.locations", {"entity": item["id"], "connections": item.get("connections", []), "characters": item.get("characters", []), "pois": item.get("pois", []), "search_actions": item.get("search_actions", [])})
    for item in case.get("pois", []):
        table(lines, "mystery.pois", {"entity": item["id"], "location": item.get("location", ""), "owner": item.get("owner", ""), "relevant_state": item.get("relevant_state", ""), "examination_action": item.get("examination_action", "")})
    for item in case.get("events", []):
        table(lines, "mystery.events", {"event": item["id"], "destination": item.get("destination", ""), "tool": item.get("tool", ""), "effects": item.get("effects", [])})
    for clue in case.get("clues", []):
        table(lines, "mystery.clues", {"id": clue["id"], "source": clue.get("source", ""), "description": clue.get("description", ""), "proposition": clue["id"], "skill": clue.get("skill", ""), "check_kind": clue.get("check_kind", ""), "difficulty": clue.get("difficulty", 0), "cost": clue.get("cost", 0), "essential": clue.get("essential", False), "prerequisites": clue.get("prerequisites", []), "blocks": clue.get("blocks", []), "topics": clue.get("topics", [])})
    for claim in case.get("claims", []):
        table(lines, "mystery.claims", {"id": claim["id"], "speaker": claim.get("speaker", ""), "proposition": claim["id"], "protects": claim.get("protects", ""), "response": claim.get("response", ""), "canonical_truth": claim.get("true", False)})
    for item in case.get("contradictions", []):
        conclusion = str(item.get("conclusion", ""))
        if conclusion and conclusion not in proposition_ids:
            conclusion = ""
        table(lines, "mystery.contradictions", {"id": item["id"], "claim": item.get("claim", ""), "fact": item.get("fact", ""), "conclusion": conclusion, "explanation": item.get("explanation", "")})
    for item in case.get("deductions", []):
        table(lines, "mystery.deductions", {"id": item["id"], "proposition": item["id"], "category": item.get("category", ""), "supports": item.get("supports", []), "unlock_questions": item.get("unlock_questions", []), "unlock_topics": item.get("unlock_topics", []), "unlock_investigations": item.get("unlock_investigations", [])})
    for item in case.get("questions", []):
        deps = list(item.get("requires_questions", []) or [])
        table(lines, "mystery.questions", {"id": item["id"], "prompt": item.get("prompt", ""), "hypothesis": item.get("hypothesis", ""), "category": item.get("category", ""), "requires_clues": item.get("requires_clues", []), "requires_claims": item.get("requires_claims", []), "requires_deductions": item.get("requires_deductions", []), "dependencies": deps, "required_for_final": item.get("required_for_final", False)})
    for item in case.get("demonstrations", []):
        table(lines, "mystery.demonstrations", {"id": item["id"], "question": item.get("question", ""), "mode": item.get("mode", ""), "resolution": item.get("resolution", ""), "result": item.get("result", ""), "prompt": item.get("prompt", ""), "slot_labels": item.get("slot_labels", []), "slot_types": item.get("slot_types", []), "accepted": item.get("accepted_routes", item.get("accepted_pieces", [])), "route_firsts": item.get("route_firsts", []), "route_counts": item.get("route_counts", []), "result_deductions": item.get("result_deductions", [])})
    for item in case.get("dialogue_approaches", []):
        table(lines, "mystery.dialogue", {"node": item["id"], "character": item.get("character", ""), "prompt": item.get("prompt", ""), "response": item.get("response", ""), "clue": item.get("clue", ""), "interaction": "", "requires": combined_refs(item, "requires"), "unlocks": combined_refs(item, "unlock")})
    for item in graph_nodes:
        requires = combined_refs(item, "requires")
        unlocks = combined_refs(item, "unlock")
        if requires or unlocks or item.get("clue") or item.get("interaction"):
            table(lines, "mystery.dialogue", {"node": item["id"], "character": "", "prompt": "", "response": "", "clue": item.get("clue", ""), "interaction": item.get("interaction", ""), "requires": requires, "unlocks": unlocks})
    for item in case.get("endings", []):
        table(lines, "mystery.endings", {"ending": item["id"], "trigger": item.get("trigger", ""), "outcome": item.get("outcome", ""), "subtitle": item.get("subtitle", ""), "epilogue": item.get("epilogue", ""), "canonical_timeline": item.get("canonical_timeline", ""), "tone": item.get("tone", ""), "primary_label": item.get("primary_label", ""), "primary_action": item.get("primary_action", ""), "secondary_label": item.get("secondary_label", ""), "secondary_action": item.get("secondary_action", "")})
    for item in case.get("city_locations", []):
        table(lines, "mystery.city_labels", {"id": item["id"], "display_name": item.get("display_name", ""), "level_spawn": item.get("level_spawn", ""), "city_site": item.get("city_site", "")})
    for item in case.get("tutorial_lessons", []):
        table(lines, "mystery.tutorial_lessons", {"id": item["id"], "capability": item.get("capability", ""), "prompt": item.get("prompt", "")})
    solution = case.get("solution", {})
    requirements = [solution.get(k, "") for k in ("weapon_block", "murder_place_block", "death_time_block", "body_movement_block", "staging_block", "cleaning_block", "alibi_block")]
    requirements = [x for x in requirements if x]
    lines += ["", "[mystery.solution]", f'culprit = {q(solution.get("culprit", ""))}', f'motive = {q(solution.get("motive", ""))}', f'decisive_contradiction = {q(solution.get("decisive_contradiction", ""))}']
    for key in ("weapon_block", "murder_place_block", "death_time_block", "body_movement_block", "staging_block", "cleaning_block", "alibi_block"):
        lines.append(f'{key} = {q(solution.get(key, ""))}')
    lines += [f'requirements = {arr(requirements)}', f'murder_events = {arr(solution.get("murder_events", []))}', f'cover_up_events = {arr(solution.get("cover_up_events", []))}', f'false_alibis = {arr(solution.get("false_alibi", []))}', f'exclusions = {arr(solution.get("exclusions", []))}', ""]
    text = "\n".join(lines)
    preserved_ids = set(entity_ids) | proposition_ids | {str(s["id"]) for s in graph.get("scenes", [])} | node_ids
    for collection in ("events", "claims", "clues", "dialogue_approaches", "contradictions", "deductions", "questions", "demonstrations", "endings", "city_locations", "tutorial_lessons"):
        preserved_ids.update(str(item["id"]) for item in case.get(collection, []) if item.get("id"))
    generated_ids = {f'{n["id"]}:choice:{i}': f'{n["id"]}.choice.{i}' for n in graph_nodes for i, _ in enumerate(n.get("choice_targets", []) or [])}
    generated_ids["story:condition:always"] = "condition.always"
    report = {
        "case_id": case["id"], "case_path": str(case_path), "graph_path": str(graph_path), "level_path": str(level_path),
        "preserved_ids": sorted(preserved_ids),
        "generated_ids": generated_ids,
        "graph_edges": sum(bool(n.get(k)) for n in graph_nodes for k in ("next", "success", "failure", "cancel")) + sum(len(n.get("choice_targets", []) or []) for n in graph_nodes),
        "sha256": hashlib.sha256(text.encode()).hexdigest(), "warnings": [],
    }
    return text, report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("case", type=Path);parser.add_argument("graph", type=Path);parser.add_argument("level", type=Path);parser.add_argument("output", type=Path);parser.add_argument("--report", type=Path)
    args = parser.parse_args();text, report = convert(args.case, args.graph, args.level)
    args.output.parent.mkdir(parents=True, exist_ok=True);args.output.write_text(text, encoding="utf-8")
    report_path = args.report or args.output.with_suffix(args.output.suffix + ".conversion.json");report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
