import
  std/[math, os],
  bumpy, pixie, vmath,
  silky, silky/scrolls

when not defined(silkyTesting):
  {.error: "Compile with -d:silkyTesting".}

const
  NormalDeceleration = 0.998
  ReleaseTime = 100.0

type
  Position = ref object
    value: Vec2

  Target = object
    state: Position
    bounds: Rect
    maximum, signs: Vec2
    depth: int

  Scene = ref object
    touchScroll: TouchScroll
    touchOrigin, mousePos: Vec2
    clipRect: Rect
    currentDrawLayer: int
    time: float64
    targets: seq[Target]

proc near(actual, expected: float64, tolerance = 0.02) =
  ## Checks positions without hiding fractional drift across frame rates.
  doAssert abs(actual - expected) < tolerance,
    $actual & " != " & $expected

proc expectedDistance(velocity, milliseconds: float64): float64 =
  ## Uses Apple's published velocity projection with normal deceleration.
  velocity / 1000 * NormalDeceleration / (1 - NormalDeceleration) *
    (1 - pow(NormalDeceleration, milliseconds))

proc register(scene: Scene, target: Target) =
  ## Publishes displayed geometry while retaining the owner's mutable position.
  var tracks, thumbs: array[2, Rect]
  let
    state = target.state
    bounds = target.bounds
  if target.maximum.x > 0:
    tracks[0] = rect(bounds.x, bounds.y + bounds.h - 8, bounds.w, 8)
    let fraction = state.value.x / target.maximum.x
    thumbs[0] = rect(
      bounds.x + (bounds.w - 20) * fraction,
      tracks[0].y,
      20,
      8
    )
  if target.maximum.y > 0:
    tracks[1] = rect(bounds.x + bounds.w - 8, bounds.y, 8, bounds.h)
    let fraction = state.value.y / target.maximum.y
    thumbs[1] = rect(
      tracks[1].x,
      bounds.y + (bounds.h - 20) * fraction,
      8,
      20
    )
  scene.registerTouchScroll(
    cast[pointer](state),
    bounds,
    state.value,
    target.maximum,
    target.signs,
    tracks,
    thumbs,
    target.depth,
    proc(position: Vec2) =
      ## Applies input to the retained viewport position.
      state.value = position
  )

proc tick(
  scene: Scene,
  milliseconds: float64,
  point = vec2(100, 100),
  motion = vec2(0),
  velocity = vec2(0),
  pressed = false,
  down = false,
  released = false,
  focused = true,
  isTouch = true,
  interrupted = false,
  showTargets = true
) =
  ## Advances one deterministic input frame and refreshes visible targets.
  scene.mousePos = point
  scene.time = milliseconds
  scene.touchScroll.beginTouchFrame(
    isTouch,
    pressed,
    down,
    released,
    focused,
    point,
    motion,
    velocity,
    milliseconds,
    interrupted
  )
  if showTargets:
    for target in scene.targets:
      scene.register(target)
  scene.touchScroll.endTouchFrame()

proc setup(
  position = vec2(0, 1000),
  maximum = vec2(0, 10000),
  signs = vec2(1)
): Scene =
  ## Starts with displayed scroll regions and no gesture in progress.
  result = Scene(
    clipRect: rect(0, 0, 800, 600),
    targets: @[
      Target(
        state: Position(value: position),
        bounds: rect(0, 0, 300, 200),
        maximum: maximum,
        signs: signs
      )
    ]
  )
  result.tick(0)

proc fling(scene: Scene, velocity = vec2(0, -1000)): Vec2 =
  ## Delivers a complete finger gesture, including release, in one frame.
  scene.tick(
    ReleaseTime,
    point = vec2(100, 100),
    motion = vec2(0, -40),
    velocity = velocity,
    pressed = true,
    released = true
  )
  scene.targets[0].state.value

proc advance(scene: Scene, until: float64, step = 10.0) =
  ## Drives animation deadlines without sleeping or consulting a wall clock.
  var time = scene.time
  while time < until:
    time = min(until, time + step)
    scene.tick(time)

block:
  echo "Testing normal iOS deceleration against the published projection"
  let scene = setup()
  let released = scene.fling()
  doAssert scene.touchScroll.momentumActive
  scene.advance(ReleaseTime + 1000)
  near(scene.targets[0].state.value.y.float64 - released.y.float64,
    expectedDistance(1000, 1000))
  doAssert scene.touchScroll.momentumActive
  scene.advance(ReleaseTime + 4000)
  doAssert not scene.touchScroll.momentumActive
  let stopped = scene.targets[0].state.value
  scene.tick(ReleaseTime + 5000)
  doAssert scene.targets[0].state.value == stopped

