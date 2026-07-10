## Demonstrates element wrapping and scrolling in a resizable frame.

import
  std/[strformat],
  opengl, windy, bumpy, vmath, chroma,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("tests/data/", "tests/data/")
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("tests/dist/atlas.png")

let window = newWindow(
  "Flow Grid Example",
  ivec2(900, 600),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

const
  BackgroundColor = parseHtmlColor("#1a1a2e").rgbx
  NumItems = 50
  Margin = 20.0f
  SliderLabelWidth = 60.0f
  SliderWidth = 300.0f

let sk = newSilky(window, "tests/dist/atlas.png")

# Track which items have been clicked.
var
  clickedItems: array[NumItems, bool]
  frameWidth = 400.0f
  frameHeight = 300.0f

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(BackgroundColor)

  ui:
    text "title":
      box Margin, Margin, 700, 24
      characters "Flow Grid Example - Resize the frame to see elements reflow"

    text "blurb":
      box Margin, 50, 700, 24
      characters "Drag the sliders to resize the frame. Elements wrap automatically."

    text "width label":
      box Margin, 80, SliderLabelWidth, 24
      characters "Width:"
    group "width slider":
      box Margin + SliderLabelWidth, 80, SliderWidth, 24
      scrubber("width", frameWidth, 200.0, 600.0)

    text "height label":
      box Margin, 110, SliderLabelWidth, 24
      characters "Height:"
    group "height slider":
      box Margin + SliderLabelWidth, 110, SliderWidth, 24
      scrubber("height", frameHeight, 100.0, 500.0)

    let
      framePos = vec2(Margin, 150)
      frameSize = vec2(frameWidth, frameHeight)

    frame "flowFrame":
      box framePos.x, framePos.y, frameSize.x, frameSize.y
      let
        buttonWidth = 32.0f + sk.padding
        margin = 12.0f
        scrollbarWidth = 16.0f
        startX = sk.at.x

      for i in 0 ..< NumItems:
        # Check if we need to wrap to the next line, accounting for scrollbar.
        if sk.at.x + buttonWidth > sk.pos.x + sk.size.x - margin - scrollbarWidth:
          sk.at.x = startX
          sk.at.y += 32 + margin

        let icon =
          if i mod 2 == 0:
            "heart"
          else:
            "cloud"
        iconButton(icon):
          clickedItems[i] = not clickedItems[i]
          echo "Clicked item ", i

    var clickCount = 0
    for i in 0 ..< NumItems:
      if clickedItems[i]:
        inc clickCount

    text "status label":
      box framePos.x + frameWidth + 20, 150, 200, 24
      characters "Click status:"
    text "status count":
      box framePos.x + frameWidth + 20, 174, 200, 24
      characters &"{clickCount} / {NumItems} items clicked"

    let ms = sk.avgFrameTime * 1000
    text "frame time":
      box sk.size.x - 250, 20, 230, 22
      characters &"frame time: {ms:>7.3f}ms"

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
