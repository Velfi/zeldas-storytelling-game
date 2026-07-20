package main

import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:time"
import sdl "vendor:sdl3"
import vk "vendor:vulkan"
import engine "zelda_engine:engine"

Camera_Uniform :: struct {
	view_projection: Mat4,
	camera_position: Vec4,
}
Draw_Constants :: struct {
	model:      Mat4,
	base_color: Vec4,
	material:   Vec4,
}
Renderer :: struct {
	vertices, indices, camera: engine.Vk_Buffer,
	descriptor_layout:         vk.DescriptorSetLayout,
	descriptor_pool:           vk.DescriptorPool,
	descriptor_sets:           [dynamic]vk.DescriptorSet,
	textures:                  [dynamic]Gpu_Image,
	depth:                     Gpu_Image,
	ui:                        Ui_Renderer,
	pipeline_layout:           vk.PipelineLayout,
	pipeline:                  vk.Pipeline,
	index_count:               u32,
	ready:                     bool,
}

perspective :: proc(fov, aspect, near, far: f32) -> Mat4 {f := 1 / f32(math.tan(f64(fov) * 0.5))
	return {
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
look_at :: proc(eye, target, up: Vec3) -> Mat4 {f := normalize3(
		{target.x - eye.x, target.y - eye.y, target.z - eye.z},
	)
	s := normalize3({f.y * up.z - f.z * up.y, f.z * up.x - f.x * up.z, f.x * up.y - f.y * up.x})
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

renderer_destroy :: proc(r: ^Renderer, ctx: ^engine.Vk_Context) {if ctx.device != nil do _ = vk.DeviceWaitIdle(ctx.device)
	ui_renderer_destroy(&r.ui, ctx)
	gpu_image_destroy(&r.depth, ctx)
	for &texture in r.textures do gpu_image_destroy(&texture, ctx)
	delete(r.textures)
	delete(r.descriptor_sets)
	if r.pipeline != vk.Pipeline(0) do vk.DestroyPipeline(ctx.device, r.pipeline, nil)
	if r.pipeline_layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(ctx.device, r.pipeline_layout, nil)
	if r.descriptor_pool != vk.DescriptorPool(0) do vk.DestroyDescriptorPool(ctx.device, r.descriptor_pool, nil)
	if r.descriptor_layout != vk.DescriptorSetLayout(0) do vk.DestroyDescriptorSetLayout(ctx.device, r.descriptor_layout, nil)
	engine.vk_destroy_buffer(ctx, &r.camera)
	engine.vk_destroy_buffer(ctx, &r.indices)
	engine.vk_destroy_buffer(ctx, &r.vertices)
	r^ = {}}

renderer_init :: proc(r: ^Renderer, ctx: ^engine.Vk_Context, scene: ^Gltf_Scene) -> bool {
	r^ = {}; if len(scene.vertices) == 0 || len(scene.indices) == 0 do return false
	if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(len(scene.vertices) * size_of(Gltf_Vertex)), {.VERTEX_BUFFER}, &r.vertices) do return false
	if !engine.vk_create_host_buffer(
		ctx,
		vk.DeviceSize(len(scene.indices) * size_of(u32)),
		{.INDEX_BUFFER},
		&r.indices,
	) {renderer_destroy(r, ctx); return false}
	if !engine.vk_create_host_buffer(
		ctx,
		vk.DeviceSize(size_of(Camera_Uniform)),
		{.UNIFORM_BUFFER},
		&r.camera,
	) {renderer_destroy(r, ctx); return false}
	mem.copy_non_overlapping(
		r.vertices.mapped,
		raw_data(scene.vertices[:]),
		len(scene.vertices) * size_of(Gltf_Vertex),
	); mem.copy_non_overlapping(r.indices.mapped, raw_data(scene.indices[:]), len(scene.indices) * size_of(u32)); r.index_count = u32(len(scene.indices))
	bindings := [3]vk.DescriptorSetLayoutBinding {
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
	}; layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 3,
		pBindings    = raw_data(bindings[:]),
	}; if vk.CreateDescriptorSetLayout(ctx.device, &layout_info, nil, &r.descriptor_layout) !=
	   .SUCCESS {renderer_destroy(r, ctx); return false}
	white := [4]u8 {
		255,
		255,
		255,
		255,
	}; fallback: Gpu_Image; if !gpu_texture_upload(ctx, white[:], 1, 1, &fallback) {renderer_destroy(r, ctx); return false}; append(&r.textures, fallback); for source in scene.images {texture: Gpu_Image; if len(source.pixels) > 0 && gpu_texture_upload(ctx, source.pixels[:], source.width, source.height, &texture) {append(&r.textures, texture)} else {append(&r.textures, Gpu_Image{})}}
	set_count := len(
		r.textures,
	); pool_sizes := [3]vk.DescriptorPoolSize{{type = .UNIFORM_BUFFER, descriptorCount = u32(set_count)}, {type = .SAMPLED_IMAGE, descriptorCount = u32(set_count)}, {type = .SAMPLER, descriptorCount = u32(set_count)}}; pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = u32(set_count),
		poolSizeCount = 3,
		pPoolSizes    = raw_data(pool_sizes[:]),
	}; if vk.CreateDescriptorPool(ctx.device, &pool_info, nil, &r.descriptor_pool) !=
	   .SUCCESS {renderer_destroy(r, ctx); return false}
	r.descriptor_sets = make(
		[dynamic]vk.DescriptorSet,
		set_count,
		set_count,
	); layouts := make([]vk.DescriptorSetLayout, set_count, context.temp_allocator); for &layout in layouts do layout = r.descriptor_layout; alloc := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = r.descriptor_pool,
		descriptorSetCount = u32(set_count),
		pSetLayouts        = raw_data(layouts),
	}; if vk.AllocateDescriptorSets(ctx.device, &alloc, raw_data(r.descriptor_sets[:])) !=
	   .SUCCESS {renderer_destroy(r, ctx); return false}
	for descriptor, i in r.descriptor_sets {texture_index := i; if r.textures[texture_index].view == vk.ImageView(0) do texture_index = 0; buffer_info := vk.DescriptorBufferInfo {
			buffer = r.camera.handle,
			offset = 0,
			range  = vk.DeviceSize(size_of(Camera_Uniform)),
		}; image_info := vk.DescriptorImageInfo {
			imageView   = r.textures[texture_index].view,
			imageLayout = .SHADER_READ_ONLY_OPTIMAL,
		}; sampler_info := vk.DescriptorImageInfo {
			sampler = r.textures[texture_index].sampler,
		}; writes := [3]vk.WriteDescriptorSet {
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = descriptor,
				dstBinding = 0,
				descriptorCount = 1,
				descriptorType = .UNIFORM_BUFFER,
				pBufferInfo = &buffer_info,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = descriptor,
				dstBinding = 1,
				descriptorCount = 1,
				descriptorType = .SAMPLED_IMAGE,
				pImageInfo = &image_info,
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = descriptor,
				dstBinding = 2,
				descriptorCount = 1,
				descriptorType = .SAMPLER,
				pImageInfo = &sampler_info,
			},
		}; vk.UpdateDescriptorSets(ctx.device, 3, raw_data(writes[:]), 0, nil)}
	push := vk.PushConstantRange {
		stageFlags = {.VERTEX, .FRAGMENT},
		offset     = 0,
		size       = u32(size_of(Draw_Constants)),
	}; pipeline_layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = 1,
		pSetLayouts            = &r.descriptor_layout,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &push,
	}; if vk.CreatePipelineLayout(ctx.device, &pipeline_layout_info, nil, &r.pipeline_layout) !=
	   .SUCCESS {renderer_destroy(r, ctx); return false}
	vert, frag: engine.Vk_Shader_Module; if !engine.vk_load_shader_module(ctx, "build/shaders/gltf_pbr.vert.spv", &vert) {renderer_destroy(r, ctx); return false}; defer engine.vk_destroy_shader_module(ctx, &vert); if !engine.vk_load_shader_module(ctx, "build/shaders/gltf_pbr.frag.spv", &frag) {renderer_destroy(r, ctx); return false}; defer engine.vk_destroy_shader_module(ctx, &frag)
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
	}
	vertex_binding := vk.VertexInputBindingDescription {
		binding   = 0,
		stride    = u32(size_of(Gltf_Vertex)),
		inputRate = .VERTEX,
	}; attributes := [4]vk.VertexInputAttributeDescription {
		{
			location = 0,
			binding = 0,
			format = .R32G32B32_SFLOAT,
			offset = u32(offset_of(Gltf_Vertex, position)),
		},
		{
			location = 1,
			binding = 0,
			format = .R32G32B32_SFLOAT,
			offset = u32(offset_of(Gltf_Vertex, normal)),
		},
		{
			location = 2,
			binding = 0,
			format = .R32G32_SFLOAT,
			offset = u32(offset_of(Gltf_Vertex, uv)),
		},
		{
			location = 3,
			binding = 0,
			format = .R32G32B32A32_SFLOAT,
			offset = u32(offset_of(Gltf_Vertex, color)),
		},
	}
	vertex_input := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &vertex_binding,
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
	}; multisample := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
	}; color_attachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask = {.R, .G, .B, .A},
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
	}; rendering := engine.vk_pipeline_rendering_info(&ctx.swapchain_format)
	rendering.depthAttachmentFormat = .D32_SFLOAT; depth_state := vk.PipelineDepthStencilStateCreateInfo {
		sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable  = true,
		depthWriteEnable = true,
		depthCompareOp   = .LESS_OR_EQUAL,
	}
	info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &rendering,
		stageCount          = 2,
		pStages             = raw_data(stages[:]),
		pVertexInputState   = &vertex_input,
		pInputAssemblyState = &assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &raster,
		pMultisampleState   = &multisample,
		pDepthStencilState  = &depth_state,
		pColorBlendState    = &blend,
		pDynamicState       = &dynamic_info,
		layout              = r.pipeline_layout,
	}; pipeline_result := vk.CreateGraphicsPipelines(
		ctx.device,
		vk.PipelineCache(0),
		1,
		&info,
		nil,
		&r.pipeline,
	); if pipeline_result != .SUCCESS {fmt.eprintln("vkCreateGraphicsPipelines failed: ", pipeline_result); renderer_destroy(r, ctx); return false}; if !gpu_depth_create(ctx, ctx.swapchain_extent.width, ctx.swapchain_extent.height, &r.depth) {renderer_destroy(r, ctx); return false}; if !ui_renderer_init(&r.ui, ctx, &r.textures[0]) {renderer_destroy(r, ctx); return false}; r.ready = true; return true
}

