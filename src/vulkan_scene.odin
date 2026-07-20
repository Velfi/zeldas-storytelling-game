package main

import "core:fmt"
import "core:math"
import "core:mem"
import "core:time"
import vk "vendor:vulkan"
import engine "zelda_engine:engine"
import resources "zelda_engine:render_resources"

Vk_World_Vertex :: struct {
	position: Vec3,
	uv:       Vec2,
	joints:   Glb_Joints,
	weights:  Vec4,
}
VK_WORLD_MAX_LIGHTS :: 64
VK_WORLD_MAX_DRAW_LIGHTS :: 8
VK_WORLD_MAX_SHADOW_CASTERS :: 16
VK_WORLD_MAX_DESCRIPTOR_SETS :: 2048 * engine.MAX_FRAMES_IN_FLIGHT
VK_WORLD_DRAW_CAPACITY :: 16384
VK_WORLD_INSTANCES_PER_FRAME :: 16384
VK_WORLD_MAX_INSTANCES :: VK_WORLD_INSTANCES_PER_FRAME * engine.MAX_FRAMES_IN_FLIGHT
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
world_time_of_day :: proc(animation_time: f32) -> f32 {return f32(
		math.mod(f64(WORLD_START_HOUR / 24 + animation_time / WORLD_DAY_SECONDS), 1.0),
	)}
world_time_hour :: proc(animation_time: f32) -> f32 {return world_time_of_day(animation_time) * 24}
world_key_light_direction :: proc(animation_time, weather_strength: f32) -> Vec3 {
	day_angle := world_time_of_day(animation_time) * f32(math.PI * 2)
	sun_height := f32(math.sin(f64(day_angle - f32(math.PI / 2))))
	simulated := vk_world_normalize(
		{
			f32(math.cos(f64(day_angle))),
			max(math.abs(sun_height), f32(.08)),
			f32(math.sin(f64(day_angle))) * .72,
		},
	)
	fixed := Vec3{-.42, .82, .38}; weather := clamp(weather_strength, 0, 1)
	return vk_world_normalize(
		{
			fixed.x + (simulated.x - fixed.x) * weather,
			fixed.y + (simulated.y - fixed.y) * weather,
			fixed.z + (simulated.z - fixed.z) * weather,
		},
	)
}
Vk_World_Camera :: struct {
	view_projection:                       Glb_Mat4,
	camera_position, lighting, atmosphere: [4]f32,
	directional_shadow_matrices:           [4]Glb_Mat4,
	directional_shadow_splits:             [4]f32,
	directional_shadow_params:             [4]f32,
	point_shadow_matrices:                 [24]Glb_Mat4,
	local_shadow_matrices:                 [10]Glb_Mat4,
	light_positions:                       [VK_WORLD_MAX_LIGHTS][4]f32,
	light_colors:                          [VK_WORLD_MAX_LIGHTS][4]f32,
	light_params:                          [VK_WORLD_MAX_LIGHTS][4]f32,
	light_shadow_meta:                     [VK_WORLD_MAX_LIGHTS][4]f32,
	shadow_casters:                        [VK_WORLD_MAX_SHADOW_CASTERS][4]f32,
	shadow_params:                         [VK_WORLD_MAX_SHADOW_CASTERS][4]f32,
}
Vk_World_Push :: struct {
	model:         Glb_Mat4,
	tint:          [4]f32,
	material, pbr: [4]f32,
	skin:          [4]u32,
}
Vk_World_Mesh :: struct {
	source:            ^Glb_Mesh,
	vertices, indices: engine.Vk_Buffer,
	images:            [dynamic]Vk_Ui_Image,
	sets:              [dynamic]vk.DescriptorSet,
}
Vk_World_Draw :: struct {
	mesh:                                                                   int,
	x, z, width, height, yaw, pitch, roll, base_y, light_x, light_z:        f32,
	light_group:                                                            u64,
	tint, bark_tint, foliage_tint:                                          [4]u8,
	foliage_colors:                                                         bool,
	scale_by_footprint, centered, shadow_only, no_shadow, use_light_anchor: bool,
	surface_kind:                                                           int,
	clip_a, clip_b:                                                         int,
	time_a, time_b, blend:                                                  f32,
}
Vk_World_Draw_Lights :: struct {
	indices_a, indices_b: [4]u32,
	weights_a, weights_b: [4]f32,
	meta:                 [4]u32,
}
Vk_World_Light_Cache_Input :: struct {
	x, z:  f32,
	group: u64,
}
Vk_World_Runtime_Light :: struct {
	position:       [4]f32,
	color:          [4]f32,
	params:         [4]f32,
	room, sequence: int,
}
Vk_Shadow_Push :: struct {
	model: Glb_Mat4,
	data:  [4]u32,
}
Vk_Shadow_Image :: struct {
	image:       Vk_Ui_Image,
	layer_views: [dynamic]vk.ImageView,
	layers:      u32,
}
Vk_Shadow_State :: struct {
	directional, points, spots: Vk_Shadow_Image,
	matrix_buffers:             [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
	descriptor_layout:          vk.DescriptorSetLayout,
	descriptor_pool:            vk.DescriptorPool,
	descriptors:                [engine.MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
	pipeline_layout:            vk.PipelineLayout,
	pipeline:                   vk.Pipeline,
	quality:                    Lighting_Quality,
	ready:                      bool,
	point_sources:              [4]int,
	spot_sources:               [6]int,
	matrices:                   [64]Glb_Mat4,
	splits:                     [4]f32,
	cascade_count:              int,
}
CHARACTER_YAW_OFFSET :: -f32(math.PI / 2)
character_render_yaw :: proc(heading: f32) -> f32 {return heading + CHARACTER_YAW_OFFSET}
Vk_World_Scene :: struct {
	meshes:                                                                                                                                                          [dynamic]Vk_World_Mesh,
	draws:                                                                                                                                                           [dynamic]Vk_World_Draw,
	cameras,
	palettes,
	draw_light_buffers:                                                                                                                           [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
	instance_buffer:                                                                                                                                                 engine.Vk_Buffer,
	mesh_cache_sources:                                                                                                                                              [VK_WORLD_MESH_CACHE_CAPACITY]^Glb_Mesh,
	mesh_cache_indices:                                                                                                                                              [VK_WORLD_MESH_CACHE_CAPACITY]int,
	draw_lights:                                                                                                                                                     [dynamic]Vk_World_Draw_Lights,
	light_cache_inputs:                                                                                                                                              [dynamic]Vk_World_Light_Cache_Input,
	light_cache_lights:                                                                                                                                              [dynamic]Vk_World_Runtime_Light,
	light_cache_quality:                                                                                                                                             Lighting_Quality,
	light_cache_valid:                                                                                                                                               bool,
	descriptor_layout:                                                                                                                                               vk.DescriptorSetLayout,
	descriptor_pool:                                                                                                                                                 vk.DescriptorPool,
	pipeline_layout:                                                                                                                                                 vk.PipelineLayout,
	pipeline:                                                                                                                                                        vk.Pipeline,
	depth:                                                                                                                                                           Vk_Ui_Image,
	white,
	flat_normal:                                                                                                                                              Vk_Ui_Image,
	ready:                                                                                                                                                           bool,
	profile_lights_ms,
	profile_batches_ms,
	profile_unbatched_ms:                                                                                                     f64,
	profile_house_structure_ms,
	profile_house_surfaces_ms,
	profile_house_walls_ms,
	profile_house_openings_ms,
	profile_house_objects_ms,
	profile_house_characters_ms: f64,
	shadows:                                                                                                                                                         Vk_Shadow_State,
}
VK_WORLD_MAX_SKINNED_DRAWS :: 16

vk_world_perspective :: proc(fov, aspect, near, far: f32) -> Glb_Mat4 {f :=
		1 / f32(math.tan(f64(fov) * .5))
	return{
		f / aspect,
		0,
		0,
		0,
		0,
		-f,
		0,
		0,
		0,
		0,
		far / (near - far),
		-1,
		0,
		0,
		(near * far) / (near - far),
		0,
	}}
vk_world_normalize :: proc(v: Vec3) -> Vec3 {length := f32(
		math.sqrt(f64(v.x * v.x + v.y * v.y + v.z * v.z)),
	)
	if length <= .00001 do return {}
	return{v.x / length, v.y / length, v.z / length}}
vk_world_look_at :: proc(eye, target, up: Vec3) -> Glb_Mat4 {f := vk_world_normalize(
		{target.x - eye.x, target.y - eye.y, target.z - eye.z},
	)
	s := vk_world_normalize(
		{f.y * up.z - f.z * up.y, f.z * up.x - f.x * up.z, f.x * up.y - f.y * up.x},
	)
	u := Vec3{s.y * f.z - s.z * f.y, s.z * f.x - s.x * f.z, s.x * f.y - s.y * f.x}
	return{
		s.x,
		u.x,
		-f.x,
		0,
		s.y,
		u.y,
		-f.y,
		0,
		s.z,
		u.z,
		-f.z,
		0,
		-(s.x * eye.x + s.y * eye.y + s.z * eye.z),
		-(u.x * eye.x + u.y * eye.y + u.z * eye.z),
		f.x * eye.x + f.y * eye.y + f.z * eye.z,
		1,
	}}

vk_world_orthographic :: proc(left, right, bottom, top, near, far: f32) -> Glb_Mat4 {return{
		2 / (right - left),
		0,
		0,
		0,
		0,
		-2 / (top - bottom),
		0,
		0,
		0,
		0,
		1 / (near - far),
		0,
		-(right + left) / (right - left),
		(top + bottom) / (top - bottom),
		near / (near - far),
		1,
	}}
vk_shadow_practical_splits :: proc(count: int, near, far: f32) -> [4]f32 {result: [4]f32; lambda :=
		f32(.62)
	for 	i in 0 ..< count {p := f32(i + 1) / f32(count); logarithmic :=
			near * f32(math.pow(f64(far / near), f64(p)))
		uniform := near + (far - near) * p
		result[i] = logarithmic * lambda + uniform * (1 - lambda)}
	for i in count ..< 4 do result[i] = far
	return result}

vk_shadow_image_destroy :: proc(image: ^Vk_Shadow_Image, ctx: ^engine.Vk_Context) {for view in image.layer_views do if view != vk.ImageView(0) do vk.DestroyImageView(ctx.device, view, nil)
	delete(image.layer_views)
	vk_ui_image_destroy(&image.image, ctx)
	image^ = {}}
vk_shadow_image_create :: proc(
	ctx: ^engine.Vk_Context,
	width, height, layers: u32,
	cube: bool,
	out: ^Vk_Shadow_Image,
) -> bool {
	// Point shadows retain cube-compatible storage but expose the six faces as a
	// 2D array. Explicit face addressing is consistent across Vulkan and MoltenVK.
	view_type := vk.ImageViewType.D2_ARRAY
	if !resources.image_array_create(
		ctx,
		width,
		height,
		layers,
		.D16_UNORM,
		{.DEPTH_STENCIL_ATTACHMENT, .SAMPLED},
		{.DEPTH},
		view_type,
		cube,
		&out.image,
		"world shadow depth",
	) {if !resources.image_array_create(ctx, width, height, layers, .D32_SFLOAT, {.DEPTH_STENCIL_ATTACHMENT, .SAMPLED}, {.DEPTH}, view_type, cube, &out.image, "world shadow depth fallback") do return false}
	out.layers = layers; out.layer_views = make([dynamic]vk.ImageView, layers, layers)
	for layer in 0 ..< layers {info := vk.ImageViewCreateInfo {
				sType = .IMAGE_VIEW_CREATE_INFO,
				image = out.image.image,
				viewType = .D2,
				format = out.image.format,
				subresourceRange = {
					aspectMask = {.DEPTH},
					baseMipLevel = 0,
					levelCount = 1,
					baseArrayLayer = layer,
					layerCount = 1,
				},
			}; if vk.CreateImageView(ctx.device, &info, nil, &out.layer_views[layer]) !=
		   .SUCCESS {vk_shadow_image_destroy(out, ctx); return false}}
	sampler := vk.SamplerCreateInfo {
			sType         = .SAMPLER_CREATE_INFO,
			magFilter     = .LINEAR,
			minFilter     = .LINEAR,
			mipmapMode    = .NEAREST,
			addressModeU  = .CLAMP_TO_EDGE,
			addressModeV  = .CLAMP_TO_EDGE,
			addressModeW  = .CLAMP_TO_EDGE,
			compareEnable = true,
			compareOp     = .LESS_OR_EQUAL,
			minLod        = 0,
			maxLod        = 0,
			borderColor   = .FLOAT_OPAQUE_WHITE,
		}
	if vk.CreateSampler(ctx.device, &sampler, nil, &out.image.sampler) !=
	   .SUCCESS {vk_shadow_image_destroy(out, ctx); return false}; return true
}

vk_shadow_state_destroy :: proc(
	state: ^Vk_Shadow_State,
	ctx: ^engine.Vk_Context,
) {vk_shadow_image_destroy(&state.directional, ctx); vk_shadow_image_destroy(&state.points, ctx)
	vk_shadow_image_destroy(&state.spots, ctx)
	if state.pipeline != vk.Pipeline(0) do vk.DestroyPipeline(ctx.device, state.pipeline, nil)
	if state.pipeline_layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(ctx.device, state.pipeline_layout, nil)
	if state.descriptor_pool != vk.DescriptorPool(0) do vk.DestroyDescriptorPool(ctx.device, state.descriptor_pool, nil)
	if state.descriptor_layout != vk.DescriptorSetLayout(0) do vk.DestroyDescriptorSetLayout(ctx.device, state.descriptor_layout, nil)
	for &buffer in state.matrix_buffers do engine.vk_destroy_buffer(ctx, &buffer)
	state^ = {}}

vk_shadow_state_init :: proc(
	state: ^Vk_Shadow_State,
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	quality: Lighting_Quality,
) -> bool {
	vk_shadow_state_destroy(
		state,
		ctx,
	); state.quality = quality; cascades := lighting_quality_directional_cascades(quality); point_slots := max(lighting_quality_point_shadow_slots(quality), 1); spot_slots := max(lighting_quality_spot_shadow_slots(quality), 1)
	if !vk_shadow_image_create(ctx, lighting_quality_directional_resolution(quality), lighting_quality_directional_resolution(quality), u32(cascades), false, &state.directional) do return false
	if !vk_shadow_image_create(ctx, lighting_quality_point_shadow_resolution(quality), lighting_quality_point_shadow_resolution(quality), u32(point_slots * 6), true, &state.points) do return false
	if !vk_shadow_image_create(ctx, lighting_quality_spot_shadow_resolution(quality), lighting_quality_spot_shadow_resolution(quality), u32(spot_slots), false, &state.spots) do return false
	for &buffer in state.matrix_buffers do if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(64 * size_of(Glb_Mat4)), {.STORAGE_BUFFER}, &buffer) do return false
	bindings := [2]vk.DescriptorSetLayoutBinding {
		{
			binding = 0,
			descriptorType = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags = {.VERTEX},
		},
		{
			binding = 1,
			descriptorType = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags = {.VERTEX},
		},
	}; layout := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 2,
		pBindings    = raw_data(bindings[:]),
	}; if vk.CreateDescriptorSetLayout(ctx.device, &layout, nil, &state.descriptor_layout) != .SUCCESS do return false
	pool_size := vk.DescriptorPoolSize {
		type            = .STORAGE_BUFFER,
		descriptorCount = 2 * engine.MAX_FRAMES_IN_FLIGHT,
	}; pool := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = engine.MAX_FRAMES_IN_FLIGHT,
		poolSizeCount = 1,
		pPoolSizes    = &pool_size,
	}; if vk.CreateDescriptorPool(ctx.device, &pool, nil, &state.descriptor_pool) != .SUCCESS do return false; layouts := [engine.MAX_FRAMES_IN_FLIGHT]vk.DescriptorSetLayout{}; for &item in layouts do item = state.descriptor_layout; allocation := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = state.descriptor_pool,
		descriptorSetCount = engine.MAX_FRAMES_IN_FLIGHT,
		pSetLayouts        = raw_data(layouts[:]),
	}; if vk.AllocateDescriptorSets(ctx.device, &allocation, raw_data(state.descriptors[:])) != .SUCCESS do return false
	for frame_index in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {matrices := vk.DescriptorBufferInfo {
			buffer = state.matrix_buffers[frame_index].handle,
			range  = vk.DeviceSize(64 * size_of(Glb_Mat4)),
		}; palettes := vk.DescriptorBufferInfo {
			buffer = scene.palettes[frame_index].handle,
			range  = vk.DeviceSize(
				VK_WORLD_MAX_SKINNED_DRAWS * GLB_MAX_JOINTS * size_of(Glb_Mat4),
			),
		}; writes := [2]vk.WriteDescriptorSet {
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = state.descriptors[frame_index],
				dstBinding = 0,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pBufferInfo = &matrices,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = state.descriptors[frame_index],
				dstBinding = 1,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pBufferInfo = &palettes,
			},
		}; vk.UpdateDescriptorSets(ctx.device, 2, raw_data(writes[:]), 0, nil)}
	push_range := vk.PushConstantRange {
		stageFlags = {.VERTEX},
		size       = u32(size_of(Vk_Shadow_Push)),
	}; pipeline_layout := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = 1,
		pSetLayouts            = &state.descriptor_layout,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &push_range,
	}; if vk.CreatePipelineLayout(ctx.device, &pipeline_layout, nil, &state.pipeline_layout) != .SUCCESS do return false
	vert: engine.Vk_Shader_Module; if !engine.vk_load_shader_module(ctx, "build/shaders/shadow.vert.spv", &vert) do return false; defer engine.vk_destroy_shader_module(ctx, &vert); stage := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.VERTEX},
		module = vert.handle,
		pName  = "main",
	}; binding := vk.VertexInputBindingDescription {
		stride    = u32(size_of(Vk_World_Vertex)),
		inputRate = .VERTEX,
	}; attributes := [4]vk.VertexInputAttributeDescription {
		{
			location = 0,
			format = .R32G32B32_SFLOAT,
			offset = u32(offset_of(Vk_World_Vertex, position)),
		},
		{location = 1, format = .R32G32_SFLOAT, offset = u32(offset_of(Vk_World_Vertex, uv))},
		{
			location = 2,
			format = .R16G16B16A16_UINT,
			offset = u32(offset_of(Vk_World_Vertex, joints)),
		},
		{
			location = 3,
			format = .R32G32B32A32_SFLOAT,
			offset = u32(offset_of(Vk_World_Vertex, weights)),
		},
	}; vertex_input := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &binding,
		vertexAttributeDescriptionCount = 4,
		pVertexAttributeDescriptions    = raw_data(attributes[:]),
	}; assembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
	}; viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}; raster := vk.PipelineRasterizationStateCreateInfo {
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable        = false,
		polygonMode             = .FILL,
		cullMode                = {.FRONT},
		frontFace               = .COUNTER_CLOCKWISE,
		depthBiasEnable         = true,
		depthBiasConstantFactor = 1.25,
		depthBiasSlopeFactor    = 1.75,
		lineWidth               = 1,
	}; samples := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
	}; depth := vk.PipelineDepthStencilStateCreateInfo {
		sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable  = true,
		depthWriteEnable = true,
		depthCompareOp   = .LESS_OR_EQUAL,
	}; states := [2]vk.DynamicState {
		.VIEWPORT,
		.SCISSOR,
	}; dynamic_info := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates    = raw_data(states[:]),
	}; rendering := vk.PipelineRenderingCreateInfo {
		sType                 = .PIPELINE_RENDERING_CREATE_INFO,
		depthAttachmentFormat = state.directional.image.format,
	}; info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &rendering,
		stageCount          = 1,
		pStages             = &stage,
		pVertexInputState   = &vertex_input,
		pInputAssemblyState = &assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &raster,
		pMultisampleState   = &samples,
		pDepthStencilState  = &depth,
		pDynamicState       = &dynamic_info,
		layout              = state.pipeline_layout,
	}; if vk.CreateGraphicsPipelines(ctx.device, vk.PipelineCache(0), 1, &info, nil, &state.pipeline) != .SUCCESS do return false; state.ready = true; return true
}

