package main

import "core:fmt"
import "core:strings"

graph_feedback :: proc(message: string, error := false) {graph_state.feedback = message
	graph_state.feedback_error = error
	graph_state.feedback_frames = 240}

graph_unique_scene_id :: proc(base: string) -> string {candidate := base; suffix := 2
	for graph_scene_index(candidate) >= 0 {candidate = fmt.tprintf("%s_%d", base, suffix)
		suffix += 1}
	return candidate}
graph_add_scene :: proc() -> bool {if graph_document.scene_count >= GRAPH_MAX_SCENES do return false
	graph_history_push("Add scene")
	id := graph_unique_scene_id("scene_new")
	index := graph_document.scene_count
	graph_document.scenes[index] = {
		scene = {id = id, summary = "New conversation scene"},
		zoom = 1,
	}
	graph_document.scene_count += 1
	graph_state.active_scene = index
	graph_clear_selection()
	graph_changed()
	graph_feedback("SCENE ADDED")
	return true}
graph_duplicate_scene :: proc() -> bool {scene_index := graph_state.active_scene; if scene_index < 0 || scene_index >= graph_document.scene_count || graph_document.scene_count >= GRAPH_MAX_SCENES do return false
	old_scene := graph_document.scenes[scene_index].scene.id
	node_count := 0
	for node in graph_document.nodes[:graph_document.node_count] do if node.beat.scene == old_scene do node_count += 1
	if graph_document.node_count + node_count > GRAPH_MAX_NODES do return false
	graph_history_push("Duplicate scene")
	new_scene := graph_unique_scene_id(fmt.tprintf("%s_copy", old_scene))
	new_scene_index := graph_document.scene_count
	graph_document.scenes[new_scene_index] = graph_document.scenes[scene_index]
	graph_document.scenes[new_scene_index].scene.id = new_scene
	old_ids: [GRAPH_MAX_NODES]string
	new_ids: [GRAPH_MAX_NODES]string
	old_count := 0
	start := graph_document.node_count
	for 	node in graph_document.nodes[:start] {if node.beat.scene != old_scene do continue; copy_node := node
		copy_node.beat = graph_beat_clone(node.beat)
		copy_node.beat.scene = new_scene
		copy_node.beat.id = graph_unique_id(fmt.tprintf("%s_copy", node.beat.id), new_scene)
		old_ids[old_count] = node.beat.id
		new_ids[old_count] = copy_node.beat.id
		old_count += 1
		graph_document.nodes[graph_document.node_count] = copy_node
		graph_document.node_count += 1}
	remap := proc(value: string, old_ids, new_ids: []string) -> string {for old, i in old_ids do if value == old do return new_ids[i]
		return value}
	for 	i in start ..< graph_document.node_count {beat := &graph_document.nodes[i].beat; beat.next = remap(
			beat.next,
			old_ids[:old_count],
			new_ids[:old_count],
		)
		beat.success = remap(beat.success, old_ids[:old_count], new_ids[:old_count])
		beat.failure = remap(beat.failure, old_ids[:old_count], new_ids[:old_count])
		beat.cancel = remap(beat.cancel, old_ids[:old_count], new_ids[:old_count])
		for &target in beat.choice_targets do target = remap(target, old_ids[:old_count], new_ids[:old_count])}
	graph_document.scenes[new_scene_index].scene.entry = remap(
		graph_document.scenes[new_scene_index].scene.entry,
		old_ids[:old_count],
		new_ids[:old_count],
	)
	original_localizations := graph_document.localization_count
	for 	item in graph_document.localizations[:original_localizations] {for old, i in old_ids[:old_count] do if item.node_id == old && graph_document.localization_count < len(graph_document.localizations) {copy_item := item; copy_item.node_id = new_ids[i]; graph_document.localizations[graph_document.localization_count] = copy_item; graph_document.localization_count += 1}}
	graph_document.scene_count += 1
	graph_state.active_scene = new_scene_index
	graph_clear_selection()
	graph_changed()
	graph_feedback("SCENE DUPLICATED")
	return true}
