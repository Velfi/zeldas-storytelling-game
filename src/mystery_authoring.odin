package main

import "core:fmt"
import "core:mem"

MYSTERY_AUTHORING_HISTORY_LIMIT :: 48
MYSTERY_AUTHORING_MAX_DEPENDENCIES :: 128

Mystery_Authoring_Record_Kind :: enum {
	Setup,
	Character,
	Location,
	POI,
	Event,
	Clue,
	Claim,
	Contradiction,
	Deduction,
	Question,
	Demonstration,
	Dialogue,
	Ending,
	City_Label,
	Tutorial_Lesson,
	Solution,
}
Mystery_Authoring_Command_Kind :: enum {
	Add,
	Update,
	Reorder,
	Rename,
	Remove,
}

Mystery_Authoring_Setup :: struct {
	action_budget:                                              int,
	seed:                                                       u64,
	tutorial_id, city_start, city_destination, reveal_location: string,
}

Mystery_Authoring_Command :: struct {
	kind:            Mystery_Authoring_Command_Kind,
	record_kind:     Mystery_Authoring_Record_Kind,
	id, new_id:      string,
	from, to:        int,
	character:       Mystery_Character_Metadata,
	location:        Mystery_Location_Metadata,
	poi:             Mystery_POI_Metadata,
	event:           Mystery_Event_Metadata,
	clue:            Mystery_Clue,
	claim:           Mystery_Claim,
	contradiction:   Mystery_Contradiction,
	deduction:       Mystery_Deduction,
	question:        Mystery_Question,
	demonstration:   Mystery_Demonstration,
	dialogue:        Mystery_Dialogue_Metadata,
	ending:          Mystery_Ending_Metadata,
	city_label:      Mystery_City_Label,
	tutorial_lesson: Mystery_Tutorial_Lesson,
	setup:           Mystery_Authoring_Setup,
	solution:        Mystery_Solution,
}

Mystery_Authoring_Dependency :: struct {
	record_kind, record_id, field: string,
}
Mystery_Authoring_Preview :: struct {
	kind:             Mystery_Authoring_Record_Kind,
	id:               string,
	dependencies:     [MYSTERY_AUTHORING_MAX_DEPENDENCIES]Mystery_Authoring_Dependency,
	dependency_count: int,
	truncated:        bool,
}
Mystery_Authoring_Result :: struct {
	ok:         bool,
	message:    string,
	revision:   u64,
	validation: Story_Validation,
	blocked_by: Mystery_Authoring_Preview,
}
Mystery_Authoring_History :: struct {
	undo, redo: [dynamic]Story_Project,
}

mystery_authoring_character_index :: proc(payload: ^Mystery_Project, id: string) -> int {for item, i in payload.characters do if item.entity_id == id do return i
	return -1}
mystery_authoring_location_index :: proc(payload: ^Mystery_Project, id: string) -> int {for item, i in payload.locations do if item.entity_id == id do return i
	return -1}
mystery_authoring_poi_index :: proc(payload: ^Mystery_Project, id: string) -> int {for item, i in payload.pois do if item.entity_id == id do return i
	return -1}
mystery_authoring_event_index :: proc(payload: ^Mystery_Project, id: string) -> int {for item, i in payload.events do if item.event_id == id do return i
	return -1}
mystery_authoring_contradiction_index :: proc(payload: ^Mystery_Project, id: string) -> int {for item, i in payload.contradictions do if item.id == id do return i
	return -1}
mystery_authoring_demonstration_index :: proc(payload: ^Mystery_Project, id: string) -> int {for item, i in payload.demonstrations do if item.id == id do return i
	return -1}
mystery_authoring_dialogue_index :: proc(payload: ^Mystery_Project, id: string) -> int {for item, i in payload.dialogue do if item.node_id == id do return i
	return -1}
mystery_authoring_ending_index :: proc(payload: ^Mystery_Project, id: string) -> int {for item, i in payload.endings do if item.ending_id == id do return i
	return -1}
mystery_authoring_city_label_index :: proc(payload: ^Mystery_Project, id: string) -> int {for item, i in payload.city_labels do if item.id == id do return i
	return -1}
mystery_authoring_tutorial_lesson_index :: proc(payload: ^Mystery_Project, id: string) -> int {for item, i in payload.tutorial_lessons do if item.id == id do return i
	return -1}

mystery_authoring_index :: proc(
	payload: ^Mystery_Project,
	kind: Mystery_Authoring_Record_Kind,
	id: string,
) -> int {
	switch kind {case .Setup:
		return id == "setup" ? 0 : -1; case .Character:
		return mystery_authoring_character_index(payload, id); case .Location:
		return mystery_authoring_location_index(payload, id); case .POI:
		return mystery_authoring_poi_index(payload, id); case .Event:
		return mystery_authoring_event_index(payload, id); case .Clue:
		return mystery_clue_index(payload, id); case .Claim:
		return mystery_claim_index(payload, id); case .Contradiction:
		return mystery_authoring_contradiction_index(payload, id); case .Deduction:
		return mystery_deduction_index(payload, id); case .Question:
		return mystery_question_index(payload, id); case .Demonstration:
		return mystery_authoring_demonstration_index(payload, id); case .Dialogue:
		return mystery_authoring_dialogue_index(payload, id); case .Ending:
		return mystery_authoring_ending_index(payload, id); case .City_Label:
		return mystery_authoring_city_label_index(payload, id); case .Tutorial_Lesson:
		return mystery_authoring_tutorial_lesson_index(payload, id); case .Solution:
		return id == "solution" ? 0 : -1}; return -1
}

