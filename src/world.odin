package main

import "core:fmt"
import "core:image"
import _ "core:image/jpeg"
import _ "core:image/png"
import "core:math"
import "core:strings"

Floorplan_Spline :: struct {points:[]Vec2,width:f32}
// Vale House is an 1800s solid-masonry mansion. 460 mm is representative of
// a substantial two-wythe brick/stone wall with interior and exterior finish.
HOUSE_EXTERIOR_WALL_THICKNESS :: f32(.46)
HOUSE_INTERIOR_WALL_THICKNESS :: f32(.18)
HOUSE_WALL_THICKNESS :: HOUSE_EXTERIOR_WALL_THICKNESS
house_wall_width :: proc(width:f32)->f32 {return width>0?width:HOUSE_INTERIOR_WALL_THICKNESS}
house_opening_face_offset :: proc(opening:Plan_Opening,face_lift:f32)->f32 {
	return house_wall_width(opening.wall_width)*.5+face_lift
}
HOUSE_WALL_HEIGHT :: f32(3.5)
HOUSE_CUTAWAY_HEIGHT :: f32(1.35)
HOUSE_WALL_SECTION_CAPACITY :: 256
house_authored_wall_height :: proc()->f32 {story:=level_document.active_story;if story>=0&&story<len(level_document.stories)&&level_document.stories[story].wall_height>0 do return level_document.stories[story].wall_height;return HOUSE_WALL_HEIGHT}
House_Wall_View :: enum {Automatic, Walls_Up, Walls_Down}
house_wall_view_name :: proc(view:House_Wall_View)->string {#partial switch view {case .Automatic:return "AUTO CUTAWAY";case .Walls_Up:return "WALLS UP";case .Walls_Down:return "WALLS DOWN"};return "AUTO CUTAWAY"}

HOUSE_WINDOW_FRAME_RAIL_HEIGHT :: .055
HOUSE_WINDOW_GLAZING_BEAD_DEPTH :: .012
HOUSE_WINDOW_HARDWARE_DEPTH :: .018
HOUSE_WINDOW_MUNTIN_DEPTH :: .016
HOUSE_WALL_COVERING_UV_SCALE :: f32(.5)
// Plan-view aperture subtraction uses a square cap whose tangent extension is
// half its cut width. Window masonry and exterior finish must cover that same
// shoulder without changing the authored span used by interior wallpaper.
HOUSE_OPENING_CUT_WIDTH :: f32(HOUSE_WALL_THICKNESS+.02)
HOUSE_OPENING_CUT_END_EXTENSION :: HOUSE_OPENING_CUT_WIDTH*.5
HOUSE_EXTERIOR_OPENING_FINISH_OVERLAP :: HOUSE_OPENING_CUT_END_EXTENSION+.02
HOUSE_NAV_CELL :: .5
HOUSE_NAV_WIDTH :: 96
HOUSE_NAV_HEIGHT :: 88
HOUSE_NAV_CELLS :: HOUSE_NAV_WIDTH*HOUSE_NAV_HEIGHT
HOUSE_SURFACE_WIDTH :: 48
HOUSE_SURFACE_HEIGHT :: 44
HOUSE_SURFACE_CELLS :: HOUSE_SURFACE_WIDTH*HOUSE_SURFACE_HEIGHT
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
house_nav_walkable:[HOUSE_NAV_CELLS]bool

house_radial_input :: proc(input:Vec2)->Vec2 {
	length:=f32(math.sqrt(f64(input.x*input.x+input.y*input.y)))
	if length<=HOUSE_STICK_DEADZONE do return {}
	// Remap the usable stick travel to 0..1, then use a gentle quadratic blend:
	// precise near center, responsive through the middle, full speed at the rim.
	direction:=Vec2{input.x/length,input.y/length};magnitude:=clamp((min(length,f32(1))-HOUSE_STICK_DEADZONE)/(1-HOUSE_STICK_DEADZONE),0,1)
	response:=magnitude*magnitude*.35+magnitude*.65
	return {direction.x*response,direction.y*response}
}

house_approach_velocity :: proc(current,target:Vec2,moving:bool)->Vec2 {
	dx,dy:=target.x-current.x,target.y-current.y;distance:=f32(math.sqrt(f64(dx*dx+dy*dy)))
	if distance<=.00001 do return target
	rate:=moving?f32(HOUSE_MOVE_ACCELERATION):f32(HOUSE_MOVE_DECELERATION)
	if moving {
		dot:=current.x*target.x+current.y*target.y
		// Give steering its own response instead of making the player coast along
		// the old heading. Reversals remain capped so they still have visible weight.
		if dot<0 {rate=f32(HOUSE_MOVE_REVERSE_ACCELERATION)} else if dot*dot<.72*.72*(current.x*current.x+current.y*current.y)*(target.x*target.x+target.y*target.y) do rate=f32(HOUSE_MOVE_TURN_ACCELERATION)
	}
	if distance<=rate do return target
	return {current.x+dx/distance*rate,current.y+dy/distance*rate}
}
// Straight spline spans are split wherever a doorway belongs. Adding curved
// paths later only requires sampling more points into the same representation.
HOUSE_WALL_SPLINES := [?]Floorplan_Spline{
	{{{0,0},{24,0},{24,16},{0,16},{0,0}},0},
	// Time-ambiguous atrium house: public rooms north, study west, service wing
	// east, and a contained courtyard with doors on every inhabited side. Vale
	// House intentionally mixes inherited and contemporary design cues.
	{{{14,0},{14,1.7}},0},{{{14,3.1},{14,5}},0},
	{{{8,5},{8,7.6}},0},{{{8,9.2},{8,13.3}},0},{{{8,14.7},{8,16}},0},
	{{{16,5},{16,7.6}},0},{{{16,9.2},{16,13.3}},0},{{{16,14.7},{16,16}},0},
	{{{8,5},{10.6,5}},0},{{{12.0,5},{16,5}},0},
	{{{8,12},{10.6,12}},0},{{{12.0,12},{16,12}},0},
}
World_Entity :: struct {
	x,y,elevation,facing,scale:f32,
	kind,source_id,name,description,appearance:string,
	tags:[STORY_MAX_TAGS]string,
	tag_count:int,
}

world_entity_has_tag :: proc(entity:^World_Entity,tag:string)->bool {for value in entity.tags[:entity.tag_count] do if value==tag do return true;return false}
world_entity_index_with_tag :: proc(tag:string)->int {for &entity,i in WORLD_ENTITIES do if world_entity_has_tag(&entity,tag) do return i;return -1}
// Runtime entities are a projection of StoryCore entities with the
// `world_entity` role. Their transforms come exclusively from LevelFormat.
// There is deliberately no compiled-in fallback: a missing spatial binding is
// invalid authored content, not permission to resurrect a stale coordinate.
WORLD_ENTITIES:[dynamic]World_Entity

Furniture_Kind :: enum {Dining_Table,Chair,Sofa,Coffee_Table,Bookcase,Desk,Bed,Plant,Side_Table}
Room_Surface :: enum {Dining,Study,Gallery,Pantry,Garden}
WALL_COVERING_PATHS := [Room_Surface]string{
	.Dining="assets/materials/wall-coverings/interior/02-ivory-art-deco.png",
	.Study="assets/materials/wall-coverings/interior/01-forest-herringbone.png",
	.Gallery="assets/materials/wall-coverings/interior/03-blue-gray-plaster.png",
	.Pantry="assets/materials/wall-coverings/interior/04-ochre-wheat.png",
	.Garden="assets/materials/wall-coverings/interior/09-limestone-plaster.png",
}
FLOOR_COVERING_PATHS := [Room_Surface]string{
	.Dining="assets/materials/floor-coverings/interior/01-walnut-herringbone.png",
	.Study="assets/materials/floor-coverings/interior/02-honey-oak-planks.png",
	.Gallery="assets/materials/floor-coverings/interior/03-slate-flagstone.png",
	.Pantry="assets/materials/floor-coverings/interior/04-encaustic-star-tile.png",
	.Garden="assets/yard-textures/yard-flagstone.png",
}
YARD_GRASS_TEXTURE_PATH :: "assets/yard-textures/yard-grass.png"
YARD_GRAVEL_TEXTURE_PATH :: "assets/yard-textures/yard-gravel.png"
YARD_DIRT_TEXTURE_PATH :: "assets/yard-textures/yard-dirt.png"
YARD_FLAGSTONE_TEXTURE_PATH :: "assets/yard-textures/yard-flagstone.png"
ROOF_TEXTURE_PATH :: "assets/materials/roof-coverings/01-slate-asphalt-shingles.png"
EXTERIOR_WALL_TEXTURE_PATH :: "assets/materials/exterior/01-limestone-cedar-stucco.png"
DOOR_TEXTURE_PATHS := [Door_Material]string{
	.Oak = "assets/materials/doors/oak.png",
	.Painted = "assets/materials/doors/painted.png",
	.Walnut = "assets/materials/doors/walnut.png",
}
FURNITURE_PATHS := [Furniture_Kind]string{
	.Dining_Table="assets/kenney_furniture-kit/Models/GLTF format/tableCloth.glb",
	.Chair="assets/kenney_furniture-kit/Models/GLTF format/chairCushion.glb",
	.Sofa="assets/kenney_furniture-kit/Models/GLTF format/loungeSofa.glb",
	.Coffee_Table="assets/kenney_furniture-kit/Models/GLTF format/tableCoffee.glb",
	.Bookcase="assets/kenney_furniture-kit/Models/GLTF format/bookcaseOpen.glb",
	.Desk="assets/kenney_furniture-kit/Models/GLTF format/desk.glb",
	.Bed="assets/kenney_furniture-kit/Models/GLTF format/bedDouble.glb",
	.Plant="assets/kenney_furniture-kit/Models/GLTF format/pottedPlant.glb",
	.Side_Table="assets/kenney_furniture-kit/Models/GLTF format/sideTableDrawers.glb",
}
Furniture :: struct {x,y,height,radius:f32,kind:Furniture_Kind,tint:[4]u8,yaw,elevation:f32}
// A grounds cell is an intentional interior-exterior: it belongs to the lot
// and pathfinding plan, but is open to the sky and receives exterior dressing.
Plan_Space_Kind :: enum {Interior,Grounds}
Opening_Kind :: enum {Door,Window}
Plan_Opening :: struct {a,b:Vec2,kind:Opening_Kind,id:string,height,sill_height,wall_width:f32,door_material:Door_Material,door_style:Door_Style,window_style:Window_Style,window_flipped,window_hinge_right:bool}
// Paint remains data on the logical wall section, not on a renderer mesh. This
// lets render chunks be rebuilt or merged freely while each side stays editable.
Wall_Face_Paint :: struct {a,b:Vec2,positive:bool,surface:Room_Surface}
Build_Command_Kind :: enum {Create_Room,Set_Wall,Place_Opening,Paint_Room,Set_Space_Kind,Paint_Wall_Side,Place_Object,Move_Object,Delete_Object}
Build_Command :: struct {kind:Build_Command_Kind,a,b:Vec2,surface:Room_Surface,space:Plan_Space_Kind,opening:Opening_Kind,furniture:Furniture,index:int}
Build_Snapshot :: struct {wall_splines:[dynamic]Floorplan_Spline,openings:[dynamic]Plan_Opening,wall_face_paints:[dynamic]Wall_Face_Paint,furniture:[dynamic]Furniture,surfaces:[HOUSE_SURFACE_CELLS]Room_Surface,space_kinds:[HOUSE_SURFACE_CELLS]Plan_Space_Kind,revision:int}
House_Plan :: struct {
	level:int, wall_splines:[dynamic]Floorplan_Spline, openings:[dynamic]Plan_Opening,
	wall_face_paints:[dynamic]Wall_Face_Paint, furniture:[dynamic]Furniture, surfaces:[HOUSE_SURFACE_CELLS]Room_Surface, space_kinds:[HOUSE_SURFACE_CELLS]Plan_Space_Kind, initialized:bool, validation:string, revision:int, dirty:bool,
	undo,redo:[16]Build_Snapshot,undo_count,redo_count:int,
}
house_plan:House_Plan
furniture_meshes: [Furniture_Kind]Glb_Mesh
catalog_object_meshes:[dynamic]Glb_Mesh
catalog_thumbnail_floor,vehicle_skid_mesh:Glb_Mesh
PICTURE_FRAME_PATHS := [5]string{
	"assets/materials/picture-frames/frame-walnut-9slice.png",
	"assets/materials/picture-frames/frame-gilded-baroque-9slice.png",
	"assets/materials/picture-frames/frame-black-lacquer-9slice.png",
	"assets/materials/picture-frames/frame-aged-bronze-9slice.png",
	"assets/materials/picture-frames/frame-painted-ivory-9slice.png",
}

catalog_furniture_kind :: proc(id:string)->(Furniture_Kind,bool) {switch id {case "plant":return .Plant,true;case "dining_table":return .Dining_Table,true;case "chair":return .Chair,true;case "sofa":return .Sofa,true;case "coffee_table":return .Coffee_Table,true;case "bookcase":return .Bookcase,true;case "desk":return .Desk,true;case "bed":return .Bed,true;case "side_table":return .Side_Table,true};return {},false}
catalog_object_mesh :: proc(id:string)->(^Glb_Mesh,bool) {for &entry in editor_catalog.entries {if entry.kind!=.Object||entry.id!=id||entry.mesh_index<0||entry.mesh_index>=len(catalog_object_meshes) do continue;mesh:=&catalog_object_meshes[entry.mesh_index];return mesh,mesh.ready};return nil,false}
catalog_object_height :: proc(mesh:^Glb_Mesh)->f32 {if mesh==nil do return 1;return max(mesh.max.y-mesh.min.y,.001)}

catalog_object_render_height :: proc(mesh:^Glb_Mesh,entry:^Catalog_Entry)->f32 {
	height:=catalog_object_height(mesh)
	if entry==nil do return height
	if entry.dimensions.y>0 do return entry.dimensions.y
	return height*catalog_model_unit_scale(entry.model)
}

load_catalog_object_meshes :: proc() {
	frame_textures:[5]Glb_Texture_Data;for path,i in PICTURE_FRAME_PATHS do frame_textures[i]=load_room_texture(path)
	catalog_object_meshes=make([dynamic]Glb_Mesh,0,len(editor_catalog.entries));for &entry in editor_catalog.entries {if entry.kind!=.Object do continue;entry.mesh_index=-1;if !entry.valid do continue;mesh:Glb_Mesh;ok:=false;if entry.image!="" {texture:=load_room_texture(entry.image);if len(texture.pixels)>0 {aspect:=f32(texture.width)/f32(max(texture.height,1));height:=f32(1.35);width:=clamp(height*aspect,.45,1.8);frame_index:=painting_frame_index(entry.id);mesh=procedural_picture_mesh(width,height,texture,frame_textures[frame_index]);ok=true}} else {mesh,ok=glb_load(entry.model)};if !ok||!mesh.ready {entry.valid=false;continue};entry.mesh_index=len(catalog_object_meshes);append(&catalog_object_meshes,mesh)}
}

painting_frame_index :: proc(id:string)->int {
	// Give the initial collection one example of every frame style. Any later
	// paintings still receive a stable style derived from their catalog id.
	if strings.contains(id, "van_gogh") do return 0
	if strings.contains(id, "botticelli") do return 1
	if strings.contains(id, "vermeer") do return 2
	if strings.contains(id, "friedrich") do return 3
	if strings.contains(id, "hokusai") do return 4
	hash:u32=2166136261;for ch in id {hash=(hash~u32(ch))*16777619};return int(hash%u32(len(PICTURE_FRAME_PATHS)))
}
house_floor_mesh,house_art_mesh,house_art_frame_mesh,house_window_mesh: Glb_Mesh
bloodstain_mesh,drag_trace_mesh: Glb_Mesh
case_statuette_mesh,case_cane_mesh,case_ledger_mesh,case_cloth_mesh,case_oil_mesh,case_watch_mesh,case_wastebin_mesh,case_rug_unfolded_mesh,case_rug_folded_mesh: Glb_Mesh
house_door_meshes:[Door_Material]Glb_Mesh
house_window_sill_mesh,house_window_header_mesh,house_window_sill_interior_mesh,house_window_header_interior_mesh,house_window_header_cap_mesh,house_window_frame_h_mesh,house_window_frame_v_mesh,house_window_muntin_h_mesh,house_window_muntin_v_mesh,house_window_bead_h_mesh,house_window_bead_v_mesh,house_window_hardware_h_mesh,house_window_hardware_v_mesh,house_window_sill_cap_mesh,house_window_exterior_sill_mesh,house_window_head_return_mesh,house_window_jamb_return_mesh,house_shutter_slat_mesh,house_wall_junction_reveal_mesh,house_wall_cap_edge_mesh,house_wall_cap_edge_interior_mesh:Glb_Mesh

house_opening_sill_mesh :: proc(opening:Plan_Opening)->^Glb_Mesh {if house_wall_width(opening.wall_width)<=HOUSE_INTERIOR_WALL_THICKNESS+.001 do return &house_window_sill_interior_mesh;return &house_window_sill_mesh}
house_opening_header_mesh :: proc(opening:Plan_Opening)->^Glb_Mesh {if house_wall_width(opening.wall_width)<=HOUSE_INTERIOR_WALL_THICKNESS+.001 do return &house_window_header_interior_mesh;return &house_window_header_mesh}
house_opening_cap_edge_mesh :: proc(opening:Plan_Opening)->^Glb_Mesh {if house_wall_width(opening.wall_width)<=HOUSE_INTERIOR_WALL_THICKNESS+.001 do return &house_wall_cap_edge_interior_mesh;return &house_wall_cap_edge_mesh}
shutter_crank_housing_mesh,shutter_crank_arm_mesh,shutter_crank_link_mesh,shutter_crank_grip_mesh,shutter_silk_mesh: Glb_Mesh
house_floor_materials:[Room_Surface]Glb_Mesh
house_floor_batches:[Plan_Space_Kind][Room_Surface]Glb_Mesh
house_wall_materials:[Room_Surface]Glb_Texture_Data
// Each wall piece owns a neutral structural core plus independently materialed
// faces. A shared wall therefore belongs visually to the room on either side.
Floorplan_Wall :: struct {a,b:Vec2,width:f32,positive_surface,negative_surface:Room_Surface,positive_interior,negative_interior:bool,core,cap,face_positive,face_negative:Glb_Mesh,core_bands:[3]Glb_Mesh}
house_walls:[dynamic]Floorplan_Wall
// Structural runs share mitered vertices at a spline corner. The per-section
// face meshes remain separate so either side can still be painted independently.
house_wall_runs,house_wall_runs_full:[dynamic]Glb_Mesh
house_wall_face_batches,house_wall_face_batches_full:[Room_Surface]Glb_Mesh
house_wall_cap_batch_full:Glb_Mesh
// Derived once from the editable splines. This is the only structural wall
// render mesh: regularized union removes prism overlaps and miter seams.
house_wall_solid,house_wall_solid_cutaway,house_wall_cap_union,house_wall_cap_union_edge:Glb_Mesh
GENERATED_ROOF_CAPACITY :: 32
generated_roof_meshes:[GENERATED_ROOF_CAPACITY]Glb_Mesh
generated_roof_base_y:[GENERATED_ROOF_CAPACITY]f32
generated_roof_story:[GENERATED_ROOF_CAPACITY]int
generated_roof_style:[GENERATED_ROOF_CAPACITY]Level_Roof_Style
generated_roof_gutter_meshes:[GENERATED_ROOF_CAPACITY]Glb_Mesh
generated_roof_has_gutters:[GENERATED_ROOF_CAPACITY]bool
generated_roof_count:int
generated_roof_revision,generated_roof_gpu_revision:u64
GENERATED_LINK_CAPACITY :: 32
generated_link_meshes:[GENERATED_LINK_CAPACITY]Glb_Mesh
generated_link_base_y:[GENERATED_LINK_CAPACITY]f32
generated_link_story:[GENERATED_LINK_CAPACITY]int
generated_link_count:int
generated_link_revision,generated_link_gpu_revision:u64
GENERATED_GROUND_CAPACITY :: 32
generated_water_meshes,generated_path_meshes:[GENERATED_GROUND_CAPACITY]Glb_Mesh
generated_water_count,generated_path_count:int
generated_ground_revision,generated_ground_gpu_revision:u64
yard_grass_texture,yard_gravel_texture,yard_dirt_texture,yard_flagstone_texture:Glb_Texture_Data
roof_texture,exterior_wall_texture:Glb_Texture_Data
TERRAIN_CHUNK_CELLS :: 8
GENERATED_TERRAIN_CAPACITY :: 64
generated_terrain_meshes:[GENERATED_TERRAIN_CAPACITY]Glb_Mesh
generated_terrain_dirty:[GENERATED_TERRAIN_CAPACITY]bool
generated_terrain_count:int
GENERATED_STORY_CAPACITY :: 128
generated_story_slab_meshes,generated_story_wall_meshes:[GENERATED_STORY_CAPACITY]Glb_Mesh
generated_foundation_meshes:[GENERATED_STORY_CAPACITY]Glb_Mesh
generated_story_slab_story,generated_story_wall_story:[GENERATED_STORY_CAPACITY]int
generated_story_slab_base_y,generated_story_wall_base_y:[GENERATED_STORY_CAPACITY]f32
generated_story_slab_count,generated_story_wall_count,generated_foundation_count:int
generated_story_revision,generated_story_gpu_revision:u64
house_derived_wall_segments:[dynamic][2]Vec2
Personal_Surface_Draw :: struct {mesh:Glb_Mesh,x,z,yaw,base,region_base,region_height:f32,wall_index:int,tint:[4]u8}
personal_floor_draws,personal_ceiling_draws,wall_finish_draws:[dynamic]Personal_Surface_Draw

catalog_material_entry :: proc(id:string)->(^Catalog_Entry,bool) {resolved:=catalog_resolve_id(id);for &entry in editor_catalog.entries do if entry.kind==.Material&&entry.id==resolved do return &entry,true;return nil,false}
material_floor_uv_scale :: proc(entry:^Catalog_Entry)->f32 {if entry!=nil&&entry.floor_repeat_m>0 do return 1/entry.floor_repeat_m;return .2}
material_wall_uv_scale :: proc(entry:^Catalog_Entry)->f32 {if entry!=nil&&entry.wall_repeat_m>0 do return 1/entry.wall_repeat_m;return HOUSE_WALL_COVERING_UV_SCALE}
mesh_rescale_uvs :: proc(mesh:^Glb_Mesh,ratio:f32) {if math.abs(ratio-1)<.00001 do return;for &uv in mesh.texcoords {uv.x*=ratio;uv.y*=ratio}}
surface_draws_rescale_uvs :: proc(draws:^[dynamic]Personal_Surface_Draw,first:int,ratio:f32) {for i in first..<len(draws) do mesh_rescale_uvs(&draws[i].mesh,ratio)}
surface_draws_set_tint :: proc(draws:^[dynamic]Personal_Surface_Draw,first:int,tint:[4]u8) {for i in first..<len(draws) do draws[i].tint=tint}
room_material_at :: proc(doc:^Level_Document,point:Vec2,wall:bool)->string {for room in doc.rooms do if room.story==doc.active_story&&level_point_in_polygon(point,room.points[:]) do return wall?room.wall_material:room.floor_material;return ""}
room_tint_at :: proc(doc:^Level_Document,point:Vec2,wall:bool)->[4]u8 {for room in doc.rooms do if room.story==doc.active_story&&level_point_in_polygon(point,room.points[:]) {tint:=wall?room.wall_tint:room.floor_tint;if tint[3]==0 do return {255,255,255,255};return tint};return {255,255,255,255}}
house_opening_host_wall_index :: proc(opening:Plan_Opening)->int {odx,odz:=opening.b.x-opening.a.x,opening.b.y-opening.a.y;opening_length:=f32(math.sqrt(f64(odx*odx+odz*odz)));if opening_length<=.001 do return -1;mx,mz:=(opening.a.x+opening.b.x)*.5,(opening.a.y+opening.b.y)*.5;best_index:=-1;best:=f32(1e30);for wall,i in house_walls {wdx,wdz:=wall.b.x-wall.a.x,wall.b.y-wall.a.y;wall_length:=f32(math.sqrt(f64(wdx*wdx+wdz*wdz)));if wall_length<=.001 do continue;parallel:=math.abs((odx*wdz-odz*wdx)/(opening_length*wall_length));if parallel>.01 do continue;line_distance:=math.abs((mx-wall.a.x)*wdz-(mz-wall.a.y)*wdx)/wall_length;if line_distance>.08 do continue;pairs:=[4][2]Vec2{{opening.a,wall.a},{opening.a,wall.b},{opening.b,wall.a},{opening.b,wall.b}};for pair in pairs {dx,dz:=pair[0].x-pair[1].x,pair[0].y-pair[1].y;distance:=dx*dx+dz*dz;if distance<best {best=distance;best_index=i}}};return best_index}

house_wall_endpoint_is_junction :: proc(wall_index:int,point:Vec2)->bool {
	if wall_index<0||wall_index>=len(house_walls) do return false
	wall:=house_walls[wall_index];dx,dz:=wall.b.x-wall.a.x,wall.b.y-wall.a.y;length:=f32(math.sqrt(f64(dx*dx+dz*dz)));if length<=.001 do return false
	for other,other_index in house_walls {if other_index==wall_index do continue;shared:=level_points_near(point,other.a)||level_points_near(point,other.b);if !shared do continue;odx,odz:=other.b.x-other.a.x,other.b.y-other.a.y;other_length:=f32(math.sqrt(f64(odx*odx+odz*odz)));if other_length<=.001 do continue
		// Collinear neighbors are opening/run splits. Extending their finish would
		// paint back across the aperture. Only actual L/T wall junctions need to
		// follow the square-capped structural union beyond the authored endpoint.
		if math.abs((dx*odz-dz*odx)/(length*other_length))>.01 do return true
	}
	return false
}

house_exterior_wall_finish_span :: proc(wall_index:int)->(Vec2,Vec2) {
	wall:=house_walls[wall_index];a,b:=wall.a,wall.b;dx,dz:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dz*dz)));if length<=.001 do return a,b
	tx,tz:=dx/length,dz/length;extension:=wall.width*.5
	if house_wall_endpoint_is_junction(wall_index,a) do a={a.x-tx*extension,a.y-tz*extension}
	if house_wall_endpoint_is_junction(wall_index,b) do b={b.x+tx*extension,b.y+tz*extension}
	return a,b
}

rebuild_personal_surfaces :: proc(doc:^Level_Document) {
	personal_floor_draws=make([dynamic]Personal_Surface_Draw,0,16);personal_ceiling_draws=make([dynamic]Personal_Surface_Draw,0,16);wall_finish_draws=make([dynamic]Personal_Surface_Draw,0,192)
	base:=doc.stories[doc.active_story].base_elevation
	for room in doc.rooms {if room.story!=doc.active_story do continue;mesh:=procedural_room_slab_mesh(room);if !mesh.ready do continue;cx,cz:=(mesh.min.x+mesh.max.x)*.5,(mesh.min.z+mesh.max.z)*.5
		// Ceilings are an interior surface, independent of the exterior roof. Open
		// and exterior rooms intentionally retain their view of the sky.
		if !room.exterior&&room.ceiling_style!="open" {ceiling:=procedural_room_ceiling_mesh(room);if ceiling.ready do append(&personal_ceiling_draws,Personal_Surface_Draw{mesh=ceiling,x=cx,z=cz,base=base+doc.stories[doc.active_story].wall_height-.015})}
		entry,found:=catalog_material_entry(room.floor_material);if !found||entry.floor=="" do continue;texture:=load_room_texture(entry.floor);if len(texture.pixels)==0 do continue;mesh_rescale_uvs(&mesh,material_floor_uv_scale(entry)/.2);apply_texture(&mesh,texture);slab_height:=max(mesh.max.y-mesh.min.y,.001);floor_tint:=room.floor_tint;if floor_tint[3]==0 do floor_tint={255,255,255,255};append(&personal_floor_draws,Personal_Surface_Draw{mesh=mesh,x=cx,z=cz,base=base+.02-slab_height,tint=floor_tint})}
	for wall,wall_index in house_walls {dx,dz:=wall.b.x-wall.a.x,wall.b.y-wall.a.y;length:=f32(math.sqrt(f64(dx*dx+dz*dz)));if length<=.01 do continue;mx,mz:=(wall.a.x+wall.b.x)*.5,(wall.a.y+wall.b.y)*.5;nx,nz:= -dz/length,dx/length;yaw:=f32(math.atan2(f64(dz),f64(dx)))
		for side in 0..<2 {positive:=side==0;interior:=positive?wall.positive_interior:wall.negative_interior;sign:=positive?f32(1):f32(-1);texture:=exterior_wall_texture;finish_tint:=[4]u8{255,255,255,255};uv_scale:=HOUSE_WALL_COVERING_UV_SCALE;face_lift:=f32(.0005);if interior {sample:=Vec2{mx+nx*.24*sign,mz+nz*.24*sign};material:=room_material_at(doc,sample,true);finish_tint=room_tint_at(doc,sample,true);surface:=positive?wall.positive_surface:wall.negative_surface;texture=house_wall_materials[surface];entry,found:=catalog_material_entry(material);if found {uv_scale=material_wall_uv_scale(entry);if entry.wall!="" {candidate:=load_room_texture(entry.wall);if len(candidate.pixels)>0 do texture=candidate}};face_lift=.004};if len(texture.pixels)==0 do continue;finish_a,finish_b:=wall.a,wall.b;finish_mx,finish_mz:=mx,mz;if !interior {finish_a,finish_b=house_exterior_wall_finish_span(wall_index);finish_mx,finish_mz=(finish_a.x+finish_b.x)*.5,(finish_a.y+finish_b.y)*.5};offset:=wall.width*.5+face_lift;before:=len(wall_finish_draws);append_wallpaper_band_draws(&wall_finish_draws,finish_a,finish_b,finish_mx+nx*offset*sign,finish_mz+nz*offset*sign,yaw+(positive?0:f32(math.PI)),texture,base,wall_index);surface_draws_rescale_uvs(&wall_finish_draws,before,uv_scale/HOUSE_WALL_COVERING_UV_SCALE);surface_draws_set_tint(&wall_finish_draws,before,finish_tint)}
	}
	for opening in house_plan.openings {
		dx,dz:=opening.b.x-opening.a.x,opening.b.y-opening.a.y;length:=f32(math.sqrt(f64(dx*dx+dz*dz)));if length<=.01 do continue
		mx,mz:=(opening.a.x+opening.b.x)*.5,(opening.a.y+opening.b.y)*.5;host_wall:=house_opening_host_wall_index(opening);nx,nz:= -dz/length,dx/length
		for side in 0..<2 {
			positive:=side==0;sign:=positive?f32(1):f32(-1);sample:=Vec2{mx+nx*.24*sign,mz+nz*.24*sign};surface,interior:=house_wall_face_classification(opening.a,opening.b,positive)
			// Structural aperture infill is intentionally opaque. Reapply the actual
			// finish on both faces: room covering inside, continuous siding outside.
			texture:=interior?house_wall_materials[surface]:exterior_wall_texture;finish_tint:=interior?room_tint_at(doc,sample,true):[4]u8{255,255,255,255};uv_scale:=HOUSE_WALL_COVERING_UV_SCALE
			if interior {material:=room_material_at(doc,sample,true);entry,found:=catalog_material_entry(material);if found {uv_scale=material_wall_uv_scale(entry);if entry.wall!="" {candidate:=load_room_texture(entry.wall);if len(candidate.pixels)>0 do texture=candidate}}}
			finish_opening:=interior?opening:house_exterior_opening_finish_span(opening);finish_lift:=interior?f32(.004):f32(.0005);before:=len(wall_finish_draws);if opening.kind==.Window {append_window_wallpaper_draws(&wall_finish_draws,finish_opening,positive,texture,base,finish_lift);if !interior {sign:=positive?f32(1):f32(-1);offset:=house_opening_face_offset(opening,finish_lift);yaw:=f32(math.atan2(f64(dz),f64(dx)))+(positive?0:f32(math.PI));sill:=opening.sill_height>0?opening.sill_height:f32(.72);jamb_height:=(opening.height>0?opening.height:f32(1.4))+.08;shoulders:=[2][2]Vec2{{finish_opening.a,opening.a},{opening.b,finish_opening.b}};for shoulder in shoulders {sx,sz:=(shoulder[0].x+shoulder[1].x)*.5,(shoulder[0].y+shoulder[1].y)*.5;append_wallpaper_region_band_draws(&wall_finish_draws,shoulder[0],shoulder[1],sx+nx*offset*sign,sz+nz*offset*sign,yaw,texture,base,sill-.04,jamb_height,host_wall)}}} else {append_door_wallpaper_header_draw(&wall_finish_draws,finish_opening,positive,texture,base,finish_lift)};surface_draws_rescale_uvs(&wall_finish_draws,before,uv_scale/HOUSE_WALL_COVERING_UV_SCALE);surface_draws_set_tint(&wall_finish_draws,before,finish_tint);for i in before..<len(wall_finish_draws) do wall_finish_draws[i].wall_index=host_wall
		}
	}
}

procedural_room_slab_mesh :: proc(room:Level_Room)->Glb_Mesh {
	m:Glb_Mesh;count:=len(room.points);if count<3 do return m;m.vertices=make([dynamic]Vec3,0,count*2);m.texcoords=make([dynamic]Vec2,0,count*2);m.indices=make([dynamic]u32,0,count*12);m.primitives=make([dynamic]Glb_Primitive_Range,0,1);thickness:=f32(.18)
	for p in room.points {append(&m.vertices,Vec3{p.x,0,p.y});append(&m.texcoords,Vec2{p.x*.2,p.y*.2})};for p in room.points {append(&m.vertices,Vec3{p.x,-thickness,p.y});append(&m.texcoords,Vec2{p.x*.2,p.y*.2})}
	area:=level_polygon_area(room.points[:]);winding:f32=area>=0?1:-1;remaining:=make([dynamic]int,0,count);defer delete(remaining);for i in 0..<count do append(&remaining,i);guard:=0
	for len(remaining)>2&&guard<count*count {clipped:=false;for cursor in 0..<len(remaining) {previous:=remaining[(cursor+len(remaining)-1)%len(remaining)];current:=remaining[cursor];next:=remaining[(cursor+1)%len(remaining)];if wall_cap_cross(room.points[previous],room.points[current],room.points[next])*winding<=.000001 do continue;occupied:=false;for candidate in remaining {if candidate==previous||candidate==current||candidate==next do continue;if wall_cap_contains(room.points[candidate],room.points[previous],room.points[current],room.points[next],winding) {occupied=true;break}};if occupied do continue;roof_add_triangle(&m,u32(previous),u32(current),u32(next));ordered_remove(&remaining,cursor);clipped=true;break};if !clipped do break;guard+=1}
	for i in 0..<count {j:=(i+1)%count;base:=u32(len(m.vertices));a,b:=room.points[i],room.points[j];append(&m.vertices,Vec3{a.x,0,a.y},Vec3{b.x,0,b.y},Vec3{b.x,-thickness,b.y},Vec3{a.x,-thickness,a.y});append(&m.texcoords,Vec2{0,0},Vec2{1,0},Vec2{1,1},Vec2{0,1});roof_add_triangle(&m,base,base+1,base+2);roof_add_triangle(&m,base,base+2,base+3)}
	m.min={1e30,-thickness,1e30};m.max={-1e30,.001,-1e30};for v in m.vertices {m.min.x=min(m.min.x,v.x);m.min.z=min(m.min.z,v.z);m.max.x=max(m.max.x,v.x);m.max.z=max(m.max.z,v.z)};surface:=level_material_surface(room.floor_material);color:=[4]f32{.52,.56,.58,1};#partial switch surface {case .Dining:color={.55,.43,.30,1};case .Study:color={.32,.43,.37,1};case .Gallery:color={.38,.45,.52,1};case .Pantry:color={.53,.49,.36,1};case .Garden:color={.29,.45,.32,1}};append(&m.primitives,Glb_Primitive_Range{0,len(m.indices),-1,color});m.ready=len(m.indices)>0;return m
}

