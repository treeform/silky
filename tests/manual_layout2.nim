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
  directionVal = 2
  anchorVal = 2
  step = 0.0f

  debugStep = 0

const
  Directions = [TopToBottom, BottomToTop, LeftToRight, RightToLeft]
  Anchors = [AnchorLeft, AnchorRight, AnchorTop, AnchorBottom]

proc isVertical(d: int): bool =
  ## Vertical directions pair with Left/Right anchors.
  d <= 1

proc isHorizontal(d: int): bool =
  ## Horizontal directions pair with Top/Bottom anchors.
  d >= 2

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(BackgroundColor)

  const Margin = 20.0f

  sk.layout.at = vec2(Margin, Margin)

  # Title.
  h1text("Layout Test")

  # Controls.
  scrubber("padding", layoutPadding, 0.0, 60.0, &"Padding: {layoutPadding:0.1f}")
  scrubber("spacing", layoutSpacing, 0.0, 40.0, &"Spacing: {layoutSpacing:0.1f}")
  scrubber("numBoxes", numBoxes, 1.0, 10.0, &"Boxes: {numBoxes:0.1f}")
  scrubber("step", step, 0.0, 20.0, &"Step: {int(step)}")


  let prevDir = directionVal
  text("Direction:")
  group(vec2(0, 0), LeftToRight):
    radioButton("Top to Bottom", directionVal, 0)
    radioButton("Bottom to Top", directionVal, 1)
    radioButton("Left to Right", directionVal, 2)
    radioButton("Right to Left", directionVal, 3)

  # Auto-fix anchor when switching between vertical and horizontal.
  if directionVal != prevDir:
    if directionVal.isVertical and anchorVal >= 2:
      anchorVal = 0
    elif directionVal.isHorizontal and anchorVal <= 1:
      anchorVal = 2

  let vertical = directionVal.isVertical
  text("Anchor:")
  group(vec2(0, 0), LeftToRight):
    radioButton("Left", anchorVal, 0, vertical)
    radioButton("Right", anchorVal, 1, vertical)
    radioButton("Top", anchorVal, 2, not vertical)
    radioButton("Bottom", anchorVal, 3, not vertical)

  # Layout area.
  let
    controlsBottom = sk.layout.at.y + 8
    areaPos = vec2(Margin, controlsBottom)
    areaW = window.size.x.float32 - Margin * 2
    areaH = window.size.y.float32 - controlsBottom - Margin
    areaSize = vec2(areaW, areaH)
    pad = layoutPadding
    stackDir = Directions[directionVal]
    stackAnc = Anchors[anchorVal]
    n = numBoxes.int

  sk.pushTheme()
  sk.theme.spacing = 0 #layoutSpacing.int
  sk.theme.padding = 0 #layoutPadding.int

  let padding = vec2(layoutPadding)
  let spacing = vec2(layoutSpacing)


  #frame("layoutArea", areaPos, areaSize):
  block:
    sk.layout.num = 0

    # group(vec2(0, 0), stackDir, stackAnc):
    #   for i in 0 ..< n:
    #     let color = BoxColors[i mod BoxColors.len]
    #     let sz = BoxSizes[i mod BoxSizes.len]
    #     rectangle(sz, color, $(i + 1))

    var dr = vec2(0, 0) # Direction vector
    var pd = vec2(0, 0) # Padding direction vector
    var si = vec2(0, 0) # Size importance vector

    case stackDir:
    of TopToBottom:
      dr = vec2(0, 1)
      case stackAnc:
      of AnchorLeft:
        si = vec2(0, 0)
        pd = vec2(1, 1)
      of AnchorRight:
        si = vec2(1, 0)
        pd = vec2(-1, 1)
      else:
        discard
    of BottomToTop:
      dr = vec2(0, -1)
      case stackAnc:
      of AnchorLeft:
        si = vec2(0, 1)
        pd = vec2(1, -1)
      of AnchorRight:
        si = vec2(1, 1)
        pd = vec2(-1, -1)
      else:
        discard
    of LeftToRight:
      dr = vec2(1, 0)
      case stackAnc:
      of AnchorTop:
        si = vec2(0, 0)
        pd = vec2(1, 1)
      of AnchorBottom:
        si = vec2(0, 1)
        pd = vec2(1, -1)
      else:
        discard
    of RightToLeft:
      dr = vec2(-1, 0)
      case stackAnc:
      of AnchorTop:
        si = vec2(1, 0)
        pd = vec2(-1, 1)
      of AnchorBottom:
        si = vec2(1, 1)
        pd = vec2(-1, -1)
      else:
        discard

    var currentStep = 0

    #sk.pushLayout(areaPos, areaSize, stackDir, stackAnc)

    sk.layout.stretchMax = sk.layout.at
    sk.layout.stretchMin = sk.layout.at

    sk.drawRect(sk.layout.at, areaSize, rgbx(10, 10, 10, 10))

    proc drawStep() =
      if currentStep == step.int:
        sk.drawRect(sk.layout.at - vec2(3, 3), vec2(6, 6), rgbx(255, 0, 0, 255))
        sk.drawRect(sk.layout.stretchMin, sk.layout.stretchMax - sk.layout.stretchMin, rgbx(60, 60, 60, 60))
      if step.int != debugStep:
        debugStep = step.int
        echo "step: ", currentStep
        echo "at: ", sk.layout.at
        echo "stretchMin: ", sk.layout.stretchMin
        echo "stretchMax: ", sk.layout.stretchMax

      inc currentStep

    drawStep()

    # Apply Anchor.
    sk.layout.at += areaSize * si
    sk.layout.stretchMin = sk.layout.at
    sk.layout.stretchMax = sk.layout.at

    drawStep()

    # Apply Padding.
    sk.layout.at += padding * pd
    sk.layout.stretchMin = min(sk.layout.stretchMin, sk.layout.at + padding * pd)
    sk.layout.stretchMax = max(sk.layout.stretchMax, sk.layout.at + padding * pd)

    drawStep()

    for i in 0 ..< n:

      if sk.layout.num > 0:
        # Apply Spacing.
        sk.layout.at += spacing * dr
        sk.layout.stretchMin = min(sk.layout.stretchMin, sk.layout.at + spacing * pd)
        sk.layout.stretchMax = max(sk.layout.stretchMax, sk.layout.at + spacing * pd)

        drawStep()

      var color = BoxColors[i]
      color.a = 128
      let size = BoxSizes[i]
      # Adjust the widget position.
      let pos = sk.layout.at + size * si * pd
      sk.drawRect(pos, size, color)
      let label = $(i + 1)
      discard sk.drawText(
        sk.textStyle, label, pos, sk.theme.textColor,
        size.x, size.y,
        hAlign = CenterAlign, vAlign = MiddleAlign
      )

      # Advance to next widget.
      sk.layout.stretchMin = min(sk.layout.stretchMin, sk.layout.at + size * pd + padding * pd)
      sk.layout.stretchMax = max(sk.layout.stretchMax, sk.layout.at + size * pd + padding * pd)
      sk.layout.at += size * dr
      inc sk.layout.num

      drawStep()

    #sk.popLayout()


  sk.popTheme()

  # Frame time.
  let ms = sk.avgFrameTime * 1000
  sk.layout.at = vec2(sk.size.x - 250, Margin)
  text(&"frame time: {ms:>7.3f}ms")

  sk.endUi()
  window.swapBuffers()

when defined(emscripten):
  window.run()
else:
  while not window.closeRequested:
    pollEvents()
