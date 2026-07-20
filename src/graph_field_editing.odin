package main

import "core:fmt"
import "core:strconv"
import "core:strings"

graph_begin_edit :: proc(
	field: Graph_Field,
	value: string,
	node := -1,
	multiline := false,
) {graph_state.field_edit = {
		active       = true,
		multiline    = multiline,
		field        = field,
		node         = node,
		choice_index = -1,
	}; count := min(
		len(value),
		len(graph_state.field_edit.buffer),
	); copy(graph_state.field_edit.buffer[:count], transmute([]u8)value); graph_state.field_edit.count = count}
graph_begin_choice_edit :: proc(
	field: Graph_Field,
	value: string,
	node, choice_index: int,
) {graph_begin_edit(field, value, node); graph_state.field_edit.choice_index = choice_index}
graph_condition_primary_string :: proc(item: ^Story_Condition) -> ^string {#partial switch
	item.kind {case .Value_Equals, .Integer_Compare:
		return(
			&item.variable_id \
		); case .Entity_Has_Tag, .Entity_Has_Role, .Aware, .Unaware, .Belief_Equals:
		return &item.entity_id; case .Communicated:
		return &item.proposition_id; case .Objective_Equals:
		return &item.objective_id; case .Event_Occurred:
		return &item.event_id; case .Scene_Completed, .Storylet_Seen:
		return &item.content_id; case:
		return &item.text_value}}
graph_effect_primary_string :: proc(item: ^Story_Effect) -> ^string {#partial switch
	item.kind {case .Set_Value, .Add_Integer:
		return &item.variable_id; case .Make_Aware, .Set_Belief, .Communicate:
		return &item.actor_id; case .Set_Objective:
		return &item.objective_id; case .Emit_Event:
		return &item.event_id; case .Complete_Scene, .Mark_Storylet:
		return &item.content_id; case:
		return &item.world_id}}
graph_definition_join_children :: proc(
	item: ^Story_Condition,
) -> string {return graph_join_strings(item.child_ids[:item.child_id_count])}
graph_condition_slot :: proc(
	item: ^Story_Condition,
	slot: int,
) -> (
	string,
	string,
	bool,
) {#partial switch item.kind {case .Always, .Never:
		return "", "", false; case .All, .Any, .Not:
		if slot == 0 do return "CHILD CONDITIONS", graph_definition_join_children(item), true; case .Value_Equals:
		if slot == 0 do return "VARIABLE", item.variable_id, true
		if slot == 1 do return "VALUE TYPE", fmt.tprintf("%d", int(item.value.kind)), true
		if slot == 2 do return "VALUE", story_value_string(item.value), true; case .Integer_Compare:
		if slot == 0 do return "VARIABLE", item.variable_id, true
		if slot == 1 do return "COMPARISON", fmt.tprintf("%d", int(item.comparison)), true
		if slot == 2 do return "INTEGER", fmt.tprintf("%d", item.value.integer_value), true; case .Entity_Has_Tag, .Entity_Has_Role:
		if slot == 0 do return "ENTITY", item.entity_id, true
		if slot == 1 do return item.kind == .Entity_Has_Tag ? "TAG" : "ROLE", item.text_value, true; case .Aware, .Unaware, .Belief_Equals:
		if slot == 0 do return "ENTITY", item.entity_id, true
		if slot == 1 do return "PROPOSITION", item.proposition_id, true
		if slot == 2 && item.kind == .Belief_Equals do return "STANCE", fmt.tprintf("%d", int(item.belief_stance)), true; case .Communicated:
		if slot == 0 do return "ACTOR", item.entity_id, true
		if slot == 1 do return "OTHER ACTOR", item.other_entity_id, true
		if slot == 2 do return "PROPOSITION", item.proposition_id, true; case .Objective_Equals:
		if slot == 0 do return "OBJECTIVE", item.objective_id, true
		if slot == 1 do return "STATUS", fmt.tprintf("%d", int(item.objective_status)), true; case .Event_Occurred:
		if slot == 0 do return "EVENT", item.event_id, true; case .Scene_Completed, .Storylet_Seen:
		if slot == 0 do return item.kind == .Scene_Completed ? "SCENE" : "STORYLET", item.content_id, true; case .Capability_State:
		if slot == 0 do return "CAPABILITY", item.entity_id, true
		if slot == 1 do return "QUERY", item.content_id, true; case .Spatial_Present, .Spatial_Contained_By, .Spatial_Distance, .Spatial_Visible, .Spatial_Reachable, .Spatial_Travel_Time:
		if slot == 0 do return "SPACE A", item.spatial_a.space_id, true
		if slot == 1 do return "TARGET A", item.spatial_a.target_id, true
		if slot == 2 do return "SPACE B", item.spatial_b.space_id, true
		if slot == 3 do return "TARGET B", item.spatial_b.target_id, true
		if slot == 4 && (item.kind == .Spatial_Distance || item.kind == .Spatial_Travel_Time) do return "DISTANCE / TIME", fmt.tprintf("%.3f", item.distance), true}; return "", "", false}
