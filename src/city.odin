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
CITY_WORLD_WIDTH :: f32(CITY_WIDTH)*CITY_WORLD_SCALE
CITY_WORLD_HEIGHT :: f32(CITY_HEIGHT)*CITY_WORLD_SCALE
city_world :: proc(value:f32)->f32 {return value*CITY_WORLD_SCALE}
city_layout :: proc(value:f32)->f32 {return value/CITY_WORLD_SCALE}

// Broad, gentle landforms give the city readable high and low districts while
// keeping the existing two-dimensional traversal and collision map unchanged.
// The envelope returns to sea level at every city edge, so the authored ground
// still meets the surrounding negative-space plane cleanly.
city_elevation :: proc(x,z:f32)->f32 {
	u:=clamp(x/CITY_WORLD_WIDTH,0,1);v:=clamp(z/CITY_WORLD_HEIGHT,0,1)
	envelope:=f32(math.sin(f64(u*math.PI))*math.sin(f64(v*math.PI)))
	variation:=f32(8)+f32(math.sin(f64(u*math.PI*2)))*2.5-f32(math.cos(f64(v*math.PI*3)))*1.5
	return max(envelope*variation,0)
}

CITY_PLAYER_RADIUS :: f32(.24)
CITY_PLAYER_MAX_STEP_HEIGHT :: f32(.35)

city_triangle_height :: proc(x,z:f32,a,b,c:Vec3)->(f32,bool) {
	denominator:=(b.z-c.z)*(a.x-c.x)+(c.x-b.x)*(a.z-c.z)
	if math.abs(denominator)<.000001 do return 0,false
	u:=((b.z-c.z)*(x-c.x)+(c.x-b.x)*(z-c.z))/denominator
	v:=((c.z-a.z)*(x-c.x)+(a.x-c.x)*(z-c.z))/denominator
	w:=1-u-v
	if u<-.0001||v<-.0001||w<-.0001 do return 0,false
	return u*a.y+v*b.y+w*c.y,true
}

// Roads contain both the carriageway and their raised curb/sidewalk geometry.
// Query the same transformed source tile used to build the render mesh so
// pedestrians stand and step on that geometry instead of passing through it.
city_surface_elevation :: proc(x,z:f32)->f32 {
	result:=city_elevation(x,z)
	layout_x,layout_z:=city_layout(x),city_layout(z)
	tile_x,tile_z:=int(math.floor(f64(layout_x/4)))*4,int(math.floor(f64(layout_z/4)))*4
	center_x,center_z:=tile_x+2,tile_z+2
	if !city_road_cell(center_x,center_z) do return result
	mesh_index,yaw:=city_road_tile(city_road_connection_mask(center_x,center_z))
	if mesh_index<0||mesh_index>=len(city_road_meshes) do return result
	mesh:=&city_road_meshes[mesh_index];if !mesh.ready do return result
	model:=vk_world_model(mesh,city_world(f32(center_x)),city_world(f32(center_z)),0,city_world(4),yaw,0,0,true)
	for triangle:=0;triangle+2<len(mesh.indices);triangle+=3 {
		points:[3]Vec3
		for corner in 0..<3 {
			vertex:=mesh.vertices[mesh.indices[triangle+corner]]
			wx:=model[0]*vertex.x+model[4]*vertex.y+model[8]*vertex.z+model[12]
			wz:=model[2]*vertex.x+model[6]*vertex.y+model[10]*vertex.z+model[14]
			wy:=model[1]*vertex.x+model[5]*vertex.y+model[9]*vertex.z+model[13]+city_elevation(wx,wz)
			points[corner]={wx,wy,wz}
		}
		if height,hit:=city_triangle_height(x,z,points[0],points[1],points[2]);hit do result=max(result,height)
	}
	return result
}

CITY_TERRAIN_STEP :: 8
procedural_city_ground_mesh :: proc()->Glb_Mesh {
	m:Glb_Mesh;columns:=int(CITY_WORLD_WIDTH)/CITY_TERRAIN_STEP+1;rows:=int(CITY_WORLD_HEIGHT)/CITY_TERRAIN_STEP+1
	m.vertices=make([dynamic]Vec3,0,columns*rows);m.texcoords=make([dynamic]Vec2,0,columns*rows);m.indices=make([dynamic]u32,0,(columns-1)*(rows-1)*6);m.primitives=make([dynamic]Glb_Primitive_Range,0,1)
	m.min={-CITY_WORLD_WIDTH*.5,0,-CITY_WORLD_HEIGHT*.5};m.max={CITY_WORLD_WIDTH*.5,0,CITY_WORLD_HEIGHT*.5}
	for row in 0..<rows {for column in 0..<columns {x:=f32(column*CITY_TERRAIN_STEP);z:=f32(row*CITY_TERRAIN_STEP);height:=city_elevation(x,z);append(&m.vertices,Vec3{x-CITY_WORLD_WIDTH*.5,height,z-CITY_WORLD_HEIGHT*.5});append(&m.texcoords,Vec2{x/CITY_WORLD_WIDTH,z/CITY_WORLD_HEIGHT});m.max.y=max(m.max.y,height)}}
	for row in 0..<rows-1 {for column in 0..<columns-1 {a:=u32(row*columns+column);b:=a+1;c:=a+u32(columns);d:=c+1;append(&m.indices,a,d,b,a,c,d)}}
	append(&m.primitives,Glb_Primitive_Range{0,len(m.indices),-1,{1,1,1,1}});m.ready=true;return m
}

CITY_MESH_PATHS := [?]string{
	"assets/kenney_city-kit-suburban_20/Models/GLB format/building-type-a.glb",
	"assets/kenney_city-kit-suburban_20/Models/GLB format/building-type-d.glb",
	"assets/kenney_city-kit-commercial_2.1/Models/GLB format/building-a.glb",
	"assets/kenney_city-kit-commercial_2.1/Models/GLB format/building-j.glb",
	"assets/kenney_city-kit-commercial_2.1/Models/GLB format/building-skyscraper-b.glb",
	"assets/kenney_city-kit-industrial_1.0/Models/GLB format/building-a.glb",
	"assets/kenney_city-kit-industrial_1.0/Models/GLB format/building-r.glb",
}
city_meshes: [len(CITY_MESH_PATHS)]Glb_Mesh
CITY_ROAD_MESH_PATHS := [?]string{
	"assets/kenney_city-kit-roads/Models/GLB format/road-straight.glb",
	"assets/kenney_city-kit-roads/Models/GLB format/road-crossroad.glb",
	"assets/kenney_city-kit-roads/Models/GLB format/road-bend.glb",
	"assets/kenney_city-kit-roads/Models/GLB format/road-intersection.glb",
	"assets/kenney_city-kit-roads/Models/GLB format/road-end.glb",
}
city_road_meshes: [len(CITY_ROAD_MESH_PATHS)]Glb_Mesh
city_bent_road_meshes: [len(CITY_ROAD_MESH_PATHS)]Glb_Mesh
city_ground_mesh,city_background_mesh:Glb_Mesh
city_quest_marker_mesh:Glb_Mesh
city_quest_marker_center:Vec2
city_quest_marker_built:bool

procedural_city_quest_marker_mesh :: proc(center:Vec2,radius:f32)->Glb_Mesh {
	m:Glb_Mesh;segments:=48;outer:=radius;inner:=radius*.68;base:=city_surface_elevation(center.x,center.y)
	m.vertices=make([dynamic]Vec3,0,segments*2);m.texcoords=make([dynamic]Vec2,0,segments*2);m.indices=make([dynamic]u32,0,segments*6);m.primitives=make([dynamic]Glb_Primitive_Range,0,1)
	m.min={-outer,1e30,-outer};m.max={outer,-1e30,outer}
	for i in 0..<segments {angle:=f32(i)*2*f32(math.PI)/f32(segments);c,s:=f32(math.cos(f64(angle))),f32(math.sin(f64(angle)));outer_y:=city_surface_elevation(center.x+c*outer,center.y+s*outer)-base;inner_y:=city_surface_elevation(center.x+c*inner,center.y+s*inner)-base;append(&m.vertices,Vec3{c*outer,outer_y,s*outer},Vec3{c*inner,inner_y,s*inner});append(&m.texcoords,Vec2{(c+1)*.5,(s+1)*.5},Vec2{(c*.68+1)*.5,(s*.68+1)*.5});m.min.y=min(m.min.y,min(outer_y,inner_y));m.max.y=max(m.max.y,max(outer_y,inner_y))}
	for i in 0..<segments {next:=(i+1)%segments;o0,i0,o1,i1:=u32(i*2),u32(i*2+1),u32(next*2),u32(next*2+1);append(&m.indices,o0,i0,i1,o0,i1,o1)}
	append(&m.primitives,Glb_Primitive_Range{0,len(m.indices),-1,{1,1,1,1}});m.ready=true;return m
}

procedural_city_road_mesh :: proc(mesh_index:int)->Glb_Mesh {
	m:Glb_Mesh;if mesh_index<0||mesh_index>=len(city_road_meshes) do return m;source:=&city_road_meshes[mesh_index];if !source.ready do return m
	m.vertices=make([dynamic]Vec3,0);m.texcoords=make([dynamic]Vec2,0);m.indices=make([dynamic]u32,0);m.primitives=make([dynamic]Glb_Primitive_Range,0,len(source.primitives));bases:=make([dynamic]u32,0,256,context.temp_allocator)
	for ty:=0;ty<CITY_HEIGHT;ty+=4 {for tx:=0;tx<CITY_WIDTH;tx+=4 {if !city_road_cell(tx+2,ty+2) do continue;kind,yaw:=city_road_tile(city_road_connection_mask(tx+2,ty+2));if kind!=mesh_index do continue;wx,wz:=city_world(f32(tx+2)),city_world(f32(ty+2));model:=vk_world_model(source,wx,wz,0,city_world(4),yaw,0,0,true);append(&bases,u32(len(m.vertices)));for vertex,i in source.vertices {world_x:=model[0]*vertex.x+model[4]*vertex.y+model[8]*vertex.z+model[12];world_z:=model[2]*vertex.x+model[6]*vertex.y+model[10]*vertex.z+model[14];world_y:=model[1]*vertex.x+model[5]*vertex.y+model[9]*vertex.z+model[13]+city_elevation(world_x,world_z);append(&m.vertices,Vec3{world_x,world_y,world_z});append(&m.texcoords,source.texcoords[i])}}}
	for primitive in source.primitives {first:=len(m.indices);for base in bases {for source_index in source.indices[primitive.first:primitive.first+primitive.count] do append(&m.indices,base+source_index)};append(&m.primitives,Glb_Primitive_Range{first,len(m.indices)-first,primitive.texture,primitive.base_color})}
	if len(m.vertices)==0 do return m;m.min={1e30,1e30,1e30};m.max={-1e30,-1e30,-1e30};for vertex in m.vertices {m.min.x=min(m.min.x,vertex.x);m.min.y=min(m.min.y,vertex.y);m.min.z=min(m.min.z,vertex.z);m.max.x=max(m.max.x,vertex.x);m.max.y=max(m.max.y,vertex.y);m.max.z=max(m.max.z,vertex.z)}
	m.textures=source.textures;m.alpha_modes=source.alpha_modes;m.alpha_cutoffs=source.alpha_cutoffs;m.normal_textures=source.normal_textures;m.roughness_textures=source.roughness_textures;m.metallic_factors=source.metallic_factors;m.roughness_factors=source.roughness_factors;m.normal_scales=source.normal_scales;m.ready=len(m.indices)>0;return m
}

City_Furniture_Kind :: enum {Bench, Planter, Street_Light, Barrier, Cone, Sign}
City_Furniture_Template :: struct {kind:City_Furniture_Kind,path:string,height,radius,mass:f32,tint:[4]u8}
CITY_FURNITURE_TEMPLATES := [?]City_Furniture_Template{
	{.Bench,"assets/kenney_city-kit-suburban_20/Models/GLB format/fence-low.glb",.72,.62,1.15,{116,78,48,255}},
	{.Planter,"assets/kenney_city-kit-suburban_20/Models/GLB format/planter.glb",.78,.46,1.35,{164,151,112,255}},
	{.Street_Light,"assets/kenney_city-kit-roads/Models/GLB format/light-curved.glb",2.8,.32,1.55,{104,116,126,255}},
	{.Barrier,"assets/kenney_city-kit-roads/Models/GLB format/construction-barrier.glb",.92,.66,.88,{238,151,48,255}},
	{.Cone,"assets/kenney_city-kit-roads/Models/GLB format/construction-cone.glb",.62,.28,.30,{242,104,36,255}},
	{.Sign,"assets/kenney_city-kit-roads/Models/GLB format/sign-highway.glb",1.75,.40,.75,{80,116,126,255}},
}
city_furniture_meshes:[len(CITY_FURNITURE_TEMPLATES)]Glb_Mesh
City_Furniture_State :: struct {x,y,heading,velocity_x,velocity_y,angular_velocity,roll,pitch:f32,kind:City_Furniture_Kind}

load_city_meshes :: proc() {
	city_ground_mesh=procedural_city_ground_mesh()
	city_background_mesh=procedural_quad_mesh(CITY_WORLD_WIDTH+city_world(240),CITY_WORLD_HEIGHT+city_world(240),true)
	for path, i in CITY_MESH_PATHS {
		loaded:bool
		city_meshes[i], loaded = glb_load(path)
		if !loaded do fmt.eprintln("failed to load city building mesh: ",path)
	}
	for path, i in CITY_ROAD_MESH_PATHS do city_road_meshes[i], _ = glb_load(path)
	for _,i in city_bent_road_meshes do city_bent_road_meshes[i]=procedural_city_road_mesh(i)
	for furniture,i in CITY_FURNITURE_TEMPLATES do city_furniture_meshes[i],_=glb_load(furniture.path)
	for car,i in CITY_CARS do city_car_meshes[i],_=glb_load(fmt.tprintf("assets/kenney_car-kit/Models/GLB format/%s.glb",car.model))
}

City_Landmark :: struct {x,y,arrival_x,arrival_y,arrival_facing:f32,id,name:string,case_authored:bool}
City_Location_Site :: struct {x,y,arrival_x,arrival_y,arrival_facing:f32,id:string}
CITY_DATA_PATH :: "assets/city/landmarks.toml"
CITY_FIXED_LANDMARKS: [dynamic]City_Landmark
CITY_CASE_LOCATION_SITES: [dynamic]City_Location_Site

city_data_initialize :: proc(path:string=CITY_DATA_PATH)->Validation {
	cpath,error:=strings.clone_to_cstring(path,context.temp_allocator);if error!=nil do return {false,"invalid city data path"}
	parsed:=toml_parse_file_ex(cpath);defer toml_free(parsed);if !parsed.ok do return toml_parse_diagnostic(path,"city data",&parsed)
	top:=parsed.toptab;if toml_case_string(top,"version")!="CityFormat v1" do return {false,"unsupported city data format"}
	clear(&CITY_FIXED_LANDMARKS);clear(&CITY_CASE_LOCATION_SITES)
	for table in toml_tables(top,"landmarks") {
		landmark:=City_Landmark{x=city_world(level_toml_float(table,"x")),y=city_world(level_toml_float(table,"y")),arrival_x=city_world(level_toml_float(table,"arrival_x")),arrival_y=city_world(level_toml_float(table,"arrival_y")),arrival_facing=level_toml_float(table,"arrival_facing"),id=toml_case_string(table,"id"),name=strings.to_upper(toml_case_string(table,"name"))}
		if landmark.id==""||landmark.name=="" do return {false,"city landmark needs an ID and name"}
		if landmark.x<0||landmark.y<0||landmark.x>=CITY_WORLD_WIDTH||landmark.y>=CITY_WORLD_HEIGHT||landmark.arrival_x<0||landmark.arrival_y<0||landmark.arrival_x>=CITY_WORLD_WIDTH||landmark.arrival_y>=CITY_WORLD_HEIGHT do return {false,fmt.tprintf("city landmark %s is outside the city",landmark.id)}
		for known in CITY_FIXED_LANDMARKS do if known.id==landmark.id||known.name==landmark.name do return {false,"duplicate city landmark"}
		append(&CITY_FIXED_LANDMARKS,landmark)
	}
	for table in toml_tables(top,"case_sites") {
		site:=City_Location_Site{x=city_world(level_toml_float(table,"x")),y=city_world(level_toml_float(table,"y")),arrival_x=city_world(level_toml_float(table,"arrival_x")),arrival_y=city_world(level_toml_float(table,"arrival_y")),arrival_facing=level_toml_float(table,"arrival_facing"),id=toml_case_string(table,"id")}
		if site.id=="" do return {false,"city case site needs an ID"}
		for known in CITY_CASE_LOCATION_SITES do if known.id==site.id do return {false,"duplicate city case site"}
		if site.x<0||site.y<0||site.x>=CITY_WORLD_WIDTH||site.y>=CITY_WORLD_HEIGHT||site.arrival_x<0||site.arrival_y<0||site.arrival_x>=CITY_WORLD_WIDTH||site.arrival_y>=CITY_WORLD_HEIGHT do return {false,"city case site is outside the city"}
		append(&CITY_CASE_LOCATION_SITES,site)
	}
	if len(CITY_FIXED_LANDMARKS)==0||len(CITY_CASE_LOCATION_SITES)==0 do return {false,"city data needs landmarks and case sites"}
	for landmark in CITY_FIXED_LANDMARKS do if city_wall(landmark.x,landmark.y)||city_wall(landmark.arrival_x,landmark.arrival_y) do return {false,fmt.tprintf("city landmark %s is not reachable",landmark.id)}
	for site in CITY_CASE_LOCATION_SITES do if city_wall(site.x,site.y)||city_wall(site.arrival_x,site.arrival_y) do return {false,"city case site is not reachable"}
	return {true,"CITY DATA VALID"}
}
City_Car :: struct {x,y:f32,model:string}
Vehicle_Traction_State :: enum {Grip, Slip, Drift, Lock, Spin}
Vehicle_Driver_Assist :: enum {None, ABS, Traction_Control}
Vehicle_State :: struct {
	x,y,heading:f32,
	// speed is the signed driveline speed; velocity carries the car's actual
	// world-space momentum so steering and the handbrake can produce slip.
	speed,steering,velocity_x,velocity_y,yaw_rate,body_roll,body_pitch,handbrake_slip,surface_blend,surface_lateral_bias,acceleration_feedback,chassis_acceleration,chassis_lateral_acceleration,impact,impact_forward,impact_side,impact_time:f32,
	traction_state:Vehicle_Traction_State,
	driver_assist:Vehicle_Driver_Assist,
	driver_assist_strength,driver_assist_time:f32,
}

