## The two-pen layout model. See docs/layout_theory.md.
##
## A layout scope carries the pen P (where the next element draws), the
## stretch pen S (the farthest corner reached), and a sign vector σ that
## points from the origin corner into the region (A1, A2). All direction
## math lives in placedPos/advancePen (A3-A5); nothing else moves a pen.

import bumpy, vmath

type
  StackDirection* = enum
    ## Direction of the current layout flow.
    TopToBottom
    BottomToTop
    LeftToRight
    RightToLeft

  LayoutScope* = object
    ## One layout region: origin corner, signs, and the two pens.
    regionPos*: Vec2       ## Region top-left, before direction is applied.
    regionSize*: Vec2      ## Region size; meaningless on axes not known.
    knownW*: bool = true   ## A8: is the width known right now?
    knownH*: bool = true   ## A8: is the height known right now?
    direction*: StackDirection
    signs*: Vec2           ## σ: +1/-1 per axis, points into the region.
    pen*: Vec2             ## P: the next element draws here.
    stretch*: Vec2         ## S: farthest corner reached, moves along σ.
    indent*: float32       ## T4: cross-axis offset for placed elements.
    vertexMark*: int       ## Vertex count at scope open, for hug chrome.
    vertexLayer*: int      ## Layer the scope opened on.

proc mainAxis*(direction: StackDirection): int =
  ## 0 = x, 1 = y.
  case direction
  of TopToBottom, BottomToTop: 1
  of LeftToRight, RightToLeft: 0

proc dirSigns*(direction: StackDirection): Vec2 =
  ## σ for a direction; the cross axis keeps its natural (+1) sign.
  case direction
  of TopToBottom: vec2(1, 1)
  of BottomToTop: vec2(1, -1)
  of LeftToRight: vec2(1, 1)
  of RightToLeft: vec2(-1, 1)

proc originCorner*(regionPos, regionSize, signs: Vec2): Vec2 =
  ## The corner σ points away from (A2).
  result = regionPos
  if signs.x < 0:
    result.x += regionSize.x
  if signs.y < 0:
    result.y += regionSize.y

proc origin*(scope: LayoutScope): Vec2 =
  ## O: where both pens started.
  originCorner(scope.regionPos, scope.regionSize, scope.signs)

proc initLayoutScope*(
  pos, size: Vec2,
  direction: StackDirection,
  knownW = true,
  knownH = true
): LayoutScope =
  let
    signs = dirSigns(direction)
    o = originCorner(pos, size, signs)
  LayoutScope(
    regionPos: pos,
    regionSize: size,
    knownW: knownW,
    knownH: knownH,
    direction: direction,
    signs: signs,
    pen: o,
    stretch: o
  )

proc farthest*(signs: Vec2, a, b: Vec2): Vec2 =
  ## Componentwise farthest point in the direction of σ.
  vec2(
    if signs.x >= 0: max(a.x, b.x) else: min(a.x, b.x),
    if signs.y >= 0: max(a.y, b.y) else: min(a.y, b.y)
  )

proc placedPos*(scope: LayoutScope, size: Vec2): Vec2 =
  ## A3: an element at the pen spans P .. P + σ·size; returns the box's
  ## top-left corner. Indent (T4) nudges the cross axis.
  var p = scope.pen
  let cross = 1 - scope.direction.mainAxis
  p[cross] += scope.signs[cross] * scope.indent
  vec2(
    if scope.signs.x >= 0: p.x else: p.x - size.x,
    if scope.signs.y >= 0: p.y else: p.y - size.y
  )

proc advancePen*(scope: var LayoutScope, size: Vec2, spacing: float32) =
  ## A4 + A5: move the pen along the main axis, absorb the far corner
  ## into the stretch pen. The stretch pen includes the trailing spacing
  ## on both axes to match the historical stretchAt behavior.
  let cross = 1 - scope.direction.mainAxis
  var far = scope.pen + scope.signs * (size + vec2(spacing, spacing))
  far[cross] += scope.signs[cross] * scope.indent
  scope.stretch = farthest(scope.signs, scope.stretch, far)
  let m = scope.direction.mainAxis
  scope.pen[m] += scope.signs[m] * (size[m] + spacing)

proc traveled*(scope: LayoutScope): Vec2 =
  ## How far the pen has moved from the origin, per axis (with indent).
  result = abs(scope.pen - scope.origin)
  let cross = 1 - scope.direction.mainAxis
  result[cross] += scope.indent

proc remainingSpace*(scope: LayoutScope): Vec2 =
  ## T3: region minus consumed space; only meaningful on known axes.
  max(scope.regionSize - scope.traveled, vec2(0, 0))

proc contentBox*(scope: LayoutScope): Rect =
  ## box(O, S): the exact bounding box of everything placed (T2, T7).
  let o = scope.origin
  rect(
    min(o.x, scope.stretch.x),
    min(o.y, scope.stretch.y),
    abs(scope.stretch.x - o.x),
    abs(scope.stretch.y - o.y)
  )
