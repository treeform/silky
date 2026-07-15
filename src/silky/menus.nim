import
  vmath, bumpy, chroma

when defined(silkyTesting):
  import silky/[semantics, testing]
else:
  import silky/contexts, windy

type
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
  menuState*: MenuState = MenuState(
    openPath: @[],
    activeRects: @[]
  )
  menuLayouts: seq[MenuLayout]
  menuPathStack: seq[string]

proc vec2(v: SomeNumber): Vec2 =
  ## Create a Vec2 from a number.
  vec2(v.float32, v.float32)

proc vec2[A, B](x: A, y: B): Vec2 =
  ## Create a Vec2 from two numbers.
  vec2(x.float32, y.float32)

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

proc menuPopupStart*(sk: Silky, path: seq[string], popupAt: Vec2, popupWidth = 200) =
  ## Begin a popup; caller must call menuPopupEnd.
  menuEnsureState()
  sk.pushLayer(PopupsLayer)
  sk.pushRawClipRect(rect(vec2(0, 0), sk.rootSize))
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

  let barHeight = sk.theme.headerHeight.float32
  sk.pushLayout(vec2(0, 0), vec2(sk.size.x, barHeight))
  sk.draw9Patch("header.9patch", 6, sk.pos, sk.size, sk.theme.headerBgColor)
  sk.at = sk.pos + vec2(sk.theme.menuPadding)

proc menuBarEnd*(sk: Silky, window: Window) =
  ## Finish the menu bar and handle outside-click closing.
  sk.popLayout()
  if menuState.openPath.len > 0 and window.buttonPressed[MouseLeft]:
    if not menuPointInside(menuState.activeRects, sk.mousePos):
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

    let hover = sk.mousePos.overlaps(menuRect)
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
    let hover = sk.mousePos.overlaps(itemRect)

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

template subMenu*(label: string, menuWidth: int, body: untyped) =
  ## Menu entry that can contain other menu items.
  let ctx = sk.subMenuStart(window, label, menuWidth)
  try:
    if ctx.open:
      menuPopup(ctx.path, ctx.popupPos, menuWidth):
        body
  finally:
    sk.subMenuEnd(ctx)

template subMenu*(label: string, body: untyped) =
  ## Menu entry that can contain other menu items.
  subMenu(label, 200):
    body

template menu*(label: string, menuWidth: int, body: untyped) =
  ## Alias for subMenu. Prefer this name at the top of a menuBar.
  subMenu(label, menuWidth):
    body

template menu*(label: string, body: untyped) =
  ## Alias for subMenu. Prefer this name at the top of a menuBar.
  subMenu(label):
    body

proc menuItemStart*(
  sk: Silky,
  window: Window,
  label: string,
  enabled = true
): MenuItemContext =
  ## Begin a menu item; returns context indicating click state.
  menuEnsureState()
  doAssert menuLayouts.len > 0, "menuItem must be inside menuBar / subMenu"
  let layout = menuLayouts[^1]

  let textSize = sk.getTextSize(sk.textStyle, label)
  let rowH = textSize.y + sk.theme.menuPadding.float32 * 2
  let rowPos = vec2(layout.origin.x + sk.theme.menuPadding.float32, layout.origin.y + layout.cursorY)
  let rowSize = vec2(layout.width - sk.theme.menuPadding.float32 * 2, rowH)
  let itemRect = rect(rowPos, rowSize)
  menuAddActive(itemRect)

  let hover = enabled and sk.mousePos.overlaps(itemRect)
  sk.drawRect(itemRect.xy, itemRect.wh, sk.theme.menuItemBgColor)
  if hover:
    sk.drawRect(itemRect.xy, itemRect.wh, sk.theme.menuPopupHoverColor)
  discard sk.drawText(
    sk.textStyle,
    label,
    rowPos + vec2(sk.theme.textPadding),
    if enabled: sk.theme.defaultTextColor
    else: sk.theme.disabledTextColor
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
  menuItem(label, true):
    body

template menuItem*(label: string, enabled: bool, body: untyped) =
  ## Leaf menu entry that runs `body` on click when enabled.
  let ctx = sk.menuItemStart(window, label, enabled)
  try:
    if ctx.clicked:
      body
  finally:
    sk.menuItemEnd(ctx)
