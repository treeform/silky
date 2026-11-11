import
  std/[importutils, math, tables, unicode],
  bumpy, pixie, vmath, windy,
  silky, silky/internal/inputs

const
  FontPath = "tests/data/IBMPlexSans-Regular.ttf"
  RuleColor = rgbx(90, 150, 220, 255)

proc close(a, b: float32): bool =
  ## Compares logical and physical coordinates with float tolerance.
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
  result.mousePos = vec2(-1)
  result.pushLayout(vec2(0), vec2(300, 300))
  result.pushClipRect(rect(0, 0, 300, 300))

proc rules(sk: Silky, clip: Rect): seq[Rect] =
  ## Finds rule quads and checks their pixel alignment and native clip.
  let vertices = sk.drawer.layers[NormalLayer]
  for i in countup(0, vertices.high, 6):
    if vertices[i].color != RuleColor:
      continue
    doAssert vertices[i].uv == vertices[i + 2].uv
    doAssert vertices[i].clipPos == clip.xy
    doAssert vertices[i].clipSize == clip.wh
    for j in i ..< i + 6:
      let pixel = vertices[j].pos * sk.uiScale
      doAssert close(pixel.x, round(pixel.x))
      doAssert close(pixel.y, round(pixel.y))
    result.add(rect(
      vertices[i].pos,
      vertices[i + 2].pos - vertices[i].pos
    ))

block:
  echo "Testing rule-only blocks have no text or implicit font line"
  privateAccess(TextBoxState)
  let
    builder = newAtlasBuilder(1024, 2)
    window = Window()
  builder.addFont(FontPath, "Default", 18)
  doAssert builder.addImage("textbox.disabled.9patch", newImage(16, 16))
  for density in [1.0'f, 1.25'f, 1.5'f, 2.0'f]:
    let
      sk = fixture(builder, density)
      origin = vec2(10.17'f, 20.29'f)
      rule = TextBlock(
        first: 0,
        last: 0,
        ruleColor: RuleColor,
        ruleThickness: 1,
        padding: vec2(12, 6)
      )
    var text = ""
    sk.at = origin
    sk.textBox(
      window, "rule", text, 80, 100,
      wrapWords = true, enabled = false, blocks = @[rule]
    )
    let
      state = textBoxStates["rule"]
      quads = sk.rules(rect(origin, vec2(80, 100)))
    doAssert state.runes.len == 0
    doAssert state.layout.len == 0
    doAssert state.runs.len == 0
    doAssert state.innerHeight == 13
    doAssert state.locationRect(0).h == 0
    state.selectAll()
    doAssert state.copyText() == ""
    doAssert state.cursor == 0 and state.selector == 0
    doAssert quads.len == 1
    doAssert close(quads[0].x * density, round((origin.x + 12) * density))
    doAssert close(quads[0].y * density, round((origin.y + 6) * density))
    doAssert close(
      (quads[0].x + quads[0].w) * density,
      round((origin.x + 80 - 12) * density)
    )
    doAssert close(quads[0].h * density, max(1.0'f, round(density)))

    sk.drawer.layers[NormalLayer].setLen(0)
    sk.at = origin
    sk.textBox(
      window, "rule", text, 20, 100,
      wrapWords = true, enabled = false, blocks = @[rule]
    )
    doAssert sk.rules(rect(origin, vec2(20, 100))).len == 0
    doAssert state.innerHeight == 13
    textBoxStates.del("rule")

  echo "Testing rules preserve shared selection and surrounding wrapping"
  const Source = "WW WW WW\nAfter"
  let
    after = Source.find('\n') + 1
    before = TextBlock(first: 0, last: after - 1, padding: vec2(12, 6))
    rule = TextBlock(
      first: after - 1,
      last: after - 1,
      ruleColor: RuleColor,
      ruleThickness: 1,
      padding: vec2(12, 6),
      spacing: 8
    )
    following = TextBlock(
      first: after, last: Source.runeLen, padding: vec2(12, 6)
    )
    plain = TextBoxState(wordWrap: true, blocks: @[before, following])
    ruled = TextBoxState(wordWrap: true, blocks: @[before, rule, following])
  plain.setText(Source)
  ruled.setText(Source)
  plain.computeLayout(builder.atlas.fonts, "Default", 64)
  ruled.computeLayout(builder.atlas.fonts, "Default", 64)
  doAssert ruled.layout.len == plain.layout.len
  doAssert ruled.runes == plain.runes
  doAssert ruled.runs.len == plain.runs.len
  doAssert ruled.layout[3].y > ruled.layout[0].y
  for i in 0 ..< after - 1:
    doAssert ruled.layout[i] == plain.layout[i]
  for i in after ..< Source.runeLen:
    doAssert ruled.layout[i].x == plain.layout[i].x
    doAssert ruled.layout[i].wh == plain.layout[i].wh
    doAssert close(ruled.layout[i].y - plain.layout[i].y, 21)
  doAssert close(ruled.innerHeight - plain.innerHeight, 21)
  ruled.selectAll()
  doAssert ruled.copyText() == Source
  doAssert ruled.locationRect(Source.runeLen).h ==
    plain.locationRect(Source.runeLen).h

echo "All native rule tests passed."
