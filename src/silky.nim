import
  std/[os, strutils, tables, unicode, times],
  pixie, opengl, boxy/[shaders], jsony, shady, vmath, windy,
  fidget2/measure,
  silky/atlas

export atlas

type
  Silky* = ref object
    ## The Silky that draws the AA pixel art sprites.
    inFrame: bool = false
    atStack: seq[Vec2]
    sizeStack: seq[Vec2]
    atlas: SilkyAtlas
    image: Image
    shader: Shader
    vao: GLuint              ## Vertex array object

    # VBOs
    posVbo: GLuint           ## Per-instance position (x, y)
    sizeVbo: GLuint          ## Per-instance size (w, h)
    uvPosVbo: GLuint         ## Per-instance UV position (u, v)
    uvSizeVbo: GLuint        ## Per-instance UV size (uw, uh)
    colorVbo: GLuint         ## Per-instance color (ColorRGBX)

    atlasTexture: GLuint     ## GL texture for the atlas image

    # Instance Data
    posData: seq[float32]
    sizeData: seq[float32]
    uvPosData: seq[uint16]
    uvSizeData: seq[uint16]
    colorData: seq[ColorRGBX]

    instanceCount: int

    # Timeing information
    frameStartTime*: float64
    frameTime*: float64
    avgFrameTime*: float64

var
  mvp: Uniform[Mat4]
  atlasSize: Uniform[Vec2]
  atlasSampler: Uniform[Sampler2D]

  traceActive: bool = false

proc pushFrame*(sk: Silky, at: Vec2, size: Vec2) =
  sk.atStack.add(at)
  sk.sizeStack.add(size)

proc move*(sk: Silky, v: Vec2) =
  sk.atStack[^1] += v

proc popFrame*(sk: Silky) =
  discard sk.atStack.pop()
  discard sk.sizeStack.pop()

proc at*(sk: Silky): Vec2 =
  sk.atStack[^1]

proc size*(sk: Silky): Vec2 =
  sk.sizeStack[^1]

proc SilkyVert*(
  pos: Vec2,
  size: Vec2,
  uvPos: Vec2,
  uvSize: Vec2,
  color: Vec4,
  fragmentUv: var Vec2,
  fragmentColor: var Vec4
) =
  # Compute the corner of the quad based on the vertex ID.
  # 0:(0,0), 1:(1,0), 2:(0,1), 3:(1,1)
  let corner = uvec2(gl_VertexID mod 2, gl_VertexID div 2)

  # Compute the position of the vertex in the atlas.
  let dx = pos.x + corner.x.float32 * size.x
  let dy = pos.y + corner.y.float32 * size.y
  gl_Position = mvp * vec4(dx, dy, 0.0, 1.0)

  # Compute the texture coordinates of the vertex.
  let sx = uvPos.x + float(corner.x) * uvSize.x
  let sy = uvPos.y + float(corner.y) * uvSize.y
  fragmentUv = vec2(sx, sy) / atlasSize
  fragmentColor = color

proc SilkyFrag*(fragmentUv: Vec2, fragmentColor: Vec4, FragColor: var Vec4) =
  # Compute the texture coordinates of the pixel.
  FragColor = texture(atlasSampler, fragmentUv) * fragmentColor

proc beginFrame*(sk: Silky, window: Window, size: IVec2) =

  when not defined(emscripten):
    if window.buttonPressed[KeyF3]:
      if traceActive == false:
        traceActive = true
        startTrace()
      else:
        traceActive = false
        endTrace()
        createDir("tmp")
        dumpMeasures(0, "tmp/trace.json")

  sk.pushFrame(vec2(0, 0), size.vec2)
  sk.inFrame = true
  sk.frameStartTime = epochTime()

  measurePush("glViewport")
  glViewport(0, 0, sk.size.x.int32, sk.size.y.int32)
  measurePop()

  measurePush("frame")

