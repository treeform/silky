import
  std/[tables, unicode, times, options],
  vmath, bumpy, chroma

when defined(silkyTesting):
  import silky/[semantics, testing, profiles]
else:
  import silky/[contexts, profiles], windy

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

  Interaction* = enum
    None,
    Pressed,
    Held,
    Released,
    ReleasedOutside,
    Hovered,
    Disabled,
    Error

var
  subWindowStates*: Table[string, SubWindowState]
  frameStates*: Table[string, FrameState]
  scrubberStates*: Table[string, ScrubberState]
  dropDownStates*: Table[uint, DropDownState]

proc mouseHover(
  interactor: var Interactor,
  mousePos: Vec2,
  clipRect: Rect,
  layer: int,
  widgetRect: Rect
): bool =
  ## Resolve mouse hovering by taking information from the last frame.
  inc interactor.currentId

  let hovering = mousePos.overlaps(widgetRect) and mousePos.overlaps(clipRect)

  if hovering and layer >= interactor.warmLayer:
    interactor.warmLayer = layer
    interactor.warmId = interactor.currentId

  return interactor.hotId == interactor.currentId and hovering

proc mouseHover*(sk: Silky, window: Window, r: Rect): bool =
  discard window
  let hit = sk.interactor.mouseHover(sk.mousePos, sk.clipRect, sk.currentDrawLayer, r)
  not sk.mouseConsumed and hit

proc interact*(
  sk: Silky,
  widgetRect: Rect,
  isEnabled: bool,
  isError: bool = false
): Interaction =
  ## Determine the interaction given mouse and widget states.
  let
    hover = sk.interactor.mouseHover(sk.mousePos, sk.clipRect, sk.currentDrawLayer, widgetRect)
    pressed = sk.buttonPressed[MouseLeft]
    down = sk.buttonDown[MouseLeft]
    released = sk.buttonReleased[MouseLeft]

  if not isEnabled:
    return Disabled
  if isError:
    return Error
  if not hover and released:
    return ReleasedOutside
  if not hover:
    return None
  if pressed:
    return Pressed
  if down:
    return Held
  if released:
    return Released
  return Hovered

proc vec2(v: SomeNumber): Vec2 =
  ## Create a Vec2 from a number.
  vec2(v.float32, v.float32)

proc vec2[A, B](x: A, y: B): Vec2 =
  ## Create a Vec2 from two numbers.
  vec2(x.float32, y.float32)

proc mouseOverlap(sk: Silky, window: Window, r: Rect): bool =
  sk.mousePos.overlaps(r) and sk.mousePos.overlaps(sk.clipRect)

