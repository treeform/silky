import
  std/unicode,
  bumpy, vmath,
  silky, silky/internal/inputs

when not defined(silkyTesting):
  {.error: "Compile with -d:silkyTesting".}

type Fixture = object
  harness: TestHarness
  id: string
  text: string
  singleLine: bool
  submitOnEnter: bool
  enabled: bool
  password: bool
  allowedChars: seq[Rune]
  spans: seq[TextSpan]
  blocks: seq[TextBlock]
  height: float32
  clip: Rect

var
  atlas: SilkyAtlas
  nextId: int

block:
  let builder = newAtlasBuilder(1024, 4)
  builder.addDir("tests/data/", "tests/data/")
  builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18.0)
  builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Wide", 30.0)
  builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Small", 12.0)
  atlas = builder.atlas

proc fixture(
  text = "Hello",
  onPress: proc(button: Button) = nil,
  onRelease: proc(button: Button) = nil,
  onRune: proc(rune: Rune) = nil,
  onFocus: proc() = nil,
  onTextInput: proc(text: string) = nil,
  onTextEdit: TextInputEditCallback = nil
): Fixture =
  ## Creates a real Silky test context with optional application callbacks.
  inc nextId
  result.id = "input" & $nextId
  result.text = text
  result.singleLine = true
  result.enabled = true
  result.height = 120
  result.harness.window = newWindow()
  let window = result.harness.window
  window.onButtonPress = onPress
  window.onButtonRelease = onRelease
  window.onRune = onRune
  window.onFocusChange = onFocus
  window.onTextInput = onTextInput
  window.onTextEdit = onTextEdit
  result.harness.sk = newSilky(window, atlas)

proc frame(f: var Fixture, visible = true, duplicate = false) =
  ## Draws an actual text box and finishes the input frame.
  f.harness.beginFrame()
  if visible:
    let
      sk = f.harness.sk
      window = f.harness.window
    if f.clip.w > 0:
      sk.pushClipRect(f.clip)
    for i in 0 .. ord(duplicate):
      sk.at = vec2(20, 20)
      sk.textBox(
        window,
        f.id,
        f.text,
        240,
        f.height,
        wrapWords = true,
        singleLine = f.singleLine,
        enabled = f.enabled,
        password = f.password,
        allowedChars = f.allowedChars,
        submitOnEnter = f.submitOnEnter,
        spans = f.spans,
        blocks = f.blocks
      )
    if f.clip.w > 0:
      sk.popClipRect()
  f.harness.endFrame()
  f.harness.window.resetInputState()

proc state(f: Fixture): TextBoxState =
  ## Returns the text state belonging to a fixture.
  textBoxStates[f.id]

proc hoverGlyph(f: var Fixture, index: int) =
  ## Moves the pointer over a visible laid-out glyph in the current view.
  let
    bounds = f.state.layout[index]
    padding = f.harness.sk.theme.padding.float32
    point = vec2(20 + padding) + bounds.xy + bounds.wh / 2 -
      f.state.scrollPos
  f.harness.window.moveMouse(point.x.int, point.y.int)
  f.frame()

proc focus(f: var Fixture) =
  ## Clicks the field and positions the caret at the end of its text.
  f.frame()
  let window = f.harness.window
  f.state.lastClickTime = 0
  window.moveMouse(35, 35)
  window.pressButton(MouseLeft)
  window.releaseButton(MouseLeft)
  f.frame()
  f.state.cursor = f.state.runes.len
  f.state.selector = f.state.cursor

proc tap(window: Window, button: Button) =
  ## Delivers a complete key press and release without drawing.
  window.pressButton(button)
  window.releaseButton(button)

proc shortcut(window: Window, button: Button, modifier = KeyLeftSuper) =
  ## Delivers a shortcut entirely between UI frames.
  window.pressButton(modifier)
  window.tap(button)
  window.releaseButton(modifier)

proc typeText(window: Window, text: string) =
  ## Sends platform text callbacks without synthesizing key events.
  for rune in text.runes:
    window.typeRune(rune)

block:
  echo "Testing normal keys, callback chaining, and focus activation"
  var
    presses, releases, runes, focuses: int
    f = fixture(
      onPress = (proc(button: Button) = inc presses),
      onRelease = (proc(button: Button) = inc releases),
      onRune = (proc(rune: Rune) = inc runes),
      onFocus = (proc() = inc focuses)
    )
  let
    window = f.harness.window
    sk = f.harness.sk
  doAssert not window.runeInputEnabled
  window.shortcut(KeyA)
  window.typeText("ignored")
  doAssert presses == 2 and releases == 2 and runes == 0
  doAssert window.buttonPressed[KeyA] and window.buttonReleased[KeyA]
  doAssert not window.buttonDown[KeyA]
  doAssert sk.buttonPressed[KeyA] and sk.buttonReleased[KeyA]
  f.focus()
  doAssert window.runeInputEnabled
  f.frame()
  doAssert window.runeInputEnabled
  doAssert f.text == "Hello" and f.state.cursor == f.state.selector
  let before = presses
  window.shortcut(KeyA)
  window.typeText("R")
  doAssert presses == before and runes == 0
  doAssert not sk.buttonPressed[KeyA] and not sk.buttonReleased[KeyA]
  f.harness.beginFrame()
  f.harness.sk.at = vec2(20, 20)
  f.harness.sk.textBox(window, f.id, f.text, 240, 120, false, true)
  doAssert window.buttonPressed[KeyA] and window.buttonReleased[KeyA]
  doAssert not window.buttonDown[KeyLeftSuper]
  doAssert f.text == "R"
  f.harness.endFrame()
  window.resetInputState()
  window.typeText("discarded")
  window.changeFocus()
  doAssert focuses == 1 and not window.runeInputEnabled
  f.frame()
  doAssert not f.state.focused and f.text == "R"

