## Semantic capture layer for Silky UI testing.

import
  std/[algorithm, strutils, tables, unicode, times],
  vmath, bumpy, chroma, pixie,
  silky/[atlas, clips, layout], testwindow

from windy/common import Button, CursorKind, Cursor

export layout

const
  LineFeedRune = Rune(10)

type
  WidgetState* = object
    ## Stores the interactive state of a widget.
    enabled*: bool
    focused*: bool
    pressed*: bool
    hovered*: bool
    checked*: bool
    value*: string

  SemanticNode* = ref object
    ## Represents a single widget in the semantic tree.
    kind*: string
    name*: string
    text*: string
    rect*: Rect
    state*: WidgetState
    childIndex*: int
    children*: seq[SemanticNode]
    parent*: SemanticNode

  SemanticCapture* = object
    ## Captures the semantic structure of a UI frame.
    stack*: seq[SemanticNode]
    root*: SemanticNode
    frameNumber*: int
    previousSnapshot*: string

proc newSemanticNode*(kind: string, name = "", text = ""): SemanticNode =
  ## Creates a new semantic node with the given kind, name, and text.
  SemanticNode(
    kind: kind,
    name: name,
    text: text,
    state: WidgetState(enabled: true)
  )

proc currentNode*(capture: var SemanticCapture): SemanticNode =
  ## Returns the current node at the top of the stack, or root if empty.
  if capture.stack.len > 0:
    return capture.stack[^1]
  else:
    return capture.root

proc pushNode*(capture: var SemanticCapture, node: SemanticNode) =
  ## Adds a node as child of current node and pushes it onto the stack.
  let parent = capture.currentNode()
  node.childIndex = parent.children.len
  node.parent = parent
  parent.children.add(node)
  capture.stack.add(node)

proc popNode*(capture: var SemanticCapture) =
  ## Pops the current node from the stack.
  if capture.stack.len > 0:
    discard capture.stack.pop()

proc reset*(capture: var SemanticCapture) =
  ## Resets the capture state for a new frame.
  capture.root = newSemanticNode("Root")
  capture.stack = @[]
  inc capture.frameNumber

proc toText*(node: SemanticNode, indent: int = 0): string =
  ## Converts a semantic node tree to indented text format.
  let prefix = "  ".repeat(indent)
  let id = if node.name.len > 0: node.name else: $node.childIndex

  if node.kind == "Root":
    result = ""
    for child in node.children:
      result.add(child.toText(indent))
    return

  result.add(prefix & id & ":\n")
  result.add(prefix & "  type: " & node.kind & "\n")

  if node.text.len > 0:
    result.add(prefix & "  text: " & node.text & "\n")

  if node.rect.w > 0 or node.rect.h > 0:
    result.add(prefix & "  rect: " &
      $node.rect.x.int & " " & $node.rect.y.int & " " &
      $node.rect.w.int & " " & $node.rect.h.int & "\n")

  var stateStr = ""
  if node.state.enabled: stateStr.add("enabled ")
  if node.state.focused: stateStr.add("focused ")
  if node.state.pressed: stateStr.add("pressed ")
  if node.state.hovered: stateStr.add("hovered ")
  if node.state.checked: stateStr.add("checked ")
  if node.state.value.len > 0: stateStr.add("value:" & node.state.value & " ")

  if stateStr.len > 0:
    result.add(prefix & "  state: " & stateStr.strip() & "\n")

  if node.children.len > 0:
    result.add(prefix & "  children:\n")
    for child in node.children:
      result.add(child.toText(indent + 2))

proc toSnapshot*(capture: SemanticCapture): string =
  ## Converts the entire capture to a snapshot string.
  result = "frame: " & $capture.frameNumber & "\n"
  result.add(capture.root.toText(0))

proc pathOf*(node: SemanticNode): string =
  ## Returns the dot-separated path from root to this node.
  var parts: seq[string] = @[]
  var current = node
  while current != nil and current.kind != "Root":
    let id = if current.name.len > 0: current.name else: $current.childIndex
    parts.insert(id, 0)
    current = current.parent
  return parts.join(".")

