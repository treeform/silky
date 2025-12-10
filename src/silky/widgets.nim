import
  std/[tables, unicode, times],
  vmath, bumpy, chroma, windy,
  silky/textinput

export tables, textinput

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

    scrollPos*: Vec2

    scrollingX*: bool
    scrollingY*: bool
    scrollDragOffset*: Vec2

  FrameState* = ref object
    scrollPos*: Vec2
    scrollingX*: bool
    scrollingY*: bool
    scrollDragOffset*: Vec2

var
  theme*: Theme = Theme()
  windowStates*: Table[string, WindowState]
  frameStates*: Table[string, FrameState]
  textInputStates*: Table[int, InputTextState]

proc vec2(v: SomeNumber): Vec2 =
  ## Create a Vec2 from a number.
  vec2(v.float32, v.float32)

proc vec2[A, B](x: A, y: B): Vec2 =
  ## Create a Vec2 from two numbers.
  vec2(x.float32, y.float32)

template windowFrame*(title: string, show: bool, body) =
  ## Create a window frame.
  if title notin windowStates:
    windowStates[title] = WindowState(
      pos: vec2(10 + windowStates.len * (300 + theme.spacing), 10),
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

      # Draw the body.
      sk.pushFrame(
        windowState.pos + vec2(theme.border, theme.border + theme.headerHeight),
        windowState.size - vec2(theme.border * 2, theme.border * 2 + theme.headerHeight)
      )
      sk.draw9Patch("frame.9patch", 6, sk.pos, sk.size)
      sk.pushClipRect(rect(
        sk.pos.x + 1,
        sk.pos.y + 1,
        sk.size.x - 2,
        sk.size.y - 2
      ))
      sk.at += vec2(theme.padding)
      let originPos = sk.at
      sk.at -= windowState.scrollPos

      body

      # Handle scrollbar drag release
      if windowState.scrollingY and (window.buttonReleased[MouseLeft] or not window.buttonDown[MouseLeft]):
        windowState.scrollingY = false
      if windowState.scrollingX and (window.buttonReleased[MouseLeft] or not window.buttonDown[MouseLeft]):
        windowState.scrollingX = false

      # Deal with scroll delta.
      if not windowState.scrollingY and window.scrollDelta.y != 0:
        windowState.scrollPos.y -= window.scrollDelta.y * 10
      if not windowState.scrollingX and window.scrollDelta.x != 0:
        windowState.scrollPos.x -= window.scrollDelta.x * 10
      windowState.scrollPos = max(windowState.scrollPos, vec2(0, 0))

      # Deal with scrolling.
      sk.stretchAt += vec2(16) # Add some extra stretch.
      let stretch = sk.stretchAt + windowState.scrollPos - originPos
      let scrollMax = stretch - sk.size

      # Limit scroll position to the max scrollable amount.
      if scrollMax.y > 0:
        windowState.scrollPos.y = min(windowState.scrollPos.y, scrollMax.y)
      else:
        windowState.scrollPos.y = 0
      if scrollMax.x > 0:
        windowState.scrollPos.x = min(windowState.scrollPos.x, scrollMax.x)
      else:
        windowState.scrollPos.x = 0

      # Draw the scrollbar if the content is too large in the Y direction.
      if stretch.y > sk.size.y:
        let scrollSize = stretch.y
        let scrollbarTrackRect = rect(
          sk.pos.x + sk.size.x - 10,
          sk.pos.y + 2,
          8,
          sk.size.y - 4 - 10
        )
        sk.draw9Patch("scrollbar.track.9patch", 4, scrollbarTrackRect.xy, scrollbarTrackRect.wh)

        let scrollPosPercent = if scrollMax.y > 0: windowState.scrollPos.y / scrollMax.y else: 0.0
        let scrollSizePercent = sk.size.y / scrollSize
        let scrollbarHandleRect = rect(
          scrollbarTrackRect.x,
          scrollbarTrackRect.y + (scrollbarTrackRect.h - (scrollbarTrackRect.h * scrollSizePercent)) * scrollPosPercent,
          8,
          scrollbarTrackRect.h * scrollSizePercent
        )

        # Handle scrollbar Y dragging
        if windowState.scrollingY:
          # Calculate new scroll position from mouse position
          let mouseY = window.mousePos.vec2.y
          let relativeY = mouseY - windowState.scrollDragOffset.y - scrollbarTrackRect.y
          let availableTrackHeight = scrollbarTrackRect.h - scrollbarHandleRect.h
          if availableTrackHeight > 0:
            let newScrollPosPercent = clamp(relativeY / availableTrackHeight, 0.0, 1.0)
            windowState.scrollPos.y = newScrollPosPercent * scrollMax.y
        elif sk.layer == sk.topLayer and window.mousePos.vec2.overlaps(scrollbarHandleRect):
          if window.buttonPressed[MouseLeft]:
            windowState.scrollingY = true
            # Store offset from top of handle to mouse
            windowState.scrollDragOffset.y = window.mousePos.vec2.y - scrollbarHandleRect.y

        sk.draw9Patch("scrollbar.9patch", 4, scrollbarHandleRect.xy, scrollbarHandleRect.wh)

      # Deal with scrolling X direction.
      if stretch.x > sk.size.x:
        let scrollSize = stretch.x
        let scrollbarTrackRect = rect(
          sk.pos.x + 2,
          sk.pos.y + sk.size.y - 10,
          sk.size.x - 4 - 10,
          8
        )
        sk.draw9Patch("scrollbar.track.9patch", 4, scrollbarTrackRect.xy, scrollbarTrackRect.wh)

        let scrollPosPercent = if scrollMax.x > 0: windowState.scrollPos.x / scrollMax.x else: 0.0
        let scrollSizePercent = sk.size.x / scrollSize
        let scrollbarHandleRect = rect(
          scrollbarTrackRect.x + (scrollbarTrackRect.w - (scrollbarTrackRect.w * scrollSizePercent)) * scrollPosPercent,
          scrollbarTrackRect.y,
          scrollbarTrackRect.w * scrollSizePercent,
          8
        )

        # Handle scrollbar X dragging
        if windowState.scrollingX:
          # Calculate new scroll position from mouse position
          let mouseX = window.mousePos.vec2.x
          let relativeX = mouseX - windowState.scrollDragOffset.x - scrollbarTrackRect.x
          let availableTrackWidth = scrollbarTrackRect.w - scrollbarHandleRect.w
          if availableTrackWidth > 0:
            let newScrollPosPercent = clamp(relativeX / availableTrackWidth, 0.0, 1.0)
            windowState.scrollPos.x = newScrollPosPercent * scrollMax.x
        elif sk.layer == sk.topLayer and window.mousePos.vec2.overlaps(scrollbarHandleRect):
          if window.buttonPressed[MouseLeft]:
            windowState.scrollingX = true
            # Store offset from left of handle to mouse
            windowState.scrollDragOffset.x = window.mousePos.vec2.x - scrollbarHandleRect.x

        sk.draw9Patch("scrollbar.9patch", 4, scrollbarHandleRect.xy, scrollbarHandleRect.wh)

      sk.popFrame()
      sk.popClipRect()

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
        windowState.size.y = max(windowState.size.y, float32(theme.headerHeight * 2 + theme.border * 2))
      else:
        if window.mousePos.vec2.overlaps(resizeHandleRect):
          if window.buttonPressed[MouseLeft]:
            windowState.resizing = true
            windowState.resizeOffset = window.mousePos.vec2 - windowState.size
      sk.drawImage("resize", resizeHandleRect.xy)

    sk.popFrame()

template frame*(id: string, framePos, frameSize: Vec2, body) =
  ## Frame with scrollbars similar to a window body.
  if id notin frameStates:
    frameStates[id] = FrameState()
  let frameState = frameStates[id]

  sk.pushFrame(framePos, frameSize)
  sk.draw9Patch("frame.9patch", 6, sk.pos, sk.size)
  sk.pushClipRect(rect(
    sk.pos.x + 1,
    sk.pos.y + 1,
    sk.size.x - 2,
    sk.size.y - 2
  ))

  sk.at = sk.pos + vec2(theme.padding)
  let originPos = sk.at
  sk.at -= frameState.scrollPos

  body

  # Handle scrollbar drag release
  if frameState.scrollingY and (window.buttonReleased[MouseLeft] or not window.buttonDown[MouseLeft]):
    frameState.scrollingY = false
  if frameState.scrollingX and (window.buttonReleased[MouseLeft] or not window.buttonDown[MouseLeft]):
    frameState.scrollingX = false

  # Scroll wheel handling (only when mouse over frame)
  if window.mousePos.vec2.overlaps(rect(sk.pos, sk.size)):
    if not frameState.scrollingY and window.scrollDelta.y != 0:
      frameState.scrollPos.y -= window.scrollDelta.y * 10
    if not frameState.scrollingX and window.scrollDelta.x != 0:
      frameState.scrollPos.x -= window.scrollDelta.x * 10
  frameState.scrollPos = max(frameState.scrollPos, vec2(0, 0))

  # Stretch and clamp scroll positions
  sk.stretchAt += vec2(16)
  let stretch = sk.stretchAt + frameState.scrollPos - originPos
  let scrollMax = stretch - sk.size

  if scrollMax.y > 0:
    frameState.scrollPos.y = min(frameState.scrollPos.y, scrollMax.y)
  else:
    frameState.scrollPos.y = 0

  if scrollMax.x > 0:
    frameState.scrollPos.x = min(frameState.scrollPos.x, scrollMax.x)
  else:
    frameState.scrollPos.x = 0

  # Draw Y scrollbar
  if stretch.y > sk.size.y:
    let scrollSize = stretch.y
    let scrollbarTrackRect = rect(
      sk.pos.x + sk.size.x - 10,
      sk.pos.y + 2,
      8,
      sk.size.y - 4 - 10
    )
    sk.draw9Patch("scrollbar.track.9patch", 4, scrollbarTrackRect.xy, scrollbarTrackRect.wh)

    let scrollPosPercent = if scrollMax.y > 0: frameState.scrollPos.y / scrollMax.y else: 0.0
    let scrollSizePercent = sk.size.y / scrollSize
    let scrollbarHandleRect = rect(
      scrollbarTrackRect.x,
      scrollbarTrackRect.y + (scrollbarTrackRect.h - (scrollbarTrackRect.h * scrollSizePercent)) * scrollPosPercent,
      8,
      scrollbarTrackRect.h * scrollSizePercent
    )

    # Handle scrollbar Y dragging
    if frameState.scrollingY:
      let mouseY = window.mousePos.vec2.y
      let relativeY = mouseY - frameState.scrollDragOffset.y - scrollbarTrackRect.y
      let availableTrackHeight = scrollbarTrackRect.h - scrollbarHandleRect.h
      if availableTrackHeight > 0:
        let newScrollPosPercent = clamp(relativeY / availableTrackHeight, 0.0, 1.0)
        frameState.scrollPos.y = newScrollPosPercent * scrollMax.y
    elif sk.layer == sk.topLayer and window.mousePos.vec2.overlaps(scrollbarHandleRect):
      if window.buttonPressed[MouseLeft]:
        frameState.scrollingY = true
        frameState.scrollDragOffset.y = window.mousePos.vec2.y - scrollbarHandleRect.y

    sk.draw9Patch("scrollbar.9patch", 4, scrollbarHandleRect.xy, scrollbarHandleRect.wh)

  # Draw X scrollbar
  if stretch.x > sk.size.x:
    let scrollSize = stretch.x
    let scrollbarTrackRect = rect(
      sk.pos.x + 2,
      sk.pos.y + sk.size.y - 10,
      sk.size.x - 4 - 10,
      8
    )
    sk.draw9Patch("scrollbar.track.9patch", 4, scrollbarTrackRect.xy, scrollbarTrackRect.wh)

    let scrollPosPercent = if scrollMax.x > 0: frameState.scrollPos.x / scrollMax.x else: 0.0
    let scrollSizePercent = sk.size.x / scrollSize
    let scrollbarHandleRect = rect(
      scrollbarTrackRect.x + (scrollbarTrackRect.w - (scrollbarTrackRect.w * scrollSizePercent)) * scrollPosPercent,
      scrollbarTrackRect.y,
      scrollbarTrackRect.w * scrollSizePercent,
      8
    )

    # Handle scrollbar X dragging
    if frameState.scrollingX:
      let mouseX = window.mousePos.vec2.x
      let relativeX = mouseX - frameState.scrollDragOffset.x - scrollbarTrackRect.x
      let availableTrackWidth = scrollbarTrackRect.w - scrollbarHandleRect.w
      if availableTrackWidth > 0:
        let newScrollPosPercent = clamp(relativeX / availableTrackWidth, 0.0, 1.0)
        frameState.scrollPos.x = newScrollPosPercent * scrollMax.x
    elif sk.layer == sk.topLayer and window.mousePos.vec2.overlaps(scrollbarHandleRect):
      if window.buttonPressed[MouseLeft]:
        frameState.scrollingX = true
        frameState.scrollDragOffset.x = window.mousePos.vec2.x - scrollbarHandleRect.x

    sk.draw9Patch("scrollbar.9patch", 4, scrollbarHandleRect.xy, scrollbarHandleRect.wh)

  sk.popFrame()
  sk.popClipRect()

template button*(label: string, body) =
  ## Create a button.
  let
    textSize = sk.getTextSize(sk.textStyle, label)
    buttonSize = textSize + vec2(theme.padding) * 2
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
  ## Create an icon button.
  let
    m2 = vec2(8, 8)
    s2 = vec2(32, 32) + vec2(8, 8) * 2
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
  ## Create a group.
  sk.pushFrame(sk.pos + p, sk.size - p)
  body
  sk.popFrame()

template frame*(p, s: Vec2, body) =
  ## Create a frame.
  sk.pushFrame(p, s)
  sk.draw9Patch("window.9patch", 14, sk.pos, sk.size)
  body
  sk.popFrame()

template ribbon*(p, s: Vec2, tint: ColorRGBX, body) =
  ## Create a ribbon.
  sk.pushFrame(p, s)
  sk.drawRect(sk.pos, sk.size, tint)
  sk.at = sk.pos
  body
  sk.popFrame()

template image*(image: string, tint = rgbx(255, 255, 255, 255)) =
  ## Draw an image.
  sk.drawImage(image, sk.at, tint)
  sk.at.x += sk.getImageSize(image).x
  sk.at.x += sk.padding

template text*(t: string) =
  ## Draw text.
  let textSize = sk.drawText(sk.textStyle, t, sk.at, rgbx(255, 255, 255, 255))
  sk.advance(textSize)

template h1text*(t: string) =
  ## Draw H1 text.
  let textSize = sk.drawText("H1", t, sk.at, rgbx(255, 255, 255, 255))
  sk.advance(textSize)

template scrubber*(p, s: Vec2) =
  ## Create a scrubber.
  sk.pushFrame(p, s)
  sk.draw9Patch("track.9patch", 16, sk.pos, sk.size)
  sk.popFrame()

template inputText*(id: int, t: var string) =
  ## Create an input text.
  let font = sk.atlas.fonts[sk.textStyle]
  let height = font.lineHeight + theme.padding.float32 * 2
  let width = sk.size.x - theme.padding.float32 * 3
  sk.pushFrame(sk.at, vec2(width, height))

  if id notin textInputStates:
    textInputStates[id] = InputTextState(focused: false)
    textInputStates[id].setText(t)

  let textInputState = textInputStates[id]

  # Handle focus
  if window.buttonPressed[MouseLeft]:
    if window.mousePos.vec2.overlaps(rect(sk.pos, sk.size)):
      textInputState.focused = true
      # TODO: Set cursor position based on click
    else:
      textInputState.focused = false

  # Handle input if focused
  if textInputState.focused:
    sk.draw9Patch("frame.9patch", 6, sk.pos, sk.size, rgbx(220, 220, 255, 255))

    # Process runes
    for r in sk.inputRunes:
      textInputState.typeCharacter(r)

    textInputState.handleInput(window)

    # Sync back
    t = textInputState.getText()
  else:
    sk.draw9Patch("frame.9patch", 6, sk.pos, sk.size)

  # Draw text
  # We should probably clip or scroll text
  let padding = vec2(theme.padding)
  discard sk.drawText(sk.textStyle, t, sk.at + padding, theme.defaultTextColor)

  # Draw cursor
  if textInputState.focused and (epochTime() * 2).int mod 2 == 0:
    # Calculate cursor position
    # This is inefficient, measuring text up to cursor
    # But fine for now
    let textBeforeCursor = $textInputState.runes[0 ..< min(textInputState.cursor, textInputState.runes.len)]
    let textSize = sk.getTextSize(sk.textStyle, textBeforeCursor)
    let cursorHeight = sk.atlas.fonts[sk.textStyle].lineHeight

    let cursorX = sk.at.x + padding.x + textSize.x
    let cursorY = sk.at.y + padding.y

    sk.drawRect(vec2(cursorX, cursorY), vec2(2, cursorHeight), theme.defaultTextColor)

  sk.popFrame()
  sk.advance(vec2(width, height))
