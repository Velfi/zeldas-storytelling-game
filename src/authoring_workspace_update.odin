package main

import "core:fmt"
import "core:os"
import "core:strings"
import ui "zelda_engine:ui"

update_authoring_workspace :: proc(g: ^Game) {
	if authoring_workspace.form_active &&
	   g.input.key_enter &&
	   int(authoring_workspace.form_action) >=
		   int(
			   Authoring_Form_Action.Asset_Source_URI,
		   ) {value := string(authoring_workspace.form_buffer[:authoring_workspace.form_count]); authoring_workspace.form_active = false; #partial switch authoring_workspace.form_action {case .Asset_Source_URI:
			authoring_workspace.asset_source_uri = strings.clone(value); case .Asset_Source_Name:
			authoring_workspace.asset_source_name = strings.clone(value); case .Asset_Creator:
			authoring_workspace.asset_creator = strings.clone(value); case .Asset_Attribution:
			authoring_workspace.asset_attribution = strings.clone(value); case .Asset_License_ID:
			authoring_workspace.asset_license_id = strings.clone(value); case .Asset_License_Text:
			authoring_workspace.asset_license_text = strings.clone(value); case .Asset_Usage:
			authoring_workspace.feedback = authoring_asset_add_usage(value); case:}; return}
	if authoring_workspace.form_active &&
	   g.input.key_enter &&
	   authoring_workspace.form_action ==
		   .Diagnostic_Search {authoring_workspace.diagnostic_filter.search = strings.clone(string(authoring_workspace.form_buffer[:authoring_workspace.form_count])); authoring_workspace.form_active = false; authoring_workspace.diagnostic_page = 0; authoring_workspace.feedback = "DIAGNOSTIC SEARCH APPLIED"; return}
	if authoring_workspace.form_active &&
	   g.input.key_enter &&
	   (authoring_workspace.form_action == .Project_Metadata ||
			   authoring_workspace.form_action == .Project_Requirement_Add ||
			   authoring_workspace.form_action == .Project_Requirement_Update ||
			   authoring_workspace.form_action == .Case_Rename ||
			   authoring_workspace.form_action ==
				   .Case_Move) {value := string(authoring_workspace.form_buffer[:authoring_workspace.form_count]); authoring_workspace.form_active = false; #partial switch authoring_workspace.form_action {case .Project_Metadata:
			authoring_workspace.feedback = authoring_project_set_metadata(
				value,
			); case .Project_Requirement_Add:
			authoring_workspace.feedback = authoring_project_requirement_commit(
				value,
				false,
			); case .Project_Requirement_Update:
			authoring_workspace.feedback = authoring_project_requirement_commit(
				value,
				true,
			); case .Case_Rename:
			authoring_workspace.feedback = authoring_workspace_case_identity_change(
				value,
				false,
			); case .Case_Move:
			authoring_workspace.feedback = authoring_workspace_case_identity_change(
				value,
				true,
			); case:}; return}
	if authoring_workspace.form_active {box := Rect{320, 560, 560, 38}; id := button_id(box); g.gui.focused = id; ui.gui_text_edit_begin(&g.gui, id, authoring_workspace.form_count); ui.gui_text_edit_handle_mouse(&g.gui, id, authoring_workspace.form_buffer[:], authoring_workspace.form_count, ui.Rect(box), ui.Vec2{box.x + 8, box.y + 8}); _ = ui.gui_text_edit_process(&g.gui, id, authoring_workspace.form_buffer[:], &authoring_workspace.form_count); if g.input.key_enter {authoring_workspace.form_active = false; value := string(authoring_workspace.form_buffer[:authoring_workspace.form_count]); if authoring_workspace.form_action == .Add {if authoring_workspace.tab == .Story_Data do authoring_workspace_add_story_record()
				else if authoring_workspace.tab == .Mystery do authoring_workspace.feedback = authoring_workspace_add_mystery_from_selected(value)
				else do authoring_workspace.feedback = "CREATE FORM IS NOT AVAILABLE FOR THIS PANEL"} else if authoring_workspace.form_action == .Story_Field {kind := Story_Authoring_Record_Kind(authoring_workspace.selected_category); field, _ := authoring_story_scalar_field(kind, authoring_story_field_cursor); authoring_workspace.feedback = authoring_story_update_field(kind, authoring_workspace.selected_record, field, value)} else if authoring_workspace.form_action == .Story_List_Add {kind := Story_Authoring_Record_Kind(authoring_workspace.selected_category); field, _ := authoring_story_list_field(kind, authoring_story_list_cursor); authoring_workspace.feedback = authoring_story_update_list(kind, authoring_workspace.selected_record, field, .Add, authoring_story_list_item, value)} else if authoring_workspace.form_action == .Story_List_Create {kind := Story_Authoring_Record_Kind(authoring_workspace.selected_category); field, _ := authoring_story_list_field(kind, authoring_story_list_cursor); authoring_workspace.feedback = authoring_story_list_create_in_picker(kind, authoring_workspace.selected_record, field, authoring_story_list_item, Story_Authoring_Record_Kind(authoring_story_picker_kind), value)} else if authoring_workspace.form_action == .Mystery_Text {kind := Mystery_Authoring_Record_Kind(authoring_workspace.selected_category); field, _, _ := authoring_mystery_scalar_field(kind, authoring_mystery_field_cursor); authoring_workspace.feedback = authoring_mystery_set_text(field, value)} else if authoring_workspace.form_action == .Mystery_Number {kind := Mystery_Authoring_Record_Kind(authoring_workspace.selected_category); field, _, _ := authoring_mystery_scalar_field(kind, authoring_mystery_field_cursor); authoring_workspace.feedback = authoring_mystery_set_number(field, value)} else if authoring_workspace.form_action == .Mystery_List_Add {kind := Mystery_Authoring_Record_Kind(authoring_workspace.selected_category); field, _ := authoring_mystery_list_field(kind, authoring_mystery_list_cursor); authoring_workspace.feedback = authoring_mystery_update_list(field, .Add, authoring_mystery_list_item, value)} else if authoring_workspace.form_action == .Mystery_Route_Add {parts := strings.split(value, ","); if len(parts) == 2 {first, fok := authoring_story_parse_int(parts[0]); route_count, cok := authoring_story_parse_int(parts[1]); if fok && cok do authoring_workspace.feedback = authoring_mystery_demonstration_route_edit(.Add, authoring_mystery_list_item, first, route_count)}} else if authoring_workspace.tab == .Story_Data {authoring_workspace.feedback = authoring_workspace_story_command(.Rename, value)} else if authoring_workspace.tab == .Mystery {authoring_workspace.feedback = authoring_workspace_mystery_command(.Rename, value)}}; if g.input.key_escape do authoring_workspace.form_active = false; return}
	if g.input.back {closed := authoring_workspace_request_lifecycle(.Close_Workspace); authoring_workspace.feedback = closed.message; if closed.ok do g.screen = .Campaign_Action; g.input.back = false; return}
	for tab in Authoring_Workspace_Tab do if button(g, {18 + f32(int(tab)) * 166, 62, 156, 38}) {authoring_workspace.tab = tab; authoring_workspace.confirm_delete = false}
	if button(
		g,
		{18, 666, 150, 38},
	) {closed := authoring_workspace_request_lifecycle(.Close_Workspace); authoring_workspace.feedback = closed.message; if closed.ok do g.screen = .Campaign_Action}
	if authoring_workspace.pending_lifecycle !=
	   .None {if button(g, {300, 614, 170, 38}) do authoring_workspace.feedback = authoring_workspace_resolve_lifecycle(g, false).message; if button(g, {480, 614, 190, 38}) do authoring_workspace.feedback = authoring_workspace_resolve_lifecycle(g, true).message; if button(g, {680, 614, 150, 38}) {authoring_workspace.pending_lifecycle = .None; authoring_workspace.feedback = "LIFECYCLE ACTION CANCELLED"}; return}
	#partial switch authoring_workspace.tab {
	case .Project:
		if button(g, {30, 130, 210, 40}) {id := authoring_workspace_next_id("story")
			authoring_workspace.feedback = authoring_app_new_case(id, "New Story", false).message}
		if button(g, {250, 130, 210, 40}) {id := authoring_workspace_next_id("mystery")
			authoring_workspace.feedback = authoring_app_new_case(id, "New Mystery", true).message}
		if button(
			g,
			{470, 130, 210, 40},
		) {path := authoring_native_select_directory("Open Story Project")
			if path != "" do authoring_workspace.feedback = authoring_workspace_request_lifecycle(.Open_Project, -1, path).message}
		if button(g, {30, 184, 210, 40}) do authoring_workspace.feedback = authoring_app_save_all().message
		if button(
			g,
			{250, 184, 210, 40},
		) {parent := authoring_native_select_directory("Choose Parent Folder for Project Copy")
			if parent !=
			   "" {saved := authoring_app_save_all(); if saved.ok {destination, error := os.join_path([]string{parent, active_authoring_project.id}, context.temp_allocator)
					if error != nil do saved = {false, "Save As destination is invalid"}
					else do saved = authoring_project_save_as(&active_authoring_project, destination)}
				if saved.ok {authoring_workspace.sequence += 1; authoring_recent_record(&authoring_workspace.recents, &active_authoring_project, u64(authoring_workspace.sequence))
					if recent_path, path_ok := authoring_recents_default_path(); path_ok do _ = authoring_recents_save(&authoring_workspace.recents, recent_path)}
				authoring_workspace.feedback = saved.message}}
		if item := authoring_workspace_case();
		   item !=
		   nil {if button(g, {470, 184, 210, 40}) {if guard := authoring_app_dirty_guard(); !guard.ok do authoring_workspace.feedback = "SAVE OR KEEP RECOVERY BEFORE DUPLICATING THIS CASE"
				else {id := authoring_workspace_next_id(item.id); authoring_workspace.feedback = authoring_app_duplicate_case(item.id, id, fmt.tprintf("%s Copy", item.title)).message}}
			if button(
				g,
				{690, 184, 210, 40},
			) {if authoring_workspace.confirm_delete {if guard := authoring_app_dirty_guard(); !guard.ok do authoring_workspace.feedback = "SAVE OR KEEP RECOVERY BEFORE DELETING THIS CASE"
					else do authoring_workspace.feedback = authoring_app_delete_case(item.id).message
					authoring_workspace.confirm_delete =
						false} else {authoring_workspace.confirm_delete = true
					authoring_workspace.feedback = "PRESS DELETE AGAIN TO MOVE CASE TO RECOVERABLE TRASH"}}}
		if button(g, {30, 238, 210, 40}) do authoring_workspace.feedback = authoring_app_save_recovery().message
		if button(g, {30, 292, 210, 40}) do authoring_workspace.feedback = authoring_workspace_apply_recovery()
		if button(
			g,
			{250, 292, 210, 40},
		) {if authoring_workspace.playtest.active {ended := authoring_playtest_end(&authoring_workspace.playtest, &active_story_project, &active_story_runtime, &graph_document, &level_document, &campaign_document, &campaign_playthrough)
				authoring_workspace.feedback =
					ended.message} else {started := authoring_playtest_begin(&authoring_workspace.playtest, &active_story_project, &active_story_runtime, &graph_document, &level_document, &campaign_document, &campaign_playthrough, &authoring_workspace.assets)
				authoring_workspace.feedback = started.message}}
		if active_authoring_read_only &&
		   button(g, {250, 238, 300, 40}) {item := authoring_workspace_case()
			if item != nil {id := authoring_workspace_next_id(item.id)
				authoring_workspace.feedback =
					authoring_app_create_editable_copy(item.id, id, fmt.tprintf("%s Editable", item.title)).message}}
		case_count := active_authoring_project.case_count
		if case_count >
		   0 {if button(g, {570, 238, 120, 40}) {next := (active_authoring_project.active_case + case_count - 1) % case_count
				authoring_workspace.feedback =
					authoring_workspace_request_lifecycle(.Switch_Case, next).message}
			if button(
				g,
				{700, 238, 120, 40},
			) {next := (active_authoring_project.active_case + 1) % case_count
				authoring_workspace.feedback =
					authoring_workspace_request_lifecycle(.Switch_Case, next).message}
			if button(
				g,
				{830, 238, 120, 40},
			) {item := authoring_workspace_case(); if item != nil do authoring_project_begin_form(.Case_Rename, item.id)}
			if button(
				g,
				{960, 238, 120, 40},
			) {item := authoring_workspace_case(); if item != nil do authoring_project_begin_form(.Case_Move, item.directory)}}
		if button(
			g,
			{470, 292, 210, 40},
		) {path := authoring_native_select_directory("Recover Moved Story Project")
			if path != "" do authoring_workspace.feedback = authoring_workspace_request_lifecycle(.Open_Project, -1, path).message}
		if authoring_workspace.recents.count >
		   0 {authoring_workspace.selected_recent = clamp(authoring_workspace.selected_recent, 0, authoring_workspace.recents.count - 1)
			if button(g, {690, 292, 90, 40}) do authoring_workspace.selected_recent = (authoring_workspace.selected_recent + authoring_workspace.recents.count - 1) % authoring_workspace.recents.count
			if button(g, {790, 292, 90, 40}) do authoring_workspace.selected_recent = (authoring_workspace.selected_recent + 1) % authoring_workspace.recents.count
			if button(
				g,
				{890, 292, 190, 40},
			) {recent := authoring_workspace.recents.items[authoring_workspace.selected_recent]
				authoring_workspace.feedback =
					authoring_workspace_request_lifecycle(.Open_Project, -1, recent.root_path).message}}
		if button(g, {30, 350, 80, 32}) do authoring_project_metadata_cursor = (authoring_project_metadata_cursor + 5) % 6
		if button(g, {120, 350, 80, 32}) do authoring_project_metadata_cursor = (authoring_project_metadata_cursor + 1) % 6
		if button(g, {210, 350, 240, 32}) {_, value := authoring_project_metadata_field()
			authoring_project_begin_form(.Project_Metadata, value)}
		if button(
			g,
			{30, 398, 220, 32},
		) {authoring_project_requirement_kind = 1 - authoring_project_requirement_kind
			authoring_project_requirement_index = 0}
		count := authoring_project_requirement_count()
		if count >
		   0 {authoring_project_requirement_index = clamp(authoring_project_requirement_index, 0, count - 1); if button(g, {260, 398, 80, 32}) do authoring_project_requirement_index = (authoring_project_requirement_index + count - 1) % count; if button(g, {350, 398, 80, 32}) do authoring_project_requirement_index = (authoring_project_requirement_index + 1) % count}
		if button(g, {30, 442, 90, 32}) do authoring_project_begin_form(.Project_Requirement_Add)
		if count > 0 && button(g, {130, 442, 90, 32}) do authoring_project_begin_form(.Project_Requirement_Update, fmt.tprintf("%s@%s", authoring_project_requirement_kind == 0 ? active_story_project.expansion_requirements[authoring_project_requirement_index].id : active_story_project.capabilities[authoring_project_requirement_index].id, authoring_project_requirement_kind == 0 ? active_story_project.expansion_requirements[authoring_project_requirement_index].version : active_story_project.capabilities[authoring_project_requirement_index].version))
		if count > 0 && button(g, {230, 442, 90, 32}) do authoring_workspace.feedback = authoring_project_requirement_action(authoring_project_requirement_kind == 0 ? .Remove_Expansion : .Remove_Capability)
		if count > 0 && button(g, {330, 442, 70, 32}) do authoring_workspace.feedback = authoring_project_requirement_action(authoring_project_requirement_kind == 0 ? .Reorder_Expansion : .Reorder_Capability, -1)
		if count > 0 && button(g, {410, 442, 70, 32}) do authoring_workspace.feedback = authoring_project_requirement_action(authoring_project_requirement_kind == 0 ? .Reorder_Expansion : .Reorder_Capability, 1)
		if authoring_project_requirement_kind == 0 &&
		   count >
			   0 {if button(g, {30, 486, 120, 30}) do authoring_workspace.feedback = authoring_project_expansion_toggle(0); if button(g, {160, 486, 120, 30}) do authoring_workspace.feedback = authoring_project_expansion_toggle(1); if button(g, {290, 486, 120, 30}) do authoring_workspace.feedback = authoring_project_expansion_toggle(2)}
	case .Story_Data:
		for kind in Story_Authoring_Record_Kind {i := int(kind)
			if button(
				g,
				{30 + f32(i % 4) * 280, 120 + f32(i / 4) * 42, 266, 34},
			) {authoring_workspace.selected_category = i; authoring_workspace.selected_record = 0
				authoring_story_field_cursor = 0
				authoring_story_list_cursor = 0
				authoring_story_list_item = 0}}
		kind := Story_Authoring_Record_Kind(
			clamp(
				authoring_workspace.selected_category,
				0,
				int(Story_Authoring_Record_Kind.Effect),
			),
		)
		count := authoring_story_count(kind)
		if count >
		   0 {authoring_workspace.selected_record = clamp(authoring_workspace.selected_record, 0, count - 1)
			if button(g, {30, 376, 180, 34}) do authoring_workspace.selected_record = (authoring_workspace.selected_record + count - 1) % count
			if button(g, {220, 376, 180, 34}) do authoring_workspace.selected_record = (authoring_workspace.selected_record + 1) % count}
		if button(g, {30, 330, 100, 38}) {authoring_workspace.form_active = true
			authoring_workspace.form_action = .Add
			authoring_workspace.form_count = 0}
		if button(g, {140, 330, 100, 38}) do authoring_workspace.feedback = authoring_workspace_duplicate_story()
		if button(g, {250, 330, 100, 38}) {authoring_workspace.form_active = true
			authoring_workspace.form_action = .Rename
			authoring_workspace.form_count = 0}
		if button(g, {360, 330, 100, 38}) do authoring_workspace.feedback = authoring_workspace_story_command(.Remove)
		if button(g, {470, 330, 70, 38}) do authoring_workspace.feedback = authoring_workspace_story_command(.Reorder, "up")
		if button(g, {550, 330, 70, 38}) do authoring_workspace.feedback = authoring_workspace_story_command(.Reorder, "down")
		if button(
			g,
			{630, 330, 100, 38},
		) {if story_authoring_undo(&active_story_project, &authoring_workspace.story_history) do authoring_workspace.feedback = "STORY UNDO"}
		if button(
			g,
			{740, 330, 100, 38},
		) {if story_authoring_redo(&active_story_project, &authoring_workspace.story_history) do authoring_workspace.feedback = "STORY REDO"}
		if button(g, {850, 330, 150, 38}) do authoring_workspace.feedback = authoring_creator_truth_access(!authoring_creator_truth_revealed)
		if count > 0 && button(g, {1010, 330, 150, 38}) do authoring_workspace.feedback = authoring_story_focus_first_usage(kind, authoring_story_id(kind, authoring_workspace.selected_record))
		field, field_count := authoring_story_scalar_field(kind, authoring_story_field_cursor)
		if button(g, {30, 422, 70, 32}) do authoring_story_field_cursor = (authoring_story_field_cursor + field_count - 1) % field_count
		if button(g, {110, 422, 70, 32}) do authoring_story_field_cursor = (authoring_story_field_cursor + 1) % field_count
		if count > 0 && button(g, {190, 422, 180, 32}) do authoring_story_begin_form(.Story_Field)
		list, list_count := authoring_story_list_field(kind, authoring_story_list_cursor)
		if list_count >
		   0 {if button(g, {30, 464, 70, 32}) do authoring_story_list_cursor = (authoring_story_list_cursor + list_count - 1) % list_count; if button(g, {110, 464, 70, 32}) {authoring_story_list_cursor = (authoring_story_list_cursor + 1) % list_count; authoring_story_list_item = 0}; items := authoring_story_list_count(kind, authoring_workspace.selected_record, list); if items > 0 {authoring_story_list_item = clamp(authoring_story_list_item, 0, items - 1); if button(g, {190, 464, 70, 32}) do authoring_story_list_item = (authoring_story_list_item + items - 1) % items; if button(g, {270, 464, 70, 32}) do authoring_story_list_item = (authoring_story_list_item + 1) % items}; if count > 0 && button(g, {350, 464, 90, 32}) do authoring_story_begin_form(.Story_List_Add); if items > 0 && button(g, {450, 464, 90, 32}) do authoring_workspace.feedback = authoring_story_update_list(kind, authoring_workspace.selected_record, list, .Remove, authoring_story_list_item); if items > 0 && button(g, {550, 464, 60, 32}) do authoring_workspace.feedback = authoring_story_update_list(kind, authoring_workspace.selected_record, list, .Move_Up, authoring_story_list_item); if items > 0 && button(g, {620, 464, 60, 32}) do authoring_workspace.feedback = authoring_story_update_list(kind, authoring_workspace.selected_record, list, .Move_Down, authoring_story_list_item); if button(g, {690, 464, 190, 32}) do authoring_story_picker_kind = (authoring_story_picker_kind + 1) % len(Story_Authoring_Record_Kind); if count > 0 && button(g, {890, 464, 170, 32}) do authoring_story_begin_form(.Story_List_Create)}
	case .Mystery:
		categories := [18]string {
			"SETUP",
			"CHARACTERS",
			"LOCATIONS",
			"POIS",
			"EVENTS",
			"CLUES",
			"CLAIMS",
			"CONTRADICTIONS",
			"DEDUCTIONS",
			"QUESTIONS",
			"DEMONSTRATIONS",
			"DIALOGUE",
			"ENDINGS",
			"CITY LABELS",
			"TUTORIAL",
			"SOLUTION",
			"ROUTES",
			"SUPPORT MAP",
		}
		for label, i in categories do if button(g, {30 + f32(i % 3) * 370, 120 + f32(i / 3) * 44, 350, 36}) {authoring_workspace.selected_category = i; authoring_workspace.selected_record = 0}
		if button(g, {30, 410, 220, 38}) do authoring_workspace_recheck()
		if button(g, {260, 410, 100, 38}) do authoring_workspace.feedback = authoring_workspace_mystery_setup_delta(-1)
		if button(g, {370, 410, 100, 38}) do authoring_workspace.feedback = authoring_workspace_mystery_setup_delta(1)
		if button(g, {480, 410, 260, 38}) do authoring_workspace.feedback = authoring_workspace_cycle_culprit()
		if authoring_workspace.selected_category >=
		   16 {edges := authoring_mystery_panel_edge_count(authoring_workspace.selected_category)
			pages := max(1, (edges + 4) / 5)
			authoring_workspace.selected_record = clamp(
				authoring_workspace.selected_record,
				0,
				pages - 1,
			)
			for visible_row in 0 ..< 5 {row := authoring_workspace.selected_record * 5 + visible_row
				_, source_kind, source_index, _, target_kind, target_index, ok :=
					authoring_mystery_panel_edge(authoring_workspace.selected_category, row)
				if !ok do break
				y := 462 + f32(visible_row) * 36
				if source_index >= 0 && button(g, {30, y, 500, 30}) do authoring_mystery_focus_support_record(source_kind, source_index)
				if target_index >= 0 && button(g, {580, y, 500, 30}) do authoring_mystery_focus_support_record(target_kind, target_index)}
			if button(g, {820, 642, 120, 24}) do authoring_workspace.selected_record = (authoring_workspace.selected_record + pages - 1) % pages
			if button(g, {950, 642, 120, 24}) do authoring_workspace.selected_record = (authoring_workspace.selected_record + 1) % pages
			break}
		kind := Mystery_Authoring_Record_Kind(
			clamp(
				authoring_workspace.selected_category,
				0,
				int(Mystery_Authoring_Record_Kind.Solution),
			),
		)
		count := authoring_mystery_count(kind)
		if count >
		   0 {authoring_workspace.selected_record = clamp(authoring_workspace.selected_record, 0, count - 1)
			if button(g, {30, 462, 100, 34}) do authoring_workspace.selected_record = (authoring_workspace.selected_record + count - 1) % count
			if button(g, {140, 462, 100, 34}) do authoring_workspace.selected_record = (authoring_workspace.selected_record + 1) % count}
		if button(g, {250, 462, 100, 34}) {authoring_workspace.form_active = true
			authoring_workspace.form_action = .Add
			authoring_workspace.form_count = 0}
		if button(g, {360, 462, 100, 34}) {authoring_workspace.form_active = true
			authoring_workspace.form_action = .Rename
			authoring_workspace.form_count = 0}
		if button(g, {470, 462, 100, 34}) do authoring_workspace.feedback = authoring_workspace_mystery_command(.Remove)
		if button(g, {580, 462, 70, 34}) do authoring_workspace.feedback = authoring_workspace_mystery_command(.Reorder, "up")
		if button(g, {660, 462, 70, 34}) do authoring_workspace.feedback = authoring_workspace_mystery_command(.Reorder, "down")
		field, field_type, field_count := authoring_mystery_scalar_field(
			kind,
			authoring_mystery_field_cursor,
		)
		if field_count >
		   0 {if button(g, {30, 508, 70, 32}) do authoring_mystery_field_cursor = (authoring_mystery_field_cursor + field_count - 1) % field_count
			if button(g, {110, 508, 70, 32}) do authoring_mystery_field_cursor = (authoring_mystery_field_cursor + 1) % field_count
			if field_type ==
			   'b' {if button(g, {190, 508, 220, 32}) do authoring_workspace.feedback = authoring_mystery_toggle_bool(field)} else if button(g, {190, 508, 220, 32}) do authoring_story_begin_form(field_type == 'n' ? .Mystery_Number : .Mystery_Text)}
		if kind == .Demonstration && count > 0 && button(g, {930, 508, 230, 32}) do authoring_workspace.feedback = authoring_workspace_preview_demonstration(g)
		list, list_count := authoring_mystery_list_field(kind, authoring_mystery_list_cursor)
		if list_count >
		   0 {if button(g, {30, 548, 70, 32}) do authoring_mystery_list_cursor = (authoring_mystery_list_cursor + list_count - 1) % list_count
			if button(g, {110, 548, 70, 32}) do authoring_mystery_list_cursor = (authoring_mystery_list_cursor + 1) % list_count
			items := authoring_mystery_selected_list_count(list)
			if items > 0 && button(g, {190, 548, 70, 32}) do authoring_mystery_list_item = (authoring_mystery_list_item + items - 1) % items
			if items > 0 && button(g, {270, 548, 70, 32}) do authoring_mystery_list_item = (authoring_mystery_list_item + 1) % items
			if button(g, {350, 548, 90, 32}) do authoring_story_begin_form(.Mystery_List_Add)
			if items > 0 && button(g, {450, 548, 90, 32}) do authoring_workspace.feedback = authoring_mystery_update_list(list, .Remove, authoring_mystery_list_item)
			if items > 0 && button(g, {550, 548, 60, 32}) do authoring_workspace.feedback = authoring_mystery_update_list(list, .Move_Up, authoring_mystery_list_item)
			if items > 0 && button(g, {620, 548, 60, 32}) do authoring_workspace.feedback = authoring_mystery_update_list(list, .Move_Down, authoring_mystery_list_item)}
		if kind ==
		   .Demonstration {route_command, route_ok := authoring_mystery_selected_update(); route_count := route_ok ? route_command.demonstration.route_count : 0; if button(g, {700, 548, 150, 32}) do authoring_story_begin_form(.Mystery_Route_Add); if route_count > 0 && button(g, {860, 548, 100, 32}) do authoring_workspace.feedback = authoring_mystery_demonstration_route_edit(.Remove, authoring_mystery_list_item, 0, 0); if route_count > 0 && button(g, {970, 548, 70, 32}) do authoring_workspace.feedback = authoring_mystery_demonstration_route_edit(.Move_Up, authoring_mystery_list_item, 0, 0)}
		if list_count > 0 &&
		   button(
			   g,
			   {1050, 548, 120, 32},
		   ) {id := authoring_workspace_next_id("picked"); authoring_workspace.feedback = authoring_mystery_create_in_picker(list, id)}
	case .Diagnostics:
		authoring_workspace_diagnostic_filter_ensure()
		if button(g, {30, 120, 140, 34}) do authoring_workspace_recheck()
		if button(
			g,
			{180, 120, 150, 34},
		) {authoring_workspace.selected_category = (authoring_workspace.selected_category + 1) % 4; authoring_workspace_recheck()}
		if button(
			g,
			{340, 120, 150, 34},
		) {authoring_workspace.diagnostic_filter.minimum_severity = Authoring_Diagnostic_Severity((int(authoring_workspace.diagnostic_filter.minimum_severity) + 1) % len(Authoring_Diagnostic_Severity)); authoring_workspace.diagnostic_page = 0}
		if button(
			g,
			{500, 120, 150, 34},
		) {authoring_workspace.diagnostic_domain = (authoring_workspace.diagnostic_domain + 1) % len(Authoring_Validation_Domain)}
		if button(
			g,
			{660, 120, 150, 34},
		) {domain := Authoring_Validation_Domain(authoring_workspace.diagnostic_domain); authoring_workspace.diagnostic_filter.domain_enabled[domain] = !authoring_workspace.diagnostic_filter.domain_enabled[domain]; authoring_workspace.diagnostic_page = 0}
		if button(g, {820, 120, 180, 34}) do authoring_project_begin_form(.Diagnostic_Search, authoring_workspace.diagnostic_filter.search)
		if button(
			g,
			{1010, 120, 160, 34},
		) {_ = authoring_apply_invalidation(&authoring_workspace.production_validation, Authoring_Validation_Domain(authoring_workspace.diagnostic_domain), active_story_project.revision); authoring_workspace.feedback = "AFFECTED DOMAINS INVALIDATED"}
		indices := authoring_workspace_diagnostic_indices(

		); defer delete(indices); pages := max(1, (len(indices) + 5) / 6); authoring_workspace.diagnostic_page = clamp(authoring_workspace.diagnostic_page, 0, pages - 1); start := authoring_workspace.diagnostic_page * 6; for row in 0 ..< min(6, len(indices) - start) {index := indices[start + row]; diagnostic := authoring_workspace.production_validation.diagnostics[index]; if button(g, {30, 198 + f32(row) * 40, 690, 34}) {_ = authoring_navigation_dispatch(diagnostic, g); authoring_workspace.feedback = fmt.tprintf("FOCUSED %s · %s", diagnostic.entity_id, diagnostic.field_path)}}; if button(g, {30, 448, 120, 30}) do authoring_workspace.diagnostic_page = max(0, authoring_workspace.diagnostic_page - 1); if button(g, {160, 448, 120, 30}) do authoring_workspace.diagnostic_page = min(pages - 1, authoring_workspace.diagnostic_page + 1)
		if button(
			g,
			{750, 198, 200, 32},
		) {authoring_workspace.playtest_start_mode = (authoring_workspace.playtest_start_mode + 1) % len(Authoring_Playtest_Start_Mode)}
		if button(
			g,
			{960, 198, 200, 32},
		) {if authoring_workspace.playtest.active do authoring_workspace.feedback = authoring_workspace_end_playtest(g)
			else do authoring_workspace.feedback = authoring_workspace_start_playtest(g)}
		if button(
			g,
			{750, 240, 200, 32},
		) {authoring_workspace.creator_category = (authoring_workspace.creator_category + 1) % 7; authoring_workspace.creator_cursor = 0}; if button(g, {960, 240, 95, 32}) do authoring_workspace.creator_cursor += 1; if button(g, {1065, 240, 95, 32}) do authoring_workspace.feedback = authoring_workspace_creator_add(authoring_workspace.creator_category)
		if button(
			g,
			{750, 282, 200, 32},
		) {authoring_creator_setup_destroy(&authoring_workspace.creator_setup); authoring_workspace.creator_setup.action_budget = -1; authoring_workspace.creator_setup.time_minutes = -1; authoring_workspace.feedback = "CREATOR STATE RESET"}
		if button(g, {960, 282, 95, 32}) do authoring_workspace.creator_setup.action_budget = max(-1, authoring_workspace.creator_setup.action_budget - 1); if button(g, {1065, 282, 95, 32}) do authoring_workspace.creator_setup.action_budget += 1
		if button(
			g,
			{750, 324, 200, 32},
		) {authoring_workspace.scenario_recording = !authoring_workspace.scenario_recording; if authoring_workspace.scenario_recording && authoring_workspace.scenario_record.id == "" do authoring_workspace.scenario_record = authoring_scenario_record_init("creator_recording", "Recorded from unified playtest")}
		if button(
			g,
			{960, 324, 95, 32},
		) {scene := ""; if graph_state.active_scene >= 0 && graph_state.active_scene < graph_document.scene_count do scene = graph_document.scenes[graph_state.active_scene].scene.id; authoring_workspace.feedback = authoring_workspace_record_step({action = "start", value = scene})}; if button(g, {1065, 324, 95, 32}) do authoring_workspace.feedback = authoring_workspace_record_step({action = "advance"})
		if button(g, {750, 366, 125, 32}) do authoring_workspace.feedback = authoring_workspace_record_step({action = "reveal"}); if button(g, {885, 366, 125, 32}) do authoring_workspace.feedback = authoring_workspace_replay_scenario(); if button(g, {1020, 366, 140, 32}) {path := authoring_native_save_file("Export Scenario Failure Trace", "scenario-failure.toml"); if path != "" do authoring_workspace.feedback = authoring_workspace_export_failure(path)}
		if button(
			g,
			{750, 408, 95, 30},
		) {choice := ""; if graph_state.selected_node >= 0 && graph_state.selected_node < graph_document.node_count && len(graph_document.nodes[graph_state.selected_node].beat.choice_ids) > 0 do choice = graph_document.nodes[graph_state.selected_node].beat.choice_ids[0]; authoring_workspace.feedback = authoring_workspace_record_step({action = "choose", value = choice})}; if button(g, {855, 408, 95, 30}) do authoring_workspace.feedback = authoring_workspace_record_step({action = "check", outcome = "success"}); if button(g, {960, 408, 95, 30}) {payload := mystery_payload(&active_story_project); id := ""; if payload != nil && len(payload.clues) > 0 do id = payload.clues[authoring_workspace.creator_cursor % len(payload.clues)].id; authoring_workspace.feedback = authoring_workspace_record_step({action = "know", state = "clue", value = id})}; if button(g, {1065, 408, 95, 30}) {payload := mystery_payload(&active_story_project); id := ""; if payload != nil && len(payload.demonstrations) > 0 do id = payload.demonstrations[authoring_workspace.creator_cursor % len(payload.demonstrations)].id; authoring_workspace.feedback = authoring_workspace_record_step({action = "demonstrate", value = id})}
	case .Assets:
		if button(
			g,
			{30, 120, 170, 38},
		) {path := authoring_native_open_file("Import Project Asset")
			if path != "" do authoring_workspace.feedback = authoring_asset_import_selected(path)}
		if button(
			g,
			{210, 120, 170, 38},
		) {path := authoring_native_select_directory("Search for Missing Assets")
			if path != "" do authoring_workspace.feedback = authoring_asset_preview_relink(path)}
		if button(
			g,
			{390, 120, 170, 38},
		) {path := authoring_native_open_file("Review Replacement Asset")
			if path != "" do authoring_workspace.feedback = authoring_asset_preview_replacement_selected(path)}
		if button(g, {570, 120, 150, 38}) &&
		   len(authoring_workspace.assets.assets) >
			   0 {i := clamp(authoring_workspace.selected_asset, 0, len(authoring_workspace.assets.assets) - 1)
			authoring_asset_history_begin()
			result := project_asset_registry_remove(
				&authoring_workspace.assets,
				authoring_workspace.assets.assets[i].id,
			)
			authoring_workspace.feedback = authoring_asset_finish_transaction(result)
			authoring_workspace.selected_asset = clamp(
				i,
				0,
				max(0, len(authoring_workspace.assets.assets) - 1),
			)}
		if button(
			g,
			{750, 120, 180, 38},
		) {report := project_asset_package_size_report(&authoring_workspace.assets)
			authoring_workspace.feedback = fmt.tprintf(
				"EMBED %d/%d B · EXTERNAL %d/%d B · BLOCKED %d/%d B",
				report.embedded_count,
				report.embedded_bytes,
				report.external_count,
				report.external_bytes,
				report.prohibited_count,
				report.prohibited_bytes,
			)}
		if len(authoring_workspace.assets.assets) >
		   0 {count := len(authoring_workspace.assets.assets)
			authoring_workspace.selected_asset = clamp(
				authoring_workspace.selected_asset,
				0,
				count - 1,
			)
			if button(
				g,
				{940, 120, 90, 38},
			) {authoring_workspace.selected_asset = (authoring_workspace.selected_asset + count - 1) % count
				authoring_asset_load_selected()}
			if button(
				g,
				{1040, 120, 90, 38},
			) {authoring_workspace.selected_asset = (authoring_workspace.selected_asset + 1) % count
				authoring_asset_load_selected()}}
		if button(g, {30, 170, 170, 34}) do authoring_workspace.asset_kind = (authoring_workspace.asset_kind + 1) % len(Project_Asset_Kind)
		if button(g, {210, 170, 170, 34}) do authoring_workspace.asset_mode = (authoring_workspace.asset_mode + 1) % 2
		if button(g, {390, 170, 170, 34}) do authoring_workspace.asset_policy = (authoring_workspace.asset_policy + 1) % 3
		if button(g, {570, 170, 180, 34}) do authoring_workspace.asset_redistribution = !authoring_workspace.asset_redistribution
		if button(g, {30, 216, 170, 32}) do authoring_asset_begin_form(.Asset_Source_URI, authoring_workspace.asset_source_uri)
		if button(g, {210, 216, 170, 32}) do authoring_asset_begin_form(.Asset_Source_Name, authoring_workspace.asset_source_name)
		if button(g, {390, 216, 170, 32}) do authoring_asset_begin_form(.Asset_Creator, authoring_workspace.asset_creator)
		if button(g, {570, 216, 170, 32}) do authoring_asset_begin_form(.Asset_Attribution, authoring_workspace.asset_attribution)
		if button(g, {750, 216, 170, 32}) do authoring_asset_begin_form(.Asset_License_ID, authoring_workspace.asset_license_id)
		if button(g, {930, 216, 200, 32}) do authoring_asset_begin_form(.Asset_License_Text, authoring_workspace.asset_license_text)
		if button(g, {30, 258, 220, 32}) do authoring_asset_begin_form(.Asset_Usage)
		if button(g, {260, 258, 260, 32}) do authoring_workspace.feedback = authoring_asset_apply_selected_metadata()
		if button(g, {530, 258, 220, 32}) do authoring_workspace.feedback = authoring_asset_map_selected_by_kind()
		if button(g, {760, 258, 210, 32}) do authoring_workspace.feedback = authoring_asset_open_first_usage(g)
		if button(g, {980, 258, 150, 32}) do authoring_workspace.feedback = authoring_asset_audition_selected(g)
		if button(g, {30, 510, 160, 32}) do authoring_workspace.feedback = authoring_asset_history_restore(true) ? "ASSET UNDO" : "NOTHING TO UNDO"
		if button(g, {200, 510, 160, 32}) do authoring_workspace.feedback = authoring_asset_history_restore(false) ? "ASSET REDO" : "NOTHING TO REDO"
		if button(g, {370, 510, 210, 32}) do authoring_workspace.feedback = authoring_asset_confirm_pending()
		if button(
			g,
			{590, 510, 180, 32},
		) {authoring_asset_cancel_pending(); authoring_workspace.feedback = "PENDING ASSET CHANGE CANCELLED"}
	case .Packages:
		if button(g, {30, 120, 200, 38}) do authoring_workspace_export_wizard_begin(false)
		if button(g, {240, 120, 200, 38}) do authoring_workspace_export_wizard_begin(true)
		if button(g, {450, 120, 200, 38}) do authoring_workspace.feedback = authoring_workspace_inspect_package(.Story, "Inspect or Import Story Package")
		if button(g, {660, 120, 200, 38}) do authoring_workspace.feedback = authoring_workspace_inspect_package(.Campaign, "Inspect or Import Campaign Package")
		if button(g, {870, 120, 200, 38}) do authoring_workspace.feedback = authoring_workspace_inspect_package(.Expansion, "Inspect Expansion Pack")
		if button(g, {30, 166, 200, 34}) do authoring_workspace.feedback = authoring_workspace_install()
		if button(g, {240, 166, 200, 34}) do authoring_workspace.feedback = authoring_workspace_export_wizard_advance()
	case .Library:
		if button(
			g,
			{30, 120, 200, 38},
		) {authoring_workspace.import_decision = (authoring_workspace.import_decision + 1) % 4
			authoring_workspace.feedback = fmt.tprintf(
				"DECISION %v",
				Authoring_Import_Decision(authoring_workspace.import_decision),
			)}
		if button(g, {240, 120, 200, 38}) do authoring_workspace.feedback = authoring_workspace_install()
		if button(
			g,
			{450, 120, 190, 38},
		) {authoring_workspace.library_root = authoring_native_select_directory("Choose Installed Story Library")
			if authoring_workspace.library_root != "" do authoring_workspace.feedback = authoring_workspace_refresh_library()}
		if button(g, {650, 120, 130, 38}) do authoring_workspace.feedback = authoring_workspace_refresh_library()
		if button(g, {790, 120, 100, 38}) && len(authoring_workspace.library.installed) > 0 do authoring_workspace.selected_library = (authoring_workspace.selected_library + len(authoring_workspace.library.installed) - 1) % len(authoring_workspace.library.installed)
		if button(g, {900, 120, 100, 38}) && len(authoring_workspace.library.installed) > 0 do authoring_workspace.selected_library = (authoring_workspace.selected_library + 1) % len(authoring_workspace.library.installed)
		if button(g, {1010, 120, 130, 38}) do authoring_workspace.feedback = authoring_workspace_discover_update()
		if button(g, {30, 172, 200, 34}) do authoring_workspace.feedback = authoring_workspace_uninstall_selected()
		if button(g, {240, 172, 200, 34}) do authoring_workspace.feedback = authoring_workspace_reveal_selected()
		if button(
			g,
			{450, 172, 230, 34},
		) {authoring_workspace.import_decision = int(Authoring_Import_Decision.Editable_Copy)
			authoring_workspace.editable_root = ""
			authoring_workspace.feedback = "EDITABLE COPY MODE SELECTED"}
		if button(g, {690, 172, 220, 34}) do authoring_workspace.feedback = authoring_workspace_launch_selected()
	}
}
