import
  std/[os, options],
  bumpy, pixie, vmath,
  silky

when not defined(silkyTesting):
  {.error: "Compile with -d:silkyTesting".}

const DataDirectory = currentSourcePath().parentDir / "data"

type Control = object
  bounds, clip: Rect
  layer: int
  enabled: bool = true

var
  atlas: SilkyAtlas
  counts: array[4, int]
  controls: seq[Control]
  origin: Vec2
  invalidateOnPress: bool
  selected: int
  showWindow = true

block:
  let builder = newAtlasBuilder(1024, 4)
  builder.addDir(DataDirectory, DataDirectory & DirSep)
  builder.addFont(DataDirectory / "IBMPlexSans-Regular.ttf", "Default", 18)
  doAssert builder.addImage("tap", newImage(24, 24))
  doAssert builder.addImage("droparrow", newImage(8, 8))
  atlas = builder.atlas

proc drawIcons(sk: Silky, window: Window) =
  ## Draws actual press-triggered icons in a viewport adjusted for safe areas.
  sk.mousePos -= origin
  for i in 0 ..< 2:
    sk.at = vec2((40 + i * 80).float32, 40)
    clickableIcon("tap", false):
      inc counts[i]

proc drawControls(sk: Silky, window: Window) =
  ## Registers overlapping candidates in explicit draw order and layers.
  for i, control in controls:
    sk.pushLayer(control.layer)
    sk.pushRawClipRect(control.clip)
    if sk.interact(control.bounds, control.enabled) == Pressed:
      inc counts[i]
      if invalidateOnPress:
        sk.resetInteractions()
    sk.popClipRect()
    sk.popLayer()

proc drawDropdown(sk: Silky, window: Window) =
  ## Exercises a press-owned control and a release-triggered button.
  sk.pushLayout(vec2(40, 40), vec2(240, 200))
  dropDown selected, [0, 1, 2]
  sk.at = vec2(40, 250)
  button("Button"):
    inc counts[0]
  sk.popLayout()

proc drawSubwindow(sk: Silky, window: Window) =
  ## Exercises a title-bar press that is released before the frame starts.
  let state = sk.subWindowStart(
    window, "First touch", showWindow,
    some(vec2(100, 100)), some(vec2(300, 200))
  )
  sk.subWindowEnd(window, state)

proc tap(
  harness: var TestHarness,
  draw: proc(sk: Silky, window: Window),
  position: Vec2,
  coalesced = false
) =
  ## Sends pointer movement with the press, without a hover-only frame.
  let pixels = ((position + origin) * harness.sk.uiScale).ivec2
  harness.window.moveMouse(pixels.x, pixels.y)
  harness.window.pressButton(MouseLeft)
  if coalesced:
    harness.window.releaseButton(MouseLeft)
  discard harness.pumpFrame(draw)
  if not coalesced:
    harness.window.releaseButton(MouseLeft)
    discard harness.pumpFrame(draw)

block:
  echo "Testing first-touch icons without hover frames at Retina scales"
  for scale in [1.0'f, 1.5'f, 3.0'f]:
    for safeOrigin in [vec2(0), vec2(0, 62)]:
      counts = default(typeof(counts))
      origin = safeOrigin
      var harness = newTestHarness(atlas)
      harness.sk.uiScale = scale
      discard harness.pumpFrame(drawIcons)
      harness.tap(drawIcons, vec2(132, 52))
      doAssert counts[1] == 1 and counts[0] == 0
      harness.tap(drawIcons, vec2(52, 52), coalesced = true)
      doAssert counts[0] == 1 and counts[1] == 1
      discard harness.pumpFrame(drawIcons)
      doAssert counts[0] == 1 and counts[1] == 1
  origin = vec2(0)

block:
  echo "Testing popup layers, draw order, disabled blockers and clipping"
  let
    bounds = rect(40, 40, 80, 80)
    fullClip = rect(0, 0, 400, 400)
  for mode in 0 ..< 4:
    counts = default(typeof(counts))
    controls = @[
      Control(bounds: bounds, clip: fullClip),
      Control(bounds: bounds, clip: fullClip)
    ]
    case mode
    of 0:
      discard # Later controls win within the same layer.
    of 1:
      controls[0].layer = PopupsLayer
    of 2:
      controls[1].enabled = false
    else:
      controls[1].clip = rect(90, 90, 20, 20)
    var harness = newTestHarness(atlas)
    discard harness.pumpFrame(drawControls)
    harness.tap(drawControls, vec2(52, 52))
    case mode
    of 0: doAssert counts[0] == 0 and counts[1] == 1
    of 1, 3: doAssert counts[0] == 1 and counts[1] == 0
    else: doAssert counts[0] == 0 and counts[1] == 0

block:
  echo "Testing moved geometry and explicit invalidation reject stale hits"
  counts = default(typeof(counts))
  controls = @[Control(bounds: rect(40, 40, 80, 80),
    clip: rect(0, 0, 400, 400))]
  var harness = newTestHarness(atlas)
  discard harness.pumpFrame(drawControls)
  controls[0].bounds.x += 1
  harness.tap(drawControls, vec2(52, 52))
  doAssert counts[0] == 0
  harness.tap(drawControls, vec2(52, 52))
  doAssert counts[0] == 1
  harness.sk.resetInteractions()
  harness.tap(drawControls, vec2(52, 52))
  doAssert counts[0] == 1
  controls.add(controls[0])
  invalidateOnPress = true
  harness.tap(drawControls, vec2(52, 52))
  doAssert counts[0] == 2 and counts[1] == 0
  invalidateOnPress = false

block:
  echo "Testing first-tap dropdowns and complete taps in one frame"
  for coalesced in [false, true]:
    counts = default(typeof(counts))
    selected = 0
    dropDownStates.clear()
    var harness = newTestHarness(atlas)
    discard harness.pumpFrame(drawDropdown)
    let bounds = harness.findByText("0", "DropDown").rect
    harness.tap(drawDropdown, bounds.xy + vec2(20, bounds.h / 2), coalesced)
    doAssert dropDownStates[cast[uint](addr selected)].open
    harness.tap(drawDropdown, bounds.xy + vec2(20, bounds.h * 2.5), coalesced)
    doAssert selected == 1
    doAssert not dropDownStates[cast[uint](addr selected)].open
    discard harness.pumpFrame(drawDropdown)
    harness.tap(drawDropdown, vec2(60, 265), coalesced)
    doAssert counts[0] == 1

block:
  echo "Testing a coalesced title-bar tap cannot latch dragging"
  subWindowStates.clear()
  var harness = newTestHarness(atlas)
  discard harness.pumpFrame(drawSubwindow)
  harness.tap(drawSubwindow, vec2(150, 115), coalesced = true)
  let state = subWindowStates["First touch"]
  doAssert not state.dragging and not state.resizing
  harness.window.moveMouse(500, 400)
  discard harness.pumpFrame(drawSubwindow)
  doAssert state.pos == vec2(100, 100)

echo "First-touch hit resolution tests passed."
