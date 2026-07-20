package main

import "core:fmt"
import "core:math"
import "core:strings"

dialogue_scene_for_source :: proc(g:^Game,source:string)->int {if g.story_project==nil do return -1;for scene,i in g.story_project.scenes do if scene.bound_entity==source do return i;return -1}
story_presentation_node :: proc(g:^Game)->^Story_Node {if !g.story_presentation.active||g.story_runtime==nil do return nil;return story_runtime_node(g.story_runtime)}
story_presentation_scene :: proc(g:^Game)->^Story_Scene {if g.story_project==nil||g.story_runtime==nil do return nil;index:=story_scene_index(g.story_project,g.story_runtime.current_scene);if index<0 do return nil;return &g.story_project.scenes[index]}
dialogue_scene_completed :: proc(g:^Game,id:string)->bool {return g.story_runtime!=nil&&story_state_history_index(g.story_runtime.state.completed_scenes[:],id)>=0}
dialogue_start_character_introduction :: proc(g:^Game,source:string)->bool {
	if g.story_project==nil||g.story_runtime==nil do return false
	id:=fmt.tprintf("scene_intro_%s",source);index:=story_scene_index(g.story_project,id)
	if index<0||dialogue_scene_completed(g,id) do return false
	return dialogue_start_scene(g,index)
}
dialogue_node_metadata :: proc(g:^Game,node:^Story_Node)->^Mystery_Dialogue_Metadata {if g.story_project==nil||node==nil do return nil;payload:=mystery_payload(g.story_project);if payload==nil do return nil;return mystery_dialogue_metadata(payload,node.id)}

conversation_transcript_append :: proc(g:^Game,speaker,text,kind,conversation_id:string) {
	if text=="" do return
	if g.conversation_transcript_count>=len(g.conversation_transcript) {for i in 1..<len(g.conversation_transcript) do g.conversation_transcript[i-1]=g.conversation_transcript[i];g.conversation_transcript_count=len(g.conversation_transcript)-1}
	g.conversation_transcript[g.conversation_transcript_count]={speaker=speaker,text=text,kind=kind,conversation_id=conversation_id};g.conversation_transcript_count+=1
}

dialogue_transcript_append :: proc(g:^Game,speaker,text,kind:string) {
	if text=="" do return
	s:=&g.story_presentation
	if s.transcript_count>=len(s.transcript) {for i in 1..<len(s.transcript) do s.transcript[i-1]=s.transcript[i];s.transcript_count=len(s.transcript)-1}
	conversation_id:="";if scene:=story_presentation_scene(g);scene!=nil do conversation_id=scene.bound_entity
	s.transcript[s.transcript_count]={speaker=speaker,text=text,kind=kind,conversation_id=conversation_id};s.transcript_count+=1
	conversation_transcript_append(g,speaker,text,kind,conversation_id)
}

dialogue_line_semantic :: proc(beat:^Story_Node)->string {
	if beat==nil do return "dialogue"
	if beat.ui=="thought"||beat.speaker_id=="thought"||beat.speaker_id=="detective_thought" do return "thought"
	if beat.speaker_id=="narrator"||beat.speaker_id=="" do return "action"
	return "dialogue"
}

dialogue_semantic_label :: proc(g:^Game,speaker,kind:string)->string {
	switch kind {
	case "thought": return "DETECTIVE THOUGHT"
	case "action": return "ACTION / OBSERVATION"
	case "check": return "SKILL CHECK"
	case "choice": return "DETECTIVE  ·  SPOKEN"
	case: return fmt.tprintf("%s  ·  SPOKEN",strings.to_upper(dialogue_speaker_name(g,speaker)))
	}
}

dialogue_semantic_color :: proc(kind:string,accent:[4]u8,opacity:f32)->[4]u8 {
	switch kind {
	case "thought": return dialogue_fade_color({202,164,255,255},opacity)
	case "action": return dialogue_fade_color({170,176,184,255},opacity)
	case "check": return dialogue_fade_color({102,205,143,255},opacity)
	case "choice": return dialogue_fade_color({119,190,213,255},opacity)
	case: return accent
	}
}

