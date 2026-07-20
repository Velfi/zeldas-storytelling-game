package main

import "core:fmt"
import "core:image"
import _ "core:image/png"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"
import sdl "vendor:sdl3"
import vk "vendor:vulkan"
import engine "zelda_engine:engine"
import resources "zelda_engine:render_resources"
import ui "zelda_engine:ui"

VK_UI_VERTEX_CAPACITY :: 65536
VK_UI_INDEX_CAPACITY :: VK_UI_VERTEX_CAPACITY / 4 * 6
VK_UI_TEXTURE_CAPACITY :: 96

Anti_Aliasing_Mode :: enum {
	None,
	MSAA_2X,
	MSAA_4X,
	FXAA,
}
Lighting_Quality :: enum {
	Low,
	Medium,
	High,
	Ultra,
}

lighting_quality_light_count :: proc(quality: Lighting_Quality) -> int {values := [4]int {
		1,
		2,
		4,
		8,
	}
	return values[int(quality)]}
lighting_quality_shadow_casters :: proc(quality: Lighting_Quality) -> int {values := [4]int {
		8,
		12,
		16,
		16,
	}
	return values[int(quality)]}
lighting_quality_shadow_candidates :: proc(quality: Lighting_Quality) -> int {values := [4]int {
		0,
		1,
		2,
		4,
	}
	return values[int(quality)]}
lighting_quality_directional_cascades :: proc(quality: Lighting_Quality) -> int {values := [4]int {
		2,
		3,
		4,
		4,
	}
	return values[int(quality)]}
lighting_quality_directional_resolution :: proc(quality: Lighting_Quality) -> u32 {values :=
		[4]u32{1024, 1024, 2048, 2048}
	return values[int(quality)]}
lighting_quality_point_shadow_slots :: proc(quality: Lighting_Quality) -> int {values := [4]int {
		0,
		1,
		3,
		4,
	}
	return values[int(quality)]}
lighting_quality_point_shadow_resolution :: proc(quality: Lighting_Quality) -> u32 {values :=
		[4]u32{1, 512, 512, 1024}
	return values[int(quality)]}
lighting_quality_spot_shadow_slots :: proc(quality: Lighting_Quality) -> int {values := [4]int {
		0,
		2,
		4,
		6,
	}
	return values[int(quality)]}
lighting_quality_spot_shadow_resolution :: proc(quality: Lighting_Quality) -> u32 {values :=
		[4]u32{1, 512, 1024, 1024}
	return values[int(quality)]}
lighting_quality_local_shadow_samples :: proc(quality: Lighting_Quality) -> int {values := [4]int {
		0,
		1,
		2,
		3,
	}
	return values[int(quality)]}
lighting_quality_shadow_face_budget :: proc(quality: Lighting_Quality) -> int {values := [4]int {
		0,
		6,
		14,
		28,
	}
	return values[int(quality)]}
lighting_quality_label :: proc(quality: Lighting_Quality) -> string {values := [4]string {
		"LOW",
		"MEDIUM",
		"HIGH",
		"ULTRA",
	}
	return values[int(quality)]}

UI_Art :: enum {
	Title,
	Portrait_Edgar,
	Portrait_Miriam,
	Portrait_Daniel,
	Portrait_Elsie,
	Evidence_Statuette,
	Evidence_Rug,
	Evidence_Silk,
	Evidence_Cane,
	Evidence_Ledger,
	Evidence_Cloth,
	Evidence_Watch,
	Evidence_Place_Setting,
	Mini_Miriam,
	Mini_Daniel,
	Mini_Elsie,
	Mini_Edgar,
	Mini_Statuette,
	Mini_Cane,
	Mini_Shutter,
	Mini_Ledger,
	Mini_Cleaning_Kit,
	Mini_Move_Arrow,
	Mini_Staging_Marker,
	Prompt_Keyboard,
	Prompt_Xbox,
	Prompt_PlayStation,
	Prompt_Switch,
	Attribute_Portraits,
	Theme_Materials,
	Level_Builder_Atlas,
}
UI_ART_PATHS := [?]string {
	"assets/ui/title/the-torn-appointment-key-art.png",
	"assets/ui/portraits/edgar.png",
	"assets/ui/portraits/miriam.png",
	"assets/ui/portraits/daniel.png",
	"assets/ui/portraits/elsie.png",
	"assets/ui/evidence/bronze-statuette.png",
	"assets/ui/evidence/bloodied-rug.png",
	"assets/ui/evidence/green-silk-thread.png",
	"assets/ui/evidence/edgars-cane.png",
	"assets/ui/evidence/private-ledger.png",
	"assets/ui/evidence/polishing-cloth.png",
	"assets/ui/evidence/stopped-watch-824.png",
	"assets/ui/evidence/disturbed-place-setting.png",
	"assets/ui/miniatures/miriam.png",
	"assets/ui/miniatures/daniel.png",
	"assets/ui/miniatures/elsie.png",
	"assets/ui/miniatures/edgar-body.png",
	"assets/ui/miniatures/bronze-statuette.png",
	"assets/ui/miniatures/cane.png",
	"assets/ui/miniatures/shutter.png",
	"assets/ui/miniatures/ledger.png",
	"assets/ui/miniatures/lamp-oil-cleaning-kit.png",
	"assets/ui/miniatures/body-movement-arrow.png",
	"assets/ui/miniatures/staging-marker.png",
	"assets/kenney_input-prompts_1.5/Keyboard & Mouse/keyboard-&-mouse_sheet_default.png",
	"assets/kenney_input-prompts_1.5/Xbox Series/xbox-series_sheet_default.png",
	"assets/kenney_input-prompts_1.5/PlayStation Series/playstation-series_sheet_default.png",
	"assets/kenney_input-prompts_1.5/Nintendo Switch/nintendo-switch_sheet_default.png",
	"assets/ui/attributes/detective-attributes-atlas.png",
	"assets/ui/theme/investigation-materials.png",
	"assets/ui/level-builder-icon-atlas-v3.png",
}

Vk_Ui_Vertex :: struct {
	position, uv: Vec2,
	color:        [4]f32,
}
Vk_Ui_Push :: struct {
	logical_viewport:     Vec2,
	framebuffer:          Vec2,
	use_texture, padding: f32,
}
Vk_Ui_Batch :: struct {
	first_index, index_count: u32,
	descriptor:               vk.DescriptorSet,
	use_texture:              bool,
	scissor:                  vk.Rect2D,
}
Vk_Ui_Image :: resources.Image

