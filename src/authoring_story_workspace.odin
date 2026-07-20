package main

import "core:fmt"
import "core:strconv"
import "core:strings"

authoring_workspace_add_story_record :: proc() {
	kind := Story_Authoring_Record_Kind(
		clamp(authoring_workspace.selected_category, 0, int(Story_Authoring_Record_Kind.Effect)),
	); id := string(authoring_workspace.form_buffer[:authoring_workspace.form_count]); if id == "" do id = authoring_workspace_next_id(strings.to_lower(fmt.tprintf("%v", kind))); command := Story_Authoring_Command {
		kind        = .Add,
		record_kind = kind,
	}
	#partial switch kind {case .Entity:
		command.entity = {
			id           = id,
			kind         = "object",
			display_name = "New Entity",
		}; case .Role:
		command.role = {
			id           = id,
			display_name = "New Role",
		}; case .Variable:
		command.variable = {
			id            = id,
			display_name  = "New Variable",
			kind          = .Boolean,
			default_value = story_value_boolean(false),
		}; case .Fact:
		command.fact = {
			id           = id,
			display_name = "New Fact",
		}; case .Proposition:
		command.proposition = {
			id   = id,
			text = "New proposition",
		}; case .Knowledge:
		authoring_workspace.feedback = "ADD REQUIRES AN ACTOR AND PROPOSITION"
		return; case .Relationship:
		command.relationship = {
			id   = id,
			kind = "relationship",
		}; case .Event:
		command.event = {
			id     = id,
			action = "event",
		}; case .Objective:
		command.objective = {
			id           = id,
			display_name = "New Objective",
		}; case .Ending:
		command.ending = {
			id           = id,
			title        = "New Ending",
			condition_id = "always",
		}; case .Storylet_Group:
		command.storylet_group = {
			id          = id,
			allow_empty = true,
		}; case .Storylet:
		command.storylet = {
			id            = id,
			fallback      = true,
			repeat_policy = .Always,
		}; case .Invariant:
		command.invariant = {
			id           = id,
			description  = "New invariant",
			condition_id = "always",
			kind         = .Always,
		}; case .Condition:
		command.condition = {
			id   = id,
			kind = .Always,
		}; case .Effect:
		command.effect = {
			id       = id,
			kind     = .Emit_Event,
			event_id = id,
		}}
	commands := [1]Story_Authoring_Command {
		command,
	}; result := story_authoring_apply(&active_story_project, &authoring_workspace.story_history, commands[:]); committed := result.ok; authoring_workspace.feedback = result.message; story_authoring_result_destroy(&result); if committed do graph_import_story(&active_story_project)
}

// ---- Story typed record editor -------------------------------------------------
// Presentation code can enumerate fields however it likes; these helpers keep all
// edits typed, transactional, undoable, and independent of widget state.
Story_List_Edit :: enum {
	Add,
	Remove,
	Move_Up,
	Move_Down,
}

authoring_story_parse_int :: proc(text: string) -> (int, bool) {v, ok := strconv.parse_i64(
		strings.trim_space(text),
	)
	return int(v), ok}
authoring_story_parse_bool :: proc(text: string) -> (bool, bool) {v := strings.to_lower(
		strings.trim_space(text),
	)
	if v == "true" || v == "1" do return true, true
	if v == "false" || v == "0" do return false, true
	return false, false}

authoring_story_selected_command :: proc(
	kind: Story_Authoring_Record_Kind,
	index: int,
) -> (
	Story_Authoring_Command,
	bool,
) {
	command := Story_Authoring_Command {
		kind        = .Update,
		record_kind = kind,
	}
	if index < 0 || index >= authoring_story_count(kind) do return command, false
	#partial switch kind {
	case .Entity:
		command.entity = active_story_project.entities[index]
	case .Role:
		command.role = active_story_project.roles[index]
	case .Variable:
		command.variable = active_story_project.variables[index]
	case .Fact:
		command.fact = active_story_project.facts[index]
	case .Proposition:
		command.proposition = active_story_project.propositions[index]
	case .Knowledge:
		command.knowledge = active_story_project.initial_knowledge[index]
	case .Relationship:
		command.relationship = active_story_project.relationships[index]
	case .Event:
		command.event = active_story_project.events[index]
	case .Objective:
		command.objective = active_story_project.objectives[index]
	case .Ending:
		command.ending = active_story_project.endings[index]
	case .Storylet_Group:
		command.storylet_group = active_story_project.storylet_groups[index]
	case .Storylet:
		command.storylet = active_story_project.storylets[index]
	case .Invariant:
		command.invariant = active_story_project.invariants[index]
	case .Condition:
		command.condition = active_story_project.conditions[index]
	case .Effect:
		command.effect = active_story_project.effects[index]
	}
	return command, true
}

