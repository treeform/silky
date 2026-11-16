import
  std/[os, strutils],
  pixie, vmath, bumpy,
  silky

when not defined(silkyTesting):
  {.error: "Compile with -d:silkyTesting".}

var
  atlas: SilkyAtlas
  mode, clicks: int
  popup: bool
  editorText = "Editable text"

block:
  let
    data = currentSourcePath().parentDir / "data"
    builder = newAtlasBuilder(1024, 4)
  builder.addDir(data, data & DirSep)
  builder.addFont(data / "IBMPlexSans-Regular.ttf", "Default", 18)
  doAssert builder.addImage("touch-icon", newImage(24, 24))
  atlas = builder.atlas

proc draw(sk: Silky, window: Window) =
  ## Exercises real nested text, icons, and scrollbars.
  ui:
    frame "touch parent":
      box 20, 30, 320, 180
      patch ""
      layout TopToBottom
      horizontalPadding 0
      verticalPadding 0
      itemSpacing 0
      group "document":
        size 300, (if mode in [1, 4]: 120 else: 500)
        sk.startCurrentChildren()
        if mode == 2:
          clickableIcon("touch-icon", false):
            inc clicks
        elif mode == 3:
          sk.textBox(window, "touch editable", editorText, 300, 120, wrapWords = true)
        else:
          let text =
            if mode == 1: "Line of text\n".repeat(80)
            else: ("Wide line ".repeat(30) & "\n").repeat(6)
          sk.richTextBox(window, "touch rich", text, 300,
            (if mode in [1, 4]: 120 else: 500), wrapWords = false)
      group "spacer":
        size 300, 500
  if popup:
    sk.pushLayer(PopupsLayer)
    discard sk.interact(rect(50, 60, 180, 120), true)
    sk.popLayer()

proc drawButtons(sk: Silky, window: Window) =
  ## Exercises release-triggered controls without any scrollable overflow.
  for i in 0 ..< 2:
    let interaction = sk.interact(rect((20 + i * 100).float32, 30, 80, 40), true)
    if interaction.isReleased(window):
      inc clicks

proc tick(h: var TestHarness) =
  ## Draws a frame and resets native transient input.
  discard h.pumpFrame(draw)

proc setup(): TestHarness =
  ## Starts from displayed geometry without requiring a hover frame.
  frameStates.clear()
  richTextBoxStates.clear()
  textBoxStates.clear()
  result = newTestHarness(atlas)
  result.window.pointerSource = TouchPointer
  result.tick()

proc press(h: var TestHarness, x, y: int) =
  ## Starts a finger gesture at a logical coordinate.
  h.window.moveMouse(x, y)
  h.window.pressButton(MouseLeft)
  h.tick()

proc release(h: var TestHarness, x, y: int) =
  ## Delivers final movement and release in the same frame.
  h.window.moveMouse(x, y)
  h.window.releaseButton(MouseLeft)
  h.tick()

proc near(actual, expected: float32) =
  ## Checks logical deltas without rounding away fractional positions.
  doAssert abs(actual - expected) < 0.01, $actual & " != " & $expected

block:
  echo "Testing nested horizontal pan leaves history unchanged"
  var h = setup()
  h.press(170, 110)
  h.window.moveMouse(110, 112)
  h.tick()
  near(frameStates["touch parent"].scrollPos.y, 0)
  near(richTextBoxStates["touch rich"].editor.scrollPos.x, 60)
  h.release(100, 112)
  near(richTextBoxStates["touch rich"].editor.scrollPos.x, 70)

block:
  echo "Testing deepest vertical viewport owns a pan"
  mode = 1
  var h = setup()
  h.press(120, 90)
  h.window.moveMouse(120, 55)
  h.tick()
  near(frameStates["touch parent"].scrollPos.y, 0)
  near(richTextBoxStates["touch rich"].editor.scrollPos.y, 35)
  h.release(120, 45)
  near(richTextBoxStates["touch rich"].editor.scrollPos.y, 45)

block:
  echo "Testing forgiving scrollbar grab and coalesced track taps"
  mode = 0
  var h = setup()
  let state = frameStates["touch parent"]
  h.press(318, 35)
  near(state.scrollPos.y, 0)
  h.window.moveMouse(318, 80)
  h.tick()
  doAssert state.scrollPos.y > 100
  h.release(318, 95)
  let position = state.scrollPos.y
  h.window.moveMouse(100, 150)
  h.tick()
  near(state.scrollPos.y, position)
  doAssert not state.scrollingY
  state.scrollPos.y = 0
  h.tick()
  h.window.moveMouse(318, 150)
  h.window.pressButton(MouseLeft)
  h.window.releaseButton(MouseLeft)
  h.tick()
  doAssert state.scrollPos.y > 300 and not state.scrollingY

