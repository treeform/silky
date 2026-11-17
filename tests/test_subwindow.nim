import
  std/options,
  vmath,
  silky

when not defined(silkyTesting):
  {.error: "Compile with -d:silkyTesting".}

let builder = newAtlasBuilder(1024, 4)
builder.addDir("tests/data/", "tests/data/")
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18.0)

var show = true

proc drawSubwindow(sk: Silky, window: Window) =
  ## Exercise the real title-bar interaction and balanced window layout.
  let state = sk.subWindowStart(
    window, "Drag regression", show, some(vec2(100, 100)), some(vec2(300, 200))
  )
  sk.subWindowEnd(window, state)

block:
  subWindowStates.clear()
  var harness = newTestHarness(builder.atlas)
  let window = harness.window
  window.moveMouse(150, 110)
  discard harness.pumpFrame(drawSubwindow, 2)
  let state = subWindowStates["Drag regression"]
  window.pressButton(MouseLeft)
  discard harness.pumpFrame(drawSubwindow)
  doAssert state.dragging, "Pressing the header must start dragging"
  doAssert state.pos == vec2(100, 100)

  # A held drag must keep working even when the pointer leaves the old header.
  window.moveMouse(210, 160)
  discard harness.pumpFrame(drawSubwindow)
  doAssert state.dragging
  doAssert state.pos == vec2(160, 150)
  let heldPosition = state.pos

  # Release well outside the current header before another frame is drawn.
  window.moveMouse(450, 350)
  window.releaseButton(MouseLeft)
  discard harness.pumpFrame(drawSubwindow)
  doAssert not state.dragging, "Releasing outside the header must end dragging"
  doAssert state.pos == heldPosition, "A released drag must not move the window"

  window.moveMouse(600, 450)
  discard harness.pumpFrame(drawSubwindow, 2)
  doAssert state.pos == heldPosition,
    "Pointer movement after an outside release must not drag the window"

  # A new drag starts from the last held position, not a stale drag offset.
  window.moveMouse(230, 160)
  discard harness.pumpFrame(drawSubwindow, 2)
  window.pressButton(MouseLeft)
  discard harness.pumpFrame(drawSubwindow)
  doAssert state.dragging and state.pos == heldPosition
  window.moveMouse(260, 180)
  discard harness.pumpFrame(drawSubwindow)
  doAssert state.pos == heldPosition + vec2(30, 20)
  discard harness.pumpFrame(drawSubwindow, 2)
  window.releaseButton(MouseLeft)
  discard harness.pumpFrame(drawSubwindow)
  doAssert not state.dragging, "Releasing over the header must still end dragging"

  echo "Subwindow outside release stops dragging and the next drag starts cleanly"
