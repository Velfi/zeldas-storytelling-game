package main

import "core:fmt"
import "core:crypto"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sys/posix"
import "core:thread"
import "core:time"
import sdl "vendor:sdl3"
import ui "zelda_engine:ui"

contains :: proc(r:Rect,p:Vec2)->bool{return p.x>=r.x&&p.x<=r.x+r.w&&p.y>=r.y&&p.y<=r.y+r.h}
WINDOW_WIDTH :: 1200
WINDOW_HEIGHT :: 720
FIXED_TIMESTEP :: 1.0 / 60.0
MAX_FRAME_TIME :: 0.25
MAX_FIXED_STEPS_PER_FRAME :: 8
APP_STORAGE_NAME :: "Zelda's Storytelling Game"
APP_LOCAL_STORAGE_DIR :: ".zeldas-storytelling-game"

mouse_to_logical :: proc(x,y:f32,window_width,window_height:i32)->Vec2 {
	if window_width<=0||window_height<=0 do return {x,y}
	return {x*f32(WINDOW_WIDTH)/f32(window_width),y*f32(WINDOW_HEIGHT)/f32(window_height)}
}

window_mouse_to_logical :: proc(window:^sdl.Window,x,y:f32)->Vec2 {
	width,height:i32
	if !sdl.GetWindowSize(window,&width,&height) do return {x,y}
	return mouse_to_logical(x,y,width,height)
}
COURIER_FONT_KIND :: 3
// The textshape runtime exposes four font slots. This renderer owns slot 3 for
// its mono face and slot 2 for the symbol-only atlas; Zelda UI supplies input
// and focus here, while all visible text is drawn by this renderer.
SYMBOL_FONT_KIND :: 2
SYSTEM_UI_FONT_KIND :: 1
COURIER_FIRST_GLYPH :: 32
COURIER_GLYPH_COUNT :: 95
COURIER_LATIN_FIRST :: 160
COURIER_LATIN_GLYPH_COUNT :: 96
COURIER_PUNCTUATION_FIRST :: 0x2000
COURIER_PUNCTUATION_GLYPH_COUNT :: 0x70
COURIER_ARROW_FIRST :: 0x2190
COURIER_ARROW_GLYPH_COUNT :: 0x70
COURIER_SHAPE_FIRST :: 0x25A0
COURIER_SHAPE_GLYPH_COUNT :: 0x60
COURIER_CELL_WIDTH :: 10
COURIER_CELL_HEIGHT :: 18
SYSTEM_UI_CELL_WIDTH :: 8
// Four source pixels per logical pixel preserve stem detail when text is drawn
// at fractional scales or the swapchain uses a non-integral HiDPI scale.
COURIER_RASTER_SCALE :: 4
COURIER_RASTER_CELL_WIDTH :: COURIER_CELL_WIDTH * COURIER_RASTER_SCALE
COURIER_RASTER_CELL_HEIGHT :: COURIER_CELL_HEIGHT * COURIER_RASTER_SCALE
COURIER_COLUMNS :: 16
COURIER_ROWS :: (COURIER_GLYPH_COUNT + COURIER_COLUMNS - 1) / COURIER_COLUMNS
COURIER_ATLAS_WIDTH :: COURIER_RASTER_CELL_WIDTH * COURIER_COLUMNS
COURIER_ATLAS_HEIGHT :: COURIER_RASTER_CELL_HEIGHT * COURIER_ROWS

utf8_next_index :: proc(value:string,index:int)->int {
	if index<0||index>=len(value) do return len(value)
	lead:=value[index];width:=1
	if lead&0xE0==0xC0 do width=2
	else if lead&0xF0==0xE0 do width=3
	else if lead&0xF8==0xF0 do width=4
	return min(index+width,len(value))
}

utf8_glyph_count :: proc(value:string)->int {count,cursor:=0,0;for cursor<len(value) {cursor=utf8_next_index(value,cursor);count+=1};return count}
Text_Layout_Line :: struct {start,end,glyph_offset:int}
Text_Layout_Word :: struct {start,end,columns:int}
Text_Layout_Badness :: struct {total,raggedness,orphan:f32,lines:int}

text_layout_plan :: proc(value:string,max_columns:int)->[dynamic]Text_Layout_Line {
	lines:=make([dynamic]Text_Layout_Line,0,8,context.temp_allocator)
	if value=="" do return lines
	paragraph_start,glyph_offset:=0,0
	for paragraph_start<len(value) {
		paragraph_end:=paragraph_start;for paragraph_end<len(value)&&value[paragraph_end]!='\n' do paragraph_end=utf8_next_index(value,paragraph_end)
		words:=make([dynamic]Text_Layout_Word,0,16,context.temp_allocator);cursor:=paragraph_start
		for cursor<paragraph_end {
			for cursor<paragraph_end&&value[cursor]==' ' {cursor+=1;glyph_offset+=1}
			if cursor>=paragraph_end do break
			word_start,word_columns:=cursor,0
			for cursor<paragraph_end&&value[cursor]!=' ' {cursor=utf8_next_index(value,cursor);word_columns+=1}
			if word_columns>max_columns { // Preserve hard wrapping for identifiers and other unbroken text.
				chunk_start,chunk_columns:=word_start,0
				for chunk_start<cursor {chunk_end:=chunk_start;chunk_columns=0;for chunk_end<cursor&&chunk_columns<max_columns {chunk_end=utf8_next_index(value,chunk_end);chunk_columns+=1};append(&words,Text_Layout_Word{chunk_start,chunk_end,chunk_columns});chunk_start=chunk_end}
			} else {append(&words,Text_Layout_Word{word_start,cursor,word_columns})}
		}
		if len(words)==0 {append(&lines,Text_Layout_Line{paragraph_start,paragraph_start,glyph_offset})} else {
			cost:=make([]f32,len(words)+1,context.temp_allocator);next:=make([]int,len(words),context.temp_allocator);cost[len(words)]=0
			for reverse in 0..<len(words) {i:=len(words)-1-reverse;cost[i]=f32(1e20);for j in i..<len(words) {columns:=utf8_glyph_count(value[words[i].start:words[j].end]);if columns>max_columns do break;unused:=f32(max_columns-columns)/f32(max_columns);line_cost:=unused*unused*unused;if j==len(words)-1 {line_cost=0;if i==j&&i>0 do line_cost=1};candidate:=line_cost+cost[j+1];if candidate<cost[i] {cost[i]=candidate;next[i]=j+1}}}
			for i:=0;i<len(words);i=next[i] {j:=next[i]-1;append(&lines,Text_Layout_Line{words[i].start,words[j].end,glyph_offset});glyph_offset+=utf8_glyph_count(value[words[i].start:words[j].end]);if next[i]<len(words) do glyph_offset+=utf8_glyph_count(value[words[j].end:words[next[i]].start])}
		}
		if paragraph_end>=len(value) do break
		paragraph_start=paragraph_end+1
	}
	return lines
}

text_layout_columns :: proc(max_width,advance:f32)->int {return max(int(max_width/max(advance,.001)),1)}
wrapped_line_count :: proc(value:string,max_width,scale:f32)->int {if value=="" do return 1;return len(text_layout_plan(value,text_layout_columns(max_width,f32(COURIER_CELL_WIDTH)*scale)))}

text_layout_badness :: proc(value:string,max_width,scale:f32)->Text_Layout_Badness {
	if value=="" do return {lines=1}
	columns:=text_layout_columns(max_width,f32(COURIER_CELL_WIDTH)*scale);plan:=text_layout_plan(value,columns);result:=Text_Layout_Badness{lines=len(plan)};scored:=0
	for line,i in plan {last:=i==len(plan)-1||(line.end<len(value)&&value[line.end]=='\n');if last do continue;used:=utf8_glyph_count(value[line.start:line.end]);unused:=f32(max(columns-used,0))/f32(columns);result.raggedness+=unused*unused*unused;scored+=1}
	if scored>0 do result.raggedness/=f32(scored)
	for line,i in plan do if i>0&&strings.index_byte(value[line.start:line.end],' ')<0 {previous:=plan[i-1];if previous.end>=len(value)||value[previous.end]!='\n' do result.orphan=1}
	result.total=result.raggedness+result.orphan;return result
}

random_story_seed :: proc()->u64 {
	seed:u64
	for seed==0 {
		entropy:[8]byte
		crypto.rand_bytes(entropy[:])
		for value in entropy do seed=(seed<<8)|u64(value)
	}
	return seed
}

story_seed_path_for :: proc(storage_name:string)->(string,bool) {
	data_dir,data_error:=os.user_data_dir(context.temp_allocator)
	if data_error!=nil do return "",false
	save_dir,join_error:=os.join_path([]string{data_dir,storage_name},context.temp_allocator)
	if join_error!=nil do return "",false
	if os.make_directory_all(save_dir)!=nil do return "",false
	path,path_error:=os.join_path([]string{save_dir,"story-seed.bin"},context.temp_allocator)
	return path,path_error==nil
}
story_seed_path :: proc()->(string,bool) {return story_seed_path_for(APP_STORAGE_NAME)}

local_persistence_path_for :: proc(filename,dirname:string)->(string,bool) {
	base,base_error:=os.get_executable_directory(context.temp_allocator)
	if base_error!=nil {base,base_error=os.get_working_directory(context.temp_allocator);if base_error!=nil do return "",false}
	dir,dir_error:=os.join_path([]string{base,dirname},context.temp_allocator)
	if dir_error!=nil||os.make_directory_all(dir)!=nil {
		base,base_error=os.get_working_directory(context.temp_allocator);if base_error!=nil do return "",false
		dir,dir_error=os.join_path([]string{base,dirname},context.temp_allocator);if dir_error!=nil||os.make_directory_all(dir)!=nil do return "",false
	}
	path,path_error:=os.join_path([]string{dir,filename},context.temp_allocator);return path,path_error==nil
}
local_persistence_path :: proc(filename:string)->(string,bool) {return local_persistence_path_for(filename,APP_LOCAL_STORAGE_DIR)}

write_with_local_fallback :: proc(primary_path,filename:string,data:[]u8)->bool {
	if primary_path!=""&&os.write_entire_file(primary_path,data)==nil do return true
	fallback,ok:=local_persistence_path(filename);return ok&&os.write_entire_file(fallback,data)==nil
}

read_with_local_fallback :: proc(primary_path,filename:string)->([]byte,bool) {
	if primary_path!="" {data,err:=os.read_entire_file_from_path(primary_path,context.temp_allocator);if err==nil do return data,true}
	fallback,ok:=local_persistence_path(filename);if ok {data,err:=os.read_entire_file_from_path(fallback,context.temp_allocator);if err==nil do return data,true}
	return nil,false
}

User_Config :: struct {anti_aliasing:Anti_Aliasing_Mode,lighting_quality:Lighting_Quality,guidance:Guidance_Mode,mute:bool}
lighting_quality_from_text :: proc(text:string)->Lighting_Quality {if strings.contains(text,"lighting_quality=low") do return .Low;if strings.contains(text,"lighting_quality=medium") do return .Medium;if strings.contains(text,"lighting_quality=ultra") do return .Ultra;return .High}
guidance_mode_from_text :: proc(text:string)->Guidance_Mode {if strings.contains(text,"guidance=full") do return .Full;if strings.contains(text,"guidance=minimal") do return .Minimal;return .Adaptive}

user_config_path_for :: proc(storage_name:string)->(string,bool) {
	config_dir,config_error:=os.user_config_dir(context.temp_allocator);if config_error!=nil do return "",false
	app_dir,join_error:=os.join_path([]string{config_dir,storage_name},context.temp_allocator);if join_error!=nil||os.make_directory_all(app_dir)!=nil do return "",false
	path,path_error:=os.join_path([]string{app_dir,"options.cfg"},context.temp_allocator);return path,path_error==nil
}
user_config_path :: proc()->(string,bool) {return user_config_path_for(APP_STORAGE_NAME)}

load_user_config :: proc()->User_Config {
	config:=User_Config{lighting_quality=.High,guidance=.Adaptive};path,_:=user_config_path();data,ok:=read_with_local_fallback(path,"options.cfg");if !ok do return config;text:=string(data)
	if strings.contains(text,"anti_aliasing=msaa_2x") {config.anti_aliasing=.MSAA_2X} else if strings.contains(text,"anti_aliasing=msaa_4x") {config.anti_aliasing=.MSAA_4X} else if strings.contains(text,"anti_aliasing=fxaa") {config.anti_aliasing=.FXAA}
	config.lighting_quality=lighting_quality_from_text(text)
	config.guidance=guidance_mode_from_text(text)
	config.mute=strings.contains(text,"mute=true");return config
}

save_user_config :: proc(config:User_Config)->bool {
	path,_:=user_config_path();aa:="none";switch config.anti_aliasing {case .None:case .MSAA_2X:aa="msaa_2x";case .MSAA_4X:aa="msaa_4x";case .FXAA:aa="fxaa"}
	quality:="high";switch config.lighting_quality {case .Low:quality="low";case .Medium:quality="medium";case .High:case .Ultra:quality="ultra"}
	guidance:="adaptive";switch config.guidance {case .Full:guidance="full";case .Adaptive:case .Minimal:guidance="minimal"}
	contents:=fmt.tprintf("anti_aliasing=%s\nlighting_quality=%s\nguidance=%s\nmute=%v\n",aa,quality,guidance,config.mute);return write_with_local_fallback(path,"options.cfg",transmute([]u8)contents)
}

persist_game_options :: proc(g:^Game) {if !save_user_config({anti_aliasing=g.aa_mode,lighting_quality=g.lighting_quality,guidance=g.guidance_mode,mute=g.mute}) do fmt.eprintln("warning: could not save user options")}
anti_aliasing_label :: proc(mode:Anti_Aliasing_Mode)->string {switch mode {case .None:return "OFF";case .MSAA_2X:return "2X MSAA";case .MSAA_4X:return "4X MSAA";case .FXAA:return "FXAA"};return "OFF"}

persist_story_seed :: proc(seed:u64)->bool {
	path,_:=story_seed_path()
	encoded:[8]byte;value:=seed
	for i:=7;i>=0;i-=1 {encoded[i]=byte(value&0xff);value>>=8}
	return write_with_local_fallback(path,"story-seed.bin",encoded[:])
}

load_or_create_story_seed :: proc()->u64 {
	path,_:=story_seed_path()
	encoded,read_ok:=read_with_local_fallback(path,"story-seed.bin");if read_ok&&len(encoded)==8 {seed:u64;for value in encoded do seed=(seed<<8)|u64(value);if seed!=0 do return seed}
	seed:=random_story_seed();if !persist_story_seed(seed) do fmt.eprintln("warning: could not persist story RNG state");return seed
}

begin_new_story_seed :: proc()->u64 {
	seed:=random_story_seed();if !persist_story_seed(seed) do fmt.eprintln("warning: could not persist story RNG state");return seed
}

content_sized_button_rect :: proc(box:Rect,label:string,anchor:=Horizontal_Anchor.Left,scale:f32=1.25,padding_x:f32=12)->Rect {
	result:=box
	result.w=f32(utf8_glyph_count(label))*f32(COURIER_CELL_WIDTH)*scale+padding_x*2
	if anchor==.Right do result.x=box.x+box.w-result.w
	return result
}

anti_aliasing_from_args :: proc()->(Anti_Aliasing_Mode,bool) {
	for argument in os.args {switch argument {case "--aa=off":return .None,true;case "--aa=2x","--msaa=2":return .MSAA_2X,true;case "--aa=4x","--msaa=4":return .MSAA_4X,true;case "--aa=fxaa","--fxaa":return .FXAA,true;case:}}
	return .None,false
}

self_test_thread :: proc(_: ^thread.Thread) {
	run_self_tests()
}

run_self_tests_with_large_stack :: proc() {
	// The acceptance suite intentionally keeps several complete Game fixtures in
	// one procedure. Run it on a dedicated stack so growth of the production Game
	// state cannot silently turn a valid assertion suite into a main-stack crash.
	previous:posix.rlimit
	if posix.getrlimit(.STACK,&previous)==nil {
		desired:=previous
		desired.rlim_cur=posix.rlim_t(64*1024*1024)
		if desired.rlim_max!=posix.RLIM_INFINITY&&desired.rlim_cur>desired.rlim_max do desired.rlim_cur=desired.rlim_max
		_=posix.setrlimit(.STACK,&desired)
	}
	worker:=thread.create(self_test_thread)
	assert(worker!=nil)
	if previous.rlim_cur>0 do _=posix.setrlimit(.STACK,&previous)
	thread.start(worker)
	thread.join(worker)
	thread.destroy(worker)
}

player_package_mode:bool
player_package_forced:bool
active_authoring_project:Authoring_Project
active_authoring_ready:bool
active_authoring_read_only:bool

argument_value :: proc(prefix:string)->string {
	for argument in os.args do if strings.has_prefix(argument,prefix) do return argument[len(prefix):]
	return ""
}

parse_vec3_argument :: proc(value:string)->(Vec3,bool) {
	parts,_:=strings.split(value,",",context.temp_allocator);if len(parts)!=3 do return {},false
	x,x_ok:=strconv.parse_f32(strings.trim_space(parts[0]));y,y_ok:=strconv.parse_f32(strings.trim_space(parts[1]));z,z_ok:=strconv.parse_f32(strings.trim_space(parts[2]))
	return {x,y,z},x_ok&&y_ok&&z_ok
}

capture_wall_view_from_text :: proc(value:string)->(House_Wall_View,bool) {
	switch strings.to_lower(strings.trim_space(value)) {case "auto","automatic":return .Automatic,true;case "up","full":return .Walls_Up,true;case "down","cutaway":return .Walls_Down,true;case:}
	return .Automatic,false
}

