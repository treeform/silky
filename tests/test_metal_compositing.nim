## Exercises Metal UI compositing into an externally owned command buffer.
## Run on macOS with nim r -d:useMetal4 tests/test_metal_compositing.nim.

when defined(useMetal4) and (defined(macosx) or defined(ios)):
  import
    pixie, vmath,
    pkg/metal4 as gpu,
    silky, silky/common, silky/drawers/metal4 as drawers

  const
    White = ColorRGBX(r: 255, g: 255, b: 255, a: 255)
    Red = ColorRGBX(r: 255, g: 0, b: 0, a: 255)
    Blue = ColorRGBX(r: 0, g: 0, b: 255, a: 255)
    HalfGreen = ColorRGBX(r: 0, g: 128, b: 0, a: 128)

  objc:
    proc commandBufferWithUnretainedReferences(
      self: MTLCommandQueue
    ): MTLCommandBuffer

  template expectSilkyError(message: string, body: untyped) =
    ## Requires invalid embedding input to report a library-specific error.
    block:
      var rejected = false
      try:
        body
      except SilkyError:
        rejected = true
      doAssert rejected, message

  proc newTarget(
      device: MTLDevice,
      size: IVec2,
      pixelFormat: MTLPixelFormat
  ): MTLTexture =
    ## Creates a CPU-readable color target without a window or drawable layer.
    let descriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
      pixelFormat,
      size.x.uint,
      size.y.uint,
      false
    )
    descriptor.setUsage(MTLTextureUsageRenderTarget)
    descriptor.setStorageMode(MTLStorageModeShared)
    result = device.newTextureWithDescriptor(descriptor)
    checkNil(result, "Could not create the external render target")

  proc encodeBackground(commandBuffer: MTLCommandBuffer, target: MTLTexture) =
    ## Models the scene pass that has already rendered behind the UI.
    let
      pass = MTLRenderPassDescriptor.renderPassDescriptor()
      color = pass.colorAttachments().objectAtIndexedSubscript(0)
    color.setTexture(target)
    color.setLoadAction(MTLLoadActionClear)
    color.setStoreAction(MTLStoreActionStore)
    color.setClearColor(MTLClearColor(red: 0, green: 0, blue: 1, alpha: 1))
    let encoder = commandBuffer.renderCommandEncoderWithDescriptor(pass)
    checkNil(encoder, "Could not begin the scene pass")
    encoder.endEncoding()

  proc quad(position, size, clipSize: Vec2, color: ColorRGBX):
      array[6, DrawerVertex] =
    ## Builds a solid UI rectangle sampling the center of the white atlas.
    const Corners = [
      vec2(0, 0), vec2(1, 0), vec2(1, 1),
      vec2(0, 0), vec2(1, 1), vec2(0, 1)
    ]
    for index, corner in Corners:
      result[index] = DrawerVertex(
        pos: position + corner * size,
        uv: vec2(0.5),
        color: color,
        clipPos: vec2(0),
        clipSize: clipSize,
        maskUv: vec2(-1),
        texture: 0
      )

  proc readPixels(target: MTLTexture, size: IVec2,
      pixelFormat: MTLPixelFormat, mipmapLevel = 0'u): Image =
    ## Reads the completed target into ordinary RGBA image storage.
    result = newImage(size.x.int, size.y.int)
    target.getBytes(
      result.data[0].addr,
      (size.x.int * sizeof(ColorRGBX)).uint,
      MTLRegion(
        origin: MTLOrigin(x: 0, y: 0, z: 0),
        size: MTLSize(width: size.x.uint, height: size.y.uint, depth: 1)
      ),
      mipmapLevel
    )
    if pixelFormat == MTLPixelFormatBGRA8Unorm:
      for pixel in result.data.mitems:
        swap(pixel.r, pixel.b)

  proc checkPixel(image: Image, x, y: int, expected: ColorRGBX,
      message: string) =
    ## Permits one byte of blend rounding on each color channel.
    let actual = image[x, y]
    doAssert abs(actual.r.int - expected.r.int) <= 1 and
      abs(actual.g.int - expected.g.int) <= 1 and
      abs(actual.b.int - expected.b.int) <= 1 and
      abs(actual.a.int - expected.a.int) <= 1,
      message & ": got " & $actual & ", expected " & $expected

  proc checkComposite(device: MTLDevice, queue: MTLCommandQueue,
      pixelFormat: MTLPixelFormat) =
    ## Checks scene retention and independent UI uploads before one commit.
    let
      atlas = newImage(2, 2)
      initialSize = ivec2(32, 24)
    atlas.fill(White)
    let drawer = newDrawer(
      device,
      atlas,
      initialSize,
      pixelFormat = pixelFormat
    )
    defer: drawer.close()
    for size in [initialSize, ivec2(56, 40)]:
      let
        target = device.newTarget(size, pixelFormat)
        commandBuffer = queue.commandBuffer()
        first = quad(
          vec2(2),
          vec2(size.x.float32 * 0.75'f - 2, size.y.float32 - 4),
          size.vec2,
          Red
        )
        second = quad(
          vec2(size.x.float32 * 0.5'f, 2),
          vec2(size.x.float32 * 0.5'f - 2, size.y.float32 * 0.5'f - 2),
          size.vec2,
          HalfGreen
        )
      defer: target.release()
      checkNil(commandBuffer, "Could not create the external command buffer")
      commandBuffer.encodeBackground(target)
      drawer.setExternalFrame(commandBuffer, target)
      drawer.endFrame(atlas, size.vec2, unsafeAddr first[0], first.len)
      doAssert commandBuffer.status() == MTLCommandBufferStatusNotEnqueued,
        "The UI must leave command-buffer submission to its owner"
      drawer.setExternalFrame(commandBuffer, target)
      drawer.endFrame(atlas, size.vec2, unsafeAddr second[0], second.len)
      doAssert commandBuffer.status() == MTLCommandBufferStatusNotEnqueued,
        "A second UI pass must remain in the same uncommitted buffer"

      expectSilkyError("Each UI pass must receive an explicit target"):
        drawer.endFrame(atlas, size.vec2, nil, 0)

      commandBuffer.commit()
      commandBuffer.waitUntilCompleted()
      checkNSError(commandBuffer.error(), "External UI compositing failed")
      let pixels = target.readPixels(size, pixelFormat)
      pixels.checkPixel(0, 0, Blue, "Scene background survives the UI")
      pixels.checkPixel(3, size.y.int div 4, Red,
        "The first UI pass retains its vertices after the second upload")
      pixels.checkPixel(size.x.int * 5 div 8, size.y.int div 4,
        rgbx(127, 128, 0, 255), "Alpha blending over the first UI pass")
      pixels.checkPixel(size.x.int - 3, size.y.int div 4,
        rgbx(0, 128, 127, 255), "Alpha blending over the scene")
      pixels.checkPixel(size.x.int - 3, size.y.int - 3, Blue,
        "The resized viewport retains uncovered scene pixels")

  proc checkAtlasMipmaps(device: MTLDevice, queue: MTLCommandQueue) =
    ## Checks prepared mip averages and regeneration after partial atlas edits.
    const
      Purple = ColorRGBX(r: 128, g: 0, b: 128, a: 255)
      Green = ColorRGBX(r: 0, g: 255, b: 0, a: 255)
      Mixed = ColorRGBX(r: 96, g: 64, b: 96, a: 255)
    let
      atlas = newImage(4, 4)
      size = ivec2(8, 8)
    for y in 0 ..< atlas.height:
      for x in 0 ..< atlas.width:
        atlas[x, y] = if (x + y) mod 2 == 0: Red else: Blue
    let drawer = newDrawer(device, atlas, size)
    defer: drawer.close()
    doAssert drawer.needsAtlasPreparation(),
      "A newly uploaded mipmapped atlas must report pending preparation"
    let texture = drawer.atlasTexture()
    doAssert texture.mipmapLevelCount() == 3,
      "The atlas must allocate every mip level down to 1x1"
    let initialCommands = queue.commandBuffer()
    checkNil(initialCommands, "Could not create the atlas command buffer")
    drawer.prepareAtlas(initialCommands)
    doAssert not drawer.needsAtlasPreparation(),
      "Recorded mipmap work must not require another encoder break"
    drawer.prepareAtlas(initialCommands)
    doAssert initialCommands.status() == MTLCommandBufferStatusNotEnqueued,
      "Atlas preparation must leave submission to the application"
    initialCommands.commit()
    initialCommands.waitUntilCompleted()
    checkNSError(initialCommands.error(), "Initial atlas mipmaps failed")
    let
      initialMip = texture.readPixels(
        ivec2(2),
        MTLPixelFormatRGBA8Unorm,
        1
      )
      initialLastMip = texture.readPixels(
        ivec2(1),
        MTLPixelFormatRGBA8Unorm,
        2
      )
    for y in 0 ..< 2:
      for x in 0 ..< 2:
        initialMip.checkPixel(x, y, Purple, "Mip one averages atlas texels")
    initialLastMip.checkPixel(0, 0, Purple, "The last mip averages the atlas")

    for y in 0 ..< 2:
      for x in 0 ..< 2:
        atlas[x, y] = Green
    drawer.uploadAtlasRegion(atlas, 0, 0, 2, 2)
    doAssert drawer.needsAtlasPreparation(),
      "Partial atlas uploads must invalidate the preparation query"
    let updateCommands = queue.commandBuffer()
    checkNil(updateCommands, "Could not create the atlas update buffer")
    drawer.prepareAtlas(updateCommands)
    doAssert not drawer.needsAtlasPreparation(),
      "Partial atlas preparation must become clean after encoding"
    doAssert updateCommands.status() == MTLCommandBufferStatusNotEnqueued,
      "Preparing changed atlas pixels must not submit the command buffer"
    updateCommands.commit()
    updateCommands.waitUntilCompleted()
    checkNSError(updateCommands.error(), "Partial atlas mipmaps failed")
    let
      updatedMip = texture.readPixels(
        ivec2(2),
        MTLPixelFormatRGBA8Unorm,
        1
      )
      updatedLastMip = texture.readPixels(
        ivec2(1),
        MTLPixelFormatRGBA8Unorm,
        2
      )
    updatedMip.checkPixel(0, 0, Green, "A partial upload regenerates its mip")
    updatedMip.checkPixel(1, 1, Purple, "Unchanged mip regions are preserved")
    updatedLastMip.checkPixel(
      0,
      0,
      Mixed,
      "The last mip includes partial edits"
    )

    atlas.fill(Red)
    drawer.uploadAtlas(atlas)
    doAssert drawer.needsAtlasPreparation(),
      "Full atlas uploads must invalidate the preparation query"
    let target = device.newTarget(size, MTLPixelFormatBGRA8Unorm)
    defer: target.release()
    let
      frameCommands = queue.commandBuffer()
      vertices = quad(vec2(0), size.vec2, size.vec2, White)
    checkNil(frameCommands, "Could not create the mipmap frame buffer")
    frameCommands.encodeBackground(target)
    drawer.setExternalFrame(frameCommands, target)
    drawer.endFrame(atlas, size.vec2, unsafeAddr vertices[0], vertices.len)
    doAssert frameCommands.status() == MTLCommandBufferStatusNotEnqueued,
      "Automatic atlas preparation must not submit the UI frame"
    frameCommands.commit()
    frameCommands.waitUntilCompleted()
    checkNSError(frameCommands.error(), "Automatic atlas mipmaps failed")
    let
      finalMip = drawer.atlasTexture().readPixels(
        ivec2(1),
        MTLPixelFormatRGBA8Unorm,
        2
      )
      rendered = target.readPixels(size, MTLPixelFormatBGRA8Unorm)
    finalMip.checkPixel(0, 0, Red, "EndFrame regenerates dirty atlas mipmaps")
    rendered.checkPixel(4, 4, Red, "The UI samples the updated atlas")

    expectSilkyError("Atlas preparation must reject a missing buffer"):
      drawer.prepareAtlas(0.MTLCommandBuffer)
    expectSilkyError("Atlas preparation must reject a submitted buffer"):
      drawer.prepareAtlas(frameCommands)
    let unretained = queue.commandBufferWithUnretainedReferences()
    checkNil(unretained, "Could not create the unretained validation buffer")
    expectSilkyError("Atlas preparation requires retained GPU resources"):
      drawer.prepareAtlas(unretained)

  proc checkEmptyFrames(device: MTLDevice, queue: MTLCommandQueue) =
    ## Checks empty UI preserves the scene and still prepares changed atlases.
    let
      atlas = newImage(2, 2)
      size = ivec2(8, 8)
    atlas.fill(Red)
    let drawer = newDrawer(device, atlas, size)
    defer: drawer.close()
    when defined(silkyMetalTesting):
      let initialWork = drawer.recordedWorkForTesting()
    for atlasSize in [2, 4]:
      let image = newImage(atlasSize, atlasSize)
      image.fill(Red)
      let
        target = device.newTarget(size, MTLPixelFormatBGRA8Unorm)
        commandBuffer = queue.commandBuffer()
      defer: target.release()
      checkNil(commandBuffer, "Could not create the empty UI command buffer")
      commandBuffer.encodeBackground(target)
      for _ in 0 .. 1:
        drawer.setExternalFrame(commandBuffer, target)
        drawer.endFrame(image, size.vec2, nil, 0)
        doAssert not drawer.needsAtlasPreparation(),
          "Empty UI must prepare initial and resized atlas mipmaps"
        doAssert commandBuffer.status() == MTLCommandBufferStatusNotEnqueued,
          "Empty UI must leave submission to the application"
        when defined(silkyMetalTesting):
          doAssert drawer.recordedWorkForTesting() == initialWork,
            "Empty UI must not allocate vertex buffers or open render passes"
      expectSilkyError("An empty UI pass must release its borrowed frame"):
        drawer.endFrame(image, size.vec2, nil, 0)
      commandBuffer.commit()
      commandBuffer.waitUntilCompleted()
      checkNSError(commandBuffer.error(), "Empty UI compositing failed")
      let pixels = target.readPixels(size, MTLPixelFormatBGRA8Unorm)
      for y in 0 ..< size.y.int:
        for x in 0 ..< size.x.int:
          pixels.checkPixel(x, y, Blue, "Empty UI must preserve every scene pixel")
      let mip = drawer.atlasTexture().readPixels(
        ivec2(1),
        MTLPixelFormatRGBA8Unorm,
        if atlasSize == 2: 1'u else: 2'u
      )
      mip.checkPixel(0, 0, Red, "Empty UI must prepare the full atlas mip chain")

    let singleTexel = newImage(1, 1)
    singleTexel.fill(White)
    drawer.uploadAtlas(singleTexel)
    doAssert drawer.needsAtlasPreparation(),
      "An external single-level atlas must stage its initial upload"
    let singleCommands = queue.commandBuffer()
    drawer.prepareAtlas(singleCommands)
    doAssert not drawer.needsAtlasPreparation(),
      "A prepared single-level atlas must not require mipmap work"
    singleTexel.fill(Red)
    drawer.uploadAtlasRegion(singleTexel, 0, 0, 1, 1)
    doAssert drawer.needsAtlasPreparation(),
      "A single-level atlas update must be ordered after earlier draws"
    drawer.prepareAtlas(singleCommands)
    doAssert not drawer.needsAtlasPreparation(),
      "A prepared single-level atlas update must become clean"
    singleCommands.commit()
    singleCommands.waitUntilCompleted()
    checkNSError(singleCommands.error(), "Single-level atlas uploads failed")
    let singlePixel = drawer.atlasTexture().readPixels(
      ivec2(1),
      MTLPixelFormatRGBA8Unorm
    )
    singlePixel.checkPixel(0, 0, Red, "Single-level uploads execute in order")

  proc checkQueuedUploads(device: MTLDevice, queue: MTLCommandQueue) =
    ## Preserves atlas, image, and vertex contents across queued UI frames.
    const Colors = [Red, HalfGreen, White]
    let
      initialAtlas = newImage(2, 2)
      image = newImage(2, 2)
      size = ivec2(12, 8)
    initialAtlas.fill(White)
    let drawer = newDrawer(
      device,
      initialAtlas,
      size,
      pixelFormat = MTLPixelFormatRGBA8Unorm
    )
    defer: drawer.close()
    let imageId = drawer.allocateTexture(2, 2)
    var
      commands: seq[MTLCommandBuffer]
      targets: seq[MTLTexture]
    defer:
      for commandBuffer in commands:
        commandBuffer.release()
      for target in targets:
        target.release()
    for index, value in Colors:
      let atlas = newImage(if index == 2: 4 else: 2, 2)
      atlas.fill(value)
      image.fill(value)
      drawer.uploadAtlas(atlas)
      drawer.uploadTextureRows(imageId, image, 0, image.height)
      doAssert drawer.needsAtlasPreparation(),
        "Atlas and independent image updates must be prepared before sampling"
      # Staging must own its pixels, including after the caller edits the image.
      atlas.fill(Blue)
      image.fill(Blue)
      let
        commandBuffer = queue.commandBuffer()
        target = device.newTarget(size, MTLPixelFormatRGBA8Unorm)
      checkNil(commandBuffer, "Could not create a queued UI command buffer")
      commandBuffer.retain()
      commands.add(commandBuffer)
      targets.add(target)
      commandBuffer.encodeBackground(target)
      drawer.setExternalFrame(commandBuffer, target)
      drawer.endFrame(atlas, size.vec2, nil, 0)
      doAssert not drawer.needsAtlasPreparation(),
        "An empty UI frame must encode pending uploads without submitting them"
      var vertices: seq[DrawerVertex]
      vertices.add(quad(vec2(0), vec2(6, 8), size.vec2, White))
      var imageVertices = quad(vec2(6, 0), vec2(6, 8), size.vec2, White)
      for vertex in imageVertices.mitems:
        vertex.texture = imageId
      vertices.add(imageVertices)
      drawer.setExternalFrame(commandBuffer, target)
      drawer.endFrame(atlas, size.vec2, vertices[0].addr, vertices.len)
      doAssert commandBuffer.status() == MTLCommandBufferStatusNotEnqueued,
        "Multiple queued UI frames must remain application-owned"
    # Encoding every frame before any commit exposes CPU texture overwrites.
    for commandBuffer in commands:
      commandBuffer.commit()
    commands[^1].waitUntilCompleted()
    for index, target in targets:
      checkNSError(commands[index].error(), "Queued external UI frame failed")
      let
        pixels = target.readPixels(size, MTLPixelFormatRGBA8Unorm)
        expected = if Colors[index] == HalfGreen:
          rgbx(0, 128, 127, 255)
        else:
          Colors[index]
      pixels.checkPixel(2, 4, expected,
        "A queued frame must sample its original atlas upload")
      pixels.checkPixel(9, 4, expected,
        "A queued frame must sample its original independent image upload")

    let atlas = newImage(2, 2)
    atlas.fill(Red)
    drawer.uploadAtlas(atlas)
    let
      commandBuffer = queue.commandBuffer()
      target = device.newTarget(size, MTLPixelFormatRGBA8Unorm)
      left = quad(vec2(0), vec2(6, 8), size.vec2, White)
      right = quad(vec2(6, 0), vec2(6, 8), size.vec2, White)
    defer: target.release()
    commandBuffer.encodeBackground(target)
    drawer.setExternalFrame(commandBuffer, target)
    drawer.endFrame(atlas, size.vec2, unsafeAddr left[0], left.len)
    atlas[0, 0] = White
    drawer.uploadAtlasRegion(atlas, 0, 0, 1, 1)
    drawer.setExternalFrame(commandBuffer, target)
    drawer.endFrame(atlas, size.vec2, unsafeAddr right[0], right.len)
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    checkNSError(commandBuffer.error(), "Same-buffer atlas update failed")
    let pixels = target.readPixels(size, MTLPixelFormatRGBA8Unorm)
    pixels.checkPixel(2, 4, Red,
      "An atlas edit must not change earlier draws in the same command buffer")
    pixels.checkPixel(9, 4, White,
      "Later draws must see the partial atlas edit in queue order")

  proc checkInvalidFrames(device: MTLDevice, queue: MTLCommandQueue) =
    ## Rejects invalid handles, incompatible formats, and submitted buffers.
    let
      image = newImage(2, 2)
      size = ivec2(8, 8)
      drawer = newDrawer(device, image, size)
    defer: drawer.close()
    let target = device.newTarget(size, MTLPixelFormatBGRA8Unorm)
    defer: target.release()
    let otherTarget = device.newTarget(size, MTLPixelFormatRGBA8Unorm)
    defer: otherTarget.release()
    let commandBuffer = queue.commandBuffer()
    checkNil(commandBuffer, "Could not create the validation command buffer")

    expectSilkyError("An external drawer must reject a missing device"):
      discard newDrawer(0.MTLDevice, image, size)
    expectSilkyError("A frame must reject a missing command buffer"):
      drawer.setExternalFrame(0.MTLCommandBuffer, target)
    expectSilkyError("A frame must reject a missing render target"):
      drawer.setExternalFrame(commandBuffer, 0.MTLTexture)
    expectSilkyError("The target must match the pipeline pixel format"):
      drawer.setExternalFrame(commandBuffer, otherTarget)

    commandBuffer.encodeBackground(target)
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    checkNSError(commandBuffer.error(), "Validation background failed")
    expectSilkyError("A frame must reject a submitted command buffer"):
      drawer.setExternalFrame(commandBuffer, target)

  when defined(macosx):
    proc checkSilkyInterface(device: MTLDevice, queue: MTLCommandQueue) =
      ## Exercises real window input and public UI with an injected drawer.
      let
        size = ivec2(32, 24)
        builder = newAtlasBuilder(32, 1)
        window = newWindow(
          "Silky Metal compositing test",
          size,
          visible = false,
          vsync = false
        )
      defer: window.close()
      let drawer = newDrawer(
        device,
        builder.atlasImage,
        size,
        pixelFormat = MTLPixelFormatRGBA8Unorm
      )
      defer: drawer.close()
      let
        sk = newSilky(window, builder.atlasImage, builder.atlas, drawer)
        target = device.newTarget(size, MTLPixelFormatRGBA8Unorm)
      defer: target.release()
      doAssert sk.drawer == drawer, "Silky must use the supplied drawer"
      doAssert not window.visible, "The integration window must stay hidden"
      doAssert window.onButtonPress != nil,
        "The real constructor must install the window's input handling"
      let commandBuffer = queue.commandBuffer()
      checkNil(commandBuffer, "Could not create the UI command buffer")
      commandBuffer.encodeBackground(target)
      sk.uiScale = 2
      sk.beginUi(window, size)
      sk.drawRect(vec2(2), vec2(4), Red)
      drawer.setExternalFrame(commandBuffer, target)
      sk.endUi()
      doAssert commandBuffer.status() == MTLCommandBufferStatusNotEnqueued,
        "Public endUi must leave the application in charge of submission"
      commandBuffer.commit()
      commandBuffer.waitUntilCompleted()
      checkNSError(commandBuffer.error(), "Public Silky compositing failed")
      let pixels = target.readPixels(size, MTLPixelFormatRGBA8Unorm)
      pixels.checkPixel(0, 0, Blue, "Public endUi preserves the scene")
      pixels.checkPixel(5, 5, Red, "Public endUi renders scaled UI geometry")
      pixels.checkPixel(10, 10, Red, "Injected drawers honor Silky's UI scale")
      pixels.checkPixel(13, 13, Blue, "The UI leaves uncovered pixels intact")

  proc main() =
    ## Owns the device and submission queue independently of every UI drawer.
    let device = MTLCreateSystemDefaultDevice()
    checkNil(device, "The compositing test requires a Metal device")
    defer: device.release()
    let queue = device.newCommandQueue()
    checkNil(queue, "Could not create the compositing queue")
    defer: queue.release()
    for pixelFormat in [MTLPixelFormatBGRA8Unorm, MTLPixelFormatRGBA8Unorm]:
      checkComposite(device, queue, pixelFormat)
    checkAtlasMipmaps(device, queue)
    checkEmptyFrames(device, queue)
    checkQueuedUploads(device, queue)
    checkInvalidFrames(device, queue)
    when defined(macosx):
      checkSilkyInterface(device, queue)
    echo "Metal compositing passed: rendering, atlas mips, empty UI, and validation."

  main()
  when defined(ios):
    quit(0)
else:
  echo "Skipped Metal compositing: requires macOS or iOS with useMetal4."
