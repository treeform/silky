import
  std/math,
  pixie, vmath, windy

const
  BackendName* = "CPU"

type
  DrawerVertex* {.packed.} = object
    ## Raw triangle layout consumed by the CPU drawer.
    pos*: Vec2
    uv*: Vec2
    color*: ColorRGBX
    clipPos*: Vec2
    clipSize*: Vec2
    maskUv*: Vec2

  Drawer* = ref object
    ## CPU-backed drawer state.
    window: Window
    framebuffer: Image
    clearColor: ColorRGBX
    layers*: array[2, seq[DrawerVertex]]
    currentLayer*: int
    layerStack*: seq[int]

proc clampFramebufferSize(size: IVec2): IVec2 =
  ivec2(max(1'i32, size.x), max(1'i32, size.y))

proc clampFramebufferSize(size: Vec2): IVec2 =
  clampFramebufferSize(ivec2(size.x.int32, size.y.int32))

proc ensureFramebuffer(drawer: Drawer, size: IVec2) =
  let safeSize = clampFramebufferSize(size)
  if drawer.framebuffer == nil or
    drawer.framebuffer.width != safeSize.x or
    drawer.framebuffer.height != safeSize.y:
    drawer.framebuffer = newImage(safeSize.x.int, safeSize.y.int)
    drawer.framebuffer.fill(drawer.clearColor)

proc ensureFramebuffer(drawer: Drawer, size: Vec2) =
  drawer.ensureFramebuffer(clampFramebufferSize(size))

proc mulByte(a, b: uint8): uint8 {.inline.} =
  ((a.uint32 * b.uint32 + 127) div 255).uint8

proc mixByte(a, b, t: uint8): uint8 {.inline.} =
  (((a.uint32 * (255'u32 - t.uint32)) + (b.uint32 * t.uint32) +
      127) div 255).uint8

proc clampByte(value: float32): uint8 {.inline.} =
  if value <= 0:
    0'u8
  elif value >= 255:
    255'u8
  else:
    round(value).uint8

proc interpolate(a, b, c: Vec2, wa, wb, wc: float32): Vec2 {.inline.} =
  a * wa + b * wb + c * wc

proc interpolate(
  a, b, c: ColorRGBX,
  wa, wb, wc: float32
): ColorRGBX {.inline.} =
  rgbx(
    clampByte(a.r.float32 * wa + b.r.float32 * wb + c.r.float32 * wc),
    clampByte(a.g.float32 * wa + b.g.float32 * wb + c.g.float32 * wc),
    clampByte(a.b.float32 * wa + b.b.float32 * wb + c.b.float32 * wc),
    clampByte(a.a.float32 * wa + b.a.float32 * wb + c.a.float32 * wc)
  )

proc edge(a, b, p: Vec2): float32 {.inline.} =
  (p.x - a.x) * (b.y - a.y) - (p.y - a.y) * (b.x - a.x)

proc sampleNearest(image: Image, uv: Vec2): ColorRGBX {.inline.} =
  let
    x = clamp(floor(uv.x).int, 0, image.width - 1)
    y = clamp(floor(uv.y).int, 0, image.height - 1)
  image.data[image.dataIndex(x, y)]

proc shadePixel(
  atlas: Image,
  uv: Vec2,
  color: ColorRGBX,
  maskUv: Vec2
): ColorRGBX {.inline.} =
  let base = atlas.sampleNearest(uv)
  if maskUv.x >= 0:
    let
      mask = atlas.sampleNearest(maskUv).r
      tintR = mixByte(255, color.r, mask)
      tintG = mixByte(255, color.g, mask)
      tintB = mixByte(255, color.b, mask)
    rgbx(
      mulByte(base.r, tintR),
      mulByte(base.g, tintG),
      mulByte(base.b, tintB),
      mulByte(base.a, color.a)
    )
  else:
    rgbx(
      mulByte(base.r, color.r),
      mulByte(base.g, color.g),
      mulByte(base.b, color.b),
      mulByte(base.a, color.a)
    )

proc blendOver(backdrop, source: ColorRGBX): ColorRGBX {.inline.} =
  let invAlpha = 255'u32 - source.a.uint32
  rgbx(
    min(255'u32, source.r.uint32 + ((backdrop.r.uint32 * invAlpha +
        127) div 255)).uint8,
    min(255'u32, source.g.uint32 + ((backdrop.g.uint32 * invAlpha +
        127) div 255)).uint8,
    min(255'u32, source.b.uint32 + ((backdrop.b.uint32 * invAlpha +
        127) div 255)).uint8,
    min(255'u32, source.a.uint32 + ((backdrop.a.uint32 * invAlpha +
        127) div 255)).uint8
  )