proc subWindowStart*(
    sk: Silky,
    window: Window,
    title: string,
    show: var bool,
    initialOrigin: Option[Vec2],
    initialSize: Option[Vec2]
  ): SubWindowState {.measure.} =
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
  let
    titleBarRect = rect(sk.pos, sk.size)
    titleBarInteraction = sk.interact(titleBarRect, true)

  case titleBarInteraction
  of Disabled, None, Error, ReleasedOutside:
    sk.draw9Patch("header.9patch", 6, sk.pos, sk.size)
  of Pressed:
    subWindowState.dragOffset = sk.mousePos - subWindowState.pos
    subWindowState.dragging = true
    sk.draw9Patch("header.dragging.9patch", 6, sk.pos, sk.size)
  of Held:
    discard
  of Hovered, Released:
    subWindowState.dragging = false
    sk.draw9Patch("header.hover.9patch", 6, sk.pos, sk.size)

  if subWindowState.dragging:
    subWindowState.pos = sk.mousePos - subWindowState.dragOffset

  sk.at += vec2(sk.theme.textPadding)

  # Handle minimizing/maximizing button for the window.
  let
    minimizeSize = sk.getImageSize("maximized")
    minimizeRect = rect(
      sk.at.x,
      sk.at.y,
      minimizeSize.x.float32,
      minimizeSize.y.float32
    )
    minimizeInteraction = sk.interact(minimizeRect, true)

  if minimizeInteraction == Pressed:
    subWindowState.minimized = not subWindowState.minimized

  if subWindowState.minimized:
    sk.drawImage("minimized", minimizeRect.xy)
  else:
    sk.drawImage("maximized", minimizeRect.xy)

  sk.at.x += sk.getImageSize("maximized").x.float32 + sk.theme.padding.float32

  # Draw the title.
  discard sk.drawText(sk.textStyle, title, sk.at, sk.theme.defaultTextColor)

  # Handle closing button for the window.
  let
    closeSize = sk.getImageSize("close")
    closeRect = rect(
      sk.at.x + sk.size.x - closeSize.x.float32 - sk.theme.padding.float32 * 5,
      sk.at.y,
      closeSize.x.float32,
      closeSize.y.float32
    )
    closeInteraction = sk.interact(closeRect, true)

  if closeInteraction == Released:
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
  if subWindowState.minimized:
    sk.popLayout()
    return

  let
    resizeHandleSize = sk.getImageSize("resize")
    resizeHandleRect = rect(
      sk.pos.x + sk.size.x - resizeHandleSize.x.float32 - sk.theme.border.float32,
      sk.pos.y + sk.size.y - resizeHandleSize.y.float32 - sk.theme.border.float32,
      resizeHandleSize.x.float32,
      resizeHandleSize.y.float32
    )
    resizeHandleInteraction = sk.interact(resizeHandleRect, true)

  case resizeHandleInteraction
  of Pressed:
    subWindowState.resizing = true
    subWindowState.resizeOffset = sk.mousePos - subWindowState.size
  of Hovered, Released, ReleasedOutside:
    subWindowState.resizing = false
  else:
    discard

  if subWindowState.resizing:
    subWindowState.size = sk.mousePos - subWindowState.resizeOffset
    subWindowState.size.x = max(subWindowState.size.x, 200f)
    subWindowState.size.y = max(subWindowState.size.y, float32(sk.theme.headerHeight * 2 + sk.theme.border * 2))

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
  if sk.mouseOverlap(window, rect(sk.pos, sk.size)):
    if not frameState.scrollingY and window.scrollDelta.y != 0:
      frameState.scrollPos.y += window.scrollDelta.y * ScrollSpeed
      frameState.scrollPos.y = clamp(frameState.scrollPos.y, 0.0, scrollMax.y)
    if not frameState.scrollingX and window.scrollDelta.x != 0:
      frameState.scrollPos.x += window.scrollDelta.x * ScrollSpeed
      frameState.scrollPos.x = clamp(frameState.scrollPos.x, 0.0, scrollMax.x)

  # Draw Y scrollbar.
  if contentSize.y > sk.size.y:
    let
      scrollSize = contentSize.y
      scrollbarTrackRect = rect(
        sk.pos.x + sk.size.x - 10,
        sk.pos.y + 2,
        8,
        sk.size.y - 4 - 10
      )
    sk.draw9Patch("scrollbar.track.9patch", 4, scrollbarTrackRect.xy, scrollbarTrackRect.wh)

    let
      scrollPosPercent = if scrollMax.y > 0: frameState.scrollPos.y / scrollMax.y else: 0.0
      scrollSizePercent = sk.size.y / scrollSize
      scrollbarHandleRect = rect(
        scrollbarTrackRect.x,
        scrollbarTrackRect.y + (scrollbarTrackRect.h - (scrollbarTrackRect.h * scrollSizePercent)) * scrollPosPercent,
        8,
        scrollbarTrackRect.h * scrollSizePercent
      )
      scrollbarHandleInteraction = sk.interact(scrollbarHandleRect, true)

    # Handle scrollbar Y dragging.
    if frameState.scrollingY:
      let
        relativeY = sk.mousePos.y - frameState.scrollDragOffset.y - scrollbarTrackRect.y
        availableTrackHeight = scrollbarTrackRect.h - scrollbarHandleRect.h
      if availableTrackHeight > 0:
        let newScrollPosPercent = clamp(relativeY / availableTrackHeight, 0.0, 1.0)
        frameState.scrollPos.y = newScrollPosPercent * scrollMax.y
    elif scrollbarHandleInteraction == Pressed:
      frameState.scrollingY = true
      frameState.scrollDragOffset.y = sk.mousePos.y - scrollbarHandleRect.y

    sk.draw9Patch("scrollbar.9patch", 4, scrollbarHandleRect.xy, scrollbarHandleRect.wh)

  # Draw X scrollbar.
  if contentSize.x > sk.size.x:
    let
      scrollSize = contentSize.x
      scrollbarTrackRect = rect(
        sk.pos.x + 2,
        sk.pos.y + sk.size.y - 10,
        sk.size.x - 4 - 10,
        8
      )
    sk.draw9Patch("scrollbar.track.9patch", 4, scrollbarTrackRect.xy, scrollbarTrackRect.wh)

    let
      scrollPosPercent = if scrollMax.x > 0: frameState.scrollPos.x / scrollMax.x else: 0.0
      scrollSizePercent = sk.size.x / scrollSize
      scrollbarHandleRect = rect(
        scrollbarTrackRect.x + (scrollbarTrackRect.w - (scrollbarTrackRect.w * scrollSizePercent)) * scrollPosPercent,
        scrollbarTrackRect.y,
        scrollbarTrackRect.w * scrollSizePercent,
        8
      )
      scrollbarHandleInteraction = sk.interact(scrollbarHandleRect, true)

    # Handle scrollbar X dragging.
    if frameState.scrollingX:
      let
        relativeX = sk.mousePos.x - frameState.scrollDragOffset.x - scrollbarTrackRect.x
        availableTrackWidth = scrollbarTrackRect.w - scrollbarHandleRect.w
      if availableTrackWidth > 0:
        let newScrollPosPercent = clamp(relativeX / availableTrackWidth, 0.0, 1.0)
        frameState.scrollPos.x = newScrollPosPercent * scrollMax.x
    elif scrollbarHandleInteraction == Pressed:
      frameState.scrollingX = true
      frameState.scrollDragOffset.x = sk.mousePos.x - scrollbarHandleRect.x

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
  ## Create a button with enabled and error states.
  let
    textSize = sk.getTextSize(sk.textStyle, label)
    buttonSize = textSize + vec2(sk.theme.padding) * 2
    buttonRect = rect(sk.at, buttonSize)

  when defined(silkyTesting):
    sk.beginWidget("Button", text = label, rect = buttonRect)

  let
    textColor =
      if not isEnabled:
        sk.theme.disabledTextColor
      elif isError:
        sk.theme.errorTextColor
      else:
        sk.theme.defaultTextColor
    interaction = sk.interact(buttonRect, isEnabled, isError)

  let patch = case interaction
    of Error:
      "button.error.9patch"
    of Disabled:
      "button.disabled.9patch"
    of None, ReleasedOutside:
      "button.9patch"
    of Pressed, Held:
      "button.down.9patch"
    of Hovered, Released:
      "button.hover.9patch"

  sk.draw9Patch(patch, 8, sk.at, buttonSize)

  if interaction == Released:
    body

  when defined(silkyTesting):
    let
      pressed = interaction == Pressed or interaction == Held
      hovered = pressed or interaction == Hovered
    sk.setWidgetState(enabled = isEnabled, pressed = pressed, hovered = hovered)

  let at = sk.at + vec2(sk.theme.padding)
  discard sk.drawText(sk.textStyle, label, at, textColor)
  when defined(silkyTesting):
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
    interaction = sk.interact(buttonRect, true, false)

  var patch = "button.9patch"

  case interaction
  of Hovered:
    sk.hover = true
    sk.tooltipAnchor = buttonRect
    patch = "button.hover.9patch"
  of Pressed, Held:
    sk.hover = true
    sk.tooltipAnchor = buttonRect
    patch = "button.down.9patch"
  of Released:
    sk.hover = false
    body
  else:
    sk.hover = false

  sk.draw9Patch(patch, 8, sk.at - m2, s2, sk.theme.iconButtonDownColor)
  sk.drawImage(image, sk.at)
  sk.stretchAt = max(sk.stretchAt, sk.at + s2)
  sk.at += vec2(32 + sk.padding, 0)

