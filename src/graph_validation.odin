package main

import "core:fmt"
import "core:strings"

graph_save_story :: proc(
	path: string,
	source: ^Story_Project,
	mark_clean := true,
) -> Validation {project: Story_Project; if built := graph_build_story_project(source, &project); !built.ok do return built
	defer story_project_destroy(&project)
	saved := save_story_project(path, &project)
	if saved.ok && mark_clean do graph_document.dirty = false
	return saved}

graph_metadata_write_refs :: proc(
	target: ^[MYSTERY_MAX_REFS]string,
	count: ^int,
	groups: ..[]string,
) {count^ = 0; for group in groups do for value in group {if count^ >= len(target^) do return; duplicate := false; for i in 0 ..< count^ do if target^[i] == value do duplicate = true; if !duplicate {target^[count^] = value; count^ += 1}}}

graph_build_story_project :: proc(source: ^Story_Project, out: ^Story_Project) -> Validation {
	if graph_import_error != "" do return {false, graph_import_error}
	if source == nil do return {false, "Graph Mode has no story project"}
	project := story_project_clone(
		source,
	); delete(project.conditions); delete(project.effects); delete(project.localizations); delete(project.scenes); delete(project.nodes); project.conditions = make([dynamic]Story_Condition, 0, graph_document.condition_count); project.effects = make([dynamic]Story_Effect, 0, graph_document.effect_count); project.localizations = make([dynamic]Story_Localization, 0, graph_document.localization_count); project.scenes = make([dynamic]Story_Scene, 0, graph_document.scene_count); project.nodes = make([dynamic]Story_Node, 0, graph_document.node_count)
	append(
		&project.conditions,
		..graph_document.conditions[:graph_document.condition_count],
	); append(&project.effects, ..graph_document.effects[:graph_document.effect_count]); for item in graph_document.localizations[:graph_document.localization_count] do append(&project.localizations, Story_Localization{item.node_id, item.language, item.text, item.status, item.note, item.voice})
	for item in graph_document.scenes[:graph_document.scene_count] {append(&project.scenes, Story_Scene{id = item.scene.id, display_name = item.scene.display_name, entry_node = item.scene.entry, bound_entity = item.scene.source, summary = item.scene.summary, return_to = item.scene.return_to})}
	for item in graph_document.nodes[:graph_document.node_count] {
		beat :=
			item.beat; kind, ok := story_node_kind_from_text(beat.kind); if !ok {story_project_destroy(&project); return {false, fmt.tprintf("Unknown node kind %s", beat.kind)}}
		node := Story_Node {
			id                  = beat.id,
			scene_id            = beat.scene,
			kind                = kind,
			line_id             = beat.line_id,
			speaker_id          = beat.speaker,
			text                = beat.text,
			next                = beat.next,
			success             = beat.success,
			failure             = beat.failure,
			cancel              = beat.cancel,
			subscene_id         = beat.subscene_id,
			ui                  = beat.ui,
			camera              = beat.camera,
			actor               = beat.actor,
			actor_mark          = beat.actor_mark,
			animation           = beat.animation,
			ui_image_asset_ref  = beat.ui_image_asset_ref,
			sound_cue_asset_ref = beat.sound_cue_asset_ref,
			animation_asset_ref = beat.animation_asset_ref,
			event_id            = beat.event_id,
			domain_ref          = beat.domain_ref,
			condition_id        = beat.condition_id,
			summary             = beat.summary,
			ending              = beat.ending,
			duration            = beat.duration,
			transition          = beat.transition,
			blocking            = beat.blocking,
			condition_root      = beat.condition_root,
			first_effect        = beat.first_effect,
			effect_count        = beat.effect_count,
		}
		node.effect_id_count = min(
			len(beat.effect_ids),
			len(node.effect_ids),
		); for i in 0 ..< node.effect_id_count do node.effect_ids[i] = beat.effect_ids[i]
		node.choice_count = min(
			len(beat.choice_labels),
			len(node.choices),
		); for i in 0 ..< node.choice_count {choice_id := i < len(beat.choice_ids) ? beat.choice_ids[i] : ""; if choice_id == "" do choice_id = fmt.tprintf("%s_choice_%d", beat.id, i + 1); node.choices[i] = {
				id           = choice_id,
				label        = beat.choice_labels[i],
				target       = i < len(beat.choice_targets) ? beat.choice_targets[i] : "",
				condition_id = i < len(beat.choice_conditions) ? beat.choice_conditions[i] : "",
			}}
		append(&project.nodes, node)
		if payload := mystery_payload(&project);
		   payload !=
		   nil {metadata := mystery_dialogue_metadata(payload, beat.id); if metadata != nil {metadata.interaction = beat.interaction; metadata.clue_id = beat.clue; if !beat.metadata_refs_dirty {graph_metadata_write_refs(&metadata.requires, &metadata.require_count, beat.metadata_requires); graph_metadata_write_refs(&metadata.unlocks, &metadata.unlock_count, beat.metadata_unlocks)} else {graph_metadata_write_refs(&metadata.requires, &metadata.require_count, beat.requires_clues, beat.requires_claims, beat.requires_topics); graph_metadata_write_refs(&metadata.unlocks, &metadata.unlock_count, beat.unlock_clues, beat.unlock_claims, beat.unlock_topics)}}}
	}
	validation := story_project_validate(
		&project,
	); if !validation.ok {message := len(validation.diagnostics) > 0 ? validation.diagnostics[0].message : "Graph story validation failed"; story_validation_destroy(&validation); story_project_destroy(&project); return {false, message}}; story_validation_destroy(&validation); out^ = project; return {true, "GRAPH STORY READY"}
}

