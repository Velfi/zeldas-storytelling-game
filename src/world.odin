package main

import "core:fmt"
import "core:math"
import "core:strings"

Floorplan_Spline :: struct {
	points: []Vec2,
	width:  f32,
}
// Vale House is an 1800s solid-masonry mansion. 460 mm is representative of
// a substantial two-wythe brick/stone wall with interior and exterior finish.
HOUSE_EXTERIOR_WALL_THICKNESS :: f32(.46)
HOUSE_INTERIOR_WALL_THICKNESS :: f32(.18)
HOUSE_WALL_THICKNESS :: HOUSE_EXTERIOR_WALL_THICKNESS
house_wall_width :: proc(width: f32) -> f32 {return(
		width > 0 ? width : HOUSE_INTERIOR_WALL_THICKNESS \
	)}
house_opening_face_offset :: proc(opening: Plan_Opening, face_lift: f32) -> f32 {
	return house_wall_width(opening.wall_width) * .5 + face_lift
}
HOUSE_WALL_HEIGHT :: f32(3.5)
HOUSE_CUTAWAY_HEIGHT :: f32(1.35)
HOUSE_WALL_SECTION_CAPACITY :: 256
house_authored_wall_height :: proc() -> f32 {story := level_document.active_story; if story >= 0 && story < len(level_document.stories) && level_document.stories[story].wall_height > 0 do return level_document.stories[story].wall_height
	return HOUSE_WALL_HEIGHT}
House_Wall_View :: enum {
	Automatic,
	Walls_Up,
	Walls_Down,
}
house_wall_view_name :: proc(view: House_Wall_View) -> string {#partial switch
	view {case .Automatic:
		return "AUTO CUTAWAY"; case .Walls_Up:
		return "WALLS UP"; case .Walls_Down:
		return "WALLS DOWN"}
	return "AUTO CUTAWAY"}

HOUSE_WINDOW_FRAME_RAIL_HEIGHT :: .055
HOUSE_WINDOW_GLAZING_BEAD_DEPTH :: .012
HOUSE_WINDOW_HARDWARE_DEPTH :: .018
HOUSE_WINDOW_MUNTIN_DEPTH :: .016
HOUSE_WALL_COVERING_UV_SCALE :: f32(.5)
// Plan-view aperture subtraction uses a square cap whose tangent extension is
// half its cut width. Window masonry and exterior finish must cover that same
// shoulder without changing the authored span used by interior wallpaper.
HOUSE_OPENING_CUT_WIDTH :: f32(HOUSE_WALL_THICKNESS + .02)
HOUSE_OPENING_CUT_END_EXTENSION :: HOUSE_OPENING_CUT_WIDTH * .5
HOUSE_EXTERIOR_OPENING_FINISH_OVERLAP :: HOUSE_OPENING_CUT_END_EXTENSION + .02
HOUSE_NAV_CELL :: .5
HOUSE_NAV_WIDTH :: 96
HOUSE_NAV_HEIGHT :: 88
HOUSE_NAV_CELLS :: HOUSE_NAV_WIDTH * HOUSE_NAV_HEIGHT
HOUSE_SURFACE_WIDTH :: 48
HOUSE_SURFACE_HEIGHT :: 44
HOUSE_SURFACE_CELLS :: HOUSE_SURFACE_WIDTH * HOUSE_SURFACE_HEIGHT
HOUSE_MANUAL_MOVE_SPEED :: .044
HOUSE_PATH_MOVE_MIN_SPEED :: .017
HOUSE_PATH_MOVE_MAX_SPEED :: .053
// Walking should answer quickly at the start and settle cleanly on release,
// while retaining a short ramp so keyboard input does not look robotic.
HOUSE_MOVE_ACCELERATION :: .014
HOUSE_MOVE_DECELERATION :: .022
HOUSE_MOVE_TURN_ACCELERATION :: .018
HOUSE_MOVE_REVERSE_ACCELERATION :: .018
HOUSE_STICK_DEADZONE :: .18
HOUSE_AUTHORED_PATH_COST :: .85
HOUSE_ATTIC_NAV_CLEARANCE :: 1.9
HOUSE_PLAYER_MAX_STEP_HEIGHT :: .35
HOUSE_PLAYER_STEP_SPEED :: .06
house_nav_walkable: [HOUSE_NAV_CELLS]bool

house_radial_input :: proc(input: Vec2) -> Vec2 {
	length := f32(math.sqrt(f64(input.x * input.x + input.y * input.y)))
	if length <= HOUSE_STICK_DEADZONE do return {}
	// Remap the usable stick travel to 0..1, then use a gentle quadratic blend:
	// precise near center, responsive through the middle, full speed at the rim.
	direction := Vec2 {
		input.x / length,
		input.y / length,
	}; magnitude := clamp((min(length, f32(1)) - HOUSE_STICK_DEADZONE) / (1 - HOUSE_STICK_DEADZONE), 0, 1)
	response := magnitude * magnitude * .35 + magnitude * .65
	return {direction.x * response, direction.y * response}
}

house_approach_velocity :: proc(current, target: Vec2, moving: bool) -> Vec2 {
	dx, dy :=
		target.x -
		current.x,
		target.y -
		current.y; distance := f32(math.sqrt(f64(dx * dx + dy * dy)))
	if distance <= .00001 do return target
	rate := moving ? f32(HOUSE_MOVE_ACCELERATION) : f32(HOUSE_MOVE_DECELERATION)
	if moving {
		dot := current.x * target.x + current.y * target.y
		// Give steering its own response instead of making the player coast along
		// the old heading. Reversals remain capped so they still have visible weight.
		if dot <
		   0 {rate = f32(HOUSE_MOVE_REVERSE_ACCELERATION)} else if dot * dot < .72 * .72 * (current.x * current.x + current.y * current.y) * (target.x * target.x + target.y * target.y) do rate = f32(HOUSE_MOVE_TURN_ACCELERATION)
	}
	if distance <= rate do return target
	return {current.x + dx / distance * rate, current.y + dy / distance * rate}
}
// Straight spline spans are split wherever a doorway belongs. Adding curved
// paths later only requires sampling more points into the same representation.
World_Entity :: struct {
	x, y, elevation, facing, scale:                 f32,
	kind, source_id, name, description, appearance: string,
	tags:                                           [STORY_MAX_TAGS]string,
	tag_count:                                      int,
}

world_entity_has_tag :: proc(entity: ^World_Entity, tag: string) -> bool {for value in entity.tags[:entity.tag_count] do if value == tag do return true
	return false}
world_entity_index_with_tag :: proc(tag: string) -> int {for &entity, i in WORLD_ENTITIES do if world_entity_has_tag(&entity, tag) do return i
	return -1}
// Runtime entities are a projection of StoryCore entities with the
// `world_entity` role. Their transforms come exclusively from LevelFormat.
// There is deliberately no compiled-in fallback: a missing spatial binding is
// invalid authored content, not permission to resurrect a stale coordinate.
WORLD_ENTITIES: [dynamic]World_Entity

Furniture_Kind :: enum {
	Dining_Table,
	Chair,
	Sofa,
	Coffee_Table,
	Bookcase,
	Desk,
	Bed,
	Plant,
	Side_Table,
}
Room_Surface :: enum {
	Dining,
	Study,
	Gallery,
	Pantry,
	Garden,
}
WALL_COVERING_PATHS := [Room_Surface]string {
	.Dining  = "assets/materials/wall-coverings/interior/02-ivory-art-deco.png",
	.Study   = "assets/materials/wall-coverings/interior/01-forest-herringbone.png",
	.Gallery = "assets/materials/wall-coverings/interior/03-blue-gray-plaster.png",
	.Pantry  = "assets/materials/wall-coverings/interior/04-ochre-wheat.png",
	.Garden  = "assets/materials/wall-coverings/interior/09-limestone-plaster.png",
}
FLOOR_COVERING_PATHS := [Room_Surface]string {
	.Dining  = "assets/materials/floor-coverings/interior/01-walnut-herringbone.png",
	.Study   = "assets/materials/floor-coverings/interior/02-honey-oak-planks.png",
	.Gallery = "assets/materials/floor-coverings/interior/03-slate-flagstone.png",
	.Pantry  = "assets/materials/floor-coverings/interior/04-encaustic-star-tile.png",
	.Garden  = "assets/yard-textures/yard-flagstone.png",
}
YARD_GRASS_TEXTURE_PATH :: "assets/yard-textures/yard-grass.png"
YARD_GRAVEL_TEXTURE_PATH :: "assets/yard-textures/yard-gravel.png"
YARD_DIRT_TEXTURE_PATH :: "assets/yard-textures/yard-dirt.png"
YARD_FLAGSTONE_TEXTURE_PATH :: "assets/yard-textures/yard-flagstone.png"
ROOF_TEXTURE_PATH :: "assets/materials/roof-coverings/01-slate-asphalt-shingles.png"
EXTERIOR_WALL_TEXTURE_PATH :: "assets/materials/exterior/01-limestone-cedar-stucco.png"
DOOR_TEXTURE_PATHS := [Door_Material]string {
	.Oak     = "assets/materials/doors/oak.png",
	.Painted = "assets/materials/doors/painted.png",
	.Walnut  = "assets/materials/doors/walnut.png",
}
FURNITURE_PATHS := [Furniture_Kind]string {
	.Dining_Table = "assets/kenney_furniture-kit/Models/GLTF format/tableCloth.glb",
	.Chair        = "assets/kenney_furniture-kit/Models/GLTF format/chairCushion.glb",
	.Sofa         = "assets/kenney_furniture-kit/Models/GLTF format/loungeSofa.glb",
	.Coffee_Table = "assets/kenney_furniture-kit/Models/GLTF format/tableCoffee.glb",
	.Bookcase     = "assets/kenney_furniture-kit/Models/GLTF format/bookcaseOpen.glb",
	.Desk         = "assets/kenney_furniture-kit/Models/GLTF format/desk.glb",
	.Bed          = "assets/kenney_furniture-kit/Models/GLTF format/bedDouble.glb",
	.Plant        = "assets/kenney_furniture-kit/Models/GLTF format/pottedPlant.glb",
	.Side_Table   = "assets/kenney_furniture-kit/Models/GLTF format/sideTableDrawers.glb",
}
Furniture :: struct {
	x, y, height, radius: f32,
	kind:                 Furniture_Kind,
	tint:                 [4]u8,
	yaw, elevation:       f32,
}
// A grounds cell is an intentional interior-exterior: it belongs to the lot
// and pathfinding plan, but is open to the sky and receives exterior dressing.
Plan_Space_Kind :: enum {
	Interior,
	Grounds,
}
Opening_Kind :: enum {
	Door,
	Window,
}
Plan_Opening :: struct {
	a, b:                               Vec2,
	kind:                               Opening_Kind,
	id:                                 string,
	height, sill_height, wall_width:    f32,
	door_material:                      Door_Material,
	door_style:                         Door_Style,
	window_style:                       Window_Style,
	window_flipped, window_hinge_right: bool,
}
// Paint remains data on the logical wall section, not on a renderer mesh. This
// lets render chunks be rebuilt or merged freely while each side stays editable.
Wall_Face_Paint :: struct {
	a, b:     Vec2,
	positive: bool,
	surface:  Room_Surface,
}
Build_Command_Kind :: enum {
	Create_Room,
	Set_Wall,
	Place_Opening,
	Paint_Room,
	Set_Space_Kind,
	Paint_Wall_Side,
	Place_Object,
	Move_Object,
	Delete_Object,
}
Build_Command :: struct {
	kind:      Build_Command_Kind,
	a, b:      Vec2,
	surface:   Room_Surface,
	space:     Plan_Space_Kind,
	opening:   Opening_Kind,
	furniture: Furniture,
	index:     int,
}
Build_Snapshot :: struct {
	wall_splines:     [dynamic]Floorplan_Spline,
	openings:         [dynamic]Plan_Opening,
	wall_face_paints: [dynamic]Wall_Face_Paint,
	furniture:        [dynamic]Furniture,
	surfaces:         [HOUSE_SURFACE_CELLS]Room_Surface,
	space_kinds:      [HOUSE_SURFACE_CELLS]Plan_Space_Kind,
	revision:         int,
}
House_Plan :: struct {
	level:                  int,
	wall_splines:           [dynamic]Floorplan_Spline,
	openings:               [dynamic]Plan_Opening,
	wall_face_paints:       [dynamic]Wall_Face_Paint,
	furniture:              [dynamic]Furniture,
	surfaces:               [HOUSE_SURFACE_CELLS]Room_Surface,
	space_kinds:            [HOUSE_SURFACE_CELLS]Plan_Space_Kind,
	initialized:            bool,
	validation:             string,
	revision:               int,
	dirty:                  bool,
	undo, redo:             [16]Build_Snapshot,
	undo_count, redo_count: int,
}
house_plan: House_Plan
furniture_meshes: [Furniture_Kind]Glb_Mesh
catalog_object_meshes: [dynamic]Glb_Mesh
catalog_thumbnail_floor, vehicle_skid_mesh: Glb_Mesh
PICTURE_FRAME_PATHS := [5]string {
	"assets/materials/picture-frames/frame-walnut-9slice.png",
	"assets/materials/picture-frames/frame-gilded-baroque-9slice.png",
	"assets/materials/picture-frames/frame-black-lacquer-9slice.png",
	"assets/materials/picture-frames/frame-aged-bronze-9slice.png",
	"assets/materials/picture-frames/frame-painted-ivory-9slice.png",
}