proc clearScreen*(sk: Silky, color: ColorRGBX) {.measure.} =
  let color = color.color
  glClearColor(color.r, color.g, color.b, color.a)
  glClear(GL_COLOR_BUFFER_BIT)

proc drawText*(sk: Silky, font: string, text: string, pos: Vec2, color: ColorRGBX) =
  ## Draw text using the specified font from the atlas.
  assert sk.inFrame
  if font notin sk.atlas.fonts:
    echo "[Warning] Font not found in atlas: " & font
    return

  let fontData = sk.atlas.fonts[font]
  var currentPos = pos
  let runedText = text.toRunes

  for i in 0 ..< runedText.len:
    let rune = runedText[i]
    
    if rune == Rune(10): # Newline
      currentPos.x = pos.x
      currentPos.y += fontData.lineHeight
      continue

    let glyphStr = $rune

    var entry: LetterEntry
    if glyphStr in fontData.entries:
      entry = fontData.entries[glyphStr]
    elif "?" in fontData.entries:
      entry = fontData.entries["?"]
    else:
      continue

    # Draw the glyph if it has dimensions
    if entry.boundsWidth > 0 and entry.boundsHeight > 0:
      let pos = vec2(
        round(currentPos.x + entry.boundsX),
        round(currentPos.y + entry.boundsY)
      )

      sk.posData.add(pos.x)
      sk.posData.add(pos.y)

      sk.sizeData.add(entry.boundsWidth)
      sk.sizeData.add(entry.boundsHeight)

      sk.uvPosData.add(entry.x.uint16)
      sk.uvPosData.add(entry.y.uint16)

      sk.uvSizeData.add(entry.boundsWidth.uint16)
      sk.uvSizeData.add(entry.boundsHeight.uint16)

      sk.colorData.add(color)

      inc sk.instanceCount

    currentPos.x += entry.advance

    # Kerning
    if i < runedText.len - 1:
      let nextRune = runedText[i+1]
      let nextGlyphStr = $nextRune
      if nextGlyphStr in entry.kerning:
        currentPos.x += entry.kerning[nextGlyphStr]
  

