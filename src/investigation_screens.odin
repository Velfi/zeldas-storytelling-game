package main

editor_advance_from_foundation :: proc(g:^Game,doc:^Level_Document,foundation_index:int)->bool {if foundation_index<0||foundation_index>=len(doc.foundations) do return false;created:=doc.foundations[foundation_index];if created.kind==.Basement&&created.story>=0 do _=level_set_active_story(doc,created.story);g.build_tool=.Room;editor_state.room_mode=.Rectangle;editor_state.selection[0]={.Foundation,created.id,-1};editor_state.selection_count=1;return true}

editor_create_room_from_foundation :: proc(g:^Game,doc:^Level_Document,foundation_id:string)->bool {index:=level_foundation_index(doc,foundation_id);if index<0 do return false;foundation:=doc.foundations[index];story:=foundation.kind==.Basement?foundation.story:level_ground_story(doc);if story<0 do return false;if doc.active_story!=story do _=level_set_active_story(doc,story);room_id:=level_next_id("room",doc.revision);create:=Level_Command{kind=.Create_Room_Polygon,entity_id=room_id,material=strings.to_lower(fmt.tprintf("%v",g.build_surface)),point_count=min(len(foundation.points),32)};for point,i in foundation.points {if i>=create.point_count do break;create.points[i]=point};preview:=create;preview.entity_id="";if level_preview_transaction(doc,preview).state==.Blocked do return false;commands:=[2]Level_Command{create,{kind=.Set_Platform,entity_id=room_id,value=foundation.kind==.Raised?foundation.elevation:0}};if !level_commit_transactions(doc,commands[:],"Create room from foundation") do return false;editor_state.selection[0]={.Room,room_id,-1};editor_state.selection_count=1;g.build_tool=.Select;return true}

editor_finish_foundation_polygon :: proc(g:^Game,repeat:bool)->bool {if editor_state.foundation_draw_count<3 do return false;command:=Level_Command{kind=.Create_Foundation,value=editor_state.foundation_elevation,c={f32(editor_state.foundation_kind),editor_state.foundation_depth},point_count=editor_state.foundation_draw_count};copy(command.points[:],editor_state.foundation_draw_points[:editor_state.foundation_draw_count]);editor_state.foundation_polygon_preview=level_preview_transaction(&level_document,command);if editor_state.foundation_polygon_preview.state==.Blocked do return false;foundation_count:=len(level_document.foundations);if !level_commit_transaction(&level_document,command,fmt.tprintf("Create polygon %s foundation",level_foundation_kind_name(editor_state.foundation_kind))) do return false;editor_state.foundation_draw_count=0;if !repeat&&len(level_document.foundations)>foundation_count do _=editor_advance_from_foundation(g,&level_document,len(level_document.foundations)-1);return true}

import "core:fmt"
import "core:math"
import "core:os"
import "core:sync"
import "core:strings"
import "core:thread"
import ui "zelda_engine:ui"

update_campaign_workspace :: proc(g:^Game) {
	doc:=&campaign_workspace.draft
	if campaign_workspace.text_field!=.None {box:=Rect{400,610,620,34};id:=button_id(box);g.gui.focused=id;ui.gui_text_edit_begin(&g.gui,id,campaign_workspace.text_count);ui.gui_text_edit_handle_mouse(&g.gui,id,campaign_workspace.text_buffer[:],campaign_workspace.text_count,ui.Rect(box),ui.Vec2{box.x+8,box.y+8});_=ui.gui_text_edit_process(&g.gui,id,campaign_workspace.text_buffer[:],&campaign_workspace.text_count);if g.input.key_enter do _=campaign_workspace_commit_text();if g.input.key_escape do campaign_workspace.text_field=.None;return}
	if campaign_workspace.exit_confirm {if g.input.back {campaign_workspace.exit_confirm=false;g.input.back=false;return};if button(g,{320,390,170,42}) {saved:=save_campaign_manifest(campaign_manifest_path,doc);campaign_workspace.feedback=saved.message;if saved.ok do campaign_workspace_discard_and_close()};if button(g,{505,390,170,42}) do campaign_workspace_discard_and_close();if button(g,{690,390,170,42}) do campaign_workspace.exit_confirm=false;return}
	if g.input.back {campaign_workspace_request_close();g.input.back=false;return}
	for tab in Campaign_Workspace_Tab do if button(g,{18+f32(int(tab))*164,64,156,38}) do campaign_workspace.tab=tab
	if button(g,{18,666,150,38}) do campaign_workspace_request_close()
	if button(g,{178,666,150,38}) {saved:=save_campaign_manifest(campaign_manifest_path,doc);campaign_workspace.feedback=saved.message;campaign_workspace.diagnostics=saved}
	if button(g,{338,666,150,38}) {campaign_workspace.diagnostics=campaign_validate(doc);campaign_workspace.feedback=campaign_workspace.diagnostics.message}
	if button(g,{498,666,100,38}) do _=campaign_workspace_undo();if button(g,{608,666,100,38}) do _=campaign_workspace_redo()
	switch campaign_workspace.tab {
	case .Overview:
		if button(g,{40,120,500,34}) do campaign_workspace_begin_text(.Campaign_Format,doc.version);if button(g,{550,120,500,34}) do campaign_workspace_begin_text(.Campaign_ID,doc.id)
		if button(g,{40,164,500,34}) do campaign_workspace_begin_text(.Campaign_Title,doc.title);if button(g,{550,164,500,34}) do campaign_workspace_begin_text(.Campaign_Creator,doc.creator)
		if button(g,{40,208,500,34}) do campaign_workspace_begin_text(.Campaign_Version,doc.content_version);if button(g,{550,208,500,34}) do campaign_workspace_begin_text(.Campaign_Thumbnail,doc.thumbnail)
		if button(g,{40,252,1010,120}) do campaign_workspace_begin_text(.Campaign_Description,doc.description)
		if button(g,{40,390,150,36}) {path:=authoring_native_save_file("New Campaign","campaign.toml");if path!="" do campaign_workspace.feedback=campaign_workspace_new_manifest(path).message};if button(g,{200,390,150,36}) {path:=authoring_native_open_file("Open Campaign");if path!="" do campaign_workspace.feedback=campaign_workspace_open_manifest(path).message};if button(g,{360,390,150,36}) {path:=authoring_native_save_file("Duplicate Campaign",fmt.tprintf("%s-copy.toml",doc.id));if path!="" do campaign_workspace.feedback=campaign_workspace_save_as(path,true).message};if button(g,{520,390,150,36}) {path:=authoring_native_save_file("Save Campaign As",fmt.tprintf("%s.toml",doc.id));if path!="" do campaign_workspace.feedback=campaign_workspace_save_as(path).message};if button(g,{680,390,150,36}) {path:=authoring_native_save_file("Move Campaign",fmt.tprintf("%s.toml",doc.id));if path!="" do campaign_workspace.feedback=campaign_workspace_move_manifest(path).message};if button(g,{840,390,190,36}) {if campaign_workspace.delete_confirm {campaign_workspace.feedback=campaign_workspace_delete_manifest().message;campaign_workspace.delete_confirm=false}else{campaign_workspace.delete_confirm=true;campaign_workspace.feedback="PRESS DELETE AGAIN TO MOVE CAMPAIGN TO TRASH"}}
	case .Cases:
		if button(g,{30,108,120,32}) do _=campaign_workspace_add_case();if button(g,{158,108,80,32}) do _=campaign_workspace_move_case(-1);if button(g,{246,108,80,32}) do _=campaign_workspace_move_case(1);if button(g,{334,108,110,32}) do _=campaign_workspace_remove_case()
		for _,i in doc.cases do if button(g,{30,148+f32(i)*48,520,40}) do campaign_workspace.selected_case=i
		i:=campaign_workspace.selected_case;if i>=0&&i<len(doc.cases) {item:=&doc.cases[i];if button(g,{620,112,250,34}) do campaign_workspace_begin_text(.Case_Title,item.title);if button(g,{880,112,250,34}) do campaign_workspace_begin_text(.Case_ID,item.id);if button(g,{620,160,250,38}) {item.required=!item.required;item.optional=!item.required;campaign_workspace_mark_changed("CASE REQUIREMENT UPDATED")};if button(g,{880,160,250,38}) do campaign_workspace_begin_text(.Case_Content_Version,item.case_content_version);if button(g,{620,208,250,38}) {item.replay_mode=Campaign_Replay_Mode((int(item.replay_mode)+1)%len(Campaign_Replay_Mode));campaign_workspace_mark_changed("REPLAY POLICY UPDATED")};if button(g,{620,256,250,38}) {item.invalid_result_policy=Campaign_Invalid_Result_Policy((int(item.invalid_result_policy)+1)%len(Campaign_Invalid_Result_Policy));campaign_workspace_mark_changed("HISTORY POLICY UPDATED")};if button(g,{620,304,250,38}) {item.unavailable_presentation=Campaign_Unavailable_Presentation((int(item.unavailable_presentation)+1)%len(Campaign_Unavailable_Presentation));campaign_workspace_mark_changed("LOCK PRESENTATION UPDATED")};if button(g,{620,358,510,30}) do campaign_workspace_begin_text(.Story_Path,item.story_path);if button(g,{620,400,510,30}) do campaign_workspace_begin_text(.Level_Path,item.level_path);if button(g,{620,442,510,50}) do campaign_workspace_begin_text(.Locked_Message,item.locked_message);if button(g,{620,504,165,36}) do campaign_workspace.feedback=campaign_workspace_open_case_source().message;if button(g,{795,504,165,36}) do campaign_workspace.feedback=campaign_workspace_create_case_source(false).message;if button(g,{970,504,165,36}) do campaign_workspace.feedback=campaign_workspace_create_case_source(true).message}
	case .Variables:
		if button(g,{30,120,150,38}) do _=campaign_workspace_add_variable();if button(g,{190,120,100,38}) {removed:=campaign_variable_remove(doc,campaign_workspace.selected_variable);if removed.ok {campaign_workspace.selected_variable=clamp(campaign_workspace.selected_variable,0,max(0,len(doc.variables)-1));campaign_workspace_mark_changed(removed.message)}else do campaign_workspace.feedback=removed.message};if button(g,{300,120,90,38})&&campaign_variable_reorder(doc,campaign_workspace.selected_variable,max(0,campaign_workspace.selected_variable-1)) {campaign_workspace.selected_variable=max(0,campaign_workspace.selected_variable-1);campaign_workspace_mark_changed("VARIABLE MOVED")};if button(g,{400,120,90,38})&&campaign_variable_reorder(doc,campaign_workspace.selected_variable,min(len(doc.variables)-1,campaign_workspace.selected_variable+1)) {campaign_workspace.selected_variable=min(len(doc.variables)-1,campaign_workspace.selected_variable+1);campaign_workspace_mark_changed("VARIABLE MOVED")};for _,i in doc.variables do if button(g,{30,170+f32(i)*46,480,38}) do campaign_workspace.selected_variable=i
		text_variable:=campaign_workspace.selected_variable;if text_variable>=0&&text_variable<len(doc.variables) {variable:=&doc.variables[text_variable];if button(g,{620,120,260,34}) do campaign_workspace_begin_text(.Variable_Name,variable.display_name);if button(g,{890,120,260,34}) do campaign_workspace_begin_text(.Variable_ID,variable.id);if button(g,{890,170,260,86}) do campaign_workspace_begin_text(.Variable_Description,variable.description);if variable.kind==.Enumeration&&campaign_workspace.selected_enum_value<variable.enum_value_count&&button(g,{890,266,260,34}) do campaign_workspace_begin_text(.Enum_Value,variable.enum_values[campaign_workspace.selected_enum_value])}
		i:=campaign_workspace.selected_variable;if i>=0&&i<len(doc.variables) {variable:=&doc.variables[i];if button(g,{620,170,260,38}) {replacement:=variable^;replacement.kind=Campaign_Value_Kind((int(variable.kind)+1)%len(Campaign_Value_Kind));if replacement.kind==.Enumeration&&replacement.enum_value_count==0 {replacement.enum_values[0]="default";replacement.enum_value_count=1;replacement.default_enum="default"};converted:=campaign_variable_convert(doc,i,replacement,true);campaign_workspace.feedback=converted.message;if converted.ok do campaign_workspace_mark_changed("VARIABLE TYPE UPDATED")};if variable.kind==.Boolean&&button(g,{620,218,260,38}) {variable.default_boolean=!variable.default_boolean;campaign_workspace_mark_changed("DEFAULT UPDATED")};if variable.kind==.Integer {if button(g,{620,218,120,38}) {variable.default_integer-=1;campaign_workspace_mark_changed("DEFAULT UPDATED")};if button(g,{750,218,120,38}) {variable.default_integer+=1;campaign_workspace_mark_changed("DEFAULT UPDATED")}}else if variable.kind==.Enumeration {if button(g,{620,266,120,34}) do _=campaign_workspace_add_enum_value();if button(g,{750,266,120,34}) do _=campaign_workspace_remove_enum_value();for value_index in 0..<variable.enum_value_count do if button(g,{620,310+f32(value_index)*38,260,32}) {campaign_workspace.selected_enum_value=value_index;variable.default_enum=variable.enum_values[value_index];campaign_workspace_mark_changed("ENUM DEFAULT UPDATED")}}}
	case .Conditions:
		for _,i in doc.cases do if button(g,{30,120+f32(i)*46,440,38}) {campaign_workspace.selected_case=i;campaign_workspace.selected_condition=doc.cases[i].condition_root}
		kinds:=[11]Campaign_Condition_Kind{.Always,.Never,.All,.Any,.Not,.Boolean_Equals,.Integer_Compare,.Enum_Equals,.Case_Started,.Case_Completed,.Case_Outcome};for kind,i in kinds do if button(g,{500+f32(i%3)*205,120+f32(i/3)*44,195,34}) do _=campaign_workspace_add_condition(kind)
		if button(g,{500,304,82,28}) do _=campaign_workspace_select_condition(-1);if button(g,{590,304,82,28}) do _=campaign_workspace_select_condition(1);if button(g,{680,304,92,28}) do _=campaign_workspace_move_condition(-1);if button(g,{780,304,92,28}) do _=campaign_workspace_move_condition(1);if button(g,{880,304,112,28}) do _=campaign_workspace_remove_condition();if button(g,{1000,304,112,28}) do _=campaign_workspace_reset_condition();if button(g,{1000,338,112,28}) do _=campaign_workspace_insert_condition_child()
		i:=campaign_workspace.selected_case;if i>=0&&i<len(doc.cases) {root:=doc.cases[i].condition_root;if campaign_workspace.selected_condition<0 do campaign_workspace.selected_condition=root;node_index:=campaign_workspace.selected_condition;if node_index>=0&&node_index<len(doc.conditions) {node:=&doc.conditions[node_index];if (node.kind==.Boolean_Equals||node.kind==.Integer_Compare||node.kind==.Enum_Equals)&&len(doc.variables)>0&&button(g,{520,370,410,38}) {kind:Campaign_Value_Kind=.Boolean;if node.kind==.Integer_Compare do kind=.Integer;else if node.kind==.Enum_Equals do kind=.Enumeration;next:=campaign_next_variable_of_kind(doc,node.variable_id,kind);if next>=0 {node.variable_id=doc.variables[next].id;if kind==.Enumeration do node.enum_value=doc.variables[next].default_enum;campaign_workspace_mark_changed("CONDITION VARIABLE UPDATED")}};if node.kind==.Boolean_Equals&&button(g,{520,418,200,38}) {node.boolean_value=!node.boolean_value;campaign_workspace_mark_changed("BOOLEAN TARGET UPDATED")};if node.kind==.Integer_Compare {if button(g,{520,418,200,38}) {node.integer_comparison=Campaign_Integer_Comparison((int(node.integer_comparison)+1)%len(Campaign_Integer_Comparison));campaign_workspace_mark_changed("COMPARISON UPDATED")};if button(g,{730,418,96,38}) {node.integer_value-=1;campaign_workspace_mark_changed("THRESHOLD UPDATED")};if button(g,{836,418,96,38}) {node.integer_value+=1;campaign_workspace_mark_changed("THRESHOLD UPDATED")}};if node.kind==.Enum_Equals {variable:=campaign_variable_index(doc,node.variable_id);if variable>=0&&button(g,{520,418,410,38}) {v:=doc.variables[variable];current:=0;for value_index in 0..<v.enum_value_count do if v.enum_values[value_index]==node.enum_value do current=value_index;current=(current+1)%v.enum_value_count;node.enum_value=v.enum_values[current];campaign_workspace_mark_changed("ENUM TARGET UPDATED")}};if (node.kind==.Case_Completed||node.kind==.Case_Started||node.kind==.Case_Outcome)&&len(doc.cases)>0&&button(g,{520,466,410,38}) {current:=campaign_case_index(doc,node.case_id);current=(current+1)%len(doc.cases);node.case_id=doc.cases[current].id;campaign_workspace_mark_changed("CONDITION CASE UPDATED")};if node.kind==.Case_Outcome&&button(g,{520,514,410,38}) {node.outcome=Outcome((int(node.outcome)+1)%len(Outcome));campaign_workspace_mark_changed("CASE OUTCOME UPDATED")}}}
	case .Effects:
		for _,i in doc.cases do if button(g,{30,120+f32(i)*42,420,34}) do campaign_workspace.selected_case=i
		if button(g,{500,120,220,36}) {campaign_workspace.selected_outcome=(campaign_workspace.selected_outcome+1)%len(Outcome)};if button(g,{730,120,120,36}) do _=campaign_workspace_add_effect();if button(g,{860,120,100,36}) do _=campaign_workspace_remove_effect();if button(g,{970,120,70,36}) do _=campaign_workspace_move_effect(-1);if button(g,{1050,120,70,36}) do _=campaign_workspace_move_effect(1)
		if campaign_workspace.selected_case>=0&&campaign_workspace.selected_case<len(doc.cases) {first,count:=campaign_effect_range(doc.cases[campaign_workspace.selected_case],Outcome(clamp(campaign_workspace.selected_outcome,0,len(Outcome)-1)));for offset in 0..<count {effect_index:=first+offset;if button(g,{500,164+f32(offset)*34,450,28}) do campaign_workspace.selected_effect=effect_index}}
		if campaign_workspace.selected_effect>=0&&campaign_workspace.selected_effect<len(doc.effects) {effect:=&doc.effects[campaign_workspace.selected_effect];if len(doc.variables)>0&&button(g,{500,500,450,38}) {current:=campaign_variable_index(doc,effect.variable_id);current=(current+1)%len(doc.variables);variable:=doc.variables[current];effect.variable_id=variable.id;effect.kind=variable.kind==.Boolean?.Set_Boolean:variable.kind==.Integer?.Set_Integer:.Set_Enum;effect.enum_value=variable.default_enum;campaign_workspace_mark_changed("EFFECT TARGET UPDATED")};if effect.kind==.Set_Boolean&&button(g,{500,548,220,38}) {effect.boolean_value=!effect.boolean_value;campaign_workspace_mark_changed("EFFECT VALUE UPDATED")};if effect.kind==.Set_Integer||effect.kind==.Add_Integer {if button(g,{500,548,100,38}) {effect.integer_value-=1;campaign_workspace_mark_changed("EFFECT VALUE UPDATED")};if button(g,{610,548,100,38}) {effect.integer_value+=1;campaign_workspace_mark_changed("EFFECT VALUE UPDATED")};if button(g,{720,548,230,38}) {effect.kind=effect.kind==.Set_Integer?.Add_Integer:.Set_Integer;campaign_workspace_mark_changed("EFFECT OPERATION UPDATED")}};if effect.kind==.Set_Enum {variable:=campaign_variable_index(doc,effect.variable_id);if variable>=0&&button(g,{500,548,450,38}) {v:=doc.variables[variable];if v.enum_value_count>0 {current:=0;for j in 0..<v.enum_value_count do if v.enum_values[j]==effect.enum_value do current=j;effect.enum_value=v.enum_values[(current+1)%v.enum_value_count];campaign_workspace_mark_changed("EFFECT VALUE UPDATED")}}}}
		if button(g,{500,600,150,34}) do _=campaign_workspace_move_effect_mapping(-1);if button(g,{660,600,150,34}) do _=campaign_workspace_move_effect_mapping(1);if button(g,{820,600,190,34}) do _=campaign_workspace_remove_effect_mapping()
	case .Simulation:
		if len(doc.variables)>0 {if button(g,{780,108,180,34}) do campaign_workspace.selected_variable=(campaign_workspace.selected_variable+1)%len(doc.variables);v:=doc.variables[campaign_workspace.selected_variable];if v.kind==.Boolean&&button(g,{970,108,180,34}) do campaign_workspace.feedback=campaign_workspace_simulation_change_variable(campaign_workspace.selected_variable,1).message;else if v.kind==.Integer {if button(g,{970,108,82,34}) do campaign_workspace.feedback=campaign_workspace_simulation_change_variable(campaign_workspace.selected_variable,-1).message;if button(g,{1060,108,82,34}) do campaign_workspace.feedback=campaign_workspace_simulation_change_variable(campaign_workspace.selected_variable,1).message}else if v.enum_value_count>0&&button(g,{970,108,180,34}) do campaign_workspace.feedback=campaign_workspace_simulation_change_variable(campaign_workspace.selected_variable,1).message}
		for _,i in doc.cases do if button(g,{30,130+f32(i)*48,720,38}) do campaign_workspace.selected_case=i
		i:=campaign_workspace.selected_case;if i>=0&&i<len(doc.cases) {if button(g,{30,610,150,34}) do campaign_workspace.feedback=campaign_workspace_simulation_start(i).message;if button(g,{190,610,190,34}) do campaign_workspace.feedback=campaign_workspace_simulation_complete(i).message;if button(g,{390,610,150,34}) do campaign_workspace.feedback=campaign_workspace_simulation_clear(i).message;if button(g,{550,610,190,34}) {loaded:=campaign_load_case_now(g,i);campaign_workspace.feedback=loaded.message;if loaded.ok do campaign_workspace.open=false}}
	case .Diagnostics:
		if button(g,{30,130,240,38}) do campaign_workspace.diagnostics=campaign_validate(doc);if button(g,{30,180,1120,36}) do _=campaign_workspace_navigate_validation();for _,i in doc.cases do if button(g,{40,260+f32(i)*34,1080,30}) do _=campaign_workspace_navigate_dependency(i)
	}
}

discover_clue_free :: proc(g:^Game,clue_index:int)->bool {
	payload:=mystery_game_payload(g);if payload==nil||clue_index<0||clue_index>=len(payload.clues)||mystery_game_clue_discovered(g,clue_index) do return false
	first_examination:=!tutorial_completed(g,.Examine);tutorial_complete(g,.Examine)
	if g.story_project!=nil&&g.mystery_state!=nil&&!mystery_acquire_evidence_free(g.story_project,g.mystery_state,payload.clues[clue_index].id) do return false
	_=mystery_game_mark_clue(g,clue_index);mystery_game_mark_clue_attempted(g,clue_index)
	for topic in payload.clues[clue_index].topics[:payload.clues[clue_index].topic_count] do unlock_topic(g,topic)
	log_line(g,payload.clues[clue_index].description)
	refresh_questions(g)
	play_sound(g,.Evidence)
	if first_examination&&g.screen==.Investigate {context_feedback(g,"OBSERVATION RECORDED · OPEN NOTEBOOK",.Complete,"notebook_recorded");g.context_ui.feedback_expires=g.animation_time+5}
	return true
}

case_uses_city_tutorial :: proc(g:^Game)->bool {payload:=mystery_game_payload(g);return payload!=nil&&payload.tutorial_id=="basic_controls"}
case_starts_in_city :: proc(g:^Game)->bool {payload:=mystery_game_payload(g);return payload!=nil&&payload.city_start!=""}

