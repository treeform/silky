import
  std/[os, strutils, tables, unicode, times],
  pixie, opengl, jsony, shady, vmath, windy, bumpy,
  atlas, shaders, common

when defined(profile):
  import fluffy/measure
  export measure
else:
  macro measure*(fn: untyped) =
    return fn
  template measurePush*(what: string) =
    discard
  template measurePop*() =
    discard

type
  SilkyVertex* {.packed.} = object
    pos*: Vec2
    size*: Vec2
    uvPos*: array[2, uint16]
    uvSize*: array[2, uint16]
    color*: ColorRGBX
    clipPos*: Vec2
    clipSize*: Vec2

  Silky* = ref object
    ## The Silky that draws the AA pixel art sprites.
    inFrame: bool = false
    at*: Vec2
    atStack: seq[Vec2]
    posStack: seq[Vec2]
    sizeStack: seq[Vec2]
    stretchAt*: Vec2
    directionStack: seq[StackDirection]
    anchorStack: seq[Anchor]
    textStyle*: string = "Default"
    padding*: float32 = 12
    theme*: Theme = Theme()
    themeStack: seq[Theme]
    cursor*: Cursor = Cursor(kind: ArrowCursor)
    inputRunes*: seq[Rune]

    # Fields for tracking tooltip visibility and hover state.
    showTooltip*: bool = false
    lastMousePos*: Vec2
    mouseIdleTime*: float64
    hover*: bool = false
    tooltipThreshold*: float64 = 0.5

    atlas*: SilkyAtlas
    image*: Image
    shader: Shader
    vao: GLuint              ## Vertex array object.

    # VBOs.
    instanceVbo: GLuint      ## Single VBO for all instance data.
    atlasTexture: GLuint     ## GL texture for the atlas image.

    # Instance Data.
    layers*: array[2, seq[SilkyVertex]]
    currentLayer*: int
    layerStack*: seq[int]

    clipStack: seq[Rect]

    # Timing information.
    frameStartTime*: float64
    frameTime*: float64
    avgFrameTime*: float64

var
  mvp: Uniform[Mat4]
  atlasSize: Uniform[Vec2]
  atlasSampler: Uniform[Sampler2D]

  traceActive*: bool = false

proc pushLayer*(sk: Silky, layer: int) =
  ## Push a new layer onto the stack.
  sk.layerStack.add(sk.currentLayer)
  sk.currentLayer = layer

proc popLayer*(sk: Silky) =
  ## Pop the current layer from the stack.
  sk.currentLayer = sk.layerStack.pop()

proc pushTheme*(sk: Silky) =
  ## Save the current theme onto the stack.
  sk.themeStack.add(sk.theme)

proc popTheme*(sk: Silky) =
  ## Restore the previous theme from the stack.
  sk.theme = sk.themeStack.pop()

proc pushLayout*(
  sk: Silky,
  pos: Vec2,
  size: Vec2,
  direction: StackDirection = TopToBottom,
  anchor: Anchor = AnchorLeft
) =
  ## Push a new layout container onto the stack.
  sk.atStack.add(sk.at)
  sk.posStack.add(pos)
  sk.at = pos
  sk.sizeStack.add(size)
  sk.directionStack.add(direction)
  sk.anchorStack.add(anchor)
  sk.stretchAt = sk.at
  case direction:
  of TopToBottom:
    sk.at = pos
    if anchor == AnchorRight: sk.at.x += size.x
  of BottomToTop:
    sk.at = pos + vec2(0, size.y)
    if anchor == AnchorRight: sk.at.x += size.x
  of LeftToRight:
    sk.at = pos
    if anchor == AnchorBottom: sk.at.y += size.y
  of RightToLeft:
    sk.at = pos + vec2(size.x, 0)
    if anchor == AnchorBottom: sk.at.y += size.y

proc popLayout*(sk: Silky) =
  ## Pop the current layout container from the stack.
  sk.at = sk.atStack.pop()
  discard sk.posStack.pop()
  discard sk.sizeStack.pop()
  discard sk.directionStack.pop()
  discard sk.anchorStack.pop()

proc pos*(sk: Silky): Vec2 =
  ## Get the current layout position.
  sk.posStack[^1]

proc size*(sk: Silky): Vec2 =
  ## Get the current layout size.
  sk.sizeStack[^1]

proc rootSize*(sk: Silky): Vec2 =
  ## Get the root layout size.
  sk.sizeStack[0]

proc stackDirection*(sk: Silky): StackDirection =
  ## Get the current stack direction.
  sk.directionStack[^1]

