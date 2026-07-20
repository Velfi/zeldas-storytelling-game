package main

graph_clone_strings :: proc(source: []string) -> []string {if source == nil do return nil
	result := make([]string, len(source))
	copy(result, source)
	return result}
graph_beat_clone :: proc(source: Graph_Beat) -> Graph_Beat {result := source; result.choice_ids =
		graph_clone_strings(source.choice_ids)
	result.choice_labels = graph_clone_strings(source.choice_labels)
	result.choice_targets = graph_clone_strings(source.choice_targets)
	result.choice_conditions = graph_clone_strings(source.choice_conditions)
	result.effect_ids = graph_clone_strings(source.effect_ids)
	result.requires_clues = graph_clone_strings(source.requires_clues)
	result.requires_claims = graph_clone_strings(source.requires_claims)
	result.requires_topics = graph_clone_strings(source.requires_topics)
	result.unlock_clues = graph_clone_strings(source.unlock_clues)
	result.unlock_claims = graph_clone_strings(source.unlock_claims)
	result.unlock_topics = graph_clone_strings(source.unlock_topics)
	result.metadata_requires = graph_clone_strings(source.metadata_requires)
	result.metadata_unlocks = graph_clone_strings(source.metadata_unlocks)
	return result}
graph_document_clone :: proc(source: ^Graph_Document) -> Graph_Document {result := source^
	result.conditions = make([dynamic]Story_Condition, 0, source.condition_count)
	append(&result.conditions, ..source.conditions[:source.condition_count])
	result.effects = make([dynamic]Story_Effect, 0, source.effect_count)
	append(&result.effects, ..source.effects[:source.effect_count])
	for i in 0 ..< source.node_count do result.nodes[i].beat = graph_beat_clone(source.nodes[i].beat)
	return result}
graph_history_push :: proc(label: string) {if graph_history.undo_count >=
	   GRAPH_HISTORY_CAPACITY {for i in 1 ..< GRAPH_HISTORY_CAPACITY do graph_history.undo[i - 1] = graph_history.undo[i]
		graph_history.undo_count = GRAPH_HISTORY_CAPACITY - 1}
	graph_history.undo[graph_history.undo_count] = {graph_document_clone(&graph_document), label}
	graph_history.undo_count += 1
	graph_history.redo_count = 0}
graph_undo :: proc() -> bool {if graph_history.undo_count <= 0 do return false; graph_history.redo[graph_history.redo_count] =
		{
			graph_document_clone(&graph_document),
			graph_history.undo[graph_history.undo_count - 1].label,
		}
	graph_history.redo_count += 1
	graph_history.undo_count -= 1
	graph_document = graph_history.undo[graph_history.undo_count].document
	graph_state.selected_node = -1
	return true}
graph_redo :: proc() -> bool {if graph_history.redo_count <= 0 do return false; graph_history.undo[graph_history.undo_count] =
		{
			graph_document_clone(&graph_document),
			graph_history.redo[graph_history.redo_count - 1].label,
		}
	graph_history.undo_count += 1
	graph_history.redo_count -= 1
	graph_document = graph_history.redo[graph_history.redo_count].document
	graph_state.selected_node = -1
	return true}
graph_changed :: proc() {graph_document.revision += 1; graph_document.dirty = true; _ =
		graph_validate(&graph_document)
	_ = authoring_invalidate_after_edit(.Graph, graph_document.revision)
	if graph_autosave_enabled && graph_source_project != nil {saved := graph_save_story(
			graph_active_autosave_path,
			graph_source_project,
			false,
		)
		graph_state.autosave_status = saved.ok ? "AUTOSAVED" : "AUTOSAVE FAILED"}
	else do graph_state.autosave_status = "AUTOSAVE OFF"}
