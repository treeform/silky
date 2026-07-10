import
  std/tables,
  bumpy, chroma, pixie, vmath,
  silky/widgets as baseWidgets

when defined(silkyTesting):
  import silky/[semantic, testing]
else:
  import silky/contexts, windy

type
  DslNodeKind* = enum
    nkRoot
    nkFrame
    nkGroup
    nkRectangle
    nkText
    nkComponent
    nkInstance

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
  sk.beginWidget(node.nodeSemanticKind(), node.nodeSemanticName(), node.nodeSemanticText(), r)
  sk.setWidgetState(
    enabled = node.semanticEnabled,
    focused = node.semanticFocused,
    pressed = node.semanticPressed,
    hovered = node.semanticHovered,
    checked = node.semanticChecked,
    value = node.semanticValue
  )
  node.semanticOpened = true

proc endSemantic(sk: Silky, node: DslNode) =
  if node != nil and node.semanticOpened:
    sk.endWidget()
    node.semanticOpened = false

proc resetNodeRect*(node: DslNode) {.inline.} =
  if node != nil:
    node.resolved = false
    node.interactionResolved = false

proc resetDslNode(node: DslNode, sk: Silky, kind: DslNodeKind, id: string) =
  ## Resets a pooled node for reuse without allocating.
  node.kind = kind
  node.id = id
  node.boxRect = rect(0'f, 0'f, 0'f, 0'f)
  node.resolvedRect = rect(0'f, 0'f, 0'f, 0'f)
  node.hasBox = false
  node.resolved = false
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
    node.patch = patchSpec("frame.9patch", 6)
    node.clipContent = true
    node.horizontalPadding = sk.theme.padding.float32
    node.verticalPadding = sk.theme.padding.float32
  else:
    discard

proc acquireDslNode(sk: Silky, kind: DslNodeKind, id: string): DslNode =
  ## Returns a pooled DSL node, growing the pool only on first use.
  if dslNodePoolUsed < dslNodePool.len:
    result = dslNodePool[dslNodePoolUsed]
  else:
    result = DslNode()
    dslNodePool.add(result)
  inc dslNodePoolUsed
  result.resetDslNode(sk, kind, id)

proc beginDsl*(sk: Silky) =
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

proc endDsl*(sk: Silky) =
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

proc inferNodeSize(sk: Silky, node: DslNode, pos: Vec2): Vec2 =
  if node.hasBox:
    return node.boxRect.wh
  if node.characters.len > 0:
    return sk.getTextSize(node.fontName, node.characters)
  if node.imageName.len > 0:
    return sk.getImageSize(node.imageName)
  let used = pos - sk.pos
  dslVec2(max(0.0'f, sk.size.x - used.x), max(0.0'f, sk.size.y - used.y))

proc resolveNodeRect(sk: Silky, node: DslNode): Rect =
  if node.resolved:
    return node.resolvedRect
  let pos =
    if node.hasBox:
      sk.pos + node.boxRect.xy
    else:
      sk.at
  let size = sk.inferNodeSize(node, pos)
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
  sk.stretchAt = max(sk.stretchAt, sk.at + amount + dslVec2(spacing))
  case sk.stackDirection
  of TopToBottom:
    sk.at.y += amount.y + spacing
  of BottomToTop:
    sk.at.y -= amount.y + spacing
  of LeftToRight:
    sk.at.x += amount.x + spacing
  of RightToLeft:
    sk.at.x -= amount.x + spacing

proc drawNode(sk: Silky, node: DslNode, keepSemanticOpen: bool) =
  let r = sk.resolveNodeRect(node)
  let color = sk.nodeTint(node)
  sk.beginSemantic(node, r)
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
  node.materialized = true
  if not keepSemanticOpen:
    sk.endSemantic(node)