procedural_room_ceiling_mesh :: proc(room:Level_Room)->Glb_Mesh {
	slab:=procedural_room_slab_mesh(room);m:Glb_Mesh;count:=len(room.points);if !slab.ready||count<3 do return m
	m.vertices=make([dynamic]Vec3,0,count);m.texcoords=make([dynamic]Vec2,0,count);m.indices=make([dynamic]u32,0,max((count-2)*3,0));m.primitives=make([dynamic]Glb_Primitive_Range,0,1)
	for i in 0..<count {append(&m.vertices,slab.vertices[i]);append(&m.texcoords,slab.texcoords[i])}
	// The slab's first triangles form its upward-facing floor. Reverse only those
	// triangles to author a downward-facing ceiling; slab edge walls do not belong
	// to the ceiling surface.
	for i:=0;i+2<len(slab.indices);i+=3 {a,b,c:=slab.indices[i],slab.indices[i+1],slab.indices[i+2];if a>=u32(count)||b>=u32(count)||c>=u32(count) do break;append(&m.indices,a,c,b)}
	m.min={1e30,0,1e30};m.max={-1e30,.001,-1e30};for v in m.vertices {m.min.x=min(m.min.x,v.x);m.min.z=min(m.min.z,v.z);m.max.x=max(m.max.x,v.x);m.max.z=max(m.max.z,v.z)}
	append(&m.primitives,Glb_Primitive_Range{0,len(m.indices),-1,{.87,.86,.82,1}});m.ready=len(m.indices)>0;return m
}

procedural_foundation_mesh :: proc(doc:^Level_Document,foundation:Level_Foundation)->Glb_Mesh {
	room:=Level_Room{points=foundation.points,floor_material="foundation"};m:=procedural_room_slab_mesh(room);if !m.ready do return m;count:=len(foundation.points);top:=foundation.elevation-.025;depth:=max(foundation.depth,.25)
	for i in 0..<count {m.vertices[i].y=top;m.vertices[count+i].y=foundation.kind==.Raised?level_terrain_height(doc,foundation.points[i]):foundation.elevation-depth}
	m.min={1e30,1e30,1e30};m.max={-1e30,-1e30,-1e30};for vertex in m.vertices {m.min.x=min(m.min.x,vertex.x);m.min.y=min(m.min.y,vertex.y);m.min.z=min(m.min.z,vertex.z);m.max.x=max(m.max.x,vertex.x);m.max.y=max(m.max.y,vertex.y);m.max.z=max(m.max.z,vertex.z)};if m.max.y-m.min.y<.001 do m.max.y=m.min.y+.001;m.primitives[0].base_color=foundation.kind==.Basement?[4]f32{.30,.32,.35,1}:foundation.kind==.Raised?[4]f32{.46,.43,.38,1}:[4]f32{.42,.44,.43,1};return m
}

wall_segments_same :: proc(a,b,c,d:Vec2)->bool {return level_points_near(a,c)&&level_points_near(b,d)||level_points_near(a,d)&&level_points_near(b,c)}
derived_wall_append :: proc(segments:^[dynamic][2]Vec2,a,b:Vec2) {if level_points_near(a,b) do return;for segment in segments^ do if wall_segments_same(a,b,segment[0],segment[1]) do return;append(segments,[2]Vec2{a,b})}
rebuild_house_wall_splines :: proc(doc:^Level_Document,story:int) {
	// Authored paths are the wall plan: they preserve deliberate corner order,
	// opening hosts, and the construction width selected for every run.
	clear(&house_plan.wall_splines);for &path in doc.paths {if path.story!=story||path.kind!=.Wall&&path.kind!=.Freestanding_Wall&&path.kind!=.Half_Wall&&path.kind!=.Fence do continue;append(&house_plan.wall_splines,Floorplan_Spline{points=path.points[:],width=house_wall_width(path.width)})}
}

rebuild_generated_stories :: proc(doc:^Level_Document) {
	generated_foundation_count=0;for foundation in doc.foundations {if generated_foundation_count>=GENERATED_STORY_CAPACITY do break;mesh:=procedural_foundation_mesh(doc,foundation);if mesh.ready {generated_foundation_meshes[generated_foundation_count]=mesh;generated_foundation_count+=1}}
	generated_story_slab_count=0;for room in doc.rooms {if generated_story_slab_count>=GENERATED_STORY_CAPACITY do break;mesh:=procedural_room_slab_mesh(room);if !mesh.ready do continue;index:=generated_story_slab_count;generated_story_slab_meshes[index]=mesh;generated_story_slab_story[index]=room.story;base:=room.platform_height;if room.story>=0&&room.story<len(doc.stories) do base+=doc.stories[room.story].base_elevation;generated_story_slab_base_y[index]=base;generated_story_slab_count+=1}
	// Walls are authored paths. Rooms own surfaces and enclosure metadata, but
	// never synthesize a second wall plan with competing dimensions.
	generated_story_wall_count=0;for path in doc.paths {if path.kind!=.Wall&&path.kind!=.Freestanding_Wall&&path.kind!=.Half_Wall&&path.kind!=.Fence do continue;if generated_story_wall_count>=GENERATED_STORY_CAPACITY do break;height:=f32(2.5);if path.story>=0&&path.story<len(doc.stories) do height=doc.stories[path.story].wall_height;if path.kind==.Half_Wall do height=1.15;if path.kind==.Fence do height=1;mesh:=procedural_wall_run_mesh(path.points[:],height,house_wall_width(path.width));if !mesh.ready do continue;index:=generated_story_wall_count;generated_story_wall_meshes[index]=mesh;generated_story_wall_story[index]=path.story;base:=f32(0);if path.story>=0&&path.story<len(doc.stories) do base=doc.stories[path.story].base_elevation;generated_story_wall_base_y[index]=base;generated_story_wall_count+=1};generated_story_revision=doc.revision
}

procedural_path_mesh :: proc(doc:^Level_Document,path:Level_Path)->Glb_Mesh {
	m:Glb_Mesh;if len(path.points)<2 do return m;m.vertices=make([dynamic]Vec3,0,len(path.points)*4);m.texcoords=make([dynamic]Vec2,0,len(path.points)*4);m.indices=make([dynamic]u32,0,(len(path.points)-1)*6);m.primitives=make([dynamic]Glb_Primitive_Range,0,1)
	distance:=f32(0);for i in 0..<len(path.points)-1 {a,b:=path.points[i],path.points[i+1];dx,dy:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dy*dy)));if length<.001 do continue;nx,ny:= -dy/length*path.width*.5,dx/length*path.width*.5;base:=u32(len(m.vertices));corners:=[4]Vec2{{a.x+nx,a.y+ny},{a.x-nx,a.y-ny},{b.x-nx,b.y-ny},{b.x+nx,b.y+ny}};u0,u1:=distance/max(path.width,.5), (distance+length)/max(path.width,.5);for p,j in corners {append(&m.vertices,Vec3{p.x,level_terrain_height(doc,p)+.035,p.y});append(&m.texcoords,Vec2{j<2?u0:u1,j==0||j==3?0:1})};append(&m.indices,base,base+2,base+1,base,base+3,base+2);distance+=length}
	if len(m.vertices)==0 do return m;m.min={1e30,1e30,1e30};m.max={-1e30,-1e30,-1e30};for v in m.vertices {m.min.x=min(m.min.x,v.x);m.min.y=min(m.min.y,v.y);m.min.z=min(m.min.z,v.z);m.max.x=max(m.max.x,v.x);m.max.y=max(m.max.y,v.y);m.max.z=max(m.max.z,v.z)};m.max.y=max(m.max.y,m.min.y+1);color:=path.kind==.Road?[4]f32{.22,.24,.25,1}:[4]f32{.58,.50,.38,1};append(&m.primitives,Glb_Primitive_Range{0,len(m.indices),-1,color});m.ready=true;return m
}

yard_path_texture :: proc(material:string)->Glb_Texture_Data {
	if strings.contains(material,"gravel") do return yard_gravel_texture
	if strings.contains(material,"dirt") do return yard_dirt_texture
	return yard_flagstone_texture
}

procedural_terrain_chunk_mesh :: proc(doc:^Level_Document,start_x,start_y,end_x,end_y:int)->Glb_Mesh {
	m:Glb_Mesh;if start_x>=end_x||start_y>=end_y do return m
	columns,rows:=end_x-start_x+1,end_y-start_y+1;m.vertices=make([dynamic]Vec3,0,columns*rows);m.texcoords=make([dynamic]Vec2,0,columns*rows);m.indices=make([dynamic]u32,0,(columns-1)*(rows-1)*6);m.primitives=make([dynamic]Glb_Primitive_Range,0,1);m.min={f32(start_x),1e30,f32(start_y)};m.max={f32(end_x),-1e30,f32(end_y)}
	for y in start_y..=end_y {for x in start_x..=end_x {height:=level_terrain_sample(doc,x,y);append(&m.vertices,Vec3{f32(x),height,f32(y)});append(&m.texcoords,Vec2{f32(x)*.125,f32(y)*.125});m.min.y=min(m.min.y,height);m.max.y=max(m.max.y,height)}}
	for y in 0..<rows-1 {for x in 0..<columns-1 {
		cell:=Vec2{f32(start_x+x)+.5,f32(start_y+y)+.5};covered:=false
		for foundation in doc.foundations {if level_foundation_contains_point(foundation,cell) {covered=true;break}}
		if !covered do for room in doc.rooms {if room.story==0&&level_point_in_polygon(cell,room.points[:]) {covered=true;break}}
		// Keep terrain continuous beneath water. Culling whole grid cells against
		// the authored polygon left square holes wherever the visible, smoothed
		// shoreline curved back inside those cells. The opaque water and bank mesh
		// own the visible surface while the terrain safely fills its footprint.
		if covered do continue
		a:=u32(y*columns+x);b:=a+1;c:=a+u32(columns);d:=c+1;append(&m.indices,a,d,b,a,c,d)
	}}
	if m.max.y-m.min.y<.001 do m.max.y=m.min.y+.001
	append(&m.primitives,Glb_Primitive_Range{0,len(m.indices),-1,{.32,.48,.31,1}});m.ready=len(m.indices)>0;return m
}

pond_smooth_outline :: proc(points:[]Vec2,iterations:int=3)->[dynamic]Vec2 {
	outline:=make([dynamic]Vec2,0,len(points),context.temp_allocator)
	append(&outline,..points)
	for _ in 0..<iterations {
		next:=make([dynamic]Vec2,0,len(outline)*2,context.temp_allocator)
		for point,i in outline {
			following:=outline[(i+1)%len(outline)]
			append(&next,
				Vec2{point.x*.75+following.x*.25,point.y*.75+following.y*.25},
				Vec2{point.x*.25+following.x*.75,point.y*.25+following.y*.75},
			)
		}
		outline=next
	}
	return outline
}

procedural_water_mesh :: proc(doc:^Level_Document,water:Level_Water)->Glb_Mesh {
	m:Glb_Mesh
	if len(water.points)<3 do return m
	outline:=pond_smooth_outline(water.points[:])
	count:=len(outline)
	m.vertices=make([dynamic]Vec3,0,count*7)
	m.texcoords=make([dynamic]Vec2,0,count*7)
	m.indices=make([dynamic]u32,0,count*18)
	m.primitives=make([dynamic]Glb_Primitive_Range,0,3)
	center:=Vec2{};for point in outline {center.x+=point.x;center.y+=point.y};center.x/=f32(count);center.y/=f32(count)
	pond_radius:=f32(.001);for point in outline {dx,dy:=point.x-center.x,point.y-center.y;pond_radius=max(pond_radius,f32(math.sqrt(f64(dx*dx+dy*dy))))}
	inner:=make([dynamic]Vec2,0,count,context.temp_allocator)
	for point in outline {toward:=Vec2{center.x-point.x,center.y-point.y};distance:=f32(math.sqrt(f64(toward.x*toward.x+toward.y*toward.y)));inset:=min(.16,distance*.08);inner_point:=distance>.001?Vec2{point.x+toward.x/distance*inset,point.y+toward.y/distance*inset}:point;append(&inner,inner_point)
		// The triangulated water ends at the inner edge of the shallow shelf.
		// Previously these vertices used the outer outline, causing the opaque
		// shelf to overlap the water as a bright decorative ring.
		append(&m.vertices,Vec3{inner_point.x,water.elevation,inner_point.y})
		append(&m.texcoords,Vec2{.5+(inner_point.x-center.x)/(pond_radius*2),.5+(inner_point.y-center.y)/(pond_radius*2)})
	}
	area:=level_polygon_area(inner[:])
	winding:f32=area>=0?1:-1
	remaining:=make([dynamic]int,0,count,context.temp_allocator)
	for i in 0..<count do append(&remaining,i)
	guard:=0
	for len(remaining)>2&&guard<count*count {
		clipped:=false
		for cursor in 0..<len(remaining) {
			previous:=remaining[(cursor+len(remaining)-1)%len(remaining)]
			current:=remaining[cursor]
			next:=remaining[(cursor+1)%len(remaining)]
			if wall_cap_cross(inner[previous],inner[current],inner[next])*winding<=.000001 do continue
			occupied:=false
			for candidate in remaining {
				if candidate==previous||candidate==current||candidate==next do continue
				if wall_cap_contains(inner[candidate],inner[previous],inner[current],inner[next],winding) {occupied=true;break}
			}
			if occupied do continue
			roof_add_triangle(&m,u32(previous),u32(current),u32(next))
			ordered_remove(&remaining,cursor)
			clipped=true
			break
		}
		if !clipped do break
		guard+=1
	}
	water_index_count:=len(m.indices)
	// A narrow submerged shelf bridges the water to the authored shoreline.
	// Extend it beneath the water plane instead of ending directly below the
	// water edge; the overlap prevents the underlying terrain from appearing as
	// a dark line at grazing camera angles.
	for point,i in outline {following:=(i+1)%count;following_point:=outline[following];inner_a:=inner[i];inner_b:=inner[following];toward_a:=Vec2{center.x-inner_a.x,center.y-inner_a.y};toward_b:=Vec2{center.x-inner_b.x,center.y-inner_b.y};distance_a:=f32(math.sqrt(f64(toward_a.x*toward_a.x+toward_a.y*toward_a.y)));distance_b:=f32(math.sqrt(f64(toward_b.x*toward_b.x+toward_b.y*toward_b.y)));if distance_a>.001 {inner_a.x+=toward_a.x/distance_a*.06;inner_a.y+=toward_a.y/distance_a*.06};if distance_b>.001 {inner_b.x+=toward_b.x/distance_b*.06;inner_b.y+=toward_b.y/distance_b*.06};base:=u32(len(m.vertices));append(&m.vertices,Vec3{point.x,water.elevation-.045,point.y},Vec3{following_point.x,water.elevation-.045,following_point.y},Vec3{inner_b.x,water.elevation-.010,inner_b.y},Vec3{inner_a.x,water.elevation-.010,inner_a.y});append(&m.texcoords,Vec2{.5+(point.x-center.x)/(pond_radius*2),.5+(point.y-center.y)/(pond_radius*2)},Vec2{.5+(following_point.x-center.x)/(pond_radius*2),.5+(following_point.y-center.y)/(pond_radius*2)},Vec2{.5+(inner_b.x-center.x)/(pond_radius*2),.5+(inner_b.y-center.y)/(pond_radius*2)},Vec2{.5+(inner_a.x-center.x)/(pond_radius*2),.5+(inner_a.y-center.y)/(pond_radius*2)});roof_add_triangle(&m,base,base+2,base+1);roof_add_triangle(&m,base,base+3,base+2)}
	shore_index_count:=len(m.indices)-water_index_count
	bank_index_start:=len(m.indices)
	for point,i in outline {
		following:=outline[(i+1)%count]
		away:=Vec2{point.x-center.x,point.y-center.y};away_distance:=f32(math.sqrt(f64(away.x*away.x+away.y*away.y)));if away_distance>.001 {away.x/=away_distance;away.y/=away_distance}
		following_away:=Vec2{following.x-center.x,following.y-center.y};following_distance:=f32(math.sqrt(f64(following_away.x*following_away.x+following_away.y*following_away.y)));if following_distance>.001 {following_away.x/=following_distance;following_away.y/=following_distance}
		outer:=Vec2{point.x+away.x*.55,point.y+away.y*.55};following_outer:=Vec2{following.x+following_away.x*.55,following.y+following_away.y*.55}
		base:=u32(len(m.vertices))
		append(&m.vertices,
			Vec3{outer.x,level_terrain_height(doc,outer),outer.y},
			Vec3{following_outer.x,level_terrain_height(doc,following_outer),following_outer.y},
			Vec3{following.x,water.elevation-.055,following.y},
			Vec3{point.x,water.elevation-.055,point.y},
		)
		append(&m.texcoords,Vec2{0,1},Vec2{1,1},Vec2{1,0},Vec2{0,0})
		roof_add_triangle(&m,base,base+1,base+2)
		roof_add_triangle(&m,base,base+2,base+3)
	}
	m.min={1e30,1e30,1e30}
	m.max={-1e30,-1e30,-1e30}
	for vertex in m.vertices {
		m.min.x=min(m.min.x,vertex.x);m.min.y=min(m.min.y,vertex.y);m.min.z=min(m.min.z,vertex.z)
		m.max.x=max(m.max.x,vertex.x);m.max.y=max(m.max.y,vertex.y);m.max.z=max(m.max.z,vertex.z)
	}
	append(&m.primitives,Glb_Primitive_Range{0,water_index_count,-1,{.075,.30,.34,1}})
	append(&m.primitives,Glb_Primitive_Range{water_index_count,shore_index_count,-1,{.075,.30,.34,1}})
	append(&m.primitives,Glb_Primitive_Range{bank_index_start,len(m.indices)-bank_index_start,-1,{.24,.20,.12,1}})
	m.ready=len(m.indices)>0
	return m
}

rebuild_generated_ground :: proc(doc:^Level_Document) {
	chunk_columns:=(doc.width+TERRAIN_CHUNK_CELLS-1)/TERRAIN_CHUNK_CELLS;expected_chunks:=chunk_columns*((doc.height+TERRAIN_CHUNK_CELLS-1)/TERRAIN_CHUNK_CELLS);full_rebuild:=generated_terrain_count!=expected_chunks
	if full_rebuild do generated_terrain_count=0
	for y:=0;y<doc.height;y+=TERRAIN_CHUNK_CELLS {for x:=0;x<doc.width;x+=TERRAIN_CHUNK_CELLS {
		index:=(y/TERRAIN_CHUNK_CELLS)*chunk_columns+x/TERRAIN_CHUNK_CELLS;if index>=GENERATED_TERRAIN_CAPACITY do continue
		end_x,end_y:=min(x+TERRAIN_CHUNK_CELLS,doc.width),min(y+TERRAIN_CHUNK_CELLS,doc.height);affected:=full_rebuild||editor_state.dirty.terrain&&f32(end_x)>=editor_state.dirty.min.x&&f32(x)<=editor_state.dirty.max.x&&f32(end_y)>=editor_state.dirty.min.y&&f32(y)<=editor_state.dirty.max.y
		if affected {mesh:=procedural_terrain_chunk_mesh(doc,x,y,end_x,end_y);if mesh.ready do apply_texture(&mesh,yard_grass_texture);generated_terrain_meshes[index]=mesh;generated_terrain_dirty[index]=true}
		if full_rebuild do generated_terrain_count=max(generated_terrain_count,index+1)
	}}
	generated_water_count=0;for water in doc.waters {if generated_water_count>=GENERATED_GROUND_CAPACITY do break;mesh:=procedural_water_mesh(doc,water);if mesh.ready {generated_water_meshes[generated_water_count]=mesh;generated_water_count+=1}}
	generated_path_count=0;for path in doc.paths {if generated_path_count>=GENERATED_GROUND_CAPACITY do break;if path.kind!=.Road&&path.kind!=.Footpath do continue;mesh:=procedural_path_mesh(doc,path);if mesh.ready {apply_texture(&mesh,yard_path_texture(path.material));generated_path_meshes[generated_path_count]=mesh;generated_path_count+=1}}
	generated_ground_revision=doc.revision
}

Generated_Stair_Shape :: enum {Straight, L, U}
generated_stair_shape :: proc(start,finish:Vec2,rise,width:f32)->Generated_Stair_Shape {dx,dy:=finish.x-start.x,finish.y-start.y;distance:=f32(math.sqrt(f64(dx*dx+dy*dy)));required:=rise/.18*.28;if distance>=required*.9 do return .Straight;if distance>=required*.55 do return .L;return .U}

stair_add_box :: proc(mesh:^Glb_Mesh,center:Vec2,bottom,top,width,depth,yaw:f32) {
	c,s:=f32(math.cos(f64(yaw))),f32(math.sin(f64(yaw)));right:=Vec2{c*width*.5,s*width*.5};forward:=Vec2{-s*depth*.5,c*depth*.5};corners:=[4]Vec2{{center.x-right.x-forward.x,center.y-right.y-forward.y},{center.x+right.x-forward.x,center.y+right.y-forward.y},{center.x+right.x+forward.x,center.y+right.y+forward.y},{center.x-right.x+forward.x,center.y-right.y+forward.y}};base:=u32(len(mesh.vertices));for p in corners {append(&mesh.vertices,Vec3{p.x,bottom,p.y});append(&mesh.texcoords,Vec2{0,0})};for p in corners {append(&mesh.vertices,Vec3{p.x,top,p.y});append(&mesh.texcoords,Vec2{0,1})};faces:=[36]u32{0,2,1,0,3,2,4,5,6,4,6,7,0,1,5,0,5,4,1,2,6,1,6,5,2,3,7,2,7,6,3,0,4,3,4,7};for index in faces do append(&mesh.indices,base+index)
}

procedural_stair_mesh :: proc(link:Level_Vertical_Link,rise:f32)->Glb_Mesh {
	m:Glb_Mesh;if link.kind!=.Stairs||rise<=0 do return m;m.vertices=make([dynamic]Vec3,0,256);m.texcoords=make([dynamic]Vec2,0,256);m.indices=make([dynamic]u32,0,512);m.primitives=make([dynamic]Glb_Primitive_Range,0,1);shape:=generated_stair_shape(link.start,link.finish,rise,link.width);path:=[4]Vec2{};count:=2;path[0]=link.start;path[1]=link.finish
	if shape==.L {dx,dy:=math.abs(link.finish.x-link.start.x),math.abs(link.finish.y-link.start.y);path[1]=dx>=dy?Vec2{link.finish.x,link.start.y}:Vec2{link.start.x,link.finish.y};path[2]=link.finish;count=3} else if shape==.U {dx,dy:=link.finish.x-link.start.x,link.finish.y-link.start.y;distance:=max(f32(math.sqrt(f64(dx*dx+dy*dy))),.001);nx,ny:= -dy/distance,dx/distance;offset:=max(link.width*1.35,distance*.5);mid:=Vec2{(link.start.x+link.finish.x)*.5,(link.start.y+link.finish.y)*.5};path[1]={mid.x+nx*offset,mid.y+ny*offset};path[2]={mid.x-nx*offset,mid.y-ny*offset};path[3]=link.finish;count=4}
	total:f32=0;lengths:=[3]f32{};for i in 0..<count-1 {dx,dy:=path[i+1].x-path[i].x,path[i+1].y-path[i].y;lengths[i]=f32(math.sqrt(f64(dx*dx+dy*dy)));total+=lengths[i]}
	steps:=max(2,int(math.ceil(f64(rise/.18))));for step in 0..<steps {travel:=(f32(step)+.5)/f32(steps)*total;segment:=0;for segment<count-2 {if travel<=lengths[segment] do break;travel-=lengths[segment];segment+=1};a,b:=path[segment],path[segment+1];t:=lengths[segment]>.001?travel/lengths[segment]:0;center:=Vec2{a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t};yaw:=f32(math.atan2(f64(b.y-a.y),f64(b.x-a.x)))-f32(math.PI/2);top:=rise*f32(step+1)/f32(steps);stair_add_box(&m,center,max(0,top-.16),top,link.width,max(.24,total/f32(steps)+.04),yaw)}
	m.min={1e30,0,1e30};m.max={-1e30,rise,-1e30};for v in m.vertices {m.min.x=min(m.min.x,v.x);m.min.z=min(m.min.z,v.z);m.max.x=max(m.max.x,v.x);m.max.z=max(m.max.z,v.z)};append(&m.primitives,Glb_Primitive_Range{0,len(m.indices),-1,{.56,.39,.24,1}});m.ready=len(m.indices)>0;return m
}

procedural_vertical_link_mesh :: proc(link:Level_Vertical_Link,rise:f32)->Glb_Mesh {
	if link.kind==.Stairs do return procedural_stair_mesh(link,rise)
	m:Glb_Mesh;if rise<=0 do return m;m.vertices=make([dynamic]Vec3,0,128);m.texcoords=make([dynamic]Vec2,0,128);m.indices=make([dynamic]u32,0,256);m.primitives=make([dynamic]Glb_Primitive_Range,0,1)
	if link.kind==.Ladder {dx,dy:=link.finish.x-link.start.x,link.finish.y-link.start.y;length:=max(f32(math.sqrt(f64(dx*dx+dy*dy))),.001);nx,ny:= -dy/length,dx/length;center:=Vec2{(link.start.x+link.finish.x)*.5,(link.start.y+link.finish.y)*.5};sides:=[2]int{-1,1};for side in sides {rail:=Vec2{center.x+nx*link.width*.42*f32(side),center.y+ny*link.width*.42*f32(side)};stair_add_box(&m,rail,0,rise,.08,.08,0)};rungs:=max(2,int(rise/.28));yaw:=f32(math.atan2(f64(ny),f64(nx)))-f32(math.PI/2);for rung in 0..=rungs {y:=rise*f32(rung)/f32(rungs);stair_add_box(&m,center,max(0,y-.035),min(rise,y+.035),link.width,.1,yaw)}} else {center:=Vec2{(link.start.x+link.finish.x)*.5,(link.start.y+link.finish.y)*.5};stair_add_box(&m,center,0,rise,link.width,link.width,0)}
	m.min={1e30,0,1e30};m.max={-1e30,rise,-1e30};for v in m.vertices {m.min.x=min(m.min.x,v.x);m.min.z=min(m.min.z,v.z);m.max.x=max(m.max.x,v.x);m.max.z=max(m.max.z,v.z)};color:=link.kind==.Ladder?[4]f32{.42,.45,.38,1}:[4]f32{.34,.42,.48,1};append(&m.primitives,Glb_Primitive_Range{0,len(m.indices),-1,color});m.ready=len(m.indices)>0;return m
}

rebuild_generated_links :: proc(doc:^Level_Document) {generated_link_count=0;for link in doc.vertical_links {if generated_link_count>=GENERATED_LINK_CAPACITY do continue;rise:=f32(3);base_y:f32=0;if link.from_story>=0&&link.to_story<len(doc.stories) {base_y=doc.stories[link.from_story].base_elevation;rise=doc.stories[link.to_story].base_elevation-base_y};mesh:=procedural_vertical_link_mesh(link,rise);if !mesh.ready do continue;generated_link_meshes[generated_link_count]=mesh;generated_link_base_y[generated_link_count]=base_y;generated_link_story[generated_link_count]=link.from_story;generated_link_count+=1};generated_link_revision=doc.revision}

roof_add_triangle :: proc(mesh:^Glb_Mesh,a,b,c:u32) {append(&mesh.indices,a,b,c,c,b,a)}

roof_add_soffit_ring :: proc(mesh:^Glb_Mesh,wall,eave:[]Vec2) {
	if len(wall)<3||len(wall)!=len(eave) do return
	for i in 0..<len(wall) {
		j:=(i+1)%len(wall);base:=u32(len(mesh.vertices))
		append(&mesh.vertices,Vec3{wall[i].x,0,wall[i].y},Vec3{eave[i].x,0,eave[i].y},Vec3{eave[j].x,0,eave[j].y},Vec3{wall[j].x,0,wall[j].y})
		length:=f32(math.sqrt(f64((wall[j].x-wall[i].x)*(wall[j].x-wall[i].x)+(wall[j].y-wall[i].y)*(wall[j].y-wall[i].y))))
		depth:=f32(math.sqrt(f64((eave[i].x-wall[i].x)*(eave[i].x-wall[i].x)+(eave[i].y-wall[i].y)*(eave[i].y-wall[i].y))))
		append(&mesh.texcoords,Vec2{0,0},Vec2{0,depth*2},Vec2{length*2,depth*2},Vec2{length*2,0})
		roof_add_triangle(mesh,base,base+1,base+2);roof_add_triangle(mesh,base,base+2,base+3)
	}
}

roof_offset_polygon :: proc(points:[]Vec2,distance:f32)->[]Vec2 {
	result:=make([]Vec2,len(points),context.temp_allocator);if len(points)<3||distance<=0 {copy(result,points);return result}
	area:f32=0;for i in 0..<len(points) {j:=(i+1)%len(points);area+=points[i].x*points[j].y-points[j].x*points[i].y};winding:f32=area>=0?1:-1
	for i in 0..<len(points) {previous,current,next:=points[(i+len(points)-1)%len(points)],points[i],points[(i+1)%len(points)];d1,d2:=Vec2{current.x-previous.x,current.y-previous.y},Vec2{next.x-current.x,next.y-current.y};l1:=f32(math.sqrt(f64(d1.x*d1.x+d1.y*d1.y)));l2:=f32(math.sqrt(f64(d2.x*d2.x+d2.y*d2.y)));if l1<.0001||l2<.0001 {result[i]=current;continue};d1.x/=l1;d1.y/=l1;d2.x/=l2;d2.y/=l2;n1:=Vec2{d1.y*winding,-d1.x*winding};n2:=Vec2{d2.y*winding,-d2.x*winding};a,b:=Vec2{current.x+n1.x*distance,current.y+n1.y*distance},Vec2{current.x+n2.x*distance,current.y+n2.y*distance};denom:=d1.x*d2.y-d1.y*d2.x;candidate:=Vec2{current.x+(n1.x+n2.x)*distance*.5,current.y+(n1.y+n2.y)*distance*.5};if math.abs(denom)>.0001 {delta:=Vec2{b.x-a.x,b.y-a.y};t:=(delta.x*d2.y-delta.y*d2.x)/denom;candidate={a.x+d1.x*t,a.y+d1.y*t}};mx,my:=candidate.x-current.x,candidate.y-current.y;miter:=f32(math.sqrt(f64(mx*mx+my*my)));limit:=max(distance*4,distance+.01);if miter>limit {candidate={current.x+mx/miter*limit,current.y+my/miter*limit}};result[i]=candidate}
	if !level_polygon_simple(result) {center:=Vec2{};for p in points {center.x+=p.x;center.y+=p.y};center.x/=f32(len(points));center.y/=f32(len(points));for p,i in points {dx,dy:=p.x-center.x,p.y-center.y;length:=f32(math.sqrt(f64(dx*dx+dy*dy)));if length>.0001 {dx/=length;dy/=length};result[i]={p.x+dx*distance,p.y+dy*distance}}}
	return result
}

// Roofs are derived directly from room polygons. Gables use a continuous
// ridge-height field, hips converge on a central high point, and flat roofs
// retain a shallow curb so their silhouette remains legible in cutaway views.
roof_axis_point :: proc(along,cross,height,ux,uy,nx,ny:f32)->Vec3 {return {along*ux+cross*nx,height,along*uy+cross*ny}}

procedural_rect_gable_mesh :: proc(points:[]Vec2,pitch,overhang,ridge_angle:f32)->Glb_Mesh {
	m:Glb_Mesh;if len(points)!=4 do return m;expanded:=roof_offset_polygon(points,overhang);if len(expanded)!=4 do return m
	angle:=ridge_angle*f32(math.PI)/180;ux,uy:=f32(math.cos(f64(angle))),f32(math.sin(f64(angle)));nx,ny:= -uy,ux;min_u,max_u,min_n,max_n:=f32(1e30),f32(-1e30),f32(1e30),f32(-1e30)
	for p in expanded {along,cross:=p.x*ux+p.y*uy,p.x*nx+p.y*ny;min_u=min(min_u,along);max_u=max(max_u,along);min_n=min(min_n,cross);max_n=max(max_n,cross)}
	if max_u-min_u<.01||max_n-min_n<.01 do return m;middle_n:=(min_n+max_n)*.5;slope:=max(f32(math.tan(f64(pitch*f32(math.PI)/180))),.01);eave:=f32(.08);ridge:=eave+(max_n-min_n)*.5*slope
	m.vertices=make([dynamic]Vec3,0,22);m.texcoords=make([dynamic]Vec2,0,22);m.indices=make([dynamic]u32,0,60);m.primitives=make([dynamic]Glb_Primitive_Range,0,1)
	append(&m.vertices,roof_axis_point(min_u,min_n,eave,ux,uy,nx,ny),roof_axis_point(max_u,min_n,eave,ux,uy,nx,ny),roof_axis_point(max_u,max_n,eave,ux,uy,nx,ny),roof_axis_point(min_u,max_n,eave,ux,uy,nx,ny),roof_axis_point(min_u,middle_n,ridge,ux,uy,nx,ny),roof_axis_point(max_u,middle_n,ridge,ux,uy,nx,ny));for v in m.vertices do append(&m.texcoords,Vec2{v.x*.2,v.z*.2})
	roof_add_triangle(&m,0,1,5);roof_add_triangle(&m,0,5,4);roof_add_triangle(&m,3,4,5);roof_add_triangle(&m,3,5,2);roof_add_triangle(&m,0,4,3);roof_add_triangle(&m,1,2,5)
	// Close the eaves down to the wall plate; gable ends remain visibly peaked.
	boundary:=[4]u32{0,1,2,3};for edge in 0..<4 {a,b:=boundary[edge],boundary[(edge+1)%4];top_a,top_b:=m.vertices[a],m.vertices[b];base:=u32(len(m.vertices));append(&m.vertices,top_a,top_b,Vec3{top_b.x,0,top_b.z},Vec3{top_a.x,0,top_a.z});append(&m.texcoords,Vec2{0,0},Vec2{1,0},Vec2{1,1},Vec2{0,1});roof_add_triangle(&m,base,base+1,base+2);roof_add_triangle(&m,base,base+2,base+3)}
	roof_surface_count:=len(m.indices);roof_add_soffit_ring(&m,points,expanded)
	m.min={1e30,0,1e30};m.max={-1e30,ridge,-1e30};for v in m.vertices {m.min.x=min(m.min.x,v.x);m.min.z=min(m.min.z,v.z);m.max.x=max(m.max.x,v.x);m.max.z=max(m.max.z,v.z)};append(&m.primitives,Glb_Primitive_Range{0,roof_surface_count,-1,{.32,.38,.43,1}},Glb_Primitive_Range{roof_surface_count,len(m.indices)-roof_surface_count,-1,{.46,.47,.45,1}});m.ready=true;return m
}

