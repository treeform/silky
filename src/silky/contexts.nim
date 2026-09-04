import
  std/[algorithm, tables, unicode, times],
  pixie, vmath, windy, bumpy,
  silky/[atlas, clips, layout, profiles]

export layout, profiles

when defined(useDirectX):
  import silky/drawers/dx12
elif defined(useVulkan):
  import silky/drawers/vk14
elif defined(useMetal4):
  import silky/drawers/metal4
elif defined(useCpu):
  import silky/drawers/cpu
else:
  import opengl
  import silky/drawers/ogl


const
  NormalLayer* = 0
  PopupsLayer* = 1
  LineFeedRune = Rune(10)
  SpaceRune = Rune(32)

type
  Theme* = object
    ## Theme for the Silky UI.
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

  Interactor* = object
    ## Solve which widget the mouse is interacting with.
    currentId*: int = -1
    warmId*: int = -1
    warmLayer*: int = -1
    hotId*: int = -1

  Silky* = ref object
    ## Main Silky context shared across rendering backends.
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
    tooltipThreshold*: float64 = 0
    atlas*: SilkyAtlas
    image*: Image
    ## Live packer for runtime atlas extension; nil until first add.
    builder*: AtlasBuilder
    drawer*: Drawer
    clipStack: ClipStack
    vertexClips: array[2, seq[int]]
    frameStartTime*: float64
    frameTime*: float64
    avgFrameTime*: float64
    interactor*: Interactor
    window: Window

proc currentDrawLayer*(sk: Silky): int =
  sk.drawer.currentLayer

proc pushLayer*(sk: Silky, layer: int) =
  ## Pushes a new rendering layer onto the stack.
  sk.drawer.layerStack.add(sk.drawer.currentLayer)
  sk.drawer.currentLayer = layer

proc popLayer*(sk: Silky) =
  ## Pops the current rendering layer from the stack.
  sk.drawer.currentLayer = sk.drawer.layerStack.pop()

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
  scope.vertexLayer = sk.drawer.currentLayer
  scope.vertexMark = sk.drawer.layers[scope.vertexLayer].len
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

proc instanceCount*(sk: Silky): int =
  ## Returns the number of queued drawer vertices.
  for i in 0 ..< sk.drawer.layers.len:
    result += sk.drawer.layers[i].len

proc advance*(sk: Silky, amount: Vec2, spacing: float32) =
  ## Advances the current layout cursor with explicit spacing.
  sk.layoutStack[^1].advancePen(amount, spacing)

proc advance*(sk: Silky, amount: Vec2) =
  ## Advances the current layout cursor.
  sk.advance(amount, sk.theme.spacing.float32)

proc placedAt*(sk: Silky, size: Vec2): Vec2 =
  ## Returns where a box of this size lands under the current scope
  ## (A3) without moving the pen. Pair with advance().
  sk.layoutStack[^1].placedPos(size)

proc place*(sk: Silky, size: Vec2): Vec2 =
  ## Places a box: returns its top-left corner and advances the pen.
  result = sk.placedAt(size)
  sk.advance(size)

proc vertexMark*(sk: Silky): int =
  ## Current vertex count on the active layer, for later patching.
  sk.drawer.layers[sk.drawer.currentLayer].len

proc beginVertexSpan*(sk: Silky): VertexSpan =
  ## Captures vertices and original clips until a layout is placed.
  result.clipMark = sk.clipStack.regions.len
  for layer in 0 ..< result.marks.len:
    result.marks[layer] = sk.drawer.layers[layer].len
    sk.vertexClips[layer].setLen(result.marks[layer])
  inc sk.clipStack.captures

proc endVertexSpan*(sk: Silky, span: VertexSpan, offset: Vec2) =
  ## Places a deferred span and resolves clips against fixed ancestors.
  sk.clipStack.translateClips(span.clipMark, offset)
  for layer in 0 ..< span.marks.len:
    for i in span.marks[layer] ..< sk.drawer.layers[layer].len:
      let clip = sk.clipStack.regions[sk.vertexClips[layer][i]].visible
      sk.drawer.layers[layer][i].pos += offset
      sk.drawer.layers[layer][i].clipPos = clip.xy
      sk.drawer.layers[layer][i].clipSize = clip.wh
  dec sk.clipStack.captures

