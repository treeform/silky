## Demonstrates text alignment inside a bounded area.
## Use the radio buttons to change horizontal and vertical alignment.
## The sample text in the box below reflows to match the selection.

import
  std/[strformat],
  opengl, windy, bumpy, vmath, chroma, pixie,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("tests/data/", "tests/data/")
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont(
  "tests/data/IBMPlexSans-Regular.ttf",
  "Default",
  18.0,
  subpixelSteps = 10
)
builder.write("tests/dist/atlas.png")

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
  Margin = 20.0f

let sk = newSilky(window, "tests/dist/atlas.png")

var
  hAlignVal = 0
  vAlignVal = 0

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(BackgroundColor)

  ui:
    text "title":
      box Margin, Margin, window.size.x.float32 - Margin * 2, 40
      characters "Text Alignment"
      font "H1"
      tint sk.theme.textH1Color
      textAlign CenterAlign, TopAlign

    group "controls":
      box Margin, 70, window.size.x.float32 - Margin * 2, 90
      layout TopToBottom
      itemSpacing 8
      text "h label":
        characters "Horizontal:"
      group "h radios":
        box 400, 28
        layout LeftToRight
        itemSpacing 12
        radioButton "Left", hAlignVal, 0
        radioButton "Center", hAlignVal, 1
        radioButton "Right", hAlignVal, 2
      text "v label":
        characters "Vertical:"
      group "v radios":
        box 400, 28
        layout LeftToRight
        itemSpacing 12
        radioButton "Top", vAlignVal, 0
        radioButton "Middle", vAlignVal, 1
        radioButton "Bottom", vAlignVal, 2

    let
      controlsBottom = 180.0f
      areaPos = vec2(Margin, controlsBottom)
      areaW = window.size.x.float32 - Margin * 2
      areaH = window.size.y.float32 - controlsBottom - Margin
      areaSize = vec2(areaW, areaH)
      ha =
        case hAlignVal:
        of 0:
          LeftAlign
        of 1:
          CenterAlign
        of 2:
          RightAlign
        else:
          LeftAlign
      va =
        case vAlignVal:
        of 0:
          TopAlign
        of 1:
          MiddleAlign
        of 2:
          BottomAlign
        else:
          TopAlign

    sk.drawRect(areaPos, areaSize, AreaBgColor)

    discard sk.drawText(
      "Default",
      SampleText,
      areaPos + vec2(12, 12),
      sk.theme.textColor,
      areaW - 24,
      (areaH - 24) * 0.4,
      hAlign = ha,
      vAlign = va
    )

    let divY = areaPos.y + areaH * 0.45
    sk.drawRect(
      vec2(areaPos.x + 8, divY),
      vec2(areaW - 16, 1),
      rgbx(100, 100, 120, 255)
    )

    discard sk.drawText(
      "Default",
      MultiLineText,
      vec2(areaPos.x + 12, divY + 12),
      sk.theme.textColor,
      areaW - 24,
      areaH * 0.55 - 24,
      hAlign = ha,
      vAlign = va
    )

    let ms = sk.avgFrameTime * 1000
    text "frame time":
      box sk.size.x - 250, Margin, 230, 22
      characters &"frame time: {ms:>7.3f}ms"

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
