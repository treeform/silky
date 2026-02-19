import
  vmath, bumpy,
  common

type
  Layout* = object
    ## Stores the current layout context.
    at*: Vec2
    num*: int
    pos*: Vec2
    size*: Vec2
    direction*: StackDirection
    anchor*: Anchor
    stretchMax*: Vec2
    stretchMin*: Vec2

    # Layout basis vectors.
    mainDir*: Vec2
    paddingDir*: Vec2
    sizeSign*: Vec2

const
  MainDirs = [
    vec2(0, 1),
    vec2(0, -1),
    vec2(1, 0),
    vec2(-1, 0)
  ]
  PaddingDirs = [
    [vec2(1, 1), vec2(-1, 1), vec2(0, 0), vec2(0, 0)],
    [vec2(1, -1), vec2(-1, -1), vec2(0, 0), vec2(0, 0)],
    [vec2(0, 0), vec2(0, 0), vec2(1, 1), vec2(1, -1)],
    [vec2(0, 0), vec2(0, 0), vec2(-1, 1), vec2(-1, -1)]
  ]

proc applyBasis(layout: var Layout) =
  ## Computes and stores basis vectors inside one layout context.
  layout.mainDir = MainDirs[layout.direction.ord]
  layout.paddingDir = PaddingDirs[layout.direction.ord][layout.anchor.ord]
  layout.sizeSign = vec2(
    if layout.paddingDir.x < 0: 1f else: 0f,
    if layout.paddingDir.y < 0: 1f else: 0f
  )

proc init*(
  layout: var Layout,
  pos: Vec2,
  size: Vec2,
  direction: StackDirection = TopToBottom,
  anchor: Anchor = AnchorLeft
)=
  ## Creates a new layout context with computed basis and stretch at start.
  layout = Layout(
    pos: pos,
    size: size,
    direction: direction,
    anchor: anchor
  )
  layout.applyBasis()
  let startPos = layout.pos + layout.size * layout.sizeSign
  layout.at = startPos
  layout.num = 0
  layout.stretchMin = startPos
  layout.stretchMax = startPos

proc newLayout*(
  pos: Vec2,
  size: Vec2,
  direction: StackDirection = TopToBottom,
  anchor: Anchor = AnchorLeft
): Layout =
  ## Creates and returns a fully initialized layout context.
  result.init(pos, size, direction, anchor)

proc start*(layout: Layout): Vec2 =
  ## Returns the initial layout cursor after anchor growth is applied.
  layout.pos + layout.size * layout.sizeSign

proc paddingOffset*(layout: Layout, padding: Vec2): Vec2 =
  ## Returns the signed padding offset for this layout.
  padding * layout.paddingDir

proc widgetPos*(layout: Layout, widgetSize: Vec2): Vec2 =
  ## Returns the top-left draw position for a widget.
  layout.at + widgetSize * layout.sizeSign * layout.paddingDir

proc advanceDelta*(layout: Layout, amount: Vec2, spacing: float32): Vec2 =
  ## Returns the cursor delta for one placed child.
  (amount + vec2(spacing)) * layout.mainDir

proc advance*(layout: var Layout, amount: Vec2, spacing: float32) =
  ## Advances layout cursor and updates stretch bounds.
  layout.stretchMin = min(layout.stretchMin, layout.at)
  layout.stretchMax = max(layout.stretchMax, layout.at + amount + vec2(spacing))
  layout.at += layout.advanceDelta(amount, spacing)
  inc layout.num

proc includeRect*(minPos: var Vec2, maxPos: var Vec2, pos: Vec2, size: Vec2) =
  ## Expands min and max points to include one rectangle.
  minPos = min(minPos, pos)
  maxPos = max(maxPos, pos + size)

proc rectFromMinMax*(minPos, maxPos: Vec2): Rect =
  ## Builds a rectangle from min and max corner points.
  rect(minPos, maxPos - minPos)