Vulkan_Backend :: struct {
	ctx:                                                                                                                                                                 engine.Vk_Context,
	window:                                                                                                                                                              ^sdl.Window,
	vertices:                                                                                                                                                            [dynamic]Vk_Ui_Vertex,
	indices:                                                                                                                                                             [dynamic]u32,
	batches:                                                                                                                                                             [dynamic]Vk_Ui_Batch,
	ui_scissor:                                                                                                                                                          vk.Rect2D,
	images:                                                                                                                                                              [dynamic]Vk_Ui_Image,
	descriptors:                                                                                                                                                         [dynamic]vk.DescriptorSet,
	// UI geometry is streamed independently for every frame in flight. Reusing
	// one mapped buffer lets the CPU overwrite vertices while the previous frame
	// is still reading them, which shows up as a one-frame burst of white quads
	// whenever a state transition changes the UI's geometry.
	vertex_buffers,
	index_buffers:                                                                                                                                       [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
	descriptor_layout:                                                                                                                                                   vk.DescriptorSetLayout,
	descriptor_pool:                                                                                                                                                     vk.DescriptorPool,
	pipeline_layout:                                                                                                                                                     vk.PipelineLayout,
	pipeline:                                                                                                                                                            vk.Pipeline,
	aa_mode:                                                                                                                                                             Anti_Aliasing_Mode,
	aa_samples:                                                                                                                                                          vk.SampleCountFlags,
	aa_color:                                                                                                                                                            Vk_Ui_Image,
	fxaa_layout:                                                                                                                                                         vk.DescriptorSetLayout,
	fxaa_pool:                                                                                                                                                           vk.DescriptorPool,
	fxaa_set:                                                                                                                                                            vk.DescriptorSet,
	fxaa_pipeline_layout:                                                                                                                                                vk.PipelineLayout,
	fxaa_pipeline:                                                                                                                                                       vk.Pipeline,
	world:                                                                                                                                                               Vk_World_Scene,
	font_texture,
	font_latin_texture,
	font_punctuation_texture,
	font_arrow_texture,
	font_shape_texture,
	system_ui_font_texture,
	watch_frame_texture,
	watch_face_texture: int,
	art_textures:                                                                                                                                                        [len(
		UI_ART_PATHS,
	)]int,
	dialogue_asset_ids:                                                                                                                                                  [64]string,
	dialogue_asset_textures:                                                                                                                                             [64]int,
	dialogue_asset_count:                                                                                                                                                int,
	asset_preview_id,
	asset_preview_hash:                                                                                                                                string,
	asset_preview_texture:                                                                                                                                               int,
	campaign_textures:                                                                                                                                                   [CAMPAIGN_MAX_CATALOG]int,
	catalog_textures:                                                                                                                                                    [64]int,
	catalog_floor_textures,
	catalog_wall_textures:                                                                                                                       [64]int,
	capture_buffer:                                                                                                                                                      engine.Vk_Buffer,
	capture_state:                                                                                                                                                       engine.Screenshot_State,
	capture_path:                                                                                                                                                        string,
	capture_requested,
	capture_written:                                                                                                                                  bool,
	frame_counter:                                                                                                                                                       u64,
	profile_shadow_ms,
	profile_world_ms,
	profile_ui_ms,
	profile_tail_ms:                                                                                                 f64,
	profile_draw_setup_ms,
	profile_draw_refresh_ms,
	profile_draw_world_build_ms,
	profile_draw_weather_ms,
	profile_draw_overlay_ms:                                       f64,
	ready:                                                                                                                                                               bool,
}

vk_ui_image_destroy :: proc(
	image: ^Vk_Ui_Image,
	ctx: ^engine.Vk_Context,
) {resources.image_destroy(image, ctx)}

vk_aa_color_create :: proc(
	ctx: ^engine.Vk_Context,
	width, height: u32,
	samples: vk.SampleCountFlags,
	out: ^Vk_Ui_Image,
) -> bool {
	if !resources.image_create(ctx, width, height, ctx.swapchain_format, {.COLOR_ATTACHMENT, .SAMPLED}, {.COLOR}, samples, out, "anti-aliasing color") do return false
	if samples == {._1} {sampler := vk.SamplerCreateInfo {
			sType        = .SAMPLER_CREATE_INFO,
			magFilter    = .LINEAR,
			minFilter    = .LINEAR,
			mipmapMode   = .NEAREST,
			addressModeU = .CLAMP_TO_EDGE,
			addressModeV = .CLAMP_TO_EDGE,
			addressModeW = .CLAMP_TO_EDGE,
			maxLod       = 0,
		}; if vk.CreateSampler(ctx.device, &sampler, nil, &out.sampler) != .SUCCESS do return false}; out.width = width; out.height = height; return true
}

vk_fxaa_init :: proc(backend: ^Vulkan_Backend) -> bool {
	ctx := &backend.ctx; bindings := [2]vk.DescriptorSetLayoutBinding{{binding = 0, descriptorType = .SAMPLED_IMAGE, descriptorCount = 1, stageFlags = {.FRAGMENT}}, {binding = 1, descriptorType = .SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}}}; layout := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 2,
		pBindings    = raw_data(bindings[:]),
	}; if vk.CreateDescriptorSetLayout(ctx.device, &layout, nil, &backend.fxaa_layout) != .SUCCESS do return false
	pool_sizes := [2]vk.DescriptorPoolSize {
		{type = .SAMPLED_IMAGE, descriptorCount = 1},
		{type = .SAMPLER, descriptorCount = 1},
	}; pool := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = 1,
		poolSizeCount = 2,
		pPoolSizes    = raw_data(pool_sizes[:]),
	}; if vk.CreateDescriptorPool(ctx.device, &pool, nil, &backend.fxaa_pool) != .SUCCESS do return false; allocation := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = backend.fxaa_pool,
		descriptorSetCount = 1,
		pSetLayouts        = &backend.fxaa_layout,
	}; if vk.AllocateDescriptorSets(ctx.device, &allocation, &backend.fxaa_set) != .SUCCESS do return false
	pipeline_layout := vk.PipelineLayoutCreateInfo {
		sType          = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = 1,
		pSetLayouts    = &backend.fxaa_layout,
	}; if vk.CreatePipelineLayout(ctx.device, &pipeline_layout, nil, &backend.fxaa_pipeline_layout) != .SUCCESS do return false
	vert, frag: engine.Vk_Shader_Module; if !engine.vk_load_shader_module(ctx, "build/shaders/fxaa.vert.spv", &vert) do return false; defer engine.vk_destroy_shader_module(ctx, &vert); if !engine.vk_load_shader_module(ctx, "build/shaders/fxaa.frag.spv", &frag) do return false; defer engine.vk_destroy_shader_module(ctx, &frag)
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
	}; vertex := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	}; assembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
	}; viewport := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}; raster := vk.PipelineRasterizationStateCreateInfo {
		sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		cullMode    = {},
		frontFace   = .COUNTER_CLOCKWISE,
		lineWidth   = 1,
	}; samples := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
	}; attachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask = {.R, .G, .B, .A},
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
	); info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &rendering,
		stageCount          = 2,
		pStages             = raw_data(stages[:]),
		pVertexInputState   = &vertex,
		pInputAssemblyState = &assembly,
		pViewportState      = &viewport,
		pRasterizationState = &raster,
		pMultisampleState   = &samples,
		pColorBlendState    = &blend,
		pDynamicState       = &dynamic_info,
		layout              = backend.fxaa_pipeline_layout,
	}; return(
		vk.CreateGraphicsPipelines(
			ctx.device,
			vk.PipelineCache(0),
			1,
			&info,
			nil,
			&backend.fxaa_pipeline,
		) ==
		.SUCCESS \
	)
}

vk_fxaa_update_descriptor :: proc(backend: ^Vulkan_Backend) {image := vk.DescriptorImageInfo {
		imageView   = backend.aa_color.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}; sampler := vk.DescriptorImageInfo {
		sampler = backend.aa_color.sampler,
	}; writes := [2]vk.WriteDescriptorSet {
		{
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = backend.fxaa_set,
			dstBinding = 0,
			descriptorCount = 1,
			descriptorType = .SAMPLED_IMAGE,
			pImageInfo = &image,
		},
		{
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = backend.fxaa_set,
			dstBinding = 1,
			descriptorCount = 1,
			descriptorType = .SAMPLER,
			pImageInfo = &sampler,
		},
	}; vk.UpdateDescriptorSets(backend.ctx.device, 2, raw_data(writes[:]), 0, nil)}

vk_ui_image_upload :: proc(
	ctx: ^engine.Vk_Context,
	pixels: []u8,
	width, height: int,
	out: ^Vk_Ui_Image,
) -> bool {
	return resources.texture_upload_rgba8(
		ctx,
		pixels,
		width,
		height,
		out,
		resources.Sampler_Options{address_mode = .CLAMP_TO_EDGE},
	)
}

vulkan_backend_destroy :: proc(backend: ^Vulkan_Backend) {
	ctx := &backend.ctx
	if ctx.device != nil do _ = vk.DeviceWaitIdle(ctx.device)
	for &image in backend.images do vk_ui_image_destroy(&image, ctx)
	if backend.pipeline != vk.Pipeline(0) do vk.DestroyPipeline(ctx.device, backend.pipeline, nil)
	if backend.fxaa_pipeline != vk.Pipeline(0) do vk.DestroyPipeline(ctx.device, backend.fxaa_pipeline, nil)
	if backend.fxaa_pipeline_layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(ctx.device, backend.fxaa_pipeline_layout, nil)
	if backend.fxaa_pool != vk.DescriptorPool(0) do vk.DestroyDescriptorPool(ctx.device, backend.fxaa_pool, nil)
	if backend.fxaa_layout != vk.DescriptorSetLayout(0) do vk.DestroyDescriptorSetLayout(ctx.device, backend.fxaa_layout, nil)
	vk_ui_image_destroy(&backend.aa_color, ctx)
	vk_world_destroy(&backend.world, ctx)
	if backend.pipeline_layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(ctx.device, backend.pipeline_layout, nil)
	if backend.descriptor_pool != vk.DescriptorPool(0) do vk.DestroyDescriptorPool(ctx.device, backend.descriptor_pool, nil)
	if backend.descriptor_layout != vk.DescriptorSetLayout(0) do vk.DestroyDescriptorSetLayout(ctx.device, backend.descriptor_layout, nil)
	for i in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {engine.vk_destroy_buffer(ctx, &backend.index_buffers[i]); engine.vk_destroy_buffer(ctx, &backend.vertex_buffers[i])}
	engine.vk_destroy_buffer(
		ctx,
		&backend.capture_buffer,
	); engine.screenshot_state_destroy(&backend.capture_state)
	delete(
		backend.vertices,
	); delete(backend.indices); delete(backend.batches); delete(backend.images); delete(backend.descriptors); engine.vk_context_destroy(ctx); backend^ = {}
}

