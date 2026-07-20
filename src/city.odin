package main

import "core:fmt"
import "core:math"
import "core:strings"

CITY_WIDTH :: 192
CITY_HEIGHT :: 160
CITY_BLOCK :: 16
// Authored city data uses compact layout units. One layout unit expands to two
// world metres so roads, blocks, and buildings match the full-size vehicles.
CITY_WORLD_SCALE :: f32(2)
CITY_WORLD_WIDTH :: f32(CITY_WIDTH) * CITY_WORLD_SCALE
CITY_WORLD_HEIGHT :: f32(CITY_HEIGHT) * CITY_WORLD_SCALE
city_world :: proc(value: f32) -> f32 {return value * CITY_WORLD_SCALE}
city_layout :: proc(value: f32) -> f32 {return value / CITY_WORLD_SCALE}

// Broad, gentle landforms give the city readable high and low districts while
// keeping the existing two-dimensional traversal and collision map unchanged.
// The envelope returns to sea level at every city edge, so the authored ground
// still meets the surrounding negative-space plane cleanly.
city_elevation :: proc(x, z: f32) -> f32 {
	u := clamp(x / CITY_WORLD_WIDTH, 0, 1); v := clamp(z / CITY_WORLD_HEIGHT, 0, 1)
	envelope := f32(math.sin(f64(u * math.PI)) * math.sin(f64(v * math.PI)))
	variation :=
		f32(8) +
		f32(math.sin(f64(u * math.PI * 2))) * 2.5 -
		f32(math.cos(f64(v * math.PI * 3))) * 1.5
	return max(envelope * variation, 0)
}

CITY_PLAYER_RADIUS :: f32(.24)
CITY_PLAYER_MAX_STEP_HEIGHT :: f32(.35)

city_triangle_height :: proc(x, z: f32, a, b, c: Vec3) -> (f32, bool) {
	denominator := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
	if math.abs(denominator) < .000001 do return 0, false
	u := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / denominator
	v := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / denominator
	w := 1 - u - v
	if u < -.0001 || v < -.0001 || w < -.0001 do return 0, false
	return u * a.y + v * b.y + w * c.y, true
}

// Roads contain both the carriageway and their raised curb/sidewalk geometry.
// Query the same transformed source tile used to build the render mesh so
// pedestrians stand and step on that geometry instead of passing through it.
city_surface_elevation :: proc(x, z: f32) -> f32 {
	result := city_elevation(x, z)
	layout_x, layout_z := city_layout(x), city_layout(z)
	tile_x, tile_z :=
		int(math.floor(f64(layout_x / 4))) * 4, int(math.floor(f64(layout_z / 4))) * 4
	center_x, center_z := tile_x + 2, tile_z + 2
	if !city_road_cell(center_x, center_z) do return result
	mesh_index, yaw := city_road_tile(city_road_connection_mask(center_x, center_z))
	if mesh_index < 0 || mesh_index >= len(city_road_meshes) do return result
	mesh := &city_road_meshes[mesh_index]; if !mesh.ready do return result
	model := vk_world_model(
		mesh,
		city_world(f32(center_x)),
		city_world(f32(center_z)),
		0,
		city_world(4),
		yaw,
		0,
		0,
		true,
	)
	for triangle := 0; triangle + 2 < len(mesh.indices); triangle += 3 {
		points: [3]Vec3
		for corner in 0 ..< 3 {
			vertex := mesh.vertices[mesh.indices[triangle + corner]]
			wx := model[0] * vertex.x + model[4] * vertex.y + model[8] * vertex.z + model[12]
			wz := model[2] * vertex.x + model[6] * vertex.y + model[10] * vertex.z + model[14]
			wy :=
				model[1] * vertex.x +
				model[5] * vertex.y +
				model[9] * vertex.z +
				model[13] +
				city_elevation(wx, wz)
			points[corner] = {wx, wy, wz}
		}
		if height, hit := city_triangle_height(x, z, points[0], points[1], points[2]); hit do result = max(result, height)
	}
	return result
}