proc moveVerticesBehind*(sk: Silky, layer, spanStart, chromeStart: int) =
  ## Rotates vertices emitted after chromeStart to the front of the
  ## span so late-drawn parent chrome renders behind its children (T2).
  let total = sk.drawer.layers[layer].len
  if chromeStart > spanStart and chromeStart < total:
    sk.drawer.layers[layer].rotateLeft(
      spanStart ..< total, chromeStart - spanStart
    )
    if sk.clipStack.captures > 0:
      sk.vertexClips[layer].rotateLeft(
        spanStart ..< total, chromeStart - spanStart
      )

proc translateVertices*(sk: Silky, layer, spanStart: int, offset: Vec2) =
  ## Shifts vertices emitted since spanStart; realizes A6 for boxes
  ## whose position is only known at scope close (T6).
  if offset == vec2(0, 0):
    return
  for i in spanStart ..< sk.drawer.layers[layer].len:
    sk.drawer.layers[layer][i].pos += offset

proc getImageSize*(sk: Silky, image: string): Vec2 =
  ## Returns the size of an atlas image in pixels.
  if image notin sk.atlas.entries:
    echo "[Warning] Image not found in atlas: " & image
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

proc shouldShowTooltip*(sk: Silky): bool =
  ## Returns true when a tooltip should be shown.
  sk.hover and sk.mouseIdleTime >= sk.tooltipThreshold

proc resetInteractions*(sk: Silky) =
  ## Clear all interaction state.
  sk.interactor.hotId = -1
  sk.interactor.warmId = -1
  sk.interactor.warmLayer = -1

proc beginUiShared*(sk: Silky, window: Window, size: IVec2) =
  ## Starts a frame and updates the shared UI state.
  beginProfileFrame()

  sk.tooltipActive = sk.showTooltip
  sk.showTooltip = false
  sk.mouseConsumed = false
  sk.framebufferSize = size
  sk.pushLayout(vec2(0, 0), size.vec2 / sk.uiScale)
  sk.inFrame = true

  let
    currentTime = epochTime()
    deltaTime = currentTime - sk.frameStartTime
    currentMousePos = window.mousePos.vec2 / sk.uiScale
  sk.frameStartTime = currentTime
  sk.mousePos = currentMousePos
  sk.mouseDelta = window.mouseDelta.vec2 / sk.uiScale

  if currentMousePos != sk.lastMousePos:
    sk.mouseIdleTime = 0
    sk.lastMousePos = currentMousePos
  else:
    sk.mouseIdleTime += deltaTime

  if sk.tooltipActive:
    sk.tooltipFadeInTime += deltaTime
  else:
    sk.tooltipFadeInTime = 0

  measurePush("frame")
  sk.pushClipRect(rect(0, 0, sk.size.x, sk.size.y))

proc clear*(sk: Silky)

proc endInteractions(interactor: var Interactor) =
  ## Commit warm state and resets per-frame counters.
  interactor.hotId = interactor.warmId
  interactor.warmId = -1
  interactor.warmLayer = -1
  interactor.currentId = -1

proc endUiShared*(sk: Silky) =
  ## Ends a frame after the backend has finished drawing.
  if sk.window.buttonReleased[MouseLeft]:
    sk.resetInteractions()
  sk.interactor.endInteractions()
  sk.clear()
  sk.popLayout()
  sk.popClipRect()
  sk.frameTime = epochTime() - sk.frameStartTime
  sk.avgFrameTime = (sk.avgFrameTime * 0.99) + (sk.frameTime * 0.01)
  sk.inputRunes.setLen(0)
  sk.inFrame = false
  measurePop()
  endProfileFrame()

proc recordVertexClip(
  sk: Silky,
  layer, count: int,
  bounds: Rect,
  inherited: bool
) =
  ## Records clip ownership only while a layout awaits placement.
  if sk.clipStack.captures == 0:
    return
  let index =
    if inherited:
      sk.clipStack.stack[^1]
    else:
      sk.clipStack.addClip(bounds)
  for i in 0 ..< count:
    sk.vertexClips[layer].add(index)

