import
  std/[tables, unicode, times, strutils, options],
  vmath, bumpy, chroma,
  silky/textinput

when defined(silkyTesting):
  import silky/semantic, silky/testing
else:
  import silky/drawing, windy

when defined(macos):
  const ScrollSpeed* = 10.0
else:
  const ScrollSpeed* = -10.0

type

  SubWindowState* = ref object
    pos*: Vec2
    size*: Vec2
    minimized*: bool
    dragging*: bool
    dragOffset*: Vec2
    resizing*: bool
    resizeOffset*: Vec2
    bodyPos*: Vec2
    bodySize*: Vec2
    visible*: bool

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

  MenuEntryContext* = object
    path*: seq[string]
    popupPos*: Vec2
    popupWidth*: int
    open*: bool
    isRoot*: bool

  MenuItemContext* = object
    layout*: MenuLayout
    rowH*: float32
    clicked*: bool

var
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
  ## Join menu path segments into a unique key.
  path.join(">")

proc menuPathOpen(path: seq[string]): bool =
  ## Check if the given menu path is currently open.
  menuState.openPath.len >= path.len and menuState.openPath[0 ..< path.len] == path

proc menuEnsureState() =
  ## Initialize menu state if not already created.
  if menuState.isNil:
    menuState = MenuState(
      openPath: @[],
      activeRects: @[]
    )

proc menuAddActive(rect: Rect) =
  ## Record a rect so outside-click detection can close menus.
  menuState.activeRects.add(rect)

proc menuPointInside(rects: seq[Rect], p: Vec2): bool =
  ## Check if point is inside any of the given rectangles.
  for r in rects:
    if p.overlaps(r):
      return true
  return false

proc vec2(v: SomeNumber): Vec2 =
  ## Create a Vec2 from a number.
  vec2(v.float32, v.float32)

proc vec2[A, B](x: A, y: B): Vec2 =
  ## Create a Vec2 from two numbers.
  vec2(x.float32, y.float32)

proc mouseInsideClip*(sk: Silky, window: Window, r: Rect): bool =
  ## Check mouse inside rect and current clip.
  window.mousePos.vec2.overlaps(r) and
  window.mousePos.vec2.overlaps(sk.clipRect)

proc subWindowStart*(
    sk: Silky,
    window: Window,
    title: string,
    show: var bool,
    initialOrigin: Option[Vec2],
    initialSize: Option[Vec2]
  ): SubWindowState =
  ## Begin a subwindow; stores body rect and visibility on the state.
  if title notin subWindowStates:
    let defaultPos = vec2(10 + subWindowStates.len * (300 + sk.theme.spacing), 10)
    let defaultSize = vec2(300, 400)
    subWindowStates[title] = SubWindowState(
      pos: if initialOrigin.isSome: initialOrigin.get else: defaultPos,
      size: if initialSize.isSome: initialSize.get else: defaultSize,
      minimized: false,
      bodyPos: vec2(0),
      bodySize: vec2(0),
      visible: false
    )
  let subWindowState = subWindowStates[title]
  if not show:
    subWindowState.visible = false
    return subWindowState

  let size = if subWindowState.minimized:
      vec2(subWindowState.size.x, float32(sk.theme.headerHeight + sk.theme.border * 2))
    else:
      subWindowState.size
  sk.pushLayout(subWindowState.pos, size)
  sk.draw9Patch("window.9patch", 14, sk.pos, sk.size)

  # Draw the header.
  sk.pushLayout(
    subWindowState.pos + vec2(sk.theme.border),
    vec2(subWindowState.size.x - sk.theme.border.float32 * 2, sk.theme.headerHeight)
  )

  # Handle dragging the window.
  if subWindowState.dragging and (window.buttonReleased[MouseLeft] or not window.buttonDown[MouseLeft]):
    subWindowState.dragging = false
  if subWindowState.dragging:
    subWindowState.pos = window.mousePos.vec2 - subWindowState.dragOffset
  if subWindowState.dragging:
    sk.draw9Patch("header.dragging.9patch", 6, sk.pos, sk.size)
  elif sk.mouseInsideClip(window, rect(sk.pos, sk.size)):
    if window.buttonPressed[MouseLeft]:
      subWindowState.dragging = true
      subWindowState.dragOffset = window.mousePos.vec2 - subWindowState.pos
    else:
      sk.draw9Patch("header.hover.9patch", 6, sk.pos, sk.size)
  else:
    sk.draw9Patch("header.9patch", 6, sk.pos, sk.size)
  sk.at += vec2(sk.theme.textPadding)

  # Handle minimizing/maximizing button for the window.
  let minimizeSize = sk.getImageSize("maximized")
  let minimizeRect = rect(
    sk.at.x,
    sk.at.y,
    minimizeSize.x.float32,
    minimizeSize.y.float32
  )
  if sk.mouseInsideClip(window, minimizeRect):
    if window.buttonReleased[MouseLeft]:
      subWindowState.minimized = not subWindowState.minimized
  if subWindowState.minimized:
    sk.drawImage("minimized", minimizeRect.xy)
  else:
    sk.drawImage("maximized", minimizeRect.xy)
  sk.at.x += sk.getImageSize("maximized").x.float32 + sk.theme.padding.float32

  # Draw the title.
  discard sk.drawText(sk.textStyle, title, sk.at, sk.theme.defaultTextColor)

  # Handle closing button for the window.
  let closeSize = sk.getImageSize("close")
  let closeRect = rect(
    sk.at.x + sk.size.x - closeSize.x.float32 - sk.theme.padding.float32 * 5,
    sk.at.y,
    closeSize.x.float32,
    closeSize.y.float32
  )
  if sk.mouseInsideClip(window, closeRect):
    if window.buttonReleased[MouseLeft]:
      show = false
  sk.drawImage("close", closeRect.xy)
  sk.popLayout()

  let bodyPos = subWindowState.pos + vec2(sk.theme.border, sk.theme.border + sk.theme.headerHeight)
  let bodySize = subWindowState.size - vec2(sk.theme.border * 2, sk.theme.border * 2 + sk.theme.headerHeight)

  subWindowState.bodyPos = bodyPos
  subWindowState.bodySize = bodySize
  subWindowState.visible = true
  return subWindowState

