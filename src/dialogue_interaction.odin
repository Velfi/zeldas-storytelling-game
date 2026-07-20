package main

import "core:fmt"
import "core:math"
import engine "zelda_engine:engine"

FOCUSED_DWELL :: f32(.65)
FOCUSED_FOCUS_TIME :: f32(.40)
FOCUSED_REVEAL_TIME :: f32(1.55)

// Focused examinations keep their rotatable model, but use the same control
// column as every other object dialogue.  Keeping these rectangles aligned
// with the dialogue sidebar also makes focus handoff predictable.
dialogue_interaction_leave_rect :: proc()->Rect {return dialogue_object_leave_rect()}
dialogue_interaction_tool_rect :: proc()->Rect {return {650,522,490,58}}
dialogue_interaction_action_rect :: proc()->Rect {return {650,456,490,58}}
dialogue_interaction_model_rect :: proc()->Rect {return {38,88,548,544}}
dialogue_interaction_region_rect :: proc(region:Dialogue_Interaction_Region)->Rect {switch region {case .Tools:return dialogue_interaction_tool_rect();case .Dialogue:return dialogue_interaction_action_rect();case .Model:return dialogue_interaction_model_rect()};return dialogue_interaction_model_rect()}
dialogue_interaction_default_rect :: proc(item:Dialogue_Interaction_Item)->Rect {return item==.Statuette?dialogue_interaction_model_rect():dialogue_interaction_action_rect()}
dialogue_interaction_has_tool_region :: proc(item:Dialogue_Interaction_Item)->bool {return item==.Desk||item==.Cloth}

dialogue_interaction_cycle_region :: proc(region:Dialogue_Interaction_Region,direction:int,has_tools:bool)->Dialogue_Interaction_Region {
	if has_tools do return Dialogue_Interaction_Region((int(region)+direction+3)%3)
	return region==.Model?.Dialogue:.Model
}

dialogue_interaction_item_name :: proc(item:Dialogue_Interaction_Item)->string {switch item {case .Statuette:return "BRONZE STATUETTE";case .Desk:return "EDGAR'S LOCKED DESK";case .Cloth:return "POLISHING CLOTH";case .None:};return "OBJECT"}

dialogue_interaction_enter :: proc(g:^Game,item:Dialogue_Interaction_Item) {
	previous:=g.dialogue_interaction
	g.dialogue_interaction={item=item,zoom=1,region=.Model,selected_tool=-1,phase=.Hidden}
	if previous.item==item {
		g.dialogue_interaction.yaw=previous.yaw;g.dialogue_interaction.pitch=previous.pitch;g.dialogue_interaction.zoom=previous.zoom
		g.dialogue_interaction.key_inserted=previous.key_inserted;g.dialogue_interaction.lock_turned=previous.lock_turned
		g.dialogue_interaction.catch_found=previous.catch_found;g.dialogue_interaction.catch_pressed=previous.catch_pressed;g.dialogue_interaction.drawer=previous.drawer
	}
	if item==.Statuette {
		g.dialogue_interaction.phase=g.study_seam_found?.Revealed:.Hidden
		g.dialogue_interaction.feedback=g.study_seam_found?"Dark blood remains caught inside the base seam.":"Turn the statuette slowly. Hold a detail in view to examine it."
		g.dialogue_interaction.ledger=g.study_seam_found?"OBSERVED — Blood trapped inside the base seam.":"The bronze is heavy and conspicuously clean."
	} else if item==.Desk {
		g.dialogue_interaction.drawer=g.desk_open?1:previous.drawer
		g.dialogue_interaction.feedback=g.desk_open?"The drawer stands open.":"Inspect the lock, or look beneath the desk for another way in."
		g.dialogue_interaction.ledger=g.desk_open?"OPENED — Edgar's marked ledger was recovered.":"A private center drawer. Locked."
	} else if item==.Cloth {
		g.dialogue_interaction.feedback="Rotate the folded cloth and inspect where the rust-colored stain crosses the oil-darkened weave."
		g.dialogue_interaction.ledger="The cloth is damp and smells sharply of lamp oil. One folded edge is stained rust-brown."
	}
	g.screen=.Dialogue;g.gui.focused=button_id(dialogue_interaction_default_rect(item));g.focus_screen=.Dialogue;g.focus_screen_initialized=true
}

