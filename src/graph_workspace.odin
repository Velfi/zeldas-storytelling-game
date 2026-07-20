package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"

graph_set_picker_create_callback :: proc(
	callback: Graph_Picker_Create_Callback,
	userdata: rawptr,
) {graph_picker_create_callback = callback; graph_picker_create_userdata = userdata}
graph_picker_create :: proc(
	field: Graph_Field,
	suggested_id: string,
) -> bool {if graph_picker_create_callback == nil do return false; id, ok :=
		graph_picker_create_callback(field, suggested_id, graph_picker_create_userdata)
	if !ok || id == "" do return false
	graph_state.field_edit.count = 0
	graph_edit_append(id)
	return graph_commit_edit()}

graph_inspector_viewport :: proc() -> Rect {return {950, 76, 250, 354}}
graph_inspector_scrolled_rect :: proc(box: Rect) -> Rect {result := box; result.y -=
		graph_state.inspector_scroll
	return result}

GRAPH_NODE_INSPECTOR_FIELDS :: [39]Graph_Field {
	.Node_Id,
	.Node_Scene,
	.Node_Kind,
	.Line_Id,
	.Speaker,
	.Text,
	.Next,
	.Success,
	.Failure,
	.Cancel,
	.Subscene,
	.UI,
	.Camera,
	.Actor,
	.Actor_Mark,
	.Animation,
	.UI_Image_Asset,
	.Sound_Cue_Asset,
	.Animation_Asset,
	.Summary,
	.Ending,
	.Domain_Ref,
	.Event,
	.Duration,
	.Transition,
	.Blocking,
	.Condition,
	.Effects,
	.Condition_Root,
	.First_Effect,
	.Effect_Count,
	.Interaction,
	.Clue,
	.Requires_Clues,
	.Requires_Claims,
	.Requires_Topics,
	.Unlock_Clues,
	.Unlock_Claims,
	.Unlock_Topics,
}
GRAPH_SCENE_INSPECTOR_FIELDS :: [5]Graph_Field {
	.Scene_Id,
	.Scene_Display_Name,
	.Scene_Bound_Entity,
	.Scene_Summary,
	.Scene_Return,
}

graph_inspector_field :: proc() -> Graph_Field {fields := GRAPH_NODE_INSPECTOR_FIELDS; return(
		fields[clamp(graph_state.inspector_field_index, 0, len(fields) - 1)] \
	)}
graph_inspector_field_label :: proc(field: Graph_Field) -> string {#partial switch
	field {case .Node_Id:
		return "NODE ID"; case .Node_Scene:
		return "SCENE"; case .Node_Kind:
		return "KIND"; case .Line_Id:
		return "LINE ID"; case .Speaker:
		return "SPEAKER"; case .Text:
		return "TEXT"; case .Next:
		return "NEXT"; case .Success:
		return "SUCCESS"; case .Failure:
		return "FAILURE"; case .Cancel:
		return "CANCEL"; case .Subscene:
		return "SUBSCENE"; case .UI:
		return "UI"; case .Camera:
		return "CAMERA"; case .Actor:
		return "ACTOR"; case .Actor_Mark:
		return "ACTOR MARK"; case .Animation:
		return "ANIMATION"; case .UI_Image_Asset:
		return "UI IMAGE ASSET"; case .Sound_Cue_Asset:
		return "SOUND CUE ASSET"; case .Animation_Asset:
		return "ANIMATION ASSET"; case .Summary:
		return "SUMMARY"; case .Ending:
		return "ENDING"; case .Domain_Ref:
		return "DOMAIN REF"; case .Event:
		return "EVENT"; case .Duration:
		return "DURATION"; case .Transition:
		return "TRANSITION"; case .Blocking:
		return "BLOCKING"; case .Condition:
		return "CONDITION"; case .Effects:
		return "EFFECTS"; case .Condition_Root:
		return "CONDITION ROOT"; case .First_Effect:
		return "FIRST EFFECT"; case .Effect_Count:
		return "EFFECT COUNT"; case .Interaction:
		return "INTERACTION"; case .Clue:
		return "CLUE"; case .Requires_Clues:
		return "REQUIRES CLUES"; case .Requires_Claims:
		return "REQUIRES CLAIMS"; case .Requires_Topics:
		return "REQUIRES TOPICS"; case .Unlock_Clues:
		return "UNLOCK CLUES"; case .Unlock_Claims:
		return "UNLOCK CLAIMS"; case .Unlock_Topics:
		return "UNLOCK TOPICS"}
	return "FIELD"}