template clickableIcon*(image: string, on: bool, body) =
  ## Create an clickable icon with no background and no padding.
  let
    imageSize = sk.getImageSize(image)
    s2 = imageSize
    hoverColor = sk.theme.iconClickableHoverColor
    upColor = sk.theme.iconClickableUpColor
    onColor = sk.theme.iconClickableOnColor
    offColor = sk.theme.iconClickableOffColor
    iconRect = rect(sk.at, s2)
    interaction = sk.interact(iconRect, true, false)

  var color =
    if interaction in [Pressed, Held]:
      upColor
    elif on:
      onColor
    else:
      offColor

  sk.hover = interaction in [Hovered, Pressed, Held]
  if sk.hover:
    sk.tooltipAnchor = iconRect

  if interaction == Pressed:
    body

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

  when defined(silkyTesting):
    sk.beginWidget("RadioButton", text = label, rect = hitRect)

  let interaction = sk.interact(hitRect, true)

  if interaction == Released:
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

  when defined(silkyTesting):
    let
      pressed = interaction == Pressed or interaction == Held
      hovered = pressed or interaction == Hovered
    sk.setWidgetState(enabled = true, pressed = pressed, hovered = hovered, checked = on)
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

  when defined(silkyTesting):
    sk.beginWidget("CheckBox", text = label, rect = hitRect)

  let interaction = sk.interact(hitRect, true)

  if interaction == Released:
    value = not value

  let
    iconPos = vec2(sk.at.x, sk.at.y + (height - iconSize.y.float32) * 0.5)
    textPos = vec2(
      iconPos.x + iconSize.x.float32 + sk.theme.spacing.float32,
      sk.at.y + (height - textSize.y) * 0.5
    )
  sk.drawImage(if value: "check.on" else: "check.off", iconPos)
  discard sk.drawText(sk.textStyle, label, textPos, sk.theme.defaultTextColor)

  when defined(silkyTesting):
    let
      pressed = interaction == Pressed or interaction == Held
      hovered = pressed or interaction == Hovered
    sk.setWidgetState(enabled = true, pressed = pressed, hovered = hovered, checked = value)
    sk.endWidget()
  sk.advance(vec2(width, height))

