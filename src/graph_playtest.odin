package main

import "core:fmt"
import ui "zelda_engine:ui"

graph_begin_playtest :: proc(g: ^Game) -> bool {checked := graph_validate(&graph_document)
	if !checked.ok {graph_feedback(checked.message, true); graph_state.diagnostics_visible = true
		return false}
	scene := graph_state.active_scene
	if scene < 0 || scene >= graph_document.scene_count do return false
	graph_playtest_snapshot = {
		active                = true,
		game                  = g^,
		scene                 = scene,
		node                  = graph_state.selected_node,
		pan                   = graph_state.pan,
		zoom                  = graph_state.zoom,
		view                  = graph_state.view,
		search_query          = graph_state.search_query,
		search_result         = graph_state.search_result,
		selected_condition    = graph_state.selected_condition,
		selected_effect       = graph_state.selected_effect,
		selected_localization = graph_state.selected_localization,
		diagnostics_visible   = graph_state.diagnostics_visible,
		help_visible          = graph_state.help_visible,
	}
	if ready := graph_apply_story_runtime(g); !ready.ok {graph_feedback(ready.message, true)
		graph_playtest_snapshot.active = false
		return false}
	g.editor_mode = .None
	graph_state.playtesting = true
	graph_state.debugger = {
		paused = true,
	}
	start := graph_document.scenes[scene].scene.entry
	if graph_state.selected_node >= 0 && graph_state.selected_node < graph_document.node_count do start = graph_document.nodes[graph_state.selected_node].beat.id
	if !dialogue_start_scene(g, scene) {g^ = graph_playtest_snapshot.game
		graph_playtest_snapshot.active = false
		graph_state.playtesting = false
		story_runtime_destroy(&graph_playtest_runtime)
		compiled_story_destroy(&graph_playtest_compiled)
		story_project_destroy(&graph_playtest_project)
		return false}
	if start != graph_document.scenes[scene].scene.entry do _ = dialogue_goto(g, start)
	graph_state.debugger.last_node = start
	return true}
graph_end_playtest :: proc(g: ^Game) -> bool {if !graph_playtest_snapshot.active do return false
	snapshot := graph_playtest_snapshot
	g^ = snapshot.game
	story_runtime_destroy(&graph_playtest_runtime)
	compiled_story_destroy(&graph_playtest_compiled)
	story_project_destroy(&graph_playtest_project)
	g.editor_mode = .Graph
	graph_state.playtesting = false
	graph_state.active_scene = snapshot.scene
	graph_select_only(snapshot.node)
	graph_state.pan = snapshot.pan
	graph_state.zoom = snapshot.zoom
	graph_state.view = snapshot.view
	graph_state.search_query = snapshot.search_query
	graph_state.search_result = snapshot.search_result
	graph_state.selected_condition = snapshot.selected_condition
	graph_state.selected_effect = snapshot.selected_effect
	graph_state.selected_localization = snapshot.selected_localization
	graph_state.diagnostics_visible = snapshot.diagnostics_visible
	graph_state.help_visible = snapshot.help_visible
	graph_playtest_snapshot.active = false
	return true}
graph_restart_playtest :: proc(g: ^Game) -> bool {if !graph_playtest_snapshot.active do return false
	snapshot := graph_playtest_snapshot
	g^ = snapshot.game
	graph_playtest_snapshot = snapshot
	if ready := graph_apply_story_runtime(g); !ready.ok {graph_feedback(ready.message, true)
		return graph_end_playtest(g)}
	g.editor_mode = .None
	graph_state.playtesting = true
	graph_state.debugger = {
		paused = true,
	}
	if !dialogue_start_scene(g, snapshot.scene) do return graph_end_playtest(g)
	start := graph_document.scenes[snapshot.scene].scene.entry
	if snapshot.node >= 0 && snapshot.node < graph_document.node_count {start =
			graph_document.nodes[snapshot.node].beat.id
		_ = dialogue_goto(g, start)}
	graph_state.debugger.last_node = start
	return true}
graph_debugger_before_update :: proc(g: ^Game) -> bool {if !graph_state.playtesting do return true
	if graph_state.debugger.paused && !graph_state.debugger.step_requested do return false
	if graph_state.debugger.step_requested {beat := story_presentation_node(g); if beat != nil && (beat.kind == .Line || beat.kind == .Stage) do g.input.activate = true}
	return true}
