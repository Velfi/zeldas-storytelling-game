package main

import vk "vendor:vulkan"
import engine "zelda_engine:engine"
import resources "zelda_engine:render_resources"

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
