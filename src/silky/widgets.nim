import
  std/[tables, unicode, times, strutils],
  vmath, bumpy, chroma, windy,
  silky/textinput

export tables, textinput

type
  StackDirection* = enum
    TopToBottom
    BottomToTop
    LeftToRight
    RightToLeft

  Theme* = object
    padding*: int = 8
    menuPadding*: int = 2
    spacing*: int = 8
    border*: int = 10
    textPadding*: int = 4
    headerHeight*: int = 32
    defaultTextColor*: ColorRGBX = rgbx(255, 255, 255, 255)

  SubWindowState* = ref object
    pos*: Vec2
    size*: Vec2
    minimized*: bool
    dragging*: bool
    dragOffset*: Vec2
    resizing*: bool
    resizeOffset*: Vec2

  FrameState* = ref object
    scrollPos*: Vec2
    scrollingX*: bool
    scrollingY*: bool
    scrollDragOffset*: Vec2

  ScrubberState* = ref object
    dragging*: bool
  DropDownState* = ref object
    open*: bool

  MenuState* = ref object
    ## Tracks which menus are open and their active hit areas.
    openPath*: seq[string]
    activeRects: seq[Rect]

  MenuLayout = ref object
    origin: Vec2
    width: float32
    cursorY: float32

var
  theme*: Theme = Theme()
  subWindowStates*: Table[string, SubWindowState]
  frameStates*: Table[string, FrameState]
  scrubberStates*: Table[string, ScrubberState]
  textInputStates*: Table[int, InputTextState]
  dropDownStates*: Table[string, DropDownState]
  menuState*: MenuState = MenuState(
    openPath: @[],
    activeRects: @[]
  )
  menuLayouts: seq[MenuLayout]
  menuPathStack: seq[string]

proc menuPathKey(path: seq[string]): string =
  path.join(">")

proc menuPathOpen(path: seq[string]): bool =
  menuState.openPath.len >= path.len and menuState.openPath[0 ..< path.len] == path

proc menuEnsureState() =
  if menuState.isNil:
    menuState = MenuState(
      openPath: @[],
      activeRects: @[]
    )

proc menuAddActive(rect: Rect) =
  ## Record a rect so outside-click detection can close menus.
  menuState.activeRects.add(rect)

proc menuPointInside(rects: seq[Rect], p: Vec2): bool =
  for r in rects:
    if p.overlaps(r):
      return true
  false

proc vec2(v: SomeNumber): Vec2 =
  ## Create a Vec2 from a number.
  vec2(v.float32, v.float32)

proc vec2[A, B](x: A, y: B): Vec2 =
  ## Create a Vec2 from two numbers.
  vec2(x.float32, y.float32)

template mouseInsideClip*(r: Rect): bool =
  ## Check mouse inside rect, current clip, and top layer.
  sk.layer == sk.topLayer and
  window.mousePos.vec2.overlaps(r) and
  window.mousePos.vec2.overlaps(sk.clipRect)

template children*(body) =
  ## Wrap children in a function call.
  proc wrapper() {.gensym.} =

    body

    return
  wrapper()