proc finishFrameScrollbars(sk: Silky, window: auto, node: DslNode) =
  let frameState = node.frameState
  if frameState == nil:
    return
  let r = node.resolvedRect
  if frameState.scrollingY and (window.buttonReleased[MouseLeft] or not window.buttonDown[MouseLeft]):
    frameState.scrollingY = false
  if frameState.scrollingX and (window.buttonReleased[MouseLeft] or not window.buttonDown[MouseLeft]):
    frameState.scrollingX = false

  sk.stretchAt += dslVec2(16)
  let contentSize = (sk.stretchAt + frameState.scrollPos) - node.frameOrigin
  let scrollMax = max(contentSize - r.wh, dslVec2(0, 0))

  if scrollMax.y > 0:
    frameState.scrollPos.y = clamp(frameState.scrollPos.y, 0.0, scrollMax.y)
  else:
    frameState.scrollPos.y = 0
  if scrollMax.x > 0:
    frameState.scrollPos.x = clamp(frameState.scrollPos.x, 0.0, scrollMax.x)
  else:
    frameState.scrollPos.x = 0

  if sk.mousePos.overlaps(r) and sk.mousePos.overlaps(sk.clipRect):
    if not frameState.scrollingY and window.scrollDelta.y != 0:
      frameState.scrollPos.y += window.scrollDelta.y * ScrollSpeed
      frameState.scrollPos.y = clamp(frameState.scrollPos.y, 0.0, scrollMax.y)
    if not frameState.scrollingX and window.scrollDelta.x != 0:
      frameState.scrollPos.x += window.scrollDelta.x * ScrollSpeed
      frameState.scrollPos.x = clamp(frameState.scrollPos.x, 0.0, scrollMax.x)

  if contentSize.y > r.h:
    let scrollbarTrackRect = rect(r.x + r.w - 10, r.y + 2, 8, r.h - 14)
    sk.draw9Patch("scrollbar.track.9patch", 4, scrollbarTrackRect.xy, scrollbarTrackRect.wh)
    let
      scrollPosPercent = if scrollMax.y > 0: frameState.scrollPos.y / scrollMax.y else: 0.0
      scrollSizePercent = r.h / contentSize.y
      scrollbarHandleRect = rect(
        scrollbarTrackRect.x,
        scrollbarTrackRect.y +
          (scrollbarTrackRect.h - scrollbarTrackRect.h * scrollSizePercent) *
          scrollPosPercent,
        8,
        scrollbarTrackRect.h * scrollSizePercent
      )
    if frameState.scrollingY:
      let relativeY = sk.mousePos.y - frameState.scrollDragOffset.y - scrollbarTrackRect.y
      let availableTrackHeight = scrollbarTrackRect.h - scrollbarHandleRect.h
      if availableTrackHeight > 0:
        let newScrollPosPercent = clamp(relativeY / availableTrackHeight, 0.0, 1.0)
        frameState.scrollPos.y = newScrollPosPercent * scrollMax.y
    elif sk.interact(scrollbarHandleRect, true) == Pressed:
      frameState.scrollingY = true
      frameState.scrollDragOffset.y = sk.mousePos.y - scrollbarHandleRect.y
    sk.draw9Patch("scrollbar.9patch", 4, scrollbarHandleRect.xy, scrollbarHandleRect.wh)

  if contentSize.x > r.w:
    let scrollbarTrackRect = rect(r.x + 2, r.y + r.h - 10, r.w - 14, 8)
    sk.draw9Patch("scrollbar.track.9patch", 4, scrollbarTrackRect.xy, scrollbarTrackRect.wh)
    let
      scrollPosPercent = if scrollMax.x > 0: frameState.scrollPos.x / scrollMax.x else: 0.0
      scrollSizePercent = r.w / contentSize.x
      scrollbarHandleRect = rect(
        scrollbarTrackRect.x +
          (scrollbarTrackRect.w - scrollbarTrackRect.w * scrollSizePercent) *
          scrollPosPercent,
        scrollbarTrackRect.y,
        scrollbarTrackRect.w * scrollSizePercent,
        8
      )
    if frameState.scrollingX:
      let relativeX = sk.mousePos.x - frameState.scrollDragOffset.x - scrollbarTrackRect.x
      let availableTrackWidth = scrollbarTrackRect.w - scrollbarHandleRect.w
      if availableTrackWidth > 0:
        let newScrollPosPercent = clamp(relativeX / availableTrackWidth, 0.0, 1.0)
        frameState.scrollPos.x = newScrollPosPercent * scrollMax.x
    elif sk.interact(scrollbarHandleRect, true) == Pressed:
      frameState.scrollingX = true
      frameState.scrollDragOffset.x = sk.mousePos.x - scrollbarHandleRect.x
    sk.draw9Patch("scrollbar.9patch", 4, scrollbarHandleRect.xy, scrollbarHandleRect.wh)

