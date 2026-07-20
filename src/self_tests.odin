package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"

count_discovered :: proc(g: ^Game) -> int {if g.mystery_state == nil do return 0; return len(
		g.mystery_state.acquired_evidence,
	)}
test_story_project: Story_Project
ensure_test_torn_story :: proc() {if test_story_project.id == "the_torn_appointment" do return
	if test_story_project.id != "" do story_project_destroy(&test_story_project)
	assert(
		load_story_project("assets/stories/mysteries/the_torn_appointment.story.toml", &test_story_project).ok,
	)}
initialize_test_mystery_state :: proc(g: ^Game) {ensure_test_torn_story()
	g.story_project = &test_story_project
	g.mystery_state = new(Mystery_State)
	g.mystery_state^ = mystery_state_init(&test_story_project)}

// Procedural window solids are authored around their local bounds. Every
// retained triangle must therefore point away from the solid's center; this
// catches reversed winding before back-face culling makes a window part vanish.
mesh_triangles_face_outward :: proc(mesh: ^Glb_Mesh) -> bool {
	if len(mesh.indices) == 0 || len(mesh.indices) % 3 != 0 do return false
	center := Vec3 {
		(mesh.min.x + mesh.max.x) * .5,
		(mesh.min.y + mesh.max.y) * .5,
		(mesh.min.z + mesh.max.z) * .5,
	}
	for triangle in 0 ..< len(mesh.indices) / 3 {
		i :=
			triangle *
			3; i0, i1, i2 := int(mesh.indices[i]), int(mesh.indices[i + 1]), int(mesh.indices[i + 2])
		if i0 < 0 || i0 >= len(mesh.vertices) || i1 < 0 || i1 >= len(mesh.vertices) || i2 < 0 || i2 >= len(mesh.vertices) do return false
		a, b, c := mesh.vertices[i0], mesh.vertices[i1], mesh.vertices[i2]
		ab, ac := Vec3{b.x - a.x, b.y - a.y, b.z - a.z}, Vec3{c.x - a.x, c.y - a.y, c.z - a.z}
		normal := Vec3 {
			ab.y * ac.z - ab.z * ac.y,
			ab.z * ac.x - ab.x * ac.z,
			ab.x * ac.y - ab.y * ac.x,
		}
		face_center := Vec3{(a.x + b.x + c.x) / 3, (a.y + b.y + c.y) / 3, (a.z + b.z + c.z) / 3}
		if normal.x * (face_center.x - center.x) + normal.y * (face_center.y - center.y) + normal.z * (face_center.z - center.z) <= 0 do return false
	}
	return true
}

glazing_is_single_sheet :: proc(mesh: ^Glb_Mesh) -> bool {
	return(
		len(mesh.vertices) == 4 &&
		len(mesh.indices) == 6 &&
		len(mesh.primitives) == 1 &&
		mesh.primitives[0].count == 6 &&
		mesh.min.z == 0 &&
		mesh.max.z == 0 \
	)
}

glazing_faces_both_outward_directions :: proc(mesh: ^Glb_Mesh) -> bool {
	return glazing_is_single_sheet(mesh)
}

