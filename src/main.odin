package main

import "core:crypto"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sys/posix"
import "core:thread"
import "core:time"
import sdl "vendor:sdl3"
import ui "zelda_engine:ui"

contains :: proc(r: Rect, p: Vec2) -> bool {return(
		p.x >= r.x &&
		p.x <= r.x + r.w &&
		p.y >= r.y &&
		p.y <= r.y + r.h \
	)}
WINDOW_WIDTH :: 1200
WINDOW_HEIGHT :: 720
FIXED_TIMESTEP :: 1.0 / 60.0
MAX_FRAME_TIME :: 0.25
MAX_FIXED_STEPS_PER_FRAME :: 8
APP_STORAGE_NAME :: "Zelda's Storytelling Game"
APP_LOCAL_STORAGE_DIR :: ".zeldas-storytelling-game"

mouse_to_logical :: proc(x, y: f32, window_width, window_height: i32) -> Vec2 {
	if window_width <= 0 || window_height <= 0 do return {x, y}
	return {x * f32(WINDOW_WIDTH) / f32(window_width), y * f32(WINDOW_HEIGHT) / f32(window_height)}
}

window_mouse_to_logical :: proc(window: ^sdl.Window, x, y: f32) -> Vec2 {
	width, height: i32
	if !sdl.GetWindowSize(window, &width, &height) do return {x, y}
	return mouse_to_logical(x, y, width, height)
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

utf8_next_index :: proc(value: string, index: int) -> int {
	if index < 0 || index >= len(value) do return len(value)
	lead := value[index]; width := 1
	if lead & 0xE0 == 0xC0 do width = 2
	else if lead & 0xF0 == 0xE0 do width = 3
	else if lead & 0xF8 == 0xF0 do width = 4
	return min(index + width, len(value))
}

utf8_glyph_count :: proc(value: string) -> int {count, cursor := 0, 0; for cursor <
	    len(value) {cursor = utf8_next_index(value, cursor); count += 1}
	return count}
Text_Layout_Line :: struct {
	start, end, glyph_offset: int,
}
Text_Layout_Word :: struct {
	start, end, columns: int,
}
Text_Layout_Badness :: struct {
	total, raggedness, orphan: f32,
	lines:                     int,
}

text_layout_plan :: proc(value: string, max_columns: int) -> [dynamic]Text_Layout_Line {
	lines := make([dynamic]Text_Layout_Line, 0, 8, context.temp_allocator)
	if value == "" do return lines
	paragraph_start, glyph_offset := 0, 0
	for paragraph_start < len(value) {
		paragraph_end :=
			paragraph_start; for paragraph_end < len(value) && value[paragraph_end] != '\n' do paragraph_end = utf8_next_index(value, paragraph_end)
		words := make(
			[dynamic]Text_Layout_Word,
			0,
			16,
			context.temp_allocator,
		); cursor := paragraph_start
		for cursor < paragraph_end {
			for cursor < paragraph_end && value[cursor] == ' ' {cursor += 1; glyph_offset += 1}
			if cursor >= paragraph_end do break
			word_start, word_columns := cursor, 0
			for cursor < paragraph_end &&
			    value[cursor] != ' ' {cursor = utf8_next_index(value, cursor); word_columns += 1}
			if word_columns > max_columns { 	// Preserve hard wrapping for identifiers and other unbroken text.
				chunk_start, chunk_columns := word_start, 0
				for chunk_start <
				    cursor {chunk_end := chunk_start; chunk_columns = 0; for chunk_end < cursor && chunk_columns < max_columns {chunk_end = utf8_next_index(value, chunk_end); chunk_columns += 1}; append(&words, Text_Layout_Word{chunk_start, chunk_end, chunk_columns}); chunk_start = chunk_end}
			} else {append(&words, Text_Layout_Word{word_start, cursor, word_columns})}
		}
		if len(words) ==
		   0 {append(&lines, Text_Layout_Line{paragraph_start, paragraph_start, glyph_offset})} else {
			cost := make(
				[]f32,
				len(words) + 1,
				context.temp_allocator,
			); next := make([]int, len(words), context.temp_allocator); cost[len(words)] = 0
			for reverse in 0 ..< len(
				words,
			) {i := len(words) - 1 - reverse; cost[i] = f32(1e20); for j in i ..< len(words) {columns := utf8_glyph_count(value[words[i].start:words[j].end]); if columns > max_columns do break; unused := f32(max_columns - columns) / f32(max_columns); line_cost := unused * unused * unused; if j == len(words) - 1 {line_cost = 0; if i == j && i > 0 do line_cost = 1}; candidate := line_cost + cost[j + 1]; if candidate < cost[i] {cost[i] = candidate; next[i] = j + 1}}}
			for i := 0;
			    i < len(words);
			    i =
				    next[i] {j := next[i] - 1; append(&lines, Text_Layout_Line{words[i].start, words[j].end, glyph_offset}); glyph_offset += utf8_glyph_count(value[words[i].start:words[j].end]); if next[i] < len(words) do glyph_offset += utf8_glyph_count(value[words[j].end:words[next[i]].start])}
		}
		if paragraph_end >= len(value) do break
		paragraph_start = paragraph_end + 1
	}
	return lines
}

text_layout_columns :: proc(max_width, advance: f32) -> int {return max(
		int(max_width / max(advance, .001)),
		1,
	)}
wrapped_line_count :: proc(value: string, max_width, scale: f32) -> int {if value == "" do return 1
	return len(
		text_layout_plan(value, text_layout_columns(max_width, f32(COURIER_CELL_WIDTH) * scale)),
	)}

text_layout_badness :: proc(value: string, max_width, scale: f32) -> Text_Layout_Badness {
	if value == "" do return {lines = 1}
	columns := text_layout_columns(
		max_width,
		f32(COURIER_CELL_WIDTH) * scale,
	); plan := text_layout_plan(value, columns); result := Text_Layout_Badness {
		lines = len(plan),
	}; scored := 0
	for line, i in plan {last :=
			i == len(plan) - 1 || (line.end < len(value) && value[line.end] == '\n')
		if last do continue
		used := utf8_glyph_count(value[line.start:line.end])
		unused := f32(max(columns - used, 0)) / f32(columns)
		result.raggedness += unused * unused * unused
		scored += 1}
	if scored > 0 do result.raggedness /= f32(scored)
	for line, i in plan do if i > 0 && strings.index_byte(value[line.start:line.end], ' ') < 0 {previous := plan[i - 1]; if previous.end >= len(value) || value[previous.end] != '\n' do result.orphan = 1}
	result.total = result.raggedness + result.orphan; return result
}

random_story_seed :: proc() -> u64 {
	seed: u64
	for seed == 0 {
		entropy: [8]byte
		crypto.rand_bytes(entropy[:])
		for value in entropy do seed = (seed << 8) | u64(value)
	}
	return seed
}

story_seed_path_for :: proc(storage_name: string) -> (string, bool) {
	data_dir, data_error := os.user_data_dir(context.temp_allocator)
	if data_error != nil do return "", false
	save_dir, join_error := os.join_path([]string{data_dir, storage_name}, context.temp_allocator)
	if join_error != nil do return "", false
	if os.make_directory_all(save_dir) != nil do return "", false
	path, path_error := os.join_path([]string{save_dir, "story-seed.bin"}, context.temp_allocator)
	return path, path_error == nil
}
story_seed_path :: proc() -> (string, bool) {return story_seed_path_for(APP_STORAGE_NAME)}

local_persistence_path_for :: proc(filename, dirname: string) -> (string, bool) {
	base, base_error := os.get_executable_directory(context.temp_allocator)
	if base_error !=
	   nil {base, base_error = os.get_working_directory(context.temp_allocator); if base_error != nil do return "", false}
	dir, dir_error := os.join_path([]string{base, dirname}, context.temp_allocator)
	if dir_error != nil || os.make_directory_all(dir) != nil {
		base, base_error = os.get_working_directory(
			context.temp_allocator,
		); if base_error != nil do return "", false
		dir, dir_error = os.join_path(
			[]string{base, dirname},
			context.temp_allocator,
		); if dir_error != nil || os.make_directory_all(dir) != nil do return "", false
	}
	path, path_error := os.join_path(
		[]string{dir, filename},
		context.temp_allocator,
	); return path, path_error == nil
}
local_persistence_path :: proc(
	filename: string,
) -> (
	string,
	bool,
) {return local_persistence_path_for(filename, APP_LOCAL_STORAGE_DIR)}

write_with_local_fallback :: proc(primary_path, filename: string, data: []u8) -> bool {
	if primary_path != "" && os.write_entire_file(primary_path, data) == nil do return true
	fallback, ok := local_persistence_path(
		filename,
	); return ok && os.write_entire_file(fallback, data) == nil
}

read_with_local_fallback :: proc(primary_path, filename: string) -> ([]byte, bool) {
	if primary_path !=
	   "" {data, err := os.read_entire_file_from_path(primary_path, context.temp_allocator); if err == nil do return data, true}
	fallback, ok := local_persistence_path(
		filename,
	); if ok {data, err := os.read_entire_file_from_path(fallback, context.temp_allocator); if err == nil do return data, true}
	return nil, false
}

User_Config :: struct {
	anti_aliasing:    Anti_Aliasing_Mode,
	lighting_quality: Lighting_Quality,
	guidance:         Guidance_Mode,
	mute:             bool,
}
lighting_quality_from_text :: proc(text: string) -> Lighting_Quality {if strings.contains(text, "lighting_quality=low") do return .Low
	if strings.contains(text, "lighting_quality=medium") do return .Medium
	if strings.contains(text, "lighting_quality=ultra") do return .Ultra
	return .High}
guidance_mode_from_text :: proc(text: string) -> Guidance_Mode {if strings.contains(text, "guidance=full") do return .Full
	if strings.contains(text, "guidance=minimal") do return .Minimal
	return .Adaptive}

user_config_path_for :: proc(storage_name: string) -> (string, bool) {
	config_dir, config_error := os.user_config_dir(
		context.temp_allocator,
	); if config_error != nil do return "", false
	app_dir, join_error := os.join_path(
		[]string{config_dir, storage_name},
		context.temp_allocator,
	); if join_error != nil || os.make_directory_all(app_dir) != nil do return "", false
	path, path_error := os.join_path(
		[]string{app_dir, "options.cfg"},
		context.temp_allocator,
	); return path, path_error == nil
}
user_config_path :: proc() -> (string, bool) {return user_config_path_for(APP_STORAGE_NAME)}

load_user_config :: proc() -> User_Config {
	config := User_Config {
		lighting_quality = .High,
		guidance         = .Adaptive,
	}; path, _ := user_config_path(

	); data, ok := read_with_local_fallback(path, "options.cfg"); if !ok do return config; text := string(data)
	if strings.contains(
		text,
		"anti_aliasing=msaa_2x",
	) {config.anti_aliasing = .MSAA_2X} else if strings.contains(text, "anti_aliasing=msaa_4x") {config.anti_aliasing = .MSAA_4X} else if strings.contains(text, "anti_aliasing=fxaa") {config.anti_aliasing = .FXAA}
	config.lighting_quality = lighting_quality_from_text(text)
	config.guidance = guidance_mode_from_text(text)
	config.mute = strings.contains(text, "mute=true"); return config
}

save_user_config :: proc(config: User_Config) -> bool {
	path, _ := user_config_path(

	); aa := "none"; switch config.anti_aliasing {case .None:; case .MSAA_2X:
		aa = "msaa_2x"; case .MSAA_4X:
		aa = "msaa_4x"; case .FXAA:
		aa = "fxaa"}
	quality := "high"; switch config.lighting_quality {case .Low:
		quality = "low"; case .Medium:
		quality = "medium"; case .High:; case .Ultra:
		quality = "ultra"}
	guidance := "adaptive"; switch config.guidance {case .Full:
		guidance = "full"; case .Adaptive:; case .Minimal:
		guidance = "minimal"}
	contents := fmt.tprintf(
		"anti_aliasing=%s\nlighting_quality=%s\nguidance=%s\nmute=%v\n",
		aa,
		quality,
		guidance,
		config.mute,
	); return write_with_local_fallback(path, "options.cfg", transmute([]u8)contents)
}

persist_game_options :: proc(g: ^Game) {if !save_user_config({anti_aliasing = g.aa_mode, lighting_quality = g.lighting_quality, guidance = g.guidance_mode, mute = g.mute}) do fmt.eprintln("warning: could not save user options")}
anti_aliasing_label :: proc(mode: Anti_Aliasing_Mode) -> string {switch mode {case .None:
		return "OFF"; case .MSAA_2X:
		return "2X MSAA"; case .MSAA_4X:
		return "4X MSAA"; case .FXAA:
		return "FXAA"}; return "OFF"}

persist_story_seed :: proc(seed: u64) -> bool {
	path, _ := story_seed_path()
	encoded: [8]byte; value := seed
	for i := 7; i >= 0; i -= 1 {encoded[i] = byte(value & 0xff); value >>= 8}
	return write_with_local_fallback(path, "story-seed.bin", encoded[:])
}

load_or_create_story_seed :: proc() -> u64 {
	path, _ := story_seed_path()
	encoded, read_ok := read_with_local_fallback(
		path,
		"story-seed.bin",
	); if read_ok && len(encoded) == 8 {seed: u64; for value in encoded do seed = (seed << 8) | u64(value); if seed != 0 do return seed}
	seed := random_story_seed(

	); if !persist_story_seed(seed) do fmt.eprintln("warning: could not persist story RNG state"); return seed
}

begin_new_story_seed :: proc() -> u64 {
	seed := random_story_seed(

	); if !persist_story_seed(seed) do fmt.eprintln("warning: could not persist story RNG state"); return seed
}

content_sized_button_rect :: proc(
	box: Rect,
	label: string,
	anchor := Horizontal_Anchor.Left,
	scale: f32 = 1.25,
	padding_x: f32 = 12,
) -> Rect {
	result := box
	result.w = f32(utf8_glyph_count(label)) * f32(COURIER_CELL_WIDTH) * scale + padding_x * 2
	if anchor == .Right do result.x = box.x + box.w - result.w
	return result
}

anti_aliasing_from_args :: proc() -> (Anti_Aliasing_Mode, bool) {
	for argument in os.args {switch argument {case "--aa=off":
			return .None, true; case "--aa=2x", "--msaa=2":
			return .MSAA_2X, true; case "--aa=4x", "--msaa=4":
			return .MSAA_4X, true; case "--aa=fxaa", "--fxaa":
			return .FXAA, true; case:}}
	return .None, false
}

self_test_thread :: proc(_: ^thread.Thread) {
	run_self_tests()
}

run_self_tests_with_large_stack :: proc() {
	// The acceptance suite intentionally keeps several complete Game fixtures in
	// one procedure. Run it on a dedicated stack so growth of the production Game
	// state cannot silently turn a valid assertion suite into a main-stack crash.
	previous: posix.rlimit
	if posix.getrlimit(.STACK, &previous) == nil {
		desired := previous
		desired.rlim_cur = posix.rlim_t(64 * 1024 * 1024)
		if desired.rlim_max != posix.RLIM_INFINITY && desired.rlim_cur > desired.rlim_max do desired.rlim_cur = desired.rlim_max
		_ = posix.setrlimit(.STACK, &desired)
	}
	worker := thread.create(self_test_thread)
	assert(worker != nil)
	if previous.rlim_cur > 0 do _ = posix.setrlimit(.STACK, &previous)
	thread.start(worker)
	thread.join(worker)
	thread.destroy(worker)
}

player_package_mode: bool
player_package_forced: bool
active_authoring_project: Authoring_Project
active_authoring_ready: bool
active_authoring_read_only: bool

argument_value :: proc(prefix: string) -> string {
	for argument in os.args do if strings.has_prefix(argument, prefix) do return argument[len(prefix):]
	return ""
}

parse_vec3_argument :: proc(value: string) -> (Vec3, bool) {
	parts, _ := strings.split(
		value,
		",",
		context.temp_allocator,
	); if len(parts) != 3 do return {}, false
	x, x_ok := strconv.parse_f32(
		strings.trim_space(parts[0]),
	); y, y_ok := strconv.parse_f32(strings.trim_space(parts[1])); z, z_ok := strconv.parse_f32(strings.trim_space(parts[2]))
	return {x, y, z}, x_ok && y_ok && z_ok
}

capture_wall_view_from_text :: proc(value: string) -> (House_Wall_View, bool) {
	switch strings.to_lower(strings.trim_space(value)) {case "auto", "automatic":
		return .Automatic, true; case "up", "full":
		return .Walls_Up, true; case "down", "cutaway":
		return .Walls_Down, true; case:}
	return .Automatic, false
}

capture_fixture_marker :: proc(
	doc: ^Level_Document,
	id: string,
	kind: Level_Marker_Kind,
) -> (
	^Level_Marker,
	bool,
) {
	index := level_marker_index(doc, id)
	if index <
	   0 {fmt.eprintln("capture fixture is missing authored marker: ", id); return nil, false}
	marker := &doc.markers[index]
	if marker.kind !=
	   kind {fmt.eprintln("capture fixture marker has wrong kind: ", id); return nil, false}
	return marker, true
}

capture_fixture_pose :: proc(g: ^Game, doc: ^Level_Document, id: string) -> bool {
	staging, staging_ok := capture_fixture_marker(
		doc,
		fmt.tprintf("capture_%s_staging", id),
		.Staging,
	); if !staging_ok do return false
	camera, camera_ok := capture_fixture_marker(
		doc,
		fmt.tprintf("capture_%s_camera", id),
		.Camera,
	); if !camera_ok do return false
	g.player_x =
		staging.position.x; g.player_y = staging.position.y; g.player_angle = staging.facing * f32(math.PI) / 180
	g.camera_x =
		camera.position.x; g.camera_y = camera.position.y; g.camera_initialized = true; g.camera_orbit = camera.facing * f32(math.PI) / 180; g.camera_orbit_initialized = true
	if camera.camera_height > 0 do g.camera_zoom = camera.camera_height
	return true
}

capture_fixture_camera_override :: proc(g: ^Game, doc: ^Level_Document, id: string) -> bool {
	staging, staging_ok := capture_fixture_marker(
		doc,
		fmt.tprintf("capture_%s_staging", id),
		.Staging,
	); if !staging_ok do return false
	camera, camera_ok := capture_fixture_marker(
		doc,
		fmt.tprintf("capture_%s_camera", id),
		.Camera,
	); if !camera_ok do return false
	g.player_x =
		staging.position.x; g.player_y = staging.position.y; g.player_angle = staging.facing * f32(math.PI) / 180
	g.camera_pose_override = true
	g.camera_eye_override = {camera.position.x, camera.camera_height, camera.position.y}
	g.camera_target_override = {staging.position.x, 0, staging.position.y}
	g.camera_initialized = true; g.camera_orbit_initialized = true
	return true
}

capture_fixture_entity :: proc(id: string) -> (int, bool) {
	index := world_entity_index(
		id,
	); if index < 0 {fmt.eprintln("capture fixture is missing authored entity: ", id); return -1, false}; return index, true
}

capture_fixture_interactive :: proc(g: ^Game, id: string) -> (int, bool) {
	index := runtime_interactive_index(
		g,
		id,
	); if index < 0 {fmt.eprintln("capture fixture is missing authored interactive: ", id); return -1, false}; return index, true
}

main :: proc() {
	story_domains_initialize()
	if len(os.args) > 1 && os.args[1] == "--agent-object-transaction" do os.exit(agent_object_transaction(os.args[2:]))
	if len(os.args) > 2 && os.args[1] == "--agent-level-validate" do os.exit(agent_level_validate(os.args[2]))
	if len(os.args) > 1 && os.args[1] == "--scenario-test" do os.exit(scenario_cli(os.args[2:]))
	if len(os.args) > 1 && os.args[1] == "--campaign-scenario-test" do os.exit(campaign_scenario_cli())
	if len(os.args) > 1 &&
	   os.args[1] ==
		   "--authoring-acceptance" {result := run_authoring_acceptance(".", len(os.args) > 2 && os.args[2] == "--keep-root"); if !result.ok {fmt.eprintln(result.phase, ": ", result.message, " (", result.assertions, " assertions)"); os.exit(2)}; fmt.println(result.message, " (", result.assertions, " assertions)"); return}
	if len(os.args) > 1 &&
	   os.args[1] ==
		   "--story-core-test" {run_story_core_tests(); fmt.println("interactive story core checks passed"); return}
	if len(os.args) > 2 &&
	   os.args[1] ==
		   "--validate-story" {project: Story_Project; checked := load_story_project(os.args[2], &project); if !checked.ok {fmt.eprintln(checked.message); os.exit(2)}; defer story_project_destroy(&project); compiled := compile_story_project(&project); defer story_compile_result_destroy(&compiled); if !compiled.ok {fmt.eprintln(compiled.message); os.exit(2)}; fmt.println("INTERACTIVE STORY VALID"); return}
	if len(os.args) > 2 &&
	   os.args[1] ==
		   "--graph-roundtrip-story" {source: Story_Project; loaded := load_story_project(os.args[2], &source); if !loaded.ok {fmt.eprintln(loaded.message); os.exit(2)}; defer story_project_destroy(&source); graph_import_story(&source); rebuilt: Story_Project; built := graph_build_story_project(&source, &rebuilt); if !built.ok {fmt.eprintln(built.message); os.exit(3)}; defer story_project_destroy(&rebuilt); before := compile_story_project(&source); after := compile_story_project(&rebuilt); defer story_compile_result_destroy(&before); defer story_compile_result_destroy(&after); if !before.ok || !after.ok || before.story.content_identity != after.story.content_identity {fmt.eprintln("graph round-trip changed story semantics"); os.exit(4)}; fmt.println("GRAPH ROUNDTRIP SEMANTICS PRESERVED"); return}
	city_data := city_data_initialize(); if !city_data.ok {fmt.eprintln(city_data.message); return}
	if len(os.args) > 1 &&
	   os.args[1] ==
		   "--vehicle-self-test" {run_vehicle_self_tests(); fmt.println("vehicle physics checks passed"); return}
	if len(os.args) > 1 && os.args[1] == "--self-test" {run_self_tests_with_large_stack(); return}
	if len(os.args) > 2 &&
	   os.args[1] ==
		   "--validate-campaign" {doc: Campaign_Definition; checked := load_campaign_manifest(os.args[2], &doc); if !checked.ok {fmt.eprintln(checked.message); os.exit(2)}; fmt.println("CAMPAIGN VALID"); return}
	level_path := argument_value(
		"--level=",
	); if level_path == "" do level_path = LEVEL_DEFAULT_PATH
	story_path := argument_value(
		"--story=",
	); if story_path == "" do story_path = "assets/stories/mysteries/the_torn_appointment.story.toml"
	LEVEL_DEFAULT_PATH =
		level_path; player_package_mode = argument_value("--player-package") != ""; if !player_package_mode {for value in os.args do if value == "--player-package" do player_package_mode = true}; player_package_forced = player_package_mode
	campaign_initialize(

	); if campaign_validation := campaign_validate(&campaign_document); !campaign_validation.ok {fmt.eprintln(campaign_validation.message); return}
	if initialized := authoring_app_initialize(story_path, level_path);
	   !initialized.ok {fmt.eprintln(initialized.message); return}
	if active_authoring_ready do _ = catalog_asset_overrides_load(active_authoring_project.root_path, &editor_catalog)
	argument :=
		len(os.args) > 1 ? os.args[1] : ""; world_preview := argument == "--world-preview"; city_preview := argument == "--city-preview"; capture_mode := strings.has_prefix(argument, "--capture-")
	loaded_story := load_story_project(
		story_path,
		&active_story_project,
	); if !loaded_story.ok {fmt.eprintln(loaded_story.message); return}; defer story_project_destroy(&active_story_project)
	payload := mystery_payload(&active_story_project)
	graph_import_story(&active_story_project)
	graph_autosave_enabled = !player_package_mode
	for fallback, i in CHARACTER_MESH_PATHS {path := fallback
		if i > 0 &&
		   payload != nil &&
		   i - 1 <
			   len(
				   payload.characters,
			   ) {if owned, ok := story_entity_appearance_path(&active_story_project, &authoring_workspace.assets, payload.characters[i - 1].entity_id); ok && os.is_file(owned) do path = owned}
		ok: bool
		character_meshes[i], ok = glb_load(path)
		if !ok && path != fallback do character_meshes[i], ok = glb_load(fallback)
		if !ok {fmt.eprintln("failed to load required animated character rig: ", path); return}}
	for object in level_document.objects {for &entry in editor_catalog.entries do if entry.id == object.catalog_id {if path, ok := level_object_model_path(&level_document, &authoring_workspace.assets, object.id); ok && os.is_file(path) {entry.model = path; entry.model_asset_ref = object.model_asset_ref}; if path, ok := level_object_material_path(&level_document, &authoring_workspace.assets, object.id); ok && os.is_file(path) {texture := load_room_texture(path); if len(texture.pixels) > 0 do entry.material_asset_ref = object.material_asset_ref}; if path, ok := level_object_texture_path(&level_document, &authoring_workspace.assets, object.id); ok && os.is_file(path) {texture := load_room_texture(path); if len(texture.pixels) > 0 do entry.texture_asset_ref = object.texture_asset_ref}; break}}
	if !load_furniture_meshes(

	) {fmt.eprintln("failed to load one or more required case-prop meshes"); return}; load_city_meshes()
	when ODIN_OS == .Darwin {if _, err := os.stat("/opt/homebrew/lib/libvulkan.1.dylib", context.temp_allocator); err == nil do _ = os.set_env("SDL_VULKAN_LIBRARY", "/opt/homebrew/lib/libvulkan.1.dylib")}
	if capture_mode {
		// NOT_FOCUSABLE protects the window itself; these hints also stop SDL's
		// macOS bootstrap and window-show path from activating the process.
		_ = sdl.SetHint(sdl.HINT_MAC_BACKGROUND_APP, "1")
		_ = sdl.SetHint(sdl.HINT_WINDOW_ACTIVATE_WHEN_SHOWN, "0")
		_ = sdl.SetHint(sdl.HINT_WINDOW_ACTIVATE_WHEN_RAISED, "0")
	}
	if !sdl.Init(
		{.VIDEO, .AUDIO, .EVENTS, .GAMEPAD},
	) {fmt.eprintln(sdl.GetError()); return}; defer sdl.Quit()
	window_flags: sdl.WindowFlags = {.VULKAN, .RESIZABLE, .HIGH_PIXEL_DENSITY}
	// Automated captures only need a presentable Vulkan surface. Prevent their
	// short-lived windows from taking keyboard focus from the user's active app.
	if capture_mode do window_flags += {.NOT_FOCUSABLE}
	window := sdl.CreateWindow(
		"Zelda's Storytelling Game",
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		window_flags,
	); if window == nil {fmt.eprintln(sdl.GetError()); return}; defer sdl.DestroyWindow(window)
	if !capture_mode {_ = sdl.StartTextInput(window); defer _ = sdl.StopTextInput(window)}
	when ODIN_OS == .Darwin {if !capture_mode do chicago_editor_menu_install()}
	user_config := load_user_config(

	); aa_override, has_aa_override := anti_aliasing_from_args(); startup_aa := has_aa_override ? aa_override : user_config.anti_aliasing
	// Ending captures validate authored result layout and copy. Keep that
	// deterministic and independent of the player's saved post-process mode.
	if argument == "--capture-ending" do startup_aa = .None
	backend: Vulkan_Backend; if !vulkan_backend_init(&backend, window, startup_aa) {fmt.eprintln("Vulkan game backend initialization failed; run make shaders"); return}; defer vulkan_backend_destroy(&backend)
	story_seed :=
		capture_mode ? u64(1) : load_or_create_story_seed(); action_budget := 0; if payload != nil {if capture_mode do story_seed = payload.seed; action_budget = payload.action_budget}
	g := Game {
		running                              = true,
		screen                               = .Campaign,
		phase                                = .Introduction,
		ap                                   = action_budget,
		seed                                 = story_seed,
		run_seed                             = story_seed,
		persist_seed                         = !capture_mode,
		mute                                 = user_config.mute,
		aa_mode                              = user_config.anti_aliasing,
		lighting_quality                     = user_config.lighting_quality,
		pending_clue                         = -1,
		active_ending                        = -1,
		board_last_section                   = -1,
		board_last_socket                    = -1,
		timeline_order                       = {0, 1, 2},
		player_x                             = 3.5,
		player_y                             = 12.5,
		camera_x                             = 3.5,
		camera_y                             = 12.5,
		camera_initialized                   = true,
		camera_orbit                         = math.PI / 4,
		camera_zoom                          = 1,
		camera_orbit_initialized             = true,
		catalog_bake_index                   = -1,
		catalog_thumbnail_autoload_attempted = capture_mode,
		pending_world_interaction            = -1,
		pending_interactive                  = -1,
		hover_interactive                    = -1,
		near_interactive                     = -1,
		auto_door                            = -1,
		hover_entity                         = -1,
		near_entity                          = -1,
		dialogue_entity                      = -1,
		near_landmark                        = -1,
		driving_vehicle                      = -1,
		near_vehicle                         = -1,
		active_device                        = .Keyboard_Mouse,
	}
	compiled_story := compile_story_project(
		&active_story_project,
	); if !compiled_story.ok {fmt.eprintln("story compilation failed"); return}; active_compiled_story = compiled_story.story; defer compiled_story_destroy(&active_compiled_story)
	spatial_level: Level_Document; if loaded := level_load(level_path, &spatial_level); !loaded.ok {fmt.eprintln(loaded.message); return}; world_entities_result := world_entities_rebuild(&active_story_project, &spatial_level); if !world_entities_result.ok {fmt.eprintln(world_entities_result.message); return}; defer delete(WORLD_ENTITIES); assert(story_spatial_registry_register(&active_spatial_registry, story_level_space(&spatial_level))); _ = story_spatial_registry_register(&active_spatial_registry, story_city_space()); defer story_spatial_registry_destroy(&active_spatial_registry); active_spatial_service = story_spatial_registry_service(&active_spatial_registry)
	spatial_validation := story_spatial_validate_project(
		&active_story_project,
		&active_spatial_registry,
	); if !spatial_validation.ok {for diagnostic in spatial_validation.diagnostics do fmt.eprintln(diagnostic.message); story_validation_destroy(&spatial_validation); return}; story_validation_destroy(&spatial_validation)
	active_story_runtime = story_runtime_new(
		&active_compiled_story,
		&active_spatial_service,
	); defer story_runtime_destroy(&active_story_runtime)
	g.story_project = &active_story_project; g.story_state = &active_story_runtime.state; g.compiled_story = &active_compiled_story; g.story_runtime = &active_story_runtime; g.mystery_state = cast(^Mystery_State)story_runtime_capability_state(&active_story_runtime, "mystery", MYSTERY_DOMAIN_VERSION); g.spatial_service = &active_spatial_service
	g.guidance_mode = user_config.guidance; g.tutorial.guidance = user_config.guidance
	// Every deterministic capture begins from an authored pose. Captures that need
	// a distinct composition resolve a more specific fixture below.
	if capture_mode && !capture_fixture_pose(&g, &level_document, "default") do return
	audio_spec := sdl.AudioSpec {
		format   = .F32,
		channels = 1,
		freq     = 44100,
	}; g.audio_stream = sdl.OpenAudioDeviceStream(
		sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK,
		&audio_spec,
		nil,
		nil,
	); if g.audio_stream != nil do _ = sdl.ResumeAudioStreamDevice(g.audio_stream); defer if g.audio_stream != nil do sdl.DestroyAudioStream(g.audio_stream); g.vehicle_audio_stream = sdl.OpenAudioDeviceStream(sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK, &audio_spec, nil, nil); if g.vehicle_audio_stream != nil do _ = sdl.ResumeAudioStreamDevice(g.vehicle_audio_stream); defer if g.vehicle_audio_stream != nil do sdl.DestroyAudioStream(g.vehicle_audio_stream); loaded_sounds := load_sound_assets(&g); if loaded_sounds != len(g.sounds) do fmt.eprintln("warning: loaded ", loaded_sounds, " of ", len(g.sounds), " OGG cues; missing cues use procedural fallback"); defer destroy_sound_assets(&g)
	initialize_city_vehicles(
		&g,
	); initialize_dispositions(&g); initialize_character_animations(&g); if world_preview {g.screen = .Investigate; _ = apply_player_spawn_marker(&g)}; if city_preview && payload != nil {g.screen = .Exterior; _ = city_place_at_landmark(&g, payload.city_start)}
	if capture_mode do capture_configure_authoring(&g, argument)
	if capture_mode &&
	   (argument == "--capture-graph" ||
			   argument == "--capture-graph-minimap-stress" ||
			   argument == "--capture-graph-routing-board" ||
			   argument == "--capture-graph-routing-crossings" ||
			   argument == "--capture-graph-quick-add" ||
			   argument == "--capture-graph-script" ||
			   argument == "--capture-graph-localization" ||
			   argument == "--capture-graph-diagnostics" ||
			   argument == "--capture-graph-inspector-edit" ||
			   argument == "--capture-graph-edge-drag" ||
			   argument == "--capture-graph-paste" ||
			   argument ==
				   "--capture-graph-debugger") {g.screen = .Investigate; g.editor_mode = .Graph; if argument == "--capture-graph-routing-board" || argument == "--capture-graph-routing-crossings" do graph_configure_routing_test_board(); if argument == "--capture-graph-minimap-stress" do graph_configure_minimap_stress_board(); graph_state.active_scene = argument == "--capture-graph-routing-crossings" ? 1 : 0; graph_select_only(graph_document.node_count > 0 ? (graph_state.active_scene == 1 ? 11 : 0) : -1); if argument == "--capture-graph-quick-add" {graph_state.quick_add = true; graph_state.quick_add_at = {540, 210}} else if argument == "--capture-graph-script" do graph_state.view = .Script
		else if argument == "--capture-graph-localization" do graph_state.view = .Localization
		else if argument == "--capture-graph-diagnostics" {if graph_document.node_count > 0 do graph_document.nodes[0].beat.next = "missing_capture_target"; _ = graph_validate(&graph_document)} else if argument == "--capture-graph-inspector-edit" && graph_state.selected_node >= 0 do graph_begin_edit(.Text, graph_document.nodes[graph_state.selected_node].beat.text, graph_state.selected_node, true)
		else if argument == "--capture-graph-edge-drag" && graph_state.selected_node >= 0 {node := graph_document.nodes[graph_state.selected_node]; graph_state.edge_drag = {
				active       = true,
				node         = graph_state.selected_node,
				port         = .Next,
				choice_index = -1,
				start        = {node.position.x + graph_state.pan.x + 190, node.position.y + graph_state.pan.y + 46},
			}; g.input.mouse_pos = {700, 410}} else if argument == "--capture-graph-paste" {if graph_copy_selection() do _ = graph_paste_clipboard({650, 420})} else if argument == "--capture-graph-debugger" do _ = graph_begin_playtest(&g)}
	if capture_mode &&
	   argument ==
		   "--capture-graph-routing-crossing-hover" {g.screen = .Investigate; g.editor_mode = .Graph; graph_configure_routing_test_board(); graph_state.active_scene = 1; graph_select_only(11); g.input.mouse_pos = {583, 269}}
	if capture_mode &&
	   argument ==
		   "--capture-graph-routing-parallel-hover" {g.screen = .Investigate; g.editor_mode = .Graph; graph_configure_routing_test_board(); graph_state.active_scene = 1; graph_select_only(15)}
	if capture_mode &&
	   argument ==
		   "--capture-graph-routing-zoomed-hover" {g.screen = .Investigate; g.editor_mode = .Graph; graph_configure_routing_test_board(); graph_state.active_scene = 1; graph_select_only(11); _ = graph_frame_nodes(); canvas := graph_canvas_rect(); center := graph_screen_to_world({canvas.x + canvas.w * .5, canvas.y + canvas.h * .5}); graph_state.zoom = .55; graph_state.pan = {canvas.x + (canvas.w * .5 - canvas.x) / graph_state.zoom - center.x, canvas.y + (canvas.h * .5 - canvas.y) / graph_state.zoom - center.y}}
	if capture_mode && argument == "--capture-graph-debugger" do graph_state.debugger.page = 1
	if capture_mode &&
	   (argument == "--capture-graph-routing-direct-hover" ||
			   argument == "--capture-graph-routing-obstacle-hover" ||
			   argument ==
				   "--capture-graph-routing-back-hover") {g.screen = .Investigate; g.editor_mode = .Graph; graph_configure_routing_test_board(); graph_state.active_scene = 0; graph_select_only(argument == "--capture-graph-routing-obstacle-hover" ? 2 : argument == "--capture-graph-routing-back-hover" ? 5 : 0)}
	if capture_mode &&
	   argument ==
		   "--capture-graph-choice" {g.screen = .Investigate; g.editor_mode = .Graph; graph_configure_routing_test_board(); graph_state.active_scene = 1; graph_select_only(15)}
	if capture_mode &&
	   argument ==
		   "--capture-graph-conditions" {g.screen = .Investigate; g.editor_mode = .Graph; graph_state.view = .Conditions; if graph_document.condition_count > 0 {graph_state.selected_condition = 0; item := &graph_document.conditions[0]; item.kind = .Spatial_Distance; item.spatial_a = {"vale_house", "detective"}; item.spatial_b = {"vale_house", "study_desk"}; item.distance = 3.5}}
	if capture_mode &&
	   argument ==
		   "--capture-graph-effects" {g.screen = .Investigate; g.editor_mode = .Graph; graph_state.view = .Effects; if graph_document.effect_count > 0 {graph_state.selected_effect = 0; item := &graph_document.effects[0]; item.kind = .Set_Value; item.variable_id = "trust_miriam"; item.value = story_value_integer(2)}}
	if capture_mode &&
	   argument ==
		   "--capture-graph-help" {g.screen = .Investigate; g.editor_mode = .Graph; graph_state.help_visible = true}
	if capture_mode &&
	   argument == "--capture-graph-localization" &&
	   graph_document.node_count > 0 &&
	   graph_document.localization_count == 0 {graph_document.localizations[0] = {
			node_id  = graph_document.nodes[0].beat.id,
			language = "fr",
			text     = "Une traduction de la première réplique.",
			status   = "review",
			note     = "Needs final context pass",
			voice    = "vo/fr/arrival_001.ogg",
		}; graph_document.localizations[1] = {
			node_id  = graph_document.nodes[0].beat.id,
			language = "de",
			status   = "draft",
		}; graph_document.localization_count = 2; graph_state.selected_localization = 0}
	if capture_mode &&
	   (argument == "--capture-graph-picker" ||
			   argument == "--capture-graph-marquee" ||
			   argument ==
				   "--capture-graph-edge-selection") {g.screen = .Investigate; g.editor_mode = .Graph; graph_state.active_scene = 0; graph_select_only(graph_document.node_count > 0 ? 0 : -1); if argument == "--capture-graph-picker" && graph_state.selected_node >= 0 do graph_begin_picker(.Speaker, "", graph_state.selected_node)
		else if argument == "--capture-graph-marquee" do graph_state.marquee = {
			active  = true,
			start   = {280, 120},
			current = {820, 430},
		}
		else if argument == "--capture-graph-edge-selection" && graph_state.selected_node >= 0 do graph_state.edge_selection = {
			active       = true,
			node         = graph_state.selected_node,
			port         = .Next,
			choice_index = -1,
		}}
	if argument ==
	   "--capture-catalog-thumbnail" {if len(os.args) < 3 {fmt.eprintln("catalog thumbnail capture requires a catalog ID"); return}; requested := os.args[2]; for entry, i in editor_catalog.entries do if entry.id == requested && entry.kind == .Object do g.catalog_bake_index = i; if g.catalog_bake_index < 0 {fmt.eprintln("unknown object catalog ID: ", requested); return}}
	if capture_mode {switch argument {case "--capture-options":
			g.screen = .Options; case "--capture-city":
			g.screen = .Exterior
			_ = city_place_at_landmark(&g, payload.city_start); case "--capture-driving":
			g.screen = .Exterior; g.driving_vehicle = 0; g.city_x = g.vehicles[0].x
			g.city_y = g.vehicles[0].y
			g.city_angle = g.vehicles[0].heading; case "--capture-world":
			g.screen = .Investigate; case "--capture-characters":
			g.screen = .Investigate; g.camera_zoom = .58; g.wall_view = .Walls_Down
			g.cutaway_transition = 1
			for &amount in g.wall_cutaways do amount = 1; case "--capture-dialogue":
			g.screen = .Dialogue; g.dialogue_entity = world_entity_index("miriam")
			trigger_character_interact(&g, "miriam")
			g.character_animations[1].transition = .5
			g.character_animations[1].next_time = .125; case "--capture-environment-card":
			g.screen = .Dialogue
			g.dialogue_entity = world_entity_index("edgar_watch"); case "--capture-check":
			g.screen = .Dialogue; g.dialogue_entity = world_entity_index("ledger")
			g.pending_clue = mystery_clue_index(payload, "clue_ledger")
			g.check_from_dialogue = true
			g.check_preview = check_target(
				payload.clues[g.pending_clue].difficulty,
			); case "--capture-shutter":
			g.screen = .Investigate; g.shutter_time = 2; g.shutter_view = 0
			g.shutter_feedback = "The dining-room sightline is ready to test."; case "--capture-study":
			g.screen = .Investigate; g.study_rug_lifted = true; g.study_statuette_held = true
			g.study_wound_matched = true
			g.study_seam_found = true
			g.study_oil_found = true; case "--capture-dinner":
			g.screen = .Dialogue
			g.dialogue_entity = world_entity_index(
				game_entity_id_with_tag(&g, "dining_walkthrough"),
			); case "--capture-notebook", "--capture-dialogue-notebook", "--capture-objectives":
			g.screen = .Notebook; case "--capture-board":
			g.screen = .Board; case "--capture-recreate":
			g.screen = .Recreate; g.recreate_section = 1; g.theory.murder = true
			mystery_game_mark_all_clues(&g)
			g.board_sockets[1] = {true, true, true}; case "--capture-cover-up-recreate":
			g.screen = .Recreate; g.recreate_section = 2; g.theory.cover_up = true
			mystery_game_mark_all_clues(&g)
			g.board_sockets[2] = {true, true, true}; case "--capture-alibi-recreate":
			g.screen = .Recreate; g.recreate_section = 3; g.theory.alibi = true
			mystery_game_mark_all_clues(&g)
			g.board_sockets[3][0] =
				true; case "--capture-proof-recreate", "--capture-shutter-recreate":
			g.screen = .Recreate; g.recreate_section = 4; g.theory.proof = true
			mystery_game_mark_all_clues(&g)
			g.board_sockets[4] = {true, true, true}; case "--capture-reveal-prep":
			g.screen = .Reveal_Prep; case "--capture-reveal", "--capture-reveal-other-lies":
			g.screen = .Reveal; case "--capture-result":
			g.screen = .Result
			g.result = mystery_evaluate_outcome(
				&active_story_project,
				g.mystery_state,
			); case "--capture-diagnostics":
			g.screen = .Diagnostics; case:}}
	if capture_mode &&
	   (argument == "--capture-world" ||
			   argument ==
				   "--capture-objectives") {_ = game_story_milestone(&g, "city.briefing_received"); _ = game_story_milestone(&g, "city.case_destination_entered"); if argument == "--capture-objectives" do g.notebook_tab = 4}
	if capture_mode &&
	   argument ==
		   "--capture-quest-complete" {g.screen = .Investigate; _ = game_story_milestone(&g, "city.briefing_received"); _ = game_story_milestone(&g, "city.case_destination_entered"); _ = game_story_milestone(&g, "investigation.question_opened"); _ = game_story_milestone(&g, "investigation.explanation_ready"); quest_tracker_sync(&g); _ = game_story_milestone(&g, "investigation.conclusion_presented"); _ = dialogue_start_source_scene(&g, "officer_lead"); g.quest_completion_pending = true; g.quest_completion_started = g.animation_time}
	if capture_mode &&
	   argument ==
		   "--capture-driving" {v := &g.vehicles[0]; v.heading = f32(math.PI / 2); v.speed = .38; v.velocity_x = .13; v.velocity_y = .35; v.steering = .42; v.yaw_rate = .014; v.chassis_lateral_acceleration = .55; v.chassis_acceleration = -.45; v.body_roll = vehicle_body_roll_target(v^, false, vehicle_tune(0)); v.body_pitch = vehicle_body_pitch_target(v.chassis_acceleration, vehicle_tune(0)); v.traction_state = vehicle_traction_state(v^); v.impact = .12; g.city_angle = v.heading; g.vehicle_camera_follow_distance = 6.1; g.keys[.S] = true; for i in 0 ..< 6 {g.vehicle_skid_marks[i] = {
				position = {
					g.city_x + (i % 2 == 0 ? f32(-.34) : f32(.34)),
					g.city_y - 1.2 - f32(i / 2) * .72,
				},
				heading  = v.heading,
				age      = f32(i / 2) * .35,
				strength = .72,
				active   = true,
			}}}
	if capture_mode &&
	   argument ==
		   "--capture-city-border" {g.screen = .Exterior; g.city_x = city_world(82); g.city_y = city_world(.55); g.city_angle = -f32(math.PI) / 2; g.city_camera_x = g.city_x; g.city_camera_y = g.city_y; g.city_camera_initialized = true; g.camera_orbit_initialized = true}
	context_capture :=
		argument == "--capture-context-person" ||
		argument == "--capture-context-evidence" ||
		argument == "--capture-context-door" ||
		argument == "--capture-context-locked" ||
		argument == "--capture-context-multiple" ||
		argument == "--capture-context-xbox" ||
		argument == "--capture-context-playstation" ||
		argument == "--capture-context-switch" ||
		argument == "--capture-context-orbit"
	if capture_mode &&
	   argument ==
		   "--capture-shutter" {g.screen = .Investigate; if !capture_fixture_pose(&g, &level_document, "shutter") do return; g.first_person_camera = true; g.shutter_time = 2; g.shutter_open = false; g.shutter_position = 0; g.shutter_target = 0; runtime_interactives_rebuild(&g); shutter_id := game_entity_id_with_tag(&g, "shutter_mechanism"); sightline, ok := capture_fixture_interactive(&g, shutter_id); if !ok do return; g.context_ui.current = context_runtime_target(&g, sightline); g.context_ui.focus_started = -1}
	if capture_mode &&
	   argument ==
		   "--capture-characters" {g.character_studio = true; if !capture_fixture_pose(&g, &level_document, "characters") do return}
	if capture_mode &&
	   context_capture {g.screen = .Investigate; if !capture_fixture_pose(&g, &level_document, "context") do return; if argument == "--capture-context-orbit" {orbit, ok := capture_fixture_marker(&level_document, "capture_context_orbit_camera", .Camera); if !ok do return; g.camera_orbit = orbit.facing * f32(math.PI) / 180}; runtime_interactives_rebuild(&g); target_id := "miriam"; if argument == "--capture-context-evidence" do target_id = "ledger"; entity, ok := capture_fixture_entity(target_id); if !ok do return; target := context_entity_target(&g, entity); if argument == "--capture-context-door" || argument == "--capture-context-locked" {door, found := capture_fixture_interactive(&g, "study_door"); if !found do return; if argument == "--capture-context-locked" do g.interactives[door].locked = true; target = context_runtime_target(&g, door)}; g.context_ui.current = target; g.context_ui.focus_started = -1; if argument == "--capture-context-xbox" || argument == "--capture-context-playstation" || argument == "--capture-context-switch" {g.active_device = .Gamepad; if argument == "--capture-context-playstation" do g.gamepad_type = .PS5
			else if argument == "--capture-context-switch" do g.gamepad_type = .NINTENDO_SWITCH_PRO}}
	if capture_mode &&
	   argument ==
		   "--capture-context-idle" {g.screen = .Investigate; g.context_ui.current = {}; g.context_ui.location_changed_at = -10}
	if capture_mode &&
	   (argument == "--capture-officer" ||
			   argument ==
				   "--capture-officer-confirm") {g.screen = .Dialogue; if !capture_fixture_pose(&g, &level_document, "officer") do return; _, ok := capture_fixture_entity("officer_lead"); if !ok do return; g.active_device = .Keyboard_Mouse; if !dialogue_start_source_scene(&g, "officer_lead") do return; if argument == "--capture-officer-confirm" {_ = dialogue_goto(&g, "officer_lead_confirm")}; dialogue_focus_default(&g)}
	if capture_mode &&
	   (argument == "--capture-context-landmark" ||
			   argument ==
				   "--capture-context-vehicle") {g.screen = .Exterior; g.city_camera_initialized = true; if argument == "--capture-context-landmark" {g.city_x = city_world(18.5); g.city_y = city_world(20.2); g.city_camera_x = g.city_x; g.city_camera_y = g.city_y; g.near_landmark = 0} else {g.city_x = g.vehicles[0].x; g.city_y = g.vehicles[0].y + 1; g.city_camera_x = g.city_x; g.city_camera_y = g.city_y; g.near_vehicle = 0}; context_resolve_city(&g); g.context_ui.focus_started = -1}
	if capture_mode &&
	   argument ==
		   "--capture-dialogue-notebook" {g.notebook_return = .Dialogue; g.dialogue_entity = world_entity_index("miriam"); _ = learn_initial_claims(&g, "miriam"); g.notebook_tab = 1; g.notebook_return_focus = button_id(dialogue_default_rect(&g)); g.active_device = .Keyboard_Mouse}
	if capture_mode &&
	   argument ==
		   "--capture-game-over" {g.screen = .Game_Over; g.game_over_reason = "Time expired before a complete reconstruction was prepared."}
	if capture_mode &&
	   argument == "--capture-pause" {g.pause_return = .Investigate; g.screen = .Pause}
	if capture_mode &&
	   argument == "--capture-floorplan" {g.screen = .Investigate; g.camera_initialized = true}
	if capture_mode &&
	   argument ==
		   "--capture-topdown-floorplan" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true}
	if capture_mode &&
	   (argument == "--capture-build" ||
			   argument == "--capture-build-drag" ||
			   argument == "--capture-build-catalog" ||
			   argument == "--capture-build-placement" ||
			   argument == "--capture-build-materials" ||
			   argument == "--capture-build-wall-paint" ||
			   argument == "--capture-build-room-draw" ||
			   argument ==
				   "--capture-build-room-rectangle") {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; if argument == "--capture-build-catalog" {g.build_tool = .Plant; editor_state.catalog_category = "objects"} else if argument == "--capture-build-placement" {g.build_tool = .Plant; editor_state.catalog_category = "objects"; editor_state.catalog_id = "sofa"; editor_state.placement_active = true; editor_state.placement_position = {10, 7}; editor_state.placement_rotation = 30; editor_state.placement_preview = level_preview_transaction(&level_document, Level_Command{kind = .Place_Object, a = editor_state.placement_position, value = editor_state.placement_rotation, material = editor_state.catalog_id})} else if argument == "--capture-build-materials" {g.build_tool = .Paint; editor_state.catalog_category = "materials"; editor_state.catalog_id = "study"; hover := level_pick(&level_document, {4, 8}); if hover.kind == .Room {editor_state.paint_hover = hover; editor_state.paint_hover_active = true}} else if argument == "--capture-build-wall-paint" {g.build_tool = .Wall_Paint; editor_state.catalog_category = "materials"; editor_state.catalog_id = "dining"; hover := level_pick(&level_document, {4, 8}); if hover.kind == .Room {editor_state.paint_hover = hover; editor_state.paint_hover_active = true; room_index := level_room_index(&level_document, hover.entity_id); if room_index >= 0 {level_document.rooms[room_index].wall_material = "dining"; level_project_runtime(&level_document)}}} else if argument == "--capture-build-room-draw" {g.build_tool = .Room; editor_state.room_mode = .Polygon; editor_state.room_draw_count = 5; editor_state.room_draw_points[0] = {4, 4}; editor_state.room_draw_points[1] = {8, 4}; editor_state.room_draw_points[2] = {9.5, 6.5}; editor_state.room_draw_points[3] = {7, 9}; editor_state.room_draw_points[4] = {4, 8}; draw_cursor, _ := editor_world_screen(&g, {4, 4}); g.input.mouse_pos = draw_cursor} else if argument == "--capture-build-room-rectangle" {g.build_tool = .Room; editor_state.room_mode = .Rectangle; editor_state.room_rectangle_active = true; editor_state.room_rectangle_start = {9, 5}; editor_state.room_rectangle_current = {15, 10}; editor_state.room_rectangle_preview = level_preview_transaction(&level_document, Level_Command{kind = .Create_Room, a = editor_state.room_rectangle_start, b = editor_state.room_rectangle_current, material = "wood"}); g.input.mouse_pos, _ = editor_world_screen(&g, editor_state.room_rectangle_current)} else if len(level_document.rooms) > 0 {editor_state.selection[0] = {.Room, level_document.rooms[0].id, -1}; editor_state.selection_count = 1; if argument == "--capture-build-drag" {editor_state.drag_active = true; editor_state.drag_selection = editor_state.selection[0]; editor_state.drag_delta = {1.25, .75}; command, _ := level_selection_move_command(&level_document, editor_state.drag_selection, editor_state.drag_delta); editor_state.drag_preview = level_preview_transaction(&level_document, command)}}}
	if capture_mode &&
	   argument ==
		   "--capture-build-wall-paint" {g.build_tool = .Paint; editor_state.paint_target = .Walls}
	if capture_mode &&
	   argument ==
		   "--capture-build-eyedropper" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Paint; editor_state.catalog_category = "materials"; editor_state.paint_target = .Walls; editor_state.paint_eyedropper = true; hover := level_pick(&level_document, {4, 8}); if hover.kind == .Room {editor_state.paint_hover = hover; editor_state.paint_hover_active = true}; g.input.mouse_pos, _ = editor_world_screen(&g, {4, 8})}
	if capture_mode &&
	   argument ==
		   "--capture-build-terrain" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = false; g.editor_mode = .Build; g.build_tool = .Terrain; editor_state.terrain_mode = .Smooth; editor_state.terrain_radius = 1; editor_state.terrain_strength = .75; _, _ = level_apply_raw(&level_document, Level_Command{kind = .Sculpt_Terrain, a = {10, 8}, b = {14, 10}, c = {1.5, 0}, value = 1, brush = .Raise}); rebuild_generated_ground(&level_document); editor_state.terrain_stroke_active = true; editor_state.terrain_stroke_start = {10, 8}; editor_state.terrain_stroke_current = {14, 10}; g.input.mouse_pos, _ = editor_world_screen(&g, editor_state.terrain_stroke_current)}
	if capture_mode &&
	   (argument == "--capture-build-foundation" ||
			   argument ==
				   "--capture-build-foundation-limit") {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = false; g.editor_mode = .Build; g.build_tool = .Foundation; editor_state.foundation_kind = .Raised; editor_state.foundation_elevation = argument == "--capture-build-foundation-limit" ? .25 : .5; editor_state.foundation_depth = .5; editor_state.foundation_rectangle_active = true; editor_state.foundation_rectangle_start = {9, 7}; editor_state.foundation_rectangle_current = {15, 11}; command := Level_Command {
			kind        = .Create_Foundation,
			value       = .5,
			c           = {f32(Level_Foundation_Kind.Raised), .5},
			point_count = 4,
		}; command.points[0] = {
			9,
			7,
		}; command.points[1] = {15, 7}; command.points[2] = {15, 11}; command.points[3] = {9, 11}; editor_state.foundation_rectangle_preview = level_preview_transaction(&level_document, command); g.input.mouse_pos, _ = editor_world_screen(&g, editor_state.foundation_rectangle_current)}
	if capture_mode &&
	   argument ==
		   "--capture-build-foundation-polygon" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Foundation; editor_state.foundation_kind = .Basement; editor_state.foundation_mode = .Polygon; editor_state.foundation_depth = 2.75; editor_state.foundation_draw_count = 6; editor_state.foundation_draw_points[0] = {9, 5}; editor_state.foundation_draw_points[1] = {15, 5}; editor_state.foundation_draw_points[2] = {15, 7}; editor_state.foundation_draw_points[3] = {12, 7}; editor_state.foundation_draw_points[4] = {12, 11}; editor_state.foundation_draw_points[5] = {9, 11}; editor_state.foundation_polygon_preview = {.Valid, "CLICK FIRST POINT OR ENTER TO CLOSE", {}, {}}; g.input.mouse_pos, _ = editor_world_screen(&g, editor_state.foundation_draw_points[0])}
	if capture_mode &&
	   argument ==
		   "--capture-build-foundation-shell" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Room; points := make([dynamic]Vec2, 0, 6); append(&points, Vec2{16, 9}, Vec2{22, 9}, Vec2{22, 11}, Vec2{19, 11}, Vec2{19, 14}, Vec2{16, 14}); append(&level_document.foundations, Level_Foundation{id = "capture_shell_foundation", kind = .Raised, story = -1, points = points, elevation = .75, depth = .25}); rebuild_generated_stories(&level_document); editor_state.selection[0] = {.Foundation, "capture_shell_foundation", -1}; editor_state.selection_count = 1; origin, ok := editor_selection_toolbar_origin(&g); if ok do g.input.mouse_pos = {origin.x + 18, origin.y + 13}}
	if capture_mode &&
	   argument ==
		   "--capture-build-foundation-point-drag" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Select; points := make([dynamic]Vec2, 0, 6); append(&points, Vec2{8, 5}, Vec2{14, 5}, Vec2{14, 8}, Vec2{11, 8}, Vec2{11, 12}, Vec2{8, 12}); append(&level_document.foundations, Level_Foundation{id = "capture_edit_foundation", kind = .Raised, story = -1, points = points, elevation = .75, depth = .25}); rebuild_generated_stories(&level_document); editor_state.selection[0] = {.Foundation, "capture_edit_foundation", -3}; editor_state.selection_count = 1; editor_state.drag_active = true; editor_state.drag_selection = editor_state.selection[0]; editor_state.drag_delta = {1, .5}; command, ok := level_selection_move_command(&level_document, editor_state.drag_selection, editor_state.drag_delta); if ok do editor_state.drag_preview = level_preview_transaction(&level_document, command)}
	if capture_mode &&
	   argument ==
		   "--capture-build-room-split" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Wall; g.build_anchor = {0, 10}; g.build_has_anchor = true; editor_state.wall_preview_point = {8, 10}; editor_state.wall_preview_active = true}
	if capture_mode &&
	   argument ==
		   "--capture-build-room-merge" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Select; command, split := level_wall_command(&level_document, {0, 10}, {8, 10}); if split {_, ok := level_apply_raw(&level_document, command); if ok {level_document.revision += 1; level_project_runtime(&level_document); editor_state.selection[0] = {.Room, command.entity_id, -1}; editor_state.selection[1] = {.Room, command.destination, -1}; editor_state.selection_count = 2}}; g.input.mouse_pos = {776, 622}}
	if capture_mode &&
	   argument ==
		   "--capture-build-opening" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Window; host := Editor_Selection{.Path, "shell", 0}; command, ok := level_opening_command_at(&level_document, host, {6, 0}, .Window); if ok {editor_state.opening_active = true; editor_state.opening_host = host; editor_state.opening_command = command; editor_state.opening_preview = level_preview_transaction(&level_document, command); editor_state.opening_position = editor_state.opening_preview.bounds_min}}
	if capture_mode &&
	   (argument == "--capture-build-window-selected" ||
			   argument == "--capture-build-window-drag" ||
			   argument ==
				   "--capture-build-window-edit") {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Select; for opening in level_document.openings {if opening.kind == .Window {editor_state.selection[0] = {.Opening, opening.id, opening.segment}; editor_state.selection_count = 1; if argument == "--capture-build-window-drag" {editor_state.drag_active = true; editor_state.drag_selection = editor_state.selection[0]; path_index := level_path_index(&level_document, opening.host_path); if path_index >= 0 && opening.segment >= 0 && opening.segment < len(level_document.paths[path_index].points) - 1 {a, b := level_document.paths[path_index].points[opening.segment], level_document.paths[path_index].points[opening.segment + 1]; dx, dy := b.x - a.x, b.y - a.y; length := f32(math.sqrt(f64(dx * dx + dy * dy))); if length > .001 {editor_state.drag_delta = {dx / length * .75, dy / length * .75}; command, ok := level_selection_move_command(&level_document, editor_state.drag_selection, editor_state.drag_delta); if ok do editor_state.drag_preview = level_preview_transaction(&level_document, command)}}} else if argument == "--capture-build-window-edit" {editor_begin_numeric_edit(.Opening_Width, opening.width); g.input.mouse_pos = {1062, 249}}; break}}}
	if capture_mode &&
	   argument ==
		   "--capture-build-roof" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = false; g.editor_mode = .Build; g.build_tool = .Roof; editor_state.roof_style = .Gable; editor_state.roof_pitch = 30; editor_state.roof_overhang = .4; editor_state.roof_gutters = true; if len(level_document.rooms) > 0 {room := level_document.rooms[0]; existing := level_roof_for_room(&level_document, room.id); if existing < 0 do append(&level_document.roofs, Level_Roof{id = "capture_roof", room_id = room.id, story = room.story, style = .Gable, pitch = 30, overhang = .4, ridge_angle = 45, gutters = true})
			else do level_document.roofs[existing].gutters = true; rebuild_generated_roofs(&level_document); editor_state.roof_hover = {.Room, room.id, -1}; editor_state.roof_hover_active = true; editor_state.roof_preview = {.Valid, "READY", {}, {}}}}
	if capture_mode &&
	   (argument == "--capture-build-roof-selected" ||
			   argument ==
				   "--capture-build-roof-numeric") {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = false; g.editor_mode = .Build; g.build_tool = .Select; editor_set_view(&g, .Roof); if len(level_document.rooms) > 0 {room := level_document.rooms[0]; existing := level_roof_for_room(&level_document, room.id); if existing < 0 {append(&level_document.roofs, Level_Roof{id = "capture_roof_selected", room_id = room.id, story = room.story, style = .Gable, pitch = 35, overhang = .45, ridge_angle = 45, gutters = true}); existing = len(level_document.roofs) - 1}; rebuild_generated_roofs(&level_document); editor_state.selection[0] = {.Roof, level_document.roofs[existing].id, -1}; editor_state.selection_count = 1; if argument == "--capture-build-roof-numeric" {editor_begin_numeric_edit(.Roof_Pitch, level_document.roofs[existing].pitch); editor_state.numeric_replace_on_input = false; g.input.mouse_pos = {1060, 188}} else do g.input.mouse_pos = {1060, 330}}}
	if capture_mode &&
	   argument ==
		   "--capture-build-mansard" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = false; g.editor_mode = .Build; g.build_tool = .Roof; editor_state.roof_style = .Mansard; editor_state.roof_pitch = 65; editor_state.roof_overhang = .35; if len(level_document.rooms) > 0 {room := level_document.rooms[0]; clear(&level_document.roofs); append(&level_document.roofs, Level_Roof{id = "capture_mansard", room_id = room.id, story = room.story, style = .Mansard, pitch = 65, overhang = .35}); rebuild_generated_roofs(&level_document); editor_state.roof_hover = {.Room, room.id, -1}; editor_state.roof_hover_active = true; editor_state.roof_preview = {.Valid, "MANSARD WITH DORMERS", {}, {}}}}
	if capture_mode &&
	   argument ==
		   "--capture-roof-overhead" {g.screen = .Investigate; garden_index := level_room_index(&level_document, "moon_garden"); center := garden_index >= 0 ? level_room_center(&level_document.rooms[garden_index]) : Vec2{20, 16}; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Roof; editor_set_view(&g, .Top_Down); editor_state.selection_count = 0; editor_state.roof_hover_active = false; rebuild_generated_roofs(&level_document)}
	if capture_mode &&
	   argument ==
		   "--capture-build-stairs" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = false; g.editor_mode = .Build; g.build_tool = .Stairs; editor_state.link_kind = .Stairs; editor_state.link_width = 1; if len(level_document.stories) < 2 do append(&level_document.stories, Level_Story{"capture_upper", "Upper", 3, 2.5}); append(&level_document.vertical_links, Level_Vertical_Link{id = "capture_stairs", kind = .Stairs, from_story = 0, to_story = 1, start = {9, 6}, finish = {13, 10}, width = 1}); rebuild_generated_links(&level_document); editor_state.link_anchor_active = true; editor_state.link_anchor = {9, 6}; editor_state.link_finish = {13, 10}; editor_state.link_preview = level_preview_transaction(&level_document, Level_Command{kind = .Create_Vertical_Link, a = {9, 6}, b = {13, 10}, c = {f32(Level_Vertical_Link_Kind.Stairs), 0}, value = 1})}
	if capture_mode &&
	   (argument == "--capture-build-stairs-selected" ||
			   argument ==
				   "--capture-build-stairs-point-drag") {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Select; if len(level_document.stories) < 2 do append(&level_document.stories, Level_Story{"capture_upper", "Upper", 3, 2.5}); append(&level_document.vertical_links, Level_Vertical_Link{id = "capture_stairs_selected", kind = .Stairs, from_story = 0, to_story = 1, start = {9, 6}, finish = {13, 10}, width = 1}); rebuild_generated_links(&level_document); editor_state.selection[0] = {.Vertical_Link, "capture_stairs_selected", -1}; editor_state.selection_count = 1; if argument == "--capture-build-stairs-point-drag" {editor_state.selection[0] = {.Vertical_Link, "capture_stairs_selected", -3}; editor_state.drag_active = true; editor_state.drag_selection = editor_state.selection[0]; editor_state.drag_delta = {1, .5}; command, ok := level_selection_move_command(&level_document, editor_state.drag_selection, editor_state.drag_delta); if ok do editor_state.drag_preview = level_preview_transaction(&level_document, command)}}
	if capture_mode &&
	   argument ==
		   "--capture-build-path" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Path; editor_state.path_kind = .Footpath; editor_state.path_width = 1.4; points := make([dynamic]Vec2, 0, 4); append(&points, Vec2{8.5, 6}, Vec2{10, 7}, Vec2{12.5, 9}, Vec2{15.5, 11}); append(&level_document.paths, Level_Path{id = "capture_path", story = 0, kind = .Footpath, points = points, material = "gravel", width = 1.4}); rebuild_generated_ground(&level_document); editor_state.path_draw_count = 4; copy(editor_state.path_draw_points[:], points[:]); g.input.mouse_pos, _ = editor_world_screen(&g, points[len(points) - 1])}
	if capture_mode &&
	   (argument == "--capture-build-path-selected" ||
			   argument == "--capture-build-path-edit" ||
			   argument ==
				   "--capture-build-path-point-drag") {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Select; points := make([dynamic]Vec2, 0, 4); append(&points, Vec2{8.5, 6}, Vec2{10, 7}, Vec2{12.5, 9}, Vec2{15.5, 11}); append(&level_document.paths, Level_Path{id = "capture_path_selected", story = 0, kind = .Footpath, points = points, material = "gravel", width = 1.4}); rebuild_generated_ground(&level_document); editor_state.selection[0] = {.Path, "capture_path_selected", -1}; editor_state.selection_count = 1; if argument == "--capture-build-path-edit" {editor_begin_numeric_edit(.Path_Width, 1.4); g.input.mouse_pos = {1062, 213}} else if argument == "--capture-build-path-point-drag" {editor_state.selection[0] = {.Path, "capture_path_selected", -4}; editor_state.drag_active = true; editor_state.drag_selection = editor_state.selection[0]; editor_state.drag_delta = {1, .5}; command, ok := level_selection_move_command(&level_document, editor_state.drag_selection, editor_state.drag_delta); if ok do editor_state.drag_preview = level_preview_transaction(&level_document, command)}}
	if capture_mode &&
	   argument ==
		   "--capture-build-water" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Water; editor_state.water_elevation = .25; points := make([dynamic]Vec2, 0, 5); append(&points, Vec2{9, 6}, Vec2{13, 6}, Vec2{15, 8}, Vec2{13.5, 11}, Vec2{9.5, 10.5}); append(&level_document.waters, Level_Water{id = "capture_pond", points = points, elevation = .25}); rebuild_generated_ground(&level_document); editor_state.water_draw_count = 5; copy(editor_state.water_draw_points[:], points[:]); g.input.mouse_pos, _ = editor_world_screen(&g, points[0])}
	if capture_mode &&
	   argument ==
		   "--capture-build-water-selected" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Select; points := make([dynamic]Vec2, 0, 5); append(&points, Vec2{9, 6}, Vec2{13, 6}, Vec2{15, 8}, Vec2{13.5, 11}, Vec2{9.5, 10.5}); append(&level_document.waters, Level_Water{id = "capture_pond_selected", points = points, elevation = .25}); rebuild_generated_ground(&level_document); editor_state.selection[0] = {.Water, "capture_pond_selected", -1}; editor_state.selection_count = 1}
	if capture_mode &&
	   argument ==
		   "--capture-pond-beauty" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .None; clear(&level_document.waters); points := make([dynamic]Vec2, 0, 7); append(&points, Vec2{8.5, 6.5}, Vec2{10.5, 5.4}, Vec2{13.2, 5.8}, Vec2{15.2, 7.6}, Vec2{14.4, 10.4}, Vec2{11.8, 11.4}, Vec2{9.2, 9.8}); append(&level_document.waters, Level_Water{id = "capture_pond_beauty", points = points, elevation = .25}); rebuild_generated_ground(&level_document)}
	if capture_mode &&
	   argument ==
		   "--capture-pond-third-person" {g.screen = .Investigate; g.camera_initialized = true; g.camera_orbit_initialized = true; g.camera_zoom = .55; g.top_down_camera = false; g.editor_mode = .None; g.environment_blend = 1; rebuild_generated_ground(&level_document)}
	if capture_mode &&
	   (argument == "--capture-build-markers" ||
			   argument ==
				   "--capture-build-marker-numeric") {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Marker; clear(&level_document.markers); for kind in Level_Marker_Kind {index := int(kind); reference := ""; if kind == .Interaction && len(payload.pois) > 0 do reference = payload.pois[0].entity_id; append(&level_document.markers, Level_Marker{id = fmt.tprintf("capture_marker_%d", index), reference = reference, kind = kind, story = 0, position = {5 + f32(index % 4) * 3.5, 5 + f32(index / 4) * 4}, radius = .65, facing = f32(index) * 45, camera_height = 2})}; editor_state.marker_kind = .Interaction; editor_state.marker_radius = .75; selected_id := argument == "--capture-build-marker-numeric" ? "capture_marker_6" : "capture_marker_2"; editor_state.selection[0] = {.Marker, selected_id, -1}; editor_state.selection_count = 1; if argument == "--capture-build-marker-numeric" {index := level_marker_index(&level_document, selected_id); if index >= 0 {editor_begin_numeric_edit(.Marker_Facing, level_document.markers[index].facing); editor_state.numeric_replace_on_input = false}; g.input.mouse_pos = {1040, 364}}}
	if capture_mode &&
	   argument ==
		   "--capture-build-diagnostics" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Select; points := make([dynamic]Vec2, 0, 3); append(&points, Vec2{7, 7}, Vec2{7.1, 7}, Vec2{7, 7.1}); append(&level_document.rooms, Level_Room{id = "broken_room", name = "Broken Room", story = 0, points = points}); append(&level_document.objects, Level_Object{id = "uncatalogued_object", story = 0, position = {12, 8}}); append(&level_document.roofs, Level_Roof{id = "orphaned_roof", room_id = "missing_room", story = 0, pitch = 90}); _ = level_validate(&level_document); editor_state.diagnostics_visible = true; editor_state.diagnostic_selected = 0; editor_state.selection_count = 0}
	if capture_mode &&
	   argument ==
		   "--capture-build-playtest" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Select; editor_state.selection[0] = {.Marker, "spawn_player", -1}; editor_state.selection_count = 1; _ = editor_begin_playtest(&g)}
	if capture_mode &&
	   argument ==
		   "--capture-build-selection" {g.screen = .Investigate; g.camera_initialized = true; g.editor_mode = .Build; g.build_tool = .Select; editor_set_view(&g, .Markers); editor_state.selection[0] = {.Room, "study", -1}; editor_state.selection[1] = {.Room, "gallery", -1}; editor_state.selection[2] = {.Marker, "marker_miriam", -1}; editor_state.selection_count = 3; editor_state.box_select_active = true; editor_state.box_select_start = {1, 1}; editor_state.box_select_current = {14, 10}}
	if capture_mode &&
	   argument ==
		   "--capture-build-delete-feedback" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Select; editor_state.selection_count = 0; editor_show_feedback("DELETED OBJECT  ·  CTRL/CMD Z TO UNDO")}
	if capture_mode &&
	   argument ==
		   "--capture-build-duplicate-feedback" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Select; editor_state.selection_count = 0; editor_show_feedback("DUPLICATED 3 ITEMS  ·  CTRL/CMD Z TO UNDO")}
	if capture_mode &&
	   argument ==
		   "--capture-build-recovery-feedback" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Select; level_document.dirty = true; editor_state.selection_count = 0; editor_show_feedback("AUTOSAVE RESTORED  ·  SAVE TO KEEP THIS VERSION")}
	if capture_mode &&
	   argument ==
		   "--capture-build-save-failed" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Select; level_document.dirty = true; editor_state.selection_count = 0; editor_show_feedback("SAVE FAILED  ·  CHECK FILE PERMISSIONS", true)}
	if capture_mode &&
	   argument ==
		   "--capture-build-view-cycle" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = false; g.editor_mode = .Build; g.build_tool = .Select; editor_state.view = .Cutaway; editor_show_feedback("VIEW  ·  CUTAWAY")}
	if capture_mode &&
	   argument ==
		   "--capture-build-view-menu" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Select; editor_state.view = .Top_Down; editor_state.view_menu_visible = true}
	if capture_mode &&
	   argument ==
		   "--capture-build-undo-feedback" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Select; editor_state.selection_count = 0; editor_show_feedback("UNDO RESTORED PREVIOUS STATE")}
	if capture_mode &&
	   argument ==
		   "--capture-build-blocked-placement" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Door; editor_state.opening_active = false; g.input.mouse_pos = {650, 360}}
	if capture_mode &&
	   argument ==
		   "--capture-build-shortcuts" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Select; editor_state.shortcut_help_visible = true}
	if capture_mode &&
	   argument ==
		   "--capture-build-tool-shortcut" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = false; g.editor_mode = .Build; editor_activate_build_mode(&g, .Roof)}
	if capture_mode &&
	   argument ==
		   "--capture-build-tool-hover" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Select; box := build_tool_grid_rect(5); g.input.mouse_pos = {box.x + box.w * .5, box.y + box.h * .5}}
	if capture_mode &&
	   argument ==
		   "--capture-build-exit-confirm" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Select; level_document.dirty = true; editor_state.exit_confirm_visible = true}
	if capture_mode &&
	   argument ==
		   "--capture-build-catalog-search" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Plant; editor_state.catalog_category = "objects"; editor_state.search_buffer[0] = 's'; editor_state.search_buffer[1] = 'o'; editor_state.search_buffer[2] = 'f'; editor_state.search_count = 3; editor_state.search_active = true}
	if capture_mode &&
	   argument ==
		   "--capture-build-catalog-pinned" {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Plant; _ = catalog_toggle_pinned(&editor_state, "chair"); _ = catalog_toggle_pinned(&editor_state, "sofa"); _ = catalog_toggle_pinned(&editor_state, "floor_lamp"); editor_state.catalog_category = "pinned"; editor_state.catalog_id = "sofa"; g.input.mouse_pos = {232, 288}}
	if capture_mode &&
	   (argument == "--capture-build-object-selected" ||
			   argument == "--capture-build-object-edit" ||
			   argument ==
				   "--capture-build-object-rotate") {g.screen = .Investigate; g.camera_initialized = true; g.top_down_camera = true; g.editor_mode = .Build; g.build_tool = .Select; for &object in level_document.objects {if object.catalog_id != "" {editor_state.selection[0] = {.Object, object.id, -1}; editor_state.selection_count = 1; if argument == "--capture-build-object-edit" {editor_begin_numeric_edit(.Object_X, object.position.x); g.input.mouse_pos = {1062, 261}} else if argument == "--capture-build-object-rotate" {editor_state.object_rotate_active = true; editor_state.object_rotate_id = object.id; editor_state.object_rotate_original = object.rotation; editor_state.object_rotate_preview = 135; object.rotation = 135}; break}}}
	if capture_mode &&
	   argument ==
		   "--capture-build-room-measures" {g.screen = .Investigate; g.camera_initialized = true; g.editor_mode = .Build; g.build_tool = .Select; editor_set_view(&g, .Top_Down); editor_state.snap_mode = .Construction; editor_state.selection[0] = {.Room, "study", -1}; editor_state.selection_count = 1}
	if capture_mode &&
	   argument ==
		   "--capture-build-navmesh" {g.screen = .Investigate; g.camera_initialized = true; g.editor_mode = .Build; g.build_tool = .Select; editor_set_view(&g, .Navmesh); editor_state.selection_count = 0}
	if capture_mode &&
	   argument ==
		   "--capture-vale-house-props" {g.screen = .Investigate; g.camera_initialized = true; g.editor_mode = .Build; g.build_tool = .Select; editor_set_view(&g, .Top_Down); editor_state.selection_count = 0; clear(&level_document.roofs); rebuild_generated_roofs(&level_document)}
	if capture_mode &&
	   (argument == "--capture-build-lighting" ||
			   argument == "--capture-build-lighting-control" ||
			   argument ==
				   "--capture-build-lighting-numeric") {g.screen = .Investigate; g.camera_initialized = true; g.editor_mode = .Build; g.build_tool = .Light; editor_set_view(&g, .Lighting); light_id := "light_gallery_spot"; index := level_light_index(&level_document, light_id); if index < 0 {append(&level_document.lights, Level_Light{id = light_id, kind = .Spot, story = 0, position = {12, 14}, elevation = 2.3, range = 4.5, intensity = 1.1, facing = 270, cone_angle = 38, color = {222, 235, 255, 255}}); index = len(level_document.lights) - 1}; editor_state.selection[0] = {.Light, light_id, -1}; editor_state.selection_count = 1; if argument == "--capture-build-lighting-numeric" {editor_begin_numeric_edit(.Light_Intensity, level_document.lights[index].intensity); editor_state.numeric_replace_on_input = false; g.input.mouse_pos = {1040, 308}}}
	if capture_mode &&
	   (argument == "--capture-lighting-low" ||
			   argument == "--capture-lighting-medium" ||
			   argument == "--capture-lighting-high" ||
			   argument == "--capture-lighting-ultra") {
		g.screen = .Investigate; g.camera_initialized = true; g.camera_orbit_initialized = true; g.camera_zoom = .32; g.environment_blend = 0; g.cutaway_transition = 1; g.wall_view = .Walls_Down; for &amount in g.wall_cutaways do amount = 1; editor_state.view = .Cutaway
		g.lighting_quality =
			argument == "--capture-lighting-low" ? .Low : argument == "--capture-lighting-medium" ? .Medium : argument == "--capture-lighting-high" ? .High : .Ultra
		clear(
			&level_document.objects,
		); clear(&level_document.lights); clear(&level_document.waters); clear(&level_document.rooms); test_floor := make([dynamic]Vec2, 0, 4); append(&test_floor, Vec2{0, 0}, Vec2{8.8, 0}, Vec2{8.8, 8}, Vec2{0, 8}); append(&level_document.rooms, Level_Room{id = "lighting_test_floor", name = "Lighting Test Floor", story = 0, points = test_floor, floor_material = "gallery", wall_material = "gallery", ceiling_style = "none"}); rebuild_generated_ground(&level_document); fixture_ids := [8]string{"floor_lamp", "floor_lamp_round", "table_lamp_square", "table_lamp_round", "floor_lamp", "floor_lamp_round", "ceiling_lamp_square", "ceiling_fan"}; fixture_positions := [8]Vec2{{3, 2.5}, {7, 2.5}, {11, 2.5}, {15, 2.5}, {3, 6}, {7, 6}, {11, 6}, {15, 6}}; light_colors := [8][4]u8{{255, 166, 92, 255}, {112, 174, 255, 255}, {255, 205, 126, 255}, {150, 118, 255, 255}, {255, 128, 92, 255}, {102, 205, 235, 255}, {255, 225, 166, 255}, {174, 142, 255, 255}}; for fixture, index in fixture_ids {elevation := f32(0); if strings.contains(fixture, "table_lamp") do elevation = .76; if strings.contains(fixture, "ceiling") do elevation = 2.25; append(&level_document.objects, Level_Object{id = fmt.tprintf("capture_light_fixture_%d", index), catalog_id = fixture, story = 0, position = fixture_positions[index], elevation = elevation, rotation = f32(index) * 45, tint = {255, 255, 255, 255}, bark_tint = {255, 255, 255, 255}, foliage_tint = {255, 255, 255, 255}}); append(&level_document.lights, Level_Light{id = fmt.tprintf("capture_light_pool_%d", index), kind = index == 3 ? .Spot : .Point, story = 0, position = fixture_positions[index], elevation = index >= 6 ? f32(2.1) : f32(1.2), range = 5.5, intensity = 2.2, facing = 225, cone_angle = 55, color = light_colors[index]})}
		prop_ids := [7]string {
			"dining_table",
			"chair",
			"chair",
			"chair",
			"chair",
			"sofa",
			"plant",
		}; prop_positions := [7]Vec2{{9, 4.5}, {7.4, 4.5}, {10.6, 4.5}, {9, 3.2}, {9, 5.8}, {4.8, 4.3}, {13.2, 4.3}}; for prop, index in prop_ids do append(&level_document.objects, Level_Object{id = fmt.tprintf("capture_shadow_prop_%d", index), catalog_id = prop, story = 0, position = prop_positions[index], rotation = index == 5 ? f32(90) : f32(index) * 45, tint = {205, 188, 166, 255}, bark_tint = {96, 69, 45, 255}, foliage_tint = {62, 118, 69, 255}})
		level_document.revision += 1; level_project_runtime(&level_document)
	}
	if capture_mode &&
	   (argument == "--capture-build-stories" ||
			   argument ==
				   "--capture-build-story-up") {g.screen = .Investigate; g.camera_initialized = true; g.editor_mode = .Build; g.build_tool = .Select; upper_points := make([dynamic]Vec2, 0, 4); append(&upper_points, Vec2{3, 3}, Vec2{17, 3}, Vec2{17, 12}, Vec2{3, 12}); upper_walls := make([dynamic]Vec2, 0, 5); append(&upper_walls, Vec2{3, 3}, Vec2{17, 3}, Vec2{17, 12}, Vec2{3, 12}, Vec2{3, 3}); append(&level_document.stories, Level_Story{"upper", "Upper", 3, 2.5}); append(&level_document.rooms, Level_Room{id = "upper_lounge", name = "Upper Lounge", story = 1, points = upper_points, floor_material = "gallery", wall_material = "gallery", ceiling_style = "flat"}); append(&level_document.paths, Level_Path{id = "upper_shell", story = 1, kind = .Wall, points = upper_walls, material = "structure", width = HOUSE_WALL_THICKNESS}); append(&level_document.objects, Level_Object{id = "upper_sofa", catalog_id = "sofa", story = 1, position = {10, 7}, rotation = 90, tint = {255, 255, 255, 255}}); level_document.active_story = 1; level_document.revision += 1; level_project_runtime(&level_document); editor_set_view(&g, .Cutaway); editor_state.selection[0] = {.Room, "upper_lounge", -1}; editor_state.selection_count = 1}
	if capture_mode &&
	   argument ==
		   "--capture-attributes" {g.screen = .Attributes; g.attribute_selected = 1; g.menu_detail_return = .Investigate}
	if capture_mode &&
	   argument == "--capture-introduction" {g.screen = .Introduction; g.introduction_step = 1}
	if capture_mode &&
	   argument ==
		   "--capture-reveal" {configure_complete_questions(&g); mystery_game_mark_all_clues(&g); g.screen = .Reveal; _ = mystery_game_mark_reveal_presented(&g, 0)}
	if capture_mode &&
	   argument ==
		   "--capture-reveal-other-lies" {configure_complete_questions(&g); mystery_game_mark_all_clues(&g); g.screen = .Reveal; g.reveal_act = 3; _ = mystery_game_mark_reveal_presented(&g, 3)}
	if capture_mode &&
	   (argument == "--capture-result-airtight" ||
			   argument ==
				   "--capture-result-canonical") {configure_complete_questions(&g); mystery_game_mark_all_clues(&g); g.result = .Airtight; _ = enter_case_ending(&g, case_ending_trigger_for_outcome(g.result)); if argument == "--capture-result-canonical" do g.show_canonical = true}
	if capture_mode &&
	   argument ==
		   "--capture-ending" {ending_id := argument_value("--ending="); if ending_id == "" {fmt.eprintln("ending capture requires --ending=<id>"); return}; if !enter_case_ending(&g, ending_id) {fmt.eprintln("unknown ending ID: ", ending_id); return}}
	if capture_mode &&
	   argument ==
		   "--capture-walking" {g.screen = .Investigate; g.player_is_walking = true; g.player_animation.current = glb_clip_index(&character_meshes[0], "Walking_B"); g.player_animation.time = .24; g.move_target_active = true; g.move_target_x = 6.5; g.move_target_y = 11.5}
	if capture_mode &&
	   argument ==
		   "--capture-case-sense" {g.screen = .Investigate; mystery_game_reveal_all_pois(&g); g.case_sense_level = 1; g.case_sense_hint_until = 5}
	if capture_mode &&
	   argument ==
		   "--capture-shutter-motion" {g.screen = .Investigate; if !capture_fixture_pose(&g, &level_document, "shutter_motion") do return; g.camera_initialized = true; g.environment_blend = 1; g.cutaway_transition = 1; for &amount in g.wall_cutaways do amount = 1; g.shutter_time = 2; g.shutter_view = 1; g.shutter_open = true; g.shutter_operated = true; g.shutter_position = .55; g.shutter_target = 1; g.shutter_feedback = "The resistant crank turns as the heavy slats climb through the frame."; editor_state.view = .Cutaway}
	if capture_mode &&
	   (argument == "--capture-shutter-crank" ||
			   argument == "--capture-shutter-crank-closed" ||
			   argument == "--capture-shutter-crank-open" ||
			   argument ==
				   "--capture-shutter-crank-evidence") {g.screen = .Investigate; g.first_person_camera = true; g.environment_blend = 1; g.cutaway_transition = 1; for &amount in g.wall_cutaways do amount = 1; mystery_game_reveal_all_pois(&g); g.shutter_time = 2; g.shutter_view = 1; g.shutter_position = argument == "--capture-shutter-crank-closed" ? f32(0) : argument == "--capture-shutter-crank-open" ? f32(1) : argument == "--capture-shutter-crank-evidence" ? f32(.63) : f32(.55); g.shutter_open = g.shutter_position > .5; g.shutter_operated = true; g.shutter_thread_found = argument == "--capture-shutter-crank-evidence"; g.shutter_target = g.shutter_position; g.shutter_feedback = g.shutter_thread_found ? "Fresh wear inside the housing shows that the shutter was operated recently." : g.shutter_position == 0 ? "The shutter is locked shut." : g.shutter_position == 1 ? "The shutter is fully open." : "The resistant brass crank turns as the heavy slats climb through the frame."; runtime_interactives_rebuild(&g); if g.shutter_thread_found do context_feedback(&g, "RECENT WEAR INSIDE THE CRANK HOUSING", .Complete, "shutter_crank")}
	if capture_mode &&
	   (argument == "--capture-shutter-crank-prompt-open" ||
			   argument ==
				   "--capture-shutter-crank-prompt-close") {g.screen = .Investigate; g.first_person_camera = true; g.environment_blend = 1; g.cutaway_transition = 1; for &amount in g.wall_cutaways do amount = 1; mystery_game_reveal_all_pois(&g); g.shutter_time = 2; g.shutter_view = 1; g.shutter_open = argument == "--capture-shutter-crank-prompt-close"; g.shutter_position = g.shutter_open ? f32(1) : f32(0); g.shutter_target = g.shutter_position; runtime_interactives_rebuild(&g); for &entity, i in WORLD_ENTITIES do if game_entity_has_tag(&g, entity.source_id, "shutter_mechanism") {g.context_ui.current = context_entity_target(&g, i); g.context_ui.focus_started = -1}}
	if capture_mode &&
	   argument ==
		   "--capture-world" {g.screen = .Investigate; g.camera_initialized = true; g.environment_blend = 1; g.cutaway_transition = 0}
	if capture_mode &&
	   argument ==
		   "--capture-chaos-profile" {g.screen = .Investigate; g.camera_initialized = true; g.camera_orbit_initialized = true; g.camera_zoom = .22; g.environment_blend = 1; g.cutaway_transition = 0; g.wall_view = .Walls_Up; for &amount in g.wall_cutaways do amount = 0}
	if capture_mode &&
	   argument ==
		   "--capture-crime-scene" {g.screen = .Investigate; if !capture_fixture_camera_override(&g, &level_document, "crime_scene") do return; g.environment_blend = 1; g.wall_view = .Walls_Down; g.cutaway_transition = 1; g.capture_hide_roofs = true; for &amount in g.wall_cutaways do amount = 1; editor_state.view = .Isometric}
	if capture_mode &&
	   argument ==
		   "--capture-shadow-exterior" {g.screen = .Exterior; g.city_x = city_world(34); g.city_y = city_world(66); g.city_camera_x = g.city_x; g.city_camera_y = g.city_y; g.city_camera_initialized = true; g.city_angle = 0; g.environment_blend = 1}
	if capture_mode &&
	   argument ==
		   "--capture-wall-cutaway-transition" {g.screen = .Investigate; g.camera_initialized = true; g.environment_blend = 1; g.cutaway_transition = .5; for &amount in g.wall_cutaways do amount = .5; editor_state.view = .Isometric}
	if capture_mode &&
	   argument ==
		   "--capture-wall-cutaway-early" {g.screen = .Investigate; g.camera_initialized = true; g.environment_blend = 1; g.cutaway_transition = .1; for &amount in g.wall_cutaways do amount = .1; editor_state.view = .Isometric}
	if capture_mode &&
	   argument ==
		   "--capture-wall-cutaway-automatic" {g.screen = .Investigate; g.camera_initialized = true; g.camera_orbit_initialized = true; g.camera_zoom = 1; g.environment_blend = 0; for &wall, i in house_walls do if i < HOUSE_WALL_SECTION_CAPACITY do g.wall_cutaways[i] = house_wall_cutaway_target(&g, &wall); editor_state.view = .Isometric}
	if capture_mode &&
	   argument ==
		   "--capture-wall-cutaway-full" {g.screen = .Investigate; g.camera_initialized = true; g.camera_orbit_initialized = true; g.camera_zoom = 1; g.environment_blend = 0; g.wall_view = .Walls_Down; for &amount in g.wall_cutaways do amount = 1; editor_state.view = .Isometric}
	if capture_mode &&
	   argument ==
		   "--capture-door-double" {g.screen = .Investigate; g.camera_initialized = true; g.camera_orbit_initialized = true; g.camera_zoom = .48; g.environment_blend = 0; g.wall_view = .Walls_Down; for &amount in g.wall_cutaways do amount = 1; editor_state.view = .Isometric}
	if capture_mode &&
	   argument ==
		   "--capture-paintings" {g.screen = .Investigate; g.first_person_camera = true; g.environment_blend = 0; g.wall_view = .Walls_Up; for &amount in g.wall_cutaways do amount = 0}
	if capture_mode &&
	   argument ==
		   "--capture-door-sliding" {g.screen = .Investigate; g.camera_initialized = true; g.camera_orbit_initialized = true; g.camera_zoom = .48; g.environment_blend = 0; g.wall_view = .Walls_Down; for &amount in g.wall_cutaways do amount = 1; editor_state.view = .Isometric}
	if capture_mode &&
	   (argument == "--capture-wall-art-full" ||
			   argument == "--capture-wall-art-fade" ||
			   argument ==
				   "--capture-wall-art-hidden") {g.screen = .Investigate; g.camera_initialized = true; g.camera_orbit_initialized = true; g.camera_zoom = .42; g.environment_blend = 0; amount := argument == "--capture-wall-art-full" ? f32(0) : argument == "--capture-wall-art-fade" ? f32(.64) : f32(1); for &wall_amount in g.wall_cutaways do wall_amount = amount; editor_state.view = .Isometric}
	if capture_mode &&
	   argument ==
		   "--capture-window-architecture" {g.screen = .Investigate; g.camera_initialized = true; g.camera_orbit_initialized = true; g.camera_zoom = .62; g.environment_blend = 1; g.cutaway_transition = 0; for &amount in g.wall_cutaways do amount = 0; editor_state.view = .Isometric}
	if capture_mode &&
	   argument ==
		   "--capture-window-double-hung" {g.screen = .Investigate; g.camera_initialized = true; g.camera_orbit_initialized = true; g.camera_zoom = .62; g.environment_blend = 1; g.cutaway_transition = 0; for &amount in g.wall_cutaways do amount = 0; editor_state.view = .Isometric}
	if capture_mode &&
	   argument ==
		   "--capture-window-exterior" {g.screen = .Investigate; g.camera_initialized = true; g.camera_orbit_initialized = true; g.camera_zoom = .62; g.environment_blend = 1; g.cutaway_transition = 0; for &amount in g.wall_cutaways do amount = 0; editor_state.view = .Isometric}
	if capture_mode &&
	   argument ==
		   "--capture-window-test-gallery" {g.screen = .Investigate; g.first_person_camera = true; g.environment_blend = 1; g.cutaway_transition = 0; g.wall_view = .Walls_Up; for &amount in g.wall_cutaways do amount = 0; editor_state.view = .Isometric}
	if capture_mode &&
	   (argument == "--capture-window-test-inside-3" ||
			   argument ==
				   "--capture-window-test-inside-4") {g.screen = .Investigate; g.first_person_camera = true; g.environment_blend = 0; g.cutaway_transition = 0; g.wall_view = .Walls_Up; for &amount in g.wall_cutaways do amount = 0; editor_state.view = .Isometric}
	if capture_mode &&
	   (argument == "--capture-window-shutter" ||
			   argument == "--capture-window-shutter-motion" ||
			   argument ==
				   "--capture-window-shutter-open") {g.screen = .Investigate; g.first_person_camera = true; g.environment_blend = 1; g.cutaway_transition = 1; for &amount in g.wall_cutaways do amount = 1; g.shutter_position = argument == "--capture-window-shutter" ? f32(0) : argument == "--capture-window-shutter-open" ? f32(1) : f32(.55); g.shutter_open = g.shutter_position > .5; g.shutter_target = g.shutter_position}
	if capture_mode &&
	   argument ==
		   "--capture-dialogue" {g.dialogue_response = "Edgar never summoned me. I did not enter his study during dinner."; unlock_topic(&g, "appointment_denial")}
	if capture_mode &&
	   argument ==
		   "--capture-dialogue-interaction-statuette" {g.study_statuette_held = true; _ = dialogue_start_source_scene(&g, game_entity_id_with_tag(&g, "statuette_examination")); for _ in 0 ..< 20 do _ = update_cinematic_dialogue(&g); g.dialogue_interaction.pitch = 2.05; g.dialogue_interaction.phase = .Revealing; g.dialogue_interaction.phase_time = .8; dialogue_interaction_commit_discovery(&g); g.active_device = .Gamepad; g.gamepad_type = .PS5}
	if capture_mode &&
	   argument ==
		   "--capture-dialogue-interaction-desk" {g.desk_key_found = true; _ = dialogue_start_source_scene(&g, "study_desk"); for _ in 0 ..< 20 do _ = update_cinematic_dialogue(&g); g.dialogue_interaction.key_inserted = true; g.dialogue_interaction.feedback = "The brass key seats in the lock. Turn it to release the drawer."; g.dialogue_interaction.ledger = "TOOL APPLIED — Edgar's brass key fits the desk."; g.active_device = .Gamepad}
	if capture_mode &&
	   argument ==
		   "--capture-cinematic-hidden" {_ = dialogue_start_source_scene(&g, "study_desk"); _ = update_cinematic_dialogue(&g); g.story_presentation.ui_opacity = 0; g.story_presentation.ui_target = 0}
	if capture_mode &&
	   argument ==
		   "--capture-cinematic-line" {_ = dialogue_start_source_scene(&g, "miriam"); _ = update_cinematic_dialogue(&g); g.active_device = .Keyboard_Mouse}
	if capture_mode &&
	   argument ==
		   "--capture-cinematic-many-responses" {_ = dialogue_start_source_scene(&g, "miriam"); dialogue_transcript_append(&g, "miriam", "Dinner began at eight. Daniel was opposite me throughout.", "line"); g.dialogue_choice_page = 1; g.active_device = .Keyboard_Mouse; dialogue_focus_default(&g)}
	if capture_mode &&
	   argument ==
		   "--capture-cinematic-inspection" {g.desk_key_found = true; _ = dialogue_start_source_scene(&g, "study_desk"); for _ in 0 ..< 20 do _ = update_cinematic_dialogue(&g); g.active_device = .Gamepad}
	if capture_mode &&
	   (argument == "--capture-dialogue-object" ||
			   argument == "--capture-dialogue-object-acquired" ||
			   argument == "--capture-dialogue-object-locked" ||
			   argument ==
				   "--capture-dialogue-object-description") {g.screen = .Dialogue; description_source := game_entity_id_with_tag(&g, "statuette_examination"); g.dialogue_entity = world_entity_index(argument == "--capture-dialogue-object-description" ? description_source : "ledger"); if argument == "--capture-dialogue-object-acquired" do _ = mystery_game_mark_clue(&g, 0); if argument == "--capture-dialogue-object-locked" do mystery_game_mark_clue_attempted(&g, 0)}
	if capture_mode &&
	   (argument == "--capture-dialogue-evidence" ||
			   argument == "--capture-dialogue-evidence-presented" ||
			   argument == "--capture-dialogue-evidence-presented-history" ||
			   argument ==
				   "--capture-dialogue-evidence-only") {g.screen = .Dialogue; g.active_device = .Keyboard_Mouse; if !capture_fixture_pose(&g, &level_document, "dialogue_miriam") do return; entity, ok := capture_fixture_entity("miriam"); if !ok do return; g.dialogue_entity = entity; trigger_character_interact(&g, "miriam"); memo_index := mystery_clue_index(payload, "clue_appointment_stub"); if memo_index >= 0 do _ = mystery_game_mark_clue(&g, memo_index); g.dialogue_response = "Edgar's memo stub fixes the time of the summons Miriam denied receiving."; if argument == "--capture-dialogue-evidence-presented" || argument == "--capture-dialogue-evidence-presented-history" {for i in 0 ..< mystery_dialogue_approach_count(payload) {node := mystery_dialogue_approach_at(payload, i); if node.character_id == "miriam" && node.clue_id == "" && !mystery_game_dialogue_completed(&g, i) {complete_dialogue_approach(&g, i); break}}; evidence_index := mystery_clue_index(payload, "clue_burned_fragment"); if evidence_index >= 0 {_ = mystery_game_mark_evidence_presented(&g, evidence_index); g.dialogue_node = 3; g.dialogue_response = dialogue_evidence_feedback(&g, evidence_index)}; g.dialogue_text_started = g.animation_time; g.dialogue_ledger_scroll = argument == "--capture-dialogue-evidence-presented-history" ? 1 : 0}; if argument == "--capture-dialogue-evidence-only" {for i in 0 ..< mystery_dialogue_approach_count(payload) {node := mystery_dialogue_approach_at(payload, i); if node.character_id == "miriam" do _ = mystery_game_mark_dialogue(&g, i, false)}}}
	if capture_mode &&
	   argument ==
		   "--capture-check-roll" {g.screen = .Dialogue; g.dialogue_entity = world_entity_index("ledger"); g.pending_clue = mystery_clue_index(payload, "clue_ledger"); g.check_from_dialogue = true; g.check_preview = check_target(payload.clues[g.pending_clue].difficulty); g.check_result = Check_Result {
			target   = g.check_preview,
			die_a    = 5,
			die_b    = 4,
			modifier = 1,
			total    = 10,
			success  = true,
		}; g.check_done = true; g.check_roll_started = -1.45}
	if capture_mode &&
	   (argument == "--capture-check-dice-start" ||
			   argument == "--capture-check-zoom" ||
			   argument ==
				   "--capture-check-success") {g.screen = .Dialogue; g.dialogue_entity = world_entity_index("ledger"); g.pending_clue = mystery_clue_index(payload, "clue_ledger"); g.check_from_dialogue = true; g.check_preview = check_target(payload.clues[g.pending_clue].difficulty); g.check_result = argument == "--capture-check-zoom" ? Check_Result{target = g.check_preview, die_a = 2, die_b = 3, modifier = 1, total = 6, success = false} : Check_Result{target = g.check_preview, die_a = 5, die_b = 4, modifier = 1, total = 10, success = true}; g.check_done = true; g.check_roll_started = argument == "--capture-check-dice-start" ? f32(-.35) : f32(-1.8)}
	if capture_mode &&
	   argument ==
		   "--capture-check-overtime" {g.screen = .Dialogue; g.dialogue_entity = world_entity_index("ledger"); g.pending_clue = mystery_clue_index(payload, "clue_ledger"); g.check_from_dialogue = true; g.check_preview = check_target(payload.clues[g.pending_clue].difficulty); g.ap = 0; g.overtime_clue_plus_one = 1}
	if capture_mode &&
	   (argument == "--capture-dialogue-elsie" ||
			   argument == "--capture-dialogue-history" ||
			   argument == "--capture-dialogue-history-oldest" ||
			   argument == "--capture-dialogue-long-response" ||
			   argument == "--capture-dialogue-many-responses" ||
			   argument == "--capture-approach-check" ||
			   argument == "--capture-approach-check-success" ||
			   argument == "--capture-approach-check-failure" ||
			   argument == "--capture-approach-check-return-success" ||
			   argument == "--capture-approach-check-return-failure" ||
			   argument == "--capture-check-tooltip" ||
			   argument == "--capture-dialogue-showcase" ||
			   argument == "--capture-dialogue-keyboard-shortcuts" ||
			   argument == "--capture-dialogue-mouse-hover" ||
			   argument == "--capture-dialogue-gamepad-focus" ||
			   argument == "--capture-dialogue-playstation-focus" ||
			   argument == "--capture-disposition-tooltip" ||
			   argument ==
				   "--capture-disposition-tooltip-neutral") {g.screen = .Dialogue; if !capture_fixture_pose(&g, &level_document, "dialogue_elsie") do return; entity, ok := capture_fixture_entity("elsie"); if !ok do return; g.dialogue_entity = entity; trigger_character_interact(&g, "elsie"); _ = learn_claim(&g, "claim_elsie_study"); unlock_topic(&g, "kitchen_routine")}
	if capture_mode &&
	   argument ==
		   "--capture-dialogue-many-responses" {for i in 0 ..< mystery_dialogue_approach_count(payload) {node := mystery_dialogue_approach_at(payload, i); if node.character_id == "elsie" do for j in 0 ..< node.require_count {id := node.requires[j]; if mystery_claim_index(payload, id) >= 0 do _ = learn_claim(&g, id)
				else do unlock_topic(&g, id)}}; g.dialogue_choice_page = 1}
	if capture_mode &&
	   (argument == "--capture-approach-check" ||
			   argument == "--capture-approach-check-success" ||
			   argument == "--capture-approach-check-failure" ||
			   argument == "--capture-approach-check-return-success" ||
			   argument ==
				   "--capture-approach-check-return-failure") {for i in 0 ..< mystery_dialogue_approach_count(payload) {node := mystery_dialogue_approach_at(payload, i); if node.character_id == "elsie" && node.clue_id != "" && dialogue_approach_available(&g, i) {begin_dialogue_approach_check(&g, i); break}}; if argument == "--capture-approach-check-success" {g.ap = 11; g.check_result = Check_Result {
				target   = g.check_preview,
				die_a    = 5,
				die_b    = 4,
				modifier = 1,
				total    = 10,
				success  = true,
			}; g.check_disposition_delta = 1; g.check_done = true; g.check_roll_started = -1.8}; if argument == "--capture-approach-check-failure" {g.ap = 11; g.check_result = Check_Result {
				target   = g.check_preview,
				die_a    = 2,
				die_b    = 3,
				modifier = 1,
				total    = 6,
				success  = false,
			}; g.check_disposition_delta = -1; g.check_done = true; g.check_roll_started = -1.8}; if argument == "--capture-approach-check-return-success" || argument == "--capture-approach-check-return-failure" {g.active_device = .Keyboard_Mouse; node_index := g.pending_dialogue_approach - 1; clue_index := g.pending_clue; success := argument == "--capture-approach-check-return-success"; if clue_index >= 0 do g.check_disposition_delta = apply_check_disposition(&g, clue_index, success); if success {if clue_index >= 0 do _ = mystery_game_mark_clue(&g, clue_index); complete_dialogue_approach(&g, node_index)} else {if clue_index >= 0 do mystery_game_set_clue_attempt_score(&g, clue_index, clue_reopen_score(&g, clue_index)); fail_dialogue_approach(&g, node_index)}; g.pending_dialogue_approach = 0; g.check_from_dialogue = false; g.check_done = false; g.dialogue_ledger_scroll = 0}}
	if capture_mode &&
	   (argument == "--capture-dialogue-history" ||
			   argument ==
				   "--capture-dialogue-history-oldest") {g.active_device = .Keyboard_Mouse; completed := 0; for i in 0 ..< mystery_dialogue_approach_count(payload) {node := mystery_dialogue_approach_at(payload, i); if node.character_id == "elsie" && node.clue_id == "" && completed < 2 {complete_dialogue_approach(&g, i); completed += 1}}; for i in 0 ..< mystery_dialogue_approach_count(payload) {node := mystery_dialogue_approach_at(payload, i); if node.node_id == "approach_elsie_theft" {_ = mystery_game_mark_dialogue(&g, i, false); clue_index := mystery_clue_index(payload, node.clue_id); if clue_index >= 0 do _ = mystery_game_mark_clue(&g, clue_index); g.dialogue_response = node.response}}; if argument == "--capture-dialogue-history-oldest" do g.dialogue_ledger_scroll = 1}
	if capture_mode &&
	   argument ==
		   "--capture-dialogue-long-response" {unlock_topic(&g, "late_case_changes"); for i in 0 ..< mystery_dialogue_approach_count(payload) {node := mystery_dialogue_approach_at(payload, i); if node.node_id == "approach_elsie_return" do complete_dialogue_approach(&g, i)}}
	if capture_mode &&
	   strings.contains(
		   argument,
		   "recreate",
	   ) {configure_complete_questions(&g); g.ap = 4; g.screen = .Recreate; if argument == "--capture-cover-up-recreate" do g.active_demonstration = demonstration_for_question(&g, question_index_by_id(&g, "q_garden_murder")); if argument == "--capture-alibi-recreate" do g.active_demonstration = demonstration_for_question(&g, question_index_by_id(&g, "q_daniel_lie")); if argument == "--capture-proof-recreate" || argument == "--capture-shutter-recreate" || argument == "--capture-recreate-motion" do g.active_demonstration = demonstration_for_question(&g, question_index_by_id(&g, "q_miriam_study_meeting"))}
	if capture_mode &&
	   (argument == "--capture-interaction-inspect" ||
			   argument == "--capture-interaction-connect" ||
			   argument ==
				   "--capture-interaction-reconstruct") {mystery_game_mark_all_clues(&g); for claim in payload.claims do _ = learn_claim(&g, claim.id); refresh_questions(&g); question_id := argument == "--capture-interaction-inspect" ? "q_garden_murder" : argument == "--capture-interaction-connect" ? "q_fragment_source" : "q_when_death"; g.question_selected = question_index_by_id(&g, question_id); demo_index := demonstration_for_question(&g, g.question_selected); if demo_index >= 0 {demo := &payload.demonstrations[demo_index]; for slot in 0 ..< demo.slot_count do mystery_question_set_slot(&g, g.question_selected, slot, mystery_demonstration_route_piece(demo, 0, slot)); begin_question_demonstration(&g)}; g.scene_transition_active = false; g.active_device = .Gamepad}
	if capture_mode && (argument == "--capture-recreate" || argument == "--capture-cover-up-recreate" || argument == "--capture-alibi-recreate") do g.recreate_started = -20
	if capture_mode &&
	   argument == "--capture-recreate-motion" {g.screen = .Recreate; g.recreate_started = -3}
	if capture_mode &&
	   (argument == "--capture-final-demo" ||
			   argument ==
				   "--capture-final-demo-paper") {configure_complete_questions(&g); mystery_game_mark_all_clues(&g); g.screen = .Reveal; g.reveal_act = 4; g.finale_demo_step = argument == "--capture-final-demo-paper" ? 1 : 2}
	if capture_mode &&
	   argument ==
		   "--capture-board-incomplete" {mystery_game_mark_all_clues(&g); for claim in payload.claims do _ = learn_claim(&g, claim.id); refresh_questions(&g); g.screen = .Challenge; g.question_selected = question_index_by_id(&g, "q_garden_murder"); demo_index := demonstration_for_question(&g, g.question_selected); mystery_question_set_slot(&g, g.question_selected, 0, mystery_demonstration_route_piece(&payload.demonstrations[demo_index], 0, 0)); mystery_question_set_state(&g, g.question_selected, .Supported); g.question_feedback = "One relevant piece is placed. Choose evidence for the remaining part of the test."}
	if capture_mode &&
	   argument ==
		   "--capture-board" {mystery_game_mark_all_clues(&g); for claim in payload.claims do _ = learn_claim(&g, claim.id); refresh_questions(&g); g.screen = .Board; g.question_selected = question_index_by_id(&g, "q_garden_murder"); g.question_feedback = "Choose a question, then combine evidence to test its claim."}
	if capture_mode &&
	   argument ==
		   "--capture-board-complete" {configure_complete_questions(&g); event_chain_from_evidence(&g); g.screen = .Board}
	if capture_mode &&
	   argument ==
		   "--capture-event-chain-break" {configure_complete_questions(&g); g.workbench_event_count = 2; g.workbench_events[0] = {507, "miriam", "move_body", "body", "garden", -1}; g.workbench_events[1] = {504, "miriam", "strike", "statuette", "study", -1}; run_workbench(&g)}
	if capture_mode &&
	   argument ==
		   "--capture-reveal-prep" {configure_complete_questions(&g); g.screen = .Reveal_Prep}
	ui.gui_init(
		&g.gui,
	); defer ui.gui_destroy(&g.gui); g.gui.focused = button_id({440, 500, 320, 54}); g.input.mouse_pos = {600, 360}
	// A core-only story enters its authored opening directly. Capability-specific
	// campaign surfaces remain opt-in instead of being a host prerequisite.
	if payload == nil && !capture_mode && !world_preview && len(active_story_project.scenes) > 0 do _ = dialogue_start_scene(&g, 0)
	if capture_mode && argument == "--capture-graph-choice" do g.input.mouse_pos = {1155, 219}
	if capture_mode &&
	   argument ==
		   "--capture-graph-routing-crossing-hover" {g.input.mouse_pos = {450, 151}; graph_state.edge_hover = graph_edge_hit(g.input.mouse_pos)}
	if capture_mode &&
	   argument ==
		   "--capture-graph-routing-parallel-hover" {from_port := graph_port_rect(graph_document.nodes[15], 1); to_port := graph_input_rect(graph_document.nodes[17]); g.input.mouse_pos = {(from_port.x + from_port.w * .5 + to_port.x + to_port.w * .5) * .5, (from_port.y + from_port.h * .5 + to_port.y + to_port.h * .5) * .5}; graph_state.edge_hover = graph_edge_hit(g.input.mouse_pos)}
	if capture_mode &&
	   argument ==
		   "--capture-graph-routing-zoomed-hover" {from_port := graph_port_rect(graph_document.nodes[11], 0); to_port := graph_input_rect(graph_document.nodes[12]); g.input.mouse_pos = {(from_port.x + from_port.w * .5 + to_port.x + to_port.w * .5) * .5, (from_port.y + from_port.h * .5 + to_port.y + to_port.h * .5) * .5}; graph_state.edge_hover = graph_edge_hit(g.input.mouse_pos)}
	if capture_mode &&
	   argument ==
		   "--capture-graph-routing-direct-hover" {from_port := graph_port_rect(graph_document.nodes[0], 0); to_port := graph_input_rect(graph_document.nodes[1]); g.input.mouse_pos = {(from_port.x + from_port.w * .5 + to_port.x + to_port.w * .5) * .5, (from_port.y + from_port.h * .5 + to_port.y + to_port.h * .5) * .5}; graph_state.edge_hover = graph_edge_hit(g.input.mouse_pos)}
	if capture_mode &&
	   argument ==
		   "--capture-graph-routing-obstacle-hover" {from_port := graph_port_rect(graph_document.nodes[2], 0); to_port := graph_input_rect(graph_document.nodes[4]); a, d := Vec2{from_port.x + from_port.w * .5, from_port.y + from_port.h * .5}, Vec2{to_port.x + to_port.w * .5, to_port.y + to_port.h * .5}; if lane, ok := graph_edge_local_lane("wire_routing", a, d, 2, 4); ok {g.input.mouse_pos = {(a.x + d.x) * .5, lane}; graph_state.edge_hover = graph_edge_hit(g.input.mouse_pos)}}
	if capture_mode &&
	   argument ==
		   "--capture-graph-routing-back-hover" {g.input.mouse_pos = {580, 360}; graph_state.edge_hover = graph_edge_hit(g.input.mouse_pos)}
	if capture_mode && g.screen == .Dialogue do dialogue_focus_default(&g)
	if capture_mode && argument == "--capture-build-lighting-control" do g.input.mouse_pos = {939, 263}
	if capture_mode && argument == "--capture-build-story-up" do g.input.mouse_pos = {950, 31}
	if capture_mode &&
	   argument ==
		   "--capture-build-tool-hover" {box := build_tool_grid_rect(5); g.input.mouse_pos = {box.x + box.w * .5, box.y + box.h * .5}}
	if capture_mode &&
	   (argument == "--capture-check-tooltip" || argument == "--capture-dialogue-showcase") {
		g.active_device = .Keyboard_Mouse
		for i in 0 ..< mystery_dialogue_approach_count(payload) {
			node := mystery_dialogue_approach_at(payload, i)
			if node.node_id != "approach_elsie_theft" do continue
			for j in 0 ..< node.require_count {
				id := node.requires[j]
				if mystery_claim_index(payload, id) >= 0 do _ = learn_claim(&g, id)
				else do _ = mystery_string_set_add(&g.mystery_state.acquired_evidence, id)
			}
		}
		g.screen = .Dialogue
		entity, ok := capture_fixture_entity("elsie"); if !ok do return; g.dialogue_entity = entity
		if argument == "--capture-dialogue-showcase" {
			g.conversation_transcript_count = 0
			conversation_transcript_append(
				&g,
				"narrator",
				"Elsie folds the polishing cloth into a smaller and smaller square.",
				"action",
				"elsie",
			)
			conversation_transcript_append(
				&g,
				"detective_thought",
				"She answered too quickly. The study matters to her.",
				"thought",
				"elsie",
			)
			conversation_transcript_append(
				&g,
				"elsie",
				"I never entered the study, Detective. Not once.",
				"dialogue",
				"elsie",
			)
		}
		clue := clue_for_source(&g, "elsie")
		count := dialogue_available_approach_count(&g, "elsie")
		for absolute in 0 ..< count {
			index := visible_dialogue_approach(&g, "elsie", absolute)
			if index < 0 || dialogue_check_clue_index(&g, index) < 0 do continue
			g.dialogue_choice_page = absolute
			local := 0
			choice := dialogue_response_rect(&g, "elsie", clue, local)
			g.gui.focused = button_id(choice)
			g.input.mouse_pos = {choice.x + choice.w * .5, choice.y + choice.h * .5}
			break
		}
	}
	if capture_mode && argument == "--capture-dialogue-complex-sequence" {
		g.active_device = .Keyboard_Mouse
		g.conversation_transcript_count = 0
		_ = dialogue_start_source_scene(&g, "miriam")
		dialogue_transcript_append(&g, "daniel", "Take your hand off me.", "dialogue")
		dialogue_transcript_append(
			&g,
			"narrator",
			"Elsie releases his wrist and steps between Daniel and the desk.",
			"action",
		)
		_ = update_cinematic_dialogue(&g)
		dialogue_focus_default(&g)
		g.input.mouse_pos = {600, 680}
	}
	if capture_mode &&
	   argument ==
		   "--capture-dialogue-keyboard-shortcuts" {g.active_device = .Keyboard_Mouse; dialogue_focus_default(&g); g.input.mouse_pos = {600, 680}}
	if capture_mode &&
	   argument ==
		   "--capture-dialogue-mouse-hover" {g.active_device = .Keyboard_Mouse; y := dialogue_choices_start_y(&g, "elsie"); first := Rect{}; for slot in 0 ..< 3 {index := visible_dialogue_approach(&g, "elsie", slot); if index < 0 do continue; choice := dialogue_approach_rect(&g, index, y); if slot == 0 do first = choice; if dialogue_check_clue_index(&g, index) >= 0 do g.gui.focused = button_id(choice); y += choice.h + 4}; g.input.mouse_pos = {first.x + 200, first.y + 20}}
	if capture_mode &&
	   (argument == "--capture-dialogue-gamepad-focus" ||
			   argument ==
				   "--capture-dialogue-playstation-focus") {g.active_device = .Gamepad; if argument == "--capture-dialogue-playstation-focus" do g.gamepad_type = .PS5; y := dialogue_choices_start_y(&g, "elsie"); first := Rect{}; for slot in 0 ..< 3 {index := visible_dialogue_approach(&g, "elsie", slot); if index < 0 do continue; choice := dialogue_approach_rect(&g, index, y); if slot == 0 do first = choice; if dialogue_check_clue_index(&g, index) >= 0 do g.gui.focused = button_id(choice); y += choice.h + 4}; g.input.mouse_pos = {first.x + 20, first.y + 20}}
	if capture_mode &&
	   (argument == "--capture-disposition-tooltip" ||
			   argument ==
				   "--capture-disposition-tooltip-neutral") {g.active_device = .Keyboard_Mouse; if argument == "--capture-disposition-tooltip-neutral" {index := character_index(&g, "elsie"); if index >= 0 do mystery_game_set_disposition(&g, "elsie", 0)}; box := disposition_rect(); g.input.mouse_pos = {box.x + box.w * .5, box.y + box.h * .5}}
	if capture_mode &&
	   argument ==
		   "--capture-dialogue-evidence-only" {clue := clue_for_source(&g, "miriam"); g.gui.focused = button_id(dialogue_evidence_choice_rect(&g, "miriam", clue))}
	if capture_mode && (argument == "--capture-approach-check" || argument == "--capture-approach-check-success" || argument == "--capture-approach-check-failure") do dialogue_focus_default(&g)
	if capture_mode && (argument == "--capture-dialogue-history" || argument == "--capture-dialogue-history-oldest") do dialogue_focus_default(&g)
	if capture_mode &&
	   argument ==
		   "--capture-dialogue-history-oldest" {g.dialogue_ledger_scroll = 2; g.input.mouse_pos = {1150, 330}}
	if capture_mode && argument == "--capture-agent-room" {
		if len(os.args) < 3 {fmt.eprintln("agent room capture requires a room ID"); return}
		room_index := level_room_index(
			&level_document,
			os.args[2],
		); if room_index < 0 {fmt.eprintln("unknown room: ", os.args[2]); return}; room := &level_document.rooms[room_index]
		level_document.active_story =
			room.story; level_project_runtime(&level_document); minimum := Vec2{1e30, 1e30}; maximum := Vec2{-1e30, -1e30}; for point in room.points {minimum.x = min(minimum.x, point.x); minimum.y = min(minimum.y, point.y); maximum.x = max(maximum.x, point.x); maximum.y = max(maximum.y, point.y)}; center := Vec2{(minimum.x + maximum.x) * .5, (minimum.y + maximum.y) * .5}; g.screen = .Investigate; g.editor_mode = .Build; g.build_tool = .Select; g.top_down_camera = true; g.player_x = center.x; g.player_y = center.y; g.camera_x = center.x; g.camera_y = center.y; g.camera_zoom = editor_frame_zoom(minimum, maximum, len(room.points)); g.camera_initialized = true; g.camera_orbit_initialized = true; g.cutaway_transition = 1; editor_state.view = .Top_Down; editor_state.selection[0] = {.Room, room.id, -1}; editor_state.selection_count = 1
	}
	if capture_mode && !capture_apply_cli_overrides(&g) do return
	capture_name :=
		capture_mode ? argument[len("--capture-"):] : ""; capture_path := argument == "--capture-catalog-thumbnail" ? fmt.tprintf("/private/tmp/chicago-catalog-%s.png", os.args[2]) : fmt.tprintf("/private/tmp/chicago-vulkan-%s.png", capture_name); custom_capture_path := argument_value("--capture-output="); if custom_capture_path != "" do capture_path = custom_capture_path; capture_mouse := g.input.mouse_pos; capture_device := g.active_device; frames := 0; profile_draw_seconds, profile_frame_seconds, profile_shadow_ms, profile_world_ms, profile_ui_ms, profile_tail_ms, profile_lights_ms, profile_batches_ms, profile_unbatched_ms, profile_draw_setup_ms, profile_draw_refresh_ms, profile_draw_world_build_ms, profile_draw_weather_ms, profile_draw_overlay_ms, profile_house_structure_ms, profile_house_surfaces_ms, profile_house_walls_ms, profile_house_openings_ms, profile_house_objects_ms, profile_house_characters_ms: f64; profile_samples := 0
	// Rendering produces elapsed wall time; the simulation consumes it only in
	// deterministic 60 Hz chunks. Seed one tick so UI and gameplay state are
	// initialized before the first presented frame.
	previous_tick := time.tick_now(); accumulator := FIXED_TIMESTEP
	begin_frame(&g)
	for g.running {
		now := time.tick_now(

		); frame_time := min(time.duration_seconds(time.tick_diff(previous_tick, now)), MAX_FRAME_TIME); previous_tick = now
		if !capture_mode do accumulator += frame_time
		poll(
			&g,
			window,
		); if capture_mode {g.input.mouse_pos = capture_mouse; g.active_device = capture_device}; if g.active_device == .Gamepad do _ = sdl.HideCursor()
		else do _ = sdl.ShowCursor(); if g.window_resized {backend.ctx.needs_swapchain_recreate = true; g.window_resized = false}
		fixed_steps := 0
		for !capture_mode &&
		    accumulator >= FIXED_TIMESTEP &&
		    fixed_steps < MAX_FIXED_STEPS_PER_FRAME {
			if g.controller_disconnected || g.input_resume_blocked {
				// Freeze gameplay until the player chooses another input device or reconnects.
			} else if g.scene_transition_active {
				scene_transition_update(&g, FIXED_TIMESTEP)
			} else {
				previous_screen := g.screen
				if g.screen == .Loading do map_loading_update(&g, FIXED_TIMESTEP)
				else do update(&g)
				if g.screen != previous_screen do scene_transition_begin(&g, previous_screen, g.screen)
				scene_transition_update(&g, FIXED_TIMESTEP)
			}
			update_vehicle_haptics(&g)
			if g.gui.clipboard_set_pending {clipboard, err := strings.clone_to_cstring(string(g.gui.clipboard_set_text[:g.gui.clipboard_set_len]), context.temp_allocator); if err == nil do _ = sdl.SetClipboardText(clipboard); g.gui.clipboard_set_pending = false}
			accumulator -= FIXED_TIMESTEP; fixed_steps += 1
			// Edge-triggered input is consumed by one simulation tick. Held keys,
			// pointer position, and analog axes remain live for catch-up ticks.
			begin_frame(&g)
		}
		// Bound recovery work after a stall to avoid the spiral of death.
		if fixed_steps == MAX_FIXED_STEPS_PER_FRAME do accumulator = min(accumulator, FIXED_TIMESTEP)
		capture_request_frame :=
			(argument == "--capture-chaos-profile" || argument == "--capture-ending") ? 120 : 3; draw_started := time.tick_now(); draw_vulkan(&backend, &g); draw_finished := time.tick_now(); if capture_mode && frames == capture_request_frame do vulkan_backend_request_capture(&backend, capture_path); frame_started := time.tick_now(); if !vulkan_backend_frame(&backend, &g) do g.running = false; frame_finished := time.tick_now(); if argument == "--capture-chaos-profile" && frames >= 30 {if frames == 30 do fmt.println("CHAOS PROFILE READY"); profile_draw_seconds += time.duration_seconds(time.tick_diff(draw_started, draw_finished)); profile_frame_seconds += time.duration_seconds(time.tick_diff(frame_started, frame_finished)); profile_shadow_ms += backend.profile_shadow_ms; profile_world_ms += backend.profile_world_ms; profile_ui_ms += backend.profile_ui_ms; profile_tail_ms += backend.profile_tail_ms; profile_lights_ms += backend.world.profile_lights_ms; profile_batches_ms += backend.world.profile_batches_ms; profile_unbatched_ms += backend.world.profile_unbatched_ms; profile_draw_setup_ms += backend.profile_draw_setup_ms; profile_draw_refresh_ms += backend.profile_draw_refresh_ms; profile_draw_world_build_ms += backend.profile_draw_world_build_ms; profile_draw_weather_ms += backend.profile_draw_weather_ms; profile_draw_overlay_ms += backend.profile_draw_overlay_ms; profile_house_structure_ms += backend.world.profile_house_structure_ms; profile_house_surfaces_ms += backend.world.profile_house_surfaces_ms; profile_house_walls_ms += backend.world.profile_house_walls_ms; profile_house_openings_ms += backend.world.profile_house_openings_ms; profile_house_objects_ms += backend.world.profile_house_objects_ms; profile_house_characters_ms += backend.world.profile_house_characters_ms; profile_samples += 1}; if backend.capture_written {if argument == "--capture-chaos-profile" && profile_samples > 0 {fmt.println(fmt.tprintf("CHAOS PROFILE samples=%d draw_ms=%.3f submit_present_ms=%.3f total_ms=%.3f", profile_samples, profile_draw_seconds / f64(profile_samples) * 1000, profile_frame_seconds / f64(profile_samples) * 1000, (profile_draw_seconds + profile_frame_seconds) / f64(profile_samples) * 1000)); fmt.println(fmt.tprintf("CHAOS DRAW setup_ms=%.3f refresh_ms=%.3f world_build_ms=%.3f weather_ms=%.3f overlay_ms=%.3f", profile_draw_setup_ms / f64(profile_samples), profile_draw_refresh_ms / f64(profile_samples), profile_draw_world_build_ms / f64(profile_samples), profile_draw_weather_ms / f64(profile_samples), profile_draw_overlay_ms / f64(profile_samples))); fmt.println(fmt.tprintf("CHAOS HOUSE structure_ms=%.3f surfaces_ms=%.3f walls_ms=%.3f openings_ms=%.3f objects_ms=%.3f characters_ms=%.3f", profile_house_structure_ms / f64(profile_samples), profile_house_surfaces_ms / f64(profile_samples), profile_house_walls_ms / f64(profile_samples), profile_house_openings_ms / f64(profile_samples), profile_house_objects_ms / f64(profile_samples), profile_house_characters_ms / f64(profile_samples))); fmt.println(fmt.tprintf("CHAOS PHASES shadow_ms=%.3f world_ms=%.3f ui_ms=%.3f tail_ms=%.3f", profile_shadow_ms / f64(profile_samples), profile_world_ms / f64(profile_samples), profile_ui_ms / f64(profile_samples), profile_tail_ms / f64(profile_samples))); fmt.println(fmt.tprintf("CHAOS WORLD lights_ms=%.3f batches_ms=%.3f unbatched_ms=%.3f", profile_lights_ms / f64(profile_samples), profile_batches_ms / f64(profile_samples), profile_unbatched_ms / f64(profile_samples)))}; fmt.println("captured Vulkan frame: ", capture_path); g.running = false}; frames += 1
	}
	campaign_case_load_reap()
	if g.gamepad != nil {_ = sdl.RumbleGamepad(g.gamepad, 0, 0, 0); sdl.CloseGamepad(g.gamepad)}
}