CITY_TERRAIN_STEP :: 8
procedural_city_ground_mesh :: proc() -> Glb_Mesh {
	m: Glb_Mesh; columns := int(CITY_WORLD_WIDTH) / CITY_TERRAIN_STEP + 1; rows := int(CITY_WORLD_HEIGHT) / CITY_TERRAIN_STEP + 1
	m.vertices = make(
		[dynamic]Vec3,
		0,
		columns * rows,
	); m.texcoords = make([dynamic]Vec2, 0, columns * rows); m.indices = make([dynamic]u32, 0, (columns - 1) * (rows - 1) * 6); m.primitives = make([dynamic]Glb_Primitive_Range, 0, 1)
	m.min = {
		-CITY_WORLD_WIDTH * .5,
		0,
		-CITY_WORLD_HEIGHT * .5,
	}; m.max = {CITY_WORLD_WIDTH * .5, 0, CITY_WORLD_HEIGHT * .5}
	for row in 0 ..< rows {for column in 0 ..< columns {x := f32(column * CITY_TERRAIN_STEP); z := f32(row * CITY_TERRAIN_STEP); height := city_elevation(x, z); append(&m.vertices, Vec3{x - CITY_WORLD_WIDTH * .5, height, z - CITY_WORLD_HEIGHT * .5}); append(&m.texcoords, Vec2{x / CITY_WORLD_WIDTH, z / CITY_WORLD_HEIGHT}); m.max.y = max(m.max.y, height)}}
	for row in 0 ..< rows -
		1 {for column in 0 ..< columns - 1 {a := u32(row * columns + column); b := a + 1; c := a + u32(columns); d := c + 1; append(&m.indices, a, d, b, a, c, d)}}
	append(
		&m.primitives,
		Glb_Primitive_Range{0, len(m.indices), -1, {1, 1, 1, 1}},
	); m.ready = true; return m
}

CITY_MESH_PATHS := [?]string {
	"assets/kenney_city-kit-suburban_20/Models/GLB format/building-type-a.glb",
	"assets/kenney_city-kit-suburban_20/Models/GLB format/building-type-d.glb",
	"assets/kenney_city-kit-commercial_2.1/Models/GLB format/building-a.glb",
	"assets/kenney_city-kit-commercial_2.1/Models/GLB format/building-j.glb",
	"assets/kenney_city-kit-commercial_2.1/Models/GLB format/building-skyscraper-b.glb",
	"assets/kenney_city-kit-industrial_1.0/Models/GLB format/building-a.glb",
	"assets/kenney_city-kit-industrial_1.0/Models/GLB format/building-r.glb",
}
city_meshes: [len(CITY_MESH_PATHS)]Glb_Mesh
CITY_ROAD_MESH_PATHS := [?]string {
	"assets/kenney_city-kit-roads/Models/GLB format/road-straight.glb",
	"assets/kenney_city-kit-roads/Models/GLB format/road-crossroad.glb",
	"assets/kenney_city-kit-roads/Models/GLB format/road-bend.glb",
	"assets/kenney_city-kit-roads/Models/GLB format/road-intersection.glb",
	"assets/kenney_city-kit-roads/Models/GLB format/road-end.glb",
}
city_road_meshes: [len(CITY_ROAD_MESH_PATHS)]Glb_Mesh
city_bent_road_meshes: [len(CITY_ROAD_MESH_PATHS)]Glb_Mesh
city_ground_mesh, city_background_mesh: Glb_Mesh
city_quest_marker_mesh: Glb_Mesh
city_quest_marker_center: Vec2
city_quest_marker_built: bool

