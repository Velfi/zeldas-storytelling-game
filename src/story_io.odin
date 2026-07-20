package main

import "core:fmt"
import "core:os"
import "core:strings"

STORY_BLANK_PROOF_PATH :: "assets/stories/the_lantern_visit.story.toml"

story_value_kind_from_text :: proc(value: string) -> (Story_Value_Kind, bool) {switch
	value {case "boolean":
		return .Boolean, true; case "integer":
		return .Integer, true; case "enum":
		return .Enumeration, true; case "entity":
		return .Entity, true}
	return .Boolean, false}
story_value_kind_text :: proc(value: Story_Value_Kind) -> string {switch value {case .Boolean:
		return "boolean"; case .Integer:
		return "integer"; case .Enumeration:
		return "enum"; case .Entity:
		return "entity"}; return "boolean"}
story_truth_from_text :: proc(value: string) -> Story_Truth {switch value {case "true":
		return .True; case "false":
		return .False}; return .Undetermined}
story_belief_from_text :: proc(value: string) -> Story_Belief_Stance {switch
	value {case "believes":
		return .Believes; case "disbelieves":
		return .Disbelieves}
	return .Uncertain}
story_repeat_from_text :: proc(value: string) -> Story_Repeat_Policy {switch value {case "once":
		return .Once; case "cooldown":
		return .Cooldown}; return .Always}
story_belief_text :: proc(value: Story_Belief_Stance) -> string {switch value {case .Believes:
		return "believes"; case .Disbelieves:
		return "disbelieves"; case .Uncertain:
		return "uncertain"}; return "uncertain"}
story_repeat_text :: proc(value: Story_Repeat_Policy) -> string {switch value {case .Once:
		return "once"; case .Cooldown:
		return "cooldown"; case .Always:
		return "always"}; return "always"}
story_truth_text :: proc(value: Story_Truth) -> string {switch value {case .True:
		return "true"; case .False:
		return "false"; case .Undetermined:
		return "undetermined"}; return "undetermined"}
story_spatial_target_kind_from_text :: proc(value: string) -> Story_Spatial_Target_Kind {switch
	value {case "marker":
		return .Marker; case "room":
		return .Room; case "interaction":
		return .Interaction; case "transition":
		return .Transition}
	return .Entity}
story_spatial_target_kind_text :: proc(value: Story_Spatial_Target_Kind) -> string {switch
	value {case .Entity:
		return "entity"; case .Marker:
		return "marker"; case .Room:
		return "room"; case .Interaction:
		return "interaction"; case .Transition:
		return "transition"}
	return "entity"}
story_spatial_command_from_text :: proc(value: string) -> Story_Spatial_Command_Kind {switch
	value {case "set_visible":
		return .Set_Visible; case "move":
		return .Move; case "spawn":
		return .Spawn; case "despawn":
		return .Despawn; case "set_access":
		return .Set_Access}
	return .Set_Interaction}
story_spatial_command_text :: proc(value: Story_Spatial_Command_Kind) -> string {switch
	value {case .Set_Interaction:
		return "set_interaction"; case .Set_Visible:
		return "set_visible"; case .Move:
		return "move"; case .Spawn:
		return "spawn"; case .Despawn:
		return "despawn"; case .Set_Access:
		return "set_access"}
	return "set_interaction"}
story_node_kind_from_text :: proc(value: string) -> (Story_Node_Kind, bool) {switch
	value {case "line":
		return .Line, true; case "choice":
		return .Choice, true; case "check":
		return .Check, true; case "stage":
		return .Stage, true; case "interaction":
		return .Interaction, true; case "effect":
		return .Effect, true; case "selector":
		return .Selector, true; case "objective":
		return .Objective, true; case "wait_event":
		return .Wait_Event, true; case "subscene":
		return .Subscene, true; case "end":
		return .End, true}
	return .Line, false}
story_node_kind_text :: proc(value: Story_Node_Kind) -> string {switch value {case .Line:
		return "line"; case .Choice:
		return "choice"; case .Check:
		return "check"; case .Stage:
		return "stage"; case .Interaction:
		return "interaction"; case .Effect:
		return "effect"; case .Selector:
		return "selector"; case .Objective:
		return "objective"; case .Wait_Event:
		return "wait_event"; case .Subscene:
		return "subscene"; case .End:
		return "end"}; return "line"}
story_invariant_kind_from_text :: proc(value: string) -> (Story_Invariant_Kind, bool) {switch
	value {case "always":
		return .Always, true; case "never":
		return .Never, true; case "reachable":
		return .Reachable, true; case "eventually":
		return .Eventually, true}
	return .Always, false}
story_invariant_kind_text :: proc(value: Story_Invariant_Kind) -> string {switch
	value {case .Always:
		return "always"; case .Never:
		return "never"; case .Reachable:
		return "reachable"; case .Eventually:
		return "eventually"}
	return "always"}

story_condition_kind_text :: proc(value: Story_Condition_Kind) -> string {switch
	value {case .Always:
		return "always"; case .Never:
		return "never"; case .All:
		return "all"; case .Any:
		return "any"; case .Not:
		return "not"; case .Value_Equals:
		return "value_equals"; case .Integer_Compare:
		return "integer_compare"; case .Entity_Has_Tag:
		return "entity_has_tag"; case .Entity_Has_Role:
		return "entity_has_role"; case .Aware:
		return "aware"; case .Unaware:
		return "unaware"; case .Belief_Equals:
		return "belief_equals"; case .Communicated:
		return "communicated"; case .Objective_Equals:
		return "objective_equals"; case .Event_Occurred:
		return "event_occurred"; case .Scene_Completed:
		return "scene_completed"; case .Storylet_Seen:
		return "storylet_seen"; case .Spatial_Present:
		return "spatial_present"; case .Spatial_Contained_By:
		return "spatial_contained_by"; case .Spatial_Distance:
		return "spatial_distance"; case .Spatial_Visible:
		return "spatial_visible"; case .Spatial_Reachable:
		return "spatial_reachable"; case .Spatial_Travel_Time:
		return "spatial_travel_time"; case .Capability_State:
		return "capability_state"}
	return "never"}