graph_delete_scene :: proc() -> bool {scene_index := graph_state.active_scene
	if graph_document.scene_count <= 1 {graph_feedback("A STORY MUST KEEP AT LEAST ONE SCENE")
		return false}
	if scene_index < 0 || scene_index >= graph_document.scene_count do return false
	scene_id := graph_document.scenes[scene_index].scene.id
	graph_history_push("Delete scene")
	for i := graph_document.node_count - 1;
	    i >= 0;
	    i -= 1 {if graph_document.nodes[i].beat.scene != scene_id do continue
		node_id := graph_document.nodes[i].beat.id
		for j := graph_document.localization_count - 1;
		    j >= 0;
		    j -= 1 {if graph_document.localizations[j].node_id == node_id {for k in j + 1 ..< graph_document.localization_count do graph_document.localizations[k - 1] = graph_document.localizations[k]
				graph_document.localization_count -= 1}}
		for j in i + 1 ..< graph_document.node_count do graph_document.nodes[j - 1] = graph_document.nodes[j]
		graph_document.node_count -= 1}
	for &node in graph_document.nodes[:graph_document.node_count] do if node.beat.subscene_id == scene_id do node.beat.subscene_id = ""
	for i in scene_index + 1 ..< graph_document.scene_count do graph_document.scenes[i - 1] = graph_document.scenes[i]
	graph_document.scene_count -= 1
	graph_state.active_scene = clamp(scene_index, 0, max(0, graph_document.scene_count - 1))
	graph_state.confirm = .None
	graph_clear_selection()
	graph_changed()
	graph_feedback("SCENE DELETED")
	return true}
graph_move_scene :: proc(direction: int) -> bool {index := graph_state.active_scene; target :=
		index + direction
	if index < 0 || target < 0 || target >= graph_document.scene_count do return false
	graph_history_push("Reorder scene")
	graph_document.scenes[index], graph_document.scenes[target] =
		graph_document.scenes[target], graph_document.scenes[index]
	graph_state.active_scene = target
	graph_changed()
	return true}
graph_choice_add :: proc(node_index: int) -> bool {if node_index < 0 || node_index >= graph_document.node_count do return false
	beat := &graph_document.nodes[node_index].beat
	if beat.kind != "choice" || len(beat.choice_labels) >= STORY_MAX_NODE_CHOICES do return false
	graph_history_push("Add choice")
	count := len(beat.choice_labels)
	ids := make([]string, count + 1)
	labels := make([]string, count + 1)
	targets := make([]string, count + 1)
	conditions := make([]string, count + 1)
	copy(ids, beat.choice_ids)
	copy(labels, beat.choice_labels)
	copy(targets, beat.choice_targets)
	copy(conditions, beat.choice_conditions)
	ids[count] = graph_unique_choice_id(beat, fmt.tprintf("%s_choice_%d", beat.id, count + 1))
	labels[count] = "New choice"
	beat.choice_ids, beat.choice_labels, beat.choice_targets, beat.choice_conditions =
		ids, labels, targets, conditions
	graph_changed()
	return true}
graph_choice_delete :: proc(node_index, choice_index: int) -> bool {if node_index < 0 || node_index >= graph_document.node_count do return false
	beat := &graph_document.nodes[node_index].beat
	count := len(beat.choice_labels)
	if choice_index < 0 || choice_index >= count do return false
	graph_history_push("Delete choice")
	ids := make([]string, count - 1)
	labels := make([]string, count - 1)
	targets := make([]string, count - 1)
	conditions := make([]string, count - 1)
	out := 0
	for 	i in 0 ..< count {if i == choice_index do continue; if i < len(beat.choice_ids) do ids[out] = beat.choice_ids[i]
		labels[out] = beat.choice_labels[i]
		if i < len(beat.choice_targets) do targets[out] = beat.choice_targets[i]
		if i < len(beat.choice_conditions) do conditions[out] = beat.choice_conditions[i]
		out += 1}
	beat.choice_ids, beat.choice_labels, beat.choice_targets, beat.choice_conditions =
		ids, labels, targets, conditions
	graph_changed()
	return true}
