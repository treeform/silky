import
  std/[tables, unicode, times],
  pixie, vmath, windy, bumpy,
  silky/atlas

when defined(profile):
  import fluffy/measure, std/os
  export measure
else:
  macro measure*(fn: untyped) =
    ## Passes procedures through unchanged when profiling is off.
    return fn

  template measurePush*(what: string) =
    ## No-op profile begin marker.
    discard

  template measurePop*() =
    ## No-op profile end marker.
    discard

when defined(useDirectX):
  import silky/drawers/dx12
elif defined(useVulkan):
  import silky/drawers/vk14
elif defined(useMetal4):
  import silky/drawers/metal4
else:
  import opengl
  import silky/drawers/ogl

const
  NormalLayer* = 0
  PopupsLayer* = 1

type
  StackDirection* = enum
    ## Direction of the current layout flow.
    TopToBottom
    BottomToTop
    LeftToRight
    RightToLeft

  Theme* = object
    ## Theme for the Silky UI.
    padding*: int = 8
    menuPadding*: int = 2
    spacing*: int = 8
    border*: int = 10
    textPadding*: int = 4
    headerHeight*: int = 32
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
    menuRootHoverColor*: ColorRGBX = rgbx(70, 70, 90, 200)
    menuItemHoverColor*: ColorRGBX = rgbx(70, 70, 90, 180)
    menuItemBgColor*: ColorRGBX = rgbx(40, 40, 50, 140)
    menuPopupHoverColor*: ColorRGBX = rgbx(80, 80, 100, 180)
    menuPopupSelectedColor*: ColorRGBX = rgbx(60, 60, 80, 120)

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
    at*: Vec2
    atStack: seq[Vec2]
    posStack: seq[Vec2]
    sizeStack: seq[Vec2]
    stretchAt*: Vec2
    directionStack: seq[StackDirection]
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
    drawer*: Drawer
    clipStack: seq[Rect]
    frameStartTime*: float64
    frameTime*: float64
    avgFrameTime*: float64
    interactor*: Interactor
    window: Window

var traceActive*: bool = false

proc currentDrawLayer*(sk: Silky): int =
  sk.drawer.currentLayer

proc pushLayer*(sk: Silky, layer: int) =
  ## Pushes a new rendering layer onto the stack.
  sk.drawer.layerStack.add(sk.drawer.currentLayer)
  sk.drawer.currentLayer = layer

proc popLayer*(sk: Silky) =
  ## Pops the current rendering layer from the stack.
  sk.drawer.currentLayer = sk.drawer.layerStack.pop()

proc pushLayout*(
  sk: Silky,
  pos: Vec2,
  size: Vec2,
  direction: StackDirection = TopToBottom
) =
  ## Pushes a new layout region onto the stack.
  sk.atStack.add(sk.at)
  sk.posStack.add(pos)
  sk.at = pos
  sk.sizeStack.add(size)
  sk.directionStack.add(direction)
  sk.stretchAt = sk.at
  case direction:
  of TopToBottom:
    sk.at = pos
  of BottomToTop:
    sk.at = pos + vec2(0, size.y)
  of LeftToRight:
    sk.at = pos
  of RightToLeft:
    sk.at = pos + vec2(size.x, 0)

proc popLayout*(sk: Silky) =
  ## Pops the current layout region from the stack.
  sk.at = sk.atStack.pop()
  discard sk.posStack.pop()
  discard sk.sizeStack.pop()
  discard sk.directionStack.pop()

proc pos*(sk: Silky): Vec2 =
  ## Returns the current layout position.
  sk.posStack[^1]

proc size*(sk: Silky): Vec2 =
  ## Returns the current layout size.
  sk.sizeStack[^1]

proc rootSize*(sk: Silky): Vec2 =
  ## Returns the root layout size.
  sk.sizeStack[0]

proc stackDirection*(sk: Silky): StackDirection =
  ## Returns the current stack direction.
  sk.directionStack[^1]

proc pushRawClipRect*(sk: Silky, rect: Rect) =
  ## Pushes a clip rectangle without intersection.
  sk.clipStack.add(rect)