vulkan_backend_init :: proc(
	backend: ^Vulkan_Backend,
	window: ^sdl.Window,
	requested_aa := Anti_Aliasing_Mode.None,
) -> bool {
	backend^ = {}
	backend.window = window
	when ODIN_OS == .Darwin {if _, err := os.stat("/opt/homebrew/lib/libvulkan.1.dylib", context.temp_allocator); err == nil do _ = os.set_env("SDL_VULKAN_LIBRARY", "/opt/homebrew/lib/libvulkan.1.dylib")}
	if !engine.vk_context_init(&backend.ctx, window, WINDOW_WIDTH, WINDOW_HEIGHT, .7) do return false
	ctx := &backend.ctx; backend.aa_mode = requested_aa; backend.aa_samples = {._1}; properties: vk.PhysicalDeviceProperties; vk.GetPhysicalDeviceProperties(ctx.physical_device, &properties); supported := properties.limits.framebufferColorSampleCounts & properties.limits.framebufferDepthSampleCounts; if requested_aa == .MSAA_2X && vk.SampleCountFlag._2 in supported {backend.aa_samples = {._2}} else if requested_aa == .MSAA_4X && vk.SampleCountFlag._4 in supported {backend.aa_samples = {._4}} else if requested_aa == .MSAA_2X || requested_aa == .MSAA_4X {fmt.eprintln("requested MSAA mode is unsupported; anti-aliasing disabled"); backend.aa_mode = .None}; backend.vertices = make([dynamic]Vk_Ui_Vertex, 0, 4096); backend.indices = make([dynamic]u32, 0, 6144); backend.batches = make([dynamic]Vk_Ui_Batch, 0, 256); backend.images = make([dynamic]Vk_Ui_Image, 0, VK_UI_TEXTURE_CAPACITY); backend.descriptors = make([dynamic]vk.DescriptorSet, 0, VK_UI_TEXTURE_CAPACITY)
	for i in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {
		if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(VK_UI_VERTEX_CAPACITY * size_of(Vk_Ui_Vertex)), {.VERTEX_BUFFER}, &backend.vertex_buffers[i]) do return false
		if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(VK_UI_INDEX_CAPACITY * size_of(u32)), {.INDEX_BUFFER}, &backend.index_buffers[i]) do return false
	}
	bindings := [2]vk.DescriptorSetLayoutBinding {
		{
			binding = 0,
			descriptorType = .SAMPLED_IMAGE,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT},
		},
		{binding = 1, descriptorType = .SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
	}; descriptor_layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 2,
		pBindings    = raw_data(bindings[:]),
	}; if vk.CreateDescriptorSetLayout(ctx.device, &descriptor_layout_info, nil, &backend.descriptor_layout) != .SUCCESS do return false; pool_sizes := [2]vk.DescriptorPoolSize{{type = .SAMPLED_IMAGE, descriptorCount = VK_UI_TEXTURE_CAPACITY}, {type = .SAMPLER, descriptorCount = VK_UI_TEXTURE_CAPACITY}}; pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = VK_UI_TEXTURE_CAPACITY,
		poolSizeCount = 2,
		pPoolSizes    = raw_data(pool_sizes[:]),
	}; if vk.CreateDescriptorPool(ctx.device, &pool_info, nil, &backend.descriptor_pool) != .SUCCESS do return false
	push := vk.PushConstantRange {
		stageFlags = {.VERTEX, .FRAGMENT},
		offset     = 0,
		size       = u32(size_of(Vk_Ui_Push)),
	}; layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = 1,
		pSetLayouts            = &backend.descriptor_layout,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &push,
	}; if vk.CreatePipelineLayout(ctx.device, &layout_info, nil, &backend.pipeline_layout) != .SUCCESS do return false
	vert, frag: engine.Vk_Shader_Module; if !engine.vk_load_shader_module(ctx, "build/shaders/ui.vert.spv", &vert) do return false; defer engine.vk_destroy_shader_module(ctx, &vert); if !engine.vk_load_shader_module(ctx, "build/shaders/ui.frag.spv", &frag) do return false; defer engine.vk_destroy_shader_module(ctx, &frag)
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
		binding   = 0,
		stride    = u32(size_of(Vk_Ui_Vertex)),
		inputRate = .VERTEX,
	}; attributes := [3]vk.VertexInputAttributeDescription {
		{
			location = 0,
			binding = 0,
			format = .R32G32_SFLOAT,
			offset = u32(offset_of(Vk_Ui_Vertex, position)),
		},
		{
			location = 1,
			binding = 0,
			format = .R32G32_SFLOAT,
			offset = u32(offset_of(Vk_Ui_Vertex, uv)),
		},
		{
			location = 2,
			binding = 0,
			format = .R32G32B32A32_SFLOAT,
			offset = u32(offset_of(Vk_Ui_Vertex, color)),
		},
	}; vertex_input := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &binding,
		vertexAttributeDescriptionCount = 3,
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
		cullMode    = {},
		frontFace   = .COUNTER_CLOCKWISE,
		lineWidth   = 1,
	}; multisample := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = backend.aa_samples,
	}; color_attachment := vk.PipelineColorBlendAttachmentState {
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
		pAttachments    = &color_attachment,
	}; dynamic_states := [2]vk.DynamicState {
		.VIEWPORT,
		.SCISSOR,
	}; dynamic_info := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates    = raw_data(dynamic_states[:]),
	}; rendering := engine.vk_pipeline_rendering_info(
		&ctx.swapchain_format,
	); info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &rendering,
		stageCount          = 2,
		pStages             = raw_data(stages[:]),
		pVertexInputState   = &vertex_input,
		pInputAssemblyState = &assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &raster,
		pMultisampleState   = &multisample,
		pColorBlendState    = &blend,
		pDynamicState       = &dynamic_info,
		layout              = backend.pipeline_layout,
	}; if vk.CreateGraphicsPipelines(ctx.device, vk.PipelineCache(0), 1, &info, nil, &backend.pipeline) != .SUCCESS do return false
	white := [4]u8 {
		255,
		255,
		255,
		255,
	}; if vulkan_ui_upload_texture(backend, white[:], 1, 1) < 0 do return false
	if !vulkan_ui_upload_courier(backend) do return false
	if !vulkan_ui_upload_system_ui_font(backend) do return false
	watch_frame, watch_error := image.load(
		"assets/ui/watch-frame.png",
		{.alpha_add_if_missing},
		context.allocator,
	); if watch_error == nil && watch_frame != nil {backend.watch_frame_texture = vulkan_ui_upload_texture(backend, watch_frame.pixels.buf[:], watch_frame.width, watch_frame.height); image.destroy(watch_frame)} else {backend.watch_frame_texture = -1}
	watch_face, face_error := image.load(
		"assets/ui/watch-face.png",
		{.alpha_add_if_missing},
		context.allocator,
	); if face_error == nil && watch_face != nil {backend.watch_face_texture = vulkan_ui_upload_texture(backend, watch_face.pixels.buf[:], watch_face.width, watch_face.height); image.destroy(watch_face)} else {backend.watch_face_texture = -1}
	for _, i in backend.art_textures do backend.art_textures[i] = -1
	for path, i in UI_ART_PATHS {art, art_error := image.load(
			path,
			{.alpha_add_if_missing},
			context.allocator,
		)
		if art_error == nil &&
		   art !=
			   nil {backend.art_textures[i] = vulkan_ui_upload_texture(backend, art.pixels.buf[:], art.width, art.height); image.destroy(art)}}
	for node in active_story_project.nodes {if backend.dialogue_asset_count >= len(backend.dialogue_asset_ids) do break; path, ok := story_node_ui_image_path(&active_story_project, &authoring_workspace.assets, node.id); if !ok || !os.is_file(path) do continue; art, art_error := image.load(path, {.alpha_add_if_missing}, context.allocator); if art_error != nil || art == nil do continue; texture := vulkan_ui_upload_texture(backend, art.pixels.buf[:], art.width, art.height); image.destroy(art); if texture < 0 do continue; i := backend.dialogue_asset_count; backend.dialogue_asset_ids[i] = node.id; backend.dialogue_asset_textures[i] = texture; backend.dialogue_asset_count += 1}
	for _, i in backend.campaign_textures do backend.campaign_textures[i] = -1
	for entry, i in campaign_browser.entries[:campaign_browser.count] {if entry.thumbnail == "" || !os.exists(entry.thumbnail) do continue; hero, hero_error := image.load(entry.thumbnail, {.alpha_add_if_missing}, context.allocator); if hero_error == nil && hero != nil {backend.campaign_textures[i] = vulkan_ui_upload_texture(backend, hero.pixels.buf[:], hero.width, hero.height); image.destroy(hero)}}
	for _, i in backend.catalog_textures do backend.catalog_textures[i] = -1
	for _, i in backend.catalog_floor_textures {backend.catalog_floor_textures[i] = -1; backend.catalog_wall_textures[i] = -1}
	for entry in editor_catalog.entries {i := entry.thumbnail_index; if entry.kind != .Object || i < 0 || i >= len(backend.catalog_textures) || entry.thumbnail == "" || !os.exists(entry.thumbnail) do continue; thumbnail, thumbnail_error := image.load(entry.thumbnail, {.alpha_add_if_missing}, context.allocator); if thumbnail_error == nil && thumbnail != nil {backend.catalog_textures[i] = vulkan_ui_upload_texture(backend, thumbnail.pixels.buf[:], thumbnail.width, thumbnail.height); image.destroy(thumbnail); if backend.catalog_textures[i] < 0 do fmt.eprintln("catalog thumbnail GPU capacity exhausted: ", entry.thumbnail)} else {fmt.eprintln("catalog thumbnail decode failed: ", entry.thumbnail)}}
	for entry in editor_catalog.entries {if entry.kind != .Material || entry.catalog_index < 0 || entry.catalog_index >= len(backend.catalog_floor_textures) do continue
		if entry.floor != "" &&
		   os.exists(
			   entry.floor,
		   ) {texture, texture_error := image.load(entry.floor, {.alpha_add_if_missing}, context.allocator); if texture_error == nil && texture != nil {backend.catalog_floor_textures[entry.catalog_index] = vulkan_ui_upload_texture(backend, texture.pixels.buf[:], texture.width, texture.height); image.destroy(texture)}}
		if entry.wall != "" &&
		   os.exists(
			   entry.wall,
		   ) {texture, texture_error := image.load(entry.wall, {.alpha_add_if_missing}, context.allocator); if texture_error == nil && texture != nil {backend.catalog_wall_textures[entry.catalog_index] = vulkan_ui_upload_texture(backend, texture.pixels.buf[:], texture.width, texture.height); image.destroy(texture)}}
	}
	if backend.aa_mode == .FXAA && !vk_fxaa_init(backend) do return false
	if !vk_world_init(&backend.world, ctx, backend.aa_samples) do return false
	backend.ready = true; return true
}

