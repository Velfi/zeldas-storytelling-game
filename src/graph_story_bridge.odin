package main

import "core:fmt"

graph_import_story :: proc(project: ^Story_Project) {
	if project == nil do return
	if len(project.scenes) > GRAPH_MAX_SCENES ||
	   len(project.nodes) > GRAPH_MAX_NODES ||
	   len(project.conditions) > GRAPH_MAX_DEFINITIONS ||
	   len(project.effects) > GRAPH_MAX_DEFINITIONS ||
	   len(project.localizations) > GRAPH_MAX_LOCALIZATIONS {
		// Never construct a partial semantic document: graph_build_story_project
		// replaces the source arrays with this document, so clamping here would
		// turn the next save into silent data loss.
		graph_source_project = nil
		graph_import_error = fmt.tprintf(
			"Story exceeds Graph Mode capacity (scenes %d/%d, nodes %d/%d, conditions %d/%d, effects %d/%d, localizations %d/%d)",
			len(project.scenes),
			GRAPH_MAX_SCENES,
			len(project.nodes),
			GRAPH_MAX_NODES,
			len(project.conditions),
			GRAPH_MAX_DEFINITIONS,
			len(project.effects),
			GRAPH_MAX_DEFINITIONS,
			len(project.localizations),
			GRAPH_MAX_LOCALIZATIONS,
		)
		graph_document = {
			case_id          = project.id,
			diagnostic_count = 1,
			error_count      = 1,
		}
		graph_document.diagnostics[0] = {.Error, "", "", graph_import_error}
		graph_state = {
			active_scene          = -1,
			selected_node         = -1,
			hover_node            = -1,
			selected_condition    = -1,
			selected_effect       = -1,
			selected_localization = -1,
			search_result         = -1,
			zoom                  = 1,
			diagnostics_visible   = true,
		}
		graph_history = {}
		return
	}
	graph_import_error = ""
	graph_source_project = project
	graph_set_picker_create_callback(authoring_graph_picker_create, nil)
	graph_document = {
		case_id = project.id,
	}; graph_state = {
		active_scene          = 0,
		selected_node         = -1,
		hover_node            = -1,
		selected_condition    = -1,
		selected_effect       = -1,
		selected_localization = -1,
		search_result         = -1,
		zoom                  = 1,
	}; graph_history = {}
	graph_document.scene_count = len(
		project.scenes,
	); for scene, i in project.scenes {graph_document.scenes[i] = {
			scene = {
				id = scene.id,
				display_name = scene.display_name,
				source = scene.bound_entity,
				entry = scene.entry_node,
				summary = scene.summary,
				return_to = scene.return_to,
			},
			zoom = 1,
		}}
	graph_document.condition_count = len(
		project.conditions,
	); graph_document.conditions = make([dynamic]Story_Condition, 0, graph_document.condition_count); append(&graph_document.conditions, ..project.conditions[:])
	graph_document.effect_count = len(
		project.effects,
	); graph_document.effects = make([dynamic]Story_Effect, 0, graph_document.effect_count); append(&graph_document.effects, ..project.effects[:])
	graph_document.localization_count = len(
		project.localizations,
	); for item, i in project.localizations do graph_document.localizations[i] = {
		node_id  = item.node_id,
		language = item.language,
		text     = item.text,
		status   = item.status,
		note     = item.note,
		voice    = item.voice,
	}
	graph_document.node_count = len(project.nodes); scene_rows: [GRAPH_MAX_SCENES]int
	for node, i in project.nodes {
		beat := Graph_Beat {
			id                  = node.id,
			scene               = node.scene_id,
			kind                = story_node_kind_text(node.kind),
			line_id             = node.line_id,
			speaker             = node.speaker_id,
			text                = node.text,
			next                = node.next,
			success             = node.success,
			failure             = node.failure,
			cancel              = node.cancel,
			subscene_id         = node.subscene_id,
			ui                  = node.ui,
			camera              = node.camera,
			actor               = node.actor,
			actor_mark          = node.actor_mark,
			animation           = node.animation,
			ui_image_asset_ref  = node.ui_image_asset_ref,
			sound_cue_asset_ref = node.sound_cue_asset_ref,
			animation_asset_ref = node.animation_asset_ref,
			event_id            = node.event_id,
			domain_ref          = node.domain_ref,
			condition_id        = node.condition_id,
			summary             = node.summary,
			ending              = node.ending,
			duration            = node.duration,
			transition          = node.transition,
			blocking            = node.blocking,
			condition_root      = node.condition_root,
			first_effect        = node.first_effect,
			effect_count        = node.effect_count,
		}
		if node.effect_id_count >
		   0 {beat.effect_ids = make([]string, node.effect_id_count); for j in 0 ..< node.effect_id_count do beat.effect_ids[j] = node.effect_ids[j]}
		if node.choice_count >
		   0 {beat.choice_ids = make([]string, node.choice_count); beat.choice_labels = make([]string, node.choice_count); beat.choice_targets = make([]string, node.choice_count); beat.choice_conditions = make([]string, node.choice_count); for j in 0 ..< node.choice_count {beat.choice_ids[j] = node.choices[j].id; beat.choice_labels[j] = node.choices[j].label; beat.choice_targets[j] = node.choices[j].target; beat.choice_conditions[j] = node.choices[j].condition_id}}
		if payload := mystery_payload(project);
		   payload !=
		   nil {if metadata := mystery_dialogue_metadata(payload, node.id); metadata != nil {beat.interaction = metadata.interaction; beat.clue = metadata.clue_id; beat.metadata_requires = graph_clone_strings(metadata.requires[:metadata.require_count]); beat.metadata_unlocks = graph_clone_strings(metadata.unlocks[:metadata.unlock_count]); graph_metadata_read_refs(payload, metadata.requires[:metadata.require_count], &beat.requires_clues, &beat.requires_claims, &beat.requires_topics); graph_metadata_read_refs(payload, metadata.unlocks[:metadata.unlock_count], &beat.unlock_clues, &beat.unlock_claims, &beat.unlock_topics)}}
		scene_index := graph_scene_index(
			node.scene_id,
		); row := 0; if scene_index >= 0 {row = scene_rows[scene_index]; scene_rows[scene_index] += 1}; graph_document.nodes[i] = {
			beat     = beat,
			position = {250 + f32(row % 3) * 220, 105 + f32(row / 3) * 130},
		}
	}
	_ = graph_validate(&graph_document)
}

