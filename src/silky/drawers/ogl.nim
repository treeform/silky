import
  std/[strformat, strutils],
  pixie, opengl, shady, vmath, windy,
  silky/drawers/shader

type
  BufferKind* = enum
    bkSCALAR, bkVEC2, bkVEC3, bkVEC4, bkMAT2, bkMAT3, bkMAT4

  Buffer* = ref object
    count*: int
    target*, componentType*: GLenum
    kind*: BufferKind
    normalized*: bool
    bufferId*: GLuint

  ShaderAttrib = object
    name: string
    location: GLint

  ShaderUniformState = object
    name: string
    componentType: GLenum
    kind: BufferKind
    values: array[64, uint8]
    location: GLint
    changed: bool

  Shader* = ref object
    paths: seq[string]
    programId*: GLuint
    attribs*: seq[ShaderAttrib]
    uniforms*: seq[ShaderUniformState]

  DrawerVertex* {.packed.} = object
    ## Raw quad layout consumed by the OpenGL drawer.
    pos*: Vec2
    uv*: Vec2
    color*: ColorRGBX
    clipPos*: Vec2
    clipSize*: Vec2
    maskUv*: Vec2

  Drawer* = ref object
    ## OpenGL-backed drawer state.
    shader: Shader
    vao: GLuint
    instanceVbo: GLuint
    atlasTexture: GLuint
    layers*: array[2, seq[DrawerVertex]]
    currentLayer*: int
    layerStack*: seq[int]

func size(componentType: GLenum): Positive =
  ## Returns the byte size of a GL component type.
  case componentType:
  of cGL_BYTE, cGL_UNSIGNED_BYTE:
    1
  of cGL_SHORT, cGL_UNSIGNED_SHORT:
    2
  of cGL_INT, GL_UNSIGNED_INT, cGL_FLOAT:
    4
  else:
    raise newException(Exception, "Unexpected componentType")

func componentCount(bufferKind: BufferKind): Positive =
  ## Returns the number of components for a buffer kind.
  case bufferKind:
  of bkSCALAR:
    1
  of bkVEC2:
    2
  of bkVEC3:
    3
  of bkVEC4, bkMAT2:
    4
  of bkMAT3:
    9
  of bkMAT4:
    16

proc bindBufferData*(buffer: Buffer, data: pointer) =
  ## Binds and uploads data to the buffer.
  if buffer.bufferId == 0:
    glGenBuffers(1, buffer.bufferId.addr)

  let byteLength =
    buffer.count *
    buffer.kind.componentCount() *
    buffer.componentType.size()

  glBindBuffer(buffer.target, buffer.bufferId)
  glBufferData(
    buffer.target,
    byteLength,
    data,
    GL_STATIC_DRAW
  )

proc getErrorLog(
  id: GLuint,
  path: string,
  lenProc: typeof(glGetShaderiv),
  strProc: typeof(glGetShaderInfoLog)
): string =
  ## Gets the error log from compiling or linking shaders.
  var length: GLint = 0
  lenProc(id, GL_INFO_LOG_LENGTH, length.addr)
  var log = newString(length.int)
  strProc(id, length, nil, log.cstring)
  when defined(emscripten):
    result = log
  else:
    if log.startsWith("Compute info"):
      log = log[25 .. ^1]
    let clickable =
      if ')' in log:
        &"{path}({log[2 .. log.find(')')]}"
      else:
        path
    result = &"{clickable}: {log}"

proc compileShaderFiles(vert, frag: (string, string)): GLuint =
  ## Compiles the shader files and links them into a program.
  var vertShader, fragShader: GLuint

  block shaders:
    var vertShaderArray = allocCStringArray([vert[1]])
    var fragShaderArray = allocCStringArray([frag[1]])
    var isCompiled: GLint

    vertShader = glCreateShader(GL_VERTEX_SHADER)
    glShaderSource(vertShader, 1, vertShaderArray, nil)
    glCompileShader(vertShader)
    glGetShaderiv(vertShader, GL_COMPILE_STATUS, isCompiled.addr)

    if isCompiled == 0:
      echo "Vertex shader compilation failed:"
      echo "--------------------------------"
      echo vert[1]
      echo "--------------------------------"
      echo getErrorLog(
        vertShader,
        vert[0],
        glGetShaderiv,
        glGetShaderInfoLog
      )
      quit()

    fragShader = glCreateShader(GL_FRAGMENT_SHADER)
    glShaderSource(fragShader, 1, fragShaderArray, nil)
    glCompileShader(fragShader)
    glGetShaderiv(fragShader, GL_COMPILE_STATUS, isCompiled.addr)

    if isCompiled == 0:
      echo "Fragment shader compilation failed:"
      echo "--------------------------------"
      echo frag[1]
      echo "--------------------------------"
      echo getErrorLog(
        fragShader,
        frag[0],
        glGetShaderiv,
        glGetShaderInfoLog
      )
      quit()

    deallocCStringArray(vertShaderArray)
    deallocCStringArray(fragShaderArray)

  result = glCreateProgram()
  glAttachShader(result, vertShader)
  glAttachShader(result, fragShader)
  glLinkProgram(result)

  var isLinked: GLint
  glGetProgramiv(result, GL_LINK_STATUS, isLinked.addr)
  if isLinked == 0:
    echo "Linking shaders failed:"
    echo getErrorLog(result, "", glGetProgramiv, glGetProgramInfoLog)
    quit()