graph_debugger_after_update :: proc(
	g: ^Game,
	before: string,
) {if !graph_state.playtesting do return; beat := story_presentation_node(g); after :=
		beat == nil ? "" : beat.id
	if after != before || !g.story_presentation.active {debug := &graph_state.debugger
		if before != "" {if debug.recent_count >= len(debug.recent) {for i in 1 ..< len(debug.recent) do debug.recent[i - 1] = debug.recent[i]
				debug.recent_count -= 1}
			debug.recent[debug.recent_count] = before
			debug.recent_count += 1}
		debug.last_node = after
		debug.completed = !g.story_presentation.active
		if debug.step_requested {debug.step_requested = false; debug.paused = true}}}
graph_debugger_button_rect :: proc(index: int) -> Rect {return{
		24 + f32(index) * 112,
		654,
		104,
		38,
	}}
graph_debug_toggle_rect :: proc(column, row: int) -> Rect {return{
		20 + f32(column) * 390,
		82 + f32(row) * 27,
		376,
		23,
	}}
graph_debugger_page_rect :: proc() -> Rect {return {1062, 10, 122, 34}}
graph_debugger_editor_rect :: proc() -> Rect {return {472, 654, 104, 38}}
graph_debugger_focus_active :: proc() -> bool {id := graph_state.debugger.last_node; if id == "" do return false
	for node, i in graph_document.nodes[:graph_document.node_count] do if node.beat.id == id {scene := graph_scene_index(node.beat.scene); if scene >= 0 do graph_state.active_scene = scene; graph_select_only(i); if graph_state.debugger.recent_count > 0 {prior := graph_state.debugger.recent[graph_state.debugger.recent_count - 1]; from := graph_node_index(node.beat.scene, prior); if from >= 0 {source := &graph_document.nodes[from].beat; for output in 0 ..< graph_output_count(source) {port, choice := graph_output_port(source, output); target := graph_port_target(source, port, choice); if target != nil && target^ == id {graph_state.edge_selection = {
							active       = true,
							node         = from,
							port         = port,
							choice_index = choice,
						}; break}}}}; _ = graph_frame_nodes(true); return true}
	return false}
graph_debugger_update_editor_toggle :: proc(g: ^Game) {if !graph_state.playtesting do return
	if button(g, graph_debugger_editor_rect()) {if g.editor_mode == .Graph do g.editor_mode = .None
		else {g.editor_mode = .Graph; _ = graph_debugger_focus_active()}}}
graph_debugger_condition_forced :: proc(runtime: ^Story_Runtime, id: string) -> (bool, bool) {for override_id, i in runtime.condition_override_ids[:runtime.condition_override_count] do if override_id == id do return runtime.condition_override_values[i], true
	return false, false}
graph_debugger_apply_effect :: proc(runtime: ^Story_Runtime, index: int) -> bool {if runtime == nil || runtime.compiled == nil || index < 0 || index >= len(runtime.compiled.runtime.effects) do return false
	indices := [1]int{index}
	result := story_apply_transaction(
		&runtime.compiled.runtime,
		&runtime.state,
		indices[:],
		runtime.spatial,
	)
	return result.ok}
graph_debugger_cycle_variable :: proc(runtime: ^Story_Runtime, index: int) -> bool {if runtime == nil || index < 0 || index >= len(runtime.state.values) do return false
	item := &runtime.state.values[index]
	#partial switch
	item.value.kind {case .Boolean:
		item.value.boolean_value = !item.value.boolean_value; case .Integer:
		item.value.integer_value += 1; case .Enumeration, .Entity:
		item.value.text_value = item.value.text_value == "" ? "debug" : ""}
	return true}
graph_topics :: proc() -> Graph_Topic_List {result: Graph_Topic_List; for 	node in graph_document.nodes[:graph_document.node_count] {groups := [2][]string {
			node.beat.requires_topics,
			node.beat.unlock_topics,
		}
		for group in groups do for value in group {exists := false; for current in result.values[:result.count] do if current == value do exists = true; if !exists && value != "" && result.count < len(result.values) {result.values[result.count] = value; result.count += 1}}}
	return result}
graph_topic_enabled :: proc(g: ^Game, id: string) -> bool {return topic_unlocked(g, id)}
graph_toggle_topic :: proc(g: ^Game, id: string) {if g.mystery_state == nil do return
	if graph_topic_enabled(
		g,
		id,
	) {_ = mystery_string_set_remove(&g.mystery_state.unlocked_topics, id)} else {_ = mystery_string_set_add(&g.mystery_state.unlocked_topics, id)}}
