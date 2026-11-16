import
  std/unicode,
  vmath, bumpy,
  silky, silky/semantics, silky/internal/[inputs, textpresses]

when not defined(silkyTesting):
  {.error: "Compile with -d:silkyTesting".}

block:
  echo "Testing stationary text hold timing and cancellation"
  var press = beginTextPress(vec2(10, 20), 100, true)
  doAssert press.updateTextPress(vec2(10, 20), true, false, false, 599) ==
    WaitingTextPress
  doAssert press.updateTextPress(vec2(10, 20), true, false, false, 600) ==
    HeldTextPress
  doAssert press.updateTextPress(vec2(10, 20), false, true, false, 601) ==
    NoTextPress
  for mode in 0 .. 2:
    press = beginTextPress(vec2(10, 20), 0, true)
    doAssert press.updateTextPress(
      (if mode == 0: vec2(16, 20) else: vec2(10, 20)),
      mode != 1, false, mode == 2, 501
    ) == NoTextPress

let builder = newAtlasBuilder(1024, 4)
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18)
var
  harness = newTestHarness(builder.atlas)
  value = "café 世界 copy"
  editable = true
  password = false
  rich = false
  hidden = false
  offset = vec2(0)
  spans: seq[TextSpan]
  blocks: seq[TextBlock]

proc draw(sk: Silky, window: Window) =
  ## Draws one real text widget with optionally deferred screen placement.
  if hidden:
    return
  sk.at = vec2(20, 20)
  let mark = sk.textInputs.textPlacementMark()
  if rich:
    sk.richTextBox(window, "menu-rich", value, 320, 180,
      spans = spans, blocks = blocks)
  else:
    sk.textBox(window, "menu-edit", value, 320, 180,
      wrapWords = true, enabled = editable, password = password)
  sk.textInputs.translateTextInput(mark, offset)

proc editor(): TextBoxState =
  ## Returns the currently displayed field state.
  if rich: richTextBoxStates["menu-rich"].editor
  else: textBoxStates["menu-edit"]

proc setup() =
  ## Starts a fresh displayed editor without a previous menu or gesture.
  textBoxStates.clear()
  richTextBoxStates.clear()
  harness = newTestHarness(builder.atlas)
  harness.window.pointerSource = TouchPointer
  discard harness.pumpFrame(draw)

proc pressGlyph(index = 1) =
  ## Presses the center of a real laid-out glyph.
  let box = editor().layout[index]
  harness.window.moveMouse(
    int(20 + harness.sk.theme.padding.float32 + box.x + box.w / 2),
    int(20 + harness.sk.theme.padding.float32 + box.y + box.h / 2)
  )
  harness.window.pressButton(MouseLeft)
  discard harness.pumpFrame(draw)

proc hold() =
  ## Advances the gesture clock without blocking the test process.
  editor().touchPress.started -= TextPressDelay + 1
  discard harness.pumpFrame(draw)
  harness.window.releaseButton(MouseLeft)
  discard harness.pumpFrame(draw)

block:
  echo "Testing selected text remains selected through a hold"
  for readOnly in [false, true]:
    rich = readOnly
    setup()
    editor().cursor = 4
    editor().selector = 0
    pressGlyph()
    doAssert editor().cursor == 4 and editor().selector == 0
    hold()
    doAssert editor().selection == (0 .. 4)
    doAssert harness.window.editMenuShows == 1
    doAssert harness.window.runeInputEnabled == not readOnly
    doAssert CopyTextAction in harness.window.editMenuActions
    doAssert (PasteTextAction in harness.window.editMenuActions) == not readOnly
    harness.window.editMenuCallback(CopyTextAction)
    discard harness.pumpFrame(draw)
    doAssert getClipboardString() == "café"