authoring_story_commit_commands :: proc(commands: []Story_Authoring_Command) -> string {
	result := story_authoring_apply(
		&active_story_project,
		&authoring_workspace.story_history,
		commands,
	)
	ok := result.ok; message := result.message; story_authoring_result_destroy(&result)
	if ok do graph_import_story(&active_story_project)
	return message
}

authoring_story_update_field :: proc(
	kind: Story_Authoring_Record_Kind,
	index: int,
	field, value: string,
) -> string {
	command, ok := authoring_story_selected_command(
		kind,
		index,
	); if !ok do return "NO SELECTED STORY RECORD"
	if (kind == .Fact || kind == .Proposition) && field == "canonical_truth" && !authoring_creator_truth_revealed do return "REVEAL CREATOR-ONLY TRUTH BEFORE EDITING"
	if field == "id" {
		if kind == .Knowledge do return "KNOWLEDGE ID IS ITS ACTOR / PROPOSITION PAIR"
		rename := Story_Authoring_Command {
			kind        = .Rename,
			record_kind = kind,
			id          = authoring_story_id(kind, index),
			new_id      = value,
		}; commands := [1]Story_Authoring_Command {
			rename,
		}; return authoring_story_commit_commands(commands[:])
	}
	int_value, int_ok := authoring_story_parse_int(
		value,
	); bool_value, bool_ok := authoring_story_parse_bool(value)
	#partial switch kind {
	case .Entity:
		r := &command.entity; switch field {case "kind":
			r.kind = value; case "display_name":
			r.display_name = value; case "description":
			r.description = value; case "spatial.space_id":
			r.spatial.space_id = value; case "spatial.target_kind":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.spatial.target_kind = Story_Spatial_Target_Kind(
				clamp(int_value, 0, int(Story_Spatial_Target_Kind.Entity)),
			); case "spatial.target_id":
			r.spatial.target_id = value; case "volume":
			if !int_ok do return "EXPECTED INTEGER"
			r.volume = int_value; case "container_capacity":
			if !int_ok do return "EXPECTED INTEGER"
			r.container_capacity = int_value; case "initially_locked":
			if !bool_ok do return "EXPECTED BOOLEAN"
			r.initially_locked = bool_value; case "owner_id":
			r.owner_id = value; case "initial_container_id":
			r.initial_container_id = value; case:
			return "UNKNOWN ENTITY FIELD"}
	case .Role:
		r := &command.role; switch field {case "display_name":
			r.display_name = value; case "description":
			r.description = value; case "minimum":
			if !int_ok do return "EXPECTED INTEGER"; r.minimum = int_value; case "maximum":
			if !int_ok do return "EXPECTED INTEGER"; r.maximum = int_value; case:
			return "UNKNOWN ROLE FIELD"}
	case .Variable:
		r := &command.variable; switch field {case "display_name":
			r.display_name = value; case "description":
			r.description = value; case "kind":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.kind = Story_Value_Kind(clamp(int_value, 0, int(Story_Value_Kind.Entity)))
			r.default_value.kind = r.kind; case "default_value.boolean":
			if !bool_ok do return "EXPECTED BOOLEAN"
			r.default_value.boolean_value = bool_value; case "default_value.integer":
			if !int_ok do return "EXPECTED INTEGER"
			r.default_value.integer_value = int_value; case "default_value.text":
			r.default_value.text_value = value; case "minimum":
			if !int_ok do return "EXPECTED INTEGER"; r.minimum = int_value; case "maximum":
			if !int_ok do return "EXPECTED INTEGER"; r.maximum = int_value; case:
			return "UNKNOWN VARIABLE FIELD"}
	case .Fact:
		r := &command.fact; switch field {case "display_name":
			r.display_name = value; case "proposition":
			r.proposition = value; case "variable_id":
			r.variable_id = value; case "canonical_truth":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.canonical_truth = Story_Truth(
				clamp(int_value, int(Story_Truth.Undetermined), int(Story_Truth.True)),
			); case "player_visible":
			if !bool_ok do return "EXPECTED BOOLEAN"; r.player_visible = bool_value; case:
			return "UNKNOWN FACT FIELD"}
	case .Proposition:
		r := &command.proposition; switch field {case "text":
			r.text = value; case "canonical_truth":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.canonical_truth = Story_Truth(
				clamp(int_value, int(Story_Truth.Undetermined), int(Story_Truth.True)),
			); case:
			return "UNKNOWN PROPOSITION FIELD"}
	case .Knowledge:
		// Pair members are the stable key in StoryCore; use create/remove to change them.
		if field == "actor_id" || field == "proposition_id" do return "KNOWLEDGE KEY FIELDS REQUIRE CREATE / REMOVE"
		if field != "stance" || !int_ok do return "UNKNOWN KNOWLEDGE FIELD OR EXPECTED ENUM NUMBER"
		command.knowledge.stance = Story_Belief_Stance(
			clamp(int_value, 0, int(Story_Belief_Stance.Disbelieves)),
		)
	case .Relationship:
		r := &command.relationship; switch field {case "source_id":
			r.source_id = value; case "target_id":
			r.target_id = value; case "kind":
			r.kind = value; case "variable_id":
			r.variable_id = value; case:
			return "UNKNOWN RELATIONSHIP FIELD"}
	case .Event:
		r := &command.event; switch field {case "subject_id":
			r.subject_id = value; case "action":
			r.action = value; case "object_id":
			r.object_id = value; case "location_id":
			r.location_id = value; case "fictional_time":
			r.fictional_time = value; case "provenance":
			r.provenance = value; case:
			return "UNKNOWN EVENT FIELD"}
	case .Objective:
		r := &command.objective; switch field {case "display_name":
			r.display_name = value; case "description":
			r.description = value; case "hidden":
			if !bool_ok do return "EXPECTED BOOLEAN"; r.hidden = bool_value; case "initial_status":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.initial_status = Story_Objective_Status(
				clamp(int_value, 0, int(Story_Objective_Status.Failed)),
			); case "stage_count":
			if !int_ok do return "EXPECTED INTEGER"
			r.stage_count = int_value; case "completion_condition_id":
			r.completion_condition_id = value; case "failure_condition_id":
			r.failure_condition_id = value; case "completion_condition":
			if !int_ok do return "EXPECTED INTEGER"
			r.completion_condition = int_value; case "failure_condition":
			if !int_ok do return "EXPECTED INTEGER"; r.failure_condition = int_value; case:
			return "UNKNOWN OBJECTIVE FIELD"}
	case .Ending:
		r := &command.ending; switch field {case "title":
			r.title = value; case "summary":
			r.summary = value; case "condition_id":
			r.condition_id = value; case "condition_root":
			if !int_ok do return "EXPECTED INTEGER"; r.condition_root = int_value; case "priority":
			if !int_ok do return "EXPECTED INTEGER"; r.priority = int_value; case:
			return "UNKNOWN ENDING FIELD"}
	case .Storylet_Group:
		r := &command.storylet_group; switch field {case "allow_empty":
			if !bool_ok do return "EXPECTED BOOLEAN"
			r.allow_empty = bool_value; case "seeded_random_ties":
			if !bool_ok do return "EXPECTED BOOLEAN"; r.seeded_random_ties = bool_value; case:
			return "UNKNOWN STORYLET GROUP FIELD"}
	case .Storylet:
		r := &command.storylet; switch field {case "group":
			r.group = value; case "scene_id":
			r.scene_id = value; case "dramatic_priority":
			if !int_ok do return "EXPECTED INTEGER"
			r.dramatic_priority = int_value; case "specificity":
			if !int_ok do return "EXPECTED INTEGER"; r.specificity = int_value; case "cooldown":
			if !int_ok do return "EXPECTED INTEGER"; r.cooldown = int_value; case "authored_order":
			if !int_ok do return "EXPECTED INTEGER"
			r.authored_order = int_value; case "repeat_policy":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.repeat_policy = Story_Repeat_Policy(
				clamp(int_value, 0, int(Story_Repeat_Policy.Once)),
			); case "fallback":
			if !bool_ok do return "EXPECTED BOOLEAN"; r.fallback = bool_value; case:
			return "UNKNOWN STORYLET FIELD"}
	case .Invariant:
		r := &command.invariant; switch field {case "description":
			r.description = value; case "condition_id":
			r.condition_id = value; case "kind":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.kind = Story_Invariant_Kind(
				clamp(int_value, 0, int(Story_Invariant_Kind.Always)),
			); case "condition_root":
			if !int_ok do return "EXPECTED INTEGER"; r.condition_root = int_value; case "required":
			if !bool_ok do return "EXPECTED BOOLEAN"; r.required = bool_value; case:
			return "UNKNOWN INVARIANT FIELD"}
	case .Condition:
		r := &command.condition; switch field {case "kind":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.kind = Story_Condition_Kind(
				clamp(int_value, 0, int(Story_Condition_Kind.Capability_State)),
			); case "first_child":
			if !int_ok do return "EXPECTED INTEGER"; r.first_child = int_value; case "child_count":
			if !int_ok do return "EXPECTED INTEGER"; r.child_count = int_value; case "variable_id":
			r.variable_id = value; case "entity_id":
			r.entity_id = value; case "other_entity_id":
			r.other_entity_id = value; case "proposition_id":
			r.proposition_id = value; case "objective_id":
			r.objective_id = value; case "event_id":
			r.event_id = value; case "content_id":
			r.content_id = value; case "text_value":
			r.text_value = value; case "value.kind":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.value.kind = Story_Value_Kind(
				clamp(int_value, 0, int(Story_Value_Kind.Entity)),
			); case "value.boolean":
			if !bool_ok do return "EXPECTED BOOLEAN"
			r.value.boolean_value = bool_value; case "value.integer":
			if !int_ok do return "EXPECTED INTEGER"
			r.value.integer_value = int_value; case "value.text":
			r.value.text_value = value; case "comparison":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.comparison = Story_Integer_Comparison(
				clamp(int_value, 0, int(Story_Integer_Comparison.Greater_Equal)),
			); case "objective_status":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.objective_status = Story_Objective_Status(
				clamp(int_value, 0, int(Story_Objective_Status.Failed)),
			); case "belief_stance":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.belief_stance = Story_Belief_Stance(
				clamp(int_value, 0, int(Story_Belief_Stance.Disbelieves)),
			); case "spatial_a.space_id":
			r.spatial_a.space_id = value; case "spatial_a.target_id":
			r.spatial_a.target_id = value; case "spatial_b.space_id":
			r.spatial_b.space_id = value; case "spatial_b.target_id":
			r.spatial_b.target_id = value; case "distance":
			parsed, pok := strconv.parse_f32(strings.trim_space(value))
			if !pok do return "EXPECTED NUMBER"
			r.distance = parsed; case:
			return "UNKNOWN CONDITION FIELD"}
	case .Effect:
		r := &command.effect; switch field {case "kind":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.kind = Story_Effect_Kind(
				clamp(int_value, 0, int(Story_Effect_Kind.Spatial_Command)),
			); case "variable_id":
			r.variable_id = value; case "actor_id":
			r.actor_id = value; case "other_actor_id":
			r.other_actor_id = value; case "proposition_id":
			r.proposition_id = value; case "objective_id":
			r.objective_id = value; case "event_id":
			r.event_id = value; case "content_id":
			r.content_id = value; case "world_id":
			r.world_id = value; case "value.kind":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.value.kind = Story_Value_Kind(
				clamp(int_value, 0, int(Story_Value_Kind.Entity)),
			); case "value.boolean":
			if !bool_ok do return "EXPECTED BOOLEAN"
			r.value.boolean_value = bool_value; case "value.integer":
			if !int_ok do return "EXPECTED INTEGER"
			r.value.integer_value = int_value; case "value.text":
			r.value.text_value = value; case "belief_stance":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.belief_stance = Story_Belief_Stance(
				clamp(int_value, 0, int(Story_Belief_Stance.Disbelieves)),
			); case "objective_status":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.objective_status = Story_Objective_Status(
				clamp(int_value, 0, int(Story_Objective_Status.Failed)),
			); case "spatial_command":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.spatial_command = Story_Spatial_Command_Kind(
				clamp(int_value, 0, int(Story_Spatial_Command_Kind.Set_Interaction)),
			); case "spatial_target.space_id":
			r.spatial_target.space_id = value; case "spatial_target.target_id":
			r.spatial_target.target_id = value; case "spatial_destination.space_id":
			r.spatial_destination.space_id = value; case "spatial_destination.target_id":
			r.spatial_destination.target_id = value; case "world_enabled":
			if !bool_ok do return "EXPECTED BOOLEAN"; r.world_enabled = bool_value; case:
			return "UNKNOWN EFFECT FIELD"}
	}
	commands := [1]Story_Authoring_Command {
		command,
	}; return authoring_story_commit_commands(commands[:])
}

