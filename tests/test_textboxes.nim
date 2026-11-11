## Tests for TextBoxState procs in silky/textboxes.

import
  std/[tables, unicode],
  vmath, bumpy,
  silky/atlas, silky/textboxes

# Build a real atlas with font metrics.
let builder = newAtlasBuilder(1024, 4)
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Wide", 30.0)
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Small", 12.0)
builder.write("tests/dist/atlas.png")
let silkyAtlas = readAtlasFromPng("tests/dist/atlas.png")
let fontData = silkyAtlas.fonts["Default"]
let lh = fontData.lineHeight

proc newState(text: string, maxWidth = 500.0f): TextBoxState =
  ## Creates a TextBoxState with word wrap on and computed layout.
  result = TextBoxState(dirty: true, wordWrap: true, boxSize: vec2(maxWidth, 300))
  result.setText(text)
  result.computeLayout(fontData, maxWidth)

proc newStateNoWrap(text: string, maxWidth = 500.0f): TextBoxState =
  ## Creates a TextBoxState with word wrap off and computed layout.
  result = TextBoxState(dirty: true, wordWrap: false, boxSize: vec2(maxWidth, 300))
  result.setText(text)
  result.computeLayout(fontData, maxWidth)
proc newStateSingleLine(text: string, maxWidth = 500.0f): TextBoxState =
  ## Creates a single-line TextBoxState with computed layout.
  result = TextBoxState(dirty: true, wordWrap: false, singleLine: true,
    boxSize: vec2(maxWidth, 300))
  result.setText(text)
  result.computeLayout(fontData, maxWidth)

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
  s.enabled = false
  s.spans = @[
    TextSpan(first: 0, last: 1, font: "Wide"),
    TextSpan(first: 2, last: 3, font: "Small")
  ]
  s.computeLayout(silkyAtlas.fonts, "Default", 500)
  doAssert s.layout.len == 3
  doAssert abs(s.layout[0].w - wide.advance(Rune('W'))) < 0.01
  doAssert abs(s.layout[1].w - fontData.advance(Rune(' '))) < 0.01
  doAssert abs(s.layout[2].w - small.advance(Rune('a'))) < 0.01
  doAssert abs(s.layout[1].x - s.layout[0].w) < 0.01
  doAssert s.lineHeight >= wide.lineHeight
  for bounds in s.layout:
    doAssert bounds.h == s.lineHeight

block:
  echo "Testing formatting and links preserve native pair kerning"
  const Sample = "AVATAR To WAVY"
  let
    plain = newStateNoWrap(Sample)
    styled = newStateNoWrap(Sample)
  doAssert fontData.lookupKerning(Rune('A'), Rune('V')) != 0
  doAssert fontData.lookupKerning(Rune('T'), Rune('o')) != 0
  doAssert plain.layout[1].x < plain.layout[0].w
  styled.enabled = false
  for i in 0 ..< styled.runes.len:
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
  doAssert styled.layout.len == plain.layout.len
  for i in 0 ..< plain.layout.len:
    let
      expected = plain.layout[i]
      actual = styled.layout[i]
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
  s.enabled = false
  s.spans = @[TextSpan(first: 0, last: 6, font: "Wide")]
  s.computeLayout(silkyAtlas.fonts, "Default", width)
  doAssert s.layout[0].y == s.layout[1].y
  doAssert s.layout[2].y > s.layout[1].y
  doAssert s.layout[4].y > s.layout[3].y
  for bounds in s.layout:
    doAssert bounds.x + bounds.w <= width + 0.01

block:
  echo "Testing styled Unicode selection preserves the original text"
  let s = newState("é code 世界")
  s.enabled = false
  s.spans = @[TextSpan(first: 2, last: 6, font: "Small")]
  s.computeLayout(silkyAtlas.fonts, "Default", 500)
  doAssert s.layout.len == s.runes.len
  s.cursor = 2
  s.selector = 6
  doAssert s.copyText() == "code"
  doAssert getSelectionRects(s.layout, 2, 6).len == 1
  s.selectAll()
  doAssert s.copyText() == "é code 世界"

block:
  echo "Testing styled code preserves tabs when copying"
  let
    s = newState("a\tb")
    small = silkyAtlas.fonts["Small"]
  s.enabled = false
  s.spans = @[TextSpan(first: 0, last: 3, font: "Small")]
  s.computeLayout(silkyAtlas.fonts, "Default", 500)
  doAssert abs(s.layout[1].w - small.advance(Rune(' ')) * 4) < 0.01
  doAssert abs(s.layout[2].x - s.layout[1].x - s.layout[1].w) < 0.01
  s.selectAll()
  doAssert s.copyText() == "a\tb"

block:
  echo "Testing the styled layout overload preserves unstyled layout"
  let
    s = newState("A plain paragraph that wraps across lines.", 100)
    expected = s.layout
  s.computeLayout(silkyAtlas.fonts, "Default", 100)
  doAssert s.layout == expected

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
  s.enabled = false
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
  doAssert s.layout.len == Sample.runeLen
  doAssert s.layout[0].h > s.layout[bodyStart].h
  doAssert s.layout[bodyStart].h > s.layout[codeStart].h
  doAssert s.layout[codeStart - 2].y > s.layout[bodyStart].y
  doAssert s.layout[bodyStart].x == 12
  doAssert s.layout[codeStart].x == 12
  doAssert abs(s.innerHeight - s.layout[^1].y - s.layout[^1].h - 12) < 0.001
  for index in [0, bodyStart, codeStart]:
    doAssert s.locationRect(index).h == s.layout[index].h
  s.selector = 2
  s.cursor = codeStart + 5
  doAssert s.copyText() == "ading\n" & Body & "\nlet x"
  let selected = getSelectionRects(s.layout, s.selector, s.cursor)
  doAssert selected.len >= 4
  doAssert selected[0].h > selected[^1].h
  s.selectAll()
  doAssert s.copyText() == Sample

  echo "Testing dragging through block spacing has no selection dead zone"
  let
    first = s.layout[0]
    body = s.layout[bodyStart]
  s.mouseAction(first.xy + vec2(0, first.h / 2))
  s.mouseAction(
    vec2(body.x, body.y - 1), click = false, shift = true
  )
  doAssert s.selector == 0
  doAssert s.cursor == bodyStart
  doAssert s.copyText() == Heading & "\n"

  echo "Testing keyboard selection follows rows with different heights"
  s.cursor = 0
  s.selector = 0
  s.savedX = first.x
  s.down(shift = true)
  doAssert s.cursor == bodyStart
  doAssert s.selector == 0
  s.up(shift = true)
  doAssert s.cursor == 0
  s.cursor = codeStart
  s.selector = codeStart
  s.savedX = s.layout[codeStart].x
  s.up(shift = true)
  doAssert s.cursor >= bodyStart and s.cursor < codeStart
  doAssert s.selector == codeStart

block:
  echo "Testing getText / setText"
  let s = newState("")
  doAssert s.getText() == ""
  doAssert s.cursor == 0
  doAssert s.selector == 0
  let s2 = newState("\n")
  doAssert s2.getText() == "\n"
  doAssert s2.cursor == 1
  doAssert s2.selector == 1
  let s3 = newState("hello")
  doAssert s3.getText() == "hello"
  doAssert s3.cursor == 5
  doAssert s3.selector == 5
  s3.setText("ab")
  doAssert s3.getText() == "ab"
  doAssert s3.cursor == 2
  s3.setText("")
  doAssert s3.getText() == ""
  doAssert s3.cursor == 0

block:
  echo "Testing selection"
  let s = newState("")
  doAssert s.selection.a == 0
  doAssert s.selection.b == 0
  let s2 = newState("hello")
  s2.cursor = 1
  s2.selector = 4
  doAssert s2.selection.a == 1
  doAssert s2.selection.b == 4
  s2.cursor = 4
  s2.selector = 1
  doAssert s2.selection.a == 1
  doAssert s2.selection.b == 4

