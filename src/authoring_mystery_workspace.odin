package main

import "core:fmt"
import "core:strconv"
import "core:strings"

authoring_mystery_default_add :: proc(
	kind: Mystery_Authoring_Record_Kind,
	id: string,
	payload: ^Mystery_Project,
) -> (
	Mystery_Authoring_Command,
	string,
) {
	command := Mystery_Authoring_Command {
		kind        = .Add,
		record_kind = kind,
	}; first_entity :=
		len(active_story_project.entities) > 0 ? active_story_project.entities[0].id : ""; first_proposition := len(active_story_project.propositions) > 0 ? active_story_project.propositions[0].id : ""
	#partial switch kind {
	case .Character:
		command.character = {
			entity_id = id,
		}
	case .Location:
		command.location = {
			entity_id = id,
		}
	case .POI:
		command.poi = {
			entity_id          = id,
			location_id        = len(payload.locations) > 0 ? payload.locations[0].entity_id : "",
			examination_action = "examine",
		}
	case .Event:
		command.event = {
			event_id       = id,
			destination_id = len(payload.locations) > 0 ? payload.locations[0].entity_id : "",
		}
	case .Clue:
		command.clue = {
			id             = id,
			source_id      = first_entity,
			description    = "New evidence",
			proposition_id = first_proposition,
			skill          = "Observation",
			check_kind     = "white",
			cost           = 0,
		}
	case .Claim:
		if first_entity == "" do return {}, "ADD A STORY ENTITY BEFORE A CLAIM"; command.claim = {
			id             = id,
			speaker_id     = first_entity,
			proposition_id = first_proposition,
		}
	case .Contradiction:
		if len(payload.claims) == 0 do return {}, "ADD A CLAIM BEFORE A CONTRADICTION"
		command.contradiction = {
			id            = id,
			claim_id      = payload.claims[0].id,
			conclusion_id = first_proposition,
			explanation   = "New contradiction",
		}
	case .Deduction:
		command.deduction = {
			id       = id,
			category = "general",
		}
	case .Question:
		command.question = {
			id       = id,
			prompt   = "New question",
			category = "general",
		}
	case .Demonstration:
		if len(payload.questions) == 0 do return {}, "ADD A QUESTION BEFORE A DEMONSTRATION"
		command.demonstration = {
			id              = id,
			question_id     = payload.questions[0].id,
			mode            = "evidence",
			presentation    = "slots",
			candidate_limit = 5,
			resolution      = "resolve",
			result          = "result",
			prompt          = "Demonstrate",
		}
	case .Dialogue:
		command.dialogue = {
			node_id = id,
		}
	case .Ending:
		command.ending = {
			ending_id      = id,
			trigger        = "solution",
			outcome        = "resolved",
			subtitle       = "Resolved",
			epilogue       = "Case closed",
			primary_label  = "Continue",
			primary_action = "continue",
		}
	case .City_Label:
		command.city_label = {
			id           = id,
			display_name = "New Destination",
			level_spawn  = "spawn_player",
			city_site    = id,
		}
	case .Tutorial_Lesson:
		command.tutorial_lesson = {
			id         = id,
			capability = fmt.tprintf("lesson.%s", id),
			prompt     = "New tutorial lesson",
		}
	case .Setup, .Solution:
		return {}, "SETUP AND SOLUTION ALREADY EXIST"
	}; return command, ""
}