block:
  echo "Testing cancellation preserves position and accepts a fresh gesture"
  var h = setup()
  let state = frameStates["touch parent"]
  h.press(100, 140)
  h.window.moveMouse(100, 100)
  h.tick()
  near(state.scrollPos.y, 40)
  h.release(-1, -1)
  near(state.scrollPos.y, 40)
  h.press(100, 140)
  h.window.moveMouse(100, 100)
  h.tick()
  near(state.scrollPos.y, 80)

block:
  echo "Testing swipe cancels a touch icon and tap activates once"
  mode = 2
  var h = setup()
  h.press(30, 40)
  doAssert clicks == 0
  h.release(30, 80)
  doAssert clicks == 0
  h.press(30, 40)
  h.release(30, 40)
  doAssert clicks == 1
  h.tick()
  doAssert clicks == 1

block:
  echo "Testing editable tap still starts native keyboard input"
  mode = 3
  var h = setup()
  h.press(80, 60)
  h.release(80, 60)
  doAssert h.window.runeInputEnabled
  doAssert textBoxStates["touch editable"].focused

block:
  echo "Testing desktop wheel still scrolls without capturing a pan"
  mode = 0
  var h = setup()
  h.window.pointerSource = MousePointer
  h.window.moveMouse(100, 100)
  h.window.scrollDelta = vec2(0, if ScrollSpeed > 0: 3 else: -3)
  h.tick()
  near(frameStates["touch parent"].scrollPos.y, 3 * abs(ScrollSpeed))
  doAssert not h.sk.touchScrolling

block:
  echo "Testing a horizontal track tap stays in the nested editor"
  mode = 4
  var h = setup()
  h.press(210, 135)
  h.release(210, 135)
  doAssert richTextBoxStates["touch rich"].editor.scrollPos.x > 100
  near(frameStates["touch parent"].scrollPos.y, 0)

block:
  echo "Testing popup controls block underlying viewport pans"
  mode = 0
  popup = true
  var h = setup()
  h.press(100, 140)
  h.release(100, 90)
  near(frameStates["touch parent"].scrollPos.y, 0)
  doAssert not h.sk.touchScrolling
  popup = false

block:
  echo "Testing reset and cancellation do not poison the next gesture"
  var h = setup()
  h.press(100, 140)
  h.sk.resetInteractions()
  h.release(-1, -1)
  h.tick()
  h.press(100, 140)
  h.release(100, 90)
  near(frameStates["touch parent"].scrollPos.y, 50)

block:
  echo "Testing panning preserves an unrelated editable selection"
  mode = 3
  var h = setup()
  let editor = textBoxStates["touch editable"]
  editor.cursor = 8
  editor.selector = 2
  h.press(100, 180)
  h.release(100, 140)
  doAssert editor.cursor == 8 and editor.selector == 2

block:
  echo "Testing a complete coalesced pan ignores the prior hover position"
  mode = 0
  for scale in [1, 3]:
    var h = setup()
    h.sk.uiScale = scale.float32
    h.tick()
    h.window.moveMouse(700 * scale, 400 * scale)
    h.window.moveMouse(120 * scale, 150 * scale)
    h.window.pressButton(MouseLeft)
    h.window.moveMouse(120 * scale, 130 * scale)
    h.window.moveMouse(120 * scale, 95 * scale)
    h.window.releaseButton(MouseLeft)
    h.tick()
    near(frameStates["touch parent"].scrollPos.y, 55)
    doAssert h.sk.touchScrolling
    h.tick()
    doAssert not h.sk.touchScrolling
    near(frameStates["touch parent"].scrollPos.y, 55)

block:
  echo "Testing a coalesced thumb drag uses the original grab offset"
  var h = setup()
  h.window.moveMouse(700, 400)
  h.window.moveMouse(318, 35)
  h.window.pressButton(MouseLeft)
  h.window.moveMouse(318, 60)
  h.window.moveMouse(318, 95)
  h.window.releaseButton(MouseLeft)
  h.tick()
  let position = frameStates["touch parent"].scrollPos.y
  doAssert position > 200 and h.sk.touchScrolling
  h.tick()
  near(frameStates["touch parent"].scrollPos.y, position)
  doAssert not frameStates["touch parent"].scrollingY

block:
  echo "Testing a drag across buttons without overflow cannot activate either"
  clicks = 0
  var h = newTestHarness(atlas)
  h.window.pointerSource = TouchPointer
  discard h.pumpFrame(drawButtons)
  h.window.moveMouse(40, 45)
  h.window.pressButton(MouseLeft)
  discard h.pumpFrame(drawButtons)
  h.window.moveMouse(140, 45)
  h.window.releaseButton(MouseLeft)
  discard h.pumpFrame(drawButtons)
  doAssert clicks == 0
  h.window.pressButton(MouseLeft)
  h.window.releaseButton(MouseLeft)
  discard h.pumpFrame(drawButtons)
  doAssert clicks == 1

echo "Touch scrolling tests passed."