template dropDown*[T](selected: var T, options: openArray[T]) =
  ## Dropdown styled like input text; options render in a new layer.
  let id = cast[uint](addr selected)

  if id notin dropDownStates:
    dropDownStates[id] = DropDownState()

  let
    state = dropDownStates[id]
    font = sk.atlas.fonts[sk.textStyle]
    height = font.lineHeight + sk.theme.padding.float32 * 2
    width = sk.size.x - sk.theme.padding.float32 * 3
    arrowSize = sk.getImageSize("droparrow")
    dropRect = rect(sk.at, vec2(width, height))
    displayText =
      when T is string:
        selected
      else:
        $selected

  # Toggle open/close on click.
  when defined(silkyTesting):
    sk.beginWidget("DropDown", text = displayText, rect = dropRect)

  let interaction = sk.interact(dropRect, true)

  if interaction == Released:
    state.open = not state.open

  # Draw control body.
  sk.pushLayout(sk.at, vec2(width, height))
  let hovered = interaction in [Pressed, Held, Hovered]
  let bgColor = if state.open or hovered: sk.theme.dropdownHoverBgColor else: sk.theme.dropdownBgColor
  sk.draw9Patch("dropdown.9patch", 6, sk.pos, sk.size, bgColor)
  discard sk.drawText(sk.textStyle, displayText, sk.at + vec2(sk.theme.padding), sk.theme.defaultTextColor)
  let arrowPos = vec2(
    sk.pos.x + sk.size.x - arrowSize.x.float32 - sk.theme.padding.float32,
    sk.pos.y + (height - arrowSize.y.float32) * 0.5
  )
  sk.drawImage("droparrow", arrowPos)
  sk.popLayout()
  sk.advance(vec2(width, height))

  when defined(silkyTesting):
    sk.endWidget()

  if state.open and options.len > 0:
    sk.pushLayer(PopupsLayer)
    sk.pushRawClipRect(rect(vec2(0, 0), sk.rootSize))

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
        isSelected = selected == opt
        interaction = sk.interact(rowRect, true)

      let rowHover = interaction in [Pressed, Held, Hovered]

      if interaction == Released:
        selected = opt
        state.open = false

      if rowHover:
        sk.drawRect(rowRect.xy, rowRect.wh, sk.theme.menuPopupHoverColor)
      elif isSelected:
        sk.drawRect(rowRect.xy, rowRect.wh, sk.theme.menuPopupSelectedColor)
      let optText =
        when T is string:
          opt
        else:
          $opt
      discard sk.drawText(sk.textStyle, optText, textPos, sk.theme.defaultTextColor)

    sk.popLayout()

    # Close when clicking outside (bypass mouseConsumed — this is an intentional raw check).
    if window.buttonPressed[MouseLeft] and
      not window.mousePos.vec2.overlaps(dropRect) and
      not window.mousePos.vec2.overlaps(popupRect):
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
        isSelected = selectedIndex == i
        interaction = sk.interact(rowRect, true)
        rowHover = interaction in [Pressed, Held, Hovered]

      if interaction == Released:
        selectedIndex = i

      if rowHover:
        sk.drawRect(rowRect.xy, rowRect.wh, sk.theme.menuPopupHoverColor)
      elif isSelected:
        sk.drawRect(rowRect.xy, rowRect.wh, sk.theme.menuPopupSelectedColor)
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
    width = sk.size.x - sk.theme.padding.float32 * 3
    controlRect = rect(sk.at, vec2(width, height))
    trackStart = controlRect.x + handleSize.x / 2
    trackEnd = controlRect.x + width - handleSize.x / 2
    travel = max(0f, trackEnd - trackStart)
    travelSafe = if travel <= 0: 1f else: travel

  # Draw track.
  sk.draw9Patch("scrubber.body.9patch", 4, controlRect.xy, controlRect.wh)

  let
    # Normalize current value.
    norm = if range == 0: 0f else: clamp((v - minF) / range, 0f, 1f)
    # Handle geometry.
    handlePos = vec2(trackStart + norm * travel - handleSize.x * 0.5, controlRect.y + (height - handleSize.y) * 0.5)
    handleRect = rect(handlePos, handleSize)
    handleInteraction = sk.interact(handleRect, true)
    controlInteraction = sk.interact(controlRect, true)
    handleReleased = handleInteraction in [Released, ReleasedOutside]
    controlReleased = controlInteraction in [Released, ReleasedOutside]
    released = handleReleased or controlReleased
    pressed = handleInteraction == Pressed or controlInteraction == Pressed

  # Dragging logic.
  if scrubState.dragging and released:
    scrubState.dragging = false

  if scrubState.dragging:
    let t = clamp((sk.mousePos.x - trackStart) / travelSafe, 0f, 1f)
    value = (minF + t * range).T
  elif pressed:
    scrubState.dragging = true
    let t = clamp((sk.mousePos.x - trackStart) / travelSafe, 0f, 1f)
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