procedural_city_quest_marker_mesh :: proc(center: Vec2, radius: f32) -> Glb_Mesh {
	m: Glb_Mesh; segments := 48; outer := radius; inner := radius * .68; base := city_surface_elevation(center.x, center.y)
	m.vertices = make(
		[dynamic]Vec3,
		0,
		segments * 2,
	); m.texcoords = make([dynamic]Vec2, 0, segments * 2); m.indices = make([dynamic]u32, 0, segments * 6); m.primitives = make([dynamic]Glb_Primitive_Range, 0, 1)
	m.min = {-outer, 1e30, -outer}; m.max = {outer, -1e30, outer}
	for i in 0 ..< segments {angle := f32(i) * 2 * f32(math.PI) / f32(segments); c, s := f32(math.cos(f64(angle))), f32(math.sin(f64(angle))); outer_y := city_surface_elevation(center.x + c * outer, center.y + s * outer) - base; inner_y := city_surface_elevation(center.x + c * inner, center.y + s * inner) - base; append(&m.vertices, Vec3{c * outer, outer_y, s * outer}, Vec3{c * inner, inner_y, s * inner}); append(&m.texcoords, Vec2{(c + 1) * .5, (s + 1) * .5}, Vec2{(c * .68 + 1) * .5, (s * .68 + 1) * .5}); m.min.y = min(m.min.y, min(outer_y, inner_y)); m.max.y = max(m.max.y, max(outer_y, inner_y))}
	for i in 0 ..< segments {next := (i + 1) % segments; o0, i0, o1, i1 := u32(i * 2), u32(i * 2 + 1), u32(next * 2), u32(next * 2 + 1); append(&m.indices, o0, i0, i1, o0, i1, o1)}
	append(
		&m.primitives,
		Glb_Primitive_Range{0, len(m.indices), -1, {1, 1, 1, 1}},
	); m.ready = true; return m
}

procedural_city_road_mesh :: proc(mesh_index: int) -> Glb_Mesh {
	m: Glb_Mesh; if mesh_index < 0 || mesh_index >= len(city_road_meshes) do return m; source := &city_road_meshes[mesh_index]; if !source.ready do return m
	m.vertices = make(
		[dynamic]Vec3,
		0,
	); m.texcoords = make([dynamic]Vec2, 0); m.indices = make([dynamic]u32, 0); m.primitives = make([dynamic]Glb_Primitive_Range, 0, len(source.primitives)); bases := make([dynamic]u32, 0, 256, context.temp_allocator)
	for ty := 0;
	    ty < CITY_HEIGHT;
	    ty += 4 {for tx := 0; tx < CITY_WIDTH; tx += 4 {if !city_road_cell(tx + 2, ty + 2) do continue; kind, yaw := city_road_tile(city_road_connection_mask(tx + 2, ty + 2)); if kind != mesh_index do continue; wx, wz := city_world(f32(tx + 2)), city_world(f32(ty + 2)); model := vk_world_model(source, wx, wz, 0, city_world(4), yaw, 0, 0, true); append(&bases, u32(len(m.vertices))); for vertex, i in source.vertices {world_x := model[0] * vertex.x + model[4] * vertex.y + model[8] * vertex.z + model[12]; world_z := model[2] * vertex.x + model[6] * vertex.y + model[10] * vertex.z + model[14]; world_y := model[1] * vertex.x + model[5] * vertex.y + model[9] * vertex.z + model[13] + city_elevation(world_x, world_z); append(&m.vertices, Vec3{world_x, world_y, world_z}); append(&m.texcoords, source.texcoords[i])}}}
	for primitive in source.primitives {first := len(m.indices); for base in bases {for source_index in source.indices[primitive.first:primitive.first + primitive.count] do append(&m.indices, base + source_index)}; append(&m.primitives, Glb_Primitive_Range{first, len(m.indices) - first, primitive.texture, primitive.base_color})}
	if len(m.vertices) == 0 do return m; m.min = {1e30, 1e30, 1e30}; m.max = {-1e30, -1e30, -1e30}; for vertex in m.vertices {m.min.x = min(m.min.x, vertex.x); m.min.y = min(m.min.y, vertex.y); m.min.z = min(m.min.z, vertex.z); m.max.x = max(m.max.x, vertex.x); m.max.y = max(m.max.y, vertex.y); m.max.z = max(m.max.z, vertex.z)}
	m.textures =
		source.textures; m.alpha_modes = source.alpha_modes; m.alpha_cutoffs = source.alpha_cutoffs; m.normal_textures = source.normal_textures; m.roughness_textures = source.roughness_textures; m.metallic_factors = source.metallic_factors; m.roughness_factors = source.roughness_factors; m.normal_scales = source.normal_scales; m.ready = len(m.indices) > 0; return m
}