authoring_story_list_strings :: proc(
	values: ^[$N]string,
	count: ^int,
	edit: Story_List_Edit,
	at: int,
	value: string,
) -> bool {
	if edit ==
	   .Add {if count^ >= N do return false; insert := clamp(at, 0, count^); for i := count^; i > insert; i -= 1 do values[i] = values[i - 1]; values[insert] = value; count^ += 1; return true}
	if at < 0 || at >= count^ do return false
	if edit ==
	   .Remove {for i in at + 1 ..< count^ do values[i - 1] = values[i]; count^ -= 1; values[count^] = ""; return true}
	to :=
		edit == .Move_Up ? at - 1 : at + 1; if to < 0 || to >= count^ do return false; values[at], values[to] = values[to], values[at]; return true
}

authoring_story_update_list :: proc(
	kind: Story_Authoring_Record_Kind,
	index: int,
	field: string,
	edit: Story_List_Edit,
	at: int,
	value: string = "",
) -> string {
	command, ok := authoring_story_selected_command(
		kind,
		index,
	); if !ok do return "NO SELECTED STORY RECORD"
	changed := false
	#partial switch kind {
	case .Entity:
		if field == "tags" do changed = authoring_story_list_strings(&command.entity.tags, &command.entity.tag_count, edit, at, value)
		else if field == "roles" do changed = authoring_story_list_strings(&command.entity.roles, &command.entity.role_count, edit, at, value)
	case .Variable:
		if field == "enum_values" do changed = authoring_story_list_strings(&command.variable.enum_values, &command.variable.enum_value_count, edit, at, value)
	case .Event:
		if field == "witnesses" do changed = authoring_story_list_strings(&command.event.witnesses, &command.event.witness_count, edit, at, value)
	case .Condition:
		if field == "child_ids" do changed = authoring_story_list_strings(&command.condition.child_ids, &command.condition.child_id_count, edit, at, value)
	case .Storylet:
		if field == "condition_ids" do changed = authoring_story_list_strings(&command.storylet.condition_ids, &command.storylet.condition_count, edit, at, value)
		else if field == "effect_ids" do changed = authoring_story_list_strings(&command.storylet.effect_ids, &command.storylet.effect_count, edit, at, value)
	case:
	}
	if !changed do return "UNKNOWN, FULL, OR INVALID STORY LIST EDIT"
	commands := [1]Story_Authoring_Command {
		command,
	}; return authoring_story_commit_commands(commands[:])
}