proc newSilky*(imagePath, jsonPath: string): Silky =
  ## Creates a new Silky.
  result = Silky()
  result.image = readImage(imagePath)
  result.atlas = readFile(jsonPath).fromJson(SilkyAtlas)
  result.posData = @[]
  result.sizeData = @[]
  result.uvPosData = @[]
  result.uvSizeData = @[]
  result.colorData = @[]
  result.instanceCount = 0

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

  # Upload atlas image to GL texture
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

  # Set up VAO and instance buffers.
  glGenVertexArrays(1, result.vao.addr)
  glBindVertexArray(result.vao)
  let program = result.shader.programId

  # 1. Position VBO (vec2)
  glGenBuffers(1, result.posVbo.addr)
  glBindBuffer(GL_ARRAY_BUFFER, result.posVbo)
  glBufferData(GL_ARRAY_BUFFER, 0, nil, GL_STREAM_DRAW)
  let posLoc = glGetAttribLocation(program, "pos")
  doAssert posLoc != -1, "pos attribute not found"
  glEnableVertexAttribArray(posLoc.GLuint)
  glVertexAttribPointer(posLoc.GLuint, 2, cGL_FLOAT, GL_FALSE, 2 * sizeof(float32), nil)
  glVertexAttribDivisor(posLoc.GLuint, 1)

  # 2. Size VBO (vec2)
  glGenBuffers(1, result.sizeVbo.addr)
  glBindBuffer(GL_ARRAY_BUFFER, result.sizeVbo)
  glBufferData(GL_ARRAY_BUFFER, 0, nil, GL_STREAM_DRAW)
  let sizeLoc = glGetAttribLocation(program, "size")
  doAssert sizeLoc != -1, "size attribute not found"
  glEnableVertexAttribArray(sizeLoc.GLuint)
  glVertexAttribPointer(sizeLoc.GLuint, 2, cGL_FLOAT, GL_FALSE, 2 * sizeof(float32), nil)
  glVertexAttribDivisor(sizeLoc.GLuint, 1)

  # 3. UV Position VBO (vec2)
  glGenBuffers(1, result.uvPosVbo.addr)
  glBindBuffer(GL_ARRAY_BUFFER, result.uvPosVbo)
  glBufferData(GL_ARRAY_BUFFER, 0, nil, GL_STREAM_DRAW)
  let uvPosLoc = glGetAttribLocation(program, "uvPos")
  doAssert uvPosLoc != -1, "uvPos attribute not found"
  glEnableVertexAttribArray(uvPosLoc.GLuint)
  glVertexAttribPointer(uvPosLoc.GLuint, 2, GL_UNSIGNED_SHORT, GL_FALSE, 2 * sizeof(uint16), nil)
  glVertexAttribDivisor(uvPosLoc.GLuint, 1)

  # 4. UV Size VBO (vec2)
  glGenBuffers(1, result.uvSizeVbo.addr)
  glBindBuffer(GL_ARRAY_BUFFER, result.uvSizeVbo)
  glBufferData(GL_ARRAY_BUFFER, 0, nil, GL_STREAM_DRAW)
  let uvSizeLoc = glGetAttribLocation(program, "uvSize")
  doAssert uvSizeLoc != -1, "uvSize attribute not found"
  glEnableVertexAttribArray(uvSizeLoc.GLuint)
  glVertexAttribPointer(uvSizeLoc.GLuint, 2, GL_UNSIGNED_SHORT, GL_FALSE, 2 * sizeof(uint16), nil)
  glVertexAttribDivisor(uvSizeLoc.GLuint, 1)

  # 5. Color VBO (vec4, normalized uint8)
  glGenBuffers(1, result.colorVbo.addr)
  glBindBuffer(GL_ARRAY_BUFFER, result.colorVbo)
  glBufferData(GL_ARRAY_BUFFER, 0, nil, GL_STREAM_DRAW)
  let colorLoc = glGetAttribLocation(program, "color")
  doAssert colorLoc != -1, "color attribute not found"
  glEnableVertexAttribArray(colorLoc.GLuint)
  glVertexAttribPointer(colorLoc.GLuint, 4, GL_UNSIGNED_BYTE, GL_TRUE, sizeof(ColorRGBX).GLsizei, nil)
  glVertexAttribDivisor(colorLoc.GLuint, 1)

  # Unbind the buffers.
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  glBindVertexArray(0)

proc drawImage*(
  sk: Silky,
  name: string,
  pos: Vec2,
  color = rgbx(255, 255, 255, 255)
) {.measure.} =
  ## Draws a sprite at the given position.
  if name notin sk.atlas.entries:
    echo "[Warning] Sprite not found in atlas: " & name
    return
  let uv = sk.atlas.entries[name]

  sk.posData.add(pos.x)
  sk.posData.add(pos.y)

  sk.sizeData.add(uv.width.float32)
  sk.sizeData.add(uv.height.float32)

  sk.uvPosData.add(uv.x.uint16)
  sk.uvPosData.add(uv.y.uint16)

  sk.uvSizeData.add(uv.width.uint16)
  sk.uvSizeData.add(uv.height.uint16)

  sk.colorData.add(color)

  inc sk.instanceCount