proc subWindowEnd*(sk: Silky, window: Window, subWindowState: SubWindowState) =
  ## Finish a subwindow, handling resize and popping layout.
  if not subWindowState.minimized:
    let resizeHandleSize = sk.getImageSize("resize")
    let resizeHandleRect = rect(
      sk.at.x + sk.size.x - resizeHandleSize.x.float32 - sk.theme.border.float32,
      sk.at.y + sk.size.y - resizeHandleSize.y.float32 - sk.theme.border.float32,
      resizeHandleSize.x.float32,
      resizeHandleSize.y.float32
    )
    if subWindowState.resizing and (window.buttonReleased[MouseLeft] or not window.buttonDown[MouseLeft]):
      subWindowState.resizing = false
    if subWindowState.resizing:
      subWindowState.size = window.mousePos.vec2 - subWindowState.resizeOffset
      subWindowState.size.x = max(subWindowState.size.x, 200f)
      subWindowState.size.y = max(subWindowState.size.y, float32(sk.theme.headerHeight * 2 + sk.theme.border * 2))
    else:
      if sk.mouseInsideClip(window, resizeHandleRect):
        if window.buttonPressed[MouseLeft]:
          subWindowState.resizing = true
          subWindowState.resizeOffset = window.mousePos.vec2 - subWindowState.size
    sk.drawImage("resize", resizeHandleRect.xy)

  sk.popLayout()

template subWindow*(title: string, show: var bool, body: untyped) =
  ## Create a window frame using default placement and sizing.
  let state = sk.subWindowStart(window, title, show, none(Vec2), none(Vec2))
  sk.beginWidget("SubWindow", name = title, rect = rect(state.pos, state.size))
  if state.visible:
    try:
      if not state.minimized:
        frame(title, state.bodyPos, state.bodySize):
          body
    finally:
      sk.subWindowEnd(window, state)
  sk.endWidget()

template subWindow*(title: string, show: var bool, initialOrigin: Vec2, initialSize: Vec2, body: untyped) =
  ## Create a window frame with explicit initial position and size.
  let state = sk.subWindowStart(window, title, show, some(initialOrigin), some(initialSize))
  sk.beginWidget("SubWindow", name = title, rect = rect(state.pos, state.size))
  if state.visible:
    try:
      if not state.minimized:
        frame(title, state.bodyPos, state.bodySize):
          body
    finally:
      sk.subWindowEnd(window, state)
  sk.endWidget()

proc frameStart*(sk: Silky, id: string, framePos, frameSize: Vec2): tuple[state: FrameState, originPos: Vec2] =
  ## Begin a scrollable frame; returns state and origin for cleanup.
  if id notin frameStates:
    frameStates[id] = FrameState()
  let frameState = frameStates[id]
  sk.pushLayout(framePos, frameSize)
  sk.draw9Patch("frame.9patch", 6, sk.pos, sk.size)
  sk.pushClipRect(rect(
    sk.pos.x + 1,
    sk.pos.y + 1,
    sk.size.x - 2,
    sk.size.y - 2
  ))
  sk.at = sk.pos + vec2(sk.theme.padding)
  let originPos = sk.at
  sk.at -= frameState.scrollPos
  return (frameState, originPos)