template tooltip*(text: string) =
  ## Draws a tooltip with fade-in and stem image.
  let tooltipText = text
  sk.pushLayer(PopupsLayer)
  sk.pushRawClipRect(rect(vec2(0, 0), sk.rootSize))

  let
    textSize = sk.getTextSize(sk.textStyle, tooltipText)
    pad = sk.theme.padding.float32
    tooltipSize = textSize + vec2(pad * 2, pad * 2)
    root = sk.rootSize
    hasAnchor = sk.tooltipAnchor.w > 0 and
      sk.tooltipAnchor.h > 0
    anchorCenter = sk.tooltipAnchor.xy +
      vec2(sk.tooltipAnchor.w, sk.tooltipAnchor.h) * 0.5

  # Position centered on anchor below, flip above if needed.
  var tooltipPos =
    if hasAnchor:
      vec2(
        anchorCenter.x - tooltipSize.x * 0.5,
        sk.tooltipAnchor.y + sk.tooltipAnchor.h + 8
      )
    else:
      sk.mousePos + vec2(16, 16)
  tooltipPos += sk.tooltipOffset
  if tooltipPos.y + tooltipSize.y > root.y:
    tooltipPos.y = sk.tooltipAnchor.y - tooltipSize.y - 8
  if tooltipSize.x <= root.x:
    tooltipPos.x = clamp(
      tooltipPos.x, pad, root.x - tooltipSize.x - pad)
  if tooltipSize.y <= root.y:
    tooltipPos.y = max(tooltipPos.y, pad)

  # Reset fade when anchor changes.
  if not sk.tooltipActive or
      sk.tooltipAnchor != sk.tooltipLastAnchor:
    sk.tooltipPos = tooltipPos
    sk.tooltipFadeInTime = 0
  sk.tooltipLastAnchor = sk.tooltipAnchor
  sk.showTooltip = true

  let
    fadeAlpha = clamp(
      sk.tooltipFadeInTime / sk.tooltipFadeInDuration,
      0.0, 1.0
    ).float32
    fadeByte = (255.0 * fadeAlpha).uint8
    fadeColor = rgbx(fadeByte, fadeByte, fadeByte, fadeByte)
  sk.pushLayout(sk.tooltipPos, tooltipSize)
  sk.draw9Patch(
    "tooltip.9patch", 6, sk.pos, sk.size, fadeColor
  )

  # Draw stem on top, pointing toward anchor.
  if hasAnchor and "tooltip.stem" in sk.atlas.entries:
    let
      stem = sk.atlas.entries["tooltip.stem"]
      stemW = stem.width.float32
      stemH = stem.height.float32
      halfH = stemH * 0.5
      uvPos = vec2(stem.x.float32, stem.y.float32)
      uv0 = uvPos
      uv1 = uvPos + vec2(stemW, 0)
      uv2 = uvPos + vec2(stemW, stemH)
      uv3 = uvPos + vec2(0, stemH)
      colors = [fadeColor, fadeColor, fadeColor]
      above = anchorCenter.y < sk.pos.y + sk.size.y * 0.5
      x = clamp(anchorCenter.x,
        sk.pos.x + stemW * 0.5,
        sk.pos.x + sk.size.x - stemW * 0.5)
      cy =
        if above: sk.pos.y + 1.0
        else: sk.pos.y + sk.size.y - 1.0
      p0 = vec2(x - stemW * 0.5, cy - halfH)
      p1 = vec2(x + stemW * 0.5, cy - halfH)
      p2 = vec2(x + stemW * 0.5, cy + halfH)
      p3 = vec2(x - stemW * 0.5, cy + halfH)
      t0 = if above: uv3 else: uv0
      t1 = if above: uv2 else: uv1
      t2 = if above: uv1 else: uv2
      t3 = if above: uv0 else: uv3
    sk.drawTriangle([p0, p1, p2], [t0, t1, t2], colors)
    sk.drawTriangle([p0, p2, p3], [t0, t2, t3], colors)

  let
    baseColor = sk.theme.defaultTextColor
    textColor = rgbx(
      (baseColor.r.float32 * fadeAlpha).uint8,
      (baseColor.g.float32 * fadeAlpha).uint8,
      (baseColor.b.float32 * fadeAlpha).uint8,
      (baseColor.a.float32 * fadeAlpha).uint8,
    )
  discard sk.drawText(
    sk.textStyle, tooltipText,
    sk.pos + vec2(sk.theme.padding), textColor
  )
  sk.popLayout()

  sk.popClipRect()
  sk.popLayer()