authoring_workspace_add_mystery_from_selected :: proc(id: string) -> string {payload :=
		mystery_payload(&active_story_project)
	kind := Mystery_Authoring_Record_Kind(
		clamp(
			authoring_workspace.selected_category,
			0,
			int(Mystery_Authoring_Record_Kind.Solution),
		),
	)
	if payload == nil do return "ACTIVE STORY IS NOT A MYSTERY"
	if kind == .Setup || kind == .Solution do return "SETUP AND SOLUTION ALREADY EXIST"
	index := authoring_workspace.selected_record
	command := Mystery_Authoring_Command {
		kind        = .Add,
		record_kind = kind,
	}
	if authoring_mystery_count(kind) > 0 {index = clamp(
			index,
			0,
			authoring_mystery_count(kind) - 1,
		)
		#partial switch
		kind {case .Character:
			command.character = payload.characters[index]
			command.character.entity_id = id; case .Location:
			command.location = payload.locations[index]
			command.location.entity_id = id; case .POI:
			command.poi = payload.pois[index]; command.poi.entity_id = id; case .Event:
			command.event = payload.events[index]; command.event.event_id = id; case .Clue:
			command.clue = payload.clues[index]; command.clue.id = id; case .Claim:
			command.claim = payload.claims[index]; command.claim.id = id; case .Contradiction:
			command.contradiction = payload.contradictions[index]
			command.contradiction.id = id; case .Deduction:
			command.deduction = payload.deductions[index]
			command.deduction.id = id; case .Question:
			command.question = payload.questions[index]
			command.question.id = id; case .Demonstration:
			command.demonstration = payload.demonstrations[index]
			command.demonstration.id = id; case .Dialogue:
			command.dialogue = payload.dialogue[index]
			command.dialogue.node_id = id; case .Ending:
			command.ending = payload.endings[index]
			command.ending.ending_id = id; case .City_Label:
			command.city_label = payload.city_labels[index]
			command.city_label.id = id; case .Tutorial_Lesson:
			command.tutorial_lesson = payload.tutorial_lessons[index]
			command.tutorial_lesson.id = id; case .Setup, .Solution:}}
	else {message: string; command, message = authoring_mystery_default_add(kind, id, payload)
		if message != "" do return message}
	prepared_story := false
	if (kind == .Character || kind == .Location || kind == .POI) &&
	   story_entity_index(&active_story_project, id) < 0 {prep := [1]Story_Authoring_Command {
			{
				kind = .Add,
				record_kind = .Entity,
				entity = {
					id = id,
					kind = kind == .Character ? "person" : "place",
					display_name = id,
				},
			},
		}
		prepared := story_authoring_apply(
			&active_story_project,
			&authoring_workspace.story_history,
			prep[:],
		)
		prepared_story = prepared.ok
		message := prepared.message
		story_authoring_result_destroy(&prepared)
		if !prepared_story do return message}
	if kind == .Ending {found := false; for ending in active_story_project.endings do if ending.id == id do found = true
		if !found {prep := [1]Story_Authoring_Command {
				{
					kind = .Add,
					record_kind = .Ending,
					ending = {id = id, title = "New Ending", condition_id = "always"},
				},
			}
			prepared := story_authoring_apply(
				&active_story_project,
				&authoring_workspace.story_history,
				prep[:],
			)
			prepared_story = prepared.ok
			message := prepared.message
			story_authoring_result_destroy(&prepared)
			if !prepared_story do return message}}
	commands := [1]Mystery_Authoring_Command{command}
	result := mystery_authoring_apply(
		&active_story_project,
		&authoring_workspace.mystery_history,
		commands[:],
	)
	ok := result.ok
	message := result.message
	if !ok && len(result.validation.diagnostics) > 0 do message = fmt.tprintf("%s · %s", message, result.validation.diagnostics[0].message)
	mystery_authoring_result_destroy(&result)
	if !ok && prepared_story do _ = story_authoring_undo(&active_story_project, &authoring_workspace.story_history)
	if ok do authoring_workspace.selected_record = authoring_mystery_count(kind) - 1
	return message}

// Shared by every typed adapter. Counts remain authoritative, unused slots are
// cleared, and callers commit the containing record through an Update command.
authoring_reference_insert :: proc(
	values: ^[$N]string,
	count: ^int,
	at: int,
	value: string,
) -> bool {if value == "" || count^ < 0 || count^ >= N do return false; for i in 0 ..< count^ do if values[i] == value do return false
	index := clamp(at, 0, count^)
	for i := count^; i > index; i -= 1 do values[i] = values[i - 1]
	values[index] = value
	count^ += 1
	return true}