proc frameEnd*(sk: Silky, window: Window, frameState: FrameState, originPos: Vec2) =
  ## Finish a scrollable frame and handle scrollbars.
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
  if sk.mouseInsideClip(window, rect(sk.pos, sk.size)):
    if not frameState.scrollingY and window.scrollDelta.y != 0:
      frameState.scrollPos.y += window.scrollDelta.y * ScrollSpeed
      frameState.scrollPos.y = clamp(frameState.scrollPos.y, 0.0, scrollMax.y)
    if not frameState.scrollingX and window.scrollDelta.x != 0:
      frameState.scrollPos.x += window.scrollDelta.x * ScrollSpeed
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

    # Handle scrollbar Y dragging.
    if frameState.scrollingY:
      let mouseY = window.mousePos.vec2.y
      let relativeY = mouseY - frameState.scrollDragOffset.y - scrollbarTrackRect.y
      let availableTrackHeight = scrollbarTrackRect.h - scrollbarHandleRect.h
      if availableTrackHeight > 0:
        let newScrollPosPercent = clamp(relativeY / availableTrackHeight, 0.0, 1.0)
        frameState.scrollPos.y = newScrollPosPercent * scrollMax.y
    elif sk.mouseInsideClip(window, scrollbarHandleRect):
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

    # Handle scrollbar X dragging.
    if frameState.scrollingX:
      let mouseX = window.mousePos.vec2.x
      let relativeX = mouseX - frameState.scrollDragOffset.x - scrollbarTrackRect.x
      let availableTrackWidth = scrollbarTrackRect.w - scrollbarHandleRect.w
      if availableTrackWidth > 0:
        let newScrollPosPercent = clamp(relativeX / availableTrackWidth, 0.0, 1.0)
        frameState.scrollPos.x = newScrollPosPercent * scrollMax.x
    elif sk.mouseInsideClip(window, scrollbarHandleRect):
      if window.buttonPressed[MouseLeft]:
        frameState.scrollingX = true
        frameState.scrollDragOffset.x = window.mousePos.vec2.x - scrollbarHandleRect.x

    sk.draw9Patch("scrollbar.9patch", 4, scrollbarHandleRect.xy, scrollbarHandleRect.wh)

  sk.popLayout()
  sk.popClipRect()

template frame*(id: string, framePos, frameSize: Vec2, body: untyped) =
  ## Frame with scrollbars similar to a window body.
  sk.beginWidget("Frame", name = id, rect = rect(framePos, frameSize))
  let frameCtx = sk.frameStart(id, framePos, frameSize)
  try:
    body
  finally:
    sk.frameEnd(window, frameCtx.state, frameCtx.originPos)
  sk.endWidget()

template button*(label: string, isEnabled: bool, isError: bool, body: untyped) =
  let
    textSize = sk.getTextSize(sk.textStyle, label)
    buttonSize = textSize + vec2(sk.theme.padding) * 2
    buttonRect = rect(sk.at, buttonSize)
  let hover = sk.mouseInsideClip(window, buttonRect)
  let pressed = hover and window.buttonDown[MouseLeft]

  sk.beginWidget("Button", text = label, rect = buttonRect)

  let patch =
    if not isEnabled:
      "button.disabled.9patch"
    elif isError:
      "button.error.9patch"
    else:
      "button.9patch"

  let textColor =
    if not isEnabled:
      sk.theme.disabledTextColor
    elif isError:
      sk.theme.errorTextColor
    else:
      sk.theme.defaultTextColor

  if isEnabled:
    if hover:
      let hoverPatch = if isError: "button.error.9patch" else: "button.hover.9patch"
      if window.buttonReleased[MouseLeft]:
        body
      elif window.buttonDown[MouseLeft]:
        let downPatch = if isError: "button.error.9patch" else: "button.down.9patch"
        sk.draw9Patch(downPatch, 8, sk.at, buttonSize)
      else:
        sk.draw9Patch(hoverPatch, 8, sk.at, buttonSize)
    else:
      sk.draw9Patch(patch, 8, sk.at, buttonSize)
  else:
    sk.draw9Patch(patch, 8, sk.at, buttonSize)

  discard sk.drawText(sk.textStyle, label, sk.at + vec2(sk.theme.padding), textColor)

  sk.setWidgetState(enabled = isEnabled, pressed = pressed, hovered = hover)
  sk.endWidget()

  sk.advance(buttonSize + vec2(sk.theme.padding))

template button*(label: string, body: untyped) =
  ## Create a button.
  button(label, true, false, body)

template button*(label: string, isEnabled: bool, body: untyped) =
  ## Create a button.
  button(label, isEnabled, false, body)

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
  if sk.mouseInsideClip(window, buttonRect):
    sk.hover = true
    if window.buttonReleased[MouseLeft]:
      body
    elif window.buttonDown[MouseLeft]:
      sk.draw9Patch("button.down.9patch", 8, sk.at - m2, s2, sk.theme.iconButtonDownColor)
    else:
      sk.draw9Patch("button.hover.9patch", 8, sk.at - m2, s2, sk.theme.iconButtonHoverColor)
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
    upColor = sk.theme.iconClickableUpColor
    onColor = sk.theme.iconClickableOnColor
    offColor = sk.theme.iconClickableOffColor
  var color = upColor
  if sk.mouseInsideClip(window, rect(sk.at, s2)):
    sk.hover = true
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
    sk.hover = false
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
    width = iconSize.x.float32 + sk.theme.spacing.float32 + textSize.x
    hitRect = rect(sk.at, vec2(width, height))

  sk.beginWidget("RadioButton", text = label, rect = hitRect)

  if sk.mouseInsideClip(window, hitRect) and window.buttonReleased[MouseLeft]:
    variable = value

  let
    on = variable == value
    iconPos = vec2(sk.at.x, sk.at.y + (height - iconSize.y.float32) * 0.5)
    textPos = vec2(
      iconPos.x + iconSize.x.float32 + sk.theme.spacing.float32,
      sk.at.y + (height - textSize.y) * 0.5
    )
  sk.drawImage(if on: "radio.on" else: "radio.off", iconPos)
  discard sk.drawText(sk.textStyle, label, textPos, sk.theme.defaultTextColor)

  sk.setWidgetState(checked = on)
  sk.endWidget()

  sk.advance(vec2(width, height))

