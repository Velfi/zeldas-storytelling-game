package main

import "core:fmt"
import "core:math"
import "core:strings"

campaign_condition_label :: proc(kind: Campaign_Condition_Kind) -> string {switch
	kind {case .Always:
		return "ALWAYS"; case .Never:
		return "NEVER"; case .All:
		return "ALL"; case .Any:
		return "ANY"; case .Not:
		return "NOT"; case .Boolean_Equals:
		return "BOOLEAN"; case .Integer_Compare:
		return "INTEGER"; case .Enum_Equals:
		return "ENUM"; case .Case_Started:
		return "CASE STARTED"; case .Case_Completed:
		return "CASE COMPLETE"; case .Case_Outcome:
		return "CASE OUTCOME"}
	return "CONDITION"}

vk_campaign_check_stroke :: proc(r: ^Vulkan_Backend, a, b: Vec2, color: [4]u8, thickness: f32) {
	dx, dy :=
		b.x -
		a.x,
		b.y -
		a.y; length := f32(math.sqrt(f64(dx * dx + dy * dy))); if length <= 0 do return
	px, py := -dy / length * thickness * .5, dx / length * thickness * .5
	a0, a1, b0, b1 :=
		Vec2{a.x + px, a.y + py},
		Vec2{a.x - px, a.y - py},
		Vec2{b.x + px, b.y + py},
		Vec2{b.x - px, b.y - py}
	// UI triangles use clockwise screen-space winding.
	vulkan_ui_triangle(r, a0, b0, a1, color); vulkan_ui_triangle(r, a1, b0, b1, color)
}

vk_campaign_check_dot :: proc(r: ^Vulkan_Backend, center: Vec2, radius: f32, color: [4]u8) {
	segments := 12
	for i in 0 ..< segments {
		a :=
			f32(i) *
			2 *
			f32(math.PI) /
			f32(segments); b := f32(i + 1) * 2 * f32(math.PI) / f32(segments)
		// Reverse the perimeter order for clockwise screen-space winding.
		p0 := Vec2 {
			center.x + f32(math.cos(f64(b))) * radius,
			center.y + f32(math.sin(f64(b))) * radius,
		}
		p1 := Vec2 {
			center.x + f32(math.cos(f64(a))) * radius,
			center.y + f32(math.sin(f64(a))) * radius,
		}
		vulkan_ui_triangle(r, center, p0, p1, color)
	}
}

vk_campaign_checkmark :: proc(r: ^Vulkan_Backend, a, joint, b: Vec2, color: [4]u8) {
	thickness: f32 = 2.5
	// Shared solid discs make the two segments one continuous stroke and give
	// the mark round endpoints without adding translucent geometry.
	vk_campaign_check_stroke(
		r,
		a,
		joint,
		color,
		thickness,
	); vk_campaign_check_stroke(r, joint, b, color, thickness)
	vk_campaign_check_dot(
		r,
		a,
		thickness * .5,
		color,
	); vk_campaign_check_dot(r, joint, thickness * .5, color); vk_campaign_check_dot(r, b, thickness * .5, color)
}

vk_campaign_checkbox :: proc(r: ^Vulkan_Backend, box: Rect, label: string, checked: bool) {
	vk_button(r, box, fmt.tprintf("      %s", label))
	check := Rect{box.x + 12, box.y + (box.h - 20) * .5, 20, 20}
	vulkan_ui_rect(r, check.x, check.y, check.w, check.h, {12, 16, 22, 255})
	vulkan_ui_outline(
		r,
		check.x,
		check.y,
		check.w,
		check.h,
		checked ? [4]u8{255, 211, 92, 255} : [4]u8{148, 155, 168, 255},
		2,
	)
	if checked {
		ink := [4]u8{255, 211, 92, 255}
		vk_campaign_checkmark(
			r,
			{check.x + 4, check.y + 10},
			{check.x + 8, check.y + 14},
			{check.x + 16, check.y + 5},
			ink,
		)
	}
}