graph_apply_story_runtime :: proc(g: ^Game) -> Validation {
	story_runtime_destroy(
		&graph_playtest_runtime,
	); compiled_story_destroy(&graph_playtest_compiled); story_project_destroy(&graph_playtest_project)
	if built := graph_build_story_project(g.story_project, &graph_playtest_project); !built.ok do return built
	compiled := compile_story_project(
		&graph_playtest_project,
	); if !compiled.ok {message := compiled.message; story_compile_result_destroy(&compiled); story_project_destroy(&graph_playtest_project); return {false, message}}
	graph_playtest_compiled =
		compiled.story; compiled.story = {}; story_validation_destroy(&compiled.validation); graph_playtest_runtime = story_runtime_new(&graph_playtest_compiled, g.spatial_service)
	g.story_project = &graph_playtest_project; g.compiled_story = &graph_playtest_compiled; g.story_runtime = &graph_playtest_runtime; g.story_state = &graph_playtest_runtime.state; g.mystery_state = cast(^Mystery_State)story_runtime_capability_state(&graph_playtest_runtime, "mystery", MYSTERY_DOMAIN_VERSION)
	return {true, "GRAPH PLAYTEST READY"}
}
graph_add_diagnostic :: proc(
	doc: ^Graph_Document,
	severity: Graph_Diagnostic_Severity,
	scene, node, message: string,
) {if doc.diagnostic_count >= len(doc.diagnostics) do return; doc.diagnostics[doc.diagnostic_count] =
		Graph_Diagnostic{severity, scene, node, message}
	doc.diagnostic_count += 1
	if severity == .Error do doc.error_count += 1}

graph_reference_add :: proc(
	out: ^Graph_Reference_List,
	kind, scene, node, field: string,
	choice := -1,
) {if out.count >= len(out.items) {out.truncated = true; return}; out.items[out.count] = {
		kind,
		scene,
		node,
		field,
		choice,
	}
	out.count += 1}
graph_used_by :: proc(kind, id: string) -> Graph_Reference_List {result: Graph_Reference_List; for 	scene in graph_document.scenes[:graph_document.scene_count] {if kind == "scene" && scene.scene.return_to == id do graph_reference_add(&result, "scene", scene.scene.id, "", "return_to")
		if kind == "node" && scene.scene.entry == id do graph_reference_add(&result, "scene", scene.scene.id, "", "entry")}
	for 	node in graph_document.nodes[:graph_document.node_count] {beat := node.beat; if kind == "scene" && beat.subscene_id == id do graph_reference_add(&result, "node", beat.scene, beat.id, "subscene_id")
		if kind == "node" {targets := [4]string{beat.next, beat.success, beat.failure, beat.cancel}
			fields := [4]string{"next", "success", "failure", "cancel"}
			for target, i in targets do if target == id do graph_reference_add(&result, "node", beat.scene, beat.id, fields[i])
			for target, i in beat.choice_targets do if target == id do graph_reference_add(&result, "choice", beat.scene, beat.id, "target", i)}
		if kind == "condition" {if beat.condition_id == id do graph_reference_add(&result, "node", beat.scene, beat.id, "condition_id")
			for value, i in beat.choice_conditions do if value == id do graph_reference_add(&result, "choice", beat.scene, beat.id, "condition_id", i)}
		if kind == "effect" do for value, i in beat.effect_ids do if value == id do graph_reference_add(&result, "node", beat.scene, beat.id, "effect_ids", i)}
	return result}