block:
  echo "Testing keyboard consumption and callback holds during text entry"
  var
    held: set[Button]
    presses, releases: int
    f = fixture(
      onPress = (proc(button: Button) =
        held.incl(button)
        inc presses),
      onRelease = (proc(button: Button) =
        held.excl(button)
        inc releases)
    )
  let
    window = f.harness.window
    sk = f.harness.sk
  window.pressButton(KeyW)
  doAssert sk.buttonDown[KeyW] and KeyW in held
  f.focus()
  doAssert not sk.buttonDown[KeyW] and KeyW notin held
  doAssert window.buttonDown[KeyW]
  let
    previousPresses = presses
    previousReleases = releases
  window.releaseButton(KeyW)
  window.pressButton(KeyW)
  window.typeText("w")
  doAssert not sk.buttonDown[KeyW]
  doAssert not sk.buttonPressed[KeyW] and not sk.buttonReleased[KeyW]
  f.frame()
  doAssert f.text == "Hellow"
  doAssert presses == previousPresses and releases == previousReleases
  window.releaseButton(KeyW)
  window.pressButton(MouseRight)
  doAssert sk.buttonDown[MouseRight] and sk.buttonPressed[MouseRight]
  doAssert MouseRight in held
  window.releaseButton(MouseRight)
  doAssert sk.buttonReleased[MouseRight] and MouseRight notin held
  doAssert presses == previousPresses + 1
  doAssert releases == previousReleases + 1
  window.pressButton(KeyA)
  f.frame(visible = false)
  window.releaseButton(KeyA)
  doAssert releases == previousReleases + 1
  window.pressButton(KeyD)
  doAssert sk.buttonDown[KeyD] and sk.buttonPressed[KeyD]
  doAssert KeyD in held
  window.releaseButton(KeyD)
  doAssert sk.buttonReleased[KeyD] and KeyD notin held
  doAssert presses == previousPresses + 2
  doAssert releases == previousReleases + 2

block:
  echo "Testing inactive input never accumulates a text batch"
  var
    runes: int
    f = fixture(onRune = (proc(rune: Rune) = inc runes))
  let window = f.harness.window
  for i in 0 ..< 65_537:
    window.tap(KeyA)
    window.onRune(Rune('a'))
  doAssert runes == 65_537
  f.focus()
  doAssert f.text == "Hello"

block:
  echo "Testing quick shortcuts and same-frame replacement"
  for modifier in [
    KeyLeftSuper, KeyRightSuper, KeyLeftControl, KeyRightControl
  ]:
    var f = fixture()
    f.focus()
    let window = f.harness.window
    window.shortcut(KeyA, modifier)
    window.typeText("R")
    f.frame()
    doAssert f.text == "R"
    doAssert f.state.cursor == 1 and f.state.selector == 1
    f.frame()
    doAssert f.text == "R"

block:
  echo "Testing shortcut selection followed by typing next frame"
  var f = fixture()
  f.focus()
  let window = f.harness.window
  window.shortcut(KeyA)
  f.frame()
  doAssert f.state.selection == (0 .. 5)
  window.typeText("Next")
  f.frame()
  doAssert f.text == "Next"

block:
  echo "Testing text before shortcuts and nonoverlapping modifiers"
  var f = fixture()
  f.focus()
  let window = f.harness.window
  window.typeText("X")
  window.shortcut(KeyA)
  f.frame()
  doAssert f.text == "HelloX" and f.state.selection == (0 .. 6)
  window.typeText("R")
  window.tap(KeyLeftSuper)
  window.tap(KeyA)
  window.typeText("a")
  f.frame()
  doAssert f.text == "Ra" and f.state.selection == (2 .. 2)
  window.pressButton(KeyLeftSuper)
  f.frame()
  window.tap(KeyA)
  window.releaseButton(KeyLeftSuper)
  window.typeText("S")
  f.frame()
  doAssert f.text == "S"

