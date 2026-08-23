when not defined(windows):
  {.error: "The Silky DirectX 12 backend requires Windows.".}

import
  pixie, vmath, windy,
  pkg/dx12, pkg/dx12/context

when not defined(shadyBinaryShaders):
  import std/os, silky/drawers/shader
  from shady import compileHlslShader, toHLSL, shaderVertex, shaderFragment

const
  InitialVertexCapacity = 4096

when not defined(shadyBinaryShaders):
  const
    ShaderDir = currentSourcePath().parentDir / "shaders"
    VertexHlslPath = ShaderDir / "silky.vert.hlsl"
    PixelHlslPath = ShaderDir / "silky.frag.hlsl"
    VertexCsoPath = ShaderDir / "silky.vs.cso"
    PixelCsoPath = ShaderDir / "silky.ps.cso"

type
  DrawerVertex* {.packed.} = object
    ## Raw quad layout consumed by the DX12 drawer.
    pos*: Vec2
    uv*: Vec2
    color*: ColorRGBX
    clipPos*: Vec2
    clipSize*: Vec2
    maskUv*: Vec2

  Drawer* = ref object
    ## DirectX 12-backed drawer state.
    window: Window
    ctx: D3D12Context
    rootSignature: ID3D12RootSignature
    pipelineState: ID3D12PipelineState
    texture: ID3D12Resource
    srvHeap: ID3D12DescriptorHeap
    srvHandleGpu: D3D12_GPU_DESCRIPTOR_HANDLE
    vertexBuffer: ID3D12Resource
    vertexBufferView: D3D12_VERTEX_BUFFER_VIEW
    vertexBufferPtr: pointer
    maxVertexCount: int
    viewportSize: IVec2
    clearColor: array[4, float32]
    layers*: array[2, seq[DrawerVertex]]
    currentLayer*: int
    layerStack*: seq[int]

proc clampViewport(size: IVec2): IVec2 =
  ## Clamps the viewport to valid swap-chain dimensions.
  ivec2(max(1'i32, size.x), max(1'i32, size.y))

proc shaderBytecode(code: string): D3D12_SHADER_BYTECODE =
  D3D12_SHADER_BYTECODE(
    pShaderBytecode: unsafeAddr code[0],
    BytecodeLength: csize_t(code.len)
  )

proc createVertexBuffer(state: Drawer, maxVertexCount: int) =
  ## Creates or replaces the persistently mapped upload vertex buffer.
  if state.vertexBuffer != nil:
    state.vertexBuffer.unmap(0, nil)
    state.vertexBuffer.release()
    state.vertexBuffer = nil
    state.vertexBufferPtr = nil

  let vertexBufferSize = uint64(maxVertexCount * sizeof(DrawerVertex))

  var bufferDesc: D3D12_RESOURCE_DESC
  zeroMem(addr bufferDesc, sizeof(bufferDesc))
  bufferDesc.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER
  bufferDesc.Alignment = 0
  bufferDesc.Width = vertexBufferSize
  bufferDesc.Height = 1
  bufferDesc.DepthOrArraySize = 1
  bufferDesc.MipLevels = 1
  bufferDesc.Format = DXGI_FORMAT_UNKNOWN
  bufferDesc.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
  bufferDesc.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR
  bufferDesc.Flags = D3D12_RESOURCE_FLAG_NONE

  var uploadHeap: D3D12_HEAP_PROPERTIES
  zeroMem(addr uploadHeap, sizeof(uploadHeap))
  uploadHeap.typ = D3D12_HEAP_TYPE_UPLOAD
  uploadHeap.CPUPageProperty = 0
  uploadHeap.MemoryPoolPreference = 0
  uploadHeap.CreationNodeMask = 1
  uploadHeap.VisibleNodeMask = 1

  state.vertexBuffer = state.ctx.device.createCommittedResource(
    addr uploadHeap,
    D3D12_HEAP_FLAG_NONE,
    addr bufferDesc,
    D3D12_RESOURCE_STATE_GENERIC_READ,
    nil
  )
  state.vertexBuffer.map(0, nil, addr state.vertexBufferPtr)
  state.maxVertexCount = maxVertexCount
  state.vertexBufferView = D3D12_VERTEX_BUFFER_VIEW(
    BufferLocation: state.vertexBuffer.getGPUVirtualAddress(),
    SizeInBytes: uint32(vertexBufferSize),
    StrideInBytes: uint32(sizeof(DrawerVertex))
  )