main :: proc() {
	story_domains_initialize()
	if len(os.args)>1&&os.args[1]=="--agent-object-transaction" do os.exit(agent_object_transaction(os.args[2:]))
	if len(os.args)>2&&os.args[1]=="--agent-level-validate" do os.exit(agent_level_validate(os.args[2]))
	if len(os.args)>1&&os.args[1]=="--scenario-test" do os.exit(scenario_cli(os.args[2:]))
	if len(os.args)>1&&os.args[1]=="--campaign-scenario-test" do os.exit(campaign_scenario_cli())
	if len(os.args)>1&&os.args[1]=="--authoring-acceptance" {result:=run_authoring_acceptance(".", len(os.args)>2&&os.args[2]=="--keep-root");if !result.ok {fmt.eprintln(result.phase, ": ", result.message, " (", result.assertions, " assertions)");os.exit(2)};fmt.println(result.message, " (", result.assertions, " assertions)");return}
	if len(os.args)>1&&os.args[1]=="--story-core-test" {run_story_core_tests();fmt.println("interactive story core checks passed");return}
	if len(os.args)>2&&os.args[1]=="--validate-story" {project:Story_Project;checked:=load_story_project(os.args[2],&project);if !checked.ok {fmt.eprintln(checked.message);os.exit(2)};defer story_project_destroy(&project);compiled:=compile_story_project(&project);defer story_compile_result_destroy(&compiled);if !compiled.ok {fmt.eprintln(compiled.message);os.exit(2)};fmt.println("INTERACTIVE STORY VALID");return}
	if len(os.args)>2&&os.args[1]=="--graph-roundtrip-story" {source:Story_Project;loaded:=load_story_project(os.args[2],&source);if !loaded.ok {fmt.eprintln(loaded.message);os.exit(2)};defer story_project_destroy(&source);graph_import_story(&source);rebuilt:Story_Project;built:=graph_build_story_project(&source,&rebuilt);if !built.ok {fmt.eprintln(built.message);os.exit(3)};defer story_project_destroy(&rebuilt);before:=compile_story_project(&source);after:=compile_story_project(&rebuilt);defer story_compile_result_destroy(&before);defer story_compile_result_destroy(&after);if !before.ok||!after.ok||before.story.content_identity!=after.story.content_identity {fmt.eprintln("graph round-trip changed story semantics");os.exit(4)};fmt.println("GRAPH ROUNDTRIP SEMANTICS PRESERVED");return}
	city_data:=city_data_initialize();if !city_data.ok {fmt.eprintln(city_data.message);return}
	if len(os.args)>1&&os.args[1]=="--vehicle-self-test" {run_vehicle_self_tests();fmt.println("vehicle physics checks passed");return}
	if len(os.args)>1&&os.args[1]=="--self-test" {run_self_tests_with_large_stack();return}
	if len(os.args)>2&&os.args[1]=="--validate-campaign" {doc:Campaign_Definition;checked:=load_campaign_manifest(os.args[2],&doc);if !checked.ok {fmt.eprintln(checked.message);os.exit(2)};fmt.println("CAMPAIGN VALID");return}
	level_path:=argument_value("--level=");if level_path=="" do level_path=LEVEL_DEFAULT_PATH
	story_path:=argument_value("--story=");if story_path=="" do story_path="assets/stories/mysteries/the_torn_appointment.story.toml"
	LEVEL_DEFAULT_PATH=level_path;player_package_mode=argument_value("--player-package")!="";if !player_package_mode {for value in os.args do if value=="--player-package" do player_package_mode=true};player_package_forced=player_package_mode
	campaign_initialize();if campaign_validation:=campaign_validate(&campaign_document);!campaign_validation.ok {fmt.eprintln(campaign_validation.message);return}
	if initialized:=authoring_app_initialize(story_path,level_path);!initialized.ok {fmt.eprintln(initialized.message);return}
	if active_authoring_ready do _=catalog_asset_overrides_load(active_authoring_project.root_path,&editor_catalog)
	argument:=len(os.args)>1?os.args[1]:"";world_preview:=argument=="--world-preview";city_preview:=argument=="--city-preview";capture_mode:=strings.has_prefix(argument,"--capture-")
	loaded_story:=load_story_project(story_path,&active_story_project);if !loaded_story.ok {fmt.eprintln(loaded_story.message);return};defer story_project_destroy(&active_story_project)
	payload:=mystery_payload(&active_story_project);if payload==nil {fmt.eprintln("story has no mystery payload");return}
	graph_import_story(&active_story_project)
	graph_autosave_enabled=!player_package_mode
	for fallback,i in CHARACTER_MESH_PATHS {path:=fallback;if i>0&&payload!=nil&&i-1<len(payload.characters) {if owned,ok:=story_entity_appearance_path(&active_story_project,&authoring_workspace.assets,payload.characters[i-1].entity_id);ok&&os.is_file(owned) do path=owned};ok:bool;character_meshes[i],ok=glb_load(path);if !ok&&path!=fallback do character_meshes[i],ok=glb_load(fallback);if !ok {fmt.eprintln("failed to load required animated character rig: ",path);return}}
	for object in level_document.objects {for &entry in editor_catalog.entries do if entry.id==object.catalog_id {if path,ok:=level_object_model_path(&level_document,&authoring_workspace.assets,object.id);ok&&os.is_file(path) {entry.model=path;entry.model_asset_ref=object.model_asset_ref};if path,ok:=level_object_material_path(&level_document,&authoring_workspace.assets,object.id);ok&&os.is_file(path) {texture:=load_room_texture(path);if len(texture.pixels)>0 do entry.material_asset_ref=object.material_asset_ref};if path,ok:=level_object_texture_path(&level_document,&authoring_workspace.assets,object.id);ok&&os.is_file(path) {texture:=load_room_texture(path);if len(texture.pixels)>0 do entry.texture_asset_ref=object.texture_asset_ref};break}}
	if !load_furniture_meshes() {fmt.eprintln("failed to load one or more required case-prop meshes");return};load_city_meshes()
	when ODIN_OS==.Darwin {if _,err:=os.stat("/opt/homebrew/lib/libvulkan.1.dylib",context.temp_allocator);err==nil do _=os.set_env("SDL_VULKAN_LIBRARY","/opt/homebrew/lib/libvulkan.1.dylib")}
	if capture_mode {
		// NOT_FOCUSABLE protects the window itself; these hints also stop SDL's
		// macOS bootstrap and window-show path from activating the process.
		_=sdl.SetHint(sdl.HINT_MAC_BACKGROUND_APP,"1")
		_=sdl.SetHint(sdl.HINT_WINDOW_ACTIVATE_WHEN_SHOWN,"0")
		_=sdl.SetHint(sdl.HINT_WINDOW_ACTIVATE_WHEN_RAISED,"0")
	}
	if !sdl.Init({.VIDEO,.AUDIO,.EVENTS,.GAMEPAD}) {fmt.eprintln(sdl.GetError());return};defer sdl.Quit()
	window_flags:sdl.WindowFlags={.VULKAN,.RESIZABLE,.HIGH_PIXEL_DENSITY}
	// Automated captures only need a presentable Vulkan surface. Prevent their
	// short-lived windows from taking keyboard focus from the user's active app.
	if capture_mode do window_flags += {.NOT_FOCUSABLE}
	window:=sdl.CreateWindow("Zelda's Storytelling Game",WINDOW_WIDTH,WINDOW_HEIGHT,window_flags);if window==nil {fmt.eprintln(sdl.GetError());return};defer sdl.DestroyWindow(window)
	if !capture_mode {_=sdl.StartTextInput(window);defer _=sdl.StopTextInput(window)}
	when ODIN_OS==.Darwin {if !capture_mode do chicago_editor_menu_install()}
	user_config:=load_user_config();aa_override,has_aa_override:=anti_aliasing_from_args();startup_aa:=has_aa_override?aa_override:user_config.anti_aliasing
	// Ending captures validate authored result layout and copy. Keep that
	// deterministic and independent of the player's saved post-process mode.
	if argument=="--capture-ending" do startup_aa=.None
	backend:Vulkan_Backend;if !vulkan_backend_init(&backend,window,startup_aa) {fmt.eprintln("Vulkan game backend initialization failed; run make shaders");return};defer vulkan_backend_destroy(&backend)
	story_seed:=capture_mode?payload.seed:load_or_create_story_seed()
	g:=Game{running=true,screen=.Campaign,phase=.Introduction,ap=payload.action_budget,seed=story_seed,run_seed=story_seed,persist_seed=!capture_mode,mute=user_config.mute,aa_mode=user_config.anti_aliasing,lighting_quality=user_config.lighting_quality,pending_clue=-1,active_ending=-1,board_last_section=-1,board_last_socket=-1,timeline_order={0,1,2},player_x=3.5,player_y=12.5,camera_x=3.5,camera_y=12.5,camera_initialized=true,camera_orbit=math.PI/4,camera_zoom=1,camera_orbit_initialized=true,catalog_bake_index=-1,catalog_thumbnail_autoload_attempted=capture_mode,pending_world_interaction=-1,pending_interactive=-1,hover_interactive=-1,near_interactive=-1,auto_door=-1,hover_entity=-1,near_entity=-1,dialogue_entity=-1,near_landmark=-1,driving_vehicle=-1,near_vehicle=-1,active_device=.Keyboard_Mouse}
	compiled_story:=compile_story_project(&active_story_project);if !compiled_story.ok {fmt.eprintln("story compilation failed");return};active_compiled_story=compiled_story.story;defer compiled_story_destroy(&active_compiled_story)
	spatial_level:Level_Document;if loaded:=level_load(level_path,&spatial_level);!loaded.ok {fmt.eprintln(loaded.message);return};world_entities_result:=world_entities_rebuild(&active_story_project,&spatial_level);if !world_entities_result.ok {fmt.eprintln(world_entities_result.message);return};defer delete(WORLD_ENTITIES);assert(story_spatial_registry_register(&active_spatial_registry,story_level_space(&spatial_level)));_=story_spatial_registry_register(&active_spatial_registry,story_city_space());defer story_spatial_registry_destroy(&active_spatial_registry);active_spatial_service=story_spatial_registry_service(&active_spatial_registry)
	spatial_validation:=story_spatial_validate_project(&active_story_project,&active_spatial_registry);if !spatial_validation.ok {for diagnostic in spatial_validation.diagnostics do fmt.eprintln(diagnostic.message);story_validation_destroy(&spatial_validation);return};story_validation_destroy(&spatial_validation)
	active_story_runtime=story_runtime_new(&active_compiled_story,&active_spatial_service);defer story_runtime_destroy(&active_story_runtime)
	g.story_project=&active_story_project;g.story_state=&active_story_runtime.state;g.compiled_story=&active_compiled_story;g.story_runtime=&active_story_runtime;g.mystery_state=cast(^Mystery_State)story_runtime_capability_state(&active_story_runtime,"mystery",MYSTERY_DOMAIN_VERSION);g.spatial_service=&active_spatial_service
	g.guidance_mode=user_config.guidance;g.tutorial.guidance=user_config.guidance
	audio_spec:=sdl.AudioSpec{format=.F32,channels=1,freq=44100};g.audio_stream=sdl.OpenAudioDeviceStream(sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK,&audio_spec,nil,nil);if g.audio_stream!=nil do _=sdl.ResumeAudioStreamDevice(g.audio_stream);defer if g.audio_stream!=nil do sdl.DestroyAudioStream(g.audio_stream);g.vehicle_audio_stream=sdl.OpenAudioDeviceStream(sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK,&audio_spec,nil,nil);if g.vehicle_audio_stream!=nil do _=sdl.ResumeAudioStreamDevice(g.vehicle_audio_stream);defer if g.vehicle_audio_stream!=nil do sdl.DestroyAudioStream(g.vehicle_audio_stream);loaded_sounds:=load_sound_assets(&g);if loaded_sounds!=len(g.sounds) do fmt.eprintln("warning: loaded ",loaded_sounds," of ",len(g.sounds)," OGG cues; missing cues use procedural fallback");defer destroy_sound_assets(&g)
	initialize_city_vehicles(&g);initialize_dispositions(&g);initialize_character_animations(&g);if world_preview {g.screen=.Investigate;_=apply_player_spawn_marker(&g)};if city_preview {g.screen=.Exterior;_=city_place_at_landmark(&g,payload.city_start)}
	if capture_mode&&argument=="--capture-theme-knoll" {g.screen=.Theme_Knoll;g.gui.focused=button_id({300,458,220,42})}
	if capture_mode&&argument=="--capture-theme-knoll-details" do g.screen=.Theme_Knoll_Details
	if capture_mode&&argument=="--capture-campaign-checkbox" {
		campaign_workspace_begin();campaign_workspace.tab=.Variables;g.screen=.Campaign_Action
		boolean_index:=-1;for variable,i in campaign_workspace.draft.variables do if variable.kind==.Boolean {boolean_index=i;break}
		if boolean_index<0 {append(&campaign_workspace.draft.variables,Campaign_Variable{id="capture_flag",display_name="Capture flag",description="Boolean component capture fixture",kind=.Boolean});boolean_index=len(campaign_workspace.draft.variables)-1}
		campaign_workspace.selected_variable=boolean_index;campaign_workspace.draft.variables[boolean_index].default_boolean=true
	}
	if capture_mode&&strings.has_prefix(argument,"--capture-campaign-authoring-") {
		campaign_workspace_begin();g.screen=.Campaign_Action
		switch argument {case "--capture-campaign-authoring-overview":campaign_workspace.tab=.Overview;case "--capture-campaign-authoring-cases":campaign_workspace.tab=.Cases;case "--capture-campaign-authoring-variables":campaign_workspace.tab=.Variables;case "--capture-campaign-authoring-conditions":campaign_workspace.tab=.Conditions;case "--capture-campaign-authoring-effects":campaign_workspace.tab=.Effects;case "--capture-campaign-authoring-simulation":campaign_workspace.tab=.Simulation;case "--capture-campaign-authoring-diagnostics":campaign_workspace.tab=.Diagnostics}
	}
	if capture_mode&&strings.has_prefix(argument,"--capture-story-authoring-") {
		authoring_workspace_begin(&g)
		switch argument {case "--capture-story-authoring-project":authoring_workspace.tab=.Project;case "--capture-story-authoring-story-data":authoring_workspace.tab=.Story_Data;case "--capture-story-authoring-mystery":authoring_workspace.tab=.Mystery;case "--capture-story-authoring-diagnostics":authoring_workspace.tab=.Diagnostics;case "--capture-story-authoring-assets":authoring_workspace.tab=.Assets;case "--capture-story-authoring-packages":authoring_workspace.tab=.Packages;case "--capture-story-authoring-library":authoring_workspace.tab=.Library}
	}
	if capture_mode&&(argument=="--capture-graph"||argument=="--capture-graph-minimap-stress"||argument=="--capture-graph-routing-board"||argument=="--capture-graph-routing-crossings"||argument=="--capture-graph-quick-add"||argument=="--capture-graph-script"||argument=="--capture-graph-localization"||argument=="--capture-graph-diagnostics"||argument=="--capture-graph-inspector-edit"||argument=="--capture-graph-edge-drag"||argument=="--capture-graph-paste"||argument=="--capture-graph-debugger") {g.screen=.Investigate;g.editor_mode=.Graph;if argument=="--capture-graph-routing-board"||argument=="--capture-graph-routing-crossings" do graph_configure_routing_test_board();if argument=="--capture-graph-minimap-stress" do graph_configure_minimap_stress_board();graph_state.active_scene=argument=="--capture-graph-routing-crossings"?1:0;graph_select_only(graph_document.node_count>0?(graph_state.active_scene==1?11:0):-1);if argument=="--capture-graph-quick-add" {graph_state.quick_add=true;graph_state.quick_add_at={540,210}}else if argument=="--capture-graph-script" do graph_state.view=.Script;else if argument=="--capture-graph-localization" do graph_state.view=.Localization;else if argument=="--capture-graph-diagnostics" {if graph_document.node_count>0 do graph_document.nodes[0].beat.next="missing_capture_target";_=graph_validate(&graph_document)}else if argument=="--capture-graph-inspector-edit"&&graph_state.selected_node>=0 do graph_begin_edit(.Text,graph_document.nodes[graph_state.selected_node].beat.text,graph_state.selected_node,true);else if argument=="--capture-graph-edge-drag"&&graph_state.selected_node>=0 {node:=graph_document.nodes[graph_state.selected_node];graph_state.edge_drag={active=true,node=graph_state.selected_node,port=.Next,choice_index=-1,start={node.position.x+graph_state.pan.x+190,node.position.y+graph_state.pan.y+46}};g.input.mouse_pos={700,410}}else if argument=="--capture-graph-paste" {if graph_copy_selection() do _=graph_paste_clipboard({650,420})}else if argument=="--capture-graph-debugger" do _=graph_begin_playtest(&g)}
	if capture_mode&&argument=="--capture-graph-routing-crossing-hover" {g.screen=.Investigate;g.editor_mode=.Graph;graph_configure_routing_test_board();graph_state.active_scene=1;graph_select_only(11);g.input.mouse_pos={583,269}}
	if capture_mode&&argument=="--capture-graph-routing-parallel-hover" {g.screen=.Investigate;g.editor_mode=.Graph;graph_configure_routing_test_board();graph_state.active_scene=1;graph_select_only(15)}
	if capture_mode&&argument=="--capture-graph-routing-zoomed-hover" {g.screen=.Investigate;g.editor_mode=.Graph;graph_configure_routing_test_board();graph_state.active_scene=1;graph_select_only(11);_=graph_frame_nodes();canvas:=graph_canvas_rect();center:=graph_screen_to_world({canvas.x+canvas.w*.5,canvas.y+canvas.h*.5});graph_state.zoom=.55;graph_state.pan={canvas.x+(canvas.w*.5-canvas.x)/graph_state.zoom-center.x,canvas.y+(canvas.h*.5-canvas.y)/graph_state.zoom-center.y}}
	if capture_mode&&argument=="--capture-graph-debugger" do graph_state.debugger.page=1
	if capture_mode&&(argument=="--capture-graph-routing-direct-hover"||argument=="--capture-graph-routing-obstacle-hover"||argument=="--capture-graph-routing-back-hover") {g.screen=.Investigate;g.editor_mode=.Graph;graph_configure_routing_test_board();graph_state.active_scene=0;graph_select_only(argument=="--capture-graph-routing-obstacle-hover"?2:argument=="--capture-graph-routing-back-hover"?5:0)}
	if capture_mode&&argument=="--capture-graph-choice" {g.screen=.Investigate;g.editor_mode=.Graph;graph_configure_routing_test_board();graph_state.active_scene=1;graph_select_only(15)}
	if capture_mode&&argument=="--capture-graph-conditions" {g.screen=.Investigate;g.editor_mode=.Graph;graph_state.view=.Conditions;if graph_document.condition_count>0 {graph_state.selected_condition=0;item:=&graph_document.conditions[0];item.kind=.Spatial_Distance;item.spatial_a={"vale_house","detective"};item.spatial_b={"vale_house","study_desk"};item.distance=3.5}}
	if capture_mode&&argument=="--capture-graph-effects" {g.screen=.Investigate;g.editor_mode=.Graph;graph_state.view=.Effects;if graph_document.effect_count>0 {graph_state.selected_effect=0;item:=&graph_document.effects[0];item.kind=.Set_Value;item.variable_id="trust_miriam";item.value=story_value_integer(2)}}
	if capture_mode&&argument=="--capture-graph-help" {g.screen=.Investigate;g.editor_mode=.Graph;graph_state.help_visible=true}
	if capture_mode&&argument=="--capture-graph-localization"&&graph_document.node_count>0&&graph_document.localization_count==0 {graph_document.localizations[0]={node_id=graph_document.nodes[0].beat.id,language="fr",text="Une traduction de la première réplique.",status="review",note="Needs final context pass",voice="vo/fr/arrival_001.ogg"};graph_document.localizations[1]={node_id=graph_document.nodes[0].beat.id,language="de",status="draft"};graph_document.localization_count=2;graph_state.selected_localization=0}
	if capture_mode&&(argument=="--capture-graph-picker"||argument=="--capture-graph-marquee"||argument=="--capture-graph-edge-selection") {g.screen=.Investigate;g.editor_mode=.Graph;graph_state.active_scene=0;graph_select_only(graph_document.node_count>0?0:-1);if argument=="--capture-graph-picker"&&graph_state.selected_node>=0 do graph_begin_picker(.Speaker,"",graph_state.selected_node);else if argument=="--capture-graph-marquee" do graph_state.marquee={active=true,start={280,120},current={820,430}};else if argument=="--capture-graph-edge-selection"&&graph_state.selected_node>=0 do graph_state.edge_selection={active=true,node=graph_state.selected_node,port=.Next,choice_index=-1}}
	if argument=="--capture-catalog-thumbnail" {if len(os.args)<3 {fmt.eprintln("catalog thumbnail capture requires a catalog ID");return};requested:=os.args[2];for entry,i in editor_catalog.entries do if entry.id==requested&&entry.kind==.Object do g.catalog_bake_index=i;if g.catalog_bake_index<0 {fmt.eprintln("unknown object catalog ID: ",requested);return}}
	if capture_mode {switch argument {case "--capture-options":g.screen=.Options;case "--capture-city":g.screen=.Exterior;_=city_place_at_landmark(&g,payload.city_start);case "--capture-driving":g.screen=.Exterior;g.driving_vehicle=0;g.city_x=g.vehicles[0].x;g.city_y=g.vehicles[0].y;g.city_angle=g.vehicles[0].heading;case "--capture-world":g.screen=.Investigate;case "--capture-characters":g.screen=.Investigate;g.player_x=15;g.player_y=27;g.player_angle=math.PI/2;g.camera_x=20.25;g.camera_y=27;g.camera_orbit=math.PI/2;g.camera_zoom=.58;g.wall_view=.Walls_Down;g.cutaway_transition=1;for &amount in g.wall_cutaways do amount=1;character_ids:=[3]string{"miriam","daniel","elsie"};character_positions:=[3]Vec2{{18.5,27},{22,27},{25.5,27}};for id,i in character_ids {entity:=world_entity_index(id);if entity>=0 {WORLD_ENTITIES[entity].x=character_positions[i].x;WORLD_ENTITIES[entity].y=character_positions[i].y}};case "--capture-dialogue":g.screen=.Dialogue;g.dialogue_entity=world_entity_index("miriam");g.player_x=2.5;g.player_y=2.5;g.player_angle=0;trigger_character_interact(&g,"miriam");g.character_animations[1].transition=.5;g.character_animations[1].next_time=.125;case "--capture-environment-card":g.screen=.Dialogue;g.dialogue_entity=world_entity_index("edgar_watch");g.player_x=12.5;g.player_y=24.5;case "--capture-check":g.screen=.Dialogue;g.dialogue_entity=world_entity_index("ledger");g.player_x=4.5;g.player_y=8.8;g.camera_x=4.5;g.camera_y=8.8;g.pending_clue=0;g.check_from_dialogue=true;g.check_preview=check_target(payload.clues[0].difficulty);case "--capture-shutter":g.screen=.Investigate;g.player_x=9;g.player_y=14;g.camera_x=10;g.camera_y=15;g.shutter_time=2;g.shutter_view=0;g.shutter_feedback="The dining-room sightline is ready to test.";case "--capture-study":g.screen=.Investigate;g.study_rug_lifted=true;g.study_statuette_held=true;g.study_wound_matched=true;g.study_seam_found=true;g.study_oil_found=true;case "--capture-dinner":g.screen=.Dialogue;g.dialogue_entity=world_entity_index("dining_room");case "--capture-notebook","--capture-dialogue-notebook","--capture-objectives":g.screen=.Notebook;case "--capture-board":g.screen=.Board;case "--capture-recreate":g.screen=.Recreate;g.recreate_section=1;g.theory.murder=true;mystery_game_mark_all_clues(&g);g.board_sockets[1]={true,true,true};case "--capture-cover-up-recreate":g.screen=.Recreate;g.recreate_section=2;g.theory.cover_up=true;mystery_game_mark_all_clues(&g);g.board_sockets[2]={true,true,true};case "--capture-alibi-recreate":g.screen=.Recreate;g.recreate_section=3;g.theory.alibi=true;mystery_game_mark_all_clues(&g);g.board_sockets[3][0]=true;case "--capture-proof-recreate","--capture-shutter-recreate":g.screen=.Recreate;g.recreate_section=4;g.theory.proof=true;mystery_game_mark_all_clues(&g);g.board_sockets[4]={true,true,true};case "--capture-reveal-prep":g.screen=.Reveal_Prep;case "--capture-reveal","--capture-reveal-other-lies":g.screen=.Reveal;case "--capture-result":g.screen=.Result;g.result=mystery_evaluate_outcome(&active_story_project,g.mystery_state);case "--capture-diagnostics":g.screen=.Diagnostics;case:}}
	if capture_mode&&(argument=="--capture-world"||argument=="--capture-objectives") {_=game_story_milestone(&g,"city.briefing_received");_=game_story_milestone(&g,"city.case_destination_entered");if argument=="--capture-objectives" do g.notebook_tab=4}
	if capture_mode&&argument=="--capture-quest-complete" {g.screen=.Investigate;_=game_story_milestone(&g,"city.briefing_received");_=game_story_milestone(&g,"city.case_destination_entered");_=game_story_milestone(&g,"investigation.question_opened");_=game_story_milestone(&g,"investigation.explanation_ready");quest_tracker_sync(&g);_=game_story_milestone(&g,"investigation.conclusion_presented");g.screen=.Dialogue;g.dialogue_entity=world_entity_index("officer_lead");g.dialogue_response=officer_opening_line("officer_lead");g.quest_completion_pending=true;g.quest_completion_started=g.animation_time}
	if capture_mode&&argument=="--capture-driving" {v:=&g.vehicles[0];v.heading=f32(math.PI/2);v.speed=.38;v.velocity_x=.13;v.velocity_y=.35;v.steering=.42;v.yaw_rate=.014;v.chassis_lateral_acceleration=.55;v.chassis_acceleration=-.45;v.body_roll=vehicle_body_roll_target(v^,false,vehicle_tune(0));v.body_pitch=vehicle_body_pitch_target(v.chassis_acceleration,vehicle_tune(0));v.traction_state=vehicle_traction_state(v^);v.impact=.12;g.city_angle=v.heading;g.vehicle_camera_follow_distance=6.1;g.keys[.S]=true;for i in 0..<6 {g.vehicle_skid_marks[i]={position={g.city_x+(i%2==0?f32(-.34):f32(.34)),g.city_y-1.2-f32(i/2)*.72},heading=v.heading,age=f32(i/2)*.35,strength=.72,active=true}}}
	if capture_mode&&argument=="--capture-city-border" {g.screen=.Exterior;g.city_x=city_world(82);g.city_y=city_world(.55);g.city_angle= -f32(math.PI)/2;g.city_camera_x=g.city_x;g.city_camera_y=g.city_y;g.city_camera_initialized=true;g.camera_orbit= -f32(math.PI)/2;g.camera_orbit_initialized=true}
	context_capture:=argument=="--capture-context-person"||argument=="--capture-context-evidence"||argument=="--capture-context-door"||argument=="--capture-context-locked"||argument=="--capture-context-multiple"||argument=="--capture-context-xbox"||argument=="--capture-context-playstation"||argument=="--capture-context-switch"||argument=="--capture-context-orbit"
	if capture_mode&&argument=="--capture-shutter" {g.screen=.Investigate;g.player_x=26.8;g.player_y=17.2;g.player_angle=2.2531;g.first_person_camera=true;g.shutter_time=2;g.shutter_open=false;g.shutter_position=0;g.shutter_target=0;runtime_interactives_rebuild(&g);sightline:=runtime_interactive_index(&g,"shutter_crank");if sightline>=0 {g.context_ui.current=context_runtime_target(&g,sightline);g.context_ui.focus_started=-1}}
	if capture_mode&&argument=="--capture-characters" {g.character_studio=true;g.player_x=-3;g.player_y=0;g.player_angle=math.PI/2;g.camera_x=0;g.camera_y=0;g.camera_orbit=math.PI/2;g.camera_zoom=.70}
	if capture_mode&&context_capture {g.screen=.Investigate;g.player_x=16;g.player_y=14;g.player_angle=0;g.camera_x=16;g.camera_y=14;g.camera_initialized=true;if argument=="--capture-context-orbit" do g.camera_orbit= -math.PI/3;runtime_interactives_rebuild(&g);target:=context_entity_target(&g,0);if argument=="--capture-context-evidence" do target=context_entity_target(&g,3);if argument=="--capture-context-door"||argument=="--capture-context-locked" {target=context_runtime_target(&g,0);if argument=="--capture-context-locked" {g.interactives[0].locked=true;target=context_runtime_target(&g,0)}};g.context_ui.current=target;g.context_ui.focus_started=-1;if argument=="--capture-context-xbox"||argument=="--capture-context-playstation"||argument=="--capture-context-switch" {g.active_device=.Gamepad;if argument=="--capture-context-playstation" do g.gamepad_type=.PS5;else if argument=="--capture-context-switch" do g.gamepad_type=.NINTENDO_SWITCH_PRO}}
	if capture_mode&&argument=="--capture-context-idle" {g.screen=.Investigate;g.context_ui.current={};g.context_ui.location_changed_at=-10}
	if capture_mode&&(argument=="--capture-officer"||argument=="--capture-officer-confirm") {g.screen=.Dialogue;g.dialogue_entity=world_entity_index("officer_lead");g.active_device=.Keyboard_Mouse;g.dialogue_response=officer_opening_line("officer_lead");g.end_confirm=argument=="--capture-officer-confirm";dialogue_focus_default(&g)}
	if capture_mode&&(argument=="--capture-context-landmark"||argument=="--capture-context-vehicle") {g.screen=.Exterior;g.city_camera_initialized=true;if argument=="--capture-context-landmark" {g.city_x=city_world(18.5);g.city_y=city_world(20.2);g.city_camera_x=g.city_x;g.city_camera_y=g.city_y;g.near_landmark=0}else{g.city_x=g.vehicles[0].x;g.city_y=g.vehicles[0].y+1;g.city_camera_x=g.city_x;g.city_camera_y=g.city_y;g.near_vehicle=0};context_resolve_city(&g);g.context_ui.focus_started=-1}
	if capture_mode&&argument=="--capture-dialogue-notebook" {g.notebook_return=.Dialogue;g.dialogue_entity=world_entity_index("miriam");_=learn_initial_claims(&g,"miriam");g.notebook_tab=1;g.notebook_return_focus=button_id(dialogue_default_rect(&g));g.active_device=.Keyboard_Mouse}
	if capture_mode&&argument=="--capture-game-over" {g.screen=.Game_Over;g.game_over_reason="Time expired before a complete reconstruction was prepared."}
	if capture_mode&&argument=="--capture-pause" {g.pause_return=.Investigate;g.screen=.Pause}
	if capture_mode&&argument=="--capture-floorplan" {g.screen=.Investigate;g.player_x=24;g.player_y=22;g.camera_x=24;g.camera_y=22;g.camera_initialized=true}
	if capture_mode&&argument=="--capture-topdown-floorplan" {g.screen=.Investigate;g.player_x=24;g.player_y=22;g.camera_x=24;g.camera_y=22;g.camera_initialized=true;g.top_down_camera=true}
	if capture_mode&&(argument=="--capture-build"||argument=="--capture-build-drag"||argument=="--capture-build-catalog"||argument=="--capture-build-placement"||argument=="--capture-build-materials"||argument=="--capture-build-wall-paint"||argument=="--capture-build-room-draw"||argument=="--capture-build-room-rectangle") {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;if argument=="--capture-build-catalog" {g.build_tool=.Plant;editor_state.catalog_category="objects"} else if argument=="--capture-build-placement" {g.build_tool=.Plant;editor_state.catalog_category="objects";editor_state.catalog_id="sofa";editor_state.placement_active=true;editor_state.placement_position={10,7};editor_state.placement_rotation=30;editor_state.placement_preview=level_preview_transaction(&level_document,Level_Command{kind=.Place_Object,a=editor_state.placement_position,value=editor_state.placement_rotation,material=editor_state.catalog_id})} else if argument=="--capture-build-materials" {g.build_tool=.Paint;editor_state.catalog_category="materials";editor_state.catalog_id="study";hover:=level_pick(&level_document,{4,8});if hover.kind==.Room {editor_state.paint_hover=hover;editor_state.paint_hover_active=true}} else if argument=="--capture-build-wall-paint" {g.build_tool=.Wall_Paint;editor_state.catalog_category="materials";editor_state.catalog_id="dining";hover:=level_pick(&level_document,{4,8});if hover.kind==.Room {editor_state.paint_hover=hover;editor_state.paint_hover_active=true;room_index:=level_room_index(&level_document,hover.entity_id);if room_index>=0 {level_document.rooms[room_index].wall_material="dining";level_project_runtime(&level_document)}}} else if argument=="--capture-build-room-draw" {g.build_tool=.Room;editor_state.room_mode=.Polygon;editor_state.room_draw_count=5;editor_state.room_draw_points[0]={4,4};editor_state.room_draw_points[1]={8,4};editor_state.room_draw_points[2]={9.5,6.5};editor_state.room_draw_points[3]={7,9};editor_state.room_draw_points[4]={4,8};draw_cursor,_:=editor_world_screen(&g,{4,4});g.input.mouse_pos=draw_cursor} else if argument=="--capture-build-room-rectangle" {g.build_tool=.Room;editor_state.room_mode=.Rectangle;editor_state.room_rectangle_active=true;editor_state.room_rectangle_start={9,5};editor_state.room_rectangle_current={15,10};editor_state.room_rectangle_preview=level_preview_transaction(&level_document,Level_Command{kind=.Create_Room,a=editor_state.room_rectangle_start,b=editor_state.room_rectangle_current,material="wood"});g.input.mouse_pos,_=editor_world_screen(&g,editor_state.room_rectangle_current)} else if len(level_document.rooms)>0 {editor_state.selection[0]={.Room,level_document.rooms[0].id,-1};editor_state.selection_count=1;if argument=="--capture-build-drag" {editor_state.drag_active=true;editor_state.drag_selection=editor_state.selection[0];editor_state.drag_delta={1.25,.75};command,_:=level_selection_move_command(&level_document,editor_state.drag_selection,editor_state.drag_delta);editor_state.drag_preview=level_preview_transaction(&level_document,command)}}}
	if capture_mode&&argument=="--capture-build-wall-paint" {g.build_tool=.Paint;editor_state.paint_target=.Walls}
	if capture_mode&&argument=="--capture-build-eyedropper" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Paint;editor_state.catalog_category="materials";editor_state.paint_target=.Walls;editor_state.paint_eyedropper=true;hover:=level_pick(&level_document,{4,8});if hover.kind==.Room {editor_state.paint_hover=hover;editor_state.paint_hover_active=true};g.input.mouse_pos,_=editor_world_screen(&g,{4,8})}
	if capture_mode&&argument=="--capture-build-terrain" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=false;g.editor_mode=.Build;g.build_tool=.Terrain;editor_state.terrain_mode=.Smooth;editor_state.terrain_radius=1;editor_state.terrain_strength=.75;_,_ = level_apply_raw(&level_document,Level_Command{kind=.Sculpt_Terrain,a={10,8},b={14,10},c={1.5,0},value=1,brush=.Raise});rebuild_generated_ground(&level_document);editor_state.terrain_stroke_active=true;editor_state.terrain_stroke_start={10,8};editor_state.terrain_stroke_current={14,10};g.input.mouse_pos,_=editor_world_screen(&g,editor_state.terrain_stroke_current)}
	if capture_mode&&(argument=="--capture-build-foundation"||argument=="--capture-build-foundation-limit") {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=false;g.editor_mode=.Build;g.build_tool=.Foundation;editor_state.foundation_kind=.Raised;editor_state.foundation_elevation=argument=="--capture-build-foundation-limit"?.25:.5;editor_state.foundation_depth=.5;editor_state.foundation_rectangle_active=true;editor_state.foundation_rectangle_start={9,7};editor_state.foundation_rectangle_current={15,11};command:=Level_Command{kind=.Create_Foundation,value=.5,c={f32(Level_Foundation_Kind.Raised),.5},point_count=4};command.points[0]={9,7};command.points[1]={15,7};command.points[2]={15,11};command.points[3]={9,11};editor_state.foundation_rectangle_preview=level_preview_transaction(&level_document,command);g.input.mouse_pos,_=editor_world_screen(&g,editor_state.foundation_rectangle_current)}
	if capture_mode&&argument=="--capture-build-foundation-polygon" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Foundation;editor_state.foundation_kind=.Basement;editor_state.foundation_mode=.Polygon;editor_state.foundation_depth=2.75;editor_state.foundation_draw_count=6;editor_state.foundation_draw_points[0]={9,5};editor_state.foundation_draw_points[1]={15,5};editor_state.foundation_draw_points[2]={15,7};editor_state.foundation_draw_points[3]={12,7};editor_state.foundation_draw_points[4]={12,11};editor_state.foundation_draw_points[5]={9,11};editor_state.foundation_polygon_preview={.Valid,"CLICK FIRST POINT OR ENTER TO CLOSE",{}, {}};g.input.mouse_pos,_=editor_world_screen(&g,editor_state.foundation_draw_points[0])}
	if capture_mode&&argument=="--capture-build-foundation-shell" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Room;points:=make([dynamic]Vec2,0,6);append(&points,Vec2{16,9},Vec2{22,9},Vec2{22,11},Vec2{19,11},Vec2{19,14},Vec2{16,14});append(&level_document.foundations,Level_Foundation{id="capture_shell_foundation",kind=.Raised,story=-1,points=points,elevation=.75,depth=.25});rebuild_generated_stories(&level_document);editor_state.selection[0]={.Foundation,"capture_shell_foundation",-1};editor_state.selection_count=1;origin,ok:=editor_selection_toolbar_origin(&g);if ok do g.input.mouse_pos={origin.x+18,origin.y+13}}
	if capture_mode&&argument=="--capture-build-foundation-point-drag" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Select;points:=make([dynamic]Vec2,0,6);append(&points,Vec2{8,5},Vec2{14,5},Vec2{14,8},Vec2{11,8},Vec2{11,12},Vec2{8,12});append(&level_document.foundations,Level_Foundation{id="capture_edit_foundation",kind=.Raised,story=-1,points=points,elevation=.75,depth=.25});rebuild_generated_stories(&level_document);editor_state.selection[0]={.Foundation,"capture_edit_foundation",-3};editor_state.selection_count=1;editor_state.drag_active=true;editor_state.drag_selection=editor_state.selection[0];editor_state.drag_delta={1,.5};command,ok:=level_selection_move_command(&level_document,editor_state.drag_selection,editor_state.drag_delta);if ok do editor_state.drag_preview=level_preview_transaction(&level_document,command)}
	if capture_mode&&argument=="--capture-build-room-split" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Wall;g.build_anchor={0,10};g.build_has_anchor=true;editor_state.wall_preview_point={8,10};editor_state.wall_preview_active=true}
	if capture_mode&&argument=="--capture-build-room-merge" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Select;command,split:=level_wall_command(&level_document,{0,10},{8,10});if split {_,ok:=level_apply_raw(&level_document,command);if ok {level_document.revision+=1;level_project_runtime(&level_document);editor_state.selection[0]={.Room,command.entity_id,-1};editor_state.selection[1]={.Room,command.destination,-1};editor_state.selection_count=2}};g.input.mouse_pos={776,622}}
	if capture_mode&&argument=="--capture-build-opening" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Window;host:=Editor_Selection{.Path,"shell",0};command,ok:=level_opening_command_at(&level_document,host,{6,0},.Window);if ok {editor_state.opening_active=true;editor_state.opening_host=host;editor_state.opening_command=command;editor_state.opening_preview=level_preview_transaction(&level_document,command);editor_state.opening_position=editor_state.opening_preview.bounds_min}}
	if capture_mode&&(argument=="--capture-build-window-selected"||argument=="--capture-build-window-drag"||argument=="--capture-build-window-edit") {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Select;for opening in level_document.openings {if opening.kind==.Window {editor_state.selection[0]={.Opening,opening.id,opening.segment};editor_state.selection_count=1;if argument=="--capture-build-window-drag" {editor_state.drag_active=true;editor_state.drag_selection=editor_state.selection[0];path_index:=level_path_index(&level_document,opening.host_path);if path_index>=0&&opening.segment>=0&&opening.segment<len(level_document.paths[path_index].points)-1 {a,b:=level_document.paths[path_index].points[opening.segment],level_document.paths[path_index].points[opening.segment+1];dx,dy:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dy*dy)));if length>.001 {editor_state.drag_delta={dx/length*.75,dy/length*.75};command,ok:=level_selection_move_command(&level_document,editor_state.drag_selection,editor_state.drag_delta);if ok do editor_state.drag_preview=level_preview_transaction(&level_document,command)}}}else if argument=="--capture-build-window-edit" {editor_begin_numeric_edit(.Opening_Width,opening.width);g.input.mouse_pos={1062,249}};break}}}
	if capture_mode&&argument=="--capture-build-roof" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=false;g.editor_mode=.Build;g.build_tool=.Roof;editor_state.roof_style=.Gable;editor_state.roof_pitch=30;editor_state.roof_overhang=.4;editor_state.roof_gutters=true;if len(level_document.rooms)>0 {room:=level_document.rooms[0];existing:=level_roof_for_room(&level_document,room.id);if existing<0 do append(&level_document.roofs,Level_Roof{id="capture_roof",room_id=room.id,story=room.story,style=.Gable,pitch=30,overhang=.4,ridge_angle=45,gutters=true});else do level_document.roofs[existing].gutters=true;rebuild_generated_roofs(&level_document);editor_state.roof_hover={.Room,room.id,-1};editor_state.roof_hover_active=true;editor_state.roof_preview={.Valid,"READY",{}, {}}}}
	if capture_mode&&(argument=="--capture-build-roof-selected"||argument=="--capture-build-roof-numeric") {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=false;g.editor_mode=.Build;g.build_tool=.Select;editor_set_view(&g,.Roof);if len(level_document.rooms)>0 {room:=level_document.rooms[0];existing:=level_roof_for_room(&level_document,room.id);if existing<0 {append(&level_document.roofs,Level_Roof{id="capture_roof_selected",room_id=room.id,story=room.story,style=.Gable,pitch=35,overhang=.45,ridge_angle=45,gutters=true});existing=len(level_document.roofs)-1};rebuild_generated_roofs(&level_document);editor_state.selection[0]={.Roof,level_document.roofs[existing].id,-1};editor_state.selection_count=1;if argument=="--capture-build-roof-numeric" {editor_begin_numeric_edit(.Roof_Pitch,level_document.roofs[existing].pitch);editor_state.numeric_replace_on_input=false;g.input.mouse_pos={1060,188}}else do g.input.mouse_pos={1060,330}}}
	if capture_mode&&argument=="--capture-build-mansard" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=false;g.editor_mode=.Build;g.build_tool=.Roof;editor_state.roof_style=.Mansard;editor_state.roof_pitch=65;editor_state.roof_overhang=.35;if len(level_document.rooms)>0 {room:=level_document.rooms[0];clear(&level_document.roofs);append(&level_document.roofs,Level_Roof{id="capture_mansard",room_id=room.id,story=room.story,style=.Mansard,pitch=65,overhang=.35});rebuild_generated_roofs(&level_document);editor_state.roof_hover={.Room,room.id,-1};editor_state.roof_hover_active=true;editor_state.roof_preview={.Valid,"MANSARD WITH DORMERS",{}, {}}}}
	if capture_mode&&argument=="--capture-roof-overhead" {g.screen=.Investigate;garden_index:=level_room_index(&level_document,"moon_garden");center:=garden_index>=0?level_room_center(&level_document.rooms[garden_index]):Vec2{20,16};g.player_x=center.x;g.player_y=center.y;g.camera_x=center.x;g.camera_y=center.y;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Roof;editor_set_view(&g,.Top_Down);editor_state.selection_count=0;editor_state.roof_hover_active=false;rebuild_generated_roofs(&level_document)}
	if capture_mode&&argument=="--capture-build-stairs" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=false;g.editor_mode=.Build;g.build_tool=.Stairs;editor_state.link_kind=.Stairs;editor_state.link_width=1;if len(level_document.stories)<2 do append(&level_document.stories,Level_Story{"capture_upper","Upper",3,2.5});append(&level_document.vertical_links,Level_Vertical_Link{id="capture_stairs",kind=.Stairs,from_story=0,to_story=1,start={9,6},finish={13,10},width=1});rebuild_generated_links(&level_document);editor_state.link_anchor_active=true;editor_state.link_anchor={9,6};editor_state.link_finish={13,10};editor_state.link_preview=level_preview_transaction(&level_document,Level_Command{kind=.Create_Vertical_Link,a={9,6},b={13,10},c={f32(Level_Vertical_Link_Kind.Stairs),0},value=1})}
	if capture_mode&&(argument=="--capture-build-stairs-selected"||argument=="--capture-build-stairs-point-drag") {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Select;if len(level_document.stories)<2 do append(&level_document.stories,Level_Story{"capture_upper","Upper",3,2.5});append(&level_document.vertical_links,Level_Vertical_Link{id="capture_stairs_selected",kind=.Stairs,from_story=0,to_story=1,start={9,6},finish={13,10},width=1});rebuild_generated_links(&level_document);editor_state.selection[0]={.Vertical_Link,"capture_stairs_selected",-1};editor_state.selection_count=1;if argument=="--capture-build-stairs-point-drag" {editor_state.selection[0]={.Vertical_Link,"capture_stairs_selected",-3};editor_state.drag_active=true;editor_state.drag_selection=editor_state.selection[0];editor_state.drag_delta={1,.5};command,ok:=level_selection_move_command(&level_document,editor_state.drag_selection,editor_state.drag_delta);if ok do editor_state.drag_preview=level_preview_transaction(&level_document,command)}}
	if capture_mode&&argument=="--capture-build-path" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Path;editor_state.path_kind=.Footpath;editor_state.path_width=1.4;points:=make([dynamic]Vec2,0,4);append(&points,Vec2{8.5,6},Vec2{10,7},Vec2{12.5,9},Vec2{15.5,11});append(&level_document.paths,Level_Path{id="capture_path",story=0,kind=.Footpath,points=points,material="gravel",width=1.4});rebuild_generated_ground(&level_document);editor_state.path_draw_count=4;copy(editor_state.path_draw_points[:],points[:]);g.input.mouse_pos,_=editor_world_screen(&g,points[len(points)-1])}
	if capture_mode&&(argument=="--capture-build-path-selected"||argument=="--capture-build-path-edit"||argument=="--capture-build-path-point-drag") {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Select;points:=make([dynamic]Vec2,0,4);append(&points,Vec2{8.5,6},Vec2{10,7},Vec2{12.5,9},Vec2{15.5,11});append(&level_document.paths,Level_Path{id="capture_path_selected",story=0,kind=.Footpath,points=points,material="gravel",width=1.4});rebuild_generated_ground(&level_document);editor_state.selection[0]={.Path,"capture_path_selected",-1};editor_state.selection_count=1;if argument=="--capture-build-path-edit" {editor_begin_numeric_edit(.Path_Width,1.4);g.input.mouse_pos={1062,213}}else if argument=="--capture-build-path-point-drag" {editor_state.selection[0]={.Path,"capture_path_selected",-4};editor_state.drag_active=true;editor_state.drag_selection=editor_state.selection[0];editor_state.drag_delta={1,.5};command,ok:=level_selection_move_command(&level_document,editor_state.drag_selection,editor_state.drag_delta);if ok do editor_state.drag_preview=level_preview_transaction(&level_document,command)}}
	if capture_mode&&argument=="--capture-build-water" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Water;editor_state.water_elevation=.25;points:=make([dynamic]Vec2,0,5);append(&points,Vec2{9,6},Vec2{13,6},Vec2{15,8},Vec2{13.5,11},Vec2{9.5,10.5});append(&level_document.waters,Level_Water{id="capture_pond",points=points,elevation=.25});rebuild_generated_ground(&level_document);editor_state.water_draw_count=5;copy(editor_state.water_draw_points[:],points[:]);g.input.mouse_pos,_=editor_world_screen(&g,points[0])}
	if capture_mode&&argument=="--capture-build-water-selected" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Select;points:=make([dynamic]Vec2,0,5);append(&points,Vec2{9,6},Vec2{13,6},Vec2{15,8},Vec2{13.5,11},Vec2{9.5,10.5});append(&level_document.waters,Level_Water{id="capture_pond_selected",points=points,elevation=.25});rebuild_generated_ground(&level_document);editor_state.selection[0]={.Water,"capture_pond_selected",-1};editor_state.selection_count=1}
	if capture_mode&&argument=="--capture-pond-beauty" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.None;clear(&level_document.waters);points:=make([dynamic]Vec2,0,7);append(&points,Vec2{8.5,6.5},Vec2{10.5,5.4},Vec2{13.2,5.8},Vec2{15.2,7.6},Vec2{14.4,10.4},Vec2{11.8,11.4},Vec2{9.2,9.8});append(&level_document.waters,Level_Water{id="capture_pond_beauty",points=points,elevation=.25});rebuild_generated_ground(&level_document)}
	if capture_mode&&argument=="--capture-pond-third-person" {g.screen=.Investigate;g.player_x=12;g.player_y=8.5;g.player_angle=-math.PI/2;g.camera_x=12.5;g.camera_y=5.2;g.camera_initialized=true;g.camera_orbit=math.PI;g.camera_orbit_initialized=true;g.camera_zoom=.55;g.top_down_camera=false;g.editor_mode=.None;g.environment_blend=1;rebuild_generated_ground(&level_document)}
	if capture_mode&&(argument=="--capture-build-markers"||argument=="--capture-build-marker-numeric") {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Marker;clear(&level_document.markers);for kind in Level_Marker_Kind {index:=int(kind);reference:="";if kind==.Interaction&&len(payload.pois)>0 do reference=payload.pois[0].entity_id;append(&level_document.markers,Level_Marker{id=fmt.tprintf("capture_marker_%d",index),reference=reference,kind=kind,story=0,position={5+f32(index%4)*3.5,5+f32(index/4)*4},radius=.65,facing=f32(index)*45,camera_height=2})};editor_state.marker_kind=.Interaction;editor_state.marker_radius=.75;selected_id:=argument=="--capture-build-marker-numeric"?"capture_marker_6":"capture_marker_2";editor_state.selection[0]={.Marker,selected_id,-1};editor_state.selection_count=1;if argument=="--capture-build-marker-numeric" {index:=level_marker_index(&level_document,selected_id);if index>=0 {editor_begin_numeric_edit(.Marker_Facing,level_document.markers[index].facing);editor_state.numeric_replace_on_input=false};g.input.mouse_pos={1040,364}}}
	if capture_mode&&argument=="--capture-build-diagnostics" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Select;points:=make([dynamic]Vec2,0,3);append(&points,Vec2{7,7},Vec2{7.1,7},Vec2{7,7.1});append(&level_document.rooms,Level_Room{id="broken_room",name="Broken Room",story=0,points=points});append(&level_document.objects,Level_Object{id="uncatalogued_object",story=0,position={12,8}});append(&level_document.roofs,Level_Roof{id="orphaned_roof",room_id="missing_room",story=0,pitch=90});_=level_validate(&level_document);editor_state.diagnostics_visible=true;editor_state.diagnostic_selected=0;editor_state.selection_count=0}
	if capture_mode&&argument=="--capture-build-playtest" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Select;editor_state.selection[0]={.Marker,"spawn_player",-1};editor_state.selection_count=1;_=editor_begin_playtest(&g)}
	if capture_mode&&argument=="--capture-build-selection" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.editor_mode=.Build;g.build_tool=.Select;editor_set_view(&g,.Markers);editor_state.selection[0]={.Room,"study",-1};editor_state.selection[1]={.Room,"gallery",-1};editor_state.selection[2]={.Marker,"marker_miriam",-1};editor_state.selection_count=3;editor_state.box_select_active=true;editor_state.box_select_start={1,1};editor_state.box_select_current={14,10}}
	if capture_mode&&argument=="--capture-build-delete-feedback" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Select;editor_state.selection_count=0;editor_show_feedback("DELETED OBJECT  ·  CTRL/CMD Z TO UNDO")}
	if capture_mode&&argument=="--capture-build-duplicate-feedback" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Select;editor_state.selection_count=0;editor_show_feedback("DUPLICATED 3 ITEMS  ·  CTRL/CMD Z TO UNDO")}
	if capture_mode&&argument=="--capture-build-recovery-feedback" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Select;level_document.dirty=true;editor_state.selection_count=0;editor_show_feedback("AUTOSAVE RESTORED  ·  SAVE TO KEEP THIS VERSION")}
	if capture_mode&&argument=="--capture-build-save-failed" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Select;level_document.dirty=true;editor_state.selection_count=0;editor_show_feedback("SAVE FAILED  ·  CHECK FILE PERMISSIONS",true)}
	if capture_mode&&argument=="--capture-build-view-cycle" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=false;g.editor_mode=.Build;g.build_tool=.Select;editor_state.view=.Cutaway;editor_show_feedback("VIEW  ·  CUTAWAY")}
	if capture_mode&&argument=="--capture-build-view-menu" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Select;editor_state.view=.Top_Down;editor_state.view_menu_visible=true}
	if capture_mode&&argument=="--capture-build-undo-feedback" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Select;editor_state.selection_count=0;editor_show_feedback("UNDO RESTORED PREVIOUS STATE")}
	if capture_mode&&argument=="--capture-build-blocked-placement" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Door;editor_state.opening_active=false;g.input.mouse_pos={650,360}}
	if capture_mode&&argument=="--capture-build-shortcuts" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Select;editor_state.shortcut_help_visible=true}
	if capture_mode&&argument=="--capture-build-tool-shortcut" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=false;g.editor_mode=.Build;editor_activate_build_mode(&g,.Roof)}
	if capture_mode&&argument=="--capture-build-tool-hover" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Select;box:=build_tool_grid_rect(5);g.input.mouse_pos={box.x+box.w*.5,box.y+box.h*.5}}
	if capture_mode&&argument=="--capture-build-exit-confirm" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Select;level_document.dirty=true;editor_state.exit_confirm_visible=true}
	if capture_mode&&argument=="--capture-build-catalog-search" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Plant;editor_state.catalog_category="objects";editor_state.search_buffer[0]='s';editor_state.search_buffer[1]='o';editor_state.search_buffer[2]='f';editor_state.search_count=3;editor_state.search_active=true}
	if capture_mode&&argument=="--capture-build-catalog-pinned" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Plant;_=catalog_toggle_pinned(&editor_state,"chair");_=catalog_toggle_pinned(&editor_state,"sofa");_=catalog_toggle_pinned(&editor_state,"floor_lamp");editor_state.catalog_category="pinned";editor_state.catalog_id="sofa";g.input.mouse_pos={232,288}}
	if capture_mode&&(argument=="--capture-build-object-selected"||argument=="--capture-build-object-edit"||argument=="--capture-build-object-rotate") {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.top_down_camera=true;g.editor_mode=.Build;g.build_tool=.Select;for &object in level_document.objects {if object.catalog_id!="" {editor_state.selection[0]={.Object,object.id,-1};editor_state.selection_count=1;g.camera_x=object.position.x;g.camera_y=object.position.y;if argument=="--capture-build-object-edit" {editor_begin_numeric_edit(.Object_X,object.position.x);g.input.mouse_pos={1062,261}}else if argument=="--capture-build-object-rotate" {editor_state.object_rotate_active=true;editor_state.object_rotate_id=object.id;editor_state.object_rotate_original=object.rotation;editor_state.object_rotate_preview=135;object.rotation=135};break}}}
	if capture_mode&&argument=="--capture-build-room-measures" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.editor_mode=.Build;g.build_tool=.Select;editor_set_view(&g,.Top_Down);editor_state.snap_mode=.Construction;editor_state.selection[0]={.Room,"study",-1};editor_state.selection_count=1}
	if capture_mode&&argument=="--capture-build-navmesh" {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.editor_mode=.Build;g.build_tool=.Select;editor_set_view(&g,.Navmesh);editor_state.selection_count=0}
	if capture_mode&&argument=="--capture-vale-house-props" {g.screen=.Investigate;g.player_x=24;g.player_y=26;g.camera_x=24;g.camera_y=26;g.camera_initialized=true;g.editor_mode=.Build;g.build_tool=.Select;editor_set_view(&g,.Top_Down);editor_state.selection_count=0;clear(&level_document.roofs);rebuild_generated_roofs(&level_document)}
	if capture_mode&&(argument=="--capture-build-lighting"||argument=="--capture-build-lighting-control"||argument=="--capture-build-lighting-numeric") {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.editor_mode=.Build;g.build_tool=.Light;editor_set_view(&g,.Lighting);light_id:="light_gallery_spot";index:=level_light_index(&level_document,light_id);if index<0 {append(&level_document.lights,Level_Light{id=light_id,kind=.Spot,story=0,position={12,14},elevation=2.3,range=4.5,intensity=1.1,facing=270,cone_angle=38,color={222,235,255,255}});index=len(level_document.lights)-1};editor_state.selection[0]={.Light,light_id,-1};editor_state.selection_count=1;if argument=="--capture-build-lighting-numeric" {editor_begin_numeric_edit(.Light_Intensity,level_document.lights[index].intensity);editor_state.numeric_replace_on_input=false;g.input.mouse_pos={1040,308}}}
	if capture_mode&&(argument=="--capture-lighting-low"||argument=="--capture-lighting-medium"||argument=="--capture-lighting-high"||argument=="--capture-lighting-ultra") {
		g.screen=.Investigate;g.player_x=9;g.player_y=5;g.camera_x=9;g.camera_y=5;g.camera_initialized=true;g.camera_orbit=f32(math.PI)*.25;g.camera_orbit_initialized=true;g.camera_zoom=.32;g.environment_blend=0;g.cutaway_transition=1;g.wall_view=.Walls_Down;for &amount in g.wall_cutaways do amount=1;editor_state.view=.Cutaway
		g.lighting_quality=argument=="--capture-lighting-low"?.Low:argument=="--capture-lighting-medium"?.Medium:argument=="--capture-lighting-high"?.High:.Ultra
		clear(&level_document.objects);clear(&level_document.lights);clear(&level_document.waters);clear(&level_document.rooms);test_floor:=make([dynamic]Vec2,0,4);append(&test_floor,Vec2{0,0},Vec2{8.8,0},Vec2{8.8,8},Vec2{0,8});append(&level_document.rooms,Level_Room{id="lighting_test_floor",name="Lighting Test Floor",story=0,points=test_floor,floor_material="gallery",wall_material="gallery",ceiling_style="none"});rebuild_generated_ground(&level_document);fixture_ids:=[8]string{"floor_lamp","floor_lamp_round","table_lamp_square","table_lamp_round","floor_lamp","floor_lamp_round","ceiling_lamp_square","ceiling_fan"};fixture_positions:=[8]Vec2{{3,2.5},{7,2.5},{11,2.5},{15,2.5},{3,6},{7,6},{11,6},{15,6}};light_colors:=[8][4]u8{{255,166,92,255},{112,174,255,255},{255,205,126,255},{150,118,255,255},{255,128,92,255},{102,205,235,255},{255,225,166,255},{174,142,255,255}};for fixture,index in fixture_ids {elevation:=f32(0);if strings.contains(fixture,"table_lamp") do elevation=.76;if strings.contains(fixture,"ceiling") do elevation=2.25;append(&level_document.objects,Level_Object{id=fmt.tprintf("capture_light_fixture_%d",index),catalog_id=fixture,story=0,position=fixture_positions[index],elevation=elevation,rotation=f32(index)*45,tint={255,255,255,255},bark_tint={255,255,255,255},foliage_tint={255,255,255,255}});append(&level_document.lights,Level_Light{id=fmt.tprintf("capture_light_pool_%d",index),kind=index==3?.Spot:.Point,story=0,position=fixture_positions[index],elevation=index>=6?f32(2.1):f32(1.2),range=5.5,intensity=2.2,facing=225,cone_angle=55,color=light_colors[index]})}
		prop_ids:=[7]string{"dining_table","chair","chair","chair","chair","sofa","plant"};prop_positions:=[7]Vec2{{9,4.5},{7.4,4.5},{10.6,4.5},{9,3.2},{9,5.8},{4.8,4.3},{13.2,4.3}};for prop,index in prop_ids do append(&level_document.objects,Level_Object{id=fmt.tprintf("capture_shadow_prop_%d",index),catalog_id=prop,story=0,position=prop_positions[index],rotation=index==5?f32(90):f32(index)*45,tint={205,188,166,255},bark_tint={96,69,45,255},foliage_tint={62,118,69,255}})
		level_document.revision+=1;level_project_runtime(&level_document)
	}
	if capture_mode&&(argument=="--capture-build-stories"||argument=="--capture-build-story-up") {g.screen=.Investigate;g.player_x=12;g.player_y=8;g.camera_x=12;g.camera_y=8;g.camera_initialized=true;g.editor_mode=.Build;g.build_tool=.Select;upper_points:=make([dynamic]Vec2,0,4);append(&upper_points,Vec2{3,3},Vec2{17,3},Vec2{17,12},Vec2{3,12});upper_walls:=make([dynamic]Vec2,0,5);append(&upper_walls,Vec2{3,3},Vec2{17,3},Vec2{17,12},Vec2{3,12},Vec2{3,3});append(&level_document.stories,Level_Story{"upper","Upper",3,2.5});append(&level_document.rooms,Level_Room{id="upper_lounge",name="Upper Lounge",story=1,points=upper_points,floor_material="gallery",wall_material="gallery",ceiling_style="flat"});append(&level_document.paths,Level_Path{id="upper_shell",story=1,kind=.Wall,points=upper_walls,material="structure",width=HOUSE_WALL_THICKNESS});append(&level_document.objects,Level_Object{id="upper_sofa",catalog_id="sofa",story=1,position={10,7},rotation=90,tint={255,255,255,255}});level_document.active_story=1;level_document.revision+=1;level_project_runtime(&level_document);editor_set_view(&g,.Cutaway);editor_state.selection[0]={.Room,"upper_lounge",-1};editor_state.selection_count=1}
	if capture_mode&&argument=="--capture-build-foundation-shell" {g.player_x=20;g.player_y=16;g.camera_x=20;g.camera_y=16}
	if capture_mode&&argument=="--capture-attributes" {g.screen=.Attributes;g.attribute_selected=1;g.menu_detail_return=.Investigate}
	if capture_mode&&argument=="--capture-introduction" {g.screen=.Introduction;g.introduction_step=1}
	if capture_mode&&argument=="--capture-reveal" {configure_complete_questions(&g);mystery_game_mark_all_clues(&g);g.screen=.Reveal;_=mystery_game_mark_reveal_presented(&g,0)}
	if capture_mode&&argument=="--capture-reveal-other-lies" {configure_complete_questions(&g);mystery_game_mark_all_clues(&g);g.screen=.Reveal;g.reveal_act=3;_=mystery_game_mark_reveal_presented(&g,3)}
	if capture_mode&&(argument=="--capture-result-airtight"||argument=="--capture-result-canonical") {configure_complete_questions(&g);mystery_game_mark_all_clues(&g);g.result=.Airtight;_=enter_case_ending(&g,case_ending_trigger_for_outcome(g.result));if argument=="--capture-result-canonical" do g.show_canonical=true}
	if capture_mode&&argument=="--capture-ending" {ending_id:=argument_value("--ending=");if ending_id=="" {fmt.eprintln("ending capture requires --ending=<id>");return};if !enter_case_ending(&g,ending_id) {fmt.eprintln("unknown ending ID: ",ending_id);return}}
	if capture_mode&&argument=="--capture-walking" {g.screen=.Investigate;g.player_is_walking=true;g.player_animation.current=glb_clip_index(&character_meshes[0],"Walking_B");g.player_animation.time=.24;g.move_target_active=true;g.move_target_x=6.5;g.move_target_y=11.5}
	if capture_mode&&argument=="--capture-case-sense" {g.screen=.Investigate;g.player_x=10;g.player_y=20;g.camera_x=10;g.camera_y=20;mystery_game_reveal_all_pois(&g);g.case_sense_level=1;g.case_sense_hint_until=5}
	if capture_mode&&argument=="--capture-shutter-motion" {g.screen=.Investigate;g.player_x=18.1;g.player_y=26.8;g.camera_x=17.8;g.camera_y=26.8;g.camera_initialized=true;g.environment_blend=1;g.cutaway_transition=1;for &amount in g.wall_cutaways do amount=1;g.shutter_time=2;g.shutter_view=1;g.shutter_open=true;g.shutter_operated=true;g.shutter_position=.55;g.shutter_target=1;g.shutter_feedback="The resistant crank turns as the heavy slats climb through the frame.";editor_state.view=.Cutaway}
	if capture_mode&&(argument=="--capture-shutter-crank"||argument=="--capture-shutter-crank-closed"||argument=="--capture-shutter-crank-open"||argument=="--capture-shutter-crank-evidence") {g.screen=.Investigate;g.player_x=16.35;g.player_y=27.18;g.player_angle=0;g.first_person_camera=true;g.environment_blend=1;g.cutaway_transition=1;for &amount in g.wall_cutaways do amount=1;mystery_game_reveal_all_pois(&g);g.shutter_time=2;g.shutter_view=1;g.shutter_position=argument=="--capture-shutter-crank-closed"?f32(0):argument=="--capture-shutter-crank-open"?f32(1):argument=="--capture-shutter-crank-evidence"?f32(.63):f32(.55);g.shutter_open=g.shutter_position>.5;g.shutter_operated=true;g.shutter_thread_found=argument=="--capture-shutter-crank-evidence";g.shutter_target=g.shutter_position;g.shutter_feedback=g.shutter_thread_found?"Fresh wear inside the housing shows that the shutter was operated recently.":g.shutter_position==0?"The shutter is locked shut.":g.shutter_position==1?"The shutter is fully open.":"The resistant brass crank turns as the heavy slats climb through the frame.";runtime_interactives_rebuild(&g);if g.shutter_thread_found do context_feedback(&g,"RECENT WEAR INSIDE THE CRANK HOUSING",.Complete,"shutter_crank")}
	if capture_mode&&(argument=="--capture-shutter-crank-prompt-open"||argument=="--capture-shutter-crank-prompt-close") {g.screen=.Investigate;g.player_x=17.12;g.player_y=28.07;g.player_angle=0;g.first_person_camera=true;g.environment_blend=1;g.cutaway_transition=1;for &amount in g.wall_cutaways do amount=1;mystery_game_reveal_all_pois(&g);g.shutter_time=2;g.shutter_view=1;g.shutter_open=argument=="--capture-shutter-crank-prompt-close";g.shutter_position=g.shutter_open?f32(1):f32(0);g.shutter_target=g.shutter_position;runtime_interactives_rebuild(&g);for &entity,i in WORLD_ENTITIES do if entity.source_id=="shutter_crank" {g.context_ui.current=context_entity_target(&g,i);g.context_ui.focus_started=-1}}
	if capture_mode&&argument=="--capture-world" {g.screen=.Investigate;g.player_x=20;g.player_y=4;g.camera_x=20;g.camera_y=16;g.camera_initialized=true;g.environment_blend=1;g.cutaway_transition=0}
	if capture_mode&&argument=="--capture-chaos-profile" {g.screen=.Investigate;g.player_x=32;g.player_y=31;g.camera_x=32;g.camera_y=32;g.camera_initialized=true;g.camera_orbit=f32(math.PI/4);g.camera_orbit_initialized=true;g.camera_zoom=.22;g.environment_blend=1;g.cutaway_transition=0;g.wall_view=.Walls_Up;for &amount in g.wall_cutaways do amount=0}
	if capture_mode&&argument=="--capture-crime-scene" {g.screen=.Investigate;g.player_x=20.5;g.player_y=24.5;g.player_angle=math.PI/2;g.camera_x=22;g.camera_y=25.8;g.camera_initialized=true;g.camera_orbit=math.PI*.18;g.camera_orbit_initialized=true;g.camera_zoom=.62;g.environment_blend=1;g.wall_view=.Walls_Down;for &amount in g.wall_cutaways do amount=1;editor_state.view=.Isometric}
	if capture_mode&&argument=="--capture-shadow-exterior" {g.screen=.Exterior;g.city_x=city_world(34);g.city_y=city_world(66);g.city_camera_x=g.city_x;g.city_camera_y=g.city_y;g.city_camera_initialized=true;g.city_angle=0;g.environment_blend=1}
	if capture_mode&&argument=="--capture-wall-cutaway-transition" {g.screen=.Investigate;g.player_x=20;g.player_y=18;g.camera_x=20;g.camera_y=18;g.camera_initialized=true;g.environment_blend=1;g.cutaway_transition=.5;for &amount in g.wall_cutaways do amount=.5;editor_state.view=.Isometric}
	if capture_mode&&argument=="--capture-wall-cutaway-early" {g.screen=.Investigate;g.player_x=20;g.player_y=18;g.camera_x=20;g.camera_y=18;g.camera_initialized=true;g.environment_blend=1;g.cutaway_transition=.1;for &amount in g.wall_cutaways do amount=.1;editor_state.view=.Isometric}
	if capture_mode&&argument=="--capture-wall-cutaway-automatic" {g.screen=.Investigate;g.player_x=16;g.player_y=14;g.camera_x=16;g.camera_y=14;g.camera_initialized=true;g.camera_orbit=f32(math.PI/4);g.camera_orbit_initialized=true;g.camera_zoom=1;g.environment_blend=0;for &wall,i in house_walls do if i<HOUSE_WALL_SECTION_CAPACITY do g.wall_cutaways[i]=house_wall_cutaway_target(&g,&wall);editor_state.view=.Isometric}
	if capture_mode&&argument=="--capture-wall-cutaway-full" {g.screen=.Investigate;g.player_x=16;g.player_y=14;g.camera_x=16;g.camera_y=14;g.camera_initialized=true;g.camera_orbit=f32(math.PI/4);g.camera_orbit_initialized=true;g.camera_zoom=1;g.environment_blend=0;g.wall_view=.Walls_Down;for &amount in g.wall_cutaways do amount=1;editor_state.view=.Isometric}
	if capture_mode&&argument=="--capture-door-double" {g.screen=.Investigate;g.player_x=24;g.player_y=14;g.camera_x=24;g.camera_y=11.5;g.camera_initialized=true;g.camera_orbit=f32(math.PI)/2;g.camera_orbit_initialized=true;g.camera_zoom=.48;g.environment_blend=0;g.wall_view=.Walls_Down;for &amount in g.wall_cutaways do amount=1;editor_state.view=.Isometric}
	if capture_mode&&argument=="--capture-paintings" {g.screen=.Investigate;g.player_x=15;g.player_y=14;g.player_angle= -f32(math.PI)/2;g.first_person_camera=true;g.environment_blend=0;g.wall_view=.Walls_Up;for &amount in g.wall_cutaways do amount=0}
	if capture_mode&&argument=="--capture-door-sliding" {g.screen=.Investigate;g.player_x=17;g.player_y=23;g.camera_x=19;g.camera_y=23;g.camera_initialized=true;g.camera_orbit=f32(math.PI);g.camera_orbit_initialized=true;g.camera_zoom=.48;g.environment_blend=0;g.wall_view=.Walls_Down;for &amount in g.wall_cutaways do amount=1;editor_state.view=.Isometric}
	if capture_mode&&(argument=="--capture-wall-art-full"||argument=="--capture-wall-art-fade"||argument=="--capture-wall-art-hidden") {g.screen=.Investigate;g.player_x=19.2;g.player_y=14;g.camera_x=19.2;g.camera_y=.2;g.camera_initialized=true;g.camera_orbit=f32(math.PI)/4;g.camera_orbit_initialized=true;g.camera_zoom=.42;g.environment_blend=0;amount:=argument=="--capture-wall-art-full"?f32(0):argument=="--capture-wall-art-fade"?f32(.64):f32(1);for &wall_amount in g.wall_cutaways do wall_amount=amount;editor_state.view=.Isometric}
	if capture_mode&&argument=="--capture-window-architecture" {g.screen=.Investigate;g.player_x=12;g.player_y=11;g.camera_x=12;g.camera_y=8.15;g.camera_initialized=true;g.camera_orbit=1.35;g.camera_orbit_initialized=true;g.camera_zoom=.62;g.environment_blend=1;g.cutaway_transition=0;for &amount in g.wall_cutaways do amount=0;editor_state.view=.Isometric}
	if capture_mode&&argument=="--capture-window-double-hung" {g.screen=.Investigate;g.player_x=31;g.player_y=11;g.camera_x=31;g.camera_y=8.15;g.camera_initialized=true;g.camera_orbit=1.35;g.camera_orbit_initialized=true;g.camera_zoom=.62;g.environment_blend=1;g.cutaway_transition=0;for &amount in g.wall_cutaways do amount=0;editor_state.view=.Isometric}
	if capture_mode&&argument=="--capture-window-exterior" {g.screen=.Investigate;g.player_x=12;g.player_y=7;g.camera_x=12;g.camera_y=11.85;g.camera_initialized=true;g.camera_orbit=1.35+f32(math.PI);g.camera_orbit_initialized=true;g.camera_zoom=.62;g.environment_blend=1;g.cutaway_transition=0;for &amount in g.wall_cutaways do amount=0;editor_state.view=.Isometric}
	if capture_mode&&argument=="--capture-window-test-gallery" {g.screen=.Investigate;g.player_x=20;g.player_y=-11;g.player_angle=f32(math.PI)/2;g.first_person_camera=true;g.environment_blend=1;g.cutaway_transition=0;g.wall_view=.Walls_Up;for &amount in g.wall_cutaways do amount=0;editor_state.view=.Isometric}
	if capture_mode&&(argument=="--capture-window-test-inside-3"||argument=="--capture-window-test-inside-4") {g.screen=.Investigate;g.player_x=argument=="--capture-window-test-inside-3"?f32(18.02):f32(25.4);g.player_y=13;g.player_angle= -f32(math.PI)/2;g.first_person_camera=true;g.environment_blend=0;g.cutaway_transition=0;g.wall_view=.Walls_Up;for &amount in g.wall_cutaways do amount=0;editor_state.view=.Isometric}
	if capture_mode&&(argument=="--capture-window-shutter"||argument=="--capture-window-shutter-motion"||argument=="--capture-window-shutter-open") {g.screen=.Investigate;g.player_x=21.20;g.player_y=26.8;g.player_angle=f32(math.PI);g.first_person_camera=true;g.environment_blend=1;g.cutaway_transition=1;for &amount in g.wall_cutaways do amount=1;g.shutter_position=argument=="--capture-window-shutter"?f32(0):argument=="--capture-window-shutter-open"?f32(1):f32(.55);g.shutter_open=g.shutter_position>.5;g.shutter_target=g.shutter_position}
	if capture_mode&&argument=="--capture-dialogue" {g.dialogue_response="Edgar never summoned me. I did not enter his study during dinner.";unlock_topic(&g,"appointment_denial")}
	if capture_mode&&argument=="--capture-dialogue-interaction-statuette" {g.study_statuette_held=true;_=dialogue_start_source_scene(&g,"statuette");for _ in 0..<20 do _=update_cinematic_dialogue(&g);g.dialogue_interaction.pitch=2.05;g.dialogue_interaction.phase=.Revealing;g.dialogue_interaction.phase_time=.8;dialogue_interaction_commit_discovery(&g);g.active_device=.Gamepad;g.gamepad_type=.PS5}
	if capture_mode&&argument=="--capture-dialogue-interaction-desk" {g.desk_key_found=true;_=dialogue_start_source_scene(&g,"study_desk");for _ in 0..<20 do _=update_cinematic_dialogue(&g);g.dialogue_interaction.key_inserted=true;g.dialogue_interaction.feedback="The brass key seats in the lock. Turn it to release the drawer.";g.dialogue_interaction.ledger="TOOL APPLIED — Edgar's brass key fits the desk.";g.active_device=.Gamepad}
	if capture_mode&&argument=="--capture-cinematic-hidden" {_=dialogue_start_source_scene(&g,"study_desk");_=update_cinematic_dialogue(&g);g.story_presentation.ui_opacity=0;g.story_presentation.ui_target=0}
	if capture_mode&&argument=="--capture-cinematic-line" {_=dialogue_start_source_scene(&g,"miriam");_=update_cinematic_dialogue(&g);g.active_device=.Keyboard_Mouse}
	if capture_mode&&argument=="--capture-cinematic-many-responses" {_=dialogue_start_source_scene(&g,"miriam");dialogue_transcript_append(&g,"miriam","Dinner began at eight. Daniel was opposite me throughout.","line");g.dialogue_choice_page=1;g.active_device=.Keyboard_Mouse;dialogue_focus_default(&g)}
	if capture_mode&&argument=="--capture-cinematic-inspection" {g.desk_key_found=true;_=dialogue_start_source_scene(&g,"study_desk");for _ in 0..<20 do _=update_cinematic_dialogue(&g);g.active_device=.Gamepad}
	if capture_mode&&(argument=="--capture-dialogue-object"||argument=="--capture-dialogue-object-acquired"||argument=="--capture-dialogue-object-locked"||argument=="--capture-dialogue-object-description") {g.screen=.Dialogue;g.dialogue_entity=world_entity_index(argument=="--capture-dialogue-object-description"?"statuette":"ledger");g.player_x=4.5;g.player_y=8.8;g.camera_x=4.5;g.camera_y=8.8;if argument=="--capture-dialogue-object-acquired" do _=mystery_game_mark_clue(&g,0);if argument=="--capture-dialogue-object-locked" do mystery_game_mark_clue_attempted(&g,0)}
	if capture_mode&&(argument=="--capture-dialogue-evidence"||argument=="--capture-dialogue-evidence-presented"||argument=="--capture-dialogue-evidence-presented-history"||argument=="--capture-dialogue-evidence-only") {g.screen=.Dialogue;g.active_device=.Keyboard_Mouse;g.dialogue_entity=0;g.player_x=2.5;g.player_y=2.5;g.player_angle=0;trigger_character_interact(&g,"miriam");memo_index:=mystery_clue_index(payload,"clue_appointment_stub");if memo_index>=0 do _=mystery_game_mark_clue(&g,memo_index);g.dialogue_response="Edgar's memo stub fixes the time of the summons Miriam denied receiving.";if argument=="--capture-dialogue-evidence-presented"||argument=="--capture-dialogue-evidence-presented-history" {for i in 0..<mystery_dialogue_approach_count(payload) {node:=mystery_dialogue_approach_at(payload,i);if node.character_id=="miriam"&&node.clue_id==""&&!mystery_game_dialogue_completed(&g,i) {complete_dialogue_approach(&g,i);break}};evidence_index:=mystery_clue_index(payload,"clue_burned_fragment");if evidence_index>=0 {_=mystery_game_mark_evidence_presented(&g,evidence_index);g.dialogue_node=3;g.dialogue_response=dialogue_evidence_feedback(&g,evidence_index)};g.dialogue_text_started=g.animation_time;g.dialogue_ledger_scroll=argument=="--capture-dialogue-evidence-presented-history"?1:0};if argument=="--capture-dialogue-evidence-only" {for i in 0..<mystery_dialogue_approach_count(payload) {node:=mystery_dialogue_approach_at(payload,i);if node.character_id=="miriam" do _=mystery_game_mark_dialogue(&g,i,false)}}}
	if capture_mode&&argument=="--capture-check-roll" {g.screen=.Dialogue;g.dialogue_entity=world_entity_index("ledger");g.player_x=4.5;g.player_y=8.8;g.camera_x=4.5;g.camera_y=8.8;g.pending_clue=0;g.check_from_dialogue=true;g.check_preview=check_target(payload.clues[0].difficulty);g.check_result=Check_Result{target=g.check_preview,die_a=5,die_b=4,modifier=1,total=10,success=true};g.check_done=true;g.check_roll_started=-1.45}
	if capture_mode&&(argument=="--capture-check-dice-start"||argument=="--capture-check-zoom"||argument=="--capture-check-success") {g.screen=.Dialogue;g.dialogue_entity=world_entity_index("ledger");g.player_x=4.5;g.player_y=8.8;g.camera_x=4.5;g.camera_y=8.8;g.pending_clue=0;g.check_from_dialogue=true;g.check_preview=check_target(payload.clues[0].difficulty);g.check_result=argument=="--capture-check-zoom"?Check_Result{target=g.check_preview,die_a=2,die_b=3,modifier=1,total=6,success=false}:Check_Result{target=g.check_preview,die_a=5,die_b=4,modifier=1,total=10,success=true};g.check_done=true;g.check_roll_started=argument=="--capture-check-dice-start"?f32(-.35):f32(-1.8)}
	if capture_mode&&argument=="--capture-check-overtime" {g.screen=.Dialogue;g.dialogue_entity=world_entity_index("ledger");g.player_x=4.5;g.player_y=8.8;g.camera_x=4.5;g.camera_y=8.8;g.pending_clue=0;g.check_from_dialogue=true;g.check_preview=check_target(payload.clues[0].difficulty);g.ap=0;g.overtime_clue_plus_one=1}
	if capture_mode&&(argument=="--capture-dialogue-elsie"||argument=="--capture-dialogue-history"||argument=="--capture-dialogue-history-oldest"||argument=="--capture-dialogue-long-response"||argument=="--capture-dialogue-many-responses"||argument=="--capture-approach-check"||argument=="--capture-approach-check-success"||argument=="--capture-approach-check-failure"||argument=="--capture-approach-check-return-success"||argument=="--capture-approach-check-return-failure"||argument=="--capture-check-tooltip"||argument=="--capture-dialogue-showcase"||argument=="--capture-dialogue-keyboard-shortcuts"||argument=="--capture-dialogue-mouse-hover"||argument=="--capture-dialogue-gamepad-focus"||argument=="--capture-dialogue-playstation-focus"||argument=="--capture-disposition-tooltip"||argument=="--capture-disposition-tooltip-neutral") {g.screen=.Dialogue;g.dialogue_entity=2;g.player_x=19.5;g.player_y=2.5;trigger_character_interact(&g,"elsie");_=learn_claim(&g,"claim_elsie_study");unlock_topic(&g,"kitchen_routine")}
	if capture_mode&&argument=="--capture-dialogue-many-responses" {for i in 0..<mystery_dialogue_approach_count(payload) {node:=mystery_dialogue_approach_at(payload,i);if node.character_id=="elsie" do for j in 0..<node.require_count {id:=node.requires[j];if mystery_claim_index(payload,id)>=0 do _=learn_claim(&g,id);else do unlock_topic(&g,id)}};g.dialogue_choice_page=1}
	if capture_mode&&(argument=="--capture-approach-check"||argument=="--capture-approach-check-success"||argument=="--capture-approach-check-failure"||argument=="--capture-approach-check-return-success"||argument=="--capture-approach-check-return-failure") {for i in 0..<mystery_dialogue_approach_count(payload) {node:=mystery_dialogue_approach_at(payload,i);if node.character_id=="elsie"&&node.clue_id!=""&&dialogue_approach_available(&g,i) {begin_dialogue_approach_check(&g,i);break}};if argument=="--capture-approach-check-success" {g.ap=11;g.check_result=Check_Result{target=g.check_preview,die_a=5,die_b=4,modifier=1,total=10,success=true};g.check_disposition_delta=1;g.check_done=true;g.check_roll_started=-1.8};if argument=="--capture-approach-check-failure" {g.ap=11;g.check_result=Check_Result{target=g.check_preview,die_a=2,die_b=3,modifier=1,total=6,success=false};g.check_disposition_delta=-1;g.check_done=true;g.check_roll_started=-1.8};if argument=="--capture-approach-check-return-success"||argument=="--capture-approach-check-return-failure" {g.active_device=.Keyboard_Mouse;node_index:=g.pending_dialogue_approach-1;clue_index:=g.pending_clue;success:=argument=="--capture-approach-check-return-success";if clue_index>=0 do g.check_disposition_delta=apply_check_disposition(&g,clue_index,success);if success {if clue_index>=0 do _=mystery_game_mark_clue(&g,clue_index);complete_dialogue_approach(&g,node_index)} else {if clue_index>=0 do mystery_game_set_clue_attempt_score(&g,clue_index,clue_reopen_score(&g,clue_index));fail_dialogue_approach(&g,node_index)};g.pending_dialogue_approach=0;g.check_from_dialogue=false;g.check_done=false;g.dialogue_ledger_scroll=0}}
	if capture_mode&&(argument=="--capture-dialogue-history"||argument=="--capture-dialogue-history-oldest") {g.active_device=.Keyboard_Mouse;completed:=0;for i in 0..<mystery_dialogue_approach_count(payload) {node:=mystery_dialogue_approach_at(payload,i);if node.character_id=="elsie"&&node.clue_id==""&&completed<2 {complete_dialogue_approach(&g,i);completed+=1}};for i in 0..<mystery_dialogue_approach_count(payload) {node:=mystery_dialogue_approach_at(payload,i);if node.node_id=="approach_elsie_theft" {_=mystery_game_mark_dialogue(&g,i,false);clue_index:=mystery_clue_index(payload,node.clue_id);if clue_index>=0 do _=mystery_game_mark_clue(&g,clue_index);g.dialogue_response=node.response}};if argument=="--capture-dialogue-history-oldest" do g.dialogue_ledger_scroll=1}
	if capture_mode&&argument=="--capture-dialogue-long-response" {unlock_topic(&g,"late_case_changes");for i in 0..<mystery_dialogue_approach_count(payload) {node:=mystery_dialogue_approach_at(payload,i);if node.node_id=="approach_elsie_return" do complete_dialogue_approach(&g,i)}}
	if capture_mode&&strings.contains(argument,"recreate") {configure_complete_questions(&g);g.ap=4;g.screen=.Recreate;if argument=="--capture-cover-up-recreate" do g.active_demonstration=demonstration_for_question(&g,question_index_by_id(&g,"q_garden_murder"));if argument=="--capture-alibi-recreate" do g.active_demonstration=demonstration_for_question(&g,question_index_by_id(&g,"q_daniel_lie"));if argument=="--capture-proof-recreate"||argument=="--capture-shutter-recreate"||argument=="--capture-recreate-motion" do g.active_demonstration=demonstration_for_question(&g,question_index_by_id(&g,"q_miriam_study_meeting"))}
	if capture_mode&&(argument=="--capture-interaction-inspect"||argument=="--capture-interaction-connect"||argument=="--capture-interaction-reconstruct") {mystery_game_mark_all_clues(&g);for claim in payload.claims do _=learn_claim(&g,claim.id);refresh_questions(&g);question_id:=argument=="--capture-interaction-inspect"?"q_garden_murder":argument=="--capture-interaction-connect"?"q_fragment_source":"q_when_death";g.question_selected=question_index_by_id(&g,question_id);demo_index:=demonstration_for_question(&g,g.question_selected);if demo_index>=0 {demo:=&payload.demonstrations[demo_index];for slot in 0..<demo.slot_count do mystery_question_set_slot(&g,g.question_selected,slot,mystery_demonstration_route_piece(demo,0,slot));begin_question_demonstration(&g)};g.scene_transition_active=false;g.active_device=.Gamepad}
	if capture_mode&&(argument=="--capture-recreate"||argument=="--capture-cover-up-recreate"||argument=="--capture-alibi-recreate") do g.recreate_started=-20
	if capture_mode&&argument=="--capture-recreate-motion" {g.screen=.Recreate;g.recreate_started=-3}
	if capture_mode&&(argument=="--capture-final-demo"||argument=="--capture-final-demo-paper") {configure_complete_questions(&g);mystery_game_mark_all_clues(&g);g.screen=.Reveal;g.reveal_act=4;g.finale_demo_step=argument=="--capture-final-demo-paper"?1:2}
	if capture_mode&&argument=="--capture-board-incomplete" {mystery_game_mark_all_clues(&g);for claim in payload.claims do _=learn_claim(&g,claim.id);refresh_questions(&g);g.screen=.Challenge;g.question_selected=question_index_by_id(&g,"q_garden_murder");demo_index:=demonstration_for_question(&g,g.question_selected);mystery_question_set_slot(&g,g.question_selected,0,mystery_demonstration_route_piece(&payload.demonstrations[demo_index],0,0));mystery_question_set_state(&g,g.question_selected,.Supported);g.question_feedback="One relevant piece is placed. Choose evidence for the remaining part of the test."}
	if capture_mode&&argument=="--capture-board" {mystery_game_mark_all_clues(&g);for claim in payload.claims do _=learn_claim(&g,claim.id);refresh_questions(&g);g.screen=.Board;g.question_selected=question_index_by_id(&g,"q_garden_murder");g.question_feedback="Choose a question, then combine evidence to test its claim."}
	if capture_mode&&argument=="--capture-board-complete" {configure_complete_questions(&g);event_chain_from_evidence(&g);g.screen=.Board}
	if capture_mode&&argument=="--capture-event-chain-break" {configure_complete_questions(&g);g.workbench_event_count=2;g.workbench_events[0]={507,"miriam","move_body","body","garden",-1};g.workbench_events[1]={504,"miriam","strike","statuette","study",-1};run_workbench(&g)}
	if capture_mode&&argument=="--capture-reveal-prep" {configure_complete_questions(&g);g.screen=.Reveal_Prep}
	ui.gui_init(&g.gui);defer ui.gui_destroy(&g.gui);g.gui.focused=button_id({440,500,320,54});g.input.mouse_pos={600,360}
	if capture_mode&&argument=="--capture-graph-choice" do g.input.mouse_pos={1155,219}
	if capture_mode&&argument=="--capture-graph-routing-crossing-hover" {g.input.mouse_pos={450,151};graph_state.edge_hover=graph_edge_hit(g.input.mouse_pos)}
	if capture_mode&&argument=="--capture-graph-routing-parallel-hover" {from_port:=graph_port_rect(graph_document.nodes[15],1);to_port:=graph_input_rect(graph_document.nodes[17]);g.input.mouse_pos={(from_port.x+from_port.w*.5+to_port.x+to_port.w*.5)*.5,(from_port.y+from_port.h*.5+to_port.y+to_port.h*.5)*.5};graph_state.edge_hover=graph_edge_hit(g.input.mouse_pos)}
	if capture_mode&&argument=="--capture-graph-routing-zoomed-hover" {from_port:=graph_port_rect(graph_document.nodes[11],0);to_port:=graph_input_rect(graph_document.nodes[12]);g.input.mouse_pos={(from_port.x+from_port.w*.5+to_port.x+to_port.w*.5)*.5,(from_port.y+from_port.h*.5+to_port.y+to_port.h*.5)*.5};graph_state.edge_hover=graph_edge_hit(g.input.mouse_pos)}
	if capture_mode&&argument=="--capture-graph-routing-direct-hover" {from_port:=graph_port_rect(graph_document.nodes[0],0);to_port:=graph_input_rect(graph_document.nodes[1]);g.input.mouse_pos={(from_port.x+from_port.w*.5+to_port.x+to_port.w*.5)*.5,(from_port.y+from_port.h*.5+to_port.y+to_port.h*.5)*.5};graph_state.edge_hover=graph_edge_hit(g.input.mouse_pos)}
	if capture_mode&&argument=="--capture-graph-routing-obstacle-hover" {from_port:=graph_port_rect(graph_document.nodes[2],0);to_port:=graph_input_rect(graph_document.nodes[4]);a,d:=Vec2{from_port.x+from_port.w*.5,from_port.y+from_port.h*.5},Vec2{to_port.x+to_port.w*.5,to_port.y+to_port.h*.5};if lane,ok:=graph_edge_local_lane("wire_routing",a,d,2,4);ok {g.input.mouse_pos={(a.x+d.x)*.5,lane};graph_state.edge_hover=graph_edge_hit(g.input.mouse_pos)}}
	if capture_mode&&argument=="--capture-graph-routing-back-hover" {g.input.mouse_pos={580,360};graph_state.edge_hover=graph_edge_hit(g.input.mouse_pos)}
	if capture_mode&&g.screen==.Dialogue do dialogue_focus_default(&g)
	if capture_mode&&argument=="--capture-build-lighting-control" do g.input.mouse_pos={939,263}
	if capture_mode&&argument=="--capture-build-story-up" do g.input.mouse_pos={950,31}
	if capture_mode&&argument=="--capture-build-tool-hover" {box:=build_tool_grid_rect(5);g.input.mouse_pos={box.x+box.w*.5,box.y+box.h*.5}}
	if capture_mode&&(argument=="--capture-check-tooltip"||argument=="--capture-dialogue-showcase") {
		g.active_device=.Keyboard_Mouse
		for i in 0..<mystery_dialogue_approach_count(payload) {
			node:=mystery_dialogue_approach_at(payload,i)
			if node.node_id!="approach_elsie_theft" do continue
			for j in 0..<node.require_count {
				id:=node.requires[j]
				if mystery_claim_index(payload,id)>=0 do _=learn_claim(&g,id)
				else do _=mystery_string_set_add(&g.mystery_state.acquired_evidence,id)
			}
		}
		g.screen=.Dialogue
		g.dialogue_entity=2
		if argument=="--capture-dialogue-showcase" {
			g.conversation_transcript_count=0
			conversation_transcript_append(&g,"narrator","Elsie folds the polishing cloth into a smaller and smaller square.","action","elsie")
			conversation_transcript_append(&g,"detective_thought","She answered too quickly. The study matters to her.","thought","elsie")
			conversation_transcript_append(&g,"elsie","I never entered the study, Detective. Not once.","dialogue","elsie")
		}
		clue:=clue_for_source(&g,"elsie")
		count:=dialogue_available_approach_count(&g,"elsie")
		for absolute in 0..<count {
			index:=visible_dialogue_approach(&g,"elsie",absolute)
			if index<0||dialogue_check_clue_index(&g,index)<0 do continue
			g.dialogue_choice_page=absolute
			local:=0
			choice:=dialogue_response_rect(&g,"elsie",clue,local)
			g.gui.focused=button_id(choice)
			g.input.mouse_pos={choice.x+choice.w*.5,choice.y+choice.h*.5}
			break
		}
	}
	if capture_mode&&argument=="--capture-dialogue-complex-sequence" {
		g.active_device=.Keyboard_Mouse
		g.conversation_transcript_count=0
		_=dialogue_start_source_scene(&g,"miriam")
		g.story_presentation.transcript_count=0
		dialogue_transcript_append(&g,"daniel","Take your hand off me.","dialogue")
		dialogue_transcript_append(&g,"narrator","Elsie releases his wrist and steps between Daniel and the desk.","action")
		_=update_cinematic_dialogue(&g)
		dialogue_focus_default(&g)
		g.input.mouse_pos={600,680}
	}
	if capture_mode&&argument=="--capture-dialogue-keyboard-shortcuts" {g.active_device=.Keyboard_Mouse;dialogue_focus_default(&g);g.input.mouse_pos={600,680}}
	if capture_mode&&argument=="--capture-dialogue-mouse-hover" {g.active_device=.Keyboard_Mouse;y:=dialogue_choices_start_y(&g,"elsie");first:=Rect{};for slot in 0..<3 {index:=visible_dialogue_approach(&g,"elsie",slot);if index<0 do continue;choice:=dialogue_approach_rect(&g,index,y);if slot==0 do first=choice;if dialogue_check_clue_index(&g,index)>=0 do g.gui.focused=button_id(choice);y+=choice.h+4};g.input.mouse_pos={first.x+200,first.y+20}}
	if capture_mode&&(argument=="--capture-dialogue-gamepad-focus"||argument=="--capture-dialogue-playstation-focus") {g.active_device=.Gamepad;if argument=="--capture-dialogue-playstation-focus" do g.gamepad_type=.PS5;y:=dialogue_choices_start_y(&g,"elsie");first:=Rect{};for slot in 0..<3 {index:=visible_dialogue_approach(&g,"elsie",slot);if index<0 do continue;choice:=dialogue_approach_rect(&g,index,y);if slot==0 do first=choice;if dialogue_check_clue_index(&g,index)>=0 do g.gui.focused=button_id(choice);y+=choice.h+4};g.input.mouse_pos={first.x+20,first.y+20}}
	if capture_mode&&(argument=="--capture-disposition-tooltip"||argument=="--capture-disposition-tooltip-neutral") {g.active_device=.Keyboard_Mouse;if argument=="--capture-disposition-tooltip-neutral" {index:=character_index(&g,"elsie");if index>=0 do mystery_game_set_disposition(&g,"elsie",0)};box:=disposition_rect();g.input.mouse_pos={box.x+box.w*.5,box.y+box.h*.5}}
	if capture_mode&&argument=="--capture-dialogue-evidence-only" {clue:=clue_for_source(&g,"miriam");g.gui.focused=button_id(dialogue_evidence_choice_rect(&g,"miriam",clue))}
	if capture_mode&&(argument=="--capture-approach-check"||argument=="--capture-approach-check-success"||argument=="--capture-approach-check-failure") do dialogue_focus_default(&g)
	if capture_mode&&(argument=="--capture-dialogue-history"||argument=="--capture-dialogue-history-oldest") do dialogue_focus_default(&g)
	if capture_mode&&argument=="--capture-dialogue-history-oldest" {g.dialogue_ledger_scroll=2;g.input.mouse_pos={1150,330}}
	if capture_mode&&argument=="--capture-agent-room" {
		if len(os.args)<3 {fmt.eprintln("agent room capture requires a room ID");return}
		room_index:=level_room_index(&level_document,os.args[2]);if room_index<0 {fmt.eprintln("unknown room: ",os.args[2]);return};room:=&level_document.rooms[room_index]
		level_document.active_story=room.story;level_project_runtime(&level_document);minimum:=Vec2{1e30,1e30};maximum:=Vec2{-1e30,-1e30};for point in room.points {minimum.x=min(minimum.x,point.x);minimum.y=min(minimum.y,point.y);maximum.x=max(maximum.x,point.x);maximum.y=max(maximum.y,point.y)};center:=Vec2{(minimum.x+maximum.x)*.5,(minimum.y+maximum.y)*.5};g.screen=.Investigate;g.editor_mode=.Build;g.build_tool=.Select;g.top_down_camera=true;g.player_x=center.x;g.player_y=center.y;g.camera_x=center.x;g.camera_y=center.y;g.camera_zoom=editor_frame_zoom(minimum,maximum,len(room.points));g.camera_initialized=true;g.camera_orbit_initialized=true;g.cutaway_transition=1;editor_state.view=.Top_Down;editor_state.selection[0]={.Room,room.id,-1};editor_state.selection_count=1
	}
	if capture_mode {
		for value in os.args do if value=="--hide-roofs" do g.capture_hide_roofs=true
		camera_position_text:=argument_value("--camera-position=");camera_look_at_text:=argument_value("--camera-look-at=")
		if camera_position_text!=""||camera_look_at_text!="" {
			if camera_position_text==""||camera_look_at_text=="" {fmt.eprintln("custom capture camera requires both --camera-position=x,y,z and --camera-look-at=x,y,z");return}
			camera_position,position_ok:=parse_vec3_argument(camera_position_text);camera_look_at,look_at_ok:=parse_vec3_argument(camera_look_at_text)
			if !position_ok||!look_at_ok {fmt.eprintln("capture camera values must be comma-separated x,y,z numbers");return}
			dx,dy,dz:=camera_look_at.x-camera_position.x,camera_look_at.y-camera_position.y,camera_look_at.z-camera_position.z
			if dx*dx+dy*dy+dz*dz<.0001 {fmt.eprintln("capture camera position and look-at must be different");return}
			g.camera_pose_override=true;g.camera_eye_override=camera_position;g.camera_target_override=camera_look_at;g.screen=.Investigate
		}
		walls_text:=argument_value("--walls=");cutaway_text:=argument_value("--cutaway=")
		if walls_text!=""&&cutaway_text!="" {fmt.eprintln("use either --walls=auto|up|down or --cutaway=0..1, not both");return}
		if walls_text!="" {
			wall_view,wall_view_ok:=capture_wall_view_from_text(walls_text);if !wall_view_ok {fmt.eprintln("capture wall mode must be auto, up, down, or cutaway");return};g.wall_view=wall_view
			if wall_view==.Walls_Up {g.cutaway_transition=0;for &amount in g.wall_cutaways do amount=0}
			else if wall_view==.Walls_Down {g.cutaway_transition=1;for &amount in g.wall_cutaways do amount=1}
			else {maximum_cutaway:f32;for &wall,i in house_walls {if i>=len(g.wall_cutaways) do break;amount:=house_wall_cutaway_target(&g,&wall);g.wall_cutaways[i]=amount;maximum_cutaway=max(maximum_cutaway,amount)};g.cutaway_transition=maximum_cutaway}
		}
		if cutaway_text!="" {
			amount,amount_ok:=strconv.parse_f32(strings.trim_space(cutaway_text));if !amount_ok||amount<0||amount>1 {fmt.eprintln("capture cutaway amount must be between 0 and 1");return}
			g.wall_view=.Automatic;g.cutaway_transition=amount;g.capture_cutaway_override=true;g.capture_cutaway_amount=amount;for &wall_amount in g.wall_cutaways do wall_amount=amount
		}
	}
	capture_name:=capture_mode?argument[len("--capture-"):]:"";capture_path:=argument=="--capture-catalog-thumbnail"?fmt.tprintf("/private/tmp/chicago-catalog-%s.png",os.args[2]):fmt.tprintf("/private/tmp/chicago-vulkan-%s.png",capture_name);custom_capture_path:=argument_value("--capture-output=");if custom_capture_path!="" do capture_path=custom_capture_path;capture_mouse:=g.input.mouse_pos;capture_device:=g.active_device;frames:=0;profile_draw_seconds,profile_frame_seconds,profile_shadow_ms,profile_world_ms,profile_ui_ms,profile_tail_ms,profile_lights_ms,profile_batches_ms,profile_unbatched_ms,profile_draw_setup_ms,profile_draw_refresh_ms,profile_draw_world_build_ms,profile_draw_weather_ms,profile_draw_overlay_ms,profile_house_structure_ms,profile_house_surfaces_ms,profile_house_walls_ms,profile_house_openings_ms,profile_house_objects_ms,profile_house_characters_ms:f64;profile_samples:=0
	// Rendering produces elapsed wall time; the simulation consumes it only in
	// deterministic 60 Hz chunks. Seed one tick so UI and gameplay state are
	// initialized before the first presented frame.
	previous_tick:=time.tick_now();accumulator:=FIXED_TIMESTEP
	begin_frame(&g)
	for g.running {
		now:=time.tick_now();frame_time:=min(time.duration_seconds(time.tick_diff(previous_tick,now)),MAX_FRAME_TIME);previous_tick=now
		if !capture_mode do accumulator+=frame_time
		poll(&g,window);if capture_mode {g.input.mouse_pos=capture_mouse;g.active_device=capture_device};if g.active_device==.Gamepad do _=sdl.HideCursor();else do _=sdl.ShowCursor();if g.window_resized {backend.ctx.needs_swapchain_recreate=true;g.window_resized=false}
		fixed_steps:=0
		for !capture_mode&&accumulator>=FIXED_TIMESTEP&&fixed_steps<MAX_FIXED_STEPS_PER_FRAME {
			if g.controller_disconnected||g.input_resume_blocked {
				// Freeze gameplay until the player chooses another input device or reconnects.
			} else if g.scene_transition_active {
				scene_transition_update(&g,FIXED_TIMESTEP)
			} else {
				previous_screen:=g.screen
				if g.screen==.Loading do map_loading_update(&g,FIXED_TIMESTEP);else do update(&g)
				if g.screen!=previous_screen do scene_transition_begin(&g,previous_screen,g.screen)
				scene_transition_update(&g,FIXED_TIMESTEP)
			}
			update_vehicle_haptics(&g)
			if g.gui.clipboard_set_pending {clipboard,err:=strings.clone_to_cstring(string(g.gui.clipboard_set_text[:g.gui.clipboard_set_len]),context.temp_allocator);if err==nil do _=sdl.SetClipboardText(clipboard);g.gui.clipboard_set_pending=false}
			accumulator-=FIXED_TIMESTEP;fixed_steps+=1
			// Edge-triggered input is consumed by one simulation tick. Held keys,
			// pointer position, and analog axes remain live for catch-up ticks.
			begin_frame(&g)
		}
		// Bound recovery work after a stall to avoid the spiral of death.
		if fixed_steps==MAX_FIXED_STEPS_PER_FRAME do accumulator=min(accumulator,FIXED_TIMESTEP)
		capture_request_frame:=(argument=="--capture-chaos-profile"||argument=="--capture-ending")?120:3;draw_started:=time.tick_now();draw_vulkan(&backend,&g);draw_finished:=time.tick_now();if capture_mode&&frames==capture_request_frame do vulkan_backend_request_capture(&backend,capture_path);frame_started:=time.tick_now();if !vulkan_backend_frame(&backend,&g) do g.running=false;frame_finished:=time.tick_now();if argument=="--capture-chaos-profile"&&frames>=30 {if frames==30 do fmt.println("CHAOS PROFILE READY");profile_draw_seconds+=time.duration_seconds(time.tick_diff(draw_started,draw_finished));profile_frame_seconds+=time.duration_seconds(time.tick_diff(frame_started,frame_finished));profile_shadow_ms+=backend.profile_shadow_ms;profile_world_ms+=backend.profile_world_ms;profile_ui_ms+=backend.profile_ui_ms;profile_tail_ms+=backend.profile_tail_ms;profile_lights_ms+=backend.world.profile_lights_ms;profile_batches_ms+=backend.world.profile_batches_ms;profile_unbatched_ms+=backend.world.profile_unbatched_ms;profile_draw_setup_ms+=backend.profile_draw_setup_ms;profile_draw_refresh_ms+=backend.profile_draw_refresh_ms;profile_draw_world_build_ms+=backend.profile_draw_world_build_ms;profile_draw_weather_ms+=backend.profile_draw_weather_ms;profile_draw_overlay_ms+=backend.profile_draw_overlay_ms;profile_house_structure_ms+=backend.world.profile_house_structure_ms;profile_house_surfaces_ms+=backend.world.profile_house_surfaces_ms;profile_house_walls_ms+=backend.world.profile_house_walls_ms;profile_house_openings_ms+=backend.world.profile_house_openings_ms;profile_house_objects_ms+=backend.world.profile_house_objects_ms;profile_house_characters_ms+=backend.world.profile_house_characters_ms;profile_samples+=1};if backend.capture_written {if argument=="--capture-chaos-profile"&&profile_samples>0 {fmt.println(fmt.tprintf("CHAOS PROFILE samples=%d draw_ms=%.3f submit_present_ms=%.3f total_ms=%.3f",profile_samples,profile_draw_seconds/f64(profile_samples)*1000,profile_frame_seconds/f64(profile_samples)*1000,(profile_draw_seconds+profile_frame_seconds)/f64(profile_samples)*1000));fmt.println(fmt.tprintf("CHAOS DRAW setup_ms=%.3f refresh_ms=%.3f world_build_ms=%.3f weather_ms=%.3f overlay_ms=%.3f",profile_draw_setup_ms/f64(profile_samples),profile_draw_refresh_ms/f64(profile_samples),profile_draw_world_build_ms/f64(profile_samples),profile_draw_weather_ms/f64(profile_samples),profile_draw_overlay_ms/f64(profile_samples)));fmt.println(fmt.tprintf("CHAOS HOUSE structure_ms=%.3f surfaces_ms=%.3f walls_ms=%.3f openings_ms=%.3f objects_ms=%.3f characters_ms=%.3f",profile_house_structure_ms/f64(profile_samples),profile_house_surfaces_ms/f64(profile_samples),profile_house_walls_ms/f64(profile_samples),profile_house_openings_ms/f64(profile_samples),profile_house_objects_ms/f64(profile_samples),profile_house_characters_ms/f64(profile_samples)));fmt.println(fmt.tprintf("CHAOS PHASES shadow_ms=%.3f world_ms=%.3f ui_ms=%.3f tail_ms=%.3f",profile_shadow_ms/f64(profile_samples),profile_world_ms/f64(profile_samples),profile_ui_ms/f64(profile_samples),profile_tail_ms/f64(profile_samples)));fmt.println(fmt.tprintf("CHAOS WORLD lights_ms=%.3f batches_ms=%.3f unbatched_ms=%.3f",profile_lights_ms/f64(profile_samples),profile_batches_ms/f64(profile_samples),profile_unbatched_ms/f64(profile_samples)))};fmt.println("captured Vulkan frame: ",capture_path);g.running=false};frames+=1
	}
	campaign_case_load_reap()
	if g.gamepad!=nil {_=sdl.RumbleGamepad(g.gamepad,0,0,0);sdl.CloseGamepad(g.gamepad)}
}

