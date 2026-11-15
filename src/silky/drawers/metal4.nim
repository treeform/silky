when not (defined(macosx) or defined(ios)):
  {.error: "The Silky Metal backend requires macOS or iOS.".}

import
  std/tables,
  pixie, shady, vmath, windy, pkg/metal4,
  ../common, shader

const
  InitialVertexCapacity = 4096
  VertexBufferIndex = 1
  MaximumTextureSize = 16384
  VertexShaderSource = toMSL(silkyVert, shaderVertex)
  FragmentShaderSource = toMSL(silkyFrag, shaderFragment)

type
  DrawerVertex* {.packed.} = object
    ## Raw quad layout consumed by the Metal drawer.
    pos*: Vec2
    uv*: Vec2
    color*: ColorRGBX
    clipPos*: Vec2
    clipSize*: Vec2
    maskUv*: Vec2
    texture*: uint32

  DrawerTexture = object
    ## A logical image handle owns a native texture and its pixel dimensions.
    texture: MTLTexture
    size: IVec2

  ShaderUniforms = object
    ## Matches the Shady vertex shader's constant buffer layout.
    viewportSize: Vec2
    atlasSize: Vec2

  Drawer* = ref object
    ## Metal 4-backed drawer state.
    ctx: MetalContext
    pipelineState: MTLRenderPipelineState
    texture: MTLTexture
    sampler: MTLSamplerState
    vertexBuffer: MTLBuffer
    vertexBufferPtr: pointer
    maxVertexCount: int
    viewportSize: IVec2
    atlasSize: IVec2
    textures: Table[uint32, DrawerTexture]
    nextTexture: uint32
    clearColor: MTLClearColor
    when defined(silkyMetalTesting):
      ownsTestDevice: bool
    layers*: array[2, seq[DrawerVertex]]
    currentLayer*: int
    layerStack*: seq[int]

static:
  doAssert sizeof(DrawerVertex) == 48
  doAssert sizeof(ShaderUniforms) == 16
  doAssert offsetOf(ShaderUniforms, viewportSize) == 0
  doAssert offsetOf(ShaderUniforms, atlasSize) == 8

proc clampViewport(size: IVec2): IVec2 =
  ## Clamps the viewport to valid drawable dimensions.
  ivec2(max(1'i32, size.x), max(1'i32, size.y))

proc close*(drawer: Drawer) =
  ## Releases all drawer-owned Metal resources after its synchronous frames.
  if drawer.isNil:
    return
  for texture in drawer.textures.values:
    texture.texture.release()
  drawer.textures.clear()
  drawer.texture.release()
  drawer.texture = 0.MTLTexture
  drawer.sampler.release()
  drawer.sampler = 0.MTLSamplerState
  drawer.pipelineState.release()
  drawer.pipelineState = 0.MTLRenderPipelineState
  drawer.vertexBuffer.release()
  drawer.vertexBuffer = 0.MTLBuffer
  drawer.vertexBufferPtr = nil
  drawer.maxVertexCount = 0
  when defined(silkyMetalTesting):
    if drawer.ownsTestDevice:
      drawer.ctx.device.release()
      drawer.ownsTestDevice = false
  drawer.ctx.destroy()

proc newTexture(state: Drawer, width, height: int): MTLTexture =
  ## Allocates a shader-readable texture using the supported 2D size limit.
  if width <= 0 or height <= 0:
    raise newException(SilkyError, "Image texture dimensions must be positive.")
  if width > MaximumTextureSize or height > MaximumTextureSize:
    raise newException(SilkyError, "Image texture exceeds the Metal size limit.")
  let descriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
    MTLPixelFormatRGBA8Unorm,
    width.uint,
    height.uint,
    false
  )
  descriptor.setUsage(MTLTextureUsageShaderRead)
  result = state.ctx.device.newTextureWithDescriptor(descriptor)
  if result.isNil:
    raise newException(SilkyError, "Could not allocate a Metal image texture.")