catalog_furniture_kind :: proc(id: string) -> (Furniture_Kind, bool) {switch id {case "plant":
		return .Plant, true; case "dining_table":
		return .Dining_Table, true; case "chair":
		return .Chair, true; case "sofa":
		return .Sofa, true; case "coffee_table":
		return .Coffee_Table, true; case "bookcase":
		return .Bookcase, true; case "desk":
		return .Desk, true; case "bed":
		return .Bed, true; case "side_table":
		return .Side_Table, true}; return {}, false}
catalog_object_mesh :: proc(id: string) -> (^Glb_Mesh, bool) {for 	&entry in editor_catalog.entries {if entry.kind != .Object || entry.id != id || entry.mesh_index < 0 || entry.mesh_index >= len(catalog_object_meshes) do continue
		mesh := &catalog_object_meshes[entry.mesh_index]
		return mesh, mesh.ready}
	return nil, false}
catalog_object_height :: proc(mesh: ^Glb_Mesh) -> f32 {if mesh == nil do return 1; return max(
		mesh.max.y - mesh.min.y,
		.001,
	)}

catalog_object_render_height :: proc(mesh: ^Glb_Mesh, entry: ^Catalog_Entry) -> f32 {
	height := catalog_object_height(mesh)
	if entry == nil do return height
	if entry.dimensions.y > 0 do return entry.dimensions.y
	return height * catalog_model_unit_scale(entry.model)
}

load_catalog_object_meshes :: proc() {
	frame_textures: [5]Glb_Texture_Data; for path, i in PICTURE_FRAME_PATHS do frame_textures[i] = load_room_texture(path)
	catalog_object_meshes = make(
		[dynamic]Glb_Mesh,
		0,
		len(editor_catalog.entries),
	); for &entry in editor_catalog.entries {if entry.kind != .Object do continue; entry.mesh_index = -1; if !entry.valid do continue; mesh: Glb_Mesh; ok := false; if entry.image != "" {texture := load_room_texture(entry.image); if len(texture.pixels) > 0 {aspect := f32(texture.width) / f32(max(texture.height, 1)); height := f32(1.35); width := clamp(height * aspect, .45, 1.8); frame_index := painting_frame_index(entry.id); mesh = procedural_picture_mesh(width, height, texture, frame_textures[frame_index]); ok = true}} else {mesh, ok = glb_load(entry.model)}; if !ok || !mesh.ready {entry.valid = false; continue}; entry.mesh_index = len(catalog_object_meshes); append(&catalog_object_meshes, mesh)}
}

painting_frame_index :: proc(id: string) -> int {
	// Give the initial collection one example of every frame style. Any later
	// paintings still receive a stable style derived from their catalog id.
	if strings.contains(id, "van_gogh") do return 0
	if strings.contains(id, "botticelli") do return 1
	if strings.contains(id, "vermeer") do return 2
	if strings.contains(id, "friedrich") do return 3
	if strings.contains(id, "hokusai") do return 4
	hash: u32 = 2166136261; for ch in id {hash = (hash ~ u32(ch)) * 16777619}; return int(hash % u32(len(PICTURE_FRAME_PATHS)))
}
house_floor_mesh, house_art_mesh, house_art_frame_mesh, house_window_mesh: Glb_Mesh
bloodstain_mesh, drag_trace_mesh: Glb_Mesh
case_statuette_mesh, case_cane_mesh, case_ledger_mesh, case_cloth_mesh, case_oil_mesh, case_watch_mesh, case_wastebin_mesh, case_rug_unfolded_mesh, case_rug_folded_mesh: Glb_Mesh
house_door_meshes: [Door_Material]Glb_Mesh
house_window_sill_mesh, house_window_header_mesh, house_window_sill_interior_mesh, house_window_header_interior_mesh, house_window_header_cap_mesh, house_window_frame_h_mesh, house_window_frame_v_mesh, house_window_muntin_h_mesh, house_window_muntin_v_mesh, house_window_bead_h_mesh, house_window_bead_v_mesh, house_window_hardware_h_mesh, house_window_hardware_v_mesh, house_window_sill_cap_mesh, house_window_exterior_sill_mesh, house_window_head_return_mesh, house_window_jamb_return_mesh, house_shutter_slat_mesh, house_wall_junction_reveal_mesh, house_wall_cap_edge_mesh, house_wall_cap_edge_interior_mesh: Glb_Mesh

house_opening_sill_mesh :: proc(opening: Plan_Opening) -> ^Glb_Mesh {if house_wall_width(opening.wall_width) <= HOUSE_INTERIOR_WALL_THICKNESS + .001 do return &house_window_sill_interior_mesh
	return &house_window_sill_mesh}
house_opening_header_mesh :: proc(opening: Plan_Opening) -> ^Glb_Mesh {if house_wall_width(opening.wall_width) <= HOUSE_INTERIOR_WALL_THICKNESS + .001 do return &house_window_header_interior_mesh
	return &house_window_header_mesh}
house_opening_cap_edge_mesh :: proc(opening: Plan_Opening) -> ^Glb_Mesh {if house_wall_width(opening.wall_width) <= HOUSE_INTERIOR_WALL_THICKNESS + .001 do return &house_wall_cap_edge_interior_mesh
	return &house_wall_cap_edge_mesh}
house_wall_cap_edge_mesh_for_width :: proc(width: f32) -> ^Glb_Mesh {if house_wall_width(width) <= HOUSE_INTERIOR_WALL_THICKNESS + .001 do return &house_wall_cap_edge_interior_mesh
	return &house_wall_cap_edge_mesh}
shutter_crank_housing_mesh, shutter_crank_arm_mesh, shutter_crank_link_mesh, shutter_crank_grip_mesh, shutter_silk_mesh: Glb_Mesh
house_floor_materials: [Room_Surface]Glb_Mesh
house_floor_batches: [Plan_Space_Kind][Room_Surface]Glb_Mesh
house_wall_materials: [Room_Surface]Glb_Texture_Data
// Each wall piece owns a neutral structural core plus independently materialed
// faces. A shared wall therefore belongs visually to the room on either side.
Floorplan_Wall :: struct {
	a, b:                                    Vec2,
	width:                                   f32,
	positive_surface, negative_surface:      Room_Surface,
	positive_interior, negative_interior:    bool,
	core, cap, face_positive, face_negative: Glb_Mesh,
	core_bands:                              [3]Glb_Mesh,
}
house_walls: [dynamic]Floorplan_Wall
// Structural runs share mitered vertices at a spline corner. The per-section
// face meshes remain separate so either side can still be painted independently.
house_wall_runs, house_wall_runs_full: [dynamic]Glb_Mesh
house_wall_face_batches, house_wall_face_batches_full: [Room_Surface]Glb_Mesh
house_wall_cap_batch_full: Glb_Mesh
// Derived once from the editable splines. This is the only structural wall
// render mesh: regularized union removes prism overlaps and miter seams.
house_wall_solid, house_wall_solid_cutaway, house_wall_cap_union, house_wall_cap_union_edge: Glb_Mesh
GENERATED_ROOF_CAPACITY :: 32
generated_roof_meshes: [GENERATED_ROOF_CAPACITY]Glb_Mesh
generated_roof_base_y: [GENERATED_ROOF_CAPACITY]f32
generated_roof_story: [GENERATED_ROOF_CAPACITY]int
generated_roof_style: [GENERATED_ROOF_CAPACITY]Level_Roof_Style
generated_roof_gutter_meshes: [GENERATED_ROOF_CAPACITY]Glb_Mesh
generated_roof_has_gutters: [GENERATED_ROOF_CAPACITY]bool
generated_roof_count: int
generated_roof_revision, generated_roof_gpu_revision: u64
GENERATED_LINK_CAPACITY :: 32
generated_link_meshes: [GENERATED_LINK_CAPACITY]Glb_Mesh
generated_link_base_y: [GENERATED_LINK_CAPACITY]f32
generated_link_story: [GENERATED_LINK_CAPACITY]int
generated_link_count: int
generated_link_revision, generated_link_gpu_revision: u64
GENERATED_GROUND_CAPACITY :: 32
generated_water_meshes, generated_path_meshes: [GENERATED_GROUND_CAPACITY]Glb_Mesh
generated_water_count, generated_path_count: int
generated_ground_revision, generated_ground_gpu_revision: u64
yard_grass_texture, yard_gravel_texture, yard_dirt_texture, yard_flagstone_texture: Glb_Texture_Data
roof_texture, exterior_wall_texture: Glb_Texture_Data
TERRAIN_CHUNK_CELLS :: 8
GENERATED_TERRAIN_CAPACITY :: 64
generated_terrain_meshes: [GENERATED_TERRAIN_CAPACITY]Glb_Mesh
generated_terrain_dirty: [GENERATED_TERRAIN_CAPACITY]bool
generated_terrain_count: int
GENERATED_STORY_CAPACITY :: 128
generated_story_slab_meshes, generated_story_wall_meshes: [GENERATED_STORY_CAPACITY]Glb_Mesh
generated_foundation_meshes: [GENERATED_STORY_CAPACITY]Glb_Mesh
generated_story_slab_story, generated_story_wall_story: [GENERATED_STORY_CAPACITY]int
generated_story_slab_base_y, generated_story_wall_base_y: [GENERATED_STORY_CAPACITY]f32
generated_story_slab_count, generated_story_wall_count, generated_foundation_count: int
generated_story_revision, generated_story_gpu_revision: u64
house_derived_wall_segments: [dynamic][2]Vec2
Personal_Surface_Draw :: struct {
	mesh:                                        Glb_Mesh,
	x, z, yaw, base, region_base, region_height: f32,
	wall_index:                                  int,
	tint:                                        [4]u8,
}
personal_floor_draws, personal_ceiling_draws, wall_finish_draws: [dynamic]Personal_Surface_Draw

catalog_material_entry :: proc(id: string) -> (^Catalog_Entry, bool) {resolved :=
		catalog_resolve_id(id)
	for &entry in editor_catalog.entries do if entry.kind == .Material && entry.id == resolved do return &entry, true
	return nil, false}
material_floor_uv_scale :: proc(entry: ^Catalog_Entry) -> f32 {if entry != nil && entry.floor_repeat_m > 0 do return 1 / entry.floor_repeat_m
	return .2}
material_wall_uv_scale :: proc(entry: ^Catalog_Entry) -> f32 {if entry != nil && entry.wall_repeat_m > 0 do return 1 / entry.wall_repeat_m
	return HOUSE_WALL_COVERING_UV_SCALE}
mesh_rescale_uvs :: proc(mesh: ^Glb_Mesh, ratio: f32) {if math.abs(ratio - 1) < .00001 do return
	for &uv in mesh.texcoords {uv.x *= ratio; uv.y *= ratio}}
surface_draws_rescale_uvs :: proc(
	draws: ^[dynamic]Personal_Surface_Draw,
	first: int,
	ratio: f32,
) {for i in first ..< len(draws) do mesh_rescale_uvs(&draws[i].mesh, ratio)}
surface_draws_set_tint :: proc(
	draws: ^[dynamic]Personal_Surface_Draw,
	first: int,
	tint: [4]u8,
) {for i in first ..< len(draws) do draws[i].tint = tint}
room_material_at :: proc(doc: ^Level_Document, point: Vec2, wall: bool) -> string {for room in doc.rooms do if room.story == doc.active_story && level_point_in_polygon(point, room.points[:]) do return wall ? room.wall_material : room.floor_material
	return ""}