City_Furniture_Kind :: enum {
	Bench,
	Planter,
	Street_Light,
	Barrier,
	Cone,
	Sign,
}
City_Furniture_Template :: struct {
	kind:                 City_Furniture_Kind,
	path:                 string,
	height, radius, mass: f32,
	tint:                 [4]u8,
}
CITY_FURNITURE_TEMPLATES := [?]City_Furniture_Template {
	{
		.Bench,
		"assets/kenney_city-kit-suburban_20/Models/GLB format/fence-low.glb",
		.72,
		.62,
		1.15,
		{116, 78, 48, 255},
	},
	{
		.Planter,
		"assets/kenney_city-kit-suburban_20/Models/GLB format/planter.glb",
		.78,
		.46,
		1.35,
		{164, 151, 112, 255},
	},
	{
		.Street_Light,
		"assets/kenney_city-kit-roads/Models/GLB format/light-curved.glb",
		2.8,
		.32,
		1.55,
		{104, 116, 126, 255},
	},
	{
		.Barrier,
		"assets/kenney_city-kit-roads/Models/GLB format/construction-barrier.glb",
		.92,
		.66,
		.88,
		{238, 151, 48, 255},
	},
	{
		.Cone,
		"assets/kenney_city-kit-roads/Models/GLB format/construction-cone.glb",
		.62,
		.28,
		.30,
		{242, 104, 36, 255},
	},
	{
		.Sign,
		"assets/kenney_city-kit-roads/Models/GLB format/sign-highway.glb",
		1.75,
		.40,
		.75,
		{80, 116, 126, 255},
	},
}
city_furniture_meshes: [len(CITY_FURNITURE_TEMPLATES)]Glb_Mesh
City_Furniture_State :: struct {
	x, y, heading, velocity_x, velocity_y, angular_velocity, roll, pitch: f32,
	kind:                                                                 City_Furniture_Kind,
}

load_city_meshes :: proc() {
	city_ground_mesh = procedural_city_ground_mesh()
	city_background_mesh = procedural_quad_mesh(
		CITY_WORLD_WIDTH + city_world(240),
		CITY_WORLD_HEIGHT + city_world(240),
		true,
	)
	for path, i in CITY_MESH_PATHS {
		loaded: bool
		city_meshes[i], loaded = glb_load(path)
		if !loaded do fmt.eprintln("failed to load city building mesh: ", path)
	}
	for path, i in CITY_ROAD_MESH_PATHS do city_road_meshes[i], _ = glb_load(path)
	for _, i in city_bent_road_meshes do city_bent_road_meshes[i] = procedural_city_road_mesh(i)
	for furniture, i in CITY_FURNITURE_TEMPLATES do city_furniture_meshes[i], _ = glb_load(furniture.path)
	for car, i in CITY_CARS do city_car_meshes[i], _ = glb_load(fmt.tprintf("assets/kenney_car-kit/Models/GLB format/%s.glb", car.model))
}

City_Landmark :: struct {
	x, y, arrival_x, arrival_y, arrival_facing: f32,
	id, name:                                   string,
	case_authored:                              bool,
}
City_Location_Site :: struct {
	x, y, arrival_x, arrival_y, arrival_facing: f32,
	id:                                         string,
}
CITY_DATA_PATH :: "assets/city/landmarks.toml"
CITY_FIXED_LANDMARKS: [dynamic]City_Landmark
CITY_CASE_LOCATION_SITES: [dynamic]City_Location_Site