graph_inspector_field_value :: proc(
	beat: ^Graph_Beat,
	field: Graph_Field,
) -> string {#partial switch field {case .Node_Id:
		return beat.id; case .Node_Scene:
		return beat.scene; case .Node_Kind:
		return beat.kind; case .Line_Id:
		return beat.line_id; case .Speaker:
		return beat.speaker; case .Text:
		return beat.text; case .Next:
		return beat.next; case .Success:
		return beat.success; case .Failure:
		return beat.failure; case .Cancel:
		return beat.cancel; case .Subscene:
		return beat.subscene_id; case .UI:
		return beat.ui; case .Camera:
		return beat.camera; case .Actor:
		return beat.actor; case .Actor_Mark:
		return beat.actor_mark; case .Animation:
		return beat.animation; case .UI_Image_Asset:
		return beat.ui_image_asset_ref; case .Sound_Cue_Asset:
		return beat.sound_cue_asset_ref; case .Animation_Asset:
		return beat.animation_asset_ref; case .Summary:
		return beat.summary; case .Ending:
		return beat.ending; case .Domain_Ref:
		return beat.domain_ref; case .Event:
		return beat.event_id; case .Duration:
		return fmt.tprintf("%.3f", beat.duration); case .Transition:
		return fmt.tprintf("%.3f", beat.transition); case .Blocking:
		return beat.blocking ? "true" : "false"; case .Condition:
		return beat.condition_id; case .Effects:
		return graph_join_strings(beat.effect_ids); case .Condition_Root:
		return fmt.tprintf("%d", beat.condition_root); case .First_Effect:
		return fmt.tprintf("%d", beat.first_effect); case .Effect_Count:
		return fmt.tprintf("%d", beat.effect_count); case .Interaction:
		return beat.interaction; case .Clue:
		return beat.clue; case .Requires_Clues:
		return graph_join_strings(beat.requires_clues); case .Requires_Claims:
		return graph_join_strings(beat.requires_claims); case .Requires_Topics:
		return graph_join_strings(beat.requires_topics); case .Unlock_Clues:
		return graph_join_strings(beat.unlock_clues); case .Unlock_Claims:
		return graph_join_strings(beat.unlock_claims); case .Unlock_Topics:
		return graph_join_strings(beat.unlock_topics)}; return ""}
graph_inspector_field_multiline :: proc(field: Graph_Field) -> bool {return(
		field == .Text ||
		field == .Summary ||
		field == .Effects ||
		(field >= .Requires_Clues && field <= .Unlock_Topics) \
	)}
graph_scene_inspector_field :: proc() -> Graph_Field {fields := GRAPH_SCENE_INSPECTOR_FIELDS
	return fields[clamp(graph_state.inspector_field_index, 0, len(fields) - 1)]}
graph_scene_inspector_label :: proc(field: Graph_Field) -> string {#partial switch
	field {case .Scene_Id:
		return "SCENE ID"; case .Scene_Display_Name:
		return "DISPLAY NAME"; case .Scene_Bound_Entity:
		return "BOUND ENTITY"; case .Scene_Summary:
		return "SUMMARY"; case .Scene_Return:
		return "RETURN TARGET"}
	return "SCENE FIELD"}
graph_scene_inspector_value :: proc(
	scene: ^Graph_Scene_Data,
	field: Graph_Field,
) -> string {#partial switch field {case .Scene_Id:
		return scene.id; case .Scene_Display_Name:
		return scene.display_name; case .Scene_Bound_Entity:
		return scene.source; case .Scene_Summary:
		return scene.summary; case .Scene_Return:
		return scene.return_to}; return ""}

graph_set_document_paths :: proc(source_path, autosave_path: string) -> bool {
	source := strings.trim_space(source_path)
	autosave := strings.trim_space(autosave_path)
	if source == "" || autosave == "" || source == autosave do return false
	graph_active_source_path = source
	graph_active_autosave_path = autosave
	graph_active_layout_path = fmt.tprintf("%s.layout", source)
	return true
}

graph_set_layout_path :: proc(path: string) -> bool {value := strings.trim_space(path); if value == "" do return false
	graph_active_layout_path = value
	return true}
graph_layout_serialize :: proc() -> string {text := fmt.tprintf(
		"case\t%s\n",
		graph_document.case_id,
	)
	for scene in graph_document.scenes[:graph_document.scene_count] do text = fmt.tprintf("%sscene\t%s\t%.3f\t%.3f\t%.3f\n", text, scene.scene.id, scene.pan.x, scene.pan.y, scene.zoom)
	for node in graph_document.nodes[:graph_document.node_count] do text = fmt.tprintf("%snode\t%s\t%s\t%.3f\t%.3f\t%d\n", text, node.beat.scene, node.beat.id, node.position.x, node.position.y, node.collapsed ? 1 : 0)
	return text}