proc stackAnchor*(sk: Silky): Anchor =
  ## Get the current stack anchor.
  sk.anchorStack[^1]

proc widgetPos*(sk: Silky, size: Vec2): Vec2 =
  ## Compute top-left draw position for a widget of the given size.
  result = sk.at
  if sk.stackDirection in {RightToLeft}:
    result.x -= size.x
  if sk.stackDirection in {BottomToTop}:
    result.y -= size.y
  if sk.stackAnchor == AnchorRight and sk.stackDirection in {TopToBottom, BottomToTop}:
    result.x -= size.x
  if sk.stackAnchor == AnchorBottom and sk.stackDirection in {LeftToRight, RightToLeft}:
    result.y -= size.y

proc pushClipRect*(sk: Silky, rect: Rect) =
  ## Push a new clip rectangle onto the stack.
  sk.clipStack.add(rect)

proc popClipRect*(sk: Silky) =
  ## Pop the current clip rectangle from the stack.
  discard sk.clipStack.pop()

proc clipRect*(sk: Silky): Rect =
  ## Get the current clip rectangle.
  sk.clipStack[^1]

proc instanceCount*(sk: Silky): int =
  ## Get the current instance count.
  var count = 0
  for i in 0 ..< sk.layers.len:
    count += sk.layers[i].len
  return count

proc advance*(sk: Silky, amount: Vec2) =
  ## Advance the position.
  sk.stretchAt = max(sk.stretchAt, sk.at + amount + vec2(sk.theme.spacing.float32))
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
  ## Get the size of an image in the atlas.
  if image notin sk.atlas.entries:
    echo "[Warning] Image not found in atlas: " & image
    return vec2(0, 0)
  let uv = sk.atlas.entries[image]
  return vec2(uv.width.float32, uv.height.float32)

proc shouldShowTooltip*(sk: Silky): bool =
  ## Check if the tooltip should be shown.
  sk.hover and sk.mouseIdleTime >= sk.tooltipThreshold

proc SilkyVert*(
  pos: Vec2,
  size: Vec2,
  uvPos: array[2, uint16],
  uvSize: array[2, uint16],
  color: ColorRGBX,
  clipPos: Vec2,
  clipSize: Vec2,
  fragmentUv: var Vec2,
  fragmentColor: var Vec4,
  fragmentClipPos: var Vec2,
  fragmentClipSize: var Vec2,
  fragmentPos: var Vec2
) =
  ## Vertex shader for Silky.
  # Compute the corner of the quad based on the vertex ID.
  # 0:(0,0), 1:(1,0), 2:(0,1), 3:(1,1).
  let corner = uvec2(uint32(gl_VertexID mod 2), uint32(gl_VertexID div 2))

  # Compute the position of the vertex in the atlas.
  let
    dx = pos.x + corner.x.float32 * size.x
    dy = pos.y + corner.y.float32 * size.y
  gl_Position = mvp * vec4(dx, dy, 0.0, 1.0)

  # Compute the texture coordinates of the vertex.
  let
    sx = float32(uvPos[0]) + float32(corner.x) * float32(uvSize[0])
    sy = float32(uvPos[1]) + float32(corner.y) * float32(uvSize[1])
  fragmentUv = vec2(sx, sy) / atlasSize
  fragmentColor = color.vec4
  fragmentClipPos = clipPos
  fragmentClipSize = clipSize
  fragmentPos = vec2(dx, dy)

proc SilkyFrag*(
  fragmentUv: Vec2,
  fragmentColor: Vec4,
  fragmentClipPos: Vec2,
  fragmentClipSize: Vec2,
  fragmentPos: Vec2,
  FragColor: var Vec4
) =
  ## Fragment shader for Silky.
  if fragmentPos.x < fragmentClipPos.x or
    fragmentPos.y < fragmentClipPos.y or
    fragmentPos.x > fragmentClipPos.x + fragmentClipSize.x or
    fragmentPos.y > fragmentClipPos.y + fragmentClipSize.y:
      # Clip the pixel.
      discardFragment()
  else:
    # Compute the texture coordinates of the pixel.
    FragColor = texture(atlasSampler, fragmentUv) * fragmentColor