block:
  echo "Testing paste hooks, replacement undo, and readonly select all"
  rich = false
  setup()
  editor().selectAll()
  pressGlyph()
  hold()
  setClipboardString("✓ café")
  harness.window.editMenuCallback(PasteTextAction)
  discard harness.pumpFrame(draw)
  doAssert value == "✓ café"
  editor().undo()
  doAssert editor().getText() == "café 世界 copy"
  value = editor().getText()
  setup()
  var
    pasteCalls = 0
    pasteWakeups = 0
  harness.sk.textInputs.onEvent = proc() =
    ## Records repaint requests for native actions without keyboard events.
    inc pasteWakeups
  harness.sk.textInputs.onPaste = proc(id: string): bool =
    ## Models Runway consuming an image paste without inserting text.
    doAssert id == "menu-edit"
    inc pasteCalls
    true
  pressGlyph()
  hold()
  harness.window.editMenuCallback(PasteTextAction)
  discard harness.pumpFrame(draw)
  doAssert pasteCalls == 1
  doAssert pasteWakeups == 1
  doAssert value == "café 世界 copy"
  rich = true
  setup()
  pressGlyph()
  hold()
  harness.window.editMenuCallback(SelectAllTextAction)
  discard harness.pumpFrame(draw)
  doAssert editor().selection == (0 .. value.runeLen)
  doAssert not harness.window.runeInputEnabled

block:
  echo "Testing blank and password fields expose only safe actions"
  rich = false
  value = ""
  setup()
  harness.window.moveMouse(45, 45)
  harness.window.pressButton(MouseLeft)
  discard harness.pumpFrame(draw)
  hold()
  doAssert harness.window.editMenuActions == {PasteTextAction}
  value = "secret"
  password = true
  setup()
  pressGlyph()
  hold()
  doAssert harness.window.editMenuActions == {PasteTextAction}
  password = false

block:
  echo "Testing short taps, scroll motion, and stale actions"
  value = "café 世界 copy"
  setup()
  editor().selectAll()
  pressGlyph()
  harness.window.releaseButton(MouseLeft)
  discard harness.pumpFrame(draw)
  doAssert editor().cursor == editor().selector
  doAssert harness.window.editMenuShows == 0
  setup()
  pressGlyph()
  editor().touchPress.started -= TextPressDelay + 1
  harness.window.moveMouse(harness.window.mousePos.x + 6,
    harness.window.mousePos.y)
  discard harness.pumpFrame(draw)
  doAssert harness.window.editMenuShows == 0
  harness.window.releaseButton(MouseLeft)
  discard harness.pumpFrame(draw)
  setup()
  harness.window.moveMouse(40, 40)
  harness.window.pressButton(MouseLeft)
  harness.window.moveMouse(55, 40)
  discard harness.pumpFrame(draw)
  doAssert not editor().touchPress.active
  hold()
  doAssert harness.window.editMenuShows == 0
  setup()
  pressGlyph()
  hold()
  let callback = harness.window.editMenuCallback
  hidden = true
  discard harness.pumpFrame(draw)
  callback(CutTextAction)
  hidden = false
  discard harness.pumpFrame(draw)
  doAssert value == "café 世界 copy"

block:
  echo "Testing hold suppresses link release and translates its menu"
  rich = true
  offset = vec2(13, 45)
  spans = @[TextSpan(first: 0, last: 4, linkId: 1)]
  setup()
  pressGlyph()
  let point = harness.window.mousePos.vec2
  hold()
  doAssert richTextBoxStates["menu-rich"].activatedSpan == -1
  doAssert abs(harness.window.editMenuBounds.x - point.x + 1 - offset.x) < 0.01
  doAssert abs(harness.window.editMenuBounds.y - point.y +
    editor().lineHeight - offset.y) < 0.01
  doAssert harness.window.editMenuShows == 1

block:
  echo "Testing image blocks cannot claim a text menu"
  offset = vec2(0)
  spans = @[]
  blocks = @[TextBlock(first: 0, last: 0, image: "missing-image",
    imageSize: vec2(100, 100))]
  setup()
  harness.window.moveMouse(60, 60)
  harness.window.pressButton(MouseLeft)
  discard harness.pumpFrame(draw)
  doAssert not editor().touchPress.active
  hold()
  doAssert harness.window.editMenuShows == 0

textBoxStates.clear()
richTextBoxStates.clear()
echo "Text menu checks passed"