// Builds an editor-only variation board for visually checking connection-wire
// routing. It deliberately does not retain a source project, so the fixture can
// never be saved or autosaved over authored story data.
graph_configure_routing_test_board :: proc() {
	graph_source_project =
		nil; graph_import_error = ""; graph_autosave_enabled = false; graph_history = {}; graph_clipboard = {}
	graph_document = {
		case_id     = "routing_test_board",
		scene_count = 2,
		node_count  = 19,
	}
	graph_document.scenes[0] = {
		scene = {
			id = "wire_routing",
			entry = "direct_from",
			summary = "Connection wire routing variations",
		},
		zoom = 1,
	}
	graph_document.scenes[1] = {
		scene = {
			id = "wire_crossings",
			entry = "cross_a_from",
			summary = "Crossing and parallel wire clarity",
		},
		zoom = 1,
	}
	graph_document.nodes[0] = {
		beat = {
			id = "direct_from",
			scene = "wire_routing",
			kind = "line",
			speaker = "DIRECT / CLEAR",
			text = "Clear forward route",
			next = "direct_to",
		},
		position = {232, 88},
	}
	graph_document.nodes[1] = {
		beat = {id = "direct_to", scene = "wire_routing", kind = "end"},
		position = {744, 88},
	}
	graph_document.nodes[2] = {
		beat = {
			id = "blocked_from",
			scene = "wire_routing",
			kind = "line",
			speaker = "FORWARD / BLOCKED",
			text = "Route around the card",
			next = "blocked_to",
		},
		position = {232, 238},
	}
	graph_document.nodes[3] = {
		beat = {id = "obstacle", scene = "wire_routing", kind = "stage", text = "OBSTACLE CARD"},
		position = {488, 238},
	}
	graph_document.nodes[4] = {
		beat = {id = "blocked_to", scene = "wire_routing", kind = "end"},
		position = {744, 238},
	}
	graph_document.nodes[5] = {
		beat = {
			id = "back_from",
			scene = "wire_routing",
			kind = "line",
			speaker = "BACK EDGE",
			text = "Outside bottom lane",
			next = "back_to",
		},
		position = {744, 382},
	}
	graph_document.nodes[6] = {
		beat = {id = "back_to", scene = "wire_routing", kind = "end"},
		position = {232, 382},
	}
	choice_ids := make(
		[]string,
		3,
	); choice_labels := make([]string, 3); choice_targets := make([]string, 3); choice_conditions := make([]string, 3)
	choice_ids[0] = "fan_upper_choice"; choice_ids[1] = "fan_middle_choice"; choice_ids[2] = "fan_lower_choice"
	choice_labels[0] = "UPPER"; choice_labels[1] = "MIDDLE"; choice_labels[2] = "LOWER"
	choice_targets[0] = "fan_upper"; choice_targets[1] = "fan_middle"; choice_targets[2] = "fan_lower"
	graph_document.nodes[7] = {
		beat = {
			id = "fan_out",
			scene = "wire_routing",
			kind = "choice",
			text = "Bundled output ports",
			choice_ids = choice_ids,
			choice_labels = choice_labels,
			choice_targets = choice_targets,
			choice_conditions = choice_conditions,
		},
		position = {232, 530},
	}
	graph_document.nodes[8] = {
		beat = {id = "fan_upper", scene = "wire_routing", kind = "end"},
		position = {488, 484},
		collapsed = true,
	}
	graph_document.nodes[9] = {
		beat = {id = "fan_middle", scene = "wire_routing", kind = "end"},
		position = {744, 530},
		collapsed = true,
	}
	graph_document.nodes[10] = {
		beat = {id = "fan_lower", scene = "wire_routing", kind = "end"},
		position = {488, 620},
		collapsed = true,
	}
	graph_document.nodes[11] = {
		beat = {
			id = "cross_a_from",
			scene = "wire_crossings",
			kind = "line",
			speaker = "CROSSING A",
			text = "Descending connection",
			next = "cross_a_to",
		},
		position = {232, 104},
	}
	graph_document.nodes[12] = {
		beat = {id = "cross_a_to", scene = "wire_crossings", kind = "end"},
		position = {744, 350},
	}
	graph_document.nodes[13] = {
		beat = {
			id = "cross_b_from",
			scene = "wire_crossings",
			kind = "line",
			speaker = "CROSSING B",
			text = "Ascending connection",
			next = "cross_b_to",
		},
		position = {232, 350},
	}
	graph_document.nodes[14] = {
		beat = {id = "cross_b_to", scene = "wire_crossings", kind = "end"},
		position = {744, 104},
	}
	parallel_ids := make(
		[]string,
		3,
	); parallel_labels := make([]string, 3); parallel_targets := make([]string, 3); parallel_conditions := make([]string, 3)
	parallel_ids[0] = "parallel_top_choice"; parallel_ids[1] = "parallel_center_choice"; parallel_ids[2] = "parallel_bottom_choice"
	parallel_labels[0] = "TOP"; parallel_labels[1] = "CENTER"; parallel_labels[2] = "BOTTOM"
	parallel_targets[0] = "parallel_top"; parallel_targets[1] = "parallel_center"; parallel_targets[2] = "parallel_bottom"
	graph_document.nodes[15] = {
		beat = {
			id = "parallel_from",
			scene = "wire_crossings",
			kind = "choice",
			text = "Tightly spaced parallel wires",
			choice_ids = parallel_ids,
			choice_labels = parallel_labels,
			choice_targets = parallel_targets,
			choice_conditions = parallel_conditions,
		},
		position = {232, 540},
	}
	// Keep the dense targets clear of the lower-right minimap so the fixture
	// tests wire separation and endpoint association rather than UI occlusion.
	graph_document.nodes[16] = {
		beat = {id = "parallel_top", scene = "wire_crossings", kind = "end"},
		position = {590, 500},
		collapsed = true,
	}
	graph_document.nodes[17] = {
		beat = {id = "parallel_center", scene = "wire_crossings", kind = "end"},
		position = {590, 562},
		collapsed = true,
	}
	graph_document.nodes[18] = {
		beat = {id = "parallel_bottom", scene = "wire_crossings", kind = "end"},
		position = {590, 624},
		collapsed = true,
	}
	graph_state = {
		active_scene  = 0,
		selected_node = -1,
		hover_node    = -1,
		view          = .Graph,
		zoom          = 1,
	}
	_ = graph_validate(&graph_document)
}