proc beginUi*(sk: Silky, window: Window, size: IVec2) =
  ## Begin the UI frame.
  when defined(profile):
    if window.buttonPressed[KeyF3]:
      if traceActive == false:
        traceActive = true
        startTrace()
      else:
        traceActive = false
        endTrace()
        createDir("tmp")
        dumpMeasures("tmp/trace.json")

  # Reset showTooltip at the start of each frame.
  sk.showTooltip = false

  sk.pushLayout(vec2(0, 0), size.vec2)
  sk.inFrame = true
  let currentTime = epochTime()
  let deltaTime = currentTime - sk.frameStartTime
  sk.frameStartTime = currentTime

  # Track mouse movement for tooltip idle detection.
  let currentMousePos = window.mousePos.vec2
  if currentMousePos != sk.lastMousePos:
    sk.mouseIdleTime = 0
    sk.lastMousePos = currentMousePos
  else:
    sk.mouseIdleTime += deltaTime

  # Reset showTooltip at the start of each frame.
  sk.showTooltip = false

  glViewport(0, 0, sk.size.x.int32, sk.size.y.int32)

  measurePush("frame")

  sk.pushClipRect(rect(0, 0, sk.size.x, sk.size.y))

proc clearScreen*(sk: Silky, color: ColorRGBX) {.measure.} =
  ## Clear the screen with a color.
  let c = color.color
  glClearColor(c.r, c.g, c.b, c.a)
  glClear(GL_COLOR_BUFFER_BIT)

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
  ## Draw text using the specified font from the atlas.
  assert sk.inFrame
  if font notin sk.atlas.fonts:
    echo "[Warning] Font not found in atlas: " & font
    return
  if clip and (maxWidth <= 0 or maxHeight <= 0):
    return

  let fontData = sk.atlas.fonts[font]
  var currentPos = pos + vec2(0, fontData.ascent)
  let maxPos = pos + vec2(maxWidth, maxHeight)
  let runedText = text.toRunes
  let hasSubpixel = fontData.subpixelSteps > 0
  let layer = sk.currentLayer
  let needsHAlign = hAlign != LeftAlign
  let needsVAlign = vAlign != TopAlign

  # Per-char clip rect: when clip is on, intersect parent clip rect with text bounds.
  let parentClip = sk.clipRect
  let (textClipPos, textClipSize) =
    if clip:
      let
        cx1 = max(pos.x, parentClip.x)
        cy1 = max(pos.y, parentClip.y)
        cx2 = min(maxPos.x, parentClip.x + parentClip.w)
        cy2 = min(maxPos.y, parentClip.y + parentClip.h)
      (vec2(cx1, cy1), vec2(max(0.0f, cx2 - cx1), max(0.0f, cy2 - cy1)))
    else:
      (parentClip.xy, parentClip.wh)

  # Track buffer indices for alignment fixup.
  let textStartIdx = sk.layers[layer].len
  var lineStartIdx = textStartIdx

  proc alignLine(sk: Silky, lineWidth: float32) =
    ## Shift glyph positions for the current line based on horizontal alignment.
    if not needsHAlign: return
    let dx =
      case hAlign:
      of LeftAlign: 0.0f
      of CenterAlign: floor((maxWidth - lineWidth) * 0.5)
      of RightAlign: floor(maxWidth - lineWidth)
    if dx != 0:
      for j in lineStartIdx ..< sk.layers[layer].len:
        sk.layers[layer][j].pos.x += dx
    lineStartIdx = sk.layers[layer].len

  var i = 0
  while i < runedText.len:
    let rune = runedText[i]

    if rune == Rune(10): # Newline.
      sk.alignLine(currentPos.x - pos.x)
      currentPos.x = pos.x
      currentPos.y += fontData.lineHeight
      inc i
      continue

    # Word wrap: at the start of a word, check if the whole word fits on this line.
    if wordWrap and currentPos.x > pos.x and rune != Rune(32):
      let isWordStart = (i == 0) or runedText[i-1] == Rune(32) or runedText[i-1] == Rune(10)
      if isWordStart:
        var wordW = 0.0f
        var j = i
        while j < runedText.len and runedText[j] != Rune(32) and runedText[j] != Rune(10):
          let gs = $runedText[j]
          if gs in fontData.entries:
            wordW += fontData.entries[gs][0].advance
          elif "?" in fontData.entries:
            wordW += fontData.entries["?"][0].advance
          inc j
        if currentPos.x + wordW > pos.x + maxWidth:
          sk.alignLine(currentPos.x - pos.x)
          currentPos.x = pos.x
          currentPos.y += fontData.lineHeight

    let glyphStr = $rune

    # For subpixel fonts, select the variant based on fractional X position.
    let variant =
      if hasSubpixel:
        let frac = currentPos.x - currentPos.x.floor
        (frac * fontData.subpixelSteps.float32).int mod fontData.subpixelSteps
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

    if currentPos.x + entry.advance > maxPos.x:
      if wordWrap:
        # Character-level fallback for words wider than maxWidth.
        sk.alignLine(currentPos.x - pos.x)
        currentPos.x = pos.x
        currentPos.y += fontData.lineHeight
      elif clip:
        # Skip chars until the next newline, then start a new line.
        while i < runedText.len and runedText[i] != Rune(10):
          inc i
        continue

    # Stop when the glyph starts below the clip area.
    if clip and currentPos.y + entry.boundsY >= maxPos.y:
      break

    # Draw the glyph if it has dimensions.
    if entry.boundsWidth > 0 and entry.boundsHeight > 0:
      let glyphPos = vec2(
        floor(currentPos.x) + entry.boundsX,
        round(currentPos.y + entry.boundsY)
      )

      sk.layers[layer].add(SilkyVertex(
        pos: glyphPos,
        size: vec2(entry.boundsWidth, entry.boundsHeight),
        uvPos: [entry.x.uint16, entry.y.uint16],
        uvSize: [entry.boundsWidth.uint16, entry.boundsHeight.uint16],
        color: color,
        clipPos: textClipPos,
        clipSize: textClipSize
      ))

    currentPos.x += entry.advance

    # Kerning (stored in variant 0 entry).
    if i < runedText.len - 1:
      let nextRune = runedText[i+1]
      let nextGlyphStr = $nextRune
      if glyphStr in fontData.entries and nextGlyphStr in fontData.entries[glyphStr][0].kerning:
        currentPos.x += fontData.entries[glyphStr][0].kerning[nextGlyphStr]

    inc i

  # Align the last line.
  sk.alignLine(currentPos.x - pos.x)

  # Vertical alignment: shift all glyphs in the buffer.
  if needsVAlign:
    let textHeight = currentPos.y - pos.y - fontData.ascent + fontData.lineHeight
    let dy =
      case vAlign:
      of TopAlign: 0.0f
      of MiddleAlign: floor((maxHeight - textHeight) * 0.5)
      of BottomAlign: floor(maxHeight - textHeight)
    if dy != 0:
      for j in textStartIdx ..< sk.layers[layer].len:
        sk.layers[layer][j].pos.y += dy

  return currentPos - pos