VEHICLE_SKID_CAPACITY :: 256
VEHICLE_SKID_LIFETIME :: f32(4)
Vehicle_Skid_Mark :: struct {position:Vec2,heading,age,strength:f32,active:bool}

Vehicle_Tune :: struct {
	acceleration,brake,reverse_acceleration,max_forward,max_reverse:f32,
	steering_response,steering_scale,yaw_response,longitudinal_grip,traction_control_floor,lateral_grip,handbrake_grip,coast_retention:f32,
	collision_tangent_retention,collision_rebound,chassis_compliance,mass:f32,
}

City_Driving_Surface :: enum {Road, Open_Ground}

vehicle_tune_for_surface :: proc(tune:Vehicle_Tune,surface:City_Driving_Surface)->Vehicle_Tune {
	if surface==.Road do return tune
	result:=tune
	result.acceleration*=.78;result.max_forward*=.66;result.max_reverse*=.78
	result.steering_scale*=.84;result.yaw_response*=.86;result.longitudinal_grip*=.70;result.lateral_grip*=.70
	return result
}

vehicle_surface_blend_step_to :: proc(current,target_roughness:f32)->f32 {
	target:=clamp(target_roughness,0,1)
	// Grip loads onto rough ground progressively and recovers a little faster
	// on pavement, avoiding a one-frame coefficient jump at road boundaries.
	response:=target>current?f32(.11):f32(.18)
	result:=current+(target-current)*response
	if math.abs(result-target)<.001 do return target
	return clamp(result,0,1)
}
vehicle_surface_blend_step :: proc(current:f32,surface:City_Driving_Surface)->f32 {return vehicle_surface_blend_step_to(current,surface==.Open_Ground?f32(1):f32(0))}
vehicle_surface_bias_step :: proc(current,target_bias:f32)->f32 {
	target:=clamp(target_bias,-1,1);response:=math.abs(target)>math.abs(current)?f32(.18):f32(.22)
	result:=current+(target-current)*response
	if math.abs(result-target)<.001 do return target
	return clamp(result,-1,1)
}

vehicle_surface_contact :: proc(v:Vehicle_State)->(roughness,lateral_bias:f32) {
	// Sample the four tire contact regions instead of classifying the chassis
	// origin. Shoulder crossings then load each axle progressively.
	forward_x:=f32(math.cos(f64(v.heading)));forward_y:=f32(math.sin(f64(v.heading)));right_x,right_y:=-forward_y,forward_x
	right_rough,left_rough:f32;longitudinal_samples:=[2]f32{-.78,.78};lateral_samples:=[2]f32{-.42,.42}
	for longitudinal in longitudinal_samples {
		for lateral in lateral_samples {
			x:=v.x+forward_x*longitudinal+right_x*lateral;y:=v.y+forward_y*longitudinal+right_y*lateral
			if city_driving_surface(x,y)==.Open_Ground {if lateral>0 do right_rough+=.5;else do left_rough+=.5}
		}
	}
	return (right_rough+left_rough)*.5,right_rough-left_rough
}
vehicle_surface_roughness :: proc(v:Vehicle_State)->f32 {roughness,_:=vehicle_surface_contact(v);return roughness}
vehicle_surface_drag_yaw :: proc(v:Vehicle_State,throttle:f32=0)->f32 {
	bias:=clamp(v.surface_lateral_bias,-1,1);longitudinal:=vehicle_longitudinal_speed(v)
	if math.abs(longitudinal)<.04 do return 0
	direction:=longitudinal<0?f32(-1):f32(1);speed_weight:=clamp((math.abs(longitudinal)-.04)/.30,0,1)
	brake_authority:f32
	if math.abs(throttle)>.05 do brake_authority=1-vehicle_requested_drive_authority(v,throttle)
	return bias*direction*speed_weight*.0016*(1+brake_authority*.55)
}

vehicle_tune_for_surface_blend :: proc(tune:Vehicle_Tune,roughness:f32)->Vehicle_Tune {
	rough:=vehicle_tune_for_surface(tune,.Open_Ground);t:=clamp(roughness,0,1);result:=tune
	result.acceleration+=(rough.acceleration-tune.acceleration)*t;result.brake+=(rough.brake-tune.brake)*t;result.reverse_acceleration+=(rough.reverse_acceleration-tune.reverse_acceleration)*t
	result.max_forward+=(rough.max_forward-tune.max_forward)*t;result.max_reverse+=(rough.max_reverse-tune.max_reverse)*t
	result.steering_response+=(rough.steering_response-tune.steering_response)*t;result.steering_scale+=(rough.steering_scale-tune.steering_scale)*t;result.yaw_response+=(rough.yaw_response-tune.yaw_response)*t
	result.longitudinal_grip+=(rough.longitudinal_grip-tune.longitudinal_grip)*t;result.traction_control_floor+=(rough.traction_control_floor-tune.traction_control_floor)*t;result.lateral_grip+=(rough.lateral_grip-tune.lateral_grip)*t;result.handbrake_grip+=(rough.handbrake_grip-tune.handbrake_grip)*t;result.coast_retention+=(rough.coast_retention-tune.coast_retention)*t
	return result
}

city_driving_surface_label :: proc(surface:City_Driving_Surface)->string {return surface==.Road?"ROAD":"ROUGH"}
vehicle_surface_blend_label :: proc(roughness:f32)->string {
	amount:=clamp(roughness,0,1)
	if amount<.20 do return "ROAD"
	if amount>.80 do return "ROUGH"
	return "MIXED"
}

vehicle_analog_curve :: proc(value:f32)->f32 {
	shaped:=clamp(value,-1,1)
	// Retain some linear response around center, then progressively open toward
	// full lock/load. This makes small stick corrections precise without making
	// the outer range feel unresponsive.
	return shaped*(.38+.62*math.abs(shaped))
}

vehicle_analog_deadzone :: proc(value,deadzone:f32)->f32 {
	clamped:=clamp(value,-1,1);magnitude:=math.abs(clamped);zone:=clamp(deadzone,0,.5)
	if magnitude<=zone do return 0
	rescaled:=(magnitude-zone)/(1-zone)
	return clamped<0?-rescaled:rescaled
}

vehicle_gamepad_throttle :: proc(right_trigger_raw,left_trigger_raw:f32)->f32 {
	right_trigger:=vehicle_analog_deadzone(right_trigger_raw,.04);left_trigger:=vehicle_analog_deadzone(left_trigger_raw,.04)
	return vehicle_analog_curve(right_trigger)-vehicle_analog_curve(left_trigger)
}

vehicle_control_inputs :: proc(g:^Game)->(throttle,steering:f32) {
	throttle=vehicle_gamepad_throttle(g.pad_right_trigger,g.pad_left_trigger)
	steering=vehicle_analog_curve(vehicle_analog_deadzone(g.pad_left_x,.08))
	if g.keys[.W]||g.keys[.UP] do throttle+=1
	if g.keys[.S]||g.keys[.DOWN] do throttle-=1
	if g.keys[.A]||g.keys[.LEFT] do steering-=1
	if g.keys[.D]||g.keys[.RIGHT] do steering+=1
	return clamp(throttle,-1,1),clamp(steering,-1,1)
}

vehicle_handbrake_input :: proc(g:^Game)->bool {return g.keys[.SPACE]||g.pad_buttons[.RIGHT_SHOULDER]}

Vehicle_Rear_Light_State :: enum {Off, Brake, Reverse}
vehicle_rear_light_state :: proc(v:Vehicle_State,throttle:f32,handbrake:bool)->Vehicle_Rear_Light_State {
	if handbrake do return .Brake
	longitudinal:=vehicle_longitudinal_speed(v)
	if throttle<-.05 {
		if v.speed>.015||vehicle_direction_change_authority(longitudinal,false)<.5 do return .Brake
		return .Reverse
	}
	if throttle>.05&&(v.speed<-.015||vehicle_direction_change_authority(longitudinal,true)<.5) do return .Brake
	return .Off
}

vehicle_rear_light_intensity :: proc(v:Vehicle_State,throttle:f32,handbrake:bool)->f32 {
	state:=vehicle_rear_light_state(v,throttle,handbrake)
	if state==.Off do return 0
	if state==.Reverse do return .55
	// Keep a readable base glow at the brake threshold, then let analog pedal
	// pressure brighten the lamps. The handbrake remains an unambiguous full cue.
	if handbrake do return .50
	return .20+clamp(math.abs(throttle),0,1)*.30
}

vehicle_engine_load :: proc(v:Vehicle_State,throttle:f32)->f32 {
	load:=clamp(math.abs(throttle),0,1)
	if load==0 do return 0
	// Opposing motion is predominantly braking, but retain a small engine
	// transient and grow load continuously as both wheel and chassis become ready.
	drive_authority:=vehicle_requested_drive_authority(v,throttle)
	result:=load*(.12+drive_authority*.88)
	if v.driver_assist==.Traction_Control do result*=1-clamp(v.driver_assist_strength,0,1)*.28
	return result
}

VEHICLE_TUNE_STANDARD :: Vehicle_Tune{.012,.028,.009,.58,.22,.16,1,.26,1,.62,1,1,.989,.72,.12,1,1}
// The everyday sedan trades the generic arcade-like launch for a progressive
// 0-to-road-speed run. Keep its speed, braking, and handling familiar; only the
// driveline is softened so it still feels responsive once underway.
VEHICLE_TUNE_SEDAN :: Vehicle_Tune{.0012,.028,.003,.58,.22,.16,1,.26,1,.62,1,1,.989,.72,.12,1,1}
VEHICLE_TUNE_SPORT :: Vehicle_Tune{.015,.032,.011,.68,.24,.19,1.12,.32,1.06,.74,1.08,.9,.990,.68,.16,.82,.88}
VEHICLE_TUNE_UTILITY :: Vehicle_Tune{.010,.026,.008,.51,.20,.14,.88,.22,.92,.58,.94,1.05,.992,.76,.10,1.12,1.18}
VEHICLE_TUNE_HEAVY :: Vehicle_Tune{.008,.022,.006,.43,.17,.12,.72,.17,.84,.54,.82,1.14,.994,.82,.07,1.24,1.65}

vehicle_tune :: proc(index:int)->Vehicle_Tune {
	if index<0||index>=len(CITY_CARS) do return VEHICLE_TUNE_STANDARD
	switch CITY_CARS[index].model {
	case "sedan":return VEHICLE_TUNE_SEDAN
	case "race","sedan-sports","hatchback-sports","police":return VEHICLE_TUNE_SPORT
	case "delivery","delivery-flat","van","ambulance","suv","suv-luxury","taxi":return VEHICLE_TUNE_UTILITY
	case "truck","truck-flat","firetruck","garbage-truck","tractor":return VEHICLE_TUNE_HEAVY
	case:return VEHICLE_TUNE_STANDARD
	}
}

vehicle_actual_speed :: proc(v:Vehicle_State)->f32 {
	return f32(math.sqrt(f64(v.velocity_x*v.velocity_x+v.velocity_y*v.velocity_y)))
}

vehicle_longitudinal_speed :: proc(v:Vehicle_State)->f32 {return v.velocity_x*f32(math.cos(f64(v.heading)))+v.velocity_y*f32(math.sin(f64(v.heading)))}
vehicle_direction_label :: proc(v:Vehicle_State)->string {longitudinal:=vehicle_longitudinal_speed(v);if longitudinal<-.02||v.speed<-.02 do return "R";if longitudinal>.02||v.speed>.02 do return "D";return "N"}

vehicle_transmission_label :: proc(v:Vehicle_State,tune:Vehicle_Tune)->string {
	longitudinal:=vehicle_longitudinal_speed(v)
	if math.abs(v.speed)<.015&&math.abs(longitudinal)>.02 do return "N"
	direction:=vehicle_direction_label(v)
	if direction!="D" do return direction
	normalized:=clamp(max(v.speed,longitudinal)/max(tune.max_forward,f32(.01)),0,1)
	gear,_:=vehicle_forward_gear_phase(normalized)
	switch gear {case 0:return "D1";case 1:return "D2";case 2:return "D3";case:return "D4"}
	return "D1"
}

vehicle_reverse_camera_target :: proc(v:Vehicle_State,throttle,current:f32)->f32 {
	longitudinal:=vehicle_longitudinal_speed(v)
	// Follow the same progressive direction-change authority as the driveline;
	// the camera should not announce reverse before reverse torque can engage.
	if throttle<-.1 do return vehicle_direction_change_authority(longitudinal,false)
	if throttle>.1 do return 1-vehicle_direction_change_authority(longitudinal,true)
	// With no directional command, travel hysteresis keeps the orbit stable.
	if longitudinal<-.045 do return 1
	if longitudinal>.045 do return 0
	return current
}

vehicle_lateral_slip_ratio :: proc(v:Vehicle_State)->f32 {
	right_x:=-f32(math.sin(f64(v.heading)));right_y:=f32(math.cos(f64(v.heading)))
	lateral:=math.abs(v.velocity_x*right_x+v.velocity_y*right_y)
	return clamp(lateral/max(vehicle_actual_speed(v),f32(.05)),0,1)
}

vehicle_longitudinal_slip_ratio :: proc(v:Vehicle_State)->f32 {
	longitudinal:=vehicle_longitudinal_speed(v)
	reference:=max(max(math.abs(longitudinal),math.abs(v.speed)),f32(.05))
	return clamp(math.abs(v.speed-longitudinal)/reference,0,1)
}

vehicle_slip_ratio :: proc(v:Vehicle_State)->f32 {return max(vehicle_lateral_slip_ratio(v),vehicle_longitudinal_slip_ratio(v)*.85)}

vehicle_traction_state :: proc(v:Vehicle_State)->Vehicle_Traction_State {
	actual_speed:=vehicle_actual_speed(v);wheel_speed:=math.abs(v.speed)
	if actual_speed<.08&&wheel_speed<.08 do return .Grip
	lateral:=vehicle_lateral_slip_ratio(v);longitudinal:=vehicle_longitudinal_slip_ratio(v)
	if lateral>.52&&actual_speed>=.08 do return .Drift
	if longitudinal>.55 {
		road_speed:=math.abs(vehicle_longitudinal_speed(v))
		if wheel_speed>road_speed+.02 do return .Spin
		return .Lock
	}
	if max(lateral,longitudinal*.85)>.22 do return .Slip
	return .Grip
}

vehicle_traction_state_step :: proc(current:Vehicle_Traction_State,v:Vehicle_State)->Vehicle_Traction_State {
	actual_speed:=vehicle_actual_speed(v);wheel_speed:=math.abs(v.speed);lateral:=vehicle_lateral_slip_ratio(v);longitudinal:=vehicle_longitudinal_slip_ratio(v)
	// Entry uses the regular classifier. Lower release thresholds prevent one
	// noisy sample from flickering the HUD and tire timbre around a boundary.
	switch current {
	case .Drift: if actual_speed>=.07&&lateral>.44 do return .Drift
	case .Spin: if wheel_speed>math.abs(vehicle_longitudinal_speed(v))+.015&&longitudinal>.45 do return .Spin
	case .Lock: if wheel_speed<=math.abs(vehicle_longitudinal_speed(v))+.025&&longitudinal>.45 do return .Lock
	case .Slip: if max(lateral,longitudinal*.85)>.16 do return .Slip
	case .Grip:
	}
	return vehicle_traction_state(v)
}

vehicle_traction_label :: proc(state:Vehicle_Traction_State)->string {
	switch state {case .Grip:return "GRIP";case .Slip:return "SLIP";case .Drift:return "DRIFT";case .Lock:return "LOCK";case .Spin:return "SPIN"}
	return "GRIP"
}

vehicle_tire_audio_frequencies :: proc(v:Vehicle_State)->(low,high:f32) {
	return vehicle_tire_audio_frequencies_for_state(vehicle_traction_state(v))
}
vehicle_tire_audio_frequencies_for_state :: proc(state:Vehicle_Traction_State)->(low,high:f32) {
	switch state {
	case .Lock: return 112,157
	case .Spin: return 218,307
	case .Drift: return 173,241
	case .Slip: return 151,211
	case .Grip: return 151,211
	}
	return 151,211
}

vehicle_tire_audio_frequencies_for_vehicle :: proc(v:Vehicle_State,state:Vehicle_Traction_State,assist:Vehicle_Driver_Assist,strength:f32)->(low,high:f32) {
	low,high=vehicle_tire_audio_frequencies_for_state(state)
	// Pitch rises continuously with scrub severity, making the approach to a
	// traction-state boundary audible instead of relying on a discrete label swap.
	severity:=clamp((vehicle_slip_ratio(v)-.16)/.84,0,1)
	pitch:=1+severity*.10;low*=pitch;high*=pitch
	amount:=clamp(strength,0,1);target_low,target_high:=low,high
	switch assist {case .ABS:target_low,target_high=112,157;case .Traction_Control:target_low,target_high=218,307;case .None:return}
	// At full intervention retain the authored hydraulic/driveline voices exactly;
	// partial intervention blends naturally out of the current tire scrub pitch.
	low+=(target_low-low)*amount;high+=(target_high-high)*amount
	return
}

vehicle_tire_frequency_step :: proc(current,target:f32)->f32 {
	if current<=0 do return target
	return current+(target-current)*.14
}

vehicle_forward_gear_phase :: proc(normalized_speed:f32)->(gear:int,progress:f32) {
	scaled:=(clamp(normalized_speed,.06,1)-.06)/.94*4
	gear=min(int(math.floor(f64(scaled))),3);progress=clamp(scaled-f32(gear),0,1)
	return
}

vehicle_shift_torque_factor :: proc(normalized_speed:f32)->f32 {
	if normalized_speed<=.06 do return 1
	gear,progress:=vehicle_forward_gear_phase(normalized_speed)
	// Unload over the closing slice of each ratio, meeting the following clutch
	// recovery at the same .78 floor. This retains a readable shift without an
	// instantaneous longitudinal-force cliff at the exact boundary.
	if gear<3&&progress>.92 do return 1-clamp((progress-.92)/.08,0,1)*.22
	if gear>0&&progress<.16 do return .78+clamp(progress/.16,0,1)*.22
	return 1
}

vehicle_engine_pitch_scale :: proc(tune:Vehicle_Tune)->f32 {
	// Preserve the standard-car voice exactly. Higher-revving, lighter tunes sit
	// above it; mass and lower road gearing give utility/heavy engines more rumble.
	return clamp(1+(tune.max_forward-VEHICLE_TUNE_STANDARD.max_forward)*.35-(tune.mass-1)*.16,.84,1.07)
}