authoring_reference_remove :: proc(
	values: ^[$N]string,
	count: ^int,
	at: int,
) -> bool {if count^ <= 0 || at < 0 || at >= count^ do return false; for i in at + 1 ..< count^ do values[i - 1] = values[i]
	count^ -= 1
	values[count^] = ""
	return true}
authoring_reference_reorder :: proc(
	values: ^[$N]string,
	count: int,
	from, to: int,
) -> bool {if from < 0 || to < 0 || from >= count || to >= count do return false; item :=
		values[from]
	if from < to {for i in from ..< to do values[i] = values[i + 1]}
	else {for i := from; i > to; i -= 1 do values[i] = values[i - 1]}
	values[to] = item
	return true}

authoring_mystery_selected_update :: proc() -> (Mystery_Authoring_Command, bool) {payload :=
		mystery_payload(&active_story_project)
	kind := Mystery_Authoring_Record_Kind(
		clamp(
			authoring_workspace.selected_category,
			0,
			int(Mystery_Authoring_Record_Kind.Solution),
		),
	)
	if payload == nil do return {}, false
	index := clamp(
		authoring_workspace.selected_record,
		0,
		max(0, authoring_mystery_count(kind) - 1),
	)
	command := Mystery_Authoring_Command {
		kind        = .Update,
		record_kind = kind,
	}
	#partial switch
	kind {case .Setup:
		command.setup = {
			payload.action_budget,
			payload.seed,
			payload.tutorial_id,
			payload.city_start,
			payload.city_destination,
			payload.reveal_location,
		}; case .Character:
		if len(payload.characters) == 0 do return {}, false
		command.character = payload.characters[index]; case .Location:
		if len(payload.locations) == 0 do return {}, false
		command.location = payload.locations[index]; case .POI:
		if len(payload.pois) == 0 do return {}, false
		command.poi = payload.pois[index]; case .Event:
		if len(payload.events) == 0 do return {}, false
		command.event = payload.events[index]; case .Clue:
		if len(payload.clues) == 0 do return {}, false
		command.clue = payload.clues[index]; case .Claim:
		if len(payload.claims) == 0 do return {}, false
		command.claim = payload.claims[index]; case .Contradiction:
		if len(payload.contradictions) == 0 do return {}, false
		command.contradiction = payload.contradictions[index]; case .Deduction:
		if len(payload.deductions) == 0 do return {}, false
		command.deduction = payload.deductions[index]; case .Question:
		if len(payload.questions) == 0 do return {}, false
		command.question = payload.questions[index]; case .Demonstration:
		if len(payload.demonstrations) == 0 do return {}, false
		command.demonstration = payload.demonstrations[index]; case .Dialogue:
		if len(payload.dialogue) == 0 do return {}, false
		command.dialogue = payload.dialogue[index]; case .Ending:
		if len(payload.endings) == 0 do return {}, false
		command.ending = payload.endings[index]; case .City_Label:
		if len(payload.city_labels) == 0 do return {}, false
		command.city_label = payload.city_labels[index]; case .Tutorial_Lesson:
		if len(payload.tutorial_lessons) == 0 do return {}, false
		command.tutorial_lesson = payload.tutorial_lessons[index]; case .Solution:
		command.solution = payload.solution}
	return command, true}
authoring_mystery_commit_update :: proc(command: Mystery_Authoring_Command) -> string {commands :=
		[1]Mystery_Authoring_Command{command}
	result := mystery_authoring_apply(
		&active_story_project,
		&authoring_workspace.mystery_history,
		commands[:],
	)
	message := result.message
	mystery_authoring_result_destroy(&result)
	return message}