proc getTextSize*(sk: Silky, font: string, text: string): Vec2 =
  ## Get the size of the text.
  let fontData = sk.atlas.fonts[font]
  var currentPos = vec2(0, fontData.lineHeight)
  let runedText = text.toRunes

  for i in 0 ..< runedText.len:
    let rune = runedText[i]

    if rune == Rune(10): # Newline.
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

    # Kerning.
    if i < runedText.len - 1:
      let nextRune = runedText[i+1]
      let nextGlyphStr = $nextRune
      if nextGlyphStr in entry.kerning:
        currentPos.x += entry.kerning[nextGlyphStr]

  return currentPos

proc newSilky*(imagePath, jsonPath: string): Silky {.measure.} =
  ## Create a new Silky.
  result = Silky()
  result.image = readImage(imagePath)
  result.atlas = readFile(jsonPath).fromJson(SilkyAtlas)
  result.layers[NormalLayer] = @[]
  result.layers[PopupsLayer] = @[]
  result.currentLayer = NormalLayer
  result.layerStack = @[]

  when defined(emscripten):
    result.shader = newShader(
      (
        "SilkyVert",
        toGLSL(SilkyVert, "300 es", "precision highp float;\n")
          .replace("uint(2)", "2")
          .replace("mod(gl_VertexID, 2)", "gl_VertexID % 2")
      ),
      (
        "SilkyFrag",
        toGLSL(SilkyFrag, "300 es", "precision highp float;\n")
      )
    )
  else:
    result.shader = newShader(
      ("SilkyVert", toGLSL(SilkyVert, "410", "")),
      ("SilkyFrag", toGLSL(SilkyFrag, "410", ""))
    )

  # Upload atlas image to GL texture.
  glGenTextures(1, result.atlasTexture.addr)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, result.atlasTexture)
  glTexImage2D(
    GL_TEXTURE_2D,
    0,
    GL_RGBA8.GLint,
    result.image.width.GLint,
    result.image.height.GLint,
    0,
    GL_RGBA,
    GL_UNSIGNED_BYTE,
    cast[pointer](result.image.data[0].addr)
  )
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
  glGenerateMipmap(GL_TEXTURE_2D)

  # Set up VAO and instance layers.
  glGenVertexArrays(1, result.vao.addr)
  glBindVertexArray(result.vao)
  let program = result.shader.programId

  # Single Instance VBO for all interleaved data.
  glGenBuffers(1, result.instanceVbo.addr)
  glBindBuffer(GL_ARRAY_BUFFER, result.instanceVbo)
  glBufferData(GL_ARRAY_BUFFER, 0, nil, GL_STREAM_DRAW)

  let stride = sizeof(SilkyVertex).GLsizei

  # Helper to set up attributes for the SilkyVertex struct.
  template setAttr(name: string, size: GLint, xtype: GLenum, normalized: GLboolean, offset: int) =
    let loc = glGetAttribLocation(program, name)
    if loc != -1:
      glEnableVertexAttribArray(loc.GLuint)
      glVertexAttribPointer(loc.GLuint, size, xtype, normalized, stride, cast[pointer](offset))
      glVertexAttribDivisor(loc.GLuint, 1)
    else:
      echo "[Warning] Attribute not found: ", name

  setAttr("pos", 2, cGL_FLOAT, GL_FALSE, offsetof(SilkyVertex, pos))
  setAttr("size", 2, cGL_FLOAT, GL_FALSE, offsetof(SilkyVertex, size))
  setAttr("uvPos", 2, GL_UNSIGNED_SHORT, GL_FALSE, offsetof(SilkyVertex, uvPos))
  setAttr("uvSize", 2, GL_UNSIGNED_SHORT, GL_FALSE, offsetof(SilkyVertex, uvSize))
  setAttr("color", 4, GL_UNSIGNED_BYTE, GL_TRUE, offsetof(SilkyVertex, color))
  setAttr("clipPos", 2, cGL_FLOAT, GL_FALSE, offsetof(SilkyVertex, clipPos))
  setAttr("clipSize", 2, cGL_FLOAT, GL_FALSE, offsetof(SilkyVertex, clipSize))

  # Unbind the layers.
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  glBindVertexArray(0)