vk_world_model :: proc(
	mesh: ^Glb_Mesh,
	x, z, width, height, yaw, pitch, base_y: f32,
	footprint: bool,
	centered := false,
	roll: f32 = 0,
) -> Glb_Mat4 {
	dimension :=
		footprint ? max(mesh.max.x - mesh.min.x, mesh.max.z - mesh.min.z) : mesh.max.y - mesh.min.y; if dimension <= 0 do dimension = 1
	sy :=
		height /
		dimension; sx, sz := sy, sy; if width > 0 {span_x := mesh.max.x - mesh.min.x; if span_x > .0001 do sx = width / span_x; sz = 1}
	cx, cy, cz :=
		(mesh.min.x + mesh.max.x) *
		.5,
		(mesh.min.y + mesh.max.y) *
		.5,
		(mesh.min.z + mesh.max.z) *
		.5; c, si := f32(math.cos(f64(yaw))), f32(math.sin(f64(yaw))); cp, sp := f32(math.cos(f64(pitch))), f32(math.sin(f64(pitch))); cr, sr := f32(math.cos(f64(roll))), f32(math.sin(f64(roll)))
	c0x, c0y, c0z :=
		(c * cr - si * sp * sr) *
		sx,
		cp *
		sr *
		sx,
		(si * cr + c * sp * sr) *
		sx; c1x, c1y, c1z := (-c * sr - si * sp * cr) * sy, cp * cr * sy, (-si * sr + c * sp * cr) * sy; c2x, c2y, c2z := -si * cp * sz, -sp * sz, c * cp * sz
	if centered {tx := x - (c0x * cx + c1x * cy + c2x * cz); ty := base_y - (c0y * cx + c1y * cy + c2y * cz); tz := z - (c0z * cx + c1z * cy + c2z * cz); return {c0x, c0y, c0z, 0, c1x, c1y, c1z, 0, c2x, c2y, c2z, 0, tx, ty, tz, 1}}
	return {
		c0x,
		c0y,
		c0z,
		0,
		c1x,
		c1y,
		c1z,
		0,
		c2x,
		c2y,
		c2z,
		0,
		x - (c0x * cx + c2x * cz),
		base_y - mesh.min.y * sy,
		z - (c0z * cx + c2z * cz),
		1,
	}
}

vk_world_room_at :: proc(point: Vec2) -> int {for room, i in level_document.rooms do if room.story == level_document.active_story && !room.exterior && level_point_in_polygon(point, room.points[:]) do return i
	return -1}

vk_world_runtime_light_score :: proc(light: Vk_World_Runtime_Light, eye: Vec3) -> f32 {dx, dz :=
		light.position[0] - eye.x, light.position[2] - eye.z
	return light.color[3] / (1 + dx * dx + dz * dz)}
vk_world_runtime_light_insert :: proc(
	out: ^[dynamic]Vk_World_Runtime_Light,
	light: Vk_World_Runtime_Light,
	eye: Vec3,
) {
	if len(out) <
	   VK_WORLD_MAX_LIGHTS {append(out, light); return}; wanted := vk_world_runtime_light_score(light, eye); worst := 0; worst_score := vk_world_runtime_light_score(out[0], eye); for candidate, i in out {score := vk_world_runtime_light_score(candidate, eye); if score < worst_score || (score == worst_score && candidate.sequence > out[worst].sequence) {worst = i; worst_score = score}}; if wanted > worst_score do out[worst] = light
}

vk_world_add_city_vehicle_lights :: proc(
	out: ^[dynamic]Vk_World_Runtime_Light,
	g: ^Game,
	focus: Vec3,
) {
	headlight_signs := [2]f32{-1, 1}
	for vehicle, vehicle_index in g.vehicles {
		forward := Vec2 {
			f32(math.cos(f64(vehicle.heading))),
			f32(math.sin(f64(vehicle.heading))),
		}; side := Vec2{-forward.y, forward.x}
		for sign in headlight_signs {position := Vec2 {
				vehicle.x + forward.x * 1.05 + side.x * .34 * sign,
				vehicle.y + forward.y * 1.05 + side.y * .34 * sign,
			}
			vk_world_runtime_light_insert(
				out,
				Vk_World_Runtime_Light {
					position = {
						position.x,
						city_elevation(position.x, position.y) + .55,
						position.y,
						12,
					},
					color = {1, .82, .58, .42},
					params = {
						f32(Level_Light_Kind.Spot),
						vehicle.heading,
						f32(math.cos(f64(18 * f32(math.PI) / 180))),
						0,
					},
					room = -1,
					sequence = 10000 + vehicle_index * 2 + (sign > 0 ? 1 : 0),
				},
				focus,
			)}
	}
	if g.driving_vehicle < 0 || g.driving_vehicle >= len(g.vehicles) do return
	vehicle :=
		g.vehicles[g.driving_vehicle]; throttle, _ := vehicle_control_inputs(g); handbrake := vehicle_handbrake_input(g); state := vehicle_rear_light_state(vehicle, throttle, handbrake); if state == .Off do return
	forward := Vec2 {
		f32(math.cos(f64(vehicle.heading))),
		f32(math.sin(f64(vehicle.heading))),
	}; side := Vec2{-forward.y, forward.x}; intensity := vehicle_rear_light_intensity(vehicle, throttle, handbrake); color := state == .Brake ? [4]f32{1, .018, .008, intensity} : [4]f32{.88, .94, 1, intensity}; light_range := state == .Brake ? f32(2.2) : f32(3); half_angle := state == .Brake ? f32(16) : f32(20)
	for sign in headlight_signs {position := Vec2 {
			vehicle.x - forward.x * 1.02 + side.x * .33 * sign,
			vehicle.y - forward.y * 1.02 + side.y * .33 * sign,
		}
		vk_world_runtime_light_insert(
			out,
			Vk_World_Runtime_Light {
				position = {
					position.x,
					city_elevation(position.x, position.y) + .52,
					position.y,
					light_range,
				},
				color = color,
				params = {
					f32(Level_Light_Kind.Spot),
					vehicle.heading + f32(math.PI),
					f32(math.cos(f64(half_angle * f32(math.PI) / 180))),
					0,
				},
				room = -1,
				sequence = 20000 + g.driving_vehicle * 2 + (sign > 0 ? 1 : 0),
			},
			focus,
		)}
}

Vk_World_View_Pose :: struct {
	eye, target, up:  Vec3,
	baking, interior: bool,
}

vehicle_camera_distance :: proc(actual_speed: f32) -> f32 {return(
		5.2 +
		clamp(actual_speed / .58, 0, 1) * 1.8 \
	)}
vehicle_camera_height :: proc(actual_speed: f32) -> f32 {return(
		1.15 +
		clamp(actual_speed / .58, 0, 1) * .32 \
	)}
vehicle_camera_acceleration_distance :: proc(v: Vehicle_State) -> f32 {load := clamp(
		v.acceleration_feedback,
		-1,
		1,
	)
	return load * (load >= 0 ? f32(.34) : f32(.20))}