proc findByPath*(node: SemanticNode, path: string): SemanticNode =
  ## Finds a node by its dot-separated path.
  if path.len == 0:
    return node
  let parts = path.split(".")
  var current = node
  for part in parts:
    if current == nil:
      return nil
    var found = false
    for child in current.children:
      let childId = if child.name.len > 0: child.name else: $child.childIndex
      if childId == part:
        current = child
        found = true
        break
    if not found:
      return nil
  return current

proc findByText*(node: SemanticNode, text: string, kind = ""): SemanticNode =
  ## Finds the first node with matching text and optional kind.
  if node.text == text:
    if kind.len == 0 or node.kind == kind:
      return node
  for child in node.children:
    let found = child.findByText(text, kind)
    if found != nil:
      return found
  return nil

proc findByName*(node: SemanticNode, name: string, kind = ""): SemanticNode =
  ## Finds the first node with matching name and optional kind.
  if node.name == name:
    if kind.len == 0 or node.kind == kind:
      return node
  for child in node.children:
    let found = child.findByName(name, kind)
    if found != nil:
      return found
  return nil

proc findAllByText*(node: SemanticNode, text: string, kind = ""): seq[SemanticNode] =
  ## Finds all nodes with matching text and optional kind.
  if node.text == text:
    if kind.len == 0 or node.kind == kind:
      result.add(node)

  for child in node.children:
    result.add(child.findAllByText(text, kind))

proc diff*(old, new: string): string =
  ## Computes a simple line-by-line diff between two strings.
  let oldLines = old.splitLines()
  let newLines = new.splitLines()

  var output: seq[string] = @[]
  var i, j = 0

  while i < oldLines.len or j < newLines.len:
    if i >= oldLines.len:
      output.add("+ " & newLines[j])
      inc j
    elif j >= newLines.len:
      output.add("- " & oldLines[i])
      inc i
    elif oldLines[i] == newLines[j]:
      inc i
      inc j
    else:
      output.add("- " & oldLines[i])
      output.add("+ " & newLines[j])
      inc i
      inc j

  if output.len == 0:
    return ""

  return output.join("\n")

const
  NormalLayer* = 0
  PopupsLayer* = 1