story_effect_kind_text :: proc(value: Story_Effect_Kind) -> string {switch value {case .Set_Value:
		return "set_value"; case .Add_Integer:
		return "add_integer"; case .Make_Aware:
		return "make_aware"; case .Set_Belief:
		return "set_belief"; case .Communicate:
		return "communicate"; case .Set_Objective:
		return "set_objective"; case .Emit_Event:
		return "emit_event"; case .Complete_Scene:
		return "complete_scene"; case .Mark_Storylet:
		return "mark_storylet"; case .Spatial_Command:
		return "spatial_command"}; return "set_value"}

story_condition_kind_from_text :: proc(value: string) -> (Story_Condition_Kind, bool) {
	switch value {
	case "always":
		return .Always, true; case "never":
		return .Never, true; case "all":
		return .All, true; case "any":
		return .Any, true; case "not":
		return .Not, true
	case "value_equals":
		return .Value_Equals, true; case "integer_compare":
		return .Integer_Compare, true; case "entity_has_tag":
		return .Entity_Has_Tag, true; case "entity_has_role":
		return .Entity_Has_Role, true
	case "aware":
		return .Aware, true; case "unaware":
		return .Unaware, true; case "belief_equals":
		return .Belief_Equals, true; case "communicated":
		return .Communicated, true
	case "objective_equals":
		return .Objective_Equals, true; case "event_occurred":
		return .Event_Occurred, true; case "scene_completed":
		return .Scene_Completed, true; case "storylet_seen":
		return .Storylet_Seen, true
	case "spatial_present":
		return .Spatial_Present, true; case "spatial_contained_by":
		return .Spatial_Contained_By, true; case "spatial_distance":
		return .Spatial_Distance, true; case "spatial_visible":
		return .Spatial_Visible, true; case "spatial_reachable":
		return .Spatial_Reachable, true; case "spatial_travel_time":
		return .Spatial_Travel_Time, true; case "capability_state":
		return .Capability_State, true
	}; return .Never, false
}

story_effect_kind_from_text :: proc(value: string) -> (Story_Effect_Kind, bool) {
	switch value {case "set_value":
		return .Set_Value, true; case "add_integer":
		return .Add_Integer, true; case "make_aware":
		return .Make_Aware, true; case "set_belief":
		return .Set_Belief, true; case "communicate":
		return .Communicate, true; case "set_objective":
		return .Set_Objective, true; case "emit_event":
		return .Emit_Event, true; case "complete_scene":
		return .Complete_Scene, true; case "mark_storylet":
		return .Mark_Storylet, true; case "spatial_command", "set_world_interaction":
		return .Spatial_Command, true}; return .Set_Value, false
}

story_toml_value :: proc(table: Toml_Datum, kind: Story_Value_Kind) -> Story_Value {
	switch kind {case .Boolean:
		return story_value_boolean(toml_case_bool(table, "boolean_value")); case .Integer:
		return story_value_integer(
			toml_case_int(table, "integer_value"),
		); case .Enumeration, .Entity:
		return story_value_text(kind, toml_case_string(table, "text_value"))}
	return {}
}

story_copy_strings :: proc(target: ^[STORY_MAX_TAGS]string, values: []string) -> int {count := min(
		len(values),
		len(target^),
	)
	for item, i in values do if i < count do target[i] = item
	return count}

