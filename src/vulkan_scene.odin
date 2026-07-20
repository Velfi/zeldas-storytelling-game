package main

import "core:math"
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