authoring_mystery_set_text :: proc(field, value: string) -> string {command, ok :=
		authoring_mystery_selected_update()
	if !ok do return "NO SELECTED RECORD"
	switch
	command.record_kind {
	case .Setup:
		switch
		field {case "tutorial_id":
			command.setup.tutorial_id = value; case "city_start":
			command.setup.city_start = value; case "city_destination":
			command.setup.city_destination = value; case "reveal_location":
			command.setup.reveal_location = value; case:
			return "FIELD IS NOT TEXT"}
	case .Character:
		switch
		field {case "private_secret":
			command.character.private_secret = value; case "motive":
			command.character.motive = value; case:
			return "USE RENAME FOR ENTITY ID"}
	case .Location:
		return "LOCATION SCALAR ID USES RENAME"
	case .POI:
		switch
		field {case "location_id":
			command.poi.location_id = value; case "owner_id":
			command.poi.owner_id = value; case "relevant_state":
			command.poi.relevant_state = value; case "examination_action":
			command.poi.examination_action = value; case:
			return "USE RENAME FOR ENTITY ID"}
	case .Event:
		switch
		field {case "destination_id":
			command.event.destination_id = value; case "tool_id":
			command.event.tool_id = value; case:
			return "USE RENAME FOR EVENT ID"}
	case .Clue:
		switch
		field {case "source_id":
			command.clue.source_id = value; case "description":
			command.clue.description = value; case "proposition_id":
			command.clue.proposition_id = value; case "skill":
			command.clue.skill = value; case "check_kind":
			command.clue.check_kind = value; case:
			return "USE RENAME FOR ID"}
	case .Claim:
		switch
		field {case "speaker_id":
			command.claim.speaker_id = value; case "proposition_id":
			command.claim.proposition_id = value; case "protects":
			command.claim.protects = value; case "response":
			command.claim.response = value; case:
			return "USE RENAME FOR ID"}
	case .Contradiction:
		switch
		field {case "claim_id":
			command.contradiction.claim_id = value; case "fact_id":
			command.contradiction.fact_id = value; case "conclusion_id":
			command.contradiction.conclusion_id = value; case "explanation":
			command.contradiction.explanation = value; case:
			return "USE RENAME FOR ID"}
	case .Deduction:
		switch
		field {case "proposition_id":
			command.deduction.proposition_id = value; case "category":
			command.deduction.category = value; case:
			return "USE RENAME FOR ID"}
	case .Question:
		switch
		field {case "prompt":
			command.question.prompt = value; case "hypothesis_id":
			command.question.hypothesis_id = value; case "category":
			command.question.category = value; case:
			return "USE RENAME FOR ID"}
	case .Demonstration:
		switch
		field {case "question_id":
			command.demonstration.question_id = value; case "mode":
			command.demonstration.mode = value; case "presentation":
			command.demonstration.presentation = value; case "gesture":
			command.demonstration.gesture = value; case "subject":
			command.demonstration.subject = value; case "art":
			command.demonstration.art = value; case "completion_cue":
			command.demonstration.completion_cue = value; case "resolution":
			command.demonstration.resolution = value; case "result":
			command.demonstration.result = value; case "prompt":
			command.demonstration.prompt = value; case:
			return "USE RENAME FOR ID"}
	case .Dialogue:
		switch
		field {case "character_id":
			command.dialogue.character_id = value; case "prompt":
			command.dialogue.prompt = value; case "response":
			command.dialogue.response = value; case "clue_id":
			command.dialogue.clue_id = value; case "interaction":
			command.dialogue.interaction = value; case:
			return "USE RENAME FOR NODE ID"}
	case .Ending:
		switch
		field {case "trigger":
			command.ending.trigger = value; case "outcome":
			command.ending.outcome = value; case "subtitle":
			command.ending.subtitle = value; case "epilogue":
			command.ending.epilogue = value; case "canonical_timeline":
			command.ending.canonical_timeline = value; case "tone":
			command.ending.tone = value; case "primary_label":
			command.ending.primary_label = value; case "primary_action":
			command.ending.primary_action = value; case "secondary_label":
			command.ending.secondary_label = value; case "secondary_action":
			command.ending.secondary_action = value; case:
			return "USE RENAME FOR ENDING ID"}
	case .City_Label:
		switch
		field {case "display_name":
			command.city_label.display_name = value; case "level_spawn":
			command.city_label.level_spawn = value; case "city_site":
			command.city_label.city_site = value; case:
			return "USE RENAME FOR ID"}
	case .Tutorial_Lesson:
		switch
		field {case "capability":
			command.tutorial_lesson.capability = value; case "prompt":
			command.tutorial_lesson.prompt = value; case:
			return "USE RENAME FOR ID"}
	case .Solution:
		switch
		field {case "culprit_id":
			command.solution.culprit_id = value; case "motive_id":
			command.solution.motive_id = value; case "decisive_contradiction_id":
			command.solution.decisive_contradiction_id = value; case "weapon_block":
			command.solution.weapon_block = value; case "murder_place_block":
			command.solution.murder_place_block = value; case "death_time_block":
			command.solution.death_time_block = value; case "body_movement_block":
			command.solution.body_movement_block = value; case "staging_block":
			command.solution.staging_block = value; case "cleaning_block":
			command.solution.cleaning_block = value; case "alibi_block":
			command.solution.alibi_block = value; case:
			return "UNKNOWN SOLUTION FIELD"}
	}
	return authoring_mystery_commit_update(command)}