template subWindow*(title: string, show: bool, body) =
  ## Create a window frame.
  if title notin subWindowStates:
    subWindowStates[title] = SubWindowState(
      pos: vec2(10 + subWindowStates.len * (300 + theme.spacing), 10),
      size: vec2(300, 400),
      minimized: false
    )
  let subWindowState = subWindowStates[title]
  if show:
    # Draw the main window frame.
    let size = if subWindowState.minimized:
        vec2(subWindowState.size.x, float32(theme.headerHeight + theme.border * 2))
      else:
        subWindowState.size
    sk.pushFrame(subWindowState.pos, size)
    sk.draw9Patch("window.9patch", 14, sk.pos, sk.size)

    # Draw the header.
    sk.pushFrame(
      subWindowState.pos + vec2(theme.border),
      vec2(subWindowState.size.x - theme.border.float32 * 2, theme.headerHeight)
    )

    # Handle dragging the window.
    if subWindowState.dragging and (window.buttonReleased[MouseLeft] or not window.buttonDown[MouseLeft]):
      subWindowState.dragging = false
    if subWindowState.dragging:
      subWindowState.pos = window.mousePos.vec2 - subWindowState.dragOffset
    if subWindowState.dragging:
      sk.draw9Patch("header.dragging.9patch", 6, sk.pos, sk.size)
    elif mouseInsideClip(rect(sk.pos, sk.size)):
      if window.buttonPressed[MouseLeft]:
        subWindowState.dragging = true
        subWindowState.dragOffset = window.mousePos.vec2 - subWindowState.pos
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
    if mouseInsideClip(minimizeRect):
      if window.buttonReleased[MouseLeft]:
        subWindowState.minimized = not subWindowState.minimized
    if subWindowState.minimized:
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
    if mouseInsideClip(closeRect):
      if window.buttonReleased[MouseLeft]:
        show = false
    sk.drawImage("close", closeRect.xy)
    sk.popFrame()

    if not subWindowState.minimized:

      let bodyPos = subWindowState.pos + vec2(theme.border, theme.border + theme.headerHeight)
      let bodySize = subWindowState.size - vec2(theme.border * 2, theme.border * 2 + theme.headerHeight)

      frame(title, bodyPos, bodySize):
        children(body)

      # Draw the resize handle.
      let resizeHandleSize = sk.getImageSize("resize")
      let resizeHandleRect = rect(
        sk.at.x + sk.size.x - resizeHandleSize.x.float32 - theme.border.float32,
        sk.at.y + sk.size.y - resizeHandleSize.y.float32 - theme.border.float32,
        resizeHandleSize.x.float32,
        resizeHandleSize.y.float32
      )
      if subWindowState.resizing and (window.buttonReleased[MouseLeft] or not window.buttonDown[MouseLeft]):
        subWindowState.resizing = false
      if subWindowState.resizing:
        subWindowState.size = window.mousePos.vec2 - subWindowState.resizeOffset
        subWindowState.size.x = max(subWindowState.size.x, 200f)
        subWindowState.size.y = max(subWindowState.size.y, float32(theme.headerHeight * 2 + theme.border * 2))
      else:
        if mouseInsideClip(resizeHandleRect):
          if window.buttonPressed[MouseLeft]:
            subWindowState.resizing = true
            subWindowState.resizeOffset = window.mousePos.vec2 - subWindowState.size
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

  children(body)

  # Handle scrollbar drag release
  if frameState.scrollingY and (window.buttonReleased[MouseLeft] or not window.buttonDown[MouseLeft]):
    frameState.scrollingY = false
  if frameState.scrollingX and (window.buttonReleased[MouseLeft] or not window.buttonDown[MouseLeft]):
    frameState.scrollingX = false

  # Calculate content size from stretchAt (add padding for last element).
  # Add scrollPos back because stretchAt is in scrolled coordinates but we need unscrolled.
  sk.stretchAt += vec2(16)
  let contentSize = (sk.stretchAt + frameState.scrollPos) - originPos
  let scrollMax = max(contentSize - sk.size, vec2(0, 0))

  # Clamp scroll position to valid range (handles resize making content smaller).
  if scrollMax.y > 0:
    frameState.scrollPos.y = clamp(frameState.scrollPos.y, 0.0, scrollMax.y)
  else:
    frameState.scrollPos.y = 0
  if scrollMax.x > 0:
    frameState.scrollPos.x = clamp(frameState.scrollPos.x, 0.0, scrollMax.x)
  else:
    frameState.scrollPos.x = 0

  # Scroll wheel handling (only when mouse over frame).
  if mouseInsideClip(rect(sk.pos, sk.size)):
    if not frameState.scrollingY and window.scrollDelta.y != 0:
      frameState.scrollPos.y += window.scrollDelta.y * 10
      frameState.scrollPos.y = clamp(frameState.scrollPos.y, 0.0, scrollMax.y)
    if not frameState.scrollingX and window.scrollDelta.x != 0:
      frameState.scrollPos.x += window.scrollDelta.x * 10
      frameState.scrollPos.x = clamp(frameState.scrollPos.x, 0.0, scrollMax.x)

  # Draw Y scrollbar.
  if contentSize.y > sk.size.y:
    let scrollSize = contentSize.y
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
    elif mouseInsideClip(scrollbarHandleRect):
      if window.buttonPressed[MouseLeft]:
        frameState.scrollingY = true
        frameState.scrollDragOffset.y = window.mousePos.vec2.y - scrollbarHandleRect.y

    sk.draw9Patch("scrollbar.9patch", 4, scrollbarHandleRect.xy, scrollbarHandleRect.wh)

  # Draw X scrollbar.
  if contentSize.x > sk.size.x:
    let scrollSize = contentSize.x
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
    elif mouseInsideClip(scrollbarHandleRect):
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
  if mouseInsideClip(rect(sk.at, buttonSize)):
    if window.buttonReleased[MouseLeft]:
      body
    elif window.buttonDown[MouseLeft]:
      sk.draw9Patch("button.down.9patch", 8, sk.at, buttonSize, rgbx(255, 255, 255, 255))
    else:
      sk.draw9Patch("button.hover.9patch", 8, sk.at, buttonSize, rgbx(255, 255, 255, 255))
  else:
    sk.draw9Patch("button.9patch", 8, sk.at, buttonSize)
  discard sk.drawText(sk.textStyle, label, sk.at + vec2(theme.padding), rgbx(255, 255, 255, 255))
  sk.advance(buttonSize + vec2(theme.padding))

