import vmath, bumpy

type
  ScrollArea* = object
    ## Pure data for scroll state and geometry computation.
    scrollPos*: Vec2
    scrollingX*: bool
    scrollingY*: bool
    scrollDragOffset*: Vec2
    contentMin*: Vec2
    contentMax*: Vec2
    viewPos*: Vec2
    viewSize*: Vec2
    initialized*: bool

proc contentSize*(sa: ScrollArea): Vec2 =
  ## Return the total content extent.
  max(sa.contentMax - sa.contentMin, vec2(0))

proc scrollMax*(sa: ScrollArea): Vec2 =
  ## Return the maximum scroll offset before content runs out.
  max(sa.contentSize - sa.viewSize, vec2(0))

proc needsScrollX*(sa: ScrollArea): bool =
  ## True when content is wider than the viewport.
  sa.contentSize.x > sa.viewSize.x

proc needsScrollY*(sa: ScrollArea): bool =
  ## True when content is taller than the viewport.
  sa.contentSize.y > sa.viewSize.y

proc clampScroll*(sa: var ScrollArea) =
  ## Clamp scroll position to the valid range.
  let sm = sa.scrollMax
  if sm.y > 0:
    sa.scrollPos.y = clamp(sa.scrollPos.y, 0.0f, sm.y)
  else:
    sa.scrollPos.y = 0
  if sm.x > 0:
    sa.scrollPos.x = clamp(sa.scrollPos.x, 0.0f, sm.x)
  else:
    sa.scrollPos.x = 0

proc initScroll*(sa: var ScrollArea) =
  ## On the first frame with overflow, default to the far end for reversed anchors.
  if sa.initialized:
    return
  let sm = sa.scrollMax
  if sm.x <= 0 and sm.y <= 0:
    return
  sa.initialized = true
  if sa.contentMin.y < sa.viewPos.y:
    sa.scrollPos.y = sm.y
  if sa.contentMin.x < sa.viewPos.x:
    sa.scrollPos.x = sm.x

proc scrollOffset*(sa: ScrollArea): Vec2 =
  ## Return the translation to apply to content before drawing.
  result = -sa.scrollPos

proc applyWheel*(sa: var ScrollArea, delta: Vec2, speed: float32) =
  ## Apply scroll wheel input.
  let sm = sa.scrollMax
  if not sa.scrollingY and delta.y != 0:
    sa.scrollPos.y += delta.y * speed
    sa.scrollPos.y = clamp(sa.scrollPos.y, 0.0f, sm.y)
  if not sa.scrollingX and delta.x != 0:
    sa.scrollPos.x += delta.x * speed
    sa.scrollPos.x = clamp(sa.scrollPos.x, 0.0f, sm.x)

proc scrollBarY*(sa: ScrollArea): tuple[track: Rect, handle: Rect] =
  ## Compute vertical scrollbar track and handle rectangles.
  let track = rect(
    sa.viewPos.x + sa.viewSize.x - 10,
    sa.viewPos.y + 2,
    8,
    sa.viewSize.y - 4 - 10
  )
  let sm = sa.scrollMax
  let cs = sa.contentSize
  let posPercent = if sm.y > 0: sa.scrollPos.y / sm.y else: 0.0f
  let sizePercent = sa.viewSize.y / cs.y
  let handle = rect(
    track.x,
    track.y + (track.h - track.h * sizePercent) * posPercent,
    8,
    track.h * sizePercent
  )
  return (track, handle)

proc scrollBarX*(sa: ScrollArea): tuple[track: Rect, handle: Rect] =
  ## Compute horizontal scrollbar track and handle rectangles.
  let track = rect(
    sa.viewPos.x + 2,
    sa.viewPos.y + sa.viewSize.y - 10,
    sa.viewSize.x - 4 - 10,
    8
  )
  let sm = sa.scrollMax
  let cs = sa.contentSize
  let posPercent = if sm.x > 0: sa.scrollPos.x / sm.x else: 0.0f
  let sizePercent = sa.viewSize.x / cs.x
  let handle = rect(
    track.x + (track.w - track.w * sizePercent) * posPercent,
    track.y,
    track.w * sizePercent,
    8
  )
  return (track, handle)

proc dragScrollY*(sa: var ScrollArea, mouseY: float32) =
  ## Update scroll position from vertical scrollbar drag.
  let (track, handle) = sa.scrollBarY
  let relativeY = mouseY - sa.scrollDragOffset.y - track.y
  let available = track.h - handle.h
  if available > 0:
    let pct = clamp(relativeY / available, 0.0f, 1.0f)
    sa.scrollPos.y = pct * sa.scrollMax.y

proc dragScrollX*(sa: var ScrollArea, mouseX: float32) =
  ## Update scroll position from horizontal scrollbar drag.
  let (track, handle) = sa.scrollBarX
  let relativeX = mouseX - sa.scrollDragOffset.x - track.x
  let available = track.w - handle.w
  if available > 0:
    let pct = clamp(relativeX / available, 0.0f, 1.0f)
    sa.scrollPos.x = pct * sa.scrollMax.x

proc releaseIfUp*(sa: var ScrollArea, mouseDown: bool) =
  ## Release scrollbar drag when mouse button is up.
  if not mouseDown:
    sa.scrollingY = false
    sa.scrollingX = false