proc drawQuad*(
  sk: Silky,
  pos: Vec2,
  size: Vec2,
  uvPos: Vec2,
  uvSize: Vec2,
  color: ColorRGBX,
  clipPos = vec2(-1, -1),
  clipSize = vec2(-1, -1),
  maskUvPos = vec2(-1, -1),
  maskUvSize = vec2(0, 0)
) =
  ## Expands one quad into six drawer vertices.
  let
    cPos =
      if clipPos.x < 0: sk.clipRect.xy
      else: clipPos
    cSize =
      if clipSize.x < 0: sk.clipRect.wh
      else: clipSize
    pos0 = pos
    pos1 = pos + vec2(size.x, 0)
    pos2 = pos + size
    pos3 = pos + vec2(0, size.y)
    uv0 = uvPos
    uv1 = uvPos + vec2(uvSize.x, 0)
    uv2 = uvPos + uvSize
    uv3 = uvPos + vec2(0, uvSize.y)
    m0 = maskUvPos
    m1 = maskUvPos + vec2(maskUvSize.x, 0)
    m2 = maskUvPos + maskUvSize
    m3 = maskUvPos + vec2(0, maskUvSize.y)
    layer = sk.drawer.currentLayer

  sk.recordVertexClip(
    layer,
    6,
    rect(cPos, cSize),
    clipPos.x < 0 and clipSize.x < 0
  )
  sk.drawer.layers[layer].add(DrawerVertex(
    pos: pos0,
    uv: uv0,
    color: color,
    clipPos: cPos,
    clipSize: cSize,
    maskUv: m0
  ))
  sk.drawer.layers[layer].add(DrawerVertex(
    pos: pos1,
    uv: uv1,
    color: color,
    clipPos: cPos,
    clipSize: cSize,
    maskUv: m1
  ))
  sk.drawer.layers[layer].add(DrawerVertex(
    pos: pos2,
    uv: uv2,
    color: color,
    clipPos: cPos,
    clipSize: cSize,
    maskUv: m2
  ))
  sk.drawer.layers[layer].add(DrawerVertex(
    pos: pos0,
    uv: uv0,
    color: color,
    clipPos: cPos,
    clipSize: cSize,
    maskUv: m0
  ))
  sk.drawer.layers[layer].add(DrawerVertex(
    pos: pos2,
    uv: uv2,
    color: color,
    clipPos: cPos,
    clipSize: cSize,
    maskUv: m2
  ))
  sk.drawer.layers[layer].add(DrawerVertex(
    pos: pos3,
    uv: uv3,
    color: color,
    clipPos: cPos,
    clipSize: cSize,
    maskUv: m3
  ))