run_story_core_tests :: proc() {
	balanced_text := text_layout_badness("alpha beta gamma delta", 110, 1)
	ragged_text := text_layout_badness("alpha beta gamma delta", 100, 1)
	assert(
		balanced_text.lines == 2 &&
		ragged_text.lines == 3 &&
		balanced_text.total < ragged_text.total &&
		ragged_text.orphan == 1,
	)
	assert(text_layout_badness("", 100, 1) == Text_Layout_Badness{lines = 1})
	balanced_value := "aaa bbb ccc ddd"; balanced_plan := text_layout_plan(balanced_value, 11); assert(len(balanced_plan) == 2 && balanced_value[balanced_plan[0].start:balanced_plan[0].end] == "aaa bbb" && balanced_value[balanced_plan[1].start:balanced_plan[1].end] == "ccc ddd")
	assert(
		len(text_layout_plan("abcdefghijklmnop", 5)) == 4 &&
		len(text_layout_plan("alpha\nbeta", 20)) == 2,
	)
	run_story_container_tests()
	run_story_spatial_tests()
	run_story_spatial_registry_tests()
	run_story_domain_lifecycle_tests()
	run_mystery_domain_tests()
	chain_events := [2]Workbench_Event {
		{time = 500, actor = "miriam", action = "strike", prop = "statuette", room = "study"},
		{time = 499, actor = "miriam", action = "move_body", prop = "body", room = "garden"},
	}; chain_support := [2]bool{true, true}; chain_result := simulate_workbench(chain_events[:], chain_support[:]); assert(!chain_result.physically_possible && chain_result.first_failed_event == 1 && strings.contains(chain_result.message, "Time runs backward")); chain_events[1].time = 507; chain_support[0] = false; chain_result = simulate_workbench(chain_events[:], chain_support[:]); assert(chain_result.physically_possible && chain_result.first_failed_event == 0 && strings.contains(chain_result.message, "exists only in theory")); chain_support[0] = true; chain_result = simulate_workbench(chain_events[:], chain_support[:]); assert(chain_result.physically_possible && chain_result.first_failed_event < 0 && strings.contains(chain_result.message, "chain holds"))
	project := Story_Project {
		version          = STORY_PROJECT_VERSION,
		id               = "story_core_test",
		title            = "Story Core Test",
		content_version  = "1.0.0",
		default_space_id = "level",
		revision         = 7,
	}
	defer story_project_destroy(&project)
	append(
		&project.entities,
		Story_Entity{id = "detective", kind = "actor", display_name = "Detective"},
		Story_Entity{id = "miriam", kind = "actor", display_name = "Miriam"},
	)
	project.entities[1].roles[0] = "suspect"; project.entities[1].role_count = 1
	append(
		&project.roles,
		Story_Role{id = "suspect", display_name = "Suspect", minimum = 1, maximum = 4},
	)
	append(
		&project.variables,
		Story_Variable {
			id = "trust",
			display_name = "Trust",
			kind = .Integer,
			default_value = story_value_integer(0),
			minimum = -2,
			maximum = 2,
		},
		Story_Variable {
			id = "door_open",
			display_name = "Door open",
			kind = .Boolean,
			default_value = story_value_boolean(false),
		},
	)
	append(
		&project.propositions,
		Story_Proposition {
			id = "prop_arrival",
			text = "Miriam arrived before nine.",
			canonical_truth = .False,
		},
	)
	append(
		&project.facts,
		Story_Fact {
			id = "arrival_fact",
			display_name = "Arrival",
			proposition = "prop_arrival",
			canonical_truth = .False,
			player_visible = true,
		},
	)
	append(
		&project.relationships,
		Story_Relationship {
			id = "miriam_trust",
			source_id = "miriam",
			target_id = "detective",
			kind = "trust",
			variable_id = "trust",
		},
	)
	append(
		&project.objectives,
		Story_Objective {
			id = "learn_arrival",
			display_name = "Learn the arrival time",
			description = "Ask what time Miriam arrived.",
			initial_status = .Active,
		},
		Story_Objective {
			id = "compare_account",
			display_name = "Compare the account",
			description = "Test the statement against what is known.",
		},
		Story_Objective {
			id = "hidden_truth",
			display_name = "Hidden truth",
			description = "Creator-only objective.",
			hidden = true,
			initial_status = .Active,
		},
	)
	append(
		&project.events,
		Story_Event{id = "arrival_revealed", subject_id = "miriam", action = "reveal"},
	)
	project.events[0].witnesses[0] = "detective"; project.events[0].witness_count = 1
	append(
		&project.conditions,
		Story_Condition{kind = .Always},
		Story_Condition {
			kind = .Integer_Compare,
			variable_id = "trust",
			comparison = .Greater_Equal,
			value = story_value_integer(1),
		},
		Story_Condition{kind = .Aware, entity_id = "detective", proposition_id = "prop_arrival"},
	)
	append(
		&project.effects,
		Story_Effect{kind = .Add_Integer, variable_id = "trust", value = story_value_integer(1)},
		Story_Effect {
			kind = .Communicate,
			actor_id = "miriam",
			other_actor_id = "detective",
			proposition_id = "prop_arrival",
			belief_stance = .Uncertain,
			content_id = "arrival_scene",
		},
		Story_Effect {
			kind = .Set_Objective,
			objective_id = "learn_arrival",
			objective_status = .Completed,
		},
		Story_Effect {
			kind = .Set_Objective,
			objective_id = "compare_account",
			objective_status = .Active,
		},
		Story_Effect{kind = .Add_Integer, variable_id = "trust", value = story_value_integer(9)},
	)
	project.effects[2].content_id = "test.objective_milestone"; project.effects[3].content_id = "test.objective_milestone"
	project.conditions[0].id = "condition_always"; project.effects[0].id = "effect_raise_trust"
	append(
		&project.scenes,
		Story_Scene{id = "fallback_scene", display_name = "Ordinary greeting"},
		Story_Scene {
			id = "arrival_scene",
			display_name = "Arrival reaction",
			entry_node = "arrival_line",
		},
	)
	append(
		&project.nodes,
		Story_Node {
			id = "arrival_line",
			scene_id = "arrival_scene",
			line_id = "arrival.line",
			speaker_id = "miriam",
			text = "I arrived after nine.",
			next = "arrival_end",
			kind = .Line,
			condition_root = 0,
			first_effect = 0,
			effect_count = 1,
		},
		Story_Node {
			id = "arrival_end",
			scene_id = "arrival_scene",
			kind = .End,
			condition_root = 0,
		},
	)
	append(
		&project.scenes,
		Story_Scene {
			id = "z_choice_scene",
			display_name = "Choice test",
			entry_node = "z_choice_prompt",
		},
	)
	choice_node := Story_Node {
		id           = "z_choice_prompt",
		scene_id     = "z_choice_scene",
		kind         = .Choice,
		condition_id = "condition_always",
		ui           = "dialogue",
		camera       = "close",
		summary      = "Choose a reply",
	}; choice_node.choices[0] = {
		id     = "accept",
		label  = "Accept",
		target = "z_choice_end",
	}; choice_node.choice_count = 1; append(&project.nodes, choice_node, Story_Node{id = "z_choice_end", scene_id = "z_choice_scene", kind = .End, condition_id = "condition_always"})
	append(
		&project.scenes,
		Story_Scene {
			id = "z_input_scene",
			display_name = "Input test",
			entry_node = "z_interaction",
		},
	); append(&project.nodes, Story_Node{id = "z_interaction", scene_id = "z_input_scene", kind = .Interaction, condition_id = "condition_always", success = "z_wait"}, Story_Node{id = "z_wait", scene_id = "z_input_scene", kind = .Wait_Event, condition_id = "condition_always", event_id = "door_opened", next = "z_input_end"}, Story_Node{id = "z_input_end", scene_id = "z_input_scene", kind = .End, condition_id = "condition_always"})
	append(&project.storylet_groups, Story_Storylet_Group{id = "miriam_greeting"})
	fallback := Story_Storylet {
		id             = "ordinary_greeting",
		group          = "miriam_greeting",
		scene_id       = "fallback_scene",
		fallback       = true,
		authored_order = 10,
		repeat_policy  = .Always,
	}; fallback.condition_roots[0] = 0; fallback.condition_count = 1
	reaction := Story_Storylet {
		id                = "arrival_reaction",
		group             = "miriam_greeting",
		scene_id          = "arrival_scene",
		dramatic_priority = 10,
		specificity       = 2,
		authored_order    = 1,
		repeat_policy     = .Once,
	}; reaction.condition_roots[0] = 1; reaction.condition_roots[1] = 2; reaction.condition_count = 2
	append(&project.storylets, fallback, reaction)
	append(
		&project.endings,
		Story_Ending {
			id = "truth",
			title = "The Truth",
			summary = "The arrival is understood.",
			condition_root = 2,
			priority = 10,
		},
	)
	append(
		&project.invariants,
		Story_Invariant {
			id = "trust_bounded",
			description = "Trust remains within its declared bounds.",
			kind = .Always,
			condition_root = 0,
			required = true,
		},
	)

	validation := story_project_validate(
		&project,
	); assert(validation.ok && validation.error_count == 0); story_validation_destroy(&validation)
	parsed_status, parsed_ok := story_objective_status_from_text(
		"",
	); assert(parsed_ok && parsed_status == .Inactive); _, parsed_ok = story_objective_status_from_text("typo"); assert(!parsed_ok)
	state := story_state_new(&project); defer story_state_destroy(&state)
	assert(
		state.schema_identity == story_schema_identity(&project) &&
		len(state.values) == 2 &&
		len(state.objectives) == 3,
	)
	assert(
		story_tracked_objective_index(&project, &state) == 0 &&
		state.objectives[0].activated_sequence > 0,
	)
	milestone_state := story_state_new(&project); milestone_game := Game {
		story_project = &project,
		story_state   = &milestone_state,
	}; assert(
		game_story_milestone(&milestone_game, "test.objective_milestone") &&
		milestone_state.objectives[0].status == .Completed &&
		milestone_state.objectives[1].status == .Active,
	); story_state_destroy(&milestone_state)
	initial := storylet_select(
		&project,
		&state,
		"miriam_greeting",
	); assert(initial.found && project.storylets[initial.storylet_index].id == "ordinary_greeting"); storylet_selection_destroy(&initial)

	effects := [4]int {
		0,
		1,
		2,
		3,
	}; transaction := story_apply_transaction(&project, &state, effects[:]); assert(transaction.ok && transaction.trace.count == 4)
	assert(state.values[story_state_value_index(&state, "trust")].value.integer_value == 1)
	assert(
		story_state_knowledge_index(&state, "detective", "prop_arrival") >= 0 &&
		len(state.communications) == 1,
	)
	assert(
		state.objectives[story_state_objective_index(&state, "learn_arrival")].status ==
		.Completed,
	)
	assert(
		story_tracked_objective_index(&project, &state) == 1 &&
		state.objectives[1].activated_sequence > state.objectives[0].activated_sequence &&
		state.objectives[0].completed_sequence > 0,
	)
	saved_objectives := story_state_clone(
		&state,
	); assert(saved_objectives.objectives[0].completed_sequence == state.objectives[0].completed_sequence && saved_objectives.objectives[1].activated_sequence == state.objectives[1].activated_sequence); story_state_destroy(&saved_objectives)
	state.objectives[0].status = .Active; state.objectives[0].activated_sequence = 0; state.objectives[1].activated_sequence = 0; assert(story_tracked_objective_index(&project, &state) == 0); state.objectives[0].status = .Completed
	tracker_game := Game {
		story_project = &project,
		story_state   = &state,
		screen        = .Investigate,
		guidance_mode = .Adaptive,
	}; defer delete(
		tracker_game.quest_transition_ids,
	); defer delete(tracker_game.quest_transition_status); quest_tracker_sync(&tracker_game); assert(len(tracker_game.quest_transition_ids) == 0 && quest_tracker_enabled(&tracker_game)); tracker_game.guidance_mode = .Minimal; assert(!quest_tracker_enabled(&tracker_game)); tracker_game.guidance_mode = .Full; tracker_game.screen = .Exterior; assert(quest_tracker_enabled(&tracker_game)); tracker_game.screen = .Dialogue; assert(!quest_tracker_enabled(&tracker_game)); tracker_game.screen = .Investigate
	for i in 0 ..< 32 do quest_transition_enqueue(&tracker_game, "compare_account", .Active); assert(len(tracker_game.quest_transition_ids) == 32); clear(&tracker_game.quest_transition_ids); clear(&tracker_game.quest_transition_status)
	state.objectives[1].status = .Completed; state.objectives[1].completed_sequence = state.sequence + 1; state.objectives[0].status = .Active; state.objectives[0].activated_sequence = state.sequence + 2; quest_tracker_sync(&tracker_game); assert(len(tracker_game.quest_transition_ids) == 2 && tracker_game.quest_transition_status[0] == .Completed && tracker_game.quest_transition_status[1] == .Active); tracker_game.animation_time = 2; quest_tracker_sync(&tracker_game); assert(len(tracker_game.quest_transition_ids) == 1 && tracker_game.quest_transition_status[0] == .Active)
	aware := story_condition_eval(&project, &state, 2); assert(aware.value)
	selected := storylet_select(
		&project,
		&state,
		"miriam_greeting",
	); assert(selected.found && project.storylets[selected.storylet_index].id == "arrival_reaction" && strings.contains(selected.explanation, "priority 10")); storylet_selection_destroy(&selected)

	before := state.values[story_state_value_index(&state, "trust")].value.integer_value
	bad_effect := [1]int {
		4,
	}; failed := story_apply_transaction(&project, &state, bad_effect[:]); assert(!failed.ok && state.values[story_state_value_index(&state, "trust")].value.integer_value == before)

	add := Story_Command {
		kind = .Add_Entity,
		entity = Story_Entity{id = "door", kind = "object", display_name = "Door"},
	}
	commands := [1]Story_Command {
		add,
	}; dry := story_command_batch(&project, 7, commands[:], true); assert(dry.ok && dry.revision == 8 && story_entity_index(&project, "door") == -1); story_command_result_destroy(&dry)
	committed := story_command_batch(
		&project,
		7,
		commands[:],
	); assert(committed.ok && project.revision == 8 && story_entity_index(&project, "door") >= 0); story_command_result_destroy(&committed)
	stale := story_command_batch(
		&project,
		7,
		commands[:],
	); assert(!stale.ok && stale.stale && project.revision == 8); story_command_result_destroy(&stale)
	add_role := Story_Command {
		kind = .Add_Record,
		record_kind = .Role,
		role = Story_Role{id = "witness", display_name = "Witness"},
	}; role_commands := [1]Story_Command {
		add_role,
	}; role_result := story_command_batch(&project, 8, role_commands[:]); assert(role_result.ok && role_result.revision == 9 && strings.contains(role_result.impact_summary, "1 record")); story_command_result_destroy(&role_result)
	updated_miriam :=
		project.entities[story_entity_index(&project, "miriam")]; updated_miriam.display_name = "Miriam Vale"; update_entity := Story_Command {
		kind        = .Update_Record,
		record_kind = .Entity,
		entity      = updated_miriam,
	}; update_commands := [1]Story_Command {
		update_entity,
	}; update_result := story_command_batch(&project, 9, update_commands[:]); assert(update_result.ok && project.entities[story_entity_index(&project, "miriam")].display_name == "Miriam Vale"); story_command_result_destroy(&update_result)
	bad_fact := Story_Command {
		kind = .Add_Record,
		record_kind = .Fact,
		fact = Story_Fact{id = "bad_fact", proposition = "missing"},
	}; bad_commands := [1]Story_Command {
		bad_fact,
	}; bad_result := story_command_batch(&project, 10, bad_commands[:]); assert(!bad_result.ok && project.revision == 10 && len(project.facts) == 1); story_command_result_destroy(&bad_result)
	capabilities := story_capabilities(

	); core_capability := false; for capability in capabilities.domains[:capabilities.domain_count] do if capability.id == STORY_DOMAIN_CORE do core_capability = true; assert(capabilities.revision_checked_commands && capabilities.deterministic_compile && capabilities.scene_runtime && capabilities.domain_count >= 1 && core_capability)
	unknown_domain := story_project_clone(
		&project,
	); append(&unknown_domain.capabilities, Story_Capability_Requirement{id = "unregistered", version = "1"}); unknown_validation := story_project_validate(&unknown_domain); assert(!unknown_validation.ok); story_validation_destroy(&unknown_validation); story_project_destroy(&unknown_domain)
	search := story_reference_search(
		&project,
		"arrival",
	); assert(len(search.items) >= 4); story_reference_query_destroy(&search)
	dependencies := story_dependencies(
		&project,
		"prop_arrival",
	); assert(len(dependencies.dependents) >= 1 && dependencies.dependents[0].id == "arrival_fact"); story_dependency_query_destroy(&dependencies)
	compiled := compile_story_project(
		&project,
	); assert(compiled.ok); defer story_compile_result_destroy(&compiled)
	compile_source := story_project_clone(
		&project,
	); defer story_project_destroy(&compile_source); append(&compile_source.expansion_requirements, Story_Expansion_Requirement{id = "optional_weather", version = "1", optional = true, fallback = .Omit}); append(&compile_source.resolved_environment.expansions, Resolved_Story_Expansion{id = "sentinel", version = "1", content_hash = "unchanged"}); compile_source.resolved_environment.identity = 77; before_compile := story_project_serialize(&compile_source); side_effect_check := compile_story_project(&compile_source); assert(side_effect_check.ok && story_project_serialize(&compile_source) == before_compile && compile_source.resolved_environment.identity == 77); story_compile_result_destroy(&side_effect_check)
	dependency_order_a := story_project_clone(
		&project,
	); defer story_project_destroy(&dependency_order_a); append(&dependency_order_a.expansion_requirements, Story_Expansion_Requirement{id = "optional_a", version = "1", optional = true, fallback = .Omit}, Story_Expansion_Requirement{id = "optional_b", version = "1", optional = true, fallback = .Omit}); dependency_order_b := story_project_clone(&dependency_order_a); defer story_project_destroy(&dependency_order_b); dependency_order_b.expansion_requirements[0], dependency_order_b.expansion_requirements[1] = dependency_order_b.expansion_requirements[1], dependency_order_b.expansion_requirements[0]; order_a := compile_story_project(&dependency_order_a); order_b := compile_story_project(&dependency_order_b); assert(order_a.ok && order_b.ok && order_a.story.content_identity == order_b.story.content_identity); story_compile_result_destroy(&order_a); story_compile_result_destroy(&order_b)
	assert(
		compiled.story.entities[0].stable_id == "detective" &&
		compiled.story.entities[1].stable_id == "door" &&
		compiled.story.nodes[0].stable_id == "arrival_end",
	)
	runtime := story_runtime_new(&compiled.story); defer story_runtime_destroy(&runtime)
	presented := story_runtime_enter_scene(
		&runtime,
		"arrival_scene",
	); assert(presented.ok && presented.line_id == "arrival.line")
	advanced := story_runtime_advance(
		&runtime,
	); assert(advanced.ok && advanced.kind == .End && advanced.trace.count == 1 && runtime.state.values[story_state_value_index(&runtime.state, "trust")].value.integer_value == 1)
	finished := story_runtime_advance(
		&runtime,
	); assert(finished.ok && finished.finished && story_state_history_index(runtime.state.completed_scenes[:], "arrival_scene") >= 0)
	choice_step := story_runtime_enter_scene(
		&runtime,
		"z_choice_scene",
	); assert(choice_step.ok && choice_step.expected == .Choice && choice_step.choice_count == 1 && choice_step.ui == "dialogue"); saved := story_runtime_save(&runtime); choice_step = story_runtime_choose(&runtime, "accept"); assert(choice_step.ok && choice_step.node_id == "z_choice_end"); assert(story_runtime_restore(&runtime, &saved) && runtime.current_node == "z_choice_prompt"); story_runtime_save_destroy(&saved)
	input_step := story_runtime_enter_scene(
		&runtime,
		"z_input_scene",
	); assert(input_step.ok && input_step.expected == .Resolution); input_step = story_runtime_resolve(&runtime, "success"); assert(input_step.ok && input_step.expected == .Signal && !story_runtime_signal(&runtime, "wrong").ok); input_step = story_runtime_signal(&runtime, "door_opened"); assert(input_step.ok && input_step.node_id == "z_input_end")
	reordered := story_project_clone(
		&project,
	); defer story_project_destroy(&reordered); reordered.entities[0], reordered.entities[2] = reordered.entities[2], reordered.entities[0]; reordered.conditions[0], reordered.conditions[2] = reordered.conditions[2], reordered.conditions[0]; reordered.effects[0], reordered.effects[2] = reordered.effects[2], reordered.effects[0]
	recompiled := compile_story_project(
		&reordered,
	); assert(recompiled.ok && recompiled.story.content_identity == compiled.story.content_identity); defer story_compile_result_destroy(&recompiled)
	meaningful := story_project_clone(
		&project,
	); defer story_project_destroy(&meaningful); meaningful.scenes[0].summary = "A materially different authored summary."; meaningful.roles[0].maximum += 1
	meaningful_compiled := compile_story_project(
		&meaningful,
	); assert(meaningful_compiled.ok && meaningful_compiled.story.content_identity != compiled.story.content_identity); defer story_compile_result_destroy(&meaningful_compiled)

	proof: Story_Project; assert(load_story_project(STORY_BLANK_PROOF_PATH, &proof).ok); defer story_project_destroy(&proof)
	assert(
		len(proof.capabilities) == 0 &&
		len(proof.entities) == 4 &&
		len(proof.roles) == 2 &&
		len(proof.variables) >= 2 &&
		len(proof.storylets) >= 3,
	)
	assert(
		proof.entities[0].spatial.space_id == "vale_house" &&
		proof.entities[0].spatial.target_id != "",
	)
	proof_state := story_state_new(&proof); defer story_state_destroy(&proof_state)
	proof_selection := storylet_select(
		&proof,
		&proof_state,
		"ada_contextual_greeting",
	); assert(proof_selection.found && proof.storylets[proof_selection.storylet_index].id == "ada_first_meeting_storylet"); storylet_selection_destroy(&proof_selection)
	proof_compiled := compile_story_project(
		&proof,
	); assert(proof_compiled.ok); defer story_compile_result_destroy(&proof_compiled)
	proof_runtime := story_runtime_new(
		&proof_compiled.story,
	); defer story_runtime_destroy(&proof_runtime)
	step := story_runtime_enter_scene(
		&proof_runtime,
		"ada_first_meeting",
	); assert(step.ok && step.node_id == "ada_greeting")
	step = story_runtime_advance(
		&proof_runtime,
	); step = story_runtime_choose(&proof_runtime, "player_first_choice.choice.0"); assert(step.ok && step.node_id == "ada_accepts_help")
	step = story_runtime_advance(&proof_runtime); _ = story_runtime_advance(&proof_runtime)
	step = story_runtime_enter_scene(
		&proof_runtime,
		"ada_explains_lantern",
	); step = story_runtime_advance(&proof_runtime); step = story_runtime_choose(&proof_runtime, "player_lantern_choice.choice.0"); assert(step.ok && step.node_id == "player_relights_lantern")
	step = story_runtime_advance(&proof_runtime); _ = story_runtime_advance(&proof_runtime)
	step = story_runtime_enter_scene(
		&proof_runtime,
		"ada_thanks_player",
	); step = story_runtime_advance(&proof_runtime); step = story_runtime_advance(&proof_runtime); step = story_runtime_advance(&proof_runtime); step = story_runtime_choose(&proof_runtime, "player_bell_choice.choice.0"); assert(step.ok && step.node_id == "player_rings_bell")
	step = story_runtime_advance(&proof_runtime); _ = story_runtime_advance(&proof_runtime)
	step = story_runtime_enter_scene(
		&proof_runtime,
		"bell_memory",
	); step = story_runtime_advance(&proof_runtime); step = story_runtime_choose(&proof_runtime, "player_memory_choice.choice.1"); assert(step.ok && step.node_id == "player_comforts_ada")
	step = story_runtime_advance(
		&proof_runtime,
	); step = story_runtime_advance(&proof_runtime); step = story_runtime_choose(&proof_runtime, "memory_second_choice.choice.1"); assert(step.ok && step.node_id == "ada_calls_thomas")
	step = story_runtime_advance(&proof_runtime); _ = story_runtime_advance(&proof_runtime)
	step = story_runtime_enter_scene(
		&proof_runtime,
		"ghost_threshold",
	); step = story_runtime_advance(&proof_runtime); step = story_runtime_choose(&proof_runtime, "ada_threshold_choice.choice.0"); assert(step.ok && step.node_id == "ada_asks_forgiveness")
	step = story_runtime_advance(&proof_runtime); _ = story_runtime_advance(&proof_runtime)
	step = story_runtime_enter_scene(
		&proof_runtime,
		"ada_release",
	); step = story_runtime_advance(&proof_runtime); step = story_runtime_choose(&proof_runtime, "player_final_choice.choice.0"); assert(step.ok && step.node_id == "player_releases_ghosts")
	step = story_runtime_advance(&proof_runtime); _ = story_runtime_advance(&proof_runtime)
	assert(
		proof_runtime.state.objectives[story_state_objective_index(&proof_runtime.state, "help_ada")].status ==
		.Completed,
	)
	lantern_event, bell_event, threshold_event :=
		false,
		false,
		false; for event in proof_runtime.state.emitted_events {if event == "lantern_repaired" do lantern_event = true; if event == "memory_bell_rang" do bell_event = true; if event == "ghost_threshold_opened" do threshold_event = true}; assert(lantern_event && bell_event && threshold_event)
	roundtrip_path := "/private/tmp/chicago-interactive-story-roundtrip.toml"; assert(save_story_project(roundtrip_path, &project).ok); roundtrip: Story_Project; assert(load_story_project(roundtrip_path, &roundtrip).ok); defer story_project_destroy(&roundtrip)
	legacy_path := "/private/tmp/chicago-legacy-domain.story.toml"; legacy_source := "version = \"InteractiveStory v1\"\nid = \"legacy\"\ntitle = \"Legacy\"\ncreator = \"Test\"\ndescription = \"Legacy domain\"\ncontent_version = \"1.0.0\"\ndomain = \"mystery\"\ndomain_version = \"1\"\n"; assert(os.write_entire_file(legacy_path, transmute([]byte)legacy_source) == nil); legacy_project: Story_Project; legacy_result := load_story_project(legacy_path, &legacy_project); assert(!legacy_result.ok && strings.contains(legacy_result.message, "regenerate or migrate"))
	assert(
		len(roundtrip.roles) == 2 &&
		len(roundtrip.facts) == 1 &&
		len(roundtrip.relationships) == 1 &&
		len(roundtrip.nodes) == 7 &&
		len(roundtrip.endings) == 1 &&
		len(roundtrip.invariants) == 1 &&
		roundtrip.default_space_id == project.default_space_id,
	)
	assert(
		roundtrip.events[0].witness_count == 1 &&
		roundtrip.events[0].witnesses[0] == "detective" &&
		roundtrip.nodes[0].line_id == "arrival.line",
	)
	assert(
		roundtrip.conditions[0].id == "condition_always" &&
		roundtrip.effects[0].id == "effect_raise_trust",
	)
}