proc pushClipRect*(sk: Silky, rect: Rect) =
  ## Pushes a clip rectangle intersected with the parent clip.
  if sk.clipStack.len == 0:
    sk.pushRawClipRect(rect)
    return

  let
    parentClip = sk.clipStack[^1]
    x1 = max(parentClip.x, rect.x)
    y1 = max(parentClip.y, rect.y)
    x2 = min(parentClip.x + parentClip.w, rect.x + rect.w)
    y2 = min(parentClip.y + parentClip.h, rect.y + rect.h)
  sk.pushRawClipRect(rect(
    x1,
    y1,
    max(0.0'f, x2 - x1),
    max(0.0'f, y2 - y1)
  ))

proc popClipRect*(sk: Silky) =
  ## Pops the current clip rectangle.
  discard sk.clipStack.pop()

proc clipRect*(sk: Silky): Rect =
  ## Returns the current clip rectangle.
  sk.clipStack[^1]

proc instanceCount*(sk: Silky): int =
  ## Returns the number of queued drawer vertices.
  for i in 0 ..< sk.drawer.layers.len:
    result += sk.drawer.layers[i].len

proc advance*(sk: Silky, amount: Vec2) =
  ## Advances the current layout cursor.
  sk.stretchAt = max(
    sk.stretchAt,
    sk.at + amount + vec2(sk.theme.spacing.float32)
  )
  case sk.stackDirection:
  of TopToBottom:
    sk.at.y += amount.y + sk.theme.spacing.float32
  of BottomToTop:
    sk.at.y -= amount.y + sk.theme.spacing.float32
  of LeftToRight:
    sk.at.x += amount.x + sk.theme.spacing.float32
  of RightToLeft:
    sk.at.x -= amount.x + sk.theme.spacing.float32

proc getImageSize*(sk: Silky, image: string): Vec2 =
  ## Returns the size of an atlas image in pixels.
  if image notin sk.atlas.entries:
    echo "[Warning] Image not found in atlas: " & image
    return vec2(0, 0)
  let uv = sk.atlas.entries[image]
  vec2(uv.width.float32, uv.height.float32)

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
  when defined(profile):
    if window.buttonPressed[KeyF3]:
      if not traceActive:
        traceActive = true
        startTrace()
      else:
        traceActive = false
        endTrace()
        createDir("tmp")
        dumpMeasures("tmp/trace.json")

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
  for i in 0 ..< 3:
    sk.drawer.layers[layer].add(DrawerVertex(
      pos: positions[i],
      uv: uvs[i],
      color: colors[i],
      clipPos: cPos,
      clipSize: cSize,
      maskUv: vec2(-1, -1)
    ))

proc isAsciiText(text: string): bool =
  for ch in text:
    if ord(ch) >= 128:
      return false
  true

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

  let
    parentClip = sk.clipRect
    textClip =
      if clip:
        let
          cx1 = max(pos.x, parentClip.x)
          cy1 = max(pos.y, parentClip.y)
          cx2 = min(maxPos.x, parentClip.x + parentClip.w)
          cy2 = min(maxPos.y, parentClip.y + parentClip.h)
        (
          vec2(cx1, cy1),
          vec2(max(0.0'f, cx2 - cx1), max(0.0'f, cy2 - cy1))
        )
      else:
        (parentClip.xy, parentClip.wh)

  let textStartIdx = sk.drawer.layers[layer].len
  var lineStartIdx = textStartIdx

  proc alignLine(lineWidth: float32) =
    ## Applies horizontal alignment to the current buffered line.
    if not needsHAlign:
      return
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

  if text.isAsciiText():
    var i = 0
    while i < text.len:
      let ch = text[i]

      if ch == '\n':
        alignLine(currentPos.x - pos.x)
        currentPos.x = pos.x
        currentPos.y += fontData.lineHeight
        inc i
        continue

      if wordWrap and currentPos.x > pos.x and ch != ' ':
        let isWordStart =
          i == 0 or
          text[i - 1] == ' ' or
          text[i - 1] == '\n'
        if isWordStart:
          var
            wordW = 0.0'f
            j = i
          while j < text.len and text[j] != ' ' and text[j] != '\n':
            var wordEntry: AsciiLetterEntry
            if fontData.lookupAsciiLetter(text[j], 0, wordEntry):
              wordW += wordEntry.advance
            inc j
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

      var entry: AsciiLetterEntry
      if not fontData.lookupAsciiLetter(ch, variant, entry):
        inc i
        continue

      if currentPos.x >= maxPos.x:
        if wordWrap:
          alignLine(currentPos.x - pos.x)
          currentPos.x = pos.x
          currentPos.y += fontData.lineHeight
        elif glyphClip:
          while i < text.len and text[i] != '\n':
            inc i
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
          color,
          textClip[0],
          textClip[1]
        )

      currentPos.x += entry.advance
      if i < text.len - 1:
        currentPos.x += fontData.lookupAsciiKerning(ch, text[i + 1])

      inc i

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

    return currentPos - pos

  let runedText = text.toRunes
  var i = 0
  while i < runedText.len:
    let rune = runedText[i]

    if rune == Rune(10):
      alignLine(currentPos.x - pos.x)
      currentPos.x = pos.x
      currentPos.y += fontData.lineHeight
      inc i
      continue

    if wordWrap and currentPos.x > pos.x and rune != Rune(32):
      let isWordStart =
        i == 0 or
        runedText[i - 1] == Rune(32) or
        runedText[i - 1] == Rune(10)
      if isWordStart:
        var
          wordW = 0.0'f
          j = i
        while j < runedText.len and
          runedText[j] != Rune(32) and
          runedText[j] != Rune(10):
          let gs = $runedText[j]
          if gs in fontData.entries:
            wordW += fontData.entries[gs][0].advance
          elif "?" in fontData.entries:
            wordW += fontData.entries["?"][0].advance
          inc j
        if currentPos.x + wordW > pos.x + maxWidth:
          alignLine(currentPos.x - pos.x)
          currentPos.x = pos.x
          currentPos.y += fontData.lineHeight

    let glyphStr = $rune
    let variant =
      if hasSubpixel:
        let frac = currentPos.x - currentPos.x.floor
        (frac * fontData.subpixelSteps.float32).int mod
          fontData.subpixelSteps
      else:
        0

    var entry: LetterEntry
    if glyphStr in fontData.entries:
      entry = fontData.entries[glyphStr][variant]
    elif "?" in fontData.entries:
      entry = fontData.entries["?"][0]
    else:
      inc i
      continue

    if currentPos.x >= maxPos.x:
      if wordWrap:
        alignLine(currentPos.x - pos.x)
        currentPos.x = pos.x
        currentPos.y += fontData.lineHeight
      elif glyphClip:
        while i < runedText.len and runedText[i] != Rune(10):
          inc i
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
        color,
        textClip[0],
        textClip[1]
      )

    currentPos.x += entry.advance
    if i < runedText.len - 1:
      let nextGlyphStr = $runedText[i + 1]
      if glyphStr in fontData.entries and
        nextGlyphStr in fontData.entries[glyphStr][0].kerning:
        currentPos.x +=
          fontData.entries[glyphStr][0].kerning[nextGlyphStr]

    inc i

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