vehicle_engine_frequency :: proc(v:Vehicle_State,tune:Vehicle_Tune)->f32 {
	pitch:=vehicle_engine_pitch_scale(tune)
	if v.speed<0 {
		normalized:=clamp(math.abs(v.speed)/max(tune.max_reverse,f32(.01)),0,1)
		// Blend the reverse tonal offset in from idle; selecting a 34 Hz base at a
		// tiny negative speed otherwise produces an audible neutral-crossing pop.
		reverse_engagement:=clamp(math.abs(v.speed)/.02,0,1)
		return (30+reverse_engagement*4+normalized*54)*pitch
	}
	normalized:=clamp(v.speed/max(tune.max_forward,f32(.01)),0,1)
	if normalized<.06 do return (30+normalized/.06*22)*pitch
	gear,progress:=vehicle_forward_gear_phase(normalized)
	// Each ratio climbs through a compact band before dropping into the next.
	// The audio stream smooths the discontinuity into a restrained shift event.
	return (52+f32(gear)*4+progress*42)*pitch
}

vehicle_normalized_driveline_speed :: proc(v:Vehicle_State,tune:Vehicle_Tune)->f32 {
	limit:=v.speed<0?tune.max_reverse:tune.max_forward
	return clamp(math.abs(v.speed)/max(limit,f32(.01)),0,1)
}

vehicle_engine_targets :: proc(v:Vehicle_State,tune:Vehicle_Tune,throttle:f32)->(frequency,gain:f32) {
	normalized:=vehicle_normalized_driveline_speed(v,tune)
	// Keep a restrained idle and let both road speed and driver load brighten it.
	frequency=vehicle_engine_frequency(v,tune)
	gain=.022+normalized*.018+vehicle_engine_load(v,throttle)*.028
	return
}

vehicle_tire_audio_target_blended :: proc(v:Vehicle_State,handbrake_amount:f32)->f32 {
	speed_weight:=clamp((vehicle_actual_speed(v)-.07)/.35,0,1)
	slip_weight:=clamp((vehicle_slip_ratio(v)-.16)/.64,0,1)
	handbrake_weight:=clamp((vehicle_actual_speed(v)-.08)/.30,0,1)*.45*clamp(handbrake_amount,0,1)
	slip_weight=max(slip_weight,handbrake_weight)
	return speed_weight*slip_weight*.042
}
vehicle_tire_audio_target :: proc(v:Vehicle_State)->f32 {return vehicle_tire_audio_target_blended(v,0)}

vehicle_rough_feedback_blended :: proc(v:Vehicle_State,roughness:f32)->f32 {
	speed_weight:=clamp((vehicle_actual_speed(v)-.045)/.34,0,1)
	return speed_weight*clamp(roughness,0,1)
}
vehicle_rough_feedback :: proc(v:Vehicle_State,surface:City_Driving_Surface)->f32 {return vehicle_rough_feedback_blended(v,surface==.Open_Ground?f32(1):f32(0))}
vehicle_rough_audio_frequency :: proc(v:Vehicle_State)->f32 {
	speed_weight:=clamp((vehicle_actual_speed(v)-.045)/.34,0,1)
	return 24+speed_weight*52
}

vehicle_longitudinal_load_haptic :: proc(acceleration_feedback:f32)->f32 {
	load:=clamp(acceleration_feedback,-1,1)
	// Braking carries slightly more low-motor weight, matching the larger visual
	// suspension travel while keeping both cues subordinate to terrain/impacts.
	return load<0?-load*.11:load*.08
}
vehicle_cornering_load_haptic :: proc(lateral_acceleration:f32)->f32 {return math.abs(clamp(lateral_acceleration,-1,1))*.06}
vehicle_shift_haptic :: proc(v:Vehicle_State,tune:Vehicle_Tune,drive_demand:f32=1)->f32 {
	demand:=clamp(drive_demand,0,1)
	if v.speed<=0||v.acceleration_feedback<=0||demand==0 do return 0
	normalized:=clamp(v.speed/max(tune.max_forward,f32(.01)),0,1)
	unload:=clamp((1-vehicle_shift_torque_factor(normalized))/.22,0,1)
	return unload*clamp(v.acceleration_feedback,0,1)*demand*.035
}
vehicle_rough_haptic :: proc(v:Vehicle_State,roughness:f32)->f32 {
	base:=vehicle_rough_feedback_blended(v,roughness)
	phase:=v.x*8.3+v.y*5.1+.4
	texture:=.65+math.abs(f32(math.sin(f64(phase))))*.35
	return base*texture*.18
}

vehicle_haptic_strengths_blended :: proc(v:Vehicle_State,roughness,handbrake_amount:f32,tune:Vehicle_Tune=VEHICLE_TUNE_STANDARD,drive_demand:f32=1)->(low,high:f32) {
	rough:=vehicle_rough_haptic(v,roughness)
	slip:=clamp(vehicle_tire_audio_target_blended(v,handbrake_amount)/.042,0,1)
	load:=vehicle_longitudinal_load_haptic(v.acceleration_feedback)+vehicle_shift_haptic(v,tune,drive_demand)
	cornering:=vehicle_cornering_load_haptic(v.chassis_lateral_acceleration)
	// Body motor carries road texture, longitudinal load, and collision weight;
	// the faster motor communicates tire scrub. Impacts briefly dominate both.
	low=clamp(max(max(max(rough,load),cornering),v.impact*.90),0,1)
	high=clamp(max(slip*.25,v.impact*.48),0,1)
	return
}
vehicle_haptic_strengths :: proc(v:Vehicle_State,roughness:f32,handbrake:bool,tune:Vehicle_Tune=VEHICLE_TUNE_STANDARD,drive_demand:f32=1)->(low,high:f32) {return vehicle_haptic_strengths_blended(v,roughness,handbrake?f32(1):f32(0),tune,drive_demand)}
vehicle_assisted_high_haptic :: proc(v:Vehicle_State,high:f32,assist:Vehicle_Driver_Assist,strength,animation_time:f32)->f32 {
	amount:=clamp(strength,0,1);multiplier:=vehicle_assist_haptic_multiplier_blended(assist,amount,animation_time);modulated:=high*multiplier
	// A correction can remove the slip rumble it was modulating. Keep a subtle
	// intervention pulse floor so successful ABS/TC remains tactile instead of
	// disappearing precisely when wheel grip is restored.
	intervention:=assist==.None?f32(0):(1-vehicle_assist_haptic_multiplier(assist,animation_time))*.09*amount
	// Assist pulses belong to tire feedback; never attenuate a simultaneous
	// collision event, which must remain the dominant high-motor cue.
	return max(max(modulated,intervention),clamp(v.impact,0,1)*.48)
}

vehicle_impact_audio_parameters :: proc(impact:f32)->(frequency,gain,duration:f32) {
	strength:=clamp(impact,0,1)
	frequency=92-strength*34;gain=.035+strength*.13;duration=.055+strength*.105
	return
}
vehicle_impact_audio_ready :: proc(impact,cooldown:f32)->bool {return impact>.12&&cooldown<=0}

vehicle_skid_strength_surface_blended :: proc(v:Vehicle_State,handbrake_amount,roughness:f32)->f32 {
	speed_weight:=clamp((vehicle_actual_speed(v)-.10)/.34,0,1)
	traction:=max(vehicle_slip_ratio(v),.52*clamp(handbrake_amount,0,1))
	road_weight:=1-clamp(roughness,0,1)
	return speed_weight*clamp((traction-.18)/.62,0,1)*road_weight
}
vehicle_skid_strength_blended :: proc(v:Vehicle_State,handbrake_amount:f32,surface:City_Driving_Surface)->f32 {return vehicle_skid_strength_surface_blended(v,handbrake_amount,surface==.Open_Ground?f32(1):f32(0))}
vehicle_skid_strength :: proc(v:Vehicle_State,handbrake:bool,surface:City_Driving_Surface)->f32 {return vehicle_skid_strength_blended(v,handbrake?f32(1):f32(0),surface)}
vehicle_front_skid_weight_for_state :: proc(state:Vehicle_Traction_State,handbrake_amount:f32)->f32 {
	if handbrake_amount>.35 do return 0
	return state==.Lock?f32(.82):f32(0)
}
vehicle_front_skid_weight :: proc(v:Vehicle_State,handbrake_amount:f32)->f32 {return vehicle_front_skid_weight_for_state(vehicle_traction_state(v),handbrake_amount)}

vehicle_age_skid_marks :: proc(g:^Game) {for &mark in g.vehicle_skid_marks {if !mark.active do continue;mark.age+=FIXED_TIMESTEP;if mark.age>=VEHICLE_SKID_LIFETIME do mark.active=false}}

vehicle_skid_pending_distance_step :: proc(current,strength:f32)->f32 {
	if strength<=.02 do return 0
	result:=max(current,f32(0))*.65
	if result<.01 do return 0
	return result
}

vehicle_skid_heading :: proc(v:Vehicle_State)->f32 {
	if vehicle_actual_speed(v)<.01 do return v.heading
	return f32(math.atan2(f64(v.velocity_y),f64(v.velocity_x)))
}

vehicle_update_skid_marks_blended :: proc(g:^Game,v:Vehicle_State,handbrake_amount,roughness:f32,resolved_movement:Vec2={},movement_resolved:bool=false,resolved_travel_distance:f32=-1) {
	strength:=vehicle_skid_strength_surface_blended(v,handbrake_amount,roughness)
	if strength<=.08 {g.vehicle_skid_emit_distance=vehicle_skid_pending_distance_step(g.vehicle_skid_emit_distance,strength);return}
	movement:=resolved_movement
	if !movement_resolved do movement={v.velocity_x,v.velocity_y}
	movement_distance:=f32(math.sqrt(f64(movement.x*movement.x+movement.y*movement.y)));travel_distance:=movement_distance
	if resolved_travel_distance>=0 do travel_distance=resolved_travel_distance
	g.vehicle_skid_emit_distance+=travel_distance
	if g.vehicle_skid_emit_distance<.72 do return
	// Preserve distance beyond the spacing threshold so changing speed does not
	// stretch the trail. Cap exceptional collision overshoot to one pending mark.
	overshoot:=min(g.vehicle_skid_emit_distance-.72,f32(.71));g.vehicle_skid_emit_distance=overshoot
	// The threshold is usually crossed between fixed ticks. Back-project along
	// resolved travel so the mark lands at that crossing instead of the frame end.
	emit_x,emit_y:=v.x,v.y
	if movement_distance>.001 {emit_x-=movement.x/movement_distance*overshoot;emit_y-=movement.y/movement_distance*overshoot}
	forward:=Vec2{f32(math.cos(f64(v.heading))),f32(math.sin(f64(v.heading)))};side:=Vec2{-forward.y,forward.x};rear:=Vec2{emit_x-forward.x*.72,emit_y-forward.y*.72}
	track_heading:=vehicle_skid_heading(v)
	signs:=[2]f32{-1,1};for sign in signs {index:=g.vehicle_skid_next%VEHICLE_SKID_CAPACITY;g.vehicle_skid_marks[index]={position={rear.x+side.x*.34*sign,rear.y+side.y*.34*sign},heading=track_heading,age=0,strength=strength,active=true};g.vehicle_skid_next=(g.vehicle_skid_next+1)%VEHICLE_SKID_CAPACITY}
	front_weight:=vehicle_front_skid_weight_for_state(v.traction_state,handbrake_amount)
	if front_weight>0 {front:=Vec2{emit_x+forward.x*.72,emit_y+forward.y*.72};for sign in signs {index:=g.vehicle_skid_next%VEHICLE_SKID_CAPACITY;g.vehicle_skid_marks[index]={position={front.x+side.x*.34*sign,front.y+side.y*.34*sign},heading=track_heading,age=0,strength=strength*front_weight,active=true};g.vehicle_skid_next=(g.vehicle_skid_next+1)%VEHICLE_SKID_CAPACITY}}
}
vehicle_update_skid_marks :: proc(g:^Game,v:Vehicle_State,handbrake:bool,surface:City_Driving_Surface) {vehicle_update_skid_marks_blended(g,v,handbrake?f32(1):f32(0),surface==.Open_Ground?f32(1):f32(0))}

vehicle_combined_grip_factor :: proc(longitudinal_impulse:f32)->f32 {
	// Keep enough lateral authority for an arcade response, but reserve part of
	// the tire budget in proportion to force actually transmitted. Using raw
	// wheel-speed error would charge low-grip tires for force they cannot produce.
	return 1-clamp(longitudinal_impulse/.075,0,1)*.34
}

vehicle_longitudinal_grip_response :: proc(handbrake_amount:f32,tune:Vehicle_Tune)->f32 {
	release:=clamp(handbrake_amount,0,1)
	normal:=f32(.34)*tune.longitudinal_grip;loose:=f32(.16)*tune.longitudinal_grip
	return normal+(loose-normal)*release
}

vehicle_longitudinal_tire_impulse :: proc(v:Vehicle_State,handbrake_amount:f32,tune:Vehicle_Tune)->f32 {
	longitudinal:=vehicle_longitudinal_speed(v)
	demand:=math.abs(v.speed-longitudinal)
	return demand*vehicle_longitudinal_grip_response(handbrake_amount,tune)
}

vehicle_lateral_grip_budget :: proc(v:Vehicle_State,handbrake_amount:f32,tune:Vehicle_Tune)->f32 {
	// One shared arcade rule: wheel lock/spin spends some cornering authority, but
	// never enough to make the car unsteerable. ABS and TC restore this naturally
	// by reducing the wheel/chassis speed mismatch.
	return vehicle_combined_grip_factor(vehicle_longitudinal_tire_impulse(v,handbrake_amount,tune))
}

vehicle_handbrake_slip_step_tuned :: proc(current:f32,pressed:bool,tune:Vehicle_Tune)->f32 {
	target:=pressed?f32(1):f32(0);release_response:=clamp(.10/max(tune.chassis_compliance,f32(.2)),.075,.125);response:=target>current?f32(.38):release_response
	result:=current+(target-current)*response
	if math.abs(result-target)<.001 do return target
	return clamp(result,0,1)
}
vehicle_handbrake_slip_step :: proc(current:f32,pressed:bool)->f32 {return vehicle_handbrake_slip_step_tuned(current,pressed,VEHICLE_TUNE_STANDARD)}

vehicle_apply_tire_grip_blended :: proc(v:^Vehicle_State,handbrake_amount:f32,tune:Vehicle_Tune) {
	forward_x:=f32(math.cos(f64(v.heading)));forward_y:=f32(math.sin(f64(v.heading)))
	right_x,right_y:=-forward_y,forward_x
	longitudinal:=v.velocity_x*forward_x+v.velocity_y*forward_y
	lateral:=v.velocity_x*right_x+v.velocity_y*right_y
	release:=clamp(handbrake_amount,0,1)
	// Longitudinal grip keeps the throttle responsive while lateral grip is
	// allowed to break away independently. A handbrake mostly releases the rear
	// tires instead of making the engine feel disconnected from the wheels.
	longitudinal_grip:=vehicle_longitudinal_grip_response(release,tune)
	normal_lateral:=clamp(.24-math.abs(longitudinal)*.18,.13,.24)*tune.lateral_grip*vehicle_lateral_grip_budget(v^,release,tune);loose_lateral:=f32(.035)*tune.handbrake_grip;lateral_grip:=normal_lateral+(loose_lateral-normal_lateral)*release
	longitudinal+=(v.speed-longitudinal)*longitudinal_grip
	lateral*=1-lateral_grip
	v.velocity_x=forward_x*longitudinal+right_x*lateral
	v.velocity_y=forward_y*longitudinal+right_y*lateral
}
vehicle_apply_tire_grip :: proc(v:^Vehicle_State,handbrake:bool,tune:Vehicle_Tune) {vehicle_apply_tire_grip_blended(v,handbrake?f32(1):f32(0),tune)}
vehicle_should_settle_velocity :: proc(v:Vehicle_State)->bool {return math.abs(v.speed)<.001&&vehicle_actual_speed(v)<.012}

vehicle_self_aligning_yaw_blended :: proc(v:Vehicle_State,handbrake_amount:f32,tune:Vehicle_Tune)->f32 {
	actual_speed:=vehicle_actual_speed(v)
	if actual_speed<.055 do return 0
	forward_x:=f32(math.cos(f64(v.heading)));forward_y:=f32(math.sin(f64(v.heading)))
	right_x,right_y:=-forward_y,forward_x
	longitudinal:=v.velocity_x*forward_x+v.velocity_y*forward_y
	lateral:=v.velocity_x*right_x+v.velocity_y*right_y
	// In reverse the body should align opposite the velocity vector, so the
	// correction changes sign with longitudinal travel. Handbrake grip loss
	// deliberately leaves only a trace of this restoring torque.
	direction:=longitudinal<0?f32(-1):f32(1)
	slip:=clamp(lateral/actual_speed,-1,1)
	speed_weight:=clamp((actual_speed-.055)/.30,0,1)
	release:=1-clamp(handbrake_amount,0,1)*.78
	// Aligning torque is generated by the same contact patch as lateral force.
	// Wheel lock/spin therefore weakens it, while ABS/TC can restore it by bringing
	// wheel speed back toward chassis travel.
	grip_budget:=vehicle_lateral_grip_budget(v,handbrake_amount,tune)
	return slip*direction*speed_weight*.010*tune.lateral_grip*release*grip_budget
}
vehicle_self_aligning_yaw :: proc(v:Vehicle_State,handbrake:bool,tune:Vehicle_Tune)->f32 {return vehicle_self_aligning_yaw_blended(v,handbrake?f32(1):f32(0),tune)}

vehicle_yaw_load_factor :: proc(v:Vehicle_State,throttle:f32,handbrake:bool)->f32 {
	if handbrake do return 1
	load:=clamp(math.abs(throttle),0,1)
	// Use the least-aligned wheel/chassis motion so either can identify braking,
	// then ramp around neutral instead of flipping load transfer in one tick.
	alignment:=min(v.speed*throttle,vehicle_longitudinal_speed(v)*throttle)
	power_weight:=clamp(alignment/.03,0,1);brake_weight:=clamp(-alignment/.03,0,1)
	return 1-load*.06*power_weight+load*.10*brake_weight
}

vehicle_steering_yaw_speed :: proc(speed:f32)->f32 {
	// Tire steering has useful leverage as soon as a car begins creeping. The
	// simulation's compact speed scale otherwise makes parking turn-in feel numb.
	// Fade the boost in from rest and away by ordinary street speed; a hard creep
	// threshold would turn tiny velocity noise into a sudden steering snap.
	magnitude:=math.abs(speed)
	if magnitude==0 do return 0
	creep_ramp:=clamp(magnitude/.016,0,1)
	boost:=(1-clamp(magnitude/.10,0,1))*.024*creep_ramp
	return speed<0?-(magnitude+boost):magnitude+boost
}