procedural_rect_mansard_mesh :: proc(points:[]Vec2,pitch,overhang,ridge_angle:f32)->Glb_Mesh {
	m:Glb_Mesh;if len(points)!=4 do return m;expanded:=roof_offset_polygon(points,overhang);angle:=ridge_angle*f32(math.PI)/180;ux,uy:=f32(math.cos(f64(angle))),f32(math.sin(f64(angle)));nx,ny:= -uy,ux;min_u,max_u,min_n,max_n:=f32(1e30),f32(-1e30),f32(1e30),f32(-1e30)
	for p in expanded {along,cross:=p.x*ux+p.y*uy,p.x*nx+p.y*ny;min_u=min(min_u,along);max_u=max(max_u,along);min_n=min(min_n,cross);max_n=max(max_n,cross)};width,depth:=max_u-min_u,max_n-min_n;if width<2||depth<2 do return m
	inset:=min(min(width,depth)*.22,f32(1.35));iu0,iu1,in0,in1:=min_u+inset,max_u-inset,min_n+inset,max_n-inset;eave:=f32(.08);lower_top:=eave+inset*max(f32(math.tan(f64(max(pitch,55)*f32(math.PI)/180))),1.4);cap_peak:=lower_top+min(iu1-iu0,in1-in0)*.16
	m.vertices=make([dynamic]Vec3,0,64);m.texcoords=make([dynamic]Vec2,0,64);m.indices=make([dynamic]u32,0,180);m.primitives=make([dynamic]Glb_Primitive_Range,0,2)
	coords:=[8][2]f32{{min_u,min_n},{max_u,min_n},{max_u,max_n},{min_u,max_n},{iu0,in0},{iu1,in0},{iu1,in1},{iu0,in1}};for coord,i in coords {height:=i<4?eave:lower_top;v:=roof_axis_point(coord[0],coord[1],height,ux,uy,nx,ny);append(&m.vertices,v);append(&m.texcoords,Vec2{v.x*.2,v.z*.2})};for side in 0..<4 {next:=(side+1)%4;roof_add_triangle(&m,u32(side),u32(next),u32(4+next));roof_add_triangle(&m,u32(side),u32(4+next),u32(4+side))};peak:=u32(len(m.vertices));center_u,center_n:=(min_u+max_u)*.5,(min_n+max_n)*.5;pv:=roof_axis_point(center_u,center_n,cap_peak,ux,uy,nx,ny);append(&m.vertices,pv);append(&m.texcoords,Vec2{pv.x*.2,pv.z*.2});for side in 0..<4 do roof_add_triangle(&m,u32(4+side),u32(4+(side+1)%4),peak)
	// Dormers are authored roof-window entities, not repeated by the roof style.
	roof_surface_count:=len(m.indices);roof_add_soffit_ring(&m,points,expanded)
	m.min={1e30,0,1e30};m.max={-1e30,cap_peak,-1e30};for v in m.vertices {m.min.x=min(m.min.x,v.x);m.min.z=min(m.min.z,v.z);m.max.x=max(m.max.x,v.x);m.max.z=max(m.max.z,v.z)};append(&m.primitives,Glb_Primitive_Range{0,roof_surface_count,-1,{.30,.34,.39,1}},Glb_Primitive_Range{roof_surface_count,len(m.indices)-roof_surface_count,-1,{.46,.47,.45,1}});m.ready=true;return m
}

procedural_parapet_mesh :: proc(points:[]Vec2,overhang:f32)->Glb_Mesh {
	m:=procedural_roof_mesh(points,.Flat,2,overhang,0);if !m.ready do return m;expanded:=roof_offset_polygon(points,overhang)
	parapet_start:=len(m.indices)
	for a,i in expanded {b:=expanded[(i+1)%len(expanded)];dx,dy:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dy*dy)));if length<.01 do continue;center:=Vec2{(a.x+b.x)*.5,(a.y+b.y)*.5};yaw:=f32(math.atan2(f64(dy),f64(dx)));stair_add_box(&m,center,.06,.48,length,.18,yaw)}
	if len(m.indices)>parapet_start do append(&m.primitives,Glb_Primitive_Range{parapet_start,len(m.indices)-parapet_start,-1,{.30,.34,.39,1}});m.max.y=max(m.max.y,.48);return m
}

procedural_roof_mesh :: proc(points:[]Vec2,style:Level_Roof_Style,pitch,overhang,ridge_angle:f32)->Glb_Mesh {
	m:Glb_Mesh;if len(points)<3 do return m
	if style==.Gable&&len(points)==4 {gable:=procedural_rect_gable_mesh(points,pitch,overhang,ridge_angle);if gable.ready do return gable}
	if style==.Mansard&&len(points)==4 {mansard:=procedural_rect_mansard_mesh(points,pitch,overhang,ridge_angle);if mansard.ready do return mansard}
	if style==.Parapet do return procedural_parapet_mesh(points,overhang)
	center:=Vec2{};for p in points {center.x+=p.x;center.y+=p.y};center.x/=f32(len(points));center.y/=f32(len(points))
	expanded:=roof_offset_polygon(points,overhang)
	angle:=ridge_angle*f32(math.PI)/180;nx,ny:= -f32(math.sin(f64(angle))),f32(math.cos(f64(angle)));min_cross,max_cross:=f32(1e30),f32(-1e30);for p in expanded {cross:=p.x*nx+p.y*ny;min_cross=min(min_cross,cross);max_cross=max(max_cross,cross)};middle:=(min_cross+max_cross)*.5;slope:=f32(math.tan(f64(pitch*f32(math.PI)/180)))
	m.vertices=make([dynamic]Vec3,0,len(points)+1);m.texcoords=make([dynamic]Vec2,0,len(points)+1);m.indices=make([dynamic]u32,0,len(points)*12);m.primitives=make([dynamic]Glb_Primitive_Range,0,1)
	for p in expanded {height:=f32(.08);if style==.Gable do height+=(max_cross-min_cross)*.5-math.abs(p.x*nx+p.y*ny-middle);height=max(height,.08);append(&m.vertices,Vec3{p.x,height*max(slope,f32(.01)),p.y});append(&m.texcoords,Vec2{p.x*.2,p.y*.2})}
	if style==.Hip {distance:=f32(1e30);for i in 0..<len(expanded) {d,_:=level_segment_distance(center,expanded[i],expanded[(i+1)%len(expanded)]);distance=min(distance,d)};peak:=u32(len(m.vertices));append(&m.vertices,Vec3{center.x,max(.12,distance*slope),center.y});append(&m.texcoords,Vec2{center.x*.2,center.y*.2});for i in 0..<len(expanded) do roof_add_triangle(&m,u32(i),u32((i+1)%len(expanded)),peak)} else {
		area:f32=0;for i in 0..<len(expanded) {j:=(i+1)%len(expanded);area+=expanded[i].x*expanded[j].y-expanded[j].x*expanded[i].y};winding:f32=area>=0?1:-1;remaining:=make([dynamic]int,0,len(expanded));defer delete(remaining);for i in 0..<len(expanded) do append(&remaining,i);guard:=0;for len(remaining)>2&&guard<len(expanded)*len(expanded) {clipped:=false;for cursor in 0..<len(remaining) {previous:=remaining[(cursor+len(remaining)-1)%len(remaining)];current:=remaining[cursor];next:=remaining[(cursor+1)%len(remaining)];if wall_cap_cross(expanded[previous],expanded[current],expanded[next])*winding<=.000001 do continue;occupied:=false;for candidate in remaining {if candidate==previous||candidate==current||candidate==next do continue;if wall_cap_contains(expanded[candidate],expanded[previous],expanded[current],expanded[next],winding) {occupied=true;break}};if occupied do continue;roof_add_triangle(&m,u32(previous),u32(current),u32(next));ordered_remove(&remaining,cursor);clipped=true;break};if !clipped do break;guard+=1}
	}
	// A fascia closes the boundary and removes the paper-thin edge common to
	// procedural roofs, especially around angled room corners.
	for i in 0..<len(expanded) {j:=(i+1)%len(expanded);top_a,top_b:=m.vertices[i],m.vertices[j];base:=u32(len(m.vertices));append(&m.vertices,top_a,top_b,Vec3{top_b.x,0,top_b.z},Vec3{top_a.x,0,top_a.z});append(&m.texcoords,Vec2{0,0},Vec2{1,0},Vec2{1,1},Vec2{0,1});roof_add_triangle(&m,base,base+1,base+2);roof_add_triangle(&m,base,base+2,base+3)}
	roof_surface_count:=len(m.indices);roof_add_soffit_ring(&m,points,expanded)
	m.min={1e30,1e30,1e30};m.max={-1e30,-1e30,-1e30};for v in m.vertices {m.min.x=min(m.min.x,v.x);m.min.y=min(m.min.y,v.y);m.min.z=min(m.min.z,v.z);m.max.x=max(m.max.x,v.x);m.max.y=max(m.max.y,v.y);m.max.z=max(m.max.z,v.z)};append(&m.primitives,Glb_Primitive_Range{0,roof_surface_count,-1,{.32,.38,.43,1}},Glb_Primitive_Range{roof_surface_count,len(m.indices)-roof_surface_count,-1,{.46,.47,.45,1}});m.ready=len(m.indices)>0;return m
}

roof_courtyard_ridge :: proc(doc:^Level_Document,room:Level_Room)->(f32,bool) {
	// An exterior room enclosed by interior rooms is a courtyard hole. A roof
	// wing bordering that hole needs a ridge parallel to the shared courtyard
	// edge; a room-local hip peak closes the hole visually and produces invalid
	// diagonal facets on concave rooms.
	best_length:=f32(0);best_angle:=f32(0)
	for courtyard in doc.rooms {
		if !courtyard.exterior||courtyard.story!=room.story do continue
		for a,i in room.points {b:=room.points[(i+1)%len(room.points)];rdx,rdy:=b.x-a.x,b.y-a.y;rlen:=f32(math.sqrt(f64(rdx*rdx+rdy*rdy)));if rlen<.001 do continue
			for c,j in courtyard.points {d:=courtyard.points[(j+1)%len(courtyard.points)];cdx,cdy:=d.x-c.x,d.y-c.y;clen:=f32(math.sqrt(f64(cdx*cdx+cdy*cdy)));if clen<.001 do continue;if math.abs(rdx*cdy-rdy*cdx)>.001*rlen*clen do continue;if point_segment_distance_sq(c.x,c.y,a,b)>.001&&point_segment_distance_sq(d.x,d.y,a,b)>.001&&point_segment_distance_sq(a.x,a.y,c,d)>.001&&point_segment_distance_sq(b.x,b.y,c,d)>.001 do continue
				axis_x,axis_y:=rdx/rlen,rdy/rlen;room_min,room_max:=a.x*axis_x+a.y*axis_y,b.x*axis_x+b.y*axis_y;if room_min>room_max do room_min,room_max=room_max,room_min;court_min,court_max:=c.x*axis_x+c.y*axis_y,d.x*axis_x+d.y*axis_y;if court_min>court_max do court_min,court_max=court_max,court_min;overlap:=min(room_max,court_max)-max(room_min,court_min);if overlap>best_length+.001 {best_length=overlap;best_angle=f32(math.atan2(f64(rdy),f64(rdx)))*180/f32(math.PI)}
			}
		}
	}
	return best_angle,best_length>.001
}

roof_story_interior_at :: proc(doc:^Level_Document,story:int,p:Vec2)->bool {for room in doc.rooms do if room.story==story&&!room.exterior&&level_point_in_polygon(p,room.points[:]) do return true;return false}
roof_story_has_courtyard :: proc(doc:^Level_Document,story:int)->bool {for room in doc.rooms do if room.story==story&&room.exterior do return true;return false}

// Roof materials are directional. Each plane owns a render-space UV seam:
// U follows its eave/ridge, while V climbs the slope. Positions at those seams
// remain numerically identical, so the architectural surface is still welded.
roof_add_shingle_quad :: proc(mesh:^Glb_Mesh,eave_a,eave_b,ridge_b,ridge_a:Vec3,hole_side:=false) {
	base:=u32(len(mesh.vertices));append(&mesh.vertices,eave_a,eave_b,ridge_b,ridge_a)
	eave_dx,eave_dz:=eave_b.x-eave_a.x,eave_b.z-eave_a.z
	rise_dx,rise_dy,rise_dz:=ridge_a.x-eave_a.x,ridge_a.y-eave_a.y,ridge_a.z-eave_a.z
	u:=f32(math.sqrt(f64(eave_dx*eave_dx+eave_dz*eave_dz)))*.2
	v:=f32(math.sqrt(f64(rise_dx*rise_dx+rise_dy*rise_dy+rise_dz*rise_dz)))*.2
	append(&mesh.texcoords,Vec2{0,0},Vec2{u,0},Vec2{u,v},Vec2{0,v})
	if hole_side {
		append(&mesh.indices,base,base+1,base+2,base,base+2,base+3)
	} else {
		append(&mesh.indices,base,base+2,base+1,base,base+3,base+2)
	}
}

procedural_compound_roof_mesh :: proc(doc:^Level_Document,story:int,pitch,overhang:f32)->Glb_Mesh {
	// This is one polygon-with-a-hole roof, not four room roofs and not a
	// rasterized slab. The two boundary loops have opposite semantic winding:
	// the outer loop bounds solid roof, while the courtyard loop bounds empty air.
	// Their simultaneous rectangular wavefronts meet at the shared ridge loop.
	m:Glb_Mesh
	outer_min,outer_max:=Vec2{1e30,1e30},Vec2{-1e30,-1e30};found_interior:=false
	hole_min,hole_max:=Vec2{1e30,1e30},Vec2{-1e30,-1e30};found_hole:=false
	for room in doc.rooms {
		if room.story!=story do continue
		if room.exterior {
			if found_hole do return m // This exact topology supports one hole.
			for p in room.points {hole_min.x=min(hole_min.x,p.x);hole_min.y=min(hole_min.y,p.y);hole_max.x=max(hole_max.x,p.x);hole_max.y=max(hole_max.y,p.y)}
			found_hole=len(room.points)==4
		} else {
			for p in room.points {outer_min.x=min(outer_min.x,p.x);outer_min.y=min(outer_min.y,p.y);outer_max.x=max(outer_max.x,p.x);outer_max.y=max(outer_max.y,p.y)}
			found_interior=true
		}
	}
	if !found_interior||!found_hole||hole_min.x<=outer_min.x||hole_min.y<=outer_min.y||hole_max.x>=outer_max.x||hole_max.y>=outer_max.y do return m
	wall_outer:=[4]Vec2{{outer_min.x,outer_min.y},{outer_max.x,outer_min.y},{outer_max.x,outer_max.y},{outer_min.x,outer_max.y}}
	wall_hole:=[4]Vec2{{hole_min.x,hole_min.y},{hole_min.x,hole_max.y},{hole_max.x,hole_max.y},{hole_max.x,hole_min.y}}

	// Room polygons follow wall centerlines. Extend the exterior eave beyond the
	// outside face and shrink the courtyard hole so its eave covers the inner
	// wall plate. Previously this path ignored every authored overhang.
	clamped_overhang:=max(overhang,0)
	outer_min.x-=clamped_overhang;outer_min.y-=clamped_overhang;outer_max.x+=clamped_overhang;outer_max.y+=clamped_overhang
	hole_min.x+=clamped_overhang;hole_min.y+=clamped_overhang;hole_max.x-=clamped_overhang;hole_max.y-=clamped_overhang
	if hole_min.x>=hole_max.x||hole_min.y>=hole_max.y do return m

	// Each ridge coordinate is the meeting point of the opposed wavefronts.
	// Vertex height is distance to the first boundary that reaches that junction.
	ridge_min:=Vec2{(outer_min.x+hole_min.x)*.5,(outer_min.y+hole_min.y)*.5}
	ridge_max:=Vec2{(outer_max.x+hole_max.x)*.5,(outer_max.y+hole_max.y)*.5}
	slope:=max(f32(math.tan(f64(pitch*f32(math.PI)/180))),.01);eave:=f32(.08)
	left_run,right_run:=(hole_min.x-outer_min.x)*.5,(outer_max.x-hole_max.x)*.5
	top_run,bottom_run:=(hole_min.y-outer_min.y)*.5,(outer_max.y-hole_max.y)*.5
	// A closed rectangular ridge is one continuous elevation. The narrowest
	// opposed wavefront collision is the limiting event; using it at all four
	// junctions keeps every emitted quadrilateral exactly planar even when an
	// authored courtyard is slightly off-centre.
	ridge_height:=eave+min(min(left_run,right_run),min(top_run,bottom_run))*slope
	ridge_heights:=[4]f32{ridge_height,ridge_height,ridge_height,ridge_height}
	outer:=[4]Vec2{{outer_min.x,outer_min.y},{outer_max.x,outer_min.y},{outer_max.x,outer_max.y},{outer_min.x,outer_max.y}}
	ridge:=[4]Vec2{{ridge_min.x,ridge_min.y},{ridge_max.x,ridge_min.y},{ridge_max.x,ridge_max.y},{ridge_min.x,ridge_max.y}}
	// Clockwise hole order is intentional and opposite the CCW outer loop.
	hole:=[4]Vec2{{hole_min.x,hole_min.y},{hole_min.x,hole_max.y},{hole_max.x,hole_max.y},{hole_max.x,hole_min.y}}
	m.vertices=make([dynamic]Vec3,0,32);m.texcoords=make([dynamic]Vec2,0,32);m.indices=make([dynamic]u32,0,48);m.primitives=make([dynamic]Glb_Primitive_Range,0,1)
	// Eight deliberate planar faces. UV seams duplicate render vertices, but all
	// shared ridge/corner positions come from these same authoritative arrays.
	hole_side_start:=[4]int{0,3,2,1};hole_side_end:=[4]int{3,2,1,0}
	for side in 0..<4 {
		next:=(side+1)%4
		o0,o1,r0,r1:=outer[side],outer[next],ridge[side],ridge[next]
		roof_add_shingle_quad(&m,{o0.x,eave,o0.y},{o1.x,eave,o1.y},{r1.x,ridge_heights[next],r1.y},{r0.x,ridge_heights[side],r0.y})
		h0,h1:=hole[hole_side_start[side]],hole[hole_side_end[side]]
		roof_add_shingle_quad(&m,{h0.x,eave,h0.y},{h1.x,eave,h1.y},{r1.x,ridge_heights[next],r1.y},{r0.x,ridge_heights[side],r0.y},true)
	}
	roof_surface_count:=len(m.indices);roof_add_soffit_ring(&m,wall_outer[:],outer[:]);roof_add_soffit_ring(&m,wall_hole[:],hole[:])
	m.min={outer_min.x,0,outer_min.y};m.max={outer_max.x,eave,outer_max.y};for height in ridge_heights do m.max.y=max(m.max.y,height)
	append(&m.primitives,Glb_Primitive_Range{0,roof_surface_count,-1,{.34,.37,.40,1}},Glb_Primitive_Range{roof_surface_count,len(m.indices)-roof_surface_count,-1,{.46,.47,.45,1}});m.ready=true;return m
}

rebuild_generated_roofs :: proc(doc:^Level_Document) {
	generated_roof_count=0;for i in 0..<GENERATED_ROOF_CAPACITY do generated_roof_has_gutters[i]=false
	for story_index in 0..<len(doc.stories) {if !roof_story_has_courtyard(doc,story_index) do continue;pitch,overhang:=f32(30),f32(.4);for roof in doc.roofs {if roof.story!=story_index do continue;if roof.pitch>0 do pitch=roof.pitch;overhang=max(overhang,roof.overhang)};mesh:=procedural_compound_roof_mesh(doc,story_index,pitch,overhang);if !mesh.ready do continue;apply_texture(&mesh,roof_texture);generated_roof_meshes[generated_roof_count]=mesh;generated_roof_base_y[generated_roof_count]=doc.stories[story_index].base_elevation+doc.stories[story_index].wall_height;generated_roof_story[generated_roof_count]=story_index;generated_roof_style[generated_roof_count]=.Hip;generated_roof_count+=1}
	for room in doc.rooms {
		if generated_roof_count>=GENERATED_ROOF_CAPACITY do continue
		if room.exterior||roof_story_has_courtyard(doc,room.story) do continue
		roof:=Level_Roof{id=fmt.tprintf("generated_roof_%s",room.id),room_id=room.id,story=room.story,style=.Gable,pitch=30,overhang=.4,ridge_angle=0};roof_index:=level_roof_for_room(doc,room.id);if roof_index>=0 do roof=doc.roofs[roof_index]
		style,ridge_angle:=roof.style,roof.ridge_angle;if courtyard_angle,borders_courtyard:=roof_courtyard_ridge(doc,room);borders_courtyard&&(style==.Gable||style==.Hip) {style=.Gable;ridge_angle=courtyard_angle}
		base_y:=room.platform_height+f32(2.5);if room.story>=0&&room.story<len(doc.stories) do base_y+=doc.stories[room.story].base_elevation+doc.stories[room.story].wall_height-2.5
		generated_roof_meshes[generated_roof_count]=procedural_roof_mesh(room.points[:],style,roof.pitch,roof.overhang,ridge_angle);apply_texture(&generated_roof_meshes[generated_roof_count],roof_texture);generated_roof_base_y[generated_roof_count]=base_y;generated_roof_story[generated_roof_count]=roof.story;generated_roof_style[generated_roof_count]=style;generated_roof_count+=1
		if roof.gutters {eaves:=roof_offset_polygon(room.points[:],roof.overhang);points:=make([]Vec2,len(eaves)+1,context.temp_allocator);copy(points,eaves);points[len(eaves)]=eaves[0];generated_roof_gutter_meshes[generated_roof_count-1]=procedural_wall_run_mesh(points,.14,.16);generated_roof_has_gutters[generated_roof_count-1]=generated_roof_gutter_meshes[generated_roof_count-1].ready}
	}
	generated_roof_revision=doc.revision
}

house_plan_initialize :: proc() {
	house_plan={level=0,wall_splines=make([dynamic]Floorplan_Spline,0,len(HOUSE_WALL_SPLINES)),openings=make([dynamic]Plan_Opening,0,16),wall_face_paints=make([dynamic]Wall_Face_Paint,0,16),furniture=make([dynamic]Furniture,0,0),initialized=true,revision=1,dirty=true}
	for spline in HOUSE_WALL_SPLINES do append(&house_plan.wall_splines,spline)
	for y in 0..<HOUSE_SURFACE_HEIGHT {for x in 0..<HOUSE_SURFACE_WIDTH {inside:=x<24&&y<16;surface:=inside?house_surface_seed_at(f32(x)+.5,f32(y)+.5):.Garden;house_plan.surfaces[y*HOUSE_SURFACE_WIDTH+x]=surface;house_plan.space_kinds[y*HOUSE_SURFACE_WIDTH+x]=inside&&surface!=.Garden?.Interior:.Grounds}}
	// Existing authored gaps are now explicit architectural openings. New build
	// commands use the same representation, rather than creating magic holes.
	append(&house_plan.openings,Plan_Opening{a={11.2,0},b={12.8,0},kind=.Door},Plan_Opening{a={11.2,16},b={12.8,16},kind=.Door},Plan_Opening{a={14,1.7},b={14,3.1},kind=.Door},Plan_Opening{a={8,7.6},b={8,9.2},kind=.Door},Plan_Opening{a={16,7.6},b={16,9.2},kind=.Door},Plan_Opening{a={8,13.3},b={8,14.7},kind=.Door},Plan_Opening{a={16,13.3},b={16,14.7},kind=.Door},Plan_Opening{a={10.6,5},b={12,5},kind=.Door},Plan_Opening{a={10.6,12},b={12,12},kind=.Door})
	// Broad, repeated glazing is what makes the low 1970s ranch read as an
	// atrium house rather than a corridor of closed boxes.
	append(&house_plan.openings,Plan_Opening{a={2,0},b={4,0},kind=.Window,height=1.4},Plan_Opening{a={7,0},b={9,0},kind=.Window,height=1.4},Plan_Opening{a={16,0},b={18,0},kind=.Window,height=1.4},Plan_Opening{a={21,0},b={23,0},kind=.Window,height=1.4},Plan_Opening{a={24,11},b={24,13},kind=.Window,height=1.4},Plan_Opening{a={0,11},b={0,13},kind=.Window,height=1.4})
}

house_snapshot :: proc()->Build_Snapshot {
	result:Build_Snapshot;result.wall_splines=make([dynamic]Floorplan_Spline,0,len(house_plan.wall_splines));result.openings=make([dynamic]Plan_Opening,0,len(house_plan.openings));result.wall_face_paints=make([dynamic]Wall_Face_Paint,0,len(house_plan.wall_face_paints));result.furniture=make([dynamic]Furniture,0,len(house_plan.furniture));for item in house_plan.wall_splines do append(&result.wall_splines,item);for item in house_plan.openings do append(&result.openings,item);for item in house_plan.wall_face_paints do append(&result.wall_face_paints,item);for item in house_plan.furniture do append(&result.furniture,item);result.surfaces=house_plan.surfaces;result.space_kinds=house_plan.space_kinds;result.revision=house_plan.revision;return result
}

house_restore :: proc(snapshot:Build_Snapshot) {house_plan.wall_splines=snapshot.wall_splines;house_plan.openings=snapshot.openings;house_plan.wall_face_paints=snapshot.wall_face_paints;house_plan.furniture=snapshot.furniture;house_plan.surfaces=snapshot.surfaces;house_plan.space_kinds=snapshot.space_kinds;house_plan.revision=snapshot.revision;house_plan.dirty=true;build_house_floorplan();build_house_navmesh();_=house_plan_validate()}
house_push_undo :: proc() {if house_plan.undo_count>=len(house_plan.undo) {for i in 1..<len(house_plan.undo) do house_plan.undo[i-1]=house_plan.undo[i];house_plan.undo_count-=1};house_plan.undo[house_plan.undo_count]=house_snapshot();house_plan.undo_count+=1;house_plan.redo_count=0}
house_undo :: proc()->bool {if house_plan.undo_count<=0 do return false;if house_plan.redo_count<len(house_plan.redo) {house_plan.redo[house_plan.redo_count]=house_snapshot();house_plan.redo_count+=1};house_plan.undo_count-=1;house_restore(house_plan.undo[house_plan.undo_count]);return true}
house_redo :: proc()->bool {if house_plan.redo_count<=0 do return false;if house_plan.undo_count<len(house_plan.undo) {house_plan.undo[house_plan.undo_count]=house_snapshot();house_plan.undo_count+=1};house_plan.redo_count-=1;house_restore(house_plan.redo[house_plan.redo_count]);return true}

house_opening_contains :: proc(opening:Plan_Opening,x,y:f32)->bool {
	return point_segment_distance_sq(x,y,opening.a,opening.b)<.28*.28
}

house_snap_opening :: proc(point:Vec2,kind:Opening_Kind)->(opening:Plan_Opening,ok:bool) {
	best:f32=1e30
	for spline in house_plan.wall_splines {for i in 0..<len(spline.points)-1 {
		a,b:=spline.points[i],spline.points[i+1];dx,dy:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dy*dy)));if length<1.2 do continue
		t:=clamp(((point.x-a.x)*dx+(point.y-a.y)*dy)/(length*length),0,1);px,py:=a.x+dx*t,a.y+dy*t;distance:=(point.x-px)*(point.x-px)+(point.y-py)*(point.y-py)
		if distance<best {half:f32=kind==.Door?.72:.88;center:=clamp(t,half/length,1-half/length);opening={a={a.x+dx*(center-half/length),a.y+dy*(center-half/length)},b={a.x+dx*(center+half/length),a.y+dy*(center+half/length)},kind=kind,height=kind==.Window?1.4:2.1};best=distance}
	}}
	return opening,best<.8*.8
}

house_snap_wall_face :: proc(point:Vec2)->(paint:Wall_Face_Paint,ok:bool) {
	best:f32=1e30
	for spline in house_plan.wall_splines {for i in 0..<len(spline.points)-1 {
		a,b:=spline.points[i],spline.points[i+1];dx,dz:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dz*dz)));if length<=.01 do continue
		t:=clamp(((point.x-a.x)*dx+(point.y-a.y)*dz)/(length*length),0,1);px,pz:=a.x+dx*t,a.y+dz*t;distance:=(point.x-px)*(point.x-px)+(point.y-pz)*(point.y-pz)
		if distance<best {nx,nz:= -dz/length,dx/length;paint={a,b,(point.x-px)*nx+(point.y-pz)*nz>=0,.Dining};best=distance}
	}}
	return paint,best<.8*.8
}

// Strict build validation treats the generated navmesh as an architectural
// invariant. A wall may shape circulation, but it may not strand a usable
// portion of the house behind an unintentional sealed partition.
house_plan_has_single_navigable_component :: proc()->bool {
	walkable:[HOUSE_NAV_CELLS]bool;visited:[HOUSE_NAV_CELLS]bool;queue:[HOUSE_NAV_CELLS]int
	first:=-1;walkable_count:=0
	for y in 0..<HOUSE_NAV_HEIGHT {for x in 0..<HOUSE_NAV_WIDTH {
		index:=y*HOUSE_NAV_WIDTH+x;center:=Vec2{f32(x)*HOUSE_NAV_CELL+HOUSE_NAV_CELL*.5,f32(y)*HOUSE_NAV_CELL+HOUSE_NAV_CELL*.5}
		walkable[index]=nav_point_walkable(center.x,center.y)
		if walkable[index] {walkable_count+=1;if first<0 do first=index}
	}}
	if first<0 do return false
	head,tail:=0,1;queue[0]=first;visited[first]=true;visited_count:=0
	for head<tail {
		current:=queue[head];head+=1;visited_count+=1;cx,cy:=current%HOUSE_NAV_WIDTH,current/HOUSE_NAV_WIDTH
		for axis in 0..<4 {
			ox,oy:=0,0;switch axis {case 0: ox=1;case 1: ox=-1;case 2: oy=1;case: oy=-1}
			nx,ny:=cx+ox,cy+oy;if nx<0||ny<0||nx>=HOUSE_NAV_WIDTH||ny>=HOUSE_NAV_HEIGHT do continue
			next:=ny*HOUSE_NAV_WIDTH+nx;if walkable[next]&&!visited[next] {visited[next]=true;queue[tail]=next;tail+=1}
		}
	}
	return visited_count==walkable_count
}

// Room paint follows actual architectural boundaries, including open doors,
// rather than treating a material name as a room identifier.
house_paint_connected_room :: proc(point:Vec2,surface:Room_Surface)->bool {
	start_x,start_y:=int(point.x),int(point.y);if start_x<0||start_x>=HOUSE_SURFACE_WIDTH||start_y<0||start_y>=HOUSE_SURFACE_HEIGHT do return false
	from:=house_plan.surfaces[start_y*HOUSE_SURFACE_WIDTH+start_x];seen:[HOUSE_SURFACE_CELLS]bool;queue:[HOUSE_SURFACE_CELLS]int;head,tail:=0,1;queue[0]=start_y*HOUSE_SURFACE_WIDTH+start_x;seen[queue[0]]=true
	for head<tail {
		current:=queue[head];head+=1;cx,cy:=current%HOUSE_SURFACE_WIDTH,current/HOUSE_SURFACE_WIDTH;house_plan.surfaces[current]=surface;house_plan.space_kinds[current]=surface==.Garden?.Grounds:.Interior
		for axis in 0..<4 {
			ox,oy:=0,0;switch axis {case 0:ox=1;case 1:ox=-1;case 2:oy=1;case:oy=-1};nx,ny:=cx+ox,cy+oy;if nx<0||ny<0||nx>=HOUSE_SURFACE_WIDTH||ny>=HOUSE_SURFACE_HEIGHT do continue
			next:=ny*HOUSE_SURFACE_WIDTH+nx;if seen[next]||house_plan.surfaces[next]!=from do continue
			// The midpoint is a wall test; openings allow the fill through.
			if world_wall(f32(cx+nx+1)*.5,f32(cy+ny+1)*.5) do continue
			seen[next]=true;queue[tail]=next;tail+=1
		}
	}
	return true
}

house_set_connected_space_kind :: proc(point:Vec2,space:Plan_Space_Kind)->bool {
	start_x,start_y:=int(point.x),int(point.y);if start_x<0||start_x>=HOUSE_SURFACE_WIDTH||start_y<0||start_y>=HOUSE_SURFACE_HEIGHT do return false
	from:=house_plan.surfaces[start_y*HOUSE_SURFACE_WIDTH+start_x];seen:[HOUSE_SURFACE_CELLS]bool;queue:[HOUSE_SURFACE_CELLS]int;head,tail:=0,1;queue[0]=start_y*HOUSE_SURFACE_WIDTH+start_x;seen[queue[0]]=true
	for head<tail {
		current:=queue[head];head+=1;cx,cy:=current%HOUSE_SURFACE_WIDTH,current/HOUSE_SURFACE_WIDTH;house_plan.space_kinds[current]=space
		for axis in 0..<4 {ox,oy:=0,0;switch axis {case 0:ox=1;case 1:ox=-1;case 2:oy=1;case:oy=-1};nx,ny:=cx+ox,cy+oy;if nx<0||ny<0||nx>=HOUSE_SURFACE_WIDTH||ny>=HOUSE_SURFACE_HEIGHT do continue;next:=ny*HOUSE_SURFACE_WIDTH+nx;if seen[next]||house_plan.surfaces[next]!=from do continue;if world_wall(f32(cx+nx+1)*.5,f32(cy+ny+1)*.5) do continue;seen[next]=true;queue[tail]=next;tail+=1}
	}
	return true
}

house_plan_validate :: proc()->bool {
	if len(house_plan.wall_splines)==0 {house_plan.validation="A house needs a structural shell.";return false}
	for opening in house_plan.openings {
		found:=false;for spline in house_plan.wall_splines {for i in 0..<len(spline.points)-1 do if point_segment_distance_sq((opening.a.x+opening.b.x)*.5,(opening.a.y+opening.b.y)*.5,spline.points[i],spline.points[i+1])<.08*.08 {found=true;break}};if opening.kind==.Window&&!found {house_plan.validation="Windows must snap to a wall section.";return false}
		if opening.kind==.Window&&!(opening.a.x<.22||opening.a.x>23.78||opening.a.y<.22||opening.a.y>15.78||opening.b.x<.22||opening.b.x>23.78||opening.b.y<.22||opening.b.y>15.78) {house_plan.validation="Windows belong on exterior or atrium-facing walls.";return false}
	}
	for item,i in house_plan.furniture {if item.x<.5||item.x>39.5||item.y<.5||item.y>33.5 {house_plan.validation="Furniture must remain inside the estate bounds.";return false};for other,j in house_plan.furniture {if j<=i do continue;dx,dy:=item.x-other.x,item.y-other.y;if dx*dx+dy*dy<(item.radius+other.radius+.18)*(item.radius+other.radius+.18) {house_plan.validation="Furniture footprints overlap.";return false}}}
	// Expanded lots may contain several intentionally separated lawn pockets
	// outside the authored fence line; room connectivity is tested separately.
	// Navigation reachability is validated against the active level and its
	// authored transition markers by the playtest suite; lawn pockets need not
	// form one component with every interior paint region.
	house_plan.validation="PLAN VALID";return true
}

house_apply_command :: proc(command:Build_Command)->bool {
	if !house_plan_validate() do return false
	house_push_undo()
	switch command.kind {
	case .Create_Room:
		min_x,max_x:=clamp(int(min(command.a.x,command.b.x)),0,HOUSE_SURFACE_WIDTH-2),clamp(int(max(command.a.x,command.b.x)),1,HOUSE_SURFACE_WIDTH);min_y,max_y:=clamp(int(min(command.a.y,command.b.y)),0,HOUSE_SURFACE_HEIGHT-2),clamp(int(max(command.a.y,command.b.y)),1,HOUSE_SURFACE_HEIGHT)
		if max_x-min_x<3||max_y-min_y<3 {house_plan.validation="Rooms need at least a 3 × 3 tile footprint.";house_plan.undo_count-=1;return false}
		for y:=min_y;y<max_y;y+=1 {for x:=min_x;x<max_x;x+=1 {house_plan.surfaces[y*HOUSE_SURFACE_WIDTH+x]=command.surface;house_plan.space_kinds[y*HOUSE_SURFACE_WIDTH+x]=command.surface==.Garden?.Grounds:.Interior}}
		append(&house_plan.wall_splines,Floorplan_Spline{[]Vec2{{f32(min_x),f32(min_y)},{f32(max_x),f32(min_y)},{f32(max_x),f32(max_y)},{f32(min_x),f32(max_y)},{f32(min_x),f32(min_y)}},0})
	case .Set_Wall: append(&house_plan.wall_splines,Floorplan_Spline{[]Vec2{command.a,command.b},0})
	case .Place_Opening:
		opening,ok:=house_snap_opening(command.a,command.opening);if !ok {house_plan.validation="Select an existing wall span for the opening.";house_plan.undo_count-=1;return false};append(&house_plan.openings,opening)
	case .Place_Object: append(&house_plan.furniture,command.furniture)
	case .Move_Object: if command.index<0||command.index>=len(house_plan.furniture) {house_plan.validation="Object does not exist.";house_plan.undo_count-=1;return false}else{house_plan.furniture[command.index].x=command.a.x;house_plan.furniture[command.index].y=command.a.y}
	case .Delete_Object: if command.index<0||command.index>=len(house_plan.furniture) {house_plan.validation="Object does not exist.";house_plan.undo_count-=1;return false};ordered_remove(&house_plan.furniture,command.index)
	case .Paint_Room:
		if !house_paint_connected_room(command.a,command.surface) {house_plan.validation="Select a room inside the house footprint.";house_plan.undo_count-=1;return false}
	case .Set_Space_Kind:
		if !house_set_connected_space_kind(command.a,command.space) {house_plan.validation="Select a room inside the house footprint.";house_plan.undo_count-=1;return false}
	case .Paint_Wall_Side:
		paint,ok:=house_snap_wall_face(command.a);if !ok {house_plan.validation="Select a wall face to paint.";house_plan.undo_count-=1;return false};paint.surface=command.surface;append(&house_plan.wall_face_paints,paint)
	}
	if !house_plan_validate() {house_plan.undo_count-=1;house_restore(house_plan.undo[house_plan.undo_count]);return false}
	house_plan.revision+=1;house_plan.dirty=true;build_house_floorplan();build_house_navmesh();return true
}