graph_unique_choice_id :: proc(beat: ^Graph_Beat, base: string) -> string {candidate := base
	suffix := 2
	for {found := false; for id in beat.choice_ids do if id == candidate do found = true
		if !found do return candidate
		candidate = fmt.tprintf("%s_%d", base, suffix)
		suffix += 1}}
graph_choice_duplicate :: proc(node_index, choice_index: int) -> bool {if node_index < 0 || node_index >= graph_document.node_count do return false
	beat := &graph_document.nodes[node_index].beat
	if choice_index < 0 || choice_index >= len(beat.choice_labels) || len(beat.choice_labels) >= STORY_MAX_NODE_CHOICES do return false
	graph_history_push("Duplicate choice")
	count := len(beat.choice_labels)
	ids := make([]string, count + 1)
	labels := make([]string, count + 1)
	targets := make([]string, count + 1)
	conditions := make([]string, count + 1)
	for 	i in 0 ..< count {out := i; if i > choice_index do out += 1; ids[out] = beat.choice_ids[i]; labels[out] =
			beat.choice_labels[i]
		targets[out] = beat.choice_targets[i]
		conditions[out] = beat.choice_conditions[i]}
	out := choice_index + 1
	ids[out] = graph_unique_choice_id(beat, fmt.tprintf("%s_copy", beat.choice_ids[choice_index]))
	labels[out] = beat.choice_labels[choice_index]
	targets[out] = beat.choice_targets[choice_index]
	conditions[out] = beat.choice_conditions[choice_index]
	beat.choice_ids, beat.choice_labels, beat.choice_targets, beat.choice_conditions =
		ids, labels, targets, conditions
	graph_changed()
	return true}
graph_choice_swap :: proc(node_index, choice_index, target: int) -> bool {if node_index < 0 || node_index >= graph_document.node_count do return false
	beat := &graph_document.nodes[node_index].beat
	if choice_index < 0 || target < 0 || choice_index >= len(beat.choice_labels) || target >= len(beat.choice_labels) do return false
	beat.choice_ids[choice_index], beat.choice_ids[target] =
		beat.choice_ids[target], beat.choice_ids[choice_index]
	beat.choice_labels[choice_index], beat.choice_labels[target] =
		beat.choice_labels[target], beat.choice_labels[choice_index]
	beat.choice_targets[choice_index], beat.choice_targets[target] =
		beat.choice_targets[target], beat.choice_targets[choice_index]
	beat.choice_conditions[choice_index], beat.choice_conditions[target] =
		beat.choice_conditions[target], beat.choice_conditions[choice_index]
	return true}
graph_choice_move :: proc(node_index, choice_index, direction: int) -> bool {target :=
		choice_index + direction
	if node_index < 0 || node_index >= graph_document.node_count || target < 0 || target >= len(graph_document.nodes[node_index].beat.choice_labels) do return false
	graph_history_push("Reorder choice")
	if !graph_choice_swap(node_index, choice_index, target) do return false
	graph_changed()
	return true}

