## Demonstrates layout stacking directions and anchoring with adjustable
## padding, spacing, and number of boxes. Use the controls at the top to tweak
## values, pick a stacking direction and anchor from the dropdowns. The colored
## boxes below respond to every change in real time.

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
  BoxSizes = [
    vec2(48, 48),
    vec2(64, 32),
    vec2(32, 64),
    vec2(80, 40),
    vec2(40, 80),
    vec2(56, 56),
    vec2(72, 36),
    vec2(36, 72),
    vec2(60, 44),
    vec2(44, 60),
  ]

let sk = newSilky("tests/dist/atlas.png", "tests/dist/atlas.json")

var
  layoutPadding = 16.0f
  layoutSpacing = 8.0f
  numBoxes = 5.0f
  directionLabel = "Top to Bottom"
  anchorLabel = "Left"

const
  DirectionLabels = ["Top to Bottom", "Bottom to Top", "Left to Right", "Right to Left"]
  AnchorLabels = ["Left", "Right", "Top", "Bottom"]

proc toStackDirection(s: string): StackDirection =
  ## Convert a direction label to a StackDirection enum.
  case s:
  of "Top to Bottom": TopToBottom
  of "Bottom to Top": BottomToTop
  of "Left to Right": LeftToRight
  of "Right to Left": RightToLeft
  else: TopToBottom

proc toAnchor(s: string): Anchor =
  ## Convert an anchor label to an Anchor enum.
  case s:
  of "Left": AnchorLeft
  of "Right": AnchorRight
  of "Top": AnchorTop
  of "Bottom": AnchorBottom
  else: AnchorLeft

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
  text("Direction:")
  dropDown(directionLabel, DirectionLabels)
  text("Anchor:")
  dropDown(anchorLabel, AnchorLabels)

  # Layout area.
  let
    controlsBottom = sk.at.y + 8
    areaPos = vec2(Margin, controlsBottom)
    areaW = window.size.x.float32 - Margin * 2
    areaH = window.size.y.float32 - controlsBottom - Margin
    areaSize = vec2(areaW, areaH)
    pad = layoutPadding
    stackDir = directionLabel.toStackDirection()
    stackAnc = anchorLabel.toAnchor()
    n = numBoxes.int

  # Draw area background.
  sk.drawRect(areaPos, areaSize, AreaBgColor)

  # Push a layout inside the area with padding applied.
  sk.pushLayout(areaPos + vec2(pad, pad), areaSize - vec2(pad * 2, pad * 2), stackDir, stackAnc)
  let savedSpacing = sk.theme.spacing
  sk.theme.spacing = layoutSpacing.int

  for i in 0 ..< n:
    let color = BoxColors[i mod BoxColors.len]
    let sz = BoxSizes[i mod BoxSizes.len]
    rectangle(sz, color)

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