vulkan_ui_upload_texture :: proc(
	backend: ^Vulkan_Backend,
	pixels: []u8,
	width, height: int,
) -> int {
	if len(backend.images) >= VK_UI_TEXTURE_CAPACITY do return -1; image: Vk_Ui_Image; if !vk_ui_image_upload(&backend.ctx, pixels, width, height, &image) do return -1; set: vk.DescriptorSet; alloc := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = backend.descriptor_pool,
		descriptorSetCount = 1,
		pSetLayouts        = &backend.descriptor_layout,
	}; if vk.AllocateDescriptorSets(backend.ctx.device, &alloc, &set) !=
	   .SUCCESS {vk_ui_image_destroy(&image, &backend.ctx); return -1}; image_info := vk.DescriptorImageInfo {
		imageView   = image.view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}; sampler_info := vk.DescriptorImageInfo {
		sampler = image.sampler,
	}; writes := [2]vk.WriteDescriptorSet {
		{
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = set,
			dstBinding = 0,
			descriptorCount = 1,
			descriptorType = .SAMPLED_IMAGE,
			pImageInfo = &image_info,
		},
		{
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = set,
			dstBinding = 1,
			descriptorCount = 1,
			descriptorType = .SAMPLER,
			pImageInfo = &sampler_info,
		},
	}; vk.UpdateDescriptorSets(backend.ctx.device, 2, raw_data(writes[:]), 0, nil); append(&backend.images, image); append(&backend.descriptors, set); return len(backend.images) - 1
}

vulkan_ui_art_texture :: proc(backend: ^Vulkan_Backend, art: UI_Art) -> int {index := int(art)
	if index < 0 || index >= len(backend.art_textures) do return -1
	return backend.art_textures[index]}
vulkan_dialogue_asset_texture :: proc(
	backend: ^Vulkan_Backend,
	node_id: string,
) -> int {if backend != nil do for id, index in backend.dialogue_asset_ids[:backend.dialogue_asset_count] do if id == node_id do return backend.dialogue_asset_textures[index]
	return -1}

// Asset images are decoded from the selected project record and uploaded on
// demand. The content hash makes replacement invalidate the preview while
// ordinary frames reuse the existing GPU texture.
vulkan_asset_preview_texture :: proc(
	backend: ^Vulkan_Backend,
	registry: ^Project_Asset_Registry,
	index: int,
) -> int {
	if backend == nil || registry == nil || index < 0 || index >= len(registry.assets) do return -1
	asset := registry.assets[index]
	if asset.kind != .Image && asset.kind != .Thumbnail && asset.kind != .Texture do return -1
	if backend.asset_preview_id == asset.id && backend.asset_preview_hash == asset.sha256 do return backend.asset_preview_texture
	path := project_asset_record_path(
		active_authoring_project.root_path,
		asset,
	); if !os.is_file(path) do return -1
	decoded, err := image.load(
		path,
		{.alpha_add_if_missing},
		context.temp_allocator,
	); if err != nil || decoded == nil do return -1
	texture := vulkan_ui_upload_texture(
		backend,
		decoded.pixels.buf[:],
		decoded.width,
		decoded.height,
	); image.destroy(decoded)
	if texture < 0 do return -1
	backend.asset_preview_id =
		asset.id; backend.asset_preview_hash = asset.sha256; backend.asset_preview_texture = texture
	return texture
}

vulkan_catalog_refresh_thumbnails :: proc(backend: ^Vulkan_Backend) -> int {
	refreshed := 0
	for &entry in editor_catalog.entries {
		if entry.kind != .Object || entry.thumbnail_index < 0 || entry.thumbnail_index >= len(backend.catalog_textures) do continue
		catalog_refresh_preview_state(&entry); if entry.thumbnail_missing do continue
		thumbnail, thumbnail_error := image.load(
			entry.thumbnail,
			{.alpha_add_if_missing},
			context.allocator,
		); if thumbnail_error != nil || thumbnail == nil do continue
		texture := vulkan_ui_upload_texture(
			backend,
			thumbnail.pixels.buf[:],
			thumbnail.width,
			thumbnail.height,
		); image.destroy(thumbnail)
		if texture >=
		   0 {backend.catalog_textures[entry.thumbnail_index] = texture; entry.thumbnail_stale = false; refreshed += 1}
	}
	return refreshed
}

vulkan_ui_begin :: proc(backend: ^Vulkan_Backend) {clear(&backend.vertices); clear(
		&backend.indices,
	)
	clear(&backend.batches)
	backend.ui_scissor = {
		offset = {0, 0},
		extent = {0xffffffff, 0xffffffff},
	}}
vulkan_ui_scissor :: proc(backend: ^Vulkan_Backend, x, y, w, h: f32) {backend.ui_scissor = {
		offset = {i32(x), i32(y)},
		extent = {u32(max(w, 0)), u32(max(h, 0))},
	}}
vulkan_ui_scissor_reset :: proc(backend: ^Vulkan_Backend) {backend.ui_scissor = {
		offset = {0, 0},
		extent = {0xffffffff, 0xffffffff},
	}}