template checkBox*(label: string, value: var bool) =
  ## Checkbox.
  let
    iconSize = sk.getImageSize("check.on")
    textSize = sk.getTextSize(sk.textStyle, label)
    height = max(iconSize.y.float32, textSize.y)
    width = iconSize.x.float32 + sk.theme.spacing.float32 + textSize.x
    hitRect = rect(sk.at, vec2(width, height))

  sk.beginWidget("CheckBox", text = label, rect = hitRect)

  if sk.mouseInsideClip(window, hitRect) and window.buttonReleased[MouseLeft]:
    value = not value

  let
    iconPos = vec2(sk.at.x, sk.at.y + (height - iconSize.y.float32) * 0.5)
    textPos = vec2(
      iconPos.x + iconSize.x.float32 + sk.theme.spacing.float32,
      sk.at.y + (height - textSize.y) * 0.5
    )
  sk.drawImage(if value: "check.on" else: "check.off", iconPos)
  discard sk.drawText(sk.textStyle, label, textPos, sk.theme.defaultTextColor)

  sk.setWidgetState(checked = value)
  sk.endWidget()

  sk.advance(vec2(width, height))

template dropDown*[T](selected: var T, options: openArray[T]) =
  ## Dropdown styled like input text; options render in a new layer.
  let id = "dropdown_" & $cast[uint](addr selected)
  if id notin dropDownStates:
    dropDownStates[id] = DropDownState()
  let state = dropDownStates[id]

  let
    font = sk.atlas.fonts[sk.textStyle]
    height = font.lineHeight + sk.theme.padding.float32 * 2
    width = sk.size.x - sk.theme.padding.float32 * 3
    arrowSize = sk.getImageSize("droparrow")
    dropRect = rect(sk.at, vec2(width, height))

  let displayText = $selected

  sk.beginWidget("DropDown", text = displayText, rect = dropRect)

  # Toggle open/close on click.
  let hover = sk.mouseInsideClip(window, dropRect)
  if hover and window.buttonReleased[MouseLeft]:
    state.open = not state.open

  # Draw control body.
  sk.pushLayout(sk.at, vec2(width, height))
  let bgColor = if state.open or hover: sk.theme.dropdownHoverBgColor else: sk.theme.dropdownBgColor
  sk.draw9Patch("dropdown.9patch", 6, sk.pos, sk.size, bgColor)
  discard sk.drawText(sk.textStyle, displayText, sk.at + vec2(sk.theme.padding), sk.theme.defaultTextColor)
  let arrowPos = vec2(
    sk.pos.x + sk.size.x - arrowSize.x.float32 - sk.theme.padding.float32,
    sk.pos.y + (height - arrowSize.y.float32) * 0.5
  )
  sk.drawImage("droparrow", arrowPos)
  sk.popLayout()
  sk.advance(vec2(width, height))

  sk.endWidget()

  if state.open and options.len > 0:
    sk.pushLayer(PopupsLayer)
    sk.pushClipRect(rect(vec2(0, 0), sk.rootSize))

    let
      rowHeight = height
      popupPos = vec2(dropRect.x, dropRect.y + dropRect.h)
      popupSize = vec2(width, rowHeight * options.len.float32)
      popupRect = rect(popupPos, popupSize)

    sk.pushLayout(popupPos, popupSize)
    sk.draw9Patch("dropdown.9patch", 6, sk.pos, sk.size, sk.theme.dropdownPopupBgColor)

    for i, opt in options:
      let
        rowPos = vec2(sk.pos.x, sk.pos.y + i.float32 * rowHeight)
        rowRect = rect(rowPos, vec2(width, rowHeight))
        textPos = rowPos + vec2(sk.theme.padding)
      let
        isSelected = selected == opt
        rowHover = sk.mouseInsideClip(window, rowRect)
      if rowHover or isSelected:
        let tint = if rowHover: sk.theme.menuPopupHoverColor else: sk.theme.menuPopupSelectedColor
        sk.drawRect(rowRect.xy, rowRect.wh, tint)
        if rowHover and window.buttonReleased[MouseLeft]:
          selected = opt
          state.open = false
      discard sk.drawText(sk.textStyle, $opt, textPos, sk.theme.defaultTextColor)

    sk.popLayout()

    # Close when clicking outside.
    if window.buttonPressed[MouseLeft] and
      not sk.mouseInsideClip(window, dropRect) and
      not sk.mouseInsideClip(window, popupRect):
      state.open = false

    sk.popClipRect()
    sk.popLayer()

