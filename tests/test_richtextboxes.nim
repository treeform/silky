import
  std/[tables, unicode],
  vmath, bumpy,
  silky/atlas, silky/textboxes, silky/richtextboxes

var silkyAtlas: SilkyAtlas

block:
  let builder = newAtlasBuilder(1024, 4)
  builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18)
  builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Wide", 30)
  builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Small", 12)
  silkyAtlas = builder.atlas

proc newState(text: string, maxWidth = 500.0'f): RichTextBoxState =
  ## Creates a wrapped read-only document and computes its rich layout.
  result = newRichTextBoxState(text)
  result.editor.boxSize = vec2(maxWidth, 300)
  result.computeLayout(silkyAtlas.fonts, "Default", maxWidth)

proc newStateNoWrap(text: string): RichTextBoxState =
  ## Creates an unwrapped rich document for exact font comparisons.
  result = newRichTextBoxState(text, wordWrap = false)
  result.computeLayout(silkyAtlas.fonts, "Default", 500)

proc newPlainState(
  text: string,
  maxWidth = 500.0'f,
  wordWrap = false
): TextBoxState =
  ## Creates an independent single-font reference layout.
  result = TextBoxState(wordWrap: wordWrap)
  result.setText(text)
  result.computeLayout(silkyAtlas.fonts["Default"], maxWidth)

proc advance(font: FontAtlas, rune: Rune): float32 =
  ## Returns the actual atlas advance used by span layout assertions.
  var entry: ptr LetterEntry
  doAssert font.lookupLetter(rune, 0, entry)
  entry.advance

block:
  echo "Testing styled text uses each span's font metrics"
  let
    s = newState("W a")
    wide = silkyAtlas.fonts["Wide"]
    small = silkyAtlas.fonts["Small"]
    regular = silkyAtlas.fonts["Default"]
  s.spans = @[
    TextSpan(first: 0, last: 1, font: "Wide"),
    TextSpan(first: 2, last: 3, font: "Small")
  ]
  s.computeLayout(silkyAtlas.fonts, "Default", 500)
  doAssert s.editor.layout.len == 3
  doAssert abs(s.editor.layout[0].w - wide.advance(Rune('W'))) < 0.01
  doAssert abs(s.editor.layout[1].w - regular.advance(Rune(' '))) < 0.01
  doAssert abs(s.editor.layout[2].w - small.advance(Rune('a'))) < 0.01
  doAssert abs(s.editor.layout[1].x - s.editor.layout[0].w) < 0.01
  doAssert s.editor.lineHeight >= wide.lineHeight
  for bounds in s.editor.layout:
    doAssert bounds.h == s.editor.lineHeight

block:
  echo "Testing formatting and links preserve native pair kerning"
  const Sample = "AVATAR To WAVY"
  let
    plain = newPlainState(Sample)
    styled = newStateNoWrap(Sample)
  doAssert silkyAtlas.fonts["Default"].lookupKerning(Rune('A'), Rune('V')) != 0
  doAssert silkyAtlas.fonts["Default"].lookupKerning(Rune('T'), Rune('o')) != 0
  doAssert plain.layout[1].x < plain.layout[0].w
  for i in 0 ..< styled.editor.runes.len:
    styled.spans.add(TextSpan(
      first: i,
      last: i + 1,
      font:
        if i mod 2 == 0:
          "Default"
        else:
          "",
      linkId:
        if i in 1 .. 8:
          1
        else:
          0
    ))
  styled.computeLayout(silkyAtlas.fonts, "Default", 500)
  doAssert styled.editor.layout.len == plain.layout.len
  for i in 0 ..< plain.layout.len:
    let
      expected = plain.layout[i]
      actual = styled.editor.layout[i]
    doAssert abs(actual.x - expected.x) < 0.001
    doAssert abs(actual.y - expected.y) < 0.001
    doAssert abs(actual.w - expected.w) < 0.001
    doAssert abs(actual.h - expected.h) < 0.001

block:
  echo "Testing styled long words wrap before crossing the width"
  let
    s = newState("WWWWWW")
    wide = silkyAtlas.fonts["Wide"]
    width = wide.advance(Rune('W')) * 2.5'f
  s.spans = @[TextSpan(first: 0, last: 6, font: "Wide")]
  s.computeLayout(silkyAtlas.fonts, "Default", width)
  doAssert s.editor.layout[0].y == s.editor.layout[1].y
  doAssert s.editor.layout[2].y > s.editor.layout[1].y
  doAssert s.editor.layout[4].y > s.editor.layout[3].y
  for bounds in s.editor.layout:
    doAssert bounds.x + bounds.w <= width + 0.01

block:
  echo "Testing styled Unicode selection preserves the original text"
  let s = newState("é code 世界")
  s.spans = @[TextSpan(first: 2, last: 6, font: "Small")]
  s.computeLayout(silkyAtlas.fonts, "Default", 500)
  doAssert s.editor.layout.len == s.editor.runes.len
  s.editor.cursor = 2
  s.editor.selector = 6
  doAssert s.editor.copyText() == "code"
  doAssert getSelectionRects(s.editor.layout, 2, 6).len == 1
  s.editor.selectAll()
  doAssert s.editor.copyText() == "é code 世界"

block:
  echo "Testing styled code preserves tabs when copying"
  let
    s = newState("a\tb")
    small = silkyAtlas.fonts["Small"]
  s.spans = @[TextSpan(first: 0, last: 3, font: "Small")]
  s.computeLayout(silkyAtlas.fonts, "Default", 500)
  doAssert abs(s.editor.layout[1].w - small.advance(Rune(' ')) * 4) < 0.01
  doAssert abs(
    s.editor.layout[2].x - s.editor.layout[1].x - s.editor.layout[1].w
  ) < 0.01
  s.editor.selectAll()
  doAssert s.editor.copyText() == "a\tb"

block:
  echo "Testing rich text without styles preserves plain layout"
  const Source = "A plain paragraph that wraps across lines."
  let
    plain = newPlainState(Source, 100, wordWrap = true)
    rich = newState(Source, 100)
  doAssert rich.editor.layout == plain.layout

block:
  echo "Testing one selection spans headings, wrapped prose, and code"
  const
    Heading = "Heading"
    Body = "é body wraps over several lines for selection."
    Code = "let x = 1\n  echo x"
    Sample = Heading & "\n" & Body & "\n" & Code
  let
    bodyStart = Heading.runeLen + 1
    codeStart = bodyStart + Body.runeLen + 1
    s = newState(Sample, 180)
  s.blocks = @[
    TextBlock(
      first: 0, last: Heading.runeLen, font: "Wide",
      padding: vec2(12, 6), spacing: 8
    ),
    TextBlock(
      first: bodyStart, last: codeStart - 1,
      padding: vec2(12, 6), spacing: 8
    ),
    TextBlock(
      first: codeStart, last: Sample.runeLen, font: "Small",
      padding: vec2(12, 12), label: "nim", labelFont: "Small",
      labelSpacing: 8
    )
  ]
  s.computeLayout(silkyAtlas.fonts, "Default", 180)
  doAssert s.editor.layout.len == Sample.runeLen
  doAssert s.editor.layout[0].h > s.editor.layout[bodyStart].h
  doAssert s.editor.layout[bodyStart].h > s.editor.layout[codeStart].h
  doAssert s.editor.layout[codeStart - 2].y > s.editor.layout[bodyStart].y
  doAssert s.editor.layout[bodyStart].x == 12
  doAssert s.editor.layout[codeStart].x == 12
  doAssert abs(
    s.innerHeight - s.editor.layout[^1].y - s.editor.layout[^1].h - 12
  ) < 0.001
  for index in [0, bodyStart, codeStart]:
    doAssert s.editor.locationRect(index).h == s.editor.layout[index].h
  s.editor.selector = 2
  s.editor.cursor = codeStart + 5
  doAssert s.editor.copyText() == "ading\n" & Body & "\nlet x"
  let selected = getSelectionRects(
    s.editor.layout, s.editor.selector, s.editor.cursor
  )
  doAssert selected.len >= 4
  doAssert selected[0].h > selected[^1].h
  s.editor.selectAll()
  doAssert s.editor.copyText() == Sample

  echo "Testing dragging through block spacing has no selection dead zone"
  let
    first = s.editor.layout[0]
    body = s.editor.layout[bodyStart]
  s.editor.mouseAction(first.xy + vec2(0, first.h / 2))
  s.editor.mouseAction(
    vec2(body.x, body.y - 1), click = false, shift = true
  )
  doAssert s.editor.selector == 0
  doAssert s.editor.cursor == bodyStart
  doAssert s.editor.copyText() == Heading & "\n"

  echo "Testing keyboard selection follows rows with different heights"
  s.editor.cursor = 0
  s.editor.selector = 0
  s.editor.savedX = first.x
  s.editor.down(shift = true)
  doAssert s.editor.cursor == bodyStart
  doAssert s.editor.selector == 0
  s.editor.up(shift = true)
  doAssert s.editor.cursor == 0
  s.editor.cursor = codeStart
  s.editor.selector = codeStart
  s.editor.savedX = s.editor.layout[codeStart].x
  s.editor.up(shift = true)
  doAssert s.editor.cursor >= bodyStart and s.editor.cursor < codeStart
  doAssert s.editor.selector == codeStart

echo "All rich textbox layout tests passed."