dialogue_semantic_text :: proc(text,kind:string)->string {
	if kind!="dialogue"&&kind!="choice" do return text
	// Some authored beats already quote speech, including action followed by a
	// quotation. Preserve those exactly; add a readable outer pair only when the
	// whole beat is otherwise unmarked spoken dialogue.
	if len(text)>0&&(text[0]=='\''||text[0]=='"') do return text
	if strings.contains(text," '")||strings.contains(text," \"") do return text
	return fmt.tprintf("\"%s\"",text)
}

story_node_requirements_met :: proc(g:^Game,node:^Story_Node)->bool {if g.story_project==nil||g.mystery_state==nil||node==nil do return false;return mystery_node_requirements_met(g.story_project,g.mystery_state,node.id)}

dialogue_apply_beat_effects :: proc(g:^Game,node:^Story_Node) {if g.story_project!=nil&&g.mystery_state!=nil&&node!=nil do _=mystery_apply_node_metadata(g.story_project,g.mystery_state,node.id)}

dialogue_set_ui_presentation :: proc(g:^Game,value:string,duration:f32) {
	if value==""||value=="unchanged" do return
	s:=&g.story_presentation;s.ui_from=s.ui_opacity;s.ui_target=value=="hidden"?f32(0):f32(1);s.ui_transition=max(0,duration);s.ui_elapsed=0
	if s.ui_transition==0 do s.ui_opacity=s.ui_target
}

dialogue_goto :: proc(g:^Game,id:string)->bool {
	s:=&g.story_presentation;if !s.active||g.story_runtime==nil do return false
	if id=="" {dialogue_end_scene(g);return true}
	if story_node_index(&g.story_runtime.compiled.runtime,g.story_runtime.current_scene,id)<0 {s.error="Dialogue target is missing.";dialogue_end_scene(g);return false}
	g.story_runtime.current_node=id;s.step=story_runtime_present(g.story_runtime);if !s.step.ok {s.error=s.step.message;dialogue_end_scene(g);return false};s.beat_entered=false;s.beat_elapsed=0;s.interaction_active=false;s.camera_active=false;s.actor_entity=-1;g.focus_screen_initialized=false;return true
}

dialogue_start_scene :: proc(g:^Game,index:int)->bool {
	if g.story_project==nil||g.story_runtime==nil||index<0||index>=len(g.story_project.scenes) do return false
	scene:=&g.story_project.scenes[index];step:=story_runtime_enter_scene(g.story_runtime,scene.id);if !step.ok do return false
	g.story_presentation={active=true,step=step,scene=index,ui_opacity=1,ui_from=1,ui_target=1,actor_entity=-1}
	if entity:=world_entity_index(scene.bound_entity);entity>=0 do g.dialogue_entity=entity
	g.screen=.Dialogue;g.focus_screen=.Dialogue;g.focus_screen_initialized=false;return true
}

dialogue_start_source_scene :: proc(g:^Game,source:string)->bool {return dialogue_start_scene(g,dialogue_scene_for_source(g,source))}
dialogue_start_dialogue_approach_scene :: proc(g:^Game,approach:int)->bool {metadata:=mystery_dialogue_approach_at(mystery_game_payload(g),approach);if metadata==nil||g.story_project==nil do return false;return dialogue_start_scene(g,story_scene_index(g.story_project,fmt.tprintf("scene_%s",metadata.node_id)))}

dialogue_returns_to_exterior :: proc(g:^Game)->bool {
	scene:=story_presentation_scene(g);return scene!=nil&&g.story_presentation.active&&scene.return_to=="exterior"
}

dialogue_end_scene :: proc(g:^Game) {
	s:=&g.story_presentation;if !s.active do return
	scene:=story_presentation_scene(g);if scene==nil {s.active=false;return};summary:=scene.summary
	if beat:=story_presentation_node(g);beat!=nil&&beat.summary!="" do summary=beat.summary
	if summary!="" do log_line(g,summary)
	s.active=false;s.interaction_active=false;g.check_from_dialogue=false;g.check_done=false;g.focus_screen_initialized=false
	switch scene.return_to {case "board":g.screen=.Board;case "exterior":g.screen=.Exterior;case:g.screen=.Investigate}
}