proc drawTriangle*(
  sk: Silky,
  positions: array[3, Vec2],
  uvs: array[3, Vec2],
  colors: array[3, ColorRGBX],
  clipPos = vec2(-1, -1),
  clipSize = vec2(-1, -1)
) =
  ## Appends one raw triangle to the current drawer layer.
  let
    cPos =
      if clipPos.x < 0: sk.clipRect.xy
      else: clipPos
    cSize =
      if clipSize.x < 0: sk.clipRect.wh
      else: clipSize
    layer = sk.drawer.currentLayer
  sk.recordVertexClip(
    layer,
    3,
    rect(cPos, cSize),
    clipPos.x < 0 and clipSize.x < 0
  )
  for i in 0 ..< 3:
    sk.drawer.layers[layer].add(DrawerVertex(
      pos: positions[i],
      uv: uvs[i],
      color: colors[i],
      clipPos: cPos,
      clipSize: cSize,
      maskUv: vec2(-1, -1)
    ))

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
): Vec2 {.measure.} =
  ## Queues text glyphs using atlas-backed font data.
  assert sk.inFrame
  if font notin sk.atlas.fonts:
    echo "[Warning] Font not found in atlas: " & font
    return
  if clip and (maxWidth <= 0 or maxHeight <= 0):
    return

  var glyphClip = clip
  if hAlign != LeftAlign or vAlign != TopAlign:
    glyphClip = false

  let
    fontData = sk.atlas.fonts[font]
    maxPos = pos + vec2(maxWidth, maxHeight)
    hasSubpixel = fontData.subpixelSteps > 0
    layer = sk.drawer.currentLayer
    needsHAlign = hAlign != LeftAlign
    needsVAlign = vAlign != TopAlign
  var currentPos = pos + vec2(0, fontData.ascent)

  if clip:
    sk.pushClipRect(rect(pos, vec2(maxWidth, maxHeight)))
  defer:
    if clip:
      sk.popClipRect()

  let textStartIdx = sk.drawer.layers[layer].len
  var lineStartIdx = textStartIdx

  template alignLine(lineWidth: float32) =
    ## Applies horizontal alignment to the current buffered line.
    if needsHAlign:
      let dx =
        case hAlign:
        of LeftAlign:
          0.0'f
        of CenterAlign:
          floor((maxWidth - lineWidth) * 0.5)
        of RightAlign:
          floor(maxWidth - lineWidth)
      if dx != 0:
        for j in lineStartIdx ..< sk.drawer.layers[layer].len:
          sk.drawer.layers[layer][j].pos.x += dx
      lineStartIdx = sk.drawer.layers[layer].len

  var
    i = 0
    previousRune = Rune(0)
    hasPreviousRune = false
  while i < text.len:
    let runeStart = i
    let rune = text.nextRune(i)

    if rune == LineFeedRune:
      alignLine(currentPos.x - pos.x)
      currentPos.x = pos.x
      currentPos.y += fontData.lineHeight
      hasPreviousRune = false
      continue

    if wordWrap and currentPos.x > pos.x and rune != SpaceRune:
      let isWordStart =
        not hasPreviousRune or
        previousRune == SpaceRune or
        previousRune == LineFeedRune
      if isWordStart:
        var
          wordW = 0.0'f
          j = runeStart
        while j < text.len:
          let wordRune = text.nextRune(j)
          if wordRune == SpaceRune or wordRune == LineFeedRune:
            break
          var wordEntry: ptr LetterEntry
          if fontData.lookupLetter(wordRune, 0, wordEntry):
            wordW += wordEntry.advance
        if currentPos.x + wordW > pos.x + maxWidth:
          alignLine(currentPos.x - pos.x)
          currentPos.x = pos.x
          currentPos.y += fontData.lineHeight

    let variant =
      if hasSubpixel:
        let frac = currentPos.x - currentPos.x.floor
        (frac * fontData.subpixelSteps.float32).int mod
          fontData.subpixelSteps
      else:
        0

    var entry: ptr LetterEntry
    if not fontData.lookupLetter(rune, variant, entry):
      previousRune = rune
      hasPreviousRune = true
      continue

    if currentPos.x >= maxPos.x:
      if wordWrap:
        alignLine(currentPos.x - pos.x)
        currentPos.x = pos.x
        currentPos.y += fontData.lineHeight
      elif glyphClip:
        while i < text.len:
          var next: Rune
          if not text.peekRune(i, next) or next == LineFeedRune:
            break
          discard text.nextRune(i)
        continue

    if glyphClip and currentPos.y + entry.boundsY >= maxPos.y:
      break

    if entry.boundsWidth > 0 and entry.boundsHeight > 0:
      let glyphPos = vec2(
        floor(currentPos.x) + entry.boundsX,
        round(currentPos.y + entry.boundsY)
      )
      sk.drawQuad(
        glyphPos,
        vec2(entry.boundsWidth, entry.boundsHeight),
        vec2(entry.x.float32, entry.y.float32),
        vec2(entry.boundsWidth, entry.boundsHeight),
        color
      )

    currentPos.x += entry.advance
    var next: Rune
    if text.peekRune(i, next):
      currentPos.x += fontData.lookupKerning(rune, next)

    previousRune = rune
    hasPreviousRune = true

  alignLine(currentPos.x - pos.x)

  if needsVAlign:
    let
      textHeight =
        currentPos.y - pos.y - fontData.ascent + fontData.lineHeight
      dy =
        case vAlign:
        of TopAlign:
          0.0'f
        of MiddleAlign:
          floor((maxHeight - textHeight) * 0.5)
        of BottomAlign:
          floor(maxHeight - textHeight)
    if dy != 0:
      for j in textStartIdx ..< sk.drawer.layers[layer].len:
        sk.drawer.layers[layer][j].pos.y += dy

  currentPos - pos

proc getTextSize*(sk: Silky, font: string, text: string): Vec2 {.measure.} =
  ## Returns the size of text in pixels.
  if font notin sk.atlas.fonts:
    return vec2(0, 0)

  let fontData = sk.atlas.fonts[font]
  var
    i = 0
    currentPos = vec2(0, fontData.lineHeight)
    maxWidth = 0.0'f

  while i < text.len:
    let rune = text.nextRune(i)
    if rune == LineFeedRune:
      maxWidth = max(maxWidth, currentPos.x)
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

  maxWidth = max(maxWidth, currentPos.x)
  vec2(maxWidth, currentPos.y)

