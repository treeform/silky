## Demonstrates text alignment inside a bounded area.
## Use the radio buttons to change horizontal and vertical alignment.
## The sample text in the box below reflows to match the selection.

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
  "Text Alignment",
  ivec2(800, 600),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

const
  BackgroundColor = parseHtmlColor("#1a1a2e").rgbx
  AreaBgColor = parseHtmlColor("#2a2a3e").rgbx
  SampleText = "The quick brown fox jumps over the lazy dog."
  MultiLineText = "Left or right,\ncenter if you like.\nThree lines of text."

let sk = newSilky("tests/dist/atlas.png", "tests/dist/atlas.json")

var
  hAlignVal = 0
  vAlignVal = 0

proc toHAlign(v: int): HorizontalAlignment =
  ## Convert radio index to horizontal alignment.
  case v:
  of 0: LeftAlign
  of 1: CenterAlign
  of 2: RightAlign
  else: LeftAlign

proc toVAlign(v: int): VerticalAlignment =
  ## Convert radio index to vertical alignment.
  case v:
  of 0: TopAlign
  of 1: MiddleAlign
  of 2: BottomAlign
  else: TopAlign

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(BackgroundColor)

  const Margin = 20.0f

  # Centered title.
  let titleSize = sk.getTextSize("H1", "Text Alignment")
  discard sk.drawText(
    "H1", "Text Alignment",
    vec2(Margin, Margin),
    sk.theme.textH1Color,
    window.size.x.float32 - Margin * 2,
    hAlign = CenterAlign
  )

  # Horizontal alignment radio buttons.
  sk.at = vec2(Margin, Margin + titleSize.y + 16)
  text("Horizontal:")
  group(vec2(0, 0), LeftToRight):
    radioButton("Left", hAlignVal, 0)
    radioButton("Center", hAlignVal, 1)
    radioButton("Right", hAlignVal, 2)

  # Vertical alignment radio buttons.
  text("Vertical:")
  group(vec2(0, 0), LeftToRight):
    radioButton("Top", vAlignVal, 0)
    radioButton("Middle", vAlignVal, 1)
    radioButton("Bottom", vAlignVal, 2)

  # Text display area.
  let
    controlsBottom = sk.at.y + 8
    areaPos = vec2(Margin, controlsBottom)
    areaW = window.size.x.float32 - Margin * 2
    areaH = window.size.y.float32 - controlsBottom - Margin
    areaSize = vec2(areaW, areaH)
    ha = hAlignVal.toHAlign()
    va = vAlignVal.toVAlign()

  # Draw area background.
  sk.drawRect(areaPos, areaSize, AreaBgColor)

  # Single line sample.
  discard sk.drawText(
    "Default", SampleText,
    areaPos + vec2(12, 12),
    sk.theme.textColor,
    areaW - 24, (areaH - 24) * 0.4,
    hAlign = ha, vAlign = va
  )

  # Divider line.
  let divY = areaPos.y + areaH * 0.45
  sk.drawRect(vec2(areaPos.x + 8, divY), vec2(areaW - 16, 1), rgbx(100, 100, 120, 255))

  # Multi-line sample.
  discard sk.drawText(
    "Default", MultiLineText,
    vec2(areaPos.x + 12, divY + 12),
    sk.theme.textColor,
    areaW - 24, areaH * 0.55 - 24,
    hAlign = ha, vAlign = va
  )

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
