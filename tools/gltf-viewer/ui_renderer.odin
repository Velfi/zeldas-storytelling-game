package main

import "core:mem"
import engine "zelda_engine:engine"
import vk "vendor:vulkan"

UI_MAX_VERTICES :: 65536
UI_MAX_INDICES :: UI_MAX_VERTICES/4*6

Ui_Vertex :: struct {position,uv:Vec2,color:Vec4}
Ui_Batch :: struct {first_index,index_count:u32,descriptor:vk.DescriptorSet,use_texture:bool,scissor:vk.Rect2D}
Ui_Push :: struct {viewport:Vec2,use_texture,padding:f32}

Ui_Renderer :: struct {
	vertices:[dynamic]Ui_Vertex,
	indices:[dynamic]u32,
	batches:[dynamic]Ui_Batch,
	vertex_buffer,index_buffer:engine.Vk_Buffer,
	descriptor_layout:vk.DescriptorSetLayout,
	descriptor_pool:vk.DescriptorPool,
	descriptor:vk.DescriptorSet,
	pipeline_layout:vk.PipelineLayout,
	pipeline:vk.Pipeline,
	ready:bool,
}

ui_renderer_destroy :: proc(ui:^Ui_Renderer,ctx:^engine.Vk_Context) {
	if ui.pipeline!=vk.Pipeline(0) do vk.DestroyPipeline(ctx.device,ui.pipeline,nil)
	if ui.pipeline_layout!=vk.PipelineLayout(0) do vk.DestroyPipelineLayout(ctx.device,ui.pipeline_layout,nil)
	if ui.descriptor_pool!=vk.DescriptorPool(0) do vk.DestroyDescriptorPool(ctx.device,ui.descriptor_pool,nil)
	if ui.descriptor_layout!=vk.DescriptorSetLayout(0) do vk.DestroyDescriptorSetLayout(ctx.device,ui.descriptor_layout,nil)
	engine.vk_destroy_buffer(ctx,&ui.index_buffer);engine.vk_destroy_buffer(ctx,&ui.vertex_buffer);delete(ui.vertices);delete(ui.indices);delete(ui.batches);ui^={}
}

