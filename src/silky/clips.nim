import bumpy, vmath

type
  ClipRegion* = object
    ## Original bounds and their intersection with an optional parent.
    bounds*: Rect
    visible*: Rect
    parent*: int
    fixed*: bool

  ClipStack* = object
    ## Clip history retained until the current frame ends.
    regions*: seq[ClipRegion]
    stack*: seq[int]
    captures*: int

  VertexSpan* = object
    ## Vertex and clip boundaries for a deferred layout on both layers.
    marks*: array[2, int]
    clipMark*: int

proc intersectClips(a, b: Rect): Rect =
  ## Intersects clip bounds while keeping empty intersections empty.
  let
    x = max(a.x, b.x)
    y = max(a.y, b.y)
  rect(
    x,
    y,
    max(0.0'f, min(a.x + a.w, b.x + b.w) - x),
    max(0.0'f, min(a.y + a.h, b.y + b.h) - y)
  )

proc addClip*(
  clips: var ClipStack,
  bounds: Rect,
  parent = -1,
  fixed = false
): int =
  ## Records original clip bounds before intersecting them.
  result = clips.regions.len
  let visible =
    if parent >= 0:
      intersectClips(clips.regions[parent].visible, bounds)
    else:
      bounds
  clips.regions.add(ClipRegion(
    bounds: bounds,
    visible: visible,
    parent: parent,
    fixed: fixed
  ))

proc pushClip*(clips: var ClipStack, bounds: Rect, raw = false) =
  ## Pushes a local clip or a fixed clip that bypasses its ancestors.
  let
    parent =
      if not raw and clips.stack.len > 0:
        clips.stack[^1]
      else:
        -1
    index = clips.addClip(bounds, parent, fixed = raw)
  clips.stack.add(index)

proc popClip*(clips: var ClipStack) =
  ## Removes the active clip while retaining bounds for deferred draws.
  let index = clips.stack.pop()
  if clips.captures == 0:
    clips.regions.setLen(index)

proc clipRect*(clips: ClipStack): Rect =
  ## Returns the active intersection for drawing and interaction.
  clips.regions[clips.stack[^1]].visible

proc translateClips*(clips: var ClipStack, first: int, offset: Vec2) =
  ## Moves local clips, then intersects them with their final ancestors.
  for i in first ..< clips.regions.len:
    if not clips.regions[i].fixed:
      clips.regions[i].bounds.x += offset.x
      clips.regions[i].bounds.y += offset.y
    let parent = clips.regions[i].parent
    clips.regions[i].visible =
      if parent >= 0:
        intersectClips(
          clips.regions[parent].visible,
          clips.regions[i].bounds
        )
      else:
        clips.regions[i].bounds
