import
  std/strutils,
  bumpy, pixie, vmath,
  silky, silky/layout

when not defined(silkyTesting):
  {.error: "Compile with -d:silkyTesting".}

const
  Viewport = rect(20, 30, 320, 180)
  TextWidth = 308.0'f
  LeadingHeight = 400.0'f
  TrailingHeight = 200.0'f
  Spacing = 10.0'f

type Fixture = object
  harness: TestHarness
  frameId, replyId, text: string
  direction: StackDirection
  height: float32
  content, origin: Vec2
  caret: Rect
  navigated: bool

var
  atlas: SilkyAtlas
  nextId: int

proc checkVec(actual, expected: Vec2) =
  ## Compares scrolling coordinates without discarding fractional positions.
  doAssert abs(actual.x - expected.x) < 0.01, $actual & " != " & $expected
  doAssert abs(actual.y - expected.y) < 0.01, $actual & " != " & $expected

block:
  echo "Testing reveal margins, clamping, and all stack directions"
  let
    viewport = rect(20, 30, 200, 100)
    content = vec2(1000, 1000)
    scroll = vec2(100, 100)
  for direction in StackDirection:
    let signs = direction.dirSigns
    checkVec(
      revealScroll(scroll, content, viewport, rect(0, 10, 10, 10), direction),
      scroll + signs * vec2(-24, -24)
    )
    checkVec(
      revealScroll(
        scroll, content, viewport, rect(220, 130, 10, 10), direction
      ),
      scroll + signs * vec2(14, 14)
    )
    checkVec(
      revealScroll(scroll, content, viewport, rect(25, 35, 10, 10), direction),
      scroll
    )
    checkVec(
      revealScroll(
        scroll, content, viewport, rect(22.5, 32.5, 10, 10), direction
      ),
      scroll + signs * vec2(-1.5, -1.5)
    )
    checkVec(
      revealScroll(
        scroll, content, viewport, rect(20, 30, 10, 10), direction, -5
      ),
      scroll
    )
    checkVec(
      revealScroll(
        scroll, content, rect(20, 30, 10, 10), rect(20, 30, 8, 8),
        direction, 20
      ),
      scroll - signs
    )
    for target in [rect(-2000, -2000, 10, 10), rect(2000, 2000, 10, 10)]:
      let expected = vec2(
        if (target.x < 0) == (signs.x > 0): 0 else: 800,
        if (target.y < 0) == (signs.y > 0): 0 else: 900
      )
      checkVec(
        revealScroll(scroll, content, viewport, target, direction), expected
      )
    checkVec(
      revealScroll(scroll, vec2(20, 20), viewport, viewport, direction),
      vec2(0, 0)
    )

    echo "Testing oversized targets stay aligned in ", direction
    let
      target = rect(40, 50, 300, 180)
      moved = revealScroll(scroll, content, viewport, target, direction)
      shifted = rect(target.xy - signs * (moved - scroll), target.wh)
    checkVec(moved, scroll + signs * vec2(20, 20))
    checkVec(shifted.xy, viewport.xy)
    checkVec(revealScroll(moved, content, viewport, shifted, direction), moved)

  checkVec(
    revealScroll(scroll, content, rect(20, 30, 0, 100), rect(0, 10, 10, 10)),
    vec2(100, 76)
  )
  checkVec(
    revealScroll(scroll, content, rect(20, 30, 200, 0), rect(0, 10, 10, 10)),
    vec2(76, 100)
  )

block:
  let builder = newAtlasBuilder(1024, 4)
  builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18)
  builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Wide", 30)
  for name in [
    "textbox.disabled.9patch", "scrollbar.track.9patch", "scrollbar.9patch"
  ]:
    doAssert builder.addImage(name, newImage(16, 16))
  atlas = builder.atlas

proc state(f: Fixture): RichTextBoxState =
  ## Returns the document state owned by the actual rich textbox widget.
  richTextBoxStates[f.replyId]

proc frameState(f: Fixture): FrameState =
  ## Returns the surrounding frame's persistent scroll state.
  frameStates[f.frameId]

proc fixture(direction: StackDirection, scale: float32): Fixture =
  ## Creates a rich document taller than its scrolling parent viewport.
  inc nextId
  result.frameId = "cursor frame " & $nextId
  result.replyId = "cursor reply " & $nextId
  result.direction = direction
  result.harness = newTestHarness(atlas)
  result.harness.sk.theme.padding = 0
  result.harness.sk.uiScale = scale
  result.text = "Heading\n" & repeat(
    "Wrapped document text with several words on each line.\n", 30
  )
  let state = newRichTextBoxState(result.text)
  state.blocks = @[
    TextBlock(first: 0, last: 7, font: "Wide", spacing: 8),
    TextBlock(first: 8, last: result.text.len)
  ]
  state.computeLayout(atlas.fonts, "Default", TextWidth)
  richTextBoxStates[result.replyId] = state
  result.height = state.innerHeight
  result.content = vec2(
    Viewport.w, LeadingHeight + result.height + TrailingHeight + Spacing * 3
  )
  let initial =
    if direction == BottomToTop:
      LeadingHeight + Spacing + result.height - Viewport.h + 4
    else:
      LeadingHeight + Spacing - 4
  frameStates[result.frameId] = FrameState(scrollPos: vec2(0, initial))