type
  Theme* = object
    ## Visual theme settings for widgets.
    padding*: int = 8
    menuPadding*: int = 2
    spacing*: int = 8
    border*: int = 10
    textPadding*: int = 4
    headerHeight*: int = 32
    windowPatch*: int = 14
    headerPatch*: int = 6
    framePatch*: int = 6
    buttonPatch*: int = 8
    dropdownPatch*: int = 6
    textboxPatch*: int = 6
    tooltipPatch*: int = 6
    scrollbarPatch*: int = 4
    scrollbarTrackPatch*: int = 4
    progressBarPatch*: int = 6
    scrubberPatch*: int = 4
    defaultTextColor*: ColorRGBX = rgbx(255, 255, 255, 255)
    disabledTextColor*: ColorRGBX = rgbx(150, 150, 150, 255)
    errorTextColor*: ColorRGBX = rgbx(255, 100, 100, 255)
    buttonHoverColor*: ColorRGBX = rgbx(255, 255, 255, 255)
    buttonDownColor*: ColorRGBX = rgbx(255, 255, 255, 255)
    iconButtonHoverColor*: ColorRGBX = rgbx(255, 255, 255, 255)
    iconButtonDownColor*: ColorRGBX = rgbx(255, 255, 255, 255)
    iconClickableUpColor*: ColorRGBX = rgbx(200, 200, 200, 200)
    iconClickableOnColor*: ColorRGBX = rgbx(255, 255, 255, 255)
    iconClickableHoverColor*: ColorRGBX = rgbx(255, 255, 255, 255)
    iconClickableOffColor*: ColorRGBX = rgbx(110, 110, 110, 110)
    dropdownHoverBgColor*: ColorRGBX = rgbx(220, 220, 240, 255)
    dropdownBgColor*: ColorRGBX = rgbx(255, 255, 255, 255)
    dropdownPopupBgColor*: ColorRGBX = rgbx(245, 245, 255, 255)
    textColor*: ColorRGBX = rgbx(255, 255, 255, 255)
    textH1Color*: ColorRGBX = rgbx(255, 255, 255, 255)
    frameFocusColor*: ColorRGBX = rgbx(220, 220, 255, 255)
    headerBgColor*: ColorRGBX = rgbx(30, 30, 40, 255)
    menuRootHoverColor*: ColorRGBX = rgbx(70, 70, 90, 255)
    menuItemHoverColor*: ColorRGBX = rgbx(70, 70, 90, 255)
    menuItemBgColor*: ColorRGBX = rgbx(40, 40, 50, 255)
    menuPopupHoverColor*: ColorRGBX = rgbx(80, 80, 100, 255)
    menuPopupSelectedColor*: ColorRGBX = rgbx(60, 60, 80, 255)

  SilkyVertex* {.packed.} = object
    ## Vertex data for GPU rendering.
    pos*: Vec2
    size*: Vec2
    uvPos*: array[2, uint16]
    uvSize*: array[2, uint16]
    color*: ColorRGBX
    clipPos*: Vec2
    clipSize*: Vec2

  Interactor* = object
    ## Solve which widget the mouse is interacting with.
    currentId*: int = -1
    warmId*: int = -1
    warmLayer*: int = -1
    hotId*: int = -1

  Silky* = ref object
    ## Main Silky context for testing mode without GPU.
    inFrame: bool = false
    uiScale*: float32 = 1.0
    ## Multiplies 9-patch borders for a denser atlas.
    sliceScale*: int = 1
    layoutStack*: seq[LayoutScope]
    textStyle*: string = "Default"
    padding*: float32 = 12
    theme*: Theme = Theme()
    cursor*: Cursor = Cursor(kind: ArrowCursor)
    inputRunes*: seq[Rune]
    mousePos*: Vec2
    mouseDelta*: Vec2
    mouseIdleTime*: float64
    mouseConsumed*: bool = false
    hover*: bool = false
    showTooltip*: bool = false
    tooltipActive*: bool = false
    tooltipPos*: Vec2
    tooltipAnchor*: Rect
    tooltipLastAnchor*: Rect
    tooltipOffset*: Vec2
    tooltipFadeInTime*: float64
    tooltipFadeInDuration*: float64 = 0.25
    framebufferSize*: IVec2
    lastMousePos*: Vec2
    tooltipThreshold*: float64 = 0.5
    atlas*: SilkyAtlas
    layers*: array[2, seq[SilkyVertex]]
    currentLayer*: int
    layerStack*: seq[int]
    clipStack: ClipStack
    frameStartTime*: float64
    frameTime*: float64
    avgFrameTime*: float64
    semantic*: SemanticCapture
    interactor*: Interactor
    window*: Window

proc currentDrawLayer*(sk: Silky): int =
  sk.currentLayer

proc pushLayer*(sk: Silky, layer: int) =
  ## Pushes a new rendering layer onto the stack.
  sk.layerStack.add(sk.currentLayer)
  sk.currentLayer = layer

proc popLayer*(sk: Silky) =
  ## Pops the current rendering layer from the stack.
  sk.currentLayer = sk.layerStack.pop()

proc currentScope*(sk: Silky): var LayoutScope =
  ## Returns the active layout scope.
  sk.layoutStack[^1]

proc at*(sk: Silky): var Vec2 =
  ## The pen P of the active scope.
  sk.layoutStack[^1].pen

proc `at=`*(sk: Silky, value: Vec2) =
  sk.layoutStack[^1].pen = value

proc stretchAt*(sk: Silky): var Vec2 =
  ## The stretch pen S of the active scope.
  sk.layoutStack[^1].stretch

proc `stretchAt=`*(sk: Silky, value: Vec2) =
  sk.layoutStack[^1].stretch = value

