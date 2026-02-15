## Demonstrates layout stacking directions with adjustable padding, spacing,
## and number of boxes. Use the controls at the top to tweak values and pick
## a stacking direction from the dropdown. The colored boxes below respond
## to every change in real time.

import
  std/[strformat],
  opengl, windy, bumpy, vmath, chroma,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("tests/data/", "tests/data/")
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("tests/dist/atlas.png", "tests/dist/atlas.json")

let window = newWindow(
  "Layout Test",
  ivec2(900, 700),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

const
  BackgroundColor = parseHtmlColor("#1a1a2e").rgbx
  AreaBgColor = parseHtmlColor("#2a2a3e").rgbx
  BoxColors = [
    parseHtmlColor("#e74c3c").rgbx,
    parseHtmlColor("#3498db").rgbx,
    parseHtmlColor("#2ecc71").rgbx,
    parseHtmlColor("#f39c12").rgbx,
    parseHtmlColor("#9b59b6").rgbx,
    parseHtmlColor("#1abc9c").rgbx,
    parseHtmlColor("#e67e22").rgbx,
    parseHtmlColor("#e84393").rgbx,
    parseHtmlColor("#00cec9").rgbx,
    parseHtmlColor("#6c5ce7").rgbx,
  ]

let sk = newSilky("tests/dist/atlas.png", "tests/dist/atlas.json")

var
  layoutPadding = 16.0f
  layoutSpacing = 8.0f
  numBoxes = 5.0f
  boxSize = 48.0f
  direction = "Left, Top to Bottom"

const Directions = [
  "Left, Top to Bottom",
  "Left, Bottom to Top",
  "Top, Left to Right",
  "Top, Right to Left",
  "Right, Top to Bottom",
  "Right, Bottom to Top",
  "Bottom, Left to Right",
  "Bottom, Right to Left",
]

proc toStackDirection(s: string): StackDirection =
  ## Convert a direction label to a StackDirection enum.
  case s:
  of "Left, Top to Bottom": TopToBottom
  of "Left, Bottom to Top": BottomToTop
  of "Top, Left to Right": LeftToRight
  of "Top, Right to Left": RightToLeft
  of "Right, Top to Bottom": RightTopToBottom
  of "Right, Bottom to Top": RightBottomToTop
  of "Bottom, Left to Right": BottomLeftToRight
  of "Bottom, Right to Left": BottomRightToLeft
  else: TopToBottom

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(BackgroundColor)

  const Margin = 20.0f

  sk.at = vec2(Margin, Margin)

  # Title.
  h1text("Layout Test")

  # Controls.
  scrubber("padding", layoutPadding, 0.0, 60.0, &"Padding: {layoutPadding:.0f}")
  scrubber("spacing", layoutSpacing, 0.0, 40.0, &"Spacing: {layoutSpacing:.0f}")
  scrubber("numBoxes", numBoxes, 1.0, 10.0, &"Boxes: {numBoxes:.0f}")
  scrubber("boxSize", boxSize, 16.0, 120.0, &"Box size: {boxSize:.0f}")
  text("Direction:")
  dropDown(direction, Directions)

  # Layout area.
  let
    controlsBottom = sk.at.y + 8
    areaPos = vec2(Margin, controlsBottom)
    areaW = window.size.x.float32 - Margin * 2
    areaH = window.size.y.float32 - controlsBottom - Margin
    areaSize = vec2(areaW, areaH)
    pad = layoutPadding
    stackDir = direction.toStackDirection()
    n = numBoxes.int
    bs = boxSize

  # Draw area background.
  sk.drawRect(areaPos, areaSize, AreaBgColor)

  # Push a layout inside the area with padding applied.
  sk.pushLayout(areaPos + vec2(pad, pad), areaSize - vec2(pad * 2, pad * 2), stackDir)
  let savedSpacing = sk.theme.spacing
  sk.theme.spacing = layoutSpacing.int

  for i in 0 ..< n:
    let color = BoxColors[i mod BoxColors.len]
    let drawPos =
      case stackDir:
      of TopToBottom, LeftToRight:
        sk.at
      of BottomToTop:
        sk.at - vec2(0, bs)
      of RightToLeft:
        sk.at - vec2(bs, 0)
      of RightTopToBottom:
        sk.at - vec2(bs, 0)
      of BottomLeftToRight:
        sk.at - vec2(0, bs)
      of RightBottomToTop, BottomRightToLeft:
        sk.at - vec2(bs, bs)
    sk.drawRect(drawPos, vec2(bs, bs), color)
    discard sk.drawText(
      "Default",
      $(i + 1),
      drawPos + vec2(bs * 0.5 - 5, bs * 0.5 - 9),
      rgbx(255, 255, 255, 255)
    )
    sk.advance(vec2(bs, bs))

  sk.theme.spacing = savedSpacing
  sk.popLayout()

  # Frame time.
  let ms = sk.avgFrameTime * 1000
  sk.at = vec2(sk.size.x - 250, Margin)
  text(&"frame time: {ms:>7.3f}ms")

  sk.endUi()
  window.swapBuffers()

when defined(emscripten):
  window.run()
else:
  while not window.closeRequested:
    pollEvents()
