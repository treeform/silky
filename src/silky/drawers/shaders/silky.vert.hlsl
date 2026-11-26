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
// from silkyVert

cbuffer ShadyUniforms0 : register(b0) {
  float2 viewportSize;
  float2 atlasSize;
};


struct VSOutput {
  float4 pos : SV_POSITION;
  float2 fragmentUv : TEXCOORD0;
  float4 fragmentColor : COLOR0;
  float2 fragmentClipPos : TEXCOORD1;
  float2 fragmentClipSize : TEXCOORD2;
  float2 fragmentPos : TEXCOORD3;
  float2 fragmentMaskUv : TEXCOORD4;
};

VSOutput VSMain(
  float2 pos : POSITION0,
  float2 uv : TEXCOORD0,
  float4 color : COLOR0,
  float2 clipPos : TEXCOORD1,
  float2 clipSize : TEXCOORD2,
  float2 maskUv : TEXCOORD3
) {
  VSOutput output;
  float4 gl_Position = float4(0.0, 0.0, 0.0, 0.0);
  float2 fragmentUv = float2(0.0, 0.0);
  float4 fragmentColor = float4(0.0, 0.0, 0.0, 0.0);
  float2 fragmentClipPos = float2(0.0, 0.0);
  float2 fragmentClipSize = float2(0.0, 0.0);
  float2 fragmentPos = float2(0.0, 0.0);
  float2 fragmentMaskUv = float2(0.0, 0.0);
  float2 ndc = float2((pos.x / viewportSize.x) * 2.0 - 1.0, 1.0 - (pos.y / viewportSize.y) * 2.0);
  gl_Position = float4(ndc.x, ndc.y, 0.0, 1.0);
  fragmentUv = uv / atlasSize;
  fragmentColor = float4(color);
  fragmentClipPos = clipPos;
  fragmentClipSize = clipSize;
  fragmentPos = pos;
  fragmentMaskUv = maskUv / atlasSize;
  output.pos = gl_Position;
  output.fragmentUv = fragmentUv;
  output.fragmentColor = fragmentColor;
  output.fragmentClipPos = fragmentClipPos;
  output.fragmentClipSize = fragmentClipSize;
  output.fragmentPos = fragmentPos;
  output.fragmentMaskUv = fragmentMaskUv;
  return output;
}