graph_repair_reference :: proc(
	reference: Graph_Reference,
	replacement: string,
) -> bool {if reference.kind == "scene" {index := graph_scene_index(reference.scene_id); if index < 0 do return false
		if reference.field == "return_to" do graph_document.scenes[index].scene.return_to = replacement
		else if reference.field == "entry" do graph_document.scenes[index].scene.entry = replacement
		else do return false
		graph_changed()
		return true}
	index := graph_node_index(reference.scene_id, reference.node_id)
	if index < 0 do return false
	beat := &graph_document.nodes[index].beat
	switch
	reference.field {case "subscene_id":
		beat.subscene_id = replacement; case "next":
		beat.next = replacement; case "success":
		beat.success = replacement; case "failure":
		beat.failure = replacement; case "cancel":
		beat.cancel = replacement; case "condition_id":
		if reference.kind == "choice" && reference.choice_index >= 0 && reference.choice_index < len(beat.choice_conditions) do beat.choice_conditions[reference.choice_index] = replacement
		else do beat.condition_id = replacement; case "target":
		if reference.choice_index < 0 || reference.choice_index >= len(beat.choice_targets) do return false
		beat.choice_targets[reference.choice_index] = replacement; case "effect_ids":
		if reference.choice_index < 0 || reference.choice_index >= len(beat.effect_ids) do return false
		beat.effect_ids[reference.choice_index] = replacement; case:
		return false}
	graph_changed()
	return true}