update_vehicle_haptics :: proc(g:^Game) {
	if g.gamepad==nil||g.vehicle_haptics_failed {g.vehicle_haptics_active=false;return}
	low,high:f32
	if g.screen==.Exterior&&g.driving_vehicle>=0&&g.driving_vehicle<len(g.vehicles) {
		v:=g.vehicles[g.driving_vehicle]
		throttle,_:=vehicle_control_inputs(g);drive_demand:=clamp(throttle,0,1)*vehicle_requested_drive_authority(v,throttle)
		low,high=vehicle_haptic_strengths_blended(v,v.surface_blend,v.handbrake_slip,vehicle_tune(g.driving_vehicle),drive_demand);high=vehicle_assisted_high_haptic(v,high,v.driver_assist,v.driver_assist_strength,v.driver_assist_time)
	}
	if low>.005||high>.005 {
		ok:=sdl.RumbleGamepad(g.gamepad,u16(low*65535),u16(high*65535),40)
		g.vehicle_haptics_active=ok;g.vehicle_haptics_failed=!ok
	} else if g.vehicle_haptics_active {
		_=sdl.RumbleGamepad(g.gamepad,0,0,0);g.vehicle_haptics_active=false
	}
}

begin_frame :: proc(g: ^Game) {g.input.mouse_wheel=0;g.input.dialogue_choice_slot=0;g.input.mouse_pressed=false;g.input.mouse_released=false;g.input.mouse_middle_pressed=false;g.input.mouse_middle_released=false;g.input.activate=false;g.input.vehicle_action=false;g.input.back=false;g.input.left=false;g.input.right=false;g.input.up=false;g.input.down=false;g.input.recreate=false;g.input.notebook=false;g.input.attributes=false;g.input.case_sense=false;g.input.case_sense_release=false;g.input.camera_toggle=false;g.input.wall_view_cycle=false;g.input.shoulder_left=false;g.input.shoulder_right=false;g.input.save_document=false;g.input.undo_document=false;g.input.redo_document=false;g.input.delete_selection=false;g.input.copy_selection=false;g.input.paste_selection=false;g.input.duplicate_selection=false;g.input.text_input_len=0;g.input.clipboard_paste_len=0;g.input.key_enter=false;g.input.key_escape=false;g.input.key_backspace=false;g.input.key_delete=false;g.input.key_tab=false;g.input.key_home=false;g.input.key_end=false;g.input.key_left=false;g.input.key_right=false;g.input.key_a=false;g.input.key_x=false;g.input.key_v=false;g.input.key_c=false}
normalize_gamepad_axis :: proc(value:i16)->f32 {v:=f32(value)/32767.0;if math.abs(v)<0.18 do return 0;return clamp(v,-1,1)}
gamepad_disconnect_should_pause :: proc(screen:Screen)->bool {return screen!=.Title&&screen!=.Campaign&&screen!=.Campaign_Action&&screen!=.Campaign_Cases&&screen!=.Options&&screen!=.Pause}
clear_gamepad_input :: proc(g:^Game) {g.pad_left_x=0;g.pad_left_y=0;g.pad_right_x=0;g.pad_right_y=0;g.pad_left_trigger=0;g.pad_right_trigger=0;g.axis_nav_x=0;g.axis_nav_y=0;for &pressed in g.pad_buttons do pressed=false}
resume_from_controller_disconnect :: proc(g:^Game) {if g.controller_disconnected {g.controller_disconnected=false;g.input_resume_blocked=true}}
activate_keyboard_mouse :: proc(g:^Game) {resume_from_controller_disconnect(g);g.active_device=.Keyboard_Mouse}
activate_gamepad :: proc(g:^Game) {resume_from_controller_disconnect(g);g.active_device=.Gamepad;g.mouse_device_motion={}}
prepare_input_poll :: proc(g:^Game) {if g.input_resume_blocked {begin_frame(g);g.input_resume_blocked=false}}
poll :: proc(g:^Game,window:^sdl.Window) {
	prepare_input_poll(g)
	e:sdl.Event; for sdl.PollEvent(&e) { #partial switch e.type {
	case .QUIT: g.running=false
	case .WINDOW_PIXEL_SIZE_CHANGED: g.window_resized=true
	case .MOUSE_MOTION:
		g.input.mouse_pos=window_mouse_to_logical(window,e.motion.x,e.motion.y);g.mouse_device_motion.x+=e.motion.xrel;g.mouse_device_motion.y+=e.motion.yrel
		if g.active_device==.Keyboard_Mouse||g.mouse_device_motion.x*g.mouse_device_motion.x+g.mouse_device_motion.y*g.mouse_device_motion.y>=4 do activate_keyboard_mouse(g)
	case .MOUSE_WHEEL: g.input.mouse_wheel+=e.wheel.y;activate_keyboard_mouse(g)
	case .MOUSE_BUTTON_DOWN: g.input.mouse_pos=window_mouse_to_logical(window,e.button.x,e.button.y);if e.button.button==2 {g.input.mouse_middle_down=true;g.input.mouse_middle_pressed=true}else if e.button.button==1 {g.input.mouse_down=true;g.input.mouse_pressed=true};activate_keyboard_mouse(g)
	case .MOUSE_BUTTON_UP: g.input.mouse_pos=window_mouse_to_logical(window,e.button.x,e.button.y);if e.button.button==2 {g.input.mouse_middle_down=false;g.input.mouse_middle_released=true}else if e.button.button==1 {g.input.mouse_down=false;g.input.mouse_released=true}
	case .TEXT_INPUT: bytes:=transmute([]u8)string(e.text.text);count:=min(len(bytes),len(g.input.text_input)-g.input.text_input_len);copy(g.input.text_input[g.input.text_input_len:],bytes[:count]);g.input.text_input_len+=count
	case .KEY_DOWN:
		activate_keyboard_mouse(g);key_was_down:=g.keys[e.key.scancode];g.keys[e.key.scancode]=true
		control:=g.keys[.LCTRL]||g.keys[.RCTRL]||g.keys[.LGUI]||g.keys[.RGUI];shift:=g.keys[.LSHIFT]||g.keys[.RSHIFT];g.input.key_ctrl=g.keys[.LCTRL]||g.keys[.RCTRL];g.input.key_super=g.keys[.LGUI]||g.keys[.RGUI];g.input.key_shift=shift
		search_was_active:=g.editor_mode==.Build&&editor_state.search_active
		numeric_was_active:=g.editor_mode==.Build&&editor_state.numeric_field!=.None
		editing_was_active:=search_was_active||numeric_was_active||graph_state.field_edit.active
		if search_was_active&&(e.key.scancode==.RETURN||e.key.scancode==.KP_ENTER) do _=editor_select_first_catalog_match(g)
		if g.editor_mode==.Build&&editor_catalog_visible(g.build_tool)&&!editing_was_active&&!editor_state.object_rotate_active&&e.key.scancode==.SLASH {editor_state.search_active=true;editor_state.catalog_page=0}
			if g.editor_mode==.Build&&!editing_was_active&&!editor_state.object_rotate_active&&!key_was_down&&e.key.scancode==.F1 do editor_state.shortcut_help_visible=!editor_state.shortcut_help_visible
			if g.editor_mode==.Graph&&!editing_was_active&&!key_was_down&&e.key.scancode==.F1 do graph_state.help_visible=!graph_state.help_visible
			if g.editor_mode==.Graph&&!editing_was_active&&!key_was_down&&control&&e.key.scancode==.F do graph_begin_edit(.Search,graph_state.search_query)
			if g.editor_mode==.Graph&&!editing_was_active&&!key_was_down&&!control&&e.key.scancode==.F do _=graph_frame_nodes(graph_state.selection_count>0)
			if g.editor_mode==.Graph&&!editing_was_active&&!key_was_down&&!control&&e.key.scancode==.LEFTBRACKET do _=graph_focus_search_result(-1)
			if g.editor_mode==.Graph&&!editing_was_active&&!key_was_down&&!control&&e.key.scancode==.RIGHTBRACKET do _=graph_focus_search_result(1)
			if g.editor_mode==.Graph&&!editing_was_active&&!key_was_down&&!control&&e.key.scancode==._0 {graph_state.pan={};graph_state.zoom=1}
		if g.editor_mode==.Build&&!editing_was_active&&!editor_state.object_rotate_active {if control&&e.key.scancode==.S do g.input.save_document=true;if control&&e.key.scancode==.Z {if shift do g.input.redo_document=true;else do g.input.undo_document=true};if control&&e.key.scancode==.Y do g.input.redo_document=true;if e.key.scancode==.DELETE||e.key.scancode==.BACKSPACE do g.input.delete_selection=true;if control&&e.key.scancode==.C do g.input.copy_selection=true;if control&&e.key.scancode==.V do g.input.paste_selection=true;if control&&e.key.scancode==.D do g.input.duplicate_selection=true}
		if g.editor_mode==.Build&&!editing_was_active&&!editor_state.object_rotate_active&&!control&&!key_was_down {#partial switch e.key.scancode {case ._1:editor_activate_build_mode(g,.Select);case ._2:editor_activate_build_mode(g,.Room);case ._3:editor_activate_build_mode(g,.Foundation);case ._4:editor_activate_build_mode(g,.Paint);case ._5:editor_activate_build_mode(g,.Plant);case ._6:editor_activate_build_mode(g,.Roof);case ._7:editor_activate_build_mode(g,.Terrain);case ._8:editor_activate_build_mode(g,.Stairs);case ._9:editor_activate_build_mode(g,.Path);case ._0:editor_activate_build_mode(g,.Water);case .M:editor_activate_build_mode(g,.Marker)}}
		if g.editor_mode==.Build&&!editing_was_active&&!editor_state.object_rotate_active&&!control&&!key_was_down&&e.key.scancode==.F do _=editor_frame_selection(g)
		if g.editor_mode==.Build&&!editing_was_active&&!editor_state.object_rotate_active&&!control&&!key_was_down&&e.key.scancode==.LEFTBRACKET do _=editor_focus_adjacent_diagnostic(g,-1)
		if g.editor_mode==.Build&&!editing_was_active&&!editor_state.object_rotate_active&&!control&&!key_was_down&&e.key.scancode==.RIGHTBRACKET do _=editor_focus_adjacent_diagnostic(g,1)
		if g.editor_mode==.Build&&!editing_was_active&&!editor_state.object_rotate_active&&!control&&!key_was_down&&e.key.scancode==.PAGEUP {above:=level_story_above(&level_document,level_document.active_story);if above>=0 do _=editor_switch_story(g,above)}
		if g.editor_mode==.Build&&!editing_was_active&&!editor_state.object_rotate_active&&!control&&!key_was_down&&e.key.scancode==.PAGEDOWN {below:=level_story_below(&level_document,level_document.active_story);if below>=0 do _=editor_switch_story(g,below)}
		if graph_state.field_edit.active {#partial switch e.key.scancode {case .RETURN,.KP_ENTER:g.input.key_enter=true;case .ESCAPE:g.input.key_escape=true;case .BACKSPACE:g.input.key_backspace=true;case .DELETE:g.input.key_delete=true;case .TAB:g.input.key_tab=true;case .UP:g.input.up=true;case .DOWN:g.input.down=true;case .HOME:g.input.key_home=true;case .END:g.input.key_end=true;case .LEFT:g.input.key_left=true;case .RIGHT:g.input.key_right=true;case .A:g.input.key_a=true;case .X:g.input.key_x=true;case .V:g.input.key_v=true;if control {clip:=sdl.GetClipboardText();if clip!=nil {bytes:=transmute([]u8)string(cstring(clip));g.input.clipboard_paste_len=min(len(bytes),len(g.input.clipboard_paste));copy(g.input.clipboard_paste[:],bytes[:g.input.clipboard_paste_len])}};case .C:g.input.key_c=true}}
		if g.editor_mode==.Graph&&!graph_state.field_edit.active&&!key_was_down {if control&&e.key.scancode==.S do g.input.save_document=true;if control&&e.key.scancode==.Z {if shift do g.input.redo_document=true;else do g.input.undo_document=true};if control&&e.key.scancode==.Y do g.input.redo_document=true;if e.key.scancode==.DELETE||e.key.scancode==.BACKSPACE do g.input.delete_selection=true;if control&&e.key.scancode==.C do g.input.copy_selection=true;if control&&e.key.scancode==.V do g.input.paste_selection=true;if control&&e.key.scancode==.D do g.input.duplicate_selection=true;if shift&&e.key.scancode==.A&&contains(graph_canvas_rect(),g.input.mouse_pos) {graph_state.quick_add=true;graph_state.quick_add_at=g.input.mouse_pos;graph_state.quick_add_selected=0}}
		if search_was_active {if e.key.scancode==.BACKSPACE {if editor_state.search_count>0 {editor_state.search_count-=1;editor_state.catalog_page=0}} else if e.key.scancode==.RETURN||e.key.scancode==.KP_ENTER {editor_state.search_active=false} else if e.key.scancode==.SPACE {_=catalog_append_search_char(&editor_state,'_')} else if int(e.key.scancode)>=int(sdl.Scancode.A)&&int(e.key.scancode)<=int(sdl.Scancode.Z) {_=catalog_append_search_char(&editor_state,u8('a'+int(e.key.scancode)-int(sdl.Scancode.A)))} else if int(e.key.scancode)>=int(sdl.Scancode._1)&&int(e.key.scancode)<=int(sdl.Scancode._9) {_=catalog_append_search_char(&editor_state,u8('1'+int(e.key.scancode)-int(sdl.Scancode._1)))} else if e.key.scancode==._0 {_=catalog_append_search_char(&editor_state,'0')}}
		if numeric_was_active {if e.key.scancode==.BACKSPACE {if editor_state.numeric_replace_on_input {editor_state.numeric_count=0;editor_state.numeric_replace_on_input=false}else if editor_state.numeric_count>0 do editor_state.numeric_count-=1} else if e.key.scancode==.RETURN||e.key.scancode==.KP_ENTER {_=editor_commit_numeric_edit()} else if e.key.scancode==.TAB {_=editor_advance_numeric_edit(shift?-1:1)} else if e.key.scancode==.ESCAPE {editor_cancel_numeric_edit()} else if e.key.scancode==.PERIOD||e.key.scancode==.KP_PERIOD {_=editor_append_numeric_char('.')} else if e.key.scancode==.MINUS||e.key.scancode==.KP_MINUS {_=editor_append_numeric_char('-')} else if int(e.key.scancode)>=int(sdl.Scancode._1)&&int(e.key.scancode)<=int(sdl.Scancode._9) {_=editor_append_numeric_char(u8('1'+int(e.key.scancode)-int(sdl.Scancode._1)))} else if e.key.scancode==._0 {_=editor_append_numeric_char('0')} else if int(e.key.scancode)>=int(sdl.Scancode.KP_1)&&int(e.key.scancode)<=int(sdl.Scancode.KP_9) {_=editor_append_numeric_char(u8('1'+int(e.key.scancode)-int(sdl.Scancode.KP_1)))} else if e.key.scancode==.KP_0 {_=editor_append_numeric_char('0')}}
		#partial switch e.key.scancode {case .RETURN,.KP_ENTER,.SPACE:if !editing_was_active do g.input.activate=true;case .E:if !editing_was_active do g.input.activate=true;case .F:if !editing_was_active&&!control&&!key_was_down {if g.screen==.Exterior do g.input.vehicle_action=true;else do g.input.camera_toggle=true};case .N:if !editing_was_active&&!control&&!key_was_down do g.input.notebook=true;case .C:if !editing_was_active&&!control&&!key_was_down do g.input.attributes=true;case .Q:if !editing_was_active&&!key_was_down do g.input.case_sense=true;case .V:if !editing_was_active&&!control do g.input.wall_view_cycle=true;case .ESCAPE:if !editing_was_active do g.input.back=true;case .LEFT:if !editing_was_active do g.input.left=true;case .RIGHT:if !editing_was_active do g.input.right=true;case .UP:if !editing_was_active do g.input.up=true;case .DOWN:if !editing_was_active do g.input.down=true;case .A:if !editing_was_active&&menu_screen(g.screen) do g.input.left=true;case .D:if !editing_was_active&&menu_screen(g.screen) do g.input.right=true;case .W:if !editing_was_active&&menu_screen(g.screen) do g.input.up=true;case .S:if !editing_was_active&&menu_screen(g.screen) do g.input.down=true}
		if !editing_was_active&&!key_was_down&&g.screen==.Dialogue {if e.key.scancode==.PAGEUP do g.input.shoulder_left=true;else if e.key.scancode==.PAGEDOWN do g.input.shoulder_right=true}
		if !editing_was_active&&!key_was_down&&g.screen==.Dialogue {#partial switch e.key.scancode {case ._1,.KP_1:g.input.dialogue_choice_slot=1;case ._2,.KP_2:g.input.dialogue_choice_slot=2;case ._3,.KP_3:g.input.dialogue_choice_slot=3}}
	case .KEY_UP: g.keys[e.key.scancode]=false;if e.key.scancode==.Q do g.input.case_sense_release=true
	case .GAMEPAD_ADDED:
		if g.gamepad==nil {g.gamepad=sdl.OpenGamepad(e.gdevice.which);g.vehicle_haptics_failed=false;if g.gamepad!=nil do g.gamepad_type=sdl.GetGamepadType(g.gamepad)}
	case .GAMEPAD_REMOVED:
		if g.gamepad!=nil && sdl.GetGamepadID(g.gamepad)==e.gdevice.which {was_active:=g.active_device==.Gamepad;pause:=was_active&&gamepad_disconnect_should_pause(g.screen);sdl.CloseGamepad(g.gamepad);g.gamepad=nil;g.gamepad_type=.UNKNOWN;g.vehicle_haptics_active=false;g.vehicle_haptics_failed=false;clear_gamepad_input(g);g.active_device=.Keyboard_Mouse;g.controller_disconnected=pause}
	case .GAMEPAD_AXIS_MOTION:
		v:=normalize_gamepad_axis(e.gaxis.value);if v!=0 do activate_gamepad(g);axis:=sdl.GamepadAxis(e.gaxis.axis);#partial switch axis {
		case .LEFTX:g.pad_left_x=v;step:i8=v>0.55?1:v < -0.55?-1:0;if menu_screen(g.screen)&&step!=0&&g.axis_nav_x==0 {g.input.right=step>0;g.input.left=step<0};g.axis_nav_x=step
		case .LEFTY:g.pad_left_y=v;step:i8=v>0.55?1:v < -0.55?-1:0;if menu_screen(g.screen)&&step!=0&&g.axis_nav_y==0 {g.input.down=step>0;g.input.up=step<0};g.axis_nav_y=step
		case .RIGHTX:g.pad_right_x=v
		case .RIGHTY:g.pad_right_y=v
		case .LEFT_TRIGGER:g.pad_left_trigger=max(v,0)
		case .RIGHT_TRIGGER:g.pad_right_trigger=max(v,0)}
	case .GAMEPAD_BUTTON_DOWN:
		activate_gamepad(g);b:=sdl.GamepadButton(e.gbutton.button);g.pad_buttons[b]=true;#partial switch b {case .SOUTH:g.input.activate=true;case .EAST:g.input.back=true;case .WEST:g.input.recreate=true;case .NORTH:if g.screen==.Exterior do g.input.vehicle_action=true;else do g.input.notebook=true;case .BACK:g.input.wall_view_cycle=true;case .LEFT_STICK:g.input.case_sense=true;case .RIGHT_STICK:g.input.camera_toggle=true;case .LEFT_SHOULDER:g.input.shoulder_left=true;case .RIGHT_SHOULDER:g.input.shoulder_right=true;case .DPAD_LEFT:if menu_screen(g.screen) do g.input.left=true;case .DPAD_RIGHT:if menu_screen(g.screen) do g.input.right=true;case .DPAD_UP:if menu_screen(g.screen)||g.screen==.Investigate do g.input.up=true;case .DPAD_DOWN:if menu_screen(g.screen)||g.screen==.Investigate do g.input.down=true}
	case .GAMEPAD_BUTTON_UP: b:=sdl.GamepadButton(e.gbutton.button);g.pad_buttons[b]=false;if b==.LEFT_STICK do g.input.case_sense_release=true
} } }

button_id :: proc(r: Rect) -> ui.Gui_Id {
	x := u64(int(r.x) + 2048); y := u64(int(r.y) + 2048)
	w := u64(int(r.w)); h := u64(int(r.h))
	return ui.Gui_Id((x << 44) ~ (y << 24) ~ (w << 12) ~ h)
}
button :: proc(g:^Game, r:Rect) -> bool {
	return ui.gui_button_at(&g.gui, button_id(r), {r.x,r.y,r.w,r.h}, "", true)
}
menu_screen :: proc(screen:Screen)->bool {return screen!=.Exterior&&screen!=.Investigate}
menu_default_rect :: proc(g:^Game)->Rect {
	#partial switch g.screen {
	case .Title:return {410,400,380,48}
	case .Campaign:return campaign_browser_card_logical_rect(0)
	case .Campaign_Action:return {410,286,380,52}
	case .Campaign_Cases:return {760,610,310,52}
	case .Options:return {410,145,380,48}
	case .Pause:return {410,210,380,48}
	case .Introduction:return {410,625,380,58}
	case .Dialogue:return dialogue_default_rect(g)
	case .Check:if g.check_done do return {430,500,340,50};return {430,510,340,58}
	case .Attributes:return {42,145,250,105}
	case .Notebook:return {20,95,205,46}
	case .Board:return {25,125,325,66}
	case .Challenge:return {70,205,330,104}
	case .Recreate:return {440,630,320,54}
	case .Reveal_Prep:return {440,630,320,54}
	case .Reveal:return {440,630,320,54}
	case .Result:return {300,630,280,54}
	case .Game_Over:return {410,410,380,52}
	case .Diagnostics:return {20,650,180,42}
	}
	return {}
}
log_line :: proc(g:^Game,s:string){g.log[3]=g.log[2];g.log[2]=g.log[1];g.log[1]=g.log[0];g.log[0]=s;if g.history_count<len(g.history){g.history[g.history_count]=s;g.history_count+=1}}
case_pacing_record :: proc(g:^Game,index:int,ready:bool) {if !ready||index<0||index>=len(g.case_pacing_times)||(g.case_pacing_mask&(u8(1)<<u8(index)))!=0 do return;g.case_pacing_mask|=u8(1)<<u8(index);g.case_pacing_times[index]=g.animation_time}
update_case_pacing :: proc(g:^Game) {
	if g.story_project==nil||g.story_project.id!="the_torn_appointment" do return
	case_pacing_record(g,0,g.screen==.Investigate||g.screen==.Dialogue||g.phase>=.Investigation)
	case_pacing_record(g,1,claim_known(g,"claim_miriam_dinner")&&claim_known(g,"claim_daniel_alibi")&&claim_known(g,"claim_elsie_study"))
	case_pacing_record(g,2,knowledge_piece_known(g,"ded_scene_staged"))
	case_pacing_record(g,3,knowledge_piece_known(g,"ded_daniel_affair")&&knowledge_piece_known(g,"ded_elsie_theft"))
	case_pacing_record(g,4,knowledge_piece_known(g,"ded_miriam_denial_disproved"))
	case_pacing_record(g,5,g.phase==.Case_Result||g.screen==.Result)
}
pacing_time_label :: proc(seconds:f32)->string {whole:=max(0,int(seconds));return fmt.tprintf("%02d:%02d",whole/60,whole%60)}
pacing_band_status :: proc(seconds,min_seconds,max_seconds:f32)->string {if seconds<min_seconds do return "EARLY";if seconds>max_seconds do return "LATE";return "ON TARGET"}
case_optional_beat_completed :: proc(g:^Game,id:string)->bool {payload:=mystery_game_payload(g);if payload==nil do return false;for i in 0..<mystery_dialogue_approach_count(payload) {node:=mystery_dialogue_approach_at(payload,i);if node!=nil&&node.node_id==id do return mystery_game_dialogue_completed(g,i)&&!mystery_game_dialogue_failed(g,i)};return false}
case_pacing_report_text :: proc(g:^Game)->string {
	labels:=[6]string{"Arrival","Three accounts","False scene","Other lies","Torn note","Outcome"}
	band_mins:=[6]f32{0,5*60,15*60,30*60,45*60,55*60};band_maxes:=[6]f32{5*60,15*60,30*60,45*60,55*60,60*60}
	result:="The Torn Appointment — first-playthrough pace"
	for label,i in labels {recorded:=(g.case_pacing_mask&(u8(1)<<u8(i)))!=0;value:=recorded?pacing_time_label(g.case_pacing_times[i]):"--:--";target:=fmt.tprintf("%s–%s",pacing_time_label(band_mins[i]),pacing_time_label(band_maxes[i]));status:=recorded?pacing_band_status(g.case_pacing_times[i],band_mins[i],band_maxes[i]):"PENDING";result=fmt.tprintf("%s\n%s: %s · target %s · %s",result,label,value,target,status)}
	optional_ids:=[7]string{"approach_miriam_edgar","approach_daniel_edgar","approach_elsie_edgar","approach_daniel_memo_habit","approach_elsie_burned_paper","approach_elsie_explanation","approach_miriam_other_lies"};optional_labels:=[7]string{"Miriam's clock memory","Daniel's leverage memory","Elsie's bell memory","Edgar's memo habit","Miriam's burning habit","Elsie's sixteen pounds","Three-way dinner confrontation"};optional_count:=0;optional_text:="";for id,i in optional_ids do if case_optional_beat_completed(g,id) {optional_count+=1;optional_text=fmt.tprintf("%s%s%s",optional_text,optional_text==""?"":", ",optional_labels[i])};if optional_text=="" do optional_text="none"
	return fmt.tprintf("%s\nDesigned optional beats: %d/7 — %s\nOther optional scenes encountered:\nConfusion or dead air:\nFinal outcome:",result,optional_count,optional_text)
}
copy_case_pacing_report :: proc(g:^Game) {
	value:=case_pacing_report_text(g);clipboard,err:=strings.clone_to_cstring(value,context.temp_allocator);if err==nil {_=sdl.SetClipboardText(clipboard);log_line(g,"First-playthrough pace report copied to the clipboard.")}else do log_line(g,"The pace report could not be copied; open diagnostics to read the timestamps.")
}
topic_unlocked :: proc(g:^Game,topic:string)->bool {return g.mystery_state!=nil&&mystery_string_set_has(g.mystery_state.unlocked_topics[:],topic)}
unlock_topic :: proc(g:^Game,topic:string){if topic==""||topic_unlocked(g,topic)||g.mystery_state==nil do return;_=mystery_string_set_add(&g.mystery_state.unlocked_topics,topic)}
claim_index :: proc(g:^Game,id:string)->int {return mystery_claim_index(mystery_game_payload(g),id)}
claim_known :: proc(g:^Game,id:string)->bool {return g.mystery_state!=nil&&mystery_string_set_has(g.mystery_state.established_claims[:],id)}
learn_claim :: proc(g:^Game,id:string)->bool {i:=claim_index(g,id);payload:=mystery_game_payload(g);if payload==nil||g.mystery_state==nil||i<0||claim_known(g,id) do return false;if !mystery_establish_claim(g.story_project,g.mystery_state,id) do return false;tutorial_complete(g,.Converse);claim:=&payload.claims[i];log_line(g,fmt.tprintf("Statement recorded: %s",mystery_story_proposition_text(g.story_project,claim.proposition_id)));refresh_questions(g);if overtime_active(g)&&proof_framework_attainable(g,payload.solution.culprit_id) do finish_overtime(g);return true}
learn_initial_claims :: proc(g:^Game,character_id:string)->int {
	learned:=0;payload:=mystery_game_payload(g);if payload==nil do return 0
	metadata:=mystery_character_metadata(payload,character_id);if metadata!=nil {for id in metadata.initial_claims[:metadata.initial_claim_count] {if learn_claim(g,id) do learned+=1}}
	refresh_questions(g)
	return learned
}
dialogue_approach_available :: proc(g:^Game,index:int)->bool {
	payload:=mystery_game_payload(g);node:=mystery_dialogue_approach_at(payload,index)
	if node==nil||(mystery_game_dialogue_completed(g,index)&&!mystery_game_dialogue_failed(g,index)) do return false
	if g.mystery_state!=nil&&!mystery_node_requirements_met(g.story_project,g.mystery_state,node.node_id) do return false
	if node.clue_id!="" {clue:=mystery_clue_index(payload,node.clue_id);return clue>=0&&clue_available(g,clue)}
	return true
}
dialogue_approach_flow_priority :: proc(g:^Game,index:int)->int {
	payload:=mystery_game_payload(g);node:=mystery_dialogue_approach_at(payload,index);if node==nil do return -1
	// Checks create evidence and should never be hidden behind optional color.
	priority:=node.require_count*10;if node.clue_id!="" do priority+=1000
	// Prefer a question whose discoveries unlock another currently unfinished
	// conversation. This keeps gateway accounts ahead of flavor while remaining
	// data-driven for other authored mysteries.
	for unlock in node.unlocks[:node.unlock_count] {
		for candidate_index in 0..<mystery_dialogue_approach_count(payload) {
			if candidate_index==index||mystery_game_dialogue_completed(g,candidate_index) do continue
			candidate:=mystery_dialogue_approach_at(payload,candidate_index);if candidate==nil do continue
			for requirement in candidate.requires[:candidate.require_count] do if requirement==unlock {priority+=100;break}
		}
	}
	return priority
}
visible_dialogue_approach :: proc(g:^Game,character:string,slot:int)->int {
	payload:=mystery_game_payload(g);if slot<0 do return -1
	selected:[32]bool
	for rank in 0..=slot {
		best,best_priority:=-1,-1
		for i in 0..<mystery_dialogue_approach_count(payload) {
			if i>=len(selected)||selected[i] do continue
			node:=mystery_dialogue_approach_at(payload,i);if node==nil||node.character_id!=character||!dialogue_approach_available(g,i) do continue
			priority:=dialogue_approach_flow_priority(g,i);if priority>best_priority {best=i;best_priority=priority}
		}
		if best<0 do return -1
		if rank==slot do return best
		selected[best]=true
	}
	return -1
}
dialogue_approach_failure_topic :: proc(id:string)->string {switch id {case "approach_daniel_affair":return "failed_daniel_affair";case "approach_elsie_theft":return "failed_elsie_theft"};return ""}
dialogue_approach_failure_response :: proc(g:^Game,index:int)->string {
	payload:=mystery_game_payload(g);node:=mystery_dialogue_approach_at(payload,index);if node==nil do return "The question lands badly. Try another angle."
	switch node.node_id {
	case "approach_daniel_affair":return "'I have given you my account.' Daniel checks his inner pocket before meeting your eye. The sentence is rehearsed; the hand is not."
	case "approach_elsie_theft":return "'You decided what I am before you asked.' Elsie's gaze returns to Edgar's desk, and one thumb counts silently against the side of her apron."
	}
	clue_index:=mystery_clue_index(payload,node.clue_id);if clue_index>=0 {clue:=&payload.clues[clue_index];if clue.check_kind=="red" do return "They end that line of questioning. Their reaction remains part of the conversation.";return "They refuse the premise. Watch what they protect, then try another angle."}
	return "The question lands badly. Try another angle."
}
complete_dialogue_approach :: proc(g:^Game,index:int){payload:=mystery_game_payload(g);node:=mystery_dialogue_approach_at(payload,index);if node==nil do return;_=mystery_game_mark_dialogue(g,index,false);if g.mystery_state!=nil do _=mystery_apply_node_metadata(g.story_project,g.mystery_state,node.node_id);for id in node.unlocks[:node.unlock_count] {if clue:=mystery_clue_index(payload,id);clue>=0 do _=discover_clue_free(g,clue);else if mystery_claim_index(payload,id)>=0 do _=learn_claim(g,id);else do unlock_topic(g,id)};g.dialogue_node=0;g.dialogue_response="";g.dialogue_text_started=g.animation_time;if g.screen==.Dialogue {g.dialogue_ledger_scroll=0;g.dialogue_choice_page=0};_=apply_story_node_animation_asset(g,node.node_id);_=play_story_node_sound(g,node.node_id);dialogue_focus_default(g)}
fail_dialogue_approach :: proc(g:^Game,index:int){node:=mystery_dialogue_approach_at(mystery_game_payload(g),index);if node==nil do return;response:=dialogue_approach_failure_response(g,index);topic:=dialogue_approach_failure_topic(node.node_id);if topic!="" do unlock_topic(g,topic);_=mystery_game_mark_dialogue(g,index,true);g.dialogue_node=0;g.dialogue_response="";conversation_transcript_append(g,node.character_id,response,"action",node.character_id);g.dialogue_text_started=g.animation_time;if g.screen==.Dialogue {g.dialogue_ledger_scroll=0;g.dialogue_choice_page=0};log_line(g,response);dialogue_focus_default(g)}
initialize_dispositions :: proc(g:^Game){payload:=mystery_game_payload(g);if payload!=nil&&g.mystery_state!=nil do for character in payload.characters {found:=false;for disposition in g.mystery_state.dispositions do if disposition.entity_id==character.entity_id do found=true;if !found do mystery_game_set_disposition(g,character.entity_id,character.initial_disposition)}}
character_index :: proc(g:^Game,id:string)->int {payload:=mystery_game_payload(g);if payload!=nil do for character,i in payload.characters do if character.entity_id==id do return i;return -1}
disposition_rect :: proc()->Rect {return {976,52,174,32}}
dialogue_disposition_label :: proc(value:int)->string {state:=value>0?"RECEPTIVE":value<0?"GUARDED":"NEUTRAL";return fmt.tprintf("%s  ·  CHECK %+d",state,clamp(value,-2,2))}
disposition_summary :: proc(g:^Game,character_index:int)->string {
	payload:=mystery_game_payload(g);if payload==nil||character_index<0||character_index>=len(payload.characters) do return "Their feelings are difficult to read."
	character:=&payload.characters[character_index];current:=mystery_game_disposition(g,character.entity_id)
	if current>character.initial_disposition do return "Your successful approaches have made them more willing to engage."
	if current<character.initial_disposition do return "A failed approach left them guarded and less receptive."
	switch character.entity_id {
	case "miriam":return "She is composed and confident she can control the conversation."
	case "daniel":return "He is cautious, but has not decided whether you are a threat."
	case "elsie":return "She expects suspicion and is protecting herself from accusation."
	}
	return current>0?"They are presently receptive.":"They are presently guarded."
}
clue_disposition :: proc(g:^Game,clue_index:int)->int {payload:=mystery_game_payload(g);if payload==nil||clue_index<0||clue_index>=len(payload.clues) do return 0;i:=character_index(g,payload.clues[clue_index].source_id);if i<0 do return 0;return mystery_game_disposition(g,payload.characters[i].entity_id)}
apply_check_disposition :: proc(g:^Game,clue_index:int,success:bool)->int {payload:=mystery_game_payload(g);if payload==nil||clue_index<0||clue_index>=len(payload.clues) do return 0;i:=character_index(g,payload.clues[clue_index].source_id);if i<0 do return 0;delta:=success?1:-1;id:=payload.characters[i].entity_id;before:=mystery_game_disposition(g,id);mystery_game_set_disposition(g,id,before+delta);return mystery_game_disposition(g,id)-before}
action_warning_text :: proc(g:^Game)->string {if g.ap<=2 do return "DEADLINE IMMINENT — only two clock ticks remain";if g.ap<=4 do return "Time is narrowing — four clock ticks remain";return ""}
load_sound_assets :: proc(g:^Game)->int {
	paths:=[Sound_Cue]string{
		.Evidence="assets/audio/cues/clue-revealed.ogg",.Fact="assets/audio/cues/fact-established.ogg",
		.Pick_Up="assets/kenney_ui-audio/Audio/click3.ogg",.Snap="assets/kenney_ui-audio/Audio/switch31.ogg",.Reject="assets/kenney_ui-audio/Audio/switch8.ogg",.Recreate="assets/kenney_ui-audio/Audio/switch20.ogg",
		.Shutter="assets/audio/cues/crank-resistance.ogg",.Sightline_Fail="assets/kenney_ui-audio/Audio/switch10.ogg",.Tick="assets/kenney_ui-audio/Audio/switch7.ogg",.Reveal_Proven="assets/audio/cues/reveal-section-proven.ogg",
		.Door_Open="assets/audio/cues/wood-open.ogg",.Door_Close="assets/audio/cues/wood-close.ogg",.Switch="assets/kenney_ui-audio/Audio/switch13.ogg",
		.Decisive_Clue="assets/audio/cues/decisive-clue.ogg",.Candle_Out="assets/audio/cues/candle-extinguished.ogg",.Shutter_Close="assets/audio/cues/wood-close.ogg",
	};loaded:=0
	for cue in Sound_Cue {path:=paths[cue];channels,sample_rate:i32;decoded:[^]i16;frames:=stb_vorbis_decode_filename(strings.clone_to_cstring(path,context.temp_allocator),&channels,&sample_rate,&decoded);if frames<=0||decoded==nil||channels<=0 {continue};defer chicago_vorbis_free(decoded);if sample_rate!=44100 do continue;frame_count:=int(frames);g.sounds[cue]=make([dynamic]f32,frame_count);for frame in 0..<frame_count {mixed:f32=0;for channel in 0..<int(channels) do mixed+=f32(decoded[frame*int(channels)+channel])/32768;g.sounds[cue][frame]=mixed/f32(channels)};loaded+=1}
	return loaded
}
destroy_sound_assets :: proc(g:^Game) {for &samples in g.sounds do if samples!=nil do delete(samples)}
play_sound :: proc(g:^Game,cue:Sound_Cue) {
	if g.mute||g.audio_stream==nil do return
	if len(g.sounds[cue])>0 {samples:=g.sounds[cue];_=sdl.PutAudioStreamData(g.audio_stream,rawptr(&samples[0]),i32(len(samples)*size_of(f32)));return}
	// A generated click remains as a defensive fallback if an asset is missing.
	frequencies:=[Sound_Cue]f32{.Evidence=880,.Fact=660,.Pick_Up=420,.Snap=760,.Reject=145,.Recreate=330,.Shutter=95,.Sightline_Fail=180,.Tick=120,.Reveal_Proven=990,.Door_Open=260,.Door_Close=220,.Switch=520,.Decisive_Clue=740,.Candle_Out=80,.Shutter_Close=110};durations:=[Sound_Cue]f32{.Evidence=.16,.Fact=.22,.Pick_Up=.08,.Snap=.12,.Reject=.13,.Recreate=.22,.Shutter=.28,.Sightline_Fail=.18,.Tick=.24,.Reveal_Proven=.25,.Door_Open=.18,.Door_Close=.18,.Switch=.1,.Decisive_Clue=.32,.Candle_Out=.14,.Shutter_Close=.3};frequency:=frequencies[cue];sample_count:=min(int(44100*durations[cue]),12000);samples:[12000]f32
	for i in 0..<sample_count {t:=f32(i)/44100;envelope:=1-f32(i)/f32(sample_count);wave:=f32(math.sin(f64(2*math.PI*frequency*t)));if cue==.Shutter do wave=wave*.55+f32(math.sin(f64(2*math.PI*(frequency*.5)*t)))*.45;if cue==.Reject||cue==.Sightline_Fail do frequency*=.99994;samples[i]=wave*envelope*.16}
	_=sdl.PutAudioStreamData(g.audio_stream,rawptr(&samples[0]),i32(sample_count*size_of(f32)))
}