block:
  echo "Testing repeated presses, selection, undo, and multiple shortcuts"
  var f = fixture()
  f.focus()
  let window = f.harness.window
  window.pressButton(KeyBackspace)
  window.pressButton(KeyBackspace)
  window.releaseButton(KeyBackspace)
  window.shortcut(KeyA)
  window.typeText("World")
  window.shortcut(KeyA)
  window.typeText("Q")
  window.shortcut(KeyZ)
  window.shortcut(KeyY)
  f.frame()
  doAssert f.text == "Q"
  window.typeText("ab")
  window.pressButton(KeyLeftShift)
  window.tap(KeyLeft)
  window.tap(KeyLeft)
  window.releaseButton(KeyLeftShift)
  window.typeText("!")
  f.frame()
  doAssert f.text == "Q!"

block:
  echo "Testing AltGr characters do not trigger Control shortcuts"
  var f = fixture("Hello")
  f.focus()
  let window = f.harness.window
  window.pressButton(KeyLeftControl)
  window.pressButton(KeyRightAlt)
  window.tap(KeyA)
  window.typeText("ą")
  window.releaseButton(KeyRightAlt)
  window.releaseButton(KeyLeftControl)
  f.frame()
  doAssert f.text == "Helloą"

block:
  echo "Testing Unicode, password, filtering, and single-line input"
  var f = fixture("")
  f.password = true
  f.focus()
  let window = f.harness.window
  window.typeText("é世界")
  window.tap(KeyEnter)
  f.frame()
  doAssert f.text == "é世界"
  doAssert f.state.displayText == "***"
  f.allowedChars = "0123456789".toRunes
  f.frame()
  window.shortcut(KeyA)
  window.typeText("a12b3")
  f.frame()
  doAssert f.text == "123"

block:
  echo "Testing Enter submission and captured Shift modifiers"
  var f = fixture("First")
  f.singleLine = false
  f.submitOnEnter = true
  f.focus()
  let window = f.harness.window
  window.tap(KeyEnter)
  f.frame()
  doAssert f.state.submitted and f.text == "First"
  f.frame()
  doAssert not f.state.submitted
  window.pressButton(KeyLeftShift)
  window.tap(KeyEnter)
  window.releaseButton(KeyLeftShift)
  f.frame()
  doAssert not f.state.submitted and f.text == "First\n"
  setClipboardString("Second\nThird")
  window.shortcut(KeyV)
  window.tap(KeyEnter)
  f.frame()
  doAssert f.state.submitted and f.text == "First\nSecond\nThird"
  f.enabled = false
  window.tap(KeyEnter)
  f.frame()
  doAssert not f.state.submitted

block:
  echo "Testing clipboard restoration before the paste frame"
  for modifier in [KeyLeftSuper, KeyLeftControl]:
    var f = fixture("Original")
    f.singleLine = false
    f.submitOnEnter = true
    f.focus()
    let
      window = f.harness.window
      dictated = "First\tline\n\n第二段 👩‍💻"
    window.shortcut(KeyA, modifier)
    setClipboardString(dictated)
    window.shortcut(KeyV, modifier)
    setClipboardString("Restored clipboard")
    doAssert f.text == "Original"
    f.frame(duplicate = true)
    doAssert f.text == dictated and not f.state.submitted
    doAssert getClipboardString() == "Restored clipboard"
    f.frame()
    doAssert f.text == dictated
    window.shortcut(KeyZ, modifier)
    f.frame()
    doAssert f.text == "Original"
    window.shortcut(KeyY, modifier)
    f.frame()
    doAssert f.text == dictated

block:
  echo "Testing native text commits replace a Unicode selection atomically"
  var f = fixture("Aé🙂Z")
  f.singleLine = false
  f.submitOnEnter = true
  f.focus()
  let
    window = f.harness.window
    committed = "First\tline\nSecond 👩‍💻"
    expected = "A" & committed & "Z"
  f.state.cursor = 1
  f.state.selector = 3
  window.onTextInput(committed)
  doAssert f.text == "Aé🙂Z"
  f.frame(duplicate = true)
  doAssert f.text == expected and not f.state.submitted
  doAssert f.state.cursor == 1 + committed.runeLen
  doAssert f.state.selector == f.state.cursor
  window.shortcut(KeyZ)
  f.frame()
  doAssert f.text == "Aé🙂Z"
  window.shortcut(KeyY)
  f.frame()
  doAssert f.text == expected

block:
  echo "Testing disabled fields reject native commits and captured paste"
  var f = fixture("Read only")
  f.enabled = false
  f.focus()
  let window = f.harness.window
  window.shortcut(KeyA)
  window.onTextInput("Ignored\n👩‍💻")
  setClipboardString("Ignored paste")
  window.shortcut(KeyV)
  f.frame()
  doAssert f.text == "Read only" and not f.state.submitted
  doAssert f.state.selection == (0 .. 9)
  window.shortcut(KeyC)
  f.frame()
  doAssert getClipboardString() == "Read only"