template icon*(image: string) =
  ## Draw an icon.
  let imageSize = sk.getImageSize(image)
  sk.drawImage(image, sk.at)
  sk.advance(vec2(imageSize.x, imageSize.y))

template iconButton*(image: string, body) =
  ## Create an icon button.
  let
    m2 = vec2(8, 8)
    s2 = sk.getImageSize(image) + vec2(8, 8) * 2
    buttonRect = rect(sk.at - m2, s2)
  if mouseInsideClip(buttonRect):
    sk.hover = true
    if window.buttonReleased[MouseLeft]:
      body
    elif window.buttonDown[MouseLeft]:
      sk.draw9Patch("button.down.9patch", 8, sk.at - m2, s2, rgbx(255, 255, 255, 255))
    else:
      sk.draw9Patch("button.hover.9patch", 8, sk.at - m2, s2, rgbx(255, 255, 255, 255))
  else:
    sk.hover = false
    sk.draw9Patch("button.9patch", 8, sk.at - m2, s2)
  sk.drawImage(image, sk.at)
  sk.stretchAt = max(sk.stretchAt, sk.at + s2)
  sk.at += vec2(32 + sk.padding, 0)

template clickableIcon*(image: string, on: bool, body) =
  ## Create an clickable icon with no background and no padding.
  let
    imageSize = sk.getImageSize(image)
    s2 = imageSize
    upColor = rgbx(200, 200, 200, 200)
    onColor = rgbx(255, 255, 255, 255)
    hoverColor = rgbx(255, 255, 255, 255)
    offColor = rgbx(110, 110, 110, 110)
  var color = upColor
  if mouseInsideClip(rect(sk.at, s2)):
    if window.buttonReleased[MouseLeft]:
      body
    elif window.buttonDown[MouseLeft]:
      color = upColor
    else:
      if on:
        color = onColor
      else:
        color = upColor
  else:
    if on:
      color = onColor
    else:
      color = offColor

  sk.drawImage(image, sk.at, color)
  sk.at += vec2(imageSize.x, 0)

