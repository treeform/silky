when not defined(windows):
  {.error: "The Silky Vulkan backend currently requires Windows.".}

import
  pixie, vmath, windy
import pkg/vk14 except Window

when not defined(shadyBinaryShaders):
  import std/os, shady, silky/drawers/shader

const
  InitialVertexCapacity = 4096

when not defined(shadyBinaryShaders):
  const
    ShaderDir = currentSourcePath().parentDir / "shaders"
    VertexGlslPath = ShaderDir / "silky.vert"
    FragmentGlslPath = ShaderDir / "silky.frag"
    VertexSpvPath = ShaderDir / "silky.vert.spv"
    FragmentSpvPath = ShaderDir / "silky.frag.spv"

const
  ShaderUniformFloatCount = 4

type
  DrawerVertex* {.packed.} = object
    pos*: Vec2
    uv*: Vec2
    color*: ColorRGBX
    clipPos*: Vec2
    clipSize*: Vec2
    maskUv*: Vec2

  VkRenderer = object
    descriptorSetLayout: VkDescriptorSetLayout
    pipelineLayout: VkPipelineLayout
    renderPass: VkRenderPass
    pipeline: VkPipeline
    imageViews: seq[VkImageView]
    framebuffers: seq[VkFramebuffer]
    commandBuffers: seq[VkCommandBuffer]
    textureImage: VkImage
    textureImageMemory: VkDeviceMemory
    textureImageView: VkImageView
    textureSampler: VkSampler
    descriptorPool: VkDescriptorPool
    descriptorSet: VkDescriptorSet
    vertexBuffer: VkBuffer
    vertexBufferMemory: VkDeviceMemory
    vertexBufferPtr: pointer
    maxVertexCount: int

  Drawer* = ref object
    window: Window
    ctx: VulkanContext
    renderer: VkRenderer
    viewportSize: IVec2
    clearColor: array[4, float32]
    pendingResize: bool
    layers*: array[2, seq[DrawerVertex]]
    currentLayer*: int
    layerStack*: seq[int]

proc clampViewport(size: IVec2): IVec2 =
  ivec2(max(1'i32, size.x), max(1'i32, size.y))

proc requiresSwapChainRecreate(vkResult: VkResult): bool =
  let code = vkResult.int32
  code == VK_SUBOPTIMAL_KHR.int32 or
    code == VK_ERROR_OUT_OF_DATE_KHR.int32