vulkan_ui_append_batch :: proc(
	backend: ^Vulkan_Backend,
	first, count: u32,
	descriptor: vk.DescriptorSet,
	use_texture: bool,
) {
	// Adjacent quads using the same material are one GPU draw. In particular,
	// this keeps a line of glyphs from consuming one command per character.
	if len(backend.batches) >
	   0 {last := &backend.batches[len(backend.batches) - 1]; if last.descriptor == descriptor && last.use_texture == use_texture && last.scissor == backend.ui_scissor && last.first_index + last.index_count == first {last.index_count += count; return}}
	append(
		&backend.batches,
		Vk_Ui_Batch{first, count, descriptor, use_texture, backend.ui_scissor},
	)
}
vulkan_ui_quad :: proc(
	backend: ^Vulkan_Backend,
	x, y, w, h: f32,
	color: [4]u8,
	texture_index := 0,
	uv0 := Vec2{},
	uv1 := Vec2{1, 1},
	use_texture := false,
) {
	if len(backend.vertices) + 4 > VK_UI_VERTEX_CAPACITY || texture_index < 0 || texture_index >= len(backend.descriptors) do return; c := [4]f32{f32(color[0]) / 255, f32(color[1]) / 255, f32(color[2]) / 255, f32(color[3]) / 255}; base := u32(len(backend.vertices)); append(&backend.vertices, Vk_Ui_Vertex{{x, y}, {uv0.x, uv0.y}, c}, Vk_Ui_Vertex{{x + w, y}, {uv1.x, uv0.y}, c}, Vk_Ui_Vertex{{x + w, y + h}, {uv1.x, uv1.y}, c}, Vk_Ui_Vertex{{x, y + h}, {uv0.x, uv1.y}, c}); first := u32(len(backend.indices)); append(&backend.indices, base, base + 1, base + 2, base, base + 2, base + 3); vulkan_ui_append_batch(backend, first, 6, backend.descriptors[texture_index], use_texture)
}

vulkan_ui_slanted_quad :: proc(
	backend: ^Vulkan_Backend,
	x, y, w, h, top_offset: f32,
	color: [4]u8,
	texture_index := 0,
	uv0 := Vec2{},
	uv1 := Vec2{1, 1},
	use_texture := false,
) {
	if len(backend.vertices) + 4 > VK_UI_VERTEX_CAPACITY || texture_index < 0 || texture_index >= len(backend.descriptors) do return
	c := [4]f32 {
		f32(color[0]) / 255,
		f32(color[1]) / 255,
		f32(color[2]) / 255,
		f32(color[3]) / 255,
	}; base := u32(len(backend.vertices))
	append(
		&backend.vertices,
		Vk_Ui_Vertex{{x + top_offset, y}, {uv0.x, uv0.y}, c},
		Vk_Ui_Vertex{{x + w + top_offset, y}, {uv1.x, uv0.y}, c},
		Vk_Ui_Vertex{{x + w, y + h}, {uv1.x, uv1.y}, c},
		Vk_Ui_Vertex{{x, y + h}, {uv0.x, uv1.y}, c},
	)
	first := u32(
		len(backend.indices),
	); append(&backend.indices, base, base + 1, base + 2, base, base + 2, base + 3); vulkan_ui_append_batch(backend, first, 6, backend.descriptors[texture_index], use_texture)
}
vulkan_ui_rect :: proc(backend: ^Vulkan_Backend, x, y, w, h: f32, color: [4]u8) {vulkan_ui_quad(
		backend,
		x,
		y,
		w,
		h,
		color,
	)}

// Dims the viewport everywhere except the supplied component bounds. Call this
// after the background UI has been drawn, then draw tutorial chrome or a modal
// on top. Bounds outside the viewport are clipped and empty bounds are ignored.
// The return value is the number of overlay rectangles emitted, which is useful
// to deterministic headless tests and renderer diagnostics.
vk_ui_dim_all_except :: proc(
	backend: ^Vulkan_Backend,
	components: []Rect,
	color: [4]u8 = {4, 7, 10, 190},
	viewport: Rect = {0, 0, WINDOW_WIDTH, WINDOW_HEIGHT},
) -> int {
	if viewport.w <= 0 || viewport.h <= 0 || color[3] == 0 do return 0
	left, top, right, bottom :=
		viewport.x, viewport.y, viewport.x + viewport.w, viewport.y + viewport.h
	emitted := 0
	x := left
	for x < right {
		next_x := right
		for component in components {
			if component.w <= 0 || component.h <= 0 do continue
			component_left := max(
				component.x,
				left,
			); component_right := min(component.x + component.w, right)
			if component_right <= component_left do continue
			if component_left > x && component_left < next_x do next_x = component_left
			if component_right > x && component_right < next_x do next_x = component_right
		}
		if next_x <= x do break
		y := top
		for y < bottom {
			covered_end := y
			// Grow a covered interval until all overlapping selections have been
			// folded in. This handles vertically overlapping component bounds.
			changed := true
			for changed {
				changed = false
				for component in components {
					if component.w <= 0 || component.h <= 0 do continue
					component_left := max(
						component.x,
						left,
					); component_right := min(component.x + component.w, right)
					component_top := max(
						component.y,
						top,
					); component_bottom := min(component.y + component.h, bottom)
					if component_right <= x || component_left >= next_x || component_bottom <= component_top do continue
					if component_top <= covered_end &&
					   component_bottom >
						   covered_end {covered_end = component_bottom; changed = true}
				}
			}
			if covered_end > y {y = min(covered_end, bottom); continue}
			next_y := bottom
			for component in components {
				if component.w <= 0 || component.h <= 0 do continue
				component_left := max(
					component.x,
					left,
				); component_right := min(component.x + component.w, right)
				component_top := max(
					component.y,
					top,
				); component_bottom := min(component.y + component.h, bottom)
				if component_right <= x || component_left >= next_x || component_bottom <= component_top do continue
				if component_top > y && component_top < next_y do next_y = component_top
			}
			if next_y <= y do break
			vulkan_ui_rect(backend, x, y, next_x - x, next_y - y, color); emitted += 1; y = next_y
		}
		x = next_x
	}
	return emitted
}

vulkan_ui_triangle :: proc(backend: ^Vulkan_Backend, a, b, c: Vec2, color: [4]u8) {
	if len(backend.vertices) + 3 > VK_UI_VERTEX_CAPACITY do return
	tint := [4]f32 {
		f32(color[0]) / 255,
		f32(color[1]) / 255,
		f32(color[2]) / 255,
		f32(color[3]) / 255,
	}
	base := u32(
		len(backend.vertices),
	); append(&backend.vertices, Vk_Ui_Vertex{a, {}, tint}, Vk_Ui_Vertex{b, {}, tint}, Vk_Ui_Vertex{c, {}, tint})
	first := u32(len(backend.indices)); append(&backend.indices, base, base + 1, base + 2)
	vulkan_ui_append_batch(backend, first, 3, backend.descriptors[0], false)
}

vulkan_ui_triangle_colors :: proc(
	backend: ^Vulkan_Backend,
	a, b, c: Vec2,
	color_a, color_b, color_c: [4]u8,
) {
	if len(backend.vertices) + 3 > VK_UI_VERTEX_CAPACITY do return
	tint_a := [4]f32 {
		f32(color_a[0]) / 255,
		f32(color_a[1]) / 255,
		f32(color_a[2]) / 255,
		f32(color_a[3]) / 255,
	}
	tint_b := [4]f32 {
		f32(color_b[0]) / 255,
		f32(color_b[1]) / 255,
		f32(color_b[2]) / 255,
		f32(color_b[3]) / 255,
	}
	tint_c := [4]f32 {
		f32(color_c[0]) / 255,
		f32(color_c[1]) / 255,
		f32(color_c[2]) / 255,
		f32(color_c[3]) / 255,
	}
	base := u32(
		len(backend.vertices),
	); append(&backend.vertices, Vk_Ui_Vertex{a, {}, tint_a}, Vk_Ui_Vertex{b, {}, tint_b}, Vk_Ui_Vertex{c, {}, tint_c})
	first := u32(len(backend.indices)); append(&backend.indices, base, base + 1, base + 2)
	vulkan_ui_append_batch(backend, first, 3, backend.descriptors[0], false)
}

vulkan_ui_outline :: proc(
	backend: ^Vulkan_Backend,
	x, y, w, h: f32,
	color: [4]u8,
	thickness: f32 = 1,
) {
	vulkan_ui_rect(
		backend,
		x,
		y,
		w,
		thickness,
		color,
	); vulkan_ui_rect(backend, x, y + h - thickness, w, thickness, color)
	vulkan_ui_rect(
		backend,
		x,
		y,
		thickness,
		h,
		color,
	); vulkan_ui_rect(backend, x + w - thickness, y, thickness, h, color)
}

vulkan_ui_glyph :: proc(
	backend: ^Vulkan_Backend,
	x, y: f32,
	ch: rune,
	color: [4]u8,
	scale_x, scale_y: f32,
) {
	vulkan_ui_glyph_slanted(backend, x, y, ch, color, scale_x, scale_y, 0)
}

