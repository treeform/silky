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
builder.addFont(
  "tests/data/IBMPlexSans-Regular.ttf",
  "Default",
  18.0,
  subpixelSteps = 10
)
builder.write("tests/dist/atlas.png")

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
  Margin = 20.0f
  BoxHeight = 600.0f

let sk = newSilky(window, "tests/dist/atlas.png")

var
  wrapWidth = 300.0f
  wordWrapOn = true
  clipOn = true

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(BackgroundColor)

  ui:
    text "title":
      box Margin, Margin, 500, 40
      characters "Word Wrap Example"
      font "H1"
      tint sk.theme.textH1Color

    group "controls":
      box Margin, 70, 500, 120
      layout TopToBottom
      itemSpacing 8
      scrubber("width", wrapWidth, 0.0, 800.0, &"{wrapWidth:.0f} px")
      checkBox "Word wrap", wordWrapOn
      checkBox "Clip", clipOn

    # Word-wrapped text with background rectangle.
    let wrappedPos = vec2(Margin, 210)
    sk.drawRect(wrappedPos, vec2(wrapWidth, BoxHeight), rgbx(40, 40, 60, 255))
    sk.drawRect(
      vec2(wrappedPos.x + wrapWidth, wrappedPos.y),
      vec2(1, BoxHeight),
      rgbx(100, 100, 200, 200)
    )
    discard sk.drawText(
      sk.textStyle,
      SampleText,
      wrappedPos,
      sk.theme.textColor,
      maxWidth = wrapWidth,
      maxHeight = BoxHeight,
      clip = clipOn,
      wordWrap = wordWrapOn
    )

    let ms = sk.avgFrameTime * 1000
    text "frame time":
      box sk.size.x - 250, Margin, 230, 22
      characters &"frame time: {ms:>7.3f}ms"

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