template radioButton*[T](label: string, variable: var T, value: T) =
  ## Radio button.
  let
    iconSize = sk.getImageSize("radio.on")
    textSize = sk.getTextSize(sk.textStyle, label)
    height = max(iconSize.y.float32, textSize.y)
    width = iconSize.x.float32 + theme.spacing.float32 + textSize.x
    hitRect = rect(sk.at, vec2(width, height))

  if mouseInsideClip(hitRect) and window.buttonReleased[MouseLeft]:
    variable = value

  let
    on = variable == value
    iconPos = vec2(sk.at.x, sk.at.y + (height - iconSize.y.float32) * 0.5)
    textPos = vec2(
      iconPos.x + iconSize.x.float32 + theme.spacing.float32,
      sk.at.y + (height - textSize.y) * 0.5
    )
  sk.drawImage(if on: "radio.on" else: "radio.off", iconPos)
  discard sk.drawText(sk.textStyle, label, textPos, theme.defaultTextColor)
  sk.advance(vec2(width, height))

template checkBox*(label: string, value: var bool) =
  ## Checkbox.
  let
    iconSize = sk.getImageSize("check.on")
    textSize = sk.getTextSize(sk.textStyle, label)
    height = max(iconSize.y.float32, textSize.y)
    width = iconSize.x.float32 + theme.spacing.float32 + textSize.x
    hitRect = rect(sk.at, vec2(width, height))

  if mouseInsideClip(hitRect) and window.buttonReleased[MouseLeft]:
    value = not value

  let
    iconPos = vec2(sk.at.x, sk.at.y + (height - iconSize.y.float32) * 0.5)
    textPos = vec2(
      iconPos.x + iconSize.x.float32 + theme.spacing.float32,
      sk.at.y + (height - textSize.y) * 0.5
    )
  sk.drawImage(if value: "check.on" else: "check.off", iconPos)
  discard sk.drawText(sk.textStyle, label, textPos, theme.defaultTextColor)
  sk.advance(vec2(width, height))

template dropDown*[T](selected: var T, options: openArray[T]) =
  ## Dropdown styled like input text; options render in a new layer.
  let id = "dropdown_" & $cast[uint](addr selected)
  if id notin dropDownStates:
    dropDownStates[id] = DropDownState()
  let state = dropDownStates[id]

  let
    font = sk.atlas.fonts[sk.textStyle]
    height = font.lineHeight + theme.padding.float32 * 2
    width = sk.size.x - theme.padding.float32 * 3
    arrowSize = sk.getImageSize("droparrow")
    dropRect = rect(sk.at, vec2(width, height))

  let displayText = $selected

  # Toggle open/close on click.
  let hover = mouseInsideClip(dropRect)
  if hover and window.buttonReleased[MouseLeft]:
    state.open = not state.open

  # Draw control body.
  sk.pushFrame(sk.at, vec2(width, height))
  let bgColor = if state.open or hover: rgbx(220, 220, 240, 255) else: rgbx(255, 255, 255, 255)
  sk.draw9Patch("dropdown.9patch", 6, sk.pos, sk.size, bgColor)
  discard sk.drawText(sk.textStyle, displayText, sk.at + vec2(theme.padding), theme.defaultTextColor)
  let arrowPos = vec2(
    sk.pos.x + sk.size.x - arrowSize.x.float32 - theme.padding.float32,
    sk.pos.y + (height - arrowSize.y.float32) * 0.5
  )
  sk.drawImage("droparrow", arrowPos)
  sk.popFrame()
  sk.advance(vec2(width, height))

  if state.open and options.len > 0:
    sk.callsbacks.add proc() =
      sk.pushLayer()

      let
        rowHeight = height
        popupPos = vec2(dropRect.x, dropRect.y + dropRect.h)
        popupSize = vec2(width, rowHeight * options.len.float32)
        popupRect = rect(popupPos, popupSize)

      sk.pushFrame(popupPos, popupSize)
      sk.draw9Patch("dropdown.9patch", 6, sk.pos, sk.size, rgbx(245, 245, 255, 255))

      for i, opt in options:
        let
          rowPos = vec2(sk.pos.x, sk.pos.y + i.float32 * rowHeight)
          rowRect = rect(rowPos, vec2(width, rowHeight))
          textPos = rowPos + vec2(theme.padding)
        let
          isSelected = selected == opt
          rowHover = mouseInsideClip(rowRect)
        if rowHover or isSelected:
          let tint = if rowHover: rgbx(80, 80, 100, 180) else: rgbx(60, 60, 80, 120)
          sk.drawRect(rowRect.xy, rowRect.wh, tint)
          if rowHover and window.buttonReleased[MouseLeft]:
            selected = opt
            state.open = false
        discard sk.drawText(sk.textStyle, $opt, textPos, theme.defaultTextColor)

      sk.popFrame()

      # Close when clicking outside.
      if window.buttonPressed[MouseLeft] and
        not mouseInsideClip(dropRect) and
        not mouseInsideClip(popupRect):
        state.open = false

      sk.popLayer()