play_story_node_sound :: proc(g:^Game,node_id:string)->bool {if g==nil||g.mute||g.audio_stream==nil do return false;path,ok:=story_node_sound_path(g.story_project,&authoring_workspace.assets,node_id);if !ok||!os.is_file(path) do return false;channels,sample_rate:i32;decoded:[^]i16;frames:=stb_vorbis_decode_filename(strings.clone_to_cstring(path,context.temp_allocator),&channels,&sample_rate,&decoded);if frames<=0||decoded==nil||channels<=0||sample_rate!=44100 do return false;defer chicago_vorbis_free(decoded);samples:=make([]f32,int(frames),context.temp_allocator);for frame in 0..<int(frames) {mixed:f32=0;for channel in 0..<int(channels) do mixed+=f32(decoded[frame*int(channels)+channel])/32768;samples[frame]=mixed/f32(channels)};return sdl.PutAudioStreamData(g.audio_stream,raw_data(samples),i32(len(samples)*size_of(f32)))}

project_asset_audio_preview_info :: proc(project_root:string,registry:^Project_Asset_Registry,id:string)->(frames,channels,sample_rate:int,ready:bool) {if registry==nil do return;index:=project_asset_index(registry,id);if index<0||registry.assets[index].kind!=.Audio do return;path:=project_asset_record_path(project_root,registry.assets[index]);if !os.is_file(path) do return;if strings.to_lower(os.ext(path))==".ogg" {decoded_channels,decoded_rate:i32;decoded:[^]i16;decoded_frames:=stb_vorbis_decode_filename(strings.clone_to_cstring(path,context.temp_allocator),&decoded_channels,&decoded_rate,&decoded);if decoded!=nil do chicago_vorbis_free(decoded);return int(decoded_frames),int(decoded_channels),int(decoded_rate),decoded_frames>0&&decoded_channels>0&&decoded_rate==44100};data,err:=os.read_entire_file_from_path(path,context.temp_allocator);if err!=nil||len(data)<44||string(data[:4])!="RIFF" do return;channels=int(project_asset_u16_le(data,22));sample_rate=int(project_asset_u32_le(data,24));bits:=int(project_asset_u16_le(data,34));if channels<=0||sample_rate!=44100||bits!=16 do return;at:=12;for at+8<=len(data) {size:=int(project_asset_u32_le(data,at+4));if at+8+size>len(data) do break;if string(data[at:at+4])=="data" {frames=size/(channels*2);return frames,channels,sample_rate,frames>0};at+=8+size+(size&1)};return}