vk_draw_campaign_workspace :: proc(r: ^Vulkan_Backend, g: ^Game) {
	doc := &campaign_workspace.draft
	vulkan_ui_rect(
		r,
		0,
		0,
		1200,
		720,
		{7, 10, 15, 255},
	); vk_text(r, 18, 18, "CAMPAIGN WORKSPACE", {255, 211, 92, 255}, 1.35); vk_text(r, 850, 22, campaign_workspace.dirty ? "UNSAVED CHANGES" : "SAVED", campaign_workspace.dirty ? [4]u8{255, 144, 119, 255} : [4]u8{117, 229, 169, 255}, .62)
	tabs := [7]string {
		"OVERVIEW",
		"CASES",
		"VARIABLES",
		"CONDITIONS",
		"EFFECTS",
		"SIMULATION",
		"DIAGNOSTICS",
	}; vk_tab_bar(r, {18, 60, 1140, 46}); for label, i in tabs do vk_tab(r, {18 + f32(i) * 164, 64, 156, 38}, label, campaign_workspace.tab == Campaign_Workspace_Tab(i))
	switch campaign_workspace.tab {
	case .Overview:
		vk_text(r, 40, 108, "CAMPAIGN DETAILS", UI_ACCENT, .64)
		vk_button(r, {40, 120, 500, 34}, fmt.tprintf("FORMAT  %s", doc.version))
		vk_button(r, {550, 120, 500, 34}, fmt.tprintf("ID  %s", doc.id))
		vk_button(r, {40, 164, 500, 34}, fmt.tprintf("TITLE  %s", doc.title))
		vk_button(r, {550, 164, 500, 34}, fmt.tprintf("CREATOR  %s", doc.creator))
		vk_button(r, {40, 208, 500, 34}, fmt.tprintf("VERSION  %s", doc.content_version))
		vk_button(r, {550, 208, 500, 34}, fmt.tprintf("THUMBNAIL  %s", doc.thumbnail))
		vk_button(r, {40, 252, 1010, 120}, "EDIT DESCRIPTION")
		vk_text_wrapped(r, 60, 282, 970, doc.description, {205, 207, 210, 255}, .66)
		vk_button(r, {40, 390, 150, 36}, "NEW")
		vk_button(r, {200, 390, 150, 36}, "OPEN")
		vk_button(r, {360, 390, 150, 36}, "DUPLICATE")
		vk_button(r, {520, 390, 150, 36}, "SAVE AS")
		vk_button(r, {680, 390, 150, 36}, "MOVE")
		vk_danger_button(
			r,
			{840, 390, 190, 36},
			campaign_workspace.delete_confirm ? "CONFIRM DELETE" : "DELETE",
		)
	case .Cases:
		vk_text(r, 30, 106, "CASE ORDER", UI_ACCENT, .62)
		vk_text(r, 620, 106, "SELECTED CASE", UI_ACCENT, .62)
		vk_primary_button(r, {30, 108, 120, 32}, "+ ADD CASE")
		vk_button(r, {158, 108, 80, 32}, "UP")
		vk_button(r, {246, 108, 80, 32}, "DOWN")
		vk_danger_button(r, {334, 108, 110, 32}, "REMOVE")
		for item, i in doc.cases do vk_button(r, {30, 148 + f32(i) * 48, 520, 40}, fmt.tprintf("%d  %s", i + 1, strings.to_upper(item.title)), i == campaign_workspace.selected_case)
		if len(doc.cases) == 0 do vk_text(r, 30, 170, "NO CASES YET  ·  ADD A STORY OR MYSTERY TO BEGIN", UI_MUTED, .66)
		i := campaign_workspace.selected_case
		if i >= 0 &&
		   i <
			   len(
				   doc.cases,
			   ) {item := doc.cases[i]; vk_button(r, {620, 112, 250, 34}, fmt.tprintf("TITLE  %s", item.title)); vk_button(r, {880, 112, 250, 34}, fmt.tprintf("ID  %s", item.id)); vk_button(r, {620, 160, 250, 38}, item.required ? "REQUIRED" : "OPTIONAL"); vk_button(r, {880, 160, 250, 38}, fmt.tprintf("VERSION  %s", item.case_content_version)); vk_button(r, {620, 208, 250, 38}, fmt.tprintf("REPLAY  %v", item.replay_mode)); vk_button(r, {620, 256, 250, 38}, fmt.tprintf("HISTORY  %v", item.invalid_result_policy)); vk_button(r, {620, 304, 250, 38}, fmt.tprintf("LOCKED  %v", item.unavailable_presentation)); vk_text(r, 620, 348, "SOURCE DOCUMENTS", UI_MUTED, .54); vk_button(r, {620, 358, 510, 30}, fmt.tprintf("STORY  %s", item.story_path)); vk_button(r, {620, 400, 510, 30}, fmt.tprintf("LEVEL  %s", item.level_path)); vk_button(r, {620, 442, 510, 50}, "EDIT LOCKED MESSAGE"); vk_primary_button(r, {620, 504, 165, 36}, "OPEN SOURCE"); vk_button(r, {795, 504, 165, 36}, "NEW GENERAL"); vk_button(r, {970, 504, 165, 36}, "NEW MYSTERY")}
	case .Variables:
		vk_text(r, 30, 108, "CAMPAIGN STATE", UI_ACCENT, .62)
		vk_text(r, 620, 108, "SELECTED VARIABLE", UI_ACCENT, .62)
		vk_primary_button(r, {30, 120, 150, 38}, "+ VARIABLE")
		vk_danger_button(r, {190, 120, 100, 38}, "REMOVE")
		vk_button(r, {300, 120, 90, 38}, "UP")
		vk_button(r, {400, 120, 90, 38}, "DOWN")
		for variable, i in doc.variables do vk_button(r, {30, 170 + f32(i) * 46, 480, 38}, fmt.tprintf("%s  ·  %v", strings.to_upper(variable.display_name), variable.kind), i == campaign_workspace.selected_variable)
		if len(doc.variables) == 0 {vk_text(r, 30, 184, "NO CAMPAIGN VARIABLES", UI_INK, .70)
			vk_text(
				r,
				30,
				214,
				"Add shared state only when progression crosses case boundaries.",
				UI_MUTED,
				.62,
			)}
		i := campaign_workspace.selected_variable
		if i >= 0 &&
		   i <
			   len(
				   doc.variables,
			   ) {variable := doc.variables[i]; vk_text(r, 620, 130, variable.id, {152, 196, 214, 255}, .72); vk_button(r, {620, 170, 260, 38}, fmt.tprintf("TYPE  %v", variable.kind)); if variable.kind == .Boolean do vk_campaign_checkbox(r, {620, 218, 260, 38}, "DEFAULT", variable.default_boolean)
			else if variable.kind == .Integer {vk_button(r, {620, 218, 120, 38}, "- 1"); vk_button(r, {750, 218, 120, 38}, "+ 1"); vk_text(r, 620, 270, fmt.tprintf("DEFAULT  %d", variable.default_integer), {248, 247, 242, 255}, .72)} else {vk_text(r, 620, 230, fmt.tprintf("DEFAULT  %s", variable.default_enum), {248, 247, 242, 255}, .72); vk_primary_button(r, {620, 266, 120, 34}, "+ VALUE"); vk_danger_button(r, {750, 266, 120, 34}, "REMOVE"); for value, j in variable.enum_values[:variable.enum_value_count] do vk_button(r, {620, 310 + f32(j) * 38, 260, 32}, value, j == campaign_workspace.selected_enum_value)}}
	case .Conditions:
		vk_text(r, 30, 108, "CHOOSE CASE", {255, 211, 92, 255}, .68)
		for item, i in doc.cases do vk_button(r, {30, 120 + f32(i) * 46, 440, 38}, strings.to_upper(item.title), i == campaign_workspace.selected_case)
		labels := [11]string {
			"ALWAYS",
			"NEVER",
			"WRAP ALL",
			"WRAP ANY",
			"WRAP NOT",
			"BOOLEAN",
			"INTEGER",
			"ENUM",
			"CASE STARTED",
			"CASE COMPLETE",
			"CASE OUTCOME",
		}
		for label, i in labels do vk_button(r, {500 + f32(i % 3) * 205, 120 + f32(i / 3) * 44, 195, 34}, label)
		controls := [6]string{"PREV", "NEXT", "UP", "DOWN", "REMOVE", "RESET"}
		for label, i in controls do vk_button(r, {500 + f32(i) * 100, 304, i < 2 ? 82 : 92, 28}, label)
		vk_button(r, {1000, 338, 112, 28}, "+ CHILD")
		node_index := campaign_workspace.selected_condition
		if node_index >= 0 &&
		   node_index <
			   len(
				   doc.conditions,
			   ) {node := doc.conditions[node_index]; parent := campaign_workspace_condition_parent(doc, node_index); vk_text(r, 520, 344, fmt.tprintf("EDITING %s · NODE %d · PARENT %d", campaign_condition_label(node.kind), node_index, parent), {255, 211, 92, 255}, .62); if node.variable_id != "" do vk_button(r, {520, 370, 410, 38}, fmt.tprintf("VARIABLE  %s", node.variable_id)); if node.kind == .Boolean_Equals do vk_campaign_checkbox(r, {520, 418, 200, 38}, "EQUALS TRUE", node.boolean_value); if node.kind == .Integer_Compare {vk_button(r, {520, 418, 200, 38}, fmt.tprintf("%v", node.integer_comparison)); vk_button(r, {730, 418, 96, 38}, "- 1"); vk_button(r, {836, 418, 96, 38}, "+ 1"); vk_text(r, 946, 430, fmt.tprintf("%d", node.integer_value), {248, 247, 242, 255}, .62)}; if node.kind == .Enum_Equals do vk_button(r, {520, 418, 410, 38}, fmt.tprintf("EQUALS  %s", node.enum_value)); if node.case_id != "" do vk_button(r, {520, 466, 410, 38}, fmt.tprintf("CASE  %s", node.case_id)); if node.kind == .Case_Outcome do vk_button(r, {520, 514, 410, 38}, fmt.tprintf("OUTCOME  %v", node.outcome))}
	case .Effects:
		vk_text(r, 30, 108, "CASE OUTCOME EFFECTS", {255, 211, 92, 255}, .72)
		for item, i in doc.cases do vk_button(r, {30, 120 + f32(i) * 42, 420, 34}, strings.to_upper(item.title), i == campaign_workspace.selected_case)
		vk_button(
			r,
			{500, 120, 220, 36},
			fmt.tprintf("OUTCOME  %v", Outcome(campaign_workspace.selected_outcome)),
		)
		vk_button(r, {730, 120, 120, 36}, "+ EFFECT")
		vk_button(r, {860, 120, 100, 36}, "REMOVE")
		vk_button(r, {970, 120, 70, 36}, "UP")
		vk_button(r, {1050, 120, 70, 36}, "DOWN")
		if campaign_workspace.selected_case >= 0 &&
		   campaign_workspace.selected_case <
			   len(
				   doc.cases,
			   ) {first, count := campaign_effect_range(doc.cases[campaign_workspace.selected_case], Outcome(clamp(campaign_workspace.selected_outcome, 0, len(Outcome) - 1)))
			for offset in 0 ..< count {effect_index := first + offset; effect := doc.effects[effect_index]; vk_button(r, {500, 164 + f32(offset) * 34, 450, 28}, fmt.tprintf("%d · %v · %s", offset + 1, effect.kind, effect.variable_id), effect_index == campaign_workspace.selected_effect)}}
		if campaign_workspace.selected_effect >= 0 &&
		   campaign_workspace.selected_effect <
			   len(doc.effects) {effect := doc.effects[campaign_workspace.selected_effect]
			vk_button(r, {500, 500, 450, 38}, fmt.tprintf("TARGET  %s", effect.variable_id))
			if effect.kind == .Set_Boolean do vk_campaign_checkbox(r, {500, 548, 220, 38}, "SET TRUE", effect.boolean_value)
			else if effect.kind == .Set_Integer || effect.kind == .Add_Integer {vk_button(r, {500, 548, 100, 38}, "- 1"); vk_button(r, {610, 548, 100, 38}, "+ 1"); vk_button(r, {720, 548, 230, 38}, fmt.tprintf("%v  %d", effect.kind, effect.integer_value))} else do vk_button(r, {500, 548, 450, 38}, fmt.tprintf("SET  %s", effect.enum_value))}
		vk_button(r, {500, 600, 150, 34}, "MAPPING UP")
		vk_button(r, {660, 600, 150, 34}, "MAPPING DOWN")
		vk_button(r, {820, 600, 190, 34}, "REMOVE MAPPING")
	case .Simulation:
		vk_text(r, 30, 108, "CREATOR-ONLY STATE SIMULATION", {255, 211, 92, 255}, .76)
		if len(doc.variables) >
		   0 {v := doc.variables[clamp(campaign_workspace.selected_variable, 0, len(doc.variables) - 1)]
			state :=
				campaign_workspace.simulated.values[clamp(campaign_workspace.selected_variable, 0, len(doc.variables) - 1)]
			vk_button(r, {780, 108, 180, 34}, fmt.tprintf("VARIABLE %s", v.id))
			if v.kind ==
			   .Integer {vk_button(r, {970, 108, 82, 34}, "- 1"); vk_button(r, {1060, 108, 82, 34}, "+ 1")
				vk_text(
					r,
					1148,
					119,
					fmt.tprintf("%d", state.integer_value),
					{248, 247, 242, 255},
					.52,
				)} else {value := v.kind == .Boolean ? fmt.tprintf("%t", state.boolean_value) : state.enum_value
				vk_button(r, {970, 108, 180, 34}, fmt.tprintf("VALUE %s", value))}}
		for item, i in doc.cases {result := campaign_workspace.simulated.results[i]; unlocked := campaign_case_unlocked(doc, &campaign_workspace.simulated, i)
			status :=
				result.present ? fmt.tprintf("COMPLETED · %v", result.outcome) : result.started ? "STARTED · INCOMPLETE" : "NOT STARTED"
			vk_button(
				r,
				{30, 130 + f32(i) * 48, 720, 38},
				fmt.tprintf("%s  ·  %s", item.title, status),
				i == campaign_workspace.selected_case,
			)
			trace := campaign_evaluate_condition(
				doc,
				&campaign_workspace.simulated,
				item.condition_root,
			)
			vk_text(
				r,
				760,
				142 + f32(i) * 48,
				fmt.tprintf("%s · %s", unlocked ? "AVAILABLE" : "LOCKED", trace.message),
				unlocked ? [4]u8{117, 229, 169, 255} : [4]u8{255, 144, 119, 255},
				.48,
			)}
		if campaign_workspace.simulation_trace != "" do vk_text_wrapped(r, 760, 550, 400, campaign_workspace.simulation_trace, {152, 196, 214, 255}, .44)
		vk_button(r, {30, 610, 150, 34}, "START")
		vk_button(r, {190, 610, 190, 34}, "COMPLETE / REPLAY")
		vk_button(r, {390, 610, 150, 34}, "CLEAR")
		vk_button(r, {550, 610, 190, 34}, "LAUNCH CASE")
	case .Diagnostics:
		vk_text(r, 30, 108, "CAMPAIGN VALIDATION", UI_ACCENT, .68)
		vk_primary_button(r, {30, 130, 240, 38}, "RUN VALIDATION")
		color := campaign_workspace.diagnostics.ok ? UI_SUCCESS : UI_DANGER
		if campaign_workspace.diagnostics.ok {vulkan_ui_rect(r, 30, 180, 1120, 42, UI_SURFACE_RAISED)
			vulkan_ui_outline(r, 30, 180, 1120, 42, UI_SUCCESS, 2)
			vk_text(
				r,
				48,
				190,
				fmt.tprintf("✓  %s", campaign_workspace.diagnostics.message),
				UI_SUCCESS,
				.68,
			)} else do vk_danger_button(r, {30, 180, 1120, 42}, fmt.tprintf("OPEN ISSUE  ·  %s", campaign_workspace.diagnostics.message))
		vk_text(
			r,
			30,
			240,
			"DEPENDENCY MAP  ·  SELECT A CASE TO OPEN ITS CONDITION",
			UI_ACCENT,
			.68,
		)
		for item, i in doc.cases {trace := campaign_evaluate_condition(doc, &campaign_workspace.simulated, item.condition_root); vk_button(r, {40, 270 + f32(i) * 38, 1080, 32}, fmt.tprintf("%s  ←  %s  [%s]", item.id, trace.message, trace.value ? "OPEN" : "LOCKED"))}
	}
	vulkan_ui_rect(
		r,
		0,
		654,
		1200,
		66,
		UI_SURFACE,
	); vk_button(r, {18, 666, 150, 38}, "CLOSE"); vk_primary_button(r, {178, 666, 150, 38}, "SAVE"); vk_button(r, {338, 666, 150, 38}, "VALIDATE"); vk_button(r, {498, 666, 100, 38}, "UNDO"); vk_button(r, {608, 666, 100, 38}, "REDO"); if campaign_workspace.feedback != "" do vk_text(r, 720, 677, campaign_workspace.feedback, UI_INFO, .66)
	if campaign_workspace.text_field !=
	   .None {vulkan_ui_rect(r, 380, 585, 660, 70, {8, 12, 18, 250}); vulkan_ui_outline(r, 380, 585, 660, 70, {255, 211, 92, 255}, 1); vk_text(r, 400, 592, fmt.tprintf("EDIT %v — ENTER TO APPLY · ESC TO CANCEL", campaign_workspace.text_field), {255, 211, 92, 255}, .48); vulkan_ui_rect(r, 400, 610, 620, 34, {238, 233, 220, 255}); vk_editor_text(r, 408, 620, string(campaign_workspace.text_buffer[:campaign_workspace.text_count]), {52, 46, 40, 255}, .52)}
	if campaign_workspace.exit_confirm {vulkan_ui_rect(r, 0, 0, 1200, 720, {4, 7, 10, 200}); vulkan_ui_rect(r, 280, 242, 640, 254, {24, 31, 38, 255}); vulkan_ui_outline(r, 280, 242, 640, 254, {255, 211, 92, 255}, 3); vk_text(r, 320, 274, "UNSAVED CAMPAIGN CHANGES", {255, 218, 112, 255}, .82); vk_text(r, 320, 314, "Save your changes before leaving the campaign editor?", {235, 237, 238, 255}, .60); vk_text(r, 320, 344, "Discarding returns to the last saved campaign.", {170, 218, 228, 255}, .60); vk_button(r, {320, 390, 170, 42}, "SAVE & EXIT", true); vk_button(r, {505, 390, 170, 42}, "DISCARD"); vk_button(r, {690, 390, 170, 42}, "CANCEL"); vk_text(r, 320, 478, "ESC RETURNS TO THE CAMPAIGN EDITOR", {205, 207, 210, 255}, .60)}
}