block:
  echo "Testing typeCharacter"
  let s = newState("")
  s.typeCharacter(Rune('a'))
  doAssert s.getText() == "a"
  doAssert s.cursor == 1
  let s2 = newState("\n")
  s2.cursor = 0
  s2.selector = 0
  s2.typeCharacter(Rune('x'))
  doAssert s2.getText() == "x\n"
  doAssert s2.cursor == 1
  let s3 = newState("bc")
  s3.cursor = 0
  s3.selector = 0
  s3.typeCharacter(Rune('a'))
  doAssert s3.getText() == "abc"
  doAssert s3.cursor == 1
  let s4 = newState("ab")
  s4.typeCharacter(Rune('c'))
  doAssert s4.getText() == "abc"
  doAssert s4.cursor == 3
  let s5 = newState("ac")
  s5.cursor = 1
  s5.selector = 1
  s5.typeCharacter(Rune('b'))
  doAssert s5.getText() == "abc"
  doAssert s5.cursor == 2

block:
  echo "Testing typeCharacters"
  let s = newState("")
  s.typeCharacters("")
  doAssert s.getText() == ""
  doAssert s.cursor == 0
  let s2 = newState("")
  s2.typeCharacters("hello")
  doAssert s2.getText() == "hello"
  doAssert s2.cursor == 5
  let s3 = newState("")
  s3.typeCharacters("a\r\nb")
  doAssert s3.getText() == "a\nb", "CR should be stripped"
  let s4 = newState("\n")
  s4.cursor = 0
  s4.selector = 0
  s4.typeCharacters("hi")
  doAssert s4.getText() == "hi\n"
  doAssert s4.cursor == 2

block:
  echo "Testing backspace"
  let s = newState("")
  s.backspace()
  doAssert s.getText() == ""
  doAssert s.cursor == 0
  let s2 = newState("\n")
  s2.cursor = 0
  s2.selector = 0
  s2.backspace()
  doAssert s2.getText() == "\n", "Backspace at 0 should not change text"
  doAssert s2.cursor == 0
  let s3 = newState("\n")
  s3.backspace()
  doAssert s3.getText() == ""
  doAssert s3.cursor == 0
  let s4 = newState("abc")
  s4.backspace()
  doAssert s4.getText() == "ab"
  doAssert s4.cursor == 2
  let s5 = newState("abc")
  s5.cursor = 1
  s5.selector = 1
  s5.backspace()
  doAssert s5.getText() == "bc"
  doAssert s5.cursor == 0
  # With selection: removes selection only.
  let s6 = newState("abcd")
  s6.cursor = 1
  s6.selector = 3
  s6.backspace()
  doAssert s6.getText() == "ad"
  doAssert s6.cursor == 1

block:
  echo "Testing delete"
  let s = newState("")
  s.delete()
  doAssert s.getText() == ""
  doAssert s.cursor == 0
  let s2 = newState("\n")
  s2.cursor = 0
  s2.selector = 0
  s2.delete()
  doAssert s2.getText() == ""
  doAssert s2.cursor == 0
  let s3 = newState("\n")
  s3.delete()
  doAssert s3.getText() == "\n", "Delete at end should not change text"
  doAssert s3.cursor == 1
  let s4 = newState("abc")
  s4.cursor = 3
  s4.selector = 3
  s4.delete()
  doAssert s4.getText() == "abc", "Delete at end should not change text"
  let s5 = newState("abc")
  s5.cursor = 0
  s5.selector = 0
  s5.delete()
  doAssert s5.getText() == "bc"
  doAssert s5.cursor == 0
  # With selection: removes selection only.
  let s6 = newState("abcd")
  s6.cursor = 1
  s6.selector = 3
  s6.delete()
  doAssert s6.getText() == "ad"
  doAssert s6.cursor == 1

block:
  echo "Testing backspaceWord"
  let s = newState("")
  s.backspaceWord()
  doAssert s.getText() == ""
  doAssert s.cursor == 0
  let s2 = newState("\n")
  s2.cursor = 0
  s2.selector = 0
  s2.backspaceWord()
  doAssert s2.getText() == "\n", "backspaceWord at 0 should not change text"
  # Cursor at end of word: delete word only, stop at space.
  let s3 = newState("hello world")
  s3.backspaceWord()
  doAssert s3.getText() == "hello "
  doAssert s3.cursor == 6
  # With selection: removes selection, no word delete.
  let s4 = newState("hello world")
  s4.cursor = 2
  s4.selector = 4
  s4.backspaceWord()
  doAssert s4.getText() == "heo world"
  doAssert s4.cursor == 2
  # Cursor after trailing space: eat space then word.
  let s5 = newState("super cat ")
  s5.backspaceWord()
  doAssert s5.getText() == "super ", "Should eat trailing space then 'cat'"
  doAssert s5.cursor == 6
  # Cursor after multiple spaces: eat all spaces then word.
  let s6 = newState("hello   world")
  s6.cursor = 8
  s6.selector = 8
  s6.backspaceWord()
  doAssert s6.getText() == "world", "Should eat spaces then 'hello'"
  doAssert s6.cursor == 0
  # Only spaces: eat all.
  let s7 = newState("   ")
  s7.backspaceWord()
  doAssert s7.getText() == ""
  doAssert s7.cursor == 0

block:
  echo "Testing deleteWord"
  let s = newState("")
  s.deleteWord()
  doAssert s.getText() == ""
  doAssert s.cursor == 0
  # Cursor at start of word: delete word then trailing spaces.
  let s2 = newState("hello world")
  s2.cursor = 0
  s2.selector = 0
  s2.deleteWord()
  doAssert s2.getText() == "world", "Should eat 'hello' then the space"
  doAssert s2.cursor == 0
  let s3 = newState("hello world")
  s3.deleteWord()
  doAssert s3.getText() == "hello world", "deleteWord at end should not change text"
  # Cursor on space: only eats spaces (no word chars before them).
  let s4 = newState(" super cat")
  s4.cursor = 0
  s4.selector = 0
  s4.deleteWord()
  doAssert s4.getText() == "super cat", "Starting on space: eat only the space"
  doAssert s4.cursor == 0
  # Cursor at start of word: delete word then trailing spaces.
  let s5 = newState("hello world end")
  s5.cursor = 6
  s5.selector = 6
  s5.deleteWord()
  doAssert s5.getText() == "hello end", "Should eat 'world' then the space"
  doAssert s5.cursor == 6
  # Only spaces: eat all.
  let s6 = newState("   ")
  s6.cursor = 0
  s6.selector = 0
  s6.deleteWord()
  doAssert s6.getText() == ""
  doAssert s6.cursor == 0
  # Cursor between words on space: only eats the space.
  let s7 = newState("hello world")
  s7.cursor = 5
  s7.selector = 5
  s7.deleteWord()
  doAssert s7.getText() == "helloworld", "Starting on space: eat only the space"
  doAssert s7.cursor == 5
  # Multiple spaces between words: eat word then all trailing spaces.
  let s8 = newState("hello   world")
  s8.cursor = 0
  s8.selector = 0
  s8.deleteWord()
  doAssert s8.getText() == "world", "Should eat 'hello' then all 3 spaces"
  doAssert s8.cursor == 0

block:
  echo "Testing left / right"
  let s = newState("")
  s.left()
  doAssert s.cursor == 0, "Left on empty should stay at 0"
  s.right()
  doAssert s.cursor == 0, "Right on empty should stay at 0"
  let s2 = newState("\n")
  s2.cursor = 0
  s2.selector = 0
  s2.left()
  doAssert s2.cursor == 0, "Left at 0 on newline should stay"
  s2.right()
  doAssert s2.cursor == 1
  s2.right()
  doAssert s2.cursor == 1, "Right at end on newline should stay"
  let s3 = newState("abc")
  s3.cursor = 0
  s3.selector = 0
  s3.left()
  doAssert s3.cursor == 0
  s3.right()
  doAssert s3.cursor == 1
  doAssert s3.selector == 1
  s3.right()
  doAssert s3.cursor == 2
  s3.cursor = 3
  s3.selector = 3
  s3.right()
  doAssert s3.cursor == 3
  # Shift extends selection.
  let s4 = newState("abc")
  s4.cursor = 1
  s4.selector = 1
  s4.right(shift = true)
  doAssert s4.cursor == 2
  doAssert s4.selector == 1, "Shift+right should not move selector"
  s4.left(shift = true)
  doAssert s4.cursor == 1
  doAssert s4.selector == 1

