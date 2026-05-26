import
  std/[random, strformat],
  bumpy, vmath, chroma,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("data/", "data/")
builder.addFont("data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont("data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("dist/atlas.png")

let window = newWindow(
  "Panels Example",
  ivec2(1200, 800),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

proc snapToPixels(rect: Rect): Rect =
  ## Snap rectangle coordinates to integer pixels.
  rect(rect.x.int.float32, rect.y.int.float32, rect.w.int.float32, rect.h.int.float32)

let sk = newSilky(window, "dist/atlas.png")

type
  AreaLayout = enum
    Horizontal
    Vertical

  Area = ref object
    layout*: AreaLayout
    areas*: seq[Area]
    panels*: seq[Panel]
    split*: float32
    selectedPanelNum*: int
    rect*: Rect # Calculated during draw

  Panel = ref object
    name*: string
    parentArea*: Area

  AreaScan = enum
    Header
    Body
    North
    South
    East
    West

const
  AreaHeaderHeight = 32.0
  AreaMargin = 6.0
  BackgroundColor = parseHtmlColor("#222222").rgbx

var
  rootArea: Area
  dragArea: Area # For resizing splits
  dragPanel: Panel # For moving panels
  dropHighlight: Rect
  showDropHighlight: bool

  maybeDragStartPos: Vec2
  maybeDragPanel: Panel

proc movePanels*(area: Area, panels: seq[Panel])

proc clear*(area: Area) =
  ## Clear the area.
  for panel in area.panels:
    panel.parentArea = nil
  for subarea in area.areas:
    subarea.clear()
  area.panels.setLen(0)
  area.areas.setLen(0)

proc removeBlankAreas*(area: Area) =
  ## Remove blank areas recursively.
  if area.areas.len > 0:
    assert area.areas.len == 2
    if area.areas[0].panels.len == 0 and area.areas[0].areas.len == 0:
      if area.areas[1].panels.len > 0:
        area.movePanels(area.areas[1].panels)
        area.areas.setLen(0)
      elif area.areas[1].areas.len > 0:
        let oldAreas = area.areas
        area.areas = area.areas[1].areas
        area.split = oldAreas[1].split
        area.layout = oldAreas[1].layout
      else:
        discard
    elif area.areas[1].panels.len == 0 and area.areas[1].areas.len == 0:
      if area.areas[0].panels.len > 0:
        area.movePanels(area.areas[0].panels)
        area.areas.setLen(0)
      elif area.areas[0].areas.len > 0:
        let oldAreas = area.areas
        area.areas = area.areas[0].areas
        area.split = oldAreas[0].split
        area.layout = oldAreas[0].layout
      else:
        discard

    for subarea in area.areas:
      removeBlankAreas(subarea)

proc addPanel*(area: Area, name: string) =
  ## Add a panel to the area.
  let panel = Panel(name: name, parentArea: area)
  area.panels.add(panel)

proc movePanel*(area: Area, panel: Panel) =
  ## Move a panel to this area.
  let idx = panel.parentArea.panels.find(panel)
  if idx != -1:
    panel.parentArea.panels.delete(idx)
  area.panels.add(panel)
  panel.parentArea = area

proc insertPanel*(area: Area, panel: Panel, index: int) =
  ## Insert a panel into this area at a specific index.
  let idx = panel.parentArea.panels.find(panel)
  var finalIndex = index

  # If moving within the same area, adjust index if we're moving forward
  if panel.parentArea == area and idx != -1:
    if idx < index:
      finalIndex = index - 1

  if idx != -1:
    panel.parentArea.panels.delete(idx)

  # Clamp index to be safe
  finalIndex = clamp(finalIndex, 0, area.panels.len)

  area.panels.insert(panel, finalIndex)
  panel.parentArea = area
  # Update selection to the new panel position
  area.selectedPanelNum = finalIndex

proc getTabInsertInfo(area: Area, mousePos: Vec2): (int, Rect) =
  ## Get the insert information for a tab.
  var x = area.rect.x + 4
  let headerH = AreaHeaderHeight

  # If no panels, insert at 0
  if area.panels.len == 0:
    return (0, rect(x, area.rect.y + 4, 4, headerH - 4))

  var bestIndex = 0
  var minDist = float32.high
  var bestX = x

  # Check before first tab (index 0)
  let dist0 = abs(mousePos.x - x)
  minDist = dist0
  bestX = x
  bestIndex = 0

  for i, panel in area.panels:
    let textSize = sk.getTextSize("Default", panel.name)
    let tabW = textSize.x + 16

    # The gap after this tab (index i + 1)
    let gapX = x + tabW + 2
    let dist = abs(mousePos.x - gapX)
    if dist < minDist:
      minDist = dist
      bestIndex = i + 1
      bestX = gapX

    x += tabW + 2

  return (bestIndex, rect(bestX - 2, area.rect.y + 4, 4, headerH - 4))

proc movePanels*(area: Area, panels: seq[Panel]) =
  ## Move multiple panels to this area.
  var panelList = panels # Copy
  for panel in panelList:
    area.movePanel(panel)

proc split*(area: Area, layout: AreaLayout) =
  ## Split the area.
  let
    area1 = Area(rect: area.rect) # inherit rect initially
    area2 = Area(rect: area.rect)
  area.layout = layout
  area.split = 0.5
  area.areas.add(area1)
  area.areas.add(area2)

proc scan*(area: Area): (Area, AreaScan, Rect) =
  ## Scan the area to find the target under mouse.
  let mousePos = window.mousePos.vec2
  var
    targetArea: Area
    areaScan: AreaScan
    resRect: Rect

  proc visit(area: Area) =
    if not mousePos.overlaps(area.rect):
      return

    if area.areas.len > 0:
      for subarea in area.areas:
        visit(subarea)
    else:
      let
        headerRect = rect(
          area.rect.xy,
          vec2(area.rect.w, AreaHeaderHeight)
        )
        bodyRect = rect(
          area.rect.xy + vec2(0, AreaHeaderHeight),
          vec2(area.rect.w, area.rect.h - AreaHeaderHeight)
        )
        northRect = rect(
          area.rect.xy + vec2(0, AreaHeaderHeight),
          vec2(area.rect.w, area.rect.h * 0.2)
        )
        southRect = rect(
          area.rect.xy + vec2(0, area.rect.h * 0.8),
          vec2(area.rect.w, area.rect.h * 0.2)
        )
        eastRect = rect(
          area.rect.xy + vec2(area.rect.w * 0.8, 0) + vec2(0, AreaHeaderHeight),
          vec2(area.rect.w * 0.2, area.rect.h - AreaHeaderHeight)
        )
        westRect = rect(
          area.rect.xy + vec2(0, 0) + vec2(0, AreaHeaderHeight),
          vec2(area.rect.w * 0.2, area.rect.h - AreaHeaderHeight)
        )

      if mousePos.overlaps(headerRect):
        areaScan = Header
        resRect = headerRect
      elif mousePos.overlaps(northRect):
        areaScan = North
        resRect = northRect
      elif mousePos.overlaps(southRect):
        areaScan = South
        resRect = southRect
      elif mousePos.overlaps(eastRect):
        areaScan = East
        resRect = eastRect
      elif mousePos.overlaps(westRect):
        areaScan = West
        resRect = westRect
      elif mousePos.overlaps(bodyRect):
        areaScan = Body
        resRect = bodyRect

      targetArea = area

  visit(rootArea)
  return (targetArea, areaScan, resRect)

proc initRootArea() =
  ## Initialize the root area with default panels.
  randomize()
  rootArea = Area()
  rootArea.split(Vertical)
  rootArea.split = 0.20

  rootArea.areas[0].addPanel("Super Panel 1")
  rootArea.areas[0].addPanel("Cool Panel 2")

  rootArea.areas[1].split(Horizontal)
  rootArea.areas[1].split = 0.5

  rootArea.areas[1].areas[0].addPanel("Nice Panel 3")
  rootArea.areas[1].areas[0].addPanel("The Other Panel 4")
  rootArea.areas[1].areas[0].addPanel("Panel 5")

  rootArea.areas[1].areas[1].addPanel("World Class Panel 6")
  rootArea.areas[1].areas[1].addPanel("FUN Panel 7")
  rootArea.areas[1].areas[1].addPanel("Amazing Panel 8")

proc regenerate() =
  ## Regenerate the panel layout randomly.
  rootArea = Area()

  var panelNum = 1
  proc iterate(area: Area, depth: int) =
    if rand(0 .. depth) < 2:
      # Split the area.
      if rand(0 .. 1) == 0:
        area.split(Horizontal)
      else:
        area.split(Vertical)
      area.split = rand(0.2 .. 0.8)
      iterate(area.areas[0], depth + 1)
      iterate(area.areas[1], depth + 1)
    else:
      # Don't split the area.
      for i in 0 ..< rand(1 .. 3):
        area.addPanel("Panel " & $panelNum)
        panelNum += 1
  iterate(rootArea, 0)

initRootArea()

proc drawAreaRecursive(area: Area, r: Rect) =
  ## Recursively draw an area and its subareas.
  area.rect = r.snapToPixels()

  if area.areas.len > 0:
    let m = AreaMargin / 2
    if area.layout == Horizontal:
      # Top/Bottom
      let splitPos = r.h * area.split

      # Handle split resizing
      let splitRect = rect(r.x, r.y + splitPos - 2, r.w, 4)

      if dragArea == nil and window.mousePos.vec2.overlaps(splitRect):
        sk.cursor = Cursor(kind: ResizeUpDownCursor)
        if window.buttonPressed[MouseLeft]:
          dragArea = area

      let r1 = rect(r.x, r.y, r.w, splitPos - m)
      let r2 = rect(r.x, r.y + splitPos + m, r.w, r.h - splitPos - m)
      drawAreaRecursive(area.areas[0], r1)
      drawAreaRecursive(area.areas[1], r2)

    else:
      # Left/Right
      let splitPos = r.w * area.split

      let splitRect = rect(r.x + splitPos - 2, r.y, 4, r.h)

      if dragArea == nil and window.mousePos.vec2.overlaps(splitRect):
        sk.cursor = Cursor(kind: ResizeLeftRightCursor)
        if window.buttonPressed[MouseLeft]:
          dragArea = area

      let r1 = rect(r.x, r.y, splitPos - m, r.h)
      let r2 = rect(r.x + splitPos + m, r.y, r.w - splitPos - m, r.h)
      drawAreaRecursive(area.areas[0], r1)
      drawAreaRecursive(area.areas[1], r2)

  elif area.panels.len > 0:
    # Draw Panel
    if area.selectedPanelNum > area.panels.len - 1:
      area.selectedPanelNum = area.panels.len - 1

    # Draw Header
    let headerRect = rect(r.x, r.y, r.w, AreaHeaderHeight)
    rectangle "panel.header:" & $cast[uint](area):
      box headerRect.x, headerRect.y, headerRect.w, headerRect.h
      patch "panel.header.9patch", 3

    # Draw Tabs
    var x = r.x + 4
    sk.pushClipRect(rect(r.x, r.y, r.w - 2, AreaHeaderHeight))
    for i, panel in area.panels:
      let textSize = sk.getTextSize("Default", panel.name)
      let tabW = textSize.x + 16
      let tabRect = rect(x, r.y + 4, tabW, AreaHeaderHeight - 4)

      let isSelected = i == area.selectedPanelNum
      let isHovered = window.mousePos.vec2.overlaps(tabRect)

      # Handle tab clicks and dragging.
      if isHovered:
        if window.buttonPressed[MouseLeft]:
          area.selectedPanelNum = i
          # Only start dragging if the mouse moves 10 pixels or more.
          maybeDragStartPos = window.mousePos.vec2
          maybeDragPanel = panel
        elif window.buttonDown[MouseLeft] and dragPanel == panel:
          # Dragging has started.
          discard

      if window.buttonDown[MouseLeft]:
        if maybeDragPanel != nil and (maybeDragStartPos - window.mousePos.vec2).length() > 10:
          dragPanel = maybeDragPanel
          maybeDragStartPos = vec2(0, 0)
          maybeDragPanel = nil
      else:
        maybeDragStartPos = vec2(0, 0)
        maybeDragPanel = nil

      rectangle "panel.tab:" & $cast[uint](panel):
        box tabRect.x, tabRect.y, tabRect.w, tabRect.h
        if isSelected:
          patch "panel.tab.selected.9patch", 3
        elif isHovered:
          patch "panel.tab.hover.9patch", 3
        else:
          patch "panel.tab.9patch", 3
        text "panel.tab.text:" & $cast[uint](panel):
          box 8, 6, tabRect.w - 16, tabRect.h - 8
          characters panel.name
          tint "#ffffff"

      x += tabW + 2
    sk.popClipRect()

    # Draw the content area for the selected panel.
    let contentRect = rect(r.x, r.y + AreaHeaderHeight, r.w, r.h - AreaHeaderHeight)
    let activePanel = area.panels[area.selectedPanelNum]
    let frameId = "panel:" & $cast[uint](activePanel)
    frame frameId:
      box contentRect.x, contentRect.y, contentRect.w, contentRect.h
      layout TopToBottom
      horizontalPadding 8
      verticalPadding 8
      itemSpacing 8
      h1text(activePanel.name)
      text "panel.body:" & $cast[uint](activePanel):
        characters "This is the content of " & activePanel.name
      for i in 0 ..< 20:
        text "panel.line:" & $cast[uint](activePanel) & ":" & $i:
          characters &"Scrollable line {i} for " & activePanel.name


window.onFrame = proc() =
  ## Main frame loop.
  sk.beginUI(window, window.size)

  sk.drawRect(vec2(0, 0), window.size.vec2, BackgroundColor)
  sk.cursor = Cursor(kind: ArrowCursor)

  # Update dragging split if active.
  if dragArea != nil:
    if not window.buttonDown[MouseLeft]:
      dragArea = nil
    else:
      if dragArea.layout == Horizontal:
        sk.cursor = Cursor(kind: ResizeUpDownCursor)
        dragArea.split = (window.mousePos.vec2.y - dragArea.rect.y) / dragArea.rect.h
      else:
        sk.cursor = Cursor(kind: ResizeLeftRightCursor)
        dragArea.split = (window.mousePos.vec2.x - dragArea.rect.x) / dragArea.rect.w
      dragArea.split = clamp(dragArea.split, 0.1, 0.9)

  # Update dragging panel if active.
  showDropHighlight = false
  if dragPanel != nil:
    if not window.buttonDown[MouseLeft]:
      # Drop
      let (targetArea, areaScan, _) = rootArea.scan()
      if targetArea != nil:
        case areaScan:
          of Header:
            let (idx, _) = targetArea.getTabInsertInfo(window.mousePos.vec2)
            targetArea.insertPanel(dragPanel, idx)
          of Body:
            targetArea.movePanel(dragPanel)
          of North:
            targetArea.split(Horizontal)
            targetArea.areas[0].movePanel(dragPanel)
            targetArea.areas[1].movePanels(targetArea.panels)
          of South:
            targetArea.split(Horizontal)
            targetArea.areas[1].movePanel(dragPanel)
            targetArea.areas[0].movePanels(targetArea.panels)
          of East:
            targetArea.split(Vertical)
            targetArea.areas[1].movePanel(dragPanel)
            targetArea.areas[0].movePanels(targetArea.panels)
          of West:
            targetArea.split(Vertical)
            targetArea.areas[0].movePanel(dragPanel)
            targetArea.areas[1].movePanels(targetArea.panels)

        rootArea.removeBlankAreas()
      dragPanel = nil
    else:
      # Continue dragging and show highlight.
      let (targetArea, areaScan, rect) = rootArea.scan()
      dropHighlight = rect
      showDropHighlight = true

      if targetArea != nil and areaScan == Header:
         let (_, highlightRect) = targetArea.getTabInsertInfo(window.mousePos.vec2)
         dropHighlight = highlightRect

  ui:
    drawAreaRecursive(rootArea, rect(0, 1, window.size.x.float32, window.size.y.float32))

    # Draw drop highlight and ghost when dragging a panel.
    if showDropHighlight and dragPanel != nil:
      rectangle "drop highlight":
        box dropHighlight.x, dropHighlight.y, dropHighlight.w, dropHighlight.h
        tint rgbx(255, 255, 0, 100)

      let label = dragPanel.name
      let textSize = sk.getTextSize("Default", label)
      let ghostPos = window.mousePos.vec2 + vec2(10, 10)
      rectangle "drag ghost":
        box ghostPos.x, ghostPos.y, textSize.x + 16, textSize.y + 8
        patch "tooltip.9patch", 4
        tint rgbx(255, 255, 255, 200)
        text "drag ghost text":
          box 8, 4, textSize.x, textSize.y
          characters label
          tint "#ffffff"

    # Regenerate the layout when R is pressed.
    if window.buttonPressed[KeyR]:
      regenerate()

    let ms = sk.avgFrameTime * 1000
    text "frame time":
      box sk.size.x - 250, 20, 230, 22
      characters &"frame time: {ms:>7.3f}ms"

  sk.endUi()
  window.swapBuffers()

  if window.cursor.kind != sk.cursor.kind:
    window.cursor = sk.cursor

while not window.closeRequested:
  pollEvents()