renderer_draw :: proc(
	r: ^Renderer,
	ctx: ^engine.Vk_Context,
	frame: engine.Vk_Frame,
	scene: ^Gltf_Scene,
	angle: f32,
) {
	extent :=
		ctx.swapchain_extent; if r.depth.width != extent.width || r.depth.height != extent.height {_ = vk.DeviceWaitIdle(ctx.device); gpu_image_destroy(&r.depth, ctx); if !gpu_depth_create(ctx, extent.width, extent.height, &r.depth) do return}; center := Vec3{(scene.min.x + scene.max.x) * .5, (scene.min.y + scene.max.y) * .5, (scene.min.z + scene.max.z) * .5}; radius := max(scene.max.x - scene.min.x, max(scene.max.y - scene.min.y, scene.max.z - scene.min.z)) * .75; if radius < .1 do radius = 1; eye := Vec3{center.x + f32(math.sin(f64(angle))) * radius * 2.5, center.y + radius * .65, center.z + f32(math.cos(f64(angle))) * radius * 2.5}; camera := Camera_Uniform {
		view_projection = mat_mul(
			perspective(
				math.PI / 3,
				f32(extent.width) / f32(max(extent.height, 1)),
				.01,
				radius * 20,
			),
			look_at(eye, center, {0, 1, 0}),
		),
		camera_position = {eye.x, eye.y, eye.z, 1},
	}; mem.copy_non_overlapping(r.camera.mapped, &camera, size_of(camera))
	image :=
		ctx.swapchain_images[frame.image_index]; engine.vk_cmd_image_barrier2(ctx, frame.command_buffer, image, {.TOP_OF_PIPE}, {.COLOR_ATTACHMENT_OUTPUT}, {}, {.COLOR_ATTACHMENT_WRITE}, .PRESENT_SRC_KHR, .COLOR_ATTACHMENT_OPTIMAL); engine.vk_cmd_image_barrier2(ctx, frame.command_buffer, r.depth.image, {.TOP_OF_PIPE}, {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}, {}, {.DEPTH_STENCIL_ATTACHMENT_WRITE}, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL, {.DEPTH})
	color_clear := vk.ClearValue {
		color = {float32 = {.035, .042, .055, 1}},
	}; depth_clear := vk.ClearValue {
		depthStencil = {depth = 1, stencil = 0},
	}; color_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = ctx.swapchain_image_views[frame.image_index],
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .STORE,
		clearValue  = color_clear,
	}; depth_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = r.depth.view,
		imageLayout = .DEPTH_ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .DONT_CARE,
		clearValue  = depth_clear,
	}; render_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {offset = {0, 0}, extent = extent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment,
		pDepthAttachment = &depth_attachment,
	}; vk.CmdBeginRendering(frame.command_buffer, &render_info)
	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(extent.width),
		height   = f32(extent.height),
		minDepth = 0,
		maxDepth = 1,
	}; scissor := vk.Rect2D {
		offset = {0, 0},
		extent = extent,
	}; vk.CmdSetViewport(
		frame.command_buffer,
		0,
		1,
		&viewport,
	); vk.CmdSetScissor(frame.command_buffer, 0, 1, &scissor); vk.CmdBindPipeline(frame.command_buffer, .GRAPHICS, r.pipeline); offset := vk.DeviceSize(0); vk.CmdBindVertexBuffers(frame.command_buffer, 0, 1, &r.vertices.handle, &offset); vk.CmdBindIndexBuffer(frame.command_buffer, r.indices.handle, 0, .UINT32)
	for draw in scene.draws {texture_set := 0; if draw.base_color_texture >= 0 && draw.base_color_texture + 1 < len(r.descriptor_sets) do texture_set = draw.base_color_texture + 1; descriptor := r.descriptor_sets[texture_set]; vk.CmdBindDescriptorSets(frame.command_buffer, .GRAPHICS, r.pipeline_layout, 0, 1, &descriptor, 0, nil); constants := Draw_Constants {
			model      = mat_identity(),
			base_color = draw.base_color,
			material   = {draw.metallic, draw.roughness, 0, draw.base_color_texture >= 0 ? 1 : 0},
		}; vk.CmdPushConstants(
			frame.command_buffer,
			r.pipeline_layout,
			{.VERTEX, .FRAGMENT},
			0,
			u32(size_of(constants)),
			&constants,
		); vk.CmdDrawIndexed(frame.command_buffer, draw.index_count, 1, draw.first_index, 0, 0)}
	ui_begin(
		&r.ui,
	); ui_quad(&r.ui, 18, 18, 300, 76, {.025, .03, .04, .78}); ui_quad(&r.ui, 32, 34, 210, 5, {.88, .72, .36, 1}); ui_quad(&r.ui, 32, 52, 260, 2, {.46, .36, .19, 1}); ui_quad(&r.ui, 32, 68, 180, 2, {.4, .8, .56, 1}); ui_draw(&r.ui, frame.command_buffer, extent)
	vk.CmdEndRendering(
		frame.command_buffer,
	); engine.vk_cmd_image_barrier2(ctx, frame.command_buffer, image, {.COLOR_ATTACHMENT_OUTPUT}, {.BOTTOM_OF_PIPE}, {.COLOR_ATTACHMENT_WRITE}, {}, .COLOR_ATTACHMENT_OPTIMAL, .PRESENT_SRC_KHR)
}