run_authoring_foundation_tests :: proc() {
	project, project_ok := authoring_project_new(
		"project_alpha",
		"Project Alpha",
		"/projects/alpha",
	); assert(project_ok)
	assert(
		!authoring_relative_path_valid("") &&
		!authoring_relative_path_valid("/absolute/story.toml") &&
		!authoring_relative_path_valid("C:/story.toml") &&
		!authoring_relative_path_valid("cases\\case_a\\story.toml") &&
		!authoring_relative_path_valid("cases/../story.toml") &&
		!authoring_relative_path_valid("cases//story.toml"),
	)
	resolved, resolved_ok := authoring_resolve_path(
		&project,
		"cases/case_a/story.toml",
	); assert(resolved_ok && resolved == "/projects/alpha/cases/case_a/story.toml")
	assert(
		authoring_project_add_case(&project, "case_a", "Case A") &&
		authoring_project_add_case(&project, "case_b", "Case B") &&
		!authoring_project_add_case(&project, "case_a", "Duplicate"),
	)
	case_a := &project.cases[0]; case_b := &project.cases[1]; assert(case_a.paths.story != case_b.paths.story && case_a.paths.level != case_b.paths.level && case_a.paths.graph_layout != case_b.paths.graph_layout && case_a.paths.story_autosave != case_b.paths.story_autosave)
	assert(
		authoring_project_switch_case(&project, "case_b") &&
		authoring_project_active_case(&project).id == "case_b" &&
		!authoring_project_switch_case(&project, "missing"),
	)
	authoring_case_mark_dirty(
		case_a,
		.Story,
		2,
	); authoring_case_mark_dirty(case_a, .Graph_Layout, 3); assert(authoring_case_dirty(case_a) && authoring_project_dirty(&project) && !authoring_case_dirty(case_b)); authoring_case_mark_saved(case_a, .Story, 2); assert(authoring_case_dirty(case_a)); authoring_case_mark_saved(case_a, .Graph_Layout, 3); assert(!authoring_project_dirty(&project))

	draft := authoring_validation_snapshot_init(
		.Draft,
		1,
	); defer authoring_validation_snapshot_destroy(&draft)
	assert(
		authoring_validation_touch_domain(&draft, .Story_Core, 4) &&
		!authoring_validation_domain_fresh(&draft, .Story_Core) &&
		authoring_validation_mark_domain_valid(&draft, .Story_Core, 4) &&
		authoring_validation_domain_fresh(&draft, .Story_Core),
	)
	warning := authoring_diagnostic_init(
		.Story_Core,
		"story",
		"entity_a",
		"display_name",
		.Warning,
		"Name could be clearer",
	); error := authoring_diagnostic_init(.Graph, "graph", "node_a", "target", .Error, "Target is missing"); incoming := [2]Authoring_Diagnostic{warning, error}; authoring_validation_merge(&draft, incoming[:]); assert(len(draft.diagnostics) == 2 && !authoring_validation_is_blocked(&draft)); draft.profile = .Playable; assert(authoring_validation_is_blocked(&draft)); draft.profile = .Exportable; assert(authoring_validation_is_blocked(&draft)); authoring_validation_invalidate_domain(&draft, .Graph); assert(len(draft.diagnostics) == 1); authoring_validation_touch_domain(&draft, .Story_Core, 5); assert(!authoring_validation_domain_fresh(&draft, .Story_Core) && authoring_validation_is_blocked(&draft))

	authored: Story_Project; assert(load_story_project(STORY_BLANK_PROOF_PATH, &authored).ok); defer story_project_destroy(&authored)
	history: Story_Authoring_History; defer story_authoring_history_destroy(&history)
	metadata := [1]Story_Authoring_Command {
		{
			kind = .Set_Metadata,
			metadata = {
				id = authored.id,
				title = "Transactionally Edited",
				creator = "Self Test",
				description = "Metadata history",
				content_version = "2",
				default_space_id = authored.default_space_id,
			},
		},
	}; metadata_result := story_authoring_apply(&authored, &history, metadata[:]); assert(metadata_result.ok && authored.title == "Transactionally Edited" && authored.creator == "Self Test"); story_authoring_result_destroy(&metadata_result); assert(story_authoring_undo(&authored, &history) && authored.title != "Transactionally Edited" && story_authoring_redo(&authored, &history) && authored.title == "Transactionally Edited")
	expansion_commands := [2]Story_Authoring_Command {
		{
			kind = .Add_Expansion,
			expansion = {id = "weather", version = "1", optional = true, fallback = .Omit},
		},
		{
			kind = .Add_Expansion,
			expansion = {id = "wardrobe", version = "2", distribution = .Embed},
		},
	}; expansions_added := story_authoring_apply(&authored, &history, expansion_commands[:]); assert(expansions_added.ok && len(authored.expansion_requirements) == 2); story_authoring_result_destroy(&expansions_added)
	expansion_update := [2]Story_Authoring_Command {
		{
			kind = .Update_Expansion,
			from = 0,
			expansion = {
				id = "weather",
				version = "1.1",
				optional = true,
				distribution = .Embed,
				fallback = .Omit,
			},
		},
		{kind = .Reorder_Expansion, from = 0, to = 1},
	}; expansions_updated := story_authoring_apply(&authored, &history, expansion_update[:]); assert(expansions_updated.ok && authored.expansion_requirements[1].id == "weather" && authored.expansion_requirements[1].version == "1.1"); story_authoring_result_destroy(&expansions_updated); expansion_remove := [1]Story_Authoring_Command{{kind = .Remove_Expansion, from = 0}}; expansion_removed := story_authoring_apply(&authored, &history, expansion_remove[:]); assert(expansion_removed.ok && len(authored.expansion_requirements) == 1); story_authoring_result_destroy(&expansion_removed)
	capability_payload := new(
		u64,
	); capability_payload^ = 71; defer free(capability_payload); capability_two_payload := new(u64); capability_two_payload^ = 72; defer free(capability_two_payload)
	capability_commands := [2]Story_Authoring_Command {
		{
			kind = .Add_Capability,
			capability = {id = "test_domain", version = "1", payload = capability_payload},
		},
		{
			kind = .Add_Capability,
			capability = {id = "test_domain_two", version = "1", payload = capability_two_payload},
		},
	}; capabilities_added := story_authoring_apply(&authored, &history, capability_commands[:]); assert(capabilities_added.ok && len(authored.capabilities) == 2 && authored.capabilities[0].payload != capability_payload && (cast(^u64)authored.capabilities[0].payload)^ == 71); story_authoring_result_destroy(&capabilities_added)
	owned_before :=
		authored.capabilities[0].payload; capability_update := [2]Story_Authoring_Command{{kind = .Update_Capability, from = 0, capability = {id = "test_domain", version = "1", payload = owned_before}}, {kind = .Reorder_Capability, from = 0, to = 1}}; capabilities_updated := story_authoring_apply(&authored, &history, capability_update[:]); assert(capabilities_updated.ok && authored.capabilities[1].id == "test_domain" && authored.capabilities[1].payload != owned_before && (cast(^u64)authored.capabilities[1].payload)^ == 71); story_authoring_result_destroy(&capabilities_updated); capability_remove := [1]Story_Authoring_Command{{kind = .Remove_Capability, from = 0}}; capability_removed := story_authoring_apply(&authored, &history, capability_remove[:]); assert(capability_removed.ok && len(authored.capabilities) == 1 && authored.capabilities[0].id == "test_domain"); story_authoring_result_destroy(&capability_removed)
	revision_before_rejection :=
		authored.revision; unknown_capability := [1]Story_Authoring_Command{{kind = .Add_Capability, capability = {id = "unsupported", version = "1"}}}; unknown_result := story_authoring_apply(&authored, &history, unknown_capability[:]); assert(!unknown_result.ok && authored.revision == revision_before_rejection && len(authored.capabilities) == 1); story_authoring_result_destroy(&unknown_result)
	add_entity := [1]Story_Authoring_Command {
		{
			kind = .Add_Entity,
			entity = {id = "test_editor_entity", kind = "person", display_name = "Editor Entity"},
		},
	}; added := story_authoring_apply(&authored, &history, add_entity[:]); assert(added.ok && story_entity_index(&authored, "test_editor_entity") >= 0); story_authoring_result_destroy(&added)
	add_prop := [1]Story_Authoring_Command {
		{
			kind = .Add_Proposition,
			proposition = {id = "test_editor_proposition", text = "An editor proposition."},
		},
	}; prop_added := story_authoring_apply(&authored, &history, add_prop[:]); assert(prop_added.ok); story_authoring_result_destroy(&prop_added); append(&authored.facts, Story_Fact{id = "test_editor_fact", display_name = "Editor fact", proposition = "test_editor_proposition", canonical_truth = .True})
	remove_prop := [1]Story_Authoring_Command {
		{kind = .Remove, record_kind = .Proposition, id = "test_editor_proposition"},
	}; blocked := story_authoring_apply(&authored, &history, remove_prop[:]); assert(!blocked.ok && blocked.blocked_by.dependency_count > 0 && story_proposition_index(&authored, "test_editor_proposition") >= 0); story_authoring_result_destroy(&blocked)
	rename_prop := [1]Story_Authoring_Command {
		{
			kind = .Rename,
			record_kind = .Proposition,
			id = "test_editor_proposition",
			new_id = "test_editor_proposition_renamed",
		},
	}; renamed := story_authoring_apply(&authored, &history, rename_prop[:]); assert(renamed.ok && authored.facts[len(authored.facts) - 1].proposition == "test_editor_proposition_renamed"); story_authoring_result_destroy(&renamed); assert(story_authoring_undo(&authored, &history) && authored.facts[len(authored.facts) - 1].proposition == "test_editor_proposition"); assert(story_authoring_redo(&authored, &history) && authored.facts[len(authored.facts) - 1].proposition == "test_editor_proposition_renamed")

	graph_import_story(
		&authored,
	); assert(graph_document.scene_count > 0); expected_name := graph_document.scenes[0].scene.display_name; rebuilt: Story_Project; built := graph_build_story_project(&authored, &rebuilt); assert(built.ok && rebuilt.scenes[0].display_name == expected_name); story_project_destroy(&rebuilt)
	oversized := story_project_clone(
		&authored,
	); defer story_project_destroy(&oversized); for i in len(oversized.nodes) ..= GRAPH_MAX_NODES do append(&oversized.nodes, Story_Node{id = fmt.tprintf("overflow_%d", i)}); graph_import_story(&oversized); assert(graph_source_project == nil && graph_document.node_count == 0 && graph_document.error_count == 1); blocked_rebuild: Story_Project; assert(!graph_build_story_project(&oversized, &blocked_rebuild).ok); graph_import_story(&authored)
}

run_authoring_lifecycle_workflow_tests :: proc() {
	root := "/private/tmp/chicago-authoring-lifecycle-workflows"
	if os.exists(root) do assert(os.remove_all(root) == nil)
	assert(os.make_directory_all(root) == nil)
	project, ok := authoring_project_new("lifecycle_ui", "Lifecycle UI", root); assert(ok)
	assert(authoring_create_case_template(&project, "case_a", "Case A", .General_Story).ok)
	assert(authoring_create_case_template(&project, "case_b", "Case B", .Mystery).ok)
	assert(project.case_count == 2 && authoring_project_switch_case(&project, "case_b"))

	recents: Authoring_Recent_Projects
	authoring_recent_record(&recents, &project, 1)
	second, second_ok := authoring_project_new(
		"second_project",
		"Second Project",
		"/private/tmp/chicago-authoring-lifecycle-second",
	); assert(second_ok)
	authoring_recent_record(&recents, &second, 2); authoring_recent_record(&recents, &project, 3)
	assert(
		recents.count == 2 &&
		recents.items[0].id == "second_project" &&
		recents.items[1].id == "lifecycle_ui" &&
		recents.items[1].opened_sequence == 3,
	)
	recents_path := fmt.tprintf(
		"%s/recent-projects.toml",
		root,
	); assert(authoring_recents_save(&recents, recents_path).ok); loaded_recents: Authoring_Recent_Projects; assert(authoring_recents_load(recents_path, &loaded_recents).ok && loaded_recents.count == 2 && loaded_recents.items[1].root_path == root)

	duplicate := authoring_case_operation_plan(
		&project,
		.Duplicate,
		"case_a",
		"case_a_copy",
		"Case A Copy",
	); assert(duplicate.allowed && authoring_case_operation_execute(&project, &duplicate).ok && authoring_project_case_index(&project, "case_a_copy") >= 0)
	rename := authoring_case_operation_plan(
		&project,
		.Rename,
		"case_a_copy",
		"case_a_renamed",
		"Case A Renamed",
	); assert(rename.allowed && authoring_case_operation_execute(&project, &rename).ok && authoring_project_case_index(&project, "case_a_copy") == -1 && authoring_project_case_index(&project, "case_a_renamed") >= 0)
	assert(authoring_case_move_directory(&project, "case_b", "relocated/mystery_case").ok)
	moved := &project.cases[authoring_project_case_index(&project, "case_b")]; assert(moved.directory == "relocated/mystery_case" && moved.paths.story == "relocated/mystery_case/story.toml")
	moved_story, _ := authoring_resolve_path(
		&project,
		moved.paths.story,
	); assert(os.is_file(moved_story))
	assert(!authoring_case_move_directory(&project, "case_b", "../outside").ok)
	stable_id :=
		moved.id; assert(authoring_case_rename_title(&project, "case_b", "Renamed Mystery Case").ok && moved.id == stable_id && moved.title == "Renamed Mystery Case" && moved.paths.story == "relocated/mystery_case/story.toml")
	copy_root := "/private/tmp/chicago-authoring-lifecycle-workflows-copy"; if os.exists(copy_root) do assert(os.remove_all(copy_root) == nil); assert(authoring_project_save_as(&project, copy_root).ok && project.root_path == copy_root); for item in project.cases[:project.case_count] {path, path_ok := authoring_resolve_path(&project, item.paths.story); assert(path_ok && os.is_file(path))}
	deleted := authoring_case_operation_plan(
		&project,
		.Delete,
		"case_a_renamed",
		"",
		"",
	); assert(deleted.allowed && authoring_case_operation_execute(&project, &deleted).ok && authoring_project_case_index(&project, "case_a_renamed") == -1)
	project.campaign_path = "manifests/campaign.toml"; project.export_directory = "release/packages"; assert(authoring_project_save_manifest(&project).ok)
	reopened: Authoring_Project; assert(authoring_project_load_manifest(copy_root, &reopened).ok && authoring_project_case_index(&reopened, "case_b") >= 0 && reopened.cases[authoring_project_case_index(&reopened, "case_b")].directory == "relocated/mystery_case" && reopened.cases[authoring_project_case_index(&reopened, "case_b")].title == "Renamed Mystery Case" && reopened.campaign_path == "manifests/campaign.toml" && reopened.export_directory == "release/packages")
	project_asset_registry_destroy(&reopened.asset_registry)
}

run_project_asset_persistence_tests :: proc() {
	root := "/private/tmp/chicago-project-asset-persistence"
	assert(os.exists(root) || os.make_directory_all(root) == nil)
	project, ok := authoring_project_new("asset_roundtrip", "Asset Roundtrip", root); assert(ok)
	assert(authoring_project_add_case(&project, "case_one", "Case One"))
	assert(authoring_project_save_manifest(&project).ok)

	registry: Project_Asset_Registry
	defer project_asset_registry_destroy(&registry)
	thumbnail := Project_Asset_Record {
		id = "cover-art",
		kind = .Thumbnail,
		source_path = "/external/source/cover.png",
		sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		source_mode = .Link,
		embed_policy = .External,
		provenance = {
			source_uri = "https://example.test/art?q=\"cover\"",
			source_name = "Cover\nArt",
			creator = "Test Artist",
			attribution = "Art by Test Artist",
			license_id = "CC-BY-4.0",
			license_text = "Creative Commons Attribution",
			redistribution_permitted = true,
		},
		technical = {
			format = ".png",
			byte_size = 4096,
			image = {width = 640, height = 360, color_space = "sRGB", has_alpha = true},
		},
	}
	audio := Project_Asset_Record {
		id = "theme-audio",
		kind = .Audio,
		source_path = "/external/source/theme.ogg",
		sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
		source_mode = .Link,
		embed_policy = .External,
		provenance = {
			source_name = "Theme",
			creator = "Test Composer",
			license_id = "CC0-1.0",
			redistribution_permitted = true,
		},
		technical = {
			format = ".ogg",
			byte_size = 8192,
			audio = {duration_seconds = 12.5, channels = 2, sample_rate = 48000},
		},
	}
	assert(project_asset_registry_add(&registry, thumbnail).ok)
	assert(project_asset_registry_add(&registry, audio).ok)
	assert(
		project_asset_registry_register_usage(
			&registry,
			{"cover-art", "campaign", "asset_roundtrip", "thumbnail"},
		),
	)
	assert(
		project_asset_registry_register_dependency(
			&registry,
			{"cover-art", "theme-audio", "campaign presentation"},
		),
	)
	expected_revision := registry.revision
	assert(project_asset_registry_save_project(&project, &registry).ok)

	reopened: Authoring_Project
	loaded := authoring_project_load_manifest(root, &reopened)
	assert(loaded.ok && reopened.asset_registry_pending)
	defer project_asset_registry_destroy(&reopened.asset_registry)
	assert(
		reopened.id == project.id &&
		reopened.case_count == 1 &&
		reopened.asset_registry.revision == expected_revision,
	)
	assert(
		len(reopened.asset_registry.assets) == 2 &&
		len(reopened.asset_registry.usages) == 1 &&
		len(reopened.asset_registry.dependencies) == 1,
	)
	loaded_thumbnail :=
		reopened.asset_registry.assets[project_asset_index(&reopened.asset_registry, "cover-art")]
	assert(
		loaded_thumbnail.provenance.source_uri == thumbnail.provenance.source_uri &&
		loaded_thumbnail.provenance.source_name == thumbnail.provenance.source_name,
	)
	assert(
		loaded_thumbnail.technical.image.width == 640 &&
		loaded_thumbnail.technical.image.height == 360 &&
		loaded_thumbnail.technical.image.has_alpha,
	)
	loaded_audio :=
		reopened.asset_registry.assets[project_asset_index(&reopened.asset_registry, "theme-audio")]
	assert(
		loaded_audio.technical.audio.channels == 2 &&
		loaded_audio.technical.audio.sample_rate == 48000 &&
		loaded_audio.technical.audio.duration_seconds == 12.5,
	)
	assert(
		reopened.asset_registry.usages[0].field_path == "thumbnail" &&
		reopened.asset_registry.dependencies[0].depends_on_id == "theme-audio",
	)

	legacy_root := "/private/tmp/chicago-project-without-asset-registry"
	assert(os.exists(legacy_root) || os.make_directory_all(legacy_root) == nil)
	_ = os.remove(fmt.tprintf("%s/%s", legacy_root, PROJECT_ASSET_REGISTRY_RELATIVE))
	legacy, legacy_ok := authoring_project_new(
		"legacy_assets",
		"Legacy Assets",
		legacy_root,
	); assert(legacy_ok)
	assert(
		authoring_project_add_case(&legacy, "legacy_case", "Legacy Case") &&
		authoring_project_save_manifest(&legacy).ok,
	)
	legacy_loaded: Authoring_Project
	assert(
		authoring_project_load_manifest(legacy_root, &legacy_loaded).ok &&
		legacy_loaded.asset_registry_pending &&
		len(legacy_loaded.asset_registry.assets) == 0,
	)
	project_asset_registry_destroy(&legacy_loaded.asset_registry)
}