proc newSilky*(
  window: Window,
  image: Image,
  atlas: SilkyAtlas
): Silky {.measure.} =
  ## Creates a new Silky context and eagerly initializes its drawer.
  result = Silky()
  result.image = image
  result.atlas = atlas
  result.builder = newAtlasBuilderFromAtlas(atlas, image)
  result.window = window
  result.drawer = newDrawer(window, image)

proc newSilky*(window: Window, atlasPngPath: string): Silky {.measure.} =
  ## Creates a new Silky from one atlas PNG file.
  let atlasData = readAtlas(atlasPngPath)
  newSilky(window, atlasData.image, atlasData.atlas)

proc uploadAtlas*(sk: Silky) =
  ## Push the current CPU atlas image to the GPU drawer.
  when not defined(useDirectX) and
      not defined(useVulkan) and
      not defined(useMetal4) and
      not defined(useCpu):
    sk.drawer.uploadAtlas(sk.image)

proc addAtlasImage*(sk: Silky, name: string, image: Image) =
  ## Pack an image into the runtime atlas and reupload the GPU texture.
  if sk.builder == nil:
    sk.builder = newAtlasBuilderFromAtlas(sk.atlas, sk.image)
  if not sk.builder.addImage(name, image):
    var size = max(sk.builder.size * 2, 64)
    let need = max(image.width, image.height) + sk.builder.margin * 4
    while size < need:
      size *= 2
    sk.builder.growAtlas(size)
    if not sk.builder.addImage(name, image):
      raise newException(
        SilkyAtlasError,
        "Failed to pack atlas image: " & name
      )
  sk.image = sk.builder.atlasImage
  sk.atlas = sk.builder.atlas
  sk.uploadAtlas()

proc drawImage*(
  sk: Silky,
  name: string,
  pos: Vec2,
  color = rgbx(255, 255, 255, 255),
  mask: string = ""
) {.measure.} =
  ## Queues an atlas image draw.
  if name notin sk.atlas.entries:
    echo "[Warning] Sprite not found in atlas: " & name
    return
  let uv = sk.atlas.entries[name]
  var
    mPos = vec2(-1, -1)
    mSize = vec2(0, 0)
  if mask.len > 0 and mask in sk.atlas.entries:
    let m = sk.atlas.entries[mask]
    mPos = vec2(m.x.float32, m.y.float32)
    mSize = vec2(m.width.float32, m.height.float32)
  sk.drawQuad(
    pos,
    vec2(uv.width.float32, uv.height.float32),
    vec2(uv.x.float32, uv.y.float32),
    vec2(uv.width.float32, uv.height.float32),
    color,
    maskUvPos = mPos,
    maskUvSize = mSize
  )

proc drawRect*(sk: Silky, pos, size: Vec2, color: ColorRGBX) =
  ## Queues a solid-colored rectangle draw.
  let
    uv = sk.atlas.entries[WhiteTileKey]
    center =
      vec2(uv.x.float32, uv.y.float32) +
      vec2(uv.width.float32, uv.height.float32) / 2
  sk.drawQuad(pos, size, center, vec2(0, 0), color)