block:
  echo "Testing native editor publication uses rune ranges and pixel bounds"
  var f = fixture("Aé🙂Z\nNext")
  f.singleLine = false
  f.focus()
  let
    window = f.harness.window
    padding = f.harness.sk.theme.padding.float32
    scale = 1.5'f
  f.state.cursor = 3
  f.state.selector = 1
  f.harness.sk.uiScale = scale
  f.frame()
  doAssert window.textInput.id == f.id
  doAssert window.textInput.text == f.text
  doAssert window.textInput.selectionStart == 1
  doAssert window.textInput.selectionEnd == 3
  doAssert window.textInput.visibleStart == 0
  doAssert window.textInput.visibleEnd == f.text.runeLen
  doAssert window.textInput.multiline and not window.textInput.password
  doAssert window.textInput.bounds == rect(
    (20 + padding) * scale,
    (20 + padding) * scale,
    (240 - padding * 2) * scale,
    (f.height - padding * 2) * scale
  )

block:
  echo "Testing native editor bounds follow nested deferred layout spans"
  for scale in [1.0'f, 1.5'f, 2.0'f]:
    var f = fixture("Nested 🙂")
    f.focus()
    let
      sk = f.harness.sk
      window = f.harness.window
      padding = sk.theme.padding.float32
    sk.uiScale = scale
    f.harness.beginFrame()
    let
      outer = sk.beginVertexSpan()
      inner = sk.beginVertexSpan()
    sk.at = vec2(20, 20)
    sk.textBox(window, f.id, f.text, 120, 60, wrapWords = true)
    sk.endVertexSpan(inner, vec2(8, 16))
    sk.endVertexSpan(outer, vec2(40, -24))
    let unrelated = sk.beginVertexSpan()
    sk.endVertexSpan(unrelated, vec2(200, 300))
    f.harness.endFrame()
    doAssert window.textInput.id == f.id
    let expected = rect(
      (vec2(68, 12) + vec2(padding)) * scale,
      (vec2(120, 60) - vec2(padding * 2)) * scale
    )
    doAssert window.textInput.bounds == expected,
      $scale & ": " & $window.textInput.bounds & " != " & $expected

block:
  echo "Testing native editor visibility follows the scrolled text"
  var f = fixture("")
  for i in 0 ..< 20:
    if i > 0:
      f.text.add("\n")
    f.text.add("Line " & $i)
  f.singleLine = false
  f.height = 54
  f.focus()
  let window = f.harness.window
  window.onTextEdit(TextInputEdit(kind: SelectText, start: high(int)))
  f.frame()
  doAssert window.textInput.visibleStart > 0
  doAssert window.textInput.visibleEnd > window.textInput.visibleStart
  doAssert window.textInput.visibleEnd <= f.text.runeLen
  doAssert window.textInput.selectionStart == f.text.runeLen

block:
  echo "Testing native editor publication clears for unavailable fields"
  for mode in 0 .. 3:
    var f = fixture("Private text 🙂")
    let window = f.harness.window
    doAssert window.textInput == TextInputState()
    f.focus()
    f.frame()
    doAssert window.textInput.text == f.text
    case mode
    of 0:
      f.frame(visible = false)
    of 1:
      f.enabled = false
      f.frame()
    of 2:
      f.password = true
      f.frame()
    else:
      window.changeFocus()
      doAssert window.textInput == TextInputState()
      f.frame()
    doAssert window.textInput == TextInputState()

block:
  echo "Testing native range replacement and deletion are single edits"
  var f = fixture("Aé🙂Z")
  f.singleLine = false
  f.submitOnEnter = true
  f.focus()
  let
    window = f.harness.window
    replacement = "First\tline\n第二段 👩‍💻"
    expected = "A" & replacement & "Z"
  window.onTextEdit(TextInputEdit(
    kind: ReplaceText,
    text: replacement,
    start: 1,
    length: 2
  ))
  doAssert f.text == "Aé🙂Z"
  f.frame(duplicate = true)
  doAssert f.text == expected and not f.state.submitted
  doAssert f.state.undoStack.len == 1
  window.shortcut(KeyZ)
  f.frame()
  doAssert f.text == "Aé🙂Z"
  window.shortcut(KeyY)
  f.frame()
  doAssert f.text == expected
  window.onTextEdit(TextInputEdit(
    kind: ReplaceText,
    start: 1,
    length: replacement.runeLen
  ))
  f.frame()
  doAssert f.text == "AZ" and not f.state.submitted
  window.shortcut(KeyZ)
  f.frame()
  doAssert f.text == expected

block:
  echo "Testing native edits clamp invalid and oversized rune ranges"
  var f = fixture("Aé🙂Z")
  f.focus()
  let window = f.harness.window
  window.onTextEdit(TextInputEdit(
    kind: ReplaceText,
    text: "!",
    start: high(int),
    length: high(int)
  ))
  f.frame()
  doAssert f.text == "Aé🙂Z!"
  window.onTextEdit(TextInputEdit(
    kind: ReplaceText,
    start: low(int),
    length: 2
  ))
  f.frame()
  doAssert f.text == "🙂Z!"
  window.onTextEdit(TextInputEdit(
    kind: SelectText,
    start: 1,
    length: low(int)
  ))
  f.frame()
  doAssert f.state.selection == (1 .. 1)
  window.onTextEdit(TextInputEdit(
    kind: ReplaceText,
    start: 1,
    length: high(int)
  ))
  f.frame()
  doAssert f.text == "🙂"
  window.shortcut(KeyZ)
  f.frame()
  doAssert f.text == "🙂Z!"

block:
  echo "Testing native selection preserves edit order and undo history"
  var f = fixture("Aé🙂Z")
  f.focus()
  let window = f.harness.window
  window.onTextInput("!")
  window.onTextEdit(TextInputEdit(kind: SelectText, start: 1, length: 2))
  f.frame()
  doAssert f.text == "Aé🙂Z!" and f.state.selection == (1 .. 3)
  doAssert f.state.undoStack.len == 1
  window.shortcut(KeyZ)
  f.frame()
  doAssert f.text == "Aé🙂Z"
  window.onTextEdit(TextInputEdit(kind: SelectText, start: 0, length: 1))
  f.frame()
  doAssert f.state.undoStack.len == 0 and f.state.redoStack.len == 1
  window.shortcut(KeyY)
  window.onTextEdit(TextInputEdit(kind: SelectText, start: 1, length: 2))
  window.onTextInput("R")
  f.frame()
  doAssert f.text == "ARZ!"

block:
  echo "Testing disabled fields retain selection and copy without editing"
  var f = fixture()
  f.focus()
  let window = f.harness.window
  window.typeText("!")
  f.frame()
  f.enabled = false
  f.frame()
  doAssert not window.runeInputEnabled
  window.shortcut(KeyA)
  window.shortcut(KeyC)
  window.shortcut(KeyX)
  window.shortcut(KeyV)
  window.shortcut(KeyZ)
  window.shortcut(KeyY)
  window.tap(KeyBackspace)
  window.typeText("ignored")
  f.frame()
  doAssert f.text == "Hello!" and getClipboardString() == "Hello!"
  doAssert f.state.selection == (0 .. 6)

block:
  echo "Testing read-only styled text retains selection and copy"
  var f = fixture("é code 世界")
  f.enabled = false
  f.singleLine = false
  f.spans = @[TextSpan(first: 2, last: 6, font: "Wide")]
  f.focus()
  let
    window = f.harness.window
    styledWidth = f.state.layout[2].w
  window.shortcut(KeyA)
  window.shortcut(KeyC)
  window.tap(KeyBackspace)
  window.typeText("ignored")
  f.frame()
  doAssert f.text == "é code 世界"
  doAssert getClipboardString() == f.text
  doAssert f.state.selection == (0 .. f.text.runeLen)
  doAssert f.state.layout[2].w == styledWidth
  f.enabled = true
  f.frame()
  doAssert f.state.layout[2].w < styledWidth
  window.typeText("Editable")
  f.frame()
  doAssert f.text == "Editable"

block:
  echo "Testing styled span clicks activate only without dragging"
  var f = fixture("Click here")
  f.enabled = false
  f.spans = @[TextSpan(first: 0, last: f.text.runeLen, font: "Wide")]
  f.frame()
  let
    window = f.harness.window
    bounds = f.state.layout[0]
    padding = f.harness.sk.theme.padding.float32
    x = (20 + padding + bounds.x + bounds.w / 2).int
    y = (20 + padding + bounds.y + bounds.h / 2).int
  window.moveMouse(x, y)
  window.pressButton(MouseLeft)
  f.frame()
  doAssert f.state.activatedSpan == -1
  window.releaseButton(MouseLeft)
  f.frame()
  doAssert f.state.activatedSpan == 0
  f.frame()
  doAssert f.state.activatedSpan == -1
  f.state.lastClickTime = 0
  window.pressButton(MouseLeft)
  f.frame()
  window.moveMouse(x + 20, y)
  f.frame()
  window.moveMouse(x, y)
  window.releaseButton(MouseLeft)
  f.frame()
  doAssert f.state.activatedSpan == -1

block:
  echo "Testing link hover cursor and non-link text boundaries"
  var f = fixture("Link bold text")
  f.enabled = false
  f.spans = @[
    TextSpan(first: 0, last: 4, linkId: 1),
    TextSpan(first: 5, last: 9, font: "Wide")
  ]
  f.frame()
  f.hoverGlyph(1)
  doAssert f.state.hoveredSpan == 0
  doAssert f.harness.window.cursor.kind == PointerCursor
  f.hoverGlyph(6)
  doAssert f.state.hoveredSpan == -1
  doAssert f.harness.window.cursor.kind == ArrowCursor
  f.hoverGlyph(1)
  f.harness.window.moveMouse(21, 21)
  f.frame()
  doAssert f.state.hoveredSpan == -1
  doAssert f.harness.window.cursor.kind == ArrowCursor
  f.hoverGlyph(1)
  f.harness.window.moveMouse(600, 400)
  f.frame()
  doAssert f.state.hoveredSpan == -1
  doAssert f.harness.window.cursor.kind == ArrowCursor
  f.hoverGlyph(1)
  f.frame(visible = false)
  doAssert f.harness.window.cursor.kind == ArrowCursor

block:
  echo "Testing wrapped links follow scrolling and ancestor clipping"
  var f = fixture(
    "A long linked sentence that wraps onto several lines in this text box."
  )
  f.enabled = false
  f.singleLine = false
  f.spans = @[
    TextSpan(first: 0, last: f.text.runeLen, font: "Wide", linkId: 1)
  ]
  f.frame()
  var secondLine = -1
  for i, bounds in f.state.layout:
    if bounds.y > 0 and bounds.w > 0:
      secondLine = i
      break
  doAssert secondLine >= 0
  f.hoverGlyph(secondLine)
  doAssert f.state.hoveredSpan == 0
  doAssert f.harness.window.cursor.kind == PointerCursor
  f.clip = rect(20, 20, 240, 20)
  f.frame()
  doAssert f.state.hoveredSpan == -1
  doAssert f.harness.window.cursor.kind == ArrowCursor
  f.clip = rect(0, 0, 0, 0)
  f.state.scrollPos.y = f.state.lineHeight
  f.hoverGlyph(secondLine)
  doAssert f.state.hoveredSpan == 0
  doAssert f.harness.window.cursor.kind == PointerCursor
  f.spans[0].linkId = 0
  f.frame()
  doAssert f.state.hoveredSpan == -1
  doAssert f.harness.window.cursor.kind == ArrowCursor
  f.spans[0].linkId = 1
  f.frame()
  doAssert f.state.hoveredSpan == 0
  f.spans.setLen(0)
  f.frame()
  doAssert f.state.hoveredSpan == -1
  doAssert f.harness.window.cursor.kind == ArrowCursor

block:
  echo "Testing focus loss, disappearing fields, and field switching"
  var f = fixture()
  f.focus()
  let window = f.harness.window
  window.typeText("discarded")
  window.moveMouse(600, 400)
  window.tap(MouseLeft)
  f.frame()
  doAssert f.text == "Hello" and not window.runeInputEnabled
  f.focus()
  window.typeText("discarded")
  f.frame(visible = false)
  doAssert not window.runeInputEnabled
  window.typeText("ignored")
  f.frame()
  doAssert not f.state.focused and f.text == "Hello"
  f.focus()
  window.typeText("discarded")
  f.id.add("other")
  f.text = "Other"
  f.frame()
  doAssert f.text == "Other" and not window.runeInputEnabled
  f.focus()
  window.typeText("!")
  f.frame()
  doAssert f.text == "Other!"

block:
  echo "Testing one block widget selects and copies across all sections"
  const Sample = "Title\nBody link\ncode()"
  var f = fixture(Sample)
  f.enabled = false
  f.singleLine = false
  f.height = 240
  f.blocks = @[
    TextBlock(
      first: 0, last: 5, font: "Wide",
      padding: vec2(4, 3), spacing: 12
    ),
    TextBlock(first: 6, last: 15, padding: vec2(4, 3), spacing: 12),
    TextBlock(
      first: 16, last: Sample.runeLen, font: "Small",
      padding: vec2(4, 3)
    )
  ]
  f.spans = @[TextSpan(first: 11, last: 15, linkId: 1)]
  f.frame()
  let
    window = f.harness.window
    origin = vec2(20 + f.harness.sk.theme.padding.float32)
    first = f.state.layout[0]
    last = f.state.layout[^1]
    start = origin + first.xy + vec2(0, first.h / 2)
    finish = origin + last.xy + vec2(last.w + 1, last.h / 2)
  window.moveMouse(start.x.int, start.y.int)
  window.pressButton(MouseLeft)
  f.frame()
  window.moveMouse(finish.x.int, finish.y.int)
  f.frame()
  window.releaseButton(MouseLeft)
  f.frame()
  doAssert f.state.selection == (0 .. Sample.runeLen)
  window.shortcut(KeyC)
  f.frame()
  doAssert getClipboardString() == Sample

  echo "Testing block links retain hover, activation, and drag selection"
  f.hoverGlyph(12)
  doAssert f.state.hoveredSpan == 0
  doAssert window.cursor.kind == PointerCursor
  f.state.lastClickTime = 0
  window.tap(MouseLeft)
  f.frame()
  doAssert f.state.activatedSpan == 0
  f.state.lastClickTime = 0
  window.pressButton(MouseLeft)
  f.frame()
  window.moveMouse(start.x.int, start.y.int)
  f.frame()
  window.releaseButton(MouseLeft)
  f.frame()
  doAssert f.state.activatedSpan == -1
  doAssert f.state.selection.a == 0
  doAssert f.state.selection.b >= 11

  echo "Testing streaming text preserves one existing block selection"
  f.state.cursor = 2
  f.state.selector = 13
  let copied = f.state.copyText()
  f.text.add("\necho 1")
  f.blocks[^1].last = f.text.runeLen
  f.frame()
  doAssert f.state.selection == (2 .. 13)
  doAssert f.state.copyText() == copied
  window.shortcut(KeyA)
  window.shortcut(KeyC)
  f.frame()
  doAssert getClipboardString() == f.text
  f.text = "Title\nBody"
  f.blocks.setLen(2)
  f.blocks[^1].last = f.text.runeLen
  f.spans.setLen(0)
  f.frame()
  doAssert f.state.selection == (0 .. f.text.runeLen)
  doAssert f.state.copyText() == f.text

  echo "Testing read-only selection clears on blur and focus epoch changes"
  window.moveMouse(600, 400)
  window.tap(MouseLeft)
  f.frame()
  doAssert not f.state.focused
  doAssert f.state.cursor == f.state.selector
  f.focus()
  window.shortcut(KeyA)
  f.frame()
  doAssert f.state.cursor != f.state.selector
  window.changeFocus()
  f.frame()
  doAssert not f.state.focused
  doAssert f.state.cursor == f.state.selector

block:
  echo "Testing one-batch editing matches separate frames and layout"
  var fixtures = [fixture(""), fixture("")]
  for f in fixtures.mitems:
    f.singleLine = false
    f.focus()
  for i, f in fixtures.mpairs:
    let window = f.harness.window
    for step in 0 .. 8:
      case step
      of 0:
        window.typeText("A long line that wraps across several rows.")
      of 1:
        window.tap(KeyEnter)
      of 2:
        window.typeText("Second line")
      of 3:
        window.tap(KeyHome)
      of 4:
        window.tap(KeyUp)
      of 5:
        window.typeText("!")
      of 6:
        window.tap(KeyDown)
      of 7:
        window.tap(KeyBackspace)
      else:
        window.typeText("é")
      if i == 1:
        f.frame()
    if i == 0:
      f.frame()
  doAssert fixtures[0].text == fixtures[1].text
  doAssert fixtures[0].state.cursor == fixtures[1].state.cursor
  doAssert fixtures[0].state.selection == fixtures[1].state.selection

block:
  echo "Testing no duplicate consumption and events arriving after a drain"
  var f = fixture("")
  f.focus()
  let
    window = f.harness.window
    sk = f.harness.sk
  window.typeText("one")
  f.frame(duplicate = true)
  doAssert f.text == "one"
  f.harness.beginFrame()
  sk.at = vec2(20, 20)
  sk.textBox(window, f.id, f.text, 240, 120, false, true)
  window.typeText("two")
  f.harness.endFrame()
  doAssert f.text == "one"
  f.frame()
  doAssert f.text == "onetwo"

block:
  echo "Testing input queues are isolated between contexts"
  var
    first = fixture()
    second = fixture("Other")
  first.focus()
  second.focus()
  first.harness.window.shortcut(KeyA)
  first.harness.window.typeText("First")
  second.harness.window.typeText("!")
  second.frame()
  first.frame()
  doAssert first.text == "First" and second.text == "Other!"

block:
  echo "Testing overflow reports an error and retains accepted events"
  var f = fixture()
  f.focus()
  let window = f.harness.window
  window.shortcut(KeyA)
  for i in 0 ..< 65_532:
    window.pressButton(KeyLeftShift)
  var failed = false
  try:
    window.typeText("overflow")
  except SilkyError:
    failed = true
  doAssert failed
  f.frame()
  doAssert f.text == "Hello" and f.state.selection == (0 .. 5)
  window.releaseButton(KeyLeftShift)
  window.typeText("R")
  f.frame()
  doAssert f.text == "R"

block:
  echo "Testing native commit callbacks forward only while inactive"
  var
    commits: seq[string]
    f = fixture(
      onTextInput = (proc(text: string) = commits.add(text))
    )
  let window = f.harness.window
  window.onTextInput("Inactive\n🙂")
  doAssert commits == @["Inactive\n🙂"]
  f.focus()
  doAssert f.text == "Hello"
  window.onTextInput(" active")
  f.frame()
  doAssert f.text == "Hello active"
  doAssert commits == @["Inactive\n🙂"]
  window.onTextInput(" discarded")
  window.changeFocus()
  f.frame()
  doAssert f.text == "Hello active"
  window.onTextInput("After blur")
  doAssert commits == @["Inactive\n🙂", "After blur"]
  f.focus()
  doAssert f.text == "Hello active"

block:
  echo "Testing replaced native commit callbacks are reinstalled once"
  var
    oldCommits, newCommits: seq[string]
    f = fixture(
      onTextInput = (proc(text: string) = oldCommits.add(text))
    )
  let window = f.harness.window
  f.focus()
  window.onTextInput(" pending")
  window.onTextInput = proc(text: string) = newCommits.add(text)
  f.frame()
  doAssert f.text == "Hello pending"
  for i in 0 ..< 5:
    window.shortcut(KeyA)
    window.onTextInput("Replacement")
    f.frame()
    doAssert f.text == "Replacement"
  doAssert oldCommits.len == 0 and newCommits.len == 0
  window.changeFocus()
  f.frame()
  window.onTextInput("Forward once")
  doAssert oldCommits.len == 0 and newCommits == @["Forward once"]
  f.focus()
  window.onTextInput = nil
  f.frame()
  window.onTextInput(" restored")
  f.frame()
  doAssert f.text == "Replacement restored"
  doAssert oldCommits.len == 0 and newCommits == @["Forward once"]

block:
  echo "Testing native edit callbacks forward and reinstall without repeats"
  var
    oldEdits, newEdits: seq[TextInputEdit]
    f = fixture(onTextEdit = (proc(edit: TextInputEdit) = oldEdits.add(edit)))
  let
    window = f.harness.window
    edit = TextInputEdit(kind: ReplaceText, text: "R", start: 0, length: 5)
  window.onTextEdit(edit)
  doAssert oldEdits == @[edit]
  f.focus()
  window.onTextEdit(edit)
  window.onTextEdit = proc(edit: TextInputEdit) = newEdits.add(edit)
  f.frame()
  doAssert f.text == "R" and oldEdits == @[edit] and newEdits.len == 0
  window.onTextEdit = nil
  f.frame()
  window.onTextEdit(TextInputEdit(kind: ReplaceText, text: "!", start: 1))
  f.frame()
  doAssert f.text == "R!"
  window.onTextEdit = proc(edit: TextInputEdit) = newEdits.add(edit)
  f.frame()
  f.enabled = false
  f.frame()
  window.onTextEdit(edit)
  f.frame()
  doAssert f.text == "R!" and newEdits.len == 0
  f.enabled = true
  f.frame()
  window.onTextEdit(edit)
  window.changeFocus()
  f.frame()
  doAssert f.text == "R!"
  window.onTextEdit(edit)
  doAssert oldEdits == @[edit] and newEdits == @[edit]

block:
  echo "Testing application callbacks assigned after construction"
  var
    calls: array[4, int]
    f = fixture()
  let window = f.harness.window
  window.onButtonPress = proc(button: Button) = inc calls[0]
  window.onButtonRelease = proc(button: Button) = inc calls[1]
  window.onRune = proc(rune: Rune) = inc calls[2]
  window.onFocusChange = proc() = inc calls[3]
  f.frame()
  window.tap(KeyW)
  window.onRune(Rune('w'))
  doAssert calls == [1, 1, 1, 0]
  f.focus()
  let before = calls
  window.shortcut(KeyA)
  window.typeText("R")
  f.frame()
  doAssert f.text == "R" and calls == before
  window.changeFocus()
  f.frame()
  doAssert calls[3] == 1 and not f.state.focused
  window.tap(KeyW)
  doAssert calls[0] == before[0] + 1
  doAssert calls[1] == before[1] + 1

block:
  echo "Testing changed callbacks preserve input and run once"
  for slot in 0 .. 3:
    var
      calls: int
      f = fixture()
    let window = f.harness.window
    f.focus()
    window.typeText("!")
    case slot
    of 0:
      window.onButtonPress = proc(button: Button) = inc calls
    of 1:
      window.onButtonRelease = proc(button: Button) = inc calls
    of 2:
      window.onRune = proc(rune: Rune) = inc calls
    else:
      window.onFocusChange = proc() = inc calls
    f.frame()
    doAssert f.text == "Hello!" and f.state.focused
    for i in 0 ..< 5:
      window.shortcut(KeyA)
      window.typeText("R")
      f.frame()
      doAssert f.text == "R" and calls == 0
    window.changeFocus()
    f.frame()
    window.tap(KeyW)
    window.onRune(Rune('w'))
    doAssert calls == 1 and not f.state.focused

block:
  echo "Testing cleared callbacks are set up again automatically"
  var f = fixture()
  let window = f.harness.window
  f.focus()
  window.typeText("!")
  window.onButtonPress = nil
  window.onButtonRelease = nil
  window.onRune = nil
  window.onFocusChange = nil
  f.frame()
  doAssert f.text == "Hello!" and f.state.focused
  window.shortcut(KeyA)
  window.typeText("R")
  f.frame()
  doAssert f.text == "R"
  window.changeFocus()
  f.frame()
  doAssert not f.state.focused and not window.runeInputEnabled

when defined(nimTypeNames):
  block:
    echo "Testing unchanged input frames allocate zero"
    let
      window = newWindow()
      inputs = newTextInputs(window)
    let before = getMemCounters()
    for i in 0 ..< 100:
      inputs.beginInputFrame(window)
      inputs.endInputFrame(window)
    let after = getMemCounters()
    doAssert after[0] == before[0], "Unchanged handlers must reuse closures."

echo "All ordered text input tests passed"