proc findMemoryType(
  ctx: VulkanContext, typeFilter: uint32, properties: uint32
): uint32 =
  var memProperties: VkPhysicalDeviceMemoryProperties
  vkGetPhysicalDeviceMemoryProperties(
    ctx.physicalDevice, memProperties.addr)
  for i in 0'u32 ..< memProperties.memoryTypeCount:
    let flags = memProperties.memoryTypes[i].propertyFlags.uint32
    if ((typeFilter shr i) and 1'u32) == 1'u32 and
       (flags and properties) == properties:
      return i
  raise newException(Exception,
    "Failed to find suitable Vulkan memory type")

proc createShaderModule(device: VkDevice, code: string): VkShaderModule =
  var createInfo = VkShaderModuleCreateInfo(
    sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
    codeSize: code.len.uint32,
    pCode: cast[ptr uint32](code[0].unsafeAddr)
  )
  checkVk(vkCreateShaderModule(
    device, createInfo.addr, nil, result.addr),
    "Creating shader module")

proc createBuffer(
  ctx: VulkanContext, size: VkDeviceSize, usage, properties: uint32,
  buffer: var VkBuffer, memory: var VkDeviceMemory
) =
  var bufferInfo = VkBufferCreateInfo(
    sType: VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
    size: size,
    usage: VkBufferUsageFlags(usage),
    sharingMode: VK_SHARING_MODE_EXCLUSIVE,
  )
  checkVk(vkCreateBuffer(
    ctx.device, bufferInfo.addr, nil, buffer.addr),
    "Creating buffer")

  var memRequirements: VkMemoryRequirements
  vkGetBufferMemoryRequirements(ctx.device, buffer, memRequirements.addr)

  var allocInfo = VkMemoryAllocateInfo(
    sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
    allocationSize: memRequirements.size,
    memoryTypeIndex: findMemoryType(
      ctx, memRequirements.memoryTypeBits, properties)
  )
  checkVk(vkAllocateMemory(
    ctx.device, allocInfo.addr, nil, memory.addr),
    "Allocating buffer memory")
  checkVk(vkBindBufferMemory(
    ctx.device, buffer, memory, VkDeviceSize(0)),
    "Binding buffer memory")

proc beginSingleTimeCommands(ctx: VulkanContext): VkCommandBuffer =
  var allocInfo = VkCommandBufferAllocateInfo(
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
    commandPool: ctx.commandPool,
    level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,
    commandBufferCount: 1
  )
  checkVk(vkAllocateCommandBuffers(
    ctx.device, allocInfo.addr, result.addr),
    "Allocating single-use command buffer")
  var beginInfo = VkCommandBufferBeginInfo(
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    flags: VkCommandBufferUsageFlags(
      VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT)
  )
  checkVk(vkBeginCommandBuffer(result, beginInfo.addr),
    "Beginning single-use command buffer")

proc endSingleTimeCommands(
  ctx: VulkanContext, commandBuffer: VkCommandBuffer
) =
  checkVk(vkEndCommandBuffer(commandBuffer),
    "Ending single-use command buffer")
  var submitInfo = VkSubmitInfo(
    sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,
    commandBufferCount: 1,
    pCommandBuffers: unsafeAddr commandBuffer
  )
  checkVk(vkQueueSubmit(
    ctx.graphicsQueue, 1, submitInfo.addr, VkFence(0)),
    "Submitting single-use command buffer")
  checkVk(vkQueueWaitIdle(ctx.graphicsQueue),
    "Waiting for queue idle")
  vkFreeCommandBuffers(
    ctx.device, ctx.commandPool, 1, unsafeAddr commandBuffer)

proc transitionImageLayout(
  ctx: VulkanContext, image: VkImage,
  oldLayout, newLayout: VkImageLayout
) =
  let commandBuffer = beginSingleTimeCommands(ctx)
  var barrier = VkImageMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    oldLayout: oldLayout,
    newLayout: newLayout,
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    image: image,
    subresourceRange: VkImageSubresourceRange(
      aspectMask: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT),
      baseMipLevel: 0, levelCount: 1,
      baseArrayLayer: 0, layerCount: 1
    )
  )

  var sourceStage, destinationStage: VkPipelineStageFlags
  if oldLayout == VK_IMAGE_LAYOUT_UNDEFINED and
     newLayout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL:
    barrier.srcAccessMask = VkAccessFlags(0)
    barrier.dstAccessMask = VkAccessFlags(VK_ACCESS_TRANSFER_WRITE_BIT)
    sourceStage = VkPipelineStageFlags(VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT)
    destinationStage = VkPipelineStageFlags(VK_PIPELINE_STAGE_TRANSFER_BIT)
  elif oldLayout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL and
       newLayout == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL:
    barrier.srcAccessMask = VkAccessFlags(VK_ACCESS_TRANSFER_WRITE_BIT)
    barrier.dstAccessMask = VkAccessFlags(VK_ACCESS_SHADER_READ_BIT)
    sourceStage = VkPipelineStageFlags(VK_PIPELINE_STAGE_TRANSFER_BIT)
    destinationStage = VkPipelineStageFlags(
      VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT)
  else:
    raise newException(Exception, "Unsupported layout transition")

  vkCmdPipelineBarrier(commandBuffer, sourceStage, destinationStage,
    VkDependencyFlags(0), 0, nil, 0, nil, 1, barrier.addr)
  endSingleTimeCommands(ctx, commandBuffer)