graph_layout_save :: proc() -> Validation {if graph_active_layout_path == "" do return {false, "graph layout path is not configured"}
	if os.write_entire_file(graph_active_layout_path, transmute([]u8)graph_layout_serialize()) != nil do return {false, "could not write graph layout"}
	return{true, "GRAPH LAYOUT SAVED"}}
graph_layout_load :: proc() -> Validation {if graph_active_layout_path == "" do return {false, "graph layout path is not configured"}
	data, error := os.read_entire_file_from_path(graph_active_layout_path, context.temp_allocator)
	if error != nil do return {false, "graph layout is unavailable"}
	for 	line in strings.split(string(data), "\n") {parts := strings.split(line, "\t"); if len(parts) == 0 do continue
		if parts[0] == "case" && len(parts) >= 2 && parts[1] != graph_document.case_id do return {false, "graph layout belongs to another case"}
		if parts[0] == "scene" && len(parts) >= 5 {index := graph_scene_index(parts[1]); x, x_ok :=
				strconv.parse_f32(parts[2])
			y, y_ok := strconv.parse_f32(parts[3])
			zoom, z_ok := strconv.parse_f32(parts[4])
			if index >= 0 && x_ok && y_ok && z_ok {graph_document.scenes[index].pan = {x, y}
				graph_document.scenes[index].zoom = zoom}}
		if parts[0] == "node" && len(parts) >= 6 {index := graph_node_index(parts[1], parts[2])
			x, x_ok := strconv.parse_f32(parts[3])
			y, y_ok := strconv.parse_f32(parts[4])
			if index >= 0 && x_ok && y_ok {graph_document.nodes[index].position = {x, y}
				graph_document.nodes[index].collapsed = parts[5] == "1"}}}
	return{true, "GRAPH LAYOUT LOADED"}}

graph_document_paths :: proc() -> (source_path, autosave_path: string) {
	return graph_active_source_path, graph_active_autosave_path
}

graph_kind_color :: proc(kind: string) -> [4]u8 {switch kind {case "line":
		return {82, 158, 220, 255}; case "choice":
		return {226, 173, 64, 255}; case "check":
		return {174, 116, 215, 255}; case "stage":
		return {65, 194, 210, 255}; case "interaction":
		return {80, 181, 119, 255}; case "end":
		return {198, 91, 91, 255}}; return {135, 142, 151, 255}}
graph_kind_label :: proc(kind: string) -> string {return strings.to_upper(kind)}
graph_world_to_screen :: proc(point: Vec2) -> Vec2 {canvas := graph_canvas_rect(); return{
		canvas.x + (point.x + graph_state.pan.x - canvas.x) * graph_state.zoom,
		canvas.y + (point.y + graph_state.pan.y - canvas.y) * graph_state.zoom,
	}}
graph_screen_to_world :: proc(point: Vec2) -> Vec2 {canvas := graph_canvas_rect(); zoom := max(
		graph_state.zoom,
		.01,
	)
	return{
		canvas.x + (point.x - canvas.x) / zoom - graph_state.pan.x,
		canvas.y + (point.y - canvas.y) / zoom - graph_state.pan.y,
	}}
GRAPH_NODE_WIDTH :: f32(190)
GRAPH_NODE_COLLAPSED_HEIGHT :: f32(36)
GRAPH_NODE_HEADER_HEIGHT :: f32(24)
GRAPH_NODE_BODY_MIN_HEIGHT :: f32(48)
GRAPH_NODE_OUTPUT_ROW_HEIGHT :: f32(18)
GRAPH_NODE_OUTPUT_PADDING :: f32(14)
GRAPH_NODE_LAYOUT_COLUMN_GAP :: f32(30)
GRAPH_NODE_LAYOUT_ROW_GAP :: f32(33)

graph_node_world_height :: proc(node: Graph_Node) -> f32 {
	if node.collapsed do return GRAPH_NODE_COLLAPSED_HEIGHT
	beat := node.beat
	outputs := max(1, graph_output_count(&beat))
	body_height := max(
		GRAPH_NODE_BODY_MIN_HEIGHT,
		GRAPH_NODE_OUTPUT_PADDING + f32(outputs) * GRAPH_NODE_OUTPUT_ROW_HEIGHT,
	)
	return GRAPH_NODE_HEADER_HEIGHT + body_height
}
graph_node_rect :: proc(node: Graph_Node) -> Rect {p := graph_world_to_screen(node.position)
	return {
		p.x,
		p.y,
		GRAPH_NODE_WIDTH * graph_state.zoom,
		graph_node_world_height(node) * graph_state.zoom,
	}}
graph_canvas_rect :: proc() -> Rect {return {220, 62, 724, 612}}
graph_scene_rect :: proc(index: int) -> Rect {return {14, 96 + f32(index) * 34, 192, 30}}
graph_scene_window_start :: proc() -> int {return clamp(
		graph_state.active_scene - 3,
		0,
		max(0, graph_document.scene_count - 8),
	)}