graph_choice_reorder_update :: proc(g: ^Game) {
	drag := &graph_state.choice_reorder; if !drag.active do return
	if drag.node < 0 ||
	   drag.node >= graph_document.node_count ||
	   graph_state.selected_node != drag.node {drag^ = {}; return}
	beat := &graph_document.nodes[drag.node].beat
	if g.input.mouse_down {
		target := clamp(int((g.input.mouse_pos.y - 184) / 48), 0, len(beat.choice_labels) - 1)
		if target != drag.index {
			if !drag.history_started {graph_history_push("Reorder choice"); drag.history_started = true}
			for drag.index !=
			    target {next := drag.index + (target > drag.index ? 1 : -1); _ = graph_choice_swap(drag.node, drag.index, next); drag.index = next}
		}
	}
	if g.input.mouse_released {changed := drag.history_started; drag^ = {}; if changed {graph_changed(); graph_feedback("CHOICE ORDER UPDATED  ·  CTRL/CMD Z TO UNDO")}}
}
graph_frame_nodes :: proc(selection_only := false) -> bool {scene := graph_active_scene_id()
	minimum := Vec2{1e30, 1e30}
	maximum := Vec2{-1e30, -1e30}
	count := 0
	for node, i in graph_document.nodes[:graph_document.node_count] {if node.beat.scene != scene || selection_only && !graph_is_selected(i) do continue
		minimum.x = min(minimum.x, node.position.x)
		minimum.y = min(minimum.y, node.position.y)
		maximum.x = max(maximum.x, node.position.x + GRAPH_NODE_WIDTH)
		maximum.y = max(maximum.y, node.position.y + graph_node_world_height(node))
		count += 1}
	if count == 0 do return false
	canvas := graph_canvas_rect()
	span_x := max(maximum.x - minimum.x, GRAPH_NODE_WIDTH)
	span_y := max(maximum.y - minimum.y, GRAPH_NODE_COLLAPSED_HEIGHT)
	graph_state.zoom = clamp(min((canvas.w - 48) / span_x, (canvas.h - 48) / span_y), .25, 1.75)
	center := Vec2{(minimum.x + maximum.x) * .5, (minimum.y + maximum.y) * .5}
	graph_state.pan = {
		canvas.x + (canvas.w * .5 - canvas.x) / graph_state.zoom - center.x,
		canvas.y + (canvas.h * .5 - canvas.y) / graph_state.zoom - center.y,
	}
	return true}
graph_auto_layout :: proc() -> bool {scene := graph_active_scene_id(); selected_only :=
		graph_state.selection_count > 0
	node_count := 0
	for node, i in graph_document.nodes[:graph_document.node_count] do if node.beat.scene == scene && (!selected_only || graph_is_selected(i)) do node_count += 1
	if node_count == 0 do return false
	graph_history_push(selected_only ? "Auto layout selection" : "Auto layout scene")
	column := 0
	row_y := f32(100)
	row_height := f32(0)
	for 	&node, i in graph_document.nodes[:graph_document.node_count] {if node.beat.scene != scene || selected_only && !graph_is_selected(i) do continue
		node.position = {
			260 + f32(column) * (GRAPH_NODE_WIDTH + GRAPH_NODE_LAYOUT_COLUMN_GAP),
			row_y,
		}
		row_height = max(row_height, graph_node_world_height(node))
		column += 1
		if column == 3 {column = 0; row_y += row_height + GRAPH_NODE_LAYOUT_ROW_GAP
			row_height = 0}}
	graph_changed()
	_ = graph_frame_nodes(selected_only)
	return true}

graph_minimap_focus :: proc(point: Vec2) -> bool {layout := graph_minimap_layout()
	if !layout.valid || !contains(graph_minimap_rect(), point) do return false
	clamped := Vec2 {
		clamp(point.x, layout.content.x, layout.content.x + layout.content.w),
		clamp(point.y, layout.content.y, layout.content.y + layout.content.h),
	}
	world := Vec2 {
		layout.world.x + (clamped.x - layout.content.x) / layout.scale,
		layout.world.y + (clamped.y - layout.content.y) / layout.scale,
	}
	canvas := graph_canvas_rect()
	graph_state.pan = {
		canvas.x + (canvas.w * .5 - canvas.x) / graph_state.zoom - world.x,
		canvas.y + (canvas.h * .5 - canvas.y) / graph_state.zoom - world.y,
	}
	return true}
graph_focus_search_result :: proc(direction: int) -> bool {query := strings.to_lower(
		strings.trim_space(graph_state.search_query),
	)
	if query == "" do return false
	matches: [GRAPH_MAX_NODES]int
	count := 0
	for 	node, i in graph_document.nodes[:graph_document.node_count] {haystack := strings.to_lower(
			fmt.tprintf(
				"%s %s %s %s %s",
				node.beat.scene,
				node.beat.id,
				node.beat.speaker,
				node.beat.text,
				node.beat.summary,
			),
		)
		if strings.contains(haystack, query) {matches[count] = i; count += 1}}
	if count == 0 {graph_feedback("NO MATCHING GRAPH BEATS", true); return false}
	graph_state.search_result = (graph_state.search_result + direction + count) % count
	index := matches[graph_state.search_result]
	scene := graph_scene_index(graph_document.nodes[index].beat.scene)
	if scene >= 0 do graph_state.active_scene = scene
	graph_select_only(index)
	_ = graph_frame_nodes(true)
	graph_feedback(fmt.tprintf("SEARCH %d OF %d", graph_state.search_result + 1, count))
	return true}