proc uploadTexture(ctx: VulkanContext, renderer: var VkRenderer, image: Image) =
  let
    texWidth = image.width
    texHeight = image.height
    imageSize = VkDeviceSize(texWidth * texHeight * 4)

  var stagingBuffer: VkBuffer
  var stagingBufferMemory: VkDeviceMemory
  createBuffer(ctx, imageSize,
    VK_BUFFER_USAGE_TRANSFER_SRC_BIT.uint32,
    VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.uint32 or
      VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.uint32,
    stagingBuffer, stagingBufferMemory)

  var mapped: pointer
  checkVk(vkMapMemory(ctx.device, stagingBufferMemory,
    VkDeviceSize(0), imageSize, VkMemoryMapFlags(0), mapped.addr),
    "Mapping staging buffer")
  for y in 0 ..< texHeight:
    let srcIdx = image.dataIndex(0, y)
    let srcPtr = cast[ptr uint8](image.data[srcIdx].addr)
    let dst = cast[pointer](cast[uint](mapped) + uint(y * texWidth * 4))
    copyMem(dst, srcPtr, texWidth * 4)
  vkUnmapMemory(ctx.device, stagingBufferMemory)

  var imageInfo = VkImageCreateInfo(
    sType: VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
    imageType: VK_IMAGE_TYPE_2D,
    format: VK_FORMAT_R8G8B8A8_UNORM,
    extent: VkExtent3D(
      width: uint32(texWidth), height: uint32(texHeight), depth: 1),
    mipLevels: 1, arrayLayers: 1,
    samples: VK_SAMPLE_COUNT_1_BIT,
    tiling: VK_IMAGE_TILING_OPTIMAL,
    usage: VkImageUsageFlags(
      VK_IMAGE_USAGE_TRANSFER_DST_BIT.uint32 or
      VK_IMAGE_USAGE_SAMPLED_BIT.uint32),
    sharingMode: VK_SHARING_MODE_EXCLUSIVE,
    initialLayout: VK_IMAGE_LAYOUT_UNDEFINED
  )
  checkVk(vkCreateImage(
    ctx.device, imageInfo.addr, nil, renderer.textureImage.addr),
    "Creating texture image")

  var memRequirements: VkMemoryRequirements
  vkGetImageMemoryRequirements(
    ctx.device, renderer.textureImage, memRequirements.addr)
  var allocInfo = VkMemoryAllocateInfo(
    sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
    allocationSize: memRequirements.size,
    memoryTypeIndex: findMemoryType(ctx,
      memRequirements.memoryTypeBits,
      VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT.uint32)
  )
  checkVk(vkAllocateMemory(
    ctx.device, allocInfo.addr, nil, renderer.textureImageMemory.addr),
    "Allocating texture memory")
  checkVk(vkBindImageMemory(ctx.device, renderer.textureImage,
    renderer.textureImageMemory, VkDeviceSize(0)),
    "Binding texture memory")

  transitionImageLayout(ctx, renderer.textureImage,
    VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL)

  let commandBuffer = beginSingleTimeCommands(ctx)
  var region = VkBufferImageCopy(
    bufferOffset: VkDeviceSize(0),
    imageSubresource: VkImageSubresourceLayers(
      aspectMask: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT),
      mipLevel: 0, baseArrayLayer: 0, layerCount: 1
    ),
    imageExtent: VkExtent3D(
      width: uint32(texWidth), height: uint32(texHeight), depth: 1)
  )
  vkCmdCopyBufferToImage(commandBuffer, stagingBuffer,
    renderer.textureImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    1, region.addr)
  endSingleTimeCommands(ctx, commandBuffer)

  transitionImageLayout(ctx, renderer.textureImage,
    VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)

  vkDestroyBuffer(ctx.device, stagingBuffer, nil)
  vkFreeMemory(ctx.device, stagingBufferMemory, nil)

  var imageViewInfo = VkImageViewCreateInfo(
    sType: VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
    image: renderer.textureImage,
    viewType: VK_IMAGE_VIEW_TYPE_2D,
    format: VK_FORMAT_R8G8B8A8_UNORM,
    components: VkComponentMapping(
      r: VK_COMPONENT_SWIZZLE_IDENTITY,
      g: VK_COMPONENT_SWIZZLE_IDENTITY,
      b: VK_COMPONENT_SWIZZLE_IDENTITY,
      a: VK_COMPONENT_SWIZZLE_IDENTITY),
    subresourceRange: VkImageSubresourceRange(
      aspectMask: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT),
      baseMipLevel: 0, levelCount: 1,
      baseArrayLayer: 0, layerCount: 1)
  )
  checkVk(vkCreateImageView(
    ctx.device, imageViewInfo.addr, nil, renderer.textureImageView.addr),
    "Creating texture image view")

  var samplerInfo = VkSamplerCreateInfo(
    sType: VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
    magFilter: VK_FILTER_LINEAR,
    minFilter: VK_FILTER_LINEAR,
    mipmapMode: VK_SAMPLER_MIPMAP_MODE_LINEAR,
    addressModeU: VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
    addressModeV: VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
    addressModeW: VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
    anisotropyEnable: VkBool32(VK_FALSE),
    maxAnisotropy: 1,
    compareEnable: VkBool32(VK_FALSE),
    compareOp: VK_COMPARE_OP_ALWAYS,
    minLod: 0, maxLod: 0,
    borderColor: VK_BORDER_COLOR_INT_OPAQUE_BLACK,
    unnormalizedCoordinates: VkBool32(VK_FALSE)
  )
  checkVk(vkCreateSampler(
    ctx.device, samplerInfo.addr, nil, renderer.textureSampler.addr),
    "Creating texture sampler")