mystery_authoring_record_id :: proc(command: ^Mystery_Authoring_Command) -> string {switch
	command.record_kind {case .Setup:
		return "setup"; case .Character:
		return command.character.entity_id; case .Location:
		return command.location.entity_id; case .POI:
		return command.poi.entity_id; case .Event:
		return command.event.event_id; case .Clue:
		return command.clue.id; case .Claim:
		return command.claim.id; case .Contradiction:
		return command.contradiction.id; case .Deduction:
		return command.deduction.id; case .Question:
		return command.question.id; case .Demonstration:
		return command.demonstration.id; case .Dialogue:
		return command.dialogue.node_id; case .Ending:
		return command.ending.ending_id; case .City_Label:
		return command.city_label.id; case .Tutorial_Lesson:
		return command.tutorial_lesson.id; case .Solution:
		return "solution"}
	return ""}

mystery_authoring_array_append :: proc(
	payload: ^Mystery_Project,
	values: []$T,
	item: T,
) -> []T {context.allocator = mem.dynamic_arena_allocator(&payload.arena); result := make(
		[]T,
		len(values) + 1,
	)
	copy(result, values)
	result[len(values)] = item
	return result}
mystery_authoring_array_remove :: proc(
	payload: ^Mystery_Project,
	values: []$T,
	index: int,
) -> []T {context.allocator = mem.dynamic_arena_allocator(&payload.arena); result := make(
		[]T,
		len(values) - 1,
	)
	if index > 0 do copy(result[:index], values[:index])
	if index < len(values) - 1 do copy(result[index:], values[index + 1:])
	return result}
mystery_authoring_array_reorder :: proc(
	payload: ^Mystery_Project,
	values: []$T,
	from, to: int,
) -> []T {context.allocator = mem.dynamic_arena_allocator(&payload.arena); result := make(
		[]T,
		len(values),
	)
	copy(result, values)
	item := result[from]
	if from < to {for i in from ..< to do result[i] = result[i + 1]}
	else {for i := from; i > to; i -= 1 do result[i] = result[i - 1]}
	result[to] = item
	return result}

mystery_authoring_preview_add :: proc(
	result: ^Mystery_Authoring_Preview,
	kind, id, field: string,
) {if result.dependency_count >= len(result.dependencies) {result.truncated = true; return}
	result.dependencies[result.dependency_count] = {kind, id, field}
	result.dependency_count += 1}
mystery_authoring_refs_have :: proc(
	values: [MYSTERY_MAX_REFS]string,
	count: int,
	id: string,
) -> bool {for i in 0 ..< count do if values[i] == id do return true; return false}
mystery_authoring_refs_rename :: proc(
	values: ^[MYSTERY_MAX_REFS]string,
	count: int,
	old, new: string,
) {for i in 0 ..< count do if values[i] == old do values[i] = new}