house_surface_seed_at :: proc(x,z:f32)->Room_Surface {
	if x>=8&&x<16&&z>=5&&z<12 do return .Garden
	if z<5 do return x<14?.Dining:.Pantry
	if x<8 do return .Study
	if x>=16 do return .Pantry
	return .Gallery
}

house_surface_at :: proc(x,z:f32)->Room_Surface {
	if house_plan.initialized {ix,iz:=clamp(int(x),0,HOUSE_SURFACE_WIDTH-1),clamp(int(z),0,HOUSE_SURFACE_HEIGHT-1);return house_plan.surfaces[iz*HOUSE_SURFACE_WIDTH+ix]}
	return house_surface_seed_at(x,z)
}

house_space_kind_at :: proc(x,z:f32)->Plan_Space_Kind {
	if !house_plan.initialized do return house_surface_seed_at(x,z)==.Garden?.Grounds:.Interior
	ix,iz:=clamp(int(x),0,HOUSE_SURFACE_WIDTH-1),clamp(int(z),0,HOUSE_SURFACE_HEIGHT-1);return house_plan.space_kinds[iz*HOUSE_SURFACE_WIDTH+ix]
}

house_ground_cell_count :: proc()->int {count:=0;for kind in house_plan.space_kinds do if kind==.Grounds do count+=1;return count}

load_room_texture :: proc(path:string)->Glb_Texture_Data {
	result:Glb_Texture_Data;img,err:=image.load(path,{.alpha_add_if_missing},context.allocator)
	if err!=nil||img==nil do return result
	result.width=img.width;result.height=img.height;result.pixels=make([dynamic]u8,len(img.pixels.buf));copy(result.pixels[:],img.pixels.buf[:]);image.destroy(img)
	return result
}

apply_texture :: proc(mesh:^Glb_Mesh,texture:Glb_Texture_Data) {
	if len(texture.pixels)==0 do return
	mesh.textures=make([dynamic]Glb_Texture_Data,0,1);append(&mesh.textures,texture);mesh.primitives[0].texture=0
}

picture_mesh_piece :: proc(m:^Glb_Mesh,left,bottom,right,top,u0,v0,u1,v1,z:f32) {
	base:=u32(len(m.vertices));append(&m.vertices,Vec3{left,bottom,z},Vec3{right,bottom,z},Vec3{right,top,z},Vec3{left,top,z})
	append(&m.texcoords,Vec2{u0,v1},Vec2{u1,v1},Vec2{u1,v0},Vec2{u0,v0});append(&m.indices,base,base+1,base+2,base,base+2,base+3)
}

procedural_picture_mesh :: proc(width,height:f32,art,frame:Glb_Texture_Data)->Glb_Mesh {
	m:Glb_Mesh;m.vertices=make([dynamic]Vec3,0,36);m.texcoords=make([dynamic]Vec2,0,36);m.indices=make([dynamic]u32,0,54);m.primitives=make([dynamic]Glb_Primitive_Range,0,2);m.textures=make([dynamic]Glb_Texture_Data,0,2)
	border:=f32(.14);left,right:= -width*.5,width*.5;bottom,top:=f32(0),height;outer_left,outer_right:=left-border,right+border;outer_bottom,outer_top:=bottom-border,top+border;third:=f32(1.0/3.0)
	picture_mesh_piece(&m,left,bottom,right,top,0,0,1,1,.006);append(&m.primitives,Glb_Primitive_Range{0,6,0,{1,1,1,1}})
	frame_start:=len(m.indices)
	picture_mesh_piece(&m,outer_left,top,left,outer_top,0,0,third,third,0)
	picture_mesh_piece(&m,left,top,right,outer_top,third,0,third*2,third,0)
	picture_mesh_piece(&m,right,top,outer_right,outer_top,third*2,0,1,third,0)
	picture_mesh_piece(&m,outer_left,bottom,left,top,0,third,third,third*2,0)
	picture_mesh_piece(&m,right,bottom,outer_right,top,third*2,third,1,third*2,0)
	picture_mesh_piece(&m,outer_left,outer_bottom,left,bottom,0,third*2,third,1,0)
	picture_mesh_piece(&m,left,outer_bottom,right,bottom,third,third*2,third*2,1,0)
	picture_mesh_piece(&m,right,outer_bottom,outer_right,bottom,third*2,third*2,1,1,0)
	append(&m.primitives,Glb_Primitive_Range{frame_start,len(m.indices)-frame_start,1,{1,1,1,1}});append(&m.textures,art,frame);m.min={outer_left,outer_bottom,0};m.max={outer_right,outer_top,.006};m.ready=true;return m
}

procedural_quad_mesh :: proc(width,height:f32,floor:bool)->Glb_Mesh {
	m:Glb_Mesh
	m.vertices=make([dynamic]Vec3,0,4);m.texcoords=make([dynamic]Vec2,4);m.indices=make([dynamic]u32,0,6);m.primitives=make([dynamic]Glb_Primitive_Range,0,1)
	if floor {
		append(&m.vertices,Vec3{-width/2,0,-height/2},Vec3{width/2,0,-height/2},Vec3{width/2,0,height/2},Vec3{-width/2,0,height/2})
		m.texcoords[0]={0,0};m.texcoords[1]={1,0};m.texcoords[2]={1,1};m.texcoords[3]={0,1}
		append(&m.indices,0,2,1,0,3,2);m.min={-width/2,0,-height/2};m.max={width/2,0.001,height/2}
	} else {
		append(&m.vertices,Vec3{-width/2,0,0},Vec3{width/2,0,0},Vec3{width/2,height,0},Vec3{-width/2,height,0})
		m.texcoords[0]={0,1};m.texcoords[1]={1,1};m.texcoords[2]={1,0};m.texcoords[3]={0,0}
		append(&m.indices,0,1,2,0,2,3);m.min={-width/2,0,0};m.max={width/2,height,0}
	}
	append(&m.primitives,Glb_Primitive_Range{0,6,-1,{1,1,1,1}});m.ready=true
	return m
}

procedural_glazing_mesh :: proc(width,height:f32)->Glb_Mesh {
	m:=procedural_quad_mesh(width,height,false)
	// The world pipeline does not cull faces, so one quad is visible from both
	// sides. A second opposite-winding copy would be coplanar transparent
	// geometry, causing unstable depth writes and patchy double blending.
	m.min.z=0;m.max.z=0;return m
}

wallpaper_face_mesh :: proc(a,b:Vec2,region_base,region_height:f32)->Glb_Mesh {
	dx,dz:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dz*dz)));mesh:=procedural_quad_mesh(length,max(region_height,.001),false);if length<=.001 do return mesh
	anchor:=math.abs(dx)>=math.abs(dz)?min(a.x,b.x):min(a.y,b.y);u0,u1:=anchor*HOUSE_WALL_COVERING_UV_SCALE,(anchor+length)*HOUSE_WALL_COVERING_UV_SCALE;v0,v1:=region_base*HOUSE_WALL_COVERING_UV_SCALE,(region_base+region_height)*HOUSE_WALL_COVERING_UV_SCALE;mesh.texcoords[0]={u0,v0};mesh.texcoords[1]={u1,v0};mesh.texcoords[2]={u1,v1};mesh.texcoords[3]={u0,v1};return mesh
}

// Stable bands anchor the material at the final cut height, transition
// midpoint, and authored wall top. Only the single band crossed by the moving
// section plane is rescaled; every complete band retains its physical UV size.
house_wall_finish_bands :: proc()->[4]f32 {height:=house_authored_wall_height();cut:=min(HOUSE_CUTAWAY_HEIGHT,height);return {0,cut,(cut+height)*.5,height}}

append_wallpaper_band_draws :: proc(out:^[dynamic]Personal_Surface_Draw,a,b:Vec2,x,z,yaw:f32,texture:Glb_Texture_Data,base:f32,wall_index:int) {
	append_wallpaper_region_band_draws(out,a,b,x,z,yaw,texture,base,0,house_authored_wall_height(),wall_index)
}

append_wallpaper_region_band_draws :: proc(out:^[dynamic]Personal_Surface_Draw,a,b:Vec2,x,z,yaw:f32,texture:Glb_Texture_Data,base,requested_base,requested_height:f32,wall_index:int=-1) {
	if len(texture.pixels)==0||requested_height<=.001 do return
	requested_top:=requested_base+requested_height
	bands:=house_wall_finish_bands();for band in 0..<len(bands)-1 {region_base:=max(requested_base,bands[band]);region_top:=min(requested_top,bands[band+1]);region_height:=region_top-region_base;if region_height<=.001 do continue;mesh:=wallpaper_face_mesh(a,b,region_base,region_height);apply_texture(&mesh,texture);append(out,Personal_Surface_Draw{mesh=mesh,x=x,z=z,yaw=yaw,base=base,region_base=region_base,region_height=region_height,wall_index=wall_index})}
}

// A batch owns only tiles with the same surface and space classification. That
// preserves the visual distinction between interior flooring and open-air
// grounds while collapsing the previous per-tile renderer submission loop.
procedural_floor_batch_mesh :: proc(surface:Room_Surface,space:Plan_Space_Kind)->Glb_Mesh {
	m:Glb_Mesh;m.vertices=make([dynamic]Vec3,0,96);m.texcoords=make([dynamic]Vec2,0,96);m.indices=make([dynamic]u32,0,144);m.primitives=make([dynamic]Glb_Primitive_Range,0,1)
	for y in 0..<HOUSE_SURFACE_HEIGHT {for x in 0..<HOUSE_SURFACE_WIDTH {
		wx,wz:=f32(x),f32(y);if house_surface_at(wx+.5,wz+.5)!=surface||house_space_kind_at(wx+.5,wz+.5)!=space do continue
		base:=u32(len(m.vertices));append(&m.vertices,Vec3{wx,0,wz},Vec3{wx+1,0,wz},Vec3{wx+1,0,wz+1},Vec3{wx,0,wz+1});append(&m.texcoords,Vec2{0,0},Vec2{1,0},Vec2{1,1},Vec2{0,1});append(&m.indices,base,base+2,base+1,base,base+3,base+2)
	}}
	if len(m.vertices)==0 do return m
	m.min={1e30,0,1e30};m.max={-1e30,1,-1e30};for vertex in m.vertices {m.min.x=min(m.min.x,vertex.x);m.min.z=min(m.min.z,vertex.z);m.max.x=max(m.max.x,vertex.x);m.max.z=max(m.max.z,vertex.z)}
	append(&m.primitives,Glb_Primitive_Range{0,len(m.indices),0,{1,1,1,1}});if len(house_floor_materials[surface].textures)>0 do apply_texture(&m,house_floor_materials[surface].textures[0]);m.ready=true;return m
}

append_wall_face_region :: proc(mesh:^Glb_Mesh,a,b:Vec2,positive:bool,base_y,height:f32) {
	dx,dz:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dz*dz)));if length<.001 do return
	nx,nz:= -dz/length,dx/length;sign:f32=positive?1:-1;offset:=f32(HOUSE_WALL_THICKNESS*.5+.004)*sign;pa,pb:=Vec2{a.x+nx*offset,a.y+nz*offset},Vec2{b.x+nx*offset,b.y+nz*offset};base:=u32(len(mesh.vertices))
	top_y:=base_y+height;u0,u1:=a.x,b.x;if math.abs(dz)>math.abs(dx) {u0,u1=a.y,b.y};append(&mesh.vertices,Vec3{pa.x,base_y,pa.y},Vec3{pb.x,base_y,pb.y},Vec3{pb.x,top_y,pb.y},Vec3{pa.x,top_y,pa.y});append(&mesh.texcoords,Vec2{u0,base_y},Vec2{u1,base_y},Vec2{u1,top_y},Vec2{u0,top_y})
	if positive {append(&mesh.indices,base,base+1,base+2,base,base+2,base+3)} else {append(&mesh.indices,base+1,base,base+3,base+1,base+3,base+2)}
}

append_wall_face_batch :: proc(mesh:^Glb_Mesh,a,b:Vec2,positive:bool,height:f32) {
	append_wall_face_region(mesh,a,b,positive,0,height)
}

house_wall_face_classification :: proc(a,b:Vec2,positive:bool)->(Room_Surface,bool) {
	dx,dz:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dz*dz)));if length<.001 do return .Dining,false
	mx,mz:=(a.x+b.x)*.5,(a.y+b.y)*.5;nx,nz:= -dz/length,dx/length;sign:f32=positive?1:-1;sx,sz:=mx+nx*.24*sign,mz+nz*.24*sign
	interior:=sx>=0&&sx<f32(HOUSE_SURFACE_WIDTH)&&sz>=0&&sz<f32(HOUSE_SURFACE_HEIGHT)&&house_space_kind_at(sx,sz)==.Interior;surface:=house_surface_at(sx,sz)
	for paint in house_plan.wall_face_paints {if paint.positive!=positive do continue;if point_segment_distance_sq(mx,mz,paint.a,paint.b)<.08*.08 {surface=paint.surface;break}}
	return surface,interior
}

append_window_wallpaper_regions :: proc(mesh:^Glb_Mesh,opening:Plan_Opening,positive:bool,wall_height:f32) {
	if opening.kind!=.Window||wall_height<=0 do return
	sill:=clamp(opening.sill_height>0?opening.sill_height:f32(.72),0,wall_height);glazing_height:=opening.height>0?opening.height:f32(1.4);head:=clamp(sill+glazing_height,0,wall_height)
	if sill>.001 do append_wall_face_region(mesh,opening.a,opening.b,positive,0,sill)
	if head<wall_height-.001 do append_wall_face_region(mesh,opening.a,opening.b,positive,head,wall_height-head)
}

house_exterior_opening_finish_span :: proc(opening:Plan_Opening)->Plan_Opening {
	result:=opening;dx,dz:=opening.b.x-opening.a.x,opening.b.y-opening.a.y;length:=f32(math.sqrt(f64(dx*dx+dz*dz)));if length<=.001 do return result
	tx,tz:=dx/length,dz/length;result.a={opening.a.x-tx*HOUSE_EXTERIOR_OPENING_FINISH_OVERLAP,opening.a.y-tz*HOUSE_EXTERIOR_OPENING_FINISH_OVERLAP};result.b={opening.b.x+tx*HOUSE_EXTERIOR_OPENING_FINISH_OVERLAP,opening.b.y+tz*HOUSE_EXTERIOR_OPENING_FINISH_OVERLAP};return result
}

append_window_wallpaper_draws :: proc(out:^[dynamic]Personal_Surface_Draw,opening:Plan_Opening,positive:bool,texture:Glb_Texture_Data,base:f32,face_lift:f32=.004) {
	dx,dz:=opening.b.x-opening.a.x,opening.b.y-opening.a.y;length:=f32(math.sqrt(f64(dx*dx+dz*dz)));if length<=.01||len(texture.pixels)==0 do return
	mx,mz:=(opening.a.x+opening.b.x)*.5,(opening.a.y+opening.b.y)*.5;nx,nz:= -dz/length,dx/length;sign:f32=positive?1:-1;offset:=house_opening_face_offset(opening,face_lift);yaw:=f32(math.atan2(f64(dz),f64(dx)))+(positive?0:f32(math.PI));sill:=opening.sill_height>0?opening.sill_height:f32(.72);head:=sill+(opening.height>0?opening.height:f32(1.4));x,z:=mx+nx*offset*sign,mz+nz*offset*sign
	if sill>.001 do append_wallpaper_region_band_draws(out,opening.a,opening.b,x,z,yaw,texture,base,0,sill)
	wall_height:=house_authored_wall_height();if head<wall_height-.001 do append_wallpaper_region_band_draws(out,opening.a,opening.b,x,z,yaw,texture,base,head,wall_height-head)
}

append_door_wallpaper_header_draw :: proc(out:^[dynamic]Personal_Surface_Draw,opening:Plan_Opening,positive:bool,texture:Glb_Texture_Data,base:f32,face_lift:f32=.004) {
	if opening.kind!=.Door||len(texture.pixels)==0 do return
	dx,dz:=opening.b.x-opening.a.x,opening.b.y-opening.a.y;length:=f32(math.sqrt(f64(dx*dx+dz*dz)));if length<=.01 do return
	wall_height:=house_authored_wall_height();head:=house_door_render_height(opening);if head>=wall_height-.001 do return
	mx,mz:=(opening.a.x+opening.b.x)*.5,(opening.a.y+opening.b.y)*.5;nx,nz:= -dz/length,dx/length;sign:f32=positive?1:-1;offset:=house_opening_face_offset(opening,face_lift)
	height:=wall_height-head;yaw:=f32(math.atan2(f64(dz),f64(dx)))+(positive?0:f32(math.PI))
	append_wallpaper_region_band_draws(out,opening.a,opening.b,mx+nx*offset*sign,mz+nz*offset*sign,yaw,texture,base,head,height)
}

finalize_wall_face_batch :: proc(mesh:^Glb_Mesh,surface:Room_Surface,height:f32) {
	if len(mesh.vertices)==0 do return
	mesh.min={1e30,0,1e30};mesh.max={-1e30,height,-1e30};for vertex in mesh.vertices {mesh.min.x=min(mesh.min.x,vertex.x);mesh.min.z=min(mesh.min.z,vertex.z);mesh.max.x=max(mesh.max.x,vertex.x);mesh.max.z=max(mesh.max.z,vertex.z)}
	append(&mesh.primitives,Glb_Primitive_Range{0,len(mesh.indices),0,{1,1,1,1}});if len(house_wall_materials[surface].pixels)>0 do apply_texture(mesh,house_wall_materials[surface]);mesh.ready=true
}

append_wall_cap_batch :: proc(mesh:^Glb_Mesh,a,b:Vec2,height,thickness:f32) {
	dx,dz:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dz*dz)));if length<.001 do return
	nx,nz:= -dz/length*thickness*.5,dx/length*thickness*.5;base:=u32(len(mesh.vertices))
	append(&mesh.vertices,Vec3{a.x+nx,height,a.y+nz},Vec3{b.x+nx,height,b.y+nz},Vec3{b.x-nx,height,b.y-nz},Vec3{a.x-nx,height,a.y-nz})
	append(&mesh.texcoords,Vec2{0,0},Vec2{length,0},Vec2{length,1},Vec2{0,1})
	append(&mesh.indices,base,base+1,base+2,base,base+2,base+3,base+2,base+1,base,base+3,base+2,base)
}

finalize_wall_cap_batch :: proc(mesh:^Glb_Mesh,height:f32) {
	if len(mesh.vertices)==0 do return
	mesh.min={1e30,0,1e30};mesh.max={-1e30,height,-1e30};for vertex in mesh.vertices {mesh.min.x=min(mesh.min.x,vertex.x);mesh.min.z=min(mesh.min.z,vertex.z);mesh.max.x=max(mesh.max.x,vertex.x);mesh.max.z=max(mesh.max.z,vertex.z)}
	append(&mesh.primitives,Glb_Primitive_Range{0,len(mesh.indices),-1,{1,1,1,1}});mesh.ready=true
}

// A wall spline is a collision solid, not a paper-thin visual divider. This
// prism uses the same authored thickness as world_wall/navmesh clearance.
procedural_wall_mesh :: proc(length,height,thickness:f32)->Glb_Mesh {
	m:Glb_Mesh;m.vertices=make([dynamic]Vec3,0,8);m.texcoords=make([dynamic]Vec2,8);m.indices=make([dynamic]u32,0,36);m.primitives=make([dynamic]Glb_Primitive_Range,0,1)
	hx,hz:=length*.5,thickness*.5;append(&m.vertices,Vec3{-hx,0,-hz},Vec3{hx,0,-hz},Vec3{hx,height,-hz},Vec3{-hx,height,-hz},Vec3{-hx,0,hz},Vec3{hx,0,hz},Vec3{hx,height,hz},Vec3{-hx,height,hz});append(&m.texcoords,Vec2{0,0},Vec2{1,0},Vec2{1,1},Vec2{0,1},Vec2{0,0},Vec2{1,0},Vec2{1,1},Vec2{0,1})
	append(&m.indices,0,2,1,0,3,2,5,7,4,5,6,7,4,3,0,4,7,3,1,6,5,1,2,6,3,6,2,3,7,6,4,1,5,4,0,1);m.min={-hx,0,-hz};m.max={hx,height,hz};append(&m.primitives,Glb_Primitive_Range{0,36,-1,{1,1,1,1}});m.ready=true;return m
}

// Aperture infill overlaps the surrounding wall at both ends. Its endpoint
// faces are internal construction surfaces; drawing them lets their unpainted
// returns peek out beside window trim when the overlap closes the union cut.
procedural_wall_infill_mesh :: proc(length,height,thickness:f32)->Glb_Mesh {
	m:=procedural_wall_mesh(length,height,thickness);if !m.ready do return m
	clear(&m.indices);append(&m.indices,0,2,1,0,3,2,5,7,4,5,6,7,3,6,2,3,7,6,4,1,5,4,0,1);m.primitives[0].count=len(m.indices);return m
}

procedural_wall_band_mesh :: proc(a,b:Vec2,region_base,region_height,thickness:f32)->Glb_Mesh {
	dx,dz:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dz*dz)));mesh:=procedural_wall_mesh(length,max(region_height,.001),thickness);if length<=.001 do return mesh
	// Internal band boundaries are not architectural surfaces. Retain front,
	// back, and endpoint returns; the renderer's dedicated cap owns the only
	// horizontal face at the current section height.
	resize(&mesh.indices,24);mesh.primitives[0].count=24
	anchor:=math.abs(dx)>=math.abs(dz)?min(a.x,b.x):min(a.y,b.y);u0,u1:=anchor*HOUSE_WALL_COVERING_UV_SCALE,(anchor+length)*HOUSE_WALL_COVERING_UV_SCALE;v0,v1:=region_base*HOUSE_WALL_COVERING_UV_SCALE,(region_base+region_height)*HOUSE_WALL_COVERING_UV_SCALE
	mesh.texcoords[0]={u0,v0};mesh.texcoords[1]={u1,v0};mesh.texcoords[2]={u1,v1};mesh.texcoords[3]={u0,v1};mesh.texcoords[4]={u0,v0};mesh.texcoords[5]={u1,v0};mesh.texcoords[6]={u1,v1};mesh.texcoords[7]={u0,v1};return mesh
}

// The exterior half of a window sill sheds water away from the wall. Local +Z
// is outward; callers rotate the mesh so its taller edge always meets the jamb.
procedural_sloped_sill_mesh :: proc(length,depth,inner_height,outer_height:f32)->Glb_Mesh {
	m:Glb_Mesh;m.vertices=make([dynamic]Vec3,0,8);m.texcoords=make([dynamic]Vec2,8);m.indices=make([dynamic]u32,0,36);m.primitives=make([dynamic]Glb_Primitive_Range,0,1)
	hx,hz:=length*.5,depth*.5;append(&m.vertices,Vec3{-hx,0,-hz},Vec3{hx,0,-hz},Vec3{hx,inner_height,-hz},Vec3{-hx,inner_height,-hz},Vec3{-hx,0,hz},Vec3{hx,0,hz},Vec3{hx,outer_height,hz},Vec3{-hx,outer_height,hz});append(&m.texcoords,Vec2{0,0},Vec2{1,0},Vec2{1,1},Vec2{0,1},Vec2{0,0},Vec2{1,0},Vec2{1,1},Vec2{0,1})
	append(&m.indices,0,2,1,0,3,2,5,7,4,5,6,7,4,3,0,4,7,3,1,6,5,1,2,6,3,6,2,3,7,6,4,1,5,4,0,1);m.min={-hx,0,-hz};m.max={hx,max(inner_height,outer_height),hz};append(&m.primitives,Glb_Primitive_Range{0,36,-1,{1,1,1,1}});m.ready=true;return m
}

procedural_wall_run_mesh :: proc(points:[]Vec2,height,thickness:f32)->Glb_Mesh {
	m:Glb_Mesh;if len(points)<2 do return m
	closed:=len(points)>2&&point_segment_distance_sq(points[0].x,points[0].y,points[len(points)-1],points[len(points)-1])<.0001
	count:=closed?len(points)-1:len(points);if count<2 do return m
	m.vertices=make([dynamic]Vec3,0,count*4);m.texcoords=make([dynamic]Vec2,0,count*4);m.indices=make([dynamic]u32,0,(count-1+(closed?1:0))*18+12);m.primitives=make([dynamic]Glb_Primitive_Range,0,1)
	half:=thickness*.5
	for i in 0..<count {
		prev:=i-1;next:=i+1;if closed {if prev<0 do prev=count-1;if next>=count do next=0}else{if prev<0 do prev=0;if next>=count do next=count-1}
		p:=points[i];previous:=points[prev];following:=points[next];pdx,pdz:=p.x-previous.x,p.y-previous.y;ndx,ndz:=following.x-p.x,following.y-p.y
		if i==0&&!closed {pdx,pdz=ndx,ndz};if i==count-1&&!closed {ndx,ndz=pdx,pdz}
		plen:=f32(math.sqrt(f64(pdx*pdx+pdz*pdz)));nlen:=f32(math.sqrt(f64(ndx*ndx+ndz*ndz)));if plen<.001||nlen<.001 do continue;pdx,pdz=pdx/plen,pdz/plen;ndx,ndz=ndx/nlen,ndz/nlen
		pnx,pnz:= -pdz,pdx;nnx,nnz:= -ndz,ndx;mx,mz:=pnx+nnx,pnz+nnz;mlen:=f32(math.sqrt(f64(mx*mx+mz*mz)));if mlen<.001 {mx,mz=nnx,nnz;mlen=1};mx,mz=mx/mlen,mz/mlen;denom:=math.abs(mx*nnx+mz*nnz);offset:=half/max(denom,.25)
		left,right:=Vec2{p.x+mx*offset,p.y+mz*offset},Vec2{p.x-mx*offset,p.y-mz*offset}
		append(&m.vertices,Vec3{left.x,0,left.y},Vec3{left.x,height,left.y},Vec3{right.x,0,right.y},Vec3{right.x,height,right.y})
		append(&m.texcoords,Vec2{0,0},Vec2{0,1},Vec2{1,0},Vec2{1,1})
	}
	segments:=closed?count:count-1
	// This mesh is the independently generated wall cap. Structural sides come
	// from the regularized union, while these mitered strips leave room interiors
	// open instead of filling an outer contour across its holes.
	for i in 0..<segments {j:=(i+1)%count;lt,rt:=u32(i*4+1),u32(i*4+3);nlt,nrt:=u32(j*4+1),u32(j*4+3);append(&m.indices,lt,nlt,nrt,lt,nrt,rt,nrt,nlt,lt,rt,nrt,lt)}
	m.min={1e30,1e30,1e30};m.max={-1e30,-1e30,-1e30};for vertex in m.vertices {m.min.x=min(m.min.x,vertex.x);m.min.y=min(m.min.y,vertex.y);m.min.z=min(m.min.z,vertex.z);m.max.x=max(m.max.x,vertex.x);m.max.y=max(m.max.y,vertex.y);m.max.z=max(m.max.z,vertex.z)}
	append(&m.primitives,Glb_Primitive_Range{0,len(m.indices),-1,{1,1,1,1}});m.ready=true;return m
}

wall_solid_add_quad :: proc(mesh:^Glb_Mesh,a,b:Vec2,bottom,top:f32) {
	base:=u32(len(mesh.vertices));append(&mesh.vertices,Vec3{a.x,bottom,a.y},Vec3{b.x,bottom,b.y},Vec3{b.x,top,b.y},Vec3{a.x,top,a.y});append(&mesh.texcoords,Vec2{0,0},Vec2{1,0},Vec2{1,1},Vec2{0,1})
	// Keep both winding directions: contour direction distinguishes exterior and
	// courtyard walls, while the mesh remains readable with either face culling.
	append(&mesh.indices,base,base+1,base+2,base,base+2,base+3,base+2,base+1,base,base+3,base+2,base)
}

wall_cap_cross :: proc(a,b,c:Vec2)->f32 {return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)}

wall_cap_contains :: proc(p,a,b,c:Vec2,winding:f32)->bool {
	// Points on an ear boundary count as contained so collinear union vertices
	// cannot leave a hairline wedge at a wall corner.
	epsilon:f32=-.00001
	return wall_cap_cross(a,b,p)*winding>=epsilon&&wall_cap_cross(b,c,p)*winding>=epsilon&&wall_cap_cross(c,a,p)*winding>=epsilon
}

// Union contours are frequently concave at T junctions and inside corners.
// A centroid fan only works for star-shaped contours and was the source of the
// small missing wedges visible in cutaway wall caps. Ear clipping covers every
// simple contour without changing the authoritative fixed-point boundary.
wall_solid_add_cap :: proc(mesh:^Glb_Mesh,points:[]Chicago_Wall_Point,height:f32) {
	count:=len(points);if count<3 do return
	polygon_area:f32=0;for i in 0..<count {j:=(i+1)%count;polygon_area+=f32(points[i].x*points[j].y-points[j].x*points[i].y)}
	winding:f32=polygon_area>=0?1:-1
	base:=u32(len(mesh.vertices));for point in points {append(&mesh.vertices,Vec3{f32(point.x),height,f32(point.y)});append(&mesh.texcoords,Vec2{0,0})}
	remaining:=make([dynamic]int,0,count);defer delete(remaining);for i in 0..<count do append(&remaining,i)
	guard:=0
	for len(remaining)>2&&guard<count*count {
		clipped:=false
		for cursor in 0..<len(remaining) {
			previous:=remaining[(cursor+len(remaining)-1)%len(remaining)];current:=remaining[cursor];next:=remaining[(cursor+1)%len(remaining)]
			a:=Vec2{f32(points[previous].x),f32(points[previous].y)};b:=Vec2{f32(points[current].x),f32(points[current].y)};c:=Vec2{f32(points[next].x),f32(points[next].y)}
			if wall_cap_cross(a,b,c)*winding<=.000001 do continue
			occupied:=false;for candidate in remaining {if candidate==previous||candidate==current||candidate==next do continue;p:=Vec2{f32(points[candidate].x),f32(points[candidate].y)};if wall_cap_contains(p,a,b,c,winding) {occupied=true;break}}
			if occupied do continue
			// Emit both windings; cap contours may arrive clockwise or counterclockwise
			// and the cutaway must remain visible under either culling configuration.
			append(&mesh.indices,base+u32(previous),base+u32(current),base+u32(next),base+u32(next),base+u32(current),base+u32(previous))
			ordered_remove(&remaining,cursor);clipped=true;break
		}
		if !clipped do break
		guard+=1
	}
}

// The bridge returns normalized, fixed-point Clipper contours. We create a
// closed extruded boundary from them here; logical sections continue to own
// paint/UV decisions rather than becoming renderer-only geometry.
build_house_wall_solid :: proc(height:f32)->Glb_Mesh {
	segments:=make([dynamic]Chicago_Wall_Segment,0,64);doors:=make([dynamic]Chicago_Wall_Door,0,16)
	for spline in house_plan.wall_splines {for i in 0..<len(spline.points)-1 {a,b:=spline.points[i],spline.points[i+1];append(&segments,Chicago_Wall_Segment{f64(a.x),f64(a.y),f64(b.x),f64(b.y),f64(house_wall_width(spline.width))})}}
	// Both doors and windows are real plan-view apertures. Window sill/header
	// masonry is restored as separate vertical infill after the union.
	for opening in house_plan.openings {a,b:=opening.a,opening.b;append(&doors,Chicago_Wall_Door{f64(a.x),f64(a.y),f64(b.x),f64(b.y),f64(house_wall_width(opening.wall_width)+.02)})}
	geometry:Chicago_Wall_Geometry;if len(segments)==0||chicago_wall_union(raw_data(segments),u32(len(segments)),len(doors)>0?raw_data(doors):nil,u32(len(doors)),&geometry)==0 do return {}
	defer chicago_wall_geometry_free(&geometry);mesh:Glb_Mesh;mesh.vertices=make([dynamic]Vec3,0,int(geometry.point_count)*6);mesh.texcoords=make([dynamic]Vec2,0,int(geometry.point_count)*6);mesh.indices=make([dynamic]u32,0,int(geometry.point_count)*18);points:=(cast([^]Chicago_Wall_Point)geometry.points)[:int(geometry.point_count)];contours:=(cast([^]Chicago_Wall_Contour)geometry.contours)[:int(geometry.contour_count)]
	for contour in contours {if contour.count<3 do continue;start:=int(contour.first);count:=int(contour.count)
		for i in 0..<count {p,q:=points[start+i],points[start+(i+1)%count];wall_solid_add_quad(&mesh,{f32(p.x),f32(p.y)},{f32(q.x),f32(q.y)},0,height)}
	}
	if len(mesh.vertices)==0 do return mesh;mesh.min={1e30,0,1e30};mesh.max={-1e30,height,-1e30};for v in mesh.vertices {mesh.min.x=min(mesh.min.x,v.x);mesh.min.z=min(mesh.min.z,v.z);mesh.max.x=max(mesh.max.x,v.x);mesh.max.z=max(mesh.max.z,v.z)};append(&mesh.primitives,Glb_Primitive_Range{0,len(mesh.indices),-1,{1,1,1,1}});mesh.ready=true;return mesh
}

build_house_wall_cap_union :: proc(extra:f32)->Glb_Mesh {
	segments:=make([dynamic]Chicago_Wall_Segment,0,64);doors:=make([dynamic]Chicago_Wall_Door,0,16)
	for spline in house_plan.wall_splines {for i in 0..<len(spline.points)-1 {a,b:=spline.points[i],spline.points[i+1];append(&segments,Chicago_Wall_Segment{f64(a.x),f64(a.y),f64(b.x),f64(b.y),f64(house_wall_width(spline.width)+extra)})}}
	for opening in house_plan.openings {append(&doors,Chicago_Wall_Door{f64(opening.a.x),f64(opening.a.y),f64(opening.b.x),f64(opening.b.y),f64(house_wall_width(opening.wall_width)+extra+.02)})}
	geometry:Chicago_Wall_Geometry;if len(segments)==0||chicago_wall_union(raw_data(segments),u32(len(segments)),len(doors)>0?raw_data(doors):nil,u32(len(doors)),&geometry)==0 do return {}
	defer chicago_wall_geometry_free(&geometry);mesh:=Glb_Mesh{vertices=make([dynamic]Vec3,0,int(geometry.point_count)),texcoords=make([dynamic]Vec2,0,int(geometry.point_count)),indices=make([dynamic]u32,0,int(geometry.point_count)*6),primitives=make([dynamic]Glb_Primitive_Range,0,1)};points:=(cast([^]Chicago_Wall_Point)geometry.points)[:int(geometry.point_count)];contours:=(cast([^]Chicago_Wall_Contour)geometry.contours)[:int(geometry.contour_count)]
	for contour in contours {if contour.count<3 do continue;start:=int(contour.first);wall_solid_add_cap(&mesh,points[start:start+int(contour.count)],0)}
	if len(mesh.vertices)==0 do return mesh;mesh.min={1e30,0,1e30};mesh.max={-1e30,.001,-1e30};for vertex in mesh.vertices {mesh.min.x=min(mesh.min.x,vertex.x);mesh.min.z=min(mesh.min.z,vertex.z);mesh.max.x=max(mesh.max.x,vertex.x);mesh.max.z=max(mesh.max.z,vertex.z)};append(&mesh.primitives,Glb_Primitive_Range{0,len(mesh.indices),-1,{1,1,1,1}});mesh.ready=true;return mesh
}

