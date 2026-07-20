package main

import "core:fmt"
import "core:strings"

graph_add_node :: proc(kind: string, position: Vec2) -> bool {if graph_document.node_count >= GRAPH_MAX_NODES || graph_state.active_scene < 0 do return false
	source := graph_state.selected_node
	graph_history_push("Add node")
	id := graph_unique_id(
		fmt.tprintf("%s_%d", kind, graph_document.revision + 1),
		graph_active_scene_id(),
	)
	scene := graph_active_scene_id()
	beat := Graph_Beat {
		id         = id,
		scene      = scene,
		kind       = kind,
		ui         = "dialogue",
		transition = .18,
	}
	if kind == "line" {beat.speaker = "narrator"; beat.text = "New dialogue line."}
	else if kind == "stage" {beat.ui = "hidden"; beat.duration = .5}
	else if kind == "end" do beat.ui = "unchanged"
	graph_document.nodes[graph_document.node_count] = {
		beat     = beat,
		position = position,
	}
	if source >= 0 &&
	   source < graph_document.node_count &&
	   graph_document.nodes[source].beat.scene == scene {from := &graph_document.nodes[source].beat
		if from.kind == "choice" {ids := make([]string, len(from.choice_labels) + 1); labels :=
				make([]string, len(from.choice_labels) + 1)
			targets := make([]string, len(from.choice_labels) + 1)
			conditions := make([]string, len(from.choice_labels) + 1)
			copy(ids, from.choice_ids)
			copy(labels, from.choice_labels)
			copy(targets, from.choice_targets)
			copy(conditions, from.choice_conditions)
			ids[len(ids) - 1] = fmt.tprintf("%s_choice_%d", from.id, len(ids))
			labels[len(labels) - 1] = "New choice"
			targets[len(targets) - 1] = id
			from.choice_ids, from.choice_labels, from.choice_targets, from.choice_conditions =
				ids, labels, targets, conditions}
		else if from.kind == "check" {if from.success == "" do from.success = id
			else if from.failure == "" do from.failure = id}
		else if from.kind == "interaction" {if from.success == "" do from.success = id
			else if from.cancel == "" do from.cancel = id}
		else if from.kind != "end" && from.next == "" do from.next = id}
	graph_select_only(graph_document.node_count)
	graph_document.node_count += 1
	graph_changed()
	graph_feedback(fmt.tprintf("ADDED %s  ·  CTRL/CMD Z TO UNDO", strings.to_upper(kind)))
	return true}
graph_delete_selected :: proc() -> bool {if graph_state.edge_selection.active {edge :=
			graph_state.edge_selection
		if edge.node >= 0 && edge.node < graph_document.node_count {target := graph_port_target(
				&graph_document.nodes[edge.node].beat,
				edge.port,
				edge.choice_index,
			)
			if target != nil {graph_history_push("Delete edge"); target^ = ""
				graph_state.edge_selection = {}
				graph_changed()
				return true}}}
	if graph_state.selection_count == 0 && graph_state.selected_node >= 0 do graph_select_only(graph_state.selected_node)
	if graph_state.selection_count == 0 do return false
	graph_history_push("Delete nodes")
	for 	selected in graph_state.selection[:graph_state.selection_count] {if selected < 0 || selected >= graph_document.node_count do continue
		deleted := graph_document.nodes[selected].beat.id
		scene := graph_document.nodes[selected].beat.scene
		for 		&node in graph_document.nodes[:graph_document.node_count] {if node.beat.scene != scene do continue
			if node.beat.next == deleted do node.beat.next = ""
			if node.beat.success == deleted do node.beat.success = ""
			if node.beat.failure == deleted do node.beat.failure = ""
			if node.beat.cancel == deleted do node.beat.cancel = ""
			for &target in node.beat.choice_targets do if target == deleted do target = ""}}
	for i := graph_document.node_count - 1; i >= 0; i -= 1 {if !graph_is_selected(i) do continue
		for j in i + 1 ..< graph_document.node_count do graph_document.nodes[j - 1] = graph_document.nodes[j]
		graph_document.node_count -= 1}
	graph_clear_selection()
	graph_changed()
	return true}