template progressBar*(value: SomeNumber, minVal: SomeNumber, maxVal: SomeNumber) =
  ## Non-interactive progress bar.
  let
    minF = minVal.float32
    maxF = maxVal.float32
    v = clamp(value.float32, minF, maxF)
    range = maxF - minF
    t = if range == 0: 0f else: clamp((v - minF) / range, 0f, 1f)
    bodySize = sk.getImageSize("progressBar.body.9patch")
    height = bodySize.y.float32
    width = max(bodySize.x.float32, sk.size.x - theme.padding.float32 * 3)
    barRect = rect(sk.at, vec2(width, height))

  sk.draw9Patch("progressBar.body.9patch", 6, barRect.xy, barRect.wh)

  let fillWidth = width * t
  if fillWidth > 0:
    sk.draw9Patch("progressBar.progress.9patch", 6, barRect.xy, vec2(fillWidth, height))

  sk.advance(vec2(width, height))

template group*(p: Vec2, direction = TopToBottom, body) =
  ## Create a group.
  sk.pushFrame(sk.at + p, sk.size - p, direction)
  children(body)
  let endAt = sk.stretchAt
  sk.popFrame()
  sk.advance(endAt - sk.at)


template frame*(p, s: Vec2, body) =
  ## Create a frame.
  sk.pushFrame(p, s)
  sk.draw9Patch("window.9patch", 14, sk.pos, sk.size)
  children(body)
  sk.popFrame()

template ribbon*(p, s: Vec2, tint: ColorRGBX, body) =
  ## Create a ribbon.
  sk.pushFrame(p, s)
  sk.drawRect(sk.pos, sk.size, tint)
  sk.at = sk.pos
  children(body)
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

template scrubber*[T, U](id: string, value: var T, minVal: T, maxVal: U) =
  ## Draggable scrubber that spans available width and advances layout.
  let
    minF = minVal.float32
    maxF = maxVal.float32
    v = clamp(value.float32, minF, maxF)
    range = maxF - minF

  if id notin scrubberStates:
    scrubberStates[id] = ScrubberState()
  let scrubState = scrubberStates[id]

  let
    handleSize = sk.getImageSize("scrubber.handle")
    bodySize = sk.getImageSize("scrubber.body.9patch")
    height = handleSize.y
    width = sk.size.x - theme.padding.float32 * 3
    controlRect = rect(sk.at, vec2(width, height))
    trackStart = controlRect.x + handleSize.x / 2
    trackEnd = controlRect.x + width - handleSize.x / 2
    travel = max(0f, trackEnd - trackStart)
    travelSafe = if travel <= 0: 1f else: travel

  # Draw track.
  sk.draw9Patch("scrubber.body.9patch", 4, controlRect.xy, controlRect.wh)

  # Normalize current value.
  let norm = if range == 0: 0f else: clamp((v - minF) / range, 0f, 1f)

  # Handle geometry.
  let
    handlePos = vec2(trackStart + norm * travel - handleSize.x * 0.5, controlRect.y + (height - handleSize.y) * 0.5)
    handleRect = rect(handlePos, handleSize)

  # Dragging logic.
  if scrubState.dragging and (window.buttonReleased[MouseLeft] or not window.buttonDown[MouseLeft]):
    scrubState.dragging = false

  if scrubState.dragging:
    let t = clamp((window.mousePos.vec2.x - trackStart) / travelSafe, 0f, 1f)
    value = (minF + t * range).T
  elif mouseInsideClip(handleRect) or mouseInsideClip(controlRect):
    if window.buttonPressed[MouseLeft]:
      scrubState.dragging = true
      let t = clamp((window.mousePos.vec2.x - trackStart) / travelSafe, 0f, 1f)
      value = (minF + t * range).T

  # Recompute normalized position after potential changes.
  let norm2 = if range == 0: 0f else: clamp((value.float32 - minF) / range, 0f, 1f)
  let handlePos2 = vec2(trackStart + norm2 * travel - handleSize.x * 0.5, controlRect.y + (height - handleSize.y) * 0.5)

  sk.drawImage("scrubber.handle", handlePos2)
  sk.advance(vec2(width, height))

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
    if mouseInsideClip(rect(sk.pos, sk.size)):
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