mystery_authoring_dependency_preview :: proc(
	project: ^Story_Project,
	kind: Mystery_Authoring_Record_Kind,
	id: string,
) -> Mystery_Authoring_Preview {
	result := Mystery_Authoring_Preview {
		kind = kind,
		id   = id,
	}; payload := mystery_payload(project); if payload == nil || id == "" do return result
	#partial switch kind {
	case .Setup, .Solution:
	case .Character:
		for item in payload.clues do if item.source_id == id do mystery_authoring_preview_add(&result, "clue", item.id, "source_id")
		for item in payload.locations do if mystery_authoring_refs_have(item.characters, item.character_count, id) do mystery_authoring_preview_add(&result, "location", item.entity_id, "characters")
		for item in payload.pois do if item.owner_id == id do mystery_authoring_preview_add(&result, "poi", item.entity_id, "owner_id")
		for item in payload.claims do if item.speaker_id == id do mystery_authoring_preview_add(&result, "claim", item.id, "speaker_id")
		for item in payload.dialogue do if item.character_id == id do mystery_authoring_preview_add(&result, "dialogue", item.node_id, "character_id")
		if payload.solution.culprit_id == id do mystery_authoring_preview_add(&result, "solution", "solution", "culprit_id")
		if mystery_authoring_refs_have(payload.solution.exclusions, payload.solution.exclusion_count, id) do mystery_authoring_preview_add(&result, "solution", "solution", "exclusions")
	case .Location:
		for item in payload.clues do if item.source_id == id do mystery_authoring_preview_add(&result, "clue", item.id, "source_id")
		for item in payload.locations do if item.entity_id != id && mystery_authoring_refs_have(item.connections, item.connection_count, id) do mystery_authoring_preview_add(&result, "location", item.entity_id, "connections")
		for item in payload.pois do if item.location_id == id do mystery_authoring_preview_add(&result, "poi", item.entity_id, "location_id")
		for item in payload.events do if item.destination_id == id do mystery_authoring_preview_add(&result, "event", item.event_id, "destination_id")
		if payload.reveal_location == id do mystery_authoring_preview_add(&result, "mystery", "setup", "reveal_location")
	case .POI:
		for item in payload.locations {if mystery_authoring_refs_have(item.pois, item.poi_count, id) do mystery_authoring_preview_add(&result, "location", item.entity_id, "pois"); if mystery_authoring_refs_have(item.search_actions, item.search_action_count, id) do mystery_authoring_preview_add(&result, "location", item.entity_id, "search_actions")}
		for item in payload.clues do if item.source_id == id do mystery_authoring_preview_add(&result, "clue", item.id, "source_id")
	case .Event:
		if mystery_authoring_refs_have(payload.solution.murder_events, payload.solution.murder_event_count, id) do mystery_authoring_preview_add(&result, "solution", "solution", "murder_events")
		if mystery_authoring_refs_have(payload.solution.cover_up_events, payload.solution.cover_up_event_count, id) do mystery_authoring_preview_add(&result, "solution", "solution", "cover_up_events")
	case .Clue:
		for item in payload.clues do if item.id != id && mystery_authoring_refs_have(item.prerequisites, item.prerequisite_count, id) do mystery_authoring_preview_add(&result, "clue", item.id, "prerequisites")
		for item in payload.questions do if mystery_authoring_refs_have(item.requires_clues, item.require_clue_count, id) do mystery_authoring_preview_add(&result, "question", item.id, "requires_clues")
		for item in payload.deductions do if mystery_authoring_refs_have(item.supports, item.support_count, id) do mystery_authoring_preview_add(&result, "deduction", item.id, "supports")
		for item in payload.dialogue {if item.clue_id == id do mystery_authoring_preview_add(&result, "dialogue", item.node_id, "clue_id"); if mystery_authoring_refs_have(item.requires, item.require_count, id) || mystery_authoring_refs_have(item.unlocks, item.unlock_count, id) do mystery_authoring_preview_add(&result, "dialogue", item.node_id, "knowledge refs")}
		for item in payload.demonstrations do if mystery_authoring_refs_have(item.accepted, item.accepted_count, id) do mystery_authoring_preview_add(&result, "demonstration", item.id, "accepted")
		if mystery_authoring_refs_have(payload.solution.requirements, payload.solution.requirement_count, id) do mystery_authoring_preview_add(&result, "solution", "solution", "requirements")
	case .Claim:
		for item in payload.characters do if mystery_authoring_refs_have(item.initial_claims, item.initial_claim_count, id) do mystery_authoring_preview_add(&result, "character", item.entity_id, "initial_claims")
		for item in payload.contradictions do if item.claim_id == id do mystery_authoring_preview_add(&result, "contradiction", item.id, "claim_id")
		for item in payload.questions do if mystery_authoring_refs_have(item.requires_claims, item.require_claim_count, id) do mystery_authoring_preview_add(&result, "question", item.id, "requires_claims")
		for item in payload.deductions do if mystery_authoring_refs_have(item.supports, item.support_count, id) do mystery_authoring_preview_add(&result, "deduction", item.id, "supports")
		for item in payload.dialogue do if mystery_authoring_refs_have(item.requires, item.require_count, id) || mystery_authoring_refs_have(item.unlocks, item.unlock_count, id) do mystery_authoring_preview_add(&result, "dialogue", item.node_id, "knowledge refs")
		if mystery_authoring_refs_have(payload.solution.requirements, payload.solution.requirement_count, id) do mystery_authoring_preview_add(&result, "solution", "solution", "requirements")
		if mystery_authoring_refs_have(payload.solution.false_alibis, payload.solution.false_alibi_count, id) do mystery_authoring_preview_add(&result, "solution", "solution", "false_alibis")
	case .Contradiction:
		if payload.solution.decisive_contradiction_id == id do mystery_authoring_preview_add(&result, "solution", "solution", "decisive_contradiction_id")
	case .Deduction:
		for item in payload.deductions do if item.id != id && mystery_authoring_refs_have(item.supports, item.support_count, id) do mystery_authoring_preview_add(&result, "deduction", item.id, "supports")
		for item in payload.questions do if mystery_authoring_refs_have(item.requires_deductions, item.require_deduction_count, id) do mystery_authoring_preview_add(&result, "question", item.id, "requires_deductions")
		for item in payload.demonstrations {if mystery_authoring_refs_have(item.accepted, item.accepted_count, id) do mystery_authoring_preview_add(&result, "demonstration", item.id, "accepted"); if mystery_authoring_refs_have(item.result_deductions, item.result_count, id) do mystery_authoring_preview_add(&result, "demonstration", item.id, "result_deductions")}
		for item in payload.dialogue do if mystery_authoring_refs_have(item.requires, item.require_count, id) || mystery_authoring_refs_have(item.unlocks, item.unlock_count, id) do mystery_authoring_preview_add(&result, "dialogue", item.node_id, "knowledge refs")
		if payload.solution.motive_id == id do mystery_authoring_preview_add(&result, "solution", "solution", "motive_id")
		if mystery_authoring_refs_have(payload.solution.requirements, payload.solution.requirement_count, id) do mystery_authoring_preview_add(&result, "solution", "solution", "requirements")
	case .Question:
		for item in payload.deductions do if mystery_authoring_refs_have(item.unlock_questions, item.unlock_question_count, id) do mystery_authoring_preview_add(&result, "deduction", item.id, "unlock_questions")
		for item in payload.questions do if item.id != id && mystery_authoring_refs_have(item.dependencies, item.dependency_count, id) do mystery_authoring_preview_add(&result, "question", item.id, "dependencies")
		for item in payload.demonstrations do if item.question_id == id do mystery_authoring_preview_add(&result, "demonstration", item.id, "question_id")
	case .Demonstration:
	case .Dialogue:
	case .Ending:
	case .City_Label:
		if payload.city_destination == id do mystery_authoring_preview_add(&result, "mystery", "setup", "city_destination")
		if payload.city_start == id do mystery_authoring_preview_add(&result, "mystery", "setup", "city_start")
	case .Tutorial_Lesson:
		if payload.tutorial_id == id do mystery_authoring_preview_add(&result, "mystery", "setup", "tutorial_id")
	}
	return result
}