vk_heading :: proc(r: ^Vulkan_Backend, title, subtitle: string) {
	vk_text(
		r,
		32,
		18,
		title,
		{255, 211, 92, 255},
		1.45,
	); vk_text(r, 32, 48, subtitle, {205, 207, 210, 255}, 1.05)
	vulkan_ui_rect(r, 24, 76, 1152, 3, {255, 211, 92, 255})
}

// A deterministic visual inventory for developing and reviewing the shared
// theme. Knolling the components onto one board makes palette, contrast,
// spacing, and state regressions visible in a single capture.
vk_draw_theme_knoll :: proc(r: ^Vulkan_Backend, g: ^Game) {
	vulkan_ui_rect(r, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, UI_CANVAS)
	material_texture := vulkan_ui_art_texture(
		r,
		.Theme_Materials,
	); if material_texture >= 0 do vulkan_ui_quad(r, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, {72, 67, 58, 96}, material_texture, {0, 0}, {.5, .5}, true)
	vk_text(
		r,
		32,
		18,
		"WESTHAVEN CONSTABULARY",
		UI_ACCENT,
		.64,
	); vk_text(r, 32, 40, "INTERFACE EVIDENCE BOARD", UI_INK_STRONG, 1.42); vk_text(r, 32, 70, "CASE UI-824  ·  Shared player + creator component reference", UI_MUTED, .70); vulkan_ui_rect(r, 32, 96, 1136, 1, UI_ACCENT_DARK); vk_text(r, 1022, 70, "FILED  8:47 PM", UI_ACCENT, .60)

	vk_panel(r, 32, 116, 340, 246); vk_text(r, 52, 136, "01 / MATERIALS", UI_ACCENT, .68)
	swatches := [8][4]u8 {
		UI_CANVAS,
		UI_SURFACE,
		UI_SURFACE_RAISED,
		UI_SURFACE_HOVER,
		UI_ACCENT,
		UI_INFO,
		UI_SUCCESS,
		UI_DANGER,
	}; labels := [8]string{"CANVAS", "SURFACE", "RAISED", "HOVER", "ACCENT", "INFO", "SUCCESS", "DANGER"}
	for color, i in swatches {column := i % 2; row := i / 2; x := f32(52 + column * 152)
		y := f32(170 + row * 42)
		vulkan_ui_rect(r, x, y, 28, 28, color)
		vulkan_ui_outline(r, x, y, 28, 28, UI_BORDER_STRONG, 1)
		vk_text(r, x + 40, y + 6, labels[i], i < 4 ? UI_MUTED : UI_INK, .64)}

	vk_panel(r, 390, 116, 778, 246); vk_text(r, 412, 136, "02 / TYPE + DOCUMENTS", UI_ACCENT, .68)
	vk_text(
		r,
		412,
		172,
		"THE TORN APPOINTMENT",
		UI_INK_STRONG,
		1.26,
	); vk_text(r, 412, 210, "Evidence heading", UI_INK, .94); vk_text(r, 412, 244, "Body copy remains quiet over the scene.", UI_INK, .78); vk_text(r, 412, 276, "VALE HOUSE  ·  STUDY  ·  8:24 PM", UI_MUTED, .66)
	if material_texture >= 0 do vulkan_ui_quad(r, 842, 158, 288, 150, {246, 230, 192, 255}, material_texture, {0, .5}, {.5, 1}, true); vulkan_ui_outline(r, 842, 158, 288, 150, UI_ACCENT_DARK, 1); vk_text(r, 862, 176, "EVIDENCE  07-B", {12, 11, 9, 255}, .64); vulkan_ui_rect(r, 862, 201, 248, 2, {48, 37, 23, 220}); vk_text(r, 862, 216, "STOPPED WATCH", {8, 8, 7, 255}, .88); vk_text(r, 862, 250, "Recovered from Edgar Vale", {18, 16, 12, 255}, .60); vk_text(r, 862, 276, "TIME FIXED:  8:24", {80, 18, 16, 255}, .66)

	vk_panel(r, 32, 382, 726, 306); vk_text(r, 52, 402, "CONTROLS + STATES", UI_ACCENT, .76)
	vk_text(
		r,
		52,
		438,
		"DEFAULT",
		UI_MUTED_DIM,
		.66,
	); vk_button(r, {52, 458, 220, 42}, "CONTINUE"); vk_text(r, 300, 438, "KEYBOARD FOCUS", UI_MUTED_DIM, .66); saved_focus := vk_focused_button; vk_focused_button = button_id({300, 458, 220, 42}); vk_button(r, {300, 458, 220, 42}, "EXAMINE"); vk_focused_button = saved_focus; vk_text(r, 548, 438, "CURRENT CHOICE", UI_MUTED_DIM, .66); vk_button(r, {548, 458, 180, 42}, "SELECTED", true)
	vk_text(
		r,
		52,
		526,
		"COMPACT / CREATOR",
		UI_MUTED_DIM,
		.66,
	); vk_tab_bar_surface(r, {52, 544, 258, 40}); vk_tab_surface(r, {52, 548, 124, 32}, "MATERIALS", false, false); vk_tab_surface(r, {186, 548, 124, 32}, "OBJECTS", true, false); vk_editor_cycle_button(r, {320, 548, 42, 32}, -1); vk_editor_cycle_button(r, {370, 548, 42, 32}, 1)
	vk_dialogue_choice_surface(
		r,
		{52, 606, 676, 56},
		false,
	); vulkan_ui_rect(r, 52, 606, 5, 56, UI_INFO); vk_text(r, 72, 615, "CHALLENGE  ·  Present the stopped watch", UI_INFO, .76); vk_text(r, 72, 639, "Free action  ·  evidence available", UI_MUTED, .66)

	vk_panel(r, 778, 382, 390, 306); vk_text(r, 798, 402, "STATUS + SURFACES", UI_ACCENT, .76)
	status_colors := [4][4]u8 {
		UI_INFO,
		UI_SUCCESS,
		UI_WARNING,
		UI_DANGER,
	}; status_labels := [4]string{"OBSERVATION RECORDED", "DEDUCTION SUPPORTED", "ACTION REQUIRED", "APPROACH CLOSED"}
	for color, i in status_colors {y := f32(440 + i * 48); box := Rect{798, y, 350, 36}
		vk_dialogue_status_surface(r, box, color)
		markers := [4]string{"i", "✓", "!", "×"}
		vk_text(
			r,
			box.x + 48,
			box.y + 8,
			fmt.tprintf("%s  %s", markers[i], status_labels[i]),
			color,
			.64,
		)}
	vulkan_ui_rect(
		r,
		798,
		640,
		350,
		28,
		UI_SURFACE_RAISED,
	); vulkan_ui_outline(r, 798, 640, 350, 28, UI_BORDER, 1); vulkan_ui_rect(r, 798, 640, 230, 28, UI_ACCENT); vk_text(r, 810, 647, "THEME COVERAGE  66%", UI_CANVAS, .56)
}