vulkan_ui_glyph_slanted :: proc(
	backend: ^Vulkan_Backend,
	x, y: f32,
	ch: rune,
	color: [4]u8,
	scale_x, scale_y, top_offset: f32,
) {
	if backend.font_texture < 0 || backend.font_texture >= len(backend.images) do return
	codepoint := int(
		ch,
	); atlas_texture, first, count := backend.font_texture, COURIER_FIRST_GLYPH, COURIER_GLYPH_COUNT
	if codepoint >= COURIER_LATIN_FIRST &&
	   codepoint <
		   COURIER_LATIN_FIRST +
			   COURIER_LATIN_GLYPH_COUNT {atlas_texture = backend.font_latin_texture; first = COURIER_LATIN_FIRST; count = COURIER_LATIN_GLYPH_COUNT} else if codepoint >= COURIER_PUNCTUATION_FIRST && codepoint < COURIER_PUNCTUATION_FIRST + COURIER_PUNCTUATION_GLYPH_COUNT {atlas_texture = backend.font_punctuation_texture; first = COURIER_PUNCTUATION_FIRST; count = COURIER_PUNCTUATION_GLYPH_COUNT} else if codepoint >= COURIER_ARROW_FIRST && codepoint < COURIER_ARROW_FIRST + COURIER_ARROW_GLYPH_COUNT {atlas_texture = backend.font_arrow_texture; first = COURIER_ARROW_FIRST; count = COURIER_ARROW_GLYPH_COUNT} else if codepoint >= COURIER_SHAPE_FIRST && codepoint < COURIER_SHAPE_FIRST + COURIER_SHAPE_GLYPH_COUNT {atlas_texture = backend.font_shape_texture; first = COURIER_SHAPE_FIRST; count = COURIER_SHAPE_GLYPH_COUNT}
	glyph := codepoint - first
	if glyph < 0 ||
	   glyph >= count ||
	   atlas_texture < 0 ||
	   atlas_texture >=
		   len(
			   backend.images,
		   ) {atlas_texture = backend.font_texture; glyph = int('?') - COURIER_FIRST_GLYPH}
	atlas :=
		backend.images[atlas_texture]; column := glyph % COURIER_COLUMNS; row := glyph / COURIER_COLUMNS
	// Sample at texel centers so linear filtering never mixes a neighboring
	// atlas cell into the edge of this glyph.
	half_u := .5 / f32(atlas.width); half_v := .5 / f32(atlas.height)
	uv0 := Vec2 {
		f32(column * COURIER_RASTER_CELL_WIDTH) / f32(atlas.width) + half_u,
		f32(row * COURIER_RASTER_CELL_HEIGHT) / f32(atlas.height) + half_v,
	}; uv1 := Vec2{f32((column + 1) * COURIER_RASTER_CELL_WIDTH) / f32(atlas.width) - half_u, f32((row + 1) * COURIER_RASTER_CELL_HEIGHT) / f32(atlas.height) - half_v}; vulkan_ui_slanted_quad(backend, x, y, f32(COURIER_CELL_WIDTH) * scale_x, f32(COURIER_CELL_HEIGHT) * scale_y, top_offset, color, atlas_texture, uv0, uv1, true)
}

vulkan_ui_text :: proc(
	backend: ^Vulkan_Backend,
	texture_index: int,
	x, y: f32,
	value: string,
	color: [4]u8,
	scale: f32 = 1,
) {
	if texture_index < 0 || texture_index >= len(backend.images) do return; cursor_x, cursor_y := x, y; cell_w := f32(COURIER_CELL_WIDTH) * scale; cell_h := f32(COURIER_CELL_HEIGHT) * scale
	for ch in value {
		if ch == '\n' {cursor_x = x; cursor_y += cell_h; continue}
		vulkan_ui_glyph(backend, cursor_x, cursor_y, ch, color, scale, scale); cursor_x += cell_w
	}
}

vulkan_ui_system_text :: proc(
	backend: ^Vulkan_Backend,
	x, y: f32,
	value: string,
	color: [4]u8,
	scale: f32 = 1,
) {
	texture :=
		backend.system_ui_font_texture; if texture < 0 || texture >= len(backend.images) do return
	atlas :=
		backend.images[texture]; cursor_x, cursor_y := x, y; cell_w := f32(COURIER_CELL_WIDTH) * scale; cell_h := f32(COURIER_CELL_HEIGHT) * scale
	bytes := transmute([]u8)value; shaped: [512]Textshape_Glyph; count := int(vo_textshape_shape(i32(SYSTEM_UI_FONT_KIND), raw_data(bytes), i32(len(bytes)), scale / f32(COURIER_RASTER_SCALE), raw_data(shaped[:]), i32(len(shaped))))
	if count <= 0 do return
	for item in shaped[:count] {
		if item.glyph_id == u32('\n') {cursor_x = x; cursor_y += cell_h; continue}
		glyph := int(item.glyph_id) - COURIER_FIRST_GLYPH
		if glyph < 0 ||
		   glyph >=
			   COURIER_GLYPH_COUNT {vulkan_ui_glyph(backend, cursor_x, cursor_y, rune(item.glyph_id), color, scale, scale); cursor_x += max(item.x_advance, cell_w); continue}
		column :=
			glyph %
			COURIER_COLUMNS; row := glyph / COURIER_COLUMNS; half_u := .5 / f32(atlas.width); half_v := .5 / f32(atlas.height)
		uv0 := Vec2 {
			f32(column * COURIER_RASTER_CELL_WIDTH) / f32(atlas.width) + half_u,
			f32(row * COURIER_RASTER_CELL_HEIGHT) / f32(atlas.height) + half_v,
		}; uv1 := Vec2{f32((column + 1) * COURIER_RASTER_CELL_WIDTH) / f32(atlas.width) - half_u, f32((row + 1) * COURIER_RASTER_CELL_HEIGHT) / f32(atlas.height) - half_v}
		vulkan_ui_quad(
			backend,
			cursor_x + item.x_offset,
			cursor_y - item.y_offset,
			cell_w,
			cell_h,
			color,
			texture,
			uv0,
			uv1,
			true,
		); cursor_x += item.x_advance
	}
}

vulkan_ui_upload_glyph_range :: proc(
	backend: ^Vulkan_Backend,
	font_kind, first, count: int,
) -> int {
	rows :=
		(count + COURIER_COLUMNS - 1) /
		COURIER_COLUMNS; width := COURIER_RASTER_CELL_WIDTH * COURIER_COLUMNS; height := COURIER_RASTER_CELL_HEIGHT * rows
	rgba := make([]u8, width * height * 4, context.temp_allocator)
	font_pixels := 14 * COURIER_RASTER_SCALE
	if vo_textshape_render_ascii_atlas(i32(font_kind), i32(first), i32(first + count - 1), i32(font_pixels), COURIER_RASTER_CELL_WIDTH, COURIER_RASTER_CELL_HEIGHT, COURIER_COLUMNS, raw_data(rgba), i32(len(rgba))) == 0 do return -1
	return vulkan_ui_upload_texture(backend, rgba, width, height)
}

vulkan_ui_upload_courier :: proc(backend: ^Vulkan_Backend) -> bool {
	path := system_courier_path(

	); if path == "" do return false; font_path := strings.clone_to_cstring(path, context.temp_allocator); font_pixels := 14 * COURIER_RASTER_SCALE; if vo_textshape_init(COURIER_FONT_KIND, font_path, f32(font_pixels)) == 0 do return false
	symbol_path := system_symbol_path(

	); if symbol_path == "" do return false; symbol_font_path := strings.clone_to_cstring(symbol_path, context.temp_allocator); if vo_textshape_init(SYMBOL_FONT_KIND, symbol_font_path, f32(font_pixels)) == 0 do return false
	backend.font_texture = vulkan_ui_upload_glyph_range(
		backend,
		COURIER_FONT_KIND,
		COURIER_FIRST_GLYPH,
		COURIER_GLYPH_COUNT,
	)
	backend.font_latin_texture = vulkan_ui_upload_glyph_range(
		backend,
		COURIER_FONT_KIND,
		COURIER_LATIN_FIRST,
		COURIER_LATIN_GLYPH_COUNT,
	)
	backend.font_punctuation_texture = vulkan_ui_upload_glyph_range(
		backend,
		COURIER_FONT_KIND,
		COURIER_PUNCTUATION_FIRST,
		COURIER_PUNCTUATION_GLYPH_COUNT,
	)
	backend.font_arrow_texture = vulkan_ui_upload_glyph_range(
		backend,
		COURIER_FONT_KIND,
		COURIER_ARROW_FIRST,
		COURIER_ARROW_GLYPH_COUNT,
	)
	backend.font_shape_texture = vulkan_ui_upload_glyph_range(
		backend,
		SYMBOL_FONT_KIND,
		COURIER_SHAPE_FIRST,
		COURIER_SHAPE_GLYPH_COUNT,
	)
	return(
		backend.font_texture >= 0 &&
		backend.font_latin_texture >= 0 &&
		backend.font_punctuation_texture >= 0 &&
		backend.font_arrow_texture >= 0 &&
		backend.font_shape_texture >= 0 \
	)
}

