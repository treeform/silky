import
  std/[math, monotimes],
  vmath, bumpy

const
  TouchPanThreshold = 6.0'f
  TouchScrollbarWidth = 28.0'f
  # UIKit's normal rate, applied per millisecond of elapsed time.
  ScrollDeceleration* = 0.998
  MinimumFlingSpeed = 50.0
  ScrollStopSpeed = 5.0
  MaximumFrameGap = 250.0

type
  TouchBlocker = object
    bounds, clip: Rect
    layer: int

  ScrollRegion = object
    target: pointer
    bounds, clip: Rect
    tracks, thumbs: array[2, Rect]
    position, maximum, signs: Vec2
    layer, depth: int
    apply: proc(position: Vec2)

  TouchScroll* = object
    ## Captures one finger gesture against the last displayed scroll regions.
    previous, current: seq[ScrollRegion]
    previousBlockers, currentBlockers: seq[TouchBlocker]
    start, last: Vec2
    target: pointer
    axis: int
    offset: float32
    coastPosition, coastVelocity, coastTime: float64
    coasting, consumeTap: bool
    pending, dragging, scrollbar, cancelled, invalidated, tap: bool
    suppress*, touchInput*: bool

proc scrollMilliseconds*(): float64 {.raises: [].} =
  ## Reads monotonic time without quantizing high-refresh animation frames.
  getMonoTime().ticks.float64 / 1_000_000

proc momentumActive*(touch: TouchScroll): bool =
  ## Reports whether another animation frame is needed after finger release.
  touch.coasting

proc stopMomentum(touch: var TouchScroll) =
  ## Releases an inertial target without changing its current scroll position.
  touch.coasting = false
  touch.coastVelocity = 0
  touch.target = nil

proc component(value: Vec2, axis: int): float32 =
  ## Selects a horizontal or vertical component.
  if axis == 0: value.x else: value.y

proc setComponent(value: var Vec2, axis: int, amount: float32) =
  ## Changes one component without moving the other axis.
  if axis == 0: value.x = amount
  else: value.y = amount

proc rebaseMomentum*(touch: var TouchScroll, target: pointer, position: Vec2) =
  ## Preserves velocity when content anchoring intentionally moves the viewport.
  if touch.coasting and touch.target == target:
    touch.coastPosition = component(position, touch.axis).float64

proc preferred(region, other: ScrollRegion): bool =
  ## Prefers the top layer and then the deepest nested scrollable widget.
  region.layer > other.layer or
    (region.layer == other.layer and region.depth >= other.depth)

