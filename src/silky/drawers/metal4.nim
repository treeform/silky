when not (defined(macosx) or defined(ios)):
  {.error: "The Silky Metal backend requires macOS or iOS.".}

import
  pixie, shady, vmath, windy, pkg/metal4,
  shader

const
  InitialVertexCapacity = 4096
  VertexBufferIndex = 1
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
    clearColor: MTLClearColor
    layers*: array[2, seq[DrawerVertex]]
    currentLayer*: int
    layerStack*: seq[int]

static:
  doAssert sizeof(DrawerVertex) == 44
  doAssert sizeof(ShaderUniforms) == 16
  doAssert offsetOf(ShaderUniforms, viewportSize) == 0
  doAssert offsetOf(ShaderUniforms, atlasSize) == 8

proc clampViewport(size: IVec2): IVec2 =
  ## Clamps the viewport to valid drawable dimensions.
  ivec2(max(1'i32, size.x), max(1'i32, size.y))

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
  let descriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
    MTLPixelFormatRGBA8Unorm,
    image.width.uint,
    image.height.uint,
    false
  )
  descriptor.setUsage(MTLTextureUsageShaderRead)
  let texture = state.ctx.device.newTextureWithDescriptor(descriptor)
  checkNil(texture, "Could not create the atlas texture")

  texture.replaceRegion(
    MTLRegion(
      origin: MTLOrigin(x: 0, y: 0, z: 0),
      size: MTLSize(
        width: image.width.uint,
        height: image.height.uint,
        depth: 1
      )
    ),
    0,
    unsafeAddr image.data[0],
    (image.width * 4).uint
  )
  state.texture.release()
  state.texture = texture
  state.atlasSize = ivec2(image.width.int32, image.height.int32)

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
  result.ctx = newMetalContext(window)
  result.initRenderer(image, safeSize)

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

proc recordDraw(state: Drawer, vertexCount: int) =
  ## Records the Metal draw pass for the current frame.
  let drawable = state.ctx.currentDrawable()
  if drawable.isNil:
    return

  let
    commandBuffer = state.ctx.newCommandBuffer()
    renderPass = state.ctx.clearPass(drawable, state.clearColor)
    encoder = commandBuffer.renderCommandEncoderWithDescriptor(renderPass)
  checkNil(encoder, "Could not create a Metal render encoder")
  encoder.setRenderPipelineState(state.pipelineState)
  encoder.setViewport(
    MTLViewport(
      originX: 0,
      originY: 0,
      width: state.ctx.layer.drawableSize().width,
      height: state.ctx.layer.drawableSize().height,
      znear: 0,
      zfar: 1
    )
  )
  encoder.setCullMode(MTLCullModeNone)
  encoder.setVertexBuffer(state.vertexBuffer, 0, VertexBufferIndex)
  var uniforms = ShaderUniforms(
    viewportSize: state.viewportSize.vec2,
    atlasSize: state.atlasSize.vec2
  )
  encoder.setVertexBytes(uniforms.addr, sizeof(uniforms).uint, 0)
  encoder.setFragmentTexture(state.texture, 0)
  encoder.setFragmentSamplerState(state.sampler, 0)
  if vertexCount > 0:
    encoder.drawPrimitives(MTLPrimitiveTypeTriangle, 0, vertexCount.uint)
  encoder.endEncoding()
  commandBuffer.presentDrawable(drawable)
  commandBuffer.commit()
  # Keep the shared vertex buffer available for the next CPU frame.
  commandBuffer.waitUntilCompleted()
  checkNSError(commandBuffer.error(), "Metal failed to render the Silky frame")

proc endFrame*(
  drawer: Drawer,
  image: Image,
  size: Vec2,
  quads: pointer,
  quadCount: int
) =
  ## Flushes the queued quads through Metal 4.
  discard size
  let vertexCount = quadCount
  if drawer.atlasSize != ivec2(image.width.int32, image.height.int32):
    drawer.uploadTexture(image)
  drawer.ensureVertexCapacity(vertexCount)

  if vertexCount > 0:
    copyMem(
      drawer.vertexBufferPtr,
      quads,
      vertexCount * sizeof(DrawerVertex)
    )

  drawer.recordDraw(vertexCount)