dialogue_interaction_item_for_source :: proc(source_id:string)->Dialogue_Interaction_Item {
	switch source_id {case "statuette":return .Statuette;case "cloth":return .Cloth;case:}
	return .None
}

dialogue_interaction_item_acquired :: proc(g:^Game,item:Dialogue_Interaction_Item)->bool {
	#partial switch item {case .Statuette:return g.study_statuette_held;case .Cloth:return g.cloth_acquired}
	return true
}

dialogue_interaction_acquire_item :: proc(g:^Game,item:Dialogue_Interaction_Item)->bool {
	if item==.None||dialogue_interaction_item_acquired(g,item) do return false
	if item==.Statuette do g.study_statuette_held=true
	if item==.Cloth do g.cloth_acquired=true
	log_line(g,fmt.tprintf("Recovered: %s",dialogue_interaction_item_name(item)));play_sound(g,.Pick_Up)
	return true
}

dialogue_interaction_statuette_look_at :: proc(zoom:f32)->Vec2 {
	// The clue is on the underside (-Y in model space). Solve the same yaw/pitch
	// rotation used by vk_world_model so that normal points at the examination eye.
	eye:=Vec3{.35,1.15,3.5*zoom};center:=Vec3{-.75,.8,0}
	dx,dy,dz:=eye.x-center.x,eye.y-center.y,eye.z-center.z
	length:=f32(math.sqrt(f64(dx*dx+dy*dy+dz*dz)));if length<=.0001 do return {}
	dx/=length;dy/=length;dz/=length
	return {-f32(math.atan2(f64(dx),f64(dz))),-f32(math.acos(f64(clamp(-dy,-1,1))))}
}
dialogue_interaction_statuette_facing :: proc(yaw,pitch,zoom:f32)->f32 {
	// Transformed local underside normal (-Y), matching vk_world_model's c1.
	sy,cy:=f32(math.sin(f64(yaw))),f32(math.cos(f64(yaw)))
	sp,cp:=f32(math.sin(f64(pitch))),f32(math.cos(f64(pitch)))
	normal:=Vec3{sy*sp,-cp,-cy*sp}
	eye:=Vec3{.35,1.15,3.5*zoom};center:=Vec3{-.75,.8,0};dx,dy,dz:=eye.x-center.x,eye.y-center.y,eye.z-center.z
	length:=f32(math.sqrt(f64(dx*dx+dy*dy+dz*dz)));if length<=.0001 do return -1
	return normal.x*dx/length+normal.y*dy/length+normal.z*dz/length
}
dialogue_interaction_desk_look_at :: proc(zoom:f32)->Vec2 {
	// The concealed catch is viewed along the desk's local +Y detail normal.
	eye:=Vec3{.35,1.15,3.5*zoom};center:=Vec3{-.65,.7,0}
	dx,dy,dz:=eye.x-center.x,eye.y-center.y,eye.z-center.z
	length:=f32(math.sqrt(f64(dx*dx+dy*dy+dz*dz)));if length<=.0001 do return {}
	dx/=length;dy/=length;dz/=length
	return {-f32(math.atan2(f64(dx),f64(dz))),f32(math.acos(f64(clamp(dy,-1,1))))}
}
dialogue_interaction_desk_facing :: proc(yaw,pitch,zoom:f32)->f32 {
	// Transformed local +Y normal, matching vk_world_model's c1.
	sy,cy:=f32(math.sin(f64(yaw))),f32(math.cos(f64(yaw)))
	sp,cp:=f32(math.sin(f64(pitch))),f32(math.cos(f64(pitch)))
	normal:=Vec3{-sy*sp,cp,cy*sp}
	eye:=Vec3{.35,1.15,3.5*zoom};center:=Vec3{-.65,.7,0};dx,dy,dz:=eye.x-center.x,eye.y-center.y,eye.z-center.z
	length:=f32(math.sqrt(f64(dx*dx+dy*dy+dz*dz)));if length<=.0001 do return -1
	return normal.x*dx/length+normal.y*dy/length+normal.z*dz/length
}
dialogue_interaction_hotspot_visible :: proc(g:^Game)->bool {
	// The stain is a localized arc on the camera-facing side of the base, so the
	// clue is visible only when both the underside and that arc face the player.
	if g.dialogue_interaction.item==.Statuette do return dialogue_interaction_statuette_facing(g.dialogue_interaction.yaw,g.dialogue_interaction.pitch,g.dialogue_interaction.zoom)>.90
	if g.dialogue_interaction.item==.Desk&&topic_unlocked(g,"elsie_desk_help")&&!g.dialogue_interaction.catch_found do return dialogue_interaction_desk_facing(g.dialogue_interaction.yaw,g.dialogue_interaction.pitch,g.dialogue_interaction.zoom)>.90
	return false
}
dialogue_interaction_is_still :: proc(g:^Game)->bool {return math.abs(g.dialogue_interaction.yaw_velocity)+math.abs(g.dialogue_interaction.pitch_velocity)<.18&&!g.dialogue_interaction.mouse_dragging&&math.abs(g.pad_right_x)+math.abs(g.pad_right_y)<.16}

