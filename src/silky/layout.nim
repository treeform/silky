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

proc initLayout*(
  pos: Vec2,
  size: Vec2,
  direction: StackDirection = TopToBottom,
  anchor: Anchor = AnchorLeft
): Layout =
  ## Creates a new layout context with computed basis and stretch at start.
  var basisLayout = Layout(direction: direction, anchor: anchor)
  basisLayout.applyBasis()
  let
    startPos = pos + size * basisLayout.sizeSign
    mainDir = basisLayout.mainDir
    paddingDir = basisLayout.paddingDir
    sizeSign = basisLayout.sizeSign
  result = Layout(
    at: startPos,
    num: 0,
    pos: pos,
    size: size,
    direction: direction,
    anchor: anchor,
    stretchMin: startPos,
    stretchMax: startPos,
    mainDir: mainDir,
    paddingDir: paddingDir,
    sizeSign: sizeSign
  )

proc pushLayout*(stack: var seq[Layout], layout: Layout) =
  ## Pushes a full layout snapshot onto a stack.
  stack.add(layout)

proc popLayout*(stack: var seq[Layout]): Layout =
  ## Pops and returns one full layout snapshot from a stack.
  stack.pop()

proc layoutStart*(pos, size: Vec2, direction: StackDirection, anchor: Anchor): Vec2 =
  ## Returns the initial layout cursor after anchor growth is applied.
  var layout = Layout(direction: direction, anchor: anchor)
  layout.applyBasis()
  pos + size * layout.sizeSign

proc layoutPaddingOffset*(padding: Vec2, direction: StackDirection, anchor: Anchor): Vec2 =
  ## Returns the signed padding offset for the selected direction and anchor.
  var layout = Layout(direction: direction, anchor: anchor)
  layout.applyBasis()
  padding * layout.paddingDir

proc layoutWidgetPos*(at, widgetSize: Vec2, direction: StackDirection, anchor: Anchor): Vec2 =
  ## Returns the top-left draw position for a widget.
  var layout = Layout(at: at, direction: direction, anchor: anchor)
  layout.applyBasis()
  layout.at + widgetSize * layout.sizeSign * layout.paddingDir

proc layoutWidgetPos*(layout: Layout, widgetSize: Vec2): Vec2 =
  ## Returns the top-left draw position for a widget.
  layout.at + widgetSize * layout.sizeSign * layout.paddingDir

proc layoutAdvanceDelta*(amount: Vec2, direction: StackDirection, spacing: float32): Vec2 =
  ## Returns the cursor delta for one placed child.
  var layout = Layout(direction: direction, anchor: AnchorLeft)
  layout.applyBasis()
  (amount + vec2(spacing)) * layout.mainDir

proc advanceLayout*(layout: var Layout, amount: Vec2, spacing: float32) =
  ## Advances layout cursor and updates stretch bounds.
  layout.stretchMin = min(layout.stretchMin, layout.at)
  layout.stretchMax = max(layout.stretchMax, layout.at + amount + vec2(spacing))
  layout.at += (amount + vec2(spacing)) * layout.mainDir
  inc layout.num

proc includeRect*(minPos: var Vec2, maxPos: var Vec2, pos: Vec2, size: Vec2) =
  ## Expands min and max points to include one rectangle.
  minPos = min(minPos, pos)
  maxPos = max(maxPos, pos + size)

proc rectFromMinMax*(minPos, maxPos: Vec2): Rect =
  ## Builds a rectangle from min and max corner points.
  rect(minPos, maxPos - minPos)
