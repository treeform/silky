import
  std/tables,
  bumpy, chroma, pixie, vmath,
  silky/widgets as baseWidgets

when defined(silkyTesting):
  import silky/[semantics, testing, profiles]
else:
  import silky/[contexts, profiles]
  import windy

type
  DslNodeKind* = enum
    nkRoot
    nkFrame
    nkGroup
    nkRectangle
    nkText
    nkComponent
    nkInstance

  SizeMode* = enum
    ## Per-axis sizing (A8): when the length becomes known.
    smAuto  ## Legacy default: box/content size, else fill remaining.
    smFixed ## Known at begin: explicit pixels.
    smFill  ## Known at begin, iff the parent axis is known (T3).
    smHug   ## Known at close: children extent + padding (T2).

  PatchSpec* = object
    name*: string
    top*, right*, bottom*, left*: int

  DslNode* = ref object
    kind*: DslNodeKind
    id*: string
    boxRect*: Rect
    resolvedRect*: Rect
    hasBox*: bool
    resolved*: bool
    widthMode*: SizeMode
    heightMode*: SizeMode
    fixedSize*: Vec2
    centerXFlag*: bool
    centerYFlag*: bool
    scrollableFlag*: bool
    chromeMark*: int
    chromeLayer*: int
    materialized*: bool
    startedChildren*: bool
    pushedLayout*: bool
    pushedClip*: bool
    patch*: PatchSpec
    imageName*: string
    characters*: string
    fontName*: string
    tintColor*: ColorRGBX
    hasTint*: bool
    clipContent*: bool
    direction*: StackDirection
    horizontalPadding*: float32
    verticalPadding*: float32
    itemSpacing*: float32
    hAlign*: HorizontalAlignment
    vAlign*: VerticalAlignment
    frameState*: FrameState
    frameOrigin*: Vec2
    interactionResolved*: bool
    interaction*: Interaction
    semanticOpened*: bool
    semanticKind*: string
    semanticName*: string
    semanticText*: string
    semanticEnabled*: bool
    semanticFocused*: bool
    semanticPressed*: bool
    semanticHovered*: bool
    semanticChecked*: bool
    semanticValue*: string

var
  root*: DslNode
  parent*: DslNode
  current*: DslNode
  scopeStack*: seq[DslNode]
  dslNodePool: seq[DslNode]
  dslNodePoolUsed: int

proc dslVec2(v: SomeNumber): Vec2 {.inline.} =
  vec2(v.float32, v.float32)

proc dslVec2[A, B](x: A, y: B): Vec2 {.inline.} =
  vec2(x.float32, y.float32)

proc white(): ColorRGBX =
  rgbx(255, 255, 255, 255)

proc patchSpec(name: string, top, right, bottom, left: int): PatchSpec =
  PatchSpec(name: name, top: top, right: right, bottom: bottom, left: left)

proc patchSpec(name: string, border: int): PatchSpec =
  patchSpec(name, border, border, border, border)

proc defaultSemanticKind(node: DslNode): string =
  case node.kind
  of nkRoot: "Root"
  of nkFrame: "Frame"
  of nkGroup: "Group"
  of nkRectangle: "Rectangle"
  of nkText: "Text"
  of nkComponent: "Component"
  of nkInstance: "Instance"

proc nodeSemanticKind(node: DslNode): string =
  if node.semanticKind.len > 0:
    node.semanticKind
  else:
    node.defaultSemanticKind()

proc nodeSemanticName(node: DslNode): string =
  if node.semanticName.len > 0:
    node.semanticName
  else:
    node.id

proc nodeSemanticText(node: DslNode): string =
  if node.semanticText.len > 0:
    node.semanticText
  elif node.kind == nkText:
    node.characters
  else:
    ""

proc beginSemantic(sk: Silky, node: DslNode, r: Rect) =
  if node.kind == nkRoot or node.semanticOpened:
    return
  when defined(silkyTesting):
    sk.beginWidget(
      node.nodeSemanticKind(),
      node.nodeSemanticName(),
      node.nodeSemanticText(),
      r
    )
    sk.setWidgetState(
      enabled = node.semanticEnabled,
      focused = node.semanticFocused,
      pressed = node.semanticPressed,
      hovered = node.semanticHovered,
      checked = node.semanticChecked,
      value = node.semanticValue
    )
    node.semanticOpened = true
  else:
    discard sk
    discard r