graph_effect_slot :: proc(
	item: ^Story_Effect,
	slot: int,
) -> (
	string,
	string,
	bool,
) {#partial switch item.kind {case .Set_Value, .Add_Integer:
		if slot == 0 do return "VARIABLE", item.variable_id, true
		if slot == 1 do return "VALUE TYPE", fmt.tprintf("%d", int(item.value.kind)), true
		if slot == 2 do return "VALUE", story_value_string(item.value), true; case .Make_Aware, .Set_Belief, .Communicate:
		if slot == 0 do return "ACTOR", item.actor_id, true
		if slot == 1 do return "OTHER ACTOR", item.other_actor_id, true
		if slot == 2 do return "PROPOSITION", item.proposition_id, true
		if slot == 3 && item.kind == .Set_Belief do return "STANCE", fmt.tprintf("%d", int(item.belief_stance)), true; case .Set_Objective:
		if slot == 0 do return "OBJECTIVE", item.objective_id, true
		if slot == 1 do return "STATUS", fmt.tprintf("%d", int(item.objective_status)), true; case .Emit_Event:
		if slot == 0 do return "EVENT", item.event_id, true; case .Complete_Scene, .Mark_Storylet:
		if slot == 0 do return item.kind == .Complete_Scene ? "SCENE" : "STORYLET", item.content_id, true; case .Spatial_Command:
		if slot == 0 do return "COMMAND", fmt.tprintf("%d", int(item.spatial_command)), true
		if slot == 1 do return "TARGET SPACE", item.spatial_target.space_id, true
		if slot == 2 do return "TARGET", item.spatial_target.target_id, true
		if slot == 3 do return "DESTINATION SPACE", item.spatial_destination.space_id, true
		if slot == 4 do return "DESTINATION", item.spatial_destination.target_id, true}; return "", "", false}
graph_set_story_value_text :: proc(value: ^Story_Value, text: string) -> bool {#partial switch
	value.kind {case .Boolean:
		lower := strings.to_lower(strings.trim_space(text))
		if lower != "true" && lower != "false" do return false
		value.boolean_value = lower == "true"; case .Integer:
		parsed, ok := strconv.parse_i64(text); if !ok do return false
		value.integer_value = int(parsed); case .Enumeration, .Entity:
		value.text_value = text}
	return true}
