import
  std/unicode,
  vmath,
  silky

when not defined(silkyTesting):
  {.error: "Compile with -d:silkyTesting".}

type Fixture = object
  harness: TestHarness
  id: string
  text: string
  singleLine: bool
  enabled: bool
  password: bool
  allowedChars: seq[Rune]

var
  atlas: SilkyAtlas
  nextId: int

block:
  let builder = newAtlasBuilder(1024, 4)
  builder.addDir("tests/data/", "tests/data/")
  builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18.0)
  atlas = builder.atlas

proc fixture(
  text = "Hello",
  onPress: proc(button: Button) = nil,
  onRelease: proc(button: Button) = nil,
  onRune: proc(rune: Rune) = nil,
  onFocus: proc() = nil
): Fixture =
  ## Creates a real Silky test context with optional application callbacks.
  inc nextId
  result.id = "input" & $nextId
  result.text = text
  result.singleLine = true
  result.enabled = true
  result.harness.window = newWindow()
  let window = result.harness.window
  window.onButtonPress = onPress
  window.onButtonRelease = onRelease
  window.onRune = onRune
  window.onFocusChange = onFocus
  result.harness.sk = newSilky(window, atlas)

proc frame(f: var Fixture, visible = true, duplicate = false) =
  ## Draws an actual text box and finishes the input frame.
  f.harness.beginFrame()
  if visible:
    let
      sk = f.harness.sk
      window = f.harness.window
    for i in 0 .. ord(duplicate):
      sk.at = vec2(20, 20)
      sk.textBox(
        window,
        f.id,
        f.text,
        240,
        120,
        wrapWords = true,
        singleLine = f.singleLine,
        enabled = f.enabled,
        password = f.password,
        allowedChars = f.allowedChars
      )
  f.harness.endFrame()
  f.harness.window.resetInputState()

proc state(f: Fixture): TextBoxState =
  ## Returns the text state belonging to a fixture.
  textBoxStates[f.id]

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

echo "All ordered text input tests passed"