proc frame(f: var Fixture) =
  ## Draws the real frame and reveals the caret only after keyboard navigation.
  let
    sk = f.harness.sk
    window = f.harness.window
    baseline = f.frameState.scrollPos
    state = f.state
  f.harness.beginFrame()
  ui:
    frame f.frameId:
      box Viewport
      patch ""
      layout f.direction
      horizontalPadding 0
      verticalPadding 0
      itemSpacing Spacing
      group "leading":
        size TextWidth, LeadingHeight
      group "reply":
        size TextWidth, f.height
        layout TopToBottom
        horizontalPadding 0
        verticalPadding 0
        itemSpacing 0
        sk.startCurrentChildren()
        f.origin = sk.at
        sk.richTextBox(
          window, f.replyId, f.text, TextWidth, f.height,
          blocks = state.blocks
        )
        f.navigated = state.cursorNavigated
        let caret = state.editor.locationRect(state.editor.cursor)
        f.caret = rect(
          f.origin + caret.xy - state.editor.scrollPos, caret.wh
        )
      group "trailing":
        size TextWidth, TrailingHeight
  f.harness.endFrame()
  if f.navigated:
    f.frameState.scrollPos = revealScroll(
      baseline, f.content, Viewport, f.caret, f.direction
    )
  window.resetInputState()

proc settle(f: var Fixture) =
  ## Checks the next idle frame preserves scrolling and shows the whole caret.
  let scroll = f.frameState.scrollPos
  f.frame()
  doAssert not f.navigated
  checkVec(f.frameState.scrollPos, scroll)
  doAssert f.caret.y >= Viewport.y - 0.01
  doAssert f.caret.y + f.caret.h <= Viewport.y + Viewport.h + 0.01
  doAssert f.state.editor.scrollPos.y == 0

proc focus(f: var Fixture) =
  ## Clicks the first glyph through the window's normal input callbacks.
  f.frame()
  let
    window = f.harness.window
    point = (
      f.origin + f.state.editor.layout[0].xy + vec2(2, 4)
    ) * f.harness.sk.uiScale
  window.moveMouse(point.x.int, point.y.int)
  window.pressButton(MouseLeft)
  window.releaseButton(MouseLeft)
  f.frame()
  doAssert f.state.editor.focused
  doAssert not f.navigated
  f.state.editor.cursor = 0
  f.state.editor.selector = 0
  f.state.editor.savedX = 0

proc tap(window: Window, key: Button) =
  ## Delivers a complete key event through Silky's installed callbacks.
  window.pressButton(key)
  window.releaseButton(key)

proc shortcut(window: Window, key: Button) =
  ## Delivers an application shortcut using the platform's usual modifier.
  let modifier =
    when defined(macosx):
      KeyLeftSuper
    else:
      KeyLeftControl
  window.pressButton(modifier)
  window.tap(key)
  window.releaseButton(modifier)

proc testDocument(direction: StackDirection, scale: float32) =
  ## Exercises real keyboard, selection, scrolling, and idle widget frames.
  echo "Testing rich cursor following in ", direction, " at scale ", scale
  var f = fixture(direction, scale)
  defer:
    frameStates.del(f.frameId)
    richTextBoxStates.del(f.replyId)
  let
    window = f.harness.window
    editor = f.state.editor
  f.focus()
  let initial = f.frameState.scrollPos.y
  for i in 0 ..< 18:
    window.pressButton(KeyDown)
    f.frame()
    doAssert f.navigated
    f.settle()
  window.releaseButton(KeyDown)
  doAssert (f.frameState.scrollPos.y - initial) * direction.dirSigns.y > 0

  let anchor = editor.cursor
  window.pressButton(KeyLeftShift)
  for i in 0 ..< 8:
    window.pressButton(KeyDown)
    f.frame()
    doAssert f.navigated
    doAssert editor.selector == anchor
    f.settle()
  doAssert editor.copyText().len > 0
  window.releaseButton(KeyDown)
  window.releaseButton(KeyLeftShift)
  let lower = f.frameState.scrollPos.y
  for i in 0 ..< 24:
    window.pressButton(KeyUp)
    f.frame()
    doAssert f.navigated
    f.settle()
  window.releaseButton(KeyUp)
  doAssert (f.frameState.scrollPos.y - lower) * direction.dirSigns.y < 0

  echo "Testing wheel, copy, and Select All do not reveal the cursor"
  let
    beforeWheel = f.frameState.scrollPos
    pointer = vec2(Viewport.x + 30, Viewport.y + 60) * scale
  window.moveMouse(pointer.x.int, pointer.y.int)
  window.scrollDelta = vec2(0, 3)
  f.frame()
  doAssert not f.navigated
  let expected = vec2(
    beforeWheel.x,
    clamp(
      beforeWheel.y + direction.dirSigns.y * 3 * ScrollSpeed,
      0.0'f,
      f.content.y - Viewport.h
    )
  )
  checkVec(f.frameState.scrollPos, expected)
  f.frame()
  checkVec(f.frameState.scrollPos, expected)
  for key in [KeyA, KeyC]:
    window.shortcut(key)
    f.frame()
    doAssert not f.navigated
    checkVec(f.frameState.scrollPos, expected)
  doAssert getClipboardString() == f.text

  echo "Testing navigation reveals an offscreen caret even at the text boundary"
  editor.cursor = 0
  editor.selector = 0
  f.frameState.scrollPos.y =
    if direction == BottomToTop:
      0.0'f
    else:
      f.content.y - Viewport.h
  f.frame()
  doAssert editor.focused
  doAssert not f.navigated
  doAssert f.caret.y + f.caret.h < Viewport.y
  window.tap(KeyUp)
  f.frame()
  doAssert f.navigated and editor.cursor == 0
  f.settle()

  for key in [KeyRight, KeyLeft, KeyEnd, KeyHome, KeyPageDown, KeyPageUp]:
    window.tap(key)
    f.frame()
    doAssert f.navigated
    f.settle()

for direction in [TopToBottom, BottomToTop]:
  for scale in [1.0'f, 1.5'f, 2.0'f]:
    testDocument(direction, scale)

echo "All cursor scrolling tests passed."