advance_introduction :: proc(g:^Game) {
	switch g.introduction_step {
	case 0: g.introduction_step=1
	case 1:
		// The house, not an omniscient tutorial, supplies the opening facts. The
		// watch can be handled on Edgar's wrist and Miriam's account must be
		// heard from Miriam before their contradiction exists in player knowledge.
		refresh_questions(g);g.question_feedback="Begin with what looks out of place. Statements and observations will open questions on your board."
		g.phase=.Investigation
		g.screen=.Investigate
	}
}

reset_case_state :: proc(g:^Game,story_seed:u64,destination:Screen) {
	delete(g.quest_transition_ids);delete(g.quest_transition_status)
	gui:=g.gui;audio_stream:=g.audio_stream;vehicle_audio_stream:=g.vehicle_audio_stream;sounds:=g.sounds;mute:=g.mute;aa_mode:=g.aa_mode;lighting_quality:=g.lighting_quality;guidance_mode:=g.guidance_mode;tutorial:=g.tutorial;persist_seed:=g.persist_seed;active_device:=g.active_device
	story_project:=g.story_project;compiled_story:=g.compiled_story;story_runtime:=g.story_runtime;spatial_service:=g.spatial_service
	gui.focused=destination==.Title?button_id({410,400,380,48}):button_id({410,625,380,58})
	phase:=destination==.Investigate?Case_Phase.Investigation:Case_Phase.Introduction
	action_budget:=0;if payload:=mystery_payload(story_project);payload!=nil do action_budget=payload.action_budget
	g^=Game{running=true,screen=destination,phase=phase,ap=action_budget,seed=story_seed,run_seed=story_seed,persist_seed=persist_seed,mute=mute,aa_mode=aa_mode,lighting_quality=lighting_quality,guidance_mode=guidance_mode,pending_clue=-1,active_ending=-1,board_last_section=-1,board_last_socket=-1,timeline_order={0,1,2},gui=gui,audio_stream=audio_stream,vehicle_audio_stream=vehicle_audio_stream,sounds=sounds,player_x=3.5,player_y=12.5,camera_x=3.5,camera_y=12.5,camera_initialized=true,camera_orbit=math.PI/4,camera_zoom=1,camera_orbit_initialized=true,catalog_bake_index=-1,pending_world_interaction=-1,pending_interactive=-1,hover_interactive=-1,near_interactive=-1,auto_door=-1,hover_entity=-1,near_entity=-1,dialogue_entity=-1,near_landmark=-1,driving_vehicle=-1,near_vehicle=-1,active_device=active_device}
	if story_runtime!=nil&&compiled_story!=nil {story_runtime_destroy(story_runtime);story_runtime^=story_runtime_new(compiled_story,spatial_service)}
	g.story_project=story_project;g.compiled_story=compiled_story;g.story_runtime=story_runtime;g.story_state=story_runtime==nil?nil:&story_runtime.state;g.mystery_state=story_runtime==nil?nil:cast(^Mystery_State)story_runtime_capability_state(story_runtime,"mystery",MYSTERY_DOMAIN_VERSION);g.spatial_service=spatial_service
	g.guidance_mode=guidance_mode;g.tutorial=tutorial;g.tutorial.guidance=guidance_mode
	if !case_uses_city_tutorial(g) {tutorial_complete(g,.Move);tutorial_complete(g,.Look);tutorial_complete(g,.Briefing);tutorial_complete(g,.Travel)}
	payload:=mystery_game_payload(g);if destination==.Exterior&&payload!=nil&&payload.city_start!="" do _=city_place_at_landmark(g,payload.city_start)
	if destination==.Investigate do _=apply_player_spawn_marker(g)
	initialize_dispositions(g);initialize_character_animations(g)
}
enter_game_over :: proc(g:^Game,reason:string) {g.game_over_reason=reason;g.screen=.Game_Over;g.gui.focused=button_id({410,410,380,52});g.focus_screen_initialized=false}
route_locked_investigation :: proc(g:^Game) {if g.game_over_reason!="" {if !enter_case_ending(g,"out_of_time") do g.screen=.Game_Over}else{g.screen=.Reveal_Prep}}

active_case_ending :: proc(g:^Game)->^Mystery_Ending_Metadata {payload:=mystery_game_payload(g);if payload==nil||g.active_ending<0||g.active_ending>=len(payload.endings) do return nil;return &payload.endings[g.active_ending]}
case_ending_trigger_for_outcome :: proc(outcome:Outcome)->string {return fmt.tprintf("outcome.%s",campaign_outcome_text(outcome))}
enter_case_ending :: proc(g:^Game,id_or_trigger:string)->bool {
	index:=mystery_ending_index(g.story_project,id_or_trigger);if index<0 do return false
	g.active_ending=index;ending:=active_case_ending(g);if ending==nil do return false;g.show_canonical=false;g.phase=.Case_Result;g.screen=.Result;g.focus_screen_initialized=false
	if outcome,ok:=campaign_outcome_from_text(ending.outcome);ok {g.result=outcome;if g.persist_seed {applied:=campaign_apply_result(&campaign_document,&campaign_playthrough,Campaign_Case_Result{case_id=g.story_project.id,outcome=outcome});if applied.ok do _=save_campaign_playthrough()}}
	return true
}
perform_case_ending_action :: proc(g:^Game,action:string) {
	switch action {case "campaign":reset_case_state(g,begin_new_story_seed(),.Campaign);case "restart":destination:Screen=case_starts_in_city(g)?.Exterior:.Investigate;reset_case_state(g,g.run_seed,destination);case "title":reset_case_state(g,begin_new_story_seed(),.Title);case "quit":g.running=false;case "reveal":g.show_canonical=true}
}

continue_from_title :: proc(g:^Game) {
	if g.menu_return==.Title {
		g.screen=case_starts_in_city(g)?.Exterior:.Investigate;g.phase=.Investigation
		if g.screen==.Investigate do _=apply_player_spawn_marker(g)
	} else do g.screen=g.menu_return
}

Case_Load_Work :: struct {
	state:i32,
	index:int,
	level:Level_Document,
	story:Story_Project,
	compiled:Compiled_Story,
	spatial_registry:Story_Spatial_Registry,
	result:Validation,
	worker:^thread.Thread,
}

case_load_work:Case_Load_Work

campaign_prepare_case :: proc(index:int,out:^Case_Load_Work)->Validation {
	if index<0||index>=len(campaign_document.cases)||!campaign_case_unlocked(&campaign_document,&campaign_playthrough,index) do return {false,"campaign case is unavailable"}
	item:=campaign_document.cases[index]
	if loaded:=load_story_project(item.story_path,&out.story);!loaded.ok do return loaded
	if out.story.id!=item.id do return {false,"campaign case ID does not match its story document"}
	compiled:=compile_story_project(&out.story);if !compiled.ok do return {false,compiled.message};out.compiled=compiled.story
	sync.atomic_store_explicit(&out.state,2,.Release)
	sync.atomic_store_explicit(&out.state,3,.Release)
	if loaded:=level_load(item.level_path,&out.level);!loaded.ok do return loaded
	assert(story_spatial_registry_register(&out.spatial_registry,story_level_space(&out.level)));_=story_spatial_registry_register(&out.spatial_registry,story_city_space());bindings:=story_spatial_validate_project(&out.story,&out.spatial_registry);if !bindings.ok {story_validation_destroy(&bindings);return {false,"story has invalid spatial bindings"}};story_validation_destroy(&bindings)
	// Projection only writes the next scene's runtime data. The loading screen
	// neither renders nor updates that world, so it can safely be prepared here.
	level_project_runtime(&out.level)
	sync.atomic_store_explicit(&out.state,4,.Release)
	return {true,"CASE READY"}
}

campaign_case_load_worker :: proc(_: ^thread.Thread) {
	case_load_work.result=campaign_prepare_case(case_load_work.index,&case_load_work)
	sync.atomic_store_explicit(&case_load_work.state,case_load_work.result.ok?i32(5):i32(6),.Release)
}

campaign_case_load_reap :: proc() {if case_load_work.worker!=nil {thread.join(case_load_work.worker);thread.destroy(case_load_work.worker);case_load_work.worker=nil}}

authoring_app_request_build_exit :: proc(g:^Game) {
	authoring_app_sync_dirty()
	if active_authoring_ready&&authoring_project_dirty(&active_authoring_project) {editor_state.exit_confirm_visible=true;editor_state.shortcut_help_visible=false}else{g.editor_mode=.None;g.interactive_count=0}
	g.move_target_active=false
}

campaign_finish_prepared_case :: proc(g:^Game)->Validation {
	index:=case_load_work.index;item:=campaign_document.cases[index]
	if active_authoring_ready {bound:=authoring_app_bind_case(index);if !bound.ok do return {false,bound.message}}
	level_document=case_load_work.level;LEVEL_DEFAULT_PATH=item.level_path
	story_runtime_destroy(&active_story_runtime);compiled_story_destroy(&active_compiled_story);story_project_destroy(&active_story_project);story_spatial_registry_destroy(&active_spatial_registry)
	active_story_project=case_load_work.story;active_compiled_story=case_load_work.compiled;active_spatial_registry=case_load_work.spatial_registry;active_spatial_service=story_spatial_registry_service(&active_spatial_registry);active_story_runtime=story_runtime_new(&active_compiled_story,&active_spatial_service);world_entities_result:=world_entities_rebuild(&active_story_project,&level_document);if !world_entities_result.ok do return {false,world_entities_result.message}
	g.story_project=&active_story_project;g.story_state=&active_story_runtime.state;g.compiled_story=&active_compiled_story;g.story_runtime=&active_story_runtime;g.mystery_state=cast(^Mystery_State)story_runtime_capability_state(&active_story_runtime,"mystery",MYSTERY_DOMAIN_VERSION);g.spatial_service=&active_spatial_service
	graph_import_story(&active_story_project);campaign_playthrough.active_case=index;campaign_playthrough.results[index].started=true;campaign_playthrough.results[index].case_id=item.id;campaign_playthrough.results[index].case_content_version=item.case_content_version;_=save_campaign_playthrough();destination:Screen=case_starts_in_city(g)?.Exterior:.Investigate;reset_case_state(g,begin_new_story_seed(),destination);return {true,"CASE STARTED"}
}

campaign_load_case_now :: proc(g:^Game,index:int)->Validation {
	work:=Case_Load_Work{index=index};loaded:=campaign_prepare_case(index,&work);if !loaded.ok do return loaded
	case_load_work=work;return campaign_finish_prepared_case(g)
}

campaign_launch_case :: proc(g:^Game,index:int)->Validation {
	if index<0||index>=len(campaign_document.cases)||!campaign_case_unlocked(&campaign_document,&campaign_playthrough,index) do return {false,"campaign case is unavailable"}
	// Case selection lives outside the Authoring lifecycle modal. Preserve any
	// dirty source drafts before replacing the active case so the player can
	// continue without either data loss or an unactionable guard message.
	if active_authoring_ready {guard:=authoring_app_dirty_guard();if !guard.ok {preserved:=authoring_app_save_recovery();if !preserved.ok do return {false,fmt.tprintf("could not preserve authoring drafts before opening case: %s",preserved.message)}}}
	item:=campaign_document.cases[index]
	campaign_case_load_reap();case_load_work=Case_Load_Work{state=1,index=index};case_load_work.worker=thread.create(campaign_case_load_worker);if case_load_work.worker==nil do return {false,"could not start case loader"};thread.start(case_load_work.worker)
	g.case_loading_active=true;g.case_loading_index=index;g.case_loading_title=item.title
	g.map_loading_active=true;g.map_loading_target=.Investigate;g.map_loading_progress=0;g.map_loading_elapsed=0;g.map_loading_stage=0
	g.screen=.Loading
	return {true,"LOADING CASE"}
}

campaign_continue_selected :: proc(g:^Game)->Validation {if g.menu_return!=.Title {continue_from_title(g);return {true,"CASE RESUMED"}};selected:=campaign_playthrough.active_case;if selected<0||selected>=len(campaign_document.cases)||!campaign_case_unlocked(&campaign_document,&campaign_playthrough,selected) {selected=-1;for _,i in campaign_document.cases do if campaign_case_unlocked(&campaign_document,&campaign_playthrough,i) {selected=i;break}};return campaign_launch_case(g,selected)}

campaign_browser_viewport :: proc()->Rect {return {120,174,960,396}}
campaign_browser_content_height :: proc()->f32 {return max(0,f32(campaign_browser.count)*96-12)}
campaign_browser_card_logical_rect :: proc(index:int)->Rect {return {120,174+f32(index)*96,944,84}}
campaign_browser_card_rect :: proc(index:int)->Rect {box:=campaign_browser_card_logical_rect(index);box.y-=campaign_browser.scroll;return box}
campaign_browser_card_id :: proc(index:int)->ui.Gui_Id {return button_id(campaign_browser_card_logical_rect(index))}
campaign_browser_card_button :: proc(g:^Game,index:int)->bool {box:=campaign_browser_card_rect(index);return ui.gui_button_at(&g.gui,campaign_browser_card_id(index),{box.x,box.y,box.w,box.h},"",true)}
campaign_case_card_rect :: proc(slot:int)->Rect {return {120,174+f32(slot)*92,960,76}}
campaign_first_unlocked_on_page :: proc(page:int)->int {first:=page*4;last:=min(first+4,len(campaign_document.cases));for i in first..<last do if campaign_case_unlocked(&campaign_document,&campaign_playthrough,i) do return i;return -1}
campaign_focus_visible_selection :: proc(g:^Game) {
	// A focused card is the current choice regardless of input device. Keeping
	// this synchronization gamepad-only allowed mouse/keyboard focus and the
	// selected card to diverge, producing two competing accent outlines.
	if g.screen==.Campaign {for i in 0..<campaign_browser.count do if g.gui.focused==campaign_browser_card_id(i) {campaign_browser.selected=i;return}}
	if g.screen==.Campaign_Cases {first:=campaign_case_page*4;last:=min(first+4,len(campaign_document.cases));for i in first..<last do if campaign_case_unlocked(&campaign_document,&campaign_playthrough,i)&&g.gui.focused==button_id(campaign_case_card_rect(i-first)) {campaign_playthrough.active_case=i;return}}
}

pause_snapshot:Game
pause_snapshot_available:bool
pause_story_snapshot:Story_Runtime_Save
pause_story_snapshot_available:bool
pause_snapshot_content_identity:u64

pause_screen_available :: proc(screen:Screen)->bool {
	#partial switch screen {case .Introduction,.Exterior,.Investigate,.Dialogue,.Check,.Board,.Challenge,.Recreate,.Reveal_Prep,.Reveal:return true}
	return false
}

back_opens_pause :: proc(screen:Screen)->bool {
	// Back is also the contextual leave action during dialogue. Let the
	// dialogue handler consume it instead of opening the pause menu first.
	return screen!=.Dialogue&&pause_screen_available(screen)
}

pause_save_game :: proc(g:^Game)->bool {
	if pause_story_snapshot_available do story_runtime_save_destroy(&pause_story_snapshot)
	pause_snapshot=g^;pause_snapshot.screen=g.pause_return
	pause_story_snapshot_available=g.story_runtime!=nil
	if pause_story_snapshot_available {pause_story_snapshot=story_runtime_save(g.story_runtime);pause_snapshot_content_identity=g.story_runtime.compiled.content_identity}else do pause_snapshot_content_identity=0
	pause_snapshot_available=true
	_=save_campaign_playthrough()
	return true
}

pause_load_game :: proc(g:^Game)->bool {
	if !pause_snapshot_available do return false
	if pause_snapshot_content_identity!=0&&(g.story_runtime==nil||g.story_runtime.compiled.content_identity!=pause_snapshot_content_identity) do return false
	gui:=g.gui;running:=g.running;window_resized:=g.window_resized;gamepad:=g.gamepad;audio_stream:=g.audio_stream;vehicle_audio_stream:=g.vehicle_audio_stream
	g^=pause_snapshot
	g.gui=gui;g.running=running;g.window_resized=window_resized;g.gamepad=gamepad;g.audio_stream=audio_stream;g.vehicle_audio_stream=vehicle_audio_stream;g.input={};for &down in g.keys do down=false;for &down in g.pad_buttons do down=false
	if pause_story_snapshot_available&&g.story_runtime!=nil {_=story_runtime_restore(g.story_runtime,&pause_story_snapshot);g.story_state=&g.story_runtime.state;g.mystery_state=cast(^Mystery_State)story_runtime_capability_state(g.story_runtime,"mystery",MYSTERY_DOMAIN_VERSION)}
	g.focus_screen_initialized=false
	return true
}