vehicle_camera_effective_distance :: proc(v: Vehicle_State, cleared_distance: f32) -> f32 {
	base := vehicle_camera_distance(vehicle_actual_speed(v)); distance := cleared_distance
	if distance <= 0 do distance = base
	offset := vehicle_camera_acceleration_distance(v)
	// Never spend launch pullback through a boom that was shortened by a wall.
	if offset > 0 && distance < base - .05 do offset = 0
	return max(distance + offset, f32(1.2))
}
vehicle_camera_bank :: proc(v: Vehicle_State) -> f32 {
	actual_speed := vehicle_actual_speed(v)
	// At useful road speed yaw implies opposite lateral load in reverse. Fade its
	// direction through neutral; retain the raw low-speed collision-spin cue.
	travel_direction :=
		actual_speed < .06 ? f32(1) : clamp(vehicle_longitudinal_speed(v) / .04, -1, 1)
	yaw_bank := clamp(v.yaw_rate / .045, -1, 1) * travel_direction * .018
	if actual_speed < .06 do return yaw_bank
	// Yaw communicates an ordinary corner; signed lateral travel adds a second,
	// bounded cue when the velocity vector escapes the chassis during oversteer.
	right_x := -f32(math.sin(f64(v.heading))); right_y := f32(math.cos(f64(v.heading)))
	lateral := v.velocity_x * right_x + v.velocity_y * right_y
	slip := clamp(lateral / max(actual_speed, f32(.05)), -1, 1)
	speed_weight := clamp((actual_speed - .06) / .25, 0, 1)
	force_bank := clamp(v.chassis_lateral_acceleration, -1, 1) * speed_weight * .020
	return clamp(yaw_bank + force_bank + slip * speed_weight * .012, -.05, .05)
}
vehicle_camera_impact_jolt :: proc(v: Vehicle_State, animation_time: f32) -> f32 {return(
		f32(math.sin(f64(animation_time * 72))) *
		v.impact *
		.09 \
	)}
vehicle_camera_impact_offset :: proc(v: Vehicle_State, animation_time: f32) -> Vec2 {
	forward, side := v.impact_forward, v.impact_side
	directional := math.abs(forward) + math.abs(side) >= .001
	phase := directional ? v.impact_time : animation_time
	if !directional do side = 1
	wave := f32(math.sin(f64(phase * 72))) * v.impact
	// Camera inertia initially travels opposite the resolved acceleration delta.
	return {-wave * forward * .075, -wave * side * .09}
}
vehicle_camera_rough_jolt :: proc(v: Vehicle_State) -> f32 {
	phase := v.x * 6.9 + v.y * 7.7 + .2
	return f32(math.sin(f64(phase))) * vehicle_rough_feedback_blended(v, v.surface_blend) * .018
}
vehicle_rough_body_pose :: proc(v: Vehicle_State) -> (roll, pitch: f32) {
	amount := vehicle_rough_feedback_blended(v, v.surface_blend)
	// Spatial phases make bump frequency follow ground speed and keep nearby cars
	// from bobbing in sync. Amplitudes remain subordinate to real load transfer.
	roll = f32(math.sin(f64(v.x * 7.3 + v.y * 4.9 + 1.7))) * amount * .006
	pitch = f32(math.sin(f64(v.x * 5.7 - v.y * 8.1 + .6))) * amount * .010
	return
}
vehicle_camera_field_of_view :: proc(v: Vehicle_State) -> f32 {
	speed_response := clamp(vehicle_actual_speed(v) / .58, 0, 1) * .105
	impact_response := clamp(v.impact, 0, 1) * .022
	load := clamp(
		v.acceleration_feedback,
		-1,
		1,
	); acceleration_response := load >= 0 ? load * .014 : load * .006
	return f32(math.PI / 3) + speed_response + impact_response + acceleration_response
}

vk_world_view_pose :: proc(g: ^Game) -> Vk_World_View_Pose {
	if g.screen == .Dialogue &&
	   g.story_presentation.interaction_active {distance := 3.5 * g.dialogue_interaction.zoom; return {{.35, 1.15, distance}, {.35, .78, 0}, {0, 1, 0}, false, true}}
	px, pz, angle := g.player_x, g.player_y, g.player_angle
	driving_speed: f32 = 0; driving_orbit_angle := angle
	if g.screen ==
	   .Exterior {px, pz, angle = g.city_x, g.city_y, g.city_angle; driving_orbit_angle = angle; if g.driving_vehicle >= 0 {car := g.vehicles[g.driving_vehicle]; driving_speed = vehicle_actual_speed(car); distance := vehicle_camera_effective_distance(car, g.vehicle_camera_follow_distance); driving_orbit_angle = angle + g.vehicle_camera_reverse_blend * f32(math.PI); px = car.x - f32(math.cos(f64(driving_orbit_angle))) * distance; pz = car.y - f32(math.sin(f64(driving_orbit_angle))) * distance}}
	interior :=
		g.screen == .Investigate ||
		g.screen ==
			.Dialogue; baking := g.catalog_bake_index >= 0; aerial := interior || (g.screen == .Exterior && g.driving_vehicle < 0)
	eye := Vec3 {
		px,
		vehicle_camera_height(driving_speed),
		pz,
	}; target := Vec3{px + f32(math.cos(f64(angle))), 1.15, pz + f32(math.sin(f64(angle)))}; up := Vec3{0, 1, 0}
	if g.screen == .Exterior && g.driving_vehicle >= 0 {
		car :=
			g.vehicles[g.driving_vehicle]; lookahead := 1.1 + clamp(driving_speed / .58, 0, 1) * 2.4; target = {car.x + car.velocity_x * lookahead, 0.72, car.y + car.velocity_y * lookahead}
		bank := vehicle_camera_bank(
			car,
		); right_x, right_z := -f32(math.sin(f64(driving_orbit_angle))), f32(math.cos(f64(driving_orbit_angle))); up = {right_x * bank, 1, right_z * bank}
		impact_offset := vehicle_camera_impact_offset(
			car,
			g.animation_time,
		); car_forward_x, car_forward_z := f32(math.cos(f64(car.heading))), f32(math.sin(f64(car.heading))); car_right_x, car_right_z := -car_forward_z, car_forward_x; jolt_x := car_forward_x * impact_offset.x + car_right_x * impact_offset.y; jolt_z := car_forward_z * impact_offset.x + car_right_z * impact_offset.y; jolt_magnitude := f32(math.sqrt(f64(jolt_x * jolt_x + jolt_z * jolt_z))); eye.y += jolt_magnitude * .55; eye.x += jolt_x; eye.z += jolt_z; target.x += jolt_x * .22; target.z += jolt_z * .22
		rough_jolt := vehicle_camera_rough_jolt(
			car,
		); eye.y += rough_jolt; target.y += rough_jolt * .28
		eye.y += city_elevation(eye.x, eye.z); target.y += city_elevation(target.x, target.z)
	}
	if baking {eye = {2.6, 2.2, 2.6}; target = {0, .72, 0}} else if aerial {focus_x, focus_z := px, pz; if interior && g.camera_initialized {focus_x, focus_z = g.camera_x, g.camera_y} else if g.screen == .Exterior && g.city_camera_initialized {focus_x, focus_z = g.city_camera_x, g.city_camera_y}; base_y := camera_story_y(g); if g.screen == .Exterior do base_y = city_elevation(focus_x, focus_z); eye, target, up = aerial_camera_pose(g, focus_x, focus_z, base_y)}
	if g.character_studio {eye = {0, 3.2, 10}; target = {0, 1, 0}; up = {0, 1, 0}}
	if interior &&
	   g.first_person_camera {pitch_scale := f32(math.cos(f64(g.first_person_pitch))); eye_height := g.player_elevation + 1.65; eye = {g.player_x, eye_height, g.player_y}; target = {g.player_x + f32(math.cos(f64(g.player_angle))) * pitch_scale, eye_height + f32(math.sin(f64(g.first_person_pitch))), g.player_y + f32(math.sin(f64(g.player_angle))) * pitch_scale}; up = {0, 1, 0}}
	return {eye, target, up, baking, interior}
}

vk_world_reuse_grouped_light_list :: proc(scene: ^Vk_World_Scene, draw_index: int) -> bool {
	if draw_index < 0 || draw_index >= len(scene.draws) || scene.draws[draw_index].light_group == 0 do return false
	for candidate in 0 ..< draw_index do if scene.draws[candidate].light_group == scene.draws[draw_index].light_group {scene.draw_lights[draw_index] = scene.draw_lights[candidate]; return true}
	return false
}

vk_world_build_draw_light_lists :: proc(
	scene: ^Vk_World_Scene,
	lights: []Vk_World_Runtime_Light,
	quality: Lighting_Quality,
	frame_index: int,
) {
	limit := lighting_quality_light_count(
		quality,
	); shadow_candidates := lighting_quality_shadow_candidates(quality); draw_count := min(len(scene.draws), len(scene.draw_lights)); group_keys: [256]u64; group_draws: [256]int; point_x: [4096]f32; point_z: [4096]f32; point_previous_primary: [4096]u32; point_previous_active: [4096]bool; point_draws: [4096]int; for &index in group_draws do index = -1; for &index in point_draws do index = -1
	cache_matches :=
		scene.light_cache_valid &&
		scene.light_cache_quality == quality &&
		len(scene.light_cache_inputs) == draw_count &&
		len(scene.light_cache_lights) == len(lights)
	if cache_matches {for light, i in lights do if light != scene.light_cache_lights[i] {cache_matches = false; break}}
	if cache_matches {for draw, i in scene.draws[:draw_count] {sample_x, sample_z := draw.x, draw.z; if draw.use_light_anchor do sample_x, sample_z = draw.light_x, draw.light_z; input := scene.light_cache_inputs[i]; if input.x != sample_x || input.z != sample_z || input.group != draw.light_group {cache_matches = false; break}}}
	if cache_matches {if draw_count > 0 do mem.copy_non_overlapping(scene.draw_light_buffers[frame_index].mapped, raw_data(scene.draw_lights[:draw_count]), draw_count * size_of(Vk_World_Draw_Lights)); return}
	for draw_index in 0 ..< draw_count {
		draw := &scene.draws[draw_index]
		group_slot := int(
			draw.light_group % len(group_keys),
		); if draw.light_group != 0 && group_keys[group_slot] == draw.light_group && group_draws[group_slot] >= 0 {scene.draw_lights[draw_index] = scene.draw_lights[group_draws[group_slot]]; continue}
		sample_x, sample_z :=
			draw.x,
			draw.z; if draw.use_light_anchor do sample_x, sample_z = draw.light_x, draw.light_z; previous := scene.draw_lights[draw_index]; previous_active := previous.meta[0] > 0; previous_primary := previous.indices_a[0]; point_hash := u64(transmute(u32)sample_x) * 0x9e3779b1 ~ u64(transmute(u32)sample_z); point_slot := int(point_hash % len(point_draws)); if point_draws[point_slot] >= 0 && point_x[point_slot] == sample_x && point_z[point_slot] == sample_z && point_previous_active[point_slot] == previous_active && point_previous_primary[point_slot] == previous_primary {scene.draw_lights[draw_index] = scene.draw_lights[point_draws[point_slot]]; continue}; list := Vk_World_Draw_Lights{}; scores: [VK_WORLD_MAX_DRAW_LIGHTS]f32; indices: [VK_WORLD_MAX_DRAW_LIGHTS]u32; weights: [VK_WORLD_MAX_DRAW_LIGHTS]f32; count := 0; draw_room := vk_world_room_at({sample_x, sample_z})
		for light, light_index in lights {dx, dz :=
				sample_x - light.position[0], sample_z - light.position[2]
			distance_sq := dx * dx + dz * dz
			range := max(light.position[3], .01)
			if distance_sq >= range * range do continue
			room_weight := f32(1)
			if draw_room !=
			   light.room {if !world_line_clear(sample_x, sample_z, light.position[0], light.position[2]) do continue
				room_weight = .35}
			falloff := 1 - f32(math.sqrt(f64(distance_sq))) / range
			score := light.color[3] * room_weight * falloff * falloff
			if score <= .0001 do continue
			insert := min(count, limit - 1)
			for slot in 0 ..< min(
				count,
				limit,
			) {if score > scores[slot] + .00001 || (math.abs(score - scores[slot]) <= .00001 && light_index < int(indices[slot])) {insert = slot; break}}
			if insert >= limit do continue
			end := min(count, limit - 1)
			for slot := end;
			    slot > insert;
			    slot -= 1 {scores[slot] = scores[slot - 1]; indices[slot] = indices[slot - 1]
				weights[slot] = weights[slot - 1]}
			scores[insert] = score
			indices[insert] = u32(light_index)
			weights[insert] = room_weight
			if count < limit do count += 1}
		if previous.meta[0] > 0 &&
		   count >
			   1 {previous_primary := previous.indices_a[0]; for slot in 1 ..< count do if indices[slot] == previous_primary && scores[0] < scores[slot] * 1.05 {scores[0], scores[slot] = scores[slot], scores[0]; indices[0], indices[slot] = indices[slot], indices[0]; weights[0], weights[slot] = weights[slot], weights[0]; break}}
		for slot in 0 ..< count {if slot < 4 {list.indices_a[slot] = indices[slot]; list.weights_a[slot] = weights[slot]} else {list.indices_b[slot - 4] = indices[slot]; list.weights_b[slot - 4] = weights[slot]}}; list.meta[0] = u32(count); list.meta[2] = u32(min(count, shadow_candidates)); if count > 0 && shadow_candidates > 0 do list.meta[1] = indices[0] + 1; scene.draw_lights[draw_index] = list; point_x[point_slot] = sample_x; point_z[point_slot] = sample_z; point_previous_active[point_slot] = previous_active; point_previous_primary[point_slot] = previous_primary; point_draws[point_slot] = draw_index; if draw.light_group != 0 {group_keys[group_slot] = draw.light_group; group_draws[group_slot] = draw_index}
	}
	resize(
		&scene.light_cache_inputs,
		draw_count,
	); for draw, i in scene.draws[:draw_count] {sample_x, sample_z := draw.x, draw.z; if draw.use_light_anchor do sample_x, sample_z = draw.light_x, draw.light_z; scene.light_cache_inputs[i] = {sample_x, sample_z, draw.light_group}}
	resize(
		&scene.light_cache_lights,
		len(lights),
	); copy(scene.light_cache_lights[:], lights); scene.light_cache_quality = quality; scene.light_cache_valid = true
	if draw_count > 0 do mem.copy_non_overlapping(scene.draw_light_buffers[frame_index].mapped, raw_data(scene.draw_lights[:draw_count]), draw_count * size_of(Vk_World_Draw_Lights))
}

