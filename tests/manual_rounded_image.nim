## Manual test for drawRoundedImage with adjustable radius sliders.
## Pass --screenshot to render one frame to tmp/rounded_screenshot.png and exit.

import
  std/[strformat, os],
  opengl, windy, vmath, chroma, pixie,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("tests/data/", "tests/data/")
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("tests/dist/atlas.png")

let window = newWindow(
  "Rounded Image Test",
  ivec2(900, 700),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

let sk = newSilky(window, "tests/dist/atlas.png")

var
  cornerRadius = 32.0f
  drawWidth = 300.0f
  drawHeight = 200.0f

proc drawFrame() =
  sk.beginUI(window, window.size)
  sk.clearScreen(rgbx(40, 40, 40, 255))

  const
    Margin = 20.0f
    LabelWidth = 80.0f
    SliderWidth = 300.0f

  ui:
    text "title":
      box Margin, Margin, 400, 24
      characters "Rounded Image Manual Test"

    let refX = Margin + LabelWidth + SliderWidth + Margin
    text "original label":
      box refX, 55, 200, 24
      characters "Original:"
    sk.drawImage("debug.9patch", vec2(refX, 80))

    group "controls":
      box Margin, 55, LabelWidth + SliderWidth, 140
      layout TopToBottom
      itemSpacing 12

      group "width row":
        box LabelWidth + SliderWidth, 24
        layout LeftToRight
        text "width label":
          box LabelWidth, 24
          characters "Width:"
        group "width slider":
          box SliderWidth, 24
          scrubber("width", drawWidth, 32.0, 600.0, &"{drawWidth:.0f}")

      group "height row":
        box LabelWidth + SliderWidth, 24
        layout LeftToRight
        text "height label":
          box LabelWidth, 24
          characters "Height:"
        group "height slider":
          box SliderWidth, 24
          scrubber("height", drawHeight, 32.0, 600.0, &"{drawHeight:.0f}")

      group "radius row":
        box LabelWidth + SliderWidth, 24
        layout LeftToRight
        text "radius label":
          box LabelWidth, 24
          characters "Radius:"
        group "radius slider":
          box SliderWidth, 24
          scrubber("radius", cornerRadius, 0.0, 300.0, &"{cornerRadius:.0f}")

    # Draw the rounded image below the controls.
    sk.drawRoundedImage(
      "debug.9patch",
      vec2(Margin, 220),
      vec2(drawWidth, drawHeight),
      cornerRadius
    )

    let ms = sk.avgFrameTime * 1000
    text "frame time":
      box sk.size.x - 250, 20, 230, 22
      characters &"frame time: {ms:>7.3f}ms"

  sk.endUi()

window.onFrame = proc() =
  drawFrame()
  window.swapBuffers()

if "--screenshot" in commandLineParams():
  pollEvents()
  drawFrame()
  let fb = window.size
  var pixels = newSeq[uint8](fb.x * fb.y * 4)
  glPixelStorei(GL_PACK_ALIGNMENT, 1)
  glReadPixels(
    0, 0, fb.x, fb.y,
    GL_RGBA, GL_UNSIGNED_BYTE,
    addr pixels[0]
  )
  let shot = newImage(fb.x, fb.y)
  for y in 0 ..< fb.y.int:
    for x in 0 ..< fb.x.int:
      let i = ((fb.y.int - 1 - y) * fb.x.int + x) * 4
      shot.data[y * fb.x.int + x] =
        rgbx(pixels[i], pixels[i + 1], pixels[i + 2], 255)
  shot.writeFile("tmp/rounded_screenshot.png")
  echo "Wrote tmp/rounded_screenshot.png"
  quit(0)

while not window.closeRequested:
  pollEvents()