update :: proc(g:^Game) {
		when ODIN_OS==.Darwin {command:=chicago_editor_menu_poll();if !player_package_mode&&command==1 {g.editor_mode=.Build;g.screen=.Investigate;g.move_target_active=false}else if !player_package_mode&&command==2 {g.editor_mode=.Graph;g.screen=.Investigate;g.move_target_active=false}else if command==3 do g.editor_mode=.None}
	g.animation_time+=FIXED_TIMESTEP
	update_case_pacing(g)
	update_shutter_motion(g,FIXED_TIMESTEP)
	// Movement state is resolved later in this tick by update_world. Sample the
	// character animations afterwards so locomotion responds to the velocity
	// that was actually applied, rather than the previous tick's velocity.
	defer update_character_animations(g,FIXED_TIMESTEP)
	ui.gui_begin_frame(&g.gui, ui.Input_State{
		window_width=WINDOW_WIDTH, window_height=WINDOW_HEIGHT,
		mouse_pos={g.input.mouse_pos.x,g.input.mouse_pos.y}, mouse_down=g.input.mouse_down,
		mouse_pressed=g.input.mouse_pressed, mouse_released=g.input.mouse_released,
		wheel_delta=g.input.mouse_wheel,
		pointer_enabled=g.active_device!=.Gamepad, active_device=g.active_device==.Gamepad?.Controller:.Mouse_Keyboard,
		nav_pressed_x=(g.input.right?f32(1):g.input.left?f32(-1):0),
		nav_pressed_y=(g.input.down?f32(1):g.input.up?f32(-1):0),
		accept_pressed=g.input.activate, back=g.input.back,
		text_input=g.input.text_input,text_input_len=g.input.text_input_len,clipboard_paste=g.input.clipboard_paste,clipboard_paste_len=g.input.clipboard_paste_len,key_shift=g.input.key_shift,key_ctrl=g.input.key_ctrl,key_super=g.input.key_super,key_enter=g.input.key_enter,key_escape=g.input.key_escape,key_backspace=g.input.key_backspace,key_delete=g.input.key_delete,key_home=g.input.key_home,key_end=g.input.key_end,key_left=g.input.key_left,key_right=g.input.key_right,key_a=g.input.key_a,key_x=g.input.key_x,key_v=g.input.key_v,key_c=g.input.key_c,
	})
	apply_pending_menu_overlay_focus(g)
	if menu_screen(g.screen)&&(!g.focus_screen_initialized||g.focus_screen!=g.screen||g.gui.focused==ui.GUI_ID_NONE) {g.gui.focused=button_id(menu_default_rect(g));g.focus_screen=g.screen;g.focus_screen_initialized=true}
	campaign_focus_visible_selection(g)
	defer ui.gui_end_frame(&g.gui)
	defer drag_cancel_if_screen_changed(g)
	if graph_state.playtesting&&g.input.back {_ = graph_end_playtest(g);g.input.back=false;return}
	if g.input.back&&back_opens_pause(g.screen)&&g.editor_mode==.None {g.pause_return=g.screen;g.pause_feedback="";g.screen=.Pause;g.input.back=false}
	if g.input.back&&g.screen==.Pause {g.screen=g.pause_return;g.input.back=false}
	if g.input.back&&editor_state.box_select_active {editor_state.box_select_active=false;g.input.back=false}
	if g.input.back&&g.screen==.Investigate&&g.editor_mode==.Build&&editor_state.object_rotate_active {editor_cancel_object_rotation();g.input.back=false}
	if g.input.back&&g.screen==.Game_Over do g.input.back=false
	if g.input.back&&g.screen==.Investigate&&g.editor_mode==.Build&&editor_state.exit_confirm_visible {editor_state.exit_confirm_visible=false;g.input.back=false}
	if g.input.back&&g.screen==.Investigate&&g.editor_mode==.Build&&editor_state.shortcut_help_visible {editor_state.shortcut_help_visible=false;g.input.back=false}
	if g.input.back&&g.screen==.Investigate&&g.editor_mode==.Build&&editor_state.view_menu_visible {editor_state.view_menu_visible=false;g.input.back=false}
	if g.input.back&&g.screen==.Investigate&&g.editor_mode==.Build&&g.build_tool==.Select&&!editor_state.search_active&&!editor_state.paint_eyedropper&&!editor_state.drag_active&&!editor_state.terrain_stroke_active&&!editor_state.foundation_rectangle_active&&editor_state.foundation_draw_count==0&&!editor_state.room_rectangle_active&&!editor_state.link_anchor_active&&editor_state.path_draw_count==0&&editor_state.water_draw_count==0&&editor_state.room_draw_count==0&&!g.build_has_anchor {authoring_app_request_build_exit(g);g.input.back=false}
	if g.input.back&&g.screen==.Authoring {g.screen=.Campaign_Action;g.input.back=false}
	if g.input.back {if g.screen==.Investigate&&g.editor_mode==.Build {if editor_state.search_active {editor_state.search_active=false}else if editor_state.paint_eyedropper {editor_state.paint_eyedropper=false}else if editor_state.drag_active {editor_cancel_drag()}else if editor_state.terrain_stroke_active {editor_cancel_terrain_stroke()}else if editor_state.foundation_rectangle_active {editor_state.foundation_rectangle_active=false}else if editor_state.foundation_draw_count>0 {editor_state.foundation_draw_count=0}else if editor_state.room_rectangle_active {editor_state.room_rectangle_active=false}else if editor_state.link_anchor_active {editor_state.link_anchor_active=false}else if editor_state.path_draw_count>0 {editor_state.path_draw_count=0}else if editor_state.water_draw_count>0 {editor_state.water_draw_count=0}else if editor_state.room_draw_count>0 {editor_state.room_draw_count=0}else if g.build_has_anchor {g.build_has_anchor=false;editor_state.wall_preview_active=false}else if g.build_tool!=.Select {g.build_tool=editor_escape_target(g.build_tool);editor_state.placement_active=false;editor_state.opening_active=false;editor_state.roof_hover_active=false}else{g.editor_mode=.None}}else if g.screen==.Dialogue {dialogue_back(g)}else if g.screen==.Options {g.screen=g.menu_return}else if g.screen==.Campaign {g.screen=.Title}else if g.screen==.Campaign_Cases {g.screen=.Campaign_Action}else if g.screen==.Campaign_Action&&!campaign_workspace.open {g.screen=.Campaign}else if g.screen==.Attributes {return_from_menu_overlay(g,g.menu_detail_return,g.menu_detail_return_focus)}else if g.screen==.Notebook {return_from_menu_overlay(g,g.notebook_return,g.notebook_return_focus)}else if g.screen==.Challenge {g.screen=.Board}else if g.screen==.Board {return_from_board(g)}else if g.screen==.Recreate {if g.interaction_active||g.interaction_mismatch {g.interaction_active=false;g.interaction_mismatch=false;g.screen=.Challenge}else{g.screen=.Board}}else if g.screen==.Diagnostics {g.screen=.Investigate}else if g.screen==.Reveal_Prep {g.screen=.Board}else if g.screen==.Check {g.screen=.Investigate}else if g.screen!=.Title&&g.screen!=.Investigate&&g.screen!=.Exterior {g.menu_return=g.screen;g.screen=.Campaign}}
	#partial switch g.screen {
	case .Title:
		if button(g,{410,400,380,48}) do g.screen=.Campaign
		if button(g,{410,456,380,48}) do continue_from_title(g)
		if button(g,{410,512,380,48}) {g.menu_return=.Title;g.screen=.Options}
		if button(g,{410,568,380,48}) {g.running=false}
	case .Campaign:
		viewport:=campaign_browser_viewport();ui.gui_scroll_begin_native(&g.gui,ui.Rect(viewport),campaign_browser_content_height(),&campaign_browser.scroll)
		for i in 0..<campaign_browser.count {if campaign_browser_card_button(g,i) {campaign_browser.selected=i;chosen:=campaign_choose(i);campaign_browser.feedback=chosen.message;if chosen.ok do g.screen=.Campaign_Action}}
		ui.gui_scroll_end(&g.gui)
		if button(g,{120,610,180,52}) {g.menu_return=.Campaign;g.screen=.Options}
		if button(g,{310,610,150,52}) do g.running=false
	case .Campaign_Action:
		if campaign_workspace.open {update_campaign_workspace(g);break}
		if button(g,{410,286,380,52}) {campaign_playthrough.active_case=campaign_first_unlocked_case(&campaign_document,&campaign_playthrough);campaign_case_page=max(campaign_playthrough.active_case,0)/4;g.screen=.Campaign_Cases}
		if campaign_can_continue()&&button(g,{410,354,380,52}) {continued:=campaign_continue_selected(g);campaign_workspace.feedback=continued.message}
		if !player_package_mode&&button(g,{410,438,380,42}) {campaign_workspace_begin();g.screen=.Campaign_Action}
		if button(g,{410,488,380,42}) do authoring_workspace_begin(g)
		if button(g,{410,570,380,48}) do g.screen=.Campaign
	case .Authoring:update_authoring_workspace(g)
	case .Campaign_Cases:
		first:=campaign_case_page*4;last:=min(first+4,len(campaign_document.cases));for i in first..<last {if campaign_case_unlocked(&campaign_document,&campaign_playthrough,i)&&button(g,campaign_case_card_rect(i-first)) do campaign_playthrough.active_case=i}
		pages:=max((len(campaign_document.cases)+3)/4,1);page_delta:=g.input.shoulder_left?-1:g.input.shoulder_right?1:0;if pages>1 {if button(g,{500,558,48,34}) do page_delta=-1;if button(g,{650,558,48,34}) do page_delta=1;if page_delta!=0 {campaign_case_page=(campaign_case_page+pages+page_delta)%pages;campaign_playthrough.active_case=campaign_first_unlocked_on_page(campaign_case_page);if campaign_playthrough.active_case>=0 do g.gui.focused=button_id(campaign_case_card_rect(campaign_playthrough.active_case-campaign_case_page*4))}}
		if button(g,{760,610,310,52}) {selected:=campaign_playthrough.active_case;if selected>=0 {ready:=campaign_playthrough_unused(&campaign_playthrough);if !ready do ready=campaign_create_playthrough(fmt.tprintf("Investigation %d",campaign_playthroughs.count+1));if ready {campaign_playthrough.active_case=selected;launched:=campaign_launch_case(g,selected);campaign_workspace.feedback=launched.message}else if campaign_playthroughs.count>=CAMPAIGN_MAX_PLAYTHROUGHS do campaign_workspace.feedback="INVESTIGATION SAVE LIMIT REACHED";else do campaign_workspace.feedback="COULD NOT SAVE A NEW INVESTIGATION"}}
		if button(g,{130,610,220,52}) do g.screen=.Campaign_Action
	case .Options:
		if button(g,{410,145,380,48}) {g.mute=!g.mute;persist_game_options(g)}
		if button(g,{410,245,380,48}) {g.aa_mode=Anti_Aliasing_Mode((int(g.aa_mode)+1)%len(Anti_Aliasing_Mode));g.aa_restart_required=true;persist_game_options(g)}
		if button(g,{410,345,380,48}) {g.lighting_quality=Lighting_Quality((int(g.lighting_quality)+1)%len(Lighting_Quality));persist_game_options(g)}
		if button(g,{410,445,380,48}) {g.guidance_mode=Guidance_Mode((int(g.guidance_mode)+1)%len(Guidance_Mode));g.tutorial.guidance=g.guidance_mode;persist_game_options(g)}
		if button(g,{410,630,380,42}) do g.screen=g.menu_return
	case .Pause:
		if button(g,{410,210,380,48}) do g.screen=g.pause_return
		if button(g,{410,266,380,48}) {g.pause_feedback=pause_save_game(g)?"GAME SAVED":"SAVE FAILED"}
		if button(g,{410,322,380,48}) {if !pause_load_game(g) do g.pause_feedback="NO SAVED GAME"}
		if button(g,{410,378,380,48}) {g.menu_return=.Pause;g.screen=.Options}
		if button(g,{410,434,380,48}) {g.menu_return=g.pause_return;g.screen=.Title}
		if button(g,{410,490,380,48}) do g.running=false
	case .Introduction: if button(g,{410,625,380,58}) do advance_introduction(g)
	case .Exterior: update_city(g)
	case .Investigate:
		if g.investigation_locked&&!overtime_active(g) {route_locked_investigation(g);break}
		if !player_package_mode&&g.keys[.F10]&&!g.build_key_latch&&!editor_state.object_rotate_active {if editor_state.playtesting do _=editor_end_playtest(g);else if g.editor_mode==.Build do authoring_app_request_build_exit(g);else{g.editor_mode=.Build;g.move_target_active=false}};g.build_key_latch=g.keys[.F10]
		if g.editor_mode==.Graph {update_graph_mode(g);break}
		if g.editor_mode==.Build {
			if editor_state.feedback_frames>0 do editor_state.feedback_frames-=1;else do editor_state.feedback=""
			if editor_state.marker_name_active {box:=editor_marker_name_rect();id:=button_id(box);g.gui.focused=id;ui.gui_text_edit_begin(&g.gui,id,editor_state.marker_name_count);ui.gui_text_edit_handle_mouse(&g.gui,id,editor_state.marker_name_buffer[:],editor_state.marker_name_count,ui.Rect(box),ui.Vec2{box.x+6,box.y+6});_=ui.gui_text_edit_process(&g.gui,id,editor_state.marker_name_buffer[:],&editor_state.marker_name_count);if g.input.key_enter do _=editor_commit_marker_name_edit();if g.input.key_escape do editor_cancel_marker_name_edit();if g.input.mouse_pressed&&!contains(box,g.input.mouse_pos) do _=editor_commit_marker_name_edit();break}
			if editor_state.exit_confirm_visible {if button(g,editor_exit_save_rect()) {saved:=authoring_app_save_all();house_plan.validation=saved.message;if saved.ok {editor_state.exit_confirm_visible=false;g.editor_mode=.None}else do editor_show_feedback("SAVE FAILED  ·  BUILD MODE REMAINS OPEN",true)};if button(g,editor_exit_autosave_rect()) {_=authoring_app_save_recovery();editor_state.exit_confirm_visible=false;g.editor_mode=.None};if button(g,editor_exit_cancel_rect()) do editor_state.exit_confirm_visible=false;g.input.mouse_pressed=false;g.input.mouse_released=false;g.input.activate=false;g.input.delete_selection=false;g.input.copy_selection=false;g.input.paste_selection=false;g.input.duplicate_selection=false}
			if editor_state.shortcut_help_visible {g.input.mouse_pressed=false;g.input.mouse_released=false;g.input.activate=false;g.input.delete_selection=false;g.input.copy_selection=false;g.input.paste_selection=false;g.input.duplicate_selection=false}
			editor_state.snap_suspended=g.keys[.LALT]||g.keys[.RALT]
			editor_update_build_camera(g)
			if g.input.mouse_pressed&&editor_begin_object_rotation(g) do g.input.mouse_pressed=false
			rotation_was_active:=editor_state.object_rotate_active
			editor_update_object_rotation(g)
			if rotation_was_active {g.input.mouse_pressed=false;g.input.mouse_released=false;g.input.activate=false;g.input.save_document=false;g.input.undo_document=false;g.input.redo_document=false;g.input.delete_selection=false;g.input.copy_selection=false;g.input.paste_selection=false;g.input.duplicate_selection=false;g.input.wall_view_cycle=false}
			editor_update_drag(g)
			editor_update_box_selection(g)
			editor_update_terrain_stroke(g)
			if g.build_tool==.Wall&&g.build_has_anchor {wx,wy,ok:=editor_mouse_ground(g,g.input.mouse_pos);if ok&&editor_viewport_contains(g.input.mouse_pos,g.build_tool) {editor_state.wall_preview_point=level_snap_point(&level_document,{wx,wy},true);editor_state.wall_preview_active=true}}else if g.build_tool!=.Wall {editor_state.wall_preview_active=false;g.build_has_anchor=false}
			if g.input.copy_selection do _=editor_copy_selection()
			if g.input.duplicate_selection {if editor_copy_selection() do _=editor_paste_selection({.5,.5},"DUPLICATED")}
			if g.input.paste_selection do _=editor_paste_selection()
			if g.input.delete_selection do _=editor_delete_selection_set()
			if editor_viewport_contains(g.input.mouse_pos,g.build_tool) {wx,wy,ok:=editor_mouse_ground(g,g.input.mouse_pos);if ok {editor_state.cursor_world={wx,wy};editor_state.cursor_world_valid=true}}
			if g.build_tool==.Plant {
				left_down,right_down:=g.keys[.COMMA],g.keys[.PERIOD]
				if left_down&&!editor_state.placement_rotate_left_latch do editor_state.placement_rotation=editor_placement_rotated(editor_state.placement_rotation,-1)
				if right_down&&!editor_state.placement_rotate_right_latch do editor_state.placement_rotation=editor_placement_rotated(editor_state.placement_rotation,1)
				editor_state.placement_rotate_left_latch=left_down;editor_state.placement_rotate_right_latch=right_down
				wx,wy,ground_ok:=editor_mouse_ground(g,g.input.mouse_pos);editor_state.placement_active=ground_ok&&editor_viewport_contains(g.input.mouse_pos,g.build_tool)
				if editor_state.placement_active&&g.input.mouse_wheel!=0 do editor_state.placement_rotation=editor_placement_rotated(editor_state.placement_rotation,editor_wheel_steps(g.input.mouse_wheel))
				if editor_state.placement_active {editor_state.placement_position=level_snap_point(&level_document,{wx,wy},true);editor_state.placement_support_id="";editor_state.placement_elevation=0;if placement_entry,found:=catalog_object_entry(editor_state.catalog_id);found do editor_state.placement_elevation=placement_entry.default_elevation;support_id,support_height,supported:=level_object_support_at(&level_document,editor_state.placement_position,editor_state.catalog_id);if supported {editor_state.placement_support_id=support_id;editor_state.placement_elevation=support_height};editor_state.placement_preview=level_preview_transaction(&level_document,Level_Command{kind=.Place_Object,a=editor_state.placement_position,c={editor_state.placement_elevation,0},value=editor_state.placement_rotation,material=editor_state.catalog_id,destination=editor_state.placement_support_id})}
			} else {editor_state.placement_active=false;editor_state.placement_rotate_left_latch=false;editor_state.placement_rotate_right_latch=false}
			editor_state.paint_hover_active=false
			if (g.build_tool==.Paint||g.build_tool==.Wall_Paint)&&editor_viewport_contains(g.input.mouse_pos,g.build_tool) {wx,wy,ground_ok:=editor_mouse_ground(g,g.input.mouse_pos);if ground_ok {hover:=level_pick(&level_document,{wx,wy});if hover.kind==.Room {editor_state.paint_hover=hover;editor_state.paint_hover_active=true}}}
			editor_state.opening_active=false
			if (g.build_tool==.Door||g.build_tool==.Window)&&editor_viewport_contains(g.input.mouse_pos,g.build_tool) {wx,wy,ground_ok:=editor_mouse_ground(g,g.input.mouse_pos);if ground_ok {host,host_ok:=level_pick_path_segment(&level_document,{wx,wy});kind:Level_Opening_Kind=g.build_tool==.Window?.Window:.Door;width,height,sill_height:=f32(0),f32(0),f32(0);if kind==.Window {width=editor_state.opening_width;height=editor_state.opening_height;sill_height=editor_state.opening_sill_height};if host_ok {command,command_ok:=level_opening_command_at(&level_document,host,{wx,wy},kind,width,height,sill_height,editor_state.window_style);if command_ok {if kind==.Door {command.destination=door_material_name(editor_state.door_material);command.points[2].x=f32(editor_state.door_style)};editor_state.opening_active=true;editor_state.opening_host=host;editor_state.opening_command=command;editor_state.opening_preview=level_preview_transaction(&level_document,command);editor_state.opening_position=editor_state.opening_preview.bounds_min}}}}
			editor_state.roof_hover_active=false
			if g.build_tool==.Roof&&editor_viewport_contains(g.input.mouse_pos,g.build_tool) {wx,wy,ground_ok:=editor_mouse_ground(g,g.input.mouse_pos);if ground_ok {picked:=level_pick(&level_document,{wx,wy});if picked.kind==.Room {editor_state.roof_hover=picked;editor_state.roof_hover_active=true;existing:=level_roof_for_room(&level_document,picked.entity_id);kind:=existing>=0?Level_Command_Kind.Set_Roof:.Create_Roof;id:="";if existing>=0 do id=level_document.roofs[existing].id;editor_state.roof_preview=level_preview_transaction(&level_document,Level_Command{kind=kind,entity_id=id,material=picked.entity_id,a={f32(editor_state.roof_style),editor_state.roof_ridge_angle},b={editor_state.roof_overhang,editor_state.roof_gutters?1:0},value=editor_state.roof_pitch})}}}
			if g.build_tool==.Stairs&&editor_state.link_anchor_active&&editor_viewport_contains(g.input.mouse_pos,g.build_tool) {wx,wy,ok:=editor_mouse_ground(g,g.input.mouse_pos);if ok {editor_state.link_finish=level_snap_point(&level_document,{wx,wy},true);editor_state.link_preview=level_preview_transaction(&level_document,Level_Command{kind=.Create_Vertical_Link,a=editor_state.link_anchor,b=editor_state.link_finish,c={f32(editor_state.link_kind),0},value=editor_state.link_width})}}
			if g.build_tool==.Room&&editor_state.room_draw_count>=3&&g.input.activate {command:=Level_Command{kind=.Create_Room_Polygon,material=editor_state.room_exterior?"flagstone":strings.to_lower(fmt.tprintf("%v",g.build_surface)),destination=editor_state.room_exterior?"patio":"",point_count=editor_state.room_draw_count};copy(command.points[:],editor_state.room_draw_points[:]);if level_commit_transaction(&level_document,command,editor_state.room_exterior?"Create polygon patio":"Create polygon room") do editor_state.room_draw_count=0}
			if g.build_tool==.Foundation&&editor_state.foundation_mode==.Polygon&&editor_state.foundation_draw_count>=3&&g.input.activate do _=editor_finish_foundation_polygon(g,g.keys[.LSHIFT]||g.keys[.RSHIFT])
			if g.build_tool==.Path&&editor_state.path_draw_count>=2&&g.input.activate {command:=Level_Command{kind=.Add_Path,c={f32(editor_state.path_kind),0},value=editor_state.path_width,point_count=editor_state.path_draw_count,material=editor_state.path_kind==.Road?"asphalt":"gravel"};copy(command.points[:],editor_state.path_draw_points[:]);if level_commit_transaction(&level_document,command,"Create terrain path") do editor_state.path_draw_count=0}
			if g.build_tool==.Water&&editor_state.water_draw_count>=3&&g.input.activate {command:=Level_Command{kind=.Create_Water,value=editor_state.water_elevation,point_count=editor_state.water_draw_count};copy(command.points[:],editor_state.water_draw_points[:]);if level_commit_transaction(&level_document,command,"Create pond") do editor_state.water_draw_count=0}
			if button(g,editor_top_close_rect()) do authoring_app_request_build_exit(g)
			if (level_document.dirty||graph_document.dirty)&&(button(g,editor_top_save_rect())||g.input.save_document) {saved:=authoring_app_save_all();house_plan.validation=saved.message;if saved.ok do editor_show_feedback("ALL DOCUMENTS SAVED");else do editor_show_feedback("SAVE FAILED  ·  CHECK FILE PERMISSIONS",true)}
			if level_history.undo_count>0&&(button(g,editor_top_undo_rect())||g.input.undo_document) {if level_undo(&level_document) do editor_show_feedback("UNDO RESTORED PREVIOUS STATE")}
			if level_history.redo_count>0&&(button(g,editor_top_redo_rect())||g.input.redo_document) {if level_redo(&level_document) do editor_show_feedback("REDO REAPPLIED CHANGE")}
			if button(g,editor_top_view_rect()) do editor_state.view_menu_visible=!editor_state.view_menu_visible
			if editor_state.view_menu_visible {for view in Editor_View_Mode {if button(g,editor_view_menu_rect(int(view))) {editor_set_view(g,view);editor_state.view_menu_visible=false;editor_show_feedback(fmt.tprintf("VIEW  ·  %s",editor_view_name(view)))}}}
			if g.input.wall_view_cycle do editor_cycle_view(g,(g.keys[.LSHIFT]||g.keys[.RSHIFT])?-1:1)
			if button(g,editor_top_validate_rect()) {checked:=level_validate(&level_document);house_plan.validation=checked.message;editor_state.diagnostics_visible=!editor_state.diagnostics_visible;if editor_state.diagnostics_visible {editor_state.selection_count=0;g.build_tool=.Select;if len(level_document.diagnostics)>0&&(editor_state.diagnostic_selected<0||editor_state.diagnostic_selected>=len(level_document.diagnostics)) do editor_state.diagnostic_selected=0}}
			if editor_state.diagnostics_visible {shown:=min(len(level_document.diagnostics),9);start:=editor_diagnostic_window_start(len(level_document.diagnostics),editor_state.diagnostic_selected,9);for row in 0..<shown do if button(g,editor_diagnostic_rect(row)) do _=editor_focus_diagnostic(g,start+row);if button(g,{1082,570,92,30}) do editor_state.diagnostics_visible=false}
			story_below:=level_story_below(&level_document,level_document.active_story);story_above:=level_story_above(&level_document,level_document.active_story)
			if story_below>=0&&button(g,editor_top_story_down_rect()) do _=editor_switch_story(g,story_below)
			if (story_above>=0||level_can_create_attic(&level_document))&&button(g,editor_top_story_up_rect()) {if story_above>=0 {_=editor_switch_story(g,story_above)}else{editor_reset_story_transients(g);if level_create_attic_story(&level_document) do editor_show_feedback("ATTIC CREATED  ·  ACTIVE STORY")}}
			if level_document.active_story>=0&&level_document.active_story<len(level_document.stories) {story:=level_document.stories[level_document.active_story];if button(g,editor_top_story_height_down_rect()) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Story_Height,entity_id=story.id,value=max(2.2,story.wall_height-.1)},"Lower floor height");if button(g,editor_top_story_height_up_rect()) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Story_Height,entity_id=story.id,value=min(6,story.wall_height+.1)},"Raise floor height")}
			if button(g,editor_top_play_rect()) do _=editor_begin_playtest(g)
			if button(g,editor_snap_rect()) do editor_state.snap_mode=Editor_Snap_Mode((int(editor_state.snap_mode)+1)%len(Editor_Snap_Mode))
			if button(g,editor_shortcut_help_rect()) do editor_state.shortcut_help_visible=true
			if editor_state.recovery_available&&button(g,editor_top_recovery_rect()) {restored:=level_load(LEVEL_AUTOSAVE_PATH,&level_document);if restored.ok {level_document.dirty=true;level_history={};editor_state.selection_count=0;editor_state.drag_active=false;editor_state.box_select_active=false;editor_state.room_draw_count=0;editor_state.foundation_draw_count=0;editor_state.path_draw_count=0;editor_state.water_draw_count=0;g.build_has_anchor=false;level_project_runtime(&level_document);editor_state.recovery_available=false;house_plan.validation="RECOVERY RESTORED";editor_show_feedback("AUTOSAVE RESTORED  ·  SAVE TO KEEP THIS VERSION")}else{house_plan.validation=restored.message;editor_show_feedback("RECOVERY FAILED  ·  AUTOSAVE COULD NOT BE READ",true)}}
			for mode,i in BUILD_MODE_GRID do if button(g,build_tool_grid_rect(i)) do editor_activate_build_mode(g,mode)
			active_mode:=build_mode_for_tool(g.build_tool)
			if active_mode==.Room {subtools:=[4]Build_Tool{.Room,.Wall,.Door,.Window};for tool,i in subtools do if button(g,build_subtool_rect(i)) do g.build_tool=tool;if g.build_tool==.Room {if button(g,build_subtool_rect(4)) {editor_state.room_mode=.Rectangle;editor_state.room_draw_count=0};if button(g,build_subtool_rect(5)) {editor_state.room_mode=.Polygon;editor_state.room_rectangle_active=false};if button(g,build_subtool_rect(6)) {editor_state.room_exterior=!editor_state.room_exterior}}} else if active_mode==.Paint {g.build_tool=.Paint;for target in Paint_Target {index:=int(target);if button(g,editor_paint_target_rect(index)) {editor_state.paint_target=target;editor_state.paint_eyedropper=false}};if button(g,editor_paint_eyedropper_rect()) do editor_state.paint_eyedropper=!editor_state.paint_eyedropper} else if active_mode==.Plant {subtools:=[2]Build_Tool{.Plant,.Light};for tool,i in subtools do if button(g,build_subtool_rect(i)) {g.build_tool=tool;if tool==.Light do editor_set_view(g,.Lighting)}}
			if g.build_tool==.Window {if button(g,editor_opening_parameter_rect(0)) do editor_state.opening_width=max(.4,editor_state.opening_width-.1);if button(g,editor_opening_parameter_rect(1)) do editor_state.opening_width=min(6,editor_state.opening_width+.1);if button(g,editor_opening_parameter_rect(2)) do editor_state.opening_height=max(.4,editor_state.opening_height-.1);if button(g,editor_opening_parameter_rect(3)) do editor_state.opening_height=min(4,editor_state.opening_height+.1);if button(g,Rect{370,188,38,26}) do editor_state.opening_sill_height=max(.2,editor_state.opening_sill_height-.1);if button(g,Rect{472,188,38,26}) do editor_state.opening_sill_height=min(2,editor_state.opening_sill_height+.1);if button(g,Rect{520,188,104,26}) do editor_state.window_style=Window_Style((int(editor_state.window_style)+1)%len(Window_Style))}
			if g.build_tool==.Door {if button(g,editor_opening_parameter_rect(0)) do editor_state.door_material=Door_Material((int(editor_state.door_material)+2)%3);if button(g,editor_opening_parameter_rect(1)) do editor_state.door_material=Door_Material((int(editor_state.door_material)+1)%3);if button(g,Rect{266,188,104,26}) do editor_state.door_style=Door_Style((int(editor_state.door_style)+1)%len(Door_Style))}
			if g.build_tool!=.Room {editor_state.room_draw_count=0;editor_state.room_rectangle_active=false}
			if g.build_tool!=.Foundation {editor_state.foundation_rectangle_active=false;editor_state.foundation_draw_count=0}
			if editor_catalog_visible(g.build_tool) do editor_update_catalog_ui(g)
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Object {object_index:=level_object_index(&level_document,editor_state.selection[0].entity_id);if object_index>=0 {entry,found:=catalog_object_entry(level_document.objects[object_index].catalog_id);if found&&entry.category=="foliage" {for color,i in FOLIAGE_COLOR_PALETTE {if button(g,editor_object_color_rect(0,i)) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Object_Color,entity_id=level_document.objects[object_index].id,destination="bark",color=color},"Set bark color");if button(g,editor_object_color_rect(1,i)) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Object_Color,entity_id=level_document.objects[object_index].id,destination="foliage",color=color},"Set foliage color")}}}}
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Object {object_index:=level_object_index(&level_document,editor_state.selection[0].entity_id);if object_index>=0 {object:=level_document.objects[object_index];if button(g,editor_object_numeric_rect(.Object_Height)) do editor_begin_numeric_edit(.Object_Height,object.elevation);if button(g,editor_object_numeric_rect(.Object_Angle)) do editor_begin_numeric_edit(.Object_Angle,object.rotation);if button(g,editor_object_numeric_rect(.Object_X)) do editor_begin_numeric_edit(.Object_X,object.position.x);if button(g,editor_object_numeric_rect(.Object_Y)) do editor_begin_numeric_edit(.Object_Y,object.position.y)}}
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Opening {opening_index:=level_opening_index(&level_document,editor_state.selection[0].entity_id);if opening_index>=0 {opening:=level_document.openings[opening_index];if button(g,editor_opening_numeric_rect(.Opening_Position)) do editor_begin_numeric_edit(.Opening_Position,opening.position*100);if button(g,editor_opening_numeric_rect(.Opening_Width)) do editor_begin_numeric_edit(.Opening_Width,opening.width);if button(g,editor_opening_numeric_rect(.Opening_Height)) do editor_begin_numeric_edit(.Opening_Height,opening.height);if opening.kind==.Window&&button(g,editor_opening_numeric_rect(.Opening_Sill)) do editor_begin_numeric_edit(.Opening_Sill,opening.sill_height)}}
			if editor_state.selection_count==1&&(editor_state.selection[0].kind==.Room||editor_state.selection[0].kind==.Edge||editor_state.selection[0].kind==.Vertex) {room_index:=level_room_index(&level_document,editor_state.selection[0].entity_id);if room_index>=0&&button(g,editor_compact_numeric_rect(.Room_Level)) do editor_begin_numeric_edit(.Room_Level,level_document.rooms[room_index].platform_height)}
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Foundation {index:=level_foundation_index(&level_document,editor_state.selection[0].entity_id);if index>=0&&button(g,editor_compact_numeric_rect(.Foundation_Measure)) {foundation:=level_document.foundations[index];editor_begin_numeric_edit(.Foundation_Measure,foundation.kind==.Raised?foundation.elevation:foundation.depth)}}
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Path {index:=level_path_index(&level_document,editor_state.selection[0].entity_id);if index>=0&&button(g,editor_compact_numeric_rect(.Path_Width)) do editor_begin_numeric_edit(.Path_Width,level_document.paths[index].width)}
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Water {index:=level_water_index(&level_document,editor_state.selection[0].entity_id);if index>=0&&button(g,editor_compact_numeric_rect(.Water_Surface)) do editor_begin_numeric_edit(.Water_Surface,level_document.waters[index].elevation)}
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Vertical_Link {index:=level_vertical_link_index(&level_document,editor_state.selection[0].entity_id);if index>=0&&button(g,editor_compact_numeric_rect(.Link_Width)) do editor_begin_numeric_edit(.Link_Width,level_document.vertical_links[index].width)}
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Roof {index:=level_roof_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {roof:=level_document.roofs[index];if button(g,editor_roof_numeric_rect(.Roof_Pitch)) do editor_begin_numeric_edit(.Roof_Pitch,roof.pitch);if button(g,editor_roof_numeric_rect(.Roof_Overhang)) do editor_begin_numeric_edit(.Roof_Overhang,roof.overhang);if button(g,editor_roof_numeric_rect(.Roof_Ridge)) do editor_begin_numeric_edit(.Roof_Ridge,roof.ridge_angle)}}
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Light {index:=level_light_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {light:=level_document.lights[index];if button(g,editor_light_numeric_rect(.Light_Range)) do editor_begin_numeric_edit(.Light_Range,light.range);if button(g,editor_light_numeric_rect(.Light_Intensity)) do editor_begin_numeric_edit(.Light_Intensity,light.intensity);if button(g,editor_light_numeric_rect(.Light_Height)) do editor_begin_numeric_edit(.Light_Height,light.elevation);if light.kind!=.Point&&button(g,editor_light_numeric_rect(.Light_Facing)) do editor_begin_numeric_edit(.Light_Facing,light.facing);if light.kind==.Spot&&button(g,editor_light_numeric_rect(.Light_Cone)) do editor_begin_numeric_edit(.Light_Cone,light.cone_angle)}}
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Marker {index:=level_marker_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {marker:=level_document.markers[index];if button(g,editor_marker_position_rect(.Marker_X)) do editor_begin_numeric_edit(.Marker_X,marker.position.x);if button(g,editor_marker_position_rect(.Marker_Y)) do editor_begin_numeric_edit(.Marker_Y,marker.position.y);if button(g,editor_marker_numeric_rect(.Marker_Radius)) do editor_begin_numeric_edit(.Marker_Radius,marker.radius);if button(g,editor_marker_numeric_rect(.Marker_Facing)) do editor_begin_numeric_edit(.Marker_Facing,marker.facing);if marker.kind==.Camera&&button(g,editor_marker_numeric_rect(.Marker_Height)) do editor_begin_numeric_edit(.Marker_Height,marker.camera_height)}}
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Marker {index:=level_marker_index(&level_document,editor_state.selection[0].entity_id);if index>=0&&button(g,editor_marker_name_rect()) do editor_begin_marker_name_edit(level_document.markers[index])}
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Marker&&button(g,editor_marker_duplicate_rect()) {step:=editor_state.snap_mode==.Fine?level_document.fine_snap:level_document.default_snap;if editor_copy_selection() do _=editor_paste_selection({step,step},"DUPLICATED MARKER")}
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Marker&&button(g,editor_marker_delete_rect()) do _=editor_delete_selection_set()
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Marker&&button(g,editor_marker_open_graph_rect()) {index:=level_marker_index(&level_document,editor_state.selection[0].entity_id);if index>=0 do _=editor_open_marker_in_graph(g,level_document.markers[index])}
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Light&&button(g,editor_light_duplicate_rect()) {step:=editor_state.snap_mode==.Fine?level_document.fine_snap:level_document.default_snap;if editor_copy_selection() do _=editor_paste_selection({step,step},"DUPLICATED LIGHT")}
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Light&&button(g,editor_light_delete_rect()) do _=editor_delete_selection_set()
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Light {index:=level_light_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {light:=level_document.lights[index];for color,i in LIGHT_COLOR_PALETTE {if button(g,editor_light_color_rect(light.kind,i)) {light.color=color;_=level_commit_transaction(&level_document,light_edit_command(light),"Set light color")}}}}
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Light {index:=level_light_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {light:=level_document.lights[index];if light.kind!=.Point {if button(g,editor_inspector_step_rect(386,-1)) {light.facing-=15;_=level_commit_transaction(&level_document,light_edit_command(light),"Rotate light left")};if button(g,editor_inspector_step_rect(386,1)) {light.facing+=15;_=level_commit_transaction(&level_document,light_edit_command(light),"Rotate light right")}};if light.kind==.Spot {if light.cone_angle>5&&button(g,editor_inspector_step_rect(432,-1)) {light.cone_angle=max(5,light.cone_angle-5);_=level_commit_transaction(&level_document,light_edit_command(light),"Narrow spotlight cone")};if light.cone_angle<160&&button(g,editor_inspector_step_rect(432,1)) {light.cone_angle=min(160,light.cone_angle+5);_=level_commit_transaction(&level_document,light_edit_command(light),"Widen spotlight cone")}}}}
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Object {object_index:=level_object_index(&level_document,editor_state.selection[0].entity_id);if object_index>=0 {object:=level_document.objects[object_index];if object.elevation>-5&&button(g,editor_compact_inspector_step_rect(174,-1)) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Object_Elevation,entity_id=object.id,value=max(-5,object.elevation-.25)},"Lower object");if object.elevation<20&&button(g,editor_compact_inspector_step_rect(174,1)) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Object_Elevation,entity_id=object.id,value=min(20,object.elevation+.25)},"Raise object");if button(g,editor_compact_inspector_step_rect(210,-1)) do _=level_commit_transaction(&level_document,Level_Command{kind=.Move_Object,entity_id=object.id,a=object.position,value=object.rotation-15},"Rotate object left");if button(g,editor_compact_inspector_step_rect(210,1)) do _=level_commit_transaction(&level_document,Level_Command{kind=.Move_Object,entity_id=object.id,a=object.position,value=object.rotation+15},"Rotate object right");step:=editor_state.snap_mode==.Fine?level_document.fine_snap:level_document.default_snap;if button(g,editor_compact_inspector_step_rect(246,-1)) do _=level_commit_transaction(&level_document,Level_Command{kind=.Move_Object,entity_id=object.id,a={object.position.x-step,object.position.y},value=object.rotation},"Move object left");if button(g,editor_compact_inspector_step_rect(246,1)) do _=level_commit_transaction(&level_document,Level_Command{kind=.Move_Object,entity_id=object.id,a={object.position.x+step,object.position.y},value=object.rotation},"Move object right");if button(g,editor_compact_inspector_step_rect(282,-1)) do _=level_commit_transaction(&level_document,Level_Command{kind=.Move_Object,entity_id=object.id,a={object.position.x,object.position.y-step},value=object.rotation},"Move object down");if button(g,editor_compact_inspector_step_rect(282,1)) do _=level_commit_transaction(&level_document,Level_Command{kind=.Move_Object,entity_id=object.id,a={object.position.x,object.position.y+step},value=object.rotation},"Move object up")}}
			if editor_state.selection_count==1&&(editor_state.selection[0].kind==.Room||editor_state.selection[0].kind==.Edge||editor_state.selection[0].kind==.Vertex) {room_index:=level_room_index(&level_document,editor_state.selection[0].entity_id);if room_index>=0 {room:=level_document.rooms[room_index];if room.platform_height>-5&&button(g,editor_compact_inspector_step_rect(174,-1)) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Platform,entity_id=room.id,value=max(-5,room.platform_height-.25)},"Lower room level");if room.platform_height<10&&button(g,editor_compact_inspector_step_rect(174,1)) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Platform,entity_id=room.id,value=min(10,room.platform_height+.25)},"Raise room level")}}
			if editor_state.selection_count==1&&(editor_state.selection[0].kind==.Room||editor_state.selection[0].kind==.Edge||editor_state.selection[0].kind==.Vertex) {room_index:=level_room_index(&level_document,editor_state.selection[0].entity_id);if room_index>=0 {room:=level_document.rooms[room_index];if button(g,editor_room_material_rect(false)) {g.build_tool=.Paint;editor_state.paint_target=.Floor;editor_state.catalog_category="materials";editor_state.catalog_id=room.floor_material;catalog_record_recent(&editor_state,room.floor_material)};if button(g,editor_room_material_rect(true)) {g.build_tool=.Paint;editor_state.paint_target=.Walls;editor_state.catalog_category="materials";editor_state.catalog_id=room.wall_material;catalog_record_recent(&editor_state,room.wall_material)}}}
			if editor_state.selection_count==1&&(editor_state.selection[0].kind==.Room||editor_state.selection[0].kind==.Edge||editor_state.selection[0].kind==.Vertex) {room_index:=level_room_index(&level_document,editor_state.selection[0].entity_id);if room_index>=0 {room_id:=level_document.rooms[room_index].id;for color,i in ROOM_TINT_PALETTE {if button(g,editor_room_tint_rect(false,i)) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Room_Tint,entity_id=room_id,destination="floor",color=color},"Tint floor covering");if button(g,editor_room_tint_rect(true,i)) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Room_Tint,entity_id=room_id,destination="walls",color=color},"Tint wall covering")}}}
			if editor_state.selection_count==1&&(editor_state.selection[0].kind==.Room||editor_state.selection[0].kind==.Edge||editor_state.selection[0].kind==.Vertex)&&button(g,editor_room_roof_rect()) {room_id:=editor_state.selection[0].entity_id;roof_index:=level_roof_for_room(&level_document,room_id);if roof_index>=0 {roof:=level_document.roofs[roof_index];editor_state.roof_style=roof.style;editor_state.roof_pitch=roof.pitch;editor_state.roof_overhang=roof.overhang;editor_state.roof_ridge_angle=roof.ridge_angle;editor_state.roof_gutters=roof.gutters};g.build_tool=.Roof;editor_state.roof_hover={.Room,room_id,-1};editor_state.roof_hover_active=true;kind:=roof_index>=0?Level_Command_Kind.Set_Roof:.Create_Roof;roof_id:=roof_index>=0?level_document.roofs[roof_index].id:"";editor_state.roof_preview=level_preview_transaction(&level_document,Level_Command{kind=kind,entity_id=roof_id,material=room_id,a={f32(editor_state.roof_style),editor_state.roof_ridge_angle},b={editor_state.roof_overhang,editor_state.roof_gutters?1:0},value=editor_state.roof_pitch})}
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Roof&&button(g,editor_roof_edit_rect()) do _=editor_begin_roof_edit(g,editor_state.selection[0].entity_id)
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Roof&&button(g,editor_roof_delete_rect())&&level_delete_selection(&level_document,editor_state.selection[0]) do editor_state.selection_count=0
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Foundation {foundation_index:=level_foundation_index(&level_document,editor_state.selection[0].entity_id);if foundation_index>=0 {foundation:=level_document.foundations[foundation_index];down:=editor_compact_inspector_step_rect(198,-1);up:=editor_compact_inspector_step_rect(198,1);step:=foundation.kind==.Slab?f32(.05):f32(.25);minimum:=foundation.kind==.Basement?f32(1.8):foundation.kind==.Raised?f32(.25):f32(.1);maximum:=foundation.kind==.Basement?f32(6):foundation.kind==.Raised?f32(3):f32(1);measure:=foundation.kind==.Raised?foundation.elevation:foundation.depth;if measure>minimum&&button(g,down) {next:=max(minimum,measure-step);command:=Level_Command{kind=.Set_Foundation,entity_id=foundation.id,value=foundation.elevation,c={f32(foundation.kind),foundation.depth}};if foundation.kind==.Raised do command.value=next;else do command.c.y=next;_=level_commit_transaction(&level_document,command,"Decrease foundation measure")};if measure<maximum&&button(g,up) {next:=min(maximum,measure+step);command:=Level_Command{kind=.Set_Foundation,entity_id=foundation.id,value=foundation.elevation,c={f32(foundation.kind),foundation.depth}};if foundation.kind==.Raised do command.value=next;else do command.c.y=next;_=level_commit_transaction(&level_document,command,"Increase foundation measure")}}}
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Path {path_index:=level_path_index(&level_document,editor_state.selection[0].entity_id);if path_index>=0 {path:=level_document.paths[path_index];down:=editor_compact_inspector_step_rect(198,-1);up:=editor_compact_inspector_step_rect(198,1);step:=path.kind==.Wall?f32(.05):f32(.2);minimum:=path.kind==.Wall?f32(.1):f32(.2);maximum:=path.kind==.Wall?f32(1):f32(8);if path.width>minimum&&button(g,down) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Path,entity_id=path.id,value=max(minimum,path.width-step)},"Narrow path");if path.width<maximum&&button(g,up) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Path,entity_id=path.id,value=min(maximum,path.width+step)},"Widen path")}}
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Water {water_index:=level_water_index(&level_document,editor_state.selection[0].entity_id);if water_index>=0 {water:=level_document.waters[water_index];if water.elevation> -5&&button(g,editor_compact_inspector_step_rect(198,-1)) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Water,entity_id=water.id,value=max(-5,water.elevation-.25)},"Lower water surface");if water.elevation<5&&button(g,editor_compact_inspector_step_rect(198,1)) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Water,entity_id=water.id,value=min(5,water.elevation+.25)},"Raise water surface")}}
			if editor_state.selection_count==1&&editor_state.selection[0].kind==.Vertical_Link {link_index:=level_vertical_link_index(&level_document,editor_state.selection[0].entity_id);if link_index>=0 {link:=level_document.vertical_links[link_index];if link.width>.6&&button(g,editor_compact_inspector_step_rect(198,-1)) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Vertical_Link,entity_id=link.id,value=max(.6,link.width-.1)},"Narrow vertical link");if link.width<3&&button(g,editor_compact_inspector_step_rect(198,1)) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Vertical_Link,entity_id=link.id,value=min(3,link.width+.1)},"Widen vertical link")}}
			if g.build_tool==.Roof {if button(g,editor_roof_style_rect()) do editor_state.roof_style=Level_Roof_Style((int(editor_state.roof_style)+1)%len(Level_Roof_Style));if button(g,editor_roof_parameter_rect(0)) do editor_state.roof_pitch=max(5,editor_state.roof_pitch-5);if button(g,editor_roof_parameter_rect(1)) do editor_state.roof_pitch=min(70,editor_state.roof_pitch+5);if button(g,editor_roof_parameter_rect(2)) do editor_state.roof_overhang=max(0,editor_state.roof_overhang-.1);if button(g,editor_roof_parameter_rect(3)) do editor_state.roof_overhang=min(2,editor_state.roof_overhang+.1);if button(g,editor_roof_parameter_rect(4)) do editor_state.roof_ridge_angle+=15;if button(g,editor_roof_gutters_rect()) do editor_state.roof_gutters=!editor_state.roof_gutters;if button(g,editor_roof_apply_rect()) do _=editor_apply_roof_preview()}
			if g.build_tool==.Stairs {if button(g,editor_link_kind_rect()) do editor_state.link_kind=Level_Vertical_Link_Kind((int(editor_state.link_kind)+1)%len(Level_Vertical_Link_Kind));if button(g,editor_link_width_rect(0)) do editor_state.link_width=max(.6,editor_state.link_width-.1);if button(g,editor_link_width_rect(1)) do editor_state.link_width=min(3,editor_state.link_width+.1)}
			if g.build_tool==.Path {if button(g,editor_link_kind_rect()) do editor_state.path_kind=editor_state.path_kind==.Road?.Footpath:.Road;if button(g,editor_link_width_rect(0)) do editor_state.path_width=max(.2,editor_state.path_width-.2);if button(g,editor_link_width_rect(1)) do editor_state.path_width=min(8,editor_state.path_width+.2)}
			if g.build_tool==.Water {if button(g,editor_water_height_rect(0)) do editor_state.water_elevation-=.25;if button(g,editor_water_height_rect(1)) do editor_state.water_elevation+=.25}
			if g.build_tool==.Foundation {for kind in Level_Foundation_Kind {index:=int(kind);if button(g,editor_foundation_kind_rect(index)) {editor_state.foundation_kind=kind;if kind==.Raised do editor_state.foundation_elevation=max(editor_state.foundation_elevation,.5);else do editor_state.foundation_elevation=0}};if button(g,editor_foundation_measure_rect(0)) {if editor_state.foundation_kind==.Raised do editor_state.foundation_elevation=max(.25,editor_state.foundation_elevation-.25);else if editor_state.foundation_kind==.Basement do editor_state.foundation_depth=max(1.8,editor_state.foundation_depth-.25);else do editor_state.foundation_depth=max(.1,editor_state.foundation_depth-.05)};if button(g,editor_foundation_measure_rect(1)) {if editor_state.foundation_kind==.Raised do editor_state.foundation_elevation=min(3,editor_state.foundation_elevation+.25);else if editor_state.foundation_kind==.Basement do editor_state.foundation_depth=min(6,editor_state.foundation_depth+.25);else do editor_state.foundation_depth=min(1,editor_state.foundation_depth+.05)};if button(g,editor_foundation_mode_rect(0)) {editor_state.foundation_mode=.Rectangle;editor_state.foundation_draw_count=0};if button(g,editor_foundation_mode_rect(1)) {editor_state.foundation_mode=.Polygon;editor_state.foundation_rectangle_active=false};if editor_state.foundation_kind==.Basement do editor_state.foundation_depth=max(editor_state.foundation_depth,2.5);if editor_state.foundation_kind==.Raised do editor_state.foundation_elevation=max(editor_state.foundation_elevation,.25)}
			if g.build_tool==.Marker {for kind in Level_Marker_Kind {index:=int(kind);if button(g,editor_marker_kind_rect(index)) do editor_state.marker_kind=kind};if button(g,editor_marker_parameter_rect(0)) do editor_state.marker_radius=max(.1,editor_state.marker_radius-.1);if button(g,editor_marker_parameter_rect(1)) do editor_state.marker_radius=min(12,editor_state.marker_radius+.1);if button(g,editor_marker_parameter_rect(2)) do editor_state.marker_facing-=15;if button(g,editor_marker_parameter_rect(3)) do editor_state.marker_facing+=15}
			if g.build_tool==.Light {if button(g,editor_light_kind_rect()) do editor_state.light_kind=Level_Light_Kind((int(editor_state.light_kind)+1)%len(Level_Light_Kind));if button(g,editor_light_parameter_rect(0)) do editor_state.light_range=max(.5,editor_state.light_range-.5);if button(g,editor_light_parameter_rect(1)) do editor_state.light_range=min(40,editor_state.light_range+.5);if button(g,editor_light_parameter_rect(2)) do editor_state.light_intensity=max(.1,editor_state.light_intensity-.1);if button(g,editor_light_parameter_rect(3)) do editor_state.light_intensity=min(100,editor_state.light_intensity+.1)}
			if g.build_tool==.Terrain {
				for mode in Terrain_Brush_Mode {index:=int(mode);if button(g,editor_terrain_mode_rect(index)) do editor_state.terrain_mode=mode}
				if button(g,editor_terrain_parameter_rect(0)) do editor_state.terrain_radius=max(.5,editor_state.terrain_radius-.5)
				if button(g,editor_terrain_parameter_rect(1)) do editor_state.terrain_radius=min(8,editor_state.terrain_radius+.5)
				if button(g,editor_terrain_parameter_rect(2)) do editor_state.terrain_strength=max(.25,editor_state.terrain_strength-.25)
				if button(g,editor_terrain_parameter_rect(3)) do editor_state.terrain_strength=min(2,editor_state.terrain_strength+.25)
			} else if editor_state.selection_count>0 {
				selected:=editor_state.selection[0];left,left_ok:=editor_selection_action_rect(g,0);right,_:=editor_selection_action_rect(g,1);duplicate,_:=editor_selection_action_rect(g,2);lower,_:=editor_selection_action_rect(g,3);raise,_:=editor_selection_action_rect(g,4);remove,_:=editor_selection_action_rect(g,5);seventh,_:=editor_selection_action_rect(g,6);eighth,_:=editor_selection_action_rect(g,7);ninth,_:=editor_selection_action_rect(g,8);tenth,_:=editor_selection_action_rect(g,9)
				if left_ok&&(selected.kind==.Room||selected.kind==.Object) {if selected.kind==.Room {if button(g,left) do _=level_commit_transaction(&level_document,Level_Command{kind=.Rotate_Room,entity_id=selected.entity_id,value=-15},"Rotate room left");if button(g,right) do _=level_commit_transaction(&level_document,Level_Command{kind=.Rotate_Room,entity_id=selected.entity_id,value=15},"Rotate room right");if button(g,duplicate) {copy_id:=level_next_id("room_copy",level_document.revision);if level_commit_transaction(&level_document,Level_Command{kind=.Duplicate_Room,entity_id=selected.entity_id,a={level_document.default_snap,level_document.default_snap},material=copy_id},"Duplicate room") {editor_state.selection[0]={.Room,copy_id,-1}}};room_index:=level_room_index(&level_document,selected.entity_id);if room_index>=0 {height:=level_document.rooms[room_index].platform_height;if button(g,lower) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Platform,entity_id=selected.entity_id,value=height-.25},"Lower platform");if button(g,raise) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Platform,entity_id=selected.entity_id,value=height+.25},"Raise platform")}} else {object_index:=level_object_index(&level_document,selected.entity_id);if object_index>=0 {object:=level_document.objects[object_index];if button(g,left) do _=level_commit_transaction(&level_document,Level_Command{kind=.Move_Object,entity_id=selected.entity_id,a=object.position,value=object.rotation-15},"Rotate object left");if button(g,right) do _=level_commit_transaction(&level_document,Level_Command{kind=.Move_Object,entity_id=selected.entity_id,a=object.position,value=object.rotation+15},"Rotate object right");if button(g,duplicate) {copy_id:=level_next_id("object_copy",level_document.revision);if level_commit_transaction(&level_document,Level_Command{kind=.Duplicate_Object,entity_id=selected.entity_id,a={level_document.default_snap,level_document.default_snap},material=copy_id},"Duplicate object") {editor_state.selection[0]={.Object,copy_id,-1}}};if button(g,lower) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Object_Elevation,entity_id=selected.entity_id,value=object.elevation-.25},"Lower object");if button(g,raise) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Object_Elevation,entity_id=selected.entity_id,value=object.elevation+.25},"Raise object")}};if button(g,remove)&&level_delete_selection(&level_document,selected) do editor_state.selection_count=0
				} else if left_ok&&selected.kind==.Opening {opening_index:=level_opening_index(&level_document,selected.entity_id);if opening_index>=0 {opening:=level_document.openings[opening_index];if opening.kind==.Window {if opening.width>.4&&button(g,left) {command,_:=level_opening_resize_command(&level_document,selected.entity_id,-.1,0);_=level_commit_transaction(&level_document,command,"Narrow window")};if opening.width<6&&button(g,right) {command,_:=level_opening_resize_command(&level_document,selected.entity_id,.1,0);_=level_commit_transaction(&level_document,command,"Widen window")};if opening.height>.4&&button(g,duplicate) {command,_:=level_opening_resize_command(&level_document,selected.entity_id,0,-.1);_=level_commit_transaction(&level_document,command,"Shorten window")};if opening.height<4&&button(g,lower) {command,_:=level_opening_resize_command(&level_document,selected.entity_id,0,.1);_=level_commit_transaction(&level_document,command,"Raise window head")};if opening.sill_height>.2&&button(g,raise) {command,_:=level_window_sill_command(&level_document,selected.entity_id,-.1);_=level_commit_transaction(&level_document,command,"Lower window sill")};if opening.sill_height<2&&button(g,remove) {command,_:=level_window_sill_command(&level_document,selected.entity_id,.1);_=level_commit_transaction(&level_document,command,"Raise window sill")};if button(g,eighth) {next:=Window_Style((int(opening.window_style)+1)%len(Window_Style));command,_:=level_window_style_command(&level_document,selected.entity_id,next);_=level_commit_transaction(&level_document,command,"Change window style")};if button(g,ninth) {command,_:=level_window_flip_command(&level_document,selected.entity_id);_=level_commit_transaction(&level_document,command,"Flip window room side")};if opening.window_style==.Casement&&button(g,tenth) {command,_:=level_window_handing_command(&level_document,selected.entity_id);_=level_commit_transaction(&level_document,command,"Change casement handing")};if button(g,seventh)&&level_delete_selection(&level_document,selected) do editor_state.selection_count=0}else{if button(g,left) {next:=Door_Style((int(opening.door_style)+1)%len(Door_Style));command,_:=level_door_style_command(&level_document,selected.entity_id,next);_=level_commit_transaction(&level_document,command,"Change door style")};if button(g,right)&&level_delete_selection(&level_document,selected) do editor_state.selection_count=0}}
				} else if left_ok&&selected.kind==.Edge {room_index:=level_room_index(&level_document,selected.entity_id);if room_index>=0&&selected.sub_index>=0&&selected.sub_index<len(level_document.rooms[room_index].points) {a:=level_document.rooms[room_index].points[selected.sub_index];b:=level_document.rooms[room_index].points[(selected.sub_index+1)%len(level_document.rooms[room_index].points)];if button(g,left)&&level_commit_transaction(&level_document,Level_Command{kind=.Insert_Room_Vertex,entity_id=selected.entity_id,a={(a.x+b.x)*.5,(a.y+b.y)*.5},value=f32(selected.sub_index)},"Insert room corner") do editor_state.selection[0]={.Vertex,selected.entity_id,selected.sub_index+1}}
				} else if left_ok&&selected.kind==.Vertex {if button(g,left)&&level_commit_transaction(&level_document,Level_Command{kind=.Remove_Room_Vertex,entity_id=selected.entity_id,value=f32(selected.sub_index)},"Remove room corner") do editor_state.selection[0]={.Room,selected.entity_id,-1}}
			}
			if g.build_tool!=.Terrain&&editor_state.selection_count>0&&editor_state.selection[0].kind==.Object {object_index:=level_object_index(&level_document,editor_state.selection[0].entity_id);if object_index>=0 {object:=level_document.objects[object_index];entry,found:=catalog_object_entry(object.catalog_id);if found&&entry.emits_light {state_button,_:=editor_selection_action_rect(g,6);power_button,_:=editor_selection_action_rect(g,7);if button(g,state_button) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Interaction,entity_id=object.id,interaction=.Toggle,interaction_prompt=object.interaction_prompt,interaction_range=max(object.interaction_range,f32(1.8)),initially_active=!object.initially_active,locked=false,powered=object.powered},"Change initial appliance state");if button(g,power_button) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Interaction,entity_id=object.id,interaction=.Toggle,interaction_prompt=object.interaction_prompt,interaction_range=max(object.interaction_range,f32(1.8)),initially_active=object.initially_active,locked=false,powered=!object.powered},"Change appliance power")}}}
			if g.build_tool!=.Terrain&&editor_state.selection_count>0&&editor_state.selection[0].kind==.Opening {opening_index:=level_opening_index(&level_document,editor_state.selection[0].entity_id);if opening_index>=0 {opening:=level_document.openings[opening_index];if opening.kind==.Door {initial_button,_:=editor_selection_action_rect(g,2);lock_button,_:=editor_selection_action_rect(g,3);if button(g,initial_button) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Interaction,entity_id=opening.id,interaction=.Door,interaction_prompt=opening.interaction_prompt,interaction_range=opening.interaction_range,initially_active=!opening.initially_active,locked=opening.locked,powered=true},"Change initial door state");if button(g,lock_button) do _=level_commit_transaction(&level_document,Level_Command{kind=.Set_Interaction,entity_id=opening.id,interaction=.Door,interaction_prompt=opening.interaction_prompt,interaction_range=opening.interaction_range,initially_active=opening.initially_active,locked=!opening.locked,powered=true},"Change door lock")}}}
			if g.build_tool!=.Terrain&&editor_state.selection_count>0&&editor_state.selection[0].kind==.Foundation {shell,ok:=editor_selection_action_rect(g,0);remove,_:=editor_selection_action_rect(g,1);if ok&&button(g,shell) do _=editor_create_room_from_foundation(g,&level_document,editor_state.selection[0].entity_id);if editor_state.selection_count>0&&editor_state.selection[0].kind==.Foundation&&button(g,remove)&&level_delete_selection(&level_document,editor_state.selection[0]) do editor_state.selection_count=0}
			if g.build_tool!=.Terrain&&editor_state.selection_count>0&&editor_state.selection[0].kind==.Path {remove,ok:=editor_selection_action_rect(g,0);if ok&&button(g,remove)&&level_delete_selection(&level_document,editor_state.selection[0]) do editor_state.selection_count=0}
			if g.build_tool!=.Terrain&&editor_state.selection_count>0&&editor_state.selection[0].kind==.Water {remove,ok:=editor_selection_action_rect(g,0);if ok&&button(g,remove)&&level_delete_selection(&level_document,editor_state.selection[0]) do editor_state.selection_count=0}
			if g.build_tool!=.Terrain&&editor_state.selection_count>0&&editor_state.selection[0].kind==.Vertical_Link {remove,ok:=editor_selection_action_rect(g,0);if ok&&button(g,remove)&&level_delete_selection(&level_document,editor_state.selection[0]) do editor_state.selection_count=0}
			if editor_state.selection_count>1 {if button(g,editor_multi_action_rect(0)) do _=editor_align_selection(true);if button(g,editor_multi_action_rect(1)) do _=editor_align_selection(false);if button(g,editor_multi_action_rect(2)) do _=editor_copy_selection();if button(g,editor_multi_action_rect(3)) {if editor_copy_selection() do _=editor_paste_selection({.5,.5},"DUPLICATED")};if button(g,editor_multi_action_rect(4)) do _=editor_delete_selection_set();if editor_state.selection_count>2 {if button(g,editor_multi_action_rect(5)) do _=editor_distribute_selection(true);if button(g,editor_multi_action_rect(6)) do _=editor_distribute_selection(false)}}
			if editor_state.selection_count==2&&editor_state.selection[0].kind==.Room&&editor_state.selection[1].kind==.Room {merge_command:=level_merge_room_command(editor_state.selection[0].entity_id,editor_state.selection[1].entity_id);if level_preview_transaction(&level_document,merge_command).state!=.Blocked&&button(g,{778,608,36,28})&&level_commit_transaction(&level_document,merge_command,"Merge rooms") {editor_state.selection[0]={.Room,merge_command.entity_id,-1};editor_state.selection_count=1}}
			if g.build_tool!=.Terrain&&editor_state.selection_count>0&&editor_state.selection[0].kind==.Marker {remove,ok:=editor_selection_action_rect(g,0);if ok&&button(g,remove)&&level_delete_selection(&level_document,editor_state.selection[0]) do editor_state.selection_count=0}
			if editor_state.selection_count>0&&editor_state.selection[0].kind==.Marker {index:=level_marker_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {marker:=level_document.markers[index];if button(g,editor_inspector_step_rect(178,-1)) {if marker.reference!=""||marker.destination!="" do editor_show_feedback("CLEAR THE MARKER BINDING BEFORE CHANGING TYPE",true);else{marker.kind=Level_Marker_Kind((int(marker.kind)-1+len(Level_Marker_Kind))%len(Level_Marker_Kind));_=level_commit_transaction(&level_document,marker_edit_command(marker),"Change marker type")}};if button(g,editor_inspector_step_rect(178,1)) {if marker.reference!=""||marker.destination!="" do editor_show_feedback("CLEAR THE MARKER BINDING BEFORE CHANGING TYPE",true);else{marker.kind=Level_Marker_Kind((int(marker.kind)+1)%len(Level_Marker_Kind));_=level_commit_transaction(&level_document,marker_edit_command(marker),"Change marker type")}};if level_marker_uses_binding(marker.kind)&&button(g,editor_inspector_step_rect(248,-1)) {binding:=marker_binding_next(g,marker,-1);if marker.kind==.Transition do marker.destination=binding;else do marker.reference=binding;_=level_commit_transaction(&level_document,marker_edit_command(marker),"Bind marker")};if level_marker_uses_binding(marker.kind)&&button(g,editor_inspector_clear_rect(248)) {marker.reference="";marker.destination="";_=level_commit_transaction(&level_document,marker_edit_command(marker),"Clear marker binding")};if level_marker_uses_binding(marker.kind)&&button(g,editor_inspector_step_rect(248,1)) {binding:=marker_binding_next(g,marker,1);if marker.kind==.Transition do marker.destination=binding;else do marker.reference=binding;_=level_commit_transaction(&level_document,marker_edit_command(marker),"Bind marker")};if marker.radius>.1&&button(g,editor_inspector_step_rect(318,-1)) {marker.radius=max(.1,marker.radius-.1);_=level_commit_transaction(&level_document,marker_edit_command(marker),"Reduce marker radius")};if marker.radius<12&&button(g,editor_inspector_step_rect(318,1)) {marker.radius=min(12,marker.radius+.1);_=level_commit_transaction(&level_document,marker_edit_command(marker),"Increase marker radius")};if button(g,editor_inspector_step_rect(354,-1)) {marker.facing-=15;_=level_commit_transaction(&level_document,marker_edit_command(marker),"Rotate marker")};if button(g,editor_inspector_step_rect(354,1)) {marker.facing+=15;_=level_commit_transaction(&level_document,marker_edit_command(marker),"Rotate marker")};if marker.kind==.Camera {if marker.camera_height>.1&&button(g,editor_inspector_step_rect(390,-1)) {marker.camera_height=max(.1,marker.camera_height-.1);_=level_commit_transaction(&level_document,marker_edit_command(marker),"Lower camera marker")};if button(g,editor_inspector_step_rect(390,1)) {marker.camera_height+=.1;_=level_commit_transaction(&level_document,marker_edit_command(marker),"Raise camera marker")}}}}
			if editor_state.selection_count>0&&editor_state.selection[0].kind==.Light {index:=level_light_index(&level_document,editor_state.selection[0].entity_id);if index>=0 {light:=level_document.lights[index];if button(g,editor_inspector_step_rect(178,-1)) {light.kind=Level_Light_Kind((int(light.kind)-1+len(Level_Light_Kind))%len(Level_Light_Kind));_=level_commit_transaction(&level_document,light_edit_command(light),"Change light type")};if button(g,editor_inspector_step_rect(178,1)) {light.kind=Level_Light_Kind((int(light.kind)+1)%len(Level_Light_Kind));_=level_commit_transaction(&level_document,light_edit_command(light),"Change light type")};if light.range>.5&&button(g,editor_inspector_step_rect(248,-1)) {light.range=max(.5,light.range-.5);_=level_commit_transaction(&level_document,light_edit_command(light),"Reduce light range")};if light.range<40&&button(g,editor_inspector_step_rect(248,1)) {light.range=min(40,light.range+.5);_=level_commit_transaction(&level_document,light_edit_command(light),"Increase light range")};if light.intensity>.1&&button(g,editor_inspector_step_rect(294,-1)) {light.intensity=max(.1,light.intensity-.1);_=level_commit_transaction(&level_document,light_edit_command(light),"Reduce light intensity")};if light.intensity<100&&button(g,editor_inspector_step_rect(294,1)) {light.intensity=min(100,light.intensity+.1);_=level_commit_transaction(&level_document,light_edit_command(light),"Increase light intensity")};if light.elevation>0&&button(g,editor_inspector_step_rect(340,-1)) {light.elevation=max(0,light.elevation-.1);_=level_commit_transaction(&level_document,light_edit_command(light),"Lower light")};if light.elevation<20&&button(g,editor_inspector_step_rect(340,1)) {light.elevation=min(20,light.elevation+.1);_=level_commit_transaction(&level_document,light_edit_command(light),"Raise light")}}}
			// Only the unobscured center is a world viewport. UI panels must never
			// leak clicks into placement or selection transactions behind them.
			if g.input.mouse_pressed&&g.build_tool==.Roof&&editor_state.roof_hover_active&&editor_state.roof_preview.state!=.Blocked&&editor_viewport_contains(g.input.mouse_pos,g.build_tool) do _=editor_apply_roof_preview()
			if g.input.mouse_pressed&&g.build_tool==.Stairs&&editor_viewport_contains(g.input.mouse_pos,g.build_tool) {wx,wy,ok:=editor_mouse_ground(g,g.input.mouse_pos);if ok {point:=level_snap_point(&level_document,{wx,wy},true);if !editor_state.link_anchor_active {editor_state.link_anchor=point;editor_state.link_finish=point;editor_state.link_anchor_active=true}else{command:=Level_Command{kind=.Create_Vertical_Link,a=editor_state.link_anchor,b=point,c={f32(editor_state.link_kind),0},value=editor_state.link_width};if level_preview_transaction(&level_document,command).state!=.Blocked&&level_commit_transaction(&level_document,command,"Create vertical link") do editor_state.link_anchor_active=false}}}
			if g.input.mouse_pressed&&g.build_tool==.Path&&editor_viewport_contains(g.input.mouse_pos,g.build_tool) {wx,wy,ok:=editor_mouse_ground(g,g.input.mouse_pos);if ok&&editor_state.path_draw_count<len(editor_state.path_draw_points) {editor_state.path_draw_points[editor_state.path_draw_count]=level_snap_point(&level_document,{wx,wy},true);editor_state.path_draw_count+=1}}
			if g.input.mouse_pressed&&g.build_tool==.Water&&editor_viewport_contains(g.input.mouse_pos,g.build_tool) {wx,wy,ok:=editor_mouse_ground(g,g.input.mouse_pos);if ok {point:=level_snap_point(&level_document,{wx,wy},true);close:=false;if editor_state.water_draw_count>=3 {first:=editor_state.water_draw_points[0];dx,dy:=point.x-first.x,point.y-first.y;close=dx*dx+dy*dy<=.35*.35};if close {command:=Level_Command{kind=.Create_Water,value=editor_state.water_elevation,point_count=editor_state.water_draw_count};copy(command.points[:],editor_state.water_draw_points[:]);if level_commit_transaction(&level_document,command,"Create pond") do editor_state.water_draw_count=0}else if editor_state.water_draw_count<len(editor_state.water_draw_points) {editor_state.water_draw_points[editor_state.water_draw_count]=point;editor_state.water_draw_count+=1}}}
			if g.build_tool==.Room&&editor_state.room_mode==.Rectangle {
				if g.input.mouse_pressed&&editor_viewport_contains(g.input.mouse_pos,g.build_tool) {wx,wy,ok:=editor_mouse_ground(g,g.input.mouse_pos);if ok {point:=level_snap_point(&level_document,{wx,wy},true);editor_state.room_rectangle_start=point;editor_state.room_rectangle_current=point;editor_state.room_rectangle_active=true;editor_state.room_rectangle_preview={.Blocked,"DRAG TO SIZE ROOM",point,point}}}
				if editor_state.room_rectangle_active&&(g.input.mouse_down||g.input.mouse_released) {wx,wy,ok:=editor_mouse_ground(g,g.input.mouse_pos);if ok {editor_state.room_rectangle_current=level_snap_point(&level_document,{wx,wy},true);editor_state.room_rectangle_preview=level_preview_transaction(&level_document,Level_Command{kind=.Create_Room,a=editor_state.room_rectangle_start,b=editor_state.room_rectangle_current,material=editor_state.room_exterior?"flagstone":strings.to_lower(fmt.tprintf("%v",g.build_surface)),destination=editor_state.room_exterior?"patio":""})}}
				if editor_state.room_rectangle_active&&g.input.mouse_released {if editor_state.room_rectangle_preview.state!=.Blocked do _=level_commit_transaction(&level_document,Level_Command{kind=.Create_Room,a=editor_state.room_rectangle_start,b=editor_state.room_rectangle_current,material=editor_state.room_exterior?"flagstone":strings.to_lower(fmt.tprintf("%v",g.build_surface)),destination=editor_state.room_exterior?"patio":""},editor_state.room_exterior?"Create rectangular patio":"Create rectangular room");editor_state.room_rectangle_active=false}
			}
			if g.build_tool==.Foundation&&editor_state.foundation_mode==.Rectangle {
				if g.input.mouse_pressed&&editor_viewport_contains(g.input.mouse_pos,g.build_tool) {wx,wy,ok:=editor_mouse_ground(g,g.input.mouse_pos);if ok {point:=level_snap_point(&level_document,{wx,wy},true);editor_state.foundation_rectangle_start=point;editor_state.foundation_rectangle_current=point;editor_state.foundation_rectangle_active=true;editor_state.foundation_rectangle_preview={.Blocked,"DRAG TO SIZE FOUNDATION",point,point}}}
				if editor_state.foundation_rectangle_active&&(g.input.mouse_down||g.input.mouse_released) {wx,wy,ok:=editor_mouse_ground(g,g.input.mouse_pos);if ok {editor_state.foundation_rectangle_current=level_snap_point(&level_document,{wx,wy},true);a,b:=editor_state.foundation_rectangle_start,editor_state.foundation_rectangle_current;command:=Level_Command{kind=.Create_Foundation,value=editor_state.foundation_elevation,c={f32(editor_state.foundation_kind),editor_state.foundation_depth},point_count=4};command.points[0]={min(a.x,b.x),min(a.y,b.y)};command.points[1]={max(a.x,b.x),min(a.y,b.y)};command.points[2]={max(a.x,b.x),max(a.y,b.y)};command.points[3]={min(a.x,b.x),max(a.y,b.y)};editor_state.foundation_rectangle_preview=level_preview_transaction(&level_document,command)}}
				if editor_state.foundation_rectangle_active&&g.input.mouse_released {if editor_state.foundation_rectangle_preview.state!=.Blocked {a,b:=editor_state.foundation_rectangle_start,editor_state.foundation_rectangle_current;command:=Level_Command{kind=.Create_Foundation,value=editor_state.foundation_elevation,c={f32(editor_state.foundation_kind),editor_state.foundation_depth},point_count=4};command.points[0]={min(a.x,b.x),min(a.y,b.y)};command.points[1]={max(a.x,b.x),min(a.y,b.y)};command.points[2]={max(a.x,b.x),max(a.y,b.y)};command.points[3]={min(a.x,b.x),max(a.y,b.y)};foundation_count:=len(level_document.foundations);if level_commit_transaction(&level_document,command,fmt.tprintf("Create %s foundation",level_foundation_kind_name(editor_state.foundation_kind)))&&!g.keys[.LSHIFT]&&!g.keys[.RSHIFT]&&len(level_document.foundations)>foundation_count do _=editor_advance_from_foundation(g,&level_document,len(level_document.foundations)-1)};editor_state.foundation_rectangle_active=false}
			}
			if g.input.mouse_pressed&&!editor_state.drag_active&&!editor_state.box_select_active&&!editor_state.terrain_stroke_active&&editor_viewport_contains(g.input.mouse_pos,g.build_tool) {
				wx,wy,ok:=editor_mouse_ground(g,g.input.mouse_pos)
				if ok {
					point:=Vec2{wx,wy};picked,handle_ok:=level_pick_control_point(&level_document,point,editor_state.selection[0]);if !handle_ok do picked,handle_ok=level_pick_room_handle(&level_document,point,editor_state.selection[0]);if !handle_ok do picked=level_pick(&level_document,point)
					if g.build_tool==.Select do picked=editor_view_pick_selection(&level_document,editor_state.view,picked)
					if g.keys[.G]&&picked.kind==.Room {_=level_commit_transaction(&level_document,Level_Command{kind=.Paint_Room,entity_id=picked.entity_id,material="__grounds__"},"Make room exterior")} else {
						#partial switch g.build_tool {
						case .Select:editor_select_pointer(g,picked,point)
						case .Terrain:editor_state.terrain_stroke_active=true;editor_state.terrain_stroke_start=point;editor_state.terrain_stroke_current=point;editor_state.terrain_sample=level_terrain_height(&level_document,point);editor_state.selection_count=0
						case .Marker:command:=Level_Command{kind=.Add_Marker,a=point,b={editor_state.marker_radius,editor_state.marker_facing},c={editor_state.marker_camera_height,f32(editor_state.marker_kind)},material=editor_state.marker_reference,destination=editor_state.marker_destination,value=f32(level_document.active_story)};_=level_commit_transaction(&level_document,command,fmt.tprintf("Place %s marker",level_marker_kind_name(editor_state.marker_kind)))
						case .Light:command:=Level_Command{kind=.Add_Light,a=point,b={editor_state.light_range,editor_state.light_intensity},c={editor_state.light_elevation,f32(editor_state.light_kind)},value=f32(level_document.active_story),color=editor_state.light_color};command.points[0]={editor_state.light_cone_angle,editor_state.light_facing};if level_commit_transaction(&level_document,command,fmt.tprintf("Place %s light",level_light_kind_name(editor_state.light_kind))) {editor_state.selection[0]={.Light,level_document.lights[len(level_document.lights)-1].id,-1};editor_state.selection_count=1}
						case .Paint,.Wall_Paint:if picked.kind==.Room {room_index:=level_room_index(&level_document,picked.entity_id);if editor_state.paint_eyedropper&&room_index>=0 {material:=editor_room_sample_material(level_document.rooms[room_index],editor_state.paint_target);if material!="" {editor_state.catalog_id=material;catalog_record_recent(&editor_state,material)};editor_state.paint_eyedropper=false}else{paint_kind:=editor_paint_command_kind(editor_state.paint_target,g.keys[.LSHIFT]||g.keys[.RSHIFT]);material:=editor_state.catalog_id;if material=="" do material="dining";label:=paint_kind==.Paint_Floor?"Paint floor":paint_kind==.Paint_Walls?"Paint walls":"Paint whole room";_=level_commit_transaction(&level_document,Level_Command{kind=paint_kind,entity_id=picked.entity_id,material=material},label)}}
						case .Plant:if editor_state.placement_preview.state!=.Blocked do _=level_commit_transaction(&level_document,Level_Command{kind=.Place_Object,a=editor_state.placement_position,c={editor_state.placement_elevation,0},value=editor_state.placement_rotation,material=editor_state.catalog_id==""?"plant":editor_state.catalog_id,destination=editor_state.placement_support_id},editor_state.placement_support_id!=""?"Place object on furniture":"Place object")
						case .Door,.Window:if editor_state.opening_active&&editor_state.opening_preview.state!=.Blocked do _=level_commit_transaction(&level_document,editor_state.opening_command,g.build_tool==.Window?"Place window":"Place door")
						case .Wall:if g.build_has_anchor {command,split:=level_wall_command(&level_document,g.build_anchor,point);if level_preview_transaction(&level_document,command).state!=.Blocked&&level_commit_transaction(&level_document,command,split?"Split room with wall":"Draw freestanding wall") {g.build_has_anchor=false;editor_state.wall_preview_active=false;if split {editor_state.selection[0]={.Room,command.entity_id,-1};editor_state.selection_count=1}}}else{g.build_anchor=level_snap_point(&level_document,point,true);g.build_has_anchor=true;editor_state.wall_preview_point=g.build_anchor;editor_state.wall_preview_active=true}
						case .Room:if editor_state.room_mode==.Polygon {snapped:=level_snap_point(&level_document,point,true);close:=false;if editor_state.room_draw_count>=3 {first:=editor_state.room_draw_points[0];dx,dy:=snapped.x-first.x,snapped.y-first.y;close=dx*dx+dy*dy<=.35*.35};if close {command:=Level_Command{kind=.Create_Room_Polygon,material=editor_state.room_exterior?"flagstone":strings.to_lower(fmt.tprintf("%v",g.build_surface)),destination=editor_state.room_exterior?"patio":"",point_count=editor_state.room_draw_count};copy(command.points[:],editor_state.room_draw_points[:]);if level_commit_transaction(&level_document,command,editor_state.room_exterior?"Create polygon patio":"Create polygon room") do editor_state.room_draw_count=0}else if editor_state.room_draw_count<len(editor_state.room_draw_points) {editor_state.room_draw_points[editor_state.room_draw_count]=snapped;editor_state.room_draw_count+=1}}
						case .Foundation:if editor_state.foundation_mode==.Polygon {snapped:=level_snap_point(&level_document,point,true);close:=false;if editor_state.foundation_draw_count>=3 {first:=editor_state.foundation_draw_points[0];dx,dy:=snapped.x-first.x,snapped.y-first.y;close=dx*dx+dy*dy<=.35*.35};if close {_=editor_finish_foundation_polygon(g,g.keys[.LSHIFT]||g.keys[.RSHIFT])}else if editor_state.foundation_draw_count<len(editor_state.foundation_draw_points) {editor_state.foundation_draw_points[editor_state.foundation_draw_count]=snapped;editor_state.foundation_draw_count+=1;editor_state.foundation_polygon_preview={.Valid,"CLICK FIRST POINT OR ENTER TO CLOSE",{}, {}}}}
						}
					}
				}
			}
			break
		}
		update_world(g)
		if button(g,gameplay_theory_rect()) || g.keys[.B] || g.input.recreate {g.screen=.Board}
		if button(g,gameplay_attributes_rect()) || g.input.attributes {open_attributes(g)}
		if button(g,gameplay_notebook_rect()) || g.input.notebook {open_notebook(g)}
		if g.keys[.F12] {g.screen=.Diagnostics}
	case .Dialogue: update_dialogue(g)
	case .Check:
		update_check_result_cue(g)
		roll_settled:=g.check_done&&g.animation_time-g.check_roll_started>=CHECK_REVEAL_DURATION
		if !g.check_done && button(g,{430,510,340,58}) {g.check_result=resolve_clue_check(g,g.pending_clue);g.check_roll_started=g.animation_time;g.check_result_cue_played=false;play_check_dice_sound(g);g.check_done=true}
		if roll_settled&&g.check_done && button(g,{430,500,340,50}) {if g.investigation_locked&&!overtime_active(g) do route_locked_investigation(g);else do g.screen=g.check_from_dialogue?.Dialogue:.Investigate}
	case .Attributes:
		for i in 0..<4 do if button(g,{42,145+f32(i)*117,250,105}) do g.attribute_selected=i
		if button(g,menu_overlay_back_rect()) do return_from_menu_overlay(g,g.menu_detail_return,g.menu_detail_return_focus)
	case .Notebook:
		old_tab:=g.notebook_tab
		if g.input.shoulder_left do g.notebook_tab=(g.notebook_tab+5)%6
		if g.input.shoulder_right do g.notebook_tab=(g.notebook_tab+1)%6
		for i in 0..<6 {if button(g,{20+f32(i)*190,95,176,46}) {g.notebook_tab=i}}
		if g.notebook_tab!=old_tab {g.notebook_scroll=0;g.notebook_scroll_target=0;g.gui.focused=button_id({20+f32(g.notebook_tab)*190,95,176,46})}
		scroll_delta:= -g.input.mouse_wheel*72+g.pad_right_y*12
		if g.input.up do scroll_delta-=56
		if g.input.down do scroll_delta+=56
		g.notebook_scroll_target=clamp(g.notebook_scroll_target+scroll_delta,0,g.notebook_scroll_max)
		g.notebook_scroll+=(g.notebook_scroll_target-g.notebook_scroll)*.2
		if math.abs(g.notebook_scroll_target-g.notebook_scroll)<.1 do g.notebook_scroll=g.notebook_scroll_target
		if button(g,menu_overlay_back_rect()) do return_from_menu_overlay(g,g.notebook_return,g.notebook_return_focus)
	case .Board:
		if g.input.notebook {open_notebook(g);break}
		if button(g,{40,70,210,38}) do g.board_view=0
		if button(g,{265,70,250,38}) do g.board_view=1
		if g.board_view==0 {
			for slot in 0..<3 {i:=visible_question_index(g,slot);if i>=0&&button(g,{120,145+f32(slot)*135,960,112}) {g.question_selected=i;g.question_slot=0;g.knowledge_cursor=0;g.screen=.Challenge}}
			if button(g,{400,610,400,58}) do g.screen=.Reveal_Prep
		}else{
			event_chain_from_evidence(g)
			for i in 0..<g.workbench_event_count do if button(g,event_chain_card_rect(i)) do g.workbench_selected=i
			if g.workbench_event_count>0 {field_map:=[4]int{0,1,2,4};for _,i in field_map do if button(g,event_chain_field_rect(i)) {g.workbench_field=i;workbench_cycle(g,field_map[i],1)};if button(g,{45,600,190,44}) do workbench_swap(g,-1);if button(g,{250,600,190,44}) do workbench_swap(g,1);if workbench_first_incomplete(g)<0&&(button(g,{900,610,255,52})||g.input.recreate) do run_workbench(g)}
		}
		if button(g,{40,660,180,42})||button(g,{40,640,200,48}) {return_from_board(g)}
	case .Challenge:
		if g.input.notebook {open_notebook(g);break}
		payload:=mystery_game_payload(g)
		if payload!=nil&&g.question_selected>=0&&g.question_selected<len(payload.questions) {demo_index:=demonstration_for_question(g,g.question_selected);if demo_index>=0 {demo:=&payload.demonstrations[demo_index];for slot in 0..<demo.slot_count do if button(g,{70+f32(slot)*365,205,330,104}) {g.question_slot=slot;g.knowledge_cursor=0;if mystery_question_slot(g,g.question_selected,slot)!="" do question_clear_slot(g)};piece_count:=question_slot_piece_count(g);start:=clamp(g.knowledge_cursor,0,max(0,piece_count-3));for shown in 0..<min(3,piece_count-start) {piece:=question_slot_piece_id(g,start+shown);x:=70+f32(shown)*365;if button(g,{x,380,330,150}) do question_place_piece(g,piece)};if button(g,{70,555,150,48})||g.input.shoulder_left do g.knowledge_cursor=max(0,g.knowledge_cursor-3);if button(g,{235,555,150,48})||g.input.shoulder_right do g.knowledge_cursor=min(max(0,piece_count-3),g.knowledge_cursor+3);can_demonstrate:=question_slots_full(g,g.question_selected);if can_demonstrate&&(button(g,{845,625,300,58})||g.input.recreate) do begin_question_demonstration(g)}}
		if button(g,{40,640,220,48}) do g.screen=.Board
	case .Recreate:
		if g.input.notebook {open_notebook(g);break};if g.interaction_active {if button(g,{440,630,320,54})||g.input.recreate do advance_question_interaction(g)} else if g.interaction_mismatch {if button(g,{440,630,320,54}) {g.interaction_mismatch=false;g.screen=.Challenge}} else if button(g,{440,630,320,54}) {g.screen=.Board}
	case .Game_Over: if button(g,{410,410,380,52}) {destination:Screen=case_starts_in_city(g)?.Exterior:.Investigate;reset_case_state(g,g.run_seed,destination)};if button(g,{410,478,380,52}) {reset_case_state(g,begin_new_story_seed(),.Title)};if button(g,{410,546,380,52}) {g.running=false}
	case .Reveal_Prep:
		for i in 0..<3 {if button(g,{330+f32(i)*190,88,175,48}) {mystery_game_set_accusation(g,suspect_id(g,i))}}
		for pillar in 0..<3 do if button(g,{990,204+f32(pillar)*125,80,50}) do cycle_proof_pillar(g,pillar)
		if button(g,{400,620,400,58}) {if mystery_game_accusation(g)=="" {g.result=evaluate_questions(g);if !enter_case_ending(g,case_ending_trigger_for_outcome(g.result)) {g.phase=.Case_Result;g.screen=.Result}}else{g.reveal_act=0;g.finale_demo_step=0;g.phase=.Final_Reveal;g.screen=.Reveal}}
		if button(g,{40,640,200,48}) {g.screen=.Board};if button(g,{930,640,220,48}) {open_notebook(g)}
	case .Reveal: if button(g,{440,630,320,54}) {if g.reveal_act<4 {if reveal_act_supported(g,g.reveal_act)&&!mystery_game_reveal_presented(g,g.reveal_act) {_=mystery_game_mark_reveal_presented(g,g.reveal_act);play_sound(g,.Reveal_Proven)}else if g.reveal_act<3 {g.reveal_act+=1}else if payload:=mystery_game_payload(g);payload!=nil&&mystery_game_accusation(g)==payload.solution.culprit_id&&knowledge_piece_known(g,"ded_miriam_denial_disproved") {g.reveal_act=4}else{g.result=evaluate_questions(g);if !enter_case_ending(g,case_ending_trigger_for_outcome(g.result)) {g.phase=.Case_Result;g.screen=.Result}}}else if g.finale_demo_step<2 {g.finale_demo_step+=1}else{g.result=evaluate_questions(g);if !enter_case_ending(g,case_ending_trigger_for_outcome(g.result)) {g.phase=.Case_Result;g.screen=.Result}}}
	case .Result:
		if ending:=active_case_ending(g);ending!=nil {if !(ending.primary_action=="reveal"&&g.show_canonical)&&button(g,{300,630,280,54}) do perform_case_ending_action(g,ending.primary_action);if ending.secondary_label!=""&&button(g,{620,630,280,54}) do perform_case_ending_action(g,ending.secondary_action)} else {if button(g,{300,630,280,54}) {g.show_canonical=true};if button(g,{620,630,280,54}) do reset_case_state(g,begin_new_story_seed(),.Campaign)}
	case .Diagnostics: if button(g,{20,650,180,42}) {g.screen=.Investigate};if button(g,{550,505,300,42}) do copy_case_pacing_report(g)
	}
}

