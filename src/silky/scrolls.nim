import vmath, bumpy

const
  TouchPanThreshold = 6.0'f
  TouchScrollbarWidth = 28.0'f

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
    pending, dragging, scrollbar, cancelled, invalidated, tap: bool
    suppress*, touchInput*: bool

proc component(value: Vec2, axis: int): float32 =
  ## Selects a horizontal or vertical component.
  if axis == 0: value.x else: value.y

proc setComponent(value: var Vec2, axis: int, amount: float32) =
  ## Changes one component without moving the other axis.
  if axis == 0: value.x = amount
  else: value.y = amount

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
  point, motion: Vec2
) =
  ## Resolves ownership before widgets draw or virtualize their contents.
  touch.suppress = false
  touch.touchInput = isTouch
  touch.tap = false
  if not isTouch or not focused or point.x < 0 or point.y < 0:
    touch.pending = false
    touch.dragging = false
    touch.cancelled = false
    touch.target = nil
    return
  if touch.cancelled:
    touch.suppress = true
    if released or not down:
      touch.cancelled = false
    return
  var barrier = 0
  let hitPoint = if pressed: point - motion else: touch.start
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
      break
    touch.last = point
  if released or not down:
    touch.tap = touch.pending and not touch.dragging and
      max(abs(distance.x), abs(distance.y)) < TouchPanThreshold
    touch.pending = false
    touch.dragging = false
    touch.target = nil

proc resetTouchScroll*(touch: var TouchScroll) =
  ## Invalidates scroll targets when the application replaces its scene.
  touch.cancelled = touch.pending or touch.dragging
  touch.pending = false
  touch.dragging = false
  touch.target = nil
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