graph_validate :: proc(doc: ^Graph_Document) -> Validation {
	doc.diagnostic_count = 0; doc.error_count = 0
	if graph_import_error !=
	   "" {graph_add_diagnostic(doc, .Error, "", "", graph_import_error); return {false, graph_import_error}}
	for scene in doc.scenes[:doc.scene_count] {if scene.scene.id == "" {graph_add_diagnostic(doc, .Error, "", "", "Scene ID is required"); continue}; entry := graph_document_node_index(doc, scene.scene.id, scene.scene.entry); if entry < 0 do graph_add_diagnostic(doc, .Error, scene.scene.id, "", "Scene entry is missing"); end_found := false; for node in doc.nodes[:doc.node_count] do if node.beat.scene == scene.scene.id && node.beat.kind == "end" do end_found = true; if !end_found do graph_add_diagnostic(doc, .Warning, scene.scene.id, "", "Scene has no ending")}
	for node, i in doc.nodes[:doc.node_count] {beat := node.beat; if beat.id == "" || !story_node_kind_valid(beat.kind) {graph_add_diagnostic(doc, .Error, beat.scene, beat.id, "Node has invalid ID or type"); continue}; for candidate, j in doc.nodes[:doc.node_count] do if i != j && candidate.beat.scene == beat.scene && candidate.beat.id == beat.id {graph_add_diagnostic(doc, .Error, beat.scene, beat.id, "Duplicate node ID"); break}; if beat.kind == "line" && beat.text == "" do graph_add_diagnostic(doc, .Error, beat.scene, beat.id, "Line needs dialogue text"); if beat.kind == "choice" && len(beat.choice_labels) != len(beat.choice_targets) do graph_add_diagnostic(doc, .Error, beat.scene, beat.id, "Choice labels and targets differ"); if beat.kind == "choice" do for label in beat.choice_labels do if strings.trim_space(label) == "" do graph_add_diagnostic(doc, .Error, beat.scene, beat.id, "Choice label cannot be empty"); if beat.kind == "check" && (beat.success == "" || beat.failure == "") do graph_add_diagnostic(doc, .Error, beat.scene, beat.id, "Check needs success and failure"); if beat.kind == "interaction" && beat.success == "" do graph_add_diagnostic(doc, .Error, beat.scene, beat.id, "Interaction needs success"); if beat.kind == "wait_event" && beat.event_id == "" do graph_add_diagnostic(doc, .Error, beat.scene, beat.id, "Wait Event needs a bound trigger event"); if beat.kind == "stage" && beat.ui == "hidden" && beat.duration <= 0 && beat.camera == "" && beat.actor_mark == "" do graph_add_diagnostic(doc, .Error, beat.scene, beat.id, "Hidden stage needs a completion cue"); targets := [4]string{beat.next, beat.success, beat.failure, beat.cancel}; for target in targets do if target != "" && graph_document_node_index(doc, beat.scene, target) < 0 do graph_add_diagnostic(doc, .Error, beat.scene, beat.id, fmt.tprintf("Missing target: %s", target)); for target in beat.choice_targets do if target == "" || graph_document_node_index(doc, beat.scene, target) < 0 do graph_add_diagnostic(doc, .Error, beat.scene, beat.id, fmt.tprintf("Missing choice target: %s", target)); camera_index := level_marker_index(&level_document, beat.camera); if beat.camera != "" && (camera_index < 0 || level_document.markers[camera_index].kind != .Camera || level_document.markers[camera_index].story != level_document.active_story) do graph_add_diagnostic(doc, .Error, beat.scene, beat.id, "Camera marker is missing, on another story, or has the wrong type"); actor_index := level_marker_index(&level_document, beat.actor_mark); if beat.actor_mark != "" && (actor_index < 0 || level_document.markers[actor_index].kind != .Staging || level_document.markers[actor_index].story != level_document.active_story) do graph_add_diagnostic(doc, .Error, beat.scene, beat.id, "Actor marker is missing, on another story, or has the wrong type")}
	for &condition, i in doc.conditions[:doc.condition_count] {if strings.trim_space(condition.id) == "" do graph_add_diagnostic(doc, .Error, "", condition.id, "Condition ID is required"); for other, j in doc.conditions[:doc.condition_count] do if i != j && condition.id == other.id {graph_add_diagnostic(doc, .Error, "", condition.id, "Duplicate condition ID"); break}; for child in condition.child_ids[:condition.child_id_count] do if story_condition_index_in_document(child) < 0 do graph_add_diagnostic(doc, .Error, "", condition.id, fmt.tprintf("Missing condition child: %s", child))}
	for effect, i in doc.effects[:doc.effect_count] {if strings.trim_space(effect.id) == "" do graph_add_diagnostic(doc, .Error, "", effect.id, "Effect ID is required"); for other, j in doc.effects[:doc.effect_count] do if i != j && effect.id == other.id {graph_add_diagnostic(doc, .Error, "", effect.id, "Duplicate effect ID"); break}}
	for node in doc.nodes[:doc.node_count] {beat := node.beat; if beat.condition_id != "" && story_condition_index_in_document(beat.condition_id) < 0 do graph_add_diagnostic(doc, .Error, beat.scene, beat.id, fmt.tprintf("Missing condition: %s", beat.condition_id)); for id in beat.choice_conditions do if id != "" && story_condition_index_in_document(id) < 0 do graph_add_diagnostic(doc, .Error, beat.scene, beat.id, fmt.tprintf("Missing choice condition: %s", id)); for id in beat.effect_ids do if id != "" && story_effect_index_in_document(id) < 0 do graph_add_diagnostic(doc, .Error, beat.scene, beat.id, fmt.tprintf("Missing effect: %s", id)); if beat.kind == "subscene" {if graph_scene_index(beat.subscene_id) < 0 do graph_add_diagnostic(doc, .Error, beat.scene, beat.id, fmt.tprintf("Missing subscene: %s", beat.subscene_id)); if beat.subscene_id == beat.scene do graph_add_diagnostic(doc, .Error, beat.scene, beat.id, "Subscene cannot call itself")}}
	for item, i in doc.localizations[:doc.localization_count] {found := false; for node in doc.nodes[:doc.node_count] do if node.beat.id == item.node_id {found = true; break}; if !found do graph_add_diagnostic(doc, .Error, "", item.node_id, "Localization belongs to a missing node"); if strings.trim_space(item.language) == "" do graph_add_diagnostic(doc, .Error, "", item.node_id, "Localization language is required"); for other, j in doc.localizations[:doc.localization_count] do if i != j && item.node_id == other.node_id && item.language == other.language {graph_add_diagnostic(doc, .Error, "", item.node_id, "Duplicate localization language for node"); break}; if item.text == "" do graph_add_diagnostic(doc, .Warning, "", item.node_id, "Translation is missing"); if item.voice == "" do graph_add_diagnostic(doc, .Warning, "", item.node_id, "Voice reference is missing")}
	return {
		doc.error_count == 0,
		doc.error_count == 0 ? "GRAPH VALID" : fmt.tprintf("%d GRAPH ERRORS", doc.error_count),
	}
}
graph_validate_complete :: proc(source: ^Story_Project) -> Validation {light := graph_validate(
		&graph_document,
	)
	if !light.ok do return light
	project: Story_Project
	built := graph_build_story_project(source, &project)
	if !built.ok {graph_add_diagnostic(
			&graph_document,
			.Error,
			graph_active_scene_id(),
			"",
			built.message,
		)
		return built}
	story_project_destroy(&project)
	return{true, "GRAPH AND STORYCORE VALID"}}