load_story_project :: proc(path: string, out: ^Story_Project) -> Validation {
	cpath, err := strings.clone_to_cstring(
		path,
		context.temp_allocator,
	); if err != nil do return {false, "invalid story path"}
	parsed := toml_parse_file_ex(
		cpath,
	); defer toml_free(parsed); if !parsed.ok do return toml_parse_diagnostic(path, "interactive story", &parsed)
	top :=
		parsed.toptab; legacy_domain := toml_case_string(top, "domain"); legacy_domain_version := toml_case_string(top, "domain_version")
	if legacy_domain != "" || legacy_domain_version != "" do return {false, "legacy domain/domain_version fields are not supported; regenerate or migrate this InteractiveStory v1 source to capability requirements"}
	project := Story_Project {
		version          = toml_case_string(top, "version"),
		id               = toml_case_string(top, "id"),
		title            = toml_case_string(top, "title"),
		creator          = toml_case_string(top, "creator"),
		description      = toml_case_string(top, "description"),
		content_version  = toml_case_string(top, "content_version"),
		default_space_id = toml_case_string(top, "default_space"),
		revision         = u64(toml_case_int(top, "revision")),
	}; if project.default_space_id == "" do project.default_space_id = "level"
	if project.version != STORY_PROJECT_VERSION do return toml_diagnostic(path, "obsolete or unsupported story format", 1)
	for table in toml_tables(top, "capabilities") do append(&project.capabilities, Story_Capability_Requirement{id = toml_case_string(table, "id"), version = toml_case_string(table, "version")})
	for table in toml_tables(
		top,
		"expansions",
	) {distribution := Story_Expansion_Distribution.Reference; if strings.to_lower(toml_case_string(table, "distribution")) == "embed" do distribution = .Embed; fallback := Story_Expansion_Fallback.None; if strings.to_lower(toml_case_string(table, "fallback")) == "omit" do fallback = .Omit; append(&project.expansion_requirements, Story_Expansion_Requirement{id = toml_case_string(table, "id"), version = toml_case_string(table, "version"), optional = toml_case_bool(table, "optional"), distribution = distribution, fallback = fallback})}
	project.ui_font_asset_ref = toml_case_string(top, "ui_font_asset_ref")
	for table in toml_tables(top, "entities") {item := Story_Entity {
			id                         = toml_case_string(table, "id"),
			kind                       = toml_case_string(table, "kind"),
			display_name               = toml_case_string(table, "display_name"),
			description                = toml_case_string(table, "description"),
			appearance_model_asset_ref = toml_case_string(table, "appearance_model_asset_ref"),
			default_animation          = toml_case_string(table, "default_animation"),
			animation_phase            = toml_case_float(table, "animation_phase"),
			presentation_facing        = toml_case_float(table, "presentation_facing"),
			visibility_condition_id    = toml_case_string(table, "visibility_condition_id"),
			availability_condition_id  = toml_case_string(table, "availability_condition_id"),
			completion_condition_id    = toml_case_string(table, "completion_condition_id"),
			interaction_scene_id       = toml_case_string(table, "interaction_scene_id"),
			interaction_prompt         = toml_case_string(table, "interaction_prompt"),
			unavailable_prompt         = toml_case_string(table, "unavailable_prompt"),
			completion_prompt          = toml_case_string(table, "completion_prompt"),
			volume                     = toml_case_int(table, "volume"),
			container_capacity         = toml_case_int(table, "container_capacity"),
			initially_locked           = toml_case_bool(table, "locked"),
			owner_id                   = toml_case_string(table, "owner"),
			initial_container_id       = toml_case_string(table, "contained_by"),
		}; tint := toml_case_ints(
			table,
			"presentation_tint",
		); item.presentation_tint = {255, 255, 255, 255}; for value, i in tint do if i < 4 do item.presentation_tint[i] = u8(clamp(value, 0, 255)); item.spatial = {
			space_id    = toml_case_string(table, "space_id"),
			target_kind = story_spatial_target_kind_from_text(
				toml_case_string(table, "target_kind"),
			),
			target_id   = toml_case_string(table, "target_id"),
		}; if item.spatial.target_id ==
		   "" {item.spatial.target_id = toml_case_string(table, "world_binding"); item.spatial.space_id = project.default_space_id}; tags := toml_case_strings(table, "tags"); roles := toml_case_strings(table, "roles"); item.tag_count = story_copy_strings(&item.tags, tags); item.role_count = story_copy_strings(&item.roles, roles); append(&project.entities, item)}
	for table in toml_tables(top, "roles") do append(&project.roles, Story_Role{id = toml_case_string(table, "id"), display_name = toml_case_string(table, "display_name"), description = toml_case_string(table, "description"), minimum = toml_case_int(table, "minimum"), maximum = toml_case_int(table, "maximum")})
	for table in toml_tables(
		top,
		"variables",
	) {kind, ok := story_value_kind_from_text(toml_case_string(table, "kind")); if !ok {story_project_destroy(&project); return {false, "story variable has unknown kind"}}; item := Story_Variable {
			id           = toml_case_string(table, "id"),
			display_name = toml_case_string(table, "display_name"),
			description  = toml_case_string(table, "description"),
			kind         = kind,
			minimum      = toml_case_int(table, "minimum"),
			maximum      = toml_case_int(table, "maximum"),
		}; item.default_value = story_toml_value(
			table,
			kind,
		); values := toml_case_strings(table, "enum_values"); item.enum_value_count = min(len(values), len(item.enum_values)); for value, i in values do if i < item.enum_value_count do item.enum_values[i] = value; append(&project.variables, item)}
	for table in toml_tables(top, "facts") do append(&project.facts, Story_Fact{id = toml_case_string(table, "id"), display_name = toml_case_string(table, "display_name"), proposition = toml_case_string(table, "proposition"), variable_id = toml_case_string(table, "variable"), canonical_truth = story_truth_from_text(toml_case_string(table, "canonical_truth")), player_visible = toml_case_bool(table, "player_visible")})
	for table in toml_tables(top, "propositions") do append(&project.propositions, Story_Proposition{id = toml_case_string(table, "id"), text = toml_case_string(table, "text"), canonical_truth = story_truth_from_text(toml_case_string(table, "canonical_truth"))})
	for table in toml_tables(top, "initial_knowledge") do append(&project.initial_knowledge, Story_Knowledge{actor_id = toml_case_string(table, "actor"), proposition_id = toml_case_string(table, "proposition"), stance = story_belief_from_text(toml_case_string(table, "stance"))})
	for table in toml_tables(top, "relationships") do append(&project.relationships, Story_Relationship{id = toml_case_string(table, "id"), source_id = toml_case_string(table, "source"), target_id = toml_case_string(table, "target"), kind = toml_case_string(table, "kind"), variable_id = toml_case_string(table, "variable")})
	for table in toml_tables(top, "events") {item := Story_Event {
			id             = toml_case_string(table, "id"),
			subject_id     = toml_case_string(table, "subject"),
			action         = toml_case_string(table, "action"),
			object_id      = toml_case_string(table, "object"),
			location_id    = toml_case_string(table, "location"),
			fictional_time = toml_case_string(table, "fictional_time"),
			provenance     = toml_case_string(table, "provenance"),
		}; witnesses := toml_case_strings(
			table,
			"witnesses",
		); item.witness_count = story_copy_strings(&item.witnesses, witnesses); append(&project.events, item)}
	for table in toml_tables(
		top,
		"objectives",
	) {initial_text := toml_case_string(table, "initial_status"); initial_status, ok := story_objective_status_from_text(initial_text); if !ok {story_project_destroy(&project); return {false, fmt.tprintf("objective has unknown initial_status %q", initial_text)}}; append(&project.objectives, Story_Objective{id = toml_case_string(table, "id"), display_name = toml_case_string(table, "display_name"), description = toml_case_string(table, "description"), hidden = toml_case_bool(table, "hidden"), initial_status = initial_status, stage_count = toml_case_int(table, "stage_count"), completion_condition = toml_case_int(table, "completion_condition"), failure_condition = toml_case_int(table, "failure_condition")})}
	for table in toml_tables(
		top,
		"conditions",
	) {kind, ok := story_condition_kind_from_text(toml_case_string(table, "kind")); if !ok {story_project_destroy(&project); return {false, "story condition has unknown kind"}}; value_kind, _ := story_value_kind_from_text(toml_case_string(table, "value_kind")); append(&project.conditions, Story_Condition{id = toml_case_string(table, "id"), kind = kind, first_child = toml_case_int(table, "first_child"), child_count = toml_case_int(table, "child_count"), variable_id = toml_case_string(table, "variable"), entity_id = toml_case_string(table, "entity"), other_entity_id = toml_case_string(table, "other_entity"), proposition_id = toml_case_string(table, "proposition"), objective_id = toml_case_string(table, "objective"), event_id = toml_case_string(table, "event"), content_id = toml_case_string(table, "content"), text_value = toml_case_string(table, "text"), value = story_toml_value(table, value_kind), comparison = Story_Integer_Comparison(clamp(toml_case_int(table, "comparison"), 0, 5)), objective_status = Story_Objective_Status(clamp(toml_case_int(table, "objective_status"), 0, 3)), belief_stance = story_belief_from_text(toml_case_string(table, "stance")), spatial_a = {toml_case_string(table, "space_a"), toml_case_string(table, "target_a")}, spatial_b = {toml_case_string(table, "space_b"), toml_case_string(table, "target_b")}, distance = toml_case_float(table, "distance")})}
	for table in toml_tables(
		top,
		"effects",
	) {kind, ok := story_effect_kind_from_text(toml_case_string(table, "kind")); if !ok {story_project_destroy(&project); return {false, "story effect has unknown kind"}}; value_kind, _ := story_value_kind_from_text(toml_case_string(table, "value_kind")); target := toml_case_string(table, "target"); if target == "" do target = toml_case_string(table, "world"); space := toml_case_string(table, "space"); if space == "" && target != "" do space = project.default_space_id; append(&project.effects, Story_Effect{id = toml_case_string(table, "id"), kind = kind, variable_id = toml_case_string(table, "variable"), actor_id = toml_case_string(table, "actor"), other_actor_id = toml_case_string(table, "other_actor"), proposition_id = toml_case_string(table, "proposition"), objective_id = toml_case_string(table, "objective"), event_id = toml_case_string(table, "event"), content_id = toml_case_string(table, "content"), value = story_toml_value(table, value_kind), belief_stance = story_belief_from_text(toml_case_string(table, "stance")), objective_status = Story_Objective_Status(clamp(toml_case_int(table, "objective_status"), 0, 3)), spatial_command = story_spatial_command_from_text(toml_case_string(table, "command")), spatial_target = {space, target}, spatial_destination = {toml_case_string(table, "destination_space"), toml_case_string(table, "destination")}, world_enabled = toml_case_bool(table, "world_enabled")})}
	for table in toml_tables(top, "localizations") do append(&project.localizations, Story_Localization{node_id = toml_case_string(table, "node"), language = toml_case_string(table, "language"), text = toml_case_string(table, "text"), status = toml_case_string(table, "status"), note = toml_case_string(table, "note"), voice = toml_case_string(table, "voice")})
	for table in toml_tables(top, "scenes") do append(&project.scenes, Story_Scene{id = toml_case_string(table, "id"), display_name = toml_case_string(table, "display_name"), entry_node = toml_case_string(table, "entry_node"), bound_entity = toml_case_string(table, "bound_entity"), summary = toml_case_string(table, "summary"), return_to = toml_case_string(table, "return_to")})
	for table in toml_tables(
		top,
		"nodes",
	) {kind, ok := story_node_kind_from_text(toml_case_string(table, "kind")); if !ok {story_project_destroy(&project); return {false, "story node has unknown kind"}}; append(&project.nodes, Story_Node{id = toml_case_string(table, "id"), scene_id = toml_case_string(table, "scene"), line_id = toml_case_string(table, "line_id"), speaker_id = toml_case_string(table, "speaker"), text = toml_case_string(table, "text"), next = toml_case_string(table, "next"), success = toml_case_string(table, "success"), failure = toml_case_string(table, "failure"), cancel = toml_case_string(table, "cancel"), subscene_id = toml_case_string(table, "subscene"), kind = kind, condition_root = toml_case_int(table, "condition"), first_effect = toml_case_int(table, "first_effect"), effect_count = toml_case_int(table, "effect_count")})}
	for table in toml_tables(top, "storylet_groups") do append(&project.storylet_groups, Story_Storylet_Group{id = toml_case_string(table, "id"), allow_empty = toml_case_bool(table, "allow_empty"), seeded_random_ties = toml_case_bool(table, "seeded_random_ties")})
	for table in toml_tables(top, "storylets") {item := Story_Storylet {
			id                = toml_case_string(table, "id"),
			group             = toml_case_string(table, "group"),
			scene_id          = toml_case_string(table, "scene"),
			dramatic_priority = toml_case_int(table, "priority"),
			specificity       = toml_case_int(table, "specificity"),
			cooldown          = toml_case_int(table, "cooldown"),
			authored_order    = toml_case_int(table, "authored_order"),
			repeat_policy     = story_repeat_from_text(toml_case_string(table, "repeat")),
			fallback          = toml_case_bool(table, "fallback"),
		}; roots := toml_case_ints(
			table,
			"conditions",
		); item.condition_count = min(len(roots), len(item.condition_roots)); for root, i in roots do if i < item.condition_count do item.condition_roots[i] = root; effects := toml_case_ints(table, "effects"); item.effect_count = min(len(effects), len(item.effect_indices)); for effect, i in effects do if i < item.effect_count do item.effect_indices[i] = effect; append(&project.storylets, item)}
	for table in toml_tables(top, "endings") do append(&project.endings, Story_Ending{id = toml_case_string(table, "id"), title = toml_case_string(table, "title"), summary = toml_case_string(table, "summary"), condition_root = toml_case_int(table, "condition"), priority = toml_case_int(table, "priority")})
	for table in toml_tables(
		top,
		"invariants",
	) {kind, ok := story_invariant_kind_from_text(toml_case_string(table, "kind")); if !ok {story_project_destroy(&project); return {false, "story invariant has unknown kind"}}; append(&project.invariants, Story_Invariant{id = toml_case_string(table, "id"), description = toml_case_string(table, "description"), kind = kind, condition_root = toml_case_int(table, "condition"), required = toml_case_bool(table, "required")})}
	for table, i in toml_tables(
		top,
		"objectives",
	) {project.objectives[i].completion_condition_id = toml_case_string(table, "completion_condition_id"); project.objectives[i].failure_condition_id = toml_case_string(table, "failure_condition_id")}
	for table, i in toml_tables(
		top,
		"conditions",
	) {children := toml_case_strings(table, "children"); project.conditions[i].child_id_count = story_copy_strings(&project.conditions[i].child_ids, children)}
	for table, i in toml_tables(
		top,
		"nodes",
	) {node := &project.nodes[i]; node.condition_id = toml_case_string(table, "condition_id"); effects := toml_case_strings(table, "effect_ids"); node.effect_id_count = story_copy_strings(&node.effect_ids, effects); node.ui = toml_case_string(table, "ui"); node.camera = toml_case_string(table, "camera"); node.actor = toml_case_string(table, "actor"); node.actor_mark = toml_case_string(table, "actor_mark"); node.animation = toml_case_string(table, "animation"); node.ui_image_asset_ref = toml_case_string(table, "ui_image_asset_ref"); node.sound_cue_asset_ref = toml_case_string(table, "sound_cue_asset_ref"); node.animation_asset_ref = toml_case_string(table, "animation_asset_ref"); node.summary = toml_case_string(table, "summary"); node.ending = toml_case_string(table, "ending"); node.domain_ref = toml_case_string(table, "domain_ref"); node.event_id = toml_case_string(table, "event_id"); node.duration = toml_case_float(table, "duration"); node.transition = toml_case_float(table, "transition"); node.blocking = toml_case_bool(table, "blocking"); choice_ids := toml_case_strings(table, "choice_ids"); choice_labels := toml_case_strings(table, "choice_labels"); choice_targets := toml_case_strings(table, "choice_targets"); choice_conditions := toml_case_strings(table, "choice_conditions"); node.choice_count = min(len(choice_ids), len(node.choices)); for choice_i in 0 ..< node.choice_count {node.choices[choice_i] = {
				id           = choice_ids[choice_i],
				label        = choice_i < len(choice_labels) ? choice_labels[choice_i] : "",
				target       = choice_i < len(choice_targets) ? choice_targets[choice_i] : "",
				condition_id = choice_i < len(choice_conditions) ? choice_conditions[choice_i] : "",
			}}}
	for table, i in toml_tables(
		top,
		"storylets",
	) {conditions := toml_case_strings(table, "condition_ids"); project.storylets[i].condition_count = max(project.storylets[i].condition_count, story_copy_strings(&project.storylets[i].condition_ids, conditions)); effects := toml_case_strings(table, "effect_ids"); project.storylets[i].effect_count = max(project.storylets[i].effect_count, story_copy_strings(&project.storylets[i].effect_ids, effects))}
	for table, i in toml_tables(top, "endings") do project.endings[i].condition_id = toml_case_string(table, "condition_id")
	for table, i in toml_tables(top, "invariants") do project.invariants[i].condition_id = toml_case_string(table, "condition_id")
	story_project_assign_legacy_ids(&project)
	story_domain_register_core(

	); for capability in project.capabilities {adapter := story_domain_find(capability.id, capability.version); if adapter != nil && adapter.parse != nil && !adapter.parse(cast(rawptr)&top, &project) {story_project_destroy(&project); return {false, "story capability payload could not be parsed"}}}
	// Loading is a lossless authoring operation. Semantic/profile validation is
	// intentionally separate so an existing project with actionable diagnostics
	// can still be opened, inspected, repaired, and saved.
	story_project_destroy(out); out^ = project; return {true, "STORY READY"}
}