dialogue_interaction_commit_discovery :: proc(g:^Game) {
	f:=&g.dialogue_interaction
	if f.item==.Statuette&&!g.study_seam_found {
		g.study_seam_found=true;learn_observation(g,2);unlock_topic(g,"staged_scene");unlock_topic(g,"statuette_blood_found")
		f.feedback="Dark blood remains inside the seam. The broad surface was wiped, but the join was missed."
		f.ledger="NEW OBSERVATION — Blood remains trapped inside the statuette's base seam."
		f.new_dialogue=true;play_sound(g,.Fact)
	} else if f.item==.Desk&&!f.catch_found {
		f.catch_found=true;unlock_topic(g,"desk_catch_found");f.feedback="A concealed brass catch sits beneath the drawer rail."
		f.ledger="NEW APPROACH — Elsie's directions reveal the desk's hidden release catch."
		f.new_dialogue=true;play_sound(g,.Snap)
	}
}

dialogue_interaction_update_discovery :: proc(g:^Game,dt:f32) {
	f:=&g.dialogue_interaction
	if f.phase==.Revealed do return
	visible:=dialogue_interaction_hotspot_visible(g)
	switch f.phase {
	case .Hidden:
		if visible&&dialogue_interaction_is_still(g) {f.phase=.Candidate;f.candidate_time=0}
	case .Candidate:
		if !visible||!dialogue_interaction_is_still(g) {f.phase=.Hidden;f.candidate_time=0}else{f.candidate_time+=dt;if f.candidate_time>=FOCUSED_DWELL {f.phase=.Focusing;f.phase_time=0;f.feedback="Hold still…"}}
	case .Focusing:
		f.phase_time+=dt
		target:=f.item==.Statuette?dialogue_interaction_statuette_look_at(f.zoom):dialogue_interaction_desk_look_at(f.zoom)
		yaw_delta:=target.x-f.yaw;for yaw_delta>math.PI do yaw_delta-=2*math.PI;for yaw_delta< -math.PI do yaw_delta+=2*math.PI
		f.yaw+=yaw_delta*.16;f.pitch+=(target.y-f.pitch)*.16
		f.yaw_velocity*=.55;f.pitch_velocity*=.55
		if f.phase_time>=FOCUSED_FOCUS_TIME {dialogue_interaction_commit_discovery(g);f.phase=.Revealing;f.phase_time=0}
	case .Revealing:
		f.phase_time+=dt;if f.phase_time>=FOCUSED_REVEAL_TIME {f.phase=.Revealed;f.phase_time=0}
	case .Revealed:
	}
}

