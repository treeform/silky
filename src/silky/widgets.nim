import vmath, bumpy, chroma


template button*(label: string, body) =
  let m2 = vec2(8, 8)
  let width = sk.getTextSize(sk.textStyle, label).x + sk.padding * 2
  let s2 = vec2(width, 32) + vec2(8, 8) * 2
  if sk.layer == sk.topLayer and window.mousePos.vec2.overlaps(rect(sk.at - m2, s2)):
    if window.buttonReleased[MouseLeft]:
      body
    elif window.buttonDown[MouseLeft]:
      echo "down"
      sk.draw9Patch("button.down.9patch", 8, sk.at - m2, s2, rgbx(255, 255, 255, 255))
    else:
      sk.draw9Patch("button.hover.9patch", 8, sk.at - m2, s2, rgbx(255, 255, 255, 255))
  else:
    sk.draw9Patch("button.9patch", 8, sk.at - m2, s2)
  sk.drawText(sk.textStyle, label, sk.at + vec2(sk.padding, 0), rgbx(255, 255, 255, 255))
  sk.at.x += width + sk.padding * 3

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
  sk.drawText(sk.textStyle, t, sk.at, rgbx(255, 255, 255, 255))
  sk.at.x += sk.padding

template h1text*(t: string) =
  sk.drawText("H1", t, sk.at, rgbx(255, 255, 255, 255))
  sk.at.x += sk.padding

template scrubber*(p, s: Vec2) =
  sk.pushFrame(p, s)
  sk.draw9Patch("track.9patch", 16, sk.pos, sk.size)
  sk.popFrame()