room_tint_at :: proc(doc: ^Level_Document, point: Vec2, wall: bool) -> [4]u8 {for room in doc.rooms do if room.story == doc.active_story && level_point_in_polygon(point, room.points[:]) {tint := wall ? room.wall_tint : room.floor_tint; if tint[3] == 0 do return {255, 255, 255, 255}; return tint}
	return{255, 255, 255, 255}}
house_opening_host_wall_index :: proc(opening: Plan_Opening) -> int {odx, odz :=
		opening.b.x - opening.a.x, opening.b.y - opening.a.y
	opening_length := f32(math.sqrt(f64(odx * odx + odz * odz)))
	if opening_length <= .001 do return -1
	mx, mz := (opening.a.x + opening.b.x) * .5, (opening.a.y + opening.b.y) * .5
	best_index := -1
	best := f32(1e30)
	for 	wall, i in house_walls {wdx, wdz := wall.b.x - wall.a.x, wall.b.y - wall.a.y; wall_length := f32(
			math.sqrt(f64(wdx * wdx + wdz * wdz)),
		)
		if wall_length <= .001 do continue
		parallel := math.abs((odx * wdz - odz * wdx) / (opening_length * wall_length))
		if parallel > .01 do continue
		line_distance := math.abs((mx - wall.a.x) * wdz - (mz - wall.a.y) * wdx) / wall_length
		if line_distance > .08 do continue
		pairs := [4][2]Vec2 {
			{opening.a, wall.a},
			{opening.a, wall.b},
			{opening.b, wall.a},
			{opening.b, wall.b},
		}
		for 		pair in pairs {dx, dz := pair[0].x - pair[1].x, pair[0].y - pair[1].y; distance :=
				dx * dx + dz * dz
			if distance < best {best = distance; best_index = i}}}
	return best_index}

house_wall_endpoint_is_junction :: proc(wall_index: int, point: Vec2) -> bool {
	if wall_index < 0 || wall_index >= len(house_walls) do return false
	wall :=
		house_walls[wall_index]; dx, dz := wall.b.x - wall.a.x, wall.b.y - wall.a.y; length := f32(math.sqrt(f64(dx * dx + dz * dz))); if length <= .001 do return false
	for other, other_index in house_walls {if other_index == wall_index do continue
		shared := level_points_near(point, other.a) || level_points_near(point, other.b)
		if !shared do continue
		odx, odz := other.b.x - other.a.x, other.b.y - other.a.y
		other_length := f32(math.sqrt(f64(odx * odx + odz * odz)))
		if other_length <= .001 do continue
		// Collinear neighbors are opening/run splits. Extending their finish would
		// paint back across the aperture. Only actual L/T wall junctions need to
		// follow the square-capped structural union beyond the authored endpoint.
		if math.abs((dx * odz - dz * odx) / (length * other_length)) > .01 do return true
	}
	return false
}

house_exterior_wall_finish_span :: proc(wall_index: int) -> (Vec2, Vec2) {
	wall :=
		house_walls[wall_index]; a, b := wall.a, wall.b; dx, dz := b.x - a.x, b.y - a.y; length := f32(math.sqrt(f64(dx * dx + dz * dz))); if length <= .001 do return a, b
	tx, tz := dx / length, dz / length; extension := wall.width * .5
	if house_wall_endpoint_is_junction(wall_index, a) do a = {a.x - tx * extension, a.y - tz * extension}
	if house_wall_endpoint_is_junction(wall_index, b) do b = {b.x + tx * extension, b.y + tz * extension}
	return a, b
}

rebuild_personal_surfaces :: proc(doc: ^Level_Document) {
	personal_floor_draws = make(
		[dynamic]Personal_Surface_Draw,
		0,
		16,
	); personal_ceiling_draws = make([dynamic]Personal_Surface_Draw, 0, 16); wall_finish_draws = make([dynamic]Personal_Surface_Draw, 0, 192)
	base := doc.stories[doc.active_story].base_elevation
	for room in doc.rooms {if room.story != doc.active_story do continue; mesh := procedural_room_slab_mesh(room); if !mesh.ready do continue; cx, cz := (mesh.min.x + mesh.max.x) * .5, (mesh.min.z + mesh.max.z) * .5
		// Ceilings are an interior surface, independent of the exterior roof. Open
		// and exterior rooms intentionally retain their view of the sky.
		if !room.exterior &&
		   room.ceiling_style !=
			   "open" {ceiling := procedural_room_ceiling_mesh(room); if ceiling.ready do append(&personal_ceiling_draws, Personal_Surface_Draw{mesh = ceiling, x = cx, z = cz, base = base + doc.stories[doc.active_story].wall_height - .015})}
		entry, found := catalog_material_entry(
			room.floor_material,
		); if !found || entry.floor == "" do continue; texture := load_room_texture(entry.floor); if len(texture.pixels) == 0 do continue; mesh_rescale_uvs(&mesh, material_floor_uv_scale(entry) / .2); apply_texture(&mesh, texture); slab_height := max(mesh.max.y - mesh.min.y, .001); floor_tint := room.floor_tint; if floor_tint[3] == 0 do floor_tint = {255, 255, 255, 255}; append(&personal_floor_draws, Personal_Surface_Draw{mesh = mesh, x = cx, z = cz, base = base + .02 - slab_height, tint = floor_tint})}
	for wall, wall_index in house_walls {dx, dz := wall.b.x - wall.a.x, wall.b.y - wall.a.y
		length := f32(math.sqrt(f64(dx * dx + dz * dz)))
		if length <= .01 do continue
		mx, mz := (wall.a.x + wall.b.x) * .5, (wall.a.y + wall.b.y) * .5
		nx, nz := -dz / length, dx / length
		yaw := f32(math.atan2(f64(dz), f64(dx)))
		for side in 0 ..< 2 {positive := side == 0; interior := positive ? wall.positive_interior : wall.negative_interior; sign := positive ? f32(1) : f32(-1); texture := exterior_wall_texture; finish_tint := [4]u8{255, 255, 255, 255}; uv_scale := HOUSE_WALL_COVERING_UV_SCALE; face_lift := f32(.0005); if interior {sample := Vec2{mx + nx * .24 * sign, mz + nz * .24 * sign}; material := room_material_at(doc, sample, true); finish_tint = room_tint_at(doc, sample, true); surface := positive ? wall.positive_surface : wall.negative_surface; texture = house_wall_materials[surface]; entry, found := catalog_material_entry(material); if found {uv_scale = material_wall_uv_scale(entry); if entry.wall != "" {candidate := load_room_texture(entry.wall); if len(candidate.pixels) > 0 do texture = candidate}}; face_lift = .004}; if len(texture.pixels) == 0 do continue; finish_a, finish_b := wall.a, wall.b; finish_mx, finish_mz := mx, mz; if !interior {finish_a, finish_b = house_exterior_wall_finish_span(wall_index); finish_mx, finish_mz = (finish_a.x + finish_b.x) * .5, (finish_a.y + finish_b.y) * .5}; offset := wall.width * .5 + face_lift; before := len(wall_finish_draws); append_wallpaper_band_draws(&wall_finish_draws, finish_a, finish_b, finish_mx + nx * offset * sign, finish_mz + nz * offset * sign, yaw + (positive ? 0 : f32(math.PI)), texture, base, wall_index); surface_draws_rescale_uvs(&wall_finish_draws, before, uv_scale / HOUSE_WALL_COVERING_UV_SCALE); surface_draws_set_tint(&wall_finish_draws, before, finish_tint)}
	}
	for opening in house_plan.openings {
		dx, dz :=
			opening.b.x -
			opening.a.x,
			opening.b.y -
			opening.a.y; length := f32(math.sqrt(f64(dx * dx + dz * dz))); if length <= .01 do continue
		mx, mz :=
			(opening.a.x + opening.b.x) *
			.5,
			(opening.a.y + opening.b.y) *
			.5; host_wall := house_opening_host_wall_index(opening); nx, nz := -dz / length, dx / length
		for side in 0 ..< 2 {
			positive :=
				side ==
				0; sign := positive ? f32(1) : f32(-1); sample := Vec2{mx + nx * .24 * sign, mz + nz * .24 * sign}; surface, interior := house_wall_face_classification(opening.a, opening.b, positive)
			// Structural aperture infill is intentionally opaque. Reapply the actual
			// finish on both faces: room covering inside, continuous siding outside.
			texture :=
				interior ? house_wall_materials[surface] : exterior_wall_texture; finish_tint := interior ? room_tint_at(doc, sample, true) : [4]u8{255, 255, 255, 255}; uv_scale := HOUSE_WALL_COVERING_UV_SCALE
			if interior {material := room_material_at(doc, sample, true); entry, found := catalog_material_entry(material); if found {uv_scale = material_wall_uv_scale(entry); if entry.wall != "" {candidate := load_room_texture(entry.wall); if len(candidate.pixels) > 0 do texture = candidate}}}
			finish_opening :=
				interior ? opening : house_exterior_opening_finish_span(opening); finish_lift := interior ? f32(.004) : f32(.0005); before := len(wall_finish_draws); if opening.kind == .Window {append_window_wallpaper_draws(&wall_finish_draws, finish_opening, positive, texture, base, finish_lift); if !interior {sign := positive ? f32(1) : f32(-1); offset := house_opening_face_offset(opening, finish_lift); yaw := f32(math.atan2(f64(dz), f64(dx))) + (positive ? 0 : f32(math.PI)); sill := opening.sill_height > 0 ? opening.sill_height : f32(.72); jamb_height := (opening.height > 0 ? opening.height : f32(1.4)) + .08; shoulders := [2][2]Vec2{{finish_opening.a, opening.a}, {opening.b, finish_opening.b}}; for shoulder in shoulders {sx, sz := (shoulder[0].x + shoulder[1].x) * .5, (shoulder[0].y + shoulder[1].y) * .5; append_wallpaper_region_band_draws(&wall_finish_draws, shoulder[0], shoulder[1], sx + nx * offset * sign, sz + nz * offset * sign, yaw, texture, base, sill - .04, jamb_height, host_wall)}}} else {append_door_wallpaper_header_draw(&wall_finish_draws, finish_opening, positive, texture, base, finish_lift)}; surface_draws_rescale_uvs(&wall_finish_draws, before, uv_scale / HOUSE_WALL_COVERING_UV_SCALE); surface_draws_set_tint(&wall_finish_draws, before, finish_tint); for i in before ..< len(wall_finish_draws) do wall_finish_draws[i].wall_index = host_wall
		}
	}
}

procedural_room_slab_mesh :: proc(room: Level_Room) -> Glb_Mesh {
	m: Glb_Mesh; count := len(room.points); if count < 3 do return m; m.vertices = make([dynamic]Vec3, 0, count * 2); m.texcoords = make([dynamic]Vec2, 0, count * 2); m.indices = make([dynamic]u32, 0, count * 12); m.primitives = make([dynamic]Glb_Primitive_Range, 0, 1); thickness := f32(.18)
	for p in room.points {append(&m.vertices, Vec3{p.x, 0, p.y}); append(&m.texcoords, Vec2{p.x * .2, p.y * .2})}; for p in room.points {append(&m.vertices, Vec3{p.x, -thickness, p.y}); append(&m.texcoords, Vec2{p.x * .2, p.y * .2})}
	area := level_polygon_area(
		room.points[:],
	); winding: f32 = area >= 0 ? 1 : -1; remaining := make([dynamic]int, 0, count); defer delete(remaining); for i in 0 ..< count do append(&remaining, i); guard := 0
	for len(remaining) > 2 &&
	    guard <
		    count *
			    count {clipped := false; for cursor in 0 ..< len(remaining) {previous := remaining[(cursor + len(remaining) - 1) % len(remaining)]; current := remaining[cursor]; next := remaining[(cursor + 1) % len(remaining)]; if wall_cap_cross(room.points[previous], room.points[current], room.points[next]) * winding <= .000001 do continue; occupied := false; for candidate in remaining {if candidate == previous || candidate == current || candidate == next do continue; if wall_cap_contains(room.points[candidate], room.points[previous], room.points[current], room.points[next], winding) {occupied = true; break}}; if occupied do continue; roof_add_triangle(&m, u32(previous), u32(current), u32(next)); ordered_remove(&remaining, cursor); clipped = true; break}; if !clipped do break; guard += 1}
	for i in 0 ..< count {j := (i + 1) % count; base := u32(len(m.vertices)); a, b := room.points[i], room.points[j]; append(&m.vertices, Vec3{a.x, 0, a.y}, Vec3{b.x, 0, b.y}, Vec3{b.x, -thickness, b.y}, Vec3{a.x, -thickness, a.y}); append(&m.texcoords, Vec2{0, 0}, Vec2{1, 0}, Vec2{1, 1}, Vec2{0, 1}); roof_add_triangle(&m, base, base + 1, base + 2); roof_add_triangle(&m, base, base + 2, base + 3)}
	m.min = {
		1e30,
		-thickness,
		1e30,
	}; m.max = {-1e30, .001, -1e30}; for v in m.vertices {m.min.x = min(m.min.x, v.x); m.min.z = min(m.min.z, v.z); m.max.x = max(m.max.x, v.x); m.max.z = max(m.max.z, v.z)}; surface := level_material_surface(room.floor_material); color := [4]f32{.52, .56, .58, 1}; #partial switch surface {case .Dining:
		color = {.55, .43, .30, 1}; case .Study:
		color = {.32, .43, .37, 1}; case .Gallery:
		color = {.38, .45, .52, 1}; case .Pantry:
		color = {.53, .49, .36, 1}; case .Garden:
		color = {
			.29,
			.45,
			.32,
			1,
		}}; append(&m.primitives, Glb_Primitive_Range{0, len(m.indices), -1, color}); m.ready = len(m.indices) > 0; return m
}

