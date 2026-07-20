package main

import "core:fmt"
import "core:math"
import "core:mem"
import "core:time"
import engine "zelda_engine:engine"
import resources "zelda_engine:render_resources"
import vk "vendor:vulkan"

Vk_World_Vertex :: struct {position:Vec3,uv:Vec2,joints:Glb_Joints,weights:Vec4}
VK_WORLD_MAX_LIGHTS :: 64
VK_WORLD_MAX_DRAW_LIGHTS :: 8
VK_WORLD_MAX_SHADOW_CASTERS :: 16
VK_WORLD_MAX_DESCRIPTOR_SETS :: 2048*engine.MAX_FRAMES_IN_FLIGHT
VK_WORLD_DRAW_CAPACITY :: 16384
VK_WORLD_INSTANCES_PER_FRAME :: 16384
VK_WORLD_MAX_INSTANCES :: VK_WORLD_INSTANCES_PER_FRAME*engine.MAX_FRAMES_IN_FLIGHT
// Every visible draw indexes this table from the fragment shader. Draw
// ingestion enforces the same independent capacity so neither the CPU render
// path nor the shader can address beyond it.
VK_WORLD_DRAW_LIGHT_CAPACITY :: VK_WORLD_DRAW_CAPACITY
// Generated wall finishes contribute hundreds of stable mesh addresses. A tiny
// direct-mapped cache made colliding addresses fall back to a full mesh scan on
// every draw, turning static wall-list construction into quadratic frame work.
// Keep a low-load open-addressed table large enough for the descriptor budget.
VK_WORLD_MESH_CACHE_CAPACITY :: 4096
WORLD_DAY_SECONDS :: f32(600)
WORLD_START_HOUR :: f32(17.5)
world_time_of_day :: proc(animation_time:f32)->f32 {return f32(math.mod(f64(WORLD_START_HOUR/24+animation_time/WORLD_DAY_SECONDS),1.0))}
world_time_hour :: proc(animation_time:f32)->f32 {return world_time_of_day(animation_time)*24}
world_key_light_direction :: proc(animation_time,weather_strength:f32)->Vec3 {
	day_angle:=world_time_of_day(animation_time)*f32(math.PI*2)
	sun_height:=f32(math.sin(f64(day_angle-f32(math.PI/2))))
	simulated:=vk_world_normalize({f32(math.cos(f64(day_angle))),max(math.abs(sun_height),f32(.08)),f32(math.sin(f64(day_angle)))*.72})
	fixed:=Vec3{-.42,.82,.38};weather:=clamp(weather_strength,0,1)
	return vk_world_normalize({fixed.x+(simulated.x-fixed.x)*weather,fixed.y+(simulated.y-fixed.y)*weather,fixed.z+(simulated.z-fixed.z)*weather})
}
Vk_World_Camera :: struct {
	view_projection:Glb_Mat4,camera_position,lighting,atmosphere:[4]f32,
	directional_shadow_matrices:[4]Glb_Mat4,
	directional_shadow_splits:[4]f32,
	directional_shadow_params:[4]f32,
	point_shadow_matrices:[24]Glb_Mat4,
	local_shadow_matrices:[10]Glb_Mat4,
	light_positions:[VK_WORLD_MAX_LIGHTS][4]f32,
	light_colors:[VK_WORLD_MAX_LIGHTS][4]f32,
	light_params:[VK_WORLD_MAX_LIGHTS][4]f32,
	light_shadow_meta:[VK_WORLD_MAX_LIGHTS][4]f32,
	shadow_casters:[VK_WORLD_MAX_SHADOW_CASTERS][4]f32,
	shadow_params:[VK_WORLD_MAX_SHADOW_CASTERS][4]f32,
}
Vk_World_Push :: struct {model:Glb_Mat4,tint:[4]f32,material,pbr:[4]f32,skin:[4]u32}
Vk_World_Mesh :: struct {source:^Glb_Mesh,vertices,indices:engine.Vk_Buffer,images:[dynamic]Vk_Ui_Image,sets:[dynamic]vk.DescriptorSet}
Vk_World_Draw :: struct {mesh:int,x,z,width,height,yaw,pitch,roll,base_y,light_x,light_z:f32,light_group:u64,tint,bark_tint,foliage_tint:[4]u8,foliage_colors:bool,scale_by_footprint,centered,shadow_only,no_shadow,use_light_anchor:bool,surface_kind:int,clip_a,clip_b:int,time_a,time_b,blend:f32}
Vk_World_Draw_Lights :: struct {indices_a,indices_b:[4]u32,weights_a,weights_b:[4]f32,meta:[4]u32}
Vk_World_Light_Cache_Input :: struct {x,z:f32,group:u64}
Vk_World_Runtime_Light :: struct {position:[4]f32,color:[4]f32,params:[4]f32,room,sequence:int}
Vk_Shadow_Push :: struct {model:Glb_Mat4,data:[4]u32}
Vk_Shadow_Image :: struct {image:Vk_Ui_Image,layer_views:[dynamic]vk.ImageView,layers:u32}
Vk_Shadow_State :: struct {
	directional,points,spots:Vk_Shadow_Image,
	matrix_buffers:[engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
	descriptor_layout:vk.DescriptorSetLayout,descriptor_pool:vk.DescriptorPool,descriptors:[engine.MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
	pipeline_layout:vk.PipelineLayout,pipeline:vk.Pipeline,
	quality:Lighting_Quality,ready:bool,
	point_sources:[4]int,spot_sources:[6]int,
	matrices:[64]Glb_Mat4,splits:[4]f32,cascade_count:int,
}
CHARACTER_YAW_OFFSET :: -f32(math.PI/2)
character_render_yaw :: proc(heading:f32)->f32 {return heading+CHARACTER_YAW_OFFSET}
Vk_World_Scene :: struct {
	meshes:[dynamic]Vk_World_Mesh,draws:[dynamic]Vk_World_Draw,
	cameras,palettes,draw_light_buffers:[engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
	instance_buffer:engine.Vk_Buffer,
	mesh_cache_sources:[VK_WORLD_MESH_CACHE_CAPACITY]^Glb_Mesh,
	mesh_cache_indices:[VK_WORLD_MESH_CACHE_CAPACITY]int,
	draw_lights:[dynamic]Vk_World_Draw_Lights,
	light_cache_inputs:[dynamic]Vk_World_Light_Cache_Input,
	light_cache_lights:[dynamic]Vk_World_Runtime_Light,
	light_cache_quality:Lighting_Quality,light_cache_valid:bool,
	descriptor_layout:vk.DescriptorSetLayout,descriptor_pool:vk.DescriptorPool,
	pipeline_layout:vk.PipelineLayout,pipeline:vk.Pipeline,depth:Vk_Ui_Image,
	white,flat_normal:Vk_Ui_Image,ready:bool,
	profile_lights_ms,profile_batches_ms,profile_unbatched_ms:f64,
	profile_house_structure_ms,profile_house_surfaces_ms,profile_house_walls_ms,profile_house_openings_ms,profile_house_objects_ms,profile_house_characters_ms:f64,
	shadows:Vk_Shadow_State,
}
VK_WORLD_MAX_SKINNED_DRAWS :: 16

vk_world_perspective :: proc(fov,aspect,near,far:f32)->Glb_Mat4 {f:=1/f32(math.tan(f64(fov)*.5));return {f/aspect,0,0,0, 0,-f,0,0, 0,0,far/(near-far),-1, 0,0,(near*far)/(near-far),0}}
vk_world_normalize :: proc(v:Vec3)->Vec3 {length:=f32(math.sqrt(f64(v.x*v.x+v.y*v.y+v.z*v.z)));if length<=.00001 do return {};return {v.x/length,v.y/length,v.z/length}}
vk_world_look_at :: proc(eye,target,up:Vec3)->Glb_Mat4 {f:=vk_world_normalize({target.x-eye.x,target.y-eye.y,target.z-eye.z});s:=vk_world_normalize({f.y*up.z-f.z*up.y,f.z*up.x-f.x*up.z,f.x*up.y-f.y*up.x});u:=Vec3{s.y*f.z-s.z*f.y,s.z*f.x-s.x*f.z,s.x*f.y-s.y*f.x};return {s.x,u.x,-f.x,0,s.y,u.y,-f.y,0,s.z,u.z,-f.z,0,-(s.x*eye.x+s.y*eye.y+s.z*eye.z),-(u.x*eye.x+u.y*eye.y+u.z*eye.z),f.x*eye.x+f.y*eye.y+f.z*eye.z,1}}

vk_world_orthographic :: proc(left,right,bottom,top,near,far:f32)->Glb_Mat4 {return {2/(right-left),0,0,0,0,-2/(top-bottom),0,0,0,0,1/(near-far),0,-(right+left)/(right-left),(top+bottom)/(top-bottom),near/(near-far),1}}
vk_shadow_practical_splits :: proc(count:int,near,far:f32)->[4]f32 {result:[4]f32;lambda:=f32(.62);for i in 0..<count {p:=f32(i+1)/f32(count);logarithmic:=near*f32(math.pow(f64(far/near),f64(p)));uniform:=near+(far-near)*p;result[i]=logarithmic*lambda+uniform*(1-lambda)};for i in count..<4 do result[i]=far;return result}

vk_shadow_image_destroy :: proc(image:^Vk_Shadow_Image,ctx:^engine.Vk_Context) {for view in image.layer_views do if view!=vk.ImageView(0) do vk.DestroyImageView(ctx.device,view,nil);delete(image.layer_views);vk_ui_image_destroy(&image.image,ctx);image^={}}
vk_shadow_image_create :: proc(ctx:^engine.Vk_Context,width,height,layers:u32,cube:bool,out:^Vk_Shadow_Image)->bool {
	// Point shadows retain cube-compatible storage but expose the six faces as a
	// 2D array. Explicit face addressing is consistent across Vulkan and MoltenVK.
	view_type:=vk.ImageViewType.D2_ARRAY
	if !resources.image_array_create(ctx,width,height,layers,.D16_UNORM,{.DEPTH_STENCIL_ATTACHMENT,.SAMPLED},{.DEPTH},view_type,cube,&out.image,"world shadow depth") {if !resources.image_array_create(ctx,width,height,layers,.D32_SFLOAT,{.DEPTH_STENCIL_ATTACHMENT,.SAMPLED},{.DEPTH},view_type,cube,&out.image,"world shadow depth fallback") do return false}
	out.layers=layers;out.layer_views=make([dynamic]vk.ImageView,layers,layers)
	for layer in 0..<layers {info:=vk.ImageViewCreateInfo{sType=.IMAGE_VIEW_CREATE_INFO,image=out.image.image,viewType=.D2,format=out.image.format,subresourceRange={aspectMask={.DEPTH},baseMipLevel=0,levelCount=1,baseArrayLayer=layer,layerCount=1}};if vk.CreateImageView(ctx.device,&info,nil,&out.layer_views[layer])!=.SUCCESS {vk_shadow_image_destroy(out,ctx);return false}}
	sampler:=vk.SamplerCreateInfo{sType=.SAMPLER_CREATE_INFO,magFilter=.LINEAR,minFilter=.LINEAR,mipmapMode=.NEAREST,addressModeU=.CLAMP_TO_EDGE,addressModeV=.CLAMP_TO_EDGE,addressModeW=.CLAMP_TO_EDGE,compareEnable=true,compareOp=.LESS_OR_EQUAL,minLod=0,maxLod=0,borderColor=.FLOAT_OPAQUE_WHITE}
	if vk.CreateSampler(ctx.device,&sampler,nil,&out.image.sampler)!=.SUCCESS {vk_shadow_image_destroy(out,ctx);return false};return true
}

vk_shadow_state_destroy :: proc(state:^Vk_Shadow_State,ctx:^engine.Vk_Context) {vk_shadow_image_destroy(&state.directional,ctx);vk_shadow_image_destroy(&state.points,ctx);vk_shadow_image_destroy(&state.spots,ctx);if state.pipeline!=vk.Pipeline(0) do vk.DestroyPipeline(ctx.device,state.pipeline,nil);if state.pipeline_layout!=vk.PipelineLayout(0) do vk.DestroyPipelineLayout(ctx.device,state.pipeline_layout,nil);if state.descriptor_pool!=vk.DescriptorPool(0) do vk.DestroyDescriptorPool(ctx.device,state.descriptor_pool,nil);if state.descriptor_layout!=vk.DescriptorSetLayout(0) do vk.DestroyDescriptorSetLayout(ctx.device,state.descriptor_layout,nil);for &buffer in state.matrix_buffers do engine.vk_destroy_buffer(ctx,&buffer);state^={}}

vk_shadow_state_init :: proc(state:^Vk_Shadow_State,scene:^Vk_World_Scene,ctx:^engine.Vk_Context,quality:Lighting_Quality)->bool {
	vk_shadow_state_destroy(state,ctx);state.quality=quality;cascades:=lighting_quality_directional_cascades(quality);point_slots:=max(lighting_quality_point_shadow_slots(quality),1);spot_slots:=max(lighting_quality_spot_shadow_slots(quality),1)
	if !vk_shadow_image_create(ctx,lighting_quality_directional_resolution(quality),lighting_quality_directional_resolution(quality),u32(cascades),false,&state.directional) do return false
	if !vk_shadow_image_create(ctx,lighting_quality_point_shadow_resolution(quality),lighting_quality_point_shadow_resolution(quality),u32(point_slots*6),true,&state.points) do return false
	if !vk_shadow_image_create(ctx,lighting_quality_spot_shadow_resolution(quality),lighting_quality_spot_shadow_resolution(quality),u32(spot_slots),false,&state.spots) do return false
	for &buffer in state.matrix_buffers do if !engine.vk_create_host_buffer(ctx,vk.DeviceSize(64*size_of(Glb_Mat4)),{.STORAGE_BUFFER},&buffer) do return false
	bindings:=[2]vk.DescriptorSetLayoutBinding{{binding=0,descriptorType=.STORAGE_BUFFER,descriptorCount=1,stageFlags={.VERTEX}},{binding=1,descriptorType=.STORAGE_BUFFER,descriptorCount=1,stageFlags={.VERTEX}}};layout:=vk.DescriptorSetLayoutCreateInfo{sType=.DESCRIPTOR_SET_LAYOUT_CREATE_INFO,bindingCount=2,pBindings=raw_data(bindings[:])};if vk.CreateDescriptorSetLayout(ctx.device,&layout,nil,&state.descriptor_layout)!=.SUCCESS do return false
	pool_size:=vk.DescriptorPoolSize{type=.STORAGE_BUFFER,descriptorCount=2*engine.MAX_FRAMES_IN_FLIGHT};pool:=vk.DescriptorPoolCreateInfo{sType=.DESCRIPTOR_POOL_CREATE_INFO,maxSets=engine.MAX_FRAMES_IN_FLIGHT,poolSizeCount=1,pPoolSizes=&pool_size};if vk.CreateDescriptorPool(ctx.device,&pool,nil,&state.descriptor_pool)!=.SUCCESS do return false;layouts:=[engine.MAX_FRAMES_IN_FLIGHT]vk.DescriptorSetLayout{};for &item in layouts do item=state.descriptor_layout;allocation:=vk.DescriptorSetAllocateInfo{sType=.DESCRIPTOR_SET_ALLOCATE_INFO,descriptorPool=state.descriptor_pool,descriptorSetCount=engine.MAX_FRAMES_IN_FLIGHT,pSetLayouts=raw_data(layouts[:])};if vk.AllocateDescriptorSets(ctx.device,&allocation,raw_data(state.descriptors[:]))!=.SUCCESS do return false
	for frame_index in 0..<engine.MAX_FRAMES_IN_FLIGHT {matrices:=vk.DescriptorBufferInfo{buffer=state.matrix_buffers[frame_index].handle,range=vk.DeviceSize(64*size_of(Glb_Mat4))};palettes:=vk.DescriptorBufferInfo{buffer=scene.palettes[frame_index].handle,range=vk.DeviceSize(VK_WORLD_MAX_SKINNED_DRAWS*GLB_MAX_JOINTS*size_of(Glb_Mat4))};writes:=[2]vk.WriteDescriptorSet{{sType=.WRITE_DESCRIPTOR_SET,dstSet=state.descriptors[frame_index],dstBinding=0,descriptorCount=1,descriptorType=.STORAGE_BUFFER,pBufferInfo=&matrices},{sType=.WRITE_DESCRIPTOR_SET,dstSet=state.descriptors[frame_index],dstBinding=1,descriptorCount=1,descriptorType=.STORAGE_BUFFER,pBufferInfo=&palettes}};vk.UpdateDescriptorSets(ctx.device,2,raw_data(writes[:]),0,nil)}
	push_range:=vk.PushConstantRange{stageFlags={.VERTEX},size=u32(size_of(Vk_Shadow_Push))};pipeline_layout:=vk.PipelineLayoutCreateInfo{sType=.PIPELINE_LAYOUT_CREATE_INFO,setLayoutCount=1,pSetLayouts=&state.descriptor_layout,pushConstantRangeCount=1,pPushConstantRanges=&push_range};if vk.CreatePipelineLayout(ctx.device,&pipeline_layout,nil,&state.pipeline_layout)!=.SUCCESS do return false
	vert:engine.Vk_Shader_Module;if !engine.vk_load_shader_module(ctx,"build/shaders/shadow.vert.spv",&vert) do return false;defer engine.vk_destroy_shader_module(ctx,&vert);stage:=vk.PipelineShaderStageCreateInfo{sType=.PIPELINE_SHADER_STAGE_CREATE_INFO,stage={.VERTEX},module=vert.handle,pName="main"};binding:=vk.VertexInputBindingDescription{stride=u32(size_of(Vk_World_Vertex)),inputRate=.VERTEX};attributes:=[4]vk.VertexInputAttributeDescription{{location=0,format=.R32G32B32_SFLOAT,offset=u32(offset_of(Vk_World_Vertex,position))},{location=1,format=.R32G32_SFLOAT,offset=u32(offset_of(Vk_World_Vertex,uv))},{location=2,format=.R16G16B16A16_UINT,offset=u32(offset_of(Vk_World_Vertex,joints))},{location=3,format=.R32G32B32A32_SFLOAT,offset=u32(offset_of(Vk_World_Vertex,weights))}};vertex_input:=vk.PipelineVertexInputStateCreateInfo{sType=.PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,vertexBindingDescriptionCount=1,pVertexBindingDescriptions=&binding,vertexAttributeDescriptionCount=4,pVertexAttributeDescriptions=raw_data(attributes[:])};assembly:=vk.PipelineInputAssemblyStateCreateInfo{sType=.PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,topology=.TRIANGLE_LIST};viewport_state:=vk.PipelineViewportStateCreateInfo{sType=.PIPELINE_VIEWPORT_STATE_CREATE_INFO,viewportCount=1,scissorCount=1};raster:=vk.PipelineRasterizationStateCreateInfo{sType=.PIPELINE_RASTERIZATION_STATE_CREATE_INFO,depthClampEnable=false,polygonMode=.FILL,cullMode={.FRONT},frontFace=.COUNTER_CLOCKWISE,depthBiasEnable=true,depthBiasConstantFactor=1.25,depthBiasSlopeFactor=1.75,lineWidth=1};samples:=vk.PipelineMultisampleStateCreateInfo{sType=.PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,rasterizationSamples={._1}};depth:=vk.PipelineDepthStencilStateCreateInfo{sType=.PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,depthTestEnable=true,depthWriteEnable=true,depthCompareOp=.LESS_OR_EQUAL};states:=[2]vk.DynamicState{.VIEWPORT,.SCISSOR};dynamic_info:=vk.PipelineDynamicStateCreateInfo{sType=.PIPELINE_DYNAMIC_STATE_CREATE_INFO,dynamicStateCount=2,pDynamicStates=raw_data(states[:])};rendering:=vk.PipelineRenderingCreateInfo{sType=.PIPELINE_RENDERING_CREATE_INFO,depthAttachmentFormat=state.directional.image.format};info:=vk.GraphicsPipelineCreateInfo{sType=.GRAPHICS_PIPELINE_CREATE_INFO,pNext=&rendering,stageCount=1,pStages=&stage,pVertexInputState=&vertex_input,pInputAssemblyState=&assembly,pViewportState=&viewport_state,pRasterizationState=&raster,pMultisampleState=&samples,pDepthStencilState=&depth,pDynamicState=&dynamic_info,layout=state.pipeline_layout};if vk.CreateGraphicsPipelines(ctx.device,vk.PipelineCache(0),1,&info,nil,&state.pipeline)!=.SUCCESS do return false;state.ready=true;return true
}

vk_world_model :: proc(mesh:^Glb_Mesh,x,z,width,height,yaw,pitch,base_y:f32,footprint:bool,centered:=false,roll:f32=0)->Glb_Mat4 {
	dimension:=footprint?max(mesh.max.x-mesh.min.x,mesh.max.z-mesh.min.z):mesh.max.y-mesh.min.y;if dimension<=0 do dimension=1
	sy:=height/dimension;sx,sz:=sy,sy;if width>0 {span_x:=mesh.max.x-mesh.min.x;if span_x>.0001 do sx=width/span_x;sz=1}
	cx,cy,cz:=(mesh.min.x+mesh.max.x)*.5,(mesh.min.y+mesh.max.y)*.5,(mesh.min.z+mesh.max.z)*.5;c,si:=f32(math.cos(f64(yaw))),f32(math.sin(f64(yaw)));cp,sp:=f32(math.cos(f64(pitch))),f32(math.sin(f64(pitch)));cr,sr:=f32(math.cos(f64(roll))),f32(math.sin(f64(roll)))
	c0x,c0y,c0z:=(c*cr-si*sp*sr)*sx,cp*sr*sx,(si*cr+c*sp*sr)*sx;c1x,c1y,c1z:=(-c*sr-si*sp*cr)*sy,cp*cr*sy,(-si*sr+c*sp*cr)*sy;c2x,c2y,c2z:=-si*cp*sz,-sp*sz,c*cp*sz
	if centered {tx:=x-(c0x*cx+c1x*cy+c2x*cz);ty:=base_y-(c0y*cx+c1y*cy+c2y*cz);tz:=z-(c0z*cx+c1z*cy+c2z*cz);return {c0x,c0y,c0z,0,c1x,c1y,c1z,0,c2x,c2y,c2z,0,tx,ty,tz,1}}
	return {c0x,c0y,c0z,0,c1x,c1y,c1z,0,c2x,c2y,c2z,0,x-(c0x*cx+c2x*cz),base_y-mesh.min.y*sy,z-(c0z*cx+c2z*cz),1}
}

vk_world_room_at :: proc(point:Vec2)->int {for room,i in level_document.rooms do if room.story==level_document.active_story&&!room.exterior&&level_point_in_polygon(point,room.points[:]) do return i;return -1}

vk_world_runtime_light_score :: proc(light:Vk_World_Runtime_Light,eye:Vec3)->f32 {dx,dz:=light.position[0]-eye.x,light.position[2]-eye.z;return light.color[3]/(1+dx*dx+dz*dz)}
vk_world_runtime_light_insert :: proc(out:^[dynamic]Vk_World_Runtime_Light,light:Vk_World_Runtime_Light,eye:Vec3) {
	if len(out)<VK_WORLD_MAX_LIGHTS {append(out,light);return};wanted:=vk_world_runtime_light_score(light,eye);worst:=0;worst_score:=vk_world_runtime_light_score(out[0],eye);for candidate,i in out {score:=vk_world_runtime_light_score(candidate,eye);if score<worst_score||(score==worst_score&&candidate.sequence>out[worst].sequence) {worst=i;worst_score=score}};if wanted>worst_score do out[worst]=light
}

vk_world_add_city_vehicle_lights :: proc(out:^[dynamic]Vk_World_Runtime_Light,g:^Game,focus:Vec3) {
	headlight_signs:=[2]f32{-1,1}
	for vehicle,vehicle_index in g.vehicles {
		forward:=Vec2{f32(math.cos(f64(vehicle.heading))),f32(math.sin(f64(vehicle.heading)))};side:=Vec2{-forward.y,forward.x}
		for sign in headlight_signs {position:=Vec2{vehicle.x+forward.x*1.05+side.x*.34*sign,vehicle.y+forward.y*1.05+side.y*.34*sign};vk_world_runtime_light_insert(out,Vk_World_Runtime_Light{position={position.x,city_elevation(position.x,position.y)+.55,position.y,12},color={1,.82,.58,.42},params={f32(Level_Light_Kind.Spot),vehicle.heading,f32(math.cos(f64(18*f32(math.PI)/180))),0},room=-1,sequence=10000+vehicle_index*2+(sign>0?1:0)},focus)}
	}
	if g.driving_vehicle<0||g.driving_vehicle>=len(g.vehicles) do return
	vehicle:=g.vehicles[g.driving_vehicle];throttle,_:=vehicle_control_inputs(g);handbrake:=vehicle_handbrake_input(g);state:=vehicle_rear_light_state(vehicle,throttle,handbrake);if state==.Off do return
	forward:=Vec2{f32(math.cos(f64(vehicle.heading))),f32(math.sin(f64(vehicle.heading)))};side:=Vec2{-forward.y,forward.x};intensity:=vehicle_rear_light_intensity(vehicle,throttle,handbrake);color:=state==.Brake?[4]f32{1,.018,.008,intensity}:[4]f32{.88,.94,1,intensity};light_range:=state==.Brake?f32(2.2):f32(3);half_angle:=state==.Brake?f32(16):f32(20)
	for sign in headlight_signs {position:=Vec2{vehicle.x-forward.x*1.02+side.x*.33*sign,vehicle.y-forward.y*1.02+side.y*.33*sign};vk_world_runtime_light_insert(out,Vk_World_Runtime_Light{position={position.x,city_elevation(position.x,position.y)+.52,position.y,light_range},color=color,params={f32(Level_Light_Kind.Spot),vehicle.heading+f32(math.PI),f32(math.cos(f64(half_angle*f32(math.PI)/180))),0},room=-1,sequence=20000+g.driving_vehicle*2+(sign>0?1:0)},focus)}
}

Vk_World_View_Pose :: struct {eye,target,up:Vec3,baking,interior:bool}

vehicle_camera_distance :: proc(actual_speed:f32)->f32 {return 5.2+clamp(actual_speed/.58,0,1)*1.8}
vehicle_camera_height :: proc(actual_speed:f32)->f32 {return 1.15+clamp(actual_speed/.58,0,1)*.32}
vehicle_camera_acceleration_distance :: proc(v:Vehicle_State)->f32 {load:=clamp(v.acceleration_feedback,-1,1);return load*(load>=0?f32(.34):f32(.20))}
vehicle_camera_effective_distance :: proc(v:Vehicle_State,cleared_distance:f32)->f32 {
	base:=vehicle_camera_distance(vehicle_actual_speed(v));distance:=cleared_distance
	if distance<=0 do distance=base
	offset:=vehicle_camera_acceleration_distance(v)
	// Never spend launch pullback through a boom that was shortened by a wall.
	if offset>0&&distance<base-.05 do offset=0
	return max(distance+offset,f32(1.2))
}
vehicle_camera_bank :: proc(v:Vehicle_State)->f32 {
	actual_speed:=vehicle_actual_speed(v)
	// At useful road speed yaw implies opposite lateral load in reverse. Fade its
	// direction through neutral; retain the raw low-speed collision-spin cue.
	travel_direction:=actual_speed<.06?f32(1):clamp(vehicle_longitudinal_speed(v)/.04,-1,1)
	yaw_bank:=clamp(v.yaw_rate/.045,-1,1)*travel_direction*.018
	if actual_speed<.06 do return yaw_bank
	// Yaw communicates an ordinary corner; signed lateral travel adds a second,
	// bounded cue when the velocity vector escapes the chassis during oversteer.
	right_x:=-f32(math.sin(f64(v.heading)));right_y:=f32(math.cos(f64(v.heading)))
	lateral:=v.velocity_x*right_x+v.velocity_y*right_y
	slip:=clamp(lateral/max(actual_speed,f32(.05)),-1,1)
	speed_weight:=clamp((actual_speed-.06)/.25,0,1)
	force_bank:=clamp(v.chassis_lateral_acceleration,-1,1)*speed_weight*.020
	return clamp(yaw_bank+force_bank+slip*speed_weight*.012,-.05,.05)
}
vehicle_camera_impact_jolt :: proc(v:Vehicle_State,animation_time:f32)->f32 {return f32(math.sin(f64(animation_time*72)))*v.impact*.09}
vehicle_camera_impact_offset :: proc(v:Vehicle_State,animation_time:f32)->Vec2 {
	forward,side:=v.impact_forward,v.impact_side
	directional:=math.abs(forward)+math.abs(side)>=.001
	phase:=directional?v.impact_time:animation_time
	if !directional do side=1
	wave:=f32(math.sin(f64(phase*72)))*v.impact
	// Camera inertia initially travels opposite the resolved acceleration delta.
	return {-wave*forward*.075,-wave*side*.09}
}
vehicle_camera_rough_jolt :: proc(v:Vehicle_State)->f32 {
	phase:=v.x*6.9+v.y*7.7+.2
	return f32(math.sin(f64(phase)))*vehicle_rough_feedback_blended(v,v.surface_blend)*.018
}
vehicle_rough_body_pose :: proc(v:Vehicle_State)->(roll,pitch:f32) {
	amount:=vehicle_rough_feedback_blended(v,v.surface_blend)
	// Spatial phases make bump frequency follow ground speed and keep nearby cars
	// from bobbing in sync. Amplitudes remain subordinate to real load transfer.
	roll=f32(math.sin(f64(v.x*7.3+v.y*4.9+1.7)))*amount*.006
	pitch=f32(math.sin(f64(v.x*5.7-v.y*8.1+.6)))*amount*.010
	return
}
vehicle_camera_field_of_view :: proc(v:Vehicle_State)->f32 {
	speed_response:=clamp(vehicle_actual_speed(v)/.58,0,1)*.105
	impact_response:=clamp(v.impact,0,1)*.022
	load:=clamp(v.acceleration_feedback,-1,1);acceleration_response:=load>=0?load*.014:load*.006
	return f32(math.PI/3)+speed_response+impact_response+acceleration_response
}

vk_world_view_pose :: proc(g:^Game)->Vk_World_View_Pose {
	if g.screen==.Dialogue&&g.story_presentation.interaction_active {distance:=3.5*g.dialogue_interaction.zoom;return {{.35,1.15,distance},{.35,.78,0},{0,1,0},false,true}}
	px,pz,angle:=g.player_x,g.player_y,g.player_angle
	driving_speed:f32=0;driving_orbit_angle:=angle
	if g.screen==.Exterior {px,pz,angle=g.city_x,g.city_y,g.city_angle;driving_orbit_angle=angle;if g.driving_vehicle>=0 {car:=g.vehicles[g.driving_vehicle];driving_speed=vehicle_actual_speed(car);distance:=vehicle_camera_effective_distance(car,g.vehicle_camera_follow_distance);driving_orbit_angle=angle+g.vehicle_camera_reverse_blend*f32(math.PI);px=car.x-f32(math.cos(f64(driving_orbit_angle)))*distance;pz=car.y-f32(math.sin(f64(driving_orbit_angle)))*distance}}
	interior:=g.screen==.Investigate||g.screen==.Dialogue;baking:=g.catalog_bake_index>=0;aerial:=interior||(g.screen==.Exterior&&g.driving_vehicle<0)
	eye:=Vec3{px,vehicle_camera_height(driving_speed),pz};target:=Vec3{px+f32(math.cos(f64(angle))),1.15,pz+f32(math.sin(f64(angle)))};up:=Vec3{0,1,0}
	if g.screen==.Exterior&&g.driving_vehicle>=0 {
		car:=g.vehicles[g.driving_vehicle];lookahead:=1.1+clamp(driving_speed/.58,0,1)*2.4;target={car.x+car.velocity_x*lookahead,0.72,car.y+car.velocity_y*lookahead}
		bank:=vehicle_camera_bank(car);right_x,right_z:=-f32(math.sin(f64(driving_orbit_angle))),f32(math.cos(f64(driving_orbit_angle)));up={right_x*bank,1,right_z*bank}
		impact_offset:=vehicle_camera_impact_offset(car,g.animation_time);car_forward_x,car_forward_z:=f32(math.cos(f64(car.heading))),f32(math.sin(f64(car.heading)));car_right_x,car_right_z:=-car_forward_z,car_forward_x;jolt_x:=car_forward_x*impact_offset.x+car_right_x*impact_offset.y;jolt_z:=car_forward_z*impact_offset.x+car_right_z*impact_offset.y;jolt_magnitude:=f32(math.sqrt(f64(jolt_x*jolt_x+jolt_z*jolt_z)));eye.y+=jolt_magnitude*.55;eye.x+=jolt_x;eye.z+=jolt_z;target.x+=jolt_x*.22;target.z+=jolt_z*.22
		rough_jolt:=vehicle_camera_rough_jolt(car);eye.y+=rough_jolt;target.y+=rough_jolt*.28
		eye.y+=city_elevation(eye.x,eye.z);target.y+=city_elevation(target.x,target.z)
	}
	if baking {eye={2.6,2.2,2.6};target={0,.72,0}} else if aerial {focus_x,focus_z:=px,pz;if interior&&g.camera_initialized {focus_x,focus_z=g.camera_x,g.camera_y}else if g.screen==.Exterior&&g.city_camera_initialized {focus_x,focus_z=g.city_camera_x,g.city_camera_y};base_y:=camera_story_y(g);if g.screen==.Exterior do base_y=city_elevation(focus_x,focus_z);eye,target,up=aerial_camera_pose(g,focus_x,focus_z,base_y)}
	if g.character_studio {eye={0,3.2,10};target={0,1,0};up={0,1,0}}
	if interior&&g.first_person_camera {pitch_scale:=f32(math.cos(f64(g.first_person_pitch)));eye_height:=g.player_elevation+1.65;eye={g.player_x,eye_height,g.player_y};target={g.player_x+f32(math.cos(f64(g.player_angle)))*pitch_scale,eye_height+f32(math.sin(f64(g.first_person_pitch))),g.player_y+f32(math.sin(f64(g.player_angle)))*pitch_scale};up={0,1,0}}
	return {eye,target,up,baking,interior}
}

vk_world_reuse_grouped_light_list :: proc(scene:^Vk_World_Scene,draw_index:int)->bool {
	if draw_index<0||draw_index>=len(scene.draws)||scene.draws[draw_index].light_group==0 do return false
	for candidate in 0..<draw_index do if scene.draws[candidate].light_group==scene.draws[draw_index].light_group {scene.draw_lights[draw_index]=scene.draw_lights[candidate];return true}
	return false
}

vk_world_build_draw_light_lists :: proc(scene:^Vk_World_Scene,lights:[]Vk_World_Runtime_Light,quality:Lighting_Quality,frame_index:int) {
	limit:=lighting_quality_light_count(quality);shadow_candidates:=lighting_quality_shadow_candidates(quality);draw_count:=min(len(scene.draws),len(scene.draw_lights));group_keys:[256]u64;group_draws:[256]int;point_x:[4096]f32;point_z:[4096]f32;point_previous_primary:[4096]u32;point_previous_active:[4096]bool;point_draws:[4096]int;for &index in group_draws do index=-1;for &index in point_draws do index=-1
	cache_matches:=scene.light_cache_valid&&scene.light_cache_quality==quality&&len(scene.light_cache_inputs)==draw_count&&len(scene.light_cache_lights)==len(lights)
	if cache_matches {for light,i in lights do if light!=scene.light_cache_lights[i] {cache_matches=false;break}}
	if cache_matches {for draw,i in scene.draws[:draw_count] {sample_x,sample_z:=draw.x,draw.z;if draw.use_light_anchor do sample_x,sample_z=draw.light_x,draw.light_z;input:=scene.light_cache_inputs[i];if input.x!=sample_x||input.z!=sample_z||input.group!=draw.light_group {cache_matches=false;break}}}
	if cache_matches {if draw_count>0 do mem.copy_non_overlapping(scene.draw_light_buffers[frame_index].mapped,raw_data(scene.draw_lights[:draw_count]),draw_count*size_of(Vk_World_Draw_Lights));return}
	for draw_index in 0..<draw_count {
		draw:=&scene.draws[draw_index]
		group_slot:=int(draw.light_group%len(group_keys));if draw.light_group!=0&&group_keys[group_slot]==draw.light_group&&group_draws[group_slot]>=0 {scene.draw_lights[draw_index]=scene.draw_lights[group_draws[group_slot]];continue}
		sample_x,sample_z:=draw.x,draw.z;if draw.use_light_anchor do sample_x,sample_z=draw.light_x,draw.light_z;previous:=scene.draw_lights[draw_index];previous_active:=previous.meta[0]>0;previous_primary:=previous.indices_a[0];point_hash:=u64(transmute(u32)sample_x)*0x9e3779b1~u64(transmute(u32)sample_z);point_slot:=int(point_hash%len(point_draws));if point_draws[point_slot]>=0&&point_x[point_slot]==sample_x&&point_z[point_slot]==sample_z&&point_previous_active[point_slot]==previous_active&&point_previous_primary[point_slot]==previous_primary {scene.draw_lights[draw_index]=scene.draw_lights[point_draws[point_slot]];continue};list:=Vk_World_Draw_Lights{};scores:[VK_WORLD_MAX_DRAW_LIGHTS]f32;indices:[VK_WORLD_MAX_DRAW_LIGHTS]u32;weights:[VK_WORLD_MAX_DRAW_LIGHTS]f32;count:=0;draw_room:=vk_world_room_at({sample_x,sample_z})
		for light,light_index in lights {dx,dz:=sample_x-light.position[0],sample_z-light.position[2];distance_sq:=dx*dx+dz*dz;range:=max(light.position[3],.01);if distance_sq>=range*range do continue;room_weight:=f32(1);if draw_room!=light.room {if !world_line_clear(sample_x,sample_z,light.position[0],light.position[2]) do continue;room_weight=.35};falloff:=1-f32(math.sqrt(f64(distance_sq)))/range;score:=light.color[3]*room_weight*falloff*falloff;if score<=.0001 do continue;insert:=min(count,limit-1);for slot in 0..<min(count,limit) {if score>scores[slot]+.00001||(math.abs(score-scores[slot])<=.00001&&light_index<int(indices[slot])) {insert=slot;break}};if insert>=limit do continue;end:=min(count,limit-1);for slot:=end;slot>insert;slot-=1 {scores[slot]=scores[slot-1];indices[slot]=indices[slot-1];weights[slot]=weights[slot-1]};scores[insert]=score;indices[insert]=u32(light_index);weights[insert]=room_weight;if count<limit do count+=1}
		if previous.meta[0]>0&&count>1 {previous_primary:=previous.indices_a[0];for slot in 1..<count do if indices[slot]==previous_primary&&scores[0]<scores[slot]*1.05 {scores[0],scores[slot]=scores[slot],scores[0];indices[0],indices[slot]=indices[slot],indices[0];weights[0],weights[slot]=weights[slot],weights[0];break}}
		for slot in 0..<count {if slot<4 {list.indices_a[slot]=indices[slot];list.weights_a[slot]=weights[slot]}else{list.indices_b[slot-4]=indices[slot];list.weights_b[slot-4]=weights[slot]}};list.meta[0]=u32(count);list.meta[2]=u32(min(count,shadow_candidates));if count>0&&shadow_candidates>0 do list.meta[1]=indices[0]+1;scene.draw_lights[draw_index]=list;point_x[point_slot]=sample_x;point_z[point_slot]=sample_z;point_previous_active[point_slot]=previous_active;point_previous_primary[point_slot]=previous_primary;point_draws[point_slot]=draw_index;if draw.light_group!=0 {group_keys[group_slot]=draw.light_group;group_draws[group_slot]=draw_index}
	}
	resize(&scene.light_cache_inputs,draw_count);for draw,i in scene.draws[:draw_count] {sample_x,sample_z:=draw.x,draw.z;if draw.use_light_anchor do sample_x,sample_z=draw.light_x,draw.light_z;scene.light_cache_inputs[i]={sample_x,sample_z,draw.light_group}}
	resize(&scene.light_cache_lights,len(lights));copy(scene.light_cache_lights[:],lights);scene.light_cache_quality=quality;scene.light_cache_valid=true
	if draw_count>0 do mem.copy_non_overlapping(scene.draw_light_buffers[frame_index].mapped,raw_data(scene.draw_lights[:draw_count]),draw_count*size_of(Vk_World_Draw_Lights))
}

vk_world_depth_create :: proc(ctx:^engine.Vk_Context,width,height:u32,out:^Vk_Ui_Image,samples:vk.SampleCountFlags={._1})->bool {
	return resources.depth_create(ctx,width,height,out,samples)
}

vk_world_mesh_destroy :: proc(mesh:^Vk_World_Mesh,ctx:^engine.Vk_Context) {for &image in mesh.images do vk_ui_image_destroy(&image,ctx);delete(mesh.images);delete(mesh.sets);engine.vk_destroy_buffer(ctx,&mesh.indices);engine.vk_destroy_buffer(ctx,&mesh.vertices);mesh^={}}
vk_world_destroy :: proc(scene:^Vk_World_Scene,ctx:^engine.Vk_Context) {for &mesh in scene.meshes do vk_world_mesh_destroy(&mesh,ctx);delete(scene.meshes);delete(scene.draws);delete(scene.draw_lights);delete(scene.light_cache_inputs);delete(scene.light_cache_lights);vk_ui_image_destroy(&scene.white,ctx);vk_ui_image_destroy(&scene.flat_normal,ctx);vk_ui_image_destroy(&scene.depth,ctx);if scene.pipeline!=vk.Pipeline(0) do vk.DestroyPipeline(ctx.device,scene.pipeline,nil);if scene.pipeline_layout!=vk.PipelineLayout(0) do vk.DestroyPipelineLayout(ctx.device,scene.pipeline_layout,nil);if scene.descriptor_pool!=vk.DescriptorPool(0) do vk.DestroyDescriptorPool(ctx.device,scene.descriptor_pool,nil);if scene.descriptor_layout!=vk.DescriptorSetLayout(0) do vk.DestroyDescriptorSetLayout(ctx.device,scene.descriptor_layout,nil);vk_shadow_state_destroy(&scene.shadows,ctx);engine.vk_destroy_buffer(ctx,&scene.instance_buffer);for i in 0..<engine.MAX_FRAMES_IN_FLIGHT {engine.vk_destroy_buffer(ctx,&scene.draw_light_buffers[i]);engine.vk_destroy_buffer(ctx,&scene.palettes[i]);engine.vk_destroy_buffer(ctx,&scene.cameras[i])};scene^={}}

vk_world_init :: proc(scene:^Vk_World_Scene,ctx:^engine.Vk_Context,sample_count:vk.SampleCountFlags={._1})->bool {
	scene^={};scene.meshes=make([dynamic]Vk_World_Mesh,0,64);scene.draws=make([dynamic]Vk_World_Draw,0,VK_WORLD_DRAW_LIGHT_CAPACITY);scene.draw_lights=make([dynamic]Vk_World_Draw_Lights,VK_WORLD_DRAW_LIGHT_CAPACITY,VK_WORLD_DRAW_LIGHT_CAPACITY)
	for i in 0..<engine.MAX_FRAMES_IN_FLIGHT {
		if !engine.vk_create_host_buffer(ctx,vk.DeviceSize(size_of(Vk_World_Camera)),{.UNIFORM_BUFFER},&scene.cameras[i]) do return false
		if !engine.vk_create_host_buffer(ctx,vk.DeviceSize(VK_WORLD_MAX_SKINNED_DRAWS*GLB_MAX_JOINTS*size_of(Glb_Mat4)),{.STORAGE_BUFFER},&scene.palettes[i]) do return false
		if !engine.vk_create_host_buffer(ctx,vk.DeviceSize(VK_WORLD_DRAW_LIGHT_CAPACITY*size_of(Vk_World_Draw_Lights)),{.STORAGE_BUFFER},&scene.draw_light_buffers[i]) do return false
	}
	if !engine.vk_create_host_buffer(ctx,vk.DeviceSize(VK_WORLD_MAX_INSTANCES*size_of(Vk_World_Push)),{.STORAGE_BUFFER},&scene.instance_buffer) do return false
	// Allocate the maximum fixed arrays once. Live quality changes alter active
	// layers and update budgets without invalidating every material descriptor.
	if !vk_shadow_state_init(&scene.shadows,scene,ctx,.Ultra) do return false
	bindings:=[12]vk.DescriptorSetLayoutBinding{{binding=0,descriptorType=.UNIFORM_BUFFER,descriptorCount=1,stageFlags={.VERTEX,.FRAGMENT}},{binding=1,descriptorType=.SAMPLED_IMAGE,descriptorCount=1,stageFlags={.FRAGMENT}},{binding=2,descriptorType=.SAMPLER,descriptorCount=1,stageFlags={.FRAGMENT}},{binding=3,descriptorType=.STORAGE_BUFFER,descriptorCount=1,stageFlags={.VERTEX}},{binding=4,descriptorType=.STORAGE_BUFFER,descriptorCount=1,stageFlags={.FRAGMENT}},{binding=5,descriptorType=.SAMPLED_IMAGE,descriptorCount=1,stageFlags={.FRAGMENT}},{binding=6,descriptorType=.SAMPLED_IMAGE,descriptorCount=1,stageFlags={.FRAGMENT}},{binding=7,descriptorType=.SAMPLED_IMAGE,descriptorCount=1,stageFlags={.FRAGMENT}},{binding=8,descriptorType=.SAMPLER,descriptorCount=1,stageFlags={.FRAGMENT}},{binding=9,descriptorType=.SAMPLED_IMAGE,descriptorCount=1,stageFlags={.FRAGMENT}},{binding=10,descriptorType=.SAMPLED_IMAGE,descriptorCount=1,stageFlags={.FRAGMENT}},{binding=11,descriptorType=.STORAGE_BUFFER,descriptorCount=1,stageFlags={.VERTEX,.FRAGMENT}}};layout_info:=vk.DescriptorSetLayoutCreateInfo{sType=.DESCRIPTOR_SET_LAYOUT_CREATE_INFO,bindingCount=12,pBindings=raw_data(bindings[:])};if vk.CreateDescriptorSetLayout(ctx.device,&layout_info,nil,&scene.descriptor_layout)!=.SUCCESS do return false
	pool_sizes:=[4]vk.DescriptorPoolSize{{type=.UNIFORM_BUFFER,descriptorCount=VK_WORLD_MAX_DESCRIPTOR_SETS},{type=.SAMPLED_IMAGE,descriptorCount=VK_WORLD_MAX_DESCRIPTOR_SETS*6},{type=.SAMPLER,descriptorCount=VK_WORLD_MAX_DESCRIPTOR_SETS*2},{type=.STORAGE_BUFFER,descriptorCount=VK_WORLD_MAX_DESCRIPTOR_SETS*3}};pool:=vk.DescriptorPoolCreateInfo{sType=.DESCRIPTOR_POOL_CREATE_INFO,maxSets=VK_WORLD_MAX_DESCRIPTOR_SETS,poolSizeCount=4,pPoolSizes=raw_data(pool_sizes[:])};if vk.CreateDescriptorPool(ctx.device,&pool,nil,&scene.descriptor_pool)!=.SUCCESS do return false
	push:=vk.PushConstantRange{stageFlags={.VERTEX,.FRAGMENT},size=u32(size_of(Vk_World_Push))};pipeline_layout:=vk.PipelineLayoutCreateInfo{sType=.PIPELINE_LAYOUT_CREATE_INFO,setLayoutCount=1,pSetLayouts=&scene.descriptor_layout,pushConstantRangeCount=1,pPushConstantRanges=&push};if vk.CreatePipelineLayout(ctx.device,&pipeline_layout,nil,&scene.pipeline_layout)!=.SUCCESS do return false
	vert,frag:engine.Vk_Shader_Module;if !engine.vk_load_shader_module(ctx,"build/shaders/world.vert.spv",&vert) do return false;defer engine.vk_destroy_shader_module(ctx,&vert);if !engine.vk_load_shader_module(ctx,"build/shaders/world.frag.spv",&frag) do return false;defer engine.vk_destroy_shader_module(ctx,&frag)
	stages:=[2]vk.PipelineShaderStageCreateInfo{{sType=.PIPELINE_SHADER_STAGE_CREATE_INFO,stage={.VERTEX},module=vert.handle,pName="main"},{sType=.PIPELINE_SHADER_STAGE_CREATE_INFO,stage={.FRAGMENT},module=frag.handle,pName="main"}};binding:=vk.VertexInputBindingDescription{stride=u32(size_of(Vk_World_Vertex)),inputRate=.VERTEX};attributes:=[4]vk.VertexInputAttributeDescription{{location=0,format=.R32G32B32_SFLOAT,offset=u32(offset_of(Vk_World_Vertex,position))},{location=1,format=.R32G32_SFLOAT,offset=u32(offset_of(Vk_World_Vertex,uv))},{location=2,format=.R16G16B16A16_UINT,offset=u32(offset_of(Vk_World_Vertex,joints))},{location=3,format=.R32G32B32A32_SFLOAT,offset=u32(offset_of(Vk_World_Vertex,weights))}};vertex_input:=vk.PipelineVertexInputStateCreateInfo{sType=.PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,vertexBindingDescriptionCount=1,pVertexBindingDescriptions=&binding,vertexAttributeDescriptionCount=4,pVertexAttributeDescriptions=raw_data(attributes[:])};assembly:=vk.PipelineInputAssemblyStateCreateInfo{sType=.PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,topology=.TRIANGLE_LIST};viewport_state:=vk.PipelineViewportStateCreateInfo{sType=.PIPELINE_VIEWPORT_STATE_CREATE_INFO,viewportCount=1,scissorCount=1};raster:=vk.PipelineRasterizationStateCreateInfo{sType=.PIPELINE_RASTERIZATION_STATE_CREATE_INFO,polygonMode=.FILL,cullMode={.BACK},frontFace=.COUNTER_CLOCKWISE,lineWidth=1};samples:=vk.PipelineMultisampleStateCreateInfo{sType=.PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,rasterizationSamples=sample_count};depth:=vk.PipelineDepthStencilStateCreateInfo{sType=.PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,depthTestEnable=true,depthWriteEnable=true,depthCompareOp=.LESS_OR_EQUAL};attachment:=vk.PipelineColorBlendAttachmentState{blendEnable=true,srcColorBlendFactor=.SRC_ALPHA,dstColorBlendFactor=.ONE_MINUS_SRC_ALPHA,colorBlendOp=.ADD,srcAlphaBlendFactor=.ONE,dstAlphaBlendFactor=.ONE_MINUS_SRC_ALPHA,alphaBlendOp=.ADD,colorWriteMask={.R,.G,.B,.A}};blend:=vk.PipelineColorBlendStateCreateInfo{sType=.PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,attachmentCount=1,pAttachments=&attachment};states:=[2]vk.DynamicState{.VIEWPORT,.SCISSOR};dynamic_info:=vk.PipelineDynamicStateCreateInfo{sType=.PIPELINE_DYNAMIC_STATE_CREATE_INFO,dynamicStateCount=2,pDynamicStates=raw_data(states[:])};rendering:=engine.vk_pipeline_rendering_info(&ctx.swapchain_format);rendering.depthAttachmentFormat=.D32_SFLOAT;info:=vk.GraphicsPipelineCreateInfo{sType=.GRAPHICS_PIPELINE_CREATE_INFO,pNext=&rendering,stageCount=2,pStages=raw_data(stages[:]),pVertexInputState=&vertex_input,pInputAssemblyState=&assembly,pViewportState=&viewport_state,pRasterizationState=&raster,pMultisampleState=&samples,pDepthStencilState=&depth,pColorBlendState=&blend,pDynamicState=&dynamic_info,layout=scene.pipeline_layout};if vk.CreateGraphicsPipelines(ctx.device,vk.PipelineCache(0),1,&info,nil,&scene.pipeline)!=.SUCCESS do return false
	white:=[4]u8{255,255,255,255};flat_normal:=[4]u8{128,128,255,255};if !resources.texture_upload_rgba8(ctx,white[:],1,1,&scene.white,resources.Sampler_Options{address_mode=.REPEAT}) do return false;if !resources.texture_upload_rgba8(ctx,flat_normal[:],1,1,&scene.flat_normal,resources.Sampler_Options{address_mode=.REPEAT,linear_color=true}) do return false;if !vk_world_depth_create(ctx,ctx.swapchain_extent.width,ctx.swapchain_extent.height,&scene.depth,sample_count) do return false;scene.ready=true;return true
}

vk_world_descriptor :: proc(scene:^Vk_World_Scene,ctx:^engine.Vk_Context,base,normal,roughness:^Vk_Ui_Image,frame_index:int)->(vk.DescriptorSet,bool) {set:vk.DescriptorSet;alloc:=vk.DescriptorSetAllocateInfo{sType=.DESCRIPTOR_SET_ALLOCATE_INFO,descriptorPool=scene.descriptor_pool,descriptorSetCount=1,pSetLayouts=&scene.descriptor_layout};if vk.AllocateDescriptorSets(ctx.device,&alloc,&set)!=.SUCCESS do return set,false;buffer:=vk.DescriptorBufferInfo{buffer=scene.cameras[frame_index].handle,range=vk.DeviceSize(size_of(Vk_World_Camera))};palette:=vk.DescriptorBufferInfo{buffer=scene.palettes[frame_index].handle,range=vk.DeviceSize(VK_WORLD_MAX_SKINNED_DRAWS*GLB_MAX_JOINTS*size_of(Glb_Mat4))};draw_lights:=vk.DescriptorBufferInfo{buffer=scene.draw_light_buffers[frame_index].handle,range=vk.DeviceSize(VK_WORLD_DRAW_LIGHT_CAPACITY*size_of(Vk_World_Draw_Lights))};instances:=vk.DescriptorBufferInfo{buffer=scene.instance_buffer.handle,range=vk.DeviceSize(VK_WORLD_MAX_INSTANCES*size_of(Vk_World_Push))};base_info:=vk.DescriptorImageInfo{imageView=base.view,imageLayout=.SHADER_READ_ONLY_OPTIMAL};normal_info:=vk.DescriptorImageInfo{imageView=normal.view,imageLayout=.SHADER_READ_ONLY_OPTIMAL};roughness_info:=vk.DescriptorImageInfo{imageView=roughness.view,imageLayout=.SHADER_READ_ONLY_OPTIMAL};sampler:=vk.DescriptorImageInfo{sampler=base.sampler};directional:=vk.DescriptorImageInfo{imageView=scene.shadows.directional.image.view,imageLayout=.SHADER_READ_ONLY_OPTIMAL};points:=vk.DescriptorImageInfo{imageView=scene.shadows.points.image.view,imageLayout=.SHADER_READ_ONLY_OPTIMAL};spots:=vk.DescriptorImageInfo{imageView=scene.shadows.spots.image.view,imageLayout=.SHADER_READ_ONLY_OPTIMAL};shadow_sampler:=vk.DescriptorImageInfo{sampler=scene.shadows.directional.image.sampler};writes:=[12]vk.WriteDescriptorSet{{sType=.WRITE_DESCRIPTOR_SET,dstSet=set,dstBinding=0,descriptorCount=1,descriptorType=.UNIFORM_BUFFER,pBufferInfo=&buffer},{sType=.WRITE_DESCRIPTOR_SET,dstSet=set,dstBinding=1,descriptorCount=1,descriptorType=.SAMPLED_IMAGE,pImageInfo=&base_info},{sType=.WRITE_DESCRIPTOR_SET,dstSet=set,dstBinding=2,descriptorCount=1,descriptorType=.SAMPLER,pImageInfo=&sampler},{sType=.WRITE_DESCRIPTOR_SET,dstSet=set,dstBinding=3,descriptorCount=1,descriptorType=.STORAGE_BUFFER,pBufferInfo=&palette},{sType=.WRITE_DESCRIPTOR_SET,dstSet=set,dstBinding=4,descriptorCount=1,descriptorType=.STORAGE_BUFFER,pBufferInfo=&draw_lights},{sType=.WRITE_DESCRIPTOR_SET,dstSet=set,dstBinding=5,descriptorCount=1,descriptorType=.SAMPLED_IMAGE,pImageInfo=&directional},{sType=.WRITE_DESCRIPTOR_SET,dstSet=set,dstBinding=6,descriptorCount=1,descriptorType=.SAMPLED_IMAGE,pImageInfo=&points},{sType=.WRITE_DESCRIPTOR_SET,dstSet=set,dstBinding=7,descriptorCount=1,descriptorType=.SAMPLED_IMAGE,pImageInfo=&spots},{sType=.WRITE_DESCRIPTOR_SET,dstSet=set,dstBinding=8,descriptorCount=1,descriptorType=.SAMPLER,pImageInfo=&shadow_sampler},{sType=.WRITE_DESCRIPTOR_SET,dstSet=set,dstBinding=9,descriptorCount=1,descriptorType=.SAMPLED_IMAGE,pImageInfo=&normal_info},{sType=.WRITE_DESCRIPTOR_SET,dstSet=set,dstBinding=10,descriptorCount=1,descriptorType=.SAMPLED_IMAGE,pImageInfo=&roughness_info},{sType=.WRITE_DESCRIPTOR_SET,dstSet=set,dstBinding=11,descriptorCount=1,descriptorType=.STORAGE_BUFFER,pBufferInfo=&instances}};vk.UpdateDescriptorSets(ctx.device,12,raw_data(writes[:]),0,nil);return set,true}

vk_world_image_upload :: proc(ctx:^engine.Vk_Context,pixels:[]u8,width,height:int,out:^Vk_Ui_Image)->bool {
	// World UVs intentionally exceed 0..1 so grass, paths, roofs, and room
	// coverings tile at a stable physical scale. UI art uses the clamp sampler.
	return resources.texture_upload_rgba8(ctx,pixels,width,height,out,resources.Sampler_Options{address_mode=.REPEAT})
}

vk_world_linear_image_upload :: proc(ctx:^engine.Vk_Context,pixels:[]u8,width,height:int,out:^Vk_Ui_Image)->bool {return resources.texture_upload_rgba8(ctx,pixels,width,height,out,resources.Sampler_Options{address_mode=.REPEAT,linear_color=true})}

vk_world_register_mesh :: proc(scene:^Vk_World_Scene,ctx:^engine.Vk_Context,source:^Glb_Mesh)->int {
	if source==nil||!source.ready do return -1
	cache_slot:=int((uintptr(source)>>4)%VK_WORLD_MESH_CACHE_CAPACITY)
	cache_insert:=-1
	for probe in 0..<VK_WORLD_MESH_CACHE_CAPACITY {
		slot:=(cache_slot+probe)%VK_WORLD_MESH_CACHE_CAPACITY
		cached:=scene.mesh_cache_sources[slot]
		if cached==source do return scene.mesh_cache_indices[slot]
		if cached==nil {cache_insert=slot;break}
	}
	// This is only reachable for a scene restored from an older/incomplete cache
	// or if the table is genuinely full. It is not part of the steady frame path.
	for mesh,i in scene.meshes do if mesh.source==source {if cache_insert>=0 {scene.mesh_cache_sources[cache_insert]=source;scene.mesh_cache_indices[cache_insert]=i};return i}
	mesh:=Vk_World_Mesh{source=source};vertices:=make([]Vk_World_Vertex,len(source.vertices),context.temp_allocator);for &vertex,i in vertices {j:=Glb_Joints{};w:=Vec4{1,0,0,0};if i<len(source.joints) do j=source.joints[i];if i<len(source.weights) do w=source.weights[i];vertex={source.vertices[i],source.texcoords[i],j,w}};if !engine.vk_create_host_buffer(ctx,vk.DeviceSize(len(vertices)*size_of(Vk_World_Vertex)),{.VERTEX_BUFFER},&mesh.vertices) do return -1;if !engine.vk_create_host_buffer(ctx,vk.DeviceSize(len(source.indices)*size_of(u32)),{.INDEX_BUFFER},&mesh.indices) {engine.vk_destroy_buffer(ctx,&mesh.vertices);return -1};mem.copy_non_overlapping(mesh.vertices.mapped,raw_data(vertices),len(vertices)*size_of(Vk_World_Vertex));mem.copy_non_overlapping(mesh.indices.mapped,raw_data(source.indices[:]),len(source.indices)*size_of(u32));mesh.images=make([dynamic]Vk_Ui_Image,0,len(source.textures)*2);mesh.sets=make([dynamic]vk.DescriptorSet,0,len(source.primitives))
	srgb_images:=make([]Vk_Ui_Image,len(source.textures),context.temp_allocator);linear_images:=make([]Vk_Ui_Image,len(source.textures),context.temp_allocator);srgb_needed:=make([]bool,len(source.textures),context.temp_allocator);linear_needed:=make([]bool,len(source.textures),context.temp_allocator)
	for primitive,primitive_index in source.primitives {if primitive.texture>=0&&primitive.texture<len(srgb_needed) do srgb_needed[primitive.texture]=true;normal_index:=primitive_index<len(source.normal_textures)?source.normal_textures[primitive_index]:-1;roughness_index:=primitive_index<len(source.roughness_textures)?source.roughness_textures[primitive_index]:-1;if normal_index>=0&&normal_index<len(linear_needed) do linear_needed[normal_index]=true;if roughness_index>=0&&roughness_index<len(linear_needed) do linear_needed[roughness_index]=true}
	for texture,i in source.textures {if len(texture.pixels)==0 do continue;if srgb_needed[i]&&vk_world_image_upload(ctx,texture.pixels[:],texture.width,texture.height,&srgb_images[i]) do append(&mesh.images,srgb_images[i]);if linear_needed[i]&&vk_world_linear_image_upload(ctx,texture.pixels[:],texture.width,texture.height,&linear_images[i]) do append(&mesh.images,linear_images[i])}
	for primitive,primitive_index in source.primitives {base:=&scene.white;normal:=&scene.flat_normal;roughness:=&scene.white;normal_index:=primitive_index<len(source.normal_textures)?source.normal_textures[primitive_index]:-1;roughness_index:=primitive_index<len(source.roughness_textures)?source.roughness_textures[primitive_index]:-1;if primitive.texture>=0&&primitive.texture<len(srgb_images)&&srgb_images[primitive.texture].view!=vk.ImageView(0) do base=&srgb_images[primitive.texture];if normal_index>=0&&normal_index<len(linear_images)&&linear_images[normal_index].view!=vk.ImageView(0) do normal=&linear_images[normal_index];if roughness_index>=0&&roughness_index<len(linear_images)&&linear_images[roughness_index].view!=vk.ImageView(0) do roughness=&linear_images[roughness_index];for frame_index in 0..<engine.MAX_FRAMES_IN_FLIGHT {set,ok:=vk_world_descriptor(scene,ctx,base,normal,roughness,frame_index);if !ok {vk_world_mesh_destroy(&mesh,ctx);return -1};append(&mesh.sets,set)}};append(&scene.meshes,mesh);index:=len(scene.meshes)-1;if cache_insert>=0 {scene.mesh_cache_sources[cache_insert]=source;scene.mesh_cache_indices[cache_insert]=index};return index
}

// Generated editor meshes keep stable source addresses while their contents
// change after transactions. Refresh their buffers in place so draw indices
// and descriptors remain valid without consuming more descriptor-pool entries.
vk_world_refresh_mesh :: proc(scene:^Vk_World_Scene,ctx:^engine.Vk_Context,source:^Glb_Mesh)->bool {
	index:=-1;for mesh,i in scene.meshes do if mesh.source==source {index=i;break};if index<0 do return true;if source==nil||!source.ready do return false
	mesh:=&scene.meshes[index];vertices:=make([]Vk_World_Vertex,len(source.vertices),context.temp_allocator);for &vertex,i in vertices {j:=Glb_Joints{};w:=Vec4{1,0,0,0};if i<len(source.joints) do j=source.joints[i];if i<len(source.weights) do w=source.weights[i];vertex={source.vertices[i],source.texcoords[i],j,w}}
	vertex_size:=vk.DeviceSize(len(vertices)*size_of(Vk_World_Vertex));index_size:=vk.DeviceSize(len(source.indices)*size_of(u32));_=vk.DeviceWaitIdle(ctx.device)
	if mesh.vertices.size!=vertex_size {engine.vk_destroy_buffer(ctx,&mesh.vertices);if !engine.vk_create_host_buffer(ctx,vertex_size,{.VERTEX_BUFFER},&mesh.vertices) do return false}
	if mesh.indices.size!=index_size {engine.vk_destroy_buffer(ctx,&mesh.indices);if !engine.vk_create_host_buffer(ctx,index_size,{.INDEX_BUFFER},&mesh.indices) do return false}
	mem.copy_non_overlapping(mesh.vertices.mapped,raw_data(vertices),int(vertex_size));mem.copy_non_overlapping(mesh.indices.mapped,raw_data(source.indices[:]),int(index_size));return true
}

vk_world_begin :: proc(scene:^Vk_World_Scene) {clear(&scene.draws)}
vk_world_draw_capacity_available :: proc(draw_count:int)->bool {return draw_count>=0&&draw_count<VK_WORLD_DRAW_CAPACITY}
vk_world_append_draw :: proc(scene:^Vk_World_Scene,draw:Vk_World_Draw)->bool {if !vk_world_draw_capacity_available(len(scene.draws)) do return false;append(&scene.draws,draw);return true}
vk_world_add :: proc(scene:^Vk_World_Scene,ctx:^engine.Vk_Context,mesh:^Glb_Mesh,x,z,height,yaw:f32,tint:=[4]u8{255,255,255,255},footprint:=false,surface_kind:=0,base_y:f32=0,pitch:f32=0,roll:f32=0,shadow_only:=false,no_shadow:bool=false) {if len(scene.draws)>=VK_WORLD_DRAW_CAPACITY do return;index:=vk_world_register_mesh(scene,ctx,mesh);if index>=0 do _=vk_world_append_draw(scene,Vk_World_Draw{mesh=index,x=x,z=z,height=height,yaw=yaw,pitch=pitch,roll=roll,base_y=base_y,tint=tint,scale_by_footprint=footprint,shadow_only=shadow_only,no_shadow=no_shadow,surface_kind=surface_kind,clip_a=-1,clip_b=-1})}
vk_world_add_centered :: proc(scene:^Vk_World_Scene,ctx:^engine.Vk_Context,mesh:^Glb_Mesh,x,z,center_y,height,yaw,pitch:f32,tint:=[4]u8{255,255,255,255},surface_kind:=0) {if len(scene.draws)>=VK_WORLD_DRAW_CAPACITY do return;index:=vk_world_register_mesh(scene,ctx,mesh);if index>=0 do _=vk_world_append_draw(scene,Vk_World_Draw{mesh=index,x=x,z=z,height=height,yaw=yaw,pitch=pitch,base_y=center_y,tint=tint,centered=true,surface_kind=surface_kind,clip_a=-1,clip_b=-1})}
vk_world_add_sized :: proc(scene:^Vk_World_Scene,ctx:^engine.Vk_Context,mesh:^Glb_Mesh,x,z,width,height,yaw:f32,tint:=[4]u8{255,255,255,255},surface_kind:=0,base_y:f32=0,no_shadow:bool=false,light_anchor:Vec2={},use_light_anchor:bool=false,light_group:u64=0) {if len(scene.draws)>=VK_WORLD_DRAW_CAPACITY do return;index:=vk_world_register_mesh(scene,ctx,mesh);if index>=0 do _=vk_world_append_draw(scene,Vk_World_Draw{mesh=index,x=x,z=z,width=width,height=height,yaw=yaw,base_y=base_y,tint=tint,surface_kind=surface_kind,no_shadow=no_shadow,light_x=light_anchor.x,light_z=light_anchor.y,light_group=light_group,use_light_anchor=use_light_anchor,clip_a=-1,clip_b=-1})}
vk_world_add_foliage :: proc(scene:^Vk_World_Scene,ctx:^engine.Vk_Context,mesh:^Glb_Mesh,x,z,height,yaw:f32,bark_tint,foliage_tint:[4]u8,base_y:f32=0,no_shadow:bool=false) {if len(scene.draws)>=VK_WORLD_DRAW_CAPACITY do return;index:=vk_world_register_mesh(scene,ctx,mesh);if index>=0 do _=vk_world_append_draw(scene,Vk_World_Draw{mesh=index,x=x,z=z,height=height,yaw=yaw,base_y=base_y,tint={255,255,255,255},bark_tint=bark_tint,foliage_tint=foliage_tint,foliage_colors=true,no_shadow=no_shadow,clip_a=-1,clip_b=-1})}
vk_world_add_animated :: proc(scene:^Vk_World_Scene,ctx:^engine.Vk_Context,mesh:^Glb_Mesh,x,z,height,yaw:f32,tint:[4]u8,clip_a,clip_b:int,time_a,time_b,blend:f32,base_y:f32=0,surface_kind:=5,pitch:f32=0) {if len(scene.draws)>=VK_WORLD_DRAW_CAPACITY do return;index:=vk_world_register_mesh(scene,ctx,mesh);if index>=0 do _=vk_world_append_draw(scene,Vk_World_Draw{mesh=index,x=x,z=z,height=height,yaw=yaw,pitch=pitch,base_y=base_y,tint=tint,surface_kind=surface_kind,clip_a=clip_a,clip_b=clip_b,time_a=time_a,time_b=time_b,blend=blend})}

vk_world_write_palette :: proc(scene:^Vk_World_Scene,mesh:^Glb_Mesh,draw:^Vk_World_Draw,slot,frame_index:int)->bool {if slot<0||slot>=VK_WORLD_MAX_SKINNED_DRAWS||len(mesh.skin.joints)==0 do return false;pose_a:=make([]Glb_TRS,len(mesh.nodes),context.temp_allocator);pose_b:=make([]Glb_TRS,len(mesh.nodes),context.temp_allocator);pose:=make([]Glb_TRS,len(mesh.nodes),context.temp_allocator);if !glb_sample_pose(mesh,draw.clip_a,draw.time_a,false,pose_a) do return false;if draw.clip_b>=0&&draw.blend>0 {if !glb_sample_pose(mesh,draw.clip_b,draw.time_b,false,pose_b) do return false;glb_blend_pose(pose_a,pose_b,clamp(draw.blend,0,1),pose)}else{copy(pose,pose_a)};palette:=make([]Glb_Mat4,len(mesh.skin.joints),context.temp_allocator);if !glb_pose_palette(mesh,pose,palette) do return false;destination:=uintptr(scene.palettes[frame_index].mapped)+uintptr(slot*GLB_MAX_JOINTS*size_of(Glb_Mat4));mem.copy_non_overlapping(rawptr(destination),raw_data(palette),len(palette)*size_of(Glb_Mat4));return true}

// Palette slots belong to scene draws, not to a particular shadow light's
// filtered caster list. The mapped palette buffer is shared by every recorded
// shadow layer and the visible pass, so compacting slots after light culling
// makes a queued shadow draw read another character's final pose at submit.
vk_world_skin_slot :: proc(scene:^Vk_World_Scene,draw_index:int)->int {
	if draw_index<0||draw_index>=len(scene.draws) do return -1
	slot:=0
	for draw,i in scene.draws {
		if i>=draw_index do break
		mesh:=&scene.meshes[draw.mesh]
		if len(mesh.source.skin.joints)>0 do slot+=1
	}
	draw:=&scene.draws[draw_index]
	mesh:=&scene.meshes[draw.mesh];if len(mesh.source.skin.joints)==0 do return -1
	return slot
}

vk_shadow_draw_eligible :: proc(draw:^Vk_World_Draw,local:bool,light_position:Vec3,light_range:f32,light_room:int)->bool {
	receiver_only:=draw.surface_kind==1||draw.surface_kind==3||draw.surface_kind==4||draw.surface_kind==6||draw.surface_kind==7||draw.surface_kind==11||draw.surface_kind==12||draw.surface_kind==14||(draw.surface_kind==16&&!draw.shadow_only);if draw.no_shadow||receiver_only||(draw.tint[3]<128&&!draw.shadow_only)||(local&&draw.shadow_only) do return false
	if local {dx,dz:=draw.x-light_position.x,draw.z-light_position.z;if dx*dx+dz*dz>(light_range+2)*(light_range+2) do return false;draw_room:=vk_world_room_at({draw.x,draw.z});if light_room>=0&&draw_room!=light_room&&!world_line_clear(draw.x,draw.z,light_position.x,light_position.z) do return false}
	return true
}

vk_shadow_render_layer :: proc(scene:^Vk_World_Scene,command:vk.CommandBuffer,image:^Vk_Shadow_Image,layer,matrix_index,frame_index:int,local:=false,light_position:=Vec3{},light_range:f32=0,light_room:=-1) {
	if layer<0||layer>=len(image.layer_views) do return;clear:=vk.ClearValue{depthStencil={depth=1}};attachment:=vk.RenderingAttachmentInfo{sType=.RENDERING_ATTACHMENT_INFO,imageView=image.layer_views[layer],imageLayout=.DEPTH_ATTACHMENT_OPTIMAL,loadOp=.CLEAR,storeOp=.STORE,clearValue=clear};rendering:=vk.RenderingInfo{sType=.RENDERING_INFO,renderArea={extent={image.image.width,image.image.height}},layerCount=1,pDepthAttachment=&attachment};vk.CmdBeginRendering(command,&rendering);viewport:=vk.Viewport{width=f32(image.image.width),height=f32(image.image.height),minDepth=0,maxDepth=1};scissor:=vk.Rect2D{extent={image.image.width,image.image.height}};vk.CmdSetViewport(command,0,1,&viewport);vk.CmdSetScissor(command,0,1,&scissor);vk.CmdBindPipeline(command,.GRAPHICS,scene.shadows.pipeline);vk.CmdBindDescriptorSets(command,.GRAPHICS,scene.shadows.pipeline_layout,0,1,&scene.shadows.descriptors[frame_index],0,nil)
	offset:=vk.DeviceSize(0);for &draw,draw_index in scene.draws {if !vk_shadow_draw_eligible(&draw,local,light_position,light_range,light_room) do continue;mesh:=&scene.meshes[draw.mesh];skinned:=len(mesh.source.skin.joints)>0;palette_slot:=skinned?vk_world_skin_slot(scene,draw_index):-1;skin_offset:=u32(max(palette_slot,0)*GLB_MAX_JOINTS);if skinned {if palette_slot<0||!vk_world_write_palette(scene,mesh.source,&draw,palette_slot,frame_index) do continue};vk.CmdBindVertexBuffers(command,0,1,&mesh.vertices.handle,&offset);vk.CmdBindIndexBuffer(command,mesh.indices.handle,0,.UINT32);model:=vk_world_model(mesh.source,draw.x,draw.z,draw.width,draw.height,draw.yaw,draw.pitch,draw.base_y,draw.scale_by_footprint,draw.centered,draw.roll);push:=Vk_Shadow_Push{model,{skinned?1:0,skin_offset,u32(matrix_index),0}};vk.CmdPushConstants(command,scene.shadows.pipeline_layout,{.VERTEX},0,u32(size_of(push)),&push);for primitive in mesh.source.primitives do vk.CmdDrawIndexed(command,u32(primitive.count),1,u32(primitive.first),0,0)};vk.CmdEndRendering(command)
}

vk_world_shadow_record :: proc(scene:^Vk_World_Scene,ctx:^engine.Vk_Context,command:vk.CommandBuffer,g:^Game,frame_index:int) {
	if !scene.shadows.ready||len(scene.draws)==0 do return;state:=&scene.shadows;view:=vk_world_view_pose(g);count:=view.interior?1:lighting_quality_directional_cascades(g.lighting_quality);state.cascade_count=count;state.splits=vk_shadow_practical_splits(count,.08,120);focus:=view.target;weather_strength:=g.screen==.Exterior?f32(1):clamp(g.environment_blend,0,1);light_direction:=world_key_light_direction(g.animation_time,weather_strength);resolution:=f32(state.directional.image.width)
	for cascade in 0..<count {far:=state.splits[cascade];interior_radius:=max(f32(max(level_document.width,level_document.height))*.75,f32(24));radius:=view.interior?interior_radius:max(far*.72,f32(5));texel:=radius*2/resolution;center:=focus;center.x=f32(math.round(f64(center.x/texel)))*texel;center.z=f32(math.round(f64(center.z/texel)))*texel;eye:=Vec3{center.x-light_direction.x*radius*2,center.y-light_direction.y*radius*2,center.z-light_direction.z*radius*2};state.matrices[cascade]=glb_mat4_multiply(vk_world_orthographic(-radius,radius,-radius,radius,.05,radius*5),vk_world_look_at(eye,center,{0,1,0}))}
	runtime_lights:=make([dynamic]Vk_World_Runtime_Light,0,VK_WORLD_MAX_LIGHTS,context.temp_allocator);sequence:=0;for light in level_document.lights {if light.story!=level_document.active_story do continue;base_y:=f32(0);if light.story>=0&&light.story<len(level_document.stories) do base_y=level_document.stories[light.story].base_elevation;vk_world_runtime_light_insert(&runtime_lights,Vk_World_Runtime_Light{position={light.position.x,base_y+light.elevation,light.position.y,light.range},color={f32(light.color[0])/255,f32(light.color[1])/255,f32(light.color[2])/255,light.intensity*.34},params={f32(light.kind),light.facing*f32(math.PI)/180,f32(math.cos(f64(light.cone_angle*.5*f32(math.PI)/180))),0},room=vk_world_room_at(light.position),sequence=sequence},focus);sequence+=1};for object in level_document.objects {if object.story!=level_document.active_story do continue;entry,found:=catalog_object_entry(object.catalog_id);if !found||!entry.emits_light do continue;has_bound:=false;for light in level_document.lights do if fmt.tprintf("light_%s",object.id)==light.id do has_bound=true;if has_bound do continue;base_y:=object.elevation;if object.story>=0&&object.story<len(level_document.stories) do base_y+=level_document.stories[object.story].base_elevation;if level_terrain_supports_position(&level_document,object.position,object.story) do base_y+=level_terrain_height(&level_document,object.position);vk_world_runtime_light_insert(&runtime_lights,Vk_World_Runtime_Light{position={object.position.x,base_y+entry.light_height,object.position.y,entry.light_range},color={f32(entry.light_color[0])/255,f32(entry.light_color[1])/255,f32(entry.light_color[2])/255,entry.light_intensity*.34},params={f32(entry.light_kind),(object.rotation+entry.light_facing)*f32(math.PI)/180,f32(math.cos(f64(entry.light_cone_angle*.5*f32(math.PI)/180))),0},room=vk_world_room_at(object.position),sequence=sequence},focus);sequence+=1}
	if g.screen==.Exterior do vk_world_add_city_vehicle_lights(&runtime_lights,g,focus)
	for &source in state.point_sources do source=-1;for &source in state.spot_sources do source=-1;point_count,spot_count:=0,0;point_limit:=lighting_quality_point_shadow_slots(g.lighting_quality);spot_limit:=lighting_quality_spot_shadow_slots(g.lighting_quality);face_budget:=lighting_quality_shadow_face_budget(g.lighting_quality);faces_used:=0
	cube_directions:=[6]Vec3{{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}};cube_ups:=[6]Vec3{{0,-1,0},{0,-1,0},{0,0,1},{0,0,-1},{0,-1,0},{0,-1,0}}
	for light in runtime_lights {if light.params[0]<.5&&point_count<point_limit&&faces_used+6<=face_budget {slot:=point_count;state.point_sources[slot]=light.sequence;position:=Vec3{light.position[0],light.position[1],light.position[2]};for face in 0..<6 {matrix_index:=4+slot*6+face;direction:=cube_directions[face];state.matrices[matrix_index]=glb_mat4_multiply(vk_world_perspective(math.PI/2,1,.08,max(light.position[3],.1)),vk_world_look_at(position,{position.x+direction.x,position.y+direction.y,position.z+direction.z},cube_ups[face]))};point_count+=1;faces_used+=6}else if light.params[0]>.5&&light.params[0]<1.5&&spot_count<spot_limit&&faces_used<face_budget {slot:=spot_count;state.spot_sources[slot]=light.sequence;position:=Vec3{light.position[0],light.position[1],light.position[2]};direction:=vk_world_normalize({f32(math.cos(f64(light.params[1]))),-.35,f32(math.sin(f64(light.params[1])))});matrix_index:=28+slot;cone:=f32(math.acos(f64(clamp(light.params[2],-.99,.99))))*2;state.matrices[matrix_index]=glb_mat4_multiply(vk_world_perspective(max(cone,.15),1,.08,max(light.position[3],.1)),vk_world_look_at(position,{position.x+direction.x,position.y+direction.y,position.z+direction.z},{0,1,0}));spot_count+=1;faces_used+=1}}
	mem.copy_non_overlapping(state.matrix_buffers[frame_index].mapped,raw_data(state.matrices[:]),len(state.matrices)*size_of(Glb_Mat4));engine.vk_cmd_image_barrier2(ctx,command,state.directional.image.image,{.TOP_OF_PIPE,.FRAGMENT_SHADER},{.EARLY_FRAGMENT_TESTS,.LATE_FRAGMENT_TESTS},{.SHADER_READ},{.DEPTH_STENCIL_ATTACHMENT_WRITE},.UNDEFINED,.DEPTH_ATTACHMENT_OPTIMAL,{.DEPTH});for cascade in 0..<count do vk_shadow_render_layer(scene,command,&state.directional,cascade,cascade,frame_index);engine.vk_cmd_image_barrier2(ctx,command,state.directional.image.image,{.EARLY_FRAGMENT_TESTS,.LATE_FRAGMENT_TESTS},{.FRAGMENT_SHADER},{.DEPTH_STENCIL_ATTACHMENT_WRITE},{.SHADER_READ},.DEPTH_ATTACHMENT_OPTIMAL,.SHADER_READ_ONLY_OPTIMAL,{.DEPTH})
	if point_count>0 {engine.vk_cmd_image_barrier2(ctx,command,state.points.image.image,{.TOP_OF_PIPE,.FRAGMENT_SHADER},{.EARLY_FRAGMENT_TESTS,.LATE_FRAGMENT_TESTS},{.SHADER_READ},{.DEPTH_STENCIL_ATTACHMENT_WRITE},.UNDEFINED,.DEPTH_ATTACHMENT_OPTIMAL,{.DEPTH});for slot in 0..<point_count {source:=state.point_sources[slot];for light in runtime_lights do if light.sequence==source {position:=Vec3{light.position[0],light.position[1],light.position[2]};for face in 0..<6 do vk_shadow_render_layer(scene,command,&state.points,slot*6+face,4+slot*6+face,frame_index,true,position,light.position[3],light.room);break}};engine.vk_cmd_image_barrier2(ctx,command,state.points.image.image,{.EARLY_FRAGMENT_TESTS,.LATE_FRAGMENT_TESTS},{.FRAGMENT_SHADER},{.DEPTH_STENCIL_ATTACHMENT_WRITE},{.SHADER_READ},.DEPTH_ATTACHMENT_OPTIMAL,.SHADER_READ_ONLY_OPTIMAL,{.DEPTH})}
	if spot_count>0 {engine.vk_cmd_image_barrier2(ctx,command,state.spots.image.image,{.TOP_OF_PIPE,.FRAGMENT_SHADER},{.EARLY_FRAGMENT_TESTS,.LATE_FRAGMENT_TESTS},{.SHADER_READ},{.DEPTH_STENCIL_ATTACHMENT_WRITE},.UNDEFINED,.DEPTH_ATTACHMENT_OPTIMAL,{.DEPTH});for slot in 0..<spot_count {source:=state.spot_sources[slot];for light in runtime_lights do if light.sequence==source {vk_shadow_render_layer(scene,command,&state.spots,slot,28+slot,frame_index,true,{light.position[0],light.position[1],light.position[2]},light.position[3],light.room);break}};engine.vk_cmd_image_barrier2(ctx,command,state.spots.image.image,{.EARLY_FRAGMENT_TESTS,.LATE_FRAGMENT_TESTS},{.FRAGMENT_SHADER},{.DEPTH_STENCIL_ATTACHMENT_WRITE},{.SHADER_READ},.DEPTH_ATTACHMENT_OPTIMAL,.SHADER_READ_ONLY_OPTIMAL,{.DEPTH})}
}

vk_world_draw_primitive_batchable :: proc(mesh:^Vk_World_Mesh,draw:^Vk_World_Draw,primitive_index:int)->bool {
	if draw.shadow_only||len(mesh.source.skin.joints)>0||draw.tint[3]<255 do return false
	alpha_mode:=primitive_index<len(mesh.source.alpha_modes)?mesh.source.alpha_modes[primitive_index]:0
	return alpha_mode!=2
}

vk_world_texture_flags :: proc(mesh:^Vk_World_Mesh,primitive_index,normal_index,roughness_index:int)->int {
	primitive:=mesh.source.primitives[primitive_index]
	material_name:=primitive_index<len(mesh.source.material_names)?mesh.source.material_names[primitive_index]:"";thin_wall:=glb_thin_wall_material_role(material_name)>0
	return (primitive.texture>=0?1:0)+(normal_index>=0?2:0)+(roughness_index>=0?4:0)+(thin_wall?8:0)
}

vk_world_draw_push :: proc(scene:^Vk_World_Scene,mesh:^Vk_World_Mesh,draw:^Vk_World_Draw,draw_index,primitive_index:int,skinned:bool=false,skin_offset:u32=0)->Vk_World_Push {
	primitive:=mesh.source.primitives[primitive_index];model:=vk_world_model(mesh.source,draw.x,draw.z,draw.width,draw.height,draw.yaw,draw.pitch,draw.base_y,draw.scale_by_footprint,draw.centered,draw.roll);primitive_tint:=[4]f32{f32(draw.tint[0])/255,f32(draw.tint[1])/255,f32(draw.tint[2])/255,f32(draw.tint[3])/255};material_name:=primitive_index<len(mesh.source.material_names)?mesh.source.material_names[primitive_index]:"";role:=glb_foliage_material_role(material_name);if draw.foliage_colors&&role==1 do primitive_tint={f32(draw.bark_tint[0])/255,f32(draw.bark_tint[1])/255,f32(draw.bark_tint[2])/255,f32(draw.bark_tint[3])/255};if draw.foliage_colors&&role==2 do primitive_tint={f32(draw.foliage_tint[0])/255,f32(draw.foliage_tint[1])/255,f32(draw.foliage_tint[2])/255,f32(draw.foliage_tint[3])/255};alpha_mode:=primitive_index<len(mesh.source.alpha_modes)?mesh.source.alpha_modes[primitive_index]:0;alpha_cutoff:=primitive_index<len(mesh.source.alpha_cutoffs)?mesh.source.alpha_cutoffs[primitive_index]:f32(.5);if draw.foliage_colors&&alpha_mode==2 {alpha_mode=1;alpha_cutoff=.5};alpha_state:=f32(alpha_mode)+alpha_cutoff*.1;normal_index:=primitive_index<len(mesh.source.normal_textures)?mesh.source.normal_textures[primitive_index]:-1;roughness_index:=primitive_index<len(mesh.source.roughness_textures)?mesh.source.roughness_textures[primitive_index]:-1;texture_flags:=vk_world_texture_flags(mesh,primitive_index,normal_index,roughness_index);pbr:=[4]f32{0,.72,1,0};authored_pbr:=primitive_index<len(mesh.source.roughness_factors);if primitive_index<len(mesh.source.metallic_factors) do pbr.x=mesh.source.metallic_factors[primitive_index];if authored_pbr do pbr.y=mesh.source.roughness_factors[primitive_index];if primitive_index<len(mesh.source.normal_scales) do pbr.z=mesh.source.normal_scales[primitive_index];pbr.w=authored_pbr?1:0;return {model,primitive_tint*primitive.base_color,{f32(texture_flags),f32(draw.surface_kind),f32(scene.draw_lights[draw_index].meta[1]),alpha_state},pbr,{skinned?1:0,skin_offset,u32(draw_index),0}}
}

vk_world_record :: proc(scene:^Vk_World_Scene,ctx:^engine.Vk_Context,command:vk.CommandBuffer,extent:vk.Extent2D,g:^Game,frame_index:int) {
	if len(scene.draws)==0 do return;if scene.depth.width!=extent.width||scene.depth.height!=extent.height {_=vk.DeviceWaitIdle(ctx.device);vk_ui_image_destroy(&scene.depth,ctx);if !vk_world_depth_create(ctx,extent.width,extent.height,&scene.depth) do return}
	scene.profile_lights_ms=0;scene.profile_batches_ms=0;scene.profile_unbatched_ms=0;lights_started:=time.tick_now()
	view:=vk_world_view_pose(g);eye,target,up:=view.eye,view.target,view.up;interior,baking:=view.interior,view.baking;projection_aspect:=baking?f32(1):f32(extent.width)/f32(max(extent.height,1));field_of_view:=f32(math.PI/3);if g.screen==.Exterior&&g.driving_vehicle>=0&&g.driving_vehicle<len(g.vehicles) do field_of_view=vehicle_camera_field_of_view(g.vehicles[g.driving_vehicle]);weather_strength:=g.screen==.Exterior?f32(1):clamp(g.environment_blend,0,1);if baking do weather_strength=0;interior_amount:=baking?f32(1):1-weather_strength;camera:=Vk_World_Camera{view_projection=glb_mat4_multiply(vk_world_perspective(field_of_view,projection_aspect,.08,140),vk_world_look_at(eye,target,up)),camera_position={eye.x,eye.y,eye.z,1},lighting={interior_amount,1-interior_amount*.18,0,0},atmosphere={weather_strength,g.animation_time,world_time_of_day(g.animation_time),0}};for shadow_matrix,index in scene.shadows.matrices[:4] do camera.directional_shadow_matrices[index]=shadow_matrix;camera.directional_shadow_splits=scene.shadows.splits;camera.directional_shadow_params={f32(scene.shadows.cascade_count),.0007,.003,1/f32(max(scene.shadows.directional.image.width,1))}
	runtime_lights:=make([dynamic]Vk_World_Runtime_Light,0,VK_WORLD_MAX_LIGHTS,context.temp_allocator);sequence:=0
	// The character studio is a diagnostic stage, so it uses a stable neutral
	// review rig instead of inheriting the active level's night lighting. A broad
	// warm key and cool fill for each model keep skin, clothing, and silhouettes
	// readable while retaining enough directionality to reveal deformation.
	if g.character_studio {
		studio_x:=[4]f32{-3,-1,1,3}
		for x in studio_x {
			append(&runtime_lights,Vk_World_Runtime_Light{position={x,3.8,2.6,7.5},color={1.0,.91,.78,1.65},params={2,0,0,0},room=vk_world_room_at({x,0}),sequence=sequence});sequence+=1
		}
		append(&runtime_lights,Vk_World_Runtime_Light{position={0,2.7,-3.2,9},color={.48,.67,1.0,.82},params={2,0,0,0},room=vk_world_room_at({0,0}),sequence=sequence});sequence+=1
	}
	if interior {for light in level_document.lights {if light.story!=level_document.active_story do continue;base_y:=f32(0);if light.story>=0&&light.story<len(level_document.stories) do base_y=level_document.stories[light.story].base_elevation;light_level:=f32(1);for object in level_document.objects {if fmt.tprintf("light_%s",object.id)==light.id {interactive_index:=runtime_interactive_index(g,object.id);if interactive_index>=0 do light_level=g.interactives[interactive_index].light_level;break}};runtime:=Vk_World_Runtime_Light{position={light.position.x,base_y+light.elevation,light.position.y,light.range},color={f32(light.color[0])/255,f32(light.color[1])/255,f32(light.color[2])/255,light.intensity*.34*light_level},params={f32(light.kind),light.facing*f32(math.PI)/180,f32(math.cos(f64(light.cone_angle*.5*f32(math.PI)/180))),0},room=vk_world_room_at(light.position),sequence=sequence};vk_world_runtime_light_insert(&runtime_lights,runtime,eye);sequence+=1}}
	if interior {for object in level_document.objects {if object.story!=level_document.active_story do continue;entry,found:=catalog_object_entry(object.catalog_id);if !found||!entry.emits_light do continue;has_bound_light:=false;for light in level_document.lights do if fmt.tprintf("light_%s",object.id)==light.id do has_bound_light=true;if has_bound_light do continue;base_y:=object.elevation;if object.story>=0&&object.story<len(level_document.stories) do base_y+=level_document.stories[object.story].base_elevation;if level_terrain_supports_position(&level_document,object.position,object.story) do base_y+=level_terrain_height(&level_document,object.position);light_level:=f32(1);interactive_index:=runtime_interactive_index(g,object.id);if interactive_index>=0 do light_level=g.interactives[interactive_index].light_level;runtime:=Vk_World_Runtime_Light{position={object.position.x,base_y+entry.light_height,object.position.y,entry.light_range},color={f32(entry.light_color[0])/255,f32(entry.light_color[1])/255,f32(entry.light_color[2])/255,entry.light_intensity*.34*light_level},params={f32(entry.light_kind),(object.rotation+entry.light_facing)*f32(math.PI)/180,f32(math.cos(f64(entry.light_cone_angle*.5*f32(math.PI)/180))),0},room=vk_world_room_at(object.position),sequence=sequence};vk_world_runtime_light_insert(&runtime_lights,runtime,eye);sequence+=1}}
	if g.screen==.Exterior do vk_world_add_city_vehicle_lights(&runtime_lights,g,eye)
	for light,slot in runtime_lights {camera.light_positions[slot]=light.position;camera.light_colors[slot]=light.color;camera.light_params[slot]=light.params;for source,shadow_slot in scene.shadows.point_sources do if source==light.sequence do camera.light_shadow_meta[slot]={1,f32(shadow_slot),light.position[3],.003};for source,shadow_slot in scene.shadows.spot_sources do if source==light.sequence do camera.light_shadow_meta[slot]={2,f32(shadow_slot),light.position[3],.002}};for matrix_index in 0..<24 do camera.point_shadow_matrices[matrix_index]=scene.shadows.matrices[4+matrix_index];for shadow_slot in 0..<10 do camera.local_shadow_matrices[shadow_slot]=scene.shadows.matrices[28+shadow_slot];camera.lighting[2]=f32(len(runtime_lights));vk_world_build_draw_light_lists(scene,runtime_lights[:],g.lighting_quality,frame_index)
	scene.profile_lights_ms=time.duration_seconds(time.tick_diff(lights_started,time.tick_now()))*1000;mem.copy_non_overlapping(scene.cameras[frame_index].mapped,&camera,size_of(camera));viewport:=vk.Viewport{width=f32(extent.width),height=f32(extent.height),minDepth=0,maxDepth=1};scissor:=vk.Rect2D{extent=extent};vk.CmdSetViewport(command,0,1,&viewport);vk.CmdSetScissor(command,0,1,&scissor);vk.CmdBindPipeline(command,.GRAPHICS,scene.pipeline);batches_started:=time.tick_now()
	// Opaque static props are order-independent. Preserve their per-object data
	// in a storage buffer and collapse each repeated mesh primitive to one draw.
	mesh_offsets:=make([]int,len(scene.meshes)+1,context.temp_allocator);draw_order:=make([]int,len(scene.draws),context.temp_allocator);for draw in scene.draws do mesh_offsets[draw.mesh+1]+=1;for i in 1..<len(mesh_offsets) do mesh_offsets[i]+=mesh_offsets[i-1];cursors:=make([]int,len(scene.meshes),context.temp_allocator);copy(cursors,mesh_offsets[:len(scene.meshes)]);for draw,draw_index in scene.draws {draw_order[cursors[draw.mesh]]=draw_index;cursors[draw.mesh]+=1}
	instance_data:=transmute([^]Vk_World_Push)(scene.instance_buffer.mapped);instance_start:=frame_index*VK_WORLD_INSTANCES_PER_FRAME;instance_count:=instance_start;vertex_offset:=vk.DeviceSize(0)
	for &mesh,mesh_index in scene.meshes {
		if len(mesh.source.skin.joints)>0 do continue
		vk.CmdBindVertexBuffers(command,0,1,&mesh.vertices.handle,&vertex_offset);vk.CmdBindIndexBuffer(command,mesh.indices.handle,0,.UINT32)
		for primitive,primitive_index in mesh.source.primitives {
			batch_start:=instance_count
			for order_index in mesh_offsets[mesh_index]..<mesh_offsets[mesh_index+1] {
				draw_index:=draw_order[order_index];draw:=&scene.draws[draw_index]
				if !vk_world_draw_primitive_batchable(&mesh,draw,primitive_index)||instance_count>=instance_start+VK_WORLD_INSTANCES_PER_FRAME do continue
				instance_data[instance_count]=vk_world_draw_push(scene,&mesh,draw,draw_index,primitive_index);instance_count+=1
			}
			batch_count:=instance_count-batch_start;if batch_count==0 do continue
			set_index:=primitive_index*engine.MAX_FRAMES_IN_FLIGHT+frame_index;if set_index<0||set_index>=len(mesh.sets) do set_index=frame_index;set:=mesh.sets[set_index];vk.CmdBindDescriptorSets(command,.GRAPHICS,scene.pipeline_layout,0,1,&set,0,nil);push:=Vk_World_Push{};push.skin={0,0,u32(batch_start),1};vk.CmdPushConstants(command,scene.pipeline_layout,{.VERTEX,.FRAGMENT},0,u32(size_of(push)),&push);vk.CmdDrawIndexed(command,u32(primitive.count),u32(batch_count),u32(primitive.first),0,0)
		}
	}
	scene.profile_batches_ms=time.duration_seconds(time.tick_diff(batches_started,time.tick_now()))*1000;unbatched_started:=time.tick_now()
	for &draw,draw_index in scene.draws {if draw.shadow_only do continue;mesh:=&scene.meshes[draw.mesh];skinned:=len(mesh.source.skin.joints)>0;palette_slot:=skinned?vk_world_skin_slot(scene,draw_index):-1;if skinned&&(palette_slot<0||!vk_world_write_palette(scene,mesh.source,&draw,palette_slot,frame_index)) do continue;skin_offset:=u32(max(palette_slot,0)*GLB_MAX_JOINTS);offset:=vk.DeviceSize(0);vk.CmdBindVertexBuffers(command,0,1,&mesh.vertices.handle,&offset);vk.CmdBindIndexBuffer(command,mesh.indices.handle,0,.UINT32);model:=vk_world_model(mesh.source,draw.x,draw.z,draw.width,draw.height,draw.yaw,draw.pitch,draw.base_y,draw.scale_by_footprint,draw.centered,draw.roll);tint:=[4]f32{f32(draw.tint[0])/255,f32(draw.tint[1])/255,f32(draw.tint[2])/255,f32(draw.tint[3])/255};light_selector:=f32(scene.draw_lights[draw_index].meta[1]);for primitive,primitive_index in mesh.source.primitives {if vk_world_draw_primitive_batchable(mesh,&draw,primitive_index) do continue;primitive_tint:=tint;material_name:=primitive_index<len(mesh.source.material_names)?mesh.source.material_names[primitive_index]:"";role:=glb_foliage_material_role(material_name);if draw.foliage_colors&&role==1 do primitive_tint={f32(draw.bark_tint[0])/255,f32(draw.bark_tint[1])/255,f32(draw.bark_tint[2])/255,f32(draw.bark_tint[3])/255};if draw.foliage_colors&&role==2 do primitive_tint={f32(draw.foliage_tint[0])/255,f32(draw.foliage_tint[1])/255,f32(draw.foliage_tint[2])/255,f32(draw.foliage_tint[3])/255};set_index:=primitive_index*engine.MAX_FRAMES_IN_FLIGHT+frame_index;if set_index<0||set_index>=len(mesh.sets) do set_index=frame_index;set:=mesh.sets[set_index];vk.CmdBindDescriptorSets(command,.GRAPHICS,scene.pipeline_layout,0,1,&set,0,nil);alpha_mode:=primitive_index<len(mesh.source.alpha_modes)?mesh.source.alpha_modes[primitive_index]:0;alpha_cutoff:=primitive_index<len(mesh.source.alpha_cutoffs)?mesh.source.alpha_cutoffs[primitive_index]:f32(.5);if draw.foliage_colors&&alpha_mode==2 {alpha_mode=1;alpha_cutoff=.5};alpha_state:=f32(alpha_mode)+alpha_cutoff*.1;normal_index:=primitive_index<len(mesh.source.normal_textures)?mesh.source.normal_textures[primitive_index]:-1;roughness_index:=primitive_index<len(mesh.source.roughness_textures)?mesh.source.roughness_textures[primitive_index]:-1;texture_flags:=vk_world_texture_flags(mesh,primitive_index,normal_index,roughness_index);pbr:=[4]f32{0,.72,1,0};authored_pbr:=primitive_index<len(mesh.source.roughness_factors);if primitive_index<len(mesh.source.metallic_factors) do pbr.x=mesh.source.metallic_factors[primitive_index];if authored_pbr do pbr.y=mesh.source.roughness_factors[primitive_index];if primitive_index<len(mesh.source.normal_scales) do pbr.z=mesh.source.normal_scales[primitive_index];pbr.w=authored_pbr?1:0;push:=Vk_World_Push{model,primitive_tint*primitive.base_color,{f32(texture_flags),f32(draw.surface_kind),light_selector,alpha_state},pbr,{skinned?1:0,skin_offset,u32(draw_index),0}};vk.CmdPushConstants(command,scene.pipeline_layout,{.VERTEX,.FRAGMENT},0,u32(size_of(push)),&push);vk.CmdDrawIndexed(command,u32(primitive.count),1,u32(primitive.first),0,0)}}
	scene.profile_unbatched_ms=time.duration_seconds(time.tick_diff(unbatched_started,time.tick_now()))*1000
}

vk_world_build_city :: proc(scene:^Vk_World_Scene,ctx:^engine.Vk_Context,g:^Game) {
	city_center_x,city_center_z:=CITY_WORLD_WIDTH*.5,CITY_WORLD_HEIGHT*.5
	// As with an interior cutaway, authored ground ends over a distinct negative-
	// space layer instead of visually promising terrain past an invisible wall.
	// The interior background shader returns a fully composed color and is only
	// safe beneath the compact dollhouse. Keep the city's much larger border on
	// the ordinary depth-tested terrain path so it can never paint over geometry.
	vk_world_add_sized(scene,ctx,&city_background_mesh,city_center_x,city_center_z,CITY_WORLD_WIDTH+city_world(240),.001,0,{19,77,87,255},7,-.08)
	// Preserve the authored terrain mesh's Y range. The generic sized-floor path
	// intentionally flattens a mesh to its requested height.
	vk_world_add(scene,ctx,&city_ground_mesh,city_center_x,city_center_z,city_ground_mesh.max.y-city_ground_mesh.min.y,0,{92,142,96,255},false,7,-.045)
	// Road vertices are baked against the same height function as the ground,
	// preserving markings and curbs while removing rigid-tile steps.
	for &road in city_bent_road_meshes {if !road.ready do continue;cx,cz:=(road.min.x+road.max.x)*.5,(road.min.z+road.max.z)*.5;vk_world_add(scene,ctx,&road,cx,cz,road.max.y-road.min.y,0,{255,255,255,255},false,7,road.min.y+.01)}
	for by in 0..<CITY_HEIGHT/CITY_BLOCK {for bx in 0..<CITY_WIDTH/CITY_BLOCK {layout_x,layout_z,place:=city_building_site(bx,by);wx,wz:=city_world(layout_x),city_world(layout_z);if !place||!city_render_chunk_visible(g,wx,wz,CITY_BUILDING_DRAW_DISTANCE,CITY_DRIVING_BEHIND_DISTANCE) do continue;mesh_index,height,yaw,tint:=city_building_style(bx,by,layout_x);vk_world_add(scene,ctx,&city_meshes[mesh_index],wx,wz,city_world(height),yaw,tint,false,8,city_elevation(wx,wz))}}
	payload:=mystery_game_payload(g);quest_index:=payload==nil?-1:city_landmark_index(g,payload.city_destination);if quest_index>=0 {quest,ok:=city_landmark_at(g,quest_index);if ok&&city_quest_marker_visible(g,quest) {dx,dz:=quest.x-g.city_x,quest.y-g.city_y;if dx*dx+dz*dz<=CITY_DYNAMIC_DRAW_DISTANCE*CITY_DYNAMIC_DRAW_DISTANCE {center:=Vec2{quest.x,quest.y};if !city_quest_marker_built||city_quest_marker_center!=center {city_quest_marker_mesh=procedural_city_quest_marker_mesh(center,3.2);city_quest_marker_center=center;city_quest_marker_built=true;_=vk_world_refresh_mesh(scene,ctx,&city_quest_marker_mesh)};marker_base:=city_surface_elevation(quest.x,quest.y)+city_quest_marker_mesh.min.y+.035;vk_world_add(scene,ctx,&city_quest_marker_mesh,quest.x,quest.y,6.4,0,{255,202,72,205},true,7,marker_base)}}}
	for mark in g.vehicle_skid_marks {if !mark.active||mark.age>=VEHICLE_SKID_LIFETIME do continue;fade:=1-mark.age/VEHICLE_SKID_LIFETIME;alpha:=u8(clamp(mark.strength*fade*125,0,125));vk_world_add(scene,ctx,&vehicle_skid_mesh,mark.position.x,mark.position.y,.62,mark.heading,{8,10,12,alpha},true,7,city_elevation(mark.position.x,mark.position.y)+.022)}
	for prop in g.city_furniture {dx,dz:=prop.x-g.city_x,prop.y-g.city_y;if dx*dx+dz*dz>CITY_DYNAMIC_DRAW_DISTANCE*CITY_DYNAMIC_DRAW_DISTANCE do continue;template:=city_furniture_template(prop.kind);vk_world_add(scene,ctx,&city_furniture_meshes[int(prop.kind)],prop.x,prop.y,template.height,prop.heading,template.tint,false,9,city_elevation(prop.x,prop.y),prop.roll,prop.pitch)}
	// Kenney's car meshes face model-space -Z. Rotate that axis onto the
	// simulation heading (+X at zero) without reversing the visible vehicle.
	for car,i in g.vehicles {dx,dz:=car.x-g.city_x,car.y-g.city_y;if dx*dx+dz*dz>CITY_DYNAMIC_DRAW_DISTANCE*CITY_DYNAMIC_DRAW_DISTANCE do continue;rough_roll,rough_pitch:=vehicle_rough_body_pose(car);vk_world_add(scene,ctx,&city_car_meshes[i],car.x,car.y,1.05,car.heading-f32(math.PI/2),{255,255,255,255},false,10,city_elevation(car.x,car.y),car.body_roll+rough_roll,car.body_pitch+rough_pitch)}
	if g.driving_vehicle<0 {player:=&g.player_animation;vk_world_add_animated(scene,ctx,&character_meshes[0],g.city_x,g.city_y,1.65,character_render_yaw(g.city_angle),{255,255,255,255},player.current,player.transitioning?player.next:-1,player.time,player.next_time,player.transitioning?player.transition:0,city_surface_elevation(g.city_x,g.city_y),9)}
}

vk_world_build_catalog_thumbnail :: proc(scene:^Vk_World_Scene,ctx:^engine.Vk_Context,g:^Game) {
	if g.catalog_bake_index<0||g.catalog_bake_index>=len(editor_catalog.entries) do return
	entry:=editor_catalog.entries[g.catalog_bake_index];mesh,ok:=catalog_object_mesh(entry.id);if !ok do return;span_x:=mesh.max.x-mesh.min.x;span_y:=mesh.max.y-mesh.min.y;span_z:=mesh.max.z-mesh.min.z
	// Normalize by the complete bounds, not just height. This keeps broad tables and
	// tall bookcases at the same visual scale without catalog-specific camera hacks.
	max_span:=max(span_x,max(span_y,span_z));if max_span<=0 do max_span=1
	normalized_height:=2.5*span_y/max_span
	vk_world_add(scene,ctx,&catalog_thumbnail_floor,0,0,12,0,{226,220,203,255},true,0,-.035)
	vk_world_add(scene,ctx,mesh,0,0,normalized_height,-f32(math.PI)/8,{255,255,255,255},false,0,0)
}

house_wall_tint :: proc(x,z:f32)->[4]u8 {
	// Room-specific wall coverings establish purpose before any HUD text is read.
	if z<5 do return {176,164,143,255} // warm dining plaster
	if z<9&&x<12 do return {118,139,125,255} // quiet green study
	if z<9&&x<17 do return {126,140,153,255} // blue-gray gallery
	if z<9 do return {169,157,124,255} // pantry ochre
	return {148,151,145,255} // garden stone
}

// The background is a deliberately separate world layer beneath the dollhouse.
// Its palette follows the room occupied by the investigator, so the surrounding
// negative space belongs to the current interior instead of reading as a void.
house_background_tint :: proc(g:^Game)->[4]u8 {
	switch world_location_index(g) {
	// These are deliberately near-black sRGB palette values. The world shader
	// decodes draw tints to linear light before rendering to the sRGB target.
	case 0: return {7,4,3,255} // dining: warm walnut/cloth
	case 1: return {4,5,7,255} // gallery: blue slate
	case 2: return {3,7,5,255} // study: ink green
	case 3: return {4,7,5,255} // garden: moonlit foliage
	case:   return {7,6,3,255} // pantry: muted ochre
	}
}

house_cutaway_amount :: proc(g:^Game)->f32 {
	if g.capture_cutaway_override {amount:=clamp(g.capture_cutaway_amount,0,1);return amount*amount*(3-2*amount)}
	explicit:=g.top_down_camera||editor_state.view==.Cutaway
	amount:=explicit?f32(1):g.wall_view==.Walls_Up?f32(0):g.wall_view==.Walls_Down?f32(1):(g.editor_mode!=.Build?clamp(g.cutaway_transition,0,1):f32(0))
	return amount*amount*(3-2*amount)
}

house_render_wall_height :: proc(g:^Game)->f32 {
	amount:=house_cutaway_amount(g)
	height:=house_authored_wall_height();return height+(min(HOUSE_CUTAWAY_HEIGHT,height)-height)*amount
}

// Structural wall meshes are already authored at their final plan dimensions.
// Supplying that span as the draw width keeps X/Z at unit scale while the
// cutaway transition changes only their vertical height.
house_render_wall_width :: proc(mesh:^Glb_Mesh)->f32 {
	return max(mesh.max.x-mesh.min.x,.0001)
}

house_wall_cap_tint :: proc(amount:f32)->[4]u8 {
	t:=clamp(amount,0,1)
	return {u8(132+36*t),u8(138+36*t),u8(134+36*t),255}
}

// Horizontal cut planes share one material ramp.
house_wall_section_tint :: proc(amount:f32)->[4]u8 {return house_wall_cap_tint(amount)}

// Vertical reveals receive less overhead light than the horizontal plane.
// Darkening the same base material gives mixed-height boundaries readable
// depth without introducing a separate architectural finish.
house_wall_junction_tint :: proc(amount:f32)->[4]u8 {
	cap:=house_wall_section_tint(amount)
	return {u8(f32(cap[0])*.76),u8(f32(cap[1])*.76),u8(f32(cap[2])*.76),255}
}

house_wall_cap_edge_tint :: proc(amount:f32)->[4]u8 {
	cap:=house_wall_section_tint(amount);t:=clamp(amount,0,1)
	return {u8(f32(cap[0])*(1-.18*t)),u8(f32(cap[1])*(1-.18*t)),u8(f32(cap[2])*(1-.18*t)),255}
}

HOUSE_WALL_CAP_EDGE_OVERHANG :: f32(.036)

house_wall_cap_draw_height :: proc(mesh:^Glb_Mesh)->f32 {return max(mesh.max.y-mesh.min.y,.001)}

house_wall_section_amount :: proc(g:^Game,index:int)->f32 {
	if index<0||index>=HOUSE_WALL_SECTION_CAPACITY do return 0
	t:=clamp(g.wall_cutaways[index],0,1);return t*t*(3-2*t)
}

house_wall_section_height :: proc(g:^Game,index:int)->f32 {
	amount:=house_wall_section_amount(g,index);height:=house_authored_wall_height();return height+(min(HOUSE_CUTAWAY_HEIGHT,height)-height)*amount
}

house_wall_uniform_amount :: proc(g:^Game)->(f32,bool) {
	if len(house_walls)==0 do return 0,false
	amount:=house_wall_section_amount(g,0);for i in 1..<len(house_walls) do if math.abs(house_wall_section_amount(g,i)-amount)>.001 do return 0,false
	return amount,true
}

house_wall_junction_reveal_height :: proc(g:^Game,index:int,endpoint:Vec2)->f32 {
	if index<0||index>=len(house_walls) do return 0
	section_height:=house_wall_section_height(g,index);neighbor_height:=section_height
	for other,j in house_walls {
		if j==index do continue
		// Endpoints may meet another endpoint or terminate into the middle of a
		// run at a T junction, so test against the complete neighboring segment.
		if point_segment_distance_sq(endpoint.x,endpoint.y,other.a,other.b)<=.025*.025 do neighbor_height=max(neighbor_height,house_wall_section_height(g,j))
	}
	return max(neighbor_height-section_height,f32(0))
}

house_wall_finish_light_anchor :: proc(index:int,face_point:Vec2)->Vec2 {
	if index<0||index>=len(house_walls) do return face_point
	host:=house_walls[index];dx,dz:=host.b.x-host.a.x,host.b.y-host.a.y;length:=f32(math.sqrt(f64(dx*dx+dz*dz)));if length<=.001 do return face_point
	tx,tz:=dx/length,dz/length;nx,nz:=-tz,tx;minimum,maximum:=f32(0),length
	for wall in house_walls {wdx,wdz:=wall.b.x-wall.a.x,wall.b.y-wall.a.y;wall_length:=f32(math.sqrt(f64(wdx*wdx+wdz*wdz)));if wall_length<=.001 do continue;if math.abs((wdx*tz-wdz*tx)/wall_length)>.01 do continue;line_distance:=math.abs((wall.a.x-host.a.x)*nz-(wall.a.y-host.a.y)*nx);if line_distance>.03 do continue;points:=[2]Vec2{};points[0]=wall.a;points[1]=wall.b;for point in points {projection:=(point.x-host.a.x)*tx+(point.y-host.a.y)*tz;minimum=min(minimum,projection);maximum=max(maximum,projection)}}
	face_offset:=(face_point.x-host.a.x)*nx+(face_point.y-host.a.y)*nz;mid:=(minimum+maximum)*.5;return {host.a.x+tx*mid+nx*face_offset,host.a.y+tz*mid+nz*face_offset}
}

house_wall_finish_light_group :: proc(index:int,face_point:Vec2)->(Vec2,u64) {
	anchor:=house_wall_finish_light_anchor(index,face_point);if index<0||index>=len(house_walls) do return anchor,0
	host:=house_walls[index];dx,dz:=host.b.x-host.a.x,host.b.y-host.a.y;length:=f32(math.sqrt(f64(dx*dx+dz*dz)));if length<=.001 do return anchor,0
	tx,tz:=dx/length,dz/length;if tx<-.001||(math.abs(tx)<=.001&&tz<0) {tx=-tx;tz=-tz}
	qx:=u64(clamp(int(math.round(f64(anchor.x*100))),0,0xfffff));qz:=u64(clamp(int(math.round(f64(anchor.y*100))),0,0xfffff))
	qtx:=u64(clamp(int(math.round(f64((tx+1)*500))),0,0x3ff));qtz:=u64(clamp(int(math.round(f64((tz+1)*500))),0,0x3ff));room:=u64(clamp(vk_world_room_at(anchor)+2,0,0xff))
	return anchor,1+qx+(qz<<20)+(qtx<<40)+(qtz<<50)+(room<<60)
}

house_opening_wall_height :: proc(g:^Game,opening:Plan_Opening)->f32 {
	index:=house_opening_host_wall_index(opening);if index>=0 do return house_wall_section_height(g,index);return house_authored_wall_height()
}

house_aperture_top_for_height :: proc(opening:Plan_Opening,host_height:f32)->f32 {
	if opening.id=="window_study_courtyard" {sill:=opening.sill_height>0?opening.sill_height:f32(.72);glazing:=opening.height>0?opening.height:f32(1.4);return min(house_authored_wall_height(),sill+glazing+HOUSE_WINDOW_FRAME_RAIL_HEIGHT)}
	return host_height
}

house_opening_aperture_top :: proc(g:^Game,opening:Plan_Opening)->f32 {
	return house_aperture_top_for_height(opening,house_opening_wall_height(g,opening))
}

house_wall_height_at_point :: proc(g:^Game,point:Vec2)->f32 {
	for wall,i in house_walls do if point_segment_distance_sq(point.x,point.y,wall.a,wall.b)<.12*.12 do return house_wall_section_height(g,i)
	return house_authored_wall_height()
}

house_wall_height_near_point :: proc(g:^Game,point:Vec2,max_distance:f32=.35)->f32 {
	index:=house_wall_index_near_point(point,max_distance)
	return index>=0?house_wall_section_height(g,index):house_authored_wall_height()
}

house_wall_index_near_point :: proc(point:Vec2,max_distance:f32=.35)->int {
	best:=max_distance*max_distance;index:=-1
	for wall,i in house_walls {distance:=point_segment_distance_sq(point.x,point.y,wall.a,wall.b);if distance<best {best=distance;index=i}}
	return index
}

house_wall_attachment_pose :: proc(index:int,authored:Vec2)->(x,z,yaw:f32,ok:bool) {
	if index<0||index>=len(house_walls) do return 0,0,0,false
	wall:=house_walls[index];dx,dz:=wall.b.x-wall.a.x,wall.b.y-wall.a.y;length_sq:=dx*dx+dz*dz
	if length_sq<=.0001 do return 0,0,0,false
	t:=clamp(((authored.x-wall.a.x)*dx+(authored.y-wall.a.y)*dz)/length_sq,0,1)
	px,pz:=wall.a.x+dx*t,wall.a.y+dz*t;length:=f32(math.sqrt(f64(length_sq)));nx,nz:= -dz/length,dx/length
	side:=(authored.x-px)*nx+(authored.y-pz)*nz;positive:=side>=0
	// Authored points occasionally sit almost exactly on the centerline. Prefer
	// the wall's sole interior face in that case, and never mount art outdoors.
	if math.abs(side)<.01 {if wall.positive_interior&&!wall.negative_interior do positive=true;else if wall.negative_interior&&!wall.positive_interior do positive=false}
	if positive&&!wall.positive_interior&&wall.negative_interior do positive=false
	if !positive&&!wall.negative_interior&&wall.positive_interior do positive=true
	sign:=positive?f32(1):f32(-1);offset:=f32(HOUSE_WALL_THICKNESS*.5+.012)
	return px+nx*offset*sign,pz+nz*offset*sign,f32(math.atan2(f64(dz),f64(dx)))+(positive?0:f32(math.PI)),true
}

HOUSE_WALL_ART_FADE_BOTTOM :: f32(1.52)
HOUSE_WALL_ART_FADE_TOP :: f32(2.42)

house_wall_art_opacity :: proc(wall_height:f32)->u8 {
	t:=clamp((wall_height-HOUSE_WALL_ART_FADE_BOTTOM)/(HOUSE_WALL_ART_FADE_TOP-HOUSE_WALL_ART_FADE_BOTTOM),0,1)
	t=t*t*(3-2*t)
	return u8(math.round(f64(t*255)))
}

house_wall_art_supported :: proc(wall_height:f32)->bool {return house_wall_art_opacity(wall_height)>0}

house_door_render_height :: proc(opening:Plan_Opening)->f32 {
	return opening.height>0?opening.height:f32(2.1)
}

house_door_render_width :: proc(aperture_width:f32)->f32 {
	return max(aperture_width,f32(.001))
}

// Casing belongs to the movable/readable door assembly, not to the masonry
// being sectioned. Keeping this separate makes that policy explicit at call sites.
house_door_casing_height :: proc(opening:Plan_Opening)->f32 {return house_door_render_height(opening)}
HOUSE_DOOR_CASING_RAIL :: f32(.085)

house_door_casing_jamb_height :: proc(opening:Plan_Opening,host_height:f32)->f32 {
	return clamp(host_height,0,house_door_casing_height(opening))
}

house_door_casing_head_base :: proc(opening:Plan_Opening)->f32 {
	return house_door_casing_height(opening)-HOUSE_DOOR_CASING_RAIL*.5
}

house_door_casing_head_height :: proc(opening:Plan_Opening,host_height:f32)->f32 {
	return clamp(host_height-house_door_casing_head_base(opening),0,HOUSE_DOOR_CASING_RAIL)
}

house_door_handle_height :: proc(opening:Plan_Opening)->f32 {return min(f32(1.02),house_door_render_height(opening)*.5)}
HOUSE_DOOR_HANDLE_ALONG :: f32(.78)

house_window_lower_masonry_height :: proc(sill_height,host_height:f32)->f32 {
	return max(min(sill_height,host_height),f32(0))
}

house_window_light_columns :: proc(width:f32)->int {
	if width<1.1 do return 1
	if width<2.4 do return 2
	if width<3.6 do return 3
	return clamp(int(math.round(f64(width/1.15))),3,6)
}

house_window_light_rows :: proc(height:f32)->int {
	if height<1.1 do return 1
	if height<2.2 do return 2
	return 3
}

house_window_muntin_width :: proc(rail:f32)->f32 {return max(rail*.55,f32(.022))}
house_window_internal_vertical_width :: proc(style:Window_Style,rail:f32)->f32 {if style==.Casement do return rail;return house_window_muntin_width(rail)}
house_window_internal_horizontal_width :: proc(style:Window_Style,rail:f32)->f32 {if style==.Awning||style==.Double_Hung do return rail;return house_window_muntin_width(rail)}
house_window_glazing_bead_width :: proc(rail:f32)->f32 {return clamp(rail*.28,f32(.014),f32(.022))}
house_window_casing_width :: proc(interior:bool)->f32 {return interior?f32(.085):f32(.065)}
house_window_head_flashing_overhang :: proc()->f32 {return .12}
house_window_head_flashing_end_dam_width :: proc()->f32 {return .022}
house_window_head_flashing_end_dam_height :: proc()->f32 {return .055}
house_window_operable_sash_offset :: proc(style:Window_Style)->f32 {if style==.Casement||style==.Awning do return .006;return 0}
house_window_operable_frame_width :: proc(rail:f32)->f32 {return clamp(rail*.48,f32(.022),f32(.032))}
house_window_operable_mullion_count :: proc(style:Window_Style,columns:int)->int {if style==.Casement do return max(columns-1,0);return 0}
house_window_perimeter_sealant_width :: proc()->f32 {return .010}
house_window_interior_caulk_width :: proc()->f32 {return .007}
house_window_hardware_offset :: proc()->f32 {return house_window_frame_v_mesh.max.z+.012}
house_window_casement_hardware_count :: proc(columns:int)->(handles,hinge_sides:int) {if columns<=1 do return 1,1;return 2,2}
house_window_casement_handle_along :: proc(columns,index:int,side,rail:f32,hinge_right:bool=false)->f32 {if columns<=1 do return hinge_right?-side+rail*.65:side-rail*.65;return (index==0?-1:1)*rail*.65}
house_window_casement_hinge_along :: proc(columns,index:int,side,rail:f32,hinge_right:bool=false)->f32 {if columns<=1 do return hinge_right?side-rail*.5:-side+rail*.5;return (index==0?-1:1)*(side-rail*.5)}
house_window_double_hung_sash_offset :: proc()->f32 {return .012}
house_window_double_hung_upper_bead_offset :: proc(frame_offset:f32)->f32 {return frame_offset-house_window_double_hung_sash_offset()*2}
house_window_double_hung_stile_along :: proc(glass_width,rail:f32)->f32 {return max(glass_width*.5-rail*.5,f32(0))}
house_window_double_hung_parting_bead_width :: proc(rail:f32)->f32 {return clamp(rail*.26,f32(.012),f32(.018))}
house_window_double_hung_parting_bead_along :: proc(glass_width,rail:f32)->f32 {return max(glass_width*.5-rail*.12,f32(0))}
house_window_room_sign :: proc(a,b:Vec2)->f32 {
	dx,dz:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dz*dz)));if length<.001 do return 1
	mx,mz:=(a.x+b.x)*.5,(a.y+b.y)*.5;nx,nz:= -dz/length,dx/length;sample:=f32(HOUSE_WALL_THICKNESS*.5+.16)
	positive_x,positive_z:=mx+nx*sample,mz+nz*sample;negative_x,negative_z:=mx-nx*sample,mz-nz*sample
	positive_inside:=positive_x>=0&&positive_x<f32(HOUSE_SURFACE_WIDTH)&&positive_z>=0&&positive_z<f32(HOUSE_SURFACE_HEIGHT)&&house_space_kind_at(positive_x,positive_z)==.Interior
	negative_inside:=negative_x>=0&&negative_x<f32(HOUSE_SURFACE_WIDTH)&&negative_z>=0&&negative_z<f32(HOUSE_SURFACE_HEIGHT)&&house_space_kind_at(negative_x,negative_z)==.Interior
	if positive_inside!=negative_inside do return positive_inside?1:-1
	return 1
}