proc readAttribsAndUniforms(shader: Shader) =
  ## Reads active attributes and uniforms from the shader program.
  block attributes:
    var activeAttribCount: GLint
    glGetProgramiv(
      shader.programId,
      GL_ACTIVE_ATTRIBUTES,
      activeAttribCount.addr
    )

    for i in 0 ..< activeAttribCount:
      var
        buf = newString(64)
        length, size: GLint
        kind: GLenum
      glGetActiveAttrib(
        shader.programId,
        i.GLuint,
        len(buf).GLint,
        length.addr,
        size.addr,
        kind.addr,
        cast[cstring](buf[0].addr)
      )
      buf.setLen(length)
      let location = glGetAttribLocation(shader.programId, buf.cstring)
      shader.attribs.add(ShaderAttrib(name: move(buf), location: location))

  block uniforms:
    var activeUniformCount: GLint
    glGetProgramiv(
      shader.programId,
      GL_ACTIVE_UNIFORMS,
      activeUniformCount.addr
    )

    for i in 0 ..< activeUniformCount:
      var
        buf = newString(64)
        length, size: GLint
        kind: GLenum
      glGetActiveUniform(
        shader.programId,
        i.GLuint,
        len(buf).GLint,
        length.addr,
        size.addr,
        kind.addr,
        cast[cstring](buf[0].addr)
      )
      buf.setLen(length)

      if buf.endsWith("[0]"):
        continue

      let location = glGetUniformLocation(shader.programId, buf.cstring)
      shader.uniforms.add(
        ShaderUniformState(
          name: move(buf),
          location: location
        )
      )

proc newShader*(vert, frag: (string, string)): Shader =
  result = Shader()
  result.paths = @[vert[0], frag[0]]
  result.programId = compileShaderFiles(vert, frag)
  result.readAttribsAndUniforms()

proc hasUniform*(shader: Shader, name: string): bool =
  for uniform in shader.uniforms:
    if uniform.name == name:
      return true
  false

proc setUniform(
  shader: Shader,
  name: string,
  componentType: GLenum,
  kind: BufferKind,
  values: array[64, uint8]
) =
  for uniform in shader.uniforms.mitems:
    if uniform.name == name:
      if uniform.componentType != componentType or
        uniform.kind != kind or
        uniform.values != values:
        uniform.componentType = componentType
        uniform.kind = kind
        uniform.values = values
        uniform.changed = true
      return

  echo &"Ignoring setUniform for \"{name}\", not active"

proc setUniform(
  shader: Shader,
  name: string,
  componentType: GLenum,
  kind: BufferKind,
  values: array[16, float32]
) =
  assert componentType == cGL_FLOAT
  setUniform(
    shader,
    name,
    componentType,
    kind,
    cast[array[64, uint8]](values)
  )

proc setUniform(
  shader: Shader,
  name: string,
  componentType: GLenum,
  kind: BufferKind,
  values: array[16, int32]
) =
  assert componentType == cGL_INT
  setUniform(
    shader,
    name,
    componentType,
    kind,
    cast[array[64, uint8]](values)
  )

proc raiseUniformVarargsException(name: string, count: int) =
  raise newException(
    Exception,
    &"{count} varargs is more than the maximum of 4 for \"{name}\""
  )

proc raiseUniformComponentTypeException(
  name: string,
  componentType: GLenum
) =
  let hex = toHex(componentType.uint32)
  raise newException(
    Exception,
    &"Uniform \"{name}\" is of unexpected component type {hex}"
  )

proc raiseUniformKindException(name: string, kind: BufferKind) =
  raise newException(
    Exception,
    &"Uniform \"{name}\" is of unexpected kind {kind}"
  )

proc setUniform*(shader: Shader, name: string, args: varargs[int32]) =
  var values: array[16, int32]
  for i in 0 ..< min(len(args), 16):
    values[i] = args[i]

  var kind: BufferKind
  case len(args):
  of 1:
    kind = bkSCALAR
  of 2:
    kind = bkVEC2
  of 3:
    kind = bkVEC3
  of 4:
    kind = bkVEC4
  else:
    raiseUniformVarargsException(name, len(args))

  shader.setUniform(name, cGL_INT, kind, values)