vk_world_depth_create :: proc(
	ctx: ^engine.Vk_Context,
	width, height: u32,
	out: ^Vk_Ui_Image,
	samples: vk.SampleCountFlags = {._1},
) -> bool {
	return resources.depth_create(ctx, width, height, out, samples)
}

vk_world_mesh_destroy :: proc(mesh: ^Vk_World_Mesh, ctx: ^engine.Vk_Context) {for &image in mesh.images do vk_ui_image_destroy(&image, ctx)
	delete(mesh.images)
	delete(mesh.sets)
	engine.vk_destroy_buffer(ctx, &mesh.indices)
	engine.vk_destroy_buffer(ctx, &mesh.vertices)
	mesh^ = {}}
vk_world_destroy :: proc(scene: ^Vk_World_Scene, ctx: ^engine.Vk_Context) {for &mesh in scene.meshes do vk_world_mesh_destroy(&mesh, ctx)
	delete(scene.meshes)
	delete(scene.draws)
	delete(scene.draw_lights)
	delete(scene.light_cache_inputs)
	delete(scene.light_cache_lights)
	vk_ui_image_destroy(&scene.white, ctx)
	vk_ui_image_destroy(&scene.flat_normal, ctx)
	vk_ui_image_destroy(&scene.depth, ctx)
	if scene.pipeline != vk.Pipeline(0) do vk.DestroyPipeline(ctx.device, scene.pipeline, nil)
	if scene.pipeline_layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(ctx.device, scene.pipeline_layout, nil)
	if scene.descriptor_pool != vk.DescriptorPool(0) do vk.DestroyDescriptorPool(ctx.device, scene.descriptor_pool, nil)
	if scene.descriptor_layout != vk.DescriptorSetLayout(0) do vk.DestroyDescriptorSetLayout(ctx.device, scene.descriptor_layout, nil)
	vk_shadow_state_destroy(&scene.shadows, ctx)
	engine.vk_destroy_buffer(ctx, &scene.instance_buffer)
	for 	i in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {engine.vk_destroy_buffer(ctx, &scene.draw_light_buffers[i])
		engine.vk_destroy_buffer(ctx, &scene.palettes[i])
		engine.vk_destroy_buffer(ctx, &scene.cameras[i])}
	scene^ = {}}

vk_world_init :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	sample_count: vk.SampleCountFlags = {._1},
) -> bool {
	scene^ =
		{}; scene.meshes = make([dynamic]Vk_World_Mesh, 0, 64); scene.draws = make([dynamic]Vk_World_Draw, 0, VK_WORLD_DRAW_LIGHT_CAPACITY); scene.draw_lights = make([dynamic]Vk_World_Draw_Lights, VK_WORLD_DRAW_LIGHT_CAPACITY, VK_WORLD_DRAW_LIGHT_CAPACITY)
	for i in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {
		if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(size_of(Vk_World_Camera)), {.UNIFORM_BUFFER}, &scene.cameras[i]) do return false
		if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(VK_WORLD_MAX_SKINNED_DRAWS * GLB_MAX_JOINTS * size_of(Glb_Mat4)), {.STORAGE_BUFFER}, &scene.palettes[i]) do return false
		if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(VK_WORLD_DRAW_LIGHT_CAPACITY * size_of(Vk_World_Draw_Lights)), {.STORAGE_BUFFER}, &scene.draw_light_buffers[i]) do return false
	}
	if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(VK_WORLD_MAX_INSTANCES * size_of(Vk_World_Push)), {.STORAGE_BUFFER}, &scene.instance_buffer) do return false
	// Allocate the maximum fixed arrays once. Live quality changes alter active
	// layers and update budgets without invalidating every material descriptor.
	if !vk_shadow_state_init(&scene.shadows, scene, ctx, .Ultra) do return false
	bindings := [12]vk.DescriptorSetLayoutBinding {
		{
			binding = 0,
			descriptorType = .UNIFORM_BUFFER,
			descriptorCount = 1,
			stageFlags = {.VERTEX, .FRAGMENT},
		},
		{
			binding = 1,
			descriptorType = .SAMPLED_IMAGE,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT},
		},
		{binding = 2, descriptorType = .SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
		{
			binding = 3,
			descriptorType = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags = {.VERTEX},
		},
		{
			binding = 4,
			descriptorType = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT},
		},
		{
			binding = 5,
			descriptorType = .SAMPLED_IMAGE,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT},
		},
		{
			binding = 6,
			descriptorType = .SAMPLED_IMAGE,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT},
		},
		{
			binding = 7,
			descriptorType = .SAMPLED_IMAGE,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT},
		},
		{binding = 8, descriptorType = .SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
		{
			binding = 9,
			descriptorType = .SAMPLED_IMAGE,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT},
		},
		{
			binding = 10,
			descriptorType = .SAMPLED_IMAGE,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT},
		},
		{
			binding = 11,
			descriptorType = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags = {.VERTEX, .FRAGMENT},
		},
	}; layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 12,
		pBindings    = raw_data(bindings[:]),
	}; if vk.CreateDescriptorSetLayout(ctx.device, &layout_info, nil, &scene.descriptor_layout) != .SUCCESS do return false
	pool_sizes := [4]vk.DescriptorPoolSize {
		{type = .UNIFORM_BUFFER, descriptorCount = VK_WORLD_MAX_DESCRIPTOR_SETS},
		{type = .SAMPLED_IMAGE, descriptorCount = VK_WORLD_MAX_DESCRIPTOR_SETS * 6},
		{type = .SAMPLER, descriptorCount = VK_WORLD_MAX_DESCRIPTOR_SETS * 2},
		{type = .STORAGE_BUFFER, descriptorCount = VK_WORLD_MAX_DESCRIPTOR_SETS * 3},
	}; pool := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = VK_WORLD_MAX_DESCRIPTOR_SETS,
		poolSizeCount = 4,
		pPoolSizes    = raw_data(pool_sizes[:]),
	}; if vk.CreateDescriptorPool(ctx.device, &pool, nil, &scene.descriptor_pool) != .SUCCESS do return false
	push := vk.PushConstantRange {
		stageFlags = {.VERTEX, .FRAGMENT},
		size       = u32(size_of(Vk_World_Push)),
	}; pipeline_layout := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = 1,
		pSetLayouts            = &scene.descriptor_layout,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &push,
	}; if vk.CreatePipelineLayout(ctx.device, &pipeline_layout, nil, &scene.pipeline_layout) != .SUCCESS do return false
	vert, frag: engine.Vk_Shader_Module; if !engine.vk_load_shader_module(ctx, "build/shaders/world.vert.spv", &vert) do return false; defer engine.vk_destroy_shader_module(ctx, &vert); if !engine.vk_load_shader_module(ctx, "build/shaders/world.frag.spv", &frag) do return false; defer engine.vk_destroy_shader_module(ctx, &frag)
	stages := [2]vk.PipelineShaderStageCreateInfo {
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.VERTEX},
			module = vert.handle,
			pName = "main",
		},
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = frag.handle,
			pName = "main",
		},
	}; binding := vk.VertexInputBindingDescription {
		stride    = u32(size_of(Vk_World_Vertex)),
		inputRate = .VERTEX,
	}; attributes := [4]vk.VertexInputAttributeDescription {
		{
			location = 0,
			format = .R32G32B32_SFLOAT,
			offset = u32(offset_of(Vk_World_Vertex, position)),
		},
		{location = 1, format = .R32G32_SFLOAT, offset = u32(offset_of(Vk_World_Vertex, uv))},
		{
			location = 2,
			format = .R16G16B16A16_UINT,
			offset = u32(offset_of(Vk_World_Vertex, joints)),
		},
		{
			location = 3,
			format = .R32G32B32A32_SFLOAT,
			offset = u32(offset_of(Vk_World_Vertex, weights)),
		},
	}; vertex_input := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &binding,
		vertexAttributeDescriptionCount = 4,
		pVertexAttributeDescriptions    = raw_data(attributes[:]),
	}; assembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
	}; viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}; raster := vk.PipelineRasterizationStateCreateInfo {
		sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		cullMode    = {.BACK},
		frontFace   = .COUNTER_CLOCKWISE,
		lineWidth   = 1,
	}; samples := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = sample_count,
	}; depth := vk.PipelineDepthStencilStateCreateInfo {
		sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable  = true,
		depthWriteEnable = true,
		depthCompareOp   = .LESS_OR_EQUAL,
	}; attachment := vk.PipelineColorBlendAttachmentState {
		blendEnable         = true,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp        = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
		alphaBlendOp        = .ADD,
		colorWriteMask      = {.R, .G, .B, .A},
	}; blend := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &attachment,
	}; states := [2]vk.DynamicState {
		.VIEWPORT,
		.SCISSOR,
	}; dynamic_info := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates    = raw_data(states[:]),
	}; rendering := engine.vk_pipeline_rendering_info(
		&ctx.swapchain_format,
	); rendering.depthAttachmentFormat = .D32_SFLOAT; info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &rendering,
		stageCount          = 2,
		pStages             = raw_data(stages[:]),
		pVertexInputState   = &vertex_input,
		pInputAssemblyState = &assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &raster,
		pMultisampleState   = &samples,
		pDepthStencilState  = &depth,
		pColorBlendState    = &blend,
		pDynamicState       = &dynamic_info,
		layout              = scene.pipeline_layout,
	}; if vk.CreateGraphicsPipelines(ctx.device, vk.PipelineCache(0), 1, &info, nil, &scene.pipeline) != .SUCCESS do return false
	white := [4]u8 {
		255,
		255,
		255,
		255,
	}; flat_normal := [4]u8{128, 128, 255, 255}; if !resources.texture_upload_rgba8(ctx, white[:], 1, 1, &scene.white, resources.Sampler_Options{address_mode = .REPEAT}) do return false; if !resources.texture_upload_rgba8(ctx, flat_normal[:], 1, 1, &scene.flat_normal, resources.Sampler_Options{address_mode = .REPEAT, linear_color = true}) do return false; if !vk_world_depth_create(ctx, ctx.swapchain_extent.width, ctx.swapchain_extent.height, &scene.depth, sample_count) do return false; scene.ready = true; return true
}

vk_world_descriptor :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	base, normal, roughness: ^Vk_Ui_Image,
	frame_index: int,
) -> (
	vk.DescriptorSet,
	bool,
) {set: vk.DescriptorSet; alloc := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = scene.descriptor_pool,
		descriptorSetCount = 1,
		pSetLayouts        = &scene.descriptor_layout,
	}; if vk.AllocateDescriptorSets(ctx.device, &alloc, &set) != .SUCCESS do return set, false; buffer := vk.DescriptorBufferInfo {
		buffer = scene.cameras[frame_index].handle,
		range  = vk.DeviceSize(size_of(Vk_World_Camera)),
	}; palette := vk.DescriptorBufferInfo {
		buffer = scene.palettes[frame_index].handle,
		range  = vk.DeviceSize(VK_WORLD_MAX_SKINNED_DRAWS * GLB_MAX_JOINTS * size_of(Glb_Mat4)),
	}; draw_lights := vk.DescriptorBufferInfo {
		buffer = scene.draw_light_buffers[frame_index].handle,
		range  = vk.DeviceSize(VK_WORLD_DRAW_LIGHT_CAPACITY * size_of(Vk_World_Draw_Lights)),
	}; instances := vk.DescriptorBufferInfo {
		buffer = scene.instance_buffer.handle,
		range  = vk.DeviceSize(VK_WORLD_MAX_INSTANCES * size_of(Vk_World_Push)),
	}; base_info := vk.DescriptorImageInfo {
		imageView   = base.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}; normal_info := vk.DescriptorImageInfo {
		imageView   = normal.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}; roughness_info := vk.DescriptorImageInfo {
		imageView   = roughness.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}; sampler := vk.DescriptorImageInfo {
		sampler = base.sampler,
	}; directional := vk.DescriptorImageInfo {
		imageView   = scene.shadows.directional.image.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}; points := vk.DescriptorImageInfo {
		imageView   = scene.shadows.points.image.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}; spots := vk.DescriptorImageInfo {
		imageView   = scene.shadows.spots.image.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}; shadow_sampler := vk.DescriptorImageInfo {
		sampler = scene.shadows.directional.image.sampler,
	}; writes := [12]vk.WriteDescriptorSet {
		{
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = set,
			dstBinding = 0,
			descriptorCount = 1,
			descriptorType = .UNIFORM_BUFFER,
			pBufferInfo = &buffer,
		},
		{
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = set,
			dstBinding = 1,
			descriptorCount = 1,
			descriptorType = .SAMPLED_IMAGE,
			pImageInfo = &base_info,
		},
		{
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = set,
			dstBinding = 2,
			descriptorCount = 1,
			descriptorType = .SAMPLER,
			pImageInfo = &sampler,
		},
		{
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = set,
			dstBinding = 3,
			descriptorCount = 1,
			descriptorType = .STORAGE_BUFFER,
			pBufferInfo = &palette,
		},
		{
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = set,
			dstBinding = 4,
			descriptorCount = 1,
			descriptorType = .STORAGE_BUFFER,
			pBufferInfo = &draw_lights,
		},
		{
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = set,
			dstBinding = 5,
			descriptorCount = 1,
			descriptorType = .SAMPLED_IMAGE,
			pImageInfo = &directional,
		},
		{
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = set,
			dstBinding = 6,
			descriptorCount = 1,
			descriptorType = .SAMPLED_IMAGE,
			pImageInfo = &points,
		},
		{
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = set,
			dstBinding = 7,
			descriptorCount = 1,
			descriptorType = .SAMPLED_IMAGE,
			pImageInfo = &spots,
		},
		{
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = set,
			dstBinding = 8,
			descriptorCount = 1,
			descriptorType = .SAMPLER,
			pImageInfo = &shadow_sampler,
		},
		{
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = set,
			dstBinding = 9,
			descriptorCount = 1,
			descriptorType = .SAMPLED_IMAGE,
			pImageInfo = &normal_info,
		},
		{
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = set,
			dstBinding = 10,
			descriptorCount = 1,
			descriptorType = .SAMPLED_IMAGE,
			pImageInfo = &roughness_info,
		},
		{
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = set,
			dstBinding = 11,
			descriptorCount = 1,
			descriptorType = .STORAGE_BUFFER,
			pBufferInfo = &instances,
		},
	}; vk.UpdateDescriptorSets(ctx.device, 12, raw_data(writes[:]), 0, nil); return set, true}

