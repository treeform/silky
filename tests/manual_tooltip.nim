## Manual test for tooltips at edges and with oversized content.
## Hover over each box to see how tooltips clamp to the window.

import
  windy, bumpy, pixie, vmath, chroma,
  silky

const
  BackgroundColor = rgbx(26, 26, 46, 255)
  BoxColor = rgbx(60, 80, 120, 255)
  BoxHoverColor = rgbx(90, 120, 170, 255)
  BoxSize = vec2(120, 80)
  WindowSize = ivec2(900, 700)
  LongText = """This is a very long tooltip that should overflow the window width if not clamped properly by the layout code somewhere inside the tooltip widget."""
  TallText = static:
    var s = ""
    for i in 1 .. 40:
      s.add("Line " & $i & ".\n")
    s
  HugeText = static:
    var s = ""
    for i in 1 .. 60:
      s.add("A very wide line of text that keeps going and going. " & $i & "\n")
    s

let builder = newAtlasBuilder(1024, 4)
builder.addDir("tests/data/", "tests/data/")
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("tests/dist/atlas.png")

let window = newWindow(
  "Tooltip Test",
  WindowSize,
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

let sk = newSilky(window, "tests/dist/atlas.png")

template hoverBox(
  nodeId: static string,
  pos: Vec2,
  size: Vec2,
  label: string,
  tip: string
) =
  ## Draw a labeled box that shows a tooltip when hovered.
  rectangle nodeId:
    box pos.x, pos.y, size.x, size.y
    tint BoxColor
    onHover:
      tint BoxHoverColor
      sk.hover = true
      if sk.shouldShowTooltip:
        sk.tooltipAnchor = sk.scopeRect()
        tooltip(tip)
    text nodeId & ".label":
      box 0, 0, size.x, size.y
      characters label
      textAlign CenterAlign, MiddleAlign

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(BackgroundColor)

  let
    winSize = vec2(window.size.x.float32, window.size.y.float32)
    centerX = (winSize.x - BoxSize.x) * 0.5
    centerY = (winSize.y - BoxSize.y) * 0.5
    edgeMargin = 4.0

  ui:
    hoverBox(
      "tl",
      vec2(edgeMargin, edgeMargin),
      BoxSize,
      "TL",
      "Top-left corner tooltip."
    )
    hoverBox(
      "tr",
      vec2(winSize.x - BoxSize.x - edgeMargin, edgeMargin),
      BoxSize,
      "TR",
      "Top-right corner tooltip."
    )
    hoverBox(
      "bl",
      vec2(edgeMargin, winSize.y - BoxSize.y - edgeMargin),
      BoxSize,
      "BL",
      "Bottom-left corner tooltip."
    )
    hoverBox(
      "br",
      vec2(winSize.x - BoxSize.x - edgeMargin, winSize.y - BoxSize.y - edgeMargin),
      BoxSize,
      "BR",
      "Bottom-right corner tooltip."
    )
    hoverBox(
      "top",
      vec2(centerX, edgeMargin),
      BoxSize,
      "Top",
      "Top edge tooltip."
    )
    hoverBox(
      "bottom",
      vec2(centerX, winSize.y - BoxSize.y - edgeMargin),
      BoxSize,
      "Bottom",
      "Bottom edge tooltip."
    )
    hoverBox(
      "left",
      vec2(edgeMargin, centerY),
      BoxSize,
      "Left",
      "Left edge tooltip."
    )
    hoverBox(
      "right",
      vec2(winSize.x - BoxSize.x - edgeMargin, centerY),
      BoxSize,
      "Right",
      "Right edge tooltip."
    )

    let
      centerGap = 16.0
      centerRowY = centerY
      centerLeftX = centerX - BoxSize.x - centerGap
      centerRightX = centerX + BoxSize.x + centerGap
    hoverBox("wide", vec2(centerLeftX, centerRowY), BoxSize, "Wide", LongText)
    hoverBox("tall", vec2(centerX, centerRowY), BoxSize, "Tall", TallText)
    hoverBox("huge", vec2(centerRightX, centerRowY), BoxSize, "Huge", HugeText)

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