run_complete_authoring_regression_tests :: proc() {
	ensure_test_torn_story()
	story := story_project_clone(&test_story_project); defer story_project_destroy(&story)
	if len(story.entities) == 0 do append(&story.entities, Story_Entity{id = "regression_actor", kind = "person", display_name = "Regression Actor"})
	if len(story.roles) == 0 do append(&story.roles, Story_Role{id = "regression_role", display_name = "Regression Role"})
	if len(story.variables) == 0 do append(&story.variables, Story_Variable{id = "regression_variable", display_name = "Regression Variable", kind = .Boolean, default_value = story_value_boolean(false)})
	if len(story.propositions) == 0 do append(&story.propositions, Story_Proposition{id = "regression_proposition", text = "Regression proposition."})
	if len(story.facts) == 0 do append(&story.facts, Story_Fact{id = "regression_fact", display_name = "Regression Fact", proposition = story.propositions[0].id})
	if len(story.initial_knowledge) == 0 do append(&story.initial_knowledge, Story_Knowledge{actor_id = story.entities[0].id, proposition_id = story.propositions[0].id})
	if len(story.relationships) == 0 do append(&story.relationships, Story_Relationship{id = "regression_relationship", source_id = story.entities[0].id, target_id = story.entities[0].id, kind = "regression"})
	if len(story.events) == 0 do append(&story.events, Story_Event{id = "regression_event", subject_id = story.entities[0].id, action = "regression"})
	if len(story.objectives) == 0 do append(&story.objectives, Story_Objective{id = "regression_objective", display_name = "Regression Objective"})
	if len(story.conditions) == 0 do append(&story.conditions, Story_Condition{id = "regression_always", kind = .Always})
	if len(story.effects) == 0 do append(&story.effects, Story_Effect{id = "regression_emit", kind = .Emit_Event, event_id = "regression"})
	if len(story.endings) == 0 do append(&story.endings, Story_Ending{id = "regression_ending", title = "Regression Ending", condition_id = story.conditions[0].id})
	if len(story.storylet_groups) == 0 do append(&story.storylet_groups, Story_Storylet_Group{id = "regression_group"})
	if len(story.storylets) == 0 do append(&story.storylets, Story_Storylet{id = "regression_storylet", group = story.storylet_groups[0].id})
	if len(story.invariants) == 0 do append(&story.invariants, Story_Invariant{id = "regression_invariant", description = "Regression invariant", condition_id = story.conditions[0].id})
	assert(
		len(story.entities) > 0 &&
		len(story.roles) > 0 &&
		len(story.variables) > 0 &&
		len(story.facts) > 0 &&
		len(story.propositions) > 0 &&
		len(story.initial_knowledge) > 0 &&
		len(story.relationships) > 0 &&
		len(story.events) > 0 &&
		len(story.objectives) > 0 &&
		len(story.endings) > 0 &&
		len(story.storylet_groups) > 0 &&
		len(story.storylets) > 0 &&
		len(story.invariants) > 0 &&
		len(story.conditions) > 0 &&
		len(story.effects) > 0,
	)
	commands := [15]Story_Authoring_Command {
		{kind = .Update, record_kind = .Entity, entity = story.entities[0]},
		{kind = .Update, record_kind = .Role, role = story.roles[0]},
		{kind = .Update, record_kind = .Variable, variable = story.variables[0]},
		{kind = .Update, record_kind = .Fact, fact = story.facts[0]},
		{kind = .Update, record_kind = .Proposition, proposition = story.propositions[0]},
		{kind = .Update, record_kind = .Knowledge, knowledge = story.initial_knowledge[0]},
		{kind = .Update, record_kind = .Relationship, relationship = story.relationships[0]},
		{kind = .Update, record_kind = .Event, event = story.events[0]},
		{kind = .Update, record_kind = .Objective, objective = story.objectives[0]},
		{kind = .Update, record_kind = .Ending, ending = story.endings[0]},
		{kind = .Update, record_kind = .Storylet_Group, storylet_group = story.storylet_groups[0]},
		{kind = .Update, record_kind = .Storylet, storylet = story.storylets[0]},
		{kind = .Update, record_kind = .Invariant, invariant = story.invariants[0]},
		{kind = .Update, record_kind = .Condition, condition = story.conditions[0]},
		{kind = .Update, record_kind = .Effect, effect = story.effects[0]},
	}
	for &command in commands {result: Story_Authoring_Result
		assert(story_authoring_apply_raw(&story, &command, &result))}
	append(
		&story.conditions,
		Story_Condition{id = "regression_child_a", kind = .Always},
		Story_Condition{id = "regression_child_b", kind = .Always},
		Story_Condition{id = "regression_parent", kind = .All},
	)
	condition_commands := [4]Story_Authoring_Command {
		{
			kind = .Insert_Condition_Child,
			owner_id = "regression_parent",
			id = "regression_child_a",
		},
		{
			kind = .Insert_Condition_Child,
			owner_id = "regression_parent",
			id = "regression_child_b",
		},
		{kind = .Reorder_Condition_Child, owner_id = "regression_parent", from = 1},
		{kind = .Remove_Condition_Child, owner_id = "regression_parent", from = 1},
	}; condition_commands[1].to = 1
	for &command in condition_commands {result: Story_Authoring_Result
		assert(story_authoring_apply_raw(&story, &command, &result))}
	append(
		&story.effects,
		Story_Effect{id = "regression_effect_a", kind = .Emit_Event, event_id = "regression_a"},
		Story_Effect{id = "regression_effect_b", kind = .Emit_Event, event_id = "regression_b"},
	)
	owner :=
		story.nodes[0].id; effect_commands := [4]Story_Authoring_Command{{kind = .Insert_Effect_Reference, owner_id = owner, id = "regression_effect_a"}, {kind = .Insert_Effect_Reference, owner_id = owner, id = "regression_effect_b"}, {kind = .Reorder_Effect_Reference, owner_id = owner, from = 1}, {kind = .Remove_Effect_Reference, owner_id = owner, from = 1}}; effect_commands[1].to = 1
	for &command in effect_commands {result: Story_Authoring_Result
		assert(story_authoring_apply_raw(&story, &command, &result))}

	payload := mystery_payload(&story); assert(payload != nil)
	if len(payload.characters) == 0 do payload.characters = mystery_authoring_array_append(payload, payload.characters, Mystery_Character_Metadata{entity_id = story.entities[0].id})
	if len(payload.locations) == 0 do payload.locations = mystery_authoring_array_append(payload, payload.locations, Mystery_Location_Metadata{entity_id = "regression_location"})
	if len(payload.pois) == 0 do payload.pois = mystery_authoring_array_append(payload, payload.pois, Mystery_POI_Metadata{entity_id = "regression_poi", location_id = payload.locations[0].entity_id})
	if len(payload.events) == 0 do payload.events = mystery_authoring_array_append(payload, payload.events, Mystery_Event_Metadata{event_id = "regression_mystery_event", destination_id = payload.locations[0].entity_id})
	if len(payload.clues) == 0 do payload.clues = mystery_authoring_array_append(payload, payload.clues, Mystery_Clue{id = "regression_clue", source_id = payload.pois[0].entity_id, proposition_id = story.propositions[0].id})
	if len(payload.claims) == 0 do payload.claims = mystery_authoring_array_append(payload, payload.claims, Mystery_Claim{id = "regression_claim", speaker_id = payload.characters[0].entity_id, proposition_id = story.propositions[0].id})
	if len(payload.contradictions) == 0 do payload.contradictions = mystery_authoring_array_append(payload, payload.contradictions, Mystery_Contradiction{id = "regression_contradiction", claim_id = payload.claims[0].id, fact_id = story.facts[0].id})
	if len(payload.deductions) == 0 do payload.deductions = mystery_authoring_array_append(payload, payload.deductions, Mystery_Deduction{id = "regression_deduction", proposition_id = story.propositions[0].id})
	if len(payload.questions) == 0 do payload.questions = mystery_authoring_array_append(payload, payload.questions, Mystery_Question{id = "regression_question", prompt = "Regression question?"})
	if len(payload.demonstrations) == 0 do payload.demonstrations = mystery_authoring_array_append(payload, payload.demonstrations, Mystery_Demonstration{id = "regression_demonstration", question_id = payload.questions[0].id})
	if len(payload.dialogue) == 0 do payload.dialogue = mystery_authoring_array_append(payload, payload.dialogue, Mystery_Dialogue_Metadata{node_id = "regression_dialogue", character_id = payload.characters[0].entity_id})
	if len(payload.endings) == 0 do payload.endings = mystery_authoring_array_append(payload, payload.endings, Mystery_Ending_Metadata{ending_id = "regression_mystery_ending"})
	if len(payload.city_labels) == 0 do payload.city_labels = mystery_authoring_array_append(payload, payload.city_labels, Mystery_City_Label{id = "regression_city_label", display_name = "Regression City Label"})
	if len(payload.tutorial_lessons) == 0 do payload.tutorial_lessons = mystery_authoring_array_append(payload, payload.tutorial_lessons, Mystery_Tutorial_Lesson{id = "regression_tutorial", capability = "regression", prompt = "Regression tutorial"})
	mystery_command := Mystery_Authoring_Command {
		kind        = .Update,
		record_kind = .Setup,
		setup       = {
			payload.action_budget,
			payload.seed,
			payload.tutorial_id,
			payload.city_start,
			payload.city_destination,
			payload.reveal_location,
		},
	}
	for kind in Mystery_Authoring_Record_Kind {
		mystery_command = {
			kind        = .Update,
			record_kind = kind,
		}
		switch kind {case .Setup:
			mystery_command.setup = {
				payload.action_budget,
				payload.seed,
				payload.tutorial_id,
				payload.city_start,
				payload.city_destination,
				payload.reveal_location,
			}; case .Character:
			mystery_command.character = payload.characters[0]; case .Location:
			mystery_command.location = payload.locations[0]; case .POI:
			mystery_command.poi = payload.pois[0]; case .Event:
			mystery_command.event = payload.events[0]; case .Clue:
			mystery_command.clue = payload.clues[0]; case .Claim:
			mystery_command.claim = payload.claims[0]; case .Contradiction:
			mystery_command.contradiction = payload.contradictions[0]; case .Deduction:
			mystery_command.deduction = payload.deductions[0]; case .Question:
			mystery_command.question = payload.questions[0]; case .Demonstration:
			mystery_command.demonstration = payload.demonstrations[0]; case .Dialogue:
			mystery_command.dialogue = payload.dialogue[0]; case .Ending:
			mystery_command.ending = payload.endings[0]; case .City_Label:
			mystery_command.city_label = payload.city_labels[0]; case .Tutorial_Lesson:
			mystery_command.tutorial_lesson = payload.tutorial_lessons[0]; case .Solution:
			mystery_command.solution = payload.solution}
		result: Mystery_Authoring_Result; assert(mystery_authoring_apply_raw(&story, &mystery_command, &result))
	}

	graph_import_story(
		&story,
	); assert(graph_document.node_count == len(story.nodes) && graph_document.condition_count == len(story.conditions) && graph_document.effect_count == len(story.effects)); graph_configure_minimap_stress_board(); assert(graph_document.node_count == 256); graph_import_story(&test_story_project)
	qualified, qualified_ok := story_spatial_id_parse(
		"house:foyer",
	); assert(qualified_ok && qualified.space_id == "house" && qualified.target_id == "foyer")
	plan := authoring_recheck_plan(
		.Story_Core,
	); assert(plan.count >= 4); diagnostic := authoring_diagnostic_init(.Level, "level", "door", "destination", .Error, "broken transition"); navigation := authoring_diagnostic_navigation(diagnostic); assert(navigation.workspace == "build" && navigation.entity_id == "door")
}

