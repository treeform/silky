import strutils, shady, silky/drawers/shader

proc checkSampleOrder(source, base, mask: string) =
  ## Keeps texture derivatives valid at fragment clipping boundaries.
  let
    baseIndex = source.find(base)
    maskIndex = source.find(mask)
    clipIndex = source.find("fragmentPos.x < fragmentClipPos.x")
    discardIndex = source.find("discard")
  doAssert baseIndex >= 0 and maskIndex >= 0
  doAssert clipIndex >= 0 and discardIndex > clipIndex
  doAssert baseIndex < clipIndex,
    "The atlas must be sampled before nonuniform clipping."
  doAssert maskIndex < clipIndex,
    "The mask must be sampled before nonuniform clipping."

block:
  let vertex = toShader(silkyVert, glsl3Desktop, shaderVertex)
  doAssert "uniform vec2 viewportSize;" in vertex
  doAssert "uniform vec2 atlasSize;" in vertex
  doAssert "in vec2 pos;" in vertex
  doAssert "in vec2 maskUv;" in vertex
  doAssert "out vec2 fragmentUv;" in vertex
  doAssert "out vec2 fragmentMaskUv;" in vertex

  let fragment = toShader(silkyFrag, glsl3Desktop, shaderFragment)
  doAssert "uniform sampler2D atlasSampler;" in fragment
  doAssert "discard" in fragment
  doAssert "texture(atlasSampler, fragmentUv)" in fragment
  doAssert "(texture(atlasSampler, fragmentMaskUv)).r" in fragment
  doAssert "mix(vec3(1.0, 1.0, 1.0), fragmentColor.rgb, maskR)" in fragment
  fragment.checkSampleOrder(
    "texture(atlasSampler, fragmentUv)",
    "texture(atlasSampler, fragmentMaskUv)"
  )

block:
  let vertex = toShader(silkyVert, vulkanGlsl450, shaderVertex)
  doAssert "#version 450" in vertex
  doAssert "layout(push_constant) uniform ShadyPushConstants" in vertex
  doAssert "vec2 viewportSize;" in vertex
  doAssert "vec2 atlasSize;" in vertex
  doAssert "layout(location = 0) in vec2 pos;" in vertex
  doAssert "layout(location = 5) in vec2 maskUv;" in vertex
  doAssert "layout(location = 5) out vec2 fragmentMaskUv;" in vertex
  doAssert "gl_Position.y = -gl_Position.y;" in vertex

  let fragment = toShader(silkyFrag, vulkanGlsl450, shaderFragment)
  doAssert "layout(set = 0, binding = 0) uniform sampler2D atlasSampler;" in fragment
  doAssert "layout(location = 5) in vec2 fragmentMaskUv;" in fragment
  doAssert "layout(location = 0) out vec4 fragColor;" in fragment
  doAssert "(texture(atlasSampler, fragmentMaskUv)).r" in fragment
  fragment.checkSampleOrder(
    "texture(atlasSampler, fragmentUv)",
    "texture(atlasSampler, fragmentMaskUv)"
  )

block:
  let vertex = toHLSL(silkyVert, shaderVertex)
  doAssert "cbuffer ShadyUniforms0 : register(b0)" in vertex
  doAssert "float2 viewportSize;" in vertex
  doAssert "float2 atlasSize;" in vertex
  doAssert "float2 pos : POSITION0" in vertex
  doAssert "float2 maskUv : TEXCOORD3" in vertex
  doAssert "float4 pos : SV_POSITION;" in vertex

  let fragment = toHLSL(silkyFrag, shaderFragment)
  doAssert "Texture2D<float4> atlasSampler : register(t0);" in fragment
  doAssert "SamplerState atlasSamplerSampler : register(s0);" in fragment
  doAssert "struct PSInput" in fragment
  doAssert "float4 pos : SV_POSITION;" in fragment
  doAssert "float4 PSMain(PSInput input) : SV_TARGET" in fragment
  doAssert "atlasSampler.Sample(atlasSamplerSampler, fragmentUv)" in fragment
  doAssert "(atlasSampler.Sample(atlasSamplerSampler, fragmentMaskUv)).r" in fragment
  doAssert "lerp(float3(1.0, 1.0, 1.0), fragmentColor.rgb, maskR)" in fragment
  fragment.checkSampleOrder(
    "atlasSampler.Sample(atlasSamplerSampler, fragmentUv)",
    "atlasSampler.Sample(atlasSamplerSampler, fragmentMaskUv)"
  )

block:
  let fragment = toShader(silkyFrag, metalMSL, shaderFragment)
  fragment.checkSampleOrder(
    "atlasSampler.sample(atlasSamplerSampler, fragmentUv)",
    "atlasSampler.sample(atlasSamplerSampler, fragmentMaskUv)"
  )

echo "Silky Shady shader codegen tests passed"
