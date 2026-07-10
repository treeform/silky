## Demonstrates subpixel text rendering.
##
## Subpixel rendering pre-renders multiple versions of each glyph at fractional
## pixel offsets. When drawing text at non-integer positions, the correct glyph
## variant is selected, resulting in smoother text positioning without blur.
## Compare the regular font (top) with the subpixel font (bottom).

import
  std/[strformat],
  opengl, windy, bumpy, vmath, chroma,
  silky

let builder = newAtlasBuilder(2048, 4)
builder.addDir("tests/data/", "tests/data/")
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Regular", 18.0)
builder.addFont(
  "tests/data/IBMPlexSans-Regular.ttf",
  "Subpixel",
  18.0,
  subpixelSteps = 10
)
builder.write("tests/dist/atlas.png")

let window = newWindow(
  "Subpixel Text Example",
  ivec2(800, 450),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

const
  BackgroundColor = parseHtmlColor("#1a1a2e").rgbx
  Margin = 30.0f
  SliderWidth = 600.0f

let sk = newSilky(window, "tests/dist/atlas.png")

var textOffset = 0.0f

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(BackgroundColor)

  ui:
    text "title":
      box Margin, Margin, 500, 24
      characters "Subpixel Text Positioning"

    text "blurb":
      box Margin, 70, 740, 24
      characters "Drag the slider to move the text. Compare regular vs subpixel rendering."

    text "offset label":
      box Margin, 110, 300, 24
      characters &"Offset: {textOffset:>6.2f} px"

    group "slider":
      box Margin, 140, SliderWidth, 32
      scrubber("offset", textOffset, 0.0, 20.0)

    text "snapped label":
      box Margin, 200, 300, 24
      characters "Pixel-snapped:"
    text "snapped sample":
      box Margin + textOffset, 225, 700, 24
      characters "The quick brown fox jumps over the lazy dog."
      font "Regular"

    text "bilinear label":
      box Margin, 260, 300, 24
      characters "Bilinear filtered:"
    sk.drawImage("text", vec2(Margin + textOffset, 285))

    text "subpixel label":
      box Margin, 320, 300, 24
      characters "Subpixel rendered:"
    text "subpixel sample":
      box Margin + textOffset, 345, 700, 24
      characters "The quick brown fox jumps over the lazy dog."
      font "Subpixel"

    let ms = sk.avgFrameTime * 1000
    text "frame time":
      box sk.size.x - 200, Margin, 180, 22
      characters &"frame time: {ms:>7.3f}ms"

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