procedural_room_ceiling_mesh :: proc(room: Level_Room) -> Glb_Mesh {
	slab := procedural_room_slab_mesh(
		room,
	); m: Glb_Mesh; count := len(room.points); if !slab.ready || count < 3 do return m
	m.vertices = make(
		[dynamic]Vec3,
		0,
		count,
	); m.texcoords = make([dynamic]Vec2, 0, count); m.indices = make([dynamic]u32, 0, max((count - 2) * 3, 0)); m.primitives = make([dynamic]Glb_Primitive_Range, 0, 1)
	for i in 0 ..< count {append(&m.vertices, slab.vertices[i]); append(&m.texcoords, slab.texcoords[i])}
	// The slab's first triangles form its upward-facing floor. Reverse only those
	// triangles to author a downward-facing ceiling; slab edge walls do not belong
	// to the ceiling surface.
	for i := 0;
	    i + 2 < len(slab.indices);
	    i += 3 {a, b, c := slab.indices[i], slab.indices[i + 1], slab.indices[i + 2]; if a >= u32(count) || b >= u32(count) || c >= u32(count) do break; append(&m.indices, a, c, b)}
	m.min = {
		1e30,
		0,
		1e30,
	}; m.max = {-1e30, .001, -1e30}; for v in m.vertices {m.min.x = min(m.min.x, v.x); m.min.z = min(m.min.z, v.z); m.max.x = max(m.max.x, v.x); m.max.z = max(m.max.z, v.z)}
	append(
		&m.primitives,
		Glb_Primitive_Range{0, len(m.indices), -1, {.87, .86, .82, 1}},
	); m.ready = len(m.indices) > 0; return m
}

procedural_foundation_mesh :: proc(
	doc: ^Level_Document,
	foundation: Level_Foundation,
) -> Glb_Mesh {
	room := Level_Room {
		points         = foundation.points,
		floor_material = "foundation",
	}; m := procedural_room_slab_mesh(
		room,
	); if !m.ready do return m; count := len(foundation.points); top := foundation.elevation - .025; depth := max(foundation.depth, .25)
	for i in 0 ..< count {m.vertices[i].y = top; m.vertices[count + i].y = foundation.kind == .Raised ? level_terrain_height(doc, foundation.points[i]) : foundation.elevation - depth}
	m.min = {
		1e30,
		1e30,
		1e30,
	}; m.max = {-1e30, -1e30, -1e30}; for vertex in m.vertices {m.min.x = min(m.min.x, vertex.x); m.min.y = min(m.min.y, vertex.y); m.min.z = min(m.min.z, vertex.z); m.max.x = max(m.max.x, vertex.x); m.max.y = max(m.max.y, vertex.y); m.max.z = max(m.max.z, vertex.z)}; if m.max.y - m.min.y < .001 do m.max.y = m.min.y + .001; m.primitives[0].base_color = foundation.kind == .Basement ? [4]f32{.30, .32, .35, 1} : foundation.kind == .Raised ? [4]f32{.46, .43, .38, 1} : [4]f32{.42, .44, .43, 1}; return m
}

wall_segments_same :: proc(a, b, c, d: Vec2) -> bool {return(
		level_points_near(a, c) && level_points_near(b, d) ||
		level_points_near(a, d) && level_points_near(b, c) \
	)}
derived_wall_append :: proc(segments: ^[dynamic][2]Vec2, a, b: Vec2) {if level_points_near(a, b) do return
	for segment in segments^ do if wall_segments_same(a, b, segment[0], segment[1]) do return
	append(segments, [2]Vec2{a, b})}
rebuild_house_wall_splines :: proc(doc: ^Level_Document, story: int) {
	// Authored paths are the wall plan: they preserve deliberate corner order,
	// opening hosts, and the construction width selected for every run.
	clear(
		&house_plan.wall_splines,
	); for &path in doc.paths {if path.story != story || path.kind != .Wall && path.kind != .Freestanding_Wall && path.kind != .Half_Wall && path.kind != .Fence do continue; append(&house_plan.wall_splines, Floorplan_Spline{points = path.points[:], width = house_wall_width(path.width)})}
}

rebuild_generated_stories :: proc(doc: ^Level_Document) {
	generated_foundation_count = 0; for foundation in doc.foundations {if generated_foundation_count >= GENERATED_STORY_CAPACITY do break; mesh := procedural_foundation_mesh(doc, foundation); if mesh.ready {generated_foundation_meshes[generated_foundation_count] = mesh; generated_foundation_count += 1}}
	generated_story_slab_count = 0; for room in doc.rooms {if generated_story_slab_count >= GENERATED_STORY_CAPACITY do break; mesh := procedural_room_slab_mesh(room); if !mesh.ready do continue; index := generated_story_slab_count; generated_story_slab_meshes[index] = mesh; generated_story_slab_story[index] = room.story; base := room.platform_height; if room.story >= 0 && room.story < len(doc.stories) do base += doc.stories[room.story].base_elevation; generated_story_slab_base_y[index] = base; generated_story_slab_count += 1}
	// Walls are authored paths. Rooms own surfaces and enclosure metadata, but
	// never synthesize a second wall plan with competing dimensions.
	generated_story_wall_count = 0; for path in doc.paths {if path.kind != .Wall && path.kind != .Freestanding_Wall && path.kind != .Half_Wall && path.kind != .Fence do continue; if generated_story_wall_count >= GENERATED_STORY_CAPACITY do break; height := f32(2.5); if path.story >= 0 && path.story < len(doc.stories) do height = doc.stories[path.story].wall_height; if path.kind == .Half_Wall do height = 1.15; if path.kind == .Fence do height = 1; mesh := procedural_wall_run_mesh(path.points[:], height, house_wall_width(path.width)); if !mesh.ready do continue; index := generated_story_wall_count; generated_story_wall_meshes[index] = mesh; generated_story_wall_story[index] = path.story; base := f32(0); if path.story >= 0 && path.story < len(doc.stories) do base = doc.stories[path.story].base_elevation; generated_story_wall_base_y[index] = base; generated_story_wall_count += 1}; generated_story_revision = doc.revision
}

procedural_path_mesh :: proc(doc: ^Level_Document, path: Level_Path) -> Glb_Mesh {
	m: Glb_Mesh; if len(path.points) < 2 do return m; m.vertices = make([dynamic]Vec3, 0, len(path.points) * 4); m.texcoords = make([dynamic]Vec2, 0, len(path.points) * 4); m.indices = make([dynamic]u32, 0, (len(path.points) - 1) * 6); m.primitives = make([dynamic]Glb_Primitive_Range, 0, 1)
	distance := f32(
		0,
	); for i in 0 ..< len(path.points) - 1 {a, b := path.points[i], path.points[i + 1]; dx, dy := b.x - a.x, b.y - a.y; length := f32(math.sqrt(f64(dx * dx + dy * dy))); if length < .001 do continue; nx, ny := -dy / length * path.width * .5, dx / length * path.width * .5; base := u32(len(m.vertices)); corners := [4]Vec2{{a.x + nx, a.y + ny}, {a.x - nx, a.y - ny}, {b.x - nx, b.y - ny}, {b.x + nx, b.y + ny}}; u0, u1 := distance / max(path.width, .5), (distance + length) / max(path.width, .5); for p, j in corners {append(&m.vertices, Vec3{p.x, level_terrain_height(doc, p) + .035, p.y}); append(&m.texcoords, Vec2{j < 2 ? u0 : u1, j == 0 || j == 3 ? 0 : 1})}; append(&m.indices, base, base + 2, base + 1, base, base + 3, base + 2); distance += length}
	if len(m.vertices) == 0 do return m; m.min = {1e30, 1e30, 1e30}; m.max = {-1e30, -1e30, -1e30}; for v in m.vertices {m.min.x = min(m.min.x, v.x); m.min.y = min(m.min.y, v.y); m.min.z = min(m.min.z, v.z); m.max.x = max(m.max.x, v.x); m.max.y = max(m.max.y, v.y); m.max.z = max(m.max.z, v.z)}; m.max.y = max(m.max.y, m.min.y + 1); color := path.kind == .Road ? [4]f32{.22, .24, .25, 1} : [4]f32{.58, .50, .38, 1}; append(&m.primitives, Glb_Primitive_Range{0, len(m.indices), -1, color}); m.ready = true; return m
}

yard_path_texture :: proc(material: string) -> Glb_Texture_Data {
	if strings.contains(material, "gravel") do return yard_gravel_texture
	if strings.contains(material, "dirt") do return yard_dirt_texture
	return yard_flagstone_texture
}

procedural_terrain_chunk_mesh :: proc(
	doc: ^Level_Document,
	start_x, start_y, end_x, end_y: int,
) -> Glb_Mesh {
	m: Glb_Mesh; if start_x >= end_x || start_y >= end_y do return m
	columns, rows :=
		end_x -
		start_x +
		1,
		end_y -
		start_y +
		1; m.vertices = make([dynamic]Vec3, 0, columns * rows); m.texcoords = make([dynamic]Vec2, 0, columns * rows); m.indices = make([dynamic]u32, 0, (columns - 1) * (rows - 1) * 6); m.primitives = make([dynamic]Glb_Primitive_Range, 0, 1); m.min = {f32(start_x), 1e30, f32(start_y)}; m.max = {f32(end_x), -1e30, f32(end_y)}
	for y in start_y ..= end_y {for x in start_x ..= end_x {height := level_terrain_sample(doc, x, y); append(&m.vertices, Vec3{f32(x), height, f32(y)}); append(&m.texcoords, Vec2{f32(x) * .125, f32(y) * .125}); m.min.y = min(m.min.y, height); m.max.y = max(m.max.y, height)}}
	for y in 0 ..< rows - 1 {for x in 0 ..< columns - 1 {
			cell := Vec2{f32(start_x + x) + .5, f32(start_y + y) + .5}; covered := false
			for foundation in doc.foundations {if level_foundation_contains_point(foundation, cell) {covered = true; break}}
			if !covered do for room in doc.rooms {if room.story == 0 && level_point_in_polygon(cell, room.points[:]) {covered = true; break}}
			// Keep terrain continuous beneath water. Culling whole grid cells against
			// the authored polygon left square holes wherever the visible, smoothed
			// shoreline curved back inside those cells. The opaque water and bank mesh
			// own the visible surface while the terrain safely fills its footprint.
			if covered do continue
			a := u32(
				y * columns + x,
			); b := a + 1; c := a + u32(columns); d := c + 1; append(&m.indices, a, d, b, a, c, d)
		}}
	if m.max.y - m.min.y < .001 do m.max.y = m.min.y + .001
	append(
		&m.primitives,
		Glb_Primitive_Range{0, len(m.indices), -1, {.32, .48, .31, 1}},
	); m.ready = len(m.indices) > 0; return m
}