vehicle_steering_travel_speed :: proc(v:Vehicle_State)->f32 {
	// Steering geometry acts on ground travel, not wheel/driveline rotation.
	// This preserves direction control during braking and neutral coasting while
	// preventing a stationary burnout from rotating the whole chassis.
	return vehicle_steering_yaw_speed(vehicle_longitudinal_speed(v))
}

vehicle_steering_lateral_grip_factor :: proc(v:Vehicle_State,steering:f32)->f32 {
	// Lateral saturation should soften added lock into a slide, giving the limit
	// a progressive understeer shoulder. Countersteer keeps full authority because
	// it is unloading the existing slip angle rather than asking for more of it.
	if vehicle_is_countersteering(v,steering) do return 1
	slip:=vehicle_lateral_slip_ratio(v)
	return 1-clamp((slip-.18)/.62,0,1)*.28
}

vehicle_apply_yaw_blended :: proc(v:^Vehicle_State,handbrake_amount:f32,tune:Vehicle_Tune,throttle:f32=0) {
	steering_speed:=vehicle_steering_travel_speed(v^)
	release:=clamp(handbrake_amount,0,1);normal_load:=vehicle_yaw_load_factor(v^,throttle,false);load_factor:=normal_load+(1-normal_load)*release;yaw_leverage:=1+release*.32
	// Steering rotation and lateral force must spend the same tire budget. This
	// keeps a locked or spinning wheel from yawing the body as though it still had
	// full cornering authority, while an ABS/TC correction restores turn-in.
	steering_grip:=vehicle_lateral_grip_budget(v^,release,tune)*vehicle_steering_lateral_grip_factor(v^,v.steering)
	target:=v.steering*steering_speed*.075*yaw_leverage*load_factor*steering_grip+vehicle_self_aligning_yaw_blended(v^,release,tune)+vehicle_surface_drag_yaw(v^,throttle)
	// Rear grip loss lets rotation persist, while normal tires settle the body
	// promptly. Archetype response gives sports cars crisp turn-in and keeps
	// heavy vehicles deliberate without changing input semantics.
	response:=tune.yaw_response*(1-release*.45)
	v.yaw_rate+=(target-v.yaw_rate)*response
	v.yaw_rate=clamp(v.yaw_rate,-.045,.045)
	if math.abs(v.speed)<.004&&math.abs(target)<.0001 do v.yaw_rate*=.72
	v.heading+=v.yaw_rate
}
vehicle_apply_yaw :: proc(v:^Vehicle_State,handbrake:bool,tune:Vehicle_Tune,throttle:f32=0) {vehicle_apply_yaw_blended(v,handbrake?f32(1):f32(0),tune,throttle)}

vehicle_body_roll_target_blended :: proc(v:Vehicle_State,handbrake_amount:f32,tune:Vehicle_Tune=VEHICLE_TUNE_STANDARD)->f32 {
	// Measured lateral tire force supplies the real weight transfer. A restrained
	// yaw contribution preserves readable passive collision rotation without
	// making a freely sliding body lean as though it still had full grip.
	speed_weight:=clamp(vehicle_actual_speed(v)/.46,0,1)
	force_turn:=clamp(v.chassis_lateral_acceleration,-1,1)
	travel_direction:=clamp(vehicle_longitudinal_speed(v)/.04,-1,1)
	rotation_turn:=clamp(v.yaw_rate/.045,-1,1)*travel_direction
	turn_weight:=clamp(force_turn+rotation_turn*.25,-1,1)
	roll_limit:=.068+(.095-.068)*clamp(handbrake_amount,0,1)
	return -turn_weight*speed_weight*roll_limit*tune.chassis_compliance
}
vehicle_body_roll_target :: proc(v:Vehicle_State,handbrake:bool,tune:Vehicle_Tune=VEHICLE_TUNE_STANDARD)->f32 {return vehicle_body_roll_target_blended(v,handbrake?f32(1):f32(0),tune)}

vehicle_update_body_roll_blended :: proc(v:^Vehicle_State,handbrake_amount:f32,tune:Vehicle_Tune=VEHICLE_TUNE_STANDARD) {
	target:=vehicle_body_roll_target_blended(v^,handbrake_amount,tune)
	compliance_response:=clamp(1/max(tune.chassis_compliance,f32(.2)),.76,1.28)
	release_response:=target==0?f32(.14):f32(.10)
	response:=vehicle_feedback_response(v.body_roll,target,.16,release_response)*compliance_response
	v.body_roll+=(target-v.body_roll)*response
	if math.abs(v.body_roll)<.0001&&math.abs(target)<.0001 do v.body_roll=0
}
vehicle_update_body_roll :: proc(v:^Vehicle_State,handbrake:bool,tune:Vehicle_Tune=VEHICLE_TUNE_STANDARD) {vehicle_update_body_roll_blended(v,handbrake?f32(1):f32(0),tune)}

vehicle_body_pitch_target :: proc(acceleration_feedback:f32,tune:Vehicle_Tune=VEHICLE_TUNE_STANDARD)->f32 {
	load:=clamp(acceleration_feedback,-1,1)
	// Launch raises the nose; braking gets slightly more travel so a firm stop
	// reads clearly without turning the chassis into a cartoon hinge.
	return load*(load>=0?f32(.038):f32(.052))*tune.chassis_compliance
}

vehicle_update_body_pitch :: proc(v:^Vehicle_State,tune:Vehicle_Tune=VEHICLE_TUNE_STANDARD) {
	target:=vehicle_body_pitch_target(v.chassis_acceleration,tune)
	compliance_response:=clamp(1/max(tune.chassis_compliance,f32(.2)),.76,1.28)
	response:=vehicle_feedback_response(v.body_pitch,target,.16,.11)*compliance_response
	v.body_pitch+=(target-v.body_pitch)*response
	if math.abs(v.body_pitch)<.0001&&math.abs(target)<.0001 do v.body_pitch=0
}

vehicle_handbrake_drag_factor :: proc(lateral_slip,roughness:f32)->f32 {
	slip:=clamp(lateral_slip,0,1);surface:=clamp(roughness,0,1)
	road:=.968-slip*.022;rough:=.962-slip*.012
	return road+(rough-road)*surface
}

vehicle_drag_factor_blended :: proc(tune:Vehicle_Tune,roughness,handbrake_amount,throttle,lateral_slip,normalized_speed:f32)->f32 {
	// Lift-off drag grows gently with road speed, providing a readable corner-
	// entry weight shift without making parking-lot coasting feel sticky. Powered
	// running retains the existing low-loss driveline response.
	coast_aero:=clamp((normalized_speed-.25)/.75,0,1)*.003
	coast:=tune.coast_retention-coast_aero
	powered_weight:=clamp(math.abs(throttle)/.12,0,1)
	road:=coast+(.994-coast)*powered_weight
	// Rough ground keeps strong lift-off loss, while powered retention rises just
	// enough for reduced surface torque to sustain the authored terrain speed.
	rough_retention:=.972+powered_weight*.010
	normal:=road+(rough_retention-road)*clamp(roughness,0,1)
	handbrake:=vehicle_handbrake_drag_factor(lateral_slip,roughness)
	return normal+(handbrake-normal)*clamp(handbrake_amount,0,1)
}
vehicle_drag_factor :: proc(tune:Vehicle_Tune,roughness:f32,handbrake:bool,throttle:f32,lateral_slip:f32=0,normalized_speed:f32=0)->f32 {return vehicle_drag_factor_blended(tune,roughness,handbrake?f32(1):f32(0),throttle,lateral_slip,normalized_speed)}

vehicle_steering_response :: proc(tune:Vehicle_Tune,normalized_speed,steer_input:f32,current_steering:f32=0)->f32 {
	response:=tune.steering_response
	// Self-centering and tiny corrections need a quicker rack than full turn-in,
	// but the transition must remain continuous around stick center.
	center_weight:=1-clamp(math.abs(steer_input)/.20,0,1)
	response*=1+center_weight*(.35+clamp(normalized_speed,0,1)*.65)
	// An intentional direction reversal should cross the rack center promptly;
	// otherwise rapid corrections feel like they spend a beat fighting stale
	// steering. Keep normal turn-in unchanged and retain the global response cap.
	opposition:=max(-steer_input*current_steering,f32(0))
	reversal_weight:=clamp(opposition/.12,0,1)
	response*=1+reversal_weight*.28
	return min(response,f32(.42))
}

vehicle_reverse_steering_weight :: proc(v:Vehicle_State)->f32 {
	longitudinal:=vehicle_longitudinal_speed(v)
	// Chassis travel owns direction once established. Near rest, a restrained
	// wheel-speed contribution anticipates the selected direction without a sign
	// threshold that would make available steering lock jump at zero velocity.
	wheel_authority:=1-clamp(math.abs(longitudinal)/.02,0,1)
	direction_signal:=longitudinal+v.speed*.15*wheel_authority
	return clamp((.02-direction_signal)/.04,0,1)
}

vehicle_normalized_steering_speed :: proc(v:Vehicle_State,tune:Vehicle_Tune)->f32 {
	// Road speed governs safe steering lock. Retain a smaller wheel-speed
	// contribution so a stationary burnout does not instantly command full lock,
	// but never let locked wheels disguise a fast-moving chassis as stationary.
	reference:=max(vehicle_actual_speed(v),math.abs(v.speed)*.45)
	// Reverse has a lower authored speed ceiling. Normalizing it against forward
	// top speed leaves far too much steering lock at maximum reversing speed. A
	// blended limit keeps direction changes continuous through neutral.
	reverse_weight:=vehicle_reverse_steering_weight(v)
	limit:=tune.max_forward+(tune.max_reverse-tune.max_forward)*reverse_weight
	return clamp(reference/max(limit,f32(.01)),0,1)
}

vehicle_is_countersteering :: proc(v:Vehicle_State,steer_input:f32)->bool {
	right_x:=-f32(math.sin(f64(v.heading)));right_y:=f32(math.cos(f64(v.heading)))
	lateral:=v.velocity_x*right_x+v.velocity_y*right_y
	return math.abs(lateral)>.01&&steer_input*lateral>0
}

vehicle_steering_limit :: proc(tune:Vehicle_Tune,normalized_speed,handbrake_amount:f32,countersteering:bool=false)->f32 {
	base:=clamp((.9-clamp(normalized_speed,0,1)*.44)*tune.steering_scale,.32,.98)
	// Rear grip release needs additional countersteer range at speed. Keep the
	// gain modest and bounded so the handbrake never restores twitchy full lock.
	if !countersteering do return base
	return clamp(base+clamp(handbrake_amount,0,1)*.12,.32,.98)
}

vehicle_stability_assist_scale :: proc(tune:Vehicle_Tune)->f32 {
	// Preserve the standard tune as the handling baseline. Agile cars leave more
	// recovery to the driver, while slower, heavier archetypes get a calmer and
	// more assertive safety net without changing their authored tire grip.
	return clamp(1+(VEHICLE_TUNE_STANDARD.yaw_response-tune.yaw_response)*2+(tune.mass-VEHICLE_TUNE_STANDARD.mass)*.08,.84,1.16)
}

vehicle_stability_steering_blended :: proc(v:Vehicle_State,handbrake_amount:f32,tune:Vehicle_Tune=VEHICLE_TUNE_STANDARD)->f32 {
	actual_speed:=vehicle_actual_speed(v)
	if actual_speed<.10 do return 0
	forward_x:=f32(math.cos(f64(v.heading)));forward_y:=f32(math.sin(f64(v.heading)));right_x,right_y:=-forward_y,forward_x
	longitudinal:=v.velocity_x*forward_x+v.velocity_y*forward_y
	lateral:=v.velocity_x*right_x+v.velocity_y*right_y
	signed_slip:=clamp(lateral/max(actual_speed,f32(.05)),-1,1);slip:=math.abs(signed_slip)
	assist_recovery:=1-clamp(handbrake_amount,0,1)
	slip_steering:=signed_slip*clamp((slip-.18)/.62,0,1)*.26
	// Slip steering points the nose back toward travel. Once that angle is nearly
	// recovered, compare remaining body rotation with the yaw still required and
	// counter only the excess so a released drift does not coast into a spin.
	direction:=longitudinal<0?f32(-1):f32(1)
	speed_authority:=clamp((actual_speed-.10)/.22,0,1)
	desired_yaw:=signed_slip*direction*speed_authority*.025
	yaw_excess:=v.yaw_rate-desired_yaw
	spin_gate:=clamp((math.abs(v.yaw_rate)-.012)/.028,0,1)*clamp((slip-.04)/.22,0,1)
	spin_steering:=-clamp(yaw_excess/.032,-1,1)*direction*spin_gate*.12
	// Apply the same ramp to all recovery torque. Without it, slip steering jumps
	// from zero to useful authority on the first tick above the speed threshold.
	assist_scale:=vehicle_stability_assist_scale(tune)
	return clamp((slip_steering+spin_steering)*assist_recovery*speed_authority*assist_scale,-.26*assist_scale,.26*assist_scale)
}
vehicle_stability_steering :: proc(v:Vehicle_State,handbrake:bool,tune:Vehicle_Tune=VEHICLE_TUNE_STANDARD)->f32 {return vehicle_stability_steering_blended(v,handbrake?f32(1):f32(0),tune)}

vehicle_assisted_steering_input :: proc(v:Vehicle_State,driver_input,handbrake_amount:f32,tune:Vehicle_Tune=VEHICLE_TUNE_STANDARD)->f32 {
	// Fade recovery authority out across useful stick travel instead of dropping
	// it at a tiny input threshold. This keeps micro-corrections continuous while
	// ensuring a deliberate steering command always owns the front wheels.
	authority:=1-clamp(math.abs(driver_input)/.35,0,1)
	assist:=vehicle_stability_steering_blended(v,handbrake_amount,tune)*authority
	return clamp(driver_input+assist,-1,1)
}

vehicle_drive_torque_for_reference :: proc(tune,driveline_tune:Vehicle_Tune,speed:f32,forward:bool)->f32 {
	limit:=forward?driveline_tune.max_forward:driveline_tune.max_reverse
	normalized:=clamp(math.abs(speed)/max(limit,f32(.01)),0,1)
	// A little launch punch makes leaving a stop decisive; tapering the upper
	// range makes reaching maximum speed feel earned instead of linear.
	result:=(forward?tune.acceleration:tune.reverse_acceleration)*(1.18-normalized*.62)
	if forward do result*=vehicle_shift_torque_factor(normalized)
	// Surface limits are sustainable speeds, not velocity clamps. Above a lower
	// surface limit, taper drive force over a short band while preserving momentum.
	surface_limit:=forward?tune.max_forward:tune.max_reverse
	if surface_limit<limit {
		taper_range:=max(surface_limit*.12,f32(.01))
		result*=1-clamp((math.abs(speed)-surface_limit)/taper_range,0,1)
	}
	return result
}
vehicle_drive_torque :: proc(tune:Vehicle_Tune,speed:f32,forward:bool)->f32 {return vehicle_drive_torque_for_reference(tune,tune,speed,forward)}

vehicle_service_brake_factor :: proc(v:Vehicle_State)->f32 {
	slip:=vehicle_longitudinal_slip_ratio(v)
	// Full pressure remains below the lock threshold. Beyond it, progressively
	// release at most 42% so braking stays strong while tires regain authority.
	return 1-clamp((slip-.18)/.62,0,1)*.42
}

vehicle_service_brake_pressure :: proc(v:Vehicle_State)->f32 {
	pressure:=vehicle_service_brake_factor(v)
	// Retained ABS strength acts as a short hydraulic memory. After a release has
	// recovered wheel speed, pressure reapplies progressively instead of snapping
	// to 100% for one tick and immediately locking the wheel again.
	if v.driver_assist==.ABS do pressure*=1-clamp(v.driver_assist_strength,0,1)*.12
	return pressure
}

vehicle_apply_abs_release :: proc(v:^Vehicle_State,brake_authority:f32) {
	authority:=clamp(brake_authority,0,1)
	if authority<=0 do return
	longitudinal:=vehicle_longitudinal_speed(v^)
	// ABS only releases a wheel lagging chassis travel; a spinning drive wheel is
	// traction control's domain. Moving toward road speed creates a real re-lock
	// cycle on the following brake tick instead of leaving the wheel at zero.
	if math.abs(v.speed)>=math.abs(longitudinal)-.001||v.speed*longitudinal<0 do return
	// Normalize the pressure modulation into lock severity. Multiplying the raw
	// 42% pressure release by another response coefficient left a fully locked
	// wheel with too little correction to recover meaningful steering authority.
	severity:=clamp((1-vehicle_service_brake_factor(v^))/.42,0,1)
	release:=severity*.62*authority
	v.speed+=(longitudinal-v.speed)*release
}

vehicle_traction_control_factor :: proc(v:Vehicle_State,tune:Vehicle_Tune)->f32 {
	wheel_speed:=math.abs(v.speed);road_speed:=math.abs(vehicle_longitudinal_speed(v))
	if wheel_speed<=road_speed+.02 do return 1
	slip:=vehicle_longitudinal_slip_ratio(v)
	return 1-clamp((slip-.20)/.60,0,1)*(1-clamp(tune.traction_control_floor,0,1))
}

vehicle_traction_control_drive_factor :: proc(v:Vehicle_State,tune:Vehicle_Tune)->f32 {
	factor:=vehicle_traction_control_factor(v,tune)
	// Wheel trim can momentarily clear the slip threshold. Retain a modest part
	// of the previous torque cut so the following tick does not jump straight to
	// full power and re-spin the tire. Fresh severe slip still cuts immediately.
	if v.driver_assist==.Traction_Control {
		retained:=1-clamp(v.driver_assist_strength,0,1)*(1-clamp(tune.traction_control_floor,0,1))*.24
		factor=min(factor,retained)
	}
	return factor
}

vehicle_traction_control_trim_response :: proc(tune:Vehicle_Tune)->f32 {
	// The torque floor describes how permissive the driveline is, while this
	// response determines how decisively an already-spinning wheel is reined in.
	// Sport cars retain more wheelspin; heavy vehicles trade flair for stability.
	return clamp(.68+(VEHICLE_TUNE_STANDARD.traction_control_floor-tune.traction_control_floor)*1.4,.54,.80)
}

