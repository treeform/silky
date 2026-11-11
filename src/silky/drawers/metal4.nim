when not defined(macosx):
  {.error: "The Silky Metal 4 backend requires macOS.".}

import
  pixie, vmath, windy, pkg/metal4

const
  InitialVertexCapacity = 4096

type
  DrawerVertex* {.packed.} = object
    ## Raw quad layout consumed by the Metal drawer.
    pos*: Vec2
    uv*: Vec2
    color*: ColorRGBX
    clipPos*: Vec2
    clipSize*: Vec2
    maskUv*: Vec2

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
    clearColor: MTLClearColor
    layers*: array[2, seq[DrawerVertex]]
    currentLayer*: int
    layerStack*: seq[int]

proc clampViewport(size: IVec2): IVec2 =
  ## Clamps the viewport to valid drawable dimensions.
  ivec2(max(1'i32, size.x), max(1'i32, size.y))

proc normalizeVertices(
  vertices: var seq[DrawerVertex],
  viewportSize: IVec2,
  atlasSize: Vec2
) =
  ## Converts queued pixel-space vertices to clip-space and normalized UVs.
  let
    width = max(1.0'f, viewportSize.x.float32)
    height = max(1.0'f, viewportSize.y.float32)
  for i in 0 ..< vertices.len:
    let p = vertices[i].pos
    vertices[i].pos = vec2(
      (p.x / width) * 2.0'f - 1.0'f,
      1.0'f - (p.y / height) * 2.0'f
    )
    vertices[i].uv = vertices[i].uv / atlasSize

proc createVertexBuffer(state: Drawer, maxVertexCount: int) =
  ## Creates or replaces the persistently mapped vertex buffer.
  state.vertexBuffer = state.ctx.device.newBufferWithLength(
    (maxVertexCount * sizeof(DrawerVertex)).uint,
    0
  )
  checkNil(state.vertexBuffer, "Could not create a Metal vertex buffer")
  state.vertexBufferPtr = state.vertexBuffer.contents()
  checkNil(state.vertexBufferPtr, "Could not map the Metal vertex buffer")
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
  state.texture = state.ctx.device.newTextureWithDescriptor(descriptor)
  checkNil(state.texture, "Could not create the atlas texture")

  state.texture.replaceRegion(
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

proc initRenderer(state: Drawer, image: Image, size: IVec2) =
  ## Creates the Metal pipeline, atlas texture, and dynamic buffers.
  const ShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct DrawerVertex {
  packed_float2 pos;
  packed_float2 uv;
  uchar4 color;
  packed_float2 clipPos;
  packed_float2 clipSize;
  packed_float2 maskUv;
};

struct VertexOut {
  float4 position [[position]];
  float2 uv;
  float4 color;
  float2 clipPos;
  float2 clipSize;
  float2 maskUv;
};

vertex VertexOut vertexMain(
  uint vertexId [[vertex_id]],
  constant DrawerVertex *vertices [[buffer(0)]]
) {
  VertexOut out;
  DrawerVertex inVertex = vertices[vertexId];
  out.position = float4(float2(inVertex.pos), 0.0, 1.0);
  out.uv = float2(inVertex.uv);
  out.color = float4(inVertex.color) / 255.0;
  out.clipPos = float2(inVertex.clipPos);
  out.clipSize = float2(inVertex.clipSize);
  out.maskUv = float2(inVertex.maskUv);
  return out;
}

fragment float4 fragmentMain(VertexOut in [[stage_in]]) {
  if (in.position.x < in.clipPos.x ||
      in.position.y < in.clipPos.y ||
      in.position.x > in.clipPos.x + in.clipSize.x ||
      in.position.y > in.clipPos.y + in.clipSize.y) {
    discard_fragment();
  }
  return float4(1.0);
}

fragment float4 texturedFragmentMain(
  VertexOut in [[stage_in]],
  texture2d<float> tex [[texture(0)]],
  sampler texSampler [[sampler(0)]]
) {
  // Fetch before clipping so discarded neighbors keep valid derivatives.
  float4 base = tex.sample(texSampler, in.uv);
  float4 shaded = base * in.color;
  if (in.maskUv.x >= 0.0) {
    float maskR = tex.sample(texSampler, in.maskUv).r;
    shaded = float4(base.rgb * mix(float3(1.0), in.color.rgb, maskR), base.a * in.color.a);
  }
  if (in.position.x < in.clipPos.x ||
      in.position.y < in.clipPos.y ||
      in.position.x > in.clipPos.x + in.clipSize.x ||
      in.position.y > in.clipPos.y + in.clipSize.y) {
    discard_fragment();
  }
  return shaded;
}
"""

  var error: NSError
  let library = state.ctx.device.newLibraryWithSource(
    @ShaderSource,
    0.ID,
    error.addr
  )
  checkNSError(error, "Could not compile the Metal shaders")
  checkNil(library, "Metal shader library was nil")

  let vertexFunction = library.newFunctionWithName(@"vertexMain")
  checkNil(vertexFunction, "Could not load Metal shader entry point: vertexMain")

  let fragmentFunction = library.newFunctionWithName(@"texturedFragmentMain")
  checkNil(
    fragmentFunction,
    "Could not load Metal shader entry point: texturedFragmentMain"
  )

  let pipelineDescriptor = MTLRenderPipelineDescriptor.alloc().init()
  checkNil(pipelineDescriptor, "Could not create a pipeline descriptor")
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
  encoder.setVertexBuffer(state.vertexBuffer, 0, 0)
  encoder.setFragmentTexture(state.texture, 0)
  encoder.setFragmentSamplerState(state.sampler, 0)
  if vertexCount > 0:
    encoder.drawPrimitives(MTLPrimitiveTypeTriangle, 0, vertexCount.uint)
  encoder.endEncoding()
  commandBuffer.presentDrawable(drawable)
  commandBuffer.commit()

proc endFrame*(
  drawer: Drawer,
  image: Image,
  size: Vec2,
  quads: pointer,
  quadCount: int
) =
  ## Flushes the queued quads through Metal 4.
  discard size
  let
    atlasSize = vec2(image.width.float32, image.height.float32)
    vertexCount = quadCount
  drawer.ensureVertexCapacity(vertexCount)

  var vertices = newSeqOfCap[DrawerVertex](vertexCount)
  let quadsArr = cast[ptr UncheckedArray[DrawerVertex]](quads)
  for i in 0 ..< quadCount:
    vertices.add(quadsArr[i])
  vertices.normalizeVertices(drawer.viewportSize, atlasSize)

  if vertexCount > 0:
    copyMem(
      drawer.vertexBufferPtr,
      unsafeAddr vertices[0],
      vertexCount * sizeof(DrawerVertex)
    )

  drawer.recordDraw(vertexCount)