dialogue_interaction_unlock_desk :: proc(g:^Game) {
	f:=&g.dialogue_interaction
	if f.lock_turned||f.catch_pressed do return
	if f.catch_found {f.catch_pressed=true;f.feedback="The hidden catch depresses. The drawer releases with a soft click.";f.ledger="RELEASED — The concealed catch opens the desk without its key.";play_sound(g,.Snap);return}
	if !g.desk_key_found {f.feedback="The keyway is intact. Find Edgar's key, or learn another way into the desk.";f.ledger="LOCKED — Another approach is required.";play_sound(g,.Reject);return}
	if !f.key_inserted {f.key_inserted=true;f.selected_tool=0;f.feedback="The brass key seats in the lock. Turn it to release the drawer.";f.ledger="TOOL APPLIED — Edgar's brass key fits the desk.";play_sound(g,.Pick_Up);return}
	f.lock_turned=true;f.feedback="The key turns through a short arc. The lock clicks open.";f.ledger="UNLOCKED — Pull the center drawer open.";play_sound(g,.Snap)
}

dialogue_interaction_open_drawer :: proc(g:^Game) {
	f:=&g.dialogue_interaction;if !(f.lock_turned||f.catch_pressed||g.desk_open) {dialogue_interaction_unlock_desk(g);return}
	g.desk_open=true;f.drawer=1;ledger:=poi_index(g,"ledger");if ledger>=0 do _=mystery_game_mark_poi_revealed(g,ledger)
	f.feedback="The drawer slides out. Edgar's marked private ledger lies inside.";f.ledger="NEW EVIDENCE — The private ledger records unreceipted household payments to M.V.";f.new_dialogue=true
	unlock_topic(g,"accounts_challenged");unlock_topic(g,"private_note_seen");log_line(g,f.feedback);play_sound(g,.Door_Open)
}

dialogue_interaction_primary_action :: proc(g:^Game) {
	if g.dialogue_interaction.phase==.Focusing||g.dialogue_interaction.phase==.Revealing do return
	if g.dialogue_interaction.item==.Statuette {
		g.dialogue_interaction.feedback=g.study_seam_found?"The blood is confined to the seam; the broad surface was wiped clean.":"Turn the underside toward you and hold it steady."
		return
	}
	if g.dialogue_interaction.item==.Cloth {
		g.dialogue_interaction.feedback="Blood has wicked through several folds. Dark bronze residue is worked deep into the same damp fibers."
		g.dialogue_interaction.ledger="EXAMINED — Diluted blood and lamp oil overlap throughout the cloth's weave."
		clue:=clue_for_source(g,"cloth");if clue>=0&&clue_available(g,clue) do spend(g,clue)
		return
	}
	if g.dialogue_interaction.item==.Desk {if g.dialogue_interaction.lock_turned||g.dialogue_interaction.catch_pressed||g.desk_open {dialogue_interaction_open_drawer(g)}else{dialogue_interaction_unlock_desk(g)}}
}