vehicle_apply_traction_control :: proc(v:^Vehicle_State,tune:Vehicle_Tune,drive_authority:f32) {
	authority:=clamp(drive_authority,0,1)
	if authority<=0 do return
	longitudinal:=vehicle_longitudinal_speed(v^);wheel_speed:=math.abs(v.speed);road_speed:=math.abs(longitudinal)
	if wheel_speed<=road_speed+.02||v.speed*longitudinal<0 do return
	intervention:=1-vehicle_traction_control_factor(v^,tune)
	range:=max(1-clamp(tune.traction_control_floor,0,1),f32(.001))
	// Normalize out the torque-retention floor so severe slip can genuinely
	// recover tire budget instead of receiving only a small cosmetic correction.
	severity:=clamp(intervention/range,0,1)
	v.speed+=(longitudinal-v.speed)*severity*vehicle_traction_control_trim_response(tune)*authority
}

vehicle_driver_assist_blended :: proc(v:Vehicle_State,tune:Vehicle_Tune,throttle,handbrake_amount:f32)->(assist:Vehicle_Driver_Assist,strength:f32) {
	authority:=1-clamp(handbrake_amount,0,1)
	if math.abs(throttle)<=.05 do return .None,0
	drive_authority:=vehicle_requested_drive_authority(v,throttle);brake_authority:=1-drive_authority
	// Service-brake ABS remains independent of the mechanically locked rear axle;
	// handbrake slip only gates traction-control authority.
	strength=clamp((1-vehicle_service_brake_factor(v))/.42,0,1)*brake_authority
	if strength>.005 do return .ABS,strength
	tc:=vehicle_traction_control_factor(v,tune);range:=max(1-tune.traction_control_floor,f32(.001));strength=clamp((1-tc)/range,0,1)*authority*drive_authority
	if strength>.005 do return .Traction_Control,strength
	return .None,0
}
vehicle_driver_assist :: proc(v:Vehicle_State,tune:Vehicle_Tune,throttle:f32,handbrake:bool)->Vehicle_Driver_Assist {if handbrake do return .None;assist,_:=vehicle_driver_assist_blended(v,tune,throttle,0);return assist}
vehicle_driver_assist_label :: proc(assist:Vehicle_Driver_Assist)->string {switch assist {case .ABS:return "ABS";case .Traction_Control:return "TC";case .None:return ""};return ""}
vehicle_driver_assist_indicator_color :: proc(strength:f32)->[4]u8 {
	amount:=clamp(strength,0,1);idle:=[4]u8{145,153,162,255};active:=[4]u8{255,211,92,255};result:=idle
	for i in 0..<3 do result[i]=u8(f32(idle[i])+(f32(active[i])-f32(idle[i]))*amount)
	return result
}
vehicle_driver_assist_state_step :: proc(current:Vehicle_Driver_Assist,current_strength:f32,detected:Vehicle_Driver_Assist,detected_strength:f32,handbrake_amount:f32=0)->(assist:Vehicle_Driver_Assist,strength:f32) {
	if detected!=.None {
		strength=clamp(detected_strength,0,1)
		if detected==current do strength=max(strength,clamp(current_strength,0,1)*.72)
		return detected,strength
	}
	if current==.Traction_Control&&handbrake_amount>.35 do return .None,0
	strength=clamp(current_strength,0,1)*.72
	if current==.None||strength<.03 do return .None,0
	return current,strength
}
vehicle_assist_haptic_multiplier :: proc(assist:Vehicle_Driver_Assist,animation_time:f32)->f32 {
	switch assist {
	case .ABS:return .55+math.abs(f32(math.sin(f64(animation_time*48))))*.45
	case .Traction_Control:return .72+math.abs(f32(math.sin(f64(animation_time*30))))*.28
	case .None:return 1
	}
	return 1
}
vehicle_assist_haptic_multiplier_blended :: proc(assist:Vehicle_Driver_Assist,strength,animation_time:f32)->f32 {pulse:=vehicle_assist_haptic_multiplier(assist,animation_time);return 1+(pulse-1)*clamp(strength,0,1)}

vehicle_assist_audio_gain :: proc(assist:Vehicle_Driver_Assist,strength,assist_time:f32)->f32 {
	if assist==.None do return 0
	depth:=1-vehicle_assist_haptic_multiplier(assist,assist_time)
	// Share intervention phase with haptics. ABS has a sharper hydraulic chatter;
	// TC remains a quieter driveline texture beneath its engine-load reduction.
	peak:=assist==.ABS?f32(.025):f32(.020)
	return depth*clamp(strength,0,1)*peak
}

vehicle_direction_change_authority :: proc(longitudinal_speed:f32,forward:bool)->f32 {
	opposing_speed:=forward?-longitudinal_speed:longitudinal_speed
	return 1-clamp(max(opposing_speed,f32(0))/.015,0,1)
}
vehicle_requested_drive_authority :: proc(v:Vehicle_State,throttle:f32)->f32 {
	if math.abs(throttle)<=.001 do return 0
	forward:=throttle>0
	return min(vehicle_direction_change_authority(v.speed,forward),vehicle_direction_change_authority(vehicle_longitudinal_speed(v),forward))
}

vehicle_apply_throttle_assisted :: proc(v:^Vehicle_State,tune,driveline_tune:Vehicle_Tune,throttle,traction_control_amount:f32) {
	longitudinal:=vehicle_longitudinal_speed(v^)
	if throttle>.001 {
		if v.speed<0 {v.speed=min(v.speed+tune.brake*vehicle_service_brake_pressure(v^)*throttle,f32(0))}
		else {tc:=vehicle_traction_control_drive_factor(v^,driveline_tune);assist:=1+(tc-1)*clamp(traction_control_amount,0,1);direction_authority:=vehicle_direction_change_authority(longitudinal,true);v.speed=min(v.speed+vehicle_drive_torque_for_reference(tune,driveline_tune,v.speed,true)*assist*throttle*direction_authority,driveline_tune.max_forward)}
	} else if throttle<-.001 {
		if v.speed>0 {v.speed=max(v.speed+tune.brake*vehicle_service_brake_pressure(v^)*throttle,f32(0))}
		else {tc:=vehicle_traction_control_drive_factor(v^,driveline_tune);assist:=1+(tc-1)*clamp(traction_control_amount,0,1);direction_authority:=vehicle_direction_change_authority(longitudinal,false);v.speed=max(v.speed+vehicle_drive_torque_for_reference(tune,driveline_tune,v.speed,false)*assist*throttle*direction_authority,-driveline_tune.max_reverse)}
	}
}
vehicle_apply_throttle_for_reference :: proc(v:^Vehicle_State,tune,driveline_tune:Vehicle_Tune,throttle:f32,traction_control:bool=true) {vehicle_apply_throttle_assisted(v,tune,driveline_tune,throttle,traction_control?f32(1):f32(0))}
vehicle_apply_throttle :: proc(v:^Vehicle_State,tune:Vehicle_Tune,throttle:f32) {vehicle_apply_throttle_for_reference(v,tune,tune,throttle)}
city_landmark_count :: proc(g:^Game)->int {payload:=mystery_game_payload(g);return len(CITY_FIXED_LANDMARKS)+(payload==nil?0:min(len(payload.city_labels),len(CITY_CASE_LOCATION_SITES)))}
city_fixed_landmark_id_exists :: proc(id:string)->bool {for landmark in CITY_FIXED_LANDMARKS do if landmark.id==id do return true;return false}
city_fixed_landmark_name_exists :: proc(name:string)->bool {candidate:=strings.to_upper(name);for landmark in CITY_FIXED_LANDMARKS do if landmark.name==candidate do return true;return false}
city_case_site_id_exists :: proc(id:string)->bool {for site in CITY_CASE_LOCATION_SITES do if site.id==id do return true;return false}
city_case_site :: proc(id:string)->(City_Location_Site,bool) {for site in CITY_CASE_LOCATION_SITES do if site.id==id do return site,true;return {},false}
city_landmark_at :: proc(g:^Game,index:int)->(City_Landmark,bool) {
	if index>=0&&index<len(CITY_FIXED_LANDMARKS) do return CITY_FIXED_LANDMARKS[index],true
	payload:=mystery_game_payload(g);case_index:=index-len(CITY_FIXED_LANDMARKS);if payload==nil||case_index<0||case_index>=len(payload.city_labels)||case_index>=len(CITY_CASE_LOCATION_SITES) do return {},false
	location:=payload.city_labels[case_index];site,found:=city_case_site(location.city_site);if !found do return {},false;return {x=site.x,y=site.y,arrival_x=site.arrival_x,arrival_y=site.arrival_y,arrival_facing=site.arrival_facing,id=location.id,name=strings.to_upper(location.display_name),case_authored=true},true
}
city_landmark_index :: proc(g:^Game,id:string)->int {for i in 0..<city_landmark_count(g) {landmark,ok:=city_landmark_at(g,i);if ok&&landmark.id==id do return i};return -1}
city_place_at_landmark :: proc(g:^Game,id:string)->bool {
	index:=city_landmark_index(g,id);if index<0 do return false
	landmark,_:=city_landmark_at(g,index);g.city_x=landmark.arrival_x;g.city_y=landmark.arrival_y;g.city_angle=landmark.arrival_facing*f32(math.PI)/180
	g.city_camera_x=g.city_x;g.city_camera_y=g.city_y;g.city_camera_initialized=true
	// Arrival facings are authored toward the destination. Put the aerial boom
	// behind that facing so the first exterior frame reveals the surrounding
	// street wall instead of looking diagonally through the widest road opening.
	g.camera_orbit=g.city_angle+f32(math.PI);g.camera_zoom=id=="police_station"?f32(1.15):f32(.82);g.camera_orbit_initialized=true
	return true
}
case_city_location :: proc(g:^Game,id:string)->(^Mystery_City_Label,bool) {payload:=mystery_game_payload(g);if payload!=nil {for &location in payload.city_labels do if location.id==id do return &location,true};return nil,false}

CITY_CARS := [?]City_Car{
	{17.4,42.0,"sedan"},{19.8,52.0,"hatchback-sports"},{33.2,66.0,"suv"},{48.0,81.2,"taxi"},
	{78.0,33.2,"delivery"},{81.3,50.0,"sedan-sports"},{96.8,67.0,"police"},{113.3,82.0,"van"},
	{132.0,17.2,"suv-luxury"},{145.5,33.4,"ambulance"},{161.3,48.0,"firetruck"},{177.8,65.4,"garbage-truck"},
	{34.0,97.4,"taxi"},{66.7,113.2,"truck"},{98.2,129.3,"truck-flat"},{129.8,114.0,"delivery-flat"},
	{145.5,129.4,"tractor"},{177.2,145.3,"race"},{18.2,23.5,"police"},
	// A small station motor pool, parked along the curb without blocking the
	// station arrival point at (49.5, 58.5).
	{49.0,53.5,"police"},{51.0,63.0,"police"},{49.0,68.0,"police"},
}
city_car_meshes: [len(CITY_CARS)]Glb_Mesh

initialize_city_vehicles :: proc(g:^Game) {
	if g.vehicles==nil do g.vehicles=make([dynamic]Vehicle_State,len(CITY_CARS),len(CITY_CARS))
	for car,i in CITY_CARS {
		heading:f32=0
		if int(car.x)%CITY_BLOCK<4 do heading=f32(math.PI/2)
		g.vehicles[i]={x=city_world(car.x),y=city_world(car.y),heading=heading}
	}
	g.vehicles_initialized=true
}

city_furniture_template :: proc(kind:City_Furniture_Kind)->City_Furniture_Template {return CITY_FURNITURE_TEMPLATES[int(kind)]}

initialize_city_furniture :: proc(g:^Game) {
	if g.city_furniture==nil do g.city_furniture=make([dynamic]City_Furniture_State,0,96)
	clear(&g.city_furniture)
	// Populate curb edges deterministically. Each candidate remains on traversable
	// ground, beside a solid block, and clear of parked cars and landmark arrivals.
	for iy in 2..<CITY_HEIGHT-2 {for ix in 2..<CITY_WIDTH-2 {
		if len(g.city_furniture)>=72||!city_road_cell(ix,iy) do continue
		hash:=ix*73856093~iy*19349663
		if hash%43!=0 do continue
		edge_x,edge_y:f32
		if city_developed_lot_cell(ix-1,iy) do edge_x=-.30
		else if city_developed_lot_cell(ix+1,iy) do edge_x=.30
		else if city_developed_lot_cell(ix,iy-1) do edge_y=-.30
		else if city_developed_lot_cell(ix,iy+1) do edge_y=.30
		else do continue
		x,y:=city_world(f32(ix)+.5+edge_x),city_world(f32(iy)+.5+edge_y)
		if city_wall(x,y) do continue
		blocked:=false
		for car in CITY_CARS {dx,dy:=x-city_world(car.x),y-city_world(car.y);if dx*dx+dy*dy<3.2*3.2 do blocked=true}
		for landmark in CITY_FIXED_LANDMARKS {dx,dy:=x-landmark.arrival_x,y-landmark.arrival_y;if dx*dx+dy*dy<3.5*3.5 do blocked=true}
		for prop in g.city_furniture {dx,dy:=x-prop.x,y-prop.y;if dx*dx+dy*dy<2.2*2.2 do blocked=true}
		if blocked do continue
		kind:=City_Furniture_Kind(hash%len(CITY_FURNITURE_TEMPLATES));heading:=edge_x!=0?f32(math.PI/2):f32(0)
		append(&g.city_furniture,City_Furniture_State{x=x,y=y,heading=heading,kind=kind})
	}}
	g.city_furniture_initialized=true
}

city_furniture_index_at :: proc(g:^Game,x,y:f32,ignore:int=-1)->int {
	for prop,i in g.city_furniture {if i==ignore do continue;radius:=city_furniture_template(prop.kind).radius;dx,dy:=x-prop.x,y-prop.y;if dx*dx+dy*dy<radius*radius do return i}
	return -1
}

vehicle_collision_furniture_index :: proc(g:^Game,x,y,heading:f32)->int {
	forward_x,forward_y:=f32(math.cos(f64(heading))),f32(math.sin(f64(heading)));right_x,right_y:=-forward_y,forward_x
	longitudinal_samples:=[3]f32{-1.05,0,1.05};lateral_samples:=[3]f32{-.48,0,.48}
	for longitudinal in longitudinal_samples {for lateral in lateral_samples {hit:=city_furniture_index_at(g,x+forward_x*longitudinal+right_x*lateral,y+forward_y*longitudinal+right_y*lateral);if hit>=0 do return hit}}
	return -1
}

city_car_index_at :: proc(g:^Game,x,y:f32,ignore:int=-1)->int {for car,i in g.vehicles {if i==ignore do continue;dx:=x-car.x;dy:=y-car.y;if dx*dx+dy*dy<0.9*0.9 do return i};return -1}
city_car_at :: proc(g:^Game,x,y:f32,ignore:int=-1)->bool {return city_car_index_at(g,x,y,ignore)>=0}

vehicle_collision_car_index :: proc(g:^Game,x,y,heading:f32,index:int)->int {
	forward_x,forward_y:=math.cos(heading),math.sin(heading);right_x,right_y:=-forward_y,forward_x
	longitudinal_samples:=[3]f32{-1.05,0,1.05};lateral_samples:=[2]f32{-0.48,0.48}
	for longitudinal in longitudinal_samples {for lateral in lateral_samples {sx:=x+forward_x*longitudinal+right_x*lateral;sy:=y+forward_y*longitudinal+right_y*lateral;hit:=city_car_index_at(g,sx,sy,index);if hit>=0 do return hit}}
	return -1
}

vehicle_position_clear :: proc(g:^Game,x,y,heading:f32,index:int)->bool {
	if vehicle_collision_furniture_index(g,x,y,heading)>=0 do return false
	forward_x,forward_y:=math.cos(heading),math.sin(heading);right_x,right_y:=-forward_y,forward_x
	longitudinal_samples:=[3]f32{-1.05,0,1.05};lateral_samples:=[2]f32{-0.48,0.48}
	for longitudinal in longitudinal_samples {for lateral in lateral_samples {sx:=x+forward_x*longitudinal+right_x*lateral;sy:=y+forward_y*longitudinal+right_y*lateral;if city_wall(sx,sy)||city_car_at(g,sx,sy,index)||city_furniture_index_at(g,sx,sy)>=0 do return false}}
	return true
}

vehicle_sync_driveline_to_velocity :: proc(v:^Vehicle_State) {
	v.speed=vehicle_longitudinal_speed(v^)
	if math.abs(v.speed)<.001 do v.speed=0
}

vehicle_feedback_response :: proc(current,target,attack,release:f32)->f32 {
	if current*target<0||math.abs(target)>math.abs(current) do return attack
	return release
}

vehicle_update_acceleration_feedback_targets :: proc(v:^Vehicle_State,target,chassis_target,lateral_target:f32) {
	response:=vehicle_feedback_response(v.acceleration_feedback,target,.24,.14)
	v.acceleration_feedback+=(target-v.acceleration_feedback)*response
	if math.abs(v.acceleration_feedback)<.001&&target==0 do v.acceleration_feedback=0
	chassis_response:=vehicle_feedback_response(v.chassis_acceleration,chassis_target,.24,.14)
	v.chassis_acceleration+=(chassis_target-v.chassis_acceleration)*chassis_response
	if math.abs(v.chassis_acceleration)<.001&&chassis_target==0 do v.chassis_acceleration=0
	lateral_response:=vehicle_feedback_response(v.chassis_lateral_acceleration,lateral_target,.28,.18)
	v.chassis_lateral_acceleration+=(lateral_target-v.chassis_lateral_acceleration)*lateral_response
	if math.abs(v.chassis_lateral_acceleration)<.001&&lateral_target==0 do v.chassis_lateral_acceleration=0
}

vehicle_update_acceleration_feedback_from_velocity :: proc(v:^Vehicle_State,before_x,before_y:f32,collided:bool) {
	target,chassis_target,lateral_target:f32
	forward_x,forward_y:=f32(math.cos(f64(v.heading))),f32(math.sin(f64(v.heading)));right_x,right_y:=-forward_y,forward_x
	delta_x,delta_y:=v.velocity_x-before_x,v.velocity_y-before_y
	if collided {
		// Swept contact already recorded the strongest lateral impulse directly.
		lateral_target=v.chassis_lateral_acceleration
	} else {
		lateral_target=clamp((delta_x*right_x+delta_y*right_y)/.018,-1,1)
		before_speed:=f32(math.sqrt(f64(before_x*before_x+before_y*before_y)));after_speed:=vehicle_actual_speed(v^)
		target=clamp((after_speed-before_speed)/.024,-1,1)
		chassis_target=clamp((delta_x*forward_x+delta_y*forward_y)/.024,-1,1)
	}
	vehicle_update_acceleration_feedback_targets(v,target,chassis_target,lateral_target)
}