authoring_mystery_set_number :: proc(field, value: string) -> string {command, ok :=
		authoring_mystery_selected_update()
	if !ok do return "NO SELECTED RECORD"
	number, parsed := strconv.parse_i64(strings.trim_space(value))
	if !parsed do return "EXPECTED INTEGER"
	n := int(number)
	#partial switch
	command.record_kind {case .Setup:
		if field == "action_budget" do command.setup.action_budget = max(1, n)
		else if field == "seed" do command.setup.seed = u64(max(0, n))
		else do return "UNKNOWN NUMERIC FIELD"; case .Character:
		if field == "initial_disposition" do command.character.initial_disposition = n
		else do return "UNKNOWN NUMERIC FIELD"; case .Clue:
		if field == "difficulty" do command.clue.difficulty = n
		else if field == "cost" do command.clue.cost = n
		else do return "UNKNOWN NUMERIC FIELD"; case .Demonstration:
		if field == "candidate_limit" do command.demonstration.candidate_limit = n
		else do return "UNKNOWN NUMERIC FIELD"; case:
		return "SELECTED FAMILY HAS NO NUMERIC SCALAR"}
	return authoring_mystery_commit_update(command)}
authoring_mystery_toggle_bool :: proc(field: string) -> string {command, ok :=
		authoring_mystery_selected_update()
	if !ok do return "NO SELECTED RECORD"
	if command.record_kind == .Claim && field == "canonical_truth" && !authoring_creator_truth_revealed do return "REVEAL CREATOR-ONLY TRUTH BEFORE EDITING"
	#partial switch
	command.record_kind {case .Clue:
		if field != "essential" do return "UNKNOWN BOOLEAN FIELD"
		command.clue.essential = !command.clue.essential; case .Claim:
		if field != "canonical_truth" do return "UNKNOWN BOOLEAN FIELD"
		command.claim.canonical_truth = !command.claim.canonical_truth; case .Question:
		if field != "required_for_final" do return "UNKNOWN BOOLEAN FIELD"
		command.question.required_for_final = !command.question.required_for_final; case:
		return "SELECTED FAMILY HAS NO BOOLEAN SCALAR"}
	return authoring_mystery_commit_update(command)}