graph_configure_minimap_stress_board :: proc() {
	graph_source_project =
		nil; graph_import_error = ""; graph_autosave_enabled = false; graph_history = {}; graph_clipboard = {}
	columns, rows := 32, 8; count := columns * rows; graph_document = {
		case_id     = "minimap_stress_board",
		scene_count = 1,
		node_count  = count,
	}
	graph_document.scenes[0] = {
		scene = {
			id = "minimap_stress",
			entry = "grid_000",
			summary = "Large graph minimap stress fixture",
		},
		zoom = 1,
	}
	for row in 0 ..< rows {for column in 0 ..< columns {i := row * columns + column; id := fmt.tprintf("grid_%03d", i); last := column == columns - 1; next := ""; if !last do next = fmt.tprintf("grid_%03d", i + 1); kind := last ? "end" : "line"; graph_document.nodes[i] = {
				beat = {
					id = id,
					scene = "minimap_stress",
					kind = kind,
					speaker = "STRESS",
					text = fmt.tprintf("Large graph node %03d", i),
					next = next,
				},
				position = {232 + f32(column) * 250, 88 + f32(row) * 138},
				collapsed = (i % 7 == 0),
			}}}
	graph_state = {
		active_scene  = 0,
		selected_node = 0,
		hover_node    = -1,
		view          = .Graph,
		zoom          = 1,
	}; graph_state.selection[0] = 0; graph_state.selection_count = 1
}