block:
  echo "Testing leftWord / rightWord"
  let s = newState("")
  s.leftWord()
  doAssert s.cursor == 0
  s.rightWord()
  doAssert s.cursor == 0
  let s2 = newState("\n")
  s2.leftWord()
  doAssert s2.cursor == 0
  let s3 = newState("hello world")
  s3.cursor = 8
  s3.selector = 8
  s3.leftWord()
  doAssert s3.cursor == 6, "leftWord should jump to start of word"
  let s4 = newState("hello world")
  s4.cursor = 0
  s4.selector = 0
  s4.leftWord()
  doAssert s4.cursor == 0, "leftWord at 0 should stay"
  let s5 = newState("hello world")
  s5.cursor = 4
  s5.selector = 4
  s5.rightWord()
  doAssert s5.cursor == 5, "rightWord should jump past word end"
  let s6 = newState("hello world")
  s6.rightWord()
  doAssert s6.cursor == 11, "rightWord at end should stay"

block:
  echo "Testing startOfLine / endOfLine"
  let s = newState("")
  s.startOfLine()
  doAssert s.cursor == 0
  s.endOfLine()
  doAssert s.cursor == 0
  let s2 = newState("\n")
  s2.cursor = 1
  s2.selector = 1
  s2.startOfLine()
  doAssert s2.cursor == 0 or s2.cursor == 1, "startOfLine on second line of \\n"
  let s3 = newState("abc")
  s3.cursor = 1
  s3.selector = 1
  s3.startOfLine()
  doAssert s3.cursor == 0
  s3.endOfLine()
  doAssert s3.cursor == 3
  let s4 = newState("ab\ncd")
  s4.cursor = 4
  s4.selector = 4
  s4.startOfLine()
  doAssert s4.cursor == 3, "startOfLine on second line should go to after newline"
  s4.endOfLine()
  doAssert s4.cursor == 5

block:
  echo "Testing selectAll"
  let s = newState("")
  s.selectAll()
  doAssert s.cursor == 0
  doAssert s.selector == 0
  let s2 = newState("\n")
  s2.selectAll()
  doAssert s2.cursor == 0
  doAssert s2.selector == 1
  let s3 = newState("hello")
  s3.selectAll()
  doAssert s3.cursor == 0
  doAssert s3.selector == 5

block:
  echo "Testing copyText / cutText"
  let s = newState("")
  doAssert s.copyText() == ""
  doAssert s.cutText() == ""
  let s2 = newState("hello")
  doAssert s2.copyText() == "", "No selection means empty copy"
  s2.cursor = 1
  s2.selector = 4
  doAssert s2.copyText() == "ell"
  doAssert s2.getText() == "hello", "Copy should not change text"
  let s3 = newState("hello")
  s3.cursor = 1
  s3.selector = 4
  doAssert s3.cutText() == "ell"
  doAssert s3.getText() == "ho"
  doAssert s3.cursor == 1
  let s4 = newState("")
  doAssert s4.cutText() == ""
  doAssert s4.getText() == ""

block:
  echo "Testing pasteText"
  let s = newState("")
  s.pasteText("hello")
  doAssert s.getText() == "hello"
  doAssert s.cursor == 5
  let s2 = newState("abcd")
  s2.cursor = 1
  s2.selector = 3
  s2.pasteText("XY")
  doAssert s2.getText() == "aXYd", "Paste should replace selection"
  doAssert s2.cursor == 3
  let s3 = newState("abc")
  s3.pasteText("")
  doAssert s3.getText() == "abc", "Paste empty should not change text"

block:
  echo "Testing undo / redo"
  let s = newState("")
  s.undo()
  doAssert s.getText() == "", "Undo on empty stack should not crash"
  s.redo()
  doAssert s.getText() == "", "Redo on empty stack should not crash"
  let s2 = newState("")
  s2.typeCharacter(Rune('a'))
  doAssert s2.getText() == "a"
  s2.undo()
  doAssert s2.getText() == ""
  doAssert s2.cursor == 0
  s2.redo()
  doAssert s2.getText() == "a"
  doAssert s2.cursor == 1
  # Undo then type clears redo stack.
  s2.undo()
  s2.typeCharacter(Rune('b'))
  s2.redo()
  doAssert s2.getText() == "b", "Redo after new edit should do nothing"

block:
  echo "Testing undo: type multiple chars then undo all"
  let s = newState("")
  s.typeCharacter(Rune('a'))
  s.typeCharacter(Rune('b'))
  s.typeCharacter(Rune('c'))
  doAssert s.getText() == "abc"
  s.undo()
  doAssert s.getText() == "ab"
  s.undo()
  doAssert s.getText() == "a"
  s.undo()
  doAssert s.getText() == ""
  # Extra undo on empty stack does nothing.
  s.undo()
  doAssert s.getText() == ""
  # Redo all.
  s.redo()
  doAssert s.getText() == "a"
  s.redo()
  doAssert s.getText() == "ab"
  s.redo()
  doAssert s.getText() == "abc"

block:
  echo "Testing undo: select word, type replacement, then undo"
  let s = newState("hello world foo")
  # Select "world" (indices 6..10).
  s.cursor = 6
  s.selector = 11
  doAssert s.copyText() == "world"
  # Type 'x' to replace the selection.
  s.typeCharacter(Rune('x'))
  doAssert s.getText() == "hello x foo"
  # Undo should restore "world".
  s.undo()
  doAssert s.getText() == "hello world foo", "Undo should restore the deleted word"
  doAssert s.cursor == 6
  # Redo should re-apply the replacement.
  s.redo()
  doAssert s.getText() == "hello x foo"

block:
  echo "Testing undo: select and paste over selection"
  let s = newState("aaa bbb ccc")
  s.cursor = 4
  s.selector = 7
  doAssert s.copyText() == "bbb"
  s.pasteText("XXX")
  doAssert s.getText() == "aaa XXX ccc"
  s.undo()
  doAssert s.getText() == "aaa bbb ccc", "Undo paste over selection should restore"

block:
  echo "Testing undo: backspace with selection"
  let s = newState("abcdef")
  s.cursor = 1
  s.selector = 4
  s.backspace()
  doAssert s.getText() == "aef"
  s.undo()
  doAssert s.getText() == "abcdef", "Undo backspace-selection should restore"

block:
  echo "Testing undo: delete with selection"
  let s = newState("abcdef")
  s.cursor = 1
  s.selector = 4
  s.delete()
  doAssert s.getText() == "aef"
  s.undo()
  doAssert s.getText() == "abcdef", "Undo delete-selection should restore"

block:
  echo "Testing undo: backspace single char"
  let s = newState("abc")
  s.backspace()
  doAssert s.getText() == "ab"
  s.undo()
  doAssert s.getText() == "abc", "Undo backspace should restore char"

block:
  echo "Testing undo: delete single char"
  let s = newState("abc")
  s.cursor = 0
  s.selector = 0
  s.delete()
  doAssert s.getText() == "bc"
  s.undo()
  doAssert s.getText() == "abc", "Undo delete should restore char"

block:
  echo "Testing undo: cutText"
  let s = newState("hello world")
  s.cursor = 0
  s.selector = 5
  let cut = s.cutText()
  doAssert cut == "hello"
  doAssert s.getText() == " world"
  s.undo()
  doAssert s.getText() == "hello world", "Undo cut should restore"

block:
  echo "Testing undo: backspaceWord"
  let s = newState("hello world")
  s.backspaceWord()
  doAssert s.getText() == "hello "
  s.undo()
  doAssert s.getText() == "hello world", "Undo backspaceWord should restore"

block:
  echo "Testing undo: deleteWord"
  let s = newState("hello world")
  s.cursor = 0
  s.selector = 0
  s.deleteWord()
  doAssert s.getText() == "world"
  s.undo()
  doAssert s.getText() == "hello world", "Undo deleteWord should restore"

block:
  echo "Testing removedSelection"
  let s = newState("")
  doAssert s.removedSelection() == false
  let s2 = newState("hello")
  s2.cursor = 5
  s2.selector = 5
  doAssert s2.removedSelection() == false
  doAssert s2.getText() == "hello"
  let s3 = newState("hello")
  s3.cursor = 1
  s3.selector = 4
  doAssert s3.removedSelection() == true
  doAssert s3.getText() == "ho"
  doAssert s3.cursor == 1
  # Select all of "\n" and remove.
  let s4 = newState("\n")
  s4.cursor = 0
  s4.selector = 1
  doAssert s4.removedSelection() == true
  doAssert s4.getText() == ""

