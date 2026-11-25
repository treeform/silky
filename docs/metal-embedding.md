# Embedding Silky in a Metal renderer

Build the application with `-d:useMetal4`. Applications that already own a
Metal device and frame can supply an external drawer to `newSilky`:

```nim
import pixie, silky, silky/drawers/metal4
import pkg/metal4 as metal

let
  atlasData = readAtlas("atlas.png")
  drawer = newDrawer(device, atlasData.image, window.size)
  sk = newSilky(window, atlasData.image, atlasData.atlas, drawer)
```

The application owns `device`, its command queue, its window's Metal layer,
and frame submission. The external drawer does not create a layer or queue.
Call `drawer.close()` after outstanding GPU work completes, before releasing
the device. The ordinary `newSilky` constructors still own their frame when
no drawer is supplied.

For each UI pass, end the application's current render encoder and select
the destination before calling `sk.endUi()`:

```nim
sk.beginUi(window, window.size)
# Build the UI with the normal Silky drawing and widget APIs.
drawer.setExternalFrame(commandBuffer, colorTexture)
sk.endUi()
# Encode any remaining application passes, then present and commit once.
```

Silky creates a separate color-only render pass with `MTLLoadActionLoad`,
preserving the application's existing pixels. It does not clear, present,
commit, or wait. `clearScreen` has no effect on external targets; clear them
in the application's own pass. Set the external frame before every `endUi`.
The target dimensions set the UI viewport, including after a resize.

The command buffer and target must use the supplied device. The command
buffer must be uncommitted and retain its resources. The target must have
one sample and match the drawer's pixel format, which defaults to
`MTLPixelFormatBGRA8Unorm`. Pass `pixelFormat = MTLPixelFormatRGBA8Unorm`
to `newDrawer` for an RGBA target. Resolve multisample scene rendering before
the UI pass.

Each UI pass uses a separate vertex buffer, so multiple passes may share
one command buffer without overwriting earlier vertex data. Atlas and
independent image textures remain mutable resources: complete pending GPU
work before changing pixels that earlier passes still need.

`drawer.atlasTexture()` returns the current borrowed Metal atlas texture for
application shaders. Read it again after atlas uploads because atlas growth
can replace the texture. Retain it explicitly if the application stores it
beyond the drawer's lifetime.

## Offscreen drawing during a UI frame

Use `sk.isolatedDrawing(bounds):` to bake images while the current UI frame
already has queued geometry. The scope is available on every rendering backend:

```nim
sk.isolatedDrawing(rect(0, 0, width.float32, height.float32)):
  # Queue the image's rectangles, text, and atlas sprites here.
  # Flush these queues to the offscreen target before leaving this scope.
```

The scope starts with empty queues on the normal layer and an independent root
layout and clip rectangle. It restores the caller's queues, layer stack, layout,
and deferred clip captures when the body exits, including after an exception.
Scopes can nest. This keeps an offscreen bake from changing the placement of a
surrounding deferred layout such as a `hug()` group.

This is a drawing scope, not another UI frame. Use drawing procedures inside it
and flush through the drawer; do not call `beginUi` or `endUi`, start another
`ui` DSL block, or process interactive widgets. The application still owns GPU
target selection and submission, and must restore its previous target itself.