graph_node_order_move :: proc(index, direction: int) -> bool {if index < 0 || index >= graph_document.node_count do return false
	scene := graph_document.nodes[index].beat.scene
	target := index + direction
	for target >= 0 && target < graph_document.node_count && graph_document.nodes[target].beat.scene != scene do target += direction
	if target < 0 || target >= graph_document.node_count do return false
	graph_history_push("Reorder script beat")
	graph_document.nodes[index], graph_document.nodes[target] =
		graph_document.nodes[target], graph_document.nodes[index]
	graph_select_only(target)
	graph_changed()
	return true}
graph_add_condition :: proc() -> bool {if graph_document.condition_count >= GRAPH_MAX_DEFINITIONS do return false
	graph_history_push("Add condition")
	index := graph_document.condition_count
	id := fmt.tprintf("condition_%04d", index)
	for story_condition_index_in_document(id) >= 0 {index += 1; id = fmt.tprintf(
			"condition_%04d",
			index,
		)}
	item := Story_Condition {
		id   = id,
		kind = .Always,
	}
	if graph_document.condition_count < len(graph_document.conditions) do graph_document.conditions[graph_document.condition_count] = item
	else do append(&graph_document.conditions, item)
	graph_state.selected_condition = graph_document.condition_count
	graph_document.condition_count += 1
	graph_changed()
	return true}
graph_duplicate_condition :: proc() -> bool {index := graph_state.selected_condition; if index < 0 || index >= graph_document.condition_count || graph_document.condition_count >= GRAPH_MAX_DEFINITIONS do return false
	graph_history_push("Duplicate condition")
	item := graph_document.conditions[index]
	base := fmt.tprintf("%s_copy", item.id)
	item.id = base
	suffix := 2
	for story_condition_index_in_document(item.id) >= 0 {item.id = fmt.tprintf(
			"%s_%d",
			base,
			suffix,
		)
		suffix += 1}
	if graph_document.condition_count < len(graph_document.conditions) do graph_document.conditions[graph_document.condition_count] = item
	else do append(&graph_document.conditions, item)
	graph_state.selected_condition = graph_document.condition_count
	graph_document.condition_count += 1
	graph_changed()
	return true}
graph_duplicate_effect :: proc() -> bool {index := graph_state.selected_effect; if index < 0 || index >= graph_document.effect_count || graph_document.effect_count >= GRAPH_MAX_DEFINITIONS do return false
	graph_history_push("Duplicate effect")
	item := graph_document.effects[index]
	base := fmt.tprintf("%s_copy", item.id)
	item.id = base
	suffix := 2
	for story_effect_index_in_document(item.id) >= 0 {item.id = fmt.tprintf("%s_%d", base, suffix)
		suffix += 1}
	if graph_document.effect_count < len(graph_document.effects) do graph_document.effects[graph_document.effect_count] = item
	else do append(&graph_document.effects, item)
	graph_state.selected_effect = graph_document.effect_count
	graph_document.effect_count += 1
	graph_changed()
	return true}
story_condition_index_in_document :: proc(id: string) -> int {for item, i in graph_document.conditions[:graph_document.condition_count] do if item.id == id do return i
	return -1}
story_effect_index_in_document :: proc(id: string) -> int {for item, i in graph_document.effects[:graph_document.effect_count] do if item.id == id do return i
	return -1}