graph_palette_rect :: proc(index: int) -> Rect {return{
		14 + f32(index % 2) * 98,
		408 + f32(index / 2) * 36,
		94,
		30,
	}}
graph_quick_rect :: proc(index: int) -> Rect {return{
		graph_state.quick_add_at.x,
		graph_state.quick_add_at.y + 34 + f32(index) * 27,
		176,
		25,
	}}
graph_search_rect :: proc() -> Rect {return {748, 682, 116, 28}}
graph_search_next_rect :: proc() -> Rect {return {870, 682, 68, 28}}
graph_minimap_rect :: proc() -> Rect {canvas := graph_canvas_rect(); return{
		canvas.x + canvas.w - 154,
		canvas.y + canvas.h - 112,
		142,
		100,
	}}
graph_minimap_layout :: proc() -> Graph_Minimap_Layout {
	box := graph_minimap_rect(

	); scene := graph_active_scene_id(); minimum := Vec2{1e30, 1e30}; maximum := Vec2{-1e30, -1e30}; count := 0
	for node in graph_document.nodes[:graph_document.node_count] {if node.beat.scene != scene do continue; minimum.x = min(minimum.x, node.position.x); minimum.y = min(minimum.y, node.position.y); maximum.x = max(maximum.x, node.position.x + GRAPH_NODE_WIDTH); maximum.y = max(maximum.y, node.position.y + graph_node_world_height(node)); count += 1}
	if count == 0 do return {}
	padding := f32(
		36,
	); world := Rect{minimum.x - padding, minimum.y - padding, max(f32(1), maximum.x - minimum.x + padding * 2), max(f32(1), maximum.y - minimum.y + padding * 2)}; inner := Rect{box.x + 5, box.y + 5, box.w - 10, box.h - 10}; scale := min(inner.w / world.w, inner.h / world.h); content := Rect{inner.x + (inner.w - world.w * scale) * .5, inner.y + (inner.h - world.h * scale) * .5, world.w * scale, world.h * scale}; return {true, world, content, scale}
}
graph_minimap_project :: proc(layout: Graph_Minimap_Layout, point: Vec2) -> Vec2 {return{
		layout.content.x + (point.x - layout.world.x) * layout.scale,
		layout.content.y + (point.y - layout.world.y) * layout.scale,
	}}
graph_edit_rect :: proc() -> Rect {return {958, 104, 234, 38}}
graph_picker_rect :: proc(index: int) -> Rect {return {958, 146 + f32(index) * 30, 234, 28}}
graph_tab_bar_rect :: proc() -> Rect {return {218, 8, 576, 48}}
graph_view_tab_rect :: proc(index: int) -> Rect {return {226 + f32(index) * 112, 12, 112, 42}}
graph_node_index :: proc(scene, id: string) -> int {for node, i in graph_document.nodes[:graph_document.node_count] do if node.beat.scene == scene && node.beat.id == id do return i
	return -1}
graph_document_node_index :: proc(doc: ^Graph_Document, scene, id: string) -> int {for node, i in doc.nodes[:doc.node_count] do if node.beat.scene == scene && node.beat.id == id do return i
	return -1}
graph_scene_index :: proc(id: string) -> int {for scene, i in graph_document.scenes[:graph_document.scene_count] do if scene.scene.id == id do return i
	return -1}
graph_active_scene_id :: proc() -> string {if graph_state.active_scene < 0 || graph_state.active_scene >= graph_document.scene_count do return ""
	return graph_document.scenes[graph_state.active_scene].scene.id}
graph_is_selected :: proc(index: int) -> bool {for value in graph_state.selection[:graph_state.selection_count] do if value == index do return true
	return false}
graph_clear_selection :: proc() {graph_state.selection_count = 0; graph_state.selected_node = -1
	graph_state.edge_selection = {}
	graph_state.inspector_scroll = 0
	graph_state.inspector_scroll_max = 0
	graph_state.choice_page = 0}
graph_select_only :: proc(index: int) {graph_clear_selection(); if index >=
	   0 {graph_state.selection[0] = index; graph_state.selection_count = 1
		graph_state.selected_node = index}}
graph_toggle_selection :: proc(index: int) {for value, i in graph_state.selection[:graph_state.selection_count] do if value == index {for j in i + 1 ..< graph_state.selection_count do graph_state.selection[j - 1] = graph_state.selection[j]; graph_state.selection_count -= 1; graph_state.selected_node = graph_state.selection_count > 0 ? graph_state.selection[graph_state.selection_count - 1] : -1; return}
	if graph_state.selection_count < GRAPH_SELECTION_CAPACITY {graph_state.selection[graph_state.selection_count] =
			index
		graph_state.selection_count += 1
		graph_state.selected_node = index}}