proc pushLayout*(
  sk: Silky,
  pos: Vec2,
  size: Vec2,
  direction: StackDirection = TopToBottom,
  knownW = true,
  knownH = true
) =
  ## Pushes a new layout region onto the stack.
  var scope = initLayoutScope(pos, size, direction, knownW, knownH)
  scope.vertexLayer = sk.currentLayer
  scope.vertexMark = sk.layers[scope.vertexLayer].len
  sk.layoutStack.add(scope)

proc popLayout*(sk: Silky) =
  ## Pops the current layout region, folding its stretch pen into the
  ## parent so overflow keeps propagating like the old global stretchAt.
  let child = sk.layoutStack.pop()
  if sk.layoutStack.len > 0:
    let parent = addr sk.layoutStack[^1]
    parent.stretch = farthest(parent.signs, parent.stretch, child.stretch)

proc pos*(sk: Silky): Vec2 =
  ## Returns the current layout position.
  sk.layoutStack[^1].regionPos

proc size*(sk: Silky): Vec2 =
  ## Returns the current layout size.
  sk.layoutStack[^1].regionSize

proc rootSize*(sk: Silky): Vec2 =
  ## Returns the root layout size.
  sk.layoutStack[0].regionSize

proc stackDirection*(sk: Silky): StackDirection =
  ## Returns the current stack direction.
  sk.layoutStack[^1].direction

proc vertexMark*(sk: Silky): int =
  ## Current vertex count on the active layer, for later patching.
  sk.layers[sk.currentLayer].len

proc beginVertexSpan*(sk: Silky): VertexSpan =
  ## Captures clip bounds while a semantic layout awaits placement.
  result.clipMark = sk.clipStack.regions.len
  inc sk.clipStack.captures

proc endVertexSpan*(sk: Silky, span: VertexSpan, offset: Vec2) =
  ## Places captured clip bounds without emitting GPU vertices.
  sk.clipStack.translateClips(span.clipMark, offset)
  dec sk.clipStack.captures

proc moveVerticesBehind*(sk: Silky, layer, spanStart, chromeStart: int) =
  ## Rotates vertices emitted after chromeStart to the front of the
  ## span so late-drawn parent chrome renders behind its children (T2).
  let total = sk.layers[layer].len
  if chromeStart > spanStart and chromeStart < total:
    sk.layers[layer].rotateLeft(
      spanStart ..< total, chromeStart - spanStart
    )

proc translateVertices*(sk: Silky, layer, spanStart: int, offset: Vec2) =
  ## Shifts vertices emitted since spanStart; realizes A6 for boxes
  ## whose position is only known at scope close (T6).
  if offset == vec2(0, 0):
    return
  for i in spanStart ..< sk.layers[layer].len:
    sk.layers[layer][i].pos += offset

proc pushRawClipRect*(sk: Silky, rect: Rect) =
  ## Pushes fixed clip bounds without intersection with ancestors.
  sk.clipStack.pushClip(rect, raw = true)

proc pushClipRect*(sk: Silky, rect: Rect) =
  ## Pushes local clip bounds intersected with the parent clip.
  sk.clipStack.pushClip(rect)

proc popClipRect*(sk: Silky) =
  ## Pops the current clip rectangle.
  sk.clipStack.popClip()

proc clipRect*(sk: Silky): Rect =
  ## Returns the current clip intersection.
  sk.clipStack.clipRect()

proc advance*(sk: Silky, amount: Vec2, spacing: float32) =
  ## Advances the current layout cursor with explicit spacing.
  sk.layoutStack[^1].advancePen(amount, spacing)

proc advance*(sk: Silky, amount: Vec2) =
  ## Advances the cursor position by the given amount.
  sk.advance(amount, sk.theme.spacing.float32)

proc placedAt*(sk: Silky, size: Vec2): Vec2 =
  ## Returns where a box of this size lands under the current scope
  ## (A3) without moving the pen. Pair with advance().
  sk.layoutStack[^1].placedPos(size)

proc place*(sk: Silky, size: Vec2): Vec2 =
  ## Places a box: returns its top-left corner and advances the pen.
  result = sk.placedAt(size)
  sk.advance(size)