authoring_mystery_update_list :: proc(
	field: string,
	edit: Story_List_Edit,
	at: int,
	value: string = "",
) -> string {command, ok := authoring_mystery_selected_update(); if !ok do return "NO SELECTED RECORD"
	changed := false
	#partial switch
	command.record_kind {
	case .Character:
		if field == "initial_claims" do changed = authoring_story_list_strings(&command.character.initial_claims, &command.character.initial_claim_count, edit, at, value)
	case .Location:
		if field == "connections" do changed = authoring_story_list_strings(&command.location.connections, &command.location.connection_count, edit, at, value)
		else if field == "characters" do changed = authoring_story_list_strings(&command.location.characters, &command.location.character_count, edit, at, value)
		else if field == "pois" do changed = authoring_story_list_strings(&command.location.pois, &command.location.poi_count, edit, at, value)
		else if field == "search_actions" do changed = authoring_story_list_strings(&command.location.search_actions, &command.location.search_action_count, edit, at, value)
	case .Event:
		if field == "effects" do changed = authoring_story_list_strings(&command.event.effects, &command.event.effect_count, edit, at, value)
	case .Clue:
		if field == "prerequisites" do changed = authoring_story_list_strings(&command.clue.prerequisites, &command.clue.prerequisite_count, edit, at, value)
		else if field == "blocks" do changed = authoring_story_list_strings(&command.clue.blocks, &command.clue.block_count, edit, at, value)
		else if field == "topics" do changed = authoring_story_list_strings(&command.clue.topics, &command.clue.topic_count, edit, at, value)
	case .Deduction:
		if field == "supports" do changed = authoring_story_list_strings(&command.deduction.supports, &command.deduction.support_count, edit, at, value)
		else if field == "unlock_questions" do changed = authoring_story_list_strings(&command.deduction.unlock_questions, &command.deduction.unlock_question_count, edit, at, value)
		else if field == "unlock_topics" do changed = authoring_story_list_strings(&command.deduction.unlock_topics, &command.deduction.unlock_topic_count, edit, at, value)
		else if field == "unlock_investigations" do changed = authoring_story_list_strings(&command.deduction.unlock_investigations, &command.deduction.unlock_investigation_count, edit, at, value)
	case .Question:
		if field == "requires_clues" do changed = authoring_story_list_strings(&command.question.requires_clues, &command.question.require_clue_count, edit, at, value)
		else if field == "requires_claims" do changed = authoring_story_list_strings(&command.question.requires_claims, &command.question.require_claim_count, edit, at, value)
		else if field == "requires_deductions" do changed = authoring_story_list_strings(&command.question.requires_deductions, &command.question.require_deduction_count, edit, at, value)
		else if field == "dependencies" do changed = authoring_story_list_strings(&command.question.dependencies, &command.question.dependency_count, edit, at, value)
	case .Demonstration:
		if field == "gesture_steps" do changed = authoring_story_list_strings(&command.demonstration.gesture_steps, &command.demonstration.gesture_step_count, edit, at, value)
		else if field == "slot_labels" do changed = authoring_story_list_strings(&command.demonstration.slot_labels, &command.demonstration.slot_count, edit, at, value)
		else if field == "slot_types" do changed = authoring_story_list_strings(&command.demonstration.slot_types, &command.demonstration.slot_count, edit, at, value)
		else if field == "accepted" do changed = authoring_story_list_strings(&command.demonstration.accepted, &command.demonstration.accepted_count, edit, at, value)
		else if field == "result_deductions" do changed = authoring_story_list_strings(&command.demonstration.result_deductions, &command.demonstration.result_count, edit, at, value)
	case .Dialogue:
		if field == "requires" do changed = authoring_story_list_strings(&command.dialogue.requires, &command.dialogue.require_count, edit, at, value)
		else if field == "unlocks" do changed = authoring_story_list_strings(&command.dialogue.unlocks, &command.dialogue.unlock_count, edit, at, value)
	case .Solution:
		if field == "requirements" do changed = authoring_story_list_strings(&command.solution.requirements, &command.solution.requirement_count, edit, at, value)
		else if field == "murder_events" do changed = authoring_story_list_strings(&command.solution.murder_events, &command.solution.murder_event_count, edit, at, value)
		else if field == "cover_up_events" do changed = authoring_story_list_strings(&command.solution.cover_up_events, &command.solution.cover_up_event_count, edit, at, value)
		else if field == "false_alibis" do changed = authoring_story_list_strings(&command.solution.false_alibis, &command.solution.false_alibi_count, edit, at, value)
		else if field == "exclusions" do changed = authoring_story_list_strings(&command.solution.exclusions, &command.solution.exclusion_count, edit, at, value)
	case:}
	if !changed do return "UNKNOWN, FULL, OR INVALID MYSTERY LIST EDIT"
	return authoring_mystery_commit_update(command)}