pond_smooth_outline :: proc(points: []Vec2, iterations: int = 3) -> [dynamic]Vec2 {
	outline := make([dynamic]Vec2, 0, len(points), context.temp_allocator)
	append(&outline, ..points)
	for _ in 0 ..< iterations {
		next := make([dynamic]Vec2, 0, len(outline) * 2, context.temp_allocator)
		for point, i in outline {
			following := outline[(i + 1) % len(outline)]
			append(
				&next,
				Vec2{point.x * .75 + following.x * .25, point.y * .75 + following.y * .25},
				Vec2{point.x * .25 + following.x * .75, point.y * .25 + following.y * .75},
			)
		}
		outline = next
	}
	return outline
}

procedural_water_mesh :: proc(doc: ^Level_Document, water: Level_Water) -> Glb_Mesh {
	m: Glb_Mesh
	if len(water.points) < 3 do return m
	outline := pond_smooth_outline(water.points[:])
	count := len(outline)
	m.vertices = make([dynamic]Vec3, 0, count * 7)
	m.texcoords = make([dynamic]Vec2, 0, count * 7)
	m.indices = make([dynamic]u32, 0, count * 18)
	m.primitives = make([dynamic]Glb_Primitive_Range, 0, 3)
	center :=
		Vec2{}; for point in outline {center.x += point.x; center.y += point.y}; center.x /= f32(count); center.y /= f32(count)
	pond_radius := f32(
		.001,
	); for point in outline {dx, dy := point.x - center.x, point.y - center.y; pond_radius = max(pond_radius, f32(math.sqrt(f64(dx * dx + dy * dy))))}
	inner := make([dynamic]Vec2, 0, count, context.temp_allocator)
	for point in outline {toward := Vec2{center.x - point.x, center.y - point.y}
		distance := f32(math.sqrt(f64(toward.x * toward.x + toward.y * toward.y)))
		inset := min(.16, distance * .08)
		inner_point :=
			distance > .001 ? Vec2{point.x + toward.x / distance * inset, point.y + toward.y / distance * inset} : point
		append(&inner, inner_point)
		// The triangulated water ends at the inner edge of the shallow shelf.
		// Previously these vertices used the outer outline, causing the opaque
		// shelf to overlap the water as a bright decorative ring.
		append(&m.vertices, Vec3{inner_point.x, water.elevation, inner_point.y})
		append(
			&m.texcoords,
			Vec2 {
				.5 + (inner_point.x - center.x) / (pond_radius * 2),
				.5 + (inner_point.y - center.y) / (pond_radius * 2),
			},
		)
	}
	area := level_polygon_area(inner[:])
	winding: f32 = area >= 0 ? 1 : -1
	remaining := make([dynamic]int, 0, count, context.temp_allocator)
	for i in 0 ..< count do append(&remaining, i)
	guard := 0
	for len(remaining) > 2 && guard < count * count {
		clipped := false
		for cursor in 0 ..< len(remaining) {
			previous := remaining[(cursor + len(remaining) - 1) % len(remaining)]
			current := remaining[cursor]
			next := remaining[(cursor + 1) % len(remaining)]
			if wall_cap_cross(inner[previous], inner[current], inner[next]) * winding <= .000001 do continue
			occupied := false
			for candidate in remaining {
				if candidate == previous || candidate == current || candidate == next do continue
				if wall_cap_contains(
					inner[candidate],
					inner[previous],
					inner[current],
					inner[next],
					winding,
				) {occupied = true; break}
			}
			if occupied do continue
			roof_add_triangle(&m, u32(previous), u32(current), u32(next))
			ordered_remove(&remaining, cursor)
			clipped = true
			break
		}
		if !clipped do break
		guard += 1
	}
	water_index_count := len(m.indices)
	// A narrow submerged shelf bridges the water to the authored shoreline.
	// Extend it beneath the water plane instead of ending directly below the
	// water edge; the overlap prevents the underlying terrain from appearing as
	// a dark line at grazing camera angles.
	for point, i in outline {following := (i + 1) % count; following_point := outline[following]
		inner_a := inner[i]
		inner_b := inner[following]
		toward_a := Vec2{center.x - inner_a.x, center.y - inner_a.y}
		toward_b := Vec2{center.x - inner_b.x, center.y - inner_b.y}
		distance_a := f32(math.sqrt(f64(toward_a.x * toward_a.x + toward_a.y * toward_a.y)))
		distance_b := f32(math.sqrt(f64(toward_b.x * toward_b.x + toward_b.y * toward_b.y)))
		if distance_a >
		   .001 {inner_a.x += toward_a.x / distance_a * .06; inner_a.y += toward_a.y / distance_a * .06}
		if distance_b >
		   .001 {inner_b.x += toward_b.x / distance_b * .06; inner_b.y += toward_b.y / distance_b * .06}
		base := u32(len(m.vertices))
		append(
			&m.vertices,
			Vec3{point.x, water.elevation - .045, point.y},
			Vec3{following_point.x, water.elevation - .045, following_point.y},
			Vec3{inner_b.x, water.elevation - .010, inner_b.y},
			Vec3{inner_a.x, water.elevation - .010, inner_a.y},
		)
		append(
			&m.texcoords,
			Vec2 {
				.5 + (point.x - center.x) / (pond_radius * 2),
				.5 + (point.y - center.y) / (pond_radius * 2),
			},
			Vec2 {
				.5 + (following_point.x - center.x) / (pond_radius * 2),
				.5 + (following_point.y - center.y) / (pond_radius * 2),
			},
			Vec2 {
				.5 + (inner_b.x - center.x) / (pond_radius * 2),
				.5 + (inner_b.y - center.y) / (pond_radius * 2),
			},
			Vec2 {
				.5 + (inner_a.x - center.x) / (pond_radius * 2),
				.5 + (inner_a.y - center.y) / (pond_radius * 2),
			},
		)
		roof_add_triangle(&m, base, base + 2, base + 1)
		roof_add_triangle(&m, base, base + 3, base + 2)}
	shore_index_count := len(m.indices) - water_index_count
	bank_index_start := len(m.indices)
	for point, i in outline {
		following := outline[(i + 1) % count]
		away := Vec2 {
			point.x - center.x,
			point.y - center.y,
		}; away_distance := f32(math.sqrt(f64(away.x * away.x + away.y * away.y))); if away_distance > .001 {away.x /= away_distance; away.y /= away_distance}
		following_away := Vec2 {
			following.x - center.x,
			following.y - center.y,
		}; following_distance := f32(math.sqrt(f64(following_away.x * following_away.x + following_away.y * following_away.y))); if following_distance > .001 {following_away.x /= following_distance; following_away.y /= following_distance}
		outer := Vec2 {
			point.x + away.x * .55,
			point.y + away.y * .55,
		}; following_outer := Vec2{following.x + following_away.x * .55, following.y + following_away.y * .55}
		base := u32(len(m.vertices))
		append(
			&m.vertices,
			Vec3{outer.x, level_terrain_height(doc, outer), outer.y},
			Vec3{following_outer.x, level_terrain_height(doc, following_outer), following_outer.y},
			Vec3{following.x, water.elevation - .055, following.y},
			Vec3{point.x, water.elevation - .055, point.y},
		)
		append(&m.texcoords, Vec2{0, 1}, Vec2{1, 1}, Vec2{1, 0}, Vec2{0, 0})
		roof_add_triangle(&m, base, base + 1, base + 2)
		roof_add_triangle(&m, base, base + 2, base + 3)
	}
	m.min = {1e30, 1e30, 1e30}
	m.max = {-1e30, -1e30, -1e30}
	for vertex in m.vertices {
		m.min.x = min(
			m.min.x,
			vertex.x,
		); m.min.y = min(m.min.y, vertex.y); m.min.z = min(m.min.z, vertex.z)
		m.max.x = max(
			m.max.x,
			vertex.x,
		); m.max.y = max(m.max.y, vertex.y); m.max.z = max(m.max.z, vertex.z)
	}
	append(&m.primitives, Glb_Primitive_Range{0, water_index_count, -1, {.075, .30, .34, 1}})
	append(
		&m.primitives,
		Glb_Primitive_Range{water_index_count, shore_index_count, -1, {.075, .30, .34, 1}},
	)
	append(
		&m.primitives,
		Glb_Primitive_Range {
			bank_index_start,
			len(m.indices) - bank_index_start,
			-1,
			{.24, .20, .12, 1},
		},
	)
	m.ready = len(m.indices) > 0
	return m
}

rebuild_generated_ground :: proc(doc: ^Level_Document) {
	chunk_columns :=
		(doc.width + TERRAIN_CHUNK_CELLS - 1) /
		TERRAIN_CHUNK_CELLS; expected_chunks := chunk_columns * ((doc.height + TERRAIN_CHUNK_CELLS - 1) / TERRAIN_CHUNK_CELLS); full_rebuild := generated_terrain_count != expected_chunks
	if full_rebuild do generated_terrain_count = 0
	for y := 0;
	    y < doc.height;
	    y += TERRAIN_CHUNK_CELLS {for x := 0; x < doc.width; x += TERRAIN_CHUNK_CELLS {
			index :=
				(y / TERRAIN_CHUNK_CELLS) * chunk_columns +
				x / TERRAIN_CHUNK_CELLS; if index >= GENERATED_TERRAIN_CAPACITY do continue
			end_x, end_y :=
				min(x + TERRAIN_CHUNK_CELLS, doc.width),
				min(
					y + TERRAIN_CHUNK_CELLS,
					doc.height,
				); affected := full_rebuild || editor_state.dirty.terrain && f32(end_x) >= editor_state.dirty.min.x && f32(x) <= editor_state.dirty.max.x && f32(end_y) >= editor_state.dirty.min.y && f32(y) <= editor_state.dirty.max.y
			if affected {mesh := procedural_terrain_chunk_mesh(doc, x, y, end_x, end_y); if mesh.ready do apply_texture(&mesh, yard_grass_texture); generated_terrain_meshes[index] = mesh; generated_terrain_dirty[index] = true}
			if full_rebuild do generated_terrain_count = max(generated_terrain_count, index + 1)
		}}
	generated_water_count = 0; for water in doc.waters {if generated_water_count >= GENERATED_GROUND_CAPACITY do break; mesh := procedural_water_mesh(doc, water); if mesh.ready {generated_water_meshes[generated_water_count] = mesh; generated_water_count += 1}}
	generated_path_count = 0; for path in doc.paths {if generated_path_count >= GENERATED_GROUND_CAPACITY do break; if path.kind != .Road && path.kind != .Footpath do continue; mesh := procedural_path_mesh(doc, path); if mesh.ready {apply_texture(&mesh, yard_path_texture(path.material)); generated_path_meshes[generated_path_count] = mesh; generated_path_count += 1}}
	generated_ground_revision = doc.revision
}

Generated_Stair_Shape :: enum {
	Straight,
	L,
	U,
}
generated_stair_shape :: proc(
	start, finish: Vec2,
	rise, width: f32,
) -> Generated_Stair_Shape {dx, dy := finish.x - start.x, finish.y - start.y; distance := f32(
		math.sqrt(f64(dx * dx + dy * dy)),
	)
	required := rise / .18 * .28
	if distance >= required * .9 do return .Straight
	if distance >= required * .55 do return .L
	return .U}

stair_add_box :: proc(mesh: ^Glb_Mesh, center: Vec2, bottom, top, width, depth, yaw: f32) {
	c, s :=
		f32(math.cos(f64(yaw))),
		f32(
			math.sin(f64(yaw)),
		); right := Vec2{c * width * .5, s * width * .5}; forward := Vec2{-s * depth * .5, c * depth * .5}; corners := [4]Vec2{{center.x - right.x - forward.x, center.y - right.y - forward.y}, {center.x + right.x - forward.x, center.y + right.y - forward.y}, {center.x + right.x + forward.x, center.y + right.y + forward.y}, {center.x - right.x + forward.x, center.y - right.y + forward.y}}; base := u32(len(mesh.vertices)); for p in corners {append(&mesh.vertices, Vec3{p.x, bottom, p.y}); append(&mesh.texcoords, Vec2{0, 0})}; for p in corners {append(&mesh.vertices, Vec3{p.x, top, p.y}); append(&mesh.texcoords, Vec2{0, 1})}; faces := [36]u32{0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7, 0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5, 2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7}; for index in faces do append(&mesh.indices, base + index)
}