proc trackHit(region: ScrollRegion, axis: int, point: Vec2): bool =
  ## Widens the invisible hit corridor inward while retaining clipping.
  if component(region.maximum, axis) <= 0:
    return false
  var hit = region.tracks[axis]
  if axis == 0:
    hit.y -= max(0.0'f, TouchScrollbarWidth - hit.h)
    hit.h = TouchScrollbarWidth
  else:
    hit.x -= max(0.0'f, TouchScrollbarWidth - hit.w)
    hit.w = TouchScrollbarWidth
  point.overlaps(hit) and point.overlaps(region.bounds) and
    point.overlaps(region.clip)

proc beginTouchFrame*(
  touch: var TouchScroll,
  isTouch, pressed, down, released, focused: bool,
  point, motion: Vec2,
  velocity: Vec2 = vec2(0),
  nowMs: float64 = scrollMilliseconds(),
  interrupted = false
) =
  ## Resolves ownership before widgets draw or virtualize their contents.
  touch.suppress = false
  touch.touchInput = isTouch
  touch.tap = false
  if not isTouch or not focused or point.x < 0 or point.y < 0 or interrupted:
    touch.pending = false
    touch.dragging = false
    touch.cancelled = false
    touch.consumeTap = false
    touch.stopMomentum()
    return
  if touch.cancelled:
    touch.suppress = true
    if released or not down:
      touch.cancelled = false
    return
  var barrier = 0
  let hitPoint = if pressed: point - motion else: touch.start
  if pressed:
    touch.consumeTap = false
    if touch.coasting:
      for region in touch.previous:
        if region.target == touch.target:
          touch.consumeTap = hitPoint.overlaps(region.bounds) and
            hitPoint.overlaps(region.clip)
          break
      touch.stopMomentum()
  elif touch.coasting:
    let elapsed = nowMs - touch.coastTime
    if elapsed < 0 or elapsed > MaximumFrameGap:
      touch.stopMomentum()
      return
    var found = false
    for region in touch.previous:
      if region.target != touch.target:
        continue
      found = true
      # Respect an application scroll jump instead of pulling it back.
      if component(region.position, touch.axis) != touch.coastPosition.float32:
        touch.stopMomentum()
        break
      let
        maximum = component(region.maximum, touch.axis).float64
        remainingMs = max(0.0, ln(ScrollStopSpeed /
          abs(touch.coastVelocity)) / ln(ScrollDeceleration))
        duration = min(elapsed, remainingMs)
        decay = pow(ScrollDeceleration, duration)
        # Preserves the projection Apple published in WWDC 2018 session 803.
        distance = touch.coastVelocity / 1000 * ScrollDeceleration /
          (1 - ScrollDeceleration) * (1 - decay)
        nextPosition = clamp(touch.coastPosition + distance, 0.0, maximum)
      var position = region.position
      position.setComponent(touch.axis, nextPosition.float32)
      region.apply(position)
      touch.coastPosition = nextPosition
      touch.coastVelocity *= decay
      touch.coastTime = nowMs
      touch.suppress = true
      if elapsed >= remainingMs or nextPosition <= 0 or
        nextPosition >= maximum:
          touch.stopMomentum()
      break
    if not found:
      touch.stopMomentum()
    return
  for blocker in touch.previousBlockers:
    if hitPoint.overlaps(blocker.bounds) and hitPoint.overlaps(blocker.clip):
      barrier = max(barrier, blocker.layer)
  if pressed:
    # Native motion excludes the initial jump to the finger-down position.
    touch.start = hitPoint
    touch.last = hitPoint
    touch.pending = true
    touch.dragging = false
    touch.scrollbar = false
    touch.target = nil
    var candidate = -1
    for i, region in touch.previous:
      for axis in 0 .. 1:
        if region.layer >= barrier and region.trackHit(axis, hitPoint) and
          (candidate < 0 or region.preferred(touch.previous[candidate])):
            candidate = i
            touch.axis = axis
    if candidate >= 0:
      let region = touch.previous[candidate]
      touch.target = region.target
      touch.scrollbar = true
      touch.dragging = true
      let thumb = region.thumbs[touch.axis]
      touch.offset =
        if component(hitPoint, touch.axis) >= component(thumb.xy, touch.axis) and
          component(hitPoint, touch.axis) <=
            component(thumb.xy + thumb.wh, touch.axis):
          component(hitPoint - thumb.xy, touch.axis)
        else:
          component(thumb.wh, touch.axis) / 2
  let distance = point - touch.start
  touch.suppress = touch.consumeTap and touch.pending
  if touch.pending and not touch.dragging and
    max(abs(distance.x), abs(distance.y)) >= TouchPanThreshold:
      touch.axis = if abs(distance.x) > abs(distance.y): 0 else: 1
      var candidate = -1
      for i, region in touch.previous:
        if region.layer >= barrier and
          component(region.maximum, touch.axis) > 0 and
          touch.start.overlaps(region.bounds) and
          touch.start.overlaps(region.clip) and
          (candidate < 0 or region.preferred(touch.previous[candidate])):
            candidate = i
      if candidate >= 0:
        touch.target = touch.previous[candidate].target
        touch.dragging = true
  if touch.dragging:
    touch.suppress = true
    for region in touch.previous:
      if region.target != touch.target:
        continue
      var position = region.position
      let maximum = component(region.maximum, touch.axis)
      if touch.scrollbar:
        let
          track = region.tracks[touch.axis]
          thumb = region.thumbs[touch.axis]
          travel = component(track.wh - thumb.wh, touch.axis)
        if travel > 0:
          var fraction = clamp(
            (component(point - track.xy, touch.axis) - touch.offset) / travel,
            0.0'f, 1.0'f
          )
          if component(region.signs, touch.axis) < 0:
            fraction = 1 - fraction
          position.setComponent(touch.axis, fraction * maximum)
      else:
        let delta = component(point - touch.last, touch.axis)
        position.setComponent(touch.axis, clamp(
          component(position, touch.axis) -
            component(region.signs, touch.axis) * delta,
          0.0'f, maximum
        ))
      region.apply(position)
      if released and not touch.scrollbar:
        let speed = -component(region.signs, touch.axis).float64 *
          component(velocity, touch.axis).float64
        if classify(speed) notin {fcNan, fcInf, fcNegInf} and
          abs(speed) >= MinimumFlingSpeed and
          ((speed > 0 and component(position, touch.axis) < maximum) or
            (speed < 0 and component(position, touch.axis) > 0)):
            touch.coasting = true
            touch.coastVelocity = speed
            touch.coastPosition = component(position, touch.axis).float64
            touch.coastTime = nowMs
      break
    touch.last = point
  if released or not down:
    touch.tap = touch.pending and not touch.dragging and not touch.consumeTap and
      max(abs(distance.x), abs(distance.y)) < TouchPanThreshold
    touch.pending = false
    touch.dragging = false
    touch.consumeTap = false
    if not touch.coasting:
      touch.target = nil

proc resetTouchScroll*(touch: var TouchScroll) =
  ## Invalidates scroll targets when the application replaces its scene.
  touch.cancelled = touch.pending or touch.dragging
  touch.pending = false
  touch.dragging = false
  touch.consumeTap = false
  touch.stopMomentum()
  touch.previous.setLen(0)
  touch.previousBlockers.setLen(0)
  touch.invalidated = true

proc touchTap*(sk: auto, bounds: Rect): bool =
  ## Accepts a touch release only in the control where the tap began.
  sk.touchScroll.tap and not sk.touchScrolling and
    (sk.touchScroll.start - sk.touchOrigin).overlaps(bounds)

proc endTouchFrame*(touch: var TouchScroll) =
  ## Retains displayed geometry and releases callbacks for vanished widgets.
  if touch.invalidated:
    touch.previous.setLen(0)
    touch.previousBlockers.setLen(0)
    touch.invalidated = false
  else:
    swap(touch.previous, touch.current)
    swap(touch.previousBlockers, touch.currentBlockers)
  touch.current.setLen(0)
  touch.currentBlockers.setLen(0)
  if touch.coasting:
    var found = false
    for region in touch.previous:
      if region.target == touch.target:
        found = true
        break
    if not found:
      touch.stopMomentum()

proc touchScrolling*(sk: auto): bool =
  ## Reports a captured pan or scrollbar, including its final release frame.
  sk.touchScroll.suppress

proc registerTouchBlocker*(sk: auto, bounds: Rect) =
  ## Keeps popup controls from passing gestures into lower visual layers.
  if sk.currentDrawLayer <= 0:
    return
  var blocker = TouchBlocker(
    bounds: bounds, clip: sk.clipRect, layer: sk.currentDrawLayer
  )
  blocker.bounds.x += sk.touchOrigin.x
  blocker.bounds.y += sk.touchOrigin.y
  blocker.clip.x += sk.touchOrigin.x
  blocker.clip.y += sk.touchOrigin.y
  sk.touchScroll.currentBlockers.add(blocker)

proc registerTouchScroll*(
  sk: auto,
  target: pointer,
  bounds: Rect,
  position, maximum, signs: Vec2,
  tracks, thumbs: array[2, Rect],
  depth: int,
  apply: proc(position: Vec2)
) =
  ## Registers a clipped scroll target in window coordinates, including insets.
  if (maximum.x <= 0 and maximum.y <= 0) or
    sk.mousePos.x <= -1000 or sk.mousePos.y <= -1000:
      return
  var region = ScrollRegion(
    target: target, bounds: bounds, clip: sk.clipRect,
    position: position, maximum: maximum, signs: signs,
    tracks: tracks, thumbs: thumbs,
    layer: sk.currentDrawLayer, depth: depth, apply: apply
  )
  region.bounds.x += sk.touchOrigin.x
  region.bounds.y += sk.touchOrigin.y
  region.clip.x += sk.touchOrigin.x
  region.clip.y += sk.touchOrigin.y
  for axis in 0 .. 1:
    region.tracks[axis].x += sk.touchOrigin.x
    region.tracks[axis].y += sk.touchOrigin.y
    region.thumbs[axis].x += sk.touchOrigin.x
    region.thumbs[axis].y += sk.touchOrigin.y
  sk.touchScroll.current.add(region)