block:
  echo "Testing computeLayout"
  let s = newState("")
  doAssert s.layout.len == 0
  let s2 = newState("abc")
  doAssert s2.layout.len == 3
  doAssert s2.layout[0].y == 0
  doAssert s2.layout[1].y == 0
  doAssert s2.layout[2].y == 0
  doAssert s2.layout[0].w > 0
  doAssert s2.layout[1].w > 0
  doAssert s2.layout[1].x > s2.layout[0].x
  doAssert s2.layout[2].x > s2.layout[1].x
  # Single newline.
  let s3 = newState("\n")
  doAssert s3.layout.len == 1
  doAssert s3.layout[0].w == 0, "Newline should have zero width"
  doAssert s3.layout[0].y == 0
  # Multi-line.
  let s4 = newState("a\nb")
  doAssert s4.layout.len == 3
  doAssert s4.layout[0].y == 0, "'a' on first line"
  doAssert s4.layout[1].w == 0, "newline has zero width"
  doAssert s4.layout[2].y > 0, "'b' on second line"
  doAssert s4.layout[2].y == lh, "'b' y should be lineHeight"

block:
  echo "Testing pickGlyphAt"
  let s = newState("")
  doAssert s.pickGlyphAt(vec2(0, 0)) == -1, "Empty layout returns -1"
  # Single newline: click on line 0.
  let s2 = newState("\n")
  doAssert s2.pickGlyphAt(vec2(0, lh * 0.5)) == 0
  let s3 = newState("abc")
  doAssert s3.pickGlyphAt(vec2(0, lh * 0.5)) == 0
  # Click near second char.
  let x1 = s3.layout[1].x
  doAssert s3.pickGlyphAt(vec2(x1 + 1, lh * 0.5)) == 1
  # Click below all lines.
  doAssert s3.pickGlyphAt(vec2(0, lh * 5)) == -1
  # Multi-line: click on second line.
  let s4 = newState("a\nb")
  doAssert s4.pickGlyphAt(vec2(0, lh * 1.5)) == 2, "Click on second line"

block:
  echo "Testing getSelectionRects"
  doAssert getSelectionRects(@[], 0, 0).len == 0
  let s = newState("abc")
  doAssert getSelectionRects(s.layout, 0, 0).len == 0, "start == stop"
  doAssert getSelectionRects(s.layout, 0, 1).len == 1
  # Same line: merged into one rect.
  let rects = getSelectionRects(s.layout, 0, 3)
  doAssert rects.len == 1, "Same line chars should merge"
  # Multi-line: one rect per line.
  let s2 = newState("ab\ncd")
  let rects2 = getSelectionRects(s2.layout, 0, 4)
  doAssert rects2.len >= 2, "Multi-line selection should have multiple rects"

block:
  echo "Testing innerHeight / innerWidth"
  let s = newState("")
  doAssert s.innerHeight == lh, "Empty text should have lineHeight"
  doAssert s.innerWidth == 0
  let s2 = newState("\n")
  doAssert s2.innerHeight == lh, "Single newline char is on line 0"
  doAssert s2.innerWidth == 0, "Single newline has zero width"
  let s3 = newState("abc")
  doAssert s3.innerHeight == lh
  doAssert s3.innerWidth > 0
  let s4 = newState("a\nb")
  doAssert s4.innerHeight == lh * 2

block:
  echo "Testing locationRect"
  let s = newState("")
  let r = s.locationRect(0)
  doAssert r.w == CursorWidth
  doAssert r.h == lh
  # Single newline at loc 0.
  let s2 = newState("\n")
  let r2 = s2.locationRect(0)
  doAssert r2.x == 0
  doAssert r2.y == 0
  # Single newline at loc 1: should be on the next line.
  let r3 = s2.locationRect(1)
  doAssert r3.x == 0
  doAssert r3.y == lh, "Cursor after newline should be on next line"
  let s3 = newState("abc")
  let r4 = s3.locationRect(0)
  doAssert r4.x == s3.layout[0].x
  # At end: past last char.
  let r5 = s3.locationRect(3)
  doAssert r5.x > s3.layout[2].x, "Cursor at end should be past last char"

block:
  echo "Testing scrollToCursor / scrollBy"
  let s = newState("")
  s.scrollBy(100, 300)
  doAssert s.scrollPos.y == 0, "scrollBy on empty should clamp to 0"
  s.scrollBy(-50, 300)
  doAssert s.scrollPos.y == 0, "scrollBy negative should clamp to 0"
  # Create state with enough content to overflow.
  let s2 = newState("a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl\nm\nn\no\np")
  s2.boxSize = vec2(500, 50)
  s2.scrollBy(1000, 50)
  let maxScroll = max(0.0f, s2.innerHeight - 50)
  doAssert s2.scrollPos.y <= maxScroll + 0.01
  doAssert s2.scrollPos.y >= maxScroll - 0.01
  # scrollToCursor: cursor at end should scroll down.
  let s3 = newState("a\nb\nc\nd\ne\nf\ng\nh\ni\nj")
  s3.boxSize = vec2(500, 40)
  s3.scrollPos = vec2(0, 0)
  s3.scrollToCursor()
  doAssert s3.scrollPos.y > 0, "scrollToCursor should scroll down when cursor at end"

block:
  echo "Testing mouseAction"
  let s = newState("")
  s.mouseAction(vec2(0, 0))
  doAssert s.cursor == 0
  let s2 = newState("hello")
  s2.mouseAction(vec2(0, -10))
  doAssert s2.cursor == 0, "Click above text should go to 0"
  s2.mouseAction(vec2(0, lh * 10))
  doAssert s2.cursor == 5, "Click below text should go to end"

block:
  echo "Testing selectWord"
  let s = newState("")
  s.mouseAction(vec2(0, 0))
  s.selectWord(vec2(0, 0))
  doAssert s.cursor == 0
  doAssert s.selector == 0
  let s2 = newState("hello world")
  let x = s2.layout[1].x
  s2.selectWord(vec2(x, lh * 0.5))
  doAssert s2.cursor == 0, "Word start of 'hello'"
  doAssert s2.selector == 5, "Word end of 'hello'"

block:
  echo "Testing selectParagraph"
  let s = newState("")
  s.mouseAction(vec2(0, 0))
  s.selectParagraph(vec2(0, 0))
  doAssert s.cursor == 0
  doAssert s.selector == 0
  let s2 = newState("ab\ncd")
  let x = s2.layout[3].x
  s2.selectParagraph(vec2(x, lh * 1.5))
  doAssert s2.cursor == 3, "Paragraph start on second line"
  doAssert s2.selector == 5, "Paragraph end on second line"
  let s3 = newState("\n")
  s3.selectParagraph(vec2(0, lh * 0.5))
  doAssert s3.cursor == 0
  doAssert s3.selector <= 1

block:
  echo "Testing up / down"
  let s = newState("ab\ncd")
  s.cursor = 0
  s.selector = 0
  s.savedX = s.cursorPos.x
  s.down()
  doAssert s.cursor >= 2, "Down from first line should go to second"
  s.up()
  doAssert s.cursor <= 1, "Up from second line should go back to first"
  # Down on last line goes to end.
  let s2 = newState("abc")
  s2.cursor = 1
  s2.selector = 1
  s2.savedX = s2.cursorPos.x
  s2.down()
  doAssert s2.cursor == 3, "Down on single line should go to end"
  # Up on first line goes to start.
  let s3 = newState("abc")
  s3.cursor = 2
  s3.selector = 2
  s3.savedX = s3.cursorPos.x
  s3.up()
  doAssert s3.cursor == 0, "Up on single line should go to start"

