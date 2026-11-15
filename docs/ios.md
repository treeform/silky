# iOS Metal integration

The iOS drawer uses the same Nim `silkyVert` and `silkyFrag` shader procedures
as the other backends. Shady translates them to MSL during the Nim build, and
Metal compiles the generated source when the drawer is created. Select this
drawer with `-d:useMetal4` and compile for iOS with `--os:ios --cpu:arm64`.

The `windy-ios`, `silky-ios`, `shady-ios`, and `metal4-ios` worktrees must be
on the Nim import path. Use `--skipParentCfg` when a parent Nim configuration
points at desktop checkouts. No Shady source changes are required for the
current Silky shaders.

## Application setup

Create the Windy window in its `runApplication` startup callback. Create
Silky in the first `window.onFrame` callback, after the native Metal view
exists. Run `beginUI(window, window.size)` and `endUI()` once per frame.
UIKit drives the event loop. There is no `pollEvents` loop or OpenGL buffer
swap in an iOS application.

Windy's iOS platform owns the UIKit app and scene delegates, MetalKit view
and input callbacks. These are implemented in Nim using Windy's shared Apple
Objective-C runtime bindings. A small C entry point starts Nim, and a tiny
Objective-C bridge references the SDK protocol metadata. GLFM is a design
reference only; it is not compiled or linked into the app.

Windy reports drawable sizes and pointer positions in pixels. Set
`sk.uiScale = window.contentScale` before `beginUI` for a point-sized UI,
and use `sk.size` for the resulting logical layout dimensions. Account for
the device's safe area when positioning controls.

Generate the atlas on the host and bundle its PNG with the application.
The PNG includes the font metrics and sprite metadata, so the device does
not need the original fonts or skin files. For the example skin, add
`examples/basicwindow/data/` with that directory as the removed prefix,
then add `IBMPlexSans-Regular.ttf` as `Default` and `H1` before writing the
atlas. `newSilky(window, atlasPngPath)` loads the packaged atlas.

Pass `pixelScale = 2` or `pixelScale = 3` to `addFont` when generating
Retina atlases. Font size, advances, kerning and line metrics stay in
logical points, while glyph pixels are rasterized at the requested
density. Select the matching atlas for the window's content scale and
keep `sk.uiScale = window.contentScale`. The text renderer uses physical
atlas coordinates and snaps glyph origins to that raster's pixel grid.
Older atlas files without density metadata continue to use 1x glyphs.
Raster image and button skin assets have their own density requirements.

## Shader bindings

The generated entry points are `vertexMain` and `fragmentMain`. Vertex
buffer 0 contains two `Vec2` uniforms: viewport size at byte 0 and atlas
size at byte 8. Vertex buffer 1 contains packed 48-byte `DrawerVertex`
values. Attributes 0 through 5 are position, UV, color, clip position,
clip size, and mask UV. The color attribute uses `UChar4Normalized`; the
other attributes use `Float2`. The atlas texture and sampler use fragment
index 0. The final `uint32` is a CPU texture handle used for batching;
it is not a shader attribute. Zero selects the atlas. Each contiguous
texture batch receives the bound texture's size in the uniform buffer.

Positions and atlas coordinates stay in pixels until the generated shader
transforms them. This also applies to tint-mask coordinates. The fragment
shader uses interpolated pixel positions for clipping.

## Current scope

The drawer renders atlas images, independent images, text, clipping, tint
masks, rich documents, and Silky controls. It uses the ordinary Metal API exposed by the `metal4` Nim
package, without requiring Apple's newer Metal 4 GPU features.

Each frame waits for GPU completion before reusing the shared vertex
buffer. This keeps the first port correct and reports command errors, but
does not overlap CPU and GPU work. A bounded set of buffers can replace
this synchronization after profiling. Runtime atlas changes are uploaded
through `uploadAtlas`, or `uploadAtlasRegion` for a changed rectangle.

Use `allocateTexture`, `uploadTextureRows`, `drawTexture` and `deleteTexture`
for images that should not consume font atlas space. Upload all image rows
before drawing the texture. Batches preserve the original layer and draw
order, including when atlas controls and independent images alternate.
Call the drawer's `close` after rendering has stopped to release its GPU
resources. Closing a drawer does not destroy Windy's UIKit view.

Atlas icons and skins accept an integer `pixelScale` through `addImage`,
`addDir` and `addDirRecursive`. Their physical texture sizes remain intact;
layout uses the corresponding logical dimensions.

Silky accepts Windy's text commits and range-based native edits, and publishes
focused text, selection and caret geometry through `TextInputState`. The
platform owns the software keyboard and composition interface. Accessibility,
multitouch gestures and remote development transport remain separate Windy
and application milestones.

## Verification

The native UIKit simulator demo verified Retina rendering, button taps,
software keyboard presentation, text insertion, single-character deletion,
keyboard dismissal and portrait/landscape resizing at 3x scale. Signed arm64
builds passed strict code signature verification. Background/resume kept the
same process and preserved edited text and the counter. Both native demos
are signed and installed on an iPhone 14 Pro. The locked phone blocked
launch, so native device runtime verification awaits an unlocked device.
The earlier prototype's rendering, touch and Retina text were verified on
that phone.

`tests/test_shader_codegen.nim` checks generated MSL resource slots and
uniform layout alongside the existing GLSL and HLSL checks.
`tests/test_metal_shader_pixels.nim` compiles the generated shaders on
macOS, links the pipeline with Silky's packed vertex layout, renders to an
offscreen texture, and verifies colors, tint masks, and clipping by pixel
readback. This host test uses Metal's runtime compiler and does not need
the optional Xcode MetalToolchain download.

`tests/test_metal_texture_pixels.nim`, built with `-d:silkyMetalTesting`,
exercises the production drawer's allocation, row uploads, atlas rectangles,
texture growth, batching, stale handles, clipping and tint masks. It renders
offscreen on macOS and checks the actual GPU pixels. `test_inputs`,
`test_cursor_scroll` and `test_rendering`, built with `-d:silkyTesting`, cover
native edit ordering, parent scrolling and on-demand frame scheduling.

`tests/test_retina_atlas.nim` checks unchanged logical metrics at 1x, 2x
and 3x, compares 3x glyph pixels against a physical-size reference,
roundtrips density metadata, loads old metadata and checks that runtime
atlas additions preserve the full glyph rectangles.