build_house_floorplan :: proc(){
	authored_height:=house_authored_wall_height()
	house_floor_mesh=procedural_quad_mesh(1,1,true)
	house_art_mesh=procedural_quad_mesh(.82,1.16,false)
	house_art_frame_mesh=procedural_quad_mesh(1.02,1.36,false)
	house_art_mesh.alpha_modes=make([dynamic]int,0,1);append(&house_art_mesh.alpha_modes,2)
	house_art_frame_mesh.alpha_modes=make([dynamic]int,0,1);append(&house_art_frame_mesh.alpha_modes,2)
	// Glass is a single sheet recessed behind the face-mounted sash. A transparent
	// closed box self-blends its front/back faces and produces diagonal artifacts.
	house_window_mesh=procedural_glazing_mesh(2.0,1.4)
	house_window_mesh.alpha_modes=make([dynamic]int,0,1);append(&house_window_mesh.alpha_modes,2)
	house_window_sill_mesh=procedural_wall_infill_mesh(2.18,.72,HOUSE_WALL_THICKNESS)
	house_window_header_mesh=procedural_wall_infill_mesh(2.18,.38,HOUSE_WALL_THICKNESS)
	house_window_sill_interior_mesh=procedural_wall_infill_mesh(2.18,.72,HOUSE_INTERIOR_WALL_THICKNESS)
	house_window_header_interior_mesh=procedural_wall_infill_mesh(2.18,.38,HOUSE_INTERIOR_WALL_THICKNESS)
	house_window_header_cap_mesh=procedural_quad_mesh(1,HOUSE_WALL_THICKNESS,true)
	// Window/door apertures are cut through the structural union and their
	// below/above masonry is restored separately. It must carry the same exterior
	// finish as the surrounding wall; room wallpaper overlays its interior face.
	apply_texture(&house_window_sill_mesh,exterior_wall_texture)
	apply_texture(&house_window_header_mesh,exterior_wall_texture)
	apply_texture(&house_window_sill_interior_mesh,exterior_wall_texture)
	apply_texture(&house_window_header_interior_mesh,exterior_wall_texture)
	house_window_frame_h_mesh=procedural_wall_mesh(2.12,HOUSE_WINDOW_FRAME_RAIL_HEIGHT,.045)
	house_window_frame_v_mesh=procedural_wall_mesh(.055,1.50,.045)
	house_window_muntin_h_mesh=procedural_wall_mesh(2.0,.03,HOUSE_WINDOW_MUNTIN_DEPTH)
	house_window_muntin_v_mesh=procedural_wall_mesh(.03,1.4,HOUSE_WINDOW_MUNTIN_DEPTH)
	house_window_bead_h_mesh=procedural_wall_mesh(2.0,.016,HOUSE_WINDOW_GLAZING_BEAD_DEPTH)
	house_window_bead_v_mesh=procedural_wall_mesh(.016,1.4,HOUSE_WINDOW_GLAZING_BEAD_DEPTH)
	house_window_hardware_h_mesh=procedural_wall_mesh(.20,.025,HOUSE_WINDOW_HARDWARE_DEPTH)
	house_window_hardware_v_mesh=procedural_wall_mesh(.025,.16,HOUSE_WINDOW_HARDWARE_DEPTH)
	house_window_sill_cap_mesh=procedural_wall_mesh(2.20,.07,HOUSE_WALL_THICKNESS+.16)
	house_window_exterior_sill_mesh=procedural_sloped_sill_mesh(2.20,.14,.07,.025)
	house_window_head_return_mesh=procedural_wall_mesh(2.16,.08,HOUSE_WALL_THICKNESS+.08)
	house_window_jamb_return_mesh=procedural_wall_mesh(.08,1.50,HOUSE_WALL_THICKNESS+.08)
	// Closed louvers overlap visually into one sightline-blocking surface; when
	// pitched open their thin depth leaves a clear view between rails.
	house_shutter_slat_mesh=procedural_wall_mesh(2.08,.124,.025)
	// A thin structural face closes the vertical step where independently
	// animated wall sections meet. Its authored width spans the wall thickness;
	// render-time height is the difference between the two section tops.
	house_wall_junction_reveal_mesh=procedural_wall_mesh(HOUSE_WALL_THICKNESS+.012,authored_height,.018)
	house_wall_cap_edge_mesh=procedural_quad_mesh(1,HOUSE_WALL_THICKNESS+.036,true)
	house_wall_cap_edge_interior_mesh=procedural_quad_mesh(1,HOUSE_INTERIOR_WALL_THICKNESS+.036,true)
	// Door openings are structural cut-outs, so they also need a separate leaf.
	// The leaf is rendered open and never participates in navigation collision.
	for material in Door_Material {house_door_meshes[material]=procedural_wall_mesh(1.4,2.1,.07);apply_texture(&house_door_meshes[material],load_room_texture(DOOR_TEXTURE_PATHS[material]))}
	// Gameplay clues are not editor dressing. These pieces give the crank a
	// permanent, readable silhouette at its interaction point.
	shutter_crank_housing_mesh=procedural_wall_mesh(.34,.54,.16)
	// Native-size spoke points along local Z; the centered world transform
	// rotates it continuously in the wall plane without stair-stepped links.
	shutter_crank_arm_mesh=procedural_wall_mesh(.065,.065,.27)
	shutter_crank_link_mesh=procedural_wall_mesh(.07,.07,.07)
	shutter_crank_grip_mesh=procedural_wall_mesh(.075,.24,.075)
	shutter_silk_mesh=procedural_wall_mesh(.028,.18,.018)
	house_walls=make([dynamic]Floorplan_Wall,0,32)
	for space in Plan_Space_Kind {for surface in Room_Surface do house_floor_batches[space][surface]=procedural_floor_batch_mesh(surface,space)}
	house_wall_runs=make([dynamic]Glb_Mesh,0,len(house_plan.wall_splines));house_wall_runs_full=make([dynamic]Glb_Mesh,0,len(house_plan.wall_splines))
	for spline in house_plan.wall_splines {width:=house_wall_width(spline.width);append(&house_wall_runs,procedural_wall_run_mesh(spline.points,min(HOUSE_CUTAWAY_HEIGHT,authored_height),width));append(&house_wall_runs_full,procedural_wall_run_mesh(spline.points,authored_height,width));for i in 0..<len(spline.points)-1 do append_house_wall_span(spline.points[i],spline.points[i+1],width)}
	house_wall_cap_batch_full=Glb_Mesh{vertices=make([dynamic]Vec3,0,len(house_walls)*4),texcoords=make([dynamic]Vec2,0,len(house_walls)*4),indices=make([dynamic]u32,0,len(house_walls)*12),primitives=make([dynamic]Glb_Primitive_Range,0,1)}
	// Keep cap vertices in local Y so the same continuous surface can be placed
	// at the authored or uniformly cut wall height by the renderer.
	for wall in house_walls do append_wall_cap_batch(&house_wall_cap_batch_full,wall.a,wall.b,0,wall.width)
	finalize_wall_cap_batch(&house_wall_cap_batch_full,.001)
	for surface in Room_Surface {
		house_wall_face_batches[surface]=Glb_Mesh{vertices=make([dynamic]Vec3,0,64),texcoords=make([dynamic]Vec2,0,64),indices=make([dynamic]u32,0,96),primitives=make([dynamic]Glb_Primitive_Range,0,1)}
		house_wall_face_batches_full[surface]=Glb_Mesh{vertices=make([dynamic]Vec3,0,64),texcoords=make([dynamic]Vec2,0,64),indices=make([dynamic]u32,0,96),primitives=make([dynamic]Glb_Primitive_Range,0,1)}
	}
	for wall in house_walls {
		if wall.positive_interior {append_wall_face_batch(&house_wall_face_batches[wall.positive_surface],wall.a,wall.b,true,min(HOUSE_CUTAWAY_HEIGHT,authored_height));append_wall_face_batch(&house_wall_face_batches_full[wall.positive_surface],wall.a,wall.b,true,authored_height)}
		if wall.negative_interior {append_wall_face_batch(&house_wall_face_batches[wall.negative_surface],wall.a,wall.b,false,min(HOUSE_CUTAWAY_HEIGHT,authored_height));append_wall_face_batch(&house_wall_face_batches_full[wall.negative_surface],wall.a,wall.b,false,authored_height)}
	}
	// Window apertures remove a complete structural strip. Restore the room's
	// covering only on the masonry below the sill and above the head; the glazing
	// and frame remain unobstructed.
	window_sides:=[2]bool{true,false};for opening in house_plan.openings {if opening.kind!=.Window do continue;for positive in window_sides {surface,interior:=house_wall_face_classification(opening.a,opening.b,positive);if !interior do continue;append_window_wallpaper_regions(&house_wall_face_batches[surface],opening,positive,min(HOUSE_CUTAWAY_HEIGHT,authored_height));append_window_wallpaper_regions(&house_wall_face_batches_full[surface],opening,positive,authored_height)}}
	for surface in Room_Surface {finalize_wall_face_batch(&house_wall_face_batches[surface],surface,min(HOUSE_CUTAWAY_HEIGHT,authored_height));finalize_wall_face_batch(&house_wall_face_batches_full[surface],surface,authored_height)}
	house_wall_solid=build_house_wall_solid(authored_height);apply_texture(&house_wall_solid,exterior_wall_texture)
	house_wall_solid_cutaway=build_house_wall_solid(min(HOUSE_CUTAWAY_HEIGHT,authored_height));apply_texture(&house_wall_solid_cutaway,exterior_wall_texture)
	house_wall_cap_union=build_house_wall_cap_union(0)
	house_wall_cap_union_edge=build_house_wall_cap_union(HOUSE_WALL_CAP_EDGE_OVERHANG)
}

append_house_wall_piece_raw :: proc(a,b:Vec2,width:f32) {
	dx,dz:=b.x-a.x,b.y-a.y;length:=math.sqrt(dx*dx+dz*dz);if length<=.01 do return
	mx,mz:=(a.x+b.x)*.5,(a.y+b.y)*.5;nx,nz:= -dz/length,dx/length
	// Sample beyond the structural thickness so junctions cannot accidentally
	// inherit the material from the wall's centerline.
	positive_surface:=house_surface_at(mx+nx*.24,mz+nz*.24)
	negative_surface:=house_surface_at(mx-nx*.24,mz-nz*.24)
	positive_interior:=mx+nx*.24>=0&&mx+nx*.24<f32(HOUSE_SURFACE_WIDTH)&&mz+nz*.24>=0&&mz+nz*.24<f32(HOUSE_SURFACE_HEIGHT)&&house_space_kind_at(mx+nx*.24,mz+nz*.24)==.Interior
	negative_interior:=mx-nx*.24>=0&&mx-nx*.24<f32(HOUSE_SURFACE_WIDTH)&&mz-nz*.24>=0&&mz-nz*.24<f32(HOUSE_SURFACE_HEIGHT)&&house_space_kind_at(mx-nx*.24,mz-nz*.24)==.Interior
	// The paint record is intentionally queried at rebuild time. A section can
	// later move between render chunks without losing its independently painted
	// positive/negative face.
	for paint in house_plan.wall_face_paints {
		if point_segment_distance_sq(mx,mz,paint.a,paint.b)<.08*.08 {
			if paint.positive {positive_surface=paint.surface} else {negative_surface=paint.surface}
		}
	}
	authored_height:=house_authored_wall_height();finish_bands:=house_wall_finish_bands();core:=procedural_wall_mesh(length,authored_height,width);apply_texture(&core,exterior_wall_texture)
	core_bands:[3]Glb_Mesh;for band in 0..<3 {region_base:=finish_bands[band];region_height:=finish_bands[band+1]-region_base;core_bands[band]=procedural_wall_band_mesh(a,b,region_base,region_height,width);apply_texture(&core_bands[band],exterior_wall_texture)}
	// A dedicated top cap makes a cutaway read as a deliberately sectioned wall
	// in aerial view, instead of as geometry that vanished with the camera.
	cap:=procedural_quad_mesh(length,width,true)
	positive:=procedural_quad_mesh(length,authored_height,false);apply_texture(&positive,house_wall_materials[positive_surface])
	negative:=procedural_quad_mesh(length,authored_height,false);apply_texture(&negative,house_wall_materials[negative_surface])
	append(&house_walls,Floorplan_Wall{a=a,b=b,width=width,positive_surface=positive_surface,negative_surface=negative_surface,positive_interior=positive_interior,negative_interior=negative_interior,core=core,cap=cap,face_positive=positive,face_negative=negative,core_bands=core_bands})
}

// Material faces are separate from the unioned structural solid. Split them at
// every collinear doorway too, otherwise a wallpaper quad visually seals the
// correctly-cut structural opening behind it.
append_house_wall_piece :: proc(a,b:Vec2,width:f32) {
	dx,dz:=b.x-a.x,b.y-a.y;length_sq:=dx*dx+dz*dz;if length_sq<=.0001 do return
	cursor:f32=0
	for cursor<1-.0001 {
		next_start,next_end:f32=1,1;found:=false
		for opening in house_plan.openings {
			mx,mz:=(opening.a.x+opening.b.x)*.5,(opening.a.y+opening.b.y)*.5
			// A long opening can straddle a render-chunk boundary, leaving its
			// midpoint outside this particular chunk even though part of the opening
			// overlaps it. Test distance to the supporting wall line here; the
			// projected interval checks below decide whether the spans overlap.
			line_distance_numerator:=(mx-a.x)*dz-(mz-a.y)*dx
			if line_distance_numerator*line_distance_numerator>.08*.08*length_sq do continue
			ta:=((opening.a.x-a.x)*dx+(opening.a.y-a.y)*dz)/length_sq
			tb:=((opening.b.x-a.x)*dx+(opening.b.y-a.y)*dz)/length_sq
			lo,hi:=min(ta,tb),max(ta,tb);if hi<=cursor+.0001||lo>=1-.0001 do continue
			lo,hi=clamp(lo,0,1),clamp(hi,0,1)
			if !found||lo<next_start {next_start,next_end=lo,hi;found=true}
		}
		if !found {append_house_wall_piece_raw({a.x+dx*cursor,a.y+dz*cursor},b,width);break}
		if next_start>cursor+.0001 do append_house_wall_piece_raw({a.x+dx*cursor,a.y+dz*cursor},{a.x+dx*next_start,a.y+dz*next_start},width)
		cursor=max(cursor,next_end)
	}
}

append_house_wall_span :: proc(a,b:Vec2,width:f32) {
	// One authored path may border several rooms. Split it at every collinear
	// room corner so each rendered face has a midpoint that belongs to exactly
	// one room. The old sample-house constants only happened to work for its
	// original dimensions and allowed neighboring finishes to bleed across long
	// walls in authored levels.
	dx,dz:=b.x-a.x,b.y-a.y;length_sq:=dx*dx+dz*dz;if length_sq<=.0001 do return
	breaks:[128]f32;break_count:=2;breaks[0]=0;breaks[1]=1
	for room in level_document.rooms {if room.story!=level_document.active_story do continue;for point in room.points {
		t:=((point.x-a.x)*dx+(point.y-a.y)*dz)/length_sq;if t<=.0001||t>=.9999 do continue
		projected:=Vec2{a.x+dx*t,a.y+dz*t};offset_x,offset_z:=point.x-projected.x,point.y-projected.y;if offset_x*offset_x+offset_z*offset_z>.001*.001 do continue
		duplicate:=false;for i in 0..<break_count do if math.abs(breaks[i]-t)<.0001 {duplicate=true;break};if duplicate||break_count>=len(breaks) do continue
		insert:=break_count;for i in 0..<break_count {if t<breaks[i] {insert=i;break}};for i:=break_count;i>insert;i-=1 do breaks[i]=breaks[i-1];breaks[insert]=t;break_count+=1
	}}
	for i in 0..<break_count-1 {start,finish:=breaks[i],breaks[i+1];if finish-start<=.0001 do continue;append_house_wall_piece({a.x+dx*start,a.y+dz*start},{a.x+dx*finish,a.y+dz*finish},width)}
}
load_furniture_meshes :: proc()->bool {
	for path,kind in FURNITURE_PATHS {furniture_meshes[kind],_=glb_load(path)}
	assets_ok:=true;ok:bool
	case_statuette_mesh,ok=glb_load("assets/models/bronze-statuette.glb");assets_ok=assets_ok&&ok&&case_statuette_mesh.ready
	case_cane_mesh,ok=glb_load("assets/models/edgars-cane.glb");assets_ok=assets_ok&&ok&&case_cane_mesh.ready
	case_ledger_mesh,ok=glb_load("assets/models/private-ledger.glb");assets_ok=assets_ok&&ok&&case_ledger_mesh.ready
	case_cloth_mesh,ok=glb_load("assets/models/polishing-cloth.glb");assets_ok=assets_ok&&ok&&case_cloth_mesh.ready
	case_oil_mesh,ok=glb_load("assets/models/lamp-oil-bottle.glb");assets_ok=assets_ok&&ok&&case_oil_mesh.ready
	case_watch_mesh,ok=glb_load("assets/models/stopped-watch-824.glb");assets_ok=assets_ok&&ok&&case_watch_mesh.ready
	case_wastebin_mesh,ok=glb_load("assets/models/miriam-metal-wastebin.glb");assets_ok=assets_ok&&ok&&case_wastebin_mesh.ready
	case_rug_unfolded_mesh,ok=glb_load("assets/rugs/study_rug_unfolded.glb");assets_ok=assets_ok&&ok&&case_rug_unfolded_mesh.ready
	case_rug_folded_mesh,ok=glb_load("assets/rugs/study_rug_folded.glb");assets_ok=assets_ok&&ok&&case_rug_folded_mesh.ready
	bloodstain_mesh=procedural_quad_mesh(1.6,1.6,true)
	apply_texture(&bloodstain_mesh,load_room_texture("assets/models/crime-scene/bloodstain-decal.png"))
	drag_trace_mesh=procedural_quad_mesh(5.6,2.2,true)
	apply_texture(&drag_trace_mesh,load_room_texture("assets/decals/garden-drag-trace.png"))
	catalog_thumbnail_floor=procedural_quad_mesh(1,1,true)
	vehicle_skid_mesh=procedural_quad_mesh(.12,.62,true)
	yard_grass_texture=load_room_texture(YARD_GRASS_TEXTURE_PATH);yard_gravel_texture=load_room_texture(YARD_GRAVEL_TEXTURE_PATH);yard_dirt_texture=load_room_texture(YARD_DIRT_TEXTURE_PATH);yard_flagstone_texture=load_room_texture(YARD_FLAGSTONE_TEXTURE_PATH)
	roof_texture=load_room_texture(ROOF_TEXTURE_PATH);exterior_wall_texture=load_room_texture(EXTERIOR_WALL_TEXTURE_PATH)
	for surface in Room_Surface {house_wall_materials[surface]=load_room_texture(WALL_COVERING_PATHS[surface]);house_floor_materials[surface]=procedural_quad_mesh(1,1,true);apply_texture(&house_floor_materials[surface],load_room_texture(FLOOR_COVERING_PATHS[surface]))}
	house_plan_initialize();_ = house_plan_validate()
	level_validation:=level_editor_initialize();if !level_validation.ok do fmt.eprintln("level editor: ",level_validation.message)
	load_catalog_object_meshes()
	build_house_floorplan()
	build_house_navmesh()
	return assets_ok
}
vertical_ranges_overlap :: proc(a_min,a_max,b_min,b_max:f32)->bool {return a_min<b_max&&a_max>b_min}

catalog_object_collision_bounds :: proc(object:Level_Object)->(radius,base,top:f32) {
	entry,found:=catalog_object_entry(object.catalog_id);radius=.35;height:=f32(.5)
	if found {radius=max(entry.footprint,.2);mesh,mesh_found:=catalog_object_mesh(object.catalog_id);if mesh_found do height=catalog_object_render_height(mesh,entry);else if entry.dimensions.y>0 do height=entry.dimensions.y}
	base=object.elevation
	if level_terrain_supports_position(&level_document,object.position,object.story) do base+=level_terrain_height(&level_document,object.position)
	return radius,base,base+height
}

catalog_object_blocks_movement :: proc(object:Level_Object)->bool {
	entry,found:=catalog_object_entry(object.catalog_id)
	// Rugs, runners, and doormats are authored floor coverings. Their footprint
	// is useful for selection, but it is not a collision volume.
	return !found||entry.category!="rugs"
}

furniture_blocked :: proc(x,y:f32)->bool {
	ground:=house_player_ground_height({x,y});player_min,player_max:=ground+.05,ground+1.65
	for item in house_plan.furniture {dx:=x-item.x;dy:=y-item.y;if dx*dx+dy*dy<item.radius*item.radius&&vertical_ranges_overlap(player_min,player_max,item.elevation,item.elevation+item.height) do return true}
	for object in level_document.objects {
		if object.story!=level_document.active_story||!catalog_object_blocks_movement(object) do continue
		radius,base,top:=catalog_object_collision_bounds(object);dx,dy:=x-object.position.x,y-object.position.y
		if dx*dx+dy*dy<radius*radius&&vertical_ranges_overlap(player_min,player_max,base,top) do return true
	}
	return false
}
water_blocked :: proc(x,y:f32)->bool {if level_document.active_story!=0 do return false;point:=Vec2{x,y};for water in level_document.waters do if level_point_in_polygon(point,water.points[:]) do return true;return false}
nav_cell_index :: proc(x,y:int)->int {return y*HOUSE_NAV_WIDTH+x}
nav_cell_center :: proc(index:int)->Vec2 {return {f32(index%HOUSE_NAV_WIDTH)*HOUSE_NAV_CELL+HOUSE_NAV_CELL*.5,f32(index/HOUSE_NAV_WIDTH)*HOUSE_NAV_CELL+HOUSE_NAV_CELL*.5}}
nav_attic_roof_clearance :: proc(point:Vec2)->(f32,bool) {
	story:=level_document.active_story;if story<0||story>=len(level_document.stories) do return 0,false
	active:=level_document.stories[story];if active.name!="Attic"&&!strings.has_prefix(active.id,"attic_") do return 0,false
	below:=level_story_below(&level_document,story);if below<0 do return 0,true
	best:=f32(-1);for roof_index in 0..<generated_roof_count {
		if generated_roof_story[roof_index]!=below do continue
		mesh:=&generated_roof_meshes[roof_index];for triangle:=0;triangle+2<len(mesh.indices);triangle+=3 {
			a,b,c:=mesh.vertices[mesh.indices[triangle]],mesh.vertices[mesh.indices[triangle+1]],mesh.vertices[mesh.indices[triangle+2]]
			denominator:=(b.z-c.z)*(a.x-c.x)+(c.x-b.x)*(a.z-c.z);if math.abs(denominator)<.00001 do continue
			u:=((b.z-c.z)*(point.x-c.x)+(c.x-b.x)*(point.y-c.z))/denominator;v:=((c.z-a.z)*(point.x-c.x)+(a.x-c.x)*(point.y-c.z))/denominator;w:=1-u-v
			if u<-.0001||v<-.0001||w<-.0001 do continue
			height:=generated_roof_base_y[roof_index]+a.y*u+b.y*v+c.y*w-active.base_elevation;best=max(best,height)
		}
	}
	return best,true
}
nav_point_walkable :: proc(x,y:f32)->bool {clearance:=[5]Vec2{{0,0},{.24,0},{-.24,0},{0,.24},{0,-.24}};for offset in clearance {point:=Vec2{x+offset.x,y+offset.y};roof_height,attic:=nav_attic_roof_clearance(point);if attic&&roof_height<HOUSE_ATTIC_NAV_CLEARANCE do return false;if world_wall(point.x,point.y)||furniture_blocked(point.x,point.y)||water_blocked(point.x,point.y) do return false};return true}
nav_traversal_cost :: proc(point:Vec2)->f32 {
	for path in level_document.paths {
		if path.story!=level_document.active_story||(path.kind!=.Footpath&&path.kind!=.Road) do continue
		radius:=max(path.width*.5,HOUSE_NAV_CELL*.5);for i in 0..<len(path.points)-1 do if point_segment_distance_sq(point.x,point.y,path.points[i],path.points[i+1])<=radius*radius do return HOUSE_AUTHORED_PATH_COST
	}
	return 1
}
build_house_navmesh :: proc() {for y in 0..<HOUSE_NAV_HEIGHT {for x in 0..<HOUSE_NAV_WIDTH {center:=nav_cell_center(nav_cell_index(x,y));house_nav_walkable[nav_cell_index(x,y)]=nav_point_walkable(center.x,center.y)}}}
nav_nearest_walkable :: proc(point:Vec2)->int {base_x:=clamp(int(point.x/HOUSE_NAV_CELL),0,HOUSE_NAV_WIDTH-1);base_y:=clamp(int(point.y/HOUSE_NAV_CELL),0,HOUSE_NAV_HEIGHT-1);for radius in 0..<max(HOUSE_NAV_WIDTH,HOUSE_NAV_HEIGHT) {for y:=max(0,base_y-radius);y<=min(HOUSE_NAV_HEIGHT-1,base_y+radius);y+=1 {for x:=max(0,base_x-radius);x<=min(HOUSE_NAV_WIDTH-1,base_x+radius);x+=1 {if x!=base_x-radius&&x!=base_x+radius&&y!=base_y-radius&&y!=base_y+radius do continue;index:=nav_cell_index(x,y);if house_nav_walkable[index] do return index}}};return -1}
nav_build_path :: proc(g:^Game,start,goal:Vec2)->bool {
	start_index:=nav_nearest_walkable(start);goal_index:=nav_nearest_walkable(goal);g.nav_path_count=0;g.nav_path_index=0;if start_index<0||goal_index<0 do return false
	cost:[HOUSE_NAV_CELLS]f32;parent:[HOUSE_NAV_CELLS]int;closed:[HOUSE_NAV_CELLS]bool;for i in 0..<HOUSE_NAV_CELLS {cost[i]=1e30;parent[i]=-1};cost[start_index]=0
	for _ in 0..<HOUSE_NAV_CELLS {current:=-1;best:f32=1e30;for i in 0..<HOUSE_NAV_CELLS do if house_nav_walkable[i]&&!closed[i]&&cost[i]<best {best=cost[i];current=i};if current<0||current==goal_index do break;closed[current]=true;cx,cy:=current%HOUSE_NAV_WIDTH,current/HOUSE_NAV_WIDTH;for oy:=-1;oy<=1;oy+=1 {for ox:=-1;ox<=1;ox+=1 {if ox==0&&oy==0 do continue;nx,ny:=cx+ox,cy+oy;if nx<0||ny<0||nx>=HOUSE_NAV_WIDTH||ny>=HOUSE_NAV_HEIGHT do continue;neighbor:=nav_cell_index(nx,ny);if !house_nav_walkable[neighbor]||closed[neighbor] do continue;if ox!=0&&oy!=0&&(!house_nav_walkable[nav_cell_index(cx+ox,cy)]||!house_nav_walkable[nav_cell_index(cx,cy+oy)]) do continue;step:f32=ox!=0&&oy!=0?1.4142135:1.0;candidate:=cost[current]+step*nav_traversal_cost(nav_cell_center(neighbor));if candidate<cost[neighbor] {cost[neighbor]=candidate;parent[neighbor]=current}}}}
	if goal_index!=start_index&&parent[goal_index]<0 do return false;reverse:[256]Vec2;count:=0;node:=goal_index;for node!=start_index&&count<len(reverse) {reverse[count]=nav_cell_center(node);count+=1;node=parent[node]};for i:=count-1;i>=0;i-=1 {g.nav_path[g.nav_path_count]=reverse[i];g.nav_path_count+=1};if g.nav_path_count==0||g.nav_path[g.nav_path_count-1].x!=goal.x||g.nav_path[g.nav_path_count-1].y!=goal.y {if g.nav_path_count<len(g.nav_path) {g.nav_path[g.nav_path_count]=nav_cell_center(goal_index);g.nav_path_count+=1}};return g.nav_path_count>0
}
character_presentation :: proc(source_id:string)->(animation:string,tint:[4]u8,phase_offset:f32) {
	switch source_id {
	case "miriam": return "Idle_A",{255,255,255,255},0
	case "daniel": return "Idle_B",{255,255,255,255},2.1
	case "elsie": return "Idle_A",{255,255,255,255},4.2
	}
	return "Idle_A",{255,255,255,255},0
}

character_mesh_index :: proc(source_id:string)->int {switch source_id {case "miriam":return 1;case "daniel":return 2;case "elsie":return 3};return 0}
character_mesh_for :: proc(source_id:string)->^Glb_Mesh {return &character_meshes[character_mesh_index(source_id)]}
Character_Action :: enum {Interact,Sit,Jump,React,Death}
character_action_clip :: proc(mesh:^Glb_Mesh,action:Character_Action)->int {switch action {case .Interact:return glb_clip_index(mesh,"Interact");case .Sit:return glb_clip_index_suffix(mesh,"_Sitting");case .Jump:return glb_clip_index_suffix(mesh,"_Jump");case .React:return glb_clip_index_suffix(mesh,"_Punch");case .Death:return glb_clip_index_suffix(mesh,"_Death")};return -1}

initialize_character_animations :: proc(g:^Game) {player_mesh:=&character_meshes[0];player_idle:=glb_clip_index(player_mesh,"Idle_A");g.player_animation={current=player_idle,next=-1,idle_clip=player_idle,action_clip=-1};payload:=mystery_game_payload(g);if payload==nil do return;for character,i in payload.characters {if i>=len(g.character_animations) do break;mesh:=character_mesh_for(character.entity_id);name,_,phase:=character_presentation(character.entity_id);clip:=glb_clip_index(mesh,name);duration:=clip>=0?mesh.clips[clip].duration:0;t:=phase;if duration>0 do t-=f32(math.floor(f64(t/duration)))*duration;g.character_animations[i]={current=clip,next=-1,idle_clip=clip,action_clip=-1,time=t}}}
character_animation_transition :: proc(state:^Character_Animation,next:int) {if next<0||state.next==next&&state.transitioning do return;state.next=next;state.next_time=0;state.transition=0;state.transitioning=true}
trigger_character_action :: proc(g:^Game,source_id:string,action:Character_Action)->bool {index:=character_index(g,source_id);if index<0||index>=len(g.character_animations) do return false;clip:=character_action_clip(character_mesh_for(source_id),action);if clip<0 do return false;state:=&g.character_animations[index];state.action_clip=clip;state.action_loop=action==.Sit;state.action_hold=action==.Death;state.interacting=action==.Interact;character_animation_transition(state,clip);return true}
trigger_character_interact :: proc(g:^Game,source_id:string) {_=trigger_character_action(g,source_id,.Interact)}
stop_character_action :: proc(g:^Game,source_id:string)->bool {index:=character_index(g,source_id);if index<0||index>=len(g.character_animations) do return false;state:=&g.character_animations[index];if state.action_clip<0 do return false;state.action_clip=-1;state.action_loop=false;state.action_hold=false;state.interacting=false;next_idle:=state.idle_clip;if next_idle<0 do next_idle=glb_clip_index(character_mesh_for(source_id),"Idle_A");character_animation_transition(state,next_idle);return true}
update_one_character_animation :: proc(mesh:^Glb_Mesh,state:^Character_Animation,dt:f32,idle_a,idle_b:int) {if state.current<0 do return;state.time+=dt;if state.transitioning {state.next_time+=dt;state.transition+=dt/.25;if state.transition>=1 {state.current=state.next;state.time=state.next_time;state.next=-1;state.transition=0;state.transitioning=false}};if state.transitioning do return;duration:=mesh.clips[state.current].duration;if state.current==state.action_clip {if duration>0&&state.time>=duration {if state.action_loop do state.time-=f32(math.floor(f64(state.time/duration)))*duration;else if state.action_hold do state.time=duration;else {state.interacting=false;state.action_clip=-1;next_idle:=state.idle_clip;if next_idle<0 do next_idle=idle_a;character_animation_transition(state,next_idle)}}}else if state.current==idle_a||state.current==idle_b {state.idle_clip=state.current;if duration>0&&state.time>=max(0,duration-.25) {next_idle:=state.current==idle_a?idle_b:idle_a;state.idle_clip=next_idle;character_animation_transition(state,next_idle)}}}
update_player_animation :: proc(g:^Game,dt:f32) {mesh:=&character_meshes[0];state:=&g.player_animation;idle:=glb_clip_index(mesh,"Idle_A");walk:=glb_clip_index(mesh,"Walking_B");run:=glb_clip_index(mesh,"Running_A");running:=g.player_is_walking&&g.player_walk_speed>HOUSE_MANUAL_MOVE_SPEED*1.15&&run>=0;target:=running?run:(g.player_is_walking&&walk>=0?walk:idle);if target>=0 {if state.transitioning&&state.next!=target {if state.current==target {state.current,state.next=state.next,state.current;state.time,state.next_time=state.next_time,state.time;state.transition=1-state.transition}else{character_animation_transition(state,target)}}else if !state.transitioning&&state.current!=target do character_animation_transition(state,target)};reference_speed:f32=running?HOUSE_MANUAL_MOVE_SPEED*1.5:HOUSE_MANUAL_MOVE_SPEED;clip_dt:=g.player_is_walking?dt*clamp(g.player_walk_speed/reference_speed,.38,1.35):dt;state.time+=clip_dt;if state.transitioning {state.next_time+=clip_dt;state.transition+=dt/.18;if state.transition>=1 {state.current=state.next;state.time=state.next_time;state.next=-1;state.transition=0;state.transitioning=false}};if !state.transitioning {duration:=mesh.clips[state.current].duration;if duration>0&&state.time>=duration do state.time-=f32(math.floor(f64(state.time/duration)))*duration}}
update_character_animations :: proc(g:^Game,dt:f32) {update_player_animation(g,dt);payload:=mystery_game_payload(g);if payload==nil do return;for &state,i in g.character_animations {if i>=len(payload.characters) do break;mesh:=character_mesh_for(payload.characters[i].entity_id);idle_a:=glb_clip_index(mesh,"Idle_A");idle_b:=glb_clip_index(mesh,"Idle_B");update_one_character_animation(mesh,&state,dt,idle_a,idle_b)}}

clue_for_source :: proc(g:^Game,source_id:string)->int {canonical:=source_id=="shutter_thread"?"shutter_crank":source_id;payload:=mystery_game_payload(g);if payload!=nil do for clue,i in payload.clues do if clue.source_id==canonical do return i;return -1}

world_entity_binding_position :: proc(doc:^Level_Document,entity:^Story_Entity)->(Vec2,bool) {
	if entity.spatial.space_id!=doc.id||entity.spatial.target_id=="" do return {},false
	switch entity.spatial.target_kind {
	case .Marker:
		index:=level_marker_index(doc,entity.spatial.target_id);if index>=0 do return doc.markers[index].position,true
	case .Room:
		index:=level_room_index(doc,entity.spatial.target_id);if index>=0 {room:=doc.rooms[index];center:=Vec2{};for point in room.points {center.x+=point.x;center.y+=point.y};if len(room.points)>0 {center.x/=f32(len(room.points));center.y/=f32(len(room.points));return center,true}}
	case .Entity:
		index:=level_object_index(doc,entity.spatial.target_id);if index>=0 do return doc.objects[index].position,true
	case .Interaction:
		if index:=level_object_index(doc,entity.spatial.target_id);index>=0 do return doc.objects[index].position,true
		if index:=level_marker_index(doc,entity.spatial.target_id);index>=0 do return doc.markers[index].position,true
		if index:=level_opening_index(doc,entity.spatial.target_id);index>=0 do return level_opening_position(doc,doc.openings[index])
	case .Transition:
		index:=level_marker_index(doc,entity.spatial.target_id);if index>=0 do return doc.markers[index].position,true
	}
	return {},false
}

world_entities_rebuild :: proc(project:^Story_Project,doc:^Level_Document)->Validation {
	clear(&WORLD_ENTITIES)
	if project==nil do return {false,"world entities require a StoryCore project"}
	for &entity in project.entities {
		if !story_entity_has_role(project,entity.id,"world_entity") do continue
		position,found:=world_entity_binding_position(doc,&entity);if !found do return {false,fmt.tprintf("world entity %s requires a valid LevelFormat spatial binding",entity.id)}
		if world_entity_index(entity.id)>=0 do return {false,fmt.tprintf("duplicate world entity binding: %s",entity.id)}
		kind:=entity.kind=="character"||entity.kind=="person"?"person":"object"
		elevation,facing,scale:=f32(0),f32(0),f32(1)
		if index:=level_marker_index(doc,entity.spatial.target_id);index>=0 {elevation=doc.markers[index].camera_height;facing=doc.markers[index].facing*f32(math.PI)/180;if doc.markers[index].radius>0 do scale=doc.markers[index].radius}
		item:=World_Entity{x=position.x,y=position.y,elevation=elevation,facing=facing,scale=scale,kind=kind,source_id=entity.id,name=entity.display_name,description=entity.description,appearance=entity.appearance_model_asset_ref,tag_count=entity.tag_count}
		for tag,i in entity.tags[:entity.tag_count] do item.tags[i]=tag
		append(&WORLD_ENTITIES,item)
	}
	if len(WORLD_ENTITIES)==0 do return {false,"story defines no world_entity roles"}
	return {true,fmt.tprintf("projected %d authored world entities",len(WORLD_ENTITIES))}
}