vk_world_image_upload :: proc(
	ctx: ^engine.Vk_Context,
	pixels: []u8,
	width, height: int,
	out: ^Vk_Ui_Image,
) -> bool {
	// World UVs intentionally exceed 0..1 so grass, paths, roofs, and room
	// coverings tile at a stable physical scale. UI art uses the clamp sampler.
	return resources.texture_upload_rgba8(
		ctx,
		pixels,
		width,
		height,
		out,
		resources.Sampler_Options{address_mode = .REPEAT},
	)
}

vk_world_linear_image_upload :: proc(
	ctx: ^engine.Vk_Context,
	pixels: []u8,
	width, height: int,
	out: ^Vk_Ui_Image,
) -> bool {return resources.texture_upload_rgba8(
		ctx,
		pixels,
		width,
		height,
		out,
		resources.Sampler_Options{address_mode = .REPEAT, linear_color = true},
	)}

vk_world_register_mesh :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	source: ^Glb_Mesh,
) -> int {
	if source == nil || !source.ready do return -1
	cache_slot := int((uintptr(source) >> 4) % VK_WORLD_MESH_CACHE_CAPACITY)
	cache_insert := -1
	for probe in 0 ..< VK_WORLD_MESH_CACHE_CAPACITY {
		slot := (cache_slot + probe) % VK_WORLD_MESH_CACHE_CAPACITY
		cached := scene.mesh_cache_sources[slot]
		if cached == source do return scene.mesh_cache_indices[slot]
		if cached == nil {cache_insert = slot; break}
	}
	// This is only reachable for a scene restored from an older/incomplete cache
	// or if the table is genuinely full. It is not part of the steady frame path.
	for mesh, i in scene.meshes do if mesh.source == source {if cache_insert >= 0 {scene.mesh_cache_sources[cache_insert] = source; scene.mesh_cache_indices[cache_insert] = i}; return i}
	mesh := Vk_World_Mesh {
		source = source,
	}; vertices := make(
		[]Vk_World_Vertex,
		len(source.vertices),
		context.temp_allocator,
	); for &vertex, i in vertices {j := Glb_Joints{}; w := Vec4{1, 0, 0, 0}; if i < len(source.joints) do j = source.joints[i]; if i < len(source.weights) do w = source.weights[i]; vertex = {source.vertices[i], source.texcoords[i], j, w}}; if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(len(vertices) * size_of(Vk_World_Vertex)), {.VERTEX_BUFFER}, &mesh.vertices) do return -1; if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(len(source.indices) * size_of(u32)), {.INDEX_BUFFER}, &mesh.indices) {engine.vk_destroy_buffer(ctx, &mesh.vertices); return -1}; mem.copy_non_overlapping(mesh.vertices.mapped, raw_data(vertices), len(vertices) * size_of(Vk_World_Vertex)); mem.copy_non_overlapping(mesh.indices.mapped, raw_data(source.indices[:]), len(source.indices) * size_of(u32)); mesh.images = make([dynamic]Vk_Ui_Image, 0, len(source.textures) * 2); mesh.sets = make([dynamic]vk.DescriptorSet, 0, len(source.primitives))
	srgb_images := make(
		[]Vk_Ui_Image,
		len(source.textures),
		context.temp_allocator,
	); linear_images := make([]Vk_Ui_Image, len(source.textures), context.temp_allocator); srgb_needed := make([]bool, len(source.textures), context.temp_allocator); linear_needed := make([]bool, len(source.textures), context.temp_allocator)
	for primitive, primitive_index in source.primitives {if primitive.texture >= 0 && primitive.texture < len(srgb_needed) do srgb_needed[primitive.texture] = true; normal_index := primitive_index < len(source.normal_textures) ? source.normal_textures[primitive_index] : -1; roughness_index := primitive_index < len(source.roughness_textures) ? source.roughness_textures[primitive_index] : -1; if normal_index >= 0 && normal_index < len(linear_needed) do linear_needed[normal_index] = true; if roughness_index >= 0 && roughness_index < len(linear_needed) do linear_needed[roughness_index] = true}
	for texture, i in source.textures {if len(texture.pixels) == 0 do continue; if srgb_needed[i] && vk_world_image_upload(ctx, texture.pixels[:], texture.width, texture.height, &srgb_images[i]) do append(&mesh.images, srgb_images[i]); if linear_needed[i] && vk_world_linear_image_upload(ctx, texture.pixels[:], texture.width, texture.height, &linear_images[i]) do append(&mesh.images, linear_images[i])}
	for primitive, primitive_index in source.primitives {base := &scene.white; normal := &scene.flat_normal; roughness := &scene.white; normal_index := primitive_index < len(source.normal_textures) ? source.normal_textures[primitive_index] : -1; roughness_index := primitive_index < len(source.roughness_textures) ? source.roughness_textures[primitive_index] : -1; if primitive.texture >= 0 && primitive.texture < len(srgb_images) && srgb_images[primitive.texture].view != vk.ImageView(0) do base = &srgb_images[primitive.texture]; if normal_index >= 0 && normal_index < len(linear_images) && linear_images[normal_index].view != vk.ImageView(0) do normal = &linear_images[normal_index]; if roughness_index >= 0 && roughness_index < len(linear_images) && linear_images[roughness_index].view != vk.ImageView(0) do roughness = &linear_images[roughness_index]; for frame_index in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {set, ok := vk_world_descriptor(scene, ctx, base, normal, roughness, frame_index); if !ok {vk_world_mesh_destroy(&mesh, ctx); return -1}; append(&mesh.sets, set)}}; append(&scene.meshes, mesh); index := len(scene.meshes) - 1; if cache_insert >= 0 {scene.mesh_cache_sources[cache_insert] = source; scene.mesh_cache_indices[cache_insert] = index}; return index
}

// Generated editor meshes keep stable source addresses while their contents
// change after transactions. Refresh their buffers in place so draw indices
// and descriptors remain valid without consuming more descriptor-pool entries.
vk_world_refresh_mesh :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	source: ^Glb_Mesh,
) -> bool {
	index := -1; for mesh, i in scene.meshes do if mesh.source == source {index = i; break}; if index < 0 do return true; if source == nil || !source.ready do return false
	mesh := &scene.meshes[index]; vertices := make([]Vk_World_Vertex, len(source.vertices), context.temp_allocator); for &vertex, i in vertices {j := Glb_Joints{}; w := Vec4{1, 0, 0, 0}; if i < len(source.joints) do j = source.joints[i]; if i < len(source.weights) do w = source.weights[i]; vertex = {source.vertices[i], source.texcoords[i], j, w}}
	vertex_size := vk.DeviceSize(
		len(vertices) * size_of(Vk_World_Vertex),
	); index_size := vk.DeviceSize(len(source.indices) * size_of(u32)); _ = vk.DeviceWaitIdle(ctx.device)
	if mesh.vertices.size !=
	   vertex_size {engine.vk_destroy_buffer(ctx, &mesh.vertices); if !engine.vk_create_host_buffer(ctx, vertex_size, {.VERTEX_BUFFER}, &mesh.vertices) do return false}
	if mesh.indices.size !=
	   index_size {engine.vk_destroy_buffer(ctx, &mesh.indices); if !engine.vk_create_host_buffer(ctx, index_size, {.INDEX_BUFFER}, &mesh.indices) do return false}
	mem.copy_non_overlapping(
		mesh.vertices.mapped,
		raw_data(vertices),
		int(vertex_size),
	); mem.copy_non_overlapping(mesh.indices.mapped, raw_data(source.indices[:]), int(index_size)); return true
}

vk_world_begin :: proc(scene: ^Vk_World_Scene) {clear(&scene.draws)}
vk_world_draw_capacity_available :: proc(draw_count: int) -> bool {return(
		draw_count >= 0 &&
		draw_count < VK_WORLD_DRAW_CAPACITY \
	)}
vk_world_append_draw :: proc(
	scene: ^Vk_World_Scene,
	draw: Vk_World_Draw,
) -> bool {if !vk_world_draw_capacity_available(len(scene.draws)) do return false; append(
		&scene.draws,
		draw,
	)
	return true}
vk_world_add :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	mesh: ^Glb_Mesh,
	x, z, height, yaw: f32,
	tint := [4]u8{255, 255, 255, 255},
	footprint := false,
	surface_kind := 0,
	base_y: f32 = 0,
	pitch: f32 = 0,
	roll: f32 = 0,
	shadow_only := false,
	no_shadow: bool = false,
) {if len(scene.draws) >= VK_WORLD_DRAW_CAPACITY do return; index := vk_world_register_mesh(
		scene,
		ctx,
		mesh,
	)
	if index >= 0 do _ = vk_world_append_draw(scene, Vk_World_Draw{mesh = index, x = x, z = z, height = height, yaw = yaw, pitch = pitch, roll = roll, base_y = base_y, tint = tint, scale_by_footprint = footprint, shadow_only = shadow_only, no_shadow = no_shadow, surface_kind = surface_kind, clip_a = -1, clip_b = -1})}
vk_world_add_centered :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	mesh: ^Glb_Mesh,
	x, z, center_y, height, yaw, pitch: f32,
	tint := [4]u8{255, 255, 255, 255},
	surface_kind := 0,
) {if len(scene.draws) >= VK_WORLD_DRAW_CAPACITY do return; index := vk_world_register_mesh(
		scene,
		ctx,
		mesh,
	)
	if index >= 0 do _ = vk_world_append_draw(scene, Vk_World_Draw{mesh = index, x = x, z = z, height = height, yaw = yaw, pitch = pitch, base_y = center_y, tint = tint, centered = true, surface_kind = surface_kind, clip_a = -1, clip_b = -1})}
vk_world_add_sized :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	mesh: ^Glb_Mesh,
	x, z, width, height, yaw: f32,
	tint := [4]u8{255, 255, 255, 255},
	surface_kind := 0,
	base_y: f32 = 0,
	no_shadow: bool = false,
	light_anchor: Vec2 = {},
	use_light_anchor: bool = false,
	light_group: u64 = 0,
) {if len(scene.draws) >= VK_WORLD_DRAW_CAPACITY do return; index := vk_world_register_mesh(
		scene,
		ctx,
		mesh,
	)
	if index >= 0 do _ = vk_world_append_draw(scene, Vk_World_Draw{mesh = index, x = x, z = z, width = width, height = height, yaw = yaw, base_y = base_y, tint = tint, surface_kind = surface_kind, no_shadow = no_shadow, light_x = light_anchor.x, light_z = light_anchor.y, light_group = light_group, use_light_anchor = use_light_anchor, clip_a = -1, clip_b = -1})}
vk_world_add_foliage :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	mesh: ^Glb_Mesh,
	x, z, height, yaw: f32,
	bark_tint, foliage_tint: [4]u8,
	base_y: f32 = 0,
	no_shadow: bool = false,
) {if len(scene.draws) >= VK_WORLD_DRAW_CAPACITY do return; index := vk_world_register_mesh(
		scene,
		ctx,
		mesh,
	)
	if index >= 0 do _ = vk_world_append_draw(scene, Vk_World_Draw{mesh = index, x = x, z = z, height = height, yaw = yaw, base_y = base_y, tint = {255, 255, 255, 255}, bark_tint = bark_tint, foliage_tint = foliage_tint, foliage_colors = true, no_shadow = no_shadow, clip_a = -1, clip_b = -1})}
vk_world_add_animated :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	mesh: ^Glb_Mesh,
	x, z, height, yaw: f32,
	tint: [4]u8,
	clip_a, clip_b: int,
	time_a, time_b, blend: f32,
	base_y: f32 = 0,
	surface_kind := 5,
	pitch: f32 = 0,
) {if len(scene.draws) >= VK_WORLD_DRAW_CAPACITY do return; index := vk_world_register_mesh(
		scene,
		ctx,
		mesh,
	)
	if index >= 0 do _ = vk_world_append_draw(scene, Vk_World_Draw{mesh = index, x = x, z = z, height = height, yaw = yaw, pitch = pitch, base_y = base_y, tint = tint, surface_kind = surface_kind, clip_a = clip_a, clip_b = clip_b, time_a = time_a, time_b = time_b, blend = blend})}