system_courier_path :: proc() -> string {
	when ODIN_OS == .Darwin {
		candidates := [?]string{"/System/Library/Fonts/SFNSMono.ttf", "/System/Library/Fonts/Courier.ttc", "/System/Library/Fonts/Supplemental/Courier New.ttf"}
		for path in candidates do if os.is_file(path) do return path
	} else when ODIN_OS == .Windows {
		candidates := [?]string{"C:/Windows/Fonts/cour.ttf", "C:/Windows/Fonts/couri.ttf"}
		for path in candidates do if os.is_file(path) do return path
	} else {
		// Common Courier-compatible system faces provided by fontconfig packages.
		candidates := [?]string{
			"/usr/share/fonts/opentype/urw-base35/NimbusMonoPS-Regular.otf",
			"/usr/share/fonts/truetype/liberation2/LiberationMono-Regular.ttf",
			"/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
			"/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
		}
		for path in candidates do if os.is_file(path) do return path
	}
	return ""
}

system_ui_font_path :: proc() -> string {
	if path,ok:=story_ui_font_path(&active_story_project,&authoring_workspace.assets);ok&&os.is_file(path) do return path
	when ODIN_OS == .Darwin {
		candidates := [?]string{"/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"}
		for path in candidates do if os.is_file(path) do return path
	} else when ODIN_OS == .Windows {
		candidates := [?]string{"C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/arial.ttf"}
		for path in candidates do if os.is_file(path) do return path
	} else {
		candidates := [?]string{"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf"}
		for path in candidates do if os.is_file(path) do return path
	}
	return system_courier_path()
}