dialogue_acquire_scene_item :: proc(g:^Game,scene:^Story_Scene) {
	switch scene.id {
	case "scene_search_wastebin":appointment_fragment_recover(g,"burned_note")
	case "scene_recover_memo_stub":appointment_fragment_recover(g,"memo_stub")
	case "scene_recover_desk_key":acquire_desk_key(g)
	case "scene_inspect_statuette":_=dialogue_interaction_acquire_item(g,.Statuette)
	case "scene_inspect_cloth":_=dialogue_interaction_acquire_item(g,.Cloth)
	case:
	}
}

dialogue_enter_interaction_beat :: proc(g:^Game,beat:^Story_Node) {
	item:=Dialogue_Interaction_Item.None
	interaction:="";if metadata:=dialogue_node_metadata(g,beat);metadata!=nil do interaction=metadata.interaction
	switch interaction {case "desk":item=.Desk;case "statuette":item=.Statuette;case "cloth":item=.Cloth;case:}
	if item!=.None {dialogue_interaction_enter(g,item);g.screen=.Dialogue;g.story_presentation.interaction_active=true}
}

dialogue_enter_beat :: proc(g:^Game) {
	s:=&g.story_presentation;beat:=story_presentation_node(g);if beat==nil do return
	s.beat_entered=true;s.beat_elapsed=0;if beat.kind==.Choice do g.dialogue_choice_page=0;dialogue_set_ui_presentation(g,beat.ui,beat.transition)
	if beat.kind==.Line {dialogue_transcript_append(g,beat.speaker_id,beat.text,dialogue_line_semantic(beat));if character_index(g,beat.speaker_id)>=0 do trigger_character_interact(g,beat.speaker_id)}
	if beat.kind==.Interaction do dialogue_enter_interaction_beat(g,beat)
	if beat.kind==.Check {if metadata:=dialogue_node_metadata(g,beat);metadata!=nil {payload:=mystery_game_payload(g);if payload!=nil {i:=mystery_clue_index(payload,metadata.clue_id);if i>=0 {g.pending_clue=i;g.check_preview=check_target(payload.clues[i].difficulty);g.check_done=false;g.check_from_dialogue=true;g.check_disposition_delta=0}}}}
	if beat.kind==.Stage {
		if beat.actor!=""&&beat.animation!="" do trigger_character_interact(g,beat.actor)
		if beat.camera!="" {index:=level_marker_index(&level_document,beat.camera);if index>=0 {marker:=level_document.markers[index];s.camera_active=true;s.camera_start={g.camera_x,g.camera_y};s.camera_target=marker.position;s.camera_orbit_start=g.camera_orbit;s.camera_orbit_target=marker.facing*f32(math.PI/180)}}
		if beat.actor!=""&&beat.actor_mark!="" {entity:=world_entity_index(beat.actor);mark:=level_marker_index(&level_document,beat.actor_mark);if entity>=0&&mark>=0 {s.actor_entity=entity;s.actor_start={WORLD_ENTITIES[entity].x,WORLD_ENTITIES[entity].y};s.actor_target=level_document.markers[mark].position}}
	}
	if beat.kind==.End {dialogue_apply_beat_effects(g,beat);scene:=story_presentation_scene(g);if scene!=nil do dialogue_acquire_scene_item(g,scene);ending:=beat.ending;_=story_runtime_advance(g.story_runtime);dialogue_end_scene(g);if ending!="" do _=enter_case_ending(g,ending)}
}

dialogue_interaction_complete :: proc(g:^Game,beat:^Story_Node)->bool {
	interaction:="";if metadata:=dialogue_node_metadata(g,beat);metadata!=nil do interaction=metadata.interaction
	switch interaction {case "desk":return g.desk_open;case "statuette":return g.study_seam_found;case "cloth":return strings.contains(g.dialogue_interaction.ledger,"EXAMINED");case "shutter":return g.shutter_operated;case "body":return g.desk_key_found;case "watch":clue:=clue_for_source(g,"edgar_watch");return clue>=0&&mystery_game_clue_discovered(g,clue);case:}
	return false
}