vk_world_write_palette :: proc(
	scene: ^Vk_World_Scene,
	mesh: ^Glb_Mesh,
	draw: ^Vk_World_Draw,
	slot, frame_index: int,
) -> bool {if slot < 0 || slot >= VK_WORLD_MAX_SKINNED_DRAWS || len(mesh.skin.joints) == 0 do return false
	pose_a := make([]Glb_TRS, len(mesh.nodes), context.temp_allocator)
	pose_b := make([]Glb_TRS, len(mesh.nodes), context.temp_allocator)
	pose := make([]Glb_TRS, len(mesh.nodes), context.temp_allocator)
	if !glb_sample_pose(mesh, draw.clip_a, draw.time_a, false, pose_a) do return false
	if draw.clip_b >= 0 && draw.blend > 0 {if !glb_sample_pose(mesh, draw.clip_b, draw.time_b, false, pose_b) do return false
		glb_blend_pose(pose_a, pose_b, clamp(draw.blend, 0, 1), pose)}
	else {copy(pose, pose_a)}
	palette := make([]Glb_Mat4, len(mesh.skin.joints), context.temp_allocator)
	if !glb_pose_palette(mesh, pose, palette) do return false
	destination :=
		uintptr(scene.palettes[frame_index].mapped) +
		uintptr(slot * GLB_MAX_JOINTS * size_of(Glb_Mat4))
	mem.copy_non_overlapping(
		rawptr(destination),
		raw_data(palette),
		len(palette) * size_of(Glb_Mat4),
	)
	return true}

// Palette slots belong to scene draws, not to a particular shadow light's
// filtered caster list. The mapped palette buffer is shared by every recorded
// shadow layer and the visible pass, so compacting slots after light culling
// makes a queued shadow draw read another character's final pose at submit.
vk_world_skin_slot :: proc(scene: ^Vk_World_Scene, draw_index: int) -> int {
	if draw_index < 0 || draw_index >= len(scene.draws) do return -1
	slot := 0
	for draw, i in scene.draws {
		if i >= draw_index do break
		mesh := &scene.meshes[draw.mesh]
		if len(mesh.source.skin.joints) > 0 do slot += 1
	}
	draw := &scene.draws[draw_index]
	mesh := &scene.meshes[draw.mesh]; if len(mesh.source.skin.joints) == 0 do return -1
	return slot
}

vk_shadow_draw_eligible :: proc(
	draw: ^Vk_World_Draw,
	local: bool,
	light_position: Vec3,
	light_range: f32,
	light_room: int,
) -> bool {
	receiver_only :=
		draw.surface_kind == 1 ||
		draw.surface_kind == 3 ||
		draw.surface_kind == 4 ||
		draw.surface_kind == 6 ||
		draw.surface_kind == 7 ||
		draw.surface_kind == 11 ||
		draw.surface_kind == 12 ||
		draw.surface_kind == 14 ||
		(draw.surface_kind == 16 &&
				!draw.shadow_only); if draw.no_shadow || receiver_only || (draw.tint[3] < 128 && !draw.shadow_only) || (local && draw.shadow_only) do return false
	if local {dx, dz := draw.x - light_position.x, draw.z - light_position.z; if dx * dx + dz * dz > (light_range + 2) * (light_range + 2) do return false; draw_room := vk_world_room_at({draw.x, draw.z}); if light_room >= 0 && draw_room != light_room && !world_line_clear(draw.x, draw.z, light_position.x, light_position.z) do return false}
	return true
}

vk_shadow_render_layer :: proc(
	scene: ^Vk_World_Scene,
	command: vk.CommandBuffer,
	image: ^Vk_Shadow_Image,
	layer, matrix_index, frame_index: int,
	local := false,
	light_position := Vec3{},
	light_range: f32 = 0,
	light_room := -1,
) {
	if layer < 0 || layer >= len(image.layer_views) do return; clear := vk.ClearValue {
		depthStencil = {depth = 1},
	}; attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = image.layer_views[layer],
		imageLayout = .DEPTH_ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .STORE,
		clearValue  = clear,
	}; rendering := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = {image.image.width, image.image.height}},
		layerCount = 1,
		pDepthAttachment = &attachment,
	}; vk.CmdBeginRendering(command, &rendering); viewport := vk.Viewport {
		width    = f32(image.image.width),
		height   = f32(image.image.height),
		minDepth = 0,
		maxDepth = 1,
	}; scissor := vk.Rect2D {
		extent = {image.image.width, image.image.height},
	}; vk.CmdSetViewport(
		command,
		0,
		1,
		&viewport,
	); vk.CmdSetScissor(command, 0, 1, &scissor); vk.CmdBindPipeline(command, .GRAPHICS, scene.shadows.pipeline); vk.CmdBindDescriptorSets(command, .GRAPHICS, scene.shadows.pipeline_layout, 0, 1, &scene.shadows.descriptors[frame_index], 0, nil)
	offset := vk.DeviceSize(
		0,
	); for &draw, draw_index in scene.draws {if !vk_shadow_draw_eligible(&draw, local, light_position, light_range, light_room) do continue; mesh := &scene.meshes[draw.mesh]; skinned := len(mesh.source.skin.joints) > 0; palette_slot := skinned ? vk_world_skin_slot(scene, draw_index) : -1; skin_offset := u32(max(palette_slot, 0) * GLB_MAX_JOINTS); if skinned {if palette_slot < 0 || !vk_world_write_palette(scene, mesh.source, &draw, palette_slot, frame_index) do continue}; vk.CmdBindVertexBuffers(command, 0, 1, &mesh.vertices.handle, &offset); vk.CmdBindIndexBuffer(command, mesh.indices.handle, 0, .UINT32); model := vk_world_model(mesh.source, draw.x, draw.z, draw.width, draw.height, draw.yaw, draw.pitch, draw.base_y, draw.scale_by_footprint, draw.centered, draw.roll); push := Vk_Shadow_Push{model, {skinned ? 1 : 0, skin_offset, u32(matrix_index), 0}}; vk.CmdPushConstants(command, scene.shadows.pipeline_layout, {.VERTEX}, 0, u32(size_of(push)), &push); for primitive in mesh.source.primitives do vk.CmdDrawIndexed(command, u32(primitive.count), 1, u32(primitive.first), 0, 0)}; vk.CmdEndRendering(command)
}

vk_world_shadow_record :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	command: vk.CommandBuffer,
	g: ^Game,
	frame_index: int,
) {
	if !scene.shadows.ready || len(scene.draws) == 0 do return; state := &scene.shadows; view := vk_world_view_pose(g); count := view.interior ? 1 : lighting_quality_directional_cascades(g.lighting_quality); state.cascade_count = count; state.splits = vk_shadow_practical_splits(count, .08, 120); focus := view.target; weather_strength := g.screen == .Exterior ? f32(1) : clamp(g.environment_blend, 0, 1); light_direction := world_key_light_direction(g.animation_time, weather_strength); resolution := f32(state.directional.image.width)
	for cascade in 0 ..< count {far := state.splits[cascade]; interior_radius := max(f32(max(level_document.width, level_document.height)) * .75, f32(24)); radius := view.interior ? interior_radius : max(far * .72, f32(5)); texel := radius * 2 / resolution; center := focus; center.x = f32(math.round(f64(center.x / texel))) * texel; center.z = f32(math.round(f64(center.z / texel))) * texel; eye := Vec3{center.x - light_direction.x * radius * 2, center.y - light_direction.y * radius * 2, center.z - light_direction.z * radius * 2}; state.matrices[cascade] = glb_mat4_multiply(vk_world_orthographic(-radius, radius, -radius, radius, .05, radius * 5), vk_world_look_at(eye, center, {0, 1, 0}))}
	runtime_lights := make(
		[dynamic]Vk_World_Runtime_Light,
		0,
		VK_WORLD_MAX_LIGHTS,
		context.temp_allocator,
	); sequence := 0; for light in level_document.lights {if light.story != level_document.active_story do continue; base_y := f32(0); if light.story >= 0 && light.story < len(level_document.stories) do base_y = level_document.stories[light.story].base_elevation; vk_world_runtime_light_insert(&runtime_lights, Vk_World_Runtime_Light{position = {light.position.x, base_y + light.elevation, light.position.y, light.range}, color = {f32(light.color[0]) / 255, f32(light.color[1]) / 255, f32(light.color[2]) / 255, light.intensity * .34}, params = {f32(light.kind), light.facing * f32(math.PI) / 180, f32(math.cos(f64(light.cone_angle * .5 * f32(math.PI) / 180))), 0}, room = vk_world_room_at(light.position), sequence = sequence}, focus); sequence += 1}; for object in level_document.objects {if object.story != level_document.active_story do continue; entry, found := catalog_object_entry(object.catalog_id); if !found || !entry.emits_light do continue; has_bound := false; for light in level_document.lights do if fmt.tprintf("light_%s", object.id) == light.id do has_bound = true; if has_bound do continue; base_y := object.elevation; if object.story >= 0 && object.story < len(level_document.stories) do base_y += level_document.stories[object.story].base_elevation; if level_terrain_supports_position(&level_document, object.position, object.story) do base_y += level_terrain_height(&level_document, object.position); vk_world_runtime_light_insert(&runtime_lights, Vk_World_Runtime_Light{position = {object.position.x, base_y + entry.light_height, object.position.y, entry.light_range}, color = {f32(entry.light_color[0]) / 255, f32(entry.light_color[1]) / 255, f32(entry.light_color[2]) / 255, entry.light_intensity * .34}, params = {f32(entry.light_kind), (object.rotation + entry.light_facing) * f32(math.PI) / 180, f32(math.cos(f64(entry.light_cone_angle * .5 * f32(math.PI) / 180))), 0}, room = vk_world_room_at(object.position), sequence = sequence}, focus); sequence += 1}
	if g.screen == .Exterior do vk_world_add_city_vehicle_lights(&runtime_lights, g, focus)
	for &source in state.point_sources do source = -1; for &source in state.spot_sources do source = -1; point_count, spot_count := 0, 0; point_limit := lighting_quality_point_shadow_slots(g.lighting_quality); spot_limit := lighting_quality_spot_shadow_slots(g.lighting_quality); face_budget := lighting_quality_shadow_face_budget(g.lighting_quality); faces_used := 0
	cube_directions := [6]Vec3 {
		{1, 0, 0},
		{-1, 0, 0},
		{0, 1, 0},
		{0, -1, 0},
		{0, 0, 1},
		{0, 0, -1},
	}; cube_ups := [6]Vec3{{0, -1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}, {0, -1, 0}, {0, -1, 0}}
	for light in runtime_lights {if light.params[0] < .5 &&
		   point_count < point_limit &&
		   faces_used + 6 <=
			   face_budget {slot := point_count; state.point_sources[slot] = light.sequence; position := Vec3{light.position[0], light.position[1], light.position[2]}; for face in 0 ..< 6 {matrix_index := 4 + slot * 6 + face; direction := cube_directions[face]; state.matrices[matrix_index] = glb_mat4_multiply(vk_world_perspective(math.PI / 2, 1, .08, max(light.position[3], .1)), vk_world_look_at(position, {position.x + direction.x, position.y + direction.y, position.z + direction.z}, cube_ups[face]))}; point_count += 1; faces_used += 6} else if light.params[0] > .5 && light.params[0] < 1.5 && spot_count < spot_limit && faces_used < face_budget {slot := spot_count; state.spot_sources[slot] = light.sequence; position := Vec3{light.position[0], light.position[1], light.position[2]}; direction := vk_world_normalize({f32(math.cos(f64(light.params[1]))), -.35, f32(math.sin(f64(light.params[1])))}); matrix_index := 28 + slot; cone := f32(math.acos(f64(clamp(light.params[2], -.99, .99)))) * 2; state.matrices[matrix_index] = glb_mat4_multiply(vk_world_perspective(max(cone, .15), 1, .08, max(light.position[3], .1)), vk_world_look_at(position, {position.x + direction.x, position.y + direction.y, position.z + direction.z}, {0, 1, 0})); spot_count += 1; faces_used += 1}}
	mem.copy_non_overlapping(
		state.matrix_buffers[frame_index].mapped,
		raw_data(state.matrices[:]),
		len(state.matrices) * size_of(Glb_Mat4),
	); engine.vk_cmd_image_barrier2(ctx, command, state.directional.image.image, {.TOP_OF_PIPE, .FRAGMENT_SHADER}, {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}, {.SHADER_READ}, {.DEPTH_STENCIL_ATTACHMENT_WRITE}, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL, {.DEPTH}); for cascade in 0 ..< count do vk_shadow_render_layer(scene, command, &state.directional, cascade, cascade, frame_index); engine.vk_cmd_image_barrier2(ctx, command, state.directional.image.image, {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}, {.FRAGMENT_SHADER}, {.DEPTH_STENCIL_ATTACHMENT_WRITE}, {.SHADER_READ}, .DEPTH_ATTACHMENT_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL, {.DEPTH})
	if point_count >
	   0 {engine.vk_cmd_image_barrier2(ctx, command, state.points.image.image, {.TOP_OF_PIPE, .FRAGMENT_SHADER}, {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}, {.SHADER_READ}, {.DEPTH_STENCIL_ATTACHMENT_WRITE}, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL, {.DEPTH}); for slot in 0 ..< point_count {source := state.point_sources[slot]; for light in runtime_lights do if light.sequence == source {position := Vec3{light.position[0], light.position[1], light.position[2]}; for face in 0 ..< 6 do vk_shadow_render_layer(scene, command, &state.points, slot * 6 + face, 4 + slot * 6 + face, frame_index, true, position, light.position[3], light.room); break}}; engine.vk_cmd_image_barrier2(ctx, command, state.points.image.image, {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}, {.FRAGMENT_SHADER}, {.DEPTH_STENCIL_ATTACHMENT_WRITE}, {.SHADER_READ}, .DEPTH_ATTACHMENT_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL, {.DEPTH})}
	if spot_count >
	   0 {engine.vk_cmd_image_barrier2(ctx, command, state.spots.image.image, {.TOP_OF_PIPE, .FRAGMENT_SHADER}, {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}, {.SHADER_READ}, {.DEPTH_STENCIL_ATTACHMENT_WRITE}, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL, {.DEPTH}); for slot in 0 ..< spot_count {source := state.spot_sources[slot]; for light in runtime_lights do if light.sequence == source {vk_shadow_render_layer(scene, command, &state.spots, slot, 28 + slot, frame_index, true, {light.position[0], light.position[1], light.position[2]}, light.position[3], light.room); break}}; engine.vk_cmd_image_barrier2(ctx, command, state.spots.image.image, {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}, {.FRAGMENT_SHADER}, {.DEPTH_STENCIL_ATTACHMENT_WRITE}, {.SHADER_READ}, .DEPTH_ATTACHMENT_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL, {.DEPTH})}
}