system_symbol_path :: proc() -> string {
	when ODIN_OS == .Darwin {
		candidates := [?]string{"/System/Library/Fonts/Apple Symbols.ttf", "/System/Library/Fonts/SFNSMono.ttf"}
		for path in candidates do if os.is_file(path) do return path
	} else when ODIN_OS == .Windows {
		candidates := [?]string{"C:/Windows/Fonts/seguisym.ttf", "C:/Windows/Fonts/seguisymbol.ttf"}
		for path in candidates do if os.is_file(path) do return path
	} else {
		candidates := [?]string{"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/truetype/noto/NotoSansSymbols2-Regular.ttf"}
		for path in candidates do if os.is_file(path) do return path
	}
	return system_courier_path()
}

skill_helper :: proc(skill:string)->(name,line:string,color:[4]u8) {
	switch skill {
	case "Observation":return "MAGPIE","Something small is asking to be noticed.",{155,201,255,255}
	case "Analysis":return "OWL","Two facts can share a board without agreeing.",{176,145,218,255}
	case "Empathy":return "HOUND","Listen for what the answer is protecting.",{102,205,143,255}
	case "Pressure":return "LION","Give the silence somewhere dramatic to land.",{255,144,119,255}
	}
	return "INSTINCT","There is a useful question here.",{255,211,92,255}
}