mystery_authoring_rename_refs :: proc(
	payload: ^Mystery_Project,
	kind: Mystery_Authoring_Record_Kind,
	old, new: string,
) {
	#partial switch kind {
	case .Setup, .Solution:
	case .Character:
		for &item in payload.clues do if item.source_id == old do item.source_id = new
		for &item in payload.locations do mystery_authoring_refs_rename(&item.characters, item.character_count, old, new)
		for &item in payload.pois do if item.owner_id == old do item.owner_id = new
		for &item in payload.claims do if item.speaker_id == old do item.speaker_id = new
		for &item in payload.dialogue do if item.character_id == old do item.character_id = new
		if payload.solution.culprit_id == old do payload.solution.culprit_id = new
		mystery_authoring_refs_rename(
			&payload.solution.exclusions,
			payload.solution.exclusion_count,
			old,
			new,
		)
	case .Location:
		for &item in payload.clues do if item.source_id == old do item.source_id = new
		for &item in payload.locations do mystery_authoring_refs_rename(&item.connections, item.connection_count, old, new)
		for &item in payload.pois do if item.location_id == old do item.location_id = new
		for &item in payload.events do if item.destination_id == old do item.destination_id = new
		if payload.reveal_location == old do payload.reveal_location = new
	case .POI:
		for &item in payload.locations {
			mystery_authoring_refs_rename(&item.pois, item.poi_count, old, new)
			mystery_authoring_refs_rename(
				&item.search_actions,
				item.search_action_count,
				old,
				new,
			)}
		for &item in payload.clues do if item.source_id == old do item.source_id = new
	case .Event:
		mystery_authoring_refs_rename(
			&payload.solution.murder_events,
			payload.solution.murder_event_count,
			old,
			new,
		)
		mystery_authoring_refs_rename(
			&payload.solution.cover_up_events,
			payload.solution.cover_up_event_count,
			old,
			new,
		)
	case .Clue:
		for &item in payload.clues do mystery_authoring_refs_rename(&item.prerequisites, item.prerequisite_count, old, new)
		for &item in payload.deductions do mystery_authoring_refs_rename(&item.supports, item.support_count, old, new)
		for &item in payload.questions do mystery_authoring_refs_rename(&item.requires_clues, item.require_clue_count, old, new)
		for &item in payload.dialogue {if item.clue_id == old do item.clue_id = new
			mystery_authoring_refs_rename(&item.requires, item.require_count, old, new)
			mystery_authoring_refs_rename(&item.unlocks, item.unlock_count, old, new)}
		for &item in payload.demonstrations do mystery_authoring_refs_rename(&item.accepted, item.accepted_count, old, new)
		mystery_authoring_refs_rename(
			&payload.solution.requirements,
			payload.solution.requirement_count,
			old,
			new,
		)
	case .Claim:
		for &item in payload.characters do mystery_authoring_refs_rename(&item.initial_claims, item.initial_claim_count, old, new)
		for &item in payload.contradictions do if item.claim_id == old do item.claim_id = new
		for &item in payload.deductions do mystery_authoring_refs_rename(&item.supports, item.support_count, old, new)
		for &item in payload.questions do mystery_authoring_refs_rename(&item.requires_claims, item.require_claim_count, old, new)
		for &item in payload.dialogue {mystery_authoring_refs_rename(&item.requires, item.require_count, old, new)
			mystery_authoring_refs_rename(&item.unlocks, item.unlock_count, old, new)}
		mystery_authoring_refs_rename(
			&payload.solution.requirements,
			payload.solution.requirement_count,
			old,
			new,
		)
		mystery_authoring_refs_rename(
			&payload.solution.false_alibis,
			payload.solution.false_alibi_count,
			old,
			new,
		)
	case .Contradiction:
		if payload.solution.decisive_contradiction_id == old do payload.solution.decisive_contradiction_id = new
	case .Deduction:
		for &item in payload.deductions do mystery_authoring_refs_rename(&item.supports, item.support_count, old, new)
		for &item in payload.questions do mystery_authoring_refs_rename(&item.requires_deductions, item.require_deduction_count, old, new)
		for &item in payload.demonstrations {mystery_authoring_refs_rename(&item.accepted, item.accepted_count, old, new)
			mystery_authoring_refs_rename(&item.result_deductions, item.result_count, old, new)}
		for &item in payload.dialogue {mystery_authoring_refs_rename(&item.requires, item.require_count, old, new)
			mystery_authoring_refs_rename(&item.unlocks, item.unlock_count, old, new)}
		if payload.solution.motive_id == old do payload.solution.motive_id = new
		mystery_authoring_refs_rename(
			&payload.solution.requirements,
			payload.solution.requirement_count,
			old,
			new,
		)
	case .Question:
		for &item in payload.deductions do mystery_authoring_refs_rename(&item.unlock_questions, item.unlock_question_count, old, new)
		for &item in payload.questions do mystery_authoring_refs_rename(&item.dependencies, item.dependency_count, old, new)
		for &item in payload.demonstrations do if item.question_id == old do item.question_id = new
	case .Demonstration:
	case .Dialogue:
	case .Ending:
	case .City_Label:
		if payload.city_destination == old do payload.city_destination = new
		if payload.city_start == old do payload.city_start = new
	case .Tutorial_Lesson:
		if payload.tutorial_id == old do payload.tutorial_id = new
	}
}