vehicle_update_acceleration_feedback :: proc(v:^Vehicle_State,longitudinal_before:f32,collided:bool) {
	forward_x,forward_y:=f32(math.cos(f64(v.heading))),f32(math.sin(f64(v.heading)))
	vehicle_update_acceleration_feedback_from_velocity(v,forward_x*longitudinal_before,forward_y*longitudinal_before,collided)
}

vehicle_collision_transfer_factor :: proc(source_tune,target_tune:Vehicle_Tune)->f32 {
	// Momentum transfer follows archetype inertia independently of restitution:
	// a truck should shove a sports car harder even if both contacts slide alike.
	return clamp(.20*source_tune.mass/max(target_tune.mass,f32(.1)),.12,.32)
}

vehicle_collision_rebound :: proc(source_tune,target_tune:Vehicle_Tune)->f32 {
	// A light car should recoil more from a heavy target, while a truck striking
	// a light body should carry through. Walls continue using the authored base.
	mass_response:=clamp(target_tune.mass/max(source_tune.mass,f32(.1)),.65,1.45)
	return clamp(source_tune.collision_rebound*mass_response,.04,.24)
}

vehicle_resolve_car_contact_velocity :: proc(relative_x,relative_y,normal_x,normal_y,tangent_retention,rebound:f32)->Vec2 {
	length:=f32(math.sqrt(f64(normal_x*normal_x+normal_y*normal_y)))
	if length<=.0001 do return {-relative_x*rebound,-relative_y*rebound}
	nx,ny:=normal_x/length,normal_y/length
	normal_speed:=relative_x*nx+relative_y*ny
	// Only reverse motion closing into the contact. A separating velocity can be
	// observed when another body has already transferred momentum this tick.
	if normal_speed>=0 do return {relative_x,relative_y}
	tangent_x,tangent_y:=relative_x-nx*normal_speed,relative_y-ny*normal_speed
	return {tangent_x*tangent_retention-nx*normal_speed*rebound,tangent_y*tangent_retention-ny*normal_speed*rebound}
}

vehicle_car_contact_transfer :: proc(relative_x,relative_y,normal_x,normal_y,transfer:f32)->Vec2 {
	length:=f32(math.sqrt(f64(normal_x*normal_x+normal_y*normal_y)))
	if length<=.0001 do return {}
	nx,ny:=normal_x/length,normal_y/length
	normal_speed:=relative_x*nx+relative_y*ny
	if normal_speed>=0 do return {}
	tangent_x,tangent_y:=relative_x-nx*normal_speed,relative_y-ny*normal_speed
	amount:=clamp(transfer,0,1)
	// Closing speed delivers the shove; only restrained tire/body friction carries
	// scrape-direction motion into the struck vehicle.
	return {-nx*(-normal_speed)*amount+tangent_x*amount*.18,-ny*(-normal_speed)*amount+tangent_y*amount*.18}
}

vehicle_car_contact_tangent_step :: proc(step_x,step_y,normal_x,normal_y:f32)->Vec2 {
	length:=f32(math.sqrt(f64(normal_x*normal_x+normal_y*normal_y)))
	if length<=.0001 do return {}
	nx,ny:=normal_x/length,normal_y/length
	normal_step:=step_x*nx+step_y*ny
	return {step_x-nx*normal_step,step_y-ny*normal_step}
}

vehicle_wall_tangent_retention :: proc()->f32 {
	// Static walls should redirect a glancing car, not repeatedly scrub away its
	// parallel speed. A high retention lets the body slide clear while the small
	// normal rebound still creates separation before the next fixed tick.
	return .94
}

vehicle_collision_yaw_impulse :: proc(source,target:Vehicle_State,incoming_x,incoming_y,transfer:f32)->f32 {
	// The center offset approximates the contact lever arm. A centered, straight
	// impact produces no spin, while a glancing hit rotates the struck chassis in
	// the direction of the delivered impulse. Keep it restrained so contact never
	// turns a parked car into a pinwheel.
	rx,ry:=source.x-target.x,source.y-target.y
	return clamp((rx*incoming_y-ry*incoming_x)*transfer*.10,-.12,.12)
}

vehicle_collision_yaw_rate :: proc(current,impulse:f32)->f32 {
	// Repeated contacts in a pileup may arrive before passive damping runs. Cap
	// the accumulated body rotation as well as each impulse to prevent pinwheels.
	return clamp(current+impulse,-.12,.12)
}

vehicle_impact_strength_from_delta :: proc(delta_x,delta_y:f32)->f32 {
	return clamp(f32(math.sqrt(f64(delta_x*delta_x+delta_y*delta_y)))/.58,0,1)
}

vehicle_impact_is_new_event :: proc(current_impact,new_strength:f32)->bool {
	amount:=clamp(new_strength,0,1)
	return current_impact<=.002||amount>current_impact+.20
}

vehicle_record_impact :: proc(v:^Vehicle_State,delta_x,delta_y,strength:f32) {
	amount:=clamp(strength,0,1)
	if amount+f32(.0001)>=v.impact {
		magnitude:=f32(math.sqrt(f64(delta_x*delta_x+delta_y*delta_y)))
		if magnitude>.0001 {
			forward_x,forward_y:=f32(math.cos(f64(v.heading))),f32(math.sin(f64(v.heading)));right_x,right_y:=-forward_y,forward_x
			v.impact_forward=clamp((delta_x*forward_x+delta_y*forward_y)/magnitude,-1,1)
			v.impact_side=clamp((delta_x*right_x+delta_y*right_y)/magnitude,-1,1)
		}
		// Comparable contact on consecutive ticks refreshes strength and direction
		// without pinning the directional camera wave at sin(0). Restart only for a
		// fresh pulse, a materially stronger hit, or after the prior pulse has run.
		if vehicle_impact_is_new_event(v.impact,amount)||v.impact_time>.09 do v.impact_time=0
	}
	v.impact=max(v.impact,amount)
}

vehicle_record_collision_lateral_load :: proc(v:^Vehicle_State,delta_x,delta_y:f32) {
	right_x:=-f32(math.sin(f64(v.heading)));right_y:=f32(math.cos(f64(v.heading)))
	load:=clamp((delta_x*right_x+delta_y*right_y)/.018,-1,1)
	if math.abs(load)>math.abs(v.chassis_lateral_acceleration) do v.chassis_lateral_acceleration=load
}

vehicle_decay_impact :: proc(v:^Vehicle_State) {
	if v.impact>0 do v.impact_time+=FIXED_TIMESTEP
	v.impact*=.82
	if v.impact<.002 {v.impact=0;v.impact_forward=0;v.impact_side=0;v.impact_time=0}
}

vehicle_collision_pitch_impulse :: proc(v:Vehicle_State,delta_x,delta_y:f32,tune:Vehicle_Tune)->f32 {
	forward_x,forward_y:=f32(math.cos(f64(v.heading))),f32(math.sin(f64(v.heading)))
	longitudinal_delta:=delta_x*forward_x+delta_y*forward_y
	return clamp(longitudinal_delta*.055*tune.chassis_compliance,-.065,.065)
}

vehicle_advance_resolved_collision_motion :: proc(g:^Game,v:^Vehicle_State,index,remaining_steps,total_steps:int)->int {
	if remaining_steps<=0||total_steps<=0 do return 0
	step_x,step_y:=v.velocity_x/f32(total_steps),v.velocity_y/f32(total_steps)
	advanced:=0
	for _ in 0..<remaining_steps {
		nx,ny:=v.x+step_x,v.y+step_y
		if !vehicle_position_clear(g,nx,ny,v.heading,index) do break
		v.x,v.y=nx,ny;advanced+=1
	}
	return advanced
}

vehicle_swept_move :: proc(g:^Game,v:^Vehicle_State,index:int,transfer_impulse:bool=true,impact_event:^f32=nil,travel_event:^f32=nil)->bool {
	distance:=vehicle_actual_speed(v^)
	if travel_event!=nil do travel_event^=0
	if distance<=.00001 do return false
	// Keep each collision probe comfortably below the narrowest vehicle sample
	// spacing. This prevents a fast car from stepping through parked traffic or
	// clipping across a building corner between frames.
	steps:=max(1,int(math.ceil(f64(distance/.10))))
	step_x,step_y:=v.velocity_x/f32(steps),v.velocity_y/f32(steps)
	step_distance:=f32(math.sqrt(f64(step_x*step_x+step_y*step_y)));traveled:f32
	collision_tune:=vehicle_tune(index)
	for step_index in 0..<steps {
		nx,ny:=v.x+step_x,v.y+step_y
		if !vehicle_position_clear(g,nx,ny,v.heading,index) {
			hit_index:=vehicle_collision_car_index(g,nx,ny,v.heading,index)
			hit_furniture:=vehicle_collision_furniture_index(g,nx,ny,v.heading)
			rebound:=collision_tune.collision_rebound;if hit_index>=0 do rebound=vehicle_collision_rebound(collision_tune,vehicle_tune(hit_index))
			if hit_furniture>=0 do rebound=.06
			incoming_x,incoming_y:=v.velocity_x,v.velocity_y
			contact_base_x,contact_base_y:f32
			if hit_index>=0 {contact_base_x=g.vehicles[hit_index].velocity_x;contact_base_y=g.vehicles[hit_index].velocity_y}
			if hit_furniture>=0 {contact_base_x=g.city_furniture[hit_furniture].velocity_x;contact_base_y=g.city_furniture[hit_furniture].velocity_y}
			relative_x,relative_y:=incoming_x-contact_base_x,incoming_y-contact_base_y
			// Resolve a glancing contact along whichever world axis remains clear.
			// This preserves tangential motion against long walls and parked cars;
			// a corner that blocks both axes still receives the compact rebound.
			x_clear:=math.abs(step_x)>.00001&&vehicle_position_clear(g,v.x+step_x,v.y,v.heading,index)
			y_clear:=math.abs(step_y)>.00001&&vehicle_position_clear(g,v.x,v.y+step_y,v.heading,index)
			contact_normal_x,contact_normal_y:f32
			if hit_index>=0||hit_furniture>=0 {
				// Vehicle contacts use their center line as the normal, making glancing
				// response rotationally consistent instead of dependent on world axes.
				if hit_index>=0 {contact_normal_x,contact_normal_y=v.x-g.vehicles[hit_index].x,v.y-g.vehicles[hit_index].y}
				else {contact_normal_x,contact_normal_y=v.x-g.city_furniture[hit_furniture].x,v.y-g.city_furniture[hit_furniture].y}
				tangent_step:=vehicle_car_contact_tangent_step(step_x,step_y,contact_normal_x,contact_normal_y)
				if tangent_step.x*tangent_step.x+tangent_step.y*tangent_step.y>.0000001&&vehicle_position_clear(g,v.x+tangent_step.x,v.y+tangent_step.y,v.heading,index) {v.x+=tangent_step.x;v.y+=tangent_step.y;traveled+=f32(math.sqrt(f64(tangent_step.x*tangent_step.x+tangent_step.y*tangent_step.y)))}
				resolved:=vehicle_resolve_car_contact_velocity(relative_x,relative_y,contact_normal_x,contact_normal_y,collision_tune.collision_tangent_retention,rebound)
				v.velocity_x=contact_base_x+resolved.x;v.velocity_y=contact_base_y+resolved.y
				tangent_speed:=math.abs(relative_x*contact_normal_y-relative_y*contact_normal_x)
				if tangent_speed>.001 do v.yaw_rate*=.42;else do v.yaw_rate*= -.22
			} else if x_clear&&!y_clear {
				v.x+=step_x;traveled+=math.abs(step_x);v.velocity_x=contact_base_x+relative_x*vehicle_wall_tangent_retention();v.velocity_y=contact_base_y-relative_y*rebound;v.yaw_rate*=.42
			} else if y_clear&&!x_clear {
				v.y+=step_y;traveled+=math.abs(step_y);v.velocity_x=contact_base_x-relative_x*rebound;v.velocity_y=contact_base_y+relative_y*vehicle_wall_tangent_retention();v.yaw_rate*=.42
			} else {
				v.velocity_x=contact_base_x-relative_x*rebound;v.velocity_y=contact_base_y-relative_y*rebound;v.yaw_rate*= -.22
			}
			// Camera, haptics, and audio should follow the acceleration occupants feel,
			// not merely closing speed. Mass-aware carry-through therefore reads softer
			// than a large recoil even when both contacts begin at the same speed.
			delta_velocity_x,delta_velocity_y:=v.velocity_x-incoming_x,v.velocity_y-incoming_y
			if hit_index>=0 {
				// The same off-center impulse that spins the struck body also acts at a
				// lever arm on the source. Derive reaction torque from its resolved delta
				// so carry-through and recoil produce proportionate rotation.
				reaction_factor:=vehicle_collision_transfer_factor(vehicle_tune(hit_index),collision_tune)
				reaction_yaw:=vehicle_collision_yaw_impulse(g.vehicles[hit_index],v^,delta_velocity_x,delta_velocity_y,reaction_factor)
				v.yaw_rate=vehicle_collision_yaw_rate(v.yaw_rate,reaction_yaw)
			}
			contact_impact:=vehicle_impact_strength_from_delta(delta_velocity_x,delta_velocity_y);new_audio_impact:=vehicle_impact_is_new_event(v.impact,contact_impact);vehicle_record_impact(v,delta_velocity_x,delta_velocity_y,contact_impact);if impact_event!=nil do impact_event^=new_audio_impact?contact_impact:f32(0)
			vehicle_record_collision_lateral_load(v,delta_velocity_x,delta_velocity_y)
			// The tire model must inherit the direction and magnitude that survived
			// contact; retaining the pre-impact wheel speed pulls the car back into
			// the obstacle on the following simulation tick.
			v.body_pitch+=vehicle_collision_pitch_impulse(v^,v.velocity_x-incoming_x,v.velocity_y-incoming_y,collision_tune)
			v.body_pitch=clamp(v.body_pitch,-.075,.075)
			vehicle_sync_driveline_to_velocity(v)
			if transfer_impulse&&hit_index>=0 {
				target:=&g.vehicles[hit_index]
				transfer:=vehicle_collision_transfer_factor(collision_tune,vehicle_tune(hit_index))
				yaw_impulse:=vehicle_collision_yaw_impulse(v^,target^,relative_x,relative_y,transfer);target.yaw_rate=vehicle_collision_yaw_rate(target.yaw_rate,yaw_impulse)
				// Use the same pre-slide contact normal as source rebound. Recomputing
				// after tangential advancement makes the two bodies solve different frames.
				delta:=vehicle_car_contact_transfer(relative_x,relative_y,contact_normal_x,contact_normal_y,transfer);delta_x,delta_y:=delta.x,delta.y
				target.body_pitch+=vehicle_collision_pitch_impulse(target^,delta_x,delta_y,vehicle_tune(hit_index));target.body_pitch=clamp(target.body_pitch,-.075,.075)
				target.velocity_x+=delta_x;target.velocity_y+=delta_y
				target_impact:=vehicle_impact_strength_from_delta(delta_x,delta_y);vehicle_record_impact(target,delta_x,delta_y,target_impact)
				vehicle_record_collision_lateral_load(target,delta_x,delta_y)
				vehicle_sync_driveline_to_velocity(target)
			}
			if transfer_impulse&&hit_furniture>=0 {
				prop:=&g.city_furniture[hit_furniture];template:=city_furniture_template(prop.kind)
				normal_length:=f32(math.sqrt(f64(contact_normal_x*contact_normal_x+contact_normal_y*contact_normal_y)));if normal_length<.001 do normal_length=1
				nx_contact,ny_contact:=contact_normal_x/normal_length,contact_normal_y/normal_length
				closing:=max(0,-(relative_x*nx_contact+relative_y*ny_contact));transfer:=clamp(collision_tune.mass/(collision_tune.mass+template.mass)*1.35,.28,1.05)
				impulse:=closing*transfer;prop.velocity_x-=nx_contact*impulse;prop.velocity_y-=ny_contact*impulse
				lever:=(-ny_contact*relative_x+nx_contact*relative_y);prop.angular_velocity+=clamp(lever*transfer*.10,-.16,.16)
				prop.pitch=clamp(prop.pitch+closing*.16,0,.38);prop.roll=clamp(prop.roll+lever*.10,-.32,.32)
			}
			// Finish the unused fraction of this fixed tick with resolved motion.
			// Each substep remains collision-checked, so a second obstacle safely stops
			// the carry-through without reapplying the first contact impulse.
			advanced:=vehicle_advance_resolved_collision_motion(g,v,index,steps-step_index-1,steps);resolved_step_distance:=vehicle_actual_speed(v^)/f32(steps);traveled+=f32(advanced)*resolved_step_distance;if travel_event!=nil do travel_event^=traveled
			return true
		}
		v.x,v.y=nx,ny;traveled+=step_distance
	}
	if travel_event!=nil do travel_event^=traveled
	return false
}

vehicle_update_passive :: proc(g:^Game,index:int) {
	v:=&g.vehicles[index]
	tune:=vehicle_tune(index)
	velocity_before_x,velocity_before_y:=v.velocity_x,v.velocity_y
	vehicle_decay_impact(v)
	v.driver_assist=.None;v.driver_assist_strength=0;v.driver_assist_time=0
	v.handbrake_slip=vehicle_handbrake_slip_step_tuned(v.handbrake_slip,false,tune)
	surface_roughness,surface_bias:=vehicle_surface_contact(v^);v.surface_blend=vehicle_surface_blend_step_to(v.surface_blend,surface_roughness);v.surface_lateral_bias=vehicle_surface_bias_step(v.surface_lateral_bias,surface_bias);surface_retention:=1-v.surface_blend*.025;surface_tune:=vehicle_tune_for_surface_blend(tune,v.surface_blend)
	v.yaw_rate+=vehicle_surface_drag_yaw(v^)+vehicle_self_aligning_yaw_blended(v^,v.handbrake_slip,surface_tune);v.yaw_rate*=vehicle_passive_yaw_retention(tune)*(1-v.surface_blend*.015);v.heading+=v.yaw_rate
	if vehicle_actual_speed(v^)<.002 {v.velocity_x=0;v.velocity_y=0;v.speed=0;v.yaw_rate*=.65;if math.abs(v.yaw_rate)<.0002 do v.yaw_rate=0;v.acceleration_feedback*=.82;v.chassis_acceleration*=.82;v.chassis_lateral_acceleration*=.82;vehicle_update_body_roll_blended(v,v.handbrake_slip,tune);vehicle_update_body_pitch(v,tune);v.traction_state=.Grip;return}
	// An unoccupied car rolls freely longitudinally, but its tires still oppose a
	// sideways shove. Sync wheel speed first so only lateral slip is scrubbed.
	vehicle_sync_driveline_to_velocity(v);vehicle_apply_tire_grip_blended(v,v.handbrake_slip,surface_tune)
	retention:=vehicle_passive_momentum_retention(tune)*surface_retention;v.velocity_x*=retention;v.velocity_y*=retention
	vehicle_sync_driveline_to_velocity(v)
	// Passive bodies still carry real collision momentum. The regular transfer
	// factor and passive damping keep pile-up propagation bounded while allowing
	// a struck car to shove the next vehicle instead of acting as a dead stop.
	collided:=vehicle_swept_move(g,v,index,true)
	v.traction_state=vehicle_traction_state_step(v.traction_state,v^)
	vehicle_update_acceleration_feedback_from_velocity(v,velocity_before_x,velocity_before_y,collided);vehicle_update_body_roll_blended(v,v.handbrake_slip,tune);vehicle_update_body_pitch(v,tune)
}