world_entity_index :: proc(source_id:string)->int {for entity,i in WORLD_ENTITIES do if entity.source_id==source_id do return i;return -1}
world_marker_pose :: proc(id:string,fallback_position:Vec2,fallback_radius,fallback_facing:f32)->(Vec2,f32,f32) {
	index:=level_marker_index(&level_document,id);if index<0 do return fallback_position,fallback_radius,fallback_facing
	marker:=level_document.markers[index];return marker.position,max(marker.radius,.01),marker.facing*f32(math.PI)/180
}
world_rotated_object_anchor :: proc(object:Level_Object,offset:Vec2,authored_rotation:f32)->Vec2 {angle:=(object.rotation-authored_rotation)*f32(math.PI)/180;c,s:=f32(math.cos(f64(angle))),f32(math.sin(f64(angle)));return {object.position.x+offset.x*c-offset.y*s,object.position.y+offset.x*s+offset.y*c}}
open_evidence_dialogue :: proc(g:^Game,index:int)->bool {
	if index<0||index>=len(WORLD_ENTITIES)||WORLD_ENTITIES[index].kind=="person" do return false
	g.dialogue_entity=index;g.dialogue_node=0;g.dialogue_ledger_scroll=0;g.dialogue_choice_page=0;g.dialogue_response="";g.dialogue_text_started=g.animation_time;g.pending_dialogue_approach=0;g.check_from_dialogue=false;g.screen=.Dialogue;dialogue_focus_default(g)
	return true
}
entity_examination_complete :: proc(g:^Game,entity_index:int)->bool {
	if entity_index<0||entity_index>=len(WORLD_ENTITIES) do return false
	clue:=clue_for_source(g,WORLD_ENTITIES[entity_index].source_id)
	return clue>=0&&mystery_game_clue_discovered(g,clue)
}
world_authored_room_at_point :: proc(point:Vec2)->int {
	story:=max(level_document.active_story,0)
	for room,i in level_document.rooms do if room.story==story&&level_point_in_polygon(point,room.points[:]) do return i
	return -1
}

world_location_id_for_room :: proc(room_id:string)->string {
	// Most authored room IDs are the investigative location IDs. These two
	// names predate that convention in the Vale House source document.
	switch room_id {case "gallery":return "hall";case "moon_garden":return "garden"}
	return room_id
}

world_room_open_connection :: proc(a_index,b_index:int)->bool {
	if a_index<0||b_index<0||a_index>=len(level_document.rooms)||b_index>=len(level_document.rooms) do return false
	a_room,b_room:=&level_document.rooms[a_index],&level_document.rooms[b_index]
	if a_room.story!=b_room.story do return false
	for a,i in a_room.points {b:=a_room.points[(i+1)%len(a_room.points)];adx,ady:=b.x-a.x,b.y-a.y;length_sq:=adx*adx+ady*ady;if length_sq<.0001 do continue
		for c,j in b_room.points {d:=b_room.points[(j+1)%len(b_room.points)];cdx,cdy:=d.x-c.x,d.y-c.y
			if math.abs(adx*cdy-ady*cdx)>.001||point_segment_distance_sq(c.x,c.y,a,b)>.001&&point_segment_distance_sq(d.x,d.y,a,b)>.001 do continue
			t0:=((c.x-a.x)*adx+(c.y-a.y)*ady)/length_sq;t1:=((d.x-a.x)*adx+(d.y-a.y)*ady)/length_sq;start,end:=max(0,min(t0,t1)),min(1,max(t0,t1));if end-start<.02 do continue
			// An authored wall path means the rooms meet through a doorway or arch.
			// With no wall across their shared edge, they form one visual search area.
			mid:=Vec2{a.x+adx*(start+end)*.5,a.y+ady*(start+end)*.5};wall_present:=false
			for path in level_document.paths {if path.story!=a_room.story||path.kind!=.Wall&&path.kind!=.Freestanding_Wall do continue;for k in 0..<len(path.points)-1 {p,q:=path.points[k],path.points[k+1];pdx,pdy:=q.x-p.x,q.y-p.y;if math.abs(adx*pdy-ady*pdx)>.001 do continue;if point_segment_distance_sq(mid.x,mid.y,p,q)<.001 {wall_present=true;break}};if wall_present do break}
			if !wall_present do return true
		}
	}
	return false
}

world_room_location_index :: proc(g:^Game,room_index:int)->int {
	if room_index<0||room_index>=len(level_document.rooms) do return -1
	id:=world_location_id_for_room(level_document.rooms[room_index].id);payload:=mystery_game_payload(g);if payload!=nil do for location,i in payload.locations do if location.entity_id==id do return i
	return -1
}

world_location_index :: proc(g:^Game)->int {
	room_index:=world_authored_room_at_point({g.player_x,g.player_y})
	if room_index<0 do return -1
	location_id:=world_location_id_for_room(level_document.rooms[room_index].id)
	payload:=mystery_game_payload(g);if payload!=nil do for location,i in payload.locations do if location.entity_id==location_id do return i
	return -1
}

world_location_label :: proc(g:^Game)->string {
	location:=world_location_index(g)
	payload:=mystery_game_payload(g);if payload!=nil&&location>=0&&location<len(payload.locations) do return character_display_name(g,payload.locations[location].entity_id)
	room:=world_authored_room_at_point({g.player_x,g.player_y})
	if room>=0 do return level_document.rooms[room].name
	return fmt.tprintf("%s · GROUNDS",level_document.name)
}
poi_index :: proc(g:^Game,id:string)->int {payload:=mystery_game_payload(g);if payload!=nil do for poi,i in payload.pois do if poi.entity_id==id do return i;return -1}
entity_visible :: proc(g:^Game,e:^World_Entity)->bool {
	if e.source_id=="ledger" do return g.desk_open
	if e.source_id=="memo_stub" do return g.desk_open
	if e.source_id=="shutter_thread" do return false
	i:=poi_index(g,e.source_id);if i<0 do return true;return mystery_game_poi_revealed(g,i)
}
location_reveals_pois :: proc(g:^Game,index:int)->bool {payload:=mystery_game_payload(g);if payload==nil||index<0||index>=len(payload.locations) do return false;location:=&payload.locations[index];for i in 0..<location.search_action_count do if location.search_actions[i]=="search" do return true;return false}
reveal_location_pois :: proc(g:^Game,index:int)->bool {payload:=mystery_game_payload(g);if payload==nil||g.mystery_state==nil||index<0||index>=len(payload.locations)||!location_reveals_pois(g,index) do return false;rooms:=make([]bool,len(level_document.rooms),context.temp_allocator);pending:=make([dynamic]int,0,len(level_document.rooms),context.temp_allocator);for _,i in level_document.rooms do if world_room_location_index(g,i)==index {rooms[i]=true;append(&pending,i)};for cursor:=0;cursor<len(pending);cursor+=1 {room:=pending[cursor];for _,other in level_document.rooms {if rooms[other]||!world_room_open_connection(room,other) do continue;rooms[other]=true;append(&pending,other)}};locations:=make([]bool,len(payload.locations),context.temp_allocator);locations[index]=true;for connected,room in rooms do if connected {location:=world_room_location_index(g,room);if location>=0&&location<len(locations) do locations[location]=true};changed:=false;revealed:=0;for connected,location in locations do if connected&&mystery_game_mark_location_searched(g,location) do changed=true;for poi,i in payload.pois {location:=false;for connected,location_index in locations do if connected&&poi.location_id==payload.locations[location_index].entity_id {location=true;break};if location {
		// The ledger remains inside its locked desk, and the cloth belongs to the
		// service closet rather than the pantry's general arrival reveal.
		if poi.entity_id=="ledger"||poi.entity_id=="cloth" do continue
		if mystery_game_mark_poi_revealed(g,i) {revealed+=1;changed=true}
	}};if !changed do return false;g.location_result=fmt.tprintf("%s — %d point%s of interest revealed.",character_display_name(g,payload.locations[index].entity_id),revealed,revealed==1?"":"s");log_line(g,g.location_result);return true}

reveal_service_closet :: proc(g:^Game)->bool {
	if g.service_closet_entered do return false
	// The rear bay of the service wing reads as a closet through its shelving
	// and narrow approach. Crossing into it is the search action.
	if g.player_x<28||g.player_y<18 do return false
	g.service_closet_entered=true;index:=poi_index(g,"cloth");if index<0||!mystery_game_mark_poi_revealed(g,index) do return false
	g.location_result="SERVICE CLOSET — A damp polishing cloth is tucked among the supplies.";log_line(g,g.location_result);context_feedback(g,"POLISHING CLOTH DISCOVERED",.Available,"cloth");return true
}
public_source_description :: proc(g:^Game,source_id:string)->string {
	if index:=world_entity_index(source_id);index>=0&&WORLD_ENTITIES[index].description!="" do return WORLD_ENTITIES[index].description
	if g.story_project!=nil {if index:=story_entity_index(g.story_project,source_id);index>=0&&g.story_project.entities[index].description!="" do return g.story_project.entities[index].description}
	return "There is more here than first appears."
}
officer_source :: proc(source_id:string)->bool {if index:=world_entity_index(source_id);index>=0 do return world_entity_has_tag(&WORLD_ENTITIES[index],"officer");return false}
officer_choice_rect :: proc(slot:int)->Rect {return {650,488+f32(slot)*48,490,40}}
officer_confirmation_rect :: proc(confirm:bool)->Rect {return confirm?Rect{900,590,240,42}:Rect{650,590,240,42}}
officer_opening_line :: proc(source_id:string)->string {switch source_id {case "officer_lead":return "Bell closes his notebook. 'We can hold the room until you are ready to put the night together.'";case "officer_hall":return "'No one has left through the gallery, Lieutenant. I have kept it clear.'";case "officer_garden":return "'Body has not been moved since we arrived. Rain is starting to soften the marks.'"};return "The officer gives you a brief nod."}
officer_report_line :: proc(g:^Game,source_id:string)->string {
	known:=proc(g:^Game,id:string)->bool {return knowledge_piece_known(g,id)}
	switch source_id {
	case "officer_hall":
		if known(g,"ded_miriam_denial_disproved") do return "Reed lowers his voice. 'The burned scrap changed the house. Ward stopped pacing. Cross stopped watching the doors. Mrs. Vale has not looked toward the study once.'"
		if known(g,"ded_daniel_affair")&&known(g,"ded_elsie_theft") do return "Reed glances along the gallery. 'Ward and Cross have both amended their stories. Odd how quickly a crowded hall empties once the innocent lies have names.'"
		if known(g,"ded_daniel_affair")||known(g,"ded_elsie_theft") do return "Reed keeps his eyes on the gallery. 'One of them is telling a smaller truth now. The others heard it. They have been choosing their silences more carefully since.'"
		if known(g,"clue_dinner_settings") do return "Reed checks the gallery doors. 'Your dining-room record accounts for the two empty places. No one else has crossed this gallery since we secured it.'"
		return "Reed checks both gallery doors. 'The household is inside and no one has crossed my post. The dining room remains as we found it: two settings disturbed, the others cleared.'"
	case "officer_garden":
		if known(g,"ded_scene_staged") do return "Shaw looks from the flattened thyme to the terrace. 'This garden was arranged to answer the first question anyone would ask. Trouble is, it answers too neatly.'"
		if known(g,"ded_body_moved") do return "Shaw studies the trail without stepping closer. 'The rain can blur a route, Lieutenant. It cannot persuade me a dead man walked it.'"
		if known(g,"clue_drag") do return "Shaw steps clear of the thyme. 'I have marked the trail you found between the terrace and the body. No one will disturb it before the rain.'"
		return "Shaw keeps one boot outside the bed. 'Rain is taking the edges off the crushed thyme. The broad mark runs from the study terrace toward the body. I will keep everyone clear.'"
	}
	return officer_opening_line(source_id)
}
reflective_interaction_rect :: proc()->Rect {return {650,420,490,58}}
dining_walkthrough_rect :: proc()->Rect {return {650,574,490,52}}
pond_reflection_line :: proc(g:^Game)->string {
	known:=known_piece_count(g)
	if knowledge_piece_known(g,"ded_miriam_denial_disproved") do return "The pond joins the shuttered window to its reflection without a seam. The appointment has done the same to two scraps of paper. What remains is to make the room live through the joined account."
	daniel_explained:=knowledge_piece_known(g,"ded_daniel_affair")
	elsie_explained:=knowledge_piece_known(g,"ded_elsie_theft")
	if daniel_explained&&elsie_explained do return "Two lies have opened instead of closed: one leaves a chair unwatched, the other puts someone at the study door. Neither is the lie the fire was meant to erase."
	if daniel_explained||elsie_explained do return "One polished account has cracked and revealed a private fear beneath it. The other voices in Vale House may be protecting wrongs that are not murder, too."
	if knowledge_piece_known(g,"ded_scene_staged")||knowledge_piece_known(g,"ded_body_moved") do return "The garden is no longer a death scene; it is a performance left in the rain. The useful question is not what the audience saw, but who needed them to see it."
	if topic_unlocked(g,"edgar_controlled_by_correction")&&topic_unlocked(g,"edgar_kept_leverage")&&topic_unlocked(g,"edgar_household_power") do return "Three portraits of Edgar align in the water: clocks corrected, drafts retained, a bell pulled twice before blame. He made control look like order. The useful question is who learned to imitate him—and who merely learned to fear him."
	if known==0 do return "Rain breaks your reflection into pieces before it can settle. The house behind you is much the same: a collection of surfaces, not yet an account."
	if known<5 do return fmt.tprintf("Your reflection gathers between the raindrops. %d facts now hold their shape; the spaces between them are what trouble you.",known)
	return "The pond gives you back a tired but recognizable face. Enough facts are on record to distrust the picture; now they must be made to belong to the same night."
}
dining_walkthrough_line :: proc(g:^Game)->string {
	if claim_known(g,"claim_miriam_dinner")&&claim_known(g,"claim_daniel_alibi") do return "You speak the table aloud: fish at 8:20; Miriam's chair pushed back, her wine trailing; Daniel's napkin gone. Their two accounts depend on two empty places pretending to witness each other."
	return "You speak the arrangement aloud: fish served at 8:20, two untouched settings, one chair pushed back and one napkin missing. The table records absence more faithfully than the household does."
}
apply_player_spawn_marker :: proc(g:^Game,id:="spawn_player")->bool {
	index:=level_marker_index(&level_document,id);if index<0 do return false
	spawn:=level_document.markers[index];g.player_x=spawn.position.x;g.player_y=spawn.position.y;g.player_angle=spawn.facing*f32(math.PI)/180;g.camera_x=g.player_x;g.camera_y=g.player_y;g.camera_initialized=true;g.move_target_active=false;g.nav_path_count=0;g.nav_path_index=0
	return true
}
investigation_unresolved_summary :: proc(g:^Game)->string {
	payload:=mystery_game_payload(g)
	if payload==nil do return "Begin with separate accounts, then compare each statement with the rooms and objects that can test it."
	if !claim_known(g,"claim_miriam_dinner")||!claim_known(g,"claim_daniel_alibi")||!claim_known(g,"claim_elsie_study") do return "Start with separate accounts from Miriam, Daniel, and Elsie. Compare what each volunteers before showing anyone your evidence."
	if !g.desk_key_found do return "Inspect Edgar before chasing theories. Ask which details belong to the dead man—and which look arranged for an audience."
	disputed:=0;for i in 0..<g.workbench_event_count do if event_chain_disputed(g,i) do disputed+=1
	if disputed>0 do return fmt.tprintf("The evidence board still contains %d disputed event%s. Compare each disputed step with the evidence that fixes its time and place.",disputed,disputed==1?"":"s")
	for &question,i in payload.questions do if question_unlocked(g,i)&&!question_resolved(g,i) do return fmt.tprintf("Take this to the evidence board: %s Build the test from facts already on record.",question.prompt)
	clue,_:=case_sense_target(g);if clue>=0 do return fmt.tprintf("Follow the next unexamined source: %s. Ask what question it can test before deciding what it means.",case_sense_source_name(g,clue))
	sources:=[3]string{"miriam","daniel","elsie"};for source in sources {if dialogue_available_approach_count(g,source)>0 do return fmt.tprintf("Return to %s's account. A recorded fact now gives you a more precise question to ask.",character_display_name(g,source))}
	if g.workbench_event_count>0 do return "Your reconstruction has no unresolved conflicts. The bell is ready to gather everyone."
	return "No immediate lead is exhausted. Revisit the evidence board and arrange the known events before gathering everyone."
}
known_claim_text :: proc(g:^Game,source_id:string)->string {
	payload:=mystery_game_payload(g);if payload!=nil {character:=mystery_character_metadata(payload,source_id);if character!=nil do for i in 0..<character.initial_claim_count {claim_id:=character.initial_claims[i];if claim_known(g,claim_id) {claim_index:=mystery_claim_index(payload,claim_id);if claim_index>=0 do return mystery_story_proposition_text(g.story_project,payload.claims[claim_index].proposition_id)}}}
	return "No statement has been established yet."
}
character_reentry_line :: proc(g:^Game,source_id:string)->string {
	known:=proc(g:^Game,id:string)->bool {return knowledge_piece_known(g,id)}
	switch source_id {
	case "miriam":
		if known(g,"ded_miriam_denial_disproved") do return "Miriam leaves the corner of Edgar's blotter crooked. 'You have your scrap of paper, Lieutenant. I suppose you mean to make it speak for the whole house.'"
		if known(g,"ded_daniel_affair")&&known(g,"ded_elsie_theft") do return "Miriam's gaze moves from Daniel to Elsie and back to you. 'How industrious. You have taught confession to everyone except the person you came to accuse.'"
		if known(g,"ded_scene_staged") do return "Miriam straightens a chair that was already square. 'You have decided the garden is a performance. Do try not to confuse an audience with an author.'"
		return "Miriam makes room for exactly one question. 'You have returned. I assume that means you can now ask it precisely.'"
	case "daniel":
		if known(g,"ded_miriam_denial_disproved") do return "Daniel does not reach for the joined paper. 'That is Edgar's habit exactly: tear a meeting in half, then let the missing piece frighten you.'"
		if known(g,"ded_daniel_affair") do return "Daniel folds Miriam's note along its old crease. 'You know what I was protecting. That does not make me proud of how well I protected it.'"
		if known(g,"ded_scene_staged") do return "Daniel watches the study door. 'A false garden death is an accusation with the name omitted. I imagine you are here to supply it.'"
		if topic_unlocked(g,"failed_daniel_affair") do return "Daniel keeps one hand clear of his coat by visible effort. 'You may ask about dinner, Lieutenant. My pockets are not part of the estate.'"
		return "Daniel closes his watch before you can read it. 'Another question, Lieutenant? I will attempt a less professionally useless answer.'"
	case "elsie":
		if known(g,"ded_miriam_denial_disproved") do return "Elsie looks toward Miriam's sitting room. 'Paper burns from the edges inward. People seem to do it the other way round.'"
		if known(g,"ded_elsie_theft") do return "Elsie's hand passes over the now-empty pocket of her apron. 'You know the worst thing I did tonight. That makes the rest easier to say, though not much easier.'"
		if known(g,"ded_scene_staged") do return "Elsie glances toward the terrace. 'Gardens do not tidy themselves, Lieutenant. Nor do dead gentlemen.'"
		if topic_unlocked(g,"failed_elsie_theft") do return "Elsie stands between you and Edgar's desk without appearing to. 'If you have another question, ask it without deciding the answer first.'"
		return "Elsie dries her hands on an apron already dry. 'Ask, then. The work will still be waiting when we have finished.'"
	}
	return ""
}
dialogue_summary :: proc(value:string)->string {if len(value)<=43 do return value;return fmt.tprintf("%s...",value[:40])}

point_segment_distance_sq :: proc(px,py:f32,a,b:Vec2)->f32 {
	dx,dy:=b.x-a.x,b.y-a.y;length_sq:=dx*dx+dy*dy
	if length_sq<=0.0001 {ex,ey:=px-a.x,py-a.y;return ex*ex+ey*ey}
	t:=clamp(((px-a.x)*dx+(py-a.y)*dy)/length_sq,0,1);ex,ey:=px-(a.x+dx*t),py-(a.y+dy*t);return ex*ex+ey*ey
}
shutter_crank_world_position :: proc()->(Vec2,bool) {
	for entity in WORLD_ENTITIES do if entity.source_id=="shutter_crank" do return {entity.x,entity.y},true
	return {},false
}
runtime_interactive_index :: proc(g:^Game,id:string)->int {for interactive,i in g.interactives[:g.interactive_count] do if interactive.id==id do return i;return -1}
runtime_interactive_position :: proc(g:^Game,index:int)->(Vec2,bool) {if index<0||index>=g.interactive_count do return {},false;item:=g.interactives[index];if item.id=="shutter_crank" {position,found:=shutter_crank_world_position();if found do return position,true};for opening in house_plan.openings do if opening.id==item.id do return {(opening.a.x+opening.b.x)*.5,(opening.a.y+opening.b.y)*.5},true;for object in level_document.objects do if object.id==item.id do return object.position,true;for marker in level_document.markers do if marker.reference==item.id do return marker.position,true;return {},false}
runtime_interactives_rebuild :: proc(g:^Game) {
	g.interactive_count=0;g.hover_interactive=-1;g.near_interactive=-1;g.auto_door=-1
	for opening in level_document.openings {if opening.kind!=.Door||opening.interaction!=.Door||g.interactive_count>=len(g.interactives) do continue;open:=opening.initially_active?f32(1):f32(0);item:=Runtime_Interactive{id=opening.id,prompt=opening.interaction_prompt,condition_id=opening.condition_id,focused_scene=opening.focused_scene,behavior=.Door,openness=open,target=open,interaction_range=opening.interaction_range,effect_id_count=opening.effect_id_count,active=opening.initially_active,locked=opening.locked,powered=opening.powered};for effect,i in opening.effect_ids do item.effect_ids[i]=effect;g.interactives[g.interactive_count]=item;g.interactive_count+=1}
	for object in level_document.objects {if object.interaction==.None||g.interactive_count>=len(g.interactives) do continue;level:=object.initially_active?f32(1):f32(0);item:=Runtime_Interactive{id=object.id,prompt=object.interaction_prompt,condition_id=object.condition_id,focused_scene=object.focused_scene,behavior=object.interaction,openness=level,target=level,light_level=level,interaction_range=object.interaction_range,effect_id_count=object.effect_id_count,active=object.initially_active,locked=object.locked,powered=object.powered};for effect,i in object.effect_ids do item.effect_ids[i]=effect;g.interactives[g.interactive_count]=item;g.interactive_count+=1}
	for marker in level_document.markers {if marker.interaction==.None||g.interactive_count>=len(g.interactives) do continue;level:=marker.initially_active?f32(1):f32(0);id:=marker.reference;if id=="" do id=marker.id;item:=Runtime_Interactive{id=id,prompt=marker.interaction_prompt,condition_id=marker.condition_id,focused_scene=marker.focused_scene,behavior=marker.interaction,openness=level,target=level,interaction_range=marker.interaction_range,effect_id_count=marker.effect_id_count,active=marker.initially_active,locked=marker.locked,powered=marker.powered};for effect,i in marker.effect_ids do item.effect_ids[i]=effect;g.interactives[g.interactive_count]=item;g.interactive_count+=1}
}
runtime_door_opening :: proc(g:^Game,opening:Plan_Opening)->f32 {index:=runtime_interactive_index(g,opening.id);if index<0 do return 1;return g.interactives[index].openness}
runtime_interactive_prompt :: proc(g:^Game,index:int)->string {if index<0||index>=g.interactive_count do return "INTERACT";item:=g.interactives[index];if item.locked do return "LOCKED";if !item.powered do return "NO POWER";if item.prompt!="" do return item.prompt;switch item.behavior {case .Door:return item.target>=.5?"CLOSE DOOR":"OPEN DOOR";case .Toggle:return item.active?"TURN OFF LAMP":"TURN ON LAMP";case .Shutter:return g.shutter_target>=.5?"CRANK SHUTTER CLOSED":"CRANK SHUTTER OPEN";case .None:};return "INTERACT"}

context_runtime_authored :: proc(id:string)->(label,prompt:string) {
	for opening in level_document.openings do if opening.id==id {prompt=opening.interaction_prompt;label=strings.to_upper(prompt);if strings.has_prefix(label,"OPEN ") do label=label[5:];else if strings.has_prefix(label,"CLOSE ") do label=label[6:];else if strings.has_prefix(label,"USE ") do label=label[4:];if label=="" do label="DOOR";return}
	for object in level_document.objects do if object.id==id {
		prompt=object.interaction_prompt
		if prompt!="" {label=strings.to_upper(prompt);if strings.has_prefix(label,"USE ") do label=label[4:]}
		if label=="" {clean,_:=strings.replace_all(object.catalog_id,"_"," ");label=strings.to_upper(clean)}
		return
	}
	for entity in WORLD_ENTITIES do if entity.source_id==id do return entity.name,""
	clean,_:=strings.replace_all(id,"_"," ");return strings.to_upper(clean),""
}

context_runtime_target :: proc(g:^Game,index:int)->Context_Target {
	if index<0||index>=g.interactive_count do return {}
	item:=g.interactives[index];position,found:=runtime_interactive_position(g,index);if !found do return {}
	label,_:=context_runtime_authored(item.id);action:=runtime_interactive_prompt(g,index);status:=Context_Status.Available
	if item.behavior==.Shutter do label="STUDY SHUTTER"
	if item.locked do status=.Locked;else if !item.powered do status=.No_Power
	if item.behavior==.Door&&item.target>=.5 {dx,dy:=position.x-g.player_x,position.y-g.player_y;if dx*dx+dy*dy<1.05*1.05 {status=.Obstructed;action="STEP CLEAR TO CLOSE"}}
	dx,dy:=position.x-g.player_x,position.y-g.player_y;distance:=f32(math.sqrt(f64(dx*dx+dy*dy)))
	return {valid=true,kind=.Runtime_Interactive,status=status,stable_id=item.id,label=label,action=action,world=position,source_index=-1,runtime_index=index,priority=30,distance=distance,reachable=runtime_near_interactive_candidate(g,index)}
}

runtime_near_interactive_candidate :: proc(g:^Game,index:int)->bool {
	if index<0||index>=g.interactive_count do return false
	item:=g.interactives[index];position,found:=runtime_interactive_position(g,index);if !found do return false;interaction_range:=item.interaction_range;if interaction_range<=0 do interaction_range=1.8
	dx,dy:=position.x-g.player_x,position.y-g.player_y
	return dx*dx+dy*dy<=interaction_range*interaction_range&&world_interaction_line_clear(g,g.player_x,g.player_y,position.x,position.y,item.id)
}

context_entity_target :: proc(g:^Game,index:int)->Context_Target {
	if index<0||index>=len(WORLD_ENTITIES)||!entity_visible(g,&WORLD_ENTITIES[index]) do return {}
	entity:=WORLD_ENTITIES[index];position:=Vec2{entity.x,entity.y};if entity.source_id=="shutter_crank" {anchor,found:=shutter_crank_world_position();if found do position=anchor};dx,dy:=position.x-g.player_x,position.y-g.player_y;distance:=f32(math.sqrt(f64(dx*dx+dy*dy)));complete:=entity_examination_complete(g,index)
	action:=entity.kind=="person"?"TALK":"EXAMINE";status:=Context_Status.Available
	if complete {action="EXAMINED";status=.Complete}
	if entity.source_id=="study_desk" {action=g.desk_open?"OPEN":"UNLOCK";if !g.desk_open&&!g.desk_key_found&&!topic_unlocked(g,"elsie_desk_help") do status=.Locked}
	if entity.source_id=="body" {action=g.desk_key_found?"INSPECTED":"INSPECT";if g.desk_key_found do status=.Complete}
	if entity.source_id=="study_rug" {action=g.study_rug_lifted?"BLOOD EXPOSED":"LIFT RUG";if g.study_rug_lifted do status=.Complete}
	if entity.source_id=="statuette" do action=complete?"EXAMINED":"INSPECT"
	if entity.source_id=="shutter_thread" {action=complete?"EXAMINED":"INSPECT HOUSING";status=complete?.Complete:.Available}
	if entity.source_id=="memo_stub" {action=g.memo_stub_found?"STUB RECOVERED":"RECOVER STUB";status=g.memo_stub_found?.Complete:.Available}
	if entity.source_id=="burned_note" {action=g.burned_note_found?"FRAGMENT RECOVERED":"SEARCH ASH";status=g.burned_note_found?.Complete:.Available}
	if entity.source_id=="pond_reflection" do action="CONTEMPLATE"
	if entity.source_id=="shutter_crank" {
		moving:=math.abs(g.shutter_target-g.shutter_position)>.01
		action=moving?(g.shutter_target>.5?"CRANKING SHUTTER OPEN":"CRANKING SHUTTER CLOSED"):(g.shutter_target>=.5?"CRANK SHUTTER CLOSED":"CRANK SHUTTER OPEN")
		status=.Available
	}
	priority:=entity.source_id=="shutter_thread"?40:entity.kind=="person"?24:20
	return {valid=true,kind=.Story_Entity,status=status,stable_id=entity.source_id,label=entity.name,action=action,world=position,source_index=index,runtime_index=-1,priority=priority,distance=distance,reachable=world_interaction_reachable(g,index)}
}

context_transition_target :: proc(g:^Game,index:int)->Context_Target {
	if index<0||index>=len(level_document.markers) do return {}
	marker:=level_document.markers[index];if marker.kind!=.Transition||marker.story!=level_document.active_story do return {}
	dx,dy:=marker.position.x-g.player_x,marker.position.y-g.player_y;distance:=f32(math.sqrt(f64(dx*dx+dy*dy)));reachable:=distance<=marker.radius&&world_line_clear(g.player_x,g.player_y,marker.position.x,marker.position.y)
	label:=marker.destination=="city:vale_house"?"VALE CITY":"PASSAGE";action:=marker.destination=="city:vale_house"?"LEAVE HOUSE":"TRAVEL"
	return {valid=true,kind=.Transition,status=.Available,stable_id=marker.id,label=label,action=action,world=marker.position,source_index=index,runtime_index=-1,priority=35,distance=distance,reachable=reachable}
}

context_transition_at_cursor :: proc(g:^Game)->int {
	if g.input.mouse_pos.y>=590 do return -1;wx,wy,ok:=gameplay_mouse_ground(g,g.input.mouse_pos);if !ok do return -1
	best:=f32(.8);result:=-1;for marker,i in level_document.markers {if marker.kind!=.Transition||marker.story!=level_document.active_story do continue;dx,dy:=marker.position.x-wx,marker.position.y-wy;distance:=f32(math.sqrt(f64(dx*dx+dy*dy)));if distance<best {best=distance;result=i}}
	return result
}

context_target_facing :: proc(g:^Game,target:Context_Target)->f32 {dx,dy:=target.world.x-g.player_x,target.world.y-g.player_y;if target.distance<=.001 do return 1;return (f32(math.cos(f64(g.player_angle)))*dx+f32(math.sin(f64(g.player_angle)))*dy)/target.distance}
context_target_better :: proc(g:^Game,candidate,best:Context_Target,facing_only:bool)->bool {if !candidate.valid||!candidate.reachable do return false;if facing_only&&context_target_facing(g,candidate)<.2 do return false;if !best.valid do return true;candidate_facing:=context_target_facing(g,candidate);best_facing:=context_target_facing(g,best);if facing_only&&math.abs(candidate_facing-best_facing)>.12 do return candidate_facing>best_facing;if candidate.priority!=best.priority do return candidate.priority>best.priority;return candidate.distance<best.distance}

context_target_add :: proc(g:^Game,target:Context_Target) {
	if !target.valid||!target.reachable do return
	for &existing in g.context_ui.targets[:g.context_ui.target_count] {
		if existing.stable_id==target.stable_id {if context_target_better(g,target,existing,false) do existing=target;return}
	}
	if g.context_ui.target_count>=len(g.context_ui.targets) do return
	g.context_ui.targets[g.context_ui.target_count]=target;g.context_ui.target_count+=1
}

context_targets_sort :: proc(g:^Game) {
	for i in 1..<g.context_ui.target_count {candidate:=g.context_ui.targets[i];j:=i;for j>0&&context_target_better(g,candidate,g.context_ui.targets[j-1],false) {g.context_ui.targets[j]=g.context_ui.targets[j-1];j-=1};g.context_ui.targets[j]=candidate}
}

context_navigation_index :: proc(selected,count:int,up,down:bool)->int {
	if count<=1 do return selected
	if up do return (selected+count-1)%count
	if down do return (selected+1)%count
	return selected
}

context_resolve_house :: proc(g:^Game,apply_navigation:=true) {
	previous_id:=g.context_ui.current.stable_id;g.context_ui.target_count=0
	for _,i in g.interactives[:g.interactive_count] do context_target_add(g,context_runtime_target(g,i))
	for &entity,i in WORLD_ENTITIES {if entity_visible(g,&entity) do context_target_add(g,context_entity_target(g,i))}
	for _,i in level_document.markers do context_target_add(g,context_transition_target(g,i))
	context_targets_sort(g);g.context_ui.selected=0
	for target,i in g.context_ui.targets[:g.context_ui.target_count] do if target.stable_id==previous_id {g.context_ui.selected=i;break}
	if g.active_device==.Keyboard_Mouse {pointer,pointer_found:=context_pointer_target(g);if pointer_found&&pointer.reachable {for target,i in g.context_ui.targets[:g.context_ui.target_count] do if target.stable_id==pointer.stable_id {g.context_ui.selected=i;break}}}
	if apply_navigation do g.context_ui.selected=context_navigation_index(g.context_ui.selected,g.context_ui.target_count,g.input.up,g.input.down)
	next:=Context_Target{};if g.context_ui.target_count>0 do next=g.context_ui.targets[g.context_ui.selected]
	if !next.valid&&g.context_ui.current.valid&&g.animation_time-g.context_ui.last_valid_time<.18 do next=g.context_ui.current
	if next.valid {g.context_ui.last_valid_time=g.animation_time;if !g.context_ui.current.valid||g.context_ui.current.kind!=next.kind||g.context_ui.current.stable_id!=next.stable_id {g.context_ui.previous=g.context_ui.current;g.context_ui.focus_started=g.animation_time;play_sound(g,.Pick_Up)}}
	g.context_ui.current=next
}