dialogue_complete_current :: proc(g:^Game,target:string) {
	beat:=story_presentation_node(g);if beat==nil do return
	step:=Story_Runtime_Step{}
	#partial switch beat.kind {case .Choice:for choice in beat.choices[:beat.choice_count] do if choice.target==target {step=story_runtime_choose(g.story_runtime,choice.id);break};case .Check,.Interaction:result:="cancel";if target==beat.success do result="success";else if target==beat.failure do result="failure";step=story_runtime_resolve(g.story_runtime,result);case:step=story_runtime_advance(g.story_runtime)}
	if step.finished {dialogue_end_scene(g);return};if !step.ok {g.story_presentation.error=step.message;dialogue_end_scene(g);return};g.story_presentation.step=step;g.story_presentation.beat_entered=false;g.story_presentation.beat_elapsed=0;g.story_presentation.interaction_active=false;g.story_presentation.camera_active=false;g.story_presentation.actor_entity=-1;g.focus_screen_initialized=false
}
cinematic_transcript_end :: proc(g:^Game,beat:^Story_Node)->int {result:=g.story_presentation.transcript_count;if beat!=nil&&beat.kind==.Line&&result>0 do result-=1;return result}
cinematic_choice_rect :: proc(g:^Game,index:int)->Rect {return {650,488+f32(index)*60,490,54}}
cinematic_choice_prev_rect :: proc(g:^Game)->Rect {return {1018,462,30,20}}
cinematic_choice_next_rect :: proc(g:^Game)->Rect {return {1074,462,30,20}}
cinematic_choice_page_count :: proc(beat:^Story_Node)->int {if beat==nil do return 1;return max(1,(beat.choice_count+DIALOGUE_RESPONSES_PER_PAGE-1)/DIALOGUE_RESPONSES_PER_PAGE)}
cinematic_choice_visible_count :: proc(g:^Game,beat:^Story_Node)->int {pages:=cinematic_choice_page_count(beat);g.dialogue_choice_page=clamp(g.dialogue_choice_page,0,pages-1);return clamp(beat.choice_count-g.dialogue_choice_page*DIALOGUE_RESPONSES_PER_PAGE,0,DIALOGUE_RESPONSES_PER_PAGE)}
cinematic_continue_rect :: proc(g:^Game)->Rect {return {650,596,490,44}}
cinematic_leave_rect :: proc(beat:^Story_Node)->Rect {return {650,654,490,28}}
cinematic_can_leave :: proc(g:^Game)->bool {beat:=story_presentation_node(g);return beat!=nil&&!beat.blocking}
cinematic_default_rect :: proc(g:^Game)->Rect {beat:=story_presentation_node(g);if beat!=nil&&beat.kind==.Choice do return cinematic_choice_rect(g,0);if beat!=nil&&beat.kind==.Interaction do return dialogue_interaction_action_rect();return cinematic_continue_rect(g)}

