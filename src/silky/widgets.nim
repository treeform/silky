import 
  std/[tables],
  vmath, bumpy, chroma, windy

export tables

type 
  Theme* = object
    padding*: int = 8
    spacing*: int = 4
    border*: int = 8
    textPadding*: int = 4
    headerHeight*: int = 32
    defaultTextColor*: ColorRGBX = rgbx(255, 255, 255, 255)
    
  WindowState* = ref object
    pos*: Vec2
    size*: Vec2
    minimized*: bool

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
    sk.pushFrame(windowState.pos, windowState.size)
    sk.draw9Patch("window.9patch", 14, sk.pos, sk.size)

    sk.pushFrame(windowState.pos + vec2(theme.border), vec2(windowState.size.x - theme.border.float32 * 2, theme.headerHeight))
    sk.draw9Patch("header.9patch", 4, sk.pos, sk.size)
    sk.at += vec2(theme.textPadding, 0)
    discard sk.drawText(sk.textStyle, title, sk.at, theme.defaultTextColor)
    sk.popFrame()
    
    sk.pushFrame(
      windowState.pos + vec2(theme.border, theme.border + theme.headerHeight),
      windowState.size - vec2(theme.border * 2, theme.border * 2 + theme.headerHeight)
    )
    sk.draw9Patch("frame.9patch", 4, sk.pos, sk.size)
    sk.at += vec2(theme.padding, 0)
    body
    sk.popFrame()
    sk.popFrame()
    
template button*(label: string, body) =
  let textSize = sk.getTextSize(sk.textStyle, label) 
  let buttonSize = textSize + vec2(theme.textPadding) * 2
  if sk.layer == sk.topLayer and window.mousePos.vec2.overlaps(rect(sk.at, buttonSize)):
    if window.buttonReleased[MouseLeft]:
      body
    elif window.buttonDown[MouseLeft]:
      sk.draw9Patch("button.down.9patch", 8, sk.at, buttonSize, rgbx(255, 255, 255, 255))
    else:
      sk.draw9Patch("button.hover.9patch", 8, sk.at, buttonSize, rgbx(255, 255, 255, 255))
  else:
    sk.draw9Patch("button.9patch", 8, sk.at, buttonSize)
  discard sk.drawText(sk.textStyle, label, sk.at + vec2(theme.textPadding), rgbx(255, 255, 255, 255))
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