mystery_authoring_apply_raw :: proc(
	project: ^Story_Project,
	command: ^Mystery_Authoring_Command,
	result: ^Mystery_Authoring_Result,
) -> bool {
	payload := mystery_payload(project); if payload == nil do return false
	if command.record_kind ==
	   .Setup {if command.kind != .Update do return false; payload.action_budget = command.setup.action_budget; payload.seed = command.setup.seed; payload.tutorial_id = command.setup.tutorial_id; payload.city_start = command.setup.city_start; payload.city_destination = command.setup.city_destination; payload.reveal_location = command.setup.reveal_location; return true}
	if command.record_kind ==
	   .Solution {if command.kind != .Update do return false; payload.solution = command.solution; return true}
	if command.kind ==
	   .Reorder {if command.from < 0 || command.to < 0 do return false; #partial switch command.record_kind {
		case .Character:
			if command.from >= len(payload.characters) || command.to >= len(payload.characters) do return false
			payload.characters = mystery_authoring_array_reorder(
				payload,
				payload.characters,
				command.from,
				command.to,
			)
		case .Location:
			if command.from >= len(payload.locations) || command.to >= len(payload.locations) do return false
			payload.locations = mystery_authoring_array_reorder(
				payload,
				payload.locations,
				command.from,
				command.to,
			)
		case .POI:
			if command.from >= len(payload.pois) || command.to >= len(payload.pois) do return false
			payload.pois = mystery_authoring_array_reorder(
				payload,
				payload.pois,
				command.from,
				command.to,
			)
		case .Event:
			if command.from >= len(payload.events) || command.to >= len(payload.events) do return false
			payload.events = mystery_authoring_array_reorder(
				payload,
				payload.events,
				command.from,
				command.to,
			)
		case .Clue:
			if command.from >= len(payload.clues) || command.to >= len(payload.clues) do return false
			payload.clues = mystery_authoring_array_reorder(
				payload,
				payload.clues,
				command.from,
				command.to,
			)
		case .Claim:
			if command.from >= len(payload.claims) || command.to >= len(payload.claims) do return false
			payload.claims = mystery_authoring_array_reorder(
				payload,
				payload.claims,
				command.from,
				command.to,
			)
		case .Contradiction:
			if command.from >= len(payload.contradictions) || command.to >= len(payload.contradictions) do return false
			payload.contradictions = mystery_authoring_array_reorder(
				payload,
				payload.contradictions,
				command.from,
				command.to,
			)
		case .Deduction:
			if command.from >= len(payload.deductions) || command.to >= len(payload.deductions) do return false
			payload.deductions = mystery_authoring_array_reorder(
				payload,
				payload.deductions,
				command.from,
				command.to,
			)
		case .Question:
			if command.from >= len(payload.questions) || command.to >= len(payload.questions) do return false
			payload.questions = mystery_authoring_array_reorder(
				payload,
				payload.questions,
				command.from,
				command.to,
			)
		case .Demonstration:
			if command.from >= len(payload.demonstrations) || command.to >= len(payload.demonstrations) do return false
			payload.demonstrations = mystery_authoring_array_reorder(
				payload,
				payload.demonstrations,
				command.from,
				command.to,
			)
		case .Dialogue:
			if command.from >= len(payload.dialogue) || command.to >= len(payload.dialogue) do return false
			payload.dialogue = mystery_authoring_array_reorder(
				payload,
				payload.dialogue,
				command.from,
				command.to,
			)
		case .Ending:
			if command.from >= len(payload.endings) || command.to >= len(payload.endings) do return false
			payload.endings = mystery_authoring_array_reorder(
				payload,
				payload.endings,
				command.from,
				command.to,
			)
		case .City_Label:
			if command.from >= len(payload.city_labels) || command.to >= len(payload.city_labels) do return false
			payload.city_labels = mystery_authoring_array_reorder(
				payload,
				payload.city_labels,
				command.from,
				command.to,
			)
		case .Tutorial_Lesson:
			if command.from >= len(payload.tutorial_lessons) || command.to >= len(payload.tutorial_lessons) do return false
			payload.tutorial_lessons = mystery_authoring_array_reorder(
				payload,
				payload.tutorial_lessons,
				command.from,
				command.to,
			)
		case:
			return false}; return true}
	if command.kind ==
	   .Rename {index := mystery_authoring_index(payload, command.record_kind, command.id); if !story_authoring_valid_id(command.new_id) || index < 0 || mystery_authoring_index(payload, command.record_kind, command.new_id) >= 0 do return false; if command.record_kind == .Character || command.record_kind == .Location {if !story_authoring_replace_id(project, .Entity, command.id, command.new_id) do return false}; #partial switch command.record_kind {case .Character:
			payload.characters[index].entity_id = command.new_id; case .Location:
			payload.locations[index].entity_id = command.new_id; case .POI:
			payload.pois[index].entity_id = command.new_id; case .Event:
			payload.events[index].event_id = command.new_id; case .Clue:
			payload.clues[index].id = command.new_id; case .Claim:
			payload.claims[index].id = command.new_id; case .Contradiction:
			payload.contradictions[index].id = command.new_id; case .Deduction:
			payload.deductions[index].id = command.new_id; case .Question:
			payload.questions[index].id = command.new_id; case .Demonstration:
			payload.demonstrations[index].id = command.new_id; case .Dialogue:
			payload.dialogue[index].node_id = command.new_id; case .Ending:
			payload.endings[index].ending_id = command.new_id; case .City_Label:
			payload.city_labels[index].id = command.new_id; case .Tutorial_Lesson:
			payload.tutorial_lessons[index].id = command.new_id; case:
			return(
				false \
			)}; mystery_authoring_rename_refs(payload, command.record_kind, command.id, command.new_id); return true}
	if command.kind ==
	   .Remove {result.blocked_by = mystery_authoring_dependency_preview(project, command.record_kind, command.id); if result.blocked_by.dependency_count > 0 || result.blocked_by.truncated do return false; index := mystery_authoring_index(payload, command.record_kind, command.id); if index < 0 do return false; #partial switch command.record_kind {case .Character:
			payload.characters = mystery_authoring_array_remove(
				payload,
				payload.characters,
				index,
			); case .Location:
			payload.locations = mystery_authoring_array_remove(
				payload,
				payload.locations,
				index,
			); case .POI:
			payload.pois = mystery_authoring_array_remove(
				payload,
				payload.pois,
				index,
			); case .Event:
			payload.events = mystery_authoring_array_remove(
				payload,
				payload.events,
				index,
			); case .Clue:
			payload.clues = mystery_authoring_array_remove(
				payload,
				payload.clues,
				index,
			); case .Claim:
			payload.claims = mystery_authoring_array_remove(
				payload,
				payload.claims,
				index,
			); case .Contradiction:
			payload.contradictions = mystery_authoring_array_remove(
				payload,
				payload.contradictions,
				index,
			); case .Deduction:
			payload.deductions = mystery_authoring_array_remove(
				payload,
				payload.deductions,
				index,
			); case .Question:
			payload.questions = mystery_authoring_array_remove(
				payload,
				payload.questions,
				index,
			); case .Demonstration:
			payload.demonstrations = mystery_authoring_array_remove(
				payload,
				payload.demonstrations,
				index,
			); case .Dialogue:
			payload.dialogue = mystery_authoring_array_remove(
				payload,
				payload.dialogue,
				index,
			); case .Ending:
			payload.endings = mystery_authoring_array_remove(
				payload,
				payload.endings,
				index,
			); case .City_Label:
			payload.city_labels = mystery_authoring_array_remove(
				payload,
				payload.city_labels,
				index,
			); case .Tutorial_Lesson:
			payload.tutorial_lessons = mystery_authoring_array_remove(
				payload,
				payload.tutorial_lessons,
				index,
			); case:
			return false}; return true}
	id := mystery_authoring_record_id(
		command,
	); if !story_authoring_valid_id(id) do return false; index := mystery_authoring_index(payload, command.record_kind, id)
	if command.kind ==
	   .Add {if index >= 0 do return false; #partial switch command.record_kind {case .Character:
			payload.characters = mystery_authoring_array_append(
				payload,
				payload.characters,
				command.character,
			); case .Location:
			payload.locations = mystery_authoring_array_append(
				payload,
				payload.locations,
				command.location,
			); case .POI:
			payload.pois = mystery_authoring_array_append(
				payload,
				payload.pois,
				command.poi,
			); case .Event:
			payload.events = mystery_authoring_array_append(
				payload,
				payload.events,
				command.event,
			); case .Clue:
			payload.clues = mystery_authoring_array_append(
				payload,
				payload.clues,
				command.clue,
			); case .Claim:
			payload.claims = mystery_authoring_array_append(
				payload,
				payload.claims,
				command.claim,
			); case .Contradiction:
			payload.contradictions = mystery_authoring_array_append(
				payload,
				payload.contradictions,
				command.contradiction,
			); case .Deduction:
			payload.deductions = mystery_authoring_array_append(
				payload,
				payload.deductions,
				command.deduction,
			); case .Question:
			payload.questions = mystery_authoring_array_append(
				payload,
				payload.questions,
				command.question,
			); case .Demonstration:
			payload.demonstrations = mystery_authoring_array_append(
				payload,
				payload.demonstrations,
				command.demonstration,
			); case .Dialogue:
			payload.dialogue = mystery_authoring_array_append(
				payload,
				payload.dialogue,
				command.dialogue,
			); case .Ending:
			payload.endings = mystery_authoring_array_append(
				payload,
				payload.endings,
				command.ending,
			); case .City_Label:
			payload.city_labels = mystery_authoring_array_append(
				payload,
				payload.city_labels,
				command.city_label,
			); case .Tutorial_Lesson:
			payload.tutorial_lessons = mystery_authoring_array_append(
				payload,
				payload.tutorial_lessons,
				command.tutorial_lesson,
			); case:
			return false}; return true}
	if command.kind ==
	   .Update {if index < 0 do return false; #partial switch command.record_kind {case .Character:
			payload.characters[index] = command.character; case .Location:
			payload.locations[index] = command.location; case .POI:
			payload.pois[index] = command.poi; case .Event:
			payload.events[index] = command.event; case .Clue:
			payload.clues[index] = command.clue; case .Claim:
			payload.claims[index] = command.claim; case .Contradiction:
			payload.contradictions[index] = command.contradiction; case .Deduction:
			payload.deductions[index] = command.deduction; case .Question:
			payload.questions[index] = command.question; case .Demonstration:
			payload.demonstrations[index] = command.demonstration; case .Dialogue:
			payload.dialogue[index] = command.dialogue; case .Ending:
			payload.endings[index] = command.ending; case .City_Label:
			payload.city_labels[index] = command.city_label; case .Tutorial_Lesson:
			payload.tutorial_lessons[index] = command.tutorial_lesson; case:
			return false}; return true}
	return false
}