proc uploadRegion(
  texture: MTLTexture,
  image: Image,
  x, y, width, height: int
) =
  ## Uploads image pixels with their original row stride into a texture region.
  texture.replaceRegion(
    MTLRegion(
      origin: MTLOrigin(x: x.uint, y: y.uint, z: 0),
      size: MTLSize(width: width.uint, height: height.uint, depth: 1)
    ),
    0,
    unsafeAddr image.data[y * image.width + x],
    (image.width * sizeof(ColorRGBX)).uint
  )

proc createVertexBuffer(state: Drawer, maxVertexCount: int) =
  ## Creates or replaces the persistently mapped vertex buffer.
  let buffer = state.ctx.device.newBufferWithLength(
    (maxVertexCount * sizeof(DrawerVertex)).uint,
    0
  )
  checkNil(buffer, "Could not create a Metal vertex buffer")
  let bufferPtr = buffer.contents()
  checkNil(bufferPtr, "Could not map the Metal vertex buffer")
  state.vertexBuffer.release()
  state.vertexBuffer = buffer
  state.vertexBufferPtr = bufferPtr
  state.maxVertexCount = maxVertexCount

proc uploadTexture(state: Drawer, image: Image) =
  ## Uploads the atlas image into one Metal texture.
  if image.isNil:
    raise newException(SilkyError, "Cannot upload an empty atlas image.")
  if state.texture.isNil or
    state.atlasSize != ivec2(image.width.int32, image.height.int32):
      let texture = state.newTexture(image.width, image.height)
      state.texture.release()
      state.texture = texture
  state.texture.uploadRegion(image, 0, 0, image.width, image.height)
  state.atlasSize = ivec2(image.width.int32, image.height.int32)

proc allocateTexture*(drawer: Drawer, width, height: int): uint32 =
  ## Allocates a separate image texture, reserving handle zero for the atlas.
  if drawer.nextTexture == high(uint32):
    raise newException(SilkyError, "Image texture handles are exhausted.")
  let texture = drawer.newTexture(width, height)
  inc drawer.nextTexture
  result = drawer.nextTexture
  drawer.textures[result] = DrawerTexture(
    texture: texture,
    size: ivec2(width.int32, height.int32)
  )

proc uploadTextureRows*(
  drawer: Drawer,
  texture: uint32,
  image: Image,
  firstRow, rowCount: int
) =
  ## Uploads a bounded set of full-width rows into a separate image texture.
  if texture notin drawer.textures or image.isNil:
    raise newException(SilkyError, "Cannot upload an unknown image texture.")
  let target = drawer.textures[texture]
  if target.size != ivec2(image.width.int32, image.height.int32) or
    firstRow < 0 or rowCount < 0 or firstRow > image.height or
    rowCount > image.height - firstRow:
      raise newException(SilkyError, "Image texture upload bounds are invalid.")
  if rowCount == 0:
    return
  target.texture.uploadRegion(image, 0, firstRow, image.width, rowCount)

proc deleteTexture*(drawer: Drawer, texture: uint32) =
  ## Releases an independent image texture; deleting a missing handle is safe.
  if texture notin drawer.textures:
    return
  drawer.textures[texture].texture.release()
  drawer.textures.del(texture)