main :: proc() {
	if len(os.args) <
	   2 {fmt.eprintln("usage: build/gltf-viewer <model.glb>"); return}; scene, ok := gltf_load_glb(os.args[1]); if !ok {fmt.eprintln("failed to load glTF 2.0 GLB: ", os.args[1]); return}; defer {delete(scene.vertices); delete(scene.indices); delete(scene.draws); for &source in scene.images do delete(source.pixels); delete(scene.images)}; fmt.println("loaded ", len(scene.vertices), " vertices, ", len(scene.indices) / 3, " triangles, ", len(scene.draws), " primitives, ", len(scene.images), " textures")
	when ODIN_OS == .Darwin {if _, err := os.stat("/opt/homebrew/lib/libvulkan.1.dylib", context.temp_allocator); err == nil do _ = os.set_env("SDL_VULKAN_LIBRARY", "/opt/homebrew/lib/libvulkan.1.dylib")}
	if !sdl.Init(
		{.VIDEO, .EVENTS},
	) {fmt.eprintln(sdl.GetError()); return}; defer sdl.Quit(); window := sdl.CreateWindow("Vulkan + Slang glTF Viewer", 1280, 720, {.VULKAN, .RESIZABLE, .HIGH_PIXEL_DENSITY}); if window == nil {fmt.eprintln(sdl.GetError()); return}; defer sdl.DestroyWindow(window)
	ctx: engine.Vk_Context; if !engine.vk_context_init(&ctx, window, 1280, 720, .7) {fmt.eprintln("Vulkan 1.3 initialization failed"); return}; defer engine.vk_context_destroy(&ctx); renderer: Renderer; if !renderer_init(&renderer, &ctx, &scene) {fmt.eprintln("renderer initialization failed; run `make shaders`"); return}; defer renderer_destroy(&renderer, &ctx)
	running :=
		true; start := time.tick_now(); for running {event: sdl.Event; for sdl.PollEvent(&event) {#partial switch event.type {case .QUIT:
				running = false; case .KEY_DOWN:
				if event.key.scancode == .ESCAPE do running = false; case .WINDOW_PIXEL_SIZE_CHANGED:
				if event.window.data1 > 0 && event.window.data2 > 0 do ctx.needs_swapchain_recreate = true}}
		if ctx.needs_swapchain_recreate {w, h: i32; sdl.GetWindowSizeInPixels(window, &w, &h); if w > 0 && h > 0 do _ = engine.vk_recreate_swapchain(&ctx, w, h); continue}; frame, frame_ok := engine.vk_begin_frame(&ctx); if !frame_ok do continue; angle := f32(time.duration_seconds(time.tick_diff(start, time.tick_now())) * .22); renderer_draw(&renderer, &ctx, frame, &scene, angle); if !engine.vk_end_frame(&ctx, frame) do running = false
	}
}