apply_story_node_animation_asset :: proc(g:^Game,node_id:string)->bool {if g==nil||g.story_project==nil do return false;path,ok:=story_node_animation_path(g.story_project,&authoring_workspace.assets,node_id);if !ok||!os.is_file(path) do return false;mesh,loaded:=glb_load(path);if !loaded||!mesh.ready do return false;node_index:=project_asset_story_node_index(g.story_project,node_id);if node_index<0 do return false;actor:=g.story_project.nodes[node_index].actor;if actor=="" do actor=g.story_project.nodes[node_index].speaker_id;payload:=mystery_game_payload(g);if payload==nil do return false;for character,i in payload.characters do if character.entity_id==actor&&i+1<len(character_meshes) {character_meshes[i+1]=mesh;return true};return false}

play_project_asset_audio :: proc(g:^Game,registry:^Project_Asset_Registry,id:string)->bool {
	if g==nil||registry==nil||g.mute||g.audio_stream==nil do return false
	_,_,_,ready:=project_asset_audio_preview_info(active_authoring_project.root_path,registry,id);if !ready do return false
	index:=project_asset_index(registry,id);if index<0||registry.assets[index].kind!=.Audio do return false
	path:=project_asset_record_path(active_authoring_project.root_path,registry.assets[index]);if !os.is_file(path) do return false
	// OGG is decoded through the same production path used by authored sound
	// cues. WAV PCM16 previews are converted directly from the validated RIFF
	// payload so every supported authoring audio format can be auditioned.
	if strings.to_lower(os.ext(path))==".ogg" {channels,sample_rate:i32;decoded:[^]i16;frames:=stb_vorbis_decode_filename(strings.clone_to_cstring(path,context.temp_allocator),&channels,&sample_rate,&decoded);if frames<=0||decoded==nil||channels<=0||sample_rate!=44100 do return false;defer chicago_vorbis_free(decoded);samples:=make([]f32,int(frames),context.temp_allocator);for frame in 0..<int(frames) {mixed:f32=0;for channel in 0..<int(channels) do mixed+=f32(decoded[frame*int(channels)+channel])/32768;samples[frame]=mixed/f32(channels)};return sdl.PutAudioStreamData(g.audio_stream,raw_data(samples),i32(len(samples)*size_of(f32)))}
	data,err:=os.read_entire_file_from_path(path,context.temp_allocator);if err!=nil||len(data)<44||string(data[:4])!="RIFF" do return false
	channels:=int(project_asset_u16_le(data,22));sample_rate:=int(project_asset_u32_le(data,24));bits:=int(project_asset_u16_le(data,34));if channels<=0||sample_rate!=44100||bits!=16 do return false
	at:=12;payload:[]u8;for at+8<=len(data) {size:=int(project_asset_u32_le(data,at+4));if at+8+size>len(data) do break;if string(data[at:at+4])=="data" {payload=data[at+8:at+8+size];break};at+=8+size+(size&1)};if len(payload)<channels*2 do return false
	frames:=len(payload)/(channels*2);samples:=make([]f32,frames,context.temp_allocator);for frame in 0..<frames {mixed:f32=0;for channel in 0..<channels {sample_at:=(frame*channels+channel)*2;raw:=i16(u16(payload[sample_at])|u16(payload[sample_at+1])<<8);mixed+=f32(raw)/32768};samples[frame]=mixed/f32(channels)};return sdl.PutAudioStreamData(g.audio_stream,raw_data(samples),i32(len(samples)*size_of(f32)))
}