vk_draw_theme_knoll_details :: proc(r: ^Vulkan_Backend, g: ^Game) {
	vulkan_ui_rect(
		r,
		0,
		0,
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		UI_CANVAS,
	); material_texture := vulkan_ui_art_texture(r, .Theme_Materials); if material_texture >= 0 do vulkan_ui_quad(r, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, {72, 67, 58, 96}, material_texture, {0, 0}, {.5, .5}, true)
	vk_text(
		r,
		32,
		16,
		"WESTHAVEN CONSTABULARY",
		UI_ACCENT,
		UI_CONSOLE_CAPTION_SCALE,
	); vk_text(r, 32, 40, "INPUT + TYPE SPECIMEN", UI_INK_STRONG, 1.42); vk_text(r, 32, 70, "CASE UI-824  ·  Full component inventory  ·  PAGE 02 / 02", UI_MUTED, UI_CONSOLE_LABEL_SCALE); vulkan_ui_rect(r, 32, 96, 1136, 1, UI_ACCENT_DARK)

	// Input inventory: production controls plus the field primitives that are
	// composed directly by editor screens.
	vk_panel(r, 32, 116, 548, 572); vk_text(r, 54, 134, "03 / INPUT INVENTORY", UI_ACCENT, .80)
	vk_text(
		r,
		54,
		172,
		"BUTTONS",
		UI_MUTED,
		UI_CONSOLE_CAPTION_SCALE,
	); vk_button(r, {54, 194, 148, 40}, "DEFAULT"); saved_focus := vk_focused_button; vk_focused_button = button_id({214, 194, 148, 40}); vk_button(r, {214, 194, 148, 40}, "FOCUSED"); vk_focused_button = saved_focus; vk_button(r, {374, 194, 148, 40}, "SELECTED", true)
	vk_text(
		r,
		54,
		248,
		"TABS + PAGING",
		UI_MUTED,
		UI_CONSOLE_CAPTION_SCALE,
	); vk_tab_bar_surface(r, {54, 268, 340, 40}); vk_tab_surface(r, {54, 272, 108, 32}, "EVIDENCE", true, false); vk_tab_surface(r, {170, 272, 108, 32}, "PEOPLE", false, false); vk_tab_surface(r, {286, 272, 108, 32}, "HISTORY", false, false); vk_editor_cycle_button(r, {430, 272, 42, 32}, -1); vk_editor_cycle_button(r, {480, 272, 42, 32}, 1)
	vk_text(
		r,
		54,
		318,
		"TEXT FIELD",
		UI_MUTED,
		UI_CONSOLE_CAPTION_SCALE,
	); vulkan_ui_rect(r, 54, 342, 468, 40, {224, 211, 181, 255}); vulkan_ui_outline(r, 54, 342, 468, 40, UI_ACCENT_DARK, 2); vk_text(r, 68, 351, "Search case notes…", {28, 25, 20, 255}, UI_CONSOLE_LABEL_SCALE); vulkan_ui_rect(r, 246, 351, 3, 22, {99, 27, 25, 255})
	vk_text(
		r,
		54,
		396,
		"CHECKBOXES",
		UI_MUTED,
		UI_CONSOLE_CAPTION_SCALE,
	); vk_campaign_checkbox(r, {54, 416, 214, 38}, "CHECKED", true); vk_campaign_checkbox(r, {282, 416, 240, 38}, "UNCHECKED", false)
	vk_text(
		r,
		54,
		464,
		"RANGE",
		UI_MUTED,
		UI_CONSOLE_CAPTION_SCALE,
	); vulkan_ui_rect(r, 54, 494, 468, 8, UI_SURFACE_RAISED); vulkan_ui_rect(r, 54, 494, 294, 8, UI_ACCENT); vulkan_ui_rect(r, 340, 486, 20, 24, UI_INK_STRONG); vulkan_ui_outline(r, 340, 486, 20, 24, UI_ACCENT_DARK, 2); vk_text(r, 458, 476, "63%", UI_INK, UI_CONSOLE_LABEL_SCALE)
	vk_text(
		r,
		54,
		526,
		"CHOICE + STATUS",
		UI_MUTED,
		UI_CONSOLE_CAPTION_SCALE,
	); choice := Rect{54, 552, 468, 54}; vk_dialogue_choice_surface(r, choice, true); vk_text(r, 74, 561, "◇  Examine the stopped watch", UI_INK, .76); vk_text(r, 74, 584, "OBSERVATION  ·  FREE ACTION", UI_INFO, UI_CONSOLE_CAPTION_SCALE)
	vulkan_ui_rect(
		r,
		54,
		624,
		150,
		34,
		UI_SURFACE_RAISED,
	); vulkan_ui_outline(r, 54, 624, 150, 34, UI_BORDER_STRONG, 2); vk_text(r, 70, 630, "DISABLED", UI_MUTED, UI_CONSOLE_CAPTION_SCALE); vulkan_ui_rect(r, 216, 624, 146, 34, UI_SUCCESS); vk_text(r, 232, 630, "CONFIRM", UI_CANVAS, UI_CONSOLE_CAPTION_SCALE); vulkan_ui_rect(r, 374, 624, 148, 34, UI_DANGER); vk_text(r, 386, 630, "DESTRUCTIVE", UI_INK_STRONG, .62)

	// Type inventory demonstrates hierarchy, prose, metadata, semantic emphasis,
	// and rich inline spans under the same physical-material treatment.
	vk_panel(
		r,
		600,
		116,
		568,
		572,
	); vk_text(r, 622, 134, "04 / TYPOGRAPHY + TEXT STYLING", UI_ACCENT, .80)
	vk_text(
		r,
		622,
		172,
		"DISPLAY / CASE TITLE",
		UI_INK_STRONG,
		1.48,
	); vk_text(r, 622, 216, "Heading / Evidence summary", UI_INK, 1.08); vk_text(r, 622, 254, "Subheading / Witness statement", UI_INK, .90)
	vk_text(
		r,
		622,
		292,
		"BODY",
		UI_MUTED,
		UI_CONSOLE_CAPTION_SCALE,
	); _ = vk_text_wrapped(r, 622, 316, 510, "Blood and bronze in the crushed watch tie 8:24 to the attack. The torn appointment places Miriam in the study minutes earlier.", UI_INK, UI_CONSOLE_BODY_SCALE, 6)
	vk_text(
		r,
		622,
		398,
		"LABEL + METADATA",
		UI_MUTED,
		UI_CONSOLE_CAPTION_SCALE,
	); vk_text(r, 622, 424, "VALE HOUSE  /  STUDY", UI_ACCENT, UI_CONSOLE_LABEL_SCALE); vk_text(r, 868, 424, "RECORDED  8:47 PM", UI_MUTED, UI_CONSOLE_CAPTION_SCALE)
	vk_text(
		r,
		622,
		466,
		"SEMANTIC EMPHASIS",
		UI_MUTED,
		UI_CONSOLE_CAPTION_SCALE,
	); _ = vk_rich_text(r, 622, 492, []Text_Span{{"Evidence ", text_effect_default(UI_INK, .76)}, {"supports", text_effect_default(UI_SUCCESS, .76)}, {" the timeline, but ", text_effect_default(UI_INK, .76)}, {"contradicts", text_effect_default(UI_DANGER, .76)}, {" the witness.", text_effect_default(UI_INK, .76)}}, g.animation_time)
	vulkan_ui_rect(
		r,
		622,
		530,
		510,
		2,
		UI_BORDER_STRONG,
	); vk_text(r, 622, 546, "CAPTION", UI_MUTED, UI_CONSOLE_CAPTION_SCALE); vk_text(r, 726, 546, "Source: stopped watch · Evidence 07-B", UI_MUTED, UI_CONSOLE_CAPTION_SCALE)
	if material_texture >= 0 do vulkan_ui_quad(r, 622, 580, 510, 78, {246, 230, 192, 255}, material_texture, {0, .5}, {.5, 1}, true); vulkan_ui_outline(r, 622, 580, 510, 78, UI_ACCENT_DARK, 1); vk_text(r, 640, 590, "TYPEWRITTEN CASE NOTE", {10, 10, 8, 255}, .70); vk_text(r, 640, 616, "Time of death cannot follow the stopped watch.", {7, 7, 6, 255}, .80); vk_text(r, 956, 636, "— DET. 12", {76, 16, 15, 255}, .64)
}