context_feedback :: proc(g:^Game,message:string,status:Context_Status,id:string) {g.context_ui.feedback=message;g.context_ui.feedback_status=status;g.context_ui.feedback_id=id;g.context_ui.feedback_expires=g.animation_time+2.2}
context_activate_house :: proc(g:^Game,target:Context_Target)->bool {
	// UI focus is cached briefly to avoid flicker. Resolve it again here so a
	// cached target cannot bypass the current range or line-of-sight check.
	resolved:=target
	#partial switch resolved.kind {
	case .Runtime_Interactive: resolved=context_runtime_target(g,resolved.runtime_index)
	case .Story_Entity: resolved=context_entity_target(g,resolved.source_index)
	case .Transition: resolved=context_transition_target(g,resolved.source_index)
	case: return false
	}
	if !resolved.valid||!resolved.reachable do return false
	if resolved.kind==.Runtime_Interactive {ok:=runtime_interactive_activate(g,resolved.runtime_index);if ok&&g.screen==.Investigate {if g.interactives[resolved.runtime_index].behavior!=.Shutter do context_feedback(g,resolved.action,.Available,resolved.stable_id)}else if !ok {context_feedback(g,g.interaction_feedback,resolved.status,resolved.stable_id)};return ok}
	if resolved.kind==.Story_Entity {begin_world_interaction(g,resolved.source_index);return true}
	if resolved.kind==.Transition {marker:=level_document.markers[resolved.source_index];if strings.has_prefix(marker.destination,"city:") {if g.city_return_x!=0||g.city_return_y!=0 {g.city_x=g.city_return_x;g.city_y=g.city_return_y;g.city_angle=g.city_return_angle}else if !city_place_at_landmark(g,marker.destination[len("city:"):]) do return false;g.city_camera_initialized=false;g.screen=.Exterior;return true}}
	return false
}
context_pointer_target :: proc(g:^Game)->(Context_Target,bool) {
	best:Context_Target
	if g.hover_interactive>=0 {candidate:=context_runtime_target(g,g.hover_interactive);if context_target_better(g,candidate,best,false) do best=candidate}
	if g.hover_entity>=0 {candidate:=context_entity_target(g,g.hover_entity);if context_target_better(g,candidate,best,false) do best=candidate}
	transition:=context_transition_at_cursor(g);if transition>=0 {candidate:=context_transition_target(g,transition);if context_target_better(g,candidate,best,false) do best=candidate}
	return best,best.valid
}
doorway_object_obstructs :: proc(opening:Plan_Opening)->bool {
	middle:=Vec2{(opening.a.x+opening.b.x)*.5,(opening.a.y+opening.b.y)*.5};door_base:=house_player_ground_height(middle);door_top:=door_base+max(opening.height,f32(2.1))
	for item in house_plan.furniture {if point_segment_distance_sq(item.x,item.y,opening.a,opening.b)<(item.radius+.28)*(item.radius+.28)&&vertical_ranges_overlap(door_base,door_top,item.elevation,item.elevation+item.height) do return true}
	for object in level_document.objects {
		if object.story!=level_document.active_story||!catalog_object_blocks_movement(object) do continue
		radius,base,top:=catalog_object_collision_bounds(object)
		if point_segment_distance_sq(object.position.x,object.position.y,opening.a,opening.b)<(radius+.28)*(radius+.28)&&vertical_ranges_overlap(door_base,door_top,base,top) do return true
	}
	return false
}

runtime_doorway_obstructed :: proc(g:^Game,index:int)->bool {
	item:=&g.interactives[index];position,found:=runtime_interactive_position(g,index);if found {dx,dy:=position.x-g.player_x,position.y-g.player_y;if dx*dx+dy*dy<1.05*1.05 do return true}
	for opening in house_plan.openings do if opening.id==item.id do return doorway_object_obstructs(opening)
	return false
}

runtime_interactive_activate :: proc(g:^Game,index:int,automatic:=false) -> bool {if index<0||index>=g.interactive_count do return false;item:=&g.interactives[index];if item.locked {g.interaction_feedback="The door is locked.";play_sound(g,.Reject);return false};if !item.powered {g.interaction_feedback="There is no power.";play_sound(g,.Reject);return false};switch item.behavior {case .Door:if automatic||item.target<.5 {item.target=1;item.active=true;play_sound(g,.Door_Open)} else {if runtime_doorway_obstructed(g,index) {g.interaction_feedback="The doorway is obstructed.";play_sound(g,.Reject);return false};item.target=0;item.active=false;play_sound(g,.Door_Close)};case .Toggle:item.active=!item.active;item.target=item.active?1:0;play_sound(g,.Switch);case .Shutter:toggle_shutter_crank(g);g.interaction_feedback=g.shutter_feedback;context_feedback(g,g.shutter_target>=.5?"SHUTTER OPENING":"SHUTTER CLOSING",.Available,"shutter_crank");case .None:return false};return true}
runtime_interactives_update :: proc(g:^Game) {if g.interactive_count==0 do runtime_interactives_rebuild(g);for &item in g.interactives[:g.interactive_count] {item.openness=approach_scalar(item.openness,item.target,.055);item.light_level=approach_scalar(item.light_level,item.active?1:0,.08)}}
runtime_interactive_at_cursor :: proc(g:^Game)->int {if g.input.mouse_pos.y>=590 do return -1;wx,wy,ok:=gameplay_mouse_ground(g,g.input.mouse_pos);if !ok do return -1;best:=f32(1.0);result:=-1;for _,i in g.interactives[:g.interactive_count] {position,found:=runtime_interactive_position(g,i);if !found do continue;dx,dy:=position.x-wx,position.y-wy;distance:=f32(math.sqrt(f64(dx*dx+dy*dy)));if distance<best {best=distance;result=i}};return result}
runtime_near_interactive :: proc(g:^Game)->int {best:=f32(1e9);result:=-1;for item,i in g.interactives[:g.interactive_count] {position,found:=runtime_interactive_position(g,i);if !found do continue;range:=f32(1.8);for opening in level_document.openings do if opening.id==item.id do range=opening.interaction_range;for object in level_document.objects do if object.id==item.id do range=object.interaction_range;dx,dy:=position.x-g.player_x,position.y-g.player_y;distance_sq:=dx*dx+dy*dy;if distance_sq<=range*range&&distance_sq<best&&world_interaction_line_clear(g,g.player_x,g.player_y,position.x,position.y,item.id) {best=distance_sq;result=i}};return result}
world_wall :: proc(x,y:f32)->bool {
	max_x,max_y:=f32(level_document.width)-.18,f32(level_document.height)-.18;if x<.18||x>max_x||y<.18||y>max_y do return true
	for opening in house_plan.openings do if opening.kind==.Door&&house_opening_contains(opening,x,y) {return false}
	if len(house_plan.wall_splines)>0 {for spline in house_plan.wall_splines {radius:=house_wall_width(spline.width)*.5;for i in 0..<len(spline.points)-1 do if point_segment_distance_sq(x,y,spline.points[i],spline.points[i+1])<radius*radius do return true}} else {for spline in HOUSE_WALL_SPLINES {radius:=house_wall_width(spline.width)*.5;for i in 0..<len(spline.points)-1 do if point_segment_distance_sq(x,y,spline.points[i],spline.points[i+1])<radius*radius do return true}}
	return false
}

world_closed_door_blocked :: proc(g:^Game,x,y:f32)->bool {for opening in house_plan.openings {if opening.kind!=.Door||runtime_door_opening(g,opening)>=.75 do continue;if house_opening_contains(opening,x,y) do return true};return false}
world_closed_door_blocked_except :: proc(g:^Game,x,y:f32,except_id:string)->bool {for opening in house_plan.openings {if opening.id==except_id||opening.kind!=.Door||runtime_door_opening(g,opening)>=.75 do continue;if house_opening_contains(opening,x,y) do return true};return false}

house_player_blocked :: proc(g:^Game,x,y:f32)->bool {
	// Manual movement needs the same body clearance as the navmesh. Testing only
	// the character origin lets the visible mesh enter a wall when backing up.
	clearance:=[5]Vec2{{0,0},{.24,0},{-.24,0},{0,.24},{0,-.24}}
	for offset in clearance {px,py:=x+offset.x,y+offset.y;if world_wall(px,py)||world_closed_door_blocked(g,px,py)||furniture_blocked(px,py)||water_blocked(px,py) do return true}
	// A capsule may climb a curb or low platform, but a taller discontinuity is
	// a ledge. Compare against the support beneath the current body rather than
	// the render offset, which can still be catching up during a step animation.
	current_height:=house_player_ground_height({g.player_x,g.player_y})
	if !house_step_height_allowed(current_height,house_player_ground_height({x,y})) do return true
	return false
}

house_step_height_allowed :: proc(current,target:f32)->bool {return target-current<=HOUSE_PLAYER_MAX_STEP_HEIGHT}

house_player_ground_height :: proc(position:Vec2)->f32 {
	story:=level_document.active_story
	for room in level_document.rooms do if room.story==story&&level_point_in_polygon(position,room.points[:]) do return room.platform_height
	if level_terrain_supports_position(&level_document,position,story) do return level_terrain_height(&level_document,position)
	return 0
}

house_update_player_elevation :: proc(g:^Game) {
	target:=house_player_ground_height({g.player_x,g.player_y})
	delta:=target-g.player_elevation
	if math.abs(delta)<=HOUSE_PLAYER_STEP_SPEED {g.player_elevation=target;return}
	g.player_elevation+=delta>0?HOUSE_PLAYER_STEP_SPEED:-HOUSE_PLAYER_STEP_SPEED
}
world_line_clear :: proc(x0,y0,x1,y1:f32)->bool {dx:=x1-x0;dy:=y1-y0;distance:=math.sqrt(dx*dx+dy*dy);if distance<=0.05 do return true;steps:=int(math.ceil(distance/0.05));for step in 1..<steps {t:=f32(step)/f32(steps);if world_wall(x0+dx*t,y0+dy*t) do return false};return true}
world_interaction_line_clear :: proc(g:^Game,x0,y0,x1,y1:f32,except_id:string)->bool {dx:=x1-x0;dy:=y1-y0;distance:=math.sqrt(dx*dx+dy*dy);if distance<=.05 do return true;steps:=int(math.ceil(distance/.05));for step in 1..<steps {t:=f32(step)/f32(steps);x,y:=x0+dx*t,y0+dy*t;if world_wall(x,y)||world_closed_door_blocked_except(g,x,y,except_id) do return false};return true}

runtime_door_on_active_path :: proc(g:^Game)->int {
	if !g.move_target_active||g.nav_path_index<0||g.nav_path_index>=g.nav_path_count do return -1
	segment_start:=Vec2{g.player_x,g.player_y}
	for path_index in g.nav_path_index..<g.nav_path_count {
		segment_end:=g.nav_path[path_index]
		for item,i in g.interactives[:g.interactive_count] {
			if item.behavior!=.Door||item.locked||item.target>=.5||i==g.pending_interactive do continue
			for opening in house_plan.openings {
				if opening.id!=item.id do continue
				center:=Vec2{(opening.a.x+opening.b.x)*.5,(opening.a.y+opening.b.y)*.5};door_dx,door_dy:=opening.b.x-opening.a.x,opening.b.y-opening.a.y;path_dx,path_dy:=segment_end.x-segment_start.x,segment_end.y-segment_start.y
				// The route must cross the doorway's host line and pass through the
				// authored aperture, not merely pass near its center.
				side_a:=door_dx*(segment_start.y-opening.a.y)-door_dy*(segment_start.x-opening.a.x);side_b:=door_dx*(segment_end.y-opening.a.y)-door_dy*(segment_end.x-opening.a.x)
				if side_a*side_b>0 do continue
				path_length_sq:=path_dx*path_dx+path_dy*path_dy;if path_length_sq<=.0001 do continue;t:=clamp(((center.x-segment_start.x)*path_dx+(center.y-segment_start.y)*path_dy)/path_length_sq,0,1);closest:=Vec2{segment_start.x+path_dx*t,segment_start.y+path_dy*t};cx,cy:=closest.x-center.x,closest.y-center.y;aperture_dx,aperture_dy:=opening.b.x-opening.a.x,opening.b.y-opening.a.y;aperture_length:=f32(math.sqrt(f64(aperture_dx*aperture_dx+aperture_dy*aperture_dy)))
				if cx*cx+cy*cy<=(aperture_length*.5+.3)*(aperture_length*.5+.3) do return i
			}
		}
		segment_start=segment_end
	}
	return -1
}

world_interaction_reachable :: proc(g:^Game,index:int)->bool {
	if index<0||index>=len(WORLD_ENTITIES) do return false
	entity:=WORLD_ENTITIES[index];position:=Vec2{entity.x,entity.y};if entity.source_id=="shutter_crank" {anchor,found:=shutter_crank_world_position();if found do position=anchor};dx,dy:=position.x-g.player_x,position.y-g.player_y
	return dx*dx+dy*dy<=1.8*1.8&&world_interaction_line_clear(g,g.player_x,g.player_y,position.x,position.y,entity.source_id)
}

aerial_camera_pose :: proc(g:^Game,focus_x,focus_y,story_y:f32)->(eye,target,up:Vec3) {
	up={0,1,0};target={focus_x,story_y,focus_y}
	if g.camera_pose_override {
		dx,dz:=g.camera_target_override.x-g.camera_eye_override.x,g.camera_target_override.z-g.camera_eye_override.z
		if dx*dx+dz*dz<.0001 do up={0,0,-1}
		return g.camera_eye_override,g.camera_target_override,up
	}
	zoom:=g.camera_orbit_initialized?g.camera_zoom:f32(1)
	if g.top_down_camera {return {focus_x,story_y+27.5*zoom,focus_y},target,{0,0,-1}}
	side:=g.camera_reverse?f32(-1):f32(1);orbit:=g.camera_orbit_initialized?g.camera_orbit:f32(math.PI/4);distance,height:=gameplay_camera_boom(g)
	return {focus_x+f32(math.cos(f64(orbit)))*distance*side,story_y+height,focus_y+f32(math.sin(f64(orbit)))*distance*side},target,up
}

camera_story_y :: proc(g:^Game)->f32 {
	if g.editor_mode==.Build&&level_document.active_story>=0&&level_document.active_story<len(level_document.stories) do return level_document.stories[level_document.active_story].base_elevation
	return 0
}

camera_world_point_screen :: proc(eye,target,up,point:Vec3)->(screen:Vec2,visible:bool) {
	forward:=vk_world_normalize(Vec3{target.x-eye.x,target.y-eye.y,target.z-eye.z});right:=vk_world_normalize(Vec3{forward.y*up.z-forward.z*up.y,forward.z*up.x-forward.x*up.z,forward.x*up.y-forward.y*up.x});camera_up:=Vec3{right.y*forward.z-right.z*forward.y,right.z*forward.x-right.x*forward.z,right.x*forward.y-right.y*forward.x};to:=Vec3{point.x-eye.x,point.y-eye.y,point.z-eye.z};depth:=to.x*forward.x+to.y*forward.y+to.z*forward.z;if depth<=.01 do return {},false
	half:=f32(math.tan(f64(math.PI/6)));aspect:=f32(WINDOW_WIDTH)/f32(WINDOW_HEIGHT);ndc_x:=(to.x*right.x+to.y*right.y+to.z*right.z)/(depth*half*aspect);ndc_y:=(to.x*camera_up.x+to.y*camera_up.y+to.z*camera_up.z)/(depth*half)
	return {(ndc_x+1)*.5*f32(WINDOW_WIDTH),(1-ndc_y)*.5*f32(WINDOW_HEIGHT)},ndc_x>=-1&&ndc_x<=1&&ndc_y>=-1&&ndc_y<=1
}

aerial_world_point_screen :: proc(g:^Game,point:Vec2)->(screen:Vec2,visible:bool) {
	story_y:=camera_story_y(g);eye,target,up:=aerial_camera_pose(g,g.camera_x,g.camera_y,story_y)
	return camera_world_point_screen(eye,target,up,{point.x,story_y,point.y})
}

gameplay_mouse_ground :: proc(g:^Game,mouse:Vec2)->(x,y:f32,ok:bool) {
	story_y:=camera_story_y(g);eye,target,up:=aerial_camera_pose(g,g.camera_x,g.camera_y,story_y)
	forward:=vk_world_normalize(Vec3{target.x-eye.x,target.y-eye.y,target.z-eye.z});right:=vk_world_normalize(Vec3{forward.y*up.z-forward.z*up.y,forward.z*up.x-forward.x*up.z,forward.x*up.y-forward.y*up.x});camera_up:=Vec3{right.y*forward.z-right.z*forward.y,right.z*forward.x-right.x*forward.z,right.x*forward.y-right.y*forward.x}
	nx:=mouse.x/f32(WINDOW_WIDTH)*2-1;ny:=1-mouse.y/f32(WINDOW_HEIGHT)*2;half:=f32(math.tan(f64(math.PI/6)));aspect:=f32(WINDOW_WIDTH)/f32(WINDOW_HEIGHT);direction:=vk_world_normalize(Vec3{forward.x+right.x*nx*half*aspect+camera_up.x*ny*half,forward.y+right.y*nx*half*aspect+camera_up.y*ny*half,forward.z+right.z*nx*half*aspect+camera_up.z*ny*half})
	if direction.y>=-.001 do return 0,0,false
	t:=(story_y-eye.y)/direction.y;return eye.x+direction.x*t,eye.z+direction.z*t,true
}

context_world_position_screen :: proc(g:^Game,point:Vec3)->(screen:Vec2,visible:bool) {
	eye,target,up:=Vec3{},Vec3{},Vec3{0,1,0}
	if g.screen==.Exterior&&g.driving_vehicle>=0 {eye={g.city_x,1.15,g.city_y};target={g.city_x+f32(math.cos(f64(g.city_angle))),1.15,g.city_y+f32(math.sin(f64(g.city_angle)))}}
	else if g.screen==.Investigate&&g.first_person_camera {pitch_scale:=f32(math.cos(f64(g.first_person_pitch)));eye={g.player_x,1.15,g.player_y};target={g.player_x+f32(math.cos(f64(g.player_angle)))*pitch_scale,1.15+f32(math.sin(f64(g.first_person_pitch))),g.player_y+f32(math.sin(f64(g.player_angle)))*pitch_scale}}
	else {focus_x,focus_y:=g.screen==.Exterior?g.city_camera_x:g.camera_x,g.screen==.Exterior?g.city_camera_y:g.camera_y;eye,target,up=aerial_camera_pose(g,focus_x,focus_y,0)}
	return camera_world_point_screen(eye,target,up,point)
}

context_world_point_screen :: proc(g:^Game,point:Vec2)->(screen:Vec2,visible:bool) {
	return context_world_position_screen(g,{point.x,0,point.y})
}

world_entity_at_cursor :: proc(g:^Game)->int {
	if g.input.mouse_pos.y>=590 do return -1
	wx,wy,valid:=gameplay_mouse_ground(g,g.input.mouse_pos);if !valid do return -1
	best:f32=1.15;result:=-1
	for &entity,i in WORLD_ENTITIES {if !entity_visible(g,&entity) do continue;ex,ey:=wx-entity.x,wy-entity.y;distance:=math.sqrt(ex*ex+ey*ey);if distance<best {best=distance;result=i}}
	return result
}

approach_scalar :: proc(value,target,amount:f32)->f32 {if value<target do return min(value+amount,target);return max(value-amount,target)}
turn_toward :: proc(current,target,amount:f32)->f32 {delta:=target-current;for delta>math.PI do delta-=2*math.PI;for delta< -math.PI do delta+=2*math.PI;return current+clamp(delta,-amount,amount)}
update_aerial_camera :: proc(g:^Game) {
	if !g.camera_initialized {g.camera_x=g.player_x;g.camera_y=g.player_y;g.camera_initialized=true}
	if !g.camera_orbit_initialized {g.camera_orbit=math.PI/4;g.camera_zoom=1;g.camera_orbit_initialized=true}
	if !g.first_person_camera {g.camera_orbit+=g.pad_right_x*.035;if g.camera_orbit>math.PI do g.camera_orbit-=2*math.PI;if g.camera_orbit< -math.PI do g.camera_orbit+=2*math.PI;minimum_zoom:=g.editor_mode==.Build?EDITOR_CAMERA_MIN_ZOOM:f32(.55);g.camera_zoom=clamp(g.camera_zoom+g.pad_right_y*.025-g.input.mouse_wheel*.1,minimum_zoom,1.65)}
	// A small velocity lead keeps the protagonist in the playable lower-middle
	// frame without the harsh, perfectly locked camera of the earlier version.
	desired_x:=g.player_x+g.player_velocity_x*2.8;desired_y:=g.player_y+g.player_velocity_y*2.8
	g.camera_x+=(desired_x-g.camera_x)*.105;g.camera_y+=(desired_y-g.camera_y)*.105
}

// A locked, character-centered spring arm. Pulling back raises the camera into a
// tactical view; pushing in lowers it toward a closer third-person composition.
// Build mode keeps its original uniform scale and cursor-anchored zoom behavior.
gameplay_camera_boom :: proc(g:^Game)->(distance,height:f32) {
	zoom:=g.camera_orbit_initialized?g.camera_zoom:f32(1)
	if g.editor_mode==.Build {return 11.314*zoom,10*zoom}
	t:=clamp((zoom-.55)/1.10,0,1)
	return 6.2+(18.7-6.2)*t,4+(16.5-4)*t
}

begin_world_interaction :: proc(g:^Game,index:int) {
	if index<0||index>=len(WORLD_ENTITIES) do return;entity:=WORLD_ENTITIES[index]
	tutorial_complete(g,.Contextual_Interaction);if entity.kind=="person" do tutorial_complete(g,.Converse)
	if entity.source_id=="body" {
		if !g.desk_key_found {g.dialogue_entity=index;_=dialogue_start_scene(g,story_scene_index(g.story_project,"scene_recover_desk_key"))} else do _=open_evidence_dialogue(g,index)
	} else if entity.source_id=="study_desk" {
		if g.desk_open {context_feedback(g,"DESK ALREADY OPEN",.Complete,"study_desk");return}
		_=dialogue_start_source_scene(g,"study_desk")
	} else if entity.source_id=="memo_stub"||entity.source_id=="burned_note" {
		already_found:=entity.source_id=="memo_stub"?g.memo_stub_found:g.burned_note_found
		if !already_found do _=dialogue_start_source_scene(g,entity.source_id);else do appointment_fragment_recover(g,entity.source_id)
	} else if entity.source_id=="shutter_crank" {
		toggle_shutter_crank(g);g.interaction_feedback=g.shutter_feedback;context_feedback(g,g.shutter_target>=.5?"SHUTTER OPENING":"SHUTTER CLOSING",.Available,"shutter_crank")
	} else if entity.source_id=="shutter_thread" {
		_=open_evidence_dialogue(g,index)
	} else if entity.source_id=="study_rug" {
		lift_study_rug(g)
	} else if entity.source_id=="statuette" {
		_=dialogue_start_source_scene(g,"statuette")
	} else if entity.source_id=="cloth" {
		_=dialogue_start_source_scene(g,"cloth")
	} else if entity.source_id=="dining_room"||entity.source_id=="edgar_watch"||entity.source_id=="pond_reflection" {
		_=open_evidence_dialogue(g,index)
	} else {
		g.dialogue_entity=index
		if entity.kind=="person"&&dialogue_start_character_introduction(g,entity.source_id) do return
		g.dialogue_node=0;g.dialogue_ledger_scroll=0;g.dialogue_choice_page=0;g.dialogue_response="";if entity.kind=="person"&&!officer_source(entity.source_id) do conversation_transcript_append(g,entity.source_id,character_reentry_line(g,entity.source_id),"dialogue",entity.source_id);g.dialogue_text_started=g.animation_time;g.pending_dialogue_approach=0
		if entity.kind=="person" do trigger_character_interact(g,entity.source_id)
		g.screen=.Dialogue;dialogue_focus_default(g)
	}
}

appointment_fragment_recover :: proc(g:^Game,source_id:string) {
	if source_id=="memo_stub" {
		if g.memo_stub_found {context_feedback(g,"MEMO STUB ALREADY RECOVERED",.Complete,source_id);return}
		g.memo_stub_found=true;clue:=clue_for_source(g,"memo_stub");if clue>=0 do spend(g,clue)
		g.interaction_feedback="The stub in Edgar's memo pad reads: 'Miriam—study, 8:20—'. Its irregular lower edge was torn away.";context_feedback(g,"EDGAR'S 8:20 MEMO STUB RECOVERED",.Complete,source_id)
	} else if source_id=="burned_note" {
		if g.burned_note_found {context_feedback(g,"BURNED FRAGMENT ALREADY RECOVERED",.Complete,source_id);return}
		g.burned_note_found=true;g.interaction_feedback="One fragment survived in Miriam's metal wastebin: '—bring the account books. We settle this tonight. —E.'";context_feedback(g,"BURNED NOTE FRAGMENT RECOVERED",.Complete,source_id)
	} else do return
	if g.memo_stub_found&&g.burned_note_found&&!g.appointment_note_joined {
		g.appointment_note_joined=true;clue:=clue_for_source(g,"burned_note");if clue>=0 do spend(g,clue)
		g.interaction_feedback="Both note fragments are recovered: Edgar's memo stub and the burned fragment from Miriam's wastebin. Compare their torn edges on the evidence board.";log_line(g,g.interaction_feedback);context_feedback(g,"NOTE FRAGMENTS READY TO COMPARE",.Complete,"burned_note");play_sound(g,.Decisive_Clue)
	}
}

acquire_desk_key :: proc(g:^Game) {
	if g.desk_key_found do return
	g.desk_key_found=true;g.dialogue_response="A small brass key rests in Edgar's waistcoat pocket, worn bright at the teeth.";g.dialogue_text_started=g.animation_time;log_line(g,g.dialogue_response);context_feedback(g,"BRASS KEY ACQUIRED",.Complete,"body");play_sound(g,.Pick_Up)
}

house_room_at_point :: proc(point:Vec2)->int {
	story:=max(level_document.active_story,0);for room,i in level_document.rooms do if room.story==story&&!room.exterior&&level_point_in_polygon(point,room.points[:]) do return i
	return -1
}

house_outdoor_exposure_at_point :: proc(point:Vec2)->f32 {
	story:=max(level_document.active_story,0)
	for room in level_document.rooms {
		if room.story==story&&level_point_in_polygon(point,room.points[:]) do return room.exterior?f32(1):f32(0)
	}
	// Positions outside an authored room footprint are open terrain.
	return 1
}

house_wall_camera_position :: proc(g:^Game)->Vec2 {
	if g.first_person_camera do return {g.player_x,g.player_y}
	if g.camera_pose_override do return {g.camera_eye_override.x,g.camera_eye_override.z}
	camera_side:=g.camera_reverse?f32(-1):f32(1);orbit:=g.camera_orbit_initialized?g.camera_orbit:f32(math.PI/4)
	distance,_:=gameplay_camera_boom(g)
	return {g.camera_x+f32(math.cos(f64(orbit)))*distance*camera_side,g.camera_y+f32(math.sin(f64(orbit)))*distance*camera_side}
}

house_wall_sightline_crosses_window :: proc(wall:^Floorplan_Wall,from,to:Vec2)->bool {
	wdx,wdz:=wall.b.x-wall.a.x,wall.b.y-wall.a.y;sdx,sdz:=to.x-from.x,to.y-from.y
	denominator:=sdx*wdz-sdz*wdx;if math.abs(denominator)<.0001 do return false
	t:=((wall.a.x-from.x)*wdz-(wall.a.y-from.y)*wdx)/denominator
	u:=((wall.a.x-from.x)*sdz-(wall.a.y-from.y)*sdx)/denominator
	if t<0||t>1||u<0||u>1 do return false
	crossing:=Vec2{from.x+sdx*t,from.y+sdz*t}
	for opening in house_plan.openings {
		if opening.kind!=.Window do continue
		odx,odz:=opening.b.x-opening.a.x,opening.b.y-opening.a.y;opening_length_sq:=odx*odx+odz*odz
		if opening_length_sq<.0001 do continue
		parallel:=math.abs(odx*wdz-odz*wdx);if parallel>.01*f32(math.sqrt(f64(opening_length_sq*(wdx*wdx+wdz*wdz)))) do continue
		if point_segment_distance_sq((opening.a.x+opening.b.x)*.5,(opening.a.y+opening.b.y)*.5,wall.a,wall.b)>.08*.08 do continue
		if point_segment_distance_sq(crossing.x,crossing.y,opening.a,opening.b)<=.01*.01 do return true
	}
	return false
}

house_wall_cutaway_target :: proc(g:^Game,wall:^Floorplan_Wall)->f32 {
	if g.editor_mode==.Build {if g.top_down_camera||editor_state.view==.Cutaway do return 1;return 0}
	if g.wall_view==.Walls_Up||g.first_person_camera do return 0
	if g.wall_view==.Walls_Down do return 1
	player_room:=house_room_at_point({g.player_x,g.player_y});if player_room<0 do return 0
	dx,dz:=wall.b.x-wall.a.x,wall.b.y-wall.a.y;length:=f32(math.sqrt(f64(dx*dx+dz*dz)));if length<.001 do return 0
	mx,mz:=(wall.a.x+wall.b.x)*.5,(wall.a.y+wall.b.y)*.5;nx,nz:= -dz/length,dx/length
	positive_room:=house_room_at_point({mx+nx*.24,mz+nz*.24});negative_room:=house_room_at_point({mx-nx*.24,mz-nz*.24})
	if positive_room!=player_room&&negative_room!=player_room do return 0
	// Use the room classification, rather than the player's instantaneous wall
	// side, as the stable interior half-plane. At door thresholds and near wall
	// ends the player can sit on the centerline (or briefly cross it while the
	// camera eases), which used to leave one leg of a foreground corner raised.
	camera:=house_wall_camera_position(g);camera_side:=dx*(camera.y-wall.a.y)-dz*(camera.x-wall.a.x)
	active_side:=positive_room==player_room?f32(1):f32(-1)
	if camera_side*active_side>=0 do return 0
	// Glazing does not occlude the view. Keep the host wall raised when the
	// camera-to-player sightline passes through one of its window apertures.
	if house_wall_sightline_crosses_window(wall,{g.player_x,g.player_y},camera) do return 0
	return 1
}