authoring_story_create_reference_command :: proc(
	kind: Story_Authoring_Record_Kind,
	id: string,
) -> (
	Story_Authoring_Command,
	bool,
) {
	c := Story_Authoring_Command {
		kind        = .Add,
		record_kind = kind,
	}; #partial switch kind {case .Entity:
		c.entity = {
			id           = id,
			kind         = "person",
			display_name = id,
		}; case .Role:
		c.role = {
			id           = id,
			display_name = id,
		}; case .Variable:
		c.variable = {
			id = id,
			display_name = id,
			kind = .Boolean,
			default_value = {kind = .Boolean},
		}; case .Proposition:
		c.proposition = {
			id   = id,
			text = id,
		}; case .Condition:
		c.condition = {
			id   = id,
			kind = .Always,
		}; case .Effect:
		c.effect = {
			id         = id,
			kind       = .Complete_Scene,
			content_id = id,
		}; case:
		return c, false}; return c, true
}

// Picker convenience: create a missing selectable record and add its id to a
// fixed-capacity list in one validation/undo transaction.
authoring_story_list_create_in_picker :: proc(
	owner_kind: Story_Authoring_Record_Kind,
	owner_index: int,
	field: string,
	at: int,
	reference_kind: Story_Authoring_Record_Kind,
	id: string,
) -> string {
	if story_authoring_record_exists(&active_story_project, reference_kind, id) do return authoring_story_update_list(owner_kind, owner_index, field, .Add, at, id)
	create, ok := authoring_story_create_reference_command(
		reference_kind,
		id,
	); if !ok do return "REFERENCE KIND CANNOT BE CREATED IN THIS PICKER"
	update, found := authoring_story_selected_command(
		owner_kind,
		owner_index,
	); if !found do return "NO SELECTED STORY RECORD"
	changed := false; #partial switch owner_kind {case .Entity:
		if field == "roles" do changed = authoring_story_list_strings(&update.entity.roles, &update.entity.role_count, .Add, at, id); case .Event:
		if field == "witnesses" do changed = authoring_story_list_strings(&update.event.witnesses, &update.event.witness_count, .Add, at, id); case .Condition:
		if field == "child_ids" do changed = authoring_story_list_strings(&update.condition.child_ids, &update.condition.child_id_count, .Add, at, id); case .Storylet:
		if field == "condition_ids" do changed = authoring_story_list_strings(&update.storylet.condition_ids, &update.storylet.condition_count, .Add, at, id)
		else if field == "effect_ids" do changed = authoring_story_list_strings(&update.storylet.effect_ids, &update.storylet.effect_count, .Add, at, id); case:}
	if !changed do return "PICKER DOES NOT ACCEPT THAT REFERENCE KIND"
	commands := [2]Story_Authoring_Command {
		create,
		update,
	}; return authoring_story_commit_commands(commands[:])
}