block:
  echo "Testing computeLayout with word wrap vs no wrap"
  # Use a narrow width so "hello world" wraps.
  let narrow = 60.0f
  let sw = newState("hello world", narrow)
  # With wrap: "world" should be on a second line.
  doAssert sw.layout.len == 11
  let lastCharY = sw.layout[^1].y
  doAssert lastCharY > 0, "Word wrap should push 'world' to second line"
  # Without wrap: all on one line.
  let snw = newStateNoWrap("hello world", narrow)
  doAssert snw.layout.len == 11
  for r in snw.layout:
    doAssert r.y == 0, "No wrap should keep all chars on line 0"
  # Empty string: both modes produce empty layout.
  let swe = newState("", narrow)
  doAssert swe.layout.len == 0
  let snwe = newStateNoWrap("", narrow)
  doAssert snwe.layout.len == 0
  # Single newline: same in both modes.
  let swn = newState("\n", narrow)
  doAssert swn.layout.len == 1
  doAssert swn.layout[0].w == 0
  let snwn = newStateNoWrap("\n", narrow)
  doAssert snwn.layout.len == 1
  doAssert snwn.layout[0].w == 0

block:
  echo "Testing innerHeight / innerWidth with word wrap vs no wrap"
  let narrow = 60.0f
  let sw = newState("hello world", narrow)
  doAssert sw.innerHeight > lh, "Wrapped text should be taller than one line"
  let snw = newStateNoWrap("hello world", narrow)
  doAssert snw.innerHeight == lh, "Unwrapped text should be one line tall"
  doAssert snw.innerWidth > narrow, "Unwrapped text should overflow the width"
  doAssert sw.innerWidth <= narrow, "Wrapped text should fit within maxWidth"

block:
  echo "Testing pickGlyphAt with word wrap vs no wrap"
  let narrow = 60.0f
  let sw = newState("hello world", narrow)
  # In wrapped mode, clicking on second line should find chars from "world".
  let wrappedSecondLineIdx = sw.pickGlyphAt(vec2(5, lh * 1.5))
  doAssert wrappedSecondLineIdx >= 5, "Wrapped: click on line 2 should find char >= 5"
  # In no-wrap mode, all chars are on line 0, no second line.
  let snw = newStateNoWrap("hello world", narrow)
  let noWrapSecondLine = snw.pickGlyphAt(vec2(5, lh * 1.5))
  doAssert noWrapSecondLine == -1, "No wrap: no chars on second line"
  let noWrapFirstLine = snw.pickGlyphAt(vec2(5, lh * 0.5))
  doAssert noWrapFirstLine >= 0, "No wrap: chars on first line"

block:
  echo "Testing locationRect with word wrap vs no wrap"
  let narrow = 60.0f
  let sw = newState("hello world", narrow)
  # Cursor at the start of "world" (index 6) should be on the second line.
  let wIdx = 6
  let wr = sw.locationRect(wIdx)
  doAssert wr.y > 0, "Wrapped: 'w' of 'world' should be on second line"
  # No wrap: same index should be on line 0.
  let snw = newStateNoWrap("hello world", narrow)
  let nwr = snw.locationRect(wIdx)
  doAssert nwr.y == 0, "No wrap: 'w' of 'world' should stay on line 0"

block:
  echo "Testing up / down with word wrap"
  let narrow = 60.0f
  let sw = newState("hello world", narrow)
  # Cursor at start, go down should land on the wrapped second line.
  sw.cursor = 0
  sw.selector = 0
  sw.savedX = sw.cursorPos.x
  sw.down()
  doAssert sw.cursor >= 5, "Down from first wrapped line should land on second"
  # Go back up.
  sw.savedX = sw.cursorPos.x
  sw.up()
  doAssert sw.cursor <= 1, "Up from second wrapped line should go back to first"

block:
  echo "Testing up / down without word wrap"
  let narrow = 60.0f
  let snw = newStateNoWrap("hello world", narrow)
  # No wrap: single line, down goes to end.
  snw.cursor = 0
  snw.selector = 0
  snw.savedX = snw.cursorPos.x
  snw.down()
  doAssert snw.cursor == 11, "No wrap: down on single line goes to end"
  # Up goes to start.
  snw.savedX = snw.cursorPos.x
  snw.up()
  doAssert snw.cursor == 0, "No wrap: up on single line goes to start"

block:
  echo "Testing up / down with word wrap and newlines"
  let narrow = 60.0f
  let sw = newState("hello world\nfoo bar", narrow)
  # Cursor at start, go down.
  sw.cursor = 0
  sw.selector = 0
  sw.savedX = sw.cursorPos.x
  sw.down()
  let afterDown = sw.cursor
  doAssert afterDown > 0, "Down should move cursor"
  # Keep going down until we are past the newline.
  sw.savedX = sw.cursorPos.x
  sw.down()
  sw.savedX = sw.cursorPos.x
  sw.down()
  sw.savedX = sw.cursorPos.x
  sw.down()
  doAssert sw.cursor >= 12, "Multiple downs should reach second paragraph"

block:
  echo "Testing getSelectionRects with word wrap vs no wrap"
  let narrow = 60.0f
  let sw = newState("hello world", narrow)
  # Select all in wrapped mode: should have multiple rects (one per wrapped line).
  let wrects = getSelectionRects(sw.layout, 0, 11)
  doAssert wrects.len >= 2, "Wrapped: select-all should span multiple lines"
  # No wrap: select all should be one rect.
  let snw = newStateNoWrap("hello world", narrow)
  let nwrects = getSelectionRects(snw.layout, 0, 11)
  doAssert nwrects.len == 1, "No wrap: select-all on one line is one rect"

block:
  echo "Testing mouseAction with word wrap vs no wrap"
  let narrow = 60.0f
  let sw = newState("hello world", narrow)
  # Click on second wrapped line.
  sw.mouseAction(vec2(5, lh * 1.5))
  doAssert sw.cursor >= 5, "Wrapped: click on second line should place cursor there"
  # No wrap: same y is below the single line.
  let snw = newStateNoWrap("hello world", narrow)
  snw.mouseAction(vec2(5, lh * 1.5))
  doAssert snw.cursor == 11, "No wrap: click below single line goes to end"

block:
  echo "Testing selectWord with word wrap"
  let narrow = 60.0f
  let sw = newState("hello world", narrow)
  # Click on "world" which is on the wrapped second line.
  let wCharX = sw.layout[7].x
  sw.selectWord(vec2(wCharX, sw.layout[7].y + lh * 0.5))
  doAssert sw.cursor == 6, "Wrapped: word start of 'world'"
  doAssert sw.selector == 11, "Wrapped: word end of 'world'"