template menuPopup(path: seq[string], popupAt: Vec2, popupWidth = 200, body: untyped) =
  ## Render a popup in a single pass with caller-provided width.
  menuEnsureState()
  var layout = MenuLayout(
    origin: popupAt,
    width: popupWidth.float32,
    cursorY: theme.menuPadding.float32
  )
  menuLayouts.add(layout)
  children(body)
  # Record the popup area for outside-click detection.
  let popupHeight = layout.cursorY + theme.menuPadding.float32
  menuAddActive(rect(popupAt, vec2(popupWidth, popupHeight)))
  menuLayouts.setLen(menuLayouts.len - 1)

template menuBar*(body: untyped) =
  ## Horizontal application menu bar (File, Edit, ...).
  menuEnsureState()
  menuState.activeRects.setLen(0)
  menuPathStack.setLen(0)

  let elevate = menuState.openPath.len > 0
  if elevate:
    sk.pushLayer()
  let barHeight = theme.headerHeight.float32
  sk.pushFrame(vec2(0, 0), vec2(sk.size.x, barHeight))
  # Use a 9-patch so the bar has a visible background.
  sk.draw9Patch("header.9patch", 6, sk.pos, sk.size, rgbx(30, 30, 40, 255))
  sk.at = sk.pos + vec2(theme.menuPadding)
  children(body)
  sk.popFrame()

  # Close menus if the user clicks outside of any active menu rect.
  if menuState.openPath.len > 0 and window.buttonPressed[MouseLeft]:
    if not menuPointInside(menuState.activeRects, window.mousePos.vec2):
      menuState.openPath.setLen(0)

  if elevate:
    sk.popLayer()

template subMenu*(label: string, menuWidth = 200, body: untyped) =
  ## Menu entry that can contain other menu items.
  menuEnsureState()
  let path = menuPathStack & @[label]
  let isRoot = menuLayouts.len == 0

  if isRoot:
    let textSize = sk.getTextSize(sk.textStyle, label)
    let size = textSize + vec2(theme.menuPadding.float32 * 2, theme.menuPadding.float32 * 2)
    let menuRect = rect(sk.at, size)
    menuAddActive(menuRect)

    let hover = window.mousePos.vec2.overlaps(menuRect)
    let open = menuPathOpen(path)

    if hover and window.buttonReleased[MouseLeft]:
      if open:
        menuState.openPath.setLen(0)
      else:
        menuState.openPath = path
    elif hover and menuState.openPath.len > 0 and not window.buttonDown[MouseLeft]:
      # When a menu is already open, hovering another root entry switches it.
      menuState.openPath = path

    if hover or open:
      sk.drawRect(menuRect.xy, menuRect.wh, rgbx(70, 70, 90, 200))
    discard sk.drawText(sk.textStyle, label, menuRect.xy + vec2(theme.menuPadding), theme.defaultTextColor)
    sk.at.x += size.x + theme.spacing.float32

    if open:
      menuPathStack.add(label)
      let popupPos = vec2(menuRect.x, menuRect.y + menuRect.h)
      menuPopup(path, popupPos, menuWidth):
        children(body)
      menuPathStack.setLen(menuPathStack.len - 1)
  else:
    var layout = menuLayouts[^1]
    let textSize = sk.getTextSize(sk.textStyle, label)
    let rowH = textSize.y + theme.menuPadding.float32 * 2
    let rowPos = vec2(layout.origin.x + theme.menuPadding.float32, layout.origin.y + layout.cursorY)
    let rowSize = vec2(layout.width - theme.menuPadding.float32 * 2, rowH)
    let itemRect = rect(rowPos, rowSize)
    menuAddActive(itemRect)

    let open = menuPathOpen(path)
    let hover = window.mousePos.vec2.overlaps(itemRect)

    if hover and menuState.openPath.len >= path.len - 1:
      menuState.openPath = path

    if hover or open:
      sk.drawRect(itemRect.xy, itemRect.wh, rgbx(70, 70, 90, 180))
    discard sk.drawText(
      sk.textStyle,
      label,
      rowPos + vec2(theme.textPadding),
      theme.defaultTextColor
    )

    # Draw submenu arrow on the right.
    let arrowPos = vec2(itemRect.x + itemRect.w - textSize.y, rowPos.y + theme.textPadding.float32)
    discard sk.drawText(sk.textStyle, ">", arrowPos, theme.defaultTextColor)

    layout.cursorY += rowH

    if open:
      menuPathStack.add(label)
      let popupPos = vec2(itemRect.x + itemRect.w, itemRect.y)
      menuPopup(path, popupPos, menuWidth):
        children(body)
      menuPathStack.setLen(menuPathStack.len - 1)

