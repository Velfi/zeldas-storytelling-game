package main

import "core:fmt"
import "core:strings"

vk_draw_authoring_workspace :: proc(r: ^Vulkan_Backend, g: ^Game) {
	vulkan_ui_rect(
		r,
		0,
		0,
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		{7, 10, 15, 255},
	); vk_text(r, 24, 14, "STORY AUTHORING", UI_ACCENT, 1.18); vk_text(r, 240, 23, "BUILD  ·  WRITE  ·  VALIDATE  ·  SHARE", UI_MUTED, .58)
	tab_labels := [7]string {
		"PROJECT",
		"STORY DATA",
		"MYSTERY",
		"DIAGNOSTICS",
		"ASSETS",
		"PACKAGES",
		"LIBRARY",
	}; vk_tab_bar(r, {18, 56, 1144, 48}); for label, i in tab_labels do vk_tab(r, {18 + f32(i) * 166, 60, 156, 40}, label, authoring_workspace.tab == Authoring_Workspace_Tab(i))
	#partial switch authoring_workspace.tab {
	case .Project:
		vk_panel(r, 22, 108, 670, 218); vk_panel(r, 704, 108, 474, 218)
		vk_text(r, 30, 116, "PROJECT FILES", UI_ACCENT, .66)
		vk_text(r, 716, 116, "ACTIVE CASE", UI_ACCENT, .66)
		labels := [11]string {
			"NEW STORY",
			"NEW MYSTERY",
			"OPEN PROJECT",
			"SAVE ALL",
			"SAVE AS",
			"DUPLICATE CASE",
			authoring_workspace.confirm_delete ? "CONFIRM DELETE" : "DELETE CASE",
			"KEEP RECOVERY",
			"CREATE EDITABLE COPY",
			"APPLY RECOVERY",
			authoring_workspace.playtest.active ? "END PLAYTEST" : "WHOLE PROJECT PLAYTEST",
		}
		positions := [11]Rect {
			{30, 140, 210, 40},
			{250, 140, 210, 40},
			{470, 140, 210, 40},
			{30, 194, 210, 40},
			{250, 194, 210, 40},
			{470, 194, 210, 40},
			{690, 184, 210, 40},
			{30, 248, 210, 40},
			{250, 248, 300, 40},
			{30, 302, 210, 40},
			{250, 302, 210, 40},
		}
		for label, i in labels do if i != 8 || active_authoring_read_only {if i == 3 || i == 10 do vk_primary_button(r, positions[i], label)
			else if i == 6 do vk_danger_button(r, positions[i], label)
			else do vk_button(r, positions[i], label)}
		vk_button(r, {570, 238, 120, 40}, "PREV CASE")
		vk_button(r, {700, 238, 120, 40}, "NEXT CASE")
		vk_button(r, {830, 238, 120, 40}, "RENAME CASE")
		vk_button(r, {960, 238, 120, 40}, "MOVE CASE")
		vk_button(r, {470, 292, 210, 40}, "RECOVER MOVED PROJECT")
		vk_button(r, {690, 292, 90, 40}, "RECENT <")
		vk_button(r, {790, 292, 90, 40}, "RECENT >")
		vk_button(r, {890, 292, 190, 40}, "OPEN RECENT")
		if item := authoring_workspace_case(); item != nil do vk_text(r, 700, 340, fmt.tprintf("CASE %d OF %d  ·  %s  ·  %s", active_authoring_project.active_case + 1, active_authoring_project.case_count, item.id, item.directory), UI_INFO, .58)
		if authoring_workspace.recents.count >
		   0 {recent := authoring_workspace.recents.items[clamp(authoring_workspace.selected_recent, 0, authoring_workspace.recents.count - 1)]
			vk_text(
				r,
				700,
				366,
				fmt.tprintf("RECENT  ·  %s  ·  %s", recent.title, recent.root_path),
				UI_MUTED,
				.54,
			)}
		field, value := authoring_project_metadata_field()
		vk_button(r, {30, 350, 80, 32}, "FIELD <")
		vk_button(r, {120, 350, 80, 32}, "FIELD >")
		vk_button(r, {210, 350, 240, 32}, fmt.tprintf("EDIT %s", strings.to_upper(field)))
		vk_text(r, 470, 358, value, UI_INFO, .50)
		vk_button(
			r,
			{30, 398, 220, 32},
			authoring_project_requirement_kind == 0 ? "EXPANSION REQUIREMENTS" : "CAPABILITY REQUIREMENTS",
		)
		vk_button(r, {260, 398, 80, 32}, "PREV")
		vk_button(r, {350, 398, 80, 32}, "NEXT")
		vk_text(r, 450, 406, authoring_project_requirement_label(), UI_INFO, .48)
		vk_button(r, {30, 442, 90, 32}, "ADD")
		vk_button(r, {130, 442, 90, 32}, "UPDATE")
		vk_button(r, {230, 442, 90, 32}, "REMOVE")
		vk_button(r, {330, 442, 70, 32}, "UP")
		vk_button(r, {410, 442, 70, 32}, "DOWN")
		if authoring_project_requirement_kind ==
		   0 {vk_button(r, {30, 486, 120, 30}, "OPTIONAL"); vk_button(r, {160, 486, 120, 30}, "DISTRIBUTION"); vk_button(r, {290, 486, 120, 30}, "FALLBACK")}
	case .Story_Data:
		vk_text(r, 30, 108, "RECORD TYPES", UI_ACCENT, .72)
		story_labels := [15]string {
			"ENTITY",
			"ROLE",
			"VARIABLE",
			"FACT",
			"PROPOSITION",
			"KNOWLEDGE",
			"RELATIONSHIP",
			"EVENT",
			"OBJECTIVE",
			"ENDING",
			"STORYLET GROUP",
			"STORYLET",
			"INVARIANT",
			"CONDITION",
			"EFFECT",
		}
		for label, i in story_labels do vk_button(r, {30 + f32(i % 4) * 280, 120 + f32(i / 4) * 42, 266, 34}, label, authoring_workspace.selected_category == i)
		vk_text(r, 30, 312, "SELECTED RECORD", UI_ACCENT, .64)
		vk_primary_button(r, {30, 330, 100, 38}, "ADD")
		vk_button(r, {140, 330, 100, 38}, "DUPLICATE")
		vk_button(r, {250, 330, 100, 38}, "RENAME")
		vk_danger_button(r, {360, 330, 100, 38}, "REMOVE")
		vk_button(r, {470, 330, 70, 38}, "UP")
		vk_button(r, {550, 330, 70, 38}, "DOWN")
		vk_button(r, {630, 330, 100, 38}, "UNDO")
		vk_button(r, {740, 330, 100, 38}, "REDO")
		vk_button(
			r,
			{850, 330, 150, 38},
			authoring_creator_truth_revealed ? "HIDE CREATOR TRUTH" : "REVEAL CREATOR TRUTH",
		)
		vk_button(r, {1010, 330, 150, 38}, "OPEN USED BY")
		kind := Story_Authoring_Record_Kind(
			clamp(
				authoring_workspace.selected_category,
				0,
				int(Story_Authoring_Record_Kind.Effect),
			),
		)
		count := authoring_story_count(kind)
		vk_button(r, {30, 376, 180, 34}, "PREVIOUS RECORD")
		vk_button(r, {220, 376, 180, 34}, "NEXT RECORD")
		vk_text(
			r,
			420,
			385,
			fmt.tprintf(
				"%d / %d · %s",
				count == 0 ? 0 : authoring_workspace.selected_record + 1,
				count,
				authoring_story_id(kind, authoring_workspace.selected_record),
			),
			UI_INFO,
			.54,
		)
		field, _ := authoring_story_scalar_field(kind, authoring_story_field_cursor)
		vk_button(r, {30, 422, 70, 32}, "FIELD <")
		vk_button(r, {110, 422, 70, 32}, "FIELD >")
		vk_button(r, {190, 422, 180, 32}, fmt.tprintf("EDIT %s", strings.to_upper(field)))
		list, list_count := authoring_story_list_field(kind, authoring_story_list_cursor)
		if list_count >
		   0 {items := authoring_story_list_count(kind, authoring_workspace.selected_record, list); vk_button(r, {30, 464, 70, 32}, "LIST <"); vk_button(r, {110, 464, 70, 32}, "LIST >"); vk_button(r, {190, 464, 70, 32}, "ITEM <"); vk_button(r, {270, 464, 70, 32}, "ITEM >"); vk_button(r, {350, 464, 90, 32}, "ADD ITEM"); vk_button(r, {450, 464, 90, 32}, "REMOVE"); vk_button(r, {550, 464, 60, 32}, "UP"); vk_button(r, {620, 464, 60, 32}, "DOWN"); vk_button(r, {690, 464, 190, 32}, fmt.tprintf("NEW %v", Story_Authoring_Record_Kind(authoring_story_picker_kind))); vk_button(r, {890, 464, 170, 32}, "CREATE + PICK"); vk_text(r, 30, 505, fmt.tprintf("%s · ITEM %d / %d", strings.to_upper(list), items == 0 ? 0 : authoring_story_list_item + 1, items), UI_INFO, .52)} else do vk_text(r, 30, 474, "THIS RECORD HAS NO LIST FIELDS", UI_MUTED, .52)
	case .Mystery:
		categories := [18]string {
			"SETUP",
			"CHARACTERS",
			"LOCATIONS",
			"POINTS OF INTEREST",
			"EVENTS",
			"CLUES",
			"CLAIMS",
			"CONTRADICTIONS",
			"DEDUCTIONS",
			"QUESTIONS",
			"DEMONSTRATIONS",
			"DIALOGUE",
			"ENDINGS",
			"CITY LOCATIONS",
			"TUTORIALS",
			"SOLUTION",
			"EVIDENCE ROUTES",
			"SUPPORT MAP",
		}
		group_labels := [6]string {
			"WORLD & CAST",
			"EVIDENCE",
			"REASONING",
			"PLAYER EXPERIENCE",
			"RESOLUTION",
			"RELATIONSHIPS",
		}
		for group, row in group_labels do vk_text(r, 30 + f32(row % 3) * 370, 108 + f32(row / 3) * 264, group, UI_MUTED, .42)
		for label, i in categories do vk_button(r, {30 + f32(i % 3) * 370, 120 + f32(i / 3) * 44, 350, 36}, label, authoring_workspace.selected_category == i)
		vk_primary_button(r, {30, 410, 220, 38}, "VALIDATE MYSTERY")
		vk_button(r, {260, 410, 100, 38}, "BUDGET -")
		vk_button(r, {370, 410, 100, 38}, "BUDGET +")
		vk_button(r, {480, 410, 260, 38}, "NEXT CULPRIT")
		payload := mystery_payload(&active_story_project)
		if payload != nil do vk_text(r, 760, 420, fmt.tprintf("ACTION BUDGET %d  ·  %d CLUES  ·  %d QUESTIONS", payload.action_budget, len(payload.clues), len(payload.questions)), UI_INFO, .58)
		if authoring_workspace.selected_category >=
		   16 {edges := authoring_mystery_panel_edge_count(authoring_workspace.selected_category)
			pages := max(1, (edges + 4) / 5)
			page := clamp(authoring_workspace.selected_record, 0, pages - 1)
			vk_text(
				r,
				30,
				452,
				authoring_workspace.selected_category == 16 ? "EVIDENCE ROUTES · CLICK EITHER END TO OPEN THE RECORD" : "DIRECT SUPPORT MAP · CLICK EITHER END TO OPEN THE RECORD",
				UI_ACCENT,
				.54,
			)
			shown := 0
			for visible_row in 0 ..< 5 {row := page * 5 + visible_row
				source, source_kind, source_index, target, target_kind, _, ok :=
					authoring_mystery_panel_edge(authoring_workspace.selected_category, row)
				if !ok do break
				y := 474 + f32(visible_row) * 36
				vk_button(
					r,
					{30, y, 500, 30},
					fmt.tprintf(
						"%v · %s%s",
						source_kind,
						source,
						source_index < 0 ? " · BROKEN" : "",
					),
				)
				vk_text(r, 542, y + 8, "→", source_index < 0 ? UI_DANGER : UI_ACCENT, .54)
				vk_button(r, {580, y, 500, 30}, fmt.tprintf("%v · %s", target_kind, target))
				shown += 1}
			if shown == 0 do vk_text(r, 30, 486, "NO AUTHORED SUPPORT RELATIONSHIPS", UI_MUTED, .58)
			vk_text(
				r,
				680,
				648,
				fmt.tprintf("%d EDGES · PAGE %d / %d", edges, page + 1, pages),
				UI_INFO,
				.54,
			)
			vk_button(r, {820, 642, 120, 24}, "PREVIOUS PAGE")
			vk_button(
				r,
				{950, 642, 120, 24},
				"NEXT PAGE",
			)} else {kind := Mystery_Authoring_Record_Kind(authoring_workspace.selected_category)
			count := authoring_mystery_count(kind)
			vk_button(r, {30, 462, 100, 34}, "PREVIOUS")
			vk_button(r, {140, 462, 100, 34}, "NEXT")
			vk_primary_button(r, {250, 462, 100, 34}, "ADD")
			vk_button(r, {360, 462, 100, 34}, "RENAME")
			vk_danger_button(r, {470, 462, 100, 34}, "REMOVE")
			vk_button(r, {580, 462, 70, 34}, "UP")
			vk_button(r, {660, 462, 70, 34}, "DOWN")
			vk_text(
				r,
				740,
				471,
				fmt.tprintf(
					"RECORD %d OF %d  ·  %s",
					count == 0 ? 0 : authoring_workspace.selected_record + 1,
					count,
					authoring_mystery_id(kind, authoring_workspace.selected_record),
				),
				UI_INFO,
				.58,
			)}
		mystery_kind := Mystery_Authoring_Record_Kind(
			clamp(
				authoring_workspace.selected_category,
				0,
				int(Mystery_Authoring_Record_Kind.Solution),
			),
		)
		field, field_type, _ := authoring_mystery_scalar_field(
			mystery_kind,
			authoring_mystery_field_cursor,
		)
		vk_button(r, {30, 508, 70, 32}, "FIELD <")
		vk_button(r, {110, 508, 70, 32}, "FIELD >")
		vk_button(
			r,
			{190, 508, 220, 32},
			fmt.tprintf("%s %s", field_type == 'b' ? "TOGGLE" : "EDIT", strings.to_upper(field)),
		)
		if mystery_kind == .Demonstration do vk_button(r, {930, 508, 230, 32}, "PREVIEW INTERACTION")
		list, list_count := authoring_mystery_list_field(
			mystery_kind,
			authoring_mystery_list_cursor,
		)
		if list_count >
		   0 {items := authoring_mystery_selected_list_count(list); vk_button(r, {30, 548, 70, 32}, "LIST <")
			vk_button(r, {110, 548, 70, 32}, "LIST >")
			vk_button(r, {190, 548, 70, 32}, "ITEM <")
			vk_button(r, {270, 548, 70, 32}, "ITEM >")
			vk_button(r, {350, 548, 90, 32}, "ADD ITEM")
			vk_button(r, {450, 548, 90, 32}, "REMOVE")
			vk_button(r, {550, 548, 60, 32}, "UP")
			vk_button(r, {620, 548, 60, 32}, "DOWN")
			vk_button(r, {1050, 548, 120, 32}, "CREATE + PICK")
			vk_text(
				r,
				30,
				590,
				fmt.tprintf(
					"%s · ITEM %d / %d",
					strings.to_upper(list),
					items == 0 ? 0 : authoring_mystery_list_item + 1,
					items,
				),
				UI_INFO,
				.50,
			)}
		if mystery_kind ==
		   .Demonstration {vk_button(r, {700, 548, 150, 32}, "ADD ROUTE"); vk_button(r, {860, 548, 100, 32}, "DEL ROUTE"); vk_button(r, {970, 548, 70, 32}, "ROUTE UP")}
	case .Diagnostics:
		authoring_workspace_diagnostic_filter_ensure()
		vk_text(r, 30, 108, "VALIDATION RESULTS", UI_ACCENT, .68)
		vk_text(r, 750, 180, "ISOLATED PLAYTEST", UI_ACCENT, .68)
		vk_text(r, 750, 222, "CREATOR STARTING STATE", UI_ACCENT, .58)
		vk_text(r, 750, 306, "SCENARIO RECORDER", UI_ACCENT, .58)
		vk_primary_button(r, {30, 120, 140, 34}, "RECHECK ALL")
		vk_button(
			r,
			{180, 120, 150, 34},
			fmt.tprintf(
				"PROFILE %v",
				Authoring_Validation_Profile(clamp(authoring_workspace.selected_category, 0, 3)),
			),
		)
		vk_button(
			r,
			{340, 120, 150, 34},
			fmt.tprintf("SEVERITY ≥ %v", authoring_workspace.diagnostic_filter.minimum_severity),
		)
		domain := Authoring_Validation_Domain(
			authoring_workspace.diagnostic_domain % len(Authoring_Validation_Domain),
		)
		vk_button(r, {500, 120, 150, 34}, fmt.tprintf("GROUP %v", domain))
		vk_button(
			r,
			{660, 120, 150, 34},
			authoring_workspace.diagnostic_filter.domain_enabled[domain] ? "GROUP VISIBLE" : "GROUP HIDDEN",
		)
		vk_button(r, {820, 120, 180, 34}, "SEARCH DIAGNOSTICS")
		vk_danger_button(r, {1010, 120, 160, 34}, "INVALIDATE GROUP")
		indices := authoring_workspace_diagnostic_indices()
		defer delete(indices)
		stale := authoring_workspace_diagnostic_stale_count()
		vk_text(
			r,
			30,
			166,
			fmt.tprintf(
				"%d / %d MATCHING · %d STALE DOMAINS · SEARCH %s",
				len(indices),
				len(authoring_workspace.production_validation.diagnostics),
				stale,
				authoring_workspace.diagnostic_filter.search,
			),
			stale > 0 ? UI_WARNING : (authoring_validation_is_blocked(&authoring_workspace.production_validation) ? UI_DANGER : UI_SUCCESS),
			.50,
		)
		start := authoring_workspace.diagnostic_page * 6
		for row in 0 ..< min(
			6,
			len(indices) - start,
		) {item := authoring_workspace.production_validation.diagnostics[indices[start + row]]
			vk_button(
				r,
				{30, 198 + f32(row) * 40, 690, 34},
				fmt.tprintf(
					"%v · %v · %s · %s · %s",
					item.domain,
					item.severity,
					item.entity_id,
					item.field_path,
					item.message,
				),
			)}
		pages := max(1, (len(indices) + 5) / 6)
		vk_button(r, {30, 448, 120, 30}, "PREVIOUS")
		vk_button(r, {160, 448, 120, 30}, "NEXT")
		vk_text(
			r,
			300,
			456,
			fmt.tprintf(
				"PAGE %d / %d · GROUPED BY DOMAIN / DOCUMENT",
				authoring_workspace.diagnostic_page + 1,
				pages,
			),
			UI_MUTED,
			.46,
		)
		mode := Authoring_Playtest_Start_Mode(
			authoring_workspace.playtest_start_mode % len(Authoring_Playtest_Start_Mode),
		)
		vk_button(r, {750, 198, 200, 32}, fmt.tprintf("START FROM %v", mode))
		vk_button(
			r,
			{960, 198, 200, 32},
			authoring_workspace.playtest.active ? "END + RESTORE PLAYTEST" : "START ISOLATED PLAYTEST",
		)
		categories := [7]string {
			"VARIABLES",
			"KNOWLEDGE / CLUES / CLAIMS / TOPICS",
			"OBJECTIVES",
			"EVENTS",
			"MYSTERY PROGRESS",
			"CAMPAIGN STATE",
			"TIME / BUDGET",
		}
		category := authoring_workspace.creator_category % len(categories)
		vk_button(r, {750, 240, 200, 32}, categories[category])
		vk_button(r, {960, 240, 95, 32}, "NEXT ITEM")
		vk_button(r, {1065, 240, 95, 32}, "ADD STATE")
		vk_button(r, {750, 282, 200, 32}, "RESET CREATOR STATE")
		vk_button(r, {960, 282, 95, 32}, "BUDGET -")
		vk_button(r, {1065, 282, 95, 32}, "BUDGET +")
		setup := &authoring_workspace.creator_setup
		vk_text(
			r,
			750,
			316,
			fmt.tprintf(
				"%d VAR · %d KNOW · %d OBJ · %d EVENTS · %d MYSTERY · %d CAMPAIGN · AP %d · TIME %d",
				len(setup.variables),
				len(setup.knowledge),
				len(setup.objectives),
				len(setup.events),
				len(setup.mystery_progress),
				len(setup.campaign_values) + len(setup.started_cases) + len(setup.completed_cases),
				setup.action_budget,
				setup.time_minutes,
			),
			UI_INFO,
			.38,
		)
		vk_button(
			r,
			{750, 324, 200, 32},
			authoring_workspace.scenario_recording ? "STOP RECORDING" : "BEGIN RECORDING",
		)
		vk_button(r, {960, 324, 95, 32}, "REC START")
		vk_button(r, {1065, 324, 95, 32}, "REC ADVANCE")
		vk_button(r, {750, 366, 125, 32}, "REC REVEAL")
		vk_button(r, {885, 366, 125, 32}, "REPLAY")
		vk_button(r, {1020, 366, 140, 32}, "EXPORT FAILURE")
		vk_button(r, {750, 408, 95, 30}, "REC CHOICE")
		vk_button(r, {855, 408, 95, 30}, "REC CHECK")
		vk_button(r, {960, 408, 95, 30}, "REC KNOW")
		vk_button(r, {1065, 408, 95, 30}, "REC QUESTION")
		vk_text(
			r,
			750,
			452,
			fmt.tprintf(
				"%d ACTIONS · %s",
				len(authoring_workspace.scenario_record.actions),
				authoring_workspace.scenario_last.ok ? "LAST REPLAY PASSED" : authoring_workspace.scenario_last.failure.failed ? "LAST REPLAY FAILED" : "NOT REPLAYED",
			),
			authoring_workspace.scenario_last.failure.failed ? UI_DANGER : UI_MUTED,
			.46,
		)
	case .Assets:
		vk_text(r, 30, 108, "ASSET LIBRARY", UI_ACCENT, .66)
		actions := [5]string{"IMPORT", "REPAIR", "REPLACE", "REMOVE", "SIZE REPORT"}
		for label, i in actions {box := Rect{30 + f32(i) * 180, 120, i == 4 ? 180 : 170, 38}
			if i == 0 do vk_primary_button(r, box, label)
			else if i == 3 do vk_danger_button(r, box, label)
			else do vk_button(r, box, label)}
		vk_button(r, {940, 120, 90, 38}, "PREVIOUS")
		vk_button(r, {1040, 120, 90, 38}, "NEXT")
		vk_button(
			r,
			{30, 170, 170, 34},
			fmt.tprintf("KIND %v", Project_Asset_Kind(authoring_workspace.asset_kind)),
		)
		vk_button(
			r,
			{210, 170, 170, 34},
			fmt.tprintf("MODE %v", Project_Asset_Source_Mode(authoring_workspace.asset_mode)),
		)
		vk_button(
			r,
			{390, 170, 170, 34},
			fmt.tprintf("POLICY %v", Project_Asset_Embed_Policy(authoring_workspace.asset_policy)),
		)
		vk_button(
			r,
			{570, 170, 180, 34},
			authoring_workspace.asset_redistribution ? "REDISTRIBUTION YES" : "REDISTRIBUTION NO",
		)
		forms := [6]string {
			"SOURCE URI",
			"SOURCE NAME",
			"CREATOR",
			"ATTRIBUTION",
			"LICENSE ID",
			"LICENSE TEXT",
		}
		for label, i in forms do vk_button(r, {30 + f32(i) * 180, 216, i == 5 ? 200 : 170, 32}, label)
		vk_text(r, 30, 250, "USAGE & REVIEW", UI_MUTED, .48)
		vk_button(r, {30, 258, 220, 32}, "REGISTER USAGE")
		vk_primary_button(r, {260, 258, 260, 32}, "APPLY METADATA / POLICY")
		vk_button(r, {530, 258, 220, 32}, "MAP BY ASSET KIND")
		vk_button(r, {760, 258, 210, 32}, "OPEN FIRST USAGE")
		vk_button(r, {980, 258, 150, 32}, "AUDITION AUDIO")
		if len(authoring_workspace.assets.assets) >
		   0 {i := clamp(authoring_workspace.selected_asset, 0, len(authoring_workspace.assets.assets) - 1)
			asset := authoring_workspace.assets.assets[i]
			preview := project_asset_change_preview(&authoring_workspace.assets, asset.id)
			defer project_asset_change_preview_destroy(&preview)
			vk_text(
				r,
				30,
				310,
				fmt.tprintf(
					"%d / %d · %s · %v · %s",
					i + 1,
					len(authoring_workspace.assets.assets),
					asset.id,
					asset.kind,
					asset.technical.format,
				),
				UI_ACCENT,
				.64,
			)
			vk_text(
				r,
				30,
				344,
				fmt.tprintf("%d BYTES · SHA256 %s", asset.technical.byte_size, asset.sha256),
				UI_INFO,
				.48,
			)
			vk_text(
				r,
				30,
				376,
				fmt.tprintf(
					"IMAGE %d×%d %s · ALPHA %s · AUDIO %d CH %d HZ %.2f S",
					asset.technical.image.width,
					asset.technical.image.height,
					asset.technical.image.color_space,
					asset.technical.image.has_alpha ? "YES" : "NO",
					asset.technical.audio.channels,
					asset.technical.audio.sample_rate,
					asset.technical.audio.duration_seconds,
				),
				UI_MUTED,
				.50,
			)
			vk_text(
				r,
				30,
				408,
				fmt.tprintf(
					"MODEL %.2f M/UNIT · %s UP · %s FORWARD · %d MESHES / %d MATERIALS · %d CLIPS %.2f S",
					asset.technical.model.meters_per_unit,
					asset.technical.model.up_axis,
					asset.technical.model.forward_axis,
					asset.technical.model.mesh_count,
					asset.technical.model.material_count,
					asset.technical.animation.clip_count,
					asset.technical.animation.duration_seconds,
				),
				UI_MUTED,
				.45,
			)
			vk_text(
				r,
				30,
				440,
				fmt.tprintf(
					"SOURCE %s · %s · %s",
					asset.provenance.creator,
					asset.provenance.license_id,
					asset.provenance.source_uri,
				),
				UI_INFO,
				.50,
			)
			vk_text(
				r,
				30,
				472,
				fmt.tprintf(
					"%d USAGES · %d DEPENDENTS · %v · %d EXTERNAL CATALOG REFS",
					len(preview.usages),
					len(preview.dependents),
					asset.embed_policy,
					len(authoring_workspace.assets.external_catalog_usages),
				),
				len(preview.usages) > 0 ? UI_WARNING : UI_SUCCESS,
				.50,
			)
			preview_box := Rect{790, 304, 360, 194}
			vulkan_ui_rect(
				r,
				preview_box.x,
				preview_box.y,
				preview_box.w,
				preview_box.h,
				{10, 14, 18, 255},
			)
			vulkan_ui_outline(
				r,
				preview_box.x,
				preview_box.y,
				preview_box.w,
				preview_box.h,
				UI_BORDER_STRONG,
				2,
			)
			texture := vulkan_asset_preview_texture(r, &authoring_workspace.assets, i)
			if texture >=
			   0 {vulkan_ui_quad(r, preview_box.x + 6, preview_box.y + 6, preview_box.w - 12, preview_box.h - 12, {255, 255, 255, 255}, texture, {}, {1, 1}, true)} else if asset.kind == .Model || asset.kind == .Animation {if !vk_authoring_model_preview(r, asset, {preview_box.x + 6, preview_box.y + 6, preview_box.w - 12, preview_box.h - 12}) do vk_text(r, preview_box.x + 20, preview_box.y + 82, "MODEL PREVIEW UNAVAILABLE", UI_WARNING, .48)} else if asset.kind == .Audio {vk_text(r, preview_box.x + 72, preview_box.y + 72, "AUDIO WAVEFORM", UI_ACCENT, .52)
				bars := min(48, max(8, int(asset.technical.audio.duration_seconds * 12)))
				for bar in 0 ..< bars {height := f32(18 + (bar * 17 % 52)); vulkan_ui_rect(r, preview_box.x + 18 + f32(bar) * 6, preview_box.y + 118 - height * .5, 3, height, {102, 205, 235, 210})}
				vk_text(
					r,
					preview_box.x + 82,
					preview_box.y + 156,
					"AUDITION AUDIO ABOVE",
					UI_INFO,
					.42,
				)} else {vk_text(r, preview_box.x + 76, preview_box.y + 82, "TECHNICAL PREVIEW", UI_MUTED, .48)}} else do vk_text(r, 30, 320, "NO PROJECT ASSETS · COMPLETE PROVENANCE THEN IMPORT", UI_MUTED, .58)
		vk_button(
			r,
			{30, 510, 160, 32},
			fmt.tprintf("UNDO (%d)", len(authoring_workspace.asset_history.undo)),
		)
		vk_button(
			r,
			{200, 510, 160, 32},
			fmt.tprintf("REDO (%d)", len(authoring_workspace.asset_history.redo)),
		)
		vk_button(r, {370, 510, 210, 32}, "CONFIRM REVIEWED CHANGE")
		vk_button(r, {590, 510, 180, 32}, "CANCEL REVIEW")
		if authoring_workspace.pending_asset_action != .None do vk_text(r, 790, 519, fmt.tprintf("PENDING %v · VERIFY HASH / REFERENCES, THEN CONFIRM", authoring_workspace.pending_asset_action), UI_WARNING, .42)
	case .Packages:
		vk_text(r, 30, 108, "1  EXPORT A VALIDATED DRAFT", UI_ACCENT, .58)
		vk_primary_button(r, {30, 120, 200, 38}, "EXPORT STORY")
		vk_primary_button(r, {240, 120, 200, 38}, "EXPORT CAMPAIGN")
		vk_text(r, 450, 108, "2  INSPECT A PORTABLE PACKAGE", UI_ACCENT, .58)
		vk_button(r, {450, 120, 200, 38}, "INSPECT STORY")
		vk_button(r, {660, 120, 200, 38}, "INSPECT CAMPAIGN")
		vk_button(r, {870, 120, 200, 38}, "INSPECT EXPANSION")
		wizard := &authoring_workspace.export_wizard
		if wizard.title !=
		   "" {vk_button(r, {30, 166, 200, 34}, "INSTALL INSPECTED"); vk_button(r, {240, 166, 200, 34}, fmt.tprintf("CONTINUE · %v", wizard.stage))
			vk_text(
				r,
				460,
				174,
				fmt.tprintf(
					"%s@%s · THUMB %s · %d DEPENDENCIES · %s",
					wizard.title,
					wizard.version,
					wizard.thumbnail == "" ? "MISSING" : wizard.thumbnail,
					wizard.dependency_count,
					wizard.message,
				),
				wizard.stage == .Result ? UI_SUCCESS : UI_INFO,
				.36,
			)
			if wizard.stage ==
			   .Dependencies {row := 0; if authoring_workspace.export_campaign {for item in campaign_document.cases {if row >= 3 do break; vk_text(r, 460, 198 + f32(row) * 24, fmt.tprintf("CASE · %s@%s · EMBEDDED", item.id, item.case_content_version), UI_INFO, .38)
						row += 1}} else {for item in active_story_project.expansion_requirements {if row >= 3 do break; vk_text(r, 460, 198 + f32(row) * 24, fmt.tprintf("EXPANSION · %s@%s · %v", item.id, item.version, item.distribution), UI_INFO, .38)
						row += 1}}}
			if wizard.stage == .Exporting do vk_text(r, 460, 270, "SYNCHRONOUS EXPORT RUNS ON CONTINUE · RESULT PROGRESS APPEARS WHEN THE VERIFIED SERVICE RETURNS", UI_WARNING, .36)} else do vk_text(r, 30, 166, fmt.tprintf("SAVED-SNAPSHOT GATE · %s@%s · %d ASSETS", active_story_project.title, active_story_project.content_version, len(authoring_workspace.assets.assets)), UI_INFO, .42)
		inspection := &authoring_workspace.inspection
		if inspection.artifact.identity.id !=
		   "" {vk_text(r, 30, 290, fmt.tprintf("%v · %s@%s · %s", inspection.artifact.identity.kind, inspection.artifact.identity.id, inspection.artifact.identity.content_version, inspection.title), UI_ACCENT, .60)
			vk_text(
				r,
				30,
				318,
				fmt.tprintf(
					"%v · %s · %d FILES · %d ASSETS · %d CASES",
					inspection.integrity,
					inspection.integrity_summary,
					len(inspection.files),
					inspection.asset_count,
					inspection.case_count,
				),
				inspection.integrity == .Valid ? UI_SUCCESS : UI_DANGER,
				.42,
			)
			row := 0
			for capability in inspection.capabilities {if row >= 3 do break; vk_text(r, 30, 348 + f32(row) * 22, fmt.tprintf("CAPABILITY · %s", capability), UI_INFO, .38)
				row += 1}
			row = 0
			for dependency in inspection.dependencies {if row >= 3 do break; vk_text(r, 390, 348 + f32(row) * 22, fmt.tprintf("DEPENDENCY · %s@%s · %s", dependency.id, dependency.version, dependency.optional ? "OPTIONAL" : "REQUIRED"), dependency.optional ? UI_MUTED : UI_INFO, .38)
				row += 1}
			for warning, i in inspection.typed_warnings {if i >= 3 do break; vk_text(r, 760, 348 + f32(i) * 22, fmt.tprintf("%s WARNING · %s", warning.audience == .Player_Safe ? "PLAYER-SAFE" : "CREATOR-ONLY", warning.message), UI_WARNING, .34)}} else {vk_text(r, 30, 290, "SELECT A PACKAGE TO INSPECT ITS MANIFEST, INTEGRITY, CAPABILITIES, DEPENDENCIES, ASSETS, CASES, AND WARNINGS", UI_MUTED, .48)}
		if authoring_workspace.last_artifact.identity.id != "" do vk_text(r, 30, 486, fmt.tprintf("LAST EXPORT · %s@%s · %s · %s %d/%d", authoring_workspace.last_artifact.identity.id, authoring_workspace.last_artifact.identity.content_version, authoring_workspace.last_artifact.package_path, authoring_workspace.package_progress.phase, authoring_workspace.package_progress.completed, authoring_workspace.package_progress.total), UI_SUCCESS, .48)
	case .Library:
		vk_text(r, 30, 108, "INSTALLED STORIES & CAMPAIGNS", UI_ACCENT, .64)
		vk_button(
			r,
			{30, 120, 200, 38},
			fmt.tprintf(
				"CONFLICT %v",
				Authoring_Import_Decision(authoring_workspace.import_decision),
			),
		)
		vk_primary_button(r, {240, 120, 200, 38}, "INSTALL PACKAGE")
		vk_button(r, {450, 120, 190, 38}, "CHOOSE ROOT")
		vk_button(r, {650, 120, 130, 38}, "REFRESH")
		vk_button(r, {790, 120, 100, 38}, "PREVIOUS")
		vk_button(r, {900, 120, 100, 38}, "NEXT")
		vk_button(r, {1010, 120, 130, 38}, "FIND UPDATE")
		vk_danger_button(r, {30, 172, 200, 34}, "UNINSTALL")
		vk_button(r, {240, 172, 200, 34}, "REVEAL IN FINDER")
		vk_button(r, {450, 172, 230, 34}, "CREATE EDITABLE COPY")
		vk_primary_button(r, {690, 172, 220, 34}, "LAUNCH SELECTED")
		vk_text(
			r,
			700,
			180,
			fmt.tprintf(
				"%d INSTALLED VERSIONS · ROOT %s",
				len(authoring_workspace.library.installed),
				authoring_workspace.library_root,
			),
			UI_MUTED,
			.54,
		)
		if len(authoring_workspace.library.installed) >
		   0 {i := clamp(authoring_workspace.selected_library, 0, len(authoring_workspace.library.installed) - 1); item := authoring_workspace.library.installed[i]; dependent_count := 0; for edge in authoring_workspace.library.dependency_edges do if edge.requirement.id == item.identity.id && edge.requirement.kind == item.identity.kind do dependent_count += 1; vk_text(r, 30, 238, fmt.tprintf("%d / %d · %v · %s@%s", i + 1, len(authoring_workspace.library.installed), item.identity.kind, item.identity.id, item.identity.content_version), UI_ACCENT, .72); vk_text(r, 30, 278, fmt.tprintf("INSTALL ROOT · %s", item.install_root), UI_INFO, .56); vk_text(r, 30, 314, fmt.tprintf("PACKAGE HASH · %s", item.package_hash), UI_MUTED, .52); vk_text(r, 30, 350, fmt.tprintf("%d REQUIRED-BY EDGES · %d PLAYER SAVES PRESERVED · %s", dependent_count, len(authoring_workspace.library.saves), item.active ? "ACTIVE" : "INACTIVE"), dependent_count > 0 ? UI_WARNING : UI_SUCCESS, .56); if inspection := &authoring_workspace.inspection; inspection.artifact.identity.id != "" {missing, unsupported, compatible := authoring_workspace_resolution_counts(); vk_text(r, 30, 402, fmt.tprintf("SELECTED IMPORT · %s@%s · %d MISSING DEPENDENCIES · %d UNSUPPORTED CAPABILITIES", inspection.artifact.identity.id, inspection.artifact.identity.content_version, missing, unsupported), compatible ? UI_SUCCESS : UI_WARNING, .54)}} else {vk_text(r, 30, 250, "YOUR LIBRARY IS EMPTY", UI_INK, .80); vk_text(r, 30, 286, "Install a portable package, or choose an existing library folder.", UI_MUTED, .66)}
	}
	vk_button(
		r,
		{18, 666, 150, 38},
		"CLOSE",
	); if authoring_workspace.feedback != "" do vk_text(r, 190, 677, authoring_workspace.feedback, UI_INFO, .54)
	if authoring_workspace.pending_lifecycle !=
	   .None {vulkan_ui_rect(r, 278, 580, 574, 78, UI_SURFACE_RAISED); vulkan_ui_outline(r, 278, 580, 574, 78, UI_WARNING, 2); vk_text(r, 300, 590, "UNSAVED STORY / GRAPH / LEVEL DRAFTS", UI_WARNING, .52); vk_button(r, {300, 614, 170, 38}, "SAVE ALL + CONTINUE"); vk_button(r, {480, 614, 190, 38}, "KEEP RECOVERY + CONTINUE"); vk_button(r, {680, 614, 150, 38}, "CANCEL")}
	if authoring_workspace.form_active {label := "NEW ID · ENTER TO RENAME"; #partial switch authoring_workspace.form_action {case .Add:
			label = "NEW RECORD ID · ENTER TO CREATE"; case .Case_Rename:
			label = "NEW CASE TITLE · STABLE ID IS PRESERVED"; case .Case_Move:
			label = "PROJECT-RELATIVE CASE DIRECTORY · ENTER TO MOVE"; case .Diagnostic_Search:
			label = "SEARCH DOCUMENT / ENTITY / FIELD / MESSAGE"; case .Story_Field:
			kind := Story_Authoring_Record_Kind(authoring_workspace.selected_category)
			field, _ := authoring_story_scalar_field(kind, authoring_story_field_cursor)
			label = fmt.tprintf(
				"SET %s · ENTER TO COMMIT",
				strings.to_upper(field),
			); case .Story_List_Add:
			label = "LIST VALUE · ENTER TO INSERT"; case .Story_List_Create:
			label = fmt.tprintf(
				"NEW %v ID · ENTER TO CREATE + PICK",
				Story_Authoring_Record_Kind(authoring_story_picker_kind),
			); case .Asset_Source_URI:
			label = "ASSET SOURCE URI · ENTER TO APPLY"; case .Asset_Source_Name:
			label = "ASSET SOURCE NAME · ENTER TO APPLY"; case .Asset_Creator:
			label = "ASSET CREATOR · ENTER TO APPLY"; case .Asset_Attribution:
			label = "ASSET ATTRIBUTION · ENTER TO APPLY"; case .Asset_License_ID:
			label = "ASSET LICENSE ID · ENTER TO APPLY"; case .Asset_License_Text:
			label = "ASSET LICENSE TEXT · ENTER TO APPLY"; case .Asset_Usage:
			label = "DOCUMENT|ENTITY|FIELD · ENTER TO REGISTER"}; vulkan_ui_rect(r, 300, 520, 600, 100, UI_SURFACE_RAISED); vulkan_ui_outline(r, 300, 520, 600, 100, UI_ACCENT, 2); vk_text(r, 320, 534, label, UI_ACCENT, .48); vulkan_ui_rect(r, 320, 560, 560, 38, {235, 229, 210, 255}); vk_text(r, 330, 570, string(authoring_workspace.form_buffer[:authoring_workspace.form_count]), {30, 26, 20, 255}, .54)}
}
