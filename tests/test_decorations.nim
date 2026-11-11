import
  std/[importutils, math, tables, unicode],
  bumpy, pixie, vmath, windy,
  silky, silky/internal/inputs

const
  FontPath = "tests/data/IBMPlexSans-Regular.ttf"
  TextColor = rgbx(90, 150, 220, 255)

proc close(a, b: float32): bool =
  ## Compares physical and logical coordinates with float tolerance.
  abs(a - b) < 0.001

proc fixture(builder: AtlasBuilder, density: float32): Silky =
  ## Queues native widget vertices without a platform window or GPU.
  privateAccess(Silky)
  result = Silky(
    atlas: builder.atlas,
    image: builder.atlasImage,
    uiScale: density,
    inFrame: true,
    inputs: TextInputs()
  )
  new(result.drawer)
  result.theme.padding = 0
  result.pushLayout(vec2(0), vec2(300, 300))
  result.pushClipRect(rect(0, 0, 300, 300))

proc rules(sk: Silky): seq[Rect] =
  ## Extracts solid decoration quads and checks their color and clipping.
  let vertices = sk.drawer.layers[NormalLayer]
  for i in countup(0, vertices.high, 6):
    if vertices[i].uv != vertices[i + 2].uv:
      continue
    doAssert vertices[i].color == TextColor
    doAssert vertices[i].clipPos == vec2(10.17'f, 20.29'f)
    doAssert vertices[i].clipSize == vec2(64, 220)
    for j in i ..< i + 6:
      let pixel = vertices[j].pos * sk.uiScale
      doAssert close(pixel.x, round(pixel.x))
      doAssert close(pixel.y, round(pixel.y))
    result.add(rect(
      vertices[i].pos,
      vertices[i + 2].pos - vertices[i].pos
    ))

block:
  echo "Testing native strikethrough wrapping, hover, and pixel alignment"
  let window = Window()
  for density in [1.0'f, 1.25'f, 1.5'f, 2.0'f]:
    let
      builder = newAtlasBuilder(256, 2)
      origin = vec2(10.17'f, 20.29'f)
    builder.addFont(
      FontPath,
      "Default",
      18,
      @[" ", "W"],
      pixelScale = density
    )
    doAssert builder.addImage("textbox.disabled.9patch", newImage(16, 16))
    let sk = fixture(builder, density)
    var
      text = "WW WW WW"
      spans = @[
        TextSpan(
          first: 0,
          last: text.runeLen,
          strikethrough: true,
          color: TextColor,
          linkId: 1
        )
      ]
    sk.at = origin
    sk.mousePos = vec2(-1)
    sk.textBox(
      window, "decorations", text, 64, 220,
      wrapWords = true, enabled = false, spans = spans
    )
    let
      state = textBoxStates["decorations"]
      strikeRules = sk.rules()
    doAssert strikeRules.len == 3
    for i, rule in strikeRules:
      let line = origin.y + state.layout[i * 3].y
      doAssert rule.y > line
      doAssert rule.y + rule.h < line + state.lineHeight
      doAssert rule.w <= 64
      doAssert close(rule.h * density, max(1.0'f, round(density)))
    state.selectAll()
    doAssert state.copyText() == text
    state.selector = state.cursor

    sk.drawer.layers[NormalLayer].setLen(0)
    sk.at = origin
    sk.mousePos = origin + state.layout[0].xy + state.layout[0].wh / 2
    sk.textBox(
      window, "decorations", text, 64, 220,
      wrapWords = true, enabled = false, spans = spans
    )
    let hoveredRules = sk.rules()
    doAssert hoveredRules.len == strikeRules.len * 2
    for i, rule in strikeRules:
      doAssert hoveredRules[i * 2] == rule
      doAssert hoveredRules[i * 2 + 1].y > rule.y

    sk.drawer.layers[NormalLayer].setLen(0)
    sk.at = origin
    sk.mousePos = vec2(-1)
    spans[0].strikethrough = false
    sk.textBox(
      window, "decorations", text, 64, 220,
      wrapWords = true, enabled = false, spans = spans
    )
    doAssert sk.rules().len == 0
    textBoxStates.del("decorations")

echo "All text decoration tests passed."