run_campaign_authoring_mutation_tests :: proc() {
	// Programmatic creation goes through the same typed workspace transaction as
	// interactive authoring and is a single dirty/undo/redo operation.
	saved_action_workspace := campaign_workspace
	campaign_workspace = {
		open  = true,
		dirty = true,
	}; campaign_workspace_request_close(

	); assert(campaign_workspace.open && campaign_workspace.exit_confirm); campaign_workspace.exit_confirm = false; campaign_workspace.dirty = false; campaign_workspace_request_close(); assert(!campaign_workspace.open)
	campaign_workspace = {
		draft = Campaign_Definition {
			version = "MysteryCampaign v2",
			id = "action_campaign",
			title = "Action Campaign",
			creator = "Test",
			description = "Typed action test",
			content_version = "1.0.0",
		},
	}
	actions := [4]Campaign_Workspace_Action {
		{
			kind = .Add_Variable,
			variable = {id = "solved", display_name = "Solved", kind = .Boolean},
		},
		{
			kind = .Add_Condition,
			condition = {kind = .Boolean_Equals, variable_id = "solved", boolean_value = false},
		},
		{
			kind = .Add_Effect,
			effect = {kind = .Set_Boolean, variable_id = "solved", boolean_value = true},
		},
		{
			kind = .Add_Case,
			case_value = {
				id = "action_case",
				title = "Action Case",
				story_path = "cases/action/story.toml",
				level_path = "cases/action/level.toml",
				case_content_version = "1.0.0",
				condition_root = 0,
				required = true,
				unavailable_presentation = .Requirements,
				replay_mode = .Disabled,
				invalid_result_policy = .Preserve,
			},
		},
	}
	action_result := campaign_workspace_apply_actions(
		actions[:],
	); if !action_result.ok do fmt.println("CAMPAIGN ACTION FAILURE · ", action_result.message); assert(action_result.ok && campaign_workspace.dirty && len(campaign_workspace.draft.cases) == 1 && campaign_workspace.history.undo_count == 1); assert(campaign_workspace_undo() && len(campaign_workspace.draft.cases) == 0); assert(campaign_workspace_redo() && len(campaign_workspace.draft.cases) == 1)
	campaign_history_clear_stack(
		&campaign_workspace.history.undo,
		&campaign_workspace.history.undo_count,
	); campaign_history_clear_stack(&campaign_workspace.history.redo, &campaign_workspace.history.redo_count); campaign_destroy(&campaign_workspace.history.current); campaign_destroy(&campaign_workspace.draft); campaign_workspace = saved_action_workspace
	saved_workspace := campaign_workspace
	campaign_workspace = {
		selected_case      = 0,
		selected_variable  = 0,
		selected_condition = campaign_document.cases[0].condition_root,
		selected_outcome   = int(Outcome.Airtight),
		draft              = campaign_clone(&campaign_document),
	}
	variable_count := len(
		campaign_workspace.draft.variables,
	); assert(campaign_workspace_add_variable() && len(campaign_workspace.draft.variables) == variable_count + 1)
	condition_count := len(
		campaign_workspace.draft.conditions,
	); assert(campaign_workspace_add_condition(.All) && len(campaign_workspace.draft.conditions) == condition_count + 2)
	effect_count := len(
		campaign_workspace.draft.effects,
	); assert(campaign_workspace_add_effect() && len(campaign_workspace.draft.effects) == effect_count + 1 && campaign_workspace.draft.effects[campaign_workspace.selected_effect].variable_id == campaign_workspace.draft.variables[0].id)
	campaign_workspace = saved_workspace

	// Every condition and effect offered by the Campaign workspace is reachable
	// through its production add/edit controls, including the integer operation
	// toggle which distinguishes SET from ADD.
	control_fixture := Campaign_Definition {
		version         = "MysteryCampaign v2",
		id              = "workspace_controls",
		title           = "Workspace Controls",
		content_version = "1.0.0",
	}
	control_enum := Campaign_Variable {
		id               = "route",
		display_name     = "Route",
		kind             = .Enumeration,
		default_enum     = "north",
		enum_value_count = 2,
	}; control_enum.enum_values[0] = "north"; control_enum.enum_values[1] = "south"
	append(
		&control_fixture.variables,
		Campaign_Variable{id = "flag", display_name = "Flag", kind = .Boolean},
		Campaign_Variable{id = "score", display_name = "Score", kind = .Integer},
		control_enum,
	)
	append(&control_fixture.conditions, Campaign_Condition{kind = .Always})
	append(
		&control_fixture.cases,
		Campaign_Case {
			id = "control_a",
			title = "Control A",
			story_path = "cases/control_a/story.toml",
			case_content_version = "1.0.0",
			condition_root = 0,
			required = true,
		},
		Campaign_Case {
			id = "control_b",
			title = "Control B",
			story_path = "cases/control_b/story.toml",
			case_content_version = "1.0.0",
			condition_root = -1,
			optional = true,
		},
	)
	for kind in Campaign_Condition_Kind {
		campaign_workspace = {
			selected_case      = 0,
			selected_condition = 0,
			draft              = campaign_clone(&control_fixture),
		}; campaign_workspace_history_initialize()
		assert(
			campaign_workspace_add_condition(kind) &&
			campaign_workspace.draft.conditions[campaign_workspace.selected_condition].kind ==
				kind &&
			campaign_workspace.history.undo_count == 1,
		)
		assert(
			campaign_workspace_undo() &&
			campaign_workspace.draft.conditions[0].kind == .Always &&
			campaign_workspace_redo() &&
			campaign_workspace.draft.conditions[campaign_workspace.selected_condition].kind ==
				kind,
		)
		campaign_destroy(
			&campaign_workspace.draft,
		); campaign_history_clear_stack(&campaign_workspace.history.undo, &campaign_workspace.history.undo_count); campaign_history_clear_stack(&campaign_workspace.history.redo, &campaign_workspace.history.redo_count); campaign_destroy(&campaign_workspace.history.current)
	}
	for kind in Campaign_Effect_Kind {
		fixture := campaign_clone(
			&control_fixture,
		); variable_index := kind == .Set_Boolean ? 0 : kind == .Set_Enum ? 2 : 1; fixture.variables[0], fixture.variables[variable_index] = fixture.variables[variable_index], fixture.variables[0]
		campaign_workspace = {
			selected_case    = 0,
			selected_effect  = -1,
			selected_outcome = int(Outcome.Airtight),
			draft            = fixture,
		}; campaign_workspace_history_initialize(); assert(campaign_workspace_add_effect())
		effect := &campaign_workspace.draft.effects[campaign_workspace.selected_effect]
		if kind ==
		   .Add_Integer {assert(effect.kind == .Set_Integer); effect.kind = .Add_Integer; campaign_workspace_mark_changed("EFFECT OPERATION UPDATED")} else do assert(effect.kind == kind)
		assert(
			effect.kind == kind &&
			campaign_workspace.history.undo_count >= 1 &&
			campaign_workspace_undo() &&
			campaign_workspace_redo() &&
			campaign_workspace.draft.effects[campaign_workspace.selected_effect].kind == kind,
		)
		campaign_destroy(
			&campaign_workspace.draft,
		); campaign_history_clear_stack(&campaign_workspace.history.undo, &campaign_workspace.history.undo_count); campaign_history_clear_stack(&campaign_workspace.history.redo, &campaign_workspace.history.redo_count); campaign_destroy(&campaign_workspace.history.current)
	}
	campaign_destroy(&control_fixture)

	// Acceptance sequence for the Campaign manifest controls: New, Open,
	// Duplicate, Move and Delete all survive a persisted reopen.
	saved_campaign_document := campaign_clone(
		&campaign_document,
	); saved_campaign_manifest_path := campaign_manifest_path
	lifecycle_root := "/private/tmp/chicago-campaign-manifest-acceptance"; if os.exists(lifecycle_root) do assert(os.remove_all(lifecycle_root) == nil); assert(os.make_directory_all(lifecycle_root) == nil)
	new_path := fmt.tprintf(
		"%s/new.toml",
		lifecycle_root,
	); duplicate_path := fmt.tprintf("%s/duplicate.toml", lifecycle_root); renamed_path := fmt.tprintf("%s/renamed.toml", lifecycle_root); moved_path := fmt.tprintf("%s/nested/moved.toml", lifecycle_root)
	assert(
		campaign_workspace_new_manifest(new_path).ok &&
		os.is_file(new_path) &&
		len(campaign_workspace.draft.cases) == 1,
	)
	assert(
		campaign_workspace_open_manifest(new_path).ok &&
		campaign_workspace.draft.id == "new_campaign",
	)
	assert(
		campaign_workspace_save_as(duplicate_path, true).ok &&
		campaign_workspace.draft.id == "new_campaign_copy" &&
		os.is_file(duplicate_path),
	)
	assert(
		campaign_workspace_add_case(),
	); added_id := campaign_workspace.draft.cases[campaign_workspace.selected_case].id; assert(campaign_workspace_move_case(-1) && campaign_workspace.draft.cases[0].id == added_id)
	campaign_workspace.selected_case = 1; assert(campaign_workspace_remove_case() && len(campaign_workspace.draft.cases) == 1 && campaign_workspace.draft.cases[0].id == added_id)
	assert(
		campaign_workspace_save_as(duplicate_path).ok,
	); accepted: Campaign_Definition; assert(load_campaign_manifest(duplicate_path, &accepted).ok && accepted.id == "new_campaign_copy" && len(accepted.cases) == 1 && accepted.cases[0].id == added_id); campaign_destroy(&accepted)
	assert(
		!campaign_workspace_rename_manifest("../unsafe.toml").ok &&
		!campaign_workspace_rename_manifest("wrong.extension").ok,
	)
	assert(
		campaign_workspace_rename_manifest("renamed.toml").ok &&
		!os.exists(duplicate_path) &&
		os.is_file(renamed_path),
	); reopened_after_rename: Campaign_Definition; assert(load_campaign_manifest(renamed_path, &reopened_after_rename).ok && reopened_after_rename.id == "new_campaign_copy"); campaign_destroy(&reopened_after_rename)
	assert(
		campaign_workspace_move_manifest(moved_path).ok &&
		!os.exists(renamed_path) &&
		os.is_file(moved_path),
	); assert(!campaign_workspace_move_manifest(new_path).ok && campaign_manifest_path == moved_path)
	assert(
		campaign_workspace_delete_manifest().ok &&
		!os.exists(moved_path) &&
		campaign_manifest_path == "" &&
		!campaign_workspace.open,
	); trash_path := fmt.tprintf("%s/nested/.trash/new_campaign_copy-1.0.0.toml", lifecycle_root); assert(os.is_file(trash_path)); recovered: Campaign_Definition; assert(load_campaign_manifest(trash_path, &recovered).ok && recovered.id == "new_campaign_copy" && len(recovered.cases) == 1); campaign_destroy(&recovered)
	campaign_destroy(
		&campaign_workspace.draft,
	); campaign_destroy(&campaign_document); campaign_document = saved_campaign_document; campaign_manifest_path = saved_campaign_manifest_path; campaign_workspace = saved_workspace

	// Exercise every serialized field and enum variant through the actual TOML
	// writer/parser instead of treating a small production fixture as full-schema
	// coverage.
	full := Campaign_Definition {
		version         = "MysteryCampaign v2",
		id              = "full_schema",
		title           = "Full Schema",
		creator         = "Creator \"Q\"",
		description     = "Line one\nLine two",
		content_version = "2.3.4",
		thumbnail       = "assets/ui/campaign.png",
	}
	append(
		&full.variables,
		Campaign_Variable {
			id = "flag",
			display_name = "Flag",
			description = "Boolean variable",
			kind = .Boolean,
			default_boolean = true,
		},
		Campaign_Variable {
			id = "score",
			display_name = "Score",
			description = "Integer variable",
			kind = .Integer,
			default_integer = -7,
		},
	)
	branch := Campaign_Variable {
		id               = "branch",
		display_name     = "Branch",
		description      = "Enum variable",
		kind             = .Enumeration,
		default_enum     = "north",
		enum_value_count = 2,
	}; branch.enum_values[0] = "north"; branch.enum_values[1] = "south"; append(&full.variables, branch)
	append(
		&full.conditions,
		Campaign_Condition{kind = .Always},
		Campaign_Condition{kind = .Never},
		Campaign_Condition{kind = .All, first_child = 0, child_count = 2},
		Campaign_Condition{kind = .Any, first_child = 0, child_count = 2},
		Campaign_Condition{kind = .Not, first_child = 1, child_count = 1},
		Campaign_Condition{kind = .Boolean_Equals, variable_id = "flag", boolean_value = true},
		Campaign_Condition {
			kind = .Integer_Compare,
			variable_id = "score",
			integer_value = -3,
			integer_comparison = .Greater_Equal,
		},
		Campaign_Condition{kind = .Enum_Equals, variable_id = "branch", enum_value = "south"},
		Campaign_Condition{kind = .Case_Started, case_id = "case_0"},
		Campaign_Condition{kind = .Case_Completed, case_id = "case_0"},
		Campaign_Condition{kind = .Case_Outcome, case_id = "case_0", outcome = .Wrong_Accusation},
	)
	append(
		&full.effects,
		Campaign_Effect{kind = .Set_Boolean, variable_id = "flag", boolean_value = false},
		Campaign_Effect{kind = .Set_Integer, variable_id = "score", integer_value = 4},
		Campaign_Effect{kind = .Add_Integer, variable_id = "score", integer_value = -2},
		Campaign_Effect{kind = .Set_Enum, variable_id = "branch", enum_value = "south"},
	)
	for condition_index in 0 ..< len(full.conditions) {item := Campaign_Case {
			id                       = fmt.tprintf("case_%d", condition_index),
			title                    = fmt.tprintf("Case %d", condition_index),
			story_path               = fmt.tprintf("cases/%d/story.toml", condition_index),
			level_path               = fmt.tprintf("cases/%d/level.toml", condition_index),
			case_content_version     = fmt.tprintf("1.%d.0", condition_index),
			locked_message           = fmt.tprintf("Locked %d", condition_index),
			condition_root           = condition_index,
			required                 = condition_index % 2 == 0,
			optional                 = condition_index % 2 != 0,
			unavailable_presentation = Campaign_Unavailable_Presentation(
				condition_index % len(Campaign_Unavailable_Presentation),
			),
			replay_mode              = Campaign_Replay_Mode(
				condition_index % len(Campaign_Replay_Mode),
			),
			invalid_result_policy    = Campaign_Invalid_Result_Policy(
				condition_index % len(Campaign_Invalid_Result_Policy),
			),
		}; if condition_index == 0 {item.outcome_effect_count = 2; item.outcome_effects[0] = {
				outcome      = .Airtight,
				first_effect = 0,
				effect_count = 2,
			}; item.outcome_effects[1] = {
				outcome      = .Wrong_Accusation,
				first_effect = 2,
				effect_count = 2,
			}}; append(&full.cases, item)}
	assert(
		campaign_validate(&full).ok,
	); canonical := campaign_serialize(&full); full_path := "/private/tmp/chicago-campaign-full-schema.toml"; assert(save_campaign_manifest(full_path, &full).ok); roundtrip: Campaign_Definition; assert(load_campaign_manifest(full_path, &roundtrip).ok && campaign_serialize(&roundtrip) == canonical)

	// Removing a nested branch compacts descendants and unreachable records while
	// repairing every stored root/child index.
	nested := Campaign_Definition {
		version         = "MysteryCampaign v2",
		id              = "nested",
		title           = "Nested",
		content_version = "1.0.0",
	}; append(
		&nested.conditions,
		Campaign_Condition{kind = .All, first_child = 1, child_count = 2},
		Campaign_Condition{kind = .Always},
		Campaign_Condition{kind = .Not, first_child = 3, child_count = 1},
		Campaign_Condition{kind = .Never},
		Campaign_Condition{kind = .Always},
	); append(&nested.cases, Campaign_Case{id = "nested_case", title = "Nested Case", story_path = "nested/story.toml", case_content_version = "1.0.0", condition_root = 0, required = true})
	assert(
		campaign_condition_remove_subtree(&nested, 2).ok &&
		len(nested.conditions) == 3 &&
		nested.conditions[0].child_count == 1 &&
		nested.cases[0].condition_root == 0,
	); assert(campaign_condition_compact(&nested).ok && len(nested.conditions) == 2 && nested.conditions[0].first_child == 1 && campaign_validate(&nested).ok)
	nested_workspace := campaign_workspace; campaign_workspace = {
		selected_case      = 0,
		selected_condition = 0,
		draft              = campaign_clone(&nested),
	}; assert(
		campaign_workspace_insert_condition_child() &&
		campaign_workspace.draft.conditions[0].child_count == 2 &&
		campaign_workspace.selected_condition == 2 &&
		campaign_validate(&campaign_workspace.draft).ok,
	); campaign_workspace = nested_workspace
	// Production authoring addresses arbitrary nested trees by stable case ID and
	// logical child path; callers never observe mutable serialization indices.
	path_workspace := campaign_workspace; campaign_workspace = {
		selected_case      = 0,
		selected_condition = 0,
		draft              = campaign_clone(&nested),
	}; child_path := Campaign_Condition_Path {
		depth = 1,
	}; child_path.children[0] = 0; assert(campaign_workspace_set_condition_at_path("nested_case", child_path, .Any)); nested_parent := Campaign_Condition_Path {
		depth = 1,
	}; nested_parent.children[0] = 0; assert(campaign_workspace_insert_condition_child_at_path("nested_case", nested_parent)); third_child := Campaign_Condition_Path {
		depth = 2,
	}; third_child.children[0] = 0; third_child.children[1] = 2; third_index, third_ok := campaign_condition_path_resolve(&campaign_workspace.draft, "nested_case", third_child); assert(third_ok && campaign_workspace.draft.conditions[third_index].kind == .Always); assert(campaign_workspace_set_condition_at_path("nested_case", third_child, .Never)); resolved, _ := campaign_condition_path_resolve(&campaign_workspace.draft, "nested_case", third_child); assert(campaign_workspace.draft.conditions[resolved].kind == .Never && campaign_validate(&campaign_workspace.draft).ok); campaign_destroy(&campaign_workspace.draft); campaign_workspace = path_workspace

	// Effect ranges remain stable for insertion, local reorder, and removals on
	// either side of another outcome mapping.
	ranges := campaign_clone(
		&full,
	); assert(campaign_effect_reorder(&ranges, 0, 1).ok && ranges.effects[0].kind == .Set_Integer); assert(!campaign_effect_reorder(&ranges, 1, 2).ok); assert(campaign_effect_remove(&ranges, 0)); first_a, count_a := campaign_effect_range(ranges.cases[0], .Airtight); first_w, count_w := campaign_effect_range(ranges.cases[0], .Wrong_Accusation); assert(first_a == 0 && count_a == 1 && first_w == 1 && count_w == 2); assert(campaign_effect_remove(&ranges, 1)); first_w, count_w = campaign_effect_range(ranges.cases[0], .Wrong_Accusation); assert(first_w == 1 && count_w == 1)
	mapping_workspace := campaign_workspace; campaign_workspace = {
		selected_case    = 0,
		selected_outcome = int(Outcome.Wrong_Accusation),
		draft            = campaign_clone(&full),
	}; assert(
		campaign_workspace_effect_mapping_index() == 1 &&
		campaign_workspace_move_effect_mapping(-1) &&
		campaign_workspace.draft.cases[0].outcome_effects[0].outcome == .Wrong_Accusation,
	); assert(campaign_workspace_remove_effect_mapping() && campaign_workspace.draft.cases[0].outcome_effect_count == 1 && len(campaign_workspace.draft.effects) == 2); campaign_workspace = mapping_workspace

	// Replay modes and invalidation execute with production semantics. Replacing
	// an upstream outcome removes a now-locked dependent result and rebuilds its
	// effects; effectless replay leaves the original record untouched.
	replay := Campaign_Definition {
		version         = "MysteryCampaign v2",
		id              = "replay",
		title           = "Replay",
		content_version = "1.0.0",
	}; append(
		&replay.variables,
		Campaign_Variable{id = "gate", display_name = "Gate", kind = .Boolean},
	); append(&replay.conditions, Campaign_Condition{kind = .Always}, Campaign_Condition{kind = .Boolean_Equals, variable_id = "gate", boolean_value = true}); append(&replay.effects, Campaign_Effect{kind = .Set_Boolean, variable_id = "gate", boolean_value = true}, Campaign_Effect{kind = .Set_Boolean, variable_id = "gate", boolean_value = false}); first_case := Campaign_Case {
		id                   = "first",
		title                = "First",
		story_path           = "first/story.toml",
		case_content_version = "1.0.0",
		condition_root       = 0,
		required             = true,
		replay_mode          = .Replace_Outcome,
	}; first_case.outcome_effect_count = 2; first_case.outcome_effects[0] = {
		outcome      = .Airtight,
		first_effect = 0,
		effect_count = 1,
	}; first_case.outcome_effects[1] = {
		outcome      = .Unresolved,
		first_effect = 1,
		effect_count = 1,
	}; append(
		&replay.cases,
		first_case,
		Campaign_Case {
			id = "dependent",
			title = "Dependent",
			story_path = "dependent/story.toml",
			case_content_version = "1.0.0",
			condition_root = 1,
			optional = true,
			replay_mode = .Effectless,
			invalid_result_policy = .Clear,
		},
	); assert(campaign_validate(&replay).ok)
	progress := Campaign_Playthrough {
		campaign_id              = replay.id,
		campaign_content_version = replay.content_version,
		next_completion_sequence = 1,
		active_case              = -1,
	}; campaign_reset_values(
		&replay,
		&progress,
	); assert(campaign_apply_result(&replay, &progress, Campaign_Case_Result{case_id = "first", outcome = .Airtight}).ok && campaign_apply_result(&replay, &progress, Campaign_Case_Result{case_id = "dependent", outcome = .Airtight}).ok); dependent_before := progress.results[1]; assert(campaign_apply_result(&replay, &progress, Campaign_Case_Result{case_id = "dependent", outcome = .Wrong_Accusation}).ok && progress.results[1] == dependent_before); assert(campaign_apply_result(&replay, &progress, Campaign_Case_Result{case_id = "first", outcome = .Unresolved}).ok && !progress.results[1].present && !progress.values[0].boolean_value && progress.completion_count == 1)
	cycle := Campaign_Definition {
		version         = "MysteryCampaign v2",
		id              = "cycle",
		title           = "Cycle",
		content_version = "1.0.0",
	}; append(
		&cycle.conditions,
		Campaign_Condition{kind = .Case_Completed, case_id = "b"},
		Campaign_Condition{kind = .Case_Completed, case_id = "a"},
	); append(&cycle.cases, Campaign_Case{id = "a", title = "A", story_path = "a/story.toml", case_content_version = "1", condition_root = 0, required = true}, Campaign_Case{id = "b", title = "B", story_path = "b/story.toml", case_content_version = "1", condition_root = 1, required = true}); cycle_validation := campaign_validate(&cycle); assert(!cycle_validation.ok && strings.contains(cycle_validation.message, "initially available"))
	project := Authoring_Project {
		case_count = 2,
	}; project.cases[0] = {
		id = "other",
		paths = {story = "cases/other/story.toml", level = "cases/other/level.toml"},
	}; project.cases[1] = {
		id = "source",
		paths = {story = "cases/source/story.toml", level = "cases/source/level.toml"},
	}; assert(
		campaign_workspace_case_source_index(&project, Campaign_Case{id = "source"}) == 1,
	); assert(campaign_workspace_case_source_index(&project, Campaign_Case{story_path = "cases/other/story.toml"}) == 0); assert(campaign_workspace_case_source_index(&project, Campaign_Case{id = "missing", story_path = "missing.toml"}) < 0)

	// Campaign edits use snapshot history even though individual controls mutate
	// the draft directly; undo/redo restores the whole manifest atomically.
	history_workspace := campaign_workspace; campaign_workspace = {
		selected_case     = 0,
		selected_variable = 0,
		draft             = campaign_clone(&replay),
	}; campaign_workspace_history_initialize(

	); before_title := campaign_workspace.draft.title; campaign_workspace.draft.title = "Edited Replay"; campaign_workspace_mark_changed("TITLE UPDATED"); assert(campaign_workspace.history.undo_count == 1 && campaign_workspace_undo() && campaign_workspace.draft.title == before_title && campaign_workspace_redo() && campaign_workspace.draft.title == "Edited Replay")
	reset_doc := Campaign_Definition {
		version         = "MysteryCampaign v2",
		id              = "reset",
		title           = "Reset",
		content_version = "1",
	}; append(
		&reset_doc.conditions,
		Campaign_Condition{kind = .All, first_child = 1, child_count = 2},
		Campaign_Condition{kind = .Always},
		Campaign_Condition{kind = .Not, first_child = 3, child_count = 1},
		Campaign_Condition{kind = .Never},
	); append(&reset_doc.cases, Campaign_Case{id = "reset_case", title = "Reset", story_path = "reset/story.toml", case_content_version = "1", condition_root = 0, required = true}); campaign_destroy(&campaign_workspace.draft); campaign_workspace = {
		selected_case      = 0,
		selected_condition = 0,
		draft              = campaign_clone(&reset_doc),
	}; campaign_workspace_history_initialize(

	); assert(campaign_workspace_reset_condition() && len(campaign_workspace.draft.conditions) == 1 && campaign_workspace.draft.conditions[0].kind == .Always); assert(campaign_workspace_undo() && len(campaign_workspace.draft.conditions) == 4)
	campaign_destroy(&campaign_workspace.draft); campaign_workspace = {
		selected_case = 0,
		selected_variable = 0,
		simulated = {
			campaign_id = replay.id,
			campaign_content_version = replay.content_version,
			next_completion_sequence = 1,
			active_case = -1,
		},
		draft = campaign_clone(&replay),
	}; campaign_reset_values(
		&campaign_workspace.draft,
		&campaign_workspace.simulated,
	); assert(campaign_workspace_simulation_change_variable(0, 1).ok && strings.contains(campaign_workspace.simulation_trace, "gate")); assert(campaign_workspace_simulation_start(0).ok && strings.contains(campaign_workspace.simulation_trace, "STARTED")); assert(campaign_workspace_simulation_complete(0).ok && strings.contains(campaign_workspace.simulation_trace, "COMPLETED")); assert(campaign_workspace_simulation_clear(0).ok && strings.contains(campaign_workspace.simulation_trace, "CLEARED")); campaign_workspace.diagnostics = {false, "campaign condition is broken"}; assert(campaign_workspace_navigate_validation() && campaign_workspace.tab == .Conditions); campaign_workspace.tab = .Diagnostics; assert(campaign_workspace_navigate_dependency(1) && campaign_workspace.tab == .Conditions && campaign_workspace.selected_case == 1)
	source_root := "/private/tmp/chicago-campaign-source-bootstrap"; if os.exists(source_root) do assert(os.remove_all(source_root) == nil); assert(os.make_directory_all(source_root) == nil); source_campaign := fmt.tprintf("%s/campaign.toml", source_root); assert(save_campaign_manifest(source_campaign, &replay).ok); saved_active_project, saved_active_ready, saved_read_only, saved_manifest := active_authoring_project, active_authoring_ready, active_authoring_read_only, campaign_manifest_path; active_authoring_ready = false; campaign_manifest_path = source_campaign; campaign_workspace.draft = campaign_clone(&replay); assert(campaign_workspace_ensure_source_project().ok && active_authoring_ready && active_authoring_project.campaign_path == "campaign.toml" && active_authoring_project.export_directory == "exports" && os.is_file(fmt.tprintf("%s/%s", source_root, AUTHORING_PROJECT_MANIFEST))); active_authoring_project = saved_active_project; active_authoring_ready = saved_active_ready; active_authoring_read_only = saved_read_only; campaign_manifest_path = saved_manifest
	campaign_workspace = history_workspace
}