update_graph_debugger :: proc(g: ^Game) {if !graph_state.playtesting do return; if button(g, graph_debugger_page_rect()) do graph_state.debugger.page = (graph_state.debugger.page + 1) % 2
	if button(g, graph_debugger_button_rect(0)) do graph_state.debugger.paused = !graph_state.debugger.paused
	if button(g, graph_debugger_button_rect(1)) {graph_state.debugger.paused = false
		graph_state.debugger.step_requested = true}
	if button(g, graph_debugger_button_rect(2)) do _ = graph_restart_playtest(g)
	if button(g, graph_debugger_button_rect(3)) do _ = graph_end_playtest(g)
	if graph_state.debugger.paused {if graph_state.debugger.page == 0 {payload :=
				mystery_game_payload(g)
			if payload != nil {for _, i in payload.clues do if button(g, graph_debug_toggle_rect(0, i)) do mystery_game_toggle_clue(g, i)
				for _, i in payload.claims do if button(g, graph_debug_toggle_rect(1, i)) do mystery_game_toggle_claim(g, i)}
			topics := graph_topics()
			for topic, i in topics.values[:topics.count] do if button(g, graph_debug_toggle_rect(2, i)) do graph_toggle_topic(g, topic)}
		else if g.story_runtime != nil {for condition, i in g.story_runtime.compiled.runtime.conditions[:min(15, len(g.story_runtime.compiled.runtime.conditions))] do if button(g, graph_debug_toggle_rect(0, i)) do _ = story_runtime_toggle_condition_override(g.story_runtime, condition.id)
			for _, i in g.story_runtime.compiled.runtime.effects[:min(15, len(g.story_runtime.compiled.runtime.effects))] do if button(g, graph_debug_toggle_rect(1, i)) do _ = graph_debugger_apply_effect(g.story_runtime, i)
			for _, i in g.story_runtime.state.values[:min(15, len(g.story_runtime.state.values))] do if button(g, graph_debug_toggle_rect(2, i)) do _ = graph_debugger_cycle_variable(g.story_runtime, i)}}
	if g.input.back do _ = graph_end_playtest(g)}

