import
  std/[tables],
  vmath, bumpy, chroma, windy

export tables

type
  Theme* = object
    padding*: int = 8
    spacing*: int = 8
    border*: int = 10
    textPadding*: int = 4
    headerHeight*: int = 32
    defaultTextColor*: ColorRGBX = rgbx(255, 255, 255, 255)

  WindowState* = ref object
    pos*: Vec2
    size*: Vec2
    minimized*: bool
    dragging*: bool
    dragOffset*: Vec2
    resizing*: bool
    resizeOffset*: Vec2

var
  theme*: Theme = Theme()
  windowStates*: Table[string, WindowState]

proc vec2(v: SomeNumber): Vec2 =
  vec2(v.float32, v.float32)

proc vec2[A, B](x: A, y: B): Vec2 =
  vec2(x.float32, y.float32)

template windowFrame*(title: string, show: bool, body) =
  if title notin windowStates:
    windowStates[title] = WindowState(
      pos: vec2(100, 100),
      size: vec2(300, 400),
      minimized: false
    )
  let windowState = windowStates[title]
  if show:
    # Draw the main window frame.
    let size = if windowState.minimized:
        vec2(windowState.size.x, float32(theme.headerHeight + theme.border * 2))
      else:
        windowState.size
    sk.pushFrame(windowState.pos, size)
    sk.draw9Patch("window.9patch", 14, sk.pos, sk.size)

    # Draw the header.
    sk.pushFrame(
      windowState.pos + vec2(theme.border),
      vec2(windowState.size.x - theme.border.float32 * 2, theme.headerHeight)
    )

    # Handle dragging the window.
    if windowState.dragging and (window.buttonReleased[MouseLeft] or not window.buttonDown[MouseLeft]):
      windowState.dragging = false
    if windowState.dragging:
      windowState.pos = window.mousePos.vec2 - windowState.dragOffset
    if windowState.dragging:
      sk.draw9Patch("header.dragging.9patch", 6, sk.pos, sk.size)
    elif sk.layer == sk.topLayer and window.mousePos.vec2.overlaps(rect(sk.pos, sk.size)):
      if window.buttonPressed[MouseLeft]:
        windowState.dragging = true
        windowState.dragOffset = window.mousePos.vec2 - windowState.pos
      else:
        sk.draw9Patch("header.hover.9patch", 6, sk.pos, sk.size)
    else:
      sk.draw9Patch("header.9patch", 6, sk.pos, sk.size)
    sk.at += vec2(theme.textPadding)

    # Handle minimizing/maximizing button for the window.
    let minimizeSize = sk.getImageSize("maximized")
    let minimizeRect = rect(
      sk.at.x,
      sk.at.y,
      minimizeSize.x.float32,
      minimizeSize.y.float32
    )
    if window.mousePos.vec2.overlaps(minimizeRect):
      if window.buttonReleased[MouseLeft]:
        windowState.minimized = not windowState.minimized
    if windowState.minimized:
      sk.drawImage("minimized", minimizeRect.xy)
    else:
      sk.drawImage("maximized", minimizeRect.xy)
    sk.at.x += sk.getImageSize("maximized").x.float32 + theme.padding.float32

    # Draw the title.
    discard sk.drawText(sk.textStyle, title, sk.at, theme.defaultTextColor)

    # Handle closing button for the window.
    let closeSize = sk.getImageSize("close")
    let closeRect = rect(
      sk.at.x + sk.size.x - closeSize.x.float32 - theme.padding.float32 * 5,
      sk.at.y,
      closeSize.x.float32,
      closeSize.y.float32
    )
    if window.mousePos.vec2.overlaps(closeRect):
      if window.buttonReleased[MouseLeft]:
        show = false
    sk.drawImage("close", closeRect.xy)
    sk.popFrame()

    if not windowState.minimized:
      sk.pushClipRect(rect(
        windowState.pos.x + theme.border.float32,
        windowState.pos.y + theme.border.float32 + theme.headerHeight.float32,
        windowState.size.x - theme.border.float32 * 2,
        windowState.size.y - theme.border.float32 * 2 - theme.headerHeight.float32
      ))
      # Draw the body.
      sk.pushFrame(
        windowState.pos + vec2(theme.border, theme.border + theme.headerHeight),
        windowState.size - vec2(theme.border * 2, theme.border * 2 + theme.headerHeight)
      )
      sk.draw9Patch("frame.9patch", 6, sk.pos, sk.size)
      sk.at += vec2(theme.padding)
      body
      sk.popFrame()

      # Draw the resize handle.
      let resizeHandleSize = sk.getImageSize("resize")
      let resizeHandleRect = rect(
        sk.at.x + sk.size.x - resizeHandleSize.x.float32 - theme.border.float32,
        sk.at.y + sk.size.y - resizeHandleSize.y.float32 - theme.border.float32,
        resizeHandleSize.x.float32,
        resizeHandleSize.y.float32
      )
      if windowState.resizing and (window.buttonReleased[MouseLeft] or not window.buttonDown[MouseLeft]):
        windowState.resizing = false
      if windowState.resizing:
        windowState.size = window.mousePos.vec2 - windowState.resizeOffset
        windowState.size.x = max(windowState.size.x, 200f)
        windowState.size.y = max(windowState.size.y, float32(theme.headerHeight + theme.border * 2))
      else:
        if window.mousePos.vec2.overlaps(resizeHandleRect):
          if window.buttonPressed[MouseLeft]:
            windowState.resizing = true
            windowState.resizeOffset = window.mousePos.vec2 - windowState.size
      sk.drawImage("resize", resizeHandleRect.xy)
      sk.popClipRect()
    sk.popFrame()