proc rasterTriangle(
  drawer: Drawer,
  atlas: Image,
  a, b, c: DrawerVertex
) =
  let area = edge(a.pos, b.pos, c.pos)
  if abs(area) <= 0.00001'f32:
    return

  let
    minX = clamp(floor(min(a.pos.x, min(b.pos.x, c.pos.x))).int, 0,
        drawer.framebuffer.width)
    minY = clamp(floor(min(a.pos.y, min(b.pos.y, c.pos.y))).int, 0,
        drawer.framebuffer.height)
    maxX = clamp(ceil(max(a.pos.x, max(b.pos.x, c.pos.x))).int, 0,
        drawer.framebuffer.width)
    maxY = clamp(ceil(max(a.pos.y, max(b.pos.y, c.pos.y))).int, 0,
        drawer.framebuffer.height)

  if minX >= maxX or minY >= maxY:
    return

  let positive = area > 0
  for y in minY ..< maxY:
    for x in minX ..< maxX:
      let p = vec2(x.float32 + 0.5'f32, y.float32 + 0.5'f32)
      var
        wa = edge(b.pos, c.pos, p)
        wb = edge(c.pos, a.pos, p)
        wc = edge(a.pos, b.pos, p)
      if positive:
        if wa < 0 or wb < 0 or wc < 0:
          continue
      else:
        if wa > 0 or wb > 0 or wc > 0:
          continue

      wa /= area
      wb /= area
      wc /= area

      let
        pos = interpolate(a.pos, b.pos, c.pos, wa, wb, wc)
        clipPos = interpolate(a.clipPos, b.clipPos, c.clipPos, wa, wb, wc)
        clipSize = interpolate(a.clipSize, b.clipSize, c.clipSize, wa, wb, wc)
      if pos.x < clipPos.x or
        pos.y < clipPos.y or
        pos.x > clipPos.x + clipSize.x or
        pos.y > clipPos.y + clipSize.y:
        continue

      let
        uv = interpolate(a.uv, b.uv, c.uv, wa, wb, wc)
        color = interpolate(a.color, b.color, c.color, wa, wb, wc)
        maskUv = interpolate(a.maskUv, b.maskUv, c.maskUv, wa, wb, wc)
        src = shadePixel(atlas, uv, color, maskUv)
        dstIdx = drawer.framebuffer.dataIndex(x, y)
      drawer.framebuffer.data[dstIdx] =
        blendOver(drawer.framebuffer.data[dstIdx], src)

proc newDrawer*(window: Window, image: Image): Drawer =
  ## Creates a new CPU drawer.
  discard image
  result = Drawer(
    window: window,
    clearColor: rgbx(0, 0, 0, 255),
    currentLayer: 0,
    layerStack: @[]
  )
  result.layers[0] = @[]
  result.layers[1] = @[]
  result.ensureFramebuffer(window.size)

proc beginFrame*(drawer: Drawer, window: Window, size: IVec2) =
  ## Prepares the CPU framebuffer for a new frame.
  drawer.window = window
  drawer.ensureFramebuffer(size)

proc clearScreen*(drawer: Drawer, color: ColorRGBX) =
  ## Clears the CPU framebuffer.
  drawer.clearColor = color
  drawer.ensureFramebuffer(drawer.window.size)
  drawer.framebuffer.fill(color)

proc endFrame*(
  drawer: Drawer,
  image: Image,
  size: Vec2,
  quads: pointer,
  quadCount: int
) =
  ## Rasterizes queued triangles and presents the CPU framebuffer.
  drawer.ensureFramebuffer(size)

  if quadCount > 0 and quads != nil:
    let vertices = cast[ptr UncheckedArray[DrawerVertex]](quads)
    var i = 0
    while i + 2 < quadCount:
      drawer.rasterTriangle(image, vertices[i], vertices[i + 1], vertices[i + 2])
      i += 3

  drawer.window.presentPixels(drawer.framebuffer)