proc drawQuad*(
  sk: Silky,
  pos: Vec2,
  size: Vec2,
  uvPos: Vec2,
  uvSize: Vec2,
  color: ColorRGBX
) =
  ## Draw a quad.
  sk.layers[sk.currentLayer].add(SilkyVertex(
    pos: pos,
    size: size,
    uvPos: [uvPos.x.uint16, uvPos.y.uint16],
    uvSize: [uvSize.x.uint16, uvSize.y.uint16],
    color: color,
    clipPos: sk.clipRect.xy,
    clipSize: sk.clipRect.wh
  ))

proc drawImage*(
  sk: Silky,
  name: string,
  pos: Vec2,
  color = rgbx(255, 255, 255, 255)
) =
  ## Draw a sprite at the given position.
  if name notin sk.atlas.entries:
    echo "[Warning] Sprite not found in atlas: " & name
    return
  let uv = sk.atlas.entries[name]
  sk.drawQuad(
    pos,
    vec2(uv.width.float32, uv.height.float32),
    vec2(uv.x.float32, uv.y.float32),
    vec2(uv.width.float32, uv.height.float32),
    color
  )

proc drawRect*(
  sk: Silky,
  pos: Vec2,
  size: Vec2,
  color: ColorRGBX
) =
  ## Draw a colored rectangle.
  let uv = sk.atlas.entries[WhiteTileKey]
  let center = vec2(uv.x.float32, uv.y.float32) + vec2(uv.width.float32, uv.height.float32) / 2
  sk.drawQuad(pos, size, center, vec2(0, 0), color)