story_toml_escape :: proc(value: string) -> string {result: strings.Builder; for 	ch in value {if ch == '\\' do _ = strings.write_string(&result, "\\\\")
		else if ch == '\"' do _ = strings.write_string(&result, "\\\"")
		else if ch == '\n' do _ = strings.write_string(&result, "\\n")
		else {_, _ = strings.write_rune(&result, ch)}}
	return strings.to_string(result)}
story_toml_string_array :: proc(values: []string) -> string {result := "["; for 	value, i in values {if i > 0 do result = fmt.tprintf("%s, ", result); result = fmt.tprintf(
			"%s\"%s\"",
			result,
			story_toml_escape(value),
		)}
	return fmt.tprintf("%s]", result)}
story_node_choice_array :: proc(node: ^Story_Node, field: int) -> string {result := "["; for 	choice, i in node.choices[:node.choice_count] {if i > 0 do result = fmt.tprintf("%s, ", result); value :=
			choice.id
		switch
		field {case 1:
			value = choice.label; case 2:
			value = choice.target; case 3:
			value = choice.condition_id; case:}
		result = fmt.tprintf("%s\"%s\"", result, story_toml_escape(value))}
	return fmt.tprintf("%s]", result)}

story_project_serialize :: proc(project: ^Story_Project) -> string {
	text := fmt.tprintf(
		"version = \"%s\"\nid = \"%s\"\ntitle = \"%s\"\ncreator = \"%s\"\ndescription = \"%s\"\ncontent_version = \"%s\"\ndefault_space = \"%s\"\nui_font_asset_ref = \"%s\"\nrevision = %d\n",
		STORY_PROJECT_VERSION,
		story_toml_escape(project.id),
		story_toml_escape(project.title),
		story_toml_escape(project.creator),
		story_toml_escape(project.description),
		story_toml_escape(project.content_version),
		story_toml_escape(project.default_space_id),
		story_toml_escape(project.ui_font_asset_ref),
		project.revision,
	)
	for capability in project.capabilities do text = fmt.tprintf("%s\n[[capabilities]]\nid = \"%s\"\nversion = \"%s\"\n", text, story_toml_escape(capability.id), story_toml_escape(capability.version))
	for requirement in project.expansion_requirements {distribution := requirement.distribution == .Embed ? "embed" : "reference"; fallback := requirement.fallback == .Omit ? "omit" : "none"; text = fmt.tprintf("%s\n[[expansions]]\nid = \"%s\"\nversion = \"%s\"\noptional = %t\ndistribution = \"%s\"\nfallback = \"%s\"\n", text, story_toml_escape(requirement.id), story_toml_escape(requirement.version), requirement.optional, distribution, fallback)}
	for item, i in project.entities do text = fmt.tprintf("%s\n[[entities]]\nid = \"%s\"\nkind = \"%s\"\ndisplay_name = \"%s\"\ndescription = \"%s\"\nappearance_model_asset_ref = \"%s\"\ndefault_animation = \"%s\"\nanimation_phase = %.3f\npresentation_tint = [%d, %d, %d, %d]\npresentation_facing = %.3f\nvisibility_condition_id = \"%s\"\navailability_condition_id = \"%s\"\ncompletion_condition_id = \"%s\"\ninteraction_scene_id = \"%s\"\ninteraction_prompt = \"%s\"\nunavailable_prompt = \"%s\"\ncompletion_prompt = \"%s\"\nspace_id = \"%s\"\ntarget_kind = \"%s\"\ntarget_id = \"%s\"\nvolume = %d\ncontainer_capacity = %d\nlocked = %t\nowner = \"%s\"\ncontained_by = \"%s\"\ntags = %s\nroles = %s\n", text, story_toml_escape(item.id), story_toml_escape(item.kind), story_toml_escape(item.display_name), story_toml_escape(item.description), story_toml_escape(item.appearance_model_asset_ref), story_toml_escape(item.default_animation), item.animation_phase, item.presentation_tint[0], item.presentation_tint[1], item.presentation_tint[2], item.presentation_tint[3], item.presentation_facing, story_toml_escape(item.visibility_condition_id), story_toml_escape(item.availability_condition_id), story_toml_escape(item.completion_condition_id), story_toml_escape(item.interaction_scene_id), story_toml_escape(item.interaction_prompt), story_toml_escape(item.unavailable_prompt), story_toml_escape(item.completion_prompt), story_toml_escape(item.spatial.space_id), story_spatial_target_kind_text(item.spatial.target_kind), story_toml_escape(item.spatial.target_id), item.volume, item.container_capacity, item.initially_locked, story_toml_escape(item.owner_id), story_toml_escape(item.initial_container_id), story_toml_string_array(project.entities[i].tags[:item.tag_count]), story_toml_string_array(project.entities[i].roles[:item.role_count]))
	for item in project.roles do text = fmt.tprintf("%s\n[[roles]]\nid = \"%s\"\ndisplay_name = \"%s\"\ndescription = \"%s\"\nminimum = %d\nmaximum = %d\n", text, story_toml_escape(item.id), story_toml_escape(item.display_name), story_toml_escape(item.description), item.minimum, item.maximum)
	for item, i in project.variables {enums := story_toml_string_array(project.variables[i].enum_values[:item.enum_value_count]); text = fmt.tprintf("%s\n[[variables]]\nid = \"%s\"\ndisplay_name = \"%s\"\ndescription = \"%s\"\nkind = \"%s\"\nboolean_value = %t\ninteger_value = %d\ntext_value = \"%s\"\nminimum = %d\nmaximum = %d\nenum_values = %s\n", text, story_toml_escape(item.id), story_toml_escape(item.display_name), story_toml_escape(item.description), story_value_kind_text(item.kind), item.default_value.boolean_value, item.default_value.integer_value, story_toml_escape(item.default_value.text_value), item.minimum, item.maximum, enums)}
	for item in project.facts do text = fmt.tprintf("%s\n[[facts]]\nid = \"%s\"\ndisplay_name = \"%s\"\nproposition = \"%s\"\nvariable = \"%s\"\ncanonical_truth = \"%s\"\nplayer_visible = %t\n", text, story_toml_escape(item.id), story_toml_escape(item.display_name), story_toml_escape(item.proposition), story_toml_escape(item.variable_id), story_truth_text(item.canonical_truth), item.player_visible)
	for item in project.propositions do text = fmt.tprintf("%s\n[[propositions]]\nid = \"%s\"\ntext = \"%s\"\ncanonical_truth = \"%s\"\n", text, story_toml_escape(item.id), story_toml_escape(item.text), story_truth_text(item.canonical_truth))
	for item in project.initial_knowledge do text = fmt.tprintf("%s\n[[initial_knowledge]]\nactor = \"%s\"\nproposition = \"%s\"\nstance = \"%s\"\n", text, story_toml_escape(item.actor_id), story_toml_escape(item.proposition_id), story_belief_text(item.stance))
	for item in project.relationships do text = fmt.tprintf("%s\n[[relationships]]\nid = \"%s\"\nsource = \"%s\"\ntarget = \"%s\"\nkind = \"%s\"\nvariable = \"%s\"\n", text, story_toml_escape(item.id), story_toml_escape(item.source_id), story_toml_escape(item.target_id), story_toml_escape(item.kind), story_toml_escape(item.variable_id))
	for item, i in project.events do text = fmt.tprintf("%s\n[[events]]\nid = \"%s\"\nsubject = \"%s\"\naction = \"%s\"\nobject = \"%s\"\nlocation = \"%s\"\nfictional_time = \"%s\"\nprovenance = \"%s\"\nwitnesses = %s\n", text, story_toml_escape(item.id), story_toml_escape(item.subject_id), story_toml_escape(item.action), story_toml_escape(item.object_id), story_toml_escape(item.location_id), story_toml_escape(item.fictional_time), story_toml_escape(item.provenance), story_toml_string_array(project.events[i].witnesses[:item.witness_count]))
	for item in project.objectives do text = fmt.tprintf("%s\n[[objectives]]\nid = \"%s\"\ndisplay_name = \"%s\"\ndescription = \"%s\"\nhidden = %t\ninitial_status = \"%s\"\nstage_count = %d\ncompletion_condition_id = \"%s\"\nfailure_condition_id = \"%s\"\n", text, story_toml_escape(item.id), story_toml_escape(item.display_name), story_toml_escape(item.description), item.hidden, story_objective_status_text(item.initial_status), item.stage_count, story_toml_escape(item.completion_condition_id), story_toml_escape(item.failure_condition_id))
	for &item in project.conditions do text = fmt.tprintf("%s\n[[conditions]]\nid = \"%s\"\nkind = \"%s\"\nchildren = %s\nvariable = \"%s\"\nentity = \"%s\"\nother_entity = \"%s\"\nproposition = \"%s\"\nobjective = \"%s\"\nevent = \"%s\"\ncontent = \"%s\"\ntext = \"%s\"\nspace_a = \"%s\"\ntarget_a = \"%s\"\nspace_b = \"%s\"\ntarget_b = \"%s\"\ndistance = %.3f\nvalue_kind = \"%s\"\nboolean_value = %t\ninteger_value = %d\ntext_value = \"%s\"\ncomparison = %d\nobjective_status = %d\nstance = \"%s\"\n", text, story_toml_escape(item.id), story_condition_kind_text(item.kind), story_toml_string_array(item.child_ids[:item.child_id_count]), story_toml_escape(item.variable_id), story_toml_escape(item.entity_id), story_toml_escape(item.other_entity_id), story_toml_escape(item.proposition_id), story_toml_escape(item.objective_id), story_toml_escape(item.event_id), story_toml_escape(item.content_id), story_toml_escape(item.text_value), story_toml_escape(item.spatial_a.space_id), story_toml_escape(item.spatial_a.target_id), story_toml_escape(item.spatial_b.space_id), story_toml_escape(item.spatial_b.target_id), item.distance, story_value_kind_text(item.value.kind), item.value.boolean_value, item.value.integer_value, story_toml_escape(item.value.text_value), int(item.comparison), int(item.objective_status), story_belief_text(item.belief_stance))
	for item in project.effects do text = fmt.tprintf("%s\n[[effects]]\nid = \"%s\"\nkind = \"%s\"\nvariable = \"%s\"\nactor = \"%s\"\nother_actor = \"%s\"\nproposition = \"%s\"\nobjective = \"%s\"\nevent = \"%s\"\ncontent = \"%s\"\ncommand = \"%s\"\nspace = \"%s\"\ntarget = \"%s\"\ndestination_space = \"%s\"\ndestination = \"%s\"\nvalue_kind = \"%s\"\nboolean_value = %t\ninteger_value = %d\ntext_value = \"%s\"\nstance = \"%s\"\nobjective_status = %d\nworld_enabled = %t\n", text, story_toml_escape(item.id), story_effect_kind_text(item.kind), story_toml_escape(item.variable_id), story_toml_escape(item.actor_id), story_toml_escape(item.other_actor_id), story_toml_escape(item.proposition_id), story_toml_escape(item.objective_id), story_toml_escape(item.event_id), story_toml_escape(item.content_id), story_spatial_command_text(item.spatial_command), story_toml_escape(item.spatial_target.space_id), story_toml_escape(item.spatial_target.target_id), story_toml_escape(item.spatial_destination.space_id), story_toml_escape(item.spatial_destination.target_id), story_value_kind_text(item.value.kind), item.value.boolean_value, item.value.integer_value, story_toml_escape(item.value.text_value), story_belief_text(item.belief_stance), int(item.objective_status), item.world_enabled)
	for item in project.localizations do text = fmt.tprintf("%s\n[[localizations]]\nnode = \"%s\"\nlanguage = \"%s\"\ntext = \"%s\"\nstatus = \"%s\"\nnote = \"%s\"\nvoice = \"%s\"\n", text, story_toml_escape(item.node_id), story_toml_escape(item.language), story_toml_escape(item.text), story_toml_escape(item.status), story_toml_escape(item.note), story_toml_escape(item.voice))
	for item in project.scenes do text = fmt.tprintf("%s\n[[scenes]]\nid = \"%s\"\ndisplay_name = \"%s\"\nentry_node = \"%s\"\nbound_entity = \"%s\"\nsummary = \"%s\"\nreturn_to = \"%s\"\n", text, story_toml_escape(item.id), story_toml_escape(item.display_name), story_toml_escape(item.entry_node), story_toml_escape(item.bound_entity), story_toml_escape(item.summary), story_toml_escape(item.return_to))
	for &item in project.nodes do text = fmt.tprintf("%s\n[[nodes]]\nid = \"%s\"\nscene = \"%s\"\nkind = \"%s\"\nline_id = \"%s\"\nspeaker = \"%s\"\ntext = \"%s\"\nnext = \"%s\"\nsuccess = \"%s\"\nfailure = \"%s\"\ncancel = \"%s\"\nsubscene = \"%s\"\ncondition_id = \"%s\"\neffect_ids = %s\nui = \"%s\"\ncamera = \"%s\"\nactor = \"%s\"\nactor_mark = \"%s\"\nanimation = \"%s\"\nui_image_asset_ref = \"%s\"\nsound_cue_asset_ref = \"%s\"\nanimation_asset_ref = \"%s\"\nsummary = \"%s\"\nending = \"%s\"\ndomain_ref = \"%s\"\nevent_id = \"%s\"\nduration = %.3f\ntransition = %.3f\nblocking = %t\nchoice_ids = %s\nchoice_labels = %s\nchoice_targets = %s\nchoice_conditions = %s\n", text, story_toml_escape(item.id), story_toml_escape(item.scene_id), story_node_kind_text(item.kind), story_toml_escape(item.line_id), story_toml_escape(item.speaker_id), story_toml_escape(item.text), story_toml_escape(item.next), story_toml_escape(item.success), story_toml_escape(item.failure), story_toml_escape(item.cancel), story_toml_escape(item.subscene_id), story_toml_escape(item.condition_id), story_toml_string_array(item.effect_ids[:item.effect_id_count]), story_toml_escape(item.ui), story_toml_escape(item.camera), story_toml_escape(item.actor), story_toml_escape(item.actor_mark), story_toml_escape(item.animation), story_toml_escape(item.ui_image_asset_ref), story_toml_escape(item.sound_cue_asset_ref), story_toml_escape(item.animation_asset_ref), story_toml_escape(item.summary), story_toml_escape(item.ending), story_toml_escape(item.domain_ref), story_toml_escape(item.event_id), item.duration, item.transition, item.blocking, story_node_choice_array(&item, 0), story_node_choice_array(&item, 1), story_node_choice_array(&item, 2), story_node_choice_array(&item, 3))
	for item in project.storylet_groups do text = fmt.tprintf("%s\n[[storylet_groups]]\nid = \"%s\"\nallow_empty = %t\nseeded_random_ties = %t\n", text, story_toml_escape(item.id), item.allow_empty, item.seeded_random_ties)
	for &item in project.storylets do text = fmt.tprintf("%s\n[[storylets]]\nid = \"%s\"\ngroup = \"%s\"\nscene = \"%s\"\ncondition_ids = %s\neffect_ids = %s\npriority = %d\nspecificity = %d\ncooldown = %d\nauthored_order = %d\nrepeat = \"%s\"\nfallback = %t\n", text, story_toml_escape(item.id), story_toml_escape(item.group), story_toml_escape(item.scene_id), story_toml_string_array(item.condition_ids[:item.condition_count]), story_toml_string_array(item.effect_ids[:item.effect_count]), item.dramatic_priority, item.specificity, item.cooldown, item.authored_order, story_repeat_text(item.repeat_policy), item.fallback)
	for item in project.endings do text = fmt.tprintf("%s\n[[endings]]\nid = \"%s\"\ntitle = \"%s\"\nsummary = \"%s\"\ncondition_id = \"%s\"\npriority = %d\n", text, story_toml_escape(item.id), story_toml_escape(item.title), story_toml_escape(item.summary), story_toml_escape(item.condition_id), item.priority)
	for item in project.invariants do text = fmt.tprintf("%s\n[[invariants]]\nid = \"%s\"\ndescription = \"%s\"\nkind = \"%s\"\ncondition_id = \"%s\"\nrequired = %t\n", text, story_toml_escape(item.id), story_toml_escape(item.description), story_invariant_kind_text(item.kind), story_toml_escape(item.condition_id), item.required)
	for capability in project.capabilities {adapter := story_domain_find(capability.id, capability.version); if capability.payload != nil && adapter != nil && adapter.serialize != nil {capability_text := adapter.serialize(capability.payload); if capability_text != "" do text = fmt.tprintf("%s\n%s", text, capability_text)}}
	return text
}

save_story_project :: proc(path: string, project: ^Story_Project) -> Validation {validation :=
		story_project_validate(project)
	if !validation.ok {story_validation_destroy(&validation); return{false, "story is invalid"}}
	story_validation_destroy(&validation)
	temporary := fmt.tprintf("%s.tmp", path)
	data := story_project_serialize(project)
	if os.write_entire_file(temporary, transmute([]u8)data) != nil do return {false, "could not write story"}
	if os.rename(temporary, path) != nil do return {false, "could not replace story"}
	return{true, "STORY SAVED"}}