update_dialogue_interaction :: proc(g:^Game) {
	f:=&g.dialogue_interaction;dt:=f32(FIXED_TIMESTEP)
	if f.item!=.Statuette {
		if g.input.shoulder_left {f.region=dialogue_interaction_cycle_region(f.region,-1,dialogue_interaction_has_tool_region(f.item));g.gui.focused=button_id(dialogue_interaction_region_rect(f.region))}
		if g.input.shoulder_right {f.region=dialogue_interaction_cycle_region(f.region,1,dialogue_interaction_has_tool_region(f.item));g.gui.focused=button_id(dialogue_interaction_region_rect(f.region))}
	}
	model_input:=f.region==.Model&&f.phase!=.Focusing&&f.phase!=.Revealing
	model_rect:=dialogue_interaction_model_rect();over_model:=contains(model_rect,g.input.mouse_pos)
	if g.input.mouse_pressed&&over_model {f.mouse_dragging=true;f.mouse_last=g.input.mouse_pos;f.region=.Model}
	if f.mouse_dragging&&g.input.mouse_down {delta:=Vec2{g.input.mouse_pos.x-f.mouse_last.x,g.input.mouse_pos.y-f.mouse_last.y};f.yaw_velocity=clamp(delta.x*.012,-.16,.16);f.pitch_velocity=clamp(delta.y*.012,-.16,.16);f.mouse_last=g.input.mouse_pos}
	if g.input.mouse_released do f.mouse_dragging=false
	if model_input {dead_x:=math.abs(g.pad_right_x)>.16?g.pad_right_x:f32(0);dead_y:=math.abs(g.pad_right_y)>.16?g.pad_right_y:f32(0);f.yaw_velocity=clamp(f.yaw_velocity+dead_x*.012,-.10,.10);f.pitch_velocity=clamp(f.pitch_velocity+dead_y*.012,-.10,.10);f.yaw+=f.yaw_velocity;f.pitch=clamp(f.pitch+f.pitch_velocity,-2.35,2.35);f.yaw_velocity*=.82;f.pitch_velocity*=.82}
	zoom_input:=g.pad_right_trigger-g.pad_left_trigger-g.input.mouse_wheel;f.zoom=clamp(f.zoom+zoom_input*.025,.68,1.35)
	if g.input.camera_toggle {f.yaw=0;f.pitch=0;f.zoom=1;f.yaw_velocity=0;f.pitch_velocity=0}
	dialogue_interaction_update_discovery(g,dt)
	if f.item!=.Statuette&&(button(g,dialogue_interaction_action_rect())||g.input.activate) do dialogue_interaction_primary_action(g)
	if dialogue_interaction_has_tool_region(f.item)&&button(g,dialogue_interaction_tool_rect())&&f.item==.Desk do dialogue_interaction_unlock_desk(g)
	if button(g,dialogue_interaction_leave_rect()) {if g.story_presentation.active {beat:=story_presentation_node(g);if beat!=nil do dialogue_complete_current(g,beat.cancel)}else{g.screen=.Investigate;g.focus_screen_initialized=false}}
}

vk_world_build_dialogue_interaction :: proc(scene:^Vk_World_Scene,ctx:^engine.Vk_Context,g:^Game) {
	f:=&g.dialogue_interaction
	if f.item==.Statuette {vk_world_add_centered(scene,ctx,&case_statuette_mesh,-.75,0,.8,2.45,f.yaw,f.pitch,{255,255,255,255},0)} else if f.item==.Desk {vk_world_add_centered(scene,ctx,&furniture_meshes[.Desk],-.65,0,.7,1.05,f.yaw,f.pitch,{255,255,255,255},0)} else if f.item==.Cloth {vk_world_add_centered(scene,ctx,&case_cloth_mesh,-.75,0,.8,2.15,f.yaw,f.pitch,{255,255,255,255},0)}
}

dialogue_interaction_controls_hint :: proc(g:^Game)->string {
	if g.active_device==.Gamepad do return fmt.tprintf("RIGHT STICK ROTATE  ·  TRIGGERS ZOOM  ·  %s RESET",prompt_label(g,.Camera))
	return fmt.tprintf("DRAG ROTATE  ·  WHEEL ZOOM  ·  %s RESET",prompt_label(g,.Camera))
}

