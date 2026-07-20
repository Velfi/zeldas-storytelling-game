package main

import "core:fmt"
import "core:os"
import "core:strings"

mystery_completion_scalar_value :: proc(
	project: ^Story_Project,
	payload: ^Mystery_Project,
	kind: Mystery_Authoring_Record_Kind,
	field: string,
) -> string {
	if kind == .Solution {s := payload.solution; switch field {case "culprit_id":
			return s.culprit_id; case "motive_id":
			return s.motive_id; case "decisive_contradiction_id":
			return s.decisive_contradiction_id; case "weapon_block":
			return s.weapon_block; case "murder_place_block":
			return s.murder_place_block; case "death_time_block":
			return s.death_time_block; case "body_movement_block":
			return s.body_movement_block; case "staging_block":
			return s.staging_block; case "cleaning_block":
			return s.cleaning_block; case "alibi_block":
			return s.alibi_block}}
	if kind == .Clue && field == "source_id" do return payload.clues[0].source_id
	if kind == .Contradiction && field == "fact_id" do return payload.contradictions[0].fact_id
	if field == "tutorial_id" do return payload.tutorial_lessons[0].id
	if field == "reveal_location" || field == "location_id" || field == "destination_id" do return payload.locations[0].entity_id
	if field == "owner_id" || field == "source_id" || field == "speaker_id" || field == "protects" || field == "character_id" do return payload.characters[0].entity_id
	if field == "proposition_id" || field == "conclusion_id" || field == "hypothesis_id" do return project.propositions[0].id
	if field == "claim_id" do return payload.claims[0].id
	if field == "fact_id" do return "coverage_fact"
	if field == "question_id" do return payload.questions[0].id
	if kind ==
	   .Demonstration {demo := payload.demonstrations[0]; switch field {case "presentation":
			return demo.presentation; case "gesture":
			return demo.gesture; case "subject":
			return demo.subject; case "art":
			return demo.art; case "completion_cue":
			return demo.completion_cue}}
	if field == "clue_id" do return payload.clues[0].id
	if field == "city_start" || field == "city_destination" || field == "city_site" do return "coverage_city_site"
	if field == "level_spawn" do return "spawn_player"
	if field == "check_kind" do return "white"
	return "coverage_value"
}

mystery_completion_list_value :: proc(
	project: ^Story_Project,
	payload: ^Mystery_Project,
	field: string,
) -> string {
	switch field {case "initial_claims", "requires_claims", "false_alibis":
		return payload.claims[0].id; case "connections":
		return(
			payload.locations[min(1, len(payload.locations) - 1)].entity_id \
		); case "characters", "exclusions":
		for item in payload.characters do if item.entity_id != payload.solution.culprit_id do return item.entity_id; case "pois", "search_actions":
		return payload.pois[0].entity_id; case "effects":
		return project.effects[0].id; case "prerequisites", "blocks", "requires_clues", "accepted":
		return payload.clues[min(1, len(payload.clues) - 1)].id; case "supports":
		return payload.clues[0].id; case "unlock_questions", "dependencies":
		return(
			payload.questions[min(1, len(payload.questions) - 1)].id \
		); case "requires_deductions", "result_deductions", "requirements":
		return payload.deductions[0].id; case "murder_events", "cover_up_events":
		return payload.events[0].event_id; case "gesture_steps":
		return payload.demonstrations[0].gesture; case "slot_labels":
		return "Coverage Slot"; case "slot_types":
		return(
			"clue" \
		); case "topics", "unlock_topics", "unlock_investigations", "requires", "unlocks":
		return "coverage.topic"}; return "coverage.value"
}