template listBox*[T](id: string, items: seq[T], selectedIndex: var int) =
  ## Listbox with scrolling and selection.
  let font = sk.atlas.fonts[sk.textStyle]
  let rowHeight = font.lineHeight + sk.theme.padding.float32
  let outerWidth = sk.size.x - sk.theme.padding.float32 * 3
  # Use a fixed height or calculate based on items, but capped at 4 items.
  let listHeight = min(rowHeight * 4.float32, rowHeight * max(1, items.len).float32) + sk.theme.padding.float32 * 2

  frame(id, sk.at, vec2(outerWidth, listHeight)):
    let itemWidth = sk.size.x - sk.theme.padding.float32 * 3
    for i, item in items:
      let
        rowRect = rect(sk.at, vec2(itemWidth, rowHeight))
        textPos = sk.at + vec2(sk.theme.padding.float32, sk.theme.padding.float32 * 0.5)

      let isSelected = selectedIndex == i
      let rowHover = sk.mouseInsideClip(window, rowRect)

      if rowHover or isSelected:
        let tint = if rowHover: sk.theme.menuPopupHoverColor else: sk.theme.menuPopupSelectedColor
        sk.drawRect(rowRect.xy, rowRect.wh, tint)
        if rowHover and window.buttonReleased[MouseLeft]:
          selectedIndex = i

      discard sk.drawText(sk.textStyle, $item, textPos, sk.theme.defaultTextColor)
      sk.advance(vec2(itemWidth, rowHeight - sk.theme.spacing.float32))
  sk.advance(vec2(outerWidth, listHeight))

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
    width = max(bodySize.x.float32, sk.size.x - sk.theme.padding.float32 * 3)
    barRect = rect(sk.at, vec2(width, height))

  sk.draw9Patch("progressBar.body.9patch", 6, barRect.xy, barRect.wh)

  let scrubberPadding = 4
  let fillWidth = scrubberPadding.float32 * 2 + (width - scrubberPadding.float32 * 2) * t
  if fillWidth > 0:
    sk.draw9Patch("progressBar.progress.9patch", scrubberPadding, barRect.xy, vec2(fillWidth, height))

  sk.advance(vec2(width, height))

proc groupStart*(sk: Silky, p: Vec2, direction = TopToBottom) =
  ## Start a group.
  sk.pushLayout(sk.at + p, sk.size - p, direction)

proc groupEnd*(sk: Silky) =
  ## End a group.
  let endAt = sk.stretchAt
  sk.popLayout()
  sk.advance(endAt - sk.at)

template group*(p: Vec2, direction = TopToBottom, body) =
  ## Create a group.
  sk.groupStart(p, direction)
  try:
    body
  finally:
    sk.groupEnd()

proc frameStart*(sk: Silky, p, s: Vec2) =
  ## Begin a simple frame.
  sk.pushLayout(p, s)
  sk.draw9Patch("window.9patch", 14, sk.pos, sk.size)

proc frameEnd*(sk: Silky) =
  ## Finish a simple frame.
  sk.popLayout()

template frame*(p, s: Vec2, body: untyped) =
  ## Create a frame.
  sk.frameStart(p, s)
  try:
    body
  finally:
    sk.frameEnd()

proc ribbonStart*(sk: Silky, p, s: Vec2, tint: ColorRGBX) =
  ## Begin a ribbon.
  sk.pushLayout(p, s)
  sk.drawRect(sk.pos, sk.size, tint)
  sk.at = sk.pos

proc ribbonEnd*(sk: Silky) =
  ## Finish a ribbon.
  sk.popLayout()

template ribbon*(p, s: Vec2, tint: ColorRGBX, body: untyped) =
  ## Create a ribbon.
  sk.ribbonStart(p, s, tint)
  try:
    body
  finally:
    sk.ribbonEnd()

template image*(imageName: string, tint: ColorRGBX) =
  ## Draw an image with explicit tint.
  sk.drawImage(imageName, sk.at, tint)
  sk.at.x += sk.getImageSize(imageName).x
  sk.at.x += sk.padding

template image*(imageName: string) =
  ## Draw an image with default text color tint.
  image(imageName, sk.theme.textColor)

proc wordWrapText*(sk: Silky, text: string, maxWidth: float32, font: string = "Default"): string =
  ## Word-wraps text to fit within maxWidth pixels using the given font.
  if text.len == 0:
    return ""

  let words = strutils.splitWhitespace(text)
  if words.len == 0:
    return text

  var lines: seq[string]
  var currentLine = words[0]

  for i in 1 ..< words.len:
    let word = words[i]
    let testLine = currentLine & " " & word
    let testSize = sk.getTextSize(font, testLine)

    if testSize.x <= maxWidth:
      currentLine = testLine
    else:
      lines.add(currentLine)
      currentLine = word

  lines.add(currentLine)

  for i, line in lines:
    if i > 0:
      result.add("\n")
    result.add(line)