house_update_wall_cutaways :: proc(g:^Game) {
	for &wall,i in house_walls {if i>=HOUSE_WALL_SECTION_CAPACITY do break;target:=house_wall_cutaway_target(g,&wall);g.wall_cutaways[i]=approach_scalar(g.wall_cutaways[i],target,.09)}
}
update_world :: proc(g:^Game){
	runtime_interactives_update(g)
	if g.input.camera_toggle do g.first_person_camera=!g.first_person_camera
	if g.input.wall_view_cycle do g.wall_view=House_Wall_View((int(g.wall_view)+1)%len(House_Wall_View))
	previous_location:=world_location_index(g)
	target_environment:=house_outdoor_exposure_at_point({g.player_x,g.player_y});g.environment_blend=approach_scalar(g.environment_blend,target_environment,.065);g.cutaway_transition=approach_scalar(g.cutaway_transition,1-target_environment,.065)
	turn:f32=0;if g.keys[.LEFT] do turn-=1;if g.keys[.RIGHT] do turn+=1;if g.first_person_camera {turn+=g.pad_right_x;g.first_person_pitch=clamp(g.first_person_pitch-g.pad_right_y*.035,-.45,.45)};g.player_angle+=turn*.045
	stick:=house_radial_input({g.pad_left_x,-g.pad_left_y});forward,strafe:=stick.y,stick.x;if g.keys[.W]||g.keys[.UP] do forward+=1;if g.keys[.S]||g.keys[.DOWN] do forward-=1;if g.keys[.A] do strafe-=1;if g.keys[.D] do strafe+=1
	manual:=math.abs(forward)+math.abs(strafe)>.05;if manual {g.move_target_active=false;g.pending_world_interaction=-1;g.pending_interactive=-1}
	g.hover_entity=world_entity_at_cursor(g)
	g.hover_interactive=runtime_interactive_at_cursor(g);if g.hover_interactive>=0 do g.hover_entity=-1
	// Populate targets for click-to-walk without consuming the D-pad edge. The
	// final resolve below applies navigation once after movement/proximity updates.
	context_resolve_house(g,false)
	if g.input.mouse_pressed&&g.input.mouse_pos.y<590 {wx,wy,valid:=gameplay_mouse_ground(g,g.input.mouse_pos);target,pointer_target:=context_pointer_target(g);if pointer_target&&target.kind==.Transition&&target.reachable {_=context_activate_house(g,target);return};if pointer_target {wx,wy=target.world.x,target.world.y;valid=true;g.pending_world_interaction=target.kind==.Story_Entity?target.source_index:-1;g.pending_interactive=target.kind==.Runtime_Interactive?target.runtime_index:-1}else{g.pending_world_interaction=-1;g.pending_interactive=-1};if valid {g.move_target_x=wx;g.move_target_y=wy;g.move_target_active=nav_build_path(g,{g.player_x,g.player_y},{wx,wy})}}
	desired_x,desired_y:=f32(0),f32(0);moving:=false
	if manual {length:=f32(math.sqrt(f64(forward*forward+strafe*strafe)));if length>.001 {magnitude:=min(length,f32(1));forward/=length;strafe/=length;if g.first_person_camera {view_x:=f32(math.cos(f64(g.player_angle)));view_y:=f32(math.sin(f64(g.player_angle)));desired_x=(forward*view_x-strafe*view_y)*HOUSE_MANUAL_MOVE_SPEED*magnitude;desired_y=(forward*view_y+strafe*view_x)*HOUSE_MANUAL_MOVE_SPEED*magnitude}else{view_x:=-f32(math.cos(f64(g.camera_orbit)));view_y:=-f32(math.sin(f64(g.camera_orbit)));desired_x=(forward*view_x-strafe*view_y)*HOUSE_MANUAL_MOVE_SPEED*magnitude;desired_y=(forward*view_y+strafe*view_x)*HOUSE_MANUAL_MOVE_SPEED*magnitude};moving=true}}
	if g.move_target_active {door:=runtime_door_on_active_path(g);if door>=0 {position,found:=runtime_interactive_position(g,door);if found {ex,ey:=position.x-g.player_x,position.y-g.player_y;if ex*ex+ey*ey<1.15*1.15 {_=runtime_interactive_activate(g,door,true);g.auto_door=door}}}}
	if g.move_target_active {waypoint:=g.nav_path[g.nav_path_index];tx,ty:=waypoint.x-g.player_x,waypoint.y-g.player_y;distance:=math.sqrt(tx*tx+ty*ty);stop_distance:f32=.14;if (g.pending_world_interaction>=0||g.pending_interactive>=0)&&g.nav_path_index==g.nav_path_count-1 do stop_distance=1.25;if distance<=stop_distance {g.nav_path_index+=1;if g.nav_path_index>=g.nav_path_count {g.move_target_active=false;if g.pending_interactive>=0 {index:=g.pending_interactive;g.pending_interactive=-1;_=runtime_interactive_activate(g,index)} else if g.pending_world_interaction>=0 {index:=g.pending_world_interaction;g.pending_world_interaction=-1;if world_interaction_reachable(g,index) do begin_world_interaction(g,index)}}} else {speed:=min(HOUSE_PATH_MOVE_MAX_SPEED,max(HOUSE_PATH_MOVE_MIN_SPEED,distance*.06));desired_x=tx/distance*speed;desired_y=ty/distance*speed;moving=true}}
	if moving&&!g.first_person_camera {desired_speed:=f32(math.sqrt(f64(desired_x*desired_x+desired_y*desired_y)));turn_rate:=.10+.16*clamp(desired_speed/HOUSE_MANUAL_MOVE_SPEED,0,1);g.player_angle=turn_toward(g.player_angle,f32(math.atan2(f64(desired_y),f64(desired_x))),turn_rate)}
	velocity:=house_approach_velocity({g.player_velocity_x,g.player_velocity_y},{desired_x,desired_y},moving);g.player_velocity_x,g.player_velocity_y=velocity.x,velocity.y
	// Preserve momentum but steer around a nearby furnishing instead of letting
	// click navigation repeatedly ram the same collision circle.
	dx,dy:=g.player_velocity_x,g.player_velocity_y;if g.move_target_active&&house_player_blocked(g,g.player_x+dx,g.player_y+dy) {angle:f32=.58;c,s:=f32(math.cos(f64(angle))),f32(math.sin(f64(angle)));sx,sy:=dx*c-dy*s,dx*s+dy*c;if house_player_blocked(g,g.player_x+sx,g.player_y+sy) {angle=-.58;c,s=f32(math.cos(f64(angle))),f32(math.sin(f64(angle)));sx,sy=dx*c-dy*s,dx*s+dy*c};if !house_player_blocked(g,g.player_x+sx,g.player_y+sy) {dx,dy=sx,sy;g.player_velocity_x,g.player_velocity_y=dx,dy}};if !house_player_blocked(g,g.player_x+dx,g.player_y) {g.player_x+=dx}else{g.player_velocity_x=0};if !house_player_blocked(g,g.player_x,g.player_y+dy) {g.player_y+=dy}else{g.player_velocity_y=0};house_update_player_elevation(g);speed:=f32(math.sqrt(f64(g.player_velocity_x*g.player_velocity_x+g.player_velocity_y*g.player_velocity_y)));g.player_walk_speed=speed;g.player_is_walking=speed>.006;update_aerial_camera(g);house_update_wall_cutaways(g)
	g.near_entity=-1;best:f32=1.7;for &e,i in WORLD_ENTITIES {if !entity_visible(g,&e) do continue;ex:=e.x-g.player_x;ey:=e.y-g.player_y;d:=math.sqrt(ex*ex+ey*ey);if d<best&&math.cos(g.player_angle)*ex+math.sin(g.player_angle)*ey>0&&world_interaction_line_clear(g,g.player_x,g.player_y,e.x,e.y,e.source_id) {best=d;g.near_entity=i}}
	g.near_interactive=runtime_near_interactive(g);if g.near_interactive>=0 do g.near_entity=-1
	for marker in level_document.markers {if marker.kind!=.Interaction||marker.story!=level_document.active_story do continue;dx,dy:=marker.position.x-g.player_x,marker.position.y-g.player_y;if dx*dx+dy*dy>marker.radius*marker.radius||!world_line_clear(g.player_x,g.player_y,marker.position.x,marker.position.y) do continue;for &entity,i in WORLD_ENTITIES do if entity.source_id==marker.reference&&world_interaction_reachable(g,i) {g.near_entity=i;break}}
	location:=world_location_index(g);if location!=previous_location {if location>=0 do _=reveal_location_pois(g,location);g.context_ui.location_index=location;g.context_ui.location_changed_at=g.animation_time};_=reveal_service_closet(g)
	if g.case_sense_level!=0&&g.animation_time>=g.case_sense_hint_until do g.case_sense_level=0
	case_sense_clicked:=button(g,{20,88,410,26})
	if case_sense_clicked {
		if g.case_sense_level==0 {g.case_sense_level=1;g.case_sense_hint_until=g.animation_time+5}else do g.case_sense_level=0;tutorial_complete(g,.Case_Sense)
	}
	if g.input.case_sense {
		if g.case_sense_level==0 {g.case_sense_level=1;g.case_sense_hint_until=g.animation_time+5}else do g.case_sense_level=0;tutorial_complete(g,.Case_Sense)
	}
	context_resolve_house(g)
	if g.context_ui.feedback!=""&&g.animation_time>=g.context_ui.feedback_expires {g.context_ui.feedback="";g.interaction_feedback=""}
	if g.input.activate do _=context_activate_house(g,g.context_ui.current)
}
begin_dialogue_approach_check :: proc(g:^Game,node_index:int){payload:=mystery_game_payload(g);node:=mystery_dialogue_approach_at(payload,node_index);if node==nil do return;clue_index:=mystery_clue_index(payload,node.clue_id);if clue_index>=0 {g.pending_dialogue_approach=node_index+1;g.pending_clue=clue_index;g.check_preview=check_target(payload.clues[clue_index].difficulty);g.check_done=false;g.check_disposition_delta=0;g.check_from_dialogue=true;dialogue_focus_default(g)}}
dialogue_approach_rect :: proc(g:^Game,index:int,y:f32)->Rect {
	node:=mystery_dialogue_approach_at(mystery_game_payload(g),index);if node==nil do return {650,y,490,38};spoken:=dialogue_semantic_text(node.prompt,"choice");lines:=wrapped_line_count(spoken,426,.9)
	return {650,y,490,node.clue_id!=""?max(f32(58),31+f32(lines)*19):max(f32(40),12+f32(lines)*19)}
}
dialogue_object_check_rect :: proc(g:^Game,clue_index:int)->Rect {
	payload:=mystery_game_payload(g);if payload==nil||clue_index<0||clue_index>=len(payload.clues) do return {650,420,490,58}
	lines:=wrapped_line_count(strings.to_upper(payload.clues[clue_index].description),426,.9)
	return {650,420,490,max(f32(58),31+f32(lines)*19)}
}
dialogue_transcript_layout_height :: proc(g:^Game,conversation_id:string)->f32 {
	indices:[256]int;count:=0
	for entry,i in g.conversation_transcript[:g.conversation_transcript_count] do if entry.conversation_id==conversation_id&&count<len(indices) {indices[count]=i;count+=1}
	if count==0 do return 0
	max_scroll:=max(0,count-1);scroll:=clamp(g.dialogue_ledger_scroll,0,max_scroll);end:=count-scroll;start:=end-1
	latest:=&g.conversation_transcript[indices[start]];latest_entity:=world_entity_index(latest.speaker);latest_portrait:=latest.kind=="dialogue"&&latest_entity>=0&&WORLD_ENTITIES[latest_entity].kind=="person"
	latest_width:=latest_portrait?f32(375):f32(445);used:=dialogue_ledger_line_height(dialogue_semantic_text(latest.text,latest.kind),latest_width)
	if latest_portrait do used=max(used,100)
	for start>0 {candidate:=dialogue_ledger_line_height(dialogue_semantic_text(g.conversation_transcript[indices[start-1]].text,g.conversation_transcript[indices[start-1]].kind),445);if used+candidate>360 do break;start-=1;used+=candidate}
	return used
}
dialogue_legacy_entry_layout_height :: proc(g:^Game,node_index:int)->f32 {
	node:=mystery_dialogue_approach_at(mystery_game_payload(g),node_index);if node==nil do return 0
	height:=dialogue_ledger_line_height(node.prompt,445)
	if node.clue_id!="" do height+=dialogue_ledger_line_height("retryable · 1 tick",445)
	return height
}
dialogue_legacy_layout_height :: proc(g:^Game,source_id:string)->f32 {
	payload:=mystery_game_payload(g);if payload==nil do return 0
	indices:[32]int;count:=0;for i in 0..<mystery_dialogue_approach_count(payload) {node:=mystery_dialogue_approach_at(payload,i);if node.character_id==source_id&&mystery_game_dialogue_completed(g,i)&&count<len(indices) {indices[count]=i;count+=1}}
	if count==0 do return 0
	clue_index:=clue_for_source(g,source_id);case_note:=dialogue_case_note_active(g,clue_index);if case_note&&g.dialogue_ledger_scroll==0 do return 0;ledger_scroll:=case_note?g.dialogue_ledger_scroll-1:g.dialogue_ledger_scroll;end:=clamp(count-ledger_scroll,1,count);start:=end-1;used:=dialogue_legacy_entry_layout_height(g,indices[start])
	for start>0&&end-start<3 {candidate:=dialogue_legacy_entry_layout_height(g,indices[start-1]);if used+candidate>379 do break;start-=1;used+=candidate}
	for end<count&&end-start<3 {candidate:=dialogue_legacy_entry_layout_height(g,indices[end]);if used+candidate>379 do break;used+=candidate;end+=1}
	return used
}
dialogue_choices_start_y :: proc(g:^Game,source_id:string)->f32 {
	// Responses follow the actual visible transcript instead of occupying a
	// fixed slot. The transcript remains bottom-aligned when it is short.
	used:=dialogue_transcript_layout_height(g,source_id);if used<=0 do used=dialogue_legacy_layout_height(g,source_id);if used<=0 do return 488
	return f32(70)+used+31
}
DIALOGUE_RESPONSE_VIEW_BOTTOM :: f32(646)
DIALOGUE_RESPONSES_PER_PAGE :: 3 // Cinematic choice beats still use their authored paging layout.
dialogue_available_approach_count :: proc(g:^Game,source_id:string)->int {count:=0;payload:=mystery_game_payload(g);for i in 0..<mystery_dialogue_approach_count(payload) {node:=mystery_dialogue_approach_at(payload,i);if node.character_id==source_id&&dialogue_approach_available(g,i) do count+=1};return count}
dialogue_response_count :: proc(g:^Game,source_id:string,clue_index:int)->int {return dialogue_available_approach_count(g,source_id)+(dialogue_can_present_evidence(g,clue_index)?1:0)}
dialogue_response_page_clamp :: proc(g:^Game,source_id:string,clue_index:int) {g.dialogue_choice_page=clamp(g.dialogue_choice_page,0,max(0,dialogue_response_count(g,source_id,clue_index)-1))}
dialogue_response_visible_count :: proc(g:^Game,source_id:string,clue_index:int)->int {dialogue_response_page_clamp(g,source_id,clue_index);return max(0,dialogue_response_count(g,source_id,clue_index)-g.dialogue_choice_page)}
dialogue_response_global_slot :: proc(g:^Game,local_slot:int)->int {return g.dialogue_choice_page+local_slot}
dialogue_response_approach :: proc(g:^Game,source_id:string,clue_index,local_slot:int)->int {global:=dialogue_response_global_slot(g,local_slot);if global>=dialogue_available_approach_count(g,source_id) do return -1;return visible_dialogue_approach(g,source_id,global)}
dialogue_response_is_evidence :: proc(g:^Game,source_id:string,clue_index,local_slot:int)->bool {return dialogue_can_present_evidence(g,clue_index)&&dialogue_response_global_slot(g,local_slot)==dialogue_available_approach_count(g,source_id)}
dialogue_response_rect :: proc(g:^Game,source_id:string,clue_index,local_slot:int)->Rect {y:=dialogue_choices_start_y(g,source_id);for slot in 0..<local_slot {index:=dialogue_response_approach(g,source_id,clue_index,slot);y+=index>=0?dialogue_approach_rect(g,index,y).h+4:f32(44)};index:=dialogue_response_approach(g,source_id,clue_index,local_slot);if index>=0 do return dialogue_approach_rect(g,index,y);return {650,y,490,40}}
dialogue_response_content_height :: proc(g:^Game,source_id:string,clue_index:int)->f32 {
	y:=f32(0);count:=dialogue_response_count(g,source_id,clue_index);approaches:=dialogue_available_approach_count(g,source_id)
	for global in 0..<count {if global<approaches {index:=visible_dialogue_approach(g,source_id,global);if index>=0 do y+=dialogue_approach_rect(g,index,0).h+4}else do y+=44}
	return max(0,y-4)
}
dialogue_response_view_bottom :: proc(g:^Game,source_id:string,clue_index:int)->f32 {return min(DIALOGUE_RESPONSE_VIEW_BOTTOM,dialogue_choices_start_y(g,source_id)+dialogue_response_content_height(g,source_id,clue_index))}
dialogue_object_result_height :: proc(g:^Game,clue_index:int)->f32 {
	payload:=mystery_game_payload(g);if payload==nil||clue_index<0||clue_index>=len(payload.clues) do return 78
	lines:=wrapped_line_count(mystery_clue_proposition_text(g.story_project,&payload.clues[clue_index]),454,.64)
	return clamp(f32(62+max(1,lines)*14),78,176)
}
dialogue_has_available_approach :: proc(g:^Game,source_id:string)->bool {
	return dialogue_available_approach_count(g,source_id)>0
}
dialogue_approaches_bottom :: proc(g:^Game,source_id:string)->f32 {
	clue:=clue_for_source(g,source_id);count:=dialogue_response_visible_count(g,source_id,clue);if count<=0 do return dialogue_choices_start_y(g,source_id);last:=dialogue_response_rect(g,source_id,clue,count-1);return last.y+last.h
}
dialogue_choice_marker :: proc(g:^Game,slot:int)->string {return g.active_device==.Gamepad?"◇":fmt.tprintf("%d.",dialogue_response_global_slot(g,slot)+1)}
dialogue_shortcut_selected :: proc(g:^Game,slot:int)->bool {return g.active_device==.Keyboard_Mouse&&g.input.dialogue_choice_slot==dialogue_response_global_slot(g,slot)+1}
dialogue_approaches_heading :: proc(g:^Game)->string {
	return "CHOOSE YOUR APPROACH"
}
dialogue_authored_choice_limit :: proc(g:^Game,clue_index:int)->int {if g.dialogue_entity<0||g.dialogue_entity>=len(WORLD_ENTITIES) do return 0;return dialogue_response_visible_count(g,WORLD_ENTITIES[g.dialogue_entity].source_id,clue_index)}
dialogue_evidence_choice_rect :: proc(g:^Game,source_id:string,clue_index:int)->Rect {
	count:=dialogue_response_visible_count(g,source_id,clue_index);for slot in 0..<count do if dialogue_response_is_evidence(g,source_id,clue_index,slot) do return dialogue_response_rect(g,source_id,clue_index,slot);return {}
}
dialogue_end_rect_for :: proc(g:^Game)->Rect {
	if g.dialogue_entity>=0&&g.dialogue_entity<len(WORLD_ENTITIES) {
		e:=WORLD_ENTITIES[g.dialogue_entity]
		if e.kind=="person" {
			if officer_source(e.source_id) do return {650,e.source_id=="officer_lead"?f32(586):f32(538),490,28}
			return {650,654,490,28}
		}
	}
	return {650,654,490,28}
}
dialogue_object_leave_rect :: proc()->Rect {return {650,654,490,28}}
dialogue_body_watch_clue :: proc(g:^Game)->int {entity:=world_entity_index("edgar_watch");if entity<0||!entity_visible(g,&WORLD_ENTITIES[entity]) do return -1;return clue_for_source(g,"edgar_watch")}
dialogue_body_watch_rect :: proc(g:^Game)->Rect {return {650,g.desk_key_found?f32(420):f32(482),490,58}}
dialogue_check_cancel_rect :: proc()->Rect {return {650,548,490,30}}
DIALOGUE_LEDGER_RAIL_Y :: f32(46)
DIALOGUE_LEDGER_RAIL_H :: f32(398)
DIALOGUE_LEDGER_THUMB_H :: f32(54)
dialogue_ledger_scroll_hit_rect :: proc()->Rect {return {1140,DIALOGUE_LEDGER_RAIL_Y,20,DIALOGUE_LEDGER_RAIL_H}}
dialogue_ledger_thumb_y :: proc(scroll,max_scroll:int)->f32 {
	if max_scroll<=0 do return DIALOGUE_LEDGER_RAIL_Y
	return DIALOGUE_LEDGER_RAIL_Y+(DIALOGUE_LEDGER_RAIL_H-DIALOGUE_LEDGER_THUMB_H)*(1-f32(clamp(scroll,0,max_scroll))/f32(max_scroll))
}
dialogue_history_position_label :: proc(scroll,max_scroll:int)->string {
	if scroll<=0 do return "↑ OLDER"
	if scroll>=max_scroll do return "↓ NEWER"
	return "↑ OLDER  ·  ↓ NEWER"
}
dialogue_history_input_hint :: proc(g:^Game)->string {
	return g.active_device==.Gamepad?"SHOULDERS":"PGUP / PGDN / WHEEL"
}
dialogue_reference_hint :: proc(g:^Game)->string {
	if g.active_device==.Gamepad {
		family:=gamepad_family(g.gamepad_type)
		return fmt.tprintf("%s  NOTEBOOK  ·  %s  ATTRIBUTES",gamepad_prompt_label(.Notebook,family),gamepad_prompt_label(.Board,family))
	}
	return "N  NOTEBOOK  ·  C  ATTRIBUTES"
}
dialogue_exchange_is_fresh :: proc(g:^Game,position,count:int)->bool {
	elapsed:=g.animation_time-g.dialogue_text_started
	return position==count-1&&elapsed>=0&&elapsed<1.25
}
dialogue_exchange_fresh_visible :: proc(g:^Game,position,count,clue_index:int)->bool {return !dialogue_case_note_active(g,clue_index)&&dialogue_exchange_is_fresh(g,position,count)}
dialogue_ledger_line_height :: proc(text:string,width:f32)->f32 {
	return 26+f32(wrapped_line_count(text,width-12,.70))*(f32(COURIER_CELL_HEIGHT)*.70+3)
}
dialogue_ledger_exchange_height :: proc(g:^Game,node_index:int)->f32 {
	node:=mystery_dialogue_approach_at(mystery_game_payload(g),node_index);if node==nil do return 0;response:=mystery_game_dialogue_failed(g,node_index)?dialogue_approach_failure_response(g,node_index):node.response;height:=dialogue_ledger_line_height(node.prompt,445)+dialogue_ledger_line_height(response,445)
	if node.clue_id!="" do height+=dialogue_ledger_line_height("retryable · 1 tick",445)
	return height+9
}
dialogue_can_present_evidence :: proc(g:^Game,clue_index:int)->bool {
	payload:=mystery_game_payload(g);return payload!=nil&&clue_index>=0&&clue_index<len(payload.clues)&&!mystery_game_evidence_presented(g,clue_index)&&relevant_evidence_for_clue(g,clue_index)>=0
}
dialogue_case_note_active :: proc(g:^Game,clue_index:int)->bool {return g.dialogue_node==3&&g.dialogue_response!=""&&clue_index>=0&&mystery_game_evidence_presented(g,clue_index)}
dialogue_failed_check_active :: proc(g:^Game,clue_index:int)->bool {
	payload:=mystery_game_payload(g);if payload==nil||clue_index<0||clue_index>=len(payload.clues)||mystery_game_clue_discovered(g,clue_index) do return false
	clue_id:=payload.clues[clue_index].id
	for i in 0..<mystery_dialogue_approach_count(payload) {node:=mystery_dialogue_approach_at(payload,i);if node.clue_id==clue_id&&mystery_game_dialogue_failed(g,i) do return true}
	return false
}
dialogue_evidence_label :: proc(g:^Game,clue_index:int)->string {
	payload:=mystery_game_payload(g);if payload!=nil&&clue_index>=0&&clue_index<len(payload.clues)&&mystery_game_evidence_presented(g,clue_index) do return "Evidence presented"
	source:=relevant_evidence_for_clue(g,clue_index)
	if source<0 {if payload!=nil&&dialogue_failed_check_active(g,clue_index)&&payload.clues[clue_index].check_kind!="red" do return "Question another account or examine a related object";return "Nothing applicable to present"}
	return fmt.tprintf("Present · %s",case_sense_source_name(g,source))
}
dialogue_evidence_feedback :: proc(g:^Game,clue_index:int)->string {
	payload:=mystery_game_payload(g)
	source:=relevant_evidence_for_clue(g,clue_index)
	if payload!=nil&&clue_index>=0&&clue_index<len(payload.clues)&&source>=0&&source<len(payload.clues) {
		target_id:=payload.clues[clue_index].id
		source_id:=payload.clues[source].id
		if target_id=="clue_daniel"&&source_id=="clue_dinner_settings" do return "You place the disturbed dinner settings beside Daniel's immaculate account. His thumb finds the crease of the note inside his coat. 'An empty chair proves absence, Lieutenant. It does not tell you what occupied it.'"
		if target_id=="clue_elsie"&&source_id=="clue_ledger" do return "You set Edgar's red-circled ledger beside the locked cash drawer. Elsie reads every marked sum before looking up. 'Household money goes missing in more than one direction, Lieutenant.'"
		if target_id=="clue_elsie"&&source_id=="clue_appointment_stub" do return "You show Elsie the words 'Miriam—study, 8:20—'. She reads the name once and the time twice. 'If you are asking whether I saw the study door, ask me that.'"
	}
	name:=source>=0?case_sense_source_name(g,source):"Relevant evidence"
	return fmt.tprintf("%s presented. Related checks gain +1 modifier.",name)
}
dialogue_return_from_check :: proc(g:^Game) {
	object_check:=g.dialogue_entity>=0&&g.dialogue_entity<len(WORLD_ENTITIES)&&WORLD_ENTITIES[g.dialogue_entity].kind!="person"
	cancelled_approach:=!g.check_done&&g.pending_dialogue_approach>0?g.pending_dialogue_approach-1:-1
	g.check_from_dialogue=false;g.check_done=false
	g.pending_dialogue_approach=0
	body_tree:=object_check&&WORLD_ENTITIES[g.dialogue_entity].source_id=="body"
	if g.investigation_locked&&!overtime_active(g) {route_locked_investigation(g)} else if object_check&&!body_tree do g.screen=.Investigate
	if g.screen==.Dialogue {
		if cancelled_approach>=0 {
			source:=WORLD_ENTITIES[g.dialogue_entity].source_id;clue:=clue_for_source(g,source);count:=dialogue_available_approach_count(g,source);for absolute in 0..<count {index:=visible_dialogue_approach(g,source,absolute);if index!=cancelled_approach do continue;g.dialogue_choice_page=absolute;choice:=dialogue_response_rect(g,source,clue,0);g.gui.focused=button_id(choice);g.focus_screen=.Dialogue;g.focus_screen_initialized=true;return}
		}
		dialogue_focus_default(g)
	}
}
dialogue_check_cancel_label :: proc(g:^Game)->string {
	person:=g.dialogue_entity>=0&&g.dialogue_entity<len(WORLD_ENTITIES)&&WORLD_ENTITIES[g.dialogue_entity].kind=="person"
	body_tree:=g.dialogue_entity>=0&&g.dialogue_entity<len(WORLD_ENTITIES)&&WORLD_ENTITIES[g.dialogue_entity].source_id=="body"
	return person||body_tree?"Cancel · Return to discoveries":"Cancel · Return to investigation"
}
dialogue_accept_prompt :: proc(g:^Game)->string {
	if g.active_device==.Gamepad do return gamepad_prompt_label(.Accept,gamepad_family(g.gamepad_type))
	return keyboard_prompt_label(.Accept)
}
dialogue_check_roll_summary :: proc(result:Check_Result)->string {
	return fmt.tprintf("DICE %d + %d   ·   MODIFIER %+d   ·   TOTAL %d / TARGET %d",result.die_a,result.die_b,result.modifier,result.total,result.target)
}
physical_check_failure_prefix :: proc(clue_id:string)->string {
	switch clue_id {
	case "clue_ledger":return "The figures suggest a grievance, but Edgar's red pencil could still be emphasis rather than accusation."
	case "clue_appointment_stub":return "The ragged stub preserves an appointment, but only half of its meaning."
	case "clue_cloth":return "The cloth carries oil and a darkened fold, but neither yet says what it polished."
	case "clue_clock":return "The broken watch gives you a time, but not yet a trustworthy reason it stopped."
	case "clue_cane":return "The garden pose looks composed; neatness alone cannot prove who composed it."
	case "clue_statuette":return "Fresh polish invites suspicion, but suspicion is not yet a wound match."
	case "clue_drag":return "The rain-softened thyme preserves a route, but not yet what traveled it."
	case "clue_dinner_settings":return "The table remembers departures, but not yet whose absence mattered."
	case "clue_burned_fragment":return "The fire spared words and an edge, but neither can answer alone."
	}
	return "The detail will not hold yet."
}
dialogue_check_failure_text :: proc(g:^Game,check_kind:string)->string {
	if g.pending_dialogue_approach>0&&g.pending_dialogue_approach<=mystery_dialogue_approach_count(mystery_game_payload(g)) do return dialogue_approach_failure_response(g,g.pending_dialogue_approach-1)
	if check_kind=="red" do return "This approach is closed, but the reaction remains evidence for another line of inquiry."
	payload:=mystery_game_payload(g);prefix:="The detail will not hold yet.";if payload!=nil&&g.pending_clue>=0&&g.pending_clue<len(payload.clues) do prefix=physical_check_failure_prefix(payload.clues[g.pending_clue].id)
	return fmt.tprintf("%s You may spend another tick to try again.",prefix)
}
dialogue_check_threshold_label :: proc(target:int)->string {return fmt.tprintf("TOTAL %d+ NEEDED",target)}
dialogue_check_tooltip_cost :: proc(cost,remaining:int)->string {if cost<=0 do return "NO COST  ·  OVERTIME";return fmt.tprintf("COST %d %s  ·  %d %s REMAIN",cost,cost==1?"TICK":"TICKS",remaining,remaining==1?"TICK":"TICKS")}
dialogue_check_prompt :: proc(g:^Game)->string {
	payload:=mystery_game_payload(g);if g.pending_dialogue_approach>0 {index:=g.pending_dialogue_approach-1;node:=mystery_dialogue_approach_at(payload,index);if node!=nil do return node.prompt}
	if payload!=nil&&g.pending_clue>=0&&g.pending_clue<len(payload.clues) do return strings.to_upper(payload.clues[g.pending_clue].description)
	return "INVESTIGATIVE CHECK"
}
dialogue_check_commit_label :: proc(g:^Game,cost:int)->string {payload:=mystery_game_payload(g);skill:="INVESTIGATIVE";if payload!=nil&&g.pending_clue>=0&&g.pending_clue<len(payload.clues) do skill=strings.to_upper(payload.clues[g.pending_clue].skill);return fmt.tprintf("[%s]  ROLL %s CHECK  ·  %s",dialogue_accept_prompt(g),skill,dialogue_tick_cost_label(cost))}
dialogue_check_disposition_result :: proc(g:^Game)->string {if g.check_disposition_delta>0 do return "DISPOSITION +1  ·  MORE RECEPTIVE";if g.check_disposition_delta<0 do return "DISPOSITION -1  ·  MORE GUARDED";return ""}
dialogue_check_cost_summary :: proc(g:^Game,clue_index:int)->string {
	payload:=mystery_game_payload(g);if payload==nil||clue_index<0||clue_index>=len(payload.clues) do return ""
	cost:=clue_action_cost(g,clue_index)
	if cost<=0 do return "NO TICK COST"
	return fmt.tprintf("COST %d TICK%s   ·   %d REMAINING AFTER ROLL",cost,cost==1?"":"S",max(0,g.ap-cost))
}
dialogue_tick_cost_label :: proc(cost:int)->string {
	if cost<=0 do return "NO COST"
	return fmt.tprintf("%d TICK%s",cost,cost==1?"":"S")
}
dialogue_scroll_ledger :: proc(g:^Game,max_scroll:int) {
	// Directional input belongs to menu focus. Giving it to the ledger as well
	// made one D-pad press both change the selected response and move history.
	source_id:="";if g.dialogue_entity>=0&&g.dialogue_entity<len(WORLD_ENTITIES) do source_id=WORLD_ENTITIES[g.dialogue_entity].source_id
	history_pointer:=g.input.mouse_pos.y<dialogue_choices_start_y(g,source_id);delta:=g.input.shoulder_left?1:g.input.shoulder_right?-1:history_pointer&&g.input.mouse_wheel>0?1:history_pointer&&g.input.mouse_wheel<0?-1:0
	g.dialogue_ledger_scroll=clamp(g.dialogue_ledger_scroll+delta,0,max_scroll)
	if max_scroll>0&&g.input.mouse_pressed&&contains(dialogue_ledger_scroll_hit_rect(),g.input.mouse_pos) {
		track:=DIALOGUE_LEDGER_RAIL_H-DIALOGUE_LEDGER_THUMB_H;position:=clamp((g.input.mouse_pos.y-DIALOGUE_LEDGER_RAIL_Y-DIALOGUE_LEDGER_THUMB_H*.5)/track,0,1)
		g.dialogue_ledger_scroll=clamp(int((1-position)*f32(max_scroll)+.5),0,max_scroll)
	}
}
dialogue_back :: proc(g:^Game) {
	if g.story_presentation.active {beat:=story_presentation_node(g);if beat!=nil&&beat.kind==.Interaction&&beat.cancel!="" {dialogue_complete_current(g,beat.cancel)}else if cinematic_can_leave(g) do dialogue_end_scene(g);return}
	if g.end_confirm {g.end_confirm=false;dialogue_focus_default(g);return}
	if !g.check_from_dialogue {g.screen=.Investigate;return}
	if g.check_done&&g.animation_time-g.check_roll_started<CHECK_REVEAL_DURATION do return
	dialogue_return_from_check(g)
}
dialogue_default_rect :: proc(g:^Game)->Rect {
	if g.story_presentation.active do return cinematic_default_rect(g)
	if g.check_from_dialogue do return {650,590,490,42}
	if g.dialogue_entity<0||g.dialogue_entity>=len(WORLD_ENTITIES) do return {650,610,490,42}
	e:=WORLD_ENTITIES[g.dialogue_entity]
	if e.source_id=="shutter_crank" do return {650,420,490,58}
	if e.source_id=="body" {watch:=dialogue_body_watch_clue(g);if watch>=0&&!mystery_game_clue_discovered(g,watch)&&clue_available(g,watch) do return dialogue_body_watch_rect(g);return dialogue_object_leave_rect()}
	if e.kind!="person" {if e.source_id=="pond_reflection" do return reflective_interaction_rect();clue:=clue_for_source(g,e.source_id);if e.source_id=="dining_room"&&clue>=0&&mystery_game_clue_discovered(g,clue) do return dining_walkthrough_rect();if clue>=0&&!mystery_game_clue_discovered(g,clue)&&clue_available(g,clue) do return dialogue_object_check_rect(g,clue);return dialogue_object_leave_rect()}
	if officer_source(e.source_id) do return g.end_confirm?officer_confirmation_rect(false):officer_choice_rect(0)
	clue:=clue_for_source(g,e.source_id);if dialogue_response_visible_count(g,e.source_id,clue)>0 do return dialogue_response_rect(g,e.source_id,clue,0)
	return dialogue_end_rect_for(g)
}
dialogue_focus_default :: proc(g:^Game) {
	if g.screen!=.Dialogue do return
	g.gui.focused=button_id(dialogue_default_rect(g));g.focus_screen=.Dialogue;g.focus_screen_initialized=true
}
update_dialogue :: proc(g:^Game){
	if graph_state.playtesting&&!g.story_presentation.active {graph_debugger_update_editor_toggle(g);update_graph_debugger(g);return}
	if g.quest_completion_pending {if g.animation_time-g.quest_completion_started>=1.5 {g.quest_completion_pending=false;g.investigation_locked=true;g.phase=.Reveal_Preparation;g.screen=.Reveal_Prep;g.end_confirm=false};return}
	if g.story_presentation.active {
		if g.input.notebook {open_notebook(g);return}
		if g.input.attributes||g.input.recreate {open_attributes(g);return}
		_=update_cinematic_dialogue(g);return
	}
	if g.check_from_dialogue {
		update_check_result_cue(g)
		settled:=g.check_done&&g.animation_time-g.check_roll_started>=CHECK_REVEAL_DURATION
		if !g.check_done {if button(g,dialogue_check_cancel_rect()) {dialogue_return_from_check(g);return};if button(g,{650,590,490,42}) {g.check_result=resolve_clue_check(g,g.pending_clue);g.check_roll_started=g.animation_time;g.check_result_cue_played=false;play_check_dice_sound(g);g.check_done=true}}
		if settled&&button(g,{650,590,490,42}) do dialogue_return_from_check(g)
		return
	}
	if g.input.notebook {open_notebook(g);return}
	if g.input.attributes||g.input.recreate {open_attributes(g);return}
	e:=WORLD_ENTITIES[g.dialogue_entity];clue:=clue_for_source(g,e.source_id)
	if e.kind=="person" {
		if officer_source(e.source_id) {
			if g.end_confirm {if button(g,officer_confirmation_rect(false)) {g.end_confirm=false;dialogue_focus_default(g)};if button(g,officer_confirmation_rect(true)) {_=game_story_milestone(g,"investigation.conclusion_presented");g.quest_completion_pending=true;g.quest_completion_started=g.animation_time};return}
			if e.source_id=="officer_lead" {if button(g,officer_choice_rect(0))||dialogue_shortcut_selected(g,0) {g.dialogue_response=investigation_unresolved_summary(g);g.dialogue_text_started=g.animation_time};if button(g,officer_choice_rect(1))||dialogue_shortcut_selected(g,1) {g.end_confirm=true;dialogue_focus_default(g)}} else if button(g,officer_choice_rect(0))||dialogue_shortcut_selected(g,0) {g.dialogue_response=officer_report_line(g,e.source_id);g.dialogue_text_started=g.animation_time;log_line(g,g.dialogue_response)}
			if button(g,dialogue_end_rect_for(g)) do g.screen=.Investigate
			return
		}
		character:=character_index(g,e.source_id)
		payload:=mystery_game_payload(g);completed_count:=0;for i in 0..<mystery_dialogue_approach_count(payload) {node:=mystery_dialogue_approach_at(payload,i);if node.character_id==e.source_id&&mystery_game_dialogue_completed(g,i) do completed_count+=1};case_note:=dialogue_case_note_active(g,clue);max_scroll:=case_note?completed_count:max(0,completed_count-1);dialogue_scroll_ledger(g,max_scroll)
		dialogue_response_page_clamp(g,e.source_id,clue);view_bottom:=dialogue_response_view_bottom(g,e.source_id,clue);if g.input.mouse_pos.x>=650&&g.input.mouse_pos.x<=1140&&g.input.mouse_pos.y>=dialogue_choices_start_y(g,e.source_id)&&g.input.mouse_pos.y<view_bottom&&g.input.mouse_wheel!=0 {delta:=g.input.mouse_wheel>0?-1:1;g.dialogue_choice_page=clamp(g.dialogue_choice_page+delta,0,max(0,dialogue_response_count(g,e.source_id,clue)-1));dialogue_focus_default(g)}
		visible:=dialogue_response_visible_count(g,e.source_id,clue);for slot in 0..<visible {choice:=dialogue_response_rect(g,e.source_id,clue,slot);index:=dialogue_response_approach(g,e.source_id,clue,slot);activated:=button(g,choice)||dialogue_shortcut_selected(g,slot);if !activated do continue;if index>=0 {node:=mystery_dialogue_approach_at(payload,index);if node!=nil&&node.clue_id=="" {complete_dialogue_approach(g,index);_=dialogue_start_dialogue_approach_scene(g,index)}else do begin_dialogue_approach_check(g,index)} else if dialogue_response_is_evidence(g,e.source_id,clue,slot) {feedback:=dialogue_evidence_feedback(g,clue);if present_evidence(g,clue) {g.dialogue_node=3;g.dialogue_response=feedback;g.dialogue_text_started=g.animation_time;g.dialogue_ledger_scroll=0;g.dialogue_choice_page=0;g.gui.focused=button_id(dialogue_default_rect(g))}};break}
		if button(g,dialogue_end_rect_for(g)) do g.screen=.Investigate
	} else {
		if e.source_id=="pond_reflection" {
			if button(g,reflective_interaction_rect())||dialogue_shortcut_selected(g,0) {g.dialogue_response=pond_reflection_line(g);g.dialogue_text_started=g.animation_time;log_line(g,g.dialogue_response);dialogue_focus_default(g)}
			if button(g,dialogue_object_leave_rect()) do g.screen=.Investigate
			return
		}
		if e.source_id=="body" {
			watch:=dialogue_body_watch_clue(g)
			payload:=mystery_game_payload(g);if payload!=nil&&watch>=0&&!mystery_game_clue_discovered(g,watch)&&clue_available(g,watch)&&(button(g,dialogue_body_watch_rect(g))||dialogue_shortcut_selected(g,0)) {g.pending_clue=watch;g.pending_dialogue_approach=0;authored:=&payload.clues[watch];g.check_preview=check_target(authored.difficulty);g.check_done=false;g.check_disposition_delta=0;g.check_from_dialogue=true;dialogue_focus_default(g)}
			if button(g,dialogue_object_leave_rect()) do g.screen=.Investigate
			return
		}
		if e.source_id=="shutter_crank" {
			if button(g,{650,420,490,58})||dialogue_shortcut_selected(g,0) {
				if g.shutter_demonstrating {g.dialogue_response="The shutter is still falling. Let the demonstration finish."}
				else if !g.shutter_sightline_failed {demonstrate_shutter_folly(g);g.dialogue_response="The shutter drops across the study window. From the dining room, the garden and study window disappear behind solid slats."}
				else {toggle_shutter_crank(g);g.dialogue_response=g.shutter_target>=.5?"The crank raises the shutter, reopening the garden sightline.":"The crank lowers the shutter. The garden sightline disappears again."}
				g.dialogue_text_started=g.animation_time;dialogue_focus_default(g)
			}
			if button(g,dialogue_object_leave_rect()) do g.screen=.Investigate
			return
		}
		if e.source_id=="dining_room"&&clue>=0&&mystery_game_clue_discovered(g,clue)&&(button(g,dining_walkthrough_rect())||dialogue_shortcut_selected(g,0)) {g.dialogue_response=dining_walkthrough_line(g);g.dialogue_text_started=g.animation_time;log_line(g,g.dialogue_response);dialogue_focus_default(g)}
		payload:=mystery_game_payload(g);if payload!=nil&&clue>=0&&!mystery_game_clue_discovered(g,clue)&&clue_available(g,clue)&&(button(g,{650,420,490,58})||dialogue_shortcut_selected(g,0)) {g.pending_clue=clue;g.pending_dialogue_approach=0;authored:=&payload.clues[clue];g.check_preview=check_target(authored.difficulty);g.check_done=false;g.check_disposition_delta=0;g.check_from_dialogue=true;dialogue_focus_default(g)}
		if button(g,dialogue_object_leave_rect()) do g.screen=.Investigate
	}
}
