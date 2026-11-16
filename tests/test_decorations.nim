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

proc glyphCount(sk: Silky, glyph: string): int =
  ## Counts native glyph quads without depending on block decorations.
  let
    entry = sk.atlas.fonts["Default"].entries[glyph][0]
    uv = vec2(entry.x.float32, entry.y.float32)
    vertices = sk.drawer.layers[NormalLayer]
  for i in countup(0, vertices.high, 6):
    if vertices[i].uv == uv:
      inc result

proc transition(
  sk: Silky,
  text: string,
  blocks: seq[TextBlock] = @[]
): RichTextBoxState =
  ## Redraws one rich widget as its source and formatting change.
  sk.drawer.layers[NormalLayer].setLen(0)
  sk.at = vec2(10.17'f, 20.29'f)
  sk.richTextBox(
    Window(), "transitions", text, 180, 160,
    wrapWords = true, blocks = blocks
  )
  result = richTextBoxStates["transitions"]

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
    let
      sk = fixture(builder, density)
      text = "WW WW WW"
    var spans = @[
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
    sk.richTextBox(
      window, "decorations", text, 64, 220,
      wrapWords = true, spans = spans
    )
    let
      state = richTextBoxStates["decorations"]
      strikeRules = sk.rules()
    doAssert strikeRules.len == 3
    for i, rule in strikeRules:
      let line = origin.y + state.editor.layout[i * 3].y
      doAssert rule.y > line
      doAssert rule.y + rule.h < line + state.editor.lineHeight
      doAssert rule.w <= 64
      doAssert close(rule.h * density, max(1.0'f, round(density)))
    state.editor.selectAll()
    doAssert state.editor.copyText() == text
    state.editor.selector = state.editor.cursor

    sk.drawer.layers[NormalLayer].setLen(0)
    sk.at = origin
    sk.mousePos = origin + state.editor.layout[0].xy +
      state.editor.layout[0].wh / 2
    sk.richTextBox(
      window, "decorations", text, 64, 220,
      wrapWords = true, spans = spans
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
    sk.richTextBox(
      window, "decorations", text, 64, 220,
      wrapWords = true, spans = spans
    )
    doAssert sk.rules().len == 0
    richTextBoxStates.del("decorations")

block:
  echo "Testing rich formatting removal retains native text rendering"
  privateAccess(RichTextBoxState)
  let builder = newAtlasBuilder(256, 2)
  builder.addFont(
    FontPath, "Default", 18, @["W"], pixelScale = 2
  )
  doAssert builder.addImage("textbox.disabled.9patch", newImage(16, 16))
  let
    sk = fixture(builder, 2)
    font = builder.atlas.fonts["Default"]
    state = sk.transition("WW", @[
      TextBlock(
        first: 0, last: 2, padding: vec2(12, 6), spacing: 8,
        quoteDepth: 1, quoteColor: TextColor
      ),
      TextBlock(
        first: 2, last: 2, padding: vec2(12, 6),
        ruleColor: TextColor, ruleThickness: 1
      )
    ])
  doAssert sk.glyphCount("W") == 2
  doAssert state.innerHeight > font.lineHeight
  doAssert state.editor.layout[0].x > 0
  doAssert state.editor.locationRect(2).h == 0

  doAssert sk.transition("WW") == state
  doAssert sk.glyphCount("W") == 2,
    "A rich widget with no spans or blocks must still draw its text."
  doAssert state.editor.layout[0].xy == vec2(0)
  doAssert close(state.innerHeight, font.lineHeight)
  doAssert close(state.editor.locationRect(2).h, font.lineHeight)

  doAssert sk.transition("") == state
  doAssert sk.glyphCount("W") == 0
  doAssert state.runs.len == 0
  doAssert state.editor.layout.len == 0
  doAssert state.editor.cursor == 0 and state.editor.selector == 0
  doAssert close(state.innerHeight, font.lineHeight)
  doAssert close(state.editor.locationRect(0).h, font.lineHeight)
  richTextBoxStates.del("transitions")

echo "All text decoration tests passed."