vehicle_passive_momentum_retention :: proc(tune:Vehicle_Tune)->f32 {
	// Once unoccupied, a struck body coasts according to inertia rather than the
	// unrelated coefficient used for sliding along collision surfaces.
	return clamp(.89+tune.mass*.035,.90,.95)
}
vehicle_passive_yaw_retention :: proc(tune:Vehicle_Tune)->f32 {
	return clamp(.76+tune.mass*.08,.80,.90)
}

vehicle_update_passive_vehicles :: proc(g:^Game) {for _,i in g.vehicles {if i!=g.driving_vehicle do vehicle_update_passive(g,i)}}

city_furniture_position_clear :: proc(g:^Game,index:int,x,y:f32)->bool {
	prop:=g.city_furniture[index];radius:=city_furniture_template(prop.kind).radius
	offsets:=[5]Vec2{{0,0},{radius,0},{-radius,0},{0,radius},{0,-radius}}
	for offset in offsets {sx,sy:=x+offset.x,y+offset.y;currently_inside_vehicle:=city_car_at(g,prop.x+offset.x,prop.y+offset.y);if city_wall(sx,sy)||city_car_at(g,sx,sy)&&!currently_inside_vehicle||city_furniture_index_at(g,sx,sy,index)>=0 do return false}
	return true
}

update_city_furniture :: proc(g:^Game) {
	for &prop,i in g.city_furniture {
		speed:=f32(math.sqrt(f64(prop.velocity_x*prop.velocity_x+prop.velocity_y*prop.velocity_y)))
		if speed>.0005 {
			steps:=max(1,int(math.ceil(f64(speed/.08))));step_x,step_y:=prop.velocity_x/f32(steps),prop.velocity_y/f32(steps)
			for _ in 0..<steps {
				x_clear:=city_furniture_position_clear(g,i,prop.x+step_x,prop.y);y_clear:=city_furniture_position_clear(g,i,prop.x,prop.y+step_y)
				if x_clear do prop.x+=step_x;else do prop.velocity_x*= -.18
				if y_clear do prop.y+=step_y;else do prop.velocity_y*= -.18
				if !x_clear&&!y_clear do break
			}
		}
		prop.heading+=prop.angular_velocity;prop.velocity_x*=.90;prop.velocity_y*=.90;prop.angular_velocity*=.86;prop.roll*=.92;prop.pitch*=.92
		if math.abs(prop.velocity_x)<.0005 do prop.velocity_x=0;if math.abs(prop.velocity_y)<.0005 do prop.velocity_y=0;if math.abs(prop.angular_velocity)<.0003 do prop.angular_velocity=0
	}
}

vehicle_can_exit :: proc(v:Vehicle_State)->bool {
	// Chassis stillness alone is insufficient during a burnout or locked driveline
	// transition. Require the wheels, body translation, and rotation all to settle.
	return vehicle_actual_speed(v)<.075&&math.abs(v.speed)<.075&&math.abs(v.yaw_rate)<.008
}

city_player_exit_clear :: proc(g:^Game,position:Vec2,vehicle_index:int)->bool {
	offsets:=[5]Vec2{{0,0},{.24,0},{-.24,0},{0,.24},{0,-.24}}
	for offset in offsets {x,y:=position.x+offset.x,position.y+offset.y;if city_wall(x,y)||city_car_at(g,x,y,vehicle_index)||city_furniture_index_at(g,x,y)>=0 do return false}
	return true
}

vehicle_exit_position :: proc(g:^Game,v:Vehicle_State,vehicle_index:int)->(Vec2,bool) {
	side:=Vec2{-f32(math.sin(f64(v.heading))),f32(math.cos(f64(v.heading)))}
	signs:=[2]f32{1,-1};for sign in signs {candidate:=Vec2{v.x+side.x*1.45*sign,v.y+side.y*1.45*sign};if city_player_exit_clear(g,candidate,vehicle_index) do return candidate,true}
	return {},false
}

city_district :: proc(x:f32)->int {if x<64 do return 0;if x<128 do return 1;return 2}
city_district_name :: proc(x:f32)->string {names:=[3]string{"WESTHAVEN","CENTRAL LOOP","LAKE INDUSTRIAL"};return names[city_district(x)]}

// Neighborhood names follow memorable seams in the city rather than the old
// three vertical render bands. They are intentionally stable map vocabulary:
// landmark directions and future cases can refer to them without owning city
// geometry.
city_neighborhood_name :: proc(x,y:f32)->string {
	lx,ly:=city_layout(x),city_layout(y)
	if lx<64 {if ly<72 do return "WESTHAVEN HEIGHTS";return "DEPOT WARD"}
	if lx<128 {
		if ly<64 do return "OLD MARKET"
		if ly<104 do return "CIVIC LOOP"
		return "FOUNDRY WARD"
	}
	if ly<64 do return "EAST BANK"
	if ly<116 do return "SOUTH QUAY"
	return "MARINA REACH"
}

// Preserve a continuous skyline from the low driving camera while leaving a
// little room before the world's far plane for meshes at the envelope edge.
CITY_ROAD_DRAW_DISTANCE :: f32(96)*CITY_WORLD_SCALE
CITY_BUILDING_DRAW_DISTANCE :: f32(112)*CITY_WORLD_SCALE
CITY_DYNAMIC_DRAW_DISTANCE :: f32(88)*CITY_WORLD_SCALE
CITY_DRIVING_BEHIND_DISTANCE :: f32(-20)*CITY_WORLD_SCALE

city_render_chunk_visible :: proc(g:^Game,x,y,distance_limit,behind_limit:f32)->bool {
	origin_x,origin_y:=g.city_x,g.city_y
	forward_x,forward_y:=f32(0),f32(0)
	if g.driving_vehicle>=0&&g.driving_vehicle<len(g.vehicles) {
		// Use the rendered camera rather than vehicle heading. Reverse driving,
		// momentum lookahead, impacts, and camera transitions can all make the
		// camera face somewhere other than g.city_angle.
		view:=vk_world_view_pose(g)
		origin_x,origin_y=view.eye.x,view.eye.z
		forward_x,forward_y=view.target.x-view.eye.x,view.target.z-view.eye.z
		forward_length:=f32(math.sqrt(f64(forward_x*forward_x+forward_y*forward_y)))
		if forward_length>.0001 {forward_x/=forward_length;forward_y/=forward_length}
	}
	dx,dy:=x-origin_x,y-origin_y
	if dx*dx+dy*dy>distance_limit*distance_limit do return false
	// Walking uses the elevated orbit camera, so the player's facing direction
	// says nothing about which chunks are in the camera frustum. The directional
	// rejection is only useful for the low, forward-facing driving camera.
	if g.driving_vehicle<0 do return true
	facing:=dx*forward_x+dy*forward_y
	return facing>=behind_limit
}

context_resolve_city :: proc(g:^Game) {
	next:=Context_Target{}
	if g.driving_vehicle>=0 {car:=g.vehicles[g.driving_vehicle];stopped:=vehicle_can_exit(car);_,exit_clear:=vehicle_exit_position(g,car,g.driving_vehicle);can_exit:=stopped&&exit_clear;action:=can_exit?"EXIT VEHICLE":stopped?"NO ROOM TO EXIT":"SLOW TO EXIT";next={valid=true,kind=.Vehicle,status=can_exit?.Available:.Unavailable,stable_id=fmt.tprintf("vehicle_%d",g.driving_vehicle),label=strings.to_upper(CITY_CARS[g.driving_vehicle].model),action=action,world={car.x,car.y},source_index=g.driving_vehicle,runtime_index=-1,priority=40,reachable=can_exit}}
	else if g.near_landmark>=0 {
		landmark,_:=city_landmark_at(g,g.near_landmark);payload:=mystery_game_payload(g);tutorial:=payload!=nil&&payload.tutorial_id=="basic_controls";destination:=payload!=nil&&landmark.id==payload.city_destination;available:=true
		action:="VISIT";if payload!=nil&&landmark.id==payload.city_start&&tutorial {available=true;action="RECEIVE BRIEFING"}else if destination {available=!tutorial||tutorial_completed(g,.Briefing);action=available?"ENTER VALE HOUSE":"RECEIVE BRIEFING FIRST"}
		next={valid=true,kind=.Landmark,status=available?.Available:.Unavailable,stable_id=landmark.id,label=landmark.name,action=action,world={landmark.x,landmark.y},source_index=g.near_landmark,runtime_index=-1,priority=30,reachable=available}
	}
	else if g.near_vehicle>=0 {car:=g.vehicles[g.near_vehicle];next={valid=true,kind=.Vehicle,status=.Available,stable_id=fmt.tprintf("vehicle_%d",g.near_vehicle),label=strings.to_upper(CITY_CARS[g.near_vehicle].model),action="ENTER VEHICLE",world={car.x,car.y},source_index=g.near_vehicle,runtime_index=-1,priority=25,reachable=true}}
	if next.valid {g.context_ui.last_valid_time=g.animation_time;if !g.context_ui.current.valid||g.context_ui.current.kind!=next.kind||g.context_ui.current.stable_id!=next.stable_id {g.context_ui.previous=g.context_ui.current;g.context_ui.focus_started=g.animation_time;play_sound(g,.Pick_Up)}}
	g.context_ui.current=next
}

city_briefing_actionable :: proc(g:^Game)->bool {
	target:=g.context_ui.current
	payload:=mystery_game_payload(g);return payload!=nil&&payload.tutorial_id=="basic_controls"&&
		target.valid&&target.reachable&&target.kind==.Landmark&&
		target.stable_id==payload.city_start
}

context_activate_city :: proc(g:^Game,target:Context_Target)->bool {
	if !target.valid||!target.reachable do return false
	if target.kind==.Vehicle {
		tutorial_complete(g,.Travel)
		if g.driving_vehicle>=0 {v:=g.vehicles[g.driving_vehicle];if !vehicle_can_exit(v) do return false;exit_position,exit_clear:=vehicle_exit_position(g,v,g.driving_vehicle);if !exit_clear do return false;g.city_x=exit_position.x;g.city_y=exit_position.y;g.city_camera_x=exit_position.x;g.city_camera_y=exit_position.y;g.city_camera_initialized=true;g.vehicles[g.driving_vehicle].driver_assist=.None;g.vehicles[g.driving_vehicle].driver_assist_strength=0;g.vehicles[g.driving_vehicle].driver_assist_time=0;g.driving_vehicle=-1;return true}
		if target.source_index>=0&&target.source_index<len(g.vehicles) {g.driving_vehicle=target.source_index;vehicle:=&g.vehicles[g.driving_vehicle];vehicle.steering=0;vehicle.acceleration_feedback=0;vehicle.chassis_acceleration=0;vehicle.chassis_lateral_acceleration=0;vehicle.driver_assist=.None;vehicle.driver_assist_strength=0;vehicle.driver_assist_time=0;vehicle.traction_state=vehicle_traction_state(vehicle^);g.city_x=vehicle.x;g.city_y=vehicle.y;g.city_angle=vehicle.heading;g.near_vehicle=-1;g.vehicle_audio_frequency=0;g.vehicle_audio_gain=0;g.vehicle_audio_tire_frequency_a=0;g.vehicle_audio_tire_frequency_b=0;g.vehicle_audio_tire_gain=0;g.vehicle_audio_rough_gain=0;g.vehicle_camera_reverse_blend=0;g.vehicle_camera_follow_distance=0;g.vehicle_skid_emit_distance=0;g.vehicle_impact_sound_cooldown=0;return true}
	}
	if target.kind==.Landmark {landmark,ok:=city_landmark_at(g,target.source_index);if !ok do return false
		payload:=mystery_game_payload(g);if payload!=nil&&landmark.id==payload.city_start&&payload.tutorial_id=="basic_controls" {tutorial_complete(g,.Contextual_Interaction);if !dialogue_start_scene(g,story_scene_index(g.story_project,"scene_police_briefing")) do return false;tutorial_complete(g,.Briefing);_=game_story_milestone(g,"city.briefing_received");return true}
		if payload!=nil&&landmark.id==payload.city_destination {location,found:=case_city_location(g,landmark.id);if !found||!apply_player_spawn_marker(g,location.level_spawn) do return false;tutorial_complete(g,.Travel);_=game_story_milestone(g,"city.case_destination_entered");g.city_return_x=landmark.arrival_x;g.city_return_y=landmark.arrival_y;g.city_return_angle=landmark.arrival_facing*f32(math.PI)/180;g.camera_initialized=false;g.environment_blend=1;g.cutaway_transition=0;g.screen=.Investigate;if !dialogue_scene_completed(g,"scene_arrival") do _=dialogue_start_scene(g,story_scene_index(g.story_project,"scene_arrival"));return true}
		context_feedback(g,landmark.name,.Available,landmark.id);g.context_ui.feedback_expires=g.animation_time+4;return true
	}
	return false
}

// A roughly GTA III-scale footprint across 30,720 cells. Each borough has its
// own grain: Westhaven's narrow residential blocks, the Loop's dense commercial
// streets, and the port's long industrial superblocks. A handful of old routes
// cross those grains and make the neighborhood seams legible while driving.
city_road_cell :: proc(ix,iy:int)->bool {
	if ix<0||ix>=CITY_WIDTH||iy<0||iy>=CITY_HEIGHT do return false
	// Cross-city boulevard, north/south spine, and the three river bridges.
	if iy>=78&&iy<=83||ix>=94&&ix<=99 do return true
	if ix>=62&&ix<=65&&(iy>=30&&iy<=35||iy>=78&&iy<=83||iy>=126&&iy<=131) do return true
	if ix>=126&&ix<=129&&(iy>=14&&iy<=19||iy>=62&&iy<=67||iy>=110&&iy<=115) do return true
	if ix<64 {
		// Close residential north/south streets with fewer, wider east/west roads.
		return ix%16<4||iy%32<4
	}
	if ix<128 {
		// The old commercial core grew at a tighter cadence around civic blocks.
		return (ix-64)%12<4||(iy+2)%20<4||ix>=80&&ix<=83||iy>=30&&iy<=35||iy>=126&&iy<=131
	}
	// Freight roads create large sheds and yards; quay roads serve the waterfront.
	return (ix-128)%32<4||(iy+2)%24<4||ix>=144&&ix<=147||iy>=30&&iy<=35||iy>=110&&iy<=115
}

CITY_ROAD_NORTH :: u8(1)
CITY_ROAD_EAST  :: u8(2)
CITY_ROAD_SOUTH :: u8(4)
CITY_ROAD_WEST  :: u8(8)

city_road_connection_mask :: proc(ix,iy:int)->u8 {
	if !city_road_cell(ix,iy) do return 0
	mask:u8
	if city_road_cell(ix,iy+4) do mask|=CITY_ROAD_NORTH
	if city_road_cell(ix+4,iy) do mask|=CITY_ROAD_EAST
	if city_road_cell(ix,iy-4) do mask|=CITY_ROAD_SOUTH
	if city_road_cell(ix-4,iy) do mask|=CITY_ROAD_WEST
	return mask
}

city_road_tile :: proc(mask:u8)->(mesh_index:int,yaw:f32) {
	count:=0;for bit:u8=1;bit<=CITY_ROAD_WEST;bit<<=1 do if mask&bit!=0 do count+=1
	if count>=4 do return 1,0
	if count==3 {
		// The source T-junction connects west/east/south (missing north).
		if mask&CITY_ROAD_NORTH==0 do return 3,0
		if mask&CITY_ROAD_WEST==0 do return 3,f32(math.PI/2)
		if mask&CITY_ROAD_SOUTH==0 do return 3,f32(math.PI)
		return 3,-f32(math.PI/2)
	}
	if count==2 {
		if mask==CITY_ROAD_EAST|CITY_ROAD_WEST do return 0,0
		if mask==CITY_ROAD_NORTH|CITY_ROAD_SOUTH do return 0,f32(math.PI/2)
		// The source bend connects west and south.
		if mask==CITY_ROAD_WEST|CITY_ROAD_SOUTH do return 2,0
		if mask==CITY_ROAD_SOUTH|CITY_ROAD_EAST do return 2,f32(math.PI/2)
		if mask==CITY_ROAD_EAST|CITY_ROAD_NORTH do return 2,f32(math.PI)
		return 2,-f32(math.PI/2)
	}
	// The source end continues west from its barrier.
	if mask&CITY_ROAD_WEST!=0 do return 4,0
	if mask&CITY_ROAD_SOUTH!=0 do return 4,f32(math.PI/2)
	if mask&CITY_ROAD_EAST!=0 do return 4,f32(math.PI)
	return 4,-f32(math.PI/2)
}

city_open_space_cell :: proc(ix,iy:int)->bool {
	// Market square, civic green, depot forecourt, tank yards, and marina basin.
	return (ix>=72&&ix<=87&&iy>=40&&iy<=55)||
		(ix>=104&&ix<=119&&iy>=70&&iy<=93)||
		(ix>=24&&ix<=43&&iy>=88&&iy<=107)||
		(ix>=136&&ix<=155&&iy>=88&&iy<=103)||
		(ix>=152&&ix<=179&&iy>=120&&iy<=143)
}

city_developed_lot_cell :: proc(ix,iy:int)->bool {
	if ix<0||ix>=CITY_WIDTH||iy<0||iy>=CITY_HEIGHT do return true
	if iy>148+(ix%7) do return true
	if ix>=62&&ix<=65&&!(iy>=30&&iy<=35)&&!(iy>=78&&iy<=83)&&!(iy>=126&&iy<=131) do return true
	if ix>=126&&ix<=129&&!(iy>=14&&iy<=19)&&!(iy>=62&&iy<=67)&&!(iy>=110&&iy<=115) do return true
	return !city_road_cell(ix,iy)&&!city_open_space_cell(ix,iy)
}

