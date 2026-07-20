# Vulkan + Slang glTF renderer

The standalone viewer and game use the same Vulkan rendering architecture. The game no longer contains an SDL drawing or software-rendering path.

Both targets import `zelda_engine:render_resources` for image allocation, depth
attachments, RGBA8 texture upload, sampler creation, and cleanup. Pipeline and
descriptor construction remains target-specific because the viewer and game
use different vertex formats, bindings, and render passes.

## Build

Install a current `slangc`, then run:

```sh
make gltf-viewer
build/gltf-viewer path/to/model.glb
```

The shader build targets Vulkan-compatible SPIR-V 1.5, which is accepted by
both native Vulkan 1.3 drivers and MoltenVK. Slang 2026 emits the SPIR-V entry
point as `main`; pipeline stages intentionally bind that emitted name. The
runtime uses the existing `zelda-engine` Vulkan 1.3 backend (dynamic rendering
and synchronization2) through SDL3.

## Current foundation

- Vulkan 1.3 swapchain and frame synchronization
- Slang vertex/fragment pipeline compiled to SPIR-V
- glTF 2.0 binary `.glb` parsing through `zelda_engine:gltf`
- scene/node transforms and indexed triangle primitives
- POSITION, NORMAL, TEXCOORD_0, COLOR_0 and generated normals
- embedded and external PNG base-color textures
- staging-buffer texture upload into device-local sRGB images
- reusable image views and nearest/repeat samplers
- per-material texture descriptor sets with a white fallback texture
- base-color factor and texture sampling plus metallic/roughness direct lighting
- perspective-correct GPU interpolation of normals and UVs
- back-face culling
- a resize-aware D32 depth attachment with depth testing and depth writes
- dynamic rendering and resize-safe swapchain/depth recreation
- explicit ownership and cleanup for buffers, images, memory, views, samplers,
  descriptors, pipelines, and shader modules

The GPU renderer is the production renderer. SDL is used only for portable
window, Vulkan-surface, event, and gamepad integration.

## Render flow

1. Parse the GLB scene graph and flatten node transforms into GPU vertices.
2. Preserve authored normals and UVs, generating normals only when absent.
3. Decode embedded or model-relative base-color images as RGBA8.
4. Upload immutable vertex, index, and texture resources.
5. Allocate a color swapchain attachment and D32 depth attachment.
6. Bind camera uniforms and per-material texture descriptors.
7. Submit indexed primitives with model/material push constants.
8. Let Vulkan perform clipping, perspective interpolation, back-face culling,
   and per-fragment depth testing.

## Integration boundary

The game creates an `SDL_WINDOW_VULKAN` window, uploads each GLB mesh and texture
once, submits lightweight world instances, then records its UI after the depth-
tested world draws. Existing city collision, vehicle simulation, and
StoryCore and MysteryDomain state remain independent of rendering.

## Remaining production features

- alpha-mask and alpha-blend pipelines
- metallic-roughness, normal, occlusion, and emissive textures
- mipmap generation and anisotropic filtering
- directional shadows and image-based lighting
- GPU mesh/texture caches and instanced city draws
- skinning, animation, and morph targets
- `.gltf` external/data-URI buffers
- KTX2/BasisU and remaining ratified material extensions