proc pushChildrenLayout(sk: Silky, node: DslNode) =
  if node.pushedLayout:
    return
  sk.drawNode(node, keepSemanticOpen = true)
  let r = node.resolvedRect
  if node.kind == nkFrame:
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
    sk.pushLayout(node.frameOrigin - node.frameState.scrollPos, childSize, node.direction)
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

proc materializeNode(sk: Silky, node: DslNode, forChildren: bool) =
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

proc closeChildrenLayout(sk: Silky, window: auto, node: DslNode) =
  if not node.pushedLayout:
    return
  if node.kind == nkFrame:
    sk.finishFrameScrollbars(window, node)
  sk.popLayout()
  if node.pushedClip:
    sk.popClipRect()
  sk.endSemantic(node)
  node.pushedLayout = false
  node.pushedClip = false

proc beginNode*(sk: Silky, kind: DslNodeKind, id: string) {.inline.} =
  sk.ensureDsl()
  let owner = scopeStack[^1]
  sk.startChildren(owner)
  parent = owner
  current = acquireDslNode(sk, kind, id)
  scopeStack.add(current)

proc finishNode*(sk: Silky, window: auto) {.inline.} =
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
  block:
    sk.startCurrentChildren()
    baseWidgets.button(label, isEnabled, isError):
      body

template button*(label: string, body: untyped) =
  block:
    sk.startCurrentChildren()
    baseWidgets.button(label, true, false):
      body

template button*(label: string, isEnabled: bool, body: untyped) =
  block:
    sk.startCurrentChildren()
    baseWidgets.button(label, isEnabled, false):
      body

template icon*(imageName: string) =
  block:
    sk.startCurrentChildren()
    baseWidgets.icon(imageName)

template iconButton*(imageName: string, body: untyped) =
  block:
    sk.startCurrentChildren()
    baseWidgets.iconButton(imageName):
      body

template clickableIcon*(imageName: string, on: bool, body: untyped) =
  block:
    sk.startCurrentChildren()
    baseWidgets.clickableIcon(imageName, on):
      body

template radioButton*[T](label: string, variable: var T, value: T) =
  block:
    sk.startCurrentChildren()
    baseWidgets.radioButton(label, variable, value)

template checkBox*(label: string, value: var bool) =
  block:
    sk.startCurrentChildren()
    baseWidgets.checkBox(label, value)

template progressBar*(value: SomeNumber, minVal: SomeNumber, maxVal: SomeNumber) =
  block:
    sk.startCurrentChildren()
    baseWidgets.progressBar(value, minVal, maxVal)

template dropDown*[T](selected: var T, options: openArray[T]) =
  block:
    sk.startCurrentChildren()
    baseWidgets.dropDown(selected, options)

template scrubber*[T, U](id: string, value: var T, minVal: T, maxVal: U, label: string = "") =
  block:
    sk.startCurrentChildren()
    baseWidgets.scrubber(id, value, minVal, maxVal, label)

template listBox*[T](id: string, items: seq[T], selectedIndex: var int) =
  block:
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