procedural_stair_mesh :: proc(link: Level_Vertical_Link, rise: f32) -> Glb_Mesh {
	m: Glb_Mesh; if link.kind != .Stairs || rise <= 0 do return m; m.vertices = make([dynamic]Vec3, 0, 256); m.texcoords = make([dynamic]Vec2, 0, 256); m.indices = make([dynamic]u32, 0, 512); m.primitives = make([dynamic]Glb_Primitive_Range, 0, 1); shape := generated_stair_shape(link.start, link.finish, rise, link.width); path := [4]Vec2{}; count := 2; path[0] = link.start; path[1] = link.finish
	if shape ==
	   .L {dx, dy := math.abs(link.finish.x - link.start.x), math.abs(link.finish.y - link.start.y); path[1] = dx >= dy ? Vec2{link.finish.x, link.start.y} : Vec2{link.start.x, link.finish.y}; path[2] = link.finish; count = 3} else if shape == .U {dx, dy := link.finish.x - link.start.x, link.finish.y - link.start.y; distance := max(f32(math.sqrt(f64(dx * dx + dy * dy))), .001); nx, ny := -dy / distance, dx / distance; offset := max(link.width * 1.35, distance * .5); mid := Vec2{(link.start.x + link.finish.x) * .5, (link.start.y + link.finish.y) * .5}; path[1] = {mid.x + nx * offset, mid.y + ny * offset}; path[2] = {mid.x - nx * offset, mid.y - ny * offset}; path[3] = link.finish; count = 4}
	total: f32 = 0; lengths := [3]f32{}; for i in 0 ..< count - 1 {dx, dy := path[i + 1].x - path[i].x, path[i + 1].y - path[i].y; lengths[i] = f32(math.sqrt(f64(dx * dx + dy * dy))); total += lengths[i]}
	steps := max(
		2,
		int(math.ceil(f64(rise / .18))),
	); for step in 0 ..< steps {travel := (f32(step) + .5) / f32(steps) * total; segment := 0; for segment < count - 2 {if travel <= lengths[segment] do break; travel -= lengths[segment]; segment += 1}; a, b := path[segment], path[segment + 1]; t := lengths[segment] > .001 ? travel / lengths[segment] : 0; center := Vec2{a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t}; yaw := f32(math.atan2(f64(b.y - a.y), f64(b.x - a.x))) - f32(math.PI / 2); top := rise * f32(step + 1) / f32(steps); stair_add_box(&m, center, max(0, top - .16), top, link.width, max(.24, total / f32(steps) + .04), yaw)}
	m.min = {
		1e30,
		0,
		1e30,
	}; m.max = {-1e30, rise, -1e30}; for v in m.vertices {m.min.x = min(m.min.x, v.x); m.min.z = min(m.min.z, v.z); m.max.x = max(m.max.x, v.x); m.max.z = max(m.max.z, v.z)}; append(&m.primitives, Glb_Primitive_Range{0, len(m.indices), -1, {.56, .39, .24, 1}}); m.ready = len(m.indices) > 0; return m
}

procedural_vertical_link_mesh :: proc(link: Level_Vertical_Link, rise: f32) -> Glb_Mesh {
	if link.kind == .Stairs do return procedural_stair_mesh(link, rise)
	m: Glb_Mesh; if rise <= 0 do return m; m.vertices = make([dynamic]Vec3, 0, 128); m.texcoords = make([dynamic]Vec2, 0, 128); m.indices = make([dynamic]u32, 0, 256); m.primitives = make([dynamic]Glb_Primitive_Range, 0, 1)
	if link.kind ==
	   .Ladder {dx, dy := link.finish.x - link.start.x, link.finish.y - link.start.y; length := max(f32(math.sqrt(f64(dx * dx + dy * dy))), .001); nx, ny := -dy / length, dx / length; center := Vec2{(link.start.x + link.finish.x) * .5, (link.start.y + link.finish.y) * .5}; sides := [2]int{-1, 1}; for side in sides {rail := Vec2{center.x + nx * link.width * .42 * f32(side), center.y + ny * link.width * .42 * f32(side)}; stair_add_box(&m, rail, 0, rise, .08, .08, 0)}; rungs := max(2, int(rise / .28)); yaw := f32(math.atan2(f64(ny), f64(nx))) - f32(math.PI / 2); for rung in 0 ..= rungs {y := rise * f32(rung) / f32(rungs); stair_add_box(&m, center, max(0, y - .035), min(rise, y + .035), link.width, .1, yaw)}} else {center := Vec2{(link.start.x + link.finish.x) * .5, (link.start.y + link.finish.y) * .5}; stair_add_box(&m, center, 0, rise, link.width, link.width, 0)}
	m.min = {
		1e30,
		0,
		1e30,
	}; m.max = {-1e30, rise, -1e30}; for v in m.vertices {m.min.x = min(m.min.x, v.x); m.min.z = min(m.min.z, v.z); m.max.x = max(m.max.x, v.x); m.max.z = max(m.max.z, v.z)}; color := link.kind == .Ladder ? [4]f32{.42, .45, .38, 1} : [4]f32{.34, .42, .48, 1}; append(&m.primitives, Glb_Primitive_Range{0, len(m.indices), -1, color}); m.ready = len(m.indices) > 0; return m
}

rebuild_generated_links :: proc(doc: ^Level_Document) {generated_link_count = 0; for 	link in doc.vertical_links {if generated_link_count >= GENERATED_LINK_CAPACITY do continue; rise :=
			f32(3)
		base_y: f32 = 0
		if link.from_story >= 0 && link.to_story < len(doc.stories) {base_y =
				doc.stories[link.from_story].base_elevation
			rise = doc.stories[link.to_story].base_elevation - base_y}
		mesh := procedural_vertical_link_mesh(link, rise)
		if !mesh.ready do continue
		generated_link_meshes[generated_link_count] = mesh
		generated_link_base_y[generated_link_count] = base_y
		generated_link_story[generated_link_count] = link.from_story
		generated_link_count += 1}
	generated_link_revision = doc.revision}

roof_add_triangle :: proc(mesh: ^Glb_Mesh, a, b, c: u32) {append(&mesh.indices, a, b, c, c, b, a)}

roof_add_soffit_ring :: proc(mesh: ^Glb_Mesh, wall, eave: []Vec2) {
	if len(wall) < 3 || len(wall) != len(eave) do return
	for i in 0 ..< len(wall) {
		j := (i + 1) % len(wall); base := u32(len(mesh.vertices))
		append(
			&mesh.vertices,
			Vec3{wall[i].x, 0, wall[i].y},
			Vec3{eave[i].x, 0, eave[i].y},
			Vec3{eave[j].x, 0, eave[j].y},
			Vec3{wall[j].x, 0, wall[j].y},
		)
		length := f32(
			math.sqrt(
				f64(
					(wall[j].x - wall[i].x) * (wall[j].x - wall[i].x) +
					(wall[j].y - wall[i].y) * (wall[j].y - wall[i].y),
				),
			),
		)
		depth := f32(
			math.sqrt(
				f64(
					(eave[i].x - wall[i].x) * (eave[i].x - wall[i].x) +
					(eave[i].y - wall[i].y) * (eave[i].y - wall[i].y),
				),
			),
		)
		append(
			&mesh.texcoords,
			Vec2{0, 0},
			Vec2{0, depth * 2},
			Vec2{length * 2, depth * 2},
			Vec2{length * 2, 0},
		)
		roof_add_triangle(
			mesh,
			base,
			base + 1,
			base + 2,
		); roof_add_triangle(mesh, base, base + 2, base + 3)
	}
}

roof_offset_polygon :: proc(points: []Vec2, distance: f32) -> []Vec2 {
	result := make(
		[]Vec2,
		len(points),
		context.temp_allocator,
	); if len(points) < 3 || distance <= 0 {copy(result, points); return result}
	area: f32 = 0; for i in 0 ..< len(points) {j := (i + 1) % len(points); area += points[i].x * points[j].y - points[j].x * points[i].y}; winding: f32 = area >= 0 ? 1 : -1
	for i in 0 ..< len(
		points,
	) {previous, current, next := points[(i + len(points) - 1) % len(points)], points[i], points[(i + 1) % len(points)]; d1, d2 := Vec2{current.x - previous.x, current.y - previous.y}, Vec2{next.x - current.x, next.y - current.y}; l1 := f32(math.sqrt(f64(d1.x * d1.x + d1.y * d1.y))); l2 := f32(math.sqrt(f64(d2.x * d2.x + d2.y * d2.y))); if l1 < .0001 || l2 < .0001 {result[i] = current; continue}; d1.x /= l1; d1.y /= l1; d2.x /= l2; d2.y /= l2; n1 := Vec2{d1.y * winding, -d1.x * winding}; n2 := Vec2{d2.y * winding, -d2.x * winding}; a, b := Vec2{current.x + n1.x * distance, current.y + n1.y * distance}, Vec2{current.x + n2.x * distance, current.y + n2.y * distance}; denom := d1.x * d2.y - d1.y * d2.x; candidate := Vec2{current.x + (n1.x + n2.x) * distance * .5, current.y + (n1.y + n2.y) * distance * .5}; if math.abs(denom) > .0001 {delta := Vec2{b.x - a.x, b.y - a.y}; t := (delta.x * d2.y - delta.y * d2.x) / denom; candidate = {a.x + d1.x * t, a.y + d1.y * t}}; mx, my := candidate.x - current.x, candidate.y - current.y; miter := f32(math.sqrt(f64(mx * mx + my * my))); limit := max(distance * 4, distance + .01); if miter > limit {candidate = {current.x + mx / miter * limit, current.y + my / miter * limit}}; result[i] = candidate}
	if !level_polygon_simple(
		result,
	) {center := Vec2{}; for p in points {center.x += p.x; center.y += p.y}; center.x /= f32(len(points)); center.y /= f32(len(points)); for p, i in points {dx, dy := p.x - center.x, p.y - center.y; length := f32(math.sqrt(f64(dx * dx + dy * dy))); if length > .0001 {dx /= length; dy /= length}; result[i] = {p.x + dx * distance, p.y + dy * distance}}}
	return result
}

// Roofs are derived directly from room polygons. Gables use a continuous
// ridge-height field, hips converge on a central high point, and flat roofs
// retain a shallow curb so their silhouette remains legible in cutaway views.
roof_axis_point :: proc(along, cross, height, ux, uy, nx, ny: f32) -> Vec3 {return{
		along * ux + cross * nx,
		height,
		along * uy + cross * ny,
	}}

procedural_rect_gable_mesh :: proc(points: []Vec2, pitch, overhang, ridge_angle: f32) -> Glb_Mesh {
	m: Glb_Mesh; if len(points) != 4 do return m; expanded := roof_offset_polygon(points, overhang); if len(expanded) != 4 do return m
	angle :=
		ridge_angle *
		f32(math.PI) /
		180; ux, uy := f32(math.cos(f64(angle))), f32(math.sin(f64(angle))); nx, ny := -uy, ux; min_u, max_u, min_n, max_n := f32(1e30), f32(-1e30), f32(1e30), f32(-1e30)
	for p in expanded {along, cross := p.x * ux + p.y * uy, p.x * nx + p.y * ny
		min_u = min(min_u, along)
		max_u = max(max_u, along)
		min_n = min(min_n, cross)
		max_n = max(max_n, cross)}
	if max_u - min_u < .01 || max_n - min_n < .01 do return m; middle_n := (min_n + max_n) * .5; slope := max(f32(math.tan(f64(pitch * f32(math.PI) / 180))), .01); eave := f32(.08); ridge := eave + (max_n - min_n) * .5 * slope
	m.vertices = make(
		[dynamic]Vec3,
		0,
		22,
	); m.texcoords = make([dynamic]Vec2, 0, 22); m.indices = make([dynamic]u32, 0, 60); m.primitives = make([dynamic]Glb_Primitive_Range, 0, 1)
	append(
		&m.vertices,
		roof_axis_point(min_u, min_n, eave, ux, uy, nx, ny),
		roof_axis_point(max_u, min_n, eave, ux, uy, nx, ny),
		roof_axis_point(max_u, max_n, eave, ux, uy, nx, ny),
		roof_axis_point(min_u, max_n, eave, ux, uy, nx, ny),
		roof_axis_point(min_u, middle_n, ridge, ux, uy, nx, ny),
		roof_axis_point(max_u, middle_n, ridge, ux, uy, nx, ny),
	); for v in m.vertices do append(&m.texcoords, Vec2{v.x * .2, v.z * .2})
	roof_add_triangle(
		&m,
		0,
		1,
		5,
	); roof_add_triangle(&m, 0, 5, 4); roof_add_triangle(&m, 3, 4, 5); roof_add_triangle(&m, 3, 5, 2); roof_add_triangle(&m, 0, 4, 3); roof_add_triangle(&m, 1, 2, 5)
	// Close the eaves down to the wall plate; gable ends remain visibly peaked.
	boundary := [4]u32 {
		0,
		1,
		2,
		3,
	}; for edge in 0 ..< 4 {a, b := boundary[edge], boundary[(edge + 1) % 4]; top_a, top_b := m.vertices[a], m.vertices[b]; base := u32(len(m.vertices)); append(&m.vertices, top_a, top_b, Vec3{top_b.x, 0, top_b.z}, Vec3{top_a.x, 0, top_a.z}); append(&m.texcoords, Vec2{0, 0}, Vec2{1, 0}, Vec2{1, 1}, Vec2{0, 1}); roof_add_triangle(&m, base, base + 1, base + 2); roof_add_triangle(&m, base, base + 2, base + 3)}
	roof_surface_count := len(m.indices); roof_add_soffit_ring(&m, points, expanded)
	m.min = {
		1e30,
		0,
		1e30,
	}; m.max = {-1e30, ridge, -1e30}; for v in m.vertices {m.min.x = min(m.min.x, v.x); m.min.z = min(m.min.z, v.z); m.max.x = max(m.max.x, v.x); m.max.z = max(m.max.z, v.z)}; append(&m.primitives, Glb_Primitive_Range{0, roof_surface_count, -1, {.32, .38, .43, 1}}, Glb_Primitive_Range{roof_surface_count, len(m.indices) - roof_surface_count, -1, {.46, .47, .45, 1}}); m.ready = true; return m
}