block:
  echo "Testing dirty flag"
  # computeLayout clears dirty.
  let s = newState("abc")
  doAssert s.dirty == false, "computeLayout should clear dirty"
  # setText sets dirty.
  s.setText("xyz")
  doAssert s.dirty == true, "setText should set dirty"
  s.computeLayout(fontData, 500)
  doAssert s.dirty == false, "computeLayout should clear dirty again"
  # typeCharacter sets dirty.
  s.typeCharacter(Rune('a'))
  doAssert s.dirty == true, "typeCharacter should set dirty"
  s.computeLayout(fontData, 500)
  doAssert s.dirty == false
  # typeCharacters sets dirty.
  s.typeCharacters("hi")
  doAssert s.dirty == true, "typeCharacters should set dirty"
  s.computeLayout(fontData, 500)
  doAssert s.dirty == false
  # backspace sets dirty when it deletes.
  let s2 = newState("ab")
  s2.backspace()
  doAssert s2.dirty == true, "backspace should set dirty when deleting"
  s2.computeLayout(fontData, 500)
  doAssert s2.dirty == false
  # backspace at 0 should not set dirty.
  let s3 = newState("ab")
  s3.cursor = 0
  s3.selector = 0
  s3.computeLayout(fontData, 500)
  s3.backspace()
  doAssert s3.dirty == false, "backspace at 0 should not set dirty"
  # delete sets dirty when it deletes.
  let s4 = newState("ab")
  s4.cursor = 0
  s4.selector = 0
  s4.delete()
  doAssert s4.dirty == true, "delete should set dirty when deleting"
  s4.computeLayout(fontData, 500)
  doAssert s4.dirty == false
  # delete at end should not set dirty.
  let s5 = newState("ab")
  s5.computeLayout(fontData, 500)
  s5.delete()
  doAssert s5.dirty == false, "delete at end should not set dirty"
  # backspaceWord sets dirty.
  let s6 = newState("hello world")
  s6.backspaceWord()
  doAssert s6.dirty == true, "backspaceWord should set dirty"
  s6.computeLayout(fontData, 500)
  doAssert s6.dirty == false
  # backspaceWord at 0 should not set dirty.
  let s7 = newState("hello")
  s7.cursor = 0
  s7.selector = 0
  s7.computeLayout(fontData, 500)
  s7.backspaceWord()
  doAssert s7.dirty == false, "backspaceWord at 0 should not set dirty"
  # deleteWord sets dirty.
  let s8 = newState("hello world")
  s8.cursor = 0
  s8.selector = 0
  s8.deleteWord()
  doAssert s8.dirty == true, "deleteWord should set dirty"
  s8.computeLayout(fontData, 500)
  doAssert s8.dirty == false
  # deleteWord at end should not set dirty.
  let s9 = newState("hello")
  s9.computeLayout(fontData, 500)
  s9.deleteWord()
  doAssert s9.dirty == false, "deleteWord at end should not set dirty"
  # removedSelection sets dirty when there is a selection.
  let s10 = newState("abcd")
  s10.cursor = 1
  s10.selector = 3
  doAssert s10.removedSelection() == true
  doAssert s10.dirty == true, "removedSelection should set dirty"
  s10.computeLayout(fontData, 500)
  doAssert s10.dirty == false
  # removedSelection with no selection should not set dirty.
  let s11 = newState("abcd")
  s11.computeLayout(fontData, 500)
  doAssert s11.removedSelection() == false
  doAssert s11.dirty == false, "removedSelection with no selection should not set dirty"
  # undo sets dirty.
  let s12 = newState("")
  s12.typeCharacter(Rune('a'))
  s12.computeLayout(fontData, 500)
  s12.undo()
  doAssert s12.dirty == true, "undo should set dirty"
  s12.computeLayout(fontData, 500)
  doAssert s12.dirty == false
  # undo on empty stack should not set dirty.
  let s13 = newState("abc")
  s13.computeLayout(fontData, 500)
  s13.undo()
  doAssert s13.dirty == false, "undo on empty stack should not set dirty"
  # redo sets dirty.
  let s14 = newState("")
  s14.typeCharacter(Rune('a'))
  s14.computeLayout(fontData, 500)
  s14.undo()
  s14.computeLayout(fontData, 500)
  s14.redo()
  doAssert s14.dirty == true, "redo should set dirty"
  s14.computeLayout(fontData, 500)
  doAssert s14.dirty == false
  # redo on empty stack should not set dirty.
  let s15 = newState("abc")
  s15.computeLayout(fontData, 500)
  s15.redo()
  doAssert s15.dirty == false, "redo on empty stack should not set dirty"
  # Navigation procs should NOT set dirty.
  let s16 = newState("abc")
  s16.computeLayout(fontData, 500)
  s16.cursor = 1
  s16.selector = 1
  s16.left()
  doAssert s16.dirty == false, "left should not set dirty"
  s16.right()
  doAssert s16.dirty == false, "right should not set dirty"
  s16.startOfLine()
  doAssert s16.dirty == false, "startOfLine should not set dirty"
  s16.endOfLine()
  doAssert s16.dirty == false, "endOfLine should not set dirty"
  let s17 = newState("hello world")
  s17.computeLayout(fontData, 500)
  s17.cursor = 3
  s17.selector = 3
  s17.leftWord()
  doAssert s17.dirty == false, "leftWord should not set dirty"
  s17.rightWord()
  doAssert s17.dirty == false, "rightWord should not set dirty"
  # selectAll should not set dirty.
  let s18 = newState("abc")
  s18.computeLayout(fontData, 500)
  s18.selectAll()
  doAssert s18.dirty == false, "selectAll should not set dirty"
  # copyText should not set dirty.
  let s19 = newState("abc")
  s19.cursor = 0
  s19.selector = 3
  s19.computeLayout(fontData, 500)
  discard s19.copyText()
  doAssert s19.dirty == false, "copyText should not set dirty"
  # cutText should set dirty (it removes selection).
  let s20 = newState("abc")
  s20.cursor = 0
  s20.selector = 3
  s20.computeLayout(fontData, 500)
  discard s20.cutText()
  doAssert s20.dirty == true, "cutText should set dirty"
  # pasteText should set dirty.
  let s21 = newState("")
  s21.computeLayout(fontData, 500)
  s21.pasteText("hi")
  doAssert s21.dirty == true, "pasteText should set dirty"
  # backspace with selection sets dirty.
  let s22 = newState("abcd")
  s22.cursor = 1
  s22.selector = 3
  s22.computeLayout(fontData, 500)
  s22.backspace()
  doAssert s22.dirty == true, "backspace with selection should set dirty"
  # delete with selection sets dirty.
  let s23 = newState("abcd")
  s23.cursor = 1
  s23.selector = 3
  s23.computeLayout(fontData, 500)
  s23.delete()
  doAssert s23.dirty == true, "delete with selection should set dirty"
  # up/down should not set dirty.
  let s24 = newState("ab\ncd")
  s24.cursor = 0
  s24.selector = 0
  s24.savedX = 0
  s24.computeLayout(fontData, 500)
  s24.down()
  doAssert s24.dirty == false, "down should not set dirty"
  s24.up()
  doAssert s24.dirty == false, "up should not set dirty"
  # Empty string operations should not set dirty spuriously.
  let s25 = newState("")
  s25.computeLayout(fontData, 500)
  s25.backspace()
  doAssert s25.dirty == false, "backspace on empty should not set dirty"
  s25.delete()
  doAssert s25.dirty == false, "delete on empty should not set dirty"
  s25.left()
  doAssert s25.dirty == false, "left on empty should not set dirty"
  s25.right()
  doAssert s25.dirty == false, "right on empty should not set dirty"
  s25.undo()
  doAssert s25.dirty == false, "undo on empty should not set dirty"
  s25.redo()
  doAssert s25.dirty == false, "redo on empty should not set dirty"
  s25.selectAll()
  doAssert s25.dirty == false, "selectAll on empty should not set dirty"
  doAssert s25.removedSelection() == false
  doAssert s25.dirty == false, "removedSelection on empty should not set dirty"

block:
  echo "Testing single-line mode: typeCharacter ignores LF"
  let s = newStateSingleLine("")
  s.typeCharacter(Rune('a'))
  doAssert s.getText() == "a"
  s.typeCharacter(Rune(10))
  doAssert s.getText() == "a", "LF should be ignored in single-line"
  doAssert s.cursor == 1
  s.typeCharacter(Rune(13))
  doAssert s.getText() == "a", "CR should be ignored in single-line"
  s.typeCharacter(Rune('b'))
  doAssert s.getText() == "ab"

block:
  echo "Testing single-line mode: typeCharacters converts newlines to spaces"
  let s = newStateSingleLine("")
  s.typeCharacters("hello\nworld")
  doAssert s.getText() == "hello world", "LF should become space"
  let s2 = newStateSingleLine("")
  s2.typeCharacters("a\r\nb")
  doAssert s2.getText() == "a b", "CRLF should become one space (CR skipped, LF to space)"
  let s3 = newStateSingleLine("")
  s3.typeCharacters("x\ry")
  doAssert s3.getText() == "xy", "CR alone should be skipped"
  let s4 = newStateSingleLine("")
  s4.typeCharacters("line1\nline2\nline3")
  doAssert s4.getText() == "line1 line2 line3"
  # Empty string paste.
  let s5 = newStateSingleLine("abc")
  s5.typeCharacters("")
  doAssert s5.getText() == "abc"

block:
  echo "Testing single-line mode: setText converts newlines to spaces"
  let s = newStateSingleLine("")
  s.setText("hello\nworld")
  doAssert s.getText() == "hello world"
  s.setText("a\r\nb")
  doAssert s.getText() == "a  b", "CR and LF each become space"
  s.setText("\n")
  doAssert s.getText() == " ", "Single LF becomes space"
  s.setText("")
  doAssert s.getText() == ""
  s.setText("no newlines")
  doAssert s.getText() == "no newlines"

block:
  echo "Testing single-line mode: paste multi-line text"
  let s = newStateSingleLine("start ")
  s.pasteText("line1\nline2\nline3")
  doAssert s.getText() == "start line1 line2 line3"