graph_unique_id :: proc(base, scene: string) -> string {candidate := base; if candidate == "" do candidate = "node"
	suffix := 2
	for {found := false; for node in graph_document.nodes[:graph_document.node_count] do if node.beat.id == candidate do found = true
		if !found do return candidate
		candidate = fmt.tprintf("%s_%d", base, suffix)
		suffix += 1}}
graph_port_target :: proc(
	beat: ^Graph_Beat,
	port: Graph_Port_Kind,
	choice_index: int,
) -> ^string {#partial switch port {case .Next:
		return &beat.next; case .Success:
		return &beat.success; case .Failure:
		return &beat.failure; case .Cancel:
		return &beat.cancel; case .Choice:
		if choice_index >= 0 && choice_index < len(beat.choice_targets) do return &beat.choice_targets[choice_index]}; return nil}
graph_port_color :: proc(port: Graph_Port_Kind) -> [4]u8 {#partial switch port {case .Next:
		return {82, 158, 220, 255}; case .Success:
		return {80, 181, 119, 255}; case .Failure:
		return {198, 91, 91, 255}; case .Cancel:
		return {135, 142, 151, 255}; case .Choice:
		return {226, 173, 64, 255}}; return {220, 226, 232, 255}}
graph_output_count :: proc(beat: ^Graph_Beat) -> int {if beat.kind == "choice" do return len(beat.choice_labels)
	if beat.kind == "check" do return 2
	if beat.kind == "interaction" do return beat.cancel != "" ? 2 : 1
	if beat.kind == "end" do return 0
	return 1}
graph_output_port :: proc(
	beat: ^Graph_Beat,
	index: int,
) -> (
	Graph_Port_Kind,
	int,
) {if beat.kind == "choice" do return .Choice, index; if beat.kind == "check" do return index == 0 ? .Success : .Failure, -1
	if beat.kind == "interaction" do return index == 0 ? .Success : .Cancel, -1
	return .Next, -1}
graph_port_rect :: proc(node: Graph_Node, index: int) -> Rect {box := graph_node_rect(node)
	beat := node.beat
	count := max(1, graph_output_count(&beat))
	header := min(box.h, f32(24) * graph_state.zoom)
	body := box.h - header
	y := header + box.y + (f32(index) + .5) * body / f32(count)
	size := f32(10) * graph_state.zoom
	return {box.x + box.w - size * .5, y - size * .5, size, size}}
graph_input_rect :: proc(node: Graph_Node) -> Rect {box := graph_node_rect(node); size :=
		f32(10) * graph_state.zoom
	header := min(box.h, f32(24) * graph_state.zoom)
	y := box.y + header + (box.h - header) * .5
	return{box.x - size * .5, y - size * .5, size, size}}
graph_rect_normalized :: proc(a, b: Vec2) -> Rect {return{
		min(a.x, b.x),
		min(a.y, b.y),
		math.abs(b.x - a.x),
		math.abs(b.y - a.y),
	}}
graph_rects_overlap :: proc(a, b: Rect) -> bool {return(
		a.x <= b.x + b.w &&
		a.x + a.w >= b.x &&
		a.y <= b.y + b.h &&
		a.y + a.h >= b.y \
	)}
graph_point_segment_distance :: proc(p, a, b: Vec2) -> f32 {dx, dy := b.x - a.x, b.y - a.y
	length := dx * dx + dy * dy
	if length <= .001 do return math.sqrt((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y))
	t := clamp(((p.x - a.x) * dx + (p.y - a.y) * dy) / length, 0, 1)
	x, y := a.x + t * dx, a.y + t * dy
	return math.sqrt((p.x - x) * (p.x - x) + (p.y - y) * (p.y - y))}
graph_edge_hit :: proc(point: Vec2) -> Graph_Edge_Selection {scene := graph_active_scene_id(); for 	&node, i in graph_document.nodes[:graph_document.node_count] {if node.beat.scene != scene do continue; for 		port_index in 0 ..< graph_output_count(&node.beat) {port, choice := graph_output_port(&node.beat, port_index)
			target := graph_port_target(&node.beat, port, choice)
			if target == nil || target^ == "" do continue
			to := graph_node_index(scene, target^)
			if to >= 0 && graph_rendered_edge_hit(point, scene, i, to, port_index) do return {active = true, node = i, port = port, choice_index = choice}}}
	return{}}

graph_field_is_picker :: proc(field: Graph_Field) -> bool {#partial switch
	field {case .Speaker,
	            .Camera,
	            .Actor,
	            .Actor_Mark,
	            .Interaction,
	            .Event,
	            .Subscene,
	            .Condition,
	            .Effects,
	            .Clue,
	            .Ending,
	            .UI,
	            .Scene_Return:
		return true
	case:
		return false}}