template button*(label: string, body) =
  let textSize = sk.getTextSize(sk.textStyle, label)
  let buttonSize = textSize + vec2(theme.padding) * 2
  if sk.layer == sk.topLayer and window.mousePos.vec2.overlaps(rect(sk.at, buttonSize)):
    if window.buttonReleased[MouseLeft]:
      body
    elif window.buttonDown[MouseLeft]:
      sk.draw9Patch("button.down.9patch", 4, sk.at, buttonSize, rgbx(255, 255, 255, 255))
    else:
      sk.draw9Patch("button.hover.9patch", 4, sk.at, buttonSize, rgbx(255, 255, 255, 255))
  else:
    sk.draw9Patch("button.9patch", 4, sk.at, buttonSize)
  #sk.drawRect(sk.at + vec2(theme.padding), textSize, rgbx(255, 0, 0, 100))
  discard sk.drawText(sk.textStyle, label, sk.at + vec2(theme.padding), rgbx(255, 255, 255, 255))
  sk.advance(buttonSize + vec2(theme.padding))

template iconButton*(image: string, body) =
  let m2 = vec2(8, 8)
  let s2 = vec2(32, 32) + vec2(8, 8) * 2
  if sk.layer == sk.topLayer and window.mousePos.vec2.overlaps(rect(sk.at - m2, s2)):
    if window.buttonReleased[MouseLeft]:
      body
    elif window.buttonDown[MouseLeft]:
      sk.draw9Patch("button.down.9patch", 8, sk.at - m2, s2, rgbx(255, 255, 255, 255))
    else:
      sk.draw9Patch("button.hover.9patch", 8, sk.at - m2, s2, rgbx(255, 255, 255, 255))
  else:
    sk.draw9Patch("button.9patch", 8, sk.at - m2, s2)
  sk.drawImage(image, sk.at)
  sk.at += vec2(32 + m, 0)

template group*(p: Vec2, body) =
  sk.pushFrame(sk.pos + p, sk.size - p)
  body
  sk.popFrame()

template frame*(p, s: Vec2, body) =
  sk.pushFrame(p, s)
  sk.draw9Patch("window.9patch", 14, sk.pos, sk.size)
  body
  sk.popFrame()

template ribbon*(p, s: Vec2, tint: ColorRGBX, body) =
  sk.pushFrame(p, s)
  sk.drawRect(sk.pos, sk.size, tint)
  sk.at = sk.pos
  body
  sk.popFrame()

template image*(image: string, tint = rgbx(255, 255, 255, 255)) =
  sk.drawImage(image, sk.at, tint)
  sk.at.x += sk.getImageSize(image).x
  sk.at.x += sk.padding

template text*(t: string) =
  let textSize = sk.drawText(sk.textStyle, t, sk.at, rgbx(255, 255, 255, 255))
  sk.advance(textSize)

template h1text*(t: string) =
  sk.drawText("H1", t, sk.at, rgbx(255, 255, 255, 255))
  sk.at.x += sk.padding

template scrubber*(p, s: Vec2) =
  sk.pushFrame(p, s)
  sk.draw9Patch("track.9patch", 16, sk.pos, sk.size)
  sk.popFrame()
