## Exercises the production Metal drawer with an offscreen render target.
## Run on macOS with nim r -d:silkyMetalTesting tests/test_metal_texture_pixels.nim.

when defined(macosx) and not defined(ios):
  when not defined(silkyMetalTesting):
    {.error: "Build this test with -d:silkyMetalTesting.".}

  import
    pixie, vmath,
    silky/common, silky/drawers/metal4

  const
    White = ColorRGBX(r: 255, g: 255, b: 255, a: 255)
    Red = ColorRGBX(r: 255, g: 0, b: 0, a: 255)
    Green = ColorRGBX(r: 0, g: 255, b: 0, a: 255)
    Blue = ColorRGBX(r: 0, g: 0, b: 255, a: 255)
    Yellow = ColorRGBX(r: 255, g: 255, b: 0, a: 255)
    Viewport = ivec2(32, 24)

  proc solidImage(width, height: int, color: ColorRGBX): Image =
    ## Creates a premultiplied solid image for a texture upload.
    result = newImage(width, height)
    result.fill(color)

  proc addQuad(
    vertices: var seq[DrawerVertex],
    texture: uint32,
    pos, size, uv: Vec2,
    color = White,
    clipPos = vec2(0, 0),
    clipSize = Viewport.vec2,
    maskUv = vec2(-1, -1)
  ) =
    ## Adds a quad sampling one texel center, avoiding filtered boundaries.
    const Corners = [
      vec2(0, 0), vec2(1, 0), vec2(1, 1),
      vec2(0, 0), vec2(1, 1), vec2(0, 1)
    ]
    for corner in Corners:
      vertices.add(DrawerVertex(
        pos: pos + corner * size,
        uv: uv,
        color: color,
        clipPos: clipPos,
        clipSize: clipSize,
        maskUv: maskUv,
        texture: texture
      ))

  proc checkPixel(
    image: Image,
    x, y: int,
    expected: ColorRGBX,
    message: string
  ) =
    ## Checks GPU output with one byte of permitted rounding per channel.
    let actual = image[x, y]
    doAssert abs(actual.r.int - expected.r.int) <= 1 and
      abs(actual.g.int - expected.g.int) <= 1 and
      abs(actual.b.int - expected.b.int) <= 1 and
      abs(actual.a.int - expected.a.int) <= 1,
      message & ": got " & $actual & ", expected " & $expected

  template expectSilkyError(body: untyped) =
    ## Checks that invalid input fails before issuing native Metal operations.
    block:
      var raised = false
      try:
        body
      except SilkyError:
        raised = true
      doAssert raised, "Expected SilkyError for invalid texture input."

  proc checkBatchOrder() =
    ## Verifies alternating texture batches, dimensions, and painter's order.
    let
      atlas = solidImage(8, 8, White)
      drawer = newOffscreenDrawerForTesting(atlas, Viewport)
      horizontal = solidImage(4, 2, Red)
      vertical = solidImage(2, 4, Blue)
      first = drawer.allocateTexture(4, 2)
      second = drawer.allocateTexture(2, 4)
    defer: drawer.close()
    doAssert first != 0 and second != 0 and first != second
    for y in 0 ..< horizontal.height:
      for x in 2 ..< horizontal.width:
        horizontal[x, y] = Green
    for y in 2 ..< vertical.height:
      for x in 0 ..< vertical.width:
        vertical[x, y] = Yellow
    drawer.uploadTextureRows(first, horizontal, 0, horizontal.height)
    drawer.uploadTextureRows(second, vertical, 0, vertical.height)

    var vertices: seq[DrawerVertex]
    vertices.addQuad(0, vec2(0, 0), Viewport.vec2, vec2(0.5, 0.5))
    vertices.addQuad(first, vec2(0, 0), vec2(24, 24), vec2(3.5, 0.5))
    vertices.addQuad(0, vec2(4, 4), vec2(16, 16), vec2(0.5, 0.5), Red)
    vertices.addQuad(second, vec2(8, 8), vec2(12, 12), vec2(0.5, 3.5))
    vertices.addQuad(0, vec2(12, 12), vec2(4, 4), vec2(0.5, 0.5), Blue)
    let pixels = drawer.renderPixelsForTesting(atlas, vertices)
    pixels.checkPixel(1, 1, Green, "First dynamic texture dimensions")
    pixels.checkPixel(5, 5, Red, "Atlas batch over first dynamic texture")
    pixels.checkPixel(9, 9, Yellow, "Second dynamic texture dimensions")
    pixels.checkPixel(13, 13, Blue, "Final atlas batch remains on top")
    pixels.checkPixel(30, 20, White, "Untouched atlas background")

    drawer.deleteTexture(first)
    drawer.deleteTexture(first)
    drawer.deleteTexture(0)
    let replacement = drawer.allocateTexture(4, 2)
    doAssert replacement != first, "Deleted texture handles must stay stale."
    drawer.uploadTextureRows(replacement, horizontal, 0, horizontal.height)
    vertices.setLen(0)
    vertices.addQuad(0, vec2(0, 0), Viewport.vec2, vec2(0.5, 0.5))
    vertices.addQuad(first, vec2(0, 0), Viewport.vec2, vec2(3.5, 0.5))
    let deletedPixels = drawer.renderPixelsForTesting(atlas, vertices)
    deletedPixels.checkPixel(10, 10, White, "Deleted textures are skipped")

  proc checkRowUploads() =
    ## Verifies partial texture uploads preserve rows outside the update.
    let
      atlas = solidImage(8, 8, White)
      drawer = newOffscreenDrawerForTesting(atlas, Viewport)
      image = solidImage(4, 4, Red)
      texture = drawer.allocateTexture(4, 4)
    defer: drawer.close()
    drawer.uploadTextureRows(texture, image, 0, image.height)
    image.fill(Green)
    drawer.uploadTextureRows(texture, image, 1, 2)
    drawer.uploadTextureRows(texture, image, image.height, 0)
    var vertices: seq[DrawerVertex]
    for row in 0 ..< image.height:
      vertices.addQuad(
        texture,
        vec2(0, row.float32 * 6),
        vec2(32, 6),
        vec2(1.5, row.float32 + 0.5)
      )
    let pixels = drawer.renderPixelsForTesting(atlas, vertices)
    pixels.checkPixel(16, 3, Red, "First row remains unchanged")
    pixels.checkPixel(16, 9, Green, "First uploaded row")
    pixels.checkPixel(16, 15, Green, "Second uploaded row")
    pixels.checkPixel(16, 21, Red, "Last row remains unchanged")

    expectSilkyError:
      discard drawer.allocateTexture(0, 1)
    expectSilkyError:
      discard drawer.allocateTexture(1, -1)
    doAssert drawer.maxTextureSize in [8192, 16384, 32768]
    expectSilkyError:
      discard drawer.allocateTexture(drawer.maxTextureSize + 1, 1)
    expectSilkyError:
      discard drawer.allocateTexture(1, drawer.maxTextureSize + 1)
    expectSilkyError:
      drawer.uploadAtlas(newImage(drawer.maxTextureSize + 1, 1))
    expectSilkyError:
      drawer.uploadTextureRows(0, image, 0, 1)
    expectSilkyError:
      drawer.uploadTextureRows(texture, nil, 0, 1)
    expectSilkyError:
      drawer.uploadTextureRows(texture, newImage(2, 4), 0, 1)
    expectSilkyError:
      drawer.uploadTextureRows(texture, image, -1, 1)
    expectSilkyError:
      drawer.uploadTextureRows(texture, image, 0, -1)
    expectSilkyError:
      drawer.uploadTextureRows(texture, image, 5, 0)
    expectSilkyError:
      drawer.uploadTextureRows(texture, image, 3, 2)

  proc checkAtlasUpdates() =
    ## Verifies clipped atlas regions, unchanged texels, and atlas resizing.
    let
      atlas = solidImage(8, 8, White)
      drawer = newOffscreenDrawerForTesting(atlas, Viewport)
    defer: drawer.close()
    atlas.fill(Red)
    drawer.uploadAtlasRegion(atlas, 2, 2, 2, 2)
    var vertices: seq[DrawerVertex]
    vertices.addQuad(0, vec2(0, 0), vec2(16, 24), vec2(0.5, 0.5))
    vertices.addQuad(0, vec2(16, 0), vec2(16, 24), vec2(2.5, 2.5))
    let firstPixels = drawer.renderPixelsForTesting(atlas, vertices)
    firstPixels.checkPixel(8, 12, White, "Atlas texels outside update")
    firstPixels.checkPixel(24, 12, Red, "Atlas region upload")

    atlas.fill(Green)
    drawer.uploadAtlasRegion(atlas, -2, -2, 4, 4)
    drawer.uploadAtlasRegion(atlas, 40, 40, 2, 2)
    drawer.uploadAtlasRegion(atlas, 2, 2, 0, 2)
    let clippedPixels = drawer.renderPixelsForTesting(atlas, vertices)
    clippedPixels.checkPixel(8, 12, Green, "Clipped atlas update")
    clippedPixels.checkPixel(24, 12, Red, "Clipped update preserves neighbors")

    let resized = solidImage(4, 4, Blue)
    drawer.uploadAtlasRegion(resized, 0, 0, 1, 1)
    let resizedPixels = drawer.renderPixelsForTesting(resized, vertices)
    resizedPixels.checkPixel(8, 12, Blue, "Resized atlas uploads completely")
    resizedPixels.checkPixel(24, 12, Blue, "Resized atlas far texels")
    resized.fill(Yellow)
    drawer.uploadAtlas(resized)
    let replacedPixels = drawer.renderPixelsForTesting(resized, vertices)
    replacedPixels.checkPixel(8, 12, Yellow, "Full atlas replacement")

  proc checkMasksAndClipping() =
    ## Verifies atlas mask and clip state after switching from an image batch.
    let
      atlas = solidImage(8, 8, White)
      drawer = newOffscreenDrawerForTesting(atlas, Viewport)
      image = solidImage(2, 2, Green)
      texture = drawer.allocateTexture(2, 2)
    defer: drawer.close()
    atlas[6, 6] = rgbx(128, 128, 128, 255)
    drawer.uploadAtlasRegion(atlas, 6, 6, 1, 1)
    drawer.uploadTextureRows(texture, image, 0, image.height)
    var vertices: seq[DrawerVertex]
    vertices.addQuad(texture, vec2(0, 0), Viewport.vec2, vec2(0.5, 0.5))
    vertices.addQuad(
      0,
      vec2(0, 0),
      Viewport.vec2,
      vec2(0.5, 0.5),
      Red,
      clipPos = vec2(8, 4),
      clipSize = vec2(16, 16),
      maskUv = vec2(6.5, 6.5)
    )
    let pixels = drawer.renderPixelsForTesting(atlas, vertices)
    pixels.checkPixel(16, 12, rgbx(255, 127, 127, 255), "Atlas tint mask")
    pixels.checkPixel(4, 12, Green, "Left clipping edge")
    pixels.checkPixel(28, 12, Green, "Right clipping edge")
    pixels.checkPixel(16, 2, Green, "Top clipping edge")
    pixels.checkPixel(16, 22, Green, "Bottom clipping edge")

  checkBatchOrder()
  checkRowUploads()
  checkAtlasUpdates()
  checkMasksAndClipping()
  echo "Metal texture pixels passed: batches, uploads, atlas, masks, clipping."
else:
  echo "Skipped Metal texture pixels: requires macOS with a Metal device."