mystery_authoring_history_clear :: proc(items: ^[dynamic]Story_Project) {for &item in items^ do story_project_destroy(&item)
	delete(items^)
	items^ = nil}
mystery_authoring_history_push :: proc(
	items: ^[dynamic]Story_Project,
	project: ^Story_Project,
) {if len(items^) >= MYSTERY_AUTHORING_HISTORY_LIMIT {story_project_destroy(&items^[0])
		ordered_remove(items, 0)}
	append(items, story_project_clone(project))}
mystery_authoring_history_destroy :: proc(
	history: ^Mystery_Authoring_History,
) {mystery_authoring_history_clear(&history.undo); mystery_authoring_history_clear(&history.redo)
	history^ = {}}

mystery_authoring_apply :: proc(
	project: ^Story_Project,
	history: ^Mystery_Authoring_History,
	commands: []Mystery_Authoring_Command,
) -> Mystery_Authoring_Result {
	result :=
		Mystery_Authoring_Result{}; if project == nil || len(commands) == 0 {result.message = "no mystery authoring commands"; return result}; result.revision = project.revision; working := story_project_clone(project)
	for &command in commands do if !mystery_authoring_apply_raw(&working, &command, &result) {story_project_destroy(&working); result.message = result.blocked_by.dependency_count > 0 ? "remove blocked by mystery dependencies" : "mystery authoring command rejected"; return result}
	working.revision += 1; result.validation = story_project_validate(&working); if !result.validation.ok {story_project_destroy(&working); result.message = "mystery authoring transaction failed validation"; return result}
	// Commands can borrow strings from the current domain arena. Deep-clone the
	// accepted working copy before destroying that arena so committed records
	// always own their text and reference IDs.
	stabilized := story_project_clone(
		&working,
	); story_project_destroy(&working); working = stabilized
	if history !=
	   nil {mystery_authoring_history_push(&history.undo, project); mystery_authoring_history_clear(&history.redo)}; story_project_destroy(project); project^ = working; result.ok = true; result.revision = project.revision; result.message = "mystery authoring transaction committed"; if project == &active_story_project do _ = authoring_invalidate_after_edit(.Mystery, project.revision); return result
}