vk_editor_preview_callout :: proc(
	r: ^Vulkan_Backend,
	g: ^Game,
	message: string,
	state: Placement_State,
) {
	if message == "" || state == .Valid || !editor_viewport_contains(g.input.mouse_pos, g.build_tool) do return
	label := strings.to_upper(message); if len(label) > 58 do label = label[:58]
	color := state == .Blocked ? [4]u8{255, 144, 119, 255} : [4]u8{255, 211, 92, 255}
	width := max(
		f32(220),
		f32(utf8_glyph_count(label)) * 7 + 24,
	); x := clamp(g.input.mouse_pos.x + 18, f32(82), f32(1188) - width); y := clamp(g.input.mouse_pos.y - 44, f32(112), f32(650))
	vulkan_ui_rect(
		r,
		x,
		y,
		width,
		32,
		{10, 14, 18, 242},
	); vulkan_ui_outline(r, x, y, width, 32, color, 2); vk_editor_text(r, x + 12, y + 9, label, color, .60)
}

vk_draw_introduction :: proc(r: ^Vulkan_Backend, g: ^Game) {
	if g.introduction_step == 0 {
		vk_heading(r, "THE CAST", g.story_project != nil ? g.story_project.title : "")
		vk_text(r, 32, 88, "Question the household. Examine the scene.", {205, 207, 210, 255}, .78)
		if g.story_project != nil do for character, i in g.story_project.entities {
			if character.kind != "character" do continue
			if i >= 4 do break
			column := i % 2; row := i / 2; x := f32(105 + column * 505); y := f32(125 + row * 220)
			vk_panel(r, x, y, 485, 195)
			vk_art_fit(r, portrait_art(character.id), x + 18, y + 18, 125, 155)
			vk_text(r, x + 165, y + 22, strings.to_upper(character.display_name), {255, 211, 92, 255}, 1.0)
			role := character.tag_count > 0 ? character.tags[0] : "character"; vk_text(r, x + 165, y + 52, strings.to_upper(role), {155, 201, 255, 255}, .6)
			_ = vk_text_wrapped(r, x + 165, y + 80, 290, character.description, {248, 247, 242, 255}, .58, 4)
		}
		vk_button(r, {410, 625, 380, 58}, "BEGIN THE MYSTERY", true)
		return
	}
	vk_heading(r, "VALE HOUSE", "Rain, 8:47 p.m.")
	vk_panel(r, 135, 105, 930, 475)
	// An in-world summons establishes only why the investigator is here. It does
	// not hand over a timeline, suspect, or contradiction before play begins.
	vulkan_ui_rect(
		r,
		205,
		175,
		310,
		300,
		{218, 205, 174, 255},
	); vulkan_ui_outline(r, 205, 175, 310, 300, {105, 82, 57, 255}, 3)
	vk_text(
		r,
		245,
		210,
		"VALE HOUSE",
		{68, 53, 42, 255},
		1.15,
	); vk_text(r, 245, 243, "TELEPHONE MESSAGE", {105, 82, 57, 255}, .62)
	_ = vk_text_wrapped(
		r,
		245,
		300,
		230,
		g.story_project != nil ? g.story_project.description : "",
		{68, 53, 42, 255},
		.78,
		7,
	)
	_ = vk_text_wrapped(
		r,
		590,
		205,
		360,
		"Rain ticks against the dark windows. Dinner has gone cold. No one from the household comes to meet you at the door.",
		{248, 247, 242, 255},
		1.05,
		7,
	)
	vk_text(r, 590, 390, "Look. Listen. Touch what seems wrong.", {155, 201, 255, 255}, .72)
	vk_button(r, {410, 625, 380, 58}, "ENTER VALE HOUSE", true)
}

vk_draw_clock_ticks :: proc(r: ^Vulkan_Backend, g: ^Game) {
	// The twelve actions read as slices of the stopped watch instead of a ruler.
	payload := mystery_game_payload(
		g,
	); total := payload != nil ? payload.action_budget : 0; cx, cy := f32(70), f32(584); face_radius := f32(32)
	// A dark dial underneath the generated brass case prevents the world from
	// showing through the small inter-slice gaps.
	for i in 0 ..< 24 {a0 := f32(i) * 2 * f32(math.PI) / 24; a1 := f32(i + 1) * 2 * f32(math.PI) / 24; p0 := Vec2{cx + f32(math.cos(f64(a0))) * face_radius, cy + f32(math.sin(f64(a0))) * face_radius}; p1 := Vec2{cx + f32(math.cos(f64(a1))) * face_radius, cy + f32(math.sin(f64(a1))) * face_radius}; vulkan_ui_triangle(r, {cx, cy}, p0, p1, {25, 26, 28, 245})}
	// The generated enamel face supplies the aged surface and engraved twelve-way
	// division; translucent state wedges let that material continue to show.
	if r.watch_face_texture >= 0 do vulkan_ui_quad(r, cx - 35, cy - 35, 70, 70, {255, 255, 255, 255}, r.watch_face_texture, {}, {1, 1}, true)
	for i in 0 ..< total {
		gap := f32(
			.025,
		); a0 := -f32(math.PI) / 2 + f32(i) * 2 * f32(math.PI) / f32(total) + gap; a1 := -f32(math.PI) / 2 + f32(i + 1) * 2 * f32(math.PI) / f32(total) - gap
		p0 := Vec2 {
			cx + f32(math.cos(f64(a0))) * face_radius,
			cy + f32(math.sin(f64(a0))) * face_radius,
		}; p1 := Vec2{cx + f32(math.cos(f64(a1))) * face_radius, cy + f32(math.sin(f64(a1))) * face_radius}
		active :=
			i <
			g.ap; color := active ? [4]u8{255, 218, 112, 95} : [4]u8{30, 31, 34, 185}; if active && g.ap <= 2 do color = {255, 144, 119, 125}
		vulkan_ui_triangle(r, {cx, cy}, p0, p1, color)
	}
	// The authored frame supplies the patinated case, crown, lugs, and leather.
	if r.watch_frame_texture >= 0 do vulkan_ui_quad(r, cx - 60, cy - 60, 120, 120, {255, 255, 255, 255}, r.watch_frame_texture, {}, {1, 1}, true)
	vulkan_ui_rect(r, cx - 3, cy - 3, 6, 6, {248, 247, 242, 255})
	vk_text(
		r,
		138,
		563,
		g.ap == 1 ? "FINAL SLICE" : fmt.tprintf("%d / %d", g.ap, total),
		g.ap <= 2 ? [4]u8{255, 144, 119, 255} : [4]u8{255, 218, 112, 255},
		1,
	)
	vk_text(r, 138, 589, "TIME REMAINING", {205, 207, 210, 255}, .72)
}

context_status_color :: proc(status: Context_Status) -> [4]u8 {switch status {case .Complete:
		return {117, 229, 169, 255}; case .Locked, .No_Power, .Obstructed, .Unavailable:
		return {255, 144, 119, 255}; case .Available:
		return {255, 218, 112, 255}}; return {255, 218, 112, 255}}

vk_draw_time_chip :: proc(r: ^Vulkan_Backend, g: ^Game) {
	x, y :=
		f32(1042),
		f32(
			16,
		); vulkan_ui_rect(r, x + 3, y + 4, 140, 48, {5, 7, 10, 85}); vulkan_ui_rect(r, x, y, 140, 48, {19, 22, 27, 232}); vulkan_ui_outline(r, x, y, 140, 48, {139, 107, 55, 220}, 1)
	if r.watch_face_texture >= 0 do vulkan_ui_quad(r, x + 8, y + 4, 40, 40, {255, 255, 255, 255}, r.watch_face_texture, {}, {1, 1}, true)
	payload := mystery_game_payload(
		g,
	); total := payload != nil ? payload.action_budget : 0; color := g.ap <= 2 ? [4]u8{255, 144, 119, 255} : [4]u8{255, 218, 112, 255}; vk_text(r, x + 55, y + 7, fmt.tprintf("%d / %d", g.ap, total), color, .82); vk_text(r, x + 55, y + 27, "TICKS LEFT", {205, 207, 210, 255}, .48)
}

vk_draw_location_plaque :: proc(r: ^Vulkan_Backend, title: string) {
	w := max(
		f32(190),
		f32(utf8_glyph_count(title)) * COURIER_CELL_WIDTH * .72 + 34,
	); vulkan_ui_rect(r, 19, 20, w, 35, {4, 6, 9, 85}); vulkan_ui_rect(r, 16, 16, w, 35, {22, 25, 30, 235}); vulkan_ui_outline(r, 16, 16, w, 35, {139, 107, 55, 215}, 1); vulkan_ui_rect(r, 16, 16, 5, 35, {255, 218, 112, 255}); vk_text(r, 31, 25, strings.to_upper(title), {248, 247, 242, 255}, .72)
}

context_bubble_visible :: proc(g: ^Game, target: Context_Target) -> bool {
	return target.valid && (g.active_device == .Keyboard_Mouse || target.reachable)
}