update_cinematic_dialogue :: proc(g:^Game)->bool {
	s:=&g.story_presentation;if !s.active do return false
	graph_debugger_update_editor_toggle(g);update_graph_debugger(g);if !graph_state.playtesting&&g.editor_mode==.Graph do return true
	before:="";if beat:=story_presentation_node(g);beat!=nil do before=beat.id
	if !graph_debugger_before_update(g) do return true
	defer graph_debugger_after_update(g,before)
	dt:=f32(FIXED_TIMESTEP)
	if s.ui_opacity!=s.ui_target {s.ui_elapsed+=dt;t:=s.ui_transition<=0?f32(1):clamp(s.ui_elapsed/s.ui_transition,0,1);smooth:=t*t*(3-2*t);s.ui_opacity=s.ui_from+(s.ui_target-s.ui_from)*smooth}
	if !s.beat_entered do dialogue_enter_beat(g)
	beat:=story_presentation_node(g);if beat==nil||!s.active do return true
	s.beat_elapsed+=dt
	if beat.kind==.Stage {
		cue_duration:=beat.duration;if cue_duration<=0&&(s.camera_active||s.actor_entity>=0) do cue_duration=max(beat.transition,f32(.5));progress:=cue_duration<=0?f32(1):clamp(s.beat_elapsed/cue_duration,0,1);smooth:=progress*progress*(3-2*progress)
		if s.camera_active {g.camera_x=s.camera_start.x+(s.camera_target.x-s.camera_start.x)*smooth;g.camera_y=s.camera_start.y+(s.camera_target.y-s.camera_start.y)*smooth;g.camera_orbit=s.camera_orbit_start+(s.camera_orbit_target-s.camera_orbit_start)*smooth}
		if s.actor_entity>=0 {WORLD_ENTITIES[s.actor_entity].x=s.actor_start.x+(s.actor_target.x-s.actor_start.x)*smooth;WORLD_ENTITIES[s.actor_entity].y=s.actor_start.y+(s.actor_target.y-s.actor_start.y)*smooth}
		finished:=cue_duration<=0||s.beat_elapsed>=cue_duration
		if g.input.activate do finished=true
		if finished {if s.camera_active {g.camera_x=s.camera_target.x;g.camera_y=s.camera_target.y;g.camera_orbit=s.camera_orbit_target};if s.actor_entity>=0 {WORLD_ENTITIES[s.actor_entity].x=s.actor_target.x;WORLD_ENTITIES[s.actor_entity].y=s.actor_target.y};dialogue_complete_current(g,beat.next)}
		return true
	}
	if beat.kind!=.Interaction&&cinematic_can_leave(g)&&button(g,cinematic_leave_rect(beat)) {dialogue_end_scene(g);return true}
	if beat.kind==.Line {if s.ui_opacity>.95&&(g.input.activate||button(g,cinematic_continue_rect(g))) do dialogue_complete_current(g,beat.next);return true}
	if beat.kind==.Choice {
		pages:=cinematic_choice_page_count(beat);if pages>1 {page_delta:=0;if g.input.mouse_pos.x>=625&&g.input.mouse_pos.y>=457 {if g.input.mouse_wheel>0 do page_delta=-1;if g.input.mouse_wheel<0 do page_delta=1};if button(g,cinematic_choice_prev_rect(g)) do page_delta=-1;if button(g,cinematic_choice_next_rect(g)) do page_delta=1;if page_delta!=0 {g.dialogue_choice_page=(g.dialogue_choice_page+pages+page_delta)%pages;g.gui.focused=button_id(cinematic_choice_rect(g,0))}}
		visible:=cinematic_choice_visible_count(g,beat);start:=g.dialogue_choice_page*DIALOGUE_RESPONSES_PER_PAGE;for local in 0..<visible {i:=start+local;choice:=beat.choices[i];if button(g,cinematic_choice_rect(g,local))||dialogue_shortcut_selected(g,local)||g.input.activate&&local==0 {dialogue_transcript_append(g,"detective",choice.label,"choice");dialogue_complete_current(g,choice.target);break}}
		return true
	}
	if beat.kind==.Interaction {
		update_dialogue_interaction(g);if !g.story_presentation.active do return true;g.screen=.Dialogue
		if dialogue_interaction_complete(g,beat) {dialogue_transcript_append(g,"investigation",g.dialogue_interaction.ledger,"interaction");dialogue_complete_current(g,beat.success)}
		return true
	}
	if beat.kind==.Check {
		payload:=mystery_game_payload(g);if payload==nil||g.pending_clue<0||g.pending_clue>=len(payload.clues) {dialogue_complete_current(g,beat.failure);return true}
		if !g.check_done {if g.input.activate||button(g,cinematic_continue_rect(g)) {g.check_result=resolve_clue_check(g,g.pending_clue);g.screen=.Dialogue;g.check_roll_started=g.animation_time;g.check_result_cue_played=false;play_check_dice_sound(g);g.check_done=true};return true}
		update_check_result_cue(g);if g.animation_time-g.check_roll_started>=CHECK_REVEAL_DURATION&&(g.input.activate||button(g,cinematic_continue_rect(g))) {success:=g.check_result.success;dialogue_transcript_append(g,"investigation",success?mystery_clue_proposition_text(g.story_project,&payload.clues[g.pending_clue]):"The check fails.","check");g.check_from_dialogue=false;g.check_done=false;dialogue_complete_current(g,success?beat.success:beat.failure)};return true
	}
	return true
}

dialogue_ui_interactive :: proc(g:^Game)->bool {return !g.story_presentation.active||g.story_presentation.ui_opacity>.95}