proc draw9Patch*(
  sk: Silky,
  name: string,
  patch: int, # How much is the border size in pixels.
  pos: Vec2,
  size: Vec2,
  color = rgbx(255, 255, 255, 255)
) =
  ## Draw a 9-patch image.
  if name notin sk.atlas.entries:
    echo "[Warning] Sprite not found in atlas: " & name
    return
  let uv = sk.atlas.entries[name]

  let
    p = patch.float32

    # Source X definitions: (offset from uv.x, width).
    srcXOffsets = [0.int, patch, uv.width - patch]
    srcWidths = [patch, uv.width - 2 * patch, patch]

    # Source Y definitions: (offset from uv.y, height).
    srcYOffsets = [0.int, patch, uv.height - patch]
    srcHeights = [patch, uv.height - 2 * patch, patch]

    # Dest X definitions: (offset from pos.x, width).
    dstXOffsets = [0.float32, p, size.x - p]
    dstWidths = [p, size.x - 2 * p, p]

    # Dest Y definitions: (offset from pos.y, height).
    dstYOffsets = [0.float32, p, size.y - p]
    dstHeights = [p, size.y - 2 * p, p]

  # Draw order: Corners, Sides, Middle.
  let order = [
    (0, 0), (2, 0), (0, 2), (2, 2), # Corners.
    (1, 0), (0, 1), (2, 1), (1, 2), # Sides.
    (1, 1)                          # Middle.
  ]

  for (x, y) in order:
    let sw = srcWidths[x]
    let sh = srcHeights[y]
    let dw = dstWidths[x]
    let dh = dstHeights[y]

    # Skip if drawing nothing (e.g. if middle has 0 width).
    if dw <= 0.001 or dh <= 0.001 or sw <= 0 or sh <= 0:
      continue

    sk.drawQuad(
      vec2(pos.x + dstXOffsets[x], pos.y + dstYOffsets[y]),
      vec2(dw, dh),
      vec2((uv.x + srcXOffsets[x]).float32, (uv.y + srcYOffsets[y]).float32),
      vec2(sw.float32, sh.float32),
      color
    )

proc contains*(sk: Silky, name: string): bool =
  ## Check if the given sprite is in the atlas.
  name in sk.atlas.entries

proc clear*(sk: Silky) =
  ## Clear the current instance queue.
  sk.layers[NormalLayer].setLen(0)
  sk.layers[PopupsLayer].setLen(0)
  sk.currentLayer = NormalLayer
  sk.layerStack.setLen(0)

proc endUi*(
  sk: Silky,
) {.measure.} =
  ## Draw all queued instances for the current sprite.
  # sk.size = Vec2(0, 0)
  # sk.inFrame = false

  # Merge all layers into the normal layer.
  for i in 1 ..< sk.layers.len:
    sk.layers[NormalLayer].add(sk.layers[i])

  let instanceCount = sk.layers[NormalLayer].len
  if instanceCount == 0:
    sk.clear()
    sk.popLayout()
    sk.popClipRect()
    return

  # Enable blending.
  glEnable(GL_BLEND)
  # Premultiplied alpha blending.
  glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)

  # Upload instance buffer.
  glBindBuffer(GL_ARRAY_BUFFER, sk.instanceVbo)
  glBufferData(GL_ARRAY_BUFFER, sk.layers[NormalLayer].len * sizeof(SilkyVertex), sk.layers[NormalLayer][0].addr, GL_STREAM_DRAW)

  # Bind the shader and the atlas texture.
  glUseProgram(sk.shader.programId)
  mvp = ortho(0.float32, sk.size.x.float32, sk.size.y.float32, 0, -1000, 1000)
  sk.shader.setUniform("mvp", mvp)
  sk.shader.setUniform("atlasSize", vec2(sk.image.width.float32, sk.image.height.float32))
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, sk.atlasTexture)
  sk.shader.setUniform("atlasSampler", 0)
  sk.shader.bindUniforms()

  # Make sure VAO is bound before drawing.
  glBindVertexArray(sk.vao)

  # Draw 4-vertex triangle strip per instance (expanded in vertex shader).
  glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, instanceCount.GLsizei)

  # Unbind minimal state.
  glBindVertexArray(0)
  glUseProgram(0)
  glBindTexture(GL_TEXTURE_2D, 0)

  # Reset the data for the next frame.
  sk.clear()

  sk.popLayout()

  # Disable blending.
  glDisable(GL_BLEND)

  sk.popClipRect()

  sk.frameTime = epochTime() - sk.frameStartTime
  sk.avgFrameTime = (sk.avgFrameTime * 0.99) + (sk.frameTime * 0.01)

  sk.inputRunes.setLen(0)

  measurePop()

# Semantic capture API (no-op versions).

proc beginWidget*(sk: Silky, kind: string, name = "", text = "", rect = rect(0f, 0f, 0f, 0f)) {.inline.} =
  discard

proc endWidget*(sk: Silky) {.inline.} =
  discard

proc setWidgetState*(sk: Silky, enabled = true, focused = false, pressed = false,
                     hovered = false, checked = false, value = "") {.inline.} =
  discard

proc setWidgetRect*(sk: Silky, rect: Rect) {.inline.} =
  discard

proc semanticSnapshot*(sk: Silky): string =
  return ""

proc semanticReset*(sk: Silky) =
  discard

proc semanticEnabled*(sk: Silky): bool =
  return false