update_vehicle_drive_audio :: proc(g:^Game,v:Vehicle_State,tune:Vehicle_Tune,throttle:f32) {
	if g==nil||g.mute||g.vehicle_audio_stream==nil do return
	target_frequency,target_gain:=vehicle_engine_targets(v,tune,throttle)
	if g.vehicle_audio_frequency<=0 do g.vehicle_audio_frequency=target_frequency
	g.vehicle_audio_frequency+=(target_frequency-g.vehicle_audio_frequency)*.10
	g.vehicle_audio_gain+=(target_gain-g.vehicle_audio_gain)*.14
	target_tire_gain:=max(vehicle_tire_audio_target_blended(v,v.handbrake_slip),vehicle_assist_audio_gain(v.driver_assist,v.driver_assist_strength,v.driver_assist_time));g.vehicle_audio_tire_gain+=(target_tire_gain-g.vehicle_audio_tire_gain)*.18
	target_tire_frequency_a,target_tire_frequency_b:=vehicle_tire_audio_frequencies_for_vehicle(v,v.traction_state,v.driver_assist,v.driver_assist_strength);g.vehicle_audio_tire_frequency_a=vehicle_tire_frequency_step(g.vehicle_audio_tire_frequency_a,target_tire_frequency_a);g.vehicle_audio_tire_frequency_b=vehicle_tire_frequency_step(g.vehicle_audio_tire_frequency_b,target_tire_frequency_b)
	target_rough_gain:=vehicle_rough_feedback_blended(v,v.surface_blend)*.026;g.vehicle_audio_rough_gain+=(target_rough_gain-g.vehicle_audio_rough_gain)*.16
	rough_frequency:=vehicle_rough_audio_frequency(v)
	// One exact fixed-tick chunk keeps latency bounded and makes synthesis
	// deterministic regardless of render rate. A dedicated stream lets UI cues
	// overlap the engine instead of waiting behind it in a shared queue.
	samples:[735]f32
	for i in 0..<len(samples) {
		phase:=g.vehicle_audio_phase;fundamental:=f32(math.sin(f64(phase)));second:=f32(math.sin(f64(phase*2)));fourth:=f32(math.sin(f64(phase*4)))
		pulse:=fundamental*.58+second*.28+fourth*.14
		// Independent incommensurate phases produce a stable scrub texture. Each
		// oscillator wraps on its own full cycle, avoiding discontinuities.
		tire_a:=f32(math.sin(f64(g.vehicle_audio_tire_phase_a)));tire_b:=f32(math.sin(f64(g.vehicle_audio_tire_phase_b)));tire:=tire_a*.62+tire_b*.38
		rough:=f32(math.sin(f64(g.vehicle_audio_rough_phase)))*.72+f32(math.sin(f64(g.vehicle_audio_rough_phase*2)))*.28
		samples[i]=pulse*g.vehicle_audio_gain+tire*g.vehicle_audio_tire_gain+rough*g.vehicle_audio_rough_gain
		g.vehicle_audio_phase+=f32(2*math.PI)*g.vehicle_audio_frequency/44100
		if g.vehicle_audio_phase>f32(2*math.PI) do g.vehicle_audio_phase-=f32(2*math.PI)
		g.vehicle_audio_tire_phase_a+=f32(2*math.PI)*g.vehicle_audio_tire_frequency_a/44100;g.vehicle_audio_tire_phase_b+=f32(2*math.PI)*g.vehicle_audio_tire_frequency_b/44100
		if g.vehicle_audio_tire_phase_a>f32(2*math.PI) do g.vehicle_audio_tire_phase_a-=f32(2*math.PI)
		if g.vehicle_audio_tire_phase_b>f32(2*math.PI) do g.vehicle_audio_tire_phase_b-=f32(2*math.PI)
		g.vehicle_audio_rough_phase+=f32(2*math.PI)*rough_frequency/44100;if g.vehicle_audio_rough_phase>f32(2*math.PI) do g.vehicle_audio_rough_phase-=f32(2*math.PI)
	}
	_=sdl.PutAudioStreamData(g.vehicle_audio_stream,rawptr(&samples[0]),i32(len(samples)*size_of(f32)))
}

