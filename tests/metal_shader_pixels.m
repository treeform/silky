// Invoked by test_metal_shader_pixels.nim with its generated shader directory.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

typedef struct __attribute__((packed)) {
  float pos[2], uv[2];
  uint8_t color[4];
  float clipPos[2], clipSize[2], maskUv[2];
} SilkyVertex;

// Compiles the generated shaders and checks pixels from four clipped quads.
int main(int argc, const char **argv) {
  @autoreleasepool {
    if (argc != 2) {
      NSLog(@"Expected the generated shader directory");
      return 1;
    }
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
      NSLog(@"No Metal device");
      return 1;
    }
    NSError *error = nil;
    NSString *directory = [NSString stringWithUTF8String:argv[1]];
    NSString *vertexSource = [NSString
      stringWithContentsOfFile:
        [directory stringByAppendingPathComponent:@"vertex.metal"]
      encoding:NSUTF8StringEncoding error:&error];
    NSString *fragmentSource = [NSString
      stringWithContentsOfFile:
        [directory stringByAppendingPathComponent:@"fragment.metal"]
      encoding:NSUTF8StringEncoding error:&error];
    if (!vertexSource || !fragmentSource) {
      NSLog(@"Cannot read generated shaders: %@", error);
      return 1;
    }
    id<MTLLibrary> vertexLibrary = [device
      newLibraryWithSource:vertexSource options:nil error:&error];
    if (!vertexLibrary) {
      NSLog(@"Vertex shader failed: %@", error);
      return 2;
    }
    id<MTLLibrary> fragmentLibrary = [device
      newLibraryWithSource:fragmentSource options:nil error:&error];
    if (!fragmentLibrary) {
      NSLog(@"Fragment shader failed: %@", error);
      return 3;
    }

    MTLRenderPipelineDescriptor *descriptor =
      [MTLRenderPipelineDescriptor new];
    descriptor.vertexFunction =
      [vertexLibrary newFunctionWithName:@"vertexMain"];
    descriptor.fragmentFunction =
      [fragmentLibrary newFunctionWithName:@"fragmentMain"];
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    MTLVertexDescriptor *vertices = [MTLVertexDescriptor vertexDescriptor];
    NSUInteger offsets[] = {0, 8, 16, 20, 28, 36};
    for (NSUInteger i = 0; i < 6; ++i) {
      vertices.attributes[i].format = i == 2 ?
        MTLVertexFormatUChar4Normalized : MTLVertexFormatFloat2;
      vertices.attributes[i].offset = offsets[i];
      vertices.attributes[i].bufferIndex = 1;
    }
    vertices.layouts[1].stride = 44;
    vertices.layouts[1].stepFunction = MTLVertexStepFunctionPerVertex;
    descriptor.vertexDescriptor = vertices;
    id<MTLRenderPipelineState> pipeline = [device
      newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (!pipeline) {
      NSLog(@"Pipeline link failed: %@", error);
      return 4;
    }
    _Static_assert(sizeof(SilkyVertex) == 44, "Unexpected vertex size");

    MTLTextureDescriptor *targetDescriptor = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
      width:16 height:8 mipmapped:NO];
    targetDescriptor.storageMode = MTLStorageModeShared;
    targetDescriptor.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> target = [device newTextureWithDescriptor:targetDescriptor];
    MTLTextureDescriptor *atlasDescriptor = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
      width:4 height:1 mipmapped:NO];
    atlasDescriptor.storageMode = MTLStorageModeShared;
    atlasDescriptor.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> atlas = [device newTextureWithDescriptor:atlasDescriptor];
    uint8_t atlasPixels[] = {
      255, 255, 255, 255,
      255, 255, 255, 255,
      128, 128, 128, 255,
      0, 0, 0, 255
    };
    [atlas replaceRegion:MTLRegionMake2D(0, 0, 4, 1) mipmapLevel:0
      withBytes:atlasPixels bytesPerRow:16];
    MTLSamplerDescriptor *samplerDescriptor = [MTLSamplerDescriptor new];
    samplerDescriptor.minFilter = MTLSamplerMinMagFilterNearest;
    samplerDescriptor.magFilter = MTLSamplerMinMagFilterNearest;
    samplerDescriptor.normalizedCoordinates = YES;
    samplerDescriptor.sAddressMode = MTLSamplerAddressModeClampToEdge;
    samplerDescriptor.tAddressMode = MTLSamplerAddressModeClampToEdge;
    id<MTLSamplerState> sampler =
      [device newSamplerStateWithDescriptor:samplerDescriptor];

    // Raw atlas pixels exercise shader normalization, including mask UVs.
    SilkyVertex vertexData[24] = {0};
    float corners[6][2] = {
      {0, 0}, {4, 0}, {4, 8}, {0, 0}, {4, 8}, {0, 8}
    };
    uint8_t colors[4][4] = {
      {0, 0, 255, 255}, {0, 255, 0, 255},
      {255, 0, 0, 255}, {255, 0, 0, 255}
    };
    for (int quad = 0; quad < 4; ++quad) {
      for (int i = 0; i < 6; ++i) {
        SilkyVertex *vertex = &vertexData[quad * 6 + i];
        vertex->pos[0] = quad * 4 + corners[i][0];
        vertex->pos[1] = corners[i][1];
        vertex->uv[0] = 0.5;
        vertex->uv[1] = 0.5;
        memcpy(vertex->color, colors[quad], 4);
        vertex->clipSize[0] = 16;
        vertex->clipSize[1] = 4;
        vertex->maskUv[0] = quad == 0 ? -1 : quad + 0.5;
        vertex->maskUv[1] = quad == 0 ? -1 : 0.5;
      }
    }
    float uniforms[4] = {16, 8, 4, 1};
    MTLRenderPassDescriptor *pass =
      [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = target;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    id<MTLCommandQueue> queue = [device newCommandQueue];
    id<MTLCommandBuffer> command = [queue commandBuffer];
    id<MTLRenderCommandEncoder> encoder =
      [command renderCommandEncoderWithDescriptor:pass];
    [encoder setRenderPipelineState:pipeline];
    [encoder setVertexBytes:uniforms length:sizeof(uniforms) atIndex:0];
    [encoder setVertexBytes:vertexData length:sizeof(vertexData) atIndex:1];
    [encoder setFragmentTexture:atlas atIndex:0];
    [encoder setFragmentSamplerState:sampler atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
      vertexStart:0 vertexCount:24];
    [encoder endEncoding];
    [command commit];
    [command waitUntilCompleted];
    if (command.error) {
      NSLog(@"Offscreen render failed: %@", command.error);
      return 5;
    }

    // BGRA samples verify blue, green, half-masked red, and uncolored white.
    uint8_t pixels[16 * 8 * 4];
    [target getBytes:pixels bytesPerRow:64
      fromRegion:MTLRegionMake2D(0, 0, 16, 8) mipmapLevel:0];
    uint8_t expected[4][4] = {
      {255, 0, 0, 255}, {0, 255, 0, 255},
      {127, 127, 255, 255}, {255, 255, 255, 255}
    };
    for (int quad = 0; quad < 4; ++quad) {
      uint8_t *rendered = &pixels[(2 * 16 + quad * 4 + 2) * 4];
      uint8_t *clipped = &pixels[(6 * 16 + quad * 4 + 2) * 4];
      for (int channel = 0; channel < 4; ++channel) {
        if (abs(rendered[channel] - expected[quad][channel]) > 1) {
          NSLog(@"Quad %d channel %d: %d != %d", quad, channel,
            rendered[channel], expected[quad][channel]);
          return 6;
        }
        if (clipped[channel] != (channel == 3 ? 255 : 0)) {
          NSLog(@"Clipping failed for quad %d, channel %d", quad, channel);
          return 7;
        }
      }
    }
    NSLog(@"Silky Metal pixels passed: normalized colors, pixel mask UVs, "
      "zero/half/full masks, uniforms, and clipping");
  }
  return 0;
}
