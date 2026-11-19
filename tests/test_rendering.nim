import
  std/unicode,
  pixie, silky, vmath,
  silky/[frames, testwindow]

when not defined(silkyTesting):
  {.error: "Run rendering tests with -d:silkyTesting; no window is used.".}

const
  InputId = "render scheduling input"
  RichInputId = "rich render scheduling input"

proc renderHarness(): TestHarness =
  ## Builds a test atlas without a native window or a generated atlas file.
  let builder = newAtlasBuilder(1024, 4)
  builder.addDir("tests/data/", "tests/data/")
  builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18.0)
  newTestHarness(builder.atlas, 600, 400)

proc typeText(window: Window, text: string) =
  ## Sends text through the callback consumed by a focused editor.
  for rune in text.runes:
    window.typeRune(rune)

proc testDeadlines() =
  ## Coalesces redraws and resumes sleeping when animation requests stop.
  echo "Testing deterministic redraw deadlines and animation lifetime"
  var
    schedule = FrameSchedule(mode: OnDemandRender)
    wakes = 0
  schedule.wake = proc() =
    ## Counts only requests that bring the next redraw forward.
    inc wakes
  doAssert schedule.needsFrame(nowMs = 100)
  schedule.beginFrame(nowMs = 100)
  doAssert not schedule.needsFrame(nowMs = 100)
  doAssert schedule.nextFrameDelay(nowMs = 100) == 1000
  schedule.requestFrame(delayMs = 83, nowMs = 100)
  doAssert wakes == 1
  doAssert not schedule.needsFrame(nowMs = 182)
  doAssert schedule.nextFrameDelay(nowMs = 182) == 1
  doAssert schedule.needsFrame(nowMs = 183)
  schedule.requestFrame(delayMs = 100, nowMs = 100)
  doAssert wakes == 1
  doAssert schedule.nextFrameDelay(nowMs = 100) == 83
  schedule.requestFrame(delayMs = 60, nowMs = 100)
  doAssert wakes == 2
  doAssert schedule.nextFrameDelay(nowMs = 100) == 60
  schedule.requestFrame(nowMs = 110)
  schedule.requestFrame(nowMs = 110)
  doAssert wakes == 3
  doAssert schedule.nextFrameDelay(nowMs = 110) == 0
  schedule.beginFrame(nowMs = 110)
  doAssert schedule.nextFrameDelay(nowMs = 110) == 50
  doAssert not schedule.needsFrame(nowMs = 159)
  schedule.beginFrame(nowMs = 160)
  doAssert not schedule.needsFrame(nowMs = 160)
  for time in [160'i64, 176, 192]:
    schedule.requestFrame(delayMs = 16, nowMs = time)
    doAssert schedule.nextFrameDelay(nowMs = time) == 16
    doAssert not schedule.needsFrame(nowMs = time + 15)
    doAssert schedule.needsFrame(nowMs = time + 16)
    schedule.beginFrame(nowMs = time + 16)
  doAssert not schedule.needsFrame(nowMs = 10_000)
  doAssert schedule.nextFrameDelay(maxWaitMs = 5000, nowMs = 10_000) == 5000
  schedule.mode = ContinuousRender
  schedule.beginFrame(nowMs = 10_000)
  doAssert schedule.needsFrame(nowMs = 10_000)
  doAssert schedule.nextFrameDelay(nowMs = 10_000) == 0

proc emptyFrame(harness: var TestHarness) =
  ## Draws a stable empty interface and consumes transient window input.
  harness.beginFrame()
  harness.endFrame()
  harness.window.resetInputState()

proc settle(harness: var TestHarness) =
  ## Allows bounded interaction settling without permitting an idle frame loop.
  for i in 0 ..< 4:
    if not harness.sk.needsFrame(harness.window):
      break
    harness.emptyFrame()
  doAssert not harness.sk.needsFrame(harness.window)

proc inputFrame(harness: var TestHarness, text: var string) =
  ## Uses the real editable textbox with a semantic window and no GPU.
  harness.beginFrame()
  harness.sk.at = vec2(12)
  harness.sk.textBox(
    harness.window,
    InputId,
    text,
    320,
    96,
    wrapWords = true
  )
  harness.endFrame()
  harness.window.resetInputState()

proc settleInput(harness: var TestHarness, text: var string) =
  ## Finishes queued editor redraws before testing a sleeping input field.
  for i in 0 ..< 4:
    if not harness.sk.needsFrame(harness.window):
      break
    harness.inputFrame(text)
  doAssert not harness.sk.needsFrame(harness.window)

proc testModes() =
  ## Keeps games continuous and lets a stable app stop rendering completely.
  echo "Testing continuous and on-demand rendering modes"
  var harness = renderHarness()
  doAssert harness.sk.renderMode == ContinuousRender
  for i in 0 ..< 3:
    doAssert harness.sk.needsFrame(harness.window)
    doAssert harness.sk.nextFrameDelay(harness.window, 1000) == 0
    harness.emptyFrame()
  harness.sk.renderMode = OnDemandRender
  doAssert harness.sk.needsFrame(harness.window)
  harness.settle()
  doAssert harness.sk.nextFrameDelay(harness.window, 1000) == 1000
  var wakes = 0
  harness.sk.onFrameRequested = proc() =
    ## Counts requests that can wake the native event wait.
    inc wakes
  harness.sk.requestFrame()
  doAssert wakes > 0
  doAssert harness.sk.needsFrame(harness.window)
  doAssert harness.sk.nextFrameDelay(harness.window, 1000) == 0
  harness.settle()
  harness.sk.renderMode = ContinuousRender
  for i in 0 ..< 3:
    doAssert harness.sk.needsFrame(harness.window)
    harness.emptyFrame()

proc testInputs() =
  ## Wakes for consumed text and keyboard input while scheduling the caret.
  echo "Testing on-demand editor input wakes and caret scheduling"
  var
    harness = renderHarness()
    text = ""
    wakes = 0
  harness.sk.renderMode = OnDemandRender
  harness.inputFrame(text)
  let editor = textBoxStates[InputId]
  defer:
    textBoxStates.del(InputId)
  harness.window.moveMouse(30, 30)
  harness.window.pressButton(MouseLeft)
  harness.window.releaseButton(MouseLeft)
  harness.inputFrame(text)
  harness.settleInput(text)
  harness.sk.onFrameRequested = proc() =
    ## Counts queued input even when the focused editor consumes callbacks.
    inc wakes
  harness.window.typeText("Dictated text")
  doAssert wakes > 0
  doAssert harness.sk.needsFrame(harness.window)
  harness.inputFrame(text)
  doAssert text == "Dictated text"
  harness.settleInput(text)
  let beforeKey = wakes
  harness.window.pressButton(KeyLeft)
  harness.window.releaseButton(KeyLeft)
  doAssert wakes > beforeKey
  doAssert harness.sk.needsFrame(harness.window)
  harness.inputFrame(text)
  doAssert editor.cursor == text.len - 1
  harness.settleInput(text)
  let delay = harness.sk.nextFrameDelay(harness.window, 1000)
  doAssert delay > 0 and delay <= 500
  editor.focused = false
  harness.window.focused = false
  harness.window.changeFocus()
  doAssert harness.sk.needsFrame(harness.window)
  harness.settle()

proc testHover() =
  ## Settles deferred hover state after input without redrawing forever.
  echo "Testing on-demand hover settling"
  var harness = renderHarness()
  harness.sk.renderMode = OnDemandRender
  harness.window.moveMouse(300, 300)
  proc frame(): bool =
    ## Resolves the same hover target through native Silky interaction state.
    harness.beginFrame()
    result = harness.sk.mouseHover(harness.window, rect(10, 10, 100, 40))
    harness.endFrame()
    harness.window.resetInputState()
  discard frame()
  for i in 0 ..< 3:
    if not harness.sk.needsFrame(harness.window):
      break
    discard frame()
  doAssert not harness.sk.needsFrame(harness.window)
  harness.window.moveMouse(30, 20)
  doAssert harness.sk.needsFrame(harness.window)
  discard frame()
  doAssert harness.sk.needsFrame(harness.window)
  doAssert frame()
  doAssert not harness.sk.needsFrame(harness.window)
  harness.window.moveMouse(300, 300)
  doAssert harness.sk.needsFrame(harness.window)
  doAssert not frame()
  if harness.sk.needsFrame(harness.window):
    doAssert not frame()
  doAssert not harness.sk.needsFrame(harness.window)

proc testGeometryInput() =
  ## Preserves geometry input through repeated scheduling queries until draw.
  echo "Testing geometry input survives frame scheduling queries"
  var harness = renderHarness()
  harness.sk.renderMode = OnDemandRender
  harness.settle()
  harness.window.size.x += 1
  doAssert harness.sk.needsFrame(harness.window)
  doAssert harness.sk.nextFrameDelay(harness.window) == 0
  harness.emptyFrame()
  doAssert harness.sk.needsFrame(harness.window),
    "A scheduling query consumed geometry input before the rendered frame."
  harness.emptyFrame()
  doAssert not harness.sk.needsFrame(harness.window)

proc testHoverGeometry() =
  ## Settles a retained hover target after its bounds or clip changes once.
  echo "Testing hover settling after layout and backing scale changes"
  var
    harness = renderHarness()
    bounds = rect(10, 10, 100, 40)
    clip = rect(0, 0, 300, 200)
  harness.sk.renderMode = OnDemandRender
  harness.window.mousePos = ivec2(30, 20)
  proc frame(): bool =
    ## Draws a fixed ordinal target using the current layout geometry.
    harness.beginFrame()
    harness.sk.pushClipRect(clip)
    result = harness.sk.mouseHover(harness.window, bounds)
    harness.sk.popClipRect()
    harness.endFrame()
    harness.window.resetInputState()
  doAssert harness.sk.needsFrame(harness.window)
  discard frame()
  doAssert harness.sk.needsFrame(harness.window)
  doAssert frame()
  doAssert not harness.sk.needsFrame(harness.window)
  for change in 0 ..< 3:
    case change
    of 0:
      bounds.x += 1
    of 1:
      clip.w -= 1
    else:
      harness.sk.uiScale = 2
      harness.window.size *= 2
      harness.window.mousePos *= 2
      bounds.w += 1
    harness.sk.requestFrame()
    doAssert harness.sk.needsFrame(harness.window)
    doAssert not frame(), "Changed regions must reject the stale hover hit."
    doAssert harness.sk.needsFrame(harness.window),
      "A changed region with the same target ID must settle its hover."
    doAssert frame()
    doAssert not harness.sk.needsFrame(harness.window),
      "Stable hover geometry must return to idle after one settling frame."
  harness.sk.uiScale = 1
  harness.window.size = ivec2(600, 400)
  harness.window.mousePos = ivec2(30, 20)
  doAssert harness.sk.needsFrame(harness.window)
  doAssert frame()
  doAssert harness.sk.needsFrame(harness.window)
  doAssert frame()
  doAssert not harness.sk.needsFrame(harness.window)
  harness.window.mousePos = ivec2(500, 300)
  doAssert harness.sk.needsFrame(harness.window)
  doAssert not frame()
  if harness.sk.needsFrame(harness.window):
    doAssert not frame()
  doAssert not harness.sk.needsFrame(harness.window)
  bounds.w += 1
  harness.sk.requestFrame()
  doAssert not frame()
  doAssert not harness.sk.needsFrame(harness.window),
    "Unhovered geometry must not schedule unnecessary settling frames."

proc testProgrammaticFocus() =
  ## Invalidates an idle editor when application code assigns focus.
  echo "Testing programmatic focus wakes an idle interface"
  var
    harness = renderHarness()
    text = "Focus me"
    wakes = 0
  harness.sk.renderMode = OnDemandRender
  harness.inputFrame(text)
  defer:
    textBoxStates.del(InputId)
  harness.settleInput(text)
  harness.sk.onFrameRequested = proc() =
    ## Records the wake sent by a focus change without native input.
    inc wakes
  textBoxStates[InputId].focus(harness.sk, harness.window, InputId)
  doAssert wakes > 0
  doAssert harness.sk.needsFrame(harness.window)
  harness.inputFrame(text)
  doAssert textBoxStates[InputId].focused
  doAssert harness.window.textInput.id == InputId

proc testRichCaret() =
  ## Keeps the new read-only rich editor's caret blinking while input is idle.
  echo "Testing on-demand rich editor caret scheduling"
  var harness = renderHarness()
  harness.sk.renderMode = OnDemandRender
  proc frame() =
    ## Draws rich content and consumes the simulated native input batch.
    harness.beginFrame()
    harness.sk.at = vec2(12)
    harness.sk.richTextBox(
      harness.window, RichInputId, "Selectable text", 320, 96
    )
    harness.endFrame()
    harness.window.resetInputState()
  frame()
  defer:
    richTextBoxStates.del(RichInputId)
  harness.window.moveMouse(30, 30)
  harness.window.pressButton(MouseLeft)
  harness.window.releaseButton(MouseLeft)
  frame()
  doAssert richTextBoxStates[RichInputId].editor.focused
  for i in 0 ..< 4:
    if not harness.sk.needsFrame(harness.window):
      break
    frame()
  doAssert not harness.sk.needsFrame(harness.window)
  let delay = harness.sk.nextFrameDelay(harness.window, 1000)
  doAssert delay > 0 and delay <= 500

proc testClippedCaret() =
  ## Keeps a focused caret outside the viewport from renewing animation work.
  echo "Testing clipped carets do not keep app rendering active"
  var harness = renderHarness()
  harness.sk.renderMode = OnDemandRender
  harness.settle()
  let editor = TextBoxState(lineHeight: 20, focused: true)
  harness.sk.requestFrame()
  harness.beginFrame()
  harness.sk.requestCursorFrame(
    harness.window, editor, rect(0, 1000, 100, 40)
  )
  harness.endFrame()
  harness.window.resetInputState()
  harness.settle()
  doAssert harness.sk.nextFrameDelay(harness.window, 1000) == 1000

testDeadlines()
testModes()
testInputs()
testHover()
testGeometryInput()
testHoverGeometry()
testProgrammaticFocus()
testRichCaret()
testClippedCaret()
echo "All rendering policy tests passed."