block:
  echo "Testing equal elapsed motion at 60 Hz, 120 Hz and uneven frame times"
  var positions: seq[float64]
  for rate in [60, 120]:
    let scene = setup()
    let released = scene.fling()
    for frame in 1 .. rate:
      scene.tick(ReleaseTime + frame.float64 * 1000 / rate.float64)
    positions.add(scene.targets[0].state.value.y.float64 - released.y.float64)
  let scene = setup()
  let released = scene.fling()
  var
    time = ReleaseTime
    frame = 0
  while time < ReleaseTime + 1000:
    let delta = [5.0, 23.0, 11.0, 31.0, 9.0][frame mod 5]
    time = min(ReleaseTime + 1000, time + delta)
    scene.tick(time)
    inc frame
  positions.add(scene.targets[0].state.value.y.float64 - released.y.float64)
  for position in positions:
    near(position, expectedDistance(1000, 1000))
    near(position, positions[0])

block:
  echo "Testing both scroll bounds stop momentum without overshoot"
  for direction in [-1.0'f, 1.0'f]:
    let scene = setup(position = vec2(0, 60), maximum = vec2(0, 120))
    discard scene.fling(velocity = vec2(0, direction * 1000))
    scene.advance(ReleaseTime + 1000)
    near(scene.targets[0].state.value.y.float64,
      if direction < 0: 120.0 else: 0.0)
    doAssert not scene.touchScroll.momentumActive

block:
  echo "Testing a stopping touch is consumed, then the next tap works"
  let scene = setup()
  discard scene.fling()
  scene.tick(ReleaseTime + 16)
  let stopped = scene.targets[0].state.value
  scene.tick(ReleaseTime + 24, pressed = true, down = true)
  doAssert not scene.touchScroll.momentumActive
  doAssert scene.touchScrolling
  scene.tick(ReleaseTime + 40, released = true)
  doAssert not scene.touchTap(rect(0, 0, 300, 200))
  doAssert scene.targets[0].state.value == stopped
  scene.tick(ReleaseTime + 60, pressed = true, released = true)
  doAssert scene.touchTap(rect(0, 0, 300, 200))
  let outside = setup()
  discard outside.fling()
  outside.tick(ReleaseTime + 24, point = vec2(400, 100),
    pressed = true, released = true)
  doAssert not outside.touchScroll.momentumActive
  doAssert outside.touchTap(rect(350, 60, 100, 80))

block:
  echo "Testing scrollbar thumb drags never start momentum"
  let scene = setup(position = vec2(0, 1000), maximum = vec2(0, 2000))
  scene.tick(
    ReleaseTime,
    point = vec2(285, 145),
    motion = vec2(0, 45),
    velocity = vec2(0, 2000),
    pressed = true,
    released = true
  )
  let released = scene.targets[0].state.value
  doAssert released.y > 1000
  doAssert not scene.touchScroll.momentumActive
  scene.advance(ReleaseTime + 300)
  doAssert scene.targets[0].state.value == released

block:
  echo "Testing a stationary release and cancelled gestures do not fling"
  for mode in 0 ..< 4:
    let scene = setup()
    scene.tick(10, point = vec2(100, 140), pressed = true, down = true)
    scene.tick(30, point = vec2(100, 100), down = true)
    let position = scene.targets[0].state.value
    case mode
    of 0:
      scene.tick(ReleaseTime, velocity = vec2(0), released = true)
    of 1:
      scene.tick(ReleaseTime, point = vec2(-1), released = true,
        velocity = vec2(0, -1000))
    of 2:
      scene.tick(ReleaseTime, focused = false, released = true,
        velocity = vec2(0, -1000))
    else:
      scene.touchScroll.resetTouchScroll()
      scene.tick(ReleaseTime, released = true, velocity = vec2(0, -1000))
    doAssert not scene.touchScroll.momentumActive
    scene.tick(ReleaseTime + 100)
    doAssert scene.targets[0].state.value == position