graph_begin_picker :: proc(field: Graph_Field, value: string, node := -1) {graph_begin_edit(
		field,
		"",
		node,
	)
	graph_state.field_edit.picker = true
	graph_state.field_edit.picker_selected = 0}
graph_picker_candidate_raw :: proc(
	g: ^Game,
	field: Graph_Field,
	index: int,
) -> string {#partial switch field {case .Speaker, .Actor:
		if index == 0 do return "narrator"; if index == 1 do return "detective"
		wanted := index - 2
		seen := 0
		if g.story_project !=
		   nil {for entity in g.story_project.entities do if entity.kind == "character" {if seen == wanted do return entity.id; seen += 1}}
	case .Clue:
		payload := mystery_game_payload(g)
		if payload != nil && index >= 0 && index < len(payload.clues) do return payload.clues[index].id
	case .Ending:
		if g.story_project != nil && index >= 0 && index < len(g.story_project.endings) do return g.story_project.endings[index].id
	case .Camera, .Actor_Mark:
		seen := 0
		wanted := field == .Camera ? Level_Marker_Kind.Camera : Level_Marker_Kind.Staging
		for marker in level_document.markers do if marker.story == level_document.active_story && marker.kind == wanted {if seen == index do return marker.id; seen += 1}
	case .Interaction:
		seen := 0
		for marker in level_document.markers do if marker.story == level_document.active_story && marker.kind == .Interaction && marker.reference != "" {if seen == index do return marker.reference; seen += 1}
	case .Event:
		seen := 0
		for marker in level_document.markers do if marker.story == level_document.active_story && marker.kind == .Trigger && marker.reference != "" {duplicate := false; for earlier in level_document.markers {if earlier.id == marker.id do break; if earlier.story == marker.story && earlier.kind == .Trigger && earlier.reference == marker.reference do duplicate = true}; if duplicate do continue; if seen == index do return marker.reference; seen += 1}
	case .Subscene:
		if index >= 0 && index < graph_document.scene_count do return graph_document.scenes[index].scene.id
	case .Condition:
		if graph_source_project != nil && index >= 0 && index < len(graph_source_project.conditions) do return graph_source_project.conditions[index].id
	case .Effects:
		if index >= 0 && index < graph_document.effect_count do return graph_document.effects[index].id
	case .UI:
		values := [3]string{"dialogue", "hidden", "unchanged"}
		if index >= 0 && index < len(values) do return values[index]
	case .Scene_Return:
		if index == 0 do return "investigation"; j := index - 1
		if j >= 0 && j < graph_document.scene_count do return graph_document.scenes[j].scene.id
	case:}; return ""}
graph_picker_search_text :: proc(field: Graph_Field, value: string) -> string {if field == .Camera || field == .Actor_Mark do return value
	if field == .Interaction {for marker in level_document.markers do if marker.story == level_document.active_story && marker.kind == .Interaction && marker.reference == value do return fmt.tprintf("%s %s", value, marker.id)}
	if field == .Event {for marker in level_document.markers do if marker.story == level_document.active_story && marker.kind == .Trigger && marker.reference == value do return fmt.tprintf("%s %s", value, marker.id)}
	return value}
graph_picker_candidate :: proc(
	g: ^Game,
	field: Graph_Field,
	filtered_index: int,
) -> string {query := strings.to_lower(graph_edit_text()); seen := 0; for 	raw in 0 ..< 512 {value := graph_picker_candidate_raw(g, field, raw); if value == "" {if raw > 64 do break
			continue}
		if query != "" && !strings.contains(strings.to_lower(graph_picker_search_text(field, value)), query) do continue
		if seen == filtered_index do return value
		seen += 1}
	return ""}
graph_picker_count :: proc(g: ^Game, field: Graph_Field) -> int {count := 0; for count < 512 && graph_picker_candidate(g, field, count) != "" do count += 1
	return count}
graph_picker_navigation_step :: proc(selected, count: int, up, down: bool) -> int {result :=
		selected
	if down do result = min(result + 1, max(0, count - 1))
	if up do result = max(0, result - 1)
	return result}
graph_picker_label :: proc(g: ^Game, field: Graph_Field, index: int) -> string {value :=
		graph_picker_candidate(g, field, index)
	if value == "" do return ""
	wanted :=
		field == .Camera ? Level_Marker_Kind.Camera : field == .Actor_Mark ? Level_Marker_Kind.Staging : field == .Interaction ? Level_Marker_Kind.Interaction : field == .Event ? Level_Marker_Kind.Trigger : Level_Marker_Kind.Player_Spawn
	if field == .Camera || field == .Actor_Mark {for marker in level_document.markers do if marker.story == level_document.active_story && marker.kind == wanted && marker.id == value do return fmt.tprintf("%s  ·  STORY %d", value, marker.story + 1)}
	else if field == .Interaction || field == .Event {for marker in level_document.markers do if marker.story == level_document.active_story && marker.kind == wanted && marker.reference == value do return fmt.tprintf("%s  ·  %s", value, strings.to_upper(marker.id))}
	return value}