city_data_initialize :: proc(path: string = CITY_DATA_PATH) -> Validation {
	cpath, error := strings.clone_to_cstring(
		path,
		context.temp_allocator,
	); if error != nil do return {false, "invalid city data path"}
	parsed := toml_parse_file_ex(
		cpath,
	); defer toml_free(parsed); if !parsed.ok do return toml_parse_diagnostic(path, "city data", &parsed)
	top :=
		parsed.toptab; if toml_case_string(top, "version") != "CityFormat v1" do return {false, "unsupported city data format"}
	clear(&CITY_FIXED_LANDMARKS); clear(&CITY_CASE_LOCATION_SITES)
	for table in toml_tables(top, "landmarks") {
		landmark := City_Landmark {
			x              = city_world(level_toml_float(table, "x")),
			y              = city_world(level_toml_float(table, "y")),
			arrival_x      = city_world(level_toml_float(table, "arrival_x")),
			arrival_y      = city_world(level_toml_float(table, "arrival_y")),
			arrival_facing = level_toml_float(table, "arrival_facing"),
			id             = toml_case_string(table, "id"),
			name           = strings.to_upper(toml_case_string(table, "name")),
		}
		if landmark.id == "" || landmark.name == "" do return {false, "city landmark needs an ID and name"}
		if landmark.x < 0 || landmark.y < 0 || landmark.x >= CITY_WORLD_WIDTH || landmark.y >= CITY_WORLD_HEIGHT || landmark.arrival_x < 0 || landmark.arrival_y < 0 || landmark.arrival_x >= CITY_WORLD_WIDTH || landmark.arrival_y >= CITY_WORLD_HEIGHT do return {false, fmt.tprintf("city landmark %s is outside the city", landmark.id)}
		for known in CITY_FIXED_LANDMARKS do if known.id == landmark.id || known.name == landmark.name do return {false, "duplicate city landmark"}
		append(&CITY_FIXED_LANDMARKS, landmark)
	}
	for table in toml_tables(top, "case_sites") {
		site := City_Location_Site {
			x              = city_world(level_toml_float(table, "x")),
			y              = city_world(level_toml_float(table, "y")),
			arrival_x      = city_world(level_toml_float(table, "arrival_x")),
			arrival_y      = city_world(level_toml_float(table, "arrival_y")),
			arrival_facing = level_toml_float(table, "arrival_facing"),
			id             = toml_case_string(table, "id"),
		}
		if site.id == "" do return {false, "city case site needs an ID"}
		for known in CITY_CASE_LOCATION_SITES do if known.id == site.id do return {false, "duplicate city case site"}
		if site.x < 0 || site.y < 0 || site.x >= CITY_WORLD_WIDTH || site.y >= CITY_WORLD_HEIGHT || site.arrival_x < 0 || site.arrival_y < 0 || site.arrival_x >= CITY_WORLD_WIDTH || site.arrival_y >= CITY_WORLD_HEIGHT do return {false, "city case site is outside the city"}
		append(&CITY_CASE_LOCATION_SITES, site)
	}
	if len(CITY_FIXED_LANDMARKS) == 0 || len(CITY_CASE_LOCATION_SITES) == 0 do return {false, "city data needs landmarks and case sites"}
	for landmark in CITY_FIXED_LANDMARKS do if city_wall(landmark.x, landmark.y) || city_wall(landmark.arrival_x, landmark.arrival_y) do return {false, fmt.tprintf("city landmark %s is not reachable", landmark.id)}
	for site in CITY_CASE_LOCATION_SITES do if city_wall(site.x, site.y) || city_wall(site.arrival_x, site.arrival_y) do return {false, "city case site is not reachable"}
	return {true, "CITY DATA VALID"}
}