play_vehicle_impact_sound :: proc(g:^Game,impact:f32) {
	if g==nil||g.mute||g.audio_stream==nil do return
	frequency,gain,duration:=vehicle_impact_audio_parameters(impact);sample_count:=min(int(duration*44100),7056);samples:[7056]f32
	for i in 0..<sample_count {
		t:=f32(i)/44100;envelope:=f32(math.exp(f64(-t*(24+impact*18))));body:=f32(math.sin(f64(2*math.PI*frequency*t)));knock:=f32(math.sin(f64(2*math.PI*(frequency*2.73)*t)))
		// A deterministic high partial supplies the initial contact without noise
		// generators or assets; the low body carries perceived impact weight.
		attack:=clamp(1-t/.006,0,1);samples[i]=(body*.72+knock*.28*attack)*envelope*gain
	}
	_=sdl.PutAudioStreamData(g.audio_stream,rawptr(&samples[0]),i32(sample_count*size_of(f32)))
}

play_check_dice_sound :: proc(g:^Game) {
	if g==nil||g.audio_stream==nil do return
	// A short deterministic wooden rattle: six decaying impacts accelerate,
	// then leave room for the settled result cue.
	sample_rate:f32=44100;sample_count:=int(CHECK_ROLL_DURATION*sample_rate);samples:=make([]f32,sample_count,context.temp_allocator)
	impacts:=[6]f32{.05,.17,.31,.48,.70,1.02}
	for i in 0..<sample_count {t:=f32(i)/sample_rate;value:f32=0;for impact,index in impacts {age:=t-impact;if age<0||age>.09 do continue;decay:=f32(math.exp(f64(-age*55)));frequency:=f32(520+index*73);value+=f32(math.sin(f64(2*math.PI*frequency*age)))*decay*.11};samples[i]=value}
	_=sdl.PutAudioStreamData(g.audio_stream,rawptr(&samples[0]),i32(len(samples)*size_of(f32)))
}

late_case_clock_line :: proc(g:^Game)->string {
	elsie:=knowledge_piece_known(g,"clue_elsie")?"Elsie keeps clear of the cash box now.":"Elsie hovers near Edgar's cash box, a folded banknote in hand."
	miriam:=knowledge_piece_known(g,"clue_burned_fragment")?"Miriam watches the scorched fragment without speaking.":"Miriam watches each new piece of evidence without speaking."
	return fmt.tprintf("The clock advances again. %s %s",elsie,miriam)
}

consume_action :: proc(g:^Game,cost:int) {
	if cost<=0 || cost>g.ap do return
	before:=g.ap
	g.ap-=cost;play_sound(g,.Tick);play_sound(g,.Candle_Out)
	if !g.threshold_four_spent&&before>8&&g.ap<=8 {
		g.threshold_four_spent=true
		unlock_topic(g,"household_tension")
		log_line(g,"The clock advances. Daniel grows visibly nervous; Miriam warns the room against speculation.")
	}
	if !g.threshold_eight_spent&&before>4&&g.ap<=4 {
		g.threshold_eight_spent=true
		unlock_topic(g,"late_case_changes")
		log_line(g,late_case_clock_line(g))
	}
	if before>4&&g.ap<=4 do log_line(g,"Four clock ticks remain. Test your reconstruction while time remains.")
	if before>2&&g.ap<=2 do log_line(g,"Two clock ticks remain. Prepare your final account.")
	if g.ap<=0 {g.ap=0;payload:=mystery_game_payload(g);culprit:=payload!=nil?payload.solution.culprit_id:"";if !proof_framework_attainable(g,culprit)&&begin_proof_overtime(g) {log_line(g,"Protected overtime is active for the shortest remaining proof route.")}else{g.investigation_locked=true;g.phase=.Reveal_Preparation;g.game_over_reason="";if !g.check_from_dialogue {g.board_view=0;g.screen=.Board;log_line(g,"The investigation clock is spent. Use the facts already gathered to prepare an accusation.")}}}
}
spend :: proc(g:^Game, clue:int) {
	payload:=mystery_game_payload(g);if payload==nil||clue<0||clue>=len(payload.clues)||g.ap<=0 || mystery_game_clue_discovered(g,clue) || payload.clues[clue].cost>g.ap do return
	_=mystery_game_mark_clue(g,clue);mystery_game_mark_clue_attempted(g,clue);g.case_sense_level=0;play_sound(g,.Evidence)
	if g.mystery_state!=nil do _=mystery_acquire_evidence(g.story_project,g.mystery_state,payload.clues[clue].id)
	refresh_questions(g)
	consume_action(g,payload.clues[clue].cost)
	for topic in payload.clues[clue].topics[:payload.clues[clue].topic_count] do unlock_topic(g,topic)
	log_line(g,mystery_clue_proposition_text(g.story_project,&payload.clues[clue]))
}

source_location :: proc(g:^Game, clue:int)->int {
	payload:=mystery_game_payload(g);if payload==nil||clue<0||clue>=len(payload.clues) do return -1;source:=payload.clues[clue].source_id
	for &location,i in payload.locations {
		if location.entity_id==source do return i
		for j in 0..<location.character_count do if location.characters[j]==source do return i
		for j in 0..<location.poi_count do if location.pois[j]==source do return i
	}
	return -1
}
overtime_active :: proc(g:^Game)->bool {if g.overtime_clue_plus_one>0 do return true;payload:=mystery_game_payload(g);if payload!=nil do for _,i in payload.clues do if mystery_game_clue_overtime_free(g,i) do return true;return false}
overtime_clue :: proc(g:^Game)->int {return g.overtime_clue_plus_one-1}
overtime_lead :: proc(g:^Game)->int {return g.overtime_lead_plus_one-1}
clue_is_overtime_action :: proc(g:^Game,clue:int)->bool {return mystery_game_clue_overtime_free(g,clue)||g.overtime_clue_plus_one>0&&(clue==overtime_clue(g)||clue==overtime_lead(g))}
clue_action_cost :: proc(g:^Game,clue:int)->int {if clue_is_overtime_action(g,clue) do return 0;payload:=mystery_game_payload(g);if payload==nil||clue<0||clue>=len(payload.clues) do return 0;return payload.clues[clue].cost}

mark_overtime_prerequisites :: proc(g:^Game,clue_index:int) {payload:=mystery_game_payload(g);if payload==nil||clue_index<0||clue_index>=len(payload.clues) do return;target:=&payload.clues[clue_index];for j in 0..<target.prerequisite_count {prerequisite:=target.prerequisites[j];for clue,i in payload.clues do if clue.id==prerequisite&&!mystery_game_clue_discovered(g,i) {mystery_game_set_clue_overtime_free(g,i,true);mark_overtime_prerequisites(g,i)}}}
mark_recovery_prerequisites :: proc(g:^Game,clue_index:int,used:^[16]bool) {payload:=mystery_game_payload(g);if payload==nil||clue_index<0||clue_index>=len(payload.clues) do return;target:=&payload.clues[clue_index];for k in 0..<target.prerequisite_count {prerequisite:=target.prerequisites[k];for clue,i in payload.clues do if clue.id==prerequisite&&!mystery_game_clue_discovered(g,i)&&!used[i] {used[i]=true;mark_recovery_prerequisites(g,i,used)}}}
mark_recovery_route :: proc(g:^Game,demo_index,route:int,used:^[16]bool)->bool {
	payload:=mystery_game_payload(g);if demo_index<0 do return true;if payload==nil||demo_index>=len(payload.demonstrations) do return false
	demo:=&payload.demonstrations[demo_index]
	for slot in 0..<demo.route_counts[route] {ref:=mystery_demonstration_route_piece(demo,route,slot);clue_found:=false;for clue,ci in payload.clues do if clue.id==ref {clue_found=true;if !mystery_game_clue_discovered(g,ci)&&!used[ci] {used[ci]=true;mark_recovery_prerequisites(g,ci,used)}};if !clue_found&&!knowledge_piece_known(g,ref)&&mystery_knowledge_piece_type(g,ref)=="deduction" do return false}
	return true
}
begin_proof_overtime :: proc(g:^Game)->bool {
	payload:=mystery_game_payload(g);if payload==nil do return false;bad_luck:=false;for _,i in payload.clues do if mystery_game_clue_attempted(g,i)&&!mystery_game_clue_discovered(g,i)&&payload.clues[i].essential do bad_luck=true
	if !bad_luck do return false
	routes:[3][32][2]int;counts:[3]int
	for pillar in 0..<3 {
		if proof_pillar_attainable(g,payload.solution.culprit_id,pillar) {routes[pillar][0]={-1,-1};counts[pillar]=1;continue}
		wanted:=fmt.tprintf("%s:%s",payload.solution.culprit_id,proof_pillar_name(pillar));for &demo,di in payload.demonstrations {supports:=false;for ri in 0..<demo.result_count {result:=demo.result_deductions[ri];for &deduction in payload.deductions do if deduction.id==result {for si in 0..<deduction.support_count do if deduction.supports[si]==wanted do supports=true}};if supports do for route in 0..<demo.route_count {probe:[16]bool;if mark_recovery_route(g,di,route,&probe)&&counts[pillar]<32 {routes[pillar][counts[pillar]]={di,route};counts[pillar]+=1}}};if counts[pillar]==0 do return false
	}
	best_cost:=1<<20;best_used:[16]bool
	for mi in 0..<counts[0] do for wi in 0..<counts[1] do for oi in 0..<counts[2] {used:[16]bool;chosen:=[3][2]int{routes[0][mi],routes[1][wi],routes[2][oi]};viable:=true;for pair in chosen do if !mark_recovery_route(g,pair[0],pair[1],&used) do viable=false;cost:=0;for selected,i in used do if selected&&i<len(payload.clues) do cost+=payload.clues[i].cost;if viable&&cost<best_cost {best_cost=cost;best_used=used}}
	if best_cost==1<<20 do return false
	mystery_game_clear_overtime_free(g);first:=-1;for free,i in best_used do if free {mystery_game_set_clue_overtime_free(g,i,true);if first<0 do first=i};if first<0 do return false
	g.overtime_clue_plus_one=first+1;g.overtime_lead_plus_one=0;g.investigation_locked=false;g.phase=.Investigation;g.game_over_reason="";if !g.check_from_dialogue do g.screen=.Investigate
	return true
}
next_failure_lead :: proc(g:^Game,clue_index:int)->int {
	payload:=mystery_game_payload(g);if payload==nil||clue_index<0||clue_index>=len(payload.clues) do return -1
	for &candidate,i in payload.clues do if i!=clue_index&&!mystery_game_clue_discovered(g,i)&&!mystery_game_clue_attempted(g,i)&&clues_semantically_related(&payload.clues[clue_index],&candidate) {
		ready:=true;for k in 0..<candidate.prerequisite_count {prerequisite:=candidate.prerequisites[k];found:=false;for known,j in payload.clues do if known.id==prerequisite&&mystery_game_clue_discovered(g,j) do found=true;if !found do ready=false}
		if ready do return i
	}
	return -1
}
begin_overtime :: proc(g:^Game,clue_index:int) {
	g.overtime_clue_plus_one=clue_index+1;lead:=next_failure_lead(g,clue_index);g.overtime_lead_plus_one=lead+1
	g.investigation_locked=false;g.phase=.Investigation;g.game_over_reason="";if !g.check_from_dialogue do g.screen=.Check
	payload:=mystery_game_payload(g);if lead>=0&&payload!=nil {log_line(g,fmt.tprintf("OVERTIME — examine %s. %s Then retry the failed check.",case_sense_source_name(g,lead),payload.clues[lead].description))} else {log_line(g,"OVERTIME — all supporting leads have been pursued. Reconsider the evidence and retry the failed check.")}
}
finish_overtime :: proc(g:^Game) {mystery_game_clear_overtime_free(g);g.overtime_clue_plus_one=0;g.overtime_lead_plus_one=0;g.investigation_locked=true;g.phase=.Reveal_Preparation;g.board_view=0;g.screen=.Board}
overtime_guidance :: proc(g:^Game)->string {lead:=overtime_lead(g);payload:=mystery_game_payload(g);if payload!=nil&&lead>=0&&!mystery_game_clue_discovered(g,lead)&&!mystery_game_clue_attempted(g,lead) do return fmt.tprintf("OVERTIME: examine %s. %s Then retry this check.",case_sense_source_name(g,lead),payload.clues[lead].description);return "OVERTIME: reconsider the gathered evidence and retry this check."}
clue_available :: proc(g:^Game, clue:int)->bool {
	payload:=mystery_game_payload(g);if payload==nil||clue<0||clue>=len(payload.clues) do return false
	if overtime_active(g)&&!clue_is_overtime_action(g,clue) do return false
	if mystery_game_clue_discovered(g,clue) || clue_action_cost(g,clue)>g.ap do return false
	// The statuette conclusion combines two separately authored observations:
	// blood beneath the shifted rug and blood missed inside the polished base
	// seam. Do not let the final wound-match check invent either discovery.
	if payload.clues[clue].source_id=="statuette"&&(!g.study_rug_lifted||!g.study_seam_found) do return false
	// One-shot checks close after an attempt. Retryable checks remain available
	// while the player can afford their tick cost.
	if !clue_is_overtime_action(g,clue)&&mystery_game_clue_attempted(g,clue)&&payload.clues[clue].check_kind=="red" do return false
	for k in 0..<payload.clues[clue].prerequisite_count {prerequisite:=payload.clues[clue].prerequisites[k]
		found:=false
		for known,i in payload.clues do if known.id==prerequisite && mystery_game_clue_discovered(g,i) do found=true
		if !found do return false
	}
	return true
}

clue_source_in_current_room :: proc(g:^Game,clue_index:int)->bool {
	payload:=mystery_game_payload(g);if payload==nil||clue_index<0||clue_index>=len(payload.clues) do return false
	player_room:=world_authored_room_at_point({g.player_x,g.player_y})
	if player_room<0 do return false
	entity:=world_entity_index(payload.clues[clue_index].source_id)
	if entity>=0 {
		source_room:=world_authored_room_at_point({WORLD_ENTITIES[entity].x,WORLD_ENTITIES[entity].y})
		return source_room==player_room
	}
	// Non-spatial sources retain their authored investigative-location fallback.
	location:=world_location_index(g)
	return location>=0&&source_location(g,clue_index)==location
}

case_sense_target :: proc(g:^Game)->(clue_index:int,local:bool) {
	payload:=mystery_game_payload(g);if payload==nil do return -1,false;for _,i in payload.clues do if clue_available(g,i)&&clue_source_in_current_room(g,i) do return i,true
	for _,i in payload.clues do if clue_available(g,i) do return i,false
	return -1,false
}

room_has_available_lead :: proc(g:^Game)->bool {
	payload:=mystery_game_payload(g);if payload!=nil do for _,i in payload.clues do if clue_available(g,i)&&clue_source_in_current_room(g,i) do return true
	return false
}

case_sense_source_name :: proc(g:^Game,clue_index:int)->string {
	payload:=mystery_game_payload(g);if payload==nil||clue_index<0||clue_index>=len(payload.clues) do return "the case"
	source:=payload.clues[clue_index].source_id
	if g.story_project!=nil {index:=story_entity_index(g.story_project,source);if index>=0 do return g.story_project.entities[index].display_name}
	return source
}

vk_draw_case_sense :: proc(r:^Vulkan_Backend,g:^Game) {
	local:=room_has_available_lead(g)
	control:=fmt.tprintf("[%s] ROOM HINT",prompt_label(g,.Room_Hint))
	if g.case_sense_level==0 {status:=local?"MORE TO LEARN HERE":"NOTHING TO SEE HERE";color:=local?[4]u8{255,211,92,255}:[4]u8{117,229,169,225};vk_text(r,20,158,fmt.tprintf("%s  ·  %s",status,control),color,.62);return}
	body:=local?"There is still something to investigate in this room.":"Nothing currently available here; another room may hold a lead."
	body_scale:f32=.74;body_y:=f32(122);body_line_spacing:=f32(4);body_bottom:=body_y+f32(wrapped_line_count(body,372,body_scale))*(f32(COURIER_CELL_HEIGHT)*body_scale+body_line_spacing);footer_y:=body_bottom+4;height:=footer_y+f32(COURIER_CELL_HEIGHT)*.58+9-88
	body_y+=62;footer_y+=62;vulkan_ui_rect(r,18,150,410,height,{14,16,20,222});vulkan_ui_outline(r,18,150,410,height,{116,91,48,210},1);vk_text(r,34,165,"ROOM HINT",{255,211,92,255},.72);_=vk_text_wrapped(r,34,body_y,372,body,{248,247,242,255},body_scale,body_line_spacing);footer:=fmt.tprintf("5 SEC  ·  TAP [%s] TO CLOSE",prompt_label(g,.Room_Hint));vk_text(r,34,footer_y,footer,{205,207,210,255},.58)
}
clues_semantically_related :: proc(target,candidate:^Mystery_Clue)->bool {for i in 0..<target.prerequisite_count do if candidate.id==target.prerequisites[i] do return true;for i in 0..<target.topic_count {for j in 0..<candidate.topic_count do if target.topics[i]==candidate.topics[j] do return true};return false}
relevant_evidence_for_clue :: proc(g:^Game,clue_index:int)->int {payload:=mystery_game_payload(g);if payload==nil||clue_index<0||clue_index>=len(payload.clues) do return -1;if character_index(g,payload.clues[clue_index].source_id)<0 do return -1;for &candidate,i in payload.clues do if i!=clue_index&&mystery_game_clue_discovered(g,i)&&clues_semantically_related(&payload.clues[clue_index],&candidate) do return i;return -1}
present_evidence :: proc(g:^Game,clue_index:int)->bool {payload:=mystery_game_payload(g);if payload==nil||clue_index<0||clue_index>=len(payload.clues)||mystery_game_evidence_presented(g,clue_index) do return false;source:=relevant_evidence_for_clue(g,clue_index);if source<0 do return false;_=mystery_game_mark_evidence_presented(g,clue_index);log_line(g,fmt.tprintf("Evidence presented: %s",mystery_clue_proposition_text(g.story_project,&payload.clues[source])));return true}
clue_situational_bonus :: proc(g:^Game,clue_index:int)->int {if clue_index>=0&&mystery_game_evidence_presented(g,clue_index) do return 10;return 0}
clue_reopen_score :: proc(g:^Game,clue_index:int)->int {score:=clue_evidence_bonus(g,clue_index)+(mystery_game_evidence_presented(g,clue_index)?1:0);payload:=mystery_game_payload(g);if payload!=nil do for &candidate,i in payload.clues do if i!=clue_index&&mystery_game_clue_attempted(g,i)&&!mystery_game_clue_discovered(g,i)&&clues_semantically_related(&payload.clues[clue_index],&candidate) do score+=1;return score}
check_retry_label :: proc(kind:string)->string {return kind=="red"?"ONE-SHOT":"RETRYABLE"}
clue_evidence_bonus :: proc(g:^Game,clue_index:int)->int {
	payload:=mystery_game_payload(g);if payload==nil||clue_index<0||clue_index>=len(payload.clues) do return 0;target:=&payload.clues[clue_index];bonus:=0
	for &candidate,i in payload.clues do if i!=clue_index&&mystery_game_clue_discovered(g,i)&&clues_semantically_related(target,&candidate) do bonus+=1
	return min(bonus,3)
}
clue_locked_label :: proc(g:^Game, clue:int)->string {
	if overtime_active(g)&&!clue_is_overtime_action(g,clue) do return "LOCKED — OVERTIME IS LIMITED TO THE ACTIVE LEAD"
	if clue_action_cost(g,clue)>g.ap do return "LOCKED — NOT ENOUGH TICKS"
	payload:=mystery_game_payload(g);if payload!=nil&&mystery_game_clue_attempted(g,clue) && payload.clues[clue].check_kind=="red" do return "NON-RETRYABLE CHECK EXPIRED"
	if payload!=nil&&clue>=0&&clue<len(payload.clues)&&payload.clues[clue].source_id=="statuette" {
		if !g.study_rug_lifted do return "LOCKED — EXPOSE WHAT THE SHIFTED RUG CONCEALS"
		if !g.study_seam_found do return "LOCKED — FIND THE DETAIL MISSED ON THE POLISHED BRONZE"
	}
	return "LOCKED — NEED PRIOR EVIDENCE"
}
resolve_clue_check :: proc(g:^Game,clue_index:int)->Check_Result {
	payload:=mystery_game_payload(g);if payload==nil||clue_index<0||clue_index>=len(payload.clues)||!clue_available(g,clue_index) do return {}
	clue:=&payload.clues[clue_index];cost:=clue_action_cost(g,clue_index);was_overtime_target:=overtime_active(g)&&clue_index==overtime_clue(g);result:=skill_check(&g.seed,skill_index(clue.skill),clue.difficulty,clue_evidence_bonus(g,clue_index),clue_disposition(g,clue_index),clue_situational_bonus(g,clue_index))
	if g.persist_seed&&!persist_story_seed(g.seed) do fmt.eprintln("warning: could not persist advanced story RNG state")
	g.check_disposition_delta=apply_check_disposition(g,clue_index,result.success)
	mystery_game_mark_clue_attempted(g,clue_index)
	if result.success {
		if clue_is_overtime_action(g,clue_index) {_=discover_clue_free(g,clue_index);mystery_game_set_clue_overtime_free(g,clue_index,false);if proof_framework_attainable(g,payload.solution.culprit_id) do finish_overtime(g)} else {spend(g,clue_index)}
		if clue.source_id=="statuette" {g.study_statuette_held=true;g.study_wound_matched=true;g.study_seam_found=true;g.study_oil_found=true}
		if clue.source_id=="shutter_crank" do g.shutter_thread_found=true
	} else {
		consume_action(g,cost)
		failure_line:=clue.check_kind=="red"?"ONE-SHOT CHECK FAILED — this approach is permanently closed.":"RETRYABLE CHECK FAILED — you may spend another tick to try again."
		log_line(g,failure_line)
		if clue.essential&&g.ap<=0&&!overtime_active(g)&&!proof_framework_attainable(g,payload.solution.culprit_id) {if !begin_proof_overtime(g) do begin_overtime(g,clue_index)}
	}
	if g.pending_dialogue_approach>0 {approach:=g.pending_dialogue_approach-1;if result.success {complete_dialogue_approach(g,approach);_=dialogue_start_dialogue_approach_scene(g,approach)}else do fail_dialogue_approach(g,approach);g.pending_dialogue_approach=0}
	return result
}