proc endSemantic(sk: Silky, node: DslNode) =
  when defined(silkyTesting):
    if node != nil and node.semanticOpened:
      sk.endWidget()
      node.semanticOpened = false
  else:
    discard sk
    discard node

proc resetNodeRect*(node: DslNode) {.inline.} =
  if node != nil:
    node.resolved = false
    node.interactionResolved = false

proc resetDslNode(node: DslNode, sk: Silky, kind: DslNodeKind, id: string) {.measure.} =
  ## Resets a pooled node for reuse without allocating.
  node.kind = kind
  node.id = id
  node.boxRect = rect(0'f, 0'f, 0'f, 0'f)
  node.resolvedRect = rect(0'f, 0'f, 0'f, 0'f)
  node.hasBox = false
  node.resolved = false
  node.widthMode = smAuto
  node.heightMode = smAuto
  node.fixedSize = vec2(0, 0)
  node.centerXFlag = false
  node.centerYFlag = false
  node.scrollableFlag = false
  node.chromeMark = 0
  node.chromeLayer = 0
  node.materialized = false
  node.startedChildren = false
  node.pushedLayout = false
  node.pushedClip = false
  node.patch = PatchSpec()
  node.imageName = ""
  node.characters = ""
  node.fontName = sk.textStyle
  node.tintColor = white()
  node.hasTint = false
  node.clipContent = false
  node.direction = TopToBottom
  node.horizontalPadding = 0
  node.verticalPadding = 0
  node.itemSpacing = sk.theme.spacing.float32
  node.hAlign = LeftAlign
  node.vAlign = TopAlign
  node.frameState = nil
  node.frameOrigin = vec2(0)
  node.interactionResolved = false
  node.interaction = None
  node.semanticOpened = false
  node.semanticKind = ""
  node.semanticName = ""
  node.semanticText = ""
  node.semanticEnabled = true
  node.semanticFocused = false
  node.semanticPressed = false
  node.semanticHovered = false
  node.semanticChecked = false
  node.semanticValue = ""
  case kind
  of nkFrame:
    node.patch = patchSpec("frame.9patch", sk.theme.framePatch)
    node.clipContent = true
    node.horizontalPadding = sk.theme.padding.float32
    node.verticalPadding = sk.theme.padding.float32
  else:
    discard

proc acquireDslNode(sk: Silky, kind: DslNodeKind, id: string): DslNode {.measure.} =
  ## Returns a pooled DSL node, growing the pool only on first use.
  if dslNodePoolUsed < dslNodePool.len:
    result = dslNodePool[dslNodePoolUsed]
  else:
    result = DslNode()
    dslNodePool.add(result)
  inc dslNodePoolUsed
  result.resetDslNode(sk, kind, id)

proc beginDsl*(sk: Silky) {.measure.} =
  ## Starts a transient authoring stack for the current immediate frame.
  dslNodePoolUsed = 0
  scopeStack.setLen(0)
  root = acquireDslNode(sk, nkRoot, "root")
  root.resolvedRect = rect(dslVec2(0, 0), sk.rootSize)
  root.resolved = true
  root.materialized = true
  root.startedChildren = true
  scopeStack.add(root)
  parent = nil
  current = root

proc endDsl*(sk: Silky) {.measure.} =
  ## Clears the transient DSL stack. Pooled nodes are kept for reuse.
  discard sk
  scopeStack.setLen(0)
  dslNodePoolUsed = 0
  root = nil
  parent = nil
  current = nil

proc ensureDsl(sk: Silky) =
  if scopeStack.len == 0:
    sk.beginDsl()
  elif root != nil:
    root.resolvedRect = rect(dslVec2(0, 0), sk.rootSize)

proc nodeTint(sk: Silky, node: DslNode): ColorRGBX =
  if node.hasTint:
    node.tintColor
  elif node.kind == nkText:
    sk.theme.textColor
  else:
    white()