vk_draw_context_bubble :: proc(r: ^Vulkan_Backend, g: ^Game, target: Context_Target) {
	if !context_bubble_visible(g, target) do return
	screen, visible := context_world_point_screen(
		g,
		target.world,
	); edge := !visible; screen.x = clamp(screen.x, f32(76), f32(WINDOW_WIDTH - 76)); screen.y = clamp(screen.y, f32(118), f32(WINDOW_HEIGHT - 92))
	color := context_status_color(
		target.status,
	); age := clamp((g.animation_time - g.context_ui.focus_started) / .18, 0, 1); ease := 1 - (1 - age) * (1 - age); label_w := f32(utf8_glyph_count(target.label)) * COURIER_CELL_WIDTH * .68; action_w := f32(utf8_glyph_count(target.action)) * COURIER_CELL_WIDTH * .55; width := max(f32(176), max(label_w, action_w) + 66) * ease; height := f32(58); x := clamp(screen.x - width * .5, f32(8), f32(WINDOW_WIDTH) - width - 8); y := clamp(screen.y - height - 10, f32(72), f32(610))
	if edge do vulkan_ui_triangle(r, {screen.x, screen.y - 8}, {screen.x - 7, screen.y + 3}, {screen.x + 7, screen.y + 3}, color)
	vulkan_ui_rect(
		r,
		x + 3,
		y + 5,
		width,
		height,
		{4, 6, 9, 90},
	); vulkan_ui_rect(r, x, y, width, height, {24, 27, 31, 244}); vulkan_ui_outline(r, x, y, width, height, color, 2); vulkan_ui_triangle(r, {screen.x - 7, y + height}, {screen.x + 7, y + height}, {screen.x, y + height + 9}, color)
	prompt_kind: Prompt_Kind = target.kind == .Vehicle ? .Vehicle_Action : .Interact
	vk_text(
		r,
		x + 14,
		y + 9,
		target.label,
		{248, 247, 242, 255},
		.68,
	); vk_text(r, x + 14, y + 32, target.action, color, .55); vk_prompt_icon(r, g, prompt_kind, x + width - 43, y + 13, 30)
}

vk_draw_context_group :: proc(r: ^Vulkan_Backend, g: ^Game) {
	if g.context_ui.target_count <= 1 {vk_draw_context_bubble(r, g, g.context_ui.current); return}
	count :=
		g.context_ui.target_count; row_h := f32(38); width := f32(310); height := f32(count) * row_h + 31; x := clamp(f32(WINDOW_WIDTH) - width - 18, f32(8), f32(WINDOW_WIDTH) - width - 8); y := clamp(f32(118), f32(72), f32(WINDOW_HEIGHT) - height - 58)
	vulkan_ui_rect(
		r,
		x + 4,
		y + 5,
		width,
		height,
		{4, 6, 9, 90},
	); vulkan_ui_rect(r, x, y, width, height, {24, 27, 31, 246}); vulkan_ui_outline(r, x, y, width, height, {255, 218, 112, 220}, 2)
	hint := fmt.tprintf(
		"%s  SELECT",
		prompt_label(g, .Navigate),
	); vk_text(r, x + 12, y + 8, fmt.tprintf("NEARBY  %d  ·  %s", count, hint), {205, 207, 210, 255}, .44)
	for target, i in g.context_ui.targets[:count] {row_y := y + 29 + f32(i) * row_h; selected := i == g.context_ui.selected; color := selected ? context_status_color(target.status) : [4]u8{143, 148, 155, 255}; if selected {vulkan_ui_rect(r, x + 5, row_y - 2, width - 10, row_h, {56, 61, 68, 235}); vulkan_ui_rect(r, x + 5, row_y - 2, 4, row_h, color)}; label := target.label; if len(label) > 25 do label = label[:25]; vk_text(r, x + 16, row_y + 2, label, selected ? [4]u8{248, 247, 242, 255} : [4]u8{190, 193, 198, 255}, .52); vk_text(r, x + 16, row_y + 20, target.action, color, .38); if selected do vk_prompt_icon(r, g, .Interact, x + width - 39, row_y + 2, 28)}
}

vk_draw_context_toast :: proc(r: ^Vulkan_Backend, g: ^Game) {if g.context_ui.feedback == "" || g.animation_time >= g.context_ui.feedback_expires do return
	color := context_status_color(g.context_ui.feedback_status)
	width := max(
		f32(250),
		f32(utf8_glyph_count(g.context_ui.feedback)) * COURIER_CELL_WIDTH * .58 + 34,
	)
	x := (f32(WINDOW_WIDTH) - width) * .5
	vulkan_ui_rect(r, x + 3, 604, width, 38, {0, 0, 0, 80})
	vulkan_ui_rect(r, x, 600, width, 38, {24, 27, 31, 246})
	vulkan_ui_outline(r, x, 600, width, 38, color, 2)
	vk_text(r, x + 17, 611, g.context_ui.feedback, color, .58)}

vk_draw_house_glints :: proc(r: ^Vulkan_Backend, g: ^Game) {
	// The nearby list is a single selection, so its world indicator must identify
	// that selection rather than every other reachable target.
	target := g.context_ui.current
	if !target.valid || !target.reachable do return
	screen, visible := context_world_point_screen(g, target.world)
	if !visible do return
	color := context_status_color(target.status)
	vulkan_ui_rect(r, screen.x - 3, screen.y - 3, 6, 6, color)
	vulkan_ui_outline(
		r,
		screen.x - 7,
		screen.y - 7,
		14,
		14,
		{color[0], color[1], color[2], 145},
		2,
	)
}

vk_draw_case_sense_poi_ping :: proc(r: ^Vulkan_Backend, g: ^Game) {
	if g.case_sense_level == 0 || g.animation_time >= g.case_sense_hint_until do return
	payload := mystery_game_payload(
		g,
	); location := world_location_index(g); if payload == nil || location < 0 || location >= len(payload.locations) do return; age := clamp(1 - (g.case_sense_hint_until - g.animation_time) / 5, 0, 1); pulse := f32(math.sin(f64(age * math.PI))); color := [4]u8{255, 218, 112, u8(120 + 100 * pulse)}
	for &entity in WORLD_ENTITIES {
		poi := poi_index(
			g,
			entity.source_id,
		); if poi < 0 || poi >= len(payload.pois) || payload.pois[poi].location_id != payload.locations[location].entity_id || !entity_visible(g, &entity) do continue
		// Keep the pulse on the visible body of the object. A ground-plane anchor
		// falls below furniture and outside a level first-person view.
		screen, visible := context_world_position_screen(
			g,
			{entity.x, .9, entity.y},
		); if !visible do continue
		radius := f32(
			12 + 8 * pulse,
		); vulkan_ui_outline(r, screen.x - radius, screen.y - radius, radius * 2, radius * 2, color, 3); vulkan_ui_outline(r, screen.x - radius - 5, screen.y - radius - 5, (radius + 5) * 2, (radius + 5) * 2, {color[0], color[1], color[2], u8(45 + 55 * pulse)}, 2)
	}
}

vk_draw_shortcut_cluster :: proc(r: ^Vulkan_Backend, g: ^Game) {attributes, notebook, theory :=
		gameplay_attributes_rect(), gameplay_notebook_rect(), gameplay_theory_rect()
	boxes := [3]Rect{attributes, notebook, theory}
	for 	box in boxes {vulkan_ui_rect(r, box.x, box.y, box.w, box.h, {17, 20, 24, 224}); vulkan_ui_outline(
			r,
			box.x,
			box.y,
			box.w,
			box.h,
			contains(box, g.input.mouse_pos) ? [4]u8{255, 218, 112, 230} : [4]u8{74, 78, 84, 190},
			contains(box, g.input.mouse_pos) ? 2 : 1,
		)}
	vk_prompt_icon(r, g, .Attributes, attributes.x + 8, attributes.y + 8, 26)
	vk_text(r, attributes.x + 40, attributes.y + 14, "ATTR", {205, 207, 210, 255}, .44)
	vk_prompt_icon(r, g, .Notebook, notebook.x + 8, notebook.y + 8, 26)
	vk_text(r, notebook.x + 40, notebook.y + 14, "NOTES", {205, 207, 210, 255}, .44)
	vk_prompt_icon(r, g, .Board, theory.x + 8, theory.y + 8, 26)
	vk_text(r, theory.x + 40, theory.y + 14, "THEORY", {205, 207, 210, 255}, .44)}

quest_transition_enqueue :: proc(g: ^Game, id: string, status: Story_Objective_Status) {
	was_empty :=
		len(g.quest_transition_ids) ==
		0; append(&g.quest_transition_ids, id); append(&g.quest_transition_status, status)
	if was_empty do g.quest_transition_started = g.animation_time
}

quest_tracker_sync :: proc(g: ^Game) {
	if g.story_project == nil || g.story_state == nil do return
	count := min(len(g.story_state.objectives), len(g.quest_observed))
	if !g.quest_tracker_initialized {for i in 0 ..< count do g.quest_observed[i] = g.story_state.objectives[i].status; g.quest_observed_count = count; g.quest_tracker_initialized = true; return}
	// Completion is announced before a newly activated successor, even when both
	// statuses change in the same authored transaction.
	for i in 0 ..< count {status := g.story_state.objectives[i].status; old := i < g.quest_observed_count ? g.quest_observed[i] : Story_Objective_Status.Inactive; if status != old && (status == .Completed || status == .Failed) do quest_transition_enqueue(g, g.story_state.objectives[i].objective_id, status)}
	for i in 0 ..< count {status := g.story_state.objectives[i].status; old := i < g.quest_observed_count ? g.quest_observed[i] : Story_Objective_Status.Inactive; if status != old && status == .Active do quest_transition_enqueue(g, g.story_state.objectives[i].objective_id, status); g.quest_observed[i] = status}
	g.quest_observed_count = count
	if len(g.quest_transition_ids) >
	   0 {duration := g.quest_transition_status[0] == .Active ? f32(1.2) : f32(1.5); if g.animation_time - g.quest_transition_started >= duration {ordered_remove(&g.quest_transition_ids, 0); ordered_remove(&g.quest_transition_status, 0); g.quest_transition_started = g.animation_time}}
}