authoring_story_scalar_field :: proc(
	kind: Story_Authoring_Record_Kind,
	cursor: int,
) -> (
	string,
	int,
) {
	#partial switch kind {
	case .Entity:
		items := [12]string {
			"id",
			"kind",
			"display_name",
			"description",
			"spatial.space_id",
			"spatial.target_kind",
			"spatial.target_id",
			"volume",
			"container_capacity",
			"initially_locked",
			"owner_id",
			"initial_container_id",
		}
		return items[cursor % len(items)], len(items)
	case .Role:
		items := [5]string{"id", "display_name", "description", "minimum", "maximum"}
		return items[cursor % len(items)], len(items)
	case .Variable:
		items := [9]string {
			"id",
			"display_name",
			"description",
			"kind",
			"default_value.boolean",
			"default_value.integer",
			"default_value.text",
			"minimum",
			"maximum",
		}
		return items[cursor % len(items)], len(items)
	case .Fact:
		items := [6]string {
			"id",
			"display_name",
			"proposition",
			"variable_id",
			"canonical_truth",
			"player_visible",
		}
		return items[cursor % len(items)], len(items)
	case .Proposition:
		items := [3]string{"id", "text", "canonical_truth"}
		return items[cursor % len(items)], len(items)
	case .Knowledge:
		items := [3]string{"actor_id", "proposition_id", "stance"}
		return items[cursor % len(items)], len(items)
	case .Relationship:
		items := [5]string{"id", "source_id", "target_id", "kind", "variable_id"}
		return items[cursor % len(items)], len(items)
	case .Event:
		items := [7]string {
			"id",
			"subject_id",
			"action",
			"object_id",
			"location_id",
			"fictional_time",
			"provenance",
		}
		return items[cursor % len(items)], len(items)
	case .Objective:
		items := [10]string {
			"id",
			"display_name",
			"description",
			"hidden",
			"initial_status",
			"stage_count",
			"completion_condition_id",
			"failure_condition_id",
			"completion_condition",
			"failure_condition",
		}
		return items[cursor % len(items)], len(items)
	case .Ending:
		items := [6]string{"id", "title", "summary", "condition_id", "condition_root", "priority"}
		return items[cursor % len(items)], len(items)
	case .Storylet_Group:
		items := [3]string{"id", "allow_empty", "seeded_random_ties"}
		return items[cursor % len(items)], len(items)
	case .Storylet:
		items := [9]string {
			"id",
			"group",
			"scene_id",
			"dramatic_priority",
			"specificity",
			"cooldown",
			"authored_order",
			"repeat_policy",
			"fallback",
		}
		return items[cursor % len(items)], len(items)
	case .Invariant:
		items := [6]string {
			"id",
			"description",
			"condition_id",
			"kind",
			"condition_root",
			"required",
		}
		return items[cursor % len(items)], len(items)
	case .Condition:
		items := [24]string {
			"id",
			"kind",
			"first_child",
			"child_count",
			"variable_id",
			"entity_id",
			"other_entity_id",
			"proposition_id",
			"objective_id",
			"event_id",
			"content_id",
			"text_value",
			"value.kind",
			"value.boolean",
			"value.integer",
			"value.text",
			"comparison",
			"objective_status",
			"belief_stance",
			"spatial_a.space_id",
			"spatial_a.target_id",
			"spatial_b.space_id",
			"spatial_b.target_id",
			"distance",
		}
		return items[cursor % len(items)], len(items)
	case .Effect:
		items := [22]string {
			"id",
			"kind",
			"variable_id",
			"actor_id",
			"other_actor_id",
			"proposition_id",
			"objective_id",
			"event_id",
			"content_id",
			"world_id",
			"value.kind",
			"value.boolean",
			"value.integer",
			"value.text",
			"belief_stance",
			"objective_status",
			"spatial_command",
			"spatial_target.space_id",
			"spatial_target.target_id",
			"spatial_destination.space_id",
			"spatial_destination.target_id",
			"world_enabled",
		}
		return items[cursor % len(items)], len(items)
	}
	return "", 0
}