proc getImageSize*(sk: Silky, image: string): Vec2 =
  ## Returns the size of an image from the atlas.
  if image notin sk.atlas.entries:
    return vec2(0, 0)
  let uv = sk.atlas.entries[image]
  vec2(uv.width.float32, uv.height.float32)

proc nextRune(text: string, i: var int): Rune {.inline.} =
  ## Reads one UTF-8 rune and advances the byte index.
  fastRuneAt(text, i, result, true)

proc peekRune(text: string, i: int, rune: var Rune): bool {.inline.} =
  ## Reads one UTF-8 rune without changing the caller's byte index.
  if i >= text.len:
    return false
  var j = i
  fastRuneAt(text, j, rune, true)
  true

proc getTextSize*(sk: Silky, font: string, text: string): Vec2 =
  ## Calculates the rendered size of text in a given font.
  if font notin sk.atlas.fonts:
    return vec2(0, 0)
  let fontData = sk.atlas.fonts[font]
  var
    i = 0
    currentPos = vec2(0, fontData.lineHeight)

  while i < text.len:
    let rune = text.nextRune(i)
    if rune == LineFeedRune:
      currentPos.x = 0
      currentPos.y += fontData.lineHeight
      continue

    var entry: ptr LetterEntry
    if not fontData.lookupLetter(rune, 0, entry):
      continue

    currentPos.x += entry.advance
    var next: Rune
    if text.peekRune(i, next):
      currentPos.x += fontData.lookupKerning(rune, next)

  return currentPos

proc contains*(sk: Silky, name: string): bool =
  ## Returns true if the atlas contains an entry with the given name.
  name in sk.atlas.entries

proc shouldShowTooltip*(sk: Silky): bool =
  ## Returns true if a tooltip should be displayed.
  sk.hover and sk.mouseIdleTime >= sk.tooltipThreshold

proc drawQuad*(sk: Silky, pos: Vec2, size: Vec2, uvPos: Vec2, uvSize: Vec2, color: ColorRGBX) {.inline.} =
  ## Stub for drawing a textured quad.
  discard

proc drawImage*(
  sk: Silky,
  name: string,
  pos: Vec2,
  color = rgbx(255, 255, 255, 255),
  mask = ""
) {.inline.} =
  ## Stub for drawing an image from the atlas.
  discard

proc drawRect*(sk: Silky, pos: Vec2, size: Vec2, color: ColorRGBX) {.inline.} =
  ## Stub for drawing a solid rectangle.
  discard

proc drawTriangle*(
  sk: Silky,
  positions: array[3, Vec2],
  uvs: array[3, Vec2],
  colors: array[3, ColorRGBX],
  clipPos = vec2(-1, -1),
  clipSize = vec2(-1, -1)
) {.inline.} =
  discard

proc drawRoundedImage*(
  sk: Silky,
  name: string,
  pos: Vec2,
  size: Vec2,
  radius: float32,
  color = rgbx(255, 255, 255, 255)
) {.inline.} =
  ## Stub for drawing an image with rounded corners.
  discard

proc draw9Patch*(sk: Silky, name: string, patch: int, pos: Vec2, size: Vec2, color = rgbx(255, 255, 255, 255)) {.inline.} =
  ## Stub for drawing a 9-patch image.
  discard

proc draw9Patch*(
  sk: Silky,
  name: string,
  top, right, bottom, left: int,
  pos: Vec2,
  size: Vec2,
  color = rgbx(255, 255, 255, 255)
) {.inline.} =
  ## Stub for drawing a 9-patch image with independent border sizes.
  discard

proc drawText*(
  sk: Silky,
  font: string,
  text: string,
  pos: Vec2,
  color: ColorRGBX,
  maxWidth = float32.high,
  maxHeight = float32.high,
  clip = true,
  wordWrap = false,
  hAlign: HorizontalAlignment = LeftAlign,
  vAlign: VerticalAlignment = TopAlign
): Vec2 =
  ## Stub for drawing text that returns the text size.
  sk.getTextSize(font, text)

proc clearScreen*(sk: Silky, color: ColorRGBX) {.inline.} =
  ## Stub for clearing the screen.
  discard

