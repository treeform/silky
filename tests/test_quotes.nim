import
  std/[importutils, math, tables],
  bumpy, pixie, vmath, windy,
  silky, silky/internal/inputs

const
  FontPath = "tests/data/IBMPlexSans-Regular.ttf"
  QuoteColor = rgbx(90, 150, 220, 255)
  RuleColor = rgbx(170, 120, 80, 255)
  CaptionColor = rgbx(80, 190, 130, 255)

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

proc render(
  sk: Silky,
  source: string,
  blocks: seq[TextBlock],
  width = 180.0'f
): TextBoxState =
  ## Draws one read-only quote document through the native textbox.
  var text = source
  textBoxStates.del("quotes")
  sk.at = vec2(10.17'f, 20.29'f)
  sk.textBox(
    Window(), "quotes", text, width, 220,
    wrapWords = true, enabled = false, blocks = blocks
  )
  result = textBoxStates["quotes"]

proc bars(sk: Silky, color: ColorRGBX, width = 180.0'f): seq[Rect] =
  ## Finds solid rules and checks their physical alignment and clipping.
  let vertices = sk.drawer.layers[NormalLayer]
  for i in countup(0, vertices.high, 6):
    if vertices[i].color != color:
      continue
    doAssert vertices[i].uv == vertices[i + 2].uv
    doAssert vertices[i].clipPos == vec2(10.17'f, 20.29'f)
    doAssert vertices[i].clipSize == vec2(width, 220)
    for j in i ..< i + 6:
      let pixel = vertices[j].pos * sk.uiScale
      doAssert close(pixel.x, round(pixel.x))
      doAssert close(pixel.y, round(pixel.y))
    result.add(rect(
      vertices[i].pos,
      vertices[i + 2].pos - vertices[i].pos
    ))

proc patchBounds(sk: Silky, name: string): Rect =
  ## Finds the outer bounds of one native code surface by atlas region.
  let
    sprite = sk.atlas.entries[name]
    vertices = sk.drawer.layers[NormalLayer]
  var
    first = true
    right, bottom: float32
  for i in countup(0, vertices.high, 6):
    let uv = vertices[i].uv
    if uv.x < sprite.x.float32 or uv.x >= (sprite.x + sprite.width).float32 or
      uv.y < sprite.y.float32 or uv.y >= (sprite.y + sprite.height).float32:
        continue
    if first:
      result.x = vertices[i].pos.x
      result.y = vertices[i].pos.y
      first = false
    else:
      result.x = min(result.x, vertices[i].pos.x)
      result.y = min(result.y, vertices[i].pos.y)
    right = max(right, vertices[i + 2].pos.x)
    bottom = max(bottom, vertices[i + 2].pos.y)
  doAssert not first
  result.w = right - result.x
  result.h = bottom - result.y

proc caption(sk: Silky): Vec2 =
  ## Finds the first caption glyph emitted by the native font renderer.
  for vertex in sk.drawer.layers[NormalLayer]:
    if vertex.color == CaptionColor:
      return vertex.pos
  doAssert false, "Expected a native code caption glyph."

block:
  echo "Testing nested quote bars and continued container spacing"
  let builder = newAtlasBuilder(2048, 2)
  builder.addFont(FontPath, "Default", 18)
  builder.addFont(FontPath, "Heading", 26)
  builder.addFont(FontPath, "Small", 12)
  doAssert builder.addImage("textbox.disabled.9patch", newImage(16, 16))
  doAssert builder.addImage("code.9patch", newImage(16, 16))
  for density in [1.0'f, 1.25'f, 1.5'f, 2.0'f]:
    for continuing in 0 .. 2:
      let
        sk = fixture(builder, density)
        state = sk.render("Head\nBody", @[
          TextBlock(
            first: 0, last: 4, font: "Heading",
            padding: vec2(12, 6), spacing: 8,
            quoteDepth: 2, quoteContinue: continuing, quoteColor: QuoteColor
          ),
          TextBlock(
            first: 5, last: 9, padding: vec2(12, 6),
            quoteDepth: 2, quoteColor: QuoteColor
          )
        ])
        quads = sk.bars(QuoteColor)
        firstHeight = builder.atlas.fonts["Heading"].lineHeight + 12
      doAssert quads.len == 4
      doAssert state.layout[0].x == 44
      doAssert state.layout[5].x == 44
      for level in 0 .. 1:
        let extension = if level < continuing: 8.0'f else: 0.0'f
        doAssert close(
          quads[level].x * density,
          round((10.17'f + 12 + level.float32 * 16) * density)
        )
        doAssert close(quads[level].w * density, max(1.0'f, round(2 * density)))
        doAssert close(
          (quads[level].y + quads[level].h) * density,
          round((20.29'f + firstHeight + extension) * density)
        )
        doAssert close(
          quads[level + 2].y * density,
          round((20.29'f + firstHeight + 8) * density)
        )
      state.selectAll()
      doAssert state.copyText() == "Head\nBody"
      doAssert state.layout.len == 9

    echo "Testing quoted code surfaces, captions, and rules at ", density
    let
      plain = fixture(builder, density)
      quoted = fixture(builder, density)
    var code = TextBlock(
      first: 0, last: 2, padding: vec2(12, 6),
      patch: "code.9patch", patchBorder: 4,
      label: "nim", labelFont: "Small", labelColor: CaptionColor,
      labelSpacing: 4
    )
    let plainState = plain.render("WW", @[code])
    code.quoteDepth = 2
    code.quoteColor = QuoteColor
    let
      quoteState = quoted.render("WW", @[code])
      plainPatch = plain.patchBounds("code.9patch")
      quotePatch = quoted.patchBounds("code.9patch")
    doAssert close(quotePatch.x - plainPatch.x, 32)
    doAssert close(plainPatch.w - quotePatch.w, 32)
    doAssert close(quoteState.layout[0].x - plainState.layout[0].x, 32)
    doAssert close(quoted.caption().x - plain.caption().x, 32)
    doAssert quoteState.innerHeight == plainState.innerHeight
    let
      ruled = fixture(builder, density)
      ruleState = ruled.render("", @[
        TextBlock(
          first: 0, last: 0, padding: vec2(12, 6),
          ruleColor: RuleColor, ruleThickness: 1,
          quoteDepth: 2, quoteColor: QuoteColor
        )
      ])
      horizontal = ruled.bars(RuleColor)
    doAssert ruleState.innerHeight == 13
    doAssert ruleState.runes.len == 0
    doAssert horizontal.len == 1
    doAssert close(horizontal[0].x * density, round((10.17'f + 44) * density))

  echo "Testing quote wrapping, empty paragraphs, and bounded indentation"
  let
    quoted = fixture(builder, 2)
    wrapped = quoted.render("WW WW WW", @[
      TextBlock(
        first: 0, last: 8, padding: vec2(12, 6),
        quoteDepth: 1, quoteColor: QuoteColor
      )
    ], 80)
  doAssert wrapped.layout[3].y > wrapped.layout[0].y
  wrapped.selectAll()
  doAssert wrapped.copyText() == "WW WW WW"
  let
    empty = fixture(builder, 2)
    emptyState = empty.render("", @[
      TextBlock(
        first: 0, last: 0, padding: vec2(12, 6),
        quoteDepth: 1, quoteColor: QuoteColor
      )
    ])
  doAssert close(
    emptyState.innerHeight,
    builder.atlas.fonts["Default"].lineHeight + 12
  )
  doAssert emptyState.layout.len == 0
  doAssert empty.bars(QuoteColor).len == 1
  for width in [0.0'f, 10.0'f, 20.0'f, 80.0'f]:
    let
      narrow = fixture(builder, 2)
      narrowState = narrow.render("", @[
        TextBlock(
          first: 0, last: 0, padding: vec2(12, 6),
          quoteDepth: 1000, quoteColor: QuoteColor
        )
      ], width)
    doAssert narrowState.innerHeight > 0
    for quad in narrow.bars(QuoteColor, width):
      doAssert quad.w >= 0 and quad.h >= 0
      doAssert quad.x >= 10
      doAssert quad.x + quad.w <= 10.17'f + width + 0.5'f
  textBoxStates.del("quotes")

echo "All native quote tests passed."