proc uploadAtlasRegion*(
  drawer: Drawer,
  image: Image,
  x, y, width, height: int
) =
  ## Refreshes changed atlas pixels, replacing the texture after atlas growth.
  if width <= 0 or height <= 0:
    return
  if image.isNil:
    raise newException(SilkyError, "Cannot upload an empty atlas image.")
  if drawer.atlasSize != ivec2(image.width.int32, image.height.int32):
    drawer.uploadTexture(image)
    return
  let
    left = clamp(x, 0, image.width)
    top = clamp(y, 0, image.height)
    right = clamp(x.int64 + width.int64, 0'i64, image.width.int64).int
    bottom = clamp(y.int64 + height.int64, 0'i64, image.height.int64).int
  if right <= left or bottom <= top:
    return
  drawer.texture.uploadRegion(image, left, top, right - left, bottom - top)

proc initRenderer(state: Drawer, image: Image, size: IVec2) =
  ## Creates the Metal pipeline, atlas texture, and dynamic buffers.
  var error: NSError
  let vertexLibrary = state.ctx.device.newLibraryWithSource(
    @VertexShaderSource,
    0.ID,
    error.addr
  )
  checkNSError(error, "Could not compile the Shady Metal vertex shader")
  checkNil(vertexLibrary, "Metal vertex library was nil")
  defer: vertexLibrary.release()

  error = 0.NSError
  let fragmentLibrary = state.ctx.device.newLibraryWithSource(
    @FragmentShaderSource,
    0.ID,
    error.addr
  )
  checkNSError(error, "Could not compile the Shady Metal fragment shader")
  checkNil(fragmentLibrary, "Metal fragment library was nil")
  defer: fragmentLibrary.release()

  let
    vertexFunction = vertexLibrary.newFunctionWithName(@"vertexMain")
    fragmentFunction = fragmentLibrary.newFunctionWithName(@"fragmentMain")
  checkNil(vertexFunction, "Could not load Shady's Metal vertex entry point")
  checkNil(fragmentFunction, "Could not load Shady's Metal fragment entry point")
  defer: vertexFunction.release()
  defer: fragmentFunction.release()

  let vertexDescriptor = MTLVertexDescriptor.alloc().init()
  checkNil(vertexDescriptor, "Could not create a Metal vertex descriptor")
  defer: vertexDescriptor.release()
  const Offsets = [
    offsetOf(DrawerVertex, pos),
    offsetOf(DrawerVertex, uv),
    offsetOf(DrawerVertex, color),
    offsetOf(DrawerVertex, clipPos),
    offsetOf(DrawerVertex, clipSize),
    offsetOf(DrawerVertex, maskUv)
  ]
  for i, offset in Offsets:
    let attribute = vertexDescriptor.attributes().objectAtIndexedSubscript(
      i.uint
    )
    attribute.setFormat(
      if i == 2: MTLVertexFormatUChar4Normalized else: MTLVertexFormatFloat2
    )
    attribute.setOffset(offset.uint)
    attribute.setBufferIndex(VertexBufferIndex)
  vertexDescriptor.layouts().objectAtIndexedSubscript(
    VertexBufferIndex
  ).setStride(sizeof(DrawerVertex).uint)

  let pipelineDescriptor = MTLRenderPipelineDescriptor.alloc().init()
  checkNil(pipelineDescriptor, "Could not create a pipeline descriptor")
  defer: pipelineDescriptor.release()
  pipelineDescriptor.setVertexDescriptor(vertexDescriptor)
  let colorAttachment =
    pipelineDescriptor.colorAttachments().objectAtIndexedSubscript(0)
  pipelineDescriptor.setVertexFunction(vertexFunction)
  pipelineDescriptor.setFragmentFunction(fragmentFunction)
  colorAttachment.setPixelFormat(MTLPixelFormatBGRA8Unorm)
  colorAttachment.setBlendingEnabled(true)
  colorAttachment.setSourceRGBBlendFactor(MTLBlendFactorOne)
  colorAttachment.setDestinationRGBBlendFactor(
    MTLBlendFactorOneMinusSourceAlpha
  )
  colorAttachment.setRgbBlendOperation(MTLBlendOperationAdd)
  colorAttachment.setSourceAlphaBlendFactor(MTLBlendFactorOne)
  colorAttachment.setDestinationAlphaBlendFactor(
    MTLBlendFactorOneMinusSourceAlpha
  )
  colorAttachment.setAlphaBlendOperation(MTLBlendOperationAdd)

  error = 0.NSError
  state.pipelineState = state.ctx.device.newRenderPipelineStateWithDescriptor(
    pipelineDescriptor,
    error.addr
  )
  checkNSError(error, "Could not create the Metal pipeline")
  checkNil(state.pipelineState, "Metal pipeline state was nil")

  let samplerDescriptor = MTLSamplerDescriptor.alloc().init()
  checkNil(samplerDescriptor, "Could not create a sampler descriptor")
  defer: samplerDescriptor.release()
  samplerDescriptor.setMinFilter(MTLSamplerMinMagFilterLinear)
  samplerDescriptor.setMagFilter(MTLSamplerMinMagFilterLinear)
  samplerDescriptor.setMipFilter(MTLSamplerMipFilterNotMipmapped)
  samplerDescriptor.setSAddressMode(MTLSamplerAddressModeClampToEdge)
  samplerDescriptor.setTAddressMode(MTLSamplerAddressModeClampToEdge)
  state.sampler = state.ctx.device.newSamplerStateWithDescriptor(
    samplerDescriptor
  )
  checkNil(state.sampler, "Could not create a sampler state")

  state.viewportSize = clampViewport(size)
  state.createVertexBuffer(InitialVertexCapacity)
  state.uploadTexture(image)

proc uploadAtlas*(drawer: Drawer, image: Image) =
  ## Replaces the atlas texture after runtime glyph or image additions.
  drawer.uploadTexture(image)

proc newDrawer*(window: Window, image: Image): Drawer =
  ## Creates a new Metal drawer and eagerly initializes its resources.
  let safeSize = clampViewport(window.size)
  result = Drawer(
    clearColor: MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
    currentLayer: 0,
    layerStack: @[],
    viewportSize: safeSize
  )
  result.layers[0] = @[]
  result.layers[1] = @[]
  try:
    result.ctx = newMetalContext(window)
    result.initRenderer(image, safeSize)
  except:
    result.close()
    raise

proc beginFrame*(drawer: Drawer, window: Window, size: IVec2) =
  ## Prepares the Metal drawer for a new frame.
  drawer.ctx.window = window
  drawer.viewportSize = clampViewport(size)
  drawer.ctx.updateDrawableSize()

proc clearScreen*(drawer: Drawer, color: ColorRGBX) =
  ## Sets the Metal clear color used at frame submission.
  let c = color.color
  drawer.clearColor = MTLClearColor(
    red: c.r.float64,
    green: c.g.float64,
    blue: c.b.float64,
    alpha: c.a.float64
  )

proc ensureVertexCapacity(state: Drawer, vertexCount: int) =
  ## Grows the vertex buffer to fit the current batch.
  if vertexCount <= state.maxVertexCount:
    return
  var newCapacity = max(InitialVertexCapacity, state.maxVertexCount)
  while newCapacity < vertexCount:
    newCapacity *= 2
  state.createVertexBuffer(newCapacity)

proc encodeDraw(
  state: Drawer,
  encoder: MTLRenderCommandEncoder,
  width, height: float64,
  vertexCount: int
) =
  ## Encodes contiguous texture batches without reordering layers or clipping.
  encoder.setRenderPipelineState(state.pipelineState)
  encoder.setViewport(
    MTLViewport(
      originX: 0,
      originY: 0,
      width: width,
      height: height,
      znear: 0,
      zfar: 1
    )
  )
  encoder.setCullMode(MTLCullModeNone)
  encoder.setVertexBuffer(state.vertexBuffer, 0, VertexBufferIndex)
  encoder.setFragmentSamplerState(state.sampler, 0)
  let vertices = cast[ptr UncheckedArray[DrawerVertex]](state.vertexBufferPtr)
  var first = 0
  while first < vertexCount:
    let textureId = vertices[first].texture
    var last = first + 1
    while last < vertexCount and vertices[last].texture == textureId:
      inc last
    var target = DrawerTexture(texture: state.texture, size: state.atlasSize)
    if textureId != 0:
      if textureId notin state.textures:
        first = last
        continue
      target = state.textures[textureId]
    var uniforms = ShaderUniforms(
      viewportSize: state.viewportSize.vec2,
      atlasSize: target.size.vec2
    )
    encoder.setVertexBytes(uniforms.addr, sizeof(uniforms).uint, 0)
    encoder.setFragmentTexture(target.texture, 0)
    encoder.drawPrimitives(
      MTLPrimitiveTypeTriangle,
      first.uint,
      (last - first).uint
    )
    first = last

proc recordDraw(state: Drawer, vertexCount: int) =
  ## Records the Metal draw pass for the current frame.
  let drawable = state.ctx.currentDrawable()
  if drawable.isNil:
    return
  let
    commandBuffer = state.ctx.newCommandBuffer()
    renderPass = state.ctx.clearPass(drawable, state.clearColor)
    encoder = commandBuffer.renderCommandEncoderWithDescriptor(renderPass)
    size = state.ctx.layer.drawableSize()
  checkNil(encoder, "Could not create a Metal render encoder")
  state.encodeDraw(encoder, size.width, size.height, vertexCount)
  encoder.endEncoding()
  commandBuffer.presentDrawable(drawable)
  commandBuffer.commit()
  # Keep the shared vertex buffer available for the next CPU frame.
  commandBuffer.waitUntilCompleted()
  checkNSError(commandBuffer.error(), "Metal failed to render the Silky frame")

proc uploadVertices(
  drawer: Drawer,
  image: Image,
  vertices: pointer,
  vertexCount: int
) =
  ## Updates the atlas and shared vertex buffer before a render pass.
  if drawer.atlasSize != ivec2(image.width.int32, image.height.int32):
    drawer.uploadTexture(image)
  drawer.ensureVertexCapacity(vertexCount)
  if vertexCount > 0:
    copyMem(
      drawer.vertexBufferPtr,
      vertices,
      vertexCount * sizeof(DrawerVertex)
    )

proc endFrame*(
  drawer: Drawer,
  image: Image,
  size: Vec2,
  quads: pointer,
  quadCount: int
) =
  ## Flushes the queued quads through Metal 4.
  discard size
  drawer.uploadVertices(image, quads, quadCount)
  drawer.recordDraw(quadCount)

when defined(silkyMetalTesting):
  objc:
    proc setStorageMode(self: MTLTextureDescriptor, x: uint)
    proc getBytes(
      self: MTLTexture,
      x: pointer,
      bytesPerRow: uint,
      fromRegion: MTLRegion,
      mipmapLevel: uint
    )

  proc newOffscreenDrawerForTesting*(image: Image, size: IVec2): Drawer =
    ## Creates the production drawer without a window for GPU pixel tests.
    result = Drawer(
      clearColor: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    )
    try:
      result.ctx.device = MTLCreateSystemDefaultDevice()
      checkNil(result.ctx.device, "The pixel test requires a Metal device")
      result.ownsTestDevice = true
      result.ctx.commandQueue = result.ctx.device.newCommandQueue()
      checkNil(result.ctx.commandQueue, "Could not create the test queue")
      result.initRenderer(image, size)
    except:
      result.close()
      raise

  proc renderPixelsForTesting*(
    drawer: Drawer,
    image: Image,
    vertices: openArray[DrawerVertex]
  ): Image =
    ## Renders through the production batching code and reads its output pixels.
    let
      width = drawer.viewportSize.x.int
      height = drawer.viewportSize.y.int
      descriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
        MTLPixelFormatBGRA8Unorm,
        width.uint,
        height.uint,
        false
      )
    descriptor.setUsage(MTLTextureUsageRenderTarget)
    descriptor.setStorageMode(0) # Shared storage allows synchronized CPU reads.
    let target = drawer.ctx.device.newTextureWithDescriptor(descriptor)
    checkNil(target, "Could not create the pixel test render target")
    defer: target.release()
    drawer.uploadVertices(
      image,
      if vertices.len > 0: unsafeAddr vertices[0] else: nil,
      vertices.len
    )
    let
      commandBuffer = drawer.ctx.newCommandBuffer()
      renderPass = MTLRenderPassDescriptor.renderPassDescriptor()
      attachment = renderPass.colorAttachments().objectAtIndexedSubscript(0)
    attachment.setTexture(target)
    attachment.setLoadAction(MTLLoadActionClear)
    attachment.setStoreAction(MTLStoreActionStore)
    attachment.setClearColor(drawer.clearColor)
    let encoder = commandBuffer.renderCommandEncoderWithDescriptor(renderPass)
    checkNil(encoder, "Could not create the pixel test render encoder")
    drawer.encodeDraw(encoder, width.float64, height.float64, vertices.len)
    encoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    checkNSError(commandBuffer.error(), "Metal failed to render test pixels")
    result = newImage(width, height)
    target.getBytes(
      result.data[0].addr,
      (width * sizeof(ColorRGBX)).uint,
      MTLRegion(
        origin: MTLOrigin(x: 0, y: 0, z: 0),
        size: MTLSize(width: width.uint, height: height.uint, depth: 1)
      ),
      0
    )
    for pixel in result.data.mitems:
      swap(pixel.r, pixel.b)