run_unified_validation_playtest_tests :: proc() {
	saved_category :=
		authoring_workspace.selected_category; authoring_workspace.selected_category = int(Authoring_Validation_Profile.Player_Safe); assert(authoring_workspace_validation_profile() == .Player_Safe); authoring_workspace.selected_category = saved_category
	filter := authoring_diagnostic_filter_all(

	); snapshot := authoring_validation_snapshot_init(.Playable, 1); defer authoring_validation_snapshot_destroy(&snapshot)
	story_issue := authoring_diagnostic_init(
		.Story_Core,
		"story",
		"actor_alpha",
		"display_name",
		.Warning,
		"missing display name",
	); level_issue := authoring_diagnostic_init(Authoring_Validation_Domain.Level, "level", "door_alpha", "destination", .Error, "broken destination"); incoming := [2]Authoring_Diagnostic{story_issue, level_issue}; authoring_validation_merge(&snapshot, incoming[:]); filter.minimum_severity = .Error; filter.search = "destination"; indices := authoring_validation_filtered_indices(&snapshot, &filter); assert(len(indices) == 1 && snapshot.diagnostics[indices[0]].domain == Authoring_Validation_Domain.Level); delete(indices); filter.domain_enabled[Authoring_Validation_Domain.Level] = false; indices = authoring_validation_filtered_indices(&snapshot, &filter); assert(len(indices) == 0); delete(indices)
	for domain in Authoring_Validation_Domain do assert(authoring_validation_touch_domain(&snapshot, domain, 1) && authoring_validation_mark_domain_valid(&snapshot, domain, 1)); plan := authoring_apply_invalidation(&snapshot, .Assets, 2); assert(plan.count == 3 && !authoring_validation_domain_fresh(&snapshot, .Assets) && !authoring_validation_domain_fresh(&snapshot, .Packaging) && !authoring_validation_domain_fresh(&snapshot, .Compatibility) && authoring_validation_domain_fresh(&snapshot, .Story_Core))

	scenario: Scenario_Context; assert(scenario_context_init("assets/stories/mysteries/the_torn_appointment.story.toml", "assets/levels/vale_house.toml", &scenario).ok); defer scenario_context_destroy(&scenario); project := &scenario.compiled.runtime; payload := mystery_payload(project); assert(payload != nil)
	setup := Authoring_Creator_State_Setup {
		action_budget = 3,
		time_minutes  = 45,
	}; defer authoring_creator_setup_destroy(&setup)
	if len(project.variables) > 0 do append(&setup.variables, Authoring_Creator_Variable{project.variables[0].id, project.variables[0].default_value})
	if len(payload.clues) > 0 do append(&setup.knowledge, Authoring_Creator_Knowledge{.Clue, payload.clues[0].id, true})
	if len(payload.claims) > 0 do append(&setup.knowledge, Authoring_Creator_Knowledge{.Claim, payload.claims[0].id, true})
	if len(payload.dialogue) > 0 && payload.dialogue[0].interaction != "" do append(&setup.knowledge, Authoring_Creator_Knowledge{.Topic, payload.dialogue[0].interaction, true})
	if len(project.objectives) > 0 do append(&setup.objectives, Authoring_Creator_Objective{project.objectives[0].id, .Completed, 2})
	if len(project.events) > 0 do append(&setup.events, project.events[0].id)
	if len(payload.deductions) > 0 do append(&setup.mystery_progress, Authoring_Creator_Mystery_Progress{.Deduction, payload.deductions[0].id, 1})
	if len(payload.questions) > 0 do append(&setup.mystery_progress, Authoring_Creator_Mystery_Progress{.Question, payload.questions[0].id, 2})
	playthrough :=
		campaign_playthrough; if len(campaign_document.variables) > 0 {variable := campaign_document.variables[0]; value := Campaign_Value {
			kind          = variable.kind,
			boolean_value = variable.default_boolean,
			integer_value = variable.default_integer,
			enum_value    = variable.default_enum,
		}; append(
			&setup.campaign_values,
			Authoring_Creator_Campaign_Value{variable.id, value},
		)}; if len(campaign_document.cases) > 0 do append(&setup.started_cases, campaign_document.cases[0].id)
	applied := authoring_apply_creator_setup(
		&setup,
		&scenario,
		&campaign_document,
		&playthrough,
	); assert(applied.ok); mystery := scenario_mystery(&scenario); assert(mystery.action_budget_remaining == 3); if len(setup.objectives) > 0 {index := story_state_objective_index(&scenario.runtime.state, setup.objectives[0].id); assert(index >= 0 && scenario.runtime.state.objectives[index].status == .Completed && scenario.runtime.state.objectives[index].stage == 2)}; if len(setup.events) > 0 do assert(scenario.runtime.state.emitted_events[len(scenario.runtime.state.emitted_events) - 1] == setup.events[0]); if len(payload.deductions) > 0 do assert(mystery_string_set_has(mystery.earned_deductions[:], payload.deductions[0].id)); if len(payload.questions) > 0 do assert(len(mystery.question_progress) > 0 && mystery.question_progress[len(mystery.question_progress) - 1].state == 2)

	scene :=
		scenario.compiled.runtime.scenes[0].id; record := authoring_scenario_record_init("deterministic_ui", "UI recording"); defer authoring_scenario_record_destroy(&record); assert(authoring_scenario_record_action(&record, {action = "start", value = scene})); first: Scenario_Context; second: Scenario_Context; assert(scenario_context_init("assets/stories/mysteries/the_torn_appointment.story.toml", "assets/levels/vale_house.toml", &first).ok && scenario_context_init("assets/stories/mysteries/the_torn_appointment.story.toml", "assets/levels/vale_house.toml", &second).ok); first_result := authoring_scenario_replay(&record, &first); second_result := authoring_scenario_replay(&record, &second); assert(first_result.ok && second_result.ok && first.runtime.current_scene == second.runtime.current_scene && first.runtime.current_node == second.runtime.current_node); scenario_context_destroy(&first); scenario_context_destroy(&second)
	failure_record := authoring_scenario_record_init(
		"failure_ui",
		"Failure export",
	); defer authoring_scenario_record_destroy(&failure_record); assert(authoring_scenario_record_action(&failure_record, {action = "start", value = "missing_scene"})); failed: Scenario_Context; assert(scenario_context_init("assets/stories/mysteries/the_torn_appointment.story.toml", "assets/levels/vale_house.toml", &failed).ok); failure := authoring_scenario_replay(&failure_record, &failed); assert(!failure.ok && failure.failure.failed && strings.contains(authoring_scenario_failure_serialize(&failure_record, &failure), "missing_scene")); scenario_context_destroy(&failed)
	saved_spatial :=
		authoring_workspace.playtest_spatial_saved; saved_x, saved_y := authoring_workspace.playtest_player_x, authoring_workspace.playtest_player_y; saved_screen := authoring_workspace.playtest_screen; authoring_workspace.playtest_spatial_saved = true; authoring_workspace.playtest_player_x = 7; authoring_workspace.playtest_player_y = 9; authoring_workspace.playtest_screen = .Authoring; game := Game {
		player_x = 100,
		player_y = 200,
		screen   = .Reveal_Prep,
	}; assert(
		authoring_workspace_restore_spatial_playtest(&game) &&
		game.player_x == 7 &&
		game.player_y == 9 &&
		game.screen == .Authoring &&
		!authoring_workspace.playtest_spatial_saved,
	); authoring_workspace.playtest_spatial_saved = saved_spatial; authoring_workspace.playtest_player_x = saved_x; authoring_workspace.playtest_player_y = saved_y; authoring_workspace.playtest_screen = saved_screen

	// The workspace entry point, not only the coordinator, exercises every
	// creator-facing start mode and restores the isolated source after each run.
	saved_active_story, saved_graph, saved_level, saved_campaign, saved_runtime :=
		active_story_project,
		graph_document,
		level_document,
		campaign_document,
		active_story_runtime; saved_playthrough := campaign_playthrough; saved_graph_source := graph_source_project; saved_creator_setup := authoring_workspace.creator_setup; saved_active_scene, saved_selected_node := graph_state.active_scene, graph_state.selected_node
	active_story_project = story_project_clone(
		project,
	); graph_document = authoring_graph_from_story(&active_story_project); graph_state.active_scene = 0; graph_state.selected_node = 0; assert(level_load("assets/levels/vale_house.toml", &level_document).ok); playtest_compiled := compile_story_project(&active_story_project); assert(playtest_compiled.ok); active_story_runtime = story_runtime_new(&playtest_compiled.story); campaign_document = {
		version         = "MysteryCampaign v2",
		id              = "workspace_modes",
		title           = "Workspace Modes",
		content_version = "1.0.0",
	}; append(
		&campaign_document.conditions,
		Campaign_Condition{kind = .Always},
	); append(&campaign_document.cases, Campaign_Case{id = active_story_project.id, title = active_story_project.title, story_path = "story.toml", level_path = "level.toml", case_content_version = active_story_project.content_version, condition_root = 0, required = true}); campaign_playthrough = {
		campaign_id              = campaign_document.id,
		campaign_content_version = campaign_document.content_version,
		active_case              = -1,
	}; authoring_workspace.creator_setup = {
		action_budget = -1,
		time_minutes  = -1,
	}; graph_source_project = &active_story_project
	for mode in Authoring_Playtest_Start_Mode {authoring_workspace.playtest_start_mode = int(mode)
		start_game := Game {
			screen   = .Authoring,
			player_x = 3,
			player_y = 4,
		}
		message := authoring_workspace_start_playtest(&start_game)
		if !authoring_workspace.playtest.active {fmt.println("PLAYTEST MODE FAILURE · ", mode, " · ", message)
			for diagnostic in authoring_workspace.playtest.validation.diagnostics do fmt.println("  ", diagnostic.entity_id, " · ", diagnostic.message)}
		assert(
			strings.contains(message, "PLAYTEST STARTED FROM") &&
			authoring_workspace.playtest.active,
		)
		switch mode {case .Opening, .Selected_Scene, .Selected_Node:
			assert(start_game.screen == .Dialogue); case .Spatial_Position:
			assert(start_game.screen == .Investigate); case .Question:
			assert(start_game.screen == .Board); case .Reveal:
			assert(start_game.screen == .Reveal_Prep)}
		assert(
			strings.contains(authoring_workspace_end_playtest(&start_game), "RESTORED") &&
			start_game.screen == .Authoring &&
			start_game.player_x == 3 &&
			start_game.player_y == 4,
		)}
	story_runtime_destroy(
		&active_story_runtime,
	); story_compile_result_destroy(&playtest_compiled); story_project_destroy(&active_story_project); authoring_graph_document_destroy(&graph_document); authoring_level_document_destroy(&level_document); campaign_destroy(&campaign_document); active_story_project = saved_active_story; graph_document = saved_graph; level_document = saved_level; campaign_document = saved_campaign; active_story_runtime = saved_runtime; campaign_playthrough = saved_playthrough; graph_source_project = saved_graph_source; authoring_workspace.creator_setup = saved_creator_setup; graph_state.active_scene = saved_active_scene; graph_state.selected_node = saved_selected_node
}