procedural_rect_mansard_mesh :: proc(
	points: []Vec2,
	pitch, overhang, ridge_angle: f32,
) -> Glb_Mesh {
	m: Glb_Mesh; if len(points) != 4 do return m; expanded := roof_offset_polygon(points, overhang); angle := ridge_angle * f32(math.PI) / 180; ux, uy := f32(math.cos(f64(angle))), f32(math.sin(f64(angle))); nx, ny := -uy, ux; min_u, max_u, min_n, max_n := f32(1e30), f32(-1e30), f32(1e30), f32(-1e30)
	for p in expanded {along, cross := p.x * ux + p.y * uy, p.x * nx + p.y * ny
		min_u = min(min_u, along)
		max_u = max(max_u, along)
		min_n = min(min_n, cross)
		max_n = max(
			max_n,
			cross,
		)}; width, depth := max_u - min_u, max_n - min_n; if width < 2 || depth < 2 do return m
	inset := min(
		min(width, depth) * .22,
		f32(1.35),
	); iu0, iu1, in0, in1 := min_u + inset, max_u - inset, min_n + inset, max_n - inset; eave := f32(.08); lower_top := eave + inset * max(f32(math.tan(f64(max(pitch, 55) * f32(math.PI) / 180))), 1.4); cap_peak := lower_top + min(iu1 - iu0, in1 - in0) * .16
	m.vertices = make(
		[dynamic]Vec3,
		0,
		64,
	); m.texcoords = make([dynamic]Vec2, 0, 64); m.indices = make([dynamic]u32, 0, 180); m.primitives = make([dynamic]Glb_Primitive_Range, 0, 2)
	coords := [8][2]f32 {
		{min_u, min_n},
		{max_u, min_n},
		{max_u, max_n},
		{min_u, max_n},
		{iu0, in0},
		{iu1, in0},
		{iu1, in1},
		{iu0, in1},
	}; for coord, i in coords {height := i < 4 ? eave : lower_top; v := roof_axis_point(coord[0], coord[1], height, ux, uy, nx, ny); append(&m.vertices, v); append(&m.texcoords, Vec2{v.x * .2, v.z * .2})}; for side in 0 ..< 4 {next := (side + 1) % 4; roof_add_triangle(&m, u32(side), u32(next), u32(4 + next)); roof_add_triangle(&m, u32(side), u32(4 + next), u32(4 + side))}; peak := u32(len(m.vertices)); center_u, center_n := (min_u + max_u) * .5, (min_n + max_n) * .5; pv := roof_axis_point(center_u, center_n, cap_peak, ux, uy, nx, ny); append(&m.vertices, pv); append(&m.texcoords, Vec2{pv.x * .2, pv.z * .2}); for side in 0 ..< 4 do roof_add_triangle(&m, u32(4 + side), u32(4 + (side + 1) % 4), peak)
	// Dormers are authored roof-window entities, not repeated by the roof style.
	roof_surface_count := len(m.indices); roof_add_soffit_ring(&m, points, expanded)
	m.min = {
		1e30,
		0,
		1e30,
	}; m.max = {-1e30, cap_peak, -1e30}; for v in m.vertices {m.min.x = min(m.min.x, v.x); m.min.z = min(m.min.z, v.z); m.max.x = max(m.max.x, v.x); m.max.z = max(m.max.z, v.z)}; append(&m.primitives, Glb_Primitive_Range{0, roof_surface_count, -1, {.30, .34, .39, 1}}, Glb_Primitive_Range{roof_surface_count, len(m.indices) - roof_surface_count, -1, {.46, .47, .45, 1}}); m.ready = true; return m
}

procedural_parapet_mesh :: proc(points: []Vec2, overhang: f32) -> Glb_Mesh {
	m := procedural_roof_mesh(
		points,
		.Flat,
		2,
		overhang,
		0,
	); if !m.ready do return m; expanded := roof_offset_polygon(points, overhang)
	parapet_start := len(m.indices)
	for a, i in expanded {b := expanded[(i + 1) % len(expanded)]; dx, dy := b.x - a.x, b.y - a.y
		length := f32(math.sqrt(f64(dx * dx + dy * dy)))
		if length < .01 do continue
		center := Vec2{(a.x + b.x) * .5, (a.y + b.y) * .5}
		yaw := f32(math.atan2(f64(dy), f64(dx)))
		stair_add_box(&m, center, .06, .48, length, .18, yaw)}
	if len(m.indices) > parapet_start do append(&m.primitives, Glb_Primitive_Range{parapet_start, len(m.indices) - parapet_start, -1, {.30, .34, .39, 1}}); m.max.y = max(m.max.y, .48); return m
}

procedural_roof_mesh :: proc(
	points: []Vec2,
	style: Level_Roof_Style,
	pitch, overhang, ridge_angle: f32,
) -> Glb_Mesh {
	m: Glb_Mesh; if len(points) < 3 do return m
	if style == .Gable &&
	   len(points) ==
		   4 {gable := procedural_rect_gable_mesh(points, pitch, overhang, ridge_angle); if gable.ready do return gable}
	if style == .Mansard &&
	   len(points) ==
		   4 {mansard := procedural_rect_mansard_mesh(points, pitch, overhang, ridge_angle); if mansard.ready do return mansard}
	if style == .Parapet do return procedural_parapet_mesh(points, overhang)
	center :=
		Vec2{}; for p in points {center.x += p.x; center.y += p.y}; center.x /= f32(len(points)); center.y /= f32(len(points))
	expanded := roof_offset_polygon(points, overhang)
	angle :=
		ridge_angle *
		f32(math.PI) /
		180; nx, ny := -f32(math.sin(f64(angle))), f32(math.cos(f64(angle))); min_cross, max_cross := f32(1e30), f32(-1e30); for p in expanded {cross := p.x * nx + p.y * ny; min_cross = min(min_cross, cross); max_cross = max(max_cross, cross)}; middle := (min_cross + max_cross) * .5; slope := f32(math.tan(f64(pitch * f32(math.PI) / 180)))
	m.vertices = make(
		[dynamic]Vec3,
		0,
		len(points) + 1,
	); m.texcoords = make([dynamic]Vec2, 0, len(points) + 1); m.indices = make([dynamic]u32, 0, len(points) * 12); m.primitives = make([dynamic]Glb_Primitive_Range, 0, 1)
	for p in expanded {height := f32(.08)
		if style == .Gable do height += (max_cross - min_cross) * .5 - math.abs(p.x * nx + p.y * ny - middle)
		height = max(height, .08)
		append(&m.vertices, Vec3{p.x, height * max(slope, f32(.01)), p.y})
		append(&m.texcoords, Vec2{p.x * .2, p.y * .2})}
	if style ==
	   .Hip {distance := f32(1e30); for i in 0 ..< len(expanded) {d, _ := level_segment_distance(center, expanded[i], expanded[(i + 1) % len(expanded)]); distance = min(distance, d)}; peak := u32(len(m.vertices)); append(&m.vertices, Vec3{center.x, max(.12, distance * slope), center.y}); append(&m.texcoords, Vec2{center.x * .2, center.y * .2}); for i in 0 ..< len(expanded) do roof_add_triangle(&m, u32(i), u32((i + 1) % len(expanded)), peak)} else {
		area: f32 = 0; for i in 0 ..< len(expanded) {j := (i + 1) % len(expanded); area += expanded[i].x * expanded[j].y - expanded[j].x * expanded[i].y}; winding: f32 = area >= 0 ? 1 : -1; remaining := make([dynamic]int, 0, len(expanded)); defer delete(remaining); for i in 0 ..< len(expanded) do append(&remaining, i); guard := 0; for len(remaining) > 2 && guard < len(expanded) * len(expanded) {clipped := false; for cursor in 0 ..< len(remaining) {previous := remaining[(cursor + len(remaining) - 1) % len(remaining)]; current := remaining[cursor]; next := remaining[(cursor + 1) % len(remaining)]; if wall_cap_cross(expanded[previous], expanded[current], expanded[next]) * winding <= .000001 do continue; occupied := false; for candidate in remaining {if candidate == previous || candidate == current || candidate == next do continue; if wall_cap_contains(expanded[candidate], expanded[previous], expanded[current], expanded[next], winding) {occupied = true; break}}; if occupied do continue; roof_add_triangle(&m, u32(previous), u32(current), u32(next)); ordered_remove(&remaining, cursor); clipped = true; break}; if !clipped do break; guard += 1}
	}
	// A fascia closes the boundary and removes the paper-thin edge common to
	// procedural roofs, especially around angled room corners.
	for i in 0 ..< len(
		expanded,
	) {j := (i + 1) % len(expanded); top_a, top_b := m.vertices[i], m.vertices[j]; base := u32(len(m.vertices)); append(&m.vertices, top_a, top_b, Vec3{top_b.x, 0, top_b.z}, Vec3{top_a.x, 0, top_a.z}); append(&m.texcoords, Vec2{0, 0}, Vec2{1, 0}, Vec2{1, 1}, Vec2{0, 1}); roof_add_triangle(&m, base, base + 1, base + 2); roof_add_triangle(&m, base, base + 2, base + 3)}
	roof_surface_count := len(m.indices); roof_add_soffit_ring(&m, points, expanded)
	m.min = {
		1e30,
		1e30,
		1e30,
	}; m.max = {-1e30, -1e30, -1e30}; for v in m.vertices {m.min.x = min(m.min.x, v.x); m.min.y = min(m.min.y, v.y); m.min.z = min(m.min.z, v.z); m.max.x = max(m.max.x, v.x); m.max.y = max(m.max.y, v.y); m.max.z = max(m.max.z, v.z)}; append(&m.primitives, Glb_Primitive_Range{0, roof_surface_count, -1, {.32, .38, .43, 1}}, Glb_Primitive_Range{roof_surface_count, len(m.indices) - roof_surface_count, -1, {.46, .47, .45, 1}}); m.ready = len(m.indices) > 0; return m
}