vk_world_draw_primitive_batchable :: proc(
	mesh: ^Vk_World_Mesh,
	draw: ^Vk_World_Draw,
	primitive_index: int,
) -> bool {
	if draw.shadow_only || len(mesh.source.skin.joints) > 0 || draw.tint[3] < 255 do return false
	alpha_mode :=
		primitive_index < len(mesh.source.alpha_modes) ? mesh.source.alpha_modes[primitive_index] : 0
	return alpha_mode != 2
}

vk_world_texture_flags :: proc(
	mesh: ^Vk_World_Mesh,
	primitive_index, normal_index, roughness_index: int,
) -> int {
	primitive := mesh.source.primitives[primitive_index]
	material_name :=
		primitive_index < len(mesh.source.material_names) ? mesh.source.material_names[primitive_index] : ""; thin_wall := glb_thin_wall_material_role(material_name) > 0
	return(
		(primitive.texture >= 0 ? 1 : 0) +
		(normal_index >= 0 ? 2 : 0) +
		(roughness_index >= 0 ? 4 : 0) +
		(thin_wall ? 8 : 0) \
	)
}

vk_world_draw_push :: proc(
	scene: ^Vk_World_Scene,
	mesh: ^Vk_World_Mesh,
	draw: ^Vk_World_Draw,
	draw_index, primitive_index: int,
	skinned: bool = false,
	skin_offset: u32 = 0,
) -> Vk_World_Push {
	primitive :=
		mesh.source.primitives[primitive_index]; model := vk_world_model(mesh.source, draw.x, draw.z, draw.width, draw.height, draw.yaw, draw.pitch, draw.base_y, draw.scale_by_footprint, draw.centered, draw.roll); primitive_tint := [4]f32{f32(draw.tint[0]) / 255, f32(draw.tint[1]) / 255, f32(draw.tint[2]) / 255, f32(draw.tint[3]) / 255}; material_name := primitive_index < len(mesh.source.material_names) ? mesh.source.material_names[primitive_index] : ""; role := glb_foliage_material_role(material_name); if draw.foliage_colors && role == 1 do primitive_tint = {f32(draw.bark_tint[0]) / 255, f32(draw.bark_tint[1]) / 255, f32(draw.bark_tint[2]) / 255, f32(draw.bark_tint[3]) / 255}; if draw.foliage_colors && role == 2 do primitive_tint = {f32(draw.foliage_tint[0]) / 255, f32(draw.foliage_tint[1]) / 255, f32(draw.foliage_tint[2]) / 255, f32(draw.foliage_tint[3]) / 255}; alpha_mode := primitive_index < len(mesh.source.alpha_modes) ? mesh.source.alpha_modes[primitive_index] : 0; alpha_cutoff := primitive_index < len(mesh.source.alpha_cutoffs) ? mesh.source.alpha_cutoffs[primitive_index] : f32(.5); if draw.foliage_colors && alpha_mode == 2 {alpha_mode = 1; alpha_cutoff = .5}; alpha_state := f32(alpha_mode) + alpha_cutoff * .1; normal_index := primitive_index < len(mesh.source.normal_textures) ? mesh.source.normal_textures[primitive_index] : -1; roughness_index := primitive_index < len(mesh.source.roughness_textures) ? mesh.source.roughness_textures[primitive_index] : -1; texture_flags := vk_world_texture_flags(mesh, primitive_index, normal_index, roughness_index); pbr := [4]f32{0, .72, 1, 0}; authored_pbr := primitive_index < len(mesh.source.roughness_factors); if primitive_index < len(mesh.source.metallic_factors) do pbr.x = mesh.source.metallic_factors[primitive_index]; if authored_pbr do pbr.y = mesh.source.roughness_factors[primitive_index]; if primitive_index < len(mesh.source.normal_scales) do pbr.z = mesh.source.normal_scales[primitive_index]; pbr.w = authored_pbr ? 1 : 0; return {model, primitive_tint * primitive.base_color, {f32(texture_flags), f32(draw.surface_kind), f32(scene.draw_lights[draw_index].meta[1]), alpha_state}, pbr, {skinned ? 1 : 0, skin_offset, u32(draw_index), 0}}
}

vk_world_record :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	command: vk.CommandBuffer,
	extent: vk.Extent2D,
	g: ^Game,
	frame_index: int,
) {
	if len(scene.draws) == 0 do return; if scene.depth.width != extent.width || scene.depth.height != extent.height {_ = vk.DeviceWaitIdle(ctx.device); vk_ui_image_destroy(&scene.depth, ctx); if !vk_world_depth_create(ctx, extent.width, extent.height, &scene.depth) do return}
	scene.profile_lights_ms = 0; scene.profile_batches_ms = 0; scene.profile_unbatched_ms = 0; lights_started := time.tick_now()
	view := vk_world_view_pose(
		g,
	); eye, target, up := view.eye, view.target, view.up; interior, baking := view.interior, view.baking; projection_aspect := baking ? f32(1) : f32(extent.width) / f32(max(extent.height, 1)); field_of_view := f32(math.PI / 3); if g.screen == .Exterior && g.driving_vehicle >= 0 && g.driving_vehicle < len(g.vehicles) do field_of_view = vehicle_camera_field_of_view(g.vehicles[g.driving_vehicle]); weather_strength := g.screen == .Exterior ? f32(1) : clamp(g.environment_blend, 0, 1); if baking do weather_strength = 0; interior_amount := baking ? f32(1) : 1 - weather_strength; camera := Vk_World_Camera {
		view_projection = glb_mat4_multiply(
			vk_world_perspective(field_of_view, projection_aspect, .08, 140),
			vk_world_look_at(eye, target, up),
		),
		camera_position = {eye.x, eye.y, eye.z, 1},
		lighting        = {interior_amount, 1 - interior_amount * .18, 0, 0},
		atmosphere      = {
			weather_strength,
			g.animation_time,
			world_time_of_day(g.animation_time),
			0,
		},
	}; for shadow_matrix, index in scene.shadows.matrices[:4] do camera.directional_shadow_matrices[index] = shadow_matrix; camera.directional_shadow_splits = scene.shadows.splits; camera.directional_shadow_params = {f32(scene.shadows.cascade_count), .0007, .003, 1 / f32(max(scene.shadows.directional.image.width, 1))}
	runtime_lights := make(
		[dynamic]Vk_World_Runtime_Light,
		0,
		VK_WORLD_MAX_LIGHTS,
		context.temp_allocator,
	); sequence := 0
	// The character studio is a diagnostic stage, so it uses a stable neutral
	// review rig instead of inheriting the active level's night lighting. A broad
	// warm key and cool fill for each model keep skin, clothing, and silhouettes
	// readable while retaining enough directionality to reveal deformation.
	if g.character_studio {
		studio_x := [4]f32{-3, -1, 1, 3}
		for x in studio_x {
			append(
				&runtime_lights,
				Vk_World_Runtime_Light {
					position = {x, 3.8, 2.6, 7.5},
					color = {1.0, .91, .78, 1.65},
					params = {2, 0, 0, 0},
					room = vk_world_room_at({x, 0}),
					sequence = sequence,
				},
			); sequence += 1
		}
		append(
			&runtime_lights,
			Vk_World_Runtime_Light {
				position = {0, 2.7, -3.2, 9},
				color = {.48, .67, 1.0, .82},
				params = {2, 0, 0, 0},
				room = vk_world_room_at({0, 0}),
				sequence = sequence,
			},
		); sequence += 1
	}
	if interior {for light in level_document.lights {if light.story != level_document.active_story do continue; base_y := f32(0); if light.story >= 0 && light.story < len(level_document.stories) do base_y = level_document.stories[light.story].base_elevation; light_level := f32(1); for object in level_document.objects {if fmt.tprintf("light_%s", object.id) == light.id {interactive_index := runtime_interactive_index(g, object.id); if interactive_index >= 0 do light_level = g.interactives[interactive_index].light_level; break}}; runtime := Vk_World_Runtime_Light {
				position = {
					light.position.x,
					base_y + light.elevation,
					light.position.y,
					light.range,
				},
				color    = {
					f32(light.color[0]) / 255,
					f32(light.color[1]) / 255,
					f32(light.color[2]) / 255,
					light.intensity * .34 * light_level,
				},
				params   = {
					f32(light.kind),
					light.facing * f32(math.PI) / 180,
					f32(math.cos(f64(light.cone_angle * .5 * f32(math.PI) / 180))),
					0,
				},
				room     = vk_world_room_at(light.position),
				sequence = sequence,
			}; vk_world_runtime_light_insert(&runtime_lights, runtime, eye); sequence += 1}}
	if interior {for object in level_document.objects {if object.story != level_document.active_story do continue; entry, found := catalog_object_entry(object.catalog_id); if !found || !entry.emits_light do continue; has_bound_light := false; for light in level_document.lights do if fmt.tprintf("light_%s", object.id) == light.id do has_bound_light = true; if has_bound_light do continue; base_y := object.elevation; if object.story >= 0 && object.story < len(level_document.stories) do base_y += level_document.stories[object.story].base_elevation; if level_terrain_supports_position(&level_document, object.position, object.story) do base_y += level_terrain_height(&level_document, object.position); light_level := f32(1); interactive_index := runtime_interactive_index(g, object.id); if interactive_index >= 0 do light_level = g.interactives[interactive_index].light_level; runtime := Vk_World_Runtime_Light {
				position = {
					object.position.x,
					base_y + entry.light_height,
					object.position.y,
					entry.light_range,
				},
				color    = {
					f32(entry.light_color[0]) / 255,
					f32(entry.light_color[1]) / 255,
					f32(entry.light_color[2]) / 255,
					entry.light_intensity * .34 * light_level,
				},
				params   = {
					f32(entry.light_kind),
					(object.rotation + entry.light_facing) * f32(math.PI) / 180,
					f32(math.cos(f64(entry.light_cone_angle * .5 * f32(math.PI) / 180))),
					0,
				},
				room     = vk_world_room_at(object.position),
				sequence = sequence,
			}; vk_world_runtime_light_insert(&runtime_lights, runtime, eye); sequence += 1}}
	if g.screen == .Exterior do vk_world_add_city_vehicle_lights(&runtime_lights, g, eye)
	for light, slot in runtime_lights {camera.light_positions[slot] = light.position
		camera.light_colors[slot] = light.color
		camera.light_params[slot] = light.params
		for source, shadow_slot in scene.shadows.point_sources do if source == light.sequence do camera.light_shadow_meta[slot] = {1, f32(shadow_slot), light.position[3], .003}
		for source, shadow_slot in scene.shadows.spot_sources do if source == light.sequence do camera.light_shadow_meta[slot] = {2, f32(shadow_slot), light.position[3], .002}}; for matrix_index in 0 ..< 24 do camera.point_shadow_matrices[matrix_index] = scene.shadows.matrices[4 + matrix_index]; for shadow_slot in 0 ..< 10 do camera.local_shadow_matrices[shadow_slot] = scene.shadows.matrices[28 + shadow_slot]; camera.lighting[2] = f32(len(runtime_lights)); vk_world_build_draw_light_lists(scene, runtime_lights[:], g.lighting_quality, frame_index)
	scene.profile_lights_ms =
		time.duration_seconds(time.tick_diff(lights_started, time.tick_now())) *
		1000; mem.copy_non_overlapping(scene.cameras[frame_index].mapped, &camera, size_of(camera)); viewport := vk.Viewport {
		width    = f32(extent.width),
		height   = f32(extent.height),
		minDepth = 0,
		maxDepth = 1,
	}; scissor := vk.Rect2D {
		extent = extent,
	}; vk.CmdSetViewport(
		command,
		0,
		1,
		&viewport,
	); vk.CmdSetScissor(command, 0, 1, &scissor); vk.CmdBindPipeline(command, .GRAPHICS, scene.pipeline); batches_started := time.tick_now()
	// Opaque static props are order-independent. Preserve their per-object data
	// in a storage buffer and collapse each repeated mesh primitive to one draw.
	mesh_offsets := make(
		[]int,
		len(scene.meshes) + 1,
		context.temp_allocator,
	); draw_order := make([]int, len(scene.draws), context.temp_allocator); for draw in scene.draws do mesh_offsets[draw.mesh + 1] += 1; for i in 1 ..< len(mesh_offsets) do mesh_offsets[i] += mesh_offsets[i - 1]; cursors := make([]int, len(scene.meshes), context.temp_allocator); copy(cursors, mesh_offsets[:len(scene.meshes)]); for draw, draw_index in scene.draws {draw_order[cursors[draw.mesh]] = draw_index; cursors[draw.mesh] += 1}
	instance_data := transmute([^]Vk_World_Push)(scene.instance_buffer.mapped); instance_start := frame_index * VK_WORLD_INSTANCES_PER_FRAME; instance_count := instance_start; vertex_offset := vk.DeviceSize(0)
	for &mesh, mesh_index in scene.meshes {
		if len(mesh.source.skin.joints) > 0 do continue
		vk.CmdBindVertexBuffers(
			command,
			0,
			1,
			&mesh.vertices.handle,
			&vertex_offset,
		); vk.CmdBindIndexBuffer(command, mesh.indices.handle, 0, .UINT32)
		for primitive, primitive_index in mesh.source.primitives {
			batch_start := instance_count
			for order_index in mesh_offsets[mesh_index] ..< mesh_offsets[mesh_index + 1] {
				draw_index := draw_order[order_index]; draw := &scene.draws[draw_index]
				if !vk_world_draw_primitive_batchable(&mesh, draw, primitive_index) || instance_count >= instance_start + VK_WORLD_INSTANCES_PER_FRAME do continue
				instance_data[instance_count] = vk_world_draw_push(
					scene,
					&mesh,
					draw,
					draw_index,
					primitive_index,
				); instance_count += 1
			}
			batch_count := instance_count - batch_start; if batch_count == 0 do continue
			set_index :=
				primitive_index * engine.MAX_FRAMES_IN_FLIGHT +
				frame_index; if set_index < 0 || set_index >= len(mesh.sets) do set_index = frame_index; set := mesh.sets[set_index]; vk.CmdBindDescriptorSets(command, .GRAPHICS, scene.pipeline_layout, 0, 1, &set, 0, nil); push := Vk_World_Push{}; push.skin = {0, 0, u32(batch_start), 1}; vk.CmdPushConstants(command, scene.pipeline_layout, {.VERTEX, .FRAGMENT}, 0, u32(size_of(push)), &push); vk.CmdDrawIndexed(command, u32(primitive.count), u32(batch_count), u32(primitive.first), 0, 0)
		}
	}
	scene.profile_batches_ms =
		time.duration_seconds(time.tick_diff(batches_started, time.tick_now())) *
		1000; unbatched_started := time.tick_now()
	for &draw, draw_index in scene.draws {if draw.shadow_only do continue; mesh := &scene.meshes[draw.mesh]; skinned := len(mesh.source.skin.joints) > 0; palette_slot := skinned ? vk_world_skin_slot(scene, draw_index) : -1; if skinned && (palette_slot < 0 || !vk_world_write_palette(scene, mesh.source, &draw, palette_slot, frame_index)) do continue; skin_offset := u32(max(palette_slot, 0) * GLB_MAX_JOINTS); offset := vk.DeviceSize(0); vk.CmdBindVertexBuffers(command, 0, 1, &mesh.vertices.handle, &offset); vk.CmdBindIndexBuffer(command, mesh.indices.handle, 0, .UINT32); model := vk_world_model(mesh.source, draw.x, draw.z, draw.width, draw.height, draw.yaw, draw.pitch, draw.base_y, draw.scale_by_footprint, draw.centered, draw.roll); tint := [4]f32{f32(draw.tint[0]) / 255, f32(draw.tint[1]) / 255, f32(draw.tint[2]) / 255, f32(draw.tint[3]) / 255}; light_selector := f32(scene.draw_lights[draw_index].meta[1]); for primitive, primitive_index in mesh.source.primitives {if vk_world_draw_primitive_batchable(mesh, &draw, primitive_index) do continue; primitive_tint := tint; material_name := primitive_index < len(mesh.source.material_names) ? mesh.source.material_names[primitive_index] : ""; role := glb_foliage_material_role(material_name); if draw.foliage_colors && role == 1 do primitive_tint = {f32(draw.bark_tint[0]) / 255, f32(draw.bark_tint[1]) / 255, f32(draw.bark_tint[2]) / 255, f32(draw.bark_tint[3]) / 255}; if draw.foliage_colors && role == 2 do primitive_tint = {f32(draw.foliage_tint[0]) / 255, f32(draw.foliage_tint[1]) / 255, f32(draw.foliage_tint[2]) / 255, f32(draw.foliage_tint[3]) / 255}; set_index := primitive_index * engine.MAX_FRAMES_IN_FLIGHT + frame_index; if set_index < 0 || set_index >= len(mesh.sets) do set_index = frame_index; set := mesh.sets[set_index]; vk.CmdBindDescriptorSets(command, .GRAPHICS, scene.pipeline_layout, 0, 1, &set, 0, nil); alpha_mode := primitive_index < len(mesh.source.alpha_modes) ? mesh.source.alpha_modes[primitive_index] : 0; alpha_cutoff := primitive_index < len(mesh.source.alpha_cutoffs) ? mesh.source.alpha_cutoffs[primitive_index] : f32(.5); if draw.foliage_colors && alpha_mode == 2 {alpha_mode = 1; alpha_cutoff = .5}; alpha_state := f32(alpha_mode) + alpha_cutoff * .1; normal_index := primitive_index < len(mesh.source.normal_textures) ? mesh.source.normal_textures[primitive_index] : -1; roughness_index := primitive_index < len(mesh.source.roughness_textures) ? mesh.source.roughness_textures[primitive_index] : -1; texture_flags := vk_world_texture_flags(mesh, primitive_index, normal_index, roughness_index); pbr := [4]f32{0, .72, 1, 0}; authored_pbr := primitive_index < len(mesh.source.roughness_factors); if primitive_index < len(mesh.source.metallic_factors) do pbr.x = mesh.source.metallic_factors[primitive_index]; if authored_pbr do pbr.y = mesh.source.roughness_factors[primitive_index]; if primitive_index < len(mesh.source.normal_scales) do pbr.z = mesh.source.normal_scales[primitive_index]; pbr.w = authored_pbr ? 1 : 0; push := Vk_World_Push{model, primitive_tint * primitive.base_color, {f32(texture_flags), f32(draw.surface_kind), light_selector, alpha_state}, pbr, {skinned ? 1 : 0, skin_offset, u32(draw_index), 0}}; vk.CmdPushConstants(command, scene.pipeline_layout, {.VERTEX, .FRAGMENT}, 0, u32(size_of(push)), &push); vk.CmdDrawIndexed(command, u32(primitive.count), 1, u32(primitive.first), 0, 0)}}
	scene.profile_unbatched_ms =
		time.duration_seconds(time.tick_diff(unbatched_started, time.tick_now())) * 1000
}