proc createDescriptorResources(
  ctx: VulkanContext, renderer: var VkRenderer
) =
  var layoutBinding = VkDescriptorSetLayoutBinding(
    binding: 0,
    descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    descriptorCount: 1,
    stageFlags: VkShaderStageFlags(VK_SHADER_STAGE_FRAGMENT_BIT),
  )
  var layoutInfo = VkDescriptorSetLayoutCreateInfo(
    sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
    bindingCount: 1, pBindings: layoutBinding.addr
  )
  checkVk(vkCreateDescriptorSetLayout(
    ctx.device, layoutInfo.addr, nil,
    renderer.descriptorSetLayout.addr),
    "Creating descriptor set layout")

  var poolSize = VkDescriptorPoolSize(
    `type`: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    descriptorCount: 1)
  var poolInfo = VkDescriptorPoolCreateInfo(
    sType: VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    maxSets: 1, poolSizeCount: 1, pPoolSizes: poolSize.addr
  )
  checkVk(vkCreateDescriptorPool(
    ctx.device, poolInfo.addr, nil, renderer.descriptorPool.addr),
    "Creating descriptor pool")

  var setLayout = renderer.descriptorSetLayout
  var setAllocInfo = VkDescriptorSetAllocateInfo(
    sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    descriptorPool: renderer.descriptorPool,
    descriptorSetCount: 1, pSetLayouts: setLayout.addr
  )
  checkVk(vkAllocateDescriptorSets(
    ctx.device, setAllocInfo.addr, renderer.descriptorSet.addr),
    "Allocating descriptor set")

  var imgInfo = VkDescriptorImageInfo(
    sampler: renderer.textureSampler,
    imageView: renderer.textureImageView,
    imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
  )
  var descriptorWrite = VkWriteDescriptorSet(
    sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
    dstSet: renderer.descriptorSet,
    dstBinding: 0, dstArrayElement: 0,
    descriptorCount: 1,
    descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    pImageInfo: imgInfo.addr,
  )
  vkUpdateDescriptorSets(ctx.device, 1, descriptorWrite.addr, 0, nil)

proc createSwapChainImageViews(
  ctx: VulkanContext, renderer: var VkRenderer
) =
  renderer.imageViews.setLen(ctx.swapChainImages.len)
  for i, image in ctx.swapChainImages:
    var createInfo = VkImageViewCreateInfo(
      sType: VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
      image: image,
      viewType: VK_IMAGE_VIEW_TYPE_2D,
      format: ctx.swapChainImageFormat,
      components: VkComponentMapping(
        r: VK_COMPONENT_SWIZZLE_IDENTITY,
        g: VK_COMPONENT_SWIZZLE_IDENTITY,
        b: VK_COMPONENT_SWIZZLE_IDENTITY,
        a: VK_COMPONENT_SWIZZLE_IDENTITY),
      subresourceRange: VkImageSubresourceRange(
        aspectMask: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT),
        baseMipLevel: 0, levelCount: 1,
        baseArrayLayer: 0, layerCount: 1)
    )
    checkVk(vkCreateImageView(
      ctx.device, createInfo.addr, nil, renderer.imageViews[i].addr),
      "Creating swapchain image view")