house_window_style_grid :: proc(style:Window_Style,width,height:f32)->(int,int) {
	switch style {
	case .Picture:return 1,1
	case .Casement:return house_window_light_columns(width),1
	case .Awning:return 1,house_window_light_rows(height)
	case .Double_Hung:return house_window_light_columns(width),2
	case .Fixed:return house_window_light_columns(width),house_window_light_rows(height)
	}
	return house_window_light_columns(width),house_window_light_rows(height)
}

vk_world_build_house :: proc(scene:^Vk_World_Scene,ctx:^engine.Vk_Context,g:^Game) {
	house_phase_started:=time.tick_now()
	scene.profile_house_structure_ms=0;scene.profile_house_surfaces_ms=0;scene.profile_house_walls_ms=0;scene.profile_house_openings_ms=0;scene.profile_house_objects_ms=0;scene.profile_house_characters_ms=0
	active_base:=f32(0);if level_document.active_story>=0&&level_document.active_story<len(level_document.stories) do active_base=level_document.stories[level_document.active_story].base_elevation
	show_below:=g.editor_mode==.Build&&(editor_state.view==.Stories_Below||editor_state.view==.Cutaway||editor_state.view==.Roof)
	// Surface kind 3 is the background shader layer. It sits just below the
	// authored floor and extends beyond the cutaway in every camera direction.
	vk_world_add(scene,ctx,&house_floor_mesh,12,8,240,0,house_background_tint(g),true,3,-.08)
	if level_document.active_story==0 {for i in 0..<generated_terrain_count {mesh:=&generated_terrain_meshes[i];cx,cz:=(mesh.min.x+mesh.max.x)*.5,(mesh.min.z+mesh.max.z)*.5;vk_world_add(scene,ctx,mesh,cx,cz,max(mesh.max.y-mesh.min.y,.001),0,{255,255,255,255},false,7,mesh.min.y)};for space in Plan_Space_Kind {for surface in Room_Surface {
		// The Moon Garden Patio is open to the sky but still owns a finished floor.
		// Other exterior grounds remain continuous lawn.
		if space==.Grounds&&surface!=.Garden do continue
		batch:=&house_floor_batches[space][surface];if !batch.ready do continue
		cx,cz:=(batch.min.x+batch.max.x)*.5,(batch.min.z+batch.max.z)*.5;tint:=space==.Grounds?[4]u8{214,218,211,255}:[4]u8{255,255,255,255};floor_base:=active_base+.012
		vk_world_add(scene,ctx,batch,cx,cz,1,0,tint,false,1,floor_base)
	}}}
	for &draw in personal_floor_draws do vk_world_add(scene,ctx,&draw.mesh,draw.x,draw.z,max(draw.mesh.max.y-draw.mesh.min.y,.001),draw.yaw,draw.tint,false,1,draw.base)
	// Enclosed rooms always keep a watertight ceiling in the directional shadow
	// pass. This is independent of whether the presentation camera cuts away the
	// visible ceiling or roof.
	for &draw in personal_ceiling_draws do vk_world_add(scene,ctx,&draw.mesh,draw.x,draw.z,max(draw.mesh.max.y-draw.mesh.min.y,.001),draw.yaw,{255,255,255,255},false,15,draw.base,shadow_only=true)
	if g.first_person_camera do for &draw in personal_ceiling_draws do vk_world_add(scene,ctx,&draw.mesh,draw.x,draw.z,max(draw.mesh.max.y-draw.mesh.min.y,.001),draw.yaw,{222,220,210,255},false,15,draw.base)
	if level_document.active_story==0 do for i in 0..<generated_foundation_count {mesh:=&generated_foundation_meshes[i];cx,cz:=(mesh.min.x+mesh.max.x)*.5,(mesh.min.z+mesh.max.z)*.5;vk_world_add(scene,ctx,mesh,cx,cz,max(mesh.max.y-mesh.min.y,.001),0,{255,255,255,255},false,0,mesh.min.y)}
	if level_document.active_story>0 {for i in 0..<generated_story_slab_count {if generated_story_slab_story[i]!=level_document.active_story do continue;mesh:=&generated_story_slab_meshes[i];if !mesh.ready do continue;cx,cz:=(mesh.min.x+mesh.max.x)*.5,(mesh.min.z+mesh.max.z)*.5;vk_world_add(scene,ctx,mesh,cx,cz,max(mesh.max.y-mesh.min.y,.001),0,{255,255,255,255},false,0,generated_story_slab_base_y[i])}}
	if show_below {for i in 0..<generated_story_slab_count {story:=generated_story_slab_story[i];if story>=level_document.active_story do continue;mesh:=&generated_story_slab_meshes[i];if !mesh.ready do continue;cx,cz:=(mesh.min.x+mesh.max.x)*.5,(mesh.min.z+mesh.max.z)*.5;vk_world_add(scene,ctx,mesh,cx,cz,max(mesh.max.y-mesh.min.y,.001),0,{174,184,188,210},false,0,generated_story_slab_base_y[i])};for i in 0..<generated_story_wall_count {story:=generated_story_wall_story[i];if story>=level_document.active_story do continue;mesh:=&generated_story_wall_meshes[i];if !mesh.ready do continue;cx,cz:=(mesh.min.x+mesh.max.x)*.5,(mesh.min.z+mesh.max.z)*.5;vk_world_add(scene,ctx,mesh,cx,cz,max(mesh.max.y-mesh.min.y,.001),0,{116,126,132,210},false,0,generated_story_wall_base_y[i])}}
	// Automatic mode lowers only the active room's camera-facing sections. This
	// preserves the far walls and neighboring rooms as visual context.
	scene.profile_house_surfaces_ms=time.duration_seconds(time.tick_diff(house_phase_started,time.tick_now()))*1000
	structure_phase_started:=time.tick_now()
	uniform_amount,uniform_walls:=house_wall_uniform_amount(g)
	finish_bands:=house_wall_finish_bands()
	// At a uniform height, draw the regularized wall union instead of separate
	// butt-ended section prisms. The union owns continuous exterior corners and
	// opening cuts, so L junctions cannot expose half-thickness corner notches.
	// Mixed-height cutaways still need the independently scalable sections below.
	if uniform_walls&&house_wall_solid.ready {
		authored_height:=house_authored_wall_height();uniform_height:=authored_height+(min(HOUSE_CUTAWAY_HEIGHT,authored_height)-authored_height)*uniform_amount
		cx,cz:=(house_wall_solid.min.x+house_wall_solid.max.x)*.5,(house_wall_solid.min.z+house_wall_solid.max.z)*.5
		// The union is authored in world X/Z coordinates. Always provide its X span
		// so changing wall height can only scale Y; the generic height-only draw
		// path scales all three axes and would create a miniature wall plan.
		vk_world_add_sized(scene,ctx,&house_wall_solid,cx,cz,house_render_wall_width(&house_wall_solid),uniform_height,0,{255,255,255,255},0,active_base)
	}
	for &wall,i in house_walls {
		mx,mz:=(wall.a.x+wall.b.x)*.5,(wall.a.y+wall.b.y)*.5;dx,dz:=wall.b.x-wall.a.x,wall.b.y-wall.a.y;length:=f32(math.sqrt(f64(dx*dx+dz*dz)));if length<.001 do continue
		yaw:=f32(math.atan2(f64(dz),f64(dx)));height:=house_wall_section_height(g,i);amount:=house_wall_section_amount(g,i)
		if !uniform_walls {core_band_drawn:=false;for band in 0..<len(wall.core_bands) {region_base:=finish_bands[band];if height<=region_base+.001 do continue;region_height:=min(finish_bands[band+1]-region_base,height-region_base);if region_height>.001&&wall.core_bands[band].ready {vk_world_add_sized(scene,ctx,&wall.core_bands[band],mx,mz,length,region_height,yaw,{255,255,255,255},0,active_base+region_base);core_band_drawn=true}};if !core_band_drawn do vk_world_add_sized(scene,ctx,&wall.core,mx,mz,length,height,yaw,{255,255,255,255},0,active_base)}
		section_tint:=house_wall_section_tint(amount)
		if !uniform_walls {vk_world_add_sized(scene,ctx,&house_wall_cap_edge_mesh,mx,mz,length+HOUSE_WALL_CAP_EDGE_OVERHANG,house_wall_cap_draw_height(&house_wall_cap_edge_mesh),yaw,house_wall_cap_edge_tint(amount),6,active_base+height+.004);vk_world_add_sized(scene,ctx,&wall.cap,mx,mz,length,house_wall_cap_draw_height(&wall.cap),yaw,section_tint,6,active_base+height+.008)}
		// Close mixed-height junctions with a vertical section reveal. Door leaves
		// remain independent, full-height objects and are never scaled by this path.
		if !uniform_walls {endpoints:=[2]Vec2{wall.a,wall.b};for endpoint in endpoints {reveal_height:=house_wall_junction_reveal_height(g,i,endpoint);if reveal_height>.001 do vk_world_add_sized(scene,ctx,&house_wall_junction_reveal_mesh,endpoint.x,endpoint.y,wall.width+.012,reveal_height,yaw+f32(math.PI)/2,house_wall_junction_tint(amount),6,active_base+height)}}
		// Interior coverings and exterior opening patches are emitted below from one
		// aperture-aware finish list.
	}
	if uniform_walls&&house_wall_cap_batch_full.ready {authored_height:=house_authored_wall_height();uniform_height:=authored_height+(min(HOUSE_CUTAWAY_HEIGHT,authored_height)-authored_height)*uniform_amount;if house_wall_cap_union_edge.ready {edge_x,edge_z:=(house_wall_cap_union_edge.min.x+house_wall_cap_union_edge.max.x)*.5,(house_wall_cap_union_edge.min.z+house_wall_cap_union_edge.max.z)*.5;vk_world_add(scene,ctx,&house_wall_cap_union_edge,edge_x,edge_z,.001,0,house_wall_cap_edge_tint(uniform_amount),false,6,active_base+uniform_height+.004)};cx,cz:=(house_wall_cap_batch_full.min.x+house_wall_cap_batch_full.max.x)*.5,(house_wall_cap_batch_full.min.z+house_wall_cap_batch_full.max.z)*.5;vk_world_add(scene,ctx,&house_wall_cap_batch_full,cx,cz,.001,0,house_wall_section_tint(uniform_amount),false,6,active_base+uniform_height+.008)}
	for &draw in wall_finish_draws {wall_height:=house_wall_section_height(g,draw.wall_index);region_height:=wall_height;region_base:=f32(0);if draw.region_height>0 {region_base=draw.region_base;if wall_height<=region_base+.001 do continue;region_height=min(draw.region_height,wall_height-region_base)};if region_height>.001 {anchor:=Vec2{draw.x,draw.z};group:u64;anchored:=draw.wall_index>=0&&draw.wall_index<len(house_walls);if anchored do anchor,group=house_wall_finish_light_group(draw.wall_index,anchor);tint:=draw.tint;if tint[3]==0 do tint={255,255,255,255};vk_world_add_sized(scene,ctx,&draw.mesh,draw.x,draw.z,house_render_wall_width(&draw.mesh),region_height,draw.yaw,tint,2,draw.base+region_base,light_anchor=anchor,use_light_anchor=anchored,light_group=group)}}
	show_roof:=house_roof_visible(g)
	if show_roof {for i in 0..<generated_roof_count {story:=generated_roof_story[i];if story!=level_document.active_story&&!(show_below&&story<level_document.active_story) do continue;roof:=&generated_roof_meshes[i];if !roof.ready do continue;alpha:=u8(clamp(int((1-g.cutaway_transition)*255),0,255));if alpha<255 do continue;cx,cz:=(roof.min.x+roof.max.x)*.5,(roof.min.z+roof.max.z)*.5;height:=max(roof.max.y-roof.min.y,.001);vk_world_add(scene,ctx,roof,cx,cz,height,0,{235,239,242,255},false,16,generated_roof_base_y[i]);if generated_roof_has_gutters[i] {gutter:=&generated_roof_gutter_meshes[i];gx,gz:=(gutter.min.x+gutter.max.x)*.5,(gutter.min.z+gutter.max.z)*.5;vk_world_add(scene,ctx,gutter,gx,gz,.14,0,{105,116,120,255},false,16,generated_roof_base_y[i]-.10)}}}
	if g.editor_mode==.Build {for i in 0..<generated_link_count {story:=generated_link_story[i];if story!=level_document.active_story&&!(show_below&&story<level_document.active_story) do continue;stairs:=&generated_link_meshes[i];if !stairs.ready do continue;cx,cz:=(stairs.min.x+stairs.max.x)*.5,(stairs.min.z+stairs.max.z)*.5;height:=max(stairs.max.y-stairs.min.y,.001);vk_world_add(scene,ctx,stairs,cx,cz,height,0,{151,104,66,255},false,0,generated_link_base_y[i])}}
	for i in 0..<generated_path_count {mesh:=&generated_path_meshes[i];cx,cz:=(mesh.min.x+mesh.max.x)*.5,(mesh.min.z+mesh.max.z)*.5;vk_world_add(scene,ctx,mesh,cx,cz,max(mesh.max.y-mesh.min.y,.001),0,{118,130,137,255},false,11,mesh.min.y)};if level_document.active_story==0 {for i in 0..<generated_water_count {mesh:=&generated_water_meshes[i];cx,cz:=(mesh.min.x+mesh.max.x)*.5,(mesh.min.z+mesh.max.z)*.5;vk_world_add(scene,ctx,mesh,cx,cz,max(mesh.max.y-mesh.min.y,.001),0,{255,255,255,255},false,17,mesh.min.y)}}
	scene.profile_house_structure_ms=time.duration_seconds(time.tick_diff(house_phase_started,time.tick_now()))*1000
	scene.profile_house_walls_ms=time.duration_seconds(time.tick_diff(structure_phase_started,time.tick_now()))*1000
	house_phase_started=time.tick_now()
	for opening in house_plan.openings {
		dx,dz:=opening.b.x-opening.a.x,opening.b.y-opening.a.y;length:=f32(math.sqrt(f64(dx*dx+dz*dz)));if length<.001 do continue
		wall_yaw:=f32(math.atan2(f64(dz),f64(dx)));wall_height:=house_opening_wall_height(g,opening)
		if opening.kind==.Window {
			mx,mz:=(opening.a.x+opening.b.x)*.5,(opening.a.y+opening.b.y)*.5
			opening_sill_mesh:=house_opening_sill_mesh(opening);opening_header_mesh:=house_opening_header_mesh(opening)
			nx,nz:= -dz/length,dx/length;face_offset:=house_wall_width(opening.wall_width)*.5+.026
			// Cutaway changes only the masonry aperture. A window is an authored object,
			// like a door leaf, so it keeps its complete proportions and may remain
			// suspended after the host wall descends below it.
			wall_aperture_top:=house_opening_aperture_top(g,opening)
			sill_height:=opening.sill_height>0?opening.sill_height:f32(.72);glass_height:=max(opening.height,f32(0));rail:=f32(HOUSE_WINDOW_FRAME_RAIL_HEIGHT)
			aperture_top:=sill_height+glass_height+rail+.10
			glass_width:=max(length-rail*2,.01);vertical_height:=max(min(glass_height+rail*2,aperture_top-(sill_height-.04)),f32(0));side_offset:=max(length*.5-rail*.5,f32(0));light_columns,light_rows:=house_window_style_grid(opening.window_style,length,glass_height)
			// Restore opaque masonry only below and above the unioned aperture.
			masonry_width:=length+HOUSE_OPENING_CUT_END_EXTENSION*2
			lower_masonry_height:=house_window_lower_masonry_height(sill_height,wall_height);if lower_masonry_height>.001 do vk_world_add_sized(scene,ctx,opening_sill_mesh,mx,mz,masonry_width,lower_masonry_height,wall_yaw,{255,255,255,255},0,active_base,no_shadow=true)
			header_base:=active_base+sill_height+glass_height;header_height:=max(wall_aperture_top-(sill_height+glass_height),f32(0));if header_height>0 {
				vk_world_add_sized(scene,ctx,opening_header_mesh,mx,mz,masonry_width,header_height,wall_yaw,{255,255,255,255},0,header_base,no_shadow=true)
				// Window apertures split the host wall and its cap at both jambs. Close
				// the restored masonry header with the same two-layer section cap.
				host:=house_opening_host_wall_index(opening);amount:=house_wall_section_amount(g,host);cap_y:=active_base+wall_aperture_top;cap_mesh:=&house_window_header_cap_mesh;if host>=0&&host<len(house_walls) do cap_mesh=&house_walls[host].cap
				// Reuse the host section's cap mesh so authored thin walls retain their
				// actual depth; a house-wide default-depth cap visibly overhung them.
				vk_world_add_sized(scene,ctx,cap_mesh,mx,mz,length+HOUSE_WALL_CAP_EDGE_OVERHANG,house_wall_cap_draw_height(cap_mesh),wall_yaw,house_wall_cap_edge_tint(amount),6,cap_y+.004)
				vk_world_add_sized(scene,ctx,cap_mesh,mx,mz,length,house_wall_cap_draw_height(cap_mesh),wall_yaw,house_wall_section_tint(amount),6,cap_y+.008)
			}
			// The square-capped plan cut also extends beyond both authored jambs.
			// Restore those vertical masonry shoulders through the glazing band; the
			// sill/header above already own the same overlap at their elevations.
			jamb_masonry_base:=active_base+sill_height-.04;jamb_masonry_height:=max(min(glass_height+.08,wall_aperture_top-(sill_height-.04)),f32(.08));jamb_half:=HOUSE_OPENING_CUT_END_EXTENSION*.5;tx,tz:=dx/length,dz/length
			vk_world_add_sized(scene,ctx,opening_header_mesh,opening.a.x-tx*jamb_half,opening.a.y-tz*jamb_half,HOUSE_OPENING_CUT_END_EXTENSION,jamb_masonry_height,wall_yaw,{255,255,255,255},0,jamb_masonry_base,no_shadow=true)
			vk_world_add_sized(scene,ctx,opening_header_mesh,opening.b.x+tx*jamb_half,opening.b.y+tz*jamb_half,HOUSE_OPENING_CUT_END_EXTENSION,jamb_masonry_height,wall_yaw,{255,255,255,255},0,jamb_masonry_base,no_shadow=true)
			// The host wall is already split at the window jambs, so its section caps
			// stop on either side of the opening. Do not bridge those caps across the
			// aperture when the cutaway drops below the glazing: that would intersect
			// the sash and read as a solid wall slab passing through the window.
			// Full-depth returns bridge the two face-mounted frames and give the
			// opening a readable sill, jamb, and head instead of an exposed wall cut.
			if glass_height>.12 {trim_tint:=[4]u8{196,198,190,255};sill_cap_base:=active_base+sill_height-.055;vk_world_add_sized(scene,ctx,&house_window_sill_cap_mesh,mx,mz,length+.20,.07,wall_yaw,trim_tint,14,sill_cap_base);head_trim_base:=active_base+min(sill_height+glass_height-.025,aperture_top-.08);vk_world_add_sized(scene,ctx,&house_window_head_return_mesh,mx,mz,length+.16,.08,wall_yaw,trim_tint,14,head_trim_base);jamb_base:=active_base+sill_height-.04;jamb_height:=max(min(glass_height+.08,aperture_top-(sill_height-.04)),f32(.08));vk_world_add_sized(scene,ctx,&house_window_jamb_return_mesh,opening.a.x,opening.a.y,.08,jamb_height,wall_yaw,trim_tint,14,jamb_base);vk_world_add_sized(scene,ctx,&house_window_jamb_return_mesh,opening.b.x,opening.b.y,.08,jamb_height,wall_yaw,trim_tint,14,jamb_base)}
			if opening.id=="window_study_courtyard"&&wall_height<wall_aperture_top-.001 {
				return_height:=wall_aperture_top-wall_height;return_width:=f32(.12);return_base:=active_base+wall_height
				vk_world_add_sized(scene,ctx,opening_header_mesh,opening.a.x,opening.a.y,return_width,return_height,wall_yaw,{255,255,255,255},0,return_base)
				vk_world_add_sized(scene,ctx,opening_header_mesh,opening.b.x,opening.b.y,return_width,return_height,wall_yaw,{255,255,255,255},0,return_base)
			}
			// One sash and glazing unit sits within the opening depth. Interior and
			// exterior finish casing remain separate, but the rear sash is no longer
			// visible through a duplicate pane.
			nominal_top:=sill_height+.01+glass_height;top_base:=min(nominal_top,aperture_top-rail);clipped_head:=top_base<nominal_top-.001;top_tint:=clipped_head?[4]u8{168,174,170,255}:[4]u8{49,57,59,255};top_kind:=clipped_head?6:14
			room_sign:=house_window_room_sign(opening.a,opening.b);if opening.window_flipped do room_sign=-room_sign
			sash_plane_offset:=house_window_operable_sash_offset(opening.window_style);sash_x,sash_z:=mx+nx*sash_plane_offset*room_sign,mz+nz*sash_plane_offset*room_sign
			// Glazing is submitted after the opaque window assembly below. The world
			// pipeline still writes depth for blended materials, so drawing glass here
			// would hide an exterior shutter when the window is viewed from indoors.
			if opening.window_style==.Double_Hung&&glass_height>.20 {
				sash_offset:=house_window_double_hung_sash_offset();lower_x,lower_z:=mx+nx*sash_offset*room_sign,mz+nz*sash_offset*room_sign;upper_x,upper_z:=mx-nx*sash_offset*room_sign,mz-nz*sash_offset*room_sign
				vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,lower_x,lower_z,length,rail,wall_yaw,{49,57,59,255},14,active_base+sill_height-.03)
				if top_base>=sill_height-.03 do vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,upper_x,upper_z,length,rail,wall_yaw,top_tint,top_kind,active_base+top_base)
			} else {
				vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,sash_x,sash_z,length,rail,wall_yaw,{49,57,59,255},14,active_base+sill_height-.03)
				if top_base>=sill_height-.03 do vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,sash_x,sash_z,length,rail,wall_yaw,top_tint,top_kind,active_base+top_base)
			}
			horizontal_member:=house_window_internal_horizontal_width(opening.window_style,rail);if opening.window_style==.Double_Hung&&glass_height>.20 {meeting_y:=sill_height+glass_height*.5;meeting_offset:=house_window_double_hung_sash_offset();lower_x,lower_z:=mx+nx*meeting_offset*room_sign,mz+nz*meeting_offset*room_sign;upper_x,upper_z:=mx-nx*meeting_offset*room_sign,mz-nz*meeting_offset*room_sign;vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,lower_x,lower_z,length,rail,wall_yaw,{49,57,59,255},14,active_base+meeting_y-rail*.42);vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,upper_x,upper_z,length,rail,wall_yaw,{55,63,65,255},14,active_base+meeting_y-rail*.58)} else {for row in 1..<light_rows {middle_base:=sill_height-horizontal_member*.5+glass_height*f32(row)/f32(light_rows);if middle_base+horizontal_member<=aperture_top do vk_world_add_sized(scene,ctx,&house_window_muntin_h_mesh,sash_x,sash_z,length,horizontal_member,wall_yaw,{55,63,65,255},14,active_base+middle_base)}}
			if vertical_height>0 {
				internal_vertical:=house_window_internal_vertical_width(opening.window_style,rail)
				if opening.window_style==.Double_Hung&&glass_height>.20 {
					// The outer jamb remains continuous while each movable sash gets its
					// own half-height stiles and muntins in the sash's actual depth plane.
					jamb_signs:=[2]f32{-1,1};for sign in jamb_signs do vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,mx+dx/length*side_offset*sign,mz+dz/length*side_offset*sign,rail,vertical_height,wall_yaw,{49,57,59,255},14,active_base+sill_height-.04)
					half_glass:=glass_height*.5;sash_offset:=house_window_double_hung_sash_offset();sash_side:=house_window_double_hung_stile_along(glass_width,rail);lower_x,lower_z:=mx+nx*sash_offset*room_sign,mz+nz*sash_offset*room_sign;upper_x,upper_z:=mx-nx*sash_offset*room_sign,mz-nz*sash_offset*room_sign
					for column in 0..=light_columns {along:=-sash_side+sash_side*2*f32(column)/f32(light_columns);edge:=column==0||column==light_columns;tint:=edge?[4]u8{49,57,59,255}:[4]u8{55,63,65,255};member_width:=edge?rail:internal_vertical;member_mesh:=edge?&house_window_frame_v_mesh:&house_window_muntin_v_mesh;vk_world_add_sized(scene,ctx,member_mesh,lower_x+dx/length*along,lower_z+dz/length*along,member_width,half_glass,wall_yaw,tint,14,active_base+sill_height);vk_world_add_sized(scene,ctx,member_mesh,upper_x+dx/length*along,upper_z+dz/length*along,member_width,half_glass,wall_yaw,tint,14,active_base+sill_height+half_glass)}
				} else {for column in 0..=light_columns {along:=-side_offset+side_offset*2*f32(column)/f32(light_columns);edge:=column==0||column==light_columns;tint:=edge?[4]u8{49,57,59,255}:[4]u8{55,63,65,255};member_width:=edge?rail:internal_vertical;member_mesh:=edge?&house_window_frame_v_mesh:&house_window_muntin_v_mesh;vk_world_add_sized(scene,ctx,member_mesh,sash_x+dx/length*along,sash_z+dz/length*along,member_width,vertical_height,wall_yaw,tint,14,active_base+sill_height-.04)}}
			}
			if (opening.window_style==.Casement||opening.window_style==.Awning)&&glass_height>.12 {outer_width:=house_window_operable_frame_width(rail);outer_side:=max(length*.5-outer_width*.5,f32(0));outer_tint:=[4]u8{66,73,74,255};vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,mx-dx/length*outer_side,mz-dz/length*outer_side,outer_width,vertical_height,wall_yaw,outer_tint,14,active_base+sill_height-.04);vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,mx+dx/length*outer_side,mz+dz/length*outer_side,outer_width,vertical_height,wall_yaw,outer_tint,14,active_base+sill_height-.04);vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,mx,mz,length,outer_width,wall_yaw,outer_tint,14,active_base+sill_height-.03);if top_base>=sill_height-.03 do vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,mx,mz,length,outer_width,wall_yaw,outer_tint,14,active_base+top_base+rail-outer_width);mullion_count:=house_window_operable_mullion_count(opening.window_style,light_columns);if mullion_count>0 {for mullion in 1..=mullion_count {along:=-side_offset+side_offset*2*f32(mullion)/f32(mullion_count+1);vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,mx+dx/length*along,mz+dz/length*along,outer_width,vertical_height,wall_yaw,outer_tint,14,active_base+sill_height-.04)}}}
			if opening.window_style==.Double_Hung&&glass_height>.20 {parting_width:=house_window_double_hung_parting_bead_width(rail);parting_along:=house_window_double_hung_parting_bead_along(glass_width,rail);parting_tint:=[4]u8{62,69,70,255};vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,mx-dx/length*parting_along,mz-dz/length*parting_along,parting_width,glass_height,wall_yaw,parting_tint,14,active_base+sill_height);vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,mx+dx/length*parting_along,mz+dz/length*parting_along,parting_width,glass_height,wall_yaw,parting_tint,14,active_base+sill_height)}
			// A narrow room-side glazing stop overlaps the pane perimeter. The small
			// proud offset gives the glass a seated edge and a readable shadow line.
			if glass_height>.04&&glass_width>.04 {
				bead:=house_window_glazing_bead_width(rail);frame_bead_offset:=house_window_frame_v_mesh.max.z+.004;bead_yaw:=room_sign>0?wall_yaw:wall_yaw+f32(math.PI);bead_tint:=[4]u8{72,80,81,255};bead_along:=max(glass_width*.5-bead*.5,f32(0))
				if opening.window_style==.Double_Hung&&glass_height>.20 {
					half_glass:=glass_height*.5;lower_x,lower_z:=mx+nx*frame_bead_offset*room_sign,mz+nz*frame_bead_offset*room_sign;upper_offset:=house_window_double_hung_upper_bead_offset(frame_bead_offset);upper_x,upper_z:=mx+nx*upper_offset*room_sign,mz+nz*upper_offset*room_sign
					vk_world_add_sized(scene,ctx,&house_window_bead_h_mesh,lower_x,lower_z,glass_width,bead,bead_yaw,bead_tint,14,active_base+sill_height);vk_world_add_sized(scene,ctx,&house_window_bead_h_mesh,lower_x,lower_z,glass_width,bead,bead_yaw,bead_tint,14,active_base+sill_height+half_glass-bead);vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,lower_x-dx/length*bead_along,lower_z-dz/length*bead_along,bead,half_glass,bead_yaw,bead_tint,14,active_base+sill_height);vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,lower_x+dx/length*bead_along,lower_z+dz/length*bead_along,bead,half_glass,bead_yaw,bead_tint,14,active_base+sill_height)
					vk_world_add_sized(scene,ctx,&house_window_bead_h_mesh,upper_x,upper_z,glass_width,bead,bead_yaw,bead_tint,14,active_base+sill_height+half_glass);vk_world_add_sized(scene,ctx,&house_window_bead_h_mesh,upper_x,upper_z,glass_width,bead,bead_yaw,bead_tint,14,active_base+sill_height+glass_height-bead);vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,upper_x-dx/length*bead_along,upper_z-dz/length*bead_along,bead,half_glass,bead_yaw,bead_tint,14,active_base+sill_height+half_glass);vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,upper_x+dx/length*bead_along,upper_z+dz/length*bead_along,bead,half_glass,bead_yaw,bead_tint,14,active_base+sill_height+half_glass)
				} else {bead_x,bead_z:=mx+nx*(frame_bead_offset+sash_plane_offset)*room_sign,mz+nz*(frame_bead_offset+sash_plane_offset)*room_sign;vk_world_add_sized(scene,ctx,&house_window_bead_h_mesh,bead_x,bead_z,glass_width,bead,bead_yaw,bead_tint,14,active_base+sill_height);vk_world_add_sized(scene,ctx,&house_window_bead_h_mesh,bead_x,bead_z,glass_width,bead,bead_yaw,bead_tint,14,active_base+sill_height+glass_height-bead);vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,bead_x-dx/length*bead_along,bead_z-dz/length*bead_along,bead,glass_height,bead_yaw,bead_tint,14,active_base+sill_height);vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,bead_x+dx/length*bead_along,bead_z+dz/length*bead_along,bead,glass_height,bead_yaw,bead_tint,14,active_base+sill_height)}
			}
			// The room face receives a flat stool and apron; the weather face receives
			// a projecting, sloped sill and a separate underside drip edge.
			apron_height:=min(f32(.16),max(sill_height-.08,f32(0)));drip_height:=f32(.045);drip_base:=top_base+rail;inside_yaw:=room_sign>0?wall_yaw:wall_yaw+f32(math.PI);inside_x,inside_z:=mx+nx*face_offset*room_sign,mz+nz*face_offset*room_sign
			if apron_height>.01 do vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,inside_x,inside_z,max(length-.10,f32(.08)),apron_height,inside_yaw,{181,184,178,255},14,active_base+sill_height-.07-apron_height)
			stool_offset:=face_offset+.075;stool_x,stool_z:=mx+nx*stool_offset*room_sign,mz+nz*stool_offset*room_sign;vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,stool_x,stool_z,length+.24,.038,inside_yaw,{202,203,197,255},14,active_base+sill_height-.038)
			exterior_sign:=-room_sign;exterior_yaw:=exterior_sign>0?wall_yaw:wall_yaw+f32(math.PI);exterior_sill_offset:=face_offset+.07;exterior_x,exterior_z:=mx+nx*exterior_sill_offset*exterior_sign,mz+nz*exterior_sill_offset*exterior_sign;vk_world_add_sized(scene,ctx,&house_window_exterior_sill_mesh,exterior_x,exterior_z,length+.24,.07,exterior_yaw,{188,192,188,255},14,active_base+sill_height-.055);drip_x,drip_z:=mx+nx*(face_offset+.145)*exterior_sign,mz+nz*(face_offset+.145)*exterior_sign;vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,drip_x,drip_z,length+.20,.018,exterior_yaw,{162,168,166,255},14,active_base+sill_height-.071)
			// A compact head casing remains readable from both faces.
			// Face-applied jamb casing overlaps the finish cut on both sides. Interior
			// trim is broader; the weather face uses a tighter brick-mould profile.
			casing_base:=sill_height-.07;casing_top:=min(aperture_top,top_base+rail+drip_height);casing_height:=max(casing_top-casing_base,f32(0));face_signs:=[2]f32{1,-1};for sign in face_signs {interior:=sign==room_sign;casing_width:=house_window_casing_width(interior);casing_offset:=face_offset+.012;ox,oz:=nx*casing_offset*sign,nz*casing_offset*sign;yaw:=sign>0?wall_yaw:wall_yaw+f32(math.PI);casing_tint:=interior?[4]u8{198,200,194,255}:[4]u8{176,181,178,255};if casing_height>.01 {left_x,left_z:=opening.a.x+ox-dx/length*casing_width*.5,opening.a.y+oz-dz/length*casing_width*.5;right_x,right_z:=opening.b.x+ox+dx/length*casing_width*.5,opening.b.y+oz+dz/length*casing_width*.5;vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,left_x,left_z,casing_width,casing_height,yaw,casing_tint,14,active_base+casing_base);vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,right_x,right_z,casing_width,casing_height,yaw,casing_tint,14,active_base+casing_base)};if !clipped_head&&drip_base+drip_height<=aperture_top+.001 do vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,mx+ox,mz+oz,length+casing_width*2,drip_height,yaw,casing_tint,14,active_base+drip_base)}
			if casing_height>.01 {sealant_width:=house_window_perimeter_sealant_width();exterior_casing:=house_window_casing_width(false);sealant_offset:=face_offset+.004;sealant_x,sealant_z:=mx+nx*sealant_offset*exterior_sign,mz+nz*sealant_offset*exterior_sign;sealant_along:=length*.5+exterior_casing+sealant_width*.5;sealant_tint:=[4]u8{104,110,108,255};vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,sealant_x-dx/length*sealant_along,sealant_z-dz/length*sealant_along,sealant_width,casing_height,exterior_yaw,sealant_tint,14,active_base+casing_base);vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,sealant_x+dx/length*sealant_along,sealant_z+dz/length*sealant_along,sealant_width,casing_height,exterior_yaw,sealant_tint,14,active_base+casing_base);sealant_head_width:=length+(exterior_casing+sealant_width)*2;vk_world_add_sized(scene,ctx,&house_window_bead_h_mesh,sealant_x,sealant_z,sealant_head_width,sealant_width,exterior_yaw,sealant_tint,14,active_base+casing_top-sealant_width)}
			if casing_height>.01 {caulk_width:=house_window_interior_caulk_width();interior_casing:=house_window_casing_width(true);caulk_offset:=face_offset+.004;caulk_x,caulk_z:=mx+nx*caulk_offset*room_sign,mz+nz*caulk_offset*room_sign;caulk_along:=length*.5+interior_casing+caulk_width*.5;caulk_tint:=[4]u8{181,184,178,255};vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,caulk_x-dx/length*caulk_along,caulk_z-dz/length*caulk_along,caulk_width,casing_height,inside_yaw,caulk_tint,14,active_base+casing_base);vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,caulk_x+dx/length*caulk_along,caulk_z+dz/length*caulk_along,caulk_width,casing_height,inside_yaw,caulk_tint,14,active_base+casing_base);caulk_head_width:=length+(interior_casing+caulk_width)*2;vk_world_add_sized(scene,ctx,&house_window_bead_h_mesh,caulk_x,caulk_z,caulk_head_width,caulk_width,inside_yaw,caulk_tint,14,active_base+casing_top-caulk_width)}
			if !clipped_head&&drip_base+drip_height<=aperture_top+.001 {
				flashing_offset:=face_offset+.06;flashing_x,flashing_z:=mx+nx*flashing_offset*exterior_sign,mz+nz*flashing_offset*exterior_sign;flashing_width:=length+house_window_head_flashing_overhang()*2;flashing_base:=active_base+drip_base+drip_height-.004
				vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,flashing_x,flashing_z,flashing_width,.022,exterior_yaw,{154,162,162,255},14,flashing_base);flashing_lip_x,flashing_lip_z:=mx+nx*(flashing_offset+.028)*exterior_sign,mz+nz*(flashing_offset+.028)*exterior_sign;vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,flashing_lip_x,flashing_lip_z,flashing_width,.026,exterior_yaw,{142,150,150,255},14,active_base+drip_base+.012)
				dam_width:=house_window_head_flashing_end_dam_width();dam_height:=house_window_head_flashing_end_dam_height();dam_along:=flashing_width*.5-dam_width*.5;dam_tint:=[4]u8{148,156,156,255};vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,flashing_x-dx/length*dam_along,flashing_z-dz/length*dam_along,dam_width,dam_height,exterior_yaw,dam_tint,14,flashing_base);vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,flashing_x+dx/length*dam_along,flashing_z+dz/length*dam_along,dam_width,dam_height,exterior_yaw,dam_tint,14,flashing_base)
			}
			// Operable hardware is mounted only on the room-facing side.
			hardware_offset:=house_window_hardware_offset();hardware_x,hardware_z:=mx+nx*hardware_offset*room_sign,mz+nz*hardware_offset*room_sign;hardware_yaw:=room_sign>0?wall_yaw:wall_yaw+f32(math.PI);hardware_tint:=[4]u8{151,121,66,255};switch opening.window_style {
			case .Casement:if glass_height>.30 {handle_count,hinge_side_count:=house_window_casement_hardware_count(light_columns);for handle_index in 0..<handle_count {handle_along:=house_window_casement_handle_along(light_columns,handle_index,side_offset,rail,opening.window_hinge_right);vk_world_add_sized(scene,ctx,&house_window_hardware_v_mesh,hardware_x+dx/length*handle_along,hardware_z+dz/length*handle_along,.025,.16,hardware_yaw,hardware_tint,14,active_base+sill_height+glass_height*.46)};for hinge_index in 0..<hinge_side_count {hinge_along:=house_window_casement_hinge_along(light_columns,hinge_index,side_offset,rail,opening.window_hinge_right);hinge_x,hinge_z:=hardware_x+dx/length*hinge_along,hardware_z+dz/length*hinge_along;vk_world_add_sized(scene,ctx,&house_window_hardware_v_mesh,hinge_x,hinge_z,.028,.07,hardware_yaw,hardware_tint,14,active_base+sill_height+glass_height*.24);vk_world_add_sized(scene,ctx,&house_window_hardware_v_mesh,hinge_x,hinge_z,.028,.07,hardware_yaw,hardware_tint,14,active_base+sill_height+glass_height*.72)}}
			case .Awning:if glass_height>.30 {vk_world_add_sized(scene,ctx,&house_window_hardware_h_mesh,hardware_x,hardware_z,.20,.025,hardware_yaw,hardware_tint,14,active_base+sill_height+.10);pivot_offset:=min(length*.24,f32(.42));pivot_base:=active_base+sill_height+glass_height-.055;vk_world_add_sized(scene,ctx,&house_window_hardware_h_mesh,hardware_x-dx/length*pivot_offset,hardware_z-dz/length*pivot_offset,.08,.024,hardware_yaw,hardware_tint,14,pivot_base);vk_world_add_sized(scene,ctx,&house_window_hardware_h_mesh,hardware_x+dx/length*pivot_offset,hardware_z+dz/length*pivot_offset,.08,.024,hardware_yaw,hardware_tint,14,pivot_base)}
			case .Double_Hung:if glass_height>.45 {lift_offset:=min(length*.18,f32(.28));vk_world_add_sized(scene,ctx,&house_window_hardware_h_mesh,hardware_x-dx/length*lift_offset,hardware_z-dz/length*lift_offset,.12,.022,hardware_yaw,hardware_tint,14,active_base+sill_height+.10);vk_world_add_sized(scene,ctx,&house_window_hardware_h_mesh,hardware_x+dx/length*lift_offset,hardware_z+dz/length*lift_offset,.12,.022,hardware_yaw,hardware_tint,14,active_base+sill_height+.10);vk_world_add_sized(scene,ctx,&house_window_hardware_h_mesh,hardware_x,hardware_z,.14,.026,hardware_yaw,hardware_tint,14,active_base+sill_height+glass_height*.5-.013)}
			case .Fixed,.Picture:
			}
			if opening.id=="window_study_courtyard" {
				outside_sign:=f32(-1);ox,oz:=nx*(face_offset+.07)*outside_sign,nz*(face_offset+.07)*outside_sign
				shutter_x,shutter_z:=mx+ox,mz+oz;shutter_yaw:=outside_sign>0?wall_yaw:wall_yaw+f32(math.PI)
				// Dedicated rails and a shallow top cassette turn the louvers into a
				// coherent exterior mechanism instead of a stack of floating boards.
				rail_tint:=[4]u8{42,48,46,255};rail_width:=f32(.07);rail_height:=min(aperture_top-sill_height,f32(1.42));rail_along:=length*.5+rail_width*.36
				vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,shutter_x-dx/length*rail_along,shutter_z-dz/length*rail_along,rail_width,rail_height,shutter_yaw,rail_tint,15,active_base+sill_height)
				vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,shutter_x+dx/length*rail_along,shutter_z+dz/length*rail_along,rail_width,rail_height,shutter_yaw,rail_tint,15,active_base+sill_height)
				vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,shutter_x,shutter_z,length+rail_width*2,.16,shutter_yaw,{47,54,51,255},15,active_base+aperture_top-.08)
				vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,shutter_x,shutter_z,length+rail_width*1.2,.045,shutter_yaw,{67,73,69,255},15,active_base+sill_height-.022)
				// Paired locking dogs slide into the bottom catch at full closure and
				// retract toward their guide rails as the louvers open.
				lock_phase:=clamp((.12-g.shutter_position)/.12,0,1);engagement:=lock_phase*lock_phase*(3-2*lock_phase);latch_travel:=(1-engagement)*.065;latch_tint:=[4]u8{u8(70+120*engagement),u8(75+75*engagement),u8(68+10*engagement),255};latch_offsets:=[2]f32{-length*.5+.11-latch_travel,length*.5-.11+latch_travel};for latch_along in latch_offsets {latch_x,latch_z:=shutter_x+dx/length*latch_along,shutter_z+dz/length*latch_along;vk_world_add(scene,ctx,&shutter_crank_link_mesh,latch_x,latch_z,.065,wall_yaw,latch_tint,false,15,active_base+sill_height+.012)}
				// Interlocked rolling-shutter slats remain in one curtain as they rise;
				// they flex slightly under load but do not rotate open like Venetian
				// blinds. The flex returns to zero at both travel limits.
				travel_position:=clamp(g.shutter_position,0,1);slat_pitch:=f32(math.sin(f64(travel_position*f32(math.PI))))*.10
				slat_travel:=travel_position*rail_height
				// The weighted terminal bar is the leading edge of a real rolling
				// shutter. It makes partial travel unambiguous and keeps both sides
				// synchronized in their guide rails.
				terminal_y:=active_base+sill_height+slat_travel;if terminal_y+.06<active_base+aperture_top-.02 {
					terminal_x,terminal_z:=shutter_x+nx*.014*outside_sign,shutter_z+nz*.014*outside_sign;terminal_tint:=[4]u8{116,105,76,255};vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,terminal_x,terminal_z,length-.015,.066,shutter_yaw,terminal_tint,15,terminal_y)
					shoe_offsets:=[2]f32{-length*.5+.035,length*.5-.035};for shoe_along in shoe_offsets {shoe_x,shoe_z:=shutter_x+dx/length*shoe_along,shutter_z+dz/length*shoe_along;vk_world_add(scene,ctx,&shutter_crank_link_mesh,shoe_x,shoe_z,.068,wall_yaw,{116,91,48,255},false,15,terminal_y-.005)}
				}
				for slat in 0..<11 {
					slat_y:=active_base+sill_height+.005+f32(slat)*.127+slat_travel
					if slat_y+.124<=active_base+aperture_top+.001 {
						slat_tint:=slat%2==0?[4]u8{54,61,57,255}:[4]u8{59,66,62,255};vk_world_add(scene,ctx,&house_shutter_slat_mesh,shutter_x,shutter_z,.124,wall_yaw,slat_tint,false,15,slat_y,slat_pitch)
						// A recessed lower-edge seam keeps each interlocking steel slat
						// legible when the shutter is face-on and fully closed.
						if g.shutter_position<.92 do vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,shutter_x,shutter_z,length-.035,.009,shutter_yaw,{31,37,35,255},15,slat_y+.116)
					}
				}
			}
			// Composite the transparent pane over the complete opaque assembly. Depth
			// testing keeps nearer slats in front from outside, while the pane blends
			// over the same solid slats instead of erasing them from the room side.
			if glass_height>0 {if opening.window_style==.Double_Hung&&glass_height>.20 {sash_offset:=house_window_double_hung_sash_offset();half_glass:=glass_height*.5;lower_x,lower_z:=mx+nx*sash_offset*room_sign,mz+nz*sash_offset*room_sign;upper_x,upper_z:=mx-nx*sash_offset*room_sign,mz-nz*sash_offset*room_sign;vk_world_add_sized(scene,ctx,&house_window_mesh,lower_x,lower_z,glass_width,half_glass,wall_yaw,{94,145,174,122},12,active_base+sill_height);vk_world_add_sized(scene,ctx,&house_window_mesh,upper_x,upper_z,glass_width,half_glass,wall_yaw,{94,145,174,122},12,active_base+sill_height+half_glass)} else do vk_world_add_sized(scene,ctx,&house_window_mesh,sash_x,sash_z,glass_width,glass_height,wall_yaw,{94,145,174,122},12,active_base+sill_height)}
		} else {
			door_openness:=runtime_door_opening(g,opening)
			// The plan union removes openings through the full wall height. Put back
			// the lintel masonry above the authored door, clipped by cutaway height.
			header_x,header_z:=(opening.a.x+opening.b.x)*.5,(opening.a.y+opening.b.y)*.5
			leaf_height:=house_door_render_height(opening);header_height:=max(wall_height-leaf_height,f32(0))
			if header_height>.001 {vk_world_add_sized(scene,ctx,house_opening_header_mesh(opening),header_x,header_z,length+.18,header_height,wall_yaw,{255,255,255,255},0,active_base+leaf_height);vk_world_add_sized(scene,ctx,house_opening_cap_edge_mesh(opening),header_x,header_z,length+.18,.001,wall_yaw,house_wall_section_tint(house_wall_section_amount(g,house_opening_host_wall_index(opening))),6,active_base+wall_height+.012)}
			// The leaf remains complete and readable during cutaway, while its
			// wall-mounted casing is clipped continuously by the host wall plane.
			frame_rail:=HOUSE_DOOR_CASING_RAIL;jamb_height:=house_door_casing_jamb_height(opening,wall_height);head_base:=house_door_casing_head_base(opening);head_height:=house_door_casing_head_height(opening,wall_height);nx,nz:= -dz/length,dx/length;face_offset:=house_wall_width(opening.wall_width)*.5+.028;along:=max(length*.5-frame_rail*.5,f32(0));frame_tint:=[4]u8{91,68,50,255}
			frame_signs:=[2]f32{1,-1};for sign in frame_signs {
				ox,oz:=nx*face_offset*sign,nz*face_offset*sign;yaw:=sign>0?wall_yaw:wall_yaw+f32(math.PI)
				if jamb_height>.001 {vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,header_x+ox-dx/length*along,header_z+oz-dz/length*along,frame_rail,jamb_height,yaw,frame_tint,14,active_base);vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,header_x+ox+dx/length*along,header_z+oz+dz/length*along,frame_rail,jamb_height,yaw,frame_tint,14,active_base)}
				if head_height>.001 do vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,header_x+ox,header_z+oz,length+frame_rail,head_height,yaw,frame_tint,14,active_base+head_base)
			}
			// Leaves are authored objects. Cutaway never changes either axis; style
			// controls only how the complete aperture width is divided and posed.
			leaf_widths:[2]f32;leaf_x,leaf_z:[2]f32;leaf_yaws:[2]f32;handle_xs,handle_zs:[2]f32;leaf_count:=1
			switch opening.door_style {
			case .Double:
				leaf_count=2;half:=house_door_render_width(length)*.5;left_yaw:=wall_yaw+f32(math.PI)*.42*door_openness;right_yaw:=wall_yaw+f32(math.PI)-f32(math.PI)*.42*door_openness
				leaf_widths={half,half};leaf_yaws={left_yaw,right_yaw};leaf_x={opening.a.x+f32(math.cos(f64(left_yaw)))*half*.5,opening.b.x+f32(math.cos(f64(right_yaw)))*half*.5};leaf_z={opening.a.y+f32(math.sin(f64(left_yaw)))*half*.5,opening.b.y+f32(math.sin(f64(right_yaw)))*half*.5}
				for i in 0..<2 {handle_xs[i]=leaf_x[i]+f32(math.cos(f64(leaf_yaws[i])))*half*(HOUSE_DOOR_HANDLE_ALONG-.5);handle_zs[i]=leaf_z[i]+f32(math.sin(f64(leaf_yaws[i])))*half*(HOUSE_DOOR_HANDLE_ALONG-.5)}
			case .Sliding:
				leaf_count=2;half:=house_door_render_width(length)*.5;ux,uz:=dx/length,dz/length;track_offset:=f32(.038)
				// Stack the moving panel over the fixed panel. The other half of the
				// aperture stays visibly open and matches the authored navigation gap.
				closed_x,closed_z:=opening.b.x-ux*half*.5,opening.b.y-uz*half*.5;stack_x,stack_z:=opening.a.x+ux*half*.5,opening.a.y+uz*half*.5;moving_x,moving_z:=closed_x+(stack_x-closed_x)*door_openness,closed_z+(stack_z-closed_z)*door_openness;leaf_widths={half,half};leaf_yaws={wall_yaw,wall_yaw};leaf_x={moving_x+nx*track_offset,stack_x-nx*track_offset};leaf_z={moving_z+nz*track_offset,stack_z-nz*track_offset}
				handle_xs={leaf_x[0]+ux*(half*.5-.10),leaf_x[1]+ux*(half*.5-.16)};handle_zs={leaf_z[0]+uz*(half*.5-.10),leaf_z[1]+uz*(half*.5-.16)}
				vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,header_x,header_z,length+.08,.045,wall_yaw,frame_tint,14,active_base+.01);vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,header_x,header_z,length+.08,.045,wall_yaw,frame_tint,14,active_base+leaf_height-.045)
			case .Hinged:
				width:=house_door_render_width(length);swing_sign:=opening.window_hinge_right?f32(-1):f32(1);hinge:=opening.window_hinge_right?opening.b:opening.a;yaw:=wall_yaw+swing_sign*f32(math.PI)*.42*door_openness;if opening.window_hinge_right do yaw+=f32(math.PI);leaf_widths[0]=width;leaf_yaws[0]=yaw;leaf_x[0]=hinge.x+f32(math.cos(f64(yaw)))*width*.5;leaf_z[0]=hinge.y+f32(math.sin(f64(yaw)))*width*.5;handle_xs[0]=hinge.x+f32(math.cos(f64(yaw)))*width*HOUSE_DOOR_HANDLE_ALONG;handle_zs[0]=hinge.y+f32(math.sin(f64(yaw)))*width*HOUSE_DOOR_HANDLE_ALONG
			}
			handle_y:=active_base+house_door_handle_height(opening);handle_tint:=[4]u8{157,121,57,255}
			for i in 0..<leaf_count {
				vk_world_add_sized(scene,ctx,&house_door_meshes[opening.door_material],leaf_x[i],leaf_z[i],leaf_widths[i],leaf_height,leaf_yaws[i],{255,255,255,255},0,active_base+.015)
				handle_nx:=-f32(math.sin(f64(leaf_yaws[i])));handle_nz:=f32(math.cos(f64(leaf_yaws[i])));handle_signs:=[2]f32{1,-1};for sign in handle_signs {hx,hz:=handle_xs[i]+handle_nx*.047*sign,handle_zs[i]+handle_nz*.047*sign;hyaw:=sign>0?leaf_yaws[i]:leaf_yaws[i]+f32(math.PI);vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,hx,hz,.045,.14,hyaw,handle_tint,14,handle_y-.07);vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,hx+f32(math.cos(f64(leaf_yaws[i])))*.045,hz+f32(math.sin(f64(leaf_yaws[i])))*.045,.13,.025,hyaw,handle_tint,14,handle_y-.0125)}
			}
		}
	}
	if g.editor_mode==.Build&&(g.build_tool==.Door||g.build_tool==.Window)&&editor_state.opening_active {
		command:=editor_state.opening_command;path_index:=level_path_index(&level_document,command.material)
		if path_index>=0 {path:=level_document.paths[path_index];segment:=int(command.value);if segment>=0&&segment<len(path.points)-1 {a,b:=path.points[segment],path.points[segment+1];dx,dz:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dz*dz)));if length>.001 {
			t:=command.c.x;mx,mz:=a.x+dx*t,a.y+dz*t;wall_yaw:=f32(math.atan2(f64(dz),f64(dx)));blocked:=editor_state.opening_preview.state==.Blocked;tint:=blocked?[4]u8{244,91,91,255}:[4]u8{96,224,156,255}
			if g.build_tool==.Window {
				nx,nz:= -dz/length,dx/length;preview_width:=command.b.y>0?command.b.y:f32(1.6);preview_height:=command.c.y>0?command.c.y:f32(1.4);preview_sill:=active_base+(command.points[0].x>0?command.points[0].x:f32(.72));preview_rail:=f32(HOUSE_WINDOW_FRAME_RAIL_HEIGHT);preview_side:=max(preview_width*.5-preview_rail*.5,f32(0));preview_vertical:=preview_height+preview_rail*2;preview_style:=Window_Style(clamp(int(command.points[0].y),0,int(Window_Style.Double_Hung)));preview_columns,preview_rows:=house_window_style_grid(preview_style,preview_width,preview_height);room_sign:=house_window_room_sign(a,b);if command.points[1].x>0 do room_sign=-room_sign;preview_sash_offset:=house_window_operable_sash_offset(preview_style);preview_sash_x,preview_sash_z:=mx+nx*preview_sash_offset*room_sign,mz+nz*preview_sash_offset*room_sign
				// Double-hung previews expose the same overlapping sash depths as the
				// committed assembly; fixed glazing stays centered while casement and
				// awning sashes use their shallow operable offset.
				preview_glass_width:=max(preview_width-preview_rail*2,.01)
				if preview_style==.Double_Hung&&preview_height>.20 {sash_offset:=house_window_double_hung_sash_offset();half_glass:=preview_height*.5;lower_x,lower_z:=mx+nx*sash_offset*room_sign,mz+nz*sash_offset*room_sign;upper_x,upper_z:=mx-nx*sash_offset*room_sign,mz-nz*sash_offset*room_sign;vk_world_add_sized(scene,ctx,&house_window_mesh,lower_x,lower_z,preview_glass_width,half_glass,wall_yaw,tint,0,preview_sill);vk_world_add_sized(scene,ctx,&house_window_mesh,upper_x,upper_z,preview_glass_width,half_glass,wall_yaw,tint,0,preview_sill+half_glass);vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,lower_x,lower_z,preview_width,preview_rail,wall_yaw,tint,0,preview_sill-preview_rail*.5);vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,upper_x,upper_z,preview_width,preview_rail,wall_yaw,tint,0,preview_sill+preview_height-preview_rail*.5)} else {vk_world_add_sized(scene,ctx,&house_window_mesh,preview_sash_x,preview_sash_z,preview_glass_width,preview_height,wall_yaw,tint,0,preview_sill);vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,preview_sash_x,preview_sash_z,preview_width,preview_rail,wall_yaw,tint,0,preview_sill-preview_rail*.5);vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,preview_sash_x,preview_sash_z,preview_width,preview_rail,wall_yaw,tint,0,preview_sill+preview_height-preview_rail*.5)}
				preview_jamb_x,preview_jamb_z:=preview_style==.Double_Hung?mx:preview_sash_x,preview_style==.Double_Hung?mz:preview_sash_z;vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,preview_jamb_x-dx/length*preview_side,preview_jamb_z-dz/length*preview_side,preview_rail,preview_vertical,wall_yaw,tint,0,preview_sill-preview_rail);vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,preview_jamb_x+dx/length*preview_side,preview_jamb_z+dz/length*preview_side,preview_rail,preview_vertical,wall_yaw,tint,0,preview_sill-preview_rail)
				preview_vertical_member:=house_window_internal_vertical_width(preview_style,preview_rail);preview_horizontal_member:=house_window_internal_horizontal_width(preview_style,preview_rail)
				if preview_style==.Double_Hung&&preview_height>.20 {half_glass:=preview_height*.5;sash_offset:=house_window_double_hung_sash_offset();sash_side:=house_window_double_hung_stile_along(preview_glass_width,preview_rail);lower_x,lower_z:=mx+nx*sash_offset*room_sign,mz+nz*sash_offset*room_sign;upper_x,upper_z:=mx-nx*sash_offset*room_sign,mz-nz*sash_offset*room_sign;for column in 0..=preview_columns {along:=-sash_side+sash_side*2*f32(column)/f32(preview_columns);edge:=column==0||column==preview_columns;member_width:=edge?preview_rail:preview_vertical_member;member_mesh:=edge?&house_window_frame_v_mesh:&house_window_muntin_v_mesh;vk_world_add_sized(scene,ctx,member_mesh,lower_x+dx/length*along,lower_z+dz/length*along,member_width,half_glass,wall_yaw,tint,0,preview_sill);vk_world_add_sized(scene,ctx,member_mesh,upper_x+dx/length*along,upper_z+dz/length*along,member_width,half_glass,wall_yaw,tint,0,preview_sill+half_glass)}} else {for column in 1..<preview_columns {along:=-preview_side+preview_side*2*f32(column)/f32(preview_columns);vk_world_add_sized(scene,ctx,&house_window_muntin_v_mesh,preview_sash_x+dx/length*along,preview_sash_z+dz/length*along,preview_vertical_member,preview_vertical,wall_yaw,tint,0,preview_sill-preview_rail)}}
				if (preview_style==.Casement||preview_style==.Awning)&&preview_height>.12 {outer_width:=house_window_operable_frame_width(preview_rail);outer_side:=max(preview_width*.5-outer_width*.5,f32(0));vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,mx-dx/length*outer_side,mz-dz/length*outer_side,outer_width,preview_vertical,wall_yaw,tint,0,preview_sill-preview_rail);vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,mx+dx/length*outer_side,mz+dz/length*outer_side,outer_width,preview_vertical,wall_yaw,tint,0,preview_sill-preview_rail);vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,mx,mz,preview_width,outer_width,wall_yaw,tint,0,preview_sill-preview_rail*.5);vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,mx,mz,preview_width,outer_width,wall_yaw,tint,0,preview_sill+preview_height+preview_rail*.5-outer_width);mullion_count:=house_window_operable_mullion_count(preview_style,preview_columns);if mullion_count>0 {for mullion in 1..=mullion_count {along:=-preview_side+preview_side*2*f32(mullion)/f32(mullion_count+1);vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,mx+dx/length*along,mz+dz/length*along,outer_width,preview_vertical,wall_yaw,tint,0,preview_sill-preview_rail)}}}
				if preview_style==.Double_Hung&&preview_height>.20 {parting_width:=house_window_double_hung_parting_bead_width(preview_rail);parting_along:=house_window_double_hung_parting_bead_along(preview_glass_width,preview_rail);vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,mx-dx/length*parting_along,mz-dz/length*parting_along,parting_width,preview_height,wall_yaw,tint,0,preview_sill);vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,mx+dx/length*parting_along,mz+dz/length*parting_along,parting_width,preview_height,wall_yaw,tint,0,preview_sill)}
				if preview_style==.Double_Hung&&preview_height>.20 {meeting_y:=preview_sill+preview_height*.5;meeting_offset:=house_window_double_hung_sash_offset();lower_x,lower_z:=mx+nx*meeting_offset*room_sign,mz+nz*meeting_offset*room_sign;upper_x,upper_z:=mx-nx*meeting_offset*room_sign,mz-nz*meeting_offset*room_sign;vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,lower_x,lower_z,preview_width,preview_rail,wall_yaw,tint,0,meeting_y-preview_rail*.42);vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,upper_x,upper_z,preview_width,preview_rail,wall_yaw,tint,0,meeting_y-preview_rail*.58)} else {for row in 1..<preview_rows {row_base:=preview_sill-preview_horizontal_member*.5+preview_height*f32(row)/f32(preview_rows);vk_world_add_sized(scene,ctx,&house_window_muntin_h_mesh,preview_sash_x,preview_sash_z,preview_width,preview_horizontal_member,wall_yaw,tint,0,row_base)}}
				bead:=house_window_glazing_bead_width(preview_rail);frame_bead_offset:=house_window_frame_v_mesh.max.z+.004;bead_yaw:=room_sign>0?wall_yaw:wall_yaw+f32(math.PI);bead_along:=max(preview_glass_width*.5-bead*.5,f32(0))
				if preview_style==.Double_Hung&&preview_height>.20 {half_glass:=preview_height*.5;lower_x,lower_z:=mx+nx*(frame_bead_offset+preview_sash_offset)*room_sign,mz+nz*(frame_bead_offset+preview_sash_offset)*room_sign;upper_offset:=house_window_double_hung_upper_bead_offset(frame_bead_offset);upper_x,upper_z:=mx+nx*upper_offset*room_sign,mz+nz*upper_offset*room_sign;vk_world_add_sized(scene,ctx,&house_window_bead_h_mesh,lower_x,lower_z,preview_glass_width,bead,bead_yaw,tint,0,preview_sill);vk_world_add_sized(scene,ctx,&house_window_bead_h_mesh,lower_x,lower_z,preview_glass_width,bead,bead_yaw,tint,0,preview_sill+half_glass-bead);vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,lower_x-dx/length*bead_along,lower_z-dz/length*bead_along,bead,half_glass,bead_yaw,tint,0,preview_sill);vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,lower_x+dx/length*bead_along,lower_z+dz/length*bead_along,bead,half_glass,bead_yaw,tint,0,preview_sill);vk_world_add_sized(scene,ctx,&house_window_bead_h_mesh,upper_x,upper_z,preview_glass_width,bead,bead_yaw,tint,0,preview_sill+half_glass);vk_world_add_sized(scene,ctx,&house_window_bead_h_mesh,upper_x,upper_z,preview_glass_width,bead,bead_yaw,tint,0,preview_sill+preview_height-bead);vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,upper_x-dx/length*bead_along,upper_z-dz/length*bead_along,bead,half_glass,bead_yaw,tint,0,preview_sill+half_glass);vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,upper_x+dx/length*bead_along,upper_z+dz/length*bead_along,bead,half_glass,bead_yaw,tint,0,preview_sill+half_glass)} else {bead_x,bead_z:=mx+nx*(frame_bead_offset+preview_sash_offset)*room_sign,mz+nz*(frame_bead_offset+preview_sash_offset)*room_sign;vk_world_add_sized(scene,ctx,&house_window_bead_h_mesh,bead_x,bead_z,preview_glass_width,bead,bead_yaw,tint,0,preview_sill);vk_world_add_sized(scene,ctx,&house_window_bead_h_mesh,bead_x,bead_z,preview_glass_width,bead,bead_yaw,tint,0,preview_sill+preview_height-bead);vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,bead_x-dx/length*bead_along,bead_z-dz/length*bead_along,bead,preview_height,bead_yaw,tint,0,preview_sill);vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,bead_x+dx/length*bead_along,bead_z+dz/length*bead_along,bead,preview_height,bead_yaw,tint,0,preview_sill)}
				preview_face_offset:=f32(HOUSE_WALL_THICKNESS*.5+.038);preview_casing_height:=preview_height+preview_rail+.115;preview_signs:=[2]f32{1,-1};for sign in preview_signs {casing_width:=house_window_casing_width(sign==room_sign);ox,oz:=nx*preview_face_offset*sign,nz*preview_face_offset*sign;yaw:=sign>0?wall_yaw:wall_yaw+f32(math.PI);casing_along:=preview_width*.5+casing_width*.5;vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,mx+ox-dx/length*casing_along,mz+oz-dz/length*casing_along,casing_width,preview_casing_height,yaw,tint,0,preview_sill-.07);vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,mx+ox+dx/length*casing_along,mz+oz+dz/length*casing_along,casing_width,preview_casing_height,yaw,tint,0,preview_sill-.07);vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,mx+ox,mz+oz,preview_width+casing_width*2,.045,yaw,tint,0,preview_sill+preview_height+preview_rail)}
				preview_apron:=min(f32(.16),max(preview_sill-active_base-.08,f32(0)));inside_yaw:=room_sign>0?wall_yaw:wall_yaw+f32(math.PI);caulk_width:=house_window_interior_caulk_width();interior_casing:=house_window_casing_width(true);caulk_x,caulk_z:=mx+nx*(preview_face_offset-.008)*room_sign,mz+nz*(preview_face_offset-.008)*room_sign;caulk_along:=preview_width*.5+interior_casing+caulk_width*.5;vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,caulk_x-dx/length*caulk_along,caulk_z-dz/length*caulk_along,caulk_width,preview_casing_height,inside_yaw,tint,0,preview_sill-.07);vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,caulk_x+dx/length*caulk_along,caulk_z+dz/length*caulk_along,caulk_width,preview_casing_height,inside_yaw,tint,0,preview_sill-.07);vk_world_add_sized(scene,ctx,&house_window_bead_h_mesh,caulk_x,caulk_z,preview_width+(interior_casing+caulk_width)*2,caulk_width,inside_yaw,tint,0,preview_sill+preview_height+preview_rail+.038);inside_x,inside_z:=mx+nx*preview_face_offset*room_sign,mz+nz*preview_face_offset*room_sign;if preview_apron>.01 do vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,inside_x,inside_z,max(preview_width-.10,f32(.08)),preview_apron,inside_yaw,tint,0,preview_sill-.07-preview_apron);stool_x,stool_z:=mx+nx*(preview_face_offset+.075)*room_sign,mz+nz*(preview_face_offset+.075)*room_sign;vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,stool_x,stool_z,preview_width+.24,.038,inside_yaw,tint,0,preview_sill-.038)
				exterior_sign:=-room_sign;exterior_yaw:=exterior_sign>0?wall_yaw:wall_yaw+f32(math.PI);sealant_width:=house_window_perimeter_sealant_width();exterior_casing:=house_window_casing_width(false);sealant_x,sealant_z:=mx+nx*(preview_face_offset-.008)*exterior_sign,mz+nz*(preview_face_offset-.008)*exterior_sign;sealant_along:=preview_width*.5+exterior_casing+sealant_width*.5;vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,sealant_x-dx/length*sealant_along,sealant_z-dz/length*sealant_along,sealant_width,preview_casing_height,exterior_yaw,tint,0,preview_sill-.07);vk_world_add_sized(scene,ctx,&house_window_bead_v_mesh,sealant_x+dx/length*sealant_along,sealant_z+dz/length*sealant_along,sealant_width,preview_casing_height,exterior_yaw,tint,0,preview_sill-.07);vk_world_add_sized(scene,ctx,&house_window_bead_h_mesh,sealant_x,sealant_z,preview_width+(exterior_casing+sealant_width)*2,sealant_width,exterior_yaw,tint,0,preview_sill+preview_height+preview_rail+.035);exterior_x,exterior_z:=mx+nx*(preview_face_offset+.07)*exterior_sign,mz+nz*(preview_face_offset+.07)*exterior_sign;vk_world_add_sized(scene,ctx,&house_window_exterior_sill_mesh,exterior_x,exterior_z,preview_width+.24,.07,exterior_yaw,tint,0,preview_sill-.055);flashing_x,flashing_z:=mx+nx*(preview_face_offset+.06)*exterior_sign,mz+nz*(preview_face_offset+.06)*exterior_sign;flashing_width:=preview_width+house_window_head_flashing_overhang()*2;flashing_base:=preview_sill+preview_height+preview_rail+.041;vk_world_add_sized(scene,ctx,&house_window_frame_h_mesh,flashing_x,flashing_z,flashing_width,.022,exterior_yaw,tint,0,flashing_base);dam_width:=house_window_head_flashing_end_dam_width();dam_along:=flashing_width*.5-dam_width*.5;vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,flashing_x-dx/length*dam_along,flashing_z-dz/length*dam_along,dam_width,house_window_head_flashing_end_dam_height(),exterior_yaw,tint,0,flashing_base);vk_world_add_sized(scene,ctx,&house_window_frame_v_mesh,flashing_x+dx/length*dam_along,flashing_z+dz/length*dam_along,dam_width,house_window_head_flashing_end_dam_height(),exterior_yaw,tint,0,flashing_base)
				hardware_offset:=house_window_hardware_offset();hardware_x,hardware_z:=mx+nx*hardware_offset*room_sign,mz+nz*hardware_offset*room_sign;hardware_yaw:=room_sign>0?wall_yaw:wall_yaw+f32(math.PI);preview_hinge_right:=command.points[1].y>0;switch preview_style {case .Casement:if preview_height>.30 {handle_count,hinge_side_count:=house_window_casement_hardware_count(preview_columns);for handle_index in 0..<handle_count {handle_along:=house_window_casement_handle_along(preview_columns,handle_index,preview_side,preview_rail,preview_hinge_right);vk_world_add_sized(scene,ctx,&house_window_hardware_v_mesh,hardware_x+dx/length*handle_along,hardware_z+dz/length*handle_along,.025,.16,hardware_yaw,tint,0,preview_sill+preview_height*.46)};for hinge_index in 0..<hinge_side_count {hinge_along:=house_window_casement_hinge_along(preview_columns,hinge_index,preview_side,preview_rail,preview_hinge_right);hinge_x,hinge_z:=hardware_x+dx/length*hinge_along,hardware_z+dz/length*hinge_along;vk_world_add_sized(scene,ctx,&house_window_hardware_v_mesh,hinge_x,hinge_z,.028,.07,hardware_yaw,tint,0,preview_sill+preview_height*.24);vk_world_add_sized(scene,ctx,&house_window_hardware_v_mesh,hinge_x,hinge_z,.028,.07,hardware_yaw,tint,0,preview_sill+preview_height*.72)}};case .Awning:if preview_height>.30 {vk_world_add_sized(scene,ctx,&house_window_hardware_h_mesh,hardware_x,hardware_z,.20,.025,hardware_yaw,tint,0,preview_sill+.10);pivot_offset:=min(preview_width*.24,f32(.42));pivot_base:=preview_sill+preview_height-.055;vk_world_add_sized(scene,ctx,&house_window_hardware_h_mesh,hardware_x-dx/length*pivot_offset,hardware_z-dz/length*pivot_offset,.08,.024,hardware_yaw,tint,0,pivot_base);vk_world_add_sized(scene,ctx,&house_window_hardware_h_mesh,hardware_x+dx/length*pivot_offset,hardware_z+dz/length*pivot_offset,.08,.024,hardware_yaw,tint,0,pivot_base)};case .Double_Hung:if preview_height>.45 {lift_offset:=min(preview_width*.18,f32(.28));vk_world_add_sized(scene,ctx,&house_window_hardware_h_mesh,hardware_x-dx/length*lift_offset,hardware_z-dz/length*lift_offset,.12,.022,hardware_yaw,tint,0,preview_sill+.10);vk_world_add_sized(scene,ctx,&house_window_hardware_h_mesh,hardware_x+dx/length*lift_offset,hardware_z+dz/length*lift_offset,.12,.022,hardware_yaw,tint,0,preview_sill+.10);vk_world_add_sized(scene,ctx,&house_window_hardware_h_mesh,hardware_x,hardware_z,.14,.026,hardware_yaw,tint,0,preview_sill+preview_height*.5-.013)};case .Fixed,.Picture:}
				vk_world_add_sized(scene,ctx,&house_window_sill_cap_mesh,mx,mz,preview_width+.20,.07,wall_yaw,tint,0,preview_sill-.055)
			} else {open_yaw:=wall_yaw+f32(math.PI)*.42;leaf_length:=command.b.y>0?command.b.y:f32(1.2);leaf_x:=mx-dx/length*leaf_length*.5+f32(math.cos(f64(open_yaw)))*leaf_length*.5;leaf_z:=mz-dz/length*leaf_length*.5+f32(math.sin(f64(open_yaw)))*leaf_length*.5;preview_height:=command.c.y>0?command.c.y:f32(2.1);vk_world_add_sized(scene,ctx,&house_door_meshes[editor_state.door_material],leaf_x,leaf_z,leaf_length,preview_height,open_yaw,tint,0,.02)}
		}}}
	}
	scene.profile_house_openings_ms=time.duration_seconds(time.tick_diff(house_phase_started,time.tick_now()))*1000
	house_phase_started=time.tick_now()
	for item in house_plan.furniture {base:=active_base+item.elevation;position:=Vec2{item.x,item.y};if level_terrain_supports_position(&level_document,position,level_document.active_story) do base+=level_terrain_height(&level_document,position);vk_world_add(scene,ctx,&furniture_meshes[item.kind],item.x,item.y,item.height,item.yaw,item.tint,false,0,base)}
	object_shadow_stride:=max((len(level_document.objects)+255)/256,1);for object,object_index in level_document.objects {no_shadow:=object_shadow_stride>1&&object_index%object_shadow_stride!=0;visible_story:=object.story==level_document.active_story||show_below&&object.story<level_document.active_story;if !visible_story do continue;mesh,found:=catalog_object_mesh(object.catalog_id);if !found do continue;base:=object.elevation;if object.story>=0&&object.story<len(level_document.stories) do base+=level_document.stories[object.story].base_elevation;if level_terrain_supports_position(&level_document,object.position,object.story) do base+=level_terrain_height(&level_document,object.position);entry,entry_found:=catalog_object_entry(object.catalog_id);render_height:=catalog_object_render_height(mesh,entry_found?entry:nil);if entry_found&&entry.category=="foliage" {vk_world_add_foliage(scene,ctx,mesh,object.position.x,object.position.y,render_height,object.rotation*f32(math.PI)/180,object.bark_tint,object.foliage_tint,base,no_shadow)}else{vk_world_add(scene,ctx,mesh,object.position.x,object.position.y,render_height,object.rotation*f32(math.PI)/180,object.tint,false,0,base,0,0,false,no_shadow)}}
	scene.profile_house_objects_ms=time.duration_seconds(time.tick_diff(house_phase_started,time.tick_now()))*1000
	house_phase_started=time.tick_now()
	if g.editor_mode==.Build&&g.build_tool==.Plant&&editor_state.placement_active {
		room_index:=vk_world_room_at(editor_state.placement_position)
		if room_index>=0 {
			room:=level_document.rooms[room_index];min_x,min_z,max_x,max_z:=room.points[0].x,room.points[0].y,room.points[0].x,room.points[0].y
			for point in room.points {min_x=min(min_x,point.x);min_z=min(min_z,point.y);max_x=max(max_x,point.x);max_z=max(max_z,point.y)}
			cell:=f32(.5);x:=f32(math.floor(f64(min_x/cell)))*cell+cell*.5
			for x<max_x {z:=f32(math.floor(f64(min_z/cell)))*cell+cell*.5;for z<max_z {point:=Vec2{x,z};if level_point_in_polygon(point,room.points[:]) {cost:=level_circulation_cost(&level_document,point);tint:=[4]u8{78,190,126,72};if cost>=.78 {tint={239,68,68,126}}else if cost>=.32 {tint={245,170,55,100}};vk_world_add_sized(scene,ctx,&catalog_thumbnail_floor,x,z,cell*.92,cell*.92,0,tint,0,active_base+.012)};z+=cell};x+=cell}
		}
	}
	// Case props share their interaction anchors with StoryCore. Props behind
	// authored gates appear only when the desk, room search, or closet reveals them.
	staging_preview:=g.editor_mode==.Build&&(g.build_tool==.Marker||editor_state.view==.Markers)
	if g.editor_mode!=.Build||staging_preview {
		rug_position:=Vec2{13.6,24.5};rug_mesh:=g.study_rug_lifted?&case_rug_folded_mesh:&case_rug_unfolded_mesh
		vk_world_add(scene,ctx,rug_mesh,rug_position.x,rug_position.y,catalog_object_height(rug_mesh),.08,{255,255,255,255},false,0,active_base+.012)
		if g.study_rug_lifted do vk_world_add(scene,ctx,&bloodstain_mesh,rug_position.x-.18,rug_position.y+.04,1.10,.08,{255,255,255,255},true,0,active_base+.018)
		for &entity in WORLD_ENTITIES {
			if !entity_visible(g,&entity)&&!staging_preview do continue
			if entity.appearance!="" {mesh,found:=catalog_object_mesh(entity.appearance);if found {entry,entry_found:=catalog_object_entry(entity.appearance);height:=catalog_object_render_height(mesh,entry_found?entry:nil);vk_world_add(scene,ctx,mesh,entity.x,entity.y,height,entity.facing,{255,255,255,255},false,0,active_base+entity.elevation)} }
		}
	}
	// Render the wall-mounted shutter mechanism separately from freestanding
	// case props so its moving parts stay aligned with the authored window.
	for &entity in WORLD_ENTITIES do if world_entity_has_tag(&entity,"shutter_mechanism") {
		// The story entity is authored at the physical wall plate, keeping the
		// prompt pointer, approach target, and rendered mechanism coincident.
		mount_x,mount_z:=entity.x,entity.y
		anchor,found:=shutter_crank_world_position();if found {mount_x=anchor.x;mount_z=anchor.y}
		vk_world_add(scene,ctx,&shutter_crank_housing_mesh,mount_x,mount_z,.54,f32(math.PI)*.5,{76,57,39,255},false,0,active_base+.66)
		// Four brass fasteners make the plate read as wall-mounted machinery at
		// gameplay distance instead of a floating brown block.
		fastener_sides:=[2]f32{-1,1};fastener_heights:=[2]f32{.72,1.10};for fastener_z in fastener_sides {for fastener_y in fastener_heights {vk_world_add(scene,ctx,&shutter_crank_link_mesh,mount_x-.095,mount_z+fastener_z*.115,.042,0,{176,133,61,255},false,0,active_base+fastener_y-.021)}}
		// A mechanical travel tell-tale on the housing shows the shutter state
		// independently of the view through the window. The end studs brighten at
		// their respective limit and the needle sweeps continuously between them.
		travel:=clamp(g.shutter_position,0,1);closed_tint:=[4]u8{u8(92+112*(1-travel)),u8(51+38*(1-travel)),42,255};open_tint:=[4]u8{48,u8(76+112*travel),u8(54+54*travel),255}
		indicator_y:=active_base+1.145;vk_world_add(scene,ctx,&shutter_crank_link_mesh,mount_x-.112,mount_z-.09,.038,0,closed_tint,false,0,indicator_y-.019);vk_world_add(scene,ctx,&shutter_crank_link_mesh,mount_x-.112,mount_z+.09,.038,0,open_tint,false,0,indicator_y-.019)
		indicator_angle:=-f32(math.PI)/3+travel*f32(math.PI)*2/3;indicator_radius:=f32(.058);indicator_z:=mount_z+f32(math.sin(f64(indicator_angle)))*indicator_radius*.5;indicator_center_y:=indicator_y+f32(math.cos(f64(indicator_angle)))*indicator_radius*.5;vk_world_add_centered(scene,ctx,&shutter_crank_arm_mesh,mount_x-.125,indicator_z,indicator_center_y,.058,0,indicator_angle,{225,180,83,255})
		// The crank turns in the wall plane while its axle and grip project into
		// the study. Building the spoke from short solid links keeps the motion
		// genuinely three-dimensional without requiring a bespoke skinned prop.
		// Two and a half turns across the shutter travel make the heavy gearing
		// readable while leaving fully closed and fully open at distinct poses.
		crank_angle:=-.65+g.shutter_position*f32(math.PI)*5
		crank_radius:=f32(.27);hub_x,hub_z,hub_y:=mount_x-.13,mount_z,active_base+.94
		// A short wall-face conduit visibly carries the crank drive into the
		// window casing. It sits behind the gear and never intersects the grip.
		vk_world_add_centered(scene,ctx,&shutter_crank_arm_mesh,mount_x-.085,mount_z-.18,hub_y,.065,0,0,{111,83,47,255})
		// The teeth rotate with the handle, making the gearing legible even when
		// the spoke is nearly vertical or horizontal.
		for tooth in 0..<12 {tooth_angle:=crank_angle+f32(tooth)*f32(math.PI)*2/12;tooth_z:=hub_z+f32(math.cos(f64(tooth_angle)))*.108;tooth_y:=hub_y+f32(math.sin(f64(tooth_angle)))*.108;vk_world_add(scene,ctx,&shutter_crank_link_mesh,hub_x-.006,tooth_z,.032,0,{157,113,46,255},false,0,tooth_y-.016)}
		vk_world_add(scene,ctx,&shutter_crank_link_mesh,hub_x,hub_z,.15,0,{235,184,77,255},false,0,hub_y-.075)
		grip_z:=hub_z+f32(math.cos(f64(crank_angle)))*crank_radius;grip_y:=hub_y+f32(math.sin(f64(crank_angle)))*crank_radius;grip_x:=hub_x-.14
		arm_z,arm_y:=(hub_z+grip_z)*.5,(hub_y+grip_y)*.5;vk_world_add_centered(scene,ctx,&shutter_crank_arm_mesh,hub_x-.015,arm_z,arm_y,.065,0,-crank_angle,{210,157,63,255})
		vk_world_add(scene,ctx,&shutter_crank_grip_mesh,grip_x,grip_z,.22,0,{235,184,77,255},false,0,grip_y-.11)
	}
	if g.editor_mode==.Build&&g.build_tool==.Plant&&editor_state.placement_active {
		mesh,found:=catalog_object_mesh(editor_state.catalog_id);entry,entry_found:=catalog_object_entry(editor_state.catalog_id);if found {state:=editor_state.placement_preview.state;status_tint:=state==.Blocked?[4]u8{244,91,91,255}:state==.Warning?[4]u8{244,190,75,255}:[4]u8{96,224,156,255};position:=editor_state.placement_position;base:=level_terrain_height(&level_document,position)+editor_state.placement_elevation;radius:=f32(.4);if entry_found do radius=max(entry.footprint,.2);vk_world_add(scene,ctx,&catalog_thumbnail_floor,position.x,position.y,radius*2,editor_state.placement_rotation*f32(math.PI)/180,status_tint,true,0,base+.008);vk_world_add(scene,ctx,mesh,position.x,position.y,catalog_object_render_height(mesh,entry_found?entry:nil),editor_state.placement_rotation*f32(math.PI)/180,{255,255,255,255},false,0,base+.018)}
	}
	// The investigator is deliberately rendered in the same space as the world,
	// rather than represented by a HUD marker, so the aerial camera remains a
	// genuine third-person view.
	if !g.first_person_camera {player:=&g.player_animation;vk_world_add_animated(scene,ctx,&character_meshes[0],g.player_x,g.player_y,1.65,character_render_yaw(g.player_angle),{255,255,255,255},player.current,player.transitioning?player.next:-1,player.time,player.next_time,player.transitioning?player.transition:0,g.player_elevation,9)}
	// The lieutenant arrives after uniforms have begun working the house. These
	// background officers keep the opening inside the playable crime scene and
	// provide human activity without handing the player an explanation.
	if g.editor_mode!=.Build||staging_preview {
		body_entity:=WORLD_ENTITIES[world_entity_index_with_tag("crime_scene_body")];body_position,body_height,body_yaw:=Vec2{body_entity.x,body_entity.y},body_entity.scale,body_entity.facing;body_base:=level_terrain_supports_position(&level_document,body_position,level_document.active_story)?level_terrain_height(&level_document,body_position):f32(0)
		// The flattened thyme runs from the study terrace toward the staged body.
		// Keep it slightly above the garden floor and below the blood/body layers.
		trace_entity:=WORLD_ENTITIES[world_entity_index_with_tag("drag_trace")];trace_position,trace_size,trace_yaw:=Vec2{trace_entity.x,trace_entity.y},trace_entity.scale,trace_entity.facing;trace_base:=level_terrain_supports_position(&level_document,trace_position,level_document.active_story)?level_terrain_height(&level_document,trace_position):f32(0)
		blood_position,blood_size,blood_yaw:=world_marker_pose("crime_scene_blood",{body_position.x-1.43,body_position.y-.15},1.35,-.12);blood_base:=level_terrain_supports_position(&level_document,blood_position,level_document.active_story)?level_terrain_height(&level_document,blood_position):f32(0)
		vk_world_add(scene,ctx,&drag_trace_mesh,trace_position.x,trace_position.y,trace_size,trace_yaw,{255,255,255,255},true,0,trace_base+.025)
		vk_world_add(scene,ctx,&bloodstain_mesh,blood_position.x,blood_position.y,blood_size,blood_yaw,{255,255,255,255},true,0,blood_base+.045)
		// Edgar is the standard human mesh held in a fixed horizontal pose. Keeping
		// this independent of the death clip avoids animation-root motion hiding the
		// corpse below the garden floor.
		body_clip:=glb_clip_index(&character_meshes[0],"Idle_A")
		vk_world_add_animated(scene,ctx,&character_meshes[0],body_position.x,body_position.y,body_height,body_yaw,{112,105,98,255},body_clip,-1,0,0,0,body_base+.08,9,math.PI/2)
		if g.editor_mode!=.Build {idle:=glb_clip_index(&character_meshes[0],"Idle_A");officer_index:=0;for &entity in WORLD_ENTITIES {if !world_entity_has_tag(&entity,"officer") do continue;position:=Vec2{entity.x,entity.y};base:=level_terrain_supports_position(&level_document,position,level_document.active_story)?level_terrain_height(&level_document,position):f32(0);vk_world_add_animated(scene,ctx,&character_meshes[0],position.x,position.y,1.65,character_render_yaw(entity.facing),{67,91,126,255},idle,-1,g.animation_time+f32(officer_index)*.73,0,0,base,9);officer_index+=1}}
	}
	for &entity,entity_index in WORLD_ENTITIES {
		if !entity_visible(g,&entity)||entity.kind!="person" do continue
		_,tint,_:=character_presentation(entity.source_id);if entity_index==g.hover_entity do tint=entity_examination_complete(g,entity_index)?[4]u8{102,205,143,255}:[4]u8{255,224,116,255};index:=character_index(g,entity.source_id);heading:f32=0
		// Persistent blocking turns authored reactions into visible performance:
		// Daniel checks Miriam before answering, Miriam turns toward him when her
		// denial is exposed, and late-case Elsie keeps facing the desk/cash box.
		if entity.source_id=="daniel"&&claim_known(g,"claim_daniel_alibi") do heading=math.PI
		if entity.source_id=="miriam"&&topic_unlocked(g,"appointment_contradiction") do heading=0
		if entity.source_id=="elsie"&&g.threshold_eight_spent do heading=math.PI/2
		if index>=0&&index<len(g.character_animations) {state:=&g.character_animations[index];position:=Vec2{entity.x,entity.y};base:=level_terrain_supports_position(&level_document,position,level_document.active_story)?level_terrain_height(&level_document,position):f32(0);vk_world_add_animated(scene,ctx,character_mesh_for(entity.source_id),entity.x,entity.y,1.65,character_render_yaw(heading),tint,state.current,state.transitioning?state.next:-1,state.time,state.next_time,state.transitioning?state.transition:0,base)}
	}
	scene.profile_house_characters_ms=time.duration_seconds(time.tick_diff(house_phase_started,time.tick_now()))*1000
}

