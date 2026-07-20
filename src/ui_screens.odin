package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:sync"
import "core:strings"
import "core:time"
import ui "zelda_engine:ui"

campaign_condition_label :: proc(kind:Campaign_Condition_Kind)->string {switch kind {case .Always:return "ALWAYS";case .Never:return "NEVER";case .All:return "ALL";case .Any:return "ANY";case .Not:return "NOT";case .Boolean_Equals:return "BOOLEAN";case .Integer_Compare:return "INTEGER";case .Enum_Equals:return "ENUM";case .Case_Started:return "CASE STARTED";case .Case_Completed:return "CASE COMPLETE";case .Case_Outcome:return "CASE OUTCOME"};return "CONDITION"}

vk_campaign_check_stroke :: proc(r:^Vulkan_Backend,a,b:Vec2,color:[4]u8,thickness:f32) {
	dx,dy:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dy*dy)));if length<=0 do return
	px,py:= -dy/length*thickness*.5,dx/length*thickness*.5
	a0,a1,b0,b1:=Vec2{a.x+px,a.y+py},Vec2{a.x-px,a.y-py},Vec2{b.x+px,b.y+py},Vec2{b.x-px,b.y-py}
	// UI triangles use clockwise screen-space winding.
	vulkan_ui_triangle(r,a0,b0,a1,color);vulkan_ui_triangle(r,a1,b0,b1,color)
}

vk_campaign_check_dot :: proc(r:^Vulkan_Backend,center:Vec2,radius:f32,color:[4]u8) {
	segments:=12
	for i in 0..<segments {
		a:=f32(i)*2*f32(math.PI)/f32(segments);b:=f32(i+1)*2*f32(math.PI)/f32(segments)
		// Reverse the perimeter order for clockwise screen-space winding.
		p0:=Vec2{center.x+f32(math.cos(f64(b)))*radius,center.y+f32(math.sin(f64(b)))*radius}
		p1:=Vec2{center.x+f32(math.cos(f64(a)))*radius,center.y+f32(math.sin(f64(a)))*radius}
		vulkan_ui_triangle(r,center,p0,p1,color)
	}
}

vk_campaign_checkmark :: proc(r:^Vulkan_Backend,a,joint,b:Vec2,color:[4]u8) {
	thickness:f32=2.5
	// Shared solid discs make the two segments one continuous stroke and give
	// the mark round endpoints without adding translucent geometry.
	vk_campaign_check_stroke(r,a,joint,color,thickness);vk_campaign_check_stroke(r,joint,b,color,thickness)
	vk_campaign_check_dot(r,a,thickness*.5,color);vk_campaign_check_dot(r,joint,thickness*.5,color);vk_campaign_check_dot(r,b,thickness*.5,color)
}

vk_campaign_checkbox :: proc(r:^Vulkan_Backend,box:Rect,label:string,checked:bool) {
	vk_button(r,box,fmt.tprintf("      %s",label))
	check:=Rect{box.x+12,box.y+(box.h-20)*.5,20,20}
	vulkan_ui_rect(r,check.x,check.y,check.w,check.h,{12,16,22,255})
	vulkan_ui_outline(r,check.x,check.y,check.w,check.h,checked?[4]u8{255,211,92,255}:[4]u8{148,155,168,255},2)
	if checked {
		ink:=[4]u8{255,211,92,255}
		vk_campaign_checkmark(r,{check.x+4,check.y+10},{check.x+8,check.y+14},{check.x+16,check.y+5},ink)
	}
}

vk_draw_campaign_workspace :: proc(r:^Vulkan_Backend,g:^Game) {
	doc:=&campaign_workspace.draft
	vulkan_ui_rect(r,0,0,1200,720,{7,10,15,255});vk_text(r,18,18,"CAMPAIGN WORKSPACE",{255,211,92,255},1.35);vk_text(r,850,22,campaign_workspace.dirty?"UNSAVED CHANGES":"SAVED",campaign_workspace.dirty?[4]u8{255,144,119,255}:[4]u8{117,229,169,255},.62)
	tabs:=[7]string{"OVERVIEW","CASES","VARIABLES","CONDITIONS","EFFECTS","SIMULATION","DIAGNOSTICS"};vk_tab_bar(r,{18,60,1140,46});for label,i in tabs do vk_tab(r,{18+f32(i)*164,64,156,38},label,campaign_workspace.tab==Campaign_Workspace_Tab(i))
	switch campaign_workspace.tab {
	case .Overview:vk_text(r,40,108,"CAMPAIGN DETAILS",UI_ACCENT,.64);vk_button(r,{40,120,500,34},fmt.tprintf("FORMAT  %s",doc.version));vk_button(r,{550,120,500,34},fmt.tprintf("ID  %s",doc.id));vk_button(r,{40,164,500,34},fmt.tprintf("TITLE  %s",doc.title));vk_button(r,{550,164,500,34},fmt.tprintf("CREATOR  %s",doc.creator));vk_button(r,{40,208,500,34},fmt.tprintf("VERSION  %s",doc.content_version));vk_button(r,{550,208,500,34},fmt.tprintf("THUMBNAIL  %s",doc.thumbnail));vk_button(r,{40,252,1010,120},"EDIT DESCRIPTION");vk_text_wrapped(r,60,282,970,doc.description,{205,207,210,255},.66);vk_button(r,{40,390,150,36},"NEW");vk_button(r,{200,390,150,36},"OPEN");vk_button(r,{360,390,150,36},"DUPLICATE");vk_button(r,{520,390,150,36},"SAVE AS");vk_button(r,{680,390,150,36},"MOVE");vk_danger_button(r,{840,390,190,36},campaign_workspace.delete_confirm?"CONFIRM DELETE":"DELETE")
	case .Cases:vk_text(r,30,106,"CASE ORDER",UI_ACCENT,.62);vk_text(r,620,106,"SELECTED CASE",UI_ACCENT,.62);vk_primary_button(r,{30,108,120,32},"+ ADD CASE");vk_button(r,{158,108,80,32},"UP");vk_button(r,{246,108,80,32},"DOWN");vk_danger_button(r,{334,108,110,32},"REMOVE");for item,i in doc.cases do vk_button(r,{30,148+f32(i)*48,520,40},fmt.tprintf("%d  %s",i+1,strings.to_upper(item.title)),i==campaign_workspace.selected_case);if len(doc.cases)==0 do vk_text(r,30,170,"NO CASES YET  ·  ADD A STORY OR MYSTERY TO BEGIN",UI_MUTED,.66);i:=campaign_workspace.selected_case;if i>=0&&i<len(doc.cases) {item:=doc.cases[i];vk_button(r,{620,112,250,34},fmt.tprintf("TITLE  %s",item.title));vk_button(r,{880,112,250,34},fmt.tprintf("ID  %s",item.id));vk_button(r,{620,160,250,38},item.required?"REQUIRED":"OPTIONAL");vk_button(r,{880,160,250,38},fmt.tprintf("VERSION  %s",item.case_content_version));vk_button(r,{620,208,250,38},fmt.tprintf("REPLAY  %v",item.replay_mode));vk_button(r,{620,256,250,38},fmt.tprintf("HISTORY  %v",item.invalid_result_policy));vk_button(r,{620,304,250,38},fmt.tprintf("LOCKED  %v",item.unavailable_presentation));vk_text(r,620,348,"SOURCE DOCUMENTS",UI_MUTED,.54);vk_button(r,{620,358,510,30},fmt.tprintf("STORY  %s",item.story_path));vk_button(r,{620,400,510,30},fmt.tprintf("LEVEL  %s",item.level_path));vk_button(r,{620,442,510,50},"EDIT LOCKED MESSAGE");vk_primary_button(r,{620,504,165,36},"OPEN SOURCE");vk_button(r,{795,504,165,36},"NEW GENERAL");vk_button(r,{970,504,165,36},"NEW MYSTERY")}
	case .Variables:vk_text(r,30,108,"CAMPAIGN STATE",UI_ACCENT,.62);vk_text(r,620,108,"SELECTED VARIABLE",UI_ACCENT,.62);vk_primary_button(r,{30,120,150,38},"+ VARIABLE");vk_danger_button(r,{190,120,100,38},"REMOVE");vk_button(r,{300,120,90,38},"UP");vk_button(r,{400,120,90,38},"DOWN");for variable,i in doc.variables do vk_button(r,{30,170+f32(i)*46,480,38},fmt.tprintf("%s  ·  %v",strings.to_upper(variable.display_name),variable.kind),i==campaign_workspace.selected_variable);if len(doc.variables)==0 {vk_text(r,30,184,"NO CAMPAIGN VARIABLES",UI_INK,.70);vk_text(r,30,214,"Add shared state only when progression crosses case boundaries.",UI_MUTED,.62)};i:=campaign_workspace.selected_variable;if i>=0&&i<len(doc.variables) {variable:=doc.variables[i];vk_text(r,620,130,variable.id,{152,196,214,255},.72);vk_button(r,{620,170,260,38},fmt.tprintf("TYPE  %v",variable.kind));if variable.kind==.Boolean do vk_campaign_checkbox(r,{620,218,260,38},"DEFAULT",variable.default_boolean);else if variable.kind==.Integer {vk_button(r,{620,218,120,38},"- 1");vk_button(r,{750,218,120,38},"+ 1");vk_text(r,620,270,fmt.tprintf("DEFAULT  %d",variable.default_integer),{248,247,242,255},.72)}else {vk_text(r,620,230,fmt.tprintf("DEFAULT  %s",variable.default_enum),{248,247,242,255},.72);vk_primary_button(r,{620,266,120,34},"+ VALUE");vk_danger_button(r,{750,266,120,34},"REMOVE");for value,j in variable.enum_values[:variable.enum_value_count] do vk_button(r,{620,310+f32(j)*38,260,32},value,j==campaign_workspace.selected_enum_value)}}
	case .Conditions:vk_text(r,30,108,"CHOOSE CASE",{255,211,92,255},.68);for item,i in doc.cases do vk_button(r,{30,120+f32(i)*46,440,38},strings.to_upper(item.title),i==campaign_workspace.selected_case);labels:=[11]string{"ALWAYS","NEVER","WRAP ALL","WRAP ANY","WRAP NOT","BOOLEAN","INTEGER","ENUM","CASE STARTED","CASE COMPLETE","CASE OUTCOME"};for label,i in labels do vk_button(r,{500+f32(i%3)*205,120+f32(i/3)*44,195,34},label);controls:=[6]string{"PREV","NEXT","UP","DOWN","REMOVE","RESET"};for label,i in controls do vk_button(r,{500+f32(i)*100,304,i<2?82:92,28},label);vk_button(r,{1000,338,112,28},"+ CHILD");node_index:=campaign_workspace.selected_condition;if node_index>=0&&node_index<len(doc.conditions) {node:=doc.conditions[node_index];parent:=campaign_workspace_condition_parent(doc,node_index);vk_text(r,520,344,fmt.tprintf("EDITING %s · NODE %d · PARENT %d",campaign_condition_label(node.kind),node_index,parent),{255,211,92,255},.62);if node.variable_id!="" do vk_button(r,{520,370,410,38},fmt.tprintf("VARIABLE  %s",node.variable_id));if node.kind==.Boolean_Equals do vk_campaign_checkbox(r,{520,418,200,38},"EQUALS TRUE",node.boolean_value);if node.kind==.Integer_Compare {vk_button(r,{520,418,200,38},fmt.tprintf("%v",node.integer_comparison));vk_button(r,{730,418,96,38},"- 1");vk_button(r,{836,418,96,38},"+ 1");vk_text(r,946,430,fmt.tprintf("%d",node.integer_value),{248,247,242,255},.62)};if node.kind==.Enum_Equals do vk_button(r,{520,418,410,38},fmt.tprintf("EQUALS  %s",node.enum_value));if node.case_id!="" do vk_button(r,{520,466,410,38},fmt.tprintf("CASE  %s",node.case_id));if node.kind==.Case_Outcome do vk_button(r,{520,514,410,38},fmt.tprintf("OUTCOME  %v",node.outcome))}
	case .Effects:vk_text(r,30,108,"CASE OUTCOME EFFECTS",{255,211,92,255},.72);for item,i in doc.cases do vk_button(r,{30,120+f32(i)*42,420,34},strings.to_upper(item.title),i==campaign_workspace.selected_case);vk_button(r,{500,120,220,36},fmt.tprintf("OUTCOME  %v",Outcome(campaign_workspace.selected_outcome)));vk_button(r,{730,120,120,36},"+ EFFECT");vk_button(r,{860,120,100,36},"REMOVE");vk_button(r,{970,120,70,36},"UP");vk_button(r,{1050,120,70,36},"DOWN");if campaign_workspace.selected_case>=0&&campaign_workspace.selected_case<len(doc.cases) {first,count:=campaign_effect_range(doc.cases[campaign_workspace.selected_case],Outcome(clamp(campaign_workspace.selected_outcome,0,len(Outcome)-1)));for offset in 0..<count {effect_index:=first+offset;effect:=doc.effects[effect_index];vk_button(r,{500,164+f32(offset)*34,450,28},fmt.tprintf("%d · %v · %s",offset+1,effect.kind,effect.variable_id),effect_index==campaign_workspace.selected_effect)}};if campaign_workspace.selected_effect>=0&&campaign_workspace.selected_effect<len(doc.effects) {effect:=doc.effects[campaign_workspace.selected_effect];vk_button(r,{500,500,450,38},fmt.tprintf("TARGET  %s",effect.variable_id));if effect.kind==.Set_Boolean do vk_campaign_checkbox(r,{500,548,220,38},"SET TRUE",effect.boolean_value);else if effect.kind==.Set_Integer||effect.kind==.Add_Integer {vk_button(r,{500,548,100,38},"- 1");vk_button(r,{610,548,100,38},"+ 1");vk_button(r,{720,548,230,38},fmt.tprintf("%v  %d",effect.kind,effect.integer_value))}else do vk_button(r,{500,548,450,38},fmt.tprintf("SET  %s",effect.enum_value))};vk_button(r,{500,600,150,34},"MAPPING UP");vk_button(r,{660,600,150,34},"MAPPING DOWN");vk_button(r,{820,600,190,34},"REMOVE MAPPING")
	case .Simulation:vk_text(r,30,108,"CREATOR-ONLY STATE SIMULATION",{255,211,92,255},.76);if len(doc.variables)>0 {v:=doc.variables[clamp(campaign_workspace.selected_variable,0,len(doc.variables)-1)];state:=campaign_workspace.simulated.values[clamp(campaign_workspace.selected_variable,0,len(doc.variables)-1)];vk_button(r,{780,108,180,34},fmt.tprintf("VARIABLE %s",v.id));if v.kind==.Integer {vk_button(r,{970,108,82,34},"- 1");vk_button(r,{1060,108,82,34},"+ 1");vk_text(r,1148,119,fmt.tprintf("%d",state.integer_value),{248,247,242,255},.52)}else {value:=v.kind==.Boolean?fmt.tprintf("%t",state.boolean_value):state.enum_value;vk_button(r,{970,108,180,34},fmt.tprintf("VALUE %s",value))}};for item,i in doc.cases {result:=campaign_workspace.simulated.results[i];unlocked:=campaign_case_unlocked(doc,&campaign_workspace.simulated,i);status:=result.present?fmt.tprintf("COMPLETED · %v",result.outcome):result.started?"STARTED · INCOMPLETE":"NOT STARTED";vk_button(r,{30,130+f32(i)*48,720,38},fmt.tprintf("%s  ·  %s",item.title,status),i==campaign_workspace.selected_case);trace:=campaign_evaluate_condition(doc,&campaign_workspace.simulated,item.condition_root);vk_text(r,760,142+f32(i)*48,fmt.tprintf("%s · %s",unlocked?"AVAILABLE":"LOCKED",trace.message),unlocked?[4]u8{117,229,169,255}:[4]u8{255,144,119,255},.48)};if campaign_workspace.simulation_trace!="" do vk_text_wrapped(r,760,550,400,campaign_workspace.simulation_trace,{152,196,214,255},.44);vk_button(r,{30,610,150,34},"START");vk_button(r,{190,610,190,34},"COMPLETE / REPLAY");vk_button(r,{390,610,150,34},"CLEAR");vk_button(r,{550,610,190,34},"LAUNCH CASE")
	case .Diagnostics:vk_text(r,30,108,"CAMPAIGN VALIDATION",UI_ACCENT,.68);vk_primary_button(r,{30,130,240,38},"RUN VALIDATION");color:=campaign_workspace.diagnostics.ok?UI_SUCCESS:UI_DANGER;if campaign_workspace.diagnostics.ok {vulkan_ui_rect(r,30,180,1120,42,UI_SURFACE_RAISED);vulkan_ui_outline(r,30,180,1120,42,UI_SUCCESS,2);vk_text(r,48,190,fmt.tprintf("✓  %s",campaign_workspace.diagnostics.message),UI_SUCCESS,.68)}else do vk_danger_button(r,{30,180,1120,42},fmt.tprintf("OPEN ISSUE  ·  %s",campaign_workspace.diagnostics.message));vk_text(r,30,240,"DEPENDENCY MAP  ·  SELECT A CASE TO OPEN ITS CONDITION",UI_ACCENT,.68);for item,i in doc.cases {trace:=campaign_evaluate_condition(doc,&campaign_workspace.simulated,item.condition_root);vk_button(r,{40,270+f32(i)*38,1080,32},fmt.tprintf("%s  ←  %s  [%s]",item.id,trace.message,trace.value?"OPEN":"LOCKED"))}
	}
	vulkan_ui_rect(r,0,654,1200,66,UI_SURFACE);vk_button(r,{18,666,150,38},"CLOSE");vk_primary_button(r,{178,666,150,38},"SAVE");vk_button(r,{338,666,150,38},"VALIDATE");vk_button(r,{498,666,100,38},"UNDO");vk_button(r,{608,666,100,38},"REDO");if campaign_workspace.feedback!="" do vk_text(r,720,677,campaign_workspace.feedback,UI_INFO,.66)
	if campaign_workspace.text_field!=.None {vulkan_ui_rect(r,380,585,660,70,{8,12,18,250});vulkan_ui_outline(r,380,585,660,70,{255,211,92,255},1);vk_text(r,400,592,fmt.tprintf("EDIT %v — ENTER TO APPLY · ESC TO CANCEL",campaign_workspace.text_field),{255,211,92,255},.48);vulkan_ui_rect(r,400,610,620,34,{238,233,220,255});vk_editor_text(r,408,620,string(campaign_workspace.text_buffer[:campaign_workspace.text_count]),{52,46,40,255},.52)}
	if campaign_workspace.exit_confirm {vulkan_ui_rect(r,0,0,1200,720,{4,7,10,200});vulkan_ui_rect(r,280,242,640,254,{24,31,38,255});vulkan_ui_outline(r,280,242,640,254,{255,211,92,255},3);vk_text(r,320,274,"UNSAVED CAMPAIGN CHANGES",{255,218,112,255},.82);vk_text(r,320,314,"Save your changes before leaving the campaign editor?",{235,237,238,255},.60);vk_text(r,320,344,"Discarding returns to the last saved campaign.",{170,218,228,255},.60);vk_button(r,{320,390,170,42},"SAVE & EXIT",true);vk_button(r,{505,390,170,42},"DISCARD");vk_button(r,{690,390,170,42},"CANCEL");vk_text(r,320,478,"ESC RETURNS TO THE CAMPAIGN EDITOR",{205,207,210,255},.60)}
}

vk_heading :: proc(r:^Vulkan_Backend,title,subtitle:string) {
	vk_text(r,32,18,title,{255,211,92,255},1.45);vk_text(r,32,48,subtitle,{205,207,210,255},1.05)
	vulkan_ui_rect(r,24,76,1152,3,{255,211,92,255})
}

// A deterministic visual inventory for developing and reviewing the shared
// theme. Knolling the components onto one board makes palette, contrast,
// spacing, and state regressions visible in a single capture.
vk_draw_theme_knoll :: proc(r:^Vulkan_Backend,g:^Game) {
	vulkan_ui_rect(r,0,0,WINDOW_WIDTH,WINDOW_HEIGHT,UI_CANVAS)
	material_texture:=vulkan_ui_art_texture(r,.Theme_Materials);if material_texture>=0 do vulkan_ui_quad(r,0,0,WINDOW_WIDTH,WINDOW_HEIGHT,{72,67,58,96},material_texture,{0,0},{.5,.5},true)
	vk_text(r,32,18,"WESTHAVEN CONSTABULARY",UI_ACCENT,.64);vk_text(r,32,40,"INTERFACE EVIDENCE BOARD",UI_INK_STRONG,1.42);vk_text(r,32,70,"CASE UI-824  ·  Shared player + creator component reference",UI_MUTED,.70);vulkan_ui_rect(r,32,96,1136,1,UI_ACCENT_DARK);vk_text(r,1022,70,"FILED  8:47 PM",UI_ACCENT,.60)

	vk_panel(r,32,116,340,246);vk_text(r,52,136,"01 / MATERIALS",UI_ACCENT,.68)
	swatches:=[8][4]u8{UI_CANVAS,UI_SURFACE,UI_SURFACE_RAISED,UI_SURFACE_HOVER,UI_ACCENT,UI_INFO,UI_SUCCESS,UI_DANGER};labels:=[8]string{"CANVAS","SURFACE","RAISED","HOVER","ACCENT","INFO","SUCCESS","DANGER"}
	for color,i in swatches {column:=i%2;row:=i/2;x:=f32(52+column*152);y:=f32(170+row*42);vulkan_ui_rect(r,x,y,28,28,color);vulkan_ui_outline(r,x,y,28,28,UI_BORDER_STRONG,1);vk_text(r,x+40,y+6,labels[i],i<4?UI_MUTED:UI_INK,.64)}

	vk_panel(r,390,116,778,246);vk_text(r,412,136,"02 / TYPE + DOCUMENTS",UI_ACCENT,.68)
	vk_text(r,412,172,"THE TORN APPOINTMENT",UI_INK_STRONG,1.26);vk_text(r,412,210,"Evidence heading",UI_INK,.94);vk_text(r,412,244,"Body copy remains quiet over the scene.",UI_INK,.78);vk_text(r,412,276,"VALE HOUSE  ·  STUDY  ·  8:24 PM",UI_MUTED,.66)
	if material_texture>=0 do vulkan_ui_quad(r,842,158,288,150,{246,230,192,255},material_texture,{0,.5},{.5,1},true);vulkan_ui_outline(r,842,158,288,150,UI_ACCENT_DARK,1);vk_text(r,862,176,"EVIDENCE  07-B",{12,11,9,255},.64);vulkan_ui_rect(r,862,201,248,2,{48,37,23,220});vk_text(r,862,216,"STOPPED WATCH",{8,8,7,255},.88);vk_text(r,862,250,"Recovered from Edgar Vale",{18,16,12,255},.60);vk_text(r,862,276,"TIME FIXED:  8:24",{80,18,16,255},.66)

	vk_panel(r,32,382,726,306);vk_text(r,52,402,"CONTROLS + STATES",UI_ACCENT,.76)
	vk_text(r,52,438,"DEFAULT",UI_MUTED_DIM,.66);vk_button(r,{52,458,220,42},"CONTINUE");vk_text(r,300,438,"KEYBOARD FOCUS",UI_MUTED_DIM,.66);saved_focus:=vk_focused_button;vk_focused_button=button_id({300,458,220,42});vk_button(r,{300,458,220,42},"EXAMINE");vk_focused_button=saved_focus;vk_text(r,548,438,"CURRENT CHOICE",UI_MUTED_DIM,.66);vk_button(r,{548,458,180,42},"SELECTED",true)
	vk_text(r,52,526,"COMPACT / CREATOR",UI_MUTED_DIM,.66);vk_tab_bar_surface(r,{52,544,258,40});vk_tab_surface(r,{52,548,124,32},"MATERIALS",false,false);vk_tab_surface(r,{186,548,124,32},"OBJECTS",true,false);vk_editor_cycle_button(r,{320,548,42,32},-1);vk_editor_cycle_button(r,{370,548,42,32},1)
	vk_dialogue_choice_surface(r,{52,606,676,56},false);vulkan_ui_rect(r,52,606,5,56,UI_INFO);vk_text(r,72,615,"CHALLENGE  ·  Present the stopped watch",UI_INFO,.76);vk_text(r,72,639,"Free action  ·  evidence available",UI_MUTED,.66)

	vk_panel(r,778,382,390,306);vk_text(r,798,402,"STATUS + SURFACES",UI_ACCENT,.76)
	status_colors:=[4][4]u8{UI_INFO,UI_SUCCESS,UI_WARNING,UI_DANGER};status_labels:=[4]string{"OBSERVATION RECORDED","DEDUCTION SUPPORTED","ACTION REQUIRED","APPROACH CLOSED"}
	for color,i in status_colors {y:=f32(440+i*48);box:=Rect{798,y,350,36};vk_dialogue_status_surface(r,box,color);markers:=[4]string{"i","✓","!","×"};vk_text(r,box.x+48,box.y+8,fmt.tprintf("%s  %s",markers[i],status_labels[i]),color,.64)}
	vulkan_ui_rect(r,798,640,350,28,UI_SURFACE_RAISED);vulkan_ui_outline(r,798,640,350,28,UI_BORDER,1);vulkan_ui_rect(r,798,640,230,28,UI_ACCENT);vk_text(r,810,647,"THEME COVERAGE  66%",UI_CANVAS,.56)
}

vk_draw_theme_knoll_details :: proc(r:^Vulkan_Backend,g:^Game) {
	vulkan_ui_rect(r,0,0,WINDOW_WIDTH,WINDOW_HEIGHT,UI_CANVAS);material_texture:=vulkan_ui_art_texture(r,.Theme_Materials);if material_texture>=0 do vulkan_ui_quad(r,0,0,WINDOW_WIDTH,WINDOW_HEIGHT,{72,67,58,96},material_texture,{0,0},{.5,.5},true)
	vk_text(r,32,16,"WESTHAVEN CONSTABULARY",UI_ACCENT,UI_CONSOLE_CAPTION_SCALE);vk_text(r,32,40,"INPUT + TYPE SPECIMEN",UI_INK_STRONG,1.42);vk_text(r,32,70,"CASE UI-824  ·  Full component inventory  ·  PAGE 02 / 02",UI_MUTED,UI_CONSOLE_LABEL_SCALE);vulkan_ui_rect(r,32,96,1136,1,UI_ACCENT_DARK)

	// Input inventory: production controls plus the field primitives that are
	// composed directly by editor screens.
	vk_panel(r,32,116,548,572);vk_text(r,54,134,"03 / INPUT INVENTORY",UI_ACCENT,.80)
	vk_text(r,54,172,"BUTTONS",UI_MUTED,UI_CONSOLE_CAPTION_SCALE);vk_button(r,{54,194,148,40},"DEFAULT");saved_focus:=vk_focused_button;vk_focused_button=button_id({214,194,148,40});vk_button(r,{214,194,148,40},"FOCUSED");vk_focused_button=saved_focus;vk_button(r,{374,194,148,40},"SELECTED",true)
	vk_text(r,54,248,"TABS + PAGING",UI_MUTED,UI_CONSOLE_CAPTION_SCALE);vk_tab_bar_surface(r,{54,268,340,40});vk_tab_surface(r,{54,272,108,32},"EVIDENCE",true,false);vk_tab_surface(r,{170,272,108,32},"PEOPLE",false,false);vk_tab_surface(r,{286,272,108,32},"HISTORY",false,false);vk_editor_cycle_button(r,{430,272,42,32},-1);vk_editor_cycle_button(r,{480,272,42,32},1)
	vk_text(r,54,318,"TEXT FIELD",UI_MUTED,UI_CONSOLE_CAPTION_SCALE);vulkan_ui_rect(r,54,342,468,40,{224,211,181,255});vulkan_ui_outline(r,54,342,468,40,UI_ACCENT_DARK,2);vk_text(r,68,351,"Search case notes…",{28,25,20,255},UI_CONSOLE_LABEL_SCALE);vulkan_ui_rect(r,246,351,3,22,{99,27,25,255})
	vk_text(r,54,396,"CHECKBOXES",UI_MUTED,UI_CONSOLE_CAPTION_SCALE);vk_campaign_checkbox(r,{54,416,214,38},"CHECKED",true);vk_campaign_checkbox(r,{282,416,240,38},"UNCHECKED",false)
	vk_text(r,54,464,"RANGE",UI_MUTED,UI_CONSOLE_CAPTION_SCALE);vulkan_ui_rect(r,54,494,468,8,UI_SURFACE_RAISED);vulkan_ui_rect(r,54,494,294,8,UI_ACCENT);vulkan_ui_rect(r,340,486,20,24,UI_INK_STRONG);vulkan_ui_outline(r,340,486,20,24,UI_ACCENT_DARK,2);vk_text(r,458,476,"63%",UI_INK,UI_CONSOLE_LABEL_SCALE)
	vk_text(r,54,526,"CHOICE + STATUS",UI_MUTED,UI_CONSOLE_CAPTION_SCALE);choice:=Rect{54,552,468,54};vk_dialogue_choice_surface(r,choice,true);vk_text(r,74,561,"◇  Examine the stopped watch",UI_INK,.76);vk_text(r,74,584,"OBSERVATION  ·  FREE ACTION",UI_INFO,UI_CONSOLE_CAPTION_SCALE)
	vulkan_ui_rect(r,54,624,150,34,UI_SURFACE_RAISED);vulkan_ui_outline(r,54,624,150,34,UI_BORDER_STRONG,2);vk_text(r,70,630,"DISABLED",UI_MUTED,UI_CONSOLE_CAPTION_SCALE);vulkan_ui_rect(r,216,624,146,34,UI_SUCCESS);vk_text(r,232,630,"CONFIRM",UI_CANVAS,UI_CONSOLE_CAPTION_SCALE);vulkan_ui_rect(r,374,624,148,34,UI_DANGER);vk_text(r,386,630,"DESTRUCTIVE",UI_INK_STRONG,.62)

	// Type inventory demonstrates hierarchy, prose, metadata, semantic emphasis,
	// and rich inline spans under the same physical-material treatment.
	vk_panel(r,600,116,568,572);vk_text(r,622,134,"04 / TYPOGRAPHY + TEXT STYLING",UI_ACCENT,.80)
	vk_text(r,622,172,"DISPLAY / CASE TITLE",UI_INK_STRONG,1.48);vk_text(r,622,216,"Heading / Evidence summary",UI_INK,1.08);vk_text(r,622,254,"Subheading / Witness statement",UI_INK,.90)
	vk_text(r,622,292,"BODY",UI_MUTED,UI_CONSOLE_CAPTION_SCALE);_=vk_text_wrapped(r,622,316,510,"Blood and bronze in the crushed watch tie 8:24 to the attack. The torn appointment places Miriam in the study minutes earlier.",UI_INK,UI_CONSOLE_BODY_SCALE,6)
	vk_text(r,622,398,"LABEL + METADATA",UI_MUTED,UI_CONSOLE_CAPTION_SCALE);vk_text(r,622,424,"VALE HOUSE  /  STUDY",UI_ACCENT,UI_CONSOLE_LABEL_SCALE);vk_text(r,868,424,"RECORDED  8:47 PM",UI_MUTED,UI_CONSOLE_CAPTION_SCALE)
	vk_text(r,622,466,"SEMANTIC EMPHASIS",UI_MUTED,UI_CONSOLE_CAPTION_SCALE);_=vk_rich_text(r,622,492,[]Text_Span{{"Evidence ",text_effect_default(UI_INK,.76)},{"supports",text_effect_default(UI_SUCCESS,.76)},{" the timeline, but ",text_effect_default(UI_INK,.76)},{"contradicts",text_effect_default(UI_DANGER,.76)},{" the witness.",text_effect_default(UI_INK,.76)}},g.animation_time)
	vulkan_ui_rect(r,622,530,510,2,UI_BORDER_STRONG);vk_text(r,622,546,"CAPTION",UI_MUTED,UI_CONSOLE_CAPTION_SCALE);vk_text(r,726,546,"Source: stopped watch · Evidence 07-B",UI_MUTED,UI_CONSOLE_CAPTION_SCALE)
	if material_texture>=0 do vulkan_ui_quad(r,622,580,510,78,{246,230,192,255},material_texture,{0,.5},{.5,1},true);vulkan_ui_outline(r,622,580,510,78,UI_ACCENT_DARK,1);vk_text(r,640,590,"TYPEWRITTEN CASE NOTE",{10,10,8,255},.70);vk_text(r,640,616,"Time of death cannot follow the stopped watch.",{7,7,6,255},.80);vk_text(r,956,636,"— DET. 12",{76,16,15,255},.64)
}

vk_editor_preview_callout :: proc(r:^Vulkan_Backend,g:^Game,message:string,state:Placement_State) {
	if message==""||state==.Valid||!editor_viewport_contains(g.input.mouse_pos,g.build_tool) do return
	label:=strings.to_upper(message);if len(label)>58 do label=label[:58]
	color:=state==.Blocked?[4]u8{255,144,119,255}:[4]u8{255,211,92,255}
	width:=max(f32(220),f32(utf8_glyph_count(label))*7+24);x:=clamp(g.input.mouse_pos.x+18,f32(82),f32(1188)-width);y:=clamp(g.input.mouse_pos.y-44,f32(112),f32(650))
	vulkan_ui_rect(r,x,y,width,32,{10,14,18,242});vulkan_ui_outline(r,x,y,width,32,color,2);vk_editor_text(r,x+12,y+9,label,color,.60)
}

vk_draw_introduction :: proc(r:^Vulkan_Backend,g:^Game) {
	if g.introduction_step==0 {
		vk_heading(r,"THE CAST",g.story_project!=nil?g.story_project.title:"")
		vk_text(r,32,88,"Question the household. Examine the scene.",{205,207,210,255},.78)
		if g.story_project!=nil do for character,i in g.story_project.entities {
			if character.kind!="character" do continue
			if i>=4 do break
			column:=i%2;row:=i/2;x:=f32(105+column*505);y:=f32(125+row*220)
			vk_panel(r,x,y,485,195)
			vk_art_fit(r,portrait_art(character.id),x+18,y+18,125,155)
			vk_text(r,x+165,y+22,strings.to_upper(character.display_name),{255,211,92,255},1.0)
			role:=character.tag_count>0?character.tags[0]:"character";vk_text(r,x+165,y+52,strings.to_upper(role),{155,201,255,255},.6)
			_=vk_text_wrapped(r,x+165,y+80,290,character.description,{248,247,242,255},.58,4)
		}
		vk_button(r,{410,625,380,58},"BEGIN THE MYSTERY",true)
		return
	}
	vk_heading(r,"VALE HOUSE","Rain, 8:47 p.m.")
	vk_panel(r,135,105,930,475)
	// An in-world summons establishes only why the investigator is here. It does
	// not hand over a timeline, suspect, or contradiction before play begins.
	vulkan_ui_rect(r,205,175,310,300,{218,205,174,255});vulkan_ui_outline(r,205,175,310,300,{105,82,57,255},3)
	vk_text(r,245,210,"VALE HOUSE",{68,53,42,255},1.15);vk_text(r,245,243,"TELEPHONE MESSAGE",{105,82,57,255},.62)
	_=vk_text_wrapped(r,245,300,230,g.story_project!=nil?g.story_project.description:"",{68,53,42,255},.78,7)
	_=vk_text_wrapped(r,590,205,360,"Rain ticks against the dark windows. Dinner has gone cold. No one from the household comes to meet you at the door.",{248,247,242,255},1.05,7)
	vk_text(r,590,390,"Look. Listen. Touch what seems wrong.",{155,201,255,255},.72)
	vk_button(r,{410,625,380,58},"ENTER VALE HOUSE",true)
}

vk_draw_clock_ticks :: proc(r:^Vulkan_Backend,g:^Game) {
	// The twelve actions read as slices of the stopped watch instead of a ruler.
	payload:=mystery_game_payload(g);total:=payload!=nil?payload.action_budget:0;cx,cy:=f32(70),f32(584);face_radius:=f32(32)
	// A dark dial underneath the generated brass case prevents the world from
	// showing through the small inter-slice gaps.
	for i in 0..<24 {a0:=f32(i)*2*f32(math.PI)/24;a1:=f32(i+1)*2*f32(math.PI)/24;p0:=Vec2{cx+f32(math.cos(f64(a0)))*face_radius,cy+f32(math.sin(f64(a0)))*face_radius};p1:=Vec2{cx+f32(math.cos(f64(a1)))*face_radius,cy+f32(math.sin(f64(a1)))*face_radius};vulkan_ui_triangle(r,{cx,cy},p0,p1,{25,26,28,245})}
	// The generated enamel face supplies the aged surface and engraved twelve-way
	// division; translucent state wedges let that material continue to show.
	if r.watch_face_texture>=0 do vulkan_ui_quad(r,cx-35,cy-35,70,70,{255,255,255,255},r.watch_face_texture,{}, {1,1},true)
	for i in 0..<total {
		gap:=f32(.025);a0:=-f32(math.PI)/2+f32(i)*2*f32(math.PI)/f32(total)+gap;a1:=-f32(math.PI)/2+f32(i+1)*2*f32(math.PI)/f32(total)-gap
		p0:=Vec2{cx+f32(math.cos(f64(a0)))*face_radius,cy+f32(math.sin(f64(a0)))*face_radius};p1:=Vec2{cx+f32(math.cos(f64(a1)))*face_radius,cy+f32(math.sin(f64(a1)))*face_radius}
		active:=i<g.ap;color:=active?[4]u8{255,218,112,95}:[4]u8{30,31,34,185};if active&&g.ap<=2 do color={255,144,119,125}
		vulkan_ui_triangle(r,{cx,cy},p0,p1,color)
	}
	// The authored frame supplies the patinated case, crown, lugs, and leather.
	if r.watch_frame_texture>=0 do vulkan_ui_quad(r,cx-60,cy-60,120,120,{255,255,255,255},r.watch_frame_texture,{}, {1,1},true)
	vulkan_ui_rect(r,cx-3,cy-3,6,6,{248,247,242,255})
	vk_text(r,138,563,g.ap==1?"FINAL SLICE":fmt.tprintf("%d / %d",g.ap,total),g.ap<=2?[4]u8{255,144,119,255}:[4]u8{255,218,112,255},1)
	vk_text(r,138,589,"TIME REMAINING",{205,207,210,255},.72)
}

context_status_color :: proc(status:Context_Status)->[4]u8 {switch status {case .Complete:return {117,229,169,255};case .Locked,.No_Power,.Obstructed,.Unavailable:return {255,144,119,255};case .Available:return {255,218,112,255}};return {255,218,112,255}}

vk_draw_time_chip :: proc(r:^Vulkan_Backend,g:^Game) {
	x,y:=f32(1042),f32(16);vulkan_ui_rect(r,x+3,y+4,140,48,{5,7,10,85});vulkan_ui_rect(r,x,y,140,48,{19,22,27,232});vulkan_ui_outline(r,x,y,140,48,{139,107,55,220},1)
	if r.watch_face_texture>=0 do vulkan_ui_quad(r,x+8,y+4,40,40,{255,255,255,255},r.watch_face_texture,{}, {1,1},true)
	payload:=mystery_game_payload(g);total:=payload!=nil?payload.action_budget:0;color:=g.ap<=2?[4]u8{255,144,119,255}:[4]u8{255,218,112,255};vk_text(r,x+55,y+7,fmt.tprintf("%d / %d",g.ap,total),color,.82);vk_text(r,x+55,y+27,"TICKS LEFT",{205,207,210,255},.48)
}

vk_draw_location_plaque :: proc(r:^Vulkan_Backend,title:string) {
	w:=max(f32(190),f32(utf8_glyph_count(title))*COURIER_CELL_WIDTH*.72+34);vulkan_ui_rect(r,19,20,w,35,{4,6,9,85});vulkan_ui_rect(r,16,16,w,35,{22,25,30,235});vulkan_ui_outline(r,16,16,w,35,{139,107,55,215},1);vulkan_ui_rect(r,16,16,5,35,{255,218,112,255});vk_text(r,31,25,strings.to_upper(title),{248,247,242,255},.72)
}

context_bubble_visible :: proc(g:^Game,target:Context_Target)->bool {
	return target.valid&&(g.active_device==.Keyboard_Mouse||target.reachable)
}

vk_draw_context_bubble :: proc(r:^Vulkan_Backend,g:^Game,target:Context_Target) {
	if !context_bubble_visible(g,target) do return
	screen,visible:=context_world_point_screen(g,target.world);edge:=!visible;screen.x=clamp(screen.x,f32(76),f32(WINDOW_WIDTH-76));screen.y=clamp(screen.y,f32(118),f32(WINDOW_HEIGHT-92))
	color:=context_status_color(target.status);age:=clamp((g.animation_time-g.context_ui.focus_started)/.18,0,1);ease:=1-(1-age)*(1-age);label_w:=f32(utf8_glyph_count(target.label))*COURIER_CELL_WIDTH*.68;action_w:=f32(utf8_glyph_count(target.action))*COURIER_CELL_WIDTH*.55;width:=max(f32(176),max(label_w,action_w)+66)*ease;height:=f32(58);x:=clamp(screen.x-width*.5,f32(8),f32(WINDOW_WIDTH)-width-8);y:=clamp(screen.y-height-10,f32(72),f32(610))
	if edge do vulkan_ui_triangle(r,{screen.x,screen.y-8},{screen.x-7,screen.y+3},{screen.x+7,screen.y+3},color)
	vulkan_ui_rect(r,x+3,y+5,width,height,{4,6,9,90});vulkan_ui_rect(r,x,y,width,height,{24,27,31,244});vulkan_ui_outline(r,x,y,width,height,color,2);vulkan_ui_triangle(r,{screen.x-7,y+height},{screen.x+7,y+height},{screen.x,y+height+9},color)
	prompt_kind:Prompt_Kind=target.kind==.Vehicle?.Vehicle_Action:.Interact
	vk_text(r,x+14,y+9,target.label,{248,247,242,255},.68);vk_text(r,x+14,y+32,target.action,color,.55);vk_prompt_icon(r,g,prompt_kind,x+width-43,y+13,30)
}

vk_draw_context_group :: proc(r:^Vulkan_Backend,g:^Game) {
	if g.context_ui.target_count<=1 {vk_draw_context_bubble(r,g,g.context_ui.current);return}
	count:=g.context_ui.target_count;row_h:=f32(38);width:=f32(310);height:=f32(count)*row_h+31;x:=clamp(f32(WINDOW_WIDTH)-width-18,f32(8),f32(WINDOW_WIDTH)-width-8);y:=clamp(f32(118),f32(72),f32(WINDOW_HEIGHT)-height-58)
	vulkan_ui_rect(r,x+4,y+5,width,height,{4,6,9,90});vulkan_ui_rect(r,x,y,width,height,{24,27,31,246});vulkan_ui_outline(r,x,y,width,height,{255,218,112,220},2)
	hint:=fmt.tprintf("%s  SELECT",prompt_label(g,.Navigate));vk_text(r,x+12,y+8,fmt.tprintf("NEARBY  %d  ·  %s",count,hint),{205,207,210,255},.44)
	for target,i in g.context_ui.targets[:count] {row_y:=y+29+f32(i)*row_h;selected:=i==g.context_ui.selected;color:=selected?context_status_color(target.status):[4]u8{143,148,155,255};if selected {vulkan_ui_rect(r,x+5,row_y-2,width-10,row_h,{56,61,68,235});vulkan_ui_rect(r,x+5,row_y-2,4,row_h,color)};label:=target.label;if len(label)>25 do label=label[:25];vk_text(r,x+16,row_y+2,label,selected?[4]u8{248,247,242,255}:[4]u8{190,193,198,255},.52);vk_text(r,x+16,row_y+20,target.action,color,.38);if selected do vk_prompt_icon(r,g,.Interact,x+width-39,row_y+2,28)}
}

vk_draw_context_toast :: proc(r:^Vulkan_Backend,g:^Game) {if g.context_ui.feedback==""||g.animation_time>=g.context_ui.feedback_expires do return;color:=context_status_color(g.context_ui.feedback_status);width:=max(f32(250),f32(utf8_glyph_count(g.context_ui.feedback))*COURIER_CELL_WIDTH*.58+34);x:=(f32(WINDOW_WIDTH)-width)*.5;vulkan_ui_rect(r,x+3,604,width,38,{0,0,0,80});vulkan_ui_rect(r,x,600,width,38,{24,27,31,246});vulkan_ui_outline(r,x,600,width,38,color,2);vk_text(r,x+17,611,g.context_ui.feedback,color,.58)}

vk_draw_house_glints :: proc(r:^Vulkan_Backend,g:^Game) {
	// The nearby list is a single selection, so its world indicator must identify
	// that selection rather than every other reachable target.
	target:=g.context_ui.current
	if !target.valid||!target.reachable do return
	screen,visible:=context_world_point_screen(g,target.world)
	if !visible do return
	color:=context_status_color(target.status)
	vulkan_ui_rect(r,screen.x-3,screen.y-3,6,6,color)
	vulkan_ui_outline(r,screen.x-7,screen.y-7,14,14,{color[0],color[1],color[2],145},2)
}

vk_draw_case_sense_poi_ping :: proc(r:^Vulkan_Backend,g:^Game) {
	if g.case_sense_level==0||g.animation_time>=g.case_sense_hint_until do return
	payload:=mystery_game_payload(g);location:=world_location_index(g);if payload==nil||location<0||location>=len(payload.locations) do return;age:=clamp(1-(g.case_sense_hint_until-g.animation_time)/5,0,1);pulse:=f32(math.sin(f64(age*math.PI)));color:=[4]u8{255,218,112,u8(120+100*pulse)}
	for &entity in WORLD_ENTITIES {
		poi:=poi_index(g,entity.source_id);if poi<0||poi>=len(payload.pois)||payload.pois[poi].location_id!=payload.locations[location].entity_id||!entity_visible(g,&entity) do continue
		// Keep the pulse on the visible body of the object. A ground-plane anchor
		// falls below furniture and outside a level first-person view.
		screen,visible:=context_world_position_screen(g,{entity.x,.9,entity.y});if !visible do continue
		radius:=f32(12+8*pulse);vulkan_ui_outline(r,screen.x-radius,screen.y-radius,radius*2,radius*2,color,3);vulkan_ui_outline(r,screen.x-radius-5,screen.y-radius-5,(radius+5)*2,(radius+5)*2,{color[0],color[1],color[2],u8(45+55*pulse)},2)
	}
}

vk_draw_shortcut_cluster :: proc(r:^Vulkan_Backend,g:^Game) {attributes,notebook,theory:=gameplay_attributes_rect(),gameplay_notebook_rect(),gameplay_theory_rect();boxes:=[3]Rect{attributes,notebook,theory};for box in boxes {vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{17,20,24,224});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,contains(box,g.input.mouse_pos)?[4]u8{255,218,112,230}:[4]u8{74,78,84,190},contains(box,g.input.mouse_pos)?2:1)};vk_prompt_icon(r,g,.Attributes,attributes.x+8,attributes.y+8,26);vk_text(r,attributes.x+40,attributes.y+14,"ATTR",{205,207,210,255},.44);vk_prompt_icon(r,g,.Notebook,notebook.x+8,notebook.y+8,26);vk_text(r,notebook.x+40,notebook.y+14,"NOTES",{205,207,210,255},.44);vk_prompt_icon(r,g,.Board,theory.x+8,theory.y+8,26);vk_text(r,theory.x+40,theory.y+14,"THEORY",{205,207,210,255},.44)}

quest_transition_enqueue :: proc(g:^Game,id:string,status:Story_Objective_Status) {
	was_empty:=len(g.quest_transition_ids)==0;append(&g.quest_transition_ids,id);append(&g.quest_transition_status,status)
	if was_empty do g.quest_transition_started=g.animation_time
}

quest_tracker_sync :: proc(g:^Game) {
	if g.story_project==nil||g.story_state==nil do return
	count:=min(len(g.story_state.objectives),len(g.quest_observed))
	if !g.quest_tracker_initialized {for i in 0..<count do g.quest_observed[i]=g.story_state.objectives[i].status;g.quest_observed_count=count;g.quest_tracker_initialized=true;return}
	// Completion is announced before a newly activated successor, even when both
	// statuses change in the same authored transaction.
	for i in 0..<count {status:=g.story_state.objectives[i].status;old:=i<g.quest_observed_count?g.quest_observed[i]:Story_Objective_Status.Inactive;if status!=old&&(status==.Completed||status==.Failed) do quest_transition_enqueue(g,g.story_state.objectives[i].objective_id,status)}
	for i in 0..<count {status:=g.story_state.objectives[i].status;old:=i<g.quest_observed_count?g.quest_observed[i]:Story_Objective_Status.Inactive;if status!=old&&status==.Active do quest_transition_enqueue(g,g.story_state.objectives[i].objective_id,status);g.quest_observed[i]=status}
	g.quest_observed_count=count
	if len(g.quest_transition_ids)>0 {duration:=g.quest_transition_status[0]==.Active?f32(1.2):f32(1.5);if g.animation_time-g.quest_transition_started>=duration {ordered_remove(&g.quest_transition_ids,0);ordered_remove(&g.quest_transition_status,0);g.quest_transition_started=g.animation_time}}
}

vk_draw_quest_card :: proc(r:^Vulkan_Backend,g:^Game,objective_index:int,status:Story_Objective_Status,transition:bool,x,y:f32) {
	objective:=g.story_project.objectives[objective_index];w:=f32(390);h:=f32(78);accent:=status==.Completed?[4]u8{117,229,169,255}:status==.Failed?[4]u8{255,144,119,255}:[4]u8{255,218,112,255}
	vulkan_ui_rect(r,x+3,y+4,w,h,{4,6,9,85});vulkan_ui_rect(r,x,y,w,h,{19,22,27,232});vulkan_ui_outline(r,x,y,w,h,{82,87,94,215},1);vulkan_ui_rect(r,x,y,5,h,accent)
	heading:=transition?(status==.Completed?"OBJECTIVE COMPLETE":status==.Failed?"OBJECTIVE CLOSED":"NEW OBJECTIVE"):"CURRENT OBJECTIVE";vk_text(r,x+17,y+9,heading,accent,.38);vk_text(r,x+17,y+28,objective.display_name,{248,247,242,255},.62);_=vk_text_wrapped(r,x+17,y+49,w-32,objective.description,{190,194,201,255},.42,2)
}

vk_draw_quest_tracker :: proc(r:^Vulkan_Backend,g:^Game) {
	if g.story_project==nil||g.story_state==nil do return
	quest_tracker_sync(g);if !quest_tracker_enabled(g) do return
	objective_index:=-1;status:=Story_Objective_Status.Active;transition:=len(g.quest_transition_ids)>0
	if transition {objective_index=story_objective_index(g.story_project,g.quest_transition_ids[0]);status=g.quest_transition_status[0]} else do objective_index=story_tracked_objective_index(g.story_project,g.story_state)
	if objective_index<0||objective_index>=len(g.story_project.objectives)||g.story_project.objectives[objective_index].hidden do return
	vk_draw_quest_card(r,g,objective_index,status,transition,16,g.screen==.Exterior?f32(96):f32(64))
}

vk_draw_quest_transition_overlay :: proc(r:^Vulkan_Backend,g:^Game) {
	if g.story_project==nil||g.story_state==nil||g.screen==.Exterior||g.screen==.Investigate do return
	quest_tracker_sync(g);if g.guidance_mode==.Minimal||len(g.quest_transition_ids)==0 do return
	objective_index:=story_objective_index(g.story_project,g.quest_transition_ids[0]);if objective_index<0||g.story_project.objectives[objective_index].hidden do return
	x,y:=g.screen==.Dialogue?f32(16):f32(405),g.screen==.Dialogue?f32(64):f32(24);vk_draw_quest_card(r,g,objective_index,g.quest_transition_status[0],true,x,y)
}

quest_tracker_enabled :: proc(g:^Game)->bool {return g.guidance_mode!=.Minimal&&g.story_project!=nil&&g.story_state!=nil&&(g.screen==.Exterior||g.screen==.Investigate)}

vk_draw_tutorial_prompt :: proc(r:^Vulkan_Backend,g:^Game) {
	if !case_uses_city_tutorial(g)||g.guidance_mode==.Minimal do return
	label:="";kind:=Prompt_Kind.Move
	if !tutorial_completed(g,.Move) {label=tutorial_lesson_prompt(g,.Move,"MOVE");kind=.Move} else if !tutorial_completed(g,.Look) {label=tutorial_lesson_prompt(g,.Look,"LOOK AROUND");kind=.Look} else if !tutorial_completed(g,.Briefing)&&city_briefing_actionable(g) {label=tutorial_lesson_prompt(g,.Briefing,"RECEIVE BRIEFING");kind=.Interact} else do return
	control_width:=max(f32(32),f32(utf8_glyph_count(prompt_label(g,kind)))*6+14);box:=Rect{420,642,360,50};vulkan_ui_rect(r,box.x+3,box.y+4,box.w,box.h,{0,0,0,90});vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{20,24,30,242});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,{255,211,92,220},2);vk_prompt_icon(r,g,kind,box.x+12,box.y+9,32);vk_text(r,box.x+control_width+26,box.y+16,label,{248,247,242,255},.66)
}

city_minimap_camera_basis :: proc(g:^Game)->(right,forward:Vec2) {
	view:=vk_world_view_pose(g);forward={view.target.x-view.eye.x,view.target.z-view.eye.z}
	length:=f32(math.sqrt(f64(forward.x*forward.x+forward.y*forward.y)))
	if length<=.0001 {forward={f32(math.cos(f64(g.city_angle))),f32(math.sin(f64(g.city_angle)))}} else {forward={forward.x/length,forward.y/length}}
	right={-forward.y,forward.x}
	return
}

city_minimap_project :: proc(point,center,right,forward:Vec2,map_center:Vec2,scale_x,scale_y:f32)->Vec2 {
	delta:=Vec2{point.x-center.x,point.y-center.y}
	return {map_center.x+(delta.x*right.x+delta.y*right.y)*scale_x,map_center.y-(delta.x*forward.x+delta.y*forward.y)*scale_y}
}

city_quest_marker_visible :: proc(g:^Game,landmark:City_Landmark)->bool {
	payload:=mystery_game_payload(g);if payload==nil||landmark.id!=payload.city_destination do return false
	return !case_uses_city_tutorial(g)||tutorial_completed(g,.Briefing)
}

vk_draw_city_quest_marker :: proc(r:^Vulkan_Backend,x,y:f32) {
	color:=[4]u8{255,218,112,255};outline:=[4]u8{74,54,24,245}
	// A compact map-pin diamond reads as the active destination without adding a
	// world-space arrow or route that would compete with the authored city.
	top:=Vec2{x,y-8};right:=Vec2{x+7,y-1};bottom:=Vec2{x,y+6};left:=Vec2{x-7,y-1}
	vulkan_ui_triangle(r,top,right,bottom,outline);vulkan_ui_triangle(r,top,bottom,left,outline)
	inner_top:=Vec2{x,y-5};inner_right:=Vec2{x+4,y-1};inner_bottom:=Vec2{x,y+3};inner_left:=Vec2{x-4,y-1}
	vulkan_ui_triangle(r,inner_top,inner_right,inner_bottom,color);vulkan_ui_triangle(r,inner_top,inner_bottom,inner_left,color)
	vulkan_ui_rect(r,x-1,y+6,2,4,color)
}

city_minimap_clamp_quest_marker :: proc(point:Vec2,map_x,map_y,map_w,map_h:f32)->Vec2 {
	edge:=f32(11)
	return {clamp(point.x,map_x+edge,map_x+map_w-edge),clamp(point.y,map_y+edge,map_y+map_h-edge)}
}

vk_draw_city_minimap :: proc(r:^Vulkan_Backend,g:^Game) {
	x,y,w,h:=f32(966),f32(82),f32(216),f32(180);inset:=f32(8);map_x,map_y:=x+inset,y+inset;map_w,map_h:=w-inset*2,h-inset*2
	vulkan_ui_rect(r,x+3,y+4,w,h,{4,6,9,100});vulkan_ui_rect(r,x,y,w,h,{15,20,25,238});vulkan_ui_outline(r,x,y,w,h,{139,107,55,220},1)
	vulkan_ui_rect(r,map_x,map_y,map_w,map_h,{37,58,61,255})
	// The city is larger than this panel can usefully show at once. Keep the
	// player at the center of a camera-relative neighborhood-sized window.
	view_w,view_h:=f32(72),f32(59.04);half_w,half_h:=view_w*.5,view_h*.5
	center_x,center_y:=g.city_x,g.city_y
	center:=Vec2{center_x,center_y};map_center:=Vec2{map_x+map_w*.5,map_y+map_h*.5};scale_x,scale_y:=map_w/view_w,map_h/view_h;right,forward:=city_minimap_camera_basis(g)
	vulkan_ui_scissor(r,map_x,map_y,map_w,map_h)
	view_radius:=f32(math.sqrt(f64(half_w*half_w+half_h*half_h)))+6
	first_x:=max(0,int(math.floor(f64((center_x-view_radius)/4)))*4);last_x:=min(CITY_WIDTH,int(math.ceil(f64((center_x+view_radius)/4)))*4)
	first_y:=max(0,int(math.floor(f64((center_y-view_radius)/4)))*4);last_y:=min(CITY_HEIGHT,int(math.ceil(f64((center_y+view_radius)/4)))*4)
	for iy:=first_y;iy<last_y;iy+=4 {
		for ix:=first_x;ix<last_x;ix+=4 {
			if !city_road_cell(ix+2,iy+2) do continue
			a:=city_minimap_project({f32(ix),f32(iy)},center,right,forward,map_center,scale_x,scale_y);b:=city_minimap_project({f32(ix+4),f32(iy)},center,right,forward,map_center,scale_x,scale_y);c:=city_minimap_project({f32(ix+4),f32(iy+4)},center,right,forward,map_center,scale_x,scale_y);d:=city_minimap_project({f32(ix),f32(iy+4)},center,right,forward,map_center,scale_x,scale_y)
			vulkan_ui_triangle(r,a,b,c,{117,126,126,235});vulkan_ui_triangle(r,a,c,d,{117,126,126,235})
		}
	}
	for i in 0..<city_landmark_count(g) {
		landmark,ok:=city_landmark_at(g,i);if !ok do continue
		projected:=city_minimap_project({landmark.x,landmark.y},center,right,forward,map_center,scale_x,scale_y);lx,ly:=projected.x,projected.y
		quest_marker:=city_quest_marker_visible(g,landmark);color:=landmark.case_authored?[4]u8{205,176,101,225}:[4]u8{152,196,214,235};radius:=f32(2.5)
		if quest_marker {clamped:=city_minimap_clamp_quest_marker({lx,ly},map_x,map_y,map_w,map_h);lx,ly=clamped.x,clamped.y}else if lx<map_x||lx>map_x+map_w||ly<map_y||ly>map_y+map_h do continue
		if quest_marker do vk_draw_city_quest_marker(r,lx,ly);else do vulkan_ui_rect(r,lx-radius,ly-radius,radius*2,radius*2,color)
	}
	player:=city_minimap_project({g.city_x,g.city_y},center,right,forward,map_center,scale_x,scale_y);px,py:=player.x,player.y;heading:=Vec2{f32(math.cos(f64(g.city_angle))),f32(math.sin(f64(g.city_angle)))}
	marker_forward:=Vec2{heading.x*right.x+heading.y*right.y,-(heading.x*forward.x+heading.y*forward.y)};marker_side:=Vec2{-marker_forward.y,marker_forward.x};tip:=Vec2{px+marker_forward.x*8,py+marker_forward.y*8};left:=Vec2{px-marker_forward.x*5+marker_side.x*4,py-marker_forward.y*5+marker_side.y*4};marker_right:=Vec2{px-marker_forward.x*5-marker_side.x*4,py-marker_forward.y*5-marker_side.y*4}
	vulkan_ui_triangle(r,tip,left,marker_right,{255,244,190,255});vulkan_ui_outline(r,px-2,py-2,4,4,{30,34,38,255},1);vulkan_ui_scissor_reset(r)
	vk_text(r,x+9,y+h-17,"CITY MAP",{205,207,210,235},.36)
}

vk_draw_city_overlay :: proc(r:^Vulkan_Backend,g:^Game) {
	payload:=mystery_game_payload(g);location:=fmt.tprintf("VALE CITY · %s",city_neighborhood_name(g.city_x,g.city_y));if payload!=nil&&!tutorial_completed(g,.Briefing) {start_index:=city_landmark_index(g,payload.city_start);if start_index>=0 {start,_:=city_landmark_at(g,start_index);location=start.name}};vk_draw_location_plaque(r,location)
	hour_value:=world_time_hour(g.animation_time);hour:=int(hour_value);minute:=int((hour_value-f32(hour))*60);vk_text(r,28,72,fmt.tprintf("%02d:%02d  ·  WEATHER: RAIN",hour,minute),{205,220,224,235},.42)
	vk_draw_city_minimap(r,g)
	if g.context_ui.current.valid&&g.driving_vehicle<0 do vk_draw_context_bubble(r,g,g.context_ui.current)
	if g.driving_vehicle>=0 {
		car:=g.vehicles[g.driving_vehicle];traction:=car.traction_state;slip:=vehicle_slip_ratio(car);traction_color:=traction==.Grip?[4]u8{117,229,169,255}:traction==.Slip?[4]u8{255,211,92,255}:[4]u8{255,144,119,255}
		_,exit_clear:=vehicle_exit_position(g,car,g.driving_vehicle);stopped:=vehicle_can_exit(car);exit_ready:=stopped&&exit_clear;exit_label:=exit_ready?fmt.tprintf("%s  EXIT",prompt_label(g,.Vehicle_Action)):stopped?"NO EXIT SPACE":"SLOW TO EXIT"
		handbrake:=vehicle_handbrake_input(g);assist_active:=car.driver_assist!=.None;control_label:=handbrake?"HANDBRAKE":assist_active?vehicle_driver_assist_label(car.driver_assist):fmt.tprintf("%s  HANDBRAKE",prompt_label(g,.Handbrake));control_color:=handbrake?[4]u8{255,144,119,255}:assist_active?vehicle_driver_assist_indicator_color(car.driver_assist_strength):[4]u8{145,153,162,255}
		surface_label:=vehicle_surface_blend_label(car.surface_blend);surface_color:=car.surface_blend<.20?[4]u8{173,183,192,255}:car.surface_blend>.80?[4]u8{255,190,92,255}:[4]u8{221,187,142,255}
		vulkan_ui_rect(r,16,646,430,56,{18,22,25,232});vulkan_ui_outline(r,16,646,430,56,{83,94,105,205},1)
		vk_text(r,30,655,fmt.tprintf("%s  ·  %s %03d",strings.to_upper(CITY_CARS[g.driving_vehicle].model),vehicle_transmission_label(car,vehicle_tune(g.driving_vehicle)),int(vehicle_actual_speed(car)*180)),{117,229,169,255},.62)
		vk_text(r,282,657,exit_label,exit_ready?[4]u8{205,207,210,255}:[4]u8{255,190,92,255},.46)
		vk_text(r,30,681,vehicle_traction_label(traction),traction_color,.42);vulkan_ui_rect(r,92,687,94,5,{48,55,62,255});vulkan_ui_rect(r,92,687,94*slip,5,traction_color)
		vk_text(r,210,681,surface_label,surface_color,.42);vk_text(r,292,681,control_label,control_color,.36)
	}
	vk_draw_context_toast(r,g);vk_draw_tutorial_prompt(r,g);vk_draw_quest_tracker(r,g)
}

vk_draw_house_overlay :: proc(r:^Vulkan_Backend,g:^Game) {
	if g.editor_mode==.Build {vk_draw_build_overlay(r,g);return}
	if g.editor_mode==.Graph {vk_draw_graph_overlay(r,g);if graph_state.playtesting {vk_draw_graph_debugger(r,g);vk_button(r,graph_debugger_editor_rect(),"GAME",true)};if graph_state.help_visible do vk_draw_graph_help(r);return}
	if editor_state.playtesting {vk_panel(r,700,646,270,48);vk_text(r,716,655,"PLAYTESTING FROM EDITOR",{117,229,169,255},.44);vk_text(r,716,674,"F10  RETURN TO BUILD MODE",{205,207,210,255},.32)}
	vk_draw_location_plaque(r,world_location_label(g));vk_draw_time_chip(r,g)
	warning:=action_warning_text(g);if warning!="" {color:=g.ap<=2?[4]u8{255,144,119,255}:[4]u8{255,218,112,255};width:=f32(utf8_glyph_count(warning))*COURIER_CELL_WIDTH*.54+30;vulkan_ui_rect(r,(WINDOW_WIDTH-width)*.5,18,width,32,{24,27,31,238});vulkan_ui_outline(r,(WINDOW_WIDTH-width)*.5,18,width,32,color,1);vk_text(r,(WINDOW_WIDTH-width)*.5+15,27,warning,color,.54)}
	vk_draw_house_glints(r,g);vk_draw_case_sense_poi_ping(r,g);vk_draw_context_group(r,g);vk_draw_context_toast(r,g)
	if g.move_target_active {target_screen,visible:=context_world_point_screen(g,{g.move_target_x,g.move_target_y});if visible {vulkan_ui_outline(r,target_screen.x-7,target_screen.y-7,14,14,{255,218,112,180},2);vulkan_ui_rect(r,target_screen.x-2,target_screen.y-2,4,4,{117,229,169,255})}}
	vk_draw_shortcut_cluster(r,g);vk_draw_case_sense(r,g)
	vk_draw_quest_tracker(r,g)
}

graph_edge_cubic_point :: proc(a,b,c,d:Vec2,t:f32)->Vec2 {
	u:=1-t;uu,tt:=u*u,t*t
	return {a.x*uu*u+3*b.x*uu*t+3*c.x*u*tt+d.x*tt*t,a.y*uu*u+3*b.y*uu*t+3*c.y*u*tt+d.y*tt*t}
}

vk_graph_cubic :: proc(r:^Vulkan_Backend,a,b,c,d:Vec2,color:[4]u8,thickness:f32) {
	// Screen-space subdivision keeps tight bends smooth without spending the
	// same number of UI quads on short, nearly straight connections.
	control_length:=f32(math.sqrt(f64((b.x-a.x)*(b.x-a.x)+(b.y-a.y)*(b.y-a.y))))+f32(math.sqrt(f64((c.x-b.x)*(c.x-b.x)+(c.y-b.y)*(c.y-b.y))))+f32(math.sqrt(f64((d.x-c.x)*(d.x-c.x)+(d.y-c.y)*(d.y-c.y))))
	steps:=clamp(int(control_length/9),8,64);previous:=a
	for i in 1..=steps {point:=graph_edge_cubic_point(a,b,c,d,f32(i)/f32(steps));vk_graph_aa_segment(r,previous,point,color,thickness);previous=point}
}

vk_graph_aa_segment :: proc(r:^Vulkan_Backend,a,b:Vec2,color:[4]u8,thickness:f32) {
	// A solid ribbon plus a one-pixel coverage fringe gives graph wires stable
	// antialiasing at every zoom level.  Overlapping round caps hide tiny cracks
	// between adaptively-subdivided curve segments.
	dx,dy:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dy*dy)));if length<.01 do return
	n:=Vec2{-dy/length,dx/length};half:=thickness*.5;outer:=half+1
	ai,ao:=Vec2{a.x+n.x*half,a.y+n.y*half},Vec2{a.x+n.x*outer,a.y+n.y*outer}
	bi,bo:=Vec2{b.x+n.x*half,b.y+n.y*half},Vec2{b.x+n.x*outer,b.y+n.y*outer}
	aj,ap:=Vec2{a.x-n.x*half,a.y-n.y*half},Vec2{a.x-n.x*outer,a.y-n.y*outer}
	bj,bp:=Vec2{b.x-n.x*half,b.y-n.y*half},Vec2{b.x-n.x*outer,b.y-n.y*outer}
	vulkan_ui_triangle(r,ai,aj,bi,color);vulkan_ui_triangle(r,bi,aj,bj,color)
	transparent:=color;transparent[3]=0
	vulkan_ui_triangle_colors(r,ao,ai,bo,transparent,color,transparent);vulkan_ui_triangle_colors(r,bo,ai,bi,transparent,color,color)
	vulkan_ui_triangle_colors(r,aj,ap,bj,color,transparent,color);vulkan_ui_triangle_colors(r,bj,ap,bp,color,transparent,transparent)
	segments:=8
	for end in 0..<2 {center:=end==0?a:b;for i in 0..<segments {angle0:=f32(i)*f32(math.PI)/f32(segments)+f32(math.PI)*.5;angle1:=f32(i+1)*f32(math.PI)/f32(segments)+f32(math.PI)*.5;if end==1 {angle0+=f32(math.PI);angle1+=f32(math.PI)};p0:=Vec2{center.x+f32(math.cos(f64(angle0)))*half,center.y+f32(math.sin(f64(angle0)))*half};p1:=Vec2{center.x+f32(math.cos(f64(angle1)))*half,center.y+f32(math.sin(f64(angle1)))*half};vulkan_ui_triangle(r,center,p0,p1,color)}}
}

vk_graph_smooth_path :: proc(r:^Vulkan_Backend,points:[]Vec2,color:[4]u8,thickness:f32) {
	// Catmull-Rom converted to cubic Beziers.  Shared derivatives make every
	// routed bend continuous, so obstacle lanes never introduce hard corners.
	if len(points)<2 do return
	for i in 0..<len(points)-1 {p0:=i>0?points[i-1]:points[i];p1,p2:=points[i],points[i+1];p3:=i+2<len(points)?points[i+2]:points[i+1];b:=Vec2{p1.x+(p2.x-p0.x)/6,p1.y+(p2.y-p0.y)/6};c:=Vec2{p2.x-(p3.x-p1.x)/6,p2.y-(p3.y-p1.y)/6};vk_graph_cubic(r,p1,b,c,p2,color,thickness)}
}

vk_graph_orthogonal_path :: proc(r:^Vulkan_Backend,a,d:Vec2,lane_y:f32,color:[4]u8,thickness:f32) {
	// Horizontal port normals are inviolate. Straight runs meet the clearance
	// lane through rounded quarter turns, so cards are always entered at 90°.
	lead:=clamp(math.abs(d.x-a.x)*.18,f32(28),f32(54));x1,x2:=a.x+lead,d.x-lead
	radius:=min(f32(22),min(math.abs(lane_y-a.y)*.45,math.abs(lane_y-d.y)*.45));radius=max(radius,f32(4))
	sy:=lane_y>=a.y?f32(1):f32(-1);ty:=d.y>=lane_y?f32(1):f32(-1);k:=f32(.55228475)
	vk_graph_aa_segment(r,a,{x1-radius,a.y},color,thickness)
	vk_graph_cubic(r,{x1-radius,a.y},{x1-radius+k*radius,a.y},{x1,lane_y-sy*radius-k*sy*radius},{x1,lane_y-sy*radius},color,thickness)
	vk_graph_aa_segment(r,{x1,lane_y-sy*radius},{x1,lane_y},color,thickness)
	vk_graph_aa_segment(r,{x1,lane_y},{x2,lane_y},color,thickness)
	vk_graph_aa_segment(r,{x2,lane_y},{x2,lane_y+ty*radius},color,thickness)
	vk_graph_cubic(r,{x2,lane_y+ty*radius},{x2,lane_y+ty*radius+k*ty*radius},{x2+radius-k*radius,d.y},{x2+radius,d.y},color,thickness)
	vk_graph_aa_segment(r,{x2+radius,d.y},d,color,thickness)
}

graph_edge_rect_hit :: proc(a,b:Vec2,box:Rect)->bool {
	// Conservative samples are intentional: routing a harmless extra bend is
	// preferable to drawing a connection through a card.
	for i in 0..=16 {t:=f32(i)/16;point:=Vec2{a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t};if contains(box,point) do return true};return false
}

graph_edge_direct_clear :: proc(scene:string,a,b:Vec2,from_index,to_index:int)->bool {
	for node,i in graph_document.nodes[:graph_document.node_count] {if i==from_index||i==to_index||node.beat.scene!=scene do continue;box:=graph_node_rect(node);box={box.x-14,box.y-14,box.w+28,box.h+28};if graph_edge_rect_hit(a,b,box) do return false};return true
}

graph_edge_segments_clear :: proc(scene:string,points:[]Vec2,from_index,to_index:int)->bool {
	for node,i in graph_document.nodes[:graph_document.node_count] {
		if i==from_index||i==to_index||node.beat.scene!=scene do continue
		box:=graph_node_rect(node);box={box.x-14,box.y-14,box.w+28,box.h+28}
		for segment in 1..<len(points) do if graph_edge_rect_hit(points[segment-1],points[segment],box) do return false
	}
	return true
}

graph_edge_local_lane :: proc(scene:string,a,d:Vec2,from_index,to_index:int)->(f32,bool) {
	// Prefer a corridor immediately above or below the cards that actually
	// obstruct this edge. This keeps detours local and leaves the canvas
	// perimeter available for genuine back edges.
	top,bottom:=f32(1e9),f32(-1e9);blocked:=false
	for node,i in graph_document.nodes[:graph_document.node_count] {
		if i==from_index||i==to_index||node.beat.scene!=scene do continue
		box:=graph_node_rect(node);box={box.x-14,box.y-14,box.w+28,box.h+28}
		if !graph_edge_rect_hit(a,d,box) do continue
		blocked=true;top=min(top,box.y-18);bottom=max(bottom,box.y+box.h+18)
	}
	if !blocked do return 0,false
	lead:=f32(28);candidates:=[2]f32{top,bottom};best,best_cost:=f32(0),f32(1e9);canvas:=graph_canvas_rect()
	for lane in candidates {
		if lane<canvas.y+10||lane>canvas.y+canvas.h-10 do continue
		points:=[4]Vec2{a,{a.x+lead,lane},{d.x-lead,lane},d}
		if !graph_edge_segments_clear(scene,points[:],from_index,to_index) do continue
		cost:=math.abs(a.y-lane)+math.abs(d.y-lane)
		if cost<best_cost {best=lane;best_cost=cost}
	}
	return best,best_cost<f32(1e9)
}

graph_edge_back_lane :: proc(scene:string,a,d:Vec2,from_index,to_index:int)->(f32,bool) {
	from,to:=graph_node_rect(graph_document.nodes[from_index]),graph_node_rect(graph_document.nodes[to_index])
	candidates:=[2]f32{min(from.y,to.y)-22,max(from.y+from.h,to.y+to.h)+22}
	best,best_cost:=f32(0),f32(1e9);canvas:=graph_canvas_rect();right_x:=min(a.x+28,canvas.x+canvas.w-4);left_x:=max(d.x-28,canvas.x+4)
	for lane in candidates {
		if lane<canvas.y+10||lane>canvas.y+canvas.h-10 do continue
		points:=[4]Vec2{a,{right_x,lane},{left_x,lane},d}
		if !graph_edge_segments_clear(scene,points[:],from_index,to_index) do continue
		cost:=math.abs(a.y-lane)+math.abs(d.y-lane)
		if cost<best_cost {best=lane;best_cost=cost}
	}
	return best,best_cost<f32(1e9)
}

vk_graph_arrow :: proc(r:^Vulkan_Backend,tip,tangent:Vec2,color:[4]u8,size:f32=10) {
	length:=f32(math.sqrt(f64(tangent.x*tangent.x+tangent.y*tangent.y)));if length<.01 do return
	d:=Vec2{tangent.x/length,tangent.y/length};n:=Vec2{-d.y,d.x};base:=Vec2{tip.x-d.x*size,tip.y-d.y*size};half:=size*.45
	vulkan_ui_triangle(r,tip,{base.x+n.x*half,base.y+n.y*half},{base.x-n.x*half,base.y-n.y*half},color)
}

graph_edge_cubic_tangent :: proc(a,b,c,d:Vec2,t:f32)->Vec2 {
	u:=1-t
	return {3*u*u*(b.x-a.x)+6*u*t*(c.x-b.x)+3*t*t*(d.x-c.x),3*u*u*(b.y-a.y)+6*u*t*(c.y-b.y)+3*t*t*(d.y-c.y)}
}

vk_graph_direction_marker :: proc(r:^Vulkan_Backend,point,tangent:Vec2,color:[4]u8) {
	// A single marker only appears on the active route. Its outline isolates a
	// clean silhouette without turning every wire into a repeated-arrow
	// diagram. An open chevron preserves the cable's continuity; a filled
	// triangle in the same highlight color reads as a gap instead of direction.
	length:=f32(math.sqrt(f64(tangent.x*tangent.x+tangent.y*tangent.y)));if length<.01 do return
	d:=Vec2{tangent.x/length,tangent.y/length};n:=Vec2{-d.y,d.x};back:=Vec2{point.x-d.x*9,point.y-d.y*9};wing_a,wing_b:=Vec2{back.x+n.x*5,back.y+n.y*5},Vec2{back.x-n.x*5,back.y-n.y*5};outline:=[4]u8{7,10,15,245}
	vk_graph_aa_segment(r,wing_a,point,outline,5);vk_graph_aa_segment(r,wing_b,point,outline,5)
	vk_graph_aa_segment(r,wing_a,point,color,2);vk_graph_aa_segment(r,wing_b,point,color,2)
}

vk_graph_edge :: proc(r:^Vulkan_Backend,scene:string,from_index,to_index,port_index:int,color:[4]u8,thickness:f32=2,direction_marker:=false) {
	from_node,to_node:=graph_document.nodes[from_index],graph_document.nodes[to_index]
	from_port,to_port:=graph_port_rect(from_node,port_index),graph_input_rect(to_node)
	a:=Vec2{from_port.x+from_port.w*.5,from_port.y+from_port.h*.5};d:=Vec2{to_port.x+to_port.w*.5,to_port.y+to_port.h*.5};dx:=d.x-a.x
	if dx>2&&graph_edge_direct_clear(scene,a,d,from_index,to_index) {
		// Keep the body fluid, but reserve a clearly perpendicular lead at each
		// port so the connection meets both card edges at exactly 90 degrees.
		if math.abs(d.y-a.y)<1 {vk_graph_aa_segment(r,a,d,color,thickness);if direction_marker do vk_graph_direction_marker(r,{a.x+(d.x-a.x)*.68,a.y+(d.y-a.y)*.68},{d.x-a.x,d.y-a.y},color);vk_graph_arrow(r,d,{1,0},color);return}
		lead:=min(f32(14),dx*.18);start,finish:=Vec2{a.x+lead,a.y},Vec2{d.x-lead,d.y};h:=max(f32(2),(finish.x-start.x)*.46);b,c:=Vec2{start.x+h,start.y},Vec2{finish.x-h,finish.y};vk_graph_aa_segment(r,a,start,color,thickness);vk_graph_cubic(r,start,b,c,finish,color,thickness);vk_graph_aa_segment(r,finish,d,color,thickness);if direction_marker {t:=f32(.68);point:=graph_edge_cubic_point(start,b,c,finish,t);vk_graph_direction_marker(r,point,graph_edge_cubic_tangent(start,b,c,finish,t),color)};vk_graph_arrow(r,d,{1,0},color);return
	}
	if dx>2 {
		if lane_y,ok:=graph_edge_local_lane(scene,a,d,from_index,to_index);ok {
			vk_graph_orthogonal_path(r,a,d,lane_y,color,thickness);if direction_marker do vk_graph_direction_marker(r,{a.x+(d.x-a.x)*.68,lane_y},{d.x-a.x,0},color);vk_graph_arrow(r,d,{1,0},color);return
		}
	}
	if dx<=2 {
		if lane_y,ok:=graph_edge_back_lane(scene,a,d,from_index,to_index);ok {
			canvas:=graph_canvas_rect();right_x:=min(a.x+28,canvas.x+canvas.w-4);left_x:=max(d.x-28,canvas.x+4);p1,p2:=Vec2{right_x,lane_y},Vec2{left_x,lane_y};span:=p2.x-p1.x
			vk_graph_cubic(r,a,{right_x,a.y},{p1.x,lane_y},p1,color,thickness)
			vk_graph_cubic(r,p1,{p1.x+span*.28,p1.y},{p2.x-span*.28,p2.y},p2,color,thickness)
			if direction_marker {b,c_mid:=Vec2{p1.x+span*.28,p1.y},Vec2{p2.x-span*.28,p2.y};t:=f32(.68);point:=graph_edge_cubic_point(p1,b,c_mid,p2,t);vk_graph_direction_marker(r,point,graph_edge_cubic_tangent(p1,b,c_mid,p2,t),color)}
			c:=Vec2{left_x,d.y};vk_graph_cubic(r,p2,{p2.x,lane_y},{c.x,d.y},d,color,thickness);vk_graph_arrow(r,d,{d.x-c.x,d.y-c.y},color);return
		}
	}
	// Back edges and obstructed forward edges use an outside lane. The two
	// boundary corridors form the useful part of the visibility graph here;
	// choose the shortest route deterministically.
	canvas:=graph_canvas_rect();top_y,bottom_y:=canvas.y+12,canvas.y+canvas.h-12
	top_cost:=math.abs(a.y-top_y)+math.abs(d.y-top_y);bottom_cost:=math.abs(a.y-bottom_y)+math.abs(d.y-bottom_y);lane_y:=top_cost<=bottom_cost?top_y:bottom_y
	vk_graph_orthogonal_path(r,a,d,lane_y,color,thickness)
	if direction_marker do vk_graph_direction_marker(r,{a.x+(d.x-a.x)*.68,lane_y},{d.x-a.x,0},color)
	vk_graph_arrow(r,d,{1,0},color)
}

vk_graph_edge_ports_foreground :: proc(r:^Vulkan_Backend,from_index,to_index,port_index:int,color:[4]u8) {
	// Card bodies stay above routed wires, but the final few pixels cross above
	// their port blocks so ports read as sockets beneath a continuous cable.
	from_node,to_node:=graph_document.nodes[from_index],graph_document.nodes[to_index]
	from_port,to_port:=graph_port_rect(from_node,port_index),graph_input_rect(to_node)
	a:=Vec2{from_port.x+from_port.w*.5,from_port.y+from_port.h*.5};d:=Vec2{to_port.x+to_port.w*.5,to_port.y+to_port.h*.5}
	vk_graph_aa_segment(r,{a.x-from_port.w*.5,a.y},{a.x+from_port.w*.5+2,a.y},color,2)
	vk_graph_aa_segment(r,{d.x-to_port.w*.5-3,d.y},{d.x+to_port.w*.5,d.y},color,2)
	vk_graph_arrow(r,d,{1,0},color)
}

graph_cubic_hit :: proc(point,a,b,c,d:Vec2)->bool {
	previous:=a
	for sample in 1..=32 {current:=graph_edge_cubic_point(a,b,c,d,f32(sample)/32);if graph_point_segment_distance(point,previous,current)<=8 do return true;previous=current}
	return false
}

graph_smooth_path_hit :: proc(point:Vec2,points:[]Vec2)->bool {
	for i in 0..<len(points)-1 {p0:=i>0?points[i-1]:points[i];p1,p2:=points[i],points[i+1];p3:=i+2<len(points)?points[i+2]:points[i+1];b:=Vec2{p1.x+(p2.x-p0.x)/6,p1.y+(p2.y-p0.y)/6};c:=Vec2{p2.x-(p3.x-p1.x)/6,p2.y-(p3.y-p1.y)/6};if graph_cubic_hit(point,p1,b,c,p2) do return true}
	return false
}

graph_segment_hit :: proc(point,a,b:Vec2)->bool {return graph_point_segment_distance(point,a,b)<=8}

graph_orthogonal_path_hit :: proc(point,a,d:Vec2,lane_y:f32)->bool {
	lead:=clamp(math.abs(d.x-a.x)*.18,f32(28),f32(54));x1,x2:=a.x+lead,d.x-lead
	radius:=min(f32(22),min(math.abs(lane_y-a.y)*.45,math.abs(lane_y-d.y)*.45));radius=max(radius,f32(4))
	sy:=lane_y>=a.y?f32(1):f32(-1);ty:=d.y>=lane_y?f32(1):f32(-1);k:=f32(.55228475)
	if graph_segment_hit(point,a,{x1-radius,a.y}) do return true
	if graph_cubic_hit(point,{x1-radius,a.y},{x1-radius+k*radius,a.y},{x1,lane_y-sy*radius-k*sy*radius},{x1,lane_y-sy*radius}) do return true
	if graph_segment_hit(point,{x1,lane_y-sy*radius},{x1,lane_y})||graph_segment_hit(point,{x1,lane_y},{x2,lane_y})||graph_segment_hit(point,{x2,lane_y},{x2,lane_y+ty*radius}) do return true
	if graph_cubic_hit(point,{x2,lane_y+ty*radius},{x2,lane_y+ty*radius+k*ty*radius},{x2+radius-k*radius,d.y},{x2+radius,d.y}) do return true
	return graph_segment_hit(point,{x2+radius,d.y},d)
}

graph_rendered_edge_hit :: proc(point:Vec2,scene:string,from_index,to_index,port_index:int)->bool {
	from_node,to_node:=graph_document.nodes[from_index],graph_document.nodes[to_index];from_port,to_port:=graph_port_rect(from_node,port_index),graph_input_rect(to_node)
	a:=Vec2{from_port.x+from_port.w*.5,from_port.y+from_port.h*.5};d:=Vec2{to_port.x+to_port.w*.5,to_port.y+to_port.h*.5};dx:=d.x-a.x
	if dx>2&&graph_edge_direct_clear(scene,a,d,from_index,to_index) {if math.abs(d.y-a.y)<1 do return graph_segment_hit(point,a,d);lead:=min(f32(14),dx*.18);start,finish:=Vec2{a.x+lead,a.y},Vec2{d.x-lead,d.y};h:=max(f32(2),(finish.x-start.x)*.46);if graph_segment_hit(point,a,start)||graph_segment_hit(point,finish,d) do return true;return graph_cubic_hit(point,start,{start.x+h,start.y},{finish.x-h,finish.y},finish)}
	if dx>2 {if lane_y,ok:=graph_edge_local_lane(scene,a,d,from_index,to_index);ok do return graph_orthogonal_path_hit(point,a,d,lane_y)}
	if dx<=2 {if lane_y,ok:=graph_edge_back_lane(scene,a,d,from_index,to_index);ok {canvas:=graph_canvas_rect();right_x:=min(a.x+28,canvas.x+canvas.w-4);left_x:=max(d.x-28,canvas.x+4);p1,p2:=Vec2{right_x,lane_y},Vec2{left_x,lane_y};span:=p2.x-p1.x;if graph_cubic_hit(point,a,{right_x,a.y},{p1.x,lane_y},p1) do return true;if graph_cubic_hit(point,p1,{p1.x+span*.28,p1.y},{p2.x-span*.28,p2.y},p2) do return true;return graph_cubic_hit(point,p2,{p2.x,lane_y},{left_x,d.y},d)}}
	canvas:=graph_canvas_rect();top_y,bottom_y:=canvas.y+12,canvas.y+canvas.h-12;top_cost:=math.abs(a.y-top_y)+math.abs(d.y-top_y);bottom_cost:=math.abs(a.y-bottom_y)+math.abs(d.y-bottom_y);lane_y:=top_cost<=bottom_cost?top_y:bottom_y;return graph_orthogonal_path_hit(point,a,d,lane_y)
}

vk_draw_graph_node :: proc(r:^Vulkan_Backend,node:^Graph_Node,index:int) {
	box:=graph_node_rect(node^);accent:=graph_kind_color(node.beat.kind);selected:=graph_is_selected(index);zoom:=graph_state.zoom
	header_h:=min(box.h,f32(24)*zoom);body_y:=box.y+header_h
	vulkan_ui_rect(r,box.x+3,box.y+4,box.w,box.h,{0,0,0,88})
	vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{24,31,40,255})
	vulkan_ui_outline(r,box.x,box.y,box.w,box.h,selected?accent:[4]u8{69,80,94,255},selected?3:1)
	vulkan_ui_rect(r,box.x,box.y,4*zoom,box.h,accent)
	vulkan_ui_rect(r,box.x,box.y,box.w,header_h,{31,39,49,255})
	vulkan_ui_rect(r,box.x,body_y,box.w,1,accent)
	vk_editor_text(r,box.x+10*zoom,box.y+6*zoom,graph_kind_label(node.beat.kind),accent,.70*zoom)
	id:=node.beat.id;if len(id)>14 do id=id[:14]
	id_width:=f32(utf8_glyph_count(id))*COURIER_CELL_WIDTH*.70*zoom
	vk_editor_text(r,max(box.x+62*zoom,box.x+box.w-id_width-9*zoom),box.y+7*zoom,id,{174,184,196,255},.70*zoom)
	if !node.collapsed {
		preview:=node.beat.text;if preview=="" do preview=node.beat.summary;if preview=="" do preview=node.beat.speaker;if preview=="" do preview=node.beat.camera
		preview_limit:=node.beat.kind=="choice"?10:14;if len(preview)>preview_limit do preview=preview[:preview_limit]
		if preview!="" do vk_editor_text(r,box.x+10*zoom,body_y+10*zoom,preview,{178,211,220,255},.70*zoom)
	}
	input:=graph_input_rect(node^);vulkan_ui_rect(r,input.x,input.y,input.w,input.h,{214,222,231,255});vulkan_ui_outline(r,input.x,input.y,input.w,input.h,{92,105,120,255},1)
	for port_index in 0..<graph_output_count(&node.beat) {
		port,choice:=graph_output_port(&node.beat,port_index);port_box:=graph_port_rect(node^,port_index);port_color:=graph_port_color(port)
		vulkan_ui_rect(r,port_box.x,port_box.y,port_box.w,port_box.h,port_color)
		label:=port==.Choice&&choice>=0&&choice<len(node.beat.choice_labels)?node.beat.choice_labels[choice]:strings.to_upper(fmt.tprintf("%v",port));if len(label)>8 do label=label[:8]
		label_width:=f32(utf8_glyph_count(label))*COURIER_CELL_WIDTH*.70*zoom;label_x:=port_box.x-label_width-6*zoom
		vulkan_ui_rect(r,label_x-4*zoom,port_box.y-3*zoom,label_width+7*zoom,port_box.h+6*zoom,{20,26,34,230})
		vk_editor_text(r,label_x,port_box.y+1*zoom,label,port_color,.70*zoom)
	}
}

graph_node_screen_visible :: proc(node:Graph_Node)->bool {box:=graph_node_rect(node);canvas:=graph_canvas_rect();return graph_rects_overlap(box,{canvas.x-12,canvas.y-12,canvas.w+24,canvas.h+24})}
graph_edge_screen_visible :: proc(from_node,to_node:Graph_Node)->bool {a,b:=graph_node_rect(from_node),graph_node_rect(to_node);bounds:=Rect{min(a.x,b.x)-64,min(a.y,b.y)-64,max(a.x+a.w,b.x+b.w)-min(a.x,b.x)+128,max(a.y+a.h,b.y+b.h)-min(a.y,b.y)+128};return graph_rects_overlap(bounds,graph_canvas_rect())}

vk_graph_endpoint_emphasis :: proc(r:^Vulkan_Backend,edge:Graph_Edge_Selection,color:[4]u8) {
	if !edge.active||edge.node<0||edge.node>=graph_document.node_count do return
	source:=&graph_document.nodes[edge.node];target:=graph_port_target(&source.beat,edge.port,edge.choice_index);if target==nil do return
	to:=graph_node_index(source.beat.scene,target^);if to<0 do return
	port_index:=-1;for i in 0..<graph_output_count(&source.beat) {port,choice:=graph_output_port(&source.beat,i);if port==edge.port&&choice==edge.choice_index {port_index=i;break}}
	if port_index<0 do return
	from_box,to_box:=graph_port_rect(source^,port_index),graph_input_rect(graph_document.nodes[to]);boxes:=[2]Rect{from_box,to_box}
	for box in boxes {vulkan_ui_outline(r,box.x-5,box.y-5,box.w+10,box.h+10,{color[0],color[1],color[2],80},3);vulkan_ui_outline(r,box.x-2,box.y-2,box.w+4,box.h+4,color,2)}
	arrow_size:=clamp(f32(8)*graph_state.zoom,f32(6),f32(9));tip:=Vec2{to_box.x-9,to_box.y+to_box.h*.5};vk_graph_arrow(r,tip,{1,0},{7,10,15,235},arrow_size+3);vk_graph_arrow(r,tip,{1,0},color,arrow_size)
}

graph_edge_footer_id :: proc(id:string)->string {
	// Node IDs are ASCII by validation. Preserve both distinguishing ends while
	// bounding the active-route label before the fixed Search controls.
	if len(id)<=13 do return id
	return fmt.tprintf("%s…%s",id[:6],id[len(id)-6:])
}

Graph_Choice_Icon :: enum {Edit_Id,Duplicate,Delete,Drag_Handle}

vk_graph_choice_icon_button :: proc(r:^Vulkan_Backend,box:Rect,icon:Graph_Choice_Icon,active:=false) {
	vk_graph_button(r,box,"",active);c:=UI_INK_STRONG;cx,cy:=box.x+box.w*.5,box.y+box.h*.5
	switch icon {
	case .Edit_Id:
		// Tag silhouette: stable IDs name authored choice branches.
		vulkan_ui_outline(r,cx-8,cy-5,12,10,c,2);vk_graph_aa_segment(r,{cx+4,cy-5},{cx+9,cy},c,2);vk_graph_aa_segment(r,{cx+9,cy},{cx+4,cy+5},c,2);vulkan_ui_rect(r,cx-5,cy-1,2,2,c)
	case .Duplicate:
		vulkan_ui_outline(r,cx-6,cy-6,9,10,c,2);vulkan_ui_outline(r,cx-2,cy-2,9,10,c,2)
	case .Delete:
		vulkan_ui_outline(r,cx-6,cy-4,12,11,c,2);vulkan_ui_rect(r,cx-8,cy-8,16,2,c);vulkan_ui_rect(r,cx-3,cy-10,6,2,c);vulkan_ui_rect(r,cx-2,cy-1,2,6,c)
	case .Drag_Handle:
		for row in 0..<3 do for column in 0..<2 do vulkan_ui_rect(r,cx-5+f32(column)*8,cy-5+f32(row)*5,3,3,c)
	}
}

vk_graph_choice_tooltip :: proc(r:^Vulkan_Backend,box:Rect,label:string) {
	if label=="" do return;width:=f32(utf8_glyph_count(label))*6+18;x:=min(box.x+box.w-width,f32(1188)-width);y:=box.y+box.h+4
	vulkan_ui_rect(r,x+3,y+3,width,24,UI_SHADOW);vulkan_ui_rect(r,x,y,width,24,{24,31,40,255});vulkan_ui_outline(r,x,y,width,24,UI_ACCENT,1);vk_editor_text(r,x+9,y+7,label,UI_INK_STRONG,.28)
}

vk_draw_graph_help :: proc(r:^Vulkan_Backend) {vulkan_ui_rect(r,272,112,656,492,{20,27,35,250});vulkan_ui_outline(r,272,112,656,492,{102,205,235,255},3);vk_editor_text(r,304,140,"DIALOGUE GRAPH SHORTCUTS",{255,218,112,255},.72);vk_editor_text(r,746,142,"F1 TO CLOSE",{170,218,228,255},.42);columns:=[3][6]string{{"WHEEL  ZOOM AT CURSOR","MIDDLE DRAG  PAN","F  FRAME SELECTION","CTRL/CMD F  SEARCH","[ / ]  SEARCH RESULTS","MINIMAP CLICK  NAVIGATE"},{"CTRL/CMD Z  UNDO","CTRL/CMD SHIFT Z  REDO","CTRL/CMD S  SAVE","CTRL/CMD C/V  COPY/PASTE","CTRL/CMD D  DUPLICATE","DELETE  REMOVE"},{"SHIFT A  QUICK ADD","DRAG PORT  CONNECT","DRAG EMPTY  MARQUEE","SHIFT CLICK  MULTISELECT","LAYOUT  SELECTION/SCENE","PLAY  SELECTED/ENTRY"}};heads:=[3]string{"NAVIGATE","EDIT","AUTHOR"};for column in 0..<3 {x:=f32(304+column*202);vk_editor_text(r,x,188,heads[column],{102,205,235,255},.48);for row in 0..<6 do vk_editor_text(r,x,224+f32(row)*42,columns[column][row],{235,237,238,255},.34)};vk_editor_text(r,304,526,"Graph, Script, Localization, Conditions, and Effects share one undoable document.",{117,229,169,255},.34);vk_editor_text(r,304,558,"Check opens diagnostics; warnings never disable Play.",{205,211,218,255},.34)}

vk_draw_graph_overlay :: proc(r:^Vulkan_Backend,g:^Game) {
	vulkan_ui_rect(r,0,0,1200,720,{10,13,18,255});vulkan_ui_rect(r,0,0,1200,58,{22,28,36,255});vulkan_ui_rect(r,0,58,214,662,{16,21,28,255});vulkan_ui_rect(r,950,58,250,662,{18,23,30,255});vulkan_ui_rect(r,214,676,736,44,{20,26,33,255})
	if graph_state.view==.Graph {vk_button(r,{966,492,68,28},"DUP SCN");vk_button(r,{1040,492,68,28},graph_state.confirm==.Delete_Scene?"CONFIRM":"DEL SCN",graph_state.confirm==.Delete_Scene);vk_button(r,{1114,492,34,28},"UP");vk_button(r,{1152,492,34,28},"DN")}
	search_label:=graph_state.search_query==""?"SEARCH":graph_state.search_query;vk_button(r,graph_search_rect(),search_label);vk_button(r,graph_search_next_rect(),"NEXT")
	if graph_state.autosave_status!="" do vk_editor_text(r,480,690,graph_state.autosave_status,graph_state.autosave_status=="AUTOSAVE FAILED"?[4]u8{255,144,119,255}:[4]u8{170,218,228,255},.30)
	if graph_state.view==.Graph&&graph_state.selected_node>=0&&graph_state.selected_node<graph_document.node_count do vk_button(r,{966,532,104,28},graph_document.nodes[graph_state.selected_node].collapsed?"EXPAND":"COLLAPSE")
	if graph_state.view==.Graph&&graph_state.selected_node>=0&&graph_state.selected_node<graph_document.node_count {field:=graph_inspector_field();beat:=&graph_document.nodes[graph_state.selected_node].beat;vk_graph_button(r,{958,660,38,28},"<");vk_graph_button(r,{1000,660,150,28},fmt.tprintf("%s  %s",graph_inspector_field_label(field),graph_inspector_field_value(beat,field)));vk_graph_button(r,{1154,660,38,28},">")}
	else if graph_state.view==.Graph&&graph_state.active_scene>=0&&graph_state.active_scene<graph_document.scene_count {field:=graph_scene_inspector_field();scene:=&graph_document.scenes[graph_state.active_scene].scene;vk_graph_button(r,{958,660,38,28},"<");vk_graph_button(r,{1000,660,150,28},fmt.tprintf("%s  %s",graph_scene_inspector_label(field),graph_scene_inspector_value(scene,field)));vk_graph_button(r,{1154,660,38,28},">")}
	if graph_state.view==.Graph&&graph_state.selected_node>=0&&graph_state.selected_node<graph_document.node_count {beat:=graph_document.nodes[graph_state.selected_node].beat;if beat.kind=="stage" {vk_graph_button(r,{966,568,220,26},fmt.tprintf("ACTOR  %s",beat.actor));vk_graph_button(r,{966,598,220,26},fmt.tprintf("ANIMATION  %s",beat.animation));vk_graph_button(r,{966,628,220,26},fmt.tprintf("UI  %s",beat.ui))}else{vk_graph_button(r,{966,568,220,26},fmt.tprintf("CONDITION  %s",beat.condition_id));vk_graph_button(r,{966,598,220,26},fmt.tprintf("EFFECTS  %s",graph_join_strings(beat.effect_ids)));if beat.kind=="selector"||beat.kind=="objective"||beat.kind=="effect"||beat.kind=="interaction" do vk_graph_button(r,{966,628,220,26},fmt.tprintf("DOMAIN  %s",beat.domain_ref))}}
	vk_graph_ui_text(r,16,20,"GRAPH MODE",{255,218,112,255},.82);active:=graph_active_scene_id();vk_editor_text(r,16,48,active,{170,218,228,255},.36)
	vk_graph_tab_bar(r,graph_tab_bar_rect());views:=[5]string{"GRAPH","SCRIPT","LOCALIZE","CONDITIONS","EFFECTS"};for label,i in views do vk_graph_tab(r,graph_view_tab_rect(i),label,graph_state.view==Graph_View(i));vk_graph_button(r,{854,14,72,34},"SAVE");vk_graph_button(r,{934,14,72,34},"CHECK");vk_primary_button(r,{1014,14,68,34},"PLAY",graph_document.error_count==0);vk_graph_button(r,{1090,14,96,34},"CLOSE")
	vk_graph_ui_text(r,14,72,"SCENES",{158,168,180,255},.48);scene_start:=graph_scene_window_start();for row in 0..<min(8,graph_document.scene_count-scene_start) {i:=scene_start+row;scene_item:=graph_document.scenes[i];box:=graph_scene_rect(row);if graph_state.active_scene==i do vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{49,66,82,255});vulkan_ui_rect(r,box.x+5,box.y+6,4,18,{82,158,220,255});label:=strings.to_upper(scene_item.scene.id);if len(label)>25 do label=label[:25];vk_editor_text(r,box.x+16,box.y+9,label,graph_state.active_scene==i?[4]u8{248,247,242,255}:[4]u8{175,183,192,255},.36)}
	if graph_state.view==.Script {vk_draw_graph_script(r);return}else if graph_state.view==.Localization {vk_draw_graph_localization(r);if graph_state.selected_localization>=0&&graph_state.selected_localization<graph_document.localization_count {note:=graph_document.localizations[graph_state.selected_localization].note;if note=="" do note="CLICK TO ADD TRANSLATOR NOTE";vk_graph_button(r,{238,618,400,24},fmt.tprintf("NOTE  %s",note))};return}else if graph_state.view==.Conditions {vk_draw_graph_conditions(r);vk_graph_button(r,{786,610,134,28},"DUPLICATE");return}else if graph_state.view==.Effects {vk_draw_graph_effects(r);vk_graph_button(r,{786,610,134,28},"DUPLICATE");return}
	vk_graph_button(r,{14,356,58,28},"+SCENE");vk_graph_button(r,{76,356,58,28},"FIT");vk_graph_button(r,{138,356,68,28},"LAYOUT");vk_graph_ui_text(r,14,390,"ADD NODE",{158,168,180,255},.42);kinds:=[11]string{"line","choice","check","stage","interaction","effect","selector","objective","wait_event","subscene","end"};for kind,i in kinds {box:=graph_palette_rect(i);color:=graph_kind_color(kind);vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{25,31,40,255});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,color,2);vulkan_ui_rect(r,box.x,box.y,5,box.h,color);label:=strings.to_upper(kind);if kind=="wait_event" do label="WAIT EVENT";vk_editor_text(r,box.x+10,box.y+10,label,color,.30)}
	canvas:=graph_canvas_rect();vulkan_ui_rect(r,canvas.x,canvas.y,canvas.w,canvas.h,{12,16,22,255});for x:=canvas.x;x<canvas.x+canvas.w;x+=24 do for y:=canvas.y;y<canvas.y+canvas.h;y+=24 do vulkan_ui_rect(r,x,y,1,1,{76,88,102,85})
	// Everything authored in graph space is clipped to the viewport. Route
	// lanes may travel beyond visible nodes, but must never paint over chrome.
	vulkan_ui_scissor(r,canvas.x,canvas.y,canvas.w,canvas.h)
	scene:=graph_active_scene_id();for &node,from_index in graph_document.nodes[:graph_document.node_count] {if node.beat.scene!=scene do continue;for port_index in 0..<graph_output_count(&node.beat) {port,choice:=graph_output_port(&node.beat,port_index);target:=graph_port_target(&node.beat,port,choice);if target==nil||target^=="" do continue;to_index:=graph_node_index(scene,target^);if to_index<0||!graph_edge_screen_visible(node,graph_document.nodes[to_index]) do continue;vk_graph_edge(r,scene,from_index,to_index,port_index,{7,10,15,238},6);color:=graph_port_color(port);color[3]=220;vk_graph_edge(r,scene,from_index,to_index,port_index,color)}}
	if graph_state.edge_hover.active&&!graph_state.edge_drag.active&&!graph_state.edge_selection.active {edge:=graph_state.edge_hover;if edge.node>=0&&edge.node<graph_document.node_count {source:=&graph_document.nodes[edge.node];target:=graph_port_target(&source.beat,edge.port,edge.choice_index);if target!=nil {to:=graph_node_index(scene,target^);if to>=0 {for port_index in 0..<graph_output_count(&source.beat) {port,choice:=graph_output_port(&source.beat,port_index);if port==edge.port&&choice==edge.choice_index {vk_graph_edge(r,scene,edge.node,to,port_index,{205,238,255,255},4,true);break}}}}}}
	for &node,i in graph_document.nodes[:graph_document.node_count] {if node.beat.scene==scene&&graph_node_screen_visible(node) do vk_draw_graph_node(r,&node,i)}
	for &node,from_index in graph_document.nodes[:graph_document.node_count] {if node.beat.scene!=scene do continue;for port_index in 0..<graph_output_count(&node.beat) {port,choice:=graph_output_port(&node.beat,port_index);target:=graph_port_target(&node.beat,port,choice);if target==nil||target^=="" do continue;to_index:=graph_node_index(scene,target^);if to_index<0||!graph_edge_screen_visible(node,graph_document.nodes[to_index]) do continue;color:=graph_port_color(port);color[3]=220;vk_graph_edge_ports_foreground(r,from_index,to_index,port_index,color)}}
	minimap:=graph_minimap_rect();vulkan_ui_rect(r,minimap.x,minimap.y,minimap.w,minimap.h,{7,11,16,242});vulkan_ui_outline(r,minimap.x,minimap.y,minimap.w,minimap.h,{102,205,235,180},1)
	mini:=graph_minimap_layout()
	if mini.valid {
		// Only authored graph-world data enters this pass. The minimap and other
		// editor overlays are never sampled or recursively represented.
		for &node,from_index in graph_document.nodes[:graph_document.node_count] {if node.beat.scene!=scene do continue;from_h:=graph_node_world_height(node);for port_index in 0..<graph_output_count(&node.beat) {port,choice:=graph_output_port(&node.beat,port_index);target:=graph_port_target(&node.beat,port,choice);if target==nil||target^=="" do continue;to_index:=graph_node_index(scene,target^);if to_index<0 do continue;count:=max(1,graph_output_count(&node.beat));from_world:=Vec2{node.position.x+GRAPH_NODE_WIDTH,node.position.y+GRAPH_NODE_HEADER_HEIGHT+(f32(port_index)+.5)*(from_h-GRAPH_NODE_HEADER_HEIGHT)/f32(count)};to_node:=graph_document.nodes[to_index];to_world:=Vec2{to_node.position.x,to_node.position.y+GRAPH_NODE_HEADER_HEIGHT+(graph_node_world_height(to_node)-GRAPH_NODE_HEADER_HEIGHT)*.5};a,b:=graph_minimap_project(mini,from_world),graph_minimap_project(mini,to_world);edge_color:=graph_port_color(port);edge_color[3]=120;vk_graph_aa_segment(r,a,b,edge_color,1)} }
		for node,i in graph_document.nodes[:graph_document.node_count] {if node.beat.scene!=scene do continue;p:=graph_minimap_project(mini,node.position);w:=max(f32(2),GRAPH_NODE_WIDTH*mini.scale);h:=max(f32(2),graph_node_world_height(node)*mini.scale);color:=graph_kind_color(node.beat.kind);fill:=[4]u8{32,40,51,255};vulkan_ui_rect(r,p.x,p.y,w,h,fill);vulkan_ui_rect(r,p.x,p.y,max(f32(1),2*mini.scale),h,color);if graph_is_selected(i) do vulkan_ui_outline(r,p.x-1,p.y-1,w+2,h+2,{235,244,250,255},1)}
		canvas:=graph_canvas_rect();view_a:=graph_screen_to_world({canvas.x,canvas.y});view_b:=graph_screen_to_world({canvas.x+canvas.w,canvas.y+canvas.h});view_min:=Vec2{max(view_a.x,mini.world.x),max(view_a.y,mini.world.y)};view_max:=Vec2{min(view_b.x,mini.world.x+mini.world.w),min(view_b.y,mini.world.y+mini.world.h)}
		if view_max.x>view_min.x&&view_max.y>view_min.y {a,b:=graph_minimap_project(mini,view_min),graph_minimap_project(mini,view_max);vulkan_ui_rect(r,a.x,a.y,b.x-a.x,b.y-a.y,{102,205,235,22});vulkan_ui_outline(r,a.x,a.y,b.x-a.x,b.y-a.y,{205,238,255,230},1)}
	}
	if !graph_state.edge_selection.active do vk_graph_endpoint_emphasis(r,graph_state.edge_hover,{205,238,255,255})
	if graph_state.edge_drag.active {edge:=graph_state.edge_drag;color:=graph_port_color(edge.port);a,d:=edge.start,g.input.mouse_pos;span:=math.abs(d.x-a.x);handle:=clamp(span*.46,f32(32),f32(180));direction:=d.x>=a.x?f32(1):f32(-1);vk_graph_cubic(r,a,{a.x+handle*direction,a.y},{d.x-handle*direction,d.y},d,color,3);for node in graph_document.nodes[:graph_document.node_count] do if node.beat.scene==scene&&node.beat.id!=graph_document.nodes[edge.node].beat.id {box:=graph_input_rect(node);vulkan_ui_outline(r,box.x-3,box.y-3,box.w+6,box.h+6,color,2)}}
	if graph_state.edge_selection.active&&!graph_state.edge_drag.active {edge:=graph_state.edge_selection;if edge.node>=0&&edge.node<graph_document.node_count {source:=graph_document.nodes[edge.node];target:=graph_port_target(&source.beat,edge.port,edge.choice_index);if target!=nil {to:=graph_node_index(scene,target^);if to>=0 {selected_port:=-1;for j in 0..<graph_output_count(&source.beat) {port,choice:=graph_output_port(&source.beat,j);if port==edge.port&&choice==edge.choice_index {selected_port=j;break}};if selected_port>=0 do vk_graph_edge(r,scene,edge.node,to,selected_port,{255,245,190,255},5,true)}}}}
	if graph_state.edge_selection.active&&!graph_state.edge_drag.active do vk_graph_endpoint_emphasis(r,graph_state.edge_selection,{255,245,190,255})
	if graph_state.marquee.active {box:=graph_rect_normalized(graph_state.marquee.start,graph_state.marquee.current);vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{82,158,220,35});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,{119,190,230,230},1)}
	if graph_state.quick_add {x,y:=graph_state.quick_add_at.x,graph_state.quick_add_at.y;vulkan_ui_rect(r,x,y,176,34+f32(len(kinds))*31,{24,31,40,255});vulkan_ui_outline(r,x,y,176,34+f32(len(kinds))*31,{255,218,112,255},2);vk_graph_ui_text(r,x+10,y+11,"QUICK ADD",{255,218,112,255},.42);for kind,i in kinds {box:=graph_quick_rect(i);color:=graph_kind_color(kind);vulkan_ui_rect(r,box.x,box.y,box.w,box.h,i==graph_state.quick_add_selected?[4]u8{55,66,80,255}:[4]u8{31,39,49,255});vulkan_ui_rect(r,box.x,box.y,5,box.h,color);vk_editor_text(r,box.x+13,box.y+9,strings.to_upper(kind),color,.38)}}
	vulkan_ui_scissor_reset(r)
	inspector_view:=graph_inspector_viewport();inspector_y:=graph_state.inspector_scroll;if graph_state.selected_node>=0&&graph_state.selected_node<graph_document.node_count&&graph_document.nodes[graph_state.selected_node].beat.kind=="choice" do inspector_y=0;vulkan_ui_scissor(r,inspector_view.x,inspector_view.y,inspector_view.w,inspector_view.h);inspector_bottom:=f32(0)
	if graph_state.selected_node>=0&&graph_state.selected_node<graph_document.node_count {node:=graph_document.nodes[graph_state.selected_node];color:=graph_kind_color(node.beat.kind);vk_graph_ui_text(r,966,82-inspector_y,"NODE INSPECTOR",color,.54);id_bottom:=vk_editor_text_wrapped(r,966,112-inspector_y,222,node.beat.id,{248,247,242,255},.42);vk_editor_text(r,966,142-inspector_y,fmt.tprintf("TYPE  %s",strings.to_upper(node.beat.kind)),color,.38);speaker_bottom:=vk_editor_text_wrapped(r,966,174-inspector_y,222,fmt.tprintf("SPEAKER  %s",node.beat.speaker),{205,211,218,255},.34);text_bottom:=vk_editor_text_wrapped(r,966,204-inspector_y,222,fmt.tprintf("TEXT  %s",node.beat.text),{170,218,228,255},.34);summary_bottom:=vk_editor_text_wrapped(r,966,274-inspector_y,222,fmt.tprintf("SUMMARY  %s",node.beat.summary),{205,211,218,255},.31);vk_editor_text(r,966,328-inspector_y,fmt.tprintf("DURATION %.2f",node.beat.duration),{205,211,218,255},.31);picker_a:=node.beat.kind=="stage"?fmt.tprintf("CAMERA  %s",node.beat.camera):node.beat.kind=="wait_event"?fmt.tprintf("TRIGGER EVENT  %s",node.beat.event_id):node.beat.kind=="check"?fmt.tprintf("CLUE  %s",node.beat.clue):fmt.tprintf("INTERACTION  %s",node.beat.interaction);picker_b:=node.beat.kind=="stage"?fmt.tprintf("STAGING  %s",node.beat.actor_mark):fmt.tprintf("UI  %s",node.beat.ui);picker_a_bottom:=vk_editor_text_wrapped(r,966,369-inspector_y,222,picker_a,{65,194,210,255},.31);picker_b_bottom:=vk_editor_text_wrapped(r,966,399-inspector_y,222,picker_b,{117,229,169,255},.31);inspector_bottom=max(max(max(id_bottom,speaker_bottom),max(text_bottom,summary_bottom)),max(picker_a_bottom,picker_b_bottom))+inspector_y;vk_graph_button(r,{966,440,102,30},"SET ENTRY");vk_graph_button(r,{1078,440,110,30},node.beat.blocking?"BLOCKING":"LEAVEABLE",node.beat.blocking);_,has_spatial:=graph_node_spatial_marker(&node);vk_graph_button(r,{966,530,222,30},has_spatial?"OPEN IN BUILD MODE":"NO SPATIAL BINDING",false)}else{vk_graph_ui_text(r,966,82-inspector_y,"SCENE INSPECTOR",{255,218,112,255},.54);if graph_state.active_scene>=0 {scene_data:=graph_document.scenes[graph_state.active_scene].scene;id_bottom:=vk_editor_text_wrapped(r,966,114-inspector_y,222,scene_data.id,{248,247,242,255},.38);entry_bottom:=vk_editor_text_wrapped(r,966,144-inspector_y,222,fmt.tprintf("ENTRY  %s",scene_data.entry),{82,158,220,255},.34);source_bottom:=vk_editor_text_wrapped(r,966,174-inspector_y,222,fmt.tprintf("SOURCE  %s",scene_data.source),{205,211,218,255},.34);inspector_bottom=max(id_bottom,max(entry_bottom,source_bottom))+inspector_y}}
	graph_state.inspector_scroll_max=max(0,inspector_bottom-(inspector_view.y+inspector_view.h-8));if graph_state.selected_node>=0&&graph_state.selected_node<graph_document.node_count&&graph_document.nodes[graph_state.selected_node].beat.kind=="choice" do graph_state.inspector_scroll_max=0;graph_state.inspector_scroll=clamp(graph_state.inspector_scroll,0,graph_state.inspector_scroll_max);vulkan_ui_scissor_reset(r);if graph_state.selected_node>=0&&graph_state.selected_node<graph_document.node_count&&graph_document.nodes[graph_state.selected_node].beat.kind!="choice" {node:=graph_document.nodes[graph_state.selected_node];vk_graph_button(r,{966,440,102,30},"SET ENTRY");vk_graph_button(r,{1078,440,110,30},node.beat.blocking?"BLOCKING":"LEAVEABLE",node.beat.blocking);_,has_spatial:=graph_node_spatial_marker(&node);vk_graph_button(r,{966,530,222,30},has_spatial?"OPEN IN BUILD MODE":"NO SPATIAL BINDING",false)};if graph_state.inspector_scroll_max>0 {track:=Rect{1192,inspector_view.y+4,3,inspector_view.h-8};thumb_h:=max(f32(28),track.h*track.h/(track.h+graph_state.inspector_scroll_max));thumb_y:=track.y+(track.h-thumb_h)*(graph_state.inspector_scroll/graph_state.inspector_scroll_max);vulkan_ui_rect(r,track.x,track.y,track.w,track.h,{56,66,78,180});vulkan_ui_rect(r,track.x,thumb_y,track.w,thumb_h,{102,205,235,240})}
	if graph_state.selected_node>=0&&graph_state.selected_node<graph_document.node_count&&graph_document.nodes[graph_state.selected_node].beat.kind=="choice" {beat:=graph_document.nodes[graph_state.selected_node].beat;vulkan_ui_rect(r,958,156,234,326,{18,23,30,255});vk_graph_ui_text(r,966,162,"PLAYER CHOICES",{226,173,64,255},.40);tooltip:="";tooltip_box:=Rect{};page_count:=max(1,(len(beat.choice_labels)+4)/5);choice_start:=clamp(graph_state.choice_page,0,page_count-1)*5;choice_end:=min(choice_start+5,len(beat.choice_labels));for i in choice_start..<choice_end {row:=i-choice_start;label:=beat.choice_labels[i];y:=f32(184+row*48);dragging:=graph_state.choice_reorder.active&&graph_state.choice_reorder.node==graph_state.selected_node&&graph_state.choice_reorder.index==i;if dragging do vulkan_ui_rect(r,956,y-2,234,48,{49,66,82,255});vulkan_ui_rect(r,958,y,122,24,{28,35,44,255});vulkan_ui_outline(r,958,y,122,24,dragging?UI_ACCENT:[4]u8{226,173,64,180},dragging?2:1);display:=label;if len(display)>14 do display=display[:14];vk_editor_text(r,966,y+8,display,{248,247,242,255},.28);id_box,duplicate_box,delete_box:=Rect{1082,y,38,24},Rect{1122,y,26,24},Rect{1152,y,36,24};handle_box:=Rect{1122,y+25,66,20};vk_graph_choice_icon_button(r,id_box,.Edit_Id);vk_graph_choice_icon_button(r,duplicate_box,.Duplicate);vk_graph_choice_icon_button(r,delete_box,.Delete);condition:=beat.choice_conditions[i];if condition=="" do condition="ALWAYS";detail:=fmt.tprintf("%s · %s",beat.choice_ids[i],condition);if len(detail)>22 do detail=detail[:22];vk_editor_text(r,968,y+29,detail,{205,153,235,255},.22);vk_graph_choice_icon_button(r,handle_box,.Drag_Handle,dragging);if contains(id_box,g.input.mouse_pos) {tooltip="EDIT CHOICE ID";tooltip_box=id_box}else if contains(duplicate_box,g.input.mouse_pos) {tooltip="DUPLICATE CHOICE";tooltip_box=duplicate_box}else if contains(delete_box,g.input.mouse_pos) {tooltip="DELETE CHOICE";tooltip_box=delete_box}else if contains(handle_box,g.input.mouse_pos) {tooltip=dragging?"RELEASE TO PLACE":"DRAG TO REORDER";tooltip_box=handle_box}};vk_graph_button(r,{966,430,104,28},"+ CHOICE");vk_graph_button(r,{1076,460,52,24},"PREV");vk_graph_button(r,{1132,460,52,24},fmt.tprintf("%d/%d",graph_state.choice_page+1,page_count));vk_graph_choice_tooltip(r,tooltip_box,tooltip)}
	if graph_state.diagnostics_visible {vulkan_ui_rect(r,706,70,486,366,{8,12,18,248});vulkan_ui_outline(r,706,70,486,366,{255,218,112,255},2);vk_graph_ui_text(r,724,80,"GRAPH DIAGNOSTICS",{255,218,112,255},.48);for item,i in graph_document.diagnostics[:min(8,graph_document.diagnostic_count)] {box:=Rect{720,104+f32(i)*40,462,36};fill:=item.severity==.Error?[4]u8{67,31,34,255}:[4]u8{58,50,27,255};vulkan_ui_rect(r,box.x,box.y,box.w,box.h,fill);title:=fmt.tprintf("%s · %s",item.scene_id,item.node_id);vk_editor_text(r,box.x+8,box.y+6,title,{248,247,242,255},.27);message:=item.message;if len(message)>58 do message=message[:58];vk_editor_text(r,box.x+8,box.y+20,message,item.severity==.Error?[4]u8{255,144,119,255}:[4]u8{255,218,112,255},.25)}}
	if graph_state.field_edit.active {box:=graph_edit_rect();vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{8,12,18,255});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,{255,218,112,255},2);text:=graph_edit_text();cell:=f32(COURIER_CELL_WIDTH*.38);if ui.gui_text_edit_has_selection(&g.gui) {selection_start,selection_end:=ui.gui_text_edit_selection(&g.gui);selection_x:=box.x+8+f32(utf8_glyph_count(string(graph_state.field_edit.buffer[:selection_start])))*cell;selection_w:=max(f32(2),f32(utf8_glyph_count(string(graph_state.field_edit.buffer[selection_start:selection_end])))*cell);vulkan_ui_rect(r,selection_x,box.y+7,selection_w,24,{82,158,220,105})};vk_editor_text(r,box.x+8,box.y+12,text,{248,247,242,255},.38);caret_x:=box.x+8+f32(utf8_glyph_count(string(graph_state.field_edit.buffer[:g.gui.text_edit_caret])))*cell;vulkan_ui_rect(r,caret_x,box.y+8,2,22,{255,218,112,255});if graph_state.field_edit.multiline do vk_editor_text(r,box.x,box.y+44,"CMD/CTRL+ENTER TO COMMIT",{135,142,151,255},.30);if graph_state.field_edit.error!="" do vk_editor_text(r,box.x,box.y+58,graph_state.field_edit.error,{255,144,119,255},.32)}
	if graph_state.field_edit.active&&graph_state.field_edit.picker {count:=graph_picker_count(g,graph_state.field_edit.field);vk_editor_text(r,966,91,"TYPE TO FILTER  ·  ↑↓ OR WHEEL",{170,218,228,255},.28);if count==0 do vk_editor_text(r,966,153,"NO MATCHING AUTHORED TARGETS",{255,190,92,255},.30);for i in 0..<8 {candidate_index:=graph_state.field_edit.picker_offset+i;label:=graph_picker_label(g,graph_state.field_edit.field,candidate_index);if label=="" do break;box:=graph_picker_rect(i);vulkan_ui_rect(r,box.x,box.y,box.w,box.h,candidate_index==graph_state.field_edit.picker_selected?[4]u8{55,66,80,255}:[4]u8{20,27,36,255});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,{76,88,102,255},1);if len(label)>31 do label=label[:31];vk_editor_text(r,box.x+9,box.y+9,label,{205,225,232,255},.31)};if count>8 do vk_editor_text(r,966,392,fmt.tprintf("%d OF %d  ·  SCROLL FOR MORE",graph_state.field_edit.picker_selected+1,count),{170,218,228,255},.28)}
	vk_editor_text(r,230,690,fmt.tprintf("%d NODES  ·  %d ERRORS  ·  %d WARNINGS",graph_document.node_count,graph_document.error_count,graph_document.diagnostic_count-graph_document.error_count),graph_document.error_count>0?[4]u8{255,144,119,255}:[4]u8{117,229,169,255},.42);if graph_state.feedback_frames>0 do vk_editor_text(r,540,690,graph_state.feedback,graph_state.feedback_error?[4]u8{255,144,119,255}:[4]u8{117,229,169,255},.42);else if graph_state.edge_hover.active {edge:=graph_state.edge_hover;if edge.node>=0&&edge.node<graph_document.node_count {source:=&graph_document.nodes[edge.node];target:=graph_port_target(&source.beat,edge.port,edge.choice_index);if target!=nil do vk_editor_text(r,520,690,fmt.tprintf("%s  →  %s",graph_edge_footer_id(source.beat.id),graph_edge_footer_id(target^)),{205,238,255,255},.38)}}
}

vk_draw_graph_script :: proc(r:^Vulkan_Backend) {vulkan_ui_rect(r,220,64,724,610,{238,233,220,255});vk_graph_ui_text(r,242,76,"EDITABLE SCRIPT",{77,61,46,255},.58);scene:=graph_active_scene_id();row:=0;for node,i in graph_document.nodes[:graph_document.node_count] {if node.beat.scene!=scene do continue;box:=graph_script_row_rect(row);selected:=graph_state.selected_node==i;vulkan_ui_rect(r,box.x,box.y,box.w,box.h,selected?[4]u8{226,217,196,255}:[4]u8{246,241,228,255});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,selected?graph_kind_color(node.beat.kind):[4]u8{190,181,164,255},selected?2:1);target:=node.beat.next;if node.beat.kind=="check" do target=fmt.tprintf("%s / %s",node.beat.success,node.beat.failure);else if node.beat.kind=="choice" do target=graph_join_strings(node.beat.choice_targets);else if node.beat.kind=="subscene" do target=node.beat.subscene_id;if len(target)>22 do target=target[:22];vk_editor_text(r,box.x+8,box.y+8,fmt.tprintf("[%s] %s",strings.to_upper(node.beat.kind),node.beat.id),graph_kind_color(node.beat.kind),.31);vk_editor_text(r,box.x+360,box.y+8,fmt.tprintf("TARGET  %s",target),{92,115,135,255},.25);speaker:=node.beat.speaker;if speaker=="" do speaker="—";vk_editor_text(r,box.x+8,box.y+38,strings.to_upper(speaker),{92,72,52,255},.27);preview:=node.beat.text;if node.beat.kind=="choice" do preview=graph_join_strings(node.beat.choice_labels);if preview=="" do preview=node.beat.summary;if len(preview)>58 do preview=preview[:58];vk_editor_text(r,box.x+92,box.y+38,preview,{52,46,40,255},.31);if selected {vk_graph_button(r,{box.x+496,box.y+5,54,24},"UP");vk_graph_button(r,{box.x+554,box.y+5,54,24},"DOWN");vk_graph_button(r,{box.x+612,box.y+5,62,24},"DELETE")};row+=1;if row>=8 do break};vk_graph_button(r,{790,646,130,28},"+ LINE BEAT")}
vk_draw_graph_localization :: proc(r:^Vulkan_Backend) {vulkan_ui_rect(r,220,64,724,610,{15,20,27,255});vk_graph_ui_text(r,242,82,"LOCALIZATION & VO",{255,218,112,255},.56);vk_graph_button(r,{238,104,80,26},"SCENE",graph_state.localization_scene_only);vk_graph_button(r,{322,104,96,26},graph_state.localization_language==""?"ALL LANG":graph_state.localization_language);vk_graph_button(r,{422,104,96,26},graph_state.localization_status==""?"ALL STATUS":graph_state.localization_status);vk_graph_button(r,{522,104,116,26},"MISSING TEXT",graph_state.localization_missing_text);vk_graph_button(r,{642,104,116,26},"MISSING VO",graph_state.localization_missing_voice);headers:=[5]string{"NODE","LANGUAGE","TRANSLATION","STATUS","VOICE"};xs:=[5]f32{242,388,482,724,806};for label,i in headers do vk_graph_ui_text(r,xs[i],140,label,{170,218,228,255},.31);visible:=0;for row in 0..<10 {i:=graph_localization_visible_index(row);if i<0 do break;visible+=1;item:=graph_document.localizations[i];box:=graph_localization_row_rect(row);selected:=graph_state.selected_localization==i;vulkan_ui_rect(r,box.x,box.y,box.w,box.h,selected?[4]u8{43,57,70,255}:[4]u8{24,31,40,255});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,selected?[4]u8{255,218,112,255}:[4]u8{70,82,94,255},selected?2:1);node:=item.node_id;if len(node)>19 do node=node[:19];text:=item.text;if len(text)>30 do text=text[:30];vk_editor_text(r,box.x+6,box.y+14,node,{235,237,238,255},.27);vk_editor_text(r,box.x+154,box.y+14,item.language,{205,211,218,255},.27);vk_editor_text(r,box.x+248,box.y+14,text,{205,225,232,255},.27);vk_editor_text(r,box.x+490,box.y+14,item.status,item.status=="final"?[4]u8{117,229,169,255}:[4]u8{255,218,112,255},.27);vk_editor_text(r,box.x+572,box.y+14,item.voice,item.voice!=""?[4]u8{117,229,169,255}:[4]u8{135,142,151,255},.27)};if visible==0 {vk_editor_text(r,366,270,"NO TRANSLATIONS MATCH THESE FILTERS",{135,142,151,255},.40)};vk_graph_button(r,{666,646,122,28},"+ TRANSLATION");vk_graph_button(r,{794,646,126,28},"DELETE")}
vk_draw_graph_conditions :: proc(r:^Vulkan_Backend) {vulkan_ui_rect(r,220,64,724,610,{15,20,27,255});vk_graph_ui_text(r,242,82,"REUSABLE CONDITIONS",{255,218,112,255},.56);for item,i in graph_document.conditions[:min(13,graph_document.condition_count)] {box:=graph_definition_row_rect(i);selected:=graph_state.selected_condition==i;vulkan_ui_rect(r,box.x,box.y,box.w,box.h,selected?[4]u8{55,49,72,255}:[4]u8{25,31,40,255});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,selected?[4]u8{174,116,215,255}:[4]u8{70,82,94,255},selected?2:1);vk_editor_text(r,box.x+8,box.y+11,item.id,{235,237,238,255},.29);vk_editor_text(r,box.x+232,box.y+11,strings.to_upper(story_condition_kind_text(item.kind)),{205,153,235,255},.27)};if graph_state.selected_condition>=0&&graph_state.selected_condition<graph_document.condition_count {item:=&graph_document.conditions[graph_state.selected_condition];vk_graph_ui_text(r,650,112,"CONDITION INSPECTOR",{205,153,235,255},.42);vk_button(r,{650,144,270,32},item.id);vk_button(r,{650,190,270,32},strings.to_upper(story_condition_kind_text(item.kind)));field_count:=0;for slot in 0..<5 {label,value,visible:=graph_condition_slot(item,slot);if !visible do continue;field_count+=1;box:=Rect{650,236+f32(slot)*58,270,52};vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{25,31,40,255});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,{174,116,215,180},1);vk_editor_text(r,box.x+8,box.y+7,label,{205,153,235,255},.24);display:=value;if display=="" do display="CLICK TO SET";if len(display)>31 do display=display[:31];vk_editor_text(r,box.x+8,box.y+27,display,{235,237,238,255},.29)};if field_count==0 do vk_editor_text(r,650,244,"THIS CONDITION HAS NO PARAMETERS",{135,142,151,255},.30)};vk_graph_button(r,{650,646,128,28},"+ CONDITION");vk_graph_button(r,{786,646,134,28},"DELETE")}
vk_draw_graph_effects :: proc(r:^Vulkan_Backend) {vulkan_ui_rect(r,220,64,724,610,{15,20,27,255});vk_graph_ui_text(r,242,82,"REUSABLE EFFECTS",{255,218,112,255},.56);for item,i in graph_document.effects[:min(13,graph_document.effect_count)] {box:=graph_definition_row_rect(i);selected:=graph_state.selected_effect==i;vulkan_ui_rect(r,box.x,box.y,box.w,box.h,selected?[4]u8{39,66,56,255}:[4]u8{25,31,40,255});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,selected?[4]u8{80,181,119,255}:[4]u8{70,82,94,255},selected?2:1);vk_editor_text(r,box.x+8,box.y+11,item.id,{235,237,238,255},.29);vk_editor_text(r,box.x+232,box.y+11,strings.to_upper(story_effect_kind_text(item.kind)),{117,229,169,255},.27)};if graph_state.selected_effect>=0&&graph_state.selected_effect<graph_document.effect_count {item:=&graph_document.effects[graph_state.selected_effect];vk_graph_ui_text(r,650,112,"EFFECT INSPECTOR",{117,229,169,255},.42);vk_button(r,{650,144,270,32},item.id);vk_button(r,{650,190,270,32},strings.to_upper(story_effect_kind_text(item.kind)));for slot in 0..<5 {label,value,visible:=graph_effect_slot(item,slot);if !visible do continue;box:=Rect{650,236+f32(slot)*58,270,52};vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{25,31,40,255});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,{80,181,119,180},1);vk_editor_text(r,box.x+8,box.y+7,label,{117,229,169,255},.24);display:=value;if display=="" do display="CLICK TO SET";if len(display)>31 do display=display[:31];vk_editor_text(r,box.x+8,box.y+27,display,{235,237,238,255},.29)}};vk_graph_button(r,{650,646,128,28},"+ EFFECT");vk_graph_button(r,{786,646,134,28},"DELETE")}

editor_selection_toolbar_origin :: proc(g:^Game)->(Vec2,bool) {
	if editor_state.object_rotate_active do return {},false
	if editor_state.selection_count!=1 do return {},false
	selected:=editor_state.selection[0];screen:=Vec2{};found:=false
	if selected.kind==.Room||selected.kind==.Vertex||selected.kind==.Edge {index:=level_room_index(&level_document,selected.entity_id);if index>=0&&len(level_document.rooms[index].points)>0 {max_y:f32=-1e30;visible_count:f32=0;for p in level_document.rooms[index].points {projected,visible:=editor_world_screen(g,p);if !visible do continue;screen.x+=projected.x;max_y=max(max_y,projected.y);visible_count+=1};if visible_count>0 {screen.x/=visible_count;screen.y=max_y;found=true}}} else if selected.kind==.Foundation {index:=level_foundation_index(&level_document,selected.entity_id);if index>=0&&len(level_document.foundations[index].points)>0 {max_y:f32=-1e30;visible_count:f32=0;for p in level_document.foundations[index].points {projected,visible:=editor_world_screen(g,p);if !visible do continue;screen.x+=projected.x;max_y=max(max_y,projected.y);visible_count+=1};if visible_count>0 {screen.x/=visible_count;screen.y=max_y;found=true}}} else if selected.kind==.Object {index:=level_object_index(&level_document,selected.entity_id);if index>=0 {screen,found=editor_world_screen(g,level_document.objects[index].position)}} else if selected.kind==.Opening {index:=level_opening_index(&level_document,selected.entity_id);if index>=0 {opening:=level_document.openings[index];path_index:=level_path_index(&level_document,opening.host_path);if path_index>=0&&opening.segment>=0&&opening.segment<len(level_document.paths[path_index].points)-1 {a,b:=level_document.paths[path_index].points[opening.segment],level_document.paths[path_index].points[opening.segment+1];screen,found=editor_world_screen(g,{a.x+(b.x-a.x)*opening.position,a.y+(b.y-a.y)*opening.position})}}} else if selected.kind==.Path||selected.kind==.Water||selected.kind==.Vertical_Link {screen,found=level_selection_position(&level_document,selected);if found do screen,found=editor_world_screen(g,screen)}
	if !found&&selected.kind==.Roof {index:=level_roof_index(&level_document,selected.entity_id);if index>=0 {room_index:=level_room_index(&level_document,level_document.roofs[index].room_id);if room_index>=0 do screen,found=editor_world_screen(g,level_room_center(&level_document.rooms[room_index]))}}
	if !found do return {},false
	return editor_selection_toolbar_position(screen),true
}
EDITOR_SELECTION_ACTION_SIZE := Vec2{36,30}
EDITOR_SELECTION_ACTION_PITCH:f32=40
editor_selection_action_rect :: proc(g:^Game,index:int)->(Rect,bool) {origin,ok:=editor_selection_toolbar_origin(g);return {origin.x+f32(index)*EDITOR_SELECTION_ACTION_PITCH,origin.y,EDITOR_SELECTION_ACTION_SIZE.x,EDITOR_SELECTION_ACTION_SIZE.y},ok}
vk_editor_action_tooltip :: proc(r:^Vulkan_Backend,box:Rect,label:string,mouse:Vec2) {
	if !contains(box,mouse) do return
	width:=f32(utf8_glyph_count(label))*7+16
	x:=clamp(box.x+(box.w-width)*.5,f32(76),f32(1188)-width);y:=box.y-30
	// Inspector controls have dense rows above and below them. Keep their
	// tooltips outside the panel so they never cover labels or color swatches.
	if box.x>=900 {x=max(f32(76),box.x-width-10);y=box.y+(box.h-24)*.5} else if y<64 do y=box.y+box.h+6
	vk_panel(r,x,y,width,24)
	vk_editor_text(r,x+8,y+6,label,{255,218,112,255},.60)
}

vk_editor_numeric_field :: proc(
	r:^Vulkan_Backend,
	box:Rect,
	field:Editor_Numeric_Field,
	prefix, value:string,
	mouse:Vec2,
	inactive_tooltip:="CLICK TO TYPE EXACT VALUE",
	active_tooltip:="ENTER APPLY · TAB NEXT · ESC CANCEL",
) {
	label:=value
	if editor_state.numeric_field==field {
		text:=editor_numeric_text()
		label=editor_state.numeric_replace_on_input?fmt.tprintf("%s[%s]",prefix,text):fmt.tprintf("%s%s |",prefix,text)
	}
	vk_button(r,box,label)
	vk_editor_action_tooltip(r,box,editor_state.numeric_field==field?active_tooltip:inactive_tooltip,mouse)
}

vk_editor_line :: proc(r:^Vulkan_Backend,a,b:Vec2,color:[4]u8,thickness:f32=3) {
	dx,dy:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dy*dy)));steps:=max(1,int(length/max(f32(1),thickness*.65)));for i in 0..=steps {t:=f32(i)/f32(steps);vulkan_ui_rect(r,a.x+dx*t-thickness*.5,a.y+dy*t-thickness*.5,thickness,thickness,color)}
}
vk_editor_measure_badge :: proc(r:^Vulkan_Backend,a,b:Vec2,label:string,color:[4]u8) {width:=f32(utf8_glyph_count(label))*7+16;x:=(a.x+b.x-width)*.5;y:=(a.y+b.y)*.5-28;vulkan_ui_rect(r,x,y,width,24,{10,14,18,238});vulkan_ui_outline(r,x,y,width,24,color,1);vk_editor_text(r,x+8,y+6,label,color,.42)}

vk_draw_build_overlay :: proc(r:^Vulkan_Backend,g:^Game) {
	editor_ui_mouse=g.input.mouse_pos
	if editor_state.box_select_active {a,a_ok:=editor_world_screen(g,editor_state.box_select_start);b,b_ok:=editor_world_screen(g,editor_state.box_select_current);if a_ok&&b_ok {x,y:=min(a.x,b.x),min(a.y,b.y);w,h:=math.abs(a.x-b.x),math.abs(a.y-b.y);vulkan_ui_rect(r,x,y,w,h,{82,190,224,32});vulkan_ui_outline(r,x,y,w,h,{102,205,235,255},2)}}
	if editor_state.view==.Collision||editor_state.view==.Navmesh {for i in 0..<HOUSE_NAV_CELLS {walkable:=house_nav_walkable[i];if editor_state.view==.Collision&&walkable do continue;if editor_state.view==.Navmesh&&!walkable do continue;center:=nav_cell_center(i);a,a_ok:=editor_world_screen(g,{center.x-HOUSE_NAV_CELL*.45,center.y-HOUSE_NAV_CELL*.45});b,b_ok:=editor_world_screen(g,{center.x+HOUSE_NAV_CELL*.45,center.y+HOUSE_NAV_CELL*.45});if a_ok&&b_ok {color:=editor_state.view==.Navmesh?[4]u8{70,224,140,72}:[4]u8{244,91,91,92};vulkan_ui_rect(r,min(a.x,b.x),min(a.y,b.y),math.abs(a.x-b.x),math.abs(a.y-b.y),color)}}}
	if editor_state.view==.Lighting||g.build_tool==.Light {for light in level_document.lights {if light.story!=level_document.active_story do continue;screen,visible:=editor_world_screen(g,light.position);if !visible do continue;edge,_:=editor_world_screen(g,{light.position.x+light.range,light.position.y});radius:=max(10,math.abs(edge.x-screen.x));selected:=editor_state.selection_count>0&&editor_state.selection[0].kind==.Light&&editor_state.selection[0].entity_id==light.id;color:=light.color;color[3]=selected?u8(230):u8(78);segments:=48;for segment in 0..<segments {a:=f32(segment)*f32(math.PI*2)/f32(segments);b:=f32(segment+1)*f32(math.PI*2)/f32(segments);vk_editor_line(r,{screen.x+f32(math.cos(f64(a)))*radius,screen.y+f32(math.sin(f64(a)))*radius},{screen.x+f32(math.cos(f64(b)))*radius,screen.y+f32(math.sin(f64(b)))*radius},color,selected?2:1)};vulkan_ui_rect(r,screen.x-7,screen.y-7,14,14,{255,244,190,235});vulkan_ui_outline(r,screen.x-7,screen.y-7,14,14,selected?[4]u8{102,205,235,255}:[4]u8{144,112,54,255},selected?3:1);if light.kind==.Spot {angle:=light.facing*f32(math.PI)/180;tip:=Vec2{screen.x+f32(math.cos(f64(angle)))*radius,screen.y+f32(math.sin(f64(angle)))*radius};vk_editor_line(r,screen,tip,color,2)}}}
	if editor_state.view==.Stories_Below {for room in level_document.rooms {if room.story>=level_document.active_story do continue;alpha:=u8(max(45,150-(level_document.active_story-room.story)*35));for point,i in room.points {next:=room.points[(i+1)%len(room.points)];a,a_ok:=editor_world_screen(g,point);b,b_ok:=editor_world_screen(g,next);if a_ok&&b_ok do vk_editor_line(r,a,b,{119,190,213,alpha},2)}}}
	if g.build_tool==.Terrain {center:=editor_state.terrain_stroke_current;if !editor_state.terrain_stroke_active {wx,wy,ok:=editor_mouse_ground(g,g.input.mouse_pos);if ok do center={wx,wy}};effective_mode:=editor_effective_terrain_mode(editor_state.terrain_mode,g.keys[.LCTRL]||g.keys[.RCTRL]);brush_color:=[4]u8{102,205,143,255};#partial switch effective_mode {case .Lower:brush_color={255,144,119,255};case .Smooth:brush_color={119,190,213,255};case .Flatten:brush_color={255,211,92,255};case .Slope:brush_color={186,139,214,255}};for segment in 0..<24 {angle:=f32(segment)*f32(math.PI*2)/24;point:=Vec2{center.x+f32(math.cos(f64(angle)))*editor_state.terrain_radius,center.y+f32(math.sin(f64(angle)))*editor_state.terrain_radius};screen,visible:=editor_world_screen(g,point);if visible&&editor_viewport_contains(screen,g.build_tool) do vulkan_ui_rect(r,screen.x-2,screen.y-2,4,4,brush_color)};if editor_state.terrain_stroke_active {for segment in 0..=16 {t:=f32(segment)/16;point:=Vec2{editor_state.terrain_stroke_start.x+(editor_state.terrain_stroke_current.x-editor_state.terrain_stroke_start.x)*t,editor_state.terrain_stroke_start.y+(editor_state.terrain_stroke_current.y-editor_state.terrain_stroke_start.y)*t};screen,visible:=editor_world_screen(g,point);if visible&&editor_viewport_contains(screen,g.build_tool) do vulkan_ui_rect(r,screen.x-3,screen.y-3,6,6,brush_color)}}}
	if editor_state.selection_count>0&&!editor_state.drag_active {
		selected:=editor_state.selection[0]
		if selected.kind==.Room||selected.kind==.Vertex||selected.kind==.Edge {index:=level_room_index(&level_document,selected.entity_id);if index>=0 {room:=level_document.rooms[index];for point,i in room.points {next:=room.points[(i+1)%len(room.points)];screen,visible:=editor_world_screen(g,point);next_screen,next_visible:=editor_world_screen(g,next);on_edge:=selected.kind==.Edge&&selected.sub_index==i;if visible&&next_visible {vk_editor_line(r,screen,next_screen,on_edge?[4]u8{255,218,112,255}:[4]u8{102,205,225,210},on_edge?3:2)};if visible&&editor_viewport_contains(screen,g.build_tool) {on:=selected.kind==.Vertex&&selected.sub_index==i;vulkan_ui_rect(r,screen.x-(on?6:4),screen.y-(on?6:4),on?12:8,on?12:8,on?[4]u8{255,218,112,255}:[4]u8{102,205,143,255});vulkan_ui_outline(r,screen.x-(on?6:4),screen.y-(on?6:4),on?12:8,on?12:8,{20,28,34,255},1)};mid:=Vec2{(point.x+next.x)*.5,(point.y+next.y)*.5};mid_screen,mid_visible:=editor_world_screen(g,mid);if mid_visible&&editor_viewport_contains(mid_screen,g.build_tool) {vulkan_ui_rect(r,mid_screen.x-(on_edge?5:3),mid_screen.y-(on_edge?5:3),on_edge?10:6,on_edge?10:6,on_edge?[4]u8{255,218,112,255}:[4]u8{119,190,213,255});if on_edge {dx,dy:=next.x-point.x,next.y-point.y;length:=f32(math.sqrt(f64(dx*dx+dy*dy)));label:=fmt.tprintf("%.2fm",length);label_width:=f32(utf8_glyph_count(label))*7+14;vulkan_ui_rect(r,mid_screen.x-label_width*.5,mid_screen.y-28,label_width,22,{10,14,18,235});vk_editor_text(r,mid_screen.x-label_width*.5+7,mid_screen.y-23,label,{255,218,112,255},.42)}}};center:=level_room_center(&room);center_screen,center_visible:=editor_world_screen(g,center);if center_visible {area:=math.abs(level_polygon_area(room.points[:]));summary:=fmt.tprintf("%.1f SQM  ·  %.2fm",area,room.platform_height);width:=f32(utf8_glyph_count(summary))*7+18;vulkan_ui_rect(r,center_screen.x-width*.5,center_screen.y-15,width,28,{10,14,18,220});vulkan_ui_outline(r,center_screen.x-width*.5,center_screen.y-15,width,28,{102,205,225,190},1);vk_editor_text(r,center_screen.x-width*.5+9,center_screen.y-7,summary,{248,247,242,255},.42)}}}
		if selected.kind==.Foundation {index:=level_foundation_index(&level_document,selected.entity_id);if index>=0 {foundation:=level_document.foundations[index];selected_point:=editor_control_point_index(selected);for point,i in foundation.points {next:=foundation.points[(i+1)%len(foundation.points)];screen,visible:=editor_world_screen(g,point);next_screen,next_visible:=editor_world_screen(g,next);if visible&&next_visible do vk_editor_line(r,screen,next_screen,{102,225,143,255},4);on:=selected_point==i;if visible&&editor_viewport_contains(screen,g.build_tool) {vulkan_ui_rect(r,screen.x-(on?7:5),screen.y-(on?7:5),on?14:10,on?14:10,on?[4]u8{117,229,169,255}:[4]u8{255,218,112,255});vulkan_ui_outline(r,screen.x-(on?7:5),screen.y-(on?7:5),on?14:10,on?14:10,{20,28,34,255},on?2:1)}}}}
		if selected.kind==.Roof {index:=level_roof_index(&level_document,selected.entity_id);if index>=0 {room_index:=level_room_index(&level_document,level_document.roofs[index].room_id);if room_index>=0 {room:=level_document.rooms[room_index];for point,i in room.points {next:=room.points[(i+1)%len(room.points)];screen,visible:=editor_world_screen(g,point);next_screen,next_visible:=editor_world_screen(g,next);if visible&&next_visible do vk_editor_line(r,screen,next_screen,{255,218,112,255},5)}}}}
		if selected.kind==.Object {index:=level_object_index(&level_document,selected.entity_id);if index>=0 {object:=level_document.objects[index];screen,visible:=editor_world_screen(g,object.position);if visible&&editor_viewport_contains(screen,g.build_tool) {vulkan_ui_outline(r,screen.x-18,screen.y-18,36,36,{255,218,112,255},3);vk_editor_line(r,{screen.x-25,screen.y},{screen.x-9,screen.y},{102,225,235,255},3);vk_editor_line(r,{screen.x+9,screen.y},{screen.x+25,screen.y},{102,225,235,255},3);vk_editor_line(r,{screen.x,screen.y-25},{screen.x,screen.y-9},{102,225,235,255},3);vk_editor_line(r,{screen.x,screen.y+9},{screen.x,screen.y+25},{102,225,235,255},3)}}}
		if selected.kind==.Opening {index:=level_opening_index(&level_document,selected.entity_id);if index>=0 {opening:=level_document.openings[index];path_index:=level_path_index(&level_document,opening.host_path);if path_index>=0&&opening.segment>=0&&opening.segment<len(level_document.paths[path_index].points)-1 {a,b:=level_document.paths[path_index].points[opening.segment],level_document.paths[path_index].points[opening.segment+1];dx,dy:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dy*dy)));if length>.001 {half:=opening.width*.5/length;start:=Vec2{a.x+dx*(opening.position-half),a.y+dy*(opening.position-half)};finish:=Vec2{a.x+dx*(opening.position+half),a.y+dy*(opening.position+half)};start_screen,start_ok:=editor_world_screen(g,start);finish_screen,finish_ok:=editor_world_screen(g,finish);if start_ok&&finish_ok {vk_editor_line(r,start_screen,finish_screen,{255,218,112,255},7);vulkan_ui_rect(r,start_screen.x-5,start_screen.y-5,10,10,{102,205,235,255});vulkan_ui_rect(r,finish_screen.x-5,finish_screen.y-5,10,10,{102,205,235,255})}}}}}
		if selected.kind==.Path {index:=level_path_index(&level_document,selected.entity_id);if index>=0 {path:=level_document.paths[index];selected_point:=editor_control_point_index(selected);for point,i in path.points {screen,visible:=editor_world_screen(g,point);on:=selected_point==i;if visible&&editor_viewport_contains(screen,g.build_tool) {vulkan_ui_rect(r,screen.x-(on?7:5),screen.y-(on?7:5),on?14:10,on?14:10,on?[4]u8{117,229,169,255}:[4]u8{255,218,112,255});vulkan_ui_outline(r,screen.x-(on?7:5),screen.y-(on?7:5),on?14:10,on?14:10,{20,28,34,255},on?2:1)};if i>0 {previous,previous_visible:=editor_world_screen(g,path.points[i-1]);if visible&&previous_visible do vk_editor_line(r,previous,screen,{102,225,235,255},4)}}}}
		if selected.kind==.Water {index:=level_water_index(&level_document,selected.entity_id);if index>=0 {water:=level_document.waters[index];selected_point:=editor_control_point_index(selected);for point,i in water.points {screen,visible:=editor_world_screen(g,point);next,next_visible:=editor_world_screen(g,water.points[(i+1)%len(water.points)]);if visible&&next_visible do vk_editor_line(r,screen,next,{82,210,245,255},4);on:=selected_point==i;if visible&&editor_viewport_contains(screen,g.build_tool) {vulkan_ui_rect(r,screen.x-(on?7:5),screen.y-(on?7:5),on?14:10,on?14:10,on?[4]u8{117,229,169,255}:[4]u8{255,218,112,255});vulkan_ui_outline(r,screen.x-(on?7:5),screen.y-(on?7:5),on?14:10,on?14:10,{20,28,34,255},on?2:1)}}}}
		if selected.kind==.Vertical_Link {index:=level_vertical_link_index(&level_document,selected.entity_id);if index>=0 {link:=level_document.vertical_links[index];start,start_visible:=editor_world_screen(g,link.start);finish,finish_visible:=editor_world_screen(g,link.finish);if start_visible&&finish_visible {vk_editor_line(r,start,finish,{186,139,235,255},6);points:=[2]Vec2{start,finish};selected_point:=editor_control_point_index(selected);for point,i in points {on:=selected_point==i;vulkan_ui_rect(r,point.x-(on?9:7),point.y-(on?9:7),on?18:14,on?18:14,on?[4]u8{117,229,169,255}:[4]u8{255,218,112,255});vulkan_ui_outline(r,point.x-(on?9:7),point.y-(on?9:7),on?18:14,on?18:14,{20,28,34,255},on?2:1)}}}}
	}
	if editor_state.selection_count==1&&editor_state.selection[0].kind==.Object&&!editor_state.drag_active {index:=level_object_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {object:=level_document.objects[index];angle:=editor_state.object_rotate_active?editor_state.object_rotate_preview:object.rotation;handle,visible:=editor_object_rotate_handle_rect(g,angle);center,center_visible:=editor_world_screen(g,object.position);if visible&&center_visible {handle_center:=Vec2{handle.x+handle.w*.5,handle.y+handle.h*.5};color:=editor_state.object_rotate_active?[4]u8{117,229,169,255}:[4]u8{255,218,112,255};vk_editor_line(r,center,handle_center,color,2);vulkan_ui_rect(r,handle.x,handle.y,handle.w,handle.h,{24,31,38,245});vulkan_ui_outline(r,handle.x,handle.y,handle.w,handle.h,color,3);if editor_state.object_rotate_active do vk_editor_measure_badge(r,center,handle_center,fmt.tprintf("ANGLE %d°  ·  ALT FREE",int(angle)%360),color);else do vk_editor_action_tooltip(r,handle,"DRAG TO ROTATE · 15° SNAP · ALT FREE",g.input.mouse_pos)}}}
	if editor_state.selection_count>1 {for selection,i in editor_state.selection[:editor_state.selection_count] {position,ok:=level_selection_position(&level_document,selection);if !ok do continue;screen,visible:=editor_world_screen(g,position);if visible {vulkan_ui_rect(r,screen.x-8,screen.y-8,16,16,{30,42,50,220});vulkan_ui_outline(r,screen.x-8,screen.y-8,16,16,{102,205,235,255},2);vk_editor_text(r,screen.x-3,screen.y-6,fmt.tprintf("%d",i+1),{255,255,255,255},.25)}}}
	// Gameplay bindings stay visible as compact atlas-backed pins instead of
	// requiring a permanent marker panel over the lot.
	if g.build_tool==.Marker||editor_state.view==.Markers {for marker in level_document.markers {if marker.story!=level_document.active_story do continue;screen,visible:=editor_world_screen(g,marker.position);if !visible||!editor_viewport_contains(screen,g.build_tool) do continue;selected:=editor_state.selection_count>0&&editor_state.selection[0].kind==.Marker&&editor_state.selection[0].entity_id==marker.id;icon:=MARKER_KIND_ICONS[int(marker.kind)];vk_level_icon_button(r,{screen.x-14,screen.y-14,28,28},icon[0],icon[1],selected);if marker.radius>.1 {edge,_:=editor_world_screen(g,{marker.position.x+marker.radius,marker.position.y});vk_editor_line(r,{screen.x,screen.y+17},{edge.x,screen.y+17},selected?[4]u8{255,218,112,210}:[4]u8{102,205,225,155},1)}}}
	if g.build_tool==.Room&&editor_state.room_rectangle_active {a,b:=editor_state.room_rectangle_start,editor_state.room_rectangle_current;corners:=[4]Vec2{{a.x,a.y},{b.x,a.y},{b.x,b.y},{a.x,b.y}};state:=editor_state.room_rectangle_preview.state;color:=state==.Blocked?[4]u8{255,144,119,255}:state==.Warning?[4]u8{255,210,112,255}:[4]u8{102,225,143,255};for point,i in corners {next:=corners[(i+1)%4];screen,visible:=editor_world_screen(g,point);next_screen,next_visible:=editor_world_screen(g,next);if visible&&next_visible do vk_editor_line(r,screen,next_screen,color,3);if visible do vulkan_ui_rect(r,screen.x-5,screen.y-5,10,10,color)};center:=Vec2{(a.x+b.x)*.5,(a.y+b.y)*.5};center_screen,visible:=editor_world_screen(g,center);if visible {width,height:=math.abs(b.x-a.x),math.abs(b.y-a.y);label:=state==.Blocked?editor_state.room_rectangle_preview.message:fmt.tprintf("%.2fm × %.2fm  ·  %.1f SQM",width,height,width*height);label_width:=f32(utf8_glyph_count(label))*7+18;vulkan_ui_rect(r,center_screen.x-label_width*.5,center_screen.y-14,label_width,28,{10,14,18,230});vulkan_ui_outline(r,center_screen.x-label_width*.5,center_screen.y-14,label_width,28,color,1);vk_editor_text(r,center_screen.x-label_width*.5+9,center_screen.y-6,label,color,.42)}}
	if g.build_tool==.Foundation&&editor_state.foundation_rectangle_active {a,b:=editor_state.foundation_rectangle_start,editor_state.foundation_rectangle_current;corners:=[4]Vec2{{a.x,a.y},{b.x,a.y},{b.x,b.y},{a.x,b.y}};state:=editor_state.foundation_rectangle_preview.state;color:=state==.Blocked?[4]u8{255,144,119,255}:state==.Warning?[4]u8{255,210,112,255}:[4]u8{102,225,143,255};for point,i in corners {next:=corners[(i+1)%4];screen,visible:=editor_world_screen(g,point);next_screen,next_visible:=editor_world_screen(g,next);if visible&&next_visible do vk_editor_line(r,screen,next_screen,color,5);if visible do vk_level_icon(r,1,6,screen.x-7,screen.y-7,14)};center:=Vec2{(a.x+b.x)*.5,(a.y+b.y)*.5};center_screen,visible:=editor_world_screen(g,center);if visible {label:=state==.Blocked?editor_state.foundation_rectangle_preview.message:fmt.tprintf("%s  ·  %.1f SQM",strings.to_upper(level_foundation_kind_name(editor_state.foundation_kind)),math.abs(b.x-a.x)*math.abs(b.y-a.y));label_width:=f32(utf8_glyph_count(label))*7+18;vulkan_ui_rect(r,center_screen.x-label_width*.5,center_screen.y-14,label_width,28,{10,14,18,230});vulkan_ui_outline(r,center_screen.x-label_width*.5,center_screen.y-14,label_width,28,color,1);vk_editor_text(r,center_screen.x-label_width*.5+9,center_screen.y-6,label,color,.42)}}
	if g.build_tool==.Foundation&&editor_state.foundation_mode==.Polygon&&editor_state.foundation_draw_count>0 {color:=editor_state.foundation_polygon_preview.state==.Blocked?[4]u8{255,144,119,255}:[4]u8{102,225,143,255};for i in 0..<editor_state.foundation_draw_count {screen,visible:=editor_world_screen(g,editor_state.foundation_draw_points[i]);if !visible do continue;vk_level_icon(r,1,6,screen.x-7,screen.y-7,14);if i>0 {previous,_:=editor_world_screen(g,editor_state.foundation_draw_points[i-1]);vk_editor_line(r,previous,screen,color,5)}};wx,wy,ok:=editor_mouse_ground(g,g.input.mouse_pos);if ok {last_point:=editor_state.foundation_draw_points[editor_state.foundation_draw_count-1];cursor_point:=level_snap_point(&level_document,{wx,wy},true);last,_:=editor_world_screen(g,last_point);cursor,_:=editor_world_screen(g,cursor_point);vk_editor_line(r,last,cursor,color,3);segment:=editor_segment_length(last_point,cursor_point);label:=fmt.tprintf("EDGE %.2fm",segment);if editor_state.foundation_draw_count>=2 {first,_:=editor_world_screen(g,editor_state.foundation_draw_points[0]);vk_editor_line(r,cursor,first,color,1);area:=editor_polygon_preview_area(editor_state.foundation_draw_points[:editor_state.foundation_draw_count],cursor_point);label=fmt.tprintf("EDGE %.2fm  ·  AREA %.1f SQM",segment,area)};vk_editor_measure_badge(r,last,cursor,label,color)}}
	if g.build_tool==.Wall&&g.build_has_anchor&&editor_state.wall_preview_active {command,split:=level_wall_command(&level_document,g.build_anchor,editor_state.wall_preview_point);preview:=level_preview_transaction(&level_document,command);color:=preview.state==.Blocked?[4]u8{255,144,119,255}:split?[4]u8{117,229,169,255}:[4]u8{102,190,225,255};start,start_ok:=editor_world_screen(g,g.build_anchor);finish,finish_ok:=editor_world_screen(g,command.b);if start_ok&&finish_ok {vk_editor_line(r,start,finish,color,5);vk_level_icon(r,1,0,start.x-7,start.y-7,14);vk_level_icon(r,1,0,finish.x-7,finish.y-7,14);label:=preview.state==.Blocked?strings.to_upper(preview.message):fmt.tprintf("%s  ·  %.2fm",split?"SPLIT INTO TWO ROOMS":"FREESTANDING WALL",editor_segment_length(g.build_anchor,command.b));vk_editor_measure_badge(r,start,finish,label,color)}}
	if g.build_tool==.Room&&editor_state.room_mode==.Polygon&&editor_state.room_draw_count>0 {preview_color:=[4]u8{102,225,143,255};for i in 0..<editor_state.room_draw_count {screen,visible:=editor_world_screen(g,editor_state.room_draw_points[i]);if !visible do continue;vulkan_ui_rect(r,screen.x-6,screen.y-6,12,12,i==0?[4]u8{255,218,112,255}:preview_color);if i>0 {previous,_:=editor_world_screen(g,editor_state.room_draw_points[i-1]);vk_editor_line(r,previous,screen,preview_color,3)}};wx,wy,ok:=editor_mouse_ground(g,g.input.mouse_pos);if ok {last_point:=editor_state.room_draw_points[editor_state.room_draw_count-1];cursor_point:=level_snap_point(&level_document,{wx,wy},true);last,_:=editor_world_screen(g,last_point);cursor,_:=editor_world_screen(g,cursor_point);vk_editor_line(r,last,cursor,preview_color,2);segment:=editor_segment_length(last_point,cursor_point);label:=fmt.tprintf("EDGE %.2fm",segment);if editor_state.room_draw_count>=2 {first,_:=editor_world_screen(g,editor_state.room_draw_points[0]);vk_editor_line(r,cursor,first,preview_color,1);area:=editor_polygon_preview_area(editor_state.room_draw_points[:editor_state.room_draw_count],cursor_point);label=fmt.tprintf("EDGE %.2fm  ·  AREA %.1f SQM",segment,area)};vk_editor_measure_badge(r,last,cursor,label,preview_color)}}
	if g.build_tool==.Path&&editor_state.path_draw_count>0 {color:=[4]u8{224,190,116,255};for i in 0..<editor_state.path_draw_count {screen,visible:=editor_world_screen(g,editor_state.path_draw_points[i]);if visible do vulkan_ui_rect(r,screen.x-5,screen.y-5,10,10,color);if i>0 {previous,_:=editor_world_screen(g,editor_state.path_draw_points[i-1]);vk_editor_line(r,previous,screen,color,max(3,editor_state.path_width*2))}};wx,wy,ok:=editor_mouse_ground(g,g.input.mouse_pos);if ok {last_point:=editor_state.path_draw_points[editor_state.path_draw_count-1];cursor_point:=level_snap_point(&level_document,{wx,wy},true);last,_:=editor_world_screen(g,last_point);cursor,_:=editor_world_screen(g,cursor_point);vk_editor_line(r,last,cursor,color,3);segment:=editor_segment_length(last_point,cursor_point);total:=editor_polyline_length(editor_state.path_draw_points[:editor_state.path_draw_count])+segment;vk_editor_measure_badge(r,last,cursor,fmt.tprintf("SEG %.2fm  ·  TOTAL %.2fm",segment,total),color)}}
	if g.build_tool==.Water&&editor_state.water_draw_count>0 {color:=[4]u8{82,190,224,255};for i in 0..<editor_state.water_draw_count {screen,visible:=editor_world_screen(g,editor_state.water_draw_points[i]);if visible do vulkan_ui_rect(r,screen.x-5,screen.y-5,10,10,i==0?[4]u8{255,218,112,255}:color);if i>0 {previous,_:=editor_world_screen(g,editor_state.water_draw_points[i-1]);vk_editor_line(r,previous,screen,color,3)}};wx,wy,ok:=editor_mouse_ground(g,g.input.mouse_pos);if ok {last_point:=editor_state.water_draw_points[editor_state.water_draw_count-1];cursor_point:=level_snap_point(&level_document,{wx,wy},true);last,_:=editor_world_screen(g,last_point);cursor,_:=editor_world_screen(g,cursor_point);vk_editor_line(r,last,cursor,color,2);segment:=editor_segment_length(last_point,cursor_point);open_length:=editor_polyline_length(editor_state.water_draw_points[:editor_state.water_draw_count])+segment;vk_editor_measure_badge(r,last,cursor,fmt.tprintf("EDGE %.2fm  ·  OPEN %.2fm",segment,open_length),color)}}
	if editor_state.paint_hover_active {index:=level_room_index(&level_document,editor_state.paint_hover.entity_id);if index>=0 {room:=level_document.rooms[index];color:=[4]u8{117,229,169,255};for point,i in room.points {next:=room.points[(i+1)%len(room.points)];a,a_ok:=editor_world_screen(g,point);b,b_ok:=editor_world_screen(g,next);if a_ok&&b_ok do vk_editor_line(r,a,b,color,4)}}}
	if editor_state.roof_hover_active {index:=level_room_index(&level_document,editor_state.roof_hover.entity_id);if index>=0 {room:=level_document.rooms[index];color:=editor_state.roof_preview.state==.Blocked?[4]u8{255,144,119,255}:[4]u8{117,229,169,255};for point,i in room.points {next:=room.points[(i+1)%len(room.points)];a,a_ok:=editor_world_screen(g,point);b,b_ok:=editor_world_screen(g,next);if a_ok&&b_ok do vk_editor_line(r,a,b,color,4)}}}
	if g.build_tool==.Stairs&&editor_state.link_anchor_active {a,a_ok:=editor_world_screen(g,editor_state.link_anchor);b,b_ok:=editor_world_screen(g,editor_state.link_finish);color:=editor_state.link_preview.state==.Blocked?[4]u8{255,144,119,255}:editor_state.link_preview.state==.Warning?[4]u8{255,211,92,255}:[4]u8{117,229,169,255};if a_ok&&b_ok {vk_editor_line(r,a,b,color,5);vulkan_ui_rect(r,a.x-7,a.y-7,14,14,color);vulkan_ui_rect(r,b.x-7,b.y-7,14,14,color);vk_editor_measure_badge(r,a,b,fmt.tprintf("RUN %.2fm",editor_segment_length(editor_state.link_anchor,editor_state.link_finish)),color)}}
	if editor_state.opening_active {path_index:=level_path_index(&level_document,editor_state.opening_host.entity_id);if path_index>=0 {path:=level_document.paths[path_index];segment:=editor_state.opening_host.sub_index;if segment>=0&&segment<len(path.points)-1 {a,a_ok:=editor_world_screen(g,path.points[segment]);b,b_ok:=editor_world_screen(g,path.points[segment+1]);color:=editor_state.opening_preview.state==.Blocked?[4]u8{255,144,119,255}:[4]u8{117,229,169,255};if a_ok&&b_ok do vk_editor_line(r,a,b,color,5);center,center_ok:=editor_world_screen(g,editor_state.opening_position);if center_ok {vulkan_ui_rect(r,center.x-7,center.y-7,14,14,color);vulkan_ui_outline(r,center.x-7,center.y-7,14,14,{20,28,34,255},1)}}}}
	if editor_state.drag_active {
		preview_color:=editor_state.drag_preview.state==.Blocked?[4]u8{255,96,82,255}:editor_state.drag_preview.state==.Warning?[4]u8{255,190,72,255}:[4]u8{102,225,143,255}
		min_screen,max_screen:=Vec2{1e30,1e30},Vec2{-1e30,-1e30};has_point:=false
		if editor_state.drag_selection.kind==.Room||editor_state.drag_selection.kind==.Vertex||editor_state.drag_selection.kind==.Edge {index:=level_room_index(&level_document,editor_state.drag_selection.entity_id);if index>=0 {room:=level_document.rooms[index];for point,i in room.points {moved:=point;if editor_state.drag_selection.kind==.Room||editor_state.drag_selection.kind==.Vertex&&editor_state.drag_selection.sub_index==i||editor_state.drag_selection.kind==.Edge&&(editor_state.drag_selection.sub_index==i||(editor_state.drag_selection.sub_index+1)%len(room.points)==i) {moved.x+=editor_state.drag_delta.x;moved.y+=editor_state.drag_delta.y};screen,visible:=editor_world_screen(g,moved);if visible {min_screen.x=min(min_screen.x,screen.x);min_screen.y=min(min_screen.y,screen.y);max_screen.x=max(max_screen.x,screen.x);max_screen.y=max(max_screen.y,screen.y);if editor_viewport_contains(screen,g.build_tool) do vulkan_ui_rect(r,screen.x-4,screen.y-4,8,8,preview_color);has_point=true}}}} else if editor_state.drag_selection.kind==.Object {index:=level_object_index(&level_document,editor_state.drag_selection.entity_id);if index>=0 {object:=level_document.objects[index];screen,visible:=editor_world_screen(g,{object.position.x+editor_state.drag_delta.x,object.position.y+editor_state.drag_delta.y});if visible {min_screen={screen.x-18,screen.y-18};max_screen={screen.x+18,screen.y+18};has_point=true}}}
		if editor_state.drag_selection.kind==.Opening {index:=level_opening_index(&level_document,editor_state.drag_selection.entity_id);if index>=0 {opening:=level_document.openings[index];command,ok:=level_selection_move_command(&level_document,editor_state.drag_selection,editor_state.drag_delta);path_index:=level_path_index(&level_document,opening.host_path);if ok&&path_index>=0&&opening.segment>=0&&opening.segment<len(level_document.paths[path_index].points)-1 {a,b:=level_document.paths[path_index].points[opening.segment],level_document.paths[path_index].points[opening.segment+1];dx,dy:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dy*dy)));if length>.001 {half:=opening.width*.5/length;position:=clamp(command.c.x,half,1-half);start:=Vec2{a.x+dx*(position-half),a.y+dy*(position-half)};finish:=Vec2{a.x+dx*(position+half),a.y+dy*(position+half)};start_screen,start_ok:=editor_world_screen(g,start);finish_screen,finish_ok:=editor_world_screen(g,finish);if start_ok&&finish_ok {vk_editor_line(r,start_screen,finish_screen,preview_color,7);min_screen={min(start_screen.x,finish_screen.x),min(start_screen.y,finish_screen.y)};max_screen={max(start_screen.x,finish_screen.x),max(start_screen.y,finish_screen.y)};has_point=true}}}}}
		control_point:=editor_control_point_index(editor_state.drag_selection)
		if editor_state.drag_selection.kind==.Foundation&&control_point>=0 {index:=level_foundation_index(&level_document,editor_state.drag_selection.entity_id);command,ok:=level_selection_move_command(&level_document,editor_state.drag_selection,editor_state.drag_delta);if index>=0&&ok {foundation:=level_document.foundations[index];for point,i in foundation.points {moved:=i==control_point?command.a:point;next_index:=(i+1)%len(foundation.points);next_point:=next_index==control_point?command.a:foundation.points[next_index];screen,visible:=editor_world_screen(g,moved);next,next_visible:=editor_world_screen(g,next_point);if visible&&next_visible do vk_editor_line(r,screen,next,preview_color,4);if visible {min_screen.x=min(min_screen.x,screen.x);min_screen.y=min(min_screen.y,screen.y);max_screen.x=max(max_screen.x,screen.x);max_screen.y=max(max_screen.y,screen.y);if editor_viewport_contains(screen,g.build_tool) do vulkan_ui_rect(r,screen.x-(i==control_point?7:4),screen.y-(i==control_point?7:4),i==control_point?14:8,i==control_point?14:8,preview_color);has_point=true}}}}
		if editor_state.drag_selection.kind==.Path&&control_point>=0 {index:=level_path_index(&level_document,editor_state.drag_selection.entity_id);command,ok:=level_selection_move_command(&level_document,editor_state.drag_selection,editor_state.drag_delta);if index>=0&&ok {path:=level_document.paths[index];for point,i in path.points {moved:=i==control_point?command.a:point;screen,visible:=editor_world_screen(g,moved);if i>0 {previous_point:=i-1==control_point?command.a:path.points[i-1];previous,previous_visible:=editor_world_screen(g,previous_point);if visible&&previous_visible do vk_editor_line(r,previous,screen,preview_color,4)};if visible {min_screen.x=min(min_screen.x,screen.x);min_screen.y=min(min_screen.y,screen.y);max_screen.x=max(max_screen.x,screen.x);max_screen.y=max(max_screen.y,screen.y);if editor_viewport_contains(screen,g.build_tool) do vulkan_ui_rect(r,screen.x-(i==control_point?7:4),screen.y-(i==control_point?7:4),i==control_point?14:8,i==control_point?14:8,preview_color);has_point=true}}}}
		if editor_state.drag_selection.kind==.Water&&control_point>=0 {index:=level_water_index(&level_document,editor_state.drag_selection.entity_id);command,ok:=level_selection_move_command(&level_document,editor_state.drag_selection,editor_state.drag_delta);if index>=0&&ok {water:=level_document.waters[index];for point,i in water.points {moved:=i==control_point?command.a:point;next_index:=(i+1)%len(water.points);next_point:=next_index==control_point?command.a:water.points[next_index];screen,visible:=editor_world_screen(g,moved);next,next_visible:=editor_world_screen(g,next_point);if visible&&next_visible do vk_editor_line(r,screen,next,preview_color,4);if visible {min_screen.x=min(min_screen.x,screen.x);min_screen.y=min(min_screen.y,screen.y);max_screen.x=max(max_screen.x,screen.x);max_screen.y=max(max_screen.y,screen.y);if editor_viewport_contains(screen,g.build_tool) do vulkan_ui_rect(r,screen.x-(i==control_point?7:4),screen.y-(i==control_point?7:4),i==control_point?14:8,i==control_point?14:8,preview_color);has_point=true}}}}
		if editor_state.drag_selection.kind==.Vertical_Link&&control_point>=0 {index:=level_vertical_link_index(&level_document,editor_state.drag_selection.entity_id);command,ok:=level_selection_move_command(&level_document,editor_state.drag_selection,editor_state.drag_delta);if index>=0&&ok {link:=level_document.vertical_links[index];start:=control_point==0?command.a:link.start;finish:=control_point==1?command.a:link.finish;start_screen,start_ok:=editor_world_screen(g,start);finish_screen,finish_ok:=editor_world_screen(g,finish);if start_ok&&finish_ok {vk_editor_line(r,start_screen,finish_screen,preview_color,6);points:=[2]Vec2{start_screen,finish_screen};for point,i in points do vulkan_ui_rect(r,point.x-(i==control_point?9:7),point.y-(i==control_point?9:7),i==control_point?18:14,i==control_point?18:14,preview_color);min_screen={min(start_screen.x,finish_screen.x),min(start_screen.y,finish_screen.y)};max_screen={max(start_screen.x,finish_screen.x),max(start_screen.y,finish_screen.y)};has_point=true}}}
		if has_point {bottom:f32=editor_catalog_visible(g.build_tool)?588:686;clipped_min:=Vec2{clamp(min_screen.x-5,f32(78),f32(1188)),clamp(min_screen.y-5,f32(64),bottom)};clipped_max:=Vec2{clamp(max_screen.x+5,f32(78),f32(1188)),clamp(max_screen.y+5,f32(64),bottom)};if clipped_max.x>clipped_min.x&&clipped_max.y>clipped_min.y do vulkan_ui_outline(r,clipped_min.x,clipped_min.y,clipped_max.x-clipped_min.x,clipped_max.y-clipped_min.y,preview_color,3);action:=control_point>=0&&(editor_state.drag_selection.kind==.Foundation||editor_state.drag_selection.kind==.Path||editor_state.drag_selection.kind==.Water||editor_state.drag_selection.kind==.Vertical_Link)?"RESHAPE POINT":"MOVE";label:=editor_state.drag_preview.state==.Blocked?editor_state.drag_preview.message:fmt.tprintf("%s  %+.2f, %+.2f m",action,editor_state.drag_delta.x,editor_state.drag_delta.y);width:=max(f32(190),f32(utf8_glyph_count(label))*7);vk_panel(r,clamp(max_screen.x+12,f32(84),f32(1182)-width),clamp(min_screen.y-8,f32(70),bottom-32),width,28);vk_editor_text(r,clamp(max_screen.x+20,f32(92),f32(1190)-width),clamp(min_screen.y,f32(78),bottom-24),label,preview_color,.5)}
	}
	// A slim global strip and atlas-backed category rail leave the lot itself as
	// the dominant surface. Secondary controls exist only for the active mode.
	vk_editor_surface(r,{8,8,1180,48},true)
	vk_editor_pill(r,editor_top_close_rect(),"X");vk_editor_pill(r,editor_top_save_rect(),level_document.dirty?"SAVE *":"SAVED",level_document.dirty,level_document.dirty);vk_editor_pill(r,editor_top_undo_rect(),fmt.tprintf("UNDO %d",level_history.undo_count),false,level_history.undo_count>0);vk_editor_pill(r,editor_top_redo_rect(),fmt.tprintf("REDO %d",level_history.redo_count),false,level_history.redo_count>0);vk_editor_pill(r,editor_top_view_rect(),editor_view_name(editor_state.view),true)
	vk_editor_pill(r,editor_top_validate_rect(),len(level_document.diagnostics)==0?"READY":fmt.tprintf("ISSUES %d",len(level_document.diagnostics)),len(level_document.diagnostics)>0);vk_editor_text(r,542,23,fmt.tprintf("%s  ·  REV %d",strings.to_upper(level_document.name),level_document.revision),EDITOR_MUTED,.60);story_below:=level_story_below(&level_document,level_document.active_story);story_above:=level_story_above(&level_document,level_document.active_story);vk_level_icon_button(r,editor_top_story_down_rect(),4,1,false,story_below>=0);story_name:="STORY";story_elevation:=f32(0);if level_document.active_story>=0&&level_document.active_story<len(level_document.stories) {story:=level_document.stories[level_document.active_story];story_name=strings.to_upper(story.name);story_elevation=story.base_elevation};if len(story_name)>14 do story_name=story_name[:14];vk_editor_surface(r,{822,11,106,40},true);vk_editor_text(r,832,15,story_name,EDITOR_INK,.60);vk_editor_text(r,832,31,level_story_label(&level_document,level_document.active_story),{47,119,140,255},.60);vk_level_icon_button(r,editor_top_story_up_rect(),4,0,false,story_above>=0||level_can_create_attic(&level_document));if contains(Rect{780,10,192,42},g.input.mouse_pos) {story_hover:=fmt.tprintf("ACTIVE STORY · %.2fm",story_elevation);if contains(editor_top_story_down_rect(),g.input.mouse_pos) do story_hover=story_below>=0?"GO TO STORY BELOW":"NO STORY BELOW";else if contains(editor_top_story_up_rect(),g.input.mouse_pos) do story_hover=story_above>=0?"GO TO STORY ABOVE":level_can_create_attic(&level_document)?"CREATE ATTIC":"NO STORY ABOVE";vk_editor_surface(r,{780,58,192,28},true);vk_editor_text(r,790,65,story_hover,EDITOR_INK,.60)};if editor_state.recovery_available do vk_editor_pill(r,editor_top_recovery_rect(),"RECOVERY");vk_editor_pill(r,editor_top_play_rect(),"PLAY",true)
	if level_document.active_story>=0&&level_document.active_story<len(level_document.stories) {story:=level_document.stories[level_document.active_story];height_down:=editor_top_story_height_down_rect();height_up:=editor_top_story_height_up_rect();vk_editor_parameter_button(r,height_down,.Height,-1,g.input.mouse_pos,story.wall_height>2.2);vk_editor_surface(r,{850,11,50,40},true);vk_editor_text(r,857,17,"HEIGHT",EDITOR_MUTED,.28);vk_editor_text(r,857,31,fmt.tprintf("%.1fm",story.wall_height),EDITOR_INK,.43);vk_editor_parameter_button(r,height_up,.Height,1,g.input.mouse_pos,story.wall_height<6);vk_editor_icon_tooltip(r,height_down,"LOWER FLOOR HEIGHT",g.input.mouse_pos);vk_editor_icon_tooltip(r,height_up,"RAISE FLOOR HEIGHT",g.input.mouse_pos)}
	if editor_state.diagnostics_visible {vulkan_ui_rect(r,806,70,382,540,{10,14,18,246});vulkan_ui_outline(r,806,70,382,540,{90,100,112,230},1);errors,warnings:=0,0;for issue in level_document.diagnostics {if issue.severity==.Error do errors+=1;else if issue.severity==.Warning do warnings+=1};vk_editor_text(r,820,84,"LEVEL DIAGNOSTICS",{255,218,112,255},.60);vk_editor_text(r,1014,86,fmt.tprintf("%d ERRORS  %d WARNINGS",errors,warnings),errors>0?[4]u8{255,144,119,255}:[4]u8{117,229,169,255},.60);vk_editor_text(r,820,108,"CLICK TO FOCUS  ·  [ ] PREVIOUS / NEXT",EDITOR_MUTED,.60);shown:=min(len(level_document.diagnostics),9);start:=editor_diagnostic_window_start(len(level_document.diagnostics),editor_state.diagnostic_selected,9);for row in 0..<shown {index:=start+row;issue:=level_document.diagnostics[index];box:=editor_diagnostic_rect(row);selected:=editor_state.diagnostic_selected==index;hovered:=contains(box,g.input.mouse_pos);fill:=selected?[4]u8{64,82,96,255}:hovered?[4]u8{48,60,70,252}:[4]u8{28,34,40,245};vulkan_ui_rect(r,box.x,box.y,box.w,box.h,fill);outline:=issue.severity==.Error?[4]u8{255,144,119,255}:issue.severity==.Warning?[4]u8{255,210,112,255}:[4]u8{117,190,225,255};vulkan_ui_outline(r,box.x,box.y,box.w,box.h,hovered?[4]u8{220,235,245,255}:outline,selected||hovered?2:1);vk_editor_text(r,box.x+10,box.y+7,fmt.tprintf("%d/%d  %s",index+1,len(level_document.diagnostics),strings.to_upper(issue.entity_id==""?"DOCUMENT":issue.entity_id)),{205,207,210,255},.60);message:=strings.to_upper(issue.message);if len(message)>46 do message=message[:46];vk_editor_text(r,box.x+10,box.y+23,message,{248,247,242,255},.60)};if shown==0 {vk_editor_text(r,882,260,"NO LEVEL ISSUES",{117,229,169,255},.72);vk_editor_text(r,858,292,"READY TO SAVE AND PLAYTEST",{205,207,210,255},.60)};vk_button(r,{1082,570,92,30},"CLOSE")}
	vk_editor_surface(r,editor_tool_rail_rect(),true)
	active_mode:=build_mode_for_tool(g.build_tool);active_tool_name:=editor_build_tool_name(g.build_tool);escape_label:=g.build_tool==.Select?"ESC EXIT":"ESC BACK";active_tool_width:=max(f32(188),f32(utf8_glyph_count(active_tool_name))*COURIER_CELL_WIDTH*.60+118);vk_editor_surface(r,{74,66,active_tool_width,30},true);vulkan_ui_rect(r,84,78,6,6,EDITOR_BLUE);vk_editor_text(r,98,73,"TOOL",EDITOR_MUTED,.60);vk_editor_text(r,134,73,active_tool_name,EDITOR_INK,.60);vk_editor_text(r,74+active_tool_width-62,73,escape_label,EDITOR_MUTED,.60)
	for mode,i in BUILD_MODE_GRID {icon:=BUILD_MODE_ICONS[i];box:=build_tool_grid_rect(i);hovered:=contains(box,g.input.mouse_pos);vk_level_icon_button(r,box,icon[0],icon[1],active_mode==mode,true,hovered);if hovered {shortcut:=editor_build_tool_shortcut(mode);label:=fmt.tprintf("[%s]  %s",shortcut,editor_build_tool_name(mode));width:=max(f32(124),f32(utf8_glyph_count(label))*7+18);vk_panel(r,74,box.y+7,width,27);vk_editor_text(r,82,box.y+14,label,{255,218,112,255},.60)}}
	if active_mode==.Room {subtools:=[4]Build_Tool{.Room,.Wall,.Door,.Window};vulkan_ui_rect(r,76,132,312,58,{10,14,18,224});for tool,i in subtools {icon_index:=0;for known,j in BUILD_TOOL_GRID do if known==tool do icon_index=j;icon:=BUILD_TOOL_ICONS[icon_index];box:=build_subtool_rect(i);vk_level_icon_button(r,box,icon[0],icon[1],g.build_tool==tool);vk_editor_icon_tooltip(r,box,BUILD_TOOL_NAMES[icon_index],g.input.mouse_pos)};vulkan_ui_rect(r,285,140,1,42,{90,100,112,180});rectangle_box:=build_subtool_rect(4);polygon_box:=build_subtool_rect(5);vk_level_icon_button(r,rectangle_box,0,1,g.build_tool==.Room&&editor_state.room_mode==.Rectangle);vk_level_icon_button(r,polygon_box,7,3,g.build_tool==.Room&&editor_state.room_mode==.Polygon);vk_editor_icon_tooltip(r,rectangle_box,"RECTANGLE",g.input.mouse_pos);vk_editor_icon_tooltip(r,polygon_box,"POLYGON",g.input.mouse_pos)} else if active_mode==.Paint {vulkan_ui_rect(r,74,132,160,58,{10,14,18,224});paint_icons:=[3][2]int{{3,0},{3,2},{3,5}};paint_labels:=[3]string{"FLOOR","WALLS","WHOLE ROOM"};for target in Paint_Target {index:=int(target);box:=editor_paint_target_rect(index);icon:=paint_icons[index];vk_level_icon_button(r,box,icon[0],icon[1],editor_state.paint_target==target);vk_editor_icon_tooltip(r,box,paint_labels[index],g.input.mouse_pos)}} else if active_mode==.Plant {subtools:=[2]Build_Tool{.Plant,.Light};vulkan_ui_rect(r,76,132,108,58,{10,14,18,224});for tool,i in subtools {icon_index:=0;for known,j in BUILD_TOOL_GRID do if known==tool do icon_index=j;icon:=BUILD_TOOL_ICONS[icon_index];box:=build_subtool_rect(i);vk_level_icon_button(r,box,icon[0],icon[1],g.build_tool==tool);vk_editor_icon_tooltip(r,box,BUILD_TOOL_NAMES[icon_index],g.input.mouse_pos)}}
	if active_mode==.Room&&g.build_tool==.Room {patio_box:=build_subtool_rect(6);vulkan_ui_rect(r,388,132,58,58,{10,14,18,224});vk_level_icon_button(r,patio_box,6,2,editor_state.room_exterior);vk_editor_icon_tooltip(r,patio_box,"PATIO",g.input.mouse_pos)}
	if active_mode==.Room&&g.build_tool==.Window {vulkan_ui_rect(r,76,186,552,34,{10,14,18,224});width_down:=editor_opening_parameter_rect(0);width_up:=editor_opening_parameter_rect(1);height_down:=editor_opening_parameter_rect(2);height_up:=editor_opening_parameter_rect(3);sill_down:=Rect{370,188,38,26};sill_up:=Rect{472,188,38,26};style_box:=Rect{520,188,104,26};vk_editor_parameter_button(r,width_down,.Width,-1,g.input.mouse_pos,editor_state.opening_width>.4);vk_editor_text(r,120,195,fmt.tprintf("W %.1fm",editor_state.opening_width),{235,237,238,255},.34);vk_editor_parameter_button(r,width_up,.Width,1,g.input.mouse_pos,editor_state.opening_width<6);vk_editor_parameter_button(r,height_down,.Height,-1,g.input.mouse_pos,editor_state.opening_height>.4);vk_editor_text(r,266,195,fmt.tprintf("H %.1fm",editor_state.opening_height),{235,237,238,255},.34);vk_editor_parameter_button(r,height_up,.Height,1,g.input.mouse_pos,editor_state.opening_height<4);vk_editor_parameter_button(r,sill_down,.Height,-1,g.input.mouse_pos,editor_state.opening_sill_height>.2);vk_editor_text(r,412,195,fmt.tprintf("S %.1fm",editor_state.opening_sill_height),{235,237,238,255},.34);vk_editor_parameter_button(r,sill_up,.Height,1,g.input.mouse_pos,editor_state.opening_sill_height<2);vk_button(r,style_box,window_style_label(editor_state.window_style));vk_editor_icon_tooltip(r,width_down,"NARROWER WINDOW",g.input.mouse_pos);vk_editor_icon_tooltip(r,width_up,"WIDER WINDOW",g.input.mouse_pos);vk_editor_icon_tooltip(r,height_down,"SHORTER WINDOW",g.input.mouse_pos);vk_editor_icon_tooltip(r,height_up,"TALLER WINDOW",g.input.mouse_pos);vk_editor_icon_tooltip(r,sill_down,"LOWER SILL",g.input.mouse_pos);vk_editor_icon_tooltip(r,sill_up,"RAISE SILL",g.input.mouse_pos);vk_editor_action_tooltip(r,style_box,"WINDOW STYLE",g.input.mouse_pos)}
	if active_mode==.Room&&g.build_tool==.Door {vulkan_ui_rect(r,76,186,294,34,{10,14,18,224});previous,next:=editor_opening_parameter_rect(0),editor_opening_parameter_rect(1);style_box:=Rect{266,188,104,26};vk_editor_parameter_button(r,previous,.Width,-1,g.input.mouse_pos,true);vk_editor_text(r,120,195,strings.to_upper(door_material_name(editor_state.door_material)),{235,237,238,255},.34);vk_editor_parameter_button(r,next,.Width,1,g.input.mouse_pos,true);vk_button(r,style_box,door_style_label(editor_state.door_style));vk_editor_icon_tooltip(r,previous,"PREVIOUS DOOR FINISH",g.input.mouse_pos);vk_editor_icon_tooltip(r,next,"NEXT DOOR FINISH",g.input.mouse_pos);vk_editor_action_tooltip(r,style_box,"DOOR STYLE",g.input.mouse_pos)}
	if active_mode==.Paint {vulkan_ui_rect(r,234,132,48,58,{10,14,18,224});box:=editor_paint_eyedropper_rect();vk_level_icon_button(r,box,3,6,editor_state.paint_eyedropper);vk_editor_icon_tooltip(r,box,"EYEDROPPER",g.input.mouse_pos)}
	if active_mode==.Foundation {vulkan_ui_rect(r,74,132,352,82,{10,14,18,236});icons:=[3][2]int{{1,6},{1,7},{7,5}};kind_labels:=[3]string{"SLAB","RAISED","BASEMENT"};for kind in Level_Foundation_Kind {index:=int(kind);icon:=icons[index];box:=editor_foundation_kind_rect(index);vk_level_icon_button(r,box,icon[0],icon[1],editor_state.foundation_kind==kind);vk_editor_icon_tooltip(r,box,kind_labels[index],g.input.mouse_pos)};vulkan_ui_rect(r,224,140,1,42,{90,100,112,180});measure_down:=editor_foundation_measure_rect(0);measure_up:=editor_foundation_measure_rect(1);vk_editor_parameter_button(r,measure_down,.Height,-1,g.input.mouse_pos,editor_state.foundation_kind==.Raised?editor_state.foundation_elevation>.25:editor_state.foundation_kind==.Basement?editor_state.foundation_depth>2.5:editor_state.foundation_depth>.1);vk_editor_parameter_button(r,measure_up,.Height,1,g.input.mouse_pos,editor_state.foundation_kind==.Raised?editor_state.foundation_elevation<3:editor_state.foundation_kind==.Basement?editor_state.foundation_depth<6:editor_state.foundation_depth<1);rectangle_box:=editor_foundation_mode_rect(0);polygon_box:=editor_foundation_mode_rect(1);vk_level_icon_button(r,rectangle_box,0,1,editor_state.foundation_mode==.Rectangle);vk_level_icon_button(r,polygon_box,7,3,editor_state.foundation_mode==.Polygon);measure_name:=editor_state.foundation_kind==.Raised?"HEIGHT":editor_state.foundation_kind==.Basement?"DEPTH":"THICKNESS";vk_editor_icon_tooltip(r,measure_down,fmt.tprintf("DECREASE %s",measure_name),g.input.mouse_pos);vk_editor_icon_tooltip(r,measure_up,fmt.tprintf("INCREASE %s",measure_name),g.input.mouse_pos);vk_editor_icon_tooltip(r,rectangle_box,"RECTANGLE",g.input.mouse_pos);vk_editor_icon_tooltip(r,polygon_box,"POLYGON",g.input.mouse_pos);kind_label:=editor_state.foundation_kind==.Slab?"SLAB":editor_state.foundation_kind==.Raised?"RAISED":"BASEMENT";measure_label:=editor_state.foundation_kind==.Raised?fmt.tprintf("%.2fm HIGH",editor_state.foundation_elevation):editor_state.foundation_kind==.Basement?fmt.tprintf("%.2fm DEEP",editor_state.foundation_depth):fmt.tprintf("%.2fm THICK",editor_state.foundation_depth);vk_editor_text(r,78,190,fmt.tprintf("%s  ·  %s",kind_label,measure_label),{235,237,238,255},.36)}
	if active_mode==.Terrain {vulkan_ui_rect(r,74,132,300,86,{10,14,18,236});terrain_icons:=[5][2]int{{4,0},{4,1},{4,3},{4,2},{4,4}};terrain_labels:=[5]string{"RAISE","LOWER","SMOOTH","FLATTEN","SLOPE"};for mode in Terrain_Brush_Mode {index:=int(mode);box:=editor_terrain_mode_rect(index);icon:=terrain_icons[index];vk_level_icon_button(r,box,icon[0],icon[1],editor_state.terrain_mode==mode);vk_editor_icon_tooltip(r,box,terrain_labels[index],g.input.mouse_pos)};radius_down:=editor_terrain_parameter_rect(0);radius_up:=editor_terrain_parameter_rect(1);strength_down:=editor_terrain_parameter_rect(2);strength_up:=editor_terrain_parameter_rect(3);vk_editor_parameter_button(r,radius_down,.Radius,-1,g.input.mouse_pos,editor_state.terrain_radius>.5);vk_editor_text(r,120,191,fmt.tprintf("R %.1fm",editor_state.terrain_radius),{235,237,238,255},.34);vk_editor_parameter_button(r,radius_up,.Radius,1,g.input.mouse_pos,editor_state.terrain_radius<8);vk_editor_parameter_button(r,strength_down,.Strength,-1,g.input.mouse_pos,editor_state.terrain_strength>.25);vk_editor_text(r,266,191,fmt.tprintf("S %.2f",editor_state.terrain_strength),{235,237,238,255},.34);vk_editor_parameter_button(r,strength_up,.Strength,1,g.input.mouse_pos,editor_state.terrain_strength<2);vk_editor_icon_tooltip(r,radius_down,"REDUCE RADIUS",g.input.mouse_pos);vk_editor_icon_tooltip(r,radius_up,"INCREASE RADIUS",g.input.mouse_pos);vk_editor_icon_tooltip(r,strength_down,"REDUCE STRENGTH",g.input.mouse_pos);vk_editor_icon_tooltip(r,strength_up,"INCREASE STRENGTH",g.input.mouse_pos)}
	if g.build_tool==.Light {vk_editor_surface(r,editor_light_panel_rect(),true);kind_box:=editor_light_kind_rect();range_down:=editor_light_parameter_rect(0);range_up:=editor_light_parameter_rect(1);intensity_down:=editor_light_parameter_rect(2);intensity_up:=editor_light_parameter_rect(3);vk_button(r,kind_box,strings.to_upper(level_light_kind_name(editor_state.light_kind)),true);vk_editor_parameter_button(r,range_down,.Range,-1,g.input.mouse_pos,editor_state.light_range>.5);vk_editor_parameter_button(r,range_up,.Range,1,g.input.mouse_pos,editor_state.light_range<40);vk_editor_parameter_button(r,intensity_down,.Intensity,-1,g.input.mouse_pos,editor_state.light_intensity>.1);vk_editor_parameter_button(r,intensity_up,.Intensity,1,g.input.mouse_pos,editor_state.light_intensity<100);vk_editor_icon_tooltip(r,kind_box,"LIGHT TYPE",g.input.mouse_pos);vk_editor_icon_tooltip(r,range_down,"REDUCE RANGE",g.input.mouse_pos);vk_editor_icon_tooltip(r,range_up,"INCREASE RANGE",g.input.mouse_pos);vk_editor_icon_tooltip(r,intensity_down,"REDUCE INTENSITY",g.input.mouse_pos);vk_editor_icon_tooltip(r,intensity_up,"INCREASE INTENSITY",g.input.mouse_pos);vk_editor_text(r,82,244,fmt.tprintf("RANGE %.1fm  ·  INTENSITY %.1fx",editor_state.light_range,editor_state.light_intensity),EDITOR_INK,.36)}
	if active_mode==.Roof {vk_editor_surface(r,editor_roof_panel_rect(),true);style_box:=editor_roof_style_rect();pitch_down:=editor_roof_parameter_rect(0);pitch_up:=editor_roof_parameter_rect(1);overhang_down:=editor_roof_parameter_rect(2);overhang_up:=editor_roof_parameter_rect(3);ridge_box:=editor_roof_parameter_rect(4);gutters_box:=editor_roof_gutters_rect();apply_box:=editor_roof_apply_rect();vk_button(r,style_box,strings.to_upper(fmt.tprintf("%v",editor_state.roof_style)),true);vk_editor_parameter_button(r,pitch_down,.Pitch,-1,g.input.mouse_pos,editor_state.roof_pitch>5);vk_editor_parameter_button(r,pitch_up,.Pitch,1,g.input.mouse_pos,editor_state.roof_pitch<70);vk_editor_parameter_button(r,overhang_down,.Overhang,-1,g.input.mouse_pos,editor_state.roof_overhang>0);vk_editor_parameter_button(r,overhang_up,.Overhang,1,g.input.mouse_pos,editor_state.roof_overhang<2);vk_editor_parameter_button(r,ridge_box,.Rotate,1,g.input.mouse_pos);vk_button(r,gutters_box,editor_state.roof_gutters?"GUTTERS":"NO GUTTERS",editor_state.roof_gutters);apply_enabled:=editor_state.roof_hover_active&&editor_state.roof_preview.state!=.Blocked;vk_button(r,apply_box,"APPLY",apply_enabled);vk_editor_icon_tooltip(r,style_box,"ROOF STYLE",g.input.mouse_pos);vk_editor_icon_tooltip(r,pitch_down,"LOWER PITCH",g.input.mouse_pos);vk_editor_icon_tooltip(r,pitch_up,"RAISE PITCH",g.input.mouse_pos);vk_editor_icon_tooltip(r,overhang_down,"LESS OVERHANG",g.input.mouse_pos);vk_editor_icon_tooltip(r,overhang_up,"MORE OVERHANG",g.input.mouse_pos);vk_editor_icon_tooltip(r,ridge_box,"ROTATE RIDGE 15°",g.input.mouse_pos);vk_editor_icon_tooltip(r,gutters_box,"TOGGLE GUTTERS",g.input.mouse_pos);vk_editor_action_tooltip(r,apply_box,apply_enabled?"COMMIT ROOF CHANGES":"MOVE OVER A ROOM FIRST",g.input.mouse_pos);vk_editor_text(r,82,180,fmt.tprintf("%d° PITCH  ·  %.1fm EAVE  ·  %d° RIDGE",int(editor_state.roof_pitch),editor_state.roof_overhang,int(editor_state.roof_ridge_angle)%360),EDITOR_INK,.34)}
	if active_mode==.Stairs {vulkan_ui_rect(r,74,132,192,54,{10,14,18,224});kind_box:=editor_link_kind_rect();width_down:=editor_link_width_rect(0);width_up:=editor_link_width_rect(1);vk_button(r,kind_box,strings.to_upper(fmt.tprintf("%v",editor_state.link_kind)),true);vk_editor_parameter_button(r,width_down,.Width,-1,g.input.mouse_pos,editor_state.link_width>.6);vk_editor_parameter_button(r,width_up,.Width,1,g.input.mouse_pos,editor_state.link_width<3);vk_editor_icon_tooltip(r,kind_box,"LINK TYPE",g.input.mouse_pos);vk_editor_icon_tooltip(r,width_down,"NARROWER",g.input.mouse_pos);vk_editor_icon_tooltip(r,width_up,"WIDER",g.input.mouse_pos)}
	if active_mode==.Path {vulkan_ui_rect(r,74,132,192,54,{10,14,18,224});kind_box:=editor_link_kind_rect();width_down:=editor_link_width_rect(0);width_up:=editor_link_width_rect(1);vk_button(r,kind_box,strings.to_upper(fmt.tprintf("%v",editor_state.path_kind)),true);vk_editor_parameter_button(r,width_down,.Width,-1,g.input.mouse_pos,editor_state.path_width>.2);vk_editor_parameter_button(r,width_up,.Width,1,g.input.mouse_pos,editor_state.path_width<8);vk_editor_icon_tooltip(r,kind_box,"PATH TYPE",g.input.mouse_pos);vk_editor_icon_tooltip(r,width_down,"NARROWER",g.input.mouse_pos);vk_editor_icon_tooltip(r,width_up,"WIDER",g.input.mouse_pos)}
	if active_mode==.Water {vulkan_ui_rect(r,74,132,124,54,{10,14,18,224});height_down:=editor_water_height_rect(0);height_up:=editor_water_height_rect(1);vk_editor_parameter_button(r,height_down,.Height,-1,g.input.mouse_pos);vk_editor_parameter_button(r,height_up,.Height,1,g.input.mouse_pos);vk_editor_icon_tooltip(r,height_down,"LOWER SURFACE",g.input.mouse_pos);vk_editor_icon_tooltip(r,height_up,"RAISE SURFACE",g.input.mouse_pos)}
	if active_mode==.Marker {vulkan_ui_rect(r,74,132,344,104,{10,14,18,224});short_labels:=[8]string{"PLAYER","CHAR","USE","CLUE","TRIG","EXIT","CAM","STAGE"};for kind in Level_Marker_Kind {index:=int(kind);icon:=MARKER_KIND_ICONS[index];box:=editor_marker_kind_rect(index);vk_level_icon_button(r,box,icon[0],icon[1],editor_state.marker_kind==kind);vk_editor_text(r,box.x+2,181,short_labels[index],editor_state.marker_kind==kind?[4]u8{255,218,112,255}:[4]u8{170,180,190,255},.20);vk_editor_icon_tooltip(r,box,strings.to_upper(level_marker_kind_name(kind)),g.input.mouse_pos)};radius_down:=editor_marker_parameter_rect(0);radius_up:=editor_marker_parameter_rect(1);facing_down:=editor_marker_parameter_rect(2);facing_up:=editor_marker_parameter_rect(3);vk_editor_parameter_button(r,radius_down,.Radius,-1,g.input.mouse_pos,editor_state.marker_radius>.1);vk_editor_parameter_button(r,radius_up,.Radius,1,g.input.mouse_pos,editor_state.marker_radius<12);vk_editor_parameter_button(r,facing_down,.Rotate,-1,g.input.mouse_pos);vk_editor_parameter_button(r,facing_up,.Rotate,1,g.input.mouse_pos);vk_editor_text(r,254,208,fmt.tprintf("%.1fm  %d°",editor_state.marker_radius,int(editor_state.marker_facing)),{235,237,238,255},.38);vk_editor_icon_tooltip(r,radius_down,"REDUCE RADIUS",g.input.mouse_pos);vk_editor_icon_tooltip(r,radius_up,"INCREASE RADIUS",g.input.mouse_pos);vk_editor_icon_tooltip(r,facing_down,"ROTATE LEFT",g.input.mouse_pos);vk_editor_icon_tooltip(r,facing_up,"ROTATE RIGHT",g.input.mouse_pos)}
	if editor_catalog_visible(g.build_tool) do vk_draw_editor_catalog(r,g)
	if g.build_tool==.Plant&&editor_state.placement_active {state:=editor_state.placement_preview.state;color:=state==.Blocked?[4]u8{255,144,119,255}:state==.Warning?[4]u8{255,210,112,255}:[4]u8{117,229,169,255};vk_panel(r,858,66,326,48);name:=strings.to_upper(editor_state.catalog_id);vk_editor_text(r,870,74,fmt.tprintf("%s   %d DEG",name,int(editor_state.placement_rotation)),{248,247,242,255},.46);message:=state==.Valid?(editor_state.placement_support_id!=""?"CLICK PLACE ON FURNITURE · WHEEL ROTATE":"CLICK · WHEEL OR < > ROTATE · ESC"):strings.to_upper(editor_state.placement_preview.message);if len(message)>43 do message=message[:43];vk_editor_text(r,870,94,message,color,.30)}
	if (g.build_tool==.Paint||g.build_tool==.Wall_Paint)&&editor_state.paint_hover_active {vk_panel(r,858,66,326,54);target:=editor_state.paint_target==.Walls?"WALLS":editor_state.paint_target==.Room?"WHOLE ROOM":"FLOOR";if editor_state.paint_eyedropper {vk_editor_text(r,870,73,fmt.tprintf("SAMPLE %s MATERIAL",target),{255,226,128,255},.68);vk_editor_text(r,870,96,"CLICK ROOM   ESC CANCEL",{150,240,192,255},.60)} else {vk_editor_text(r,870,73,fmt.tprintf("%s   %s",strings.to_upper(editor_state.catalog_id),target),{255,255,255,255},.68);vk_editor_text(r,870,96,"CLICK APPLY   SHIFT WHOLE ROOM",{150,240,192,255},.60)}}
	if (g.build_tool==.Door||g.build_tool==.Window)&&editor_state.opening_active {state:=editor_state.opening_preview.state;color:=state==.Blocked?[4]u8{255,144,119,255}:[4]u8{117,229,169,255};vk_panel(r,818,66,366,48);title:=g.build_tool==.Window?fmt.tprintf("WINDOW   %.1fm W × %.1fm H   SILL %.1fm",editor_state.opening_width,editor_state.opening_height,editor_state.opening_sill_height):"DOOR   HOSTED";vk_editor_text(r,830,74,title,{248,247,242,255},.42);message:=state==.Blocked?strings.to_upper(editor_state.opening_preview.message):"CLICK PLACE   ESC BACK";if len(message)>48 do message=message[:48];vk_editor_text(r,830,94,message,color,.32)}
	if g.build_tool==.Roof&&editor_state.roof_hover_active {color:=editor_state.roof_preview.state==.Blocked?[4]u8{255,144,119,255}:[4]u8{117,229,169,255};vk_panel(r,814,66,370,48);vk_editor_text(r,826,74,fmt.tprintf("%s   %d DEG   %.1fm",strings.to_upper(fmt.tprintf("%v",editor_state.roof_style)),int(editor_state.roof_pitch),editor_state.roof_overhang),{248,247,242,255},.46);vk_editor_text(r,826,94,editor_state.roof_preview.state==.Blocked?strings.to_upper(editor_state.roof_preview.message):"APPLY BUTTON OR CLICK ROOM",color,.32)}
	if g.build_tool==.Stairs {state:=editor_state.link_preview.state;color:=state==.Blocked?[4]u8{255,144,119,255}:state==.Warning?[4]u8{255,211,92,255}:[4]u8{117,229,169,255};vk_panel(r,814,66,370,48);vk_editor_text(r,826,74,fmt.tprintf("%s   %.1fm WIDE",strings.to_upper(fmt.tprintf("%v",editor_state.link_kind)),editor_state.link_width),{248,247,242,255},.46);message:=!editor_state.link_anchor_active?"STEP 1 / 2   CLICK LOWER LANDING":state==.Valid?"STEP 2 / 2   CLICK UPPER LANDING":strings.to_upper(editor_state.link_preview.message);if len(message)>48 do message=message[:48];vk_editor_text(r,826,94,message,color,.32)}
	if g.build_tool==.Path {vk_panel(r,814,66,370,48);vk_editor_text(r,826,74,fmt.tprintf("%s   %.1fm WIDE   ·   %d POINTS",strings.to_upper(fmt.tprintf("%v",editor_state.path_kind)),editor_state.path_width,editor_state.path_draw_count),{248,247,242,255},.46);message:=editor_state.path_draw_count==0?"STEP 1   CLICK PATH START":editor_state.path_draw_count<2?"STEP 2   CLICK ANOTHER POINT":"STEP 3   ADD POINTS OR ENTER TO FINISH";vk_editor_text(r,826,94,message,{224,190,116,255},.32)}
	if g.build_tool==.Water {vk_panel(r,814,66,370,48);vk_editor_text(r,826,74,fmt.tprintf("POND   SURFACE %.2fm   ·   %d POINTS",editor_state.water_elevation,editor_state.water_draw_count),{248,247,242,255},.46);message:=editor_state.water_draw_count==0?"STEP 1   CLICK SHORELINE START":editor_state.water_draw_count<3?"STEP 2   ADD AT LEAST 3 POINTS":"STEP 3   CLICK START OR ENTER TO CLOSE";vk_editor_text(r,826,94,message,{82,190,224,255},.32)}
	if g.build_tool==.Marker {vk_panel(r,814,66,370,48);selected_marker:Level_Marker;editing:=false;if editor_state.selection_count==1&&editor_state.selection[0].kind==.Marker {index:=level_marker_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {selected_marker=level_document.markers[index];editing=true}};if editing {vk_editor_text(r,826,74,fmt.tprintf("EDITING %s MARKER",strings.to_upper(level_marker_kind_name(selected_marker.kind))),{248,247,242,255},.46);vk_editor_text(r,826,94,"INSPECTOR CHANGES SELECTED · CLICK EMPTY TO PLACE NEW",{102,205,235,255},.30)}else{vk_editor_text(r,826,74,fmt.tprintf("NEW %s MARKER",strings.to_upper(level_marker_kind_name(editor_state.marker_kind))),{248,247,242,255},.46);binding:="CLICK TO PLACE";if (editor_state.marker_kind==.Character_Spawn||editor_state.marker_kind==.Interaction||editor_state.marker_kind==.Clue)&&editor_state.marker_reference=="" do binding="PLACE NOW · BIND REFERENCE IN INSPECTOR";if editor_state.marker_kind==.Trigger&&editor_state.marker_reference=="" do binding="PLACE NOW · BIND STORY EVENT IN INSPECTOR";if editor_state.marker_kind==.Transition&&editor_state.marker_destination=="" do binding="PLACE NOW · CHOOSE DESTINATION LATER";vk_editor_text(r,826,94,binding,{117,229,169,255},.30)}}
	if g.build_tool==.Light {vk_button(r,editor_light_kind_rect(),fmt.tprintf("NEW %s",strings.to_upper(level_light_kind_name(editor_state.light_kind))),true);vk_panel(r,814,66,370,48);selected_light:Level_Light;editing:=false;if editor_state.selection_count==1&&editor_state.selection[0].kind==.Light {index:=level_light_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {selected_light=level_document.lights[index];editing=true}};if editing {vk_editor_text(r,826,74,fmt.tprintf("EDITING %s LIGHT",strings.to_upper(level_light_kind_name(selected_light.kind))),{248,247,242,255},.46);vk_editor_text(r,826,94,"INSPECTOR CHANGES SELECTED · CLICK EMPTY TO PLACE NEW",{102,205,235,255},.30)}else{vk_editor_text(r,826,74,fmt.tprintf("NEW %s LIGHT   %.1fm   %.1fx",strings.to_upper(level_light_kind_name(editor_state.light_kind)),editor_state.light_range,editor_state.light_intensity),{248,247,242,255},.46);vk_editor_text(r,826,94,"CLICK TO PLACE · THEN FINE-TUNE IN INSPECTOR",{255,218,112,255},.30)}}
	if g.build_tool==.Terrain {vk_panel(r,824,66,360,48);mode:=editor_effective_terrain_mode(editor_state.terrain_mode,g.keys[.LCTRL]||g.keys[.RCTRL]);vk_editor_text(r,836,74,fmt.tprintf("%s   R %.1fm   S %.2f",strings.to_upper(fmt.tprintf("%v",mode)),editor_state.terrain_radius,editor_state.terrain_strength),{248,247,242,255},.46);vk_editor_text(r,836,94,"DRAG SCULPT   CTRL INVERT RAISE/LOWER",{255,218,112,255},.30)}
	if g.build_tool==.Plant&&editor_state.placement_active do vk_editor_preview_callout(r,g,editor_state.placement_preview.message,editor_state.placement_preview.state)
	if (g.build_tool==.Door||g.build_tool==.Window) {if editor_state.opening_active do vk_editor_preview_callout(r,g,editor_state.opening_preview.message,editor_state.opening_preview.state);else do vk_editor_preview_callout(r,g,"Move cursor over a wall",.Blocked)}
	if g.build_tool==.Roof {if editor_state.roof_hover_active do vk_editor_preview_callout(r,g,editor_state.roof_preview.message,editor_state.roof_preview.state);else do vk_editor_preview_callout(r,g,"Move cursor over a room",.Blocked)}
	if g.build_tool==.Stairs&&editor_state.link_anchor_active do vk_editor_preview_callout(r,g,editor_state.link_preview.message,editor_state.link_preview.state)
	if editor_state.selection_count>0&&!editor_state.drag_active {selected:=editor_state.selection[0];left,left_ok:=editor_selection_action_rect(g,0);right,_:=editor_selection_action_rect(g,1);duplicate,_:=editor_selection_action_rect(g,2);lower,_:=editor_selection_action_rect(g,3);raise,_:=editor_selection_action_rect(g,4);remove,_:=editor_selection_action_rect(g,5);seventh,_:=editor_selection_action_rect(g,6);if left_ok&&(selected.kind==.Room||selected.kind==.Object) {origin,_:=editor_selection_toolbar_origin(g);vulkan_ui_rect(r,origin.x-5,origin.y-5,246,36,{10,14,18,220});icons:=[6][2]int{{6,2},{6,1},{6,3},{4,1},{4,0},{6,4}};actions:=[6]string{"ROTATE LEFT","ROTATE RIGHT","DUPLICATE","LOWER","RAISE","DELETE"};boxes:=[6]Rect{left,right,duplicate,lower,raise,remove};for box,i in boxes {icon:=icons[i];vk_level_icon_button(r,box,icon[0],icon[1]);vk_editor_action_tooltip(r,box,actions[i],g.input.mouse_pos)}} else if left_ok&&selected.kind==.Opening {origin,_:=editor_selection_toolbar_origin(g);index:=level_opening_index(&level_document,selected.entity_id);if index>=0 {opening:=level_document.openings[index];if opening.kind==.Window {vulkan_ui_rect(r,origin.x-5,origin.y-5,286,36,{10,14,18,220});vk_editor_parameter_button(r,left,.Width,-1,g.input.mouse_pos,opening.width>.4);vk_editor_parameter_button(r,right,.Width,1,g.input.mouse_pos,opening.width<6);vk_editor_parameter_button(r,duplicate,.Height,-1,g.input.mouse_pos,opening.height>.4);vk_editor_parameter_button(r,lower,.Height,1,g.input.mouse_pos,opening.height<4);vk_editor_parameter_button(r,raise,.Height,-1,g.input.mouse_pos,opening.sill_height>.2);vk_editor_parameter_button(r,remove,.Height,1,g.input.mouse_pos,opening.sill_height<2);vk_level_icon_button(r,seventh,6,4);vk_editor_action_tooltip(r,left,"NARROWER WINDOW",g.input.mouse_pos);vk_editor_action_tooltip(r,right,"WIDER WINDOW",g.input.mouse_pos);vk_editor_action_tooltip(r,duplicate,"SHORTER WINDOW",g.input.mouse_pos);vk_editor_action_tooltip(r,lower,"TALLER WINDOW",g.input.mouse_pos);vk_editor_action_tooltip(r,raise,"LOWER SILL",g.input.mouse_pos);vk_editor_action_tooltip(r,remove,"RAISE SILL",g.input.mouse_pos);vk_editor_action_tooltip(r,seventh,"DELETE WINDOW",g.input.mouse_pos)}else{vulkan_ui_rect(r,origin.x-5,origin.y-5,166,36,{10,14,18,220});vk_button(r,left,door_style_label(opening.door_style));vk_level_icon_button(r,right,6,4);vk_button(r,duplicate,opening.initially_active?"OPEN":"SHUT");vk_button(r,lower,opening.locked?"LOCK":"FREE");vk_editor_action_tooltip(r,left,"CHANGE DOOR STYLE",g.input.mouse_pos);vk_editor_action_tooltip(r,right,"DELETE DOOR",g.input.mouse_pos);vk_editor_action_tooltip(r,duplicate,"TOGGLE INITIAL DOOR STATE",g.input.mouse_pos);vk_editor_action_tooltip(r,lower,"TOGGLE DOOR LOCK",g.input.mouse_pos)}}} else if left_ok&&selected.kind==.Edge {origin,_:=editor_selection_toolbar_origin(g);vulkan_ui_rect(r,origin.x-5,origin.y-5,46,36,{10,14,18,220});vk_level_icon_button(r,left,0,6);vk_editor_action_tooltip(r,left,"INSERT CORNER",g.input.mouse_pos)} else if left_ok&&selected.kind==.Vertex {origin,_:=editor_selection_toolbar_origin(g);vulkan_ui_rect(r,origin.x-5,origin.y-5,46,36,{10,14,18,220});vk_level_icon_button(r,left,0,7);vk_editor_action_tooltip(r,left,"REMOVE CORNER",g.input.mouse_pos)}}
	if editor_state.selection_count==1&&(editor_state.selection[0].kind==.Room||editor_state.selection[0].kind==.Edge||editor_state.selection[0].kind==.Vertex)&&!editor_state.drag_active {selected:=editor_state.selection[0];index:=level_room_index(&level_document,selected.entity_id);if index>=0 {room:=level_document.rooms[index];area:=math.abs(level_polygon_area(room.points[:]));box:=editor_selection_inspector_rect();vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{10,14,18,232});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,{90,100,112,190},1);selection_context:=selected.kind==.Edge?"EDGE":selected.kind==.Vertex?"CORNER":"ROOM";title:=fmt.tprintf("%s  ·  %s",strings.to_upper(room.name==""?room.id:room.name),selection_context);if len(title)>31 do title=title[:31];vk_editor_text(r,box.x+14,box.y+14,title,{255,218,112,255},.60);vk_editor_text(r,box.x+14,box.y+37,fmt.tprintf("%.1f SQM  ·  %d CORNERS  ·  STORY %d",area,len(room.points),room.story+1),{205,207,210,255},.60);level_down:=editor_compact_inspector_step_rect(174,-1);level_up:=editor_compact_inspector_step_rect(174,1);vk_editor_parameter_button(r,level_down,.Height,-1,g.input.mouse_pos,room.platform_height>-5);vk_editor_text(r,994,183,fmt.tprintf("LEVEL %.2fm",room.platform_height),{248,247,242,255},.60);vk_editor_parameter_button(r,level_up,.Height,1,g.input.mouse_pos,room.platform_height<10);vk_editor_action_tooltip(r,level_down,"LOWER ROOM LEVEL",g.input.mouse_pos);vk_editor_action_tooltip(r,level_up,"RAISE ROOM LEVEL",g.input.mouse_pos);vk_editor_text(r,box.x+14,box.y+84,fmt.tprintf("FLOOR %s  ·  WALLS %s",strings.to_upper(room.floor_material),strings.to_upper(room.wall_material)),{205,207,210,255},.60);hint:=selected.kind==.Edge?"DRAG EDGE  ·  INSERT CORNER VIA TOOLBAR":selected.kind==.Vertex?"DRAG CORNER  ·  REMOVE VIA TOOLBAR":"DRAG EDGE OR CORNER TO RESHAPE";vk_editor_text(r,box.x+14,box.y+108,hint,{102,205,235,255},.60)}}
	if editor_state.selection_count==1&&(editor_state.selection[0].kind==.Room||editor_state.selection[0].kind==.Edge||editor_state.selection[0].kind==.Vertex)&&!editor_state.drag_active {index:=level_room_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {room:=level_document.rooms[index];floor_label:=fmt.tprintf("F %s",strings.to_upper(room.floor_material));wall_label:=fmt.tprintf("W %s",strings.to_upper(room.wall_material));if len(floor_label)>14 do floor_label=floor_label[:14];if len(wall_label)>14 do wall_label=wall_label[:14];floor_box:=editor_room_material_rect(false);wall_box:=editor_room_material_rect(true);roof_box:=editor_room_roof_rect();roof_index:=level_roof_for_room(&level_document,room.id);roof_label:="ADD ROOF";if roof_index>=0 {roof:=level_document.roofs[roof_index];roof_label=fmt.tprintf("ROOF %s  ·  %d°",strings.to_upper(level_roof_style_name(roof.style)),int(roof.pitch))};vulkan_ui_rect(r,938,228,250,106,{10,14,18,232});vulkan_ui_outline(r,938,124,250,210,{90,100,112,190},1);vulkan_ui_rect(r,946,200,232,28,{10,14,18,255});vk_editor_pill(r,floor_box,floor_label);vk_editor_pill(r,wall_box,wall_label);vk_editor_pill(r,roof_box,roof_label);vk_editor_text(r,950,272,"FLOOR",{205,207,210,255},.48);vk_editor_text(r,950,296,"WALLS",{205,207,210,255},.48);for color,i in ROOM_TINT_PALETTE {for row in 0..<2 {swatch:=editor_room_tint_rect(row==1,i);active:=(row==0&&room.floor_tint==color)||(row==1&&room.wall_tint==color);vulkan_ui_rect(r,swatch.x,swatch.y,swatch.w,swatch.h,color);vulkan_ui_outline(r,swatch.x,swatch.y,swatch.w,swatch.h,active?[4]u8{102,205,235,255}:[4]u8{220,224,228,180},active?3:1);vk_editor_action_tooltip(r,swatch,row==0?"TINT FLOOR COVERING":"TINT WALL COVERING",g.input.mouse_pos)}};vk_editor_action_tooltip(r,floor_box,"EDIT FLOOR MATERIAL",g.input.mouse_pos);vk_editor_action_tooltip(r,wall_box,"EDIT WALL MATERIAL",g.input.mouse_pos);vk_editor_action_tooltip(r,roof_box,roof_index>=0?"EDIT AUTHORED ROOF":"ADD ROOF TO ROOM",g.input.mouse_pos)}}
	if editor_state.selection_count==1&&editor_state.selection[0].kind==.Object&&!editor_state.drag_active {index:=level_object_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {object:=level_document.objects[index];box:=editor_object_inspector_rect();vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{10,14,18,232});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,{90,100,112,190},1);name:=strings.to_upper(object.catalog_id);if len(name)>26 do name=name[:26];vk_editor_text(r,box.x+14,box.y+14,name,{255,218,112,255},.60);id:=strings.to_upper(object.id);if len(id)>30 do id=id[:30];vk_editor_text(r,box.x+14,box.y+37,id,{205,207,210,255},.60);elevation_down:=editor_compact_inspector_step_rect(174,-1);elevation_up:=editor_compact_inspector_step_rect(174,1);vk_editor_parameter_button(r,elevation_down,.Height,-1,g.input.mouse_pos,object.elevation>-5);vk_editor_text(r,1000,183,fmt.tprintf("HEIGHT %.2fm",object.elevation),{248,247,242,255},.60);vk_editor_parameter_button(r,elevation_up,.Height,1,g.input.mouse_pos,object.elevation<20);vk_editor_action_tooltip(r,elevation_down,"LOWER OBJECT",g.input.mouse_pos);vk_editor_action_tooltip(r,elevation_up,"RAISE OBJECT",g.input.mouse_pos);rotation_down:=editor_compact_inspector_step_rect(210,-1);rotation_up:=editor_compact_inspector_step_rect(210,1);vk_editor_parameter_button(r,rotation_down,.Rotate,-1,g.input.mouse_pos);vk_editor_text(r,1000,219,fmt.tprintf("ANGLE %d°",int(object.rotation)%360),{248,247,242,255},.60);vk_editor_parameter_button(r,rotation_up,.Rotate,1,g.input.mouse_pos);vk_editor_action_tooltip(r,rotation_down,"ROTATE LEFT 15°",g.input.mouse_pos);vk_editor_action_tooltip(r,rotation_up,"ROTATE RIGHT 15°",g.input.mouse_pos);x_down:=editor_compact_inspector_step_rect(246,-1);x_up:=editor_compact_inspector_step_rect(246,1);vk_button(r,x_down,"X-");vk_editor_text(r,1000,255,fmt.tprintf("X %.2fm",object.position.x),{248,247,242,255},.60);vk_button(r,x_up,"X+");vk_editor_action_tooltip(r,x_down,"MOVE LEFT BY SNAP",g.input.mouse_pos);vk_editor_action_tooltip(r,x_up,"MOVE RIGHT BY SNAP",g.input.mouse_pos);y_down:=editor_compact_inspector_step_rect(282,-1);y_up:=editor_compact_inspector_step_rect(282,1);vk_button(r,y_down,"Y-");vk_editor_text(r,1000,291,fmt.tprintf("Y %.2fm",object.position.y),{248,247,242,255},.60);vk_button(r,y_up,"Y+");vk_editor_action_tooltip(r,y_down,"MOVE DOWN BY SNAP",g.input.mouse_pos);vk_editor_action_tooltip(r,y_up,"MOVE UP BY SNAP",g.input.mouse_pos);entry,found:=catalog_object_entry(object.catalog_id);if found&&entry.category=="foliage" {vk_editor_text(r,box.x+14,box.y+204,"BARK",{205,207,210,255},.60);vk_editor_text(r,box.x+14,box.y+228,"LEAVES",{205,207,210,255},.60);for color,i in FOLIAGE_COLOR_PALETTE {for row in 0..<2 {swatch:=editor_object_color_rect(row,i);vulkan_ui_rect(r,swatch.x,swatch.y,swatch.w,swatch.h,color);vulkan_ui_outline(r,swatch.x,swatch.y,swatch.w,swatch.h,{220,224,228,180},1)}}}else{support_label:=object.support_id!=""?fmt.tprintf("ON %s",strings.to_upper(object.support_id)):fmt.tprintf("STORY %d",object.story+1);if len(support_label)>34 do support_label=support_label[:34];vk_editor_text(r,box.x+14,box.y+204,support_label,{205,207,210,255},.60);vk_editor_text(r,box.x+14,box.y+228,"DRAG TO MOVE · ARROWS NUDGE",{102,205,235,255},.60)}}}
	if editor_state.selection_count==1&&editor_state.selection[0].kind==.Object&&!editor_state.drag_active {index:=level_object_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {object:=level_document.objects[index];fields:=[4]Editor_Numeric_Field{.Object_Height,.Object_Angle,.Object_X,.Object_Y};prefixes:=[4]string{"HEIGHT ","ANGLE ","X ","Y "};values:=[4]string{fmt.tprintf("HEIGHT %.2fm",object.elevation),fmt.tprintf("ANGLE %d°",int(object.rotation)%360),fmt.tprintf("X %.2fm",object.position.x),fmt.tprintf("Y %.2fm",object.position.y)};for field,i in fields do vk_editor_numeric_field(r,editor_object_numeric_rect(field),field,prefixes[i],values[i],g.input.mouse_pos)}}
	if editor_state.selection_count==1&&editor_state.selection[0].kind==.Foundation&&!editor_state.drag_active {index:=level_foundation_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {foundation:=level_document.foundations[index];box:=editor_selection_inspector_rect();vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{10,14,18,232});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,{90,100,112,190},1);vk_editor_text(r,box.x+14,box.y+14,fmt.tprintf("%s FOUNDATION",strings.to_upper(level_foundation_kind_name(foundation.kind))),{255,218,112,255},.60);id:=strings.to_upper(foundation.id);if len(id)>30 do id=id[:30];vk_editor_text(r,box.x+14,box.y+37,id,{205,207,210,255},.60);area:=math.abs(level_polygon_area(foundation.points[:]));support:=foundation.story>=0?fmt.tprintf("STORY %d",foundation.story+1):"GROUND SUPPORT";vk_editor_text(r,box.x+14,box.y+61,fmt.tprintf("%.1f SQM  ·  %d CORNERS  ·  %s",area,len(foundation.points),support),{248,247,242,255},.60);measure_down:=editor_compact_inspector_step_rect(198,-1);measure_up:=editor_compact_inspector_step_rect(198,1);measure_value:=foundation.kind==.Raised?foundation.elevation:foundation.depth;measure_name:=foundation.kind==.Raised?"HEIGHT":foundation.kind==.Basement?"DEPTH":"THICK";minimum:=foundation.kind==.Basement?f32(1.8):foundation.kind==.Raised?f32(.25):f32(.1);maximum:=foundation.kind==.Basement?f32(6):foundation.kind==.Raised?f32(3):f32(1);vk_editor_parameter_button(r,measure_down,.Height,-1,g.input.mouse_pos,measure_value>minimum);vk_editor_text(r,994,207,fmt.tprintf("%s %.2fm",measure_name,measure_value),{248,247,242,255},.60);vk_editor_parameter_button(r,measure_up,.Height,1,g.input.mouse_pos,measure_value<maximum);vk_editor_action_tooltip(r,measure_down,fmt.tprintf("DECREASE %s",measure_name),g.input.mouse_pos);vk_editor_action_tooltip(r,measure_up,fmt.tprintf("INCREASE %s",measure_name),g.input.mouse_pos);vk_editor_text(r,box.x+14,box.y+108,"CREATE SHELL OR DELETE VIA TOOLBAR",{102,205,235,255},.60)}}
	if editor_state.selection_count==1&&editor_state.selection[0].kind==.Roof&&!editor_state.drag_active {index:=level_roof_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {roof:=level_document.roofs[index];box:=editor_roof_inspector_rect();vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{10,14,18,242});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,{255,218,112,220},2);vk_editor_text(r,box.x+14,box.y+14,fmt.tprintf("%s  ·  ROOF",strings.to_upper(level_roof_style_name(roof.style))),{255,218,112,255},.66);id:=strings.to_upper(roof.id);if len(id)>30 do id=id[:30];vk_editor_text(r,box.x+14,box.y+38,id,{205,207,210,255},.66);fields:=[3]Editor_Numeric_Field{.Roof_Pitch,.Roof_Overhang,.Roof_Ridge};prefixes:=[3]string{"PITCH ","EAVE ","RIDGE "};values:=[3]string{fmt.tprintf("PITCH %.1f°",roof.pitch),fmt.tprintf("EAVE %.2fm",roof.overhang),fmt.tprintf("RIDGE %.1f°",roof.ridge_angle)};for field,i in fields do vk_editor_numeric_field(r,editor_roof_numeric_rect(field),field,prefixes[i],values[i],g.input.mouse_pos);vk_editor_text(r,box.x+14,box.y+158,roof.gutters?"GUTTERS ENABLED":"NO GUTTERS",roof.gutters?[4]u8{117,229,169,255}:[4]u8{205,207,210,255},.66);edit_box:=editor_roof_edit_rect();delete_box:=editor_roof_delete_rect();vk_button(r,edit_box,"EDIT ROOF",true);vk_level_icon_button(r,delete_box,6,4);vk_editor_action_tooltip(r,edit_box,"OPEN ROOF CONTROLS FOR THIS ROOM",g.input.mouse_pos);vk_editor_action_tooltip(r,delete_box,"DELETE ROOF",g.input.mouse_pos)}}
	if editor_state.selection_count==1&&editor_state.selection[0].kind==.Object&&!editor_state.drag_active {index:=level_object_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {object:=level_document.objects[index];entry,found:=catalog_object_entry(object.catalog_id);if found&&entry.emits_light {state_button,ok:=editor_selection_action_rect(g,6);power_button,_:=editor_selection_action_rect(g,7);if ok {vk_button(r,state_button,object.initially_active?"ON":"OFF");vk_button(r,power_button,object.powered?"PWR":"DEAD");vk_editor_action_tooltip(r,state_button,"TOGGLE INITIAL APPLIANCE STATE",g.input.mouse_pos);vk_editor_action_tooltip(r,power_button,"TOGGLE APPLIANCE POWER",g.input.mouse_pos)}}}}
	if editor_state.selection_count==1&&editor_state.selection[0].kind==.Opening&&!editor_state.drag_active {index:=level_opening_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {opening:=level_document.openings[index];box:=editor_opening_inspector_rect();vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{10,14,18,232});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,{90,100,112,190},1);vk_editor_text(r,box.x+14,box.y+14,fmt.tprintf("%s OPENING",strings.to_upper(level_opening_kind_name(opening.kind))),{255,218,112,255},.60);id:=strings.to_upper(opening.id);if len(id)>30 do id=id[:30];vk_editor_text(r,box.x+14,box.y+37,id,{205,207,210,255},.60);path_index:=level_path_index(&level_document,opening.host_path);story:=path_index>=0?level_document.paths[path_index].story+1:0;host:=strings.to_upper(opening.host_path);if len(host)>16 do host=host[:16];vk_editor_text(r,box.x+14,box.y+61,fmt.tprintf("%s · SEG %d · STORY %d",host,opening.segment+1,story),{205,207,210,255},.60);fields:=[4]Editor_Numeric_Field{.Opening_Position,.Opening_Width,.Opening_Height,.Opening_Sill};prefixes:=[4]string{"POSITION ","WIDTH ","HEIGHT ","SILL "};values:=[4]string{fmt.tprintf("POSITION %d%%",int(opening.position*100)),fmt.tprintf("WIDTH %.2fm",opening.width),fmt.tprintf("HEIGHT %.2fm",opening.height),fmt.tprintf("SILL %.2fm",opening.sill_height)};row_count:=opening.kind==.Window?4:3;for i in 0..<row_count {field:=fields[i];vk_editor_numeric_field(r,editor_opening_numeric_rect(field),field,prefixes[i],values[i],g.input.mouse_pos)};hint_y:=opening.kind==.Window?box.y+218:box.y+182;vk_editor_text(r,box.x+14,hint_y,"DRAG TO SLIDE · TOOLBAR FOR STYLE",{102,205,235,255},.60)}}
	if editor_state.selection_count==1&&editor_state.selection[0].kind==.Path&&!editor_state.drag_active {index:=level_path_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {path:=level_document.paths[index];box:=editor_selection_inspector_rect();vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{10,14,18,232});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,{90,100,112,190},1);kind_name:=strings.to_upper(fmt.tprintf("%v",path.kind));vk_editor_text(r,box.x+14,box.y+14,fmt.tprintf("%s  ·  PATH",kind_name),{255,218,112,255},.60);id:=strings.to_upper(path.id);if len(id)>30 do id=id[:30];vk_editor_text(r,box.x+14,box.y+37,id,{205,207,210,255},.60);vk_editor_text(r,box.x+14,box.y+61,fmt.tprintf("%d POINTS  ·  STORY %d  ·  %s",len(path.points),path.story+1,strings.to_upper(path.material)),{248,247,242,255},.60);width_down:=editor_compact_inspector_step_rect(198,-1);width_up:=editor_compact_inspector_step_rect(198,1);minimum:=path.kind==.Wall?f32(.1):f32(.2);maximum:=path.kind==.Wall?f32(1):f32(8);vk_editor_parameter_button(r,width_down,.Width,-1,g.input.mouse_pos,path.width>minimum);vk_editor_text(r,994,207,fmt.tprintf("WIDTH %.2fm",path.width),{248,247,242,255},.60);vk_editor_parameter_button(r,width_up,.Width,1,g.input.mouse_pos,path.width<maximum);vk_editor_action_tooltip(r,width_down,"NARROWER PATH",g.input.mouse_pos);vk_editor_action_tooltip(r,width_up,"WIDER PATH",g.input.mouse_pos);vk_editor_text(r,box.x+14,box.y+108,"DELETE VIA TOOLBAR OR KEYBOARD",{102,205,235,255},.60)}}
	if editor_state.selection_count==1&&editor_state.selection[0].kind==.Water&&!editor_state.drag_active {index:=level_water_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {water:=level_document.waters[index];box:=editor_selection_inspector_rect();vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{10,14,18,232});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,{90,100,112,190},1);vk_editor_text(r,box.x+14,box.y+14,"POND  ·  WATER",{255,218,112,255},.60);id:=strings.to_upper(water.id);if len(id)>30 do id=id[:30];vk_editor_text(r,box.x+14,box.y+37,id,{205,207,210,255},.60);area:=math.abs(level_polygon_area(water.points[:]));vk_editor_text(r,box.x+14,box.y+61,fmt.tprintf("%.1f SQM  ·  %d SHORE POINTS",area,len(water.points)),{248,247,242,255},.60);height_down:=editor_compact_inspector_step_rect(198,-1);height_up:=editor_compact_inspector_step_rect(198,1);vk_editor_parameter_button(r,height_down,.Height,-1,g.input.mouse_pos,water.elevation> -5);vk_editor_text(r,994,207,fmt.tprintf("SURFACE %.2fm",water.elevation),{248,247,242,255},.60);vk_editor_parameter_button(r,height_up,.Height,1,g.input.mouse_pos,water.elevation<5);vk_editor_action_tooltip(r,height_down,"LOWER WATER SURFACE",g.input.mouse_pos);vk_editor_action_tooltip(r,height_up,"RAISE WATER SURFACE",g.input.mouse_pos);vk_editor_text(r,box.x+14,box.y+108,"DELETE VIA TOOLBAR OR KEYBOARD",{102,205,235,255},.60)}}
	if editor_state.selection_count==1&&editor_state.selection[0].kind==.Vertical_Link&&!editor_state.drag_active {index:=level_vertical_link_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {link:=level_document.vertical_links[index];box:=editor_selection_inspector_rect();vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{10,14,18,232});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,{90,100,112,190},1);vk_editor_text(r,box.x+14,box.y+14,fmt.tprintf("%s  ·  VERTICAL LINK",strings.to_upper(level_link_kind_name(link.kind))),{255,218,112,255},.60);id:=strings.to_upper(link.id);if len(id)>30 do id=id[:30];vk_editor_text(r,box.x+14,box.y+37,id,{205,207,210,255},.60);distance:=f32(math.sqrt(f64((link.finish.x-link.start.x)*(link.finish.x-link.start.x)+(link.finish.y-link.start.y)*(link.finish.y-link.start.y))));vk_editor_text(r,box.x+14,box.y+61,fmt.tprintf("STORY %d → %d  ·  RUN %.1fm",link.from_story+1,link.to_story+1,distance),{248,247,242,255},.60);width_down:=editor_compact_inspector_step_rect(198,-1);width_up:=editor_compact_inspector_step_rect(198,1);vk_editor_parameter_button(r,width_down,.Width,-1,g.input.mouse_pos,link.width>.6);vk_editor_text(r,994,207,fmt.tprintf("WIDTH %.2fm",link.width),{248,247,242,255},.60);vk_editor_parameter_button(r,width_up,.Width,1,g.input.mouse_pos,link.width<3);vk_editor_action_tooltip(r,width_down,"NARROWER LINK",g.input.mouse_pos);vk_editor_action_tooltip(r,width_up,"WIDER LINK",g.input.mouse_pos);vk_editor_text(r,box.x+14,box.y+108,"DELETE VIA TOOLBAR OR KEYBOARD",{102,205,235,255},.60)}}
	if editor_state.selection_count==1&&!editor_state.drag_active {selected:=editor_state.selection[0];field:=Editor_Numeric_Field.None;prefix:="";label:="";#partial switch selected.kind {case .Room,.Edge,.Vertex:index:=level_room_index(&level_document,selected.entity_id);if index>=0 {field=.Room_Level;prefix="LEVEL ";label=fmt.tprintf("LEVEL %.2fm",level_document.rooms[index].platform_height)};case .Foundation:index:=level_foundation_index(&level_document,selected.entity_id);if index>=0 {foundation:=level_document.foundations[index];field=.Foundation_Measure;prefix=foundation.kind==.Raised?"HEIGHT ":foundation.kind==.Basement?"DEPTH ":"THICK ";measure:=foundation.kind==.Raised?foundation.elevation:foundation.depth;label=fmt.tprintf("%s%.2fm",prefix,measure)};case .Path:index:=level_path_index(&level_document,selected.entity_id);if index>=0 {field=.Path_Width;prefix="WIDTH ";label=fmt.tprintf("WIDTH %.2fm",level_document.paths[index].width)};case .Water:index:=level_water_index(&level_document,selected.entity_id);if index>=0 {field=.Water_Surface;prefix="SURFACE ";label=fmt.tprintf("SURFACE %.2fm",level_document.waters[index].elevation)};case .Vertical_Link:index:=level_vertical_link_index(&level_document,selected.entity_id);if index>=0 {field=.Link_Width;prefix="WIDTH ";label=fmt.tprintf("WIDTH %.2fm",level_document.vertical_links[index].width)}};if field!=.None do vk_editor_numeric_field(r,editor_compact_numeric_rect(field),field,prefix,label,g.input.mouse_pos,"CLICK TO TYPE EXACT VALUE","TYPE VALUE · ENTER APPLY · ESC CANCEL")}
	if editor_state.selection_count>0&&editor_state.selection[0].kind==.Marker {index:=level_marker_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {marker:=level_document.markers[index];vulkan_ui_rect(r,906,124,282,310,{10,14,18,242});vulkan_ui_outline(r,906,124,282,310,{90,100,112,220},1);vk_editor_text(r,920,140,"GAMEPLAY MARKER",{255,218,112,255},.48);name_box:=editor_marker_name_rect();if editor_state.marker_name_active {vulkan_ui_rect(r,name_box.x,name_box.y,name_box.w,name_box.h,{24,32,42,255});vulkan_ui_outline(r,name_box.x,name_box.y,name_box.w,name_box.h,{102,205,235,255},2);vk_editor_text(r,name_box.x+6,name_box.y+8,editor_marker_name_text(),{248,247,242,255},.31)}else{vk_editor_text(r,920,158,strings.to_upper(marker.id),{205,207,210,255},.32);vk_editor_action_tooltip(r,name_box,"CLICK TO RENAME MARKER",g.input.mouse_pos)};vk_button(r,editor_inspector_step_rect(178,-1),"<");vk_editor_text(r,966,187,strings.to_upper(level_marker_kind_name(marker.kind)),{248,247,242,255},.42);vk_button(r,editor_inspector_step_rect(178,1),">");vk_editor_action_tooltip(r,editor_inspector_step_rect(178,-1),"PREVIOUS MARKER TYPE",g.input.mouse_pos);vk_editor_action_tooltip(r,editor_inspector_step_rect(178,1),"NEXT MARKER TYPE",g.input.mouse_pos);vk_editor_text(r,920,224,marker.kind==.Transition?"DESTINATION":"STORY BINDING",{205,207,210,255},.34);binding:=marker.kind==.Transition?marker.destination:marker.reference;vk_button(r,editor_inspector_step_rect(248,-1),"<");vk_editor_text(r,966,257,binding==""?"UNBOUND":strings.to_upper(binding),binding==""?[4]u8{255,190,92,255}:[4]u8{117,229,169,255},.34);vk_button(r,editor_inspector_clear_rect(248),"X");vk_button(r,editor_inspector_step_rect(248,1),">");vk_editor_action_tooltip(r,editor_inspector_step_rect(248,-1),"PREVIOUS BINDING",g.input.mouse_pos);vk_editor_action_tooltip(r,editor_inspector_clear_rect(248),"CLEAR BINDING",g.input.mouse_pos);vk_editor_action_tooltip(r,editor_inspector_step_rect(248,1),"NEXT BINDING",g.input.mouse_pos);vk_editor_text(r,920,294,fmt.tprintf("POSITION   %.2f, %.2f",marker.position.x,marker.position.y),{205,207,210,255},.35);vk_editor_parameter_button(r,editor_inspector_step_rect(318,-1),.Radius,-1,g.input.mouse_pos,marker.radius>.1);vk_editor_text(r,966,327,fmt.tprintf("RADIUS   %.1fm",marker.radius),{248,247,242,255},.38);vk_editor_parameter_button(r,editor_inspector_step_rect(318,1),.Radius,1,g.input.mouse_pos,marker.radius<12);vk_editor_action_tooltip(r,editor_inspector_step_rect(318,-1),"REDUCE RADIUS",g.input.mouse_pos);vk_editor_action_tooltip(r,editor_inspector_step_rect(318,1),"INCREASE RADIUS",g.input.mouse_pos);vk_editor_parameter_button(r,editor_inspector_step_rect(354,-1),.Rotate,-1,g.input.mouse_pos);vk_editor_text(r,966,363,fmt.tprintf("FACING   %d°",int(marker.facing)),{248,247,242,255},.38);vk_editor_parameter_button(r,editor_inspector_step_rect(354,1),.Rotate,1,g.input.mouse_pos);vk_editor_action_tooltip(r,editor_inspector_step_rect(354,-1),"ROTATE LEFT",g.input.mouse_pos);vk_editor_action_tooltip(r,editor_inspector_step_rect(354,1),"ROTATE RIGHT",g.input.mouse_pos);if marker.kind==.Camera {vk_editor_parameter_button(r,editor_inspector_step_rect(390,-1),.Height,-1,g.input.mouse_pos,marker.camera_height>.1);vk_editor_text(r,966,399,fmt.tprintf("HEIGHT   %.1fm",marker.camera_height),{248,247,242,255},.38);vk_editor_parameter_button(r,editor_inspector_step_rect(390,1),.Height,1,g.input.mouse_pos);vk_editor_action_tooltip(r,editor_inspector_step_rect(390,-1),"LOWER CAMERA",g.input.mouse_pos);vk_editor_action_tooltip(r,editor_inspector_step_rect(390,1),"RAISE CAMERA",g.input.mouse_pos)}}}
	if editor_state.selection_count==1&&editor_state.selection[0].kind==.Marker {index:=level_marker_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {marker:=level_document.markers[index];fields:=[3]Editor_Numeric_Field{.Marker_Radius,.Marker_Facing,.Marker_Height};prefixes:=[3]string{"RADIUS ","FACING ","HEIGHT "};values:=[3]string{fmt.tprintf("RADIUS %.2fm",marker.radius),fmt.tprintf("FACING %.1f°",marker.facing),fmt.tprintf("HEIGHT %.2fm",marker.camera_height)};count:=marker.kind==.Camera?3:2;for i in 0..<count {field:=fields[i];vk_editor_numeric_field(r,editor_marker_numeric_rect(field),field,prefixes[i],values[i],g.input.mouse_pos)}}}
	if editor_state.selection_count>0&&editor_state.selection[0].kind==.Light {index:=level_light_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {light:=level_document.lights[index];vulkan_ui_rect(r,906,124,282,274,{10,14,18,242});vulkan_ui_outline(r,906,124,282,274,{90,100,112,220},1);vk_editor_text(r,920,140,"AUTHORED LIGHT",{255,218,112,255},.48);vk_editor_text(r,920,158,strings.to_upper(light.id),{205,207,210,255},.32);vk_button(r,editor_inspector_step_rect(178,-1),"<");vk_editor_text(r,966,187,strings.to_upper(level_light_kind_name(light.kind)),{248,247,242,255},.42);vk_button(r,editor_inspector_step_rect(178,1),">");vk_editor_action_tooltip(r,editor_inspector_step_rect(178,-1),"PREVIOUS LIGHT TYPE",g.input.mouse_pos);vk_editor_action_tooltip(r,editor_inspector_step_rect(178,1),"NEXT LIGHT TYPE",g.input.mouse_pos);vk_editor_parameter_button(r,editor_inspector_step_rect(248,-1),.Range,-1,g.input.mouse_pos,light.range>.5);vk_editor_text(r,966,257,fmt.tprintf("RANGE   %.1fm",light.range),{248,247,242,255},.38);vk_editor_parameter_button(r,editor_inspector_step_rect(248,1),.Range,1,g.input.mouse_pos,light.range<40);vk_editor_action_tooltip(r,editor_inspector_step_rect(248,-1),"REDUCE RANGE",g.input.mouse_pos);vk_editor_action_tooltip(r,editor_inspector_step_rect(248,1),"INCREASE RANGE",g.input.mouse_pos);vk_editor_parameter_button(r,editor_inspector_step_rect(294,-1),.Intensity,-1,g.input.mouse_pos,light.intensity>.1);vk_editor_text(r,966,303,fmt.tprintf("INTENSITY   %.1fx",light.intensity),{248,247,242,255},.38);vk_editor_parameter_button(r,editor_inspector_step_rect(294,1),.Intensity,1,g.input.mouse_pos,light.intensity<100);vk_editor_action_tooltip(r,editor_inspector_step_rect(294,-1),"REDUCE INTENSITY",g.input.mouse_pos);vk_editor_action_tooltip(r,editor_inspector_step_rect(294,1),"INCREASE INTENSITY",g.input.mouse_pos);vk_editor_parameter_button(r,editor_inspector_step_rect(340,-1),.Height,-1,g.input.mouse_pos,light.elevation>0);vk_editor_text(r,966,349,fmt.tprintf("HEIGHT   %.1fm",light.elevation),{248,247,242,255},.38);vk_editor_parameter_button(r,editor_inspector_step_rect(340,1),.Height,1,g.input.mouse_pos,light.elevation<20);vk_editor_action_tooltip(r,editor_inspector_step_rect(340,-1),"LOWER LIGHT",g.input.mouse_pos);vk_editor_action_tooltip(r,editor_inspector_step_rect(340,1),"RAISE LIGHT",g.input.mouse_pos)}}
	if editor_state.selection_count==1&&editor_state.selection[0].kind==.Light {index:=level_light_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {light:=level_document.lights[index];fields:=[3]Editor_Numeric_Field{.Light_Range,.Light_Intensity,.Light_Height};prefixes:=[3]string{"RANGE ","INTENSITY ","HEIGHT "};values:=[3]string{fmt.tprintf("RANGE %.2fm",light.range),fmt.tprintf("INTENSITY %.2fx",light.intensity),fmt.tprintf("HEIGHT %.2fm",light.elevation)};for field,i in fields do vk_editor_numeric_field(r,editor_light_numeric_rect(field),field,prefixes[i],values[i],g.input.mouse_pos)}}
	if editor_state.selection_count>0&&!editor_state.drag_active&&editor_state.selection[0].kind==.Foundation&&editor_control_point_index(editor_state.selection[0])<0 {shell,ok:=editor_selection_action_rect(g,0);remove,_:=editor_selection_action_rect(g,1);if ok {origin,_:=editor_selection_toolbar_origin(g);vulkan_ui_rect(r,origin.x-5,origin.y-5,86,36,{10,14,18,230});vk_level_icon_button(r,shell,1,1);vk_level_icon_button(r,remove,6,4);vk_editor_action_tooltip(r,shell,"CREATE SHELL",g.input.mouse_pos);vk_editor_action_tooltip(r,remove,"DELETE",g.input.mouse_pos)}}
	if editor_state.selection_count>0&&!editor_state.drag_active&&editor_state.selection[0].kind==.Path&&editor_control_point_index(editor_state.selection[0])<0 {remove,ok:=editor_selection_action_rect(g,0);if ok {origin,_:=editor_selection_toolbar_origin(g);vulkan_ui_rect(r,origin.x-5,origin.y-5,46,36,{10,14,18,230});vk_level_icon_button(r,remove,6,4);vk_editor_action_tooltip(r,remove,"DELETE PATH",g.input.mouse_pos)}}
	if editor_state.selection_count>0&&!editor_state.drag_active&&editor_state.selection[0].kind==.Water&&editor_control_point_index(editor_state.selection[0])<0 {remove,ok:=editor_selection_action_rect(g,0);if ok {origin,_:=editor_selection_toolbar_origin(g);vulkan_ui_rect(r,origin.x-5,origin.y-5,46,36,{10,14,18,230});vk_level_icon_button(r,remove,6,4);vk_editor_action_tooltip(r,remove,"DELETE POND",g.input.mouse_pos)}}
	if editor_state.selection_count>0&&!editor_state.drag_active&&editor_state.selection[0].kind==.Vertical_Link&&editor_control_point_index(editor_state.selection[0])<0 {remove,ok:=editor_selection_action_rect(g,0);if ok {origin,_:=editor_selection_toolbar_origin(g);vulkan_ui_rect(r,origin.x-5,origin.y-5,46,36,{10,14,18,230});vk_level_icon_button(r,remove,6,4);vk_editor_action_tooltip(r,remove,"DELETE LINK",g.input.mouse_pos)}}
	if editor_state.selection_count>0&&!editor_state.drag_active&&editor_state.selection[0].kind==.Marker {remove,ok:=editor_selection_action_rect(g,0);if ok {origin,_:=editor_selection_toolbar_origin(g);vulkan_ui_rect(r,origin.x-5,origin.y-5,46,36,{10,14,18,230});vk_button(r,remove,"DEL")}}
	if editor_state.selection_count==1&&editor_state.selection[0].kind==.Marker {index:=level_marker_index(&level_document,editor_state.selection[0].entity_id);if index>=0&&!level_marker_uses_binding(level_document.markers[index].kind) {vulkan_ui_rect(r,918,216,258,70,{10,14,18,255});vk_editor_text(r,930,235,"NO BINDING REQUIRED",{117,229,169,255},.60);vk_editor_text(r,930,258,"THIS MARKER IS SELF-CONTAINED",{205,207,210,255},.48)}}
	if editor_state.selection_count==1&&editor_state.selection[0].kind==.Marker {index:=level_marker_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {marker:=level_document.markers[index];fields:=[2]Editor_Numeric_Field{.Marker_X,.Marker_Y};prefixes:=[2]string{"X ","Y "};values:=[2]string{fmt.tprintf("X %.2fm",marker.position.x),fmt.tprintf("Y %.2fm",marker.position.y)};for field,i in fields do vk_editor_numeric_field(r,editor_marker_position_rect(field),field,prefixes[i],values[i],g.input.mouse_pos,"CLICK TO TYPE EXACT POSITION")}}
	if editor_state.selection_count==1&&editor_state.selection[0].kind==.Marker {index:=level_marker_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {marker:=level_document.markers[index];referenced:=false;for node in graph_document.nodes[:graph_document.node_count] {if node.beat.camera==marker.id||node.beat.actor_mark==marker.id||(marker.kind==.Interaction&&marker.reference!=""&&node.beat.interaction==marker.reference)||(marker.kind==.Trigger&&marker.reference!=""&&node.beat.event_id==marker.reference) {referenced=true;break}};vk_graph_button(r,editor_marker_open_graph_rect(),referenced?"OPEN IN GRAPH MODE":"NOT USED IN GRAPH",false)}}
	if editor_state.selection_count==1&&editor_state.selection[0].kind==.Marker {duplicate_box:=editor_marker_duplicate_rect();delete_box:=editor_marker_delete_rect();vk_level_icon_button(r,duplicate_box,6,3);vk_level_icon_button(r,delete_box,6,4);vk_editor_action_tooltip(r,duplicate_box,"DUPLICATE MARKER · OFFSET BY SNAP",g.input.mouse_pos);vk_editor_action_tooltip(r,delete_box,"DELETE MARKER · UNDO AVAILABLE",g.input.mouse_pos)}
	if editor_state.selection_count==1&&editor_state.selection[0].kind==.Light {duplicate_box:=editor_light_duplicate_rect();delete_box:=editor_light_delete_rect();vk_level_icon_button(r,duplicate_box,6,3);vk_level_icon_button(r,delete_box,6,4);vk_editor_action_tooltip(r,duplicate_box,"DUPLICATE LIGHT · OFFSET BY SNAP",g.input.mouse_pos);vk_editor_action_tooltip(r,delete_box,"DELETE LIGHT · UNDO AVAILABLE",g.input.mouse_pos)}
	if editor_state.selection_count==1&&editor_state.selection[0].kind==.Light {index:=level_light_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {light:=level_document.lights[index];vk_editor_text(r,920,220,"COLOR",{205,207,210,255},.60);current:=editor_light_current_color_rect();vulkan_ui_rect(r,current.x+2,current.y+3,current.w,current.h,{0,0,0,90});vulkan_ui_rect(r,current.x,current.y,current.w,current.h,light.color);vulkan_ui_outline(r,current.x,current.y,current.w,current.h,{102,205,235,255},3);vk_editor_action_tooltip(r,current,"CURRENT AUTHORED COLOR",g.input.mouse_pos);for color,i in LIGHT_COLOR_PALETTE {swatch:=editor_light_color_rect(light.kind,i);active:=light.color==color;vulkan_ui_rect(r,swatch.x+2,swatch.y+3,swatch.w,swatch.h,{0,0,0,90});vulkan_ui_rect(r,swatch.x,swatch.y,swatch.w,swatch.h,color);vulkan_ui_outline(r,swatch.x,swatch.y,swatch.w,swatch.h,active?[4]u8{102,205,235,255}:[4]u8{205,207,210,190},active?3:1);vk_editor_action_tooltip(r,swatch,"SET LIGHT COLOR",g.input.mouse_pos)}}}
	if editor_state.selection_count==1&&editor_state.selection[0].kind==.Light {index:=level_light_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {light:=level_document.lights[index];if light.kind!=.Point {extension_height:=light.kind==.Spot?f32(80):f32(34);vulkan_ui_rect(r,906,398,282,extension_height,{10,14,18,242});vulkan_ui_outline(r,906,124,282,274+extension_height,{90,100,112,220},1);fields:=[2]Editor_Numeric_Field{.Light_Facing,.Light_Cone};prefixes:=[2]string{"FACING ","CONE "};values:=[2]string{fmt.tprintf("FACING %.1f°",light.facing),fmt.tprintf("CONE %.1f°",light.cone_angle)};count:=light.kind==.Spot?2:1;for i in 0..<count {field:=fields[i];y:=i==0?f32(386):f32(432);box:=editor_light_numeric_rect(field);vk_editor_parameter_button(r,editor_inspector_step_rect(y,-1),i==0?.Rotate:.Cone,-1,g.input.mouse_pos,i==0||light.cone_angle>5);vk_editor_numeric_field(r,box,field,prefixes[i],values[i],g.input.mouse_pos);vk_editor_parameter_button(r,editor_inspector_step_rect(y,1),i==0?.Rotate:.Cone,1,g.input.mouse_pos,i==0||light.cone_angle<160);vk_editor_action_tooltip(r,editor_inspector_step_rect(y,-1),i==0?"ROTATE LIGHT LEFT 15°":"NARROW CONE 5°",g.input.mouse_pos);vk_editor_action_tooltip(r,editor_inspector_step_rect(y,1),i==0?"ROTATE LIGHT RIGHT 15°":"WIDEN CONE 5°",g.input.mouse_pos)}}}}
	if editor_state.selection_count>1&&!editor_state.drag_active {vk_panel(r,350,602,510,42);vk_editor_text(r,366,616,fmt.tprintf("%d SELECTED",editor_state.selection_count),{102,205,235,255},.60);align_x:=editor_multi_action_rect(0);align_y:=editor_multi_action_rect(1);copy_box:=editor_multi_action_rect(2);duplicate_box:=editor_multi_action_rect(3);delete_box:=editor_multi_action_rect(4);vk_button(r,align_x,"AX");vk_button(r,align_y,"AY");vk_button(r,copy_box,"COPY");vk_button(r,duplicate_box,"DUP");vk_level_icon_button(r,delete_box,6,4);vk_editor_action_tooltip(r,align_x,"ALIGN X TO FIRST SELECTED",g.input.mouse_pos);vk_editor_action_tooltip(r,align_y,"ALIGN Y TO FIRST SELECTED",g.input.mouse_pos);vk_editor_action_tooltip(r,copy_box,"COPY SELECTION · CTRL/CMD C",g.input.mouse_pos);vk_editor_action_tooltip(r,duplicate_box,"DUPLICATE SELECTION · CTRL/CMD D",g.input.mouse_pos);vk_editor_action_tooltip(r,delete_box,"DELETE SELECTION",g.input.mouse_pos);if editor_state.selection_count>2 {distribute_x:=editor_multi_action_rect(5);distribute_y:=editor_multi_action_rect(6);vk_button(r,distribute_x,"DX");vk_button(r,distribute_y,"DY");vk_editor_action_tooltip(r,distribute_x,"DISTRIBUTE EVENLY ON X",g.input.mouse_pos);vk_editor_action_tooltip(r,distribute_y,"DISTRIBUTE EVENLY ON Y",g.input.mouse_pos)};if editor_state.selection_count==2&&editor_state.selection[0].kind==.Room&&editor_state.selection[1].kind==.Room {merge_box:=Rect{778,608,36,28};merge_command:=level_merge_room_command(editor_state.selection[0].entity_id,editor_state.selection[1].entity_id);preview:=level_preview_transaction(&level_document,merge_command);enabled:=preview.state!=.Blocked;vk_level_icon_button(r,merge_box,1,1,false,enabled);if contains(merge_box,g.input.mouse_pos) {label:=enabled?"MERGE ROOMS":strings.to_upper(preview.message);width:=max(f32(100),f32(utf8_glyph_count(label))*7+16);vk_panel(r,814-width,574,width,26);vk_editor_text(r,822-width,581,label,enabled?[4]u8{117,229,169,255}:[4]u8{255,144,119,255},.60)}}}
	if editor_state.selection_count==1&&editor_state.selection[0].kind==.Opening&&!editor_state.drag_active {index:=level_opening_index(&level_document,editor_state.selection[0].entity_id);style_action,ok:=editor_selection_action_rect(g,7);flip_action,_:=editor_selection_action_rect(g,8);hand_action,_:=editor_selection_action_rect(g,9);if ok&&index>=0&&level_document.openings[index].kind==.Window {opening:=level_document.openings[index];style_name:=strings.to_upper(window_style_name(opening.window_style));action_count:=opening.window_style==.Casement?3:2;vulkan_ui_rect(r,style_action.x-3,style_action.y-3,style_action.w+f32(action_count-1)*EDITOR_SELECTION_ACTION_PITCH+6,style_action.h+6,{10,14,18,220});vk_button(r,style_action,"S");vk_button(r,flip_action,opening.window_flipped?"F*":"F");vk_editor_action_tooltip(r,style_action,fmt.tprintf("STYLE: %s · CLICK TO CHANGE",style_name),g.input.mouse_pos);vk_editor_action_tooltip(r,flip_action,opening.window_flipped?"ROOM SIDE FLIPPED · CLICK FOR AUTOMATIC SIDE":"FLIP WINDOW ROOM SIDE",g.input.mouse_pos);if opening.window_style==.Casement {vk_button(r,hand_action,opening.window_hinge_right?"HR":"HL");vk_editor_action_tooltip(r,hand_action,opening.window_hinge_right?"RIGHT-HINGED · CLICK FOR LEFT":"LEFT-HINGED · CLICK FOR RIGHT",g.input.mouse_pos)}}}
	if editor_state.view_menu_visible {panel:=editor_view_menu_panel_rect();vk_editor_surface(r,panel,true);for view in Editor_View_Mode {box:=editor_view_menu_rect(int(view));vk_editor_pill(r,box,editor_view_name(view),editor_state.view==view);if contains(box,g.input.mouse_pos) do vulkan_ui_outline(r,box.x,box.y,box.w,box.h,{220,235,245,255},2)}}
	help_box:=editor_shortcut_help_rect();vk_button(r,help_box,"?");vk_editor_action_tooltip(r,help_box,"BUILD SHORTCUTS · F1",g.input.mouse_pos);snap_box:=editor_snap_rect();vk_button(r,snap_box,editor_snap_name(),editor_state.snap_mode!=.Off&&!editor_state.snap_suspended);vk_editor_action_tooltip(r,snap_box,editor_state.snap_suspended?"RELEASE ALT TO RESTORE SNAP":"CLICK TO CYCLE SNAP · HOLD ALT FOR NO SNAP",g.input.mouse_pos)
	hint:=g.build_has_anchor?"Step 2 / 2 · Click the wall end · Esc cancels":editor_state.foundation_rectangle_active?"Step 2 / 2 · Release to create foundation · Esc cancels":editor_state.foundation_draw_count>0?fmt.tprintf("Step 2 · Foundation corner %d · click start or Enter to close",editor_state.foundation_draw_count):editor_state.room_rectangle_active?"Step 2 / 2 · Release to create room · Esc cancels":editor_state.room_draw_count>0?fmt.tprintf("Step 2 · Room corner %d · click start or Enter to close",editor_state.room_draw_count):g.build_tool==.Path&&editor_state.path_draw_count>0?fmt.tprintf("Step %d · Path point %d · click to add or Enter to finish",editor_state.path_draw_count<2?2:3,editor_state.path_draw_count):g.build_tool==.Water&&editor_state.water_draw_count>0?fmt.tprintf("Step %d · Shore point %d · add points or Enter to close",editor_state.water_draw_count<3?2:3,editor_state.water_draw_count):g.build_tool==.Stairs&&editor_state.link_anchor_active?"Step 2 / 2 · Click the upper landing · Esc cancels":g.build_tool==.Foundation?(editor_state.foundation_mode==.Rectangle?"Step 1 · Drag footprint · release continues to rooms · Shift repeats":"Step 1 · Click the first foundation corner"):g.build_tool==.Room&&editor_state.room_mode==.Polygon?"Step 1 · Click the first room corner":g.build_tool==.Select&&editor_state.selection_count>0?editor_selection_status_hint(editor_state.selection[0],editor_state.selection_count):editor_build_tool_idle_hint(g.build_tool);width:=max(f32(190),f32(utf8_glyph_count(hint))*7+24);hint_x:=editor_status_hint_x(width);vk_panel(r,hint_x,650,width,30);vk_editor_text(r,hint_x+12,659,hint,{170,218,228,255},.60)
	if editor_state.feedback_frames>0&&editor_state.feedback!="" {feedback_width:=max(f32(250),f32(utf8_glyph_count(editor_state.feedback))*7+24);feedback_x:=editor_status_hint_x(feedback_width);feedback_color:=editor_state.feedback_error?[4]u8{255,144,119,255}:[4]u8{117,229,169,255};vk_panel(r,feedback_x,612,feedback_width,30);vulkan_ui_outline(r,feedback_x,612,feedback_width,30,feedback_color,2);vk_editor_text(r,feedback_x+12,621,editor_state.feedback,feedback_color,.60)}
	if editor_state.shortcut_help_visible {_=vk_ui_dim_all_except(r,nil);vulkan_ui_rect(r,280,112,640,492,{24,31,38,255});vulkan_ui_outline(r,280,112,640,492,{102,205,235,255},3);vk_editor_text(r,310,138,"BUILD MODE SHORTCUTS",{255,218,112,255},.82);vk_editor_text(r,738,140,"F1 OR ESC TO CLOSE",{170,218,228,255},.60);vulkan_ui_rect(r,310,170,580,1,{90,112,126,220});headings:=[3]string{"NAVIGATE & SELECT","EDIT & HISTORY","DRAW & PLACE"};rows:=[3][6]string{{"WASD     PAN CAMERA","WHEEL    ZOOM AT CURSOR","F        FRAME SELECTION","[ / ]    PREV/NEXT ISSUE","SHIFT    ADD/REMOVE","V / SHIFT V  VIEWS"},{"CMD/CTRL Z   UNDO","CMD/CTRL SHIFT Z REDO","CMD/CTRL S   SAVE","CMD/CTRL C   COPY","CMD/CTRL D   DUPLICATE","DELETE       REMOVE"},{"ENTER    FINISH / APPLY","/        SEARCH CATALOG","CLICK VALUE  TYPE EXACT","TAB      NEXT VALUE","SHIFT TAB  PREVIOUS VALUE","CLICK    APPLY/PLACE"}};for column in 0..<3 {x:=f32(310+column*198);vk_editor_text(r,x,194,headings[column],{102,205,235,255},.60);for row in 0..<6 do vk_editor_text(r,x,228+f32(row)*38,rows[column][row],{235,237,238,255},.60)};vulkan_ui_rect(r,310,474,580,1,{90,112,126,220});vk_editor_text(r,310,496,"TOOL KEYS",{255,218,112,255},.60);vk_editor_text(r,310,526,"1 Select · 2 Room · 3 Foundation · 4 Paint · 5 Objects · 6 Roof",{205,207,210,255},.60);vk_editor_text(r,310,558,"7 Terrain · 8 Stairs · 9 Path · 0 Water · M Markers",{117,229,169,255},.60)}
	if editor_state.exit_confirm_visible {_=vk_ui_dim_all_except(r,nil,{4,7,10,200});vulkan_ui_rect(r,280,242,640,254,{24,31,38,255});vulkan_ui_outline(r,280,242,640,254,{255,211,92,255},3);vk_editor_text(r,320,274,"UNSAVED LEVEL CHANGES",{255,218,112,255},.82);vk_editor_text(r,320,314,"The current level has changes that are not in the main level file.",{235,237,238,255},.60);vk_editor_text(r,320,344,"An autosave exists, but Save & Exit is the safest choice.",{170,218,228,255},.60);vulkan_ui_rect(r,320,390,560,1,{90,112,126,220});vk_button(r,editor_exit_save_rect(),"SAVE & EXIT",true);vk_button(r,editor_exit_autosave_rect(),"EXIT · KEEP AUTOSAVE");vk_button(r,editor_exit_cancel_rect(),"CANCEL");vk_editor_text(r,320,478,"ESC RETURNS TO BUILD MODE",{205,207,210,255},.60)}
	vk_editor_action_tooltip(r,editor_top_close_rect(),"EXIT BUILD MODE · F10",g.input.mouse_pos);vk_editor_action_tooltip(r,editor_top_save_rect(),"SAVE LEVEL · CTRL/CMD S",g.input.mouse_pos);vk_editor_action_tooltip(r,editor_top_undo_rect(),"UNDO · CTRL/CMD Z",g.input.mouse_pos);vk_editor_action_tooltip(r,editor_top_redo_rect(),"REDO · CTRL/CMD SHIFT Z",g.input.mouse_pos);vk_editor_action_tooltip(r,editor_top_view_rect(),fmt.tprintf("V NEXT: %s · SHIFT V PREVIOUS",editor_view_name(editor_adjacent_view(editor_state.view))),g.input.mouse_pos);vk_editor_action_tooltip(r,editor_top_validate_rect(),"VALIDATE LEVEL",g.input.mouse_pos);if editor_state.recovery_available do vk_editor_action_tooltip(r,editor_top_recovery_rect(),"RESTORE AUTOSAVE · REPLACES CURRENT UNSAVED STATE",g.input.mouse_pos);vk_editor_action_tooltip(r,editor_top_play_rect(),"VALIDATE AND PLAYTEST",g.input.mouse_pos)
}

vk_dialogue_ledger_line :: proc(r:^Vulkan_Backend,x,y,width:f32,speaker,text:string,color:[4]u8)->f32 {
	// A turn reads as a paragraph, with one stable text edge. The colored rule
	// makes speaker changes visible without forcing the eye across two columns.
	vulkan_ui_rect(r,x,y+2,3,14,color)
	vk_text(r,x+12,y,strings.to_upper(speaker),color,.68)
	return vk_text_wrapped(r,x+12,y+19,width-12,text,{248,247,242,255},.70,3)+7
}

dialogue_transcript_entry_height :: proc(entry:^Dialogue_Transcript_Entry,width:f32)->f32 {
	if entry==nil do return 0
	return dialogue_ledger_line_height(dialogue_semantic_text(entry.text,entry.kind),width)
}

vk_draw_character_transcript :: proc(r:^Vulkan_Backend,g:^Game,conversation_id:string)->bool {
	indices:[256]int;count:=0
	for entry,i in g.conversation_transcript[:g.conversation_transcript_count] do if entry.conversation_id==conversation_id&&count<len(indices) {indices[count]=i;count+=1}
	if count==0 do return false
	max_scroll:=max(0,count-1);scroll:=clamp(g.dialogue_ledger_scroll,0,max_scroll);end:=count-scroll;start:=end-1;latest:=&g.conversation_transcript[indices[end-1]];latest_entity:=world_entity_index(latest.speaker);latest_portrait:=latest.kind=="dialogue"&&latest_entity>=0&&WORLD_ENTITIES[latest_entity].kind=="person";latest_width:=latest_portrait?f32(375):f32(445);used:=dialogue_transcript_entry_height(latest,latest_width);if latest_portrait do used=max(used,100)
	for start>0 {candidate:=dialogue_transcript_entry_height(&g.conversation_transcript[indices[start-1]],445);if used+candidate>360 do break;start-=1;used+=candidate}
	// The response block is laid out from this same measured transcript height,
	// so history and choices form one continuous column without reserved space.
	y:=f32(48)
	for position in start..<end {entry:=&g.conversation_transcript[indices[position]];color:=dialogue_semantic_color(entry.kind,{255,218,112,255},1);speaker_entity:=world_entity_index(entry.speaker);portrait:=position==end-1&&entry.kind=="dialogue"&&speaker_entity>=0&&WORLD_ENTITIES[speaker_entity].kind=="person";if portrait {vk_dialogue_portrait(r,646,y,WORLD_ENTITIES[speaker_entity]);line_y:=vk_dialogue_ledger_line(r,730,y,375,dialogue_semantic_label(g,entry.speaker,entry.kind),dialogue_semantic_text(entry.text,entry.kind),color);y=max(line_y,y+100)} else do y=vk_dialogue_ledger_line(r,660,y,445,dialogue_semantic_label(g,entry.speaker,entry.kind),dialogue_semantic_text(entry.text,entry.kind),color)}
	return true
}

dialogue_evidence_type :: proc(entity:World_Entity)->string {
	switch entity.source_id {
	case "ledger": return "DOCUMENT"
	case "memo_stub","burned_note": return "DOCUMENT FRAGMENT"
	case "shutter_crank": return "MECHANISM"
	case "dining_room": return "SCENE ARRANGEMENT"
	case "edgar_watch": return "TIMEPIECE"
	case "garden": return "SCENE TRACE"
	case "pond_reflection": return "REFLECTION"
	case: return "PHYSICAL OBJECT"
	}
}

dialogue_full_evidence_art :: proc(source_id:string)->(UI_Art,bool) {
	switch source_id {
	case "statuette": return .Evidence_Statuette,true
	case "shutter_crank","shutter_thread": return .Evidence_Silk,true
	case "edgar_watch": return .Evidence_Watch,true
	case "dining_room": return .Evidence_Place_Setting,true
	case "ledger": return .Evidence_Ledger,true
	case "memo_stub","burned_note": return .Evidence_Ledger,true
	case "cloth": return .Evidence_Cloth,true
	}
	return {},false
}

vk_dialogue_portrait :: proc(r:^Vulkan_Backend,x,y:f32,entity:World_Entity) {
	vulkan_ui_rect(r,x,y,72,92,{15,17,20,220});vulkan_ui_outline(r,x,y,72,92,{139,107,55,210},1)
	if entity.kind=="person" {
		if officer_source(entity.source_id) {vulkan_ui_rect(r,x+3,y+3,66,86,{28,36,48,255});vulkan_ui_outline(r,x+7,y+7,58,78,{119,190,213,220},1);vk_text(r,x+15,y+15,"POLICE",{119,190,213,255},.52);vk_text(r,x+26,y+36,"◆",{248,247,242,255},1.25);vk_text(r,x+12,y+70,"ON SCENE",{205,207,210,255},.38);return}
		// A generated dossier portrait anchors the speaker without obscuring the scene.
		vk_art_fit(r,portrait_art(entity.source_id),x+3,y+3,66,86)
		return
	}
	// Evidence gets its own archival card; never imply that an object is a person.
	vulkan_ui_rect(r,x+3,y+3,66,86,{25,28,32,255})
	vulkan_ui_outline(r,x+7,y+7,58,78,{78,68,50,230},1)
	vk_text(r,x+13,y+14,"EVIDENCE",{202,166,92,255},.42)
	vulkan_ui_rect(r,x+13,y+29,46,1,{139,107,55,210})
	vk_text(r,x+25,y+34,"◇",{202,166,92,255},1.55)
	vk_text(r,x+14,y+70,"CASE FILE",{190,194,198,255},.38)
}

vk_dialogue_footer_button :: proc(r:^Vulkan_Backend,box:Rect,label:string,accent:[4]u8,enabled:=true) {
	focused:=enabled&&vk_focused_button==button_id(box);surface:=enabled?(focused?[4]u8{48,53,64,250}:[4]u8{22,26,33,242}):[4]u8{19,22,28,210};edge:=enabled?(focused?accent:[4]u8{106,113,126,220}):[4]u8{66,72,82,180};text_color:=enabled?(focused?[4]u8{248,247,242,255}:[4]u8{205,207,210,255}):[4]u8{116,122,133,210}
	vulkan_ui_rect(r,box.x,box.y,box.w,box.h,surface)
	if enabled do vulkan_ui_rect(r,box.x,box.y,focused?f32(7):f32(3),box.h,accent)
	vulkan_ui_outline(r,box.x,box.y,box.w,box.h,edge,focused?f32(2):f32(1))
	if focused do vulkan_ui_triangle(r,{box.x-11,box.y+box.h*.5},{box.x-2,box.y+box.h*.5-6},{box.x-2,box.y+box.h*.5+6},accent)
	vk_text(r,box.x+15,box.y+7,strings.to_upper(label),text_color,.66)
}

vk_dialogue_end_choice :: proc(r:^Vulkan_Backend,box:Rect) {
	focused:=vk_focused_button==button_id(box)
	if focused do vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{38,43,52,220})
	vulkan_ui_rect(r,box.x,box.y,box.w,1,focused?[4]u8{255,211,92,225}:[4]u8{112,118,128,155})
	if focused do vulkan_ui_rect(r,box.x,box.y,3,box.h,{255,211,92,235})
	vk_text(r,box.x+15,box.y+8,"END CONVERSATION",focused?[4]u8{248,247,242,255}:[4]u8{170,176,184,255},.58)
}

vk_dialogue_page_nav :: proc(r:^Vulkan_Backend,prev,next:Rect,page,pages:int,y:f32,color:[4]u8={170,176,184,255}) {
	prev_active:=vk_focused_button==button_id(prev);next_active:=vk_focused_button==button_id(next)
	if prev_active {vulkan_ui_rect(r,prev.x,prev.y,prev.w,prev.h,{38,43,52,220});vulkan_ui_outline(r,prev.x,prev.y,prev.w,prev.h,{255,211,92,210},1)}
	if next_active {vulkan_ui_rect(r,next.x,next.y,next.w,next.h,{38,43,52,220});vulkan_ui_outline(r,next.x,next.y,next.w,next.h,{255,211,92,210},1)}
	vulkan_ui_triangle(r,{prev.x+18,prev.y+5},{prev.x+10,prev.y+10},{prev.x+18,prev.y+15},prev_active?[4]u8{255,211,92,255}:color)
	vulkan_ui_triangle(r,{next.x+12,next.y+5},{next.x+20,next.y+10},{next.x+12,next.y+15},next_active?[4]u8{255,211,92,255}:color)
	label:=fmt.tprintf("%d OF %d",page+1,pages);vk_text(r,1058-f32(utf8_glyph_count(label))*3.1,y,label,color,.42)
}

dialogue_pointer_over_control :: proc(g:^Game)->bool {
	return dialogue_pointer_focus_id(g)!=ui.GUI_ID_NONE
}
dialogue_control_focused :: proc(g:^Game,box:Rect)->bool {
	if dialogue_pointer_over_control(g) do return contains(box,g.input.mouse_pos)
	return g.gui.focused==button_id(box)
}

vk_draw_disposition :: proc(r:^Vulkan_Backend,g:^Game,index:int) {
	payload:=mystery_game_payload(g);if payload==nil||index<0||index>=len(payload.characters) do return
	box:=disposition_rect();value:=mystery_game_disposition(g,payload.characters[index].entity_id);hovered:=g.active_device==.Keyboard_Mouse&&contains(box,g.input.mouse_pos);color:=value>0?[4]u8{102,205,143,255}:value<0?[4]u8{255,144,119,255}:[4]u8{170,190,205,255};state_label:=value>0?"RECEPTIVE":value<0?"GUARDED":"NEUTRAL"
	if hovered {vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{42,47,57,220});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,{205,207,210,190},1)}
	vulkan_ui_rect(r,box.x+2,box.y+11,4,4,color);vk_text(r,box.x+14,box.y+7,dialogue_disposition_label(value),hovered?color:[4]u8{190,184,181,235},.56)
	if !hovered do return
	tx,ty,tw,th:=f32(850),f32(98),f32(300),f32(96);vk_panel(r,tx,ty,tw,th);vk_text(r,tx+16,ty+13,state_label,color,.9);_=vk_text_wrapped(r,tx+16,ty+37,tw-32,disposition_summary(g,index),{248,247,242,255},.68,1);vk_text(r,tx+16,ty+76,fmt.tprintf("CHECK MODIFIER  %+d",clamp(value,-2,2)),color,.64)
}

vk_draw_dialogue :: proc(r:^Vulkan_Backend,g:^Game) {
	if g.pending_dialogue_approach>0 {if node:=mystery_dialogue_approach_at(mystery_game_payload(g),g.pending_dialogue_approach-1);node!=nil {texture:=vulkan_dialogue_asset_texture(r,node.node_id);if texture>=0 do vulkan_ui_quad(r,650,105,490,190,{255,255,255,255},texture,{}, {1,1},true)}}
	if g.dialogue_entity<0||g.dialogue_entity>=len(WORLD_ENTITIES) do return
	entity:=WORLD_ENTITIES[g.dialogue_entity];clue_index:=clue_for_source(g,entity.source_id);payload:=mystery_game_payload(g)
	// One continuous conversation surface holds played beats, checks, available
	// responses, and the exit action in reading order.
	vulkan_ui_rect(r,0,0,1200,720,{0,0,0,118})
	if evidence_art,has_evidence_art:=dialogue_full_evidence_art(entity.source_id);has_evidence_art {
		vulkan_ui_rect(r,38,88,548,544,{12,14,17,238});vulkan_ui_outline(r,38,88,548,544,{139,107,55,220},2)
		vk_text(r,62,108,"CASE EVIDENCE  ·  PHYSICAL EXAMINATION",{202,166,92,255},.62)
		vulkan_ui_rect(r,62,137,500,1,{139,107,55,180})
		vk_art_fit(r,evidence_art,62,154,500,402)
		vk_text(r,62,583,strings.to_upper(entity.name),{255,218,112,255},.86)
		vk_text(r,62,608,strings.to_upper(dialogue_evidence_type(entity)),{190,194,198,255},.52)
	}
	standard_conversation:=entity.kind=="person"&&!officer_source(entity.source_id)
	shell_x:=f32(625);shell_w:=standard_conversation?f32(540):f32(555)
	// Ordinary character dialogue is one tall transcript column. Evidence and
	// special-purpose interactions retain their dedicated identity treatment.
	if !standard_conversation {vulkan_ui_rect(r,625,26,555,120,{12,14,17,232});vulkan_ui_outline(r,625,26,555,120,{213,184,111,205},1)}
	action_bottom:=standard_conversation?f32(694):f32(642)
	if !standard_conversation&&!g.check_from_dialogue&&entity.kind=="person" {end_box:=dialogue_end_rect_for(g);action_bottom=end_box.y+end_box.h+12;if g.end_confirm do action_bottom=642}
	body_top:=standard_conversation?f32(26):f32(198);vulkan_ui_rect(r,shell_x,body_top,shell_w,action_bottom-body_top,{12,14,17,226});vulkan_ui_outline(r,shell_x,body_top,shell_w,action_bottom-body_top,{105,108,112,178},1)
	if entity.kind!="person"&&!g.check_from_dialogue {vulkan_ui_rect(r,625,646,555,48,{12,14,17,226});vulkan_ui_outline(r,625,646,555,48,{105,108,112,178},1)}
	if !standard_conversation {vk_text(r,660,45,entity.name,{255,218,112,255},1.25);_=vk_text_wrapped(r,660,75,360,public_source_description(g,entity.source_id),{205,207,210,255},.68,2)}
	// Rolls belong to the spoken line. This compact state keeps the character,
	// prior exchanges, odds, and consequence in one uninterrupted ledger.
	if payload!=nil&&g.check_from_dialogue&&g.pending_clue>=0&&g.pending_clue<len(payload.clues) {
		clue:=&payload.clues[g.pending_clue];check_heading:=entity.kind=="person"?"PRESS THE CONVERSATION":"INVESTIGATIVE CHECK";vk_text(r,660,218,check_heading,{255,211,92,255},.8);_=vk_text_wrapped(r,660,246,445,dialogue_check_prompt(g),{248,247,242,255},.9,2)
		if !g.check_done {cancel_box:=dialogue_check_cancel_rect();vk_dialogue_footer_button(r,cancel_box,dialogue_check_cancel_label(g),{148,155,168,255});vk_prompt_icon(r,g,.Back,cancel_box.x+cancel_box.w-27,cancel_box.y+5,20);helper,helper_line,color:=skill_helper(clue.skill);modifier:=check_modifier(skill_index(clue.skill),clue_evidence_bonus(g,g.pending_clue),clue_disposition(g,g.pending_clue),clue_situational_bonus(g,g.pending_clue));cost:=clue_action_cost(g,g.pending_clue);chance:=check_success_percent(g.check_preview,modifier);vk_text(r,660,326,strings.to_upper(clue.skill),color,1.18);_=vk_text_wrapped(r,660,352,445,helper_line,color,.68,2);vulkan_ui_rect(r,660,407,445,1,{139,107,55,170});vk_draw_die_face(r,660,420,31,0);vk_draw_die_face(r,699,420,31,0);vk_text(r,744,430,fmt.tprintf("MOD %+d  ·  NEED %d+ TOTAL  ·  %d%% SUCCESS",modifier,g.check_preview,chance),{255,211,92,255},.64);vk_text(r,660,470,helper,{205,207,210,255},.62);vk_text(r,660,492,clue.check_kind=="red"?"ONE-SHOT CHECK  ·  ONE ATTEMPT":"RETRYABLE CHECK  ·  PAY PER ATTEMPT",clue.check_kind=="red"?[4]u8{255,144,119,255}:[4]u8{155,201,255,255},.64);vk_text(r,660,520,dialogue_check_cost_summary(g,g.pending_clue),cost>0?[4]u8{255,211,92,255}:[4]u8{102,205,143,255},.62);vk_button(r,{650,590,490,42},dialogue_check_commit_label(g,cost),true)} else {helper,helper_line,color:=skill_helper(clue.skill);modifier:=check_modifier(skill_index(clue.skill),clue_evidence_bonus(g,g.pending_clue),clue_disposition(g,g.pending_clue),clue_situational_bonus(g,g.pending_clue));vk_text(r,660,326,strings.to_upper(clue.skill),color,1.18);_=vk_text_wrapped(r,660,352,445,helper_line,color,.68,2);vulkan_ui_rect(r,660,407,445,1,{139,107,55,170});vk_draw_die_face(r,660,420,31,g.check_result.die_a);vk_draw_die_face(r,699,420,31,g.check_result.die_b);vk_text(r,744,430,fmt.tprintf("%+d   ·   TARGET %d",modifier,g.check_preview),{255,211,92,255},.82);vk_text(r,660,470,helper,{205,207,210,255},.62);elapsed:=max(0,g.animation_time-g.check_roll_started);settled:=elapsed>=CHECK_REVEAL_DURATION;if !settled {vulkan_ui_rect(r,0,0,1200,720,{4,6,8,158});_=vk_draw_check_roll(r,g,300,220,600)} else {vulkan_ui_rect(r,650,407,490,150,{12,14,17,255});vulkan_ui_outline(r,650,407,490,150,{139,107,55,170},1);status:=g.check_result.success?"THE CHECK SUCCEEDS.":"THE CHECK FAILS.";status_color:=g.check_result.success?[4]u8{102,205,143,255}:[4]u8{255,144,119,255};vk_text(r,670,425,status,status_color,1.05);vk_text(r,670,459,dialogue_check_roll_summary(g.check_result),{255,211,92,255},.62);vulkan_ui_rect(r,670,480,450,1,{106,113,126,170});_=vk_text_wrapped(r,670,493,450,g.check_result.success?mystery_clue_proposition_text(g.story_project,clue):dialogue_check_failure_text(g,clue.check_kind),{248,247,242,255},.72,2);disposition_result:=dialogue_check_disposition_result(g);if entity.kind=="person"&&disposition_result!="" do vk_text(r,670,537,disposition_result,status_color,.56);continue_label:=entity.kind=="person"?"CONTINUE CONVERSATION":"RETURN TO INVESTIGATION";vk_button(r,{650,590,490,42},fmt.tprintf("[%s]  %s",dialogue_accept_prompt(g),continue_label),true)}}
		return
	}
	if entity.source_id=="body" {
		vulkan_ui_rect(r,660,350,445,1,{139,107,55,150});vk_text(r,660,360,"EDGAR'S BODY",{255,211,92,255},.60)
		watch:=dialogue_body_watch_clue(g);if watch>=0&&!mystery_game_clue_discovered(g,watch)&&clue_available(g,watch) {watch_box:=dialogue_body_watch_rect(g);vk_dialogue_choice_surface(r,watch_box,dialogue_control_focused(g,watch_box));vk_text(r,watch_box.x+18,watch_box.y+18,"1.  Examine the crushed wristwatch",{248,247,242,255},.76)} else if watch>=0&&mystery_game_clue_discovered(g,watch) {vk_text(r,660,522,"WRISTWATCH EXAMINED  ·  8:24",{102,205,143,255},.62)}
		leave_box:=dialogue_object_leave_rect();vk_dialogue_footer_button(r,leave_box,"Return to investigation",{148,155,168,255});vk_prompt_icon(r,g,.Back,leave_box.x+leave_box.w-27,leave_box.y+4,20);return
	}
	if entity.kind=="person" {
		if officer_source(entity.source_id) {
			vulkan_ui_rect(r,660,198,465,1,{139,107,55,190});vk_text(r,660,218,g.end_confirm?"END THE INVESTIGATION?":"OFFICER REPORT",g.end_confirm?[4]u8{255,144,119,255}:[4]u8{119,190,213,255},.72);_=vk_text_wrapped(r,660,250,445,g.end_confirm?investigation_unresolved_summary(g):(g.dialogue_response!=""?g.dialogue_response:officer_opening_line(entity.source_id)),{248,247,242,255},.78,5)
			vulkan_ui_rect(r,660,449,445,1,{139,107,55,150});vk_text(r,660,457,g.end_confirm?"THIS WILL LOCK THE SCENE":"WHAT DO YOU SAY?",{205,207,210,255},.60)
			if g.end_confirm {vk_dialogue_footer_button(r,officer_confirmation_rect(false),"Keep investigating",{148,155,168,255});vk_dialogue_footer_button(r,officer_confirmation_rect(true),"Gather everyone",{255,144,119,255})} else {first:=officer_choice_rect(0);vk_dialogue_choice_surface(r,first,dialogue_control_focused(g,first));vk_text(r,first.x+18,first.y+11,entity.source_id=="officer_lead"?"1.  What remains unresolved?":"1.  Anything to report?",{248,247,242,255},.78);if entity.source_id=="officer_lead" {second:=officer_choice_rect(1);vk_dialogue_choice_surface(r,second,dialogue_control_focused(g,second));vk_text(r,second.x+18,second.y+11,"2.  I'm ready to reconstruct what happened.",{248,247,242,255},.78)};end_box:=dialogue_end_rect_for(g);vk_dialogue_end_choice(r,end_box);vk_prompt_icon(r,g,.Back,end_box.x+end_box.w-27,end_box.y+4,20)}
			return
		}
		vulkan_ui_rect(r,660,198,465,1,{139,107,55,190})
		completed_count:=0;for i in 0..<mystery_dialogue_approach_count(payload) {node:=mystery_dialogue_approach_at(payload,i);if node.character_id==entity.source_id&&mystery_game_dialogue_completed(g,i) do completed_count+=1}
		case_note:=dialogue_case_note_active(g,clue_index)
		if !case_note&&vk_draw_character_transcript(r,g,entity.source_id) {
			// The persistent log owns player-facing history. Mystery dialogue
			// summaries remain state metadata and never substitute for played beats.
		} else if completed_count==0 {
			if case_note {vk_text(r,660,218,"CASE NOTE",{119,190,213,255},.72);_=vk_text_wrapped(r,660,240,445,g.dialogue_response,{248,247,242,255},.78)} else if g.dialogue_response!="" {fresh:=g.animation_time-g.dialogue_text_started>=0&&g.animation_time-g.dialogue_text_started<1.25;vk_text(r,660,216,fresh?"OPENING STATEMENT  ·  JUST NOW":"OPENING STATEMENT",fresh?[4]u8{119,190,213,255}:[4]u8{205,207,210,255},.52);vulkan_ui_rect(r,650,238,3,82,{119,190,213,fresh?u8(230):u8(110)});vk_text(r,660,240,strings.to_upper(entity.name),{255,218,112,255},.70);_=vk_text_wrapped(r,674,260,431,g.dialogue_response,{248,247,242,255},.78)} else {vk_text(r,660,218,"THE CONVERSATION BEGINS",{205,207,210,255},.72);_=vk_text_wrapped(r,660,240,445,known_claim_text(g,entity.source_id),{248,247,242,255},.78)}
		} else {
			max_scroll:=case_note?completed_count:max(0,completed_count-1);if max_scroll>0 {rail_hover:=g.active_device==.Keyboard_Mouse&&contains(dialogue_ledger_scroll_hit_rect(),g.input.mouse_pos);heading:=case_note&&g.dialogue_ledger_scroll==0?"CASE NOTE":g.dialogue_ledger_scroll==0?"CONVERSATION  ·  NEWEST":"CONVERSATION  ·  EARLIER";heading_color:=case_note&&g.dialogue_ledger_scroll==0?[4]u8{119,190,213,255}:[4]u8{205,207,210,255};vk_text(r,660,48,heading,heading_color,.52);position:=dialogue_history_position_label(g.dialogue_ledger_scroll,max_scroll);vk_text(r,1098-f32(utf8_glyph_count(position))*6,48,position,{170,176,184,255},.52);thumb_y:=dialogue_ledger_thumb_y(g.dialogue_ledger_scroll,max_scroll);vulkan_ui_rect(r,rail_hover?f32(1149):f32(1151),DIALOGUE_LEDGER_RAIL_Y,rail_hover?f32(5):f32(1),DIALOGUE_LEDGER_RAIL_H,rail_hover?[4]u8{148,155,168,210}:[4]u8{116,91,48,180});vulkan_ui_rect(r,rail_hover?f32(1146):f32(1148),thumb_y,rail_hover?f32(11):f32(7),DIALOGUE_LEDGER_THUMB_H,{255,211,92,rail_hover?u8(255):u8(220)})}
			if case_note&&g.dialogue_ledger_scroll==0 {vulkan_ui_rect(r,650,238,3,86,{119,190,213,230});vk_text(r,660,240,"EVIDENCE PRESENTED",{119,190,213,255},.66);_=vk_text_wrapped(r,660,268,445,g.dialogue_response,{248,247,242,255},.78,5)} else {
			completed_indices:[32]int;count:=0;for i in 0..<mystery_dialogue_approach_count(payload) {node:=mystery_dialogue_approach_at(payload,i);if node.character_id==entity.source_id&&mystery_game_dialogue_completed(g,i)&&count<len(completed_indices) {completed_indices[count]=i;count+=1}}
			if max_scroll==0 {fresh:=dialogue_exchange_fresh_visible(g,count-1,count,clue_index);vk_text(r,660,48,fresh?"CONVERSATION  ·  JUST NOW":"CONVERSATION  ·  NEWEST",fresh?[4]u8{119,190,213,255}:[4]u8{205,207,210,255},.52)}
			ledger_scroll:=case_note?g.dialogue_ledger_scroll-1:g.dialogue_ledger_scroll;y:f32=70;end:=clamp(count-ledger_scroll,1,count);start:=end-1;used:=dialogue_legacy_entry_layout_height(g,completed_indices[start]);for start>0&&end-start<3 {candidate:=dialogue_legacy_entry_layout_height(g,completed_indices[start-1]);if used+candidate>379 do break;start-=1;used+=candidate};for end<count&&end-start<3 {candidate:=dialogue_legacy_entry_layout_height(g,completed_indices[end]);if used+candidate>379 do break;used+=candidate;end+=1}
			for position in start..<end {i:=completed_indices[position];node:=mystery_dialogue_approach_at(payload,i);if node==nil do continue;failed:=mystery_game_dialogue_failed(g,i);if dialogue_exchange_fresh_visible(g,position,count,clue_index) {freshness:=clamp(1-(g.animation_time-g.dialogue_text_started)/1.25,0,1);bar_h:=min(dialogue_legacy_entry_layout_height(g,i)-8,449-y);vulkan_ui_rect(r,650,y,3,bar_h,{119,190,213,u8(70+int(freshness*170))})};y=vk_dialogue_ledger_line(r,660,y,445,"DETECTIVE  ·  SPOKEN",node.prompt,{119,190,213,255});if node.clue_id!="" {check_index:=mystery_clue_index(payload,node.clue_id);if check_index>=0 {clue:=&payload.clues[check_index];state:=failed?"FAILED":"SUCCESS";check_color:=failed?[4]u8{255,144,119,255}:[4]u8{102,205,143,255};cost:=clue_action_cost(g,check_index);y=vk_dialogue_ledger_line(r,660,y,445,fmt.tprintf("%s  ·  SKILL CHECK  ·  %s",strings.to_upper(clue.skill),state),fmt.tprintf("%s · %s",strings.to_lower(check_retry_label(clue.check_kind)),strings.to_lower(dialogue_tick_cost_label(cost))),check_color)}}}
			}
		}
		has_approach:=dialogue_has_available_approach(g,entity.source_id);evidence_available:=dialogue_can_present_evidence(g,clue_index);evidence_just_presented:=g.dialogue_node==3&&clue_index>=0&&mystery_game_evidence_presented(g,clue_index);failed_check:=dialogue_failed_check_active(g,clue_index);retry_available:=failed_check&&clue_index>=0&&clue_index<len(payload.clues)&&payload.clues[clue_index].check_kind!="red"&&clue_available(g,clue_index);section_label:=evidence_just_presented?"EVIDENCE PRESENTED  ·  +1 RELATED CHECKS":retry_available?"CHECK FAILED  ·  RETRY AVAILABLE":failed_check&&has_approach?"CHECK CLOSED  ·  OTHER APPROACHES AVAILABLE":has_approach?"YOUR RESPONSE":evidence_available?"EVIDENCE AVAILABLE":failed_check?"CHECK CLOSED  ·  TRY ANOTHER APPROACH":"CONVERSATION COMPLETE";section_color:=evidence_just_presented||failed_check?[4]u8{119,190,213,255}:has_approach?[4]u8{205,207,210,255}:evidence_available?[4]u8{119,190,213,255}:[4]u8{102,205,143,255};choices_y:=dialogue_choices_start_y(g,entity.source_id);vk_text(r,660,choices_y-19,section_label,section_color,.60)
		tooltip:=-1;tooltip_box:=Rect{};visible:=dialogue_response_visible_count(g,entity.source_id,clue_index);view_bottom:=dialogue_response_view_bottom(g,entity.source_id,clue_index);vulkan_ui_scissor(r,650,choices_y,490,max(0,view_bottom-choices_y));for slot in 0..<visible {choice:=dialogue_response_rect(g,entity.source_id,clue_index,slot);if choice.y>=view_bottom do break;index:=dialogue_response_approach(g,entity.source_id,clue_index,slot);focused:=dialogue_control_focused(g,choice);if index>=0 {check:=dialogue_check_clue_index(g,index)>=0;vk_dialogue_approach_choice(r,g,choice,index,slot,focused);if check&&focused {tooltip=index;tooltip_box=choice}} else if dialogue_response_is_evidence(g,entity.source_id,clue_index,slot) do vk_dialogue_evidence_choice(r,g,choice,clue_index,slot,focused)};vulkan_ui_scissor_reset(r);response_total:=dialogue_response_count(g,entity.source_id,clue_index);content_height:=dialogue_response_content_height(g,entity.source_id,clue_index);if choices_y+content_height>DIALOGUE_RESPONSE_VIEW_BOTTOM {track_h:=view_bottom-choices_y;thumb_h:=max(f32(24),track_h/f32(response_total));thumb_y:=choices_y+(track_h-thumb_h)*f32(g.dialogue_choice_page)/f32(max(1,response_total-1));vulkan_ui_rect(r,1136,choices_y,2,track_h,{78,82,90,150});vulkan_ui_rect(r,1134,thumb_y,6,thumb_h,{255,211,92,220})}
		if !has_approach {
			if failed_check&&!evidence_available {
				vulkan_ui_rect(r,660,493,445,78,{35,28,25,210});vulkan_ui_outline(r,660,493,445,78,{208,126,91,190},1);vk_text(r,676,505,"ANOTHER APPROACH NEEDED",{255,144,119,255},.58);vk_text(r,676,529,"This line of questioning is closed.",{248,247,242,255},.72);vk_text(r,676,551,"QUESTION ANOTHER ACCOUNT OR EXAMINE A RELATED OBJECT",{205,176,168,255},.52)
			} else if !evidence_available do _=vk_text_wrapped(r,674,500,415,"Every available line of inquiry with this person has been exhausted.",{170,176,184,255},.70,2)
		}
		end_box:=dialogue_end_rect_for(g);vk_dialogue_end_choice(r,end_box);vk_prompt_icon(r,g,.Back,end_box.x+end_box.w-27,end_box.y+4,20)
		if tooltip>=0 do vk_draw_check_tooltip(r,g,tooltip,tooltip_box)
	} else {if entity.source_id=="shutter_crank" {vulkan_ui_rect(r,660,214,445,1,{139,107,55,150});vk_text(r,660,224,g.shutter_sightline_failed?"SIGHTLINE TEST COMPLETE":"PHYSICAL SIGHTLINE TEST",g.shutter_sightline_failed?[4]u8{102,205,143,255}:[4]u8{205,207,210,255},.68);_=vk_text_wrapped(r,660,254,445,g.dialogue_response!=""?g.dialogue_response:"Operate the interior crank and test what remains visible from the dining room when the study shutter closes.",{248,247,242,255},.76,5);choice:=Rect{650,420,490,58};vk_dialogue_choice_surface(r,choice,dialogue_control_focused(g,choice));label:=g.shutter_demonstrating?"WAIT FOR SHUTTER":!g.shutter_sightline_failed?"1.  Test the dining-room sightline":g.shutter_target>=.5?"1.  Crank shutter closed":"1.  Crank shutter open";vk_text(r,choice.x+18,choice.y+18,label,{248,247,242,255},.76);leave_box:=dialogue_object_leave_rect();vk_dialogue_footer_button(r,leave_box,"Return to investigation",{148,155,168,255});vk_prompt_icon(r,g,.Back,leave_box.x+leave_box.w-27,leave_box.y+4,20)} else if entity.source_id=="pond_reflection" {vulkan_ui_rect(r,660,214,445,1,{139,107,55,150});vk_text(r,660,224,"A QUIET MOMENT",{119,190,213,255},.68);_=vk_text_wrapped(r,660,254,445,g.dialogue_response!=""?g.dialogue_response:"Rain dimples the pond. Your reflection appears only in the intervals between drops.",{248,247,242,255},.76,5);choice:=reflective_interaction_rect();vk_dialogue_choice_surface(r,choice,dialogue_control_focused(g,choice));vk_text(r,choice.x+18,choice.y+18,"1.  Contemplate your reflection",{248,247,242,255},.76);leave_box:=dialogue_object_leave_rect();vk_dialogue_footer_button(r,leave_box,"Return to investigation",{148,155,168,255});vk_prompt_icon(r,g,.Back,leave_box.x+leave_box.w-27,leave_box.y+4,20)} else if payload!=nil&&clue_index>=0 {section_label:=mystery_game_clue_discovered(g,clue_index)?"EXAMINATION RESULT":clue_available(g,clue_index)?"AVAILABLE APPROACH":"APPROACH UNAVAILABLE";vulkan_ui_rect(r,660,390,445,1,{139,107,55,150});vk_text(r,660,398,section_label,{205,207,210,255},.60);choice:=clue_available(g,clue_index)?dialogue_object_check_rect(g,clue_index):Rect{650,420,490,58};if mystery_game_clue_discovered(g,clue_index) {result_box:=choice;result_box.h=dialogue_object_result_height(g,clue_index);vk_dialogue_status_surface(r,result_box,{102,205,143,210});vk_text(r,result_box.x+18,result_box.y+9,"EVIDENCE ACQUIRED",{102,205,143,255},.78);_=vk_text_wrapped(r,result_box.x+18,result_box.y+31,result_box.w-36,g.dialogue_response!=""?g.dialogue_response:mystery_clue_proposition_text(g.story_project,&payload.clues[clue_index]),{248,247,242,255},.64);vk_text(r,result_box.x+18,result_box.y+result_box.h-17,"RECORDED IN NOTEBOOK  ·  AVAILABLE FOR THEORY",{157,210,176,255},.52);if entity.source_id=="dining_room" {walk:=dining_walkthrough_rect();vk_dialogue_choice_surface(r,walk,dialogue_control_focused(g,walk));vk_text(r,walk.x+18,walk.y+15,"1.  Talk through the place settings",{248,247,242,255},.74)}} else if clue_available(g,clue_index) {focused:=dialogue_control_focused(g,choice);vk_dialogue_object_check_choice(r,g,choice,clue_index,focused);if focused do vk_draw_check_tooltip_clue(r,g,clue_index,choice)} else {red:=payload.clues[clue_index].check_kind=="red";locked:=clue_locked_label(g,clue_index);vk_dialogue_status_surface(r,choice,red?[4]u8{150,91,78,210}:[4]u8{98,105,118,210});vk_text(r,choice.x+18,choice.y+8,red?"ONE-SHOT CHECK EXPIRED":"APPROACH UNAVAILABLE",red?[4]u8{255,144,119,255}:[4]u8{170,176,184,255},.68);_=vk_text_wrapped(r,choice.x+18,choice.y+32,choice.w-36,locked,{205,207,210,255},.58,2)}};leave_box:=dialogue_object_leave_rect();vk_dialogue_footer_button(r,leave_box,"Return to investigation",{148,155,168,255});vk_prompt_icon(r,g,.Back,leave_box.x+leave_box.w-27,leave_box.y+4,20)}
}

// Give the throw a readable dramatic shape: anticipation, tumble, result, release.
CHECK_LAUNCH_HOLD :: f32(.28)
CHECK_ROLL_DURATION :: f32(1.75)
CHECK_REVEAL_DURATION :: f32(2.65)
check_roll_ease :: proc(elapsed:f32)->f32 {
	// Hold for the initial toss, then let the dice lose energy continuously.
	t:=clamp((elapsed-CHECK_LAUNCH_HOLD)/(CHECK_ROLL_DURATION-CHECK_LAUNCH_HOLD),0,1)
	// The integrated trapezoid gives the tumble a fast middle and gentle settle.
	accel_time:f32=.30;cruise_end:f32=.70;max_speed:=1/(cruise_end-accel_time+accel_time)
	if t<accel_time do return .5*max_speed*t*t/accel_time
	accel_distance:=.5*max_speed*accel_time
	if t<cruise_end do return accel_distance+max_speed*(t-accel_time)
	brake_time:=1-cruise_end;brake_elapsed:=t-cruise_end
	return accel_distance+max_speed*(cruise_end-accel_time)+max_speed*brake_elapsed-.5*max_speed*brake_elapsed*brake_elapsed/brake_time
}

check_roll_animating :: proc(g:^Game)->bool {
	return g!=nil&&g.check_done&&g.animation_time-g.check_roll_started>=0&&g.animation_time-g.check_roll_started<CHECK_REVEAL_DURATION
}

update_check_result_cue :: proc(g:^Game) {
	// Fire on the reveal, then leave the result on screen long enough to land.
	if g==nil||!g.check_done||g.check_result_cue_played||g.animation_time-g.check_roll_started<CHECK_ROLL_DURATION do return
	play_sound(g,g.check_result.success?.Fact:.Reject);g.check_result_cue_played=true
}

vk_draw_die_pip :: proc(r:^Vulkan_Backend,x,y,size:f32){vulkan_ui_rect(r,x-size*.5,y-size*.5,size,size,{30,32,33,255})}
vk_draw_die_face :: proc(r:^Vulkan_Backend,x,y,size:f32,value:int,tint:[4]u8={238,232,216,255}) {
	shadow:f32=5;vulkan_ui_rect(r,x+shadow,y+shadow,size,size,{0,0,0,105});vulkan_ui_rect(r,x,y,size,size,tint);vulkan_ui_outline(r,x,y,size,size,{24,27,29,230},2)
	if value<=0 {vk_text(r,x+size*.34,y+size*.18,"?",{34,37,39,220},size/32);return}
	pip:=max(f32(3),size*.12);left,center,right:=x+size*.24,x+size*.5,x+size*.76;top,middle,bottom:=y+size*.24,y+size*.5,y+size*.76
	if value==1||value==3||value==5 do vk_draw_die_pip(r,center,middle,pip)
	if value>=2 {vk_draw_die_pip(r,left,top,pip);vk_draw_die_pip(r,right,bottom,pip)}
	if value>=4 {vk_draw_die_pip(r,right,top,pip);vk_draw_die_pip(r,left,bottom,pip)}
	if value==6 {vk_draw_die_pip(r,left,middle,pip);vk_draw_die_pip(r,right,middle,pip)}
}

vk_draw_check_roll :: proc(r:^Vulkan_Backend,g:^Game,x:f32=230,y:f32=300,w:f32=740)->bool {
	elapsed:=max(0,g.animation_time-g.check_roll_started);ease:=check_roll_ease(elapsed)
	// Resolution is one physical 2d6 throw; both faces settle to the values used
	// by the rules, and the modifier is applied only after they stop.
	shown_a:=elapsed>=CHECK_ROLL_DURATION?g.check_result.die_a:1+(int(elapsed*23)%6);shown_b:=elapsed>=CHECK_ROLL_DURATION?g.check_result.die_b:1+(int(elapsed*29+3)%6)
	cx:=x+w*.5;die_y:=y+8
	die_values:=[2]int{shown_a,shown_b}
	for value,index in die_values {
		size:f32=66;jitter_x:=f32(math.sin(f64(elapsed*31+f32(index)*2.4)))*(1-ease)*18;lift:=f32(math.sin(f64(elapsed*17+f32(index)*2)))*(1-ease)*28;dx:=cx-76+f32(index)*86+jitter_x
		vk_draw_die_face(r,dx,die_y+lift,size,value,index==0?[4]u8{226,218,196,255}:[4]u8{244,238,218,255})
	}
	if elapsed>=CHECK_ROLL_DURATION {status:=g.check_result.success?"CHECK SUCCESS":"CHECK FAILURE";color:=g.check_result.success?[4]u8{102,205,143,255}:[4]u8{255,112,91,255};vulkan_ui_rect(r,x+60,y+94,w-120,92,{10,12,14,255});vulkan_ui_outline(r,x+60,y+94,w-120,92,{139,107,55,190},1);label_w:=f32(utf8_glyph_count(status))*f32(COURIER_CELL_WIDTH)*1.08;vk_text(r,cx-label_w*.5,y+105,status,color,1.08);roll:=fmt.tprintf("%d + %d  %+d  =  %d     TARGET  %d",g.check_result.die_a,g.check_result.die_b,g.check_result.modifier,g.check_result.total,g.check_result.target);roll_w:=f32(utf8_glyph_count(roll))*f32(COURIER_CELL_WIDTH)*.64;vk_text(r,cx-roll_w*.5,y+151,roll,{205,207,210,255},.64)}
	return elapsed>=CHECK_REVEAL_DURATION
}

vk_draw_check :: proc(r:^Vulkan_Backend,g:^Game) {
	if !g.check_done do vk_heading(r,"DETECTIVE CHECK","")
	payload:=mystery_game_payload(g);if g.check_done {vk_panel(r,120,70,960,550)} else {vk_panel(r,250,130,700,450)};if payload==nil||g.pending_clue<0||g.pending_clue>=len(payload.clues) do return;clue:=&payload.clues[g.pending_clue]
	if g.check_done {
		_,helper_line,helper_color:=skill_helper(clue.skill);vk_text(r,190,116,strings.to_upper(clue.skill),helper_color,1.65);_=vk_text_wrapped(r,190,151,820,helper_line,helper_color,.72,2)
		elapsed:=clamp(g.animation_time-g.check_roll_started,0,CHECK_REVEAL_DURATION);fade_in:=clamp(elapsed/.18,0,1);fade_out:=clamp((CHECK_REVEAL_DURATION-elapsed)/.20,0,1);fade:=min(fade_in,fade_out);if fade>0 do vk_ui_spotlight(r,nil,u8(178*fade),0)
		settled:=vk_draw_check_roll(r,g);if !settled do return
		status:=g.check_result.success?"SUCCESS — FACT ESTABLISHED":clue.check_kind=="red"?"FAILED — APPROACH CLOSED":"FAILED — RETRY AVAILABLE"
		status_w:=f32(utf8_glyph_count(status))*f32(COURIER_CELL_WIDTH)*1.05;vk_text(r,600-status_w*.5,430,status,g.check_result.success?[4]u8{102,205,143,255}:[4]u8{208,126,91,255},1.05);if g.check_result.success {_=vk_text_wrapped(r,300,466,600,mystery_clue_proposition_text(g.story_project,clue),{205,232,213,255},.64,1)} else if clue.check_kind!="red" {_=vk_text_wrapped(r,300,466,600,"You may spend another tick to try again.",{205,207,210,255},.68,1)};vk_button(r,{430,500,340,50},g.check_from_dialogue?"RETURN TO CONVERSATION":"RETURN TO INVESTIGATION");return
	}
	helper,helper_line,helper_color:=skill_helper(clue.skill)
	vk_draw_helper_badge(r,285,165,clue.skill,helper_color)
	vk_text(r,430,175,strings.to_upper(clue.skill),helper_color,2);vk_text(r,430,215,helper,{205,207,210,255},.85);_=vk_text_wrapped(r,430,240,450,helper_line,helper_color,.8);vk_text(r,335,290,fmt.tprintf("[ROLL]  %s",strings.to_upper(clue.description)));modifier:=check_modifier(skill_index(clue.skill),clue_evidence_bonus(g,g.pending_clue),clue_disposition(g,g.pending_clue),clue_situational_bonus(g,g.pending_clue));vk_text(r,470,326,fmt.tprintf("2D6  %+d  /  NEED %d+",modifier,g.check_preview),{248,247,242,255},1.2)
	vk_text(r,390,400,"ROLL TWO SIX-SIDED DICE. ADD THE MODIFIER. MEET THE TARGET.",{205,207,210,255},.68)
	cost:=clue_action_cost(g,g.pending_clue);vk_button(r,{430,510,340,58},cost==0?"ROLL DICE  [OVERTIME — FREE]":fmt.tprintf("ROLL DICE  [-%d TICK%s]",cost,cost==1?"":"S"),true)
}

hypothesis_state_text :: proc(state:Hypothesis_State)->string {switch state {case .Locked:return "LOCKED";case .Unsubstantiated:return "OPEN / UNTESTED";case .Supported:return "EVIDENCE INCOMPLETE";case .Substantiated:return "ESTABLISHED";case .Eliminated:return "DISPROVED";case .Explained:return "EXPLAINED"};return "LOCKED"}
hypothesis_state_color :: proc(state:Hypothesis_State)->[4]u8 {switch state {case .Substantiated,.Explained:return {102,205,143,255};case .Eliminated:return {255,144,119,255};case .Supported:return {255,211,92,255};case .Unsubstantiated:return {205,207,210,255};case .Locked:return {90,89,84,255}};return {90,89,84,255}}
knowledge_type_color :: proc(kind:string)->[4]u8 {switch kind {case "OBSERVATION":return {255,211,92,255};case "TESTIMONY":return {206,154,255,255};case "STATEMENT":return {155,201,255,255};case "DEDUCTION":return {102,205,143,255}};return {205,207,210,255}}

vk_draw_workbench :: proc(r:^Vulkan_Backend,g:^Game) {
	vk_heading(r,"OPEN QUESTIONS","Turn observations and statements into facts you can apply.")
	vk_button(r,{40,70,210,38},"QUESTIONS",true);vk_button(r,{265,70,250,38},"EVENT CHAIN",true)
	vk_text(r,120,105,"CHOOSE ONE QUESTION TO CHALLENGE",{255,211,92,255},.78)
	visible:=0
	payload:=mystery_game_payload(g);for slot in 0..<3 {i:=visible_question_index(g,slot);if payload!=nil&&i>=0 {question:=payload.questions[i];state:=mystery_question_state(g,i);color:=hypothesis_state_color(state);y:=145+f32(slot)*135;vk_button(r,{120,y,960,112},"");vulkan_ui_outline(r,120,y,960,112,color,3);vk_text(r,150,y+17,fmt.tprintf("◇  %s",hypothesis_state_text(state)),color,.66);_=vk_text_wrapped(r,150,y+52,880,question.prompt,{248,247,242,255},1.0,2);visible+=1}}
	if visible==0 {vk_text(r,385,260,"NO OPEN QUESTIONS",{102,205,143,255},1.0);vk_text(r,385,315,"You may apply the facts you have or keep investigating.",{248,247,242,255},.82)}
	resolved:=resolved_question_count(g);vk_text(r,120,565,fmt.tprintf("◆  %d RESOLVED QUESTION%s",resolved,resolved==1?"":"S"),{102,205,143,255},.72);if visible==3 do vk_text(r,765,565,"MORE QUESTIONS APPEAR AS THESE RESOLVE",{205,207,210,255},.58)
	vk_button(r,{40,640,200,48},"BACK");vk_button(r,{400,610,400,58},"BUILD ACCUSATION",true)
}

event_chain_card_rect :: proc(index:int)->Rect {return {45+f32(index%3)*380,112+f32(index/3)*100,350,82}}
event_chain_field_rect :: proc(index:int)->Rect {return {45+f32(index)*280,470,255,58}}

vk_draw_event_chain :: proc(r:^Vulkan_Backend,g:^Game) {
	vk_heading(r,"EVENT CHAIN","Evidence proposes fragments. Resolve disagreements, then put the night in order.")
	vk_button(r,{40,70,210,38},"QUESTIONS",true);vk_button(r,{265,70,250,38},"EVENT CHAIN",true)
	if g.workbench_event_count==0 {vk_panel(r,190,185,820,245);vk_text(r,350,245,"NO EVENTS INFERRED YET",{205,207,210,255},1.05);_=vk_text_wrapped(r,300,300,600,"Interview the household and examine the scene. Events will form here when evidence suggests that something happened.",{248,247,242,255},.78,4);vk_button(r,{40,640,200,48},"BACK");return}
	for i in 0..<g.workbench_event_count {event:=g.workbench_events[i];box:=event_chain_card_rect(i);selected:=i==g.workbench_selected;disputed:=event_chain_disputed(g,i);complete:=workbench_event_complete(event);color:=disputed?[4]u8{255,144,119,255}:complete?[4]u8{102,205,143,255}:[4]u8{255,211,92,255};vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{37,42,49,255});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,selected?[4]u8{255,211,92,255}:color,selected?4:2);vk_text(r,box.x+14,box.y+11,fmt.tprintf("%d  ·  %02d:%02d",i+1,event.time/60,event.time%60),{255,211,92,255},.58);sentence:=fmt.tprintf("%s  %s  ·  %s",strings.to_upper(event.actor),workbench_action_label(event.action),workbench_noun_label(event.room));if len(sentence)>39 do sentence=sentence[:39];vk_text(r,box.x+14,box.y+38,sentence,{248,247,242,255},.62);vk_text(r,box.x+220,box.y+11,event_chain_fragment_label(g,i),color,.40)}
	event:=g.workbench_events[g.workbench_selected];vk_text(r,45,420,fmt.tprintf("EVENT %d  ·  COMPLETE THE PROPOSITION",g.workbench_selected+1),{255,211,92,255},.72)
	labels:=[4]string{"WHEN","WHO","DID WHAT","WHERE"};values:=[4]string{fmt.tprintf("%02d:%02d",event.time/60,event.time%60),strings.to_upper(event.actor),workbench_action_label(event.action),workbench_noun_label(event.room)}
	for value,i in values {box:=event_chain_field_rect(i);missing:=i==1&&event.actor=="someone"||i==3&&event.room=="unknown place";color:=missing?[4]u8{255,144,119,255}:[4]u8{155,201,255,255};vk_text(r,box.x,box.y-22,labels[i],color,.52);vk_button(r,box,fmt.tprintf("‹  %s  ›",value),g.workbench_field==i);if missing do vulkan_ui_outline(r,box.x,box.y,box.w,box.h,color,3)}
	if event_chain_disputed(g,g.workbench_selected) {vulkan_ui_rect(r,45,548,1110,42,{89,52,68,220});vk_text(r,65,561,"CONFLICT  ·  THIS VERSION CANNOT AGREE WITH ALL ATTACHED EVIDENCE",{255,144,119,255},.62)} else {vulkan_ui_rect(r,45,548,1110,42,{35,65,48,180});vk_text(r,65,561,workbench_source_text(g,g.workbench_selected),{102,205,143,255},.58)}
	vk_button(r,{45,600,190,44},"MOVE EARLIER",g.workbench_selected>0);vk_button(r,{250,600,190,44},"MOVE LATER",g.workbench_selected<g.workbench_event_count-1);vk_text(r,480,614,"Ordering and testing are free.",{205,207,210,255},.55);vk_button(r,{40,660,180,42},"BACK");vk_button(r,{900,610,255,52},workbench_first_incomplete(g)<0?"TEST CHAIN":"RESOLVE MISSING FIELDS",workbench_first_incomplete(g)<0)
}

vk_draw_event_chain_test :: proc(r:^Vulkan_Backend,g:^Game) {
	result:=g.workbench_result;failed:=result.first_failed_event
	vk_heading(r,"DOLLHOUSE TEST","The chain runs in order. The first impossible event stops the reconstruction.")
	for i in 0..<g.workbench_event_count {event:=g.workbench_events[i];x:=45+f32(i)*128;color:=i==failed?[4]u8{255,144,119,255}:failed<0||i<failed?[4]u8{102,205,143,255}:[4]u8{90,89,84,255};vulkan_ui_rect(r,x,105,116,66,{37,42,49,255});vulkan_ui_outline(r,x,105,116,66,color,i==failed?4:2);vk_text(r,x+10,117,fmt.tprintf("%02d:%02d",event.time/60,event.time%60),color,.52);vk_text(r,x+10,142,workbench_action_short(event.action),color,.52)}
	rooms:=[4]string{"DINING ROOM","HALL","STUDY","GARDEN"};room_tints:=[4][4]u8{{67,58,52,255},{55,58,63,255},{47,54,62,255},{48,63,53,255}}
	for room,i in rooms {x:=65+f32(i)*285;vulkan_ui_rect(r,x,230,250,220,room_tints[i]);vulkan_ui_outline(r,x,230,250,220,{139,107,55,255},3);vk_text(r,x+18,247,room,{255,211,92,255},.62)}
	active:=failed>=0?failed:max(0,g.workbench_event_count-1);if g.workbench_event_count>0 {event:=g.workbench_events[active];room_index:=0;for room,i in WORKBENCH_ROOMS do if room==event.room&&i>0 do room_index=i-1;x:=125+f32(room_index)*285;art:=mini_actor_art(event.actor);vk_art_fit(r,art,x,295,105,130);vk_text(r,x+105,330,workbench_action_label(event.action),failed>=0?[4]u8{255,144,119,255}:[4]u8{102,205,143,255},.62);if event.prop!="none" do vk_text(r,x+105,360,workbench_noun_label(event.prop),{255,211,92,255},.52)}
	color:=failed>=0?[4]u8{255,144,119,255}:[4]u8{102,205,143,255};vulkan_ui_rect(r,120,500,960,72,failed>=0?[4]u8{89,52,68,220}:[4]u8{35,65,48,200});vulkan_ui_outline(r,120,500,960,72,color,3);vk_text(r,155,515,failed>=0?"CHAIN BREAKS":"CHAIN HOLDS",color,.72);_=vk_text_wrapped(r,155,540,875,result.message,{248,247,242,255},.62,2);vk_button(r,{440,630,320,54},failed>=0?"RETURN TO CONFLICT":"RETURN TO EVENT CHAIN",true)
}

vk_draw_challenge :: proc(r:^Vulkan_Backend,g:^Game) {
	payload:=mystery_game_payload(g);if payload==nil||g.question_selected<0||g.question_selected>=len(payload.questions) {vk_heading(r,"CHALLENGE","No question selected.");vk_button(r,{40,640,220,48},"BACK");return}
	question:=payload.questions[g.question_selected];demo_index:=demonstration_for_question(g,g.question_selected);if demo_index<0 do return;demo:=payload.demonstrations[demo_index]
	vk_heading(r,"CHALLENGE THE HYPOTHESIS","Combine discovered evidence to test the claim. Demonstrations cost no ticks.")
	vk_text(r,70,105,fmt.tprintf("◇  %s",hypothesis_state_text(mystery_question_state(g,g.question_selected))),hypothesis_state_color(mystery_question_state(g,g.question_selected)),.7);_=vk_text_wrapped(r,70,135,1060,mystery_question_hypothesis_text(g,&question),{248,247,242,255},1.05,2)
	for slot in 0..<demo.slot_count {label:=demo.slot_labels[slot];x:=70+f32(slot)*365;selected:=slot==g.question_slot;piece:=mystery_question_slot(g,g.question_selected,slot);kind:=strings.to_upper(demo.slot_types[slot]);type_color:=knowledge_type_color(kind);glow:=type_color;glow[3]=110;vulkan_ui_rect(r,x,205,330,104,{37,42,49,255});if selected do vulkan_ui_outline(r,x-5,200,340,114,glow,6);vulkan_ui_outline(r,x,205,330,104,type_color,selected?4:2);vk_text(r,x+16,220,fmt.tprintf("%s%s",selected?"▶  ":"◇  ",label),type_color,.62);if piece=="" {vk_text(r,x+16,267,fmt.tprintf("CHOOSE %s",kind),{205,207,210,255},.67)}else{vk_text(r,x+16,257,fmt.tprintf("◆  %s",knowledge_piece_kind(g,piece)),type_color,.58);vk_text(r,x+16,282,"EVIDENCE PLACED",{102,205,143,255},.7)}}
	filter_kind:=question_slot_piece_kind(g);filter_color:=knowledge_type_color(filter_kind);vk_text(r,70,340,fmt.tprintf("SHOWING: %s",filter_kind),filter_color,.72);piece_count:=question_slot_piece_count(g);start:=clamp(g.knowledge_cursor,0,max(0,piece_count-3));for shown in 0..<min(3,piece_count-start) {piece:=question_slot_piece_id(g,start+shown);x:=70+f32(shown)*365;kind:=knowledge_piece_kind(g,piece);kind_color:=knowledge_type_color(kind);vk_button(r,{x,380,330,150},"");vulkan_ui_outline(r,x,380,330,150,kind_color,2);vk_text(r,x+18,397,fmt.tprintf("◆  %s",kind),kind_color,.62);_=vk_text_wrapped(r,x+18,433,294,knowledge_piece_text(g,piece),{248,247,242,255},.7,3)}
	vk_button(r,{70,555,150,48},"← PREV",start>0);vk_button(r,{235,555,150,48},"NEXT →",start+3<piece_count);vk_text(r,430,570,fmt.tprintf("%d EVIDENCE ITEMS",piece_count),{205,207,210,255},.62);if g.question_feedback!="" do _=vk_text_wrapped(r,610,557,530,g.question_feedback,{255,211,92,255},.62,2);vk_button(r,{40,640,220,48},"BACK TO QUESTIONS");full:=question_slots_full(g,g.question_selected);vk_button(r,{845,625,300,58},full?"DEMONSTRATE":"FILL EVERY SLOT",full)
}

interaction_action_label :: proc(demo:^Mystery_Demonstration,step:int)->string {
	gesture:=demo.gesture;if step>=0&&step<demo.gesture_step_count&&demo.gesture_steps[step]!="" do gesture=demo.gesture_steps[step]
	switch gesture {case "rotate":return "ROTATE TO THE FOCUS POINT";case "reveal":return "REVEAL THE RECORDED PROPERTY";case "unfold":return "UNFOLD THE EVIDENCE";case "operate":return "OPERATE THE MECHANISM";case "join":return "BRING THE EDGES TOGETHER";case "overlay":return "ALIGN THE OVERLAY";case "contrast":return "COMPARE THE DISAGREEMENT";case "align":return "ALIGN THE EVIDENCE";case "order":return "TEST THIS ORDER";case "resolve_conflict":return "RUN THE DISPUTED ACCOUNT"}
	return "TEST THE RELATIONSHIP"
}

vk_draw_investigation_interaction :: proc(r:^Vulkan_Backend,g:^Game,demo:^Mystery_Demonstration) {
	title:=strings.to_upper(demo.presentation);vk_heading(r,fmt.tprintf("%s EVIDENCE",title),"One deliberate gesture tests the relationship. Back preserves the selected evidence.")
	vk_panel(r,90,105,1020,465);vk_text(r,145,132,strings.to_upper(demo.prompt),{255,211,92,255},.82);step_total:=max(1,demo.gesture_step_count);vk_text(r,880,132,fmt.tprintf("STEP %d / %d",min(g.interaction_step+1,step_total),step_total),{205,207,210,255},.62)
	placed:=mystery_question_slots(g,g.question_selected);if demo.presentation=="inspect" {vulkan_ui_rect(r,400,205,400,245,{37,42,49,255});vulkan_ui_outline(r,400,205,400,245,{255,211,92,255},3);vk_text(r,425,228,"FOCUSED EVIDENCE",{205,207,210,255},.58);_=vk_text_wrapped(r,425,280,350,knowledge_piece_text(g,demo.subject),{248,247,242,255},.76,5)} else {for slot in 0..<demo.slot_count {x:=150+f32(slot)*340;vulkan_ui_rect(r,x,225,290,205,{37,42,49,255});vulkan_ui_outline(r,x,225,290,205,slot==0?[4]u8{255,211,92,255}:[4]u8{155,201,255,255},3);vk_text(r,x+18,245,strings.to_upper(demo.slot_labels[slot]),{205,207,210,255},.58);_=vk_text_wrapped(r,x+18,290,254,knowledge_piece_text(g,placed[slot]),{248,247,242,255},.72,4)}}
	if demo.presentation=="connect" {progress:=g.interaction_active?f32(g.interaction_step+1)/f32(step_total):f32(1);left:f32=440;right:f32=760;gap:=(right-left)*(1-progress);vulkan_ui_rect(r,520-gap*.5,455,80+gap,4,{102,205,143,255});vk_text(r,535,475,strings.to_upper(demo.gesture),{102,205,143,255},.75)} else if demo.presentation=="inspect" {vulkan_ui_outline(r,460,200,280,260,{102,205,143,180},5);vk_text(r,505,465,"FOCUS ASSIST · SNAP ENABLED",{102,205,143,255},.62)} else {vk_text(r,430,465,"FIRST CONFLICT STOPS THE RECONSTRUCTION",{255,144,119,255},.62)}
	if g.interaction_mismatch {vulkan_ui_rect(r,130,505,940,58,{89,52,68,220});_=vk_text_wrapped(r,155,520,890,g.question_feedback,{255,184,162,255},.65,2);vk_button(r,{440,630,320,54},"CHANGE THE EVIDENCE",true)} else {vk_button(r,{440,630,320,54},interaction_action_label(demo,g.interaction_step),true)}
}

vk_draw_workbench_recreate :: proc(r:^Vulkan_Backend,g:^Game) {
	payload:=mystery_game_payload(g);if payload==nil||g.active_demonstration<0||g.active_demonstration>=len(payload.demonstrations) {vk_heading(r,"DEMONSTRATION","No authored demonstration is active.");vk_button(r,{440,630,320,54},"RETURN TO QUESTIONS");return}
	demo:=payload.demonstrations[g.active_demonstration];q:=question_index_by_id(g,demo.question_id);state:=q>=0?mystery_question_state(g,q):.Unsubstantiated;color:=hypothesis_state_color(state)
	if g.interaction_active||g.interaction_mismatch {vk_draw_investigation_interaction(r,g,&demo);return}
	vk_heading(r,fmt.tprintf("%s DEMONSTRATION",strings.to_upper(demo.mode)),"The chosen evidence is tested against the claim.");vk_panel(r,90,105,1020,465);vk_text(r,145,130,hypothesis_state_text(state),color,1.0);if q>=0 do _=vk_text_wrapped(r,145,170,900,mystery_question_hypothesis_text(g,&payload.questions[q]),{248,247,242,255},1.0,2)
	switch demo.mode {
	case "physical":
		if demo.question_id=="q_fragment_source" {vulkan_ui_rect(r,180,245,330,210,{47,54,62,255});vulkan_ui_outline(r,225,285,230,120,{173,127,63,255},3);vk_text(r,245,310,"MIRIAM—STUDY, 8:20—",{248,247,242,255},.62);vulkan_ui_rect(r,470,335,245,5,{255,211,92,255});vulkan_ui_rect(r,745,245,330,210,{55,48,43,255});vulkan_ui_outline(r,790,285,230,120,{134,101,72,255},3);vk_text(r,810,310,"—BRING THE ACCOUNTS",{248,247,242,255},.62);vk_text(r,225,470,"MEMO-PAD STUB",{255,211,92,255},.72);vk_text(r,785,470,"BURNED FRAGMENT",{102,205,143,255},.68)} else {vulkan_ui_rect(r,145,260,310,180,{47,54,62,255});vulkan_ui_rect(r,745,260,310,180,{48,63,53,255});vk_art_fit(r,.Evidence_Rug,210,300,150,100);vulkan_ui_rect(r,455,340,290,5,{255,144,119,255});for i in 0..<6 do vulkan_ui_rect(r,505+f32(i)*38,330+f32(i%2)*18,14,7,{102,205,143,255});vk_text(r,505,375,"BODY ROUTE",{102,205,143,255},.72)}
	case "timeline":
		if demo.question_id=="q_miriam_alibi" {vulkan_ui_rect(r,190,250,820,205,{67,58,52,255});vulkan_ui_outline(r,320,285,560,120,{139,107,55,255},3);vk_art_fit(r,.Mini_Miriam,245,300,90,110);vk_art_fit(r,.Mini_Daniel,865,300,90,110);vulkan_ui_rect(r,480,340,240,5,{255,144,119,255});vk_text(r,505,295,"8:24",{255,211,92,255},1.35);vk_text(r,430,430,"BOTH SETTINGS ABANDONED",{255,144,119,255},.75)} else if demo.question_id=="q_when_death" {vk_art_fit(r,.Evidence_Watch,210,270,190,190);vulkan_ui_rect(r,470,345,500,5,{125,132,143,255});vulkan_ui_rect(r,635,310,6,75,{255,144,119,255});vk_text(r,585,270,"8:24",{255,211,92,255},1.35);vk_text(r,855,300,"8:20",{205,207,210,255},1.0);vk_text(r,510,410,"8:20 MEMO PRECEDES THE FATAL STRIKE",{255,144,119,255},.7)} else {vulkan_ui_rect(r,145,260,260,180,{67,58,52,255});vulkan_ui_rect(r,795,260,260,180,{47,54,62,255});vulkan_ui_rect(r,490,250,220,200,{29,31,35,255});vk_text(r,205,320,"MIRIAM'S DENIAL",{255,144,119,255},.68);vk_text(r,515,320,"JOINED NOTE",{102,205,143,255},.72);vk_text(r,515,365,"STUDY · 8:20",{255,211,92,255},.82);vk_text(r,445,460,"DENIAL DISPROVED",{255,144,119,255},.75)}
	case "comparison":
		if demo.question_id=="q_miriam_motive" {vk_art_fit(r,.Evidence_Ledger,210,245,190,210);vulkan_ui_rect(r,455,340,290,4,{255,211,92,255});vulkan_ui_rect(r,790,265,230,150,{218,205,174,255});vulkan_ui_outline(r,790,265,230,150,{105,82,57,255},3);vk_text(r,815,300,"MIRIAM—STUDY, 8:20—",{68,53,42,255},.55);vk_text(r,815,335,"TORN LOWER EDGE",{68,53,42,255},.48);vk_text(r,175,455,"UNRECEIPTED M.V. PAYMENTS",{255,211,92,255},.62);vk_text(r,790,455,"8:20 MEMO ENTRY",{102,205,143,255},.62)} else if demo.question_id=="q_miriam_study_meeting" {vulkan_ui_rect(r,145,260,270,170,{67,58,52,255});vulkan_ui_outline(r,145,260,270,170,{255,144,119,255},3);vk_text(r,185,295,"MIRIAM'S DENIAL",{255,144,119,255},.7);_=vk_text_wrapped(r,175,335,210,"Edgar did not summon me.",{248,247,242,255},.62,2);vulkan_ui_rect(r,480,270,240,150,{218,205,174,255});vulkan_ui_outline(r,480,270,240,150,{105,82,57,255},3);vk_text(r,500,300,"MIRIAM—STUDY, 8:20—",{68,53,42,255},.52);vk_text(r,520,345,"TORN EDGE",{105,82,57,255},.55);vulkan_ui_rect(r,785,270,270,150,{187,171,142,255});vulkan_ui_outline(r,785,270,270,150,{105,82,57,255},3);vk_text(r,805,300,"—BRING THE ACCOUNT BOOKS",{68,53,42,255},.48);vk_text(r,825,345,"MATCHING EDGE",{102,105,73,255},.55);vk_text(r,485,455,"JOINED SUMMONS DISPROVES THE DENIAL",{102,205,143,255},.62)} else {vk_art_fit(r,.Evidence_Cane,250,245,110,210);vk_art_fit(r,.Evidence_Statuette,770,245,190,210);vulkan_ui_rect(r,450,340,300,4,{255,211,92,255});vk_text(r,485,305,"WOUND PROFILE",{255,211,92,255},.7);vk_text(r,505,365,"MATCHES BRONZE BASE",{102,205,143,255},.7)}
	case "confrontation":
		vk_art_fit(r,demo.question_id=="q_daniel_lie"?.Mini_Daniel:.Mini_Elsie,210,240,170,215);vulkan_ui_rect(r,430,250,570,170,{37,42,49,255});vulkan_ui_outline(r,430,250,570,170,color,3);vk_text(r,460,275,"STATEMENT CHALLENGED",{155,201,255,255},.72);_=vk_text_wrapped(r,460,315,500,demo.result,{248,247,242,255},.72,3)
	}
	vulkan_ui_rect(r,130,490,940,58,{35,65,48,190});_=vk_text_wrapped(r,155,505,890,demo.result,color,.65,2);vk_button(r,{440,630,320,54},"RETURN TO QUESTIONS",true)
}

vk_recreate_figure :: proc(r:^Vulkan_Backend,x,y:f32,label:string,tint:[4]u8,solid:bool) {
	alpha:u8=solid?255:105;color:=tint;color[3]=alpha
	vulkan_ui_rect(r,x,y+21,28,55,color);skin:=[4]u8{226,183,150,alpha};vulkan_ui_rect(r,x+5,y,18,20,skin);vk_text(r,x-12,y+86,label,solid?[4]u8{255,218,112,255}:[4]u8{205,207,210,180},.65)
}

vk_draw_reveal_prep :: proc(r:^Vulkan_Backend,g:^Game) {
	vk_heading(r,"BUILD YOUR ACCUSATION","Choose a candidate, then apply one established fact to each proof pillar.")
	vk_text(r,80,105,"MURDER CANDIDATE",{255,211,92,255},.72);for i in 0..<3 do vk_button(r,{330+f32(i)*190,88,175,48},suspect_name(g,i),mystery_game_accusation(g)==suspect_id(g,i))
	labels:=[3]string{"MOTIVE","MEANS","OPPORTUNITY"};for label,pillar in labels {y:=180+f32(pillar)*125;vulkan_ui_rect(r,100,y,1000,100,{37,42,49,255});vulkan_ui_outline(r,100,y,1000,100,mystery_game_theory_pillar(g,pillar)!=""?[4]u8{102,205,143,255}:[4]u8{90,89,84,255},2);vk_text(r,125,y+18,label,{255,211,92,255},.72);id:=mystery_game_theory_pillar(g,pillar);if id!="" {vk_text(r,330,y+15,"◆ ESTABLISHED FACT",{102,205,143,255},.58);_=vk_text_wrapped(r,330,y+43,650,known_deduction_proposition(g,id),{248,247,242,255},.64,2)}else if mystery_game_accusation(g)=="" {vk_text(r,330,y+37,"Choose a candidate first.",{205,207,210,255},.66)}else if proof_pillar_piece_count(g,mystery_game_accusation(g),pillar)==0 {vk_text(r,330,y+37,"No established fact supports this pillar yet.",{255,144,119,255},.66)}else{vk_text(r,330,y+37,"Choose an unlocked fact.",{255,211,92,255},.66)};vk_button(r,{990,y+24,80,50},id==""?"ADD":"NEXT",mystery_game_accusation(g)!=""&&proof_pillar_piece_count(g,mystery_game_accusation(g),pillar)>0)}
	ready:=question_ready_to_present(g);action_label:=ready?"PRESENT SUPPORTED ACCUSATION":mystery_game_accusation(g)!=""?"ACCUSE ANYWAY":"END WITHOUT ACCUSATION";vk_button(r,{40,640,200,48},"EDIT BOARD");vk_button(r,{400,620,400,58},action_label,true);vk_button(r,{930,640,220,48},"NOTEBOOK")
}

finale_demo_label :: proc(step:int)->string {
	labels:=[3]string{"PLACE MIRIAM'S EXACT DENIAL","PRESENT THE JOINED APPOINTMENT","ANCHOR THE STRIKE AT 8:24"}
	return labels[clamp(step,0,2)]
}

finale_demo_message :: proc(g:^Game)->string {
	messages:=[3]string{
		"Miriam's recorded words remain exact: 'He did not.' The room has already heard the denial the player chose to preserve.",
		"The proof returns already earned: two rooms, two scraps, one joined summons at 8:20. Miriam reaches to square the paper, then leaves it crooked.",
		"Blood and bronze in Edgar's crushed watch place the fatal strike at 8:24—four minutes after the appointment Miriam denied.",
	}
	message:=messages[clamp(g.finale_demo_step,0,2)]
	if g.finale_demo_step>=2&&!knowledge_piece_known(g,"ded_miriam_denial_disproved") do return "The fragments point toward Miriam, but your account has not established both her denial and the matching note."
	return message
}

vk_draw_finale_demonstration :: proc(r:^Vulkan_Backend,g:^Game) {
	supported:=knowledge_piece_known(g,"ded_miriam_denial_disproved")
	vk_heading(r,"THE FINAL REVEAL","Act V of 5 — perform the decisive proof.")
	vk_panel(r,105,105,990,470);vk_text(r,150,135,"ACT V — THE TORN APPOINTMENT",{255,211,92,255},1.6)
	if g.finale_demo_step>=1 do vk_text(r,535,180,"8:20",{255,211,92,255},2)
	vulkan_ui_rect(r,155,235,260,205,{67,58,52,255});vulkan_ui_outline(r,155,235,260,205,{139,107,55,255},3);vk_text(r,170,255,"MIRIAM'S SITTING ROOM",{255,211,92,255},.8)
	vulkan_ui_rect(r,785,235,260,205,{47,54,62,255});vulkan_ui_outline(r,785,235,260,205,{139,107,55,255},3);vk_text(r,880,255,"STUDY",{255,211,92,255},.8)
	vk_art_fit(r,.Mini_Miriam,220,285,90,110)
	if g.finale_demo_step>=1 {
		vulkan_ui_rect(r,505,225,190,225,{29,31,35,255});vulkan_ui_outline(r,505,225,190,225,{173,127,63,255},4)
		for y in 0..<7 do vulkan_ui_rect(r,520,245+f32(y)*27,160,19,{68,71,77,255})
	}
	vulkan_ui_rect(r,275,327,225,4,{255,144,119,255});vulkan_ui_rect(r,500,314,9,30,{255,144,119,255});vk_text(r,350,350,"HE DID NOT",{255,144,119,255},.8)
	if g.finale_demo_step>=1 {vk_art_fit(r,.Evidence_Ledger,875,285,92,92);vk_text(r,840,410,supported?"TORN EDGES — MATCH":"NOTE NOT SUPPORTED",supported?[4]u8{102,205,143,255}:[4]u8{208,126,91,255},.7)}
	if g.finale_demo_step>=2 {vk_art_fit(r,.Evidence_Watch,675,275,85,105);vk_text(r,625,400,"WATCH STOPPED 8:24",{255,211,92,255},.7)}
	_=vk_text_wrapped(r,155,480,890,finale_demo_message(g),g.finale_demo_step>=2&&supported?[4]u8{102,205,143,255}:[4]u8{248,247,242,255},1)
	vk_button(r,{440,630,320,54},finale_demo_label(g.finale_demo_step),true)
}

vk_draw_reveal_act_stage :: proc(r:^Vulkan_Backend,g:^Game,act:int,supported:bool) {
	x,y:=f32(755),f32(255);vulkan_ui_rect(r,x,y,275,220,{35,39,45,255});vulkan_ui_outline(r,x,y,275,220,supported?[4]u8{102,205,143,255}:[4]u8{116,91,48,255},3);vk_text(r,x+18,y+15,"YOUR CLOCKWORK SCENE",{255,211,92,255},.72)
	for socket in 0..<board_socket_count(act) {placed:=g.board_sockets[act][socket];vk_text(r,x+20,y+43+f32(socket)*22,fmt.tprintf("%s %s",placed?"◆":"◇",board_socket_label(act,socket)),placed?[4]u8{102,205,143,255}:[4]u8{205,207,210,255},.58)}
	switch act {
	case 0:
		vulkan_ui_rect(r,x+35,y+125,62,43,{64,91,76,220});vk_text(r,x+44,y+139,"LEDGER",{248,247,242,255},.5);vk_recreate_figure(r,x+188,y+115,"MIRIAM",{122,67,91,255},supported)
	case 1:
		vk_recreate_figure(r,x+55,y+125,"MIRIAM",{122,67,91,255},supported);vk_recreate_figure(r,x+190,y+125,"EDGAR",{92,87,72,255},supported);vulkan_ui_rect(r,x+126,y+148,38,12,{151,109,57,255});vk_text(r,x+112,y+180,"8:24",{255,211,92,255},.65)
	case 2:
		vulkan_ui_rect(r,x+32,y+145,48,15,{151,109,57,255});vulkan_ui_rect(r,x+112,y+156,68,12,{92,87,72,200});vulkan_ui_rect(r,x+220,y+135,10,48,{92,87,72,200});vk_text(r,x+25,y+185,"CLEAN  →  MOVE  →  STAGE",supported?[4]u8{102,205,143,255}:[4]u8{205,207,210,255},.55)
	case 3:
		vulkan_ui_rect(r,x+35,y+125,205,70,{102,70,47,255});vk_recreate_figure(r,x+70,y+112,"DANIEL",{58,88,121,255},supported);vk_recreate_figure(r,x+175,y+112,"ELSIE",{92,87,72,255},supported);vulkan_ui_rect(r,x+100,y+184,75,5,{118,35,42,220})
	}
}

vk_draw_reveal :: proc(r:^Vulkan_Backend,g:^Game) {
	if g.reveal_act==4 {vk_draw_finale_demonstration(r,g);return}
	subtitles:=[4]string{
		"Act I of 5 — establish the pressure behind the murder.",
		"Act II of 5 — reconstruct where, when, and how Edgar died.",
		"Act III of 5 — turn the garden accident back into a deliberate scene.",
		"Act IV of 5 — separate the lies that concealed other crimes.",
	}
	subtitle:=subtitles[clamp(g.reveal_act,0,3)]
	vk_heading(r,"THE FINAL REVEAL",subtitle)
	acts:=[5]string{"MOTIVE","THE MURDER","THE FALSE SCENE","THE OTHER LIES",""}
	first,second:=reveal_act_lines(g,g.reveal_act);third:=reveal_act_third_line(g,g.reveal_act);supported:=reveal_act_supported(g,g.reveal_act);presented:=mystery_game_reveal_presented(g,g.reveal_act)
	vk_panel(r,120,120,960,430);vk_text(r,170,155,acts[g.reveal_act],{255,211,92,255},2)
	status:=supported?(presented?"EVIDENCE PRESENTED":"CHALLENGED / EVIDENCE READY"):"WEAK OR MISSING"
	vk_text(r,170,220,status,supported?(presented?[4]u8{102,205,143,255}:[4]u8{255,211,92,255}):[4]u8{208,126,91,255});vk_text(r,170,270,"DETECTIVE:",{255,211,92,255})
	body_scale:=g.reveal_act==3?f32(.72):f32(1);line_y:=vk_text_wrapped(r,170,305,535,first,{248,247,242,255},body_scale,3)
	if second!="" do line_y=vk_text_wrapped(r,170,line_y,535,second,{248,247,242,255},body_scale,3)
	if third!="" do line_y=vk_text_wrapped(r,170,line_y,535,third,{248,247,242,255},body_scale,3)
	response_label_y:=g.reveal_act==3?max(line_y+5,f32(430)):max(line_y+8,f32(410));vk_text(r,170,response_label_y,"RESPONSE:",{255,211,92,255})
	response:=reveal_act_response(g,g.reveal_act,supported,presented)
	_=vk_text_wrapped(r,170,response_label_y+28,535,response,{248,247,242,255},g.reveal_act==3?f32(.72):f32(1),3)
	vk_draw_reveal_act_stage(r,g,g.reveal_act,supported);button_label:=supported&&!presented?"PRESENT ESTABLISHED EVIDENCE":"CONTINUE REVEAL";vk_button(r,{440,630,320,54},button_label,true)
}

vk_draw_result :: proc(r:^Vulkan_Backend,g:^Game) {
	if ending:=active_case_ending(g);ending!=nil {
		core_ending:=mystery_core_ending(g.story_project,ending);title,summary:="CASE END", "";if core_ending!=nil {title=core_ending.title;summary=core_ending.summary}
		accent:=[4]u8{205,207,210,255};switch ending.tone {case "success":accent={102,205,143,255};case "warning":accent={255,211,92,255};case "failure":accent={255,144,119,255};case:}
		vk_heading(r,"CASE END",ending.subtitle);vk_panel(r,120,105,960,470);vk_text(r,170,135,title,accent,1.35);_=vk_text_wrapped(r,170,180,860,summary,{248,247,242,255},.88,3)
		vulkan_ui_rect(r,170,260,860,1,{139,107,55,170});if ending.epilogue!=""&&!g.show_canonical {vk_text(r,170,285,"WHAT FOLLOWS",{255,211,92,255},.72);_=vk_text_wrapped(r,170,320,860,ending.epilogue,{205,207,210,255},.76,5)}
		if g.show_canonical&&ending.canonical_timeline!="" {vulkan_ui_rect(r,155,270,890,260,{24,28,34,254});vulkan_ui_outline(r,155,270,890,260,{139,107,55,210},1);vk_text(r,185,295,"POST-CASE CANONICAL ACCOUNT",{255,211,92,255},.82);_=vk_text_wrapped(r,185,340,830,ending.canonical_timeline,{248,247,242,255},.8,7)}
		primary:=ending.primary_action=="reveal"&&g.show_canonical?"TIMELINE REVEALED":ending.primary_label;vk_button(r,{300,630,280,54},primary,ending.primary_action!="reveal"||!g.show_canonical);if ending.secondary_label!="" do vk_button(r,{620,630,280,54},ending.secondary_label)
		return
	}
	vk_heading(r,"CASE OUTCOME",fmt.tprintf("Accused: %s",mystery_game_accusation(g)==""?"none":character_display_name(g,mystery_game_accusation(g))));labels:=[5]string{"AIRTIGHT SOLUTION","CORRECT, BUT UNPROVEN","PLAUSIBLE, BUT INCOMPLETE","WRONG ACCUSATION","CASE UNRESOLVED"};summaries:=[5]string{"The joined note defeats Miriam's denial. Daniel's affair and Elsie's theft explain their lies without sharing her guilt.","Your account points to Miriam, but a material gap remains in the proof, a competing lie, or the physical sequence.","You name Miriam, but too much of the night remains unproved for the accusation to hold.","The night you describe cannot be reconciled with the person you accuse.","You bring no complete accusation to the table."};vk_panel(r,120,105,960,470);vk_text(r,170,130,labels[int(g.result)],g.result==.Airtight?[4]u8{102,205,143,255}:[4]u8{208,126,91,255},1.35);_=vk_text_wrapped(r,170,170,860,summaries[int(g.result)])
	section_labels:=[5]string{"WHO","WHAT HAPPENED","WHERE / WHEN","CONCEALMENT","CONTRADICTION"};categories:=[5]string{"who","what","where_when","concealment","contradiction"};vk_text(r,170,235,"YOUR DEMONSTRATED FRAMEWORK",{255,211,92,255},.9);for label,i in section_labels {count:=final_category_count(g,categories[i]);color:=count>0?[4]u8{102,205,143,255}:[4]u8{208,126,91,255};vk_text(r,185,270+f32(i)*34,label,{248,247,242,255},.72);vk_text(r,405,270+f32(i)*34,count>0?fmt.tprintf("%d ESTABLISHED",count):"MISSING",color,.62)}
	excluded,total:=exclusion_progress(g);vk_text(r,185,450,fmt.tprintf("INNOCENT SUSPECTS EXCLUDED  %d / %d",excluded,total),excluded==total?[4]u8{102,205,143,255}:[4]u8{255,211,92,255},.72);chronology_ok:=mystery_timeline_order_possible(g,g.timeline_order);vk_text(r,185,482,chronology_ok?"CHRONOLOGY  POSSIBLE":"CHRONOLOGY  CONTRADICTED",chronology_ok?[4]u8{102,205,143,255}:[4]u8{208,126,91,255},.72)
	if g.show_canonical {vk_text(r,605,235,"POST-CASE CANONICAL TIMELINE",{255,211,92,255},.9);_=vk_text_wrapped(r,605,275,420,"Edgar summoned Miriam to the study at 8:20. She killed him at 8:24, cleaned the statuette at 8:25, moved his body at 8:27, and staged the garden fall at 8:29. In her sitting room she tried to burn her half of the summons at 8:30, hid the surviving fragment at 8:31, and returned to dinner at 8:33. Daniel saw her return. The joined fragments expose her denial.",{248,247,242,255},.82)} else {diagnosis:=g.mystery_state!=nil?mystery_diagnose_player(g.story_project,g.mystery_state):Mystery_Diagnosis{};vk_text(r,605,235,"WHY THIS RESULT",{255,211,92,255},.9);lines:=[3]string{diagnosis.complete?"The accusation names a supported suspect.":"The accusation remains incomplete.",diagnosis.evidence_supported?"The required evidence routes are supported.":fmt.tprintf("%d required support route%s remain open.",diagnosis.missing_requirement_count,diagnosis.missing_requirement_count==1?"":"s"),diagnosis.exclusive?"The established account excludes competing suspects.":"Competing explanations have not all been excluded."};for line,i in lines do _=vk_text_wrapped(r,620,275+f32(i)*50,390,fmt.tprintf("• %s",line),{205,207,210,255},.68)}
	vk_button(r,{300,630,280,54},g.show_canonical?"TIMELINE REVEALED":"REVEAL CANONICAL TIMELINE");vk_button(r,{620,630,280,54},"RESTART CASE")
}

vk_draw_game_over :: proc(r:^Vulkan_Backend,g:^Game) {
	vk_art_cover(r,.Title,0,0,WINDOW_WIDTH,WINDOW_HEIGHT);vulkan_ui_rect(r,0,0,WINDOW_WIDTH,WINDOW_HEIGHT,{5,8,14,190});vk_panel(r,250,105,700,510)
	vk_text(r,460,145,"OUT OF TIME",{255,144,119,255},2.2);vulkan_ui_rect(r,350,200,500,2,{116,91,48,220})
	vk_text(r,420,235,"THE INVESTIGATION CLOCK REACHED ZERO",{255,211,92,255},.72);reason:=g.game_over_reason;if reason=="" do reason="Time expired before a complete reconstruction was prepared.";_=vk_text_wrapped(r,330,275,540,reason,{248,247,242,255},.88,4)
	vk_text(r,382,350,"Choose how to continue.",{205,207,210,255},.78)
	vk_button(r,{410,410,380,52},"RELOAD CASE",true);vk_button(r,{410,478,380,52},"MAIN MENU");vk_button(r,{410,546,380,52},"QUIT")
}

block_route_stats :: proc(g:^Game,block:string)->(routes,guaranteed,min_cost:int) {
	min_cost=999;payload:=mystery_game_payload(g);if payload==nil do return
	for &clue in payload.clues {found:=false;for i in 0..<clue.block_count do if clue.blocks[i]==block do found=true;if found {routes+=1;if clue.essential do guaranteed+=1;min_cost=min(min_cost,clue.cost)}}
	if min_cost==999 do min_cost=0
	return
}

vk_draw_diagnostics :: proc(r:^Vulkan_Backend,g:^Game) {
	vk_heading(r,"DEVELOPMENT DIAGNOSTICS","F12 only | canonical state and route safety; never shown to players")
	vk_text(r,30,95,"CANONICAL  20:15 close → 20:24 murder → 20:25 clean → 20:27 move → 20:29 stage → 20:30 burn → 20:31 hide → 20:33 return",{255,211,92,255},.9)
	vk_text(r,30,125,fmt.tprintf("STATE  %d clues | %d actions left | phase %v",count_discovered(g),g.ap,g.phase),{248,247,242,255},.9)
	vk_text(r,30,165,"REQUIRED ROUTE REPORT",{255,211,92,255},1.1)
	payload:=mystery_game_payload(g);if payload==nil do return;solution:=&payload.solution;labels:=[7]string{"Weapon","Murder place","Death time","Body movement","Staging","Cleaning","False alibi"};blocks:=[7]string{solution.weapon_block,solution.murder_place_block,solution.death_time_block,solution.body_movement_block,solution.staging_block,solution.cleaning_block,solution.alibi_block}
	for label,i in labels {routes,guaranteed,cost:=block_route_stats(g,blocks[i]);color:=guaranteed>0?[4]u8{102,205,143,255}:[4]u8{255,144,119,255};vk_text(r,55,205+f32(i)*34,label);vk_text(r,300,205+f32(i)*34,fmt.tprintf("%d route%s | %d guaranteed | cheapest %d",routes,routes==1?"":"s",guaranteed,cost),color,.9)}
	essential_cost:=0;for clue in payload.clues do if clue.essential do essential_cost+=clue.cost
	vk_text(r,700,205,"SAFETY GATES",{255,211,92,255},1.1);vk_text(r,720,245,fmt.tprintf("Protected white-check route: %d / %d actions",essential_cost,payload.action_budget),essential_cost<=payload.action_budget?[4]u8{102,205,143,255}:[4]u8{255,144,119,255},.9)
	vk_text(r,720,280,"Essential failures: explicit free fallback",{102,205,143,255},.9);vk_text(r,720,315,"Repeated discoveries: no time cost",{102,205,143,255},.9);vk_text(r,720,350,"Innocent complete solutions: rejected",{102,205,143,255},.9)
	vk_text(r,700,395,"DESTROYED EVIDENCE",{255,211,92,255},1.1);_=vk_text_wrapped(r,720,430,440,"Daniel protects the affair. Elsie protects an earlier theft. Miriam denies Edgar's summons, but the fragment from the metal wastebin in her sitting room joins his 8:20 memo stub.",{205,207,210,255},.9)
	vk_text(r,30,475,"FIRST-PLAYTHROUGH PACE",{255,211,92,255},.82);pace_labels:=[6]string{"ARRIVE","3 ACCOUNTS","FALSE SCENE","OTHER LIES","TORN NOTE","OUTCOME"};for label,i in pace_labels {recorded:=(g.case_pacing_mask&(u8(1)<<u8(i)))!=0;value:=recorded?pacing_time_label(g.case_pacing_times[i]):"--:--";vk_text(r,55+f32(i%2)*260,505+f32(i/2)*28,fmt.tprintf("%s  %s",value,label),recorded?[4]u8{102,205,143,255}:[4]u8{150,153,158,255},.58)};vk_button(r,{550,505,300,42},"COPY PLAYTEST REPORT")
	vk_button(r,{20,650,180,42},"CLOSE DIAGNOSTICS")
}

question_resolved :: proc(g:^Game,index:int)->bool {
	return question_is_resolved(g,index)
}

ATTRIBUTE_NAMES := [4]string{"OBSERVATION","ANALYSIS","EMPATHY","PRESSURE"}
ATTRIBUTE_SKILLS := [4]string{"Observation","Analysis","Empathy","Pressure"}
ATTRIBUTE_DOMAINS := [4]string{"SENSE THE SCENE","CONNECT THE FACTS","READ THE PERSON","CONTROL THE ROOM"}
ATTRIBUTE_DESCRIPTIONS := [4]string{
	"Notices small physical details: disturbed objects, hidden traces, and the one thing in a room that does not belong.",
	"Tests whether facts agree. Reconstructs sequence, motive, timing, and the contradictions between separate accounts.",
	"Listens beneath an answer for fear, loyalty, shame, or grief. Finds what a person is protecting without forcing them.",
	"Applies nerve and authority when silence must break. Pushes guarded people and commits to confrontational approaches.",
}

vk_draw_attribute_portrait :: proc(r:^Vulkan_Backend,index:int,x,y,size:f32,color:[4]u8) {
	texture:=vulkan_ui_art_texture(r,.Attribute_Portraits)
	if texture<0 {vk_draw_helper_badge(r,x,y,ATTRIBUTE_SKILLS[clamp(index,0,3)],color);return}
	column,row:=index%2,index/2;cell_min:=Vec2{.014+f32(column)*.5,.014+f32(row)*.5};cell_max:=Vec2{.486+f32(column)*.5,.486+f32(row)*.5}
	vulkan_ui_quad(r,x,y,size,size,{255,255,255,255},texture,cell_min,cell_max,true);vulkan_ui_outline(r,x,y,size,size,color,3)
}

vk_menu_overlay_back_button :: proc(r:^Vulkan_Backend,g:^Game,return_screen:Screen) {
	box:=menu_overlay_back_rect();vk_button(r,box,menu_overlay_back_label(return_screen));vk_prompt_icon(r,g,.Back,box.x+box.w-27,box.y+5,20);context_label:=menu_overlay_context_label(return_screen);if context_label!="" do vk_text(r,850,660,context_label,{170,176,184,255},.56)
}

vk_draw_attributes :: proc(r:^Vulkan_Backend,g:^Game) {
	vk_heading(r,"DETECTIVE ATTRIBUTES","Four voices shape every check — select one to hear what it does")
	for name,i in ATTRIBUTE_NAMES {
		skill:=ATTRIBUTE_SKILLS[i];x,y:=f32(42),145+f32(i)*117;_,voice,color:=skill_helper(skill);selected:=i==g.attribute_selected
		vk_button(r,{x,y,250,105},"",selected);vk_draw_attribute_portrait(r,i,x+10,y+1,105,color)
		vk_text(r,x+122,y+12,name,color,.58);vulkan_ui_rect(r,x+122,y+34,108,2,color);vk_text(r,x+122,y+43,fmt.tprintf("%+d",skill_index(skill)),color,1.75);vk_text(r,x+122,y+77,"CHECK MODIFIER",{205,207,210,255},.46)
		if selected {vk_panel(r,330,145,828,456);vulkan_ui_outline(r,330,145,828,456,color,3);vk_text(r,380,188,name,color,2.5);vk_text(r,382,240,ATTRIBUTE_DOMAINS[i],{255,211,92,255},.85);vk_draw_attribute_portrait(r,i,970,174,155,color);_=vk_text_wrapped(r,380,300,550,ATTRIBUTE_DESCRIPTIONS[i],{248,247,242,255},1.0,4);vulkan_ui_rect(r,380,430,690,1,{139,107,55,190});vk_text(r,380,458,"INNER VOICE",{205,207,210,255},.62);_=vk_text_wrapped(r,380,490,690,voice,color,.9,2);vk_text(r,380,558,fmt.tprintf("BASE CHECK MODIFIER  %+d",skill_index(skill)),color,.72)}
	}
	vk_menu_overlay_back_button(r,g,g.menu_detail_return)
}

vk_draw_notebook :: proc(r:^Vulkan_Backend,g:^Game) {
	vk_heading(r,"POCKET NOTEBOOK","Observations record what was found; objectives recall where the story left off.");tabs:=[6]string{"KNOWLEDGE","STATEMENTS","PEOPLE","QUESTIONS","OBJECTIVES","HISTORY"};vk_tab_bar(r,{20,91,1126,54});for label,i in tabs do vk_tab(r,{20+f32(i)*190,95,176,46},label,i==g.notebook_tab);vk_panel(r,20,158,1160,462);vulkan_ui_scissor(r,26,164,1148,450);y:f32=180-g.notebook_scroll;shown:=0
	payload:=mystery_game_payload(g)
	switch g.notebook_tab {
	case 0: if payload!=nil {for &clue in payload.clues do if knowledge_piece_known(g,clue.id) {vk_text(r,40,y,"OBSERVED",{255,211,92,255});y=max(vk_text_wrapped(r,160,y,980,mystery_clue_proposition_text(g.story_project,&clue)),y+38);shown+=1};for deduction in payload.deductions do if knowledge_piece_known(g,deduction.id) {vk_text(r,40,y,"DEDUCED",{102,205,143,255});y=max(vk_text_wrapped(r,160,y,980,mystery_story_proposition_text(g.story_project,deduction.proposition_id)),y+38);shown+=1}}
	case 1: if payload!=nil do for claim in payload.claims do if claim_known(g,claim.id) {vk_text(r,40,y,"SAID",{155,201,255,255});y=max(vk_text_wrapped(r,160,y,980,mystery_story_proposition_text(g.story_project,claim.proposition_id)),y+38);shown+=1}
	case 2: if g.story_project!=nil do for character in g.story_project.entities do if character.kind=="character"&&character.tag_count>0&&character.tags[0]=="suspect" {vk_text(r,40,y,character.display_name,{255,211,92,255});y=max(vk_text_wrapped(r,260,y,870,character.description),y+55);shown+=1}
	case 3: if payload!=nil do for question,i in payload.questions do if question_unlocked(g,i) {state:=mystery_question_state(g,i);resolved:=question_is_resolved(g,i);vk_text(r,40,y,hypothesis_state_text(state),hypothesis_state_color(state),.5);vk_text(r,210,y,question.prompt,resolved?[4]u8{205,207,210,255}:[4]u8{248,247,242,255},.7);y+=45;shown+=1}
	case 4:
		if g.story_project!=nil&&g.story_state!=nil {
			for objective in g.story_project.objectives {state_index:=story_state_objective_index(g.story_state,objective.id);if objective.hidden||state_index<0||g.story_state.objectives[state_index].status!=.Active do continue;vk_text(r,40,y,"ACTIVE",{255,211,92,255},.48);vk_text(r,160,y,objective.display_name,{248,247,242,255},.72);y=max(vk_text_wrapped(r,160,y+25,950,objective.description,{205,207,210,255},.58,3),y+68);shown+=1}
			last_sequence:u64=0;for state in g.story_state.objectives do if state.status==.Completed&&state.completed_sequence>last_sequence do last_sequence=state.completed_sequence
			for pass in 0..<len(g.story_state.objectives) {wanted:u64=0;wanted_index:=-1;for state,state_index in g.story_state.objectives {if state.status!=.Completed||state.completed_sequence==0||state.completed_sequence>last_sequence||state.completed_sequence<=wanted do continue;wanted=state.completed_sequence;wanted_index=state_index};if wanted_index<0 do break;state:=g.story_state.objectives[wanted_index];objective_index:=story_objective_index(g.story_project,state.objective_id);if objective_index>=0&&!g.story_project.objectives[objective_index].hidden {objective:=g.story_project.objectives[objective_index];vk_text(r,40,y,"COMPLETE",{117,229,169,255},.42);vk_text(r,160,y,objective.display_name,{205,207,210,255},.66);y+=42;shown+=1};last_sequence=wanted-1}
			for reverse in 0..<len(g.story_state.objectives) {state_index:=len(g.story_state.objectives)-1-reverse;state:=g.story_state.objectives[state_index];if state.status!=.Completed||state.completed_sequence!=0 do continue;objective_index:=story_objective_index(g.story_project,state.objective_id);if objective_index>=0&&!g.story_project.objectives[objective_index].hidden {vk_text(r,40,y,"COMPLETE",{117,229,169,255},.42);vk_text(r,160,y,g.story_project.objectives[objective_index].display_name,{205,207,210,255},.66);y+=42;shown+=1}}
		}
	case 5: for i in 0..<g.history_count {vk_text(r,40,y,fmt.tprintf("%02d",i+1),{205,207,210,255});y=max(vk_text_wrapped(r,90,y,1040,g.history[i]),y+38);shown+=1}
	}
	g.notebook_scroll_max=max(0,y+g.notebook_scroll-596);g.notebook_scroll_target=clamp(g.notebook_scroll_target,0,g.notebook_scroll_max);vulkan_ui_scissor_reset(r)
	if shown==0 do vk_text(r,430,350,"Nothing established in this category yet.",{205,207,210,255})
	if g.notebook_scroll_max>0 {rail_y:f32=174;rail_h:f32=426;thumb_h:=max(48,rail_h*rail_h/(rail_h+g.notebook_scroll_max));thumb_y:=rail_y+(rail_h-thumb_h)*g.notebook_scroll/g.notebook_scroll_max;vulkan_ui_rect(r,1160,rail_y,3,rail_h,{116,122,136,180});vulkan_ui_rect(r,1156,thumb_y,11,thumb_h,{255,211,92,230});vk_text(r,1075,630,"SCROLL  ↕",{205,207,210,255},.48)}
	vk_menu_overlay_back_button(r,g,g.notebook_return)
}

SCENE_TRANSITION_DURATION :: f32(.68)

scene_transition_is_story_screen :: proc(screen:Screen)->bool {
	#partial switch screen {
	case .Introduction,.Loading,.Exterior,.Investigate,.Dialogue,.Check,.Board,.Challenge,.Recreate,.Reveal_Prep,.Reveal,.Result,.Game_Over:return true
	}
	return false
}

map_loading_index :: proc(screen:Screen)->int {if screen==.Exterior do return 0;if screen==.Investigate do return 1;return -1}

map_loading_required :: proc(g:^Game,from,to:Screen)->bool {
	if from==.Loading do return false
	index:=map_loading_index(to)
	return index>=0&&!g.map_ready[index]&&(from!=.Dialogue&&from!=.Check)
}

map_loading_begin :: proc(g:^Game,target:Screen) {
	g.map_loading_active=true;g.map_loading_target=target;g.map_loading_progress=0
	g.map_loading_elapsed=0;g.map_loading_stage=0;g.screen=.Loading
}

map_loading_update :: proc(g:^Game,dt:f32) {
	if !g.map_loading_active do return
	g.map_loading_elapsed+=dt
	if g.case_loading_active {
		state:=sync.atomic_load_explicit(&case_load_work.state,.Acquire)
		g.map_loading_stage=clamp(int(state)-1,0,3)
		targets:=[5]f32{0,.12,.38,.78,1};target:=targets[clamp(int(state),0,4)]
		g.map_loading_progress+=(target-g.map_loading_progress)*min(1,dt*10)
		if state==6 {campaign_case_load_reap();g.case_loading_active=false;g.map_loading_active=false;g.screen=.Campaign_Cases;campaign_workspace.feedback=case_load_work.result.message;return}
		if state==5&&g.map_loading_progress>=.995&&g.map_loading_elapsed>=.25 {
			campaign_case_load_reap();loaded:=campaign_finish_prepared_case(g)
			if !loaded.ok {g.case_loading_active=false;g.map_loading_active=false;g.screen=.Campaign_Cases;campaign_workspace.feedback=loaded.message;return}
			destination:=g.screen;g.case_loading_active=false;g.map_loading_active=false;index:=map_loading_index(destination);if index>=0 do g.map_ready[index]=true;g.screen=destination
		}
		return
	}
	target_progress:=clamp(g.map_loading_elapsed/.52,0,1)
	g.map_loading_progress+=(target_progress-g.map_loading_progress)*min(1,dt*14)
	if target_progress<.28 do g.map_loading_stage=0
	else if target_progress<.62 do g.map_loading_stage=1
	else if target_progress<1 do g.map_loading_stage=2
	else {g.map_loading_stage=3;g.map_loading_progress=1;index:=map_loading_index(g.map_loading_target);if index>=0 do g.map_ready[index]=true;g.case_loading_active=false;g.map_loading_active=false;g.screen=g.map_loading_target}
}

vk_draw_map_loading :: proc(r:^Vulkan_Backend,g:^Game) {
	vulkan_ui_rect(r,0,0,WINDOW_WIDTH,WINDOW_HEIGHT,{3,5,9,255})
	vulkan_ui_rect(r,154,120,892,480,{13,17,25,255});vulkan_ui_outline(r,154,120,892,480,{72,78,89,220},1)
	vulkan_ui_rect(r,154,120,8,480,{255,211,92,255});vulkan_ui_rect(r,198,178,804,2,{116,91,48,220})
	vk_text(r,198,148,"STORYCORE  /  SCENE TRANSFER",{152,196,214,255},.58)
	destination:=g.case_loading_active?strings.to_upper(g.case_loading_title):g.map_loading_target==.Exterior?"VALE CITY":"CASE LOCATION"
	vk_text(r,198,225,g.case_loading_active?"LOADING CASE":"LOADING MAP",{248,247,242,255},2.15);vk_text(r,200,278,destination,{255,211,92,255},.82)
	stages:=[4]string{"READING LOCATION","PREPARING GEOMETRY","PLACING EVIDENCE","SCENE READY"};stage:=clamp(g.map_loading_stage,0,len(stages)-1);stage_label:=stage==0&&g.case_loading_active?"READING CASE FILE":stages[stage]
	vk_text(r,198,380,stage_label,stage==3?[4]u8{117,229,169,255}:[4]u8{205,207,210,255},.66)
	x,y,w,h:=f32(198),f32(425),f32(804),f32(22);progress:=clamp(g.map_loading_progress,0,1)
	vulkan_ui_rect(r,x,y,w,h,{24,29,38,255});vulkan_ui_outline(r,x,y,w,h,{90,89,84,255},1)
	if progress>0 do vulkan_ui_rect(r,x+3,y+3,(w-6)*progress,h-6,{255,211,92,255})
	vk_text(r,198,470,fmt.tprintf("%03d%%",int(progress*100+.5)),{248,247,242,255},.72);vk_text(r,842,532,"PLEASE STAND BY",{125,132,143,255},.52)
}

scene_transition_begin :: proc(g:^Game,from,to:Screen) {
	if from==to||g.editor_mode!=.None||(!scene_transition_is_story_screen(from)&&to!=.Loading)||!scene_transition_is_story_screen(to) do return
	// The theory board is a frequently opened utility screen, so present it
	// immediately in both directions instead of interrupting navigation.
	if from==.Board||to==.Board do return
	// Dialogue and checks retain the same physical scene; wiping those small UI
	// changes would make ordinary investigation feel sluggish.
	if (from==.Investigate||from==.Dialogue||from==.Check)&&(to==.Investigate||to==.Dialogue||to==.Check) do return
	target:=to
	if map_loading_required(g,from,to) {map_loading_begin(g,to);target=.Loading}
	g.scene_transition_style=Scene_Transition_Style(g.scene_transition_sequence%5)
	g.scene_transition_sequence+=1
	g.scene_transition_elapsed=0
	g.scene_transition_active=true
	g.scene_transition_target=target
	// A fade needs the outgoing image for its first half. The destination state
	// has already been prepared, so hold only its presentation until full black.
	if g.scene_transition_style==.Fade do g.screen=from
}

scene_transition_update :: proc(g:^Game,dt:f32) {
	if !g.scene_transition_active do return
	g.scene_transition_elapsed+=dt
	if g.scene_transition_style==.Fade&&g.screen!=g.scene_transition_target&&g.scene_transition_elapsed>=SCENE_TRANSITION_DURATION*.5 do g.screen=g.scene_transition_target
	if g.scene_transition_elapsed>=SCENE_TRANSITION_DURATION {g.scene_transition_elapsed=SCENE_TRANSITION_DURATION;g.scene_transition_active=false}
}

vk_draw_scene_transition :: proc(r:^Vulkan_Backend,g:^Game) {
	if !g.scene_transition_active do return
	t:=clamp(g.scene_transition_elapsed/SCENE_TRANSITION_DURATION,0,1);t=t*t*(3-2*t)
	ink:=[4]u8{3,5,9,255}
	switch g.scene_transition_style {
	case .Horizontal:
		x:=WINDOW_WIDTH*t;vulkan_ui_rect(r,x,0,WINDOW_WIDTH-x,WINDOW_HEIGHT,ink)
	case .Vertical:
		y:=WINDOW_HEIGHT*t;vulkan_ui_rect(r,0,y,WINDOW_WIDTH,WINDOW_HEIGHT-y,ink)
	case .Diagonal:
		strips:=24;strip_h:=f32(WINDOW_HEIGHT)/f32(strips);travel:=f32(WINDOW_WIDTH)+f32(WINDOW_HEIGHT)*.48
		for i in 0..<strips {y:=f32(i)*strip_h;edge:=clamp(t*travel-y*.48,0,WINDOW_WIDTH);vulkan_ui_rect(r,edge,y,WINDOW_WIDTH-edge,strip_h+1,ink)}
	case .Iris:
		// A banded ellipse gives the classic expanding aperture without a
		// one-off shader or extra render target.
		bands:=32;band_h:=WINDOW_HEIGHT/f32(bands);radius_x:=WINDOW_WIDTH*.72*t;radius_y:=WINDOW_HEIGHT*.72*t
		for i in 0..<bands {y:=f32(i)*band_h;dy:=math.abs((y+band_h*.5)-WINDOW_HEIGHT*.5);half:f32=0;if radius_y>0&&dy<radius_y do half=radius_x*f32(math.sqrt(f64(max(0,1-dy*dy/(radius_y*radius_y)))));left:=clamp(WINDOW_WIDTH*.5-half,0,WINDOW_WIDTH*.5);right:=clamp(WINDOW_WIDTH*.5+half,WINDOW_WIDTH*.5,WINDOW_WIDTH);vulkan_ui_rect(r,0,y,left,band_h+1,ink);vulkan_ui_rect(r,right,y,WINDOW_WIDTH-right,band_h+1,ink)}
	case .Fade:
		alpha:=u8(clamp(int((1-math.abs(t*2-1))*255),0,255));vulkan_ui_rect(r,0,0,WINDOW_WIDTH,WINDOW_HEIGHT,{ink[0],ink[1],ink[2],alpha})
	}
}

weather_hash :: proc(value:f32)->f32 {scrambled:=f32(math.sin(f64(value*12.9898+78.233)))*43758.547;return scrambled-f32(math.floor(f64(scrambled)))}

vk_draw_weather :: proc(r:^Vulkan_Backend,g:^Game) {
	strength:f32=0
	if g.screen==.Exterior do strength=1
	if g.screen==.Investigate do strength=clamp(g.environment_blend,0,1)
	if strength<=.01||g.editor_mode==.Build do return
	// Three depth layers move at different rates. Drops gather loosely into
	// passing curtains, while jittered angles and sparse gaps break any grid.
	for i in 0..<96 {
		index:=f32(i);depth:=f32(i%3)/2
		seed:=weather_hash(index+4.7);vertical_seed:=weather_hash(index*2.31+19.4)
		cluster:=f32(i%9);cluster_center:=weather_hash(cluster*5.17+11.8)*WINDOW_WIDTH
		scatter:=(weather_hash(index*7.13+2.4)-.5)*(150+depth*310)
		independent_x:=weather_hash(index*3.91+44.2)*WINDOW_WIDTH
		x:=cluster_center+scatter;x=x*.72+independent_x*.28
		speed:=210+depth*330+seed*145
		y:=f32(math.mod(f64(vertical_seed*(WINDOW_HEIGHT+140)+g.animation_time*speed),f64(WINDOW_HEIGHT+140)))-70
		gust:=f32(math.sin(f64(g.animation_time*.72+y*.004+cluster*1.7)))
		wind:=.10+depth*.10+gust*.045+(seed-.5)*.08
		x+=g.animation_time*(18+depth*25)+gust*24
		x=f32(math.mod(f64(x+WINDOW_WIDTH+100),f64(WINDOW_WIDTH+100)))-50
		length:=5+depth*14+seed*13
		thickness:=.7+depth*.75+seed*.35
		catch_light:=weather_hash(index*11.29+91.7)>.94?f32(25):f32(0)
		alpha:=u8(clamp(int((10+depth*24+seed*14+catch_light)*strength),0,255))
		vk_editor_line(r,{x,y},{x+length*wind,y+length},{174,211,224,alpha},thickness)
	}
}

// Production frame compositor. SDL remains the window/event provider only;
// every command below is recorded into the Vulkan command buffer.
draw_vulkan :: proc(r:^Vulkan_Backend,g:^Game) {
	draw_phase_started:=time.tick_now()
	r.profile_draw_setup_ms=0;r.profile_draw_refresh_ms=0;r.profile_draw_world_build_ms=0;r.profile_draw_weather_ms=0;r.profile_draw_overlay_ms=0
	if g.catalog_thumbnail_baking {
		state,_:=os.process_wait(g.catalog_thumbnail_process,0)
		if state.exited {
			g.catalog_thumbnail_baking=false
			if state.success&&state.exit_code==0 {count:=vulkan_catalog_refresh_thumbnails(r);g.catalog_thumbnail_status=fmt.tprintf("%d PREVIEW%s UPDATED",count,count==1?"":"S")} else {g.catalog_thumbnail_status="THUMBNAIL RENDER FAILED"}
		}
	}
	vk_focused_button=g.gui.focused
	vulkan_ui_begin(r)
	r.profile_draw_setup_ms=time.duration_seconds(time.tick_diff(draw_phase_started,time.tick_now()))*1000
	draw_phase_started=time.tick_now()
	if generated_roof_gpu_revision!=generated_roof_revision {for i in 0..<generated_roof_count do _=vk_world_refresh_mesh(&r.world,&r.ctx,&generated_roof_meshes[i]);generated_roof_gpu_revision=generated_roof_revision}
	if generated_link_gpu_revision!=generated_link_revision {for i in 0..<generated_link_count do _=vk_world_refresh_mesh(&r.world,&r.ctx,&generated_link_meshes[i]);generated_link_gpu_revision=generated_link_revision}
	if generated_ground_gpu_revision!=generated_ground_revision {for i in 0..<generated_terrain_count do if generated_terrain_dirty[i] {_=vk_world_refresh_mesh(&r.world,&r.ctx,&generated_terrain_meshes[i]);generated_terrain_dirty[i]=false};for i in 0..<generated_water_count do _=vk_world_refresh_mesh(&r.world,&r.ctx,&generated_water_meshes[i]);for i in 0..<generated_path_count do _=vk_world_refresh_mesh(&r.world,&r.ctx,&generated_path_meshes[i]);generated_ground_gpu_revision=generated_ground_revision}
	if generated_story_gpu_revision!=generated_story_revision {for i in 0..<generated_foundation_count do _=vk_world_refresh_mesh(&r.world,&r.ctx,&generated_foundation_meshes[i]);for i in 0..<generated_story_slab_count do _=vk_world_refresh_mesh(&r.world,&r.ctx,&generated_story_slab_meshes[i]);for i in 0..<generated_story_wall_count do _=vk_world_refresh_mesh(&r.world,&r.ctx,&generated_story_wall_meshes[i]);generated_story_gpu_revision=generated_story_revision}
	r.profile_draw_refresh_ms=time.duration_seconds(time.tick_diff(draw_phase_started,time.tick_now()))*1000
	draw_phase_started=time.tick_now()
	vk_world_begin(&r.world);if g.catalog_bake_index>=0 {vk_world_build_catalog_thumbnail(&r.world,&r.ctx,g)} else if g.character_studio {vk_world_build_character_studio(&r.world,&r.ctx,g)} else {presentation:=g.screen==.Pause?g.pause_return:g.screen;exterior_dialogue:=presentation==.Dialogue&&dialogue_returns_to_exterior(g);if presentation==.Exterior||exterior_dialogue do vk_world_build_city(&r.world,&r.ctx,g);if presentation==.Investigate||presentation==.Dialogue&&!exterior_dialogue&&!g.story_presentation.interaction_active do vk_world_build_house(&r.world,&r.ctx,g);if presentation==.Dialogue&&!exterior_dialogue&&g.story_presentation.interaction_active do vk_world_build_dialogue_interaction(&r.world,&r.ctx,g)}
	r.profile_draw_world_build_ms=time.duration_seconds(time.tick_diff(draw_phase_started,time.tick_now()))*1000
	if g.catalog_bake_index>=0 do return
	if g.character_studio do return
	draw_phase_started=time.tick_now()
	vk_draw_weather(r,g)
	r.profile_draw_weather_ms=time.duration_seconds(time.tick_diff(draw_phase_started,time.tick_now()))*1000
	draw_phase_started=time.tick_now()
	#partial switch g.screen {
	case .Theme_Knoll:
		vk_draw_theme_knoll(r,g)
	case .Theme_Knoll_Details:
		vk_draw_theme_knoll_details(r,g)
	case .Title:
		vk_art_cover(r,.Title,0,0,WINDOW_WIDTH,WINDOW_HEIGHT);vulkan_ui_rect(r,0,0,WINDOW_WIDTH,WINDOW_HEIGHT,{5,8,14,90});vulkan_ui_rect(r,132,48,936,624,{13,17,25,218});vulkan_ui_outline(r,132,48,936,624,{255,211,92,255},2);vulkan_ui_outline(r,138,54,924,612,{72,78,89,220},1)
		vulkan_ui_rect(r,156,96,888,5,{255,211,92,255});vk_text(r,291,132,"C H I C A G O   S T O R Y   S T U D I O",{255,211,92,255},1.65)
		vk_text(r,414,217,"YOUR STORIES",{248,247,242,255},2.55);vk_text(r,390,286,"ONE WORLD  •  MANY POSSIBILITIES",{205,207,210,255},.88)
		vk_button(r,{410,400,380,48},"STORY LIBRARY",true);vk_button(r,{410,456,380,48},"CONTINUE STORY");vk_button(r,{410,512,380,48},"OPTIONS");vk_button(r,{410,568,380,48},"QUIT")
		vk_text(r,410,632,"CORE READY  •  CONTENT COMBINES FREELY",{255,211,92,255},.62)
	case .Campaign:
		vk_art_cover(r,.Title,0,0,WINDOW_WIDTH,WINDOW_HEIGHT);vulkan_ui_rect(r,0,0,WINDOW_WIDTH,WINDOW_HEIGHT,{5,8,14,190});vk_panel(r,82,48,1036,624)
		vk_text(r,120,78,"STORY LIBRARY",{255,211,92,255},1.75);vk_text(r,122,116,"Standalone stories and collections share one library.",{205,207,210,255},.66)
		vulkan_ui_rect(r,120,143,116,24,{44,51,61,235});vulkan_ui_outline(r,120,143,116,24,{255,211,92,220},1);vk_text(r,135,150,"ALL STORIES",{255,211,92,255},.44);vk_text(r,256,150,"ITEM TYPES:  COLLECTION  •  STANDALONE",{152,196,214,255},.44)
		viewport:=campaign_browser_viewport();content_height:=campaign_browser_content_height();vulkan_ui_scissor(r,viewport.x,viewport.y,viewport.w,viewport.h);for i in 0..<campaign_browser.count {item:=campaign_browser.entries[i];box:=campaign_browser_card_rect(i);if box.y+box.h<viewport.y||box.y>viewport.y+viewport.h do continue;y:=box.y;selected:=i==campaign_browser.selected;focused:=vk_focused_button==campaign_browser_card_id(i);highlighted:=selected||focused;vulkan_ui_rect(r,box.x,box.y,box.w,box.h,highlighted?[4]u8{28,38,49,248}:[4]u8{17,23,31,235});_=vk_campaign_hero_cover(r,i,122,y+2,226,80,highlighted?[4]u8{255,255,255,255}:[4]u8{178,184,192,255});vulkan_ui_rect(r,348,y+2,714,80,highlighted?[4]u8{28,38,49,232}:[4]u8{17,23,31,220});if focused do vulkan_ui_rect(r,box.x,box.y,7,box.h,UI_ACCENT);vulkan_ui_outline(r,box.x,box.y,box.w,box.h,focused?UI_ACCENT:selected?[4]u8{255,211,92,235}:[4]u8{72,78,89,190},focused?4:selected?2:1);kind:=item.kind==.Collection?"COLLECTION":"STANDALONE";count_label:=item.kind==.Collection?fmt.tprintf("%d %s",item.story_count,item.story_count==1?"STORY":"STORIES"):"1 STORY";vk_text(r,374,y+10,strings.to_upper(item.title),highlighted?[4]u8{255,211,92,255}:[4]u8{248,247,242,255},.78);vk_text(r,374,y+35,fmt.tprintf("%s  •  %s",kind,count_label),{152,196,214,255},.46);vk_text(r,374,y+55,item.description,{190,195,202,255},.45);badge_w:=max(f32(128),f32(utf8_glyph_count(item.requirements))*COURIER_CELL_WIDTH*.43+24);vulkan_ui_rect(r,1038-badge_w,y+45,badge_w,24,{37,43,51,245});vulkan_ui_outline(r,1038-badge_w,y+45,badge_w,24,{139,107,55,210},1);vk_text(r,1050-badge_w,y+52,item.requirements,{255,211,92,255},.42);vk_text(r,902,y+10,item.creator,{152,196,214,255},.42)};vulkan_ui_scissor_reset(r)
		max_scroll:=max(content_height-viewport.h,0);if max_scroll>0 {rail_x:=viewport.x+viewport.w-8;thumb_h:=max(48,viewport.h*viewport.h/content_height);thumb_y:=viewport.y+(viewport.h-thumb_h)*campaign_browser.scroll/max_scroll;vulkan_ui_rect(r,rail_x,viewport.y,3,viewport.h,{116,122,136,180});vulkan_ui_rect(r,rail_x-4,thumb_y,11,thumb_h,{255,211,92,230})};vk_button(r,{120,610,180,52},"OPTIONS");vk_button(r,{310,610,150,52},"QUIT");if campaign_browser.feedback!="" do vk_text(r,720,578,campaign_browser.feedback,{152,196,214,255},.48)
	case .Campaign_Action:
		if campaign_workspace.open {vk_draw_campaign_workspace(r,g);break}
		if !vk_campaign_hero_cover(r,campaign_browser.selected,0,0,WINDOW_WIDTH,WINDOW_HEIGHT) do vk_art_cover(r,.Title,0,0,WINDOW_WIDTH,WINDOW_HEIGHT);vulkan_ui_rect(r,0,0,WINDOW_WIDTH,WINDOW_HEIGHT,{5,8,14,155});vk_panel(r,250,72,700,576)
		vk_text(r,310,112,campaign_document.title,{255,211,92,255},1.8);vk_text(r,312,158,campaign_document.description,{205,207,210,255},.68);vk_text(r,312,205,fmt.tprintf("%d CASE%s  •  %d COMPLETE",len(campaign_document.cases),len(campaign_document.cases)==1?"":"S",campaign_playthrough.completion_count),{152,196,214,255},.60)
		vk_button(r,{410,286,380,52},campaign_can_continue()?"NEW INVESTIGATION":"BEGIN NEW INVESTIGATION",true);if campaign_can_continue() do vk_button(r,{410,354,380,52},fmt.tprintf("CONTINUE  ·  %s",strings.to_upper(campaign_document.cases[campaign_playthrough.active_case].title)));else{vulkan_ui_rect(r,410,354,380,52,{38,42,48,225});vulkan_ui_outline(r,410,354,380,52,{82,88,98,180},1);vk_text(r,476,372,"CONTINUE  ·  NO ACTIVE CASE",{132,138,146,255},.57)};vk_text(r,410,418,"CREATOR TOOLS",{152,196,214,255},.52);if !player_package_mode do vk_button(r,{410,438,380,42},"EDIT CAMPAIGN");vk_button(r,{410,488,380,42},player_package_mode?"CREATE EDITABLE COPY / AUTHORING":"STORY AUTHORING");vk_button(r,{410,570,380,48},"CHOOSE ANOTHER CAMPAIGN")
	case .Authoring:
		vk_draw_authoring_workspace(r,g)
	case .Campaign_Cases:
		vk_art_cover(r,.Title,0,0,WINDOW_WIDTH,WINDOW_HEIGHT);vulkan_ui_rect(r,0,0,WINDOW_WIDTH,WINDOW_HEIGHT,{5,8,14,190});vk_panel(r,82,48,1036,624);vk_text(r,120,82,"CHOOSE A CASE",{255,211,92,255},1.75);vk_text(r,122,126,campaign_document.title,{205,207,210,255},.78)
		case_first:=campaign_case_page*4;case_last:=min(case_first+4,len(campaign_document.cases));for i in case_first..<case_last {item:=campaign_document.cases[i];box:=campaign_case_card_rect(i-case_first);y:=box.y;unlocked:=campaign_case_unlocked(&campaign_document,&campaign_playthrough,i);selected:=campaign_playthrough.active_case==i;focused:=unlocked&&vk_focused_button==button_id(box);highlighted:=selected||focused;vulkan_ui_rect(r,box.x,box.y,box.w,box.h,highlighted?[4]u8{28,38,49,248}:unlocked?[4]u8{22,30,39,240}:[4]u8{16,20,26,225});if focused do vulkan_ui_rect(r,box.x,box.y,7,box.h,UI_ACCENT);vulkan_ui_outline(r,box.x,box.y,box.w,box.h,focused?UI_ACCENT:selected?[4]u8{255,211,92,235}:unlocked?[4]u8{139,107,55,200}:[4]u8{64,70,78,180},focused?4:selected?2:1);vk_text(r,148,y+17,fmt.tprintf("CASE %d  ·  %s",i+1,strings.to_upper(item.title)),unlocked?[4]u8{248,247,242,255}:[4]u8{128,132,138,255},.88);vk_text(r,900,y+20,unlocked?"AVAILABLE":"LOCKED",unlocked?[4]u8{255,211,92,255}:[4]u8{128,132,138,255},.58);vk_text(r,148,y+48,item.required?"REQUIRED CASE":"OPTIONAL CASE",{152,196,214,255},.52)}
		case_pages:=max((len(campaign_document.cases)+3)/4,1);if case_pages>1 {vk_button(r,{500,558,48,34},"‹");vk_text(r,566,568,fmt.tprintf("%d / %d",campaign_case_page+1,case_pages),{205,207,210,255},.54);vk_button(r,{650,558,48,34},"›")};vk_button(r,{130,610,220,52},"BACK");if campaign_playthrough.active_case>=0 do vk_button(r,{760,610,310,52},"START NEW CASE",true);else{vulkan_ui_rect(r,760,610,310,52,{38,42,48,225});vulkan_ui_outline(r,760,610,310,52,{82,88,98,180},1);vk_text(r,821,628,"CHOOSE A CASE TO START",{132,138,146,255},.55)};if campaign_workspace.feedback!="" {vulkan_ui_rect(r,354,548,492,46,{48,25,24,245});vulkan_ui_outline(r,354,548,492,46,{255,211,92,230},2);vk_text(r,378,563,campaign_workspace.feedback,{248,247,242,255},.62)}
	case .Options:
		vk_art_cover(r,.Title,0,0,WINDOW_WIDTH,WINDOW_HEIGHT);vulkan_ui_rect(r,0,0,WINDOW_WIDTH,WINDOW_HEIGHT,{5,8,14,165});vk_panel(r,250,60,700,620);vk_heading(r,"OPTIONS","Audio, video, and controls")
		vk_text(r,410,115,"AUDIO",{255,211,92,255},.82);vk_button(r,{410,145,380,48},g.mute?"MUTED":"ON",true)
		vk_text(r,410,215,"ANTI-ALIASING",{255,211,92,255},.82);vk_button(r,{410,245,380,48},anti_aliasing_label(g.aa_mode),true)
		vk_text(r,410,315,"LIGHTING QUALITY",{255,211,92,255},.82);vk_button(r,{410,345,380,48},lighting_quality_label(g.lighting_quality),true)
		vk_text(r,410,415,"GUIDANCE",{255,211,92,255},.82);vk_button(r,{410,445,380,48},guidance_mode_label(g.guidance_mode),true);vk_text(r,410,501,"Changes control prompts only. Room hints stay neutral.",{205,207,210,255},.50)
		if g.aa_restart_required do vk_text(r,442,548,"ANTI-ALIASING SAVED — APPLIES NEXT LAUNCH",{205,207,210,255},.58)
		options_hint:=fmt.tprintf("%s NAVIGATE  •  %s SELECT",prompt_label(g,.Navigate),prompt_label(g,.Accept));hint_width:=f32(utf8_glyph_count(options_hint))*f32(COURIER_CELL_WIDTH)*.66;vk_text(r,(WINDOW_WIDTH-hint_width)*.5,602,options_hint,{205,207,210,255},.66);vk_button(r,{410,630,380,42},"BACK",true)
	case .Pause:
		vulkan_ui_rect(r,0,0,WINDOW_WIDTH,WINDOW_HEIGHT,{2,4,7,180});vk_panel(r,320,74,560,580)
		vk_text(r,503,108,"GAME PAUSED",{255,211,92,255},1.35);vk_text(r,443,154,"THE STORY WAITS FOR YOU",{205,207,210,255},.60)
		load_available:=pause_snapshot_available&&(pause_snapshot_content_identity==0||g.story_runtime!=nil&&g.story_runtime.compiled.content_identity==pause_snapshot_content_identity);vk_button(r,{410,210,380,48},"RESUME",true);vk_button(r,{410,266,380,48},"SAVE GAME");vk_button(r,{410,322,380,48},load_available?"LOAD GAME":"LOAD GAME  ·  EMPTY");vk_button(r,{410,378,380,48},"OPTIONS");vk_button(r,{410,434,380,48},"MAIN MENU");vk_button(r,{410,490,380,48},"QUIT")
		if g.pause_feedback!="" do vk_text(r,522,564,g.pause_feedback,g.pause_feedback=="GAME SAVED"?[4]u8{152,196,214,255}:[4]u8{255,211,92,255},.58)
	case .Introduction:
		vk_draw_introduction(r,g)
	case .Loading:
		vk_draw_map_loading(r,g)
	case .Exterior:
		vk_draw_city_overlay(r,g)
	case .Investigate,.Dialogue:
		if g.screen==.Investigate&&!g.story_presentation.active do vk_draw_house_overlay(r,g);if g.screen==.Dialogue {if g.story_presentation.active do vk_draw_cinematic_dialogue(r,g);else do vk_draw_dialogue(r,g)};if graph_state.playtesting {vk_draw_graph_debugger(r,g);vk_button(r,graph_debugger_editor_rect(),g.editor_mode==.Graph?"GAME":"EDITOR",g.editor_mode==.Graph)}
	case .Attributes:
		vk_draw_attributes(r,g)
	case .Notebook:
		vk_draw_notebook(r,g)
	case .Check: vk_draw_check(r,g)
	case .Board: if g.board_view==0 do vk_draw_workbench(r,g);else do vk_draw_event_chain(r,g)
	case .Challenge: vk_draw_challenge(r,g)
	case .Recreate: if g.workbench_event_count>0 do vk_draw_event_chain_test(r,g);else do vk_draw_workbench_recreate(r,g)
	case .Reveal_Prep: vk_draw_reveal_prep(r,g)
	case .Reveal: vk_draw_reveal(r,g)
	case .Result: vk_draw_result(r,g)
	case .Game_Over: vk_draw_game_over(r,g)
	case .Diagnostics: vk_draw_diagnostics(r,g)
	}
	if g.screen!=.Loading&&g.active_device==.Keyboard_Mouse&&!check_roll_animating(g) do vulkan_ui_outline(r,g.input.mouse_pos.x-5,g.input.mouse_pos.y-5,10,10,{255,218,112,255})
	vk_draw_quest_transition_overlay(r,g)
	vk_draw_scene_transition(r,g)
	if g.controller_disconnected {
		vulkan_ui_rect(r,0,0,WINDOW_WIDTH,WINDOW_HEIGHT,{2,4,7,190});vk_panel(r,330,252,540,216)
		vk_text(r,416,294,"CONTROLLER DISCONNECTED",{255,211,92,255},1.05)
		vk_text(r,421,350,"GAMEPLAY IS PAUSED",{248,247,242,255},.78)
		vk_text(r,370,395,"Reconnect and use it, or press a keyboard or mouse button.",{205,207,210,255},.48)
	}
	r.profile_draw_overlay_ms=time.duration_seconds(time.tick_diff(draw_phase_started,time.tick_now()))*1000
}
