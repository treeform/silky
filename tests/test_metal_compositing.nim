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
      pixelFormat: MTLPixelFormat): Image =
    ## Reads the completed target into ordinary RGBA image storage.
    result = newImage(size.x.int, size.y.int)
    target.getBytes(
      result.data[0].addr,
      (size.x.int * sizeof(ColorRGBX)).uint,
      MTLRegion(
        origin: MTLOrigin(x: 0, y: 0, z: 0),
        size: MTLSize(width: size.x.uint, height: size.y.uint, depth: 1)
      ),
      0
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
    checkInvalidFrames(device, queue)
    when defined(macosx):
      checkSilkyInterface(device, queue)
    echo "Metal compositing passed: rendering, public UI, and validation."

  main()
  when defined(ios):
    quit(0)
else:
  echo "Skipped Metal compositing: requires macOS or iOS with useMetal4."