proc setUniform*(shader: Shader, name: string, args: varargs[float32]) =
  var values: array[16, float32]
  for i in 0 ..< min(len(args), 16):
    values[i] = args[i]

  var kind: BufferKind
  case len(args):
  of 1:
    kind = bkSCALAR
  of 2:
    kind = bkVEC2
  of 3:
    kind = bkVEC3
  of 4:
    kind = bkVEC4
  else:
    raiseUniformVarargsException(name, len(args))

  shader.setUniform(name, cGL_FLOAT, kind, values)

proc setUniform*(shader: Shader, name: string, v: Vec2) =
  var values: array[16, float32]
  values[0] = v.x
  values[1] = v.y
  shader.setUniform(name, cGL_FLOAT, bkVEC2, values)

proc setUniform*(shader: Shader, name: string, v: Vec3) =
  var values: array[16, float32]
  values[0] = v.x
  values[1] = v.y
  values[2] = v.z
  shader.setUniform(name, cGL_FLOAT, bkVEC3, values)

proc setUniform*(shader: Shader, name: string, v: Vec4) =
  var values: array[16, float32]
  values[0] = v.x
  values[1] = v.y
  values[2] = v.z
  values[3] = v.w
  shader.setUniform(name, cGL_FLOAT, bkVEC4, values)

proc setUniform*(shader: Shader, name: string, m: Mat4) =
  shader.setUniform(
    name,
    cGL_FLOAT,
    bkMAT4,
    cast[array[16, float32]](m)
  )

proc setUniform*(shader: Shader, name: string, b: bool) =
  var values: array[16, int32]
  values[0] = b.int32
  shader.setUniform(name, cGL_INT, bkSCALAR, values)

proc bindUniforms*(shader: Shader) =
  for uniform in shader.uniforms.mitems:
    if uniform.componentType == 0.GLenum:
      continue
    if not uniform.changed:
      continue

    if uniform.componentType == cGL_INT:
      let values = cast[array[16, GLint]](uniform.values)
      case uniform.kind:
      of bkSCALAR:
        glUniform1i(uniform.location, values[0])
      of bkVEC2:
        glUniform2i(uniform.location, values[0], values[1])
      of bkVEC3:
        glUniform3i(uniform.location, values[0], values[1], values[2])
      of bkVEC4:
        glUniform4i(
          uniform.location,
          values[0],
          values[1],
          values[2],
          values[3]
        )
      else:
        raiseUniformKindException(uniform.name, uniform.kind)
    elif uniform.componentType == cGL_FLOAT:
      let values = cast[array[16, float32]](uniform.values)
      case uniform.kind:
      of bkSCALAR:
        glUniform1f(uniform.location, values[0])
      of bkVEC2:
        glUniform2f(uniform.location, values[0], values[1])
      of bkVEC3:
        glUniform3f(uniform.location, values[0], values[1], values[2])
      of bkVEC4:
        glUniform4f(
          uniform.location,
          values[0],
          values[1],
          values[2],
          values[3]
        )
      of bkMAT4:
        glUniformMatrix4fv(
          uniform.location,
          1,
          GL_FALSE,
          values[0].unsafeAddr
        )
      else:
        raiseUniformKindException(uniform.name, uniform.kind)
    else:
      raiseUniformComponentTypeException(
        uniform.name,
        uniform.componentType
      )

    uniform.changed = false

proc uploadAtlas*(drawer: Drawer, image: Image) =
  ## Replace the GPU atlas texture from a CPU image.
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, drawer.atlasTexture)
  glTexImage2D(
    GL_TEXTURE_2D,
    0,
    GL_RGBA8.GLint,
    image.width.GLint,
    image.height.GLint,
    0,
    GL_RGBA,
    GL_UNSIGNED_BYTE,
    cast[pointer](image.data[0].addr)
  )
  glGenerateMipmap(GL_TEXTURE_2D)