authoring_story_list_field :: proc(
	kind: Story_Authoring_Record_Kind,
	cursor: int,
) -> (
	string,
	int,
) {#partial switch kind {case .Entity:
		items := [2]string{"tags", "roles"}; return items[cursor % 2], 2; case .Variable:
		return "enum_values", 1; case .Event:
		return "witnesses", 1; case .Condition:
		return "child_ids", 1; case .Storylet:
		items := [2]string{"condition_ids", "effect_ids"}
		return items[cursor % 2], 2}; return "", 0}
authoring_story_list_count :: proc(
	kind: Story_Authoring_Record_Kind,
	index: int,
	field: string,
) -> int {if index < 0 || index >= authoring_story_count(kind) do return 0; #partial switch
	kind {case .Entity:
		return(
			field == "tags" ? active_story_project.entities[index].tag_count : active_story_project.entities[index].role_count \
		); case .Variable:
		return active_story_project.variables[index].enum_value_count; case .Event:
		return active_story_project.events[index].witness_count; case .Condition:
		return active_story_project.conditions[index].child_id_count; case .Storylet:
		return(
			field == "condition_ids" ? active_story_project.storylets[index].condition_count : active_story_project.storylets[index].effect_count \
		)}
	return 0}
authoring_story_begin_form :: proc(
	action: Authoring_Form_Action,
) {authoring_workspace.form_active = true; authoring_workspace.form_action = action
	authoring_workspace.form_count = 0}