run_vertical_link_tests :: proc() {
	doc: Level_Document; assert(level_load(LEVEL_DEFAULT_PATH, &doc).ok); append(&doc.stories, Level_Story{"upper_test", "Upper Test", 3, 2.5}); clear(&doc.vertical_links); doc.active_story = 0; command := Level_Command {
		kind      = .Create_Vertical_Link,
		entity_id = "straight_test",
		a         = {2, 2},
		b         = {2, 8},
		c         = {f32(Level_Vertical_Link_Kind.Stairs), 0},
		value     = 1,
	}; assert(
		level_preview_transaction(&doc, command).state != .Blocked &&
		level_commit_transaction(&doc, command, "create stairs") &&
		len(doc.vertical_links) == 1,
	); mesh := procedural_stair_mesh(doc.vertical_links[0], 3); assert(mesh.ready && len(mesh.indices) > 0 && mesh.max.y == 3); assert(generated_stair_shape({2, 2}, {2, 8}, 3, 1) == .Straight && generated_stair_shape({2, 2}, {2, 4}, 3, 1) == .U); landing, picked := level_pick_control_point(&doc, {2, 8}, {.Vertical_Link, "straight_test", -1}); assert(picked && editor_control_point_index(landing) == 1); old_finish := doc.vertical_links[0].finish; move, ok := level_selection_move_command(&doc, landing, {1, 1}); assert(ok && move.kind == .Move_Vertical_Link_Point && level_preview_transaction(&doc, move).state != .Blocked && level_commit_transaction(&doc, move, "move upper landing") && doc.vertical_links[0].finish != old_finish); assert(level_undo(&doc) && doc.vertical_links[0].finish == old_finish); assert(level_delete_selection(&doc, {.Vertical_Link, "straight_test", -1}) && len(doc.vertical_links) == 0 && level_undo(&doc) && len(doc.vertical_links) == 1)
}