proc uploadTexture(state: Drawer, image: Image) =
  ## Uploads the atlas image to a DX12 texture and creates one SRV.
  const BytesPerPixel = 4

  var texDesc: D3D12_RESOURCE_DESC
  zeroMem(addr texDesc, sizeof(texDesc))
  texDesc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D
  texDesc.Alignment = 0
  texDesc.Width = uint64(image.width)
  texDesc.Height = uint32(image.height)
  texDesc.DepthOrArraySize = 1
  texDesc.MipLevels = 1
  texDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM
  texDesc.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
  texDesc.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN
  texDesc.Flags = D3D12_RESOURCE_FLAG_NONE

  var defaultHeap: D3D12_HEAP_PROPERTIES
  zeroMem(addr defaultHeap, sizeof(defaultHeap))
  defaultHeap.typ = D3D12_HEAP_TYPE_DEFAULT
  defaultHeap.CPUPageProperty = 0
  defaultHeap.MemoryPoolPreference = 0
  defaultHeap.CreationNodeMask = 1
  defaultHeap.VisibleNodeMask = 1

  state.texture = state.ctx.device.createCommittedResource(
    addr defaultHeap,
    D3D12_HEAP_FLAG_NONE,
    addr texDesc,
    D3D12_RESOURCE_STATE_COPY_DEST,
    nil
  )

  var footprint = D3D12_PLACED_SUBRESOURCE_FOOTPRINT()
  var numRows: uint32
  var rowSize: uint64
  var totalBytes: uint64
  state.ctx.device.getCopyableFootprints(
    addr texDesc,
    0,
    1,
    0'u64,
    addr footprint,
    addr numRows,
    addr rowSize,
    addr totalBytes
  )

  var uploadDesc: D3D12_RESOURCE_DESC
  zeroMem(addr uploadDesc, sizeof(uploadDesc))
  uploadDesc.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER
  uploadDesc.Alignment = 0
  uploadDesc.Width = totalBytes
  uploadDesc.Height = 1
  uploadDesc.DepthOrArraySize = 1
  uploadDesc.MipLevels = 1
  uploadDesc.Format = DXGI_FORMAT_UNKNOWN
  uploadDesc.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
  uploadDesc.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR
  uploadDesc.Flags = D3D12_RESOURCE_FLAG_NONE

  var uploadHeap: D3D12_HEAP_PROPERTIES
  zeroMem(addr uploadHeap, sizeof(uploadHeap))
  uploadHeap.typ = D3D12_HEAP_TYPE_UPLOAD
  uploadHeap.CPUPageProperty = 0
  uploadHeap.MemoryPoolPreference = 0
  uploadHeap.CreationNodeMask = 1
  uploadHeap.VisibleNodeMask = 1

  let uploadBuffer = state.ctx.device.createCommittedResource(
    addr uploadHeap,
    D3D12_HEAP_FLAG_NONE,
    addr uploadDesc,
    D3D12_RESOURCE_STATE_GENERIC_READ,
    nil
  )

  var uploadPtr: pointer
  uploadBuffer.map(0, nil, addr uploadPtr)
  let
    rowPitch = int(footprint.Footprint.RowPitch)
    srcRowSize = image.width * BytesPerPixel
  var dst = cast[ptr uint8](cast[uint](uploadPtr) + uint(footprint.Offset))
  for y in 0 ..< image.height:
    let srcIdx = image.dataIndex(0, y)
    let srcPtr = cast[ptr uint8](image.data[srcIdx].addr)
    copyMem(dst, srcPtr, srcRowSize)
    if rowPitch > srcRowSize:
      zeroMem(
        cast[pointer](cast[uint](dst) + uint(srcRowSize)),
        rowPitch - srcRowSize
      )
    dst = cast[ptr uint8](cast[uint](dst) + uint(rowPitch))
  uploadBuffer.unmap(0, nil)

  state.ctx.commandAllocator.reset()
  state.ctx.commandList.reset(state.ctx.commandAllocator, nil)

  var dstLocation = D3D12_TEXTURE_COPY_LOCATION(
    pResource: state.texture,
    typ: D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX,
    data: D3D12_TEXTURE_COPY_LOCATION_UNION(SubresourceIndex: 0)
  )
  var srcLocation = D3D12_TEXTURE_COPY_LOCATION(
    pResource: uploadBuffer,
    typ: D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT,
    data: D3D12_TEXTURE_COPY_LOCATION_UNION(
      PlacedFootprint: footprint
    )
  )
  state.ctx.commandList.copyTextureRegion(
    addr dstLocation,
    0,
    0,
    0,
    addr srcLocation,
    nil
  )

  var barrier = D3D12_RESOURCE_BARRIER(
    typ: D3D12_RESOURCE_BARRIER_TYPE_TRANSITION,
    Flags: D3D12_RESOURCE_BARRIER_FLAG_NONE,
    data: D3D12_RESOURCE_BARRIER_union(Transition: D3D12_RESOURCE_TRANSITION_BARRIER(
      pResource: state.texture,
      Subresource: D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
      StateBefore: D3D12_RESOURCE_STATE_COPY_DEST,
      StateAfter: D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE
    ))
  )
  state.ctx.commandList.resourceBarrier(1, addr barrier)
  state.ctx.commandList.close()
  state.ctx.executeFrame(
    if state.window != nil: state.window.vsync else: true
  )
  state.ctx.waitForGpu()
  uploadBuffer.release()

  var srvHeapDesc = D3D12_DESCRIPTOR_HEAP_DESC(
    typ: D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV,
    NumDescriptors: 1'u32,
    Flags: D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE,
    NodeMask: 0
  )
  state.srvHeap = state.ctx.device.createDescriptorHeap(addr srvHeapDesc)
  let srvCpuHandle = state.srvHeap.getCPUDescriptorHandleForHeapStart()
  state.srvHandleGpu = state.srvHeap.getGPUDescriptorHandleForHeapStart()

  var srvDesc = D3D12_SHADER_RESOURCE_VIEW_DESC(
    Format: DXGI_FORMAT_R8G8B8A8_UNORM,
    ViewDimension: D3D12_SRV_DIMENSION_TEXTURE2D,
    Shader4ComponentMapping: D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING,
    data: D3D12_SHADER_RESOURCE_VIEW_DESC_UNION(
      Texture2D: D3D12_TEX2D_SRV(
        MostDetailedMip: 0,
        MipLevels: 1,
        PlaneSlice: 0,
        ResourceMinLODClamp: 0.0
      )
    )
  )
  state.ctx.device.createShaderResourceView(
    state.texture,
    addr srvDesc,
    srvCpuHandle
  )