// Mystery descriptors use a one-byte editor type: t=text, n=number, b=toggle.
authoring_mystery_scalar_field :: proc(
	kind: Mystery_Authoring_Record_Kind,
	cursor: int,
) -> (
	string,
	u8,
	int,
) {#partial switch kind {
	case .Setup:
		a := [6]string {
			"action_budget",
			"seed",
			"tutorial_id",
			"city_start",
			"city_destination",
			"reveal_location",
		}
		types := [6]u8{'n', 'n', 't', 't', 't', 't'}
		i := cursor % 6
		return a[i], types[i], 6
	case .Character:
		a := [3]string{"private_secret", "motive", "initial_disposition"}; i := cursor % 3
		return a[i], i == 2 ? 'n' : 't', 3
	case .Location:
		return "id (rename)", 't', 1
	case .POI:
		a := [4]string{"location_id", "owner_id", "relevant_state", "examination_action"}
		return a[cursor % 4], 't', 4
	case .Event:
		a := [2]string{"destination_id", "tool_id"}; return a[cursor % 2], 't', 2
	case .Clue:
		a := [8]string {
			"source_id",
			"description",
			"proposition_id",
			"skill",
			"check_kind",
			"difficulty",
			"cost",
			"essential",
		}
		types := [8]u8{'t', 't', 't', 't', 't', 'n', 'n', 'b'}
		i := cursor % 8
		return a[i], types[i], 8
	case .Claim:
		a := [5]string{"speaker_id", "proposition_id", "protects", "response", "canonical_truth"}
		i := cursor % 5
		return a[i], i == 4 ? 'b' : 't', 5
	case .Contradiction:
		a := [4]string{"claim_id", "fact_id", "conclusion_id", "explanation"}
		return a[cursor % 4], 't', 4
	case .Deduction:
		a := [2]string{"proposition_id", "category"}; return a[cursor % 2], 't', 2
	case .Question:
		a := [4]string{"prompt", "hypothesis_id", "category", "required_for_final"}
		i := cursor % 4
		return a[i], i == 3 ? 'b' : 't', 4
	case .Demonstration:
		a := [12]string {
			"question_id",
			"mode",
			"presentation",
			"gesture",
			"subject",
			"art",
			"completion_cue",
			"candidate_limit",
			"resolution",
			"result",
			"prompt",
			"routes",
		}
		i := cursor % 12
		return a[i], i == 7 ? 'n' : 't', 12
	case .Dialogue:
		a := [5]string{"character_id", "prompt", "response", "clue_id", "interaction"}
		return a[cursor % 5], 't', 5
	case .Ending:
		a := [10]string {
			"trigger",
			"outcome",
			"subtitle",
			"epilogue",
			"canonical_timeline",
			"tone",
			"primary_label",
			"primary_action",
			"secondary_label",
			"secondary_action",
		}
		return a[cursor % 10], 't', 10
	case .City_Label:
		a := [3]string{"display_name", "level_spawn", "city_site"}; return a[cursor % 3], 't', 3
	case .Tutorial_Lesson:
		a := [2]string{"capability", "prompt"}; return a[cursor % 2], 't', 2
	case .Solution:
		a := [10]string {
			"culprit_id",
			"motive_id",
			"decisive_contradiction_id",
			"weapon_block",
			"murder_place_block",
			"death_time_block",
			"body_movement_block",
			"staging_block",
			"cleaning_block",
			"alibi_block",
		}
		return a[cursor % 10], 't', 10
	}; return "", 't', 0}