proc isHug(node: DslNode): bool {.inline.} =
  node.widthMode == smHug or node.heightMode == smHug

proc axisKnown(scope: LayoutScope, axis: int): bool {.inline.} =
  if axis == 0: scope.knownW else: scope.knownH

proc inferNodeSize(sk: Silky, node: DslNode): Vec2 =
  ## Resolves per-axis size by mode (A8). Hug axes stay 0 until the
  ## scope closes; fill inside an unknown axis degrades to 0 (T3).
  var
    content = vec2(0, 0)
    hasContent = false
  if node.characters.len > 0:
    content = sk.getTextSize(node.fontName, node.characters)
    hasContent = true
  elif node.imageName.len > 0:
    content = sk.getImageSize(node.imageName)
    hasContent = true
  let remaining = sk.currentScope.remainingSpace()
  for axis in 0 .. 1:
    let mode = if axis == 0: node.widthMode else: node.heightMode
    result[axis] =
      case mode
      of smFixed:
        node.fixedSize[axis]
      of smFill:
        when defined(silkyLayoutDebug):
          if not sk.currentScope.axisKnown(axis):
            echo "[silky] fill inside a hug parent is undefined (A8): ", node.id
        remaining[axis]
      of smHug:
        if node.kind == nkFrame:
          # Frames clip and scroll; their region must be known (T7).
          when defined(silkyLayoutDebug):
            echo "[silky] frames cannot hug; using fill: ", node.id
          remaining[axis]
        else:
          0.0'f
      of smAuto:
        if node.hasBox:
          node.boxRect.wh[axis]
        elif hasContent:
          content[axis]
        else:
          remaining[axis]

proc resolveNodeRect(sk: Silky, node: DslNode): Rect =
  if node.resolved:
    return node.resolvedRect
  let size = sk.inferNodeSize(node)
  var pos =
    if node.hasBox:
      sk.pos + node.boxRect.xy
    else:
      sk.currentScope.placedPos(size)
  if node.centerXFlag or node.centerYFlag:
    # T5: centering is plain arithmetic when both sizes are known.
    let scope = sk.currentScope
    if node.centerXFlag and scope.knownW and node.widthMode != smHug:
      pos.x = scope.regionPos.x + (scope.regionSize.x - size.x) * 0.5
    if node.centerYFlag and scope.knownH and node.heightMode != smHug:
      pos.y = scope.regionPos.y + (scope.regionSize.y - size.y) * 0.5
  node.resolvedRect = rect(pos, size)
  node.resolved = true
  node.resolvedRect

proc setInteractionState(node: DslNode, interaction: Interaction) =
  node.semanticHovered = interaction in [Pressed, Held, Released, Hovered]
  node.semanticPressed = interaction in [Pressed, Held]

proc nodeInteraction*(sk: Silky, node: DslNode, isEnabled = true, isError = false): Interaction {.inline.} =
  if node == nil or node.kind == nkRoot:
    return None
  if not node.interactionResolved:
    node.semanticEnabled = isEnabled
    let r = sk.resolveNodeRect(node)
    node.interaction = sk.interact(r, isEnabled, isError)
    node.setInteractionState(node.interaction)
    node.interactionResolved = true
  node.interaction

proc advanceDsl(sk: Silky, owner: DslNode, amount: Vec2) =
  let spacing =
    if owner != nil:
      owner.itemSpacing
    else:
      sk.theme.spacing.float32
  sk.advance(amount, spacing)

proc drawNodeVisual(sk: Silky, node: DslNode, r: Rect) =
  ## Emits the node's own pixels (chrome) at the given rect.
  let color = sk.nodeTint(node)
  if node.patch.name.len > 0:
    sk.draw9Patch(
      node.patch.name,
      node.patch.top,
      node.patch.right,
      node.patch.bottom,
      node.patch.left,
      r.xy,
      r.wh,
      color
    )
  if node.kind == nkRectangle and node.patch.name.len == 0 and
      node.imageName.len == 0 and node.characters.len == 0 and node.hasTint:
    sk.drawRect(r.xy, r.wh, color)
  if node.imageName.len > 0:
    sk.drawImage(node.imageName, r.xy, color)
  if node.characters.len > 0:
    discard sk.drawText(
      node.fontName,
      node.characters,
      r.xy,
      color,
      maxWidth = r.w,
      maxHeight = r.h,
      hAlign = node.hAlign,
      vAlign = node.vAlign
    )