vk_world_build_city :: proc(scene: ^Vk_World_Scene, ctx: ^engine.Vk_Context, g: ^Game) {
	city_center_x, city_center_z := CITY_WORLD_WIDTH * .5, CITY_WORLD_HEIGHT * .5
	// As with an interior cutaway, authored ground ends over a distinct negative-
	// space layer instead of visually promising terrain past an invisible wall.
	// The interior background shader returns a fully composed color and is only
	// safe beneath the compact dollhouse. Keep the city's much larger border on
	// the ordinary depth-tested terrain path so it can never paint over geometry.
	vk_world_add_sized(
		scene,
		ctx,
		&city_background_mesh,
		city_center_x,
		city_center_z,
		CITY_WORLD_WIDTH + city_world(240),
		.001,
		0,
		{19, 77, 87, 255},
		7,
		-.08,
	)
	// Preserve the authored terrain mesh's Y range. The generic sized-floor path
	// intentionally flattens a mesh to its requested height.
	vk_world_add(
		scene,
		ctx,
		&city_ground_mesh,
		city_center_x,
		city_center_z,
		city_ground_mesh.max.y - city_ground_mesh.min.y,
		0,
		{92, 142, 96, 255},
		false,
		7,
		-.045,
	)
	// Road vertices are baked against the same height function as the ground,
	// preserving markings and curbs while removing rigid-tile steps.
	for &road in city_bent_road_meshes {if !road.ready do continue
		cx, cz := (road.min.x + road.max.x) * .5, (road.min.z + road.max.z) * .5
		vk_world_add(
			scene,
			ctx,
			&road,
			cx,
			cz,
			road.max.y - road.min.y,
			0,
			{255, 255, 255, 255},
			false,
			7,
			road.min.y + .01,
		)}
	for by in 0 ..< CITY_HEIGHT /
		CITY_BLOCK {for bx in 0 ..< CITY_WIDTH / CITY_BLOCK {layout_x, layout_z, place := city_building_site(bx, by); wx, wz := city_world(layout_x), city_world(layout_z); if !place || !city_render_chunk_visible(g, wx, wz, CITY_BUILDING_DRAW_DISTANCE, CITY_DRIVING_BEHIND_DISTANCE) do continue; mesh_index, height, yaw, tint := city_building_style(bx, by, layout_x); vk_world_add(scene, ctx, &city_meshes[mesh_index], wx, wz, city_world(height), yaw, tint, false, 8, city_elevation(wx, wz))}}
	payload := mystery_game_payload(
		g,
	); quest_index := payload == nil ? -1 : city_landmark_index(g, payload.city_destination); if quest_index >= 0 {quest, ok := city_landmark_at(g, quest_index); if ok && city_quest_marker_visible(g, quest) {dx, dz := quest.x - g.city_x, quest.y - g.city_y; if dx * dx + dz * dz <= CITY_DYNAMIC_DRAW_DISTANCE * CITY_DYNAMIC_DRAW_DISTANCE {center := Vec2{quest.x, quest.y}; if !city_quest_marker_built || city_quest_marker_center != center {city_quest_marker_mesh = procedural_city_quest_marker_mesh(center, 3.2); city_quest_marker_center = center; city_quest_marker_built = true; _ = vk_world_refresh_mesh(scene, ctx, &city_quest_marker_mesh)}; marker_base := city_surface_elevation(quest.x, quest.y) + city_quest_marker_mesh.min.y + .035; vk_world_add(scene, ctx, &city_quest_marker_mesh, quest.x, quest.y, 6.4, 0, {255, 202, 72, 205}, true, 7, marker_base)}}}
	for mark in g.vehicle_skid_marks {if !mark.active || mark.age >= VEHICLE_SKID_LIFETIME do continue; fade := 1 - mark.age / VEHICLE_SKID_LIFETIME; alpha := u8(clamp(mark.strength * fade * 125, 0, 125)); vk_world_add(scene, ctx, &vehicle_skid_mesh, mark.position.x, mark.position.y, .62, mark.heading, {8, 10, 12, alpha}, true, 7, city_elevation(mark.position.x, mark.position.y) + .022)}
	for prop in g.city_furniture {dx, dz := prop.x - g.city_x, prop.y - g.city_y; if dx * dx + dz * dz > CITY_DYNAMIC_DRAW_DISTANCE * CITY_DYNAMIC_DRAW_DISTANCE do continue; template := city_furniture_template(prop.kind); vk_world_add(scene, ctx, &city_furniture_meshes[int(prop.kind)], prop.x, prop.y, template.height, prop.heading, template.tint, false, 9, city_elevation(prop.x, prop.y), prop.roll, prop.pitch)}
	// Kenney's car meshes face model-space -Z. Rotate that axis onto the
	// simulation heading (+X at zero) without reversing the visible vehicle.
	for car, i in g.vehicles {dx, dz := car.x - g.city_x, car.y - g.city_y; if dx * dx + dz * dz > CITY_DYNAMIC_DRAW_DISTANCE * CITY_DYNAMIC_DRAW_DISTANCE do continue; rough_roll, rough_pitch := vehicle_rough_body_pose(car); vk_world_add(scene, ctx, &city_car_meshes[i], car.x, car.y, 1.05, car.heading - f32(math.PI / 2), {255, 255, 255, 255}, false, 10, city_elevation(car.x, car.y), car.body_roll + rough_roll, car.body_pitch + rough_pitch)}
	if g.driving_vehicle <
	   0 {player := &g.player_animation; vk_world_add_animated(scene, ctx, &character_meshes[0], g.city_x, g.city_y, 1.65, character_render_yaw(g.city_angle), {255, 255, 255, 255}, player.current, player.transitioning ? player.next : -1, player.time, player.next_time, player.transitioning ? player.transition : 0, city_surface_elevation(g.city_x, g.city_y), 9)}
}

vk_world_build_catalog_thumbnail :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	g: ^Game,
) {
	if g.catalog_bake_index < 0 || g.catalog_bake_index >= len(editor_catalog.entries) do return
	entry :=
		editor_catalog.entries[g.catalog_bake_index]; mesh, ok := catalog_object_mesh(entry.id); if !ok do return; span_x := mesh.max.x - mesh.min.x; span_y := mesh.max.y - mesh.min.y; span_z := mesh.max.z - mesh.min.z
	// Normalize by the complete bounds, not just height. This keeps broad tables and
	// tall bookcases at the same visual scale without catalog-specific camera hacks.
	max_span := max(span_x, max(span_y, span_z)); if max_span <= 0 do max_span = 1
	normalized_height := 2.5 * span_y / max_span
	vk_world_add(
		scene,
		ctx,
		&catalog_thumbnail_floor,
		0,
		0,
		12,
		0,
		{226, 220, 203, 255},
		true,
		0,
		-.035,
	)
	vk_world_add(
		scene,
		ctx,
		mesh,
		0,
		0,
		normalized_height,
		-f32(math.PI) / 8,
		{255, 255, 255, 255},
		false,
		0,
		0,
	)
}
