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
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Subpixel", 18.0, subpixelSteps = 10)
builder.write("tests/dist/atlas.png", "tests/dist/atlas.json")

let window = newWindow(
  "Subpixel Text Example",
  ivec2(800, 450),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

const
  BackgroundColor = parseHtmlColor("#1a1a2e").rgbx

let sk = newSilky("tests/dist/atlas.png", "tests/dist/atlas.json")

var textOffset = 0.0f

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(BackgroundColor)

  const
    Margin = 30.0f
    SliderWidth = 600.0f

  # Title.
  sk.layout.at = vec2(Margin, Margin)
  text("Subpixel Text Positioning")

  # Explanation.
  sk.layout.at = vec2(Margin, 70)
  text("Drag the slider to move the text. Compare regular vs subpixel rendering.")

  # Big slider.
  sk.layout.at = vec2(Margin, 110)
  text(&"Offset: {textOffset:>6.2f} px")
  sk.pushLayout(vec2(Margin, 140), vec2(SliderWidth, 32))
  scrubber("offset", textOffset, 0.0, 20.0)
  sk.popLayout()

  # Pixel-snapped font (snaps to integer pixels).
  sk.layout.at = vec2(Margin, 200)
  text("Pixel-snapped:")
  sk.layout.at = vec2(Margin + textOffset, 225)
  sk.textStyle = "Regular"
  text("The quick brown fox jumps over the lazy dog.")

  # Bilinear filtered (GPU interpolation causes blur).
  sk.layout.at = vec2(Margin, 260)
  sk.textStyle = "Default"
  text("Bilinear filtered:")
  sk.drawImage("text", vec2(Margin + textOffset, 285))

  # Subpixel rendered font.
  sk.layout.at = vec2(Margin, 320)
  text("Subpixel rendered:")
  sk.layout.at = vec2(Margin + textOffset, 345)
  sk.textStyle = "Subpixel"
  text("The quick brown fox jumps over the lazy dog.")

  # Reset to default font.
  sk.textStyle = "Default"

  # Frame time display.
  let ms = sk.avgFrameTime * 1000
  sk.layout.at = vec2(sk.size.x - 200, Margin)
  text(&"frame time: {ms:>7.3f}ms")

  sk.endUi()
  window.swapBuffers()

when defined(emscripten):
  window.run()
else:
  while not window.closeRequested:
    pollEvents()