vk_draw_quest_card :: proc(
	r: ^Vulkan_Backend,
	g: ^Game,
	objective_index: int,
	status: Story_Objective_Status,
	transition: bool,
	x, y: f32,
) {
	objective :=
		g.story_project.objectives[objective_index]; w := f32(390); h := f32(78); accent := status == .Completed ? [4]u8{117, 229, 169, 255} : status == .Failed ? [4]u8{255, 144, 119, 255} : [4]u8{255, 218, 112, 255}
	vulkan_ui_rect(
		r,
		x + 3,
		y + 4,
		w,
		h,
		{4, 6, 9, 85},
	); vulkan_ui_rect(r, x, y, w, h, {19, 22, 27, 232}); vulkan_ui_outline(r, x, y, w, h, {82, 87, 94, 215}, 1); vulkan_ui_rect(r, x, y, 5, h, accent)
	heading :=
		transition ? (status == .Completed ? "OBJECTIVE COMPLETE" : status == .Failed ? "OBJECTIVE CLOSED" : "NEW OBJECTIVE") : "CURRENT OBJECTIVE"; vk_text(r, x + 17, y + 9, heading, accent, .38); vk_text(r, x + 17, y + 28, objective.display_name, {248, 247, 242, 255}, .62); _ = vk_text_wrapped(r, x + 17, y + 49, w - 32, objective.description, {190, 194, 201, 255}, .42, 2)
}

vk_draw_quest_tracker :: proc(r: ^Vulkan_Backend, g: ^Game) {
	if g.story_project == nil || g.story_state == nil do return
	quest_tracker_sync(g); if !quest_tracker_enabled(g) do return
	objective_index := -1; status := Story_Objective_Status.Active; transition := len(g.quest_transition_ids) > 0
	if transition {objective_index = story_objective_index(g.story_project, g.quest_transition_ids[0]); status = g.quest_transition_status[0]} else do objective_index = story_tracked_objective_index(g.story_project, g.story_state)
	if objective_index < 0 || objective_index >= len(g.story_project.objectives) || g.story_project.objectives[objective_index].hidden do return
	vk_draw_quest_card(
		r,
		g,
		objective_index,
		status,
		transition,
		16,
		g.screen == .Exterior ? f32(96) : f32(64),
	)
}

vk_draw_quest_transition_overlay :: proc(r: ^Vulkan_Backend, g: ^Game) {
	if g.story_project == nil || g.story_state == nil || g.screen == .Exterior || g.screen == .Investigate do return
	quest_tracker_sync(
		g,
	); if g.guidance_mode == .Minimal || len(g.quest_transition_ids) == 0 do return
	objective_index := story_objective_index(
		g.story_project,
		g.quest_transition_ids[0],
	); if objective_index < 0 || g.story_project.objectives[objective_index].hidden do return
	x, y :=
		g.screen == .Dialogue ? f32(16) : f32(405),
		g.screen == .Dialogue ? f32(64) : f32(24); vk_draw_quest_card(r, g, objective_index, g.quest_transition_status[0], true, x, y)
}

quest_tracker_enabled :: proc(g: ^Game) -> bool {return(
		g.guidance_mode != .Minimal &&
		g.story_project != nil &&
		g.story_state != nil &&
		(g.screen == .Exterior || g.screen == .Investigate) \
	)}

vk_draw_tutorial_prompt :: proc(r: ^Vulkan_Backend, g: ^Game) {
	if !case_uses_city_tutorial(g) || g.guidance_mode == .Minimal do return
	label := ""; kind := Prompt_Kind.Move
	if !tutorial_completed(
		g,
		.Move,
	) {label = tutorial_lesson_prompt(g, .Move, "MOVE"); kind = .Move} else if !tutorial_completed(g, .Look) {label = tutorial_lesson_prompt(g, .Look, "LOOK AROUND"); kind = .Look} else if !tutorial_completed(g, .Briefing) && city_briefing_actionable(g) {label = tutorial_lesson_prompt(g, .Briefing, "RECEIVE BRIEFING"); kind = .Interact} else do return
	control_width := max(
		f32(32),
		f32(utf8_glyph_count(prompt_label(g, kind))) * 6 + 14,
	); box := Rect{420, 642, 360, 50}; vulkan_ui_rect(r, box.x + 3, box.y + 4, box.w, box.h, {0, 0, 0, 90}); vulkan_ui_rect(r, box.x, box.y, box.w, box.h, {20, 24, 30, 242}); vulkan_ui_outline(r, box.x, box.y, box.w, box.h, {255, 211, 92, 220}, 2); vk_prompt_icon(r, g, kind, box.x + 12, box.y + 9, 32); vk_text(r, box.x + control_width + 26, box.y + 16, label, {248, 247, 242, 255}, .66)
}

city_minimap_camera_basis :: proc(g: ^Game) -> (right, forward: Vec2) {
	view := vk_world_view_pose(
		g,
	); forward = {view.target.x - view.eye.x, view.target.z - view.eye.z}
	length := f32(math.sqrt(f64(forward.x * forward.x + forward.y * forward.y)))
	if length <=
	   .0001 {forward = {f32(math.cos(f64(g.city_angle))), f32(math.sin(f64(g.city_angle)))}} else {forward = {forward.x / length, forward.y / length}}
	right = {-forward.y, forward.x}
	return
}

city_minimap_project :: proc(
	point, center, right, forward: Vec2,
	map_center: Vec2,
	scale_x, scale_y: f32,
) -> Vec2 {
	delta := Vec2{point.x - center.x, point.y - center.y}
	return {
		map_center.x + (delta.x * right.x + delta.y * right.y) * scale_x,
		map_center.y - (delta.x * forward.x + delta.y * forward.y) * scale_y,
	}
}

city_quest_marker_visible :: proc(g: ^Game, landmark: City_Landmark) -> bool {
	payload := mystery_game_payload(
		g,
	); if payload == nil || landmark.id != payload.city_destination do return false
	return !case_uses_city_tutorial(g) || tutorial_completed(g, .Briefing)
}

vk_draw_city_quest_marker :: proc(r: ^Vulkan_Backend, x, y: f32) {
	color := [4]u8{255, 218, 112, 255}; outline := [4]u8{74, 54, 24, 245}
	// A compact map-pin diamond reads as the active destination without adding a
	// world-space arrow or route that would compete with the authored city.
	top := Vec2 {
		x,
		y - 8,
	}; right := Vec2{x + 7, y - 1}; bottom := Vec2{x, y + 6}; left := Vec2{x - 7, y - 1}
	vulkan_ui_triangle(
		r,
		top,
		right,
		bottom,
		outline,
	); vulkan_ui_triangle(r, top, bottom, left, outline)
	inner_top := Vec2 {
		x,
		y - 5,
	}; inner_right := Vec2{x + 4, y - 1}; inner_bottom := Vec2{x, y + 3}; inner_left := Vec2{x - 4, y - 1}
	vulkan_ui_triangle(
		r,
		inner_top,
		inner_right,
		inner_bottom,
		color,
	); vulkan_ui_triangle(r, inner_top, inner_bottom, inner_left, color)
	vulkan_ui_rect(r, x - 1, y + 6, 2, 4, color)
}

city_minimap_clamp_quest_marker :: proc(point: Vec2, map_x, map_y, map_w, map_h: f32) -> Vec2 {
	edge := f32(11)
	return {
		clamp(point.x, map_x + edge, map_x + map_w - edge),
		clamp(point.y, map_y + edge, map_y + map_h - edge),
	}
}