graph_add_effect :: proc() -> bool {if graph_document.effect_count >= GRAPH_MAX_DEFINITIONS do return false
	graph_history_push("Add effect")
	suffix := graph_document.effect_count
	id := fmt.tprintf("effect_%04d", suffix)
	for story_effect_index_in_document(id) >= 0 {suffix += 1; id = fmt.tprintf(
			"effect_%04d",
			suffix,
		)}
	item := Story_Effect {
		id   = id,
		kind = .Emit_Event,
	}
	if graph_source_project != nil && len(graph_source_project.events) > 0 do item.event_id = graph_source_project.events[0].id
	if graph_document.effect_count < len(graph_document.effects) do graph_document.effects[graph_document.effect_count] = item
	else do append(&graph_document.effects, item)
	graph_state.selected_effect = graph_document.effect_count
	graph_document.effect_count += 1
	graph_changed()
	return true}
graph_condition_referenced :: proc(id: string) -> bool {for 	node in graph_document.nodes[:graph_document.node_count] {if node.beat.condition_id == id do return true
		for choice in node.beat.choice_conditions do if choice == id do return true}
	for &condition in graph_document.conditions[:graph_document.condition_count] do for child in condition.child_ids[:condition.child_id_count] do if child == id do return true
	return false}
graph_effect_referenced :: proc(id: string) -> bool {for node in graph_document.nodes[:graph_document.node_count] do for effect in node.beat.effect_ids do if effect == id do return true
	return false}
graph_delete_condition :: proc() -> bool {index := graph_state.selected_condition; if index < 0 || index >= graph_document.condition_count do return false
	id := graph_document.conditions[index].id
	if graph_condition_referenced(id) {graph_feedback("CONDITION IS STILL REFERENCED", true)
		return false}
	graph_history_push("Delete condition")
	for i in index + 1 ..< graph_document.condition_count do graph_document.conditions[i - 1] = graph_document.conditions[i]
	graph_document.condition_count -= 1
	graph_state.selected_condition = clamp(index, 0, max(0, graph_document.condition_count - 1))
	graph_changed()
	return true}
graph_delete_effect :: proc() -> bool {index := graph_state.selected_effect; if index < 0 || index >= graph_document.effect_count do return false
	id := graph_document.effects[index].id
	if graph_effect_referenced(id) {graph_feedback("EFFECT IS STILL REFERENCED", true); return(
			false \
		)}
	graph_history_push("Delete effect")
	for i in index + 1 ..< graph_document.effect_count do graph_document.effects[i - 1] = graph_document.effects[i]
	graph_document.effect_count -= 1
	graph_state.selected_effect = clamp(index, 0, max(0, graph_document.effect_count - 1))
	graph_changed()
	return true}
graph_add_localization :: proc() -> bool {node := graph_state.selected_node; if node < 0 || node >= graph_document.node_count || graph_document.localization_count >= len(graph_document.localizations) do return false
	graph_history_push("Add localization")
	graph_document.localizations[graph_document.localization_count] = {
		node_id  = graph_document.nodes[node].beat.id,
		language = "und",
		status   = "draft",
	}
	graph_state.selected_localization = graph_document.localization_count
	graph_document.localization_count += 1
	graph_changed()
	return true}
graph_delete_localization :: proc() -> bool {index := graph_state.selected_localization; if index < 0 || index >= graph_document.localization_count do return false
	graph_history_push("Delete localization")
	for i in index + 1 ..< graph_document.localization_count do graph_document.localizations[i - 1] = graph_document.localizations[i]
	graph_document.localization_count -= 1
	graph_state.selected_localization = clamp(
		index,
		0,
		max(0, graph_document.localization_count - 1),
	)
	graph_changed()
	return true}

graph_metadata_read_refs :: proc(
	payload: ^Mystery_Project,
	refs: []string,
	clues, claims, topics: ^[]string,
) {clue_values := make([dynamic]string, 0, len(refs)); claim_values := make(
		[dynamic]string,
		0,
		len(refs),
	)
	topic_values := make([dynamic]string, 0, len(refs))
	for 	id in refs {if mystery_clue_index(payload, id) >= 0 do append(&clue_values, id)
		else if mystery_claim_index(payload, id) >= 0 do append(&claim_values, id)
		else do append(&topic_values, id)}
	clues^ = clue_values[:]
	claims^ = claim_values[:]
	topics^ = topic_values[:]}