vk_draw_helper_badge :: proc(r:^Vulkan_Backend,x,y:f32,skill:string,color:[4]u8) {
	vulkan_ui_rect(r,x,y,105,105,{34,38,43,255});vulkan_ui_outline(r,x,y,105,105,color,3)
	switch skill {
	case "Observation":
		vulkan_ui_rect(r,x+28,y+29,42,45,color);vulkan_ui_rect(r,x+70,y+43,22,10,{255,211,92,255});vulkan_ui_rect(r,x+57,y+39,7,7,{20,22,25,255});vulkan_ui_rect(r,x+20,y+20,18,18,color)
	case "Analysis":
		vulkan_ui_rect(r,x+25,y+29,55,50,color);vulkan_ui_rect(r,x+16,y+18,26,26,color);vulkan_ui_rect(r,x+63,y+18,26,26,color);vulkan_ui_rect(r,x+34,y+43,10,10,{20,22,25,255});vulkan_ui_rect(r,x+61,y+43,10,10,{20,22,25,255});vulkan_ui_rect(r,x+49,y+60,8,12,{255,211,92,255})
	case "Empathy":
		vulkan_ui_rect(r,x+27,y+31,51,49,color);vulkan_ui_rect(r,x+14,y+23,20,48,color);vulkan_ui_rect(r,x+71,y+23,20,48,color);vulkan_ui_rect(r,x+48,y+55,10,9,{20,22,25,255});vulkan_ui_rect(r,x+37,y+43,6,6,{20,22,25,255});vulkan_ui_rect(r,x+63,y+43,6,6,{20,22,25,255})
	case "Pressure":
		vulkan_ui_rect(r,x+17,y+17,71,71,color);vulkan_ui_rect(r,x+29,y+29,47,47,{94,58,43,255});vulkan_ui_rect(r,x+38,y+44,7,7,{20,22,25,255});vulkan_ui_rect(r,x+61,y+44,7,7,{20,22,25,255});vulkan_ui_rect(r,x+47,y+62,12,4,{255,211,92,255})
	}
}

character_stage_direction :: proc(g:^Game,id:string)->string {
	if id=="miriam" {
		if topic_unlocked(g,"appointment_contradiction") do return "The rejoined note remains crooked before her. For once, she does not look toward Daniel."
		if topic_unlocked(g,"appointment_denial") do return "She denies Edgar sent for her before you mention the time written on his memo stub."
		if g.threshold_eight_spent do return "She keeps her hands folded beneath the table and watches every new piece of evidence."
		return "Composed, she supplies more detail than the question requires."
	}
	if id=="daniel" {
		if topic_unlocked(g,"affair_admitted") do return "Relief softens him once the affair is separated from Edgar's death."
		if claim_known(g,"claim_daniel_alibi") do return "He looks to Miriam before committing himself to her account."
		if g.threshold_four_spent do return "He worries a thumbnail against his watch chain."
	}
	if id=="elsie" {
		if topic_unlocked(g,"theft_explained") do return "She stops straightening the table and finally meets your eyes."
		if topic_unlocked(g,"miriam_sighting") do return "The fear drains from her voice when the theft is named separately."
		if g.threshold_eight_spent do return "A folded banknote protrudes from the cash box she is trying to put back."
		return "She aligns a crooked frame while insisting she never entered the study."
	}
	return "The room waits for the next question."
}
// Shared UI theme. Keep the palette semantic: screens should choose a role
// (ink, muted, accent, danger) instead of inventing another near-identical
// blue-black or brass. This also gives creator and player tools one visual
// language while preserving their distinct blue/gold accents.
UI_INK              := [4]u8{232,224,207,255}
UI_INK_STRONG       := [4]u8{250,242,220,255}
// Secondary copy still needs to survive presentation scaling and dark rooms.
// Keep it quieter than body ink through hue, not insufficient luminance.
UI_MUTED            := [4]u8{210,205,192,255}
UI_MUTED_DIM        := [4]u8{190,187,177,255}
UI_CANVAS           := [4]u8{3,4,5,255}
UI_SURFACE          := [4]u8{7,8,9,250}
UI_SURFACE_RAISED   := [4]u8{12,13,14,252}
UI_SURFACE_HOVER    := [4]u8{22,23,22,255}
UI_BORDER           := [4]u8{74,68,56,230}
UI_BORDER_STRONG    := [4]u8{128,112,82,255}
UI_ACCENT           := [4]u8{207,162,74,255}
UI_ACCENT_SOFT      := [4]u8{59,43,18,255}
UI_ACCENT_DARK      := [4]u8{104,78,36,255}
UI_INFO             := [4]u8{132,161,164,255}
UI_SUCCESS          := [4]u8{127,166,126,255}
UI_WARNING          := [4]u8{207,162,74,255}
UI_DANGER           := [4]u8{181,83,70,255}
UI_SHADOW           := [4]u8{0,0,0,165}
UI_CONSOLE_CAPTION_SCALE :: f32(.76)
UI_CONSOLE_LABEL_SCALE   :: f32(.82)
UI_CONSOLE_BODY_SCALE    :: f32(.90)

ui_success_chance_color :: proc(chance:int)->[4]u8 {
	if chance<50 do return UI_DANGER
	if chance<75 do return UI_WARNING
	return UI_SUCCESS
}

vk_text :: proc(r:^Vulkan_Backend,x,y:f32,value:string,color:=UI_INK,scale:f32=1.25) {
	vulkan_ui_text(r,r.font_texture,x,y,value,color,scale)
}
// Editor copy is often displayed over a detailed 3D scene and the window may
// be shorter than the 1200x720 logical canvas. Below this size the mono glyph
// stems collapse after presentation scaling, so compact editor labels must
// spend space on legibility rather than becoming miniature annotations.
EDITOR_MIN_TEXT_SCALE :: f32(.70)
vk_editor_text :: proc(r:^Vulkan_Backend,x,y:f32,value:string,color:=UI_INK,scale:f32=.65) {
	vk_text(r,x,y,value,color,max(scale,EDITOR_MIN_TEXT_SCALE))
}
vk_editor_text_wrapped :: proc(r:^Vulkan_Backend,x,y,max_width:f32,value:string,color:=UI_INK,scale:f32=.65,line_spacing:f32=1)->f32 {
	return vk_text_wrapped(r,x,y,max_width,value,color,max(scale,EDITOR_MIN_TEXT_SCALE),line_spacing)
}
vk_graph_ui_text :: proc(r:^Vulkan_Backend,x,y:f32,value:string,color:=UI_INK,scale:f32=.65) {
	vulkan_ui_system_text(r,x,y,value,color,max(scale,EDITOR_MIN_TEXT_SCALE))
}
vk_art_fit :: proc(r:^Vulkan_Backend,art:UI_Art,x,y,w,h:f32,tint:=[4]u8{255,255,255,255}) {
	texture:=vulkan_ui_art_texture(r,art);if texture<0||texture>=len(r.images) do return
	image:=r.images[texture];source_aspect:=f32(image.width)/f32(max(image.height,1));box_aspect:=w/max(h,.001);dw,dh:=w,h
	if source_aspect>box_aspect {dh=w/source_aspect}else{dw=h*source_aspect}
	vulkan_ui_quad(r,x+(w-dw)/2,y+(h-dh)/2,dw,dh,tint,texture,{}, {1,1},true)
}
vk_art_cover :: proc(r:^Vulkan_Backend,art:UI_Art,x,y,w,h:f32,tint:=[4]u8{255,255,255,255}) {
	texture:=vulkan_ui_art_texture(r,art);if texture<0||texture>=len(r.images) do return
	image:=r.images[texture];source_aspect:=f32(image.width)/f32(max(image.height,1));box_aspect:=w/max(h,.001);uv0,uv1:=Vec2{},Vec2{1,1}
	if source_aspect>box_aspect {visible:=box_aspect/source_aspect;uv0.x=(1-visible)/2;uv1.x=1-uv0.x}else{visible:=source_aspect/box_aspect;uv0.y=(1-visible)/2;uv1.y=1-uv0.y}
	vulkan_ui_quad(r,x,y,w,h,tint,texture,uv0,uv1,true)
}
vk_art_stretch :: proc(r:^Vulkan_Backend,art:UI_Art,x,y,w,h:f32,tint:=[4]u8{255,255,255,255}) {
	texture:=vulkan_ui_art_texture(r,art);if texture<0||texture>=len(r.images) do return
	vulkan_ui_quad(r,x,y,w,h,tint,texture,{}, {1,1},true)
}