vk_draw_city_minimap :: proc(r: ^Vulkan_Backend, g: ^Game) {
	x, y, w, h :=
		f32(966),
		f32(82),
		f32(216),
		f32(
			180,
		); inset := f32(8); map_x, map_y := x + inset, y + inset; map_w, map_h := w - inset * 2, h - inset * 2
	vulkan_ui_rect(
		r,
		x + 3,
		y + 4,
		w,
		h,
		{4, 6, 9, 100},
	); vulkan_ui_rect(r, x, y, w, h, {15, 20, 25, 238}); vulkan_ui_outline(r, x, y, w, h, {139, 107, 55, 220}, 1)
	vulkan_ui_rect(r, map_x, map_y, map_w, map_h, {37, 58, 61, 255})
	// The city is larger than this panel can usefully show at once. Keep the
	// player at the center of a camera-relative neighborhood-sized window.
	view_w, view_h := f32(72), f32(59.04); half_w, half_h := view_w * .5, view_h * .5
	center_x, center_y := g.city_x, g.city_y
	center := Vec2 {
		center_x,
		center_y,
	}; map_center := Vec2{map_x + map_w * .5, map_y + map_h * .5}; scale_x, scale_y := map_w / view_w, map_h / view_h; right, forward := city_minimap_camera_basis(g)
	vulkan_ui_scissor(r, map_x, map_y, map_w, map_h)
	view_radius := f32(math.sqrt(f64(half_w * half_w + half_h * half_h))) + 6
	first_x := max(
		0,
		int(math.floor(f64((center_x - view_radius) / 4))) * 4,
	); last_x := min(CITY_WIDTH, int(math.ceil(f64((center_x + view_radius) / 4))) * 4)
	first_y := max(
		0,
		int(math.floor(f64((center_y - view_radius) / 4))) * 4,
	); last_y := min(CITY_HEIGHT, int(math.ceil(f64((center_y + view_radius) / 4))) * 4)
	for iy := first_y; iy < last_y; iy += 4 {
		for ix := first_x; ix < last_x; ix += 4 {
			if !city_road_cell(ix + 2, iy + 2) do continue
			a := city_minimap_project(
				{f32(ix), f32(iy)},
				center,
				right,
				forward,
				map_center,
				scale_x,
				scale_y,
			); b := city_minimap_project({f32(ix + 4), f32(iy)}, center, right, forward, map_center, scale_x, scale_y); c := city_minimap_project({f32(ix + 4), f32(iy + 4)}, center, right, forward, map_center, scale_x, scale_y); d := city_minimap_project({f32(ix), f32(iy + 4)}, center, right, forward, map_center, scale_x, scale_y)
			vulkan_ui_triangle(
				r,
				a,
				b,
				c,
				{117, 126, 126, 235},
			); vulkan_ui_triangle(r, a, c, d, {117, 126, 126, 235})
		}
	}
	for i in 0 ..< city_landmark_count(g) {
		landmark, ok := city_landmark_at(g, i); if !ok do continue
		projected := city_minimap_project(
			{landmark.x, landmark.y},
			center,
			right,
			forward,
			map_center,
			scale_x,
			scale_y,
		); lx, ly := projected.x, projected.y
		quest_marker := city_quest_marker_visible(
			g,
			landmark,
		); color := landmark.case_authored ? [4]u8{205, 176, 101, 225} : [4]u8{152, 196, 214, 235}; radius := f32(2.5)
		if quest_marker {clamped := city_minimap_clamp_quest_marker({lx, ly}, map_x, map_y, map_w, map_h); lx, ly = clamped.x, clamped.y} else if lx < map_x || lx > map_x + map_w || ly < map_y || ly > map_y + map_h do continue
		if quest_marker do vk_draw_city_quest_marker(r, lx, ly)
		else do vulkan_ui_rect(r, lx - radius, ly - radius, radius * 2, radius * 2, color)
	}
	player := city_minimap_project(
		{g.city_x, g.city_y},
		center,
		right,
		forward,
		map_center,
		scale_x,
		scale_y,
	); px, py := player.x, player.y; heading := Vec2{f32(math.cos(f64(g.city_angle))), f32(math.sin(f64(g.city_angle)))}
	marker_forward := Vec2 {
		heading.x * right.x + heading.y * right.y,
		-(heading.x * forward.x + heading.y * forward.y),
	}; marker_side := Vec2{-marker_forward.y, marker_forward.x}; tip := Vec2{px + marker_forward.x * 8, py + marker_forward.y * 8}; left := Vec2{px - marker_forward.x * 5 + marker_side.x * 4, py - marker_forward.y * 5 + marker_side.y * 4}; marker_right := Vec2{px - marker_forward.x * 5 - marker_side.x * 4, py - marker_forward.y * 5 - marker_side.y * 4}
	vulkan_ui_triangle(
		r,
		tip,
		left,
		marker_right,
		{255, 244, 190, 255},
	); vulkan_ui_outline(r, px - 2, py - 2, 4, 4, {30, 34, 38, 255}, 1); vulkan_ui_scissor_reset(r)
	vk_text(r, x + 9, y + h - 17, "CITY MAP", {205, 207, 210, 235}, .36)
}

vk_draw_city_overlay :: proc(r: ^Vulkan_Backend, g: ^Game) {
	payload := mystery_game_payload(
		g,
	); location := fmt.tprintf("VALE CITY · %s", city_neighborhood_name(g.city_x, g.city_y)); if payload != nil && !tutorial_completed(g, .Briefing) {start_index := city_landmark_index(g, payload.city_start); if start_index >= 0 {start, _ := city_landmark_at(g, start_index); location = start.name}}; vk_draw_location_plaque(r, location)
	hour_value := world_time_hour(
		g.animation_time,
	); hour := int(hour_value); minute := int((hour_value - f32(hour)) * 60); vk_text(r, 28, 72, fmt.tprintf("%02d:%02d  ·  WEATHER: RAIN", hour, minute), {205, 220, 224, 235}, .42)
	vk_draw_city_minimap(r, g)
	if g.context_ui.current.valid && g.driving_vehicle < 0 do vk_draw_context_bubble(r, g, g.context_ui.current)
	if g.driving_vehicle >= 0 {
		car :=
			g.vehicles[g.driving_vehicle]; traction := car.traction_state; slip := vehicle_slip_ratio(car); traction_color := traction == .Grip ? [4]u8{117, 229, 169, 255} : traction == .Slip ? [4]u8{255, 211, 92, 255} : [4]u8{255, 144, 119, 255}
		_, exit_clear := vehicle_exit_position(
			g,
			car,
			g.driving_vehicle,
		); stopped := vehicle_can_exit(car); exit_ready := stopped && exit_clear; exit_label := exit_ready ? fmt.tprintf("%s  EXIT", prompt_label(g, .Vehicle_Action)) : stopped ? "NO EXIT SPACE" : "SLOW TO EXIT"
		handbrake := vehicle_handbrake_input(
			g,
		); assist_active := car.driver_assist != .None; control_label := handbrake ? "HANDBRAKE" : assist_active ? vehicle_driver_assist_label(car.driver_assist) : fmt.tprintf("%s  HANDBRAKE", prompt_label(g, .Handbrake)); control_color := handbrake ? [4]u8{255, 144, 119, 255} : assist_active ? vehicle_driver_assist_indicator_color(car.driver_assist_strength) : [4]u8{145, 153, 162, 255}
		surface_label := vehicle_surface_blend_label(
			car.surface_blend,
		); surface_color := car.surface_blend < .20 ? [4]u8{173, 183, 192, 255} : car.surface_blend > .80 ? [4]u8{255, 190, 92, 255} : [4]u8{221, 187, 142, 255}
		vulkan_ui_rect(
			r,
			16,
			646,
			430,
			56,
			{18, 22, 25, 232},
		); vulkan_ui_outline(r, 16, 646, 430, 56, {83, 94, 105, 205}, 1)
		vk_text(
			r,
			30,
			655,
			fmt.tprintf(
				"%s  ·  %s %03d",
				strings.to_upper(CITY_CARS[g.driving_vehicle].model),
				vehicle_transmission_label(car, vehicle_tune(g.driving_vehicle)),
				int(vehicle_actual_speed(car) * 180),
			),
			{117, 229, 169, 255},
			.62,
		)
		vk_text(
			r,
			282,
			657,
			exit_label,
			exit_ready ? [4]u8{205, 207, 210, 255} : [4]u8{255, 190, 92, 255},
			.46,
		)
		vk_text(
			r,
			30,
			681,
			vehicle_traction_label(traction),
			traction_color,
			.42,
		); vulkan_ui_rect(r, 92, 687, 94, 5, {48, 55, 62, 255}); vulkan_ui_rect(r, 92, 687, 94 * slip, 5, traction_color)
		vk_text(
			r,
			210,
			681,
			surface_label,
			surface_color,
			.42,
		); vk_text(r, 292, 681, control_label, control_color, .36)
	}
	vk_draw_context_toast(r, g); vk_draw_tutorial_prompt(r, g); vk_draw_quest_tracker(r, g)
}

vk_draw_house_overlay :: proc(r: ^Vulkan_Backend, g: ^Game) {
	if g.editor_mode == .Build {vk_draw_build_overlay(r, g); return}
	if g.editor_mode ==
	   .Graph {vk_draw_graph_overlay(r, g); if graph_state.playtesting {vk_draw_graph_debugger(r, g); vk_button(r, graph_debugger_editor_rect(), "GAME", true)}; if graph_state.help_visible do vk_draw_graph_help(r); return}
	if editor_state.playtesting {vk_panel(r, 700, 646, 270, 48); vk_text(r, 716, 655, "PLAYTESTING FROM EDITOR", {117, 229, 169, 255}, .44); vk_text(r, 716, 674, "F10  RETURN TO BUILD MODE", {205, 207, 210, 255}, .32)}
	vk_draw_location_plaque(r, world_location_label(g)); vk_draw_time_chip(r, g)
	warning := action_warning_text(
		g,
	); if warning != "" {color := g.ap <= 2 ? [4]u8{255, 144, 119, 255} : [4]u8{255, 218, 112, 255}; width := f32(utf8_glyph_count(warning)) * COURIER_CELL_WIDTH * .54 + 30; vulkan_ui_rect(r, (WINDOW_WIDTH - width) * .5, 18, width, 32, {24, 27, 31, 238}); vulkan_ui_outline(r, (WINDOW_WIDTH - width) * .5, 18, width, 32, color, 1); vk_text(r, (WINDOW_WIDTH - width) * .5 + 15, 27, warning, color, .54)}
	vk_draw_house_glints(
		r,
		g,
	); vk_draw_case_sense_poi_ping(r, g); vk_draw_context_group(r, g); vk_draw_context_toast(r, g)
	if g.move_target_active {target_screen, visible := context_world_point_screen(g, {g.move_target_x, g.move_target_y}); if visible {vulkan_ui_outline(r, target_screen.x - 7, target_screen.y - 7, 14, 14, {255, 218, 112, 180}, 2); vulkan_ui_rect(r, target_screen.x - 2, target_screen.y - 2, 4, 4, {117, 229, 169, 255})}}
	vk_draw_shortcut_cluster(r, g); vk_draw_case_sense(r, g)
	vk_draw_quest_tracker(r, g)
}