vulkan_ui_upload_system_ui_font :: proc(backend: ^Vulkan_Backend) -> bool {
	path := system_ui_font_path(

	); if path == "" do return false; font_path := strings.clone_to_cstring(path, context.temp_allocator); font_pixels := 14 * COURIER_RASTER_SCALE
	if vo_textshape_init(SYSTEM_UI_FONT_KIND, font_path, f32(font_pixels)) == 0 do return false
	rows :=
		(COURIER_GLYPH_COUNT + COURIER_COLUMNS - 1) /
		COURIER_COLUMNS; width := COURIER_RASTER_CELL_WIDTH * COURIER_COLUMNS; height := COURIER_RASTER_CELL_HEIGHT * rows
	rgba := make([]u8, width * height * 4, context.temp_allocator)
	if vo_textshape_render_ascii_atlas(i32(SYSTEM_UI_FONT_KIND), i32(COURIER_FIRST_GLYPH), i32(COURIER_FIRST_GLYPH + COURIER_GLYPH_COUNT - 1), i32(font_pixels), COURIER_RASTER_CELL_WIDTH, COURIER_RASTER_CELL_HEIGHT, COURIER_COLUMNS, raw_data(rgba), i32(len(rgba))) == 0 do return false
	backend.system_ui_font_texture = vulkan_ui_upload_texture(backend, rgba, width, height)
	return backend.system_ui_font_texture >= 0
}

vulkan_backend_request_capture :: proc(
	backend: ^Vulkan_Backend,
	path: string,
) {backend.capture_path = path; backend.capture_requested = true; backend.capture_written = false}

vulkan_check_screen_effect :: proc(g: ^Game) -> (zoom: f32, focus, shake: Vec2) {
	zoom = 1; focus = {WINDOW_WIDTH * .5, WINDOW_HEIGHT * .5}; if g == nil || g.screen != .Check || !g.check_done do return
	elapsed :=
		g.animation_time -
		g.check_roll_started; if elapsed < 0 || elapsed >= CHECK_REVEAL_DURATION do return
	ease := check_roll_ease(
		elapsed,
	); shown := f32(g.check_result.total) * ease; proximity := 1 - clamp(math.abs(shown - f32(g.check_result.target)) / 4, 0, 1)
	// A coarse screen-space shake gives the tumbling dice a physical impact.
	roll_phase := clamp(
		elapsed / CHECK_ROLL_DURATION,
		0,
		1,
	); envelope := min(clamp((roll_phase - .05) / .12, 0, 1), clamp((1 - roll_phase) / .1, 0, 1)); closeness := 1 - clamp(math.abs(f32(g.check_result.total - g.check_result.target)) / 4, 0, 1); zoom = 1 + envelope * (.025 + proximity * (.08 + closeness * .14)); focus = {WINDOW_WIDTH * .5, 335}
	amplitude :=
		envelope *
		proximity *
		(1 +
				closeness *
					3); shake = {f32(math.round(math.sin(f64(g.animation_time * 43)) * f64(amplitude))), f32(math.round(math.sin(f64(g.animation_time * 61 + 1.7)) * f64(amplitude)))}
	return
}