template text*(t: string) =
  ## Draw text.
  let textRect = rect(sk.at, sk.getTextSize(sk.textStyle, t))
  sk.beginWidget("Text", text = t, rect = textRect)
  let textSize = sk.drawText(sk.textStyle, t, sk.at, sk.theme.textColor)
  sk.endWidget()
  sk.advance(textSize)

template h1text*(t: string) =
  ## Draw H1 text.
  let textSize = sk.drawText("H1", t, sk.at, sk.theme.textH1Color)
  sk.advance(textSize)

template scrubber*[T, U](id: string, value: var T, minVal: T, maxVal: U, label: string = "") =
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
    baseHandleSize = sk.getImageSize("scrubber.handle")
    buttonHandleSize = sk.getImageSize("button.9patch")
    labelSize = if label.len > 0: sk.getTextSize(sk.textStyle, label) else: vec2(0, 0)
    minLabelSize = if label.len > 0: sk.getTextSize(sk.textStyle, "0000") else: vec2(0, 0)
    knobTextPadding = sk.theme.padding.float32 * 2 + 8f
    handleWidth =
      if label.len > 0:
        max(buttonHandleSize.x, max(labelSize.x, minLabelSize.x) + knobTextPadding)
      else:
        baseHandleSize.x
    handleHeight = if label.len > 0: max(buttonHandleSize.y, baseHandleSize.y) else: baseHandleSize.y
    handleSize = vec2(handleWidth, handleHeight)
    height = handleSize.y
    width = sk.size.x
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
  elif sk.mouseInsideClip(window, handleRect) or sk.mouseInsideClip(window, controlRect):
    if window.buttonPressed[MouseLeft]:
      scrubState.dragging = true
      let t = clamp((window.mousePos.vec2.x - trackStart) / travelSafe, 0f, 1f)
      value = (minF + t * range).T

  # Recompute normalized position after potential changes.
  let norm2 = if range == 0: 0f else: clamp((value.float32 - minF) / range, 0f, 1f)
  let handlePos2 = vec2(trackStart + norm2 * travel - handleSize.x * 0.5, controlRect.y + (height - handleSize.y) * 0.5)

  if label.len > 0:
    sk.draw9Patch("button.9patch", 8, handlePos2, handleSize)
    let textPos = vec2(
      handlePos2.x + (handleSize.x - labelSize.x) * 0.5,
      handlePos2.y + (handleSize.y - labelSize.y) * 0.5
    )
    discard sk.drawText(sk.textStyle, label, textPos, sk.theme.defaultTextColor)
  else:
    sk.drawImage("scrubber.handle", handlePos2)
  sk.advance(vec2(width, height))

template inputText*(id: int, t: var string, enabled: bool = true, error: bool = false) =
  ## Create an input text.
  let font = sk.atlas.fonts[sk.textStyle]
  let height = font.lineHeight + sk.theme.padding.float32 * 2
  let width = sk.size.x - sk.theme.padding.float32 * 3
  sk.pushLayout(sk.at, vec2(width, height))

  if id notin textInputStates:
    textInputStates[id] = InputTextState(focused: false)
    textInputStates[id].setText(t)

  let textInputState = textInputStates[id]

  # If t changed externally, update the internal state
  if not textInputState.focused and textInputState.getText() != t:
    textInputState.setText(t)

  # Handle focus
  if enabled and window.buttonPressed[MouseLeft]:
    if sk.mouseInsideClip(window, rect(sk.pos, sk.size)):
      textInputState.focused = true
      # TODO: Set cursor position based on click.
    else:
      textInputState.focused = false

  let patch =
    if not enabled:
      "input.disabled.9patch"
    elif error:
      "input.error.9patch"
    else:
      "input.9patch"

  # Handle input if focused
  if enabled and textInputState.focused:
    sk.draw9Patch(patch, 6, sk.pos, sk.size, sk.theme.frameFocusColor)

    # Process runes
    for r in sk.inputRunes:
      textInputState.typeCharacter(r)

    textInputState.handleInput(window)

    # Sync back
    t = textInputState.getText()
  else:
    textInputState.focused = false
    sk.draw9Patch(patch, 6, sk.pos, sk.size)

  # Draw text and we should probably clip or scroll text.
  let padding = vec2(sk.theme.padding)
  let textColor =
    if not enabled:
      sk.theme.disabledTextColor
    elif error:
      sk.theme.errorTextColor
    else:
      sk.theme.defaultTextColor
  discard sk.drawText(sk.textStyle, t, sk.at + padding, textColor)

  # Draw cursor if focused and blinking is on.
  if textInputState.focused and (epochTime() * 2).int mod 2 == 0:
    # Calculate cursor position, which is inefficient but fine for now.
    let textBeforeCursor = $textInputState.runes[0 ..< min(textInputState.cursor, textInputState.runes.len)]
    let textSize = sk.getTextSize(sk.textStyle, textBeforeCursor)
    let cursorHeight = sk.atlas.fonts[sk.textStyle].lineHeight

    let cursorX = sk.at.x + padding.x + textSize.x
    let cursorY = sk.at.y + padding.y

    sk.drawRect(vec2(cursorX, cursorY), vec2(2, cursorHeight), textColor)

  sk.popLayout()
  sk.advance(vec2(width, height))