roof_courtyard_ridge :: proc(doc: ^Level_Document, room: Level_Room) -> (f32, bool) {
	// An exterior room enclosed by interior rooms is a courtyard hole. A roof
	// wing bordering that hole needs a ridge parallel to the shared courtyard
	// edge; a room-local hip peak closes the hole visually and produces invalid
	// diagonal facets on concave rooms.
	best_length := f32(0); best_angle := f32(0)
	for courtyard in doc.rooms {
		if !courtyard.exterior || courtyard.story != room.story do continue
		for a, i in room.points {b := room.points[(i + 1) % len(room.points)]; rdx, rdy := b.x - a.x, b.y - a.y; rlen := f32(math.sqrt(f64(rdx * rdx + rdy * rdy))); if rlen < .001 do continue
			for c, j in courtyard.points {d := courtyard.points[(j + 1) % len(courtyard.points)]; cdx, cdy := d.x - c.x, d.y - c.y; clen := f32(math.sqrt(f64(cdx * cdx + cdy * cdy))); if clen < .001 do continue; if math.abs(rdx * cdy - rdy * cdx) > .001 * rlen * clen do continue; if point_segment_distance_sq(c.x, c.y, a, b) > .001 && point_segment_distance_sq(d.x, d.y, a, b) > .001 && point_segment_distance_sq(a.x, a.y, c, d) > .001 && point_segment_distance_sq(b.x, b.y, c, d) > .001 do continue
				axis_x, axis_y :=
					rdx /
					rlen,
					rdy /
					rlen; room_min, room_max := a.x * axis_x + a.y * axis_y, b.x * axis_x + b.y * axis_y; if room_min > room_max do room_min, room_max = room_max, room_min; court_min, court_max := c.x * axis_x + c.y * axis_y, d.x * axis_x + d.y * axis_y; if court_min > court_max do court_min, court_max = court_max, court_min; overlap := min(room_max, court_max) - max(room_min, court_min); if overlap > best_length + .001 {best_length = overlap; best_angle = f32(math.atan2(f64(rdy), f64(rdx))) * 180 / f32(math.PI)}
			}
		}
	}
	return best_angle, best_length > .001
}

roof_story_interior_at :: proc(doc: ^Level_Document, story: int, p: Vec2) -> bool {for room in doc.rooms do if room.story == story && !room.exterior && level_point_in_polygon(p, room.points[:]) do return true
	return false}
roof_story_has_courtyard :: proc(doc: ^Level_Document, story: int) -> bool {for room in doc.rooms do if room.story == story && room.exterior do return true
	return false}

// Roof materials are directional. Each plane owns a render-space UV seam:
// U follows its eave/ridge, while V climbs the slope. Positions at those seams
// remain numerically identical, so the architectural surface is still welded.
roof_add_shingle_quad :: proc(
	mesh: ^Glb_Mesh,
	eave_a, eave_b, ridge_b, ridge_a: Vec3,
	hole_side := false,
) {
	base := u32(len(mesh.vertices)); append(&mesh.vertices, eave_a, eave_b, ridge_b, ridge_a)
	eave_dx, eave_dz := eave_b.x - eave_a.x, eave_b.z - eave_a.z
	rise_dx, rise_dy, rise_dz := ridge_a.x - eave_a.x, ridge_a.y - eave_a.y, ridge_a.z - eave_a.z
	u := f32(math.sqrt(f64(eave_dx * eave_dx + eave_dz * eave_dz))) * .2
	v := f32(math.sqrt(f64(rise_dx * rise_dx + rise_dy * rise_dy + rise_dz * rise_dz))) * .2
	append(&mesh.texcoords, Vec2{0, 0}, Vec2{u, 0}, Vec2{u, v}, Vec2{0, v})
	if hole_side {
		append(&mesh.indices, base, base + 1, base + 2, base, base + 2, base + 3)
	} else {
		append(&mesh.indices, base, base + 2, base + 1, base, base + 3, base + 2)
	}
}

procedural_compound_roof_mesh :: proc(
	doc: ^Level_Document,
	story: int,
	pitch, overhang: f32,
) -> Glb_Mesh {
	// This is one polygon-with-a-hole roof, not four room roofs and not a
	// rasterized slab. The two boundary loops have opposite semantic winding:
	// the outer loop bounds solid roof, while the courtyard loop bounds empty air.
	// Their simultaneous rectangular wavefronts meet at the shared ridge loop.
	m: Glb_Mesh
	outer_min, outer_max := Vec2{1e30, 1e30}, Vec2{-1e30, -1e30}; found_interior := false
	hole_min, hole_max := Vec2{1e30, 1e30}, Vec2{-1e30, -1e30}; found_hole := false
	for room in doc.rooms {
		if room.story != story do continue
		if room.exterior {
			if found_hole do return m // This exact topology supports one hole.
			for p in room.points {hole_min.x = min(hole_min.x, p.x); hole_min.y = min(hole_min.y, p.y); hole_max.x = max(hole_max.x, p.x); hole_max.y = max(hole_max.y, p.y)}
			found_hole = len(room.points) == 4
		} else {
			for p in room.points {outer_min.x = min(outer_min.x, p.x); outer_min.y = min(outer_min.y, p.y); outer_max.x = max(outer_max.x, p.x); outer_max.y = max(outer_max.y, p.y)}
			found_interior = true
		}
	}
	if !found_interior || !found_hole || hole_min.x <= outer_min.x || hole_min.y <= outer_min.y || hole_max.x >= outer_max.x || hole_max.y >= outer_max.y do return m
	wall_outer := [4]Vec2 {
		{outer_min.x, outer_min.y},
		{outer_max.x, outer_min.y},
		{outer_max.x, outer_max.y},
		{outer_min.x, outer_max.y},
	}
	wall_hole := [4]Vec2 {
		{hole_min.x, hole_min.y},
		{hole_min.x, hole_max.y},
		{hole_max.x, hole_max.y},
		{hole_max.x, hole_min.y},
	}

	// Room polygons follow wall centerlines. Extend the exterior eave beyond the
	// outside face and shrink the courtyard hole so its eave covers the inner
	// wall plate. Previously this path ignored every authored overhang.
	clamped_overhang := max(overhang, 0)
	outer_min.x -=
		clamped_overhang; outer_min.y -= clamped_overhang; outer_max.x += clamped_overhang; outer_max.y += clamped_overhang
	hole_min.x +=
		clamped_overhang; hole_min.y += clamped_overhang; hole_max.x -= clamped_overhang; hole_max.y -= clamped_overhang
	if hole_min.x >= hole_max.x || hole_min.y >= hole_max.y do return m

	// Each ridge coordinate is the meeting point of the opposed wavefronts.
	// Vertex height is distance to the first boundary that reaches that junction.
	ridge_min := Vec2{(outer_min.x + hole_min.x) * .5, (outer_min.y + hole_min.y) * .5}
	ridge_max := Vec2{(outer_max.x + hole_max.x) * .5, (outer_max.y + hole_max.y) * .5}
	slope := max(f32(math.tan(f64(pitch * f32(math.PI) / 180))), .01); eave := f32(.08)
	left_run, right_run := (hole_min.x - outer_min.x) * .5, (outer_max.x - hole_max.x) * .5
	top_run, bottom_run := (hole_min.y - outer_min.y) * .5, (outer_max.y - hole_max.y) * .5
	// A closed rectangular ridge is one continuous elevation. The narrowest
	// opposed wavefront collision is the limiting event; using it at all four
	// junctions keeps every emitted quadrilateral exactly planar even when an
	// authored courtyard is slightly off-centre.
	ridge_height := eave + min(min(left_run, right_run), min(top_run, bottom_run)) * slope
	ridge_heights := [4]f32{ridge_height, ridge_height, ridge_height, ridge_height}
	outer := [4]Vec2 {
		{outer_min.x, outer_min.y},
		{outer_max.x, outer_min.y},
		{outer_max.x, outer_max.y},
		{outer_min.x, outer_max.y},
	}
	ridge := [4]Vec2 {
		{ridge_min.x, ridge_min.y},
		{ridge_max.x, ridge_min.y},
		{ridge_max.x, ridge_max.y},
		{ridge_min.x, ridge_max.y},
	}
	// Clockwise hole order is intentional and opposite the CCW outer loop.
	hole := [4]Vec2 {
		{hole_min.x, hole_min.y},
		{hole_min.x, hole_max.y},
		{hole_max.x, hole_max.y},
		{hole_max.x, hole_min.y},
	}
	m.vertices = make(
		[dynamic]Vec3,
		0,
		32,
	); m.texcoords = make([dynamic]Vec2, 0, 32); m.indices = make([dynamic]u32, 0, 48); m.primitives = make([dynamic]Glb_Primitive_Range, 0, 1)
	// Eight deliberate planar faces. UV seams duplicate render vertices, but all
	// shared ridge/corner positions come from these same authoritative arrays.
	hole_side_start := [4]int{0, 3, 2, 1}; hole_side_end := [4]int{3, 2, 1, 0}
	for side in 0 ..< 4 {
		next := (side + 1) % 4
		o0, o1, r0, r1 := outer[side], outer[next], ridge[side], ridge[next]
		roof_add_shingle_quad(
			&m,
			{o0.x, eave, o0.y},
			{o1.x, eave, o1.y},
			{r1.x, ridge_heights[next], r1.y},
			{r0.x, ridge_heights[side], r0.y},
		)
		h0, h1 := hole[hole_side_start[side]], hole[hole_side_end[side]]
		roof_add_shingle_quad(
			&m,
			{h0.x, eave, h0.y},
			{h1.x, eave, h1.y},
			{r1.x, ridge_heights[next], r1.y},
			{r0.x, ridge_heights[side], r0.y},
			true,
		)
	}
	roof_surface_count := len(
		m.indices,
	); roof_add_soffit_ring(&m, wall_outer[:], outer[:]); roof_add_soffit_ring(&m, wall_hole[:], hole[:])
	m.min = {
		outer_min.x,
		0,
		outer_min.y,
	}; m.max = {outer_max.x, eave, outer_max.y}; for height in ridge_heights do m.max.y = max(m.max.y, height)
	append(
		&m.primitives,
		Glb_Primitive_Range{0, roof_surface_count, -1, {.34, .37, .40, 1}},
		Glb_Primitive_Range {
			roof_surface_count,
			len(m.indices) - roof_surface_count,
			-1,
			{.46, .47, .45, 1},
		},
	); m.ready = true; return m
}

rebuild_generated_roofs :: proc(doc: ^Level_Document) {
	generated_roof_count = 0; for i in 0 ..< GENERATED_ROOF_CAPACITY do generated_roof_has_gutters[i] = false
	for story_index in 0 ..< len(
		doc.stories,
	) {if !roof_story_has_courtyard(doc, story_index) do continue; pitch, overhang := f32(30), f32(.4); for roof in doc.roofs {if roof.story != story_index do continue; if roof.pitch > 0 do pitch = roof.pitch; overhang = max(overhang, roof.overhang)}; mesh := procedural_compound_roof_mesh(doc, story_index, pitch, overhang); if !mesh.ready do continue; apply_texture(&mesh, roof_texture); generated_roof_meshes[generated_roof_count] = mesh; generated_roof_base_y[generated_roof_count] = doc.stories[story_index].base_elevation + doc.stories[story_index].wall_height; generated_roof_story[generated_roof_count] = story_index; generated_roof_style[generated_roof_count] = .Hip; generated_roof_count += 1}
	for room in doc.rooms {
		if generated_roof_count >= GENERATED_ROOF_CAPACITY do continue
		if room.exterior || roof_story_has_courtyard(doc, room.story) do continue
		roof := Level_Roof {
			id          = fmt.tprintf("generated_roof_%s", room.id),
			room_id     = room.id,
			story       = room.story,
			style       = .Gable,
			pitch       = 30,
			overhang    = .4,
			ridge_angle = 0,
		}; roof_index := level_roof_for_room(
			doc,
			room.id,
		); if roof_index >= 0 do roof = doc.roofs[roof_index]
		style, ridge_angle :=
			roof.style,
			roof.ridge_angle; if courtyard_angle, borders_courtyard := roof_courtyard_ridge(doc, room); borders_courtyard && (style == .Gable || style == .Hip) {style = .Gable; ridge_angle = courtyard_angle}
		base_y :=
			room.platform_height +
			f32(
				2.5,
			); if room.story >= 0 && room.story < len(doc.stories) do base_y += doc.stories[room.story].base_elevation + doc.stories[room.story].wall_height - 2.5
		generated_roof_meshes[generated_roof_count] = procedural_roof_mesh(
			room.points[:],
			style,
			roof.pitch,
			roof.overhang,
			ridge_angle,
		); apply_texture(&generated_roof_meshes[generated_roof_count], roof_texture); generated_roof_base_y[generated_roof_count] = base_y; generated_roof_story[generated_roof_count] = roof.story; generated_roof_style[generated_roof_count] = style; generated_roof_count += 1
		if roof.gutters {eaves := roof_offset_polygon(room.points[:], roof.overhang); points := make([]Vec2, len(eaves) + 1, context.temp_allocator); copy(points, eaves); points[len(eaves)] = eaves[0]; generated_roof_gutter_meshes[generated_roof_count - 1] = procedural_wall_run_mesh(points, .14, .16); generated_roof_has_gutters[generated_roof_count - 1] = generated_roof_gutter_meshes[generated_roof_count - 1].ready}
	}
	generated_roof_revision = doc.revision
}