proc drawRect*(
  sk: Silky,
  pos: Vec2,
  size: Vec2,
  color: ColorRGBX
) {.measure.} =
  ## Draws a colored rectangle.
  let uv = sk.atlas.entries[WhiteTileKey]

  sk.posData.add(pos.x)
  sk.posData.add(pos.y)

  sk.sizeData.add(size.x)
  sk.sizeData.add(size.y)

  # Use the center of the white tile for UVs to avoid edge bleeding
  let center = vec2(uv.x.float32, uv.y.float32) + vec2(uv.width.float32, uv.height.float32) / 2
  sk.uvPosData.add(center.x.uint16)
  sk.uvPosData.add(center.y.uint16)

  # UV size is effectively 0 or 1 pixel for solid color, but let's keep it consistent
  sk.uvSizeData.add(0)
  sk.uvSizeData.add(0)

  sk.colorData.add(color)

  inc sk.instanceCount

proc contains*(sk: Silky, name: string): bool =
  ## Checks if the given sprite is in the atlas.
  name in sk.atlas.entries

proc clear*(sk: Silky) =
  ## Clears the current instance queue.
  sk.posData.setLen(0)
  sk.sizeData.setLen(0)
  sk.uvPosData.setLen(0)
  sk.uvSizeData.setLen(0)
  sk.colorData.setLen(0)
  sk.instanceCount = 0

proc endFrame*(
  sk: Silky,
) {.measure.} =
  ## Draw all queued instances for the current sprite.
  # sk.size = Vec2(0, 0)
  # sk.inFrame = false

  if sk.instanceCount == 0:
    return

  # Enable blending.
  glEnable(GL_BLEND)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

  # Upload position buffer.
  glBindBuffer(GL_ARRAY_BUFFER, sk.posVbo)
  glBufferData(GL_ARRAY_BUFFER, sk.posData.len * sizeof(float32), sk.posData[0].addr, GL_STREAM_DRAW)

  # Upload size buffer.
  glBindBuffer(GL_ARRAY_BUFFER, sk.sizeVbo)
  glBufferData(GL_ARRAY_BUFFER, sk.sizeData.len * sizeof(float32), sk.sizeData[0].addr, GL_STREAM_DRAW)

  # Upload UV position buffer.
  glBindBuffer(GL_ARRAY_BUFFER, sk.uvPosVbo)
  glBufferData(GL_ARRAY_BUFFER, sk.uvPosData.len * sizeof(uint16), sk.uvPosData[0].addr, GL_STREAM_DRAW)

  # Upload UV size buffer.
  glBindBuffer(GL_ARRAY_BUFFER, sk.uvSizeVbo)
  glBufferData(GL_ARRAY_BUFFER, sk.uvSizeData.len * sizeof(uint16), sk.uvSizeData[0].addr, GL_STREAM_DRAW)

  # Upload color buffer.
  glBindBuffer(GL_ARRAY_BUFFER, sk.colorVbo)
  glBufferData(GL_ARRAY_BUFFER, sk.colorData.len * sizeof(ColorRGBX), sk.colorData[0].addr, GL_STREAM_DRAW)

  # Bind the shader and the atlas texture.
  glUseProgram(sk.shader.programId)
  mvp = ortho(0.float32, sk.size.x.float32, sk.size.y.float32, 0, -1000, 1000)
  sk.shader.setUniform("mvp", mvp)
  sk.shader.setUniform("atlasSize", vec2(sk.image.width.float32, sk.image.height.float32))
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, sk.atlasTexture)
  sk.shader.setUniform("atlasSampler", 0)
  sk.shader.bindUniforms()

  # Make sure VAO is bound before drawing
  glBindVertexArray(sk.vao)

  # Draw 4-vertex triangle strip per instance (expanded in vertex shader)
  glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, sk.instanceCount.GLsizei)

  # Unbind minimal state
  glBindVertexArray(0)
  glUseProgram(0)
  glBindTexture(GL_TEXTURE_2D, 0)

  # Reset the data for the next frame.
  sk.clear()

  sk.popFrame()

  # Disable blending.
  glDisable(GL_BLEND)

  sk.frameTime = epochTime() - sk.frameStartTime
  sk.avgFrameTime = (sk.avgFrameTime * 0.99) + (sk.frameTime * 0.01)

  measurePop()
