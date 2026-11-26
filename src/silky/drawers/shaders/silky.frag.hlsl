// target hlsl dx12
int2 shadyTextureSize(Texture2D<float4> image, int level) {
  uint width, height, levels;
  image.GetDimensions(level, width, height, levels);
  return int2(width, height);
}
int2 shadyTextureSize(Texture2D<uint4> image, int level) {
  uint width, height, levels;
  image.GetDimensions(level, width, height, levels);
  return int2(width, height);
}
// from silkyFrag

Texture2D<float4> atlasSampler : register(t0);
SamplerState atlasSamplerSampler : register(s0);


struct PSInput {
  float4 pos : SV_POSITION;
  float2 fragmentUv : TEXCOORD0;
  float4 fragmentColor : COLOR0;
  float2 fragmentClipPos : TEXCOORD1;
  float2 fragmentClipSize : TEXCOORD2;
  float2 fragmentPos : TEXCOORD3;
  float2 fragmentMaskUv : TEXCOORD4;
};

float4 PSMain(PSInput input) : SV_TARGET {
  float2 fragmentUv = input.fragmentUv;
  float4 fragmentColor = input.fragmentColor;
  float2 fragmentClipPos = input.fragmentClipPos;
  float2 fragmentClipSize = input.fragmentClipSize;
  float2 fragmentPos = input.fragmentPos;
  float2 fragmentMaskUv = input.fragmentMaskUv;
  float4 fragColor = float4(0.0, 0.0, 0.0, 0.0);
  float4 base = atlasSampler.Sample(atlasSamplerSampler, fragmentUv);
  float4 shaded = base * fragmentColor;
  if (0.0 <= float(fragmentMaskUv.x)) {
    float maskR = (atlasSampler.Sample(atlasSamplerSampler, fragmentMaskUv)).r;
    shaded = float4(base.rgb * lerp(float3(1.0, 1.0, 1.0), fragmentColor.rgb, maskR), base.a * fragmentColor.a);
  }
  if ((((fragmentPos.x < fragmentClipPos.x) || (fragmentPos.y < fragmentClipPos.y)) || (fragmentClipPos.x + fragmentClipSize.x < fragmentPos.x)) || (fragmentClipPos.y + fragmentClipSize.y < fragmentPos.y)) {
    discard;
  } else {
    fragColor = shaded;
  }
  return fragColor;
}