city_building_site :: proc(bx,by:int)->(x,y:f32,place:bool) {
	district:=city_district(f32(bx*CITY_BLOCK+8))
	switch district {
	case 0:
		x=f32(bx*CITY_BLOCK+9+(by%2)*2);y=f32(by*CITY_BLOCK+10);place=(bx+by*3)%7!=0
	case 1:
		x=f32(bx*CITY_BLOCK+10);y=f32(by*CITY_BLOCK+9+(bx%2)*2);place=true
	case 2:
		x=f32(bx*CITY_BLOCK+11);y=f32(by*CITY_BLOCK+11);place=(bx+by)%2==0
	}
	if city_open_space_cell(int(x),int(y))||city_road_cell(int(x),int(y)) do place=false
	return
}

// Permanent landmarks still belong to the static city, so their street-side
// interaction points need a recognizable piece of the skyline behind them.
// The station occupies the complete block east of its authored marker;
// render that block as a low civic building instead of a random Westhaven home.
city_police_station_building :: proc(bx,by:int)->bool {return bx==3&&by==3}

city_building_style :: proc(bx,by:int,layout_x:f32)->(mesh_index:int,height,yaw:f32,tint:[4]u8) {
	district:=city_district(layout_x)
	mesh_index=district==0?(bx+by)%2:district==1?2+(bx+by)%3:5+(bx+by)%2
	height=district==0?f32(2.7+f32((bx+by)%3)*.35):district==1?f32(4.2+f32((bx*7+by*3)%6)*.75):f32(3.0+f32((bx*5+by)%3)*.55)
	yaw=district==0&&by%2==1?f32(math.PI):district==2&&bx%2==1?f32(math.PI/2):f32(0)
	tint={255,255,255,255}
	if city_police_station_building(bx,by) {
		mesh_index=2 // broad commercial facade, distinct from nearby houses
		height=4.1
		yaw=-f32(math.PI/2) // entrance addresses the north/south street marker
		tint={184,205,214,255}
	}
	return
}

city_building_wall :: proc(layout_x,layout_y:f32)->bool {
	if layout_x<0||layout_y<0 do return false
	bx,by:=int(layout_x)/CITY_BLOCK,int(layout_y)/CITY_BLOCK
	if bx<0||bx>=CITY_WIDTH/CITY_BLOCK||by<0||by>=CITY_HEIGHT/CITY_BLOCK do return false
	building_x,building_y,place:=city_building_site(bx,by);if !place do return false
	mesh_index,height,yaw,_:=city_building_style(bx,by,building_x)
	// Match the rectangle to the mesh transform used by vk_world_build_city.
	// The previous district-wide square extended well beyond narrow facades,
	// leaving solid patches of apparently empty lawn and road setback.
	if mesh_index>=0&&mesh_index<len(city_meshes) {
		mesh:=&city_meshes[mesh_index]
		span_y:=mesh.max.y-mesh.min.y
		if mesh.ready&&span_y>.0001 {
			scale:=height/span_y
			dx,dy:=layout_x-building_x,layout_y-building_y
			c,s:=f32(math.cos(f64(yaw))),f32(math.sin(f64(yaw)))
			local_x:=c*dx+s*dy;local_y:=-s*dx+c*dy
			half_x:=(mesh.max.x-mesh.min.x)*scale*.5
			half_y:=(mesh.max.z-mesh.min.z)*scale*.5
			return math.abs(local_x)<=half_x&&math.abs(local_y)<=half_y
		}
	}
	// Asset loading failures should remain safe without restoring the oversized
	// district collider.
	return math.abs(layout_x-building_x)<=3&&math.abs(layout_y-building_y)<=3
}

city_driving_surface :: proc(x,y:f32)->City_Driving_Surface {
	ix,iy:=int(city_layout(x)),int(city_layout(y))
	return city_road_cell(ix,iy)?.Road:.Open_Ground
}

vehicle_camera_clear_distance :: proc(x,y,direction_x,direction_y,desired:f32)->f32 {
	if desired<=1.2 do return max(desired,.2)
	distance:=f32(.45)
	for distance<=desired {
		if city_wall(x+direction_x*distance,y+direction_y*distance) do return max(distance-.24,f32(1.2))
		distance+=.14
	}
	return desired
}

vehicle_camera_distance_step :: proc(current,target:f32)->f32 {
	if current<=0 do return target
	response:=target<current?f32(.30):f32(.075)
	return current+(target-current)*response
}

vehicle_camera_momentum_heading :: proc(v:Vehicle_State)->f32 {
	if vehicle_actual_speed(v)<.08 do return v.heading
	travel_heading:=f32(math.atan2(f64(v.velocity_y),f64(v.velocity_x)))
	delta:=travel_heading-v.heading
	for delta>math.PI do delta-=f32(math.PI*2)
	for delta< -math.PI do delta+=f32(math.PI*2)
	// A car's body axis is directionless for this purpose: choose the travel-axis
	// orientation nearest its nose. This keeps reverse and near-broadside motion
	// continuous instead of letting the camera snap by half a turn.
	if delta>math.PI/2 do delta-=f32(math.PI)
	if delta< -math.PI/2 do delta+=f32(math.PI)
	weight:=clamp((vehicle_lateral_slip_ratio(v)-.12)/.58,0,1)*.32
	return v.heading+delta*weight
}

city_wall :: proc(x,y:f32)->bool {
	if x<0||x>=CITY_WORLD_WIDTH||y<0||y>=CITY_WORLD_HEIGHT do return true
	layout_x,layout_y:=city_layout(x),city_layout(y);ix:=int(layout_x);iy:=int(layout_y)
	if ix<0||ix>=CITY_WIDTH||iy<0||iy>=CITY_HEIGHT do return true
	// The rendered waterfront defines the outer borough silhouette. Interior
	// channels are not rendered, so they cannot contribute collision here.
	if iy>148+(ix%7) do return true
	// Two broad cross-city arterials and the regular street grid remain open.
	if city_road_cell(ix,iy) do return false
	// Squares, greens, station forecourts, yards, and the marina break the rhythm.
	if city_open_space_cell(ix,iy) do return false
	// Non-road portions of a lot are lawn or yard. Only the actual building
	// footprint is solid, allowing both pedestrians and vehicles to go off-road.
	return city_building_wall(layout_x,layout_y)
}

city_player_blocked :: proc(g:^Game,x,y:f32)->bool {
	offsets:=[5]Vec2{{0,0},{CITY_PLAYER_RADIUS,0},{-CITY_PLAYER_RADIUS,0},{0,CITY_PLAYER_RADIUS},{0,-CITY_PLAYER_RADIUS}}
	for offset in offsets {sx,sy:=x+offset.x,y+offset.y;if city_wall(sx,sy)||city_car_at(g,sx,sy)||city_furniture_index_at(g,sx,sy)>=0 do return true}
	current:=city_surface_elevation(g.city_x,g.city_y)
	for offset in offsets {if city_surface_elevation(x+offset.x,y+offset.y)-current>CITY_PLAYER_MAX_STEP_HEIGHT do return true}
	return false
}

city_line_clear :: proc(x0,y0,x1,y1:f32)->bool {dx:=x1-x0;dy:=y1-y0;distance:=math.sqrt(dx*dx+dy*dy);if distance<=0.05 do return true;steps:=int(math.ceil(distance/0.1));for step in 1..<steps {t:=f32(step)/f32(steps);if city_wall(x0+dx*t,y0+dy*t) do return false};return true}

city_update_camera :: proc(g:^Game) {
	if !g.city_camera_initialized {g.city_camera_x=g.city_x;g.city_camera_y=g.city_y;g.city_camera_initialized=true}
	if !g.camera_orbit_initialized {g.camera_orbit=math.PI/4;g.camera_zoom=1;g.camera_orbit_initialized=true}
	g.camera_orbit+=g.pad_right_x*.035
	if g.camera_orbit>math.PI do g.camera_orbit-=2*math.PI
	if g.camera_orbit< -math.PI do g.camera_orbit+=2*math.PI
	g.camera_zoom=clamp(g.camera_zoom+g.pad_right_y*.025-g.input.mouse_wheel*.1,.55,1.65)
	desired_x:=g.city_x+g.city_velocity_x*2.8;desired_y:=g.city_y+g.city_velocity_y*2.8
	g.city_camera_x+=(desired_x-g.city_camera_x)*.105;g.city_camera_y+=(desired_y-g.city_camera_y)*.105
}

update_city :: proc(g:^Game) {
	if !g.vehicles_initialized {g.driving_vehicle=-1;g.near_vehicle=-1;initialize_city_vehicles(g)}
	if !g.city_furniture_initialized do initialize_city_furniture(g)
	update_city_furniture(g)
	vehicle_age_skid_marks(g)
	passive_collision_impact:f32
	passive_collision:=false
	if g.driving_vehicle>=0 {
		// Age the player's prior impact before passive bodies can deliver a new one.
		// Decaying afterward makes the same collision weaker solely because another
		// vehicle happened to initiate contact resolution first.
		active:=&g.vehicles[g.driving_vehicle];vehicle_decay_impact(active);impact_before_passives:=active.impact;passive_before_x,passive_before_y:=active.velocity_x,active.velocity_y
		g.vehicle_impact_sound_cooldown=max(0,g.vehicle_impact_sound_cooldown-FIXED_TIMESTEP)
		vehicle_update_passive_vehicles(g)
		passive_collision=math.abs(active.velocity_x-passive_before_x)+math.abs(active.velocity_y-passive_before_y)>.00001
		if vehicle_impact_is_new_event(impact_before_passives,active.impact) do passive_collision_impact=active.impact
	} else {
		vehicle_update_passive_vehicles(g)
	}
	if g.driving_vehicle>=0 {
		v:=&g.vehicles[g.driving_vehicle]
		position_before_x,position_before_y:=v.x,v.y
		velocity_before_x,velocity_before_y:=v.velocity_x,v.velocity_y
		base_tune:=vehicle_tune(g.driving_vehicle);surface_roughness,surface_bias:=vehicle_surface_contact(v^);v.surface_blend=vehicle_surface_blend_step_to(v.surface_blend,surface_roughness);v.surface_lateral_bias=vehicle_surface_bias_step(v.surface_lateral_bias,surface_bias);tune:=vehicle_tune_for_surface_blend(base_tune,v.surface_blend)
		throttle,steer_input:=vehicle_control_inputs(g)
		handbrake:=vehicle_handbrake_input(g)
		v.handbrake_slip=vehicle_handbrake_slip_step_tuned(v.handbrake_slip,handbrake,base_tune)
		reverse_camera_target:=vehicle_reverse_camera_target(v^,throttle,g.vehicle_camera_reverse_blend);g.vehicle_camera_reverse_blend+=(reverse_camera_target-g.vehicle_camera_reverse_blend)*.075
		vehicle_apply_throttle_assisted(v,tune,base_tune,throttle,1-v.handbrake_slip)
		// Surface limits are sustainable speeds, not teleporting clamps. Preserve
		// momentum across a road edge and let rough-ground drag bleed excess speed.
		v.speed=clamp(v.speed,-base_tune.max_reverse,base_tune.max_forward)
		normalized_speed:=vehicle_normalized_steering_speed(v^,tune);assisted_input:=vehicle_assisted_steering_input(v^,steer_input,v.handbrake_slip,base_tune);steer_limit:=vehicle_steering_limit(tune,normalized_speed,v.handbrake_slip,vehicle_is_countersteering(v^,assisted_input));target_steer:=clamp(assisted_input,-1,1)*steer_limit;steering_response:=vehicle_steering_response(tune,normalized_speed,steer_input,v.steering);v.steering+=(target_steer-v.steering)*steering_response
		v.speed*=vehicle_drag_factor_blended(base_tune,v.surface_blend,v.handbrake_slip,throttle,vehicle_lateral_slip_ratio(v^),math.abs(v.speed)/max(base_tune.max_forward,f32(.01)));if math.abs(v.speed)<0.001 do v.speed=0
		detected_assist,detected_assist_strength:=vehicle_driver_assist_blended(v^,base_tune,throttle,v.handbrake_slip);previous_assist:=v.driver_assist;v.driver_assist,v.driver_assist_strength=vehicle_driver_assist_state_step(v.driver_assist,v.driver_assist_strength,detected_assist,detected_assist_strength,v.handbrake_slip);if v.driver_assist==.None do v.driver_assist_time=0;else if v.driver_assist!=previous_assist do v.driver_assist_time=0;else do v.driver_assist_time+=FIXED_TIMESTEP
		requested_drive_authority:=vehicle_requested_drive_authority(v^,throttle);brake_authority:=(1-requested_drive_authority)*math.abs(throttle);vehicle_apply_abs_release(v,brake_authority);vehicle_apply_traction_control(v,base_tune,requested_drive_authority*math.abs(throttle)*(1-v.handbrake_slip))
		// Steering observes the wheel state after driver assists have released lock
		// or trimmed spin, so recovered tire authority is available this same tick.
		vehicle_apply_yaw_blended(v,v.handbrake_slip,tune,throttle)

		// Resolve tire forces in the car's local forward/right basis so power and
		// side grip have distinct, tunable responses.
		vehicle_apply_tire_grip_blended(v,v.handbrake_slip,tune)
		if vehicle_should_settle_velocity(v^) {v.velocity_x*=.82;v.velocity_y*=.82}
		collision_impact,collision_travel:f32;collided:=vehicle_swept_move(g,v,g.driving_vehicle,true,&collision_impact,&collision_travel)
		v.traction_state=vehicle_traction_state_step(v.traction_state,v^)
		// Synthesize after forces and contact so tire timbre, engine load, and the
		// HUD all observe the same resolved simulation tick.
		update_vehicle_drive_audio(g,v^,base_tune,throttle)
		vehicle_update_acceleration_feedback_from_velocity(v,velocity_before_x,velocity_before_y,collided||passive_collision)
		vehicle_update_body_roll_blended(v,v.handbrake_slip,base_tune)
		vehicle_update_body_pitch(v,base_tune)
		audible_impact:=max(collision_impact,passive_collision_impact);if vehicle_impact_audio_ready(audible_impact,g.vehicle_impact_sound_cooldown) {play_vehicle_impact_sound(g,audible_impact);g.vehicle_impact_sound_cooldown=.14}
		vehicle_update_skid_marks_blended(g,v^,v.handbrake_slip,v.surface_blend,{v.x-position_before_x,v.y-position_before_y},true,collision_travel)
		g.city_x=v.x;g.city_y=v.y
		camera_heading:=vehicle_camera_momentum_heading(v^);angle_delta:=camera_heading-g.city_angle;for angle_delta>math.PI do angle_delta-=f32(math.PI*2);for angle_delta< -math.PI do angle_delta+=f32(math.PI*2);g.city_angle+=angle_delta*0.09
		nominal_camera_distance:=vehicle_camera_distance(vehicle_actual_speed(v^));camera_orbit:=g.city_angle+g.vehicle_camera_reverse_blend*f32(math.PI);clear_camera_distance:=vehicle_camera_clear_distance(v.x,v.y,-f32(math.cos(f64(camera_orbit))),-f32(math.sin(f64(camera_orbit))),nominal_camera_distance);g.vehicle_camera_follow_distance=vehicle_camera_distance_step(g.vehicle_camera_follow_distance,clear_camera_distance)
		g.near_vehicle=-1;g.near_landmark=-1
		context_resolve_city(g)
		if g.input.vehicle_action do _=context_activate_city(g,g.context_ui.current)
		return
	}
	if !g.camera_orbit_initialized {g.camera_orbit=math.PI/4;g.camera_zoom=1;g.camera_orbit_initialized=true}
	turn:f32=0;if g.keys[.LEFT] do turn-=1;if g.keys[.RIGHT] do turn+=1;g.city_angle+=turn*0.045
	stick:=house_radial_input({g.pad_left_x,-g.pad_left_y});forward,strafe:=stick.y,stick.x;if g.keys[.W]||g.keys[.UP] do forward+=1;if g.keys[.S]||g.keys[.DOWN] do forward-=1;if g.keys[.A] do strafe-=1;if g.keys[.D] do strafe+=1
	desired_x,desired_y:=f32(0),f32(0);moving:=math.abs(forward)+math.abs(strafe)>.05
	if moving {length:=f32(math.sqrt(f64(forward*forward+strafe*strafe)));magnitude:=min(length,f32(1));forward/=length;strafe/=length;view_x:=-f32(math.cos(f64(g.camera_orbit)));view_y:=-f32(math.sin(f64(g.camera_orbit)));desired_x=(forward*view_x-strafe*view_y)*.065*magnitude;desired_y=(forward*view_y+strafe*view_x)*.065*magnitude;g.city_angle=turn_toward(g.city_angle,f32(math.atan2(f64(desired_y),f64(desired_x))),.14)}
	velocity:=house_approach_velocity({g.city_velocity_x,g.city_velocity_y},{desired_x,desired_y},moving);g.city_velocity_x,g.city_velocity_y=velocity.x,velocity.y
	dx,dy:=g.city_velocity_x,g.city_velocity_y;if !city_player_blocked(g,g.city_x+dx,g.city_y) {g.city_x+=dx}else{g.city_velocity_x=0};if !city_player_blocked(g,g.city_x,g.city_y+dy) {g.city_y+=dy}else{g.city_velocity_y=0};speed:=f32(math.sqrt(f64(g.city_velocity_x*g.city_velocity_x+g.city_velocity_y*g.city_velocity_y)));g.player_walk_speed=speed;g.player_is_walking=speed>.006
	if g.player_is_walking do tutorial_complete(g,.Move)
	if math.abs(turn)+math.abs(g.pad_right_x)>.1 do tutorial_complete(g,.Look)
	city_update_camera(g)
	g.near_vehicle=-1;car_best:f32=1.9;for car,i in g.vehicles {cx:=car.x-g.city_x;cy:=car.y-g.city_y;d:=math.sqrt(cx*cx+cy*cy);if d<car_best {car_best=d;g.near_vehicle=i}}
	g.near_landmark=-1;best:f32=2.2
	for i in 0..<city_landmark_count(g) {landmark,_:=city_landmark_at(g,i);ex:=landmark.x-g.city_x;ey:=landmark.y-g.city_y;d:=math.sqrt(ex*ex+ey*ey);if d<best&&math.cos(g.city_angle)*ex+math.sin(g.city_angle)*ey>0&&city_line_clear(g.city_x,g.city_y,landmark.x,landmark.y){best=d;g.near_landmark=i}}
	context_resolve_city(g)
	if g.input.vehicle_action||g.input.activate&&g.context_ui.current.kind==.Landmark do _=context_activate_city(g,g.context_ui.current)
}