proc menuPopupStart*(sk: Silky, path: seq[string], popupAt: Vec2, popupWidth = 200) =
  ## Begin a popup; caller must call menuPopupEnd.
  menuEnsureState()
  sk.pushLayer(PopupsLayer)
  sk.pushClipRect(rect(vec2(0, 0), sk.rootSize))
  let layout = MenuLayout(
    origin: popupAt,
    width: popupWidth.float32,
    cursorY: sk.theme.menuPadding.float32
  )
  menuLayouts.add(layout)

proc menuPopupEnd*(sk: Silky) =
  ## Finish a popup and record its active area.
  let layout = menuLayouts[^1]
  let popupHeight = layout.cursorY + sk.theme.menuPadding.float32
  menuAddActive(rect(layout.origin, vec2(layout.width, popupHeight)))
  menuLayouts.setLen(menuLayouts.len - 1)
  sk.popClipRect()
  sk.popLayer()

template menuPopup(path: seq[string], popupAt: Vec2, popupWidth = 200, body: untyped) =
  ## Render a popup in a single pass with caller-provided width.
  sk.menuPopupStart(path, popupAt, popupWidth)
  try:
    body
  finally:
    sk.menuPopupEnd()

proc menuBarStart*(sk: Silky, window: Window) =
  ## Begin the horizontal application menu bar.
  menuEnsureState()
  menuState.activeRects.setLen(0)
  menuPathStack.setLen(0)

  let elevate = menuState.openPath.len > 0
  discard elevate

  let barHeight = sk.theme.headerHeight.float32
  sk.pushLayout(vec2(0, 0), vec2(sk.size.x, barHeight))
  sk.draw9Patch("header.9patch", 6, sk.pos, sk.size, sk.theme.headerBgColor)
  sk.at = sk.pos + vec2(sk.theme.menuPadding)

proc menuBarEnd*(sk: Silky, window: Window) =
  ## Finish the menu bar and handle outside-click closing.
  sk.popLayout()
  if menuState.openPath.len > 0 and window.buttonPressed[MouseLeft]:
    if not menuPointInside(menuState.activeRects, window.mousePos.vec2):
      menuState.openPath.setLen(0)

template menuBar*(body: untyped) =
  ## Horizontal application menu bar (File, Edit, ...).
  sk.menuBarStart(window)
  try:
    body
  finally:
    sk.menuBarEnd(window)

proc subMenuStart*(sk: Silky, window: Window, label: string, menuWidth = 200): MenuEntryContext =
  ## Begin a submenu entry; returns context describing whether it is open.
  menuEnsureState()
  let path = menuPathStack & @[label]
  let isRoot = menuLayouts.len == 0
  var ctx = MenuEntryContext(
    path: path,
    popupPos: vec2(0),
    popupWidth: menuWidth,
    open: false,
    isRoot: isRoot
  )

  if isRoot:
    let textSize = sk.getTextSize(sk.textStyle, label)
    let size = textSize + vec2(sk.theme.menuPadding.float32 * 2, sk.theme.menuPadding.float32 * 2)
    let menuRect = rect(sk.at, size)
    menuAddActive(menuRect)

    let hover = window.mousePos.vec2.overlaps(menuRect)
    var open = menuPathOpen(path)

    if hover and window.buttonReleased[MouseLeft]:
      if open:
        menuState.openPath.setLen(0)
      else:
        menuState.openPath = path
    elif hover and menuState.openPath.len > 0 and not window.buttonDown[MouseLeft]:
      menuState.openPath = path

    open = menuPathOpen(path)
    ctx.open = open

    if hover or open:
      sk.drawRect(menuRect.xy, menuRect.wh, sk.theme.menuRootHoverColor)
    discard sk.drawText(sk.textStyle, label, menuRect.xy + vec2(sk.theme.menuPadding), sk.theme.defaultTextColor)
    sk.at.x += size.x + sk.theme.spacing.float32

    if ctx.open:
      menuPathStack.add(label)
      ctx.popupPos = vec2(menuRect.x, menuRect.y + menuRect.h)
  else:
    var layout = menuLayouts[^1]
    let textSize = sk.getTextSize(sk.textStyle, label)
    let rowH = textSize.y + sk.theme.menuPadding.float32 * 2
    let rowPos = vec2(layout.origin.x + sk.theme.menuPadding.float32, layout.origin.y + layout.cursorY)
    let rowSize = vec2(layout.width - sk.theme.menuPadding.float32 * 2, rowH)
    let itemRect = rect(rowPos, rowSize)
    menuAddActive(itemRect)

    var open = menuPathOpen(path)
    let hover = window.mousePos.vec2.overlaps(itemRect)

    if hover and menuState.openPath.len >= path.len - 1:
      menuState.openPath = path

    open = menuPathOpen(path)
    ctx.open = open

    sk.drawRect(itemRect.xy, itemRect.wh, sk.theme.menuItemBgColor)
    if hover or open:
      sk.drawRect(itemRect.xy, itemRect.wh, sk.theme.menuItemHoverColor)
    discard sk.drawText(
      sk.textStyle,
      label,
      rowPos + vec2(sk.theme.textPadding),
      sk.theme.defaultTextColor
    )

    let arrowPos = vec2(itemRect.x + itemRect.w - textSize.y, rowPos.y + sk.theme.textPadding.float32)
    discard sk.drawText(sk.textStyle, ">", arrowPos, sk.theme.defaultTextColor)

    layout.cursorY += rowH

    if ctx.open:
      menuPathStack.add(label)
      ctx.popupPos = vec2(itemRect.x + itemRect.w, itemRect.y)

  return ctx