ui_renderer_init :: proc(ui:^Ui_Renderer,ctx:^engine.Vk_Context,fallback:^Gpu_Image)->bool {
	ui^={};ui.vertices=make([dynamic]Ui_Vertex,0,4096);ui.indices=make([dynamic]u32,0,6144);ui.batches=make([dynamic]Ui_Batch,0,64)
	if !engine.vk_create_host_buffer(ctx,vk.DeviceSize(UI_MAX_VERTICES*size_of(Ui_Vertex)),{.VERTEX_BUFFER},&ui.vertex_buffer) do return false
	if !engine.vk_create_host_buffer(ctx,vk.DeviceSize(UI_MAX_INDICES*size_of(u32)),{.INDEX_BUFFER},&ui.index_buffer) {ui_renderer_destroy(ui,ctx);return false}
	bindings:=[2]vk.DescriptorSetLayoutBinding{{binding=0,descriptorType=.SAMPLED_IMAGE,descriptorCount=1,stageFlags={.FRAGMENT}},{binding=1,descriptorType=.SAMPLER,descriptorCount=1,stageFlags={.FRAGMENT}}};layout_info:=vk.DescriptorSetLayoutCreateInfo{sType=.DESCRIPTOR_SET_LAYOUT_CREATE_INFO,bindingCount=2,pBindings=raw_data(bindings[:])};if vk.CreateDescriptorSetLayout(ctx.device,&layout_info,nil,&ui.descriptor_layout)!=.SUCCESS {ui_renderer_destroy(ui,ctx);return false}
	pool_sizes:=[2]vk.DescriptorPoolSize{{type=.SAMPLED_IMAGE,descriptorCount=1},{type=.SAMPLER,descriptorCount=1}};pool_info:=vk.DescriptorPoolCreateInfo{sType=.DESCRIPTOR_POOL_CREATE_INFO,maxSets=1,poolSizeCount=2,pPoolSizes=raw_data(pool_sizes[:])};if vk.CreateDescriptorPool(ctx.device,&pool_info,nil,&ui.descriptor_pool)!=.SUCCESS {ui_renderer_destroy(ui,ctx);return false};alloc:=vk.DescriptorSetAllocateInfo{sType=.DESCRIPTOR_SET_ALLOCATE_INFO,descriptorPool=ui.descriptor_pool,descriptorSetCount=1,pSetLayouts=&ui.descriptor_layout};if vk.AllocateDescriptorSets(ctx.device,&alloc,&ui.descriptor)!=.SUCCESS {ui_renderer_destroy(ui,ctx);return false}
	image_info:=vk.DescriptorImageInfo{imageView=fallback.view,imageLayout=.SHADER_READ_ONLY_OPTIMAL};sampler_info:=vk.DescriptorImageInfo{sampler=fallback.sampler};writes:=[2]vk.WriteDescriptorSet{{sType=.WRITE_DESCRIPTOR_SET,dstSet=ui.descriptor,dstBinding=0,descriptorCount=1,descriptorType=.SAMPLED_IMAGE,pImageInfo=&image_info},{sType=.WRITE_DESCRIPTOR_SET,dstSet=ui.descriptor,dstBinding=1,descriptorCount=1,descriptorType=.SAMPLER,pImageInfo=&sampler_info}};vk.UpdateDescriptorSets(ctx.device,2,raw_data(writes[:]),0,nil)
	push:=vk.PushConstantRange{stageFlags={.VERTEX,.FRAGMENT},offset=0,size=u32(size_of(Ui_Push))};pipeline_layout_info:=vk.PipelineLayoutCreateInfo{sType=.PIPELINE_LAYOUT_CREATE_INFO,setLayoutCount=1,pSetLayouts=&ui.descriptor_layout,pushConstantRangeCount=1,pPushConstantRanges=&push};if vk.CreatePipelineLayout(ctx.device,&pipeline_layout_info,nil,&ui.pipeline_layout)!=.SUCCESS {ui_renderer_destroy(ui,ctx);return false}
	vert,frag:engine.Vk_Shader_Module;if !engine.vk_load_shader_module(ctx,"build/shaders/ui.vert.spv",&vert) {ui_renderer_destroy(ui,ctx);return false};defer engine.vk_destroy_shader_module(ctx,&vert);if !engine.vk_load_shader_module(ctx,"build/shaders/ui.frag.spv",&frag) {ui_renderer_destroy(ui,ctx);return false};defer engine.vk_destroy_shader_module(ctx,&frag)
	stages:=[2]vk.PipelineShaderStageCreateInfo{{sType=.PIPELINE_SHADER_STAGE_CREATE_INFO,stage={.VERTEX},module=vert.handle,pName="main"},{sType=.PIPELINE_SHADER_STAGE_CREATE_INFO,stage={.FRAGMENT},module=frag.handle,pName="main"}};binding:=vk.VertexInputBindingDescription{binding=0,stride=u32(size_of(Ui_Vertex)),inputRate=.VERTEX};attributes:=[3]vk.VertexInputAttributeDescription{{location=0,binding=0,format=.R32G32_SFLOAT,offset=u32(offset_of(Ui_Vertex,position))},{location=1,binding=0,format=.R32G32_SFLOAT,offset=u32(offset_of(Ui_Vertex,uv))},{location=2,binding=0,format=.R32G32B32A32_SFLOAT,offset=u32(offset_of(Ui_Vertex,color))}};vertex_input:=vk.PipelineVertexInputStateCreateInfo{sType=.PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,vertexBindingDescriptionCount=1,pVertexBindingDescriptions=&binding,vertexAttributeDescriptionCount=3,pVertexAttributeDescriptions=raw_data(attributes[:])};assembly:=vk.PipelineInputAssemblyStateCreateInfo{sType=.PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,topology=.TRIANGLE_LIST};viewport_state:=vk.PipelineViewportStateCreateInfo{sType=.PIPELINE_VIEWPORT_STATE_CREATE_INFO,viewportCount=1,scissorCount=1};raster:=vk.PipelineRasterizationStateCreateInfo{sType=.PIPELINE_RASTERIZATION_STATE_CREATE_INFO,polygonMode=.FILL,cullMode={},frontFace=.COUNTER_CLOCKWISE,lineWidth=1};multisample:=vk.PipelineMultisampleStateCreateInfo{sType=.PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,rasterizationSamples={._1}};color_attachment:=vk.PipelineColorBlendAttachmentState{blendEnable=true,srcColorBlendFactor=.SRC_ALPHA,dstColorBlendFactor=.ONE_MINUS_SRC_ALPHA,colorBlendOp=.ADD,srcAlphaBlendFactor=.ONE,dstAlphaBlendFactor=.ONE_MINUS_SRC_ALPHA,alphaBlendOp=.ADD,colorWriteMask={.R,.G,.B,.A}};blend:=vk.PipelineColorBlendStateCreateInfo{sType=.PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,attachmentCount=1,pAttachments=&color_attachment};dynamic_states:=[2]vk.DynamicState{.VIEWPORT,.SCISSOR};dynamic_info:=vk.PipelineDynamicStateCreateInfo{sType=.PIPELINE_DYNAMIC_STATE_CREATE_INFO,dynamicStateCount=2,pDynamicStates=raw_data(dynamic_states[:])};rendering:=engine.vk_pipeline_rendering_info(&ctx.swapchain_format);info:=vk.GraphicsPipelineCreateInfo{sType=.GRAPHICS_PIPELINE_CREATE_INFO,pNext=&rendering,stageCount=2,pStages=raw_data(stages[:]),pVertexInputState=&vertex_input,pInputAssemblyState=&assembly,pViewportState=&viewport_state,pRasterizationState=&raster,pMultisampleState=&multisample,pColorBlendState=&blend,pDynamicState=&dynamic_info,layout=ui.pipeline_layout};if vk.CreateGraphicsPipelines(ctx.device,vk.PipelineCache(0),1,&info,nil,&ui.pipeline)!=.SUCCESS {ui_renderer_destroy(ui,ctx);return false};ui.ready=true;return true
}