proc createRenderPass(ctx: VulkanContext, renderer: var VkRenderer) =
  var
    colorAttachment = VkAttachmentDescription(
      format: ctx.swapChainImageFormat,
      samples: VK_SAMPLE_COUNT_1_BIT,
      loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,
      storeOp: VK_ATTACHMENT_STORE_OP_STORE,
      stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,
      stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
      initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
      finalLayout: VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
    )
    colorAttachmentRef = VkAttachmentReference(
      attachment: 0,
      layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL)
    subpass = VkSubpassDescription(
      pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
      colorAttachmentCount: 1,
      pColorAttachments: colorAttachmentRef.addr
    )
    dependency = VkSubpassDependency(
      srcSubpass: VK_SUBPASS_EXTERNAL, dstSubpass: 0,
      srcStageMask: VkPipelineStageFlags(
        VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
      srcAccessMask: VkAccessFlags(0),
      dstStageMask: VkPipelineStageFlags(
        VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
      dstAccessMask: VkAccessFlags(
        VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT)
    )
    renderPassInfo = VkRenderPassCreateInfo(
      sType: VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
      attachmentCount: 1, pAttachments: colorAttachment.addr,
      subpassCount: 1, pSubpasses: subpass.addr,
      dependencyCount: 1, pDependencies: dependency.addr
    )
  checkVk(vkCreateRenderPass(
    ctx.device, renderPassInfo.addr, nil, renderer.renderPass.addr),
    "Creating render pass")

proc createGraphicsPipeline(ctx: VulkanContext, renderer: var VkRenderer) =
  when defined(shadyBinaryShaders):
    const
      vertShaderCode = staticRead("shaders/silky.vert.spv")
      fragShaderCode = staticRead("shaders/silky.frag.spv")
  else:
    const
      vertShaderCode = compileSpirvShader(
        toShader(silkyVert, vulkanGlsl450, shaderVertex),
        VertexGlslPath,
        VertexSpvPath,
        binaryVertex
      )
      fragShaderCode = compileSpirvShader(
        toShader(silkyFrag, vulkanGlsl450, shaderFragment),
        FragmentGlslPath,
        FragmentSpvPath,
        binaryFragment
      )
  let
    vertModule = createShaderModule(ctx.device, vertShaderCode)
    fragModule = createShaderModule(ctx.device, fragShaderCode)
  try:
    var
      vertStage = VkPipelineShaderStageCreateInfo(
        sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage: VK_SHADER_STAGE_VERTEX_BIT,
        module: vertModule, pName: "main")
      fragStage = VkPipelineShaderStageCreateInfo(
        sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage: VK_SHADER_STAGE_FRAGMENT_BIT,
        module: fragModule, pName: "main")
      shaderStages = [vertStage, fragStage]

      bindingDesc = VkVertexInputBindingDescription(
        binding: 0,
        stride: uint32(sizeof(DrawerVertex)),
        inputRate: VK_VERTEX_INPUT_RATE_VERTEX)
      attributeDescs = [
        VkVertexInputAttributeDescription(
          location: 0, binding: 0,
          format: VK_FORMAT_R32G32_SFLOAT, offset: 0),
        VkVertexInputAttributeDescription(
          location: 1, binding: 0,
          format: VK_FORMAT_R32G32_SFLOAT, offset: 8),
        VkVertexInputAttributeDescription(
          location: 2, binding: 0,
          format: VK_FORMAT_R8G8B8A8_UNORM, offset: 16),
        VkVertexInputAttributeDescription(
          location: 3, binding: 0,
          format: VK_FORMAT_R32G32_SFLOAT, offset: 20),
        VkVertexInputAttributeDescription(
          location: 4, binding: 0,
          format: VK_FORMAT_R32G32_SFLOAT, offset: 28),
        VkVertexInputAttributeDescription(
          location: 5, binding: 0,
          format: VK_FORMAT_R32G32_SFLOAT, offset: 36),
      ]
      vertexInputInfo = VkPipelineVertexInputStateCreateInfo(
        sType: VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount: 1,
        pVertexBindingDescriptions: bindingDesc.addr,
        vertexAttributeDescriptionCount: uint32(attributeDescs.len),
        pVertexAttributeDescriptions: attributeDescs[0].addr)
      inputAssembly = VkPipelineInputAssemblyStateCreateInfo(
        sType: VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        primitiveRestartEnable: VkBool32(VK_FALSE))
      viewport = VkViewport(x: 0, y: 0,
        width: ctx.swapChainExtent.width.float32,
        height: ctx.swapChainExtent.height.float32,
        minDepth: 0, maxDepth: 1)
      scissor = VkRect2D(
        offset: VkOffset2D(x: 0, y: 0),
        extent: ctx.swapChainExtent)
      viewportState = VkPipelineViewportStateCreateInfo(
        sType: VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount: 1, pViewports: viewport.addr,
        scissorCount: 1, pScissors: scissor.addr)
      rasterizer = VkPipelineRasterizationStateCreateInfo(
        sType: VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        depthClampEnable: VkBool32(VK_FALSE),
        rasterizerDiscardEnable: VkBool32(VK_FALSE),
        polygonMode: VK_POLYGON_MODE_FILL,
        lineWidth: 1.0,
        cullMode: VkCullModeFlags(VK_CULL_MODE_NONE),
        frontFace: VK_FRONT_FACE_CLOCKWISE,
        depthBiasEnable: VkBool32(VK_FALSE))
      multisampling = VkPipelineMultisampleStateCreateInfo(
        sType: VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        sampleShadingEnable: VkBool32(VK_FALSE),
        rasterizationSamples: VK_SAMPLE_COUNT_1_BIT)
      colorBlendAttachment = VkPipelineColorBlendAttachmentState(
        colorWriteMask: VkColorComponentFlags(0x0000000F),
        blendEnable: VkBool32(VK_TRUE),
        srcColorBlendFactor: VK_BLEND_FACTOR_ONE,
        dstColorBlendFactor: VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        colorBlendOp: VK_BLEND_OP_ADD,
        srcAlphaBlendFactor: VK_BLEND_FACTOR_ONE,
        dstAlphaBlendFactor: VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        alphaBlendOp: VK_BLEND_OP_ADD)
      colorBlending = VkPipelineColorBlendStateCreateInfo(
        sType: VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        logicOpEnable: VkBool32(VK_FALSE),
        logicOp: VK_LOGIC_OP_COPY,
        attachmentCount: 1,
        pAttachments: colorBlendAttachment.addr,
        blendConstants: [0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32])

      pushConstantRange = VkPushConstantRange(
        stageFlags: VkShaderStageFlags(VK_SHADER_STAGE_VERTEX_BIT),
        offset: 0,
        size: uint32(ShaderUniformFloatCount * sizeof(float32)))
      pipelineLayoutInfo = VkPipelineLayoutCreateInfo(
        sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount: 1,
        pSetLayouts: renderer.descriptorSetLayout.addr,
        pushConstantRangeCount: 1,
        pPushConstantRanges: pushConstantRange.addr)

    checkVk(vkCreatePipelineLayout(
      ctx.device, pipelineLayoutInfo.addr, nil,
      renderer.pipelineLayout.addr),
      "Creating pipeline layout")

    var pipelineInfo = VkGraphicsPipelineCreateInfo(
      sType: VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
      stageCount: uint32(shaderStages.len),
      pStages: shaderStages[0].addr,
      pVertexInputState: vertexInputInfo.addr,
      pInputAssemblyState: inputAssembly.addr,
      pViewportState: viewportState.addr,
      pRasterizationState: rasterizer.addr,
      pMultisampleState: multisampling.addr,
      pDepthStencilState: nil,
      pColorBlendState: colorBlending.addr,
      pDynamicState: nil,
      layout: renderer.pipelineLayout,
      renderPass: renderer.renderPass,
      subpass: 0
    )
    checkVk(vkCreateGraphicsPipelines(
      ctx.device, VkPipelineCache(0), 1, pipelineInfo.addr, nil,
      renderer.pipeline.addr),
      "Creating graphics pipeline")
  finally:
    vkDestroyShaderModule(ctx.device, vertModule, nil)
    vkDestroyShaderModule(ctx.device, fragModule, nil)

proc createFramebuffers(ctx: VulkanContext, renderer: var VkRenderer) =
  renderer.framebuffers.setLen(renderer.imageViews.len)
  for i, imageView in renderer.imageViews:
    var attachments = [imageView]
    var framebufferInfo = VkFramebufferCreateInfo(
      sType: VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
      renderPass: renderer.renderPass,
      attachmentCount: 1, pAttachments: attachments[0].addr,
      width: ctx.swapChainExtent.width,
      height: ctx.swapChainExtent.height,
      layers: 1
    )
    checkVk(vkCreateFramebuffer(
      ctx.device, framebufferInfo.addr, nil,
      renderer.framebuffers[i].addr),
      "Creating framebuffer")

proc createVertexBuffer(
  ctx: VulkanContext, renderer: var VkRenderer, maxVertexCount: int
) =
  if renderer.vertexBuffer.int64 != 0:
    if renderer.vertexBufferPtr != nil:
      vkUnmapMemory(ctx.device, renderer.vertexBufferMemory)
      renderer.vertexBufferPtr = nil
    vkDestroyBuffer(ctx.device, renderer.vertexBuffer, nil)
    vkFreeMemory(ctx.device, renderer.vertexBufferMemory, nil)
    renderer.vertexBuffer = VkBuffer(0)
    renderer.vertexBufferMemory = VkDeviceMemory(0)

  let bufferSize = VkDeviceSize(maxVertexCount * sizeof(DrawerVertex))
  createBuffer(ctx, bufferSize,
    VK_BUFFER_USAGE_VERTEX_BUFFER_BIT.uint32,
    VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.uint32 or
      VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.uint32,
    renderer.vertexBuffer, renderer.vertexBufferMemory)
  checkVk(vkMapMemory(ctx.device, renderer.vertexBufferMemory,
    VkDeviceSize(0), bufferSize, VkMemoryMapFlags(0),
    renderer.vertexBufferPtr.addr),
    "Mapping vertex buffer")
  renderer.maxVertexCount = maxVertexCount

proc allocateCommandBuffers(
  ctx: VulkanContext, renderer: var VkRenderer
) =
  renderer.commandBuffers.setLen(ctx.swapChainImages.len)
  var allocInfo = VkCommandBufferAllocateInfo(
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
    commandPool: ctx.commandPool,
    level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,
    commandBufferCount: uint32(renderer.commandBuffers.len)
  )
  checkVk(vkAllocateCommandBuffers(
    ctx.device, allocInfo.addr, renderer.commandBuffers[0].addr),
    "Allocating command buffers")

proc destroySwapChainResources(
  ctx: VulkanContext, renderer: var VkRenderer
) =
  if renderer.commandBuffers.len > 0:
    vkFreeCommandBuffers(ctx.device, ctx.commandPool,
      uint32(renderer.commandBuffers.len),
      renderer.commandBuffers[0].addr)
    renderer.commandBuffers.setLen(0)
  for fb in renderer.framebuffers:
    vkDestroyFramebuffer(ctx.device, fb, nil)
  renderer.framebuffers.setLen(0)
  for iv in renderer.imageViews:
    vkDestroyImageView(ctx.device, iv, nil)
  renderer.imageViews.setLen(0)
  if renderer.pipeline.int64 != 0:
    vkDestroyPipeline(ctx.device, renderer.pipeline, nil)
    renderer.pipeline = VkPipeline(0)
  if renderer.pipelineLayout.int64 != 0:
    vkDestroyPipelineLayout(ctx.device, renderer.pipelineLayout, nil)
    renderer.pipelineLayout = VkPipelineLayout(0)
  if renderer.renderPass.int64 != 0:
    vkDestroyRenderPass(ctx.device, renderer.renderPass, nil)
    renderer.renderPass = VkRenderPass(0)

proc recreateSwapChainResources(
  state: Drawer, width, height: int
) =
  discard vkDeviceWaitIdle(state.ctx.device)
  destroySwapChainResources(state.ctx, state.renderer)
  recreateSwapChain(state.ctx, width, height)
  createSwapChainImageViews(state.ctx, state.renderer)
  createRenderPass(state.ctx, state.renderer)
  createGraphicsPipeline(state.ctx, state.renderer)
  createFramebuffers(state.ctx, state.renderer)
  allocateCommandBuffers(state.ctx, state.renderer)

proc initRenderer(state: Drawer, image: Image, size: IVec2) =
  uploadTexture(state.ctx, state.renderer, image)
  createDescriptorResources(state.ctx, state.renderer)
  createSwapChainImageViews(state.ctx, state.renderer)
  createRenderPass(state.ctx, state.renderer)
  createGraphicsPipeline(state.ctx, state.renderer)
  createFramebuffers(state.ctx, state.renderer)
  createVertexBuffer(state.ctx, state.renderer, InitialVertexCapacity)
  allocateCommandBuffers(state.ctx, state.renderer)

proc ensureVertexCapacity(state: Drawer, vertexCount: int) =
  if vertexCount <= state.renderer.maxVertexCount:
    return
  discard vkDeviceWaitIdle(state.ctx.device)
  var newCapacity = max(InitialVertexCapacity, state.renderer.maxVertexCount)
  while newCapacity < vertexCount:
    newCapacity *= 2
  createVertexBuffer(state.ctx, state.renderer, newCapacity)

proc newDrawer*(window: Window, image: Image): Drawer =
  let
    safeSize = clampViewport(window.size)
    hwnd = window.getHWND()
  result = Drawer(
    window: window,
    clearColor: [0.0'f32, 0.0'f32, 0.0'f32, 1.0'f32],
    currentLayer: 0,
    layerStack: @[],
    viewportSize: safeSize,
  )
  result.layers[0] = @[]
  result.layers[1] = @[]
  result.ctx.initDevice(hwnd, safeSize.x.int, safeSize.y.int, window.vsync)
  result.initRenderer(image, safeSize)

proc beginFrame*(drawer: Drawer, window: Window, size: IVec2) =
  let safeSize = clampViewport(size)
  drawer.window = window
  if drawer.viewportSize != safeSize:
    drawer.pendingResize = true
    drawer.viewportSize = safeSize

proc clearScreen*(drawer: Drawer, color: ColorRGBX) =
  let c = color.color
  drawer.clearColor = [c.r, c.g, c.b, c.a]

proc endFrame*(
  drawer: Drawer,
  image: Image,
  size: Vec2,
  quads: pointer,
  quadCount: int
) =
  discard size
  let safeSize = drawer.viewportSize

  if drawer.pendingResize:
    drawer.pendingResize = false
    drawer.recreateSwapChainResources(safeSize.x.int, safeSize.y.int)

  let
    atlasSize = vec2(image.width.float32, image.height.float32)
    vertexCount = quadCount
  drawer.ensureVertexCapacity(vertexCount)

  var vertices = newSeqOfCap[DrawerVertex](vertexCount)
  let quadsArr = cast[ptr UncheckedArray[DrawerVertex]](quads)
  for i in 0 ..< quadCount:
    vertices.add(quadsArr[i])

  if vertexCount > 0:
    copyMem(drawer.renderer.vertexBufferPtr,
      unsafeAddr vertices[0],
      vertexCount * sizeof(DrawerVertex))

  let frame = drawer.ctx.currentFrame
  let fence = drawer.ctx.inFlightFences[frame]
  discard vkWaitForFences(
    drawer.ctx.device, 1, unsafeAddr fence,
    VkBool32(VK_TRUE), uint64.high)
  discard vkResetFences(drawer.ctx.device, 1, unsafeAddr fence)

  var imageIndex: uint32
  let acquireResult = vkAcquireNextImageKHR(
    drawer.ctx.device, drawer.ctx.swapChain, uint64.high,
    drawer.ctx.imageAvailableSemaphores[frame],
    VkFence(0), imageIndex.addr)
  if requiresSwapChainRecreate(acquireResult):
    drawer.recreateSwapChainResources(safeSize.x.int, safeSize.y.int)
    return

  let commandBuffer = drawer.renderer.commandBuffers[imageIndex]
  discard vkResetCommandBuffer(commandBuffer, VkCommandBufferResetFlags(0))
  var beginInfo = VkCommandBufferBeginInfo(
    sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO)
  checkVk(vkBeginCommandBuffer(commandBuffer, beginInfo.addr),
    "Beginning command buffer")

  var clearValue = VkClearValue(
    color: VkClearColorValue(float32: drawer.clearColor))
  var renderPassInfo = VkRenderPassBeginInfo(
    sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    renderPass: drawer.renderer.renderPass,
    framebuffer: drawer.renderer.framebuffers[imageIndex],
    renderArea: VkRect2D(
      offset: VkOffset2D(x: 0, y: 0),
      extent: drawer.ctx.swapChainExtent),
    clearValueCount: 1, pClearValues: clearValue.addr
  )

  var vertexBuffers = [drawer.renderer.vertexBuffer]
  var offsets = [VkDeviceSize(0)]
  var descriptorSet = drawer.renderer.descriptorSet
  var shaderUniforms = [
    safeSize.x.float32,
    safeSize.y.float32,
    atlasSize.x,
    atlasSize.y
  ]

  vkCmdBeginRenderPass(
    commandBuffer, renderPassInfo.addr, VK_SUBPASS_CONTENTS_INLINE)
  vkCmdBindPipeline(
    commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS,
    drawer.renderer.pipeline)
  vkCmdBindDescriptorSets(
    commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS,
    drawer.renderer.pipelineLayout,
    0, 1, descriptorSet.addr, 0, nil)
  vkCmdPushConstants(
    commandBuffer, drawer.renderer.pipelineLayout,
    VkShaderStageFlags(VK_SHADER_STAGE_VERTEX_BIT),
    0, uint32(ShaderUniformFloatCount * sizeof(float32)),
    shaderUniforms.addr)
  vkCmdBindVertexBuffers(
    commandBuffer, 0, 1, vertexBuffers[0].addr, offsets[0].addr)
  if vertexCount > 0:
    vkCmdDraw(commandBuffer, uint32(vertexCount), 1, 0, 0)
  vkCmdEndRenderPass(commandBuffer)
  checkVk(vkEndCommandBuffer(commandBuffer), "Ending command buffer")

  var
    waitSemaphores = [drawer.ctx.imageAvailableSemaphores[frame]]
    waitStages: array[1, VkPipelineStageFlags] = [
      VkPipelineStageFlags(
        VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT)]
    signalSemaphores = [drawer.ctx.renderFinishedSemaphores[frame]]
    submitInfo = VkSubmitInfo(
      sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,
      waitSemaphoreCount: 1,
      pWaitSemaphores: waitSemaphores[0].addr,
      pWaitDstStageMask: waitStages[0].addr,
      commandBufferCount: 1,
      pCommandBuffers: unsafeAddr commandBuffer,
      signalSemaphoreCount: 1,
      pSignalSemaphores: signalSemaphores[0].addr)
  checkVk(vkQueueSubmit(
    drawer.ctx.graphicsQueue, 1, submitInfo.addr, fence),
    "Submitting draw command buffer")

  var
    swapChains = [drawer.ctx.swapChain]
    presentInfo = VkPresentInfoKHR(
      sType: VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
      waitSemaphoreCount: 1,
      pWaitSemaphores: signalSemaphores[0].addr,
      swapchainCount: 1,
      pSwapchains: swapChains[0].addr,
      pImageIndices: imageIndex.addr)
  let presentResult = vkQueuePresentKHR(
    drawer.ctx.presentQueue, presentInfo.addr)
  if requiresSwapChainRecreate(presentResult):
    drawer.recreateSwapChainResources(safeSize.x.int, safeSize.y.int)
  drawer.ctx.currentFrame =
    (drawer.ctx.currentFrame + 1) mod FRAME_COUNT
