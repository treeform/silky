#version 450
// from silkyFrag

layout(set = 0, binding = 0) uniform sampler2D atlasSampler;

layout(location = 0) in vec2 fragmentUv;
layout(location = 1) in vec4 fragmentColor;
layout(location = 2) in vec2 fragmentClipPos;
layout(location = 3) in vec2 fragmentClipSize;
layout(location = 4) in vec2 fragmentPos;
layout(location = 5) in vec2 fragmentMaskUv;
layout(location = 0) out vec4 fragColor;

void main() {
  vec4 base = texture(atlasSampler, fragmentUv);
  vec4 shaded = base * fragmentColor;
  if (0.0 <= float(fragmentMaskUv.x)) {
    float maskR = (texture(atlasSampler, fragmentMaskUv)).r;
    shaded = vec4(base.rgb * mix(vec3(1.0, 1.0, 1.0), fragmentColor.rgb, maskR), base.a * fragmentColor.a);
  }
  if ((((fragmentPos.x < fragmentClipPos.x) || (fragmentPos.y < fragmentClipPos.y)) || (fragmentClipPos.x + fragmentClipSize.x < fragmentPos.x)) || (fragmentClipPos.y + fragmentClipSize.y < fragmentPos.y)) {
    discard;
  } else {
    fragColor = shaded;
  }
}