ui_begin :: proc(ui:^Ui_Renderer) {clear(&ui.vertices);clear(&ui.indices);clear(&ui.batches)}

ui_quad :: proc(ui:^Ui_Renderer,x,y,w,h:f32,color:Vec4,uv0:=Vec2{},uv1:=Vec2{1,1},textured:=false,scissor:=vk.Rect2D{offset={0,0},extent={0xffffffff,0xffffffff}}) {
	if len(ui.vertices)+4>UI_MAX_VERTICES||len(ui.indices)+6>UI_MAX_INDICES do return;base:=u32(len(ui.vertices));append(&ui.vertices,Ui_Vertex{{x,y},{uv0.x,uv0.y},color},Ui_Vertex{{x+w,y},{uv1.x,uv0.y},color},Ui_Vertex{{x+w,y+h},{uv1.x,uv1.y},color},Ui_Vertex{{x,y+h},{uv0.x,uv1.y},color});first:=u32(len(ui.indices));append(&ui.indices,base,base+1,base+2,base,base+2,base+3);append(&ui.batches,Ui_Batch{first,6,ui.descriptor,textured,scissor})
}

ui_draw :: proc(ui:^Ui_Renderer,cmd:vk.CommandBuffer,extent:vk.Extent2D) {
	if !ui.ready||len(ui.vertices)==0 do return;mem.copy_non_overlapping(ui.vertex_buffer.mapped,raw_data(ui.vertices[:]),len(ui.vertices)*size_of(Ui_Vertex));mem.copy_non_overlapping(ui.index_buffer.mapped,raw_data(ui.indices[:]),len(ui.indices)*size_of(u32));viewport:=vk.Viewport{x=0,y=0,width=f32(extent.width),height=f32(extent.height),minDepth=0,maxDepth=1};vk.CmdSetViewport(cmd,0,1,&viewport);vk.CmdBindPipeline(cmd,.GRAPHICS,ui.pipeline);offset:=vk.DeviceSize(0);vk.CmdBindVertexBuffers(cmd,0,1,&ui.vertex_buffer.handle,&offset);vk.CmdBindIndexBuffer(cmd,ui.index_buffer.handle,0,.UINT32)
	for batch in ui.batches {scissor:=batch.scissor;if scissor.extent.width==0xffffffff do scissor={offset={0,0},extent=extent};vk.CmdSetScissor(cmd,0,1,&scissor);descriptor:=batch.descriptor;vk.CmdBindDescriptorSets(cmd,.GRAPHICS,ui.pipeline_layout,0,1,&descriptor,0,nil);push:=Ui_Push{{f32(extent.width),f32(extent.height)},batch.use_texture?1:0,0};vk.CmdPushConstants(cmd,ui.pipeline_layout,{.VERTEX,.FRAGMENT},0,u32(size_of(push)),&push);vk.CmdDrawIndexed(cmd,batch.index_count,1,batch.first_index,0,0)}
}