proc draw9Patch*(
  sk: Silky,
  name: string,
  top, right, bottom, left: int,
  pos: Vec2,
  size: Vec2,
  color = rgbx(255, 255, 255, 255)
) {.measure.} =
  ## Queues a 9-patch image draw with independent border sizes.
  if name notin sk.atlas.entries:
    echo "[Warning] Sprite not found in atlas: " & name
    return
  let
    scale = max(sk.sliceScale, 1)
    topS = top * scale
    rightS = right * scale
    bottomS = bottom * scale
    leftS = left * scale
    uv = sk.atlas.entries[name]
    l = leftS.float32
    r = rightS.float32
    u = topS.float32
    d = bottomS.float32
    srcXOffsets = [0.int, leftS, uv.width - rightS]
    srcWidths = [leftS, uv.width - leftS - rightS, rightS]
    srcYOffsets = [0.int, topS, uv.height - bottomS]
    srcHeights = [topS, uv.height - topS - bottomS, bottomS]
    dstXOffsets = [0.0'f, l, size.x - r]
    dstWidths = [l, size.x - l - r, r]
    dstYOffsets = [0.0'f, u, size.y - d]
    dstHeights = [u, size.y - u - d, d]
    order = [
      (0, 0), (2, 0), (0, 2), (2, 2),
      (1, 0), (0, 1), (2, 1), (1, 2),
      (1, 1)
    ]

  for (x, y) in order:
    let
      sw = srcWidths[x]
      sh = srcHeights[y]
      dw = dstWidths[x]
      dh = dstHeights[y]
    if dw <= 0.001 or dh <= 0.001 or sw <= 0 or sh <= 0:
      continue
    sk.drawQuad(
      vec2(pos.x + dstXOffsets[x], pos.y + dstYOffsets[y]),
      vec2(dw, dh),
      vec2(
        (uv.x + srcXOffsets[x]).float32,
        (uv.y + srcYOffsets[y]).float32
      ),
      vec2(sw.float32, sh.float32),
      color
    )

proc draw9Patch*(
  sk: Silky,
  name: string,
  patch: int,
  pos: Vec2,
  size: Vec2,
  color = rgbx(255, 255, 255, 255)
) =
  ## Queues a 9-patch image draw.
  sk.draw9Patch(name, patch, patch, patch, patch, pos, size, color)

proc drawRoundedImage*(
  sk: Silky,
  name: string,
  pos: Vec2,
  size: Vec2,
  radius: float32,
  color = rgbx(255, 255, 255, 255)
) {.measure.} =
  ## Queues an atlas image draw filling size with rounded corners.
  ## The image keeps its aspect ratio: it is scaled uniformly to cover
  ## the destination rect, centered, and the overflow is cropped.
  ## Builds the shape from an inner rect, four edge rects and four
  ## triangle fans, keeping UVs mapped to the destination rect throughout.
  if name notin sk.atlas.entries:
    echo "[Warning] Sprite not found in atlas: " & name
    return
  if size.x <= 0.001 or size.y <= 0.001:
    return
  let
    entry = sk.atlas.entries[name]
    entrySize = vec2(entry.width.float32, entry.height.float32)
    cover = max(size.x / entrySize.x, size.y / entrySize.y)
    uvOrigin =
      vec2(entry.x.float32, entry.y.float32) +
      (entrySize - size / cover) / 2
    uvScale = vec2(1 / cover, 1 / cover)
    r = clamp(radius, 0.0'f, min(size.x, size.y) / 2)

  template uvAt(p: Vec2): Vec2 =
    uvOrigin + (p - pos) * uvScale

  template piece(piecePos, pieceSize: Vec2) =
    if pieceSize.x > 0.001 and pieceSize.y > 0.001:
      sk.drawQuad(
        piecePos,
        pieceSize,
        uvAt(piecePos),
        pieceSize * uvScale,
        color
      )

  if r < 0.5:
    piece(pos, size)
    return

  # Inner rect plus the four edge rects between the corners.
  piece(pos + vec2(r, r), size - vec2(r, r) * 2)
  piece(pos + vec2(r, 0), vec2(size.x - r * 2, r))
  piece(pos + vec2(r, size.y - r), vec2(size.x - r * 2, r))
  piece(pos + vec2(0, r), vec2(r, size.y - r * 2))
  piece(pos + vec2(size.x - r, r), vec2(r, size.y - r * 2))

  # Quarter-circle fans, one segment per ~2px of arc on screen.
  let
    arcLength = r * PI.float32 / 2 * max(sk.uiScale, 1.0'f)
    segments = max(4, ceil(arcLength / 2).int)
    corners = [
      (pos + vec2(r, r), PI.float32),
      (pos + vec2(size.x - r, r), PI.float32 * 1.5),
      (pos + vec2(size.x - r, size.y - r), 0.0'f),
      (pos + vec2(r, size.y - r), PI.float32 * 0.5)
    ]
  for (pivot, startAngle) in corners:
    var previous = pivot + vec2(cos(startAngle), sin(startAngle)) * r
    for i in 1 .. segments:
      let
        angle = startAngle + PI.float32 / 2 * i.float32 / segments.float32
        current = pivot + vec2(cos(angle), sin(angle)) * r
      sk.drawTriangle(
        [pivot, previous, current],
        [uvAt(pivot), uvAt(previous), uvAt(current)],
        [color, color, color]
      )
      previous = current

proc contains*(sk: Silky, name: string): bool =
  ## Returns true if the atlas contains one image entry.
  name in sk.atlas.entries

proc getAtlasEntry*(sk: Silky, name: string, entry: var Entry): bool =
  ## Gets one atlas entry by name.
  if name notin sk.atlas.entries:
    return false
  entry = sk.atlas.entries[name]
  true

proc atlasImageSize*(sk: Silky): IVec2 =
  ## Returns the atlas image size.
  ivec2(sk.image.width.int32, sk.image.height.int32)

proc clear*(sk: Silky) =
  ## Clears the queued draw data for the next frame.
  sk.drawer.layers[NormalLayer].setLen(0)
  sk.drawer.layers[PopupsLayer].setLen(0)
  sk.drawer.currentLayer = NormalLayer
  sk.drawer.layerStack.setLen(0)
  for layer in 0 ..< sk.vertexClips.len:
    sk.vertexClips[layer].setLen(0)

proc beginUi*(sk: Silky, window: Window, size: IVec2) =
  ## Begins a new UI frame.
  sk.drawer.beginFrame(window, size)
  sk.beginUiShared(window, size)

proc clearScreen*(sk: Silky, color: ColorRGBX) {.measure.} =
  ## Clears or updates the frame clear color through the drawer.
  sk.drawer.clearScreen(color)

proc endUi*(sk: Silky) =
  ## Flushes the queued draws through the active drawer.
  for i in 1 ..< sk.drawer.layers.len:
    sk.drawer.layers[NormalLayer].add(sk.drawer.layers[i])

  let
    scale = sk.uiScale
    quadCount = sk.drawer.layers[NormalLayer].len
    needsScale = not (scale ~= 1.0f)
  var
    quadsPtr: pointer
    scaledVertices: seq[DrawerVertex]
  if quadCount > 0:
    if needsScale:
      scaledVertices = newSeqOfCap[DrawerVertex](quadCount)
      for i in 0 ..< quadCount:
        var vertex = sk.drawer.layers[NormalLayer][i]
        vertex.pos *= scale
        vertex.clipPos *= scale
        vertex.clipSize *= scale
        scaledVertices.add(vertex)
      quadsPtr = cast[pointer](unsafeAddr scaledVertices[0])
    else:
      quadsPtr = cast[pointer](unsafeAddr sk.drawer.layers[NormalLayer][0])
  else:
    quadsPtr = nil
  sk.drawer.endFrame(
    sk.image,
    sk.framebufferSize.vec2,
    quadsPtr,
    quadCount
  )
  sk.endUiShared()

proc buttonDown*(sk: Silky): ButtonView =
  ## Returns a view that returns true if the selected button is down
  sk.window.buttonDown

proc buttonPressed*(sk: Silky): ButtonView =
  ## Returns a view that returns true the frame the selected button is pressed
  sk.window.buttonPressed

proc buttonReleased*(sk: Silky): ButtonView =
  ## Returns a view that returns true the frame the selected button is released
  sk.window.buttonReleased

when not defined(useDirectX) and
    not defined(useVulkan) and
    not defined(useMetal4) and
    not defined(useCpu):
  proc atlasTextureId*(sk: Silky): GLuint =
    ## Returns the OpenGL texture id of the atlas.
    sk.drawer.atlasTextureId()

proc beginWidget*(
  sk: Silky,
  kind: string,
  name = "",
  text = "",
  rect = rect(0'f, 0'f, 0'f, 0'f)
) {.inline.} =
  ## No-op semantic begin hook for GPU backends.
  discard

proc endWidget*(sk: Silky) {.inline.} =
  ## No-op semantic end hook for GPU backends.
  discard

proc setWidgetState*(
  sk: Silky,
  enabled = true,
  focused = false,
  pressed = false,
  hovered = false,
  checked = false,
  value = ""
) {.inline.} =
  ## No-op semantic state update for GPU backends.
  discard

proc setWidgetRect*(sk: Silky, rect: Rect) {.inline.} =
  ## No-op semantic rectangle update for GPU backends.
  discard

proc semanticSnapshot*(sk: Silky): string =
  ## Returns an empty semantic snapshot for GPU backends.
  ""

proc semanticReset*(sk: Silky) =
  ## Resets semantic capture for GPU backends.
  discard

proc semanticEnabled*(sk: Silky): bool =
  ## Returns false for GPU backends.
  false