vulkan_backend_frame :: proc(backend: ^Vulkan_Backend, g: ^Game = nil) -> bool {
	ctx := &backend.ctx
	backend.profile_shadow_ms = 0; backend.profile_world_ms = 0; backend.profile_ui_ms = 0; backend.profile_tail_ms = 0
	// Capture uses one readback buffer and may sample a shared post-process
	// target. Drain older frames before recording the requested image so the
	// screenshot cannot contain pieces from two frames in flight.
	if backend.capture_requested do _ = vk.DeviceWaitIdle(ctx.device)
	if ctx.needs_swapchain_recreate {w, h: i32; sdl.GetWindowSizeInPixels(backend.window, &w, &h); if w > 0 && h > 0 do _ = engine.vk_recreate_swapchain(ctx, w, h); return true}; frame, ok := engine.vk_begin_frame(ctx); if !ok do return true; extent := ctx.swapchain_extent; image := ctx.swapchain_images[frame.image_index]; engine.vk_cmd_image_barrier2(ctx, frame.command_buffer, image, {.TOP_OF_PIPE}, {.COLOR_ATTACHMENT_OUTPUT}, {}, {.COLOR_ATTACHMENT_WRITE}, .PRESENT_SRC_KHR, .COLOR_ATTACHMENT_OPTIMAL); engine.vk_cmd_begin_swapchain_render_pass(ctx, frame, ui.Color{f32(UI_CANVAS[0]) / 255, f32(UI_CANVAS[1]) / 255, f32(UI_CANVAS[2]) / 255, 1})
	if backend.world.depth.width != extent.width ||
	   backend.world.depth.height !=
		   extent.height {_ = vk.DeviceWaitIdle(ctx.device); vk_ui_image_destroy(&backend.world.depth, ctx); if !vk_world_depth_create(ctx, extent.width, extent.height, &backend.world.depth, backend.aa_samples) do return false}
	msaa := backend.aa_mode == .MSAA_2X || backend.aa_mode == .MSAA_4X
	fxaa := backend.aa_mode == .FXAA
	if (msaa || fxaa) &&
	   (backend.aa_color.width != extent.width ||
			   backend.aa_color.height !=
				   extent.height) {_ = vk.DeviceWaitIdle(ctx.device); vk_ui_image_destroy(&backend.aa_color, ctx); if !vk_aa_color_create(ctx, extent.width, extent.height, backend.aa_samples, &backend.aa_color) do return false; if fxaa do vk_fxaa_update_descriptor(backend)}
	if msaa || fxaa do engine.vk_cmd_image_barrier2(ctx, frame.command_buffer, backend.aa_color.image, {.TOP_OF_PIPE}, {.COLOR_ATTACHMENT_OUTPUT}, {}, {.COLOR_ATTACHMENT_WRITE}, .UNDEFINED, .COLOR_ATTACHMENT_OPTIMAL)
	engine.vk_cmd_image_barrier2(
		ctx,
		frame.command_buffer,
		backend.world.depth.image,
		{.TOP_OF_PIPE},
		{.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS},
		{},
		{.DEPTH_STENCIL_ATTACHMENT_WRITE},
		.UNDEFINED,
		.DEPTH_ATTACHMENT_OPTIMAL,
		{.DEPTH},
	)
	// Restart dynamic rendering with a depth attachment; UI draws later in this
	// same pass with depth disabled by its pipeline.
	resolve_mode: vk.ResolveModeFlags = {}; if msaa do resolve_mode = {.AVERAGE}
	engine.vk_cmd_end_swapchain_render_pass(
		frame,
	); shadow_started := time.tick_now(); if g != nil do vk_world_shadow_record(&backend.world, ctx, frame.command_buffer, g, int(frame.frame_index)); backend.profile_shadow_ms = time.duration_seconds(time.tick_diff(shadow_started, time.tick_now())) * 1000; clear_color := [4]f32{.035, .042, .055, 1}; if g != nil && (g.screen == .Exterior || dialogue_returns_to_exterior(g)) do clear_color = {.18, .34, .52, 1}; if g != nil && (g.screen == .Investigate || g.screen == .Dialogue && !dialogue_returns_to_exterior(g)) do clear_color = {.075, .098, .108, 1}; color_clear := vk.ClearValue {
		color = {float32 = clear_color},
	}; depth_clear := vk.ClearValue {
		depthStencil = {depth = 1},
	}; color_attachment := vk.RenderingAttachmentInfo {
		sType              = .RENDERING_ATTACHMENT_INFO,
		imageView          = (msaa || fxaa) ? backend.aa_color.view : ctx.swapchain_image_views[frame.image_index],
		imageLayout        = .COLOR_ATTACHMENT_OPTIMAL,
		resolveMode        = resolve_mode,
		resolveImageView   = msaa ? ctx.swapchain_image_views[frame.image_index] : vk.ImageView(0),
		resolveImageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp             = .CLEAR,
		storeOp            = msaa ? .DONT_CARE : .STORE,
		clearValue         = color_clear,
	}; depth_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = backend.world.depth.view,
		imageLayout = .DEPTH_ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .DONT_CARE,
		clearValue  = depth_clear,
	}; rendering := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = extent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment,
		pDepthAttachment = &depth_attachment,
	}; vk.CmdBeginRendering(frame.command_buffer, &rendering)
	world_started := time.tick_now(

	); if g != nil do vk_world_record(&backend.world, ctx, frame.command_buffer, extent, g, int(frame.frame_index)); backend.profile_world_ms = time.duration_seconds(time.tick_diff(world_started, time.tick_now())) * 1000
	ui_started := time.tick_now(

	); if len(backend.vertices) > 0 {vertex_buffer := &backend.vertex_buffers[frame.frame_index]; index_buffer := &backend.index_buffers[frame.frame_index]; mem.copy_non_overlapping(vertex_buffer.mapped, raw_data(backend.vertices[:]), len(backend.vertices) * size_of(Vk_Ui_Vertex)); mem.copy_non_overlapping(index_buffer.mapped, raw_data(backend.indices[:]), len(backend.indices) * size_of(u32)); zoom, focus, shake := vulkan_check_screen_effect(g); sx := f32(extent.width) / WINDOW_WIDTH; sy := f32(extent.height) / WINDOW_HEIGHT; viewport := vk.Viewport {
			x        = (focus.x * (1 - zoom) + shake.x) * sx,
			y        = (focus.y * (1 - zoom) + shake.y) * sy,
			width    = f32(extent.width) * zoom,
			height   = f32(extent.height) * zoom,
			minDepth = 0,
			maxDepth = 1,
		}; vk.CmdSetViewport(
			frame.command_buffer,
			0,
			1,
			&viewport,
		); vk.CmdBindPipeline(frame.command_buffer, .GRAPHICS, backend.pipeline); offset := vk.DeviceSize(0); vk.CmdBindVertexBuffers(frame.command_buffer, 0, 1, &vertex_buffer.handle, &offset); vk.CmdBindIndexBuffer(frame.command_buffer, index_buffer.handle, 0, .UINT32); for batch in backend.batches {scissor := batch.scissor; if scissor.extent.width == 0xffffffff {scissor = {
					offset = {0, 0},
					extent = extent,
				}} else {scissor.offset = {
					i32(f32(scissor.offset.x) * sx),
					i32(f32(scissor.offset.y) * sy),
				}
				scissor.extent = {
					u32(f32(scissor.extent.width) * sx),
					u32(f32(scissor.extent.height) * sy),
				}}; vk.CmdSetScissor(frame.command_buffer, 0, 1, &scissor); descriptor := batch.descriptor; vk.CmdBindDescriptorSets(frame.command_buffer, .GRAPHICS, backend.pipeline_layout, 0, 1, &descriptor, 0, nil); push := Vk_Ui_Push{{WINDOW_WIDTH, WINDOW_HEIGHT}, {f32(extent.width), f32(extent.height)}, batch.use_texture ? 1 : 0, 0}; vk.CmdPushConstants(frame.command_buffer, backend.pipeline_layout, {.VERTEX, .FRAGMENT}, 0, u32(size_of(push)), &push); vk.CmdDrawIndexed(frame.command_buffer, batch.index_count, 1, batch.first_index, 0, 0)}}; backend.profile_ui_ms = time.duration_seconds(time.tick_diff(ui_started, time.tick_now())) * 1000
	tail_started := time.tick_now(); vk.CmdEndRendering(frame.command_buffer)
	if fxaa {
		engine.vk_cmd_image_barrier2(
			ctx,
			frame.command_buffer,
			backend.aa_color.image,
			{.COLOR_ATTACHMENT_OUTPUT},
			{.FRAGMENT_SHADER},
			{.COLOR_ATTACHMENT_WRITE},
			{.SHADER_READ},
			.COLOR_ATTACHMENT_OPTIMAL,
			.SHADER_READ_ONLY_OPTIMAL,
		)
		post_attachment := vk.RenderingAttachmentInfo {
			sType       = .RENDERING_ATTACHMENT_INFO,
			imageView   = ctx.swapchain_image_views[frame.image_index],
			imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
			loadOp      = .DONT_CARE,
			storeOp     = .STORE,
		}; post_rendering := vk.RenderingInfo {
			sType = .RENDERING_INFO,
			renderArea = {extent = extent},
			layerCount = 1,
			colorAttachmentCount = 1,
			pColorAttachments = &post_attachment,
		}; vk.CmdBeginRendering(frame.command_buffer, &post_rendering); viewport := vk.Viewport {
			width    = f32(extent.width),
			height   = f32(extent.height),
			minDepth = 0,
			maxDepth = 1,
		}; scissor := vk.Rect2D {
			extent = extent,
		}; vk.CmdSetViewport(
			frame.command_buffer,
			0,
			1,
			&viewport,
		); vk.CmdSetScissor(frame.command_buffer, 0, 1, &scissor); vk.CmdBindPipeline(frame.command_buffer, .GRAPHICS, backend.fxaa_pipeline); vk.CmdBindDescriptorSets(frame.command_buffer, .GRAPHICS, backend.fxaa_pipeline_layout, 0, 1, &backend.fxaa_set, 0, nil); vk.CmdDraw(frame.command_buffer, 3, 1, 0, 0); vk.CmdEndRendering(frame.command_buffer)
	}
	do_capture := backend.capture_requested && ctx.swapchain_supports_transfer_src
	if do_capture {
		byte_count := vk.DeviceSize(extent.width) * vk.DeviceSize(extent.height) * 4
		if backend.capture_buffer.size <
		   byte_count {engine.vk_destroy_buffer(ctx, &backend.capture_buffer); if !engine.vk_create_host_buffer(ctx, byte_count, {.TRANSFER_DST}, &backend.capture_buffer) do do_capture = false}
	}
	if do_capture {
		engine.vk_cmd_image_barrier2(
			ctx,
			frame.command_buffer,
			image,
			{.COLOR_ATTACHMENT_OUTPUT},
			{.TRANSFER},
			{.COLOR_ATTACHMENT_WRITE},
			{.TRANSFER_READ},
			.COLOR_ATTACHMENT_OPTIMAL,
			.TRANSFER_SRC_OPTIMAL,
		)
		region := vk.BufferImageCopy {
			imageSubresource = {aspectMask = {.COLOR}, layerCount = 1},
			imageExtent = {extent.width, extent.height, 1},
		}; vk.CmdCopyImageToBuffer(
			frame.command_buffer,
			image,
			.TRANSFER_SRC_OPTIMAL,
			backend.capture_buffer.handle,
			1,
			&region,
		)
		engine.vk_cmd_image_barrier2(
			ctx,
			frame.command_buffer,
			image,
			{.TRANSFER},
			{.BOTTOM_OF_PIPE},
			{.TRANSFER_READ},
			{},
			.TRANSFER_SRC_OPTIMAL,
			.PRESENT_SRC_KHR,
		)
	} else {engine.vk_cmd_image_barrier2(
			ctx,
			frame.command_buffer,
			image,
			{.COLOR_ATTACHMENT_OUTPUT},
			{.BOTTOM_OF_PIPE},
			{.COLOR_ATTACHMENT_WRITE},
			{},
			.COLOR_ATTACHMENT_OPTIMAL,
			.PRESENT_SRC_KHR,
		)}
	ended := engine.vk_end_frame(ctx, frame); backend.frame_counter += 1
	if do_capture && ended {
		_ = vk.DeviceWaitIdle(
			ctx.device,
		); byte_count := int(extent.width * extent.height * 4); pointer := transmute([^]u8)backend.capture_buffer.mapped; pixels := pointer[:byte_count]
		if engine.screenshot_state_publish_from_gpu_rgba(
			&backend.capture_state,
			pixels,
			extent.width,
			extent.height,
			ctx.swapchain_format,
			backend.frame_counter,
		) {data, _, _, _, encoded := engine.screenshot_state_copy_png(&backend.capture_state, context.temp_allocator); if encoded && os.write_entire_file(backend.capture_path, data) == nil {backend.capture_written = true; backend.capture_requested = false}}
	}
	backend.profile_tail_ms =
		time.duration_seconds(time.tick_diff(tail_started, time.tick_now())) * 1000; return ended
}