proc initRenderer(state: Drawer, image: Image, size: IVec2) =
  ## Creates the DX12 pipeline, upload buffers, and atlas texture.
  when defined(shadyBinaryShaders):
    const
      vertexShaderCode = staticRead("shaders/silky.vs.cso")
      pixelShaderCode = staticRead("shaders/silky.ps.cso")
  else:
    const
      vertexShaderSrc = toHLSL(silkyVert, shaderVertex)
      pixelShaderSrc = toHLSL(silkyFrag, shaderFragment)
      vertexShaderCode = compileHlslShader(
        vertexShaderSrc,
        VertexHlslPath,
        VertexCsoPath,
        "VSMain",
        "vs_6_0"
      )
      pixelShaderCode = compileHlslShader(
        pixelShaderSrc,
        PixelHlslPath,
        PixelCsoPath,
        "PSMain",
        "ps_6_0"
      )
  let
    safeSize = clampViewport(size)

  when defined(shadyBinaryShaders):
    let
      vsBytecode = shaderBytecode(vertexShaderCode)
      psBytecode = shaderBytecode(pixelShaderCode)
  else:
    let
      vsBlob = compileShader(vertexShaderSrc, "VSMain", "vs_5_0")
      psBlob = compileShader(pixelShaderSrc, "PSMain", "ps_5_0")
      vsBytecode = shaderBytecode(vsBlob)
      psBytecode = shaderBytecode(psBlob)

  var range = D3D12_DESCRIPTOR_RANGE(
    RangeType: D3D12_DESCRIPTOR_RANGE_TYPE_SRV,
    NumDescriptors: 1,
    BaseShaderRegister: 0,
    RegisterSpace: 0,
    OffsetInDescriptorsFromTableStart:
      D3D12_DESCRIPTOR_RANGE_OFFSET_APPEND
  )

  var rootParams = [
    D3D12_ROOT_PARAMETER(
      ParameterType: D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS,
      data: D3D12_ROOT_PARAMETER_UNION(
        Constants: D3D12_ROOT_CONSTANTS(
          ShaderRegister: 0,
          RegisterSpace: 0,
          Num32BitValues: 4
        )
      ),
      ShaderVisibility: D3D12_SHADER_VISIBILITY_VERTEX
    ),
    D3D12_ROOT_PARAMETER(
      ParameterType: D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE,
      data: D3D12_ROOT_PARAMETER_UNION(
        DescriptorTable: D3D12_ROOT_DESCRIPTOR_TABLE(
          NumDescriptorRanges: 1,
          pDescriptorRanges: addr range
        )
      ),
      ShaderVisibility: D3D12_SHADER_VISIBILITY_PIXEL
    )
  ]

  var sampler = D3D12_STATIC_SAMPLER_DESC(
    Filter: D3D12_FILTER_MIN_MAG_MIP_LINEAR,
    AddressU: D3D12_TEXTURE_ADDRESS_MODE_CLAMP,
    AddressV: D3D12_TEXTURE_ADDRESS_MODE_CLAMP,
    AddressW: D3D12_TEXTURE_ADDRESS_MODE_CLAMP,
    MipLODBias: 0.0,
    MaxAnisotropy: 0,
    ComparisonFunc: D3D12_COMPARISON_FUNC_ALWAYS,
    BorderColor: D3D12_STATIC_BORDER_COLOR_OPAQUE_BLACK,
    MinLOD: 0.0,
    MaxLOD: 1000.0,
    ShaderRegister: 0,
    RegisterSpace: 0,
    ShaderVisibility: D3D12_SHADER_VISIBILITY_PIXEL
  )

  var rootDesc = D3D12_ROOT_SIGNATURE_DESC(
    NumParameters: uint32(rootParams.len),
    pParameters: addr rootParams[0],
    NumStaticSamplers: 1,
    pStaticSamplers: addr sampler,
    Flags: D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT
  )
  let rootBlob = serializeRootSignature(addr rootDesc)
  state.rootSignature = state.ctx.device.createRootSignature(
    0,
    getBufferPointer(rootBlob),
    getBufferSize(rootBlob)
  )
  release(rootBlob)

  var inputElements = [
    D3D12_INPUT_ELEMENT_DESC(
      SemanticName: "POSITION",
      SemanticIndex: 0,
      Format: DXGI_FORMAT_R32G32_FLOAT,
      InputSlot: 0,
      AlignedByteOffset: 0,
      InputSlotClass: D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,
      InstanceDataStepRate: 0
    ),
    D3D12_INPUT_ELEMENT_DESC(
      SemanticName: "TEXCOORD",
      SemanticIndex: 0,
      Format: DXGI_FORMAT_R32G32_FLOAT,
      InputSlot: 0,
      AlignedByteOffset: 8,
      InputSlotClass: D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,
      InstanceDataStepRate: 0
    ),
    D3D12_INPUT_ELEMENT_DESC(
      SemanticName: "COLOR",
      SemanticIndex: 0,
      Format: DXGI_FORMAT_R8G8B8A8_UNORM,
      InputSlot: 0,
      AlignedByteOffset: 16,
      InputSlotClass: D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,
      InstanceDataStepRate: 0
    ),
    D3D12_INPUT_ELEMENT_DESC(
      SemanticName: "TEXCOORD",
      SemanticIndex: 1,
      Format: DXGI_FORMAT_R32G32_FLOAT,
      InputSlot: 0,
      AlignedByteOffset: 20,
      InputSlotClass: D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,
      InstanceDataStepRate: 0
    ),
    D3D12_INPUT_ELEMENT_DESC(
      SemanticName: "TEXCOORD",
      SemanticIndex: 2,
      Format: DXGI_FORMAT_R32G32_FLOAT,
      InputSlot: 0,
      AlignedByteOffset: 28,
      InputSlotClass: D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,
      InstanceDataStepRate: 0
    ),
    D3D12_INPUT_ELEMENT_DESC(
      SemanticName: "TEXCOORD",
      SemanticIndex: 3,
      Format: DXGI_FORMAT_R32G32_FLOAT,
      InputSlot: 0,
      AlignedByteOffset: 36,
      InputSlotClass: D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,
      InstanceDataStepRate: 0
    )
  ]

  var blendDesc: D3D12_BLEND_DESC
  blendDesc.AlphaToCoverageEnable = 0
  blendDesc.IndependentBlendEnable = 0
  blendDesc.RenderTarget[0] = D3D12_RENDER_TARGET_BLEND_DESC(
    BlendEnable: 1,
    LogicOpEnable: 0,
    SrcBlend: D3D12_BLEND_ONE,
    DestBlend: D3D12_BLEND_INV_SRC_ALPHA,
    BlendOp: D3D12_BLEND_OP_ADD,
    SrcBlendAlpha: D3D12_BLEND_ONE,
    DestBlendAlpha: D3D12_BLEND_INV_SRC_ALPHA,
    BlendOpAlpha: D3D12_BLEND_OP_ADD,
    LogicOp: 0,
    RenderTargetWriteMask: uint8(D3D12_COLOR_WRITE_ENABLE_ALL)
  )

  let depthOp = D3D12_DEPTH_STENCILOP_DESC(
    StencilFailOp: D3D12_STENCIL_OP_KEEP,
    StencilDepthFailOp: D3D12_STENCIL_OP_KEEP,
    StencilPassOp: D3D12_STENCIL_OP_KEEP,
    StencilFunc: D3D12_COMPARISON_FUNC_ALWAYS
  )

  var psoDesc = D3D12_GRAPHICS_PIPELINE_STATE_DESC(
    pRootSignature: state.rootSignature,
    VS: vsBytecode,
    PS: psBytecode,
    StreamOutput: D3D12_STREAM_OUTPUT_DESC(),
    BlendState: blendDesc,
    SampleMask: D3D12_DEFAULT_SAMPLE_MASK,
    RasterizerState: D3D12_RASTERIZER_DESC(
      FillMode: D3D12_FILL_MODE_SOLID,
      CullMode: D3D12_CULL_MODE_NONE,
      FrontCounterClockwise: 0,
      DepthBias: 0,
      DepthBiasClamp: 0.0,
      SlopeScaledDepthBias: 0.0,
      DepthClipEnable: 1,
      MultisampleEnable: 0,
      AntialiasedLineEnable: 0,
      ForcedSampleCount: 0,
      ConservativeRaster: D3D12_CONSERVATIVE_RASTERIZATION_MODE_OFF
    ),
    DepthStencilState: D3D12_DEPTH_STENCIL_DESC(
      DepthEnable: 0,
      DepthWriteMask: D3D12_DEPTH_WRITE_MASK_ALL,
      DepthFunc: D3D12_COMPARISON_FUNC_ALWAYS,
      StencilEnable: 0,
      StencilReadMask: 0xff'u8,
      StencilWriteMask: 0xff'u8,
      FrontFace: depthOp,
      BackFace: depthOp
    ),
    InputLayout: D3D12_INPUT_LAYOUT_DESC(
      pInputElementDescs: addr inputElements[0],
      NumElements: uint32(inputElements.len)
    ),
    IBStripCutValue: 0,
    PrimitiveTopologyType: D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE,
    NumRenderTargets: 1,
    DSVFormat: DXGI_FORMAT_UNKNOWN,
    SampleDesc: DXGI_SAMPLE_DESC(Count: 1, Quality: 0),
    NodeMask: 0,
    CachedPSO: D3D12_CACHED_PIPELINE_STATE(),
    Flags: 0
  )
  psoDesc.RTVFormats[0] = DXGI_FORMAT_R8G8B8A8_UNORM
  state.pipelineState = state.ctx.device.createGraphicsPipelineState(
    addr psoDesc
  )

  when not defined(shadyBinaryShaders):
    release(vsBlob)
    release(psBlob)

  state.viewportSize = safeSize
  state.createVertexBuffer(InitialVertexCapacity)
  state.uploadTexture(image)