graph_node_spatial_marker :: proc(node: ^Graph_Node) -> (string, bool) {
	if node.beat.camera != "" do return node.beat.camera, true
	if node.beat.actor_mark != "" do return node.beat.actor_mark, true
	if node.beat.interaction !=
	   "" {for marker in level_document.markers do if marker.kind == .Interaction && marker.reference == node.beat.interaction do return marker.id, true}
	if node.beat.event_id !=
	   "" {for marker in level_document.markers do if marker.kind == .Trigger && marker.reference == node.beat.event_id do return marker.id, true}
	return "", false
}
graph_open_selected_in_build :: proc(g: ^Game) -> bool {
	if graph_state.selected_node < 0 ||
	   graph_state.selected_node >=
		   graph_document.node_count {graph_feedback("SELECT A NODE WITH A SPATIAL BINDING", true); return false}
	id, found := graph_node_spatial_marker(
		&graph_document.nodes[graph_state.selected_node],
	); if !found {graph_feedback("THIS NODE HAS NO SPATIAL BINDING", true); return false}
	index := level_marker_index(
		&level_document,
		id,
	); if index < 0 {graph_feedback(fmt.tprintf("SPATIAL MARKER NOT FOUND  ·  %s", strings.to_upper(id)), true); return false}
	marker :=
		level_document.markers[index]; level_document.active_story = marker.story; editor_state.view = .Markers; g.top_down_camera = true; g.build_tool = .Marker; editor_state.selection_count = 1; editor_state.selection[0] = {.Marker, marker.id, -1}; g.editor_mode = .Build; g.move_target_active = false; _ = editor_frame_selection(g); editor_show_feedback(fmt.tprintf("OPENED FROM GRAPH  ·  %s", strings.to_upper(marker.id))); return true
}
graph_picker_apply :: proc(g: ^Game, index: int) -> bool {value := graph_picker_candidate(
		g,
		graph_state.field_edit.field,
		index,
	)
	if value == "" do return false
	graph_state.field_edit.count = 0
	graph_edit_append(value)
	return graph_commit_edit()}

graph_script_row_rect :: proc(row: int) -> Rect {return {238, 92 + f32(row) * 70, 682, 64}}
graph_localization_row_rect :: proc(row: int) -> Rect {return {238, 158 + f32(row) * 46, 682, 42}}
graph_localization_visible_index :: proc(row: int) -> int {visible := 0; scene :=
		graph_active_scene_id()
	for 	item, i in graph_document.localizations[:graph_document.localization_count] {if graph_state.localization_scene_only && graph_node_index(scene, item.node_id) < 0 do continue
		if graph_state.localization_language != "" && item.language != graph_state.localization_language do continue
		if graph_state.localization_status != "" && item.status != graph_state.localization_status do continue
		if graph_state.localization_missing_text && strings.trim_space(item.text) != "" do continue
		if graph_state.localization_missing_voice && strings.trim_space(item.voice) != "" do continue
		if visible == row do return i
		visible += 1}
	return -1}
graph_definition_row_rect :: proc(row: int) -> Rect {return {238, 118 + f32(row) * 38, 390, 34}}
update_graph_script_view :: proc(g: ^Game) {scene := graph_active_scene_id(); row := 0; for 	node, i in graph_document.nodes[:graph_document.node_count] {if node.beat.scene != scene do continue
		box := graph_script_row_rect(row)
		if button(g, box) do graph_select_only(i)
		if graph_state.selected_node == i {if button(g, {box.x + 496, box.y + 5, 54, 24}) do _ = graph_node_order_move(i, -1)
			if button(g, {box.x + 554, box.y + 5, 54, 24}) do _ = graph_node_order_move(i, 1)
			if button(g, {box.x + 612, box.y + 5, 62, 24}) do _ = graph_delete_selected()
			if g.input.mouse_pressed &&
			   contains({box.x + 86, box.y + 30, 390, 28}, g.input.mouse_pos) {if node.beat.kind == "choice" && len(node.beat.choice_labels) > 0 do graph_begin_choice_edit(.Choice_Label, node.beat.choice_labels[0], i, 0)
				else if node.beat.kind == "line" do graph_begin_edit(.Text, node.beat.text, i, true)
				else do graph_begin_edit(.Summary, node.beat.summary, i, true)}
			if g.input.mouse_pressed && contains({box.x + 8, box.y + 30, 74, 28}, g.input.mouse_pos) do graph_begin_picker(.Speaker, node.beat.speaker, i)}
		row += 1
		if row >= 8 do break}
	if button(g, {790, 646, 130, 28}) do _ = graph_add_node("line", {300, 120 + f32(row) * 110})}