dialogue_speaker_name :: proc(g:^Game,id:string)->string {if id=="detective" do return "DETECTIVE";if id=="dispatch" do return "DISPATCH";if id=="narrator"||id=="" do return "SCENE";return character_display_name(g,id)}
dialogue_fade_color :: proc(color:[4]u8,opacity:f32)->[4]u8 {result:=color;result[3]=u8(clamp(int(f32(color[3])*opacity),0,255));return result}

vk_cinematic_response_action :: proc(r:^Vulkan_Backend,box:Rect,label:string,opacity:f32) {
	focused:=vk_focused_button==button_id(box);accent:=dialogue_fade_color({255,211,92,235},opacity);text_color:=dialogue_fade_color(focused?[4]u8{248,247,242,255}:[4]u8{182,188,196,255},opacity)
	if focused do vulkan_ui_rect(r,box.x,box.y,box.w,box.h,dialogue_fade_color({38,43,52,220},opacity))
	border:=dialogue_fade_color(focused?[4]u8{255,211,92,225}:[4]u8{112,118,128,155},opacity);vulkan_ui_outline(r,box.x,box.y,box.w,box.h,border,focused?f32(2):f32(1))
	if focused do vulkan_ui_rect(r,box.x,box.y,3,box.h,accent)
	vk_text(r,box.x+15,box.y+8,strings.to_upper(label),text_color,.58)
}

