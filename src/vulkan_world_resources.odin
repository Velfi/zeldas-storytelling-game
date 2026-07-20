package main

import "core:mem"
import vk "vendor:vulkan"
import engine "zelda_engine:engine"
import resources "zelda_engine:render_resources"

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