update_graph_localization_view :: proc(g: ^Game) {if button(g, {238, 104, 80, 26}) do graph_state.localization_scene_only = !graph_state.localization_scene_only
	if button(g, {322, 104, 96, 26}) do graph_begin_edit(.Localization_Filter_Language, graph_state.localization_language)
	if button(g, {422, 104, 96, 26}) do graph_begin_edit(.Localization_Filter_Status, graph_state.localization_status)
	if button(g, {522, 104, 116, 26}) do graph_state.localization_missing_text = !graph_state.localization_missing_text
	if button(g, {642, 104, 116, 26}) do graph_state.localization_missing_voice = !graph_state.localization_missing_voice
	for 	row in 0 ..< 10 {i := graph_localization_visible_index(row); if i < 0 do break; box :=
			graph_localization_row_rect(row)
		if button(g, box) do graph_state.selected_localization = i
		if graph_state.selected_localization == i {item := graph_document.localizations[i]
			if g.input.mouse_pressed && contains({box.x + 150, box.y, 90, box.h}, g.input.mouse_pos) do graph_begin_edit(.Localization_Language, item.language)
			if g.input.mouse_pressed && contains({box.x + 244, box.y, 238, box.h}, g.input.mouse_pos) do graph_begin_edit(.Localization_Text, item.text, -1, true)
			if g.input.mouse_pressed && contains({box.x + 486, box.y, 78, box.h}, g.input.mouse_pos) do graph_begin_edit(.Localization_Status, item.status)
			if g.input.mouse_pressed && contains({box.x + 568, box.y, 106, box.h}, g.input.mouse_pos) do graph_begin_edit(.Localization_Voice, item.voice)}}
	if button(g, {666, 646, 122, 28}) do _ = graph_add_localization()
	if button(g, {794, 646, 126, 28}) do _ = graph_delete_localization()}
update_graph_conditions_view :: proc(g: ^Game) {for 	i in 0 ..< min(13, graph_document.condition_count) {if button(g, graph_definition_row_rect(i)) do graph_state.selected_condition = i}
	if graph_state.selected_condition >= 0 &&
	   graph_state.selected_condition <
		   graph_document.condition_count {item := &graph_document.conditions[graph_state.selected_condition]
		if g.input.mouse_pressed && contains({650, 144, 270, 32}, g.input.mouse_pos) do graph_begin_edit(.Condition_Id, item.id)
		if g.input.mouse_pressed && contains({650, 190, 270, 32}, g.input.mouse_pos) do graph_begin_edit(.Condition_Kind, story_condition_kind_text(item.kind))
		for 		slot in 0 ..< 5 {_, value, visible := graph_condition_slot(item, slot); box := Rect {
				650,
				236 + f32(slot) * 58,
				270,
				52,
			}
			if visible && g.input.mouse_pressed && contains(box, g.input.mouse_pos) do graph_begin_edit(Graph_Field(int(Graph_Field.Condition_Value) + slot), value, -1, true)}}
	if button(g, {650, 646, 128, 28}) do _ = graph_add_condition()
	if button(g, {786, 646, 134, 28}) do _ = graph_delete_condition()}
update_graph_effects_view :: proc(g: ^Game) {for 	i in 0 ..< min(13, graph_document.effect_count) {if button(g, graph_definition_row_rect(i)) do graph_state.selected_effect = i}
	if graph_state.selected_effect >= 0 &&
	   graph_state.selected_effect < graph_document.effect_count {item := &graph_document.effects[graph_state.selected_effect]
		if g.input.mouse_pressed && contains({650, 144, 270, 32}, g.input.mouse_pos) do graph_begin_edit(.Effect_Id, item.id)
		if g.input.mouse_pressed && contains({650, 190, 270, 32}, g.input.mouse_pos) do graph_begin_edit(.Effect_Kind, story_effect_kind_text(item.kind))
		for 		slot in 0 ..< 5 {_, value, visible := graph_effect_slot(item, slot); box := Rect {
				650,
				236 + f32(slot) * 58,
				270,
				52,
			}
			if visible && g.input.mouse_pressed && contains(box, g.input.mouse_pos) do graph_begin_edit(Graph_Field(int(Graph_Field.Effect_Value) + slot), value, -1, true)}}
	if button(g, {650, 646, 128, 28}) do _ = graph_add_effect()
	if button(g, {786, 646, 134, 28}) do _ = graph_delete_effect()}