proc drawNode(sk: Silky, node: DslNode, keepSemanticOpen: bool) {.measure.} =
  let r = sk.resolveNodeRect(node)
  sk.beginSemantic(node, r)
  sk.drawNodeVisual(node, r)
  node.materialized = true
  if not keepSemanticOpen:
    sk.endSemantic(node)

proc finishFrameScrollbars(sk: Silky, window: auto, node: DslNode) =
  ## T7: content size is |S - O| of the child scope — shift-invariant,
  ## so no scroll compensation is needed. The shared scrollbar proc
  ## handles origin-relative t, thumb resting edge, and wheel signs.
  let frameState = node.frameState
  if frameState == nil:
    return
  let
    contentSize = sk.currentScope.contentBox().wh + dslVec2(16)
    signs = sk.currentScope.signs
  baseWidgets.frameScrollbars(
    sk, window, frameState, node.resolvedRect, contentSize, signs
  )

proc pushChildrenLayout(sk: Silky, node: DslNode) =
  if node.pushedLayout:
    return
  if node.isHug and node.kind != nkFrame and not node.hasBox:
    # T2: chrome is deferred to close; children draw first while the
    # stretch pen measures them. Record where this span begins.
    when defined(silkyLayoutDebug):
      if node.scrollableFlag:
        echo "[silky] scrollable needs a known region, not hug (A8): ",
          node.id
    let r = sk.resolveNodeRect(node)
    sk.beginSemantic(node, r)
    node.chromeLayer = sk.currentDrawLayer
    node.chromeMark = sk.vertexMark()
    let
      childPos = r.xy + dslVec2(node.horizontalPadding, node.verticalPadding)
      childSize = dslVec2(
        max(0.0'f, r.w - node.horizontalPadding * 2),
        max(0.0'f, r.h - node.verticalPadding * 2)
      )
    sk.pushLayout(
      childPos,
      childSize,
      node.direction,
      knownW = node.widthMode != smHug,
      knownH = node.heightMode != smHug
    )
    node.pushedLayout = true
    return
  sk.drawNode(node, keepSemanticOpen = true)
  let r = node.resolvedRect
  if node.kind == nkFrame or node.scrollableFlag:
    if node.id notin frameStates:
      frameStates[node.id] = FrameState()
    node.frameState = frameStates[node.id]
    let clipRect = rect(r.x + 1, r.y + 1, max(0.0'f, r.w - 2), max(0.0'f, r.h - 2))
    sk.pushClipRect(clipRect)
    node.pushedClip = true
    node.frameOrigin = r.xy + dslVec2(node.horizontalPadding, node.verticalPadding)
    let childSize = dslVec2(
      max(0.0'f, r.w - node.horizontalPadding * 2),
      max(0.0'f, r.h - node.verticalPadding * 2)
    )
    # T7: scrolling translates the content by -σ·t, so the origin edge
    # is pinned at rest and overflow hides past the far edge.
    let
      signs = dirSigns(node.direction)
      scrollOffset = signs * node.frameState.scrollPos
    sk.pushLayout(node.frameOrigin - scrollOffset, childSize, node.direction)
  else:
    if node.clipContent:
      sk.pushClipRect(r)
      node.pushedClip = true
    let childPos = r.xy + dslVec2(node.horizontalPadding, node.verticalPadding)
    let childSize = dslVec2(
      max(0.0'f, r.w - node.horizontalPadding * 2),
      max(0.0'f, r.h - node.verticalPadding * 2)
    )
    sk.pushLayout(childPos, childSize, node.direction)
  node.pushedLayout = true

proc materializeNode(sk: Silky, node: DslNode, forChildren: bool) {.measure.} =
  if not node.materialized:
    if forChildren:
      sk.pushChildrenLayout(node)
    else:
      sk.drawNode(node, keepSemanticOpen = false)

proc startChildren(sk: Silky, node: DslNode) =
  if node == nil or node.kind == nkRoot or node.startedChildren:
    return
  node.startedChildren = true
  sk.pushChildrenLayout(node)

proc closeHugLayout(sk: Silky, node: DslNode) =
  ## Closes a hug scope: measure the content box, translate the span
  ## into final position (A6/T6), size the node, then emit its chrome
  ## behind the children (T2).
  let
    scope = sk.currentScope
    content = scope.contentBox()
    childPos = scope.regionPos
    signs = dirSigns(node.direction)
  sk.popLayout()
  var r = node.resolvedRect
  # The stretch pen includes one trailing item spacing per axis
  # (advancePen's legacy inflation); hug shouldn't.
  let extent = vec2(
    max(0.0'f, content.w - node.itemSpacing),
    max(0.0'f, content.h - node.itemSpacing)
  )
  var contentMin = content.xy
  if signs.x < 0:
    contentMin.x += min(node.itemSpacing, content.w)
  if signs.y < 0:
    contentMin.y += min(node.itemSpacing, content.h)
  if node.widthMode == smHug:
    r.w = extent.x + node.horizontalPadding * 2
  if node.heightMode == smHug:
    r.h = extent.y + node.verticalPadding * 2
  # Reverse-direction hug: children grew away from the provisional
  # origin; pull the whole rigid box back into place.
  var shift = vec2(0, 0)
  if node.widthMode == smHug:
    shift.x = childPos.x - contentMin.x
  if node.heightMode == smHug:
    shift.y = childPos.y - contentMin.y
  # The box's own position may move now that its size is known:
  # reverse-direction parents place against the pen (A3), centered
  # nodes re-center with the final size (T5).
  if not node.hasBox:
    var finalPos = sk.currentScope.placedPos(r.wh)
    let parentScope = sk.currentScope
    if node.centerXFlag and parentScope.knownW:
      finalPos.x = parentScope.regionPos.x +
        (parentScope.regionSize.x - r.w) * 0.5
    if node.centerYFlag and parentScope.knownH:
      finalPos.y = parentScope.regionPos.y +
        (parentScope.regionSize.y - r.h) * 0.5
    shift += finalPos - r.xy
    r.x = finalPos.x
    r.y = finalPos.y
  sk.translateVertices(node.chromeLayer, node.chromeMark, shift)
  node.resolvedRect = r
  node.resolved = true
  let chromeStart = sk.vertexMark()
  sk.drawNodeVisual(node, r)
  sk.moveVerticesBehind(node.chromeLayer, node.chromeMark, chromeStart)
  node.materialized = true
  when defined(silkyTesting):
    if node.semanticOpened:
      sk.setWidgetRect(r)
  sk.endSemantic(node)

proc closeChildrenLayout(sk: Silky, window: auto, node: DslNode) =
  if not node.pushedLayout:
    return
  if node.isHug and node.kind != nkFrame and not node.hasBox:
    sk.closeHugLayout(node)
    node.pushedLayout = false
    return
  if node.frameState != nil:
    sk.finishFrameScrollbars(window, node)
  sk.popLayout()
  if node.pushedClip:
    sk.popClipRect()
  sk.endSemantic(node)
  node.pushedLayout = false
  node.pushedClip = false

proc beginNode*(sk: Silky, kind: DslNodeKind, id: string) {.measure.} =
  sk.ensureDsl()
  let owner = scopeStack[^1]
  sk.startChildren(owner)
  parent = owner
  current = acquireDslNode(sk, kind, id)
  scopeStack.add(current)

proc finishNode*(sk: Silky, window: auto) {.measure.} =
  if scopeStack.len == 0:
    return
  let node = scopeStack[^1]
  if node.kind == nkRoot:
    return
  if not node.startedChildren:
    sk.materializeNode(node, forChildren = false)
  else:
    sk.closeChildrenLayout(window, node)
  let amount = node.resolvedRect.wh
  discard scopeStack.pop()
  if scopeStack.len > 0:
    current = scopeStack[^1]
    parent =
      if scopeStack.len > 1:
        scopeStack[^2]
      else:
        nil
    # T5: a node centered on the stack's main axis is a degenerate
    # scope; it does not advance the pen.
    let mainAxis = sk.stackDirection.mainAxis
    let centeredOnMain =
      (mainAxis == 0 and node.centerXFlag) or
      (mainAxis == 1 and node.centerYFlag)
    if not centeredOnMain:
      sk.advanceDsl(current, amount)
  else:
    current = nil
    parent = nil

proc scopeRect*(sk: Silky): Rect {.inline.} =
  ## Returns the current node rect, resolving it without retaining anything.
  if current == nil or current.kind == nkRoot:
    return rect(0'f, 0'f, 0'f, 0'f)
  sk.resolveNodeRect(current)

proc startCurrentChildren*(sk: Silky) {.inline.} =
  ## Lets direct immediate widgets participate inside the active DSL scope.
  if current != nil and current.kind != nkRoot:
    sk.startChildren(current)

template ui*(body: untyped) =
  ## Wraps a Silky frame in the transient Fidget-style authoring stack.
  sk.beginDsl()
  try:
    body
  finally:
    sk.endDsl()

template dslNode(kindValue: DslNodeKind, id: string, body: untyped) =
  sk.beginNode(kindValue, id)
  try:
    body
  finally:
    sk.finishNode(window)

template frame*(id: string, body: untyped) =
  dslNode(nkFrame, id, body)

template group*(id: string, body: untyped) =
  dslNode(nkGroup, id, body)

template rectangle*(id: string, body: untyped) =
  dslNode(nkRectangle, id, body)

template text*(id: string, body: untyped) =
  dslNode(nkText, id, body)

template component*(id: string, body: untyped) =
  dslNode(nkComponent, id, body)

template instance*(id: string, body: untyped) =
  dslNode(nkInstance, id, body)

proc box*[A, B, C, D: SomeNumber](x: A, y: B, w: C, h: D) {.inline.} =
  if current != nil:
    current.boxRect = rect(x.float32, y.float32, w.float32, h.float32)
    current.hasBox = true
    current.resetNodeRect()

proc box*(r: Rect) {.inline.} =
  if current != nil:
    current.boxRect = r
    current.hasBox = true
    current.resetNodeRect()

template box*[A, B: SomeNumber](w: A, h: B) =
  box(sk.at.x - sk.pos.x, sk.at.y - sk.pos.y, w, h)

proc font*(name: string) {.inline.} =
  if current != nil:
    current.fontName = name
    current.resetNodeRect()

proc characters*(value: string) {.inline.} =
  if current != nil:
    current.characters = value
    current.resetNodeRect()

proc setImage*(name: string) {.inline.} =
  if current != nil:
    current.imageName = name
    current.resetNodeRect()

proc semanticKind*(kind: string) {.inline.} =
  if current != nil:
    current.semanticKind = kind

proc semanticName*(name: string) {.inline.} =
  if current != nil:
    current.semanticName = name

proc semanticText*(text: string) {.inline.} =
  if current != nil:
    current.semanticText = text

proc semanticState*(
  enabled = true,
  focused = false,
  pressed = false,
  hovered = false,
  checked = false,
  value = ""
) {.inline.} =
  if current != nil:
    current.semanticEnabled = enabled
    current.semanticFocused = focused
    current.semanticPressed = pressed
    current.semanticHovered = hovered
    current.semanticChecked = checked
    current.semanticValue = value

template image*(imageName: string) =
  if current != nil and current.kind != nkRoot:
    setImage(imageName)
  else:
    baseWidgets.image(imageName)

template image*(imageName: string, imageTint: ColorRGBX) =
  if current != nil and current.kind != nkRoot:
    setImage(imageName)
    tint(imageTint)
  else:
    baseWidgets.image(imageName, imageTint)

proc width*(value: SomeNumber) {.inline.} =
  ## Fixed width in pixels (A8: known at begin).
  if current != nil:
    current.widthMode = smFixed
    current.fixedSize.x = value.float32
    current.resetNodeRect()

proc height*(value: SomeNumber) {.inline.} =
  ## Fixed height in pixels (A8: known at begin).
  if current != nil:
    current.heightMode = smFixed
    current.fixedSize.y = value.float32
    current.resetNodeRect()

proc size*[A, B: SomeNumber](w: A, h: B) {.inline.} =
  ## Fixed size in pixels; unlike box() the position still flows.
  width(w)
  height(h)

proc fillWidth*() {.inline.} =
  ## Take the parent's remaining width (T3: parent must be known).
  if current != nil:
    current.widthMode = smFill
    current.resetNodeRect()

proc fillHeight*() {.inline.} =
  ## Take the parent's remaining height (T3: parent must be known).
  if current != nil:
    current.heightMode = smFill
    current.resetNodeRect()

proc hugWidth*() {.inline.} =
  ## Width becomes the children's extent + padding at close (T2).
  if current != nil:
    current.widthMode = smHug
    current.resetNodeRect()

proc hugHeight*() {.inline.} =
  ## Height becomes the children's extent + padding at close (T2).
  if current != nil:
    current.heightMode = smHug
    current.resetNodeRect()

proc hug*() {.inline.} =
  ## Hug children on both axes (T2).
  hugWidth()
  hugHeight()

proc center*() {.inline.} =
  ## Center in the parent on both axes (T5: both sizes must be known).
  if current != nil:
    current.centerXFlag = true
    current.centerYFlag = true
    current.resetNodeRect()

proc centerX*() {.inline.} =
  if current != nil:
    current.centerXFlag = true
    current.resetNodeRect()

proc centerY*() {.inline.} =
  if current != nil:
    current.centerYFlag = true
    current.resetNodeRect()

template indent*(amount: SomeNumber, body: untyped) =
  ## T4: nudge the cross-axis start of children placed in this block.
  sk.startCurrentChildren()
  sk.currentScope.indent += amount.float32
  try:
    body
  finally:
    sk.currentScope.indent -= amount.float32

proc scrollable*(enabled = true) {.inline.} =
  ## T7: clip this node and scroll its overflow. Scrolling is a
  ## ramification of clipping, independent of sizing — legal on any
  ## node whose region is known (fixed or fill; not hug, A8).
  if current != nil:
    current.scrollableFlag = enabled

proc clipContent*(enabled = true) {.inline.} =
  if current != nil:
    current.clipContent = enabled

proc layout*(direction: StackDirection) {.inline.} =
  if current != nil:
    current.direction = direction

proc horizontalPadding*(value: SomeNumber) {.inline.} =
  if current != nil:
    current.horizontalPadding = value.float32

proc verticalPadding*(value: SomeNumber) {.inline.} =
  if current != nil:
    current.verticalPadding = value.float32

proc itemSpacing*(value: SomeNumber) {.inline.} =
  if current != nil:
    current.itemSpacing = value.float32

proc patch*(name: string) {.inline.} =
  if current != nil:
    if name.len == 0:
      current.patch = PatchSpec()
    else:
      current.patch = patchSpec(name, 0)

proc patch*(name: string, border: SomeInteger) {.inline.} =
  if current != nil:
    if name.len == 0:
      current.patch = PatchSpec()
    else:
      current.patch = patchSpec(name, border.int)

proc patch*(name: string, top, right, bottom, left: SomeInteger) {.inline.} =
  if current != nil:
    if name.len == 0:
      current.patch = PatchSpec()
    else:
      current.patch = patchSpec(name, top.int, right.int, bottom.int, left.int)

proc tint*(value: ColorRGBX) {.inline.} =
  if current != nil:
    current.tintColor = value
    current.hasTint = true

proc tint*(value: string) {.inline.} =
  tint(parseHtmlColor(value).rgbx)

proc textAlign*(hAlign: HorizontalAlignment, vAlign: VerticalAlignment = TopAlign) {.inline.} =
  if current != nil:
    current.hAlign = hAlign
    current.vAlign = vAlign

template onHover*(body: untyped) =
  block:
    let interaction = sk.nodeInteraction(current)
    if interaction in [Hovered, Pressed, Held, Released]:
      sk.hover = true
      body

template onDown*(body: untyped) =
  block:
    let interaction = sk.nodeInteraction(current)
    if interaction in [Pressed, Held]:
      sk.hover = true
      body

template onClick*(body: untyped) =
  block:
    let interaction = sk.nodeInteraction(current)
    if interaction == Released:
      sk.hover = true
      sk.mouseConsumed = true
      body

template onClickOutside*(body: untyped) =
  block:
    let eventRect = sk.scopeRect()
    if window.buttonReleased[MouseLeft] and not sk.mousePos.overlaps(eventRect):
      body

template text*(value: string) =
  if current != nil and current.kind != nkRoot:
    text("text:" & value):
      characters(value)
  else:
    baseWidgets.text(value)

template h1text*(value: string) =
  if current != nil and current.kind != nkRoot:
    text("h1:" & value):
      characters(value)
      font("H1")
      tint(sk.theme.textH1Color)
  else:
    baseWidgets.h1text(value)

template button*(label: string, isEnabled: bool, isError: bool, body: untyped) =
  profileBlock "button":
    sk.startCurrentChildren()
    baseWidgets.button(label, isEnabled, isError):
      body

template button*(label: string, body: untyped) =
  profileBlock "button":
    sk.startCurrentChildren()
    baseWidgets.button(label, true, false):
      body

template button*(label: string, isEnabled: bool, body: untyped) =
  profileBlock "button":
    sk.startCurrentChildren()
    baseWidgets.button(label, isEnabled, false):
      body

template icon*(imageName: string) =
  profileBlock "icon":
    sk.startCurrentChildren()
    baseWidgets.icon(imageName)

template iconButton*(imageName: string, body: untyped) =
  profileBlock "iconButton":
    sk.startCurrentChildren()
    baseWidgets.iconButton(imageName):
      body

template clickableIcon*(imageName: string, on: bool, body: untyped) =
  profileBlock "clickableIcon":
    sk.startCurrentChildren()
    baseWidgets.clickableIcon(imageName, on):
      body

template radioButton*[T](label: string, variable: var T, value: T) =
  profileBlock "radioButton":
    sk.startCurrentChildren()
    baseWidgets.radioButton(label, variable, value)

template checkBox*(label: string, value: var bool) =
  profileBlock "checkBox":
    sk.startCurrentChildren()
    baseWidgets.checkBox(label, value)

template progressBar*(value: SomeNumber, minVal: SomeNumber, maxVal: SomeNumber) =
  profileBlock "progressBar":
    sk.startCurrentChildren()
    baseWidgets.progressBar(value, minVal, maxVal)

template dropDown*[T](selected: var T, options: openArray[T]) =
  profileBlock "dropDown":
    sk.startCurrentChildren()
    baseWidgets.dropDown(selected, options)

template scrubber*[T, U](id: string, value: var T, minVal: T, maxVal: U, label: string = "") =
  profileBlock "scrubber":
    sk.startCurrentChildren()
    baseWidgets.scrubber(id, value, minVal, maxVal, label)

template listBox*[T](id: string, items: seq[T], selectedIndex: var int) =
  profileBlock "listBox":
    sk.startCurrentChildren()
    baseWidgets.listBox(id, items, selectedIndex)

template group*(p: Vec2, direction = TopToBottom, body: untyped) =
  group("group"):
    box(p.x, p.y, max(0.0'f, sk.size.x - p.x), max(0.0'f, sk.size.y - p.y))
    layout(direction)
    body

template frame*(id: string, framePos, frameSize: Vec2, body: untyped) =
  ## Absolute framePos/size, matching widgets.frame; box is parent-relative.
  frame(id):
    box(
      framePos.x - sk.pos.x,
      framePos.y - sk.pos.y,
      frameSize.x,
      frameSize.y
    )
    body

template frame*(p, s: Vec2, body: untyped) =
  ## Absolute p/s, matching widgets.frame; box is parent-relative.
  frame("frame"):
    box(p.x - sk.pos.x, p.y - sk.pos.y, s.x, s.y)
    body

template ribbon*(p, s: Vec2, ribbonTint: ColorRGBX, body: untyped) =
  ## Absolute p/s, matching widgets.ribbon; box is parent-relative.
  rectangle("ribbon"):
    box(p.x - sk.pos.x, p.y - sk.pos.y, s.x, s.y)
    tint(ribbonTint)
    body