vk_draw_cinematic_dialogue :: proc(r:^Vulkan_Backend,g:^Game) {
	s:=&g.story_presentation;if !s.active do return
	beat:=story_presentation_node(g);if beat==nil do return
	opacity:=clamp(s.ui_opacity,0,1);if opacity<=.01 do return
	if s.interaction_active {vk_draw_dialogue_interaction(r,g);return}
	panel:=dialogue_fade_color({12,14,17,232},opacity);soft_panel:=dialogue_fade_color({12,14,17,226},opacity);edge:=dialogue_fade_color({105,108,112,178},opacity);primary:=dialogue_fade_color({248,247,242,255},opacity);muted:=dialogue_fade_color({205,207,210,255},opacity);accent:=dialogue_fade_color({255,218,112,255},opacity)
	vulkan_ui_rect(r,0,0,1200,720,{0,0,0,u8(118*opacity)})
	// Scripted beats share the ordinary conversation's single full-height shell.
	// Cinematic describes pacing and staging, not a separate dialogue screen.
	vulkan_ui_rect(r,625,26,540,668,soft_panel);vulkan_ui_outline(r,625,26,540,668,edge,1)
	transcript_end:=cinematic_transcript_end(g,beat);choice_context:=""
	if beat.kind==.Choice {choice_context=beat.text;if choice_context==""&&transcript_end>0 {transcript_end-=1;choice_context=s.transcript[transcript_end].text}}
	conversation_id:="";if scene:=story_presentation_scene(g);scene!=nil do conversation_id=scene.bound_entity
	shared_transcript:=beat.kind==.Line&&conversation_id!=""&&vk_draw_character_transcript(r,g,conversation_id)
	if beat.kind==.Line&&!shared_transcript {semantic:=dialogue_line_semantic(beat);semantic_color:=dialogue_semantic_color(semantic,accent,opacity);speaker_entity:=world_entity_index(beat.speaker_id);portrait:=semantic=="dialogue"&&speaker_entity>=0&&WORLD_ENTITIES[speaker_entity].kind=="person";line_x:=portrait?f32(746):f32(674);line_width:=portrait?f32(359):f32(431);if portrait do vk_dialogue_portrait(r,660,70,WORLD_ENTITIES[speaker_entity]);vulkan_ui_rect(r,line_x-14,75,3,17,semantic_color);vk_text(r,line_x,72,dialogue_semantic_label(g,beat.speaker_id,semantic),semantic_color,.68);_=vk_text_wrapped(r,line_x,102,line_width,dialogue_semantic_text(beat.text,semantic),semantic=="action"?muted:primary,semantic=="thought"?.78:.82,5)}
	if beat.kind==.Choice&&choice_context!="" {player_color:=dialogue_semantic_color("choice",accent,opacity);vulkan_ui_rect(r,660,75,3,17,player_color);vk_text(r,674,72,dialogue_semantic_label(g,"detective","choice"),player_color,.68);_=vk_text_wrapped(r,674,102,431,dialogue_semantic_text(choice_context,"choice"),primary,.74,4)}
	if beat.kind==.Check {payload:=mystery_game_payload(g);if payload!=nil&&g.pending_clue>=0&&g.pending_clue<len(payload.clues) {clue:=payload.clues[g.pending_clue];check_color:=dialogue_semantic_color("check",accent,opacity);vulkan_ui_rect(r,660,75,3,17,check_color);vk_text(r,674,72,fmt.tprintf("%s  ·  SKILL CHECK",strings.to_upper(clue.skill)),check_color,.68);_=vk_text_wrapped(r,674,102,431,clue.description,primary,.74,3);if g.check_done&&g.animation_time-g.check_roll_started>=CHECK_REVEAL_DURATION do vk_text(r,674,168,g.check_result.success?"CHECK SUCCEEDS":"CHECK FAILS",g.check_result.success?dialogue_fade_color({102,205,143,255},opacity):dialogue_fade_color({255,144,119,255},opacity),.82)}}
	if transcript_end>0&&!shared_transcript {entry:=s.transcript[transcript_end-1];entry_color:=dialogue_semantic_color(entry.kind,accent,opacity);vulkan_ui_rect(r,660,184,445,1,dialogue_fade_color({139,107,55,150},opacity));vk_text(r,660,196,"PREVIOUS TURN",muted,.46);vulkan_ui_rect(r,660,216,3,13,entry_color);vk_text(r,674,213,dialogue_semantic_label(g,entry.speaker,entry.kind),entry_color,.52);_=vk_text_wrapped(r,674,234,431,dialogue_semantic_text(entry.text,entry.kind),entry.kind=="action"?muted:primary,.60,2)}
	if beat.kind==.Choice do vk_text(r,660,466,"YOUR RESPONSE",muted,.60)
	if beat.kind==.Choice {pages:=cinematic_choice_page_count(beat);if pages>1 {prev:=cinematic_choice_prev_rect(g);next:=cinematic_choice_next_rect(g);vk_dialogue_page_nav(r,prev,next,g.dialogue_choice_page,pages,468,muted)};visible:=cinematic_choice_visible_count(g,beat);start:=g.dialogue_choice_page*DIALOGUE_RESPONSES_PER_PAGE;for local in 0..<visible {i:=start+local;box:=cinematic_choice_rect(g,local);vk_dialogue_choice_surface(r,box,g.gui.focused==button_id(box));vk_text(r,668,box.y+17,fmt.tprintf("%d.",i+1),accent,.68);_=vk_text_wrapped(r,704,box.y+9,418,beat.choices[i].label,primary,.64,2)}}
	if beat.kind==.Line||beat.kind==.Check {box:=cinematic_continue_rect(g);label:=beat.kind==.Check?(g.check_done?"Continue":"Roll check"):"Continue";vk_cinematic_response_action(r,box,label,opacity)}
	if cinematic_can_leave(g) {leave:=cinematic_leave_rect(beat);vk_dialogue_end_choice(r,leave);vk_prompt_icon(r,g,.Back,leave.x+leave.w-27,leave.y+4,20)}
}