dialogue_pointer_focus_id :: proc(g:^Game)->ui.Gui_Id {
	if g.screen!=.Dialogue||g.active_device!=.Keyboard_Mouse||g.dialogue_entity<0||g.dialogue_entity>=len(WORLD_ENTITIES) do return ui.GUI_ID_NONE
	point:=g.input.mouse_pos
	if g.check_from_dialogue {
		if !g.check_done {if contains(dialogue_check_cancel_rect(),point) do return button_id(dialogue_check_cancel_rect());roll:=Rect{650,590,490,42};if contains(roll,point) do return button_id(roll)} else if g.animation_time-g.check_roll_started>=CHECK_REVEAL_DURATION {next:=Rect{650,590,490,42};if contains(next,point) do return button_id(next)}
		return ui.GUI_ID_NONE
	}
	entity:=WORLD_ENTITIES[g.dialogue_entity]
	if entity.source_id=="shutter_crank" {approach:=Rect{650,420,490,58};if contains(approach,point) do return button_id(approach);leave:=dialogue_object_leave_rect();if contains(leave,point) do return button_id(leave);return ui.GUI_ID_NONE}
	if entity.source_id=="pond_reflection" {if contains(reflective_interaction_rect(),point) do return button_id(reflective_interaction_rect());if contains(dialogue_object_leave_rect(),point) do return button_id(dialogue_object_leave_rect());return ui.GUI_ID_NONE}
	if entity.kind=="person" {
		if officer_source(entity.source_id) {if g.end_confirm {for i in 0..<2 {choice:=officer_confirmation_rect(i==1);if contains(choice,point) do return button_id(choice)}} else {choice:=officer_choice_rect(0);if contains(choice,point) do return button_id(choice);if entity.source_id=="officer_lead" {choice=officer_choice_rect(1);if contains(choice,point) do return button_id(choice)};end:=dialogue_end_rect_for(g);if contains(end,point) do return button_id(end)};return ui.GUI_ID_NONE}
		clue:=clue_for_source(g,entity.source_id);view_bottom:=dialogue_response_view_bottom(g,entity.source_id,clue);visible:=dialogue_response_visible_count(g,entity.source_id,clue);for slot in 0..<visible {choice:=dialogue_response_rect(g,entity.source_id,clue,slot);if choice.y<view_bottom&&choice.y+choice.h>dialogue_choices_start_y(g,entity.source_id)&&contains(choice,point) do return button_id(choice)}
		end:=dialogue_end_rect_for(g);if contains(end,point) do return button_id(end)
		return ui.GUI_ID_NONE
	}
	clue:=clue_for_source(g,entity.source_id);approach:=dialogue_object_check_rect(g,clue);if entity.source_id=="dining_room"&&clue>=0&&mystery_game_clue_discovered(g,clue)&&contains(dining_walkthrough_rect(),point) do return button_id(dining_walkthrough_rect());if clue>=0&&!mystery_game_clue_discovered(g,clue)&&clue_available(g,clue)&&contains(approach,point) do return button_id(approach)
	leave:=dialogue_object_leave_rect();if contains(leave,point) do return button_id(leave)
	return ui.GUI_ID_NONE
}
dialogue_overlay_return_focus :: proc(g:^Game)->ui.Gui_Id {pointer_focus:=dialogue_pointer_focus_id(g);return pointer_focus!=ui.GUI_ID_NONE?pointer_focus:g.gui.focused}
open_notebook :: proc(g:^Game) {tutorial_complete(g,.Notebook);g.notebook_return=g.screen;g.notebook_return_focus=dialogue_overlay_return_focus(g);g.screen=.Notebook}
open_attributes :: proc(g:^Game) {g.menu_detail_return=g.screen;g.menu_detail_return_focus=dialogue_overlay_return_focus(g);g.screen=.Attributes}
return_from_menu_overlay :: proc(g:^Game,screen:Screen,focus:ui.Gui_Id) {
	g.screen=screen
	g.menu_overlay_focus_pending=true
	g.menu_overlay_pending_screen=screen
	g.menu_overlay_pending_focus=focus
	// The overlay's gui_end_frame rejects controls which were not registered on
	// that overlay. Restore on the returned screen's next frame instead.
	g.focus_screen_initialized=false
}
dialogue_focus_id_valid :: proc(g:^Game,focus:ui.Gui_Id)->bool {
	if g.story_presentation.active {if !dialogue_ui_interactive(g) do return false;beat:=story_presentation_node(g);if beat==nil do return false;if cinematic_can_leave(g)&&focus==button_id(cinematic_leave_rect(beat)) do return true;if beat.kind==.Choice {pages:=cinematic_choice_page_count(beat);if pages>1&&(focus==button_id(cinematic_choice_prev_rect(g))||focus==button_id(cinematic_choice_next_rect(g))) do return true;visible:=cinematic_choice_visible_count(g,beat);for i in 0..<visible do if focus==button_id(cinematic_choice_rect(g,i)) do return true;return false};if beat.kind==.Interaction do return focus==button_id(dialogue_interaction_action_rect())||focus==button_id(dialogue_interaction_tool_rect())||focus==button_id(dialogue_interaction_leave_rect());return focus==button_id(cinematic_continue_rect(g))}
	if focus==ui.GUI_ID_NONE||g.dialogue_entity<0||g.dialogue_entity>=len(WORLD_ENTITIES) do return false
	if g.check_from_dialogue {
		if !g.check_done do return focus==button_id(Rect{650,590,490,42})||focus==button_id(dialogue_check_cancel_rect())
		settled:=g.animation_time-g.check_roll_started>=CHECK_REVEAL_DURATION
		return settled&&focus==button_id(Rect{650,590,490,42})
	}
	entity:=WORLD_ENTITIES[g.dialogue_entity]
	if entity.source_id=="shutter_crank" do return focus==button_id(Rect{650,420,490,58})||focus==button_id(dialogue_object_leave_rect())
	if entity.source_id=="pond_reflection" do return focus==button_id(reflective_interaction_rect())||focus==button_id(dialogue_object_leave_rect())
	if entity.kind=="person" {
		if officer_source(entity.source_id) {if g.end_confirm do return focus==button_id(officer_confirmation_rect(false))||focus==button_id(officer_confirmation_rect(true));if focus==button_id(officer_choice_rect(0)) do return true;if entity.source_id=="officer_lead"&&focus==button_id(officer_choice_rect(1)) do return true;return focus==button_id(dialogue_end_rect_for(g))}
		clue:=clue_for_source(g,entity.source_id);view_bottom:=dialogue_response_view_bottom(g,entity.source_id,clue);visible:=dialogue_response_visible_count(g,entity.source_id,clue);for slot in 0..<visible {choice:=dialogue_response_rect(g,entity.source_id,clue,slot);if choice.y<view_bottom&&focus==button_id(choice) do return true}
		return focus==button_id(dialogue_end_rect_for(g))
	}
	clue:=clue_for_source(g,entity.source_id);if entity.source_id=="dining_room"&&clue>=0&&mystery_game_clue_discovered(g,clue)&&focus==button_id(dining_walkthrough_rect()) do return true;if clue>=0&&!mystery_game_clue_discovered(g,clue)&&clue_available(g,clue)&&focus==button_id(dialogue_object_check_rect(g,clue)) do return true
	return focus==button_id(dialogue_object_leave_rect())
}
apply_pending_menu_overlay_focus :: proc(g:^Game) {
	if !g.menu_overlay_focus_pending do return
	g.menu_overlay_focus_pending=false
	if g.screen!=g.menu_overlay_pending_screen do return
	focus:=g.menu_overlay_pending_focus
	if g.screen==.Dialogue&&!dialogue_focus_id_valid(g,focus) do focus=button_id(dialogue_default_rect(g))
	if focus!=ui.GUI_ID_NONE {
		g.gui.focused=focus
		g.focus_screen=g.screen
		g.focus_screen_initialized=true
	} else {
		g.focus_screen_initialized=false
	}
}
menu_overlay_back_rect :: proc()->Rect {return {20,650,320,42}}
menu_overlay_back_label :: proc(return_screen:Screen)->string {return return_screen==.Dialogue?"BACK TO CONVERSATION":"BACK"}
menu_overlay_context_label :: proc(return_screen:Screen)->string {return return_screen==.Dialogue?"CONVERSATION PAUSED  ·  BACK RESUMES":""}
theory_has_section :: proc(g:^Game,act:int)->bool {return act>=0&&act<3&&mystery_game_theory_pillar(g,act)!=""}
known_proposition_for_clue :: proc(g:^Game,id:string)->string {payload:=mystery_game_payload(g);if payload!=nil do for &clue,i in payload.clues do if clue.id==id&&knowledge_piece_known(g,id) do return mystery_clue_proposition_text(g.story_project,&clue);return ""}
known_proposition_for_block :: proc(g:^Game,block_id:string)->string {payload:=mystery_game_payload(g);if payload!=nil do for &clue in payload.clues do if knowledge_piece_known(g,clue.id) {for i in 0..<clue.block_count do if clue.blocks[i]==block_id do return mystery_clue_proposition_text(g.story_project,&clue)};return ""}
known_deduction_proposition :: proc(g:^Game,id:string)->string {payload:=mystery_game_payload(g);if payload!=nil do for &deduction in payload.deductions do if deduction.id==id&&knowledge_piece_known(g,id) do return mystery_story_proposition_text(g.story_project,deduction.proposition_id);return ""}
mystery_question_hypothesis_text :: proc(g:^Game,question:^Mystery_Question)->string {
	if question==nil||question.hypothesis_id=="" do return ""
	if g.story_project!=nil&&story_proposition_index(g.story_project,question.hypothesis_id)>=0 do return mystery_story_proposition_text(g.story_project,question.hypothesis_id)
	return question.hypothesis_id
}
reveal_act_lines :: proc(g:^Game,act:int)->(string,string) {
	if act==3 {
		daniel:=knowledge_piece_known(g,"ded_daniel_affair")
		elsie:=knowledge_piece_known(g,"ded_elsie_theft")
		if daniel&&elsie do return "Daniel's false alibi concealed his intended meeting with Miriam, not Edgar's murder.","Elsie denied entering the study because she had stolen sixteen pounds—and her confession places Miriam at the study door."
		if daniel do return "Daniel's false alibi concealed his intended meeting with Miriam, not Edgar's murder.","Elsie's account remains unexplained."
		if elsie do return "Elsie's denial concealed the sixteen pounds she stole, not Edgar's murder.","Daniel's false alibi remains unexplained."
		return "You have not separated the household's other lies from the murder.",""
	}
	if !theory_has_section(g,act) do return "You left this part of the night unexplained.",""
	return known_deduction_proposition(g,mystery_game_theory_pillar(g,act)),""
}
reveal_act_third_line :: proc(g:^Game,act:int)->string {if act==3&&knowledge_piece_known(g,"ded_daniel_affair")&&knowledge_piece_known(g,"ded_elsie_theft") do return "Their secrets explain the smoke around the dinner table. Neither explains the blood in Edgar's study.";return ""}
reveal_act_supported :: proc(g:^Game,act:int)->bool {if act==3 do return knowledge_piece_known(g,"ded_daniel_affair")&&knowledge_piece_known(g,"ded_elsie_theft");first,_:=reveal_act_lines(g,act);return theory_has_section(g,act)&&first!=""&&first!="The accusation outruns the evidence you brought."}
reveal_act_response :: proc(g:^Game,act:int,supported,presented:bool)->string {
	if mystery_game_accusation(g)=="" do return "No suspect stands accused; the room waits in silence."
	if act==3 {
		if !supported do return "Daniel and Elsie both seize on the omissions. The room still has two alternative stories."
		if !presented do return "Two lesser crimes still crowd the accusation. Show the room why they are not Edgar's murder."
		return "Daniel lowers his eyes. Elsie leaves the sixteen pounds on the table. Neither lie can shelter Miriam now."
	}
	if !supported do return "The room catches at the gap. This part of your account cannot hold."
	if !presented {
		switch act {
		case 0:return "Miriam folds her hands. 'A missing sum is a grievance, detective. It is not a murder.'"
		case 1:return "Miriam glances toward the study. 'An object in my husband's room was available to everyone in this house.'"
		case 2:return "'You have made a sequence out of separate untidiness,' Miriam says. 'Sequence is not proof.'"
		}
	}
	switch act {
	case 0:return "Miriam's gaze rests on the circled sums. 'They purchased the only thing Edgar never allowed: an unaccounted-for hour.' It is her first answer that does not correct the question."
	case 1:return "Elsie studies the bronze. 'I polished that seam yesterday. Someone cleaned it again after.' Miriam does not look at her."
	case 2:return "Cane, cloth, terrace, and body lock into order. Daniel stops watching Miriam and starts watching the door."
	}
	return "No answer dislodges what you have shown."
}
board_socket_count :: proc(section:int)->int {counts:=[5]int{1,3,3,1,3};if section<0||section>=len(counts) do return 0;return counts[section]}
board_socket_id :: proc(g:^Game,section,socket:int)->string {payload:=mystery_game_payload(g);if payload==nil do return "";solution:=&payload.solution;switch section {case 0:if socket==0 do return solution.motive_id;case 1:ids:=[3]string{solution.weapon_block,solution.murder_place_block,solution.death_time_block};if socket>=0&&socket<3 do return ids[socket];case 2:ids:=[3]string{solution.body_movement_block,solution.staging_block,solution.cleaning_block};if socket>=0&&socket<3 do return ids[socket];case 3:if socket==0 do return solution.alibi_block;case 4:for &contradiction in payload.contradictions do if contradiction.id==solution.decisive_contradiction_id {if socket==0 do return contradiction.claim_id;if socket==1 do return contradiction.fact_id;if socket==2 {clue_index:=mystery_clue_index(payload,contradiction.fact_id);if clue_index>=0&&payload.clues[clue_index].prerequisite_count>0 do return payload.clues[clue_index].prerequisites[0]}}};return ""}
board_socket_label :: proc(section,socket:int)->string {labels:=[5][3]string{{"MOTIVE / FACT","",""},{"OBJECT / WEAPON","PLACE / SCENE","TIME / WINDOW"},{"ACTION / MOVE","FACT / STAGING","ACTION / CLEAN"},{"CLAIM / ALIBI","",""},{"CLAIM / DENIAL","BURNED FRAGMENT","MEMO STUB"}};if section<0||section>=5||socket<0||socket>=3 do return "SOCKET";return labels[section][socket]}
board_socket_available :: proc(g:^Game,section,socket:int)->bool {id:=board_socket_id(g,section,socket);if id=="" do return false;if section==0||(section==4&&socket>0) do return knowledge_piece_known(g,id);return mystery_game_has_block(g,id)}
board_socket_source :: proc(g:^Game,section,socket:int)->string {id:=board_socket_id(g,section,socket);if section==0||(section==4&&socket>0) do return known_proposition_for_clue(g,id);return known_proposition_for_block(g,id)}
board_source_summary :: proc(value:string)->string {if len(value)<=75 do return value;return fmt.tprintf("%s…",value[:72])}
board_section_available :: proc(g:^Game,section:int)->bool {count:=board_socket_count(section);if count==0 do return false;for socket in 0..<count do if !board_socket_available(g,section,socket) do return false;return true}
board_section_filled :: proc(g:^Game,section:int)->bool {count:=board_socket_count(section);if count==0 do return false;for socket in 0..<count do if !g.board_sockets[section][socket] do return false;return true}
set_theory_section :: proc(g:^Game,section:int,value:bool){if section>=0&&section<3&&!value do mystery_game_set_theory_pillar(g,section,"")}
sync_board_from_theory :: proc(g:^Game){for section in 0..<3 do if theory_has_section(g,section) {for socket in 0..<board_socket_count(section) do g.board_sockets[section][socket]=true}}
sync_theory_from_board :: proc(g:^Game){for section in 0..<3 do set_theory_section(g,section,board_section_filled(g,section))}
clear_board_section :: proc(g:^Game,section:int){if section<0||section>=5 do return;for socket in 0..<3 do g.board_sockets[section][socket]=false;set_theory_section(g,section,false);g.board_clear_confirm=false}
toggle_board_socket :: proc(g:^Game,section,socket:int)->bool {
	if section<0||section>=5||socket<0||socket>=board_socket_count(section) do return false
	g.board_inspect_socket=socket
	if !board_socket_available(g,section,socket) {g.board_feedback="No discovered evidence supports this part of the account yet.";play_sound(g,.Reject);return false}
	g.board_sockets[section][socket]=!g.board_sockets[section][socket]
	g.board_last_section=section;g.board_last_socket=socket;g.board_snap_started=g.animation_time
	g.board_feedback=g.board_sockets[section][socket]?"Evidence placed. The reconstruction gains one supported detail.":"Evidence removed. That detail is open again."
	play_sound(g,g.board_sockets[section][socket]?.Snap:.Pick_Up)
	g.board_clear_confirm=false;sync_theory_from_board(g);g.diagnostics={}
	return true
}
board_source_text :: proc(g:^Game,section:int)->string {
	if !board_section_available(g,section) do return "Discover the evidence for this part of the account first."
	payload:=mystery_game_payload(g);if payload==nil do return "No supporting evidence is available.";solution:=&payload.solution
	switch section {case 0:return known_proposition_for_clue(g,solution.motive_id);case 1:return known_proposition_for_block(g,solution.weapon_block);case 2:return known_proposition_for_block(g,solution.body_movement_block);case 3:return known_proposition_for_block(g,solution.alibi_block);case 4:for contradiction in payload.contradictions do if contradiction.id==solution.decisive_contradiction_id do return contradiction.explanation}
	return "No supporting evidence is available."
}
Readiness_State :: enum {Missing, Unsupported, Supported}
story_event_time_by_id :: proc(project:^Story_Project,id:string)->int {if project!=nil do for event in project.events do if event.id==id do return clock_minutes(event.fictional_time);return -1}
mystery_timeline_order_possible :: proc(g:^Game,order:[3]int)->bool {payload:=mystery_game_payload(g);if payload==nil||payload.solution.cover_up_event_count<3 do return false;seen:[3]bool;previous:=-1;for slot in order {if slot<0||slot>=3||seen[slot] do return false;seen[slot]=true;minutes:=story_event_time_by_id(g.story_project,payload.solution.cover_up_events[slot]);if minutes<0||minutes<previous do return false;previous=minutes};return true}
readiness_state :: proc(g:^Game,section:int)->Readiness_State {if !theory_has_section(g,section) do return .Missing;if !board_section_available(g,section) do return .Unsupported;if section==2&&!mystery_timeline_order_possible(g,g.timeline_order) do return .Unsupported;return .Supported}
readiness_text :: proc(state:Readiness_State)->string {switch state {case .Missing:return "MISSING";case .Unsupported:return "SELECTED / UNSUPPORTED";case .Supported:return "SUPPORTED"};return "MISSING"}
final_category_count :: proc(g:^Game,category:string)->int {count:=0;payload:=mystery_game_payload(g);if payload!=nil do for deduction in payload.deductions do if deduction.category==category&&knowledge_piece_known(g,deduction.id) do count+=1;return count}
exclusion_progress :: proc(g:^Game)->(known,total:int) {payload:=mystery_game_payload(g);if payload==nil do return;total=payload.solution.exclusion_count;for i in 0..<total {suspect:=payload.solution.exclusions[i];if suspect=="daniel"&&knowledge_piece_known(g,"ded_daniel_excluded") {known+=1}else if suspect=="elsie"&&knowledge_piece_known(g,"ded_elsie_theft") {known+=1}};return}
character_display_name :: proc(g:^Game,id:string)->string {if g.story_project!=nil {index:=story_entity_index(g.story_project,id);if index>=0 do return g.story_project.entities[index].display_name};return id}
suspect_id :: proc(g:^Game,index:int)->string {seen:=0;if g.story_project!=nil do for character in g.story_project.entities do if character.kind=="character"&&character.tag_count>0&&character.tags[0]=="suspect" {if seen==index do return character.id;seen+=1};return ""}
suspect_name :: proc(g:^Game,index:int)->string {id:=suspect_id(g,index);if id!="" do return character_display_name(g,id);return "UNKNOWN"}
return_from_board :: proc(g:^Game){if g.investigation_locked do route_locked_investigation(g);else do g.screen=.Investigate}
workbench_event_rect :: proc(index:int)->Rect {return {25+f32(index)*128,485,118,48}}
workbench_room_rect :: proc(index:int)->Rect {return {25+f32(index)*290,145,265,150}}
workbench_selected_figure_rect :: proc(g:^Game)->Rect {if g.workbench_event_count<=0 do return {};event:=g.workbench_events[g.workbench_selected];if event.actor=="someone" do return {};room_index:=-1;for room,i in WORKBENCH_ROOMS do if room==event.room&&i>0 do room_index=i-1;if room_index<0 do return {};return {85+f32(room_index)*290,185,70,92}}
drag_begin :: proc(g:^Game,kind:Drag_Kind,index:int,box:Rect){g.drag={kind=kind,index=index,hover_index=-1,start=g.input.mouse_pos,offset={g.input.mouse_pos.x-box.x,g.input.mouse_pos.y-box.y},origin_screen=g.screen}}
drag_cancel :: proc(g:^Game){g.drag={index=-1,hover_index=-1}}
drag_update_threshold :: proc(g:^Game)->bool {if g.drag.kind==.None do return false;if !g.input.mouse_down&&!g.input.mouse_released {drag_cancel(g);return false};dx:=g.input.mouse_pos.x-g.drag.start.x;dy:=g.input.mouse_pos.y-g.drag.start.y;if !g.drag.active&&dx*dx+dy*dy>=36 {g.drag.active=true;play_sound(g,.Pick_Up)};return g.drag.active}
drag_cancel_if_screen_changed :: proc(g:^Game){if g.drag.kind!=.None&&g.screen!=g.drag.origin_screen do drag_cancel(g)}
workbench_insertion_index :: proc(count:int,x:f32)->int {if count<=0 do return -1;return clamp(int(math.floor(f64((x-25+64)/128))),0,count-1)}
update_workbench_drag :: proc(g:^Game) {
	if g.active_device!=.Keyboard_Mouse {drag_cancel(g);return}
	if g.drag.kind==.None&&g.input.mouse_pressed {
		for i in 0..<g.workbench_event_count {box:=workbench_event_rect(i);if contains(box,g.input.mouse_pos) {g.workbench_selected=i;drag_begin(g,.Event,i,box);return}}
		figure:=workbench_selected_figure_rect(g);if figure.w>0&&contains(figure,g.input.mouse_pos) {drag_begin(g,.Miniature,g.workbench_selected,figure);return}
	}
	if g.drag.kind==.None do return
	if drag_update_threshold(g)&&g.workbench_feedback!="Move along the rail; release over a numbered slot."&&g.workbench_feedback!="Carry the miniature into a highlighted room." do g.workbench_feedback=g.drag.kind==.Event?"Move along the rail; release over a numbered slot.":"Carry the miniature into a highlighted room."
	g.drag.hover_index=-1
	if g.drag.active {if g.drag.kind==.Event {if g.input.mouse_pos.y>=467&&g.input.mouse_pos.y<=551 do g.drag.hover_index=workbench_insertion_index(g.workbench_event_count,g.input.mouse_pos.x)}else{for i in 0..<4 do if contains(workbench_room_rect(i),g.input.mouse_pos) do g.drag.hover_index=i}}
	if !g.input.mouse_released do return
	if g.drag.active&&g.drag.hover_index>=0 {if g.drag.kind==.Event {if !workbench_move_event(g,g.drag.index,g.drag.hover_index) {g.workbench_feedback="The event settles back into the same timeline slot.";play_sound(g,.Pick_Up)}}else{rooms:=[4]string{"dining_room","hall","study","garden"};event:=&g.workbench_events[g.drag.index];if event.room!=rooms[g.drag.hover_index] {workbench_remember(g);event.room=rooms[g.drag.hover_index];g.workbench_test_current=false;sync_theory_from_workbench(g);g.workbench_feedback="Room changed. Test the sequence again to confirm it.";play_sound(g,.Snap)}else{g.workbench_feedback="The miniature returns to its original room.";play_sound(g,.Pick_Up)}}}else if g.drag.active {g.workbench_feedback="Release the piece over a highlighted room or timeline slot.";play_sound(g,.Reject)}
	drag_cancel(g)
}
shutter_clue_index :: proc(g:^Game)->int {
	payload:=mystery_game_payload(g);if payload!=nil do for clue,i in payload.clues do if clue.source_id=="shutter_crank" do return i
	return -1
}

update_shutter_motion :: proc(g:^Game,dt:f32) {
	difference:=g.shutter_target-g.shutter_position
	if math.abs(difference)<.002 {g.shutter_position=g.shutter_target;g.shutter_demonstrating=false;return}
	// Slow start and stop, with a firm minimum travel speed, gives the mechanism weight.
	speed:=clamp(math.abs(difference)*3.6,.34,1.5);g.shutter_position+=clamp(difference,-speed*dt,speed*dt)
}

toggle_shutter_crank :: proc(g:^Game) {
	opening:=g.shutter_target<.5
	g.shutter_target=opening?1:0;g.shutter_open=opening;g.shutter_operated=true
	g.shutter_feedback=opening?"The resistant crank turns as the heavy slats climb through the frame.":"The crank reverses and the heavy shutter descends across the window."
	play_sound(g,.Shutter);play_sound(g,opening?.Door_Open:.Shutter_Close)
}

demonstrate_shutter_folly :: proc(g:^Game) {
	already_demonstrated:=g.shutter_sightline_failed
	if already_demonstrated&&g.shutter_target==0&&g.shutter_position>.002 {
		g.shutter_feedback="The shutter is still falling. Let the demonstration finish."
		return
	}
	g.shutter_view=0;g.shutter_time=2;g.shutter_open=false;g.shutter_operated=true
	// Start open so the automatic fall itself makes the failed sightline visible.
	g.shutter_position=1;g.shutter_target=0;g.shutter_sightline_failed=true;g.shutter_demonstrating=true
	learn_observation(g,4,false);learn_observation(g,5,false);learn_observation(g,6,false)
	play_sound(g,.Shutter);play_sound(g,.Shutter_Close);play_sound(g,.Decisive_Clue)
	g.shutter_feedback=already_demonstrated?"The shutter repeats its automatic fall, sealing the study window from the dining room.":"The shutter falls across the study window. From the dining room, the closed slats hide the glass completely."
}

lift_study_rug :: proc(g:^Game) {
	if g.study_rug_lifted {context_feedback(g,"BLOOD AND WATCH-GLASS EXPOSED",.Complete,"study_rug");return}
	g.study_rug_lifted=true;learn_observation(g,0)
	message:="The rug peels back with a wet drag. Beside the diluted blood, a wrist-width scuff in the varnish holds tiny watch-glass fragments."
	log_line(g,message);context_feedback(g,"BLOOD AND WATCH-GLASS EXPOSED",.Complete,"study_rug");play_sound(g,.Pick_Up)
}
