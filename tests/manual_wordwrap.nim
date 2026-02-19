## Demonstrates word wrapping in text rendering.
##
## Word wrapping breaks text at word boundaries when it exceeds the specified
## maximum width. Drag the slider to adjust the wrapping width and compare
## the wrapped text against the non-wrapped version.

import
  std/[strformat],
  opengl, windy, bumpy, vmath, chroma,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("tests/data/", "tests/data/")
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18.0, subpixelSteps = 10)
builder.write("tests/dist/atlas.png", "tests/dist/atlas.json")

let window = newWindow(
  "Word Wrap Example",
  ivec2(900, 800),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

const
  BackgroundColor = parseHtmlColor("#1a1a2e").rgbx
  SampleText = """Hello!
Short line.
A slightly longer line to test medium wrapping behavior.
The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs. How vexingly quick daft zebras jump. The five boxing wizards jump quickly.
OK.
Word wrap splits text at word boundaries when it would exceed the maximum width.
Hi.
Supercalifragilisticexpialidocious is a very long word that tests character-level fallback wrapping.
Done."""

let sk = newSilky("tests/dist/atlas.png", "tests/dist/atlas.json")

var
  wrapWidth = 300.0f
  wordWrapOn = true
  clipOn = true

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(BackgroundColor)

  const
    Margin = 20.0f
    BoxHeight = 600.0f

  sk.layout.at = vec2(Margin, Margin)

  # Title.
  h1text("Word Wrap Example")

  # Width slider.
  scrubber("width", wrapWidth, 0.0, 800.0, &"{wrapWidth:.0f} px")

  # Checkboxes.
  checkBox("Word wrap", wordWrapOn)
  checkBox("Clip", clipOn)

  # Word-wrapped text with background rectangle.
  let wrappedPos = sk.layout.at
  sk.drawRect(wrappedPos, vec2(wrapWidth, BoxHeight), rgbx(40, 40, 60, 255))
  sk.drawRect(vec2(wrappedPos.x + wrapWidth, wrappedPos.y), vec2(1, BoxHeight), rgbx(100, 100, 200, 200))
  discard sk.drawText(
    sk.textStyle, SampleText,
    wrappedPos,
    sk.theme.textColor,
    maxWidth = wrapWidth,
    maxHeight = BoxHeight,
    clip = clipOn,
    wordWrap = wordWrapOn
  )

  # Frame time display.
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