authoring_mystery_demonstration_route_edit :: proc(
	edit: Story_List_Edit,
	at, first, count: int,
) -> string {command, ok := authoring_mystery_selected_update(); if !ok || command.record_kind != .Demonstration do return "SELECT A DEMONSTRATION"
	r := &command.demonstration
	if edit == .Add {if r.route_count >= MYSTERY_MAX_REFS do return "ROUTE LIST FULL"; insert :=
			clamp(at, 0, r.route_count)
		for i := r.route_count; i > insert; i -= 1 {r.route_firsts[i] = r.route_firsts[i - 1]
			r.route_counts[i] = r.route_counts[i - 1]}
		r.route_firsts[insert] = first
		r.route_counts[insert] = count
		r.route_count += 1}
	else {if at < 0 || at >= r.route_count do return "INVALID ROUTE"; if edit == .Remove {for 			i in at + 1 ..< r.route_count {r.route_firsts[i - 1] = r.route_firsts[i]; r.route_counts[i - 1] =
					r.route_counts[i]}
			r.route_count -= 1
			r.route_firsts[r.route_count] = 0
			r.route_counts[r.route_count] = 0}
		else {to := edit == .Move_Up ? at - 1 : at + 1; if to < 0 || to >= r.route_count do return "INVALID ROUTE MOVE"
			r.route_firsts[at], r.route_firsts[to] = r.route_firsts[to], r.route_firsts[at]
			r.route_counts[at], r.route_counts[to] = r.route_counts[to], r.route_counts[at]}}
	return authoring_mystery_commit_update(command)}

authoring_mystery_picker_kind :: proc(
	field: string,
) -> (
	Mystery_Authoring_Record_Kind,
	bool,
) {switch field {case "initial_claims":
		return .Claim, true; case "connections":
		return .Location, true; case "characters", "exclusions":
		return .Character, true; case "pois", "search_actions":
		return .POI, true; case "prerequisites", "blocks", "requires_clues":
		return .Clue, true; case "unlock_questions", "dependencies":
		return .Question, true; case "requires_claims", "false_alibis":
		return .Claim, true; case "requires_deductions", "result_deductions", "requirements":
		return .Deduction, true; case "murder_events", "cover_up_events":
		return .Event, true}; return {}, false}
authoring_mystery_create_in_picker :: proc(field, id: string) -> string {target, typed :=
		authoring_mystery_picker_kind(field)
	if !typed do return "THIS LIST ACCEPTS FREE TEXT OR STORY DATA REFERENCES"
	owner_kind := clamp(
		authoring_workspace.selected_category,
		0,
		int(Mystery_Authoring_Record_Kind.Solution),
	)
	owner_index := authoring_workspace.selected_record
	authoring_workspace.selected_category = int(target)
	authoring_workspace.selected_record = 0
	created := authoring_workspace_add_mystery_from_selected(id)
	if !strings.contains(created, "committed") {authoring_workspace.selected_category = owner_kind
		authoring_workspace.selected_record = owner_index
		return created}
	created_index := authoring_mystery_count(target) - 1
	authoring_workspace.selected_category = owner_kind
	authoring_workspace.selected_record = owner_index
	linked := authoring_mystery_update_list(field, .Add, authoring_mystery_list_item, id)
	if !strings.contains(linked, "committed") {_ = mystery_authoring_undo(
			&active_story_project,
			&authoring_workspace.mystery_history,
		)
		return fmt.tprintf("CREATE ROLLED BACK · %s", linked)}
	authoring_workspace.selected_category = int(target)
	authoring_workspace.selected_record = created_index
	return fmt.tprintf("CREATED, LINKED, AND FOCUSED %v · %s", target, id)}