vk_draw_graph_debugger :: proc(r:^Vulkan_Backend,g:^Game) {if !graph_state.playtesting do return;vulkan_ui_rect(r,0,0,1200,54,{8,11,16,238});vulkan_ui_outline(r,0,0,1200,54,{255,218,112,190},1);beat:=story_presentation_node(g);kind:="COMPLETE";node:=graph_state.debugger.last_node;if beat!=nil {kind=strings.to_upper(story_node_kind_text(beat.kind));node=beat.id};vk_text(r,18,15,"GRAPH PLAYTEST",{255,218,112,255},.52);vk_text(r,178,15,fmt.tprintf("%s  ·  %s  ·  %s",graph_active_scene_id(),node,kind),{235,237,238,255},.45);vk_text(r,900,15,graph_state.debugger.paused?"PAUSED":"RUNNING",graph_state.debugger.paused?[4]u8{255,218,112,255}:[4]u8{117,229,169,255},.48);vk_button(r,graph_debugger_page_rect(),graph_state.debugger.page==0?"MYSTERY":"STORYCORE",true);vulkan_ui_rect(r,8,64,1184,440,{8,12,18,225});headers:=graph_state.debugger.page==0?[3]string{"CLUE OVERRIDES","CLAIM OVERRIDES","TOPIC OVERRIDES"}:[3]string{"CONDITION OVERRIDES","APPLY EFFECT","STORY STATE"};for header,i in headers do vk_text(r,24+f32(i)*390,68,header,{255,218,112,255},.36);if graph_state.debugger.page==0 {payload:=mystery_game_payload(g);if payload!=nil {for clue,i in payload.clues {box:=graph_debug_toggle_rect(0,i);enabled:=knowledge_piece_known(g,clue.id);vulkan_ui_rect(r,box.x,box.y,box.w,box.h,enabled?[4]u8{30,83,61,240}:[4]u8{29,36,46,240});vk_text(r,box.x+6,box.y+7,fmt.tprintf("%s %s",enabled?"✓":"·",clue.id),enabled?[4]u8{117,229,169,255}:[4]u8{175,183,192,255},.29)};for claim,i in payload.claims {box:=graph_debug_toggle_rect(1,i);enabled:=claim_known(g,claim.id);vulkan_ui_rect(r,box.x,box.y,box.w,box.h,enabled?[4]u8{36,69,99,240}:[4]u8{29,36,46,240});vk_text(r,box.x+6,box.y+7,fmt.tprintf("%s %s",enabled?"✓":"·",claim.id),enabled?[4]u8{119,190,230,255}:[4]u8{175,183,192,255},.29)}};topics:=graph_topics();for topic,i in topics.values[:topics.count] {box:=graph_debug_toggle_rect(2,i);enabled:=graph_topic_enabled(g,topic);vulkan_ui_rect(r,box.x,box.y,box.w,box.h,enabled?[4]u8{79,55,96,240}:[4]u8{29,36,46,240});vk_text(r,box.x+6,box.y+7,fmt.tprintf("%s %s",enabled?"✓":"·",topic),enabled?[4]u8{205,153,235,255}:[4]u8{175,183,192,255},.29)}}else if g.story_runtime!=nil {for condition,i in g.story_runtime.compiled.runtime.conditions[:min(15,len(g.story_runtime.compiled.runtime.conditions))] {box:=graph_debug_toggle_rect(0,i);forced_value,forced:=graph_debugger_condition_forced(g.story_runtime,condition.id);actual:=story_runtime_condition_eval(g.story_runtime,condition.id).value;color:=forced?[4]u8{174,116,215,255}:[4]u8{29,36,46,240};vulkan_ui_rect(r,box.x,box.y,box.w,box.h,color);vk_text(r,box.x+6,box.y+7,fmt.tprintf("%s %s",actual?"TRUE":"FALSE",condition.id),forced_value?[4]u8{235,210,255,255}:[4]u8{175,183,192,255},.29)};for effect,i in g.story_runtime.compiled.runtime.effects[:min(15,len(g.story_runtime.compiled.runtime.effects))] {box:=graph_debug_toggle_rect(1,i);vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{29,54,44,240});vk_text(r,box.x+6,box.y+7,fmt.tprintf("APPLY  %s",effect.id),{117,229,169,255},.29)};for value,i in g.story_runtime.state.values[:min(15,len(g.story_runtime.state.values))] {box:=graph_debug_toggle_rect(2,i);vulkan_ui_rect(r,box.x,box.y,box.w,box.h,{36,50,68,240});vk_text(r,box.x+6,box.y+7,fmt.tprintf("%s = %s",value.variable_id,story_value_string(value.value)),{170,218,228,255},.29)}};labels:=[4]string{graph_state.debugger.paused?"RESUME":"PAUSE","STEP","RESTART","STOP"};for label,i in labels do vk_button(r,graph_debugger_button_rect(i),label,i==0&&graph_state.debugger.paused);if graph_state.debugger.recent_count>0 {recent:=graph_state.debugger.recent[graph_state.debugger.recent_count-1];vk_text(r,492,668,fmt.tprintf("LAST EDGE  %s → %s",recent,node),{170,218,228,255},.38)}}