vk_draw_dialogue_interaction :: proc(r:^Vulkan_Backend,g:^Game) {
	f:=&g.dialogue_interaction
	// Match physical-evidence dialogue: model on the left, uninterrupted
	// investigation ledger and choices in the standard right sidebar.
	// UI is composited after the 3D pass. Shade only outside the model viewport;
	// covering the viewport itself makes both the bronze and its seam material
	// appear to render behind the examination background.
	vulkan_ui_rect(r,0,0,1200,88,{0,0,0,150});vulkan_ui_rect(r,0,632,1200,88,{0,0,0,150});vulkan_ui_rect(r,0,88,38,544,{0,0,0,150});vulkan_ui_rect(r,586,88,614,544,{0,0,0,150})
	vulkan_ui_outline(r,38,88,548,544,{139,107,55,220},2)
	vk_text(r,62,108,"CASE EVIDENCE  ·  PHYSICAL EXAMINATION",{202,166,92,255},.62);vulkan_ui_rect(r,62,137,500,1,{139,107,55,180})
	vk_text(r,62,583,dialogue_interaction_item_name(f.item),{255,218,112,255},.86);vk_text(r,62,608,dialogue_interaction_controls_hint(g),{190,194,198,255},.46)
	// The clue only telegraphs after a deliberate dwell; the ring fills while the object is still.
	if f.phase==.Candidate {progress:=clamp(f.candidate_time/FOCUSED_DWELL,0,1);vulkan_ui_outline(r,252,272,120,120,{255,211,92,u8(80+int(progress*175))},2+progress*4);vk_text(r,264,402,"HOLD STILL",{255,211,92,255},.72)}
	if f.phase==.Focusing||f.phase==.Revealing {pulse:=f32(.5+.5*math.sin(f64(g.animation_time*9)));vulkan_ui_outline(r,222-pulse*8,242-pulse*8,180+pulse*16,180+pulse*16,{255,144,119,255},4);vk_text(r,250,444,f.phase==.Focusing?"FOCUSING…":"DETAIL FOUND",{255,144,119,255},.9)}
	if f.item==.Statuette&&g.study_seam_found {alpha:=f.phase==.Revealing?u8(clamp(int(f.phase_time/FOCUSED_REVEAL_TIME*255),30,255)):u8(255);vulkan_ui_rect(r,250,406,132,6,{154,45,45,alpha});vk_text(r,246,420,"BLOOD IN SEAM",{255,144,119,alpha},.68)}
	vulkan_ui_rect(r,625,26,555,668,{12,14,17,242});vulkan_ui_outline(r,625,26,555,668,{255,211,92,230},2)
	vk_text(r,650,57,dialogue_interaction_item_name(f.item),{255,218,112,255},1.45);_=vk_text_wrapped(r,650,91,490,"Examine the object closely and record what its physical details establish.",{205,207,210,255},.74,2)
	vulkan_ui_rect(r,650,164,490,1,{139,107,55,190});vk_text(r,650,181,f.new_dialogue?"NEW INVESTIGATION NOTE":"INVESTIGATION NOTE",f.new_dialogue?[4]u8{102,205,143,255}:[4]u8{205,207,210,255},.60)
	_=vk_text_wrapped(r,650,210,490,f.ledger,{248,247,242,255},.78,6);vulkan_ui_rect(r,650,322,490,1,{139,107,55,150});_=vk_text_wrapped(r,650,342,490,f.feedback,{255,218,112,255},.72,5)
	if f.item!=.Statuette {
		action:=f.item==.Cloth?"EXAMINE STAINED WEAVE":(g.desk_open?"DRAWER OPEN":f.lock_turned||f.catch_pressed?"PULL OPEN DRAWER":f.catch_found?"PRESS HIDDEN CATCH":g.desk_key_found?(f.key_inserted?"TURN BRASS KEY":"USE BRASS KEY"):"TEST LOCK")
		vk_dialogue_choice_surface(r,dialogue_interaction_action_rect(),f.region==.Dialogue);vk_text(r,668,dialogue_interaction_action_rect().y+18,fmt.tprintf("1.  %s",action),{248,247,242,255},.76)
	}
	if dialogue_interaction_has_tool_region(f.item) {
		tool:=f.item==.Desk?(g.desk_key_found?"TOOL  •  EDGAR'S KEY":topic_unlocked(g,"elsie_desk_help")?"APPROACH  •  HIDDEN CATCH":"NO RELEVANT TOOL"):"DETAIL  •  DAMP STAINED FIBERS"
		vk_dialogue_choice_surface(r,dialogue_interaction_tool_rect(),f.region==.Tools);vk_text(r,668,dialogue_interaction_tool_rect().y+18,tool,{205,207,210,255},.70)
	}
	vk_dialogue_footer_button(r,dialogue_interaction_leave_rect(),"Return to investigation",{148,155,168,255});vk_prompt_icon(r,g,.Back,dialogue_interaction_leave_rect().x+dialogue_interaction_leave_rect().w-27,dialogue_interaction_leave_rect().y+4,20)
}