authoring_mystery_list_field :: proc(
	kind: Mystery_Authoring_Record_Kind,
	cursor: int,
) -> (
	string,
	int,
) {#partial switch kind {case .Character:
		return "initial_claims", 1; case .Location:
		a := [4]string{"connections", "characters", "pois", "search_actions"}
		return a[cursor % 4], 4; case .Event:
		return "effects", 1; case .Clue:
		a := [3]string{"prerequisites", "blocks", "topics"}
		return a[cursor % 3], 3; case .Deduction:
		a := [4]string{"supports", "unlock_questions", "unlock_topics", "unlock_investigations"}
		return a[cursor % 4], 4; case .Question:
		a := [4]string{"requires_clues", "requires_claims", "requires_deductions", "dependencies"}
		return a[cursor % 4], 4; case .Demonstration:
		a := [5]string {
			"gesture_steps",
			"slot_labels",
			"slot_types",
			"accepted",
			"result_deductions",
		}
		return a[cursor % 5], 5; case .Dialogue:
		a := [2]string{"requires", "unlocks"}; return a[cursor % 2], 2; case .Solution:
		a := [5]string {
			"requirements",
			"murder_events",
			"cover_up_events",
			"false_alibis",
			"exclusions",
		}
		return a[cursor % 5], 5}; return "", 0}

authoring_mystery_selected_list_count :: proc(field: string) -> int {c, ok :=
		authoring_mystery_selected_update()
	if !ok do return 0
	#partial switch
	c.record_kind {case .Character:
		return c.character.initial_claim_count; case .Location:
		if field == "connections" do return c.location.connection_count
		if field == "characters" do return c.location.character_count
		if field == "pois" do return c.location.poi_count
		return c.location.search_action_count; case .Event:
		return c.event.effect_count; case .Clue:
		if field == "prerequisites" do return c.clue.prerequisite_count
		if field == "blocks" do return c.clue.block_count
		return c.clue.topic_count; case .Deduction:
		if field == "supports" do return c.deduction.support_count
		if field == "unlock_questions" do return c.deduction.unlock_question_count
		if field == "unlock_topics" do return c.deduction.unlock_topic_count
		return c.deduction.unlock_investigation_count; case .Question:
		if field == "requires_clues" do return c.question.require_clue_count
		if field == "requires_claims" do return c.question.require_claim_count
		if field == "requires_deductions" do return c.question.require_deduction_count
		return c.question.dependency_count; case .Demonstration:
		if field == "gesture_steps" do return c.demonstration.gesture_step_count
		if field == "slot_labels" || field == "slot_types" do return c.demonstration.slot_count
		if field == "accepted" do return c.demonstration.accepted_count
		return c.demonstration.result_count; case .Dialogue:
		return(
			field == "requires" ? c.dialogue.require_count : c.dialogue.unlock_count \
		); case .Solution:
		if field == "requirements" do return c.solution.requirement_count; if field == "murder_events" do return c.solution.murder_event_count
		if field == "cover_up_events" do return c.solution.cover_up_event_count
		if field == "false_alibis" do return c.solution.false_alibi_count
		return c.solution.exclusion_count}
	return 0}