graph_copy_selection :: proc() -> bool {if graph_state.selection_count == 0 && graph_state.selected_node >= 0 do graph_select_only(graph_state.selected_node)
	if graph_state.selection_count == 0 do return false
	graph_clipboard = {}
	min_pos := Vec2{1e9, 1e9}
	for 	index in graph_state.selection[:graph_state.selection_count] {if index < 0 || index >= graph_document.node_count || graph_clipboard.node_count >= GRAPH_CLIPBOARD_CAPACITY do continue
		node := graph_document.nodes[index]
		node.beat = graph_beat_clone(node.beat)
		graph_clipboard.nodes[graph_clipboard.node_count] = node
		graph_clipboard.node_count += 1
		min_pos.x = min(min_pos.x, node.position.x)
		min_pos.y = min(min_pos.y, node.position.y)}
	graph_clipboard.anchor = min_pos
	for 	item in graph_document.localizations[:graph_document.localization_count] {for node in graph_clipboard.nodes[:graph_clipboard.node_count] do if item.node_id == node.beat.id && graph_clipboard.localization_count < len(graph_clipboard.localizations) {graph_clipboard.localizations[graph_clipboard.localization_count] = item; graph_clipboard.localization_count += 1}}
	graph_feedback(fmt.tprintf("COPIED %d NODES", graph_clipboard.node_count))
	return graph_clipboard.node_count > 0}
graph_clipboard_has_id :: proc(id: string) -> bool {for node in graph_clipboard.nodes[:graph_clipboard.node_count] do if node.beat.id == id do return true
	return false}
graph_paste_clipboard :: proc(
	at: Vec2,
	duplicate := false,
) -> bool {if graph_clipboard.node_count <= 0 || graph_document.node_count + graph_clipboard.node_count > GRAPH_MAX_NODES do return false
	graph_history_push(duplicate ? "Duplicate subgraph" : "Paste subgraph")
	scene := graph_active_scene_id()
	old_ids: [GRAPH_CLIPBOARD_CAPACITY]string
	new_ids: [GRAPH_CLIPBOARD_CAPACITY]string
	world_at := graph_screen_to_world(at)
	offset :=
		duplicate ? Vec2{30, 30} : Vec2{world_at.x - graph_clipboard.anchor.x, world_at.y - graph_clipboard.anchor.y}
	start := graph_document.node_count
	for 	source, i in graph_clipboard.nodes[:graph_clipboard.node_count] {old_ids[i] = source.beat.id; new_ids[i] =
			graph_unique_id(source.beat.id, scene)
		node := source
		node.beat = graph_beat_clone(source.beat)
		node.beat.scene = scene
		node.beat.id = new_ids[i]
		node.position = {source.position.x + offset.x, source.position.y + offset.y}
		graph_document.nodes[graph_document.node_count] = node
		graph_document.node_count += 1}
	remap := proc(target: string, old_ids, new_ids: []string) -> string {if target == "" do return ""
		for id, i in old_ids do if id == target do return new_ids[i]
		return ""}
	for 	i in 0 ..< graph_clipboard.node_count {beat := &graph_document.nodes[start + i].beat; beat.next = remap(
			beat.next,
			old_ids[:graph_clipboard.node_count],
			new_ids[:graph_clipboard.node_count],
		)
		beat.success = remap(
			beat.success,
			old_ids[:graph_clipboard.node_count],
			new_ids[:graph_clipboard.node_count],
		)
		beat.failure = remap(
			beat.failure,
			old_ids[:graph_clipboard.node_count],
			new_ids[:graph_clipboard.node_count],
		)
		beat.cancel = remap(
			beat.cancel,
			old_ids[:graph_clipboard.node_count],
			new_ids[:graph_clipboard.node_count],
		)
		for &target in beat.choice_targets do target = remap(target, old_ids[:graph_clipboard.node_count], new_ids[:graph_clipboard.node_count])}
	for 	item in graph_clipboard.localizations[:graph_clipboard.localization_count] {for old, i in old_ids[:graph_clipboard.node_count] do if item.node_id == old && graph_document.localization_count < len(graph_document.localizations) {copy_item := item; copy_item.node_id = new_ids[i]; graph_document.localizations[graph_document.localization_count] = copy_item; graph_document.localization_count += 1}}
	graph_clear_selection()
	for 	i in 0 ..< graph_clipboard.node_count {graph_state.selection[i] = start + i
		graph_state.selection_count += 1}
	graph_state.selected_node = start + graph_clipboard.node_count - 1
	graph_changed()
	graph_feedback(fmt.tprintf("PASTED %d NODES", graph_clipboard.node_count))
	return true}
graph_duplicate_selection :: proc(at: Vec2) -> bool {if !graph_copy_selection() do return false
	return graph_paste_clipboard(at, true)}
