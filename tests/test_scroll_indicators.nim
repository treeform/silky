import
  std/os,
  pixie, vmath, bumpy,
  silky, silky/scrolls

when not defined(silkyTesting):
  {.error: "Compile with -d:silkyTesting".}

type
  Position = ref object
    value: Vec2

  Scene = ref object
    touchScroll: TouchScroll
    touchOrigin, mousePos: Vec2
    clipRect: Rect
    currentDrawLayer: int
    delays: seq[int]
    position: Position

proc drawWidgets(sk: Silky, window: Window) =
  ## Exercises a real frame with overflow and its retained scrollbar.
  ui:
    frame "indicator frame":
      box 20, 30, 320, 180
      patch ""
      layout TopToBottom
      horizontalPadding 0
      verticalPadding 0
      itemSpacing 0
      group "content":
        size 300, 800

proc requestFrame(scene: Scene, delayMs = 0) =
  ## Records redraw deadlines requested by a transient indicator.
  scene.delays.add(delayMs)

proc near(actual, expected: float32) =
  ## Checks opacity without depending on floating-point rounding.
  doAssert abs(actual - expected) < 0.001'f, $actual & " != " & $expected

proc register(scene: Scene) =
  ## Publishes one retained viewport with a visible scrollbar track.
  let position = scene.position
  var tracks, thumbs: array[2, Rect]
  tracks[1] = rect(192, 0, 8, 200)
  thumbs[1] = rect(192, position.value.y / 10, 8, 20)
  scene.registerTouchScroll(
    cast[pointer](position), rect(0, 0, 200, 200), position.value,
    vec2(0, 2000), vec2(1), tracks, thumbs, 0,
    proc(value: Vec2) =
      ## Applies captured gestures to the retained viewport.
      position.value = value
  )

proc setup(): Scene =
  ## Creates displayed scroll geometry without starting a gesture.
  result = Scene(
    position: Position(), clipRect: rect(0, 0, 400, 400),
    mousePos: vec2(100, 100)
  )
  result.register()
  result.touchScroll.endTouchFrame()

proc tick(
  scene: Scene, time: float64, point: Vec2,
  pressed = false, down = false, released = false,
  velocity = vec2(0), isTouch = true
) =
  ## Advances input while retaining final-release activity for drawing.
  scene.mousePos = point
  scene.touchScroll.beginTouchFrame(
    isTouch, pressed, down, released, true, point, vec2(0), velocity, time
  )
  scene.register()
  scene.touchScroll.endTouchFrame()

block:
  echo "Testing scroll indicator timing and renewed activity"
  var indicator: ScrollIndicator
  near(indicator.indicatorOpacity(false, 100), 0)
  near(indicator.indicatorOpacity(true, 100), 1)
  near(indicator.indicatorOpacity(false, 250), 1)
  near(indicator.indicatorOpacity(false, 375), 0.5)
  near(indicator.indicatorOpacity(false, 500), 0)
  near(indicator.indicatorOpacity(false, 1000), 0)
  near(indicator.indicatorOpacity(true, 1100), 1)
  near(indicator.indicatorOpacity(false, 1400), 0.4)
  near(indicator.indicatorOpacity(true, 1401), 1)

block:
  echo "Testing fade redraw deadlines and desktop visibility"
  let scene = setup()
  var indicator: ScrollIndicator
  scene.tick(0, vec2(100, 100))
  let target = cast[pointer](scene.position)
  near(scene.scrollbarOpacity(indicator, target, nowMs = 0), 0)
  doAssert scene.delays.len == 0
  near(scene.scrollbarOpacity(indicator, target, true, 100), 1)
  doAssert scene.delays[^1] == ScrollIndicatorDelay.int
  near(scene.scrollbarOpacity(indicator, target, false, 300), 0.8)
  doAssert scene.delays[^1] == 16
  let before = scene.delays.len
  near(scene.scrollbarOpacity(indicator, target, false, 500), 0)
  doAssert scene.delays.len == before
  scene.tick(600, vec2(100, 100), isTouch = false)
  near(scene.scrollbarOpacity(indicator, target, nowMs = 600), 1)
  doAssert scene.delays.len == before

block:
  echo "Testing only the dragged viewport remains visible on release"
  let scene = setup()
  var active, other: ScrollIndicator
  let target = cast[pointer](scene.position)
  scene.tick(0, vec2(100, 150), pressed = true, down = true)
  near(scene.scrollbarOpacity(active, target, nowMs = 0), 0)
  scene.tick(20, vec2(100, 100), down = true)
  doAssert scene.position.value.y == 50
  near(scene.scrollbarOpacity(active, target, nowMs = 20), 1)
  near(scene.scrollbarOpacity(other, cast[pointer](1), nowMs = 20), 0)
  scene.tick(40, vec2(100, 80), released = true)
  near(scene.scrollbarOpacity(active, target, nowMs = 40), 1)
  doAssert active.lastActivity == 40
  scene.tick(41, vec2(100, 80))
  near(scene.scrollbarOpacity(active, target, nowMs = 41), 1)
  doAssert active.lastActivity == 40
  scene.tick(440, vec2(100, 80))
  near(scene.scrollbarOpacity(active, target, nowMs = 440), 0)

block:
  echo "Testing momentum keeps its indicator visible through the final frame"
  let scene = setup()
  var indicator: ScrollIndicator
  let target = cast[pointer](scene.position)
  scene.tick(0, vec2(100, 150), pressed = true, down = true)
  scene.tick(20, vec2(100, 100), down = true)
  scene.tick(40, vec2(100, 80), released = true, velocity = vec2(0, -400))
  doAssert scene.touchScroll.momentumActive()
  var time = 40.0
  while scene.touchScroll.momentumActive():
    time += 100
    scene.tick(time, vec2(100, 80))
    near(scene.scrollbarOpacity(indicator, target, nowMs = time), 1)
    doAssert indicator.lastActivity == time
    doAssert time < 10000
  scene.tick(time + 1, vec2(100, 80))
  near(scene.scrollbarOpacity(indicator, target, nowMs = time + 1), 1)
  doAssert indicator.lastActivity == time
  scene.tick(time + 400, vec2(100, 80))
  near(scene.scrollbarOpacity(indicator, target, nowMs = time + 400), 0)

block:
  echo "Testing hidden real frame scrollbars still accept thumb dragging"
  let
    data = currentSourcePath().parentDir / "data"
    builder = newAtlasBuilder(1024, 4)
  builder.addDir(data, data & DirSep)
  builder.addFont(data / "IBMPlexSans-Regular.ttf", "Default", 18)
  frameStates.clear()
  var h = newTestHarness(builder.atlas)
  h.window.pointerSource = TouchPointer
  discard h.pumpFrame(drawWidgets)
  let state = frameStates["indicator frame"]
  doAssert not state.scrollIndicator.shown
  h.window.moveMouse(318, 35)
  h.window.pressButton(MouseLeft)
  discard h.pumpFrame(drawWidgets)
  h.window.moveMouse(318, 80)
  discard h.pumpFrame(drawWidgets)
  doAssert state.scrollPos.y > 100
  doAssert state.scrollIndicator.shown
  h.window.releaseButton(MouseLeft)
  discard h.pumpFrame(drawWidgets)
  let position = state.scrollPos.y
  state.scrollIndicator.lastActivity = scrollMilliseconds() - 500
  discard h.pumpFrame(drawWidgets)
  doAssert not state.scrollIndicator.shown
  near(state.scrollPos.y, position)

echo "All scroll indicator tests passed."