block:
  echo "Testing single-line mode: computeLayout stays on one line"
  let s = newStateSingleLine("abcdef")
  doAssert s.layout.len == 6
  for r in s.layout:
    doAssert r.y == 0, "All chars should be on line 0"
  # Even a space does not cause wrapping in single-line.
  let s2 = newStateSingleLine("hello world this is a test", 60)
  for r in s2.layout:
    doAssert r.y == 0, "Single-line should never wrap"

block:
  echo "Testing single-line mode: empty string operations"
  let s = newStateSingleLine("")
  s.typeCharacter(Rune(10))
  doAssert s.getText() == ""
  s.backspace()
  doAssert s.getText() == ""
  s.delete()
  doAssert s.getText() == ""
  s.left()
  doAssert s.cursor == 0
  s.right()
  doAssert s.cursor == 0
  s.selectAll()
  doAssert s.cursor == 0
  doAssert s.selector == 0

block:
  echo "Testing single-line mode: up/down are no-ops"
  let s = newStateSingleLine("hello world")
  s.cursor = 3
  s.selector = 3
  s.savedX = 0
  s.computeLayout(fontData, 500)
  s.down()
  doAssert s.cursor == 11, "Down on single line goes to end"
  s.up()
  doAssert s.cursor == 0, "Up on single line goes to start"

block:
  echo "Testing single-line mode: multi-line not affected"
  # Verify multi-line mode still allows newlines.
  let s = newState("abc")
  s.cursor = 3
  s.selector = 3
  s.typeCharacter(Rune(10))
  doAssert s.getText() == "abc\n", "Multi-line should allow LF"
  let s2 = newState("")
  s2.typeCharacters("a\nb")
  doAssert s2.getText() == "a\nb", "Multi-line should keep LF"
  let s3 = newState("")
  s3.setText("x\ny")
  doAssert s3.getText() == "x\ny", "Multi-line setText should keep LF"

block:
  echo "Testing disabled state: text cannot be modified"
  let s = newState("hello")
  s.enabled = false
  # Typing is blocked.
  s.typeCharacter(Rune('x'))
  doAssert s.getText() == "hello", "typeCharacter should be blocked when disabled"
  # Pasting is blocked.
  s.typeCharacters("world")
  doAssert s.getText() == "hello", "typeCharacters should be blocked when disabled"
  s.pasteText("world")
  doAssert s.getText() == "hello", "pasteText should be blocked when disabled"
  # Backspace is blocked.
  s.cursor = 3
  s.selector = 3
  s.backspace()
  doAssert s.getText() == "hello", "backspace should be blocked when disabled"
  doAssert s.cursor == 3
  # Delete is blocked.
  s.delete()
  doAssert s.getText() == "hello", "delete should be blocked when disabled"
  # BackspaceWord is blocked.
  s.backspaceWord()
  doAssert s.getText() == "hello", "backspaceWord should be blocked when disabled"
  # DeleteWord is blocked.
  s.deleteWord()
  doAssert s.getText() == "hello", "deleteWord should be blocked when disabled"
  # Cut returns text but does not remove it.
  s.cursor = 1
  s.selector = 4
  let cutResult = s.cutText()
  doAssert cutResult == "ell", "cutText should return selection text when disabled"
  doAssert s.getText() == "hello", "cutText should not remove text when disabled"
  # Copy still works.
  doAssert s.copyText() == "ell", "copyText should work when disabled"
  # Navigation still works.
  s.cursor = 2
  s.selector = 2
  s.left()
  doAssert s.cursor == 1, "left should work when disabled"
  s.right()
  doAssert s.cursor == 2, "right should work when disabled"
  s.selectAll()
  doAssert s.cursor == 0
  doAssert s.selector == 5
  # Disabled empty state.
  let s2 = newState("")
  s2.enabled = false
  s2.typeCharacter(Rune('a'))
  doAssert s2.getText() == "", "typeCharacter on disabled empty should do nothing"
  s2.backspace()
  doAssert s2.getText() == ""
  s2.delete()
  doAssert s2.getText() == ""
  doAssert s2.copyText() == ""
  # Re-enable should allow edits again.
  s2.enabled = true
  s2.typeCharacter(Rune('a'))
  doAssert s2.getText() == "a", "Re-enabled state should allow typing"

block:
  echo "Testing error state: purely visual, does not affect behavior"
  # Error state is visual only. All operations should work normally.
  let s = newState("hello")
  s.typeCharacter(Rune('!'))
  doAssert s.getText() == "hello!"
  s.backspace()
  doAssert s.getText() == "hello"
  s.cursor = 1
  s.selector = 3
  doAssert s.copyText() == "el"
  doAssert s.cutText() == "el"
  doAssert s.getText() == "hlo"
  s.pasteText("EL")
  doAssert s.getText() == "hELlo"
  s.selectAll()
  doAssert s.cursor == 0
  doAssert s.selector == 5
  # Error on empty.
  let s2 = newState("")
  s2.typeCharacter(Rune('x'))
  doAssert s2.getText() == "x"

block:
  echo "Testing word wrap disables horizontal scroll"
  # With word wrap on, scrollToCursor should never change X.
  let s = newState("hello world this is a long line", 60)
  s.boxSize = vec2(60, 40)
  s.scrollPos.x = 0
  s.cursor = s.runes.len
  s.selector = s.cursor
  s.scrollToCursor()
  doAssert s.scrollPos.x == 0, "Cursor at end with wrap should not scroll X"
  # Move cursor around, X stays 0.
  s.cursor = 0
  s.selector = 0
  s.scrollToCursor()
  doAssert s.scrollPos.x == 0, "Cursor at start with wrap should not scroll X"
  # Without word wrap, scrollPos.x can be non-zero.
  let snw = newStateNoWrap("hello world this is a long line", 60)
  snw.boxSize = vec2(60, 40)
  snw.cursor = snw.runes.len
  snw.selector = snw.cursor
  snw.scrollToCursor()
  doAssert snw.scrollPos.x > 0, "Cursor at end without wrap should scroll X"

block:
  echo "Testing word wrap: scrollBy does not affect X"
  let s = newState("hello world", 60)
  s.boxSize = vec2(60, 40)
  s.scrollPos.x = 0
  # scrollBy only changes Y, but let us verify X stays 0.
  s.scrollBy(100, 40)
  doAssert s.scrollPos.x == 0, "scrollBy should not affect X when word wrap on"

block:
  echo "Testing no-wrap: horizontal scroll works"
  let s = newStateNoWrap("abcdefghijklmnopqrstuvwxyz", 60)
  s.boxSize = vec2(60, 40)
  # Move cursor to end.
  s.cursor = s.runes.len
  s.selector = s.cursor
  s.scrollToCursor()
  doAssert s.scrollPos.x > 0, "Cursor at end without wrap should scroll right"
  # Move cursor to start.
  s.cursor = 0
  s.selector = 0
  s.scrollToCursor()
  doAssert s.scrollPos.x == 0, "Cursor at start should scroll back to 0"

block:
  echo "Testing word wrap: typing does not cause horizontal scroll"
  let s = newState("", 60)
  s.boxSize = vec2(60, 40)
  for c in "hello world this is a test":
    s.typeCharacter(Rune(c))
    s.computeLayout(fontData, 60)
  doAssert s.scrollPos.x == 0, "Typing with wrap should never cause X scroll"

block:
  echo "Testing no-wrap: typing long text causes horizontal scroll"
  let s = newStateNoWrap("", 60)
  s.boxSize = vec2(60, 40)
  for c in "hello world this is a test":
    s.typeCharacter(Rune(c))
    s.computeLayout(fontData, 60)
  doAssert s.scrollPos.x > 0, "Typing without wrap should cause X scroll"

block:
  echo "Testing word wrap: left/right navigation does not scroll X"
  let s = newState("hello world this is long text", 60)
  s.boxSize = vec2(60, 40)
  s.cursor = 0
  s.selector = 0
  for i in 0 ..< s.runes.len:
    s.right()
    s.computeLayout(fontData, 60)
    doAssert s.scrollPos.x == 0, "right() with wrap should never scroll X"