run_story_mystery_completion_tests :: proc() {
	// A blank template can become a variable-driven, compilable story without
	// hand-editing its serialized representation. Every mutation crosses the
	// production typed authoring-command boundary used by the workspace.
	blank := authoring_minimal_story(
		"blank_variable_story",
		"Blank Variable Story",
		.General_Story,
	); defer story_project_destroy(&blank)
	blank_history: Story_Authoring_History; defer story_authoring_history_destroy(&blank_history)
	blank_commands := [4]Story_Authoring_Command {
		{
			kind = .Add,
			record_kind = .Variable,
			variable = {
				id = "door_open",
				display_name = "Door Open",
				kind = .Boolean,
				default_value = story_value_boolean(false),
			},
		},
		{
			kind = .Add,
			record_kind = .Condition,
			condition = {
				id = "door_is_open",
				kind = .Value_Equals,
				variable_id = "door_open",
				value = story_value_boolean(true),
			},
		},
		{
			kind = .Add,
			record_kind = .Effect,
			effect = {
				id = "open_door",
				kind = .Set_Value,
				variable_id = "door_open",
				value = story_value_boolean(true),
			},
		},
		{kind = .Insert_Effect_Reference, owner_id = "opening_end", id = "open_door"},
	}
	blank_authored := story_authoring_apply(
		&blank,
		&blank_history,
		blank_commands[:],
	); assert(blank_authored.ok); story_authoring_result_destroy(&blank_authored)
	duplicate_commands := [1]Story_Authoring_Command {
		{
			kind = .Duplicate,
			record_kind = .Variable,
			new_id = "door_open_copy",
			variable = blank.variables[story_variable_index(&blank, "door_open")],
		},
	}; duplicated := story_authoring_apply(&blank, &blank_history, duplicate_commands[:]); assert(duplicated.ok); story_authoring_result_destroy(&duplicated)
	reorder_commands := [1]Story_Authoring_Command {
		{kind = .Reorder, record_kind = .Variable, from = 1, to = 0},
	}; reordered := story_authoring_apply(&blank, &blank_history, reorder_commands[:]); assert(reordered.ok && blank.variables[0].id == "door_open_copy"); story_authoring_result_destroy(&reordered)
	remove_commands := [1]Story_Authoring_Command {
		{kind = .Remove, record_kind = .Variable, id = "door_open_copy"},
	}; removed := story_authoring_apply(&blank, &blank_history, remove_commands[:]); assert(removed.ok && story_variable_index(&blank, "door_open_copy") < 0); story_authoring_result_destroy(&removed)
	blank_compiled := compile_story_project(
		&blank,
	); assert(blank_compiled.ok && len(blank_compiled.story.compiled_nodes) == 1); story_compile_result_destroy(&blank_compiled)

	// Drive a blank Mystery template through the same workspace actions as the
	// in-game panels. Defaults create required Story identities atomically.
	saved_active := new(
		Story_Project,
	); saved_active^ = active_story_project; saved_workspace := new(Authoring_Workspace_State); saved_workspace^ = authoring_workspace
	active_story_project = authoring_minimal_story(
		"blank_mystery_actions",
		"Blank Mystery Actions",
		.Mystery,
	); authoring_workspace = {
		tab = .Mystery,
	}
	kinds := [16]Mystery_Authoring_Record_Kind {
		.Character,
		.Character,
		.Character,
		.Location,
		.POI,
		.Event,
		.Claim,
		.Claim,
		.Contradiction,
		.Deduction,
		.Question,
		.Demonstration,
		.Dialogue,
		.Ending,
		.City_Label,
		.Tutorial_Lesson,
	}; ids := [16]string{"suspect_a", "suspect_b", "witness", "study", "desk", "mystery_event", "claim_a", "claim_b", "contradiction_a", "deduction_a", "question_a", "demo_a", "opening_end", "mystery_ending", "city_label_a", "tutorial_a"}; for kind, i in kinds {authoring_workspace.selected_category = int(kind); authoring_workspace.selected_record = 0; message := authoring_workspace_add_mystery_from_selected(ids[i]); if !strings.contains(message, "committed") do fmt.println("MYSTERY ACTION FAILED · ", kind, " · ", ids[i], " · ", message); assert(strings.contains(message, "committed"))}
	// Add, reorder, and remove use the same selected-record actions as buttons.
	authoring_workspace.selected_category = int(
		Mystery_Authoring_Record_Kind.Claim,
	); authoring_workspace.selected_record = 1; assert(strings.contains(authoring_workspace_mystery_command(.Reorder, "up"), "committed")); assert(mystery_payload(&active_story_project).claims[0].id == "claim_b"); assert(strings.contains(authoring_workspace_mystery_command(.Remove), "committed")); assert(mystery_authoring_index(mystery_payload(&active_story_project), .Claim, "claim_b") < 0)
	// Creator truth cannot be inspected or changed until the explicit reveal.
	authoring_workspace.selected_record = 0; _ = authoring_creator_truth_access(false); assert(strings.contains(authoring_mystery_toggle_bool("canonical_truth"), "REVEAL")); _ = authoring_creator_truth_access(true); assert(strings.contains(authoring_mystery_toggle_bool("canonical_truth"), "committed")); _ = authoring_creator_truth_access(false)
	truth_commands := [2]Story_Authoring_Command {
		{
			kind = .Add,
			record_kind = .Proposition,
			proposition = {id = "creator_truth_proposition", text = "Creator-only proposition"},
		},
		{
			kind = .Add,
			record_kind = .Fact,
			fact = {
				id = "creator_truth_fact",
				display_name = "Creator Truth Fact",
				proposition = "creator_truth_proposition",
				canonical_truth = .Undetermined,
			},
		},
	}; truth_added := story_authoring_apply(&active_story_project, &authoring_workspace.story_history, truth_commands[:]); assert(truth_added.ok); story_authoring_result_destroy(&truth_added)
	_ = authoring_creator_truth_access(
		false,
	); truth_proposition := story_proposition_index(&active_story_project, "creator_truth_proposition"); truth_fact := -1; for fact, i in active_story_project.facts do if fact.id == "creator_truth_fact" do truth_fact = i; assert(truth_proposition >= 0 && truth_fact >= 0); truth_value := fmt.aprintf("%d", int(Story_Truth.True)); assert(strings.contains(authoring_story_update_field(.Proposition, truth_proposition, "canonical_truth", truth_value), "REVEAL")); assert(strings.contains(authoring_story_update_field(.Fact, truth_fact, "canonical_truth", truth_value), "REVEAL")); _ = authoring_creator_truth_access(true); proposition_truth_message := authoring_story_update_field(.Proposition, truth_proposition, "canonical_truth", truth_value); if !strings.contains(proposition_truth_message, "committed") do fmt.println("PROPOSITION TRUTH ACTION FAILED · ", proposition_truth_message); assert(strings.contains(proposition_truth_message, "committed") && active_story_project.propositions[truth_proposition].canonical_truth == .True); fact_truth_message := authoring_story_update_field(.Fact, truth_fact, "canonical_truth", truth_value); if !strings.contains(fact_truth_message, "committed") do fmt.println("FACT TRUTH ACTION FAILED · ", fact_truth_message); assert(strings.contains(fact_truth_message, "committed") && active_story_project.facts[truth_fact].canonical_truth == .True); _ = authoring_creator_truth_access(false)
	// Typed support chains and direct route actions: add, reorder, and remove.
	authoring_workspace.selected_category = int(
		Mystery_Authoring_Record_Kind.Deduction,
	); authoring_workspace.selected_record = 0; assert(strings.contains(authoring_mystery_update_list("supports", .Add, 0, "initial_clue"), "committed"))
	authoring_workspace.selected_category = int(
		Mystery_Authoring_Record_Kind.Demonstration,
	); authoring_workspace.selected_record = 0; route_fixture, route_fixture_ok := authoring_mystery_selected_update(); assert(route_fixture_ok); route_fixture.demonstration.slot_count = 1; route_fixture.demonstration.slot_labels[0] = "Evidence"; route_fixture.demonstration.slot_types[0] = "clue"; assert(strings.contains(authoring_mystery_commit_update(route_fixture), "committed")); assert(strings.contains(authoring_mystery_update_list("accepted", .Add, 0, "initial_clue"), "committed")); assert(strings.contains(authoring_mystery_update_list("accepted", .Add, 1, "initial_clue"), "committed")); route_message := authoring_mystery_demonstration_route_edit(.Add, 0, 0, 1); if !strings.contains(route_message, "committed") do fmt.println("ROUTE ACTION FAILED · ", route_message); assert(strings.contains(route_message, "committed")); assert(strings.contains(authoring_mystery_demonstration_route_edit(.Add, 1, 1, 1), "committed")); assert(strings.contains(authoring_mystery_demonstration_route_edit(.Move_Up, 1, 0, 0), "committed")); assert(mystery_payload(&active_story_project).demonstrations[0].route_firsts[0] == 1); assert(strings.contains(authoring_mystery_demonstration_route_edit(.Remove, 1, 0, 0), "committed")); assert(mystery_payload(&active_story_project).demonstrations[0].route_count == 1)
	// Both support and innocent-exclusion edges resolve to navigable records.
	found_support, found_exclusion :=
		false,
		false; for row := 0; row < authoring_mystery_panel_edge_count(17); row += 1 {source, source_kind, source_index, _, target_kind, target_index, ok := authoring_mystery_panel_edge(17, row); assert(ok); if source == "initial_clue" && source_kind == .Clue && source_index >= 0 && target_kind == .Deduction {authoring_mystery_focus_support_record(source_kind, source_index); found_support = authoring_workspace.selected_category == int(Mystery_Authoring_Record_Kind.Clue)}; if source == "suspect_a" && source_kind == .Character && source_index >= 0 && target_kind == .Solution && target_index == 0 {authoring_mystery_focus_support_record(source_kind, source_index); found_exclusion = authoring_workspace.selected_category == int(Mystery_Authoring_Record_Kind.Character)}}; assert(found_support && found_exclusion)
	filtered := authoring_story_filter_indices(
		.Entity,
		"suspect",
	); assert(len(filtered) >= 2); delete(filtered); used_target, used_ok := authoring_story_used_by_target(.Entity, "evidence_source"); assert(used_ok && used_target.workspace == "mystery")
	blank_mystery_validation := story_project_validate(
		&active_story_project,
	); assert(blank_mystery_validation.ok); story_validation_destroy(&blank_mystery_validation)
	story_authoring_history_destroy(
		&authoring_workspace.story_history,
	); mystery_authoring_history_destroy(&authoring_workspace.mystery_history); story_project_destroy(&active_story_project); active_story_project = saved_active^; free(saved_active); authoring_workspace = saved_workspace^; free(saved_workspace)

	// The production mystery exercises every MysteryDomain table.  Canonical
	// byte equality after a validated save/load proves every populated scalar,
	// table, fixed array, and route array survives the storage boundary.
	story: Story_Project; assert(load_story_project("assets/stories/mysteries/the_torn_appointment.story.toml", &story).ok); defer story_project_destroy(&story)
	payload := mystery_payload(
		&story,
	); assert(payload != nil && len(payload.characters) > 0 && len(payload.locations) > 0 && len(payload.pois) > 0 && len(payload.events) > 0 && len(payload.clues) > 0 && len(payload.claims) > 0 && len(payload.contradictions) > 0 && len(payload.deductions) > 0 && len(payload.questions) > 0 && len(payload.demonstrations) > 0 && len(payload.dialogue) > 0 && len(payload.endings) > 0 && len(payload.city_labels) > 0 && len(payload.tutorial_lessons) > 0)
	// Descriptor-driven coverage: every scalar and list row exposed by the
	// Mystery workspace invokes its production action, survives undo/redo, and
	// is loadable after serialization. Each action is isolated back to the same
	// validated source so list cardinalities cannot mask one another.
	field_saved_active := new(
		Story_Project,
	); field_saved_active^ = active_story_project; field_saved_workspace := new(Authoring_Workspace_State); field_saved_workspace^ = authoring_workspace; active_story_project = story_project_clone(&story); authoring_workspace = {
		tab = .Mystery,
	}; if len(active_story_project.effects) ==
	   0 {support_effect := [1]Story_Authoring_Command{{kind = .Add, record_kind = .Effect, effect = {id = "mystery_field_support_effect", kind = .Complete_Scene, content_id = active_story_project.scenes[0].id}}}; support_added := story_authoring_apply(&active_story_project, &authoring_workspace.story_history, support_effect[:]); assert(support_added.ok); story_authoring_result_destroy(&support_added)}; field_payload := mystery_payload(&active_story_project); field_roundtrip_path := "/private/tmp/chicago-mystery-field-action-roundtrip.toml"
	for kind in Mystery_Authoring_Record_Kind {authoring_workspace.selected_category = int(kind)
		authoring_workspace.selected_record = 0
		_, _, scalar_count := authoring_mystery_scalar_field(kind, 0)
		for cursor in 0 ..< scalar_count {field, field_type, _ := authoring_mystery_scalar_field(kind, cursor)
			message: string
			if field ==
			   "id (rename)" {old := authoring_mystery_id(kind, 0); message = authoring_workspace_mystery_command(.Rename, fmt.tprintf("%s_coverage", old))} else if field == "routes" {message = authoring_mystery_demonstration_route_edit(.Move_Down, 0, 0, 0)} else if field_type == 'b' {if kind == .Claim do _ = authoring_creator_truth_access(true)
				message = authoring_mystery_toggle_bool(
					field,
				)} else if field_type == 'n' {number := field == "action_budget" ? "100" : field == "candidate_limit" ? "3" : "1"
				message = authoring_mystery_set_number(
					field,
					number,
				)} else {message = authoring_mystery_set_text(field, mystery_completion_scalar_value(&active_story_project, field_payload, kind, field))}
			if !strings.contains(message, "committed") do fmt.println("MYSTERY SCALAR ACTION FAILED · ", kind, " · ", field, " · ", message)
			assert(strings.contains(message, "committed"))
			assert(
				mystery_authoring_undo(
					&active_story_project,
					&authoring_workspace.mystery_history,
				) &&
				mystery_authoring_redo(
					&active_story_project,
					&authoring_workspace.mystery_history,
				),
			)
			field_text := story_project_serialize(&active_story_project)
			assert(os.write_entire_file(field_roundtrip_path, transmute([]u8)field_text) == nil)
			field_loaded: Story_Project
			field_load := load_story_project(field_roundtrip_path, &field_loaded)
			if !field_load.ok || story_project_serialize(&field_loaded) != field_text do fmt.println("MYSTERY FIELD ROUNDTRIP FAILED · ", kind, " · ", field, " · ", field_load.message)
			assert(field_load.ok && story_project_serialize(&field_loaded) == field_text)
			story_project_destroy(&field_loaded)
			assert(
				mystery_authoring_undo(
					&active_story_project,
					&authoring_workspace.mystery_history,
				),
			)
			field_payload = mystery_payload(&active_story_project)}
		_, list_count := authoring_mystery_list_field(kind, 0)
		for cursor in 0 ..< list_count {field, _ := authoring_mystery_list_field(kind, cursor); at := authoring_mystery_selected_list_count(field); message := authoring_mystery_update_list(field, .Add, at, mystery_completion_list_value(&active_story_project, field_payload, field)); if !strings.contains(message, "committed") do fmt.println("MYSTERY LIST ACTION FAILED · ", kind, " · ", field, " · ", message); assert(strings.contains(message, "committed")); assert(mystery_authoring_undo(&active_story_project, &authoring_workspace.mystery_history) && mystery_authoring_redo(&active_story_project, &authoring_workspace.mystery_history)); field_text := story_project_serialize(&active_story_project); assert(os.write_entire_file(field_roundtrip_path, transmute([]u8)field_text) == nil); field_loaded: Story_Project; field_load := load_story_project(field_roundtrip_path, &field_loaded); if !field_load.ok || story_project_serialize(&field_loaded) != field_text do fmt.println("MYSTERY FIELD ROUNDTRIP FAILED · ", kind, " · ", field, " · ", field_load.message); assert(field_load.ok && story_project_serialize(&field_loaded) == field_text); story_project_destroy(&field_loaded); assert(mystery_authoring_undo(&active_story_project, &authoring_workspace.mystery_history)); field_payload = mystery_payload(&active_story_project)}}
	_ = authoring_creator_truth_access(
		false,
	); story_authoring_history_destroy(&authoring_workspace.story_history); mystery_authoring_history_destroy(&authoring_workspace.mystery_history); story_project_destroy(&active_story_project); active_story_project = field_saved_active^; free(field_saved_active); authoring_workspace = field_saved_workspace^; free(field_saved_workspace)
	canonical_before := story_project_serialize(
		&story,
	); roundtrip_path := "/private/tmp/chicago-story-mystery-exhaustive-roundtrip.toml"; assert(save_story_project(roundtrip_path, &story).ok); roundtrip: Story_Project; assert(load_story_project(roundtrip_path, &roundtrip).ok); assert(story_project_serialize(&roundtrip) == canonical_before); story_project_destroy(&roundtrip)

	// Every discriminant is selected through the production workspace field
	// action. The records themselves enter through typed Add commands, carrying
	// the fields needed by each union arm. Undo/redo traverses every selection,
	// then the authored result survives the TOML boundary.
	enum_saved_active := new(
		Story_Project,
	); enum_saved_active^ = active_story_project; enum_saved_workspace := new(Authoring_Workspace_State); enum_saved_workspace^ = authoring_workspace
	active_story_project = story_project_clone(&story); authoring_workspace = {
		tab = .Story_Data,
	}
	condition_base := len(
		active_story_project.conditions,
	); effect_base := len(active_story_project.effects)
	variable_id := "completion_enum_variable"; entity_id := active_story_project.entities[0].id; proposition_id := "completion_enum_proposition"; objective_id := "completion_enum_objective"; event_id := "completion_enum_event"; scene_id := active_story_project.scenes[0].id
	enum_commands: [dynamic]Story_Authoring_Command; defer delete(enum_commands)
	append(
		&enum_commands,
		Story_Authoring_Command {
			kind = .Add,
			record_kind = .Variable,
			variable = {
				id = variable_id,
				display_name = "Enum Variable",
				kind = .Integer,
				default_value = story_value_integer(0),
				minimum = -100,
				maximum = 100,
			},
		},
	)
	append(
		&enum_commands,
		Story_Authoring_Command {
			kind = .Add,
			record_kind = .Proposition,
			proposition = {id = proposition_id, text = "Enum proposition"},
		},
	)
	append(
		&enum_commands,
		Story_Authoring_Command {
			kind = .Add,
			record_kind = .Objective,
			objective = {
				id = objective_id,
				display_name = "Enum Objective",
				description = "Control coverage objective",
				hidden = false,
			},
		},
	)
	append(
		&enum_commands,
		Story_Authoring_Command {
			kind = .Add,
			record_kind = .Event,
			event = {id = event_id, action = "enum_control"},
		},
	)
	append(
		&enum_commands,
		Story_Authoring_Command {
			kind = .Add,
			record_kind = .Condition,
			condition = {id = "completion_enum_child", kind = .Always},
		},
	)
	for kind in Story_Condition_Kind {condition := Story_Condition {
			id               = fmt.aprintf("completion_condition_%d", int(kind)),
			kind             = .Always,
			variable_id      = variable_id,
			entity_id        = entity_id,
			other_entity_id  = entity_id,
			proposition_id   = proposition_id,
			objective_id     = objective_id,
			event_id         = event_id,
			content_id       = scene_id,
			text_value       = "authored",
			value            = story_value_integer(7),
			comparison       = .Greater_Equal,
			objective_status = .Completed,
			belief_stance    = .Believes,
			spatial_a        = {"level", "a"},
			spatial_b        = {"level", "b"},
			distance         = 4.5,
		}; if kind ==
		   .Capability_State {condition.entity_id = active_story_project.capabilities[0].id; condition.content_id = "known:initial_clue"}; if kind == .All || kind == .Any || kind == .Not {condition.child_ids[0] = "completion_enum_child"; condition.child_id_count = 1}; append(&enum_commands, Story_Authoring_Command{kind = .Add, record_kind = .Condition, condition = condition})}
	for kind in Story_Effect_Kind {append(
			&enum_commands,
			Story_Authoring_Command {
				kind = .Add,
				record_kind = .Effect,
				effect = {
					id = fmt.aprintf("completion_effect_%d", int(kind)),
					kind = .Complete_Scene,
					variable_id = variable_id,
					actor_id = entity_id,
					other_actor_id = entity_id,
					proposition_id = proposition_id,
					objective_id = objective_id,
					event_id = event_id,
					content_id = scene_id,
					world_id = "world",
					value = story_value_integer(9),
					belief_stance = .Disbelieves,
					objective_status = .Failed,
					spatial_command = .Move,
					spatial_target = {"level", "a"},
					spatial_destination = {"level", "b"},
					world_enabled = true,
				},
			},
		)}
	enum_added := story_authoring_apply(
		&active_story_project,
		&authoring_workspace.story_history,
		enum_commands[:],
	); assert(enum_added.ok); story_authoring_result_destroy(&enum_added)
	for kind, i in Story_Condition_Kind {message := authoring_story_update_field(
			.Condition,
			condition_base + 1 + i,
			"kind",
			fmt.aprintf("%d", int(kind)),
		)
		assert(strings.contains(message, "committed"))
		condition := active_story_project.conditions[condition_base + 1 + i]
		assert(
			condition.kind == kind &&
			condition.variable_id == variable_id &&
			condition.entity_id ==
				(kind == .Capability_State ? active_story_project.capabilities[0].id : entity_id) &&
			condition.proposition_id == proposition_id &&
			condition.distance == 4.5,
		)}
	for kind, i in Story_Effect_Kind {message := authoring_story_update_field(
			.Effect,
			effect_base + i,
			"kind",
			fmt.aprintf("%d", int(kind)),
		)
		assert(strings.contains(message, "committed"))
		effect := active_story_project.effects[effect_base + i]
		assert(
			effect.kind == kind &&
			effect.variable_id == variable_id &&
			effect.actor_id == entity_id &&
			effect.proposition_id == proposition_id &&
			effect.world_enabled,
		)}
	enum_selection_count :=
		len(Story_Condition_Kind) +
		len(
			Story_Effect_Kind,
		); for _ in 0 ..< enum_selection_count do assert(story_authoring_undo(&active_story_project, &authoring_workspace.story_history)); for kind, i in Story_Condition_Kind do assert(active_story_project.conditions[condition_base + 1 + i].kind == .Always); for kind, i in Story_Effect_Kind do assert(active_story_project.effects[effect_base + i].kind == .Complete_Scene); for _ in 0 ..< enum_selection_count do assert(story_authoring_redo(&active_story_project, &authoring_workspace.story_history))
	enum_text := story_project_serialize(
		&active_story_project,
	); enum_path := "/private/tmp/chicago-story-enum-roundtrip.toml"; assert(os.write_entire_file(enum_path, transmute([]u8)enum_text) == nil); enum_roundtrip: Story_Project; assert(load_story_project(enum_path, &enum_roundtrip).ok); for kind, i in Story_Condition_Kind do assert(enum_roundtrip.conditions[condition_base + 1 + i].kind == kind && enum_roundtrip.conditions[condition_base + 1 + i].distance == 4.5); for kind, i in Story_Effect_Kind do assert(enum_roundtrip.effects[effect_base + i].kind == kind && enum_roundtrip.effects[effect_base + i].world_enabled); story_project_destroy(&enum_roundtrip)
	story_authoring_history_destroy(
		&authoring_workspace.story_history,
	); story_project_destroy(&active_story_project); active_story_project = enum_saved_active^; free(enum_saved_active); authoring_workspace = enum_saved_workspace^; free(enum_saved_workspace)

	// Nested condition and ordered-effect edits are one command transaction and
	// therefore one undo/redo unit, including the nested child order.
	edited := story_project_clone(
		&story,
	); history: Story_Authoring_History; defer story_authoring_history_destroy(&history)
	owner := edited.nodes[0].id
	commands := [7]Story_Authoring_Command {
		{
			kind = .Add,
			record_kind = .Condition,
			condition = {id = "completion_child_a", kind = .Always},
		},
		{
			kind = .Add,
			record_kind = .Condition,
			condition = {id = "completion_child_b", kind = .Never},
		},
		{
			kind = .Add,
			record_kind = .Condition,
			condition = {id = "completion_parent", kind = .All},
		},
		{
			kind = .Add,
			record_kind = .Effect,
			effect = {
				id = "completion_effect_a",
				kind = .Complete_Scene,
				content_id = edited.scenes[0].id,
			},
		},
		{
			kind = .Add,
			record_kind = .Effect,
			effect = {
				id = "completion_effect_b",
				kind = .Emit_Event,
				event_id = edited.events[0].id,
			},
		},
		{
			kind = .Insert_Condition_Child,
			owner_id = "completion_parent",
			id = "completion_child_a",
		},
		{
			kind = .Insert_Condition_Child,
			owner_id = "completion_parent",
			id = "completion_child_b",
			to = 0,
		},
	}
	added := story_authoring_apply(
		&edited,
		&history,
		commands[:],
	); assert(added.ok); story_authoring_result_destroy(&added)
	effect_commands := [3]Story_Authoring_Command {
		{kind = .Insert_Effect_Reference, owner_id = owner, id = "completion_effect_a"},
		{kind = .Insert_Effect_Reference, owner_id = owner, id = "completion_effect_b", to = 0},
		{kind = .Reorder_Effect_Reference, owner_id = owner, from = 0, to = 1},
	}
	effected := story_authoring_apply(
		&edited,
		&history,
		effect_commands[:],
	); assert(effected.ok); story_authoring_result_destroy(&effected); parent := story_condition_index(&edited, "completion_parent"); assert(parent >= 0 && edited.conditions[parent].child_id_count == 2 && edited.conditions[parent].child_ids[0] == "completion_child_b" && edited.nodes[0].effect_ids[0] == "completion_effect_a" && edited.nodes[0].effect_ids[1] == "completion_effect_b")
	assert(
		story_authoring_undo(&edited, &history) &&
		story_authoring_undo(&edited, &history) &&
		story_condition_index(&edited, "completion_parent") < 0,
	); assert(story_authoring_redo(&edited, &history) && story_authoring_redo(&edited, &history) && story_condition_index(&edited, "completion_parent") >= 0); story_project_destroy(&edited)

	// A StoryCore entity rename repairs both Graph-node and MysteryDomain refs;
	// deletion previews report those same cross-domain dependencies.
	cross := story_project_clone(
		&story,
	); cross_payload := mystery_payload(&cross); old_entity := cross_payload.characters[0].entity_id; new_entity := "completion_cross_domain_entity"; cross.nodes[0].speaker_id = old_entity
	preview := story_authoring_dependency_preview(
		&cross,
		.Entity,
		old_entity,
	); mystery_dependency := false; for dependency in preview.dependencies[:preview.dependency_count] do if strings.has_prefix(dependency.record_kind, "mystery.") do mystery_dependency = true; assert(mystery_dependency)
	rename := [1]Story_Authoring_Command {
		{kind = .Rename, record_kind = .Entity, id = old_entity, new_id = new_entity},
	}; renamed := story_authoring_apply(&cross, nil, rename[:]); assert(renamed.ok); cross_payload = mystery_payload(&cross); assert(cross.nodes[0].speaker_id == new_entity && cross_payload.characters[0].entity_id == new_entity); story_authoring_result_destroy(&renamed)
	remove := [1]Story_Authoring_Command {
		{kind = .Remove, record_kind = .Entity, id = new_entity},
	}; blocked := story_authoring_apply(&cross, nil, remove[:]); assert(!blocked.ok && blocked.blocked_by.dependency_count > 0); story_authoring_result_destroy(&blocked); story_project_destroy(&cross)

	// Route mutations are undoable, invalid ranges and missing references are
	// diagnosed, and essential prerequisite closure—not merely leaf clues—must
	// fit the budget and remain free of one-shot checks.
	routes := story_project_clone(
		&story,
	); routes_payload := mystery_payload(&routes); demo := routes_payload.demonstrations[0]; assert(demo.accepted_count > 0); demo.route_count = 1; demo.route_firsts[0] = 0; demo.route_counts[0] = demo.accepted_count
	mhistory: Mystery_Authoring_History; defer mystery_authoring_history_destroy(&mhistory); route_update := [1]Mystery_Authoring_Command{{kind = .Update, record_kind = .Demonstration, demonstration = demo}}; route_result := mystery_authoring_apply(&routes, &mhistory, route_update[:]); assert(route_result.ok && mystery_payload(&routes).demonstrations[0].route_count == 1); mystery_authoring_result_destroy(&route_result); assert(mystery_authoring_undo(&routes, &mhistory) && mystery_authoring_redo(&routes, &mhistory)); story_project_destroy(&routes)
	broken := story_project_clone(
		&story,
	); broken_payload := mystery_payload(&broken); broken_payload.demonstrations[0].route_counts[0] = broken_payload.demonstrations[0].accepted_count + 1; broken_validation := story_project_validate(&broken); assert(!broken_validation.ok && mystery_validation_has(&broken_validation, "route range")); story_validation_destroy(&broken_validation); story_project_destroy(&broken)
	broken = story_project_clone(
		&story,
	); broken_payload = mystery_payload(&broken); broken_payload.clues[0].prerequisites[0] = "missing_completion_clue"; broken_payload.clues[0].prerequisite_count = 1; broken_validation = story_project_validate(&broken); assert(!broken_validation.ok && mystery_validation_has(&broken_validation, "[routes]")); story_validation_destroy(&broken_validation); story_project_destroy(&broken)
	broken = story_project_clone(
		&story,
	); broken_payload = mystery_payload(&broken); essential_index := -1; for clue, i in broken_payload.clues do if clue.essential && essential_index < 0 do essential_index = i; assert(essential_index >= 0 && len(broken_payload.clues) > 1); prerequisite_index := essential_index == 0 ? 1 : 0; broken_payload.clues[prerequisite_index].essential = false; broken_payload.clues[essential_index].prerequisites[0] = broken_payload.clues[prerequisite_index].id; broken_payload.clues[essential_index].prerequisite_count = 1; broken_payload.clues[essential_index].cost = 1; broken_payload.clues[prerequisite_index].cost = 1; broken_payload.action_budget = 1; broken_validation = story_project_validate(&broken); assert(!broken_validation.ok && mystery_validation_has(&broken_validation, "[affordability]")); story_validation_destroy(&broken_validation); broken_payload.action_budget = 12; broken_payload.clues[prerequisite_index].check_kind = "red"; broken_validation = story_project_validate(&broken); assert(!broken_validation.ok && mystery_validation_has(&broken_validation, "[routes]")); story_validation_destroy(&broken_validation); story_project_destroy(&broken)

	// Player-safe serialization has an explicit allow-list and cannot leak any
	// creator-only secret, canonical claim truth, solution, ending timeline, or
	// hidden demonstration route.
	state := mystery_state_init(
		&story,
	); view := mystery_player_query(&story, &state); safe := mystery_player_view_serialize(&view); assert(!strings.contains(safe, "canonical_truth") && !strings.contains(safe, "culprit_id") && !strings.contains(safe, "canonical_timeline") && !strings.contains(safe, "route_firsts")); for character in payload.characters do if character.private_secret != "" do assert(!strings.contains(safe, character.private_secret)); if payload.solution.decisive_contradiction_id != "" do assert(!strings.contains(safe, payload.solution.decisive_contradiction_id)); mystery_player_view_destroy(&view); mystery_state_destroy(&state)
}