update_graph_mode :: proc(g: ^Game) {
	if graph_state.playtesting {graph_debugger_update_editor_toggle(g); update_graph_debugger(g); return}
	if graph_state.feedback_frames > 0 do graph_state.feedback_frames -= 1
	if graph_state.field_edit.active {
		edit := &graph_state.field_edit; edit_box := graph_edit_rect(); id := button_id(edit_box); g.gui.focused = id; ui.gui_text_edit_begin(&g.gui, id, edit.count); ui.gui_text_edit_handle_mouse(&g.gui, id, edit.buffer[:], edit.count, ui.Rect(edit_box), ui.Vec2{edit_box.x + 8, edit_box.y + 11}); _ = ui.gui_text_edit_process(&g.gui, id, edit.buffer[:], &edit.count)
		if edit.picker {candidate_count := graph_picker_count(g, edit.field); edit.picker_selected = graph_picker_navigation_step(edit.picker_selected, candidate_count, g.input.up, g.input.down); if g.input.mouse_wheel < 0 do edit.picker_selected = min(edit.picker_selected + 8, max(0, candidate_count - 1)); if g.input.mouse_wheel > 0 do edit.picker_selected = max(0, edit.picker_selected - 8); if edit.picker_selected < edit.picker_offset do edit.picker_offset = edit.picker_selected; if edit.picker_selected >= edit.picker_offset + 8 do edit.picker_offset = edit.picker_selected - 7; if g.input.key_enter || g.input.activate {_ = graph_picker_apply(g, edit.picker_selected); g.input.activate = false; return}; for i in 0 ..< 8 do if button(g, graph_picker_rect(i)) {_ = graph_picker_apply(g, edit.picker_offset + i); return}}
		if g.input.key_escape {graph_cancel_edit(); g.input.back = false; return}; if g.input.key_enter && !edit.multiline {_ = graph_commit_edit(); g.input.activate = false; return}; if g.input.key_enter && edit.multiline && (g.input.key_ctrl || g.input.key_super) {_ = graph_commit_edit(); g.input.activate = false; return}
		if g.input.key_tab {_ = graph_advance_edit(g.input.key_shift ? -1 : 1); return}
		if g.input.mouse_pressed &&
		   !contains(graph_edit_rect(), g.input.mouse_pos) {_ = graph_commit_edit(); return}
		return
	}
	if g.input.back {if graph_state.quick_add do graph_state.quick_add = false
		else do g.editor_mode = .None; g.input.back = false}
	if g.input.save_document {saved := graph_save_story(graph_active_source_path, g.story_project); graph_feedback(saved.message, !saved.ok)}
	if g.input.undo_document && graph_undo() do graph_feedback("UNDO RESTORED GRAPH")
	if g.input.redo_document && graph_redo() do graph_feedback("REDO RESTORED GRAPH")
	if g.input.delete_selection do _ = graph_delete_selected()
	if g.input.copy_selection do _ = graph_copy_selection()
	if g.input.paste_selection do _ = graph_paste_clipboard(g.input.mouse_pos)
	if g.input.duplicate_selection do _ = graph_duplicate_selection(g.input.mouse_pos)
	if button(g, {1090, 14, 96, 34}) do g.editor_mode = .None
	if button(
		g,
		{854, 14, 72, 34},
	) {saved := graph_save_story(graph_active_source_path, g.story_project); graph_feedback(saved.message, !saved.ok)}
	if button(
		g,
		{934, 14, 72, 34},
	) {checked := graph_validate_complete(g.story_project); graph_feedback(checked.message, !checked.ok); graph_state.diagnostics_visible = !graph_state.diagnostics_visible}
	if button(
		g,
		{1014, 14, 68, 34},
	) {if graph_document.error_count > 0 {graph_state.diagnostics_visible = true; graph_feedback("FIX BLOCKING GRAPH ERRORS BEFORE PLAY", true)} else do _ = graph_begin_playtest(g)}
	if graph_state.view ==
	   .Graph {if button(g, {966, 530, 222, 30}) do _ = graph_open_selected_in_build(g); if button(g, {14, 356, 58, 28}) do _ = graph_add_scene(); if button(g, {76, 356, 58, 28}) do _ = graph_frame_nodes(); if button(g, {138, 356, 68, 28}) do _ = graph_auto_layout(); if button(g, {966, 492, 68, 28}) do _ = graph_duplicate_scene(); if button(g, {1040, 492, 68, 28}) {if graph_state.confirm == .Delete_Scene do _ = graph_delete_scene()
			else {graph_state.confirm = .Delete_Scene; graph_feedback("CLICK DELETE SCENE AGAIN TO CONFIRM", true)}}; if button(g, {1114, 492, 34, 28}) do _ = graph_move_scene(-1); if button(g, {1152, 492, 34, 28}) do _ = graph_move_scene(1)}
	scene_start := graph_scene_window_start(

	); for row in 0 ..< min(8, graph_document.scene_count - scene_start) {i := scene_start + row; if button(g, graph_scene_rect(row)) {graph_state.active_scene = i; graph_state.selected_node = -1}}
	if graph_state.diagnostics_visible {for i in 0 ..< min(8, graph_document.diagnostic_count) {if button(g, {720, 92 + f32(i) * 42, 462, 38}) {item := graph_document.diagnostics[i]; scene_index := graph_scene_index(item.scene_id); if scene_index >= 0 do graph_state.active_scene = scene_index; node_index := graph_node_index(item.scene_id, item.node_id); if node_index >= 0 {graph_select_only(node_index); _ = graph_frame_nodes(true)}; graph_state.diagnostics_visible = false}}}
	views := [5]Graph_View {
		.Graph,
		.Script,
		.Localization,
		.Conditions,
		.Effects,
	}; for view, i in views do if button(g, graph_view_tab_rect(i)) do graph_state.view = view
	if button(g, graph_search_rect()) do graph_begin_edit(.Search, graph_state.search_query)
	if button(g, graph_search_next_rect()) do _ = graph_focus_search_result(1)
	if graph_state.view ==
	   .Script {update_graph_script_view(g); return}; if graph_state.view == .Localization {if graph_state.selected_localization >= 0 && graph_state.selected_localization < graph_document.localization_count && g.input.mouse_pressed && contains({238, 618, 400, 24}, g.input.mouse_pos) do graph_begin_edit(.Localization_Note, graph_document.localizations[graph_state.selected_localization].note, -1, true); update_graph_localization_view(g); return}; if graph_state.view == .Conditions {if button(g, {786, 610, 134, 28}) do _ = graph_duplicate_condition(); update_graph_conditions_view(g); return}; if graph_state.view == .Effects {if button(g, {786, 610, 134, 28}) do _ = graph_duplicate_effect(); update_graph_effects_view(g); return}; if graph_state.view != .Graph do return
	if graph_state.selected_node >= 0 &&
	   graph_state.selected_node <
		   graph_document.node_count {selected := graph_document.nodes[graph_state.selected_node].beat; graph_state.inspector_scroll_max = selected.kind == "choice" ? max(0, f32(len(selected.choice_labels)) * 50 - 250) : f32(180)} else do graph_state.inspector_scroll_max = 0
	inspector_view := graph_inspector_viewport(

	); if contains(inspector_view, g.input.mouse_pos) && g.input.mouse_wheel != 0 do graph_state.inspector_scroll = clamp(graph_state.inspector_scroll - g.input.mouse_wheel * 48, 0, graph_state.inspector_scroll_max)
	kinds := [11]string {
		"line",
		"choice",
		"check",
		"stage",
		"interaction",
		"effect",
		"selector",
		"objective",
		"wait_event",
		"subscene",
		"end",
	}; for kind, i in kinds do if button(g, graph_palette_rect(i)) do _ = graph_add_node(kind, graph_screen_to_world({420 + f32(i % 2) * 210, 160 + f32(i / 2) * 100}))
	canvas := graph_canvas_rect(

	); if graph_state.quick_add {for kind, i in kinds {if button(g, graph_quick_rect(i)) {_ = graph_add_node(kind, graph_screen_to_world(graph_state.quick_add_at)); graph_state.quick_add = false}}}
	if g.input.mouse_pressed &&
	   contains(
		   graph_minimap_rect(),
		   g.input.mouse_pos,
	   ) {_ = graph_minimap_focus(g.input.mouse_pos); g.input.mouse_pressed = false}
	graph_state.edge_hover =
		{}; if contains(canvas, g.input.mouse_pos) && !graph_state.edge_drag.active && !graph_state.dragging && !graph_state.marquee.active {over_node := false; scene := graph_active_scene_id(); for node in graph_document.nodes[:graph_document.node_count] do if node.beat.scene == scene && contains(graph_node_rect(node), g.input.mouse_pos) {over_node = true; break}; if !over_node do graph_state.edge_hover = graph_edge_hit(g.input.mouse_pos)}
	if graph_state.quick_add {if g.input.down do graph_state.quick_add_selected = (graph_state.quick_add_selected + 1) % len(kinds); if g.input.up do graph_state.quick_add_selected = (graph_state.quick_add_selected + len(kinds) - 1) % len(kinds); if g.input.activate {_ = graph_add_node(kinds[graph_state.quick_add_selected], graph_screen_to_world(graph_state.quick_add_at)); graph_state.quick_add = false; g.input.activate = false}}
	if contains(canvas, g.input.mouse_pos) &&
	   g.input.mouse_wheel !=
		   0 {before := graph_screen_to_world(g.input.mouse_pos); graph_state.zoom = clamp(graph_state.zoom + g.input.mouse_wheel * .10, .25, 1.75); after := graph_screen_to_world(g.input.mouse_pos); graph_state.pan.x += after.x - before.x; graph_state.pan.y += after.y - before.y}
	if contains(canvas, g.input.mouse_pos) &&
	   g.input.mouse_middle_pressed {graph_state.panning = true; graph_state.pan_origin = g.input.mouse_pos; graph_state.pan_start = graph_state.pan}
	if graph_state.panning &&
	   g.input.mouse_middle_down {graph_state.pan = {graph_state.pan_start.x + (g.input.mouse_pos.x - graph_state.pan_origin.x) / graph_state.zoom, graph_state.pan_start.y + (g.input.mouse_pos.y - graph_state.pan_origin.y) / graph_state.zoom}}
	if graph_state.panning && g.input.mouse_middle_released do graph_state.panning = false
	if graph_state.selected_node >= 0 &&
	   graph_state.selected_node < graph_document.node_count &&
	   graph_document.nodes[graph_state.selected_node].beat.kind ==
		   "choice" {beat := &graph_document.nodes[graph_state.selected_node].beat; page_count := max(1, (len(beat.choice_labels) + 4) / 5); graph_state.choice_page = clamp(graph_state.choice_page, 0, page_count - 1); choice_start := graph_state.choice_page * 5; choice_end := min(choice_start + 5, len(beat.choice_labels)); for i in choice_start ..< choice_end {row := i - choice_start; y := f32(184 + row * 48); if g.input.mouse_pressed && contains({958, y, 122, 24}, g.input.mouse_pos) do graph_begin_choice_edit(.Choice_Label, beat.choice_labels[i], graph_state.selected_node, i); if g.input.mouse_pressed && contains({1082, y, 38, 24}, g.input.mouse_pos) do graph_begin_choice_edit(.Choice_Id, beat.choice_ids[i], graph_state.selected_node, i); if button(g, {1122, y, 26, 24}) do _ = graph_choice_duplicate(graph_state.selected_node, i); if button(g, {1152, y, 36, 24}) do _ = graph_choice_delete(graph_state.selected_node, i); if g.input.mouse_pressed && contains({968, y + 25, 150, 20}, g.input.mouse_pos) do graph_begin_choice_edit(.Choice_Condition, beat.choice_conditions[i], graph_state.selected_node, i); if g.input.mouse_pressed && contains({1122, y + 25, 66, 20}, g.input.mouse_pos) {graph_state.choice_reorder = {
					active = true,
					node   = graph_state.selected_node,
					index  = i,
				}; g.input.mouse_pressed =
					false}}; if button(g, {1076, 460, 52, 24}) do graph_state.choice_page = max(0, graph_state.choice_page - 1); if button(g, {1132, 460, 52, 24}) do graph_state.choice_page = min(page_count - 1, graph_state.choice_page + 1); graph_choice_reorder_update(g)}
	if graph_state.selected_node >= 0 &&
	   graph_state.selected_node < graph_document.node_count &&
	   button(
		   g,
		   {966, 532, 104, 28},
	   ) {graph_history_push("Toggle node collapse"); graph_document.nodes[graph_state.selected_node].collapsed = !graph_document.nodes[graph_state.selected_node].collapsed; graph_changed()}
	if graph_state.selected_node >= 0 && graph_state.selected_node < graph_document.node_count {
		if button(g, {958, 660, 38, 28}) do graph_state.inspector_field_index = (graph_state.inspector_field_index + len(GRAPH_NODE_INSPECTOR_FIELDS) - 1) % len(GRAPH_NODE_INSPECTOR_FIELDS)
		if button(g, {1154, 660, 38, 28}) do graph_state.inspector_field_index = (graph_state.inspector_field_index + 1) % len(GRAPH_NODE_INSPECTOR_FIELDS)
		if button(
			g,
			{1000, 660, 150, 28},
		) {beat := &graph_document.nodes[graph_state.selected_node].beat; field := graph_inspector_field(); graph_begin_edit(field, graph_inspector_field_value(beat, field), graph_state.selected_node, graph_inspector_field_multiline(field))}
	} else if graph_state.active_scene >= 0 &&
	   graph_state.active_scene < graph_document.scene_count {
		if button(g, {958, 660, 38, 28}) do graph_state.inspector_field_index = (graph_state.inspector_field_index + len(GRAPH_SCENE_INSPECTOR_FIELDS) - 1) % len(GRAPH_SCENE_INSPECTOR_FIELDS)
		if button(g, {1154, 660, 38, 28}) do graph_state.inspector_field_index = (graph_state.inspector_field_index + 1) % len(GRAPH_SCENE_INSPECTOR_FIELDS)
		if button(
			g,
			{1000, 660, 150, 28},
		) {scene := &graph_document.scenes[graph_state.active_scene].scene; field := graph_scene_inspector_field(); graph_begin_edit(field, graph_scene_inspector_value(scene, field), -1, field == .Scene_Summary)}
	}
	if graph_state.selected_node >= 0 &&
	   graph_state.selected_node <
		   graph_document.node_count {beat := &graph_document.nodes[graph_state.selected_node].beat; if beat.kind == "stage" {if g.input.mouse_pressed && contains({966, 568, 220, 26}, g.input.mouse_pos) do graph_begin_picker(.Actor, beat.actor, graph_state.selected_node); if g.input.mouse_pressed && contains({966, 598, 220, 26}, g.input.mouse_pos) do graph_begin_edit(.Animation, beat.animation, graph_state.selected_node); if g.input.mouse_pressed && contains({966, 628, 220, 26}, g.input.mouse_pos) do graph_begin_picker(.UI, beat.ui, graph_state.selected_node)} else {if g.input.mouse_pressed && contains({966, 568, 220, 26}, g.input.mouse_pos) do graph_begin_picker(.Condition, beat.condition_id, graph_state.selected_node); if g.input.mouse_pressed && contains({966, 598, 220, 26}, g.input.mouse_pos) do graph_begin_picker(.Effects, graph_join_strings(beat.effect_ids), graph_state.selected_node); if (beat.kind == "selector" || beat.kind == "objective" || beat.kind == "effect" || beat.kind == "interaction") && g.input.mouse_pressed && contains({966, 628, 220, 26}, g.input.mouse_pos) do graph_begin_edit(.Domain_Ref, beat.domain_ref, graph_state.selected_node)}}
	if graph_state.selected_node >= 0 &&
	   graph_state.selected_node <
		   graph_document.node_count {node := &graph_document.nodes[graph_state.selected_node]; if g.input.mouse_pressed && contains(graph_inspector_scrolled_rect({958, 100, 234, 34}), g.input.mouse_pos) {graph_begin_edit(.Node_Id, node.beat.id, graph_state.selected_node)} else if node.beat.kind == "choice" {if button(g, {966, 430, 104, 28}) do _ = graph_choice_add(graph_state.selected_node)} else if g.input.mouse_pressed && contains(graph_inspector_scrolled_rect({958, 162, 234, 28}), g.input.mouse_pos) {graph_begin_picker(.Speaker, node.beat.speaker, graph_state.selected_node)} else if g.input.mouse_pressed && contains(graph_inspector_scrolled_rect({958, 190, 234, 60}), g.input.mouse_pos) {graph_begin_edit(.Text, node.beat.text, graph_state.selected_node, true)} else if g.input.mouse_pressed && contains(graph_inspector_scrolled_rect({958, 260, 234, 52}), g.input.mouse_pos) {graph_begin_edit(.Summary, node.beat.summary, graph_state.selected_node, true)} else if g.input.mouse_pressed && contains(graph_inspector_scrolled_rect({958, 320, 112, 30}), g.input.mouse_pos) {graph_begin_edit(.Duration, fmt.tprintf("%.3f", node.beat.duration), graph_state.selected_node)} else if g.input.mouse_pressed && contains(graph_inspector_scrolled_rect({1080, 320, 112, 30}), g.input.mouse_pos) {graph_begin_edit(.Transition, fmt.tprintf("%.3f", node.beat.transition), graph_state.selected_node)} else if g.input.mouse_pressed && contains(graph_inspector_scrolled_rect({958, 360, 234, 28}), g.input.mouse_pos) {field := Graph_Field.Interaction; if node.beat.kind == "stage" do field = .Camera
			else if node.beat.kind == "wait_event" do field = .Event
			else if node.beat.kind == "subscene" do field = .Subscene
			else if node.beat.kind == "check" do field = .Clue
			else if node.beat.kind == "end" do field = .Ending; value := node.beat.interaction; if field == .Camera do value = node.beat.camera
			else if field == .Event do value = node.beat.event_id
			else if field == .Subscene do value = node.beat.subscene_id
			else if field == .Clue do value = node.beat.clue
			else if field == .Ending do value = node.beat.ending; graph_begin_picker(field, value, graph_state.selected_node)} else if g.input.mouse_pressed && contains(graph_inspector_scrolled_rect({958, 390, 234, 28}), g.input.mouse_pos) {field := Graph_Field.UI; if node.beat.kind == "stage" do field = .Actor_Mark; value := node.beat.ui; if field == .Actor_Mark do value = node.beat.actor_mark; graph_begin_picker(field, value, graph_state.selected_node)}; if node.beat.kind != "choice" && button(g, {966, 440, 102, 30}) {graph_history_push("Set scene entry"); graph_document.scenes[graph_state.active_scene].scene.entry = node.beat.id; graph_changed(); graph_feedback("SCENE ENTRY UPDATED")}; if node.beat.kind != "choice" && button(g, {1078, 440, 110, 30}) {graph_history_push("Toggle blocking"); node.beat.blocking = !node.beat.blocking; graph_changed(); graph_feedback(node.beat.blocking ? "CONVERSATION CANNOT BE LEFT AT THIS BEAT" : "CONVERSATION MAY BE LEFT AT THIS BEAT")}} else if graph_state.active_scene >= 0 {scene := &graph_document.scenes[graph_state.active_scene].scene; if g.input.mouse_pressed && contains({958, 100, 234, 34}, g.input.mouse_pos) do graph_begin_edit(.Scene_Id, scene.id)
		else if g.input.mouse_pressed && contains({958, 145, 234, 70}, g.input.mouse_pos) do graph_begin_edit(.Scene_Summary, scene.summary, -1, true)
		else if g.input.mouse_pressed && contains({958, 225, 234, 34}, g.input.mouse_pos) do graph_begin_edit(.Scene_Return, scene.return_to)}
	if g.input.mouse_pressed &&
	   contains(canvas, g.input.mouse_pos) &&
	   !graph_state.quick_add {scene := graph_active_scene_id(); port_picked := false; for &node, i in graph_document.nodes[:graph_document.node_count] {if node.beat.scene != scene do continue; for port_index in 0 ..< graph_output_count(&node.beat) {if contains(graph_port_rect(node, port_index), g.input.mouse_pos) {port, choice := graph_output_port(&node.beat, port_index); graph_state.edge_drag = {
						active       = true,
						node         = i,
						port         = port,
						choice_index = choice,
						start        = g.input.mouse_pos,
					}; graph_state.edge_selection = {
						active       = true,
						node         = i,
						port         = port,
						choice_index = choice,
					}; port_picked =
						true; break}}; if port_picked do break}; if !port_picked {picked := -1; for node, i in graph_document.nodes[:graph_document.node_count] do if node.beat.scene == scene && contains(graph_node_rect(node), g.input.mouse_pos) {picked = i; break}; if picked >= 0 {if g.input.key_shift do graph_toggle_selection(picked)
				else if !graph_is_selected(picked) do graph_select_only(picked); graph_history_push("Move nodes"); graph_state.dragging = true; graph_state.drag_origin = g.input.mouse_pos; for selected, j in graph_state.selection[:graph_state.selection_count] do graph_state.drag_node_origins[j] = graph_document.nodes[selected].position} else {edge := graph_edge_hit(g.input.mouse_pos); if edge.active {if !g.input.key_shift do graph_clear_selection(); graph_state.edge_selection = edge} else {if !g.input.key_shift do graph_clear_selection(); graph_state.marquee = {
						active  = true,
						start   = g.input.mouse_pos,
						current = g.input.mouse_pos,
					}}}}}
	if graph_state.marquee.active {graph_state.marquee.current = g.input.mouse_pos; if g.input.mouse_released {box := graph_rect_normalized(graph_state.marquee.start, graph_state.marquee.current); if !g.input.key_shift do graph_clear_selection(); scene := graph_active_scene_id(); for node, i in graph_document.nodes[:graph_document.node_count] do if node.beat.scene == scene && graph_rects_overlap(box, graph_node_rect(node)) && !graph_is_selected(i) && graph_state.selection_count < GRAPH_SELECTION_CAPACITY {graph_state.selection[graph_state.selection_count] = i; graph_state.selection_count += 1; graph_state.selected_node = i}; graph_state.marquee.active = false}}
	if graph_state.edge_drag.active &&
	   g.input.mouse_released {target := -1; scene := graph_active_scene_id(); for node, i in graph_document.nodes[:graph_document.node_count] do if node.beat.scene == scene && i != graph_state.edge_drag.node && contains(graph_input_rect(node), g.input.mouse_pos) {target = i; break}; if target >= 0 {edge := graph_state.edge_drag; pointer := graph_port_target(&graph_document.nodes[edge.node].beat, edge.port, edge.choice_index); if pointer != nil {graph_history_push("Reconnect edge"); pointer^ = graph_document.nodes[target].beat.id; graph_changed()}}; graph_state.edge_drag = {}}
	if graph_state.dragging &&
	   graph_state.selected_node >=
		   0 {if g.input.mouse_down {delta := Vec2{(g.input.mouse_pos.x - graph_state.drag_origin.x) / graph_state.zoom, (g.input.mouse_pos.y - graph_state.drag_origin.y) / graph_state.zoom}; for selected, j in graph_state.selection[:graph_state.selection_count] {origin := graph_state.drag_node_origins[j]; graph_document.nodes[selected].position = {origin.x + delta.x, origin.y + delta.y}}}; if g.input.mouse_released {graph_state.dragging = false; graph_changed()}}
}