template menuItem*(label: string, body: untyped) =
  ## Leaf menu entry that runs `body` on click.
  menuEnsureState()
  var layout = menuLayouts[^1]

  let textSize = sk.getTextSize(sk.textStyle, label)
  let rowH = textSize.y + theme.menuPadding.float32 * 2
  let rowPos = vec2(layout.origin.x + theme.menuPadding.float32, layout.origin.y + layout.cursorY)
  let rowSize = vec2(layout.width - theme.menuPadding.float32 * 2, rowH)
  let itemRect = rect(rowPos, rowSize)
  menuAddActive(itemRect)

  let hover = window.mousePos.vec2.overlaps(itemRect)
  if hover:
    sk.drawRect(itemRect.xy, itemRect.wh, rgbx(80, 80, 100, 180))
  discard sk.drawText(
    sk.textStyle,
    label,
    rowPos + vec2(theme.textPadding),
    theme.defaultTextColor
  )

  if hover and window.buttonReleased[MouseLeft]:
    menuState.openPath.setLen(0)
    children(body)

  layout.cursorY += rowH

template tooltip*(text: string) =
  ## Display a tooltip at the mouse cursor.
  ## This should be called after a widget when sk.showTooltip is true.
  let tooltipText = text
  sk.callsbacks.add proc() =
    sk.pushLayer()

    let textSize = sk.getTextSize(sk.textStyle, tooltipText)
    let tooltipSize = textSize + vec2(theme.padding.float32 * 2, theme.padding.float32 * 2)
    let mousePos = window.mousePos.vec2

    # Position tooltip near mouse, offset slightly to avoid cursor.
    var tooltipPos = mousePos + vec2(16, 16)

    # Keep tooltip on screen.
    if tooltipPos.x + tooltipSize.x > sk.size.x:
      tooltipPos.x = sk.size.x - tooltipSize.x - theme.padding.float32
    if tooltipPos.y + tooltipSize.y > sk.size.y:
      tooltipPos.y = mousePos.y - tooltipSize.y - 4

    # Ensure tooltip doesn't go off-screen left or top.
    tooltipPos.x = max(tooltipPos.x, theme.padding.float32)
    tooltipPos.y = max(tooltipPos.y, theme.padding.float32)

    sk.pushFrame(tooltipPos, tooltipSize)
    sk.draw9Patch("tooltip.9patch", 6, sk.pos, sk.size)
    discard sk.drawText(sk.textStyle, tooltipText, sk.pos + vec2(theme.padding), theme.defaultTextColor)
    sk.popFrame()

    sk.popLayer()