vk_campaign_hero_cover :: proc(r:^Vulkan_Backend,index:int,x,y,w,h:f32,tint:=[4]u8{255,255,255,255})->bool {
	if index<0||index>=len(r.campaign_textures) do return false;texture:=r.campaign_textures[index];if texture<0||texture>=len(r.images) do return false
	img:=r.images[texture];source_aspect:=f32(img.width)/f32(max(img.height,1));box_aspect:=w/max(h,.001);uv0,uv1:=Vec2{},Vec2{1,1};if source_aspect>box_aspect {visible:=box_aspect/source_aspect;uv0.x=(1-visible)/2;uv1.x=1-uv0.x}else{visible:=source_aspect/box_aspect;uv0.y=(1-visible)/2;uv1.y=1-uv0.y};vulkan_ui_quad(r,x,y,w,h,tint,texture,uv0,uv1,true);return true
}

vk_prompt_icon :: proc(r:^Vulkan_Backend,g:^Game,kind:Prompt_Kind,x,y,size:f32) {
	art:=UI_Art.Prompt_Keyboard;sheet_w,sheet_h:=f32(1088),f32(1024);cell_x,cell_y:=f32(0),f32(0);mapped:=false
	if g.active_device==.Keyboard_Mouse {
		#partial switch kind {case .Accept,.Interact:cell_x=320;cell_y=320;mapped=true;case .Board:cell_x=192;cell_y=192;mapped=true;case .Notebook:cell_x=896;cell_y=512;mapped=true;case .Back:cell_x=832;cell_y=320;mapped=true;case:}
	} else {
		switch gamepad_family(g.gamepad_type) {
		case 1:
			art=.Prompt_PlayStation;sheet_w=768;sheet_h=768
			#partial switch kind {case .Accept,.Interact:cell_x=320;cell_y=64;mapped=true;case .Board,.Attributes,.Handbrake:cell_x=704;cell_y=64;mapped=true;case .Notebook:cell_x=64;cell_y=128;mapped=true;case .Back:cell_x=448;cell_y=0;mapped=true;case:}
		case 2:
			art=.Prompt_Switch;sheet_w=704;sheet_h=704
			#partial switch kind {case .Accept,.Interact:cell_x=384;cell_y=0;mapped=true;case .Board,.Attributes,.Handbrake:cell_x=256;cell_y=128;mapped=true;case .Notebook:cell_x=128;cell_y=128;mapped=true;case .Back:cell_x=256;cell_y=0;mapped=true;case:}
		case:
			art=.Prompt_Xbox;sheet_w=640;sheet_h=640
			#partial switch kind {case .Accept,.Interact:cell_x=256;cell_y=0;mapped=true;case .Board,.Attributes,.Handbrake:cell_x=0;cell_y=192;mapped=true;case .Notebook:cell_x=128;cell_y=192;mapped=true;case .Back:cell_x=384;cell_y=0;mapped=true;case:}
		}
	}
	if !mapped {label:=prompt_label(g,kind);width:=max(size,f32(utf8_glyph_count(label))*6+14);vulkan_ui_rect(r,x,y,width,size,{38,43,52,245});vulkan_ui_outline(r,x,y,width,size,{205,207,210,220},2);scale:=min(f32(.46),(width-8)/(max(f32(utf8_glyph_count(label)),1)*f32(COURIER_CELL_WIDTH)));vk_text(r,x+7,y+(size-f32(COURIER_CELL_HEIGHT)*scale)/2,label,{248,247,242,255},scale);return}
	texture:=vulkan_ui_art_texture(r,art);if texture<0 do return
	// Kenney atlas XML uses a top-left origin; Vulkan samples these uploaded
	// sheets from the bottom-left.
	cell_y=sheet_h-cell_y-64
	uv0:=Vec2{cell_x/sheet_w,cell_y/sheet_h};uv1:=Vec2{(cell_x+64)/sheet_w,(cell_y+64)/sheet_h}
	vulkan_ui_quad(r,x,y,size,size,{255,255,255,255},texture,uv0,uv1,true)
}

vk_level_icon :: proc(r:^Vulkan_Backend,row,column:int,x,y,size:f32,tint:=[4]u8{255,255,255,255}) {texture:=vulkan_ui_art_texture(r,.Level_Builder_Atlas);if texture<0 do return;cell:f32=1.0/8.0;inset:f32=.004;uv0:=Vec2{f32(column)*cell+inset,f32(row)*cell+inset};uv1:=Vec2{f32(column+1)*cell-inset,f32(row+1)*cell-inset};vulkan_ui_quad(r,x,y,size,size,tint,texture,uv0,uv1,true)}
EDITOR_INK := UI_INK
EDITOR_MUTED := UI_MUTED
EDITOR_SURFACE := UI_SURFACE
EDITOR_SURFACE_STRONG := UI_SURFACE_RAISED
EDITOR_BORDER := UI_BORDER
EDITOR_BLUE := UI_INFO
EDITOR_BLUE_SOFT := [4]u8{37,72,86,255}
editor_ui_mouse := Vec2{-1000,-1000}

vk_editor_surface :: proc(r:^Vulkan_Backend,box:Rect,strong:=false) {vulkan_ui_rect(r,box.x+3,box.y+5,box.w,box.h,{31,38,43,70});vulkan_ui_rect(r,box.x,box.y,box.w,box.h,strong?EDITOR_SURFACE_STRONG:EDITOR_SURFACE);vulkan_ui_outline(r,box.x,box.y,box.w,box.h,EDITOR_BORDER,1)}

vk_tab_bar_surface :: proc(r:^Vulkan_Backend,box:Rect) {
	vulkan_ui_rect(r,box.x+3,box.y+5,box.w,box.h,UI_SHADOW)
	vulkan_ui_rect(r,box.x,box.y,box.w,box.h,UI_SURFACE)
	vulkan_ui_outline(r,box.x,box.y,box.w,box.h,UI_BORDER,1)
	vulkan_ui_rect(r,box.x+1,box.y+box.h-4,box.w-2,3,UI_ACCENT_DARK)
}

vk_tab_surface :: proc(r:^Vulkan_Backend,box:Rect,label:string,active,focused:bool,enabled:=true) {
	draw_box:=box
	if active {draw_box.y-=4;draw_box.h+=5}
	fill:=active?UI_SURFACE_HOVER:focused?UI_SURFACE_RAISED:UI_SURFACE
	text_color:=active?UI_INK_STRONG:focused?UI_INK:UI_MUTED_DIM
	edge:=UI_ACCENT_DARK
	if !enabled {fill={10,11,12,235};text_color={110,108,102,220};edge=UI_BORDER}
	vulkan_ui_rect(r,draw_box.x,draw_box.y,draw_box.w,draw_box.h,fill)
	vulkan_ui_rect(r,draw_box.x+draw_box.w-1,draw_box.y+8,1,max(0,draw_box.h-16),edge)
	if active {
		vulkan_ui_rect(r,draw_box.x,draw_box.y,draw_box.w,3,UI_ACCENT)
		vulkan_ui_rect(r,draw_box.x,draw_box.y,2,draw_box.h,edge);vulkan_ui_rect(r,draw_box.x+draw_box.w-2,draw_box.y,2,draw_box.h,edge)
		vulkan_ui_rect(r,draw_box.x+2,draw_box.y+draw_box.h-4,draw_box.w-4,4,fill)
	} else if focused {
		vulkan_ui_rect(r,draw_box.x+12,draw_box.y+draw_box.h-5,draw_box.w-24,3,UI_ACCENT)
	}
	glyphs:=utf8_glyph_count(label);scale:f32=1.0
	if glyphs>0 do scale=min(scale,max((box.w-22)/(f32(glyphs)*COURIER_CELL_WIDTH),.72))
	width:=f32(glyphs)*COURIER_CELL_WIDTH*scale
	vk_text(r,draw_box.x+(draw_box.w-width)*.5,draw_box.y+(draw_box.h-f32(COURIER_CELL_HEIGHT)*scale)/2,label,text_color,scale)
}

vk_editor_pill :: proc(r:^Vulkan_Backend,box:Rect,label:string,on:=false,enabled:=true) {
	hovered:=enabled&&contains(box,editor_ui_mouse)
	fill:=on?EDITOR_BLUE_SOFT:hovered?[4]u8{48,60,70,252}:EDITOR_SURFACE_STRONG
	border:=on?EDITOR_BLUE:hovered?[4]u8{126,151,169,255}:EDITOR_BORDER
	text_color:=on?[4]u8{221,246,252,255}:hovered?[4]u8{255,255,255,255}:EDITOR_INK
	if !enabled {fill={31,37,44,235};border={62,70,79,220};text_color={110,120,130,220}}
	vulkan_ui_rect(r,box.x+2,box.y+3,box.w,box.h,{0,0,0,80});vulkan_ui_rect(r,box.x,box.y,box.w,box.h,fill);vulkan_ui_outline(r,box.x,box.y,box.w,box.h,border,on||hovered?2:1)
	if on {vulkan_ui_rect(r,box.x+5,box.y+box.h-4,box.w-10,3,EDITOR_INK);vulkan_ui_rect(r,box.x+7,box.y+7,4,4,EDITOR_INK)}
	scale:=EDITOR_MIN_TEXT_SCALE;glyphs:=utf8_glyph_count(label);vk_editor_text(r,box.x+(box.w-f32(glyphs)*COURIER_CELL_WIDTH*scale)/2,box.y+(box.h-f32(COURIER_CELL_HEIGHT)*scale)/2,label,text_color,scale)
}
vk_level_icon_button :: proc(r:^Vulkan_Backend,box:Rect,row,column:int,on:=false,enabled:=true,hovered:=false) {
	is_hovered:=(hovered||contains(box,editor_ui_mouse))&&enabled
	background:=on?EDITOR_BLUE_SOFT:is_hovered?[4]u8{48,60,70,252}:EDITOR_SURFACE_STRONG
	outline:=on?EDITOR_BLUE:is_hovered?[4]u8{126,151,169,255}:EDITOR_BORDER
	tint:=on?[4]u8{220,246,252,255}:is_hovered?[4]u8{255,255,255,255}:EDITOR_INK
	if !enabled {background={31,37,44,235};outline={62,70,79,220};tint={110,120,130,170}}
	vulkan_ui_rect(r,box.x+2,box.y+3,box.w,box.h,{0,0,0,80});vulkan_ui_rect(r,box.x,box.y,box.w,box.h,background);vk_level_icon(r,row,column,box.x+5,box.y+5,min(box.w,box.h)-10,tint);vulkan_ui_outline(r,box.x,box.y,box.w,box.h,outline,on||is_hovered?2:1)
}
vk_editor_cycle_button :: proc(r:^Vulkan_Backend,box:Rect,direction:int,enabled:=true) {
	hovered:=enabled&&contains(box,editor_ui_mouse);fill:=hovered?EDITOR_BLUE_SOFT:enabled?EDITOR_SURFACE_STRONG:[4]u8{31,37,44,235};border:=hovered?EDITOR_BLUE:enabled?EDITOR_BORDER:[4]u8{62,70,79,220};c:=enabled?EDITOR_INK:[4]u8{110,120,130,170}
	vulkan_ui_rect(r,box.x+2,box.y+3,box.w,box.h,{0,0,0,80});vulkan_ui_rect(r,box.x,box.y,box.w,box.h,fill);vulkan_ui_outline(r,box.x,box.y,box.w,box.h,border,hovered?2:1)
	center:=Vec2{box.x+box.w*.5,box.y+box.h*.5};half:=min(box.w,box.h)*.18
	if direction<0 do vulkan_ui_triangle(r,{center.x+half,center.y-half},{center.x-half,center.y},{center.x+half,center.y+half},c);else do vulkan_ui_triangle(r,{center.x-half,center.y-half},{center.x+half,center.y},{center.x-half,center.y+half},c)
}
Editor_Parameter_Icon :: enum {Height, Radius, Strength, Range, Intensity, Pitch, Overhang, Width, Rotate, Cone}
vk_editor_parameter_button :: proc(r:^Vulkan_Backend,box:Rect,icon:Editor_Parameter_Icon,direction:int,mouse:Vec2,enabled:=true) {
	hovered:=enabled&&contains(box,mouse);fill:=hovered?EDITOR_BLUE_SOFT:enabled?EDITOR_SURFACE_STRONG:[4]u8{31,37,44,235};border:=hovered?EDITOR_BLUE:enabled?EDITOR_BORDER:[4]u8{62,70,79,220}
	vulkan_ui_rect(r,box.x+2,box.y+3,box.w,box.h,{0,0,0,80});vulkan_ui_rect(r,box.x,box.y,box.w,box.h,fill);vulkan_ui_outline(r,box.x,box.y,box.w,box.h,border,hovered?2:1)
	c:=enabled?EDITOR_INK:[4]u8{110,120,130,170};x:=box.x+8;y:=box.y+7;w:=min(f32(15),box.w-20);h:=box.h-14
	atlas_column:=-1;#partial switch icon {case .Range:atlas_column=3;case .Intensity:atlas_column=4;case .Height:atlas_column=5;case .Rotate:atlas_column=6;case .Cone:atlas_column=7}
	if atlas_column>=0 {size:=min(box.h-8,box.w-18);vk_level_icon(r,0,atlas_column,box.x+4,box.y+(box.h-size)*.5,size,enabled?[4]u8{255,255,255,255}:[4]u8{125,132,138,170})} else {switch icon {
	case .Height: vulkan_ui_rect(r,x+w*.45,y,2,h,c);vulkan_ui_rect(r,x+w*.2,y,8,2,c);vulkan_ui_rect(r,x+w*.2,y+h-2,8,2,c)
	case .Radius:
		center:=Vec2{x+w*.5,y+h*.5};radius:=min(w,h)*.42;for i in 0..<16 {a:=f32(i)*f32(math.PI*2)/16;b:=f32(i+1)*f32(math.PI*2)/16;vk_editor_line(r,{center.x+f32(math.cos(f64(a)))*radius,center.y+f32(math.sin(f64(a)))*radius},{center.x+f32(math.cos(f64(b)))*radius,center.y+f32(math.sin(f64(b)))*radius},c,1)};vk_editor_line(r,center,{center.x+radius,center.y},c,2)
	case .Strength: for i in 0..<3 do vulkan_ui_rect(r,x+f32(i)*5,y+h-f32(i+1)*4,3,f32(i+1)*4,c)
	case .Range:
		center:=Vec2{x+2,y+h*.5};for ring in 1..=2 {radius:=f32(ring)*4;for i in -3..=3 {a:=f32(i)*f32(math.PI)/7;b:=f32(i+1)*f32(math.PI)/7;vk_editor_line(r,{center.x+f32(math.cos(f64(a)))*radius,center.y+f32(math.sin(f64(a)))*radius},{center.x+f32(math.cos(f64(b)))*radius,center.y+f32(math.sin(f64(b)))*radius},c,1)}}
	case .Intensity: vulkan_ui_rect(r,x+5,y+4,7,7,c);vulkan_ui_rect(r,x+7,y,2,3,c);vulkan_ui_rect(r,x+7,y+12,2,3,c);vulkan_ui_rect(r,x+1,y+6,3,2,c);vulkan_ui_rect(r,x+13,y+6,3,2,c)
	case .Pitch: vk_editor_line(r,{x,y+h-2},{x+w*.5,y+1},c,2);vk_editor_line(r,{x+w*.5,y+1},{x+w,y+h-2},c,2)
	case .Overhang: vk_editor_line(r,{x,y+5},{x+w*.5,y+1},c,2);vk_editor_line(r,{x+w*.5,y+1},{x+w,y+5},c,2);vulkan_ui_rect(r,x+3,y+7,w-6,2,c);vulkan_ui_rect(r,x+5,y+9,2,h-9,c);vulkan_ui_rect(r,x+w-7,y+9,2,h-9,c)
	case .Width: vulkan_ui_rect(r,x,y+h*.5,w,2,c);vulkan_ui_rect(r,x,y+h*.5-3,2,8,c);vulkan_ui_rect(r,x+w-2,y+h*.5-3,2,8,c)
	case .Rotate:
		center:=Vec2{x+w*.5,y+h*.5};radius:=min(w,h)*.42;for i in 0..<12 {a:=f32(i)*f32(math.PI*1.65)/12-f32(math.PI*.75);b:=f32(i+1)*f32(math.PI*1.65)/12-f32(math.PI*.75);vk_editor_line(r,{center.x+f32(math.cos(f64(a)))*radius,center.y+f32(math.sin(f64(a)))*radius},{center.x+f32(math.cos(f64(b)))*radius,center.y+f32(math.sin(f64(b)))*radius},c,2)};vulkan_ui_rect(r,x+w-4,y+1,5,3,c)
	case .Cone: vk_editor_line(r,{x,y+h*.5},{x+w,y+1},c,2);vk_editor_line(r,{x,y+h*.5},{x+w,y+h-1},c,2);vulkan_ui_rect(r,x,y+h*.5-1,3,3,c)
	}
	}
	delta:=direction<0?"-":"+";delta_color:=enabled?(direction<0?EDITOR_MUTED:[4]u8{117,229,169,255}):[4]u8{100,108,116,150};vk_editor_text(r,box.x+box.w-12,box.y+box.h-15,delta,delta_color,.52)
}
vk_editor_icon_tooltip :: proc(r:^Vulkan_Backend,box:Rect,label:string,mouse:Vec2) {
	if !contains(box,mouse) do return
	width:=f32(utf8_glyph_count(label))*7+16
	x:=clamp(box.x,f32(74),f32(418)-width)
	vk_editor_surface(r,{x,102,width,24},true)
	vk_editor_text(r,x+8,108,label,EDITOR_INK,.36)
}
vk_catalog_thumbnail :: proc(r:^Vulkan_Backend,entry:Catalog_Entry,box:Rect) {if entry.kind==.Object&&entry.thumbnail_index>=0&&entry.thumbnail_index<len(r.catalog_textures) {texture:=r.catalog_textures[entry.thumbnail_index];if texture>=0 do vulkan_ui_quad(r,box.x+3,box.y+3,box.w-6,48,{255,255,255,255},texture,{}, {1,1},true)} else if entry.kind==.Material&&entry.catalog_index>=0&&entry.catalog_index<len(r.catalog_floor_textures) {half:=(box.w-6)*.5;floor_texture,wall_texture:=r.catalog_floor_textures[entry.catalog_index],r.catalog_wall_textures[entry.catalog_index];if floor_texture>=0 do vulkan_ui_quad(r,box.x+3,box.y+3,half,48,{255,255,255,255},floor_texture,{}, {1,1},true);if wall_texture>=0 do vulkan_ui_quad(r,box.x+3+half,box.y+3,half,48,{255,255,255,255},wall_texture,{}, {1,1},true)}}

vk_draw_editor_catalog :: proc(r:^Vulkan_Backend,g:^Game) {
	catalog_clamp_page(&editor_state);footer:=editor_catalog_footer_y();bottom:=editor_catalog_panel_bottom(g.build_tool);vk_editor_surface(r,{74,194,284,bottom-194},true)
	categories:=[4]string{"all",g.build_tool==.Plant?"objects":"materials","recent","pinned"};vk_tab_bar_surface(r,{86,198,255,36});for category,i in categories {box:=Rect{86+f32(i)*65,202,60,28};vk_tab_surface(r,box,category=="pinned"?"PIN":strings.to_upper(category),editor_state.catalog_category==category,contains(box,editor_ui_mouse))}
	search_text:=catalog_search_text(&editor_state);vk_editor_pill(r,editor_catalog_search_rect(),search_text==""?(editor_state.search_active?"SEARCH  |":"SEARCH  [ / ]"):fmt.tprintf("SEARCH  %s%s",strings.to_upper(search_text),editor_state.search_active?"|":""),editor_state.search_active);vk_editor_pill(r,editor_catalog_search_clear_rect(),"X",search_text!="")
	if editor_state.search_active&&search_text!=""&&catalog_match_count(&editor_state)>0 {vk_panel(r,370,238,214,30);vk_editor_text(r,382,247,"ENTER SELECTS FIRST RESULT",{117,229,169,255},.60)}
	catalog_clamp_page(&editor_state);shown,matched:=0,0;start:=editor_state.catalog_page*9
	for entry in editor_catalog.entries {
		if !catalog_entry_matches(entry,&editor_state) do continue
		if matched>=start&&shown<9 {box:=editor_catalog_card_rect(shown);on:=entry.id==editor_state.catalog_id;vulkan_ui_rect(r,box.x,box.y,box.w,box.h,on?[4]u8{67,130,151,255}:[4]u8{238,235,221,245});vk_catalog_thumbnail(r,entry,box);vulkan_ui_rect(r,box.x+3,box.y+49,box.w-6,18,{15,20,25,245});card_ok:=entry.valid&&!entry.thumbnail_missing&&!entry.thumbnail_stale;outline:=card_ok?[4]u8{160,165,155,255}:entry.thumbnail_stale?[4]u8{255,211,92,255}:[4]u8{255,144,119,255};vulkan_ui_outline(r,box.x,box.y,box.w,box.h,on?[4]u8{107,206,235,255}:outline,on?3:1);if entry.thumbnail_missing do vk_editor_text(r,box.x+box.w-14,box.y+6,"!",{255,144,119,255},.60);if entry.thumbnail_stale do vk_editor_text(r,box.x+box.w-17,box.y+6,"R",{255,211,92,255},.48);pinned:=catalog_is_pinned(&editor_state,entry.id);pin:=editor_catalog_pin_rect(shown);vulkan_ui_rect(r,pin.x,pin.y,pin.w,pin.h,pinned?[4]u8{255,218,112,245}:[4]u8{20,28,34,220});vulkan_ui_outline(r,pin.x,pin.y,pin.w,pin.h,pinned?[4]u8{255,245,190,255}:[4]u8{205,207,210,220},1);vk_editor_text(r,pin.x+5,pin.y+1,"*",pinned?[4]u8{20,28,34,255}:[4]u8{255,218,112,255},.66);vk_editor_action_tooltip(r,pin,pinned?"UNPIN FROM SESSION SHELF":"PIN FOR THIS EDITING SESSION",g.input.mouse_pos);label:=strings.to_upper(entry.id);if len(label)>11 do label=label[:11];vk_editor_text(r,box.x+5,box.y+52,label,entry.valid?[4]u8{255,255,255,255}:[4]u8{255,144,119,255},.60);if contains(box,g.input.mouse_pos)&&!contains(pin,g.input.mouse_pos) {status:=entry.valid?(entry.thumbnail_missing?"PREVIEW MISSING":entry.thumbnail_stale?"PREVIEW OUTDATED":strings.to_upper(entry.category)):"ASSET UNAVAILABLE";status_color:=entry.valid?(entry.thumbnail_missing||entry.thumbnail_stale?[4]u8{255,211,92,255}:[4]u8{205,207,210,255}):[4]u8{255,144,119,255};detail_width:=max(f32(150),f32(max(utf8_glyph_count(entry.id),utf8_glyph_count(status)))*7+20);vk_panel(r,370,box.y,detail_width,42);vk_editor_text(r,380,box.y+6,strings.to_upper(entry.id),{255,255,255,255},.60);vk_editor_text(r,380,box.y+23,status,status_color,.52)};shown+=1}
		matched+=1
	}
	if shown==0 {query:=catalog_search_text(&editor_state);empty_label:=query!=""?"NO SEARCH RESULTS":editor_state.catalog_category=="recent"?"NO RECENT ASSETS":editor_state.catalog_category=="pinned"?"NO PINNED ASSETS":"NO ASSETS AVAILABLE";vk_editor_text(r,98,292,empty_label,query!=""?[4]u8{255,144,119,255}:[4]u8{205,207,210,255},.52);if query!="" do vk_button(r,editor_catalog_empty_action_rect(),"CLEAR SEARCH",true)}
	pages:=catalog_page_count(&editor_state);vk_editor_pill(r,{86,footer,38,30},"<",false,editor_state.catalog_page>0);vk_editor_pill(r,{132,footer,168,30},fmt.tprintf("%d-%d OF %d",matched==0?0:start+1,min(start+shown,matched),matched));vk_editor_pill(r,{308,footer,38,30},">",false,editor_state.catalog_page+1<pages)
	if g.build_tool==.Plant {actions_y:=footer+38;if g.catalog_thumbnail_baking {vk_button(r,{86,actions_y,260,30},g.catalog_thumbnail_status,true)} else {vk_button(r,{86,actions_y,126,30},"RENDER ITEM");vk_button(r,{220,actions_y,126,30},"UPDATE PREVIEWS")}}
}
portrait_art :: proc(id:string)->UI_Art {switch id {case "miriam":return .Portrait_Miriam;case "daniel":return .Portrait_Daniel;case "elsie":return .Portrait_Elsie;case:return .Portrait_Edgar}}
mini_actor_art :: proc(id:string)->UI_Art {switch id {case "miriam":return .Mini_Miriam;case "daniel":return .Mini_Daniel;case "elsie":return .Mini_Elsie;case:return .Mini_Edgar}}
vk_text_wrapped :: proc(r:^Vulkan_Backend,x,y,max_width:f32,value:string,color:=[4]u8{248,247,242,255},scale:f32=1.25,line_spacing:f32=4)->f32 {
	if value=="" do return y
	line_height:=f32(COURIER_CELL_HEIGHT)*scale+line_spacing;cursor_y:=y;plan:=text_layout_plan(value,text_layout_columns(max_width,f32(COURIER_CELL_WIDTH)*scale))
	for line in plan {vk_text(r,x,cursor_y,value[line.start:line.end],color,scale);cursor_y+=line_height}
	return cursor_y
}
vk_panel :: proc(r:^Vulkan_Backend,x,y,w,h:f32) {
	// Opaque, layered surfaces keep copy readable over both bright exterior shots
	// and the darker house. The inset highlight gives panels a console-card feel.
	vulkan_ui_rect(r,x+6,y+8,w,h,UI_SHADOW)
	vulkan_ui_rect(r,x,y,w,h,UI_SURFACE)
	texture:=vulkan_ui_art_texture(r,.Theme_Materials);if texture>=0 do vulkan_ui_quad(r,x+2,y+2,w-4,h-4,{96,91,80,68},texture,{0,0},{.5,.5},true)
	vulkan_ui_outline(r,x,y,w,h,UI_BORDER_STRONG,1)
	// One pair of registration corners carries the case-board motif without
	// surrounding every content region in a second decorative frame.
	corner:=f32(18);weight:=f32(2);c:=UI_ACCENT_DARK
	vulkan_ui_rect(r,x,y,corner,weight,c);vulkan_ui_rect(r,x,y,weight,corner,c)
	vulkan_ui_rect(r,x+w-corner,y+h-weight,corner,weight,c);vulkan_ui_rect(r,x+w-weight,y+h-corner,weight,corner,c)
}