proc clear*(sk: Silky) =
  ## Clears all rendering layers.
  sk.layers[NormalLayer].setLen(0)
  sk.layers[PopupsLayer].setLen(0)
  sk.currentLayer = NormalLayer
  sk.layerStack.setLen(0)

proc instanceCount*(sk: Silky): int =
  ## Returns the number of render instances.
  return 0

proc newSilky*(window: Window, atlas: SilkyAtlas): Silky =
  ## Creates a new Silky context for testing from atlas data.
  result = Silky()
  result.atlas = atlas
  result.layers[NormalLayer] = @[]
  result.layers[PopupsLayer] = @[]
  result.currentLayer = NormalLayer
  result.layerStack = @[]
  result.window = window

proc newSilky*(window: Window, atlasPngPath: string): Silky =
  ## Creates a new Silky context for testing from a single atlas PNG.
  let atlas = readAtlasFromPng(atlasPngPath)
  newSilky(window, atlas)

proc beginUi*(sk: Silky, window: auto, size: IVec2) =
  ## Begins a new UI frame.
  sk.tooltipActive = sk.showTooltip
  sk.showTooltip = false
  sk.framebufferSize = size
  sk.mousePos = window.mousePos.vec2 / sk.uiScale
  sk.mouseDelta = window.mouseDelta.vec2 / sk.uiScale
  sk.pushLayout(vec2(0, 0), size.vec2 / sk.uiScale)
  sk.inFrame = true
  let currentTime = epochTime()
  sk.frameStartTime = currentTime
  sk.pushClipRect(rect(0, 0, sk.size.x, sk.size.y))
  sk.semantic.reset()

proc endInteractions(interactor: var Interactor) =
  ## Commit warm state and resets per-frame counters.
  interactor.hotId = interactor.warmId
  interactor.warmId = -1
  interactor.warmLayer = -1
  interactor.currentId = -1

proc resetInteractions*(sk: Silky) =
  ## Clear all interaction state.
  sk.interactor.hotId = -1

proc endUi*(sk: Silky) =
  ## Ends the current UI frame.
  sk.interactor.endInteractions()
  sk.clear()
  sk.popLayout()
  sk.popClipRect()
  sk.frameTime = epochTime() - sk.frameStartTime
  sk.avgFrameTime = (sk.avgFrameTime * 0.99) + (sk.frameTime * 0.01)
  sk.inputRunes.setLen(0)

template buttonDown*(sk: Silky): array[Button, bool] =
  sk.window.buttonDown

template buttonPressed*(sk: Silky): array[Button, bool] =
  sk.window.buttonPressed

template buttonReleased*(sk: Silky): array[Button, bool] =
  sk.window.buttonReleased

proc beginWidget*(sk: Silky, kind: string, name = "", text = "", rect = rect(0f, 0f, 0f, 0f)) {.inline.} =
  ## Begins a new semantic widget node.
  let node = newSemanticNode(kind, name, text)
  node.rect = rect
  sk.semantic.pushNode(node)

proc endWidget*(sk: Silky) {.inline.} =
  ## Ends the current semantic widget node.
  sk.semantic.popNode()

proc setWidgetState*(sk: Silky, enabled = true, focused = false, pressed = false,
                     hovered = false, checked = false, value = "") {.inline.} =
  ## Sets the state of the current widget node.
  let node = sk.semantic.currentNode()
  node.state.enabled = enabled
  node.state.focused = focused
  node.state.pressed = pressed
  node.state.hovered = hovered
  node.state.checked = checked
  node.state.value = value

proc setWidgetRect*(sk: Silky, rect: Rect) {.inline.} =
  ## Sets the bounding rectangle of the current widget node.
  let node = sk.semantic.currentNode()
  node.rect = rect

proc semanticSnapshot*(sk: Silky): string =
  ## Returns a snapshot of the current semantic tree.
  sk.semantic.toSnapshot()

proc semanticReset*(sk: Silky) =
  ## Resets the semantic capture state.
  sk.semantic.reset()

proc semanticEnabled*(sk: Silky): bool =
  ## Returns true if semantic capture is enabled.
  true