proc newDrawer*(window: Window, image: Image): Drawer =
  ## Creates a new DX12 drawer and eagerly initializes its resources.
  let
    state = Drawer(
      window: window,
      clearColor: [0.0'f, 0.0'f, 0.0'f, 1.0'f],
      currentLayer: 0,
      layerStack: @[]
    )
    hwnd = window.getHWND()
    safeSize = clampViewport(window.size)
  state.layers[0] = @[]
  state.layers[1] = @[]
  result = state
  state.ctx.initDevice(hwnd, safeSize.x.int, safeSize.y.int)
  state.initRenderer(image, safeSize)

proc beginFrame*(drawer: Drawer, window: Window, size: IVec2) =
  ## Prepares the DX12 drawer for a new frame.
  let safeSize = clampViewport(size)
  drawer.window = window
  if drawer.viewportSize != safeSize:
    drawer.ctx.resize(safeSize.x.int, safeSize.y.int)
    drawer.viewportSize = safeSize

proc clearScreen*(drawer: Drawer, color: ColorRGBX) =
  ## Sets the DX12 clear color used at frame submission.
  let c = color.color
  drawer.clearColor = [c.r, c.g, c.b, c.a]

proc ensureVertexCapacity(state: Drawer, vertexCount: int) =
  ## Grows the upload vertex buffer to fit the current batch.
  if vertexCount <= state.maxVertexCount:
    return
  var newCapacity = max(InitialVertexCapacity, state.maxVertexCount)
  while newCapacity < vertexCount:
    newCapacity *= 2
  state.createVertexBuffer(newCapacity)