proc subMenuEnd*(sk: Silky, ctx: MenuEntryContext) =
  ## Finish a submenu entry and pop path if open.
  if ctx.open:
    menuPathStack.setLen(menuPathStack.len - 1)

template subMenu*(label: string, menuWidth = 200, body: untyped) =
  ## Menu entry that can contain other menu items.
  let ctx = sk.subMenuStart(window, label, menuWidth)
  try:
    if ctx.open:
      menuPopup(ctx.path, ctx.popupPos, menuWidth):
        body
  finally:
    sk.subMenuEnd(ctx)

proc menuItemStart*(sk: Silky, window: Window, label: string): MenuItemContext =
  ## Begin a menu item; returns context indicating click state.
  menuEnsureState()
  let layout = menuLayouts[^1]

  let textSize = sk.getTextSize(sk.textStyle, label)
  let rowH = textSize.y + sk.theme.menuPadding.float32 * 2
  let rowPos = vec2(layout.origin.x + sk.theme.menuPadding.float32, layout.origin.y + layout.cursorY)
  let rowSize = vec2(layout.width - sk.theme.menuPadding.float32 * 2, rowH)
  let itemRect = rect(rowPos, rowSize)
  menuAddActive(itemRect)

  let hover = window.mousePos.vec2.overlaps(itemRect)
  sk.drawRect(itemRect.xy, itemRect.wh, sk.theme.menuItemBgColor)
  if hover:
    sk.drawRect(itemRect.xy, itemRect.wh, sk.theme.menuPopupHoverColor)
  discard sk.drawText(
    sk.textStyle,
    label,
    rowPos + vec2(sk.theme.textPadding),
    sk.theme.defaultTextColor
  )

  var clicked = false
  if hover and window.buttonReleased[MouseLeft]:
    menuState.openPath.setLen(0)
    clicked = true

  return MenuItemContext(
    layout: layout,
    rowH: rowH,
    clicked: clicked
  )

proc menuItemEnd*(sk: Silky, ctx: MenuItemContext) =
  ## Finish a menu item and advance layout cursor.
  ctx.layout.cursorY += ctx.rowH

template menuItem*(label: string, body: untyped) =
  ## Leaf menu entry that runs `body` on click.
  let ctx = sk.menuItemStart(window, label)
  try:
    if ctx.clicked:
      body
  finally:
    sk.menuItemEnd(ctx)

template tooltip*(text: string) =
  ## Display a tooltip at the mouse cursor.
  ## This should be called after a widget when sk.showTooltip is true.
  let tooltipText = text
  sk.pushLayer(PopupsLayer)
  sk.pushClipRect(rect(vec2(0, 0), sk.rootSize))

  let textSize = sk.getTextSize(sk.textStyle, tooltipText)
  let tooltipSize = textSize + vec2(sk.theme.padding.float32 * 2, sk.theme.padding.float32 * 2)
  let mousePos = window.mousePos.vec2

  # Position tooltip near mouse, offset slightly to avoid cursor.
  var tooltipPos = mousePos + vec2(16, 16)

  # Keep tooltip on screen.
  let root = sk.rootSize
  if tooltipPos.x + tooltipSize.x > root.x:
    tooltipPos.x = root.x - tooltipSize.x - sk.theme.padding.float32
  if tooltipPos.y + tooltipSize.y > root.y:
    tooltipPos.y = mousePos.y - tooltipSize.y - 4

  # Ensure tooltip doesn't go off-screen left or top.
  tooltipPos.x = max(tooltipPos.x, sk.theme.padding.float32)
  tooltipPos.y = max(tooltipPos.y, sk.theme.padding.float32)

  sk.pushLayout(tooltipPos, tooltipSize)
  sk.draw9Patch("tooltip.9patch", 6, sk.pos, sk.size)
  discard sk.drawText(sk.textStyle, tooltipText, sk.pos + vec2(sk.theme.padding), sk.theme.defaultTextColor)
  sk.popLayout()

  sk.popClipRect()
  sk.popLayer()