run_ui_dim_tests :: proc() {
	backend: Vulkan_Backend
	assert(vk_ui_dim_all_except(&backend, nil) == 1)
	assert(vk_ui_dim_all_except(&backend, []Rect{{100, 100, 200, 100}}) == 4)
	assert(vk_ui_dim_all_except(&backend, []Rect{{-50, -50, 100, 100}}) == 2)
	assert(vk_ui_dim_all_except(&backend, []Rect{{0, 0, 1200, 720}}) == 0)
	assert(vk_ui_dim_all_except(&backend, []Rect{{100, 100, 200, 100}, {200, 150, 200, 100}}) > 0)
	assert(vk_ui_dim_all_except(&backend, nil, {0, 0, 0, 0}) == 0)
}
run_roof_numeric_tests :: proc() {
	doc: Level_Document; assert(level_load(LEVEL_DEFAULT_PATH, &doc).ok); assert(len(doc.rooms) > 0); room := doc.rooms[0]; roof_index := level_roof_for_room(&doc, room.id); if roof_index < 0 {command := Level_Command {
			kind      = .Create_Roof,
			entity_id = "numeric_roof",
			material  = room.id,
			a         = {f32(Level_Roof_Style.Gable), 0},
			b         = {.4, 1},
			value     = 30,
		}; assert(
			level_commit_transaction(&doc, command, "create numeric roof"),
		); roof_index = level_roof_index(&doc, "numeric_roof")}; level_document = level_clone_document(&doc); level_history = {}; roof := level_document.roofs[roof_index]; editor_state.selection[0] = {.Roof, roof.id, -1}; editor_state.selection_count = 1; editor_begin_numeric_edit(.Roof_Pitch, roof.pitch); assert(editor_append_numeric_char('4') && editor_append_numeric_char('2') && editor_advance_numeric_edit(1) && editor_state.numeric_field == .Roof_Overhang && level_document.roofs[roof_index].pitch == 42); editor_cancel_numeric_edit(); assert(level_undo(&level_document) && level_document.roofs[roof_index].pitch == roof.pitch)
}
run_light_numeric_tests :: proc() {
	doc: Level_Document; assert(level_load(LEVEL_DEFAULT_PATH, &doc).ok); if len(doc.lights) == 0 {command := Level_Command {
			kind      = .Add_Light,
			entity_id = "numeric_light",
			a         = {4, 4},
			b         = {4, 1},
			c         = {2, f32(Level_Light_Kind.Point)},
			value     = 0,
			color     = {255, 255, 255, 255},
		}; assert(
			level_commit_transaction(&doc, command, "create numeric light"),
		)}; level_document = level_clone_document(&doc); level_history = {}; light := level_document.lights[0]; editor_state.selection[0] = {.Light, light.id, -1}; editor_state.selection_count = 1; editor_begin_numeric_edit(.Light_Range, light.range); assert(editor_append_numeric_char('6') && editor_append_numeric_char('.') && editor_append_numeric_char('2') && editor_append_numeric_char('5') && editor_advance_numeric_edit(1) && editor_state.numeric_field == .Light_Intensity && level_document.lights[0].range == 6.25); editor_cancel_numeric_edit(); assert(level_undo(&level_document) && level_document.lights[0].range == light.range)
}
run_marker_numeric_tests :: proc() {
	doc: Level_Document; assert(level_load(LEVEL_DEFAULT_PATH, &doc).ok); if len(doc.markers) == 0 {command := Level_Command {
			kind      = .Add_Marker,
			entity_id = "numeric_marker",
			a         = {4, 4},
			b         = {.5, 0},
			c         = {2, f32(Level_Marker_Kind.Camera)},
			value     = 0,
		}; assert(
			level_commit_transaction(&doc, command, "create numeric marker"),
		)}; level_document = level_clone_document(&doc); level_history = {}; marker := level_document.markers[0]; editor_state.selection[0] = {.Marker, marker.id, -1}; editor_state.selection_count = 1; editor_begin_numeric_edit(.Marker_Radius, marker.radius); assert(editor_append_numeric_char('1') && editor_append_numeric_char('.') && editor_append_numeric_char('2') && editor_append_numeric_char('5') && editor_advance_numeric_edit(1) && editor_state.numeric_field == .Marker_Facing && level_document.markers[0].radius == 1.25); editor_cancel_numeric_edit(); assert(level_undo(&level_document) && level_document.markers[0].radius == marker.radius)
}
run_light_direction_numeric_tests :: proc() {
	doc: Level_Document; assert(level_load(LEVEL_DEFAULT_PATH, &doc).ok); append(&doc.lights, Level_Light{id = "numeric_spot", kind = .Spot, story = 0, position = {4, 4}, elevation = 2, range = 5, intensity = 1, facing = 45, cone_angle = 30, color = {255, 255, 255, 255}}); level_document = level_clone_document(&doc); level_history = {}; index := level_light_index(&level_document, "numeric_spot"); assert(index >= 0); editor_state.selection[0] = {.Light, "numeric_spot", -1}; editor_state.selection_count = 1; editor_begin_numeric_edit(.Light_Facing, 45); assert(editor_append_numeric_char('1') && editor_append_numeric_char('3') && editor_append_numeric_char('5') && editor_advance_numeric_edit(1) && editor_state.numeric_field == .Light_Cone && level_document.lights[index].facing == 135); assert(editor_append_numeric_char('4') && editor_append_numeric_char('0') && editor_commit_numeric_edit() && level_document.lights[index].cone_angle == 40); assert(level_undo(&level_document) && level_document.lights[index].cone_angle == 30); assert(level_undo(&level_document) && level_document.lights[index].facing == 45)
}
run_ground_generation_tests :: proc() {
	doc: Level_Document; assert(level_load(LEVEL_DEFAULT_PATH, &doc).ok); assert(level_water_index(&doc, "garden_pond") >= 0); clear(&doc.waters); path := Level_Command {
		kind        = .Add_Path,
		entity_id   = "road_test",
		c           = {f32(Level_Path_Kind.Road), 0},
		value       = 3,
		point_count = 3,
	}; path.points[0] = {
		1,
		14,
	}; path.points[1] = {8, 13}; path.points[2] = {14, 15}; assert(level_preview_transaction(&doc, path).state != .Blocked && level_commit_transaction(&doc, path, "create road") && doc.paths[len(doc.paths) - 1].kind == .Road); path_mesh := procedural_path_mesh(&doc, doc.paths[len(doc.paths) - 1]); assert(path_mesh.ready && len(path_mesh.indices) == 12); pond := Level_Command {
		kind        = .Create_Water,
		entity_id   = "pond_test",
		value       = .25,
		point_count = 4,
	}; pond.points[0] = {
		17,
		6,
	}; pond.points[1] = {21, 6}; pond.points[2] = {21, 10}; pond.points[3] = {17, 10}; assert(level_preview_transaction(&doc, pond).state != .Blocked && level_commit_transaction(&doc, pond, "create pond") && len(doc.waters) == 1); water_mesh := procedural_water_mesh(&doc, doc.waters[0]); assert(water_mesh.ready && len(water_mesh.indices) > 0 && len(water_mesh.vertices) > len(doc.waters[0].points) * 5); assert(level_pick(&doc, {19, 8}).kind == .Water)
	path_point, picked := level_pick_control_point(
		&doc,
		{8, 13},
		{.Path, "road_test", -1},
	); assert(picked && editor_control_point_index(path_point) == 1); old_path_point := doc.paths[level_path_index(&doc, "road_test")].points[1]; move_path, ok := level_selection_move_command(&doc, path_point, {1, .5}); assert(ok && move_path.kind == .Move_Path_Point && level_preview_transaction(&doc, move_path).state != .Blocked && level_commit_transaction(&doc, move_path, "reshape path")); assert(doc.paths[level_path_index(&doc, "road_test")].points[1] != old_path_point && level_undo(&doc) && doc.paths[level_path_index(&doc, "road_test")].points[1] == old_path_point)
	water_point, picked_water := level_pick_control_point(
		&doc,
		{21, 6},
		{.Water, "pond_test", -1},
	); assert(picked_water && editor_control_point_index(water_point) == 1); old_water_point := doc.waters[level_water_index(&doc, "pond_test")].points[1]; move_water, water_ok := level_selection_move_command(&doc, water_point, {.5, .5}); assert(water_ok && move_water.kind == .Move_Water_Point && level_preview_transaction(&doc, move_water).state != .Blocked && level_commit_transaction(&doc, move_water, "reshape shoreline")); assert(doc.waters[level_water_index(&doc, "pond_test")].points[1] != old_water_point && level_undo(&doc) && doc.waters[level_water_index(&doc, "pond_test")].points[1] == old_water_point)
	level_document = level_clone_document(
		&doc,
	); level_document.active_story = 0; assert(!nav_point_walkable(19, 8)); door_index := level_opening_index(&level_document, "door_hall_dining"); if door_index >= 0 {door_position, door_ok := level_opening_position(&level_document, level_document.openings[door_index]); assert(door_ok && level_circulation_cost(&level_document, door_position) > .99 && level_furniture_circulation_cost(&level_document, door_position, .6) >= .99); assert(level_furniture_doorway_badness(&level_document, door_position, 1.15) >= .999); door_bed_preview := level_preview_transaction(&level_document, Level_Command{kind = .Place_Object, entity_id = "door_bed_regression", a = door_position, value = 90, material = "bed"}); assert(door_bed_preview.state == .Blocked && strings.contains(door_bed_preview.message, "doorway"))}; assert(level_delete_selection(&doc, {.Water, "pond_test", -1}) && len(doc.waters) == 0 && level_undo(&doc) && len(doc.waters) == 1)
}
run_marker_editor_tests :: proc() {
	doc: Level_Document; assert(level_load(LEVEL_DEFAULT_PATH, &doc).ok); clear(&doc.markers); level_history = {}
	for kind in Level_Marker_Kind {id := fmt.tprintf("marker_%d", int(kind)); reference := ""
		destination := ""
		if kind == .Character_Spawn || kind == .Interaction || kind == .Clue || kind == .Trigger do reference = "case_binding"
		if kind == .Transition do destination = "marker_0"
		command := Level_Command {
			kind        = .Add_Marker,
			entity_id   = id,
			a           = {2 + f32(int(kind)), 3},
			b           = {.75, 45},
			c           = {2.25, f32(kind)},
			material    = reference,
			destination = destination,
			value       = 0,
		}
		assert(
			level_preview_transaction(&doc, command).state != .Blocked &&
			level_commit_transaction(&doc, command, "place typed marker"),
		)
		marker := doc.markers[len(doc.markers) - 1]
		assert(
			marker.id == id &&
			marker.kind == kind &&
			marker.radius == .75 &&
			marker.facing == 45 &&
			marker.camera_height == 2.25 &&
			marker.reference == reference &&
			marker.destination == destination,
		)}
	assert(
		level_marker_uses_binding(.Trigger),
	); assert(!level_marker_binding_compatible(.Trigger, .Camera))
	assert(
		len(doc.markers) == len(Level_Marker_Kind),
	); selected := Editor_Selection{.Marker, "marker_6", -1}; before := doc.markers[level_marker_index(&doc, "marker_6")]; move, ok := level_selection_move_command(&doc, selected, {.5, .25}); assert(ok && move.kind == .Set_Marker && level_commit_transaction(&doc, move, "move camera marker")); moved := doc.markers[level_marker_index(&doc, "marker_6")]; assert(moved.position != before.position && moved.kind == before.kind && moved.camera_height == before.camera_height); assert(level_undo(&doc) && doc.markers[level_marker_index(&doc, "marker_6")].position == before.position); count := len(doc.markers); assert(level_delete_selection(&doc, selected) && len(doc.markers) == count - 1); assert(level_undo(&doc) && len(doc.markers) == count && doc.markers[level_marker_index(&doc, "marker_6")].camera_height == 2.25)
	rename := marker_edit_command(
		doc.markers[level_marker_index(&doc, "marker_0")],
	); rename.interaction_prompt = "front_door_spawn"; assert(level_commit_transaction(&doc, rename, "rename marker") && level_marker_index(&doc, "front_door_spawn") >= 0 && doc.markers[level_marker_index(&doc, "marker_5")].destination == "front_door_spawn"); assert(level_undo(&doc) && level_marker_index(&doc, "marker_0") >= 0 && doc.markers[level_marker_index(&doc, "marker_5")].destination == "marker_0")
	ensure_test_torn_story(

	); payload := mystery_payload(&test_story_project); assert(payload != nil); binding_game := Game {
		story_project = &test_story_project,
	}; interaction :=
		doc.markers[level_marker_index(&doc, "marker_2")]; interaction.reference = ""; first_binding := marker_binding_next_in(&doc, &binding_game, interaction, 1); assert(len(payload.pois) > 0 && first_binding == payload.pois[0].entity_id); interaction.reference = first_binding; assert(marker_binding_next_in(&doc, &binding_game, interaction, -1) == payload.pois[len(payload.pois) - 1].entity_id); transition := doc.markers[level_marker_index(&doc, "marker_5")]; assert(marker_binding_next_in(&doc, &binding_game, transition, 1) != "" && marker_binding_next_in(&doc, &binding_game, transition, 1) != transition.id)
	trigger :=
		doc.markers[level_marker_index(&doc, "marker_4")]; trigger.reference = ""; assert(len(test_story_project.events) > 0 && marker_binding_next_in(&doc, &binding_game, trigger, 1) == test_story_project.events[0].id)
	level_document = level_clone_document(
		&doc,
	); level_document.active_story = 0; level_document.markers[level_marker_index(&level_document, "marker_4")].reference = test_story_project.events[0].id; assert(graph_picker_candidate_raw(&binding_game, .Event, 0) == test_story_project.events[0].id); assert(graph_picker_candidate_raw(&binding_game, .Interaction, 0) == "case_binding"); append(&level_document.markers, Level_Marker{id = "other_story_camera", kind = .Camera, story = 1}); assert(graph_picker_candidate_raw(&binding_game, .Camera, 1) == "")
}
run_diagnostic_focus_tests :: proc() {
	assert(
		level_load(LEVEL_DEFAULT_PATH, &level_document).ok,
	); append(&level_document.objects, Level_Object{id = "diagnostic_object", story = 0, position = {11, 9}}); _ = level_validate(&level_document); issue := -1; for diagnostic, i in level_document.diagnostics do if diagnostic.entity_id == "diagnostic_object" do issue = i; assert(issue >= 0 && level_selection_for_id(&level_document, "diagnostic_object").kind == .Object); g := Game {
		camera_x = 1,
		camera_y = 1,
	}; editor_state.diagnostics_visible =
		true; assert(editor_focus_diagnostic(&g, issue)); assert(!editor_state.diagnostics_visible && editor_state.selection_count == 1 && editor_state.selection[0].entity_id == "diagnostic_object" && g.camera_x == 11 && g.camera_y == 9)
}
run_editor_playtest_tests :: proc() {
	assert(
		level_load(LEVEL_DEFAULT_PATH, &level_document).ok,
	); spawn_index := level_marker_index(&level_document, "spawn_player"); assert(spawn_index >= 0); spawn := level_document.markers[spawn_index]; editor_state.selection[0] = {.Marker, spawn.id, -1}; editor_state.selection_count = 1; editor_state.cursor_world = {20, 20}; editor_state.cursor_world_valid = true; editor_state.playtesting = false; editor_playtest_snapshot = {}; g := Game {
		story_project   = &test_story_project,
		editor_mode     = .Build,
		camera_x        = 12,
		camera_y        = 8,
		top_down_camera = true,
		player_x        = 1,
		player_y        = 1,
		build_tool      = .Marker,
	}; assert(
		apply_player_spawn_marker(&g) &&
		g.player_x == spawn.position.x &&
		g.player_y == spawn.position.y &&
		math.abs(g.player_angle - f32(math.PI) / 2) < .001 &&
		g.camera_x == spawn.position.x &&
		g.camera_y == spawn.position.y,
	); revision := level_document.revision; assert(editor_begin_playtest(&g) && editor_state.playtesting && g.editor_mode != .Build && g.player_x == spawn.position.x && g.player_y == spawn.position.y && !g.top_down_camera); level_document.revision += 10; editor_state.selection_count = 0; assert(editor_end_playtest(&g) && !editor_state.playtesting && g.editor_mode == .Build && g.top_down_camera && g.camera_x == spawn.position.x && g.camera_y == spawn.position.y && level_document.revision == revision && editor_state.selection_count == 1 && editor_state.selection[0].entity_id == spawn.id); append(&level_document.objects, Level_Object{id = "invalid_playtest_object", story = 0, position = {4, 4}}); assert(!editor_begin_playtest(&g) && editor_state.diagnostics_visible)
}
run_editor_selection_set_tests :: proc() {
	assert(
		level_load(LEVEL_DEFAULT_PATH, &level_document).ok,
	); clear(&level_document.objects); clear(&level_document.markers); append(&level_document.objects, Level_Object{id = "box_object_a", catalog_id = "core:plant", story = 0, position = {1, 1}, rotation = 15, tint = {255, 255, 255, 255}}, Level_Object{id = "box_object_b", catalog_id = "core:chair", story = 0, position = {1.5, 1.5}, elevation = .25, tint = {255, 255, 255, 255}}); append(&level_document.markers, Level_Marker{id = "box_marker", kind = .Camera, story = 0, position = {3, 2}, radius = .5, facing = 90, camera_height = 2.2}); found: [16]Editor_Selection; count := level_select_box(&level_document, {.5, .5}, {3.5, 2.5}, &found); assert(count == 3); editor_state.selection_count = count; copy(editor_state.selection[:], found[:count]); assert(editor_selection_index(&editor_state, {.Marker, "box_marker", -1}) >= 0); assert(!editor_selection_toggle(&editor_state, {.Marker, "box_marker", -1}) && editor_state.selection_count == 2); assert(editor_selection_toggle(&editor_state, {.Marker, "box_marker", -1}) && editor_state.selection_count == 3)
	editor_state.selection[0] = {
		.Object,
		"box_object_a",
		-1,
	}; editor_state.selection_count = 1; editor_begin_numeric_edit(.Object_X, 1); assert(editor_append_numeric_char('2') && editor_append_numeric_char('.') && editor_append_numeric_char('2') && editor_append_numeric_char('5')); level_history = {}; assert(editor_advance_numeric_edit(1) && editor_state.numeric_field == .Object_Y && level_document.objects[level_object_index(&level_document, "box_object_a")].position.x == 2.25 && level_history.undo_count == 1); editor_cancel_numeric_edit(); assert(level_undo(&level_document) && level_document.objects[level_object_index(&level_document, "box_object_a")].position.x == 1); editor_state.selection_count = count; copy(editor_state.selection[:], found[:count])
	marker_y_before :=
		level_document.markers[level_marker_index(&level_document, "box_marker")].position.y; level_history = {}; assert(editor_align_selection(false) && level_history.undo_count == 1); anchor_y := level_document.objects[level_object_index(&level_document, "box_object_a")].position.y; assert(level_document.objects[level_object_index(&level_document, "box_object_b")].position.y == anchor_y && level_document.markers[level_marker_index(&level_document, "box_marker")].position.y == anchor_y); assert(level_undo(&level_document) && level_document.markers[level_marker_index(&level_document, "box_marker")].position.y == marker_y_before); assert(level_redo(&level_document))
	level_history =
		{}; assert(editor_distribute_selection(true) && level_history.undo_count == 1 && level_document.objects[level_object_index(&level_document, "box_object_b")].position.x == 2); assert(level_undo(&level_document) && level_document.objects[level_object_index(&level_document, "box_object_b")].position.x == 1.5); assert(level_redo(&level_document))
	move_commands: [16]Level_Command; move_count := editor_drag_commands({.5, .25}, &move_commands); assert(move_count == 3); object_a_before := level_document.objects[level_object_index(&level_document, "box_object_a")].position; level_history = {}; assert(level_commit_transactions(&level_document, move_commands[:move_count], "move selection set") && level_history.undo_count == 1 && level_document.objects[level_object_index(&level_document, "box_object_a")].position != object_a_before); assert(level_undo(&level_document) && level_document.objects[level_object_index(&level_document, "box_object_a")].position == object_a_before); assert(level_redo(&level_document))
	assert(
		editor_copy_selection(),
	); objects_before := len(level_document.objects); markers_before := len(level_document.markers); level_history = {}; assert(editor_paste_selection({.5, .5}) && level_history.undo_count == 1 && len(level_document.objects) == objects_before + 2 && len(level_document.markers) == markers_before + 1 && editor_state.selection_count == 3); pasted_marker := level_document.markers[len(level_document.markers) - 1]; assert(pasted_marker.kind == .Camera && pasted_marker.facing == 90 && pasted_marker.camera_height == 2.2); assert(level_undo(&level_document) && len(level_document.objects) == objects_before && len(level_document.markers) == markers_before); assert(level_redo(&level_document) && len(level_document.objects) == objects_before + 2 && len(level_document.markers) == markers_before + 1); assert(editor_delete_selection_set() && len(level_document.objects) == objects_before && len(level_document.markers) == markers_before); assert(level_undo(&level_document) && len(level_document.objects) == objects_before + 2 && len(level_document.markers) == markers_before + 1)
	window_index := -1; for opening, i in level_document.openings do if opening.kind == .Window {window_index = i; break}; assert(window_index >= 0); window := level_document.openings[window_index]; editor_state.selection[0] = {.Opening, window.id, window.segment}; editor_state.selection_count = 1; editor_begin_numeric_edit(.Opening_Height, window.height); assert(editor_append_numeric_char('0') && editor_append_numeric_char('.') && editor_append_numeric_char('8')); level_history = {}; assert(editor_commit_numeric_edit() && level_document.openings[window_index].height == .8 && level_history.undo_count == 1); assert(level_undo(&level_document) && level_document.openings[window_index].height == window.height)
	path_index := -1; for path, i in level_document.paths do if path.kind != .Wall {path_index = i; break}; assert(path_index >= 0); path_width_before := level_document.paths[path_index].width; editor_state.selection[0] = {.Path, level_document.paths[path_index].id, -1}; editor_state.selection_count = 1; editor_begin_numeric_edit(.Path_Width, path_width_before); assert(editor_append_numeric_char('1') && editor_append_numeric_char('.') && editor_append_numeric_char('8')); level_history = {}; assert(editor_commit_numeric_edit() && level_document.paths[path_index].width == 1.8 && level_history.undo_count == 1); assert(level_undo(&level_document) && level_document.paths[path_index].width == path_width_before)
	view_game :=
		Game{}; editor_set_view(&view_game, .Navmesh); assert(view_game.top_down_camera && editor_state.view == .Navmesh && editor_view_name(.Navmesh) == "NAVMESH"); editor_set_view(&view_game, .Cutaway); assert(!view_game.top_down_camera && editor_state.view == .Cutaway)
}
accept_level_command :: proc(
	doc: ^Level_Document,
	command: Level_Command,
	label: string,
) {fmt.println("SELF TEST · ", strings.to_upper(label)); level_history = {}; assert(
		level_preview_transaction(doc, command).state != .Blocked &&
		level_commit_transaction(doc, command, label),
	)
	revision := doc.revision
	assert(level_undo(doc) && level_redo(doc) && doc.revision == revision)}
run_vale_house_editor_acceptance_tests :: proc() {
	doc: Level_Document; assert(level_load(LEVEL_DEFAULT_PATH, &doc).ok); append(&doc.stories, Level_Story{"acceptance_upper", "Acceptance Upper", 3, 2.5}); doc.active_story = 0
	accept_level_command(
		&doc,
		Level_Command{kind = .Move_Room, entity_id = "dining_room", a = {.25, 0}},
		"accept room edit",
	)
	wall := Level_Command {
			kind        = .Add_Path,
			entity_id   = "acceptance_wall",
			material    = "structure",
			c           = {f32(Level_Path_Kind.Wall), 0},
			value       = HOUSE_WALL_THICKNESS,
			point_count = 2,
		}; wall.points[0] = {
		17,
		13,
	}; wall.points[1] = {22, 13}; accept_level_command(&doc, wall, "accept path edit")
	host := Editor_Selection {
		.Path,
		"acceptance_wall",
		0,
	}; opening, opening_ok := level_opening_command_at(&doc, host, {19.5, 13}, .Door); assert(opening_ok); opening.entity_id = "acceptance_door"; accept_level_command(&doc, opening, "accept opening edit")
	center := level_room_center(
		&doc.rooms[level_room_index(&doc, "study")],
	); accept_level_command(&doc, Level_Command{kind = .Place_Object, entity_id = "acceptance_object", a = center, value = 30, material = "chair"}, "accept object edit")
	study_roof := level_roof_for_room(
		&doc,
		"study",
	); if study_roof >= 0 do ordered_remove(&doc.roofs, study_roof); accept_level_command(&doc, Level_Command{kind = .Create_Roof, entity_id = "acceptance_roof", material = "study", a = {f32(Level_Roof_Style.Hip), 0}, b = {.4, 0}, value = 30}, "accept roof edit")
	accept_level_command(
		&doc,
		Level_Command {
			kind = .Create_Vertical_Link,
			entity_id = "acceptance_stairs",
			a = {17, 14},
			b = {22, 14},
			c = {f32(Level_Vertical_Link_Kind.Stairs), 0},
			value = 1,
		},
		"accept stair edit",
	)
	pond := Level_Command {
		kind        = .Create_Water,
		entity_id   = "acceptance_pond",
		value       = .25,
		point_count = 4,
	}; pond.points[0] = {
		17,
		6,
	}; pond.points[1] = {21, 6}; pond.points[2] = {21, 10}; pond.points[3] = {17, 10}; accept_level_command(&doc, pond, "accept water edit")
	accept_level_command(
		&doc,
		Level_Command {
			kind = .Sculpt_Terrain,
			a = {2, 4},
			b = {6, 7},
			c = {.5, 0},
			value = .5,
			brush = .Raise,
		},
		"accept terrain edit",
	)
	accept_level_command(
		&doc,
		Level_Command {
			kind = .Add_Marker,
			entity_id = "acceptance_marker",
			a = {18, 12},
			b = {.75, 90},
			c = {2, f32(Level_Marker_Kind.Staging)},
			value = 0,
		},
		"accept marker edit",
	)
	path := "/private/tmp/chicago-vale-house-acceptance.toml"; assert(level_save(path, &doc).ok); reloaded: Level_Document; assert(level_load(path, &reloaded).ok && level_validate(&reloaded).ok); assert(len(reloaded.objects) >= len(doc.objects) && level_object_index(&reloaded, "acceptance_object") >= 0 && level_roof_index(&reloaded, "acceptance_roof") >= 0 && level_vertical_link_index(&reloaded, "acceptance_stairs") >= 0 && level_water_index(&reloaded, "acceptance_pond") >= 0 && level_marker_index(&reloaded, "acceptance_marker") >= 0)
	level_document = level_clone_document(
		&reloaded,
	); editor_state.selection[0] = {.Marker, "spawn_player", -1}; editor_state.selection_count = 1; editor_state.cursor_world_valid = false; editor_state.playtesting = false; editor_playtest_snapshot = {}; g := Game {
		story_project   = &test_story_project,
		editor_mode     = .Build,
		camera_x        = 12,
		camera_y        = 8,
		top_down_camera = true,
		player_x        = 1,
		player_y        = 1,
		build_tool      = .Select,
	}; before := level_serialize(
		&level_document,
	); assert(editor_begin_playtest(&g) && editor_end_playtest(&g)); after := level_serialize(&level_document); assert(before == after && g.editor_mode == .Build && editor_state.selection[0].entity_id == "spawn_player")
}
