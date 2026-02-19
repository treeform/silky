import
  vmath, bumpy,
  common

type
  LayoutBasis* = object
    ## Stores vectors used by the layout solver for one direction-anchor pair.
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

proc layoutBasis*(direction: StackDirection, anchor: Anchor): LayoutBasis =
  ## Returns the table-driven basis vectors for the given direction and anchor.
  let paddingDir = PaddingDirs[direction.ord][anchor.ord]
  result = LayoutBasis(
    mainDir: MainDirs[direction.ord],
    paddingDir: paddingDir,
    sizeSign: vec2(
      if paddingDir.x < 0: 1f else: 0f,
      if paddingDir.y < 0: 1f else: 0f
    )
  )

proc layoutStart*(pos, size: Vec2, direction: StackDirection, anchor: Anchor): Vec2 =
  ## Returns the initial layout cursor after anchor growth is applied.
  let basis = layoutBasis(direction, anchor)
  pos + size * basis.sizeSign

proc layoutPaddingOffset*(padding: Vec2, direction: StackDirection, anchor: Anchor): Vec2 =
  ## Returns the signed padding offset for the selected direction and anchor.
  let basis = layoutBasis(direction, anchor)
  padding * basis.paddingDir

proc layoutWidgetPos*(at, widgetSize: Vec2, direction: StackDirection, anchor: Anchor): Vec2 =
  ## Returns the top-left draw position for a widget.
  let basis = layoutBasis(direction, anchor)
  at + widgetSize * basis.sizeSign * basis.paddingDir

proc layoutAdvanceDelta*(amount: Vec2, direction: StackDirection, spacing: float32): Vec2 =
  ## Returns the cursor delta for one placed child.
  let basis = layoutBasis(direction, AnchorLeft)
  (amount + vec2(spacing)) * basis.mainDir

proc includeRect*(minPos: var Vec2, maxPos: var Vec2, pos: Vec2, size: Vec2) =
  ## Expands min and max points to include one rectangle.
  minPos = min(minPos, pos)
  maxPos = max(maxPos, pos + size)

proc rectFromMinMax*(minPos, maxPos: Vec2): Rect =
  ## Builds a rectangle from min and max corner points.
  rect(minPos, maxPos - minPos)