graph_condition_set_slot :: proc(
	item: ^Story_Condition,
	slot: int,
	text: string,
) -> bool {#partial switch item.kind {case .All, .Any, .Not:
		if slot ==
		   0 {values := graph_split_references(text); item.child_id_count = min(len(values), len(item.child_ids)); for i in 0 ..< item.child_id_count do item.child_ids[i] = values[i]; return true}; case .Value_Equals:
		if slot == 0 {item.variable_id = text; return true}
		if slot == 1 {parsed, ok := strconv.parse_i64(text)
			if !ok do return false
			item.value.kind = Story_Value_Kind(clamp(int(parsed), 0, 3))
			return true}
		if slot == 2 do return graph_set_story_value_text(&item.value, text); case .Integer_Compare:
		if slot == 0 {item.variable_id = text; return true}
		if slot == 1 {parsed, ok := strconv.parse_i64(text)
			if !ok do return false
			item.comparison = Story_Integer_Comparison(clamp(int(parsed), 0, 5))
			return true}
		if slot ==
		   2 {parsed, ok := strconv.parse_i64(text); if !ok do return false; item.value.kind = .Integer; item.value.integer_value = int(parsed); return true}; case .Entity_Has_Tag, .Entity_Has_Role:
		if slot == 0 {item.entity_id = text; return true}
		if slot == 1 {item.text_value = text; return true}; case .Aware, .Unaware, .Belief_Equals:
		if slot == 0 {item.entity_id = text; return true}; if slot == 1 {item.proposition_id = text
			return true}
		if slot == 2 &&
		   item.kind ==
			   .Belief_Equals {parsed, ok := strconv.parse_i64(text); if !ok do return false; item.belief_stance = Story_Belief_Stance(clamp(int(parsed), 0, 2)); return true}; case .Communicated:
		if slot == 0 {item.entity_id = text; return true}
		if slot == 1 {item.other_entity_id = text
			return true}
		if slot == 2 {item.proposition_id = text; return true}; case .Objective_Equals:
		if slot == 0 {item.objective_id = text; return true}
		if slot ==
		   1 {parsed, ok := strconv.parse_i64(text); if !ok do return false; item.objective_status = Story_Objective_Status(clamp(int(parsed), 0, 3)); return true}; case .Event_Occurred:
		if slot == 0 {item.event_id = text; return true}; case .Scene_Completed, .Storylet_Seen:
		if slot == 0 {item.content_id = text; return true}; case .Capability_State:
		if slot == 0 {item.entity_id = text; return true}
		if slot ==
		   1 {item.content_id = text; return true}; case .Spatial_Present, .Spatial_Contained_By, .Spatial_Distance, .Spatial_Visible, .Spatial_Reachable, .Spatial_Travel_Time:
		if slot == 0 {item.spatial_a.space_id = text; return true}
		if slot == 1 {item.spatial_a.target_id = text; return true}
		if slot == 2 {item.spatial_b.space_id = text; return true}
		if slot == 3 {item.spatial_b.target_id = text; return true}
		if slot ==
		   4 {parsed, ok := strconv.parse_f32(text); if !ok do return false; item.distance = parsed; return true}; case:}; return false}
graph_effect_set_slot :: proc(
	item: ^Story_Effect,
	slot: int,
	text: string,
) -> bool {#partial switch item.kind {case .Set_Value, .Add_Integer:
		if slot == 0 {item.variable_id = text; return true}
		if slot == 1 {parsed, ok := strconv.parse_i64(text)
			if !ok do return false
			item.value.kind = Story_Value_Kind(clamp(int(parsed), 0, 3))
			return true}
		if slot == 2 do return graph_set_story_value_text(&item.value, text); case .Make_Aware, .Set_Belief, .Communicate:
		if slot == 0 {item.actor_id = text; return true}; if slot == 1 {item.other_actor_id = text
			return true}
		if slot == 2 {item.proposition_id = text; return true}
		if slot == 3 &&
		   item.kind ==
			   .Set_Belief {parsed, ok := strconv.parse_i64(text); if !ok do return false; item.belief_stance = Story_Belief_Stance(clamp(int(parsed), 0, 2)); return true}; case .Set_Objective:
		if slot == 0 {item.objective_id = text; return true}
		if slot ==
		   1 {parsed, ok := strconv.parse_i64(text); if !ok do return false; item.objective_status = Story_Objective_Status(clamp(int(parsed), 0, 3)); return true}; case .Emit_Event:
		if slot == 0 {item.event_id = text; return true}; case .Complete_Scene, .Mark_Storylet:
		if slot == 0 {item.content_id = text; return true}; case .Spatial_Command:
		if slot == 0 {parsed, ok := strconv.parse_i64(text); if !ok do return false
			item.spatial_command = Story_Spatial_Command_Kind(clamp(int(parsed), 0, 5))
			return true}
		if slot == 1 {item.spatial_target.space_id = text; return true}
		if slot == 2 {item.spatial_target.target_id = text; return true}
		if slot == 3 {item.spatial_destination.space_id = text; return true}
		if slot ==
		   4 {item.spatial_destination.target_id = text; return true}; case:}; return false}
graph_edit_text :: proc() -> string {return string(
		graph_state.field_edit.buffer[:graph_state.field_edit.count],
	)}
graph_join_strings :: proc(values: []string) -> string {result := ""; for 	value, i in values {if i > 0 do result = fmt.tprintf("%s, %s", result, value)
		else do result = value}
	return result}