house_roof_visible :: proc(g:^Game)->bool {
	if g.capture_hide_roofs do return false
	if g.editor_mode==.Build&&(g.build_tool==.Roof||editor_state.view==.Roof) do return true
	// The boom eye commonly sits beyond the building footprint while looking into
	// a room. Roof cutaway follows the camera's subject, not the eye or player, so
	// zooming and orbiting cannot re-enable a roof between camera and subject.
	camera_focus:=Vec2{g.camera_x,g.camera_y}
	if g.first_person_camera do camera_focus={g.player_x,g.player_y}
	if g.camera_pose_override do camera_focus={g.camera_target_override.x,g.camera_target_override.z}
	return house_room_at_point(camera_focus)<0
}

vk_world_build_character_studio :: proc(scene:^Vk_World_Scene,ctx:^engine.Vk_Context,g:^Game) {
	vk_world_add(scene,ctx,&catalog_thumbnail_floor,0,0,14,0,{92,99,108,255},true,7,-.025)
	positions:=[4]f32{-3,-1,1,3}
	for &mesh,i in character_meshes {
		clip:=glb_clip_index(&mesh,i==2?"Idle_B":"Idle_A")
		vk_world_add_animated(scene,ctx,&mesh,positions[i],0,2.25,0,{255,255,255,255},clip,-1,f32(i)*.37,0,0,0,i==0?9:5)
	}
}