proc newDrawer*(window: Window, image: Image): Drawer =
  ## Creates a new OpenGL drawer and eagerly uploads its resources.
  discard window
  result = Drawer()
  result.layers[0] = @[]
  result.layers[1] = @[]
  result.currentLayer = 0
  result.layerStack = @[]

  when defined(emscripten):
    result.shader = newShader(
      ("SilkyVert", toGLSL(silkyVert, glslES3)),
      ("SilkyFrag", toGLSL(silkyFrag, glslES3))
    )
  else:
    result.shader = newShader(
      ("SilkyVert", toGLSL(silkyVert, glslDesktop)),
      ("SilkyFrag", toGLSL(silkyFrag, glslDesktop))
    )

  glGenTextures(1, result.atlasTexture.addr)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, result.atlasTexture)
  glTexParameteri(
    GL_TEXTURE_2D,
    GL_TEXTURE_MIN_FILTER,
    GL_LINEAR_MIPMAP_LINEAR.GLint
  )
  glTexParameteri(
    GL_TEXTURE_2D,
    GL_TEXTURE_MAG_FILTER,
    GL_LINEAR.GLint
  )
  glTexParameteri(
    GL_TEXTURE_2D,
    GL_TEXTURE_WRAP_S,
    GL_CLAMP_TO_EDGE.GLint
  )
  glTexParameteri(
    GL_TEXTURE_2D,
    GL_TEXTURE_WRAP_T,
    GL_CLAMP_TO_EDGE.GLint
  )
  result.uploadAtlas(image)

  glGenVertexArrays(1, result.vao.addr)
  glBindVertexArray(result.vao)
  let program = result.shader.programId

  glGenBuffers(1, result.instanceVbo.addr)
  glBindBuffer(GL_ARRAY_BUFFER, result.instanceVbo)
  glBufferData(GL_ARRAY_BUFFER, 0, nil, GL_STREAM_DRAW)

  let stride = sizeof(DrawerVertex).GLsizei

  template setAttr(
    name: string,
    size: GLint,
    xtype: GLenum,
    normalized: GLboolean,
    offset: int
  ) =
    let loc = glGetAttribLocation(program, name)
    if loc != -1:
      glEnableVertexAttribArray(loc.GLuint)
      glVertexAttribPointer(
        loc.GLuint,
        size,
        xtype,
        normalized,
        stride,
        cast[pointer](offset)
      )
    else:
      echo "[Warning] Attribute not found: ", name

  setAttr("pos", 2, cGL_FLOAT, GL_FALSE, offsetof(DrawerVertex, pos))
  setAttr("uv", 2, cGL_FLOAT, GL_FALSE, offsetof(DrawerVertex, uv))
  setAttr(
    "color",
    4,
    GL_UNSIGNED_BYTE,
    GL_TRUE,
    offsetof(DrawerVertex, color)
  )
  setAttr(
    "clipPos",
    2,
    cGL_FLOAT,
    GL_FALSE,
    offsetof(DrawerVertex, clipPos)
  )
  setAttr(
    "clipSize",
    2,
    cGL_FLOAT,
    GL_FALSE,
    offsetof(DrawerVertex, clipSize)
  )
  setAttr(
    "maskUv",
    2,
    cGL_FLOAT,
    GL_FALSE,
    offsetof(DrawerVertex, maskUv)
  )

  glBindBuffer(GL_ARRAY_BUFFER, 0)
  glBindVertexArray(0)

proc beginFrame*(drawer: Drawer, window: Window, size: IVec2) =
  ## Prepares the OpenGL drawer for a new frame.
  discard window
  glViewport(0, 0, size.x, size.y)

proc clearScreen*(drawer: Drawer, color: ColorRGBX) =
  ## Clears the OpenGL framebuffer.
  discard drawer
  let c = color.color
  glClearColor(c.r, c.g, c.b, c.a)
  glClear(GL_COLOR_BUFFER_BIT)

proc endFrame*(
  drawer: Drawer,
  image: Image,
  size: Vec2,
  quads: pointer,
  quadCount: int
) =
  ## Flushes the queued quads through OpenGL.
  if quadCount == 0:
    return

  # Own the viewport: the shader maps quads to clip space assuming
  # the viewport covers the whole framebuffer. A host that rendered
  # its own passes first may have left a smaller viewport bound,
  # which would draw the UI offset and scaled while hit testing
  # stays in window space.
  glViewport(0, 0, GLsizei(size.x), GLsizei(size.y))

  glEnable(GL_BLEND)
  glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)

  glBindBuffer(GL_ARRAY_BUFFER, drawer.instanceVbo)
  glBufferData(
    GL_ARRAY_BUFFER,
    quadCount * sizeof(DrawerVertex),
    quads,
    GL_STREAM_DRAW
  )

  glUseProgram(drawer.shader.programId)
  drawer.shader.setUniform("viewportSize", size)
  drawer.shader.setUniform(
    "atlasSize",
    vec2(image.width.float32, image.height.float32)
  )
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, drawer.atlasTexture)
  drawer.shader.setUniform("atlasSampler", 0)
  drawer.shader.bindUniforms()

  glBindVertexArray(drawer.vao)
  glDrawArrays(GL_TRIANGLES, 0, quadCount.GLsizei)

  glBindVertexArray(0)
  glUseProgram(0)
  glBindTexture(GL_TEXTURE_2D, 0)
  glDisable(GL_BLEND)

proc atlasTextureId*(drawer: Drawer): GLuint =
  ## Returns the OpenGL texture id of the atlas.
  drawer.atlasTexture
