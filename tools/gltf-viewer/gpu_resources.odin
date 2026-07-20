package main

import engine "zelda_engine:engine"
import resources "zelda_engine:render_resources"

Gpu_Image :: resources.Image

gpu_image_destroy :: proc(image: ^Gpu_Image, ctx: ^engine.Vk_Context) {resources.image_destroy(
		image,
		ctx,
	)}
gpu_depth_create :: proc(
	ctx: ^engine.Vk_Context,
	width, height: u32,
	out: ^Gpu_Image,
) -> bool {return resources.depth_create(ctx, width, height, out)}
gpu_texture_upload :: proc(
	ctx: ^engine.Vk_Context,
	pixels: []u8,
	width, height: int,
	out: ^Gpu_Image,
) -> bool {return resources.texture_upload_rgba8(ctx, pixels, width, height, out)}