graph_split_references :: proc(value: string) -> []string {result := make([dynamic]string, 0, 8)
	for part in strings.split(
		value,
		",",
	) {trimmed := strings.trim_space(part); if trimmed != "" do append(&result, trimmed)}
	return result[:]}
graph_edit_append :: proc(text: string) {edit := &graph_state.field_edit; if !edit.active do return
	available := len(edit.buffer) - edit.count
	count := min(len(text), available)
	copy(edit.buffer[edit.count:edit.count + count], transmute([]u8)text)
	edit.count += count
	edit.error = ""}
graph_edit_backspace :: proc() {edit := &graph_state.field_edit; if edit.count <= 0 do return
	edit.count -= 1
	for edit.count > 0 && (edit.buffer[edit.count] & 0xc0) == 0x80 do edit.count -= 1
	edit.error = ""}
graph_valid_id :: proc(value: string) -> bool {if value == "" do return false; for c in value do if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '_') do return false
	return true}
graph_commit_edit :: proc() -> bool {
	edit := &graph_state.field_edit; if !edit.active do return false; value := graph_edit_text(); node_index := edit.node
	if edit.field ==
	   .Scene_Id {if !graph_valid_id(value) {edit.error = "Use letters, numbers, and underscores"; return false}; for scene, i in graph_document.scenes[:graph_document.scene_count] do if i != graph_state.active_scene && scene.scene.id == value {edit.error = "Scene ID already exists"; return false}}
	if edit.field ==
	   .Node_Id {if !graph_valid_id(value) {edit.error = "Use letters, numbers, and underscores"; return false}; if node_index < 0 || node_index >= graph_document.node_count do return false; for node, i in graph_document.nodes[:graph_document.node_count] do if i != node_index && node.beat.id == value {edit.error = "Node ID already exists"; return false}}
	if edit.field == .Node_Scene &&
	   graph_scene_index(value) < 0 {edit.error = "Scene does not exist"; return false}
	if edit.field ==
	   .Node_Kind {_, ok := story_node_kind_from_text(value); if !ok {edit.error = "Unsupported node kind"; return false}}
	if edit.field ==
	   .Choice_Id {if !graph_valid_id(value) || node_index < 0 || node_index >= graph_document.node_count {edit.error = "Choice IDs use letters, numbers, and underscores"; return false}; beat := &graph_document.nodes[node_index].beat; for id, i in beat.choice_ids do if i != edit.choice_index && id == value {edit.error = "Choice ID already exists on this node"; return false}}
	if edit.field == .Condition_Id ||
	   edit.field ==
		   .Effect_Id {if !graph_valid_id(value) {edit.error = "Use letters, numbers, and underscores"; return false}; if edit.field == .Condition_Id {for item, i in graph_document.conditions[:graph_document.condition_count] do if i != graph_state.selected_condition && item.id == value {edit.error = "Condition ID already exists"; return false}} else {for item, i in graph_document.effects[:graph_document.effect_count] do if i != graph_state.selected_effect && item.id == value {edit.error = "Effect ID already exists"; return false}}}
	if edit.field ==
	   .Condition_Kind {_, ok := story_condition_kind_from_text(value); if !ok {edit.error = "Unknown condition kind"; return false}}
	if edit.field ==
	   .Effect_Kind {_, ok := story_effect_kind_from_text(value); if !ok {edit.error = "Unknown effect kind"; return false}}
	if edit.field ==
	   .Localization_Filter_Language {graph_state.localization_language = value; edit.active = false; return true}
	if edit.field ==
	   .Localization_Filter_Status {graph_state.localization_status = value; edit.active = false; return true}
	graph_history_push("Edit graph field")
	if edit.field ==
	   .Scene_Id {scene := &graph_document.scenes[graph_state.active_scene].scene; old := scene.id; scene.id = value; for &node in graph_document.nodes[:graph_document.node_count] {if node.beat.scene == old do node.beat.scene = value; if node.beat.subscene_id == old do node.beat.subscene_id = value}; for &other in graph_document.scenes[:graph_document.scene_count] do if other.scene.return_to == old do other.scene.return_to = value
	} else if edit.field == .Scene_Display_Name do graph_document.scenes[graph_state.active_scene].scene.display_name = value
	else if edit.field == .Scene_Bound_Entity do graph_document.scenes[graph_state.active_scene].scene.source = value
	else if edit.field == .Scene_Summary do graph_document.scenes[graph_state.active_scene].scene.summary = value
	else if edit.field == .Scene_Return do graph_document.scenes[graph_state.active_scene].scene.return_to = value
	else if edit.field == .Localization_Filter_Language do graph_state.localization_language = value
	else if edit.field == .Localization_Filter_Status do graph_state.localization_status = value
	else if edit.field >= .Localization_Language && edit.field <= .Localization_Voice && graph_state.selected_localization >= 0 && graph_state.selected_localization < graph_document.localization_count {item := &graph_document.localizations[graph_state.selected_localization]; #partial switch edit.field {case .Localization_Language:
			item.language = value; case .Localization_Text:
			item.text = value; case .Localization_Status:
			item.status = value; case .Localization_Note:
			item.note = value; case .Localization_Voice:
			item.voice = value; case:}} else if edit.field >= .Condition_Id && edit.field <= .Condition_Value_5 && graph_state.selected_condition >= 0 && graph_state.selected_condition < graph_document.condition_count {item := &graph_document.conditions[graph_state.selected_condition]; if edit.field == .Condition_Id {old := item.id; item.id = value; for &node in graph_document.nodes[:graph_document.node_count] {if node.beat.condition_id == old do node.beat.condition_id = value; for &choice in node.beat.choice_conditions do if choice == old do choice = value}; for &condition in graph_document.conditions[:graph_document.condition_count] do for &child in condition.child_ids[:condition.child_id_count] do if child == old do child = value} else if edit.field == .Condition_Kind {kind, _ := story_condition_kind_from_text(value); item.kind = kind} else {slot := int(edit.field) - int(Graph_Field.Condition_Value); if !graph_condition_set_slot(item, slot, value) {graph_document = graph_history.undo[graph_history.undo_count - 1].document; graph_history.undo_count -= 1; edit.error = "Value does not match this field"; return false}}} else if edit.field >= .Effect_Id && edit.field <= .Effect_Value_5 && graph_state.selected_effect >= 0 && graph_state.selected_effect < graph_document.effect_count {item := &graph_document.effects[graph_state.selected_effect]; if edit.field == .Effect_Id {old := item.id; item.id = value; for &node in graph_document.nodes[:graph_document.node_count] do for &effect in node.beat.effect_ids do if effect == old do effect = value} else if edit.field == .Effect_Kind {kind, _ := story_effect_kind_from_text(value); item.kind = kind} else {slot := int(edit.field) - int(Graph_Field.Effect_Value); if !graph_effect_set_slot(item, slot, value) {graph_document = graph_history.undo[graph_history.undo_count - 1].document; graph_history.undo_count -= 1; edit.error = "Value does not match this field"; return false}}} else if edit.field == .Search {graph_state.search_query = value; graph_state.search_result = -1; edit.active = false; _ = graph_focus_search_result(1); return true} else if node_index >= 0 && node_index < graph_document.node_count {beat := &graph_document.nodes[node_index].beat; #partial switch edit.field {
		case .Node_Id:
			old := beat.id; beat.id = value; for &node in graph_document.nodes[:graph_document.node_count] {if node.beat.scene != beat.scene do continue; if node.beat.next == old do node.beat.next = value; if node.beat.success == old do node.beat.success = value; if node.beat.failure == old do node.beat.failure = value; if node.beat.cancel == old do node.beat.cancel = value; for &target in node.beat.choice_targets do if target == old do target = value}; for &scene in graph_document.scenes[:graph_document.scene_count] do if scene.scene.id == beat.scene && scene.scene.entry == old do scene.scene.entry = value; for &item in graph_document.localizations[:graph_document.localization_count] do if item.node_id == old do item.node_id = value
		case .Node_Scene:
			old := beat.scene; beat.scene = value; for &scene in graph_document.scenes[:graph_document.scene_count] do if scene.scene.id == old && scene.scene.entry == beat.id do scene.scene.entry = ""; graph_state.active_scene = graph_scene_index(value)
		case .Node_Kind:
			beat.kind = value
		case .Line_Id:
			beat.line_id = value; case .Text:
			beat.text = value; case .Summary:
			beat.summary = value; case .Speaker:
			beat.speaker = value; case .Camera:
			beat.camera = value; case .Actor:
			beat.actor = value; case .Actor_Mark:
			beat.actor_mark = value; case .Animation:
			beat.animation = value; case .UI_Image_Asset:
			beat.ui_image_asset_ref = value; case .Sound_Cue_Asset:
			beat.sound_cue_asset_ref = value; case .Animation_Asset:
			beat.animation_asset_ref = value; case .Interaction:
			beat.interaction = value; case .Event:
			beat.event_id = value; case .Subscene:
			beat.subscene_id = value; case .Domain_Ref:
			beat.domain_ref = value; case .Condition:
			beat.condition_id = value; case .Effects:
			beat.effect_ids = graph_split_references(value); case .Condition_Root:
			parsed, ok := strconv.parse_i64(value); if !ok do return false; beat.condition_root = int(parsed); case .First_Effect:
			parsed, ok := strconv.parse_i64(value); if !ok do return false; beat.first_effect = int(parsed); case .Effect_Count:
			parsed, ok := strconv.parse_i64(value); if !ok do return false; beat.effect_count = int(parsed); case .Clue:
			beat.clue = value; case .Ending:
			beat.ending = value; case .UI:
			beat.ui = value; case .Next:
			beat.next = value; case .Success:
			beat.success = value; case .Failure:
			beat.failure = value; case .Cancel:
			beat.cancel = value; case .Blocking:
			beat.blocking = strings.to_lower(value) == "true" || value == "1"; case .Requires_Clues:
			beat.requires_clues = graph_split_references(value); case .Requires_Claims:
			beat.requires_claims = graph_split_references(value); case .Requires_Topics:
			beat.requires_topics = graph_split_references(value); case .Unlock_Clues:
			beat.unlock_clues = graph_split_references(value); case .Unlock_Claims:
			beat.unlock_claims = graph_split_references(value); case .Unlock_Topics:
			beat.unlock_topics = graph_split_references(value)
		case .Choice_Id:
			if edit.choice_index >= 0 && edit.choice_index < len(beat.choice_ids) do beat.choice_ids[edit.choice_index] = value
		case .Choice_Label:
			if edit.choice_index >= 0 && edit.choice_index < len(beat.choice_labels) do beat.choice_labels[edit.choice_index] = value
		case .Choice_Target:
			if edit.choice_index >= 0 && edit.choice_index < len(beat.choice_targets) do beat.choice_targets[edit.choice_index] = value
		case .Choice_Condition:
			if edit.choice_index >= 0 && edit.choice_index < len(beat.choice_conditions) do beat.choice_conditions[edit.choice_index] = value
		case .Duration:
			v, ok := strconv.parse_f32(value); if !ok {graph_document = graph_history.undo[graph_history.undo_count - 1].document; graph_history.undo_count -= 1; edit.error = "Enter a number"; return false}; beat.duration = v
		case .Transition:
			v, ok := strconv.parse_f32(value); if !ok {graph_document = graph_history.undo[graph_history.undo_count - 1].document; graph_history.undo_count -= 1; edit.error = "Enter a number"; return false}; beat.transition = v
		case:}}
	if node_index >= 0 && node_index < graph_document.node_count && edit.field >= .Requires_Clues && edit.field <= .Unlock_Topics do graph_document.nodes[node_index].beat.metadata_refs_dirty = true
	edit.active = false; graph_changed(); return true
}
graph_cancel_edit :: proc() {graph_state.field_edit = {}}
graph_advance_edit :: proc(direction: int) -> bool {edit := graph_state.field_edit
	if !graph_commit_edit() do return false
	if edit.node >= 0 &&
	   edit.node < graph_document.node_count {beat := graph_document.nodes[edit.node].beat
		fields := [5]Graph_Field{.Node_Id, .Speaker, .Text, .Summary, .Duration}
		current := 0
		for field, i in fields do if field == edit.field do current = i
		next := (current + direction + len(fields)) % len(fields)
		field := fields[next]
		value := ""
		multiline := false
		#partial switch field {case .Node_Id:
			value = beat.id; case .Speaker:
			value = beat.speaker; case .Text:
			value = beat.text; multiline = true; case .Summary:
			value = beat.summary; multiline = true; case .Duration:
			value = fmt.tprintf("%.3f", beat.duration); case:}
		graph_begin_edit(field, value, edit.node, multiline)
		return true}
	return true}