mystery_authoring_undo :: proc(
	project: ^Story_Project,
	history: ^Mystery_Authoring_History,
) -> bool {if project == nil || history == nil || len(history.undo) == 0 do return false
	mystery_authoring_history_push(&history.redo, project)
	replacement := history.undo[len(history.undo) - 1]
	ordered_remove(&history.undo, len(history.undo) - 1)
	story_project_destroy(project)
	project^ = replacement
	if project == &active_story_project do _ = authoring_invalidate_after_edit(.Mystery, project.revision)
	return true}
mystery_authoring_redo :: proc(
	project: ^Story_Project,
	history: ^Mystery_Authoring_History,
) -> bool {if project == nil || history == nil || len(history.redo) == 0 do return false
	mystery_authoring_history_push(&history.undo, project)
	replacement := history.redo[len(history.redo) - 1]
	ordered_remove(&history.redo, len(history.redo) - 1)
	story_project_destroy(project)
	project^ = replacement
	if project == &active_story_project do _ = authoring_invalidate_after_edit(.Mystery, project.revision)
	return true}
mystery_authoring_result_destroy :: proc(
	result: ^Mystery_Authoring_Result,
) {story_validation_destroy(&result.validation); result^ = {}}

// StoryCore identities are also referenced by MysteryDomain payloads.  Keep
// this adapter beside the domain command implementation so the generic Story
// authoring service can preview deletes and perform one atomic cross-domain
// rename without knowing the Mystery schema.
mystery_authoring_core_dependency_preview :: proc(
	project: ^Story_Project,
	kind: Story_Authoring_Record_Kind,
	id: string,
	preview: ^Story_Authoring_Dependency_Preview,
) {
	payload := mystery_payload(project); if payload == nil || preview == nil || id == "" do return
	#partial switch kind {
	case .Entity:
		for item in payload.characters {if item.entity_id == id do story_authoring_dependency_add(preview, "mystery.character", item.entity_id, "entity_id")}
		for &item in payload.locations {if item.entity_id == id do story_authoring_dependency_add(preview, "mystery.location", item.entity_id, "entity_id"); for value in item.characters[:item.character_count] do if value == id do story_authoring_dependency_add(preview, "mystery.location", item.entity_id, "characters")}
		for item in payload.pois {if item.entity_id == id do story_authoring_dependency_add(preview, "mystery.poi", item.entity_id, "entity_id"); if item.location_id == id do story_authoring_dependency_add(preview, "mystery.poi", item.entity_id, "location_id"); if item.owner_id == id do story_authoring_dependency_add(preview, "mystery.poi", item.entity_id, "owner_id")}
		for item in payload.events {if item.destination_id == id do story_authoring_dependency_add(preview, "mystery.event", item.event_id, "destination_id"); if item.tool_id == id do story_authoring_dependency_add(preview, "mystery.event", item.event_id, "tool_id")}
		for item in payload.clues do if item.source_id == id do story_authoring_dependency_add(preview, "mystery.clue", item.id, "source_id")
		for item in payload.claims do if item.speaker_id == id do story_authoring_dependency_add(preview, "mystery.claim", item.id, "speaker_id")
		for item in payload.dialogue do if item.character_id == id do story_authoring_dependency_add(preview, "mystery.dialogue", item.node_id, "character_id")
		if payload.solution.culprit_id == id do story_authoring_dependency_add(preview, "mystery.solution", "solution", "culprit_id")
		for value in payload.solution.exclusions[:payload.solution.exclusion_count] do if value == id do story_authoring_dependency_add(preview, "mystery.solution", "solution", "exclusions")
	case .Proposition:
		for item in payload.clues do if item.proposition_id == id do story_authoring_dependency_add(preview, "mystery.clue", item.id, "proposition_id")
		for item in payload.claims do if item.proposition_id == id do story_authoring_dependency_add(preview, "mystery.claim", item.id, "proposition_id")
		for item in payload.contradictions do if item.conclusion_id == id do story_authoring_dependency_add(preview, "mystery.contradiction", item.id, "conclusion_id")
		for item in payload.deductions do if item.proposition_id == id do story_authoring_dependency_add(preview, "mystery.deduction", item.id, "proposition_id")
		for item in payload.questions do if item.hypothesis_id == id do story_authoring_dependency_add(preview, "mystery.question", item.id, "hypothesis_id")
	case .Fact:
		for item in payload.contradictions do if item.fact_id == id do story_authoring_dependency_add(preview, "mystery.contradiction", item.id, "fact_id")
	case .Event:
		for item in payload.events do if item.event_id == id do story_authoring_dependency_add(preview, "mystery.event", item.event_id, "event_id")
		for value in payload.solution.murder_events[:payload.solution.murder_event_count] do if value == id do story_authoring_dependency_add(preview, "mystery.solution", "solution", "murder_events")
		for value in payload.solution.cover_up_events[:payload.solution.cover_up_event_count] do if value == id do story_authoring_dependency_add(preview, "mystery.solution", "solution", "cover_up_events")
	case .Ending:
		for item in payload.endings do if item.ending_id == id do story_authoring_dependency_add(preview, "mystery.ending", item.ending_id, "ending_id")
	case:
	}
}