block:
  echo "Testing interruptions, focus loss and vanished targets stop coasting"
  for mode in 0 ..< 7:
    let scene = setup()
    discard scene.fling()
    scene.tick(ReleaseTime + 16)
    case mode
    of 0:
      scene.tick(ReleaseTime + 24, interrupted = true)
    of 1:
      scene.tick(ReleaseTime + 24, focused = false)
    of 2:
      scene.tick(ReleaseTime + 24, isTouch = false)
    of 3:
      scene.touchScroll.resetTouchScroll()
      scene.tick(ReleaseTime + 24)
    of 4:
      scene.tick(ReleaseTime + 24, showTargets = false)
      scene.tick(ReleaseTime + 32, showTargets = false)
    of 5:
      scene.targets[0].state.value.y += 200
      for target in scene.targets:
        scene.register(target)
      scene.touchScroll.endTouchFrame()
      scene.tick(ReleaseTime + 24)
    else:
      scene.tick(ReleaseTime + 1000)
    doAssert not scene.touchScroll.momentumActive
    let position = scene.targets[0].state.value
    scene.tick(ReleaseTime + 100)
    doAssert scene.targets[0].state.value == position

block:
  echo "Testing nested axes and bottom-origin momentum ownership"
  for bottomOrigin in [false, true]:
    let scene = setup(signs = vec2(1, if bottomOrigin: -1 else: 1))
    let child = Position(value: vec2(1000, 0))
    scene.targets.add(Target(
      state: child,
      bounds: rect(40, 20, 180, 170),
      maximum: vec2(10000, 0),
      signs: vec2(1),
      depth: 1
    ))
    scene.tick(1)
    let released = scene.fling()
    scene.advance(ReleaseTime + 100)
    near(scene.targets[0].state.value.y.float64 - released.y.float64,
      expectedDistance(if bottomOrigin: -1000.0 else: 1000.0, 100))
    near(child.value.x.float64, 1000)
  let scene = setup()
  let child = Position(value: vec2(1000, 0))
  scene.targets.add(Target(
    state: child,
    bounds: rect(40, 20, 180, 170),
    maximum: vec2(10000, 0),
    signs: vec2(1),
    depth: 1
  ))
  scene.tick(1)
  scene.tick(ReleaseTime, point = vec2(100, 100), motion = vec2(-40, 0),
    velocity = vec2(-1000, -800), pressed = true, released = true)
  let released = child.value
  scene.advance(ReleaseTime + 100)
  near(child.value.x.float64 - released.x.float64,
    expectedDistance(1000, 100))
  near(scene.targets[0].state.value.y.float64, 1000)

var atlas: SilkyAtlas

block:
  let
    data = currentSourcePath().parentDir / "data"
    builder = newAtlasBuilder(1024, 4)
  builder.addDir(data, data & DirSep)
  builder.addFont(data / "IBMPlexSans-Regular.ttf", "Default", 18)
  atlas = builder.atlas

proc drawViewport(sk: Silky, window: Window) =
  ## Exercises the normal frame pipeline with a scrollable rendered viewport.
  ui:
    frame "momentum viewport":
      box 20, 30, 300, 200
      patch ""
      horizontalPadding 0
      verticalPadding 0
      itemSpacing 0
      layout TopToBottom
      group "document":
        size 280, 10000

block:
  echo "Testing native velocity conversion at 1x and 3x Retina scale"
  var positions: seq[float64]
  for scale in [1, 3]:
    frameStates.clear()
    var h = newTestHarness(atlas, 400 * scale, 400 * scale)
    h.sk.uiScale = scale.float32
    h.sk.touchTimeMs = 0
    h.window.pointerSource = TouchPointer
    discard h.pumpFrame(drawViewport)
    frameStates["momentum viewport"].scrollPos.y = 1000
    discard h.pumpFrame(drawViewport)
    h.window.moveMouse(100 * scale, 150 * scale)
    h.window.pressButton(MouseLeft)
    h.window.moveMouse(100 * scale, 110 * scale)
    h.window.pointerVelocity = vec2(0, (-1000 * scale).float32)
    h.window.releaseButton(MouseLeft)
    h.sk.touchTimeMs = ReleaseTime
    discard h.pumpFrame(drawViewport)
    let released = frameStates["momentum viewport"].scrollPos.y
    doAssert h.sk.touchScroll.momentumActive
    for frame in 1 .. 50:
      h.sk.touchTimeMs = ReleaseTime + frame.float64 * 10
      discard h.pumpFrame(drawViewport)
    positions.add(frameStates["momentum viewport"].scrollPos.y.float64 -
      released.float64)
  for position in positions:
    near(position, expectedDistance(1000, 500))
    near(position, positions[0])

echo "Scroll momentum tests passed."
