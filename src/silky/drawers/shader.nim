import pixie, shady, vmath

var
  viewportSize*: Uniform[Vec2]
  atlasSize*: Uniform[Vec2]
  atlasSampler*: Uniform[Sampler2D]

proc silkyVert*(
  pos: Vec2,
  uv: Vec2,
  color: ColorRGBX,
  clipPos: Vec2,
  clipSize: Vec2,
  maskUv: Vec2,
  gl_Position: var Vec4,
  fragmentUv: var Vec2,
  fragmentColor: var Vec4,
  fragmentClipPos: var Vec2,
  fragmentClipSize: var Vec2,
  fragmentPos: var Vec2,
  fragmentMaskUv: var Vec2
) =
  let ndc = vec2(
    pos.x / viewportSize.x * 2.0'f32 - 1.0'f32,
    1.0'f32 - pos.y / viewportSize.y * 2.0'f32
  )
  gl_Position = vec4(ndc.x, ndc.y, 0.0, 1.0)
  fragmentUv = uv / atlasSize
  fragmentColor = vec4(color)
  fragmentClipPos = clipPos
  fragmentClipSize = clipSize
  fragmentPos = pos
  fragmentMaskUv = maskUv / atlasSize

proc silkyFrag*(
  fragmentUv: Vec2,
  fragmentColor: Vec4,
  fragmentClipPos: Vec2,
  fragmentClipSize: Vec2,
  fragmentPos: Vec2,
  fragmentMaskUv: Vec2,
  fragColor: var Vec4
) =
  # Sample before clipping so neighboring fragments provide valid derivatives.
  let base = texture(atlasSampler, fragmentUv)
  var shaded = base * fragmentColor
  if fragmentMaskUv.x >= 0.0:
    let maskR = texture(atlasSampler, fragmentMaskUv).r
    shaded = vec4(
      base.rgb * mix(vec3(1.0, 1.0, 1.0), fragmentColor.rgb, maskR),
      base.a * fragmentColor.a
    )
  if fragmentPos.x < fragmentClipPos.x or
    fragmentPos.y < fragmentClipPos.y or
    fragmentPos.x > fragmentClipPos.x + fragmentClipSize.x or
    fragmentPos.y > fragmentClipPos.y + fragmentClipSize.y:
    discardFragment()
  else:
    fragColor = shaded