block:
  echo "Testing password mode: displayText masks characters"
  let s = newState("hello")
  doAssert s.displayText() == "hello", "Non-password should show real text"
  s.password = true
  doAssert s.displayText() == "*****", "Password should mask with *"
  s.passwordChar = Rune('#')
  doAssert s.displayText() == "#####", "Custom password char"
  # Empty string.
  let s2 = newState("")
  s2.password = true
  doAssert s2.displayText() == ""
  # Single char.
  let s3 = newState("x")
  s3.password = true
  doAssert s3.displayText() == "*"

block:
  echo "Testing password mode: layout uses password char width"
  let s = newState("abc")
  s.password = true
  s.computeLayout(fontData, 500)
  doAssert s.layout.len == 3
  # All chars should have the same width (the * char width).
  doAssert s.layout[0].w == s.layout[1].w
  doAssert s.layout[1].w == s.layout[2].w

block:
  echo "Testing password mode: getText returns real text"
  let s = newState("secret")
  s.password = true
  doAssert s.getText() == "secret", "getText should return real text"
  doAssert s.displayText() == "******", "displayText should mask"

block:
  echo "Testing password mode: editing works on real text"
  let s = newState("pass")
  s.password = true
  s.typeCharacter(Rune('!'))
  doAssert s.getText() == "pass!"
  doAssert s.displayText() == "*****"
  s.backspace()
  doAssert s.getText() == "pass"
  doAssert s.displayText() == "****"
  s.cursor = 0
  s.selector = 4
  doAssert s.copyText() == "pass", "Copy should return real text"

block:
  echo "Testing password mode: toggling recomputes layout"
  let s = newState("hello")
  s.computeLayout(fontData, 500)
  let normalWidth = s.layout[0].w
  s.password = true
  s.dirty = true
  s.computeLayout(fontData, 500)
  let maskedWidth = s.layout[0].w
  # The * char likely has a different width than 'h'.
  # Just verify layout was recomputed (len is still correct).
  doAssert s.layout.len == 5

block:
  echo "Testing password mode: selection and cut"
  let s = newState("secret")
  s.password = true
  s.cursor = 1
  s.selector = 4
  doAssert s.copyText() == "ecr", "Copy in password mode returns real text"
  let cut = s.cutText()
  doAssert cut == "ecr", "Cut in password mode returns real text"
  doAssert s.getText() == "set"
  doAssert s.displayText() == "***"

block:
  echo "Testing password mode: paste"
  let s = newState("ab")
  s.password = true
  s.cursor = 1
  s.selector = 1
  s.pasteText("XY")
  doAssert s.getText() == "aXYb"
  doAssert s.displayText() == "****"

block:
  echo "Testing password mode: undo restores real text"
  let s = newState("pass")
  s.password = true
  s.typeCharacter(Rune('!'))
  doAssert s.getText() == "pass!"
  s.undo()
  doAssert s.getText() == "pass"
  doAssert s.displayText() == "****"

block:
  echo "Testing password mode: delete and backspaceWord"
  let s = newState("hello world")
  s.password = true
  s.cursor = 0
  s.selector = 0
  s.delete()
  doAssert s.getText() == "ello world"
  doAssert s.displayText() == "**********"
  s.backspaceWord()
  doAssert s.getText() == "ello world", "backspaceWord at 0 should not change"
  s.cursor = s.runes.len
  s.selector = s.cursor
  s.backspaceWord()
  doAssert s.getText() == "ello "
  doAssert s.displayText() == "*****"

block:
  echo "Testing password mode: selectAll and clear"
  let s = newState("secret")
  s.password = true
  s.selectAll()
  doAssert s.cursor == 0
  doAssert s.selector == 6
  s.backspace()
  doAssert s.getText() == ""
  doAssert s.displayText() == ""

block:
  echo "Testing password mode: cursor navigation"
  let s = newState("abc")
  s.password = true
  s.computeLayout(fontData, 500)
  s.cursor = 0
  s.selector = 0
  s.right()
  doAssert s.cursor == 1
  s.right()
  doAssert s.cursor == 2
  s.left()
  doAssert s.cursor == 1
  s.startOfLine()
  doAssert s.cursor == 0
  s.endOfLine()
  doAssert s.cursor == 3

block:
  echo "Testing password mode: single-line password"
  let s = newStateSingleLine("mypass")
  s.password = true
  doAssert s.displayText() == "******"
  s.typeCharacter(Rune(10))
  doAssert s.getText() == "mypass", "Newline ignored in single-line password"
  doAssert s.displayText() == "******"

block:
  echo "Testing password mode: disabled password"
  let s = newState("secret")
  s.password = true
  s.enabled = false
  s.typeCharacter(Rune('x'))
  doAssert s.getText() == "secret", "Disabled password should block typing"
  doAssert s.displayText() == "******"
  s.cursor = 0
  s.selector = 6
  doAssert s.copyText() == "secret", "Copy from disabled password returns real text"

block:
  echo "Testing password mode: displayText length matches runes"
  let s = newState("")
  s.password = true
  for c in "testing":
    s.typeCharacter(Rune(c))
    doAssert s.displayText().len == s.getText().len,
      "displayText length should match getText length"

block:
  echo "Testing allowedChars: typeCharacter filters"
  let s = newState("")
  s.allowedChars = "0123456789".toRunes
  s.typeCharacter(Rune('5'))
  doAssert s.getText() == "5"
  s.typeCharacter(Rune('a'))
  doAssert s.getText() == "5", "Letter should be rejected"
  s.typeCharacter(Rune('3'))
  doAssert s.getText() == "53"
  s.typeCharacter(Rune(' '))
  doAssert s.getText() == "53", "Space should be rejected"

block:
  echo "Testing allowedChars: typeCharacters filters"
  let s = newState("")
  s.allowedChars = "0123456789".toRunes
  s.typeCharacters("abc123def456")
  doAssert s.getText() == "123456", "Only digits should pass"

block:
  echo "Testing allowedChars: paste filters"
  let s = newState("")
  s.allowedChars = "0123456789".toRunes
  s.pasteText("hello 42 world 99")
  doAssert s.getText() == "4299", "Only digits from paste"

block:
  echo "Testing allowedChars: setText filters"
  let s = newState("")
  s.allowedChars = "0123456789".toRunes
  s.setText("abc123")
  doAssert s.getText() == "123"
  s.setText("")
  doAssert s.getText() == ""
  s.setText("no digits here")
  doAssert s.getText() == ""

block:
  echo "Testing allowedChars: empty means all allowed"
  let s = newState("")
  s.allowedChars = @[]
  s.typeCharacter(Rune('a'))
  doAssert s.getText() == "a"
  s.typeCharacter(Rune('1'))
  doAssert s.getText() == "a1"
  s.typeCharacter(Rune(' '))
  doAssert s.getText() == "a1 "

block:
  echo "Testing allowedChars: backspace and delete still work"
  let s = newState("")
  s.allowedChars = "abc".toRunes
  s.typeCharacters("abc")
  doAssert s.getText() == "abc"
  s.backspace()
  doAssert s.getText() == "ab"
  s.cursor = 0
  s.selector = 0
  s.delete()
  doAssert s.getText() == "b"

block:
  echo "Testing allowedChars: undo works"
  let s = newState("")
  s.allowedChars = "0123456789".toRunes
  s.typeCharacter(Rune('5'))
  s.typeCharacter(Rune('3'))
  doAssert s.getText() == "53"
  s.undo()
  doAssert s.getText() == "5"
  s.undo()
  doAssert s.getText() == ""

block:
  echo "Testing allowedChars: combined with singleLine"
  let s = newStateSingleLine("")
  s.allowedChars = "0123456789".toRunes
  s.typeCharacter(Rune('1'))
  s.typeCharacter(Rune(10))
  doAssert s.getText() == "1", "Newline rejected by both singleLine and allowedChars"
  s.typeCharacters("a2b3c")
  doAssert s.getText() == "123"

block:
  echo "Testing allowedChars: combined with password"
  let s = newState("")
  s.password = true
  s.allowedChars = "0123456789".toRunes
  s.typeCharacters("pin1234")
  doAssert s.getText() == "1234"
  doAssert s.displayText() == "****"

echo "All tests passed."