mystery_authoring_rename_core_refs :: proc(
	project: ^Story_Project,
	kind: Story_Authoring_Record_Kind,
	old, new: string,
) {
	payload := mystery_payload(project); if payload == nil do return
	#partial switch kind {
	case .Entity:
		for &item in payload.characters do if item.entity_id == old do item.entity_id = new
		for &item in payload.locations {if item.entity_id == old do item.entity_id = new; mystery_authoring_refs_rename(&item.characters, item.character_count, old, new)}
		for &item in payload.pois {if item.entity_id == old do item.entity_id = new; if item.location_id == old do item.location_id = new; if item.owner_id == old do item.owner_id = new}
		for &item in payload.events {if item.destination_id == old do item.destination_id = new; if item.tool_id == old do item.tool_id = new}
		for &item in payload.clues do if item.source_id == old do item.source_id = new
		for &item in payload.claims do if item.speaker_id == old do item.speaker_id = new
		for &item in payload.dialogue do if item.character_id == old do item.character_id = new
		if payload.solution.culprit_id == old do payload.solution.culprit_id = new; mystery_authoring_refs_rename(&payload.solution.exclusions, payload.solution.exclusion_count, old, new)
	case .Proposition:
		for &item in payload.clues do if item.proposition_id == old do item.proposition_id = new
		for &item in payload.claims do if item.proposition_id == old do item.proposition_id = new
		for &item in payload.contradictions do if item.conclusion_id == old do item.conclusion_id = new
		for &item in payload.deductions do if item.proposition_id == old do item.proposition_id = new
		for &item in payload.questions do if item.hypothesis_id == old do item.hypothesis_id = new
	case .Fact:
		for &item in payload.contradictions do if item.fact_id == old do item.fact_id = new
	case .Event:
		for &item in payload.events do if item.event_id == old do item.event_id = new
		mystery_authoring_refs_rename(
			&payload.solution.murder_events,
			payload.solution.murder_event_count,
			old,
			new,
		); mystery_authoring_refs_rename(&payload.solution.cover_up_events, payload.solution.cover_up_event_count, old, new)
	case .Ending:
		for &item in payload.endings do if item.ending_id == old do item.ending_id = new
	case:
	}
}