UI_SPOTLIGHT_MAX_FOCI :: 4
vk_ui_spotlight :: proc(r:^Vulkan_Backend,focuses:[]Rect,dim_alpha:u8=178,padding:f32=8,outline_color:=[4]u8{255,211,92,0}) {
	// Split the screen at every focus edge and dim only cells outside all focus
	// rectangles. Existing widgets remain bright through the resulting holes,
	// so tutorials do not need a second rendering path for highlighted controls.
	count:=min(len(focuses),UI_SPOTLIGHT_MAX_FOCI);if count<=0 {vulkan_ui_rect(r,0,0,WINDOW_WIDTH,WINDOW_HEIGHT,{5,7,11,dim_alpha});return}
	expanded:[UI_SPOTLIGHT_MAX_FOCI]Rect;xs,ys:[UI_SPOTLIGHT_MAX_FOCI*2+2]f32;xs[0]=0;xs[1]=WINDOW_WIDTH;ys[0]=0;ys[1]=WINDOW_HEIGHT;xn,yn:=2,2
	for i in 0..<count {box:=focuses[i];left:=clamp(box.x-padding,0,WINDOW_WIDTH);top:=clamp(box.y-padding,0,WINDOW_HEIGHT);right:=clamp(box.x+box.w+padding,0,WINDOW_WIDTH);bottom:=clamp(box.y+box.h+padding,0,WINDOW_HEIGHT);expanded[i]={left,top,right-left,bottom-top};xs[xn]=left;xs[xn+1]=right;ys[yn]=top;ys[yn+1]=bottom;xn+=2;yn+=2}
	for i in 1..<xn {value:=xs[i];j:=i;for j>0&&xs[j-1]>value {xs[j]=xs[j-1];j-=1};xs[j]=value};for i in 1..<yn {value:=ys[i];j:=i;for j>0&&ys[j-1]>value {ys[j]=ys[j-1];j-=1};ys[j]=value}
	for yi in 0..<yn-1 {for xi in 0..<xn-1 {x0,x1,y0,y1:=xs[xi],xs[xi+1],ys[yi],ys[yi+1];if x1<=x0||y1<=y0 do continue;cx,cy:=(x0+x1)*.5,(y0+y1)*.5;inside:=false;for i in 0..<count {box:=expanded[i];if cx>=box.x&&cx<=box.x+box.w&&cy>=box.y&&cy<=box.y+box.h do inside=true};if !inside do vulkan_ui_rect(r,x0,y0,x1-x0,y1-y0,{5,7,11,dim_alpha})}}
	// Three chunky alpha steps soften the cutout without abandoning the game's
	// pixel-grid language or requiring a blur pass.
	for i in 0..<count {box:=expanded[i];for step in 0..<3 {inset:=f32(step)*4;alpha:=u8((3-step)*10);vulkan_ui_outline(r,box.x+inset,box.y+inset,max(0,box.w-inset*2),max(0,box.h-inset*2),{5,7,11,alpha},4)}}
	if outline_color[3]>0 do for i in 0..<count {box:=expanded[i];vulkan_ui_outline(r,box.x,box.y,box.w,box.h,outline_color,2)}
}

vk_focused_button: ui.Gui_Id

// Tabs share one recessed rail instead of reading as a row of unrelated
// action buttons. The active page rises slightly and opens into the content
// below; focus remains a separate gold cue for keyboard/gamepad navigation.
vk_tab_bar :: proc(r:^Vulkan_Backend,box:Rect) {
	vk_tab_bar_surface(r,box)
}

vk_tab :: proc(r:^Vulkan_Backend,box:Rect,label:string,active:=false) {
	vk_tab_surface(r,box,label,active,vk_focused_button==button_id(box))
}

vk_button_surface :: proc(r:^Vulkan_Backend,box:Rect,label:string,selected,primary:bool) {
	// Selection communicates persistent choice. Primary communicates action
	// hierarchy. Focus remains transient input location and is intentionally
	// independent from both.
	focused:=vk_focused_button==button_id(box)
	is_previous:=label=="<"||label=="‹"
	is_next:=label==">"||label=="›"
	vulkan_ui_rect(r,box.x+4,box.y+5,box.w,box.h,UI_SHADOW)
	color:=focused?UI_SURFACE_HOVER:selected?UI_ACCENT_SOFT:primary?UI_ACCENT_SOFT:UI_SURFACE_RAISED;vulkan_ui_rect(r,box.x,box.y,box.w,box.h,color)
	if focused {rail_width:=f32(9);vulkan_ui_rect(r,is_next?box.x+box.w-rail_width:box.x,box.y,rail_width,box.h,UI_ACCENT)}
	vulkan_ui_outline(r,box.x,box.y,box.w,box.h,focused?UI_ACCENT:primary?UI_ACCENT_DARK:UI_BORDER_STRONG,focused?f32(4):primary?f32(2):f32(1))
	// Selection gets its own shape marker; focus remains the heavy gold rail.
	if selected&&!focused {vulkan_ui_rect(r,box.x+11,box.y+box.h*.5-3,6,6,UI_INK_STRONG);vulkan_ui_rect(r,box.x+box.w-5,box.y+5,3,box.h-10,UI_ACCENT)}
	if is_previous||is_next {center:=Vec2{box.x+box.w*.5,box.y+box.h*.5};half:=min(box.w,box.h)*.18;if is_previous do vulkan_ui_triangle(r,{center.x+half,center.y-half},{center.x-half,center.y},{center.x+half,center.y+half},{248,247,242,255});else do vulkan_ui_triangle(r,{center.x-half,center.y-half},{center.x+half,center.y},{center.x-half,center.y+half},{248,247,242,255});return}
	text_inset:=selected&&!focused?f32(30):f32(16);right_inset:=selected&&!focused?f32(14):f32(16)
	scale:f32=1.3;glyphs:=utf8_glyph_count(label);if glyphs>0 do scale=min(scale,max((box.w-text_inset-right_inset)/(f32(glyphs)*COURIER_CELL_WIDTH),.72));vk_text(r,box.x+text_inset,box.y+(box.h-f32(COURIER_CELL_HEIGHT)*scale)/2,label,selected||primary||focused?UI_INK_STRONG:UI_INK,scale)
}

// Use selected only when the control represents the current persistent choice
// (tab, mode, toggle, chosen item). Action hierarchy belongs here instead.
vk_button :: proc(r:^Vulkan_Backend,box:Rect,label:string,selected:=false) {
	vk_button_surface(r,box,label,selected,false)
}

vk_primary_button :: proc(r:^Vulkan_Backend,box:Rect,label:string,primary:=true) {
	vk_button_surface(r,box,label,false,primary)
}

vk_danger_button :: proc(r:^Vulkan_Backend,box:Rect,label:string) {
	focused:=vk_focused_button==button_id(box)
	vulkan_ui_rect(r,box.x+4,box.y+5,box.w,box.h,UI_SHADOW)
	vulkan_ui_rect(r,box.x,box.y,box.w,box.h,focused?UI_SURFACE_HOVER:UI_SURFACE_RAISED)
	vulkan_ui_outline(r,box.x,box.y,box.w,box.h,UI_DANGER,focused?f32(4):f32(2))
	if focused do vulkan_ui_rect(r,box.x,box.y,9,box.h,UI_DANGER)
	scale:f32=1.3;glyphs:=utf8_glyph_count(label);if glyphs>0 do scale=min(scale,max((box.w-32)/(f32(glyphs)*COURIER_CELL_WIDTH),.72))
	vk_text(r,box.x+16,box.y+(box.h-f32(COURIER_CELL_HEIGHT)*scale)/2,label,UI_DANGER,scale)
}
vk_graph_button :: proc(r:^Vulkan_Backend,box:Rect,label:string,on:=false) {
	focused:=vk_focused_button==button_id(box);vulkan_ui_rect(r,box.x+4,box.y+5,box.w,box.h,UI_SHADOW)
	color:=focused?UI_SURFACE_HOVER:on?UI_ACCENT_SOFT:UI_SURFACE_RAISED;vulkan_ui_rect(r,box.x,box.y,box.w,box.h,color)
	if focused do vulkan_ui_rect(r,box.x,box.y,9,box.h,UI_ACCENT)
	vulkan_ui_outline(r,box.x,box.y,box.w,box.h,focused?UI_ACCENT:UI_BORDER_STRONG,focused?f32(4):f32(1))
	if on&&!focused {vulkan_ui_rect(r,box.x+11,box.y+box.h*.5-3,6,6,UI_INK_STRONG);vulkan_ui_rect(r,box.x+box.w-5,box.y+5,3,box.h-10,UI_ACCENT)}
	text_inset:=on&&!focused?f32(30):f32(16);right_inset:=on&&!focused?f32(14):f32(16);scale:f32=1.3;glyphs:=utf8_glyph_count(label)
	if glyphs>0 do scale=min(scale,max((box.w-text_inset-right_inset)/(f32(glyphs)*COURIER_CELL_WIDTH),.72))
	vulkan_ui_system_text(r,box.x+text_inset,box.y+(box.h-f32(COURIER_CELL_HEIGHT)*scale)/2,label,on||focused?UI_INK_STRONG:UI_INK,scale)
}
vk_graph_tab :: proc(r:^Vulkan_Backend,box:Rect,label:string,active:=false) {
	vk_tab_surface(r,box,label,active,vk_focused_button==button_id(box))
}
vk_graph_tab_bar :: proc(r:^Vulkan_Backend,box:Rect) {
	vk_tab_bar_surface(r,box)
}
vk_compact_button :: proc(r:^Vulkan_Backend,box:Rect,label:string,on:=false) {
	focused:=vk_focused_button==button_id(box)
	vulkan_ui_rect(r,box.x+4,box.y+5,box.w,box.h,{0,0,0,120});vulkan_ui_rect(r,box.x,box.y,box.w,box.h,focused?[4]u8{58,62,73,255}:on?[4]u8{74,57,20,255}:[4]u8{40,46,58,255})
	if on||focused do vulkan_ui_rect(r,box.x,box.y,6,box.h,{255,211,92,255})
	vulkan_ui_outline(r,box.x,box.y,box.w,box.h,on||focused?[4]u8{255,211,92,255}:[4]u8{148,155,168,255},on||focused?3:2)
	glyphs:=utf8_glyph_count(label);scale:f32=.78;if glyphs>0 do scale=min(scale,(box.w-16)/(f32(glyphs)*COURIER_CELL_WIDTH));scale=max(scale,EDITOR_MIN_TEXT_SCALE)
	vk_editor_text(r,box.x+8,box.y+(box.h-f32(COURIER_CELL_HEIGHT)*scale)/2,label,{255,255,255,255},scale)
}
vk_dialogue_choice_surface :: proc(r:^Vulkan_Backend,box:Rect,focused:bool) {
	if focused {
		vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{38,43,52,248});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,{255,211,92,235},2);vulkan_ui_rect(r,box.x,box.y,5,box.h,{255,211,92,255})
	} else {
		vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{22,27,34,150});vulkan_ui_rect(r,box.x,box.y+box.h-1,box.w,1,{118,124,134,145});vulkan_ui_rect(r,box.x,box.y,2,box.h,{180,156,96,150})
	}
}
vk_dialogue_status_surface :: proc(r:^Vulkan_Backend,box:Rect,accent:[4]u8) {
	vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{20,24,31,232});vulkan_ui_outline(r,box.x,box.y,box.w,box.h,accent,1);vulkan_ui_rect(r,box.x,box.y,5,box.h,accent)
	// Semantic notch patterns provide a non-color cue: info=one, success=two,
	// warning=three, danger=four. They remain visible in monochrome captures.
	notches:=1;if accent==UI_SUCCESS do notches=2;else if accent==UI_WARNING do notches=3;else if accent==UI_DANGER do notches=4
	for i in 0..<notches do vulkan_ui_rect(r,box.x+11+f32(i)*8,box.y+6,5,3,accent)
}

vk_dialogue_object_check_choice :: proc(r:^Vulkan_Backend,g:^Game,box:Rect,clue_index:int,focused:bool) {
	payload:=mystery_game_payload(g);if payload==nil||clue_index<0||clue_index>=len(payload.clues) do return;vk_dialogue_choice_surface(r,box,focused);clue:=&payload.clues[clue_index];_,_,skill_color:=skill_helper(clue.skill);kind_color:=clue.check_kind=="red"?[4]u8{255,144,119,255}:[4]u8{155,201,255,255}
	number:=text_effect_default({255,211,92,255},.9);skill:=text_effect_default(skill_color,.78);skill.letter_spacing=1;kind:=text_effect_default(kind_color,.72);meta:=text_effect_default({205,207,210,255},.68)
	modifier:=check_modifier(skill_index(clue.skill),clue_evidence_bonus(g,clue_index),clue_disposition(g,clue_index),clue_situational_bonus(g,clue_index));chance:=check_success_percent(check_target(clue.difficulty),modifier);odds:=text_effect_default(ui_success_chance_color(chance),.72);cost:=clue_action_cost(g,clue_index);_=vk_rich_text(r,box.x+17,box.y+8,[]Text_Span{{fmt.tprintf("%s  ",dialogue_choice_marker(g,0)),number},{strings.to_upper(clue.skill),skill},{fmt.tprintf("  %d%%",chance),odds},{fmt.tprintf("  %s",check_retry_label(clue.check_kind)),kind},{fmt.tprintf("   %s",dialogue_tick_cost_label(cost)),meta}},g.animation_time)
	body:=text_effect_default({248,247,242,255},.9);body.shadow_color={0,0,0,180};body.shadow_offset={1,1};_=vk_text_effect_wrapped(r,box.x+48,box.y+30,box.w-64,strings.to_upper(clue.description),body,g.animation_time,2)
}

vk_dialogue_approach_choice :: proc(r:^Vulkan_Backend,g:^Game,box:Rect,index,slot:int,focused:bool) {
	payload:=mystery_game_payload(g);node:=mystery_dialogue_approach_at(payload,index);if node==nil do return
	if focused {vulkan_ui_rect(r,box.x+11,box.y+4,3,box.h-8,{255,211,92,255});vulkan_ui_rect(r,box.x+18,box.y+box.h-1,box.w-36,1,{255,211,92,100})}
	number:=text_effect_default({255,211,92,255},.9);number.letter_spacing=1
	if node.clue_id=="" {_=vk_rich_text(r,box.x+17,box.y+10,[]Text_Span{{dialogue_choice_marker(g,slot),number}},g.animation_time);body:=text_effect_default({248,247,242,255},.9);body.shadow_color={0,0,0,180};body.shadow_offset={1,1};_=vk_text_effect_wrapped(r,box.x+48,box.y+10,box.w-64,dialogue_semantic_text(node.prompt,"choice"),body,g.animation_time,2);return}
	clue_index:=dialogue_check_clue_index(g,index);if clue_index<0 do return;clue:=&payload.clues[clue_index];_,_,skill_color:=skill_helper(clue.skill);kind_color:=clue.check_kind=="red"?[4]u8{255,144,119,255}:[4]u8{155,201,255,255}
	skill:=text_effect_default(skill_color,.78);skill.letter_spacing=1;skill.shadow_color={0,0,0,180};skill.shadow_offset={1,1};meta:=text_effect_default({205,207,210,255},.68);kind:=text_effect_default(kind_color,.72)
	modifier:=check_modifier(skill_index(clue.skill),clue_evidence_bonus(g,clue_index),clue_disposition(g,clue_index),clue_situational_bonus(g,clue_index));chance:=check_success_percent(check_target(clue.difficulty),modifier);odds:=text_effect_default(ui_success_chance_color(chance),.72);cost:=clue_action_cost(g,clue_index);_=vk_rich_text(r,box.x+17,box.y+8,[]Text_Span{{fmt.tprintf("%s  ",dialogue_choice_marker(g,slot)),number},{strings.to_upper(clue.skill),skill},{fmt.tprintf("  %d%%",chance),odds},{fmt.tprintf("  %s",check_retry_label(clue.check_kind)),kind},{fmt.tprintf("   %s",dialogue_tick_cost_label(cost)),meta}},g.animation_time)
	body:=text_effect_default({248,247,242,255},.9);body.shadow_color={0,0,0,180};body.shadow_offset={1,1};_=vk_text_effect_wrapped(r,box.x+48,box.y+30,box.w-64,dialogue_semantic_text(node.prompt,"choice"),body,g.animation_time,2)
}

vk_dialogue_evidence_choice :: proc(r:^Vulkan_Backend,g:^Game,box:Rect,clue_index,slot:int,focused:bool) {
	vk_dialogue_choice_surface(r,box,focused);source:=relevant_evidence_for_clue(g,clue_index);name:=source>=0?case_sense_source_name(g,source):"relevant evidence"
	number:=text_effect_default({255,211,92,255},.9);challenge:=text_effect_default({119,190,213,255},.74);challenge.letter_spacing=1;body:=text_effect_default({248,247,242,255},.9);body.shadow_color={0,0,0,180};body.shadow_offset={1,1}
	_=vk_rich_text(r,box.x+17,box.y+10,[]Text_Span{{fmt.tprintf("%s  ",dialogue_choice_marker(g,slot)),number},{"CHALLENGE  ·  ",challenge},{fmt.tprintf("Use %s",name),body}},g.animation_time)
}

dialogue_check_clue_index :: proc(g:^Game,node_index:int)->int {
	payload:=mystery_game_payload(g);node:=mystery_dialogue_approach_at(payload,node_index);if node==nil||node.clue_id=="" do return -1;return mystery_clue_index(payload,node.clue_id)
}

vk_draw_check_tooltip_clue :: proc(r:^Vulkan_Backend,g:^Game,clue_index:int,anchor:Rect) {
	payload:=mystery_game_payload(g);if payload==nil||clue_index<0||clue_index>=len(payload.clues) do return
	clue:=&payload.clues[clue_index];skill:=skill_index(clue.skill);evidence:=clue_evidence_bonus(g,clue_index);disposition:=clue_disposition(g,clue_index);presented:=clue_situational_bonus(g,clue_index)
	target:=check_target(clue.difficulty);modifier:=check_modifier(skill,evidence,disposition,presented);chance:=check_success_percent(target,modifier);cost:=clue_action_cost(g,clue_index);verdict_color:=[4]u8{255,211,92,255}
	person_check:=g.dialogue_entity>=0&&g.dialogue_entity<len(WORLD_ENTITIES)&&WORLD_ENTITIES[g.dialogue_entity].kind=="person";breakdown_rows:=2+(person_check?1:0)+(presented>0?1:0)
	target_y:=anchor.y+anchor.h*.5;x,w:=f32(310),f32(285);h:=f32(260+21*(breakdown_rows-2));y:=clamp(target_y-h*.5,f32(170),f32(710)-h);vk_panel(r,x,y,w,h)
	vulkan_ui_rect(r,x+2,y+2,w-4,40,verdict_color);vk_text(r,x+18,y+11,fmt.tprintf("%s  •  %s",strings.to_upper(clue.skill),check_retry_label(clue.check_kind)),{14,16,20,255},.92)
	vk_text(r,x+20,y+55,"ROLL TWO DICE",verdict_color,.9);vk_text(r,x+20,y+78,fmt.tprintf("2D6  %+d",modifier),{248,247,242,255},1.75);vk_text(r,x+20,y+115,dialogue_check_threshold_label(target),{255,211,92,255},.72);vk_text(r,x+166,y+117,fmt.tprintf("%d%% SUCCESS",chance),ui_success_chance_color(chance),.68)
	vulkan_ui_rect(r,x+20,y+137,w-40,1,{148,155,168,210})
	row_y:=y+f32(151);vk_text(r,x+20,row_y,fmt.tprintf("SKILL        %+d",skill),{248,247,242,255},.74);row_y+=21
	vk_text(r,x+20,row_y,fmt.tprintf("EVIDENCE     %+d",evidence),evidence>0?[4]u8{102,205,143,255}:[4]u8{205,207,210,255},.74);row_y+=21
	if person_check {vk_text(r,x+20,row_y,fmt.tprintf("DISPOSITION  %+d",disposition),disposition>0?[4]u8{102,205,143,255}:disposition<0?[4]u8{255,144,119,255}:[4]u8{205,207,210,255},.74);row_y+=21}
	if presented>0 {vk_text(r,x+20,row_y,fmt.tprintf("PRESENTED   +%d",presented/10),{102,205,143,255},.74);row_y+=21}
	cost_y:=row_y+8;vk_text(r,x+20,cost_y,dialogue_check_tooltip_cost(cost,max(0,g.ap-cost)),cost<=0?[4]u8{102,205,143,255}:verdict_color,.62)
	failure:=clue.check_kind=="red"?"YOU MAY TRY ONCE":"YOU MAY RETRY."
	_=vk_text_wrapped(r,x+20,cost_y+22,w-40,failure,verdict_color,.62,1)
	// A single leader meets the row's focus arrow without adding a second marker.
	card_edge:=x+w;vulkan_ui_rect(r,card_edge,target_y-2,anchor.x-card_edge-14,4,{255,211,92,255})
}
vk_draw_check_tooltip :: proc(r:^Vulkan_Backend,g:^Game,node_index:int,anchor:Rect) {vk_draw_check_tooltip_clue(r,g,dialogue_check_clue_index(g,node_index),anchor)}