proc recordDraw(state: Drawer, vertexCount: int, atlasSize: Vec2) =
  ## Records the DX12 draw pass for the current frame.
  state.ctx.commandAllocator.reset()
  state.ctx.commandList.reset(state.ctx.commandAllocator, state.pipelineState)
  state.ctx.commandList.setGraphicsRootSignature(state.rootSignature)
  state.ctx.commandList.setPipelineState(state.pipelineState)

  var barrier = D3D12_RESOURCE_BARRIER(
    typ: D3D12_RESOURCE_BARRIER_TYPE_TRANSITION,
    Flags: D3D12_RESOURCE_BARRIER_FLAG_NONE,
    data: D3D12_RESOURCE_BARRIER_union(Transition: D3D12_RESOURCE_TRANSITION_BARRIER(
      pResource: state.ctx.renderTargets[state.ctx.currentFrame],
      Subresource: D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
      StateBefore: D3D12_RESOURCE_STATE_PRESENT,
      StateAfter: D3D12_RESOURCE_STATE_RENDER_TARGET
    ))
  )
  state.ctx.commandList.resourceBarrier(1, addr barrier)
  state.ctx.commandList.rsSetViewports(1, addr state.ctx.viewport)
  state.ctx.commandList.rsSetScissorRects(1, addr state.ctx.scissor)
  state.ctx.commandList.omSetRenderTargets(
    1,
    addr state.ctx.rtvHandles[state.ctx.currentFrame],
    1,
    nil
  )
  state.ctx.commandList.clearRenderTargetView(
    state.ctx.rtvHandles[state.ctx.currentFrame],
    unsafeAddr state.clearColor[0],
    0,
    nil
  )

  var heaps = [state.srvHeap]
  state.ctx.commandList.setDescriptorHeaps(1, addr heaps[0])
  var shaderUniforms = [
    state.viewportSize.x.float32,
    state.viewportSize.y.float32,
    atlasSize.x,
    atlasSize.y
  ]
  state.ctx.commandList.setGraphicsRoot32BitConstants(
    0,
    uint32(shaderUniforms.len),
    unsafeAddr shaderUniforms[0],
    0
  )
  state.ctx.commandList.setGraphicsRootDescriptorTable(
    1,
    state.srvHandleGpu
  )
  state.ctx.commandList.iaSetPrimitiveTopology(
    D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST
  )
  state.ctx.commandList.iaSetVertexBuffers(
    0,
    1,
    unsafeAddr state.vertexBufferView
  )
  if vertexCount > 0:
    state.ctx.commandList.drawInstanced(uint32(vertexCount), 1, 0, 0)

  barrier.data.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET
  barrier.data.Transition.StateAfter = D3D12_RESOURCE_STATE_PRESENT
  state.ctx.commandList.resourceBarrier(1, addr barrier)
  state.ctx.commandList.close()

proc endFrame*(
  drawer: Drawer,
  image: Image,
  size: Vec2,
  quads: pointer,
  quadCount: int
) =
  ## Flushes the queued draws through DirectX 12.
  discard size
  let
    atlasSize = vec2(image.width.float32, image.height.float32)
    vertexCount = quadCount
  drawer.ensureVertexCapacity(vertexCount)

  var vertices = newSeqOfCap[DrawerVertex](vertexCount)
  let quadsArr = cast[ptr UncheckedArray[DrawerVertex]](quads)
  for i in 0 ..< quadCount:
    vertices.add(quadsArr[i])

  if vertexCount > 0:
    copyMem(
      drawer.vertexBufferPtr,
      unsafeAddr vertices[0],
      vertexCount * sizeof(DrawerVertex)
    )

  drawer.recordDraw(vertexCount, atlasSize)
  drawer.ctx.executeFrame(
    if drawer.window != nil: drawer.window.vsync else: true
  )