proc getTextSize*(sk: Silky, font: string, text: string): Vec2 =
  ## Returns the size of text in pixels.
  if font notin sk.atlas.fonts:
    return vec2(0, 0)

  let
    fontData = sk.atlas.fonts[font]
  var
    currentPos = vec2(0, fontData.lineHeight)
    maxWidth = 0.0'f

  if text.isAsciiText():
    for i in 0 ..< text.len:
      let ch = text[i]
      if ch == '\n':
        maxWidth = max(maxWidth, currentPos.x)
        currentPos.x = 0
        currentPos.y += fontData.lineHeight
        continue

      var entry: AsciiLetterEntry
      if not fontData.lookupAsciiLetter(ch, 0, entry):
        continue

      currentPos.x += entry.advance
      if i < text.len - 1:
        currentPos.x += fontData.lookupAsciiKerning(ch, text[i + 1])
  else:
    let runedText = text.toRunes
    for i in 0 ..< runedText.len:
      let rune = runedText[i]
      if rune == Rune(10):
        maxWidth = max(maxWidth, currentPos.x)
        currentPos.x = 0
        currentPos.y += fontData.lineHeight
        continue

      let glyphStr = $rune
      var entry: LetterEntry
      if glyphStr in fontData.entries:
        entry = fontData.entries[glyphStr][0]
      elif "?" in fontData.entries:
        entry = fontData.entries["?"][0]
      else:
        continue

      currentPos.x += entry.advance
      if i < runedText.len - 1:
        let nextGlyphStr = $runedText[i + 1]
        if nextGlyphStr in entry.kerning:
          currentPos.x += entry.kerning[nextGlyphStr]

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
  result.window = window
  result.drawer = newDrawer(window, image)

proc newSilky*(window: Window, atlasPngPath: string): Silky {.measure.} =
  ## Creates a new Silky from one atlas PNG file.
  let atlasData = readAtlas(atlasPngPath)
  newSilky(window, atlasData.image, atlasData.atlas)

proc drawImage*(
  sk: Silky,
  name: string,
  pos: Vec2,
  color = rgbx(255, 255, 255, 255),
  mask: string = ""
) =
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
) =
  ## Queues a 9-patch image draw with independent border sizes.
  if name notin sk.atlas.entries:
    echo "[Warning] Sprite not found in atlas: " & name
    return
  let
    uv = sk.atlas.entries[name]
    l = left.float32
    r = right.float32
    u = top.float32
    d = bottom.float32
    srcXOffsets = [0.int, left, uv.width - right]
    srcWidths = [left, uv.width - left - right, right]
    srcYOffsets = [0.int, top, uv.height - bottom]
    srcHeights = [top, uv.height - top - bottom, bottom]
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

proc beginUi*(sk: Silky, window: Window, size: IVec2) =
  ## Begins a new UI frame.
  sk.drawer.beginFrame(window, size)
  sk.beginUiShared(window, size)

proc clearScreen*(sk: Silky, color: ColorRGBX) {.measure.} =
  ## Clears or updates the frame clear color through the drawer.
  sk.drawer.clearScreen(color)

proc endUi*(sk: Silky) {.measure.} =
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
    not defined(useMetal4):
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
